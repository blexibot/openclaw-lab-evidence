// j198830.mjs (macOS guest, node >= 22; no dependencies): helpers for T198830. Talks ONLY to 127.0.0.1.
//   proxy <listen> <upstream> <log.jsonl> <modefile>   recording proxy (127.0.0.1:listen -> 127.0.0.1:upstream)
//   models <base> <out.json> [needle]                  GET /api/v1/models; MODEL/LOADED lines; KEY line for needle
//   load <base> <key> <ctx> <out.json>                  POST /api/v1/models/load (echo_load_config); LOADDIRECT line
//   unloadall <base>                                    unload every loaded instance; UNLOAD line
//   probe <base> <model-or-instance> <alt.txt> <tag>    per-input embeddings; PROBE line (tokens, cosines, truncation;
//                                                       expected token floor from <alt>.expect, written by the controller)
//   pxidx <log.jsonl> <fromLine> <toLine> <tag>         PXIDX line: embedding inputs answered 2xx in that range (index)
//   search <file> <q>                                   SR lines from `openclaw memory search --json`
//   status <file>                                       STATUSJ line from `openclaw memory status --deep --json`
//   cfg <out> <key> <catalog none|N> <baseUrl> <ws>    write the OpenClaw config for one cell
//   pxsum <log.jsonl> <fromLine>                        PX lines: what OpenClaw sent to LM Studio in this cell
// Inputs are synthetic. Vectors are never logged, only their length.
import fs from "node:fs";
import http from "node:http";

const [cmd, ...a] = process.argv.slice(2);
const one = (s, n = 300) => String(s ?? "").replace(/\s+/g, "_").slice(0, n) || "-";

function req(base, method, path, body, timeoutMs = 0) {
  return new Promise((resolve) => {
    const u = new URL(path, base);
    const data = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
    const t0 = Date.now();
    const r = http.request({ host: u.hostname, port: u.port, path: u.pathname + u.search, method,
      headers: data ? { "content-type": "application/json", "content-length": data.length } : {} }, (res) => {
      const parts = [];
      res.on("data", (c) => parts.push(c));
      res.on("end", () => resolve({ status: res.statusCode, text: Buffer.concat(parts).toString("utf8"), ms: Date.now() - t0 }));
    });
    if (timeoutMs) r.setTimeout(timeoutMs, () => r.destroy(new Error("timeout")));
    r.on("error", (e) => resolve({ status: 0, text: "ERROR " + e.message, ms: Date.now() - t0 }));
    if (data) r.write(data);
    r.end();
  });
}
const pj = (t) => { try { return JSON.parse(t); } catch { return undefined; } };

function summarizeReq(path, body) {
  const j = pj(body);
  if (!j) return { raw: body.slice(0, 2000) };
  if (path.includes("/embeddings")) {
    const inp = Array.isArray(j.input) ? j.input : [j.input];
    return { model: j.model, n_inputs: inp.length, input_chars: inp.map((s) => String(s).length),
      input_heads: inp.map((s) => String(s).slice(0, 48)) };
  }
  return j;
}
function summarizeResp(path, text) {
  const j = pj(text);
  if (path.includes("/embeddings") && j && Array.isArray(j.data))
    return { n: j.data.length, dim: j.data[0]?.embedding?.length ?? null, model: j.model, usage: j.usage };
  return j ?? text.slice(0, 8192);
}

async function proxy(listen, upstream, logf, modef) {
  let n = 0;
  const log = (o) => fs.appendFileSync(logf, JSON.stringify(o) + "\n");
  http.createServer((ireq, ires) => {
    const parts = [];
    ireq.on("data", (c) => parts.push(c));
    ireq.on("end", async () => {
      const id = ++n, t = Date.now() / 1000, body = Buffer.concat(parts).toString("utf8");
      let maxfwd = 0;
      try { maxfwd = parseInt(fs.readFileSync(modef, "utf8").trim(), 10) || 0; } catch {}
      const sreq = summarizeReq(ireq.url, body);
      // Capture-only mode (only when the Metal gate is not `matched`). Enforced here, and only here:
      //  (1) a load asking for more than maxfwd tokens is recorded and answered 599 by the lab proxy itself;
      //  (2) an embeddings request is answered 599 unless LM Studio already has an instance of that model loaded at a
      //      context <= maxfwd, so LM Studio cannot JIT-load the model at a context of its own choosing.
      // Both are logged as capture_only. Everything OpenClaw does after a 599 is its reaction to the lab proxy
      // (synthetic-599), not to LM Studio.
      const deny = (why) => {
        const msg = JSON.stringify({ error: `lab proxy capture-only (synthetic-599): ${why}` });
        log({ id, t, method: ireq.method, path: ireq.url, req: sreq, status: 599, ms: 0, forwarded: false, capture_only: why, resp: pj(msg) });
        ires.writeHead(599, { "content-type": "application/json" }); ires.end(msg);
      };
      if (maxfwd > 0 && ireq.url.includes("/models/load") && (pj(body)?.context_length ?? 0) > maxfwd) {
        deny(`load with context_length > ${maxfwd} not forwarded`); return;
      }
      if (maxfwd > 0 && ireq.url.includes("/embeddings")) {
        const want = pj(body)?.model;
        const m = await req(`http://127.0.0.1:${upstream}`, "GET", "/api/v1/models", undefined, 20000);
        const inst = (pj(m.text)?.models ?? []).flatMap((x) => (x.loaded_instances ?? []).map((i) => ({ key: x.key, id: i.id, ctx: Number(i.config?.context_length) })));
        const fit = inst.filter((i) => (i.id === want || i.key === want) && i.ctx > 0 && i.ctx <= maxfwd);
        if (!fit.length) {
          deny(`embeddings for ${want} not forwarded: no instance loaded at context <= ${maxfwd} (loaded: ${inst.map((i) => `${i.id}:${i.ctx}`).join(",") || "none"}; LM Studio could JIT-load)`);
          return;
        }
      }
      const r = await new Promise((resolve) => {
        const t0 = Date.now();
        const f = http.request({ host: "127.0.0.1", port: upstream, path: ireq.url, method: ireq.method,
          headers: { ...ireq.headers, host: `127.0.0.1:${upstream}` } }, (res) => {
          const p2 = [];
          res.on("data", (c) => p2.push(c));
          res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, buf: Buffer.concat(p2), ms: Date.now() - t0 }));
        });
        f.on("error", (e) => resolve({ status: 502, headers: { "content-type": "text/plain" }, buf: Buffer.from("lab proxy upstream error: " + e.message), ms: Date.now() - t0, err: e.message }));
        f.end(body);
      });
      log({ id, t, method: ireq.method, path: ireq.url, req: sreq, status: r.status, ms: r.ms, forwarded: true,
        upstream_error: r.err, resp: summarizeResp(ireq.url, r.buf.toString("utf8")) });
      const h = { ...r.headers }; delete h["transfer-encoding"]; delete h["content-length"]; delete h.connection;
      ires.writeHead(r.status, h); ires.end(r.buf);
    });
  }).listen(listen, "127.0.0.1", () => console.log(`PROXY listening 127.0.0.1:${listen} -> 127.0.0.1:${upstream}`));
}

async function models(base, out, needle) {
  const r = await req(base, "GET", "/api/v1/models", undefined, 20000);
  fs.writeFileSync(out, r.text);
  const j = pj(r.text);
  console.log(`MODELS http=${r.status} n=${j?.models?.length ?? "unparsed"}`);
  let key = "";
  for (const m of j?.models ?? []) {
    const li = (m.loaded_instances ?? []).map((x) => `${x.id}:${x.config?.context_length ?? "?"}`).join(",") || "none";
    console.log(`MODEL key=${one(m.key)} type=${one(m.type)} max_ctx=${m.max_context_length ?? "?"} selected_variant=${one(m.selected_variant)} loaded=${li}`);
    const hay = JSON.stringify([m.key, m.variants, m.selected_variant, m.path, m.display_name]).toLowerCase();
    if (needle && !key && m.type === "embedding" && hay.includes(needle.toLowerCase())) key = m.key;
  }
  if (needle) console.log(`KEY ${key || "NONE"}`);
  const loaded = (j?.models ?? []).flatMap((m) => (m.loaded_instances ?? []).map((x) => `${m.key}|${x.id}|${x.config?.context_length ?? "?"}`));
  console.log(`LOADED n=${loaded.length} ${loaded.join(" ") || "none"}`);
}

async function load(base, key, ctx, out) {
  const r = await req(base, "POST", "/api/v1/models/load", { model: key, context_length: Number(ctx), echo_load_config: true }, 300000);
  fs.writeFileSync(out, JSON.stringify({ status: r.status, ms: r.ms, body: r.text }));
  const j = pj(r.text);
  console.log(`LOADDIRECT req_ctx=${ctx} http=${r.status} status=${one(j?.status)} instance=${one(j?.instance_id)} eff_ctx=${j?.load_config?.context_length ?? "none"} secs=${(r.ms / 1000).toFixed(1)} err=${r.status >= 200 && r.status < 300 ? "-" : one(r.text)}`);
}

async function unloadall(base) {
  const r = await req(base, "GET", "/api/v1/models", undefined, 20000);
  const ids = (pj(r.text)?.models ?? []).flatMap((m) => (m.loaded_instances ?? []).map((x) => x.id));
  for (const id of ids) {
    const u = await req(base, "POST", "/api/v1/models/unload", { instance_id: id }, 120000);
    console.log(`UNLOADED id=${one(id)} http=${u.status}`);
  }
  const r2 = await req(base, "GET", "/api/v1/models", undefined, 20000);
  const left = (pj(r2.text)?.models ?? []).flatMap((m) => m.loaded_instances ?? []).length;
  console.log(`UNLOAD requested=${ids.length} remaining=${left}`);
}

const cos = (x, y) => { let d = 0, a = 0, b = 0; for (let i = 0; i < x.length; i++) { d += x[i] * y[i]; a += x[i] * x[i]; b += y[i] * y[i]; } return d / Math.sqrt(a * b); };
async function probe(base, model, altf, tag) {
  const inputs = fs.readFileSync(altf, "utf8").split("\n");  // B, B-alt, C, C-alt (see c198830.py)
  let expMin = NaN;
  try { expMin = Number(/tokens_min=(\d+)/.exec(fs.readFileSync(altf.replace(/\.txt$/, ".expect"), "utf8"))?.[1]); } catch {}
  const v = [], tk = [], st = [];
  for (const s of inputs) {
    const r = await req(base, "POST", "/v1/embeddings", { model, input: [s] }, 120000);
    const j = pj(r.text);
    st.push(r.status); tk.push(j?.usage?.prompt_tokens ?? "?"); v.push(j?.data?.[0]?.embedding);
    if (!(r.status >= 200 && r.status < 300)) console.log(`PROBE_ERR ${tag} http=${r.status} err=${one(r.text)}`);
  }
  const ok = v.every((x) => Array.isArray(x) && x.length);
  const cB = ok ? cos(v[0], v[1]) : NaN, cC = ok ? cos(v[2], v[3]) : NaN;
  const md = (x, y) => Math.max(...x.map((e, i) => Math.abs(e - y[i])));
  const dB = ok ? md(v[0], v[1]) : NaN, dC = ok ? md(v[2], v[3]) : NaN;
  // B pair: differ only in the sentence at the START (before ~1350 digit tokens). C pair: differ only in the sentence
  // at the END (after them). Four cases:
  //   C same, B differ  -> truncated=yes kind=tail-dropped (the end of a long input was cut off)
  //   B same, C differ  -> truncated=yes kind=head-dropped (the start of a long input was cut off)
  //   both differ       -> truncated=no kind=full ONLY if prompt_tokens of B and C are >= the controller's floor;
  //                        otherwise unclear (vectors differ but the token count does not prove full coverage)
  //   both same         -> unclear
  const tB = typeof tk[0] === "number" ? tk[0] : NaN, tC = typeof tk[2] === "number" ? tk[2] : NaN;
  let tr, kind;
  if (!ok) { tr = "error"; kind = "error"; }
  else if (dB > 1e-5 && dC < 1e-6) { tr = "yes"; kind = "tail-dropped"; }
  else if (dB < 1e-6 && dC > 1e-5) { tr = "yes"; kind = "head-dropped"; }
  else if (dB > 1e-5 && dC > 1e-5) {
    if (!(expMin > 0)) { tr = "unclear"; kind = "no-expected-token-floor"; }
    else if (Number.isNaN(tB) || Number.isNaN(tC)) { tr = "unclear"; kind = "tokens-unreported"; }
    else if (tB >= expMin && tC >= expMin) { tr = "no"; kind = "full"; }
    else { tr = "unclear"; kind = "tokens-below-floor"; }
  } else { tr = "unclear"; kind = "both-pairs-identical"; }
  console.log(`PROBE ${tag} model=${one(model)} http=${st.join(",")} tokens_B=${tk[0]} tokens_Balt=${tk[1]} tokens_C=${tk[2]} tokens_Calt=${tk[3]} tokens_floor=${Number.isNaN(expMin) ? "none" : expMin} cos_B_vs_Balt=${cB.toFixed(6)} cos_C_vs_Calt=${cC.toFixed(6)} maxdiff_B=${dB.toExponential(2)} maxdiff_C=${dC.toExponential(2)} truncated=${tr} kind=${kind}`);
}

function search(file, q) {
  const t = fs.readFileSync(file, "utf8");
  const s = t.indexOf("{");
  const j = s >= 0 ? pj(t.slice(s)) : undefined;
  if (!j) { console.log(`SEARCHJ ${q} parsed=no head=${one(t, 200)}`); return; }
  const res = j.results ?? [];
  console.log(`SEARCHJ ${q} parsed=yes n=${res.length} stale=${j.stale ?? false} warning=${one(j.warning)} ok=${j.ok ?? "-"} error=${one(j.error?.message)}`);
  res.forEach((r, i) => console.log(`SR ${q} rank=${i + 1} path=${one(r.path ?? r.file ?? r.relPath)} score=${typeof r.score === "number" ? r.score.toFixed(4) : one(r.score)}`));
}

function status(file) {
  const t = fs.readFileSync(file, "utf8");
  const s = t.search(/[[{]/);
  const j = s >= 0 ? pj(t.slice(s)) : undefined;
  if (!j) { console.log(`STATUSJ parsed=no head=${one(t, 200)}`); return; }
  const e = Array.isArray(j) ? j[0] : j;
  const st = e?.status ?? e;
  const find = (o, k, d = 0) => { if (!o || typeof o !== "object" || d > 6) return undefined; if (k in o && typeof o[k] !== "object") return o[k]; for (const v of Object.values(o)) { const r = find(v, k, d + 1); if (r !== undefined) return r; } return undefined; };
  console.log(`STATUSJ parsed=yes agent=${one(e?.agentId)} files=${st?.files ?? find(e, "files") ?? "?"} chunks=${st?.chunks ?? find(e, "chunks") ?? "?"} provider=${one(st?.provider ?? find(e, "provider"))} model=${one(st?.model ?? find(e, "model"))} dirty=${st?.dirty ?? "?"} vector_available=${st?.vector?.available ?? st?.vector?.semanticAvailable ?? "?"} error=${one(find(e, "error") ?? find(e, "syncError") ?? find(e, "lastError"))}`);
}

function cfg(out, key, catalog, baseUrl, ws) {
  const models = catalog === "none" ? [] : [{ id: key, name: "Qwen3 Embedding 0.6B", contextTokens: Number(catalog), contextWindow: 32768, input: ["text"] }];
  const c = {
    agents: { defaults: { workspace: ws, skipBootstrap: true } },
    memory: { search: { enabled: true, provider: "lmstudio", model: key, fallback: "none" } },
    models: { providers: { lmstudio: { baseUrl, api: "openai-completions", models } } },
  };
  fs.mkdirSync(out.replace(/\/[^/]+$/, ""), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(c, null, 2) + "\n");
  console.log(`CFG catalog=${catalog} models_entries=${models.length} baseUrl=${baseUrl} key=${key} file=${out}`);
}

function pxsum(logf, from) {
  const rows = fs.existsSync(logf) ? fs.readFileSync(logf, "utf8").split("\n").slice(Number(from)).filter(Boolean).map(pj).filter(Boolean) : [];
  const loads = rows.filter((r) => r.path.includes("/models/load"));
  const embs = rows.filter((r) => r.path.includes("/embeddings"));
  const gets = rows.filter((r) => r.method === "GET");
  const ctxs = loads.map((r) => r.req?.context_length ?? "?");
  const lst = loads.map((r) => `${r.status}/${r.resp?.status ?? "-"}/${r.resp?.load_config?.context_length ?? "-"}/${r.forwarded === false ? "capture-only" : "fwd"}`);
  const firstErr = loads.find((r) => !(r.status >= 200 && r.status < 300));
  console.log(`PX loads=${loads.length} req_ctx=${ctxs.join(",") || "none"} first_req_ctx=${ctxs[0] ?? "none"} load_results=${lst.join(",") || "none"} first_load_http=${loads[0]?.status ?? "none"} first_load_status=${one(loads[0]?.resp?.status)} first_load_instance=${one(loads[0]?.resp?.instance_id)} first_load_secs=${loads[0] ? (loads[0].ms / 1000).toFixed(1) : "-"}`);
  console.log(`PX_LOADERR ${firstErr ? one(JSON.stringify(firstErr.resp), 600) : "none"}`);
  const eModels = [...new Set(embs.map((r) => r.req?.model))];
  const eStatus = embs.map((r) => r.status);
  const firstEErr = embs.find((r) => !(r.status >= 200 && r.status < 300));
  const maxChars = Math.max(0, ...embs.flatMap((r) => r.req?.input_chars ?? []));
  const tok = embs.map((r) => r.resp?.usage?.prompt_tokens ?? "?");
  console.log(`PX embeds=${embs.length} capture_only=${embs.filter((r) => r.capture_only).length} models=${eModels.map((m) => one(m)).join(",") || "none"} http=${eStatus.join(",") || "none"} inputs=${embs.map((r) => r.req?.n_inputs ?? "?").join(",") || "none"} max_input_chars=${maxChars} prompt_tokens=${tok.join(",") || "none"} gets=${gets.length}`);
  console.log(`PX_EMBERR ${firstEErr ? one(JSON.stringify(firstEErr.resp), 600) : "none"}`);
  rows.slice(0, 40).forEach((r) => console.log(`PXROW id=${r.id} ${r.method} ${r.path} status=${r.status} ms=${r.ms} fwd=${r.forwarded} req=${one(JSON.stringify(r.path.includes("/embeddings") ? { model: r.req?.model, n: r.req?.n_inputs, chars: r.req?.input_chars } : r.req), 300)} resp=${one(JSON.stringify(r.path.includes("/embeddings") ? { n: r.resp?.n, dim: r.resp?.dim, usage: r.resp?.usage, err: r.resp?.error } : r.method === "GET" ? "(models list)" : r.resp), 400)}`));
}

function pxidx(logf, from, to, tag) {
  const rows = fs.existsSync(logf) ? fs.readFileSync(logf, "utf8").split("\n").slice(Number(from), Number(to)).filter(Boolean).map(pj).filter(Boolean) : [];
  const embs = rows.filter((r) => r.path.includes("/embeddings"));
  const ok = embs.filter((r) => r.status >= 200 && r.status < 300);
  const sum = (xs) => xs.reduce((s, r) => s + (Number(r.req?.n_inputs) || 0), 0);
  console.log(`PXIDX ${tag} rows=${rows.length} loads=${rows.filter((r) => r.path.includes("/models/load")).length} embeds=${embs.length} inputs_2xx=${sum(ok)} inputs_non2xx=${sum(embs) - sum(ok)} capture_only=${rows.filter((r) => r.capture_only).length}`);
}

const run = { proxy: () => proxy(Number(a[0]), Number(a[1]), a[2], a[3]), models: () => models(a[0], a[1], a[2]),
  load: () => load(a[0], a[1], a[2], a[3]), unloadall: () => unloadall(a[0]), probe: () => probe(a[0], a[1], a[2], a[3]),
  search: () => search(a[0], a[1]), status: () => status(a[0]), cfg: () => cfg(a[0], a[1], a[2], a[3], a[4]),
  pxsum: () => pxsum(a[0], a[1]), pxidx: () => pxidx(a[0], a[1], a[2], a[3]) }[cmd];
if (!run) { console.error("usage: see header"); process.exit(2); }
await run();
