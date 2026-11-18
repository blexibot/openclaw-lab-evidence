# Evidence packet: openclaw/openclaw#198373 on the native Ollama `/api/chat` route (2026.11.3, 2026.11.4)

Status: **published; reviewed by Harold before posting.** The comment that links here was posted at
https://github.com/openclaw/openclaw/issues/198373#issuecomment-6925571504 on 2026-11-16 (UTC). Corrected
after first publication: `ASSERTIONS.md` row 5 (tool-call IDs) and the withheld original hashes (see "Test kit" and
"Custody"). Lab evidence, built 2026-11-16 from the run's pulled raw files. Every file listed in `MANIFEST.sha256` is
in this folder; the manifest covers only these redacted/synthetic copies (see "Custody").

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#198373 (a replayed tool result gains `"__openclaw": {"runId": …}`, breaking append-only history) |
| Lab run ID | `T198373` (ticket `20261116-0700-10-lab-198373-runid-replay`), tags `v113` and `v114` |
| Observation time (UTC) | v113: 2026-11-16T08:42:21Z – 08:43:53Z. v114: 2026-11-16T08:50:22Z – 08:51:56Z |
| Route | OpenClaw `api: "ollama"` provider → native Ollama `POST /api/chat`. **Not** the `openai-completions` route the reporters used |
| Attempts / failures | One two-run pair per version (2 attempts total, 0 harness failures). Run 1 produced a tool result on the first try in both tags; no retry was needed |

### Narrow assertions and outcomes

| # | Assertion | 2026.11.3 | 2026.11.4 | Evidence kind |
|---|---|---|---|---|
| A1 | In OpenClaw's own `diagnostics.cacheTrace`, the replayed `toolResult` in run 2 carries `"__openclaw": {"runId": "<run 1's runId>"}`, which it did not carry in run 1 | reproduced | reproduced | observed |
| A2 | The gateway's prompt-cache watchdog reports `message 3 (toolResult) differs … changed fields: envelope.__openclaw` on run 2 | reproduced | reproduced | observed |
| A3 | The captured `/api/chat` request bodies carry `__openclaw`/`runId` on the replayed tool message | not reproduced under these conditions | not reproduced under these conditions | observed |
| A4 | Run 2's first request is byte-append-only over run 1's last request (identical prefix through the end of run 1's messages array) | observed: yes | observed: yes | observed |

Plain statement: on this native Ollama route, **we observed no `__openclaw`/`runId` field on the captured tool message,
despite the internal trace stamp and the watchdog warning.** This sample does not show what other transports
serialize, does not show the issue's ID-normalization symptom (the underscore-bearing tool-call IDs `call_` + 8 were
replayed unchanged; `ASSERTIONS.md` row 5), does not exercise its system-prompt symptom, and does not establish
native-route cache stability in general.

Supporting counters (backend fields as returned through the relay; `uncached` is derived as
`prompt_eval_count − prompt_eval_cached_count`):

| Version | Run 1 last request (seq) | Run 2 first request (seq) | Run 2 `prompt_eval_count` | Run 2 `prompt_eval_cached_count` | Derived uncached |
|---|---|---|---|---|---|
| 2026.11.3 | seq=8 | seq=9 | 15467 | 15298 | 169 |
| 2026.11.4 | seq=8 | seq=9 | 15494 | 15325 | 169 |

OpenClaw's own `cache:result` trace record for run 2 reports the same values (`promptTokens` 15467/15494, `input` 169,
`cacheRead` 15298/15325, `broke: false`) — adapter-derived, not independent.

### Limits

- **Unmatched precondition: route.** Both outside reproductions used `openai-completions`. The lab model filter only
  admits native `/api/chat`; the OpenAI-compatible route was not tested. This packet says nothing about it.
- **Topology.** One OpenClaw client in an Incus **container** (shares the Linux host kernel) talking through an
  in-container logging proxy and a lab relay/filter to **one remote Ollama on an Apple Silicon host** (`<LAB-MODEL>`).
  Not native inference on Linux.
- **One run per version.** Counts only; no rate is implied.
- **One tool shape.** A single text `read` tool result. The native serializer's behavior for other content (images,
  multi-part results) was not exercised.
- **Counters are supporting evidence only.** The model is shared; the relay's own log (`lab-stats-*-window.json`) shows
  no other request between seq=8 and seq=9 in either tag, but whether every client of that model goes through this
  relay is **unknown**. Cache counters cover this one pair, not native-route cache behavior generally.
- **Cause not investigated.** Why the native request omits the field (serializer construction vs. stripping) was not
  examined in source by this run. Any statement about it is outside this packet.
- **2026.11.5-beta.4 not run** (optional step skipped by the worker). No current-main or candidate build was tested.
- **Install conditions.** 2026.11.4 was installed with `npm install -g` over 2026.11.3 in the same container (fresh
  `OPENCLAW_HOME` per tag). npm reported that install scripts were not run for `openclaw@2026.11.4` (its
  `postinstall: node scripts/postinstall-bundled-plugins.mjs` included) because of the allow-scripts policy
  (`raw/install/J198373b.log`). For 2026.11.3 the npm output was discarded by the bench tool, so whether its scripts ran
  is **unknown**. Effect on this result: **unknown** (not investigated).
- **Harness gaps (do not affect the decisive files).**
  - `run198373.sh` writes `evidence-<tag>.sha256` *before* appending the final `DONE` line to `steps.log`, so the
    in-bench manifest never matches the final `steps.log` (both tags). This is a kit ordering bug.
  - The kit's `pkill -f "openclaw gateway run"` did not stop the v113 gateway: its log continues until a SIGTERM at
    08:49:23Z, about 5.5 minutes after `DONE`; the sender of that SIGTERM is not recorded. That is why
    `gw-v113.log` also differs from its in-bench manifest. The v114 gateway log has no shutdown lines (the bench was
    destroyed afterwards). The wire logs, cache traces, analyses and run outputs all match their in-bench manifests.
  - The gateway file log went to `/tmp/openclaw/openclaw-2026-11-16.log`, outside the per-tag `OPENCLAW_HOME`; it was
    not collected (the stdout copy `gw-<tag>.log` was).

## Inputs

### OpenClaw package

| | 2026.11.3 | 2026.11.4 |
|---|---|---|
| Banner (`openclaw --version`, in `steps.log`) | `OpenClaw 2026.11.3 (847611d)` | `OpenClaw 2026.11.4 (d843d6a)` |
| Registry `dist.integrity` (`npm view`, read on 2026-11-16, `raw/install/npm-view.txt`) | `sha512-FBq/q0TCaoA2b7qfdV0q81fHhI6RBB1zAQfJQREc1u2TlK5khVgCUsAlXskLWthyVqRz5PWEj+oOmfYgK58dHg==` | `sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==` |
| Integrity of the tarball actually installed in the bench | unknown (not captured before the bench was destroyed) | unknown |
| Install method | `bench openclaw` (`raw/install/bench-tool.sh`): official Node tarball, SHA-checked, then `npm install -g openclaw@2026.11.3 --no-fund --no-audit` | `npm install -g openclaw@2026.11.4 --no-fund --no-audit` over 2026.11.3 (`raw/install/J198373b.sh`, log `J198373b.log`) |
| Running Gateway revision | Gateway started from the same install by `openclaw gateway run`; its log reports `current v2026.11.3` in the update notice. A separate gateway commit banner was not logged | same; no version line in the gateway log beyond the shared CLI banner |
| Resolved `openclaw` executable path | unknown (not recorded; `/usr/local/bin/openclaw` is inferred from the Node tarball being unpacked into `/usr/local`) | unknown (same inference) |

### Test kit

- Original kit archive `kit-198373.tgz`, sha256 `<WITHHELD-ORIGINAL-HASH>` (verified by the worker on extraction,
  `evidence.txt`). Files as run whose published copies are byte-identical (original sha256 = published sha256):
  `analyze198373.py` `4211606159b031cdb009b0b79f2c4af3949d1e8098c5935b4d19ac1573ccc593`, `openclaw.json`
  `f56e3c84bcf9c40d0bb37735e9e6a3691ffda85af512a6c0dfbe885b1c40d6ff`.
- `logproxy.py` and `run198373.sh` in `kit/` have the relay address replaced with `<RELAY>`. The original hashes of
  these two files and of the kit archive are **withheld** (`<WITHHELD-ORIGINAL-HASH>`): they would let anyone confirm
  guesses at the redacted address. They are kept in the lab's private store.
- Exact invocation (inside the bench, as root):
  `cd /root/r198373 && (setsid nohup bash kit-198373/run198373.sh <tag> > <tag>.console 2>&1 < /dev/null &)`
  with `<tag>` = `v113`, then `v114` after the 2026.11.4 install.
- What the script runs: run 1 `openclaw agent --agent main --session-key cache-repro -m 'Use the read tool to read
  note.txt in your workspace, then reply with its first word only.' --timeout 1400 --json`; run 2 in the same session
  `-m 'Reply with one word: ready.'`. Fixture: `/root/r198373/ws/note.txt` = `lab-198373 synthetic note`.
- Replay check: `python3 -I tools/verify198373.py raw/v113 raw/v114` re-derives A1, A3, A4 and the counters from
  the files in this packet.

### Configuration (redacted)

`kit/openclaw.json` as published; at run time the script substitutes a random throwaway gateway credential for the
`REPLACE_ME` placeholder (never collected). Relevant settings: provider `ollama`, `api: "ollama"`,
`baseUrl http://127.0.0.1:11434` (the in-bench logging proxy), model `qwen3.8:27b-q4_K_M`, configured
`contextWindow 262144`, provider `timeoutSeconds 1200`, no `keep_alive`, `diagnostics.cacheTrace.enabled true`.
Both read back by `openclaw config get` before the run (`steps.log`: `config baseUrl read back`, `cacheTrace read back:
true`). No hand edits to the kit or config during the run (worker report; consistent with `steps.log`, which shows no
retry or failure branch).

### Resolved paths

| What | Path | Evidence |
|---|---|---|
| `OPENCLAW_HOME` | `/root/r198373/<tag>/home` | set by `run198373.sh` |
| Config file | `/root/r198373/<tag>/home/.openclaw/openclaw.json` | written by the script; read-back succeeded on the first path (no "retry with" line in `steps.log`) — inferred to be the file read |
| Workspace | `/root/r198373/ws` | `workspaceDir` in `cache-trace.jsonl`, `run1.json` |
| Session key | `agent:main:cache-repro` | gateway log, trace |
| Cache trace file | found by `find "$OPENCLAW_HOME" -name 'cache-trace*.jsonl'`; exact sub-path unknown | `run198373.sh` |
| State / session store directories | unknown (not logged) | — |
| Gateway file log | `/tmp/openclaw/openclaw-2026-11-16.log` (outside `OPENCLAW_HOME`) | `gw-v114.log` line 98 |

### Host, guest, runtime

| | Value | Kind |
|---|---|---|
| Guest | Incus container from `images:ubuntu/24.04` (requested image; exact guest build not recorded), running as root | documented (ticket, `J198373a.sh`) |
| Guest runtime | Node 24.22.3, linux x64, V8 13.6.233.17-node.63, OpenSSL 3.5.9, SQLite 3.54.1 | observed (`gw-<tag>.log` "native runtime" line) |
| npm version | unknown (bundled with Node 24.22.3; not recorded) | unknown |
| Host | Ubuntu 26.04.1 LTS, kernel 7.0.0-43-generic, x86_64, Incus 6.0.5 | observed read-only on 2026-11-16 ~09:30Z, after the run; the kernel at run time was not recorded |
| Isolation | container (`bench new` without `--vm`): shares the host kernel | documented (`bench-tool.sh`) |

### Backend

| | Value | Kind |
|---|---|---|
| Server version | `{"version":"0.40.16"}` from `GET /api/version` through the proxy and relay | observed (relay-reported; assumed to be the Ollama server's own answer) |
| Model | `qwen3.8:27b-q4_K_M`, digest `25b843619e944cd0ae6069f94ff4e5e26a16e109ccbc0a66a0f05979ed70098e`, `Q4_K_M`, family `qwen35`, 27.3B, GGUF | observed (`/api/tags` response, `raw/<tag>/wire-<tag>-meta.jsonl`) |
| Host | one remote Apple Silicon machine (`<LAB-MODEL>`), shared, one request at a time | documented |
| `num_ctx` sent by OpenClaw | none (`options` = `{"num_predict": 32768}` only) on all six `/api/chat` requests | observed |
| `keep_alive` sent | none | observed |
| Configured context | 262144 (`openclaw.json`; `run1.json` `contextTokens 262144`, source `resolved`) | observed (client side) |
| Effective server context | **unknown.** `/api/tags` reports model `context_length 262144`, which is the model's metadata, not the loaded runtime context; `/api/ps` was not captured. The lab's server setting of 262K is documented, not verified by this run. Requests used ~15.5K prompt-eval counts, so this run does not validate a 262K window | unknown |
| Cache/residency settings | unknown (server side not captured) | unknown |

### Proxy, filter and capture position

- **Capture point:** `kit/logproxy.py` (published sha256 in `MANIFEST.sha256`; original
  `<WITHHELD-ORIGINAL-HASH>`), listening on `127.0.0.1:11434` **inside the bench**, between OpenClaw and the lab relay. It records
  each request body exactly as OpenClaw sent it (plus its sha256 at capture time) and the response bytes as returned by
  the relay. It re-sends bodies upstream with `Content-Length` (no chunking); bodies are not altered.
- **Downstream of the capture:** the lab relay/filter at `<RELAY>:11435`, then Ollama. Filter revision: **unknown**
  (not recorded in this run). Routes: native `/api/chat`, `/api/tags`, `/api/show`, `/api/version` allowed; `/v1/…`
  refused (documented in the ticket; not exercised here). No request in either tag was refused (all statuses 200).
- Whether the relay modifies response bodies (including the counter fields) is **unknown**.

## Outputs in this packet

| Path | What | Redaction |
|---|---|---|
| `raw/<tag>/steps.log` | run timeline, version banner, exit codes of both turns (`turn exit=0`) | none |
| `raw/<tag>/wire-<tag>-chat.jsonl` | the three captured `/api/chat` records (seq 7, 8, 9), verbatim lines | none; each `req` still hashes to its captured `req_sha256` |
| `raw/<tag>/wire-<tag>-meta.jsonl` | captured `/api/version` and `/api/tags` records | `/api/tags` `modified_at` redacted, so that response is re-serialized |
| (not included) | the capture's `/api/show` records (seq 3, 4 and 6; model metadata, about 28 KB each) and the second `/api/tags` record (seq 5) | omitted: not used by any claim; kept in the private lab store |
| `raw/<tag>/cache-trace.jsonl` | OpenClaw `diagnostics.cacheTrace` output, verbatim | none |
| `raw/<tag>/analysis-wire-<tag>.txt`, `pair-<tag>.txt`, `analysis-trace-<tag>.txt` | analyzer output (`kit/analyze198373.py`) | none |
| `raw/<tag>/gw-<tag>.log`, `gw-promptcache-<tag>.txt` | gateway stdout log and its prompt-cache lines | none |
| `raw/<tag>/run1.json`, `run2.json` | `openclaw agent --json` output of each turn (run IDs, payload text) | none |
| `raw/<tag>/lab-stats-<tag>-window.json` | relay request log, filtered to this tag's run window | other lab clients' records outside the window removed |
| `raw/<tag>/proxy.log` | proxy start line | relay address → `<RELAY>` |
| `raw/<tag>/evidence-<tag>.sha256` | the in-bench manifest of the original files (for the record; see "Harness gaps") | none |
| `raw/install/` | install wrappers and logs, bench tool (`bench-tool.sh`, original sha256 `<WITHHELD-ORIGINAL-HASH>`), `npm view` output | `bench-tool.sh`: one internal network-fence name in a comment replaced; otherwise none |
| `tools/verify198373.py` | replay check over this packet | — |

Exit codes: both turns `exit=0` in both tags (`steps.log`); `openclaw agent` status `ok` (`run1.json`, `run2.json`);
install jobs exit `0` (`raw/install/J198373a.exit`, `J198373b.exit`). External timeout: `timeout 1500` per turn, not
reached.

## Custody

Raw files were pulled out of the container as whole files before it was destroyed (worker, `v113.tgz`/`v114.tgz`,
sha256 `12a11e38…` / `84ae9c67…`), then copied unmodified to the maintainer's private lab store. The in-bench
manifests verify `OK` for every file except `steps.log` (both tags) and `gw-v113.log` (see "Harness gaps"). The
throwaway gateway credential lived only in the excluded `home/` folder and does not appear in any pulled file. This
packet holds inspected copies; where a file was redacted, the original hash does not identify the published bytes.
Original hashes of redacted files are withheld from this packet (the kit archive, `logproxy.py`, `run198373.sh` and
`bench-tool.sh`): each would let a guess at a redacted address or name be confirmed. They are kept privately.
`MANIFEST.sha256` hashes exactly the files in this folder.
