# The published models from lib/PottsModels: the generated code must reproduce the
# hand-written CorePotts ports in `models.jl` exactly (same ΔH, commit and constraints on
# every proposal; test/symbolic.jl).
using Potts, PottsModels

# The published models come from lib/PottsModels (M3.3 acceptance: parity from its sources).
const Sorting = GranerGlazier
const Merks = MerksVasculogenesis
const Monolayer = SingleDivisionFixture

const SORTING = mtkcompile(Sorting(; name = :sorting))
const WORTEL = mtkcompile(WortelAct(; name = :wortel, lattice = (16, 16)))
const MERKS = mtkcompile(Merks(; name = :merks, lattice = (12, 12)))
const MONOLAYER = mtkcompile(Monolayer(; name = :monolayer))

function symbolic_graner_problem(; nmcs = 100, seed = 97329219, T = Float64)
    σ, kinds = graner_state()
    return PottsProblem(SORTING, [ownership => σ, kind => kinds], (0, nmcs); seed, T)
end
function symbolic_wortel_problem(; tspan = (0, 40), seed = 0)
    σ = wortel_state()
    q = WORTEL_PORT_P
    return PottsProblem(WORTEL, [ownership => σ, kind => [:cell, :cell], :J => Matrix(q.J), :λ => q.λ, :V₀ => q.V0,
        :λₛ => q.λs, :S₀ => q.S0, :λ_act => q.λact, :max_act => q.maxact, :T => q.T], tspan; seed)
end
function symbolic_merks_problem(; tspan = (0, 40), seed = 0)
    q = MERKS_PORT_P
    return PottsProblem(MERKS, [ownership => merks_state(), kind => [:endothelial, :endothelial], :J => Matrix(q.J),
        :λ => q.λ, :V₀ => q.V0, :λ_L => q.λL, :L => q.L, :χ => q.χ, :Dc => q.D, :σc => q.s, :δc => q.k, :T => q.T],
        tspan; seed)
end
function symbolic_openvt_problem(; tspan = (0, 20), seed = 0)
    σ = zeros(Int32, 12, 8); σ[5:8, 4:5] .= 1
    return PottsProblem(MONOLAYER, [ownership => σ, kind => [:epithelial]], tspan; seed, capacity = 8)
end
