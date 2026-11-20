# Definitions of lifecycle_tests.jl that other test files use.
frozen_dynamics(st, p, prop, ctx) = false
lc_state(σ, kinds, lat; capacity = length(kinds), cell = (;)) = with_capacity(
    initial_state(σ, kinds; cell = merge(init_moments(σ, lat, length(kinds)), cell)), capacity)

function run_lifecycle(σ, kinds, lat, lifecycle; capacity = length(kinds) + 4, tspan = (0, 1),
        cell = (;), constraint = frozen_dynamics, p = gg_params(), alg = SequentialCPM(),
        phases = Phases(), backend = CPU())
    st = lc_state(σ, kinds, lat; capacity, cell)
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint, lifecycle, phases)
    return solve(PottsProblem(f, st, lat, tspan, p), alg; backend)
end

divide_at(t) = (st, p, ctx, key, mcs, c) -> mcs == t ? EVENT_DIVIDE : EVENT_NONE

# D-081: a frozen mask that derives from the state (as Potts' `[frozen]` kinds) is
# recomputed after every MCS with a lifecycle event, by `refresh_frozen!` and by `reinit!`.
# `FrozenKind(k)`: the standard rule (built on the device), the sites of cells of kind `k`
# are frozen. `HostFrozen(k)`: the same rule given as a custom `remake_frozen` (the host
# fallback). `nothing`: a static mask.
struct FrozenKind
    k::Int32
end
CorePotts.frozen_kinds(s::FrozenKind) = (s.k,)              # `frozen_varies` follows
struct HostFrozen
    k::Int32
end
CorePotts.frozen_varies(::HostFrozen) = true                # required with a custom rule
struct OnlyRemake end                                       # … which this one forgets
fk_mask(u, k) = (kinds = Array(u.cell.kind); map(c -> c != 0 && kinds[c] == k, Array(u.ownership)))
CorePotts.remake_frozen(s::HostFrozen, prob, u) = fk_mask(u, s.k)
CorePotts.remake_frozen(::OnlyRemake, prob, u) = fk_mask(u, 2)

# 30×30 periodic, cell 1 (kind 1) and cell 2 (kind 2), both 6×6 and growing toward V0 = 40
function fk_problem(trigger = nothing; kind = nothing, sys = FrozenKind(2), T = Float64,
        tspan = (0, 30), seed = 1)
    lat = Lattice((30, 30))
    σ = zeros(Int32, 30, 30); σ[5:10, 5:10] .= 1; σ[18:23, 18:23] .= 2
    st = lc_state(σ, Int32[1, 2], lat)
    lc = trigger === nothing ? nothing :
         Lifecycle(trigger; normal = AlongMinorAxis{T}(), (kind === nothing ? (;) : (; kind))...)
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, lifecycle = lc, sys)
    return PottsProblem(f, st, lat, tspan, gg_params(T); seed, frozen = fk_mask(st, 2))
end
fk_sites(u, c) = Array(u.ownership) .== c
# saved states i-1 → i in which cell c's site set changed
fk_moved(sol, c, is) = count(i -> fk_sites(sol.u[i], c) != fk_sites(sol.u[i - 1], c), is)
fk_flip(S) = (st, p, ctx, key, mcs, c) -> mcs == S ? EVENT_TRANSITION : EVENT_NONE
fk_swap(st, p, ctx, key, mcs, c) = Int32(3 - st.cell.kind[c])
# a disk domain with no frozen kind (a static mask) and a division at MCS 2
function fk_domain_problem(; T = Float64)
    lat = Lattice((30, 30); boundary = Closed(), domain = x -> (x[1] - 15.5)^2 + (x[2] - 15.5)^2 <= 13^2)
    σ = zeros(Int32, 30, 30); σ[10:19, 12:19] .= 1
    st = lc_state(σ, Int32[1], lat; capacity = 3)
    lc = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 2 && c == 1 ? EVENT_DIVIDE : EVENT_NONE;
        normal = AlongMinorAxis{T}())
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, lifecycle = lc)
    return PottsProblem(f, st, lat, (0, 8), gg_params(T))
end

# D-128: a custom rule declares the leaves it reads (`frozen_reads`). On the CPU
# the declared path is the live state (no copy), so only the validation and the masks are
# exercised here; the byte behaviour is covered on Metal by the acceptance file
# `frozen_kind_refresh_bytes_tests.jl`. A bad declaration fails at `init`, before any step.
struct DeclaredFrozen
    k::Int32
    reads::Any
end
CorePotts.frozen_varies(::DeclaredFrozen) = true
CorePotts.frozen_reads(s::DeclaredFrozen) = s.reads
CorePotts.remake_frozen(s::DeclaredFrozen, prob, u) = fk_mask(u, s.k)
struct KindsBadReads end                                    # the standard rule, a bad declaration
CorePotts.frozen_kinds(::KindsBadReads) = (Int32(2),)
CorePotts.frozen_reads(::KindsBadReads) = (:nonexistent,)
