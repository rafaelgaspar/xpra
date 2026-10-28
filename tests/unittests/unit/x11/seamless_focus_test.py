#!/usr/bin/env python3
# This file is part of Xpra.
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

import importlib.util
import unittest
from collections import deque
from unittest.mock import Mock, patch


@unittest.skipUnless(importlib.util.find_spec("xpra.x11.bindings.core"), "X11 bindings are not built")
class SeamlessFocusTest(unittest.TestCase):

    @staticmethod
    def server(x11_focus: int, parents: dict[int, int]):
        from xpra.x11.server import seamless

        window = Mock(xid=0x400005, corral_xid=0x200010)
        window.is_OR.return_value = False
        window.is_managed.return_value = True

        class ServerStub:
            _focus = seamless.SeamlessServer._focus
            _x11_focus_is_on = seamless.SeamlessServer._x11_focus_is_on

            def __init__(self):
                self._has_focus = 1
                self.last_raised = None
                self._focus_history = deque(maxlen=100)
                self._id_to_window = {1: window}

            def get_window(self, wid):
                return self._id_to_window.get(wid)

        server = ServerStub()
        bindings = Mock()
        bindings.XGetInputFocus.return_value = (x11_focus, 0)
        bindings.getParent.side_effect = lambda xid: parents.get(xid, 0)
        return server, window, bindings

    def focus(self, server, bindings) -> None:
        with patch("xpra.x11.server.seamless.X11WindowBindings", return_value=bindings):
            server._focus(None, 1, None)

    def test_skips_when_x_focus_is_on_the_window(self) -> None:
        server, window, bindings = self.server(0x400005, {})
        self.focus(server, bindings)
        window.give_client_focus.assert_not_called()

    def test_skips_when_x_focus_is_on_a_child_of_the_window(self) -> None:
        # e.g. a toolkit focusing its own child after WM_TAKE_FOCUS
        server, window, bindings = self.server(0x400009, {0x400009: 0x400005})
        self.focus(server, bindings)
        window.give_client_focus.assert_not_called()

    def test_takes_focus_back_from_another_x_client(self) -> None:
        # another seamless server on a different screen of the same X server
        server, window, bindings = self.server(0x1200006, {0x1200006: 0x6f9})
        self.focus(server, bindings)
        window.give_client_focus.assert_called_once()
        self.assertEqual(server._has_focus, 1)

    def test_takes_focus_back_from_pointer_root(self) -> None:
        server, window, bindings = self.server(1, {})
        self.focus(server, bindings)
        window.give_client_focus.assert_called_once()


def main():
    unittest.main()


if __name__ == "__main__":
    main()
