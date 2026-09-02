# PottsToolkit and CorePotts development roadmap

Status: current navigation; non-normative

Date: 2026-08-09

## Authority

This page is a short map for contributors. It does not define phases, requirements, review rules,
or completion. Current authority is:

1. [Decision 0043](../spec/decisions/0043-retire-processbigraphs.md) for the clean three-package
   boundary;
2. [Decision 0044](../spec/decisions/0044-pre-g6-cohesion-and-mtk-hardening.md) and the
   [G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md) for current work; and
3. the [LocalWorksets V1 Contract](../spec/localworksets-v1.md) and
   [Implementation Gate](../spec/localworksets-v1-implementation-gate.md) for the accepted
   post-G5H route; and
4. the [Compiler Construction Contract](../spec/symbolic-potts-v1-compiler-construction.md) for
   cleared G0--G5 evidence and future G6--G9 work as amended by G5H.

The former R0--R5 roadmap is retired because it competed with the accepted G0--G9 construction
order. It remains recoverable from Git history and must not be cited as an active gate.

## Entry checkpoint

G5 and its R2 execution review are the fixed entry checkpoint. G5H, R2H-C, and LocalWorksets LW-R0
have cleared on their exact candidates; LW-1 is next but has not begun, and G6 remains closed. The
historical and current gate status is the [G5H control record](hardening/g5h-control.md).

## Authoritative path forward

```text
verify Decision 0043 clean baseline
    -> G5H-0 authority and preservation freeze -> R2H-A
    -> G5H-1 Core/semantic consolidation
    -> G5H-2 cohesive pure-Potts authoring
    -> G5H-3 native global MTK integration -> R2H-B
    -> G5H-4 dynamic components, fields, ensembles, and backend profiles
    -> G5H-5 product qualification and documentation -> R2H-C
    -> LocalWorksets LW-0 corrected baseline -> internal slice
    -> one checkerboard sequence -> direct parity -> LW-R1 -> LW-4 disposition
    -> explicit owner send-off
    -> G6--G9
```

The G5H contract and LocalWorksets implementation gate own their respective entry conditions,
deliverables, exit conditions, reviews, and failure routes. The
[G5H control record](hardening/g5h-control.md) tracks status without redefining requirements. Do not
copy them into a second roadmap or audit file.

## Package direction

- PottsToolkit owns `PottsSystem`, authoring, structural MTK compilation, native component
  scheduling, problem construction, late lowering, and the public SciML lifecycle.
- CorePotts remains the independently testable, MTK-free numerical execution kernel.
- LocalWorksets begins as an internal CorePotts substrate; standalone extraction requires LW-R1 and
  an explicit LW-4 disposition.
- MakiePotts consumes explicit public observations and solutions without owning simulation
  semantics.
- External orchestration and a future Mermaid adapter require a new decision and are not on the
  G5H critical path.

## Review discipline

G5H used independent reviews at three irreversible boundaries: authority/preservation,
cohesive native-MTK architecture, and final pre-G6 qualification. Each implementation subgate
still has executable exit checks. LocalWorksets adds the bounded LW-R0 baseline review and LW-R1
direct-parity review defined by its gate. Later G7 and G9 reviews remain unchanged.

Historical research and review files under `design/audits/` describe exact earlier repository
states. They are not living roadmaps or qualification for a changed implementation.
