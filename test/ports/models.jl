# Hand-written CorePotts ports of the published models (small configurations): an
# independent oracle for the generated code (test/symbolic.jl compares them exactly).
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

# --- OpenVT monolayer with one scheduled division, 12×8 closed --------------------------
openvt_trigger(st, p, ctx, key, mcs, c) =
    mcs == 0 && @inbounds(st.cell.volume[c]) >= 8 ? EVENT_DIVIDE : EVENT_NONE   # AtMCS(1)
openvt_normal(st, p, ctx, key, mcs, c) = (1.0, 0.0)
openvt_split!(st, p, ctx, key, mcs, parent, daughter) =
    (m = st.cell.mass[parent] / 2; st.cell.mass[parent] = m; st.cell.mass[daughter] = m; nothing)
function openvt_delta_H(st, p, prop, ctx)
    J(a, b) = (a == 0 || b == 0) ? p.Jm : p.Jt
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
function openvt_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx.lattice, prop)
end

function openvt_problem(; tspan = (0, 20), seed = 0)
    σ = zeros(Int32, 12, 8); σ[5:8, 4:5] .= 1
    lat = Lattice((12, 8); boundary = Closed())
    st = with_capacity(initial_state(σ, [1]; cell = merge(init_moments(σ, lat, 1), (; mass = [8.0]))), 8)
    f = CPMFunction(openvt_delta_H; commit! = openvt_commit!, temperature = merks_temperature,
        lifecycle = Lifecycle(openvt_trigger; normal = openvt_normal, divide! = openvt_split!))
    p = (; λ = 2.0, V0 = 8.0, Jt = 0.0, Jm = 4.0, T = 2.0)
    return CPMProblem(f, st, lat, tspan, p; contact = Moore(1), seed)
end
