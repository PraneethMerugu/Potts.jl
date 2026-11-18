# F4-E11 to F4-E15 (gaps found by the Potts test port F4-B4t, ~/lpwork/f4B4t/EVIDENCE.txt). Until
# F4-B6 each model here was checked bitwise against its A form; now the oracles are an
# independent spelling (an array field against the same fields as scalars) and LatticePDE's own
# run of the same PDESystem (σ frozen: no cells). Uses `cp_msg` and `CpHost` of fields_couple.jl.
# Negative controls (each item's src change reverted alone in the test copy):
# ~/lpwork/f4E/nc-e11e15.log.

@testitem "F4-E11: array fields of a PDESystem are the components u_1, …, u_n" setup = [CoupleSetup] tags = [:potts, :fields_couple_e11] begin
    @testset "F4-E11: array fields of a PDESystem are the components u_1, …, u_n" begin
        op = ce_op((12, 10))
        for fs in (BackwardEuler(), CrankNicolson())
            a, b = ce_steps(CeFiCompB(; name = :f), op, 3; field_solver = fs), ce_steps(CeFiScal(; name = :f), op, 3; field_solver = fs)
            @test filter(n -> !endswith(string(n), "__next"), first.(a[end])) == [:u_1, :u_2] && ce_values(a) == ce_values(b)   # bitwise, by component
        end
        a, b = ce_steps(CeFcCompB(; name = :f), op, 3), ce_steps(CeFcScal(; name = :f), op, 3)
        @test ce_values(a) == ce_values(b) && maximum(abs, last(a[end][1])) > 0.01
        # `Potts.couple` too, and `@fields u = …` bound the vector of the components
        m = Potts.couple(CeHostArr(; name = :h), CeArr.fi())
        @test ce_steps(m, op, 3; field_solver = BackwardEuler()) == ce_steps(CeFiCompB(; name = :f), op, 3; field_solver = BackwardEuler())
        d = ce_steps(CeFiDriveB(; name = :f), op, 3; field_solver = BackwardEuler(), seed = 3)
        @test ce_values(d) == ce_values(ce_steps(CeFiDriveScal(; name = :f), op, 3; field_solver = BackwardEuler(), seed = 3))
        # only vectors: a matrix of fields is refused by its shape
        e = cp_msg(() -> Potts.couple(CeHostArr(; name = :h), CeArr.mat()))
        @test occursin("has the shape (2, 2)", e) && occursin("`q(..)[1:n]`", e) || (println(e); false)
    end
end

@testitem "F4-E11: a face condition on a component of an array field" setup = [CoupleSetup] tags = [:potts, :fields_couple_e11] begin
    @testset "F4-E11: a face condition on a component of an array field" begin
        op = ce_op((12, 10))
        for fs in (ExplicitEuler(), BackwardEuler())
            ra = ce_steps(Potts.couple(CeHostArr(; name = :h), CeArrF.arr()), op, 3; field_solver = fs)
            rs = ce_steps(Potts.couple(CeHostArr(; name = :h), CeArrF.sca()), op, 3; field_solver = fs)
            @test [last.(r) for r in ra] == [last.(r) for r in rs] && maximum(last(ra[end][1])) > 0.5
        end
    end
end

@testitem "F4-E12: Advect with a velocity vector in a coupled PDESystem" setup = [CoupleSetup] tags = [:potts, :fields_couple_e11] begin
    @testset "F4-E12: Advect with a velocity vector in a coupled PDESystem" begin
        LP = Potts.LatticePDE
        e0(dims) = [ownership => zeros(Int32, dims...), kind => Symbol[]]
        run(M, op, k, fs) = solve(PottsProblem(M(; name = :f), op, (0, k); field_solver = fs, seed = 1), SequentialCPM()).u[end].site
        # LatticePDE's own run of the same system (no cells: σ is the medium), `k` windows of length 1
        own(sys, u0, k, alg) = reshape(LP.solve(LP.remake(LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(size(u0)); T = Float64));
                    u0 = vec(u0), tspan = (0.0, Float64(k))
                ), alg; dt = 1.0
            ).u[end], size(u0)
        )
        c0 = [0.01 * (i + 3j) for i in 1:8, j in 1:6]
        for (B, sys) in ((CeAdvB, CeAdv.adv((8, 6))), (CeAdvConstB, CeAdv.advconst((8, 6))))
            b = run(B, [e0((8, 6)); :c => c0], 2, ExplicitEuler(; substeps = 4))
            @test b.c == own(sys, c0, 2, LP.ExplicitEuler(; substeps = 4)) && maximum(b.c) > 0
        end
        cb0 = [0.5 + 0.4 * sin(2π * (i - 0.5) / 32) for i in 1:32, j in 1:32]
        # (the user's count past the linearized limit warns once per session, fields.jl tests it)
        b, o = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            run(CeBurgersB, [e0((32, 32)); :cb => cb0], 5, ExplicitEuler(; substeps = 8)),
                own(CeAdv.burgers((32, 32)), cb0, 5, LP.ExplicitEuler(; substeps = 8))
        end
        @test b.cb == o && b.cb != cb0
        ci0 = [0.01 * i * j for i in 1:16, j in 1:16]
        b = run(CeIvAdvB, [e0((16, 16)); :ci => ci0], 2, ExplicitEuler())
        @test b.ci == own(CeAdv.ivadv((16, 16)), ci0, 2, LP.ExplicitEuler()) && b.ci != ci0
    end
end

@testitem "F4-E13: a centroid in a masked condition allocates the moment trackers" setup = [CoupleSetup] tags = [:potts, :fields_couple_e11] begin
    @testset "F4-E13: a centroid in a masked condition allocates the moment trackers" begin
        for M in (CeMaskB,)
            prob = PottsProblem(M(; name = :bm), [ownership => ce_mask_sigma(), kind => [:ka, :ka]], (0, 1); T = Float64,
                field_solver = ExplicitEuler(substeps = 1))
            @test hasproperty(prob.u0.cell, :anchor)
            u = solve(prob, SequentialCPM()).u[end]
            @test Array(u.ownership) == ce_mask_sigma() && Array(u.site.c) == 7.0 .* (ce_mask_sigma() .== 1)
        end
    end
end

@testitem "F4-E14: a face condition on a field with no spatial operator is refused" setup = [CoupleSetup] tags = [:potts, :fields_couple_e11] begin
    @testset "F4-E14: a face condition on a field with no spatial operator is refused" begin
        op = [ownership => zeros(Int32, 8, 6), kind => Symbol[]]
        e = cp_msg(() -> PottsProblem(CeFaceB(; name = :f), op, (0, 1)))
        @test occursin("the PDESystem `nolap`", e) && occursin("has no `laplacian(c)`", e) && occursin("would do nothing", e) ||
              (println(e); false)
        @test PottsProblem(CeFaceLapB(; name = :f), op, (0, 1)) isa PottsProblem          # control: with `laplacian(c)`
    end
end

@testitem "F4-E15: a neighbourhood's anonymous weight does not enter the fingerprint by name" setup = [CoupleSetup] tags = [:potts, :fields_couple_e11] begin
    @testset "F4-E15: a neighbourhood's anonymous weight does not enter the fingerprint by name" begin
        @test typeof(CE_W1.weight) != typeof(CE_W2.weight)
        op = (σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; [ownership => σ, kind => [:A]])
        f1, f2 = (PottsProblem(M(; name = :w), op, (0, 1)).f.fingerprint for M in (CeW1, CeW2))
        @test f1 == f2
        # the resolved weights do enter it: another weight gives another fingerprint
        W3 = Potts.CorePotts.Weighted(Moore(1), o -> 2 / sqrt(sum(abs2, o)))
        @eval @potts_model CeW3 begin
            @kinds medium A
            @lattice Lattice((20, 20); boundary = Periodic(), neighborhood = $W3)
            @energy cells => (volume - 16.0)^2
            @sweep Metropolis(; temperature = 10.0)
        end
        @test Base.invokelatest(() -> PottsProblem(CeW3(; name = :w), op, (0, 1)).f.fingerprint) != f1
        # a neighbourhood without a closure keeps its printed form (and so its fingerprint)
        @test !occursin("resolved(", Potts._fingerprint_seed(CpHost(; name = :m), Float64))
    end
end
