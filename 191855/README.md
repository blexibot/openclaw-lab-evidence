# Evidence packet: openclaw/openclaw#191855 (and draft PR #194166)

Status: **lab packet, not posted.** Nothing here has been published. The human publication gate still applies.

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#191855: update capture and `backup create` refuse a directory the user cannot search ("Private update capture marker is unreadable; export refused.") |
| Candidate | openclaw/openclaw#194166 (draft), head `5438a832520be89cde6799215b99a711fc039950`. PR state and head were read from the fetch at 09:17Z; recheck both before posting |
| Run ID | lab ticket `20261116-0900-11-lab-191855-foreign-dir` (job T191855) |
| Observation window (UTC) | 2026-11-16T09:04:19Z (first step) to 09:57:22Z (last step). The worker's receipt closed at 10:17:51Z |
| Kit | `kit/ORDER.md` (the ticket; public copy redacted, see Redactions) plus `kit/scripts/*.sh` (byte-identical to what ran) |

### Narrow assertions and outcomes

Outcome words follow the lab rules: `reproduced` · `not reproduced under these conditions` · `blocked` ·
`inconclusive / harness failure` · `candidate passes this scenario`.

| # | Assertion (only what was observed) | Outcome | Attempts / failures |
|---|---|---|---|
| A2 | On shipped **2026.11.3** (`847611d`), macOS 26.6.2 guest, with an APFS disk image attached by the user (`hdiutil attach -owners on`) at `<state>/workspace/state/labvol`, the image's `.fseventsd` was `root:staff drwx------`. `stat` of the marker inside it failed with "Permission denied", and `openclaw backup create --verify --json` exited 1 with "Private update capture marker is unreadable; export refused." After `hdiutil detach`, the same command exited 0 | **reproduced** | 1 attempt, 1 refusal; 1 detach control, passed |
| A3 | Same image and command on shipped **2026.11.4** (`d843d6a`): same refusal, rc=1. After detach: rc=0 | **reproduced** | 1 / 1; control passed once |
| A4 | `openclaw update --tag 2026.11.4 --yes --no-restart --json` from 2026.11.3. **U1, image attached:** update capture logged as a *warning* ("Original state capture is unavailable; the update continues without it"), with cause `EACCES: permission denied, lstat '$OPENCLAW_STATE_DIR/workspace/state/labvol/.fseventsd/.openclaw-private-update-capture'`. The run then failed at step `package-update`, reason `global-install-permission-denied`, with "Package update cannot write /Users/admin/.npm-global/lib/node_modules (EACCES; owner UID 501, GID 20)". The running user was uid 501, and `ls` showed that directory as `drwxr-xr-x admin staff`. The version stayed 2026.11.3. **U2, image detached:** update rc=0, the capture was retained, and the version became 2026.11.4 | **reproduced** (the shape of the reported updater symptom: a failure whose message names a directory the running user owns) | U1: 1 run, 1 failure. U2: 1 run, 0 failures |
| B | Ubuntu 24.04 container, 2026.11.3, user `lab` (uid 1001). A root-created `drwx------ root root` directory at `<state>/workspace/state/foreign`: `stat` of the marker gave Permission denied, and `backup create --verify` exited 1 with the same refusal. After root `rmdir`: rc=0 | **reproduced** | 1 / 1; control passed once |
| C1 | PR #194166 head `5438a83`, built from source (it reports itself as `OpenClaw 2026.11.1 (5438a83)`), on the same Linux container and state, with the same root-owned `foreign` directory: `backup create --verify` exited 0. The output lists `{"kind":"entry", …/foreign, "reason":"unreadable-foreign"}` under `skipped`, with the warning "Skipped unreadable foreign entry: …/foreign" | **candidate passes this scenario** (backup only, Linux only) | 1 / 0 failures |
| C2 | Same PR build. **N1:** a directory owned by `lab` at mode 000 → rc=1, "Private update capture marker is unreadable; export refused." **N2:** a marker file owned by `lab` at mode 000 → rc=1, "Private update capture marker is invalid or unreadable; export refused." | refusal controls held (each refused once) | 1 run each |

The one decisive comparison: with the foreign-owned unsearchable directory present, the shipped CLI refuses
`backup create`, and removing that directory is enough to make it succeed (macOS 2026.11.3, macOS 2026.11.4, Linux
2026.11.3). On Linux, the PR head completes the same backup and records the skip, while the two owned-entry controls
still refuse.

### Limits (material first)

1. **Backup only, for the candidate.** The PR build was tested only with `backup create` on Linux. The macOS
   attached-volume case, the original update capture, and `openclaw update` were **not run** on the PR build. This
   packet says nothing about whether the updater symptom is repaired.
2. **No matched base.** No parent/base build of the PR branch was tested with the same kit. The shipped
   2026.11.3/2026.11.4 releases are not the PR's base: the branch reports package version 2026.11.1. The comparison
   is confounded, so attribution stops at "candidate passes this scenario".
3. **The PR build ran on state written by 2026.11.3.** Every PR-build backup printed "Your OpenClaw config was
   written by version 2026.11.3, but this command is running 2026.11.1." Each `--verify` run also printed
   "[state/db] state database schema migration pending; verifying integrity first" and "Warning: the backup outcome
   could not be recorded: Client credentials require backed-up migration custody …". The effect of these on the
   result is **unknown**. They are not established as harmless.
4. **Archive contents were not inspected.** `--verify` exited 0, which shows the archive is internally valid. It does
   not show that `foreign` is absent from it, that readable siblings were retained, or that a restore works.
   Archives were not copied out of the benches.
5. **The updater contrast identifies a trigger, not the failed operation.** In U1 the capture refusal was logged as
   a warning, and the update continued. The failing step was `package-update`. Which syscall or path was actually
   denied is **unknown**. Both releases lack the diagnostic/classifier change in #194160. The shipped 2026.11.3
   `dist` was checked by grep on the bench and does not contain its text. 2026.11.4 was checked only in source,
   before the run (`kit/ORDER.md`). U1 and U2 ran one after the other on the same bench (U1 first), not
   counterbalanced. Both started from a 2026.11.3 install that had been upgraded to 2026.11.4 and downgraded again
   during A3 (`outputs/bench-log.tsv`). During U2, the updater's own candidate checks ran `gateway run` internally;
   the kit started no Gateway.
6. **Single attempt per cell.** No repeats, so nothing here is a rate.
7. **Topology.** The macOS runs were in a Tart VM guest on an Apple Silicon lab Mac. The disk image was created and
   attached inside the guest. The Linux runs were in an Incus **container** (not a VM) with `security.nesting=true`,
   sharing the lab host's kernel. No model, provider or channel was configured.

### Reported preconditions not matched

- Reporter: macOS 26.3.1 arm64, npm prefix `/opt/homebrew`, a real mounted volume (type not stated in our ticket).
  Here: macOS 26.6.2 (25G83) arm64 guest, npm prefix `~/.npm-global` (user-writable), a 64 MB APFS disk image. The
  updater message names `~/.npm-global/lib/node_modules`, not `/opt/homebrew/lib/node_modules`.
- Planned A2 variants that were not run: V2 (APFS, default ownership), V3 (HFS+), and **V4 (a root-owned directory
  with no volume on macOS)**. The ticket required V4 always; it was missed. On Linux, part B has the equivalent shape.
- The issue's part (a) (ProcSafeError "unterminated Darwin environment", Terminal plus a LaunchAgent gateway) was out
  of scope. The string did not appear in any captured output.
- A systemd `ProtectHome` trigger (from a commenter) was deliberately not tested.

## Inputs

### Code identity

| Item | Value | Evidence kind |
|---|---|---|
| Shipped CLI A | `openclaw@2026.11.3`, banner `OpenClaw 2026.11.3 (847611d)`, buildId `2026.11.3-release-847611dcaa3b-2026-11-10T11-11-36.248Z` | observed (`outputs/a0.txt`, `outputs/a4-u1.txt`) |
| Shipped CLI B | `openclaw@2026.11.4`, banner `OpenClaw 2026.11.4 (d843d6a)`, buildId `2026.11.4-release-d843d6af39a4-2026-11-15T22-45-53.485Z` | observed (`outputs/a3.txt`, `outputs/a4-u2-excerpt.txt`) |
| Registry integrity, 2026.11.3 | `sha512-FBq/q0TCaoA2b7qfdV0q81fHhI6RBB1zAQfJQREc1u2TlK5khVgCUsAlXskLWthyVqRz5PWEj+oOmfYgK58dHg==` (shasum `d7db24ae086448184e328ff69a39cbea3e43d4b6`) | registry metadata (`npm view`, read 2026-11-16). The installed tarball's integrity on the bench was **not recorded** |
| Registry integrity, 2026.11.4 | `sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==` (shasum `71eeeac4e4b95a0d2bb6c80fb1e0463ac7ec79b9`) | registry metadata, as above |
| Install method (macOS) | the bench tool runs `npm install -g openclaw@<v> --no-fund --no-audit` in the guest, as the guest user (the prefix is user-writable). U2's 2026.11.4 came from `openclaw update` itself | the tool's source (read-only), plus the U2 output |
| Install method (Linux) | the bench tool installs the Node v24.22.3 official tarball (SHA-checked) to `/usr/local`, then runs `npm install -g openclaw@2026.11.3` as root in the container. Tests ran as `lab` | the tool's source (read-only) |
| Candidate | `git fetch --depth 1 origin pull/194166/head`; `git rev-parse HEAD` = `5438a832520be89cde6799215b99a711fc039950`; built with `pnpm install --frozen-lockfile && pnpm build` (pnpm 12.15.0, downloaded by corepack; Node v24.22.3); `build rc=0`; run as `node /home/lab/pr/openclaw.mjs`; banner `OpenClaw 2026.11.1 (5438a83)` | observed (`outputs/c-build-excerpt.txt`, `outputs/c1.txt`) |
| Running Gateway revision | none: the kit started no Gateway. The updater's internal candidate check in U2 ran `gateway run` from the candidate package | observed (`outputs/a4-u2-excerpt.txt`) |
| #194160 text in shipped dist | `grep -rl "denied path is unknown or outside the install root" <npm root -g>/openclaw/dist` → no match (rc=1) on **2026.11.3**. Not run on 2026.11.4 | observed for 2026.11.3 (`outputs/a0.txt`); source-supported only for 2026.11.4 (`kit/ORDER.md`) |

### Kit and invocation

- Ticket: `kit/ORDER.md`. The original's sha256 is `f000b40c4e9079143d03f13907ec67e34bf95bd311649c3f85a360255287e811`,
  which matches `kit/order.json`. The public copy is redacted, so its bytes and hash differ (see Redactions).
- Scripts: `kit/scripts/*.sh`. Each one is byte-identical to the file the worker hashed in its private
  `evidence.sha256`.
- Per-step invocation (from the ticket's recipes). Each script was copied into the bench, its hash was checked on
  both sides, then:
  - macOS: `/usr/local/bin/bench exec t191855-mac -- 'zsh ~/<s>.sh' > <s>.txt 2>&1; echo "host-rc=$?" >> <s>.txt`
  - Linux as `lab`: `ssh <user>@<LAB-HOST> 'bench exec t191855-lin -- su - lab -c "bash /home/lab/<s>.sh"' > <s>.txt 2>&1`
  - Linux as root (`b2root`, `b3root`, `c0root`, `c1root` only): `... 'bench exec t191855-lin -- bash /home/lab/<s>.sh'`
  - PR build: `kit/scripts/J191855c.sh` in a detached tmux session on the Linux lab host; it runs `c-build.sh` as
    `lab`.
- Each script starts with `export OPENCLAW_HOME=…`, `set -x` and `date -u`, so every command and its UTC start time
  appears in the output.
- Bench lifecycle, with UTC times: `outputs/bench-log.tsv`.

### Fixture and configuration

- The fixture is synthetic: `openclaw setup --baseline` (no onboarding, no model, no provider, no channel), then the
  foreign directory or disk image described above.
- The configuration is whatever `setup --baseline` wrote. Its file contents were **not captured** (only `ls -la`
  in `outputs/a1-redacted.txt`), so no config file is included. It is unknown beyond "baseline, unmodified by the
  kit". The updater's Doctor changed the config keys `meta` and `wizard` during U2 (observed in private raw output).
- Resolved paths, from the real backup plan (dry-run and `--verify` JSON):
  - macOS: `OPENCLAW_HOME=/Users/admin/t191855`; state `/Users/admin/t191855/.openclaw`; workspace
    `/Users/admin/t191855/.openclaw/workspace` (skipped as `covered` by state); agent root
    `…/.openclaw/agents/main/agent`; foreign mount `…/.openclaw/workspace/state/labvol`.
  - Linux: `OPENCLAW_HOME=/home/lab/t191855`; state `/home/lab/t191855/.openclaw`; workspace
    `/home/lab/t191855/.openclaw/workspace`; foreign directory `…/.openclaw/workspace/state/foreign`.
  - The updater's state dir is `/Users/admin/t191855/.openclaw` (from its suggested `OPENCLAW_STATE_DIR` line in U1).

### Environment

| | macOS | Linux |
|---|---|---|
| OS / build | macOS 26.6.2, build 25G83 (guest) | Ubuntu 24.04.5 LTS (container) |
| Arch | arm64 | x86_64 / amd64 (apt and pnpm packages) |
| Virtualisation | Tart VM cloned from a golden image, on an Apple Silicon lab Mac (host macOS 27.0 26A425, unchanged since before the run). Tart version unknown | Incus 6.0.5 **container**, `security.nesting=true`; host kernel `Linux 7.0.0-43-generic x86_64` (host up since 2026-11-13, so the same kernel was running at test time) |
| Runtime | Node v24.22.3, npm 11.19.1, npm prefix `/Users/admin/.npm-global` | Node v24.22.3, npm 11.19.1 |
| Test user | `admin`, uid 501, gid 20 (staff), in group `admin` (synthetic guest account) | `lab`, uid 1001 (synthetic) |
| Privileges | `openclaw` never ran as root. On macOS no sudo was used at all (V4 was not run) | Root was used only for `b2root`, `b3root`, `c0root` and `c1root` (creating or removing the foreign directory, installing git and corepack) |
| Foreign entry | `.fseventsd` on the attached image: `drwx------+ root staff`, ACL `group:everyone allow readextattr`; `diskutil` reports Owners: Enabled | `drwx------ root root`, created by root |

Backend, model digest, route and context window: **not applicable** (no model was used). Proxy/filter and capture
position: **not applicable** (no network capture; evidence is CLI stdout/stderr and exit codes only).

## Outputs

`outputs/` holds the decisive raw outputs. Each one has `set -x` command traces, UTC timestamps and inline
`rc=` lines.

| File | What it shows |
|---|---|
| `a0.txt` | OS, Node/npm, banner, `id`, the #194160 grep (2026.11.3) |
| `a1-redacted.txt` | `backup create --help`, `update --help`, `setup --baseline`, baseline dry-run and `--verify` (both rc=0), `ls` of state |
| `a2-v1.txt` | **macOS 2026.11.3 refusal** and the detach control |
| `a3.txt` | **macOS 2026.11.4 refusal** and the detach control |
| `a4-u1.txt` | updater with the image attached (full JSON; one guest hostname redacted) |
| `a4-u2-excerpt.txt` | updater with the image detached (excerpt; omitted ranges are marked) |
| `b1.txt`, `b2root.txt`, `b2.txt`, `b3root.txt`, `b3.txt` | **Linux 2026.11.3**: baseline, root-owned directory, refusal, removal, success |
| `c0root.txt`, `c-build-excerpt.txt` | PR build prerequisites; PR head hash and build result (excerpt) |
| `c1root.txt`, `c1.txt` | **PR head**: root-owned directory recreated; skip recorded, rc=0 |
| `c2.txt` | **PR head**: N1 and N2 controls, both refused |
| `bench-log.tsv` | bench create, install and destroy times on both lab hosts |
| `worker-receipt.json` | the lab worker's terminal receipt (state `passed`, report sha256) |

The detailed claim → artifact mapping is in `ASSERTIONS.md`. `MANIFEST.sha256` covers every file in this packet
except itself.

## Custody

- The raw job folder was copied off the lab Mac before this packet was built. It is kept private, with the worker's
  own `evidence.sha256`; every listed file matched except `report.md`, which the worker edited after hashing, as its
  report says. Both benches were destroyed after the run (`bench-log.tsv`).
- The `.txt` files in `outputs/` without a `-redacted` or `-excerpt` suffix are byte-identical to the worker's
  hashed originals, except `a4-u1.txt`. `worker-receipt.json` is a byte copy of the lab mailbox receipt.
  `bench-log.tsv` is a transcription of the matching lines from each lab host's bench log, read after the run. `a1-redacted.txt`, `a4-u1.txt`, `a4-u2-excerpt.txt` and `c-build-excerpt.txt` are
  edited copies. Their hashes in `MANIFEST.sha256` identify only these published bytes, not the originals.

## Redactions

- `kit/ORDER.md`: the lab host IP is replaced with `<LAB-HOST>` and the lab service account with `<user>`. The guest
  image's default sudo secret is replaced with `<GUEST-SUDO-PASSWORD>`. The worker's lease-file name is replaced with
  `<lease-file>`, and the words of two redaction instructions are neutralised. The owner's name is replaced with
  "the owner".
- `outputs/a1-redacted.txt`: the `openclaw setup --help` flag listing is omitted (it names credential flags; no
  values).
- `outputs/a4-u1.txt`: the guest VM hostname is replaced with `<GUEST-HOST>`.
- `outputs/a4-u2-excerpt.txt`: Doctor and lint progress is omitted (this includes a generic "Gateway auth is off"
  lint finding, with no values).
- Usernames `admin` (macOS guest) and `lab` (Linux container) are synthetic bench accounts and are kept.
