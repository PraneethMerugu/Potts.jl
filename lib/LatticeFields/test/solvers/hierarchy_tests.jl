# The solver hierarchy: depth and the bottom cut, the n ÷ 2 widths, and the rule-M build
# against hand-computed coarse operators (independent oracles), with the ½Σ control.

using LatticeFields.Solvers: depth, RULE_M
const SV = LatticeFields.Solvers

function built(op, inputs; rule = RULE_M)
    sv = case_solver((op, inputs), Float64; inner = Multigrid(), rule)
    rebuild!(sv)
    return sv
end

@testset "depth: coarsen to the first axis of size 1; bottom at ≤ 4096 sites" begin
    @test depth((42, 42, 42)) == (5, 2)              # 42 21 10 5 2 1; 10³ is the first ≤ 4096
    @test depth((512, 512)) == (9, 3)                # 64² = 4096 starts the bottom
    @test depth((300, 192)) == (7, 2)                # coarsest (2, 1)
    @test depth((8, 1)) == (3, 1)                    # the size-1 axis is never coarsened
    sv = built(box_case(300, 192; s = 1e-3)...)
    @test sv.ctx.dims[end] == (2, 1)
end

@testset "widths: level-ℓ cells are 2^ℓ wide, the last takes the rest" begin
    w(n0, ℓ) = (
        n = n0 >> ℓ; [SV._width(Int32(i), Int32(n), Int32(n0), Int32(ℓ)) for i in 1:n])
    @test w(42, 1) == fill(2, 21)
    @test w(42, 2)[(end - 1):end] == [4, 6]
    @test w(42, 3)[(end - 1):end] == [8, 10]
    @test w(42, 4)[(end - 1):end] == [16, 26]
    @test all(ℓ -> sum(w(300, ℓ)) == 300, 1:8)
end

@testset "rule M on hand-computed coarse operators" begin
    one_d(mask) = (CellOperator((4, 1); shift = 0.0, mask = "in.mask", value = 0.0),
        ("in.mask" => mask,))
    # site 4 masked: its face to site 3 lies inside coarse cell {3,4}: Σ (rule M), not ½Σ
    for (rule, absorb) in ((RULE_M, 1.0), (
        SV.RuleWeights(inside = 0.5, plane = 0.5,
            inherited = 0.5), 0.5))
        sv = built(one_d(UInt8[0, 0, 0, 1])...; rule)
        @test level_matrix(sv, 1) ≈ [0.5 -0.5; -0.5 0.5+absorb]
    end
    # site 3 masked: face 2–3 lies on the plane between two active coarse cells (Σ into the
    # active side) and face 3–4 inside {3,4}; the coarse cells decouple
    sv = built(one_d(UInt8[0, 0, 1, 0])...)
    @test level_matrix(sv, 1) ≈ [1.0 0.0; 0.0 1.0]
    # Majority fold drops {3,4} (1 of 2 children active is not a majority)
    sv = built(one_d(UInt8[0, 0, 1, 0])...; rule = SV.RuleWeights(majority = true))
    @test field(sv, lkey(1, "active"))[1:2] == UInt8[1, 0]
    # box face-Dirichlet absorption folds with ½Σ (2 per fine face → 2 per coarse face)
    sv = built(box_case(8, 2; s = 0.0)...)
    @test field(sv, lkey(1, "sbox"))[1:4] ≈ [2, 0, 0, 2]
    # odd periodic axis: faces rediscretized with physical widths, f = (1 + 1)/(2 + 3)
    sv = built(CellOperator((5, 2); periodic = (true, true), shift = 0.1), ())
    @test field(sv, lkey(1, "w1")) ≈ [0.8, 0.8]
    @test field(sv, lkey(1, "s")) ≈ [0.4, 0.6]
end

@testset "coarse operators are symmetric (sphere 42³, random islands)" begin
    for case in (ball_case((42, 42, 42); s = 0.022, R = 15.8, ctr = (21.13, 20.87, 21.41)),
        box_case(60, 40; s = 1e-3, islands = 0.1))
        sv = built(case...)
        for l in 1:(sv.ctx.L)
            A = level_matrix(sv, l)
            @test A ≈ A' rtol = 1e-14
        end
    end
end
