# Evidence packet: openclaw/openclaw#198178 on released 2026.11.4 and 2026.11.5 against a real SGLang server

Status: lab evidence, built 2026-11-18 from the run's pulled raw files; the 2026.11.5 run (`T198178v5`) was added the
same day. This folder is published only after the
maintainer's review; the comment on the issue that links here is the record of that review. Every file listed in
`MANIFEST.sha256` is in this folder; the manifest covers only these redacted/synthetic copies (see "Custody").

**Two releases, same experiment.** The sections "Summary" through "Custody" below describe the 2026.11.4 run
(`T198178r2`, raw files under `raw/t1/`, `raw/relay/`, `raw/analysis/`, `raw/install/`, `raw/server/`). The 2026.11.5
run (`T198178v5`, raw files under `raw/v115/`) has its own section at the end, "2026.11.5 run (T198178v5)", which
lists what differs. Its kit targets 2026.11.5, gives c3 its own baseline, and has a stricter retry rule (no retry was
needed).
On 2026.11.5 all three setup reruns again replaced the row `maxTokens` 8192 with 32768 and the next request asked for
32768; that run's scores come from the run's own analyzer, with no re-score.

**Scoring disclosure.** The outcomes for c1, c2 and c3 below come from a **post-run re-score** made outside the
worker, not from the run's own analyzer. The analyzer shipped with the kit (`kit/an198178.py`, `3dc29a39…`) already
had the rule "the retry, when the kit made one, is the attempt that counts" (`find_infer`), but it looked for a step
named `<label>-retry`, while this run's kit named its retry `<label>-retry1`. So it scored c1 on the first inference
attempt, which the lab's own request proxy refused with a 429 (`lab-request-in-flight`, a busy single-request slot;
not the model server), instead of the retry, which got a 200. That made c1 `baseline=fail` and pulled c2 and c3 down
to `inconclusive / harness failure`. Contemporaneous evidence that the baseline was good: during the run, before any
re-score, the run script's own gate logged `C1OK=yes statuses=[200:-:8192:-]` at 16:03:35Z (`raw/t1/steps.log`
line 31). After the run, the retry lookup was fixed (`kit/an198178-4aaa0971.py`: take the highest-numbered
`<label>-retryN` step) and the **same raw files** were re-scored. Only the c1, c2 and c3 `VERDICT` lines change; every
other line of the output is identical (`raw/analysis/verdict-t1-3dc29a39.txt` vs `verdict-t1-4aaa0971.txt`). **c4 was
`reproduced` under both versions.** A later revision (`kit/an198178-c04d4d41.py`, with 15 regression tests kept
privately) gives the same outcomes and adds where each baseline came from (`raw/analysis/verdict-t1-c04d4d41.txt`).
The lab's job receipt for this run says `stopped`, because it was written from the first scoring.

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#198178 (vLLM and SGLang setup run again replaces the saved model output limit with 32768) |
| Lab run ID | `T198178r2` (ticket `20261117-1545-26-lab-198178-sglang-r2`), tag `t1` |
| Observation time (UTC) | 2026-11-17T16:02:07Z – 16:05:16Z (`raw/t1/steps.log`) |
| Build | OpenClaw `2026.11.4 (d843d6a)` from npm, CLI only (no Gateway was started) |
| Route | OpenClaw provider `sglang`, `api: "openai-completions"` → `POST /v1/chat/completions` → (in-bench logger → host relay → lab proxy, which rebuilds the body; see "Lab proxy") → SGLang serving `deepseek-v4.1-flash` |
| Attempts / failures | One attempt per cell (c1–c4). One inference (c1) got the lab proxy's 429 on its first try and a 200 on the kit's one retry; no other refusals. 7 chat POSTs forwarded in total, 6 answered 200. An earlier run of the same ticket (r1, 2026-11-17T14:48Z) stopped at the c1 baseline on two lab-proxy 429s; no setup rerun was reached and it has no product result; it is not in this packet. r2 changed only `run198178.sh` and `relay198178.py` (the retry handling) |
| Unmatched preconditions | The reporter used a source build of main `ee854a1d757` and a local stand-in server; this run used the released 2026.11.4 and a real SGLang server. 2026.11.4 is on a release line that diverged from main on 2026-10-15 (GitHub compare `ee854a1d757...d843d6a`: diverged). 2026.11.5 was published to npm at 2026-11-17T09:59Z, about six hours before this run, and was not run here; it was run the next day (see "2026.11.5 run (T198178v5)"). The reporter's HTTP 400 needs a server whose context is smaller than prompt + 32768; ours is 1048576, and our relay forwarded at most 256 output tokens, so **no server rejection could occur and none is claimed**. vLLM was not run |

### Narrow assertions and outcomes

| Cell | Setup path (what ran) | Outcome | Evidence kind |
|---|---|---|---|
| c1 | Hand-written config with row `maxTokens: 8192`, row `contextWindow: 200000`, provider `maxTokens: 4096`, `timeoutSeconds: 1234`, two sentinels; one `openclaw infer model run --local --agent main` | `baseline=ok`: the 200 request carried `max_completion_tokens: 8192` (re-scored; see disclosure) | observed |
| c2 | `openclaw onboard --non-interactive … --auth-choice sglang` on c1's config (same profile): **exit 1**, "Replacement credential saved but inactive", no model request; then the printed `openclaw models auth activate sglang:setup-<uuid> --agent main` (exit 0; its probe asked for 256); one inference | `reproduced`, `scope=config+request`: row `maxTokens` 8192 → 32768; next request `max_completion_tokens: 32768`, 200 (re-scored) | observed |
| c3 | `openclaw models auth login --provider sglang --agent main`, interactive, driven by a script through a pseudo-terminal, on a byte-identical copy of c1's base config in its own profile (exit 0; no activation printed; no model request during login); one inference | `reproduced`, `scope=config+request`: row 8192 → 32768; next request 32768, 200 (re-scored; baseline borrowed from c1) | observed (config change; next request 32768) / inferred (that this profile would have sent 8192 before login: c1's baseline, identical base config) |
| c4 | Fresh `onboard`, then the same pins with `openclaw config set` (6/6 exit 0), one inference (sent 8192, 200), then the **same** `onboard` again: **exit 0, written directly, no staging, no model request**; one inference | `reproduced`, `scope=config+request`: row 8192 → 32768; next request 32768, 200 (same under both analyzer versions) | observed |

Side observations, reported separately from the outcome (all observed, config snapshots and analyzer `CTXWIN` /
`PROVFIELDS` / `SENTINEL` lines):

| | c2 | c3 | c4 |
|---|---|---|---|
| Row `contextWindow` | 200000 → 128000 | 200000 → 128000 | 200000 → 128000 |
| Provider `maxTokens` / `timeoutSeconds` | kept (4096 / 1234) | kept | **removed** (4096 → absent, 1234 → absent) |
| Provider `apiKey` (`"SGLANG_API_KEY"`, the env-var name) | removed; auth profile `sglang:setup-<uuid>` added and bound as `agents.entries.main.model` | kept | kept |
| Row gains `reasoning`, `input`, `cost` | yes | no | already present (from the first onboard) |
| Sentinels (`diagnostics.cacheTrace.enabled`, `agents.defaults.workspace`), primary, `baseUrl` | kept | kept | kept |

Plain statement: **on 2026.11.4, against a real SGLang server, every one of the three setup reruns we ran replaced the
saved row `maxTokens: 8192` with 32768 and the row `contextWindow: 200000` with 128000, and the next
`openclaw infer model run` asked for `max_completion_tokens: 32768`.** Whether the provider-level `maxTokens` /
`timeoutSeconds` survived depended on the path. The SGLang server never received 32768 (see Limits).

### Differences from the report (observed; no cause claimed)

- **No setup-time request carried 32768.** In the report, the setup probe asked for 32768 and a 16384-token server
  refused it, so the re-run could not be activated. Here, `onboard` and `models auth login` sent no model request at
  all (`statuses=[]` on `ONBOARD c2`, `LOGIN c3`, `ONBOARD c4-1` and `ONBOARD c4-2` in `steps.log`). The only
  setup-time request was c2's activation probe, which asked for `max_completion_tokens: 256` (wire seq 4;
  `ACTIVATE c2 rc=0 statuses=[200:-:256:-]`). The first request carrying 32768 was the next inference. The report's
  "setup probe is refused" symptom was therefore not exercised.
- **The staged non-interactive path kept the provider-level fields.** The report shows `provider maxTokens=undefined`
  after its non-interactive runs. Here c2 (staged, then activated) kept provider `maxTokens` 4096 and
  `timeoutSeconds` 1234; they were removed only on c4, the config that `onboard` had created (`PROVFIELDS` lines).
- **The login prompt did not offer the saved base URL.** The reporter kept the saved base URL. Here the base URL
  prompt came pre-filled with SGLang's default `http://127.0.0.1:30000/v1` (`raw/t1/pc/c3-transcript.txt`), so the
  saved URL had to be retyped (see Limits).

## Limits

- **The server never saw OpenClaw's cap.** The kit's host relay clamps the forwarded output cap to 256
  (`raw/relay/relay.jsonl`, `orig_caps` vs `fwd_caps` on every POST). The measured value is the cap OpenClaw put on
  the wire, captured before the relay (`raw/t1/wire.jsonl`) and again by the relay with an identical body hash.
  Nothing here says what SGLang would do with 32768. With a 1048576-token server context, a rejection would not be
  expected anyway (inferred).
- **Effective server context** is observed, but not at run time: `context_length 1048576` was read from SGLang's
  `GET /get_server_info` on 2026-11-18 at 05:42:22Z (`raw/server/sglang-server-info-extract.json`). Whether SGLang was
  restarted between the run (2026-11-17T16:05Z) and the read (2026-11-18T05:42Z) is unknown. The lab proxy in front
  of it did not restart (same process since 2026-11-15T13:30:43Z), which says nothing about SGLang. OpenClaw's own
  configured row `contextWindow` was 200000 before setup and 128000 after.
- **One attempt per cell.** Counts only; no rate is implied.
- **c3 has no baseline of its own (2026.11.4 run only; the 2026.11.5 run gave c3 its own).** It uses c1's 8192 request: c1 ran in profile `pa`, c3 in profile `pc`, from
  byte-identical base configs (same raw sha256 `87e5aa8d…` in `steps.log`, `SNAP … n=1 label=base`).
- **c3 was driven by a script, not a person** (`kit/pty198178.py`, a 50×400 pseudo-terminal: it answers base URL,
  key and model, in that order). The base URL prompt came pre-filled with SGLang's default
  `http://127.0.0.1:30000/v1`, not the saved `http://127.0.0.1:18178/v1`; the driver erased it (120 backspaces) and
  typed the saved URL. The model prompt showed `Qwen/Qwen3-8B` as hint text (no cursor after it), and the driver typed
  the saved model over it without erasing (`raw/t1/pc/c3-transcript.txt`; `kit/pty198178.py`). So the reporter's
  "keeping the saved base URL" was matched by retyping it, not by accepting a pre-filled value. What Enter alone does
  at the model prompt is unknown.
- **Paths differ from the source read and from each other.** c2 staged a replacement credential (onboard exit 1) and
  the overwrite came from `models auth activate`. c4's second onboard, on a config that onboard itself had created
  (with auth profile `sglang:default`), wrote directly with exit 0. Why one staged and the other did not was not
  investigated.
- **No Gateway.** All commands ran as local CLI processes (`--skip-daemon`, `infer model run --local`). `models auth
  activate` and `models auth login` each printed that the local Gateway could not be refreshed. Gateway behaviour is
  not covered.
- **Topology.** One Incus **container** (shares the host's Linux kernel) running OpenClaw as root, with fresh isolated
  `HOME`, `OPENCLAW_HOME`, `OPENCLAW_STATE_DIR` and `OPENCLAW_CONFIG_PATH` per profile. The model is a shared lab
  model on a remote GPU cluster, reached through a lab request proxy; it is not a private SGLang instance.
- **Not run in this run:** 2026.11.5 (published to npm 2026-11-17T09:59Z, before the run; run on 2026-11-18, see
  "2026.11.5 run (T198178v5)"); vLLM; the reporter's
  main `ee854a1d757`; current main; closed PR #198179 (not run, built or fetched). Source-supported only (read, not
  run): at tag `v2026.11.5` (`e13cf15e`), `src/plugins/provider-self-hosted-setup.ts` lines 86–90 still build the row
  `maxTokens` from the context-window default when no `maxTokens` is passed in; whether the setup paths pass the saved
  value there was not traced.

## Inputs

### OpenClaw package

| | Value | Kind |
|---|---|---|
| Banner | `OpenClaw 2026.11.4 (d843d6a)` (`steps.log` line 2) | observed |
| Installed package | `/usr/local/bin/openclaw -> /usr/local/lib/node_modules/openclaw/openclaw.mjs`, `npm root -g` `/usr/local/lib/node_modules`, `package.json` `openclaw 2026.11.4` (`steps.log` `INSTALL`) | observed |
| Registry `dist.integrity` (pinned in the ticket) | `sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==`; `dist.shasum` `71eeeac4e4b95a0d2bb6c80fb1e0463ac7ec79b9`; both match the registry as read on 2026-11-18 (`raw/install/npm-view.txt`) | documented / observed (registry read after the run) |
| Integrity of the tarball actually installed | unknown (`INSTALL … resolved=- integrity=-`: not available from the installed tree) | unknown |
| File-level check | nine `dist/` files involved in setup (`provider-setup-E2rsiVoE.mjs`, `setup-inference-turn-DQMCJqMA.mjs`, `auth-choice-DVV6ffVF.mjs`, `defaults-Bg930vxE.mjs`, `setup-inference-credentials-mmWiSKQg.mjs`, `setup-model-selection-Dgw4DOAO.mjs`, `merge-patch-2v7qN-ym.mjs`, `model-K8moo_f0.mjs`, `extensions/sglang/index.js`) hashed in the bench and compared with the same files in the registry tarball: all `match=yes` (`steps.log` `INTEGRITY` lines) | observed |
| Install method | `bench new ubuntu/24.04 r198178 && bench openclaw r198178 2026.11.4` (`raw/install/J198178a.sh`; exit 0, `J198178a.exit`; log `J198178a.log` holds only the bench name and the banner). The lab's `bench` tool (`raw/install/bench-tool.sh`, the repository copy; the deployed copy at run time was not checked) installs an official Node tarball, SHA-checked, then `npm install -g openclaw@<version> --no-fund --no-audit` with npm's output discarded | observed / documented |
| Node.js version in the bench | v24.22.3 per the bench tool's default (`BENCH_NODE_VERSION`) | documented (not observed in this run) |
| npm install scripts | whether they ran is unknown: the bench tool discards npm's output | unknown |
| Running Gateway | none | observed (no gateway step; `PROCS … n=0` after every setup step) |

### Test kit

- Files as run whose published copies are byte-identical (original sha256 = published sha256):
  `an198178.py` `3dc29a39e2012059ec36ffb076c4334e44695048a2d3e82609274493b47b37bf`,
  `cfg-base.json` `87e5aa8db42914983682b7cf5c7220fcd7516655cd5e1213d4656b986b0b1e51`,
  `pty198178.py` `c0df7d1767d156160315fea413405db325784326a63ab819e753df63bea2048d`.
- `hostrelay198178.sh`, `relay198178.py`, `run198178.sh` and `shim198178.py` were redacted (list under "Custody").
  The original hashes of these four files, of the kit archive and of the watcher `check198178.sh` (not included) are
  **withheld**: they would let anyone confirm guesses at the redacted addresses and names. They are kept in the lab's
  private store.
- Re-score analyzers (added after the run, not part of the kit): `an198178-4aaa0971.py`
  (`4aaa09713ee97e99c25fa4b9d0458df3fc243cdbf559519bc9bebd73c8fa3adf`; the only change from `an198178.py` is
  `find_infer`) and `an198178-c04d4d41.py` (`c04d4d416c777ba4e2663b8fb0a4f242d57ccb7d97ac6c169bed49546ab73c8b`).
- Exact invocation as run (inside the bench, as root):
  `cd /root/r198178 && (setsid nohup bash kit-198178/run198178.sh t1 <BRIDGE-IP>:18178 1794952800 > t1.console 2>&1 < /dev/null &)`.
  Host relay (on the bench host, not in the bench): `bash hostrelay198178.sh start r198178 1794952800`.
- Commands the script runs (per profile, `kit/run198178.sh`):
  - c1/c4 inference: `openclaw infer model run --local --agent main --prompt "Reply with the single word OK." --json`
    (on a lab-proxy 429 `lab-request-in-flight` it waits for `Retry-After` plus jitter and retries as `<label>-retryN`).
  - c2/c4 setup: `openclaw onboard --non-interactive --accept-risk --mode local --auth-choice sglang
    --custom-base-url http://127.0.0.1:18178/v1 --custom-model-id deepseek-v4.1-flash --skip-channels --skip-daemon
    --skip-health --skip-hooks --skip-search --skip-skills --skip-ui --skip-bootstrap --json`, key from
    `SGLANG_API_KEY=lab-dummy-198178` (a dummy; the relay replaces it). If the output prints
    `openclaw models auth activate <id>` and `<id>` is a whole id in `models auth list`, it runs exactly that.
  - c3 setup: `openclaw models auth login --provider sglang --agent main` through `kit/pty198178.py`.
  - c4 pins: `openclaw config set` for the four model values and two sentinels (`steps.log` `CONFIGSET` lines).
- Replay checks (analysis):
  - `python3 -I kit/an198178-4aaa0971.py verdict raw/t1 raw/relay/relay.jsonl` reproduces
    `raw/analysis/verdict-t1-4aaa0971.txt` byte for byte; `kit/an198178.py` reproduces `verdict-t1-3dc29a39.txt`
    byte for byte (both checked on these redacted copies).
  - `python3 -I tools/verify198178.py` re-derives the body hashes, the cap per request at both capture points, the
    config fields per snapshot, and the lab proxy cross-check, from the files in this packet.

### Configuration (redacted)

`kit/cfg-base.json` is the hand-written base config for c1 and c3 (c4 builds the same values with `config set`).
Config snapshots `raw/t1/<profile>/cfg-NN-<label>.json` were written by the kit's redactor (the throwaway gateway
token in c4's config appears as `<redacted len=48>`); the raw sha256 of each unredacted snapshot is in `steps.log`
(`SNAP` lines). The provider `apiKey` value in the config is the string `SGLANG_API_KEY` (the env-var name OpenClaw
resolves), not a key.

### Resolved paths

| What | Path | Evidence |
|---|---|---|
| Profile homes | `/root/r198178/t1/{pa,pc,pb}/home` (`HOME` = `OPENCLAW_HOME`; `OPENCLAW_STATE_DIR` = `<home>/.openclaw`) | `steps.log` `PROFILE`; `kit/run198178.sh` `prof()` |
| Active config file | `/root/r198178/t1/pa/home/.openclaw/openclaw.json` (`openclaw config file` = expected) | `steps.log` `CONFIGFILE`, `pa/c1-configfile.out` |
| Auth store | `$OPENCLAW_HOME/.openclaw/state/openclaw.sqlite` | `pa/auth-*.txt` (`models auth list`) |
| Workspace sentinel | `/root/r198178/ws` | `cfg-base.json`, snapshots |

### Host, guest, runtime

| | Value | Kind |
|---|---|---|
| Guest | Incus container from `images:ubuntu/24.04` (exact guest build not recorded), OpenClaw run as root | documented (`J198178a.sh`) |
| Isolation | container: shares the host kernel | documented (`bench-tool.sh`) |
| Host | the lab's Linux bench host (`<LAB-LINUX-HOST>`), Ubuntu 26.04.1 LTS, x86_64, Incus 6.0.5 as read on 2026-11-16; kernel at run time not recorded | documented (not re-read for this run) |
| Python in the bench (kit's logger, driver, analyzer) | 3.12 (`/usr/lib/python3.12` in `raw/t1/shim.log`) | observed |

### Backend

| | Value | Kind |
|---|---|---|
| Server | SGLang, reported `version` `0.0.0.dev0` (a development build; the exact release is unknown), `served_model_name` `deepseek-v4.1-flash`, `tp_size 4`, `max_running_requests 16` | observed (`raw/server/sglang-server-info-extract.json`, read after the run) |
| Effective context | `context_length 1048576`, `max_req_input_len 1048570`, `max_total_num_tokens 5531904` | observed after the run (see Limits) |
| Configured context in OpenClaw | row `contextWindow` 200000 before setup, 128000 after | observed |
| Model digest / quantization | unknown (not exposed through the proxy; not recorded) | unknown |
| Output actually allowed | at most 256 tokens per request (relay clamp); every response finished with `"finish_reason":"stop"` after 2 completion tokens (`OK`) | observed |

### Relay, proxy and capture position

- **Capture point 1:** `kit/shim198178.py` on `127.0.0.1:18178` **inside the bench** (OpenClaw's `baseUrl`). It logs
  every request body exactly as OpenClaw sent it, with its sha256 at capture time, and the response; never header
  values (`auth_present` only). It forwards bodies unchanged to the host relay. → `raw/t1/wire.jsonl`.
- **Capture point 2:** `kit/relay198178.py` on the bench bridge (`<BRIDGE-IP>:18178`), outside the bench. It accepts
  only the bench's address, only `GET /v1/models` and `POST /v1/chat/completions`, at most 16 forwarded POSTs and
  16 KB bodies; it injects the lab proxy credential (never in the bench) and clamps the forwarded output cap to 256,
  logging `orig_caps` and `fwd_caps`. → `raw/relay/relay.jsonl`. Every bench POST matched a relay record with an
  identical body hash (`XCHECK_SUMMARY bench_posts=7 relay_posts=7 relay_forwarded=7 matched=7 relay_refusals=[]`).
- **Lab proxy (documented, not observed).** Between the relay and SGLang sits the lab's request proxy
  (`<LAB-PROXY>`). Its revision at run time is unknown (the deployed copy was not checked). Per its source in the
  lab's repository, it: serves only `POST /v1/chat/completions` and `GET /v1/models`; answers `GET /v1/models` itself
  with a static one-model list (so `raw/t1/preflight-models.json` is the proxy's own answer, not SGLang's model list);
  identifies callers by their token (each token maps to a caller name, which is what its log records); rebuilds every
  request body from an allowlist of fields; forces the model name and a scheduling priority; and turns the cap into
  `max_tokens` clamped to [1, 8192]; it admits one lab request at a time and refuses the rest with 429
  `lab-request-in-flight`. So SGLang received a rebuilt body with `max_tokens` derived from the relay's 256, not the
  relay's bytes; what the proxy sent on was not captured. The proxy's last start record before the run is at
  2026-11-15T13:30:43Z and its log has no later one (`raw/server/proxy-start-extract.json`, an extract with the time
  only).
- **Independent cross-check (observed, after the run):** the proxy's own log for the relay's window
  (16:01:52Z–16:05:11Z) has exactly seven records under the bench host's caller name: one `429
  lab-request-in-flight` at 16:02:22Z, then six `200 forwarded` whose `in`/`out` (`11/2`, `50/2`, `11/2`, `11/2`,
  `11/2`, `11/2`) equal the `usage` the relay saw in each response, one for one (`raw/server/proxy-window.jsonl`;
  `tools/verify198178.py`). At the 429, a request from the lab's worker host was in flight (logged at 16:02:30Z after
  17513 ms, so started about 16:02:12.5Z): the cause of the 429 was the shared single slot (observed).

## Replay

The analysis replays from this folder alone (see "Replay checks" above). To rerun the experiment itself:

1. A throwaway Linux container or VM where you are root, with Node, `python3`, `curl` and
   `npm install -g openclaw@2026.11.4` (the script stops with `version-not-2026.11.4` on any other version; the lab's
   install method is `raw/install/bench-tool.sh`, which defaulted to Node v24.22.3: documented, not observed).
2. Copy `kit/` to `/root/r198178/kit-198178/` (the script expects that path).
3. Serve an OpenAI-compatible SGLang endpoint with the model name `deepseek-v4.1-flash`, or change `MID` in
   `run198178.sh` and the model ids in `cfg-base.json`.
4. Run `bash /root/r198178/kit-198178/run198178.sh <new-tag> <sglang-host:port> <epoch at least 15 min ahead>`. The
   second argument is only where the in-bench logger forwards (plain HTTP), so it can be your own SGLang server with no
   relay; without the relay and lab proxy the server sees the real 8192 / 32768 caps. The third is a hard stop: the
   value used here (`1794952800`, 2026-11-17T22:00Z) has passed and would stop the script with `past-hard-stop`.
   The script also refuses to start between 07:30 and 13:00 UTC (`host-night-window`, the lab host's night jobs).
5. `python3 -I /root/r198178/kit-198178/an198178-4aaa0971.py verdict /root/r198178/<tag>` (copy the re-score analyzer
   into the kit folder first; without a relay log the cross-check lines are skipped).

`hostrelay198178.sh` and `relay198178.py` are the lab's own relay (they need the lab's `bench` tool, `tmux`, a named
bridge, and `UPSTREAM` set; with the placeholder default the relay exits with a `ValueError`). They are included to
show what sat between OpenClaw and the server, not as a replay requirement.

## Outputs in this packet

| Path | What | Redaction |
|---|---|---|
| `raw/t1/steps.log` | run timeline: version, install, integrity, every step's exit code and wire range, config snapshot hashes, `ONBOARD` / `ACTIVATE` / `LOGIN` / `INFER` / `CONFIGSET` / `PROCS` lines | none |
| `raw/t1/wire.jsonl` | bench capture of all 8 requests (1 GET, 7 POST), bodies and responses | none |
| `raw/t1/<profile>/` | per profile: config snapshots `cfg-*.json`, `models auth list` after each step `auth-*.txt`, each command's `.out` / `.err`, c3's terminal transcript `c3-transcript.txt` | config snapshots redacted by the kit (gateway token) |
| `raw/t1/analysis.txt` | the bench's own analyzer run (pinned analyzer, no relay cross-check) | none |
| `raw/t1/evidence.sha256` | in-bench manifest of the original files | the `shim.log` line's hash replaced with `<WITHHELD-ORIGINAL-HASH>` (it would confirm a guess at the redacted bridge address); 61 of 62 lines verify, 1 withheld |
| `raw/t1/shim.log`, `preflight-models.json`, `DONE` | logger start line and three harmless `ConnectionResetError` tracebacks; the lab proxy's static `GET /v1/models` answer (not SGLang's model list); the kit's done marker | `shim.log`: bridge address |
| `raw/relay/relay.jsonl`, `relay.log` | host relay records and start line | bench and bridge addresses, proxy address, host account |
| `raw/install/` | bench install wrapper, its log and exit code; the lab's bench tool (`bench-tool.sh`, repository copy); `npm-view.txt` (registry read on 2026-11-18) | `bench-tool.sh`: one internal network-fence name in a comment replaced; otherwise none |
| `raw/analysis/verdict-t1-*.txt` | outside analyzer outputs over the pulled files: as run (`3dc29a39`), re-score (`4aaa0971`), later revision (`c04d4d41`) | none needed (no addresses) |
| `raw/server/proxy-window.jsonl` | lab proxy log records in the relay window, prefill progress lines (`warm-step`) dropped | caller names → `<LAB-LINUX-HOST>` / `<LAB-MAC-HOST>`; re-serialized as compact JSON |
| `raw/server/proxy-start-extract.json` | the time of the lab proxy's last start record before the run | extract: event and time only; other fields omitted |
| `raw/server/sglang-server-info-extract.json` | selected fields of `GET /get_server_info`, read 2026-11-18T05:42:22Z | other fields omitted (kept privately) |
| `tools/verify198178.py` | replay check over this packet (`v115` argument: the 2026.11.5 run) | — |
| `raw/v115/…`, `kit/v115/…` | the 2026.11.5 run and its changed kit files; see "2026.11.5 run (T198178v5)" | see there |
| (not included) | `t1.console` (same lines as `steps.log` on the console), the kit archive, the watcher `check198178.sh` (not needed to replay), the ticket's order, the worker's report and evidence log (they carry the withheld hashes), the profile `home/` folders (never pulled: throwaway auth stores and gateway tokens) | kept privately / never collected |

Exit codes (`steps.log` `STEP … rc=`): c1-validate 0, c1-infer 1 (429), c1-infer-retry1 0, c2-onboard 1 (staged),
c2-activate 0, c2-infer 0, c3-login 0 (driver `PTY rc=0`), c3-infer 0, c4-onboard1 0, six `CONFIGSET` 0,
c4-validate 0, c4-infer1 0, c4-onboard2 0, c4-infer2 0. Per-step external timeout 300 s, never reached. Token use
(SGLang `usage`, through the relay): 105 prompt and 12 completion tokens over 6 answered POSTs.

## Custody

The worker pulled `t1` (excluding `home/`) out of the bench and the relay log off the bench host as whole files,
checked them against the in-bench manifest (62/62 `OK`) and the relay log's hash on both sides, then destroyed the
bench (destroy at 16:59:14Z, from the lab's run log; no artifact kept; the worker's report wrongly said it had not
destroyed it). The job folder was copied unmodified to a private store, the pinned analyzer was re-run there
(byte-identical to the worker's `verdict-t1.txt`), and the re-score described at the top was made from that copy.
The full `get_server_info` response, its read time and the unredacted proxy log extract are kept in the same private
store with their hashes.

Original hashes of redacted files are withheld from this packet (the four redacted kit files, the kit archive,
`relay.jsonl`, and the `shim.log` line of `raw/t1/evidence.sha256`): each would let a guess at the redacted address or
name be confirmed. They are kept privately.

Redactions in this packet (text replacement only; nothing else changed):
- `kit/hostrelay198178.sh`, `kit/relay198178.py`: lab proxy address → `<LAB-PROXY>`; bridge and bench addresses →
  `<BRIDGE-IP>` / `<BENCH-IP>`; host role names and account; four comments naming private systems or a local time
  zone reworded (the night window is given in UTC).
- `kit/run198178.sh`: bridge address → `<BRIDGE-IP>`; one comment reworded; the night-window refusal marker renamed to
  `FAILED-host-night-window` (it was not reached). The string `spark-busy` (lines 67 and 74) is a functional match on
  one of the lab proxy's refusal reasons and was left as is.
- `kit/shim198178.py`, `raw/t1/shim.log`, `raw/relay/relay.log`, `raw/relay/relay.jsonl`: bridge, bench and proxy
  addresses; host account in a log path.
- `raw/t1/evidence.sha256`: the `shim.log` hash withheld (above).
- `raw/server/proxy-start-extract.json`, `raw/server/sglang-server-info-extract.json`: extracts (above).

Both analyzers reproduce their outputs byte for byte from the redacted copies. The lab proxy credential never entered
the bench or any pulled file. `MANIFEST.sha256` hashes exactly the files in this folder.

## 2026.11.5 run (T198178v5)

Everything not listed here is as in the 2026.11.4 run above: the same experiment and cells, the same hand-written base
config (`kit/cfg-base.json`, same sha256 `87e5aa8d…`), the same pty driver (`kit/pty198178.py`, same sha256
`c0df7d17…`), the same in-bench logger and host relay (`shim198178.py`, `relay198178.py`: their original hashes equal
the 2026.11.4 originals in the lab's private order records, so the redacted copies in `kit/` apply unchanged), the
same lab proxy route, SGLang model and output clamp (256). Paths in this section are relative to `raw/v115/` unless
they start with `kit/`.

### Summary (2026.11.5)

| Field | Value |
|---|---|
| Lab run ID | `T198178v5` (ticket `20261118-1600-30-lab-198178-v5`), tag `t1`, bench `r198178b` |
| Observation time (UTC) | 2026-11-18T16:06:09Z – 16:08:14Z (`t1/steps.log` lines 1 and 80); driver 16:05:26Z – 16:08:15Z (`host/steps.log`) |
| Build | OpenClaw `2026.11.5 (e13cf15)` from npm, CLI only (no Gateway) |
| Attempts / failures | One attempt per cell, including the two new baselines. Every step `attempt=1`; no refusals: 7 chat POSTs, 7 answered 200 (`host/verdict.txt` lines 140 and 148: `TOKENS posts=7 posts_200=7 refused=0`, `XCHECK_SUMMARY bench_posts=7 relay_posts=7 relay_forwarded=7 matched=7 relay_refusals=[]`) |
| Lab verdict | `host/verdict.txt` (from `kit/v115/verdict198178.py`, the run's own analyzer; no re-score): c1 `pass`, c2 `fail` (= reproduced), c3-baseline `pass`, c3 `fail`, c4-baseline `pass`, c4 `fail`; `HINT outcome=reproduced` (lines 1–7). The maintainer's `lab-verify` check, run outside the lab on the maintainer's machine, passed (see "Custody (2026.11.5)"). Re-run here on the published copies, the analyzer gives the same file byte for byte (see "Replay (2026.11.5)") |
| Worker's report | the lab worker's own report says `reproduced` for all three paths. It is a claim, not evidence; it is not in this packet and nothing here depends on it |

### Narrow assertions and outcomes (2026.11.5)

| Cell | What ran | Outcome | Evidence (file:line) |
|---|---|---|---|
| c1 | hand-written config (profile `pa`), one inference | `baseline=ok`: `max_completion_tokens: 8192`, 200, first attempt | `t1/steps.log:23`; `t1/wire.jsonl:2`; `relay/relay.jsonl:3`; `host/verdict.txt:1` |
| c2 | `onboard --non-interactive … --auth-choice sglang` on c1's config: **exit 1**, "Replacement credential saved but inactive. Your connection is unchanged.", config unchanged; then the printed `models auth activate sglang:setup-<uuid> --agent main` (exit 0, its probe asked for 256, 200); one inference | `reproduced`, `scope=config+request`: row `maxTokens` 8192 → 32768, `contextWindow` 200000 → 128000; next request `max_completion_tokens: 32768`, 200 | onboard `t1/steps.log:26-27`, `t1/pa/c2-onboard.err:6-7`; unchanged config `t1/steps.log:29` (raw sha256 = base, line 21), `host/verdict.txt:79`; activate `t1/steps.log:30-33`, `t1/wire.jsonl:3`, `t1/pa/c2-activate.out:1-2`; rewrite `host/verdict.txt:80-99`, `t1/pa/cfg-04-after-c2-activate.json:42-43`; next request `t1/steps.log:37`, `t1/wire.jsonl:4`, `relay/relay.jsonl:5`; `host/verdict.txt:2` |
| c3-baseline (new) | the same hand-written config in its own profile `pc` (raw sha256 `87e5aa8d…`, equal to `pa`'s), one inference before login | `baseline=ok`: 8192, 200 | `t1/steps.log:40,42,44`; `t1/wire.jsonl:5`; `relay/relay.jsonl:6`; `host/verdict.txt:3` (`base_identical_to_pa=True`) |
| c3 | `models auth login --provider sglang --agent main`, interactive, driven through a pty (exit 0; no activation printed; no model request during login); one inference | `reproduced`, `scope=config+request`: row 8192 → 32768, `contextWindow` 200000 → 128000, `models.mode` → `merge`; next request 32768, 200; **baseline is its own** (`baseline_from=own:pc:c3-infer0`) | `t1/steps.log:45-49`; `t1/pc/c3-transcript.txt:41-44`; `host/verdict.txt:102-108`; `t1/pc/cfg-03-after-c3-login.json:22-23,28`; `t1/steps.log:51`; `t1/wire.jsonl:6`; `relay/relay.jsonl:7`; `host/verdict.txt:4` |
| c4-baseline | fresh `onboard`, the same pins with `config set` (6/6 exit 0), one inference | `baseline=ok`: 8192, 200 | `t1/steps.log:54-68`; `t1/wire.jsonl:7`; `relay/relay.jsonl:8`; `host/verdict.txt:5` |
| c4 | the **same** `onboard` again: exit 0, "Updated config", written directly (no staging, no model request); one inference | `reproduced`, `scope=config+request`: row 8192 → 32768, `contextWindow` 200000 → 128000; next request 32768, 200 | `t1/steps.log:70-74`; `t1/pb/c4-onboard2.out:2`, `t1/pb/c4-onboard2.err:8`; `host/verdict.txt:118-123`; `t1/steps.log:76`; `t1/wire.jsonl:8`; `relay/relay.jsonl:9`; `host/verdict.txt:6` |

Side observations (observed; analyzer `CTXWIN` / `PROVFIELDS` / `SENTINEL` lines, `host/verdict.txt:127-139`):

| | c2 | c3 | c4 |
|---|---|---|---|
| Row `contextWindow` | 200000 → 128000 | 200000 → 128000 | 200000 → 128000 |
| Provider `maxTokens` / `timeoutSeconds` | **removed** (4096 → absent, 1234 → absent; line 128) | kept (line 133) | **removed** (line 138) |
| Provider `apiKey` (`"SGLANG_API_KEY"`, the env-var name) | replaced by a 49-character value that the kit's redactor withheld (`t1/pa/cfg-04-after-c2-activate.json:27`; `host/verdict.txt:88`); auth profile `sglang:setup-<uuid>` added and bound as `agents.entries.main.model` (lines 81–84) | kept | kept |
| Row gains `reasoning`, `input`, `cost` | yes | no | already present (from the first onboard) |
| Sentinels, primary, `baseUrl` | kept (line 129) | kept (line 134) | kept (line 139) |

The kit's redactor replaces any string under a key-like name unless it is an environment-variable name or starts with
`lab-dummy` (`kit/v115/an198178.py` lines 27–39). The only key that entered the bench was the dummy
`lab-dummy-198178`. What the 49-character value holds is **unknown**; its length equals that of the staged profile
id `sglang:setup-b6ac8270-5b28-4ff2-b633-846688898d24` (an observation, nothing more).

Plain statement: **on 2026.11.5, against the same real SGLang server, every one of the three setup reruns we ran
replaced the saved row `maxTokens: 8192` with 32768 and the row `contextWindow: 200000` with 128000, and the next
`openclaw infer model run` asked for `max_completion_tokens: 32768`. Each rerun cell had its own 8192 baseline in the
same profile.** The SGLang server never received 32768 (relay clamp, as before).

### What differs from the 2026.11.4 run (observed; no cause claimed)

- **Which path kept the provider-level fields moved.** On 2026.11.4 the staged path (c2) kept provider `maxTokens`
  4096 and `timeoutSeconds` 1234 and removed provider `apiKey`; on 2026.11.5 c2 removed `maxTokens` and
  `timeoutSeconds` and kept an `apiKey` key whose value changed (above). c3 (kept) and c4 (removed) are the same on
  both releases. c2's activation changed 17 config paths on 2026.11.4 and 19 on 2026.11.5 (`host/verdict.txt:80`).
- **The login prompt offered the saved base URL.** On 2026.11.5 the base URL prompt came pre-filled with the saved
  `http://127.0.0.1:18178/v1` (`t1/pc/c3-transcript.txt:16-17`); on 2026.11.4 it showed SGLang's default
  `http://127.0.0.1:30000/v1`. The driver still erased it and retyped the saved URL (line 20). The model prompt again
  showed `Qwen/Qwen3-8B` as hint text and the driver typed the saved model over it (lines 34–39). **This is not
  isolated to the release:** on 2026.11.5 profile `pc` ran one inference (`c3-infer0`, the new baseline,
  `t1/steps.log:41-42`) before `models auth login` (line 45), while on 2026.11.4 `pc` logged in without having run
  anything (`raw/t1/pc/` has no `infer0` files). The config file was byte-identical before login both times (raw
  sha256 `87e5aa8d…`; `t1/steps.log:43`), but other state written by that inference may differ. The kit also changed
  (`umask 022`, "Test kit (2026.11.5)").
- **Differences from the report, on 2026.11.5.** Both of the 2026.11.4 run's differences from the report (see
  "Differences from the report" above) are gone on 2026.11.5: the staged non-interactive path (c2) dropped the
  provider-level `maxTokens` and `timeoutSeconds`, as the report shows (`host/verdict.txt:128`), and the login prompt
  offered the saved base URL (with the confound above). Only the setup-probe difference remains: the only setup-time
  model request was c2's activation probe at 256, so the report's refused 32768 setup probe was again not exercised.
- **Unchanged:** onboard on a hand-written config staged (exit 1) and the overwrite landed at `models auth activate`;
  onboard on an onboarded config wrote directly (exit 0); the only setup-time model request was c2's activation probe,
  `max_completion_tokens: 256` (`t1/wire.jsonl:3`); `onboard` and `models auth login` sent no model request
  (`statuses=[]` on `t1/steps.log` lines 27, 46, 55, 71); c3's 6 changed paths are the same 6 paths.
- **Harness:** no 429 this time, so no retry and no re-score. Token use: 116 prompt and 14 completion tokens over 7
  answered POSTs (`host/verdict.txt:140`).

### Limits (2026.11.5)

- **The server never saw OpenClaw's cap**: the relay forwarded `max_completion_tokens: 256` on all seven POSTs
  (`relay/relay.jsonl` `fwd_caps`, lines 3–9). No server rejection could occur and none is claimed.
- **No lab-proxy cross-check for this run**: the proxy log extract was not taken, so the 2026.11.4 run's third
  capture point (`raw/server/proxy-window.jsonl`) has no 2026.11.5 counterpart. The bench capture and the relay
  agree 7/7 with identical body hashes. The SGLang server facts in "Backend" above were read once, after the
  2026.11.4 run; they were not re-read for this run.
- **One attempt per cell.** Counts only.
- **c3 was driven by a script** that erases and retypes the saved base URL even though 2026.11.5 pre-filled it, so
  what Enter alone does at either prompt is unknown.
- **c2 and c4 still took different paths** (staged + activate vs direct write); why was not investigated.
- **No Gateway; one Incus container** (shares the host kernel), as before.
- **Not run:** vLLM; the reporter's main `ee854a1d757`; current main; any fix.

### Inputs (2026.11.5)

| | Value | Kind |
|---|---|---|
| Banner | `OpenClaw 2026.11.5 (e13cf15)` (`t1/steps.log:2`; `host/steps.log:12`; `host/identity.txt:1`; `host/host.log:2`) | observed |
| Installed package | `package=openclaw 2026.11.5`, `/usr/local/lib/node_modules/openclaw` (`t1/steps.log:3`); `resolved=- integrity=-` | observed / unknown (tarball integrity) |
| Tag | `v2026.11.5` → commit `e13cf15ece9bbd969b7362927c315362c90c97ff` (GitHub API, read 2026-11-18; recorded in the #198373 packet) | documented |
| Registry `dist.integrity` | `sha512-mqPlsGLOe8NS85BfP1vWW9YVwFXchsV75QTkEbyR4csylORxts+fmfZp9+qbD7aPbXQIctyjRk+CPL91fDvxBA==` (`npm view`, read 2026-11-18) | documented |
| File-level check | six setup-related `dist/` files (`provider-setup-B98DCyPJ.mjs`, `defaults-BWyoTPqn.mjs`, `merge-patch-B7gt1grQ.mjs`, `setup-inference-turn-x2uYo8LG.mjs`, `auth-choice-BFNQSl9s.mjs`, `extensions/sglang/index.js`) hashed in the bench and compared with the same files in the 2026.11.5 registry tarball: all `match=yes` (`t1/steps.log:4-9`) | observed |
| Bench | fresh Incus container `r198178b` (`bench created`, `host/steps.log:11`); `BENCH_ENV node=v24.22.3 npm=11.19.1 os=Ubuntu 24.04.5 LTS kernel=Linux 7.0.0-43-generic x86_64` (`host/steps.log:13`). The image name `ubuntu/24.04` comes from the lab's custody log, which is not in this packet | observed / documented (image name) |
| Host | `HOST_ENV kernel=Linux 7.0.0-43-generic x86_64`, Incus 6.0.5 client and server (`host/steps.log:14`); the deployed bench tool's hash is withheld (see Custody) | observed |
| Install method | the lab-host driver ran `bench new ubuntu/24.04 r198178b`, `bench openclaw r198178b 2026.11.5`, then checked that `openclaw --version` contains the target before running anything (`host/steps.log:11-12`). The driver script is not published: it embeds the unredacted inner kit | documented (driver not published) |
| Invocation | inside the bench, as root, in the foreground: `cd /root/r198178 && bash kit-198178v5/run198178.sh t1 <BRIDGE-IP>:18178 1795020926 > t1.console 2>&1 < /dev/null` (hard stop 2026-11-18T16:55:26Z, `host/steps.log:2`); host relay started by the driver with `MAX_POSTS=16 MAX_BODY=16384 OUT_CAP=256` (`host/steps.log:22`, `relay/relay.log`) | documented (driver) / observed (relay start line) |
| Resolved paths | profile homes `/root/r198178/t1/{pa,pc,pb}/home` (`t1/steps.log:12,39,53`); active config `/root/r198178/t1/pa/home/.openclaw/openclaw.json` = expected (`t1/steps.log:15`) | observed |
| Night-window and umask guards | `WINDOW ok … umask=0022` (`t1/steps.log:1`) | observed |
| Running Gateway | none (`PROCS … n=0` at preflight, after each of the 5 setup steps and at finish: 7 lines in `t1/steps.log`, lines 11, 28, 34, 47, 56, 72, 78) | observed |

### Test kit (2026.11.5)

In-bench `sha256sum` of the inner kit as run (`host/steps.log` lines 4–9 and 15–21):

| File as run | sha256 as run | Published copy |
|---|---|---|
| `an198178.py` (analyzer, v5 revision: uses c3's own baseline when present, counts every refusal as an attempt) | `b851ef6b893f7d6022e5493c5b31a8b6f0174440427c3ccd2206b3a50c43a864` | `kit/v115/an198178.py`, byte-identical |
| `cfg-base.json` | `87e5aa8db42914983682b7cf5c7220fcd7516655cd5e1213d4656b986b0b1e51` | `kit/cfg-base.json` (unchanged from 2026.11.4) |
| `pty198178.py` | `c0df7d1767d156160315fea413405db325784326a63ab819e753df63bea2048d` | `kit/pty198178.py` (unchanged) |
| `run198178.sh` (v5: target 2026.11.5, c3 baseline, three-attempt 429 rule, `umask 022`, 2026.11.5 `INTEGRITY` list) | withheld (redacted file) | `kit/v115/run198178.sh`, redacted |
| `relay198178.py`, `shim198178.py` | withheld (redacted files); equal to the 2026.11.4 originals per the lab's private order records | `kit/relay198178.py`, `kit/shim198178.py` (unchanged) |
| kit archive `kit.tgz` | withheld | not published |

The lab's mechanical verdict wrapper `kit/v115/verdict198178.py` (run by the lab's collector, not in the bench; it
imports `an198178.py` from its own folder) is published redacted (one host name in its docstring).
`kit/v115/run198178.sh` differs from the file as run only on two lines: a host name in a comment, and the
night-window refusal marker renamed `host-night-window` (not reached). The string `spark-busy` (lines 65 and 76) is a
functional match on one of the lab proxy's refusal reasons and was left as is.

### Replay (2026.11.5)

From the packet root, Python 3 stdlib only (checked on these redacted copies, 2026-11-18). Use `-B`:
`verdict198178.py` imports `an198178.py` from its own folder, and without `-B` Python would write a `__pycache__`
folder into the packet:

- `python3 -I -B kit/v115/verdict198178.py raw/v115` reproduces `raw/v115/host/verdict.txt` byte for byte (the
  six `VERDICT` lines, the `HINT` line and all 141 `AN` lines, including the relay cross-check).
- `python3 -I -B kit/v115/an198178.py verdict raw/v115/t1` reproduces the bench's own `raw/v115/t1/analysis.txt`
  byte for byte (no relay cross-check).
- `python3 -I -B tools/verify198178.py v115` re-derives the body hashes, the cap per request at both capture points and
  the config fields per snapshot, and checks the in-bench manifest: 63 of 64 lines `OK`, 1 withheld (`shim.log`).

To rerun the experiment itself, follow "Replay" above with `kit/v115/run198178.sh` in place of `run198178.sh`, copied
to `/root/r198178/kit-198178v5/` together with `kit/v115/an198178.py`, `kit/cfg-base.json`, `kit/pty198178.py` and
`kit/shim198178.py`. It expects `openclaw@2026.11.5` (override with `R198178_VERSION`).

### Outputs (2026.11.5)

| Path (under `raw/v115/`) | What | Redaction |
|---|---|---|
| `t1/` | the whole pulled run folder (the profile `home/` folders were never pulled): `steps.log`, `wire.jsonl` (8 requests: 1 GET, 7 POST), per-profile config snapshots, `models auth list` outputs, every command's `.out`/`.err`, c3's terminal transcript, `analysis.txt`, `preflight-models.json`, `shim.log`, `evidence.sha256`, `DONE` | config snapshots redacted by the kit (c4's throwaway gateway token `<redacted len=48>`; c2's 49-character `apiKey` value); `shim.log`: bridge address; `evidence.sha256`: the `shim.log` hash withheld |
| `relay/relay.jsonl`, `relay/relay.log` | host relay records (9: 2 GET, 7 POST) and start line | bench, bridge and proxy addresses; host account |
| `host/identity.txt`, `host/host.log` | the driver's identity lines and bench tool checks | none |
| `host/steps.log` | the driver's timeline: kit check, relay selftest, bench create/install/version, `BENCH_ENV`, `HOST_ENV`, relay start, run start/exit, pull check | addresses and host account; original hashes of the kit archive, the three redacted kit files and the deployed bench tool withheld (`<WITHHELD-ORIGINAL-HASH>`) |
| `host/verdict.txt` | the lab's verdict file for the run (from `kit/v115/verdict198178.py`) | none needed |
| `host/custody.txt` | the lab's bench-destroy record | bench addresses, host account and address, ssh key path |
| (not included) | `t1.console` (byte-identical to `t1/steps.log`), the driver's own output (`kit.out`, empty), the driver script and its embedded kit, the unpacked inner kit (`ik/`), the lab's sealing and pull hash lists, the worker's report and notes | kept privately |

### Custody (2026.11.5)

- The driver pulled `t1` (excluding `home/`) and `t1.console` out of the bench and checked the in-bench manifest
  (`EVIDENCE-CHECK ok`, `host/steps.log:28`); the lab host's and the lab Mac's hash lists of the 83 pulled files are
  equal, and the lab sealed the job folder (86 files). The maintainer's `lab-verify` check on 2026-11-18 passed:
  sealed hashes re-checked, analyzer re-run gives the same six `VERDICT` lines, custody record matches the bench log.
  In the maintainer's copy, `sha256sum -c` of the original `t1/evidence.sha256` gives `OK` for all 64 files.
- Bench `r198178b` was destroyed at 2026-11-18T16:12:59Z–16:13:01Z (rc 0); the bench list before shows it running
  and the list after no longer shows it (`host/custody.txt`).
- Withheld original hashes (each would let a guess at a redacted address or name be confirmed): the kit archive,
  `run198178.sh`, `relay198178.py`, `shim198178.py`, the deployed bench tool, the `shim.log` line of
  `t1/evidence.sha256`, and the pulled `relay.jsonl`, `relay.log`, `steps.log` (host) and `shim.log`. They are kept
  in the lab's private store.
- No credential is in the published files: `home/` was never pulled; the only key in the bench was the dummy
  `lab-dummy-198178`; by the kit's design the lab proxy credential is read only by the host relay, outside the bench. A search of every `raw/v115/` and `kit/v115/`
  file for `Bearer`, `sk-`, `password`, `secret`, token- and key-shaped values finds only the kit's own redaction
  markers, the env-var name `SGLANG_API_KEY`, the dummy key in the kit, and the kit's redactor code.
