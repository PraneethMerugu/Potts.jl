# Reviewer probe (P6.1h review; not a record). 4 threads.
using Potts, PottsModels
const PM = 16
function bond_counts(σ, k)
    n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        a == 0 && ((a, b) = (b, a))
        key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
        n[key] += 1
    end
    n
end
function annealed(σ, k, run; seed = 1)
    top = maximum(σ); top == 0 && return copy(σ)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(σ)),
        [ownership => copy(σ), kind => k[1:top], :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 2PM); seed)
    ownership(solve(q, SequentialCPM(); saveat = 2PM).u[end])
end
alive(σ, k) = (s = Set(σ); (count(c -> k[c] == 1 && c in s, eachindex(k)), count(c -> k[c] == 2 && c in s, eachindex(k))))
# fragmentation: per cell, VN components; share of cells in >1 piece, share of cell sites outside largest piece
function frag(σ)
    nx, ny = size(σ); lab = zeros(Int, nx, ny); comp = Dict{Int, Vector{Int}}()
    id = 0
    for y in 1:ny, x in 1:nx
        c = σ[x, y]; (c == 0 || lab[x, y] != 0) && continue
        id += 1; sz = 0; stack = [(x, y)]; lab[x, y] = id
        while !isempty(stack)
            (i, j) = pop!(stack); sz += 1
            for (di, dj) in ((1,0),(-1,0),(0,1),(0,-1))
                u, v = mod1(i + di, nx), mod1(j + dj, ny)
                (σ[u, v] == c && lab[u, v] == 0) && (lab[u, v] = id; push!(stack, (u, v)))
            end
        end
        push!(get!(comp, c, Int[]), sz)
    end
    multi = count(v -> length(v) > 1, values(comp)) / max(1, length(comp))
    tot = sum(sum, values(comp)); out = sum(v -> sum(v) - maximum(v), values(comp))
    (multi, out / tot)
end
mode = ARGS[1]
if mode == "units"
    # hand check of H on a tiny state: once-counted Moore bonds and λ(a−A)²
    σ = zeros(Int32, 8, 8); σ[3:4, 3:5] .= 1; σ[5:6, 3:4] .= 2
    k = Int32[1, 2]
    p = PottsProblem(GranerGlazier(; name = :u, lattice = (8, 8)), [ownership => σ, kind => k], (0, 1); seed = 1)
    J = [0 16 16; 16 2 11; 16 11 14]
    hand(σ, areas) = (H = 0.0; for y in 1:8, x in 1:8, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[mod1(x + dx, 8), mod1(y + dy, 8)]
        a == b && continue
        H += J[(a == 0 ? 1 : k[a] + 1), (b == 0 ? 1 : k[b] + 1)]
    end; H + sum((a - 40)^2 for a in areas))
    H = hand(σ, (6, 4))
    if false
    for y in 1:8, x in 1:8, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[mod1(x + dx, 8), mod1(y + dy, 8)]
        a == b && continue
        H += J[(a == 0 ? 1 : k[a] + 1), (b == 0 ? 1 : k[b] + 1)]
    end
    end
    println("units: total_energy = ", total_energy(p), "  hand (bonds once, λ(a-A)^2) = ", H)
    σ2 = copy(σ); σ2[2, 3] = 1   # one copy: medium site gains cell 1
    p2 = remake(p; u0 = [ownership => σ2, kind => k])
    H2 = hand(σ2, (7, 4))
    println("after copy: total_energy = ", total_energy(p2), " hand = ", H2)
elseif mode == "lambda"
    ts = [50, 100, 200, 500, 800, 1000]
    jobs = [(λ, s) for λ in (0.1, 0.2, 0.5) for s in (3001, 3002)]
    res = Vector{Any}(undef, length(jobs))
    Threads.@threads :dynamic for i in eachindex(jobs)
        λ, s = jobs[i]
        σ0, k0 = graner_glazier_aggregate(1000; seed = s, margin = 30)
        prob = PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ0)), [ownership => σ0, kind => k0, :T => 5.0, :λ => λ], (0, PM * last(ts)); seed = s + 10000)
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = PM .* ts)
        res[i] = [(t, alive(ownership(sol.u[findfirst(==(PM * t), sol.t)]), k0)) for t in ts]
    end
    for (j, r) in zip(jobs, res); println("lambda=", j[1], " seed=", j[2], " alive (dark, light) of (500,500): ", r); end
elseif mode == "hot"
    ts = [50, 100, 200, 500]
    jobs = [(T, λ) for (T, λ) in ((40.0, 1.0), (80.0, 1.0), (160.0, 1.0), (80.0, 0.5))]
    res = Vector{Any}(undef, length(jobs))
    Threads.@threads :dynamic for i in eachindex(jobs)
        T, λ = jobs[i]
        σ0, k0 = graner_glazier_aggregate(1000; seed = 3001, margin = 60)
        prob = PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ0)), [ownership => σ0, kind => k0, :T => T, :λ => λ], (0, PM * last(ts)); seed = 13001)
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = PM .* ts)
        out = []
        for t in ts
            σ = ownership(sol.u[findfirst(==(PM * t), sol.t)])
            σa = annealed(σ, k0, prob)
            b = bond_counts(σa, k0); N = sum(values(b))
            push!(out, (t = t, raw_alive = alive(σ, k0), ann_alive = alive(σa, k0), Fdl_ann = round(b[:dl] / max(N, 1); digits = 3),
                frag_raw = round.(frag(σ); digits = 3), frag_ann = round.(frag(σa); digits = 3),
                medium_sites_in_aggregate_box = count(==(0), σ[100:248, 100:248])))
        end
        res[i] = out
    end
    for (j, r) in zip(jobs, res); println("T=", j[1], " λ=", j[2]); foreach(x -> println("   ", x), r); end
end
