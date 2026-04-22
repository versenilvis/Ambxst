#!/usr/bin/env python3
import socket, sys, json

sock_path = "/tmp/ambxst-clipboard.sock"
cmd = sys.argv[1] if len(sys.argv) > 1 else "{}"

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    s.sendall((cmd + "\n").encode())
    s.shutdown(socket.SHUT_WR)
    data = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    s.close()
    sys.stdout.write(data.decode())
except Exception as e:
    sys.stderr.write(str(e) + "\n")
    sys.exit(1)
