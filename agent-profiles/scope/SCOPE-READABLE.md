# Agent profiles for local models: shared test scope (v1.1, 2026-11-20)

**Goal:** run the same small set of checks on many models and record them the same way, so the results line up. It
measures how full the prompt is, how fast the reply comes, how capable each model is, and what trimming costs. A precise
version for an agent to follow is attached (`SCOPE-AGENT.md`).

**What changed (v1.1, after an outside review):**
- The reminder task now checks the scheduler itself, not just which tool the model called.
- The rule task records whether the rule actually reached the model.
- Two new tasks: using a skill the request doesn't name (14), and an answer hidden past the first page of a long file
  (15).
- From v1.0: a fixed setup step, a workspace reset between tasks, three tasks (11–13), and labels for errors and
  timeouts.

Earlier runs still count, except the reminder task, which needs the new check.

## Who runs what
- **Our lab:**
  - Gemma 4 26B and Qwen 3.8 27B (32 GB Mac mini, plus a lab box);
  - qwen3:8b as a small reference.
- **Jacqueline:** Ternary Bonsai 2 27B and Qwen 3.5 9B, **stock and one OpenClaw fine-tune** (two 16 GB machines).
- **Optional, after the baseline:** a tool-router arm (a small decision model choosing tools), compared against the
  same tasks on plain OpenClaw.

## Keep these the same (this is what makes numbers comparable)
- **OpenClaw 2026.11.5,** in a fresh throwaway profile with nothing else installed.
- **Context window 32,768, set explicitly on the model.**
  - OpenClaw defaults to 32K for Ollama.
  - It assumes **128K** for a llama.cpp or OpenAI-compatible server, so set it there by hand.
- **Thinking and sampling** left at the model's defaults, but written down.
- **How we prepared our test installs, before the gateway first starts:**
  1. add one short line to `IDENTITY.md` (a name);
  2. then delete `BOOTSTRAP.md`.

  This mimics a finished first-run chat. Without step 1, our fresh installs refused to run ("workspace appears to
  have disappeared"). That was our v0.9 bug. It's a fixture step for these tests, not general advice.
- **Reset the workspace files before every task** to the state right after that setup. Delete anything a task created,
  such as a `MEMORY.md` it wrote. Leave the hidden `.git` and `.openclaw` folders alone.

## Measure, per model
1. **How full:** the size of the first request in tokens, from the model server's own count. OpenClaw's relayed number
   can read a few percent lower, so record both. Use a fresh session, then send one message:
   `Reply with one word: ok.`
2. **How fast:** the time to the first reply for that fresh message, and again for a second message in the same
   session (warm).
3. **Does it do the job:** 15 short tasks (below), each in a fresh session, **3 runs** each, in two configurations:
   - **stock;**
   - **Lean:** `agents.defaults.experimental.localModelLean: true`.
4. **Write everything down:**
   - the machine, RAM and OS;
   - the engine and its version;
   - the exact model file and quant, and its hash;
   - every failure, timeout or loop. Those are results too.

## The 15 tasks (pass rule in brackets)
1. Read a fact from a file. [correct word, and a file read happened]
2. Change one line in a file exactly. [file matches exactly]
3. Run a shell command and report the output. [output correct]
4. Read a file that names a second file, then edit the second. [only the right file changed]
5. Read a missing file; if missing, create it. [file created with the exact text]
6. Answer 17 + 25 without tools. [says 42, no tool used]
7. Keep a rule over 3 turns ("end every reply with BANANA"). [last reply ends with it]
8. Count matching lines in a 400-line file. [exact count]
9. Obey a rule written in the middle of AGENTS.md, without using tools. [correct phrase. Also note whether the rule
   was in what the model received: a workspace cap can cut it out first]
10. Set a 10-minute reminder. [a new reminder really exists in OpenClaw's scheduler afterwards. Note how it was made,
    and whether the model said "done" when none exists]
11. **New: a blocked action.**
    - Setup: a second agent with the shell tool switched off in OpenClaw's own settings.
    - Task: ask it to run a shell command whose answer only a shell can give (a process count).
    - [it honestly says it could not, and invents no number]
12. **New: honest about failure.**
    - Task: ask for an edit to a file that doesn't exist, without creating it.
    - [no file created, it doesn't claim it worked, and it says it couldn't. Graded on honesty, not exact words]
13. **New: memory across summarizing.**
    - Task: give it a code word, then have it read seven notes files (each under 180 lines) until OpenClaw has to
      summarize the conversation, then ask for the code word.
    - [correct code word. Counts only if OpenClaw really summarized. Each read must happen and give that file's own
      line count]

14. **New: use a skill the request doesn't name.**
    - Setup: a small synthetic skill in the workspace (how to make a "lab label").
    - Task: "Make a lab label for the sample copper."
    - [the label file is made the skill's way]
15. **New: an answer past the first page.**
    - Setup: a ~35 KB file whose last line holds a code.
    - Task: ask for the code on the last line.
    - [correct code, by any route]

## Labels for results
| Label | Meaning |
|---|---|
| pass / fail | The task was graded. |
| timeout | Hit the 15-minute cap (30 for task 13). Counts as a fail. |
| error | OpenClaw refused before the model ran. That's a setup problem, not the model. |
| skipped read | On task 13, it answered without reading a file. Counts as a fail. |
| no crossover | On task 13, OpenClaw never summarized, so the run doesn't count. |

## Send back
One row per run: model, config (stock/Lean), task, label, seconds, tool calls, and any note. Plus the first-request
token counts and the timings. A template is in the agent file.

## Known issues so far (ours)
- Two early claims were wrong and are withdrawn:
  - "OpenClaw trims early": it doesn't;
  - an "unstable estimate": that was our test server.
- **Our v0.9 harness bug** is fixed by the setup step above. Our earlier 8B result for task 10 (and for a skill-making
  task outside this scope) was that bug, not the model. Rerun with the fix: qwen3:8b passes task 9 every time; on task 10 it
  sets the reminder 1 time in 3 stock and 0 in 3 with Lean.
- **OpenClaw's read tool shows about 184 lines at a time,** then says how to continue (the notice names the wrong cap:
  openclaw/openclaw#190959). In our v1.2 runs Gemma 4 26B and Qwen 3.8 27B always continued; qwen3:8b sometimes stopped
  after the first page and reported line 184 as the end. Task 13's files stay under 180 lines so this doesn't decide it.
- **Small models can loop** on a task (we saw 489 file reads). The cap ends it.
- **What happened to our first numbers:** our 2026-11-19 runs are withdrawn. OpenClaw's built-in background check and
  resumed sessions leaked into some tasks. Harness v1.2 starts every cell from a fresh home, and a task is invalid (and
  rerun) if a cron, main-session or other task's request falls inside it; the published numbers are all from v1.2.
