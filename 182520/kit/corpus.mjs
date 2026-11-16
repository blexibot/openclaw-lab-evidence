// corpus.mjs DIR NFILES SALT [WORDS] : write NFILES synthetic Markdown notes into DIR (created; old *.md removed).
// Text is pseudo-random words from a fixed made-up vocabulary, seeded by SALT, so every run's content is new
// (no embedding-cache hits) and nothing personal is ever in it. Prints "CORPUS <dir> files=<n> bytes=<b>".
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const [dir, nArg, salt, wArg] = process.argv.slice(2);
const n = Number(nArg), words = Number(wArg || 900);
if (!dir || !(n > 0) || !salt) { console.error("usage: corpus.mjs DIR NFILES SALT [WORDS]"); process.exit(2); }
fs.mkdirSync(dir, { recursive: true });
for (const f of fs.readdirSync(dir)) if (f.endsWith(".md")) fs.rmSync(path.join(dir, f));
const syl = ["ka", "lo", "mi", "ren", "tas", "vo", "qui", "pel", "dor", "sen", "ut", "bra", "zen", "fal", "mor", "ti"];
const vocab = [];
for (let i = 0; i < 400; i++) vocab.push(syl[i % 16] + syl[(i * 7 + 3) % 16] + (i % 3 ? syl[(i * 5 + 1) % 16] : ""));
let bytes = 0;
for (let i = 0; i < n; i++) {
  let seed = crypto.createHash("sha256").update(`${salt}:${i}`).digest().readUInt32LE(0) || 1;
  const rnd = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
  const out = [`# Lab note ${salt} ${i}`, ""];
  let line = [];
  for (let w = 0; w < words; w++) {
    line.push(vocab[(rnd() >>> 16) % vocab.length]);
    if (line.length === 15) { out.push(line.join(" ") + "."); line = []; }
    if (w % 120 === 119) out.push("");
  }
  if (line.length) out.push(line.join(" ") + ".");
  const text = out.join("\n") + "\n";
  bytes += Buffer.byteLength(text);
  fs.writeFileSync(path.join(dir, `note-${String(i).padStart(5, "0")}.md`), text);
}
console.log(`CORPUS ${dir} files=${n} bytes=${bytes}`);
