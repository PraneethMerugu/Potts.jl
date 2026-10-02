# Potts.jl target API — one synthesis of the twelve sketches

> **RATIFIED by D-075 (maintainer, 2026-09-30) at round 3.** Where this document says
> "D-07x (TBD, ≥ D-075)" or "pending ratification", read D-075. 2026-09-30, round 3 (revised after two adversarial
> reviews of the same day). Written as if Potts.jl were an in-house SciML package (the stance
> of Catalyst, MethodOfLines and JumpProcesses), so that a CPM reads as one more problem
> type in the ecosystem. Nothing here is implemented; every claim about existing code cites
> `file:line` at `monorepo` HEAD, and every claim about a SciML package cites the version
> the workspace `Manifest.toml` pins.

Inputs: the twelve sketches in `model-specs/sketches/` and their index; `AUTHORING.md`;
`src/vocabulary.jl`, `src/macro.jl`, `src/problem.jl`, `src/observed.jl`,
`src/compose.jl`, `src/layouts.jl`, `src/components.jl`, `src/schedule.jl`,
`src/compile.jl`, `src/codegen.jl`; `lib/CorePotts/src/{CorePotts,algorithms,problem,
sequential,checkerboard,model}.jl`; `benchmark/gate.jl`; DECISIONS D-029…D-074; ROADMAP
Phase 6 (steps 0–12 as of 2026-09-30, including P6.0c, P6.0g, P6.0m, P6.2a2, P6.5b);
`feature-roadmap-review.md` R0–R16; `model-specs/README.md` §2–§4, §6. Package names were
checked against the **pinned** versions: ModelingToolkitBase 1.77.0
(`~/.julia/packages/ModelingToolkitBase/IwLYy`), SciMLBase 3.56.1 (`SciMLBase/AFdol`),
DiffEqBase 7.21.2 (`DiffEqBase/wJ4a3`: the Manifest's git-tree `bf9fd5cc…` resolves to
that slug by `Base.version_slug`; `wRYJL` is 7.21.1), SymbolicIndexingInterface 0.3.55
(`SymbolicIndexingInterface/faxpV`), DiffEqCallbacks 4.19.4 (`DiffEqCallbacks/LYx6b`),
JumpProcesses 9.33.1. ModelingToolkit itself is not in the Manifest; its `NEWS.md` is cited
from the depot copy of 11.45.1 (`ModelingToolkit/brqnn`).

Status tags used below: **exists** (usable at HEAD), **R#** (planned, roadmap row), **new**
(not on any roadmap row), **amend** (changes a recorded decision; called out explicitly).

### Revision log (round 3)

Each item of the second review (`/tmp/api-synthesis-review-r2.md`) and what changed.

| Item | Resolution | Where |
|---|---|---|
| **D1** DiffEqBase path | The reviewer is right: `bf9fd5cc…` → `DiffEqBase/wJ4a3` (7.21.2; `wRYJL` is 7.21.1). Every DiffEqBase citation now reads `wJ4a3/src/solve.jl:653` (`solve`), `:150` (`init`), `:164`/`:720` (jump methods) | inputs paragraph; §0.1; §3.1; §7 item 3; §8.1 Q2 |
| **N1** solver move unbuildable, silent Merks change | Solvers are baked into generated code at problem construction (`src/codegen.jl:386-387, 427, 442, 466`; the fingerprint is taken there, `src/problem.jl:87`). Redesign, MOL-style: `field_solver`, `ode_solver` and `solvers` are **keywords of `PottsProblem(sys, op, tspan; …)`**, resolved in Potts and compiled at the one existing codegen point; **no algorithm-level solver fields**, because an override there would mean codegen at `init` (a `remake` is the override); **no silent default**: a model with a field and no `field_solver` is a construction error naming the keyword, so `benchmark/gate.jl:29`, `lib/PottsModels/test/mechanisms.jl:324-348` and the tutorials are migrated explicitly in P6.0c, not changed silently. The non-existent "Merks `papers.jl` band" is replaced by the actual checks (`mechanisms.jl:324-348`, `gate.jl:29`). `default_algorithm` dropped. D-016 row added (fingerprint includes the solver spec) | §2.1; §2.4; §2.11; §3.1; §3.4; §5.1; §5.2; §5.4; §6.1; §6.4 P6.0c; §7 items 1–2; §8.1 Q9 |
| **N2** model content in CorePotts algorithm types (D-046) | `track` moves to `PottsProblem(…; track = (:ΔH, :chemo))`, where Potts compiles it into a generated accumulation function and a state buffer (RGF ids and state NamedTuples are the per-model types D-046 allows); `CheckerboardCPM(; count = true)` stays, as a plain `Bool` with no model content; `solvers` is resolved in Potts at construction (N1). No algorithm type parameter carries a model name; D-046 row added as **unchanged, applied** | §2.13; §3.1; §3.4; §3.7; §6.1 |
| **S1** Q6 windowed BFS | Reworked: the propose kernel only appends local-test failures to a compacted per-colour list; a **separate deferred kernel** runs the windowed BFS over that list (bitmap in registers, `MVector{…, UInt16}` stack that spills only in that kernel, AllocCheck proof under D-047 because `propose_body!` also runs as a CPU loop, `checkerboard.jl:204-209`); occupancy cost confined to the deferred kernel and measured in the P6.9 late-state A/B; `window` is a keyword of `components`/`Global()`, not of D-074's local `connectivity(k)`; overflow depends on piece *length*, so conservative rejection is exact only when `exp(−α/T) ≈ 0`, which P6.9 checks for 05 and 11 | §2.5; §8.1 Q6; §6.4 P6.9 |
| **S2** checkerboard `attempts` | `attempts = 4` no longer "runs the cycle four times": each sub-cycle gets its own `local_index` in `draw` (`lib/CorePotts/src/rng.jl:78-82`, the slot already reserved for round/substep) and `_color_order!` takes the sub-cycle too (`checkerboard.jl:196, 227`); the thinning draw and the `at_init` draws get named streams. D-031 F-1/F-2 row added (`attempts == 1` keeps today's streams bit for bit) | §2.12; §6.1 |
| **S3** `track`/`count` buffer | "per-colour-site" was wrong (`prio`/`source` are reused per colour, `checkerboard.jl:143, 173`); the buffer is **lattice-indexed** (N entries), written once per site per colour cycle (race-free), accumulated across sub-cycles, reduced once per MCS | §2.13; §3.7 |
| **S4** R17's first consumer | P6.2a2 is StableRNG only; the Akeeb `clock`/`cue` expression defaults move to P6.4a with R17, with their own re-baseline under the same D-07x entry; clocks then vary with `replica` under a fixed layout (stated) | §2.4; §5.4 (10); §6.2 R17; §6.4 P6.2a2, P6.4a |
| **S5** amendments table | Rows added: D-016 (amend), D-038 (amend), D-046 (unchanged, applied), D-057 (amend, `paint!` signature), D-031 F-1/F-2 (amend); D-051 item 5 relabelled **amend (time-boxed)**; D-049 F-6 relabelled "amended by D-074" | §6.1 |
| **S6** ensemble default | Stated: with `AbstractPottsAlgorithm <: AbstractDEAlgorithm`, `solve(EnsembleProblem, alg)` matches `SciMLBase.__solve(::AbstractEnsembleProblem, ::Union{AbstractDEAlgorithm, Nothing})`, which defaults to `EnsembleThreads()` (`AFdol/src/ensemble/basic_ensemble_solve.jl:205-217`); today nothing matches (`CPMAlgorithm <: AbstractSciMLAlgorithm`, `algorithms.jl:42`) and the tests pass the ensemble algorithm explicitly (`lib/CorePotts/test/sciml.jl:11-19`). Resolution: CorePotts adds its own two-argument `__solve` method: `EnsembleThreads()` on the CPU backend (the OrdinaryDiffEq default), `EnsembleSerial()` when a GPU backend is passed, documented | §3.5; §6.1 |
| Nits | JumpProcesses precedent corrected (`AbstractJumpProblem <: AbstractDEProblem`; DiffEqBase special-cases it at `wJ4a3/src/solve.jl:164, 720`; Potts' route is simpler, not the same); `mcs_duration` reconciled to `0.75` (h, spec 06: 45 min per quarter-MCS step, `06_jiang2005_tumor.md:228, 251`) in §2.12 and §5.2; checkerboard `stats.attempts` labelled an expected count | §0.1; §2.12; §3.1; §7 item 3; §8.1 Q2 |

### Revision log (round 2)

Each item of the first review (`/tmp/api-synthesis-review.md`) and what changed. Entries
superseded by round 3 are marked.

| Item | Resolution | Where |
|---|---|---|
| **B1** stale depot versions | Every MTK/SciMLBase name re-checked against MTKBase 1.77.0 and SciMLBase 3.56.1. `parameter_dependencies` → `bindings` (`IwLYy/src/systems/system.jl:193`); `defaults` → `initial_conditions` (`system.jl:198`); `@mtkmodel` is deprecated in MTK 11 and moved to SciCompDSL.jl (`ModelingToolkit/brqnn/NEWS.md:328`, depwarn `IwLYy/src/systems/system.jl:584`), so `@potts_model` is positioned as Potts' own DSL over the functional `System(...)` keywords, as Catalyst's `@reaction_network` is | inputs paragraph; §0.1 rows 1, 5, 6; §2.3; §3.2; §7 item 8; §7.1 |
| **B2** `AbstractDiscreteProblem` captures `solve` | Supertype change withdrawn. `PottsProblem <: SciMLBase.AbstractSciMLProblem` (rename only). Evidence: `AbstractDiscreteProblem <: AbstractODEProblem <: AbstractDEProblem` (`AFdol/src/SciMLBase.jl:406, 386, 202`) and DiffEqBase, always loaded through MTKBase, owns `solve(prob::AbstractDEProblem, …)` (`wJ4a3/src/solve.jl:653`, corrected in round 3) and `init` (`:150`). `isdiscrete` is an algorithm trait (`AFdol/src/alg_traits.jl:124`); it is defined on `AbstractPottsAlgorithm` instead | §0.1; §0.2; §3.1; §6.1; §7 item 3; §7.1; Q2; §8.1 Q2, Q9 |
| **B3** `@on_copy` neighbour scatter | Rewritten: new syntax, new codegen (`_write` takes one index, `src/codegen.jl:286-297`) and a new write footprint (the compiler never sets `write`: `src/compile.jl:420`); plain stores, no atomics; colour cost 4 → 9 (2D), 8 → 27 (3D); lifecycle fires only `clear_on_ownership_change`; 08b conservation test on both algorithms and Metal; sequential first, checkerboard behind a recorded D-051 item 5 interim exception | §2.9; §2.13; §4 row "copy-time field spread"; §6.1; §6.4 (P6.12); §8.1 Q7 |
| **B4** feature-first build order | §6.4 rewritten as amendments to the existing ROADMAP Phase 6 rows (P6.0c, P6.0g, P6.0m, P6.2a2, P6.3a–d, P6.4a–c, P6.5a–b, P6.6–P6.12); every primitive lands with its first consumer model | §6.4 |
| **S1** law placement vs D-052 | `@sweep` names the model's *default* law (`Metropolis`, `Barker`) with its physics; `MetropolisHastings()` is **not** a `@sweep` value and stays the algorithm-level opt-in D-052 decided. Amendment row added (a clarification of D-052, no change of substance) | §0.1; §2.1; §2.12; §6.1; §8.1 Q1 |
| **S2** solver placement | *(superseded by round 3 N1)* Round 2 put all solver choice on the algorithm; round 3 moves it to `PottsProblem` construction (MOL-style) because the solver is compiled into the phases at construction. Still true: no `[solver = …]` metadata in the model; `Adaptive(alg; abstol, reltol)` **kept** (precedent: `DynamicSS(alg; abstol)`); `ExplicitEuler(substeps, lower)` keeps `lower`, so Merks' `lower = 0.0` (`lib/PottsModels/src/merks.jl:59`) survives verbatim | §2.1; §2.4; §2.11; §3.4; §5.1; §5.2; §5.4; §6.3; §7 items 1–2; §8.1 Q9 |
| **S3** `components` BFS on the checkerboard | *(reworked in round 3 S1: deferred kernel over a compacted list)* Device design specified: private-memory windowed BFS (bitmap + fixed stack), no shared visited buffer, conservative rejection with a counter when the window overflows; sequential stays the exact reference; late-state benchmark added because `benchmark/gate.jl` times 3 warm MCS from t0 on 5 fixed models and only flags Metal (`gate.jl:9-12, 91`) | §2.5; §8.1 Q6; §6.4 (P6.9) |
| **S4** `@on_copy H_acc += ΔH` | Dropped as an `@on_copy` write (model-scope on-copy writes are rejected, `src/codegen.jl:297`; `commit!` gets no ΔH, `sequential.jl:29-30`, `checkerboard.jl:127-128`). Replaced by an opt-in accumulator (`track = (:ΔH,)`; on `PottsProblem` since round 3 N2), exact on sequential, lattice-indexed buffer plus one reduction per MCS on the checkerboard, `nothing` when off (D-058 item 4); no global atomic | §2.13; §4 row "run statistics"; §5.4 (01); §6.2 R0b |
| **S5** `naccept`/`nreject` | Rename withdrawn: `DEStats.naccept` counts accepted *steps* (`AFdol/src/solutions/ode_solutions.jl:45-46, 64`). `PottsStats.accepted`/`attempts` stay; checkerboard counting is opt-in (`count = true`) through the same reduction as S4; `acceptance(sol)` returns `missing` when not counted | §0.1; §3.7; §4; §6.1; §6.2; §7 item 4; §8.1 Q9 |
| **S6** `@schedule` cost | "Compile-time permutation" withdrawn. `step!` hard-codes before → sweep → after → lifecycle → end (`lib/CorePotts/src/problem.jl:263-293`); the design now makes the sweep and the lifecycle entries of a static phase tuple, and states that every named host pass is one device↔host round trip per MCS on a GPU. D-035 amendment row added | §2.12; §2.9; §2.10; §6.1 |
| **S7** folds in energies; `interfaces` | Explicit compiler rejection of every fold over `neighbors`, `contacts`, `links`, `edges`, `angles`, `interfaces` and `sites(c)` inside `@energy`/`@drive` (today only site-term gathers are rejected, `src/compile.jl:195`). `interfaces(k, k)` cost stated: exclusive claims on every neighbour cell (8 in 2D Moore, 26 in 3D) plus a device pair store; sequential exact first. `linked(chain, owner, owner′)` in a contact term is exact | §2.5; §2.6; §5.3; §6.4 (P6.7) |
| **S8** unlisted science changes | Akeeb: D-074 (2026-09-30) now rules `connectivity(k)` = CC3D "exactly one component", so the shipped `@constraint connectivity(leader, follower)` (`akeeb.jl:53`) is kept and the soft `!= 1` drive is a sibling only; §2.5 and §5.4 corrected. Akeeb `clock` seeding as an expression default changes the RNG stream against the frozen `papers.jl` band (D-068, D-071): *(round 3 S4)* its own re-baseline at P6.4a, separate from P6.2a2's StableRNG one | §2.5; §5.4 (10); §6.1; §6.4 (P6.2a2, P6.4a) |
| **S9** R17 "is MTK's" | R17 is the Potts `at_init` host phase (`src/problem.jl:340-344`), not MTK's `InitializationProblem`; `remake(p = …)` re-runs it and re-draws `rand()` defaults for variables not in `u0` | §3.2; §6.2 R17; §7.1 |
| **S10** fractional `attempts` on the checkerboard | Specified: Bernoulli thinning per site from the counter RNG, compiled out when `attempts == 1`; `stats.attempts` records the expected count | §2.12 |
| Nits | `DEIntegrator{Alg, false, S, Int}` kept as at `lib/CorePotts/src/problem.jl:100`; `macro.jl:47` attributed to Potts; `vocabulary.jl:343-351` described as the symbolic `_gather` builder (loops in `src/lower.jl`); decision numbers written "D-07x (TBD, ≥ D-075)"; §0.1 no longer lists `@initialization_equations` as an MTK section; "Merks (ROADMAP step 3)" | §0.1; §2.6; §3.1; §6.4; §8.1 Q8, Q9 |
| Amendments table | §6.1 now lists every DECISIONS entry the proposal touches: D-052, D-035, D-049 F-6 (no change; D-074 confirms), D-058 item 4, D-029 (no atomic ships), D-051 item 5 (interim exception), D-031, D-032, D-068/D-071, D-066 | §6.1 |

---

## 0. Where a CPM sits in SciML

**A cellular Potts model is a discrete-time Markov chain on a lattice, clocked in MCS,
whose per-tick operator is a stochastic sweep that no symbolic system can express, plus
clocked deterministic dynamics (updates, fields, cell ODEs, lifecycle) that MTK can.**

Three abstractions were candidates. The choice, and why:

| Candidate | Use it for | Do not use it for | Why |
|---|---|---|---|
| **JumpProcesses** (`JumpProblem`, `SSAStepper`, aggregators `Direct`, …) | A future rejection-free algorithm (`KineticMonteCarlo()`) and the *exact-distribution oracle* on tiny lattices | The base abstraction | Every paper defines time in MCS (N attempts per unit), not in exponential waiting times. Mapping a sweep onto `VariableRateJump`s means N·|proposal| jumps whose rates depend on ΔH; the aggregators enumerate them per event (O(N)), which is the n-fold-way CPM, a *different algorithm* with different kinetics. The GPU checkerboard has no SSA analogue. We share the SciMLBase integrator/solution/callback/ensemble layer with JumpProcesses (`SSAIntegrator` is the model for `PottsIntegrator`, INTERNALS §1.9), and nothing else |
| **MTK discrete systems** (`Shift`, `ShiftIndex`, `Clock(dt)`, `ImplicitDiscreteSystem`) | Everything deterministic that happens once per MCS: `@before_mcs`/`@after_mcs` updates, Boolean networks, clocked components, cadence (`Every(n)` ≡ a slower clock) | The sweep, ΔH, lifecycle | The MCS *is* a clock tick with period `mcs_duration`. `x ~ f(Pre(x))` in an update is `x(k) ~ f(x(k-1))`. We adopt that meaning (D-042 already does) and lower `Pre(x, n)` to `Shift(t, -n)`. The sweep is a Potts-owned operator inside the tick |
| **MTK continuous systems** (`System`, `D(x) ~ …`, `@components`, `mtkcompile`) | Fields (PDE step), cell and model ODEs, MTK components | — | Unchanged from AUTHORING §6 |

So Potts **extends** MTK (a `PottsSystem <: AbstractSystem` with one extra operator, the
sweep, and lattice-scoped variables), **stands apart from** JumpProcesses at the problem
level, and **reuses** SciMLBase, SII, DiffEqCallbacks and EnsembleProblem unchanged. This is
the Catalyst pattern: `ReactionSystem` is its own `AbstractSystem` with domain statements
(reactions), and problems are produced from it; it does not pretend to be an `ODESystem`.

### 0.1 The SciML mapping table

| Potts concept | SciML/MTK counterpart | Same, or a stated deviation |
|---|---|---|
| `@potts_model` | Potts' own DSL, as `@reaction_network` is Catalyst's. MTK 11 deprecated `@mtkmodel` and moved it to SciCompDSL.jl (`ModelingToolkit/brqnn/NEWS.md:328`; depwarn at `ModelingToolkitBase/IwLYy/src/systems/system.jl:584`), so the maintained MTK surface is the functional `System(eqs, t; …)` with `@components` | Section names mirror MTK's `System` **keywords** where one exists: `@parameters`/`@variables` (`@parameters`/`@variables` macros), `@structural_parameters`, `@components` (`systems`), `@extend` (`extend`), `@equations` (`eqs`), `@discrete_events` (`discrete_events`), `@initialization_equations` (`initialization_eqs`, `system.jl:212`). Potts adds lattice sections (`@kinds`, `@lattice`, `@relations`, `@energy`, `@drive`, `@constraint`, `@sweep`, `@schedule`, lifecycle, relationships, `@boundary`, `@observed`, updates). No upstream section proposal is made against a deprecated macro |
| `PottsSystem` | `ModelingToolkitBase.AbstractSystem` (as Catalyst's `ReactionSystem`) | Same lifecycle: build → `extend` → `mtkcompile` → problem. `compose` is not implemented (D-039) |
| `mtkcompile(sys)` | `mtkcompile` | Same name; in addition derives ΔH (AUTHORING §4) |
| `PottsProblem(sys, op, tspan; kw)` | `ODEProblem(sys, op, tspan)`; type `AbstractSciMLProblem` | **Rename only.** `CPMProblem <: SciMLBase.AbstractSciMLProblem` (`lib/CorePotts/src/problem.jl:22-23`) becomes `PottsProblem` with the **same supertype**. `AbstractDiscreteProblem` was considered and rejected: it is `<: AbstractODEProblem <: AbstractDEProblem` (`SciMLBase/AFdol/src/SciMLBase.jl:406, 386, 202`), and DiffEqBase, always loaded because MTKBase depends on it, owns `solve(prob::AbstractDEProblem, args...; …)` (`DiffEqBase/wJ4a3/src/solve.jl:653`) and `init` (`:150`), which would run `solve_up`/`get_concrete_problem`/`promote_u0` on a `CPMState`. JumpProcesses stayed *inside* the DE hierarchy (`AbstractJumpProblem <: AbstractDEProblem`) and DiffEqBase special-cases it (`solve.jl:164, 720`); Potts' route, outside the hierarchy with CommonSolve methods, is the simpler one and needs no upstream special case. Verified by the reviewer's script (`/tmp/apirev/sciml2.jl`): a fake `<: AbstractSciMLProblem` with a `<: AbstractDEAlgorithm` gets no DiffEqBase method |
| `u0` | operating point `[x => v, …]`, `remake(prob; u0)` | Same. A saved state (`CPMState`) is also a valid `u0`. Symbolic entries (`A => volume`) are allowed, as MTK allows `u0 = [x => 2y]` |
| `initial_conditions`, `initialization_eqs`, `guesses` (MTKBase 1.77 names, `system.jl:198, 202, 212`; `defaults` was renamed) | MTK initialization | **Same surface, different engine (stated):** expression defaults and `@initialization_equations` are resolved by the Potts `at_init` host phase (`src/problem.jl:340-344`), not by MTK's `InitializationProblem`, because the unknowns are ragged per-entity columns (§3.2) |
| `t` | MTK `t` | `t` is the MCS index (`Int`); physical time is `t * mcs_duration`, the period of the Potts clock |
| `Pre(x)`, `Pre(x, n)` | MTK `Pre`, `Shift(t, -n)` | `Pre(x, n)` lowers to `Shift(t, -n)(x)`; `ShiftIndex` syntax is accepted in components unchanged |
| `Every(n)` | `Clock(n * dt)` | Lowered as a sub-clock of the MCS clock |
| `@components cells(k) name = sys` | `@components name = Sys()` | Same; the domain (`cells(k)`, `model`) is Potts. Any object with the component trait (§2.10) may be a component, MTK `System` being one |
| `@discrete_events`, `@terminate` | `SymbolicDiscreteCallback` → `DiscreteCallback`; `terminate!` | Same; `@terminate` is sugar |
| `solve(prob, alg; kw)` / `init` / `step!` / `solve!` | CommonSolve | Same (`lib/CorePotts/src/problem.jl:141, 263, 295`) |
| `SequentialCPM()`, `CheckerboardCPM()` | algorithm structs, `AbstractPottsAlgorithm <: SciMLBase.AbstractDEAlgorithm` (today `CPMAlgorithm <: AbstractSciMLAlgorithm`, `lib/CorePotts/src/algorithms.jl:42`) | Same idiom as `Tsit5()`; the algorithm holds only what is a run-time value in the kernels (`acceptance`, `proposal`, `count`), not sub-solvers, which are compiled into the problem (§3.4). `SciMLBase.isdiscrete(::AbstractPottsAlgorithm) = true` (an **algorithm** trait, `AFdol/src/alg_traits.jl:114-124`). Side effect of the retype, stated in §3.5: `solve(EnsembleProblem, alg)` then defaults to `EnsembleThreads()` unless CorePotts overrides it |
| `PottsProblem(sys, op, tspan; field_solver, ode_solver, solvers, track)` | `discretize(pde, MOLFiniteDifference(…))` (MethodOfLines): the numerics of a discretised operator are chosen when the problem is built | **Deviation, stated:** the field and ODE sub-solvers are problem-construction keywords, because they are compiled into the phases at the one codegen point (`src/codegen.jl:386-387, 427, 442, 466`) and hashed into the checkpoint fingerprint (`src/problem.jl:87`, D-016). `remake(prob; field_solver = …)` is the override (§3.4) |
| `Metropolis`, `Barker` in `@sweep`; `MetropolisHastings` on the algorithm | JumpProcesses aggregator / OrdinaryDiffEq sub-solver | **Deviation, stated:** the model's default acceptance law and its physics (temperature, offset, tie policy) are *model* content (`@sweep`), because they define the chain the paper wrote (as Catalyst's rate laws are model content). Today's wiring is exactly this: `_law(alg, f) = something(alg.acceptance, f.acceptance, Metropolis())` (`lib/CorePotts/src/algorithms.jl:19`). The Hastings correction stays an algorithm-level opt-in (`acceptance = MetropolisHastings()`), as D-052 decided; it is not a `@sweep` value (§2.12) |
| `PottsIntegrator` | `SciMLBase.DEIntegrator{Alg, false, S, Int}` (modelled on `SSAIntegrator`) | Same, unchanged (`lib/CorePotts/src/problem.jl:100`) |
| `PottsSolution` | `AbstractTimeseriesSolution`; `sol[x]`, `sol(t)`, `sol.retcode`, `sol.stats` | Same; `sol(t)` is exact lookup (D-031 F-10). `sol.stats` keeps `PottsStats` (`accepted`, `attempts`, `mcs`, `launches`, `lifecycle`): `DEStats.naccept`/`nreject` count accepted and rejected *steps* (`AFdol/src/solutions/ode_solutions.jl:45-46, 64`), a different quantity (§3.7) |
| `sol[x]`, `getu`, `setu`, `getp`, `setp`, `observed` | SymbolicIndexingInterface | Same (`src/observed.jl:108-138`). The symbolic container is the compiled system |
| `EnsembleProblem(prob; prob_func, output_func, reduction)` | SciMLBase ensembles | Same; trajectory `i` gets replica `i` unless `prob_func` changed the seed (`lib/CorePotts/src/problem.jl:382-395`) |
| `DiscreteCallback`, `CallbackSet`, `SavingCallback`, `PresetTimeCallback` | SciMLBase / DiffEqCallbacks | Same; continuous callbacks are rejected (`problem.jl:186-193`) |
| `ReturnCode` | SciMLBase | Same (`Default`, `Success`, `Failure`, `Terminated`) |
| units | MTK `VariableUnit` + DynamicQuantities extension | Same (D-039) |
| extensions | package extensions (weak deps) | OrdinaryDiffEq, LinearSolve, NonlinearSolve, SteadyStateDiffEq, COBREXA+JuMP, Metal/CUDA, DynamicQuantities, Graphs, MethodOfLines (oracle) |

### 0.2 Where Potts necessarily differs, and the cost

1. **The sweep operator.** ΔH-derived, fused, allocation-free kernels (D-014 amended,
   D-033) cannot come from `build_function` (Float32 literals, lazy `ifelse`, loops, status
   words). Cost: a Potts-owned lowering (`src/lower.jl`), already the case.
2. **Ragged, growing state.** Cell variables are per-cell columns whose length changes at
   MCS boundaries (D-013). SII therefore returns per-cell vectors for cell quantities and
   lattice arrays for site quantities (`src/observed.jl:57-66`). MTK assumes a fixed `u`
   vector. Cost: `sol[x]` is a `Vector{Vector}`/`Vector{Array}` rather than a matrix.
3. **Acceptance law in the model.** See the table. Cost: none; the algorithm keyword
   overrides it per solve.
4. **Integer time.** `tspan::Tuple{Int,Int}`, no interpolation. The same convention as
   `DiscreteProblem`, without its supertype (§0.1): Potts owns `solve`, `init`, `remake`
   and the ensemble hooks through CommonSolve, as JumpProcesses does.
5. **Host passes.** Some model content (`@convert`, `HostOperator`, `uptake`/`secrete`,
   model-scope `contacts(rel)` folds) runs on the host once per MCS. On a GPU backend
   each is one device↔host round trip per MCS; a model that declares none pays nothing
   (§2.12, D-035 amendment in §6.1).

---

## 1. Design principles

1. **Author the Hamiltonian and the chain; the compiler derives ΔH** (D-026). Unchanged.
2. **SciML homogeneity is hard.** Wherever MTK/SciMLBase has a convention it is used with
   the same name and lifecycle (§0.1). A deviation needs a reason in this document.
3. **Fewer, more general primitives.** One comprehension semantics over every domain (§2.6);
   one reference type (§2.7); one ownership-event routine (§2.9); one initialization
   mechanism (§3.2); one host-pass primitive (§2.9, §2.10); one phase vocabulary (§2.12).
4. **Zero cost when unused** (D-051 item 2, D-058 item 4): every feature below states its
   hot-path cost and how the unused path stays identical to today's loops.
5. **Both algorithms** (D-051 item 5): every feature works on `SequentialCPM` and
   `CheckerboardCPM`; where checkerboard exactness is relaxed, it is validated
   statistically (D-065 Q7) and said so.
6. **No model- or author-named paths in core** (guardrails, D-051 item 1). Every paper below
   is written from the public vocabulary of §2.
7. **Breaking changes are cheap now** (pre-1.0, local-only). Where a rename or a moved
   keyword buys a cleaner SciML shape, this proposal takes it and lists it in §6.

---

## 2. The model language

Section by section: syntax, semantics, what it lowers to, hot-path cost, status.

### 2.1 Sections (final list)

| Section | Purpose | MTK analogue | Status |
|---|---|---|---|
| `@structural_parameters` | literals in generated code | same | exists |
| `@kinds` | kinds (the first is label 0), `[frozen]`, **kind classes** | — | exists; classes P6.0g |
| `@parameters` | scalars, kind tables (entries may be expressions of parameters), vectors | same; a symbolic table entry is the MTK notion of a *binding* (`bindings`, `system.jl:193`), re-derived by Potts on `remake`/`setp` | exists; symbolic entries **new** |
| `@variables` | scoped state `x(site)`, `x(cell)`, `x(model)`, `c(field)`, `e(rel)`; metadata `[grid=…]`, `[clear_on_ownership_change]`, `::CellRef` | same; metadata is MTK metadata. **No solver metadata**: solver choice is a `PottsProblem` keyword (§3.4) | exists; `grid`, `CellRef` R5/R6 |
| `@lattice` | `Lattice(dims; boundary, neighborhood, spacing, geometry, domain)` | — | exists |
| `@relations` | named relations; `proposal = <law or relation>` | — | exists; laws R10 |
| `@relationship` | named cell–cell link sets; `ordered = true`, `directed = true` | — | exists; ordered/directed R9 |
| `@energy` | `[name =] domain => expr` | — | exists; names **new** |
| `@drive` | `[name =] copy => expr` | — | exists; names **new** |
| `@constraint` | hard proposal constraints | — | exists |
| `@sweep` | the chain's default law and physics: `Metropolis(; temperature, offset, tie, attempts, mcs_duration)` or `Barker(; …)`; never `MetropolisHastings` (D-052, algorithm-level) | — (Catalyst rate-law analogue) | exists; `tie`, `attempts` R1/R10; **solver keywords moved to `PottsProblem`** (§3.4) |
| `@schedule` | phase order within one MCS, including `sweep` and `lifecycle` as entries | — | R5, syntax decided here; needs the `step!` restructuring of §2.12 |
| `@before_mcs`, `@after_mcs`, `@on_copy` | clocked updates | discrete equations (`Shift`) / event affects | exists |
| `@equations` | `D(x) ~ …` fields, cell/model ODEs, component couplings | same | exists |
| `@boundary` | field boundary conditions per face or per site mask | MOL boundary equations | R5 |
| `@initialization_equations` | initial values from the state; steady fields | `initialization_eqs` keyword of `System` (`system.jl:212`); resolved by the Potts `at_init` phase, not `InitializationProblem` (§3.2) | **new** (MTK name) |
| `@divide`, `@transition`, `@retire`, `@create`, `@convert` | lifecycle and ownership events | — | `@divide` exists; rest R3/R8 |
| `@link`, `@unlink` | link rules | — | exists |
| `@components` | per-cell or model components (MTK systems, host operators) | same | exists; operators R15 |
| `@discrete_events`, `@terminate` | events | same; sugar | R3 |
| `@observed` | derived quantities | `observed` | exists; new domains §2.6 |
| `@extend` | inheritance with named replacement | same | exists; named replacement **new** |

Removed: nothing that exists is removed except the solver keywords of `@sweep`
(`field_solver`, `ode_solver`), which move to `PottsProblem` construction (§3.4). `Adaptive(alg; abstol,
reltol)` is **kept** as the tolerance bundle around an OrdinaryDiffEq algorithm (the
`DynamicSS(alg; abstol)` precedent). Not adopted from the sketches: `@initialize` (10),
`@kind_classes` (11), `@exchange` (08), `@relations proposal = … ` with a bare law (04 —
kept but the law wraps a relation), `the(kind)` (05/06/07 → `only`), `initial(volume)`
(05), `Fill`/`OneCell` (07 → `collective = true`), `cluster_integral` (14 → `sites(cluster)`),
`@convert x => y, sites => …` keyword form (05/07 → the block form), `order = (Sweep(), …)`
in `@sweep` (06 → `@schedule`).

### 2.2 Kinds and kind classes (P6.0g)

```julia
@kinds begin
    medium                              # label 0; may own no site (05, 07)
    fluid; matrix                       # collectives: ordinary cells
    tip; stalk; prolif
    border[frozen]
    ecm         = (fluid, matrix)       # a class: a named set of kinds
    endothelial = (tip, stalk, prolif)
end
```

- A class is usable everywhere a kind list is: `cells(endothelial)`, `clusters(class)`,
  `kind ∈ endothelial`, `kind[new] ∈ ecm`, `@transition cells(endothelial) => …`,
  `@components cells(endothelial) …`, `no_extinction(ecm)`.
- Lowering: a class is a `Tuple{Int}` at construction; `kind ∈ class` becomes an unrolled
  `|` of equalities (what `_kind_in` does today, `src/components.jl:127`). Cost: none.
- **Label 0 stays the background** (σ = 0, no cell record). A model "without a medium"
  declares a background kind that owns no site and uses classes in its gates instead of
  `old == 0`. This keeps the hot path (`σ == 0` tests, medium never claimed, D-031) and
  needs no change. The dead kind-table row is cosmetic.
- Kind tables may be written by class: `J[kind, kind] = KindTable(ecm => ecm => 85,
  ecm => endothelial => 76, endothelial => endothelial => 30, medium => _ => 0)`. It expands
  to the full symmetric matrix at construction; overlapping entries are an error. Fixes 05
  friction 2 without a second table type.

### 2.3 Parameters with symbolic table entries (01 F6, 10 F4, 09)

```julia
@parameters begin
    J_cc = 40.0; J_cM = 20.0; J_cB = 100.0
    J[kind, kind] = [0 J_cM 0; J_cM J_cc J_cB; 0 J_cB 0]
end
```

`J` becomes a *bound* parameter in MTK's sense: MTKBase 1.77 calls the map "bindings"
(`ModelingToolkitBase/IwLYy/src/systems/system.jl:193`; the older `parameter_dependencies`
keyword no longer exists). MTK's bindings are scalar-keyed, so an array whose *entries*
are bound is not expressible upstream today (§7.1); Potts implements the re-derivation
itself: `remake(prob; p = [J_cc => 10])` and `setp(prob, J_cc)` re-derive `J` through the
existing hook (`src/problem.jl:222-229, 414-426`), and `J` is read-only through SII. Cost:
none at run time (tables are still `SMatrix` constants of the parameter object, D-012).
Status: **new**, small, and both `_derived_parameters` and `_param_value`
(`src/problem.jl:247-255`) change: the `Info(:kindtable)` default may hold a symbolic array
that must be evaluated against the scalar parameters.

A parameter with no default (`@parameters T`) is the **UNSPECIFIED sentinel**: `PottsProblem`
already throws "parameter `T` has no default; give it in the operating point"
(`src/problem.jl:202`). The `NaN` sentinels of 04/05/06/11/12 are replaced by that; no new
construct.

### 2.4 Variables: scopes, metadata, references

```julia
@variables begin
    act(site)   = 0.0, [clear_on_ownership_change = true]
    c(field)    = 0.0                                                      # its solver is a `PottsProblem` keyword (§3.4)
    O2(field)   = 0.0, [grid = Coarse(4; restrict = mean, prolong = Nearest(), clamp = All())]   # R5 (default per §8.1 Q5)
    A(cell)     = volume                                                   # expression default → initialization equation
    prev(cell)::CellRef                                                    # R6, D-066 item 5
    â(touch)    = 0.0, [directed = true]                                   # per-direction edge payload (11b)
    G(model)    = 1.0
end
```

- Metadata uses MTK's `[key = value]` list. `grid` is a Potts metadata key registered like
  `VariableUnit` (`src/vocabulary.jl:57-58`). There is **no `solver` metadata**: the grid is
  model content (where the field lives); the solver is a numerical choice made when the
  problem is built (§3.4, review S2/N1).
- An **expression default** (`A(cell) = volume`, `cue(site) = position[2] - 1`,
  `clock(cell) = ifelse(rand() < PP, floor(75rand()), -1)`) has MTK's meaning (an
  `initial_conditions` entry that is an expression, `system.jl:198`) and becomes an
  initialization equation `A ~ volume` (§3.2), resolved by the Potts `at_init` phase.
  Replaces `@initialize` (10), `A => volume` as a *special* op form (04), `initial(volume)`
  (05), and `V_target(cell) = volume` as a special case (07): all four are this one rule.
  A default that draws (`rand()`) is re-drawn whenever `at_init` runs, including
  `remake(prob; p = …)` (§3.2 item 3), from a named stream (`Potts.init.<var>`, the
  `stream_id` mechanism of `src/lower.jl:73`) addressed by cell id, so the draws vary with
  `replica` even under a fixed layout. A model whose seeding is frozen in a test band
  (Akeeb, D-068/D-071) migrates to it only with its own re-baseline (§6.4, P6.4a).
- `x(cell)::CellRef` declares a reference (D-066 item 5). `Int32` storage, 0 = none.
- Directed edge variables store two payload slots per link; `â` in edge scope reads the
  `a → b` slot, `â′` the `b → a` slot (the prime convention of D-061 reused).
- Cost: metadata is compile-time; references are one `Int32` column when declared.

### 2.5 Energies, drives, constraints, names

```julia
@energy begin
    area      = cells(endothelial) => λ * (volume - A)^2
    adhesion  = contacts           => J[kind, kind′]
    continuity = cells(endothelial) => α * (components > 1)                   # R4 as a state energy (amend)
    length    = edges(chain)        => ζ * (distance - D)^2
    curvature = angles(chain)       => ξ * (2sin(angle) / norm(separation(a, b)))^2   # R9
    aniso     = interfaces(cell, cell) => -contact * lever(a, interface_centroid) * lever(b, interface_centroid)   # R11b
end
@drive chemo = copy => -χ * (c[target] - c[source])
@constraint kind[new] == endothelial
```

- **Names are optional** (`name = domain => expr`). A named term is an observed quantity:
  `sol[curvature]` is the term's total over its domain, `sol[area]` its total, and
  `total_energy` is their sum. An `@extend` that redeclares a name **replaces** the base's
  term (same rule as updates, `src/compose.jl:41-46`). Fixes 01 F11, 13 F6, 14 F3.
  Cost: none; observed terms are evaluated on saved states only.
- **Domains** (`cells`, `clusters`, `contacts(rel)`, `sites`, `edges(rel)`, `model`) exist.
  New: `angles(rel)` (R9, every path `a – pivot – b` in an ordered relationship, once; binds
  `a`, `b`, `pivot`, `angle`, `separation`) and `interfaces(k₁, k₂)` (R11b, every touching
  cell pair once; binds `a`, `b`, `contact`, `interface_centroid`, and the pair's `Σp`,
  `Σppᵀ` aggregates, so both readings of Zajac's segment average are expressible, 12 F2).
  **Cost of `interfaces` in an energy (review S7):** a copy changes the pair trackers of
  `old`, `new` and every neighbouring cell of the target, so an exact ΔH needs *exclusive*
  write claims on all of them (up to 8 cells in 2D Moore, 26 in 3D, against today's 2
  plus shared read claims, D-058) and a dynamic pair store on the device (a bounded
  open-addressing table keyed by `(min(a,b), max(a,b))`, sized from `capacity` ×
  expected degree). Sequential is exact with a host `Dict`. Plan: sequential-exact first
  under P6.7 (D-051 item 3 already calls the exact per-copy form the reference), the
  checkerboard variant behind an A/B measurement, both acceptance items of P6.7 (§6.4).
  `angles(rel)` and `edges(rel)` in energies are cheap by comparison: links change only at
  MCS boundaries, so their reads are shared claims two hops deep.
- **`a`, `b` are reserved names** (12 F5). Today `_BOUND_BUILTINS` (`src/macro.jl:44-46`)
  omits them although `BUILTIN_NAMES` (`src/vocabulary.jl:36-39`) has them, so `@parameters
  b` binds silently. Fix: reserve globally (Zajac's semi-axes become `a₀`, `b₀`).
- **R4 amendment.** Bauer 2009 Eq 1 and Jafari Eq 3 are state energies α·[fragmented]: a
  cell pays while fragmented, a reconnecting copy earns −α, and only an energy enters
  `total_energy` and the self-check (05 F3, 11 F8). So `components` is a **cell-scope
  built-in with an exact after-value**, like `major_length` (`src/compile.jl:47`,
  `CorePotts.major_length_after`): evaluated for `old` by the local test and a BFS only when
  the local test fails, and for `new` only when the gained site touches two or more of
  `new`'s local pieces. The per-copy drive `E₀ * (local_components > 1)` stays the
  Merks/CC3D form. Copy-scope `local_components`, `ring_arcs`, `ring_cells` exist (R0).
  **`connectivity(k)` means CC3D's rule (D-074, 2026-09-30):** a copy is rejected unless
  every constrained cell it touches is exactly one component afterwards. Today it accepts
  0 components (`src/vocabulary.jl:410`; confirmed by the review's script: the last pixel
  and an isolated fragment can be taken), which P6.0m fixes under D-074. The shipped Akeeb
  model keeps its hard `@constraint connectivity(leader, follower)`
  (`lib/PottsModels/src/akeeb.jl:53`, D-049 F-6); the soft drive
  `E * ((old != 0) & (local_components != 1))` (10 F2) is a *sibling* for the family, not
  a change to Akeeb. The 2⁸-ring enumeration test against `ring_arcs` is its test. Cost:
  none unless `components` appears in a term; then one local test per copy and a BFS on
  failure. The global rule is `components` (cell scope) or `Global()` on a drive, and
  **the BFS window is their keyword** (`components(; window = W)`, `Global(; window)`),
  not `connectivity(k)`'s, which is CC3D's local rule and has no window. The device
  design (a deferred BFS kernel over the compacted list of local-test failures), its
  unmeasured failure rate on thin sprouts, and the benchmark that would actually see it
  are in §8.1 Q6.
- `centroid` becomes allowed in energies once R7 gives it an exact after-value (D-032 text
  "not allowed" is superseded by R7).
- `Chemotaxis(c; strength, response = identity, when = new != 0)`: the gain test moves into
  the **default** of `when` (`src/vocabulary.jl:635-639` ANDs it unconditionally, which
  cannot express 01, 10, 11 or D-067 C7). `when = true` is every copy; `when =
  (kind[new] == a) | (kind[old] == a)` is CC3D's either-cell gate. Status: R0 follow-up.

### 2.6 One comprehension semantics: folds over every domain

`fold(body for x in DOMAIN if cond; init)` is the single iteration construct, in any scope
where the domain is meaningful:

| Domain | Elements | Names bound in `body` | Where it may appear | Lowering / cost |
|---|---|---|---|---|
| `R(s)` (a relation at a site) | neighbour sites | `x` (site), site variables `v[x]` | everywhere | unrolled loop over literal offsets (exists: the symbolic `_gather` node is built at `src/vocabulary.jl:343-351`; the loop is emitted by `src/lower.jl`) |
| `Moore(1; include_self = true)(s)` | same, with the origin | same | everywhere | exists |
| `cells(k…)`, `clusters(k…)` | alive cells / roots | `c` (a `CellRef`), `v[c]`, `centroid(c, k)` | updates, rules, observed; energies as per-MCS snapshots (D-041) | population kernel, hoisted per D-042 (exists) |
| `sites` | every lattice site | `s`, `owner[s]`, `v[s]`, `position` | same | exists |
| `sites(c)`, `sites(cluster)` | a cell's / a cluster's sites | site names; gathers allowed inside | cell updates, rules, observed, temperature; **not** energies | `CellReduce` at the boundary (the `integral` machinery, `src/vocabulary.jl:227-231`); recomputed where D-042's ordering requires (fixes 05 F5 rim staleness: the body may contain a gather, and a `sites(c)` fold reading a variable written earlier in the same block sees the new value) |
| `contacts(rel)` | unordered unlike site pairs | `kind`, `kind′`, `x`, `x′`, `owner`, `owner′` (the D-061 env) | `@observed`, updates at model scope | one host pass over the lattice (**new**; 09 F1, 04 F8, 13) |
| `neighbors(c; relation = contact)` | distinct neighbouring cells incl. the medium (ref 0) | `n` (a `CellRef`), `contact(c, n)`, `contact_point(c, n)` | rules' `when`, updates, observed | `ContactPhase` at MCS cadence (R11a; the `relation` keyword is decided here: 04 F4, 09 F7, 10 F7) |
| `links(c, rel)` | incident links | `(n, e)`: partner ref and edge handle; edge variables `x[e]` | same | link-store loop (**new**; 11b) |
| `edges(rel)`, `angles(rel)`, `interfaces(k, k)` | as in energies | the domain's names | `@observed`, model updates | host pass (**new**; 13 F6) |
| `members(cluster)`, `members(cluster, k)` | a cluster's cells | `m` | cell scope, rules | small loop over the cluster's members (R6) |

Folds: `sum`, `prod`, `count`, `any`, `all`, `mean`, `geomean`, `log1p_geomean`, `minimum`,
`maximum`, `argmin`, `argmax`, `only`, `var` (**new**: `argmin`/`argmax`/`only`/`var`).
`argmax(f, cells(k))` follows Julia's two-argument form and returns the **element** — a
`CellRef` (05 F4, 07 F4, 08 F12, 11 F11). `only(cells(necrotic))` is Julia's `only`: the unique
element, an error otherwise (replaces `the(kind)`; on the device the error is the status
word). `sibling(k)` ≡ `only(members(cluster, k))` but reads 0 when absent (D-066 item 5).

**Empty sets** (08 F7): `sum`/`count` → 0, `prod` → 1, `any` → `false`, `all` → `true`;
`minimum`/`maximum`/`argmin`/`argmax`/`mean`/`geomean`/`var` take Julia's `init` keyword
(`maximum(…; init = -Inf)`), and `mean`/`geomean`/`var` a `default` keyword; without one an
empty set is `NaN` for means and an error (status word) for extrema, as in Julia. `argmax`
with `init = 0` yields ref 0.

`integral(x)` remains as documented sugar for `sum(x for s in sites(cell))`. Today it reads
one MCS stale when its argument is written in the same `@after_mcs` (review script; P6.0m);
under the fold semantics above it follows D-042 ordering like every other read.

**Explicit rejection in energies (review S7).** Inside `@energy` and `@drive` the compiler
rejects every fold over `neighbors`, `contacts`, `links`, `edges` (outside the `edges(rel)`
domain itself), `angles`, `interfaces` and `sites(c)`, and every `Pre(...)` of a contact
structure, with a message naming the domain and the reason: those are per-MCS snapshots,
and a snapshot inside ΔH breaks the ΔH self-check on both algorithms. Today only site-term
gathers are rejected (`src/compile.jl:195`); the `cells(k)`/`clusters(k)` population
snapshots stay allowed under D-041's stated semantics. This check ships with the first
host-pass fold (P6.4a, §6.4).

### 2.7 References (R6) and geometry helpers

- `CellRef` values come from: `x(cell)::CellRef` variables, `argmax`/`argmin`/`only`,
  `sibling(k)`, `sibling(c, k)`, `members(...)`, `neighbors(c)`, `root(cluster)`,
  `prev(rel, c)`/`next(rel, c)` of an ordered relationship, and `owner[s]`. Any of them may
  be indexed: `v[ref]`, `kind[ref]`, `volume[ref]`, `centroid(ref, k)`, `alive(ref)`.
  Chains compose (`next(chain, next(chain, c))`, 13 F2); the footprint analysis derives the
  hop depth and widens claims (D-065 Q7: sequential is the reference, checkerboard is
  validated statistically).
- A dead referent reads as 0 (D-066 item 5). `alive(ref)` guards it.
- `centroid(c, k)` (cell-first, mirrors `displacement(c, k)`, `src/vocabulary.jl:219`);
  `centroid(k)` stays the current cell's (14 F4).
- `separation(a, b)`: the minimum-image vector `centroid(a) − centroid(b)` (13 F3);
  `minimum_image(d, axis)`: the scalar wrap (14 F5); both work on the rhombic hex torus
  through `CorePotts.min_image`.
- `cluster_centroid(k)` unwrapped (R7).
- Vector `ifelse` is component-wise on `QuantityVector` (13 F4; `src/vocabulary.jl:105`).

### 2.8 Relationships: ordered, directed, 3-body (R9)

```julia
@relationship chain(cell, cell) capacity = 2, ordered = true
@relationship touch(cell, cell) capacity = 12, directed = true
@link   chain when = …;  @unlink touch when = (contact(a, b) == 0) & (â == 0)
@after_mcs â ~ contact(a, b) / surface[a]        # edge-scope update (11b): a, b bound
```

- `ordered = true` keeps a rank per member so `prev(chain, c)`, `next(chain, c)`,
  `rank(chain, c)` and `linked(chain, a, b)` are one store (13 F1: replaces ν, prev/next
  references and the link list). `angles(chain)` enumerates consecutive pairs at each pivot;
  for `capacity > 2` it enumerates all pairs, stated in the docstring.
- Edge-scope updates (`@after_mcs` with an edge variable on the left) run in the link phase.
- Cost: the ordered store is one extra `Int32` column; angle terms read 2-hop partners,
  which are shared read claims (D-058) two hops deep.

### 2.9 Lifecycle and ownership events (R3, R8): one routine, one priority

```julia
@divide     cells(k…)  [Every(n)] when = cond, along = principal_axis() | RandomPlane() | rand((v₁, v₂)) | vector, x => rule…
@transition cells(k…) => k′  when = cond, x => rule…            # state rules read the pre-transition cell
@retire     cells(k…)  when = cond [, sites => medium | ref]     # default medium; `sites => only(cells(necrotic))`
@create     k  when = cond, at = Sphere(center, r) | Box(lo, hi) | RandomSite(region), x => value…
@convert    name domain begin … end                             # below
@terminate  [Every(n)] when = cond
```

- **Priority within one MCS** (review §4, unchanged): remove > convert > transition >
  divide > create. All are applied by one host routine that updates trackers, links,
  cluster roots, `sites(c)` sums, the frozen mask (P6.0d) and applies
  `clear_on_ownership_change` to every site whose owner changed (review gap [f]).
  **It does not fire `@on_copy`** (review B3): an `@on_copy` block is copy scope, where
  `source`, `target`, `old`, `new` and `ΔH` are bound; a lifecycle ownership change has no
  source and no ΔH, and firing 08b's neighbour scatter from a division would redistribute
  O₂ for no physical reason. A model that wants a rule-time effect writes it in the rule's
  state rules (`x => …`), which are the lifecycle's own hook. This corrects the wording of
  ROADMAP P6.5b ("ownership hooks fire `@on_copy` / `clear_on_ownership_change`"): only the
  second. Within one rule kind, cells are visited in id order; `@transition … limit = 1`
  fires for at most one cell per MCS (06 F2's core bootstrap).
- `along` accepts any cell-scope vector expression, including a draw from a finite set
  (`rand((…))`, 08 F4); CorePotts' `normal` takes any vector already.
- Division state rules are evaluated in the parent's environment; `daughter` (1 or 2) is
  bound (AUTHORING §12.7). `Split()`, `Copy()`, `Reset(v)`, `Redraw(dist)` exist.
- `@retire … sites => ref` delivers the sites to an existing cell; `V_target[ref] += volume`
  in its state rules is the scatter-add (06).
- **`@convert`** is the general *sequential host pass* with ownership writes:

  ```julia
  @convert protrusion clusters(cytoplasm) begin
      from  = sibling(cytoplasm)                 # CellRef expressions (cluster scope)
      to    = sibling(lamellipodium) | Fresh(lamellipodium)   # allocate when absent (born on first site, D-066 X2)
      sites = touches_substrate(site) & (owner[site] == from)  # candidate predicate (site scope)
      order = Shuffled()                         # visiting order from the addressed RNG
      p     = 0.1 * (1 - V_target[to] / (φ_F * sum(V_target[m] for m in members(cluster))))   # re-evaluated per candidate
      budget = deg                               # optional: sites per pass, fractional with carry-over
      V_target[to]   += ifelse(created, 1.5, 1.0)   # writes run once per conversion; `created` is bound
      V_target[from] -= ifelse(created, 1.5, 1.0)
  end
  ```

  `domain` is what the pass iterates (`cells(tip)`, `clusters(k)`, or `model` for one global
  pass). `p`, `when`, `gate` and the writes are re-evaluated **before each candidate** on the
  running trackers (14 F2). `budget` accumulates a fractional carry per entity (05 F7).
  It runs off the hot path, once per MCS (or per `Every(n)`), in `@schedule` order. The same
  host-pass machinery runs `HostOperator` components (§2.10). **Cost (review S6):** on a
  GPU backend a host pass is one device↔host round trip per firing: the pass's declared
  inputs (here `σ` in the candidate region, `V_target`, the cluster columns) are read back,
  the pass runs on the host, and its writes (`σ` at converted sites, the trackers) go back.
  That is more than D-035's "one 4-byte readback per checked MCS" and is recorded as an
  amendment (§6.1): the budget becomes *one readback for the lifecycle trigger, plus one
  round trip per declared host pass per firing*, and the model author sees it because the
  pass is a named phase in `@schedule`. On the CPU backend nothing is copied. A model with
  no host pass pays nothing (`nothing` in the phase tuple, D-058 item 4). Status: R8; this
  block form replaces the keyword forms of 05/07.

### 2.10 Components: MTK systems, clocked networks, host operators

`@components cells(k…) name = obj` accepts any `obj` with the component trait:

| Trait | Objects | Lowering | Status |
|---|---|---|---|
| `ContinuousSystem()` | MTK `System` with `D(x) ~ …` | batched cell ODE kernel (D-038, `src/components.jl:65-104`) | exists |
| `ClockedSystem()` | MTK `System` with `Shift`/`ShiftIndex(Clock(dt))`, Bool or Real unknowns | per-cell phase in the `components` slot; `dt = mcs_duration / k` gives `k` ticks per MCS (the "run to the attractor" sub-clock, 11 F3c) | P6.0k / R13 |
| `HostOperator()` | `FluxBalance(model; …)` (COBREXA/JuMP extension), any user `CellOperator(f!; inputs, outputs)` | host pass, `order = Shuffled() \| ByID()`, once per MCS (or `Every(n)`) in `@schedule` order; only declared inputs/outputs cross the device boundary, one round trip per firing on a GPU (§2.9 cost note) | R15 |

Couplings are `@equations name.p ~ expr` for every trait (`src/components.jl:56-60`), and
vector couplings (`grn.u ~ [rand() for _ in 1:8]`, 06 F5) are component-wise `_eq`
(`src/vocabulary.jl:143-147`). Component scope is a kind class, so state survives
`@transition` within the class (review gap [g]). Write-back of an operator's outputs to
sites is an ordinary update placed after it in the schedule and executed per entity in the
operator's order (08 X2):

```julia
@components cells(oxidative, fermentative) fba = FluxBalance(hmr; objective = "biomass_synthesis",
    optimizer = HiGHS.Optimizer, tiebreak = Parsimonious(), warm_start = true, exchanges = (O2 = "Ex_O2[s]", …))
@equations fba.uptake_O2 ~ sum(O2 for s in sites(cell))
@after fba begin                                # a per-entity write-back phase, sequential in fba's order
    O2[s ∈ sites(cell)] ~ Pre(O2) - fba.flux_O2 * Pre(O2) / fba.uptake_O2
end
```

`@after name begin … end` is the update block bound to a host pass (an `ImperativeAffect`
per entity, `ModelingToolkitBase/src/systems/imperative_affect.jl`); it replaces 08's
`@exchange`. Uptake and secretion sugar (§2.11) expand into such a pass.

**Upstream:** Bool-typed unknowns and `&`/`|`/`!` in `Shift` systems (11 F3a) are an MTK
gap; the workaround is 0/1 reals with `min`/`max`, recorded per D-065 Q9.

### 2.11 Fields: solvers, boundaries, grids, operators (R5, R14, R15)

```julia
@variables begin
    V(field)  = 0.0                                                      # implicit on the host: chosen when the problem is built (R14)
    c(field)  = 0.0                                                      # explicit device kernel (the default)
    O2(field) = 0.0, [grid = Coarse(4)]                                  # coarse grid (R5): part of the problem
end
@equations begin
    D(V) ~ D_V * Δ(V) - λ_V * V - uptake(V; max = β, by = kind ∈ endothelial, per = Cell())
    D(c) ~ Dc * Δ(c) + secrete(c; rate = α, by = kind == endothelial) - ε * c * (kind == medium)
end
@boundary V begin
    x => (Dirichlet(0.0), Dirichlet(S))          # per face
    sites(kind == border) => Dirichlet(0.0)      # masked clamp, applied every substep (01 M5)
end
@initialization_equations 0 ~ D_V * Δ(V) - λ_V * V - uptake(V; …)       # steady start (05/07 B7)

prob = PottsProblem(sys, op, (0, 5000);
    field_solver = ExplicitEuler(substeps = 15, lower = 0.0),                        # every field without an entry in `solvers`
    solvers = [V => Adaptive(KenCarp4(linsolve = KrylovJL_GMRES()); reltol = 1e-6)])   # per variable, symbolic keys
solve(prob, SequentialCPM())
```

- **Solver per variable is a `PottsProblem` construction keyword** (`solvers`, a
  symbolic-keyed map resolved in Potts like an operating point), not model metadata
  (review S2) and not an algorithm field (review N1): the field and ODE solvers are
  compiled into the phase code at construction (`src/codegen.jl:386-387` reads
  `substeps`/`lower`, `:427`/`:442` the cell and model ODE steppers, `:466` the adaptive
  host integrator) and hashed into the D-016 fingerprint (`src/problem.jl:87`). This is
  the MethodOfLines shape: `discretize(pde, MOLFiniteDifference(…))` fixes the numerics
  when the problem is built. P6.0c's wording "solver metadata per equation block or
  component" is amended to this (§6.4). `ode_solver` keeps today's default
  (`ExplicitEuler()`, `src/vocabulary.jl:614-616`, D-038); **`field_solver` has no
  default**: a model with a field and no `field_solver` is a construction error naming the
  keyword, so no call can silently change a paper's numerics (review N1). Any
  OrdinaryDiffEq algorithm is accepted inside `Adaptive(alg; abstol, reltol, dt)`, the
  tolerance bundle, kept (the same shape as SteadyStateDiffEq's `DynamicSS(alg; abstol,
  reltol)`). `ExplicitEuler(; substeps, lower, upper)` keeps its clamps, so Merks' shipped
  `ExplicitEuler(substeps = 2, lower = 0.0)` (`lib/PottsModels/src/merks.jl:59`) moves
  verbatim from `@sweep` to every `PottsProblem(MerksVasculogenesis(…), …)` call:
  `benchmark/gate.jl:29`, `lib/PottsModels/test/mechanisms.jl:324-348` and the tutorials
  are edited in P6.0c, and the compiler error catches any call that is missed.
- `uptake(c; max, relative = 1, by, per = Site() | Cell(), over = sites(cell) | rim(cell))`
  and `secrete(c; rate, by, over, clamp)` are **operator-split terms**: the compiler removes
  them from the PDE right-hand side and runs them once per MCS, conservatively, as a host
  pass in `by`'s order (D-065 Q8). In `@initialization_equations` they stay in the equation
  as smooth sinks (07 F7). This is the one keyword set that replaces the three of 05/07/11.
- `@boundary` lowers to boundary equations in the MethodOfLines sense; the masked clamp is
  a node value, the face form a ghost value (01 F7). Kind-mask clamps are re-evaluated every
  substep from `σ`, so they move with the cells (06).
- `Coarse(k; restrict = mean, prolong = Nearest(), clamp = All())` answers 06 F3 (default `All()` per §8.1 Q5): a
  fine-site read returns the prolonged value; kind-dependent sources are restricted by the
  mean over the node's fine sites; a mask clamps a node when the `clamp` rule holds over its
  fine sites; a cell mean is `mean(u for s in sites(c))` of the prolonged values.
- Cost: nothing when unused; the explicit device kernel is unchanged. Implicit and steady
  solves live in the OrdinaryDiffEq/LinearSolve/NonlinearSolve extensions and run on the
  host: on a GPU backend that is one field readback and writeback per MCS, the same cost
  class as a host pass (§2.9). `uptake`/`secrete` as operator-split host passes (D-065 Q8)
  cost the same round trip; a model whose uptake is a smooth sink in the PDE pays nothing
  extra.

### 2.12 The sweep and the schedule

```julia
@relations proposal = UnlikeNeighbor(NeighborOrder(4); source = kind == endothelial)   # R10 law wrapping a relation
@sweep Metropolis(; temperature = T, offset = 0.0, tie = Half() | Accept() | Reject(),
                  attempts = 1 // 4, mcs_duration = 0.75)      # h per step: 45 min per quarter-MCS (spec 06 Fig 3)
@schedule fields, before_mcs, sweep, after_mcs, components, protrusion, lifecycle
```

- **The chain is model content; the Hastings correction is not.** `@sweep` names the
  model's default law, `Metropolis` or `Barker`, with its physics: `temperature` may be a
  scalar, `T[kind]` or cell state (AUTHORING §12.1); `offset`; `tie` is the T ≤ 0 policy
  (R1, 04 F2); `attempts` is attempts per MCS as a number or a rational (D-051 item 2; the
  whole-MCS path compiles to today's loop); `mcs_duration` is the clock period (MTK
  `Clock(dt)`). `MetropolisHastings()` is **only** an algorithm value
  (`SequentialCPM(; acceptance = MetropolisHastings())`), as D-052 decided: it corrects a
  chain for its proposal law rather than defining one, and every reproduction runs the
  uncorrected chain. `@sweep MetropolisHastings(…)` is a compile error pointing at the
  keyword. This keeps D-052 as written (§6.1 records it as a clarification). `t` counts MCS
  steps; with `attempts = 1//4` a step is a quarter sweep and the docs say so (06 F1; no
  `step` alias).
- **Fractional and multiple `attempts` on the checkerboard (review S10, round-2 S2).**
  Sequential does exactly `round(q·N)` attempts per step. The checkerboard runs every
  colour and thins per site: each site attempts with probability `q` from a draw on a new
  named stream (`CorePotts.thinning`, `stream_id` as at `lib/CorePotts/src/rng.jl:67-69`),
  so the count per step is Binomial(N, q) with mean `q·N`; `stats.attempts` records the
  **expected** count `round(q·N)`, labelled as such in the docstring. `attempts = 1`
  compiles the gate out (`q == 1` is a structural parameter), so the default path is
  today's kernels and today's streams bit for bit (D-051 item 2). `attempts = 4` runs the
  colour cycle four times **with a sub-cycle index**: today `draw(key, mcs, t,
  STREAM_PROPOSAL)` (`checkerboard.jl:61`) and `_color_order!(order, key, mcs)`
  (`checkerboard.jl:196, 227`) have no such index and would replay identical proposals;
  the sub-cycle goes into `draw`'s `local_index` slot, which already packs
  round/substep/draw/retry (`rng.jl:76-82`), and into `_color_order!`. This is a D-031
  F-1/F-2 stream change for `attempts ≠ 1` only (§6.1). Jiang (3D, `1//4`) is the consumer
  (P6.11), and its acceptance compares the two algorithms' spheroid growth statistically
  (D-065 Q7).
- **Proposal laws** live in `@relations proposal` (D-049 F-1; the algorithm keyword
  overrides): `UniformNeighbor(rel)` (a bare relation means this), `UnlikeNeighbor(rel;
  source)` (all-site attempt counting, non-wall picks are null), `BoundarySite(rel)`
  (draws among boundary sites only). Each defines `proposal_ratio` for
  `MetropolisHastings`. Decided over 07's `law =` in `@sweep`.
- **`@schedule`** lists the phases of one MCS tick in order. The canonical names are
  `before_mcs`, `sweep`, `after_mcs`, `fields`, `components`, `operators`, `lifecycle`,
  `end_mcs`, plus any **named** rule or component (`protrusion`, `fba`). Unlisted phases
  keep the default order (today's: before → sweep → after → lifecycle → end, with fields
  and components inside the after phase). `end_mcs` (history push, `sites(c)` refresh,
  callbacks, save) is always last. One vocabulary serves Merks (fields first), Bauer 2007
  (rules → sweep → fields), Jiang 2005 and FBCA. `@before_mcs`/`@after_mcs` keep their
  names because D-042's semantics refer to them; the schedule only moves the other phases
  around them.
- **What it costs (review S6; replaces "a compile-time permutation").** Today `step!`
  hard-codes the order: `before_mcs` phases, then `sequential_mcs!`/`checkerboard_mcs!`,
  then `after_mcs`, then `run_lifecycle!`, then `end_mcs`
  (`lib/CorePotts/src/problem.jl:263-293`); only the update phases are a tuple. The design
  makes the sweep and the lifecycle *entries* of the compiled phase tuple
  (`SweepPhase()`, `LifecyclePhase()` sentinels dispatched in `_run_phases`), so `step!`
  becomes one `foldl` over a static tuple of at most a dozen entries, unrolled by the
  compiler with no dynamic dispatch. That is a restructuring of `step!` and of
  `Phases` (`src/schedule.jl`), not a permutation of what exists; it lands with Merks
  (P6.3b, §6.4) and is gated on Metal by `benchmark/ab.jl` because `gate.jl` only flags
  Metal (`benchmark/gate.jl:9-12, 91`). Once the tuple exists, a *device* phase order costs
  nothing; a *host* phase (`@convert`, `HostOperator`, `uptake`/`secrete`, a model-scope
  `contacts(rel)` fold) costs one device↔host round trip per firing on a GPU (§2.9), and
  the D-035 amendment in §6.1 says so.

### 2.13 Updates, draws, on-copy accumulators

Unchanged (D-042): `@before_mcs`/`@after_mcs` blocks with `Pre`, compound assignments, one
writer per target, cadence `Every(n)`. Additions:

- **Accepted-ΔH accumulation is an algorithm-side, opt-in statistic, not an `@on_copy`
  write** (review S4). `@on_copy H_acc += ΔH` cannot be built as stated: model-scope
  targets are rejected in on-copy blocks (`src/codegen.jl:297`), `commit!` receives no ΔH
  (`lib/CorePotts/src/sequential.jl:29-30`, `checkerboard.jl:127-128`), and a global
  Float32 atomic would be contended and non-deterministic (D-029 keeps only free
  determinism). Instead: `PottsProblem(sys, op, tspan; track = (:ΔH,))` accumulates the
  accepted ΔH of the sweep in `sol.stats.accepted_ΔH::Float64`. `track` is a **problem**
  keyword, not an algorithm one (review N2): `:chemo` names a model term, and Potts
  resolves the names at construction into one generated accumulation function and one
  buffer in the state NamedTuple, the per-model types D-046 allows; CorePotts' algorithm
  types carry nothing. Sequential: `dH` is already in scope at the accept
  (`sequential.jl:24-30`) and is summed into a host `Float64`, exact. Checkerboard: the
  propose kernel stores the winning proposal's ΔH in a **lattice-indexed** `Float32` buffer
  (N entries, one write per site per colour cycle, so race-free; `+=` across sub-cycles;
  `nothing` when `track` is empty, D-058 item 4). It cannot be a per-colour-site buffer:
  `prio` and `source` are reused by every colour (`checkerboard.jl:143, 173`), so a
  reduction over such a buffer would see only the last colour (round-2 S3). The commit
  kernel zeroes the losers, and one reduction per MCS over the N entries adds into the
  host `Float64`; the reduction order is relaxed (D-029). Cost when on: one buffer write
  per proposal, one zeroing pass, one reduction launch per MCS; when off: nothing.
  Per-term contributions (`track = (:ΔH, :chemo)`) get one buffer per name. Merks'
  cumulative accepted ΔH (01 F9) reads `sol.stats.accepted_ΔH`.
- **Copy-scope writes to neighbour sites** (08b's field redistribution, review B3): the
  left side of an `@on_copy` equation may be `x[n]` for `n` drawn from a relation at
  `target`, with a filter:
  `@on_copy O2[n] ~ Pre(O2[n]) + share for n in Moore(1)(target) if owner[n] == 0`. This is
  new syntax (today `_write` takes one index, `src/codegen.jl:286-297`), new codegen (a
  loop over literal offsets with the filter, plain stores) and a new footprint: the
  compiler never sets `Footprint.write` today (`src/compile.jl:420` passes only `read`,
  `source_read`, `source_write`); the relation's radius becomes `write = r_w`, and the
  checkerboard stride `s = r + w + 1` (`lib/CorePotts/src/checkerboard.jl:169-170`,
  `model.jl:101-106`) then separates same-colour targets by at least `r + 2`, so the write
  sets are disjoint and **plain stores are exact**, no atomics. Cost on the checkerboard:
  the colour count goes from `(r+1)^N` to `(r+2)^N`: in 2D with `r = 1`, 4 → 9 colours
  (8 → 18 launches per MCS, two kernels per colour); in 3D, 8 → 27. Fewer sites per colour
  also changes the checkerboard chain's mixing, which the D-065 Q7 statistical validation
  covers. Sequential pays nothing beyond the loop. The build plan (§8.1 Q7) lands the
  sequential form first with 08 and the checkerboard form behind an A/B and a conservation
  test.
- **`Pre` on contact structure:** `Pre(neighbors(c))` and `Pre(contact(c, n))` keep the
  previous MCS's contact table when read, so T1 events are
  `@after_mcs n_T1 ~ count(true for c in cells for n in neighbors(c) if n ∉ Pre(neighbors(c)))`
  (04 F5). Cost: one extra table when used.
- `rand(dist)` with Distributions' `quantile` (R3); `hazard(rate)` sugar for a per-MCS
  Bernoulli.

### 2.14 Observables versus docs analysis (R16)

`@observed` is for quantities that are folds over the domains of §2.6 on one state. Graph
analysis (components seeded by predicates, `find_peaks`, spectra, Fürth fits, Ψ̄) is docs
Julia on `sol` (D-051 item 6), with `contact_graph(u; relation)` exposed as a public helper
returning a Graphs.jl graph over alive cells. The D-069 `find_peaks` port lives in
`lib/PottsModels/src/analysis/` as library code used by the tutorial (10 F7).

---

## 3. Problem, solve and analysis layer

### 3.1 Types

```julia
abstract type AbstractPottsAlgorithm <: SciMLBase.AbstractDEAlgorithm end
struct SequentialCPM{A, P}   <: AbstractPottsAlgorithm  # acceptance, proposal (as today, algorithms.jl:52-70)
struct CheckerboardCPM{A, P} <: AbstractPottsAlgorithm  # + count::Bool (a plain flag, no model content: D-046)
struct PottsProblem{...}     <: SciMLBase.AbstractSciMLProblem                # unchanged supertype; built with
                                                                              # field_solver, ode_solver, solvers, track (§3.4)
struct PottsIntegrator{...} <: SciMLBase.DEIntegrator{Alg, false, S, Int}     # unchanged (problem.jl:100)
struct PottsSolution{...}   <: SciMLBase.AbstractTimeseriesSolution{S, 1, Vector{S}}
SciMLBase.isdiscrete(::AbstractPottsAlgorithm) = true
```

`CPMProblem` (`lib/CorePotts/src/problem.jl:22`) is renamed `PottsProblem` in CorePotts (the
symbolic constructor `PottsProblem(sys, op, tspan)` dispatches on the system type, as
`ODEProblem(sys, …)` does over `ODEProblem(f, …)`). One name, one type, as in every SciML
solver package. **The supertype stays `AbstractSciMLProblem`** (review B2): subtyping
`AbstractDiscreteProblem` would put the problem under `AbstractDEProblem`
(`SciMLBase/AFdol/src/SciMLBase.jl:406, 386, 202`), and DiffEqBase, which MTKBase loads,
owns `solve`/`init` for that type (`DiffEqBase/wJ4a3/src/solve.jl:653, 150`); CorePotts
defines no `solve` of its own and relies on `CommonSolve.solve!(init(…))`
(`lib/CorePotts/src/problem.jl:141, 263, 295`), so the retype would route every call
through `solve_up`/`get_concrete_problem`/`promote_u0` on a `CPMState`. The in-place flag
of `DEIntegrator` stays `false` as today, since the integrator owns its state rather than
writing into a user-supplied `u`. What Potts wants from the discrete hierarchy it gets
from the algorithm trait (`isdiscrete`, `AFdol/src/alg_traits.jl:114-124`) and from its own
`remake`/ensemble methods. If a later spike shows explicit `solve`/`init`/`remake`/
`EnsembleProblem` methods on a `PottsProblem <: AbstractDiscreteProblem` are cleaner, that
is a separate decision with its own tests; it is not proposed here.

### 3.2 Initialization: one mechanism

The initialization *surface* is MTK's (`initial_conditions`, `initialization_eqs`,
`guesses`, MTKBase 1.77 `system.jl:198-212`): variable defaults (numbers or expressions),
`@initialization_equations`, and the operating point. The *engine* is not MTK's
`InitializationProblem` (review S9): it is the Potts `at_init` host phase
(`src/problem.jl:340-344`, `_host_init!` runs `phases.at_init` on the CPU), extended to
run initialization equations in dependency order. MTK's engine assumes a fixed unknown
vector and a nonlinear solve; Potts' unknowns are ragged per-entity columns and its
equations are explicit assignments, plus at most one steady-field solve per field.

1. **Order.** Operating-point values override defaults (as `u0` overrides MTK defaults).
   Numeric defaults fill the rest. Expression defaults and `@initialization_equations` run
   in a host initialization phase (`phases.at_init`, `src/problem.jl:340-344`, extended),
   in D-042 dependency order, after the lattice state (`ownership`, `kind`, `cluster`,
   links) is set, so `volume`, `position`, `centroid`, `rand()` and neighbour gathers are
   available.
2. **Forms.** `x ~ expr` (explicit, all scopes; e.g. `cue ~ position[2] - 1`,
   `A ~ volume`), `0 ~ D_V * Δ(V) - …` (a steady field: NonlinearSolve via the extension,
   LinearSolve when linear, SteadyStateDiffEq as the alternative), and symbolic
   operating-point entries (`A => volume`, `V_target => volume` for a saved state).
3. **`remake(prob; u0 = saved_state)`** accepts a `CPMState` (any `sol[i]`) as a complete
   `u0`; initialization equations then run only for variables *not* in it, so `A` keeps its
   value unless the map also says `A => volume` (04's coarsen-then-reset, 09's annealed
   copies, 12's relaxed start). `remake(prob; u0 = op)` with a map rebuilds from the map
   (`src/problem.jl:438-447`). Both re-run `at_init`. **`remake(prob; p = …)` also re-runs
   `at_init`** for every variable not fixed by `u0`, so a default that draws (`rand()`)
   is re-drawn under a parameter change; the draws come from the addressed counter RNG
   (`seed`, `replica`, `repeat`, `src/problem.jl:341`), so the same seed gives the same
   draws, and a different `p` alone does not change them unless the default reads `p`.
4. **Layouts** return operating points (D-057), now with cell columns, links and `cluster`
   (§3.3). `layout(l, sys; report = true)` returns `(op, report)` (10 F5).

Replaces: `@initialize` (10), `initial(volume)` (05), the bare `A => volume` special case
(04) and `V_target(cell) = volume` as a one-off (07). **Upstream:** none for the section
name: `@mtkmodel` is deprecated (`ModelingToolkit/brqnn/NEWS.md:328`) and `initialization_eqs`
is a `System` keyword (`system.jl:212`), which Potts' section maps to directly. What could
go upstream is an initialization *engine* for ragged per-entity unknowns (§7.1).

### 3.3 Layouts (R2)

- `paint!(op::LayoutState, l, lat)`: `op` holds `σ`, `kinds` and any cell column or link
  list a layer adds (`cluster`, ranks, `chain => pairs`). `layout` returns
  `[ownership => σ, kind => kinds, cluster => …, :chain => pairs, :rank => …]`.
- Layers: `Tiling(size; spacing, region, kinds, partial = :skip | :clip, jitter)`,
  `Scattered(n, shape; …)` where `shape` may be a box or a composite (`Chain`,
  `Ellipse`), `Frame`, `Plane(kind; axis, at)`, `Spheres`, `Fibres`, `BrickWall(size;
  offset, widths)`, `Eden(n; rounds, region)`, `Splits(layer, k)` (reuses the lifecycle
  division routine, 01 F10), `Chains(s; area, spacing, orientation)`, `VoronoiBall`,
  `InsertUntil(kind; into, fraction, on_miss = :count | :retry | :skip, check)`.
- Combinators: `overlay`, `Group(layers…)` (emits `cluster`), `Relabel(layer, c -> kind)`,
  `collective = true` on any layer (one id, expected multi-piece, no split warning; 07 F11).

### 3.4 Algorithms and solver placement (breaking)

```julia
prob = PottsProblem(sys, op, (0, 500);
    field_solver = ExplicitEuler(substeps = 15, lower = 0.0),   # required when the model has a field; no default
    ode_solver   = ExplicitEuler(substeps = 1),                 # default as today (D-038)
    solvers = [V => Adaptive(KenCarp4(linsolve = KrylovJL_GMRES()); reltol = 1e-6),
               grn => Adaptive(Rodas5P())],                     # per variable / component, symbolic keys resolved in Potts
    track = (:ΔH,))                                             # opt-in accumulators (§2.13); () is free
solve(prob, CheckerboardCPM(; acceptance = nothing,            # nothing: the model's @sweep law; MetropolisHastings() is the D-052 opt-in
                              proposal   = nothing,            # nothing: the model's @relations proposal
                              count = false);                  # opt-in accepted-copy counting on the checkerboard (§3.7)
      backend = MetalBackend(), saveat = 0:10:500, callback = cb)
prob2 = remake(prob; field_solver = ExplicitEuler(substeps = 30, lower = 0.0))   # the override: a rebuilt problem
```

`field_solver`, `ode_solver` and `Adaptive(...)` leave `@sweep` (`SweepSpec`,
`src/vocabulary.jl:604-616`), there is no solver metadata in the model (review S2), and
**the algorithms carry no solver fields** (review N1). The reason is mechanical: the
solvers are compiled into the phase code when the problem is built (`src/codegen.jl:386-387,
427, 442, 466`), and the D-016 fingerprint is taken there (`src/problem.jl:87`). An
algorithm-level solver, even as a `nothing`-defaulting fallback in the `_law` style, would
have to regenerate phases at `init`: `prob.f` would no longer determine the code (the
checkpoint fingerprint would need a second input), each distinct algorithm would pay a
compile, and the `Adaptive` + `rand()` check (`src/compile.jl:405-408`) would move to
`init`. So the placement is MethodOfLines': `discretize(pde, MOLFiniteDifference(dxs, t;
approx_order))` fixes the numerics when the problem is built, and a different scheme is a
different problem. `remake(prob; field_solver = …)` is the override; it rebuilds the
problem through the one codegen point, as `remake` with a new `f` does elsewhere. The
model states physics and where each field lives (`grid`); the problem states how each
field and ODE is integrated, per variable where a paper's scheme matters (Merks' 15
substeps, Bauer's implicit `V`), keyed by the symbolic variable exactly as an operating
point is and resolved to generated code before CorePotts sees it (D-046). The algorithm
keeps only what the kernels take as a run-time value: the acceptance law, the proposal
law, and the `count` flag. `Adaptive(alg; abstol, reltol, dt)` is kept as the bundle for
host solves, as `DynamicSS(alg; abstol, reltol)` bundles them in SteadyStateDiffEq.
**No silent default:** `field_solver` is required when the model has a field. The error
message for a missing keyword names the keyword and, for a `PottsModels` model, the
tutorial's value. The `@sweep`-side defaults that exist today (`ExplicitEuler()` for
both, `src/vocabulary.jl:614-616`) are what would otherwise silently replace Merks'
`substeps = 2, lower = 0.0` in every bare call (`benchmark/gate.jl:29`,
`lib/PottsModels/test/mechanisms.jl:324-348`, the tutorials); P6.0c edits those calls and
the compiler catches any that are missed. `ode_solver` keeps its default because
`ExplicitEuler(substeps = 1)` over one MCS is what D-038 specifies and no shipped model
overrides it.

### 3.5 Ensembles and staged protocols

Unchanged SciMLBase: `EnsembleProblem(prob; prob_func, output_func, reduction)`,
`EnsembleThreads()`. `prob_func = (q, ctx) -> remake(q; u0 = layout(remake(l; seed =
ctx.sim_id), sys), p = […])` is the documented "u0 depends on the trajectory" idiom (09,
10). **One side effect of retyping the algorithms (round-2 review D2):** with
`AbstractPottsAlgorithm <: AbstractDEAlgorithm`, `solve(EnsembleProblem(prob), alg)`
without an ensemble algorithm matches `SciMLBase.__solve(::AbstractEnsembleProblem,
::Union{AbstractDEAlgorithm, Nothing})`, which picks `EnsembleThreads()`
(`SciMLBase/AFdol/src/ensemble/basic_ensemble_solve.jl:205-217`). Today no method matches
(`CPMAlgorithm <: AbstractSciMLAlgorithm`, `lib/CorePotts/src/algorithms.jl:42`) and the
tests always pass `EnsembleSerial()`/`EnsembleThreads()` explicitly
(`lib/CorePotts/test/sciml.jl:11-19`). The threaded default is the OrdinaryDiffEq one and
is acceptable on the CPU backend, where trajectories already run concurrently through one
phase object (`src/codegen.jl:470-472`); it is not acceptable as a *silent* default on a
GPU backend, where several host threads would issue kernels to one device. So CorePotts
defines `SciMLBase.__solve(prob::AbstractEnsembleProblem, alg::AbstractPottsAlgorithm;
backend = CPU(), kwargs...)` choosing `EnsembleThreads()` for `CPU()` and
`EnsembleSerial()` otherwise, with a docstring saying so; passing the ensemble algorithm
explicitly is unchanged. Staged protocols (04, 09, 12) are `remake` + `solve` + `DiscreteCallback(cond,
terminate!)`, with `integ[obs]` available in callbacks through SII; `@terminate` in a model
lowers to exactly that callback (04 F6).

### 3.6 Callbacks and saving

`DiscreteCallback`, `CallbackSet`, `PresetTimeCallback`, `SavingCallback((u, t, integ) ->
(integ[φ], integ[n_T1]), sv)` from DiffEqCallbacks work on `PottsIntegrator` (integer `t`);
the streaming per-MCS series of 04 are `SavingCallback`s, not saved states.
`@discrete_events (t == 100) => [blocked ~ 1.0]` is MTK's syntax lowered to a
`DiscreteCallback`.

### 3.7 Solutions, indexing, statistics

- `sol[x]` for any quantity or expression (SII, exists); `sol[curvature]` for a named term;
  `sol[x, i]` for one saved state (the SII form; `sol[i][x]` stays as a convenience).
- `sol.stats` **keeps `PottsStats` and its names** (`accepted`, `attempts`, `mcs`,
  `launches`, `lifecycle`; `lib/CorePotts/src/problem.jl:85-91`), review S5. The
  `DEStats` names `naccept`/`nreject` count accepted and rejected *steps* of an adaptive
  integrator (`SciMLBase/AFdol/src/solutions/ode_solutions.jl:45-46, 64`); reusing them for
  copies would be a false friend, and `PottsStats` is not a `DEStats` anyway. Two
  additions: `accepted_ΔH` (opt-in, §2.13) and `lifecycle` gains `conversions`. The
  checkerboard does not count acceptances by default (`accepted = -1`, `problem.jl:88`);
  `CheckerboardCPM(; count = true)` counts them through a lattice-indexed `UInt8` buffer
  (one write per site per colour cycle, race-free, `prio`/`source` being per-colour and
  reused, `checkerboard.jl:143, 173`) and one reduction per MCS, as `track` does (§2.13),
  `nothing` when off. `count` is a plain flag with no model content, so it may live on the
  CorePotts algorithm (D-046). `acceptance(sol)` is
  `accepted / attempts`, or `missing` when `accepted == -1` (12 F8 needs it on sequential
  or with `count = true`).
- `observe(prob, x, u)` stays as the host evaluator of an expression on any state (used by
  annealed-copy measurements, 09).

---

## 4. Conflict resolutions

| Topic | Forms in the sketches | Chosen | Reason |
|---|---|---|---|
| Proposal law placement | `@relations proposal = UnlikeNeighbor(rel)` (04); `@sweep Metropolis(law = UnlikeNeighbor())` (07); `Metropolis(proposal = BoundarySite(rel))` (12) | `@relations proposal = Law(rel; …)`; a bare relation is `UniformNeighbor` | Keeps D-049 F-1 and the algorithm override; a law needs its relation anyway |
| Phase order | `@schedule fields, copies` (01, 07); `order = (Sweep(), …)` in `@sweep` (06); comments (08, 14) | `@schedule` with canonical lowercase phase names plus rule names | One vocabulary; a static phase tuple with the sweep and lifecycle as entries (a `step!` restructuring, §2.12); the sweep section stays about the chain |
| Fractional / multiple attempts | `attempts = 1//4` (06); `attempts = 4` (08) | `attempts` on `@sweep`, number or rational | D-051 item 2 |
| Step vs MCS naming | `step` alias (06) | `t` counts steps; no alias | One clock; documented |
| Continuity | cell-scope `components` energy (05); `components(old; scope = Global())` drive (11); ring drive (01, 10) | both: `components` as a cell built-in with an exact after-value (energy), and the copy-scope values for drives | Bauer/Jafari are state energies; Merks/CC3D are per-copy penalties |
| Initial values from state | `A => volume` (04); `initial(volume)` (05); `V_target(cell) = volume` (07); `@initialize` (10); `@initialization_equations` (05, 07, steady) | expression defaults + `@initialization_equations` + symbolic op entries | It is MTK's initialization system |
| Steady initial field | `@initialization_equations 0 ~ …` (05, 07) | same | MTK name |
| Uptake keywords | `amount, per = cells(k), cap` (05); `max, by, per = :cell` (07); `max_amount, relative, per, by` (11) | `uptake(c; max, relative, by, per = Site()\|Cell(), over)` | CC3D's semantics (AUTHORING §12.9) plus the per-cell budget; operator-split per D-065 Q8 |
| Singleton cell | `the(kind)` (05, 06, 07) | `only(cells(kind))` | Julia's `only` |
| Tip / argmax | `cx == maximum(…)` (05, 07); `argmax` fold (05, 07, 08, 11) | `argmax(f, cells(k))` returning a `CellRef` | Julia's two-argument `argmax` |
| `@convert` shape | keyword forms (05, 07); named block (14) | named block with `from`, `to`, `sites`, `order`, `p`, `budget`, writes | The general sequential host pass; names allow `@extend` replacement |
| `@retire … sites => ref` (06) vs `@convert` | — | `@retire … sites => ref` stays as sugar over the same routine | Reads as the paper does |
| Destination allocation | `to` made on demand (14) | `Fresh(kind)` in `to`; `created` bound | Explicit; D-066 X2 |
| Kind classes | `ecm = [fluid, matrix]` inside `@kinds` (05); `@kind_classes` block (11) | `name = (k…)` inside `@kinds` | One declaring section |
| Kind tables by class | `J[class, class]` (05) | `KindTable(class => class => v, …)` value for `J[kind, kind]` | No second table type |
| Chemotaxis gate | raw drives (01, 10, 11, 14); `parties = …` (10); `mode = …` (14) | `when` default `new != 0`; `when = true` = every copy | One keyword; fixes `vocabulary.jl:636` |
| `neighbors(c)` relation | `relation = Moore(1)` (04, 10); none (06, 11) | `neighbors(c; relation = contact)` | 04 F4, 09 F7, 10 F7 |
| Medium as a neighbour | assumed (11) | `neighbors(c)` yields ref 0 for the medium | AUTHORING §12.3's `exposure` example needs it |
| Contact-pair counts | `count(… for _ in contacts)` (09, 04, 13) | same, over `contacts(rel)` | One comprehension semantics |
| Cluster reductions | `cluster_integral` (14) | `sum(x for s in sites(cluster))` | Uniform fold; `integral` stays sugar |
| Sibling centroid | `centroid(sibling(k), 1)` (14) | `centroid(c, k)` | Mirrors `displacement(c, k)` |
| Periodic differences | `minimum_image(d, axis)` (14); `separation(x, y)` (13) | both | Scalar and vector forms of one primitive |
| Rod order | `ν`, `prev`/`next` refs, `chain` links (13) | `@relationship chain … ordered = true` with `prev`/`next`/`rank`/`linked` | One store (13 F1) |
| 3-body syntax | `angles(rel)` (13) | same | Only proposal; fits the domain pattern |
| Zajac pair energy | `interfaces(k, k)` with `interface_centroid` (12) | same, plus `Σp`, `Σppᵀ` aggregates | Both segment readings expressible |
| Named terms/rules | `@drive chemo: …` (01); `@energy curvature = …` (13); `@convert protrusion` (14) | `name = domain => expr` for terms and drives; `@convert name`; `sol[name]` | One naming rule, `@extend` replacement |
| Replace a PDE by an update under `@extend` (14c) | redeclaration | redeclaring `F(site)` drops the base's `F(field)` equations and boundary | "Structural replacement is explicit: redeclare the target" (AUTHORING §6) |
| Helper functions under `@extend` (14c) | binding a body-local function | not supported; put helpers outside the model | Body functions are not system content |
| Layout metadata | `layout(…; report = true)` (10) | same | Only way to see uncreated ghosts (D-066 X2) |
| Layout cell columns/links | `layout(fig6, sys)` emitting `ν`, links (13); `cluster => […]` by hand (14) | `paint!(op::LayoutState, …)`; `Group(...)` | R2 protocol widening |
| Copy-time field spread | `spread((O2, …), n for n in Moore(1)(target) if owner[n] == 0)` (08b) | `@on_copy` with neighbour targets: `O2[n] ~ Pre(O2[n]) + … for n in Moore(1)(target) if owner[n] == 0` | New syntax, codegen and a declared write footprint (§2.13). Exact on sequential; exact on the checkerboard through the stride with 4 → 9 colours in 2D, plain stores. Sequential first; checkerboard rejected with a message until built (interim D-051 item 5 exception, §6.1; §8.1 Q7) |
| Division plane by draw (08) | `along = rand(((1,0),(0,1)))` | same | `along` takes any vector expression |
| Boolean networks | MTK clocked component (06, 11) | same; sub-clock by `Clock(mcs_duration/k)` | D-065 Q9 |
| Bool tables (11) | `tab[0:1, …]::Bool` | integer-indexed tables `tab[0:1, 0:1, 0:1, 0:1]` (R13) | Existing `Info(:kindtable)` generalised to any integer axes |
| UNSPECIFIED | `NaN` (04, 05, 06, 11, 12) | a parameter with no default | `src/problem.jl:202` already errors |
| Run statistics | `sol.stats.acceptance` (12); `cumulative_accepted_ΔH` (01); event log (08) | `acceptance(sol)` from `accepted`/`attempts` (`count = true` on the checkerboard); `track = (:ΔH,)` → `stats.accepted_ΔH`; `stats.lifecycle` + `SavingCallback` | `PottsStats` names kept (§3.7); the accumulator is opt-in and free when off (§2.13) |
| T1 counting (04) | streaming counter | `Pre(neighbors(c))` in an update + `SavingCallback` | Composes from existing pieces |
| Vector `ifelse` (13) | — | component-wise on `QuantityVector` | Small |
| Fold defaults (08) | `init`/`default` | Julia's `init`; `default` for means | Julia semantics |
| `a`/`b` (12) | rename semi-axes | reserve `a`, `b` globally | `macro.jl:44-46` omits them; the review's script shows `@parameters b` is then read as the edge endpoint inside `edges(rel)` terms (silent wrong physics, P6.0m) |
| Conditional declarations (12) | allow conditional `@variables` | keep unconditional; unused variables are pruned at `mtkcompile` | Constructor keywords are fixed at macro time (`macro.jl:137-138`) |
| Relaxation gate (01) | `(t >= t_relax) * (…)` in the PDE | `@discrete_events (t == t_relax) => [field_on ~ 1]` | Reads as intended; no 1,500 no-op substeps |
| Lie split within a field step (01) | `LieSplit(...)` | not adopted; O(Δt²), statistically invisible (D-029) | Cost without a measurable effect |
| Physical-units lattice (01) | `spacing = 2u"µm"` conversion | not adopted now; units are checked, not converted (D-039) | Out of scope; open question §7 |

---

## 5. Proof: three sketches in the unified API

### 5.1 Fortuna 14a/14b + Dal-Castel 14c (`@extend`, `@convert`, references, 3D)

```julia
using Potts

@potts_model FortunaCrawling begin
    @structural_parameters begin
        lattice = (120, 120, 31)
        retraction = true                       # C7 (D-067)
        stop_on_detachment = true
    end
    @kinds begin
        medium; substrate[frozen]; lid[frozen]; cytoplasm; lamellipodium; nucleus
        body = (cytoplasm, lamellipodium, nucleus)
    end
    @parameters begin
        T = 100.0; λ = 10.0; φ_F = 0.05; λ_F = 150.0
        D_F = 1.0e-4; k_decay = 0.9; k_source = 0.9
        J[kind, kind]    = [1 20 -20 20 40/3 100; 20 1 1 20 20/3 100; -20 1 1 20 40/3 100;
                            20 20 20 40 40 100; 40/3 20/3 40/3 40 40 100; 100 100 100 100 100 100]
        Jint[kind, kind] = KindTable(cytoplasm => lamellipodium => 10, cytoplasm => nucleus => 20,
                                     lamellipodium => nucleus => 40, _ => _ => 0)          # C1
    end
    @variables begin
        F(field)        = 0.0                    # one CC3D step per MCS: `field_solver = ExplicitEuler(substeps = 1)` on `PottsProblem`
        V_target(cell)  = 0.0
        births(model)   = 0.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = VonNeumann(1)
    @energy begin
        volume_term = cells(body) => λ * (volume - V_target)^2
        adhesion    = contacts    => ifelse(cluster[owner] == cluster[owner′], Jint[kind, kind′], J[kind, kind′])
    end
    extension  = (kind[new] == lamellipodium) & (old == 0)
    retracting = (kind[old] == lamellipodium) & (new == 0)
    @drive protrusion_work = copy => ifelse(retraction ? extension | retracting : extension,
                                            λ_F * (F[target] - F[source]), 0.0)
    @equations D(F) ~ D_F * Δ(F) - k_decay * F +
                      k_source * (kind == lamellipodium) * any(kind[n] == substrate for n in VonNeumann(1)(site))
    @convert protrusion clusters(cytoplasm) begin
        from   = sibling(cytoplasm)
        to     = sibling(lamellipodium) | Fresh(lamellipodium)
        sites  = (owner[site] == from) & any(kind[n] == substrate for n in VonNeumann(1)(site))
        order  = Shuffled()
        p      = 0.1 * (1 - V_target[to] / (φ_F * sum(V_target[m] for m in members(cluster))))
        V_target[to]   += ifelse(created, 1.5, 1.0)
        V_target[from] -= ifelse(created, 1.5, 1.0)
        births         += created
    end
    @schedule sweep, fields, protrusion, lifecycle                          # 14 §2.9.6
    if stop_on_detachment
        @terminate Every(50) when = (t > 10) &&
            any(!alive(sibling(c, lamellipodium)) || contact(c, sibling(c, lamellipodium)) == 0 for c in cells(cytoplasm))
    end
    @observed begin
        front_deaths ~ births - count(true for c in cells(lamellipodium))
        Πx(cell) ~ volume * minimum_image(centroid(1) - centroid(sibling(nucleus), 1), 1) / (volume + volume[sibling(nucleus)])
        Πy(cell) ~ volume * minimum_image(centroid(2) - centroid(sibling(nucleus), 2), 2) / (volume + volume[sibling(nucleus)])
    end
    @sweep Metropolis(; temperature = T)
end

@named cell = FortunaCrawling()
R = 15; L, Lz = 120, 31; V = 4.19R^3; c = (L ÷ 2 + 1, L ÷ 2 + 1, R + 1)
body = Group(Spheres([c]; radius = R, kinds = [:cytoplasm]),
             Tiling((6, 6, 6); region = map(a -> (a - 3):(a + 2), c), kinds = [:nucleus]))   # one cluster
op = layout(overlay(body, Plane(:substrate; axis = 3, at = 1), Plane(:lid; axis = 3, at = Lz)), cell)
prob = PottsProblem(cell, [op; V_target => [floor(0.85V) + 0.5, floor(0.15V) + 0.5, 0, 0]], (0, 100_001);
                    seed = 1, field_solver = ExplicitEuler(substeps = 1))      # required: the model has a field (§3.4)
sol  = solve(prob, SequentialCPM(); saveat = 0:50:100_001)   # `prob` built with field_solver = ExplicitEuler(substeps = 1)
ens  = EnsembleProblem(prob; trajectories = 5)

# ── 14c: binary F-actin, tanh bias, 100-MCS gate ─────────────────────────────────────────
touches_substrate(s) = any(kind[n] == substrate for n in VonNeumann(1)(s))     # helper outside the model

@potts_model DalCastelChemotaxis begin
    @extend T, λ, λ_F, φ_F, V_target = base = FortunaCrawling(; lattice = (59, 59, 21), λ_F = 175.0)
    @parameters begin ρ = 0.5; μ = 0.0; χ = 1.0; δ = 0.0 end
    @variables begin
        F(site) = 0.0                          # redeclared as a site variable: the base's PDE and boundary are dropped
        φ_frac(cell) = 0.0; φ_sum(cell) = 0.0; φ_EST(cell) = 0.0
        Q̄(cell) = 0.0; σQ(cell) = 1.0
    end
    base_site = touches_substrate(site) & (kind != nucleus)
    Q = minimum_image(position[1] - centroid(sibling(owner, cytoplasm), 1), 1)
    @after_mcs begin
        F      ~ (kind == lamellipodium) * touches_substrate(site)
        φ_frac ~ volume[sibling(lamellipodium)] / (V_target + volume[sibling(lamellipodium)] + volume[sibling(nucleus)])
        φ_sum  ~ Pre(φ_sum) + φ_frac - Pre(φ_frac, 100)                        # R12
        φ_EST  ~ ifelse(t < 100, φ_F, φ_sum / 100)
        Q̄      ~ sum(Q * base_site for s in sites(cluster)) / sum(base_site for s in sites(cluster))
        σQ     ~ sqrt(sum(Q^2 * base_site for s in sites(cluster)) / sum(base_site for s in sites(cluster)) - Q̄^2)
    end
    @convert protrusion clusters(cytoplasm) begin                              # replaces the base's rule by name
        from = sibling(cytoplasm); to = sibling(lamellipodium) | Fresh(lamellipodium)
        sites = (owner[site] == from) & touches_substrate(site)
        order = Shuffled()
        p     = ρ * (χ * tanh(μ * (Q - Q̄[from]) / σQ[from]) + 1)
        gate  = volume[to] / (V_target[from] + volume[to] + volume[sibling(nucleus)]) - δ <= φ_EST[from]
    end
    @schedule sweep, after_mcs, protrusion, lifecycle
    @terminate when = count(true for c in cells(lamellipodium)) == 0
end
```

Everything in 14a's sweep reads only `old`, `new`, `cluster` and site values, so the
checkerboard is exact there (14 F11); the conversion and the observables run at the
boundary.

### 5.2 Jiang 2005 (3D, fractional attempts, coarse fields, clocked network, retire-into)

```julia
using Potts, ModelingToolkit, OrdinaryDiffEq, LinearSolve
using ModelingToolkit: t_nounits as t

function G1SNetwork(; name, rb_e2f = :inhibitory)            # J3 blocking; MTK clocked component
    k = ShiftIndex(Clock(0.75))                                # one tick per Potts step (45 min)
    @variables GSK3b(t)=1 TGFb(t)=1 SCF(t)=1 SMAD(t)=0 P15(t)=0 P27(t)=0 P21(t)=0 CycD(t)=0 CycE(t)=0 Rb(t)=0 E2F(t)=0
    @parameters F θ stage u[1:8]
    gate(x, rule, τ, i) = ifelse(stage == τ, ifelse((F > θ) | (u[i] < F), rule, x(k - 1)), x(k - 1))
    on(x) = x(k - 1); off(x) = 1 - x(k - 1)
    System([GSK3b(k) ~ on(GSK3b), TGFb(k) ~ on(TGFb), SCF(k) ~ on(SCF),
            SMAD(k) ~ gate(SMAD, on(TGFb), 2, 1), P15(k) ~ gate(P15, on(SMAD), 3, 2),
            P27(k) ~ gate(P27, on(SMAD) * on(SCF), 3, 3), P21(k) ~ gate(P21, on(SCF), 3, 4),
            CycD(k) ~ gate(CycD, off(GSK3b) * off(P15) * off(P27), 4, 5), CycE(k) ~ gate(CycE, off(P27) * off(P21), 4, 6),
            Rb(k) ~ gate(Rb, off(CycD) * off(CycE), 5, 7),
            E2F(k) ~ gate(E2F, rb_e2f === :inhibitory ? off(Rb) : on(Rb), 6, 8)], t; name)
end

@potts_model Jiang2005Spheroid begin
    @structural_parameters begin
        lattice; Δx = cbrt(1200 / 64); erratum = false; chart_death = false
    end
    @kinds begin
        medium; proliferating; quiescent; necrotic
        viable = (proliferating, quiescent);  tumour = (proliferating, quiescent, necrotic)
    end
    @parameters begin
        T; γ_P; γ_N; V_init; tol_vol; α_F; θ_F; J_QQ                # UNSPECIFIED: no defaults
        J[kind, kind] = [0 16 14 12; 16 28 28 24; 14 28 J_QQ 22; 12 24 22 0]
        a₀[kind] = [0.0, 108.0, 50.0, 0.0];  b₀[kind] = [0.0, erratum ? 216.0 : 162.0, 80.0, 0.0]
        C₀[kind] = [0.0, 240.0, 110.0, 0.0]; d₀[kind] = [0.0, 1.0, 0.5, 0.0]; e₀[kind] = [0.0, 0.0, 1.0, 2.0]
        w_N = 10.0; D_O2 = 5.94e6; D_n = 1.52e5; D_w = 2.124e5; D_gf = 1e2; D_if = 1e2
        uO_O2 = 0.28; uO_n = 5.5; uT_O2 = 0.02; uT_n = 0.06; uW = 8.0; u0_O2 = 0.08; u0_n = 5.5
        p_shed = 0.2; R_shed = 300.0 / Δx; window = 32
    end
    @variables begin
        O2(field)  = 0.0, [grid = Coarse(4)]           # implicit host solver chosen when the problem is built (§3.4)
        glc(field) = 0.0, [grid = Coarse(4)]
        lac(field) = 0.0, [grid = Coarse(4)]
        gf(field)  = 0.0, [grid = Coarse(4)]
        inh(field) = 0.0, [grid = Coarse(4)]
        died(cell)     = -Inf                          # step of death (set by the transition)
        V_target(cell) = 2V_init
        γ(cell)        = γ_P
        stage(cell)    = 1.0
        core(model)::CellRef                           # the necrotic core, once it exists
        R_sph(model)   = 0.0
    end
    @components cells(viable) grn = G1SNetwork()
    @lattice Lattice(lattice; spacing = Δx, boundary = Closed(), neighborhood = Moore(1))

    @energy begin
        adhesion = contacts      => J[kind, kind′]
        volume_term = cells(tumour) => γ * (volume - V_target)^2
    end
    fO2 = (O2 - uT_O2) / (uO_O2 - uT_O2);  fn = (glc - uT_n) / (uO_n - uT_n)
    fresh = (kind == necrotic) * (t - died[owner] <= window)
    @equations begin
        D(O2)  ~ D_O2 * Δ(O2) - a₀[kind] * fO2
        D(glc) ~ D_n * Δ(glc) - b₀[kind] * fn
        D(lac) ~ D_w * Δ(lac) + C₀[kind] * (fO2 + fn) / 2 + w_N * fresh
        D(gf)  ~ D_gf * Δ(gf) - d₀[kind]
        D(inh) ~ D_if * Δ(inh) + e₀[kind] * ifelse(kind == necrotic, fresh, 1.0)
    end
    @boundary begin
        sites(kind == medium) => [O2 => Dirichlet(u0_O2), glc => Dirichlet(u0_n), lac => Dirichlet(0.0),
                                  gf => Dirichlet(1.0), inh => Dirichlet(0.0)]
    end
    cmean(u) = mean(u for s in sites(cell))
    hostile = (cmean(O2) < uT_O2) | (cmean(glc) < uT_n) | (cmean(lac) > uW)
    @equations begin
        grn.F ~ 1 / (1 + exp(-α_F * ((cmean(gf) - cmean(inh)) - θ_F)))
        grn.θ ~ θ_F;  grn.stage ~ stage;  grn.u ~ [rand() for _ in 1:8]
    end
    @after_mcs begin
        stage ~ ifelse((kind == proliferating) & (Pre(stage) < 16), Pre(stage) + 1, Pre(stage))
        R_sph ~ cbrt(3 / 4π * sum(volume for c in cells(tumour)))
    end
    checkpoint = (stage == 6) | (stage == 12) | (stage == 16)
    arrest = ((stage == 6) & (grn.E2F < 0.5)) | (checkpoint & (volume < V_init * (1 + stage / 16) * (1 - tol_vol)))
    dying  = chart_death ? (kind == proliferating) & hostile : (kind == quiescent) & hostile
    @transition cells(proliferating) => quiescent when = arrest | (hostile & !chart_death), V_target => volume, γ => 4γ
    @transition cells(viable) => necrotic when = dying & !alive(core), limit = 1,
        V_target => volume, γ => γ_N, died => t, core => id          # the first death is the core
    @retire cells(viable) when = dying & alive(core), sites => core, V_target[core] += volume
    ready = (stage >= 16) & (volume >= V_target)
    on_surface = any(n == 0 for n in neighbors(c))
    @retire cells(proliferating) when = ready & on_surface & (R_sph > R_shed) & (rand() < p_shed)
    @divide cells(proliferating) when = ready, along = RandomPlane(), stage => 1.0
    @observed begin
        n_viable(model) ~ count(true for c in cells(viable))
        g1(model) ~ count(true for c in cells(proliferating) if stage[c] <= 6) / n_viable
    end
    @schedule sweep, fields, components, after_mcs, lifecycle                 # Fig 3
    @sweep Metropolis(; temperature = T, attempts = 1 // 4, mcs_duration = 0.75)
end

@named sys = Jiang2005Spheroid(; lattice = (96, 96, 96))
c = sys.lattice.dims .÷ 2
op = layout(Tiling((3, 3, 3); region = map(i -> (i - 1):(i + 1), c), kinds = [:proliferating]), sys)
prob = PottsProblem(sys, [op; T => 10.0, γ_P => 2.0, γ_N => 20.0, V_init => 27.0, tol_vol => 0.1,
                          α_F => 5.0, θ_F => 0.5, J_QQ => 28.0], (0, 32 * 30);
                    field_solver = Adaptive(ImplicitEuler(linsolve = KrylovJL_CG())))   # all five coarse fields (§3.4)
sol = solve(EnsembleProblem(prob; trajectories = 10), SequentialCPM(), EnsembleSerial(); saveat = 0:32:960)
```

The core bootstrap race (06 F2) is closed by `core::CellRef` at model scope, `limit = 1`,
and the remove > transition priority.

### 5.3 Starruß myxobacteria (ordered relationship, 3-body term, references in a drive, hex)

```julia
using Potts

@potts_model StarrussMyxobacteria begin
    @structural_parameters begin lattice = (256, 256); s = 8; unit_θ = true end
    @kinds medium segment
    @parameters begin
        A = 12.0; D = sqrt(12.0); λ = 0.7; ζ = 35.0; ξ = 300.0; ω = 0.5; kT = 0.8; J_SS = 0.3
        J[kind, kind] = [0.0 1.0; 1.0 3.0]
    end
    @variables pinned(cell) = 0.0
    @lattice Lattice(lattice; geometry = Hexagonal(), boundary = Periodic(), neighborhood = NeighborOrder(2))   # 12 sites; Hex(2) would be 18 (topology audit 2026-10-01)
    @relations proposal = Hex(1)
    @relationship chain(cell, cell) capacity = 2, ordered = true

    inv_R = 2 * sin(angle) / norm(separation(a, b))
    @energy begin
        area      = cells(segment) => λ * (volume - A)^2
        adhesion  = contacts       => ifelse(linked(chain, owner, owner′), J_SS, J[kind, kind′])   # exact: links change only at MCS boundaries (review S7)
        length    = edges(chain)   => ζ * (distance - D)^2
        curvature = angles(chain)  => ξ * inv_R^2
    end
    θ(c) = unit_θ ? normalize(separation(prev(chain, c), next(chain, c))) : separation(prev(chain, c), next(chain, c))
    # head and tail inherit the neighbouring chord (Eq 9): prev(head) = 0, next(tail) = 0
    chord(c) = ifelse(prev(chain, c) == 0, θ(next(chain, c)), ifelse(next(chain, c) == 0, θ(prev(chain, c)), θ(c)))
    work(c) = ifelse(c == 0, 0.0, dot(direction, chord(c)))
    @drive propulsion = copy => -ω * (work(old) + work(new))
    @constraint no_extinction(segment)
    @constraint (pinned[old] == 0) && (pinned[new] == 0)
    @observed begin
        E_curve ~ sum(ξ * inv_R^2 for _ in angles(chain))          # or simply sol[curvature]
        rod_x(cell) ~ cluster_centroid(1);  rod_y(cell) ~ cluster_centroid(2)
    end
    @sweep Metropolis(; temperature = kT)
end

rod  = Chains(8; area = 12, spacing = sqrt(12), kinds = :segment, orientation = RandomDirection())   # emits cluster, chain, rank
@named myxo = StarrussMyxobacteria()
op   = layout(Scattered(100, rod; seed = 1), myxo)
prob = PottsProblem(myxo, op, (0, 50_000); seed = 1)
sol  = solve(prob, SequentialCPM(); saveat = 0:100:50_000)          # Y2: sequential reference
ens  = EnsembleProblem(remake(prob; u0 = layout(InsertUntil(rod; occupied = 0.30, seed = 1), myxo)); trajectories = 15)
```

Vector `ifelse` (§2.7) lets `chord` be a vector; the 2-hop reads (`next` of `next`) are
derived by the footprint analysis.

### 5.4 The remaining models, one paragraph each

- **01 Merks.** Unchanged in substance. `J` gets symbolic entries (`J_cc`, `J_cM`, `J_cB`)
  so the Fig 7 sweeps are scalar `remake`s; the absorbing ring is `@boundary c
  sites(kind == border) => Dirichlet(0)`; the 15 substeps and the positivity clamp are the
  problem's `field_solver = ExplicitEuler(substeps = 15, lower = 0.0)` (today's
  `substeps = 2, lower = 0.0` in `@sweep`, `lib/PottsModels/src/merks.jl:59`, moves
  verbatim to every `PottsProblem(MerksVasculogenesis(…), …)` call, `benchmark/gate.jl:29`
  and `lib/PottsModels/test/mechanisms.jl:324-348` included, and is required there;
  D-050 M-decisions set the count); the order is `@schedule fields, sweep`; the
  relaxation is a `@discrete_events (t == t_relax) => [field_on ~ 1]` gate; the E₀ rule
  stays a drive over `ring_arcs`, `ring_cells` and a gather; the cumulative accepted ΔH is
  `PottsProblem(…; track = (:ΔH,))` → `sol.stats.accepted_ΔH` (§2.13); the
  width-2 frame stays (§8.1 Q3). 2006/2008 are `@extend`s of `MerksCore` with named `chemo`
  and `connectivity` drives the extensions may replace.
- **04 Foam.** `@relations proposal = UnlikeNeighbor(NeighborOrder(4))`; `tie = Accept()`;
  `A(cell) = volume` as an expression default; stages by `remake(u0 = sol[end], u0 map…)`;
  `sides(cell) ~ count(true for n in neighbors(c; relation = Moore(1)))`; `φ ~ count((kind
  == bubble) & (kind′ == bubble) for _ in contacts)`; T1 by `Pre(neighbors(c))` and a
  `SavingCallback`; `μ₂ ~ var(sides for c in cells(bubble))`.
- **05 Bauer 2009.** Kind classes in `@kinds`; `continuity = cells(endothelial) => α *
  (components > 1)`; `V(field) = 0.0` with `solvers = [V => Adaptive(KenCarp4(linsolve =
  KrylovJL_GMRES()))]` on the problem; `@initialization_equations 0 ~ …`; `uptake(V; max = β, by = kind ∈ endothelial, per =
  Cell())`; `lead = id == argmax(c -> centroid(c, 1), cells(endothelial))`; `@create stalk
  when = …, at = Sphere((1, y_base), r_new)`; `@convert degradation cells(tip) begin from =
  only(cells(matrix)); to = only(cells(fluid)); sites = any(kind[n] == tip for n in
  Moore(1)(site)); budget = deg_budget end`; `activated ~ max(Pre(activated),
  sum(V * rim for s in sites(cell)) >= v_a * sum(rim for s in sites(cell)))` with `rim`
  a gather inside the body (no staleness).
- **07 Bauer 2007.** Same vocabulary as 05; `Chemotaxis(V; strength = -μ, when = chemotactic)`
  (unchanged); `@relations proposal = UnlikeNeighbor(NeighborOrder(2); source = kind ==
  endothelial)`; `V_target(cell) = volume` default; `tip ~ id == argmax(...)`; `@transition
  cells(endothelial) => inert` with the P6.0d mask refresh; `@schedule before_mcs, sweep,
  fields, lifecycle`; `Fibres(…; collective = true)`.
- **08 FBCA.** `@components cells(oxidative, fermentative) fba = FluxBalance(…)` with the
  `HostOperator` trait; couplings by `@equations`; write-back in `@after fba`; `attempts =
  4`; `along = rand(((1.0, 0.0), (0.0, 1.0)))`; `@retire … when = sum(position[2] == 1 for
  s in sites(cell)) > 0`; Eq 6 as a site update with `mean(…; default = Pre(O2))`; the 08b
  extension replaces the base's coupling equations by redeclaration and adds `@on_copy
  O2[n] += … for n in Moore(1)(target) if owner[n] == 0`; `@schedule fba, before_mcs,
  lifecycle, sweep, after_mcs`.
- **09 Sorting.** `N_dl ~ count(pair(dark, light) for _ in contacts)`; annealed copies via
  `remake(q; u0 = u, p = [T => 0], tspan = (0, 32))` and `observe`; `@transition
  cells(unlabelled) => labelled when = (t == t_label) & (rand() < p_label)` or, cleaner, a
  `@discrete_events` at `t_label`; `temperature = T * ifelse(t < t_label, 1, k_pert)` (`t`
  in copy scope, R1); `Relabel`, `BrickWall(; widths)`.
- **10 Akeeb.** `J[kind, kind] = [0 2 10; 2 16 J_LF; 10 J_LF 5]`; `cue(site) = position[2]
  - 1` and `clock(cell) = ifelse((kind == follower) & (rand() <= PP), floor(75rand()),
  -1.0)` as expression defaults (re-drawn under `remake(p = [PP => …])`). **Two things
  this changes in the shipped model (review S8):** the `clock` default replaces the
  host-side seeding of `akeeb_state` and so changes the RNG stream against the frozen
  `papers.jl` band (D-068, D-071); it migrates inside P6.2a2, which already re-baselines
  that band for the MersenneTwister → StableRNG change, under one DECISIONS entry (§6.1).
  The connectivity rule is **not** changed: the shipped hard `@constraint
  connectivity(leader, follower)` (`akeeb.jl:53`, D-049 F-6) stays, with D-074's "exactly
  one component" semantics (P6.0m revalidates the frozen tests); the soft `!= 1` drive of
  10 F2 is the family's sibling variant, not Akeeb. `lonely(cell) ~ count(true for n in
  neighbors(c; relation = VonNeumann(1)) if n != 0) == 0`; `Tiling(…; partial = :clip)`,
  `InsertUntil(…; on_miss = :count)`, `layout(…; report = true)`.
- **11 Jafari Nivlouei.** Classes in `@kinds`; `continuity = cells(tumour, vessel) => α *
  (components > 1)` (the exact two-sided energy, N5); `n(field) = n₀` and `V(field) = 0.0`
  with `solvers = [n => Adaptive(KenCarp4(…))]` and `field_solver = ExplicitEuler()` for
  `V` on the problem; `@boundary n sites(kind ∈
  vessel) => Dirichlet(n_vessel)`; tables `grow_tab[0:1, 0:1, 0:1, 0:1]`; the network as a
  clocked component with `Clock(1 / depth)`; `ecm ~ sum(contact(c, o) for o in
  neighbors(c) if o == 0) / surface`; transitions in stated priority; `@discrete_events (t
  == therapy_day * 1440) => [blocked ~ 1.0]`. 11b: `touch` with `directed = true`, `links(c,
  touch)` folds, edge-scope `@after_mcs`.
- **12 Zajac.** `aniso = interfaces(cell, cell) => …` with `eccentricity`, `orientation`,
  `polar_moment` (R7 names fixed here: `eccentricity = √(1 − λ_min/λ_max)`, `orientation` a
  unit long-axis vector, `polar_moment = tr(inertia)`); the pair-tracker cost and claim
  design of §2.5 apply, sequential-exact first (P6.7); `@relations proposal =
  BoundarySite(Moore(1))`; `a₀`, `b₀`; `T₄₆` from `acceptance(sol)` (sequential, or
  `count = true`); relaxed start via `remake(u0 = relax[end])`; no `NaN`s: parameters
  without defaults.
- **13 Starruß.** §5.3.

---

## 6. Roadmap and decision changes

### 6.1 Amendments to recorded decisions (explicit)

Every DECISIONS entry or roadmap wording the proposal touches, with the kind of change
(**amend** = substance changes and needs a new entry; **clarify** = wording only;
**unchanged** = listed because the review asked).

| Decision | Kind | Change | Reason |
|---|---|---|---|
| D-052 acceptance for non-symmetric laws | **clarify** | `@sweep` names the model's default law (`Metropolis`/`Barker`) and its physics; `MetropolisHastings()` remains algorithm-only (`acceptance = MetropolisHastings()`) and is rejected in `@sweep`. Today's `_law(alg, f)` (`lib/CorePotts/src/algorithms.jl:19`) is already this precedence | review S1: the first draft listed MH among `@sweep` laws, which contradicted D-052 |
| D-035 one 4-byte readback per checked MCS | **amend** | budget becomes: one readback for the lifecycle trigger, **plus one device↔host round trip per declared host pass per firing** (`@convert`, `HostOperator`, `uptake`/`secrete`, host field solvers, model-scope `contacts(rel)` folds); a model with none pays nothing; each pass is a named `@schedule` phase so the cost is visible | review S6; §2.9, §2.12 |
| D-049 F-6 Akeeb `rule = :local` "exactly CC3D" | **amended by D-074** (nothing further here) | the shipped hard `@constraint connectivity(leader, follower)` stays; D-074 fixes its semantics to "exactly one component"; the soft `!= 1` drive is a sibling, not Akeeb | review S8; the first draft's §5.4 wording implied the drive |
| D-068 / D-071 Akeeb seeding and the frozen `papers.jl` band | **amend** (re-baseline) | `clock(cell)`/`cue(site)` become expression defaults drawn by `at_init` from named streams, changing the RNG stream; done at P6.4a with R17, with its own re-baseline under the same D-07x entry, **separate** from P6.2a2's StableRNG re-baseline so a band shift is attributable; the clocks then vary with `replica` under a fixed layout | review S8; round-2 S4 |
| D-058 item 4 zero cost when off | **unchanged, applied** | every new buffer (`track`, `count`, per-colour ΔH, BFS scratch, pair store) is `nothing` when its feature is off | review S4, S5 |
| D-029 free determinism only | **unchanged** | no global atomic ships: the ΔH accumulator is a per-site buffer plus one relaxed reduction per MCS; neighbour scatters are plain stores | review S4, B3 |
| D-051 item 5 both algorithms | **amend (time-boxed)** | `@on_copy` neighbour-target writes and `interfaces(k,k)` energies are sequential-only until their checkerboard forms land (P6.12, P6.7); `CheckerboardCPM` rejects such a model with a message naming the exception; the entry names the row that closes it | review B3, S7; round-2 S5 |
| D-051 item 2 fractional MCS at zero cost | **clarify** | the checkerboard form is Bernoulli thinning, compiled out at `attempts == 1` | review S10; §2.12 |
| D-031 F-13 / `PottsStats` | **unchanged** | names `accepted`/`attempts`/`mcs`/`launches` stay; `accepted_ΔH` and `lifecycle.conversions` added; `count = true` opt-in on the checkerboard | review S5 |
| D-032 / AUTHORING §12.2 "`centroid` is not allowed in energies" | **amend** | allowed once R7 gives exact after-values | Zajac and Starruß read centroids in energies |
| R4 (review §3, README §2.2) "soft rule: a drive" | **amend** | `components` also a cell-scope built-in with an exact after-value (state energy) | Bauer 2009 Eq 1 and Jafari Eq 3 are energies (05 F3, 11 F8) |
| D-049 F-1 "`@sweep Metropolis(; proposal = …)`" | **clarify** | the proposal (law) lives in `@relations proposal`, as AUTHORING §3 already says; `@sweep` keeps physics only | one place (04 F2) |
| AUTHORING §6 `field_solver`/`ode_solver` in `@sweep`; ROADMAP P6.0c "solver metadata per equation block or component" | **amend** | both become `PottsProblem` construction keywords: `field_solver` (required when the model has a field), `ode_solver`, and the symbolic-keyed `solvers` map, resolved in Potts and compiled at construction; no model metadata; no algorithm fields; `Adaptive` kept as the tolerance bundle; `ExplicitEuler(; substeps, lower)` keeps `lower` | MOL-style discretisation at construction (§3.4); review S2, round-2 N1 |
| D-016 fingerprint | **amend** | the fingerprint hash adds the solver specification (`field_solver`, `ode_solver`, `solvers`, `track`) beside the generated-code strings, structural parameters, lattice and scalar type, so a checkpoint from a differently discretised problem is rejected (`lib/CorePotts/src/checkpoint.jl:39`) | round-2 N1: the solver is part of the generated code's meaning |
| D-038 "each MCS covers `mcs_duration` with the sweep's `ode_solver`" | **amend** | "with the problem's `ode_solver`"; default `ExplicitEuler()` unchanged | round-2 S5 |
| D-046 no model content in CorePotts algorithm types | **unchanged, applied** | `track` and `solvers` are problem-construction keywords resolved in Potts into generated functions and state buffers (the per-model types D-046 allows); `CheckerboardCPM(; count::Bool)` carries no model content; no algorithm type parameter names a model term | round-2 N2 |
| D-057 `paint!(σ, kinds, l, lat)` public extension API | **amend** | `paint!(op::LayoutState, l, lat)` so layers can emit cell columns and links (§3.3); every existing layer's method is rewritten in the same change | R2 widening; round-2 S5 |
| D-031 F-1/F-2 RNG key and streams | **amend** | new named streams `CorePotts.thinning` (fractional attempts) and `Potts.init.<var>` (`at_init` draws), and a sub-cycle index in `draw`'s `local_index` slot and in `_color_order!` for `attempts > 1`; `attempts == 1` reproduces today's streams bit for bit | round-2 S2 |
| `CPMProblem` name | **amend** (rename only) | `PottsProblem <: AbstractSciMLProblem`, supertype unchanged | review B2; §3.1 |
| ROADMAP P6.5b "ownership hooks fire `@on_copy` / `clear_on_ownership_change`" | **clarify** | only `clear_on_ownership_change`; `@on_copy` is copy scope and never fires from the lifecycle | review B3; §2.9 |
| D-053 item 9 / D-065 Q9 "no Potts helper" | **unchanged** | a sub-clock `Clock(dt/k)` is MTK, not a helper | 11 F3c |
| D-066 item 5 references "cleared at boundaries" | **unchanged** | `Fresh(kind)` and `created` added to the R8 routine | 14 F2 |
| D-074 `connectivity(k)` exactly one component | **unchanged, adopted** | §2.5 wording follows it; P6.0m implements | review S8 |

### 6.2 New or changed R-items

- **R0b (new, small) = ROADMAP P6.0m plus:** `Chemotaxis` `when` default; reserve `a`/`b`;
  `connectivity` per D-074; `integral` ordering (all four are P6.0m's confirmed defects);
  fold `init`/`default`; vector `ifelse`; `argmax`/`argmin`/`only`/`var` folds;
  parameters-without-defaults as the UNSPECIFIED convention. The `track`/`count`
  algorithm keywords (§2.13, §3.7) are R0b too, but land with their first consumer (01
  for `track`, 12 for `count`).
- **R2 (widened):** `paint!` on a `LayoutState` that carries cell columns and links;
  `Group`, `Relabel`, `collective`, `partial`, `report`, `Splits` reusing the lifecycle
  division routine.
- **R3 (widened):** `limit = n` on `@transition`; `@discrete_events` MTK syntax;
  `@terminate` as sugar.
- **R5 (widened):** `@schedule` with the `step!` restructuring of §2.12; `[grid = …]`
  metadata (solver choice is a `PottsProblem` keyword, §3.4); masked clamps; the coarse-grid
  semantics of §2.11.
- **R6 (clarified):** `CellRef` sources listed in §2.7; `centroid(c, k)`, `separation`,
  `minimum_image`; hop-depth footprints.
- **R8 (decided):** the `@convert` block form; `Fresh`, `created`, `budget` carry-over;
  `@retire … sites => ref` as sugar; the priority list.
- **R9 (decided):** `ordered = true`, `directed = true`, `angles(rel)`, `links(c, rel)`,
  edge-scope updates.
- **R11 (decided):** `neighbors(c; relation)` with the medium as ref 0; `Pre(neighbors(c))`;
  `interfaces(k, k)` with `Σp`, `Σppᵀ`, sequential-exact first with the claim and pair-store
  design of §2.5 as P6.7 acceptance items; contact-pair folds in `@observed`; the explicit
  energy ban of §2.6.
- **R13 (decided):** integer-indexed tables generalise kind tables; clocked components with
  sub-clocks.
- **R14/R15 (decided):** OrdinaryDiffEq algorithms accepted directly inside `Adaptive`;
  the `solvers` map on `PottsProblem` construction (§3.4); `uptake`/`secrete` keyword set; `HostOperator` trait;
  `@after name` write-back blocks; each host pass costed per §2.9.
- **R17 (new):** the initialization system (§3.2), implemented as the Potts `at_init`
  host phase (`src/problem.jl:340-344`), not MTK's `InitializationProblem`: expression
  defaults, `@initialization_equations`, symbolic op entries, `remake(u0 = state)`, and
  re-draw of `rand()` defaults on every `remake` from named `Potts.init.<var>` streams.
  Lands with its first consumer, **P6.4a** (04's `A => volume`); Akeeb's `clock`/`cue`
  defaults follow there with their own re-baseline; 05/07 reuse it.
- **R18 (new):** named terms, drives and rules with `@extend` replacement and `sol[name]`.

### 6.3 What can be removed or simplified

- `SweepSpec.field_solver/ode_solver` (`src/vocabulary.jl:604-615`); `Adaptive` stays, but
  only as the tolerance bundle inside the problem's `field_solver`/`solvers`.
- `integral` as a separate lowering path (it becomes the `sites(c)` fold).
- The four separate spellings of "initial value from state" in the sketches.
- `@exchange`, `@initialize`, `@kind_classes`, `the`, `initial`, `cluster_integral`, `Fill`,
  `OneCell`, `T1Counter`, `spread`, `Relabel`-by-hand host code: none is needed.
- Per-model `*_state` functions in PottsModels once layouts emit columns.

### 6.4 Build plan: amendments to ROADMAP Phase 6 (model-first)

The first draft listed a feature-first order; the review (B4) is right that Phase 6 is
model-first (ROADMAP:79-104: "every new primitive is used by a sibling, and a new
published model adds its sibling and gate case"), and that several of its rows already
exist (P6.0c, P6.0g, P6.0m). This section therefore proposes **no new order**: it maps
every §2–§3 primitive onto the existing row that first consumes it, and states the wording
change each row needs. Rows not named are unchanged. Decision numbers for the batch are
"D-07x (TBD, ≥ D-075)": D-070–D-074 exist (DECISIONS:1152-1260).

**Step 0 — composition fixes and infrastructure**

| Row | Amendment | Consumer that proves it |
|---|---|---|
| **P6.0m** (confirmed defects) | as written: `Chemotaxis` `when` default (`src/vocabulary.jl:636`), `connectivity` per D-074 with the frozen Akeeb tests revalidated, reserve `a`/`b` (`src/macro.jl:44-46`), `integral` ordering. Add: the rename `CPMProblem → PottsProblem` (supertype unchanged, §3.1), because every later row writes the name; and `SciMLBase.isdiscrete(::AbstractPottsAlgorithm) = true` | GG/Akeeb/Merks all rebuild; the review's four scripts become tests |
| **P6.0c** (solver placement) | reword from "solver metadata per equation block or component" to "`field_solver` (required when the model has a field), `ode_solver` and a symbolic-keyed `solvers` map as **`PottsProblem` construction keywords**, compiled at the existing codegen point and hashed into the D-016 fingerprint; removed from `@sweep`; no algorithm fields; `remake(prob; field_solver = …)` is the override; `Adaptive(alg; abstol, reltol)` kept as the bundle; `ExplicitEuler(; substeps, lower)` keeps `lower`" (§3.4). Accept stays: a stiff component (`Adaptive(Rodas5P())`) beside an explicit field in one model, conformance against each solver alone. Add: every `PottsProblem(MerksVasculogenesis(…), …)` call passes `field_solver = ExplicitEuler(substeps = 2, lower = 0.0)` explicitly (`benchmark/gate.jl:29`, `lib/PottsModels/test/mechanisms.jl:324-348`, the tutorials), the `mechanisms.jl` Merks tests and the `merks_100` gate case are unchanged in result, and a bare call is a construction error; a checkpoint taken before the change fails the fingerprint check by design | Merks (P6.3), Bauer (P6.8/P6.9) |
| **P6.0g** (kind classes) | as written, plus the symbolic kind-table entries of §2.3 (both `_derived_parameters` and `_param_value`, `src/problem.jl:247-255`, change; no MTK `bindings` on array entries) | Bauer-style class gates (its own accept); Merks Fig 7 scalar `remake`s |
| **P6.0k** (MTK discrete spike) | as written; §2.10's `ClockedSystem()` trait and the sub-clock `Clock(mcs_duration / k)` are its output | Jafari (P6.10) |
| **P6.0d**, **P6.0l**, **P6.0b2** | unchanged | — |

**Step 2 — Akeeb**

| Row | Amendment | Consumer |
|---|---|---|
| **P6.2a2** (`akeeb_state` on `InsertUntil`; re-baseline for StableRNG) | **unchanged**: StableRNG only, so its band shift has one cause. The `cue`/`clock` expression defaults are *not* here; they move with R17 at P6.4a (below) | Akeeb |

**Step 3 — Merks**

| Row | Amendment | Consumer |
|---|---|---|
| **P6.3a** | as written (R4 topology values, soft E₀, `Global()`); add `track = (:ΔH,)` → `stats.accepted_ΔH` (§2.13) for 01 F9, with `nothing` when off and the A/B unchanged | Merks |
| **P6.3b** | as written (R5 `@boundary`, masked clamp every substep, explicit phase order); the phase order **is** `@schedule` and needs the `step!` restructuring of §2.12 (sweep and lifecycle as phase-tuple entries). Accept adds: the gate is unchanged on CPU and the Metal A/B is ≤ 1.01 for the five gate models (host phases are `nothing` there); the D-035 amendment (§6.1) is written in the same change | Merks (`fields, sweep`), then Bauer 2007, Jiang, FBCA |
| **P6.3d** | as written; the 15 substeps and `J` symbolic entries are P6.0c/P6.0g consumers; `@discrete_events (t == t_relax)` (R3 syntax, MTK's) lands here as its first consumer | Merks 2006/2008 |

**Step 4 — Foam**

| Row | Amendment | Consumer |
|---|---|---|
| **P6.4a** | as written (copy-scope `direction`, `time`, `mcs`; `Metropolis(tie)`); add: **R17** initialization (`A(cell) = volume`, `remake(u0 = sol[end])` keeping unlisted values, `at_init` re-run on `remake(p = …)`), and the small folds (`argmax`/`only`/`var`, `init`/`default`, `Pre(neighbors(c))`), because 04's staging and T1 counting are their first consumers; the explicit energy ban of §2.6 ships with the first host-pass fold here (`contacts` in `@observed`). Also here: Akeeb's `cue(site)`/`clock(cell)` become expression defaults drawn from `Potts.init.<var>` streams, with **their own** `papers.jl` re-baseline under the D-07x entry that amends D-068/D-071 (separate from P6.2a2's), and the tutorial notes that clocks now vary with `replica` | Foam; Akeeb (R17 second consumer) |
| **P6.4b** | as written (R10 laws, all-site attempt counting, fractional attempts at zero cost, Hastings at algorithm level per D-052). Add the checkerboard thinning form of §2.12 and the "`@sweep MetropolisHastings` is an error" check | Foam, Jiang (P6.11) |
| **P6.4c** | as written (R3 `@retire`, `@transition`, `rand(dist)`, `hazard`, `@discrete_events`, `@terminate`); `@transition … limit = 1` from §2.9 | Foam; 06 bootstrap |

**Step 5 — Fortuna**

| Row | Amendment | Consumer |
|---|---|---|
| **P6.5a** | as written (R6 references, D-066 liveness, claim widening) plus `centroid(c, k)`, `separation`, `minimum_image` | Fortuna |
| **P6.5b** | reword: "ownership hooks apply `clear_on_ownership_change`; `@on_copy` never fires from the lifecycle" (§2.9); the `@convert` block form with `Fresh`, `created`, `budget`; each `@convert` is a named `@schedule` phase costed as one host round trip per firing (D-035 amendment) | Fortuna 14a/14b, then Bauer 2009's degradation pass |

**Steps 6–12** (expanded at the step-5 checkpoint, as ROADMAP says)

| Row | Amendment | Consumer |
|---|---|---|
| **P6.6** | as written; add `ordered = true`, `prev`/`next`/`rank`/`linked`, `angles(rel)` energies (cheap, links change at MCS boundaries) | Starruß |
| **P6.7** | as written; add the `interfaces(k, k)` cost design of §2.5 as acceptance items: sequential-exact with a host pair `Dict` first; the checkerboard form (exclusive neighbour claims, device pair store) behind an A/B and a statistical comparison, or recorded as a D-051 item 5 exception if the A/B fails; `count = true` for `T₄₆` | Zajac |
| **P6.8** | as written; `uptake` as a host pass is one round trip per MCS on Metal (D-035 amendment); `solvers = [V => …]` for the steady/implicit field | Bauer 2007 |
| **P6.9** | as written (R4 `Global()` on both algorithms, `@create`); add the device BFS design of §8.1 Q6 (a deferred kernel over the compacted list of local-test failures, windowed BFS with an `MVector` stack, AllocCheck proof on the CPU path per D-047, conservative rejection counter, `window` on `components`/`Global()`) and the **late-state benchmark**: a saved sprout-stage state as `u0` timed under both algorithms and Metal by `benchmark/ab.jl`, measuring the local-test failure fraction, the deferred kernel's occupancy cost and the overflow rate, because `gate.jl` times 3 warm MCS from t0 on five fixed models and only flags Metal (`benchmark/gate.jl:9-12, 91`); acceptance also records `exp(−α/T)` for 05 and 11 (the condition under which conservative rejection is exact) | Bauer 2009, Jafari |
| **P6.10** | as written; `directed = true`, `links(c, rel)`, edge-scope updates (11b); integer-indexed tables | Jafari |
| **P6.11** | as written (3D, fractional attempts, coarse grids, R14 implicit, `@retire … sites => ref`); `Coarse(k; clamp = All())` default with the T10 sensitivity sweep (§8.1 Q5) | Jiang |
| **P6.12** | as written ("copy-time field writes"); specify: the `@on_copy` neighbour-target form of §2.13, **sequential first**, with the 08b conservation test (`sum(O2)` invariant under redistribution) on sequential; the checkerboard form (write footprint, 4 → 9 colours) is a second item with the same conservation test on the checkerboard and on Metal and an A/B; until it lands `CheckerboardCPM` rejects the model (interim D-051 item 5 exception, §6.1) | FBCA |

**Removed from the first draft's plan:** the supertype change (B2); `naccept`/`nreject`
(S5); `[solver = …]` metadata (S2); R17 "before any consumer" (B4); the feature-first
numbering. Steps the review accepted (kind classes = P6.0g; R6 + R7 = P6.5a; R14/R15
last) are kept as those rows.

---

## 7. What the SciML maintainers would reject in the current design

1. **Solver configuration inside the model (`@sweep … field_solver = …, ode_solver = …`),
   and equally solver choice as variable metadata.** Problem/solver separation is the
   first SciML rule; OrdinaryDiffEq never reads a solver choice from the system, and
   `[solver = …]` on a variable is the same thing in a different place. → §3.4: all of it
   at problem construction, MethodOfLines-style, per variable through a symbolic-keyed
   map. (They would equally reject solver fields on the algorithm here, because that
   would mean generating code at `init`; a Potts problem is a discretised map, and the
   discretisation belongs to the problem, as `discretize(pde, MOLFiniteDifference(…))`
   has it.)
2. **A bare wrapper instead of the algorithm.** Users pass `Tsit5()` everywhere else. →
   accept any OrdinaryDiffEq algorithm; `Adaptive(alg; abstol, reltol)` is the tolerance
   bundle, the `DynamicSS(alg; abstol)` shape, and nothing else.
3. **`CPMProblem` next to `PottsProblem`.** Two names for one problem type. → one name,
   `PottsProblem`. The supertype stays `AbstractSciMLProblem`: the maintainers would
   *also* reject `<: AbstractDiscreteProblem` for a type that does not implement the
   `DiscreteFunction` contract, because DiffEqBase's `solve`/`init` would claim it
   (`DiffEqBase/wJ4a3/src/solve.jl:653, 150`). JumpProcesses did *not* make this choice:
   `AbstractJumpProblem <: AbstractDEProblem`, and DiffEqBase special-cases it
   (`solve.jl:164, 720`); Potts' route outside the hierarchy is the simpler one.
4. **Statistics that reuse `DEStats` names for a different quantity.** `naccept` means
   accepted steps (`AFdol/src/solutions/ode_solutions.jl:64`); copies are not steps. →
   keep `PottsStats` names, §3.7.
5. **`Pre(x, k)` as a second method of MTK's `Pre`.** MTK's `Pre` is the event-affect
   operator with one meaning; the lag is `Shift(t, -k)`. → keep the sugar, lower to `Shift`,
   accept `ShiftIndex` syntax.
6. **`Every(n)` as a Potts-only cadence type.** MTK models cadence as clocks. → lower
   `Every(n)` to a sub-clock; keep the syntax.
7. **`integral(x)` as a special reduction with its own staleness rules.** One fold semantics
   with D-042 ordering is what they would expect. → §2.6.
8. **Four ways to initialize from state**, none of them `initialization_eqs`. → §3.2 (the
   MTK surface, a Potts engine, said so).
9. **`observe(prob, x, u)` and `sol[i][x]` as primary indexing.** SII is the interface;
   conveniences are fine but must be documented as such. → `sol[x, i]` first.
10. **A `PottsModelInfo` as the SII container** (`src/observed.jl`) rather than the compiled
    system in `prob.f.sys`. → `symbolic_container(f) = f.sys` returning the
    `CompiledPottsSystem` itself, with the observed-function cache on the system.
11. **`NaN` sentinels for unspecified parameters.** MTK's answer is "no default, error at
    problem construction", which Potts already implements. → drop the sentinel.
12. **Boolean networks as anything but clocked `System`s.** Already decided (D-065 Q9).

Things they would *accept* as necessary deviations: the Potts-owned lowering (D-014
amended), per-entity ragged state, the acceptance law in the model, integer time, and a
problem type outside the DE hierarchy with its own CommonSolve methods.

Things they would still flag in *this* draft, stated so the maintainer sees them: a
per-MCS host pass is a synchronisation point that no other SciML solver has (JumpProcesses'
callbacks run on the integrator, not across a device boundary), so the D-035 amendment
must be documented as a cost class; and the `track`/`count` opt-ins are Potts-specific
keywords with no ecosystem analogue, which is acceptable only because they are off by
default.

### 7.1 Upstream proposals (with the local workaround)

| Gap | Upstream change | Local workaround until then |
|---|---|---|
| Initialization of ragged per-entity unknowns | an initialization engine that accepts explicit per-entity assignment equations (no nonlinear solve) beside `initialization_eqs`; MTKBase 1.77's engine assumes one unknown vector | Potts `at_init` host phase (`src/problem.jl:340-344`) |
| Bool unknowns and `&`/`\|`/`!` in `Shift` systems | typed discrete unknowns in the discrete-system lowering | 0/1 reals with `min`/`max`/`1 − x` |
| No per-variable solver selection on a split problem | a `solvers = [x => alg]` keyword convention for algorithms that integrate a partitioned system (`mtkcompile` partitioning gives the split) | the `solvers` map on the Potts algorithms (§3.4) |
| Array-parameter entries as bindings | `bindings` (`ModelingToolkitBase/IwLYy/src/systems/system.jl:193`) keyed by array *elements* | Potts re-derives the table on `remake`/`setp` |
| Deprecated `@mtkmodel` | nothing to propose: MTK 11 moved it to SciCompDSL.jl (`ModelingToolkit/brqnn/NEWS.md:328`) | `@potts_model` is Potts' own DSL over `System` keywords |
| Per-entity imperative affects | `ImperativeAffect` with an iteration domain | the Potts host pass |
| SII for ragged per-entity variables | `getu` returning `Vector{Vector}` with a documented shape trait | Potts observed functions |

---

## 8. Open questions for the maintainer

1. **Acceptance law placement.** This proposal keeps `Metropolis(; temperature)` in the
   model (§0.1) with algorithm override, and `MetropolisHastings()` algorithm-only as
   D-052 decided. The alternative the coordinator raised, an OrdinaryDiffEq-style
   `solve(prob, Metropolis(; sweep = Checkerboard()))`, moves the paper's chain out of the
   model. Confirm the model-side placement and the D-052 clarification (§6.1).
2. **`PottsProblem` name and supertype.** Confirm the rename of `CPMProblem` (breaking for
   CorePotts users) with the supertype **unchanged** (`AbstractSciMLProblem`), or ask for
   a spike of `<: AbstractDiscreteProblem` with explicit `solve`/`init`/`remake`/ensemble
   methods.
3. **Off-lattice `Wall(kind)` boundary** (01 F2): build it (attempts counted over mobile
   sites, an off-lattice neighbour that reads as a kind), or keep the width-2 frame
   emulation and record the ≈ 4 % attempt-count deviation.
4. **Physical-units lattice** (01 F5): convert unit-carrying parameters to lattice units
   from `spacing` and `mcs_duration` (a DynamicQuantities extension), or keep units
   check-only (D-039).
5. **Coarse-grid clamp rule default** (§2.11): `Majority()` is a choice the paper does not
   make; `Any()` is more conservative near the tumour. Pick, or ask Jiang.
6. **`components` energy on the checkerboard** (05 F12): D-051 item 5 allows the BFS. The
   device form needs bounded private scratch (§8.1 Q6); accept the windowed BFS with
   conservative rejection beyond the window, and the late-state benchmark as its gate?
7. **`@on_copy` scatter to neighbours (08b)** needs a declared write footprint and 4 → 9
   colours in 2D; accept sequential-first with an interim D-051 item 5 exception for the
   checkerboard until the footprint form is built and measured?
8. **Name reservation of `a`, `b`** breaks any existing model with a parameter `a` or `b`
   (none in `lib/PottsModels`). Confirm.
9. **Renames.** `CPMProblem → PottsProblem` (supertype unchanged), `@sweep` solver keyword
   removal with `field_solver`/`solvers` as `PottsProblem` keywords, P6.0c and P6.5b rewording: all
   breaking or wording changes. Confirm the batch before P6.0m/P6.0c.

### 8.1 Recommended answers

> **Recommendations pending the maintainer's ratification. These are not decisions.**
> Each answer is written as the SciML maintainers (API, ecosystem homogeneity) and James
> Glazier (CPM physics, what the published models need, CompuCell3D practice) would have
> written it together. "SciML:" and "Glazier:" mark the two views; "Resolution:" says how
> a disagreement was settled; "Consequence:" names the roadmap or decision change.

**Q1 — Acceptance law placement: the model's default law and physics in `@sweep`; the Hastings correction algorithm-only, exactly as D-052 says. Confirmed, with a clarification row in §6.1.**
- SciML: the rule is that the *problem* holds what defines the solution and the *algorithm*
  holds how it is computed. A Metropolis chain and a Barker chain at the same temperature
  are different chains with different kinetics, so the law the paper wrote is part of what
  is being solved, exactly as Catalyst keeps mass-action versus explicit rate laws in the
  `ReactionSystem` and not in the SSA aggregator. The Hastings *correction* is different in
  kind: it does not define a chain, it repairs one for a non-symmetric proposal law, and
  every reproduction runs without it (D-052: "all reproduction tutorials use it [plain
  Metropolis]"). That is a solver-side switch, and D-052 already placed it there as an
  acceptance type with a zero-cost-when-unused requirement. So: `@sweep Metropolis(…)` or
  `@sweep Barker(…)`, `SequentialCPM(; acceptance = MetropolisHastings())` to opt in, and
  `@sweep MetropolisHastings(…)` is an error. The precedence is today's
  `_law(alg, f) = something(alg.acceptance, f.acceptance, Metropolis())`
  (`lib/CorePotts/src/algorithms.jl:19`). What must *not* be in the model is the execution
  strategy (sequential/checkerboard) or the numerical sub-solvers, which §3.4 moves out.
- Glazier: every paper writes the acceptance function next to the Hamiltonian (09c Eq 3,
  04b Eq 3, 12b Eq 4, 13 Eq 7), and CompuCell3D configures `Temperature`, the acceptance
  function and its offset in the `<Potts>` element of the model XML, not on the solver.
  Temperature is a physical parameter of the tissue, often per kind. Moving it out of the
  model would make a published model incomplete without a solver call. The Hastings
  correction is not in any of the twelve papers, so it belongs to the experimenter, not
  the model.
- Resolution: no disagreement, once "law" and "correction" are distinguished. The first
  draft listed `MetropolisHastings` among the `@sweep` laws; that contradicted D-052 and is
  withdrawn (review S1).
- Consequence: §0.1, §2.1 and §2.12 revised; D-049 F-1 unchanged; D-052 gets a **clarify**
  row in §6.1 (no change of substance); the `Metropolis(; sweep = …)` algorithm-type
  alternative is dropped.

**Q2 — `CPMProblem` is renamed `PottsProblem`; the supertype stays `AbstractSciMLProblem`. Confirmed as a rename only.**
- SciML: the first draft's `<: AbstractDiscreteProblem` is withdrawn (review B2), and the
  reason is one a SciML maintainer would give first: `AbstractDiscreteProblem` is a
  *DE* problem (`AbstractDiscreteProblem <: AbstractODEProblem <: AbstractDEProblem`,
  `SciMLBase/AFdol/src/SciMLBase.jl:406, 386, 202`), and DiffEqBase, which every MTK user
  has loaded (MTKBase depends on it), defines `solve(prob::AbstractDEProblem, args...;
  …)` at `DiffEqBase/wJ4a3/src/solve.jl:653` and `init` at `:150`. CorePotts defines no
  `solve` of its own (`CommonSolve.solve!(init(…))`, `lib/CorePotts/src/problem.jl:141, 263,
  295`), so the retype would route every `solve(prob, alg)` through `solve_up`,
  `get_concrete_problem` and `promote_u0` on a `CPMState`. Subtyping a contract one does
  not implement (`DiscreteFunction`, `u0::AbstractArray`, `dt`) is what the ecosystem
  rejects, not what it rewards. JumpProcesses is *not* the precedent: `AbstractJumpProblem
  <: AbstractDEProblem` and DiffEqBase special-cases it (`solve.jl:164, 720`); staying
  outside the hierarchy with CommonSolve methods, as the reviewer's `sciml2.jl` shows
  works today, is simpler than JumpProcesses' route.
  "`isdiscrete` for free" was wrong: it is an algorithm trait
  (`AFdol/src/alg_traits.jl:114-124`), so `SciMLBase.isdiscrete(::AbstractPottsAlgorithm) =
  true` is the correct, free statement. One name per problem type still holds:
  `PottsProblem(sys, op, tspan)` in Potts and `PottsProblem(f, u0, tspan, p)` in CorePotts
  are one type.
- Glazier: indifferent to the Julia type, but wants one thing: `tspan` in MCS with no
  interpolation, because MCS is the unit every paper reports (09 §8.5, 06 Fig 3). The
  rename keeps that; the supertype never gave it.
- Resolution: rename only. If the maintainer wants the DE hierarchy anyway, the price is
  explicit `solve`, `init`, `remake`, `EnsembleProblem` hooks and tests that DiffEqBase's
  generic path is never entered; that is a separate spike, not part of this proposal.
- Consequence: P6.0m carries the rename (§6.4); `lib/CorePotts/src/problem.jl:22-23`
  changes name, not supertype; `DEIntegrator{Alg, false, S, Int}` (`problem.jl:100`) is
  unchanged; D-031 F-10 (exact `sol(t)`) unchanged; §0.1, §3.1, §6.1, §7 item 3 revised.

**Q3 — `Wall(kind)`: do not build it. Keep the frame emulation and record the attempt-count deviation.**
- Glazier: TST's off-lattice border (01 ca.cpp:228-230) is a TST implementation detail;
  CompuCell3D has no such thing, its boundaries are periodic or no-flux and walls are
  frozen cells the user paints. The measurable effect of an off-lattice border is the
  J(c,B) = 100 penalty at the edge, which a frozen frame reproduces exactly. The 4 %
  (202²) or 1.6 % (502²) surplus of null attempts on frozen sites (01 F2) only rescales the
  MCS clock by that factor, which is invisible against the ±10 % run-to-run spread of the
  01 targets (01 §5 V-E2/E3, n = 10–100).
- SciML: a boundary type that makes the contact loop read a virtual kind off the lattice
  adds a branch to every contact term for every model, which violates the zero-cost rule
  (D-051 item 2, D-058 item 4) for a feature one reproduction would use. If attempt
  counting ever matters, R10's `attempts` keyword already lets a tutorial set
  `attempts = 198^2 // 202^2`, which costs nothing when unused.
- Resolution: agreed.
- Consequence: `Wall(kind)` is removed from AUTHORING §3's boundary list at the next
  AUTHORING revision; 01's tutorial deviations table records "frozen frame, 4 % null
  attempts, optionally corrected with `attempts`"; no roadmap row.

**Q4 — Physical-units lattice: keep units check-only (D-039). Ship a documented conversion helper in the tutorials, not a lattice mode.**
- SciML: MTK's units are a validation layer (`VariableUnit` + DynamicQuantities); automatic
  non-dimensionalisation is not something MTK does for ODEs either, and a lattice that
  silently rescales `major_length`, `position` and `L` into metres would break every
  built-in's documented unit (AUTHORING §8: built-ins are lattice units). The right
  ecosystem shape is an explicit helper the user calls: parameters in, lattice-unit
  parameters out, checked by the existing unit machinery.
- Glazier: every published CPM converts by hand and states the conversion (01a p.49:
  2 µm/px, 30 s/MCS; 11a p.13: 4 µm, 1 min; 14 §2.9.1), and the conversions are part of
  the deviations table a reproduction must show. Hiding them in a lattice mode would hide
  the one place readers check first.
- Resolution: agreed.
- Consequence: no roadmap row; `lib/PottsModels/reproductions/` gains a shared
  `lattice_units(; spacing, mcs_duration, params...)` helper (docs-level Julia per D-051
  item 6) used by 01, 05, 06, 07, 11. 01 F5 is closed as "by design".

**Q5 — Coarse-grid clamp default: `All()` (clamp a coarse node only when every fine site it covers is medium). Ship it, flag it, ask Jiang.**
- Glazier: the medium clamp in 06 (Appendix, p.9 [3892]) stands for a well-stirred bath; a
  coarse node that already contains consuming cells is *inside* the spheroid rim, and
  clamping it to the bath value deletes those cells' consumption and over-feeds the rim by
  up to one coarse cell (4 fine sites ≈ 10 µm). Under-supplying the rim is the smaller
  error, because O₂ is quasi-static at these diffusivities (06 §3.2) and a free node
  relaxes to the bath value within a step anyway. So the clamp should apply where the node
  is entirely medium: `All()`. `Majority()` was a compromise with no physical reading.
- SciML: a default must be a named, documented value with the alternatives one keyword
  away (`clamp = All() | Any() | Majority()`), and the choice must be visible in the
  tutorial's deviations table and sweepable in the reproduction's sensitivity test (06 §5
  T10 already sweeps a diffusivity; add the clamp rule).
- Resolution: agreed; this is one of the "ask the author" physics defaults.
- Consequence: §2.11 changed (`Majority()` → `All()`, two places, marked "per §8.1 Q5");
  06's author questions gain "which coarse nodes were clamped"; the P6.11 acceptance runs
  T10 with `Any()` and `All()` and reports the difference.

**Q6 — `components` (BFS) on the checkerboard: run it, never reject on a heuristic, but with a specified device design and a benchmark that can actually see it.**
- SciML: a solver that refuses a valid problem on a heuristic is worse than one that runs
  it and reports; the existing preflight (`lib/CorePotts/src/problem.jl:211-230`) rejects
  only what would be *wrong*. Exactness holds (review S3 agrees): the BFS reads only the
  constrained cell's own sites, and those change only through copies that claim that cell
  (`lib/CorePotts/src/checkerboard.jl:84-97`). What the first draft did not say is *how*
  the BFS runs on a device with no allocation and no shared scratch. **Design (round-2
  review S1 applied):** (1) The propose kernel runs the local ring test (`ring_arcs`,
  exact when it passes) and, on failure, does **not** BFS inline: it appends the
  proposal's colour-local index to a compacted per-colour list (one `UInt32` counter,
  relaxed atomic increment, D-029) and leaves `prio` undecided. (2) A **separate deferred
  kernel**, launched over the list (a fixed launch size of the colour's site count with
  early exit, so no host readback of the count), runs the windowed BFS for those
  proposals only, computes the exact after-value of `components` for `old` and `new`,
  finishes ΔH, takes the same acceptance draw (`draw(key, mcs, t, STREAM_PROPOSAL)` is
  deterministic) and writes `prio`; commit then runs unchanged. The BFS window has radius
  `W` around the target: the visited bitmap (2D `W = 8`: 289 bits = 10 `UInt32`; 3D
  `W = 4`: 729 bits = 23 `UInt32`) fits in registers; the stack is an `MVector{289,
  UInt16}` / `MVector{729, UInt16}` (about 0.6–1.5 KB per thread) that **spills to device
  memory on Apple GPUs**, which is why it lives in its own kernel: private-stack size is
  static per kernel, so putting it in `propose_body!` would cost occupancy on every
  thread of every `components` model, BFS or not. Because `propose_body!` is also run as a
  plain CPU loop (`lib/CorePotts/src/checkerboard.jl:204-209`), KA `@private` is not
  available; the `MVector` must be proven stack-allocated on the CPU by AllocCheck (D-047).
  Per-proposal scratch means two proposals that BFS the same cell never share a buffer.
  `W` is a keyword of the global rule, `components(; window = W)` or `Global(; window)`,
  **not** of `connectivity(k)`, which is CC3D's local rule (D-074) and has no window.
  (3) If the BFS reaches the window boundary on a site the cell owns, the device cannot
  decide: the proposal is **rejected conservatively** and a counter
  (`stats.connectivity_deferred`, `nothing` when the feature is off) records it;
  sequential runs the exact global BFS with a preallocated visited array and is the
  reference (D-065 Q7). **Honestly:** overflow depends on the *length* of the piece being
  traversed, not the width of the sprout. Proving that a mid-sprout retraction leaves one
  component means exhausting a whole piece, and on a long thin sprout both pieces exceed
  17 sites, so overflow concentrates on exactly the copies that matter. Conservative
  rejection equals the true answer only when the fragmentation penalty makes such copies
  effectively forbidden anyway, `exp(−α/T) ≈ 0`; P6.9's acceptance records `α/T` for 05
  and 11 and, where the condition fails, widens `W` or falls back to sequential for that
  model; that fallback is a D-051 item 5 exception under the time-boxed row of §6.1. (4) No branch, list, kernel or counter exists when `components`/`Global()` is
  absent from the model (`nothing` in the phase tuple, D-058 item 4). **Benchmark:** the review is right
  that "gate on the performance test" gated nothing: `benchmark/gate.jl` times 3 warm MCS
  from `t0` on five fixed models, only flags Metal, and none uses `components`
  (`benchmark/gate.jl:9-12, 24-36, 91`). P6.9 therefore adds a **late-state case**: a saved
  sprout-stage state (05 at the branching stage, thin 1–3 px sprouts) as `u0`, timed under
  both algorithms and on Metal by `benchmark/ab.jl`, with the BFS-failure fraction
  measured and printed rather than assumed, together with the deferred kernel's
  occupancy cost and the overflow rate.
- Glazier: CompuCell3D's `ConnectivityGlobal` runs its flood fill inside the serial copy
  loop and is used routinely. The first draft's "a few per cent" was a guess; on 1–3 px
  sprouts the local test fails on most retractions, so the fraction must be measured on
  the late state, which is exactly the benchmark above. The round-2 argument that a
  17-site window "covers every sprout width" was backwards (review S1): the BFS walks
  along the sprout, not across it, so it is the sprout's *length* that overflows. What
  makes the conservative rejection acceptable in 05 and 11 is physics, not geometry: the
  continuity penalty α is chosen by those authors to be prohibitive (a fragmented
  endothelial cell is not a modelled state), so the copies the device cannot decide are
  ones the exact rule would reject with probability `1 − exp(−α/T) ≈ 1`. That must be
  checked against each paper's α and T, not assumed. Sequential is the reference anyway
  (D-065 Q7).
- Resolution: agreed; the device design and the late-state benchmark are the price of
  "never reject".
- Consequence: §2.5 and §6.4 (P6.9) revised; D-051 item 5 stands as written; the deferred
  BFS kernel, its AllocCheck proof, the overflow counter, the `α/T` check for 05 and 11,
  and the late-state A/B are P6.9 acceptance items.

**Q7 — `@on_copy` scatter to neighbours (08b): a declared write footprint, exact on both algorithms once built; sequential first, checkerboard behind an interim D-051 item 5 exception until measured.**
- SciML: the checkerboard stride is `s = r + w + 1` (`lib/CorePotts/src/checkerboard.jl:169-170`,
  `model.jl:101-106`), so with `w = 1` same-colour targets are at least `r + 2` apart and
  the write sets of `Moore(1)(target)` are disjoint: the scatter is exact with **plain
  stores**, and atomics would only add cost (the first draft's "per-site atomic add" is
  withdrawn; Float32 atomic add on Metal is also unverified). But nothing of this "already
  exists" (review B3): the compiler never sets `Footprint.write` (`src/compile.jl:420`
  passes `read`, `source_read`, `source_write` only), `_write` takes a single index
  (`src/codegen.jl:286-297`), and the left-hand form `x[n] ~ … for n in R(target) if …` is
  new syntax. **Cost:** 2D colours `(r+1)² → (r+2)²`, 4 → 9 for `r = 1` (launches per MCS
  8 → 18, two kernels per colour); 3D 8 → 27; fewer sites per colour, and a different
  checkerboard chain, which the D-065 Q7 statistical validation must cover. Nothing in ΔH
  reads the nutrient fields in 08b, so acceptance is unaffected. The lifecycle does not
  fire `@on_copy` (§2.9), so a division cannot trigger the redistribution.
- Glazier: in the authors' MATLAB model the redistribution is done serially at the copy,
  and conservation is what matters (08b p.287). 08 runs at 100 × 155 with an LP per cell
  per MCS; the sweep's throughput is irrelevant there, so a sequential reproduction loses
  nothing, and the conservation test (`sum(O2)` over the lattice invariant under the
  redistribution, per MCS) is the acceptance that matters on either algorithm.
- Resolution: agreed. Build the sequential form with 08 (P6.12) and its conservation test;
  build the checkerboard form as a second P6.12 item with the write footprint, the same
  conservation test on the checkerboard and on Metal (Float32), and an A/B; until then
  `CheckerboardCPM` rejects a model with neighbour-target on-copy writes with a message
  that names the interim exception.
- Consequence: §2.13 (syntax, codegen, footprint, cost) and §4's row revised; §6.1 records
  the interim D-051 item 5 exception; §6.4 (P6.12) carries both items.

**Q8 — Reserve `a` and `b` globally. Confirmed.**
- SciML: Potts' own reserved list already holds `t`, `D`, `Pre` and `name`
  (`_reserved_names()`, `src/macro.jl:47`; this is Potts' list, not `@mtkmodel`'s), and
  a silent shadow of an edge endpoint by a parameter is a correctness bug that a macro
  must reject at expansion time, as `_declare!` does for every other built-in
  (`src/macro.jl:50-56`). The review's script shows the bug is real: `@parameters b` is
  accepted and then `b` inside an `edges(bond)` term resolves to the endpoint built-in.
  The alternative (endpoints named `cell₁`/`cell₂` to free `a`/`b`) is more typing in
  every edge term for the sake of two letters; a clear error with the rename hint is the
  better trade.
- Glazier: `a`, `b` for cells of a pair is the notation of the papers themselves (12b Fig 4
  uses a, b for the two cells; 13 Eq 2 for the triple's ends), and the semi-axes clash in
  12 is fixed by `a₀`, `b₀` with no loss.
- Resolution: agreed.
- Consequence: R0b adds `:a`, `:b` to `_BOUND_BUILTINS` (`src/macro.jl:44-46`); the error
  message suggests `a₀`/`b₀`; no model in `lib/PottsModels/src` is affected.

**Q9 — The breaking batch: one DECISIONS entry, no aliases, landed across P6.0m and P6.0c rather than as a step of its own.**
- SciML: pre-1.0 and local-only is when breaking is free; the ecosystem practice is one
  coherent breaking release with a changelog, not a trickle of deprecations. Aliases for
  `CPMProblem` or the `@sweep` solver keywords would keep two vocabularies alive in the
  docs. D-028 already sets the precedent ("old names are not kept as aliases").
- Glazier: the models are the tests; `lib/PottsModels` and the tutorials are edited in the
  same change so that every published model still builds and its reproduction test still
  passes. Nothing scientific changes: renames and keyword moves do not touch ΔH. The one
  exception is Merks' `lower = 0.0` clamp, which is physics (a concentration cannot go
  negative) and must survive the move verbatim (§3.4). There is no Merks band in
  `papers.jl` (it covers GG, WortelAct and Akeeb, `lib/PottsModels/test/papers.jl:8, 88,
  142`); the checks that must be unchanged in result are the Merks mechanism tests
  (`lib/PottsModels/test/mechanisms.jl:324-348`) and the gate's `merks_100` case
  (`benchmark/gate.jl:29`), each of which now passes `field_solver` explicitly, and a bare
  call is a construction error rather than a silent `ExplicitEuler()`.
- Resolution: agreed.
- Consequence: a single decision entry (D-07x, TBD, ≥ D-075: D-070–D-074 are taken,
  DECISIONS:1152-1260) listing: `CPMProblem → PottsProblem` (supertype unchanged);
  `field_solver`/`ode_solver` removed from `@sweep` and made `PottsProblem` construction
  keywords with the symbolic-keyed `solvers` map (`field_solver` required when a field
  exists); `track` as a construction keyword; the D-016 fingerprint extension; `Adaptive(alg; abstol, reltol)` kept as the bundle;
  `ExplicitEuler(; substeps, lower)`; `a`/`b` reserved; `Chemotaxis` `when` default;
  `connectivity` per D-074; the P6.0c and P6.5b rewordings. `PottsStats` names are **not**
  in the batch (they stay). It lands across P6.0m (hygiene, rename) and P6.0c (solver
  move), before the next reproduction item (§6.4).
