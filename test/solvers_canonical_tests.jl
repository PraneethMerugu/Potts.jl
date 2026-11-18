# Canonical solver strings, D-016 / D-118 / D-122 fingerprint invariants, and TS-R2 §2.6 repr round-trips.

@testitem "canonical solver strings: no collisions, no host details" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "canonical solver strings: no collisions, no host details" begin
        canon(x) = Potts._canonical(Adaptive(x))
        @test canon(SolverFakeAlg(SolverTrivial, nothing, ())) != canon(SolverFakeAlg(SolverLinear, nothing, ()))       # enums
        @test canon(SolverFakeAlg('a', nothing, ())) != canon(SolverFakeAlg('b', nothing, ()))                          # primitives
        @test canon(SolverFakeAlg(nothing, solver_limiter(0.0), ())) != canon(SolverFakeAlg(nothing, solver_limiter(5.0), ()))   # captures
        @test canon(SolverFakeAlg(nothing, solver_limiter(1.0), ())) == canon(SolverFakeAlg(nothing, solver_limiter(1.0), ()))
        @test canon(SolverFakeAlg(nothing, nothing, 1:3)) != canon(SolverFakeAlg(nothing, nothing, [1, 2, 3]))             # ranges
        @test canon(SolverFakeAlg(nothing, nothing, Float64[])) != canon(SolverFakeAlg(nothing, nothing, Int[]))         # element types
        d1 = Dict(:a => 1, :b => 2, :c => 3); d2 = Dict(:c => 3, :b => 2, :a => 1)
        @test canon(SolverFakeAlg(nothing, nothing, d1)) == canon(SolverFakeAlg(nothing, nothing, d2))                   # no hash slots
        @test canon(SolverFakeAlg(nothing, nothing, d1)) != canon(SolverFakeAlg(nothing, nothing, Dict(:a => 1, :b => 2, :c => 4)))
        @test Potts._canonical(Adaptive(Tsit5(); reltol = 1.0e-6, abstol = 1.0e-8)) ==
            Potts._canonical(Adaptive(Tsit5(); abstol = 1.0e-8, reltol = 1.0e-6))                                         # sorted kwargs
        # solvers that differ only in a closure's captures never share a phase
        sys = SolverPairYS(; name = :p)
        prob = PottsProblem(
            sys, solver_op(), (0, 2); solvers = [
                :y => Adaptive(Tsit5(step_limiter! = solver_limiter(-10.0))), :s => Adaptive(Tsit5(step_limiter! = solver_limiter(5.0))),
            ]
        )
        @test count(ph -> ph isa Potts._AdaptiveODE, prob.f.phases.after_mcs) == 2
        @test solve(prob, SequentialCPM()).u[end].cell.s[1] == 5.0                     # its own limiter
    end
end

@testitem "D-016: fingerprints do not depend on the checkout path" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "D-016: fingerprints do not depend on the checkout path" begin
        exprs = Any[values(Base.structdiff(generated_code(SolverPairYS(; name = :p)), (; phases = nothing)))...]
        append!(exprs, generated_code(SolverPairYS(; name = :p)).phases)
        exprs = filter(!isnothing, exprs)
        moved(ex) = ex isa LineNumberNode ? LineNumberNode(ex.line + 100, Symbol("/elsewhere/src/codegen.jl")) :
            ex isa Expr ? Expr(ex.head, map(moved, ex.args)...) : ex
        hasmacroline(ex) = ex isa Expr && ((ex.head === :macrocall && ex.args[2] isa LineNumberNode) || any(hasmacroline, ex.args))
        @test any(hasmacroline, exprs)                                   # the case the hash must ignore
        @test Potts._code_hash(exprs) == Potts._code_hash(map(moved, exprs))
        @test Potts._code_hash(exprs) != Potts._code_hash(exprs[2:end])  # negative control
        # Symbolics' term order is build dependent: sums and products hash in a canonical order
        @test Potts._code_hash([:(f(x) = (+)(a, (*)(-1, b), c))]) == Potts._code_hash([:(f(x) = (+)(c, a, (*)(b, -1)))])
        @test Potts._code_hash([:(f(x) = (-)(a, b))]) != Potts._code_hash([:(f(x) = (-)(b, a))])
        # regrouping of nested sums/products is read flattened (Symbolics' grouping is build-dependent)
        @test Potts._code_hash(Any[:(x + (y + z))]) == Potts._code_hash(Any[:(y + (z + x))])
        @test Potts._code_hash(Any[:(a * (b * c))]) == Potts._code_hash(Any[:((c * a) * b)])
        @test Potts._code_hash(Any[:(a * (b + c))]) != Potts._code_hash(Any[:(a * b + c)])   # nesting across operators kept
    end
end

@testitem "equal specifications share a phase and a fingerprint" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "equal specifications share a phase and a fingerprint" begin
        sys = SolverPairYS(; name = :p)
        A() = Adaptive(Tsit5(); abstol = [1.0e-8, 1.0e-8], reltol = 1.0e-8)
        @test !isequal(A(), A())                                         # fresh, not egal
        whole = PottsProblem(sys, solver_op(), (0, 2); ode_solver = A())
        split = PottsProblem(sys, solver_op(), (0, 2); solvers = [:y => A(), :s => A()])
        @test split.f.fingerprint == whole.f.fingerprint
        @test count(ph -> ph isa Potts._AdaptiveODE, split.f.phases.after_mcs) == 1
        @test keys(split.u0.cell) == keys(whole.u0.cell)
        @test solve(split, SequentialCPM()).u[end].cell.s == solve(whole, SequentialCPM()).u[end].cell.s
    end
end

@testitem "D-016: the structural seed is a canonical string" setup = [SolversSetup, PortsSetup] tags = [:potts, :solvers] begin
    @testset "D-016: the structural seed is a canonical string" begin
        gg = graner_state()
        sys = mtkcompile(GranerGlazier(; name = :gg))
        seed = Potts._fingerprint_seed(getfield(sys, :sys), Float64)
        @test seed isa String && occursin("T=Float64", seed) && occursin("Moore", seed)
        @test !occursin("0x", seed)                                       # no addresses
        p64 = PottsProblem(sys, [ownership => gg[1], kind => gg[2]], (0, 1))
        p32 = PottsProblem(sys, [ownership => gg[1], kind => gg[2]], (0, 1); T = Float32)
        @test p64.f.fingerprint != p32.f.fingerprint
        @test Potts._fingerprint_seed(getfield(mtkcompile(SolverPairYS(; name = :p)), :sys), Float64) != seed
        @test Potts._fingerprint_seed(getfield(mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))), :sys), Float64) !=
            Potts._fingerprint_seed(getfield(mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (30, 30))), :sys), Float64)
    end
end

@testitem "D-118: a non-default mcs_duration is in the fingerprint" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "D-118: a non-default mcs_duration is in the fingerprint" begin
        md_sigma() = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s)
        refused(p, ck) = try
            init(p, SequentialCPM(); checkpoint = ck); false
        catch e
            e isa ArgumentError
        end
        ad(md) = PottsProblem(
            md_ode_model(md), [ownership => md_sigma(), kind => [:A]], (0, 4);
            ode_solver = Adaptive(Tsit5(); reltol = 1.0e-10, abstol = 1.0e-12)
        )
        a1, a2, ah = ad(1.0), ad(1.0), ad(0.5)
        # the runs differ: y = e^{-4} after 4 MCS of length 1, e^{-2} of length 0.5
        @test solve(a1, SequentialCPM()).u[end].cell.y[1] ≈ exp(-4) rtol = 1.0e-6
        @test solve(ah, SequentialCPM()).u[end].cell.y[1] ≈ exp(-2) rtol = 1.0e-6
        @test a1.f.fingerprint == a2.f.fingerprint                      # control: same schedule
        @test a1.f.fingerprint != ah.f.fingerprint
        i1 = init(a1, SequentialCPM()); step!(i1); step!(i1)
        ck = checkpoint(i1)
        @test refused(ah, ck)
        @test init(a2, SequentialCPM(); checkpoint = ck).t == i1.t      # control: same schedule loads
        # an explicit-substeps field step (no parameter bound): already distinct through its code;
        # kept as a regression guard
        fd(md) = PottsProblem(
            md_field_model(md), [ownership => md_sigma(), kind => [:A], :c => [Float64(x + y) for x in 1:12, y in 1:12]],
            (0, 3); field_solver = ExplicitEuler(substeps = 4)
        )
        f1, fh = fd(1.0), fd(0.5)
        @test solve(f1, SequentialCPM()).u[end].site.c != solve(fh, SequentialCPM()).u[end].site.c
        @test f1.f.fingerprint == fd(1.0).f.fingerprint
        @test f1.f.fingerprint != fh.f.fingerprint
        j1 = init(f1, SequentialCPM()); step!(j1)
        @test refused(fh, checkpoint(j1))
        # the default `mcs_duration` adds nothing: an explicit 1.0 equals an unset one
        @test fd(1.0).f.fingerprint == PottsProblem(
            md_field_model(1), [
                ownership => md_sigma(), kind => [:A],
                :c => [Float64(x + y) for x in 1:12, y in 1:12],
            ], (0, 3); field_solver = ExplicitEuler(substeps = 4)
        ).f.fingerprint
    end
end

@testitem "D-122: thin lattices whose default neighbourhood aliases" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "D-122: thin lattices whose default neighbourhood aliases" begin
        line = Stencil([[0, 1], [0, -1]])
        line2 = Stencil([[0, 1], [0, -1], [0, 2], [0, -2]])
        for (dims, nbhd) in (((2, 12), VonNeumann(1)), ((1, 12), VonNeumann(1)), ((2, 12), Moore(1)))
            σ = zeros(Int32, dims); σ[:, 2:3] .= 1
            op = [ownership => σ, kind => [:A]]
            # control: the default itself does not resolve on this lattice
            sv_throws(
                ArgumentError, [dims[1] == 1 ? "wraps onto the origin" : "alias on lattice"],
                () -> Potts.CorePotts.relation(VonNeumann(1), Potts.CorePotts.Lattice(dims))
            )
            p = PottsProblem(thin_model(dims, line, nbhd), op, (0, 3); seed = 1)
            @test Symbol(solve(p, SequentialCPM()).retcode) === :Success
            @test PottsProblem(thin_model(dims, line, nbhd), op, (0, 3); seed = 1).f.fingerprint == p.f.fingerprint
            @test PottsProblem(thin_model(dims, line2, nbhd), op, (0, 3); seed = 1).f.fingerprint != p.f.fingerprint
        end
    end
end

@testitem "TS-R2 §2.6: canonical solver-spec properties and repr round-trips" setup = [SolversSetup] tags = [:potts, :solvers] begin
    @testset "TS-R2 §2.6: canonical solver-spec properties and repr round-trips" begin
        LFP = Potts.LatticeFields.Problems
        LFS = Potts.LatticeFields.Solvers
        LP = Potts.LatticePDE

        # Canonical solver-spec generator: omitted defaults == explicit defaults, keyword order
        # invariance and sensitivity to every semantic knob.
        for (a, b, diff) in (
                (
                    ExplicitEuler(), ExplicitEuler(; substeps = nothing, lower_bound = nothing, init = nothing, compute_type = :auto),
                    ExplicitEuler(; substeps = 3),
                ),
                (
                    ExplicitEuler(; substeps = 2, lower_bound = 0.0), ExplicitEuler(; lower_bound = 0.0, substeps = 2),
                    ExplicitEuler(; substeps = 2, lower_bound = 1.0e-6),
                ),
                (ExplicitMap(), ExplicitMap(; compute_type = :auto), ExplicitMap(; compute_type = Float32)),
                (
                    BackwardEuler(), BackwardEuler(; linsolve = :auto, solver_type = :auto, init = nothing, compute_type = :auto),
                    BackwardEuler(; newton = 4),
                ),
                (
                    CrankNicolson(; linsolve = LFS.LatticePCG(; reltol = 1.0e-8)), CrankNicolson(; linsolve = LFS.LatticePCG(; reltol = 1.0e-8)),
                    CrankNicolson(; linsolve = LFS.Multigrid(; cycle = LFS.VCycle(1, 1))),
                ),
                (
                    BDF2(; solver_type = Float64), BDF2(; solver_type = Float64, init = nothing),
                    BDF2(; solver_type = Float32),
                ),
                (
                    QuasiSteady(), QuasiSteady(; newton = nothing, linsolve = :auto),
                    QuasiSteady(; init = :steady),
                ),
                (
                    FieldGroups(:c => BackwardEuler(); default = ExplicitEuler()),
                    FieldGroups(:c => BackwardEuler(); default = ExplicitEuler()),
                    FieldGroups(:c => CrankNicolson(); default = ExplicitEuler()),
                ),
                (
                    Adaptive(Tsit5(); reltol = 1.0e-6, abstol = 1.0e-8), Adaptive(Tsit5(); abstol = 1.0e-8, reltol = 1.0e-6),
                    Adaptive(Tsit5(); reltol = 1.0e-5, abstol = 1.0e-8),
                ),
            )
            @test Potts._canonical(a) == Potts._canonical(b)
            @test Potts._canonical(a) != Potts._canonical(diff)
        end

        # `repr` round-trip: `eval(Meta.parse(repr(x))) == x`
        rt_mod = Module(:ReprRoundTrip)
        Core.eval(
            rt_mod, quote
                using Potts
                const CorePotts = Potts.CorePotts
                const LatticeFields = Potts.LatticeFields
                using Potts.LatticeFields.Problems: ExplicitEuler, ExplicitMap, BackwardEuler, CrankNicolson, BDF2, QuasiSteady
                using Potts.LatticeFields.Solvers: LatticePCG, Multigrid, VCycle
                using Potts.LatticePDE: LatticeMultigrid
            end
        )
        roundtrip(x) = Core.eval(rt_mod, Meta.parse(repr(x)))

        for x in (
                ExplicitEuler(),
                ExplicitEuler(; substeps = 4, lower_bound = 0.0),
                ExplicitMap(),
                BackwardEuler(),
                BackwardEuler(; newton = 3, linsolve = LFS.LatticePCG(; reltol = 1.0e-8)),
                CrankNicolson(; substeps = 2),
                BDF2(),
                QuasiSteady(; init = :steady),
                Potts.RK4(),
                Potts.RK4(; substeps = 3),
                LFS.VCycle(2, 2),
                SequentialCPM(),
                CheckerboardCPM(; parts = 2),
                VonNeumann(1),
                Moore(1),
                EuclideanBall(2.0),
                Metropolis(; offset = 0.5),
                Barker(; offset = 0.0),
            )
            @test roundtrip(x) == x
        end
        let x = LP.LatticeMultigrid(), y = roundtrip(x)
            @test typeof(y) === typeof(x)
            @test repr(y) == repr(x)
        end
    end
end
