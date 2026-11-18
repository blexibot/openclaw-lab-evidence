#!/usr/bin/env python3
"""Analyzer for openclaw/openclaw#198373 on the OpenAI-compatible route (api "openai-completions",
POST /v1/chat/completions). Lab only, synthetic prompts. Python 3 stdlib only. Usage:
  python3 analyze198373v1.py wire  <wire-TAG.jsonl> [lab-stats.json]      # every /v1 chat request, consecutive pairs
  python3 analyze198373v1.py pair  <wire-TAG.jsonl> <seqA> <seqB> [lab-stats.json]   # exactly these two requests
  python3 analyze198373v1.py trace <cache-trace.jsonl>                    # OpenClaw's own diagnostics.cacheTrace
For each pair of model requests it prints: whether the earlier messages were kept byte-identical (append-only), EVERY
changed message index (up to 12) with the first JSON path inside it that differs, STAMP lines for __openclaw/runId,
the byte offset where the two serialized requests first differ, and PARAMS lines for every top-level field other than
"messages" that differs (tools and their order, tool_choice, max_tokens, stream_options, model, sampling fields).
For each request it prints the backend counters taken from the response itself (the streamed "usage" chunk:
prompt_tokens, completion_tokens, prompt_tokens_details.cached_tokens when present) and, when a lab-stats file is
given, the filter's /lab/stats record matched by X-Lab-Request-Id (never by position). A counter the backend did not
report is printed as "absent", never as 0.
"""
import json, re, sys

# Only JSON KEYS count as a stamp. OpenClaw 2026.11.4's system prompt contains the prose "runIds"/"runId" (subagents
# tool text), so a plain substring count would flag every request.
KEY_RE = re.compile(r'"(__openclaw|runId)"\s*:')

CHAT = "/v1/chat/completions"


def ser(x):
    return json.dumps(x, ensure_ascii=False, separators=(",", ":"))


def first_path(a, b, path="$"):
    if type(a) != type(b):
        return path
    if isinstance(a, dict):
        for k in list(a) + [k for k in b if k not in a]:
            if k not in a or k not in b:
                return f"{path}.{k} (only in {'new' if k in b else 'old'})"
            p = first_path(a[k], b[k], f"{path}.{k}")
            if p:
                return p
        return None
    if isinstance(a, list):
        for i in range(min(len(a), len(b))):
            p = first_path(a[i], b[i], f"{path}[{i}]")
            if p:
                return p
        return None if len(a) == len(b) else f"{path} (length {len(a)} -> {len(b)})"
    return None if a == b else path


def find_messages(o):
    if isinstance(o, dict):
        if isinstance(o.get("messages"), list):
            return o["messages"]
        for v in o.values():
            m = find_messages(v)
            if m is not None:
                return m
    elif isinstance(o, list):
        for v in o:
            m = find_messages(v)
            if m is not None:
                return m
    return None


def label(o):
    for k in ("stage", "event", "type", "kind", "phase", "name"):
        if isinstance(o, dict) and isinstance(o.get(k), str):
            return f"{k}={o[k]}"
    return "?"


def sse_objects(resp):
    """JSON objects from an SSE body ("data: {...}" lines) or a plain JSON body."""
    out = []
    for line in resp.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            d = line[5:].strip()
            if d and d != "[DONE]":
                try:
                    out.append(json.loads(d))
                except Exception:
                    pass
    if not out:
        try:
            o = json.loads(resp)
            if isinstance(o, dict):
                out.append(o)
        except Exception:
            pass
    return out


def resp_summary(resp):
    objs = sse_objects(resp)
    usage = None
    for o in objs:
        if isinstance(o.get("usage"), dict):
            usage = o["usage"]
    ids, names, finish, text = [], [], None, ""
    for o in objs:
        for ch in o.get("choices") or []:
            if not isinstance(ch, dict):
                continue
            finish = ch.get("finish_reason") or finish
            d = ch.get("delta") or ch.get("message") or {}
            if isinstance(d.get("content"), str):
                text += d["content"]
            for tc in d.get("tool_calls") or []:
                if isinstance(tc, dict):
                    if tc.get("id"):
                        ids.append(tc["id"])
                    fn = tc.get("function") or {}
                    if fn.get("name"):
                        names.append(fn["name"])
    if usage is None:
        u = "usage=absent"
    else:
        det = usage.get("prompt_tokens_details") if isinstance(usage.get("prompt_tokens_details"), dict) else {}
        cached = det.get("cached_tokens", "absent")
        pt = usage.get("prompt_tokens")
        unc = pt - cached if isinstance(pt, int) and isinstance(cached, int) else "n/a"
        u = (f"prompt_tokens={pt} completion_tokens={usage.get('completion_tokens')} cached_tokens={cached} "
             f"uncached={unc} usage_keys={sorted(usage)}")
    return (f"{u} finish={finish} tool_call_ids={ids} tool_names={names} text={text[:60]!r}")


def load_stats(path):
    if not path:
        return {}
    try:
        o = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        print(f"lab-stats: unreadable ({type(e).__name__})")
        return {}
    recs = o.get("records") if isinstance(o, dict) else o
    if isinstance(o, dict) and recs is None:
        for v in o.values():
            if isinstance(v, list):
                recs = v
                break
    return {r.get("id"): r for r in (recs or []) if isinstance(r, dict) and r.get("id")}


def stats_line(rec, stats):
    rid = (rec.get("resp_headers") or {}).get("X-Lab-Request-Id")
    if not stats:
        return f"lab_request_id={rid}"
    r = stats.get(rid)
    if r is None:
        return f"lab_request_id={rid} lab_stats=not-found"
    keep = {k: r[k] for k in r if k not in ("id",)}
    return f"lab_request_id={rid} lab_stats={ser(keep)}"


def params(body):
    return {k: v for k, v in body.items() if k != "messages"}


def compare(items):
    prev = None
    for idx, (lab, raw, msgs, extra, body) in enumerate(items):
        print(f"--- #{idx} {lab} messages={len(msgs)} stamp_keys={len(KEY_RE.findall(raw))} (JSON keys __openclaw/runId)")
        print(f"    {extra}")
        roles = [m.get("role") for m in msgs if isinstance(m, dict)]
        print(f"    roles={roles}")
        tcids = [(i, m.get("tool_call_id")) for i, m in enumerate(msgs) if isinstance(m, dict) and m.get("role") == "tool"]
        acids = [(i, [tc.get("id") for tc in (m.get("tool_calls") or []) if isinstance(tc, dict)])
                 for i, m in enumerate(msgs) if isinstance(m, dict) and m.get("tool_calls")]
        if tcids or acids:
            print(f"    assistant tool_call ids={acids} tool_call_id on tool messages={tcids}")
        if prev is not None:
            praw, pmsgs, pbody = prev
            n = min(len(pmsgs), len(msgs))
            allch = [i for i in range(n) if ser(pmsgs[i]) != ser(msgs[i])]
            if len(msgs) < len(pmsgs):
                print(f"    NOTE: this request has FEWER messages ({len(msgs)}) than the previous one ({len(pmsgs)})")
            if not allch:
                print(f"    APPEND-ONLY vs previous: yes (previous {len(pmsgs)} messages kept byte-identical)")
            else:
                changed = allch[0]
                print(f"    APPEND-ONLY vs previous: NO. first changed message index {changed} "
                      f"(role {pmsgs[changed].get('role') if isinstance(pmsgs[changed], dict) else '?'}); "
                      f"first differing path: {first_path(pmsgs[changed], msgs[changed], f'messages[{changed}]')}")
                for i in allch[:12]:
                    r = pmsgs[i].get('role') if isinstance(pmsgs[i], dict) else '?'
                    print(f"    changed message index {i} (role {r}): {first_path(pmsgs[i], msgs[i], f'messages[{i}]')}")
                for i in allch[:12]:
                    if KEY_RE.search(ser(msgs[i])):
                        print(f"    STAMP: message index {i} has a JSON key __openclaw/runId in the NEW request "
                              f"(old has it: {bool(KEY_RE.search(ser(pmsgs[i])))})")
                print(f"      old: {ser(pmsgs[changed])[:600]}")
                print(f"      new: {ser(msgs[changed])[:600]}")
            pa, pb = params(pbody), params(body)
            pch = [k for k in sorted(set(pa) | set(pb)) if ser(pa.get(k)) != ser(pb.get(k))]
            if not pch:
                print("    PARAMS vs previous: identical (every top-level field other than messages)")
            for k in pch:
                if k == "tools":
                    ta = [t.get("function", {}).get("name") for t in (pa.get(k) or []) if isinstance(t, dict)]
                    tb = [t.get("function", {}).get("name") for t in (pb.get(k) or []) if isinstance(t, dict)]
                    print(f"    PARAMS changed: tools (names/order {ta} -> {tb}; first path "
                          f"{first_path(pa.get(k), pb.get(k), 'tools')})")
                else:
                    print(f"    PARAMS changed: {k}: {ser(pa.get(k))[:200]} -> {ser(pb.get(k))[:200]}")
            off = next((i for i in range(min(len(praw), len(raw))) if praw[i] != raw[i]), min(len(praw), len(raw)))
            print(f"    first differing byte offset of the whole serialized request: {off} of {len(praw)}")
        prev = (raw, msgs, body)


def last_user(msgs):
    """The last user prompt, skipping OpenClaw's trailing "OpenClaw runtime context:" user message and the
    "Runtime: ..." line it appends to a prompt (both seen in the 2026.11.4 dry run)."""
    for m in reversed(msgs):
        if isinstance(m, dict) and m.get("role") == "user":
            c = m.get("content")
            c = c if isinstance(c, str) else ser(c)
            if c.startswith("OpenClaw runtime context"):
                continue
            return c.split("\n\nRuntime:", 1)[0][-70:].replace("\n", " ")
    return ""


def main():
    mode, path = sys.argv[1], sys.argv[2]
    want = [int(x) for x in sys.argv[3:5]] if mode == "pair" else None
    stats_path = (sys.argv[5] if len(sys.argv) > 5 else None) if mode == "pair" else (sys.argv[3] if len(sys.argv) > 3 else None)
    stats = load_stats(stats_path) if mode in ("wire", "pair") else {}
    items, other = [], []
    prev_t = None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        if mode in ("wire", "pair"):
            if o.get("path") != CHAT:
                other.append(f"seq={o.get('seq')} {o.get('method')} {o.get('path')} status={o.get('status')}")
                continue
            if want is not None and o.get("seq") not in want:
                continue
            try:
                body = json.loads(o["req"])
            except Exception:
                continue
            msgs = body.get("messages") or []
            gap = round(o["t"] - prev_t, 1) if isinstance(o.get("t"), (int, float)) and prev_t is not None else None
            prev_t = o.get("t") if isinstance(o.get("t"), (int, float)) else prev_t
            items.append((f"seq={o['seq']} t={o.get('t')} gap_s={gap} status={o['status']} secs={o['secs']} "
                          f"stream={body.get('stream')} max_tokens={body.get('max_tokens')} "
                          f"last_user={last_user(msgs)!r}",
                          o["req"], msgs,
                          f"{resp_summary(o.get('resp', ''))} {stats_line(o, stats)}", body))
        else:
            msgs = find_messages(o)
            if msgs is None:
                continue
            items.append((label(o), ser(o), msgs, "", {}))
    if want is not None and len(items) != 2:
        print(f"pair: expected 2 {CHAT} records with seq {want}, found {len(items)}")
    print(f"{mode}: {len(items)} records with messages in {path}")
    for x in other:
        print(f"other request: {x}")
    compare(items)


if __name__ == "__main__":
    main()
