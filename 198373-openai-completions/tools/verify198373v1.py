#!/usr/bin/env python3
"""Re-derive the decisive #198373 (openai-completions) observations from this packet's raw files.
Python 3 standard library only. Usage, from the packet root:

    python3 -I -B tools/verify198373v1.py raw/v114 raw/v115

The tag (v114, v115) is the folder name; file names inside follow it (wire-<tag>.jsonl, lab-stats-<tag>.json,
gw-<tag>.log). For each folder it prints, from that folder only:
  - whether every captured request body still hashes to the req_sha256 the capture proxy recorded;
  - the pairs, located by the last real user prompt (not by position): run 1 last -> run 2 first, and the
    control run 2 last -> run 3 first;
  - for each pair: the byte-identical prefix length, where the earlier request's messages array closes, whether the
    earlier messages are equal as parsed JSON, and which top-level fields other than messages differ;
  - JSON-key counts of "__openclaw" / "runId" in every request body (the plain word "runId" also occurs in a tool
    description in the system prompt; that is not a key);
  - the tool-call id the model returned (from the response stream) and the ids OpenClaw replayed;
  - usage.prompt_tokens / prompt_tokens_details.cached_tokens from each response's final stream chunk, the matching
    filter record in lab-stats by X-Lab-Request-Id, and any filter record between the two requests of each pair;
  - per cache-trace record of the cache-repro session: the assistant tool-call id and the toolResult keys/__openclaw;
  - run 1's last vs run 2's first stream:context record, message by message (as parsed JSON, keys sorted);
  - per cache-trace record of the cache-repro session that has no messages: the cache:state / cache:result fields
    (prefixUnchanged, changes, broke, promptTokens, input, cacheRead) and the snapshot's modelApi / streamStrategy;
  - the gateway's [prompt-cache] lines;
  - the steps.log config read-backs, preflight line, turn lines and tool-result check.
Trace records are numbered by their 0-based index in cache-trace.jsonl ("record N" is file line N+1). The kit's own
analyzer numbers only records that carry messages, so its #13 and #20 are records 18 and 27 here.
Offsets are given in characters of the decoded body and in UTF-8 bytes (the bodies contain non-ASCII characters).
"""
import datetime, hashlib, json, os, re, sys


def usage_of(resp):
    u = None
    for ln in resp.splitlines():
        if ln.startswith("data: {"):
            try:
                o = json.loads(ln[6:])
            except Exception:
                continue
            if o.get("usage"):
                u = o["usage"]
    return u or {}


def last_prompt(body):
    for m in reversed(body["messages"]):
        c = m.get("content")
        if m.get("role") == "user" and isinstance(c, str) and not c.startswith("OpenClaw runtime context:"):
            return c
    return ""


def keycount(s):
    return s.count('"__openclaw":'), s.count('"runId":')


def main(d):
    tag = os.path.basename(os.path.normpath(d))
    print(f"######## {d} (tag {tag})")
    recs = [json.loads(l) for l in open(os.path.join(d, f"wire-{tag}.jsonl"), encoding="utf-8") if l.strip()]
    stats = json.load(open(os.path.join(d, f"lab-stats-{tag}.json"), encoding="utf-8"))["records"]
    sid = {s["id"]: s for s in stats}
    chat = []
    for r in recs:
        ok = hashlib.sha256(r["req"].encode("utf-8")).hexdigest() == r["req_sha256"]
        lid = (r.get("resp_headers") or {}).get("X-Lab-Request-Id")
        t = datetime.datetime.fromtimestamp(r["t"], datetime.timezone.utc).isoformat(timespec="milliseconds")
        line = (f"seq={r['seq']} t={t} {r['method']} {r['path']} status={r['status']} secs={r['secs']} lab_request_id={lid}"
                f" req_sha256_matches_capture={ok} req_utf8_bytes={len(r['req'].encode('utf-8'))}"
                f" filter.bytes={sid.get(lid, {}).get('bytes')}")
        if r["path"] == "/v1/chat/completions" and r["req"]:
            b = json.loads(r["req"])
            u = usage_of(r["resp"])
            det = u.get("prompt_tokens_details") or {}
            st = sid.get(lid, {})
            line += (f" messages={len(b['messages'])} keys(__openclaw,runId)={keycount(r['req'])}"
                     f" usage.prompt_tokens={u.get('prompt_tokens')} cached_tokens={det.get('cached_tokens')}"
                     f" completion_tokens={u.get('completion_tokens')}"
                     f" filter.prompt_tokens={st.get('prompt_tokens')} filter.cached_tokens={st.get('cached_tokens')}"
                     f" keep_alive_key={'keep_alive' in b} reasoning_effort_key={'reasoning_effort' in b}"
                     f" last_prompt={last_prompt(b).split(chr(10))[0][-60:]!r}")
            chat.append((r, b, lid))
        print(line)

    def first(sfx):
        return next(x for x in chat if sfx in last_prompt(x[1]))

    def last(sfx, need_tool=False):
        return [x for x in chat if sfx in last_prompt(x[1]) and (not need_tool or any(m.get("role") == "tool" for m in x[1]["messages"]))][-1]

    r1last = last("then reply with its first word only.", need_tool=True)
    r2first, r2last, r3first = first("Reply with one word: ready."), last("Reply with one word: ready."), first("Reply with one word: again.")
    for name, (a, ab, alid), (b, bb, blid) in (("run1 last -> run2 first", r1last, r2first), ("control: run2 last -> run3 first", r2last, r3first)):
        ra, rb = a["req"], b["req"]
        off = next((k for k in range(min(len(ra), len(rb))) if ra[k] != rb[k]), min(len(ra), len(rb)))
        close = ra.rfind('],"stream"')
        n = len(ab["messages"])
        same_msgs = ab["messages"] == bb["messages"][:n]
        params = sorted(k for k in set(ab) | set(bb) if k != "messages" and ab.get(k) != bb.get(k))
        print(f"== {name}: seq={a['seq']} -> seq={b['seq']}")
        print(f"   byte-identical prefix {off} chars = {len(ra[:off].encode('utf-8'))} UTF-8 bytes; seq={a['seq']} messages array"
              f" closes at char {close}; total {len(ra)} / {len(rb)} chars")
        print(f"   earlier {n} messages equal as JSON: {same_msgs}; top-level fields differing (excluding messages): {params or 'none'}")
        print(f"   tools: {[t['function']['name'] for t in bb['tools']]}")
        print(f"   max_tokens={bb.get('max_tokens')} stream_options={bb.get('stream_options')} model={bb.get('model')}")
        between = [s for s in stats if alid and blid and s["t"] > sid[alid]["t"] and s["t"] < sid[blid]["t"]]
        print(f"   filter records strictly between {alid} and {blid}: {len(between)}")
        for m in bb["messages"][:n]:
            if m.get("role") == "assistant" and m.get("tool_calls"):
                print(f"   replayed assistant tool_calls ids: {[c['id'] for c in m['tool_calls']]}")
            if m.get("role") == "tool":
                print(f"   replayed tool message keys={sorted(m)} tool_call_id={m.get('tool_call_id')}")
    for r, b, lid in chat:
        ids = sorted(set(re.findall(r'"tool_calls":\[\{"id":"([^"]+)"', r["resp"])))
        if ids:
            print(f"model-returned tool_call ids in seq={r['seq']} response stream: {ids}")

    runs = {}
    for f in ("run1", "run2", "run3"):
        runs[json.load(open(os.path.join(d, f + ".json"), encoding="utf-8"))["runId"]] = f
    print(f"runIds: {runs}")
    for i, l in enumerate(open(os.path.join(d, "cache-trace.jsonl"), encoding="utf-8")):
        o = json.loads(l)
        if o.get("sessionKey") != "agent:main:cache-repro":
            continue
        if not o.get("messages"):
            opt = o.get("options") or {}
            if o.get("stage", "").startswith("cache:"):
                snap = opt.get("snapshot") or {}
                f = {k: opt.get(k) for k in ("prefixUnchanged", "changes", "broke", "promptTokens", "input", "cacheRead") if k in opt}
                print(f"record {i} (line {i + 1}) {runs.get(o.get('runId'), '?')} {o.get('stage')} seq={o.get('seq')}: {json.dumps(f)}"
                      + (f" modelApi={snap.get('modelApi')} streamStrategy={snap.get('streamStrategy')}" if snap else ""))
            continue
        out = []
        for j, m in enumerate(o["messages"]):
            if not isinstance(m, dict):
                continue
            if m.get("role") == "assistant" and isinstance(m.get("content"), list):
                for c in m["content"]:
                    if c.get("type") == "toolCall":
                        out.append(f"msg{j} assistant toolCall id={c['id']}")
            if m.get("role") == "toolResult":
                out.append(f"msg{j} toolResult toolCallId={m.get('toolCallId')} keys={sorted(m)} __openclaw={m.get('__openclaw')}")
        print(f"record {i} (line {i + 1}) {runs.get(o.get('runId'), '?')} {o.get('stage')} seq={o.get('seq')}: " + "; ".join(out))
    # run 1's last stream:context vs run 2's first stream:context: compare the replayed assistant and toolResult
    ctx = [json.loads(l) for l in open(os.path.join(d, "cache-trace.jsonl"), encoding="utf-8")]
    ctx = [o for o in ctx if o.get("sessionKey") == "agent:main:cache-repro" and o.get("stage") == "stream:context"]
    a = [o for o in ctx if runs.get(o.get("runId")) == "run1"][-1]["messages"]
    b = [o for o in ctx if runs.get(o.get("runId")) == "run2"][0]["messages"]
    for j in range(len(a)):
        x, y = a[j], dict(b[j])
        if not isinstance(x, dict):
            continue
        same = json.dumps(x, sort_keys=True) == json.dumps(y, sort_keys=True)
        y.pop("__openclaw", None) if "__openclaw" not in x else None
        same_wo = json.dumps(x, sort_keys=True) == json.dumps(y, sort_keys=True)
        print(f"stream:context run1-last vs run2-first msg{j} role={x.get('role')}: identical={same}; identical ignoring a newly added __openclaw={same_wo}")
    # the replayed toolResult in every stream:context record of the session, as parsed JSON (keys sorted)
    first_stamp = None
    for i, l in enumerate(open(os.path.join(d, "cache-trace.jsonl"), encoding="utf-8")):
        o = json.loads(l)
        if o.get("sessionKey") != "agent:main:cache-repro" or not o.get("messages"):
            continue
        for m in o["messages"]:
            if isinstance(m, dict) and m.get("role") == "toolResult":
                if first_stamp is None and "__openclaw" in m:
                    first_stamp = (i, o.get("stage"), runs.get(o.get("runId"), "?"))
                if o.get("stage") == "stream:context":
                    h = hashlib.sha256(json.dumps(m, sort_keys=True).encode("utf-8")).hexdigest()[:16]
                    print(f"stream:context record {i} {runs.get(o.get('runId'), '?')}: toolResult sha256(sorted JSON)[:16]={h}"
                          f" has __openclaw={'__openclaw' in m}")
    print(f"first cache-trace record whose toolResult carries __openclaw: {first_stamp}")
    pc = [l.rstrip() for l in open(os.path.join(d, f"gw-{tag}.log"), encoding="utf-8") if "[prompt-cache]" in l]
    for l in pc:
        print("gateway: " + l)
    print(f"gateway [prompt-cache] lines: {len(pc)}")
    for l in open(os.path.join(d, "steps.log"), encoding="utf-8"):
        if any(k in l for k in (" config ", "cacheTrace read back", "PREFLIGHT", "tool result seen", "turn ")):
            print("steps: " + l.rstrip())


if __name__ == "__main__":
    for d in sys.argv[1:] or ["raw/v114"]:
        main(d)
