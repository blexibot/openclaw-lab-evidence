# Method (kit v1.2, runs 2026-11-20)

## Builds and rungs

Every rung's config is written by `kit/rungs.py` from the onboarded `base-openclaw.json`. The written config of each
cell is kept at `runs/<tag>/<cell>/openclaw.json`. Every rung pins the Ollama params of each model row:

- `num_ctx` 32768;
- `seed` = the cell seed (1, 2, 3);
- `truncate: false`, so an overflow becomes an error instead of a silent cut.

| Rung | Build | What it sets in `agents.defaults` |
|---|---|---|
| R0 | release 2026.11.5 (`e13cf15`), all three models (Qwen 3.8 27B: `runs/q27m-v4b`) | nothing (stock) |
| R1 | release | `experimental.localModelLean: true` (today's Lean; `openclaw/lean` on the branch) |
| R2 | release | R1 + `skills: []` (no skills available at all: no Skills section, and no `skills_read` / `skills_search` in the deferred list) |
| R3 | release | R2 + `bootstrapTotalMaxChars: 4000` |
| PB | branch `ffe3bf0` (PR #202517), built from source | nothing: `openclaw/base`, the default |
| PS | branch | `agentProfileId: "openclaw/small"` |

The branch build is selected with `OC_BIN_DIR`. Each `run.log` names its build once, at the start of the run.

### Cohorts

- **Branch cohort** (`*-pr-*`): `ffe3bf0`, built from source; it reports itself as 2026.11.5 but is a newer `main` than
  the release. Compare PB with PS, never PB with R0.
- **Release cohort**: 2026.11.5 (`e13cf15`): `g19-v4`, `q8-v6`, `q27m-v4b`.
- **Quarantined** (no claim uses them):
  - `q27m-v4` ran on 2026.11.6 (`06afb10`). In a one-word footprint turn before it, the model ran
    `openclaw update --yes` itself and replaced the shared test install
    (`excerpts/self-update-during-footprint-turn.txt`).
  - `q27m-fp`, the release footprint run in which that happened: its R1-s1 cell aborted when the install was replaced
    (the gateway stopped itself), and its R2-s1 and R3-s1 cells ran after the replacement (very likely on 2026.11.6,
    inferred: no file records their version), although its `run.log` names only the starting build, 2026.11.5.

`runs/q27m-v4b` reran R0–R3 on 2026.11.5 with `kit/rungs.py` `NO_SELF_UPDATE` (`update.checkOnStart: false`,
`update.auto.enabled: false`, visible in each cell's `openclaw.json`); it is the Qwen 27B release run. Those settings
remove the update notice and automatic updates; they do **not** remove the agent's ability to run `openclaw update`
through its shell tool, and a fresh OpenClaw home per cell does not pin the shared binary. We did not record the
executable or gateway identity per cell for `q27m-v4b`. No recorded tool call in any graded task of any run contains
`openclaw update` (ASSERTIONS 5a), which is consistent with an unchanged build but is not a pin. Future runs should use
a build the tested agent cannot replace (read-only to the agent's user) and record executable and gateway identity
before and after each cell. The other runs predate `NO_SELF_UPDATE` and ran with OpenClaw's default update settings.

The `kit/` in this packet is v1.2 as shipped, which every other run used. `q27m-v4b` ran kit v1.2b: the same kit plus
these three lines in `kit/rungs.py` (run with `NO_SELF_UPDATE=1`), which the packet's `rungs.py` does not contain:

```python
# v1.2b: NO_SELF_UPDATE=1 turns off the startup update check and auto-update.
if os.environ.get("NO_SELF_UPDATE"): c["update"] = {**(c.get("update") or {}), "checkOnStart": False, "auto": {"enabled": False}}
```

To reproduce `q27m-v4b`, add that line just before the final `json.dump` in `rungs.py` and set `NO_SELF_UPDATE=1`.

Task IDs map to the shared scope (`scope/`) as T10b = task 9, T11b = task 10, T15 = task 14, T16 = task 15.

## Fresh vs lived-in workspace

Both workspaces start from OpenClaw's own non-interactive Ollama onboarding into a throwaway `OPENCLAW_HOME`.
`kit/prep_ws.py` then mimics a finished first-run chat before any gateway starts: it appends a short synthetic block to
IDENTITY.md and deletes BOOTSTRAP.md.

- **Fresh:** the result of those steps, plus each task's files.
- **Lived-in** (`LIVEDIN=1`): applied before the snapshot, by two steps.
  - `kit/livedin.py` (deterministic, seed 1119, all synthetic):
    - appends user conventions to AGENTS.md and USER.md;
    - writes MEMORY.md;
    - adds 40 workspace skills with frontmatter.
    - Logged sizes: AGENTS.md 17,114, USER.md 3,070 and MEMORY.md 13,688 chars. AGENTS.md is 17,211 with the T10b
      rule inserted.
  - `run_matrix.sh` registers one stdio MCP server, `labtools` (`kit/mcpfake.py`):
    - 15 synthetic tools named `lab_<domain>_query`;
    - every call returns fixed text.
  - The lived-in condition therefore changes files, the skill catalog and the tool surface together.

## Harness rules (v1.2)

- **A fresh home per cell.** Every rung×seed cell starts from a byte-identical copy of the post-onboarding home. No
  sessions, automation state or resumed turns carry over between cells. The workspace is restored from its snapshot as
  well.
- **The gateway** runs in its own process group behind a recording proxy (`kit/logproxy.py`). It is stopped only
  after the wire has been quiet for 20 s (at most 600 s), and the cell's home is archived.
- **Untimed preload.** One untimed `generate` call loads the model before any cell.
- **One session per task.** Each task runs with `openclaw agent` in its own session (`suite-<cell>-<task>-<time>`).
  The workspace's top-level files are restored before each task.
- **What the grader keeps** (`suite.py` `is_own`). Every `/api/chat` request captured from the task's start until
  grading is classified by the session key and cron marker that OpenClaw writes into the request's user text:
  - **excluded as foreign:** requests marked as cron (`[cron:`), the main session (key ending `:main`), and any other
    suite task's session (`:suite-` with a different key);
  - **kept:** the task's own key, **and also** requests with no session marker and requests with any other key (for
    example OpenClaw's `internal-session-effects` and `openclaw` helper sessions), on the assumption that the task
    started them.
  - So the grader does not positively link every kept request to the task; it rejects the known kinds of foreign
    request. Across the 288 retained rows of the runs used for claims (quarantined `q27m-v4` excluded), the kept
    requests were 1,114 with the task's own key, 82 `internal-session-effects`, 7 `agent:openclaw:` helper sessions and
    37 unmarked (ASSERTIONS 36b).
  - The rule-presence flag (`info.in_request`) and `first_sys_chars` read only the kept requests whose user text
    contains the task's own message.
- **Foreign requests invalidate the task.** If an excluded request falls inside the task's window, the verdict is
  `invalid` and the attempt is kept in results.jsonl as attempt 1. No retained (latest) row has a recorded foreign
  request.
- **Watchdog.** A task that hits its wall-clock cap is `incomplete`. The cap is 900 s, or 480 s for T11b.
- **Reruns.** `invalid` and `incomplete` tasks are rerun once, in a fresh cell (attempt 2). The latest attempt per
  label and task counts. An invalid first cell, or OpenClaw errors in the first cell, aborts the run.
- **Budgets.** 40 model requests and 6,000 generated tokens per task. Going over is `over-budget`, a fail.
- **Other verdicts.** `backend-error` (an unrecovered HTTP ≥ 400 from the backend) and `error` (OpenClaw refused
  before any model request) are kept apart from model fails. A turn that ends with OpenClaw's context-overflow message
  after model requests is graded `fail`. The verdict is about the turn: such a turn may already have made tool calls
  with effects (in two lived-in PB T11b runs the reminder job was registered before the turn ended this way).
- **Footprint mode.** One fresh session gets "Reply with one word: ok.". `kit/suite/footprint.py` records the
  server's `prompt_eval_count` for the **first captured `/api/chat` request of the cell** (it does not check the
  session key), with OpenClaw's own route and estimate for the turn (`runs/footprints.txt`). The route is OpenClaw's
  classification of its own estimate, not a measurement that the request did not fit: all three lived-in PB probes were
  `compact_only` and still completed (`rc=0`, `done=stop`).
- **What is in the packet.** `runs/<tag>/results.jsonl` are derived run records written by the grader: per request
  the wire seq, status, session key, tool-call names and arguments (each cut at 4,000 chars) and token counts, plus
  replies, checks and flags. They are not full wire captures. The one session-linked request pair is
  `excerpts/agents-rule-base-vs-small.txt`: system-message excerpts with request hashes, linked to the results rows
  `g-pr-lv4` PB/s1 and PS/s1 T10b by wire seq 9 and system-message length (73,459 / 29,105 chars). The excerpt header
  prints `session None`; the session keys (`…suite-pb-s1-t10b-…`, `…suite-ps-s1-t10b-…`) are in those rows
  (ASSERTIONS 16b).

## Tasks and grading (`kit/suite/tasks4.json`, `kit/suite/suite.py`)

| Task | Request | Pass | Recorded, not graded |
|---|---|---|---|
| T10b | "What is the lab greeting from your workspace conventions? … Do not read any files or use any tools." The rule `TANGERINE WAVE` is inserted in the middle of AGENTS.md. | reply contains `TANGERINE WAVE` and no tool calls | `in_request`: the rule is in the system prompt of the task's own requests; `found_by_tools` |
| T15 | "Make a lab label for the sample copper. Reply with the word done…" A workspace skill `skills/lab-labeler` says to write `LBL-<SAMPLE>-7`. | `label.txt` is exactly `LBL-COPPER-7` (an optional trailing newline is allowed) | `in_request` (the skill listed in the prompt); `found_by_tools` |
| T16 | "What is the final code written on the last line of long.txt…?" The file has 400 filler lines plus `Line 0401: final code KESTREL-88`, about 36 KB. | reply contains `KESTREL-88` (case-sensitive), by any route | tool calls |
| T11b | "Set a reminder that fires 10 minutes from now with the text: stretch break…" | the scheduler readback (`openclaw cron list --all --json`) holds **at least one** job that was not there before the task, is enabled, contains "stretch", was created during the task (`createdAtMs` ≥ task start − 5 s) and has its next run 300–900 s after its own `createdAtMs`. Not checked: one-shot configuration, exact timing, or delivery. | `scheduler.matching` / `duplicates` (one release Gemma pass, `g19-v4` R2/s3, had 2 matches), `native_tool_used` (`automations`), `shell_cli_used` (`openclaw cron/automations add`), `false_completion` ("done" with no matching job) |

T11b runs last in each cell, so its job can't fire before the readback. Pre-existing built-in jobs are kept, and jobs
created during the task are removed after grading.

## Sampling and serving (`env.txt`)

- Thinking is off (OpenClaw's default for these model rows). This is documented in `env.txt`; no file in this packet
  shows the request field.
- Qwen models get Qwen's published non-thinking settings through `MODEL_PARAMS`: temperature 0.7, top_p 0.8, top_k 20,
  min_p 0, presence_penalty 1.5.
- Gemma uses Ollama/OpenClaw defaults.
- Ollama 0.40.16 on a Mac mini (Apple M6, 32 GiB, macOS 27.0). The MLX runner serves `gemma4:26b-a4b` and
  `qwen3.8:27b`; llama.cpp serves `qwen3:8b`. Model digests are in `env.txt` and each run's `run.log`.

## Not controlled, or not isolated

- **n=3 per cell.** Within a rung, the prompts are identical across seeds, so the seeds differ only in sampling. No
  rates are estimated.
- **One machine, one window size (32,768) and one backend.** Prefill timings are not compared.
- **PB vs PS changes several things at once:** the skill listing, the reference sections and the workspace cap. Which
  of them drives a given difference is not isolated. The same holds for the lived-in condition (files, 40 skills and
  the MCP server).
- **The MCP distractor's tool names** (`lab_files_query` and others) share the word "lab" with the T15 request.
- **T10b puts its rule in the middle of AGENTS.md on purpose** (a worst case for head/tail truncation).
- **Build identity per cell was not recorded.** Only `q27m-v4b` ran with the update check off; the other runs used
  OpenClaw's defaults. Each `run.log` names one build at the start; no run recorded executable or gateway identity per
  cell. The two runs known to be affected by the self-update (`q27m-v4`, `q27m-fp`) are quarantined (Cohorts).
- **OpenClaw's prompt estimate ran 1.5–1.7× the server's count** on the lived-in first requests (e.g. 35,922 vs
  23,817, `runs/footprints.txt`), and that estimate decides when OpenClaw ends a turn with its context-overflow message.
  The 43–47 % lived-in saving comes from one first-request pair per model; prefill timings are not compared.
- **Gemma ran with default sampling** while the Qwen models ran with Qwen's published settings.
- **Ollama's prefix cache was not disabled.** The footprint number is the server's `prompt_eval_count` for a fresh
  session's first request.
- **Earlier runs (2026-11-19, kit ≤ v1.1) are withdrawn.** One OpenClaw home served a whole run, so OpenClaw's
  background "Proactive check" automation and resumed sessions shared the model and were graded with the tasks. v1.2
  was written to remove that. In these runs, 10 task attempts (8 invalid, 2 incomplete) were rerun once (4 in
  `q27m-v4b`, 1 in `q27m-pr-v4` and 5 in `q27m-pr-lv4`; see each `run.log`), plus 5 (4 invalid, 1 incomplete) in the
  quarantined `q27m-v4`. No other run needed a rerun. All 12 invalid attempts were caught by the detector above: 11 by
  cron-marked main-session requests and 1 by another suite task's session.
