# `boundary_schedule_tests.jl` (ROADMAP Phase 6, step 3; api-synthesis §2.11, §2.12, §6.1 (D-035 row), §6.4; R5):
# `@boundary` per face and per site mask (a masked clamp applied after EVERY explicit field
# substep), field phase placement and an explicit phase order. The phase order IS `@schedule`,
# with the `step!` restructuring of api-synthesis §2.12 (the sweep and the lifecycle become
# entries of the phase order). D-035 is amended as D-075 states, in the same change.
# Decision: D-145.
#
# The fields here are plain MTK PDESystems coupled with `@fields`, and the
# `@boundary` entries below are their conditions. `x => (Dirichlet(v), …)` is `c(t, 0, y) ~ v`
# (the high face `c(t, X, y) ~ v`, `X` the extent), `NoFlux()` is no condition, and
# `sites(pred) => Dirichlet(v)` is the masked condition `c ~ masked(mask, v)`, its 0/1 input
# `mask` bound to `pred` at `@fields`. The semantics, oracles and controls are unchanged.
#
# Surface pinned here (model content; nothing in core is model-named):
#
#   @boundary c begin
#       x => (Dirichlet(v_low), NoFlux())        # per face: one pair (low, high) per axis
#       y => (NoFlux(), Dirichlet(S))            # values: numbers, parameters, parameter expressions
#       sites(kind == border) => Dirichlet(v)    # masked clamp (a site predicate)
#   end
#
#   - One `@boundary <field>` block per field; `<field>` must be a `(field)` variable.
#   - Axes are named `x`, `y`, `z` (axes 1, 2, 3). A face value is a GHOST value (01 F7;
#     CorePotts' existing per-face rule): on a closed face, `Dirichlet(v)` sets the missing
#     neighbour to 2v − c (the face value is reached midway between the edge site and its
#     ghost), `NoFlux()` mirrors the site (ghost = c). A closed axis with no entry is
#     zero-flux (today's behaviour, unchanged). A face entry on a periodic axis, or an axis
#     the lattice does not have, is an error naming it.
#   - `sites(pred) => Dirichlet(v)` is a NODE value: after every explicit substep (after the
#     substep's write and any `lower` clip, before the next substep's rate is evaluated) every
#     site where `pred` holds is set to `v`. `pred` is re-evaluated from σ at every substep, so
#     the mask moves with the cells (api-synthesis §2.11, 06).
#   - `Dirichlet` and `NoFlux` are DSL names (`Potts.DSL`).
#   - Changing a boundary VALUE through a parameter (`remake(prob; p = [:S => …])`) does not
#     regenerate code (`remake(…).f === prob.f`); changing the boundary SPEC does (fingerprint).
#
#   @schedule fields, sweep                       # one line: phases of one MCS, in order
#
#   - Canonical names: `before_mcs`, `sweep`, `after_mcs`, `fields`, `components`, `operators`,
#     `lifecycle`, `end_mcs`. Each is accepted whether or not the model has that phase.
#     The default order (no `@schedule`) is today's:
#         before_mcs, sweep, after_mcs, fields, components, operators, lifecycle, end_mcs
#     (`fields` = the field PDE steps; today's after-MCS phase is after_mcs, fields, and the
#     ODE/discrete/link phases after them.)
#   - Placement rule for unlisted phases (D-145): the listed phases run in the listed order;
#     then each unlisted phase, taken in default order, is placed directly after the LAST
#     (in the order being built) of the phases that precede it in the default order, or first
#     if none does. So a schedule that lists phases in their default relative order equals no
#     schedule, and `@schedule fields, sweep` runs before_mcs, fields, sweep, after_mcs, …
#   - `end_mcs` is always last: listing it anywhere else is an error naming it.
#   - `before_mcs` must precede `sweep` and `after_mcs` must follow it when listed with it
#     (D-042's semantics refer to them): otherwise an error naming the phase.
#   - An unknown name, or a name listed twice, is an error naming it.
#   - The schedule is model content: different orders have different fingerprints, and a
#     checkpoint does not cross them.
#
# Semantics pinned here, and their oracles:
#  1. Ring (2D, the acceptance line "the absorbing frame keeps c = 0 on the ring after every
#     substep"): a frozen one-site frame `border` around a medium interior,
#     ∂c/∂t = Dc Δc + s, `sites(kind == border) => Dirichlet(cb)`. Oracle: a plain-Julia
#     explicit Euler (written here) that sets the ring to cb after every substep. Equality to
#     1e-12 after each of 3 MCS with 4 substeps per MCS OBSERVES EVERY SUBSTEP: the interior
#     after an MCS is a function of the ring values after substeps 1…n−1 (they enter the next
#     substep's stencil), and the ring itself is checked exactly (== cb) after substep n.
#     Negative controls, on the oracle (so the test is sensitive): clamping once per MCS (at
#     its end) changes the interior by > 1e-2; clamping BEFORE each substep instead of after
#     leaves the ring ≠ 0. The oracle itself is checked against CorePotts phases built by hand
#     on today's code (a control that passes now).
#  2. Moving mask: a non-frozen `sink` cell moving under the sweep, sweep then fields; after
#     every MCS, c == 0 exactly on the sites the sink owns NOW and c > 0 everywhere else
#     (s > 0 and a positive start keep them positive). Control: the sink's site set changes.
#  3. Per face, 2D (Closed × Periodic): `x => (Dirichlet(0.0), NoFlux())`, y periodic, no
#     cells. Oracle: the same explicit Euler with ghost rules. Negative controls: all
#     zero-flux and a NODE Dirichlet on the low face both differ from it by > 1e-2; mass
#     falls strictly every MCS (it is conserved without the Dirichlet face — the control
#     model without `@boundary`, which passes today and pins "unlisted face = zero flux").
#  4. Per face + mask, 3D (Closed × Closed × Periodic): `x => (Dirichlet(1.0), Dirichlet(0.0))`,
#     `y => (NoFlux(), Dirichlet(S))` and an interior frozen block clamped to 0; the oracle as
#     above; `remake(p = [:S => 0.5])` follows the oracle with S = 0.5 and keeps `f`.
#  5. PDE-before-sweep vs sweep-before-PDE (the acceptance line "ordering is observable in a
#     two-phase test"), two exact tests:
#     (a) a drive that vetoes every copy unless c[target] > s/2 (ΔH + 10⁶ otherwise; exp(−10⁶)
#         is 0), c(0) = 0, ∂c/∂t = s. With `@schedule fields, sweep` the first sweep sees c = s
#         and copies happen in MCS 0; with sweep first (default or listed) MCS 0 has none.
#         Site updates `@before_mcs wb ~ c`, `@after_mcs wa ~ c; occ ~ (kind == A)` pin the
#         placement of `fields` against before_mcs/after_mcs (exact values 0 or s per MCS),
#         and `occ == (σ .== cell)` in every saved state pins that after_mcs follows the sweep
#         in every order (including an unlisted after_mcs under `fields, sweep`).
#     (b) a Merks-shaped model (secreting cells, decay in the medium, chemotaxis, an absorbing
#         frozen frame): with `fields, sweep` the field step of MCS k sees σ(k) (the saved state
#         before the MCS), so u[k+1].c equals the explicit-Euler oracle on (u[k].c, u[k].ownership);
#         with `sweep, fields` it equals the oracle on (u[k].c, u[k+1].ownership). Each order FAILS the
#         other's oracle by > 1e-3 (negative control: swapping the order changes the result).
#     Both on SequentialCPM and CheckerboardCPM.
#  6. Listing the default relative order (`sweep, fields`; the full canonical list) equals no
#     schedule bit for bit (every saved state), on both algorithms. The lifecycle is an entry:
#     with `@schedule lifecycle, fields` a division at MCS 0 happens before the field step
#     (c = the daughter's volume, 8), by default after it (c = the mother's, 16).
#  7. Errors (any exception at expansion, construction or `PottsProblem`, message naming the
#     offender): a face on a periodic axis ("periodic"), axis `z` on a 2D lattice ("z"),
#     `@boundary` on a non-field variable (its name), an unknown phase (its name), a phase
#     listed twice, `end_mcs` not last, `after_mcs` before `sweep`, `before_mcs` after `sweep`.
#  8. Fingerprints: the schedule and the boundary spec are hashed (D-016): different orders
#     and with/without `@boundary` differ; a checkpoint of one order fails to load into the
#     other (`ArgumentError`). Parameter remakes of boundary values keep `f`.
#  9. Metal (skipped without POTTS_GPU=metal and Metal loaded; `T = Float32`,
#     CheckerboardCPM): 1–5 hold to Float32 tolerance (ring and mask values exactly), and
#     D-035 as amended (D-075 §6.1): a model with no host pass makes 0 syncs, 0 transfers and
#     0 bytes per quiet MCS whatever its schedule (device phase order costs nothing); a model
#     with one host pass (an `Adaptive` cell ODE) makes the same per-MCS syncs/transfers/bytes
#     under every schedule, exactly one sync per MCS (one round trip per firing).
#
# Not here (the coordinator checks at merge): the CPU gate is unchanged and the Metal A/B is
# ≤ 1.01 on the five gate models (their host phases are `nothing`).
#
# Today this fails with `UndefVarError: @boundary not defined` / `UndefVarError: @schedule
# not defined` (raised when a model source using them is evaluated, inside each testset), and
# `Dirichlet`/`NoFlux` missing from `Potts.DSL`. The controls (oracle against hand-built
# CorePotts phases; the no-`@boundary` zero-flux model; the unscheduled order and lifecycle
# models) pass on the base.

@testsetup module BoundaryScheduleSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using StableRNGs: StableRNG
using OrdinaryDiffEqRosenbrock: Rodas5P
# =======================================================================================
# Oracle: explicit Euler on a square N-D lattice, spacing 1, h = 1/nsub per substep.
#   axes[d] = :periodic, or (low, high) with each :noflux or a number v (ghost = 2v − c)
#   `node` = (d, side, v): a NODE Dirichlet on one face (sites on that face set to v after
#   every substep; a negative-control variant only)
#   rate = D Δc + src − decay·c (src, decay: numbers or arrays)
#   clamp ∈ (:post, :pre, :end): when `mask` is set to `val` (after every substep, before
#   every substep, or once at the end of each MCS)
# =======================================================================================
boundary_at(a, x) = a isa AbstractArray ? a[x] : a
function ftcs(
        c0, nsub, nmcs; D, src = 0.0, decay = 0.0, axes, mask = nothing, val = 0.0,
        clamp = :post, node = nothing
    )
    c = Float64.(copy(c0))
    h = 1.0 / nsub
    N = ndims(c)
    R = CartesianIndices(c)
    setmask!(c) = mask === nothing || (c[mask] .= val)
    function setnode!(c)
        node === nothing && return
        d, side, v = node
        for x in R
            Tuple(x)[d] == (side == 1 ? 1 : size(c, d)) && (c[x] = v)
        end
    end
    for _ in 1:nmcs
        for _ in 1:nsub
            clamp === :pre && setmask!(c)
            cn = similar(c)
            for x in R
                ci = c[x]
                acc = 0.0
                for d in 1:N, (side, s) in ((1, -1), (2, 1))
                    y = Tuple(x)[d] + s
                    if 1 <= y <= size(c, d)
                        v = c[CartesianIndex(Base.setindex(Tuple(x), y, d))]
                    elseif axes[d] === :periodic
                        v = c[CartesianIndex(Base.setindex(Tuple(x), mod1(y, size(c, d)), d))]
                    else
                        f = axes[d][side]
                        v = f === :noflux ? ci : 2f - ci
                    end
                    acc += v - ci
                end
                cn[x] = ci + h * (D * acc + boundary_at(src, x) - boundary_at(decay, x) * ci)
            end
            c = cn
            clamp === :post && setmask!(c)
            setnode!(c)
        end
        clamp === :end && setmask!(c)
    end
    return c
end
const NOFLUX2 = ((:noflux, :noflux), (:noflux, :noflux))
# =======================================================================================
# Model sources. A source that uses `@boundary`/`@schedule` cannot be expanded on the base,
# so every model is evaluated on first use, inside the testset that needs it.
# =======================================================================================
const SRC = Dict{Symbol, Expr}()
const DEFINED = Set{Symbol}()
function ctor(nm::Symbol)
    if !(nm in DEFINED)
        Core.eval(
            @__MODULE__, Expr(
                :macrocall, Symbol("@potts_model"), LineNumberNode(@__LINE__, Symbol(@__FILE__)),
                nm, SRC[nm]
            )
        )
        push!(DEFINED, nm)
    end
    return Base.invokelatest(getglobal, @__MODULE__, nm)
end
boundary_sys(nm::Symbol) = Base.invokelatest(ctor(nm); name = :boundary_schedule)
problem(nm::Symbol, op, tspan; kw...) = PottsProblem(boundary_sys(nm), op, tspan; kw...)
# body + extra sections (each an `Expr` of a section macro call)
boundary_body(base::Expr, extra...) = (b = copy(base); foreach(e -> push!(b.args, e), extra); b)
# --- the fields: plain MTK PDESystems coupled with `@fields` -----------------------------
# The conditions are those of the PDESystem: a face value `Dirichlet(v)` is `c(t, 0, y) ~ v` at
# the face (its ghost rule above), a zero-flux face has no condition, and a site mask is the
# masked condition `c ~ masked(mask, v)`, its 0/1 input `mask` bound to a kind test at `@fields`.
# Each builder declares its axes, field, inputs and parameters (`Potts.ModelingToolkitBase`'s
# `@parameters`, `@variables`) and returns `system(…)`.
system(eq, bcs, dims, xs, dvs, ps) = Potts.ModelingToolkitBase.PDESystem(
    [eq], bcs,
    Potts.LatticePDE.lattice_domain(Potts.t, Tuple(xs), dims), [Potts.t; xs], dvs, ps; name = :boundary_field
)
const boundary_laplacian = Potts.LatticePDE.laplacian
const boundary_masked = Potts.LatticePDE.masked
# --- 1. the 2D absorbing ring ---------------------------------------------------------------
const RING_BASE = quote
    @kinds medium border[frozen]
    @lattice Lattice((14, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 0.0 * volume
    @sweep Metropolis(; temperature = 1.0)
end
# `D(c) ~ Dc Δc + s`; `clamp`: c = cb on the border sites after every substep
function ring_pde(; clamp)
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.2 s = 0.05 cb = 0.0
    Potts.ModelingToolkitBase.@variables c(..) mask(..)::Bool [input = true]
    C, M = c(Potts.t, x, y), mask(Potts.t, x, y)
    return system(
        Potts.D(C) ~ Dc * boundary_laplacian(C) + s, [c(0, x, y) ~ 0.0; clamp ? [C ~ boundary_masked(M, cb)] : []],
        (14, 12), [x, y], clamp ? [C, M] : [C], [Dc, s, cb]
    )
end
SRC[:Ring] = boundary_body(RING_BASE, :(@fields ring_pde(; clamp = true) (:mask => kind == border)))
SRC[:RingFree] = boundary_body(RING_BASE, :(@fields ring_pde(; clamp = false)))
# control: no clamp
const RING_DIMS = (14, 12)
ring_mask() = (m = trues(RING_DIMS); m[2:(end - 1), 2:(end - 1)] .= false; m)
function ring_op(; cb = 0.0)
    ring = ring_mask()
    σ = zeros(Int32, RING_DIMS); σ[ring] .= 1
    c0 = 0.2 .+ rand(StableRNG(2), RING_DIMS...); c0[ring] .= cb
    return [ownership => σ, kind => [:border], :c => c0], c0
end
ring_oracle(c0, n, k; cb = 0.0, clamp = :post) =
    ftcs(c0, n, k; D = 0.2, src = 0.05, axes = NOFLUX2, mask = ring_mask(), val = cb, clamp)
# --- 2. a moving sink -------------------------------------------------------------------------
function sink_pde()
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.2 s = 0.05
    Potts.ModelingToolkitBase.@variables c(..) mask(..)::Bool [input = true]
    C, M = c(Potts.t, x, y), mask(Potts.t, x, y)
    return system(
        Potts.D(C) ~ Dc * boundary_laplacian(C) + s, [c(0, x, y) ~ 0.0, C ~ boundary_masked(M, 0.0)], (16, 16), [x, y],
        [C, M], [Dc, s]
    )
end
SRC[:Sink] = quote
    @kinds medium sink
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @fields sink_pde() (:mask => kind == sink)
    @parameters T = 4.0
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = T)
end
function sink_op()
    σ = zeros(Int32, 16, 16); σ[7:10, 7:10] .= 1
    c0 = fill(0.1, 16, 16); c0[σ .== 1] .= 0.0
    return [ownership => σ, kind => [:sink], :c => c0]
end
# --- 3. per face, 2D ----------------------------------------------------------------------------
const FACE2_BASE = quote
    @kinds medium A
    @lattice Lattice((16, 10); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
# `D(c) ~ Dc Δc`; `dirichlet`: x => (Dirichlet(0.0), NoFlux()), the value 0 at the low x face
# and zero flux at the high one (`false`: zero flux on both)
function face2_pde(; dirichlet = false)
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.2
    Potts.ModelingToolkitBase.@variables c(..)
    C = c(Potts.t, x, y)
    return system(
        Potts.D(C) ~ Dc * boundary_laplacian(C), [c(0, x, y) ~ 0.0; dirichlet ? [c(Potts.t, 0, y) ~ 0.0] : []],
        (16, 10), [x, y], [C], [Dc]
    )
end
SRC[:Face2] = boundary_body(FACE2_BASE, :(@fields face2_pde(; dirichlet = true)))
SRC[:Face2Free] = boundary_body(FACE2_BASE, :(@fields face2_pde()))
# control: no face condition
const FACE2_C0 = 0.5 .+ rand(StableRNG(3), 16, 10)
face2_op() = [ownership => zeros(Int32, 16, 10), kind => Symbol[], :c => copy(FACE2_C0)]
const FACE2_AXES = ((0.0, :noflux), :periodic)
# --- 4. per face + mask, 3D ---------------------------------------------------------------------
# x => (Dirichlet(1.0), Dirichlet(0.0)), y => (NoFlux(), Dirichlet(S)) and the border sites at 0
function face3_pde()
    Potts.ModelingToolkitBase.@parameters x y z Dc = 0.15 S = 2.0
    Potts.ModelingToolkitBase.@variables c(..) mask(..)::Bool [input = true]
    C, M, t = c(Potts.t, x, y, z), mask(Potts.t, x, y, z), Potts.t
    bcs = [c(0, x, y, z) ~ 0.0, c(t, 0, y, z) ~ 1.0, c(t, 7, y, z) ~ 0.0, c(t, x, 6, z) ~ S, C ~ boundary_masked(M, 0.0)]
    return system(Potts.D(C) ~ Dc * boundary_laplacian(C), bcs, (7, 6, 5), [x, y, z], [C, M], [Dc, S])
end
SRC[:Face3] = quote
    @kinds medium border[frozen]
    @lattice Lattice((7, 6, 5); boundary = (Closed(), Closed(), Periodic()), neighborhood = Moore(1))
    @fields face3_pde() (:mask => kind == border)
    @energy cells => 0.0 * volume
    @sweep Metropolis(; temperature = 1.0)
end
const FACE3_DIMS = (7, 6, 5)
block() = (m = falses(FACE3_DIMS); m[3:4, 3:4, 2:3] .= true; m)
function face3_op()
    σ = zeros(Int32, FACE3_DIMS); σ[block()] .= 1
    c0 = rand(StableRNG(4), FACE3_DIMS...); c0[block()] .= 0.0
    return [ownership => σ, kind => [:border], :c => c0], c0
end
face3_oracle(c0, n, k; S = 2.0) =
    ftcs(c0, n, k; D = 0.15, axes = ((1.0, 0.0), (:noflux, S), :periodic), mask = block(), val = 0.0)
# --- 5a/6. order: a drive gated on the field, before/after site updates -----------------------
# `D(c) ~ rate`, its input `rate` bound to the model's parameter `s` (which the drive reads too)
function order_pde()
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables c(..) rate(..) [input = true]
    C = c(Potts.t, x, y)
    return system(Potts.D(C) ~ rate(Potts.t, x, y), [c(0, x, y) ~ 0.0], (12, 12), [x, y], [C, rate(Potts.t, x, y)], Any[])
end
const ORDER_BASE = quote
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @parameters begin
        s = 1.0
        T = 1.0
    end
    @fields c = order_pde() (:rate => s)
    @variables begin
        wb(site) = -1.0
        wa(site) = -1.0
        occ(site) = -1.0
    end
    @energy cells => (volume - 16.0)^2
    @drive copy => ifelse(c[target] > 0.5 * s, 0.0, 1.0e6)
    @before_mcs wb ~ c
    @after_mcs begin
        wa ~ c
        occ ~ (kind == A)
    end
    @sweep Metropolis(; temperature = T)
end
const ORDERS = (
    none = nothing,
    sweep_fields = :(@schedule sweep, fields),
    canonical = :(@schedule before_mcs, sweep, after_mcs, fields, components, operators, lifecycle, end_mcs),
    fields_sweep = :(@schedule fields, sweep),
    fields_before = :(@schedule fields, before_mcs, sweep),
    fields_after = :(@schedule sweep, fields, after_mcs),
)
for (v, sched) in pairs(ORDERS)
    SRC[Symbol(:Order_, v)] = sched === nothing ? boundary_body(ORDER_BASE) : boundary_body(ORDER_BASE, sched)
end
function order_σ()
    σ = zeros(Int32, 12, 12); σ[5:8, 5:8] .= 1
    return σ
end
order_problem(v; T = Float64, seed = 3) =
    problem(
    Symbol(:Order_, v), [ownership => order_σ(), kind => [:A]], (0, 3);
    field_solver = ExplicitEuler(substeps = 1), T, seed
)
# expected after MCS k (k = 1, 2, 3; s = 1): (c, wb, wa); `moves0`: copies in MCS 0
const ORDER_EXPECT = (
    none = (c = k -> k, wb = k -> k - 1, wa = k -> k - 1, moves0 = false),
    sweep_fields = (c = k -> k, wb = k -> k - 1, wa = k -> k - 1, moves0 = false),
    canonical = (c = k -> k, wb = k -> k - 1, wa = k -> k - 1, moves0 = false),
    fields_sweep = (c = k -> k, wb = k -> k - 1, wa = k -> k, moves0 = true),
    fields_before = (c = k -> k, wb = k -> k, wa = k -> k, moves0 = true),
    fields_after = (c = k -> k, wb = k -> k - 1, wa = k -> k, moves0 = false),
)
# --- 6. the lifecycle as an entry -----------------------------------------------------------------
# `D(c) ~ src`, its input `src` bound to the owner's volume on the A sites
function life_pde()
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables c(..) src(..) [input = true]
    C = c(Potts.t, x, y)
    return system(Potts.D(C) ~ src(Potts.t, x, y), [c(0, x, y) ~ 0.0], (12, 12), [x, y], [C, src(Potts.t, x, y)], Any[])
end
const LIFE_BASE = quote
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @fields life_pde() (:src => ifelse(kind == A, volume[owner], 0.0))
    @energy cells => (volume - 16.0)^2
    @drive copy => 1.0e9
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 1.0)
end
SRC[:Life_none] = boundary_body(LIFE_BASE)
SRC[:Life_listed] = boundary_body(LIFE_BASE, :(@schedule sweep, fields, lifecycle))
SRC[:Life_first] = boundary_body(LIFE_BASE, :(@schedule lifecycle, fields))
life_problem(v; seed = 3) =
    problem(
    Symbol(:Life_, v), [ownership => order_σ(), kind => [:A]], (0, 2);
    field_solver = ExplicitEuler(substeps = 1), capacity = 4, seed
)
# --- 5b. Merks-shaped: per-MCS oracle from the saved states ---------------------------------------
# `D(c) ~ Dc Δc + σc [A] − δc c [medium]`, c = 0 on the border sites
function merks_pde()
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.2 σc = 0.3 δc = 0.05
    Potts.ModelingToolkitBase.@variables c(..) a(..)::Bool [input = true] med(..)::Bool [input = true] mask(..)::Bool [input = true]
    C, X, Y, M = c(Potts.t, x, y), a(Potts.t, x, y), med(Potts.t, x, y), mask(Potts.t, x, y)
    return system(
        Potts.D(C) ~ Dc * boundary_laplacian(C) + σc * X - δc * C * Y, [c(0, x, y) ~ 0.0, C ~ boundary_masked(M, 0.0)],
        (16, 16), [x, y], [C, X, Y, M], [Dc, σc, δc]
    )
end
const MERKS_BASE = quote
    @kinds medium A border[frozen]
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @fields c = merks_pde() (:a => kind == A, :med => kind == medium, :mask => kind == border)
    @parameters begin
        χ = 50.0
        T = 5.0
    end
    @energy cells(A) => (volume - 9.0)^2
    @drive copy => -χ * (c[target] - c[source])
    @sweep Metropolis(; temperature = T)
end
SRC[:Merks_fields_sweep] = boundary_body(MERKS_BASE, :(@schedule fields, sweep))
SRC[:Merks_sweep_fields] = boundary_body(MERKS_BASE, :(@schedule sweep, fields))
const MERKS_N = 3
function merks_op()
    σ = zeros(Int32, 16, 16)
    σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
    σ[4:6, 4:6] .= 2; σ[10:12, 5:7] .= 3; σ[6:8, 10:12] .= 4
    return [ownership => σ, kind => [:border, :A, :A, :A]]
end
merks_problem(v; T = Float64, seed = 11) =
    problem(
    Symbol(:Merks_, v), merks_op(), (0, 6);
    field_solver = ExplicitEuler(substeps = MERKS_N), T, seed
)
# one MCS of the field from c with the kinds of σ (cell 1 = border, cells ≥ 2 = A)
function merks_step(c, σ)
    σ = Array(σ)
    return ftcs(
        Array(c), MERKS_N, 1; D = 0.2, src = 0.3 .* (σ .>= 2), decay = 0.05 .* (σ .== 0),
        axes = NOFLUX2, mask = σ .== 1, val = 0.0
    )
end
# --- 9. one host pass: an `Adaptive` cell ODE beside the field (Metal) ---------------------------
# `D(c) ~ Dc Δc + [A]` on the periodic 16² lattice
function host_pde()
    Potts.ModelingToolkitBase.@parameters x y Dc = 0.1
    Potts.ModelingToolkitBase.@variables c(..) a(..)::Bool [input = true]
    C = c(Potts.t, x, y)
    return system(
        Potts.D(C) ~ Dc * boundary_laplacian(C) + a(Potts.t, x, y), [c(0, x, y) ~ 0.0], (16, 16), [x, y],
        [C, a(Potts.t, x, y)], [Dc]
    )
end
const HOST_BASE = quote
    @kinds medium A
    @parameters k = 0.3
    @variables y(cell) = 1.0
    @lattice Lattice((16, 16))
    @fields host_pde() (:a => kind == A)
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -k * y
    @sweep Metropolis(; temperature = 1.0)
end
SRC[:Host_none] = boundary_body(HOST_BASE)
SRC[:Host_fields_sweep] = boundary_body(HOST_BASE, :(@schedule fields, sweep))
SRC[:Host_components_sweep] = boundary_body(HOST_BASE, :(@schedule components, sweep))
function host_problem(v; T = Float32)
    σ = zeros(Int32, 16, 16); σ[3:6, 3:6] .= 1; σ[10:13, 10:13] .= 2
    return problem(
        Symbol(:Host_, v), [ownership => σ, kind => [:A, :A]], (0, 10);
        T, capacity = 8, seed = 3, field_solver = ExplicitEuler(substeps = 2),
        ode_solver = Adaptive(Rodas5P(); reltol = 1.0e-8, abstol = 1.0e-10)
    )
end
# =======================================================================================
# helpers
# =======================================================================================
const ALGS = (SequentialCPM(), CheckerboardCPM())
same(u, v) = Array(u.ownership) == Array(v.ownership) && u.site == v.site && u.cell == v.cell && u.model == v.model
boundary_c(u) = Float64.(Array(u.site.c))
mass(u) = sum(boundary_c(u))
# the exception a model source raises (at expansion, construction or `PottsProblem`), or nothing
function boundary_error(f)
    try
        f()
        return nothing
    catch e
        while e isa LoadError
            e = e.error
        end
        return e
    end
end
message(e) = e === nothing ? "" : sprint(showerror, e)
const BAD = Ref(0)
function bad(body::Expr, op, tspan; kw...)
    nm = Symbol(:Bad_, BAD[] += 1)
    SRC[nm] = body
    return boundary_error(() -> problem(nm, op, tspan; kw...))
end
# =======================================================================================
# Controls on the base: the oracle reproduces a hand-written explicit Euler step with the
# per-face ghost rule (since the field-compiler cutover, C8, CorePotts has no field step of
# its own: the field-compiler switch)
# =======================================================================================
# the 5-point Laplacian (h = 1) at site i: a missing neighbor across a face is the ghost
# 2v − c_i for `Dirichlet(v)` (`bc[axis][side] = v`), else c_i (zero flux)
function hand_lap(c, lat, i, bc)
    x = CorePotts.coordinates(lat, i)
    N = length(x)
    acc = 0.0
    for d in 1:N, (s, side) in ((-1, 1), (1, 2))
        inside, y = CorePotts.shift(lat, x, ntuple(k -> Int32(k == d ? s : 0), N))
        v = bc === nothing ? nothing : bc[d][side]
        acc += (inside ? c[CorePotts.linear_index(lat, y)] : v === nothing ? c[i] : 2 * v - c[i]) - c[i]
    end
    return acc
end
# one explicit Euler substep of length h into the scratch `c__next`
struct HandRate{B}
    D::Float64
    src::Float64
    bc::B
    h::Float64
end
(r::HandRate)(st, p, ctx, key, mcs, i) =
    (c = st.site.c; st.site.c__next[i] = c[i] + r.h * (r.D * hand_lap(c, ctx.lattice, i, r.bc) + r.src); nothing)
hand_substep(r) = (CorePotts.SitePhase(r), CorePotts.CopyPhase((:site, :c) => (:site, :c__next)))
struct HandClamp
    sites::Vector{Int}
end
(k::HandClamp)(st, p, ctx, key, mcs, backend) = (st.site.c[k.sites] .= 0.0; 0)
function with_phases(prob, phases)
    f = prob.f
    g = CPMFunction(
        f.delta_H; f.commit!, f.constraint, f.temperature, f.bias, phases,
        f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys
    )
    return remake(prob; f = g)
end
# =======================================================================================
# 7. errors
# =======================================================================================
# the error fixtures: a face condition on the periodic axis `y`; a field on
# (t, x, y, z) with a zero-flux condition on its low `z` face, coupled to the 2D lattice (the
# lattice has no axis `z`); and a masked condition on `wbin`, an input that reads the site
# variable `wb`, a condition that sets no field
function face2_bad(which)
    Potts.ModelingToolkitBase.@parameters x y z Dc = 0.2
    Potts.ModelingToolkitBase.@variables c(..)
    if which === :periodic
        C = c(Potts.t, x, y)
        return system(Potts.D(C) ~ Dc * boundary_laplacian(C), [c(0, x, y) ~ 0.0, c(Potts.t, x, 0) ~ 0.0], (16, 10), [x, y], [C], [Dc])
    end
    C = c(Potts.t, x, y, z)
    zface = Potts.ModelingToolkitBase.Differential(z)(c(Potts.t, x, y, 0)) ~ 0.0
    return system(Potts.D(C) ~ Dc * boundary_laplacian(C), [c(0, x, y, z) ~ 0.0, zface], (16, 10, 4), [x, y, z], [C], [Dc])
end
function wb_bad()
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables w(..) wbin(..) [input = true, lattice_input_name = "wb"] a(..)::Bool [input = true]
    W = w(Potts.t, x, y)
    return system(
        Potts.D(W) ~ 0.0, [w(0, x, y) ~ 0.0, wbin(Potts.t, x, y) ~ boundary_masked(a(Potts.t, x, y), 0.0)],
        (12, 12), [x, y], [W, wbin(Potts.t, x, y), a(Potts.t, x, y)], Any[]
    )
end
# =======================================================================================
# 9. Metal
# =======================================================================================
const ON_DEVICE = PottsDevices.on_device()
function metal_counts(prob; nwarm = 1, n = 3)
    integ = init(prob, CheckerboardCPM(); backend = PottsDevices.device_backend(), save_start = false, save_everystep = false, save_end = false)
    foreach(_ -> step!(integ), 1:nwarm)
    out = NTuple{3, Int}[]
    for _ in 1:n
        c0 = (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes)
        step!(integ)
        push!(out, (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes) .- c0)
    end
    return out
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "boundary schedule control: the oracle is CorePotts' explicit Euler, per-face rule and clamp (base)" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary schedule control: the oracle is CorePotts' explicit Euler, per-face rule and clamp (base)" begin
        # per-face ghost values through the hand step
        prob = problem(:Face2Free, face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
        hand = CorePotts.Phases(;
            after_mcs = Tuple(
                Iterators.flatten(
                    hand_substep(HandRate(0.2, 0.0, ((0.0, nothing), (nothing, nothing)), 1.0 / 3)) for _ in 1:3
                )
            )
        )
        u = solve(with_phases(prob, hand), SequentialCPM()).u[end]
        @test maximum(abs, boundary_c(u) .- ftcs(FACE2_C0, 3, 2; D = 0.2, axes = FACE2_AXES)) < 1.0e-12
        # the ring clamp after every substep, as n single-substep steps each followed by a clamp
        op, c0 = ring_op()
        n = 4
        prob = problem(:RingFree, op, (0, 3); field_solver = ExplicitEuler(substeps = n), seed = 1)
        ring = findall(vec(ring_mask()))
        one = hand_substep(HandRate(0.2, 0.05, nothing, 1.0 / n))
        hand = CorePotts.Phases(; after_mcs = Tuple(Iterators.flatten((one..., HandClamp(ring)) for _ in 1:n)))
        sol = solve(with_phases(prob, hand), SequentialCPM(); saveat = 1)
        for k in 1:3
            @test maximum(abs, boundary_c(sol.u[k + 1]) .- ring_oracle(c0, n, k)) < 1.0e-12
        end
    end
end

@testitem "boundary schedule control: an unlisted closed face is zero flux (base)" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary schedule control: an unlisted closed face is zero flux (base)" begin
        for alg in ALGS
            prob = problem(:Face2Free, face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
            sol = solve(prob, alg; saveat = 1)
            @test maximum(abs, boundary_c(sol.u[end]) .- ftcs(FACE2_C0, 3, 2; D = 0.2, axes = ((:noflux, :noflux), :periodic))) < 1.0e-12
            @test all(u -> abs(mass(u) - sum(FACE2_C0)) < 1.0e-10, sol.u)
        end
    end
end

@testitem "boundary schedule: the absorbing frame keeps c = 0 on the ring after every substep" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # 1. the absorbing ring, every substep
    # =======================================================================================
    @testset "boundary schedule: the absorbing frame keeps c = 0 on the ring after every substep ($(nameof(typeof(alg))))" for alg in ALGS
        # negative controls on the oracle: the test can tell a per-MCS or a pre-substep clamp apart
        _, c0 = ring_op()
        @test maximum(abs, ring_oracle(c0, 4, 1; clamp = :end) .- ring_oracle(c0, 4, 1)) > 1.0e-2
        @test maximum(abs, ring_oracle(c0, 4, 1; clamp = :pre)[ring_mask()]) > 1.0e-2
        for n in (1, 4)
            op, c0 = ring_op()
            prob = problem(:Ring, op, (0, 3); field_solver = ExplicitEuler(substeps = n), seed = 1)
            sol = solve(prob, alg; saveat = 1)
            ring = ring_mask()
            for k in 1:3
                c = boundary_c(sol.u[k + 1])
                @test all(==(0.0), c[ring])                                             # exactly
                @test maximum(abs, c .- ring_oracle(c0, n, k)) < 1.0e-12             # every substep
            end
            @test Array(sol.u[end].ownership) == op[1].second                                  # the frame is frozen
        end
        # a parameter value: remake keeps the generated code, and the clamp follows it
        op, c0 = ring_op(; cb = 0.5)
        prob = problem(:Ring, op, (0, 2); field_solver = ExplicitEuler(substeps = 4), seed = 1)
        p2 = remake(prob; p = [:cb => 0.5])
        @test p2.f === prob.f
        c = boundary_c(solve(p2, alg).u[end])
        @test all(==(0.5), c[ring_mask()])
        @test maximum(abs, c .- ring_oracle(c0, 4, 2; cb = 0.5)) < 1.0e-12
    end
end

@testitem "boundary schedule: a kind mask is re-evaluated from σ" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # 2. the mask moves with the cells
    # =======================================================================================
    @testset "boundary schedule: a kind mask is re-evaluated from σ ($(nameof(typeof(alg))))" for alg in ALGS
        op = sink_op()
        prob = problem(:Sink, op, (0, 10); field_solver = ExplicitEuler(substeps = 2), seed = 5)
        sol = solve(prob, alg; saveat = 1)
        for u in sol.u[2:end]
            σ, c = Array(u.ownership), boundary_c(u)
            @test all(==(0.0), c[σ .== 1])
            @test all(>(0.0), c[σ .== 0])
        end
        @test any(u -> Array(u.ownership) != op[1].second, sol.u)                              # control: the sink moved
    end
end

@testitem "boundary schedule: per-face conditions, 2D Closed × Periodic" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # 3–4. per face, 2D and 3D
    # =======================================================================================
    @testset "boundary schedule: per-face conditions, 2D Closed × Periodic ($(nameof(typeof(alg))))" for alg in ALGS
        o = ftcs(FACE2_C0, 3, 2; D = 0.2, axes = FACE2_AXES)
        # negative controls on the oracle: the face condition matters, and it is a ghost value
        @test maximum(abs, o .- ftcs(FACE2_C0, 3, 2; D = 0.2, axes = ((:noflux, :noflux), :periodic))) > 1.0e-2
        @test maximum(
            abs, o .- ftcs(
                FACE2_C0, 3, 2; D = 0.2, axes = ((:noflux, :noflux), :periodic),
                node = (1, 1, 0.0)
            )
        ) > 1.0e-2
        prob = problem(:Face2, face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
        sol = solve(prob, alg; saveat = 1)
        @test maximum(abs, boundary_c(sol.u[end]) .- o) < 1.0e-12
        @test mass(sol.u[2]) < sum(FACE2_C0) - 1.0e-3 && mass(sol.u[3]) < mass(sol.u[2]) - 1.0e-3
        free = problem(:Face2Free, face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
        @test prob.f.fingerprint != free.f.fingerprint
    end
end

@testitem "boundary schedule: per-face conditions and a mask, 3D" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary schedule: per-face conditions and a mask, 3D ($(nameof(typeof(alg))))" for alg in ALGS
        op, c0 = face3_op()
        prob = problem(:Face3, op, (0, 2); field_solver = ExplicitEuler(substeps = 4), seed = 1)
        sol = solve(prob, alg; saveat = 1)
        for k in 1:2
            c = boundary_c(sol.u[k + 1])
            @test all(==(0.0), c[block()])
            @test maximum(abs, c .- face3_oracle(c0, 4, k)) < 1.0e-12
        end
        # each face condition matters (negative controls on the oracle)
        o = face3_oracle(c0, 4, 2)
        @test maximum(
            abs, o .- ftcs(
                c0, 4, 2; D = 0.15, axes = ((:noflux, 0.0), (:noflux, 2.0), :periodic),
                mask = block()
            )
        ) > 1.0e-2
        @test maximum(abs, o .- face3_oracle(c0, 4, 2; S = 0.5)) > 1.0e-2
        p2 = remake(prob; p = [:S => 0.5])
        @test p2.f === prob.f
        @test maximum(abs, boundary_c(solve(p2, alg).u[end]) .- face3_oracle(c0, 4, 2; S = 0.5)) < 1.0e-12
    end
end

@testitem "boundary schedule: the phase order is observable, drive gated on the field" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # 5. PDE before vs after the sweep
    # =======================================================================================
    @testset "boundary schedule: the phase order is observable, drive gated on the field ($(nameof(typeof(alg))))" for alg in ALGS
        sols = Dict(v => solve(order_problem(v), alg; saveat = 1) for v in keys(ORDERS))
        σ0 = order_σ()
        for v in keys(ORDERS)
            sol, ex = sols[v], ORDER_EXPECT[v]
            for k in 1:3
                u = sol.u[k + 1]
                @test all(==(Float64(ex.c(k))), Array(u.site.c))
                @test all(==(Float64(ex.wb(k))), Array(u.site.wb))
                @test all(==(Float64(ex.wa(k))), Array(u.site.wa))
            end
            # after_mcs follows the sweep in every order (listed or not)
            @test all(u -> Array(u.site.occ) == Float64.(Array(u.ownership) .== 1), sol.u[2:end])
            @test (Array(sol.u[2].ownership) != σ0) == ex.moves0
        end
        # negative control: swapping `fields` and `sweep` changes the trajectory
        @test Array(sols[:fields_sweep].u[2].ownership) != Array(sols[:sweep_fields].u[2].ownership)
        # listing the default relative order is no schedule, bit for bit
        for v in (:sweep_fields, :canonical)
            @test all(i -> same(sols[v].u[i], sols[:none].u[i]), eachindex(sols[:none].u))
        end
    end
end

@testitem "boundary schedule: PDE-before-sweep vs sweep-before-PDE, Merks-shaped oracle" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary schedule: PDE-before-sweep vs sweep-before-PDE, Merks-shaped oracle ($(nameof(typeof(alg))))" for alg in ALGS
        fs = solve(merks_problem(:fields_sweep), alg; saveat = 1)
        sf = solve(merks_problem(:sweep_fields), alg; saveat = 1)
        ring = merks_op()[1].second .== 1
        for (sol, fieldsfirst) in ((fs, true), (sf, false))
            right = wrong = 0.0
            for k in 1:6
                u, u′ = sol.u[k], sol.u[k + 1]
                @test all(==(0.0), boundary_c(u′)[ring])
                # fields first: the field step of MCS k sees σ(k); sweep first: it sees σ(k + 1)
                a = merks_step(boundary_c(u), fieldsfirst ? u.ownership : u′.ownership)
                b = merks_step(boundary_c(u), fieldsfirst ? u′.ownership : u.ownership)
                right = max(right, maximum(abs, boundary_c(u′) .- a))
                wrong = max(wrong, maximum(abs, boundary_c(u′) .- b))
            end
            @test right < 1.0e-12
            @test wrong > 1.0e-3                          # negative control: the other order's oracle fails
        end
        @test any(k -> Array(fs.u[k].ownership) != Array(fs.u[k + 1].ownership), 1:6)                   # control: cells moved
    end
end

@testitem "boundary schedule: the lifecycle is a schedule entry" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # 6. the lifecycle is an entry of the order
    # =======================================================================================
    @testset "boundary schedule: the lifecycle is a schedule entry ($(nameof(typeof(alg))))" for alg in ALGS
        none = solve(life_problem(:none), alg; saveat = 1)
        listed = solve(life_problem(:listed), alg; saveat = 1)
        lifefirst = solve(life_problem(:first), alg; saveat = 1)
        @test all(i -> same(listed.u[i], none.u[i]), eachindex(none.u))
        for (sol, after) in ((none, false), (lifefirst, true))
            u = sol.u[2]
            σ, c, vol = Array(u.ownership), boundary_c(u), Array(u.cell.volume)
            @test count(>(0), vol) == 2                                                 # control: it divided
            @test all(i -> c[i] == (σ[i] == 0 ? 0.0 : after ? Float64(vol[σ[i]]) : 16.0), eachindex(σ))
        end
    end
end

@testitem "boundary schedule: @boundary and @schedule errors name the offender" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary schedule: @boundary and @schedule errors name the offender" begin
        face = (face2_op(), (0, 1))
        fkw = (; field_solver = ExplicitEuler(substeps = 1))
        e = bad(boundary_body(FACE2_BASE, :(@fields face2_bad(:periodic))), face...; fkw...)
        @test e !== nothing && occursin("periodic", lowercase(message(e)))
        e = bad(boundary_body(FACE2_BASE, :(@fields face2_bad(:z))), face...; fkw...)
        @test e !== nothing && occursin(r"\bz\b", message(e)) && occursin("the lattice of `boundary_schedule` has 2 axes", message(e))
        order = ([ownership => order_σ(), kind => [:A]], (0, 1))
        e = bad(boundary_body(ORDER_BASE, :(@fields wb_bad() (:a => kind == A))), order...; fkw...)
        @test e !== nothing && occursin(r"\bwb\b", message(e))
        for (sched, name) in (
                (:(@schedule feilds, sweep), "feilds"), (:(@schedule sweep, fields, sweep), "sweep"),
                (:(@schedule end_mcs, sweep), "end_mcs"), (:(@schedule after_mcs, sweep), "after_mcs"),
                (:(@schedule sweep, before_mcs), "before_mcs")
            )
            e = bad(boundary_body(ORDER_BASE, sched), order...; fkw...)
            @test e !== nothing && occursin(name, message(e))
        end
        # controls: the same sources with valid entries build
        @test problem(:Face2, face...; fkw...) isa PottsProblem
        @test order_problem(:fields_sweep) isa PottsProblem
        @test !(:Dirichlet in keys(Potts.DSL)) && !(:NoFlux in keys(Potts.DSL))     # removed with `@boundary`
    end
end

@testitem "boundary schedule: the schedule is hashed; checkpoints do not cross orders" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # 8. fingerprints and checkpoints
    # =======================================================================================
    @testset "boundary schedule: the schedule is hashed; checkpoints do not cross orders" begin
        a, b = order_problem(:none), order_problem(:fields_sweep)
        @test a.f.fingerprint != b.f.fingerprint
        integ = init(a, SequentialCPM())
        step!(integ)
        ck = checkpoint(integ)
        @test_throws ArgumentError init(b, SequentialCPM(); checkpoint = ck)
        @test init(a, SequentialCPM(); checkpoint = ck) isa CorePotts.PottsIntegrator     # control
    end
end

@testitem "boundary schedule: boundaries and the schedule on the device (CheckerboardCPM, Float32)" setup = [BoundaryScheduleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boundary schedule: boundaries and the schedule on the device (CheckerboardCPM, Float32)" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            # ring, every substep
            op, c0 = ring_op()
            sol = solve(
                problem(:Ring, op, (0, 3); T = Float32, field_solver = ExplicitEuler(substeps = 4), seed = 1),
                alg; backend, saveat = 1
            )
            for k in 1:3
                c = boundary_c(sol.u[k + 1])
                @test all(==(0.0), c[ring_mask()])
                @test maximum(abs, c .- ring_oracle(c0, 4, k)) < 1.0e-5
            end
            # per face, 2D and 3D
            sol = solve(
                problem(
                    :Face2, face2_op(), (0, 2); T = Float32, field_solver = ExplicitEuler(substeps = 3),
                    seed = 1
                ), alg; backend
            )
            @test maximum(abs, boundary_c(sol.u[end]) .- ftcs(FACE2_C0, 3, 2; D = 0.2, axes = FACE2_AXES)) < 1.0e-5
            op, c0 = face3_op()
            sol = solve(
                problem(:Face3, op, (0, 2); T = Float32, field_solver = ExplicitEuler(substeps = 4), seed = 1),
                alg; backend
            )
            @test all(==(0.0), boundary_c(sol.u[end])[block()])
            @test maximum(abs, boundary_c(sol.u[end]) .- face3_oracle(c0, 4, 2)) < 1.0e-5
            # the moving mask
            sol = solve(
                problem(
                    :Sink, sink_op(), (0, 10); T = Float32, field_solver = ExplicitEuler(substeps = 2),
                    seed = 5
                ), alg; backend, saveat = 1
            )
            @test all(u -> all(==(0.0), boundary_c(u)[Array(u.ownership) .== 1]) && all(>(0.0), boundary_c(u)[Array(u.ownership) .== 0]), sol.u[2:end])
            # the order: gated drive and the Merks-shaped oracle
            for v in (:sweep_fields, :fields_sweep)
                sol = solve(order_problem(v; T = Float32), alg; backend, saveat = 1)
                ex = ORDER_EXPECT[v]
                @test (Array(sol.u[2].ownership) != order_σ()) == ex.moves0
                @test all(k -> all(==(Float32(ex.wa(k))), Array(sol.u[k + 1].site.wa)), 1:3)
            end
            for (v, fieldsfirst) in ((:fields_sweep, true), (:sweep_fields, false))
                sol = solve(merks_problem(v; T = Float32), alg; backend, saveat = 1)
                right = wrong = 0.0
                for k in 1:6
                    u, u′ = sol.u[k], sol.u[k + 1]
                    right = max(right, maximum(abs, boundary_c(u′) .- merks_step(boundary_c(u), fieldsfirst ? u.ownership : u′.ownership)))
                    wrong = max(wrong, maximum(abs, boundary_c(u′) .- merks_step(boundary_c(u), fieldsfirst ? u′.ownership : u.ownership)))
                end
                @test right < 1.0e-4
                @test wrong > 1.0e-3
            end
            # D-035 as amended: no host pass, no traffic, whatever the order
            for prob in (
                    merks_problem(:fields_sweep; T = Float32), merks_problem(:sweep_fields; T = Float32),
                    order_problem(:fields_sweep; T = Float32),
                )
                @test all(==((0, 0, 0)), metal_counts(prob))
            end
            # one host pass (an Adaptive cell ODE): the same round trip under every order, one sync per MCS
            counts = Dict(v => metal_counts(host_problem(v)) for v in (:none, :fields_sweep, :components_sweep))
            @test all(c -> all(==(1), first.(c)), values(counts))
            @test counts[:fields_sweep] == counts[:none] && counts[:components_sweep] == counts[:none]
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end
