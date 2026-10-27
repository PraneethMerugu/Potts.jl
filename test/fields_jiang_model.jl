# The Jiang-like model of F3-18 (test/fields_jiang.jl) and its spheroid, shared with the guard's
# soft set (test/fields_identity.jl, review r1).
# the model on lattice `dims` (`frozen`: the cells do not move)
function jiang_model(name, dims; frozen = true)
    kinds = frozen ? :(@kinds medium P[frozen] Q[frozen] N[frozen]) : :(@kinds medium P Q N)
    return eval(:(@potts_model $name begin
        $kinds
        @parameters begin
            Do = 2880.0              # O₂, glucose, lactate, growth factor, inhibitor (voxel²/MCS)
            Dg = 73.7
            Dl = 103.0
            Df = 0.048
            Di = 0.048
            a0 = 324.0               # O₂ and glucose consumption, lactate production (mM/MCS)
            b0 = 648.0
            C0 = 720.0
            oT = 0.02                # thresholds and optimal concentrations (mM)
            gT = 0.06
            oO = 0.28
            gO = 5.5
            o0 = 0.08                # the medium values (mM; relative for the factors)
            g0 = 5.5
            df = 3.0                 # growth factor consumption, inhibitor production (relative/MCS)
            ei = 3.0
        end
        @variables begin
            o(field) = 0.0, [lattice_level = Coarse(4)]
            g(field) = 0.0, [lattice_level = Coarse(4)]
            l(field) = 0.0, [lattice_level = Coarse(4)]
            gf(field) = 0.0, [lattice_level = Coarse(4)]
            inh(field) = 0.0, [lattice_level = Coarse(4)]
            ocell(cell) = 0.0
        end
        @lattice Lattice($dims; boundary = Closed())
        @energy cells => (volume - 27.0)^2
        @equations begin
            D(o) ~ Do * Δ(o) - a0 * max(o - oT, 0) / (oO - oT) * ismember(kind, (P, Q))
            D(g) ~ Dg * Δ(g) - b0 * max(g - gT, 0) / (gO - gT) * ismember(kind, (P, Q))
            D(l) ~ Dl * Δ(l) + C0 * (max(o - oT, 0) / (oO - oT) + max(g - gT, 0) / (gO - gT)) / 2 * ismember(kind, (P, Q))
            D(gf) ~ Df * Δ(gf) - df * gf * ((kind == P) + 0.5 * (kind == Q))
            D(inh) ~ Di * Δ(inh) + ei * ((kind == Q) + 2 * (kind == N))
        end
        @bcs begin
            o ~ masked(kind == medium, o0)
            g ~ masked(kind == medium, g0)
            l ~ masked(kind == medium, 0.0)
            gf ~ masked(kind == medium, 1.0)
            inh ~ masked(kind == medium, 0.0)
        end
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
