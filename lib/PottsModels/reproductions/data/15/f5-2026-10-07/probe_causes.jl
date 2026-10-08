# P6.15e cause probe for the failing V4 rows (V4.2, V4.3, V4.5): case (b) with the TST division
# axis (minor axis, `@divide` default) and with a connectivity constraint, 20 runs each (seeds
# 15001–15020), same lattice, stop and guard as run_f5.jl. Output is quoted in README.md.
#     taskset -c 0-11,16-27 julia -t 12 --project=lib/PottsModels/test probe_causes.jl
using Potts, PottsModels
using Potts: CorePotts, @potts_model
using Statistics: mean
const L = 400
@potts_model PrMinor begin
    @kinds medium cell
    @parameters begin
        A₀ = 50.0; λ = 2.0; T = 20.0; α = 50 / 775; μ_X = 2.0; σ_X = 0.4; β = 0.0; γ = 0.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @variables begin
        A_star(cell) = A₀
        X(cell) = 0.0
        f(cell) = 1.0
    end
    @lattice Lattice((400, 400); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - A_star)^2
        contacts => J[kind, kind′]
    end
    @before_mcs X ~ ifelse(Pre(X) > 0, Pre(X), randn(μ_X, σ_X; lower = 0.0))
    @after_mcs begin
        f ~ ifelse(count(true for _ in contacts) > 0,
            count(kind′ == medium for _ in contacts) / count(true for _ in contacts), 1.0)
        A_star ~ ifelse((volume / Pre(A_star) >= β) && (f >= γ), Pre(A_star) + α, Pre(A_star))
    end
    @divide cells(cell) when = volume >= X * A₀, A_star => Split(), X => randn(μ_X, σ_X; lower = 0.0)
    @sweep Metropolis(; temperature = T)
end

@potts_model PrConn begin
    @kinds medium cell
    @parameters begin
        A₀ = 50.0; λ = 2.0; T = 20.0; α = 50 / 775; μ_X = 2.0; σ_X = 0.4; β = 0.0; γ = 0.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @variables begin
        A_star(cell) = A₀
        X(cell) = 0.0
        f(cell) = 1.0
    end
    @lattice Lattice((400, 400); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - A_star)^2
        contacts => J[kind, kind′]
    end
    @before_mcs X ~ ifelse(Pre(X) > 0, Pre(X), randn(μ_X, σ_X; lower = 0.0))
    @after_mcs begin
        f ~ ifelse(count(true for _ in contacts) > 0,
            count(kind′ == medium for _ in contacts) / count(true for _ in contacts), 1.0)
        A_star ~ ifelse((volume / Pre(A_star) >= β) && (f >= γ), Pre(A_star) + α, Pre(A_star))
    end
    @divide cells(cell) when = volume >= X * A₀, along = RandomPlane(), A_star => Split(), X => randn(μ_X, σ_X; lower = 0.0)
    @constraint connectivity(cell; rule = :arc_or_pair)
    @sweep Metropolis(; temperature = T)
end

for (variant, axis_minor, conn) in (("minor_axis", true, false), ("connectivity", false, true))
    sys = axis_minor ? PrMinor(; name = :prminor) : PrConn(; name = :prconn)
    prob = PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000); capacity = 1500, seed = 1)
    res = Vector{Any}(undef, 20)
    t = @elapsed Threads.@threads :dynamic for k in 1:20
        sol = solve(remake(prob; seed = 15_000 + k), SequentialCPM(; proposal = Moore(1));
            callback = CorePotts.CallbackSet(PottsModels.stop_at_cells(1000), PottsModels.edge_guard(5; terminate = true)))
        res[k] = PottsModels.openvt_snapshot(sol.u[end])
    end
    f = reduce(vcat, [r.f for r in res]); a = reduce(vcat, [r.a for r in res])
    nz = filter(>(0), f)
    h = [count(x -> lo <= x < lo + 0.05, nz) for lo in 0:0.05:0.95]
    println(variant, " wall ", round(t), " s: n ", length(f), " f0 ", round(mean(==(0), f); digits = 4),
        " meanf ", round(mean(f); digits = 4), " maxf ", round(maximum(f); digits = 3), " frac nz f>0.56 ",
        round(mean(>(0.56), nz); digits = 4), " meana ", round(mean(a); digits = 4), " mina ", round(minimum(a); digits = 3),
        " maxa ", round(maximum(a); digits = 3), " n a<0.42 ", count(<(0.42), a))
    println("   nonzero f per 0.05: ", h)
end
