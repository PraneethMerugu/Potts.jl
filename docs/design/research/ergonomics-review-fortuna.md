# Ergonomics review: compartment cells, references and `@convert` (Fortuna, 14)

2026-10-13, spec owner. A paper review, done before the code exists. Inputs:
- the P6.5a interface as frozen in `lib/PottsModels/test/acceptance/p6_5a_cell_refs.jl` (header §A–G);
- the P6.5b contract (D-233 draft; spec 14 §9 ruling);
- the 14 sketch (`model-specs/sketches/14_nucleus_migration.md`);
- AUTHORING;
- `research/initial-state-vocabulary.md`.

The maintainer asked for fixes to land with P6.5b. Each item says where it belongs:
- **[5b]**: in the P6.5b item or its batch;
- **[5a-fix]**: a small follow-up on the P6.5a branch before it merges;
- **[5c]**: already planned for P6.5c, so make sure it lands.

The test was to write the Fortuna model as a newcomer would, and record every place where they would need to know an implementation detail, hold an index in their head, or could make a silent mistake.

> **Superseded in part (audit 2026-10-13).** Spec 14's ruling fixes the targets from t = 0, with no `V_target` transfer: the cytoplasm target is (1 − φ_n − φ_l)V and the lamellipodium target is φ_l·V. The conversion probability reads the parameter, p = c·(1 − V₃/(φ_l·V_cell)), not `V_target[to]` (which gives 0/0 when the lamellipodium is absent). E1's default example and E3's `p` and `transfer` usage below predate this ruling. `transfer` remains a general primitive, but Fortuna does not use it.

## Summary

| # | Friction | Severity | Fix | Where |
|---|---|---|---|---|
| E1 | Compartment cells are assembled by hand: `cluster => [1, 1, 3, 4]` and per-slot `V_target` vectors, which need the slot order | high (silent wrong cell) | `Group` in layouts, plus kind-conditional defaults for cell variables | [5c] Group; [5b] defaults |
| E2 | Contact tables are positional k×k matrices in kind order | high (silent physics bug) | named-pair parameters with symmetric fill | [5b] batch |
| E3 | `@convert` makes the author write the clamp and the volume bookkeeping | medium | `p` clamped to [0, 1] by the runtime; `transfer` helper for target-volume moves | [5b] |
| E4 | A dead reference silently reads as the medium | medium (hidden bugs) | `checkbounds`-style debug mode that warns on dereferencing a dead referent; doc pattern `alive(ref)` | [5a-fix] warn only in debug |
| E5 | `sibling(k)` is undefined with two alive members of kind k | medium (future models) | error at runtime status word in debug, documented rule "lowest birth" otherwise | [5a-fix] |
| E6 | Vocabulary load: new/old vs source/target vs owner/owner′; `old == 0` for the medium | medium | docs table + lint; prefer `kind[old] == medium` in all examples; a `medium(c)` predicate | [5b] docs |
| E7 | Missing helpers the sketch needs: `centroid(c, k)`, `minimum_image`, `cluster_integral` | medium (workarounds) | add the three as cell-scope built-ins | [5b] if small, else [5c] |
| E8 | Energy refuses `volume[ref]` while a drive accepts it | low (message explains) | keep; make the error name the drive alternative and link AUTHORING | [5a-fix] message text |

## Items

### E1. Building compartment cells (high)
**Now (sketch l.111–117):**
```julia
op = layout(overlay(Spheres(...; kinds = [:cytoplasm]), Tiling(...; kinds = [:nucleus]), Plane(...), Plane(...)), cell)
op = [op; cluster => [1, 1, 3, 4],
      :V_target => [floor(0.85V) + 0.5, floor(0.15V) + 0.5, 0, 0]]
```
The author must know that ids follow layer order and that the planes took slots 3 and 4. They also have to compute each compartment's target volume by hand. Getting either wrong runs without complaint.

**Fix.**
- `Group` (planned at P6.5c, initial-state-vocabulary §5.4 l.378) emits `cluster`. Make sure it lands with P6.5c and that the 14 docs use it:
  ```julia
  op = layout(overlay(Group(Objects(Sphere(c, R); kind = :cytoplasm),
                            Objects(Box(c, 6); kind = :nucleus)),
                      Fill(:substrate; region = z == 1), Fill(:lid; region = z == Lz)), cell)
  ```
- For `V_target`, use a **kind-conditional default** declared in the model, so the op never carries a per-slot vector:
  ```julia
  @variables V_target(cell) = ifelse(kind == nucleus, φ_n, ifelse(kind == lamellipodium, 0.0, 1 - φ_n)) * V_cell
  ```
  This needs cell-variable defaults that are expressions of `kind` and parameters, evaluated at problem construction. That is the R17/D-075 expression-defaults item. Check whether it exists. If it doesn't, it is the [5b] part of E1, because `@convert` moves `V_target` between compartments and the initial values must be right.

### E2. Named contact pairs (high)
**Now:** `J[kind, kind] = [1 20 -20 20 40/3 100; …]`, a 6×6 matrix plus a second 6×6 for intra-cluster contacts. One transposed or misplaced entry is a silent physics error. Fortuna has 21 distinct pairs per table.

**Fix.** A pair form for kind-indexed parameters that fills symmetrically and defaults the rest:
```julia
J[kind, kind] = Pairs(default = 0.0,
    (medium, substrate) => 20, (medium, cytoplasm) => 20, (medium, lamellipodium) => 40/3,
    (cytoplasm, nucleus) => 20, ...)
```
- Compile-time checks: unknown kind names are an error; a pair given twice is an error; asymmetric input is only allowed with `symmetric = false`.
- It lowers to the same matrix, so there is zero runtime cost.
- It is independent of P6.5b, but small enough for that batch.
- Keep the matrix form for compact tables such as Graner–Glazier's 3×3.

### E3. `@convert`: let the runtime do the bookkeeping (medium)
**Now (sketch l.82–89):** the author clamps p themselves, writes `V_target[to] += …` and `V_target[from] -= …`, and handles `created`.

**Fix, in the P6.5b contract.**
- **Clamp p.** The runtime clamps `p` to [0, 1], as the D-233 ruling's "clamped at 0" requires anyway. The author writes the paper's formula verbatim, `p = c * (1 - volume[to] / V_target[to])`. The tests already cover V₃ ≥ target converting nothing.
- **`transfer` helper.** `transfer(V_target, from => to, per_site = 1.0)` moves a per-cell quantity per converted site, applied once per cluster with the conversion count. That is correct under the per-MCS independent-decision kernel, where counts are known after decide. Writing `+=` per conversion invites code that assumes a sequential order.
- **Defaults for `from`, `to` and `at`.** `from` defaults to the cluster member the block is declared on, so `clusters(cytoplasm)` gives `from = sibling(cytoplasm)`. `at` defaults to all of `from`'s sites. Fortuna then needs only `to`, `at` and `p`.

The resulting base block:
```julia
@convert protrusion clusters(cytoplasm) begin
    to = sibling(lamellipodium)
    at = touches_substrate(site)
    p  = c * (1 - volume[to] / V_target[to])
end
```
**Note for the test author.** If `transfer` is adopted, it needs one frozen oracle: target-volume conservation per cluster.

### E4. Dead references (medium)
A dead referent reads as the medium with defaults (D-066 item 5). That is correct and fast, but a model that forgets `alive(ref)` gets plausible-looking zeros.

**Fix.**
- No hot-path cost in normal runs.
- In a debug mode (the existing self-check or a `check = true` solve flag, whichever exists), count the dereferences of dead referents per term. Report once after the solve, e.g. "`V_target[to]` read a dead cell 312 times".
- Document the guard pattern in AUTHORING next to `sibling`.

### E5. `sibling(k)` with several members of kind k (medium)
Fortuna never hits this case; myxobacteria (13) and multi-nucleus variants would.

**Fix.**
- Define the rule now so it isn't left accidental: the alive member with the lowest `birth`.
- In debug mode, set a status-word bit when there is more than one candidate.
- One sentence in AUTHORING.

### E6. Vocabulary (medium)
- A newcomer meets `source`/`target` (sites), `new`/`old` (cells), `owner`/`owner′` (contact pairs), and `cluster`, `sibling`, `members`, `root`, `CellRef`, `alive` and `birth`.
- The sketch's `old == 0` means "the medium", and it is opaque.

**Fix (docs, in the P6.5b batch).**
- A single "Names inside a copy" table in AUTHORING: site versus cell, before versus after, and examples of each.
- Every example uses `kind[old] == medium`, never `old == 0`. Check that this form compiles; the OpenVT model already uses `kind′ == medium`.
- A short "Compartment cells" how-to page, written against the real Fortuna model when P6.5d lands.

### E7. Helpers the 14 sketch needs (medium)
- `centroid(c, k)` (another cell's centroid), for polarization Π and the 14c Q statistics.
- `minimum_image(d, axis)`, for wrapped differences on periodic axes.
- `cluster_integral(x)`, for 14c's base statistics. **Renamed 2026-10-14 (maintainer):** `integral(x; over = cluster)`.

Without them, the 14b/14c observables need host code. All three are cell-scope reads with no sweep-time cost. They land with P6.5b if they're small; otherwise they become P6.5c rows, but they must be in place before P6.5d.

### E8. The energy/drive restriction message (low)
The D-209 refusal is correct. Make the message carry the fix: "`volume[partner]` changes during the sweep, so an `@energy` term cannot read it (ΔH only sees the copy's two cells). Read it in a `@drive` (a per-copy work term), or store it in a cell variable at `@after_mcs`."

## Not changed
- `CellRef` as an integer slot under the hood (no device cost).
- Reading references in drives but not in energies (D-209).
- The per-MCS `@convert` semantics (D-233).

These are correct, and they are the right defaults.
