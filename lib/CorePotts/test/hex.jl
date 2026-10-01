# Hexagonal 2D lattices (M2.1b): axial coordinates embedded at (q + r/2, r·√3/2).
@testset "hexagonal lattices" begin
    L = Lattice((24, 24); geometry = Hexagonal())
    @test length(relation(Hex(1), L)) == 6 && length(relation(Hex(2), L)) == 18 && length(relation(Hex(3), L)) == 36
    @test relation(Moore(1), L) == relation(Hex(1), L) && relation(VonNeumann(2), L) == relation(Hex(2), L)
    @test length(relation(NeighborOrder(1), L)) == 6 && length(relation(NeighborOrder(2), L)) == 12 &&
          length(relation(NeighborOrder(3), L)) == 18
    @test length(relation(Ball(1.0), L)) == 6 && length(relation(Ball(sqrt(3)), L)) == 12
    @test all(o -> abs(hypot(embed(L, Float64.(o))...) - 1) < 1e-12, relation(Hex(1), L).offsets)   # unit distance
    @test_throws ArgumentError relation(Hex(1), Lattice((8, 8)))
    @test_throws ArgumentError Lattice((4, 4, 4); geometry = Hexagonal())
    @test L != Lattice((24, 24)) && hash(L) != hash(Lattice((24, 24)))
    # fields: the 6-point stencils are exact for quadratics (Δ) and linear functions (∇)
    pos(i) = embed(L, Float64.(CorePotts.coordinates(L, i)))
    f = [sum(abs2, pos(i)) for i in 1:nsites(L)]
    g = [2.0 * pos(i)[1] - 3.0 * pos(i)[2] for i in 1:nsites(L)]
    ctx = (; lattice = L)
    i = CorePotts.linear_index(L, (10, 12))
    @test laplacian(reshape(f, 24, 24), ctx, i) ≈ 4.0
    @test all(gradient(reshape(g, 24, 24), ctx, i) .≈ (2.0, -3.0))
    # a hexagonal disc: centroid, isotropic shape, even division
    σ = zeros(Int32, 24, 24)
    centre = (12, 12)
    for x in CartesianIndices(σ)
        CorePotts._hexdist(Tuple(x) .- centre) <= 4 && (σ[x] = 1)
    end
    @test count(==(1), σ) == 61                                  # 1 + 6·(1 + 2 + 3 + 4)
    cell = merge((; volume = [count(==(1), σ)]), init_moments(σ, L, 1))
    @test all(centroid_position(Float64, cell, L, 1) .≈ embed(L, (12.0, 12.0)))
    sh = shape(Float64, cell, L, 1)
    @test sh.elongation ≈ 1 atol = 1e-12                         # isotropic in the embedding
    sq = zeros(Int32, 24, 24); sq[8:16, 10:14] .= 1              # a lattice-coordinate box is a rhombus
    cs = merge((; volume = [count(==(1), sq)]), init_moments(sq, L, 1))
    @test shape(Float64, cs, L, 1).elongation > 1.2
    @test abs(hypot(principal_axis(Float64, cs, L, 1, 2)...) - 1) < 1e-12
    # division through the embedded centroid: a Cartesian plane x = const splits the disc evenly
    ellipse = zeros(Int32, 24, 24)
    for x in CartesianIndices(ellipse)
        e = embed(L, Float64.(Tuple(x) .- centre))
        (e[1] / 6)^2 + (e[2] / 3)^2 <= 1 && (ellipse[x] = 1)
    end
    u = run_lifecycle(ellipse, [1], L, Lifecycle(divide_at(0); normal = along_minor_axis)).u[end]   # plane across the long x axis
    halves = [[embed(L, Float64.(Tuple(x)))[1] for x in CartesianIndices(u.σ) if u.σ[x] == c] for c in 1:2]
    onplane = count(x -> ellipse[x] == 1 && abs(embed(L, Float64.(Tuple(x) .- centre))[1]) < 1e-9, CartesianIndices(ellipse))
    @test u.cell.volume[1] - u.cell.volume[2] == onplane               # sites on the plane stay with the parent
    @test maximum(halves[1]) < minimum(halves[2]) || maximum(halves[2]) < minimum(halves[1])   # separated along x
end
