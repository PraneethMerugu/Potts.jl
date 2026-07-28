# [Extension author reference](@id extension-author-reference)

CorePotts extension contracts are stable only where classified `stable_extension` by the Phase 13
inventory. PottsToolkit is still the preferred biological authoring interface.

## Component protocol

A downstream scientific component declares:

- semantic identity and version;
- required properties, relations, and observations;
- supported dimensions and backend capabilities;
- RNG namespace and streams, when stochastic;
- proposal contribution through the appropriate energy, drive, constraint, modifier, mechanical,
  tracker, topology, event, or lifecycle protocol;
- validation and conformance behavior.

Use the matching test helper before integrating:

| Family | Conformance entry point |
|:--|:--|
| Energy | `test_energy_component` |
| Drive | `test_algorithm` plus `validate_drive_component` |
| Constraint | `validate_constraint_component` |
| Kinetic modifier | `validate_kinetic_modifier_component` |
| Mechanical component | `validate_mechanical_component` |
| Proposal law | `validate_proposal_component` |
| Tracker | `test_tracker` |
| Topology | `test_topology` |
| Event | `test_event` |

## Required boundaries

Extensions must not mutate logical ownership or properties behind commit, read undeclared backend
storage, allocate hidden RNG streams, synchronize devices during observation, or infer stability
from an export.

Semantic RNG addresses use the registered namespace, operation, entity, and MCS. Persistence must
either serialize all continuation state through the canonical contract or reject checkpointing
explicitly.

## Minimal review sequence

1. Define the smallest typed component.
2. Implement metadata, requirements, and validation.
3. Implement CPU behavior and the applicable proposal contribution.
4. Pass conformance and reconstruction tests.
5. Declare backend and dimension support conservatively.
6. Add authoring lowering only after the CorePotts contract is stable.
7. Propose API classification; the project owner approves stable promotion.

The complete stable binding inventory is
`design/audits/phase-13-api-inventory.toml`. Names from the provisional Phase 14 allowlist remain
experimental.
