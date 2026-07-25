# Phase 14.0 Corpus, Sources, and Requirements Audit

Status: Complete; six-model portfolio frozen and Phase 14.0 exit gate passed

Date: 2026-07-24

Architecture supersession: This audit's source portfolio, capability requirements, and closure
evidence remain accepted. Its registry v1 contract decomposition is historical and has been
replaced by [Decision 0031](../../spec/decisions/0031-phase-14-single-semantic-kernel.md) and
[Contract Registry v2](../../spec/phase-14-contract-registry-v2.toml).

This audit closes Phase 14.0 under
[Decision 0029](../../spec/decisions/0029-phase-14-model-driven-capability-and-documentation-policy.md)
and the
[Published-Model Reproduction Semantics](../../spec/published-model-reproduction-semantics.md).
It records evidence, not reproduction claims. Every selected model remains
`Reimplementation in Progress`.

The machine-readable records are:

- [accepted source records](phase-14-model-source-records-v1.toml);
- [source closure, license dispositions, and sensitivity envelopes](phase-14-source-closure-v1.toml);
- [model-to-capability matrix](phase-14-model-capability-matrix-v1.toml);
- [D9 work-item registry](phase-14-d9-work-items-v1.toml); and
- [Morpheus continuous-semantics compatibility matrix](phase-14-morpheus-continuous-semantics-v1.toml).

The candidate D9 public surface and coupling semantics are recorded in the
[Phase 14 Coupled Dynamics and ModelingToolkit API](../../spec/phase-14-coupled-dynamics-api.md).
Its individual contracts deliberately remain Provisional until their Phase 14.1 prototypes and
conformance gates pass. The machine-readable
[historical Phase 14 contract registry v1](../../spec/phase-14-contract-registry-v1.toml) tracks every candidate
contract, capability row, source model, persistence obligation, backend claim, and acceptance gate.

The registry is backed by focused candidate specifications for
[execution](../../spec/phase-14-coupled-execution-semantics.md),
[dynamic state](../../spec/phase-14-dynamic-state-semantics.md),
[spatial roles and attempt budgets](../../spec/phase-14-spatial-and-attempt-semantics.md),
[cell and field dynamics](../../spec/phase-14-cell-and-field-dynamics-semantics.md),
[continuous systems and Morpheus compatibility](../../spec/phase-14-continuous-systems-and-morpheus-compatibility.md),
[relationships and lifecycle](../../spec/phase-14-relationship-and-lifecycle-semantics.md), and
[persistence and observations](../../spec/phase-14-coupled-persistence-and-observation-semantics.md).

## Current conclusion

The six-model release portfolio is frozen and Phase 14.0 is complete. Three records have a pinned,
transcribed paper-associated implementation:

- Wortel Act-CPM: Zenodo `v1.0.0` / Git
  `c980498712e4f4401aacd7689009f2fcbf250d2e`, MIT;
- Wang collective tumor migration: Zenodo `paper-v0` / Git
  `60ebcf013aafefdff39ebe566114ee79f2a6e54d`, CC-BY-4.0; and
- Shirinifard CNV scenario ID 38: PLOS Text S6 checksum
  `fc4884fa62b40a8c999b33663dd8a3eccdae5f3fc11dc579892e7e64e747da4d` and
  CompuCell3D 3.4.2.

The Graner--Glazier and Mombach sorting papers and the Merks vasculogenesis paper lack recoverable
original programs. Phase 14.0 closes those records without inventing a unique configuration:
each has a named result, authority order, explicit ambiguity list, preregistered sensitivity axes,
failure rule, clarification questions, license disposition, and claim boundary. These limitations
remain later reproduction gates; they are no longer unowned audit work.

## Candidate release portfolio

| Record | Flagship coverage | Primary target | Source maturity | Freeze state |
| --- | --- | --- | --- | --- |
| Graner--Glazier 1992 sorting | Glazier | Figure 2 boundary-length kinetics | Paper only | frozen with `gg1992-source-envelope-v1` |
| Mombach et al. 1995 sorting | Glazier | Figure 4 experiment/simulation kinetics | Paper only | frozen with `mombach1995-source-envelope-v1` |
| Merks et al. 2006 vasculogenesis | Glazier | Figure 5 lacunae and branch points | Open paper; original code unavailable | frozen with `merks2006-source-envelope-v1` |
| Wortel et al. 2021 Act-CPM | Wortel | Figure 2B--D speed/persistence and mode map | Pinned code and analysis | frozen; source transcribed |
| Shirinifard et al. 2012 CNV | Glazier and Jiang | Figure 7 scenario-ID-38 ensemble | Pinned scenario source | frozen; source transcribed with foreign-runtime gates |
| Wang et al. 2025 tumor migration | Jiang | Figure 3 migration modes and parameter map | Pinned code, data, and analysis | frozen; source transcribed with foreign-runtime gates |

This portfolio intentionally contains two sorting models. The 1992 model anchors the foundational
two-dimensional claim; the 1995 model adds a quantitative experiment comparison, unequal cell
sizes, three dimensions, and fluctuation-dependent arrest. If Phase 14 scope must shrink, removing
one is an owner-visible claim reduction rather than an invisible implementation shortcut.

## Source pinning results

### Graner--Glazier sorting

The paper specifies a two-dimensional next-nearest-neighbor CPM, temperature 10, area strength 1,
the five reported contact energies, and 16 lattice-site attempts per MCS. Figure 2 is a stronger
primary result than the familiar snapshots because it names boundary observables and a time
interval. The exact lattice, cell population, target area, boundary conditions, replicas, seeds,
and raw values are unavailable in the audited record.

Authority: paper, then author clarification. Later sorting demonstrations are not substitutes for
the 1992 source implementation.

### Mombach three-dimensional sorting

The paper provides a bounded 100-cubed case, unequal target volumes, high- and low-temperature
conditions, and experimental/simulation boundary trajectories. It does not yet give a complete,
unambiguous executable specification. In particular, reported surface tensions must not be copied
into a Potts contact matrix without proving the conversion.

Authority: paper, then author clarification. Figure digitization may create a comparison baseline,
but cannot recover missing execution semantics.

### Merks vasculogenesis

The paper supplies the lattice scale, 282-cell initialization region, physical MCS mapping,
morphogen diffusion and decay order of magnitude, elongation mechanism, and quantitative Figure 5
ensemble. The original simulator and exact image-analysis programs were not found. Later Tissue
Simulation Toolkit code can help locate questions, but cannot silently define the 2006 model.

Authority: paper equations, original implementation if recovered, then author clarification.

### Wortel Act-CPM

The archived `2020-ucsp` release pins the simulation and figure programs. The primary 2D source
uses a 150-by-150 periodic field, one cell, `T=20`, a 500-MCS burn-in, a 50,000-MCS measurement,
51 explicit activity-parameter pairs, 30 seeded simulations per pair, output every 5 MCS, and six
analysis groups of five tracks. The archived aggregate table and every defining source file have a
registered checksum. The moving repository head is not the baseline.

Authority: paper and supplement for intent, Zenodo `v1.0.0` for implementation evidence, then
author clarification.

### Shirinifard CNV

PLOS Text S6 contains the CompuCell3D source, custom oxygen solver, and retinal input for adhesion
scenario ID 38. The archive fixes a 40-by-40-by-35 domain, 3-micrometer voxels, periodic x/y and
no-flux z, source seed 498377 for simulation 902, 146,000 MCS, three field families, VEGF2
subcycling 12 times per MCS, and the Python lifecycle/relationship program. Figure 7's other nine
seed identities remain unavailable and therefore have a registered replacement-ensemble policy.
The full Table 7 classification remains a stretch target.

Authority: paper tables and Text S3 for intent, Text S6 for implementation evidence, then
CompuCell3D 3.4.2 behavior and author clarification.

### Wang collective tumor migration

The `paper-v0` archive resolves to Git commit
`60ebcf013aafefdff39ebe566114ee79f2a6e54d` and includes the CompuCell3D model, parameter-scan
driver, geometric feature calculation, two-step clustering, saved transforms, and Figure 3 data.
The source fixes 231 combinations—21 focal strengths and 11 protrusion forces—50 repeats per
combination, and analysis at MCS 90 and 270. The XML identifies CompuCell3D 4.2.5 and uses distinct
orders for proposal, contact, focal activation, focal search, field, and cell-neighbor queries.
The registered Python order and frequencies make centroid history, cell ODE state, field uptake,
ten-MCS focal-link retuning, neighbor polarity alignment, and Hill-scaled protrusion drive explicit.
The [accepted order audit](phase-14-wang-order-audit.md) and exact CompuCell3D 4.2.5 runtime oracle
close built-in scheduler placement. They also expose a paper/source discrepancy: Equation 11 says
`x(t)-x(t-5)`, while the source appends `x(t)` and selects `[-5]`, yielding `x(t)-x(t-4)`.
Missing foreign RNG seeds remain an explicit later reproduction gate.

Authority: paper and supplement for intent, Zenodo `paper-v0` for implementation evidence,
CompuCell3D 4.2.5 for simulator behavior, then author clarification.

## Adversarial capability result

The corpus does not require a broad rewrite of the Phase 13 core. It requires a small set of
versioned dynamic-state protocols and exact authoring access to spatial and time semantics:

1. independent spatial-role relations;
2. a separately identified source-attempt schedule;
3. accepted-copy site history;
4. evolving fields and cell-field coupling;
5. typed cell state, vector history, and ordered per-MCS dynamics;
6. dynamic relationship graphs;
7. degradable lattice structures and state-dependent lifecycle programs;
8. explicit staged protocols; and
9. paper observables and archival analyses.

The matrix makes a useful architectural distinction. Geometry, parameter assembly, and final paper
analysis stay with published-model source. Hidden state transitions, solvers, relationship mutation,
and accepted-copy behavior cannot.

## Freeze-impact assessment

No selected model currently justifies changing a frozen Phase 13 meaning.

- `SequentialCPM` remains exactly `N` attempts per MCS. Source-specific budgets require a new
  algorithm or typed attempt-schedule identity. Mutating the existing algorithm would be an
  incompatible D10 action.
- Fixed focal-point springs remain fixed. Dynamic relationships require a distinct component and
  state contract.
- Immutable sampled fields remain valid. Evolving fields add a solver/splitting contract rather
  than changing snapshot sampling.
- Existing component meanings, including Elongation, are audited for equivalence before reuse.
  A mismatch produces a new versioned law; it does not redefine the existing component.
- PottsToolkit's present first-shell defaults remain defaults. Explicit spatial-role authoring is
  additive and must be materialized in manifests.

The accepted D10 classification is recorded in
[Decision 0030](../../spec/decisions/0030-phase-14-coupled-dynamics-and-freeze-impact.md).
The registry and focused D9 specifications name every public identity and freeze effect. Decision
0030 accepts the additive architecture without pretending that its Provisional D9 contracts are
implemented or qualified.

## Registered Phase 14.1 chunks

| Chunk | Vertical slice | First proving model | Entry dependency |
| --- | --- | --- | --- |
| 14.1-A | spatial roles, source attempt schedule, component equivalence | Graner--Glazier | sorting source questions plus D9 time/spatial semantics |
| 14.1-B | accepted-copy site state and decay | Wortel | pinned Figure 2 transcription plus D9 auxiliary-state semantics |
| 14.1-C | evolving fields and cell coupling | Merks, then Wang/CNV | solver choice and D9 splitting semantics |
| 14.1-D | cell history/ODE state and dynamic relationships | Wang | pinned source update-order transcription |
| 14.1-E | degradable structures and state-dependent lifecycle | CNV | scenario-ID-38 minimum mechanism audit |
| 14.1-F | staged protocols, observations, manifests, and restart | one complete model slice | D11-shaped observation definitions, without final tolerances yet |
| 14.1-G | continuous-system language and Morpheus semantic compatibility | Morpheus integrate-and-fire, cell-cycle, rule, delay, mapper, and field microfixtures | focused continuous-system D9 contract and accepted D10 timed-lifecycle classification |

The chunk order is a risk order, not permission to build all abstractions up front. Each stable
capability must first complete one CPU reference model slice and then backend-resident Metal and
ROCm execution through lowering, inspection, persistence, restart, residency, and bounded
validation under Decision 0032.

## Phase 14.0 exit-gate evidence

1. **Portfolio and target approval — passed.** The project owner's completed interview selected A
   for all portfolio and fidelity questions and the owner explicitly directed completion of Phase
   14.0. All six records are `portfolio_status = "frozen"` and have stable validation-target IDs.
2. **Paper-only source closure — passed.** Graner--Glazier, Mombach, and Merks each have a registered
   sensitivity envelope, failure rule, clarification questions, authority order, and claim limit in
   [source closure v1](phase-14-source-closure-v1.toml).
3. **Pinned-source transcription — passed.** Wortel, CNV, and Wang have exact source revisions,
   defining-file checksums, scan/replicate schedules, execution order, field behavior, and residual
   foreign-runtime gates. Missing source seeds remain explicit rather than invented.
4. **License disposition — passed.** Every record now says whether source/assets are citation-only,
   fetched by checksum, or reusable with attribution. The repository policy chooses clean-room
   implementation and generated outputs; no third-party artifact is silently vendored.
5. **Mechanism traceability — passed.** Every named paper mechanism maps explicitly to one or more
   capability IDs, and every model capability is bidirectionally represented in the source record
   and capability matrix. Every additive/stable extension is registered in at least one D9
   contract, except existing frozen components, source-law equivalence, and paper-specific
   initialization, which are explicitly classified outside new contract creation.
6. **D9 ownership — passed.** [D9 work items v1](phase-14-d9-work-items-v1.toml) assigns every missing
   semantic family a specification, contracts, capabilities, owner, first proving model,
   conformance plan, persistence impact, API layer, backend claim, implementation chunk, and D10
   classification.
7. **D10 assessment — passed.** [Decision 0030](../../spec/decisions/0030-phase-14-coupled-dynamics-and-freeze-impact.md)
   accepts the additive architecture and names the stop condition for any implementation that
   would mutate a frozen Phase 13 meaning.

Phase 14.1 may now begin one vertical slice at a time after that slice's Provisional D9 contract is
accepted through its registered CPU, Metal, and ROCm prototype and conformance evidence. The
Wortel CPU, Metal, and ROCm gate passed on 2026-07-25; Wang is open and its exact execution-order
audit is accepted.
This closure does not claim a published-model reproduction, claim Morpheus parity, or add
Mermaid.jl to the roadmap. Automatic MorpheusML import remains optional after hand-authored
semantic parity.
