# Emit newline-delimited JSON events for desktop-server (unix socket server).

from __future__ import annotations

import json
import os
import socket
import threading
from typing import Any

from xpra.log import Logger

log = Logger("server")

_lock = threading.Lock()
_clients: list[socket.socket] = []
_listener: socket.socket | None = None
_thread: threading.Thread | None = None


def _socket_path() -> str | None:
    path = os.environ.get("DESKTOP_SERVER_EVENTS_SOCKET", "").strip()
    return path or None


def _accept_loop(listener: socket.socket) -> None:
    while True:
        try:
            client, _addr = listener.accept()
        except OSError:
            return
        with _lock:
            _clients.append(client)


def start() -> None:
    global _listener, _thread
    path = _socket_path()
    if not path:
        return
    if _listener is not None:
        return
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    try:
        if os.path.exists(path):
            os.unlink(path)
    except OSError:
        pass
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(path)
    os.chmod(path, 0o666)
    listener.listen(8)
    _listener = listener
    _thread = threading.Thread(target=_accept_loop, args=(listener,), name="desktop-server-events", daemon=True)
    _thread.start()
    log.info("desktop-server events listening on %s", path)


def emit(event: dict[str, Any]) -> None:
    if _listener is None:
        return
    line = (json.dumps(event, separators=(",", ":")) + "\n").encode()
    dead: list[socket.socket] = []
    with _lock:
        for client in _clients:
            try:
                client.sendall(line)
            except OSError:
                dead.append(client)
        for client in dead:
            _clients.remove(client)


def on_client_connected(server) -> None:
    count = len(getattr(server, "_server_sources", {}) or {})
    emit({"type": "client_count", "count": count})


def on_client_disconnected(server) -> None:
    count = len(getattr(server, "_server_sources", {}) or {})
    emit({"type": "client_count", "count": count})


def on_client_dimensions(width: int, height: int) -> None:
    if width <= 0 or height <= 0:
        return
    emit({"type": "client_dimensions", "width": width, "height": height})
