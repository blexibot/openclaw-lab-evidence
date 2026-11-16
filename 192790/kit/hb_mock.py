#!/usr/bin/env python3
"""Mock / logging relay for openclaw/openclaw#192790 (heartbeat scratch). Synthetic only. Stdlib only.

Serve:   python3 hb_mock.py serve        (env: PORT=11434, LOG=<jsonl>, MODE_FILE=<path>, UPSTREAM=<url or empty>)
Report:  python3 hb_mock.py summary <jsonl>

Mock mode (UPSTREAM empty). MODE_FILE holds one word, re-read on every request:
  note   heartbeat turn -> heartbeat_respond {outcome no_change, notify false, summary, scratch=<reporter's note>}
  plain  heartbeat turn -> heartbeat_respond {outcome no_change, notify false, summary}   (no scratch)
  text   heartbeat turn -> plain text "NO_REPLY"                                          (no tool call)
  If heartbeat_respond is not in tools[] (e.g. a build without it), the mock answers "NO_REPLY" and logs hb_tool=false.
  After a tool result, or for any non-heartbeat turn, it answers "NO_REPLY".
Relay mode (UPSTREAM=http://host:port): forwards /api/* to UPSTREAM unchanged, buffers the reply, and logs the
  same per-request summary plus the model's final message (tool calls included). Nothing is rewritten.
"""
import json, os, sys, threading, time, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NOTE = ("No active heartbeat tasks. HEARTBEAT.md is comment-only; keep future wakes quiet unless new scratch "
        "context or tasks are provided.")
LOG = os.environ.get("LOG", "/root/r192790/requests.jsonl")
MODE_FILE = os.environ.get("MODE_FILE", "/root/r192790/mode")
UPSTREAM = os.environ.get("UPSTREAM", "").rstrip("/")
PORT = int(os.environ.get("PORT", "11434"))
lock = threading.Lock()
seq = [0]


def log(entry):
    with lock:
        seq[0] += 1
        entry["seq"] = seq[0]
        entry["t"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with open(LOG, "a") as f:
            f.write(json.dumps(entry) + "\n")
        return seq[0]


def mode():
    try:
        return open(MODE_FILE).read().strip() or "plain"
    except OSError:
        return "plain"


def text_of(m):
    c = m.get("content")
    if isinstance(c, list):
        return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
    return c or ""


def summarize(body):
    msgs = body.get("messages") or []
    alltext = "\n".join(text_of(m) for m in msgs)
    tools = [((t.get("function") or {}).get("name")) for t in (body.get("tools") or [])]
    last = msgs[-1] if msgs else {}
    holder = next((text_of(m) for m in reversed(msgs) if "Heartbeat monitor scratch:" in text_of(m)), "")
    idx = holder.rfind("Heartbeat monitor scratch:")
    return {
        "n_msgs": len(msgs),
        "n_tools": len(tools),
        "hb_tool": "heartbeat_respond" in tools,
        "hb_poll": ("[OpenClaw heartbeat poll]" in alltext) or ("Follow the heartbeat monitor scratch" in alltext),
        "scratch_in_prompt": idx >= 0,
        "scratch_excerpt": holder[idx + 26: idx + 26 + 160].strip() if idx >= 0 else None,
        "last_role": last.get("role"),
        "num_ctx": (body.get("options") or {}).get("num_ctx"),
        "req_bytes": len(json.dumps(body)),
    }


def decide(s):
    if s["last_role"] == "tool" or not s["hb_poll"]:
        return "reply-text", {"content": "NO_REPLY"}
    m = mode()
    if m == "text" or not s["hb_tool"]:
        return "hb-text", {"content": "NO_REPLY"}
    args = {"outcome": "no_change", "notify": False, "summary": "Nothing needs attention."}
    if m == "note":
        args["scratch"] = NOTE
    return "hb-respond-" + m, {"content": "", "tool_calls": [{"function": {"name": "heartbeat_respond", "arguments": args}}]}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send_bytes(self, data, ctype="application/json", code=200):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def relay(self, method, raw):
        req = urllib.request.Request(UPSTREAM + self.path, data=raw if method == "POST" else None, method=method,
                                     headers={"Content-Type": self.headers.get("Content-Type", "application/json")})
        try:
            with urllib.request.urlopen(req, timeout=1800) as r:
                return r.status, r.headers.get("Content-Type", "application/json"), r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type", "application/json"), e.read()

    def do_GET(self):
        if UPSTREAM:
            code, ctype, data = self.relay("GET", None)
            log({"method": "GET", "path": self.path, "status": code})
            return self.send_bytes(data, ctype, code)
        log({"method": "GET", "path": self.path})
        if self.path.startswith("/api/tags"):
            return self.send_bytes(json.dumps({"models": [{"name": "mock:latest", "model": "mock:latest", "size": 1,
                                   "digest": "0", "details": {"family": "mock", "parameter_size": "1B"}}]}).encode())
        if self.path.startswith("/api/version"):
            return self.send_bytes(b'{"version":"0.40.16"}')
        return self.send_bytes(b"{}")

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            body = json.loads(raw or b"{}")
        except Exception:
            body = {}
        if not self.path.startswith("/api/chat"):
            if UPSTREAM:
                code, ctype, data = self.relay("POST", raw)
                log({"method": "POST", "path": self.path, "status": code})
                return self.send_bytes(data, ctype, code)
            log({"method": "POST", "path": self.path})
            return self.send_bytes(json.dumps({"model_info": {"general.context_length": 65536},
                                   "capabilities": ["completion", "tools"], "details": {"family": "mock"},
                                   "parameters": ""}).encode())
        s = summarize(body)
        t0 = time.time()
        if UPSTREAM:
            code, ctype, data = self.relay("POST", raw)
            final, content, calls = {}, "", []
            for line in data.decode("utf-8", "replace").splitlines():
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                msg = o.get("message") or {}
                content += msg.get("content") or ""
                calls += msg.get("tool_calls") or []
                if o.get("done"):
                    final = o
            entry = {"method": "POST", "path": self.path, "mode": "relay", "status": code, **s,
                     "secs": round(time.time() - t0, 1), "reply_text": content[:300], "reply_tool_calls": calls,
                     "prompt_eval_count": final.get("prompt_eval_count"), "eval_count": final.get("eval_count"),
                     "done_reason": final.get("done_reason"), "error": None if code == 200 else data[:300].decode("utf-8", "replace")}
            sq = log(entry)
            print(f"[relay] #{sq} {code} hb_poll={s['hb_poll']} scratch_in_prompt={s['scratch_in_prompt']} "
                  f"calls={[c.get('function', {}).get('name') for c in calls]} pe={entry['prompt_eval_count']} {entry['secs']}s", flush=True)
            return self.send_bytes(data, ctype, code)
        kind, msg = decide(s)
        sq = log({"method": "POST", "path": self.path, "mode": "mock", "kind": kind, **s, "reply": msg, "body": body})
        print(f"[mock] #{sq} {kind} hb_poll={s['hb_poll']} hb_tool={s['hb_tool']} scratch_in_prompt={s['scratch_in_prompt']}", flush=True)
        m = {"role": "assistant", "content": msg.get("content", "")}
        if msg.get("tool_calls"):
            m["tool_calls"] = msg["tool_calls"]
        final = {"model": body.get("model", "mock:latest"), "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                 "message": m, "done": True, "done_reason": "stop", "prompt_eval_count": s["req_bytes"] // 4,
                 "eval_count": 1, "prompt_eval_duration": 1, "eval_duration": 1, "total_duration": 2}
        return self.send_bytes((json.dumps(final) + "\n").encode(), "application/x-ndjson")


def summary(path):
    print("seq  time                  kind/status        hb_poll hb_tool scratch_in_prompt  calls  prompt_eval  secs")
    for line in open(path):
        e = json.loads(line)
        if not e.get("path", "").startswith("/api/chat"):
            continue
        calls = e.get("reply_tool_calls") or (e.get("reply") or {}).get("tool_calls") or []
        names = []
        for c in calls:
            f = c.get("function", {})
            a = f.get("arguments") or {}
            if isinstance(a, str):
                try:
                    a = json.loads(a)
                except Exception:
                    a = {}
            names.append(f"{f.get('name')}(outcome={a.get('outcome')},scratch={'yes' if 'scratch' in a else 'no'})")
        print(f"{e['seq']:>3}  {e['t']}  {str(e.get('kind') or e.get('status')):<17}  {str(e['hb_poll']):<7} "
              f"{str(e['hb_tool']):<7} {str(e['scratch_in_prompt']):<18} {';'.join(names) or '-':<6} "
              f"{e.get('prompt_eval_count')}  {e.get('secs', '')}")
        if e.get("scratch_excerpt"):
            print(f"       scratch excerpt: {e['scratch_excerpt'][:120]!r}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "summary":
        summary(sys.argv[2])
    else:
        os.makedirs(os.path.dirname(LOG) or ".", exist_ok=True)
        ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
