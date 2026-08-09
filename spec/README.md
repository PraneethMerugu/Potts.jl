# Potts.jl semantics specification

Version: `0.6-draft`

Status: Draft

## Authority

This specification defines the observable scientific behavior of PottsToolkit and CorePotts.
A conforming implementation may change storage layouts, kernel organization, parallel scheduling,
backend libraries, and other internal mechanisms, but it must preserve accepted observable
behavior.

Apply authority in this order:

1. the accepted [Project Charter](project-charter.md) and the latest accepted decision that
   explicitly changes a product or architecture choice;
2. the
   [G5H-R Native Moving-Field Research Gate](symbolic-potts-v1-native-moving-field-research.md)
   and [G5H Hardening Contract](symbolic-potts-v1-hardening.md) for post-G5 work order, MTK/SciML
   integration, component scheduling, late lowering, capability profiles, and the G6 entry gate;
3. accepted scientific contracts for state, CPM transitions, lifecycle, randomness, persistence,
   topology, observation, and numerical meaning;
4. earlier construction contracts only where the current index or a later decision has not marked
   them superseded; and
5. implementation, tests, tutorials, examples, and historical design evidence.

A more specific later accepted decision wins only in the scope it names. Historical audits,
superseded clauses, and working code are evidence, not authority to restore an obsolete API or
product boundary.

## Scope

The specification covers:

- PottsToolkit model authoring, composition, completion, validation, and compilation;
- CorePotts state, transition, lifecycle, observation, checkpoint, and execution semantics;
- SciML problem, algorithm, integrator, solution, remake, and ensemble behavior;
- ModelingToolkit completion and compilation integration;
- CPU and accelerator backend guarantees;
- reproducibility, semantic randomness, numerical expectations, and scientific claims; and
- published-model admission and evidence requirements.

External orchestration systems are out of scope unless admitted by a later, independently reviewed
extension contract. They cannot redefine PottsToolkit or CorePotts semantics.

## Surviving scientific contracts

- [Project Charter](project-charter.md)
- [Glossary](glossary.md)
- [State Model](state-model.md)
- [Time and Monte Carlo Steps](time-and-mcs.md)
- [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md)
- [Lifecycle](lifecycle.md)
- [Randomness and Reproducibility](randomness-and-reproducibility.md)
- [Snapshots, Checkpoints, Restore, and Logical Storage](persistence.md)
- [Energy, Proposals, Acceptance, and Trackers](energy-proposals-and-trackers.md)
- [Topology and Spatial Relations](topology-and-spatial-relations.md)
- [Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md)
- [Sequential Reference Engine](reference-engine-semantics.md)
- [Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md)
- [Transition-Kernel Verification](transition-kernel-verification.md)
- [Published-Model Reproduction Semantics](published-model-reproduction-semantics.md)

The scientific meaning in these files survives G5H. Historical API names, algorithm inventories,
backend claims, or phase order inside them do not override Decision 0044 or the hardening contract.

## Superseded-in-part interface contracts

- [PottsToolkit Authoring, Composition, and API Semantics](pottstoolkit-authoring-composition-and-api-semantics.md)
- [CorePotts Public Scientific and Execution Interfaces](corepotts-public-interface-semantics.md)
- [SciML Interface Semantics](sciml-interface-semantics.md)
- [PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md)

These documents retain useful scientific intent and earlier evidence. Their pre-V1 `PottsModel`,
old public API, authoring layers, algorithm inventory, compilation ownership, phase assignments,
and maturity claims are not current implementation authority. G5H-0 must disposition each retained
behavior before source cleanup.

## Current construction program

- [Symbolic Potts V1 Native Moving-Field Research and Amendment Gate](symbolic-potts-v1-native-moving-field-research.md)
  — authoritative for the current committee-reviewed pre-G6 research and any resulting bounded
  G5H amendment
- [Symbolic Potts V1 G5H Hardening](symbolic-potts-v1-hardening.md) — authoritative for the current
  passed post-G5 implementation record and, as amended after G5H-R review, G6 entry
- [Symbolic Potts V1 Compiler Construction](symbolic-potts-v1-compiler-construction.md) —
  authoritative for cleared G0--G5 and future G6--G9 as amended by G5H
- [Symbolic Potts V1](symbolic-potts-v1.md)
- [Symbolic Potts V1 Architecture Redirection](symbolic-potts-v1-architecture-redirection.md)

The last two documents are superseded in part. Their `EquationComponent` assimilation, public
backend-specific compilation, public `PottsExecutable`, and direct G5-to-G6 clauses must not be
implemented.

Any clause in those documents that assumes the retired orchestration package is superseded by
[Decision 0043](decisions/0043-retire-processbigraphs.md). PottsToolkit and CorePotts must remain
independently loadable and testable without that retired package or its API.

## Decision records

Accepted semantic decisions and their status are indexed in
[Decision Records](decisions/README.md).

[Historical conformance evidence](conformance-evidence.md) and files under `design/audits/` describe
earlier exact repository states. G5H creates a new preservation map rather than treating those
claims as current qualification.

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** retain their usual
normative meanings. Accepted semantics and implementation maturity are separate: working code is
not automatically a compatibility or scientific claim.
