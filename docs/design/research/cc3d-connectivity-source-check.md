# CompuCell3D `Connectivity` plugin: source check across versions (P6.3k, D-189 ruling 11)

2026-10-08, spec-owner session. A read-only check to settle what CC3D's local `Connectivity`
plugin does in the versions the Akeeb authors used, before any page or paper text claims
"exactly CC3D".

**Source.** `CompuCell3D/core/CompuCell3D/plugins/Connectivity/ConnectivityPlugin.cpp` in
github.com/CompuCell3D/CompuCell3D, read at the tags 4.3.1, 4.6.0, 4.7.0, 4.8.0, 4.9.0 and at
`master` (2026-10-08).

**Akeeb inputs** (`docs/references/codebases/10_Akeeb2026_Leader_Follower_Invasion_Model/`,
the authors' release):
- The three 2D samples (`Multimodal_invasion`, `Single_cell_invasion`, `No_Invasion`,
  `Simulation/CCIecm.xml`) declare `Version="4.3.1"`. They set
  `<Plugin Name="Connectivity"><Penalty>100000</Penalty></Plugin>` (l.29–31), Potts
  `<NeighborOrder>1</NeighborOrder>` (l.17) and `<Temperature>10.0</Temperature>` (l.16). The
  cell types are Medium, LC and FC (l.36–38).
- The 3D samples declare 4.6.0 and do not load `Connectivity`. They could not: the plugin
  throws on a 3D lattice (below).
- The paper names CC3D 4.6.0 (spec 10 D9).

## 1. Findings

1. **The `<Penalty>` value is honoured in 4.3.1 and 4.6.0, and ignored from 4.7.0 on.**
   - In 4.3.1 and 4.6.0, `update()` reads `penalty = _xmlData->getFirstElement("Penalty")->getDouble()`
     (l.48) and `changeEnergy` returns `penalty` on rejection (l.89, l.125).
   - In 4.7.0, 4.8.0, 4.9.0 and master, `update()` is `//Nothing to do`, and `changeEnergy`
     returns a hard-coded `64` ("The energy returned can be any positive number; it is
     arbitrary for ConnectivityPlugin").
   - So the Akeeb runs, at 4.3.1 or 4.6.0, used **ΔH += 10⁵** per violating copy. At T = 10 the
     acceptance factor is e^(−10⁴), which is 0 in double precision, so the rule is effectively
     a veto.
   - Under CC3D ≥ 4.7.0 the same XML gives a penalty of 64. At T = 10 that is an acceptance
     factor of e^(−6.4) ≈ 1.7 × 10⁻³ per violating attempt, so cells can fragment. **Anyone
     re-running the Akeeb XML on a current CC3D gets different dynamics.** That is worth a
     sentence on page 10 and in the paper.
   - The research audit's "soft 64 in current source" (connectivity-vocabulary.md §3) is
     correct for master and wrong for the authors' versions.
2. **`changeEnergy` is otherwise identical in 4.3.1, 4.6.0 and master.** Apart from the
   penalty source, the diff shows only commented-out logging. It returns 0 if `oldCell` is the
   medium; otherwise it applies two rules.
   - **Rule 1 (gain test).** If `newCell` owns no first-order (face, `NeighborOrder(1)`: 4 in
     2D) neighbour of the target, it returns the penalty. This also applies when `newCell` is
     the medium.
   - **Rule 2 (ring test).** It walks the 8 sites around the target in clockwise order and
     counts transitions between consecutive sites where either is `oldCell` and the two differ.
     It accepts only if the count is exactly 2: `oldCell`'s ring sites form exactly one
     contiguous arc. Zero transitions (no `oldCell` on the ring, or a **full ring** of `oldCell`)
     and 4 or more (two or more arcs) are penalised.
3. **The plugin is 2D only.** `initializeNeighborsOffsets` throws `CC3DException` when all three
   dimensions exceed 1.
4. **Quirk at a closed edge** (as written in all versions read). In `changeEnergy`,
   `std::vector<Point3D> n(numberOfNeighbors, Point3D())` initialises every ring position to
   (0, 0, 0). When a ring neighbour is invalid (off a non-periodic face, so `neighbor.distance
   == 0`), the code `continue`s and leaves `n[i]` at (0, 0, 0). Rule 2 then reads **the owner
   of pixel (0, 0, 0)** for those ring positions.
   - In the Akeeb 2D samples, y is non-periodic and the slab starts at the bottom rows, so the
     three ring positions below a bottom-row target read whatever cell owns (0, 0, 0).
   - That can add or merge arcs for cells touching the bottom wall.
   - I did not run CC3D to measure how often this changes a decision. It is a source-level
     observation, flagged [unverified effect size].

## 2. Akeeb's `connectivity(leader, follower)` + `no_extinction` against CC3D 4.3.1

| CC3D behaviour | Potts.jl today (`akeeb.jl:62–63`) | Same? |
|---|---|---|
| Applies to every non-medium losing cell (LC and FC are the only non-medium types) | `connectivity(leader, follower)` | yes |
| Penalty 10⁵ at T = 10, a veto in effect | hard `@constraint` | yes, up to e^(−10⁴) |
| Rule 1, gain test: `newCell` has a face neighbour at the target | Potts proposals are `VonNeumann(1)` (CC3D NeighborOrder 1), so the source is always a face neighbour owned by `newCell`. Rule 1 can never fire | yes (vacuous) |
| Rule 2, exactly one arc of `oldCell` on the 8-ring | `local_components == 1` (3×3 flood fill, face adjacency within the ring). The ring components equal CC3D's contiguous arcs | yes |
| Zero arcs penalised (last site, isolated fragment) | `:local` rejects zero pieces; `no_extinction` also forbids the last site | yes |
| Full ring penalised | `:local` counts a full ring as one piece and accepts it | differs in principle. **Unreachable here**: with face-neighbour proposals the source is on the ring, so a full ring of `oldCell` means `newCell == oldCell`, a null move |
| Closed-edge quirk: off-lattice ring positions read pixel (0, 0, 0) | off-lattice sites are "nothing" | **differs for bottom-row targets** (finding 4) |

**Conclusion for the Akeeb text.**
- "Exactly CC3D 4.3.1/4.6.0" is accurate for the rule and its strength, with **one
  exception**: the closed-edge (0, 0, 0) read in finding 4.
- Recommended wording: "the CC3D 4.3.1/4.6.0 `Connectivity` rule with penalty 10⁵ (a veto at
  T = 10), except at the closed bottom edge, where CC3D reads off-lattice ring positions as
  the cell at pixel (0, 0, 0) (a source quirk we do not reproduce)".
- Also add: "CC3D ≥ 4.7.0 ignores `<Penalty>` and uses 64".
- Whether to *reproduce* the quirk is a maintainer call. I recommend **not** reproducing it:
  it is an implementation artefact and not part of the model. Record it as a deviations row
  with "suspected effect: small, bottom-wall cells only; unmeasured".

## 3. Consequences for the D-189 vocabulary rulings

- **Ruling 3 (`Local(; gain)`, default on).** CC3D's gain test is **face adjacency** (`NeighborOrder(1)`) and also applies when `newCell` is the medium. `Local(; gain = true)` should test exactly that, so `Local()` with defaults equals CC3D's rules 1 and 2. For Akeeb (face proposals) the gain test is vacuous, so the frozen results cannot change from it.
- **Ruling 10 (refuse the full ring).** This matches CC3D rule 2. For Akeeb it is unreachable (see the table), so again no change. It bites only for models whose proposals reach past face neighbours, such as legacy `MerksVasculogenesis`.
- **"Penalty" semantics in `connectivity(…; penalty)`.** The mapping table should map CC3D 4.3.1–4.6.0 to `@drive connectivity(k; rule = Local(), penalty = P)` with the XML's P, and CC3D ≥ 4.7.0 to the same with `penalty = 64`. The hard `@constraint` form is the T-limit of either.
- **Closed edges.** The (0, 0, 0) quirk is a third behaviour, besides "nothing" (ours) and "a cell" (TST's frame, P6.0ae). It should not become a rule option. Record it in the mapping table as a CC3D source artefact.

## 4. Not checked

- Morpheus and Artistoo were not re-read here; see connectivity-vocabulary.md §3.
- `ConnectivityLocalFlex` and `ConnectivityGlobal` were not diffed across tags.
- No CC3D run was made, so finding 4's frequency is unmeasured.
