# Target authoring sketches — index and cross-model findings

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** These sketches are proposals, not decisions. They show each paper model
> written with `@potts_model` from public, family-general primitives. Syntax for unbuilt features
> is proposed, not decided. Written 2026-09-30 by six parallel agents; none of the code has been run.

Tags in the code: `[R#]` planned roadmap feature · `[NEW]` not on the roadmap · `[?]`/`[verify]`
an untested combination of existing primitives · `UNSPECIFIED` a value the paper does not give.

| # | Sketch | Code lines | Heaviest dependencies |
|---|---|---|---|
| 1 | [01_merks.md](01_merks.md) — `MerksCore` + `Merks2006` / `Merks2008` via `@extend` | 105 | R5 phase order and boundary, R2 `Eden`/`Splits` |
| 4 | [04_foam.md](04_foam.md) | 78 | R1 `tie`, R10 proposal laws, streaming T1 counts |
| 5 | [05_bauer2009_ecm.md](05_bauer2009_ecm.md) | 122 | empty medium, R4 as a state energy, R8, R14 |
| 6 | [06_jiang2005_tumor.md](06_jiang2005_tumor.md) | 140 | 3D, fractional attempts, coarse fields, R13 network, necrotic core |
| 7 | [07_bauer2007_sprouting.md](07_bauer2007_sprouting.md) | 98 | R14 implicit every step, `@convert` to a cell, argmax tip |
| 8 | [08_fbca.md](08_fbca.md) — SC1 base + 08b `@extend` | 118 | R15 LP `CellOperator`, copy-time field writes, division by draw |
| 9 | [09_cell_sorting.md](09_cell_sorting.md) — GG + Osborne/Chaste | 96 | contact-pair folds, annealed-copy measurement |
| 10 | [10_akeeb_invasion.md](10_akeeb_invasion.md) | 93 | `InsertUntil` report, R16 metrics in docs |
| 11 | [11_multiscale.md](11_multiscale.md) — Jafari Nivlouei + Andasari component | 164 | R13 tables, R14, directed edge memory |
| 12 | [12_zajac_convergent_extension.md](12_zajac_convergent_extension.md) — reconstruction | 93 | R7 tensor, R11b interface pair energy |
| 13 | [13_starruss_myxobacteria.md](13_starruss_myxobacteria.md) | 89 | R9 angles, ordered chains, two-hop references |
| 14 | [14_nucleus_migration.md](14_nucleus_migration.md) — 14a/b + 14c `@extend` | 118 | R8 `@convert` contract, replaceable rules |

## 1. Defects or limits in features that already exist

| Finding | Models | Evidence / proposal |
|---|---|---|
| `Chemotaxis(...)` always gates on `new != 0`, so copies where the medium gains a site are never chemotactic | 01 (2006 every copy; 2008 ext.+retr.), 10 (CC3D either-cell gate), 11, 14 (C7) | `src/vocabulary.jl:636`. Move the gain test into the default of `when`, or add `parties = :gaining \| :either`. The shipped models use raw `@drive`, so nothing current is wrong; the helper just cannot express these papers |
| `connectivity(k)` accepts 0 components, so extinction needs a separate `no_extinction`; neither `:arc` nor `:arc_or_pair` equals TST's rule | 10, 01 | CC3D's rule is one soft drive `1e5 * ((old != 0) & (local_components != 1))`; TST's is writable from `ring_arcs`, `ring_cells` and an `any` gather. Test `local_components` against CC3D's count over all 2⁸ ring patterns |
| `a`, `b` are not reserved names; a parameter `b` probably shadows the pair built-in silently | 12 | `src/macro.jl` reserved list — unverified |
| `integral(...)` is recomputed after the sweep but before `@after_mcs` updates, so it reads last MCS's site variables | 05 | Allow gathers inside `integral` bodies, or document the order |
| A filtered fold over an empty set gives NaN | 08 | Folds need a `default` |

## 2. Planned features that need their design changed

- **R4 soft continuity**: Bauer 2009 Eq 1 and Jafari Nivlouei Eq 3 are state energies (a cell pays α while it is fragmented, and a reconnecting copy earns −α), not a per-copy drive. Proposal: a cell-scope `components` built-in with an exact after-value, like `major_length` (05, 11).
- **R5 phase order**: every model needs an explicit order that covers the sweep, fields, components, lifecycle, updates and host operators, not only fields (01, 06, 08, 10, 14). Coarse grids have four open semantics: what a fine-site read returns, source restriction, the moving Dirichlet clamp, and cell averages (06).
- **R8 `@convert`** must deliver sites to an existing cell (`the(kind)` or a `CellRef`), not create one per site. It needs a stated sequential contract (recompute before each candidate, a shuffled order) and a fractional budget with carry-over (05, 07, 14). FBCA's serial per-cell LP has the same shape: one general "sequential shuffled host pass" (08).
- **R11a `neighbors(c)`** needs a `relation` keyword (foam sides, 09 V-PRE6, Akeeb's von Neumann metrics) and must be usable in rule `when` scope (04, 06, 09, 10).
- **R14 implicit** is needed at every step, not only for the initial state: 05 (~7900 substeps/MCS), 07 (~5×10⁵), 11 (~15,000; ROADMAP P6.10 lists only R5).
- **R9** needs 3-body syntax (`angles(rel)`), ordered chains with `prev`/`next`/`rank`, and two-hop references (13).
- **R7** must name the physics inertia tensor's quantities explicitly (`eccentricity`, `orientation`, `polar_moment`), apart from `elongation` (12).
- **R10**: decide where the proposal law is declared (04); what `mcs` means with fractional attempts (06: a `step` alias); a source predicate on `UnlikeNeighbor` (07).
- **R2 layouts** must emit cell columns, links and `cluster`, not only ownership and kinds (13, 14). They also need `InsertUntil` with a miss report (10) and `Tiling(; partial = :clip)` (10).

## 3. New primitives that recur (not on the roadmap)

| Primitive | Models |
|---|---|
| Contact-pair folds in `@observed`: `count(expr for _ in contacts(rel))` | 09, 04, 13 |
| Initial values from the state (`V_target => volume`, `@initialize`, `@initialization_equations`) | 04, 05, 07, 10 |
| `argmax` fold returning a `CellRef` (tip cell, dominant type) | 05, 07, 08 |
| `the(kind)`: a singleton cell reference | 05, 06, 07 |
| Named rules, drives and energy terms that `@extend` can replace | 01, 08, 13, 14 |
| Kind tables with symbolic scalar entries (scan one J by `remake`) | 01, 10 |
| `separation` / `minimum_image` / `centroid(c, k)` for periodic geometry | 13, 14 |
| Kind 0 that is not a medium, or an empty medium | 05, 07 |
| Verify: `remake(prob; u0 = saved state)` and `@observed` on an annealed copy | 09, 12, 13 |
| Run statistics: acceptance rate, cumulative accepted ΔH, division event log, streaming per-MCS hooks | 12, 01, 08, 04 |
| Small ones: vector `ifelse` (13), fold defaults (08), an `UNSPECIFIED` sentinel (11, 12), `along = rand(...)` (08), `spread(...)` copy-time writes (08) | — |

## 4. New author questions raised by the sketches (not yet in README §5)

- **Bauer 2009:** Eq 1 sums over sites, which may count each pair twice (a 2× J question).
- **Bauer 2007:**
  - Under the one-cell reading of fluid and matrix, J_ff = 35 and J_mm = 5 never enter H.
  - A single starting EC never divides, so a sprout started from one cell stalls.
- **Foam:** which relation defines a bubble's sides (the same gap as 09 V-PRE6).
- **FBCA:** `mmc1.xls` has no arginine exchange, and its L-lactate transport is export-only, so SC1's oxidative type cannot take up lactate (affects V08a-1/2). Both come from a string search; confirm with a parser.
- **Jafari Nivlouei:** read literally, Fig 3 sends every inactive endothelial cell to apoptosis, so the table must be limited to tumour cells (an unstated choice).

## 5. Things that already compose

- Starruß's Eq 6 contact rule and the Eq 4 length energy (`edges(chain) => ζ(distance − D)²`) work today.
- Tip-only chemotaxis in Bauer 2007 is exactly `Chemotaxis(V; strength, when = tip[new] > 0)`.
- TST's exact connectivity rule (Merks) is writable today from R0 built-ins.
- `ExplicitEuler(substeps = 1)` reproduces CC3D's "diffuse + decay, then secrete" order for Fortuna's F-actin.
- Every Fortuna 14a energy reads only the copy's owners and `cluster`, so the checkerboard is exact there.
- Foam's shear drive is writable today from coordinate site variables; R1 is mostly sugar apart from `Metropolis(tie)`.

## 6. Errata from the topology audit (2026-10-01)

These drafts are kept unedited for audit. A port must apply these corrections (source:
`../../topology-neighborhood-audit.md` §4, §6). The specs themselves are already correct
unless noted.

| Sketch | Error | Correct form | Evidence |
|---|---|---|---|
| 13 (l.49, 124, 246) | `Hex(2)` called "12 sites" | `NeighborOrder(2)` on `Hexagonal()` = 12; `Hex(2)` is the 18-site hex-distance ball | `lib/CorePotts/src/lattice.jl` `Hex`, `_candidates(::NeighborOrder, N, ::Hexagonal)`; README Y3 and `api-synthesis.md` fixed |
| 06 (l.163) | plain Metropolis proposals | unlike-neighbour proposals: "one of its unlike neighbors' ID" | 06 p.3; spec 06 §2 row "Neighbourhood" |
| 05 | default `VonNeumann(1)`, uniform proposals | unlike-neighbour proposals from the 2007 lineage (`NeighborOrder(2)` + `UnlikeNeighbor`), or document VN(1) as a deviation | spec 05 l.43, G8; 07 p.7 |
| 08 (l.115) | 08b `lattice = (175, 115)` | `(115, 175)`: spec 08 gives h × w = 175 × 115 and the 11 × 115 vessel spans the width; Potts tuples are (x, y) | 08b p.285–286 |
| 08 (l.102) | SC1 `Tiling((5, 5); kinds = [ox, fe])` alternates by id, which gives vertical stripes on 20 (even) columns | **Open:** Fig 2A may show a checkerboard (visual reading only); confirm before porting | 08a Fig 2A |
| 04 (l.67, 90) | sides and T1 neighbour lists on `Moore(1)` | `VonNeumann(1)` by default (spec 04 updated) | 04b p.5823 |
| 11 (11b component, l.180) | `VonNeumann(1)` proposals with no deviation note | "up to fourth nearest neighbour" = `NeighborOrder(4)` (20 sites), or a stated deviation | 11b p.11; spec 11 l.160, l.285 |
