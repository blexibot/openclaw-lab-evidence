# Evidence packet: openclaw/openclaw#182520 (managed local model service has no cross-process ownership)

Status: **built, not yet reviewed by the human publisher. Not posted anywhere.** Nothing in this packet authorizes a
public action. Issue state when this packet was built (read-only check, 2026-11-16): open, labels include `stale`, `P2`.

## Result in one paragraph

On OpenClaw **2026.11.4 (d843d6a)**, Linux x64, two `openclaw infer model run --local` CLI processes sharing one
managed `localService` (a small stand-in HTTP model server, not `llama-server`): the first CLI (the *owner*) started
the server through OpenClaw's own `provider-local-service` code; the second CLI (the *borrower*) reused the healthy
endpoint without starting or owning it; when the owner's request finished and its CLI shut down cleanly, the owner's
`host-shutdown` cleanup sent **SIGTERM** to the server while the borrower's request (accepted 34.9 s earlier) was still
open (no end or close logged; the stand-in streams one chunk per second by design, chunks are not logged). The
borrower failed with `terminated`, exit code 1, and did not retry. Controls: the same managed config
with one CLI succeeds, and the same two CLIs against a server that no OpenClaw process owns both succeed. Outcome:
**reproduced** for that narrow lifetime primitive (one run per case). It is **not** the reported Gateway incident: no
Gateway ran, the server was a stand-in, and only the graceful SIGTERM path was exercised (not the `exit`-handler
SIGKILL path). A separate attempt with the real managed `llama-server` and two CLI `memory index` processes never
reached overlap: OpenClaw refused the second command with an exclusive offline state-ownership error before it touched
the server (**blocked** as a surrogate; the kit printed `inconclusive`).

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#182520 |
| Run ID | lab ticket `20261116-1235-14-lab-182520-llamacpp-provider` (job `T182520`, long job `J182520`, throwaway bench `b182520`) |
| UTC observation time | Part A 2026-11-16T13:38:20Z to 13:42:18Z (try 1). Part B try 1 13:42:18Z (blocked at onboarding). Part B try 2 13:48:13Z to 13:53:13Z. Bench created 13:08:07Z, destroyed 13:59:01Z (`custody/bench-log.tsv`). |
| Test outcome, Part A `overlap` (stand-in server, CLI owner + CLI borrower, graceful CLI shutdown) | **reproduced** |
| Test outcome, Part A controls (`solo`, `external`) | both pass (rc 0, full reply), as designed |
| Test outcome, Part B try 2 (real managed `llama-server`, two CLI `memory index` runs, one state root) | **blocked**: the trigger was unreachable by this surrogate (second CLI refused admission before acquisition). The kit's own label is `RESULT_B=inconclusive (attempt 2: reused=yes overlap=no)`. |
| Test outcome, Part B try 1 | **blocked**: embedding-only onboarding failed, `libgomp.so.1: cannot open shared object file` |
| Attribution | None. No fix candidate was tested. The issue's reported version (2026.10.6) was not run. |
| Attempts / failures | Part A: one run per case. `overlap`: 1 run, borrower failed (rc 1), owner rc 0. `solo`: 1 run, rc 0. `external`: 1 run, both CLIs rc 0. Part B try 2: calibration (borrower alone) 1 run rc 0; overlap attempts 2, in both the borrower exited rc 1 within 4-5 s with the admission error, owner rc 0, no overlap. Part B try 1: 1 run, blocked at onboarding. No harness crash; every run wrote its terminal receipt (`run.exit` = 0). |

### Narrow assertion (Part A `overlap`)

In one run on 2026.11.4 with a managed `localService` whose `command` is a stand-in server:

1. The owner CLI's stderr shows OpenClaw starting the service (`starting stub local service`, `ready: pid=951`); the
   kit did not start it (port refused connections before the owner started).
2. The borrower CLI's stderr has no `[provider-local-service]` line, and its request (`id=2`) arrived at the same
   server pid 951 (`servers_started=1`). In v2026.11.4 source, a healthy probe returns from
   `startAndWaitForLocalService()` without spawning or registering ownership (**source-supported**).
3. After the owner's own request ended (13:40:38.859Z), the owner CLI logged
   `stopping local model service: reason=host-shutdown`, and the server logged `STUB got SIGTERM` at 13:40:38.873Z.
   The borrower's request has no `REQ end` and no `REQ client-closed` line.
4. The borrower printed `Model request failed provider=stub model=slow message=terminated` and exited rc 1
   (`.rc` end stamp 13:40:38Z, whole seconds). One borrower request, no retry onto a new server.

Wording to use: the borrower **borrowed/reused the healthy endpoint**; it did not adopt child-management ownership.

### Known limits

- **Stand-in server.** Part A's model server is `kit/slowllm.mjs`, which exits immediately on SIGTERM. Whether a real
  `llama-server` finishes an in-flight request after SIGTERM is **unknown**. In v2026.11.4 source, `stopLocalServiceProcess()`
  waits up to 2 s after SIGTERM and then sends SIGKILL (**source-supported**, not measured here).
- **Only the graceful CLI shutdown path** (`closeCliResources()` → `host-shutdown` → SIGTERM) was observed. The
  `process.once("exit")` handler's `forceStopManagedService()` SIGKILL path (owner crash or hard exit) was not tested.
- **No Gateway.** Owner and borrower were both short-lived CLIs sharing one `OPENCLAW_HOME` and config within each
  case (each case had its own fresh `OPENCLAW_HOME`). The reported
  incident has the Gateway as the borrower (or owner); that was not exercised.
- **Counts, not rates.** One run per case. One deterministic witness; no reliability or frequency claim.
- **Timing figures** (34.9 s in flight, 14 ms SIGTERM after the owner's request end) come from one run's log stamps.
- **Process roles.** `A_overlap_PIDS owner_cli=882 borrower_cli=969` are the kit's background-subshell pids (`$!`),
  not the `openclaw` node processes. The server's parent chain `,951,901,885,884,882,...` contains 882; the identities
  of 884/885/901 (`timeout` wrapper, `openclaw` launcher/node) are **inferred** from the kit, not recorded.
- **Topology.** One Incus system container on one Linux host; the container shares the host kernel. No macOS or
  Windows client.
- **Part B ran on a modified bench.** Between try 1 and try 2 the worker installed the OS package `libgomp1` inside
  the bench (worker-reported version `14.2.0-4ubuntu2~24.04.1`; no install log was captured). The ticket allowed one
  retry only for a download/network failure, so this retry was outside the ticket. Part A ran before that change and
  is unaffected.

### Reported preconditions not matched

From the issue text (2026-10-24): Linux x64 (Arch-based), Node 24.22.1, OpenClaw 2026.10.6 (fe06181), npm global,
`@openclaw/llama-cpp-provider` official channel, managed CPU llama.cpp b10809, embeddings
`hf:ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/embeddinggemma-300m-qat-Q8_0.gguf`, `memory.search.provider: "local"`,
`fallback: "none"`, embedding-only setup; steps: Gateway idle-stops its server, a CLI `memory index` spawns one, a
Gateway memory sync adopts it, the CLI exits and kills it.

| Precondition | This run |
|---|---|
| OpenClaw 2026.10.6 | **not matched**: 2026.11.4 (d843d6a) |
| Arch-based Linux, Node 24.22.1 | **not matched**: Ubuntu 24.04.5 container, Node v24.22.3 |
| Gateway as the borrower (memory sync) | **not matched** in either part: no Gateway ran |
| CLI `memory index` as the owner | Part B only (owner `memory index` did start the real `llama-server`); Part A owner is `infer model run --local` |
| Real managed `llama-server` b10809, EmbeddingGemma Q8_0, provider `local`, fallback `none`, embedding-only | Part B matched these (build `b10809-5266f24da`); Part A used a stand-in |
| CLI exit kills the server under an in-flight request | Part A only, graceful SIGTERM path, stand-in server |
| "SIGKILLs that process group" on exit | **not matched**: observed SIGTERM via the graceful path; SIGKILL fallback not reached |

## Inputs

### OpenClaw under test

| Item | Value | Evidence kind |
|---|---|---|
| Install method | `npm install -g openclaw@2026.11.4 --no-fund --no-audit` as root inside the container, by the lab's `bench openclaw b182520 2026.11.4` helper (lab helper revision sha256 `bf11b9affcaeb9d40ae341517115e1118731a9965f742d819285f28218a05498`; helper not included) | observed (helper source read 2026-11-16) |
| Banner | `OpenClaw 2026.11.4 (d843d6a)` (`runs/try1/versions.txt`, `runs/try2/versions.txt`) | observed |
| Source commit for the tag | `v2026.11.4` → `d843d6af39a42cd3c30084edbeabeece732fd93a` (GitHub API, read-only, 2026-11-16); matches the banner's short hash | observed |
| Registry integrity, `openclaw@2026.11.4` | `sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==` (shasum `71eeeac4e4b95a0d2bb6c80fb1e0463ac7ec79b9`), from `npm view` on 2026-11-16 | observed (registry); **unknown** whether the bench's installed tarball had this integrity (not recorded; bench destroyed) |
| Plugin (Part B) | `@openclaw/llama-cpp-provider@2026.11.4`, installed by `openclaw plugins install` (`runs/B/b1-plugin-install.txt`); registry integrity `sha512-5LFf2Xlu/gG+zPpZbWIfLdpG2Vro9kL5cQfMYy78jeEvVQodi3E12adpAyZWpzGf0O4HEh0J6P9mTVQTMVFu4A==` (shasum `8883e1092319a6d6f3e5e69076d3cfd07e6ac8d5`) | observed (registry); installed integrity **unknown** |
| Resolved executable | `openclaw` on PATH from the global npm prefix `/usr/local` (`/usr/local/lib/node_modules/openclaw`, seen in `runs/B/b1-plugin-install.txt` and `b4-status-owner.txt`) | observed |
| Running Gateway revision | **not applicable**: no Gateway was started in this run | observed |
| Node / npm | Node `v24.22.3` (official tarball, SHA-checked by the helper); npm `11.19.1` (worker-reported, not in a captured artifact) | observed / **unknown** for npm |

### Kit

- Kit tarball sha256 `c75be79f012f0e528d3c34fde607917a61167f5e84976f6f1801ea5cafda0afd` (9 files). The in-bench sha256 of
  all 9 files is printed at the top of each `runs/try*/versions.txt` and `run.log`.
- `kit/` holds the 9 files. Eight are byte-identical to the run's copies. `kit/job.sh` is a **redacted copy**: one
  comment word (the lab account name) became `<user>`, so its hash here (`50a0ed13…`) differs from the run's
  (`18abc743…`); the code is unchanged.
- Files: `run.sh` (entry point inside the bench), `partA.sh` (Part A), `partB.sh` (Part B), `slowllm.mjs` (stand-in
  OpenAI-compatible server that logs every request start/end/close and signal with its pid), `cfg.mjs` (writes the
  Part A config, dumps Part B config with secrets redacted), `procs.mjs` (`/proc` process snapshot with parent chain),
  `hc.mjs` (health probe), `corpus.mjs` (synthetic Markdown notes from a made-up vocabulary), `job.sh` (host wrapper).

**Exact invocation.**

```
# on the lab Linux host (try 1, Part A then Part B):
bash ~/worker/jobs/T182520/kit/job.sh AB
#   -> bench exec b182520 -- bash /root/kit/run.sh AB      (as root inside the container)
# try 2 (Part B only, after the worker's libgomp1 install and moving B -> B-try1):
bash ~/worker/jobs/T182520/kit/job.sh B
# each CLI in Part A (partA.sh start_cli):
timeout 300 openclaw infer model run --local --model stub/slow --prompt "Lab check. DELAY=<40|90> TAG=<owner|borrower>" --json
# each indexer in Part B (partB.sh run_index):
OPENCLAW_DEBUG_MEMORY_EMBEDDINGS=1 timeout 1500 openclaw memory index --agent <owner|borrower> --force --verbose
# Part B setup:
openclaw plugins install @openclaw/llama-cpp-provider@2026.11.4
openclaw config set memory.search.provider local ; ... memory.search.fallback none ; ... memory.search.cache.enabled false
openclaw onboard --non-interactive --accept-risk --skip-health --auth-choice llama-cpp --llama-cpp-embedding-only
openclaw agents add <owner|borrower> --workspace /root/t182520/B/ws-<role> --non-interactive
```

Part A ordering (`overlap`): owner CLI starts → kit polls `/v1/models` until 200 → 2 s → borrower CLI starts →
`/proc` snapshots at owner-ready, borrower+10 s, owner-exited+1 s, borrower-exited. Part B ordering per attempt:
owner `memory index` starts → kit waits for `/health` → 2 s → borrower `memory index` starts → 1 s process monitor.

### Configuration (synthetic; no secrets)

Part A, written by `kit/cfg.mjs stub` (managed cases `solo` and `overlap`; `external` omits `localService` and the kit
starts the server itself):

```json
{
  "models": { "mode": "merge", "providers": { "stub": {
    "baseUrl": "http://127.0.0.1:18555/v1", "apiKey": "stub-local", "api": "openai-completions", "timeoutSeconds": 300,
    "models": [{ "id": "slow", "name": "Slow stub", "reasoning": false, "input": ["text"],
                 "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }, "contextWindow": 32768, "maxTokens": 1024 }],
    "localService": { "command": "/usr/local/bin/node",
                      "args": ["/root/kit/slowllm.mjs", "18555", "/root/t182520/out/A/<case>-stub.log"],
                      "healthUrl": "http://127.0.0.1:18555/v1/models", "readyTimeoutMs": 60000, "idleStopMs": 0 } } } },
  "agents": { "defaults": { "model": { "primary": "stub/slow" }, "workspace": "/root/t182520/A-<case>/ws" } }
}
```

(`apiKey` is the literal placeholder `stub-local`; the stand-in ignores it.)

Part B, after onboarding: `runs/B/b3-config.json` (dumped by `cfg.mjs dump` with its key-name redactor; it had nothing
to redact).

### Resolved paths

| Part | Path | Source |
|---|---|---|
| A | `OPENCLAW_HOME=/root/t182520/A-<solo|overlap|external>`; config `/root/t182520/A-<case>/.openclaw/openclaw.json`; workspace `/root/t182520/A-<case>/ws` | `runs/A/A.log` (`CFG wrote …`) |
| A | session/state files created by `infer model run --local`: **unknown** (not listed) | — |
| B | `OPENCLAW_HOME=/root/t182520/B`; config `/root/t182520/B/.openclaw/openclaw.json`; state root `/root/t182520/B/.openclaw` (named in the admission error) | `runs/B/ov1-borrower.txt`, `b4-agent-*.txt` |
| B | agent DB `/root/t182520/B/.openclaw/agents/owner/agent/openclaw-agent.sqlite`; workspaces `/root/t182520/B/ws-owner`, `/root/t182520/B/ws-borrower` | `runs/B/b4-status-owner.txt` |
| B | `llama-server` `/root/t182520/B/.openclaw/tools/llama.cpp/b10809/linux-x64/llama-server`; model file `/root/t182520/B/.openclaw/models/llama.cpp/hf_ggml-org_embeddinggemma-300m-qat-Q8_0.gguf` | `runs/B/b3-config.json`, `b4-status-owner.txt` |

### Host, guest, runtime

| Item | Value | Evidence kind |
|---|---|---|
| Guest | Incus **system container** (not a VM) from image `images:ubuntu/24.04`, `security.nesting=true`; `Ubuntu 24.04.5 LTS`; glibc 2.39; commands run as **root** inside the container | observed (`versions.txt`, `B_HOST`, helper source) |
| Kernel | `7.0.0-43-generic x86_64` (shared with the host; `uname -r` on the host matches) | observed |
| Host | Ubuntu 26.04.1 LTS, x86_64, Incus 6.0.5; 20 CPUs and ~32 GB visible to the container (`nproc=20`, `mem_kb=32020200`) | observed |
| Egress | NAT; HTTPS 200 to huggingface.co, github.com, registry.npmjs.org (`B_EGRESS`) | observed |
| GPU | **unknown** whether any GPU was visible (not recorded); the managed build path is `b10809/linux-x64` | unknown |

### Backend, model, route, context

| Item | Part A | Part B |
|---|---|---|
| Backend | `kit/slowllm.mjs` on Node v24.22.3, OpenAI-compatible, `127.0.0.1:18555` | managed llama.cpp, `buildInfo` `b10809-5266f24da` (`b4-status-owner.txt`): router `llama-server` on `127.0.0.1:43837` (`--models-preset … --models-max 2 --metrics --no-ui`) plus an embedding child on `127.0.0.1:45297` |
| Model | `slow` (stand-in; replies `STUB_DONE_<n>` after n seconds, one `.` chunk per second when streaming) | `embeddinggemma-300m-qat-q8_0` (`hf:ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/embeddinggemma-300m-qat-Q8_0.gguf`), Q8_0 QAT, ~0.3 GB download, 768-dim vectors |
| Model digest | not applicable | **unknown** (file hash not recorded) |
| Route | `provider stub` → `api: openai-completions` → `POST /v1/chat/completions`, `stream: true` | `memory.search.provider local`, `fallback none`, cache disabled → router → embedding child |
| Context | configured `contextWindow: 32768`; effective not applicable (stand-in ignores it) | effective child `--ctx-size 2048` (process args in `ov*-monitor.txt`); configured: none set in config |
| Proxy / filter | **none**. All model traffic stayed on loopback inside the container. No packet capture. Capture positions: the stand-in server's own event log (server side), each CLI's stdout/stderr/exit code, and `/proc` snapshots by `procs.mjs`. | same: CLI output with `OPENCLAW_DEBUG_MEMORY_EMBEDDINGS=1`, 1 s `/proc` monitor, `memory status --deep` |

### Source references (v2026.11.4, `d843d6a`, read through the GitHub API, read-only)

- `src/agents/provider-local-service.ts`: `startAndWaitForLocalService()` returns when `probeHealth()` succeeds
  (lines 346-349), otherwise logs `starting ${provider} local service` (367) and spawns with
  `detached: shouldDetachChildForProcessTree()` (376); `stopManagedProviderLocalServices()` stops every service this
  process registered with reason `host-shutdown` (249-251; log line 512); `installExitHandler()` runs
  `forceStopManagedService()` on `process.once("exit")` (568-577).
- `src/agents/provider-local-service-process.ts`: `stopLocalServiceProcess()` sends SIGTERM, waits up to
  `DEFAULT_PROBE_TIMEOUT_MS = 2_000`, then SIGKILL (85-103).
- `src/cli/runtime-cleanup.ts` line 132: finalizer `"provider-local-services": stopActiveManagedProviderLocalServices`.

## Outputs

| Path | What it is |
|---|---|
| `runs/try1/run.log`, `runs/try1/versions.txt` | Try 1 (Part A + Part B) full job log and version/kit-hash header |
| `runs/try2/run.log`, `runs/try2/versions.txt`, `run.started`, `run.ended`, `run.exit` | Try 2 (Part B only); terminal receipt `run.exit` = `0` |
| `runs/A/A.log` | Part A full log: case headers, `/proc` snapshots, health probes, stub logs, summary lines, `RESULT_A` |
| `runs/A/<case>-<role>.out/.err/.rc/.start` | Each CLI's stdout (JSON), stderr, exit code + end epoch, start epoch |
| `runs/A/<case>-stub.log` | Stand-in server event log per case (pid, ppid, pgid, request start/end/close, signals) |
| `runs/B/summary.txt` | Part B summary lines, `RESULT_B` |
| `runs/B/b1-*.txt`, `b2-*.txt`, `b3-config.json`, `b4-*.txt` | Plugin install, config sets, post-onboard config, agent adds, owner `memory status --deep` |
| `runs/B/b3-onboard.excerpt.txt` | Onboarding output with the 8,251 progress-bar lines and colour codes removed (the 8 remaining lines are verbatim) |
| `runs/B/cal-borrower.excerpt.txt`, `.start`, `.rc` | Calibration (borrower alone): output with the 243 `memory embeddings:` debug lines and colour codes removed |
| `runs/B/ov<k>-owner.txt`, `ov<k>-borrower.txt`, `.start`, `.rc` | The two overlap attempts: full (redacted-by-kit) outputs |
| `runs/B/ov<k>-monitor.txt` | 1 s process monitor while the borrower ran |
| `runs/B/ov<k>-status-borrower.txt` | `memory status --deep --agent borrower` after each attempt |
| `runs/B-try1/summary.txt`, `b3-onboard.excerpt.txt` | Try 1's Part B (blocked at onboarding) |
| `custody/worker-evidence.sha256` | The worker's original 75-entry manifest of the unredacted run outputs (covers originals, not this packet) |
| `custody/bench-log.tsv` | The lab helper's action log lines for `b182520` (create, install, destroy) |
| `ASSERTIONS.md` | Claim → artifact → observation → limitation |
| `MANIFEST.sha256` | sha256 of every other file in this packet |

Not included (kept privately): `b1-plugin-list.txt` (35 KB plugin table), full `b3-onboard.txt` (465 KB of progress
bars), full `cal-borrower.txt` (debug lines), the tarballs. The worker's manifest hashes for those originals are in
`custody/worker-evidence.sha256`.

## Custody

- The job wrote `out.tgz` out of the container before `run.exit` and before the bench was destroyed (13:59:01Z).
  Copies were verified on two lab hosts and on the controller: `out.tgz` sha256
  `5d0749291aa414f0d44ad765a6a40698d29b2d03200239f90089f1d156b8a9b5`; all 75 entries of the worker manifest verify
  `OK` against the private raw copy; try 1's Part A files are byte-identical to the final archive's Part A files.
- This packet is an inspected copy. Files under `runs/` are byte-identical to the originals except the two
  `*.excerpt.txt` files (filtered as described) and `kit/job.sh` (one comment word). Original hashes do not identify
  those three files.
- Redaction: no tokens, keys, passwords, house/lab hostnames or IPs, or personal content. Loopback addresses
  (`127.0.0.1`) and container-internal paths under `/root/` are kept. `apiKey: "stub-local"` in `kit/cfg.mjs` is a
  synthetic placeholder; the `token|secret|password|apikey` strings in `kit/cfg.mjs` and `kit/partB.sh` are the kit's
  own redaction patterns.
- Synthetic content only: prompts are `Lab check. DELAY=<n> TAG=<role>`; the memory corpus is generated by
  `kit/corpus.mjs` from a made-up vocabulary.
- A private lab note traced which source paths acquisition, borrowing and shutdown went through. It is not part of
  this packet; every point it supports is restated, with its artifact and source lines, in `ASSERTIONS.md` and
  "Source references" above.

## Publication notes

- Recheck the issue's state and any linked PR just before posting.
- Post on the issue (general reproduction). No PR exists to validate.
- Part B's admission refusal is a boundary of the surrogate, not a finding about #182520. It does not say whether a
  CLI and a Gateway can overlap on the same managed service, which is the reported route.
- Disclosure line only after the human publisher's review has actually happened.
