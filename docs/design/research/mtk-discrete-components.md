# MTK discrete-time components (P6.0k spike, D-065 Q9)

Status: investigation, 2026-09-30. Nothing in `src/` changes. The scratch evidence is in
`/tmp/p60k/` (`d1.jl`–`d8.jl`, `proto.jl`, `proto_lag2.jl`). The prototype's core is
reproduced in the appendix so this note stands alone.

**Maintainer decision (D-065 Q9).** Boolean and discrete networks are MTK discrete-time
components (clocked, `Shift`), extending D-038, with a well-tested lowering into the per-cell
phases. There is no Potts truth-table helper.

## 0. Summary

- **Feasible today, on the workspace's own MTK.**
  - The workspace uses **ModelingToolkitBase 1.77.0** (Symbolics 7.41.1, SymbolicUtils 4.48.0,
    SciMLBase 3.56.1). Full `ModelingToolkit` is **not** in the workspace Manifest.
  - `mtkcompile` of a purely discrete `System` works. It returns a small, regular form:
    - lag unknowns `xₜ₋₁`;
    - one equation `Shift(t, 1)(xₜ₋₁) ~ x(t)` per lag;
    - one observed equation `x(t) ~ f(lags, params)` per discrete variable, with same-step
      reads already substituted in dependency order.
  - Bool unknowns and parameters with `&`, `|`, `!`, `xor` and `ifelse` compile.
  - The clock period survives as `VariableTimeDomain` metadata on the compiled unknowns.
- **The prototype works.** It extracts that form and generates one per-cell Jacobi "tick"
  function. That function matches a hand-written 3-node truth table:
  - on the CPU, with Float32, Float64 and Bool storage, and zero warm allocations;
  - on Metal (Float32 and Bool storage), through a KernelAbstractions kernel.

  It also handles an in-step-ordered variant, a Jafari-style rule with a thresholded
  coupling on a `Clock(5)` (a tick every 5 MCS), and a lag-2 recurrence.
- **Full ModelingToolkit 11.45.3 is worse here, not better.** Its open-source compiler
  rejects every clocked discrete system ("Discrete systems with multiple clocks are not
  supported with the standard MTK compiler"), as well as hybrid Sample/Hold systems.
  - Loading ModelingToolkit also overrides `ModelingToolkitBase.mtkcompile`. The
    MTKBase path that works in the workspace then throws.
  - This is the one gap that could bite a user. It has an MTK-sanctioned workaround
    (§4, G1).
- **What Potts does today.** `@components` of a discrete system fails at `mtkcompile` of the
  Potts model:
  - Bool-typed: `AssertionError: T === Bool`, from substituting a Bool MTK leaf with a
    Real Potts variable.
  - Real-typed: `ArgumentError: only explicit ODEs D(x) ~ f are supported`.

  Both have simple fixes (§3, §4).

## 1. Versions and discrete-time support (runnable evidence)

The environment is the worktree root project (`julia --project=.`), with Julia 1.12.6.
Versions come from `Manifest.toml`: ModelingToolkitBase 1.77.0, Symbolics 7.41.1,
SymbolicUtils 4.48.0, SciMLBase 3.56.1, KernelAbstractions 0.9.43 and Metal 1.10.0 (Metal is
in the `test` project). **No `ModelingToolkit` entry exists.** For comparison, full MTK was
installed in a scratch environment, `/tmp/p60k/mtkenv`: ModelingToolkit 11.45.3 on
ModelingToolkitBase 1.77.2, with ModelingToolkitTearing 1.20.6 and StateSelection 1.11.1.

### 1.1 API in ModelingToolkitBase 1.77 (`d1.jl`, `d2.jl`, `d3.jl`, `d8.jl`)

| Item | MTKBase 1.77 | Notes |
|---|---|---|
| `Clock`, `Shift`, `ShiftIndex`, `Sample`, `Hold`, `SampleTime`, `SolverStepClock` | exported | `Clock` is `SciMLBase.Clock`, so `Clock(dt; phase)` is a `PeriodicClock` |
| `ShiftIndex(Clock(dt))`, `ShiftIndex(dt)` | works | `x(k)` tags `x` with `VariableTimeDomain = clock` |
| `ShiftIndex(t, 0)` | works | `IntegerSequence` clock: a pure step count, with no period |
| `ShiftIndex()` (inferred clock) | **MethodError** | Full MTK has it, but there it fails clock inference (§1.3) |
| `System([x(k) ~ f(x(k-1))], t)` | works | |
| `mtkcompile` of a purely discrete system | **works** | Form below; `is_discrete_system(cs) == true` |
| `x(k+1) ~ f(x(k))` | error: "Only non-positive shifts are allowed" | Write it as `x(k) ~ f(x(k-1))` |
| `x(k) ~ f(x(k), x(k-1))` (implicit) | compiles, leaving the algebraic `0 ~ …` | Not an explicit update, so the lowering rejects it |
| Same-step reads `C(k) ~ !(A(k) \| B(k-1))` | works | MTK substitutes `A(k)` from its observed equation (the rule is ordered) |
| Deeper lags `z(k-2)` | works | Chain `Shift(zₜ₋₂) ~ zₜ₋₁`, `Shift(zₜ₋₁) ~ z` |
| Array variables `z[1:3]` | works | Scalar observed equations plus an extra `z ~ array_literal(…)` (skip it) |
| Clock after `mtkcompile` | kept | `getmetadata(u, VariableTimeDomain)` on each unknown gives `PeriodicClock(5.0, 0.0)` or `IntegerSequence()` |
| `DiscreteProblem`, `ImplicitDiscreteProblem` (Real) | work | `tType` is `Int`, one step per unit, **the clock period is ignored** |
| `DiscreteProblem` with any Bool unknown or parameter | **TypeError** | `expected ParameterIndex{Initials,Int}, got ParameterIndex{Constants,…}` (bug) |
| `generate_rhs(cs)` (Bool) | works | Emits `(!)(u[1])`, but its argument layout (`MTKParameters`, `Vector u`) is host-only |
| Hybrid `D(x) ~ … + Hold(yd)`, `yd(k) ~ Sample(clock)(x) …` | **compiles silently wrong** | No clock partitioning: `yd` becomes an *observed* of the continuous `x`, not held |
| Hybrid without Sample (`D(x) ~ yd`, `yd(k) ~ yd(k-1) + x`) | `HybridSystemNotSupportedException` | |

The compiled form, from `d1.jl` (and likewise for Bool):

```
eqs = [x(k) ~ a*x(k-1) + y(k-1), y(k) ~ x(k-1)]  →  mtkcompile  →
unknowns:  yₜ₋₁(t), xₜ₋₁(t)
equations: Shift(t, 1)(yₜ₋₁(t)) ~ y(t),  Shift(t, 1)(xₜ₋₁(t)) ~ x(t)
observed:  x(t) ~ yₜ₋₁(t) + a*xₜ₋₁(t),   y(t) ~ xₜ₋₁(t)
initial_conditions: x(t) => 1.0, y(t) => 0.0, a => 0.5     # keyed by the node, not the lag
```

MTK's own convention for initial values: the defaults are the node values at step 0.
`DiscreteProblem` solves the initialization for the lags, then stores `u0 = f(u0)`. The
stored vector therefore holds the **latest node values** `x(0)`, and `prob.f(u)` returns
`x(1)`. Evidence: `u0 = [0.0, 1.0]` and `f(u0) = [1.0, 0.5]` for `x(0) = 1, y(0) = 0`.
The Potts lowering adopts the same meaning: a stored slot holds the latest value of its
node.

### 1.2 Boolean logic (`d2.jl`, `d8.jl`)

- **Bool variables and parameters** (`@variables A(t)::Bool`, `@parameters wnt::Bool`).
  - `&`, `|`, `!`, `xor` and `ifelse` build terms with symtype Bool, and `mtkcompile`
    keeps them.
  - The Jafari rule "Wnt ∨ (Akt ∧ ¬cadherin ∧ ¬APC)" (spec 11a, Table 1) compiles as
    written: `β(t) ~ Wnt | ((Aktₜ₋₁(t) & !cad) & !APC)`.
  - Output nodes that no rule reads at `k-1` (β here) become **observed only**, with no
    unknown. The lowering must still store them (§3.2).
  - The spec's precedence caveat (§7 of spec 11) is a modelling question; MTK does not
    settle it.
- **Real (0/1) variables.**
  - `!x` fails at construction (`MethodError`).
  - `x & y` *builds* a term but would throw at run time on floats.
  - `ifelse(cond, 1.0, 0.0)` and comparisons work.
  - **Use Bool-typed MTK variables for Boolean nodes.**
- **Thresholded inputs** (`i(k) ~ frac > T`) compile to an observed with no unknown: a
  sampled input.
- **MTKBase does not type-check.** `A::Bool ~ 1 + x` compiles, so the lowering must check
  that a Bool slot gets a Bool expression.

### 1.3 Full ModelingToolkit 11.45.3 (`d6.jl`, `d7.jl`, in `/tmp/p60k/mtkenv`)

Every clocked discrete system fails, even `x(k) ~ 0.5x(k-1)`:

- `HybridSystemNotSupportedException: Discrete systems with multiple clocks are not
  supported with the standard MTK compiler.`
- The source is `ModelingToolkit/src/systems/systemstructure.jl:146-172`. After
  `infer_clocks!`/`split_system`, a system with no continuous partition is compiled only
  when `additional_passes` contains a pass `p` with `ModelingToolkit.discrete_compile_pass(p) == true`
  (the default is `false`, `systems.jl:224`). No open-source package in the depot provides
  one; JuliaSimCompiler is the commercial provider.

Other results in full MTK:

- `ShiftIndex()` (an inferred clock) fails: "a clock partition that must be discrete … does
  not have any associated clock".
- Hybrid Sample/Hold fails: "Hybrid continuous-discrete systems are currently not supported
  with the standard MTK compiler".
- **Loading ModelingToolkit changes `ModelingToolkitBase.mtkcompile`.** The stack trace
  runs `ModelingToolkitBase.mtkcompile` → `_mtkcompile` → `ModelingToolkit.__mtkcompile`.
  A user who does `using ModelingToolkit` next to Potts would therefore turn a working
  discrete component into an error.

## 2. How D-038 lowers a continuous component today

The code is `src/components.jl` (`_bind_components`) and `src/codegen.jl` (`_phases`,
`_cell_ode_expr`, `_ode_steps`).

1. `ModelingToolkitBase.mtkcompile(comp.system)` runs once.
2. Each unknown `u` becomes a Potts `variable(@variables name₊u(t), :cell or :model; default)`.
   It is a **Real** symbolic, with defaults from `initial_conditions(cs)` as `Float64`.
3. Each parameter becomes either a model parameter `name₊p` (`parameter(nm, Float64 default)`)
   or, when coupled with `@equations name.p ~ expr`, that cell-scope expression.
4. Observed equations are expanded to a fixpoint and exposed under `name₊y`.
5. Every equation must be `D(x) ~ f`, or an `ArgumentError` is thrown. The right side is
   kind-gated (`ifelse(kind ∈ kinds, rhs, 0)`) and appended to the model's cell ODEs.
6. Codegen puts all cell ODEs into **one** `CorePotts.CellPhase`, the last per-cell
   phase of `after_mcs`. It runs after the update stages and field steps, and before the
   model ODEs and link phases.
   - The phase reads state into locals `y_i`. Every right side sees the start-of-step
     state (Jacobi).
   - It takes `substeps` fixed steps and writes back.
   - Dead cells (`volume == 0`) are skipped.
7. The model's own update blocks (`@after_mcs`, D-042) already follow MTK discrete
   semantics.
   - `Pre(x)` is the previous value. A variable read through `Pre` by another update is
     snapshotted in `x__pre`, and the scheduler orders bare reads.
   - `Every(n)` wraps a phase in `_Gated(n, phase)`, which runs when `mcs % n == 0`.
   - `d5.jl` checks this: a hand-written `x ~ ifelse(Pre(y) > 0.5, 0, 1); y ~ Pre(x)`
     cycles (0,1) → (0,0) → (1,0) → (1,1) → (0,1), which is exactly the Jacobi Boolean
     update.

## 3. Proposed lowering of a discrete component

### 3.1 Detection and extraction (the "discrete update")

After `cs = mtkcompile(comp.system)`, a component is **discrete** when any equation has a
`Shift` on its left side. A component is either continuous or discrete, never both (§4, G4).

The extraction (`discrete_update` in the appendix) does the following:

- **Reject** anything MTKBase compiles but the lowering cannot honour. Each rejection is an
  `ArgumentError` naming the component:
  - `Differential` anywhere (a hybrid system);
  - `Sample`/`Hold` (MTKBase compiles them with the wrong semantics);
  - any equation that is not `Shift(t, 1)(ℓ) ~ rhs` with `ℓ` an unknown (implicit or
    algebraic `0 ~ …`);
  - more than one clock among the unknowns;
  - a Bool node whose expression is not Bool.
- **Slots** are the stored per-cell values. There is one slot per discrete variable (the
  left side of each observed equation, skipping `array_literal` aggregates), named after
  the node: `grn₊A`. A lag of a lag (`zₜ₋₂`) gets an extra slot named after its source
  (`grn₊zₜ₋₁`).
- **Lag leaves.** Each lag unknown `ℓ` with `Shift(ℓ) ~ v` reads the slot of `v`, as it
  was before the tick.
- **Next values.** Each slot gets the fixpoint-expanded observed right side, which is a
  function of lag leaves and parameters only. A lag-of-lag slot gets its source's
  pre-tick value.
- **Clock.** Read `VariableTimeDomain` from the unknowns:
  - `IntegerSequence` (`ShiftIndex(t, 0)`) means one tick per MCS.
  - `PeriodicClock(dt, phase)` means one tick every `n = dt / mcs_duration` MCS. `n` must
    be a positive integer (relative tolerance 1e-9), and so must `phase / mcs_duration`
    (the offset). Anything else is an `ArgumentError`.
  - A component with no unknowns (pure thresholds) ticks every MCS unless its variables
    carry a clock.

### 3.2 The per-cell phase

There is **one `CellPhase` per distinct clock**. All discrete components on the same
clock fuse into it, as D-038 fuses the ODEs. The generated body below is the prototype's
(`proto.jl`, `T = Float32`) output, plus the two Potts gates (liveness and kinds), which
the prototype did not emit:

```julia
(st, p, mcs, c) -> begin
    mcs % 5 == 0 || return nothing                       # Clock(5) at mcs_duration = 1 (only when n > 1)
    @inbounds st.cell.volume[c] > 0 || return nothing    # live cells (as _cell_ode_expr)
    kind ∈ kinds || return nothing                       # @components cells(kinds…)
    y_1 = !(iszero(@inbounds st.jaf₊Akt[c]))             # lag leaves: pre-tick slots, cast to Bool
    y_2 = !(iszero(@inbounds st.jaf₊PI3K[c]))
    q_1 = !(iszero(p.jaf₊Wnt))                           # uncoupled Bool parameter (stored as T)
    q_2 = !(iszero(p.jaf₊APC))
    q_3 = !(iszero(@inbounds st.contact[c] > 0.3f0))     # coupled: @equations jaf.cad ~ <cell expr>
    v_1 = (|)(q_1, (&)((&)(y_1, (!)(q_3)), (!)(q_2)))    # β = Wnt | (Akt & !cad & !APC)
    v_2 = y_2                                            # Akt = PI3K(k-1)
    v_3 = y_2                                            # PI3K = PI3K(k-1)
    @inbounds st.jaf₊β[c] = (Float32)(v_1)               # write every slot after every read
    @inbounds st.jaf₊Akt[c] = (Float32)(v_2)
    @inbounds st.jaf₊PI3K[c] = (Float32)(v_3)
    return nothing
end
```

- **Jacobi or ordered update.** The update order is *the MTK equations'* order; Potts
  does not choose it.
  - All reads are locals taken before any write, so a rule written with `x(k-1)` is
    synchronous (Jacobi). This is the Jafari spec's synchronous update (11a p.11).
  - A rule that reads `y(k)` sees y's new value. MTK has already substituted it
    (`C(k) ~ !(A(k) | B(k-1))` becomes `!((wnt | (Bₜ₋₁ & !Cₜ₋₁)) | Bₜ₋₁)`). This gives
    sequential, Gauss–Seidel-style updating in a deterministic order, and the prototype
    confirms it against its own reference.
  - A cycle of same-step reads is an algebraic loop, so MTK leaves `0 ~ …`, which is
    rejected.
  - Random-order *asynchronous* updating (as in Boolean-network toolboxes) is not a
    deterministic MTK form. §4, G9 gives the MTK-form workaround.
- **Where the tick runs:** in `after_mcs`, **after** the cell and model ODE phases and
  **before** the link phases and the lifecycle.
  - This matches MTK's hybrid semantics at a tick `t_k`. The discrete partition samples
    the continuous state at the end of the interval, and the continuous side sees the
    held value over the next interval.
  - Division rules and model updates in the next MCS read the fresh node values.
- **The cadence is `Every(n)`.** The gate is the same `mcs % n == 0` (with an offset for
  `phase`) that `@after_mcs Every(n)` and P6.0f's lifecycle `Every(n)` use. `n == 1`
  emits no gate. The ROADMAP should keep a single definition: "a phase with cadence `n`
  runs after MCS `m` when `m % n == 0`".
- **Storage is `T`, holding exact 0/1 (Float32 on Metal).**
  - Keeping the state NamedTuple homogeneous leaves SII, `sol[:grn₊A]`, saving, plotting,
    `remake`, division copy rules and `CopyPhase` untouched.
  - 0 and 1 are exact in every float type.
  - Bool storage also works, on CPU and Metal (see the prototype). Keep it, or UInt8, as
    a later memory optimisation behind the same lowering, not now.
- **The Bool cast happens only at the phase boundary.** Reads use `!iszero(slot)` and
  writes `T(v)`. Inside, the code is plain Bool logic that Metal compiles (the prototype
  verified this).
- **Parameters and couplings (D-038 unchanged).**
  - An uncoupled component parameter `p` becomes a model parameter `grn₊p`. A Bool
    default is stored as `T` 0/1 and read with `!iszero`.
  - A coupled parameter `@equations grn.p ~ expr` is lowered by Potts' `lower` in the
    cell environment, so it can read cell variables, `volume`, integrals, other
    components' slots and `rand()` with the phase key. A Bool parameter coupled to a Real
    expression is cast with `!iszero`; write thresholds explicitly (`contact_frac > T_cad`).
  - Reading the other way, `grn.A` in model statements becomes the cell variable
    `grn₊A`. It is tagged `boolean = true` in its `Info`, so `lower` emits
    `!iszero(st.cell.grn₊A[c])` where a Bool is needed and the raw `T` elsewhere
    (`λ * grn.A` works either way).
- **Continuous ↔ discrete coupling across components** replaces MTK's Sample/Hold, which
  MTKBase cannot compile (G3).
  - A continuous component coupled to a discrete slot (`ode.k ~ grn.A`) holds that value
    until the next tick: a zero-order hold.
  - A discrete component coupled to an ODE state (`grn.cad ~ ecad.x > 0.5`) samples it at
    the tick.
  - Each component remains a pure MTK `System`.

### 3.3 Initial values

- A slot's default is `initial_conditions(cs)[x(t)]`, as a Bool or number, converted to
  `T`. This is MTK's convention (node values at step 0, §1.1).
- The operating point overrides it per cell: `:grn₊A => [true, false, …]`.
- Lag-of-lag slots take `initial_conditions` of `x(k-j)` when given. Otherwise an
  `ArgumentError` asks for a value.
- An output node with no default is an error, as for ODE components today. MTK's
  initialization would compute it; Potts asks for it instead (G8).

## 4. Gaps and MTK-first workarounds

| # | Gap | Where | Workaround (MTK representation kept) |
|---|---|---|---|
| G1 | Full ModelingToolkit 11 rejects clocked discrete systems, and **loading it overrides `ModelingToolkitBase.mtkcompile`** | MTK `systemstructure.jl:146-172` | The workspace uses MTKBase only, so nothing breaks today. When full MTK is loaded, Potts calls `mtkcompile(sys; additional_passes = [PottsDiscretePass()])` from a weak extension `PottsModelingToolkitExt`. That pass implements MTK's own hook `ModelingToolkit.discrete_compile_pass(::PottsDiscretePass) = true` and returns the same `Shift`/observed form. A test runs the extension against the MTKBase path. The hook is internal to MTK, so pin it and record the risk. The fallback is to detect `HybridSystemNotSupportedException` and extract from the uncompiled equations with the same explicit-update checks. |
| G2 | `ShiftIndex()` (inferred clock) is missing in MTKBase and fails inference in full MTK | `discretedomain.jl:113` | Document `ShiftIndex(t, 0)` (one tick per MCS) or `ShiftIndex(Clock(n * mcs_duration))`. |
| G3 | Hybrid systems: MTKBase compiles `Sample`/`Hold` **silently wrong**, throws without them, and full MTK throws too | §1.1, §1.3 | Reject `Differential`, `Sample` and `Hold` in a discrete component. Hybrid models become two components, one continuous and one discrete, coupled through `@equations` (hold and sample semantics, §3.2). |
| G4 | No clock partitioning, so one component can have only one clock | MTKBase | Reject multiple clocks in one component; put one clock per component. |
| G5 | `DiscreteProblem`/`ImplicitDiscreteProblem` throw `TypeError` (ParameterIndex Initials vs Constants) for any Bool unknown or parameter | MTKBase 1.77 | Not on Potts' path (Potts lowers symbolically). For MTK-level oracles in tests, use a Real-typed twin or the hand-written table. Report upstream. |
| G6 | `DiscreteProblem` ignores the clock period (integer `t`) | MTKBase | Potts reads the period from `VariableTimeDomain` and converts it to `Every(n)`. |
| G7 | The Bool symtype is not enforced (`A::Bool ~ 1 + x` compiles). Substituting a Bool leaf with a Real stand-in throws `AssertionError: T === Bool` (today's Potts failure) | SymbolicUtils `promote_symtype(!)`, `src/components.jl` | Create Potts stand-ins and locals with the MTK leaf's symtype (`Symbolics.variable(y; T = symtype(u))`, as in the prototype). Check `symtype(next) === Bool` for Bool slots. |
| G8 | Initialization of output-only nodes, which MTK would solve | lowering | Require a default or an operating-point value, as for ODE components. |
| G9 | Random-order asynchronous Boolean updating is not a deterministic MTK form | semantics | In MTK form: a coupled per-cell random input `@equations grn.u ~ rand()` and rules `A(k) ~ ifelse(u < 1/3, f_A, A(k-1))`. No Potts-side network representation. |
| G10 | `x(k+1) ~ f(x(k))` is rejected ("only non-positive shifts") | MTKBase | Write `x(k) ~ f(x(k-1))`. Documentation only. |
| G11 | Array variables add a `z ~ array_literal(…)` observed | MTKBase | **Implemented (P6.0k):** aggregate observed equations are skipped and each element is a scalar slot `grn₊z_1…` (a matrix: `grn₊z_i_j`), the `QuantityVector` convention; an element's default comes from the array's default. Two slots with one name are an `ArgumentError`. |
| G12 | `Clock(dt, phase)` positional form is missing | SciMLBase | Use `Clock(dt; phase)`. Documentation only. |
| G13 | A Bool node read at an index (`grn.A[j]`) is built by Potts' `at`, which is Real-typed, so `&`, `!` and `ifelse` on it failed | Potts `_index` | **Implemented (P6.0k):** `x[j]` of a `Bool` quantity is `_nonzero(at(x, j))`, a Bool read of the slot at `j`. (MTK initialization, ill-posed for Boolean maps, is never run: values come from defaults and the operating point; see G8.) |
| G14 | `Clock(n)` ticks at MTK clock times `t = n, 2n, …` (after MCS `n − 1`, …), one MCS later than `Every(n)` (MCS 0, n, …) | semantics | Deliberate: the clock belongs to the MTK system. To align with `Every(n)`, use `Clock(n; phase = 1)`, which ticks at `t = 1, n + 1, …`, i.e. after MCS 0, n, …. |
| G15 | An under-determined discrete system (a node read with no update of its own) surfaces MTK's `ExtraVariablesSystemException` | MTKBase | Wrapped in an `ArgumentError` naming the component and prefixed "every discrete variable needs an update `x(k) ~ …`". |

**Implementation notes (P6.0k).**
- A tick reads only pre-tick values across cells and phases: when a cell-scope rule reads a
  slot at another index (`x[j]`, a gather, an unhoisted fold), or when several tick phases
  exist (scopes, clocks), new values go to scratch slots `x__tick` published after all ticks.
  Measured on the fixture network (21 cells, 3 slots, CPU): the scratch path adds about
  45 ns per tick MCS (after-MCS phases 215 → 265 ns), with the MCS itself unchanged at
  about 17–18 µs and zero allocations.
- **N3 (out of scope, recorded).** The same Gauss–Seidel-across-cells effect exists for
  cell ODEs (D-038): a cell ODE whose rate reads another cell's ODE state (`x[j]`) sees
  the neighbour's updated value if that cell was already advanced in the same kernel, and
  races on the GPU. No model does this yet; the same scratch treatment would apply.

G1–G12 should become one DECISIONS entry that extends D-038, as the ROADMAP P6.0k
acceptance requires. That entry should be written with the implementation, not in this
spike.

## 5. Proposal

### 5.1 User syntax and semantics

```julia
using Potts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables, @parameters, @named
const t = Potts.t

k = ShiftIndex(t, 0)                  # one tick per MCS (or ShiftIndex(Clock(n * mcs_duration)))
@variables A(t)::Bool = false B(t)::Bool = false C(t)::Bool = false
@parameters wnt::Bool = false
@named grn = System([A(k) ~ wnt | (B(k - 1) & !C(k - 1)),
                     B(k) ~ A(k - 1),
                     C(k) ~ !(A(k - 1) | B(k - 1))], t)

@potts_model Tumour begin
    @kinds medium tumour
    @variables signal(cell) = 0.0
    @components cells(tumour) grn = grn               # the same statement as D-038
    @equations grn.wnt ~ signal > 0.5                 # coupling: a cell-scope expression
    @divide cells(tumour) when = grn.A && volume >= 40, along = principal_axis()
    ...
end
```

- `@components cells(kinds…) name = sys` and `@components model name = sys` accept a
  discrete `System`. **No new macro, keyword or truth-table form is added.**
- Each discrete variable `x` of `sys` becomes the cell (or model) variable `name₊x`. It
  holds the value from the latest tick (MTK's `x(k)`), stored as `T` 0/1 when Bool.
- A tick replaces every slot with the rule evaluated on the pre-tick values. It runs in
  `after_mcs` after the ODEs, for live cells of the component's kinds, every `n` MCS, where
  `n` is the clock period divided by `mcs_duration`.
- The update order is MTK's: `x(k-1)` is synchronous, and a same-step `x(k)` read is
  ordered.
- Couplings, parameter naming, `sol[:grn₊A]` and operating-point overrides are those of
  D-038.

### 5.2 Frozen acceptance test outline (`lib/PottsModels/test/acceptance/p6_0k_boolean_network.jl`)

Freeze the following before implementation (AUTONOMY §7.3).

1. **Fixture.**
   - The 3-node network `grn` of §5.1 on `ShiftIndex(t, 0)`.
   - A model with one kind, a cell variable `input(cell)`, the coupling
     `@equations grn.wnt ~ input > 0.5`, a volume energy and `T` small but nonzero.
   - 16 cells in a 4×4 grid. The operating point gives cell `i` the i-th combination of
     `(input, A, B, C) ∈ {0,1}⁴`.
2. **Reference.**
   - A hand-written literal table `TABLE::Dict{NTuple{4,Int}, NTuple{3,Int}}` with 16
     rows, written out in the test file as in `proto.jl`, not computed from the rules.
   - It is iterated for each cell over `K = 12` ticks. The reference trajectory is
     `ref[i][m]`.
3. **Exact agreement.**
   - For `alg ∈ (SequentialCPM(), CheckerboardCPM())` and `T ∈ (Float64, Float32)`,
     `solve(prob, alg; saveat = 0:K)`.
   - For every cell `i` and tick `m`, `(sol.u[m+1].cell.grn₊A[i], …B, …C) == ref[i][m]`,
     compared exactly.
   - The trajectories do not depend on the sweep, because the inputs are cell variables.
4. **Metal** (the `GPU` group, `POTTS_GPU=metal`): the same with `T = Float32`,
   `CheckerboardCPM()` and `backend = MetalBackend()`. Exact equality.
5. **Zero warm allocations.**
   - `minimum(_qa_warm_allocated(init(prob, alg)) for _ in 1:5) == 0` for both algorithms,
     with Float32 and Float64.
   - `check_allocs` on the generated tick phase.
6. **Cadence.**
   - `Clock(2.0)` at `mcs_duration = 1` ticks only after MCS 2, 4, … (the slots are
     unchanged on odd MCS, and on even MCS equal the reference at tick `m ÷ 2`).
   - `Clock(1.5)` throws an `ArgumentError`.
7. **Ordering.** The variant `C(k) ~ !(A(k) | B(k-1))` matches its own literal table. On at
   least one row it differs from the Jacobi table, so the test can tell the two semantics
   apart.
8. **Kinds and liveness.**
   - With two kinds, the component on `cells(tumour)` leaves the other kind's slots at
     their initial values.
   - A cell that reaches `volume == 0` stops ticking.
9. **Negative controls.**
   - Swapping `&` for `|` in the A rule fails check 3 (asserted with `@test !`).
   - An `@after_mcs` hand-written update with the wrong lag also fails it.
10. **Rejections** (`ArgumentError`, whose message names the component):
    - a component with `D(x)`;
    - `Sample`/`Hold`;
    - an implicit `x(k) ~ f(x(k))`;
    - two clocks in one system;
    - a Bool node given a Real rule.
11. **A Jafari-style smoke test.**
    - The node `β(k) ~ Wnt | (Akt(k-1) & !cad & !APC)`, with `cad` coupled to a contact
      threshold (`cadherin fraction > 0.3`) on a frozen two-cell configuration.
    - β is 1 exactly for the low-contact cell, one tick after Akt turns on.

### 5.3 Implementation write set

- `src/components.jl`
  - Split `_bind_components` into continuous and discrete binding.
  - Add `_discrete_update(cs)` (extraction, rejections, clock → `every`, slots and
    defaults).
  - Make substitutions keep symtypes (G7).
  - Collect the discrete blocks into the returned `PottsSystem`.
- `src/system.jl`: add a `discrete::Vector{DiscreteBlock}` field (slots, next expressions,
  kinds, `every` and `offset`) to `PottsSystem`, carried by `extend` in `src/compose.jl`.
- `src/vocabulary.jl`: add the `boolean` variable option to `_VARIABLE_OPTIONS`. It is set
  internally from MTK symtypes.
- `src/lower.jl`: emit `!iszero(…)` for boolean-tagged cell variables and parameters where
  a Bool is needed.
- `src/compile.jl`
  - Store the discrete blocks in `CompiledPottsSystem`.
  - Run name and scope checks with source lines.
  - Verify that the clock ratio is an integer.
- `src/codegen.jl`
  - Add `_cell_discrete_expr(c, T, block)` (and a model-scope twin).
  - In `_phases`, place it after the ODE phases and before `_link_phases`, gated by
    `_Gated(every, …)`, which is shared with `Every(n)`.
- `src/problem.jl`: initialize slot defaults and overrides (Bool → `T`), and let `remake`
  accept Bool parameter values.
- `ext/PottsModelingToolkitExt.jl` (weak dependency on `ModelingToolkit`) with the G1
  pass. It could be deferred to a follow-up, but the fallback detection must land with
  this work.
- Tests
  - `test/symbolic.jl`: unit tests of the extraction and the rejections.
  - `lib/PottsModels/test/acceptance/p6_0k_boolean_network.jl`: frozen (§5.2).
  - `test/gpu.jl`: the Metal case.
  - `test/qa.jl`: the model joins the warm-allocation and JET gates.
- `docs/design/DECISIONS.md`: a new entry extending D-038 (discrete components,
  semantics, gaps G1–G12). `ROADMAP.md`: tick P6.0k.

## Appendix: prototype core (`/tmp/p60k/proto.jl`)

This is abridged. The full script also runs the 16-row truth table on CPU (Float32,
Float64, Bool) and Metal (Float32, Bool), the ordered variant and the Jafari clocked rule.
Output: *all prototype checks passed; warm allocations 0*. `proto_lag2.jl` checks a
lag-2 recurrence: `z` over 6 ticks is `[2, 3, 5, 8, 13, 21]`.

```julia
function discrete_update(sys)
    cs = mtkcompile(sys)
    eqs, obs = equations(cs), observed(cs)
    for eq in [eqs; obs], side in (eq.lhs, eq.rhs)
        _has(S.Differential, side) && error("hybrid system: not a discrete component")
        (_has(Sample, side) || _has(Hold, side)) && error("Sample/Hold unsupported (MTKBase has no clock partitioning)")
    end
    unk = Set{Any}(unknowns(cs)); src = Dict{Any, Any}()
    for eq in eqs
        l = S.unwrap(eq.lhs)
        (iscall(l) && operation(l) isa Shift && operation(l).steps == 1 && arguments(l)[1] in unk) ||
            error("not an explicit discrete update: $eq")
        src[arguments(l)[1]] = S.unwrap(eq.rhs)
    end
    obsd = Dict{Any, Any}(S.unwrap(o.lhs) => S.unwrap(o.rhs) for o in obs)
    expand(x) = fixpoint(y -> S.unwrap(S.substitute(y, obsd; fold = Val(false))), x)
    slots, booleans, next, lagslot = Symbol[], Bool[], Any[], Dict{Any, Symbol}()
    for o in obs
        push!(slots, getname(o.lhs)); push!(booleans, symtype(S.unwrap(o.lhs)) === Bool)
        push!(next, expand(S.unwrap(o.rhs)))
    end
    for (u, v) in src; v in unk || (lagslot[u] = getname(v)); end
    for (u, v) in src                                   # lag of a lag: its own slot
        v in unk && (push!(slots, getname(v)); push!(booleans, symtype(u) === Bool); push!(next, v);
                     lagslot[u] = getname(v))
    end
    clock = only(unique(getmetadata(u, VariableTimeDomain, nothing) for u in unknowns(cs)))
    return (; slots, booleans, next, lagslot, params = parameters(cs),
        period = clock isa PeriodicClock ? clock.dt : nothing)
end

# locals first (Jacobi), then every write; Bool cast only at the boundary
function tick_expr(du, ns; T, every = 1, couplings = Dict())
    ys = Dict{Any, Any}(); body = Any[]
    for (i, (u, s)) in enumerate(du.lagslot)
        ys[u] = S.unwrap(S.variable(Symbol(:y_, i); T = symtype(u)))    # keep the symtype (G7)
        read = :(@inbounds st.$(Symbol(ns, :₊, s))[c])
        push!(body, :($(Symbol(:y_, i)) = $(symtype(u) === Bool ? :(!iszero($read)) : :($T($read)))))
    end
    for (j, q) in enumerate(du.params)
        ys[q] = S.unwrap(S.variable(Symbol(:q_, j); T = symtype(q)))
        code = get(couplings, getname(q), :(p.$(Symbol(ns, :₊, getname(q)))))
        push!(body, :($(Symbol(:q_, j)) = $(symtype(q) === Bool ? :(!iszero($code)) : :($T($code)))))
    end
    for (j, x) in enumerate(du.next)
        push!(body, :($(Symbol(:v_, j)) = $(S.toexpr(S.substitute(x, ys; fold = Val(false))))))
    end
    for (j, s) in enumerate(du.slots)
        push!(body, :(@inbounds st.$(Symbol(ns, :₊, s))[c] = $T($(Symbol(:v_, j)))))
    end
    gate = every == 1 ? nothing : :(mcs % $every == 0 || return nothing)
    return :((st, p, mcs, c) -> begin $gate; $(body...); return nothing end)
end
```

In Potts, `S.toexpr` is replaced by `lower(x, _cell_env(T, :c, rn; extra = locals))`, so
that couplings, kinds and draws go through the existing lowering (as `_cell_ode_expr`
does), and the function is compiled with `_rgf`.
