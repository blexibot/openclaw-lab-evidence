#!/usr/bin/env python3
"""verdict198178: cell status for #198178 kits (v5 driver layout). Python 3.9 stdlib; run by lab-collect on <LAB-MAC-HOST>.
usage: python3 -I verdict198178.py <run>          (<run> = pulled/<run>: <run>/t1/ and <run>/relay/relay.jsonl)
       python3 -I verdict198178.py <tagdir> <relay.jsonl>   (replay on an older layout, e.g. the r2 pull)
Runs an198178.py's verdict (same folder) on the raw files and prints, first, one line per cell:
  VERDICT <cell> pass|fail|blocked|null <the analyzer's own fields>
Cells, in order: c1 (baseline, profile pa), c2, c3-baseline (profile pc), c3, c4-baseline (profile pb), c4.
Status (LAB-TOOLS-SPEC section 5; this is a failure witness, so `fail` = the reported bug was seen):
  baseline cells: pass = baseline=ok (exit 0, a 200 carrying the pinned 8192; a counted retry byte-identical);
                  blocked = still refused after the W5 attempts; fail = ran and did not send 8192 with a 200;
                  null = not run, or borrowed (r1/r2 kits had no c3 baseline).
  rerun cells:    fail = reproduced (row maxTokens changed from 8192; scope says whether the next request sent it);
                  pass = not reproduced under these conditions; blocked = a proxy/relay refusal; null = inconclusive
                  or not run (never a pass).
Then a HINT line (a mechanical suggestion, the worker decides the outcome) and the full analyzer output, each line
prefixed "AN " (WIRE, CFG, DIFF, CTXWIN, PROVFIELDS, SENTINEL, REFUSAL, TOKENS, XCHECK, ...).
"""
import io, os, re, sys
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import an198178 as A  # noqa: E402

CELLS = ("c1", "c2", "c3-baseline", "c3", "c4-baseline", "c4")
BASELINES = ("c1", "c3-baseline", "c4-baseline")


def locate(argv):
    run = argv[1]
    if len(argv) > 2:
        return run, argv[2], run
    tag = os.path.join(run, "t1")
    tagdir = tag if os.path.isdir(tag) else (run if os.path.exists(os.path.join(run, "steps.log")) and
                                             os.path.exists(os.path.join(run, "wire.jsonl")) else None)
    relay = next((p for p in (os.path.join(run, "relay", "relay.jsonl"), os.path.join(run, "J198178r", "relay.jsonl"))
                  if os.path.exists(p)), None)
    return tagdir, relay, run


def markers(*dirs):
    out, seen = [], set()
    for d in dirs:
        if d and os.path.isdir(d) and os.path.realpath(d) not in seen:
            seen.add(os.path.realpath(d))
            out += sorted(n for n in os.listdir(d) if n.startswith("FAILED-"))
    return out


def status(cell, line):
    if cell in BASELINES:
        m = re.search(r"baseline=(\w+) reason=(\S+)", line)
        word, why = (m.group(1), m.group(2)) if m else ("?", "?")
        if word == "ok":
            return "pass"
        if word == "blocked":
            return "blocked"
        if word == "fail" and why != "not-run":
            return "fail"
        return "null"
    m = re.search(r"outcome='([^']*)'", line)
    o = m.group(1) if m else ""
    return {"reproduced": "fail", "not reproduced under these conditions": "pass", "blocked": "blocked"}.get(o, "null")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    tagdir, relay, run = locate(sys.argv)
    marks = markers(run, tagdir)
    if not tagdir:
        why = marks[0] if marks else "no-run-dir"
        word = "blocked" if any(re.match(r"FAILED-(run-FAILED-)?(blocked|relay-budget|hard-stop)", m) for m in marks) \
            else "null"
        for c in CELLS:
            print("VERDICT %s %s reason=no-tag-dir run_marker=%s" % (c, word, why))
        print("HINT outcome=%s (no run data; markers=%s)" % ("blocked" if word == "blocked" else "inconclusive", marks))
        return 0
    buf = io.StringIO()
    with redirect_stdout(buf):
        A.verdict(tagdir, relay)
    out = buf.getvalue().splitlines()
    got = {}
    for line in out:
        m = re.match(r"VERDICT (\S+) (.*)$", line)
        if m and m.group(1) in CELLS and m.group(1) not in got:
            got[m.group(1)] = m.group(2)
    gate = any(re.search(r"FAILED: (blocked|relay-budget|hard-stop)", l) for l in A.readf(
        os.path.join(tagdir, "steps.log")).splitlines()) or any(re.match(r"FAILED-(blocked|relay-budget|hard-stop)", m)
                                                               for m in marks)
    st = {}
    for c in CELLS:
        if c in got:
            st[c] = status(c, got[c])
            if gate and st[c] == "null" and ("reason=not-run" in got[c] or "outcome='not run'" in got[c]):
                st[c] = "blocked"  # not reached because the run stopped at the lab gate
            print("VERDICT %s %s %s" % (c, st[c], got[c]))
        else:
            st[c] = "null"
            print("VERDICT %s null reason=no-analyzer-line" % c)
    reruns = [st[c] for c in ("c2", "c3", "c4")]
    if st["c1"] == "pass" and "fail" in reruns:
        hint = "reproduced"
    elif st["c1"] == "pass" and st["c2"] == "pass" and "fail" not in reruns:
        hint = "not-reproduced"
    elif "blocked" in st.values():
        hint = "blocked"
    else:
        hint = "inconclusive"
    print("HINT outcome=%s c1=%s c2=%s c3=%s c4=%s markers=%s relay_log=%s"
          % (hint, st["c1"], st["c2"], st["c3"], st["c4"], marks or "none", "yes" if relay else "no"))
    for line in out:
        print("AN " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
