#!/usr/bin/env python3

import hashlib
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


SECRET = os.environ["WEBHOOK_SECRET"].encode()
HOST = os.environ.get("WEBHOOK_HOST", "127.0.0.1")
PORT = int(os.environ.get("WEBHOOK_PORT", "8080"))
PATH = os.environ.get("WEBHOOK_PATH", "/events")
MAX_BODY_BYTES = int(os.environ.get("WEBHOOK_MAX_BODY_BYTES", str(1024 * 1024)))


class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != PATH:
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", ""))
        except (TypeError, ValueError):
            self.send_error(400, "invalid Content-Length")
            return

        if length < 0:
            self.send_error(400, "invalid Content-Length")
            return

        if length > MAX_BODY_BYTES:
            self.send_error(413, "request body too large")
            return

        body = self.rfile.read(length)

        expected = "sha256=" + hmac.new(SECRET, body, hashlib.sha256).hexdigest()
        supplied = self.headers.get("X-VpsAdmin-Signature-256", "")
        if not hmac.compare_digest(supplied, expected):
            self.send_error(401, "invalid signature")
            return

        try:
            payload = json.loads(body)
            delivery_id = str(payload["delivery"]["id"])
            events = payload["events"]
            if payload["version"] != 1 or not isinstance(events, list) or not events:
                raise ValueError
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            self.send_error(400, "invalid webhook payload")
            return

        if self.headers.get("X-VpsAdmin-Delivery") != delivery_id:
            self.send_error(400, "delivery ID does not match")
            return

        print(json.dumps(payload, sort_keys=True), flush=True)
        self.send_response(204)
        self.end_headers()

    def log_message(self, format, *args):
        print(f"{self.address_string()} - {format % args}", flush=True)


if __name__ == "__main__":
    print(f"Listening on http://{HOST}:{PORT}{PATH}", flush=True)
    ThreadingHTTPServer((HOST, PORT), WebhookHandler).serve_forever()
