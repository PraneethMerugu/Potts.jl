# [Canonical structure and semantic identity](@id canonical-identity)

> **Support level:** qualified internal-beta identity contracts.

Identity is layered because “the same model” is not one question.

| Identity | Changes when |
|---|---|
| Scientific family/version | admitted scientific meaning changes |
| Documentation profile | teaching extent, seed, or runtime bound changes |
| Semantic model fingerprint | stores, actors, parameters, ports, or schedules change |
| Canonical IR fingerprint | normalized structure changes |
| Execution-plan fingerprint | compiled execution policy changes |
| Problem fingerprint | initial state, interventions, observations, horizon, or seed changes |
| Run identity | one execution instance is created |
| Checkpoint identity | persisted logical state or clocks change |

Canonical encodings are deterministic and construction-order invariant for
semantically unordered declarations. They never rely on object addresses,
anonymous closure identity, dictionary iteration order, ACSet row order, or
display formatting. A component's concrete Julia type name is diagnostic and
dispatch information, not scientific identity. Renaming a reconstructable type
without changing the mounted name, kind, semantic version, semantic parameters,
ports, capabilities, schedule, dependencies, domain, or continuation contract
preserves the semantic fingerprint.

`semantic_fingerprint(model)`, `ir_fingerprint(lower(model))`, and
`plan_fingerprint(compile(model))` should be recorded separately. Equality at
one layer does not imply equality at another. In particular, canonical IR may
retain the concrete type as reconstructable implementation metadata, so a type
rename can preserve semantic identity while changing the IR fingerprint.

## Migration rule

Persistence readers validate their schema identity and compatible semantic
context. A new semantic model version does not silently claim an old
checkpoint. Migration must be explicit, testable, and trace the old and new
meaning.

ProcessBigraphs 0.6 uses authoring contract
`process-bigraph-authoring-v2`. It removes concrete Julia component type names
from semantic model fingerprints. Semantic archives written under
`process-bigraph-authoring-v1` are rejected with a migration-required
diagnostic; they are not silently relabeled because every affected fingerprint
must be recomputed and reviewed.

**Next:** [Logical state, effects, and reconciliation](@ref state-effects-reconciliation).
