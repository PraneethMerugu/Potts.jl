# Diagnostic for spec 09 V-PRE5 (not a verdict run): late dark-cluster coarsening on the
# P6.1f fixture (graner_glazier_aggregate(1000; seed, margin = 60), 347² periodic), from the
# Voronoi start and from its one-type relaxed copy (PRE §II D3: J_ll = 2, J_lM = 8, T = 5,
# 400 paper MCS), independent seeds 11..(10+NREP), to 2×10⁴ paper MCS.
using Potts, PottsModels
const PAPER_MCS = 16
const NREP = parse(Int, get(ENV, "NREP", "6"))
const T_END = parse(Int, get(ENV, "T_END", "20000"))
ts = filter(<=(T_END), [10, 100, 1000, 2000, 3000, 4000, 5000, 6400, 8000, 10_000, 13_500, 16_000, 20_000])

function bond_counts(σ, k)
    n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]
        b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        a == 0 && ((a, b) = (b, a))
        key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
        n[key] += 1
    end
    return n
end
function annealed(σ, k; seed = 1)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(σ)),
        [ownership => copy(σ), kind => k, :T => 0.0], (0, 2PAPER_MCS); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 2PAPER_MCS).u[end])
end
function cell_areas(σ, k)
    a = zeros(Int, length(k))
    for c in σ
        c > 0 && (a[c] += 1)
    end
    return a
end
function root!(parent, c)
    while parent[c] != c
        parent[c] = parent[parent[c]]
        c = parent[c]
    end
    return c
end
function dark_clusters(σ, k)      # copied from the frozen page
    parent = collect(eachindex(k))
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a, b = σ[x, y], σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        (a == b || a == 0 || b == 0 || k[a] != 1 || k[b] != 1) && continue
        parent[root!(parent, a)] = root!(parent, b)
    end
    a = cell_areas(σ, k)
    size_of = Dict{Int, Int}()
    for c in eachindex(k)
        (k[c] == 1 && a[c] > 0) || continue
        r = root!(parent, c)
        size_of[r] = get(size_of, r, 0) + 1
    end
    return length(size_of), maximum(values(size_of)) / sum(values(size_of))
end

alg = SequentialCPM(; proposal = Moore(1))
jobs = [(i, relaxed) for i in 11:(10 + NREP) for relaxed in (false, true)]
res = Vector{Any}(undef, length(jobs))
Threads.@threads for j in eachindex(jobs)
    i, relaxed = jobs[j]
    σ0, k0 = graner_glazier_aggregate(1000; seed = i, margin = 60)
    gg = GranerGlazier(; name = Symbol(:gg, j), lattice = size(σ0))
    if relaxed
        r = PottsProblem(gg, [ownership => σ0, kind => fill(eltype(k0)(2), length(k0)), :J => [0 8 8; 8 2 2; 8 2 2], :T => 5.0],
            (0, 400PAPER_MCS); seed = 500 + i)
        σ0 = ownership(solve(r, alg; saveat = 400PAPER_MCS).u[end])
    end
    q = PottsProblem(gg, [ownership => σ0, kind => k0], (0, PAPER_MCS * last(ts)); seed = 100 + i)
    sol = solve(q, alg; saveat = PAPER_MCS .* ts)
    rows = map(ts) do t
        σ = ownership(sol.u[findfirst(==(PAPER_MCS * t), sol.t)])
        σa = annealed(σ, k0)
        b = bond_counts(σa, k0)
        N = sum(values(b))
        nc, big = dark_clusters(σa, k0)
        (t, b[:dl] / N, b[:dM] / N, nc, big)
    end
    res[j] = (i, relaxed, rows)
    @info "done" i relaxed
end
open(joinpath(@__DIR__, "diag5_out.tsv"), "w") do io
    println(io, "seed\trelaxed\tt\tF_dl\tF_dM\tdark_clusters\tlargest")
    for (i, relaxed, rows) in res, r in rows
        println(io, join((i, relaxed, r[1], round(r[2]; digits = 5), round(r[3]; digits = 5), r[4], round(r[5]; digits = 4)), '\t'))
    end
end
