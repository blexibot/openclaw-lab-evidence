// j194166.mjs <cmd> <arg>: read-only JSON helper for T194166 (macOS guest, Node 24). Never writes anything.
//   plan <file>      backup --dry-run --json output -> STATE=<path> and WORKSPACE=<path> lines
//   scan <file>      any JSON file -> FOUND_REASON unreadable-foreign <path>, FOUND_EXCLUDED <path>, FOUND_STRING ...
//   buildid <npmroot> installed openclaw's dist/build-info.json -> buildId (or "none")
import fs from "node:fs";
import path from "node:path";

const [cmd, arg] = process.argv.slice(2);

function extractJson(text) {
  try {
    return JSON.parse(text);
  } catch {}
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith("{")) continue;
    for (let j = lines.length; j > i; j--) {
      try {
        return JSON.parse(lines.slice(i, j).join("\n"));
      } catch {}
    }
  }
  return null;
}

function readJson(file) {
  try {
    return extractJson(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

if (cmd === "plan") {
  const o = readJson(arg);
  if (!o) {
    console.log("PLAN_PARSE=failed");
    process.exit(0);
  }
  const all = [...(o.assets ?? []), ...(o.skipped ?? [])];
  const state = all.find((a) => a && a.kind === "state");
  const ws = all.find((a) => a && a.kind === "workspace");
  console.log(`PLAN_PARSE=ok`);
  if (state?.sourcePath) console.log(`STATE=${state.sourcePath}`);
  if (ws?.sourcePath) console.log(`WORKSPACE=${ws.sourcePath}`);
} else if (cmd === "scan") {
  const o = readJson(arg);
  if (!o) {
    console.log("SCAN_PARSE=failed");
    process.exit(0);
  }
  console.log("SCAN_PARSE=ok");
  let strings = 0;
  const walk = (v, key) => {
    if (Array.isArray(v)) {
      if (key === "excludedRoots") for (const e of v) console.log(`FOUND_EXCLUDED ${String(e)}`);
      for (const e of v) walk(e, key);
    } else if (v && typeof v === "object") {
      if (v.reason === "unreadable-foreign") {
        console.log(`FOUND_REASON unreadable-foreign ${v.sourcePath ?? v.displayPath ?? "?"}`);
      }
      for (const [k, e] of Object.entries(v)) walk(e, k);
    } else if (typeof v === "string" && v.includes(".fseventsd") && strings < 20) {
      strings++;
      console.log(`FOUND_STRING ${key} ${v.replace(/\s+/g, " ").slice(0, 300)}`);
    }
  };
  walk(o, "");
} else if (cmd === "buildid") {
  const o = readJson(path.join(arg ?? "", "openclaw", "dist", "build-info.json"));
  console.log(o?.buildId ? String(o.buildId).replace(/\s+/g, "_") : "none");
} else {
  console.log("usage: j194166.mjs plan|scan <file> | buildid <npmroot>");
  process.exit(2);
}
