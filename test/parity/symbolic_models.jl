# The legacy parity models authored in the symbolic surface (AUTHORING.md): the generated
# code must reproduce the hand-written ports in `models.jl` exactly (same ΔH, commit and
# constraints on every proposal) and pass the legacy parity tests.
using Potts

@potts_model Sorting begin
    @structural_parameters begin
        lattice = (72, 72)
    end
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model WortelAct begin
    @structural_parameters begin
        lattice = (8, 8)
    end
    @kinds medium endothelial
    @parameters begin
        λ = 1.0
        V₀ = 6.0
        λₛ = 0.05
        S₀ = 8.0
        λ_act = 4.0
        max_act = 5.0
        T = 8.0
        J[kind, kind] = [0.0 6.0; 6.0 2.0]
    end
    @variables act(site) = 0.0
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(endothelial) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        contacts => J[kind, kind′]
    end
    act_mean(s) = geomean_shifted(act[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])
    @drive copy => ifelse(kind[new] == endothelial, -(λ_act / max_act) * (act_mean(source) - act_mean(target)), 0.0)
    @on_copy act[target] ~ ifelse((old == 0) && (new != 0), max_act, 0.0)
    @after_mcs act ~ max(Pre(act) - 1, 0)
    @constraint connectivity(endothelial; rule = :merks)
    @sweep Metropolis(; temperature = T)
end

@potts_model Merks begin
    @structural_parameters begin
        lattice = (8, 8)
    end
    @kinds medium endothelial
    @parameters begin
        λ = 1.0
        V₀ = 6.0
        χ = 2.0
        Dc = 0.08
        σc = 0.02
        δc = 0.01
        T = 6.0
    end
    @variables c(field) = 0.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy cells(endothelial) => λ * (volume - V₀)^2
    @drive copy => ifelse((old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]), 0.0)
    @equations D(c) ~ Dc * Δ(c) - δc * c + σc * (kind == endothelial)
    @constraint connectivity(endothelial; rule = :merks)
    @sweep Metropolis(; temperature = T, field_solver = ExplicitEuler(substeps = 2, lower = 0.0))
end

@potts_model Monolayer begin
    @structural_parameters begin
        lattice = (12, 8)
    end
    @kinds medium epithelial
    @parameters begin
        λ = 2.0
        V₀ = 8.0
        T = 2.0
        J[kind, kind] = [0.0 4.0; 4.0 0.0]
    end
    @variables mass(cell) = 8.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(epithelial) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @divide cells(epithelial) when = (mcs == 0) && (volume >= 8), along = (1.0, 0.0), mass => Split()
    @sweep Metropolis(; temperature = T)
end

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
