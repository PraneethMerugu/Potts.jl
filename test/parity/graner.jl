# Graner–Glazier parity against the legacy reference samples (ROADMAP M2.1, D-022).
include(joinpath(@__DIR__, "..", "..", "benchmark", "models.jl"))
include(joinpath(@__DIR__, "observables.jl"))
using Statistics: mean, var

"""Two-sample Kolmogorov–Smirnov statistic."""
function ks(x, y)
    D = 0.0
    for v in vcat(x, y)
        D = max(D, abs(count(<=(v), x) / length(x) - count(<=(v), y) / length(y)))
    end
    return D
end
ks_critical(n, m; c = 1.95) = c * sqrt((n + m) / (n * m))    # α ≈ 0.001
welch(x, y) = (mean(x) - mean(y)) / sqrt(var(x) / length(x) + var(y) / length(y))

@testset "Graner–Glazier parity with legacy Potts (KS, 16 seeds)" begin
    path = joinpath(@__DIR__, "..", "..", "reference", "data", "graner_parity.tsv")
    lines = filter(l -> !startswith(l, "#"), readlines(path))
    names = Symbol.(split(lines[1], '\t'))
    legacy = [parse.(Float64, split(l, '\t')) for l in lines[2:end]]
    σ, kinds = graner_state()
    prob = graner_problem(; nmcs = 320)
    new = map(1001:(1000 + length(legacy))) do seed
        sol = solve(remake(prob; seed), SequentialCPM(; proposal = Moore(1)); save_start = false)
        collect(Float64, values(observables(sol.u[end].σ, kinds)))
    end
    for (j, name) in enumerate(names)
        name == :alive && continue          # legacy forbids extinction; compare separately
        x = getindex.(legacy, j); y = getindex.(new, j)
        D = ks(x, y); t = welch(x, y)
        @info "parity" name legacy = mean(x) new = mean(y) D t
        @test D < ks_critical(length(x), length(y))
        @test abs(t) < 4
    end
    @test all(r -> r[end] == 64, new)       # no extinction at these parameters
end
