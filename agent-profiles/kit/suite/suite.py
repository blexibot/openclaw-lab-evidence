#!/usr/bin/env python3
"""suite.py: run a task suite once against a running gateway and grade it deterministically (Python 3.9+, stdlib).
Usage: suite.py --tasks tasks.json --ws <workspace dir> --wire <proxy wire.jsonl> --out <results.jsonl>
                --label <rung>/<seed> [--only T1,T2] [--pristine <snapshot dir>] [--ws-restricted <dir>] [--cap 900]
Each task: restore the workspace's top-level files from the pristine snapshot, write its files, run its turns with
`openclaw agent` in a fresh session, then grade from workspace bytes, the reply text, and the wire records written
during that task (tool calls and backend counters).

Verdicts (v1.2), first match wins:
  invalid        a request from another session (an earlier task's session, OpenClaw's own cron/proactive turns) fell
                 inside this task's window: the cell was contaminated. Never a model result; rerun (run_matrix does once)
  backend-error  the backend rejected a request (HTTP >= 400 or an error object): does-not-fit, not capability
  incomplete     the task hit its wall-clock watchdog (all turns together; default 900 s). Not a fail: rerun. (v1.0
                 called this `timeout`.) The graded limits are the step/token budgets below
  over-budget    the task used more model requests or generated tokens than its budget (same for every model): a fail
  error          OpenClaw itself refused the turn (non-ok status, unparseable output): a harness/runtime result, not
                 a model result. stderr and stdout tails are kept
  no-crossover   a task that needs the summarizing point (requires_compaction) never reached it: not counted
  pass / fail    the grade
The harness never deletes BOOTSTRAP.md (prep_ws.py does that before the gateway starts)."""
import argparse, json, os, re, shutil, subprocess, time

SESSION_RE = re.compile(r"session=(agent:[A-Za-z0-9_.:-]+)")
BUDGET_REQUESTS, BUDGET_GEN_TOKENS = 40, 6000   # per task, all turns; a task may set "budget": {"requests": n, "gen_tokens": n}

STARTING = "during gateway startup"

def wire_lines(p):
    if not os.path.exists(p): return []
    with open(p) as f: return [json.loads(l) for l in f if l.strip()]

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

def reply_text(js):
    try: o = json.loads(js)
    except Exception: return None, "unparseable", None
    pl = ((o.get("result") or {}).get("payloads") or [])
    return "\n".join((p.get("text") or "") for p in pl).strip(), o.get("status"), find(o, "compactionCount")

def chat_records(recs):
    out = []
    for r in recs:
        if r.get("method") != "POST" or "/api/chat" not in r.get("path", "") and "chat/completions" not in r.get("path", ""): continue
        calls, args, counters = [], [], {}
        for line in (r.get("resp") or "").splitlines():
            line = line.strip()
            if line.startswith("data:"): line = line[5:].strip()
            if not line or line == "[DONE]": continue
            try: o = json.loads(line)
            except Exception: continue
            msg = o.get("message") or {}
            for tc in msg.get("tool_calls") or []:
                f = tc.get("function") or {}; calls.append(f.get("name")); args.append(json.dumps(f.get("arguments"))[:4000])
            for ch in o.get("choices") or []:
                for tc in ((ch.get("delta") or {}).get("tool_calls") or []):
                    n = (tc.get("function") or {}).get("name")
                    if n: calls.append(n)
            for k in ("prompt_eval_count", "prompt_eval_cached_count", "prompt_eval_duration", "eval_count", "eval_duration", "done_reason"):
                if k in o: counters[k] = o[k]
            if o.get("error"): counters["error"] = str(o["error"])[:200]
        try: mm = json.loads(r.get("req") or "{}").get("messages") or []
        except Exception: mm = []
        nmsgs = len(mm) if mm else None
        def _txt(m):
            c = m.get("content")
            return c if isinstance(c, str) else json.dumps(c)
        users = [_txt(m) for m in mm if m.get("role") == "user"]
        last_user = users[-1] if users else ""
        all_text = "\n".join(_txt(m) for m in mm)
        ut = "\n".join(users); sm = SESSION_RE.search(ut)
        session = sm.group(1).lower() if sm else None
        is_cron = "[cron:" in ut
        sys_text = "\n".join(_txt(m) for m in mm if m.get("role") in ("system", "developer"))
        out.append({"seq": r.get("seq"), "status": r.get("status"), "req_bytes": len(r.get("req") or ""), "msgs": nmsgs, "_last_user": last_user[-2000:], "_user_text": "\n".join(users), "_all_text": all_text, "_sys_text": sys_text, "session": session, "cron": is_cron,
                    "tool_calls": calls, "tool_args": args, **counters})
    return out

WORDS = ("calibrated shelf bench sample reagent batch logged audited cabinet sensor drawer column ledger "
         "spare filter valve gauge label rack tray probe cable module").split()

def gen_file(spec):
    if "filler" in spec:  # deterministic filler text, about 80 chars a line, for the summarizing-crossover task
        k, n = spec.get("seed", 1), spec["filler"]
        lines = [f"Line {i:04d}: inventory note {k}-{i}: " + " ".join(WORDS[(i * 7 + j * 3 + k) % len(WORDS)] for j in range(8))
                 for i in range(1, n + 1)]
        if "tail" in spec:  # v1.1 tail sentinel: one last line whose content only a full read (or a tail/grep) reveals
            lines.append(f"Line {n + 1:04d}: {spec['tail']}")
            return "\n".join(lines) + "\n", spec["tail"]
        return "\n".join(lines) + "\n", str(n)
    n, every, w = spec["lines"], spec["every"], spec["match_word"]
    lines = [f"row {i},{w if i % every == 0 else 'ok'}" for i in range(1, n + 1)]
    return "\n".join(lines) + "\n", str(sum(1 for i in range(1, n + 1) if i % every == 0))

def restore_workspace(ws, pristine):
    """Mirror the workspace back to the snapshot before every task: edited files get their snapshot bytes back, and
    anything a task created (MEMORY.md, memory/, skills, scratch files) is removed, so nothing leaks into the next
    task's prompt.
    Dot-entries (.git, and the .openclaw folder the gateway creates) belong to OpenClaw and are never touched."""
    if not pristine or not os.path.isdir(pristine): return
    keep = set(n for n in os.listdir(pristine) if not n.startswith("."))
    for name in os.listdir(ws):
        if name.startswith("."): continue
        p = os.path.join(ws, name)
        if name in keep and os.path.isfile(os.path.join(pristine, name)) and os.path.isfile(p) and not os.path.islink(p): continue
        if os.path.isdir(p) and not os.path.islink(p): shutil.rmtree(p)
        else: os.remove(p)
    for name in keep:
        src, dst = os.path.join(pristine, name), os.path.join(ws, name)
        if os.path.isdir(src): shutil.copytree(src, dst, symlinks=True)
        else: shutil.copyfile(src, dst)

def wait_quiet(wire, quiet=30, limit=600):
    """After a timeout the gateway may still be running that turn. Wait until the wire has been quiet for `quiet`
    seconds (at most `limit`), so its late requests are not graded as part of the next task."""
    t0 = time.time(); last_n, last_t = len(wire_lines(wire)), time.time()
    while time.time() - t0 < limit:
        time.sleep(5); n = len(wire_lines(wire))
        if n != last_n: last_n, last_t = n, time.time()
        elif time.time() - last_t >= quiet: return round(time.time() - t0)
    return round(time.time() - t0)

def cron_jobs():
    """v1.1 scheduler oracle: every automation the gateway holds, read back through OpenClaw's own CLI (JSON).
    Returns None if the readback fails in any way: the grade then becomes unknown, never a guess."""
    try:
        p = subprocess.run(["openclaw", "cron", "list", "--all", "--json"], capture_output=True, text=True, timeout=90)
        out = p.stdout or ""; i = min([k for k in (out.find("{"), out.find("[")) if k >= 0] or [0])
        o = json.loads(out[i:])
    except Exception: return None
    if isinstance(o, dict): o = o.get("jobs") or o.get("automations") or o.get("items") or []
    return o if isinstance(o, list) else None

def cron_ids():
    jobs = cron_jobs()
    return None if jobs is None else set(j.get("id") for j in jobs if j.get("id"))

def cron_remove_new(keep):
    """Remove only the automations created since `keep` was taken, so a task's reminder can't fire into a later task.
    OpenClaw's own built-in jobs (a provisioned default automation, memory-core's dreaming promotion) are kept: they
    are part of a stock install."""
    if keep is None: return {"skipped": "keep-set unknown (readback failed before the task); nothing removed"}
    removed, failed = [], []
    for j in cron_jobs() or []:
        jid = j.get("id")
        if not jid or jid in keep: continue
        ok = False
        for _ in range(2):
            try: ok = subprocess.run(["openclaw", "cron", "rm", jid], capture_output=True, text=True, timeout=90).returncode == 0
            except Exception: ok = False
            if ok: break
        (removed if ok else failed).append(jid)
    return {"removed": removed, "failed": failed}

def job_text(j):
    return " ".join(str(x) for x in (j.get("name"), (j.get("payload") or {}).get("message"), (j.get("payload") or {}).get("text")) if x).lower()

def run_turn(agent, sk, msg, deadline):
    """One turn, retried only while the gateway says it is still starting. Returns (text, status, tail, compactionCount)."""
    while True:
        left = int(deadline - time.time())
        if left < 5: return None, "timeout", "", None
        try:
            p = subprocess.run(["openclaw", "agent", "--agent", agent, "--session-key", sk, "-m", msg,
                                "--timeout", str(left), "--json"], capture_output=True, text=True, timeout=left + 60)
        except subprocess.TimeoutExpired:
            return None, "timeout", "", None
        txt, st, comp = reply_text(p.stdout)
        tail = ((p.stderr or "")[-300:] + " | " + (p.stdout or "")[-300:]) if st != "ok" else ""
        if st != "ok" and STARTING in (p.stdout or "") + (p.stderr or ""):
            time.sleep(2); continue
        return txt, st, tail, comp

def main():
    a = argparse.ArgumentParser()
    for k in ("--tasks", "--ws", "--wire", "--out", "--label"): a.add_argument(k, required=True)
    a.add_argument("--only", default=""); a.add_argument("--cap", type=int, default=900)
    a.add_argument("--attempt", type=int, default=1)
    a.add_argument("--pristine", default=""); a.add_argument("--ws-restricted", default="")
    args = a.parse_args()
    suite = json.load(open(args.tasks)); only = set(x for x in args.only.split(",") if x)
    for t in suite["tasks"]:
        if only and t["id"] not in only: continue
        agent = t.get("agent", "main")
        if agent != "main" and not args.ws_restricted:
            print(f"{args.label} {t['id']} skipped: needs --ws-restricted (RESTRICTED=1)", flush=True); continue
        ws = args.ws_restricted if agent != "main" else args.ws
        restore_workspace(ws, args.pristine)
        bootstrap_present = os.path.exists(os.path.join(ws, "BOOTSTRAP.md"))
        expected_gen = {}
        for name in list(t.get("files", {})) + ["missing.txt"] + list(t.get("files_generated", {})) + t.get("ensure_absent", []):
            p = os.path.join(ws, name)
            if os.path.exists(p): os.remove(p)
        for name, body in t.get("files", {}).items():
            os.makedirs(os.path.dirname(os.path.join(ws, name)), exist_ok=True)  # v1.1: files may live in subfolders (skills/x/SKILL.md)
            with open(os.path.join(ws, name), "w") as f: f.write(body)
        if any(n.startswith("skills/") for n in t.get("files", {})): time.sleep(3)  # let OpenClaw's skills watcher refresh
        for name, spec in t.get("files_generated", {}).items():
            body, ans = gen_file(spec); expected_gen[name] = ans
            with open(os.path.join(ws, name), "w") as f: f.write(body)
        appended = {}
        for name, text in t.get("append", {}).items():
            p = os.path.join(ws, name); appended[name] = open(p).read() if os.path.exists(p) else None
            with open(p, "a") as f: f.write(text)
        for name, text in t.get("insert_middle", {}).items():
            p = os.path.join(ws, name); old = open(p).read() if os.path.exists(p) else ""; appended[name] = old if os.path.exists(p) else None
            cut = old.rfind("\n", 0, int(len(old) * 0.55)) + 1
            with open(p, "w") as f: f.write(old[:cut] + text + old[cut:])
        for dd in t.get("cleanup_dirs", []):
            shutil.rmtree(os.path.join(ws, dd), ignore_errors=True)
        sched_keep = cron_ids() if t.get("scheduler_reset") else None  # jobs present before the task (built-ins)
        pre_wait = wait_quiet(args.wire, quiet=10, limit=600)  # v1.2: start each task only when no request is in flight
        before = len(wire_lines(args.wire)); sk = f"suite-{args.label.replace('/', '-')}-{t['id']}-{int(time.time())}"
        replies, statuses, tails, turn_starts, comps = [], [], [], [], []
        t0 = time.time(); deadline = t0 + int(t.get("cap", args.cap))  # a task may need longer (T14: 8 turns)
        for msg in t["turns"]:
            turn_starts.append(len(wire_lines(args.wire)))
            txt, st, tail, comp = run_turn(agent, sk, msg, deadline)
            replies.append(txt); statuses.append(st); tails.append(tail); comps.append(comp)
            if st != "ok": break  # a timeout or refusal ends the task; later turns would test nothing
        time.sleep(1)
        quiet_wait = wait_quiet(args.wire) if "timeout" in statuses else 0
        all_wire = wire_lines(args.wire)
        own_key = f"agent:{agent}:{sk}".lower()
        def is_own(r):  # v1.2: foreign = OpenClaw cron/background turns, the main session, or another suite task's session.
            # Helper sessions the task itself starts (the `openclaw` assistant tool, memory/compaction helpers, skill
            # reviews) carry other keys and belong to the task; unmarked requests go with the task too.
            sess = r.get("session") or ""
            if r.get("cron") or sess.endswith(":main"): return False
            return not (":suite-" in sess and sess != own_key)
        all_recs = chat_records(all_wire[before:])
        foreign = [{"seq": r["seq"], "session": r.get("session"), "cron": r.get("cron")} for r in all_recs if not is_own(r)]
        recs = [r for r in all_recs if is_own(r)]
        last_recs = [r for r in chat_records(all_wire[turn_starts[-1]:]) if is_own(r)] if turn_starts else []
        calls = [c for r in recs for c in r["tool_calls"]]
        last_calls = [c for r in last_recs for c in r["tool_calls"]]
        g = t["grade"]; checks = {}
        last = (replies[-1] or "") if len(replies) == len(t["turns"]) else ""
        if "reply_contains" in g: checks["reply_contains"] = g["reply_contains"] in last
        if "reply_contains_ci" in g: checks["reply_contains_ci"] = g["reply_contains_ci"].lower() in last.lower()
        if "reply_contains_any_ci" in g: checks["reply_contains_any_ci"] = any(x.lower() in last.lower() for x in g["reply_contains_any_ci"])
        if "reply_no_digits" in g: checks["reply_no_digits"] = not any(ch.isdigit() for ch in last)
        if "reply_not_startswith_ci" in g:
            checks["reply_not_startswith_ci"] = not last.strip().lower().startswith(g["reply_not_startswith_ci"].lower())
        if "tool_called_any" in g: checks["tool_called_any"] = any(c in g["tool_called_any"] for c in calls)
        if "tool_not_called" in g: checks["tool_not_called"] = not any(c in g["tool_not_called"] for c in calls)
        if "file_equals" in g:
            ok = True
            for name, body in g["file_equals"].items():
                p = os.path.join(ws, name)
                ok = ok and os.path.exists(p) and open(p).read() == body
            checks["file_equals"] = ok
        if "file_equals_any" in g:
            ok = True
            for name, bodies in g["file_equals_any"].items():
                p = os.path.join(ws, name)
                ok = ok and os.path.exists(p) and open(p).read() in bodies
            checks["file_equals_any"] = ok
        if "file_absent" in g: checks["file_absent"] = not any(os.path.exists(os.path.join(ws, n)) for n in g["file_absent"])
        if "reply_equals_stripped" in g: checks["reply_equals"] = last.strip().strip(".") == g["reply_equals_stripped"]
        if "reply_equals_stripped_generated" in g:
            checks["reply_equals"] = last.strip().strip(".") == expected_gen[g["reply_equals_stripped_generated"]]
        if g.get("no_tool_calls"): checks["no_tool_calls"] = not calls
        if g.get("last_turn_no_tool_calls"): checks["last_turn_no_tool_calls"] = not last_calls
        if "last_reply_endswith" in g: checks["endswith"] = last.rstrip(" .!\n").endswith(g["last_reply_endswith"])
        if "file_exists_contains" in g:
            ok = True
            for name, needles in g["file_exists_contains"].items():
                p = os.path.join(ws, name); body = open(p).read() if os.path.exists(p) else None
                ok = ok and body is not None and all(n in body for n in needles)
            checks["file_exists_contains"] = ok
        if "tool_call_mentions" in g:
            w = g["tool_call_mentions"]
            checks["tool_call_mentions"] = any(w in (c or "") for c in calls) or any(w in a for r in recs for a in r.get("tool_args", []))
        if "tool_used" in g:
            w = g["tool_used"]; used = w in calls
            for r in recs:
                for n, a in zip(r["tool_calls"], r.get("tool_args", [])):
                    if n == "dispatch_action" and re.search(r'\\?"id\\?":\s*\\?"(?:[\w.-]+:)*' + re.escape(w) + r'\\?"', a): used = True
            checks["tool_used"] = used  # v1.0d: a namespaced id such as openclaw:core:automations also counts
        info = {}
        own = [r for r in recs if any(x[:60] in r.get("_user_text", "") for x in t["turns"])]  # this task's own requests
        if "native_tool_info" in g:  # which route was used is recorded, not graded (external review review 2)
            w = g["native_tool_info"]; used = w in calls
            for r in recs:
                for n, a in zip(r["tool_calls"], r.get("tool_args", [])):
                    if n == "dispatch_action" and re.search(r'\\?"id\\?":\s*\\?"(?:[\w.-]+:)*' + re.escape(w) + r'\\?"', a): used = True
            info["native_tool_used"] = used
            info["shell_cli_used"] = any(re.search(r"openclaw\s+(cron|automations)\s+(add|create)", a) for r in recs for a in r.get("tool_args", []))
        if "request_contains_info" in g:  # was the instruction actually in what the model received?
            needle = g["request_contains_info"]
            info["in_request"] = any(needle in r.get("_sys_text", "") for r in own)  # delivered by OpenClaw (system prompt)
            info["found_by_tools"] = (not info["in_request"]) and any(needle in r.get("_all_text", "") for r in own)
            info["first_sys_chars"] = len(own[0].get("_sys_text", "")) if own else None
        sched = None
        if "scheduler_job" in g:  # v1.1: grade the effect, read back from the gateway, not the tool name
            spec = g["scheduler_job"]; jobs = cron_jobs()
            if jobs is None or sched_keep is None:
                sched = {"readback": "failed", "keep_known": sched_keep is not None}
            else:
                def nxt(j): return j.get("nextRunAtMs") or (j.get("state") or {}).get("nextRunAtMs")
                def delay_ok(j):  # "10 minutes from now", measured from when the job was created, not from task start
                    c, n_ = j.get("createdAtMs"), nxt(j)
                    return bool(c and n_ and spec.get("min_s", 300) * 1000 <= n_ - c <= spec.get("max_s", 900) * 1000)
                match = [j for j in jobs if j.get("id") not in (sched_keep or set()) and spec["text"].lower() in job_text(j) and j.get("enabled", True)
                         and (j.get("createdAtMs") or 0) >= t0 * 1000 - 5000 and delay_ok(j)]
                checks["scheduler_job"] = len(match) >= 1
                sched = {"readback": "ok", "jobs_after": len(jobs), "matching": len(match), "duplicates": max(0, len(match) - 1),
                         "matching_ids": [j.get("id") for j in match],
                         "other_jobs": [{"id": j.get("id"), "text": job_text(j)[:80], "nextRunAtMs": nxt(j), "preexisting": j.get("id") in (sched_keep or set())} for j in jobs if j not in match]}
            low = re.sub(r"[*_`]", "", last).strip().lower().rstrip(".! ")
            said_not = "not done" in low
            info["claimed_done"] = (not said_not) and (low.startswith("done") or low.endswith("done"))
            info["false_completion"] = (bool(info["claimed_done"] and not checks["scheduler_job"])
                                        if "scheduler_job" in checks else None)
        sched_removed_after = cron_remove_new(sched_keep) if t.get("scheduler_reset") else None
        pes = [r.get("prompt_eval_count") for r in recs if r.get("prompt_eval_count")]
        # The summarizing point counts only on real events (as in trim_test.py): OpenClaw reports a compaction, or the
        # history sent shrinks (message count falls between requests). prompt_eval_count is not used: with Ollama's
        # prefix cache it can count only the uncached part.
        ms = [r.get("msgs") for r in recs if r.get("msgs") is not None]
        bounds = turn_starts + [len(all_wire)]
        for name, old in appended.items():
            p = os.path.join(ws, name)
            if old is None:
                if os.path.exists(p): os.remove(p)
            else:
                with open(p, "w") as f: f.write(old)
        # A rejected request (4xx/error) counts only if the turn did not recover: OpenClaw compacts and retries on a
        # context overflow, so a later request in the same turn that succeeded means it recovered.
        unrecovered, recovered = [], []
        for i, (a_, b_) in enumerate(zip(bounds, bounds[1:])):
            tr = [x for x in chat_records(all_wire[a_:b_]) if is_own(x)]
            for j, r in enumerate(tr):
                if (r["status"] or 0) >= 400 or "error" in r:
                    ok_later = statuses[i] == "ok" and any((x["status"] or 0) < 400 and "error" not in x for x in tr[j + 1:])
                    (recovered if ok_later else unrecovered).append({"seq": r["seq"], "status": r["status"], "error": r.get("error")})
        backend_err = bool(unrecovered)
        # Intermediate answers and reads (T14): each filler turn must read its file and give its own line count.
        skipped = []
        for i, chk in enumerate(t.get("turn_checks", [])):
            if not chk or i >= len(replies): continue
            tr = [x for x in chat_records(all_wire[bounds[i]:bounds[i + 1]]) if is_own(x)] if i + 1 < len(bounds) else []
            read_ok = any(c in ("read", "exec") for r in tr for c in r["tool_calls"])
            ans_ok = expected_gen.get(chk["file"], "?").lstrip("0") in (replies[i] or "")
            if not (read_ok and ans_ok): skipped.append({"turn": i + 1, "read": read_ok, "answer_ok": ans_ok})
        # The summarizing point, proved from the main history: the last turn's own request (a user message carries the
        # last turn's text) no longer contains the first turn's text. Memory-flush and summarizer side requests are
        # ignored because their last user message is not the task's turn text.
        crossing_signal = None
        if t.get("requires_compaction") and len(replies) == len(t["turns"]):
            first, lastq = t["turns"][0][:60], t["turns"][-1][:60]
            mains = [r for r in last_recs if lastq in r.get("_user_text", "")]  # any user message: OpenClaw appends a runtime-context user message after the turn text
            if mains and all(first not in r.get("_all_text", "") for r in mains): crossing_signal = "turn1_dropped"
        session_compactions = None
        if t.get("requires_compaction"):  # OpenClaw's own count for this session (the check an external runner can do)
            try:
                o = json.loads(subprocess.run(["openclaw", "sessions", "--agent", agent, "--json"], capture_output=True,
                                              text=True, timeout=60).stdout)
                rows = o if isinstance(o, list) else (o.get("sessions") or [])
                for row in rows:
                    if str(row.get("key", "")).lower().endswith(sk.lower()): session_compactions = row.get("compactionCount")
            except Exception:
                pass
            if crossing_signal is None and isinstance(session_compactions, int) and session_compactions > 0:
                crossing_signal = "session_compactionCount"
        crossed = crossing_signal is not None
        zero_requests = not recs
        bud = t.get("budget") or {}
        gen_tokens = sum(r.get("eval_count") or 0 for r in recs)
        usage = {"requests": len(recs), "gen_tokens": gen_tokens,
                 "budget_requests": bud.get("requests", BUDGET_REQUESTS), "budget_gen_tokens": bud.get("gen_tokens", BUDGET_GEN_TOKENS),
                 "prompt_tokens": sum(r.get("prompt_eval_count") or 0 for r in recs),
                 "cached_tokens": sum(r.get("prompt_eval_cached_count") or 0 for r in recs),
                 "prefill_s": round(sum(r.get("prompt_eval_duration") or 0 for r in recs) / 1e9, 1),
                 "gen_s": round(sum(r.get("eval_duration") or 0 for r in recs) / 1e9, 1)}
        over_budget = usage["requests"] > usage["budget_requests"] or gen_tokens > usage["budget_gen_tokens"]
        if foreign: verdict = "invalid"
        elif backend_err: verdict = "backend-error"
        elif "timeout" in statuses: verdict = "incomplete"
        elif over_budget: verdict = "over-budget"
        elif any(s != "ok" for s in statuses):
            # OpenClaw refused before the model ran (no requests): a harness/runtime error. If the model ran and
            # OpenClaw stopped the turn (e.g. its repeated-tool-failure guard), that is the model failing.
            verdict = "error" if zero_requests else "fail"
        elif sched is not None and sched.get("readback") == "failed": verdict = "unknown"  # the effect couldn't be read back
        elif skipped: verdict = "skipped-read"
        elif t.get("requires_compaction") and not crossed: verdict = "no-crossover"
        else: verdict = "pass" if checks and all(checks.values()) else "fail"
        rec = {"label": args.label, "task": t["id"], "agent": agent, "attempt": args.attempt, "kit": "v1.2", "verdict": verdict,
               "checks": checks, "info": info, "scheduler": sched, "foreign_requests": foreign, "usage": usage, "pre_task_wait_s": pre_wait,
               "scheduler_kept": sorted(sched_keep) if sched_keep is not None else None, "scheduler_removed_after": sched_removed_after,
               "statuses": statuses, "error_tails": [x for x in tails if x], "bootstrap_present": bootstrap_present,
               "replies": [(r or "")[:300] for r in replies], "tool_calls": calls, "n_tool_calls": len(calls),
               "crossed_summarizing_point": crossed, "crossing_signal": crossing_signal, "session_compactions": session_compactions, "compaction_counts": comps, "msgs_series": ms,
               "recovered_backend_errors": recovered, "unrecovered_backend_errors": unrecovered, "skipped_reads": skipped, "prompt_eval_series": pes, "requests": [{k: v for k, v in r.items() if not k.startswith("_")} for r in recs],
               "first_prompt_eval_count": next((r.get("prompt_eval_count") for r in recs if "prompt_eval_count" in r), None),
               "max_prompt_eval_count": max([r.get("prompt_eval_count") or 0 for r in recs] or [0]),
               "secs": round(time.time() - t0 - quiet_wait, 1), "quiet_wait_after_timeout": quiet_wait}
        with open(args.out, "a") as f: f.write(json.dumps(rec) + "\n")
        print(f"{args.label} {t['id']} {verdict} {checks} calls={len(calls)} crossed={crossed} "
              f"prompt_eval={rec['first_prompt_eval_count']}..{rec['max_prompt_eval_count']} {rec['secs']}s", flush=True)

if __name__ == "__main__":
    main()
