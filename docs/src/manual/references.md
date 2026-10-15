# [Cell references and geometry helpers](@id manual-references)

A model often needs to read one cell from another. A nucleus reads its cytoplasm, a cell
reads the partner it is bonded to, a protrusion reads the centroid of the body it belongs
to. This page covers the names that do this. A **cell reference** names a cell, and
**geometry helpers** measure between cells.

## Which cell a name means

The names for cells and sites depend on where an expression is evaluated:

| Name | Means | Where |
|---|---|---|
| `id` | the current cell | cell scope (updates, `@observed`, cell energies) |
| `owner`, `owner′` | the cell at a site, at the other site of a contact pair | site scope, contact terms |
| `source`, `target` | the sites of a copy: `source` spreads into `target` | drives, constraints, on-copy updates |
| `new`, `old` | the cells of a copy: `new` owns `source` and gains `target`, `old` loses it | drives, constraints, on-copy updates |
| a `CellRef` variable, `sibling(…)`, `root(…)` | another cell, by reference | see below |

The medium is cell 0, and so is "no cell". When you test whether a cell is the medium,
compare its kind with the medium's name rather than comparing the cell with 0. Write
`kind[old] == medium` instead of `old == 0`: the kind test says what it means, and it stays
correct if the medium is renamed or the cell is a reference.

## References: `CellRef`

A cell variable declared `::CellRef` holds the number of another cell:

```julia
@variables begin
    partner(cell)::CellRef            # 0, the default, is no reference
end
```

A reference is read through indexing. `x[partner]` is the cell variable `x` of the cell
`partner` names. The same works for `kind[partner]`, `volume[partner]` and
`birth[partner]`. Chains are allowed: `kind[partner[partner]]`. `alive(partner)` is `true`
when the referent owns at least one site. A reference compares with `==` against `id`,
another reference or 0.

A cell is alive while it owns a site. A reference to a dead cell, or the reference
0, reads as the medium:

- its kind is 0;
- its volume is 0;
- `birth` is 0;
- `alive` is `false`;
- every cell variable has its declared default.

At the MCS where cells are born or removed, every reference to a dead cell is reset to 0
before any slot is reused. A new cell never inherits a reference meant for the old one.
`birth[c]` is a serial number that a reused slot never repeats. Use it to tell whether
the cell you stored is still the same cell.

Daughters copy their parent's references. Updates write references with another
reference, `id`, `old`, `new`, `cluster`, a cell number, 0, or `ifelse` between these.

### Compartments: `sibling`, `members`, `root`

In a model with compartments (`cluster`, see [Energy](@ref manual-energy)), these sources
name the cells of a compartment cluster:

| Form | Meaning |
|---|---|
| `sibling(k)` | the alive member of kind `k` of the current cell's cluster (the cell itself if it is of kind `k`), or 0 |
| `sibling(c, k)` | the same for cell `c`, e.g. `sibling(owner, cytoplasm)` at a site |
| `root(cluster)` | the cluster's root cell, as a reference |
| `members(cluster)`, `members(cluster, k…)` | the fold domain of the cluster's alive cells (of kinds `k…`) |

```julia
@after_mcs begin
    nuc ~ sibling(nucleus)                                     # store the reference
    body_volume ~ sum(volume[m] for m in members(cluster))     # fold over the members
end
@observed nucleus_share(cell) ~ volume[sibling(nucleus)] / sum(volume[m] for m in members(cluster))
```

`sibling` and `members` scan the whole cluster. They are available between sweeps: in
updates, field equations, division conditions and rules, `@convert` and `@observed`. Copy
steps (energies, drives, constraints, on-copy updates) cannot use them. To read a sibling
during the copy step, store it in a `CellRef` variable after each MCS and read through
that variable.

### Where references can be read

- **Energies** can read a referent's static values only: cell variables, `kind`, `birth`
  and `alive`. They cannot read what a copy changes, such as `volume[partner]`, because
  ΔH would not see the change. That is an `ArgumentError` that names the alternative.
- **Drives and constraints** can read anything through a reference.
- **Between sweeps**, everything is available.

Every cell a copy reads through a reference joins that copy's claim set. So a model that
reads references in its drives stays exact under `CheckerboardCPM`. A model that reads
references only between sweeps adds nothing to the copy step.

## Geometry helpers

The helpers below work in lattice units. They use the same centroid convention as
`centroid(k)`: on a periodic axis the centroid is the circular mean, wrapped into
[1, L + 1), and on a hexagonal lattice it is embedded.

| Form | Meaning | Where |
|---|---|---|
| `centroid(c, k)` | coordinate `k` of the centroid of the cell `c` names; 0 for a dead cell or 0 | between sweeps (not energies, drives, constraints, on-copy) |
| `separation(a, b)` | the minimum-image vector `centroid(a) − centroid(b)` (N components) | as `centroid(c, k)` |
| `minimum_image(d, k)` | `d` wrapped to the image nearest 0 on axis `k` (`d` itself on a closed axis) | everywhere, energies and drives included |
| `integral(x; over = cluster)` | the site expression `x` summed over the sites of the cluster's alive members | as `integral(x)` |

`k` is a literal axis: 1, 2 or 3, up to the lattice's dimension.

```julia
@kinds medium cytoplasm nucleus
# a polarization: the centroid offset of the cytoplasm from its nucleus, x component
@observed Πx(cell) ~ volume * minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1) /
                     (volume + volume[sibling(nucleus)])
@after_mcs begin
    gap ~ norm(separation(id, sibling(nucleus)))               # centroid distance to the nucleus
    reach ~ ifelse(alive(sibling(nucleus)), gap, 0.0)          # guard a referent that may be dead
end
```

- **`centroid(c, k)`** reads another cell's centroid. `c` is any reference: `sibling(k)`,
  a `CellRef` variable, `root(cluster)`, `owner` at a site, or a fold's cell
  (`sum(centroid(c, 1) for c in cells(nucleus))`). It cannot be used in energies, because
  a copy moves centroids and ΔH does not include that shift, or in other copy-step code.
  For a centroid shift in a drive, use `displacement(c, k)`.
- **`separation(a, b)`** is the vector between two centroids. Read one component with
  `separation(a, b)[k]`, or the distance with `norm(separation(a, b))`.
  - On a square lattice, component `k` is `minimum_image(centroid(a, k) − centroid(b, k), k)`.
  - On a periodic hexagonal lattice it is the nearest image on the skewed torus. That can be
    a diagonal image, which the per-axis wrap would miss. It is the same distance that
    link energies measure.
  - If either cell is dead, or a reference is 0, every component reads 0. That is not the
    distance to the medium, so guard such a read with `alive(ref)`.
- **`minimum_image(d, k)`** wraps a coordinate difference on a periodic axis: it returns the
  representative of `d` modulo L that is nearest 0.
  - At exactly ±L/2 the sign is unspecified, but the magnitude is L/2.
  - `d` is assumed to be within one period, as any difference of two coordinates is.
  - It is a pure function, so drives and energies can use it, for example
    `@drive copy => κ * minimum_image(position[target][1] - x₀, 1)`.
  - On a hexagonal lattice a single axis does not carry a displacement, so there it is an
    `ArgumentError`; use `separation` instead.
- **`integral(x; over = cluster)`** sums `x` over every site of the cluster's alive
  members, and every member reads the same value. `x` is a site expression, so `kind` and
  `volume` inside it are those of the cell that owns each site.
  - `integral(volume; over = cluster)` is Σ V_m² over the members.
  - `integral(1.0; over = cluster)` is the cluster's volume.
  - Divide two such integrals for a mean over the cluster's sites.
  - Plain `integral(x)` stays the sum over the cell's own sites.

The helpers also work in site scope between sweeps: field equations, site updates and the
decisions of a `@convert` pass. For example, here is the x offset of a site from its
cytoplasm's centroid:

```julia
Q = minimum_image(position[1] - centroid(sibling(owner, cytoplasm), 1), 1)
@equations D(signal) ~ Q * (kind == cytoplasm) - signal
```
