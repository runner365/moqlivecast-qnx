#!/usr/bin/env python3
"""Minimal time reference: returns the host's epoch milliseconds as JSON.

    GET /time  ->  {"t": 1795488354649, "iso": "2026-11-24T02:45:54.649Z"}

Run it on ONE machine (the reference), then measure every other machine's clock
offset against it with scripts/time_probe.py.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/time_plain":
            # Plain text: a single integer, for clients that cannot parse JSON
            # (e.g. a small C probe on QNX).
            body = ("%d\n" % int(time.time() * 1000)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        if route != "/time":
            self.send_response(404)
            self.end_headers()
            return
        now_ms = int(time.time() * 1000)
        body = json.dumps({
            "t": now_ms,
            "iso": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(now_ms / 1000))
                   + ".%03dZ" % (now_ms % 1000),
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9001
    print(f"time reference listening on 0.0.0.0:{port}  (GET /time)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
