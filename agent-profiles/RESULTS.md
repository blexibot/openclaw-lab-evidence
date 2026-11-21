# Results (kit v1.2, 3 seeds per cell; latest attempt per cell counts)

Each cell is `passes/3`. Flags in brackets count the same 3 runs:
`req` the rule or skill text was in the model's request; `srch` the skill was found with tools (not listed);
`nat` the native automations tool was used; `sh` a shell/CLI route was used; `false` the reply claimed done but no correct reminder exists.
Rungs: R0 stock release; R1 Lean; R2 Lean + no skills; R3 R2 + 4,000-char workspace cap. PB = PR #202517 branch, default profile; PS = same branch, `openclaw/small`.

## Gemma 4 26B-A4B — release OpenClaw 2026.11.5 (e13cf15) — fresh workspace (`runs/g19-v4`)

| task | R0 | R1 | R2 | R3 |
|---|---|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 3/3 [req 3] | 3/3 [req 3] | 0/3 |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 3/3 [req 3] | 3/3 [srch 3] | 3/3 [srch 3] |
| T16 read a 401-line file, report its last line | 3/3 | 3/3 | 3/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 1/3 [sh 1, false 2] | 1/3 [false 1, sh 1] | 2/3 [sh 2, false 1] | 0/3 [false 1] |

Rows in file: 48 (reruns: 0); rows with foreign requests: 0.

## Qwen 3.8 27B — release OpenClaw 2026.11.5 (e13cf15) — fresh workspace (`runs/q27m-v4b`)

| task | R0 | R1 | R2 | R3 |
|---|---|---|---|---|
| T10b obey a rule in AGENTS.md | 0/3 [req 3] | 2/3 [req 3] | 2/3 [req 3] | 0/3 |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 3/3 [req 3] | 0/3 | 2/3 [srch 2] |
| T16 read a 401-line file, report its last line | 3/3 | 3/3 | 3/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 3/3 [nat 3] | 3/3 [sh 3] | 2/3 [sh 3] | 3/3 [sh 3] |

Rows in file: 52 (reruns: 4); rows with foreign requests: 4.

## Qwen3 8B — release OpenClaw 2026.11.5 (e13cf15) — fresh workspace (`runs/q8-v6`)

| task | R0 | R1 | R2 | R3 |
|---|---|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 3/3 [req 3] | 3/3 [req 3] | 0/3 |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 2/3 [req 3] | 0/3 | 0/3 |
| T16 read a 401-line file, report its last line | 2/3 | 3/3 | 0/3 | 0/3 |
| T11b set a one-shot reminder in 10 min | 1/3 [nat 2] | 0/3 | 0/3 | 0/3 |

Rows in file: 48 (reruns: 0); rows with foreign requests: 0.

## Gemma 4 26B-A4B — branch OpenClaw 2026.11.5 (ffe3bf0) — fresh workspace (`runs/g-pr-v4`)

| task | PB | PS |
|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 3/3 [req 3] |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 3/3 [srch 3] |
| T16 read a 401-line file, report its last line | 3/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 3/3 [nat 3] | 1/3 [nat 2, false 2] |

Rows in file: 24 (reruns: 0); rows with foreign requests: 0.

## Qwen 3.8 27B — branch OpenClaw 2026.11.5 (ffe3bf0) — fresh workspace (`runs/q27m-pr-v4`)

| task | PB | PS |
|---|---|---|
| T10b obey a rule in AGENTS.md | 2/3 [req 3] | 2/3 [req 3] |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 1/3 [srch 1] |
| T16 read a 401-line file, report its last line | 3/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 2/3 [nat 3, false 1] | 3/3 [nat 3] |

Rows in file: 25 (reruns: 1); rows with foreign requests: 1.

## Qwen3 8B — branch OpenClaw 2026.11.5 (ffe3bf0) — fresh workspace (`runs/q8-pr-v4`)

| task | PB | PS |
|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 3/3 [req 3] |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 0/3 |
| T16 read a 401-line file, report its last line | 3/3 | 0/3 |
| T11b set a one-shot reminder in 10 min | 0/3 | 0/3 |

Rows in file: 24 (reruns: 0); rows with foreign requests: 0.

## Gemma 4 26B-A4B — branch OpenClaw 2026.11.5 (ffe3bf0) — lived-in workspace (`runs/g-pr-lv4`)

| task | PB | PS |
|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 0/3 |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 0/3 |
| T16 read a 401-line file, report its last line | 0/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 0/3 [nat 3] | 3/3 [nat 3] |

Rows in file: 24 (reruns: 0); rows with foreign requests: 0.

## Qwen 3.8 27B — branch OpenClaw 2026.11.5 (ffe3bf0) — lived-in workspace (`runs/q27m-pr-lv4`)

| task | PB | PS |
|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 0/3 [srch 1] |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 2/3 [srch 2] |
| T16 read a 401-line file, report its last line | 2/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 0/3 [nat 1] | 3/3 [nat 3] |

Rows in file: 29 (reruns: 5); rows with foreign requests: 3.

## Qwen3 8B — branch OpenClaw 2026.11.5 (ffe3bf0) — lived-in workspace (`runs/q8-pr-lv4`)

| task | PB | PS |
|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 0/3 |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 0/3 |
| T16 read a 401-line file, report its last line | 0/3 | 0/3 |
| T11b set a one-shot reminder in 10 min | 0/3 [false 1] | 0/3 |

Rows in file: 24 (reruns: 0); rows with foreign requests: 0.

## Qwen 3.8 27B — release, reference only: ran on 2026.11.6 after the model self-updated the install (superseded by q27m-v4b) OpenClaw 2026.11.6 (06afb10) — fresh workspace (`runs/q27m-v4`)

| task | R0 | R1 | R2 | R3 |
|---|---|---|---|---|
| T10b obey a rule in AGENTS.md | 3/3 [req 3] | 3/3 [req 3] | 2/3 [req 3] | 0/3 |
| T15 use a workspace skill (not named in the request) | 3/3 [req 3] | 3/3 [req 3] | 3/3 [srch 3] | 3/3 [srch 3] |
| T16 read a 401-line file, report its last line | 3/3 | 3/3 | 3/3 | 3/3 |
| T11b set a one-shot reminder in 10 min | 3/3 [nat 3] | 3/3 [sh 3] | 2/3 [sh 3] | 3/3 [sh 3] |

Rows in file: 53 (reruns: 5); rows with foreign requests: 4.

