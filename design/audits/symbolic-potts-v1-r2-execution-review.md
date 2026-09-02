# Symbolic Potts V1 R2 execution review

Date: 2026-08-04

Branch: `codex/symbolic-potts-v1`

Reviewed commit: `5fc007d61a933a2d3e71b2176575202c6d61cd3d`

Production implementation commit: `e22c660e41d358aad15d3e7c92db9b627ec04c96`

Status: complete fresh-context read-only whole-G5 review

Verdict: **R2 clears — P0=0, P1=0, P2=1, P3=0; stop before G6**

## Exact-tree proof

The independent reviewer confirmed the exact branch and commit, an empty `git status --short`, and
an empty `git diff --check HEAD^..HEAD`. Production last changed at `e22c660`; every later path
through the reviewed commit is an audit or specification file. The reviewer remained read-only.

R2 clears under the accepted zero-P0/zero-P1 threshold. This clearance closes G5 but does not open
G6, proof-model migration, or documentation work.

## Finding

### P2 — CPU workgroup matrix lacks ordinary `Pkg.test` ownership

CCV1-024 requires compiler conformance through normal `Pkg.test`
(`spec/symbolic-potts-v1-compiler-construction.md:1077-1080`), requires every kernel family to run
boundary/workgroup fixtures (`:1109-1110`), and specifies `1`, `W-1`, `W`, `W+1`, another
nonmultiple, and a rectangle (`:1144-1147`).

The production-realized matrix exists in
`test/backend_conformance/checkerboard_execution.jl:360-413`. It covers shapes `(1,1)`, `(255,1)`,
`(256,1)`, `(257,1)`, and `(17,19)`; workgroups 32, 64, 128, and 256; and rare constraint and
energy-rejection branches. The fast runner and Metal qualification invoke it. Root
`test/runtests.jl` does not, while the ordinary CI workflow runs `Pkg.test` only.

This is test/CI ownership, not a production defect, and it does not invalidate the exact CPU/Metal
evidence. Earliest repair ownership is G4 checkerboard conformance. It remains a nonblocking P2 for
autonomous disposition before terminal qualification.

## Prior R2 blocker disposition

All eight earlier blockers remain closed:

1. Footprints are closed, compositional, anchor-aware, and policy-sensitive.
2. Checkerboard topology and owned color storage are canonically derived, verified, and rebound by
   compiled programs.
3. Evaluation precedes claims; only accepted proposals claim.
4. Actual launch workgroups and boundary sizes execute with scalar indexing disabled on Metal; only
   the ordinary-test ownership P2 remains.
5. External trackers use typed bounded contracts and independent reconstruction oracles.
6. Relationship reads are incident-local; bounded transactions preserve ownership and atomic
   publication.
7. The authoritative coloring test invokes the production exclusive-footprint reducer and proves
   collision freedom and order independence.
8. Names, declaration order, capacities, slots, parameter values, and homogeneous counts do not
   create unnecessary structural families; the 1/32/1,024 guards remain authoritative.

## Lifecycle disposition

The independent review cleared every challenged lifecycle claim:

- the lifecycle language is closed, typed, and mechanism-neutral;
- cell, relationship, request, tracker, status, and staging storage is fixed-capacity, with no
  runtime resizing;
- sequential and backend paths consume one immutable plan and common transaction contracts;
- there is exactly one production `KernelAbstractions.synchronize`, in settlement;
- submitted, drained, committed, and materialized positions remain distinct;
- device failure is sticky, exact, and mutation-inert after the failure boundary;
- first failure follows canonical request order and state-rule rank, not kernel launch order;
- every admitted effect/policy and the external operations retain shared CPU and real-Metal
  witnesses; and
- no adaptable-storage GPU path silently falls back to the host.

The reviewer specifically challenged the host-stage composition. The branch at
`lib/CorePotts/src/execution/sequential_program.jl:430-495` is explicit, CPU-only, and
host-qualified. Device adaptation rejects accepted/after-MCS stages at
`lib/CorePotts/src/execution/checkerboard_program.jl:490-497`. The supported device lifecycle path
remains backend-resident in `lifecycle_backend_enqueue.jl` and settles once. This bounds the
qualified relationship-mutation surface; it is not a hidden GPU executor or transfer fallback.

## Compilation, payload, and test-cost disposition

The recorded exact-implementation evidence remains authoritative:

- fast profile: 469 assertions, 386.1 seconds test time and 437.34 seconds wall;
- CorePotts: 223 functional assertions and Aqua 10/10;
- sequential lifecycle: 222 assertions; and
- real Metal: 1,035.94 seconds including 46.59 seconds precompile, with scalar indexing disabled.

The cold/warm separation remains consistent with intended structural compilation. Combined
optimized typed IR is 15,252 bytes versus 13,420 bytes for volume-only, or 1.137x rather than a
combinatorial product. Reduced state payloads are 850--1,003 type-description characters versus
6,405 for the previous complete-state argument.

The reduced state-kernel payload remains the established direction. Remaining complete-state
kernel arguments are measurement-only candidates unless a concrete signature, ABI, generated-code,
or backend-compilation measurement attributes material cost to one.

Guarantee-preserving cost reductions may:

- share immutable completed or compiled fixtures while retaining fresh mutable runtimes,
  workspaces, registries, and independent oracles;
- remove repeated compilation of structurally identical fixtures; and
- replace redundant cross-products with orthogonal microfixtures.

Per-kernel Metal cache-family inventories, evaluator-bank slicing, timed fixture sharing, and
measured argument narrowing remain measurement-only. Full scalar-disabled Metal and broad
specialization/IR stress remain explicit qualification rather than everyday CI.

The review rejects speculative generated/static/function-barrier annotations, whole-payload
rewrites, CI timing thresholds, weakened independent oracles, and replacing full Metal
qualification with a smoke test.

## Stop boundary

R2 clears and G5 is complete. The branch stops here before G6 for owner review. No public-integration
expansion, proof-model reconstruction, Wortel/Merks/Act migration, documentation work, new lifecycle
vocabulary, or broad compiler refactor is authorized by this verdict.
