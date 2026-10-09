# [Connectivity](@id manual-connectivity)

A cellular Potts cell is a set of lattice sites, and nothing in the energy keeps it in one
piece. Connectivity rules forbid, or charge for, the copies that would break a cell up. They
are **local**: each rule reads only the target's **shell**, so it is cheap and runs on every
algorithm and device.

The **shell** of the target is the 8 sites of its 3×3 box on a square lattice, its 6
neighbours on a hexagonal one, and the 26 sites of its 3×3×3 box in 3D, whatever the model's
neighbourhood. A periodic axis wraps. A shell position off a closed face is out of the domain:
it is never the cell, never the medium, and the folds skip it.

## One helper, two statements

```julia
@constraint connectivity(endothelial)                                    # the veto
@drive connectivity(endothelial; rule = ArcOrPair(), penalty = E₀)       # the penalty
```

`connectivity(kinds…; rule = Local(), penalty = nothing)` applies `rule` to cells of `kinds`
(every kind if none; kind classes work too). The medium is never tested.

- In `@constraint`, a copy is refused when the losing cell is of `kinds` and the rule fails.
  Under `Simple()`, a copy is also refused when the gaining cell is of `kinds` and fails its
  test.
- In `@drive`, every copy the veto would refuse is charged `penalty`: ΔH += penalty ·
  [refused]. `penalty` is a number or a parameter.

A `penalty` in `@constraint`, or no `penalty` in `@drive`, is an `ArgumentError` naming the
other statement.

## The rules

| Rule | The losing cell `old` passes when | The gaining cell | The last site |
|---|---|---|---|
| `Local(; gain = true, adjacency = :face)` | its shell sites form exactly one piece, the shell is not full, and (with `gain`) `new` owns a shell site next to the target | not tested on its own | refused |
| `ArcOrPair()` | its shell sites form at most one face piece, or exactly two distinct cells and no medium are on the shell | not tested | allowed |
| `Simple(; adjacency = :face)` | the target is a simple point of `old`: no piece and no hole is made or lost | the same test for `new` | refused |
| `Global(; window, adjacency)` | the whole cell stays one piece (not available until P6.9; using it is an `ArgumentError`) | | |

Details:

- **`adjacency`.** `:face` joins shell sites that are face neighbours (4 in 2D, 6 hex, 6 in
  3D). `:full` joins any neighbours (8 in 2D, 26 in 3D). A hexagonal lattice has one
  adjacency, so there `:full` is `:face`.
- **`Local()`'s full shell.** When every shell position is in the domain and owned by `old`,
  taking the target would make a one-site hole, so `Local()` refuses it, as CompuCell3D does.
  A shell that touches a closed face is never full.
- **`Local()`'s gain test.** `new` (the medium included) must own a face neighbour of the
  target, or under `:full` any shell site. With `VonNeumann(1)` copies the source is always
  such a site, so the test never fires. With `Moore(1)` or longer copies it refuses gains
  that touch the cell only at a corner, or not at all.
- **`ArcOrPair()` at a closed face.** The out-of-domain positions count as one extra cell, as
  the frame of the Tissue Simulation Toolkit does. The folds below do not do this; for them
  out of domain is nothing.
- **`Simple()`.** The cell uses `adjacency`, and the background (other cells, the medium, out
  of domain) uses the dual one: `:face` is (4, 8) in 2D and (6, 26) in 3D, `:full` is (8, 4)
  and (26, 6). In 2D, out-of-domain positions are background, so a pocket against a wall is
  not a hole.
- **3D.** `Local()` counts the face pieces of the 26-site shell. It is conservative for
  splitting and allows tunnels. `Simple()` is exact.

## The pieces

`connected(c; rule = Local())` is the copy-scope Boolean "under `rule`, cell `c` stays
connected through this copy". `c` is `old`, or `new` under `Simple()`; it is `true` for the
medium. It composes like any condition:

```julia
@constraint connected(old) | (volume[old] == 1)            # allow death, not splitting
@drive copy => λ * !connected(old; rule = Simple())
```

`shell(target)` is a relation for folds:

| Fold | Value |
|---|---|
| `pieces(c, shell(target); adjacency = :face)` | the pieces of the shell sites owned by `c` (`0` is the medium) |
| `pieces(n for n in shell(target) if cond(n); adjacency = :face)` | the pieces of the shell sites where `cond` holds |
| `distinct(body(n) for n in R(s) if cond(n))` | the number of distinct values of `body` over relation `R` (or `shell`); the medium's 0 is a value |

`pieces` takes only `shell`; there are no custom shells.

```julia
# a lumen (the medium) must not be split by a gaining cell
@constraint (old != 0) | (pieces(n for n in shell(target) if owner[n] == 0) <= 1)
# cluster connectivity: a cell's compartments together stay in one piece
@constraint (cluster[new] == cluster[old]) |
            (pieces(n for n in shell(target) if cluster[owner[n]] == cluster[old]) <= 1)
```

## Old names

| Old | New | Generated code |
|---|---|---|
| `rule = :local` | `rule = Local()` (the default) | identical |
| `rule = :arc_or_pair` | `rule = ArcOrPair()` | identical |
| `ring_cells` | `distinct(owner[n] for n in shell(target) if owner[n] != 0)` | identical |
| `ring_medium` | `count(owner[n] == 0 for n in shell(target))` | identical |
| `ring_arcs`, `local_components` | `pieces(old, shell(target))` for a cell (0 for the medium) | the values are kept |
| `components(old; scope = Global())` | removed with no alias; `connected(old; rule = Global())` comes with P6.9 | |

The symbols are aliases of the rule values, so their meaning changed with them. Since P6.3g,
`rule = :local` also refuses a full shell and runs the gain test, and `rule = :arc_or_pair`
counts the frame at a closed face.

## Coming from another framework

| You used | Write |
|---|---|
| CompuCell3D `Connectivity`, versions 4.3.1–4.6.0 | `@drive connectivity(k; rule = Local(), penalty = P)` with the XML's `<Penalty>` P. A large P (Akeeb et al. use 10⁵ at T = 10) is a veto: `@constraint connectivity(k)`, the T → 0 limit of the penalty form |
| CompuCell3D `Connectivity`, version 4.7.0 and later | `@drive connectivity(k; rule = Local(), penalty = 64.0)`. These versions ignore `<Penalty>` and return a hard-coded 64 |
| CompuCell3D `ConnectivityGlobal` | `@constraint connectivity(k; rule = Global())` (P6.9) |
| Morpheus `ConnectivityConstraint` | `@constraint connectivity(k; rule = Simple())` (close: Morpheus' 3D test is a face count plus first-order conditions) |
| Artistoo `LocalConnectivityConstraint` | `@constraint connectivity(k; rule = Local(; gain = false))` (Artistoo joins diagonal shell sites, so it is slightly less strict) |
| Artistoo `SoftLocalConnectivityConstraint` | `@drive connectivity(k; rule = Local(; gain = false), penalty = λ)` |
| Artistoo `ConnectivityConstraint` | `@constraint connectivity(k; rule = Global())` (P6.9) |
| Tissue Simulation Toolkit `ConnectivityPreservedP` with `conn_diss` | `@drive connectivity(k; rule = ArcOrPair(), penalty = conn_diss)` |
| Durand & Guesnet 2016 | `@constraint connectivity(k; rule = Simple())` with `VonNeumann(1)` copies |

**CompuCell3D, in detail.** We read the plugin's source at 4.3.1, 4.6.0, 4.7.0, 4.8.0, 4.9.0
and master. Apart from the penalty, its `changeEnergy` is the same in every version:

- it returns 0 when the losing cell is the medium;
- rule 1: the gaining cell, the medium included, must own a face neighbour of the target;
- rule 2: the losing cell must form exactly one arc on the clockwise 8-ring, so a full ring
  is refused;
- in 3D the plugin throws.

`Local()` with its defaults is rules 1 and 2. The plugin is 2D only.

**A source artefact we do not reproduce.** CompuCell3D initialises its ring positions to
pixel (0, 0, 0), and an off-lattice position (off a non-periodic face) keeps that value. At a
closed edge it therefore reads the owner of pixel (0, 0, 0) for those positions, which can
add or merge arcs for cells touching that edge. Potts.jl reads off-lattice positions as
nothing. This is a quirk of the source, not a rule option; its effect has not been measured.
