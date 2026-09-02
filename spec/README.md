# Potts.jl specifications

The accepted [project charter](project-charter.md) is the normative project
authority. A more specific accepted decision applies only to the scope it
names. Implementation and tests are evidence; they do not silently redefine a
scientific contract.

## Current contracts

- [Project charter](project-charter.md)
- [Correctness and contract stabilization](correctness-and-contract-stabilization.md)
- [Package identity and independent repository cutover](package-identity-and-repository-separation.md)
- [LocalMath specifications](../lib/LocalMath/spec/README.md)
- [CorePotts specifications](../lib/CorePotts/spec/README.md)
- [Cartesian surfaces, queries, and fields](cartesian-surface-queries-and-fields.md)
- [Published-model reproduction semantics](published-model-reproduction-semantics.md)
- [Potts authoring and API semantics](potts-authoring-composition-and-api-semantics.md)
- [SciML interface semantics](sciml-interface-semantics.md)
- [Rule and model semantics](potts-rule-and-model-semantics.md)
- [Decision records](decisions/README.md)

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
