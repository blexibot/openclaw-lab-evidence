// mock.mjs: capture-and-mock server for openclaw/openclaw#188657 (lab ticket LM188657). Node >= 22, no deps.
// Serves POST /v1/responses (OpenAI Responses, SSE or JSON) and POST /v1/chat/completions (control route).
// Every request body is saved byte-for-byte as $CAP_DIR/req-NNN.json and indexed in $CAP_DIR/index.jsonl.
// GET /__mark?label=X writes a marker line to the index (the driver marks turn boundaries).
// Scripted replies (no model): if the newest real user message contains READFILE and no tool result follows it,
// answer with a function call to the read tool (path fixture.txt); after a tool result, answer text; else "ok".
// Optional proxy mode: UPSTREAM=http://host:port forwards POSTs there instead (captures still written).
import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const PORT = Number(process.env.PORT || 8099);
const CAP = process.env.CAP_DIR || "./cap";
const UPSTREAM = process.env.UPSTREAM || "";
const MARKER = "OpenClaw runtime context:";
fs.mkdirSync(CAP, { recursive: true });
let n = 0, seq = 0;
const idx = (o) => fs.appendFileSync(path.join(CAP, "index.jsonl"), JSON.stringify({ t: new Date().toISOString(), ...o }) + "\n");
const rid = (p) => `${p}_${Date.now().toString(36)}${(++seq).toString(36)}`;

function textOf(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) return content.map((c) => (typeof c === "string" ? c : c?.text ?? "")).join("");
  return "";
}
// items: Responses input[] or chat messages[]; returns "tool" | "final" | "text"
function decide(items) {
  const last = items[items.length - 1] || {};
  if (last.type === "function_call_output" || last.role === "tool") return "final";
  for (let i = items.length - 1; i >= 0; i--) {
    const it = items[i];
    if (it.type === "function_call_output" || it.role === "tool") return "final";
    if (it.role !== "user") continue;
    const t = textOf(it.content).trim();
    if (t.startsWith(MARKER)) continue;
    return t.includes("READFILE") ? "tool" : "text";
  }
  return "text";
}
function pickTool(tools) {
  const norm = (tools || []).map((t) => ({ name: t.name ?? t.function?.name, params: t.parameters ?? t.function?.parameters ?? {} }));
  const tool = norm.find((t) => t.name === "read") || norm.find((t) => /read/i.test(t.name || ""));
  if (!tool) return null;
  const props = Object.keys(tool.params.properties || {});
  const key = props.includes("path") ? "path" : props.includes("file_path") ? "file_path" : (tool.params.required || [])[0] || "path";
  return { name: tool.name, args: JSON.stringify({ [key]: "fixture.txt" }) };
}
const usage = { input_tokens: 100, input_tokens_details: { cached_tokens: 0 }, output_tokens: 10, output_tokens_details: { reasoning_tokens: 0 }, total_tokens: 110 };

function responsesReply(body, res, action) {
  const id = rid("resp"), model = body.model || "test-model";
  let item;
  if (action === "tool") {
    const t = pickTool(body.tools);
    if (!t) action = "text";
    else item = { id: rid("fc"), type: "function_call", status: "completed", call_id: rid("call"), name: t.name, arguments: t.args };
  }
  const text = action === "final" ? "The fixture says: lab fixture line one." : action === "text" ? "ok" : "";
  if (!item) item = { id: rid("msg"), type: "message", status: "completed", role: "assistant", content: [{ type: "output_text", text, annotations: [] }] };
  const done = { id, object: "response", created_at: Math.floor(Date.now() / 1000), status: "completed", model, output: [item], usage };
  if (!body.stream) { res.writeHead(200, { "content-type": "application/json" }); return res.end(JSON.stringify(done)); }
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
  let s = 0;
  const ev = (type, o) => res.write(`event: ${type}\ndata: ${JSON.stringify({ type, sequence_number: s++, ...o })}\n\n`);
  const start = { ...done, status: "in_progress", output: [], usage: null };
  ev("response.created", { response: start });
  ev("response.in_progress", { response: start });
  if (item.type === "function_call") {
    ev("response.output_item.added", { output_index: 0, item: { ...item, status: "in_progress", arguments: "" } });
    ev("response.function_call_arguments.delta", { item_id: item.id, output_index: 0, delta: item.arguments });
    ev("response.function_call_arguments.done", { item_id: item.id, output_index: 0, name: item.name, arguments: item.arguments });
  } else {
    ev("response.output_item.added", { output_index: 0, item: { ...item, status: "in_progress", content: [] } });
    ev("response.content_part.added", { item_id: item.id, output_index: 0, content_index: 0, part: { type: "output_text", text: "", annotations: [] } });
    ev("response.output_text.delta", { item_id: item.id, output_index: 0, content_index: 0, delta: text });
    ev("response.output_text.done", { item_id: item.id, output_index: 0, content_index: 0, text });
    ev("response.content_part.done", { item_id: item.id, output_index: 0, content_index: 0, part: item.content[0] });
  }
  ev("response.output_item.done", { output_index: 0, item });
  ev("response.completed", { response: done });
  res.end();
}

function chatReply(body, res, action) {
  const id = rid("chatcmpl"), model = body.model || "test-model", created = Math.floor(Date.now() / 1000);
  let call = null;
  if (action === "tool") { const t = pickTool(body.tools); if (t) call = { id: rid("call"), type: "function", function: { name: t.name, arguments: t.args } }; else action = "text"; }
  const text = action === "final" ? "The fixture says: lab fixture line one." : "ok";
  const u = { prompt_tokens: 100, completion_tokens: 10, total_tokens: 110, prompt_tokens_details: { cached_tokens: 0 } };
  const finish = call ? "tool_calls" : "stop";
  if (!body.stream) {
    const msg = call ? { role: "assistant", content: null, tool_calls: [call] } : { role: "assistant", content: text };
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ id, object: "chat.completion", created, model, choices: [{ index: 0, message: msg, finish_reason: finish }], usage: u }));
  }
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
  const ch = (delta, fr = null, extra = {}) => res.write(`data: ${JSON.stringify({ id, object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta, finish_reason: fr }], ...extra })}\n\n`);
  ch({ role: "assistant", content: "" });
  if (call) ch({ tool_calls: [{ index: 0, id: call.id, type: "function", function: { name: call.function.name, arguments: call.function.arguments } }] });
  else ch({ content: text });
  ch({}, finish);
  res.write(`data: ${JSON.stringify({ id, object: "chat.completion.chunk", created, model, choices: [], usage: u })}\n\n`);
  res.end("data: [DONE]\n\n");
}

function proxy(req, raw, res, file) {
  const u = new URL(req.url, UPSTREAM);
  const headers = { "content-type": req.headers["content-type"] || "application/json", authorization: req.headers.authorization || "Bearer dummy", "content-length": raw.length };
  const up = http.request(u, { method: req.method, headers }, (ur) => {
    res.writeHead(ur.statusCode, { "content-type": ur.headers["content-type"] || "application/json" });
    const out = fs.createWriteStream(file.replace(/\.json$/, ".reply.txt"));
    ur.on("data", (d) => { out.write(d); res.write(d); });
    ur.on("end", () => { out.end(); res.end(); idx({ upstream_status: ur.statusCode, file: path.basename(file) }); });
  });
  up.on("error", (e) => { idx({ upstream_error: String(e) }); res.writeHead(502); res.end(String(e)); });
  up.end(raw);
}

http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (d) => chunks.push(d));
  req.on("end", () => {
    const raw = Buffer.concat(chunks);
    const url = new URL(req.url, "http://x");
    if (req.method === "GET" && url.pathname === "/__mark") { idx({ mark: url.searchParams.get("label") }); res.writeHead(200); return res.end("marked\n"); }
    if (req.method === "GET" && url.pathname.endsWith("/models")) {
      idx({ method: "GET", path: url.pathname });
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ object: "list", data: [{ id: "test-model", object: "model", owned_by: "lab" }] }));
    }
    if (req.method !== "POST") { idx({ method: req.method, path: url.pathname, unhandled: true, upgrade: req.headers.upgrade || null }); res.writeHead(404); return res.end(); }
    const file = path.join(CAP, `req-${String(++n).padStart(3, "0")}.json`);
    fs.writeFileSync(file, raw);
    let body = {};
    try { body = JSON.parse(raw.toString("utf8")); } catch { idx({ path: url.pathname, file: path.basename(file), parse_error: true }); res.writeHead(400); return res.end(); }
    const route = url.pathname.endsWith("/responses") ? "responses" : url.pathname.endsWith("/chat/completions") ? "chat" : "other";
    const items = route === "responses" ? (Array.isArray(body.input) ? body.input : []) : (body.messages || []);
    const action = decide(items);
    idx({ method: "POST", path: url.pathname, route, file: path.basename(file), bytes: raw.length, stream: !!body.stream, action: UPSTREAM ? "proxy" : action, tool_names: (body.tools || []).map((t) => t.name ?? t.function?.name) });
    if (UPSTREAM) return proxy(req, raw, res, file);
    if (route === "responses") return responsesReply(body, res, action);
    if (route === "chat") return chatReply(body, res, action);
    res.writeHead(404); res.end();
  });
}).listen(PORT, "127.0.0.1", () => console.log(`mock on 127.0.0.1:${PORT} cap=${CAP}${UPSTREAM ? " upstream=" + UPSTREAM : ""}`));
