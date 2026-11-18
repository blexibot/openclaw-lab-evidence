#!/usr/bin/env python3
"""Drive `openclaw models auth login --provider sglang --agent main` through a pseudo-terminal (cell c3, #198178).
Python 3 stdlib only. Answers exactly three known prompts and nothing it cannot recognise blindly beyond Enter:
  "... base URL"  -> clears the pre-filled value (backspaces) and types BASE_URL
  "... API key"   -> types the dummy key from $SGLANG_API_KEY (the bench never holds a real token)
  "... model"     -> types MODEL_ID
Any other prompt that waits QUIET seconds without output gets one Enter (accept the default), at most MAX_ENTERS
times; each is logged with the screen text it answered. Hard limit LIMIT seconds, then the child is killed.
Writes a transcript (ANSI stripped) to argv[1] and prints one line: PTY rc=<child rc|killed> answered=<list> enters=<n>;
exits with the child's exit code (137 when killed or unknown). The child gets a 50x400 window.
Usage: BASE_URL=http://127.0.0.1:18178/v1 MODEL_ID=deepseek-v4.1-flash python3 -I pty198178.py <transcript> -- openclaw ...
"""
import fcntl, os, pty, re, select, signal, struct, sys, termios, time

ANSI = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][0-9A-Za-z]")
QUIET, LIMIT, MAX_ENTERS = 12.0, 240.0, 4


def main():
    out = sys.argv[1]
    cmd = sys.argv[sys.argv.index("--") + 1:]
    answers = [("base url", "url"), ("api key", "key"), ("model", "model")]
    done, enters, log = [], 0, open(out, "wb")
    pid, fd = pty.fork()
    if pid == 0:
        # a wide window (50 rows x 400 columns), so a long `models auth activate <provider:setup-uuid>` hint is never
        # wrapped or split by the terminal or a note box (with no size set the app falls back to ~80 columns)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 400, 0, 0))
        os.environ["COLUMNS"], os.environ["LINES"] = "400", "50"
        os.execvp(cmd[0], cmd)
    screen, last_out, t0, rc = b"", time.time(), time.time(), None

    def send(s, why):
        os.write(fd, s.encode() if isinstance(s, str) else s)
        log.write(f"\n[pty198178 sent: {why}]\n".encode()); log.flush()

    while True:
        if time.time() - t0 > LIMIT:
            os.kill(pid, signal.SIGKILL); rc = "killed"; break
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                break
            clean = ANSI.sub(b"", data)
            log.write(clean); log.flush()
            screen = (screen + clean)[-4000:]; last_out = time.time()
            low = screen.lower().decode("utf-8", "replace")
            for needle, kind in answers[len(done):len(done) + 1]:  # strictly in order: url, then key, then model
                if needle not in low:
                    continue
                time.sleep(0.4)
                if kind == "url":
                    send(b"\x7f" * 120, "backspace x120"); time.sleep(0.2)
                    send(os.environ["BASE_URL"] + "\r", "base url")
                elif kind == "key":
                    send(os.environ.get("SGLANG_API_KEY", "lab-dummy-198178") + "\r", "dummy api key")
                else:
                    send(os.environ["MODEL_ID"] + "\r", "model id")
                done.append(kind); screen = b""; last_out = time.time()
                break
        elif time.time() - last_out > QUIET:
            try:
                wpid, status = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                wpid, status = pid, 0
            if wpid:
                rc = os.waitstatus_to_exitcode(status); break
            if enters >= MAX_ENTERS:
                os.kill(pid, signal.SIGKILL); rc = "killed"; break
            tail = screen[-300:].decode("utf-8", "replace").replace("\n", " | ")
            send("\r", f"enter (default) after quiet; screen tail: {tail}")
            enters += 1; last_out = time.time()
    if rc is None:
        try:
            _, status = os.waitpid(pid, 0); rc = os.waitstatus_to_exitcode(status)
        except ChildProcessError:
            rc = "unknown"
    log.close()
    print(f"PTY rc={rc} answered={','.join(done) or 'none'} enters={enters}")
    sys.exit(rc if isinstance(rc, int) and 0 <= rc < 256 else 137)  # the step's rc is the child's (137 = killed/unknown)


if __name__ == "__main__":
    main()
