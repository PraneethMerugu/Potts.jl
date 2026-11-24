# Field-compiler cutover: design of record (summary)

This is a summary of `research/field-compiler/v3-design.md` (2026-10-16, converged after pass 4),
kept in the repository so that the branch carries its design. Where this summary and v3 differ,
v3 wins. Decisions: D-256 (the cutover and its rulings) and D-257 (the open decisions), both
provisional until the maintainer confirms them.

## 1. What changes

Today a model's fields go `@equations` → Expr → `CorePotts.FieldStep`, with explicit Euler only.
The cutover replaces that path with an MTK-native lattice PDE compiler for finite volume (and,
after the merge, lattice-aligned Q1 FEM). It adds Backward Euler and IMEX, multigrid and PCG with
a multigrid preconditioner for masked solves, quasi-steady and steady-init solves, discrete maps
through `Shift(t, 1)`, coarse grids, and the lagged switch.

A Potts model becomes a `PottsSystem` (W-lite LA): an `AbstractSystem` that wraps a flattened,
complete `System`, a `PDESystem` and the CPM payload.

## 2. Packages and dependency direction

```
ModelingToolkitBase, Symbolics, SymbolicUtils, DomainSets
            │
            ▼
       LatticePDE ──────────► LatticeFields ◄──── CorePotts (imports Exec)
   (discretizer, operators,   (Exec, IR, Compile,        ▲
    keys, BC parser,           Schedule, FV, Solvers,    │
    linearity table,           Problems; FEM later)    Potts ──► PottsModels, MakiePotts
    MTK → IR lowering)
```

- **LatticeFields** (MIT): KernelAbstractions, Adapt, StaticArrays, SciMLBase, SII,
  SciMLStructures, SciMLOperators, RuntimeGeneratedFunctions, Polyester. Weak: AMDGPU, Metal,
  CUDA, LinearSolve, Krylov, OrdinaryDiffEq. No MTKBase, Symbolics or CorePotts.
- **LatticePDE** (MIT): LatticeFields, MTKBase, Symbolics, SymbolicUtils, DomainSets. It
  re-exports `Grid`, the steppers and `Interval`. `LatticeDiscretization <:
  SciMLBase.AbstractDiscretization`.
- **CorePotts** depends on LatticeFields and uses `Exec` for its own CPU and launch paths. It
  still loads no MTKBase or Symbolics.
- **Full ModelingToolkit (AGPL) leaves the workspace** (C1). PureKLU (LGPL-2.1+, through
  LinearSolve, a hard dependency of MTKBase) remains and is named in the license section.
- **No LBM code** in the cutover or before the paper.

## 3. Layers

| Layer | Object | Owner |
|---|---|---|
| L0 Model | `PottsSystem(name, inner::System, fields::PDESystem, part)`; standalone: a `PDESystem` | `@potts_model`, `Potts.wrap`, `Potts.compose` |
| L1 Discretization | `LatticeDiscretization(grid; methods, T, backend, problem)` | LatticePDE |
| L2 Analysis | operation-keyed bindings, BC parser, linearity table, map and offset-read classification, cross-read graph → order | LatticePDE |
| L3 IR | `Program{N}`: fields, tables, masks, flags, kernels (hash-consed DAG), boundary rules | LatticeFields.IR |
| L4 Passes | legality → fold/zeros → semantic BC resolution → **fingerprint** → hoist → types → index lowering → emit | LatticeFields.Compile |
| L5 Schedule | order, cost-model fusion, ping-pong, launch plans, MG and PCG plans | LatticeFields.Schedule |
| L6 Execution | RGF bodies, host executor, one generic device wrapper, parallel compile | LatticeFields.Exec |
| L7 Outputs | owned `FieldProblem`, `ODEProblem`, `LinearProblem`, Potts phases | LatticeFields.Problems, Potts |

## 4. The MTK-native rule and what we own

Every user-visible symbolic object is an MTKBase variable, parameter, `Equation`, `System` or
`PDESystem`. The IR is an internal, one-way lowering target. Three things MTK lacks are owned
and disclosed:

- **S-2, coupling.** Fields read the CPM through `[input = true]` dependent variables of the
  `PDESystem`. Bindings are keyed by the input's operation and stored per component as
  (path, name), so composition renaming does not break them. The CPM reads fields through
  registered `at(c, target)` reads, cell reductions and solver-written site arrays.
- **S-3, operators.** Positional, callable-struct operators (`Δ`, `DivKGrad`, `Advect`, …) and
  an own linearity table (`linear_expansion` cannot see registered operators).
- **S-5, boundary conditions.** LatticePDE parses `bcs`, including masked interior conditions.

Kind tables are read with `at(Dk, kindₛ)` and `at2(J, k, k′)`, never MTK `getindex`, wherever a
template compiles (MTK issue F-5). Maps are `Shift(t, 1)(c(t, x, y)) ~ rhs`; `ShiftIndex`
arguments and `Pre` are refused.

## 5. The IR and compiler

- **Values, not types:** `Sel` index selects, epochs, masks and flags, `FaceRule` Robin
  boundaries, an n-ary hash-consed DAG. FV and FEM only.
- **Storage:** lanes keyed by element bitstype; one array per field.
- **Emission:** an `if`-guard kernel wrapper, interleaved stores, `Launch{K, WG, NP}`, static
  ndrange for single-ndrange bodies, a plan walk emitted per plan as a RuntimeGeneratedFunction
  (no `@generated`), and host-parallel compile.
- **Fusion:** every kernel fuses with its neighbor in the step order whenever that is legal
  (D-335; the cost model of the cutover design is deleted).
- **Ordering:** topological over the cross-read graph, Jacobi inside cycles, `Sequential` for a
  stated paper sequence (D-257 item 2).
- **Masked solves:** an eliminated SPD form; rule M and the Any fold in the hierarchy; PCG with
  a fixed V(2,2) Chebyshev preconditioner, budget 8; a stationary budget-12 fallback.
- **Derivatives:** an IR tangent pass after boundary resolution; an interval evaluator; adjoints
  deferred.
- **Fingerprint:** the semantic IR after pass 2 plus the layout, with the additivity invariant
  (D-257 item 1).

## 6. KernelAbstractions and backends

The cutover lands on KA 0.9.43. Branch code follows the bump-safe rules (v3 §9.1). The bump to
KA 0.10 is one later commit, after JumpProcesses, LinearSolve #1388, AllocCheck (LLVM 10),
RecursiveArrayTools 4.5.5 and Metal 1.12 are registered. Escalation dates: 2026-10-30 and
2026-11-27. The C0 dry run found the cutover's own upstream gate empty: no `[sources]` pins.

## 7. Budget

About 9.5k CTX-comparable lines (ruling 1), read as the cutover cap (D-257 item 4).

| Module | v3 cap (k) | Cutover (k) |
|---|---|---|
| `Exec` | 0.55 | 0.55 |
| `IR` | 1.34 | 1.34 |
| `Compile` | 1.71 | 1.71 |
| `Schedule` | 0.48 | 0.48 |
| `FV` | 1.56 | 1.56 |
| `Solvers` | 1.66 | 1.66 |
| `FEM` (after the merge) | 0.85 | 0 |
| `LatticePDE` | 1.61 | 1.61 |
| **CTX-comparable** | **9.76** | **8.91** |
| `Problems` (outside CTX) | 0.80 | 0.80 |
| Potts + CorePotts, net | ≈ +1.30 | ≈ +1.30 |

More than 15% over a v3 module cap during implementation is a stop-and-report item.

## 8. Commit sequence (v3 §11.2)

| # | Content | Gate |
|---|---|---|
| C0 | D-entries, dry-run resolve, spot-checks, this folder | resolve on registered packages; no P |
| C1 | Remove full ModelingToolkit | AGPL scan; suites |
| C2 | `Exec` on KA 0.9.43 (`lib/LatticeFields` skeleton) | paired CPU + ROCm A/B; PG-0, PG-13, PG-15; frozen run |
| C2b | LatticePDE vocabulary (no lowering) | unit tests; the Merks fingerprint may move |
| C3 | MTK-native symbols (`potts_entity`, real `@parameters`, `at`/`at2`, V3-3 rewrites) | frozen run |
| C4 | W-lite LA container | 53-check suite; refusal matrix and its negative control |
| C5 | IR, Compile, Schedule | builder and fault-injection self-tests |
| C6 | LatticePDE discretizer | end-to-end oracles from `PDESystem` |
| C7a | FV explicit, problems, SII | PG-1, PG-2, PG-6, PG-10, PG-14 |
| C7b | MG (rule M), PCG, stationary path | PG-4, PG-5; rule-M negative control |
| C7c | Tangent pass, IMEX, lagged switch, maps | dot-product test; T-ports |
| C8 | The switch; old field code and its non-frozen tests deleted | PG-3, PG-11 (ROCm), PG-12, PG-13; frozen = expected set |
| C9 | Components by `Potts.compose`; SciMLStructures on `PottsParameters`; `PottsCatalystExt` dropped by the user's ruling (2026-10-17: Catalyst 16 → Latexify → Ghostscript_jll, an AGPL-3.0 binary) | AGPL scan |
| C10 | Docs and D-entries (supersede D-137; amend D-159, D-016/D-107, D-145, D-051, …) | docs build |

Every commit builds and passes the non-frozen suites. The frozen suite runs on C2, C3, C8 and the
head; its failures must equal `expected-frozen-diffs.toml`. After C10: one list-A re-freeze
approval, `fixup!` commits folded into C2, C2b, C3 and C8, then the merge with the maintainer's
OK. After the merge: FULL reruns, the FEM library, then the KA 0.10 bump. LBM after the paper.

## 9. Re-freeze list A (v3 §11.3)

1. Field-model fingerprints (Merks pin `0xe8c37fa651d985f6`; may first move at C2b).
2. Non-field code pins from C2 (executor) and C3 (symbol identity and order).
3. MTK-container contract files: `p6_0o_abstract_system.jl`, `p6_0bs_mtk_claims.jl` (C1/C9),
   `p6_0bm_hamiltonian_metadata.jl`, `p6_0bp_updates.jl`.
4. Bitwise digests → statistical tests with pre-registered statistic, tolerance, replicates and
   a perturbed-model negative control.
5. Launch-count pins (Merks 100² from `8 + 2·15` to about `8 + 15 + 1`, inside `[23, 38]`).
6. Checkpoints: pre-cutover checkpoints are refused.
7. D-250 AUTO candidates (`P60BK2_IR` and any other declared String pin).
8. Frozen tests broken by C8's deletions: `p6_0v3_launch_fusion.jl`, `p6_3b_boundary_schedule.jl`,
   `p6_0y_stable_substeps.jl`; check `p6_0bn_ode_mtkcompile.jl`.

List B (the KA 0.10 bump) is separate and comes with the bump commit.

## 10. Top risks (v3 §13)

- **First-MCS margin** (R-2): parallel compile is required; measured end to end on ROCm at C8;
  fallback PCG → stationary MG.
- **W-lite LA coupling to MTKBase** (R-1, R-10): pinned by the 15-method list test and the SII
  checks on every MTKBase bump.
- **Float32 port of rule M and PCG** (R-5): proven in Float64 only; ported at C7b.
- **O-2 refused** (R-14): fallback is hashing emitted Exprs.
- **KA 0.10 bump gate** (R-12): off the paper path; escalation dates above.
