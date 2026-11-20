@testitem "operators and aux fields equal LatticePDE's own run, bitwise" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "operators and aux fields equal LatticePDE's own run, bitwise" begin
        LP, MTKB = Potts.LatticePDE, Potts.ModelingToolkitBase
        tt, DD = MTKB.t_nounits, MTKB.D_nounits
        dims, k, n = (8, 6), 3, 4
        c0 = rand(StableRNG(3), dims...)
        Potts.ModelingToolkitBase.@parameters x y K0 = 0.4 s = 0.01 ux = 0.3
        Potts.ModelingToolkitBase.@variables c(..) K(..)
        ce, Ke = c(tt, x, y), K(tt, x, y)
        dom = [tt ∈ LP.Interval(0.0, Float64(k)), x ∈ LP.Interval(0.0, 8.0), y ∈ LP.Interval(0.0, 6.0)]
        Dx, Dy = MTKB.Differential(x), MTKB.Differential(y)
        b(eqs, dvs, ps) = MTKB.PDESystem(eqs, [c(0, x, y) ~ 0.0], dom, [tt, x, y], dvs, ps; name = :b)
        bsys = Dict(
            :FpDivK => b([DD(ce) ~ LP.DivKGrad(:harmonic)(K0, ce) + s * x], [ce], [K0, s]),
            :FpRaw => b([DD(ce) ~ Dx(K0 * Dx(ce)) + Dy(K0 * Dy(ce)) + s * x], [ce], [K0, s]),
            :FpAdvect => b([DD(ce) ~ -LP.Advect(LP.Upwind1())([ux, 0.0], ce) + s * y], [ce], [ux, s]),
            :FpAux => b([Ke ~ K0 * (1 + 0.05 * x), DD(ce) ~ LP.DivKGrad(:arithmetic)(Ke, ce) + s * x], [ce, Ke], [K0, s])
        )
        for (name, M) in ((:FpDivK, FpDivK), (:FpRaw, FpRaw), (:FpAdvect, FpAdvect), (:FpAux, FpAux))
            prob = PottsProblem(M(; name = :f), [fd_empty(dims); :c => c0], (0, k); field_solver = ExplicitEuler(; substeps = n))
            integ = init(prob, SequentialCPM())
            foreach(_ -> step!(integ), 1:k)
            a = Array(current_state(integ).site.c)
            bp = LP.discretize(bsys[name], LP.LatticeDiscretization(LP.Grid(dims); T = Float64))
            bb = LP.solve(LP.remake(bp; u0 = vec(c0)), LP.ExplicitEuler(; substeps = n); dt = 1.0)[:c, end]
            @test a == bb
            @test maximum(abs, a .- c0) > 1.0e-3                 # the operator moved the field
        end
        # the raw flux form is the `DivKGrad` form (B's rule)
        rawdiv = [
            Array(
                solve(
                    PottsProblem(
                        M(; name = :f), [fd_empty(dims); :c => c0], (0, k);
                        field_solver = ExplicitEuler(; substeps = n)
                    ), SequentialCPM()
                ).u[end].site.c
            ) for M in (FpRaw, FpDivK)
        ]
        @test rawdiv[1] == rawdiv[2]
    end
end

@testitem "map under repeat, constant velocity, global coordinates, z in 2D" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "map under repeat, constant velocity, global coordinates, z in 2D" begin
        # M1: one map per MCS under `repeat(4, fields)` (base, before the fix: 1.875, 1.9921875, …:
        # one map per pass)
        integ = init(PottsProblem(FpMapRepeat(; name = :f), fd_empty((6, 4)), (0, 3)), SequentialCPM())
        vals = [(step!(integ); Array(current_state(integ).site.m)[1]) for _ in 1:3]
        @test vals == [1.0, 1.5, 1.75]
        # M2: the old refusal's route followed verbatim, `[0.3, 0.0]`, equals the parameter form
        # bitwise (base: "`Advect` takes … or a vector of 2 terms (`[ux, uy]`)")
        c0 = rand(StableRNG(3), 8, 6)
        run(M) = solve(
            PottsProblem(
                M(; name = :f), [fd_empty((8, 6)); :c => c0], (0, 2);
                field_solver = ExplicitEuler(; substeps = 4)
            ), SequentialCPM()
        ).u[end].site.c
        @test run(FpAdvectConst) == run(FpAdvect)
        # M3: a module global `y` read in a body (here a binding of `@fields`) warns (base: the
        # coordinate replaced it silently); a declared `x` does not
        m = Module(:FpGlobals)
        Core.eval(m, :(using Potts; const y = 3.0; const x = 1.0))
        P = FdPDE
        @test_logs (:warn, r"`y` in the model body is the lattice coordinate") match_mode = :any Core.eval(
            m, quote
                @potts_model GlobY begin
                    @kinds medium A
                    @lattice Lattice((6, 4); boundary = Closed())
                    @energy cells(A) => (volume - 9.0)^2
                    @fields $P.volume_read() ($P.volume => y)
                    @sweep Metropolis(; temperature = 1.0)
                end
            end
        )
        @test_logs min_level = Base.CoreLogging.Warn Core.eval(
            m, quote
                @potts_model DeclX begin
                    @kinds medium A
                    @parameters x = 0.5
                    @lattice Lattice((6, 4); boundary = Closed())
                    @energy cells(A) => (volume - 9.0)^2
                    @fields $P.volume_read() ($P.volume => x)
                    @sweep Metropolis(; temperature = 1.0)
                end
            end
        )
        # A helper argument `x` binds `x` in the helper only, so the binding's
        # `x` (the coordinate) still warns (base: the helper silenced the warning for the body)
        @test_logs (:warn, r"`x` in the model body is the lattice coordinate") match_mode = :any Core.eval(
            m, quote
                @potts_model GlobXHelper begin
                    @kinds medium A
                    @lattice Lattice((6, 4); boundary = Closed())
                    g(x) = 2x
                    @energy cells(A) => (volume - 9.0)^2
                    @fields $P.volume_read() ($P.volume => g(1.0) * x)
                    @sweep Metropolis(; temperature = 1.0)
                end
            end
        )
        # controls: reads of `x` only inside binders (a helper, its keyword, a generator) and a
        # keyword name (R2) do not warn
        @test_logs min_level = Base.CoreLogging.Warn Core.eval(
            m, quote
                @potts_model LocalXOnly begin
                    @kinds medium A
                    @lattice Lattice((6, 4); boundary = Closed())
                    g(x) = 2x
                    h(; x = 1.0) = 3x
                    w = sum(x for x in 1:3)
                    @energy cells(A) => (volume - 9.0)^2
                    @fields $P.volume_read() ($P.volume => g(1.0) + h(x = 0.5) + w)
                    @sweep Metropolis(; temperature = 1.0)
                end
            end
        )
        # R3: a wrong-length velocity fails loudly
        err = something(fd_err(() -> mtkcompile(FpAdvectShort(; name = :f))), "")
        @test occursin("[0.3]", err)
        # S4: `Differential(z)` on a 2D lattice is refused
        err = something(fd_err(() -> mtkcompile(FpZ2D(; name = :f))), "")
        @test occursin("`z`", err)
    end
end

@testitem "maps, one kind per model, coordinates" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "maps, one kind per model, coordinates" begin
        LP = Potts.LatticePDE
        # a map steps once per MCS (`ExplicitMap()` by default): m₁ = x, m₂ = 0.5 m₁ + x, …
        integ = init(PottsProblem(FpMap(; name = :f), fd_empty((6, 4)), (0, 3)), SequentialCPM())
        vals = [(step!(integ); copy(Array(current_state(integ).site.m))) for _ in 1:3]
        xs = [i - 0.5 for i in 1:6, j in 1:4]                  # the cell centers along x
        @test vals[1] == xs && vals[2] == 0.5 .* xs .+ xs && vals[3] == 0.5 .* vals[2] .+ xs
        # `solvers` takes `ExplicitMap()` for it; a rate algorithm is refused naming `ExplicitMap()`
        sm = solve(PottsProblem(FpMap(; name = :f), fd_empty((6, 4)), (0, 3); solvers = [:m => ExplicitMap()]), SequentialCPM())
        @test Array(sm.u[end].site.m) == vals[3]
        err = something(fd_err(() -> PottsProblem(FpMap(; name = :f), fd_empty((6, 4)), (0, 3); field_solver = ExplicitEuler())), "")
        @test occursin("ExplicitMap", err)
        # B steps the model's map the same way
        bm = LP.solve(LP.discretize(Potts.fields(FpMap(; name = :f)), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64)), ExplicitMap())
        @test bm[:m, 2] == vals[1] && bm[:m, end] == vals[1]  # B's span is the PDESystem's (0, 1): one map step
        # a rate and a map in one model: refused
        err = something(fd_err(() -> mtkcompile(FpMixed(; name = :f))), "")
        @test occursin("rate", err)
        err = something(
            fd_err(
                () -> LP.discretize(
                    Potts.fields(FpMixed(; name = :f)),
                    LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64)
                )
            ), ""
        )
        @test occursin("rate", err)
        # `z` is the third coordinate: one substep of 0.1 z (cell centers 0.5, 1.5, 2.5)
        uz = solve(PottsProblem(FpZ(; name = :f), fd_empty((4, 4, 3)), (0, 1)), SequentialCPM()).u[end].site.c
        @test all(kk -> all(≈(0.1 * (kk - 0.5); rtol = 1.0e-14), uz[:, :, kk]), 1:3)
    end
end

@testitem "aux fields with states start at rhs (in a model)" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "aux fields with states start at rhs (in a model)" begin
        σ0 = zeros(Int32, 8, 8)
        σ0[3:5, 3:5] .= 1
        c0 = [0.1 * i + 0.01 * j for i in 1:8, j in 1:8]
        integ = init(
            PottsProblem(
                FaState(; name = :s), [ownership => σ0, kind => [:A], :c => c0], (0, 2);
                field_solver = ExplicitEuler(substeps = 2)
            ), SequentialCPM()
        )
        st0 = CorePotts.current_state(integ)
        @test Array(st0.site.c) == c0                                   # the zero-length step moves no state
        @test Array(st0.site.K) ≈ 2 .* c0 .+ 1 rtol = 1.0e-14
        @test Array(integ.saved_u[1].site.K) ≈ 2 .* c0 .+ 1 rtol = 1.0e-14  # the saved start
        # N1: `c` keeps its initial value bitwise under `lower_bound = 0.0`; `K = rhs(u0)`
        ig = init(
            PottsProblem(
                FaLower(; name = :l), [ownership => σ0, kind => [:A]], (0, 2);
                field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)
            ), SequentialCPM()
        )
        sl = CorePotts.current_state(ig)
        @test all(==(-1.0), Array(sl.site.c)) && all(==(-1.0), Array(sl.site.K))
        @test all(==(-1.0), Array(ig.saved_u[1].site.c))
        step!(ig)                                                       # (the step clips: `lower` holds)
        @test minimum(Array(CorePotts.current_state(ig).site.c)) >= 0.0
    end
end

@testitem "aux-only fields in a model" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "aux-only fields in a model" begin
        st(integ) = CorePotts.current_state(integ)
        σ0 = zeros(Int32, 12, 8)
        σ0[3:6, 3:6] .= 1
        # The shape of the custom field algorithm: builds; `cfield = 1` at init (declared 0) and after each MCS; no substep
        integ = init(PottsProblem(FaOne(; name = :a), [ownership => σ0, kind => [:A]], (0, 3)), SequentialCPM())
        @test all(==(1.0), Array(st(integ).site.cfield)) && substep_counts(integ) == [0]
        step!(integ)
        @test all(==(1.0), Array(st(integ).site.cfield))
        # PO07: a `field_solver` names the aux field
        @test_throws ArgumentError PottsProblem(FaOne(; name = :a), [ownership => σ0, kind => [:A]], (0, 1); field_solver = ExplicitEuler())
        # the clock: once per MCS under `repeat(4, …)`, in pass 1 (`time` at the MCS start, `mcs`
        # its number), one launch per MCS; at init `K = 0` (mcs 0, time 0; declared -1)
        s1 = zeros(Int32, 6, 4)
        s1[2:3, 2:3] .= 1
        integ = init(PottsProblem(FaClock(; name = :a), [ownership => s1, kind => [:A]], (0, 3)), SequentialCPM())
        @test all(==(0.0), Array(st(integ).site.K))
        for j in 1:3
            l0 = integ.stats.launches
            step!(integ)
            @test all(==(1.5 * (j - 1)), Array(st(integ).site.K)) && integ.stats.launches - l0 == 1
        end
        # a CPM read: `K` follows the kinds after each sweep (the phase runs after the sweep)
        s2 = zeros(Int32, 12, 12)
        s2[2:5, 2:5] .= 1
        s2[7:10, 7:10] .= 2
        integ = init(PottsProblem(FaKind(; name = :a), [ownership => s2, kind => [:A, :B]], (0, 4); seed = 3), SequentialCPM())
        owner(s) = (σ = Array(s.ownership); [i == 0 ? 0 : (i == 1 ? 1 : 2) for i in σ])
        @test Array(st(integ).site.K) == Float64.(owner(st(integ)) .== 2)
        moved = false
        for _ in 1:4
            σb = Array(st(integ).ownership)
            step!(integ)
            moved |= Array(st(integ).ownership) != σb
            @test Array(st(integ).site.K) == Float64.(owner(st(integ)) .== 2)
        end
        @test moved                                     # the sweep moved the cells
        # a drive that reads `K`: the first sweep reads the init value (`K = 1`), so nothing moves;
        # control: with `K = 0` until the phase of MCS 3 (mcs 2), the sweeps move σ until then, and
        # the sweep after that phase sees `K = 1` and moves nothing
        s3 = zeros(Int32, 12, 12)
        s3[4:7, 4:7] .= 1
        run(m0, n) = (
            ig = init(
                PottsProblem(FaBlock(; name = :a), [ownership => s3, kind => [:A], :m0 => m0], (0, n); seed = 5),
                SequentialCPM()
            );
            [(step!(ig); Array(st(ig).ownership)) for _ in 1:n]
        )
        @test all(==(s3), run(0.0, 2))
        late = run(2.0, 5)
        @test late[1] != s3 && late[2] != late[1] && late[3] != late[2]   # K = 0 in the sweeps of MCS 1–3
        @test late[4] == late[3] && late[5] == late[3]                    # K = 1 from the sweep of MCS 4
    end
end

@testitem "one substep policy, one warning set" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "one substep policy, one warning set" begin
        LP, LFP, MTKB = Potts.LatticePDE, Potts.LatticeFields.Problems, Potts.ModelingToolkitBase
        warns(logs) = count(l -> l.level == Base.CoreLogging.Warn && occursin("does not cover", string(l.message)), logs)
        # the policy warns once per key and process: forget the keys warned so far (by an earlier
        # item in this worker, or an earlier run of this item in a dev session)
        lock(() -> empty!(LFP._SEEN_WARNED), LFP._SEEN_WARNED_LOCK)
        n0 = length(LFP._SEEN_WARNED)
        op = fd_empty((8, 8))
        # A: a sweep over `kw` with an explicit count warns once, in A's words (the A route kept)
        logs, probs = Test.collect_test_logs() do
            [
                PottsProblem(FwNonlinear(; name = :w), [op; :kw => k], (0, 1); field_solver = ExplicitEuler(substeps = 4))
                    for k in (0.5, 0.7, 0.9)
            ]
        end
        @test warns(logs) == 1 && occursin(r"field `c`: 4 substeps per field step.*does not cover `[^`]*c\^2", string(logs[end].message))
        @test length(LFP._SEEN_WARNED) == n0 + 1                       # the one set
        rule = only(
            ph.substeps for e in probs[1].f.phases.mcs for t in (e isa CorePotts.Repeat ? e.entries : (e,))
                if t isa Tuple for ph in t if ph isa CorePotts.FieldPhase && !ph.init
        )
        @test rule isa LFP.GroupSubsteps
        # B: the same term in a PDESystem, a sweep over `kw` warns once more (its own program), in B's words
        Potts.ModelingToolkitBase.@parameters x y Dc = 0.1 kw = 0.5
        Potts.ModelingToolkitBase.@variables c(..)
        ce = c(MTKB.t_nounits, x, y)
        dom = [MTKB.t_nounits ∈ LP.Interval(0.0, 1.0), x ∈ LP.Interval(0.0, 8.0), y ∈ LP.Interval(0.0, 8.0)]
        sys = MTKB.PDESystem(
            [MTKB.D_nounits(ce) ~ Dc * LP.laplacian(ce) - kw * ce^2], [c(0, x, y) ~ 0.0], dom, [MTKB.t_nounits, x, y],
            [ce], [Dc, kw]; name = :w
        )
        bp = LP.discretize(sys, LP.LatticeDiscretization(LP.Grid((8, 8)); T = Float64))
        logs, _ = Test.collect_test_logs() do
            [LP.init(LP.remake(bp; p = [kw => k]), LP.ExplicitEuler(; substeps = 4); dt = 1.0) for k in (0.5, 0.7, 0.9)]
        end
        @test warns(logs) == 1 && occursin("ExplicitEuler(substeps = 4): 4 substeps", string(logs[end].message))
        @test length(LFP._SEEN_WARNED) == n0 + 2
        # The automatic count's refusal of the unseen term comes at `remake`, as at 743ab0a0;
        # at 8f658abd `remake` returned and `init` refused
        @test_throws ArgumentError remake(probs[1]; field_solver = ExplicitEuler())
    end
end

@testitem "an aux-carried loop runs in a model (Jacobi in a group, the split across groups)" setup = [FieldsSetup, FieldsOpBcsSetup] tags = [:potts, :fields] begin
    @testset "an aux-carried loop runs in a model (Jacobi in a group, the split across groups)" begin
        σ = zeros(Int32, 6, 4)
        σ[2:3, 2:3] .= 1
        op = [ownership => σ, kind => [:A]]
        sys = FxLoop(; name = :x)
        cv = only(filter(x -> string(x) in ("c", "c(t)"), Potts.declared_variables(sys)))
        s = solve(PottsProblem(sys, op, (0, 3); field_solver = ExplicitEuler(substeps = 2)), SequentialCPM())
        w, c = 1.0, 0.0
        for _ in 1:6
            w, c = w - 0.5 * c, c + 0.5 * w
        end
        @test s.retcode == Potts.SciMLBase.ReturnCode.Success
        @test all(≈(w; rtol = 1.0e-14), s.u[end].site.w) && all(≈(c; rtol = 1.0e-14), s.u[end].site.c)
        s2 = solve(
            PottsProblem(sys, op, (0, 3); field_solver = ExplicitEuler(substeps = 1), solvers = [cv => ExplicitEuler(substeps = 2)]),
            SequentialCPM()
        )
        w, c = 1.0, 0.0
        for _ in 1:3
            w = w - c                                       # w's group: K = c, held over the MCS
            for _ in 1:2
                c = c + 0.5 * w                             # c's group reads the new w
            end
        end
        @test all(≈(w; rtol = 1.0e-14), s2.u[end].site.w) && all(≈(c; rtol = 1.0e-14), s2.u[end].site.c)
    end
end
