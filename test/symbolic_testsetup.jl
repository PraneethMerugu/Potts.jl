# Symbolic front end (ROADMAP M3.1–M3.3): generated models equal the hand-written oracle
# ports proposal by proposal, and the derived ΔH equals H(after) − H(before) of the
# generated total energy.

@testsetup module SymbolicSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
isdefined(@__MODULE__, :stat_accept) || include(joinpath(@__DIR__, "shared", "stats_helpers.jl"))
using PottsModels: WortelAct, GranerGlazier
using Random: Xoshiro

using InteractiveUtils: code_llvm


# the field models' PDESystems (F4-B4t)
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module SyPDE
    using ..FieldPDE
    @variables c(..) src(..)::Bool [input = true]
    const C, S = c(t, x, y), src(t, x, y)
    float() = pdesys([Dt(C) ~ 0.1 * laplacian(C) - C / 10 + exp(-1) * S], [c(0, x, y) ~ 0.0], (16, 16), [C, S])
    disk() = pdesys([Dt(C) ~ 0.2 * laplacian(C) + 0.01 * S], [c(0, x, y) ~ 0.0], (40, 40), [C, S])
    chemo(dims) = pdesys([Dt(C) ~ 0.1 * laplacian(C) + 0.02 * S - 0.01 * C], [c(0, x, y) ~ 0.0], dims, [C, S])
    function sorting3d()
        C3, S3 = c(t, x, y, z), src(t, x, y, z)
        return pdesys([Dt(C3) ~ 0.1 * laplacian(C3) + 0.05 * S3 - 0.01 * C3], [c(0, x, y, z) ~ 0.0], (24, 24, 24), [C3, S3])
    end
    hex() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * laplacian(C)], [c(0, x, y) ~ 0.0], (30, 30), [C], [Dc]))
end


"""Random proposals (Moore(1) sources) on states along a trajectory of `prob`."""
function proposal_states(prob; mcs = (0, 5, 20), n = 400, rng = Xoshiro(11))
    sol = solve(remake(prob; tspan = (0, maximum(mcs))), SequentialCPM(; proposal = Moore(1)); saveat = collect(mcs))
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    out = Tuple{Any, Any}[]
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.ownership)); x = CorePotts.coordinates(lat, t)
        d = rand(rng, 1:length(moore))
        ins, y = CorePotts.shift(lat, x, moore.offsets[d])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        push!(out, (u, CorePotts.Proposal(t, s, x, d, u.ownership[t], u.ownership[s])))
    end
    return out
end


ctx_of(prob) = (;
    lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...,
)


@potts_model Spring begin
    @kinds medium blob
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        T = 10.0
        k = 2.0
        J[kind, kind] = [0 16; 16 2]
    end
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
        edges(bond) => k * (distance - rest)^2
    end
    @sweep Metropolis(; temperature = T)
end


# ---------------------------------------------------------------------------------------
# Regressions from the review of the symbolic layer

function selfcheck(prob; n = 300)
    worst = 0.0
    for (u, prop) in proposal_states(remake(prob; tspan = (0, 3)); mcs = (0, 3), n)
        a = deepcopy(u); a.ownership[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end


# ---------------------------------------------------------------------------------------
# Several named relationships (P6.0b): a link store, law and rules per name

@potts_model Chain begin
    @kinds medium blob
    @parameters begin
        k₁ = 0.7
        k₂ = 1.3
        J[kind, kind] = [0 16; 16 2]
    end
    @variables begin
        rest(bond) = 6.0
        len(tether) = 9.0
    end
    @relationship bond(cell, cell) capacity = 2
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((36, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 36)^2
        contacts => J[kind, neighbor_kind]
        edges(bond) => k₁ * (distance - rest)^2
        edges(tether) => k₂ * (distance - len)^2
    end
    @sweep Metropolis(; temperature = 8.0)
end


# the same model without link energies: the difference of total energies is the link energy


# four touching 6×6 cells in a row; 2 has a bond partner (1) and a tether partner (3)
function chain_state()
    σ = zeros(Int32, 36, 16)
    for c in 1:4
        σ[(6c - 3):(6c + 2), 6:11] .= c
    end
    return σ
end

const CHAIN_LINKS = (:bond => [(1, 2), (3, 4)], :tether => [(2, 3), (1, 4)])


# ΔH of random copies on relation `rel` against H(after) − H(before), over a short trajectory


@potts_model AmbiguousEdge begin
    @kinds medium blob
    @variables rest(edge) = 1.0
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy edges(bond) => distance - rest
    @sweep Metropolis(; temperature = 1.0)
end


# a base whose `rest(edge)` means its only relationship, extended by a second relationship


# a body built on its own (no @extend), whose `rest(edge)` binds to its only relationship
# `tether`, then extended functionally over `Spring` (`rest(edge)` on `bond`)


@potts_model RestOnTether begin                        # `rest(edge)`: `tether`
    @kinds medium blob
    @variables rest(edge) = 5.0
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy edges(tether) => (distance - rest)^2
    @sweep Metropolis(; temperature = 10.0)
end


function two_kind_blocks()
    σ = zeros(Int32, 24, 24)
    for (c, (i, j)) in enumerate(Iterators.product(2:6:20, 2:6:20))
        σ[i:(i + 4), j:(j + 4)] .= c
    end
    return σ, [isodd(c) ? 1 : 2 for c in 1:maximum(σ)]
end


@potts_model Census begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables begin
        act(site) = 0.0
        total(model) = 0.0
        ndark(model) = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - 25)^2
        contacts => J[kind, neighbor_kind]
    end
    @on_copy act[target] ~ 1.0
    @after_mcs begin
        total ~ sum(act[s] for s in sites)
        ndark ~ count(true for c in cells(dark))
    end
    @observed begin
        mean_volume ~ mean(volume for c in cells)
        dark_area ~ sum(volume for c in cells(dark))
        big ~ volume > 25
        excess ~ dark_area - 25 * ndark
    end
    @sweep Metropolis(; temperature = T)
end


@potts_model KindTemperature begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 25.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = 3.0, kinds = (dark,))
    @sweep Metropolis(; temperature = Tk[kind], combine = min)
end


# Compartments (D-036) in the authoring surface: the CorePotts nucleus/cytoplasm test model.
@potts_model Compartments begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        Jint = 2.0
        V₀[kind] = [0.0, 48.0, 16.0]
        λ = 1.0
        λc = 1.0
        Vc = 64.0
        λs = 0.1
        Sc = 32.0
        T = 10.0
    end
    @variables mass(cell) = 2.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], Jint, J[kind, neighbor_kind])
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2 + λs * (cluster_surface - Sc)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) when = (mcs == 2) && (cluster_volume >= 56), along = (1.0, 0.0), mass => Split()
    @sweep Metropolis(; temperature = T)
end


function compartment_state()
    σ = zeros(Int32, 30, 30)
    n = 0
    for i in 1:10:21, j in 1:10:21
        n += 1
        σ[i:(i + 7), j:(j + 7)] .= n
    end
    for c in 1:n
        idx = findall(==(c), σ); lo = minimum(idx)
        σ[(lo[1] + 2):(lo[1] + 5), (lo[2] + 2):(lo[2] + 5)] .= n + c
    end
    return σ, vcat(fill(:cytoplasm, n), fill(:nucleus, n)), vcat(1:n, 1:n)
end


# P6.0a: a nucleus dividing alone inside a cluster runs only its cell rule, and its daughter
# stays in the cluster; the cluster division runs only the cluster rule
@potts_model NucleusDivision begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        Jint = 2.0
        V₀[kind] = [0.0, 48.0, 16.0]
        λ = 10.0
        λc = 1.0
        Vc = 64.0
        T = 10.0
    end
    @variables begin
        mass(cell) = 2.0
        ndiv(cell) = 0.0
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], Jint, J[kind, neighbor_kind])
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) when = (mcs == 2) && (cluster_volume >= 56), along = (1.0, 0.0), mass => Split()
    @divide cells(nucleus) when = (mcs == 3) && (volume >= 2), along = (0.0, 1.0), ndiv => ndiv + 1
    @sweep Metropolis(; temperature = T)
end


function check_nucleus_division(v)
    live = findall(>(0), Array(v.cell.volume))
    kd = Array(v.cell.kind)
    cl = Array(v.cell.cluster)
    roots = unique(cl[live])
    @test length(live) == 54 && length(roots) == 18
    @test all(r -> sort(kd[filter(c -> cl[c] == r, live)]) == [1, 2, 2], roots)   # nuclei stay inside
    @test all(==(1), Array(v.cell.mass)[live])                    # Split once, by the cluster rule
    cnt = Array(v.cell.ndiv)
    @test all(c -> cnt[c] == (kd[c] == 2 ? 1 : 0), live)           # the cell rule once, nuclei only
    @test Array(v.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(v.ownership), cl)
    @test Array(v.cell.volume) == [count(==(c), Array(v.ownership)) for c in eachindex(kd)]
end


@potts_model DiskSorting begin
    @kinds medium dark light
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((40, 40); boundary = Closed(), domain = x -> (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2)
    @energy begin
        Volume(dark, light; target = 25.0)
        Adhesion(J)
    end
    @fields SyPDE.disk() (SyPDE.src => kind == dark)
    @sweep Metropolis(; temperature = T)
end


# Composition: a chemotactic extension of the Graner model and an obstacle kind added to it.


# D-114: a bound vector parameter redeclared takes the extension's default or keyword.
# Fixture: cell 1 (A, volume 9) and cell 2 (B, volume 12) on a 12×12 von Neumann lattice;
# the base without the `d` terms is 9 + 52 + 10.5 = 71.5, and the `d` terms add 9 d₁ + 12 d₂.


# Components (M4.1): MTK systems instantiated per cell, advanced by a batched cell ODE kernel.
using Potts.ModelingToolkitBase: System, @parameters

const _tc = Potts.t

Potts.ModelingToolkitBase.@variables y_c(_tc) = 1.0 m_c(_tc) = 0.0

@parameters k_c = 0.3 τ_c = 20.0 r_c = 1.0

@named decay = System([Potts.D(y_c) ~ -k_c * y_c], _tc)

@named clock = System([Potts.D(m_c) ~ r_c / τ_c], _tc)


function component_model()
    @potts_model Decaying begin
        @kinds medium A B
        @parameters T = 1.0
        @components begin
            decay = decay
        end
        @components cells(A) clock = clock
        @equations clock.r_c ~ volume / 25
        @lattice Lattice((20, 20))
        @energy cells => (volume - 25.0)^2
        @divide cells(A) when = clock.m_c >= 1, along = (1.0, 0.0), clock.m_c => 0.0
        @sweep Metropolis(; temperature = T)
    end
    return Decaying(; name = :decaying)
end


# First-class 3D: the same surface, N-generic generated code.


@parameters k_nd

@named nodefault = System([Potts.D(y_c) ~ -k_nd * y_c], _tc)


module UserFunctions
    using Potts
    using Potts: Symbolics
    hill(x, K) = x^2 / (K^2 + x^2)
    Symbolics.@register_symbolic hill(x, K)
    @potts_model Hill begin
        @kinds medium A
        @parameters T = 5.0
        @variables g(cell) = 0.5
        @lattice Lattice((16, 16))
        @energy cells => (volume - 20.0 * hill(g, 0.5))^2
        @after_mcs g ~ Pre(g) + 0.1 * hill(volume, 10.0)
        @sweep Metropolis(; temperature = T)
    end
end


# D-237 oracle: generated cell draws are addressed by `cell_entity(id, generation)` with the
# generation the cell holds when it draws, independently of the pins. Single-site B cells
# vanish (50 per site) and free the lowest ids, so at MCS 8 the first daughters take reused
# slots (generation 1 → 2) while their parents stay at generation 1: the post-increment,
# pre-increment, parent's and raw-id addressings all differ.


@potts_model Persistent begin
    @kinds medium A
    @parameters μ = 0.0 T = 2.0
    @variables begin
        px(cell) = 0.0
        py(cell) = 0.0
        cx(cell) = 0.0
        cy(cell) = 0.0
    end
    @lattice Lattice((48, 48); neighborhood = Moore(1))
    @energy begin
        Volume(A; target = 25.0, strength = 2.0)
        contacts => 4 * (kind != neighbor_kind)
    end
    @drive copy => -μ * (
        px[new] * displacement(new, 1) + py[new] * displacement(new, 2) +
            px[old] * displacement(old, 1) + py[old] * displacement(old, 2)
    )
    @after_mcs begin
        px ~ ifelse(mcs == 0, 0.0, 0.8 * Pre(px) + 0.2 * (centroid(1) - Pre(cx)))
        py ~ ifelse(mcs == 0, 0.0, 0.8 * Pre(py) + 0.2 * (centroid(2) - Pre(cy)))
        cx ~ centroid(1)
        cy ~ centroid(2)
    end
    @observed x(cell) ~ centroid(1)
    @sweep Metropolis(; temperature = T)
end


# A model built inside an `@extend` base's body is a build of its own: it neither continues
# the outer numbering nor changes the lattice dimension `centroid()` reads afterwards.


@potts_model Lags begin
    @kinds medium A
    @variables begin
        n(model) = 0.0
        lag3(model) = -1.0
        w(site) = 0.0
        wlag(site) = -1.0
        u(cell) = 0.0
    end
    @lattice Lattice((8, 8))
    @after_mcs begin
        n ~ Pre(n) + 1
        lag3 ~ Pre(n, 3)
        w ~ Pre(w) + 1
        wlag ~ Pre(w, 2) - Pre(w, 1)
    end
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model Integrals begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        mass(cell) = 0.0
        hot(cell) = 0.0
        n(model) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        mass ~ integral(w)
        hot ~ integral(w > 0.5) / volume
        n ~ Pre(n) + 1
    end
    @observed begin
        cmass(cell) ~ integral(w)
        occupied(cell) ~ integral(1)
    end
    @sweep Metropolis(; temperature = 2.0)
end


@potts_model VectorBits begin
    @kinds medium A
    @parameters begin
        d[1:2] = [1.0, 0.0]
        T = 1.0
    end
    @lattice Lattice((12, 12))
    @variables begin
        g(site)[1:2] = [0.5, -0.5]
        m(model)[1:2] = 0.0
        q(cell)[1:3] = [1.0, 2.0, 3.0]
    end
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ Pre(m) + d
        g ~ normalize(g)
    end
    @divide cells(A) when = mcs == 1, q => Split()
    @sweep Metropolis(; temperature = T)
end


@potts_model Fresh begin
    @kinds medium A
    @parameters k = 1.0
    @variables begin
        w(site) = 1.0
        mb(cell) = 0.0
        n(model) = 0.0
        d1(site) = -1.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 44)^2
    @before_mcs mb ~ integral(k * w)
    @after_mcs begin
        w ~ Pre(w) + 1
        n ~ Pre(n) + 1
        d1 ~ Pre(n, 1) - Pre(n, 2)
    end
    @divide cells(A) when = volume > 40, along = RandomPlane()
    @observed begin
        cmass(cell) ~ integral(w)
        occ(cell) ~ integral(1)
    end
    @sweep Metropolis(; temperature = 1.0)
end


# P6.0m (D-042): an integral read in a block that writes its operand bare folds the new
# values; readers after the block (equations, the temperature) see them too.


# P6.0m3 (D-042, D-076): `integral(Pre(w))` is its own slot, refreshed at the start of the
# after block (σ post-sweep, w at its block-start value). It needs no `w__pre` snapshot and
# is left intact when another read does snapshot `w`; in @before_mcs the boundary refresh is
# already the block-start fold.


# P6.0m: the ring rule is TST's `ConnectivityPreservedP` (Merks reference), not CC3D's local
# rule, so D-074 leaves it alone: at most one arc (zero included) or exactly two ring cells


Potts.ModelingToolkitBase.@variables drug_c(_tc) = 0.0

@parameters drug_k = 0.2 drug_dose = 0.0

@named drug = System([Potts.D(drug_c) ~ drug_dose - drug_k * drug_c], _tc)


@potts_model Systemic begin
    @kinds medium A
    @variables g(model) = 1.0
    @components model pk = drug
    @equations begin
        D(g) ~ -0.5 * g
        pk.drug_dose ~ count(true for c in cells)           # dosing ∝ the number of live cells
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model HexSorting begin
    @kinds medium dark light
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @variables cx(cell) = 0.0
    @lattice Lattice((30, 30); geometry = Hexagonal(), neighborhood = Hex(2))
    @energy begin
        cells => (volume - 19)^2 + 0.2 * (surface - 60)^2
        contacts => J[kind, neighbor_kind]
    end
    @fields SyPDE.hex()
    @after_mcs cx ~ centroid(1)
    @sweep Metropolis(; temperature = 8.0)
end


# ---------------------------------------------------------------------------------------
# P6.0e: contact energies read site values `x` (at s) and `x′` (at s′)

using Statistics: Statistics


@potts_model SiteContacts begin
    @structural_parameters begin
        dims = (24, 24)
        geometry = CorePotts.Square()
        near = Moore(1)
        far = Moore(2)
    end
    @kinds medium A B
    @parameters begin
        λ = 1.0
        T = 6.0
        β = 3.0
        γ = 0.4
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables cue(site) = 0.0
    @lattice Lattice(dims; geometry, neighborhood = near)
    @relations wide = far
    @energy begin
        cells(A, B) => λ * (volume - 16)^2
        # asymmetric in s/s′ and in the kinds: the compiler averages it with its mirror
        contacts => J[kind, neighbor_kind] + β * cue * (1 + cue′)^2 * (kind == A)
        contacts(wide) => weight * γ * (cue - 2 * cue′) * (neighbor_owner != 0)
    end
    @sweep Metropolis(; temperature = T)
end


"""Blocks of `side`ⁿ cells (kinds A/B alternating) with medium gaps, and a random cue."""
function site_contact_state(dims; side = 4, rng = Xoshiro(3))
    σ = zeros(Int32, dims...)
    n = 0
    for corner in Iterators.product((1:(side + 1):(d - side) for d in dims)...)
        n += 1
        σ[(c:(c + side - 1) for c in corner)...] .= n
    end
    return σ, [isodd(c) ? :A : :B for c in 1:n], rand(rng, dims...)
end


site_contact_problem(sys, dims; tspan = (0, 4), side = 4, kw...) =
    (
    (σ, kinds, cue) = site_contact_state(dims; side);
    PottsProblem(sys, [ownership => σ, kind => kinds, :cue => cue], tspan; kw...)
)


"""ΔH of random copies against H(after) − H(before); `dH` defaults to the generated ΔH."""
function site_selfcheck(prob, rel; n = 400, dH = (u, prop) -> energy_change(prob, u, prop))
    sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = rel); saveat = [0, 2, 4])
    lat = prob.lattice
    R = CorePotts.relation(rel, lat)
    rng = Xoshiro(5)
    worst = 0.0
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.ownership)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, R.offsets[rand(rng, 1:length(R))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s])
        a = deepcopy(u); a.ownership[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(dH(u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end


# the generated ΔH with the pair's site reads exchanged (`x[target]` ↔ `x[s′]`): a mutant
# lowering that confuses `x` and `x′`


# an on-copy write and a clear-on-ownership-change variable read by contact (and site) terms:
# ΔH sees the target's value after the copy (D-045)
@potts_model SiteContactsOnCopy begin
    @structural_parameters begin
        write = true
        clear = true
    end
    @kinds medium A
    @parameters begin
        T = 6.0
        β = 2.0
        γ = 1.5
        J[kind, kind] = [0 8; 8 3]
    end
    @variables begin
        mark(site) = 0.0
        tag(site) = 0.5, [clear_on_ownership_change = clear]
    end
    @lattice Lattice((20, 20); neighborhood = Moore(1))
    @energy begin
        cells(A) => (volume - 16)^2
        contacts => J[kind, neighbor_kind] + β * mark * (1 + mark′) * (owner != 0) + γ * (tag - tag′)^2
        sites => 0.3 * mark * (kind == A)
    end
    if write
        @on_copy mark[target] ~ 0.5 * mark[source] + 1.0
    end
    @sweep Metropolis(; temperature = T)
end


# a population fold in a contact term reads its own bound site: `cue` and `kind` there are
# not the pair's (neither placed at `site` nor mirrored)


# `x′` in an extension: bound next to `x` by `@extend`, or named explicitly (scalar and vector)
@potts_model SiteContactsBase begin
    @kinds medium A B
    @parameters J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    @variables begin
        cue(site) = 0.0
        v(site)[1:2] = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(A, B) => (volume - 16)^2
        contacts => J[kind, neighbor_kind] + cue * cue′ + v[1] * v′[2]
    end
    @sweep Metropolis(; temperature = 6.0)
end


# two site terms and an on-copy write both read: each site term sees the written value


# P6.0e2: `x′` of a quantity that is not a site/field variable is a Potts error, raised when
# the constructor reads the unbound `x′`; a local named `x′` is ordinary Julia


# ---------------------------------------------------------------------------------------
# P6.0f: `Every(n)` per lifecycle rule

@potts_model RuleCadences begin
    @structural_parameters begin
        na = 1
        nb = 1
        dims = (48, 32)
        geometry = CorePotts.Square()
        near = Moore(1)
    end
    @kinds medium ka kb
    @variables x(cell) = 0.0
    @parameters T = 10.0
    @lattice Lattice(dims; geometry, neighborhood = near)
    @energy cells => (volume - 64.0)^2
    @constraint no_extinction
    @divide cells(ka) Every(na) when = volume >= 4, along = RandomPlane(), x => 1.0
    @divide cells(kb) Every(nb) when = volume >= 4, along = RandomPlane(), x => 2.0
    @sweep Metropolis(; temperature = T)
end


# one cell of each kind, `w` sites wide
function rule_cadence_state(dims; w = 12)
    σ = zeros(Int32, dims)
    idx(o) = ntuple(d -> d == 1 ? (o:(o + w - 1)) : (2:(1 + min(w, dims[d] - 2))), length(dims))
    σ[idx(2)...] .= 1
    σ[idx(dims[1] ÷ 2 + 2)...] .= 2
    return σ, [:ka, :kb]
end

live_kinds(u) = (
    v = Array(u.cell.volume); k = Array(u.cell.kind);
    (count(c -> v[c] > 0 && k[c] == 1, eachindex(v)), count(c -> v[c] > 0 && k[c] == 2, eachindex(v)))
)

# every live cell divides at each checked MCS: 2^(checked MCS in 0:N-1) cells
cadence_oracle(n, N) = 2^count(m -> m % n == 0, 0:(N - 1))

_has_ast(ex, pred) = pred(ex) || (ex isa Expr && any(a -> _has_ast(a, pred), ex.args))
_count_ast(ex, pred) = (pred(ex) ? 1 : 0) + (ex isa Expr ? sum(a -> _count_ast(a, pred), ex.args; init = 0) : 0)
_trigger_ast(sys) = Potts.generated_code(sys).lifecycle.trigger
_has_modulo_gate(ex, n) = _has_ast(
    ex,
    x -> x isa Expr && x.head === :call && length(x.args) == 3 && x.args[1] === :(==) && x.args[3] == 0 &&
        x.args[2] isa Expr && x.args[2].head === :call && length(x.args[2].args) == 3 &&
        x.args[2].args[1] === :% && x.args[2].args[2] === :mcs && x.args[2].args[3] == n
)
_has_any_modulo_gate(ex) = _has_ast(
    ex,
    x -> x isa Expr && x.head === :call && length(x.args) == 3 &&
        x.args[1] === :% && x.args[2] === :mcs
)
_has_ruled_event(ex) = _has_ast(ex, x -> x isa Expr && x.head === :call && x.args[1] == :(CorePotts.ruled_event))
_has_true_and(ex) = _has_ast(ex, x -> x isa Expr && x.head === :&& && !isempty(x.args) && x.args[1] === true)
_has_ruled_divide(sys) = any(
    e -> e isa Expr && e.head === :(->) && e.args[1] isa Expr && e.args[1].head === :tuple &&
        :daughter in e.args[1].args && :rule in e.args[1].args,
    Potts.generated_code(sys).phases
)


# Only the rule that fired writes the daughters' state (P6.0f review): rules sharing a kind
# are tried in model order, and the first whose cadence, kinds and `when` hold wins, its
# division and its state rules.
@potts_model SameKindCadences begin
    @structural_parameters begin
        na = 2
        nb = 3
        wa = 4           # rule a is met when volume ≥ wa, rule b when volume ≥ wb
        wb = 4
        xa = 1.0
        xb = 2.0
    end
    @kinds medium ka
    @variables x(cell) = 0.0
    @lattice Lattice((48, 32))
    @energy cells => (volume - 64.0)^2
    @constraint no_extinction
    @divide cells(ka) Every(na) when = volume >= wa, along = RandomPlane(), x => xa
    @divide cells(ka) Every(nb) when = volume >= wb, along = RandomPlane(), x => xb
    @sweep Metropolis(; temperature = 10.0)
end


# cluster rules at cadences that are not the gcd, sharing their kind (rule-carrying events
# on the cluster path: every member takes its root's rule)
@potts_model ClusterCadences begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        V₀[kind] = [0.0, 48.0, 16.0]
    end
    @variables mass(cell) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 2.0, J[kind, neighbor_kind])
        clusters(cytoplasm) => (cluster_volume - 64.0)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) Every(3) when = cluster_volume >= 16, along = (1.0, 0.0), mass => 3.0
    @divide clusters(cytoplasm) Every(2) when = cluster_volume >= 16, along = (1.0, 0.0), mass => 5.0
    @sweep Metropolis(; temperature = 10.0)
end


# The discrete-time component fixtures are in shared/discrete_fixtures.jl: the QA items read
# them too and a setup cannot see another setup's names.
isdefined(@__MODULE__, :discrete_counter_model) || include(joinpath(@__DIR__, "shared", "discrete_fixtures.jl"))


# A tick reading another cell's node sees its pre-tick value (Jacobi across cells), under both
# algorithms: a shift register moves one cell per tick (review P6.0k round 2, B1).
@named shiftcell = System([dX(_kd) ~ ds], _tc)

@potts_model DiscreteShiftRegister begin
    @kinds medium A
    @components cells(A) xc = shiftcell
    @equations xc.ds ~ ifelse(id > 1, xc.dX[max(id - 1, 1)] > 0.5, true)
    @lattice Lattice((16, 16))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

shift_register_oracle(m) = Float64[c <= m for c in 1:6]


# Array variables: one scalar slot per element, `name₊z_i` (G11)
Potts.ModelingToolkitBase.@variables dz(_tc)[1:2]::Bool = [false, true]

@named ring = System([dz[1](_kd) ~ !dz[2](_kd - 1), dz[2](_kd) ~ dz[1](_kd - 1)], _tc)

@potts_model DiscreteArray begin
    @kinds medium A
    @components cells(A) ar = ring
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end


# MTK's compile of a discrete component raises `PottsCompileError` naming the component; an
# error raised in Potts' own code propagates unchanged.
Potts.ModelingToolkitBase.@variables k2X(_tc)::Bool = false k2Y(_tc)::Bool = false


# P6.0r (D-083): free slots (capacity > n; kind 1, their own cluster roots) add nothing to H


# P6.0v3 (F1, D-101): the last after-MCS cell update moves into `Lifecycle.before` (one
# device launch with the trigger) exactly when the trigger reads what it writes only at its
# own cell; otherwise it stays a phase of its own


# ---------------------------------------------------------------------------------------
# P6.0ah (D-107): textually equal folds over different bound variables in one statement keep
# a canonical slot numbering (their key carries the variables' names), and integrals of
# such folds stay distinct and are not hoisted apart from their trackers. A salted
# `Base.hash` of the Potts operators stands for another package build (inert at salt 0).

const P60AH_TIE_SALT = Ref{UInt}(0)

for f in (Potts.population, Potts.gather, Potts.value_at, Potts.cell_integral)
    @eval function Base.hash(g::typeof($f), h::UInt)
        P60AH_TIE_SALT[] == 0 && return invoke(hash, Tuple{Function, UInt}, g, h)
        return hash(P60AH_TIE_SALT[], hash(:p60ah_tie_salt, h))
    end
end

p60ah_tie_salted(f, s) = (
    P60AH_TIE_SALT[] = s; try
        f()
    finally
        P60AH_TIE_SALT[] = 0
    end
)


function p60ah_tie_code(M, solver)
    strip!(x) = x isa Expr ?
        (
            Base.remove_linenums!(x);
            x.head === :macrocall && length(x.args) >= 2 && x.args[2] isa LineNumberNode && (x.args[2] = nothing);
            x.args .= strip!.(x.args); x
        ) :
        x isa NamedTuple ? NamedTuple{keys(x)}(map(strip!, values(x))) :
        x isa Tuple ? map(strip!, x) :
        x isa AbstractVector ? map(strip!, x) : x
    g = Potts.generated_code(M(; name = :x); ode_solver = solver)
    return [
        strip!(deepcopy(x)) for k in propertynames(g) for x in (
                getproperty(g, k) isa AbstractVector ?
                getproperty(g, k) : (getproperty(g, k),)
            )
    ]
end


# A change re-derives a computed parameter iff it is not named and an input is named or
# re-derived (transitively); every other value is kept. Diamond p₁ → p₂, (p₂, p₃) → p₄, p₃ → p₅.
@potts_model ParamDiamond begin
    @kinds medium A
    @parameters begin
        p₁ = 1.0
        p₂ = 2p₁
        p₃ = 3.0
        p₄ = p₂ + p₃
        p₅ = 5p₃
        λ = 1.0
    end
    @lattice Lattice((6, 6); neighborhood = VonNeumann(1))
    @energy begin
        cells(A) => λ * (volume - p₄)^2
    end
    @sweep Metropolis(; temperature = 1.0)
end


# One name, one category, for vectors: a vector claims its name and each component name
# (`vb_1`, `vb_2`); a quantity of another category, or a scalar of the same category, named
# like a component is rejected (in one model, through `@extend`/`extend`, programmatically).


# ---------------------------------------------------------------------------------------
# P6.0ai (D-110): a population fold inside `integral(x)` that reads neither the site nor the
# cell is computed once per refresh of the integral (a model slot), not at every site. The
# slot must be current at every refresh: in a block after a write to what the fold reads, at
# the MCS boundary after the lifecycle, at init, and for observed integrals.


function p60ai_init(dims)
    σ = zeros(Int32, dims)
    if length(dims) == 2
        σ[3:6, 3:6] .= 1; σ[10:13, 9:12] .= 2
    else
        σ[2:3, 2:3, 2:5] .= 1; σ[5:6, 5:6, 3:6] .= 2
    end
    w = [1 + 0.5 * sin(I[1] / 3) * cos(sum(Tuple(I)[2:end]) / 5) for I in CartesianIndices(dims)]
    return σ, w
end


# Every refresh point of a hoisted fold's slot: at init (read by a before-MCS update in the
# first MCS), a gated reader of a fold whose operand the block writes, an equation reading
# such an integral after the block, and a checkpoint continuation.
@potts_model P60aiRefresh begin
    @kinds medium A
    @variables begin
        w(site) = 1.0
        v(cell) = 0.0
        sb(cell) = 0.0
        s2(cell) = 0.0
        r(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @before_mcs sb ~ integral(w * sum(volume[c] for c in cells))
    @after_mcs v ~ Pre(v) + 1
    @after_mcs Every(2) s2 ~ integral(w * sum(v[c] for c in cells))
    @equations D(r) ~ integral(sin(w) * sum(v[c] for c in cells))
    @observed o(cell) ~ integral(w * mean(volume[c] for c in cells))
    @sweep Metropolis(; temperature = 2.0)
end


# `div`/`÷` on parameters and cell quantities in step code, and a variable default computed
# with a function of parameters (D-117)


# ---------------------------------------------------------------------------------------
# P6.0t (D-120): the start-of-after refresh covers the integrals read after the sweep, and
# a tick reads its population folds through slots (`__tickpop`), so an integral read only
# inside a tick's fold must still count as read after the sweep. Twin: the same fold over
# `volume` (w ≡ 1 makes `integral(w)` the volume); a stale integral lags one MCS.


# Stored integrals keep the full gather's order (and the fingerprint) when no integral is
# read only by `@observed`: here `@observed` is the first statement to read pb.


# ---------------------------------------------------------------------------------------
# D-137 review (P6.0o): namespaced keys of the model's own `sys.x`, `@set` on the MTK mirror
# names, metadata precedence in `extend`, property errors naming the category

@potts_model NsCell begin
    @kinds medium host
    @parameters begin
        λ = 2.0
        T = 1.0
        w[1:2] = [0.5, 0.25]
    end
    @variables begin
        x(cell) = 1.5
        g(model) = 0.0
    end
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy cells(host) => λ * (volume - 9.0)^2
    @equations D(x) ~ -0.1 * x
    @after_mcs g ~ g + 1.0
    @observed total ~ sum(x for n in cells)
    @sweep Metropolis(; temperature = T)
end

const NS_DECAY = Ref{Any}(nothing)

let t = Potts.t
    Potts.ModelingToolkitBase.@variables y(t) = 1.0
    Potts.ModelingToolkitBase.@parameters k = 0.1
    NS_DECAY[] = Potts.ModelingToolkitBase.System([Potts.D(y) ~ -k * y], t; name = :decay)
end


struct NsKey end

using Potts.ModelingToolkitBase: Setfield as NsSetfield


# P6.4a1 (D-188): the copy scope reads `direction[k]`, `position[s][k]` and `mcs`.
# The acceptance file pins the values on the host hook and the kernel path; here: the
# `mcs` convention read back through an on-copy write, and the diagnostics.


include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
