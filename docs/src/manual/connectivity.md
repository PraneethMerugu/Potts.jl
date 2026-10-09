# [Connectivity](@id manual-connectivity)

A cellular Potts cell is a set of lattice sites, and nothing in the energy keeps it in one
piece. Connectivity rules forbid, or charge for, the copies that would break a cell up. Three
of them are **local**: they read only the target's **shell**, so they are cheap and run on
every algorithm and device. The fourth, `Global()`, looks at the whole cell (see "Whole-cell
connectivity" below). The cell-scope values `pieces` and `largest_piece` let energies read a
cell's connectivity directly (see "A cell's pieces in the energy" below).

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
  Under `Simple()` and `Global()`, a copy is also refused when the gaining cell is of `kinds`
  and fails its test.
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
| `Global(; window = nothing, adjacency = :face)` | the copy does not increase its number of pieces | gaining the target does not increase its pieces (the target touches it) | allowed |

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
  and (26, 6). On every geometry, out-of-domain positions are background, so a pocket
  against a wall is not a hole.
- **3D.** `Local()` counts the face pieces of the 26-site shell. It is conservative for
  splitting and allows tunnels. `Simple()` is exact.

## The pieces

`connected(c; rule = Local())` is the copy-scope Boolean "under `rule`, cell `c` stays
connected through this copy". `c` is `old`, or `new` under `Simple()` and `Global()`; it is
`true` for the medium. It composes like any condition:

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

`pieces` takes only `shell`; there are no custom shells. The shell is anchored at a site
(`shell(target)`, `shell(source)`) and takes no options: `shell(old)` and
`shell(target; include_self = true)` are `ArgumentError`s.

**Shadowing (D-195).** These names came after published models used some of them as
structural parameters (`WortelAct(; connected)`). A structural parameter may take the name
`connected`, `shell`, `pieces`, `distinct`, `Local`, `ArcOrPair` or `Simple`; inside its own
model it then shadows the helper, and that model cannot call the helper. For example, with
`@structural_parameters connected = true`, a line `@constraint connected(old)` fails with
"objects of type Bool are not callable". Other declarations (kinds, parameters, variables)
may not take these names.

```julia
# a lumen (the medium) must not be split by a gaining cell
@constraint (old != 0) | (pieces(n for n in shell(target) if owner[n] == 0) <= 1)
# cluster connectivity: a cell's compartments together stay in one piece
@constraint (cluster[new] == cluster[old]) |
            (pieces(n for n in shell(target) if cluster[owner[n]] == cluster[old]) <= 1)
```

## Whole-cell connectivity: Global

```julia
@constraint connectivity(endothelial; rule = Global())                  # exact
@constraint connectivity(endothelial; rule = Global(; window = 12))     # windowed on the checkerboard
@drive connectivity(endothelial; rule = Global(), penalty = 50.0)       # the penalty form
@constraint connected(old; rule = Global()) | (kind[old] == stalk)      # composed
```

`Global(; window, adjacency)` is CompuCell3D's `ConnectivityGlobal` without its hole
heuristic, and Artistoo's `ConnectivityConstraint`. A cell's **pieces** are the connected
components of its sites under `adjacency`. Under `Global()`, cell `c` stays connected
through a copy when it is the medium or the copy **does not increase** its number of
pieces. A cell that is already in pieces can still move, and its last site may be taken
(compose with `no_extinction` to forbid that). Both cells are tested:

- the losing cell must not split: its sites next to the target must stay connected through
  its other sites;
- the gaining cell must not gain a detached site: the target must touch it. Under `:face`
  this refuses a `Moore(1)` copy that reaches the cell only at a corner.

**Cost.** The veto is evaluated after the acceptance draw: the local test, then ΔH, then the
draw, then the search. The draw comes from the counter RNG, so the trajectory is the same
as evaluating the rule first, and the search runs only for accepted copies whose shell
test fails. One consequence: a refused copy whose ΔH is not finite now fails the run
(`retcode = Failure`), where a constraint evaluated first would have skipped it. The search
floods the cell from one touching site and stops when it has reached the others.

**`window`** is used by `CheckerboardCPM` only. `SequentialCPM` and `BoundarySiteCPM` are
exact and ignore it.

- On the checkerboard, an accepted copy whose shell test fails is put on a list. A deferred
  kernel searches each listed copy inside the box `|Δ| ≤ window` round the target, in index
  space with the minimum image on periodic axes. If the copy passes, the kernel raises its
  claims, so the commit step is unchanged.
- A copy is refused for want of window when the touching pieces do not meet inside the box
  and every one of them leaves it. Such copies are counted in
  `sol.stats.connectivity_deferred`. The counter is `nothing` for a model without `Global`,
  and always 0 on the host algorithms and without a window.
- The window search uses a fixed-size stack (an `MVector` of the box size) and allocates
  nothing, so it runs on a device. Each thread holds `CAP` `Int32`s of stack and two bit
  sets of `CAP` bits, `CAP` being the box's site count (at most (2W + 1)^d): about
  4.25·CAP bytes per thread, so ≈ 1 KB at W = 7 in 2D but ≈ 14 KB at W = 7 in 3D. Large
  windows cost registers and private memory on a GPU; keep them small in 3D.
- Without a window the checkerboard search is exact, on the CPU and on a device alike: it
  runs over a scratch array one copy at a time (a serial kernel on a device).

**Launches.** A `Global` veto adds one launch per colour on the checkerboard: 4 per MCS in
2D with `Moore(1)` copies. Cell-scope `pieces` add another one per colour (below). Models
that use neither generate exactly the code they did before.

**Inline.** `connected(c; rule = Global(…))` in a drive or constraint is exact on the host
algorithms. On the checkerboard, a rule with a window searches inside it, and a copy it
cannot decide reads `false`. A rule without a window is exact there too.

## A cell's pieces in the energy

| Value | Scope | Meaning |
|---|---|---|
| `pieces`, `pieces(; adjacency = :face)` | cell (`@energy cells(k) => …`, `@observed q(cell) ~ …`) | the number of pieces of the cell, 0 for a dead cell |
| `largest_piece`, `largest_piece(; adjacency = :face)` | cell | the site count of its largest piece, 0 for a dead cell |
| `pieces[c]`, `pieces(c; adjacency)`, `largest_piece[c]`, `largest_piece(c; adjacency)` | copy (`@drive`, `@constraint`), `c ∈ {old, new}` | the value before the copy; the medium reads 0 |

```julia
@energy cells(endothelial) => α * (largest_piece != volume)   # Bauer et al. 2009, Eq 1
@energy cells(cell) => α * (pieces > 1)                        # Jafari Nivlouei et al., Eq 3
@observed fragments(cell) ~ pieces
```

- These are exact trackers, like `euler`. A cell term sees the exact values after the copy,
  so ΔH equals the difference of the Hamiltonian. They take no window on any algorithm.
- A bare `pieces` or `largest_piece` in a drive is an `ArgumentError`, as for `volume`: index
  it (`pieces[old]`).
- The shell fold `pieces(c, shell(target))` is a different value and is unchanged.
- **Cost.** The after-values come from the shell when the cell is one piece and the shell
  test holds, or when the target is a piece of its own. Otherwise the cell is flooded.
- **Checkerboard.** A copy that needs a flood runs in a serial kernel, one copy at a time, over
  the same scratch. This adds one launch per colour.
- **Lifecycles.** Divisions and removals rebuild the trackers on the host. A device
  lifecycle does not maintain them, so that combination is an `ArgumentError`.

## Old names

| Old | New | Generated code |
|---|---|---|
| `rule = :local` | `rule = Local()` (the default) | identical |
| `rule = :arc_or_pair` | `rule = ArcOrPair()` | identical |
| `ring_cells` | `distinct(owner[n] for n in shell(target) if owner[n] != 0)` | identical |
| `ring_medium` | `count(owner[n] == 0 for n in shell(target))` | identical |
| `ring_arcs`, `local_components` | `pieces(old, shell(target))` for a cell (0 for the medium) | the values are kept |
| `components(old; scope = Global())` | removed with no alias; write `!connected(old; rule = Global())` | |

The symbols are aliases of the rule values, so their meaning changed with them. Since P6.3g,
`rule = :local` also refuses a full shell and runs the gain test, and `rule = :arc_or_pair`
counts the frame at a closed face.

## Coming from another framework

| You used | Write |
|---|---|
| CompuCell3D `Connectivity`, versions 4.3.1–4.6.0 | `@drive connectivity(k; rule = Local(), penalty = P)` with the XML's `<Penalty>` P. A large P (Akeeb et al. use 10⁵ at T = 10) is a veto: `@constraint connectivity(k)`, the T → 0 limit of the penalty form |
| CompuCell3D `Connectivity`, version 4.7.0 and later | `@drive connectivity(k; rule = Local(), penalty = 64.0)`. These versions ignore `<Penalty>` and return a hard-coded 64 |
| CompuCell3D `ConnectivityGlobal` | `@constraint connectivity(k; rule = Global())` (CompuCell3D's hole heuristic is not reproduced) |
| Morpheus `ConnectivityConstraint` | `@constraint connectivity(k; rule = Simple())` (close: Morpheus' 3D test is a face count plus first-order conditions) |
| Artistoo `LocalConnectivityConstraint` | `@constraint connectivity(k; rule = Local(; gain = false))` (Artistoo joins diagonal shell sites, so it is slightly less strict) |
| Artistoo `SoftLocalConnectivityConstraint` | `@drive connectivity(k; rule = Local(; gain = false), penalty = λ)` |
| Artistoo `ConnectivityConstraint` | `@constraint connectivity(k; rule = Global())` |
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
