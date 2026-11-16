# Assertions: #192790, run L192790, OpenClaw 2026.11.3 (847611d)

Quantity: **measured** (read directly from a record), **derived** (computed from measured records), **estimated**
(none in this packet). Evidence kind: **observed**, **source-supported**, **inferred**, **unknown**.
Times are UTC on 2026-11-16. "Tick" = a scheduled heartbeat wake. A tick that reaches the model produces one heartbeat
request plus one tool continuation request (the gateway sends the tool result back); request counts below count
heartbeat requests only, unless they say "chat requests".

## Main assertion (A3a then A3b; `messages.visibleReplies=message_tool`, scripted provider)

| # | Claim | Artifact | Observation | Limitation | Quantity / kind |
|---|---|---|---|---|---|
| 1 | Before A3a the scratch was missing. | `raw/part1/A3a-action.txt`; `raw/part1/scratch-reads.txt` "A3a after-action 11:07:05Z" | `"scratch": null, "currentRevision": 2` | — | measured / observed |
| 2 | On each of the six A3a ticks the provider proposed the note and the tool accepted it. | `derived/request-ledger-part1.txt` rows A3a 16–27; `raw/part1/A3a-stats.txt` | 6 heartbeat requests (11:07:10 … 11:12:10, one per tick); each reply `heartbeat_respond(notify,outcome,scratch,summary)`; each tool result `"status": "accepted"`, `"scratchPending": true`, `"scratchBytes": 130` | Scripted provider, not a real model. | measured / observed |
| 3 | The note was stored as non-empty monitor scratch. | `raw/part1/scratch-reads.txt` A3a +60 s … +300 s | Reads at 11:08:07, 11:09:08, 11:10:10, 11:11:11, 11:12:13 show the note at revisions 3, 4, 6, 7, 8; `updatedAtMs` of each converts to 11:07:10, 11:08:10, 11:10:10, 11:11:10, 11:12:10 | Revision 5 was never read. That each of the six proposals bumped the revision once (2 → 8) is derived from the numbers and times, not observed per tick. | measured (reads), derived (per-tick) / observed |
| 4 | From the second A3a tick on, the stored note was in the current-turn heartbeat prompt. | `derived/current-turn-heartbeat-prompts.txt` #16 vs #18; `derived/request-ledger-part1.txt` `current_turn_scratch` | #16 (tick 1): no `Heartbeat monitor scratch:` block. #18 (tick 2) and every later A3a/A3b heartbeat request: block present with the note | Detected by string match on the block header. | measured / observed |
| 5 | After proposals stopped (A3b, mode `plain`), the stored scratch stayed the note, unchanged. | `raw/part1/scratch-reads.txt` A3b before-action … +240 s | Six reads 11:12:17 … 11:16:25, all revision 8, note content, `updatedAtMs` 11:12:10 | Reads about every 60 s. | measured / observed |
| 6 | **Decisive:** on each of the four subsequent observed ticks the model was dispatched; no empty-scratch skip was observed on those ticks. | `derived/request-ledger-part1.txt` rows A3b 28–35; `raw/part1/A3b-stats.txt`; `raw/part1/A3b-gateway-window.log`; `raw/part1/A3b-hblast.txt` | 4 heartbeat requests at 11:13:10, 11:14:10, 11:15:10, 11:16:10 (`hb_calls=4`, 8 chat requests incl. continuations); 4 gateway lines "recorded message-tool-only run outcome" at the same seconds; last status `ok-token`, reason `interval` | Four ticks over about four minutes. Only the last tick's status is recorded by `heartbeat last`; "no skip" on the other three rests on a request at each tick time. Says nothing about longer periods or real models. | measured / observed |
| 7 | With an explicit comment-only scratch, the same release skips the model. | `raw/part1/A2-stats.txt`, `A2-hblast.txt`, `scratch-reads.txt` A2; same for A4 | A2 and A4: 0 chat requests over 4 ticks each; scratch `<!-- idle: nothing to check -->` (rev 1 in A2, rev 9 in A4) unchanged at every read; last status `skipped`, reason `empty-heartbeat-file` | The gateway log has no line for a skip (both windows empty); per-tick skips are derived from zero requests. | measured / observed |
| 8 | With a missing scratch, the same release dispatches the model. | `raw/part1/A1-stats.txt`, `A1-hblast.txt`, `scratch-reads.txt` A1 | 4 heartbeat requests on 4 ticks (10:59:10 … 11:02:10); scratch null, revision 0 at all six reads; last status `ok-token` | — | measured / observed |

## Other observations

| # | Claim | Artifact | Observation | Limitation | Quantity / kind |
|---|---|---|---|---|---|
| 9 | In the default embedded configuration (no `messages` block) the proposal did not persist. | `inputs/config-mock-A5.json`; `derived/current-turn-heartbeat-prompts.txt` #4; `derived/request-ledger-part1.txt` A5; `raw/part1/A5-gateway-window.log`; `A5-hblast.txt`; `scratch-reads.txt` A5 | Prompt asks for `NO_REPLY`, not `heartbeat_respond`; the mock called `heartbeat_respond` with `scratch` anyway on 3 heartbeat runs (11:21:11, 11:22:10, 11:23:12; no heartbeat request after 11:23:12 in the phase window); tool error "heartbeat_respond is only accepted during a heartbeat run" each time; gateway "session event wake failed … error=agent-runner-failure" ×3; last status `failed`; scratch null, revision 10, at all five reads after the unset | The scripted provider ignored the prompt; only the `heartbeat_respond.scratch` path was exercised. Our ticket predicted this from a source reading that is not part of this packet; no other write path was tested. Why no run followed at 11:24 is unknown. | measured / observed |
| 10 | Mock's `scratch_in_prompt=True` in A5 comes from older history, not the current turn. | `raw/part1/A5-stats.txt` vs `derived/request-ledger-part1.txt` A5 | `A5-stats.txt`: True ×3. Ledger: `current_turn_scratch` False ×3, `history_scratch` True | Kit flag design; does not affect claims 1–8 (ledger shows current turn True there). | derived / observed |
| 11 | Qwen did not propose a scratch note on six idle ticks. | `raw/part2/Q-stats.txt`, `relay.out`, `scratch-reads.txt`, `derived/labstats-part2-new-records.jsonl` | 6 ticks, 15 chat requests, all 200; 6 `heartbeat_respond` calls with keys `notify,outcome,summary` only; first tick also made 3 `exec` calls; scratch null, revision 0, at every read incl. 11:54:01 | One model, fresh bootstrap workspace, about 24 minutes. Trigger precondition not reached; not a refutation of claims 2–6 and not an incidence rate. | measured / observed |
| 12 | Part 2 requests carried `num_ctx` 262144. | `derived/labstats-part2-new-records.jsonl`; `inputs/config-qwen-part2.json` | 15 records, all `num_ctx: 262144`, `status: 200`; `prompt_eval_count` 14111 … 17632 | Requested value only; effective server context unknown. | measured / observed (requested); effective: unknown |
| 13 | The beta could not start with the kit's config. | `raw/part3-beta/gateway-beta-refusal-excerpt.log`; `inputs/config-beta-part3.json` | "agents.defaults: Unrecognized key: \"heartbeat\"" / "Heartbeat configuration retired", twice | Kit compatibility block. No data about the beta's heartbeat/Automations behaviour. | measured / observed |
| 14 | Release under test is 2026.11.3 (847611d). | `inputs/versions.txt` | CLI banner from the bench install job | Gateway process revision not separately recorded (inferred same binary). | measured (CLI) / observed; Gateway: inferred |

## Derived calculations

- Revisions consumed in A3a: 8 − 2 = 6, equal to the 6 accepted proposals (claim 3). Revision 9 is the A4 `--set`
  (`raw/part1/A4-action.txt`); revision 10 is the A5 `--unset` (`A5-action.txt`).
- `updatedAtMs` → UTC: 1794827230758 → 11:07:10Z; 1794827290371 → 11:08:10Z; 1794827410508 → 11:10:10Z;
  1794827470412 → 11:11:10Z; 1794827530438 → 11:12:10Z.
- A2/A4 tick count: phase windows 11:02:53–11:07:01 and 11:16:31–11:20:39 each contain four 60 s ticks (the tick
  schedule is the :10 second mark seen in A1/A3).
