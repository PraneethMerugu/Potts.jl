# P6.3j: cell-scope Euler-characteristic tracker (design note)

Status: design only (2026-10-08), for D-189 ruling 12. Nothing here is implemented or committed.
It is written against `docs/design/research/connectivity-vocabulary.md` (§8.1, §8.4, §8.6, §9,
§13.1) and the tracker code paths `lib/CorePotts/src/model.jl:262-306` (`surface_change`,
`commit_surface!`), `lib/CorePotts/src/contact_counts.jl`, `lib/CorePotts/src/lifecycle.jl:470`
(`_rebuild_trackers!`), `src/codegen.jl:66-76, 170-245, 323-345` (cell env, ΔH, commit) and
`src/compile.jl:398-420, 656` (`uses_surface`, footprint, `_cell_delta`).

Every formula below was checked by brute force in a short Julia script, which was not
committed (`scratchpad/euler_check.jl`). The checks cover:

- all 256 square rings and all 64 hex rings;
- random copy sequences of 5000 steps in 2D and hex, and 1500 steps in 3D;
- closed and periodic lattices, under both adjacencies.

After every step, the incremental χ equalled a full recount of the cell complex. Bibliographic
details marked *(memory)* were not re-fetched.

---

## 0. Decision in one paragraph

Track one `Int32` per cell, `euler`, for each adjacency the model reads. On every accepted copy:

- the losing cell changes by `−D(m_old)`;
- the gaining cell changes by `+D(m_new)`.

Here `m_c` is the membership mask of cell `c` on the target's shell: 8 sites on the square lattice, 6 on hex and 26 in 3D. This is the same shell that `Local()` and `Simple()` read.

`D` is the exact change in χ when the target is added to the set. It is given in closed form:
- a few mask-and-popcount operations;
- no table in 2D or 3D;
- `:full` adjacency comes from `:face` by complementing the mask (digital duality).

The tracker is wired exactly like `surface`. A `uses_euler` flag:
- adds a column;
- adds a `δeuler` binding in ΔH, substituted by `_cell_delta`;
- adds a commit line;
- adds a host and device rebuild after lifecycle events.

A model that never names `euler` gets no column, no code and no footprint change.

The `holes(c) = pieces(c) − euler(c)` identity holds in 2D. Its energy-usable form needs P6.9's cell-scope `pieces`, so it is proposed to land with P6.9 (Q1).

---

## 1. The mathematics

### 1.1 What χ is, per adjacency (well-composed pairing)

A cell's site set X is turned into a cell complex whose topology is the one the adjacency
names. The complement is then read with the dual adjacency, which is the standard
Rosenfeld pairing. Under that pairing the digital Jordan theorem holds, and so does
`holes = b₀(X) − χ` in 2D (Kong & Rosenfeld 1989 *(memory)*).

| Geometry | `adjacency` | cell / complement | complex of X | χ |
|---|---|---|---|---|
| square 2D | `:face` (default) | 4 / 8 | graph complex: V = sites, E = 4-adjacent pairs, F = full 2×2 blocks | V − E + F |
| square 2D | `:full` | 8 / 4 | union of closed unit pixels (grid vertices, unit edges, pixels) | V − E + F |
| hex | (only one; self-dual) | 6 / 6 | triangulation: V = sites, E = adjacent pairs, F = triangles of 3 mutually adjacent sites | V − E + F |
| cubic 3D | `:face` (default) | 6 / 26 | graph complex: V, E = 6-adjacent pairs, F = full 2×2 squares (3 orientations), C = full 2×2×2 cubes | V − E + F − C |
| cubic 3D | `:full` | 26 / 6 | union of closed unit voxels | V − E + F − C |

The topological meaning of the counts:
- In 2D, χ = b₀ − b₁, the number of pieces minus the number of holes.
- In 3D, χ = b₀ − b₁ + b₂, the number of pieces minus the number of tunnels plus the number of cavities.

These match the two classical bit-quad formulas. Gray 1971 (*IEEE Trans. Comput.* C-20:551 *(memory)*):

- χ₄ = (n(Q₁) − n(Q₃) + 2 n(Q_D)) / 4
- χ₈ = (n(Q₁) − n(Q₃) − 2 n(Q_D)) / 4

Both were confirmed against the complexes and against a flood fill, b₀ − #bounded complement components, on 2000 random 7×7 images.

The 3D octant formulation used by Lee, Kashyap & Chu 1994 (*CVGIP: Graph. Models Image Process.* 56:462 *(memory)*) is equivalent. It is an 8-octant × 128-entry Euler LUT for the 26/6 pair, used for thinning in ITK's `BinaryThinningImageFilter3D` and in skimage `skeletonize_3d` *(memory)*. So is Toriwaki & Yonekura 2002 (*Forma* 17:183 *(memory)*), whose 2×2×2 LUT skimage `measure.euler_number` uses for both connectivities. The closed forms in §1.2 are the same sums, grouped by complex-cell type instead of by octant.

### 1.2 Exact local Δχ for a single-site copy

χ is a sum of contributions from the 2×2 (2D) or 2×2×2 (3D) windows of the lattice. Only the
windows that contain the target x change, and they all lie inside the 3×3 or 3×3×3 box. So the
change is a function of the shell mask alone.

Let `D(m)` be the change in χ(X) when x is **added** to X, where m is X's mask on the shell.
Removing x gives `−D(m)` with the same mask. The copy `old → new` at x therefore gives:

```
Δχ(old) = −D_adj(m_old)        Δχ(new) = +D_adj(m_new)        (no other cell changes)
```

`m_old` is the old cell's mask, with x itself excluded. When `old == 0` or `new == 0`, nothing is
done on that side, because the medium has no column.

**Square 2D, `:face` (4/8).** Ring bits 1…8 go round the box starting at (−1,−1):
(−1,−1), (−1,0), (−1,1), (0,1), (1,1), (1,0), (1,−1), (0,−1).
- `FACE4 = 0b10101010`, the four face neighbours.
- The four corner trios are corner|face|face: (1,2,8), (2,3,4), (4,5,6), (6,7,8).

```
D₄(m) = 1 − popcount(m & FACE4) + #{corner trios t : m ⊇ t}
```

Adding x adds one vertex, one edge to each face neighbour already in X, and one face per
2×2 block it completes. Range −3…1.

**Square 2D, `:full` (8/4).** `D₈(m) = D₄(~m & 0xff)`.

This is 2D duality: χ₈(X) + χ₄(Xᶜ) is constant, so adding x to X has the same effect as removing it from Xᶜ.

As a direct form, `D₈ = 1 − (4 − n₄) + #{corners whose 3 other pixels are all outside X}`. Its three terms are the new face, the new edges and the new vertices. All 256 entries were checked equal to the 3×3 recount.

**Hex.** The six neighbours are in cyclic order, so consecutive ring sites are mutually adjacent and form a triangle with x.

```
D_hex(m) = 1 − popcount(m) + popcount(m & rotr6(m))
         = 1 − runs(m)    (m ≠ 0, 0x3f);   D(0) = D(0x3f) = 1
```

The lattice is self-dual, and `D_hex(m) = D_hex(~m)` was verified. So `:face` and `:full`
coincide on hex (Q4).

**Cubic 3D, `:face` (6/26).** Bits index the 26 offsets. There are three kinds of mask:
- `FACE6`, the 6 face bits;
- 12 *edge trios*, each an edge-diagonal neighbour with its two face neighbours (x plus the trio is one 2×2 square);
- 8 *octants*, each the 7 non-x voxels of one 2×2×2 cube.

```
D₆(m) = 1 − popcount(m & FACE6) + #{trios t : m ⊇ t} − #{octants o : m ⊇ o}
```

The terms are one new vertex, the new edges, the new squares and the new cubes. The sampled range is −5…5.

**Cubic 3D, `:full` (26/6).** `D₂₆(m) = −D₆(~m & 0x3ffffff)`.

The sign flips because, in 3D, Alexander duality gives χ(X) = χ(Xᶜ) rather than "const − χ". As a direct form:

`D₂₆ = #{octants o with m ∩ o = ∅} − #{trios t with m ∩ t = ∅} + (6 − n₆) − 1`

Its terms are the new vertices, edges, faces and the cube.

Both 3D forms were checked against full recounts on closed and periodic 4×5×4 lattices over
1500 random flips each. Known shapes check out: a one-voxel-thick ring has χ = 0 for both
adjacencies, and a hollow 3×3×3 cube has χ = 2.

**Why closed forms rather than a 256-entry or 2²⁶ table.**
- The 2D table would be 256 `Int8`. The closed form costs about the same: 1 popcount and 4 mask-compares.
- A 3D table over the 26 bits is impossible (64 MB).
- Lee's octant LUT would need 8 bit-gathers to build the 7-bit indices. The closed form needs 21 `(m & k) == k` tests on a `UInt32`, with no memory traffic.
- The 256-entry `NTuple{256, Int8}` stays available as the 2D fallback if P6.3h's benchmark prefers it.

### 1.3 Periodic seams and cells that wrap a torus

P6.3g already makes an axis shorter than 3 a build error (W19). With every periodic axis ≥ 3, the 3×3 or 3×3×3 box has distinct sites, and the window decomposition holds on the torus complex unchanged. The tracker therefore computes **χ of the cell as a subcomplex of the periodic lattice**. This was verified on 6×7 tori (2D, hex) and 4×5×4 3-tori.

For any cell that does not wrap, this equals the planar value. A wrapping cell reports its true torus topology:

| Cell | What is reported |
|---|---|
| a band round one axis (2D) | χ = 0: one piece, one non-contractible cycle. So `holes = pieces − χ` reads **1** |
| the whole 2-torus | χ = 0 (b₀ = 1, b₁ = 2, b₂ = 1) |
| a rod through a periodic axis (3D) | χ = 0: one tunnel |

**What we report:** the exact torus χ, documented as "a cycle round a periodic axis counts as a hole or tunnel".

The alternative, the χ of the lift to the universal cover, is non-local. No local update can give it, so it is rejected.

Wrapping cells are rare in CPM practice. The docs give a check, `bounding_extent < L − 1` on each periodic axis. This is a candidate observable and not part of v1 (Q2).

Mixed boundaries, periodic on one axis and closed on another, need nothing extra: `shift` already wraps or excludes per axis.

### 1.4 Out-of-domain sites (closed faces, domain masks)

χ is **intrinsic**: the complex is built from the cell's own sites only. An out-of-domain site is never in X, so its bit is 0; `shift` returns `inside = false` and the mask builder leaves the bit clear. Nothing else is needed. This reading is consistent with ruling 7 ("out of domain is background"):
- A cell pressed against a closed wall forms a pocket. It has no hole, χ = 1.
- A cell that encloses a masked obstacle has a hole, χ = 0. That is right, since the obstacle is background.

The raw-fold rule (ruling 5: out of domain is nothing) and the `ArcOrPair()` frame rule do not apply, because χ never counts the complement.

### 1.5 Medium, frames, kinds

- **Medium.** `owner = 0` has no entry, so nothing is tracked for it.
- **Frames.** A frame is a real cell. It is tracked, and its χ never changes.
- **Kinds.** The column is per cell for all kinds, at 4 bytes per cell. Kind filters live in the energy term (`cells(k) => …`), as with `surface`.

---

## 2. API fit

### 2.1 Surface (vocabulary §8.1 additions)

The new surface is three cell-scope built-ins:

- **`euler`**, the cell's Euler characteristic under face adjacency. It is exact after every copy, like `volume` and `surface`, and has an exact after-value in energies.
- **`euler(; adjacency = :full)`**, the same under full adjacency. The keyword follows ruling 4.
- **`holes`** (2D only), equal to `pieces − euler` under the same adjacency. Energy use needs P6.9's `pieces` (Q1). In 3D, `holes` is a build error that points to `euler`, because tunnels and cavities are not separable locally.

Two further forms complete the surface:

- **In copy scope**, the forms `euler[c]` and `euler(c; adjacency)` read the before-value. This is the same rule §8.4 sets for `pieces[old]`. Using `euler` without an index there is a build error.
- **As an observable**, `euler` is like any cell built-in. It can be read in `@observed`, in saved cell columns, in lifecycle rules and in cell phases.

### 2.2 Examples

```julia
# a cell held to one piece: λ per hole (2D), exact ΔH
@constraint connectivity(epithelium)                      # Local(): no copy splits a cell
@energy     cells(epithelium) => λ_hole * (1 - euler)
# genus-like target in 3D (e.g. a lumenised cyst, one cavity: χ = 2)
@energy     cells(cyst) => λ * (euler - 2)^2
# both adjacencies side by side (diagnostic)
@observed   χ8 = cells(epithelium) => euler(; adjacency = :full)
# after P6.9: holes for any cell, fragmented or not
@energy     cells(k) => λ * holes                         # ≡ λ * (pieces - euler)
# lifecycle: remove a cell that has become a ring
@rule cells(k) => (euler <= 0) => remove()
```

### 2.3 Compiler and codegen wiring (mirrors `surface`)

- **Vocabulary.** Add `B.euler`, a built-in with `Info(:builtin, :euler, …)`, and its delta symbol, defined as
  `DEULER = _tag(_sym(:δeuler), Info(:delta, :euler, nothing, (;)))`.
  The `adjacency` keyword gives a second built-in key, `:euler_full`, so each adjacency gets its own column and its own delta.
- **`compile.jl`.**
  - Set the flags `uses_euler = _uses_builtin(x, :euler)` and `uses_euler_full`.
  - Add `_unwrap(B.euler) => B.euler + DEULER` to `_cell_delta`'s substitution map.
  - Raise the footprint to `radius_read = max(radius_read, 1)`. It is already ≥ 1 in every model with a surface or a shell rule.
- **ΔH (`_delta_H_expr`).** When either flag is set, emit
  `(δe_old, δe_new) = CorePotts.euler_change(st.σ, ctx, prop, Val(:face))` (and `Val(:full)`).
  Bind `:δeuler => :δe_old` or `:δe_new` per side in `_cell_env`'s `extra`. The pattern is that of `δsurface`. ΔH is then `E(euler + δ) − E(euler)` for `old` and `new`, which is exact.
- **Commit (`_commit_expr`).** Emit `uses_euler && CorePotts.commit_surface!`-style
  `commit_euler!(st.cell.euler, prop, CorePotts.euler_change(…))`. It is recomputed in commit as `surface_change` is, at the cost of one more shell evaluation. Sharing it with ΔH is a P6.3h optimisation. *P6.3h:* declined. The checkerboard commits in a separate launch from ΔH, so sharing would need a per-copy buffer; the recompute costs about 10 ns (2D) or 37 ns (3D) per accepted copy after P6.3h's kernels.
  - No atomics are needed. Only `old` and `new` change, and the checkerboard write-claims both (`checkerboard.jl:50-54`).
  - A concurrent copy at a shell site y can change `old` or `new` membership only by claiming one of them. So `m_old` and `m_new` are stable, and the window sets of two committed copies are disjoint. This holds even with no footprint argument.
- **Shell read.** The kernel takes σ or a `CorePotts.ShellRead`; since P6.3h a generated function with two or more shell kernels binds one `read_shell` and passes it to each. Only the masks `m_old` and `m_new` are derived; the medium is never masked.
- **Initial state (`problem.jl:624` pattern).** Emit `push!(cell, :euler => CorePotts.recompute_euler(σ, lat, Val(:face), ncell))`.
- **Lifecycle.**
  - **Host.** `_rebuild_trackers!` gains `haskey(st.cell, :euler)`, which recomputes from σ.
  - **Device.** The device pass follows the `_dcount_zero_body!`/`_dcount_body!` pattern. One thread per 2×2 or 2×2×2 window, anchored at its min corner and including the low padding windows on closed axes. For each distinct owner in the window it atomically adds that owner's scaled window weight, ×4 in 2D or ×8 in 3D, as `Int32`. A final per-cell pass divides by 4 or 8; the sums are exact integers.
- **MTK fit.** As for `surface` or `major_length`, it is a Potts symbolic built-in with a delta tag. It needs no `@register_symbolic`, and nothing reaches `mtkcompile`. `hamiltonian(sys)` displays `λ * (1 - euler)` as written, and `total_energy` reads the column.

### 2.4 Relation to the rest of the connectivity vocabulary

- **`Simple()` implies Δχ = 0 for both cells.** A simple point preserves topology. Under `@constraint connectivity(k; rule = Simple())`, every cell of kind k keeps its χ, which gives a free invariant test (§4). The converse is false: Δχ = 0 can hide a split plus a hole being filled.
- **The pairings agree.** `euler(; adjacency = :face)` pairs with `pieces(; adjacency = :face)`, which comes from P6.9 and ruling 4, and with `Simple(; adjacency = :face)`. All three read the complement under full adjacency. So `holes = pieces − euler` counts exactly the background components that `Simple()` protects.
- **Enclosure (§8.6) is unchanged.** "The nucleus lies inside its cell" is still not expressible. χ is per cell and says nothing about inclusion between cells.

---

## 3. Cost

**Per copy, when used.** Count per call to `euler_change`. ΔH and commit each call it once.

| Geometry | Reads | Integer ops (both sides) | Memory |
|---|---|---|---|
| square 2D | 8 owners, shared with any shell rule | 16 compares to build the 2 masks, then about 2 × (popcount + 4 mask tests) | none |
| hex | 6 owners | 12 compares, then 2 × (2 popcounts + rotate) | none |
| cubic 3D | 26 owners | 52 compares, then 2 × (popcount + 20 mask tests); `D₂₆` adds one `~` | none |

There are no tables: the masks are constant `UInt32` literals folded into the code. The 2D variant could use a 256-byte `NTuple{256, Int8}` constant instead.

**Memory per cell.** One `Int32` per adjacency used, so 4 or 8 bytes times the capacity.

**Device.**
- Masks are `UInt32`, and deltas are `Int8` widened to `Int32`.
- The tracker is `Int32`. The only float conversion is `T(δ)` inside ΔH, where `T` is the model's float type (`Float32` on device).
- There is no `Float64`, no `throw`, no allocation and no division in the per-copy kernel. Integer division appears only in the rebuild, as an exact `÷4` or `÷8`.
- Metal and ROCm run the same generic code as CPU.

**Zero cost when unused.** Every emission is guarded by `uses_euler` or `uses_euler_full`. These flags are set only when the model's scanned expressions contain the built-in. Without them, codegen emits nothing: no ΔH lines, no commit line, no column, no footprint change and no rebuild work. The same holds in `_rebuild_trackers!`, because it is keyed on `haskey(st.cell, :euler)`.

As a result, the generated code and the fingerprint of every published model are byte-identical. This is pinned by the existing `generated_code` and fingerprint tests. D-058 item 4 (no name, no code, no buffer) holds as it does for shell quantities (§9.2).

---

## 4. Test plan

All tests use small lattices and run in the CorePotts or Potts groups. The brute-force helpers live in the test files, are independent of the kernel, and follow the definitions of §1.1. The checks of `scratchpad/euler_check.jl` port directly.

**4.1 Kernel oracles (exhaustive or large samples).**
- **2D and hex.** Check all 256 square masks and all 64 hex masks. In each case `D` must equal χ(3×3 patch or 7-site patch, with x) − χ(without x), recounted from the complex, for both adjacencies.
- **3D.** Check every mask with ≤ 4 or ≥ 22 set bits, plus 10⁶ random masks, against a 3×3×3 recount for both adjacencies.
- **Identities.** Check the three identities over the full 2D and hex sets and the sampled 3D masks: `D₈(m) = D₄(~m)`, `D₂₆(m) = −D₆(~m)` and `D_hex(m) = D_hex(~m)`.

**4.2 Global oracles after random copy sequences.** Use real integrators (Sequential, CPU Checkerboard and BoundarySite) on models with 3 to 6 cells and a noisy energy, so that topology changes often. Use NeighborOrder(2) proposals so that holes form.

The lattices are:
- 2D square 12×12;
- hex 10×10;
- 3D 6×6×6.

Each lattice is run under three boundary setups:
- closed;
- periodic;
- periodic with a domain mask.

Every k MCS, compare each cell's tracked `euler` with two oracles:

- **(a) Complex recount.** V − E + F (− C) of the cell's subcomplex. This is exact on tori too.
- **(b) Flood fill.**
  - **2D and hex:** b₀ under the cell adjacency minus the number of complement components under the dual adjacency that do not touch the padded outside. Out-of-domain sites count as background.
  - **3D:** b₀ and the cavities (bounded complement components) by flood fill, plus a check that b₁ = b₀ + b₂ − χ ≥ 0.
  - **Scope:** closed lattices, plus periodic lattices when the cell is checked not to wrap.

**4.3 Reference shapes, exact values.** In 2D:
- a disc has χ = 1;
- an annulus has χ = 0;
- a 4-site diamond around an empty centre has `:face` χ = 4 and `:full` χ = 0;
- a periodic band has χ = 0 (the documented torus convention);
- a cell against a closed wall or round a masked obstacle has χ = 1 or 0 respectively.

In 3D:
- a solid ring has χ = 0;
- a hollow cube has χ = 2;
- a rod through a periodic axis has χ = 0.

**4.4 Lifecycle.** Divisions that cut non-convex cells, removals and kind transitions must leave the column equal to `recompute_euler` (host and device paths).

**4.5 Exact ΔH.** For random proposals under `cells(k) => λ * (1 - euler)^2` (plus `λ * holes` after P6.9), `delta_H` must equal `total_energy(after) − total_energy(before)` by brute force, with exact integer χ parts.

**4.6 Invariant.** Under `@constraint connectivity(k; rule = Simple())`, every tracked χ of kind k stays constant over a long run, in 2D, hex and 3D.

**4.7 GPU.** Metal and ROCm must give `euler` columns bitwise equal to the CPU on the gpu.jl sibling cases.

**4.8 Negative controls.** Each control must fail or show the effect within N steps:
1. A mutant kernel that uses `D₄` for `:full`, drops the octant term in 3D, or gets the 3D duality sign wrong must fail oracle 4.2. This tests the test.
2. **`pieces` is blind to holes.** A cell grows an annulus: `pieces` stays at 1 while `euler` drops to 0.
3. **The energy has an effect.** Run NeighborOrder(2) proposals with λ_hole > 0 and with λ_hole = 0. The mean number of holed cells must be significantly lower at λ_hole > 0, over paired seeds.
4. **The torus convention.** A wrapping band must read χ = 0, not 1. This documents the convention.

**4.9 Zero cost (D-171).**
- **Static.** No published model's generated code or fingerprint changes, and there is no `:euler` column in its state.
- **Benchmark.** Run the paired A/B (`benchmark/ab.jl`) with two same-commit controls, on CPU and ROCm, using Merks2006 and Akeeb. Acceptance is a ratio of 1.00 within the controls' spread.
- **Allocations.** `benchmark/gate.jl` must show zero warm allocations.
- **Cost when used.** It is measured and reported, not gated, on two models: a 2D model with `λ * (1 - euler)` and a 3D model with `euler`.

---

## 5. Open questions for the maintainer

1. **`holes` before P6.9.** The question is whether to ship `euler` now with `holes` landing with P6.9's cell-scope `pieces`, or to ship `holes` now. Shipping it now would mean either a host-only observable (flood fill at save time) or a version valid only for one-piece cells.
   *Recommended:* ship `euler` now. `holes = pieces − euler` lands with P6.9. The docs show `1 − euler` under a connectivity constraint for the common case.
2. **Torus convention.** One option is to report the torus χ, under which a wrapping band reads as one hole. The other is to flag wrapping cells, which would need a non-local check.
   *Recommended:* report the torus χ, document it, and add no flag in v1.
3. **3D scope.** Should 3D have only `euler`, with no `tunnels` or `cavities` in v1? Cavities need a global flood of the complement, and tunnels follow as b₀ + b₂ − χ once `pieces` and cavities exist.
   *Recommended:* `euler` only, with `cavities` as a P6.9 follow-on if a model asks for it.
4. **`adjacency = :full` on hex.** The two adjacencies are identical on hex. The options are to accept it silently or to make it a build error.
   *Recommended:* follow whatever P6.3g decides for `Local` and `Simple` on hex, for consistency.
5. **Observable-only use.** A model that reads `euler` only in `@observed` could skip the tracker and recompute from σ at save time. That would give zero per-copy cost, at the price of a σ transfer per save.
   *Recommended:* always track (one rule, as with `surface`), since the cost is about 20 integer ops per copy. Revisit only if a benchmark says otherwise.
6. **Cluster-scope χ (compartments) later.** The same kernel works with the predicate `cluster[owner[n]] == cluster[c]`. It is not needed by any listed model.
   *Recommended:* not in v1.
