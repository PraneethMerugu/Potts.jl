# 0043: Retire ProcessBigraphs and restore the PottsToolkit/CorePotts focus

Status: Accepted

Date: 2026-08-05

## Context

The repository incubated `ProcessBigraphs.jl` as a domain-neutral orchestration engine and later
connected it to PottsToolkit through a package extension. The implementation accumulated a second
authoring, compilation, scheduling, persistence, and SciML-facing stack. That surface no longer
serves the project's immediate goal of producing a cohesive PottsToolkit authoring layer over a
small, independently testable CorePotts engine.

Experiments with Mermaid.jl may still inform future composition work, but they do not justify
retaining an unfinished runtime, compatibility surface, or dependency in this repository.

## Decision

1. Remove the ProcessBigraphs package, Potts adapter, public hooks, dependencies, manifests,
   tests, documentation, CI jobs, qualification scripts, and dedicated normative artifacts from
   the working repository.
2. PottsToolkit owns biological and symbolic authoring, ModelingToolkit integration, validation,
   lowering, and creation of executable Potts problems.
3. CorePotts owns numerical execution, runtime state, algorithms, observations, checkpoints, and
   backend contracts. It must not depend upward on PottsToolkit or an orchestration framework.
4. `process_component` and all ProcessBigraph-specific compatibility behavior are removed without
   a migration shim. The package was unpublished and pre-1.0.
5. A future Mermaid integration must begin as a new, bounded adapter proposal. It may not restore
   the retired engine, duplicate the Potts lifecycle, or become a prerequisite for using either
   PottsToolkit or CorePotts.
6. Historical mixed documents may mention the retired work. Those references are non-normative
   and cannot authorize implementation. This decision supersedes Decisions 0034 and 0036 through
   0042 wherever they require the retired package or its integration surface.

## Consequences

- The active package family contains PottsToolkit, CorePotts, and MakiePotts.
- PottsToolkit and CorePotts development can proceed from direct public boundaries without an
  orchestration compatibility burden.
- Checkpoints and artifacts that require ProcessBigraph runtime types are not supported by the
  cleaned repository.
- Tracked deleted material remains recoverable from Git history. A pre-removal workspace snapshot
  also preserves modified, untracked, and generated material during the transition.

## Required verification

- No project, manifest, extension, source, test, documentation build, or CI job loads or resolves
  the retired package.
- PottsToolkit and CorePotts each load and pass their independent test suites.
- The integration suite passes with only the admitted ModelingToolkit and unit adapters.
- Repository documentation builds without links to the removed package manual.
