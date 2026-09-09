#!/usr/bin/env python3
"""Bounds on the OAuth redirect listener.

The listener sits on loopback during sign-in, so anything local can talk to it.
These cover what it accepts, what it refuses, and that it refuses without
buffering first.
"""

from __future__ import annotations

import base64
import importlib.util
import io
import socket
import sys
import threading
import unittest
from pathlib import Path

SOURCE_ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = SOURCE_ROOT / "scripts" / "oauth-callback.py"
SPEC = importlib.util.spec_from_file_location("oauth_callback", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load the OAuth callback helper")
helper = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = helper
SPEC.loader.exec_module(helper)


class RequestLineReading(unittest.TestCase):
    def pair(self):
        left, right = socket.socketpair()
        self.addCleanup(left.close)
        self.addCleanup(right.close)
        return left, right

    def test_reads_one_line_and_drops_the_carriage_return(self):
        client, server = self.pair()
        client.sendall(b"GET /callback?code=abc HTTP/1.1\r\nHost: x\r\n\r\n")
        self.assertEqual(
            helper.read_request_line(server), "GET /callback?code=abc HTTP/1.1"
        )

    def test_refuses_a_request_line_past_the_budget(self):
        client, server = self.pair()
        flood = b"GET /" + b"a" * (helper.MAX_REQUEST_BYTES + 64)
        client.sendall(flood)
        with self.assertRaises(helper.Overflow):
            helper.read_request_line(server)

    def test_a_client_that_closes_without_a_line_is_not_an_error(self):
        client, server = self.pair()
        client.sendall(b"GET /callback HTTP/1.1")
        client.close()
        self.assertIsNone(helper.read_request_line(server))

    def test_a_line_just_inside_the_budget_is_read(self):
        client, server = self.pair()
        target = "/callback?code=" + "a" * 100
        line = f"GET {target} HTTP/1.1"
        client.sendall(line.encode() + b"\r\n")
        self.assertEqual(helper.read_request_line(server), line)


class RequestLineMatching(unittest.TestCase):
    def test_accepts_the_expected_path_with_and_without_a_query(self):
        self.assertTrue(
            helper.request_line_targets("GET /callback?code=a HTTP/1.1", "/callback")
        )
        self.assertTrue(helper.request_line_targets("GET /callback HTTP/1.0", "/callback"))

    def test_rejects_anything_else(self):
        cases = [
            "GET /favicon.ico HTTP/1.1",
            "POST /callback HTTP/1.1",
            "GET /callback",
            "GET /callback HTTP/1.1 extra",
            "nonsense",
            "",
        ]
        for line in cases:
            with self.subTest(line=line):
                self.assertFalse(helper.request_line_targets(line, "/callback"))


class ResponseReading(unittest.TestCase):
    def test_decodes_one_base64_line(self):
        payload = b"HTTP/1.1 200 OK\r\n\r\nhello"
        stream = io.StringIO(base64.b64encode(payload).decode() + "\n")
        self.assertEqual(helper.read_response(stream), payload)

    def test_refuses_junk_and_oversized_input(self):
        self.assertIsNone(helper.read_response(io.StringIO("not base64!!\n")))
        self.assertIsNone(helper.read_response(io.StringIO("")))
        huge = "A" * (helper.MAX_RESPONSE_BYTES + 10)
        self.assertIsNone(helper.read_response(io.StringIO(huge + "\n")))


class ServingEndToEnd(unittest.TestCase):
    def serve_on_free_port(self, stdin, stdout, path="/callback", timeout=5.0):
        bound = threading.Event()
        chosen = []
        result = []

        def ready(port):
            chosen.append(port)
            bound.set()

        def run():
            result.append(
                helper.serve(0, path, timeout, stdin=stdin, stdout=stdout, ready=ready)
            )

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        self.assertTrue(bound.wait(5), "listener never bound")
        return chosen[0], thread, result

    def test_accepts_the_redirect_and_writes_back_what_it_is_given(self):
        response = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"
        stdin = io.StringIO(base64.b64encode(response).decode() + "\n")
        stdout = io.StringIO()
        port, thread, result = self.serve_on_free_port(stdin, stdout)

        with socket.create_connection(("127.0.0.1", port), timeout=5) as client:
            client.sendall(b"GET /callback?code=abc&state=xyz HTTP/1.1\r\n\r\n")
            received = client.recv(len(response))
        thread.join(5)
        self.assertEqual(received, response)
        self.assertEqual(result, [0])
        self.assertEqual(stdout.getvalue(), "GET /callback?code=abc&state=xyz HTTP/1.1\n")

    def test_a_flood_is_refused_and_the_real_redirect_still_lands(self):
        response = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"
        stdin = io.StringIO(base64.b64encode(response).decode() + "\n")
        stdout = io.StringIO()
        port, thread, result = self.serve_on_free_port(stdin, stdout)

        with socket.create_connection(("127.0.0.1", port), timeout=5) as attacker:
            attacker.sendall(b"GET /" + b"a" * (helper.MAX_REQUEST_BYTES + 512))
            self.assertIn(b"431", attacker.recv(128))

        with socket.create_connection(("127.0.0.1", port), timeout=5) as client:
            client.sendall(b"GET /callback?code=abc HTTP/1.1\r\n\r\n")
            client.recv(len(response))
        thread.join(5)
        self.assertEqual(result, [0])
        self.assertEqual(stdout.getvalue().count("\n"), 1, "exactly one record emitted")

    def test_an_unexpected_path_is_answered_and_ignored(self):
        response = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"
        stdin = io.StringIO(base64.b64encode(response).decode() + "\n")
        stdout = io.StringIO()
        port, thread, result = self.serve_on_free_port(stdin, stdout)

        with socket.create_connection(("127.0.0.1", port), timeout=5) as stray:
            stray.sendall(b"GET /favicon.ico HTTP/1.1\r\n\r\n")
            self.assertIn(b"404", stray.recv(128))

        with socket.create_connection(("127.0.0.1", port), timeout=5) as client:
            client.sendall(b"GET /callback?code=abc HTTP/1.1\r\n\r\n")
            client.recv(len(response))
        thread.join(5)
        self.assertEqual(result, [0])
        self.assertEqual(stdout.getvalue(), "GET /callback?code=abc HTTP/1.1\n")

    def test_gives_up_when_the_deadline_passes(self):
        port, thread, result = self.serve_on_free_port(
            io.StringIO(""), io.StringIO(), timeout=0.3
        )
        thread.join(5)
        self.assertEqual(result, [1], "a listener nobody used exits non-zero")


if __name__ == "__main__":
    unittest.main()
