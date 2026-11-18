#!/usr/bin/python3 -I
# c198830.py (<LAB-HOST>, controller side; run with /usr/bin/python3 -I). Helpers for T198830 that must stay OUTSIDE the
# guest, so the oracle is computed by the controller:
#   corpus <outdir> <nonce>          write the synthetic corpus (ws-full, ws-prose), queries.tsv, expected.txt, alt.txt;
#                                    prints CORPUS lines (file names, sizes, sha256, expected files/chunks, overlap check)
#   chunks <file>                    expected chunk count for one file (port of OpenClaw 2026.11.x markdown-chunks.ts,
#                                    ASCII text, tokens=400 overlap=80, i.e. maxChars=1600 overlapChars=320)
#   sup <sup.jsonl> <t0> <t1>        host-memory peaks between two UTC epochs (from the host supervisor's samples)
#   ranks <m-cell.txt> <expected.txt> rank of each sentinel file in that cell's SR lines (1 = top; none = absent)
#   livesum <live.txt> <tag>         PX/RTSUM lines rebuilt from the host-side live tail of the guest's proxy.jsonl and
#                                    LM Studio logs (used only when the VM died before the cell printed its own lines)
# All content is synthetic. Nothing here talks to the network or the guest.
import hashlib, json, os, random, re, sys

SENT = {
    "A": "The lighthouse keeper polished the brass lantern every evening before fishing boats returned to harbor.",
    "B": "Grandmother baked rye bread with caraway seeds inside her wood-fired oven.",
    "C": "Volcanic ash drifted across the glacier and darkened the snowfield for weeks.",
    "D": "The orchestra tuned their violins while the conductor waited beside the podium.",
}
# Paraphrase queries: they must share no word (and no word prefix) with ANY corpus file, because OpenClaw's hybrid
# search (vector 0.7 / FTS 0.3, hard-coded) would otherwise surface a truncated chunk lexically.
QUERY = {
    "A": "coastal beacon caretaker cleaning metal lamp during dusk",
    "B": "elderly relative making loaves using spice kernels near timber stove",
    "C": "eruption dust blew onto ice sheet turning frozen terrain grey",
    "D": "symphony players adjusting fiddles; maestro stood near lectern",
}
# Alternative sentence for the direct truncation probe: swapped in at the same position as B's or C's sentence.
ALT = "Copper kettles whistled loudly when morning tea was finally ready upstairs."
ITEMS = ["bolts", "hinges", "washers", "brackets", "gaskets", "rivets", "clamps", "spools"]
COLORS = ["green", "yellow", "orange", "purple"]
DIGITS = 1350  # digits on the long line: Qwen tokenizes digits one per token, so about 1350 tokens (> 1024, < 2048)
# Token floor for "full coverage" of a B/C probe input: the digits alone are DIGITS tokens; the sentence adds ~12-16.
# A prompt_tokens count below this floor means LM Studio did not embed the whole input.
TOKENS_MIN = DIGITS + 8


def toks(s):
    return re.findall(r"[a-z0-9]+", s.lower())


def filler_line(rng):
    return "Shelf %d in aisle %d holds %d cartons of %s labelled %s." % (
        rng.randint(1, 99), rng.randint(1, 40), rng.randint(2, 900), rng.choice(ITEMS), rng.choice(COLORS))


def est_tail(line, budget):
    return line[len(line) - budget:] if budget > 0 and budget < len(line) else (line if budget >= len(line) else "")


def chunk_count(text):
    """Port of createMarkdownChunker/chunkMarkdown (perEntry=false) for ASCII text whose lines are < 1600 chars."""
    maxc, ov = 1600, 320
    cur, cc, n = [], 0, 0
    def carry(window):
        nonlocal cur, cc
        if window <= 0 or not cur:
            cur, cc = [], 0
            return
        acc, kept = 0, []
        for line in reversed(cur):
            size = len(line) + 1
            rem = window - acc
            if size > rem:
                if not kept:
                    tail = est_tail(line, rem - 1)
                    if tail:
                        kept.insert(0, tail)
                        acc += len(tail) + 1
                break
            acc += size
            kept.insert(0, line)
            if acc >= window:
                break
        cur, cc = kept, acc
    for line in text.split("\n"):
        if len(line) >= maxc:
            raise SystemExit("chunk oracle: line too long for this port")
        size = len(line) + 1
        if cc + size > maxc and cur:
            n += 1
            carry(min(ov, max(0, maxc - size)))
        cur.append(line)
        cc += size
    if cur:
        n += 1
    return n


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="ascii") as f:
        f.write(text)  # no trailing newline on purpose (keeps the chunk oracle simple)


def corpus(outdir, nonce):
    rng = random.Random(int(nonce, 16))
    tag = nonce[:8]
    digits = "".join(rng.choice("0123456789") for _ in range(DIGITS))
    files = {}
    files["a-%s.md" % tag] = SENT["A"]
    files["b-%s.md" % tag] = SENT["B"] + "\n" + digits
    files["c-%s.md" % tag] = digits + "\n" + SENT["C"]
    files["d-%s.md" % tag] = "\n".join([filler_line(rng) for _ in range(90)] + [SENT["D"]])
    for i in range(1, 5):
        files["f%d-%s.md" % (i, tag)] = "\n".join(filler_line(rng) for _ in range(rng.randint(4, 9)))
    prose = {k: v for k, v in files.items() if not k.startswith(("b-", "c-"))}
    corpus_toks = set()
    for v in files.values():
        corpus_toks.update(toks(v))
    overlap = []
    for q, text in QUERY.items():
        for t in toks(text):
            if any(ct.startswith(t) or t.startswith(ct) for ct in corpus_toks if not ct.isdigit()):
                overlap.append("%s:%s" % (q, t))
    for ws, fs in (("ws-full", files), ("ws-prose", prose)):
        for name, text in fs.items():
            write(os.path.join(outdir, ws, "memory", name), text)
    exp = {}
    for ws, fs in (("ws-full", files), ("ws-prose", prose)):
        exp[ws] = (len(fs), sum(chunk_count(t) for t in fs.values()))
    with open(os.path.join(outdir, "queries.tsv"), "w") as f:
        for q in "ABCD":
            f.write("%s\t%s-%s.md\t%s\n" % (q, q.lower(), tag, QUERY[q]))
    with open(os.path.join(outdir, "expected.txt"), "w") as f:
        for ws, (nf, nc) in exp.items():
            f.write("EXP %s files=%d chunks=%d\n" % (ws, nf, nc))
        for q in "ABCD":
            f.write("SENTINEL %s file=%s-%s.md\n" % (q, q.lower(), tag))
        f.write("PROBE_EXPECT tokens_min=%d\n" % TOKENS_MIN)
    with open(os.path.join(outdir, "alt.expect"), "w") as f:
        f.write("tokens_min=%d\n" % TOKENS_MIN)
    # Probe inputs for the direct truncation probe (one input per line): B, B with ALT sentence, C, C with ALT sentence.
    with open(os.path.join(outdir, "alt.txt"), "w") as f:
        f.write("\n".join([files["b-%s.md" % tag].replace("\n", " "), (ALT + "\n" + digits).replace("\n", " "),
                           files["c-%s.md" % tag].replace("\n", " "), (digits + "\n" + ALT).replace("\n", " ")]))
    for ws, fs in (("ws-full", files), ("ws-prose", prose)):
        for name in sorted(fs):
            b = fs[name].encode()
            print("CORPUS %s %s bytes=%d chunks=%d sha256=%s" % (ws, name, len(b), chunk_count(fs[name]),
                                                                 hashlib.sha256(b).hexdigest()))
    for ws, (nf, nc) in exp.items():
        print("CORPUS_EXPECT %s files=%d chunks=%d" % (ws, nf, nc))
    print("CORPUS_OVERLAP n=%d %s" % (len(overlap), ",".join(overlap) or "none"))
    return 0 if not overlap else 3


def sup(path, t0, t1):
    rows = []
    with open(path) as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if t0 <= r.get("t", 0) <= t1:
                rows.append(r)
    if not rows:
        print("host_samples=0")
        return
    print("host_samples=%d host_min_avail_gib=%.2f host_max_level=%d host_max_swap_delta_mib=%.0f "
          "host_max_comp_delta_gib=%.2f host_max_vm_rss_gib=%.2f" % (
              len(rows), min(r["avail_gib"] for r in rows), max(r["level"] for r in rows),
              max(r["swap_delta_mib"] for r in rows), max(r["comp_delta_gib"] for r in rows),
              max(r.get("vm_rss_gib", 0) for r in rows)))


def ranks(mfile, expfile):
    want = {}
    with open(expfile) as f:
        for line in f:
            m = re.match(r"SENTINEL (\w) file=(\S+)", line)
            if m:
                want[m.group(1)] = m.group(2)
    got = {}
    with open(mfile, errors="replace") as f:
        for line in f:
            m = re.match(r"SR (\w) rank=(\d+) path=(\S+) score=(\S+)", line)
            if m and m.group(1) in want and m.group(1) not in got and m.group(3).endswith(want[m.group(1)]):
                got[m.group(1)] = "%s@%s" % (m.group(2), m.group(4))
    print(" ".join("%s=%s" % (q, got.get(q, "none")) for q in "ABCD"))


def livesum(path, tag):
    """Rebuild PX / RTSUM lines from `tail -F proxy.jsonl lms-runtime.log lms-server.log` output (BSD tail headers)."""
    cur, rows, rt = "", [], []
    with open(path, errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.match(r"==> (.*) <==$", line)
            if m:
                cur = os.path.basename(m.group(1))
                continue
            if cur == "proxy.jsonl" or (not cur and line.startswith("{")):
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
            elif line:
                rt.append(line)
    loads = [r for r in rows if "/models/load" in r.get("path", "")]
    embs = [r for r in rows if "/embeddings" in r.get("path", "")]
    def ctx(r):
        return str((r.get("req") or {}).get("context_length", "?"))
    def st(r):
        resp = r.get("resp") if isinstance(r.get("resp"), dict) else {}
        return str(resp.get("status", "-")).replace(" ", "_")
    def eff(r):
        resp = r.get("resp") if isinstance(r.get("resp"), dict) else {}
        lc = resp.get("load_config") if isinstance(resp.get("load_config"), dict) else {}
        return str(lc.get("context_length", "-"))
    res = ["%s/%s/%s/%s" % (r.get("status"), st(r), eff(r), "capture-only" if r.get("forwarded") is False else "fwd")
           for r in loads]
    first = loads[0] if loads else None
    print("PX loads=%d req_ctx=%s first_req_ctx=%s load_results=%s first_load_http=%s first_load_status=%s src=live-tail" % (
        len(loads), ",".join(ctx(r) for r in loads) or "none", ctx(first) if first else "none", ",".join(res) or "none",
        first.get("status") if first else "none", st(first) if first else "-"))
    err = next((r for r in loads if not (200 <= int(r.get("status") or 0) < 300)), None)
    print("PX_LOADERR %s" % (re.sub(r"\s+", "_", json.dumps(err.get("resp")))[:600] if err else "none"))
    print("PX embeds=%d capture_only=%d http=%s src=live-tail" % (len(embs), sum(1 for r in embs if r.get("capture_only")),
                                                              ",".join(str(r.get("status")) for r in embs) or "none"))
    text = "\n".join(rt)
    nctx = [int(x) for x in re.findall(r"n_ctx(?:_seq)? *= *(\d+)", text)]
    nctx = [x for i, x in enumerate(nctx) if i == 0 or nctx[i - 1] != x]
    fails = re.findall(r"of size (\d+)", text)
    af = len(re.findall(r"failed to allocate", text, re.I))
    mb = "unknown"
    mbl = [l for l in rt if re.search(r"model buffer size", l, re.I)]
    if any(re.search(r"MTL|Metal", l, re.I) for l in mbl):
        mb = "MTL0"
    elif mbl:
        mb = "CPU"
    print("RTSUM %s src=live-tail bytes=%d n_ctx=%s model_buf=%s alloc_fail=%d max_fail_bytes=%s guardrail_lines=%d" % (
        tag, len(text), ",".join(map(str, nctx)) or "none", mb, af, max(map(int, fails)) if fails else "none",
        len(re.findall(r"guardrail|insufficient", text, re.I))))
    for l in [l for l in rt if re.search(r"failed to allocate|n_ctx|buffer size|guardrail|insufficient|out of memory|Resetting batch", l, re.I)][:40]:
        print("RTL %s live %s" % (tag, l[:300]))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["corpus"]:
        sys.exit(corpus(a[1], a[2]))
    elif a[:1] == ["chunks"]:
        print(chunk_count(open(a[1]).read()))
    elif a[:1] == ["sup"]:
        sup(a[1], float(a[2]), float(a[3]))
    elif a[:1] == ["ranks"]:
        ranks(a[1], a[2])
    elif a[:1] == ["livesum"]:
        livesum(a[1], a[2])
    else:
        print(__doc__ if __doc__ else "usage: corpus|chunks|sup|ranks", file=sys.stderr)
        sys.exit(2)
