# Potts.jl specifications

The accepted [project charter](project-charter.md) is the normative project
authority. A more specific accepted decision applies only to the scope it
names. Implementation and tests are evidence; they do not silently redefine a
scientific contract.

## Current contracts

- [Project charter](project-charter.md)
- [Correctness and contract stabilization](correctness-and-contract-stabilization.md)
- [Package identity and independent repository cutover](package-identity-and-repository-separation.md)
- [LocalMath](localmath.md)
- [LocalMath effortless explicit setup](localmath-effortless-setup.md)
- [LocalMath descriptor and relation ergonomics](localmath-descriptor-and-relation-ergonomics.md)
- [LocalMath semantic-preserving physical fusion](localmath-physical-fusion.md)
- [LocalMath private lifetimes and exact conflict lowering](localmath-private-lifetimes-and-conflicts.md)
- [LocalMath developer-experience completion](localmath-developer-experience-completion.md)
- [CorePotts compiler targeting LocalMath](corepotts-localmath-compiler.md)
- [State model](state-model.md)
- [Time and Monte Carlo steps](time-and-mcs.md)
- [Auxiliary and mechanical state](auxiliary-state-semantics.md)
- [Lifecycle](lifecycle.md)
- [Randomness and reproducibility](randomness-and-reproducibility.md)
- [Persistence](persistence.md)
- [Energy, proposals, acceptance, and trackers](energy-proposals-and-trackers.md)
- [Topology and spatial relations](topology-and-spatial-relations.md)
- [Cartesian surfaces, queries, and fields](cartesian-surface-queries-and-fields.md)
- [Reference engine semantics](reference-engine-semantics.md)
- [Numerical and cross-backend semantics](numerical-and-cross-backend-semantics.md)
- [Transition-kernel verification](transition-kernel-verification.md)
- [Published-model reproduction semantics](published-model-reproduction-semantics.md)
- [PottsToolkit authoring and API semantics](pottstoolkit-authoring-composition-and-api-semantics.md)
- [CorePotts public interfaces](corepotts-public-interface-semantics.md)
- [SciML interface semantics](sciml-interface-semantics.md)
- [Rule and model semantics](pottstoolkit-rule-and-model-semantics.md)
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
