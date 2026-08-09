# G5H-5 implementation matrix

Status: passed on exact corrected implementation candidate; R2H-C rereview pending

Date: 2026-08-08

Authority: [Symbolic Potts V1 G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md)

G5H-5 is the product-qualification boundary. Passing package tests alone is
insufficient: each row below requires final-interface evidence, an exact
candidate, and an honest claim boundary. R2H-C opens only after every row is
passed.

| ID | Required outcome | Authoritative artifact | Executable or static proof | State |
|:--|:--|:--|:--|:--|
| H5-A | Executable final-interface documentation for every stable authoring and execution concept | Curated `docs/make.jl` page tree and rewritten `docs/src` manual | One home page, ten learn/concept pages, two published-model pages, and three API pages are the exact 16-page `docs/make.jl` source set; doctests, cross-references, checks, and HTML rendering passed with `warnonly=false` | passed |
| H5-B | Complete serial Wortel and Merks programs through only the final public API, with upstream symbolic ownership wherever applicable | `examples/wortel_2021_serial.jl`, `examples/merks_2006_serial.jl`, and published-model pages | A statement-by-statement advisory audit found Wortel's site activity/copy/MCS mechanisms intrinsically CPM-owned. Merks diffusion/decay are PDE-shaped, but its moving-occupancy secretion cannot enter the qualified output-only MethodOfLines adapter; a fixed mask would change the mechanism. Published pages record both dispositions and MTK ownership of native internal connections. Root product tests and both direct Mac executions passed; formal R2H-C must independently confirm the substrate disposition. | passed; R2H-C audits |
| H5-C | Fresh-process package and extension load-order closure | Root/integration/package-owned load tests | CPU MTK/MOL/Unitful 3/3, real-Metal 2/2, and Makie 2/2 order matrices passed; Core/base isolation and optional-dependency absence passed | passed |
| H5-D | Package-quality closure | `test/test_package_quality.jl` and package-owned quality tests | Root Aqua/ExplicitImports and exact stale invocation, private-upstream, docs-set, dependency/weakdep, manifest, precompile, and package-owned quality checks passed | passed |
| H5-E | Preservation and removal closure | `g5h5-preservation-closure.md` | PR01--PR30 have passing successor witnesses or explicit owner-deferred dispositions; `EquationProcess` is absent from implementation and public API, with only explicit retirement assertions remaining | passed; R2H-C audits |
| H5-F | Quantitative comparison with the exact G5H-0 baseline | `g5h5-quantitative-evidence.md` and `benchmark/src/g5h5_comparison_probe.jl` | Exact G5H-0 and final source paths measured on target Mac: total construction 0.877x, median MCS 0.934x, allocations and checkpoint regressions explicitly retained; component-pool baseline correctly recorded as absent | passed |
| H5-G | Exact support and limitations matrix | Final manual capability pages plus the G5H-4 conjunction matrix | Capability, runtime, extension, and API pages restrict claims to checked conjunctions and preserve explicit 3D/vendor/MOL-GPU/adaptive/graph-rewrite limitations; docs/API agreement checks passed | passed |
| H5-Q | Full product qualification and freeze | Living control record and exact candidate commit/tree | Root 411/411 + 2,189/2,189; Core 956/956; Makie 503/503; integration 278/278; complete Metal, strict docs, inventory 68, specialization 12/12, static evaluator, 251 tracked Julia parses, 150 tracked TOML parses, diff, retired-surface, and empty-directory checks passed | passed: `06741e681cc1a5cacbbc4f56ac8a412401e4ee52` / `19a8ca73145412b0efa060845ae56fd929605a19` |
| R2H-C | Independent hardening exit review | Fresh read-only review record | First review returned FAIL: P0=0, P1=1 (`EquationProcess` false public surface), P2=1 (incorrect category count), P3=0. The first rereview closed the implementation and owner-added substrate criteria but returned P2=1 because the corrected category count omitted the home page. The exact 16-page set is now recorded; a fresh rereview remains mandatory. | rereview pending |

## Claim discipline

The Wortel and Merks programs are integration/product witnesses, not G7
scientific reproduction claims. The manual must not imply support from
successful structural compilation, from a different backend or component
scope, or from historical unpublished APIs. CUDA, ROCm, 3D execution,
MethodOfLines on GPU, adaptive native GPU solvers, and unrestricted graph
rewriting remain unsupported unless separately qualified before the exact
G5H-5 candidate is frozen.

R2H-C must independently audit every authored Wortel and Merks mechanism.
“Wherever applicable” is resolved by semantics, not implementation
convenience: copy acceptance, lattice ownership, and CPM energy terms are
Potts-owned; continuous/discrete equation systems and their internal wiring
are upstream MTK-owned. Catalyst and MethodOfLines must be used when their
native systems can express the mechanism through a qualified coupling path.
If a published program retains a PottsToolkit numerical component, the review
must identify the exact missing upstream/adapter capability and decide whether
that gap blocks G5H-5. Passing output assertions alone cannot clear this row.

## Freeze protocol

The implementation candidate is committed before its hash is written into the
matrix, quantitative evidence, preservation closure, and living control
record. A second record-only commit binds those artifacts to the immutable
tree. R2H-C reviews that exact implementation candidate; any repair produces a
new candidate and invalidates the earlier review result.
