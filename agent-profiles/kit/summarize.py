#!/usr/bin/env python3
"""summarize.py <runs dir> [tag...]: VERDICT lines first, then detail.
Footprint tags (mode footprint): per rung, the backend's prompt_eval_count of the first request (model tokenizer,
chat template included), status, and OpenClaw's own budget. Suite tags (results.jsonl): per rung, passes / scored
runs with a Wilson 95% interval, backend-errors counted apart (does-not-fit, never a fail), critical-task failures,
and the median first-request prompt_eval_count. Pre-registered rule for the model's minimum working rung: the
smallest-footprint rung whose passes are at most 2 below the best rung's and that loses no critical task."""
import json, math, os, re, statistics, sys

def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 0.0)
    p = k / n; d = 1 + z * z / n; c = p + z * z / (2 * n); r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (max(0.0, (c - r) / d), min(1.0, (c + r) / d))

root = sys.argv[1]; tags = sys.argv[2:] or sorted(os.listdir(root))
out, detail = [], []
for tag in tags:
    d = os.path.join(root, tag)
    if not os.path.isdir(d): continue
    steps = open(os.path.join(d, "steps.log")).read() if os.path.exists(os.path.join(d, "steps.log")) else ""
    head = re.search(r"model=(\S+) ctx=(\d+)", steps); model, ctx = (head.group(1), head.group(2)) if head else ("?", "?")
    for m in re.finditer(r"\[(R\d)-s(\d+)\] footprint turn rc=(\d+) (.*)", steps):
        rung, seed, rc, rest = m.groups()
        pe = re.search(r"prompt_eval_count=(\S+)", rest); st = re.search(r"status=(\S+)", rest)
        out.append(f"VERDICT footprint {tag} model={model} num_ctx={ctx} {rung} prompt_eval_count={pe.group(1) if pe else None} "
                   f"http={st.group(1) if st else None} rc={rc}")
        detail.append(f"{tag} {rung}: {rest}")
    res = os.path.join(d, "results.jsonl")
    if os.path.exists(res):
        rows = [json.loads(l) for l in open(res) if l.strip()]
        crit = set(["T2", "T4", "T6"])
        by = {}
        for r in rows: by.setdefault(r["label"].split("/")[0], []).append(r)
        summ = {}
        for rung, rs in sorted(by.items()):
            scored = [r for r in rs if r["verdict"] in ("pass", "fail")]; k = sum(r["verdict"] == "pass" for r in scored)
            be = sum(r["verdict"] == "backend-error" for r in rs)
            cf = sorted(set(r["task"] for r in scored if r["task"] in crit and r["verdict"] == "fail"))
            fp = [r["first_prompt_eval_count"] for r in rs if r.get("first_prompt_eval_count")]
            lo, hi = wilson(k, len(scored)); med = int(statistics.median(fp)) if fp else None
            summ[rung] = (k, len(scored), med, cf)
            out.append(f"VERDICT suite {tag} model={model} num_ctx={ctx} {rung} pass={k}/{len(scored)} "
                       f"wilson95=[{lo:.2f},{hi:.2f}] backend_errors={be} critical_failed={cf or 'none'} median_first_prompt_eval={med}")
            per = {}
            for r in rs: per.setdefault(r["task"], []).append(r["verdict"][0])
            detail.append(f"{tag} {rung}: " + " ".join(f"{t}:{''.join(v)}" for t, v in sorted(per.items())))
        if summ:
            best = max(v[0] for v in summ.values())
            ok = [(v[2] or 10**9, r) for r, v in summ.items() if v[0] >= best - 2 and not v[3] and v[1] > 0]
            out.append(f"VERDICT minimum-working-rung {tag} model={model} num_ctx={ctx} "
                       + (f"{min(ok)[1]} first_prompt_eval={min(ok)[0]}" if ok else "none") +
                       " (rule: footprint-smallest rung with passes >= best-2 and no critical-task failure)")
print("\n".join(out)); print("\n".join(detail))
