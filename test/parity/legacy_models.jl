# Merks and Wortel parity against legacy samples (ROADMAP M2.5/M2.6, D-022): per saved MCS,
# two-sample KS of cell volumes and field/activity summaries over 64 + 64 seeds.
include(joinpath(@__DIR__, "models.jl"))

function read_legacy(name)
    path = joinpath(@__DIR__, "..", "..", "reference", "data", "$(name)_parity.tsv")
    lines = filter(l -> !startswith(l, "#"), readlines(path))
    header = Symbol.(split(lines[1], '\t'))
    rows = [NamedTuple{Tuple(header)}(Tuple(parse.(Float64, split(l, '\t')))) for l in lines[2:end]]
    return rows
end

function new_samples(problem, quantity, times, seeds)
    rows = NamedTuple[]
    for seed in seeds
        sol = solve(problem(; tspan = (0, maximum(times)), seed), SequentialCPM(; proposal = Moore(1));
            saveat = times, save_start = false)
        for (t, u) in zip(sol.t, sol.u)
            q = quantity === nothing ? [0.0] : getproperty(u.site, quantity)
            push!(rows, (; mcs = t, volume1 = count(==(1), u.σ), volume2 = count(==(2), u.σ),
                qsum = sum(q), qmax = maximum(q), ncells = length(unique(filter(>(0), vec(u.σ))))))
        end
    end
    return rows
end

@testset "legacy parity: $name" for (name, problem, quantity) in (
        ("merks", merks_problem, :c), ("wortel", wortel_problem, :act))
    legacy = read_legacy(name)
    times = filter(>(0), sort(unique(Int[r.mcs for r in legacy])))
    nseeds = length(unique(r.seed for r in legacy))
    new = new_samples(problem, quantity, times, 10_001:(10_000 + nseeds))
    qname = Symbol(name == "merks" ? "concentration" : "activity")
    for t in times, (lk, nk) in ((:volume1, :volume1), (:volume2, :volume2),
            (Symbol(qname, :_sum), :qsum), (Symbol(qname, :_max), :qmax))
        x = [getproperty(r, lk) for r in legacy if r.mcs == t]
        y = [Float64(getproperty(r, nk)) for r in new if r.mcs == t]
        all(iszero, x) && all(iszero, y) && continue
        D = ks(x, y)
        ok = D < ks_critical(length(x), length(y))
        ok || @warn "parity" name t observable = lk legacy = mean(x) new = mean(y) D
        @test ok
    end
end

@testset "legacy parity: openvt (division)" begin
    legacy = read_legacy("openvt")
    times = sort(unique(Int[r.mcs for r in legacy]))
    nseeds = length(unique(r.seed for r in legacy))
    new = new_samples(openvt_problem, nothing, times, 10_001:(10_000 + nseeds))
    for t in times, k in (:volume1, :volume2, :ncells)
        x = [getproperty(r, k) for r in legacy if r.mcs == t]
        y = [Float64(getproperty(r, k)) for r in new if r.mcs == t]
        D = ks(x, y)
        ok = D < ks_critical(length(x), length(y))
        ok || @warn "parity" t observable = k legacy = mean(x) new = mean(y) D
        @test ok
    end
end
