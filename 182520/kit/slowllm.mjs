// slowllm.mjs PORT LOGFILE : a tiny OpenAI-compatible stand-in "model server" for openclaw/openclaw#182520 Part A.
// GET /v1/models -> one model "slow". POST /v1/chat/completions -> waits DELAY seconds (from "DELAY=<n>" in the
// request body, default 5), sending one "." chunk per second when streaming, then "STUB_DONE_<n>".
// Every event is one line in LOGFILE with this server's pid, so a request that starts and never ends shows that the
// server died under it (a SIGKILL leaves no last words). Synthetic content only; no network beyond 127.0.0.1.
import http from "node:http";
import fs from "node:fs";

const port = Number(process.argv[2] || 18555);
const logFile = process.argv[3] || "/tmp/slowllm.log";
let ppid = "?", pgid = "?";
try {
  const stat = fs.readFileSync("/proc/self/stat", "utf8");
  const rest = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
  ppid = rest[1]; pgid = rest[2];
} catch { ppid = String(process.ppid); }
let seq = 0;
const log = (msg) => fs.appendFileSync(logFile, `${new Date().toISOString()} pid=${process.pid} ${msg}\n`);

const server = http.createServer((req, res) => {
  if (req.method === "GET" && /^\/(v1\/)?models\/?$/.test(req.url.split("?")[0])) {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ object: "list", data: [{ id: "slow", object: "model", owned_by: "stub" }] }));
    return;
  }
  if (req.method === "GET" && /^\/health\/?$/.test(req.url)) {
    res.writeHead(200, { "content-type": "application/json" });
    res.end('{"status":"ok"}');
    return;
  }
  if (req.method !== "POST" || !/\/chat\/completions\/?$/.test(req.url.split("?")[0])) {
    res.writeHead(404, { "content-type": "application/json" });
    res.end('{"error":{"message":"not found"}}');
    return;
  }
  let body = "";
  req.on("data", (c) => { body += c; });
  req.on("end", () => {
    const id = ++seq;
    const delays = [...body.matchAll(/DELAY=(\d+)/g)];
    const tags = [...body.matchAll(/TAG=([a-z0-9_-]+)/g)];
    const delay = Math.min(600, delays.length ? Number(delays[delays.length - 1][1]) : 5);
    const tag = tags.length ? tags[tags.length - 1][1] : "none";
    let parsed = {};
    try { parsed = JSON.parse(body); } catch { /* keep {} */ }
    const stream = parsed.stream === true;
    log(`REQ start id=${id} tag=${tag} delay=${delay} stream=${stream} bytes=${body.length}`);
    let finished = false;
    res.on("close", () => { if (!finished) log(`REQ client-closed id=${id} tag=${tag}`); });
    const created = Math.floor(Date.now() / 1000);
    const text = `STUB_DONE_${delay}`;
    const usage = { prompt_tokens: 10, completion_tokens: delay + 1, total_tokens: delay + 11 };
    const chunk = (delta, finish) => `data: ${JSON.stringify({ id: `chatcmpl-${id}`, object: "chat.completion.chunk", created, model: "slow", choices: [{ index: 0, delta, finish_reason: finish }] })}\n\n`;
    if (stream) {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
      res.write(chunk({ role: "assistant", content: "" }, null));
      let n = 0;
      const t = setInterval(() => {
        n += 1;
        if (n < delay) { res.write(chunk({ content: "." }, null)); return; }
        clearInterval(t);
        res.write(chunk({ content: ` ${text}` }, null));
        res.write(chunk({}, "stop"));
        res.write(`data: ${JSON.stringify({ id: `chatcmpl-${id}`, object: "chat.completion.chunk", created, model: "slow", choices: [], usage })}\n\n`);
        res.write("data: [DONE]\n\n");
        finished = true;
        res.end();
        log(`REQ end id=${id} tag=${tag}`);
      }, 1000);
    } else {
      setTimeout(() => {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ id: `chatcmpl-${id}`, object: "chat.completion", created, model: "slow", choices: [{ index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" }], usage }));
        finished = true;
        log(`REQ end id=${id} tag=${tag}`);
      }, delay * 1000);
    }
  });
});
server.listen(port, "127.0.0.1", () => log(`STUB start port=${port} ppid=${ppid} pgid=${pgid}`));
for (const s of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(s, () => { log(`STUB got ${s}`); process.exit(0); });
