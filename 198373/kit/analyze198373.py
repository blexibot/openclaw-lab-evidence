#!/usr/bin/env python3
"""Analyzer for openclaw/openclaw#198373. Usage:
  python3 analyze198373.py wire  <wire-TAG.jsonl>        # what OpenClaw really sent to the model (/api/chat bodies)
  python3 analyze198373.py trace <cache-trace.jsonl>     # OpenClaw's own diagnostics.cacheTrace records
  python3 analyze198373.py pair  <wire-TAG.jsonl> <seqA> <seqB>   # compare exactly these two wire requests
For each consecutive pair of model requests it prints: whether the earlier messages were kept unchanged (append-only),
EVERY message index that changed (up to 12) with the first JSON path inside it that differs (so a changed system
message cannot hide a changed tool message further down), the first one's old/new text, the byte offset where the
serialized requests first differ, and how often "__openclaw" / "runId" appear. For wire logs it also prints Ollama's
prompt_eval_count / prompt_eval_cached_count from the response, so uncached = total - cached.
"""
import json, sys


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


def counters(resp):
    last = None
    for line in resp.splitlines():
        try:
            last = json.loads(line)
        except Exception:
            pass
    if not isinstance(last, dict):
        return ""
    tot, cac = last.get("prompt_eval_count"), last.get("prompt_eval_cached_count")
    unc = tot - cac if isinstance(tot, int) and isinstance(cac, int) else None
    ped = last.get("prompt_eval_duration")
    return f"prompt_eval_count={tot} cached={cac} uncached={unc} prompt_eval_s={round(ped/1e9,2) if ped else ped}"


def compare(items):
    prev = None
    for idx, (lab, raw, msgs, extra) in enumerate(items):
        print(f"--- #{idx} {lab} messages={len(msgs)} __openclaw={raw.count('__openclaw')} runId={raw.count('runId')} {extra}")
        roles = [m.get("role") for m in msgs if isinstance(m, dict)]
        print(f"    roles={roles}")
        if prev is not None:
            praw, pmsgs = prev
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
                    if '__openclaw' in ser(msgs[i]) or 'runId' in ser(msgs[i]):
                        print(f"    STAMP: message index {i} has __openclaw/runId in the NEW request "
                              f"(old has it: {'__openclaw' in ser(pmsgs[i]) or 'runId' in ser(pmsgs[i])})")
                print(f"      old: {ser(pmsgs[changed])[:600]}")
                print(f"      new: {ser(msgs[changed])[:600]}")
            off = next((i for i in range(min(len(praw), len(raw))) if praw[i] != raw[i]), min(len(praw), len(raw)))
            print(f"    first differing byte offset of the whole serialized request: {off} of {len(praw)}")
        prev = (raw, msgs)


def last_user(msgs):
    for m in reversed(msgs):
        if isinstance(m, dict) and m.get("role") == "user":
            c = m.get("content")
            return (c if isinstance(c, str) else ser(c))[-60:].replace("\n", " ")
    return ""


def main():
    mode, path = sys.argv[1], sys.argv[2]
    want = [int(x) for x in sys.argv[3:5]] if mode == "pair" else None
    items = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        if mode in ("wire", "pair"):
            if o.get("path") != "/api/chat":
                continue
            if want is not None and o.get("seq") not in want:
                continue
            try:
                body = json.loads(o["req"])
            except Exception:
                continue
            msgs = body.get("messages") or []
            opts = body.get("options") if isinstance(body.get("options"), dict) else {}
            items.append((f"seq={o['seq']} t={o.get('t')} status={o['status']} secs={o['secs']} "
                          f"num_ctx={opts.get('num_ctx')} keep_alive={body.get('keep_alive')} "
                          f"last_user={last_user(msgs)!r}", o["req"], msgs, counters(o.get("resp", ""))))
        else:
            msgs = find_messages(o)
            if msgs is None:
                continue
            items.append((label(o), ser(o), msgs, ""))
    if want is not None and len(items) != 2:
        print(f"pair: expected 2 /api/chat records with seq {want}, found {len(items)}")
    print(f"{mode}: {len(items)} records with messages in {path}")
    compare(items)


if __name__ == "__main__":
    main()
