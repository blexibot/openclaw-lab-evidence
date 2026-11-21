#!/usr/bin/env python3
"""prep_ws.py <workspace>: put a freshly onboarded workspace into the state a user has after the first-run ritual,
BEFORE any gateway starts (v1.0 harness fix).

Why: OpenClaw 2026.11.5 refuses to run a recently attested workspace whose BOOTSTRAP.md is gone while every starter
file is still untouched. It treats that as a wiped workspace (WorkspaceVanishedError, "Refusing to reseed
BOOTSTRAP.md"). That was our v0.9 harness bug: deleting BOOTSTRAP.md mid-run, with a pristine workspace. The docs
(start/bootstrapping.md) say a workspace counts as configured once SOUL.md, IDENTITY.md or USER.md differs from its
starter template. The ritual fills IDENTITY.md and then deletes BOOTSTRAP.md, so we do the same: append a short
synthetic identity block (about 80 chars) and delete BOOTSTRAP.md. Idempotent. Prints what it did."""
import os, sys
ws = sys.argv[1]
idp = os.path.join(ws, "IDENTITY.md")
marker = "## Filled in at first run (synthetic)"
body = open(idp).read() if os.path.exists(idp) else ""
if marker not in body:
    with open(idp, "a") as f: f.write(f"\n\n{marker}\n- Name: Lab Assistant\n- Emoji: 🧪\n")
bp = os.path.join(ws, "BOOTSTRAP.md")
had = os.path.exists(bp)
if had: os.remove(bp)
print(f"prep_ws: IDENTITY.md filled ({os.path.getsize(idp)} bytes), BOOTSTRAP.md {'removed' if had else 'already absent'}")
