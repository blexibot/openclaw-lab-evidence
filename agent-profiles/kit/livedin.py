#!/usr/bin/env python3
"""livedin.py <workspace>: turn a freshly onboarded workspace into a synthetic "lived-in" one. Removes the first-run
BOOTSTRAP.md (as finishing the first-run conversation does), appends ~6K chars of user conventions to AGENTS.md,
~2K to USER.md, writes an ~8K-char MEMORY.md, and adds 40 workspace skills with realistic frontmatter. Measured on our fixture: AGENTS.md 17,058, USER.md 3,130,
MEMORY.md 13,688 chars (about 25K added in total). All content is
synthetic. Deterministic (fixed seed). Prints what it wrote."""
import os, random, sys
ws = sys.argv[1]; rnd = random.Random(1119)
W = ("project review weekly summary deadline invoice garden recipe workout budget travel itinerary reading list "
     "podcast backup photos receipts meeting agenda follow-up reminder grocery maintenance car insurance renewal "
     "birthday gift newsletter draft spreadsheet report tidy archive").split()
def sent(n=14): return " ".join(rnd.choice(W) for _ in range(n)).capitalize() + "."
bp = os.path.join(ws, "BOOTSTRAP.md")
if os.path.exists(bp): os.remove(bp)
conv = "\n\n## My conventions (synthetic lab user)\n" + "\n".join(f"- {sent()} {sent(8)}" for _ in range(55)) + "\n"
open(os.path.join(ws, "AGENTS.md"), "a").write(conv)
open(os.path.join(ws, "USER.md"), "a").write("\n\n## More about me (synthetic)\n" + "\n".join(f"- {sent(12)}" for _ in range(20)) + "\n")
mem = "# MEMORY (synthetic)\n\n" + "\n".join(f"- {rnd.randint(2025, 2026)}-{rnd.randint(1, 12):02d}: {sent()} {sent(6)}" for _ in range(80)) + "\n"
open(os.path.join(ws, "MEMORY.md"), "w").write(mem)
sk = os.path.join(ws, "skills"); os.makedirs(sk, exist_ok=True)
for i in range(40):
    a, b = rnd.choice(W), rnd.choice(W); name = f"lab-{a}-{b}-{i:02d}"
    os.makedirs(os.path.join(sk, name), exist_ok=True)
    open(os.path.join(sk, name, "SKILL.md"), "w").write(
        f"---\nname: {name}\ndescription: {sent(18)} Use when the user asks about {a} or {b}.\n---\n\n# {name}\n\n" +
        "\n".join(f"{k + 1}. {sent(10)}" for k in range(8)) + "\n")
sizes = {f: os.path.getsize(os.path.join(ws, f)) for f in ("AGENTS.md", "USER.md", "MEMORY.md")}
print(f"livedin: {sizes} skills=40")
