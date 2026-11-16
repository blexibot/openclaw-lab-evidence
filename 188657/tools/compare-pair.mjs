// compare-pair.mjs <cap-dir> [<cap-dir>...]: for the decisive pair (req-002.json = last request of turn 1,
// req-003.json = first request of turn 2) print: equality of every top-level field other than input/messages,
// sha256 (first 16 hex) and index of each runtime-context carrier item, and the raw-byte common prefix of the two
// files as captured by the mock. Read-only; Node >= 22.
import fs from "node:fs"; import path from "node:path"; import crypto from "node:crypto";
const MARKER = "OpenClaw runtime context:";
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex").slice(0, 16);
for (const dir of process.argv.slice(2)) {
  const ra = fs.readFileSync(path.join(dir, "req-002.json")), rb = fs.readFileSync(path.join(dir, "req-003.json"));
  const A = JSON.parse(ra), B = JSON.parse(rb);
  const ia = A.input || A.messages, ib = B.input || B.messages;
  const other = [...new Set([...Object.keys(A), ...Object.keys(B)])].filter((k) => k !== "input" && k !== "messages")
    .map((k) => `${k}:${JSON.stringify(A[k]) === JSON.stringify(B[k]) ? "equal" : "DIFFERENT"}`).join(" ");
  const car = (items) => items.map((x, i) => [i, JSON.stringify(x)]).filter(([, s]) => s.includes(MARKER)).map(([i, s]) => `[${i}] sha=${sha(s)} chars=${s.length}`).join(" ");
  let p = 0; while (p < ra.length && p < rb.length && ra[p] === rb[p]) p++;
  console.log(`${path.basename(dir)}`);
  console.log(`  top-level fields other than input/messages: ${other}`);
  console.log(`  instructions field present: ${"instructions" in A || "instructions" in B ? "yes" : "no"}`);
  console.log(`  items: ${ia.length} -> ${ib.length}`);
  console.log(`  carriers turn-1 last: ${car(ia)} | turn-2 first: ${car(ib)}`);
  console.log(`  raw bytes: ${ra.length} -> ${rb.length}; raw common prefix bytes: ${p}; turn-1 file next bytes: ${JSON.stringify(ra.subarray(p, p + 40).toString())}; turn-2 file next bytes: ${JSON.stringify(rb.subarray(p, p + 40).toString())}`);
}
