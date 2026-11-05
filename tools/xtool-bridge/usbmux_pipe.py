"""Pipe stdin/stdout to Apple's usbmuxd service on Windows (127.0.0.1:27015).

Runs on Windows (python.exe). iphone-bridge.sh in WSL starts one copy per
connection, so Linux tools (xtool, libimobiledevice) reach the iPhone through
the Apple Devices app, without usbipd.
"""
import socket
import sys
import threading

sock = socket.create_connection(("127.0.0.1", 27015))
sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)


def to_socket():
    stdin = sys.stdin.buffer.raw
    while True:
        data = stdin.read(65536)
        if not data:
            break
        sock.sendall(data)
    try:
        sock.shutdown(socket.SHUT_WR)
    except OSError:
        pass


threading.Thread(target=to_socket, daemon=True).start()
stdout = sys.stdout.buffer
while True:
    data = sock.recv(65536)
    if not data:
        break
    stdout.write(data)
    stdout.flush()
