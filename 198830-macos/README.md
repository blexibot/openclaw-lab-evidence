# Evidence packet: openclaw/openclaw#198830 on macOS (LM Studio embedding preload context)

Status: **draft, not yet reviewed by the human publisher, not posted.** Synthetic fixtures only, on a disposable macOS
VM (user `admin`; destroyed after the run: `MAC_DESTROY rc=0`, `NO_LEFTOVER t198830-mac` in `raw/verdicts.txt`).
Publish this folder only as a fresh file copy, never by pushing the lab's own repository.

**Custody and redactions.** The files in `raw/` were fetched from the lab job folder `T198830r4` on 2026-11-17 with a
streamed tar and checked against the job's private `evidence.sha256`. All 72 files under `raw/` matched it before
editing. The 184 fetched files listed there all matched; the 9 listed files not fetched (the kit tarball, the
worker's report, and the seven guest-evidence tarballs whose contents are the extracted `raw/guest/ev/` files) were
not checked. Six files were edited before publishing, so their hashes differ from the lab's:
- `raw/verdicts.txt`, line 1: the `kit_d=` value (sha256 of the unredacted driver script) → `<REDACTED-UNREDACTED-KIT-HASH>`.
  That hash would let a guess at the redacted names below be confirmed.
- `kit/d198830.sh`, `kit/h198830.sh`: lab host name → `<LAB-HOST>`, lab account → `<LAB-USER>` (header comment).
- `kit/c198830.py`, `kit/s198830.sh`, `kit/w198830.sh`: lab host name → `<LAB-HOST>` (comment).
`kit/j198830.mjs` and `kit/m198830.sh` are byte-identical to the lab's copies. The kit tarball as run, the lab's hash
list and the worker's own notes are not included, because they would reveal or confirm the redacted values. Nothing in
`raw/` names a lab machine, account, address or key. The only user path is the guest's `/Users/admin`. The VM host's
hardware model and macOS version are in `raw/sup.log`.

## Summary

| Field | Value |
|---|---|
| Issue | openclaw/openclaw#198830 |
| Run ID | T198830r4 (one disposable macOS guest; the supervisor qualification run is not in this packet) |
| UTC time | 2026-11-17T10:54:51Z – 11:02:29Z (`raw/verdicts.txt`) |
| OpenClaw | `OpenClaw 2026.11.3 (847611d)` (preinstalled on the guest image) and `OpenClaw 2026.11.4 (d843d6a)` (`npm install -g`, `raw/guest/ev/c4.install.txt`). `INTEGRITY` lines in `raw/out/m-c*.txt`: npm `dist.integrity` and `dist.shasum` match the values pinned in `kit/m198830.sh` (`OC_113_*`, `OC_114_*`), and the installed `models.fetch-*.mjs` and `memory-embedding-adapter-*.mjs` files match their pinned sha256 |
| Guest | Tart VM `VirtualMac2,1`, macOS 26.6.2 (25G83) arm64, 4 vCPU, 16 GiB (`memsize=17179869184`), Node v24.22.3, npm 11.19.1 (`raw/out/m-info.txt`). The clone was raised from 8192 MB to 16384 MB with `tart set` (`VMCONFIG` lines in `raw/verdicts.txt`) |
| VM host | Apple Silicon `Mac18,5`, 32 GiB, macOS 27.0 (`raw/sup.log`) |
| LM Studio | 0.4.28+2 from the official DMG (`bytes=572548100` matched; sha256 recorded), app route, `lms` from the app. Runtime `llama.cpp-mac-arm64-apple-metal-advsimd@2.73.0` selected (`raw/out/m-lmsinst.txt`, `raw/out/m-lmssetup.txt`) |
| Model | Qwen3-Embedding-0.6B Q8_0 GGUF, `bytes=639150592`, sha256 `06507c7b…49c3e439` matched the pin; key `text-embedding-qwen3-embedding-0.6b`, `type=embedding`, `max_ctx=32768` (`raw/out/m-model.txt`, `raw/guest/ev/models-0.json`) |
| Route | OpenClaw → in-guest recording proxy `127.0.0.1:1235` → LM Studio `127.0.0.1:1234`, all on the guest's loopback. OpenClaw's `baseUrl` points at the proxy (`raw/guest/ev/c*.config.json`) |
| Proxy | `j198830.mjs proxy`, **capture-only**: a load with `context_length > 2048` is recorded and answered `599` by the proxy, never forwarded; embeddings with no instance loaded at ≤ 2048 are answered `599` too. Everything else is forwarded. Capture: `raw/guest/ev/proxy.jsonl` |
| Why capture-only | The kit forwards large loads only when the Metal budget matches a 16 GB host. Here `METALGATE metal=unknown why=no-model-buffer-line` (`raw/out/m-p1024.txt`): no model-buffer or `recommendedMaxWorkingSetSize` line in the runtime log of a 1024 load, so the guest's Metal budget (through the VM's virtual GPU; inferred from the `VirtualMac2,1` model, not shown in a raw file) could not be read |
| Command per cell | `openclaw memory reset --yes`, `openclaw memory index --force --verbose`, `openclaw memory status --deep --json`, `openclaw memory search --query <paraphrase> --max-results 6 --min-score 0 --json` ×4, then `lms ps` (raw files `raw/guest/ev/c<n>.*`) |
| Cells (run order) | c2 (2026.11.3, `contextTokens: 1024`), c1 (2026.11.3, no entry), c4 (2026.11.4, 1024), c5 (2026.11.4, 2048), c3 (2026.11.4, no entry). Each cell has its own OpenClaw home; LM Studio had nothing loaded at each cell's start (`PRE UNLOAD … remaining=0`) |
| Corpus | 8 synthetic markdown files, 12 chunks expected (`raw/corpus/`). `a` is prose; `d` is short numeric inventory sentences (`Shelf N in aisle M holds K cartons…`) with its target sentence last; `f1`–`f4` are fillers of the same numeric kind; `b` has a sentence then ~1350 digits; `c` has ~1350 digits then a sentence. Four paraphrase queries A–D, one per file (`raw/corpus/queries.tsv`) |

**Narrow assertions and outcomes.** Same guest, LM Studio, model and corpus in every cell; the only config difference
between the "no entry" and "1024" cells is the `models.providers.lmstudio.models` entry (`raw/guest/ev/c1.config.json`
vs `c2.config.json`; c1 = c3 and c2 = c4 byte for byte).
- **q1, the request: `reproduced` on 2026.11.3 and 2026.11.4.** With no catalog entry, the first
  `POST /api/v1/models/load` OpenClaw sent was `{"model":"text-embedding-qwen3-embedding-0.6b","context_length":32768}`
  (proxy ids 36 in c1, 145 in c3). It sent 15 such loads per cell, all 32768. With the entry
  `contextTokens: 1024, contextWindow: 32768`, its one load was `"context_length":1024` (ids 3 in c2, 79 in c4),
  answered `200 loaded`; `lms ps` then showed `CONTEXT 1024`.
- **q2, the allocation / out-of-memory: `blocked` (environment not matched).** No 32768 load reached LM Studio
  (capture-only), and the guest's Metal budget was unknown. This run says nothing for or against the reported
  allocation failure. A CPU or VM result would not be a negative of the Metal case. Everything OpenClaw did after a
  `599` in c1/c3 (`index rc=1`, warmup warnings, retries) is its reaction to the lab proxy, not product behaviour.
- **q3, the 1024 control: completes.** c2 and c4: index `rc=0`, `Memory index updated (main): 8 files indexed.`;
  status `files 8`, `chunks 12`, vector index `complete`; 12/12 embedding inputs answered 2xx; queries A and D
  rank their own file first. **The kit's verdict lines say `control failed` for c2 and c4: that label is a
  harness parse failure**, not a product result. Each raw guest file is a `+ openclaw … [timestamp]` echo line, the
  JSON, then non-JSON trailing lines (`[state/agent-db] agent database clean-close receipt: written`, `rc=0`). The kit's
  `search()` slices from the first `{` (the start of the JSON) and `status()` from the first `[` or `{` (the echo line's
  `[timestamp]`); both then hand the rest, trailing lines included, to a whole-string JSON parse, which fails. So every
  `STATUSJ`/`SEARCHJ` line says `parsed=no` (`raw/out/m-c2.txt`) and the fields come out empty
  (`files=/8 chunks=/12 A=none …`). The outcomes here are read from the raw files by decoding the first JSON value after
  the echo line (a raw/streaming decode that ignores the trailing lines).
- **Truncation at 1024: observed.** In c2 and c4, during `openclaw memory index`, LM Studio's runtime log has two
  `[WARNING] Number of tokens in input string (1367|1369) exceeds model context length (1024). Truncating to 1024
  tokens.` lines (c2 10:58:35Z and 10:58:38Z, `c2.rt:118` and `:134`, index started 10:58:32Z; c4 11:00:13Z and
  11:00:15Z, `c4.rt:84` and `:134`, index started 11:00:10Z), and the index still reports success. A plain
  `grep -c 'Truncating to 1024'` gives 18 per file, not 2: each `.rt` file has a short un-timestamped excerpt at the top
  (lines 13–37), then the timestamped log, which is repeated once (c2 lines 375–630 repeat 78–333; c4 likewise), and
  each cell also ran an in-cell kit probe after the searches (the four warnings at 10:59:02–09 in c2 and 11:00:42–49 in
  c4). Only the two timestamped warnings inside the index window belong to the index. In-cell probe results
  (`PROBE insitu-c<n>` in `raw/out/m-c<n>.txt`): c2 and c4 `cos_C_vs_Calt=1.000000`, `cos_B_vs_Balt=0.747740`; c5
  `cos_C_vs_Calt=0.377749`, `cos_B_vs_Balt=0.433757`. In a direct probe against a 1024 instance (`raw/out/m-p1024.txt`,
  `raw/guest/ev/p1024.rt`), two inputs identical for their first ~1350 digit tokens and different only after them
  returned identical vectors (`cos_C_vs_Calt=1.000000`, `maxdiff_C=0`), with the same warning for 1367–1369-token
  inputs; the pair differing only at the start differed (`cos_B_vs_Balt=0.747740`). Query C, whose sentence sits
  after the digits in file `c`, did not rank `c` first at 1024 (c2, c4) and did at 2048 (c5, one run).

**Not covered by this packet (stated, not hidden).**
- The out-of-memory itself (q2), on any build: blocked, above. The reporter's host is bare-metal macOS 27.2.1 with
  16 GB; ours is a 16 GiB macOS 26.6.2 Tart VM (`VirtualMac2,1`; Metal through the VM's virtual GPU, inferred).
- The reporter's working setup also preloaded on CPU (`lms load … --gpu off --context-length 1024`) and then reused
  that instance. We did not preload; OpenClaw's own load with `contextTokens: 1024` went to LM Studio's default device.
  Instance reuse was not tested.
- The 64,000 fallback is source-supported only (issue text; the bot review cites `models.fetch.ts`). We observed only
  its clamped value, 32768, for a model whose advertised maximum is 32768.
- Which index inputs were truncated is **inferred**: the log does not tie each warning to an input, but files `b` and
  `c` (1425/1428 characters, mostly digits) are the only digit-runs of that size. Other inputs are longer in
  characters (the `d` chunks are 1576–1583 characters, `proxy.jsonl` id 11) but are short numeric inventory sentences,
  not digit runs; no per-input token counts were observed (`prompt_tokens: 0` on every call).
- Query B also missed at 1024 (file `b` not in the 6 returned results) and hit at 2048, although B's sentence is at
  the start of `b` and is inside the first 1024 tokens. At 1024 neither `b` nor `c` appears in any of the four
  queries' 6 results; at 2048 both appear in all four. The cause of the B miss is **not established**: `b`'s chunk was
  probably truncated too (assertion 13, inferred), and truncation changes the vector even when the dropped part is the
  tail (assertion 14), so truncation is not ruled out. (The worker's own re-read note said B's sentence comes after
  the digits; it does not, see `raw/corpus/ws-full/memory/`.)
- At 2048 (c5) both probe pairs differ and no truncation warning appears in `raw/guest/ev/c5.rt`, but LM Studio
  returned `usage.prompt_tokens: 0` on every embeddings answer, so full coverage at 2048 is not certified (kit:
  `truncated=unclear kind=tokens-below-floor`). Token counts come only from llama.cpp's warnings.
- llama.cpp's own `n_ctx`/`n_ubatch` lines do not appear at this log level (`RTSUM … n_ctx=none`). The effective
  context is from `GET /api/v1/models` and `lms ps`.
- One attempt per cell, fixed order, synthetic corpus, 0.6B model: counts, not rates; not a search-quality benchmark.
- llama.cpp warned on every embedding that `At least one last token in strings embedded is not SEP` and that
  `tokenizer.ggml.add_eos_token` should be true (63 lines each in `c2.rt`, `c4.rt`, `c5.rt`; 12 in `p1024.rt`). So the
  inputs were embedded without an EOS token, which this model's pooling expects. The warning is identical in every
  cell, so it does not bear on q1 or q2, but the retrieval results are not a measure of the model as intended.
- `raw/verdicts.txt` logs the sha256 of the seven guest-evidence tarballs (`PACK`/`PULL … guest-ev-*.tgz`). Those
  tarballs are not included; they hold only the guest `ev/` folder, whose extracted files are `raw/guest/ev/`.
- No source change, candidate build or new default was tested.

## Cells

| Cell | OpenClaw | Catalog entry | First load request (proxy) | Load result | Index | Status files/chunks | Top-1 A / B / C / D |
|---|---|---|---|---|---|---|---|
| c1 | 2026.11.3 | none | `context_length: 32768` (×15) | `599` from the lab proxy, not forwarded | rc=1 `[synthetic-599]` | 0 / 0 | not run |
| c3 | 2026.11.4 | none | `context_length: 32768` (×15) | `599` from the lab proxy, not forwarded | rc=1 `[synthetic-599]` | 0 / 0 | not run |
| c2 | 2026.11.3 | `contextTokens: 1024` | `context_length: 1024` (×1) | `200 loaded`, `lms ps` CONTEXT 1024 | rc=0, 8 files | 8 / 12 | a / a / a / d |
| c4 | 2026.11.4 | `contextTokens: 1024` | `context_length: 1024` (×1) | `200 loaded`, `lms ps` CONTEXT 1024 | rc=0, 8 files | 8 / 12 | a / a / a / d |
| c5 | 2026.11.4 | `contextTokens: 2048` | `context_length: 2048` (×1) | `200 loaded`, `lms ps` CONTEXT 2048 | rc=0, 8 files | 8 / 12 | a / b / c / d |

Expected top-1: A→a, B→b, C→c, D→d. Vector scores are in `raw/guest/ev/c<n>.search.<Q>.txt`.

## Assertions

Kinds use the standard's vocabulary: observed, source-supported, inferred, unknown.

| # | Claim | Artifact | Observation | Kind / limit |
|---|---|---|---|---|
| 1 | No entry → first load asks 32768 (2026.11.3) | `raw/guest/ev/proxy.jsonl` ids 35–36; `PX loads=` and `PXROW` lines in `raw/out/m-c1.txt`; `raw/guest/ev/c1.config.json` | `GET /api/v1/models` shows no loaded instance, then `POST /api/v1/models/load {"context_length":32768}` | observed (request object at the proxy) |
| 2 | Same on 2026.11.4 | `proxy.jsonl` ids 144–145; `raw/out/m-c3.txt`; `c3.config.json` | same | observed |
| 3 | `contextTokens: 1024` → load asks 1024 and loads | `proxy.jsonl` ids 3 and 79; `raw/out/m-c2.txt`, `m-c4.txt`; `c2/c4.lms-ps.txt` and `.lms-ps.json.txt` | `context_length:1024`, `200 loaded`; `CONTEXT 1024`, `"contextLength":1024` | observed |
| 4 | Only the catalog entry differs between the paired cells | `c1.config.json` vs `c2.config.json`; c1 = c3, c2 = c4 | `diff` shows only the `models` array | observed |
| 5 | The model advertises 32768 | `raw/guest/ev/models-0.json`; `MODEL` line in `raw/out/m-model.txt` | `max_context_length: 32768` | observed |
| 6 | 32768 comes from the 64,000 fallback clamped to the max | issue text; bot review citing `extensions/lmstudio/src/models.fetch.ts` | — | source-supported (not read by us in this run) |
| 7 | Allocation / OOM at 32768 | `METALGATE` in `raw/out/m-p1024.txt`; `599` rows in `proxy.jsonl` | no large load forwarded; Metal budget unknown | **blocked**; nothing observed about allocation |
| 8 | c1/c3 index failures are reactions to the proxy | `raw/guest/ev/c1.index.txt`, `c3.index.txt`; `CELLERR` lines in `raw/verdicts.txt` | `(599): lab proxy capture-only (synthetic-599)` | observed; not product behaviour |
| 9 | 1024 control completes | `c2/c4.index.txt`, `c2/c4.status.json.txt`, `PXIDX` lines | rc=0, 8 files, 12 chunks, `index.state: complete`, 12/12 inputs 2xx | observed |
| 10 | Prose paraphrases found at 1024 | `c2/c4.search.A.txt`, `.search.D.txt` | A→`a-…md` (vectorScore 0.696203), D→`d-…md` (0.453006) | observed; one run each |
| 11 | The kit's `control failed` label is a harness parse failure | `SUMMARY ctl1024-*` lines in `raw/verdicts.txt`; `STATUSJ`/`SEARCHJ … parsed=no head=+_openclaw_…` in `raw/out/m-c2.txt`; `search()`/`status()` in `kit/j198830.mjs` | `search()` slices at the first `{` and `status()` at the first `[`/`{` (the echo line's timestamp); both whole-string parses fail on the trailing `[state/agent-db] …` and `rc=0` lines | observed |
| 12 | LM Studio truncates >1024-token inputs during OpenClaw's index at 1024 and the index reports success | `raw/guest/ev/c2.rt`, `c4.rt` (`Truncating to 1024 tokens`, timestamps); `c2/c4.index.txt` (start time, `8 files indexed`, `rc=0`) | two warnings per cell inside the index window (`c2.rt:118`, `:134`; `c4.rt:84`, `:134`), 1367 and 1369 tokens; the other matches in the files are a top excerpt, a repeated log block and the in-cell probe (see q3 notes) | observed |
| 13 | The truncated index inputs were the chunks of files `b` and `c` | `raw/corpus/ws-full/memory/`; claim 12 | the only digit-run chunks of that size; the log does not name the input | inferred |
| 14 | Text past ~1024 tokens does not change the vector at 1024 | `PROBE direct-1024` in `raw/out/m-p1024.txt`; `raw/guest/ev/p1024.rt`; `raw/corpus/alt.txt` | `cos_C_vs_Calt=1.000000`, `maxdiff_C=0.00e+0`; warnings for 1367–1369 tokens | observed (direct probe, kit's 4 inputs) |
| 15 | Query C misses at 1024 and hits at 2048 | `c2/c4/c5.search.C.txt` | 1024: top-1 `a` (0.335452); 2048: top-1 `c` (0.614038) | observed; one run per cell. Consistent with claim 14 (inferred link) |
| 16 | Query B misses at 1024 and hits at 2048 | `c2/c4/c5.search.B.txt` | 1024: top-1 `a`, `b` absent from all 6 results; 2048: top-1 `b` (0.629907) | observed; cause not established (truncation of `b` not ruled out) |
| 17 | No truncation warning at 2048 | `raw/guest/ev/c5.rt` | zero `exceeds model context length` lines | observed; full coverage unknown (`prompt_tokens: 0`) |
| 18 | Package identity | `INSTALL`/`INTEGRITY` lines in `raw/out/m-c*.txt`; `raw/guest/ev/c4.install.txt` | versions 2026.11.3 (847611d), 2026.11.4 (d843d6a); integrity, shasum, two dist files match | observed |
| 19 | LM Studio, runtime and model identity | `raw/out/m-lmsinst.txt`, `m-lmssetup.txt`, `m-model.txt` | 0.4.28+2, runtime 2.73.0 selected, GGUF sha256 matched | observed |
| 20 | Host stayed within its guard | `raw/sup.log` | `SUP_PEAKS … max_level=1 max_swap_delta_mib=0 max_vz_rss_gib=19.81` (cap 21) | observed |

## Replay

`kit/` holds the scripts as run, with the comment redactions listed above. `s198830.sh` starts the host supervisor
(`h198830.sh`) and the driver (`d198830.sh`) detached; the driver runs `m198830.sh` and `j198830.mjs` in the guest and
builds the corpus with `c198830.py`; `w198830.sh` is a read-only watcher. Invocation, from a fresh job folder:
`ALLOW_TART_SET=1 MODE=run bash kit/s198830.sh <jobdir>/run <hard-stop-epoch-utc>`. It expects Tart, a VM wrapper
command `bench` (`list`, `new`, `exec`, `stop`, `destroy`) at `/usr/local/bin/bench`, and a golden macOS 26 image with
Node and OpenClaw 2026.11.3 preinstalled. The guest downloads the LM Studio DMG and the GGUF from the pinned URLs in
`m198830.sh`. Known kit bug: `j198830.mjs` `search()`/`status()` parse the whole remainder of each raw guest file,
which ends in non-JSON lines (`[state/agent-db] …`, `rc=0`), and `status()` also starts at the echo line's
`[timestamp]`. Skipping the echo line alone does not fix it; the reader must decode the first JSON value after the echo
line and ignore what follows (or strip the echo and trailing lines). Without that fix the control labels read
`control failed`.

`MANIFEST.sha256` covers every file in this folder except itself (`find . -type f | LC_ALL=C sort`).
