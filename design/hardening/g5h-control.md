# G5H implementation control

Status: active; G5H-0 review candidate ready; R2H-A pending

Authority: [Symbolic Potts V1 G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md)

This is the sole living status record for G5H. It records outcomes and exact evidence; it does not
repeat or amend gate requirements.

## Gate state

| Boundary | State | Evidence or blocker |
|:--|:--|:--|
| G5H-0 — authority, baseline, preservation | `candidate_ready` | The authority cleanup, exhaustive baseline and preservation map, Decision 0043 retirement, and candidate evidence below are complete. The commit containing this state defines the immutable review candidate. |
| R2H-A — authority and preservation review | `pending` | Awaiting a fresh independent read-only review of the exact candidate commit. |
| G5H-1 — semantic and CorePotts consolidation | `pending` | Blocked by R2H-A. |
| G5H-2 — pure-Potts authoring and SciML lifecycle | `pending` | Depends on G5H-1. |
| G5H-3 — native global MTK integration | `pending` | Depends on G5H-2. |
| R2H-B — cohesion and real-MTK review | `pending` | Opens only after G5H-1 through G5H-3 pass. |
| G5H-4 — dynamic components, fields, ensembles, profiles | `pending` | Blocked by R2H-B. |
| G5H-5 — product qualification and docs | `pending` | Depends on G5H-4. |
| R2H-C — hardening exit review | `pending` | Opens only after G5H-5 passes. |
| G6 owner decision | `closed` | Requires cleared R2H-C and explicit owner send-off. |

## Review results

No formal G5H review has run. Pre-commit readiness audits found no P0, P1, or carry-worthy P2
content findings, but they are not R2H-A. The formal result is recorded here only after a fresh
independent read-only review of the exact candidate commit. Separate request, copied-log, or
freshness-ledger files are not pre-created.

## G5H-0 candidate evidence

All commands completed on the target Mac with Julia 1.12.1 on 2026-08-06.

| Obligation | Exact result |
|:--|:--|
| PottsToolkit full package suite | `Pkg.test("PottsToolkit")`: 1,989/1,989 passed in 35m54s. |
| Independent package suites | CorePotts: 233/233 passed (223 functional and 10 package-quality assertions); MakiePotts: 501/501 passed. |
| Optional integration suite | 22/22 passed: 12 legacy MTK-assimilation, 4 ModelingToolkitStandardLibrary, 4 Unitful, and 2 load-order assertions. The first two groups preserve existing behavior only and do not qualify the G5H-3 native-island target. The ignored local environment resolved ModelingToolkit 11.37.1, ModelingToolkitBase 1.58.1, ModelingToolkitStandardLibrary 2.29.5, SciMLBase 3.39.1, SymbolicIndexingInterface 0.3.51, Symbolics 7.34.1, DynamicQuantities 1.13.0, and Unitful 1.28.0. |
| Documentation | Strict four-page temporary manual built with `warnonly=false`; the active manual and authority corpus have 208 Markdown files and zero missing local targets. |
| Fresh-process boundaries | PottsToolkit loaded without full ModelingToolkit or the retired package; CorePotts loaded without PottsToolkit, ModelingToolkitBase, ModelingToolkit, SciML, or Makie; the public platform smoke trajectory passed. |
| Inventory and static integrity | `git diff --check` passed; all 115 production source files and 58 test/support files are exactly partitioned; public declarations are 299 unique PottsToolkit names (300 declarations), 479 CorePotts names, and 74 MakiePotts names with the exact file digests recorded in the baseline. |
| Retirement and environments | All 356 tracked deletions match `g5h0-deletion-inventory.tsv`; active source, tests, projects, manifests, workflows, and documentation contain no retired dependency or hook; stale application manifests were regenerated from their surviving projects. |
| Recovery | Parent commit `3591eccd6820bf51c185cf631c75467114319332` recovers every tracked deletion. The external archive checksum is `338d74d39aa46c2610f49bfc55cfb48ce60e86d12113b337d7d669af8a2007bd` and it contains 16,294 entries under `lib/ProcessBigraphs/`. |

## Control rules

- A gate becomes `passed` only when every normative exit condition has executable or static
  evidence and the exact checkpoint is recorded.
- A later regression marks the earliest owning gate `reopened` and invalidates downstream review
  clearance as specified by the contract.
- P2 findings may be carried through R2H-A or R2H-B only with an explicit owning gate. R2H-C closes
  every in-scope P2.
- Historical audit results qualify only their recorded repository state.
