# PottsToolkit and CorePotts development roadmap

Status: current navigation; non-normative

Date: 2026-08-09

## Authority

This page is a short map for contributors. It does not define phases, requirements, review rules,
or completion. Current authority is:

1. [Decision 0043](../spec/decisions/0043-retire-processbigraphs.md) for the clean three-package
   boundary;
2. [Decision 0045](../spec/decisions/0045-native-moving-field-research-gate.md), the
   [G5H-R Research Gate](../spec/symbolic-potts-v1-native-moving-field-research.md),
   [Decision 0044](../spec/decisions/0044-pre-g6-cohesion-and-mtk-hardening.md), and the
   [G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md) for current work; and
3. the [Compiler Construction Contract](../spec/symbolic-potts-v1-compiler-construction.md) for
   cleared G0--G5 evidence and future G6--G9 work as amended by G5H.

The former R0--R5 roadmap is retired because it competed with the accepted G0--G9 construction
order. It remains recoverable from Git history and must not be cited as an active gate.

## Entry checkpoint

G5 and its R2 execution review are the fixed entry checkpoint. Decision 0045 now closes G6 after
the cleared G5H/R2H-C checkpoint until G5H-R research, committee review, and any accepted amendment
route clear. Live status is split between the historical
[G5H control record](hardening/g5h-control.md) and the active
[G5H-R control record](hardening/g5h-r-control.md).

## Authoritative path forward

```text
verify Decision 0043 clean baseline
    -> G5H-0 authority and preservation freeze -> R2H-A
    -> G5H-1 Core/semantic consolidation
    -> G5H-2 cohesive pure-Potts authoring
    -> G5H-3 native global MTK integration -> R2H-B
    -> G5H-4 dynamic components, fields, ensembles, and backend profiles
    -> G5H-5 product qualification and documentation -> R2H-C
    -> G5H-R native moving-field research -> R2H-D committee review
    -> post-review amendment or no-change disposition
    -> all accepted reopened work and reviews
    -> explicit owner send-off
    -> G6--G9
```

The G5H and G5H-R contracts own every entry condition, deliverable, exit condition, review rule,
and failure route in this sequence. Their living control records track status without redefining
requirements. Do not copy them into a second roadmap or audit file.

## Package direction

- PottsToolkit owns `PottsSystem`, authoring, structural MTK compilation, native component
  scheduling, problem construction, late lowering, and the public SciML lifecycle.
- CorePotts remains the independently testable, MTK-free numerical execution kernel.
- MakiePotts consumes explicit public observations and solutions without owning simulation
  semantics.
- External orchestration and a future Mermaid adapter require a new decision and are not on the
  G5H critical path.

## Review discipline

The completed G5H used independent reviews at authority/preservation, cohesive native-MTK
architecture, and product qualification. G5H-R adds one four-role research committee because it may
reopen that cleared architecture; it is not a recurring review after every implementation subgate.
Later G7 and G9 reviews remain unchanged.

Historical research and review files under `design/audits/` describe exact earlier repository
states. They are not living roadmaps or qualification for a changed implementation.
