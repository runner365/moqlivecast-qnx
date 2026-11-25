#!/usr/bin/env python3
"""Receive log files uploaded from the QNX target.

    python3 scripts/log_receiver.py [port] [outdir]

On the target:

    curl --data-binary @/tmp/flv2moqtransport_client.log \
         "http://10.0.2.2:8000/upload?name=client.log"

The file is written to <outdir>/<name>. Only the basename is used, so a crafted
name cannot escape the output directory.
"""
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

OUTDIR = "."


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/upload":
            self.send_response(404)
            self.end_headers()
            return
        name = (parse_qs(url.query).get("name") or ["upload.bin"])[0]
        name = os.path.basename(name) or "upload.bin"
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            self.send_response(400)
            self.end_headers()
            return
        data = self.rfile.read(length)
        path = os.path.join(OUTDIR, name)
        with open(path, "wb") as fh:
            fh.write(data)
        print(f"received {len(data)} bytes -> {path}", flush=True)
        body = b"ok\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    if len(sys.argv) > 2:
        OUTDIR = sys.argv[2]
    os.makedirs(OUTDIR, exist_ok=True)
    print(f"log receiver on 0.0.0.0:{port}, writing to {OUTDIR}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
