# The legacy parity models, authored in the symbolic surface (lib/PottsModels): the generated
# code must reproduce the hand-written ports in `models.jl` exactly (same ΔH, commit and
# constraints on every proposal) and pass the legacy parity tests.
using Potts, PottsModels

# The published models come from lib/PottsModels (M3.3 acceptance: parity from its sources).
const Sorting = GranerGlazier
const Merks = MerksVasculogenesis
const Monolayer = OpenVTMonolayer

const SORTING = mtkcompile(Sorting(; name = :sorting))
const WORTEL = mtkcompile(WortelAct(; name = :wortel))
const MERKS = mtkcompile(Merks(; name = :merks))
const MONOLAYER = mtkcompile(Monolayer(; name = :monolayer))

function symbolic_graner_problem(; nmcs = 100, seed = 97329219, T = Float64)
    σ, kinds = graner_state()
    return PottsProblem(SORTING, [ownership => σ, kind => kinds], (0, nmcs); seed, T)
end
function symbolic_wortel_problem(; tspan = (0, 40), seed = 0)
    σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1; σ[6:7, 6:7] .= 2
    return PottsProblem(WORTEL, [ownership => σ, kind => [:endothelial, :endothelial]], tspan; seed)
end
function symbolic_merks_problem(; tspan = (0, 40), seed = 0)
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
    return PottsProblem(MERKS, [ownership => σ, kind => [:endothelial]], tspan; seed)
end
function symbolic_openvt_problem(; tspan = (0, 20), seed = 0)
    σ = zeros(Int32, 12, 8); σ[5:8, 4:5] .= 1
    return PottsProblem(MONOLAYER, [ownership => σ, kind => [:epithelial]], tspan; seed, capacity = 8)
end
