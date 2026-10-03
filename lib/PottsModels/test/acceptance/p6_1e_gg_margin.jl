# P6.1e (ROADMAP Phase 6, step 1): `graner_glazier_aggregate`'s default medium margin.
# Frozen (AUTONOMY §7.3).
#
# Problem: the default margin is 10 sites. `GranerGlazier` is periodic (the paper does not
# say; topology-neighborhood-audit §3.1 row 2, §5), so over a long sorting run the aggregate
# reaches the lattice edge and wraps across it (and, in the 10⁴-paper-MCS paper run, joins
# its periodic image). The paper run (`docs/paper_runs/graner_glazier.jl`) uses margin 60.
# Fix (implementer): raise the default margin to ≥ 60 sites and keep the periodic lattice.
#
# Size formula today (lib/PottsModels/src/graner_glazier.jl):
#     L = 2ceil(Int, sqrt(40n / π)) + 1 + 2margin,      size(σ) == (L, L)
# The tests below require the default to be a single margin M ≥ 60 in that formula, the same
# for every n, and the default call to be bitwise the explicit `margin = M` call.
#
# Margin, as measured here: for a cell site at (i, j) on an L×L lattice, its distance to the
# lattice edge is min(i - 1, L - i, j - 1, L - j) (the number of medium rows/columns between
# it and the edge). "Margin ≥ m on every side" = that minimum over all cell sites is ≥ m.
#
# Criterion of the long run (testset 3). At every saved frame (every 100 MCS) no cell site
# lies on the outermost rows or columns of the lattice (edge distance ≥ 1). A site on row 1
# is Moore-adjacent across the periodic seam to row L, so this is the condition that no cell
# wraps across the boundary and no cell site touches anything across it. Measured on today's
# code (b011b772), n = 200 aggregate (seed 1), run seed 16, 25 000 MCS:
#   - margin 10 (123²): edge distance 11 at t = 0, first 0 at t = 22 800 (aggregate drift);
#     it stays at 0 to 30 000. Of 17 run seeds scanned (1:17) at margin 10, three reach the
#     edge within 40 000 MCS (2 at 30 900, 3 at 29 000, 16 at 22 800); seed 16 is the
#     earliest, so the control is short. Its run length leaves 2 200 MCS of slack.
#   - margin 60 (223²), same seeds: minimum edge distance 55 over the 25 000 MCS.
# What moves the aggregate to the edge at this length is whole-aggregate drift, not shape
# change: the circular medium gap between the aggregate and its periodic image (the longest
# run of empty rows/columns around the torus) never fell below 10 in these margin-10 runs
# (n = 200, 40 000 MCS, seeds 1–3), nor below 12 for n = 1000 over 30 000 MCS. The image
# join seen in the paper run (n = 1000, 160 000 MCS) is out of reach of a ≤ 60 s test; the
# edge criterion is the one this length can show. The test also checks that gap stays ≥ 1.
#
# Cost (one CPU thread): the control ≈ 11 s, the default run ≈ 23 s at margin 60 (more for a
# larger default margin: the lattice grows as (L)²).
#
# Digests (testset 2): computed on today's code (b011b772) by /tmp/p61e/digests_today.jl:
# SHA-256 of σ's little-endian Int32 bytes (column-major), SHA-256 of the kinds joined by ','.

using SHA: sha256

p61e_σdigest(σ) = bytes2hex(sha256(reinterpret(UInt8, vec(htol.(Int32.(σ))))))
p61e_kdigest(k) = bytes2hex(sha256(join(string.(k), ",")))
p61e_core(n) = 2ceil(Int, sqrt(40n / π)) + 1                  # lattice side minus 2margin

function p61e_edge(σ)                                          # min edge distance of a cell site
    L1, L2 = size(σ)
    d = typemax(Int)
    for x in CartesianIndices(σ)
        σ[x] == 0 && continue
        i, j = Tuple(x)
        d = min(d, i - 1, L1 - i, j - 1, L2 - j)
    end
    return d
end

function p61e_circgap(occ::AbstractVector{Bool})               # longest circular run of `false`
    L = length(occ)
    all(!, occ) && return L
    best = run = 0
    for i in 1:(2L)
        occ[mod1(i, L)] ? (run = 0) : (run += 1; best = max(best, run))
    end
    return min(best, L)
end
p61e_imagegap(σ) = (c = σ .!= 0; min(p61e_circgap(vec(any(c; dims = 2))), p61e_circgap(vec(any(c; dims = 1)))))

const P61E_DIGESTS = Dict(   # (n, seed, margin) => (side, σ digest, kinds digest), today b011b772
    (200, 1, 10) => (123, "637e070aa6101222a7ddb7ea9c45f4688de5c9599cac29ba0c22d177db43b142",
        "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b"),
    (200, 1, 60) => (223, "5f0e638e089f8bea167ff9f8589a4b39001f799eea3303bddb896d768dcb7dea",
        "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b"),
    (200, 2, 10) => (123, "6b969ec2c140b940684fbe15d9e311fb53d70bdf1f46ba360f29f917ec4dee4e",
        "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b"),
    (200, 2, 60) => (223, "441c36578744e3a77612e35ac9f576ee3cf09fda37f671b354f0d783e72d0927",
        "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b"),
    (1000, 1, 10) => (247, "8af14647277b7b4d0aa49bb4da445b967efb3f89edafa0657e4cee178905ef1f",
        "1be89756b456ad17a13888210217cb977b9ebe409e93344a6ce3d8b5a8d7144f"),
    (1000, 1, 60) => (347, "d76c8f3d55eda46ed8fe83c3685098d90dacd9d64798bb96e58797636bda0df7",
        "1be89756b456ad17a13888210217cb977b9ebe409e93344a6ce3d8b5a8d7144f"),
    (1000, 2, 10) => (247, "84e02b13946c1b118c2618d8ac183a77f35d64f89c9494e6113171f4f81dae26",
        "1be89756b456ad17a13888210217cb977b9ebe409e93344a6ce3d8b5a8d7144f"),
    (1000, 2, 60) => (347, "dce2fe1ef87eb45927798422902dad338971d3b3d3a6d7e02962799dbec14f5e",
        "1be89756b456ad17a13888210217cb977b9ebe409e93344a6ce3d8b5a8d7144f"))

# The long run of testset 3: n = 200 (seed 1), run seed 16, 25 000 MCS, frames every 100 MCS.
const P61E_RUN = (n = 200, seed = 1, run_seed = 16, mcs = 25_000, every = 100)
function p61e_run(σ, k)
    prob = PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ)), [ownership => σ, kind => k],
        (0, P61E_RUN.mcs); seed = P61E_RUN.run_seed)
    sol = solve(prob, SequentialCPM(); saveat = P61E_RUN.every)
    frames = [Array(u.σ) for u in sol.u]
    return (; edge = minimum(p61e_edge, frames), gap = minimum(p61e_imagegap, frames),
        frames = length(frames), cells = maximum(frames[end]))
end

@testset "P6.1e: Graner–Glazier aggregate margin" begin
    @testset "1. default margin ≥ 60 on every side; lattice sized by the formula" begin
        margins = Int[]
        for n in (50, 200, 1000), seed in (1, 2, 3)
            σ, k = graner_glazier_aggregate(n; seed)
            L = size(σ, 1)
            @test size(σ) == (L, L)
            @test p61e_edge(σ) >= 60                                    # measured from σ
            @test iseven(L - p61e_core(n))
            M = (L - p61e_core(n)) ÷ 2                                  # the default margin
            push!(margins, M)
            @test M >= 60
            σM, kM = graner_glazier_aggregate(n; seed, margin = M)      # default ≡ margin = M
            @test σM == σ && kM == k
        end
        @test allequal(margins)                                         # one default for every n
    end

    @testset "2. explicit margin is honoured exactly as today" begin
        for ((n, seed, margin), (side, dσ, dk)) in sort(collect(P61E_DIGESTS); by = first)
            σ, k = graner_glazier_aggregate(n; seed, margin)
            @test size(σ) == (side, side) == ntuple(_ -> p61e_core(n) + 2margin, 2)
            @test eltype(σ) == Int32 && eltype(k) == Int32
            @test p61e_σdigest(σ) == dσ
            @test p61e_kdigest(k) == dk
            @test p61e_edge(σ) >= margin
        end
    end

    @testset "3. a long sorting run at the default margin stays off the lattice edge" begin
        (; n, seed) = P61E_RUN
        # negative control: margin 10 reaches the edge (today at t = 22 800 MCS)
        ctl = p61e_run(graner_glazier_aggregate(n; seed, margin = 10)...)
        @test ctl.frames == P61E_RUN.mcs ÷ P61E_RUN.every + 1 && ctl.cells == n
        @test ctl.edge == 0
        @test ctl.gap >= 1                     # (drift, not a join with the image: see header)
        # the default margin: no cell site on the outermost rows/columns at any frame
        def = p61e_run(graner_glazier_aggregate(n; seed)...)
        @test def.frames == P61E_RUN.mcs ÷ P61E_RUN.every + 1 && def.cells == n
        @test def.edge >= 1
        @test def.gap >= 1
    end
end
