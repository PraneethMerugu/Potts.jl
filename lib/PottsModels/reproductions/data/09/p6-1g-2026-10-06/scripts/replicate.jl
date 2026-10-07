# P6.1g (D-151; spec 09 §9.5): one replicate of the reproduction-09 FULL fixture, measured
# at a dense late save grid for the time to a single dark cluster. Not a verdict run; the
# frozen page is not touched. Measurement = the page's: a copy annealed 2 paper MCS at T = 0
# with the run's energies (seed 1), Moore bonds once, all mismatched bonds as denominator;
# `dark_clusters` copied verbatim from the page; isolation guard on the raw state.
#
# usage: julia --project=docs replicate.jl <outfile> <group> <ncells> <start_seed> <run_seed> <T> <Vd> <Vl> <t_end>
#   Vd == Vl == 40 → the published `GranerGlazier` (page parameters, T as given);
#   otherwise the per-kind target-area variant below (scan (b) only).
using Potts, PottsModels

const PAPER_MCS = 16
const MARGIN = 60

# Scan (b) variant: the published model with one target area per kind (cf. openvt_chain).
# Every other statement is GranerGlazier's.
@potts_model GranerGlazierSized begin
    @structural_parameters begin
        lattice = (72, 72)
    end
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V_d = 40.0
        V_l = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(dark) => λ * (volume - V_d)^2
        cells(light) => λ * (volume - V_l)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

out, group = ARGS[1], ARGS[2]
ncells, start_seed, run_seed = parse.(Int, ARGS[3:5])
T, Vd, Vl = parse.(Float64, ARGS[6:8])
t_end = parse(Int, ARGS[9])
ts = filter(<=(t_end), sort(unique([10, 100, 200, 500, collect(1000:500:20_000)...])))
sized = !(Vd == 40.0 && Vl == 40.0)

function make(σ, k, tspan, seed; Tval = T, name = :gg)
    if sized
        PottsProblem(GranerGlazierSized(; name, lattice = size(σ)),
            [ownership => copy(σ), kind => k, :T => Tval, :V_d => Vd, :V_l => Vl], tspan; seed)
    else
        PottsProblem(GranerGlazier(; name, lattice = size(σ)),
            [ownership => copy(σ), kind => k, :T => Tval], tspan; seed)
    end
end

# --- page helpers (verbatim from lib/PottsModels/reproductions/09_cell_sorting.jl) ---
function cell_areas(σ, k)
    a = zeros(Int, length(k))
    for c in σ
        c > 0 && (a[c] += 1)
    end
    return a
end
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
function root!(parent, c)
    while parent[c] != c
        parent[c] = parent[parent[c]]
        c = parent[c]
    end
    return c
end
function dark_clusters(σ, k)
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
isolated(σ) = any(x -> all(==(0), view(σ, x, :)), axes(σ, 1)) && any(y -> all(==(0), view(σ, :, y)), axes(σ, 2))
# annealed copy at T = 0 with the run's energies (page: seed = 1)
annealed(σ, k) = ownership(solve(make(σ, k, (0, 2PAPER_MCS), 1; Tval = 0.0, name = :anneal),
    SequentialCPM(); saveat = 2PAPER_MCS).u[end])
# ---

alg = SequentialCPM(; proposal = Moore(1))
σ0, k0 = graner_glazier_aggregate(ncells; seed = start_seed, margin = MARGIN)
prob = make(σ0, k0, (0, PAPER_MCS * last(ts)), run_seed)
solve(remake(prob; tspan = (0, 1)), alg)                # compile
wall = @elapsed sol = solve(prob, alg; saveat = PAPER_MCS .* ts)
mean_(v) = isempty(v) ? NaN : sum(v) / length(v)
open(out * ".part", "w") do io
    println(io, join(("group", "ncells", "start_seed", "run_seed", "T", "V_d", "V_l", "paper_mcs",
        "F_dl", "F_dd", "F_ll", "F_dM", "F_lM", "mismatched_bonds", "dark_clusters", "largest_dark_cluster",
        "isolated", "mean_area_dark", "mean_area_light", "alive_dark", "alive_light", "wall_s"), '\t'))
    for t in ts
        σ = ownership(sol.u[findfirst(==(PAPER_MCS * t), sol.t)])
        σa = annealed(σ, k0)
        b = bond_counts(σa, k0)
        N = sum(values(b))
        nc, big = dark_clusters(σa, k0)
        a = cell_areas(σ, k0)
        ad = [a[c] for c in eachindex(k0) if k0[c] == 1 && a[c] > 0]
        al = [a[c] for c in eachindex(k0) if k0[c] == 2 && a[c] > 0]
        println(io, join((group, ncells, start_seed, run_seed, T, Vd, Vl, t,
            (round(b[key] / N; digits = 5) for key in (:dl, :dd, :ll, :dM, :lM))..., N, nc, round(big; digits = 4),
            isolated(σ), round(mean_(ad); digits = 3), round(mean_(al); digits = 3), length(ad), length(al),
            round(wall; digits = 1)), '\t'))
    end
end
mv(out * ".part", out; force = true)
@info "done" out wall
