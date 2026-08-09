# G5H-5 implementation matrix

Status: implementation qualified; exact candidate freeze pending

Date: 2026-08-08

Authority: [Symbolic Potts V1 G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md)

G5H-5 is the product-qualification boundary. Passing package tests alone is
insufficient: each row below requires final-interface evidence, an exact
candidate, and an honest claim boundary. R2H-C opens only after every row is
passed.

| ID | Required outcome | Authoritative artifact | Executable or static proof | State |
|:--|:--|:--|:--|:--|
| H5-A | Executable final-interface documentation for every stable authoring and execution concept | Curated `docs/make.jl` page tree and rewritten `docs/src` manual | Twelve final-interface learn/concept pages plus API and published-model references are the exact `docs/make.jl` source set; doctests, cross-references, checks, and HTML rendering passed with `warnonly=false` | passed on freeze worktree |
| H5-B | Complete serial Wortel and Merks programs through only the final public API | `examples/wortel_2021_serial.jl`, `examples/merks_2006_serial.jl`, and published-model pages | Reusable programs execute verbatim in strict docs and root tests; product suite passed 9/9 and both direct Mac executions passed | passed on freeze worktree |
| H5-C | Fresh-process package and extension load-order closure | Root/integration/package-owned load tests | CPU MTK/MOL/Unitful 3/3, real-Metal 2/2, and Makie 2/2 order matrices passed; Core/base isolation and optional-dependency absence passed | passed on freeze worktree |
| H5-D | Package-quality closure | `test/test_package_quality.jl` and package-owned quality tests | Root Aqua/ExplicitImports and exact stale invocation, private-upstream, docs-set, dependency/weakdep, manifest, precompile, and package-owned quality checks passed | passed on freeze worktree |
| H5-E | Preservation and removal closure | `g5h5-preservation-closure.md` | PR01--PR30 have passing successor witnesses or explicit owner-deferred dispositions; retired paths have negative inventory proof and obsolete manual/model files are deleted | passed pending R2H-C audit |
| H5-F | Quantitative comparison with the exact G5H-0 baseline | `g5h5-quantitative-evidence.md` and `benchmark/src/g5h5_comparison_probe.jl` | Exact G5H-0 and final source paths measured on target Mac: total construction 0.877x, median MCS 0.934x, allocations and checkpoint regressions explicitly retained; component-pool baseline correctly recorded as absent | passed; commit binding pending |
| H5-G | Exact support and limitations matrix | Final manual capability pages plus the G5H-4 conjunction matrix | Capability, runtime, extension, and API pages restrict claims to checked conjunctions and preserve explicit 3D/vendor/MOL-GPU/adaptive/graph-rewrite limitations; docs/API agreement checks passed | passed on freeze worktree |
| H5-Q | Full product qualification and freeze | Living control record and exact candidate commit/tree | Root 411/411 + 2,190/2,190; Core 956/956; Makie 503/503; integration 278/278; complete Metal, strict docs, inventory 68, specialization 12/12, static evaluator, 251 Julia parses, 154 TOML parses, diff, and empty-directory checks passed | qualification passed; exact freeze pending |
| R2H-C | Independent hardening exit review | Fresh read-only review record | Exact candidate/environment/diff/commands; P0=0, P1=0, unresolved in-scope P2=0; every preservation row and public claim reviewed | closed until H5-Q |

## Claim discipline

The Wortel and Merks programs are integration/product witnesses, not G7
scientific reproduction claims. The manual must not imply support from
successful structural compilation, from a different backend or component
scope, or from historical unpublished APIs. CUDA, ROCm, 3D execution,
MethodOfLines on GPU, adaptive native GPU solvers, and unrestricted graph
rewriting remain unsupported unless separately qualified before the exact
G5H-5 candidate is frozen.

## Freeze protocol

The implementation candidate is committed before its hash is written into the
matrix, quantitative evidence, preservation closure, and living control
record. A second record-only commit binds those artifacts to the immutable
tree. R2H-C reviews that exact implementation candidate; any repair produces a
new candidate and invalidates the earlier review result.
