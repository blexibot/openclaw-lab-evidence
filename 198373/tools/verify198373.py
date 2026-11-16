#!/usr/bin/env python3
"""Re-derive the decisive #198373 observations from this packet's raw files (Python 3 stdlib only).
Usage (from the packet root):  python3 -I tools/verify198373.py raw/v113 raw/v114
For each tag directory it prints:
  - whether each /api/chat record's req bytes still hash to the req_sha256 the capture proxy recorded;
  - run 1's last request (the first request whose last message is a tool message) and run 2's first request
    (the next one), their tool-message keys and whether either contains "__openclaw" or "runId";
  - the length of the byte-identical prefix of the two serialized requests and where run 1's messages array ends;
  - Ollama's prompt_eval_count / prompt_eval_cached_count from each response's final stream line (uncached is derived);
  - the toolResult message of every cacheTrace record, with its __openclaw value, and run1.json's runId.
"""
import hashlib, json, os, sys


def final_line(resp):
    last = None
    for ln in resp.splitlines():
        try:
            last = json.loads(ln)
        except Exception:
            pass
    return last or {}


def tag(d):
    t = os.path.basename(os.path.normpath(d))
    print(f"===== {t}")
    recs = [json.loads(l) for l in open(os.path.join(d, f"wire-{t}-chat.jsonl"), encoding="utf-8") if l.strip()]
    for r in recs:
        ok = hashlib.sha256(r["req"].encode("utf-8")).hexdigest() == r["req_sha256"]
        print(f"seq={r['seq']} status={r['status']} secs={r['secs']} req_sha256_matches_capture={ok}")
    i = next(k for k, r in enumerate(recs) if json.loads(r["req"])["messages"][-1].get("role") == "tool")
    a, b = recs[i], recs[i + 1]
    for r in (a, b):
        body = json.loads(r["req"])
        tools = [m for m in body["messages"] if m.get("role") == "tool"]
        fl = final_line(r["resp"])
        tot, cac = fl.get("prompt_eval_count"), fl.get("prompt_eval_cached_count")
        print(f"seq={r['seq']} messages={len(body['messages'])} options={body.get('options')} keep_alive={body.get('keep_alive')}")
        for m in tools:
            s = json.dumps(m, ensure_ascii=False)
            print(f"   tool message keys={sorted(m)} contains__openclaw={'__openclaw' in s} contains_runId={'runId' in s}")
            print(f"   {s}")
        print(f"   prompt_eval_count={tot} prompt_eval_cached_count={cac} uncached(derived)={tot - cac if isinstance(tot, int) and isinstance(cac, int) else None}")
    ra, rb = a["req"], b["req"]
    off = next((k for k in range(min(len(ra), len(rb))) if ra[k] != rb[k]), min(len(ra), len(rb)))
    end_msgs = ra.find('],"stream"')
    print(f"byte-identical prefix of seq={a['seq']} and seq={b['seq']}: {off} chars; seq={a['seq']} messages array closes at {end_msgs}")
    print(f"'__openclaw' in seq={a['seq']}: {ra.count('__openclaw')}, in seq={b['seq']}: {rb.count('__openclaw')}; 'runId' occurrences: {ra.count('runId')} / {rb.count('runId')}")
    run1 = json.load(open(os.path.join(d, "run1.json")))["runId"]
    run2 = json.load(open(os.path.join(d, "run2.json")))["runId"]
    print(f"run1.json runId={run1} run2.json runId={run2}")
    for l in open(os.path.join(d, "cache-trace.jsonl"), encoding="utf-8"):
        o = json.loads(l)
        tr = [m for m in (o.get("messages") or []) if isinstance(m, dict) and m.get("role") == "toolResult"]
        if tr:
            m = tr[0]
            who = "run1" if o.get("runId") == run1 else "run2" if o.get("runId") == run2 else "?"
            print(f"trace {who} stage={o.get('stage')} toolResult keys={sorted(m)} __openclaw={m.get('__openclaw')}")


for d in sys.argv[1:]:
    tag(d)
