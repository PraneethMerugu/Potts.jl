# Published-Model Reproduction Semantics

Status: Accepted

## Scope

This document defines when Potts.jl documentation may describe a model as a reimplementation or
reproduction of a published model. It governs the Published Models section, its reusable Julia
model sources, validation programs, manifests, archived evidence, and release claims. It does not
require ordinary teaching examples to reproduce a paper.

## Content Classes

The documentation distinguishes three content classes:

- **Learn** teaches concepts in a guided sequence and MAY simplify mechanisms deliberately.
- **Examples** demonstrates focused or composed uses of the library and MAY be inspired by
  literature when that inspiration is cited.
- **Published Models** reimplements identified published work and is subject to every requirement
  in this document.

An Inspired Example MUST NOT appear as a published-model reproduction or support a claim that the
paper result has been reproduced.

## Source Record

Before implementation, every published model MUST have a versioned source record containing:

- the complete paper citation and persistent identifier;
- the exact figure, table, statistic, or described result being targeted;
- pinned supplementary material, source code, input data, and source-simulator versions when
  available;
- license and permitted-use information for code, data, figures, and media;
- the authority order used when the paper, supplement, code, and later author clarification
  disagree; and
- every unresolved ambiguity, inferred value, and unavailable input.

The original paper and supplement define scientific intent. Source code is implementation evidence,
not silent authority over a conflicting paper statement. A conflict MUST be recorded and resolved
explicitly or left visible as an ambiguity.

## Model Manifest

Each model MUST provide a machine-readable manifest sufficient to reconstruct and audit the run.
The manifest includes, as applicable:

- model and source-record identity;
- Potts.jl revision and semantic contract versions;
- domain, dimension, lattice spacing, topology, and boundary conditions;
- proposal, contact, surface, query, and field relations independently;
- component laws, parameters, units, and parameter provenance;
- cell types, counts, geometries, initial state, and initialization checksum;
- algorithm, normalized-MCS attempt budget, precision, backend, and device capability;
- accepted-copy, per-MCS, lifecycle, field, auxiliary-state, and staged-protocol update order;
- RNG profile, semantic seed identities, ensemble identities, and replicate count;
- observation schedule, observables, analysis program, and output schema;
- validation targets, tolerances, stopping rules, and registered exclusions;
- deviations from the source, unresolved ambiguities, and fidelity status; and
- evidence archive identifiers, reviewer identity where applicable, and review date.

Defaults that affect a reproduced result MUST be materialized in the manifest. A default inherited
from the library is not sufficient provenance.

## Fidelity Dimensions

Fidelity is reported across separate dimensions:

1. **Mechanistic fidelity**: the same modeled entities, interactions, state variables, and
   biological update laws are represented.
2. **Execution fidelity**: attempt normalization, spatial roles, update order, splitting,
   discretization, precision, initialization, and observation timing match the source record.
3. **Parameter fidelity**: values, units, distributions, and calibration procedures match or have a
   recorded transformation.
4. **Output fidelity**: the same observable and analysis definition is used.
5. **Result fidelity**: the registered qualitative or quantitative target passes.

One summary label MUST NOT conceal a weaker dimension. Every deliberate difference and every source
ambiguity appears beside the result and in the manifest.

## Evidence Status

The permitted public statuses are:

- **Inspired Example**: related to a paper but not a reproduction; permitted only in Learn or
  Examples.
- **Reimplementation in Progress**: source and mechanism work is incomplete or validation has not
  passed; it cannot support a release or paper claim.
- **Qualitative Reproduction**: the registered qualitative target passes and the source record
  justifies qualitative rather than quantitative validation.
- **Quantitative Reproduction**: the preregistered quantitative target passes using the required
  ensemble and analysis.

`Author Reviewed` is an orthogonal badge. It states that a named author or domain collaborator
reviewed the recorded scope and evidence; it MUST NOT upgrade a failed or incomplete reproduction.

The initial published-model portfolio targets Quantitative Reproduction wherever the source record
provides a quantitative endpoint. A failed quantitative target remains a failed reproduction study
and MUST NOT be downgraded after the run to obtain a passing qualitative label.

## Validation Plan

Before final runs, each reproduction MUST register:

- the primary result and any secondary results;
- exact or statistical comparison method;
- tolerances justified by the scientific effect size, source uncertainty, and numerical contract;
- ensemble size, stopping rule, exclusions, and multiplicity treatment;
- required source-simulator or digitized-paper baseline;
- backend and precision scope; and
- the conditions under which the study is inconclusive.

Implementation debugging MAY use exploratory runs. Exploratory data MUST NOT be substituted for the
registered final study without declaring a new version of the validation plan.

When a paper provides insufficient information for an exact match, the reproduction reports the
maximum supported fidelity and performs sensitivity analysis for consequential assumptions. It
MUST NOT invent a unique source configuration.

## Library Boundary

Reusable scientific behavior belongs in CorePotts or Potts. Model source MAY assemble
components, encode paper parameters and schedules, and define paper-specific analyses, but MUST NOT
implement a private proposal engine, hidden state transition, field solver, lifecycle path, or
backend-specific scientific law.

A missing mechanism is classified before implementation:

- use an existing stable protocol when it expresses the source without semantic distortion;
- add an additive, versioned protocol when the behavior is reusable and does not change a frozen
  contract;
- create an experimental protocol only when the published model is explicitly excluded from
  release claims; or
- require an explicit release decision when a frozen contract must change.

Every new stable mechanism starts with an ordinary sequential CPU reference implementation and
conformance tests. Backend support is claimed only after applicable real-hardware qualification.

## Reproducible Execution and Evidence

A published model MUST run from a clean, pinned environment through a documented command. Fast
deterministic or bounded numerical checks run in ordinary CI. Full ensembles and expensive
rendering MAY run in scheduled or release tiers, but their raw results, environment reports,
manifests, analysis programs, and output checksums MUST be content-addressed and retrievable.

Figures, tables, and animations are generated from archived machine-readable results. A manually
edited output cannot serve as reproduction evidence.

Checkpoint/restart MUST preserve the applicable model state, semantic time, RNG identity, dynamic
fields, auxiliary state, relationship state, and staged-protocol position. A resumed run must meet
the accepted continuation contract before it can contribute to a reproduction ensemble.

## Page Requirements

Every Published Models page MUST show:

- citation and target result;
- biological question and modeled mechanism;
- source and license provenance;
- complete runnable command and pinned environment;
- algorithm, seed profile, precision, backend, and support limitations;
- parameter and initialization access;
- fidelity table and visible deviations;
- registered validation method and result;
- links to reusable source, manifest, raw evidence, and generated outputs; and
- evidence status plus author-review status.

The page MAY explain the model progressively, but explanatory simplification MUST NOT change the
executable reproduction hidden behind the page.

## Portfolio Completion

The selected release portfolio is complete only when every model:

1. has a closed source and requirements audit;
2. uses accepted or explicitly scoped experimental mechanisms;
3. passes its registered release-status validation;
4. runs from the clean documentation or reproduction environment;
5. has retrievable evidence and reproducible outputs; and
6. exposes all deviations and backend limitations.

Removing, replacing, or lowering the target status of a selected model requires an explicit
owner-approved scope amendment and claim-impact assessment.
