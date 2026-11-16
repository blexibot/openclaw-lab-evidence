// cfg.mjs : small config helpers for the #182520 kit (plain JSON openclaw.json only).
//   cfg.mjs stub FILE PORT MANAGED(0|1) NODEBIN KITDIR STUBLOG WORKSPACE   write the Part A config
//   cfg.mjs dump FILE          print the llama-cpp provider, memory and agents sections, secrets redacted
//   cfg.mjs health FILE        print the llama-cpp health URL (localService.healthUrl, else baseUrl + /models)
//   cfg.mjs set FILE PATH JSON set a dotted path (fallback when `openclaw config set` refuses); prints the new value
import fs from "node:fs";
import path from "node:path";

const [mode, file, ...rest] = process.argv.slice(2);
const read = () => JSON.parse(fs.readFileSync(file, "utf8"));
const redact = (v) => JSON.parse(JSON.stringify(v, (k, x) =>
  /token|secret|password|apikey|authorization/i.test(k) && typeof x === "string" ? "<redacted>" : x));

if (mode === "stub") {
  const [port, managed, nodeBin, kitDir, stubLog, ws] = rest;
  const provider = {
    baseUrl: `http://127.0.0.1:${port}/v1`,
    apiKey: "stub-local",
    api: "openai-completions",
    timeoutSeconds: 300,
    models: [{
      id: "slow", name: "Slow stub", reasoning: false, input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 32768, maxTokens: 1024,
    }],
  };
  if (managed === "1") {
    provider.localService = {
      command: nodeBin,
      args: [path.join(kitDir, "slowllm.mjs"), String(port), stubLog],
      healthUrl: `http://127.0.0.1:${port}/v1/models`,
      readyTimeoutMs: 60000,
      idleStopMs: 0,
    };
  }
  const cfg = {
    models: { mode: "merge", providers: { stub: provider } },
    agents: { defaults: { model: { primary: "stub/slow" }, workspace: ws } },
  };
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
  console.log(`CFG wrote ${file} managed=${managed}`);
} else if (mode === "dump") {
  const c = read();
  console.log(JSON.stringify(redact({
    "models.providers.llama-cpp": c?.models?.providers?.["llama-cpp"],
    memory: c?.memory,
    agents: c?.agents,
    plugins: c?.plugins,
  }), null, 2));
} else if (mode === "health") {
  const p = read()?.models?.providers?.["llama-cpp"];
  const ls = p?.localService;
  if (!p || !ls) { console.log("NONE"); process.exit(1); }
  console.log(ls.healthUrl || `${String(p.baseUrl).replace(/\/+$/, "")}/models`);
} else if (mode === "set") {
  const [dotted, json] = rest;
  const c = read();
  const keys = dotted.split(".");
  let o = c;
  for (const k of keys.slice(0, -1)) { if (typeof o[k] !== "object" || o[k] === null) o[k] = {}; o = o[k]; }
  o[keys[keys.length - 1]] = JSON.parse(json);
  fs.writeFileSync(file, JSON.stringify(c, null, 2) + "\n");
  console.log(`CFG set ${dotted}=${JSON.stringify(redact(o[keys[keys.length - 1]]))}`);
} else {
  console.error("usage: see header");
  process.exit(2);
}
