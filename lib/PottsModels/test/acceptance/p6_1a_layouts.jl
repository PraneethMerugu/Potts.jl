# P6.1a (ROADMAP Phase 6, step 1; review §3 R2 first slice): layout values composed by
# `overlay` and turned into an SII operating point by `layout`. Frozen (AUTONOMY §7.3).
#
# Surface fixed by the coordinator:
#   Tiling(size; spacing = 0, region = <whole lattice>, kinds)   boxes of `size`, `spacing`
#       medium sites apart, filling `region` (a tuple of ranges) in column-major order;
#       `kinds` is cycled over the cells in placement order
#   Scattered(n, size; region = <whole lattice>, kinds, seed, gap = 1)   `n` boxes at random
#       positions, at least `gap` medium sites apart; deterministic in `seed`; throws an
#       ArgumentError when they cannot be placed
#   Frame(kind; width = 1)   one cell of `kind` owning every site within `width` of the edge
#   overlay(layers...)   later layers overwrite earlier ones; ids follow layer order
#   layout(l, dims) -> [ownership => σ, kind => kinds]   (an operating point for PottsProblem)
using Potts: CorePotts

opget(op, key) = only(last(p) for p in op if isequal(first(p), key))

@potts_model FramedSorting begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        λ = 1.0
        V₀ = 25.0
        T = 6.0
        J[kind, kind] = [0 0 16 16; 0 0 20 20; 16 20 2 11; 16 20 11 14]
    end
    @lattice Lattice((30, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

@testset "P6.1a: Tiling and Frame, overlaid" begin
    tiles = Tiling((5, 5); spacing = 1, region = (3:28, 3:28), kinds = [:dark, :light])
    op = layout(overlay(Frame(:wall), tiles), (30, 30))
    σ, kinds = opget(op, ownership), opget(op, kind)
    @test size(σ) == (30, 30)
    @test length(kinds) == 17 && kinds[1] == :wall                  # the frame is layer 1
    border = [i in (1, 30) || j in (1, 30) for i in 1:30, j in 1:30]
    @test all(σ[border] .== 1) && count(==(1), σ) == 116
    for c in 2:17
        idx = findall(==(c), σ)
        @test length(idx) == 25                                     # untouched 5×5 boxes
        @test all(i -> 3 <= i[1] <= 28 && 3 <= i[2] <= 28, idx)
        @test maximum(i[1] for i in idx) - minimum(i[1] for i in idx) == 4
    end
    @test kinds[2:17] == repeat([:dark, :light], 8)
    # the operating point drives a problem; the frame is frozen
    prob = PottsProblem(FramedSorting(; name = :fs), op, (0, 5))
    u = solve(prob, SequentialCPM()).u[end]
    @test Array(u.σ)[border] == σ[border]
end

@testset "P6.1a: Scattered" begin
    sc(seed) = layout(Scattered(10, (4, 4); kinds = [:dark], seed), (40, 40))
    σ = opget(sc(1), ownership)
    @test maximum(σ) == 10 && all(c -> count(==(c), σ) == 16, 1:10)
    @test opget(sc(1), kind) == fill(:dark, 10)
    apart = true                                     # gap = 1: no two cells touch (Moore)
    for i in CartesianIndices(σ), d in CartesianIndices((-1:1, -1:1))
        j = i + d
        checkbounds(Bool, σ, j) || continue
        σ[i] != 0 && σ[j] != 0 && σ[i] != σ[j] && (apart = false)
    end
    @test apart
    @test opget(sc(1), ownership) == σ                              # deterministic in seed
    @test opget(sc(2), ownership) != σ
    @test_throws ArgumentError layout(Scattered(200, (4, 4); kinds = [:dark], seed = 1), (40, 40))
end

@testset "P6.1a: layouts in 3D" begin
    op = layout(Tiling((3, 3, 3); spacing = 1, region = (2:13, 2:13, 2:13), kinds = [:dark]), (14, 14, 14))
    σ = opget(op, ownership)
    @test size(σ) == (14, 14, 14) && maximum(σ) == 27
    @test all(c -> count(==(c), σ) == 27, 1:27)
end
