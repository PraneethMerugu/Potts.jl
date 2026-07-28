# [Cellular Potts concepts](@id cellular-potts-concepts)

A Cellular Potts model represents extended cells as connected sets of lattice sites. Every site is
owned by a finite cell or by a medium domain. A copy attempt proposes changing one site's owner;
energies, drives, constraints, and the selected algorithm decide whether that proposal commits.

## The four objects to keep separate

1. A `PottsModel` declares biology and mechanics.
2. A `CartesianDomain` declares lattice geometry, spacing, boundaries, and obstacles.
3. A `PottsProblem` binds a model to an initial layout, capacity, seed, and time span.
4. An algorithm declares proposal scheduling, temperature, and execution semantics.

This separation lets one model run in several domains without hiding changes to initialization or
execution.

## Ownership and energy

Finite-cell identity is not a raw label. The engine tracks cell ID, generation, and type so a
retired slot cannot be confused with a later biological cell. The Hamiltonian may include volume,
surface, elongation, contact, and other supported terms. Nonconservative work such as chemotaxis is
reported separately from energy.

For a proposal with conservative change ``\Delta H``, temperature controls acceptance of
energetically unfavorable moves. Temperature is a model-algorithm parameter, not physical
temperature unless a study supplies an independent calibration.

## Monte Carlo steps

An MCS is the selected algorithm's normalized scheduling unit. `SequentialCPM` performs exactly one
independent recipient selection per mutable lattice site. Other algorithms have their own
documented normalization. An MCS is not automatically seconds, minutes, or cell-cycle time.

```@example cellular-potts-concepts
concepts = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials", "cellular_potts_concepts.jl"))
(concepts.lattice_sites, concepts.occupied_sites, concepts.temperature,
    concepts.guarantee)
```

The `unqualified` guarantee label does not mean unusable. It means equilibrium, kinetic, or other
stronger scientific equivalence has not been claimed. Compatibility, successful execution, and
scientific qualification remain separate.

## A useful mental model

```text
declarations → validated problem → proposals → accepted commits → observations
```

Nothing downstream should reach backward and mutate authoritative state. Analysis and
visualization consume explicit observations or complete host snapshots. The next page applies
these concepts to a relaxing cell.
