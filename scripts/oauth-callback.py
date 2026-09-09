#!/usr/bin/env python3
"""Loopback listener for the Spotify OAuth redirect.

This used to be `socat TCP4-LISTEN:... STDIO`, which hands every byte it reads
straight to the caller. Anything local could connect during the sign-in window
and stream a request line that never ends, and the reader on the other side
buffered all of it before anyone looked at what it was.

So this reads a request line into a fixed budget and gives up the moment it is
exceeded, holds a deadline over the whole wait, ignores anything that is not a
GET for the expected path, and prints exactly one line: the request line it
accepted. The caller checks the OAuth state and sends back the response to
write, base64 on a single line, because the response itself has newlines in it.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import errno
import signal
import socket
import sys
import time

# A browser redirect is a couple of hundred bytes. This is room to spare, and
# far too small to be worth flooding.
MAX_REQUEST_BYTES = 4096
# The caller's response is about a kilobyte before encoding.
MAX_RESPONSE_BYTES = 64 * 1024
# Junk connections get an answer and a close; this bounds how many we entertain.
MAX_CONNECTIONS = 8
# One client gets this long to send its request line.
PER_CONNECTION_TIMEOUT = 5.0

TOO_LONG = (
    b"HTTP/1.1 431 Request Header Fields Too Large\r\n"
    b"Content-Length: 0\r\nConnection: close\r\n\r\n"
)
NOT_FOUND = b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"


class Overflow(Exception):
    """The client sent more than the budget without finishing its request line."""


def read_request_line(connection, limit=MAX_REQUEST_BYTES, deadline=None):
    """The first line, or None if the client gave up or ran out of time.

    Raises Overflow as soon as the budget is passed, without keeping what was
    read: a sender this far outside the protocol has nothing worth buffering.
    """
    buffered = bytearray()
    while True:
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            connection.settimeout(min(remaining, PER_CONNECTION_TIMEOUT))
        try:
            chunk = connection.recv(1024)
        except (TimeoutError, socket.timeout):
            return None
        except OSError as error:
            if error.errno == errno.EINTR:
                continue
            return None
        if not chunk:
            return None
        newline = chunk.find(b"\n")
        if newline < 0:
            if len(buffered) + len(chunk) > limit:
                raise Overflow
            buffered.extend(chunk)
            continue
        if len(buffered) + newline > limit:
            raise Overflow
        buffered.extend(chunk[:newline])
        return bytes(buffered).rstrip(b"\r").decode("utf-8", "replace")


def request_line_targets(line, expected_path):
    """Whether this is a GET for the path we are waiting on."""
    parts = str(line or "").split(" ")
    if len(parts) != 3 or parts[0] != "GET" or not parts[2].startswith("HTTP/"):
        return False
    target = parts[1]
    separator = target.find("?")
    path = target if separator < 0 else target[:separator]
    return path == str(expected_path or "/callback")


def read_response(stream, limit=MAX_RESPONSE_BYTES):
    """One base64 line from the caller, decoded. None if it never arrives."""
    line = stream.readline(limit + 1)
    if not line or len(line) > limit:
        return None
    try:
        return base64.b64decode(line.strip(), validate=True)
    except (binascii.Error, ValueError):
        return None


def serve(port, path, timeout, stdin=None, stdout=None, ready=None):
    """Wait for the redirect. Returns 0 once a response has been written."""
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    deadline = time.monotonic() + timeout

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(("127.0.0.1", port))
        listener.listen(MAX_CONNECTIONS)
        if ready is not None:
            ready(listener.getsockname()[1])

        for _ in range(MAX_CONNECTIONS):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            listener.settimeout(remaining)
            try:
                connection, _ = listener.accept()
            except (TimeoutError, socket.timeout):
                break
            except OSError:
                break
            with connection:
                try:
                    line = read_request_line(connection, deadline=deadline)
                except Overflow:
                    _send(connection, TOO_LONG)
                    continue
                if line is None:
                    continue
                if not request_line_targets(line, path):
                    _send(connection, NOT_FOUND)
                    continue
                stdout.write(line + "\n")
                stdout.flush()
                response = read_response(stdin)
                if response:
                    _send(connection, response)
                return 0
    finally:
        listener.close()
    return 1


def _send(connection, payload):
    try:
        connection.sendall(payload)
    except OSError:
        pass


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--path", default="/callback")
    parser.add_argument("--timeout", type=float, default=180.0)
    arguments = parser.parse_args(argv)

    # Quickshell stops us by signalling; leave the port free on the way out.
    for name in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(name, lambda *_: sys.exit(1))

    if not 0 < arguments.port < 65536:
        print("oauth-callback.py: port out of range", file=sys.stderr)
        return 2
    try:
        return serve(arguments.port, arguments.path, arguments.timeout)
    except OSError as error:
        print(f"oauth-callback.py: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
