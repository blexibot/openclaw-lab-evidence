# Evidence packet: openclaw/openclaw#194166 on macOS (matched base vs head, backup path)

Status: **draft, not yet reviewed by the human publisher, not posted.** Synthetic fixtures only, on a disposable macOS
VM (user `admin`, uid 501; destroyed after the run). Publish this folder only as a fresh file copy, never by pushing
the lab's own repository.

**Custody and redactions.** Every file in `raw/` is byte-identical to the lab job `T194166r2`. On 2026-11-17 the files
were checked against the job's private `evidence.sha256` (all matched), and the six `attach.*`/`probe.*` files against
hashes taken on the lab host at fetch time. Four kit files were edited before publishing, so their hashes differ from
the lab's:
- `kit/d194166.sh`: build host address → `<LAB-LINUX-HOST>`, lab account → `<LAB-USER>`, SSH key name → `<KEY>`, VM tool
  path → `<VM-TOOL>`, lab host name removed from the header comment.
- `kit/m194166.sh`: the guest's sudo password is no longer inline; it is read from `GUEST_SUDO_PW` at run time.
- `kit/s194166.sh`, `kit/w194166.sh`: lab host name removed from a comment.
The kit tarball as run and the lab's hash list are not included because they would identify those values. The
capture manifests carry the guest's stock VM host name and random per-run UUIDs; nothing there identifies a machine.

## Summary

| Field | Value |
|---|---|
| PR / issue | openclaw/openclaw#194166 (fixes #191855) |
| Run ID | T194166r2 (one disposable macOS guest) |
| UTC time | 2026-11-16T21:27:50Z – about 22:30Z |
| Builds | PR base `8dd41fc95291553e5885fec09992bd41c3038004` (the head's parent; the PR body calls it base); PR head `5438a832520be89cde6799215b99a711fc039950`. **Both report `OpenClaw 2026.11.1`.** Also shipped release 2026.11.3 (`847611d`), preinstalled on the guest image (install log not in this packet) |
| Base/head build | repo packager in an Ubuntu 24.04 container from clean checkouts (`git status --porcelain` empty), installed with `npm install -g <tgz>`. Base buildid `2026.11.1-8dd41fc95291-2026-11-16T21-35-23.415Z`, tgz sha256 `3af2c602…a5a300d`; head buildid `2026.11.1-5438a832520b-2026-11-16T22-04-59.771Z`, tgz sha256 `eec57a9b…c273a55` (`raw/out/l-build-*.txt`, `INSTALL` lines in `raw/out/m-install-*-bk.txt`) |
| Head pin | unchanged during the run (`raw/verdicts.txt`: `PR_HEAD … moved=no`) |
| Guest | macOS 26.6.2 (25G83) arm64, Node v24.22.3, npm 11.19.1, user-writable npm prefix `~/.npm-global` (`raw/out/m-info.txt`) |
| Trigger | 64 MB APFS image, `hdiutil attach -owners on`, mounted at `<state>/workspace/state/labvol`. Its root carries macOS's own `.fseventsd`, `drwx------+ root staff` (ACL present). `stat` of the private marker inside it as the test user: `Permission denied` (`raw/ev/probe.bk-*-B1.txt`) |
| Command | `openclaw backup create --verify --json` (plus `--dry-run` once per build) |

**Narrow assertion and outcome.** Same kit, guest and trigger:
- PR base `8dd41fc`: `reproduced`. B1 (volume attached) exits 1 with `Private update capture marker is unreadable;
  export refused.`, no archive.
- PR head `5438a83`: `candidate passes this scenario`. B1 exits 0 with the warning `Skipped unreadable foreign entry:
  …/labvol/.fseventsd` and a manifest `skipped` entry with `"reason": "unreadable-foreign"`. The archive has no
  `.fseventsd` entry, and it holds the volume's one readable file `x.txt` with the controller's nonce. The off-volume
  control file `sibling/keep.txt` is also present, as it is in every successful backup.
- Release 2026.11.3: `reproduced` (same refusal). This was already posted on #191855 from the earlier run; it is
  context here.
- B0 (no volume) and B2 (volume detached again) succeed on all three builds.
- The N controls refuse or succeed as expected on all three builds (table below).

**Not covered by this packet (stated, not hidden).**
- **The update half: blocked at this base.** With the volume attached, `openclaw update` from base to a head tarball
  exited 0 with capture available. That is not a valid non-reproduction, because the trigger was not reached. On
  these 2026.11.1-based builds the original-state capture manifest (kind `update-recovery`) lists 9 entries under
  `.openclaw` (databases, config and a few state paths), with `excludedRoots: []` and no path on the volume. So the
  capture appears not to walk the workspace (inferred from the manifest; source not read). On shipped 2026.11.3 the
  update capture did reach the volume (it `lstat`ed the marker under `labvol/.fseventsd`; posted on #191855). Testing
  the update half needs a head on a base whose capture covers the workspace. This says nothing for or against the PR's
  update-capture change.
- `--dry-run` never hit the refusal on any build (rc 0, assets only `$OPENCLAW_HOME/.openclaw`); the refusal comes from
  the export walk.
- The refusal text names no path. "The refused entry is `.fseventsd`" for base and release is **inferred**: it is the
  only root-owned 0700 entry on the volume (`LSVOL` lines), and head names that path when it skips it.
- APFS with owners enabled only. BorClaw's machine has an HFS mount and a `noowners` APFS mount; neither was tested.
- Archives were listed and read back, not restored. One attempt per cell. No explicit-required-resource control (no
  CLI stimulus).

## Controls (from the `BK` lines in `raw/out/m-bk-*.txt`)

| Control | 2026.11.3 | base | head | Expected |
|---|---|---|---|---|
| N1 owned dir, mode 000 | rc=1 unreadable | rc=1 unreadable | rc=1 unreadable | refuse |
| N2 owned valid marker, mode 000 | rc=1 invalid | rc=1 invalid | rc=1 invalid | refuse |
| N3 owned malformed marker, readable | rc=1 invalid | rc=1 invalid | rc=1 invalid | refuse |
| N4 valid marker in owned `priv/` + `secret.txt` | rc=0, 0 `priv/` entries | rc=0, 0 | rc=0, 0 | succeed, nothing from `priv/` |
| N5 foreign marker (root, 0600, unreadable to the test user) in a searchable root-owned dir | rc=1 invalid | rc=1 invalid | rc=1 invalid | refuse |

`unreadable` = `Private update capture marker is unreadable; export refused.`; `invalid` = `Private update capture
marker is invalid or unreadable; export refused.` (the CLI's own text; the labels are the kit's grep categories).
N5's marker was unreadable to the test user in every row (`N5PROBE read_rc=1 eacces=1`).

## Assertions

Kinds use the standard's vocabulary: observed, source-supported, inferred, unknown.

| # | Claim | Artifact | Observation | Kind / limit |
|---|---|---|---|---|
| 1 | Trigger reached on every attached backup row | `raw/ev/probe.bk-*-B1.txt`; `raw/ev/attach.bk-*-B1.txt`; `TRIGGER` lines in `raw/out/m-bk-*.txt` | `stat: … Permission denied` on the marker under `.fseventsd`; image mounted at `…/labvol` | observed |
| 2 | Base refuses B1 | `raw/ev/bk-base.B1.backup.txt` | rc=1, `Private update capture marker is unreadable; export refused.` | observed |
| 3 | Head completes B1 and skips `.fseventsd` | `raw/ev/bk-head.B1.backup.txt`, `raw/ev/bk-head.B1.manifest.json` (line 56), `raw/ev/bk-head.B1.list` | rc=0; warning names `.fseventsd`; `unreadable-foreign`; no `.fseventsd` in the archive list | observed |
| 4 | The volume's readable file is kept by head | `ARCH bk-head B1 … x=892f51504c5e48bf` in `raw/out/m-bk-head.txt`; `raw/ev/bk-head.B1.list` | `x.txt` present, nonce matches | observed (via the kit's nonce check; archive not restored) |
| 5 | Release refuses as base does | `raw/ev/bk-rel.B1.backup.txt` | same message, rc=1 | observed |
| 6 | B0 and B2 succeed on all builds | `BK … B0` / `BK … B2` lines in `raw/out/m-bk-*.txt` | rc=0, no refusal | observed |
| 7 | Base and head identity | `raw/out/l-build-*.txt`, `INSTALL` lines in `raw/out/m-install-*-bk.txt` | clean checkouts; installed version and buildid match each build | observed |
| 8 | Dry-run does not hit the refusal | `raw/ev/bk-*.B1.dryrun.txt` (last line `rc=0`) | plan has only `.openclaw` assets | observed. The verdict line's `DRY rc=` is always 0 (kit bug), so the file is the source |
| 9 | Refused entry on base/release is `.fseventsd` | `LSVOL` lines; claim 3 | only root-owned 0700 entry on the volume | inferred |
| 10 | Refusal controls unchanged by head | controls table | all as expected | observed; one observation per cell |
| 11 | Update half blocked at this base | `raw/ev/up-head-att.capture1.manifest.json`, `raw/ev/up-base-att.capture1.manifest.json`, `raw/out/m-up-*-att.txt` | kind `update-recovery`, 9 entries, `excludedRoots: []`, no `labvol` path | observed manifest. "Does not walk the workspace" is inferred; source not read |
| 12 | Head pin unchanged during the run | `raw/verdicts.txt` | `PR_HEAD … moved=no` | observed |

## Replay

`kit/` holds the scripts as run, with the edits listed above. `d194166.sh` drives the run, `m194166.sh` runs on the
guest, and `l194166-build.sh` builds in the Linux container. Invocation: `bash d194166.sh` from a job folder, with a
macOS 26 VM image (the release preinstalled) and an Ubuntu 24.04 container. Set `GUEST_SUDO_PW` to the guest's
password; per the kit header, sudo is used only to create and remove the root-owned N5 fixture. The APFS image is
created and attached by the test user.

`MANIFEST.sha256` covers every file in this folder except itself (`find . -type f | LC_ALL=C sort`).
