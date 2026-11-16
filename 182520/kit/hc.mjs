// hc.mjs URL [WAIT_SECONDS] : poll URL every 0.5 s until it answers HTTP 200 or the wait runs out.
// Prints "HC READY <url> after <s>s" (exit 0) or "HC NOTREADY <url> after <s>s last=<status|error>" (exit 1).
// WAIT_SECONDS 0 means a single probe.
const url = process.argv[2];
const wait = Number(process.argv[3] || 0);
const t0 = Date.now();
let last = "none";
for (;;) {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(2000) });
    last = String(r.status);
    await r.body?.cancel?.();
    if (r.status === 200) {
      console.log(`HC READY ${url} after ${((Date.now() - t0) / 1000).toFixed(1)}s`);
      process.exit(0);
    }
  } catch (e) {
    last = (e && (e.cause?.code || e.code || e.name)) || "error";
  }
  if ((Date.now() - t0) / 1000 >= wait) break;
  await new Promise((r) => setTimeout(r, 500));
}
console.log(`HC NOTREADY ${url} after ${((Date.now() - t0) / 1000).toFixed(1)}s last=${last}`);
process.exit(1);
