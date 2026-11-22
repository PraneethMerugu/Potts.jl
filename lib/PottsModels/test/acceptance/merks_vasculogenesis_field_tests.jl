# The field of `MerksVasculogenesis` against a hand-written explicit Euler.
#
# The model (lib/PottsModels/src/merks.jl, docs/models/merks.jl) states its field step:
# `∂c/∂t = Dc Δc + σc δ_cell − δc c δ_medium` with the 5-point Laplacian, zero flux at the
# faces of the closed lattice and no border ring, 15 explicit substeps per MCS clipped at
# `c ≥ 0` (`ExplicitEuler(substeps = 15, lower_bound = 0.0)`), and no `@schedule`, so the
# field step comes after the sweep and sees the σ that the sweep left. The oracle is
# `merks_split_field` (shared/merks_field_oracle.jl), the one the `Merks2006` and
# `Merks2008` field tests use, with the clip on and the ring off.
#
# Negative controls, each of which must miss the oracle: no clip, 14 and 16 substeps, the
# field step before the sweep, and the authors' absorbing border (c = 0 on the outer ring)
# in place of the zero-flux faces. The start holds negative values in the medium, so the
# field without the clip goes negative and the clip acts.

@testsetup module MerksVasculogenesisFieldSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "shared", "merks_field_oracle.jl"))
const DIMS = (20, 20)
const CLIPPED = ExplicitEuler(substeps = 15, lower_bound = 0.0)
# three endothelial cells, the first on the x = 1 face
const BLOCKS = (
    [(x, y) for x in 1:4 for y in 4:9],
    [(x, y) for x in 11:14 for y in 8:12],
    [(x, y) for x in 6:9 for y in 14:17],
)
function start_sigma()
    σ = zeros(Int32, DIMS)
    for (k, b) in enumerate(BLOCKS), x in b
        σ[x...] = k
    end
    return σ
end
# a positive pattern, with c = −0.2 on every fifth medium site
function start_field(σ)
    return [
        σ[x, y] == 0 && (x + 2y) % 5 == 0 ? -0.2 : 0.05 + 0.01 * ((7x + 3y) % 9)
            for x in 1:DIMS[1], y in 1:DIMS[2]
    ]
end
# kind codes for the oracle: 0 medium, 1 endothelial (there is no frame)
kind_code(c) = c == 0 ? 0 : 1
field(u) = Float64.(Array(u.site.c))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "MerksVasculogenesis field: 15 clipped explicit substeps after the sweep, zero \
    flux at the faces" setup = [MerksVasculogenesisFieldSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    σ0 = start_sigma()
    c0 = start_field(σ0)
    op = [ownership => σ0, kind => fill(:endothelial, length(BLOCKS)), :c => c0]
    prob = PottsProblem(
        MerksVasculogenesis(; name = :m, lattice = DIMS), [op; :T => 200.0], (0, 4);
        field_solver = CLIPPED, seed = 7
    )
    p = (; Dc = prob.p.Dc, α = prob.p.σc, ε = prob.p.δc)
    sol = solve(prob, SequentialCPM(); saveat = 1)
    @test field(sol.u[1]) == c0
    outer = [x in (1, DIMS[1]) || y in (1, DIMS[2]) for x in 1:DIMS[1], y in 1:DIMS[2]]
    oracle(c, σ; kw...) = merks_split_field(c, σ, kind_code, p; clamp = false, kw...)
    errs = Dict(
        k => 0.0 for k in (:right, :no_clip, :n14, :n16, :before_sweep, :absorbing)
    )
    for k in 1:4
        u, u′ = sol.u[k], sol.u[k + 1]
        c, c′, σ′ = field(u), field(u′), Array(u′.ownership)
        @test all(>=(0.0), c′)
        for (key, want) in (
                :right => oracle(c, σ′; lower_bound = 0.0),
                :no_clip => oracle(c, σ′),
                :n14 => oracle(c, σ′; n = 14, lower_bound = 0.0),
                :n16 => oracle(c, σ′; n = 16, lower_bound = 0.0),
                :before_sweep => oracle(c, Array(u.ownership); lower_bound = 0.0),
                :absorbing => merks_split_field(
                    c, σ′, kind_code, p; lower_bound = 0.0, ring = outer
                ),
            )
            errs[key] = max(errs[key], maximum(abs, c′ .- want))
        end
    end
    @test errs[:right] < 1.0e-12
    # negative controls: each misses the oracle by far more than its tolerance
    @test errs[:no_clip] > 1.0e-3
    @test errs[:n14] > 1.0e-6 && errs[:n16] > 1.0e-6
    @test errs[:before_sweep] > 1.0e-4
    @test errs[:absorbing] > 1.0e-3
    # the clip is not vacuous: without it the first MCS leaves negative values
    @test minimum(oracle(c0, Array(sol.u[2].ownership))) < -1.0e-3
    # the phase-order control is not vacuous: the cells moved in every MCS
    @test all(k -> Array(sol.u[k].ownership) != Array(sol.u[k + 1].ownership), 1:4)
end
