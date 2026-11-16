// analyze.mjs <CAP_DIR>: checks the captured requests of one run for openclaw/openclaw#188657.
// Turn boundaries come from the driver's /__mark lines (t1, t2, ...). Prints per-request facts, then a VERDICT line.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const dir = process.argv[2];
const MARKER = "OpenClaw runtime context:";
const END = "End OpenClaw runtime context.";
const h = (s) => crypto.createHash("sha256").update(s).digest("hex").slice(0, 12);
const lines = fs.readFileSync(path.join(dir, "index.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
let turn = null;
const reqs = [];
for (const l of lines) {
  if (l.mark) { turn = l.mark; continue; }
  if (l.method !== "POST" || !l.file || (l.route !== "responses" && l.route !== "chat")) continue;
  const raw = fs.readFileSync(path.join(dir, l.file), "utf8");
  const body = JSON.parse(raw);
  const items = l.route === "responses" ? body.input || [] : body.messages || [];
  const ser = items.map((it) => JSON.stringify(it));
  const carriers = ser.filter((s) => s.includes(MARKER));
  reqs.push({ turn, file: l.file, route: l.route, raw, body, items, ser, carriers,
    nMarker: raw.split(MARKER).length - 1, nEnd: raw.split(END).length - 1 });
}
const count = (a, b) => { let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++; return i; };
const label = (it) => {
  if (!it) return "(none)";
  const kind = it.type || "message", role = it.role ? `/${it.role}` : "";
  let t = typeof it.content === "string" ? it.content : Array.isArray(it.content) ? it.content.map((c) => c.text ?? "").join("") : it.output ?? it.arguments ?? "";
  return `${kind}${role} "${String(t).replace(/\s+/g, " ").slice(0, 70)}"`;
};
console.log(`run dir: ${dir}`);
console.log(`requests: ${reqs.length}`);
for (const r of reqs) {
  console.log(`- ${r.file} turn=${r.turn} route=${r.route} items=${r.items.length} carriers(items)=${r.carriers.length} ` +
    `marker_count=${r.nMarker} end_count=${r.nEnd} prev_response_id=${r.body.previous_response_id ?? "-"} store=${r.body.store ?? "-"} ` +
    `prompt_cache_key=${r.body.prompt_cache_key ? "set" : "-"} instructions_sha=${r.body.instructions ? h(r.body.instructions) : "-"} tools_sha=${h(JSON.stringify(r.body.tools || []))}`);
}
const t1 = reqs.filter((r) => r.turn === "t1"), t2 = reqs.filter((r) => r.turn === "t2");
if (!t1.length || !t2.length) { console.log("VERDICT incomplete: need requests in turns t1 and t2"); process.exit(2); }
const pair = (a, b, name) => {
  const c = count(a.ser, b.ser), isPrefix = c === a.ser.length;
  const rawA = JSON.stringify(a.items), rawB = JSON.stringify(b.items);
  const charPrefix = count(rawA.slice(0, -1), rawB);
  console.log(`\n[${name}] ${a.file} -> ${b.file}`);
  console.log(`  items: ${a.ser.length} -> ${b.ser.length}; identical leading items: ${c}; earlier list is a prefix of later: ${isPrefix ? "YES" : "NO"}`);
  console.log(`  serialized input chars: ${rawA.length} -> ${rawB.length}; common prefix chars: ${charPrefix}`);
  if (!isPrefix) { console.log(`  first difference at item ${c}:`); console.log(`    before: ${label(a.items[c])}`); console.log(`    after:  ${label(b.items[c])}`); }
  console.log(`  instructions equal: ${(a.body.instructions ?? "") === (b.body.instructions ?? "") ? "YES" : "NO"}; tools equal: ${JSON.stringify(a.body.tools || []) === JSON.stringify(b.body.tools || []) ? "YES" : "NO"}`);
  return isPrefix;
};
if (t1.length > 1) pair(t1[0], t1[t1.length - 1], "within turn 1 (control)");
const a = t1[t1.length - 1], b = t2[0];
const prefix = pair(a, b, "turn 1 last -> turn 2 first (the bug)");
// Carrier text can be identical across turns, so check by position: each turn-1 carrier must still sit at the same
// index, byte-identical, in turn 2's first request, and turn 2 must add its own on top.
const pos = (r) => r.ser.map((s, i) => (s.includes(MARKER) ? i : -1)).filter((i) => i >= 0);
const pa = pos(a), pb = pos(b);
const retained = pa.every((i) => b.ser[i] === a.ser[i]) && pb.length >= pa.length + 1;
console.log(`  carrier item positions: turn 1 last [${pa.join(",")}] of ${a.ser.length}; turn 2 first [${pb.join(",")}] of ${b.ser.length}`);
console.log(`  turn-1 carrier kept in place and turn 2 adds its own: ${retained ? "YES" : "NO"}`);
const toolCalled = t1.some((r) => r.items.some((it) => it.type === "function_call_output" || it.role === "tool"));
console.log(`\nVERDICT route=${b.route} tool_call_in_turn1=${toolCalled ? "yes" : "no"} carrier_retained=${retained ? "yes" : "no"} append_only_prefix=${prefix ? "yes" : "no"} prev_response_id_used=${reqs.some((r) => r.body.previous_response_id) ? "yes" : "no"}`);
