# New-side ports of the legacy PottsModels examples (de97149), hand-written against CorePotts
# with the legacy semantics (Potts 427dc2e2): the oracle for M3's generated code.
using CorePotts, StaticArrays

endo(st, c) = c != 0 && @inbounds(st.cell.kind[c]) == 1
legacy_connectivity(st, p, prop, ctx) =
    endo(st, prop.old) ? merks_connectivity(st.σ, ctx, prop) : true

# --- Merks et al. (2006) vasculogenesis, 8×8 closed ------------------------------------
function merks_delta_H(st, p, prop, ctx)
    E(v, c) = p.λ * (v - p.V0)^2
    dH = volume_delta(st.cell.volume, prop, E)
    chem = is_extension(prop) && endo(st, prop.new) ? chemotaxis_delta(st.site.c, prop, p.χ) :
           zero(dH)
    return dH + chem
end
merks_rate(st, p, ctx, key, mcs, i, c) =
    p.D * laplacian(c, ctx, i) - p.k * @inbounds(c[i]) + p.s * (owner_kind(st, i) == 1)
merks_temperature(st, p, prop, ctx) = p.T

function merks_problem(; tspan = (0, 40), seed = 0)
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
    c = zeros(8, 8)
    st = initial_state(σ, [1]; site = (; c, c_next = zero(c)))
    ph = Phases(after_mcs = (FieldStep((:site, :c) => (:site, :c_next), merks_rate;
        dt = 1.0, substeps = 2, lower = 0.0),))
    f = CPMFunction(merks_delta_H; temperature = merks_temperature,
        constraint = legacy_connectivity, phases = ph)
    p = (; λ = 1.0, V0 = 6.0, χ = 2.0, D = 0.08, s = 0.02, k = 0.01, T = 6.0)
    return CPMProblem(f, st, Lattice((8, 8); boundary = Closed()), tspan, p; seed)
end

# --- Wortel et al. (2021) activity-driven migration, 8×8 periodic ---------------------
function wortel_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[a == 0 ? 1 : 2, b == 0 ? 1 : 2]
    E(v, c) = p.λ * (v - p.V0)^2
    S(s, c) = p.λs * (s - p.S0)^2
    act = endo(st, prop.new) ?
          act_delta(st.site.act, st.σ, ctx, prop, p.λact, p.maxact; shifted = true) : 0.0
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
           surface_delta(st.cell.surface, prop, surface_change(st.σ, ctx, prop), S) + act
end
function wortel_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_surface!(st.cell.surface, prop, surface_change(st.σ, ctx, prop))
    @inbounds st.site.act[prop.target] = is_extension(prop) ? p.maxact : zero(p.maxact)
    return nothing
end
decay_act!(st, p, ctx, key, mcs, i) =
    (@inbounds st.site.act[i] = max(st.site.act[i] - one(p.maxact), zero(p.maxact)); nothing)

function wortel_problem(; tspan = (0, 40), seed = 0)
    σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1; σ[6:7, 6:7] .= 2
    lat = Lattice((8, 8))
    surface = recompute_surface(σ, lat, relation(Moore(1), lat), 2)
    st = initial_state(σ, [1, 1]; cell = (; surface), site = (; act = zeros(8, 8)))
    f = CPMFunction(wortel_delta_H; commit! = wortel_commit!, temperature = merks_temperature,
        constraint = legacy_connectivity,
        phases = Phases(after_mcs = (SitePhase(decay_act!),)))
    p = (; J = SMatrix{2, 2}(0.0, 6.0, 6.0, 2.0), λ = 1.0, V0 = 6.0, λs = 0.05, S0 = 8.0,
        λact = 4.0, maxact = 5.0, T = 8.0)
    return CPMProblem(f, st, lat, tspan, p; contact = Moore(1),
        relations = (; surface = Moore(1), act = Moore(1)), seed)
end
