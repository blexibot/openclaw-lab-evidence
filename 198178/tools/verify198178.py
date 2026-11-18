#!/usr/bin/env python3
"""Replay check for the openclaw/openclaw#198178 packet (Python 3 stdlib only).

Run from the packet root:  python3 -I tools/verify198178.py          (2026.11.4 run, raw/t1 + raw/relay)
                           python3 -I tools/verify198178.py v115     (2026.11.5 run, raw/v115/t1 + raw/v115/relay)
Re-derives, from the raw files in this packet only:
  1. each captured request body still hashes to the req_sha256 the in-bench logger wrote at capture time;
  2. the output cap OpenClaw put on every chat POST (bench capture) and the same body seen by the host relay;
  3. the pinned row / provider fields in each config snapshot, per profile;
  4. (2026.11.4 only) the lab proxy's records in the relay window against the relay's POSTs (status, in/out usage);
  5. (v115 only) the in-bench manifest raw/v115/t1/evidence.sha256 against the published copies (the one withheld
     line, shim.log, is counted and skipped).
Prints a short table; exits 1 if any check fails.
"""
import hashlib, json, os, sys, datetime

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN = sys.argv[1] if len(sys.argv) > 1 else ""
if RUN not in ("", "v115"):
    sys.exit("usage: verify198178.py [v115]")
R = lambda *p: os.path.join(root, "raw", RUN, *p) if RUN else os.path.join(root, "raw", *p)
fail = []

def jl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]

def cap(body):
    if not body:
        return None
    o = json.loads(body)
    for k in ("max_completion_tokens", "max_tokens"):
        if k in o:
            return k, o[k]
    return None

def usage(resp):
    u = None
    for line in (resp or "").splitlines():
        if line.startswith("data: {"):
            d = json.loads(line[6:])
            if d.get("usage"):
                u = d["usage"]
    return u

# 1 + 2: bench capture and relay
wire = jl(R("t1", "wire.jsonl"))
relay = jl(R("relay", "relay.jsonl"))
unused = [r for r in relay if r["method"] == "POST"]  # matched in order: identical bodies (a retry) repeat a hash
print("seq  bench step-time(UTC)  status  cap OpenClaw sent            relay: same body  forwarded cap  usage in/out")
for w in wire:
    got = hashlib.sha256(w["req"].encode("utf-8")).hexdigest()
    if got != w["req_sha256"]:
        fail.append("wire seq %s body hash mismatch" % w["seq"])
    if w["method"] != "POST":
        continue
    r = next((x for x in unused if x["req_sha256"] == w["req_sha256"]), None)
    if r is not None:
        unused.remove(r)
    if r is None:
        fail.append("wire seq %s not seen by relay" % w["seq"])
        continue
    if r["req"] != w["req"]:
        fail.append("wire seq %s relay body differs" % w["seq"])
    u = usage(r["resp"])
    t = datetime.datetime.fromtimestamp(w["t"], datetime.timezone.utc).strftime("%H:%M:%S")
    print("%-4s %-19s %-7s %-28s %-17s %-14s %s" % (
        w["seq"], t, w["status"], cap(w["req"]), r["req"] == w["req"], r.get("fwd_caps"),
        "%s/%s" % (u["prompt_tokens"], u["completion_tokens"]) if u else "-"))

if unused:
    fail.append("relay POSTs with no bench capture: %s" % [x["seq"] for x in unused])

# 3: config snapshots
print("\nprofile snapshot                      row.maxTokens row.contextWindow prov.maxTokens prov.timeoutSeconds prov.apiKey")
for prof in ("pa", "pc", "pb"):
    for fn in sorted(os.listdir(R("t1", prof))):
        if not (fn.startswith("cfg-") and fn.endswith(".json")):
            continue
        with open(R("t1", prof, fn), encoding="utf-8") as f:
            c = json.load(f)
        p = c["models"]["providers"]["sglang"]
        row = p["models"][0]
        print("%-7s %-30s %-13s %-17s %-14s %-19s %s" % (
            prof, fn, row.get("maxTokens"), row.get("contextWindow"), p.get("maxTokens", "<absent>"),
            p.get("timeoutSeconds", "<absent>"), p.get("apiKey", "<absent>")))

if RUN == "v115":
    # 5: in-bench manifest against the published copies
    ok = withheld = 0
    with open(R("t1", "evidence.sha256"), encoding="utf-8") as f:
        for line in f:
            h, name = line.rstrip("\n").split("  ", 1)
            if h == "<WITHHELD-ORIGINAL-HASH>":
                withheld += 1
                continue
            with open(R("t1", name[2:]), "rb") as g:
                if hashlib.sha256(g.read()).hexdigest() == h:
                    ok += 1
                else:
                    fail.append("t1/%s differs from evidence.sha256" % name[2:])
    print("\nin-bench manifest raw/v115/t1/evidence.sha256: %d OK, %d withheld (not checkable here)" % (ok, withheld))
    print("lab proxy cross-check: not available for this run (no proxy log extract in the packet)")
    print("\nRESULT", "FAIL: " + "; ".join(fail) if fail else "OK: all checks passed")
    sys.exit(1 if fail else 0)

# 4: lab proxy window vs relay POSTs
px = [d for d in jl(R("server", "proxy-window.jsonl")) if d.get("caller") == "<LAB-LINUX-HOST>"]
rp = [r for r in relay if r["method"] == "POST"]
print("\nrelay POST (UTC)   status  usage in/out  |  lab proxy record (UTC)  status  in/out")
if len(px) != len(rp):
    fail.append("proxy has %d <LAB-LINUX-HOST> records in the window, relay has %d POSTs" % (len(px), len(rp)))
for r, p in zip(rp, px):
    u = usage(r["resp"])
    rt = datetime.datetime.fromtimestamp(r["t"], datetime.timezone.utc)
    pt = datetime.datetime.fromisoformat(p["t"])
    ok = (r["status"] == p["status"] and abs((pt - rt).total_seconds()) <= 3 and
          ((u is None and "in" not in p) or (u and u["prompt_tokens"] == p.get("in") and u["completion_tokens"] == p.get("out"))))
    if not ok:
        fail.append("relay seq %s vs proxy %s differ" % (r["seq"], p["t"]))
    print("%-18s %-7s %-13s |  %-22s %-7s %s" % (
        rt.strftime("%H:%M:%S.%f")[:12], r["status"], "%s/%s" % (u["prompt_tokens"], u["completion_tokens"]) if u else "-",
        p["t"][11:19], p["status"], "%s/%s" % (p.get("in"), p.get("out")) if "in" in p else p.get("reason")))

print("\nRESULT", "FAIL: " + "; ".join(fail) if fail else "OK: all checks passed")
sys.exit(1 if fail else 0)
