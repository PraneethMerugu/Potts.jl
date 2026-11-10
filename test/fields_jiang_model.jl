# The Jiang-like model of F3-18 (test/fields_jiang.jl) and its spheroid, shared with the guard's
# soft set (test/fields_identity.jl, review r1).
isdefined(Main, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))
module JgPDE
using ..FieldPDE
@variables o(..) [lattice_level = Coarse(4)] g(..) [lattice_level = Coarse(4)] l(..) [lattice_level = Coarse(4)]
@variables gf(..) [lattice_level = Coarse(4)] inh(..) [lattice_level = Coarse(4)]
@variables pq(..)::Bool [input = true] kP(..)::Bool [input = true] kQ(..)::Bool [input = true] kN(..)::Bool [input = true]
@variables med(..)::Bool [input = true]
# the five fields on a coarse grid (`Coarse(4)`); the kinds are bound inputs: `pq` is
# `ismember(kind, (P, Q))`, `kP`, `kQ`, `kN` the kinds and `med` the medium
function jiang(dims)
    @parameters Do = 2880.0 Dg = 73.7 Dl = 103.0 Df = 0.048 Di = 0.048 a0 = 324.0 b0 = 648.0 C0 = 720.0 oT = 0.02 gT = 0.06
    @parameters oO = 0.28 gO = 5.5 o0 = 0.08 g0 = 5.5 df = 3.0 ei = 3.0
    X = (t, x, y, z)
    O, G, L, GF, INH = o(X...), g(X...), l(X...), gf(X...), inh(X...)
    PQ, P, Q, N, M = pq(X...), kP(X...), kQ(X...), kN(X...), med(X...)
    eqs = [Dt(O) ~ Do * Δ(O) - a0 * max(O - oT, 0) / (oO - oT) * PQ,
        Dt(G) ~ Dg * Δ(G) - b0 * max(G - gT, 0) / (gO - gT) * PQ,
        Dt(L) ~ Dl * Δ(L) + C0 * (max(O - oT, 0) / (oO - oT) + max(G - gT, 0) / (gO - gT)) / 2 * PQ,
        Dt(GF) ~ Df * Δ(GF) - df * GF * (P + 0.5 * Q),
        Dt(INH) ~ Di * Δ(INH) + ei * (Q + 2 * N)]
    bcs = [o(0, x, y, z) ~ 0.0, g(0, x, y, z) ~ 0.0, l(0, x, y, z) ~ 0.0, gf(0, x, y, z) ~ 0.0, inh(0, x, y, z) ~ 0.0,
        O ~ masked(M, o0), G ~ masked(M, g0), L ~ masked(M, 0.0), GF ~ masked(M, 1.0), INH ~ masked(M, 0.0)]
    return pdesys(eqs, bcs, dims, [O, G, L, GF, INH, PQ, P, Q, N, M],
        [Do, Dg, Dl, Df, Di, a0, b0, C0, oT, gT, oO, gO, o0, g0, df, ei])
end
end
# the model on lattice `dims` (`frozen`: the cells do not move)
function jiang_model(name, dims; frozen = true)
    kinds = frozen ? :(@kinds medium P[frozen] Q[frozen] N[frozen]) : :(@kinds medium P Q N)
    return eval(:(@potts_model $name begin
        $kinds
        @variables ocell(cell) = 0.0
        @lattice Lattice($dims; boundary = Closed())
        @energy cells => (volume - 27.0)^2
        # O₂, glucose, lactate, growth factor and inhibitor (diffusion in voxel²/MCS; O₂ and
        # glucose consumption and lactate production in mM/MCS; thresholds, optimal and medium
        # concentrations in mM, relative for the factors)
        @fields o = JgPDE.jiang($dims) (JgPDE.pq => ismember(kind, (P, Q)), JgPDE.kP => kind == P, JgPDE.kQ => kind == Q,
            JgPDE.kN => kind == N, JgPDE.med => kind == medium)
        @after_mcs ocell ~ integral(o) / volume
        @schedule repeat(4, sweep(fraction = 1//4), fields), after_mcs
        @sweep Metropolis(; temperature = 2.0)
    end))
end
# a spheroid of 3×3×3 cells at the center: necrotic core, quiescent shell, proliferating rim
function jiang_state(dims; r = dims[1] / 3)
    σ = zeros(Int32, dims)
    kinds = Symbol[]
    c = dims ./ 2
    for I in CartesianIndices(dims)
        J = (Tuple(I) .- 1) .÷ 3                     # the 3×3×3 cell the site falls in
        ρ = sqrt(sum(abs2, (J .* 3 .+ 2) .- c))      # the cell center's distance
        ρ <= r || continue
        k = LinearIndices(dims .÷ 3 .+ 1)[(J .+ 1)...]
        σ[I] = k                                     # (renumbered below)
    end
    ids = sort!(unique(filter(!=(0), σ)))
    new = Dict(k => Int32(i) for (i, k) in enumerate(ids))
    for I in eachindex(σ)
        σ[I] == 0 || (σ[I] = new[σ[I]])
    end
    for k in ids
        J = Tuple(CartesianIndices(dims .÷ 3 .+ 1)[k]) .- 1
        ρ = sqrt(sum(abs2, (J .* 3 .+ 2) .- c))
        push!(kinds, ρ < r / 3 ? :N : ρ < 2r / 3 ? :Q : :P)
    end
    return σ, kinds
end
const JG_DIMS = (32, 32, 32)
const JiangLike = jiang_model(:JiangLike, JG_DIMS)
