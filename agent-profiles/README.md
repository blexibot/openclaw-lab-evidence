# Agent profiles on small local models: `openclaw/base` vs `openclaw/small` at `ffe3bf0` (runs 2026-11-20)

**Tested head:** `etzelm/openclaw` `feat/agent-profiles-core` @ **`ffe3bf0`** (PR openclaw/openclaw#202517), built from
source. Everything in sections 1–3 compares that one head with no profile (**PB**, `openclaw/base`, the default) and
with `agentProfileId: "openclaw/small"` (**PS**). Nothing here was run on the reworked branch.

The question is the open one in #202517: are the `openclaw/small` values (no listed skills, with skill search still
available; a 12,000-character total cap on workspace files; reference sections dropped; all tools kept) good defaults
beyond the tasks measured in the PR? This packet informs that **preset decision**. It does not test or certify
migration, model-entry binding, or the reworked head.

Setup: three Ollama models (Gemma 4 26B-A4B, Qwen 3.8 27B, qwen3:8b) at a 32K window on one 32 GB Apple-silicon Mac,
in two synthetic workspaces:

- **fresh:** OpenClaw's onboarding defaults plus the task files;
- **lived-in:** the same, plus AGENTS.md 17.1K, USER.md 3.1K and MEMORY.md 13.7K chars, 40 workspace skills and one
  MCP server with 15 tools.

Four tasks, each aimed at one of the trims, 3 seeds per cell: the counts are small-sample observations, not rates.
Tables: [RESULTS.md](RESULTS.md). Every claim with a check command, marked as recounting a generated flag or inspecting
the underlying artifact: [ASSERTIONS.md](ASSERTIONS.md). Setup and grader: [METHOD.md](METHOD.md). Task IDs map to the
shared scope's numbers as T10b = 9, T11b = 10, T15 = 14, T16 = 15. `runs/*/results.jsonl` are derived run records
written by the grader (excerpts of each request, tool calls and replies), not full wire captures.

## Two cases to carry into the rework

### 1. The workspace cap removed an actual instruction

- Setup: the lived-in AGENTS.md is 17,211 chars, and we placed a one-line rule ("When anyone asks for the lab greeting,
  reply exactly: TANGERINE WAVE") in its middle on purpose, a worst case for truncation. T10b asks for the greeting and
  forbids tools.
- The rule text was in the system prompt of the task's requests in **9/9 PB** runs and **0/9 PS** runs; the task
  passed 9/9 vs 0/9. In one PS run Qwen 27B read AGENTS.md with a tool and found the rule; it is graded fail because
  the task forbids tools.
- What the model received (`excerpts/agents-rule-base-vs-small.txt`: Gemma, lived-in, seed 1, the first request of
  the T10b task session, linked to its results row by wire seq 9 and system-message length):
  - PB: 73,459-char system message; the `## Lab convention (synthetic)` heading and the rule line are both there.
  - PS: 29,105-char system message; the heading is kept, its body is replaced by `[...51 more policy lines
    omitted...]`, and the file carries the marker `…(truncated AGENTS.md: kept 5400+policy 4188+1800 chars of
    17211)…`. The prompt also carries the generic `[Bootstrap truncation warning]` ("Some workspace bootstrap files were
    truncated … read the relevant files directly if details seem missing").
- The gateway logged `AGENTS.md is 17211 chars (limit 12000); truncating` in every lived-in PS cell; in the same turns
  SOUL.md (1,526 chars) was cut to a 424-char limit.
- In the fresh workspace, where AGENTS.md (about 7.2K) is under the cap, the rule was present 9/9 under PS and the
  task passed 8/9 under both PB and PS.
- **Question for the rework:** the branch already documents an in-prompt truncation notice and per-file information in
  `/context`. Is it clear enough there that the *profile* set the cap, and which file lost what? The notice we saw names
  no file; the marker inside AGENTS.md does. Head, policy lines and tail were kept, so the body of a mid-file section
  can go even when its heading stays; that may be worth a line in the profile docs.

### 2. Search being available did not make the skill reliably discoverable

- T15 asks for a workspace skill that the request does not name (`skills/lab-labeler`, write `LBL-COPPER-7`).
- PB (skill listed): passed 9/9 lived-in and 9/9 fresh.
- PS (skills unlisted, `skills_search` available): passed **2/9 lived-in** and 4/9 fresh (Gemma 3/3 by listing
  `skills/`, Qwen 27B 1/3, 8B 0/3; the fresh failures never called a search tool).
- Lived-in PS: all 7 failures called `tool_search` and then our synthetic MCP tool `lab_files_query`. Its "lab" naming
  overlaps the request; that is our fixture's choice and a real caveat. `skills_search` was called once in the 18 PS
  runs (Qwen 27B, lived-in), and that run passed.
- PB vs PS changes more than the listing (the fresh T15 system prompt is about 37.9K vs 28.5K chars), and the lived-in
  fixture changes files, skills and tools together.
- **Read this as a counterexample to "available means found",** not as proof that the empty listing alone caused the
  failures, and not as an argument for any particular search design. The check worth keeping: is an unnamed workspace
  skill found?

## 3. What `small` improved: footprint and the longer tasks

- **Estimated prompt pressure, lived-in, first request** (one footprint probe per model and profile, `runs/footprints.txt`):
  - OpenClaw budgets 24,576 tokens of the 32,768 window (8,192 reserve).
  - OpenClaw's own estimate classified all three PB probes as `compact_only` (estimate 35,922 / 36,498 / 33,254 for
    Gemma / Qwen 27B / 8B) and all three PS probes as `fits` (21,751 / 21,821 / 18,632).
  - All three PB probes completed. The server's counts were PB 23,817 / 23,811 / 20,469 and PS 13,202 / 13,554 /
    10,797 tokens, so PB's server counts were also under 24,576. OpenClaw's estimate ran about 1.5–1.7× the server
    count; we did not look into why.
  - PS lowered the reported first-request count by **43–47 %** (44.6 / 43.1 / 47.3 %). That is one first-request pair
    per model on this fixture. It is not a latency result, and it is not split between files, skill listing and MCP
    tools.
- **The longer tasks, lived-in, Gemma and Qwen 27B together** (T16 read a 401-line file; T11b set a reminder):
  - Turn verdicts: **PB 2/12, PS 12/12.**
  - All 10 PB failures ended with OpenClaw's context-overflow message ("Context overflow: the system prompt, injected
    cont…"). Every one of those turns had already made tool calls (2–4 each), and some had effects: in 2 T11b runs
    (Gemma s1, Qwen 27B s2) the reminder job was registered during the turn and found by the scheduler readback.
  - The reminder check passes when the scheduler readback holds **at least one** enabled job containing "stretch",
    created during the task, whose next run is 5–15 minutes after its creation. It does not check one-shot
    configuration, exact timing or delivery. One Gemma release run (`g19-v4` R2/s3) passed with two matching jobs.
- **The 8B passed neither longer task under either profile in the lived-in workspace: PB 0/6, PS 0/6.** (One of its PB
  T16 runs ended with the context-overflow message; the other failures were page-1 stops, a case slip and failed
  reminder attempts, see Appendix B.)
- **Fresh workspace:** the first-request saving was 16–18.5 % (PB 15,335 / 15,571 / 12,689 → PS 12,684 / 13,079 /
  10,337). The PR reports the same comparison at −19.1 % on a different model and backend. Fresh Gemma PB also crossed
  OpenClaw's budget on T16 (by 923 estimated tokens) in all three seeds and passed after compaction.
- **Fresh workspace, other tasks: no consistent profile effect at n=3.** Reminder: Gemma PB 3/3 vs PS 1/3, Qwen 27B
  PB 2/3 vs PS 3/3, 8B 0/3 in both. 401-line read: Gemma and Qwen 27B 3/3 in both; the 8B 3/3 in PB and 0/3 in PS.
  The two Gemma PS reminder failures were model errors (Appendix B).

## Cohorts and builds

- **Branch cohort (sections 1–3):** `ffe3bf0`, built from source and selected with `OC_BIN_DIR`; it reports itself as
  2026.11.5. It is a newer `main` than the release, so it is a separate cohort from the release runs: compare PB with
  PS, never PB with R0.
- **Release cohort (Appendix A):** 2026.11.5 (`e13cf15`): `g19-v4`, `q8-v6`, and for Qwen 27B `q27m-v4b`.
- **Quarantined, not used for any claim:**
  - `q27m-v4` ran on 2026.11.6 because Qwen 27B had replaced the shared install during an earlier footprint turn
    (Appendix B). Its tables stay in RESULTS.md for reference only.
  - `q27m-fp` (release footprints) is the run in which that happened: its R1 cell aborted when the install was
    replaced, and its later cells ran after the replacement. It is not a clean 2026.11.5 comparison.
- `q27m-v4b` reran the Qwen 27B release rungs on 2026.11.5 with `update.checkOnStart: false` and
  `update.auto.enabled: false`. Those settings remove the update notice and automatic updates; they do not remove the
  agent's ability to run `openclaw update` itself. We did **not** record the executable or gateway identity per cell
  for `q27m-v4b` (its `run.log` names the build once, at the start). No recorded tool call in any graded task of any
  run contains `openclaw update`, but that is not a build pin. Future runs should use a build the tested agent cannot
  replace and record executable and gateway identity before and after each cell.

## How each model was served (Ollama 0.40.16, `env.txt`)

- `gemma4:26b-a4b` (26.2B MoE, nvfp4, MLX runner), Ollama/OpenClaw default sampling.
- `qwen3.8:27b` (27.8B, nvfp4, MLX runner; Ollama's default tag on a Mac), Qwen's published non-thinking sampling.
- `qwen3:8b` (Q4_K_M GGUF, llama.cpp runner), the same Qwen sampling.

`num_ctx` 32,768 and seed = cell seed (in each cell's `openclaw.json`). Thinking was off, OpenClaw's default for these
models; that is documented in `env.txt` but not shown by a file in this packet.

## Limits

- n=3 per cell, on one machine, at one context size (32,768). The four synthetic tasks target the trims; they are not
  the full shared scope.
- PB vs PS changes three things at once: the skill listing, the reference sections and the workspace cap. Case 1 is tied
  to the cap by the request excerpt and the gateway's truncation log. Case 2 and the 8B paging difference are not
  isolated to any one trim.
- The lived-in workspace is our own synthetic construction, and it changes files, the skill catalog and the tool
  surface together.
- Grading is session-scoped but not positively linked request by request: the grader rejects cron, main-session and
  other-task requests and accepts the rest (METHOD.md). The footprint probe takes the first captured model request of
  the cell. The excerpt pair in case 1 is the only session-linked request text in this packet.
- We withdrew our earlier (2026-11-19) runs. One OpenClaw home served a whole run, so a background "Proactive check"
  automation and resumed sessions leaked into graded tasks. Harness v1.2 gives every cell a fresh home.

## Reproduce

The kit is `kit/` (v1.2), and the exact settings are in `env.txt`. `OC_BIN_DIR` points at a build of the branch.
`SHA256SUMS` lists a hash for every file in this packet.

```sh
export APX=$HOME/apx KIT=$PWD/kit TASKS=tasks4.json
# Qwen only: MODEL_PARAMS='{"temperature":0.7,"top_p":0.8,"top_k":20,"min_p":0,"presence_penalty":1.5}'
OC_BIN_DIR=<branch>/bin kit/run_matrix.sh g-pr-v4 gemma4:26b-a4b 32768 suite "PB PS" "1 2 3"
LIVEDIN=1 OC_BIN_DIR=<branch>/bin kit/run_matrix.sh g-pr-lv4 gemma4:26b-a4b 32768 suite "PB PS" "1 2 3"
LIVEDIN=1 OC_BIN_DIR=<branch>/bin kit/run_matrix.sh g-pr-lfp gemma4:26b-a4b 32768 footprint "PB PS" "1"
kit/run_matrix.sh g19-v4 gemma4:26b-a4b 32768 suite "R0 R1 R2 R3" "1 2 3"               # release rungs (Appendix A)
```

## Thanks

- Mitchell Etzel, for the branch and the numbers in his PR.
- Jacqueline, for running the shared test scope on her own hardware.
- Vincent Koc and Onur Solmaz, for the Agent Profiles RFC (openclaw/rfcs#18).

(Drafted with my AI assistant; the runs are from my own lab.)

---

## Appendix A. Release ladder (separate cohort, 2026.11.5)

For reference we also ran the release at four settings, fresh workspace only: R0 stock, R1 Lean
(`experimental.localModelLean`), R2 Lean with skills off (`skills: []`), R3 R2 plus a 4,000-char workspace cap. Runs:
`g19-v4` (Gemma), `q27m-v4b` (Qwen 27B), `q8-v6` (8B); tables in RESULTS.md. These are a different build from the
branch, so they do not bear on PB vs PS. The quarantined `q27m-v4` table is in RESULTS.md, marked reference only.

## Appendix B. Pitfalls of small local models (not specific to profiles)

- **Gemma sent `tool_search` with `queries` as plain strings** in 4 of 6 fresh branch reminder runs, and on the
  release too (results.jsonl `tool_args`); the tool's schema expects objects. It then reached the scheduler through
  `tool_describe`.
- **Local time with a UTC `Z` suffix.** Gemma wrote the message header's local time with a `Z` suffix in 3 of 6 fresh
  branch reminder runs (2 PB, 1 PS), so the time was hours in the past. The two PB runs recovered by running `date -u`.
  PS/s2 rescheduled about 5 hours out and replied "done". The other Gemma PS failure (s3) returned an empty turn after
  `date -u`, then replied "done" with no job created.
- **The 8B stopped after the first page of a paged read** and reported line 184 as the last line.
  - Fresh workspace: in 6/9 runs on the leaner prompts (release R2/R3, PS) and 0/9 on R0/R1/PB. The cause is not
    isolated.
  - Lived-in workspace: stopped after page 1 in 2/3 runs under both PB and PS (0/3 passed in both).
- **Case slips.** The 8B answered `Kestrel-88` for `KESTREL-88` in 4 runs. The grader is case-sensitive.
- **Repetition loops.** 1 Qwen 27B rule-task run (branch PB, fresh) ended in OpenClaw's "Repetitive output stopped"
  reply. The quarantined `q27m-v4` had 2 more (R3); `q27m-v4b` had none.
- **False "done".** The 8B often reported success without doing the work: with no skill listed it wrote a made-up
  label (9/9 fresh cells on PS and release R2/R3); once, with the skill listed (release R1), it called the skill name
  as a tool and still replied "done" without writing the label.
- **An unrequested self-update.** Asked only to "Reply with one word: ok.", Qwen 27B (release, Lean, `q27m-fp` R1-s1)
  checked for updates, read `openclaw update --help`, did a dry run and then ran
  `openclaw update --yes`, replacing the install under the running gateway
  (`excerpts/self-update-during-footprint-turn.txt`). Seen once. Turning the update check off hides the notice but does
  not stop a model from running the command; see Cohorts and builds.
