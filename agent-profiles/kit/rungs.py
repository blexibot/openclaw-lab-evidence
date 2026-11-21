#!/usr/bin/env python3
"""rungs.py <base openclaw.json> <out openclaw.json> <rung> <seed> <num_ctx>: write one rung's config.
Every rung pins the model rows' Ollama params (num_ctx, seed, truncate=false so overflow is an error, not a silent
cut). Rungs: R0 stock; R1 Lean (today's experimental.localModelLean, the branch's openclaw/lean); R2 R1 + no skills;
R3 R2 + workspace files capped at 4000 chars in total. Sampling is the model's own default unless MODEL_PARAMS (a JSON
object) is set: v1.2 uses it for the Qwen models' published non-thinking settings, since OpenClaw runs local models with
thinking off and Ollama's Qwen defaults are the thinking-mode ones."""
import json, os, sys
base, out, rung, seed, ctx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
c = json.load(open(base))
for prov in c["models"]["providers"].values():
    for m in prov.get("models", []):
        m["params"] = {**(m.get("params") or {}), **json.loads(os.environ.get("MODEL_PARAMS") or "{}"),
                       "num_ctx": ctx, "seed": seed, "truncate": False}
d = c.setdefault("agents", {}).setdefault("defaults", {})
if rung in ("R1", "R2", "R3"): d.setdefault("experimental", {})["localModelLean"] = True
if rung in ("R2", "R3"): d["skills"] = []
if rung == "R3": d["bootstrapTotalMaxChars"] = 4000
# Agent Profiles branch (openclaw/openclaw#202517, run with OC_BIN_DIR pointing at that build): PB = no profile
# (openclaw/base, the default); PS = agents.defaults.agentProfileId "openclaw/small".
if rung == "PS": d["agentProfileId"] = "openclaw/small"
if rung not in ("R0", "R1", "R2", "R3", "PB", "PS"): sys.exit("unknown rung " + rung)
# v1.2b: NO_SELF_UPDATE=1 turns off the startup update check and auto-update. On 2026-11-20 a model, told at startup that an
# update was available, ran `openclaw update` during a one-word turn and replaced the install mid-matrix.
if os.environ.get("NO_SELF_UPDATE"): c["update"] = {**(c.get("update") or {}), "checkOnStart": False, "auto": {"enabled": False}}
json.dump(c, open(out, "w"), indent=2)
