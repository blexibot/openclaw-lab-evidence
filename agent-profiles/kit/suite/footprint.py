#!/usr/bin/env python3
"""footprint.py <wire.jsonl> <turn.json>: one line: first chat request bytes, the backend's prompt_eval_count (the
model's own tokenizer, chat template included), done_reason or error, and OpenClaw's own budget fields."""
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
chat = [r for r in recs if r.get("method") == "POST" and "/api/chat" in r.get("path", "")]
if not chat: print("no /api/chat request"); sys.exit(0)
r = chat[0]; pe = dr = err = None; dur = {}
for line in (r.get("resp") or "").splitlines():
    try: o = json.loads(line)
    except Exception: continue
    pe = o.get("prompt_eval_count", pe); dr = o.get("done_reason", dr); err = o.get("error", err)
    for k in ("load_duration", "prompt_eval_duration", "total_duration"):
        if k in o: dur[k] = round(o[k] / 1e9, 2)
try: req = json.loads(r["req"]); opts = req.get("options") or {}; top = {k: req.get(k) for k in ("truncate", "shift") if k in req}
except Exception: opts, top = {}, {}
def find(o, k):
    if isinstance(o, dict):
        for a, b in o.items():
            if a == k: return b
            x = find(b, k)
            if x is not None: return x
    if isinstance(o, list):
        for v in o:
            x = find(v, k)
            if x is not None: return x
try: b = find(json.load(open(sys.argv[2])), "contextBudgetStatus") or {}
except Exception: b = {}
print(f"status={r.get('status')} req_bytes={len(r.get('req') or '')} prompt_eval_count={pe} done={dr} error={str(err)[:120] if err else None} "
      f"num_ctx={opts.get('num_ctx')} seed={opts.get('seed')} top={top} oc_route={b.get('route')} oc_estimate={b.get('estimatedPromptTokens')} "
      f"oc_budget={b.get('promptBudgetBeforeReserve')}/{b.get('contextTokenBudget')} oc_remaining={b.get('remainingPromptBudgetTokens')} "
      f"secs_load={dur.get('load_duration')} secs_prefill={dur.get('prompt_eval_duration')} secs_total={dur.get('total_duration')} wall={r.get('secs')}")
