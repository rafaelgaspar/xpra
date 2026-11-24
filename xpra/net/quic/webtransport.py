# This file is part of Xpra.
# Copyright (C) 2022 Antoine Martin <antoine@xpra.org>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

from queue import SimpleQueue
from typing import Any
from collections.abc import Callable

from aioquic.h3.events import (
    DatagramReceived,
    DataReceived,
    H3Event,
    WebTransportStreamDataReceived,
)
from aioquic.buffer import Buffer, BufferReadError
from aioquic.quic.packet import QuicErrorCode

from xpra.net.common import pretty_socket
from xpra.net.quic.connection import XpraQuicConnection, HttpConnection
from xpra.net.quic.common import SERVER_NAME, http_date
from xpra.log import Logger

log = Logger("quic")

# Capsule types on the WebTransport session (CONNECT) stream,
# draft-ietf-webtrans-http3 and RFC 9297 (HTTP Datagrams and the Capsule Protocol):
CLOSE_WEBTRANSPORT_SESSION = 0x2843
DRAIN_WEBTRANSPORT_SESSION = 0x78ae

# every xpra packet starts with this header byte:
XPRA_PACKET_HEADER = ord("P")


def is_grease(capsule_type: int) -> bool:
    # reserved capsule types, RFC 9297 section 5.4:
    return capsule_type >= 0x17 and (capsule_type - 0x17) % 0x29 == 0


def parse_capsules(data: bytes) -> tuple[list[tuple[int, bytes]], bytes]:
    """
    Split `data` into complete (type, value) capsules,
    returns the capsules and any trailing bytes of an incomplete capsule.
    """
    capsules: list[tuple[int, bytes]] = []
    pos = 0
    while pos < len(data):
        buf = Buffer(data=data[pos:])
        try:
            capsule_type = buf.pull_uint_var()
            length = buf.pull_uint_var()
            value = buf.pull_bytes(length)
        except BufferReadError:
            break
        capsules.append((capsule_type, value))
        pos += buf.tell()
    return capsules, data[pos:]


class ServerWebTransportConnection(XpraQuicConnection):
    def __init__(self, connection: HttpConnection, scope: dict, stream_id: int, transmit: Callable[[], None]):
        super().__init__(connection, stream_id, transmit, "", 0, "webtransport")
        self.http_event_queue: SimpleQueue[DataReceived] = SimpleQueue()
        # self.read_datagram_queue = SimpleQueue()
        # incoming datagrams are ignored (see `http_event_received`):
        self.datagram = False
        self.scope = scope
        # the CONNECT stream, `stream_id` moves to the first WebTransport stream the peer opens:
        self.session_id = stream_id
        # what the peer sends on the session stream:
        # xpra's own client sends its packets there, browsers only send capsules
        # (ie: GREASE, CLOSE_WEBTRANSPORT_SESSION) and use WebTransport streams for the payload.
        # `None` until we have seen the first byte:
        self.session_payload: bool | None = None
        self.capsule_buffer = b""

    def __repr__(self):
        try:
            return f"QuicConnection({pretty_socket(self.endpoint)}, {self.stream_id})"
        except AttributeError:
            return f"WebTransportHandler<{self.stream_id}>"

    def http_event_received(self, event: H3Event) -> None:
        log("wt.http_event_received(%s) closed=%s, accepted=%s", event, self.closed, self.accepted)
        if self.closed:
            return
        if self.accepted:
            if isinstance(event, DatagramReceived):
                # self.read_datagram_queue.put(event.data)
                log("datagram ignored")
            elif isinstance(event, DataReceived):
                self.session_data_received(event.data)
            elif isinstance(event, WebTransportStreamDataReceived):
                if event.stream_id != self.stream_id:
                    log(f"switching to stream_id={event.stream_id}")
                    self.stream_id = event.stream_id
                self.read_queue.put(event.data)
        else:
            self.accepted = True
            self.send_accept()
            self.transmit()

    def session_data_received(self, data: bytes) -> None:
        if not data:
            return
        if self.session_payload is None:
            self.session_payload = data[0] == XPRA_PACKET_HEADER
            log("webtransport session stream carries %s", "xpra packets" if self.session_payload else "capsules")
        if self.session_payload:
            self.read_queue.put(data)
            return
        capsules, self.capsule_buffer = parse_capsules(self.capsule_buffer + data)
        for capsule_type, value in capsules:
            self.capsule_received(capsule_type, value)

    def capsule_received(self, capsule_type: int, value: bytes) -> None:
        if capsule_type == CLOSE_WEBTRANSPORT_SESSION:
            code = int.from_bytes(value[:4], "big") if len(value) >= 4 else 0
            reason = value[4:].decode("utf8", errors="replace")
            log("webtransport session closed by peer: code=%i, reason=%r", code, reason)
            self.read_queue.put(b"")
            return
        if capsule_type == DRAIN_WEBTRANSPORT_SESSION:
            log("webtransport session drain requested by peer")
            return
        log("ignoring %s capsule type %#x (%i bytes)",
            "GREASE" if is_grease(capsule_type) else "unknown", capsule_type, len(value))

    def do_write(self, stream_id: int, data: bytes) -> None:
        if stream_id == self.session_id:
            super().do_write(stream_id, data)
            return
        # WebTransport streams carry raw bytes, not HTTP/3 DATA frames,
        # and `send_data` refuses them since they never had any headers:
        self.connection._quic.send_stream_data(stream_id, data, end_stream=self.closed)
        self.output_bytecount += len(data)
        self.output_writecount += 1

    def send_accept(self) -> None:
        headers: dict[str, Any] = {
            ":status": "200",
            "server": SERVER_NAME,
            "date": http_date(),
            "sec-webtransport-http3-draft": "draft02",
        }
        assert self.stream_id == 0
        self.send_headers(self.stream_id, headers)
        self.transmit()

    def send_close(self, code=QuicErrorCode.NO_ERROR, reason="") -> None:
        if not self.accepted:
            httpcode = 200 if code == QuicErrorCode.NO_ERROR else 500
            self.send_http_close(httpcode, reason)
        super().send_close(code, reason)

    def send_http_close(self, code: int = 500, reason: str = "") -> None:
        log(f"send_http_close({code}, {reason!r})")
        self.send_headers(0, {":status": code})
        self.transmit()

    def send_datagram(self, data: bytes) -> None:
        log("send_datagram(%i bytes)", len(data))
        self.connection.send_datagram(self.stream_id, data=data)
        self.transmit()

    def read(self, n: int) -> bytes:
        log("WebTransportHandler.read(%s)", n)
        return self.read_queue.get()
