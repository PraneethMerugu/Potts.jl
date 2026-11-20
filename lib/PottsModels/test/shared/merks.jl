using Potts, PottsModels, Test
using Statistics: mean, std
const FULLREPRO = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const RSOLVER = ExplicitEuler(substeps = 15)
# ---------------------------------------------------------------------------------------------
# Observables
# ---------------------------------------------------------------------------------------------
const MERKS_R8 = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
const MERKS_R4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]
merks_cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
"""Area of the convex hull of integer points (Andrew's monotone chain, shoelace); 0 for < 3
non-collinear points."""
function hull_area(pts)
    P = sort(unique(pts))
    length(P) < 3 && return 0.0
    chain(Q) = foldl(Q; init = eltype(Q)[]) do h, q
        while length(h) >= 2 && merks_cross(h[end - 1], h[end], q) <= 0
            pop!(h)
        end
        push!(h, q)
    end
    h = [chain(P)[1:(end - 1)]; chain(reverse(P))[1:(end - 1)]]
    length(h) < 3 && return 0.0
    return abs(sum(k -> h[k][1] * h[mod1(k + 1, end)][2] - h[mod1(k + 1, end)][1] * h[k][2], eachindex(h))) / 2
end
"""O1: TST compactness (σ: 0 medium, 1 frame, ≥ 2 endothelial)."""
merks_compactness(σ) = (pts = [(I[1], I[2]) for I in findall(>=(2), σ)]; length(pts) / hull_area(pts))
function components(mask, offs)
    X, Y = size(mask)
    lab = zeros(Int, X, Y)
    sizes = Int[]
    stack = Tuple{Int, Int}[]
    for x in 1:X, y in 1:Y
        (mask[x, y] && lab[x, y] == 0) || continue
        push!(sizes, 0)
        k = length(sizes)
        lab[x, y] = k
        push!(stack, (x, y))
        while !isempty(stack)
            i, j = pop!(stack)
            sizes[k] += 1
            for (a, b) in offs
                p, q = i + a, j + b
                (1 <= p <= X && 1 <= q <= Y && mask[p, q] && lab[p, q] == 0) || continue
                lab[p, q] = k
                push!(stack, (p, q))
            end
        end
    end
    return sizes, lab
end
"""O2 and O3."""
function merks_network(σ)
    occ, _ = components(σ .>= 2, MERKS_R8)
    med, lab = components(σ .== 0, MERKS_R4)
    touch = falses(length(med))
    X, Y = size(σ)
    for x in 1:X, y in 1:Y
        σ[x, y] == 1 || continue
        for (a, b) in MERKS_R4
            p, q = x + a, y + b
            (1 <= p <= X && 1 <= q <= Y && lab[p, q] > 0) && (touch[lab[p, q]] = true)
        end
    end
    share = isempty(occ) ? 0.0 : maximum(occ) / sum(occ)
    return (; share, lacunae = count(k -> !touch[k] && med[k] >= 10, eachindex(med)))
end
"""O4."""
isnetwork(r) = r.share >= 0.9 && r.lacunae >= 3
"""Centroids of cells 2:maximum(σ) (NaN for an empty cell)."""
function centroids(σ)
    n = Int(maximum(σ))
    sx, sy, m = zeros(n), zeros(n), zeros(Int, n)
    for I in CartesianIndices(σ)
        c = σ[I]
        c >= 2 || continue
        sx[c] += I[1]; sy[c] += I[2]; m[c] += 1
    end
    return [(sx[c] / m[c], sy[c] / m[c]) for c in 2:n]
end
"""O5, in sites (× 2 µm)."""
merks_displacement(σ0, σ1) = mean(((a, b),) -> hypot(b[1] - a[1], b[2] - a[2]), zip(centroids(σ0), centroids(σ1)))
"""O6 over a vector of σ's saved at equal intervals: (Σ par², Σ perp²)."""
function merks_anisotropy(σs)
    par = perp = 0.0
    for k in 1:(length(σs) - 1)
        a, b = σs[k], σs[k + 1]
        for c in 2:Int(maximum(a))
            A, B = findall(==(c), a), findall(==(c), b)
            (isempty(A) || isempty(B)) && continue
            ma = (mean(I[1] for I in A), mean(I[2] for I in A))
            mb = (mean(I[1] for I in B), mean(I[2] for I in B))
            sxx = mean((I[1] - ma[1])^2 for I in A)
            syy = mean((I[2] - ma[2])^2 for I in A)
            sxy = mean((I[1] - ma[1]) * (I[2] - ma[2]) for I in A)
            λ = (sxx + syy) / 2 + sqrt(((sxx - syy) / 2)^2 + sxy^2)
            e = if abs(sxy) > 1.0e-12
                (λ - syy, sxy)
            elseif sxx >= syy
                (1.0, 0.0)
            else
                (0.0, 1.0)
            end
            e = e ./ hypot(e...)
            d = mb .- ma
            pa = (d[1] * e[1] + d[2] * e[2])^2
            par += pa
            perp += d[1]^2 + d[2]^2 - pa
        end
    end
    return par, perp
end
# ---------------------------------------------------------------------------------------------
# Runs
# ---------------------------------------------------------------------------------------------
"""One 2006 run: final σ's at the save times (MCS)."""
function run06(seed, saves; lattice = (500, 500), n = 282, p = Pair[])
    op = layout(merks2006_layout(; lattice, n, seed), lattice)
    prob = PottsProblem(Merks2006(; name = :m6, lattice), [op; p...], (0, maximum(saves)); field_solver = RSOLVER, seed)
    sol = solve(prob, SequentialCPM(); saveat = saves)
    return Dict(Int(t) => Array(u.ownership) for (t, u) in zip(sol.t, sol.u))
end
"""One 2008 sprout run (or the paper de novo start): σ's at the save times (MCS)."""
function run08(seed, saves; p = Pair[], mode = :extension_retraction, denovo = false)
    lattice = denovo ? (502, 502) : (202, 202)
    l = denovo ? merks2008_denovo(; lattice, n = 1000, region = (85:417, 85:417), seed) : merks2008_sprout(; seed)
    op = layout(l, lattice)
    prob = PottsProblem(Merks2008(; name = :m8, lattice, mode), [op; p...], (0, maximum(saves)); field_solver = RSOLVER, seed)
    sol = solve(prob, SequentialCPM(); saveat = saves)
    return Dict(Int(t) => Array(u.ownership) for (t, u) in zip(sol.t, sol.u))
end
"""O6 of isolated cells without chemotaxis (9 cells of 10² over 120² of a framed 160²)."""
function merks_walk(seed; p = Pair[], tend = 2000)
    G = (160, 160)
    op = layout(merks2006_layout(; lattice = G, region = (120, 120), n = 9, seed), G)
    prob = PottsProblem(
        Merks2006(; name = :m6, lattice = G), [op; :χcM => 0.0; :χcc => 0.0; p...], (0, tend);
        field_solver = RSOLVER, seed
    )
    sol = solve(prob, SequentialCPM(); saveat = 200:10:tend)          # the first 200 MCS relax the squares
    par, perp = merks_anisotropy([Array(u.ownership) for u in sol.u])
    return par / perp
end
# a crossing of y(x) through `level` by linear interpolation, the first one (nothing if none)
function crossing(xs, ys, level)
    for k in 1:(length(xs) - 1)
        a, b = ys[k] - level, ys[k + 1] - level
        a == 0 && return xs[k]
        a * b < 0 && return xs[k] + (xs[k + 1] - xs[k]) * a / (a - b)
    end
    return nothing
end
# ---------------------------------------------------------------------------------------------
# FULL (offline; POTTS_FULL_REPRODUCTION=true)
# ---------------------------------------------------------------------------------------------
tmap(f, xs) = (
    out = Vector{Any}(undef, length(xs)); Threads.@threads(
        for i in eachindex(xs)
            out[i] = f(xs[i])
        end
    ); out
)
