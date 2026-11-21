# Split from test/symbolic_tests.jl

@testitem "discrete components: lag-2 recurrence (Fibonacci oracle)" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: lag-2 recurrence (Fibonacci oracle)" begin
        σ = _discrete_blocks(2)
        cs = mtkcompile(DiscreteFib(; name = :f))
        @test Set(
            Potts.info(v).name
                for v in Potts.declared_variables(getfield(cs, :sys))
        ) ==
            Set([:fib₊fz, Symbol("fib₊fzₜ₋₁")])
        # the older lag has no MTK default: the operating point must give it
        @test_throws ArgumentError PottsProblem(
            cs, [ownership => σ, kind => [1, 1]], (
                0, 6,
            )
        )
        prob = PottsProblem(
            cs, [
                ownership => σ, kind => [1, 1], Symbol("fib₊fzₜ₋₁") => [0.0, 1.0],
            ], (0, 6)
        )
        function fibs(a, b, n)
            out = [a]
            for _ in 1:n
                a, b = a + b, a
                push!(out, a)
            end
            return out
        end
        for alg in _DISCRETE_ALGS
            sol = solve(prob, alg; saveat = 0:6)
            # 1, 1, 2, 3, 5, 8, 13
            @test [u.cell.fib₊fz[1] for u in sol.u] == fibs(1.0, 0.0, 6)
            # 1, 2, 3, 5, 8, 13, 21
            @test [u.cell.fib₊fz[2] for u in sol.u] == fibs(1.0, 1.0, 6)
            @test sol[Symbol("fib₊fzₜ₋₁")][end] == [8.0, 13.0]
        end
    end
end

@testitem "discrete components: clock periods, phases and mcs_duration" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: clock periods, phases and mcs_duration" begin
        σ = _discrete_blocks(2)
        op = [ownership => σ, kind => [1, 1]]
        function ticks(sys; n = 12)
            return [
                u.cell.ctr₊dn[1]
                    for u in solve(
                        PottsProblem(sys, op, (0, n)), SequentialCPM();
                        saveat = 0:n
                    ).u
            ]
        end
        # MTK clock time: ticks at t = phase + k·dt; the state saved at t has had that many
        # ticks
        oracle(dt, phase, n) = [Float64(count(τ -> 0 < τ <= t, phase:dt:n)) for t in 0:n]
        @test ticks(discrete_counter_model(_kd)) == 0:12
        @test ticks(discrete_counter_model(ShiftIndex(Clock(1.0)))) == 0:12
        @test ticks(discrete_counter_model(ShiftIndex(Clock(3.0)))) == oracle(3, 0, 12)
        @test ticks(discrete_counter_model(ShiftIndex(Clock(3.0; phase = 1.0)))) ==
            oracle(3, 1, 12)
        # the phase is visible
        @test oracle(3, 1, 12) != oracle(3, 0, 12)
        # the period is model time: Clock(1) at half an MCS per MCS is one tick every two
        # MCS
        @test ticks(discrete_counter_model(ShiftIndex(Clock(1.0)); mcs_duration = 0.5)) ==
            oracle(2, 0, 12)
        # a step count, no period
        @test ticks(discrete_counter_model(_kd; mcs_duration = 0.5)) == 0:12
        for bad in (Clock(2.5), Clock(3.0; phase = 0.5), Clock(3.0; phase = 3.0))
            @test_throws Potts.PottsCompileError mtkcompile(
                discrete_counter_model(ShiftIndex(bad))
            )
        end
    end
end

@testitem "discrete components: model scope" setup = [SymbolicSetup] tags = [
    :potts,
    :symbolic,
] begin
    @testset "discrete components: model scope" begin
        σ = _discrete_blocks(3)
        sys = discrete_counter_model(ShiftIndex(Clock(2.0)); scope = :model)
        prob = PottsProblem(sys, [ownership => σ, kind => [1, 1, 1]], (0, 8))
        @test :ctr₊dn in propertynames(prob.u0.model)
        for alg in _DISCRETE_ALGS
            sol = solve(prob, alg; saveat = 0:8)
            # 3 live cells per tick
            @test [u.model.ctr₊dn[1] for u in sol.u] == [3.0 * (t ÷ 2) for t in 0:8]
        end
    end
end

@testitem "discrete components: hold, sample and the tick after the ODEs" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: hold, sample and the tick after the ODEs" begin
        σ = _discrete_blocks(2)
        prob = PottsProblem(
            DiscreteHybrid(; name = :h),
            [ownership => σ, kind => [1, 1], Symbol("tg₊dA") => [false, true]], (0, 8)
        )
        for alg in _DISCRETE_ALGS
            sol = solve(prob, alg; saveat = 0:8)
            for c in 1:2
                # the toggle after m ticks
                A = [isodd(m + c - 1) for m in 0:8]
                @test [u.cell.tg₊dA[c] for u in sol.u] == Float64.(A)
                # the ODE of MCS m sees A after m ticks (held over the MCS): Euler with r =
                # 0.1·A
                @test [u.cell.rel₊yx[c] for u in sol.u] ≈
                    [
                    prod(1 - 0.1 * A[j + 1] for j in 0:(m - 1); init = 1.0)
                        for m in 0:8
                ] rtol = 1.0e-12
                # the tick of MCS m samples x = m + 1 (the ODE step of the same MCS came
                # first)
                @test [u.cell.smp₊dB[c] for u in sol.u] == [t >= 3 ? 1.0 : 0.0 for t in 0:8]
                # after-MCS updates run before the tick: they read A after m ticks
                @test sol.u[end].cell.seen[c] == count(A[1:8])
            end
        end
    end
end

@testitem "discrete components: per-cell draws (asynchronous updating in MTK form)" setup =
    [SymbolicSetup] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: per-cell draws (asynchronous updating in MTK form)" begin
        σ = _discrete_blocks(100, 40)
        prob = PottsProblem(
            DiscreteCoin(; name = :c), [
                ownership => σ, kind => fill(1, 100),
            ], (0, 40)
        )
        sols = [solve(prob, alg; saveat = 0:40) for alg in _DISCRETE_ALGS]
        A = reduce(hcat, [u.cell.cn₊dA for u in sols[1].u])
        # keyed draws: the sweep does not matter
        @test A == reduce(hcat, [u.cell.cn₊dA for u in sols[2].u])
        flips = count(A[:, 2:end] .!= A[:, 1:(end - 1)]) / length(A[:, 2:end])
        @test abs(flips - 0.5) < 4 * sqrt(0.25 / length(A[:, 2:end]))       # P(flip) = 1/2
        @test all(x -> x == 0 || x == 1, A)
    end
end

@testitem "discrete components: statements and couplings" setup = [SymbolicSetup] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: statements and couplings" begin
        @potts_model DiscreteBad begin
            @structural_parameters case = :ok
            @kinds medium A
            @variables inp(cell) = 0.0
            @components cells(A) tg = toggle
            if case === :ok
                @after_mcs inp ~ 1.0
            elseif case === :write
                @after_mcs tg.dA ~ 1.0
            else
                @equations tg.dA ~ inp
            end
            @lattice Lattice((8, 8))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0)
        end
        # a node evolves only by its ticks (control: the same model without the statement
        # compiles)
        @test mtkcompile(DiscreteBad(; name = :b, case = :ok)) isa CompiledPottsSystem
        @test_throws Potts.PottsCompileError mtkcompile(
            DiscreteBad(; name = :b, case = :write)
        )
        @test_throws Potts.PottsCompileError mtkcompile(
            DiscreteBad(; name = :b, case = :param)
        )
        # a Bool parameter coupled to a Real expression reads it as `!iszero`
        σ = _discrete_blocks(2, 8)
        _DISCRETE_SYS[] = sampler
        @potts_model DiscreteRealCoupling begin
            @kinds medium A
            @variables inp(cell) = 0.0
            @components cells(A) smp = _DISCRETE_SYS[]
            @equations smp.dsig ~ inp
            @lattice Lattice((8, 8))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        u = solve(
            PottsProblem(
                DiscreteRealCoupling(; name = :r),
                [ownership => σ, kind => [1, 1], :inp => [0.0, 0.3]], (0, 1)
            ),
            SequentialCPM()
        ).u[end]
        @test u.cell.smp₊dB == [0.0, 1.0]
        # an uncoupled Bool parameter is a model parameter holding 0/1
        @potts_model DiscreteBoolParameter begin
            @kinds medium A
            @components cells(A) smp = _DISCRETE_SYS[]
            @lattice Lattice((8, 8))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        p = PottsProblem(
            DiscreteBoolParameter(; name = :b), [
                ownership => σ, kind => [1, 1],
            ], (0, 1)
        )
        @test p.p.smp₊dsig === 0.0
        @test solve(
            remake(p; p = [Symbol("smp₊dsig") => true]),
            SequentialCPM()
        ).u[end].cell.smp₊dB ==
            [1.0, 1.0]
        # components travel through `extend`
        @potts_model DiscreteExtended begin
            @extend base = DiscreteFib()
            @kinds medium A
            @parameters λx = 2.0
            @energy cells => λx * (volume - 9.0)^2
        end
        ec = mtkcompile(DiscreteExtended(; name = :e))
        @test only(getfield(ec, :discrete)).name === :fib &&
            length(getfield(ec, :cell_terms)) == 2
    end
end

@testitem "discrete components: ticks on one MCS are Jacobi across phases" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: ticks on one MCS are Jacobi across phases" begin
        @potts_model DiscreteOrderCM begin
            @kinds medium A
            @components cells(A) cc = xcell
            @components model mm = mmodel
            @equations begin
                cc.ds ~ mm.dM > 0.5
                mm.dq ~ 1.0 + count(true for c in cells)
            end
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        @potts_model DiscreteOrderMC begin
            @kinds medium A
            @components model mm = mmodel
            @components cells(A) cc = xcell
            @equations begin
                cc.ds ~ mm.dM > 0.5
                mm.dq ~ 1.0 + count(true for c in cells)
            end
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        @potts_model DiscreteOrderZY begin
            @kinds medium A
            @components cells(A) zz = zslow
            @components cells(A) yy = yfast
            @equations yy.dw ~ zz.dZ
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        @potts_model DiscreteOrderYZ begin
            @kinds medium A
            @components cells(A) yy = yfast
            @components cells(A) zz = zslow
            @equations yy.dw ~ zz.dZ
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        σ = _discrete_blocks(2)
        function run(sys)
            return solve(
                PottsProblem(sys, [ownership => σ, kind => [1, 1]], (0, 5)),
                SequentialCPM(); saveat = 0:5
            )
        end
        # cell and model scope on one clock: X reads M before the tick
        for M in (DiscreteOrderCM, DiscreteOrderMC)
            sol = run(M(; name = :xm))
            @test [u.model.mm₊dM[1] for u in sol.u] == [0.0; fill(3.0, 5)]
            # one tick behind M
            @test [u.cell.cc₊dX[1] for u in sol.u] == [0.0, 0.0, 1.0, 1.0, 1.0, 1.0]
            # published after both
            @test :cc₊dX__tick in propertynames(sol.u[1].cell)
        end
        # two clocks coinciding on even t: Y reads Z before Z's tick
        for M in (DiscreteOrderZY, DiscreteOrderYZ)
            sol = run(M(; name = :zy))
            Z = [isodd(t ÷ 2) for t in 0:5]
            @test [u.cell.zz₊dZ[1] for u in sol.u] == Float64.(Z)
            @test [u.cell.yy₊dY[1] for u in sol.u] == Float64.([false; Z[1:5]])
        end
        # a single phase writes its slots directly (no scratch)
        @test !(
            :tg₊dA__tick in propertynames(
                PottsProblem(
                    DiscreteHybrid(; name = :h), [ownership => σ, kind => [1, 1]], (0, 1)
                ).u0.cell
            )
        )
    end
end

@testitem "discrete components: a Bool node indexed by a cell" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: a Bool node indexed by a cell" begin
        @potts_model DiscreteIndexed begin
            @kinds medium A
            @variables begin
                got(cell) = 0.0
                amp(cell) = 0.0
                neg(cell) = 0.0
                sel(cell) = 0.0
            end
            @components cells(A) tg = toggle
            @after_mcs begin
                got ~ 1.0 + tg.dA[id]                          # as a number: 0/1
                amp ~ ifelse(tg.dA[id] & (volume > 1), 1.0, 0.0)   # as a Bool
                neg ~ ifelse(!tg.dA[id], 1.0, 0.0)
                sel ~ ifelse(tg.dA[id], 1.0, 0.0)
            end
            @lattice Lattice((8, 8))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        σ = _discrete_blocks(2, 8)
        u = solve(
            PottsProblem(
                DiscreteIndexed(; name = :i),
                [ownership => σ, kind => [1, 1], Symbol("tg₊dA") => [false, true]],
                (0, 1)
            ),
            SequentialCPM()
        ).u[end]
        # the updates run before the MCS-0 tick
        @test u.cell.got == [1.0, 2.0] && u.cell.amp == [0.0, 1.0] &&
            u.cell.neg == [1.0, 0.0] && u.cell.sel == [0.0, 1.0]
    end
end

@testitem "discrete components: Jacobi across cells (shift register)" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: Jacobi across cells (shift register)" begin
        prob = PottsProblem(
            DiscreteShiftRegister(; name = :s),
            [ownership => _discrete_blocks(6, 16), kind => fill(1, 6)], (0, 4)
        )
        # a cross-cell read ticks through scratch
        @test :xc₊dX__tick in propertynames(prob.u0.cell)
        for alg in _DISCRETE_ALGS
            sol = solve(prob, alg; saveat = 0:4)
            @test [u.cell.xc₊dX for u in sol.u] == shift_register_oracle.(0:4)
        end
    end
end

@testitem "discrete components: array variables" setup = [SymbolicSetup] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: array variables" begin
        cs = mtkcompile(DiscreteArray(; name = :a))
        @test Set(
            Potts.info(v).name
                for v in Potts.declared_variables(getfield(cs, :sys))
        ) == Set([:ar₊dz_1, :ar₊dz_2])
        sol = solve(
            PottsProblem(cs, [ownership => _discrete_blocks(1, 8), kind => [1]], (0, 5)),
            SequentialCPM(); saveat = 0:5
        )
        # (z1, z2) ← (!z2, z1) from the array default (0, 1): (0,1) → (0,0) → (1,0) → (1,1)
        # → (0,1) → (0,0)
        @test [(u.cell.ar₊dz_1[1], u.cell.ar₊dz_2[1]) for u in sol.u] ==
            [(0.0, 1.0), (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]
    end
end

@testitem "discrete components: an under-determined node" setup = [SymbolicSetup] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete components: an under-determined node" begin
        @named undet = System([dX(_kd) ~ ds & dY(_kd)], _tc)
        _DISCRETE_SYS[] = undet
        @potts_model DiscreteUndetermined begin
            @kinds medium A
            @components cells(A) ud = _DISCRETE_SYS[]
            @lattice Lattice((8, 8))
            @sweep Metropolis(; temperature = 1.0)
        end
        @test_throws Potts.PottsCompileError mtkcompile(DiscreteUndetermined(; name = :u))
    end
end

@testitem "discrete compile errors: MTK's relabelled, Potts' own propagate" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "discrete compile errors: MTK's relabelled, Potts' own propagate" begin
        comp = Potts.ComponentSpec(
            :grn, System([dA(_kd) ~ !dB(_kd - 1), dB(_kd) ~ dA(_kd - 1)], _tc; name = :grn),
            :model
        )
        # an MTK failure (an unknown with no update) names the component
        bad = Potts.ComponentSpec(
            :grn, System([k2X(_kd) ~ k2Y(_kd - 1)], _tc; name = :grn),
            :model
        )
        err = try
            Potts._compile_discrete(bad)
            nothing
        catch e
            e
        end
        @test err isa Potts.PottsCompileError
        # a non-Potts error raised inside the compile call: relabelled
        err = try
            Potts._mtk_compile_call(sys -> throw(DomainError(sys, "outside Potts")), comp)
            nothing
        catch e
            e
        end
        @test err isa Potts.PottsCompileError
        # a Potts internal broken on purpose (a MethodError raised in components.jl):
        # unchanged
        err = try
            Potts._mtk_compile_call(
                sys -> Potts._clock_cadence(comp, nothing, Any[], 1.0),
                comp
            )
            nothing
        catch e
            e
        end
        @test err isa MethodError
        err = try
            Potts._mtk_compile_call(sys -> Potts._discrete_plan(comp, nothing, 1.0), comp)
            nothing
        catch e
            e
        end
        @test err isa MethodError
    end
end

@testitem "stdlib frames are not Potts', brownians are rejected" setup = [
    SymbolicSetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "stdlib frames are not Potts', brownians are rejected" begin
        # a stdlib frame (recorded under the build machine's path) is not Potts code
        bt = try
            Statistics.quantile([1.0], 2.0)
        catch
            catch_backtrace()
        end
        @test !Potts._raised_in_potts(bt)
        Potts.ModelingToolkitBase.@variables y(Potts.t) = 1.0
        Potts.ModelingToolkitBase.@parameters k = 0.3
        Potts.ModelingToolkitBase.@brownians B
        noisy = System([Potts.D(y) ~ -k * y + 5.0 * B], Potts.t; name = :noisy)
        err = try
            Potts._reject_ignored_features(Potts.ComponentSpec(:noisy, noisy, :model))
            nothing
        catch e
            e
        end
        @test err isa Potts.PottsCompileError
    end
end
