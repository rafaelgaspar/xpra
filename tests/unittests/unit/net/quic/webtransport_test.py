#!/usr/bin/env python3
# This file is part of Xpra.
# Copyright (C) 2026 Antoine Martin <antoine@xpra.org>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

"""
`ServerWebTransportConnection` against a real aioquic client, connected back to back in memory.

Browsers only send capsules on the WebTransport session (CONNECT) stream,
starting with a GREASE capsule, and carry the payload on WebTransport streams.
xpra's own client sends its packets on the session stream itself.
Both must work, and replies on a WebTransport stream must be raw stream bytes.
"""

import unittest
from queue import SimpleQueue, Empty
from unittest.mock import patch

try:
    from aioquic.buffer import encode_uint_var
    from aioquic.quic.configuration import QuicConfiguration
    from aioquic.quic.connection import QuicConnection
    from aioquic.h3.connection import H3_ALPN
    from xpra.net.quic.h3conn import XpraH3Connection
    from aioquic.h3.events import DataReceived, WebTransportStreamDataReceived
    from unit.net.quic.datagram_test import make_certificate, SyncLoop, ADDR
    HAVE_AIOQUIC = True
except ImportError:
    HAVE_AIOQUIC = False

# a GREASE capsule type (0x29 * N + 0x17), as sent by Chrome:
GREASE_TYPE = 0x2a2fc39b2d2a426
HELLO = b"P\x00\x00\x00\x00\x00\x00\x05hello"


def capsule(capsule_type: int, value: bytes) -> bytes:
    return encode_uint_var(capsule_type) + encode_uint_var(len(value)) + value


def drain(queue: SimpleQueue) -> list[bytes]:
    items = []
    while True:
        try:
            items.append(queue.get_nowait())
        except Empty:
            return items


class WebTransportPair:
    """ an aioquic client with an open WebTransport session to a `ServerWebTransportConnection` """

    def __init__(self, cert, key):
        from xpra.net.quic.webtransport import ServerWebTransportConnection
        self.now = 0.0
        cconfig = QuicConfiguration(alpn_protocols=H3_ALPN, is_client=True,
                                    max_datagram_frame_size=65536, verify_mode=0)
        sconfig = QuicConfiguration(alpn_protocols=H3_ALPN, is_client=False,
                                    max_datagram_frame_size=65536)
        sconfig.certificate = cert
        sconfig.private_key = key
        self.cquic = QuicConnection(configuration=cconfig)
        self.squic = QuicConnection(configuration=sconfig,
                                    original_destination_connection_id=self.cquic.original_destination_connection_id)
        self.chttp = XpraH3Connection(self.cquic, enable_webtransport=True)
        self.shttp = XpraH3Connection(self.squic, enable_webtransport=True)
        self.client_events = []
        self.cquic.connect(ADDR, now=self.now)
        self.settle()
        self.session_id = self.cquic.get_next_available_stream_id()
        self.server = ServerWebTransportConnection(self.shttp, {}, self.session_id, self.settle)
        self.chttp.send_headers(self.session_id, [
            (b":method", b"CONNECT"), (b":protocol", b"webtransport"), (b":scheme", b"https"),
            (b":authority", b"localhost"), (b":path", b"/"),
        ])
        self.settle()
        assert self.server.accepted

    def settle(self) -> None:
        for _ in range(200):
            self.now += 0.005
            moved = 0
            for src, dst in ((self.cquic, self.squic), (self.squic, self.cquic)):
                for data, _addr in src.datagrams_to_send(now=self.now):
                    moved += 1
                    dst.receive_datagram(data, ADDR, now=self.now)
            while (event := self.cquic.next_event()) is not None:
                self.client_events += self.chttp.handle_event(event)
            while (event := self.squic.next_event()) is not None:
                for http_event in self.shttp.handle_event(event):
                    self.server.http_event_received(http_event)
            if not moved:
                return

    def client_session_send(self, data: bytes) -> None:
        self.chttp.send_data(self.session_id, data, end_stream=False)
        self.settle()

    def client_stream_send(self, data: bytes) -> int:
        stream_id = self.chttp.create_webtransport_stream(self.session_id)
        self.cquic.send_stream_data(stream_id, data, end_stream=False)
        self.settle()
        return stream_id

    def client_received(self, event_type) -> list:
        return [(e.stream_id, e.data) for e in self.client_events if isinstance(e, event_type) and e.data]


@unittest.skipUnless(HAVE_AIOQUIC, "aioquic not available")
class WebTransportTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.cert, cls.key = make_certificate()

    def setUp(self):
        patcher = patch("xpra.net.quic.connection.get_threaded_loop", return_value=SyncLoop())
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_parse_capsules(self):
        from xpra.net.quic.webtransport import parse_capsules, is_grease
        assert is_grease(GREASE_TYPE)
        assert not is_grease(0x2843)
        data = capsule(GREASE_TYPE, b"x" * 7) + capsule(0x2843, b"\0\0\0\0bye")
        capsules, rest = parse_capsules(data[:-2])
        assert capsules == [(GREASE_TYPE, b"x" * 7)]
        assert rest == data[len(capsule(GREASE_TYPE, b"x" * 7)):-2]
        capsules, rest = parse_capsules(rest + data[-2:])
        assert capsules == [(0x2843, b"\0\0\0\0bye")]
        assert rest == b""

    def test_browser_grease_then_stream(self):
        pair = WebTransportPair(self.cert, self.key)
        # Chrome sends a GREASE capsule on the session stream before opening its stream:
        pair.client_session_send(capsule(GREASE_TYPE, b"\x9b\x2d"))
        assert drain(pair.server.read_queue) == [], "a capsule must not be read as xpra data"
        stream_id = pair.client_stream_send(HELLO)
        assert drain(pair.server.read_queue) == [HELLO]
        assert pair.server.stream_id == stream_id
        # the reply goes back on the same WebTransport stream, as raw bytes:
        pair.server.do_write(pair.server.stream_id, b"reply")
        pair.settle()
        assert pair.client_received(WebTransportStreamDataReceived) == [(stream_id, b"reply")]

    def test_browser_close_capsule(self):
        pair = WebTransportPair(self.cert, self.key)
        pair.client_stream_send(HELLO)
        drain(pair.server.read_queue)
        pair.client_session_send(capsule(0x2843, b"\0\0\0\0done"))
        assert drain(pair.server.read_queue) == [b""], "the peer closing the session must end the read loop"

    def test_xpra_client_session_payload(self):
        # xpra's own client sends its packets on the session stream:
        pair = WebTransportPair(self.cert, self.key)
        pair.client_session_send(HELLO)
        pair.client_session_send(b"more")
        assert drain(pair.server.read_queue) == [HELLO, b"more"]
        pair.server.do_write(pair.server.session_id, b"reply")
        pair.settle()
        assert pair.client_received(DataReceived) == [(pair.session_id, b"reply")]


def main():
    unittest.main()


if __name__ == '__main__':
    main()
