#!/usr/bin/env python3
"""Analyzer for openclaw/openclaw#198178 (SGLang setup rerun vs an operator-pinned model-row maxTokens). Stdlib only.
  python3 -I an198178.py redact <config.json> <out.json>     # copy with secret-looking values replaced
  python3 -I an198178.py status <wire.jsonl> <from> <to>     # "<status>:<reason|->:<cap|->:<Retry-After|->" per chat POST
  python3 -I an198178.py verdict <tagdir> [relay.jsonl]      # every WIRE/CFG/DIFF/VERDICT/TOKENS/XCHECK line
The verdict is computed only from raw files (steps.log, cfg-*.json snapshots, wire.jsonl, the host relay's log),
so anyone can re-run it on the pulled evidence. Flags: config CAP-OVERWRITE / PRESERVED, ACTIVATION-FAILURE,
ACTIVATE-MISSED, ONBOARD-FAILURE, INFERENCE-FAILURE, LEFTOVER-PROCS; test outcome in LAB-EVIDENCE-RULES vocabulary
(reproduced / not reproduced under these conditions / blocked / inconclusive / harness failure / not run).
"not reproduced" is only possible when the setup demonstrably took effect (staged: activate ran with rc 0; direct
write: setup rc 0) and the baseline request carried the pinned 8192. c2 uses c1's baseline (same profile pa); c4
uses its own (profile pb); c3 (profile pc) uses its own login baseline "c3-infer0" (v5 kits) and only when that step
is absent (r1/r2 kits) borrows c1's from profile pa, which is valid only when the two base configs are identical, so
that VERDICT line prints base_identical (pa and pc "base" snapshot raw sha256 equal).
Retries: the attempt that counts is the highest-numbered one: "<label>-retry"/"-retryN" for inference,
"<cell>-activate<N>" for activate (plain "<cell>-activate" is attempt 0).
429 rule (LAB-IMPROVEMENT-PLAN W5): every proxy/relay refusal is an attempt and gets its own REFUSAL line (time,
status, reason, Retry-After). A counted inference retry is scored only when its chat body is byte-identical to the
refused attempt's (retry_body_identical=yes); otherwise the baseline fails / the cell is inconclusive
(reason retry-body-differs). A cell whose counted attempt is still refused is `blocked`.
"""
import json, os, re, sys, time

MODEL = "deepseek-v4.1-flash"
PINNED = 8192
REFUSED_STATUS = (401, 404, 413, 429, 503)
SECRETISH = re.compile(r"(token|password|secret|apikey|api_key|key)$", re.I)
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")
CHAT = "/v1/chat/completions"


def redact(o, k=""):
    if isinstance(o, dict):
        return {kk: redact(v, kk) for kk, v in o.items()}
    if isinstance(o, list):
        return [redact(v, k) for v in o]
    if isinstance(o, str) and SECRETISH.search(k) and not ENV_NAME.match(o) and not o.startswith("lab-dummy"):
        return f"<redacted len={len(o)}>"
    return o


def load_json(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def wire(p):
    out = {}
    if p and os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if line:
                try:
                    r = json.loads(line); out[r["seq"]] = r
                except Exception:
                    pass
    return out


def req_info(r):
    try:
        b = json.loads(r.get("req") or "")
    except Exception:
        return {"cap_field": None, "cap": None, "stream": None, "nmsg": None, "user": None}
    if not isinstance(b, dict):
        b = {}
    field = next((k for k in ("max_completion_tokens", "max_tokens") if k in b), None)
    msgs = b.get("messages") if isinstance(b.get("messages"), list) else []
    user = ""
    for m in reversed(msgs):
        if isinstance(m, dict) and m.get("role") == "user":
            c = m.get("content"); user = c if isinstance(c, str) else json.dumps(c); break
    return {"cap_field": field, "cap": b.get(field) if field else None, "both": {k: b.get(k) for k in
            ("max_completion_tokens", "max_tokens") if k in b}, "stream": b.get("stream"), "nmsg": len(msgs),
            "roles": [m.get("role") for m in msgs if isinstance(m, dict)], "user": user[:70],
            "tools": len(b.get("tools") or []) if isinstance(b.get("tools"), list) else 0, "model": b.get("model")}


def resp_info(text):
    txt, usage, err = "", None, None
    for line in (text or "").splitlines():
        line = line.strip()
        if line.startswith("data:"):
            d = line[5:].strip()
            if d == "[DONE]":
                continue
            try:
                o = json.loads(d)
            except Exception:
                continue
            for ch in o.get("choices") or []:
                delta = ch.get("delta") or ch.get("message") or {}
                if isinstance(delta.get("content"), str):
                    txt += delta["content"]
            if o.get("usage"):
                usage = o["usage"]
    if not txt and usage is None:
        try:
            o = json.loads(text)
            if isinstance(o, dict):
                if "choices" in o:
                    txt = ((o["choices"][0].get("message") or {}).get("content") or "")
                    usage = o.get("usage")
                if "error" in o:
                    e = o["error"]; err = e.get("reason") or e.get("message") if isinstance(e, dict) else str(e)
        except Exception:
            pass
    return {"text": txt.strip()[:60], "usage": usage, "err": err}


def steps(tagdir):
    st, snaps, misc = [], [], []
    p = os.path.join(tagdir, "steps.log")
    for line in (open(p, encoding="utf-8") if os.path.exists(p) else []):
        line = line.rstrip("\n")
        m = re.search(r"STEP profile=(\S+) label=(\S+) rc=(-?\d+) secs=(\d+) wire=(\d+)\.\.(\d+)(?: t0=(\d+))?", line)
        if m:
            st.append({"profile": m[1], "label": m[2], "rc": int(m[3]), "secs": int(m[4]),
                       "w": (int(m[5]), int(m[6])), "t0": int(m[7]) if m[7] else None}); continue
        m = re.search(r"SNAP profile=(\S+) n=(\d+) label=(\S+) .*file=(\S+)", line)
        if m:
            sha = re.search(r" raw_sha256=([0-9a-f]{64}) ", line)
            snaps.append({"profile": m[1], "n": int(m[2]), "label": m[3], "file": m[4], "sha": sha[1] if sha else None})
            continue
        misc.append(line)
    return st, snaps, misc


def flat(o, pre=""):
    out = {}
    if isinstance(o, dict):
        for k, v in o.items():
            out.update(flat(v, f"{pre}.{k}" if pre else k))
    elif isinstance(o, list) and o and all(isinstance(x, dict) and "id" in x for x in o):
        for x in o:
            out.update(flat(x, f"{pre}[id={x['id']}]"))
    else:
        out[pre] = o
    return out


def cfg_fields(c):
    prov = (((c or {}).get("models") or {}).get("providers") or {}).get("sglang") or {}
    rows = prov.get("models") or []
    row = next((r for r in rows if isinstance(r, dict) and r.get("id") == MODEL), rows[0] if rows else {})
    agents = ((c or {}).get("agents") or {}).get("defaults") or {}
    return {"row.maxTokens": row.get("maxTokens"), "row.contextWindow": row.get("contextWindow"),
            "rows": len(rows), "prov.maxTokens": prov.get("maxTokens"), "prov.timeoutSeconds": prov.get("timeoutSeconds"),
            "prov.baseUrl": prov.get("baseUrl"), "prov.apiKey": prov.get("apiKey"),
            "prov.keys": ",".join(sorted(prov.keys())), "row.keys": ",".join(sorted(row.keys())) if isinstance(row, dict) else "",
            "sentinel.cacheTrace": (((c or {}).get("diagnostics") or {}).get("cacheTrace") or {}).get("enabled"),
            "sentinel.workspace": agents.get("workspace"),
            "primary": (agents.get("model") or {}).get("primary") if isinstance(agents.get("model"), dict) else agents.get("model")}


def safe(x):
    """A short token with no spaces or colons, for the status line the run script pattern-matches."""
    return re.sub(r"[^A-Za-z0-9._-]", "_", str(x))[:40] if x not in (None, "") else "-"


def readf(*paths):
    out = ""
    for p in paths:
        try:
            out += open(p, encoding="utf-8", errors="replace").read()
        except Exception:
            pass
    return out


def fmt(d):
    return " ".join(f"{k}={v}" for k, v in d.items())


def verdict(tagdir, relay_path=None):
    W = wire(os.path.join(tagdir, "wire.jsonl"))
    R = wire(relay_path) if relay_path else {}
    st, snaps, misc = steps(tagdir)
    for line in misc:
        if re.search(r"version:|INSTALL|PREFLIGHT|INTEGRITY|DISTFILE|CONFIGFILE|READBACK|ONBOARD|LOGIN|INFER|CONFIGSET|ACTIVATE|SLOTWAIT|BLOCKED|PROCS|SKIP|FAILED|PATH|C1OK|C3OK|RELAY|WINDOW", line):
            print("LOG " + line)
    owner = {}
    for s in st:
        for q in range(s["w"][0], s["w"][1] + 1):
            owner[q] = f'{s["profile"]}/{s["label"]}'
    # WIRE lines
    posts, posts200, tin, tout, miss, refusals = 0, 0, 0, 0, 0, []
    for q in sorted(W):
        r = W[q]; ri = req_info(r); rs = resp_info(r.get("resp"))
        if r.get("path", "").rstrip("/") == CHAT and r.get("method") == "POST":
            posts += 1
            posts200 += r.get("status") == 200
            if r.get("status") in REFUSED_STATUS:
                refusals.append(q)
            if rs["usage"]:
                tin += rs["usage"].get("prompt_tokens") or 0; tout += rs["usage"].get("completion_tokens") or 0
            elif r.get("status") == 200:
                miss += 1
        print(f'WIRE seq={q} step={owner.get(q, "preflight/other")} {r.get("method")} {r.get("path")} '
              f'status={r.get("status")} secs={r.get("secs")} req_bytes={r.get("req_bytes")} '
              f'cap_field={ri["cap_field"]} cap={ri["cap"]} caps={ri.get("both")} stream={ri["stream"]} '
              f'msgs={ri["nmsg"]} roles={ri.get("roles")} tools={ri.get("tools")} user={ri["user"]!r} '
              f'resp_text={rs["text"]!r} usage={rs["usage"]} err={rs["err"]} auth_present={r.get("auth_present")}')
    # every refusal is an attempt (W5): time, status, reason, Retry-After, and the step that made it
    for q in refusals:
        r = W[q]; t = r.get("t")
        ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)) if isinstance(t, (int, float)) else "-"
        print(f'REFUSAL seq={q} step={owner.get(q, "preflight/other")} t={ts} status={r.get("status")} '
              f'reason={safe(resp_info(r.get("resp"))["err"])} retry_after={safe(r.get("retry_after"))} '
              f'req_sha256={(r.get("req_sha256") or "-")[:16]}')
    # chat POSTs that started outside every step's time window (a background process, not the step that owns the range)
    wins = [(s["t0"] - 1, s["t0"] + s["secs"] + 2) for s in st if s.get("t0") is not None]
    orphans = [q for q in sorted(W) if W[q].get("method") == "POST" and W[q].get("path", "").rstrip("/") == CHAT
               and wins and not any(a <= (W[q].get("t") or 0) <= b for a, b in wins)]
    print(f"ORPHANS chat_posts_outside_every_step={orphans if wins else 'unknown (no step times)'}")
    leftover = {}
    for line in misc:
        m = re.search(r"PROCS profile=(\S+) after=(\S+) n=(\d+)", line)
        if m and int(m[3]) > 0:
            leftover.setdefault(m[1], []).append(m[2])
    # CFG and DIFF lines per profile
    cf = {}
    for s in snaps:
        c = load_json(os.path.join(tagdir, s["profile"], s["file"]))
        cf[(s["profile"], s["label"])] = c
        print(f'CFG profile={s["profile"]} n={s["n"]} label={s["label"]} ' + (fmt(cfg_fields(c)) if c is not None else "unreadable"))
    byp = {}
    for s in snaps:
        byp.setdefault(s["profile"], []).append(s)
    for p, ss in byp.items():
        for a, b in zip(ss, ss[1:]):
            A, B = flat(cf.get((p, a["label"])) or {}), flat(cf.get((p, b["label"])) or {})
            ch = [k for k in sorted(set(A) | set(B)) if A.get(k, "<absent>") != B.get(k, "<absent>")]
            print(f'DIFF profile={p} {a["label"]} -> {b["label"]}: {len(ch)} changed path(s)')
            for k in ch[:60]:
                print(f'  {k}: {json.dumps(A.get(k, "<absent>"))} -> {json.dumps(B.get(k, "<absent>"))}')
    # per-cell verdicts
    def find(p, label):
        return next((s for s in st if s["profile"] == p and s["label"] == label), None)

    def caps(s):
        if not s:
            return []
        out = []
        for q in range(s["w"][0], s["w"][1] + 1):
            r = W.get(q)
            if r and r.get("path", "").rstrip("/") == CHAT and r.get("method") == "POST":
                ri = req_info(r); out.append((q, ri["cap_field"], ri["cap"], r.get("status"), resp_info(r.get("resp"))["err"]))
        return out

    def snapf(p, label):
        c = cf.get((p, label)); return cfg_fields(c) if c is not None else None

    def last_snap_before(p, labels):
        for lab in labels:
            if (p, lab) in cf and cf[(p, lab)] is not None:
                return lab, cfg_fields(cf[(p, lab)])
        return None, None

    def find_infer(p, label):  # the last retry, when the kit made one, is the attempt that counts
        # r1 kits label a retry "<label>-retry"; r2 kits number them "<label>-retry1", "-retry2", ...
        rs = [s for s in st if s["profile"] == p and re.fullmatch(re.escape(label) + r"-retry(\d*)", s["label"])]
        if rs:
            return max(rs, key=lambda s: int(s["label"].rsplit("-retry", 1)[1] or 0))
        return find(p, label)

    def find_act(p, cell):  # activate retries are labelled "<cell>-activate1", "-activate2", ...; the last one counts
        rs = [s for s in st if s["profile"] == p and re.fullmatch(re.escape(cell) + r"-activate(\d*)", s["label"])]
        return max(rs, key=lambda s: int(s["label"].rsplit("-activate", 1)[1] or 0)) if rs else None

    def base_sha(p):
        return next((s["sha"] for s in snaps if s["profile"] == p and s["label"] == "base"), None)

    def attempts(p, label):  # every inference attempt of one step: the plain label plus its -retry/-retryN steps
        return [s for s in st if s["profile"] == p and (s["label"] == label or
                                                        re.fullmatch(re.escape(label) + r"-retry(\d*)", s["label"]))]

    def chat_shas(s):
        return [W[q].get("req_sha256") for q in range(s["w"][0], s["w"][1] + 1)
                if q in W and W[q].get("method") == "POST" and W[q].get("path", "").rstrip("/") == CHAT]

    def retry_identity(p, label):
        """W5: a counted retry is scored only when its chat body is byte-identical to the refused attempt's.
        n/a = no retry counted; yes/no = compared with the first attempt's chat body; unknown = nothing to compare."""
        s, first = find_infer(p, label), find(p, label)
        if not s or not first or s is first:
            return "n/a"
        a, b = chat_shas(first), chat_shas(s)
        if not a or not b or None in a + b:
            return "unknown"
        return "yes" if set(b) == {a[0]} else "no"

    def refused_of(c):
        return [x for x in c if x[3] in REFUSED_STATUS or (x[4] or "").startswith("relay")]

    def transient(x):  # the kit's own retry rule (run198178.sh): these 429 reasons may be retried
        return x[3] == 429 and re.fullmatch(r"lab-request-in-flight|spark-busy|metrics-\S*", x[4] or "") is not None

    def in_step(s):
        """W5 for a retry made by the product itself inside one step (2026.11.5 `models auth activate` re-sends a
        refused probe on its own, in the same command). Returns (requests, refusals, identical, n):
        a transient 429 followed, in the same step, by a POST answered 200 is an attempt, set aside when at most two
        precede that 200 (three attempts in all) and each has the 200's chat body (identical=yes). identical=no when a
        body differs (the step is not scored); n/a when nothing was set aside. More than two stays a refusal (blocked)."""
        c = caps(s); ok = [x for x in c if x[3] == 200]; ref = refused_of(c)
        if not ok:
            return c, ref, "n/a", 0
        retried = [x for x in ref if x[0] < ok[-1][0]]
        if not retried or len(retried) > 2 or not all(transient(x) for x in retried):
            return c, ref, "n/a", 0
        sha = W[ok[-1][0]].get("req_sha256")
        same = bool(sha) and all(W[x[0]].get("req_sha256") == sha for x in retried)
        return ([x for x in c if x not in retried], [x for x in ref if x not in retried], "yes" if same else "no",
                len(retried))

    def baseline(p, label):
        """(ok, cap, reason, blocked): ok only when the counted attempt exited 0, a 200 request carried the pinned cap
        and (for a counted retry, by the kit or inside the step) its body is byte-identical to the refused one;
        blocked when a refusal remains after in_step()."""
        s = find_infer(p, label)
        c, ref, sid, _ = in_step(s) if s else ([], [], "n/a", 0)
        ok200 = [x for x in c if x[3] == 200]
        cap = ok200[0][2] if ok200 else (c[0][2] if c else None)
        if not s:
            return False, None, "not-run", False
        if ref:
            return False, cap, f"refused-{ref[-1][3]}-{safe(ref[-1][4])}", True
        if s["rc"] != 0:
            return False, cap, f"rc-{s['rc']}", False
        if not ok200:
            return False, cap, "no-200", False
        if not any(x[2] == PINNED for x in ok200):
            return False, cap, f"cap-{cap}", False
        if retry_identity(p, label) == "no" or sid == "no":
            return False, cap, "retry-body-differs", False
        return True, PINNED, "-", False

    def base_line(name, p, label, extra=""):
        s = find_infer(p, label); ok, cap, why, blk = baseline(p, label)
        _, _, sid, sn = in_step(s) if s else ([], [], "n/a", 0)
        word = "ok" if ok else ("blocked" if blk else "fail")
        print(f'VERDICT {name} baseline={word} reason={why} baseline_cap={cap} infer_rc={s["rc"] if s else "not-run"} '
              f'attempts={len(attempts(p, label))} retry_body_identical={retry_identity(p, label)} '
              f'in_step_retries={sn}:{sid}{extra} '
              f'requests={[(q, f, v, st_) for q, f, v, st_, _ in caps(s)]}')
        return ok, cap

    base = snapf("pa", "base")
    c1ok, c1cap = base_line("c1", "pa", "c1-infer", f' cfg_row_maxTokens={base and base["row.maxTokens"]} '
                                                    f'cfg_prov_maxTokens={base and base["prov.maxTokens"]}')

    def rerun_cell(cell, p, setup_labels, before_label, after_labels, infer_label, kind, base_ok, base_cap, pre_issue,
                   setup_files, base_from):
        before = snapf(p, before_label)
        setup = [find(p, l) for l in setup_labels]
        if not any(setup):
            stopped = next((m.split("FAILED: ", 1)[1] for m in misc if "FAILED: " in m), None)
            skip = next((m for m in misc if f"SKIP {cell} " in m),
                        f"SKIP {cell} run stopped earlier (FAILED-{stopped})" if stopped else "SKIP no setup step in steps.log")
            blk = bool(stopped and stopped.startswith(("blocked", "relay-budget", "hard-stop")))
            print(f"VERDICT {cell} outcome={'blocked' if blk else 'not run'!r} detail={skip.split('SKIP ', 1)[-1]!r}")
            return
        act = find_act(p, cell)
        missed = next((m for m in misc if f"ACTIVATE {cell} MISSED" in m), None)
        staged_msg = "saved but inactive" in readf(*[os.path.join(tagdir, p, f) for f in setup_files]).lower()
        staged = bool(act or missed or staged_msg)
        alab, after = last_snap_before(p, after_labels)
        inf = find_infer(p, infer_label)
        ic, iref, iid, inn = in_step(inf) if inf else ([], [], "n/a", 0)
        pc, pref, pid_, pnn = in_step(act) if act else ([], [], "n/a", 0)
        setup_rc = ",".join(f'{s["label"]}={s["rc"]}' for s in setup if s)
        setup_ok = all(s and s["rc"] == 0 for s in setup)
        path = f'{kind}:{"staged" if staged else "direct-write"}{"+activate" if act else ""}'
        # did the setup take effect? staged: only through an activate that ran and exited 0; direct: setup exit 0
        effective = bool(act and act["rc"] == 0) if staged else setup_ok
        flags = []
        refused = pref + iref
        rbi = retry_identity(p, infer_label)
        if "no" in (iid, pid_):
            rbi = "no"
        if act and act["rc"] != 0:
            flags.append("ACTIVATION-FAILURE")
        if missed or (staged and not act):
            flags.append("ACTIVATE-MISSED")
        if not staged and not setup_ok:
            flags.append("ONBOARD-FAILURE")
        overwrite = None
        if before and after:
            overwrite = after["row.maxTokens"] != before["row.maxTokens"]
            flags.append("CAP-OVERWRITE" if overwrite else "PRESERVED")
        nxt = [x for x in ic]
        n200 = [x for x in nxt if x[3] == 200]
        first = n200[0] if n200 else (nxt[0] if nxt else None)   # the answered request, not a refused one before it
        next_cap = first[2] if first else None
        next_status = first[3] if first else None
        if inf and (inf["rc"] != 0 or not any(x[3] == 200 for x in nxt)):
            flags.append("INFERENCE-FAILURE")
        if leftover.get(p):
            flags.append("LEFTOVER-PROCS")
        req_changed = (next_cap != base_cap) if (next_cap is not None and base_cap is not None) else None
        scope, why = "-", "-"
        if refused:
            outcome = "blocked"
        elif rbi == "no":
            outcome, why = "inconclusive / harness failure", "retry-body-differs"
        elif not base_ok:
            outcome, why = "inconclusive / harness failure", f"baseline-did-not-send-{PINNED}"
        elif pre_issue:
            outcome, why = "inconclusive / harness failure", pre_issue
        elif overwrite and req_changed and next_cap == (after or {}).get("row.maxTokens"):
            outcome, scope = "reproduced", "config+request"
        elif overwrite and next_cap is None:
            outcome, scope = "reproduced", "config-only"
            why = "no-next-request" if not nxt else "no-cap-field"
        elif not effective:
            outcome = "inconclusive / harness failure"
            why = ("activate-failed" if act else "activate-missed") if staged else "setup-failed"
        elif overwrite is False and next_cap == base_cap:
            outcome = "not reproduced under these conditions"
        else:
            outcome, why = "inconclusive / harness failure", "unmatched"
        sent = lambda f: before and after and (before[f] == after[f])
        print(f'VERDICT {cell} outcome={outcome!r} scope={scope} reason={why} flags={"+".join(flags) or "none"} path={path} '
              f'setup_rc={setup_rc} activate_rc={act["rc"] if act else "n/a"} setup_effective={effective} '
              f'probe_requests={[(q, f, v, s) for q, f, v, s, _ in caps(act)]} '
              f'row_maxTokens={before and before["row.maxTokens"]}->{after and after["row.maxTokens"]} '
              f'baseline_cap={base_cap} next_request_cap={next_cap} next_status={next_status} request_cap_changed={req_changed} '
              f'after_snapshot={alab} refused={[(q, s, e) for q, f, v, s, e in refused]} '
              f'attempts={len(attempts(p, infer_label))} retry_body_identical={rbi} in_step_retries=probe:{pnn}:{pid_},infer:{inn}:{iid} baseline_from={base_from}')
        print(f'CTXWIN {cell} row_contextWindow={before and before["row.contextWindow"]}->{after and after["row.contextWindow"]}')
        print(f'PROVFIELDS {cell} prov_maxTokens={before and before["prov.maxTokens"]}->{after and after["prov.maxTokens"]} '
              f'prov_timeoutSeconds={before and before["prov.timeoutSeconds"]}->{after and after["prov.timeoutSeconds"]} '
              f'prov_keys={before and before["prov.keys"]}->{after and after["prov.keys"]} '
              f'row_keys={before and before["row.keys"]}->{after and after["row.keys"]}')
        print(f'SENTINEL {cell} cacheTrace_preserved={sent("sentinel.cacheTrace")} workspace_preserved={sent("sentinel.workspace")} '
              f'primary={before and before["primary"]}->{after and after["primary"]} '
              f'baseUrl_preserved={sent("prov.baseUrl")}')

    rerun_cell("c2", "pa", ["c2-onboard"], "after-c1-infer", ["after-c2-activate", "after-c2-onboard"], "c2-infer",
               "noninteractive-rerun", c1ok, c1cap, None, ["c2-onboard.out", "c2-onboard.err"], "own:pa:c1")
    sa, sc = base_sha("pa"), base_sha("pc")
    base_identical = (sa == sc) if (sa and sc) else None
    if find("pc", "c3-infer0") or not find("pc", "c3-login"):
        # v5 kits: c3's own login baseline in profile pc (the hand-written pinned config, before the login)
        c3ok, c3cap = base_line("c3-baseline", "pc", "c3-infer0", f" base_identical_to_pa={base_identical}")
        c3before, c3from = "after-c3-infer0", "own:pc:c3-infer0"
    else:
        # r1/r2 kits had no c3 baseline: borrow c1's (profile pa), valid only when the base configs are byte-identical
        c3ok, c3cap = c1ok, c1cap
        print(f"VERDICT c3-baseline baseline=borrowed reason=no-c3-baseline-in-this-kit from=pa:c1 "
              f"base_identical={base_identical}")
        c3before, c3from = "base", f"pa:c1 base_identical={base_identical}"
    rerun_cell("c3", "pc", ["c3-login"], c3before, ["after-c3-activate", "after-c3-login"], "c3-infer",
               "interactive-login", c3ok, c3cap, None, ["c3-transcript.txt", "c3-login.out", "c3-login.err"], c3from)
    cs = [re.search(r"CONFIGSET (\S+) .* rc=(\S+)$", m) for m in misc if "CONFIGSET " in m]
    csbad = [m[1] for m in cs if m and m[2] != "0"]
    c4ok, c4cap = base_line("c4-baseline", "pb", "c4-infer1", f" configset_total={len([m for m in cs if m])} "
                                                              f"configset_nonzero={csbad}")
    rerun_cell("c4", "pb", ["c4-onboard2"], "after-c4-infer1", ["after-c4-activate", "after-c4-onboard2"], "c4-infer2",
               "noninteractive-rerun-of-onboarded", c4ok, c4cap, f"configset-failed-{len(csbad)}" if csbad else None,
               ["c4-onboard2.out", "c4-onboard2.err"], "own:pb:c4-infer1")
    print(f"TOKENS posts={posts} posts_200={posts200} refused={len(refusals)} actual_in={tin} actual_out={tout} posts_200_without_usage={miss} "
          f"(SGLang usage from the responses; the relay clamps output to its OUT_CAP)")
    if R:
        used, matched = set(), 0
        for q in sorted(W):
            r = W[q]
            if r.get("method") != "POST":
                continue
            # pair in order: the first unused relay POST with the identical body (identical prompts repeat)
            x = next((R[k] for k in sorted(R) if k not in used and R[k].get("method") == "POST"
                      and R[k].get("req_sha256") == r.get("req_sha256")), None)
            if x:
                used.add(x["seq"]); matched += 1
            ri = req_info(r)
            print(f'XCHECK bench_seq={q} relay_seq={x and x.get("seq")} body_identical={bool(x)} '
                  f'bench_status={r.get("status")} relay_status={x and x.get("status")} relay_reason={x and x.get("relay_reason")} '
                  f'bench_cap={ri["cap"]} relay_orig_caps={x and x.get("orig_caps")} relay_fwd_caps={x and x.get("fwd_caps")}')
        rposts = [r for r in R.values() if r.get("method") == "POST"]
        fwd = [r for r in rposts if r.get("relay_reason") == "forwarded"]
        print(f"XCHECK_SUMMARY bench_posts={sum(1 for r in W.values() if r.get('method') == 'POST')} "
              f"relay_posts={len(rposts)} relay_forwarded={len(fwd)} matched={matched} "
              f"relay_refusals={[(r.get('seq'), r.get('status'), r.get('relay_reason')) for r in rposts if r.get('relay_reason') != 'forwarded']}")


def main():
    mode = sys.argv[1]
    if mode == "redact":
        try:
            o = json.load(open(sys.argv[2], encoding="utf-8"))
            json.dump(redact(o), open(sys.argv[3], "w"), indent=1, sort_keys=False)
        except Exception as e:
            open(sys.argv[3], "w").write(json.dumps({"unreadable": f"{type(e).__name__}: {e}"}))
    elif mode == "status":
        W = wire(sys.argv[2]); a, b = int(sys.argv[3]), int(sys.argv[4])
        print(" ".join(f'{W[q].get("status")}:{safe(resp_info(W[q].get("resp"))["err"])}:{safe(req_info(W[q])["cap"])}:'
                       f'{safe(W[q].get("retry_after"))}' for q in range(a, b + 1)
                       if q in W and W[q].get("method") == "POST" and W[q].get("path", "").rstrip("/") == CHAT))
    elif mode == "verdict":
        verdict(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
