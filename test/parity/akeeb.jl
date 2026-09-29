# Akeeb leader/follower invasion: statistical parity with the legacy SCDPotts runner.
# Legacy samples: reference/data/akeeb_parity.tsv (reference/sample_akeeb.jl; 99×60,
# 400 MCS, J_LF = 2, motility 30, PP = 0.5). Metrics (reference/akeeb_metrics.jl) at
# MCS 200 (`*_mid`) and 400; each is tested with a two-sample Welch t, |t| < 4.
using Test, Potts, DelimitedFiles
using PottsModels: AkeebInvasion, akeeb_state
using Statistics: mean, std, var
include(joinpath(@__DIR__, "..", "..", "reference", "akeeb_metrics.jl"))

@testset "Akeeb invasion parity with legacy SCDPotts (Welch t, 16 seeds)" begin
    path = joinpath(@__DIR__, "..", "..", "reference", "data", "akeeb_parity.tsv")
    lines = filter(l -> !startswith(l, "#"), readlines(path))
    names = Symbol.(split(lines[1], '\t'))
    legacy = readdlm(IOBuffer(join(lines[2:end], '\n')), '\t', Float64)
    W, H, nmcs = 99, 60, 400
    new = map(2001:2016) do seed
        op = akeeb_state(; lattice = (W, H), seed)
        n0 = length(op[2].second)
        prob = PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (W, H)), op, (0, nmcs);
            capacity = 1000, seed)
        sol = solve(prob, SequentialCPM(; proposal = VonNeumann(1)); saveat = [nmcs ÷ 2, nmcs])
        mid = akeeb_metrics(sol.u[1].σ, sol.u[1].cell.kind .== 1, n0)
        fin = akeeb_metrics(sol.u[end].σ, sol.u[end].cell.kind .== 1, n0)
        m = (; seed, (Symbol(k, :_mid) => v for (k, v) in pairs(mid))..., fin...)
        [Float64(m[n]) for n in names]
    end
    for (j, name) in enumerate(names)
        name == :seed && continue
        x = legacy[:, j]; y = getindex.(new, j)
        if var(x) == 0 && var(y) == 0
            @test mean(x) == mean(y)
            continue
        end
        t = (mean(x) - mean(y)) / sqrt(var(x) / length(x) + var(y) / length(y))
        @info "akeeb parity" name legacy = (mean(x), std(x)) new = (mean(y), std(y)) t
        @test abs(t) < 4
    end
end
