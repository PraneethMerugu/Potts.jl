# [Compose a biological model](@id build-model)

PottsToolkit separates a reusable biological model from the domain and initial condition on which
it will run.

## Declarations

Most models begin with:

1. one or more `Medium` and `CellType` identities;
2. energies, drives, constraints, fields, properties, or lifecycle declarations;
3. a `PottsModel` that assembles them.

The constructor accepts declarations in any order. Normalization resolves dependencies and
produces a canonical model; declaration order does not change the semantic fingerprint.

```@example build-model
using PottsToolkit

medium = Medium(:medium)
first_population = CellType(:first_population)
second_population = CellType(:second_population)
model = PottsModel(
    medium,
    first_population,
    second_population,
    Volume(
        first_population => (target = 16, strength = 2),
        second_population => (target = 16, strength = 2),
    ),
    Adhesion(
        (medium, medium) => 0,
        (medium, first_population) => 8,
        (medium, second_population) => 8,
        (first_population, first_population) => 2,
        (second_population, second_population) => 2,
        (first_population, second_population) => 15,
    ),
)
normalized = normalize(model)
fingerprint = semantic_fingerprint(normalized)

@assert isvalid(model)
@assert semantic_fingerprint(model) == fingerprint
result = (; model, normalized, fingerprint, report = validate(model))

(isvalid(result.model), length(result.model.declarations), result.fingerprint)
```

The
[`canonical source`](https://github.com/PraneethMerugu/Potts.jl/blob/main/docs/models/tutorials/build_model.jl)
contains the complete pairwise contact table.

## Validate before lowering

`validate(model)` returns all discoverable diagnostics. Use it in exploratory code; use
`normalize(model)` or `PottsProblem(...)` when invalid input should stop execution.

```@example build-model
(isvalid(result.report), length(result.report.diagnostics))
```

`explain`, `dependencies`, `capabilities`, and `provenance` expose progressively deeper views of
the normalized model without requiring access to engine storage.

## Identity and provenance

Use `semantic_fingerprint(model)` for the normalized scientific model identity. Use
`execution_fingerprint` when algorithm and backend choices are part of the identity.
`semantic_manifest` records the independent authoring, normalized-IR, and fingerprint contract
versions.

Fingerprints identify exact inputs under a versioned canonicalization contract. They do not by
themselves prove that two algorithms have the same kinetics or scientific guarantees.

The model remains independent of lattice size, initial cells, capacity, seed, and run duration.
[Domains and initialization](@ref domains-and-initialization) adds those choices explicitly.

## Level 1 and advanced extensions

Level 1 declarations cover the normal biological authoring path. `CorePotts` owns lower-level
scientific components and extension protocols. Move down a level only when the required behavior
cannot be expressed as a PottsToolkit declaration, and preserve validation, capabilities, semantic
RNG ownership, persistence, and backend reporting in the extension.
