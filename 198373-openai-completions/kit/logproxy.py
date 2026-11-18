#!/usr/bin/env python3
"""Logging pass-through for openclaw/openclaw#198373 (lab only, synthetic prompts). v1-route edition (2026-11-17):
also records the X-Lab-Request-Id and Content-Type response headers so wire records match /lab/stats by id.
Listens on LISTEN (default 127.0.0.1:11434), forwards every request byte for byte to UPSTREAM (the lab model relay),
and appends one JSON line per request to LOG: the raw request body (as text), its sha256, the status, and the raw
response text. Requests go upstream with Content-Length only (the lab filter refuses chunked bodies). Responses are
streamed back to OpenClaw as they arrive (chunked), so a slow cold prompt never looks like a stalled stream.
Python 3 stdlib only.
Usage: LISTEN=127.0.0.1:11434 UPSTREAM=<RELAY>:11435 LOG=/root/r198373/wire-<tag>.jsonl python3 logproxy.py
"""
import hashlib, http.client, json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN = os.environ.get("LISTEN", "127.0.0.1:11434")
UH, UP = os.environ.get("UPSTREAM", "<RELAY>:11435").rsplit(":", 1)
LOG = os.environ.get("LOG", "wire.jsonl")
lock, seq = threading.Lock(), [0]


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def go(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        hdrs = {"Content-Type": self.headers.get("Content-Type", "application/json")}
        if self.command in ("POST", "PUT"):
            hdrs["Content-Length"] = str(len(body))
        t0 = time.time()
        parts, status, err, c, sent, rh = [], 502, None, None, False, {}
        try:
            c = http.client.HTTPConnection(UH, int(UP), timeout=1800)
            c.request(self.command, self.path, body=body if body else None, headers=hdrs)
            r = c.getresponse(); status = r.status
            rh = {k: r.getheader(k) for k in ("X-Lab-Request-Id", "Content-Type") if r.getheader(k) is not None}
            self.send_response(status)
            self.send_header("Content-Type", r.getheader("Content-Type", "application/json"))
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers(); sent = True
            while True:
                chunk = r.read1(65536)
                if not chunk:
                    break
                parts.append(chunk)
                if self.command != "HEAD":
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk)); self.wfile.flush()
            if self.command != "HEAD":
                self.wfile.write(b"0\r\n\r\n"); self.wfile.flush()
        except Exception as e:
            err = f"logproxy: {type(e).__name__}: {e}"
            if not sent:
                data = json.dumps({"error": err}).encode()
                try:
                    self.send_response(502)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers(); self.wfile.write(data)
                except Exception:
                    pass
            self.close_connection = True
        finally:
            if c is not None:
                c.close()
        with lock:
            seq[0] += 1
            rec = {"seq": seq[0], "t": t0, "secs": round(time.time() - t0, 3), "method": self.command,
                   "path": self.path, "status": status, "req_sha256": hashlib.sha256(body).hexdigest(),
                   "req": body.decode("utf-8", "replace"), "resp": b"".join(parts).decode("utf-8", "replace"),
                   "resp_headers": rh}
            if err:
                rec["proxy_error"] = err
            with open(LOG, "a") as f:
                f.write(json.dumps(rec) + "\n")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = go


if __name__ == "__main__":
    h, p = LISTEN.rsplit(":", 1)
    print(f"logproxy {LISTEN} -> {UH}:{UP} log {LOG}", flush=True)
    ThreadingHTTPServer((h, int(p)), H).serve_forever()
