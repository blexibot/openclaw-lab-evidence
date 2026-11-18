#!/usr/bin/env python3
"""In-bench wire logger for openclaw/openclaw#198178 (lab only, synthetic prompts). Python 3 stdlib only.
Listens on LISTEN (default 127.0.0.1:18178). OpenClaw's sglang provider baseUrl points here. Every request is
forwarded byte for byte (body unchanged) to UPSTREAM, the host relay on <LAB-LINUX-HOST>'s bench bridge, which alone holds
the lab-proxy token. This shim never sees a real token: OpenClaw sends a dummy key, which is passed on and replaced
by the host relay. One JSON line per request goes to LOG: seq, t, secs, method, path, status, auth_present (bool
only; no Authorization value is ever logged), req (raw body text), req_sha256, resp (raw response text, up to 64 KB),
retry_after (the Retry-After header, when present).
Responses are streamed back to OpenClaw as they arrive (chunked), so a streamed answer is not held back.
Usage: LISTEN=127.0.0.1:18178 UPSTREAM=<BRIDGE-IP>:18178 LOG=/root/r198178/<tag>/wire.jsonl python3 -I shim198178.py
"""
import hashlib, http.client, json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN = os.environ.get("LISTEN", "127.0.0.1:18178")
UH, UP = os.environ.get("UPSTREAM", "<BRIDGE-IP>:18178").rsplit(":", 1)
LOG = os.environ.get("LOG", "wire.jsonl")
RESP_MAX = 65536
lock, seq = threading.Lock(), [0]


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def go(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        auth = self.headers.get("Authorization")
        hdrs = {"Content-Type": self.headers.get("Content-Type", "application/json")}
        if auth:
            hdrs["Authorization"] = auth  # passed on, never logged; the host relay replaces it
        if self.command in ("POST", "PUT"):
            hdrs["Content-Length"] = str(len(body))
        t0 = time.time()
        parts, status, err, c, sent, ra = [], 502, None, None, False, None
        try:
            c = http.client.HTTPConnection(UH, int(UP), timeout=900)
            c.request(self.command, self.path, body=body if body else None, headers=hdrs)
            r = c.getresponse(); status = r.status
            self.send_response(status)
            self.send_header("Content-Type", r.getheader("Content-Type", "application/json"))
            ra = r.getheader("Retry-After")  # not secret; logged so the run waits as told
            if ra:
                self.send_header("Retry-After", ra)
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
            err = f"shim: {type(e).__name__}: {e}"
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
        resp = b"".join(parts)
        with lock:
            seq[0] += 1
            rec = {"seq": seq[0], "t": t0, "secs": round(time.time() - t0, 3), "method": self.command,
                   "path": self.path, "status": status, "auth_present": bool(auth),
                   "req_sha256": hashlib.sha256(body).hexdigest(), "req_bytes": len(body),
                   "req": body.decode("utf-8", "replace"),
                   "resp": resp[:RESP_MAX].decode("utf-8", "replace"), "resp_bytes": len(resp)}
            if ra:
                rec["retry_after"] = ra
            if err:
                rec["shim_error"] = err
            with open(LOG, "a") as f:
                f.write(json.dumps(rec) + "\n")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = go


if __name__ == "__main__":
    h, p = LISTEN.rsplit(":", 1)
    print(f"shim198178 {LISTEN} -> {UH}:{UP} log {LOG}", flush=True)
    ThreadingHTTPServer((h, int(p)), H).serve_forever()
