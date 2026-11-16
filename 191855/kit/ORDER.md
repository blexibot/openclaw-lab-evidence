# Lab ticket T191855: openclaw/openclaw#191855, update capture and backup refuse a root-owned foreign directory, shipped-CLI RED on macOS, Linux control, PR #194166 GREEN (from the Maintainer)

- **Kind:** execute, on throwaway benches only: **one** Tart macOS bench `t191855-mac` (made with
  `/usr/local/bin/bench` on lab-mac, this Mac), then **one** Incus bench `t191855-lin` (made with `bench` on lab-linux,
  over SSH). No model, no gateway, no channel accounts are needed.
- **Done means:** Part A says whether shipped 2026.11.3 refuses `backup create` (and what `openclaw update` does) with a
  real root-owned 0700 directory under the state dir on macOS, with the exact output; Part B gives the same on Linux;
  Part C (if time) gives PR #194166's built CLI on the same shape; both benches are destroyed; the evidence sha256 file
  exists and its lines are in the report.
- **Write scope:** on lab-mac: `~/worker/jobs/T191855/` and `~/worker/notes/`. On lab-linux: only
  `~/jobs/J191855c.*` (the Part C long-job files). Inside the two benches: anything. Everything else is read-only.
- **Durable home:** `~/worker/notes/TIPS.md`. **Step 0, before anything else:** add your lessons from LM4 (and any
  ticket since), then this ticket's lesson before you finish. Quote the lines in your report.

Lab-internal. Touch nothing outside the write scope above. **Post nothing anywhere public** (GitHub is read-only for
this lab: no comments, reactions, labels, PRs). Cloning or fetching public code from github.com inside a bench (Part C)
is allowed; that is reading. Results go in your report only. This may become a public comment to the OpenClaw
maintainers, so precision beats speed.

**Time box: 3 hours of lab time, hard stop.** Write your start time (UTC, `date -u +%FT%TZ`) as the first line of
`~/worker/jobs/T191855/evidence.txt`, and write `HARD STOP = <start + 2 h 45 min>` as the second line. At the start of
**every** turn, compare `date -u` with that line. Once it has passed: stop whatever is running, destroy both benches,
write what you have, and finish (`stopped` with "time box" if Part A2 is incomplete; otherwise the normal result with
the rest marked `not run` or `partial`).

**Order of work (follow it exactly):** A0 → A1 → A2 → A3 → (A4 only if at least **2 h 00 min** remain before the hard
stop) → A5 (destroy the Mac bench) → B → (C only if at least **75 min** remain). If time is short, C is dropped first,
then A4. Never start B while the Mac bench still exists.

This ticket uses **no model**. Do not configure a model provider, do not start a gateway, do not run `openclaw onboard`
or `openclaw setup` without `--baseline`, and do not install any service.

## The bug (#191855, plain)
OpenClaw's update capture and `backup create` walk the state directory. For every real directory they meet, they
`lstat` a privacy marker inside it (`<dir>/.openclaw-private-update-capture`). If that `lstat` fails with anything
other than ENOENT/ENOTDIR (for example EACCES, because the directory belongs to root and is mode 0700), they throw
**"Private update capture marker is unreadable; export refused."** and the whole capture or backup fails. On macOS the
everyday trigger is a mounted volume inside the state dir: its `.fseventsd` folder is root-owned 0700. The reporter
(macOS 26.3.1 arm64, npm under /opt/homebrew) also saw the updater fail with a misleading
"cannot write /opt/homebrew/lib/node_modules" EACCES.

What the Maintainer checked (read-only, `gh api`, 2026-11-15/16):
- **verified:** `src/infra/update-capture-paths.ts` is the **same blob** (`a2fa793b…`) at tags v2026.11.3 and
  v2026.11.4, and contains the throw above (twice: once for the marker `lstat`, once for an `lstat` of a path
  component). A second, different refusal also exists: "Private update capture marker is invalid or unreadable; export
  refused." (a marker file that exists but cannot be read or has the wrong bytes).
- **verified:** `backup create` at v2026.11.3 imports `isUpdateCapturePath` from that file
  (`src/infra/backup-create.ts`, `src/commands/backup-resource-inventory.ts`), and includes workspaces by default
  (there is a `--no-include-workspace` flag).
- **verified:** neither tag contains #194160's new classifier text ("denied path is unknown or outside the install
  root"); both still have the old `Package update cannot write ${directory}` message. So the misleading-EACCES fix
  is **not** in 2026.11.3 or 2026.11.4.
- **verified:** the fix PR #194166 ("skip unreadable foreign directories during update capture") is an **open draft**,
  head `5438a832520be89cde6799215b99a711fc039950`. It skips an entry only when the error is EACCES/EPERM **and** the
  first stat-able path at or above the failure is owned by a **different uid**; its warning text is
  `Skipped unreadable foreign entry: <path>`. Its own body says built-CLI RED/GREEN "with a real root-owned 0700
  workspace directory remains unproven", and the review bot asks for a "shipped-CLI baseline failure and repaired
  capture/backup success with genuine foreign ownership". **That missing proof is this ticket.**
- **verified (CLI flags at v2026.11.3, from source):** `openclaw setup --baseline` ("Create baseline
  config/workspace/session folders without onboarding"); `openclaw backup create` has `--output <path>`, `--json`,
  `--dry-run`, `--verify`; `openclaw update` has `--json`, `--no-restart`, `--dry-run`, `--tag <version>`, `--yes`.
  Still confirm each with `--help` on the bench and record the help text.
- **inferred, not tested on our image:** a user-attached `hdiutil` volume gets a root-owned 0700 `.fseventsd`
  without sudo, **but only if the volume honours ownership**. Disk images may mount with ownership ignored, in which
  case everything shows as yours and there is no EACCES. That is why A2 has a small matrix. Also inferred:
  `hdiutil attach` works over SSH in the guest (if it fails with a session/permission error, record it and go to V4).

Do **not** chase part (a) of the issue (ProcSafeError "unterminated Darwin environment"): it needs Terminal and a
LaunchAgent gateway. If that string appears anywhere in your output, just record it.

## Rules for this ticket
- **Never run `openclaw` under sudo or as root.** The bug is a normal user versus root. Root ignores 0700 and the bug
  vanishes. In the Mac guest, sudo (`echo <GUEST-SUDO-PASSWORD> | sudo -S -p '' …`, the golden's documented default password) is
  allowed only for the V4 `mkdir`/`rmdir` in A2. On Linux, root is used only for the setup steps marked "as root".
- **Every guest command runs from a script file.** Each `bench exec` is a fresh SSH login: `export`, `cd` and shell
  variables do **not** carry over between calls. So each step below is a small script you write **on lab-mac** in
  `~/worker/jobs/T191855/`, send into the bench, check, run, and capture. Each script must start with these lines
  (macOS guest, zsh):

  ```
  export OPENCLAW_HOME=$HOME/t191855
  set -x
  date -u +%FT%TZ
  ```
  (Linux scripts: `#!/bin/bash`, then `export OPENCLAW_HOME=/home/lab/t191855`, `set -x`, `date -u +%FT%TZ`.)
  `set -x` prints each command into the captured output, which is the "every command" part of the evidence. After
  A1, also add the line `STATE=<the real state dir>` and `W=<the real workspace>/state` with the literal paths you
  found (no guessing).
- **Mac recipe** (all on lab-mac; `J=~/worker/jobs/T191855`; `<s>` = the script's name, for example `a1`):
  1. `/usr/local/bin/bench exec t191855-mac -- 'cat > ~/<s>.sh' < $J/<s>.sh`
  2. `/usr/local/bin/bench exec t191855-mac -- 'shasum -a 256 ~/<s>.sh'` and `shasum -a 256 $J/<s>.sh`: the two
     hashes must match (compare with a command, not by eye). If not, the copy failed: stop and fix it.
  3. `/usr/local/bin/bench exec t191855-mac -- 'zsh ~/<s>.sh' > $J/<s>.txt 2>&1; echo "host-rc=$?" >> $J/<s>.txt`
  4. `test -s $J/<s>.txt && wc -l $J/<s>.txt` must show lines (LM4: a quoted grep inside `bench exec` silently made an
     empty file). Then append it to `evidence.txt`: `cat $J/<s>.txt >> $J/evidence.txt`.
  Never put `$`, `|`, `>` or nested quotes directly in a `bench exec` line; they go in the script.
- **Linux recipe** (all from lab-mac; `LX='ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST>'` is only shorthand in
  this text, type the full ssh command each time):
  1. Copy: `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench exec t191855-lin -- tee /home/lab/<s>.sh' < $J/<s>.sh > /dev/null`
  2. Check: `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench exec t191855-lin -- sha256sum /home/lab/<s>.sh'`
     against `shasum -a 256 $J/<s>.sh`. Must match.
  3. Run **as lab**: `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench exec t191855-lin -- su - lab -c "bash /home/lab/<s>.sh"' > $J/<s>.txt 2>&1; echo "host-rc=$?" >> $J/<s>.txt`
     Run **as root** (only where the step says so): `... 'bench exec t191855-lin -- bash /home/lab/<s>.sh' > $J/<s>.txt 2>&1`
  4. Non-empty check and append to `evidence.txt`, as on the Mac.
  The Linux `bench exec` passes arguments straight to `incus exec` (no shell); that is why the command inside is a
  plain `su - lab -c "bash <file>"` and nothing more.
- Record each `echo rc=$?` **directly after** the command it belongs to (inside the script), never after a pipe.

## Part A: macOS, the reporter's platform (lab-mac)
**A0. Bench.** Run `/usr/local/bin/bench list` and record it. If two macOS VMs are already RUNNING, stop and finish
`stopped` ("no macOS slot"); do not stop anyone else's VM. Then `/usr/local/bin/bench new t191855-mac` (clones
`golden-macos26`, boots, prints the name) and `/usr/local/bin/bench openclaw t191855-mac 2026.11.3` (prints the
version; record it). Script `a0`:

```
sw_vers; uname -m; node --version; npm --version; npm prefix -g; openclaw --version; id
grep -rl "denied path is unknown or outside the install root" "$(npm root -g)/openclaw/dist" | head -3
echo "grep194160 rc=$pipestatus[1]"
```
(zsh's `$pipestatus[1]` is grep's own exit code: 1 means "not found", which is the expected result.) Note: the
golden's npm prefix is `~/.npm-global` (user-writable; **documented** in the bench tool), not the reporter's
`/opt/homebrew`. That's fine for the capture refusal; say so in the report.

**A1. State dir and workspace (max 20 min).** Script `a1` (after the standard header):

```
mkdir -p $OPENCLAW_HOME $HOME/t191855-out
openclaw backup create --help; openclaw setup --help; openclaw update --help
openclaw setup --baseline; echo "setup rc=$?"
openclaw backup create --dry-run --json; echo "dryrun rc=$?"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"
ls -la $OPENCLAW_HOME $OPENCLAW_HOME/.openclaw
```
- If `setup --baseline` fails or asks a question: record it, then use the fallback in a new script `a1b`:
  `mkdir -p $OPENCLAW_HOME/.openclaw/workspace; echo '{}' > $OPENCLAW_HOME/.openclaw/openclaw.json`, then the two
  backup commands again. Say so in the report.
- **Baseline (must pass):** both backup commands exit 0. From the dry-run JSON, read the state dir and the workspace
  path(s) and write them in `evidence.txt` as `STATE=…` and `WORKSPACE=…` (the expected values are
  `$HOME/t191855/.openclaw` and `$HOME/t191855/.openclaw/workspace`, **inferred** from `src/config/paths.ts`; use what
  the plan really says). Then `W=<WORKSPACE>/state`. If the baseline itself fails, record it, skip to A5, then Part B.

**A2. RED: a real root-owned 0700 directory under the workspace.** Run the variants **one at a time** (one script
each: `a2-v1`, `a2-v2`, …), each ending with its volume detached. Stop trying further variants once one is RED, except
that V4 is **always** run (it is the no-volume control). Each script, after the header and the `STATE=`/`W=` lines:

| Variant | Create and attach (as admin, no sudo) |
|---|---|
| V1 APFS, owners on | `hdiutil create -size 64m -fs APFS -volname labvol1 ~/labvol1.dmg; mkdir -p $W/labvol; hdiutil attach -owners on -mountpoint $W/labvol ~/labvol1.dmg; echo "attach rc=$?"` |
| V2 APFS, default | the same with `labvol2` and **no** `-owners` flag |
| V3 HFS+, owners on | `hdiutil create -size 64m -fs HFS+ -volname labvol3 ~/labvol3.dmg`, then attach `-owners on` at `$W/labvol` |
| V4 root dir, no volume | `mkdir -p $W; echo <GUEST-SUDO-PASSWORD> \| sudo -S -p '' mkdir -m 700 $W/rootdir; echo "mkdir rc=$?"` (in the script, write the pipe as a normal `|`) |

Then, in the same script (for V4 use `$W/rootdir` where it says `$W/labvol/.fseventsd`):
1. `echo x > $W/labvol/x.txt`, then wait up to 30 s for `.fseventsd`:
   `for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do [ -e $W/labvol/.fseventsd ] && break; sleep 2; done`
   (this short wait inside a guest script is fine; it is not a polling loop in your turn).
2. `mount | grep labvol; diskutil info $W/labvol | grep -iE 'owners|file system|mount point'`;
   `ls -leOd $W/labvol $W/labvol/.fseventsd`;
   `stat $W/labvol/.fseventsd/.openclaw-private-update-capture; echo "stat rc=$?"`
   (expect "Permission denied" and rc 1 for a true RED shape).
3. `openclaw backup create --dry-run --json; echo "dryrun rc=$?"` and
   `openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"`.
   Expected for RED: non-zero exit carrying "Private update capture marker is unreadable; export refused." Keep the
   full output, the exit code, and any `cause` (EACCES, the path).
4. Detach: `hdiutil detach $W/labvol; echo "detach rc=$?"` (V4: `echo <GUEST-SUDO-PASSWORD> | sudo -S -p '' rmdir $W/rootdir`).
   Rerun the `--verify` backup once; it should succeed again (the "remove the foreign dir and it works" control).

**Reproduced (RED)** means: in at least one variant, `stat` of the marker path inside the root-owned dir gives
"Permission denied" (EACCES), **and** `backup create --verify` exits non-zero with the refusal text. Write the results
table in `evidence.txt` (variant → owner/mode of the dir → `stat` result → dry-run rc → backup rc → message). Note for
each variant that was not RED, why (owners ignored, no `.fseventsd`, walker didn't cross the mount, etc.). That table
is the most useful thing in this ticket. "Best RED variant" below means the first RED one (prefer a volume variant
over V4).

**A3. Same check on 2026.11.4.** `/usr/local/bin/bench openclaw t191855-mac 2026.11.4` (record the printed version),
then script `a3`: recreate/reattach the best RED variant (the `.dmg` from A2 is still in `~`, so V1–V3 need only the
`hdiutil attach` line), run A2 steps 2–4 again. Then `/usr/local/bin/bench openclaw t191855-mac 2026.11.3` to go back
and record the printed version.

**A4. The updater with the foreign dir present (2026.11.3 → 2026.11.4).** Only if at least 2 h 00 min remain. The
command, the same in U1 and U2 (all flags **verified** in source; confirm in the `update --help` you saved in A1):
`openclaw update --tag 2026.11.4 --yes --no-restart --json`. Pin `--tag 2026.11.4` so a newer release cannot slip in.
1. **U1, foreign dir present** (script `a4-u1`): attach the best RED variant, then
   `touch ~/u1-marker; openclaw update --tag 2026.11.4 --yes --no-restart --json; echo "update rc=$?"; openclaw --version`.
   Then `find $STATE $HOME/.openclaw -newer ~/u1-marker -type f 2>/dev/null` and `cat` each file it lists that is
   under 200 KB and ends in `.json`, `.log` or `.txt` (they are synthetic; before you copy the output anywhere, check
   it for credential-like strings and replace any value with `<redacted>`). Then
   `openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"` on the new version with the
   volume still attached, then detach.
   Record: every phase line; whether "Original state capture is unavailable" appears; whether any step fails with
   `global-install-permission-denied` or "cannot write …node_modules"; the final `openclaw --version`.
2. **U2, control** (script `a4-u2`): volume detached. First on lab-mac:
   `/usr/local/bin/bench openclaw t191855-mac 2026.11.3` (record the version), then the same update command in the
   script. Record the same fields.
   **The useful result** is the difference between U1 and U2. If U1 shows the misleading permission error, that is a
   big find (maintainers could not reproduce it): capture everything, including `npm config list` and
   `ls -leOd "$(npm prefix -g)/lib/node_modules"` (in a script).
3. If the updater asks to restart or install a gateway service, it must not: `--no-restart --yes` should prevent it.
   If it still tries, record exactly what it said; do not start any gateway yourself.

**A5.** `/usr/local/bin/bench destroy t191855-mac`, then `/usr/local/bin/bench list` must show no `t191855-mac`
(record it). Do this before Part B, so no macOS VM is left running.

## Part B: Linux control (lab-linux, by SSH from lab-mac)
Incus benches run commands as **root**, which would hide the bug. So every openclaw command below runs as a normal
user `lab` (the Linux recipe's "as lab" form).
1. On lab-mac:
   `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench new ubuntu/24.04 t191855-lin'` and
   `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench openclaw t191855-lin 2026.11.3'` (record the version), then
   `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench exec t191855-lin -- useradd -m -s /bin/bash lab'`.
   (The scripts are copied with `tee` as root; they come out root-owned but world-readable, which is all `bash <file>`
   needs.)
2. Script `b1` as lab: `cat /etc/os-release | head -2; node --version; openclaw --version; id`, then the same
   commands as A1 (`setup --baseline` or the fallback, whichever worked on macOS), with
   `--output /home/lab/t191855-out`. Baseline must pass. Write `STATE=` and `WORKSPACE=` from the dry-run plan; then
   `W=<WORKSPACE>/state`.
3. Script `b2root` **as root**: `mkdir -p <W>; chown lab:lab <W>; mkdir -m 700 <W>/foreign; ls -ld <W>/foreign`
   (literal paths; `<W>/foreign` is root-owned 0700). Then script `b2` as lab:
   `stat <W>/foreign/.openclaw-private-update-capture; echo "stat rc=$?"` (expect Permission denied), then the dry-run
   and `backup create --verify --json --output /home/lab/t191855-out`, each followed by its `echo rc=$?`.
4. Control: script `b3root` as root: `rmdir <W>/foreign`; then script `b3` as lab: rerun the `--verify` backup,
   expect success.
5. Keep the bench for Part C only if at least **75 minutes** remain before the hard stop; otherwise go to Finish
   (destroy it there).

Do **not** set up systemd `ProtectHome` or any service confinement: a commenter's systemd variant is a different
trigger, and mixing them would muddy the result.

## Part C (optional, only with ≥ 75 min left): GREEN with PR #194166's built CLI (Linux bench)
The PR's skip logic is platform-neutral, and a root-owned 0700 directory seen by a normal user is "genuine foreign
ownership", so the Linux bench is a fair and much cheaper place to build it than a macOS VM.
1. Script `c0root` **as root**:
   `export DEBIAN_FRONTEND=noninteractive COREPACK_ENABLE_DOWNLOAD_PROMPT=0; command -v git || (apt-get -qq update && apt-get -qq install -y git); corepack enable; echo "corepack rc=$?"; git --version`.
2. Write `c-build.sh` (to be run as lab) on lab-mac and copy it in with the Linux recipe:

   ```
   #!/bin/bash
   set -x
   export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
   mkdir -p /home/lab/pr && cd /home/lab/pr
   git init -q && git remote add origin https://github.com/openclaw/openclaw.git
   git fetch -q --depth 1 origin pull/194166/head && git checkout -q FETCH_HEAD
   git rev-parse HEAD
   pnpm install --frozen-lockfile && pnpm build
   echo "build rc=$?"
   ```
   Expect 30–60 min (package.json at the PR head, **verified**: `pnpm@12.15.0` via corepack, Node `>=24.16.0 <25`;
   the bench has v24.22.3, `bin` is `openclaw.mjs`).
3. Start it as a **long job** on lab-linux (AGENTS.md "Long jobs"). Write this wrapper on lab-mac as `$J/J191855c.sh`:

   ```
   #!/bin/bash
   bench exec t191855-lin -- su - lab -c "bash /home/lab/c-build.sh" > ~/jobs/J191855c.log 2>&1
   echo $? > ~/jobs/J191855c.exit
   ```
   then `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'mkdir -p ~/jobs && cat > ~/jobs/J191855c.sh' < $J/J191855c.sh`,
   check its sha256 on both sides, and
   `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'tmux new -d -s J191855c "bash ~/jobs/J191855c.sh"'`.
   Add the ledger row and arm one watcher (exit file `~/jobs/J191855c.exit` on lab-linux) exactly as AGENTS.md says,
   and check `consecutiveErrors: 0`. End the turn; do not wait in it.
4. When it has exited: copy the log back (`ssh … 'cat ~/jobs/J191855c.log' > $J/c-build.log`). Record the
   `git rev-parse HEAD` line: if it is not `5438a832520be89cde6799215b99a711fc039950`, the PR moved; record the new
   head and continue with it. If `build rc` is not 0, put the last 60 lines of the log in `evidence.txt` and mark C
   `partial`.
5. Script `c1root` as root: `mkdir -m 700 <W>/foreign` again. Script `c1` as lab:
   `node /home/lab/pr/openclaw.mjs --version`, then the dry-run and
   `node /home/lab/pr/openclaw.mjs backup create --verify --json --output /home/lab/t191855-out`, each with its
   `echo rc=$?`. **Expected GREEN:** exit 0, a warning `Skipped unreadable foreign entry: <path>` naming `foreign`
   (text **verified** from the PR's source), and the archive verifies. Record exactly what appears.
6. Negative checks (the PR must still refuse what the user **owns**), script `c2` as lab, each followed by the
   `--verify` backup with the PR CLI and its `echo rc=$?`:
   - **N1, owned dir it cannot search:** `mkdir -m 000 <W>/owned`. Expected: still refused (same EACCES as `foreign`,
     but the owner is lab, so the PR must not skip it). Then `chmod 700 <W>/owned; rmdir <W>/owned`.
   - **N2, owned marker it cannot read:** `mkdir <W>/owned2; printf 'openclaw-private-update-capture-v1\n' > <W>/owned2/.openclaw-private-update-capture; chmod 000 <W>/owned2/.openclaw-private-update-capture`.
     Expected: refused with "…marker is invalid or unreadable; export refused." Then
     `chmod 600 <W>/owned2/.openclaw-private-update-capture; rm -r <W>/owned2`.
7. Delete the lab-linux job files: `ssh … 'rm -f ~/jobs/J191855c.sh ~/jobs/J191855c.log ~/jobs/J191855c.exit'`
   (after you copied the log), and remove the watcher.

## Finish
- `~/worker/jobs/T191855/evidence.txt`: start time and hard stop, every script's captured output in order (each has
  its UTC time and, via `set -x`, its commands), the `STATE=`/`WORKSPACE=` lines, and the results table.
- Keep every per-step script and output file in the job folder.
- Destroy the Linux bench: `ssh -i ~/.ssh/lab_worker <user>@<LAB-HOST> 'bench destroy t191855-lin'`, then
  `… 'bench list'` must show no `t191855-lin`. The Mac bench must already be gone (A5). Record both lists.
- Then the hashes, leaving out the hash file itself and your lease file (<lease-file>):
  `cd ~/worker/jobs/T191855 && find . -maxdepth 1 -type f ! -name evidence.sha256 ! -name <lease-file> | LC_ALL=C sort | xargs shasum -a 256 > evidence.sha256`
- Result (labmail accepts only `passed`, `failed`, `stopped`):
  - `passed` (**reproduced**): RED on shipped 2026.11.3 on macOS (A2 definition above). Part B is reported alongside
    as `reproduced` / `not reproduced` / `not run`, and C as `green` / `not green` / `partial` / `not run`.
  - `failed` (**not reproduced**): on macOS, `stat` of the marker path gives EACCES in some variant, **yet**
    `backup create --verify` succeeds. That is a real result ("cannot reproduce on 2026.11.3, here is exactly what we
    ran"), not your mistake.
  - `stopped` (**blocked**): no variant gave a root-owned unreadable directory, setup or bench failure, or time box.
    Say which.
- The report gives: the macOS version and the bench's `id`; the A2 variant table; the exact refusal text and its
  cause; A3 (2026.11.4) result; U1 versus U2 (phases, capture warning, any permission error, final version) or
  `not run`; the #194160 grep result; Part B outcome; Part C hash, build result, GREEN and N1/N2 outcomes; the
  contents of `evidence.sha256`; anything odd. Mark each claim **verified** (you saw it), **documented**, **inferred**
  or **unknown**. You spotted the block-list XML and the cache detail without being asked; look just as hard here. For
  example: does the walker cross into the mount at all? Does `--dry-run` hit the refusal or only the real run? Does
  the update report name the denied syscall and path? Is the refused path the `.fseventsd` one or something else on
  the volume?
- No personal content: everything here is synthetic; redact any credential that shows up in a report file. Do not
  copy backup archives (`t191855-out`) out of the benches.

Don't message the owner about this ticket; the Maintainer reads the receipt.

