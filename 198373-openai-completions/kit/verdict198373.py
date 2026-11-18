#!/usr/bin/env python3
"""verdict198373: mechanical pair selection + scoring for #198373 kits (v1 route). Python 3.9 stdlib.
usage: python3 verdict198373.py <wire.jsonl> [lab-stats.json]
Pairs are chosen by rule (never by position), as the order defines:
  run1-last  = last /v1 request whose last_user ends with the run-1 prompt and whose roles include "tool"
  run2-first = first request whose last_user ends "Reply with one word: ready."
  run2-last  = last such request;  run3-first = first request whose last_user ends "Reply with one word: again."
Prints one VERDICT line per pair: VERDICT <pair> pass|fail|null append_only=.. params=.. stamp_keys=.. cached=.. prompt=..
pass = append-only and params identical; fail = not; null = pair not found (no result recorded, never a pass).
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze198373v1 as A  # noqa: E402

RUN1 = ("then reply with its first word only.", "reply with the time only.")
READY, AGAIN = "Reply with one word: ready.", "Reply with one word: again."


def load(path):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        if o.get("path") != A.CHAT:
            continue
        try:
            body = json.loads(o["req"])
        except Exception:
            continue
        msgs = body.get("messages") or []
        out.append({"seq": o.get("seq"), "raw": o["req"], "body": body, "msgs": msgs, "lu": A.last_user(msgs),
                    "roles": [m.get("role") for m in msgs if isinstance(m, dict)], "resp": o.get("resp", "")})
    return out


def usage(resp):
    for o in reversed(A.sse_objects(resp)):
        if isinstance(o.get("usage"), dict):
            u = o["usage"]
            d = u.get("prompt_tokens_details") if isinstance(u.get("prompt_tokens_details"), dict) else {}
            return u.get("prompt_tokens", "absent"), d.get("cached_tokens", "absent")
    return "absent", "absent"


def score(name, a, b):
    if a is None or b is None:
        return "VERDICT %s null reason=pair-not-found" % name
    pm, m = a["msgs"], b["msgs"]
    ch = [i for i in range(min(len(pm), len(m))) if A.ser(pm[i]) != A.ser(m[i])]
    short = len(m) < len(pm)
    pa, pb = A.params(a["body"]), A.params(b["body"])
    pch = [k for k in sorted(set(pa) | set(pb)) if A.ser(pa.get(k)) != A.ser(pb.get(k))]
    ao = "yes" if not ch and not short else "no(first=%s)" % (ch[0] if ch else "fewer-messages")
    prm = "identical" if not pch else "changed(%s)" % ",".join(pch)
    stamps = len(A.KEY_RE.findall(b["raw"]))
    pt, ct = usage(b["resp"])
    word = "pass" if ao == "yes" and not pch else "fail"
    return ("VERDICT %s %s seqs=%s->%s append_only=%s params=%s stamp_keys=%d prompt_tokens=%s cached_tokens=%s"
            % (name, word, a["seq"], b["seq"], ao, prm, stamps, pt, ct))


def main():
    reqs = load(sys.argv[1])
    r1 = [r for r in reqs if r["lu"].endswith(RUN1) and "tool" in r["roles"]]
    r2 = [r for r in reqs if r["lu"].endswith(READY)]
    r3 = [r for r in reqs if r["lu"].endswith(AGAIN)]
    print(score("run1last-run2first", r1[-1] if r1 else None, r2[0] if r2 else None))
    print(score("run2last-run3first(control)", r2[-1] if r2 else None, r3[0] if r3 else None))


if __name__ == "__main__":
    main()
