# 0044: Insert pre-G6 cohesion, MTK, and product hardening

Status: Accepted

Date: 2026-08-06

## Context

The G0--G5 compiler and execution work established substantial CPM machinery, but the repository
reached the G6 boundary with an incohesive public authoring surface and a ModelingToolkit extension
that treats `mtkcompile` as backend-specific executable lowering. External MTK systems are copied
field by field into Potts systems, the public executable is selected too early, and working CorePotts
features are spread across overlapping schemas and protocols.

Opening G6 in that state would freeze the wrong integration boundary. The project instead needs a
bounded phase that preserves its strong numerical work, consolidates semantic ownership, uses MTK
as MTK is designed to be used, qualifies dynamic per-cell components and fields, and rebuilds the
authoring manual only after the interface is cohesive.

## Decision

1. Insert `G5H` after the cleared G5/R2 checkpoint and before G6.
2. Adopt the [G5H hardening contract](../symbolic-potts-v1-hardening.md) as the sole authority for
   that phase and for revised post-G5 MTK, SciML, late-lowering, component, capability, and public
   lifecycle requirements.
3. `mtkcompile(::PottsSystem)` is structural and returns a scheduled `PottsSystem`. Engine,
   backend, scalar, and device specialization occurs during problem materialization, `init`, or
   `solve`.
4. Preserve external MTK systems as native component islands. Do not assimilate them by copying
   equations, variables, defaults, events, or hierarchy into a Potts surrogate.
5. Keep integer completed MCS as the master CPM clock. Couple native component time through an
   explicit duration-per-MCS map and named split policy.
6. Keep CorePotts MTK-free and consolidate it into a narrow, mechanism-free execution kernel.
7. Treat whole-trajectory SciML ensembles and within-trajectory per-cell vectorization as distinct
   first-class features.
8. Require CPU reference and explicit real-GPU evidence for each stable component-scope profile;
   unsupported combinations reject without fallback.
9. Evaluate Dagger only as an optional coarse scheduler. An evidence-backed deferral is acceptable.
10. Use three independent reviews: after the authority/preservation freeze, after the cohesive
    Core/authoring/native-MTK vertical slice, and at hardening exit. Do not add a fresh review after
    every implementation subgate.
11. G6 remains closed until the terminal G5H review clears and the project owner explicitly opens
    it.

## Scoped supersession

This decision supersedes conflicting portions of Decisions 0013, 0016, 0025, 0026, and 0029
through 0033 concerning the active algorithm inventory, `PottsModel`/`ModelFragment` authoring,
compiler and problem ownership, coupled scheduling, blanket accelerator promotion, simultaneous
vendor requirements, and documentation phase order. Their compatible scientific semantics and
evidence remain useful.

It also supersedes the conflicting public lifecycle, `EquationComponent` assimilation, manual MTK
field-copying, public `PottsExecutable`, and direct G5-to-G6 ordering clauses in the Symbolic Potts
V1, Architecture Redirection, and Compiler Construction contracts. The hardening contract contains
the exact disposition.

Decision 0043 remains fully in force. G5H does not restore ProcessBigraphs or authorize a Mermaid
runtime dependency.

## Consequences

- G5H is a hardening and consolidation phase, not a second platform project.
- Some currently implemented public methods and documentation examples are expected to be removed
  rather than preserved for compatibility.
- Existing G0--G5 evidence is retained unless a G5H change touches its invariant, in which case the
  applicable witness and review reopen.
- The legacy manual is quarantined during hardening and rebuilt against the final public API in
  G5H-5.
- A private executable cache remains permitted, but it cannot become a second public model or
  compilation authority.

## Required conformance evidence

- The authority index and every superseded-in-part active document point to the G5H contract.
- The three G5H reviews clear under the shared severity and exact-commit protocol.
- Pure Potts and native MTK black-box workflows pass through one public lifecycle.
- CorePotts independently loads and tests without MTK or PottsToolkit.
- Dynamic per-cell lifecycle, MethodOfLines, ensembles, and admitted CPU/GPU profiles have explicit
  evidence or explicit rejection.
- Wortel and Merks run serially through the final public API in strict documentation and on the
  target Mac before G6 opens.
