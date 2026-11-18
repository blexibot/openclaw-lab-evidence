# OpenClaw lab evidence

Replayable evidence packets for OpenClaw issue reproductions, from a small home lab run by Harold (an OpenClaw
maintainer focused on local-model UX).

Each folder is one result, named after the issue it belongs to (for example `188657/`). The comment on that issue or
PR links here.

## What's in a packet
- `README.md`: the narrow claim and its outcome, attempts and failures, limits, and the reported preconditions we did
  **not** match. Then the inputs: exact OpenClaw build, test-kit hash and invocation, environment, backend and model,
  and capture position.
- `ASSERTIONS.md`: each claim mapped to the artifact that supports it, what was observed, and its limit. Each claim
  is marked as measured, derived or estimated, and as observed, source-supported, inferred or unknown.
- The test kit, a synthetic fixture and redacted config, and the minimal raw outputs behind each claim.
- `MANIFEST.sha256`: hashes of exactly the files in the folder. Check them with `sha256sum -c MANIFEST.sha256`
  (`shasum -a 256 -c` on macOS).

## How to read the outcomes
- **Test outcome:** reproduced · not reproduced under these conditions · blocked · inconclusive (harness failure) ·
  candidate passes this scenario.
- **Evidence kind:** observed · source-supported · inferred · unknown.
- "Not reproduced" only means something when the run reached the reported trigger, and it never means "fixed".
  "Candidate passes this scenario" is not "fixed by this PR".

## How the lab works
The tests run on fresh, throwaway machines that are destroyed after each issue: Linux (Incus containers, which share
the host kernel), Windows 11 (Hyper-V VMs) and macOS 26 (Tart VMs). Where a model is needed, the OpenClaw installs
under test use a remote model served by the lab (Qwen3.8-27B on Ollama, or DeepSeek V4.1 Flash on SGLang), behind a
relay and a request filter; each packet names the model and the path. Most kits use a
deterministic mock server instead of a model.

The tests are run by an autonomous lab of AI agents using local models, from written tickets. Harold reviews every
result's commands, evidence and conclusions before anything is published here.

## Data
Everything here is synthetic test data. Tokens, hostnames and addresses are replaced with placeholders such as
`<TOKEN>` and `<RELAY>`. Original captures are kept privately; the hashes here cover only the redacted copies.

## License
CC0 1.0: use any of it, including in OpenClaw tests, without asking.
