# ED-R0 engineering-debt review

Status: passed; bounded ED-1 candidate accepted; LW-5 may begin with its
representability inventory and one evidence-bearing pilot

Date: 2026-08-13

Baseline commit: `a049b464b224a47fc4a695338f54db443493d737`

Baseline tree: `079cf8ba4a84d818f138916b178b0330447c7c71`

Qualified ED-1 product commit:
`da80a0ec1f6b52321973872066e02632124ec0f4`

Qualified ED-1 product tree:
`3f81fe700fbba6a82667121ff9d8ada3153aa380`

Authority: [ED-0/ED-1 audit and implementation matrix](ed0-ed1-engineering-debt-audit.md)

## Decision

ED-R0 accepts the exact ED-1 product above with P0=0, P1=0, and P2=0. Every
matrix row is closed, the complete CPU and qualified real-Metal evidence is
green, and no admission, determinism, lifecycle, checkpoint, or scientific
boundary was weakened to obtain the result.

This is an engineering-debt gate, not a new architectural freeze. It does not
authorize broad cleanup or implementation-family expansion. LW-5 may now
start exactly as already specified: inventory representability, choose one
bounded compiled local-operation pilot, and compare adapter size, clarity,
inspection, allocations, launch behavior, CPU behavior, and qualified Metal
behavior against the preserved implementation.

## Qualification record

All commands ran from the repository root unless a project is explicit.
Elapsed wall time is diagnostic only; the laptop changed physical location
during earlier measurements and no duration from this pass is an admission
criterion.

| Boundary | Environment | Result |
|---|---|---|
| LocalWorksets complete package suite | Julia 1.12.6, macOS/Apple M1 | Passed. Package quality includes Aqua, zero package-owned ambiguities, ExplicitImports, API, all mechanisms, generic declarations, consolidation, lifetime/failure, and hostile admission tests. |
| CorePotts complete package suite | Julia 1.12.6, macOS/Apple M1 | Passed. Package quality includes zero package-owned ambiguities and ExplicitImports; scientific reference, direct/LocalWorksets parity, RNG, acceptance, lifecycle, checkpoint, capability, and hostile fresh-world adapter tests passed. |
| PottsToolkit complete package suite | Julia 1.12.6, macOS/Apple M1, one thread | `2,340/2,340` passed. This was the corrected complete rerun, not the earlier targeted-only result. |
| SII/lifecycle focus | Julia 1.12.6 | Passed: attempts 4, validation 27, late profiles 30, remake 15, SII 46, saving 21, checkpoint 20, ensemble 11, callback 25. |
| Cross-domain LocalWorksets CPU witnesses | Julia 1.12.6 | Passed for D2Q9 LBM, deterministic and fast spring accumulation, matrix-free FEM, and z-buffer resolution. Exact result parity, invalid-declaration rejection, launch counts, final waits, and warm workspace reuse remained covered. |
| Behavioral integration | Julia 1.12.1 and the exact versions in `integration/Project.toml` | `278/278` passed, including MTK/MTSL retention, serial and batched native ODE, DAE, Catalyst, MethodOfLines, Unitful, extension loading, and load-order boundaries. |
| Strict documentation | Julia 1.12.1 and `docs/Manifest.toml` | Documenter completed doctests, executable examples, checks, and HTML rendering. |
| Qualified real Metal | Julia 1.12.6, Apple M1 | Semantic suite `7/7` and lifetime/failure suite `8/8` passed. The new topology-diagnostic witness proved structured prelaunch rejection and an unchanged device sentinel. |
| Static seal | exact product tree | Parsed 424 Julia files, 311 TOML files, and CI YAML; `git diff --check` passed; Runic 1.7.0 reported no touched-file changes. |

Fail-closed qualification was observed rather than bypassed. The native
integration suite rejected Julia 1.12.6 before execution and then passed in
its qualified Julia 1.12.1 environment. The standalone Metal suite rejected
Julia 1.12.1 before launch and then passed in its qualified Julia 1.12.6
environment. CI now selects those exact environments instead of treating
vendor-neutral source as runtime qualification.

No kernel or measured execution path changed. Consequently ED-R0 does not
manufacture a throughput claim or rerun the 1,000-pair performance campaign.
The affected paths are constructor/plan validation, exact dispatch, and
diagnostics. Cross-domain CPU launch/allocation witnesses, the complete
CorePotts direct/reference suite, and qualified real-Metal semantics cover
those changes. The sealed LW-4 bundle and direct/reference implementations
were not edited.

## Before/after metrics

Physical line counts are descriptive; no line-count threshold was used.

| Boundary | Baseline production | Candidate production | Delta | Baseline tests | Candidate tests | Delta |
|---|---:|---:|---:|---:|---:|---:|
| PottsToolkit `src` | 24,043 | 24,089 | +46 | 12,040 | 12,058 | +18 |
| PottsToolkit extensions | 2,196 | 2,196 | 0 | - | - | - |
| Integration | - | - | - | 2,213 | 2,213 | 0 |
| CorePotts | 23,218 | 23,224 | +6 | 5,127 | 5,152 | +25 |
| LocalWorksets | 9,112 | 9,150 | +38 | 4,497 | 4,731 | +234 |
| Total production | 58,569 | 58,659 | +90 |  |  |  |

The production increase is earned by explicit statement-family dispatch and
structured validation facts, not architecture growth. The larger
LocalWorksets test increase is the CPU/real-Metal malformed-topology matrix.

The public surface is exactly unchanged:

| Package | Baseline exported/public-only | Candidate exported/public-only | Undocumented public names |
|---|---:|---:|---:|
| PottsToolkit | 272 / 76 | 272 / 76 | 0 |
| CorePotts | 1 / 37 | 1 / 37 | 0 |
| LocalWorksets | 22 / 1 | 22 / 1 | 0 |

Package-owned ambiguity counts changed from PottsToolkit/CorePotts/
LocalWorksets `25/3/0` to `0/0/0`. PottsToolkit's existing ExplicitImports
gate remains green; CorePotts and LocalWorksets now have ordinary green gates
with exact private-access allowlists. CorePotts removed unused `Symmetric`,
`eigen`, and `CellCapacityFailure` imports. Production dependency counts are
unchanged: PottsToolkit 7, CorePotts 7, LocalWorksets 4. ExplicitImports is
test-only debt detection.

Fresh-process, already-precompiled import diagnostics on this Mac were:

| Package | Baseline seconds / bytes | Candidate seconds / bytes |
|---|---:|---:|
| PottsToolkit | 4.490 / 567,912,296 | 5.167 / 574,987,816 |
| CorePotts | 0.220 / 32,816,400 | 0.292 / 33,418,544 |
| LocalWorksets | 0.223 / 25,954,464 | 0.233 / 26,424,112 |

These single fresh-process observations include load and machine noise and
are not compile-time benchmarks. They disclose no change to an execution hot
path and do not justify speculative optimization before the LW-5 value test.

## Focused engineering review

The review applied four independent lenses to the exact product tree:

1. **Julia dispatch and API stability:** exact methods remove demonstrated
   ambiguities; no broad fallback, export, public name, constructor spelling,
   or SII meaning changed.
2. **Backend and admission integrity:** structured faults remain prelaunch,
   unpoisoned, and output-preserving; external declarations still cannot
   authorize execution; CPU/Metal qualification remains fail closed.
3. **Scientific and lifecycle ownership:** CorePotts retains RNG, acceptance,
   Hamiltonian folding, proposal views, settlement, clocks, transactions, and
   checkpoints. LocalWorksets receives no domain behavior.
4. **Build and repository reproducibility:** all four packages appear in CI;
   native and LocalWorksets qualification use their actual exact Julia/dependency
   environments; strict docs and incremental Runic policy are ordinary checks.

Findings:

| Severity | Count | Disposition |
|---|---:|---|
| P0 | 0 | None. |
| P1 | 0 | None. |
| P2 | 0 | None. The three large-file responsibility waivers are explicit LW-5-pilot decisions, not hidden correctness or usability defects. |

Issues found during qualification were repaired without weakening evidence:
the first root rerun exposed a test assertion using `==` on a collection that
can contain `missing`; it now uses `isequal`, and the complete suite passed.
The integration environment had relied on an ignored local Manifest and an
unqualified Julia selection; exact dependency compat and CI runtime selection
now reproduce the reviewed environment. Running native and Metal suites under
the wrong Julia minor demonstrated the intended fail-closed admission before
the qualified reruns passed.

## Preserved deferrals and next boundary

The MethodOfLines input-field issue remains deferred exactly as documented.
ED-R0 does not reopen LocalWorksets naming, lifecycle, execution-family
algebra, or the LW-4 freeze. It does not delete legacy lowering, direct paths,
or scientific reference oracles.

LW-5 is now open, but only its first bounded sequence is authorized:

1. inventory the existing operation lifecycle and terms;
2. classify what is faithfully representable as local work without moving
   domain authority;
3. choose one operation with a preserved direct/reference oracle;
4. implement one evidence-bearing pilot; and
5. use adapter-size, readability, inspection, CPU/Metal parity, allocation,
   and launch evidence to decide whether further consolidation is earned.

If the pilot requires large custom adapters, the authoring surface is reopened
for simplification before any additional mechanism or migration is admitted.
