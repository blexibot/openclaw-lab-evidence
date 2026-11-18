# Evidence packet: openclaw/openclaw#188657 (Responses route drops the previous turn's runtime-context carrier)

Status: **published; reviewed by Harold before posting.** The comment that links here was posted at
https://github.com/openclaw/openclaw/issues/188657#issuecomment-6925567235 on 2026-11-16 (UTC).

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#188657 |
| Run ID | lab ticket `20261116-0530-07-lab-188657-responses-carrier` (job `LM188657`, throwaway bench `b188657`) |
| UTC observation time | release runs 2026-11-16T06:30:02Z to 06:38Z; source build 06:32:55Z to 06:47:51Z; source-build runs 06:50:56Z to 06:52:27Z |
| Test outcome (2026.11.3, 2026.11.4, `openai-responses`) | **reproduced** |
| Test outcome (source commit `bf0b8002c2b9741ecadeda9b4219e1cb633b508a`, `openai-responses`) | **candidate passes this scenario** |
| Controls (`openai-completions`, 2026.11.3 and `bf0b800`) | carrier retained, input array append-only (the kit and driver are fair on the route the release already protects) |
| Attribution | Fails on the two tested releases; passes at this source commit; consistent with #198100 (not an isolated parent-vs-fix comparison). |
| Attempts / failures | 5 recorded runs, one per cell, all completed (both turns exit 0). Both release Responses runs showed the defect; the one source-build Responses run did not. One further control invocation used the wrong binary (PATH fell back to the global npm 2026.11.4) and was discarded by the worker; it is not in this packet. No harness failures in the 5 recorded runs. |

**Narrow assertion.** In a two-turn session through the shipped CLI (`openclaw agent`, one session key, a real
`read` tool call in turn 1) against a custom `openai-responses` endpoint, the request bodies received by the endpoint
show: on 2026.11.3 and 2026.11.4, the first request of turn 2 no longer has the runtime-context carrier item that sat
at `input[2]` in the last request of turn 1, so turn 1's last `input` array is not a prefix of turn 2's first
`input` array (first difference at item 2). Turn 2's first request carries one carrier, at the end (`input[6]` of 7),
after turn 2's user message. At source commit `bf0b800`, the same scenario keeps turn 1's carrier at `input[2]`
(byte-identical serialized item) and appends turn 2's own carrier at `input[7]` of 8; the earlier array is a prefix of
the later one.

**What this is not.** It is a serialization result at the endpoint. It is not a measured prefix-cache or KV-cache
effect: no model or inference backend ran, and the mock returns constant usage counters (`cached_tokens: 0`).

### Known limits

- One run per cell. Counts, not rates.
- Release vs source commit is a confounded comparison: besides #198100, `bf0b800` differs in the system prompt
  (44,032 vs 49,232 serialized chars at `input[0]`), carrier content (298 vs 955 chars), the user-message envelope,
  the tool list and the loaded plugin set (14 vs 18 plugins). No matched parent-vs-#198100 build was run.
- Source-build version string is not bumped: `node openclaw.mjs --version` prints `OpenClaw 2026.11.3 (bf0b800)`.
  Code identity comes from the build log's `HEAD` line and the run header `oc='node /root/src/openclaw/openclaw.mjs'`.
- Same gateway process for both turns. No cold process reopen or gateway restart between turns was tested.
- Only full-input mode: every request had `store: false` and no `previous_response_id`. A route that uses
  `previous_response_id` was not tested.
- Only the custom-provider `openai-responses` and `openai-completions` routes were exercised. The `ollama` route,
  bundled-provider routes (e.g. xAI) and plugin/helper/SDK paths were not exercised.
- HTTP request headers were not captured (bodies only).
- No beta was run. The ticket's premise that `2026.11.5-beta.4` lacks #198100 was not re-verified.
- Internal trace vs wire: on 2026.11.3 the cache trace's `stream:context` record orders the turn-1 carrier after the
  tool result, while the wire request puts it before the `function_call`. Claims here rest on the wire captures; the
  trace flags are a separate, internal boundary.

### Reported preconditions not matched

- The issue concerns prefix-cache loss on real backends (vLLM, SGLang, llama.cpp, proxies). No real backend or cache
  counter was used, so cache loss itself is **not** shown; only the non-append-only request input is.
- Linux only, in one Incus system container. No macOS or Windows client.

## Inputs

### OpenClaw under test

| Run | Executable (as invoked) | Banner (`--version`) | Package / source identity |
|---|---|---|---|
| rel113-resp, rel113-comp | `openclaw` on PATH | `OpenClaw 2026.11.3 (847611d)` | npm `openclaw@2026.11.3`; registry `dist.integrity` `sha512-FBq/q0TCaoA2b7qfdV0q81fHhI6RBB1zAQfJQREc1u2TlK5khVgCUsAlXskLWthyVqRz5PWEj+oOmfYgK58dHg==` (`dist.shasum` `d7db24ae086448184e328ff69a39cbea3e43d4b6`) |
| rel114-resp | `openclaw` on PATH | `OpenClaw 2026.11.4 (d843d6a)` | npm `openclaw@2026.11.4`; registry `dist.integrity` `sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==` (`dist.shasum` `71eeeac4e4b95a0d2bb6c80fb1e0463ac7ec79b9`) |
| main-resp, main-comp-src | `node /root/src/openclaw/openclaw.mjs` | `OpenClaw 2026.11.3 (bf0b800)` | source commit `bf0b8002c2b9741ecadeda9b4219e1cb633b508a` (`fix(agents): keep every session prefix append-only on every route (#198100)`), built with `kit/build-main.sh` |

- Registry integrity values were read on 2026-11-16 with `npm view openclaw@<v> dist.integrity dist.shasum` (read-only).
  The integrity of the tarball actually installed in the bench was **not recorded** (unknown); npm checks registry
  integrity on install by default (documented npm behaviour, not observed here).
- Install method for releases: the lab's `bench openclaw <bench> <version>` helper installs the official Node tarball
  (SHA-checked) and runs `npm install -g openclaw@<version> --no-fund --no-audit` as root inside the container.
  2026.11.4 was installed over 2026.11.3 with `npm install -g openclaw@2026.11.4 --no-fund --no-audit`.
- Resolved release executable: `/usr/local/lib/node_modules/openclaw` (observed in the source-build gateway's warning
  `PATH CLI 2026.11.4 at /usr/local/lib/node_modules/openclaw differs from this Gateway 2026.11.3 at /root/src/openclaw`;
  for the release runs themselves this path is inferred from the same install).
- Running Gateway revision: each run starts `<executable> gateway run --port 18789` with the same executable as the
  CLI. Source-build gateway: `this Gateway 2026.11.3 at /root/src/openclaw` and CLI clients `version=2026.11.3
  build=legacy` (`runs/main-resp/gateway-log-excerpt.txt`). 2026.11.3 gateway: `update available (latest): v2026.11.4
  (current v2026.11.3)`. 2026.11.4 gateway: no revision line in its log; revision inferred from the CLI banner of the
  same executable.
- Source build: `pnpm 12.15.0` (corepack), Node v24.22.3, `pnpm install --frozen-lockfile` then
  `NODE_OPTIONS=--max-old-space-size=8192 pnpm build`; exit 0; build stamps 06:32:55Z / 06:41:00Z / 06:42:26Z /
  06:47:51Z. The build log shows `src/agents/transcript-policy.ts` lines `31:  appendOnlyRuntimeContext: true,` and
  `172:    policy.appendOnlyRuntimeContext ||= context.inHistorySystemUpdates;` (`build/build-main.excerpt.txt`).

### Kit

- Run kit: `kit.tgz` sha256 `02935315cfc790c558742ac79be949d525ff766cedc479f29aa9e13ba32d5b7c`, carried in the ticket
  as base64 and hash-checked on both lab hosts and in the bench.
- Files as run (sha256): `analyze.mjs` `1f3b58bb0d6e…cc8e`, `build-main.sh` `00d460dca21f…2c95`, `drive.sh`
  `3bc86c364abd…e0f8`, `mock.mjs` `987045f21041…7eb4` (full hashes in the run ticket; `analyze.mjs`, `build-main.sh`
  and `mock.mjs` in `kit/` are byte-identical to the run copies).
- **Published `kit/drive.sh` differs from the run copy in one way only:** the synthetic loopback gateway token string
  is replaced by `<TOKEN>` (two places). The script still runs as published; any string works there. Its own hash is
  in `MANIFEST.sha256`.
- Packet tools (written after the run, read-only over the captures): `tools/compare-pair.mjs` (top-level field
  equality, carrier hashes and raw-byte prefix for the decisive pair) and `tools/trace-extract.py` (carrier flags from
  the cache trace).

Exact invocations (inside the bench, as root, from the ticket and the run headers):

```
bash /root/kit/drive.sh rel113-resp openai-responses
bash /root/kit/drive.sh rel113-comp openai-completions
npm install -g openclaw@2026.11.4 --no-fund --no-audit
bash /root/kit/drive.sh rel114-resp openai-responses
bash /root/kit/build-main.sh            # default ref bf0b8002c2b9741ecadeda9b4219e1cb633b508a
bash /root/kit/drive.sh main-resp openai-responses node /root/src/openclaw/openclaw.mjs
bash /root/kit/drive.sh main-comp-src openai-completions node /root/src/openclaw/openclaw.mjs
```

Each `drive.sh` run: fresh `OPENCLAW_HOME`, mock on `127.0.0.1:8099`, gateway on loopback `18789`, then two turns
with `openclaw agent --session-key s188657 --json`:
turn 1 `READFILE: please read fixture.txt with your read tool and tell me what it says.`, turn 2
`Second turn: just reply ok.`, then `analyze.mjs` over the captures.

Replay on another machine: install the version under test, put the four kit files in one directory and run the same
`drive.sh` lines (Node >= 22, bash, curl, setsid, coreutils `timeout`). Captures land in `/root/r188657/cap-<run>/`
unless `BASE` is set.

### Fixture and configuration

- Synthetic fixture: `fixture.txt` containing `lab fixture line one.` in the run workspace. Model replies are scripted
  by `mock.mjs` (tool call → `The fixture says: lab fixture line one.` → `ok`). No personal content.
- Config written by `drive.sh` (redacted copies: `runs/<run>/openclaw.redacted.json`): custom provider `myproxy`,
  `api` = `openai-responses` or `openai-completions`, `baseUrl` `http://127.0.0.1:8099/v1`, placeholder `apiKey`
  `dummy`, model `test-model` with `contextWindow: 65536`, `maxTokens: 4096`; gateway `mode: local`,
  `bind: loopback`, token auth (`<TOKEN>`); `diagnostics.cacheTrace.enabled: true`. The installed config differs per
  run only in `api` and `workspace`.
- `config get models.providers.myproxy.api` returned the intended api on every run (`== config check:` line).

### Resolved paths (per run, inside the bench)

| What | Path |
|---|---|
| `OPENCLAW_HOME` | `/root/r188657/home-<run>` (driver refuses to reuse one) |
| Config | `/root/r188657/home-<run>/.openclaw/openclaw.json` (file present there in the run archive) |
| Session | key `s188657` → `agent:main:s188657`; agent DB `/root/r188657/home-<run>/.openclaw/agents/main/agent/openclaw-agent.sqlite` |
| Cache trace | `/root/r188657/home-<run>/.openclaw/logs/cache-trace.jsonl` |
| Gateway file log | releases: `/tmp/openclaw/openclaw-2026-11-16.log` (**outside** `OPENCLAW_HOME`, shared by the release runs); source build: `/root/r188657/home-<run>/.openclaw/logs/openclaw-2026-11-16.log` |
| Workspace | `/root/r188657/ws-<run>` |
| Captures | `/root/r188657/cap-<run>/req-NNN.json`, `index.jsonl`, `analysis.txt` |

### Environment

| Field | Value |
|---|---|
| Host | Ubuntu 26.04.1 LTS, Linux 7.0.0-43-generic, x86_64; Incus 6.0.5 (read 2026-11-16 after the run) |
| Guest | Incus **system container** from `images:ubuntu/24.04` (exact point release: unknown), `security.nesting=true`; shares the host kernel (system prompt reports `os=Linux 7.0.0-43-generic (x64)`). Container privilege mode: not set by the helper, so Incus default (unprivileged) — inferred. |
| Resources in guest | 30 GB RAM, 20 vCPU (build log `free -g`, `nproc`) |
| Runtime | Node v24.22.3 (official tarball, SHA-checked by the helper) |
| User / privileges | root inside the container |
| Network | Model traffic loopback-only to the mock. The source build cloned `https://github.com/openclaw/openclaw.git` and downloaded dependencies. Other outbound traffic from OpenClaw (e.g. the gateway's `remote model catalog applied` line) was not captured. |

### Backend

| Field | Value |
|---|---|
| Backend | `kit/mock.mjs` (scripted, no model). Not an inference server. |
| Model digest / quantization | none (no model) |
| Route | OpenClaw → `POST /v1/responses` or `POST /v1/chat/completions` on `127.0.0.1:8099`, streaming (`stream: true`) |
| Context | configured `contextWindow` 65,536; OpenClaw reported `contextTokens: 65536` (`contextTokensSource: resolved`). No backend, so no effective backend context exists to compare. |
| Cache / residency | none. The mock's usage block is constant (`input_tokens: 100`, `cached_tokens: 0`). |

### Proxy / filter and capture position

- No proxy or filter in the path (`UPSTREAM` unset). Capture position: the endpoint itself. `mock.mjs` writes each
  POST body to `req-NNN.json` exactly as received (after HTTP transfer decoding by Node), before replying.
- The mock serves only `POST /v1/responses`, `POST /v1/chat/completions`, `GET …/models` and `GET /__mark`; anything
  else is logged as `unhandled` and gets 404. Every run's `index.jsonl` contains only marks and three POSTs (no
  `unhandled`, no `/models`), so every request the endpoint received is captured.

## Outputs

Per run, in `runs/<run>/`:

| File | What it is | Kind |
|---|---|---|
| `driver-stdout.txt` | `drive.sh` stdout+stderr (header with executable and home, banner, config check, both turns' exit codes and reply tails, mock index, analysis, cache-trace counts) | raw |
| `req-002.json`, `req-003.json` | last request of turn 1 and first request of turn 2, as received by the endpoint | raw |
| `index.jsonl` | mock request index with turn marks | raw |
| `analysis.txt` | `analyze.mjs` output with the `VERDICT` line | derived |
| `cache-trace-carriers.txt` | `tools/trace-extract.py` over the run's `cache-trace.jsonl` (internal trace, not wire) | derived |
| `gateway-log-excerpt.txt` | line-numbered lines from the gateway log: model, listen, log path, revision/version, client connects | raw excerpt |
| `openclaw.redacted.json` | installed config, token replaced by `<TOKEN>` | raw, redacted |

Also: `runs/pair-compare.txt` (`tools/compare-pair.mjs` over the five decisive pairs) and
`build/build-main.excerpt.txt` (line-numbered excerpt of the source build log; exit file `0`).

Exit codes: both turns exit 0 in all five runs (`driver-stdout.txt`). External timeout per turn 180 s
(`timeout -s KILL`); not reached.

### Run table

| Run | Build | Route | Items (t1 last → t2 first) | Leading identical items | Carrier positions | `carrier_retained` | `append_only_prefix` | First difference |
|---|---|---|---|---|---|---|---|---|
| rel113-resp | 2026.11.3 (847611d) | responses | 5 → 7 | 2 | [2] → [6] | no | no | item 2 |
| rel113-comp | 2026.11.3 (847611d) | chat | 5 → 8 | 5 | [2] → [2,7] | yes | yes | none |
| rel114-resp | 2026.11.4 (d843d6a) | responses | 5 → 7 | 2 | [2] → [6] | no | no | item 2 |
| main-resp | source `bf0b800` | responses | 5 → 8 | 5 | [2] → [2,7] | yes | yes | none |
| main-comp-src | source `bf0b800` | chat | 5 → 8 | 5 | [2] → [2,7] | yes | yes | none |

All five: `tool_call_in_turn1=yes`, `prev_response_id_used=no`; within turn 1 (req-001 → req-002) the input array was
append-only on every run.

## Custody

- Raw evidence was copied off the bench to both lab hosts before the bench was destroyed; `evidence.sha256` of that
  copy is `8ce316e4b0e23d563f39ebeb92c8f6c7f4b726f56db9356d8571bf06e12a8703`, and all 8 listed files verified on the
  maintainer's private copy (2026-11-16). That private copy (full build log, run archive with homes, worker notes)
  stays private.
- Files here are inspected, synthetic copies. Only `drive.sh` and the five `openclaw.redacted.json` files were
  altered (token placeholder). `MANIFEST.sha256` hashes the bytes in this packet; it does not identify the private
  originals.
