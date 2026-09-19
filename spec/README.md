# Potts.jl specifications

The accepted [project charter](project-charter.md) is the normative project
authority. A more specific accepted decision applies only to the scope it
names. Implementation and tests are evidence; they do not silently redefine a
scientific contract.

## Current contracts

- [Project charter](project-charter.md)
- [Correctness and contract stabilization](correctness-and-contract-stabilization.md)
- [Package identity and independent repository cutover](package-identity-and-repository-separation.md)
- [LocalMath specifications](https://github.com/PraneethMerugu/LocalMath.jl/tree/main/spec)
- [CorePotts specifications](https://github.com/PraneethMerugu/CorePotts.jl/tree/main/spec)
- [Cartesian surfaces, queries, and fields](cartesian-surface-queries-and-fields.md)
- [Published-model reproduction semantics](published-model-reproduction-semantics.md)
- [Potts authoring and API semantics](potts-authoring-composition-and-api-semantics.md)
- [SciML interface semantics](sciml-interface-semantics.md)
- [Rule and model semantics](potts-rule-and-model-semantics.md)
- [Decision records](decisions/README.md)

## Design vision

- [Ideal API vision](ideal_api_vision.md) — aspirational, non-normative direction
  with concrete scoped-authoring, scientific ownership, native coupling,
  lifecycle, numerical-policy and ordinary behavioral-test requirements.
- [Authoring and model-ecosystem PR plan](../design/authoring-and-model-ecosystem-plan.md)
  — feature ownership, dense coordinated changes, PottsModels tutorials and CI.
- [Consolidated PR dependency map](../design/consolidated-pr-dependency-map.md)
  — enumerated repository PRs, coordinated dependencies, coverage and count risks.
- [Compiler-contract chain amendment](../design/compiler-contract-chain-amendment.md)
  — user-approved G05C/R49/R50 scope and pressure-tested obligations across the
  chain; planned work, not an implementation or qualification claim.
- [End-state API overview and single-file examples](../design/authoring-api-overview.md)
  — semantic walkthroughs, not final syntax or currently runnable APIs.
- [Authoring design research](../design/authoring-design-research.md)
  — primary-source rationale, pitfalls and implementation uncertainties.

Some older interface documents contain superseded names alongside surviving
scientific requirements. The charter, accepted decision records, and the
current LocalMath contract take precedence for package identity, execution
architecture, and contributor workflow.

## Historical records

Development roadmaps, milestone specifications, audits, qualification reports,
and earlier architecture proposals are retained as design history. They do not
impose live execution modes, compatibility layers, machine allowlists, timing
thresholds, or development gates. Historical evidence is indexed under
`design/`; archived scripts live under `scripts/archive/`.

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** retain
their usual normative meanings.
