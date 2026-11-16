# Evidence packet: openclaw/openclaw#192790 (heartbeat monitor scratch, release 2026.11.3)

Status: **draft, not yet reviewed by the human publisher, not posted.** Synthetic content only. Redacted copies; the private raw
bundle is kept in the lab and is not identified by the hashes in this packet.

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#192790: an idle heartbeat keeps dispatching the model once a `no_change` scratch note is stored |
| Run ID | L192790 (bench `b192790`, monitor job `2bd49155-13b7-4ff9-9c55-517c83852c00`; Part 2 job `c7987ae3-a975-4589-adfe-9b285273c7c4`) |
| UTC time | Part 1: 2026-11-16T10:58:38Z – 11:25:04Z. Part 2: 11:29:49Z – 11:54:06Z. Part 3 attempts: 11:56:05Z – about 12:02Z |
| Release | OpenClaw 2026.11.3 (847611d), npm global install in an Ubuntu 24.04 Incus container |
| Route | embedded runner, provider `ollama` (api `ollama`) pointed at a scripted provider (`hb_mock.py`) on 127.0.0.1 |
| Configuration that matters | `messages.visibleReplies: "message_tool"`, `agents.defaults.heartbeat.every: "1m"`, `target: "none"` |

**Narrow assertion and outcome — `reproduced`.** On 2026.11.3 with `messages.visibleReplies=message_tool`, a scripted
provider proposed a `no_change` scratch note on six consecutive heartbeat ticks; each proposal was accepted and the
note was stored as non-empty monitor scratch (sampled revisions 3, 4, 6, 7, 8). After the proposals stopped, the
model was still dispatched on each of the four subsequent observed ticks (4 heartbeat requests, 0 empty-scratch skips
observed), with the note present in the current-turn heartbeat prompt and the stored scratch unchanged at revision 8.

**Controls (same release, same bench):**
- Missing scratch (A1): model dispatched on 4 of 4 ticks. Observed.
- Explicit comment-only scratch `<!-- idle: nothing to check -->` (A2, and again after the note in A4): 0 model
  requests over 4 ticks each; last recorded heartbeat status `skipped`, reason `empty-heartbeat-file`. Observed.
- Default embedded configuration without `messages.visibleReplies` (A5): the heartbeat prompt does not ask for
  `heartbeat_respond`; the scripted provider called it anyway with a `scratch` note; the tool returned an error
  ("heartbeat_respond is only accepted during a heartbeat run"), each of the 3 heartbeat runs ended `failed` /
  `agent-runner-failure`, and the scratch stayed missing. The proposal did not persist in this configuration.
  Observed.

**Real local model (Part 2) — `not reproduced under these conditions`.** Qwen (`qwen3.8:27b-q4_K_M`, requested
`num_ctx` 262144) on six idle 4-minute ticks called `heartbeat_respond` six times, never with a `scratch` argument,
and the scratch stayed missing (revision 0). The trigger precondition (a scratch proposal) was not reached, so this
neither refutes the scripted mechanism nor says how often a model proposes a note.

**Fix line (Part 3) — `blocked`.** 2026.11.5-beta.4 installed (exit 0) but refused to start with the kit's config:
`agents.defaults: Unrecognized key: "heartbeat"` ("Heartbeat configuration retired"). This is a kit compatibility
block (the runner always writes the retired key), not a product finding. Automations migration, preserved-note
recovery and missing/comment-only semantics on current source were **not tested**.

**Attempts and failures.** One run of each phase. Part 1: 6 note proposals, 6 accepted; 4 later plain ticks, 4
dispatched; 0 harness failures. A5: 3 of 3 heartbeat runs failed (expected for that control). Part 2: 6 ticks, 15
chat requests, 0 non-200. Part 3: 2 gateway start attempts, 2 config refusals (one after a diagnostic
`openclaw doctor --fix` on the beta home).

**Limits.**
- Scripted provider: shows the mechanism, not how often real models write such a note.
- Scratch was sampled by CLI reads about once a minute, not after every tick: revision 5 was never observed;
  per-tick writes are derived from revision numbers and timestamps, not observed one by one.
- `openclaw system heartbeat last` records only the most recent heartbeat per phase. The gateway log prints no line
  for a skip (A2's skip control has an empty log window), so the absence of `empty-heartbeat-file` in the log is not
  evidence. "No skip" on a tick is supported by a model request at that tick time, not by a log line.
- Four post-proposal ticks over about four minutes. Nothing is claimed about longer periods.
- One local model, six ticks, a fresh bootstrap workspace.
- The session (`agent:main:main`) carried history across phases and across the A5 gateway restart (63 messages at
  A5's first request).
- Bench is an Incus container sharing the lab host kernel; Part 2's model runs remotely (<LAB-MODEL>), so this is one
  OpenClaw client against one remote Ollama.

**Reported preconditions not matched.**
- The reporter used the Codex harness/runtime; this run used the embedded runner with `message_tool`. Codex was not run.
- The reporter's model wrote the note itself over four days (revision 158, 204 calls); here a scripted provider wrote it
  for six ticks.
- The reporter's exact version, OS and model are not reproduced here (not checked against this packet).
- Two other commenters report the missing-scratch case; A1 covers only that the model is dispatched when scratch is
  missing, not their token or cost figures.

## Inputs

- **Package:** see `inputs/versions.txt` (banner, install command, registry `dist.integrity`, what is unknown).
- **Kit:** `kit/hb_mock.py` (sha256 `6608081e14a9611cf4cfc70983f0c48033049ddbd0e5041940ffd9e5271d6491`),
  `kit/run192790.sh` (original sha256 `58ff4a6f79cbd7cb5cb41da1ee13a154bc37faf9f6e0a07dfe3ac229b9153f71`), shipped as
  `kit192790.tgz` sha256 `a83473722c7e95df6c1bb12fd028537f6df86d6f2be643d5e2d2aed724fad3e0` (the ticket's value; the
  worker and this packet both re-hashed it). `hb_mock.py` here is byte-identical to the original. The published
  `run192790.sh` is a redacted copy: the lab filter address is replaced by `http://<RELAY>` (three lines), so its
  hash in `MANIFEST.sha256` differs from the original hash above. To replay Part 2, set your own Ollama endpoint there. `kit/p_stats.py.generated` is the stats helper `run192790.sh` writes at
  run time (copied from the bench, not part of the tgz).
- **Exact invocation** (from the lab controller; `<LAB-HOST>` is the lab Linux host):
  ```
  ssh <LAB-HOST> '{ bench new ubuntu/24.04 b192790 && bench openclaw b192790 2026.11.3; }'
  bench exec b192790 -- bash /root/r192790/run192790.sh prep
  bench exec b192790 -- bash /root/r192790/run192790.sh start mock
  bench exec b192790 -- bash /root/r192790/run192790.sh oc mock cron scratch 2bd49155-13b7-4ff9-9c55-517c83852c00 --json
  bench exec b192790 -- bash /root/r192790/run192790.sh part1 2bd49155-13b7-4ff9-9c55-517c83852c00
  bench exec b192790 -- bash /root/r192790/run192790.sh start qwen 262144
  bench exec b192790 -- bash /root/r192790/run192790.sh qwen c7987ae3-a975-4589-adfe-9b285273c7c4
  bench exec b192790 -- bash /root/r192790/run192790.sh install-beta
  bench exec b192790 -- bash /root/r192790/run192790.sh start beta
  ```
  `bench` is a private lab helper and is not included (its hash in `inputs/versions.txt` identifies it for us only).
  To replay without it: start an Ubuntu 24.04 container, install Node 24 and `npm install -g openclaw@2026.11.3`,
  copy `kit/` to `/root/r192790/`, then run the `run192790.sh` lines above inside it as root.
  Part 1 phases (from `raw/part1/steps.log`): A1 mode=plain action=unset; A2 plain/comment; A3a note/unset (wait 270 s);
  A3b plain/none; A4 note/comment; A5 note/unset after restarting the gateway without the `messages` block. Tick 60 s.
  Mock mode is a one-word file re-read on every request (`note` = reply with `heartbeat_respond` + the reporter's
  `scratch` text; `plain` = same without `scratch`).
- **Redacted config:** `inputs/config-mock-A1-A4.json` (with `message_tool`), `inputs/config-mock-A5.json`
  (without), `inputs/config-qwen-part2.json`, `inputs/config-beta-part3.json`. Gateway token replaced by `<TOKEN>`.
  `apiKey: "ollama-local"` is a placeholder string, not a credential.
- **Resolved paths (inside the bench):** `OPENCLAW_HOME=/root/r192790/home-mock`; config
  `/root/r192790/home-mock/.openclaw/openclaw.json` (worker read back the written config before Part 1); state under
  `/root/r192790/home-mock/.openclaw/` (`/root/.openclaw` absent, worker note); workspace `/root/r192790/ws-mock`;
  session key `agent:main:main`, session id `70f7a616-9fd1-4cac-b20f-3143f66ae5fe` (A5 log); gateway log file
  `/tmp/openclaw/openclaw-2026-11-16.log` (gateway banner). Part 2 home `/root/r192790/home-qwen`.
- **OS / arch / runtime / privileges:** see `inputs/versions.txt`. Runner and gateway ran as root inside the container.
- **Backend:** Part 1 none (scripted). Part 2 Ollama via the lab filter `<RELAY>`; model digest unknown; effective
  context unknown; requested 262144; largest `prompt_eval_count` 17632 (filter record).
- **Capture position:** `hb_mock.py` sits between the gateway and the provider on 127.0.0.1 (port 11434 in Part 1,
  where it is the provider; port 11436 in Part 2, where it relays unchanged to `<RELAY>`). It logs the request body
  the gateway sent (Part 1, full bodies) or a per-request summary (Part 2). The lab filter's `/lab/stats` records
  (Part 2) are taken after the bench relay and before Ollama. Filter revision unknown.

## Outputs in this packet

| Path | What |
|---|---|
| `ASSERTIONS.md` | claim → artifact → observation → limitation |
| `raw/part1/steps.log` | phase start/end times, actions, exit codes |
| `raw/part1/scratch-reads.txt` | every CLI scratch read (before/after each action, then about every 60 s) |
| `raw/part1/A*-action.txt` | output of the scratch action that opened each phase |
| `raw/part1/A*-hblast.txt` | `openclaw system heartbeat last --json` at each phase end |
| `raw/part1/A*-stats.txt`, `table.txt` | per-phase request counts and tool calls/results (runner's `p_stats.py`) |
| `raw/part1/A1,A3a,A3b,A5-gateway-window.log` | gateway log lines during each phase (A2/A4 windows were empty and are omitted) |
| `raw/part1/kit-mock.out` | mock's own console, one line per request |
| `derived/request-ledger-part1.txt` | every chat request: scheduled heartbeat request vs tool continuation, current-turn scratch vs history (made by `tools/ledger.py` from the private request bodies) |
| `derived/current-turn-heartbeat-prompts.txt` | verbatim current-turn heartbeat prompt of requests #16, #18 (A3a), #28 (A3b), #4 (A5) |
| `raw/part2/*` | Part 2 steps, scratch reads, stats, `heartbeat last`, gateway lines, relay console |
| `derived/labstats-part2-new-records.jsonl` | the 15 filter records added during Part 2 (after-minus-before) |
| `raw/part3-beta/*` | beta install log and the verbatim config refusal |
| `MANIFEST.sha256` | sha256 of every other file in this packet |

Not included (kept private in the lab): full request bodies (`requests-mock.jsonl`, 2.6 MB, includes the 38 KB
system prompt), full gateway logs, the worker's notes, and the filter's earlier records.

## Packet notes

- Mock's `scratch_in_prompt` flag scans the whole history. In A5 it reads True although the current-turn prompt
  has no scratch block (older turns do). `derived/request-ledger-part1.txt` separates the two; use its
  `current_turn_scratch` column.
- "Scratch" here is the heartbeat monitor job's scratch (`openclaw cron scratch <job>`), not the `HEARTBEAT.md`
  file. The note text mentions `HEARTBEAT.md` only because it is the reporter's wording.
