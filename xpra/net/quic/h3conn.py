# This file is part of Xpra.
# Copyright (C) 2026 Antoine Martin <antoine@xpra.org>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

"""HTTP/3 connection that advertises WebTransport session SETTINGS.

aioquic still only sends ENABLE_WEBTRANSPORT (draft-02). Safari 26.4+
requires SETTINGS_WT_MAX_SESSIONS >= 1 before it will complete `ready()`.
Value 1 means a single session per connection, so the draft-14
WT_INITIAL_MAX_* flow-control settings are not required.
"""

from aioquic.h3.connection import H3Connection

# draft-ietf-webtrans-http3-13 SETTINGS_WT_MAX_SESSIONS
SETTINGS_WT_MAX_SESSIONS = 0x14E9CD29
# draft-ietf-webtrans-http3-07 SETTINGS_WEBTRANSPORT_MAX_SESSIONS
SETTINGS_WEBTRANSPORT_MAX_SESSIONS = 0xC671706A

# Exactly one session: browsers open one WT per QUIC connection here.
WT_MAX_SESSIONS = 1


def with_wt_max_sessions(settings: dict[int, int]) -> dict[int, int]:
    """Copy `settings` and advertise a single WebTransport session."""
    advertised = dict(settings)
    advertised[SETTINGS_WT_MAX_SESSIONS] = WT_MAX_SESSIONS
    advertised[SETTINGS_WEBTRANSPORT_MAX_SESSIONS] = WT_MAX_SESSIONS
    return advertised


class XpraH3Connection(H3Connection):
    def _get_local_settings(self) -> dict[int, int]:
        settings = super()._get_local_settings()
        if self._enable_webtransport:
            return with_wt_max_sessions(settings)
        return settings
