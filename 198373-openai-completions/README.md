# Evidence packet: openclaw/openclaw#198373 on the OpenAI-compatible route (`openai-completions`, `POST /v1/chat/completions`), 2026.11.4 and 2026.11.5

Status: lab evidence, built 2026-11-18 from the runs' pulled raw files; the 2026.11.5 run (`T198373v5`) was added the
same day. Folders in this repository are published after
the maintainer's review (see the repository README). This is the follow-up to the native Ollama `/api/chat` packet
(`../198373/`). It does not repeat that run. Every file listed in `MANIFEST.sha256` is in this folder, and the
manifest covers only these copies (see "Custody").

**Record numbers.** "Record N" means the 0-based line index in `raw/<tag>/cache-trace.jsonl` (file line N+1). Both
traces have 39 records in the same layout (records 18, 27 and 36 are the last `stream:context` of run 1 and the first
of runs 2 and 3). The kit's analyzer (`analysis-trace-<tag>.txt`) numbers only records that carry a `messages` field,
so its `#13` and `#20` are records 18 and 27 here. Each record also has its own per-run `seq`, which
`tools/verify198373v1.py` prints.

## Two releases, same kit

The same inner kit, byte for byte (its archive and file hashes match the 2026.11.4 order; see "2026.11.5 run" below),
was run on 2026.11.4 on 2026-11-17 and on 2026.11.5 on 2026-11-18, against the same Ollama version (0.40.16) and model
name (`qwen3.8:27b-q4_K_M`) behind the same filter process (its request counter continues from the 2026.11.4 run:
`a8e78b-15`, then `a8e78b-17` on, in `raw/v115/lab-stats-v115.json`). The model digest was captured in neither run.

| | 2026.11.4 (`d843d6a`), run `T198373v1` | 2026.11.5 (`e13cf15`), run `T198373v5` |
|---|---|---|
| Wire, run 1 last → run 2 first (seq 5 → 6) | append-only (identical prefix 49,786 bytes = end of seq 5's `messages`); other top-level fields identical; 0 `__openclaw` / `runId` keys | append-only (identical prefix 53,134 bytes = end of seq 5's `messages`); other top-level fields identical; 0 keys |
| Tool-call id | model returned `call_6yhilm61`; `call6yhilm61` sent in seq 5, 6 and 7 | model returned `call_nd55xwq9`; `callnd55xwq9` sent in seq 5, 6 and 7 |
| Backend counters, run 2 first | 15,149 of 15,330 prompt tokens cached | 17,213 of 17,432 cached |
| Control, run 2 last → run 3 first (seq 6 → 7) | append-only; 15,326 of 15,500 cached | append-only; 17,428 of 17,640 cached |
| cacheTrace: replayed `toolResult` in `stream:context` | no `__openclaw` in run 1 (record 18); `__openclaw.runId` added in run 2 (record 27), kept in run 3 (record 36). First stamped `toolResult`: record 21 (run 2 `session:loaded`) | `__openclaw.runId` already present in run 1 (record 18); the same serialization, byte for byte, in records 18, 27 and 36 |
| cacheTrace: run 2's `cache:state` (record 26) | `prefixUnchanged: false`, change `content[0].id` on message 2 | `prefixUnchanged: true`, `changes: null` |
| Gateway `[prompt-cache]` lines | 1 (run 2): `message 2 (assistant) differs … changed fields: content[0].id` | 0 in the 185-line gateway log; `gw-promptcache-v115.txt` is empty. Gateway file log: 0 `prompt-cache` entries, 2 WARN entries from `agent/embedded` (the subsystem that logged the 2026.11.4 line; the 2026.11.4 file log has that line) |

Plain statement: **on both releases the request bodies stayed append-only and the backend cache held. On 2026.11.4
OpenClaw's own history changed internally between runs and its watchdog warned; on 2026.11.5 the history handed to
the model request (`stream:context`) already carried the stamp in run 1 and was unchanged in runs 2 and 3, and the
watchdog logged nothing.** Other trace stages still differ on 2026.11.5 (the raw id and a `details` field in run 1's
`session:after`, see B10). One session, one tool call, one backend per release.

What this does not show:
- **Which 2026.11.5 change caused the difference.** Not examined. The watchdog's source file
  (`src/agents/embedded-agent-runner/prompt-cache-observability.ts`) differs between the two tags (git blob
  `c03ffeb1…` at `v2026.11.4`, `bd0dd609…` at `v2026.11.5`), and `v2026.11.5` is not a descendant of `v2026.11.4`
  (GitHub compare: `diverged`, 11,811 commits ahead, 1,779 behind; read 2026-11-18). Either could matter.
- **That the 2026.11.4 warning came from the raw vs. sanitized id.** On 2026.11.5 the trace still holds the raw id
  `call_nd55xwq9` in run 1's `session:after` (record 20) and in the `session:loaded` records of runs 2 and 3 (records 21
  and 30), the same pattern as on 2026.11.4, yet no warning was logged. The 2026.11.5 run neither confirms nor refutes
  that inference (assertion 14).
- Anything about 2026.11.2 or 2026.11.3 (the releases in the reports), other backends, reasoning models, longer
  sessions or system-prompt changes (see "Limits").

The sections "Summary" through "Custody" below describe the 2026.11.4 run. The 2026.11.5 run has its own section at
the end, "2026.11.5 run (T198373v5)", which lists only what differs.

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#198373 (replayed history is not append-only between turns: tool-call ids regenerated, `__openclaw.runId` stamped onto replayed tool results) |
| Lab run ID | `T198373v1` (ticket `20261117-1830-27-lab-198373-v1-route`), tag `v114` |
| Observation time (UTC) | 2026-11-17T18:56:50Z – 18:59:00Z (`raw/v114/steps.log`) |
| Route | OpenClaw custom provider `lab-qwen`, `api: "openai-completions"` → `POST /v1/chat/completions` on Ollama, streamed, with `stream_options.include_usage` |
| Attempts / failures | One attempt; 0 failures in the run. Run 1 produced a tool call and tool result on the first try (no retry); the preflight passed on its first attempt. One worker command failed afterwards, during bench destruction (see "Custody") |
| Outcome | stamp or id change on the wire: **not reproduced under these conditions**; internal trace stamp and watchdog warning: **reproduced**; backend cache loss: **not reproduced under these conditions**. In plain words: the wire payload stayed stable despite an internal warning |

### Narrow assertions and outcomes

| # | Assertion | Result on 2026.11.4 | Evidence kind |
|---|---|---|---|
| A1 | Run 2's first request is byte-append-only over run 1's last request, and every top-level field other than `messages` (`tools` and their order, `max_tokens`, `stream_options`, `model`, `stream`, `tool_choice`) is identical | observed: yes (seq 5 → seq 6) | observed |
| A2 | The captured request bodies carry an `__openclaw` or `runId` JSON key | not reproduced under these conditions (0 keys in all 6 captured chat requests: the preflight and OpenClaw's 5) | observed |
| A3 | In OpenClaw's own `diagnostics.cacheTrace`, run 2's replayed `toolResult` carries `"__openclaw": {"runId": "<run 1's runId>"}`, which it did not carry in run 1's last `stream:context` | reproduced (record 18 vs record 27) | observed |
| A4 | The gateway's prompt-cache watchdog logs an append-only warning on run 2's first request | reproduced: `message 2 (assistant) differs from the previous request; history must be append-only; changed fields: content[0].id`. The source names this change `historyRewrite`; the trace records its code only as `"***"` | observed (the name `historyRewrite`: source-supported) |
| A5 | The model's tool-call id `call_6yhilm61` was sent back as `call6yhilm61` (underscore removed) in all 3 replayed requests, including run 1's own continuation, so the wire id did not change between the two runs | observed | observed |
| A6 | Run 2's first request lost the backend prefix cache | not observed: `cached_tokens` 15149 of `prompt_tokens` 15330 (Ollama's `usage.prompt_tokens_details` in the final stream chunk, as relayed) | observed (measured) |

Plain statement: **on this route and this backend, the replayed history on the wire stayed append-only and the
backend cache held, while OpenClaw's own trace and watchdog reported a change.** This matches the native-route
result (`../198373/`) for the `__openclaw.runId` stamp. For the tool-call id it differs: the native runs got the same
id shape from the same backend (`call_4qt7agvr` on 2026.11.3, `call_wv9i28u6` on 2026.11.4, in that packet's
`wire-*-chat.jsonl`). There OpenClaw replayed the id unchanged and no `content[i].id` warning appeared. On this route
it sent the id without the underscore and the warning appeared (2026.11.4). The native packet's assertion row 5
originally said "no underscore-bearing IDs occurred"; that was wrong (the ids did carry an underscore, and that route
did not change them) and row 5 has been corrected in the same publish.

### What the watchdog line does and does not show

- **The watchdog names only the first differing message** (source-supported, in the release that ran). In the
  2026.11.4 source at tag `v2026.11.4` (`d843d6af39a42cd3c30084edbeabeece732fd93a`),
  `src/agents/embedded-agent-runner/prompt-cache-observability.ts` lines 574–576 compute
  `divergence = previous.history.findIndex(...)` and report that one index as a single `historyRewrite` change
  (https://github.com/openclaw/openclaw/blob/d843d6af39a42cd3c30084edbeabeece732fd93a/src/agents/embedded-agent-runner/prompt-cache-observability.ts#L574-L576).
  The registry tarball `openclaw-2026.11.4.tgz` (sha512 equal to the `dist.integrity` below) has the same code in
  `dist/attempt-system-prompt-prepare-BJzLf74w.mjs` line 750 (file sha256
  `f4b27d8123eec2eeb73a1dc7939e4ce487edcfe739329bc340730f74257bb114`). The chunk names in this run's gateway file log
  (`console-Co7MoKLd.mjs`, `logger-CTQV8XKu.mjs` in `fullFilePath`) are present in that tarball. Here the first
  differing message is message 2 (the assistant tool call), so the line does not mention the stamped `toolResult`
  (message 3) that the native run's watchdog reported as `envelope.__openclaw`.
- **The Gateway logs this warning once per session key per process** (source-supported, same file and tag: line 99
  creates `historyRewriteWarnings = createDedupeCache({ ttlMs: 0, ... })`, an entry with `ttlMs: 0` never expires, and
  lines 615–619 log only on the first hit; in the tarball, `dist/attempt-system-prompt-prepare-BJzLf74w.mjs` lines
  479–482 and 777 and `dist/dedupe-5aqLNx3Q.mjs`). Run 3 used the same session key in the same Gateway process
  (pid 960), so a missing log line in run 3 shows nothing. The trace does: run 2's `cache:state` (record 26) has
  `prefixUnchanged: false` with the message-2 change, and its `cache:result` (record 28) lists it; run 3's
  `cache:state` (record 35) has `prefixUnchanged: true`, `changes: null`, and its `cache:result` (record 37) has
  `changes: null`.
- **Which two id strings the watchdog compared is not logged.** Observed: the model returned `call_6yhilm61`
  (seq 4 response stream). In the trace, `call_6yhilm61` appears only in run 1's `session:after` (record 20) and in
  the `session:loaded` records of runs 2 and 3 (records 21 and 30). The other 13 records that carry the call use
  `call6yhilm61`: every `session:sanitized`, `session:limited`, `prompt:*` and `stream:context` record, and the
  `session:after` records of runs 2 and 3 (records 29 and 38). All 3 replayed requests on the wire use `call6yhilm61`.
  `session:after` records the in-memory message snapshot at the end of a run, not the stored transcript
  (source-supported: `dist/builtin-openclaw-CslO-Opu.mjs` line 1186 in the 2026.11.4 tarball,
  `recordStage("session:after", { messages: messagesSnapshot, ... })`). The stored transcript was checked privately:
  the bench's state database (in the excluded `home/` folder) holds the raw form 3 times and the sanitized form 0
  times. That the watchdog compared the raw form against the sanitized form is **inferred**. It is consistent with the
  observer-layer reading in the 2026-11-14 comment on the issue by another contributor
  (https://github.com/openclaw/openclaw/issues/198373#issuecomment-6886009928); we did not inspect that code path.
- Between run 1's last and run 2's first `stream:context` records (records 18 and 27), messages 0–2 (including the
  assistant tool call) are identical as parsed JSON, and the `toolResult` (message 3) differs only by the added
  `__openclaw` key (`tools/verify198373v1.py`).

### Supporting counters

Backend fields from Ollama's OpenAI-compatible `usage` in the final stream chunk, as relayed by the lab filter; the
filter's own record for the same `X-Lab-Request-Id` has the same values, but it parses them out of the same chunk it
relays, so it is not independent. `uncached` is derived. Filter `bytes` equals the UTF-8 length of the captured body
in every request.

| Request | seq | filter id | `prompt_tokens` | `cached_tokens` | uncached (derived) | `completion_tokens` | body bytes | proxy `secs` | gap before (s) |
|---|---|---|---|---|---|---|---|---|---|
| warm turn | 3 | a8e78b-11 | 15086 | 0 | 15086 | 75 | 63,744 | 70.546 | — |
| run 1, tool call | 4 | a8e78b-12 | 15101 | 14574 | 527 | 74 | 63,815 | 6.621 | 73.2 |
| run 1 last (tool result) | 5 | a8e78b-13 | 15153 | 15097 | 56 | 26 | 64,057 | 2.258 | 6.7 |
| **run 2 first** | **6** | **a8e78b-14** | **15330** | **15149** | **181** | 289 | 64,710 | 14.09 | 3.8 |
| run 3 first (control) | 7 | a8e78b-15 | 15500 | 15326 | 174 | 15 | 65,358 | 2.33 | 15.7 |

In each of seq 5, 6 and 7, `cached_tokens` is exactly 4 lower than the previous request's `prompt_tokens`. Why is not
investigated; the verdict does not rest on it. OpenClaw's own `cache:result` record for run 2 (record 28) reports
`broke: false`, `cacheRead` 15149 (adapter-derived from the same fields, not independent). Seq 6 took 14.09 s because
the model generated 289 tokens (its response stream carries `reasoning` deltas; none of the 5 captured OpenClaw
requests carried `reasoning_effort`); this is latency, not part of the prefix question.

### Limits

- **One session, one tool call, one model, one backend, per release (2026.11.4 and 2026.11.5).** Counts only; no rate is implied.
  This says nothing about other OpenAI-compatible backends, longer histories, multiple tool calls per turn, or ids
  that the sanitizer would change differently.
- **Unmatched preconditions from the reports:**
  - *Release.* The issue and its minimal repro are on 2026.11.3 (`847611d`); the 2026-11-14 contributor reports are
    on 2026.11.2. This route was run on **2026.11.4 and 2026.11.5 only**. At the 2026.11.4 run the gateway's
    update notice reported `v2026.11.5` as latest (`gw-v114.log` line 127). No 2026.11.2, 2026.11.3, beta,
    current-main or candidate build was tested on this route.
  - *Backend.* The reporters used DeepSeek via a hosted proxy, and oMLX. Neither was tested.
  - *Reasoning.* The issue's model row has `reasoning: true`, its warnings name `content[1].id` / `content[2].id`,
    and one of its warnings is a `reasoning_effort` parameter change. Here the model row has no reasoning flag, none
    of the 5 captured OpenClaw requests carried `reasoning_effort`, the replayed assistant messages carried no
    reasoning content, and the stored assistant message was one `toolCall` block at `content[0]`. Reasoning replay
    and the `reasoning_effort` signal were not exercised.
  - *System prompt.* The system message (index 0) was byte-identical across both pairs (same system-prompt digests in
    every `cache:state` record of the session). The 2026-11-14 reports place their cache drops on system-message
    changes; that symptom was not exercised, and this limit qualifies "the backend cache held".
  - *Token-limit field.* The model row pinned `compat: {"maxTokensField": "max_tokens"}` (`kit/openclaw.json`
    line 16), and every captured chat request in both releases sent `max_tokens: 4096` (`raw/v114/wire-v114.jsonl`,
    `raw/v115/wire-v115.jsonl`, seqs 2–7). A comment on the issue from another user (2026-11-18 17:19:57Z) reports
    `historyRewrite` with `provider-input-change:parameters:max_completion_tokens` on 2026.11.5 with Exo/MLX, cured
    by that same pin. This run could not show a field-name switch. (Added 2026-11-18 after that comment.)
  - *Session length.* Requests here held 3 to 11 messages; the report's warnings name messages 139 and 290.
  - *Id shape.* The model's ids here were `call_` plus 8 lowercase alphanumerics; the reporters' ids were longer
    (for example `call_<32 hex>_<n>` on oMLX).
- **Topology.** One OpenClaw client in an Incus **container** (it shares the Linux host kernel), talking through an
  in-container logging proxy and the lab filter/relay to **one remote Ollama on an Apple Silicon host**
  (`<LAB-MODEL>`). Not native inference on Linux.
- **Shared model.** The filter's log shows no other request between seq 5 and seq 6 (ids a8e78b-13 and a8e78b-14 are
  consecutive), but whether every client of that Ollama goes through this filter is **unknown**.
- **Effective server context unknown.** None of the 5 captured OpenClaw requests carried a context-size field;
  `/api/ps` was not captured. Requests were about 15.3K prompt tokens, so this run says nothing about a 262K window.
- **Request bodies only.** Request headers were not logged. The capture proxy forwards only `Content-Type` and
  `Content-Length`, and the relay builds its own upstream headers, so the backend never saw OpenClaw's other headers.
  The comparison covers request bodies only.
- **Cause not investigated.** Why the wire carries neither the stamp nor the raw id (serializer construction vs.
  stripping) was not examined in source for this packet.
- The worker's report contradicts itself on the id (it says OpenClaw "stripped nothing", then that the underscore
  was removed). The wire bytes above are what this packet relies on.

### Harness gaps (do not affect the decisive files)

- The kit analyzer labels a **character** offset as "first differing byte offset" (`raw/pairs/*.txt`,
  `analysis-wire-v114.txt`). The bodies contain 9 non-ASCII characters before that point, so seq 5's 49,768
  characters are 49,786 bytes, and seq 5 is 64,039 characters but 64,057 bytes (the filter's `bytes`). The verify
  script prints both.
- `analysis-trace-v114.txt` runs the wire comparison over consecutive trace records across stages, so its
  "APPEND-ONLY … NO", "STAMP … in the NEW request" and "byte offset of the whole serialized request" lines compare
  trace stages, not requests. They do not bear on A1 or A2.
- `v114.console` (the kit's stdout and stderr) was never pulled out of the bench; nobody inspected it.
- The OpenClaw install log was not pulled (see "Inputs").
- The worker's first destroy block failed (see "Custody"); the second ran.
- A lab-side 5-minute automation the worker created for this ticket (`T198373v1 bench create`) outlived the ticket
  and was removed on 2026-11-18. It ran on the worker, not in the bench, after the bench was destroyed.

## Inputs

### OpenClaw package

| Field | Value | Kind |
|---|---|---|
| Banner | `OpenClaw 2026.11.4 (d843d6a)` (`raw/v114/steps.log` line 1; also the worker's bench preflight, `raw/worker/evidence.txt`) | observed |
| Registry `dist.integrity` for 2026.11.4 | `sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==` (`npm view`, read 2026-11-16; in the native packet `../198373/raw/install/npm-view.txt`). A registry tarball with this sha512 was used for the source citations above | documented |
| Tag | `v2026.11.4` → commit `d843d6af39a42cd3c30084edbeabeece732fd93a` (GitHub API, read 2026-11-17) | documented |
| Integrity of the tarball actually installed | unknown (not captured before the bench was destroyed) | unknown |
| Install method | fresh container, `bench openclaw r198373 2026.11.4`: the lab bench tool (published as `../198373/raw/install/bench-tool.sh`) installs the official Node tarball, SHA-checked, then `npm install -g openclaw@2026.11.4`. The install log was not pulled; the worker recorded exit 0 and the banner (`raw/worker/evidence.txt`) | documented |
| Whether npm ran install scripts | unknown (the install log was not pulled) | unknown |
| Resolved install path | `/usr/local/lib/node_modules/openclaw/dist/…` (`fullFilePath` in `raw/v114/oclog-openclaw-2026-11-17.log`) | observed |
| Running Gateway | `openclaw gateway run` from the same install (pid 960); its log reports `current v2026.11.4` (`raw/v114/gw-v114.log` line 127). No separate gateway commit banner is logged | observed |

### Test kit

- Kit archive `kit-198373v1.tgz`, sha256 `<REDACTED-UNREDACTED-KIT-HASH>`, verified on the worker's Mac and inside the
  bench (`raw/worker/evidence.txt`). Original file hashes: `analyze198373v1.py`
  `89630ccea43d45c13f18042ade7a0f80a9190f358ac391a35d3ebfa74bd533f0`, `openclaw.json`
  `3140b7c9fe3bb119ad541f18cacebe62537dde00117df146243bf621f1707be0`; `run198373v1.sh` and `logproxy.py`
  `<REDACTED-UNREDACTED-KIT-HASH>`.
- Published copies in `kit/`: `analyze198373v1.py` and `openclaw.json` are byte-identical to the originals.
  `logproxy.py` and `run198373v1.sh` have the relay address replaced with `<RELAY>`. The hashes of the unredacted
  archive, of these two files and of the unredacted `proxy.log` are withheld, because they would let a guess at the
  redacted address be confirmed.
- Exact invocation (inside the bench, as root):
  `cd /root/r198373 && (setsid nohup bash kit-198373v1/run198373v1.sh v114 > v114.console 2>&1 < /dev/null &)`.
- What the script runs (`kit/run198373v1.sh`):
  1. preflight: one direct streamed `/v1/chat/completions` request with one `read` tool (`raw/v114/preflight-req.json`,
     response `preflight-a.sse`), to qualify streaming, structured tool calls and streamed usage through the filter;
  2. gateway start;
  3. warm turn, session `warm`: `Reply with one word: warm.`;
  4. run 1, session `cache-repro`: `Use the read tool to read note.txt in your workspace, then reply with its first word only.`;
  5. run 2, same session: `Reply with one word: ready.`;
  6. run 3, same session (control): `Reply with one word: again.`.

  Each turn is `timeout 1500 openclaw agent --agent main --session-key <key> -m '<msg>' --timeout 1400 --json`.
  Fixture: `/root/r198373/ws/note.txt` = `lab-198373 synthetic note`.
- Replay check: `python3 -I -B tools/verify198373v1.py raw/v114 raw/v115` re-derives, for each release, A1–A6, the counters, the body sizes against
  the filter's `bytes`, the proxy times in UTC, the trace id forms, each `cache:state` / `cache:result` record of the
  session (`prefixUnchanged`, `changes`, `broke`, token fields, `modelApi`, `streamStrategy`), the gateway's
  `[prompt-cache]` line and the `steps.log` config read-backs, from the files in this packet. The kit's own analyzer:
  `python3 -I -B kit/analyze198373v1.py wire raw/v114/wire-v114.jsonl raw/v114/lab-stats-v114.json`
  and `… pair raw/v114/wire-v114.jsonl 5 6 raw/v114/lab-stats-v114.json` (the same with `v115`). The lab's
  mechanical verdict: `python3 -I -B kit/verdict198373.py raw/v115/wire-v115.jsonl` (also runs on `v114`).
- **Re-running on your own backend.** (1) The script expects the kit at `$ROOT/kit-198373v1/`; copy `kit/` there
  (default `ROOT=/root/r198373`). (2) Set `RELAY=host:port` to your OpenAI-compatible server; the published default
  is the placeholder `<RELAY>:11435`. (3) The kit's proxy listens on `127.0.0.1:11434`, so a local Ollama on its
  default port stops the run with `port-11434-busy`; run the backend on another port or host. (4) The proxy forwards
  only `Content-Type` and `Content-Length`, so a backend that needs an API key will refuse. A missing `/lab/stats`
  endpoint is fine: the analyzer prints `lab-stats: unreadable` and carries on.

### Configuration (redacted)

`kit/openclaw.json` as published. At run time the script substitutes a random throwaway gateway credential for
`REPLACE_ME`; it was never collected into this packet. The relevant settings:

- provider id `lab-qwen` (deliberately without "ollama"; the lab ticket documents this as keeping the Ollama plugin
  from injecting `options.num_ctx`; not tested here);
- `api: "openai-completions"`, `baseUrl http://127.0.0.1:11434/v1` (the in-bench logging proxy);
- model `qwen3.8:27b-q4_K_M` with `contextWindow 262144`, `maxTokens 4096`, no `reasoning` flag, and
  `compat: {"maxTokensField": "max_tokens", "supportsUsageInStreaming": true}`;
- provider `timeoutSeconds 1200`, `diagnostics.cacheTrace.enabled true`.

Read back by `openclaw config get` and `openclaw config validate` before the run (`steps.log` lines 2–6).

### Resolved paths

| What | Path | Evidence |
|---|---|---|
| `OPENCLAW_HOME` | `/root/r198373/v114/home` | set by `run198373v1.sh` |
| Config file | `$OPENCLAW_HOME/.openclaw/openclaw.json` | `steps.log` `Config valid: $OPENCLAW_HOME/.openclaw/openclaw.json` |
| Workspace | `/root/r198373/ws` | `workspaceDir` in `cache-trace.jsonl` |
| Session key | `agent:main:cache-repro` | gateway log, trace |
| Cache trace | `$OPENCLAW_HOME/.openclaw/logs/cache-trace.jsonl` | observed in the pulled `home/` (not published) |
| Gateway file log | `/tmp/openclaw/openclaw-2026-11-17.log`, copied as `oclog-openclaw-2026-11-17.log` | `run198373v1.sh` |

### Host, guest, runtime

| | Value | Kind |
|---|---|---|
| Guest | Incus container from `images:ubuntu/24.04` (requested image; exact guest build not recorded), running as root | documented |
| Kernel at run time | `Linux 7.0.0-43-generic (x64)` (OpenClaw's own runtime line inside the captured prompts) | observed |
| Guest runtime | Node 24.22.3, linux x64, V8 13.6.233.17-node.63, OpenSSL 3.5.9, SQLite 3.54.1 (`gw-v114.log` line 98) | observed |
| Isolation | container, shares the host kernel | documented |

### Backend

| | Value | Kind |
|---|---|---|
| Server version | `{"version":"0.40.16"}` from `GET /api/version` through the proxy and filter (`steps.log`, wire seq 1) | observed (filter-relayed) |
| Model | `qwen3.8:27b-q4_K_M`, `system_fingerprint: fp_ollama` in the response chunks. Digest `25b84361…` and `Q4_K_M` are from the native packet's `/api/tags` capture on 2026-11-16; not re-captured in this run | observed (name) / documented (digest) |
| Request fields sent by OpenClaw | top-level `model, messages, stream, stream_options, tools, tool_choice, max_tokens` only, in all 5 captured OpenClaw requests; `max_tokens` 4096; no `reasoning_effort`, no `keep_alive`, no context-size field | observed |
| Configured context | 262144 (`openclaw.json`) | documented |
| Effective server context | unknown (no `/api/ps` capture) | unknown |
| `keep_alive` | no request carried a `keep_alive` key | observed |
| Server cache / model residency settings | not captured | unknown |
| Cache counter provenance | `usage.prompt_tokens_details.cached_tokens` in Ollama's final stream chunk, as relayed; the filter parses and records the same fields from that chunk (`lab-stats-v114.json`) | observed |

### Proxy, filter and capture position

- **Capture point:** `kit/logproxy.py` on `127.0.0.1:11434` **inside the bench**, between OpenClaw and the filter. It
  logs each request body as OpenClaw sent it (with its sha256 at capture time), the response bytes as returned, and
  the filter's `X-Lab-Request-Id` and `Content-Type` response headers. Request bodies are re-sent upstream unaltered,
  with only `Content-Type` and `Content-Length` headers. Request headers are not logged. Responses are re-chunked on
  the way back to OpenClaw.
- **Downstream:** the lab filter/relay at `<RELAY>:11435` ("filter v4", installed sha256
  `545fb16a90024a74415ec126bc40e3ee8335d1a70c391d88471c087051bde199`, documented in the lab's install record), then
  Ollama. Filter v4 admits `/v1/chat/completions` only with `max_tokens` (refuses `max_completion_tokens`) and, on
  streams, `stream_options.include_usage`. Its allowed routes are `GET /api/version`, `GET /api/tags`,
  `POST /api/show`, `POST /api/chat`, `POST /v1/chat/completions` and its own `GET /lab/stats`; any other target is
  refused with 403. It rejects out-of-range requests rather than rewriting them. No request in this run was refused
  (all statuses 200).
- **Does the filter change bodies?** Source-supported (lab filter v4 source, not published): it forwards an accepted
  request body byte for byte, relays response bytes unchanged and only reads counters from them. Observed: the filter's `bytes` equals the UTF-8 length of every
  captured request body (63,744 / 63,815 / 64,057 / 64,710 / 65,358), and its counters match the captured response.
  Not captured: anything upstream of the filter.

## Outputs in this packet

| Path | What | Redaction |
|---|---|---|
| `raw/v114/steps.log` | run timeline, version banner, config read-backs, preflight line, exit code of every turn (`turn exit=0` ×4), clean stop of gateway and proxy by PID | none |
| `raw/v114/wire-v114.jsonl` | the whole proxy capture: seq 1 `/api/version`, seq 2 preflight, seq 3–7 OpenClaw's requests and responses | none; each `req` re-hashes to its captured `req_sha256` |
| `raw/v114/cache-trace.jsonl` | OpenClaw `diagnostics.cacheTrace` output (39 records) | none |
| `raw/v114/gw-v114.log`, `gw-promptcache-v114.txt`, `oclog-openclaw-2026-11-17.log` | gateway stdout, its prompt-cache line, gateway file log. `gw-promptcache-v114.txt` is not in the in-bench manifest (the kit writes it afterwards); it equals line 145 of `gw-v114.log` | none |
| `raw/v114/analysis-wire-v114.txt`, `analysis-trace-v114.txt` | kit analyzer output, as produced in the bench (see "Harness gaps" for how to read both) | none |
| `raw/pairs/pair-5-6.txt`, `pair-6-7.txt` | analyzer pair output for the pair that matters and the control, produced on the worker's Mac from the pulled copies | none |
| `raw/v114/run1.json`, `run2.json`, `run3.json`, `warm.json` | `openclaw agent --json` output of each turn (run IDs, status `ok`) | none |
| `raw/v114/lab-stats-v114.json` | the filter's request log as the kit fetched it. Records a8e78b-1…7 (17:07–17:10Z) predate this run by about 1 h 46 min and are the filter's installation checks per the lab log; a8e78b-8 is the worker's bench preflight; a8e78b-9…15 are this run | none |
| `raw/v114/preflight-req.json`, `preflight-a.sse` | the preflight request and its streamed response (`finish_reason: tool_calls`, usage present) | none |
| `raw/v114/proxy.log` | proxy start line | relay address → `<RELAY>` |
| `raw/v114/evidence-v114.sha256` | the in-bench manifest of the original files | the `proxy.log` row is removed (its hash is of the unredacted file); the other 14 rows are unchanged |
| `raw/worker/evidence.txt` | the worker's command log: bench preflight, kit hashes, launch, custody lines | lab host address → `<LAB-LINUX>`, bench addresses → `<BENCH-IP>`, one host name → `<LAB-LINUX>`; the hashes of the unredacted kit archive, `logproxy.py` and `run198373v1.sh` → `<REDACTED-UNREDACTED-KIT-HASH>`; in the three 2026-11-17T20:00:10Z custody error lines, the lab account's key path → `~/.ssh/lab_worker` and its user name → `<user>` |
| `tools/verify198373v1.py` | replay check over this packet (any tag folder) | — |
| `kit/verdict198373.py` | the lab's mechanical pair verdict, as used for `T198373v5` (sha256 `005f213b…`, byte-identical) | none |
| `raw/v115/…`, `raw/v115-host/…`, `raw/pairs-v115/…` | the 2026.11.5 run; see "2026.11.5 run (T198373v5)" | see there |

`raw/v114/` has 17 files: the 15 originals listed in the in-bench manifest, the manifest itself and
`gw-promptcache-v114.txt`.

Not included: the pulled `home/` folder (it holds the throwaway gateway credential and OpenClaw's state); the
worker's report (its claims are restated here only where re-checked against the raw files); the kit's empty `DONE`
marker. `v114.console` was never pulled (see "Harness gaps").

Exit codes: all four turns `exit=0` (`steps.log`); `openclaw agent` status `ok` in each `run*.json`. External timeout
`timeout 1500` per turn, not reached. Gateway stopped by SIGTERM from the kit at 18:58:58Z (`gw-v114.log` lines
150–152; `steps.log` `STOP … left:` with nothing left running).

## Custody

- The raw files were pulled out of the container as whole files before it was destroyed, and copied unmodified to the
  maintainer's private lab store. There, `sha256sum -c evidence-v114.sha256` gives `OK` for all 15 files.
- In this folder, 14 of those 15 files are byte-identical copies; `proxy.log` is redacted. The published
  `evidence-v114.sha256` has the `proxy.log` row removed (see "Outputs"), so `cd raw/v114 && sha256sum -c
  evidence-v114.sha256` reports `OK` for the 14 files it lists and exits 0.
- `raw/worker/evidence.txt` is a redacted copy (see "Outputs").
- Bench destruction, from the worker's own command log (`raw/worker/evidence.txt`):
  - a first destroy block at 20:00:10Z never ran (a quoting error: `no such file or directory: ssh …`);
  - `bench list` at 20:00:22Z showed `r198373` running;
  - `bench destroy r198373` ran once, at 20:00:33Z;
  - `bench list` at 20:00:45Z and `incus list` at 20:00:57Z no longer show it.

  The worker's narrative report gives a different time for the first list and omits the failed block; the command log
  is what this packet relies on.
- The throwaway gateway credential appears only in the excluded `home/` folder; a byte search of every published
  file for it finds nothing.
- `MANIFEST.sha256` hashes exactly the files in this folder (it does not list itself). Re-run
  `sha256sum -c MANIFEST.sha256` after any edit.

## 2026.11.5 run (T198373v5)

Everything not listed here is as in the 2026.11.4 run above: the same inner kit, configuration, prompts, fixture,
filter process, Ollama version and model name (digest not captured); the same capture point and the same record
layout.

### Summary

| Field | Value |
|---|---|
| Lab run ID | `T198373v5` (ticket `20261118-1300-29-lab-198373-v5`), tag `v115`, bench `r198373b` |
| Observation time (UTC) | 2026-11-18T13:04:27Z – 13:06:48Z (`raw/v115/steps.log`, `raw/v115-host/steps.log`) |
| Attempts / failures | One attempt, 0 turn-level failures. All four turns `exit=0`; one transient gateway-level error during the warm turn (see "Harness notes"); preflight passed on its first attempt; run 1 produced its tool call and tool result on the first try |
| Lab verdict | `raw/v115-host/verdict.txt` (from `kit/verdict198373.py`): both pairs `pass`, `append_only=yes params=identical stamp_keys=0`. Re-run here on the published copy: same two lines |
| Outcome | stamp or id change on the wire: **not reproduced under these conditions**; internal history change and watchdog warning: **not reproduced under these conditions**; backend cache loss: **not reproduced under these conditions** |

### Assertions (2026.11.5)

Rows B0–B11 in `ASSERTIONS.md`. In short: seq 5 → seq 6 is append-only with identical top-level fields and 0 stamp
keys (B1–B3); the id went out as `callnd55xwq9` in seq 5, 6 and 7 (B4); 17,213 of 17,432 prompt tokens cached (B5);
the replayed `toolResult` carries `__openclaw.runId` from run 1's `stream:context` on and is identical in runs 1–3
(B6); run 2's `cache:state` reports no change (B7) and no `[prompt-cache]` line was logged (B8), one comparison seen twice; control pair also append-only
(B9); the trace still shows the raw id at the same stages (B10); what changed is not examined (B11).

### Supporting counters (2026.11.5)

Same sources and caveats as the 2026.11.4 table. Filter `bytes` equals the UTF-8 length of the captured body in every
request.

| Request | seq | filter id | `prompt_tokens` | `cached_tokens` | uncached (derived) | `completion_tokens` | body bytes | proxy `secs` | gap before (s) |
|---|---|---|---|---|---|---|---|---|---|
| warm turn | 3 | a8e78b-20 | 17150 | 0 | 17150 | 449 | 74,545 | 94.304 | — |
| run 1, tool call | 4 | a8e78b-21 | 17165 | 16638 | 527 | 120 | 74,616 | 8.43 | 96.9 |
| run 1 last (tool result) | 5 | a8e78b-22 | 17217 | 17161 | 56 | 26 | 74,858 | 2.067 | 8.5 |
| **run 2 first** | **6** | **a8e78b-23** | **17432** | **17213** | **219** | 25 | 75,679 | 2.692 | 3.7 |
| run 3 first (control) | 7 | a8e78b-24 | 17640 | 17428 | 212 | 29 | 76,495 | 2.971 | 3.9 |

As on 2026.11.4, `cached_tokens` in seq 5, 6 and 7 is exactly 4 below the previous request's `prompt_tokens` (not
investigated). OpenClaw's `cache:result` for run 2 (record 28): `broke: false`, `promptTokens` 17432, `input` 219,
`cacheRead` 17213 (adapter-derived, not independent). Prompts are about 2.1K tokens longer than on 2026.11.4 and one
of the 14 tools differs (`github_publish` on 2026.11.5 where 2026.11.4 had `heartbeat_respond`); within each release
the system message and tool list were identical across both pairs.

### Inputs (2026.11.5)

| | Value | Kind |
|---|---|---|
| Banner | `OpenClaw 2026.11.5 (e13cf15)` (`raw/v115/steps.log` line 1; `raw/v115-host/steps.log`, `identity.txt`, `host.log`) | observed |
| Tag | `v2026.11.5` → commit `e13cf15ece9bbd969b7362927c315362c90c97ff` (GitHub API, read 2026-11-18) | documented |
| Registry `dist.integrity` for 2026.11.5 | `sha512-mqPlsGLOe8NS85BfP1vWW9YVwFXchsV75QTkEbyR4csylORxts+fmfZp9+qbD7aPbXQIctyjRk+CPL91fDvxBA==` (`npm view`, read 2026-11-18, after the run) | documented |
| Integrity of the tarball actually installed | unknown (not captured) | unknown |
| Install method | fresh Incus container from `ubuntu/24.04`, `bench openclaw r198373b 2026.11.5` (the same lab bench tool), driven by a lab-host script that then checks the installed version contains `2026.11.5` before running anything (`raw/v115-host/steps.log` `bench version` line). The driver script is not published: it embeds the unredacted inner kit | documented |
| Resolved install path | `/usr/local/lib/node_modules/openclaw/dist/…` (`fullFilePath` in `raw/v115/oclog-openclaw-2026-11-18.log`) | observed |
| Running Gateway | pid 820, same install; Node 24.22.3, V8 13.6.233.17-node.63, OpenSSL 3.5.9, SQLite 3.54.1 (`gw-v115.log` line 127); no update notice logged | observed |
| Kernel at run time | `Linux 7.0.0-43-generic (x64)` (runtime line inside the captured prompts) | observed |
| Inner kit | the 2026.11.4 kit unchanged: `raw/v115-host/steps.log` lists the in-bench `sha256sum` of the archive and its four files. `analyze198373v1.py` (`89630cce…`) and `openclaw.json` (`3140b7c9…`) match `kit/` here; the archive, `logproxy.py` and `run198373v1.sh` hashes are withheld as before (`<REDACTED-UNREDACTED-KIT-HASH>`) and were checked privately against the 2026.11.4 order: all equal | observed (private check: documented) |
| Backend | `{"version":"0.40.16"}` via the lab filter (`steps.log`, wire seq 1); model name `qwen3.8:27b-q4_K_M`; model digest not captured (in neither run). Same filter process as the 2026.11.4 run: `raw/v115/lab-stats-v115.json` still holds the 2026-11-17 records `a8e78b-1…15` and continues at `a8e78b-17`. "filter v4" in `identity.txt` is a constant the driver prints, not an observation | observed (filter-relayed) |
| Invocation | the lab-host driver ran, in the foreground, `bench exec r198373b -- sh -c "cd /root/r198373 && bash kit-198373v1/run198373v1.sh v115 > v115.console 2>&1 < /dev/null"` (the 2026.11.4 run was launched detached with `setsid nohup … &`, `raw/worker/evidence.txt`) | documented (driver not published) |
| Resolved paths | `OPENCLAW_HOME` `/root/r198373/v115/home` (set by `run198373v1.sh`); gateway file log `/tmp/openclaw/openclaw-2026-11-18.log` (`gw-v115.log`, `log file:` line), copied as `oclog-openclaw-2026-11-18.log`; everything else as for `v114` | observed / set by the kit |

### Outputs in this packet (2026.11.5)

| Path | What | Redaction |
|---|---|---|
| `raw/v115/` (17 files) | the 15 originals listed in the in-bench manifest, the manifest, and `gw-promptcache-v115.txt` (0 bytes: the kit's grep found no `[prompt-cache]` line). Same roles as the `raw/v114/` files above | `proxy.log`: relay address → `<RELAY>`; `evidence-v115.sha256`: the `proxy.log` row removed (its hash is of the unredacted file). The other 14 files are byte-identical; `cd raw/v115 && sha256sum -c evidence-v115.sha256` reports `OK` for all 14 |
| `raw/v115-host/steps.log` | the lab-host driver's timeline: bench creation, installed version, backend version, in-bench kit hashes, run start and exit | three kit hashes → `<REDACTED-UNREDACTED-KIT-HASH>` (archive, `logproxy.py`, `run198373v1.sh`) |
| `raw/v115-host/identity.txt`, `host.log`, `v115.console`, `verdict.txt` | version and backend identity; the driver's tool checks; the kit's console output (pulled this time); the lab's verdict | none |
| `raw/pairs-v115/pair-5-6.txt`, `pair-6-7.txt` | `kit/analyze198373v1.py pair` output on the published copies, produced on the maintainer's machine | none |

Not included: the bench's `home/` folder (never pulled: the driver excludes it), the driver script and its kit
archive (they embed the unredacted inner kit), the lab's custody record (it holds lab host addresses; summarized
below), the worker's report.

### Harness notes (2026.11.5)

- `proxy.log` holds three `ConnectionResetError` tracebacks from connections on `127.0.0.1` that sent no request
  line. All 7 requests in the capture completed with status 200 and each re-hashes to its captured `req_sha256`.
  Which client opened those connections was not investigated.
- The filter's log has no record `a8e78b-16` (between this run's records and the 2026.11.4 run's). It falls outside
  both runs; not investigated.
- The analyzer caveats in "Harness gaps" above apply to `analysis-wire-v115.txt` and `analysis-trace-v115.txt` too
  (character offset labelled "byte offset": seq 5's 53,110 characters are 53,134 bytes).
- During the warm turn the gateway answered one `agent` request with `errorCode=UNAVAILABLE … agent unavailable during
  gateway startup` (`gw-v115.log` line 141); the same request id was answered OK 1.7 s later (line 156) and the turn
  exited 0. Nothing like it is in the 2026.11.4 log. "0 failures" above is turn-level.
- `gw-v115.log` contains terminal colour codes (592 ESC bytes; `gw-v114.log` has none); strip them before grepping.
- `gw-v115.log` has two `[agent/embedded]` warnings not seen on 2026.11.4 (lines 159 and 163, at 13:06:22.6Z and
  13:06:33.7Z; which request each belongs to was not traced): the model "emitted reasoning while configured reasoning: false; reasoning was hidden". They are
  the 2 WARN entries in the file log; neither is a `[prompt-cache]` line.

### Custody (2026.11.5)

- The run folder was pulled from the bench before destruction; the lab host's and the lab Mac's hash lists of the 26
  pulled files are equal, and the lab sealed them (29 files with the job's own records). The maintainer's
  `lab-verify` re-check on 2026-11-18 passed: sealed hashes re-checked, analyzer re-run gives the same two verdict
  lines, custody record matches the bench log.
- In the maintainer's copy, `sha256sum -c evidence-v115.sha256` gives `OK` for all 15 original files.
- Bench `r198373b` was destroyed at 2026-11-18T13:11:37Z–13:11:39Z (rc 0); the bench list before shows it running and
  the list after no longer shows it (lab custody record, not published).
- No gateway credential is in the published files: `home/` was never pulled, and a search of every published file for
  the kit's credential pattern (`lab-` plus 24 hex characters) finds nothing.
