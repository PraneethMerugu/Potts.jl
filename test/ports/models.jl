# Hand-written CorePotts ports of the published models (small configurations): an
# independent oracle for the generated code (test/symbolic.jl compares them exactly).
using CorePotts, StaticArrays

endo(st, c) = c != 0 && @inbounds(st.cell.kind[c]) == 1
one_arc_connectivity(st, p, prop, ctx) =
    endo(st, prop.old) ? locally_connected(st.σ, ctx, prop) : true

# --- Merks et al. (2006) vasculogenesis (D-049), 12×12 closed ----------------------------
function merks_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[a == 0 ? 1 : 2, b == 0 ? 1 : 2]
    E(v, c) = p.λ * (v - p.V0)^2
    Tf = typeof(p.λ)
    ℓ(c, s) = c == 0 ? zero(Tf) :
              p.λL * ((major_length_after(Tf, st.cell, ctx.lattice, c, prop.x, s) - p.L)^2 -
                      (major_length(Tf, st.cell, ctx.lattice, c) - p.L)^2)
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
           ℓ(prop.old, -1) + ℓ(prop.new, 1) + chemotaxis_delta(st.site.c, prop, p.χ)   # every copy
end
function merks_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx.lattice, prop)
end
merks_rate(st, p, ctx, key, mcs, i, c) =
    p.D * laplacian(c, ctx, i) - p.k * @inbounds(c[i]) * (owner_kind(st, i) == 0) + p.s * (owner_kind(st, i) == 1)
merks_temperature(st, p, prop, ctx) = p.T

const MERKS_PORT_P = (; J = SMatrix{2, 2}(0.0, 5.0, 5.0, 8.0), λ = 2.0, V0 = 9.0, λL = 1.0, L = 5.0, χ = 50.0,
    D = 0.2, s = 0.05, k = 0.02, T = 10.0)
merks_state() = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s[7:9, 6:8] .= 2; s)
function merks_problem(; tspan = (0, 40), seed = 0)
    σ = merks_state()
    lat = Lattice((12, 12); boundary = Closed())
    c = zeros(12, 12)
    st = initial_state(σ, [1, 1]; cell = init_moments(σ, lat, 2), site = (; c, c_next = zero(c)))
    ph = Phases(after_mcs = (FieldStep((:site, :c) => (:site, :c_next), merks_rate;
        dt = 1.0, substeps = 2, lower = 0.0),))
    f = CPMFunction(merks_delta_H; commit! = merks_commit!, temperature = merks_temperature,
        constraint = one_arc_connectivity, phases = ph)
    return PottsProblem(f, st, lat, tspan, MERKS_PORT_P; contact = Moore(1), proposal = Moore(1), seed)
end

# --- Niculescu et al. (2015) Act migration (Artistoo semantics, D-049), 16×16 periodic ------
function wortel_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[a == 0 ? 1 : 2, b == 0 ? 1 : 2]
    E(v, c) = p.λ * (v - p.V0)^2
    S(s, c) = p.λs * (s - p.S0)^2
    m(site, owner) = neighborhood_mean(st.site.act, st.σ, ctx, site, owner; relation = ctx.act)
    act = -(p.λact / p.maxact) * (m(prop.source, prop.new) - m(prop.target, prop.old))   # every copy
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
           surface_delta(st.cell.surface, prop, surface_change(st.σ, ctx, prop), S) + act
end
function wortel_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_surface!(st.cell.surface, prop, surface_change(st.σ, ctx, prop))
    @inbounds st.site.act[prop.target] = prop.new != 0 ? p.maxact : zero(p.maxact)
    return nothing
end
decay_act!(st, p, ctx, key, mcs, i) =
    (@inbounds st.site.act[i] = max(st.site.act[i] - one(p.maxact), zero(p.maxact)); nothing)

const WORTEL_PORT_P = (; J = SMatrix{2, 2}(0.0, 10.0, 10.0, 20.0), λ = 5.0, V0 = 16.0, λs = 0.5,
    S0 = 24.0, λact = 40.0, maxact = 10.0, T = 10.0)
wortel_state() = (s = zeros(Int32, 16, 16); s[3:6, 3:6] .= 1; s[10:13, 9:12] .= 2; s)
function wortel_problem(; tspan = (0, 40), seed = 0)
    σ = wortel_state()
    lat = Lattice((16, 16))
    surface = recompute_surface(σ, lat, relation(Moore(1), lat), 2)
    st = initial_state(σ, [1, 1]; cell = (; surface), site = (; act = zeros(16, 16)))
    f = CPMFunction(wortel_delta_H; commit! = wortel_commit!, temperature = merks_temperature,
        phases = Phases(after_mcs = (SitePhase(decay_act!),)))
    return PottsProblem(f, st, lat, tspan, WORTEL_PORT_P; contact = Moore(1), proposal = Moore(1),
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
    return PottsProblem(f, st, lat, tspan, p; contact = Moore(1), seed)
end
