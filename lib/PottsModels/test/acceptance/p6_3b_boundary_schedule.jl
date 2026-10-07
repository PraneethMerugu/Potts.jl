# P6.3b (ROADMAP Phase 6, step 3; api-synthesis §2.11, §2.12, §6.1 (D-035 row), §6.4; R5):
# `@boundary` per face and per site mask (a masked clamp applied after EVERY explicit field
# substep), field phase placement and an explicit phase order. The phase order IS `@schedule`,
# with the `step!` restructuring of api-synthesis §2.12 (the sweep and the lifecycle become
# entries of the phase order). D-035 is amended as D-075 states, in the same change.
# Decision: D-145. Frozen (AUTONOMY §7.3).
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
#         before the MCS), so u[k+1].c equals the explicit-Euler oracle on (u[k].c, u[k].σ);
#         with `sweep, fields` it equals the oracle on (u[k].c, u[k+1].σ). Each order FAILS the
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
p63b_at(a, x) = a isa AbstractArray ? a[x] : a

function p63b_ftcs(c0, nsub, nmcs; D, src = 0.0, decay = 0.0, axes, mask = nothing, val = 0.0,
        clamp = :post, node = nothing)
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
                cn[x] = ci + h * (D * acc + p63b_at(src, x) - p63b_at(decay, x) * ci)
            end
            c = cn
            clamp === :post && setmask!(c)
            setnode!(c)
        end
        clamp === :end && setmask!(c)
    end
    return c
end

const P63B_NOFLUX2 = ((:noflux, :noflux), (:noflux, :noflux))

# =======================================================================================
# Model sources. A source that uses `@boundary`/`@schedule` cannot be expanded on the base,
# so every model is evaluated on first use, inside the testset that needs it.
# =======================================================================================
const P63B_SRC = Dict{Symbol, Expr}()
const P63B_DEFINED = Set{Symbol}()

function p63b_ctor(nm::Symbol)
    if !(nm in P63B_DEFINED)
        Core.eval(@__MODULE__, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(@__LINE__, Symbol(@__FILE__)),
            nm, P63B_SRC[nm]))
        push!(P63B_DEFINED, nm)
    end
    return Base.invokelatest(getglobal, @__MODULE__, nm)
end
p63b_sys(nm::Symbol) = Base.invokelatest(p63b_ctor(nm); name = :p63b)
p63b_problem(nm::Symbol, op, tspan; kw...) = PottsProblem(p63b_sys(nm), op, tspan; kw...)

# body + extra sections (each an `Expr` of a section macro call)
p63b_body(base::Expr, extra...) = (b = copy(base); foreach(e -> push!(b.args, e), extra); b)

# --- 1. the 2D absorbing ring ---------------------------------------------------------------
const P63B_RING_BASE = quote
    @kinds medium border[frozen]
    @parameters begin
        Dc = 0.2
        s = 0.05
        cb = 0.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((14, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 0.0 * volume
    @equations D(c) ~ Dc * Δ(c) + s
    @sweep Metropolis(; temperature = 1.0)
end
P63B_SRC[:P63bRing] = p63b_body(P63B_RING_BASE, :(@boundary c begin
    sites(kind == border) => Dirichlet(cb)
end))
P63B_SRC[:P63bRingFree] = p63b_body(P63B_RING_BASE)        # control: no @boundary

const P63B_RING_DIMS = (14, 12)
p63b_ring_mask() = (m = trues(P63B_RING_DIMS); m[2:(end - 1), 2:(end - 1)] .= false; m)
function p63b_ring_op(; cb = 0.0)
    ring = p63b_ring_mask()
    σ = zeros(Int32, P63B_RING_DIMS); σ[ring] .= 1
    c0 = 0.2 .+ rand(StableRNG(2), P63B_RING_DIMS...); c0[ring] .= cb
    return [ownership => σ, kind => [:border], :c => c0], c0
end
p63b_ring_oracle(c0, n, k; cb = 0.0, clamp = :post) =
    p63b_ftcs(c0, n, k; D = 0.2, src = 0.05, axes = P63B_NOFLUX2, mask = p63b_ring_mask(), val = cb, clamp)

# --- 2. a moving sink -------------------------------------------------------------------------
P63B_SRC[:P63bSink] = quote
    @kinds medium sink
    @parameters begin
        Dc = 0.2
        s = 0.05
        T = 4.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) + s
    @boundary c begin
        sites(kind == sink) => Dirichlet(0.0)
    end
    @sweep Metropolis(; temperature = T)
end
function p63b_sink_op()
    σ = zeros(Int32, 16, 16); σ[7:10, 7:10] .= 1
    c0 = fill(0.1, 16, 16); c0[σ .== 1] .= 0.0
    return [ownership => σ, kind => [:sink], :c => c0]
end

# --- 3. per face, 2D ----------------------------------------------------------------------------
const P63B_FACE2_BASE = quote
    @kinds medium A
    @parameters Dc = 0.2
    @variables c(field) = 0.0
    @lattice Lattice((16, 10); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end
P63B_SRC[:P63bFace2] = p63b_body(P63B_FACE2_BASE, :(@boundary c begin
    x => (Dirichlet(0.0), NoFlux())
end))
P63B_SRC[:P63bFace2Free] = p63b_body(P63B_FACE2_BASE)      # control: no @boundary
const P63B_FACE2_C0 = 0.5 .+ rand(StableRNG(3), 16, 10)
p63b_face2_op() = [ownership => zeros(Int32, 16, 10), kind => Symbol[], :c => copy(P63B_FACE2_C0)]
const P63B_FACE2_AXES = ((0.0, :noflux), :periodic)

# --- 4. per face + mask, 3D ---------------------------------------------------------------------
P63B_SRC[:P63bFace3] = quote
    @kinds medium border[frozen]
    @parameters begin
        Dc = 0.15
        S = 2.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((7, 6, 5); boundary = (Closed(), Closed(), Periodic()), neighborhood = Moore(1))
    @energy cells => 0.0 * volume
    @equations D(c) ~ Dc * Δ(c)
    @boundary c begin
        x => (Dirichlet(1.0), Dirichlet(0.0))
        y => (NoFlux(), Dirichlet(S))
        sites(kind == border) => Dirichlet(0.0)
    end
    @sweep Metropolis(; temperature = 1.0)
end
const P63B_FACE3_DIMS = (7, 6, 5)
p63b_block() = (m = falses(P63B_FACE3_DIMS); m[3:4, 3:4, 2:3] .= true; m)
function p63b_face3_op()
    σ = zeros(Int32, P63B_FACE3_DIMS); σ[p63b_block()] .= 1
    c0 = rand(StableRNG(4), P63B_FACE3_DIMS...); c0[p63b_block()] .= 0.0
    return [ownership => σ, kind => [:border], :c => c0], c0
end
p63b_face3_oracle(c0, n, k; S = 2.0) =
    p63b_ftcs(c0, n, k; D = 0.15, axes = ((1.0, 0.0), (:noflux, S), :periodic), mask = p63b_block(), val = 0.0)

# --- 5a/6. order: a drive gated on the field, before/after site updates -----------------------
const P63B_ORDER_BASE = quote
    @kinds medium A
    @parameters begin
        s = 1.0
        T = 1.0
    end
    @variables begin
        c(field) = 0.0
        wb(site) = -1.0
        wa(site) = -1.0
        occ(site) = -1.0
    end
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @drive copy => ifelse(c[target] > 0.5 * s, 0.0, 1.0e6)
    @before_mcs wb ~ c
    @after_mcs begin
        wa ~ c
        occ ~ (kind == A)
    end
    @equations D(c) ~ s
    @sweep Metropolis(; temperature = T)
end
const P63B_ORDERS = (
    none = nothing,
    sweep_fields = :(@schedule sweep, fields),
    canonical = :(@schedule before_mcs, sweep, after_mcs, fields, components, operators, lifecycle, end_mcs),
    fields_sweep = :(@schedule fields, sweep),
    fields_before = :(@schedule fields, before_mcs, sweep),
    fields_after = :(@schedule sweep, fields, after_mcs),
)
for (v, sched) in pairs(P63B_ORDERS)
    P63B_SRC[Symbol(:P63bOrder_, v)] = sched === nothing ? p63b_body(P63B_ORDER_BASE) : p63b_body(P63B_ORDER_BASE, sched)
end
function p63b_order_σ()
    σ = zeros(Int32, 12, 12); σ[5:8, 5:8] .= 1
    return σ
end
p63b_order_problem(v; T = Float64, seed = 3) =
    p63b_problem(Symbol(:P63bOrder_, v), [ownership => p63b_order_σ(), kind => [:A]], (0, 3);
        field_solver = ExplicitEuler(substeps = 1), T, seed)
# expected after MCS k (k = 1, 2, 3; s = 1): (c, wb, wa); `moves0`: copies in MCS 0
const P63B_ORDER_EXPECT = (
    none = (c = k -> k, wb = k -> k - 1, wa = k -> k - 1, moves0 = false),
    sweep_fields = (c = k -> k, wb = k -> k - 1, wa = k -> k - 1, moves0 = false),
    canonical = (c = k -> k, wb = k -> k - 1, wa = k -> k - 1, moves0 = false),
    fields_sweep = (c = k -> k, wb = k -> k - 1, wa = k -> k, moves0 = true),
    fields_before = (c = k -> k, wb = k -> k, wa = k -> k, moves0 = true),
    fields_after = (c = k -> k, wb = k -> k - 1, wa = k -> k, moves0 = false),
)

# --- 6. the lifecycle as an entry -----------------------------------------------------------------
const P63B_LIFE_BASE = quote
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @drive copy => 1.0e9
    @equations D(c) ~ ifelse(kind == A, volume[owner], 0.0)
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 1.0)
end
P63B_SRC[:P63bLife_none] = p63b_body(P63B_LIFE_BASE)
P63B_SRC[:P63bLife_listed] = p63b_body(P63B_LIFE_BASE, :(@schedule sweep, fields, lifecycle))
P63B_SRC[:P63bLife_first] = p63b_body(P63B_LIFE_BASE, :(@schedule lifecycle, fields))
p63b_life_problem(v; seed = 3) =
    p63b_problem(Symbol(:P63bLife_, v), [ownership => p63b_order_σ(), kind => [:A]], (0, 2);
        field_solver = ExplicitEuler(substeps = 1), capacity = 4, seed)

# --- 5b. Merks-shaped: per-MCS oracle from the saved states ---------------------------------------
const P63B_MERKS_BASE = quote
    @kinds medium A border[frozen]
    @parameters begin
        Dc = 0.2
        σc = 0.3
        δc = 0.05
        χ = 50.0
        T = 5.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy cells(A) => (volume - 9.0)^2
    @drive copy => -χ * (c[target] - c[source])
    @equations D(c) ~ Dc * Δ(c) + σc * (kind == A) - δc * c * (kind == medium)
    @boundary c begin
        sites(kind == border) => Dirichlet(0.0)
    end
    @sweep Metropolis(; temperature = T)
end
P63B_SRC[:P63bMerks_fields_sweep] = p63b_body(P63B_MERKS_BASE, :(@schedule fields, sweep))
P63B_SRC[:P63bMerks_sweep_fields] = p63b_body(P63B_MERKS_BASE, :(@schedule sweep, fields))
const P63B_MERKS_N = 3
function p63b_merks_op()
    σ = zeros(Int32, 16, 16)
    σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
    σ[4:6, 4:6] .= 2; σ[10:12, 5:7] .= 3; σ[6:8, 10:12] .= 4
    return [ownership => σ, kind => [:border, :A, :A, :A]]
end
p63b_merks_problem(v; T = Float64, seed = 11) =
    p63b_problem(Symbol(:P63bMerks_, v), p63b_merks_op(), (0, 6);
        field_solver = ExplicitEuler(substeps = P63B_MERKS_N), T, seed)
# one MCS of the field from c with the kinds of σ (cell 1 = border, cells ≥ 2 = A)
function p63b_merks_step(c, σ)
    σ = Array(σ)
    return p63b_ftcs(Array(c), P63B_MERKS_N, 1; D = 0.2, src = 0.3 .* (σ .>= 2), decay = 0.05 .* (σ .== 0),
        axes = P63B_NOFLUX2, mask = σ .== 1, val = 0.0)
end

# --- 9. one host pass: an `Adaptive` cell ODE beside the field (Metal) ---------------------------
const P63B_HOST_BASE = quote
    @kinds medium A
    @parameters begin
        k = 0.3
        Dc = 0.1
    end
    @variables begin
        y(cell) = 1.0
        c(field) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * y
        D(c) ~ Dc * Δ(c) + (kind == A)
    end
    @sweep Metropolis(; temperature = 1.0)
end
P63B_SRC[:P63bHost_none] = p63b_body(P63B_HOST_BASE)
P63B_SRC[:P63bHost_fields_sweep] = p63b_body(P63B_HOST_BASE, :(@schedule fields, sweep))
P63B_SRC[:P63bHost_components_sweep] = p63b_body(P63B_HOST_BASE, :(@schedule components, sweep))
function p63b_host_problem(v; T = Float32)
    σ = zeros(Int32, 16, 16); σ[3:6, 3:6] .= 1; σ[10:13, 10:13] .= 2
    return p63b_problem(Symbol(:P63bHost_, v), [ownership => σ, kind => [:A, :A]], (0, 10);
        T, capacity = 8, seed = 3, field_solver = ExplicitEuler(substeps = 2),
        ode_solver = Adaptive(Rodas5P(); reltol = 1e-8, abstol = 1e-10))
end

# =======================================================================================
# helpers
# =======================================================================================
const P63B_ALGS = (SequentialCPM(), CheckerboardCPM())
p63b_same(u, v) = Array(u.σ) == Array(v.σ) && u.site == v.site && u.cell == v.cell && u.model == v.model
p63b_c(u) = Float64.(Array(u.site.c))
p63b_mass(u) = sum(p63b_c(u))

# the exception a model source raises (at expansion, construction or `PottsProblem`), or nothing
function p63b_error(f)
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
p63b_message(e) = e === nothing ? "" : sprint(showerror, e)
const P63B_BAD = Ref(0)
function p63b_bad(body::Expr, op, tspan; kw...)
    nm = Symbol(:P63bBad_, P63B_BAD[] += 1)
    P63B_SRC[nm] = body
    return p63b_error(() -> p63b_problem(nm, op, tspan; kw...))
end

# =======================================================================================
# Controls on the base: the oracle reproduces CorePotts' own field step and per-face rule
# =======================================================================================
struct P63bHandRate{B}
    D::Float64
    src::Float64
    bc::B
end
(r::P63bHandRate)(st, p, ctx, key, mcs, i, c) = r.D * CorePotts.laplacian(c, ctx, i; bc = r.bc) + r.src
struct P63bHandClamp
    sites::Vector{Int}
end
(k::P63bHandClamp)(st, p, ctx, key, mcs, backend) = (st.site.c[k.sites] .= 0.0; 0)
function p63b_with_phases(prob, phases)
    f = prob.f
    g = CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads, f.temperature, f.bias, phases,
        f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys)
    return remake(prob; f = g)
end

@testset "P6.3b control: the oracle is CorePotts' explicit Euler, per-face rule and clamp (base)" begin
    # per-face ghost values through CorePotts.laplacian(…; bc) on today's code
    prob = p63b_problem(:P63bFace2Free, p63b_face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
    hand = CorePotts.Phases(; after_mcs = (CorePotts.FieldStep((:site, :c) => (:site, :c__next),
        P63bHandRate(0.2, 0.0, ((0.0, nothing), (nothing, nothing))); dt = 1.0, substeps = 3),))
    u = solve(p63b_with_phases(prob, hand), SequentialCPM()).u[end]
    @test maximum(abs, p63b_c(u) .- p63b_ftcs(P63B_FACE2_C0, 3, 2; D = 0.2, axes = P63B_FACE2_AXES)) < 1e-12
    # the ring clamp after every substep, as n single-substep steps each followed by a clamp
    op, c0 = p63b_ring_op()
    n = 4
    prob = p63b_problem(:P63bRingFree, op, (0, 3); field_solver = ExplicitEuler(substeps = n), seed = 1)
    ring = findall(vec(p63b_ring_mask()))
    one = CorePotts.FieldStep((:site, :c) => (:site, :c__next), P63bHandRate(0.2, 0.05, nothing); dt = 1.0 / n, substeps = 1)
    hand = CorePotts.Phases(; after_mcs = Tuple(Iterators.flatten((one, P63bHandClamp(ring)) for _ in 1:n)))
    sol = solve(p63b_with_phases(prob, hand), SequentialCPM(); saveat = 1)
    for k in 1:3
        @test maximum(abs, p63b_c(sol.u[k + 1]) .- p63b_ring_oracle(c0, n, k)) < 1e-12
    end
end

@testset "P6.3b control: an unlisted closed face is zero flux (base)" begin
    for alg in P63B_ALGS
        prob = p63b_problem(:P63bFace2Free, p63b_face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
        sol = solve(prob, alg; saveat = 1)
        @test maximum(abs, p63b_c(sol.u[end]) .- p63b_ftcs(P63B_FACE2_C0, 3, 2; D = 0.2, axes = ((:noflux, :noflux), :periodic))) < 1e-12
        @test all(u -> abs(p63b_mass(u) - sum(P63B_FACE2_C0)) < 1e-10, sol.u)
    end
end

# =======================================================================================
# 1. the absorbing ring, every substep
# =======================================================================================
@testset "P6.3b: the absorbing frame keeps c = 0 on the ring after every substep ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    # negative controls on the oracle: the test can tell a per-MCS or a pre-substep clamp apart
    _, c0 = p63b_ring_op()
    @test maximum(abs, p63b_ring_oracle(c0, 4, 1; clamp = :end) .- p63b_ring_oracle(c0, 4, 1)) > 1e-2
    @test maximum(abs, p63b_ring_oracle(c0, 4, 1; clamp = :pre)[p63b_ring_mask()]) > 1e-2
    for n in (1, 4)
        op, c0 = p63b_ring_op()
        prob = p63b_problem(:P63bRing, op, (0, 3); field_solver = ExplicitEuler(substeps = n), seed = 1)
        sol = solve(prob, alg; saveat = 1)
        ring = p63b_ring_mask()
        for k in 1:3
            c = p63b_c(sol.u[k + 1])
            @test all(==(0.0), c[ring])                                             # exactly
            @test maximum(abs, c .- p63b_ring_oracle(c0, n, k)) < 1e-12             # every substep
        end
        @test Array(sol.u[end].σ) == op[1].second                                  # the frame is frozen
    end
    # a parameter value: remake keeps the generated code, and the clamp follows it
    op, c0 = p63b_ring_op(; cb = 0.5)
    prob = p63b_problem(:P63bRing, op, (0, 2); field_solver = ExplicitEuler(substeps = 4), seed = 1)
    p2 = remake(prob; p = [:cb => 0.5])
    @test p2.f === prob.f
    c = p63b_c(solve(p2, alg).u[end])
    @test all(==(0.5), c[p63b_ring_mask()])
    @test maximum(abs, c .- p63b_ring_oracle(c0, 4, 2; cb = 0.5)) < 1e-12
end

# =======================================================================================
# 2. the mask moves with the cells
# =======================================================================================
@testset "P6.3b: a kind mask is re-evaluated from σ ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    op = p63b_sink_op()
    prob = p63b_problem(:P63bSink, op, (0, 10); field_solver = ExplicitEuler(substeps = 2), seed = 5)
    sol = solve(prob, alg; saveat = 1)
    for u in sol.u[2:end]
        σ, c = Array(u.σ), p63b_c(u)
        @test all(==(0.0), c[σ .== 1])
        @test all(>(0.0), c[σ .== 0])
    end
    @test any(u -> Array(u.σ) != op[1].second, sol.u)                              # control: the sink moved
end

# =======================================================================================
# 3–4. per face, 2D and 3D
# =======================================================================================
@testset "P6.3b: per-face conditions, 2D Closed × Periodic ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    o = p63b_ftcs(P63B_FACE2_C0, 3, 2; D = 0.2, axes = P63B_FACE2_AXES)
    # negative controls on the oracle: the face condition matters, and it is a ghost value
    @test maximum(abs, o .- p63b_ftcs(P63B_FACE2_C0, 3, 2; D = 0.2, axes = ((:noflux, :noflux), :periodic))) > 1e-2
    @test maximum(abs, o .- p63b_ftcs(P63B_FACE2_C0, 3, 2; D = 0.2, axes = ((:noflux, :noflux), :periodic),
        node = (1, 1, 0.0))) > 1e-2
    prob = p63b_problem(:P63bFace2, p63b_face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
    sol = solve(prob, alg; saveat = 1)
    @test maximum(abs, p63b_c(sol.u[end]) .- o) < 1e-12
    @test p63b_mass(sol.u[2]) < sum(P63B_FACE2_C0) - 1e-3 && p63b_mass(sol.u[3]) < p63b_mass(sol.u[2]) - 1e-3
    free = p63b_problem(:P63bFace2Free, p63b_face2_op(), (0, 2); field_solver = ExplicitEuler(substeps = 3), seed = 1)
    @test prob.f.fingerprint != free.f.fingerprint
end

@testset "P6.3b: per-face conditions and a mask, 3D ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    op, c0 = p63b_face3_op()
    prob = p63b_problem(:P63bFace3, op, (0, 2); field_solver = ExplicitEuler(substeps = 4), seed = 1)
    sol = solve(prob, alg; saveat = 1)
    for k in 1:2
        c = p63b_c(sol.u[k + 1])
        @test all(==(0.0), c[p63b_block()])
        @test maximum(abs, c .- p63b_face3_oracle(c0, 4, k)) < 1e-12
    end
    # each face condition matters (negative controls on the oracle)
    o = p63b_face3_oracle(c0, 4, 2)
    @test maximum(abs, o .- p63b_ftcs(c0, 4, 2; D = 0.15, axes = ((:noflux, 0.0), (:noflux, 2.0), :periodic),
        mask = p63b_block())) > 1e-2
    @test maximum(abs, o .- p63b_face3_oracle(c0, 4, 2; S = 0.5)) > 1e-2
    p2 = remake(prob; p = [:S => 0.5])
    @test p2.f === prob.f
    @test maximum(abs, p63b_c(solve(p2, alg).u[end]) .- p63b_face3_oracle(c0, 4, 2; S = 0.5)) < 1e-12
end

# =======================================================================================
# 5. PDE before vs after the sweep
# =======================================================================================
@testset "P6.3b: the phase order is observable, drive gated on the field ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    sols = Dict(v => solve(p63b_order_problem(v), alg; saveat = 1) for v in keys(P63B_ORDERS))
    σ0 = p63b_order_σ()
    for v in keys(P63B_ORDERS)
        sol, ex = sols[v], P63B_ORDER_EXPECT[v]
        for k in 1:3
            u = sol.u[k + 1]
            @test all(==(Float64(ex.c(k))), Array(u.site.c))
            @test all(==(Float64(ex.wb(k))), Array(u.site.wb))
            @test all(==(Float64(ex.wa(k))), Array(u.site.wa))
        end
        # after_mcs follows the sweep in every order (listed or not)
        @test all(u -> Array(u.site.occ) == Float64.(Array(u.σ) .== 1), sol.u[2:end])
        @test (Array(sol.u[2].σ) != σ0) == ex.moves0
    end
    # negative control: swapping `fields` and `sweep` changes the trajectory
    @test Array(sols[:fields_sweep].u[2].σ) != Array(sols[:sweep_fields].u[2].σ)
    # listing the default relative order is no schedule, bit for bit
    for v in (:sweep_fields, :canonical)
        @test all(i -> p63b_same(sols[v].u[i], sols[:none].u[i]), eachindex(sols[:none].u))
    end
end

@testset "P6.3b: PDE-before-sweep vs sweep-before-PDE, Merks-shaped oracle ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    fs = solve(p63b_merks_problem(:fields_sweep), alg; saveat = 1)
    sf = solve(p63b_merks_problem(:sweep_fields), alg; saveat = 1)
    ring = p63b_merks_op()[1].second .== 1
    for (sol, fieldsfirst) in ((fs, true), (sf, false))
        right = wrong = 0.0
        for k in 1:6
            u, u′ = sol.u[k], sol.u[k + 1]
            @test all(==(0.0), p63b_c(u′)[ring])
            # fields first: the field step of MCS k sees σ(k); sweep first: it sees σ(k + 1)
            a = p63b_merks_step(p63b_c(u), fieldsfirst ? u.σ : u′.σ)
            b = p63b_merks_step(p63b_c(u), fieldsfirst ? u′.σ : u.σ)
            right = max(right, maximum(abs, p63b_c(u′) .- a))
            wrong = max(wrong, maximum(abs, p63b_c(u′) .- b))
        end
        @test right < 1e-12
        @test wrong > 1e-3                          # negative control: the other order's oracle fails
    end
    @test any(k -> Array(fs.u[k].σ) != Array(fs.u[k + 1].σ), 1:6)                   # control: cells moved
end

# =======================================================================================
# 6. the lifecycle is an entry of the order
# =======================================================================================
@testset "P6.3b: the lifecycle is a schedule entry ($(nameof(typeof(alg))))" for alg in P63B_ALGS
    none = solve(p63b_life_problem(:none), alg; saveat = 1)
    listed = solve(p63b_life_problem(:listed), alg; saveat = 1)
    lifefirst = solve(p63b_life_problem(:first), alg; saveat = 1)
    @test all(i -> p63b_same(listed.u[i], none.u[i]), eachindex(none.u))
    for (sol, after) in ((none, false), (lifefirst, true))
        u = sol.u[2]
        σ, c, vol = Array(u.σ), p63b_c(u), Array(u.cell.volume)
        @test count(>(0), vol) == 2                                                 # control: it divided
        @test all(i -> c[i] == (σ[i] == 0 ? 0.0 : after ? Float64(vol[σ[i]]) : 16.0), eachindex(σ))
    end
end

# =======================================================================================
# 7. errors
# =======================================================================================
@testset "P6.3b: @boundary and @schedule errors name the offender" begin
    face = (p63b_face2_op(), (0, 1))
    fkw = (; field_solver = ExplicitEuler(substeps = 1))
    bad_boundary(entry) = p63b_body(P63B_FACE2_BASE, Expr(:macrocall, Symbol("@boundary"), LineNumberNode(1, :p63b), :c,
        Expr(:block, entry)))
    e = p63b_bad(bad_boundary(:(y => (Dirichlet(0.0), NoFlux()))), face...; fkw...)
    @test e !== nothing && occursin("periodic", lowercase(p63b_message(e)))
    e = p63b_bad(bad_boundary(:(z => (NoFlux(), NoFlux()))), face...; fkw...)
    @test e !== nothing && occursin(r"\bz\b", p63b_message(e))
    order = ([ownership => p63b_order_σ(), kind => [:A]], (0, 1))
    e = p63b_bad(p63b_body(P63B_ORDER_BASE, :(@boundary wb begin
        sites(kind == A) => Dirichlet(0.0)
    end)), order...; fkw...)
    @test e !== nothing && occursin("wb", p63b_message(e))
    for (sched, name) in ((:(@schedule feilds, sweep), "feilds"), (:(@schedule sweep, fields, sweep), "sweep"),
            (:(@schedule end_mcs, sweep), "end_mcs"), (:(@schedule after_mcs, sweep), "after_mcs"),
            (:(@schedule sweep, before_mcs), "before_mcs"))
        e = p63b_bad(p63b_body(P63B_ORDER_BASE, sched), order...; fkw...)
        @test e !== nothing && occursin(name, p63b_message(e))
    end
    # controls: the same sources with valid entries build
    @test p63b_problem(:P63bFace2, face...; fkw...) isa PottsProblem
    @test p63b_order_problem(:fields_sweep) isa PottsProblem
    @test :Dirichlet in keys(Potts.DSL) && :NoFlux in keys(Potts.DSL)
end

# =======================================================================================
# 8. fingerprints and checkpoints
# =======================================================================================
@testset "P6.3b: the schedule is hashed; checkpoints do not cross orders" begin
    a, b = p63b_order_problem(:none), p63b_order_problem(:fields_sweep)
    @test a.f.fingerprint != b.f.fingerprint
    integ = init(a, SequentialCPM())
    step!(integ)
    ck = checkpoint(integ)
    @test_throws ArgumentError init(b, SequentialCPM(); checkpoint = ck)
    @test init(a, SequentialCPM(); checkpoint = ck) isa CorePotts.PottsIntegrator     # control
end

# =======================================================================================
# 9. Metal
# =======================================================================================
const P63B_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()

function p63b_metal_counts(prob; nwarm = 1, n = 3)
    integ = init(prob, CheckerboardCPM(); backend = Main.PottsDevices.device_backend(), save_start = false, save_end = false)
    foreach(_ -> step!(integ), 1:nwarm)
    out = NTuple{3, Int}[]
    for _ in 1:n
        c0 = (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes)
        step!(integ)
        push!(out, (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes) .- c0)
    end
    return out
end

@testset "P6.3b: boundaries and the schedule on the device (CheckerboardCPM, Float32)" begin
    if P63B_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM()
        # ring, every substep
        op, c0 = p63b_ring_op()
        sol = solve(p63b_problem(:P63bRing, op, (0, 3); T = Float32, field_solver = ExplicitEuler(substeps = 4), seed = 1),
            alg; backend, saveat = 1)
        for k in 1:3
            c = p63b_c(sol.u[k + 1])
            @test all(==(0.0), c[p63b_ring_mask()])
            @test maximum(abs, c .- p63b_ring_oracle(c0, 4, k)) < 1e-5
        end
        # per face, 2D and 3D
        sol = solve(p63b_problem(:P63bFace2, p63b_face2_op(), (0, 2); T = Float32, field_solver = ExplicitEuler(substeps = 3),
            seed = 1), alg; backend)
        @test maximum(abs, p63b_c(sol.u[end]) .- p63b_ftcs(P63B_FACE2_C0, 3, 2; D = 0.2, axes = P63B_FACE2_AXES)) < 1e-5
        op, c0 = p63b_face3_op()
        sol = solve(p63b_problem(:P63bFace3, op, (0, 2); T = Float32, field_solver = ExplicitEuler(substeps = 4), seed = 1),
            alg; backend)
        @test all(==(0.0), p63b_c(sol.u[end])[p63b_block()])
        @test maximum(abs, p63b_c(sol.u[end]) .- p63b_face3_oracle(c0, 4, 2)) < 1e-5
        # the moving mask
        sol = solve(p63b_problem(:P63bSink, p63b_sink_op(), (0, 10); T = Float32, field_solver = ExplicitEuler(substeps = 2),
            seed = 5), alg; backend, saveat = 1)
        @test all(u -> all(==(0.0), p63b_c(u)[Array(u.σ) .== 1]) && all(>(0.0), p63b_c(u)[Array(u.σ) .== 0]), sol.u[2:end])
        # the order: gated drive and the Merks-shaped oracle
        for v in (:sweep_fields, :fields_sweep)
            sol = solve(p63b_order_problem(v; T = Float32), alg; backend, saveat = 1)
            ex = P63B_ORDER_EXPECT[v]
            @test (Array(sol.u[2].σ) != p63b_order_σ()) == ex.moves0
            @test all(k -> all(==(Float32(ex.wa(k))), Array(sol.u[k + 1].site.wa)), 1:3)
        end
        for (v, fieldsfirst) in ((:fields_sweep, true), (:sweep_fields, false))
            sol = solve(p63b_merks_problem(v; T = Float32), alg; backend, saveat = 1)
            right = wrong = 0.0
            for k in 1:6
                u, u′ = sol.u[k], sol.u[k + 1]
                right = max(right, maximum(abs, p63b_c(u′) .- p63b_merks_step(p63b_c(u), fieldsfirst ? u.σ : u′.σ)))
                wrong = max(wrong, maximum(abs, p63b_c(u′) .- p63b_merks_step(p63b_c(u), fieldsfirst ? u′.σ : u.σ)))
            end
            @test right < 1e-4
            @test wrong > 1e-3
        end
        # D-035 as amended: no host pass, no traffic, whatever the order
        for prob in (p63b_merks_problem(:fields_sweep; T = Float32), p63b_merks_problem(:sweep_fields; T = Float32),
                p63b_order_problem(:fields_sweep; T = Float32))
            @test all(==((0, 0, 0)), p63b_metal_counts(prob))
        end
        # one host pass (an Adaptive cell ODE): the same round trip under every order, one sync per MCS
        counts = Dict(v => p63b_metal_counts(p63b_host_problem(v)) for v in (:none, :fields_sweep, :components_sweep))
        @test all(c -> all(==(1), first.(c)), values(counts))
        @test counts[:fields_sweep] == counts[:none] && counts[:components_sweep] == counts[:none]
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
