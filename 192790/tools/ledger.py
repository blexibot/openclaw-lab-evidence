#!/usr/bin/env python3
"""Compact request ledger for #192790 packet. Stdlib only. Run: python3 -I ledger.py <requests.jsonl> [phase-label]

For each /api/chat request logged by hb_mock.py it prints: seq, logged UTC time, mock kind, last message role,
whether the CURRENT turn's heartbeat prompt carries a "Heartbeat monitor scratch:" block, whether ANY earlier
history message does, the tool calls the mock returned (name + argument keys), and for tool continuations the
tool result the gateway sent back.

"Current turn" = the last user message whose text starts with "Follow the heartbeat monitor scratch" (the
heartbeat poll prompt). hb_mock.py's own scratch_in_prompt flag scans every message in the history, so it can be
True because of an older turn; this script separates the two.
"""
import json, sys

MARK = "Heartbeat monitor scratch:"
POLL = "Follow the heartbeat monitor scratch"


def text(m):
    c = m.get("content")
    if isinstance(c, list):
        return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
    return c or ""


def main(path, label):
    print("phase seq t_logged_utc kind last_role current_turn_scratch history_scratch tool_calls | tool_result")
    for line in open(path):
        e = json.loads(line)
        if not e.get("path", "").startswith("/api/chat"):
            continue
        msgs = (e.get("body") or {}).get("messages") or []
        polls = [i for i, m in enumerate(msgs) if m.get("role") == "user" and text(m).startswith(POLL)]
        cur = polls[-1] if polls else None
        cur_scr = (MARK in text(msgs[cur])) if cur is not None else None
        hist_scr = any(MARK in text(m) for i, m in enumerate(msgs) if cur is None or i < cur)
        if e.get("last_role") == "tool":
            # a tool continuation belongs to the same turn as the poll before it
            cur_scr = "(continuation)"
        calls = []
        for c in ((e.get("reply") or {}).get("tool_calls") or []):
            f = c.get("function") or {}
            a = f.get("arguments") or {}
            calls.append(f"{f.get('name')}({','.join(sorted(a))})")
        tr = ""
        if e.get("last_role") == "tool" and msgs:
            tr = " ".join(text(msgs[-1]).split())[:200]
        print(f"{label} {e['seq']} {e['t']} {e.get('kind')} {e.get('last_role')} {cur_scr} {hist_scr} "
              f"{';'.join(calls) or '-'} | {tr}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "-")
