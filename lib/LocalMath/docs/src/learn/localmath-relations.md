# [LocalMath relations and storage](@id localmath-relations)

A Relation answers one mathematical question: for each item in its domain,
which bounded items in its codomain may be read or published? The relation
descriptor owns that meaning. Storage, when required, supplies its concrete
endpoints without becoming the descriptor.

## Choose the relation from the mathematics

| Scientific intent | LocalMath form | Bind relation storage? |
|:--|:--|:--|
| Same-item read or write | `field[i]` | No; identity is authored automatically |
| Cartesian interior stencil | `interior(space, width)` | No; affine mappings are authored automatically |
| Cartesian periodic stencil | `periodic(space)` | No; periodic boundary mappings are automatic |
| Fixed mesh incidence or graph endpoints | `FixedRelation` | Yes |
| Endpoint keys held in a Field | `IndexRelation` | No; bind the key Field |
| Optional Field-held key | `IndexRelation(...; optional=true)` | No; use `samples` for absent lanes |
| Compose bounded mappings | `compose` | Bind only stored factors |
| Select a base mapping through an injection | `SelectedRelation` | Bind only stored factors |
| Source mask over another relation | `MaskedRelation` | Bind the Boolean mask Field and stored factors |
| Reverse adjacency | `InverseRelation` | Yes |
| Runtime-keyed publication | `RuntimeRelation` | No; keys are evaluator results |
| Mutable bounded incidence | `PackedRelation` | Yes, through `MutableRelationStorage` |
| Exterior ghost mapping | `BoundaryRelation(..., GhostBoundary(...))` | Yes, for the ghost mapping |

Ordinary stencil authors normally write no relation constructor. The equation
supplies identity or Cartesian topology directly:

```julia
cells = Space((nx, ny))
u = Field(cells, Float32)
residual = Field(cells, Float32)

law = @localmath (i, j) ∈ interior(cells, 1) begin
    residual[i, j] =
        u[i - 1, j] + u[i + 1, j] +
        u[i, j - 1] + u[i, j + 1] - 4f0 * u[i, j]
end
```

## Fixed mesh and graph topology

Declare the mathematical direction and exact lane bound independently of the
endpoint array:

```julia
elements = Space(element_count)
nodes = Space(node_count)
values = Field(nodes, Float32)
residual = Field(nodes, Float32)
incidence = FixedRelation(elements => nodes; degree=4)

law = @localmath element ∈ elements begin
    local_values = values[incidence(element)]
    residual[incidence(element)] += element_residual(local_values)
end

prepared = @prepare (law; backend) begin
    values = nodal_values
    residual = allocate(0f0)
    incidence = incidence_endpoints
end
```

`incidence_endpoints` is lane-major with at least `degree` lanes and one entry
per source item. A direct array represents a full-degree relation. Optional
lanes use `(; endpoints, counts)`, where `counts` has one bounded integer per
source item.

## Field-keyed indirection

`IndexRelation` is computed from an integer Field and therefore receives no
relation binding:

```julia
particles = Space(particle_count)
cells = Space(cell_count)
cell_key = Field(particles, Int32)
mass = Field(cells, Float32)
particle_cell = IndexRelation(cell_key => cells)

law = @localmath particle ∈ particles begin
    mass[particle_cell(particle)] += particle_mass(particle)
end

prepared = @prepare (law; backend) begin
    cell_key = particle_cell_keys
    mass = allocate(0f0)
end
```

Strict invalid keys fail the transaction. With `optional=true`, invalid keys
are absent lanes and must be consumed through sample-aware access or optional
publication.

## Composition and selection

`compose(a, b)` applies bounded relations left-to-right. `SelectedRelation`
uses one relation as an injection into another relation's domain. Both are
computed descriptors: bind their stored factors, not the composed result.
Their display and `LocalMath.inspect(law; level=:relations)` retain factor
identity and total degree.

## Mutable packed topology

`PackedRelation` is intended for domain compilers that own relationship
generation, validation, and transaction meaning. Its runtime state remains
canonical packed storage on CPU and GPU:

```julia
relationships = PackedRelation(
    owners => records;
    degree_bound=max_degree,
    capacity=owner_count,
)

prepared = prepare(law,
    relationships => LocalMath.MutableRelationStorage(
        packed_storage;
        generation,
        status,
    ),
    generated_bindings...;
    backend,
)
```

Ordinary models should not select `PackedRelation` merely because their
topology is stored in an array. Immutable mesh and graph topology uses
`FixedRelation`.

## Discover requirements before preparation

At the REPL, display the law or inspect its relation projection:

```julia
display(law)
LocalMath.inspect(law; level=:relations)
```

The display distinguishes computed and stored Relations. If preparation is
incomplete, LocalMath reports every missing descriptor in encounter order.
Malformed fixed topology reports the expected degree/domain layout and the
actual array shape without changing or adapting caller storage.
