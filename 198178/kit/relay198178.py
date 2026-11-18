#!/usr/bin/env python3
"""Host relay for openclaw/openclaw#198178, run on <LAB-LINUX-HOST> as <LAB-USER> (NOT in a bench). Python 3 stdlib only.

Why it exists: Linux benches cannot reach the lab proxy directly (lab network policy), and the proxy token must never
enter a bench. So this relay listens on the bench bridge address, accepts
only the one bench IP named in ALLOW, and forwards to the lab proxy with <LAB-LINUX-HOST>'s own token, read from TOKEN_FILE
for each request (never logged, never printed, never on a command line).

Guards (all outside the bench, all logged as relay_reason):
  - only clients in ALLOW (comma-separated CIDRs; the order passes the bench's /32);
  - only GET /v1/models and POST /v1/chat/completions (the two routes the lab proxy serves); anything else ->
    404 relay-path, never forwarded; at most MAX_POSTS forwarded POSTs (default 16), then 429 relay-budget;
  - request body over MAX_BODY bytes (default 16384, ~4K tokens) -> 413 relay-too-large, never forwarded;
  - after HARD_STOP (epoch seconds; capped at start + 4 h, so a mistyped epoch cannot keep the path open)
    -> 503 relay-hard-stop; the process exits 60 s after it;
  - its own clock guard: 07:30-13:00Z (the lab host's night jobs) -> 503 relay-night, never forwarded;
  - output cap: for a chat POST, max_completion_tokens / max_tokens are clamped to OUT_CAP (default 256) before
    forwarding (if neither is present, max_tokens=OUT_CAP is added), so the model never generates thousands of tokens.
    The cap OpenClaw REQUESTED is the measurement; it is recorded here (orig_caps) and in the bench's own wire log.
    The lab proxy would clamp to 8192 anyway, so the server never sees an OpenClaw cap above 8192 in any case.
Log (LOG, one JSON line per request): seq, t, secs, client, method, path, status, relay_reason, auth_in_present,
req_sha256 (body exactly as received = what OpenClaw sent), fwd_sha256, orig_caps, fwd_caps, req_bytes, resp (up to
64 KB), retry_after. No header values.

Usage:
  LISTEN=<BRIDGE-IP>:18178 ALLOW=<BENCH-IP>/32 UPSTREAM=<LAB-PROXY> TOKEN_FILE=~/.config/lab-proxy/token \
  LOG=~/jobs/J198178r/relay.jsonl HARD_STOP=1794952800 python3 -I relay198178.py
  python3 -I relay198178.py selftest     # GET /v1/models on UPSTREAM with the token; prints status + model ids only
"""
import hashlib, http.client, ipaddress, json, os, re, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("UPSTREAM", "<LAB-PROXY>")
UH, UP = UPSTREAM.rsplit(":", 1)
TOKEN_FILE = os.path.expanduser(os.environ.get("TOKEN_FILE", "~/.config/lab-proxy/token"))
LOG = os.path.expanduser(os.environ.get("LOG", "relay.jsonl"))
MAX_POSTS = int(os.environ.get("MAX_POSTS", "16"))
MAX_SLOT_WAITS = int(os.environ.get("MAX_SLOT_WAITS", "40"))  # r2: at most 40 single-slot 429s, then relay-budget
slot_waits = [0]
MAX_BODY = int(os.environ.get("MAX_BODY", "16384"))
OUT_CAP = int(os.environ.get("OUT_CAP", "256"))
HARD_STOP = float(os.environ.get("HARD_STOP", "0"))
if HARD_STOP:
    HARD_STOP = min(HARD_STOP, time.time() + 4 * 3600)
ROUTES = {("GET", "/v1/models"), ("POST", "/v1/chat/completions")}
TOKEN_OK = re.compile(r"^[A-Za-z0-9._~+/=-]+$")
RESP_MAX = 65536
CAP_KEYS = ("max_completion_tokens", "max_tokens")
lock, seq, posts = threading.Lock(), [0], [0]


def token():
    """The lab-proxy token. Any error names only its kind, never the value."""
    with open(TOKEN_FILE) as f:
        t = f.read().strip()
    if not TOKEN_OK.match(t):
        raise ValueError("token file content is not a single header-safe token (value not shown)")
    return t


def selftest():
    try:
        c = http.client.HTTPConnection(UH, int(UP), timeout=30)
        c.request("GET", "/v1/models", headers={"Authorization": "Bearer " + token()})
        r = c.getresponse(); data = r.read()
    except Exception as e:  # only the type name: a header error message would carry the token
        print(f"SELFTEST upstream={UPSTREAM} error={type(e).__name__}")
        return 1
    try:
        ids = [m.get("id") for m in json.loads(data).get("data", [])]
    except Exception:
        ids = "unparsable"
    print(f"SELFTEST upstream={UPSTREAM} status={r.status} models={ids}")
    return 0 if r.status == 200 else 1


def night(t):
    """07:30-13:00Z: the lab host's night jobs (the lab proxy's own clock backstop is 07:30-12:30Z)."""
    g = time.gmtime(t); hm = g.tm_hour * 100 + g.tm_min
    return 730 <= hm < 1300


def clamp_caps(body):
    """Returns (forwarded body bytes, orig_caps, fwd_caps). Non-JSON bodies pass unchanged (the proxy answers 400)."""
    try:
        o = json.loads(body)
    except Exception:
        return body, None, None
    if not isinstance(o, dict):
        return body, None, None
    orig = {k: o[k] for k in CAP_KEYS if k in o}
    present = False
    for k in CAP_KEYS:
        v = o.get(k)
        if isinstance(v, int) and not isinstance(v, bool):
            o[k] = max(1, min(v, OUT_CAP)); present = True
    if not present:
        o["max_tokens"] = OUT_CAP
    fwd = {k: o[k] for k in CAP_KEYS if k in o}
    return json.dumps(o).encode(), orig, fwd


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 120

    def log_message(self, *a):
        pass

    def local(self, status, reason, extra=None):
        data = json.dumps({"error": {"type": "relay198178", "reason": reason}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers(); self.wfile.write(data)
        return data

    def go(self):
        t0 = time.time()
        client = self.client_address[0]
        rec = {"t": t0, "client": client, "method": self.command, "path": self.path,
               "auth_in_present": bool(self.headers.get("Authorization"))}
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = -1
        if n > MAX_BODY or n < 0:
            rec.update(status=413, relay_reason="relay-too-large", req_bytes=n)
            self.close_connection = True
            self.local(413, "relay-too-large")
            return self.write(rec, t0)
        body = self.rfile.read(n) if n else b""
        rec.update(req_bytes=len(body), req_sha256=hashlib.sha256(body).hexdigest(), req=body.decode("utf-8", "replace"))
        if HARD_STOP and t0 > HARD_STOP:
            rec.update(status=503, relay_reason="relay-hard-stop"); self.local(503, "relay-hard-stop")
            return self.write(rec, t0)
        if night(t0):
            rec.update(status=503, relay_reason="relay-night"); self.local(503, "relay-night")
            return self.write(rec, t0)
        if self.command not in ("GET", "POST"):
            rec.update(status=405, relay_reason="relay-method"); self.local(405, "relay-method")
            return self.write(rec, t0)
        if (self.command, self.path.split("?", 1)[0].rstrip("/")) not in ROUTES:
            rec.update(status=404, relay_reason="relay-path"); self.local(404, "relay-path")
            return self.write(rec, t0)
        fwd = body
        if self.command == "POST":
            with lock:
                if posts[0] >= MAX_POSTS:
                    over = True
                else:
                    over = False; posts[0] += 1
            if over:
                rec.update(status=429, relay_reason="relay-budget")
                self.local(429, "relay-budget", {"Retry-After": "3600"})
                return self.write(rec, t0)
            fwd, rec["orig_caps"], rec["fwd_caps"] = clamp_caps(body)
        rec["fwd_sha256"] = hashlib.sha256(fwd).hexdigest()
        parts, status, sent, c = [], 502, False, None
        try:
            hdrs = {"Content-Type": self.headers.get("Content-Type", "application/json"), "Authorization": "Bearer " + token()}
            if self.command == "POST":
                hdrs["Content-Length"] = str(len(fwd))
            c = http.client.HTTPConnection(UH, int(UP), timeout=900)
            c.request(self.command, self.path, body=fwd if self.command == "POST" else None, headers=hdrs)
            r = c.getresponse(); status = r.status
            rec["retry_after"] = r.getheader("Retry-After")
            self.send_response(status)
            self.send_header("Content-Type", r.getheader("Content-Type", "application/json"))
            if rec["retry_after"]:
                self.send_header("Retry-After", rec["retry_after"])
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers(); sent = True
            while True:
                chunk = r.read1(65536)
                if not chunk:
                    break
                parts.append(chunk)
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk)); self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n"); self.wfile.flush()
            rec["relay_reason"] = "forwarded"
        except Exception as e:
            rec["relay_reason"] = f"relay-error {type(e).__name__}"
            if not sent:
                try:
                    self.local(502, "relay-upstream-error")
                except Exception:
                    pass
            self.close_connection = True
        finally:
            if c is not None:
                c.close()
        resp = b"".join(parts)
        if self.command == "POST" and status == 429 and b"lab-request-in-flight" in resp:
            with lock:  # r2: refused by the proxy's single lab slot, never reached the model server: not counted against MAX_POSTS
                posts[0] -= 1; slot_waits[0] += 1
                rec["slot_waits"] = slot_waits[0]
                if slot_waits[0] > MAX_SLOT_WAITS:
                    posts[0] = MAX_POSTS  # bound the retries too: further POSTs get relay-budget
        rec.update(status=status, resp=resp[:RESP_MAX].decode("utf-8", "replace"), resp_bytes=len(resp))
        self.write(rec, t0)

    def write(self, rec, t0):
        with lock:
            seq[0] += 1
            rec["seq"] = seq[0]; rec["secs"] = round(time.time() - t0, 3)
            with open(LOG, "a") as f:
                f.write(json.dumps(rec) + "\n")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = go


class S(ThreadingHTTPServer):
    daemon_threads = True

    def verify_request(self, request, client_address):
        ip = ipaddress.ip_address(client_address[0])
        return any(ip in n for n in NETS)


def stopper():
    while True:
        time.sleep(15)
        if HARD_STOP and time.time() > HARD_STOP + 60:
            print("relay198178: past hard stop, exiting", flush=True)
            os._exit(0)


if __name__ == "__main__":
    if sys.argv[1:] == ["selftest"]:
        sys.exit(selftest())
    allow = os.environ.get("ALLOW", "")
    if not allow:
        sys.exit("relay198178: ALLOW (the bench IP as a /32) is required")
    NETS = [ipaddress.ip_network(x.strip(), strict=False) for x in allow.split(",") if x.strip()]
    if not HARD_STOP:
        sys.exit("relay198178: HARD_STOP (epoch) is required")
    token()  # fail now if the token file is missing
    h, p = os.environ.get("LISTEN", "<BRIDGE-IP>:18178").rsplit(":", 1)
    threading.Thread(target=stopper, daemon=True).start()
    print(f"relay198178 {h}:{p} routes=GET /v1/models,POST /v1/chat/completions night=07:30-13:00Z allow={allow} -> {UPSTREAM} max_posts={MAX_POSTS} max_body={MAX_BODY} "
          f"out_cap={OUT_CAP} hard_stop={int(HARD_STOP)} log={LOG}", flush=True)
    S((h, int(p)), H).serve_forever()
