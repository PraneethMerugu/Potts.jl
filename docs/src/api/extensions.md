# [Extension author reference](@id extension-author-reference)

CorePotts extension contracts are stable only where classified `stable_extension` by the Phase 13
inventory. PottsToolkit is still the preferred biological authoring interface.

## Choose the smallest extension point

| You are adding… | Extend | Validate with |
|:--|:--|:--|
| conservative Hamiltonian contribution | energy component protocol | `test_energy_component` |
| nonconservative proposal work | drive component protocol | `validate_drive_component` and algorithm tests |
| hard proposal veto | constraint component protocol | `validate_constraint_component` |
| acceptance-rate modification | kinetic modifier protocol | `validate_kinetic_modifier_component` |
| stateful mechanical term | mechanical component protocol | `validate_mechanical_component` |
| proposal generation | proposal-law protocol | `validate_proposal_component` |
| commit-coupled state tracking | tracker protocol | `test_tracker` |
| neighborhood or adjacency semantics | topology protocol | `test_topology` |
| scheduled behavior | event or lifecycle protocol | `test_event` and reconstruction tests |

Do not implement a lower-level protocol when a PottsToolkit declaration already expresses the
behavior.

## Declare the whole component contract

A downstream scientific component declares:

- semantic identity and version;
- required properties, relations, and observations;
- supported dimensions and backend capabilities;
- RNG namespace and streams, when stochastic;
- proposal contribution through the appropriate energy, drive, constraint, modifier, mechanical,
  tracker, topology, event, or lifecycle protocol;
- validation and conformance behavior.

## Required boundaries

Extensions must not mutate logical ownership or properties behind commit, read undeclared backend
storage, allocate hidden RNG streams, synchronize devices during observation, or infer stability
from an export.

Semantic RNG addresses use the registered namespace, operation, entity, and MCS. Persistence must
either serialize all continuation state through the canonical contract or reject checkpointing
explicitly.

## Executable review sequence

1. Define the smallest typed component.
2. Implement metadata, requirements, and validation.
3. Add a hand-checkable CPU fixture with a known local contribution.
4. Exercise invalid declarations and unsupported domain/backend combinations.
5. Pass the matching conformance helper and reconstruction test.
6. Add checkpoint coverage for every state variable or reject persistence explicitly.
7. Declare dimension and backend support conservatively.
8. Add device behavior only after the CPU semantics and resource manifest are fixed.
9. Add PottsToolkit lowering only after the CorePotts contract is stable.
10. Propose API classification; the project owner approves stable promotion.

An executable extension specification should name the type, semantic version, properties,
resources, RNG addresses, proposal contribution, commit behavior, observation surface,
persistence behavior, conformance commands, and evidence needed for each advertised backend.

The complete stable binding inventory is
`design/audits/phase-13-api-inventory.toml`. Names from the provisional Phase 14 allowlist remain
experimental.
