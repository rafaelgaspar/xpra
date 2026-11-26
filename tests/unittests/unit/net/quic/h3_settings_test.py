#!/usr/bin/env python3
# This file is part of Xpra.
# Copyright (C) 2026 Antoine Martin <antoine@xpra.org>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

"""Safari 26.4+ needs SETTINGS_WT_MAX_SESSIONS on the HTTP/3 SETTINGS frame."""

import unittest

from xpra.net.quic.h3conn import (
    SETTINGS_WEBTRANSPORT_MAX_SESSIONS,
    SETTINGS_WT_MAX_SESSIONS,
    WT_MAX_SESSIONS,
    with_wt_max_sessions,
)

try:
    from aioquic.h3.connection import Setting
    from aioquic.quic.configuration import QuicConfiguration
    from aioquic.quic.connection import QuicConnection
    from xpra.net.quic.h3conn import XpraH3Connection
    HAVE_AIOQUIC = True
except ImportError:
    HAVE_AIOQUIC = False


class WithWtMaxSessionsTest(unittest.TestCase):

    def test_advertises_both_codepoints_at_one(self):
        settings = with_wt_max_sessions({0x8: 1})
        assert settings[0x8] == 1
        assert settings[SETTINGS_WT_MAX_SESSIONS] == WT_MAX_SESSIONS == 1
        assert settings[SETTINGS_WEBTRANSPORT_MAX_SESSIONS] == 1

    def test_does_not_mutate_input(self):
        original = {0x8: 1}
        with_wt_max_sessions(original)
        assert SETTINGS_WT_MAX_SESSIONS not in original


@unittest.skipUnless(HAVE_AIOQUIC, "aioquic not available")
class XpraH3ConnectionSettingsTest(unittest.TestCase):

    def _http(self, *, enable_webtransport: bool) -> "XpraH3Connection":
        config = QuicConfiguration(is_client=True, max_datagram_frame_size=65536)
        quic = QuicConnection(configuration=config)
        return XpraH3Connection(quic, enable_webtransport=enable_webtransport)

    def test_webtransport_settings_include_wt_max_sessions(self):
        http = self._http(enable_webtransport=True)
        settings = http._sent_settings or http._get_local_settings()
        assert settings[SETTINGS_WT_MAX_SESSIONS] == 1
        assert settings[SETTINGS_WEBTRANSPORT_MAX_SESSIONS] == 1
        assert settings[int(Setting.ENABLE_WEBTRANSPORT)] == 1

    def test_without_webtransport_omits_session_limit(self):
        http = self._http(enable_webtransport=False)
        settings = http._sent_settings or http._get_local_settings()
        assert SETTINGS_WT_MAX_SESSIONS not in settings
        assert SETTINGS_WEBTRANSPORT_MAX_SESSIONS not in settings


def main():
    unittest.main()


if __name__ == "__main__":
    main()
