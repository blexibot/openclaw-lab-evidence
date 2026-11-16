# trace-extract.py <cache-trace.jsonl>: for each stream:context record, list messages (index, role) and the
# runtime-context flags OpenClaw attached to carrier messages. Derived view; read-only.
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    d = json.loads(line)
    if d.get("stage") != "stream:context":
        continue
    out = []
    for i, m in enumerate(d.get("messages") or []):
        c = m.get("content")
        text = c if isinstance(c, str) else "".join(p.get("text", "") for p in c if isinstance(p, dict)) if isinstance(c, list) else ""
        flags = {k: m[k] for k in ("runtimeContextCarrier", "runtimeContextCarrierRetained", "runtimeContext") if k in m}
        is_carrier = text.startswith("OpenClaw runtime context:")
        out.append(f"[{i}] {m.get('role')}" + (f" CARRIER {json.dumps(flags, sort_keys=True)}" if is_carrier or flags else ""))
    print(f"run={d.get('runId','')[:8]} seq={d.get('seq')} modelApi={d.get('modelApi')} messageCount={d.get('messageCount')} :: " + "; ".join(out))
