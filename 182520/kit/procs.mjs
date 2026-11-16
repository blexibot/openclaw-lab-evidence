// procs.mjs REGEX : list processes whose command line matches REGEX (Linux /proc), one line each:
//   pid=<p> ppid=<pp> pgid=<g> chain=,<p>,<pp>,...,1, args=<first 200 chars>
// "chain" is the parent chain up to pid 1, comma-wrapped so a shell can test `*,<pid>,*`. Excludes itself.
import fs from "node:fs";

const re = new RegExp(process.argv[2] || ".");
const info = new Map();
for (const d of fs.readdirSync("/proc")) {
  if (!/^\d+$/.test(d)) continue;
  try {
    const stat = fs.readFileSync(`/proc/${d}/stat`, "utf8");
    const rest = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
    const args = fs.readFileSync(`/proc/${d}/cmdline`, "utf8").split("\0").filter(Boolean).join(" ");
    info.set(Number(d), { ppid: Number(rest[1]), pgid: Number(rest[2]), args });
  } catch { /* process went away */ }
}
for (const [pid, p] of [...info].sort((a, b) => a[0] - b[0])) {
  if (pid === process.pid || !re.test(p.args)) continue;
  const chain = [pid];
  let cur = p.ppid;
  for (let i = 0; i < 64 && cur > 0; i++) {
    chain.push(cur);
    const next = info.get(cur);
    if (!next) break;
    cur = next.ppid;
  }
  console.log(`pid=${pid} ppid=${p.ppid} pgid=${p.pgid} chain=,${chain.join(",")}, args=${p.args.slice(0, 200)}`);
}
