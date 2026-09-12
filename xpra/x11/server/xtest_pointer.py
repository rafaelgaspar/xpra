# This file is part of Xpra.
# Copyright (C) 2010 Antoine Martin <antoine@xpra.org>
# Copyright (C) 2008 Nathaniel Smith <njs@pobox.com>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

import ctypes
import os

from xpra.x11.error import xsync
from xpra.x11.bindings.test import XTestBindings
from xpra.log import Logger

log = Logger("x11", "server", "pointer")

# Fork patch: XTestFakeMotionEvent hardcodes screen_number=0 at compile
# time (xpra/x11/bindings/test.pyx: "DEF screen_number = 0"), so on a real
# multi-screen X server (DISPLAY=:N.M with M != 0) every synthetic pointer move lands on screen 0 instead of the
# screen this xpra server is actually bound to -- button_action handling
# calls move_pointer() with the click's own coordinates before pressing the
# button (xpra/server/subsystem/pointer.py do_process_mouse_common), so this
# breaks clicks too, not just standalone motion. Warp the pointer via a
# direct ctypes call to XWarpPointer instead, which does take an explicit
# destination window (and therefore screen); xtest_fake_button has no screen
# parameter and acts on wherever the pointer currently is, so it needs no
# change once the pointer is warped correctly first.
_libx11 = None
_x11_display = None
_x11_root_window = None


def _x11_root():
    global _libx11, _x11_display, _x11_root_window
    if _x11_root_window is not None:
        return _libx11, _x11_display, _x11_root_window
    lib = ctypes.CDLL("libX11.so.6")
    lib.XOpenDisplay.restype = ctypes.c_void_p
    lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    # None -> NULL -> Xlib falls back to getenv("DISPLAY") itself, same as
    # every other X11 client in this process.
    display = lib.XOpenDisplay(None)
    if not display:
        raise RuntimeError(f"XOpenDisplay failed for DISPLAY={os.environ.get('DISPLAY')!r}")
    lib.XDefaultRootWindow.restype = ctypes.c_ulong
    lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    root = lib.XDefaultRootWindow(display)
    lib.XWarpPointer.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,
        ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
        ctypes.c_int, ctypes.c_int,
    ]
    lib.XFlush.argtypes = [ctypes.c_void_p]
    _libx11, _x11_display, _x11_root_window = lib, display, root
    return lib, display, root


def _warp_pointer(x: int, y: int) -> bool:
    try:
        lib, display, root = _x11_root()
    except Exception as e:
        log.warn("Warning: failed to open a direct X11 connection for pointer warp: %s", e)
        return False
    # src_w=0 (X11 "None" -- no source-window constraint), dest_w=root of
    # our own screen, dest_x/y absolute within it -- moves the pointer onto
    # this screen regardless of which screen XTest itself defaults to.
    lib.XWarpPointer(display, 0, root, 0, 0, 0, 0, x, y)
    lib.XFlush(display)
    return True


class XTestPointerDevice:
    __slots__ = ()

    def __repr__(self):
        return "XTestPointerDevice"

    @staticmethod
    def move_pointer(x: int, y: int, props: dict) -> None:
        log("xtest_fake_motion%s", (x, y, props))
        with xsync:
            if not _warp_pointer(x, y):
                XTestBindings().xtest_fake_motion(x, y)

    @staticmethod
    def get_position() -> tuple[int, int]:
        with xsync:
            from xpra.x11.bindings.keyboard import X11KeyboardBindings
            return X11KeyboardBindings().query_pointer()

    @staticmethod
    def click(button: int, pressed: bool, props: dict) -> None:
        log("xtest_fake_button(%i, %s, %s)", button, pressed, props)
        with xsync:
            XTestBindings().xtest_fake_button(button, pressed)

    @staticmethod
    def wheel_motion(button: int, distance: float) -> None:
        raise NotImplementedError()

    @staticmethod
    def has_precise_wheel() -> bool:
        return False
