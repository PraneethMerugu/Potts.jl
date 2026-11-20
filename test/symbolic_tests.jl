# Split from test/symbolic_tests.jl

@testitem "symbolic models equal the hand-written ports: name" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "symbolic models equal the hand-written ports: $name" for (name, sym, hand) in (
            ("graner", () -> symbolic_graner_problem(; nmcs = 20), () -> graner_problem(; nmcs = 20)),
            ("wortel", symbolic_wortel_problem, wortel_problem),
            ("merks", symbolic_merks_problem, merks_problem),
            ("openvt", symbolic_openvt_problem, openvt_problem),
        )
        sp, hp = sym(), hand()
        ctx = merge(ctx_of(hp), ctx_of(sp))
        worst_h = 0.0; worst_e = 0.0
        agree_c = true; agree_commit = true
        for (u, prop) in proposal_states(sp)
            dHs = sp.f.delta_H(u, sp.p, prop, ctx)
            dHh = hp.f.delta_H(u, hp.p, prop, ctx)
            worst_h = max(worst_h, abs(dHs - dHh))
            agree_c &= sp.f.constraint(u, sp.p, prop, ctx) == hp.f.constraint(u, hp.p, prop, ctx)
            # commit: both applied to copies after the ownership write
            a = deepcopy(u); b = deepcopy(u)
            a.ownership[prop.target] = prop.new; b.ownership[prop.target] = prop.new
            sp.f.commit!(a, sp.p, prop, ctx); hp.f.commit!(b, hp.p, prop, ctx)
            agree_commit &= all(k -> getfield(a.cell, k) == getfield(b.cell, k), intersect(keys(a.cell), keys(b.cell))) &&
                all(k -> getfield(a.site, k) == getfield(b.site, k), intersect(keys(a.site), keys(b.site)))
            # self-check: ΔE equals H(after) − H(before)
            H0 = total_energy(sp, u)
            H1 = total_energy(sp, a)
            worst_e = max(worst_e, abs(energy_change(sp, u, prop) - (H1 - H0 + Potts._killing_credit(sp, u, prop, a))))
        end
        @test worst_h < 1.0e-9
        @test agree_c
        @test agree_commit
        @test worst_e < 1.0e-9
        # trajectories agree too (same address-keyed randomness, same functions)
        tspan = (0, 15)
        us = solve(remake(sp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
        uh = solve(remake(hp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
        @test us.ownership == uh.ownership
    end
end


@testitem "symbolic surface: generated code" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "symbolic surface: generated code" begin
        ex = Potts.generated_code(SORTING)
        @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[]], (0, 1); expression = Val(true))
        @test _has_ast(ex.delta_H, node -> node == :(p.J)) &&
            _has_ast(ex.delta_H, node -> node == :(st.cell.volume))
        @test !_has_ast(ex.delta_H, node -> node isa Expr && node.head === :call && node.args[1] === :^)   # closed form
        prob = symbolic_graner_problem(; nmcs = 5)
        @test remake(prob; p = [:λ => 2.0]).f === prob.f                  # parameters change, code does not
        @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 4, 4)], (0, 1))
        @test_throws ArgumentError PottsProblem(
            SORTING, [
                ownership => zeros(Int32, 72, 72), kind => Int[],
                first(filter(x -> Potts.info(x).name === :J, Potts.declared_parameters(getfield(SORTING, :sys)))) => [0 1 1; 2 0 1; 1 1 0],
            ], (0, 1)
        )
    end
end


@testitem "symbolic surface: a constant integer power is a product chain" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "symbolic surface: a constant integer power is a product chain" begin
        # values through a solved problem, against Base's `^` in Float64
        @potts_model PowerValues begin
            @kinds medium A
            @variables begin
                z(cell) = 1.3
                p4(cell) = 0.0
                p5(cell) = 0.0
                p7(cell) = 0.0
                p13(cell) = 0.0
                m3(cell) = 0.0
                vol(cell) = 0.0
                vm3(cell) = 0.0
            end
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @after_mcs begin
                p4 ~ z^4
                p5 ~ z^5
                p7 ~ z^7
                p13 ~ z^13
                m3 ~ z^-3
                vol ~ volume
                vm3 ~ volume^-3
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        σ = zeros(Int32, 12, 8)
        σ[2:5, 2:5] .= 1
        σ[7:10, 2:5] .= 2
        for T in (Float32, Float64)
            sol = solve(PottsProblem(PowerValues(; name = :m), [ownership => σ, kind => [:A, :A]], (0, 2); T, seed = 1), SequentialCPM())
            z = Float64(T(1.3))
            for (name, n) in ((:p4, 4), (:p5, 5), (:p7, 7), (:p13, 13), (:m3, -3))
                v = last(sol[name])
                @test eltype(v) === T
                @test all(isapprox.(v, z^n; rtol = abs(n) * eps(T)))
            end
            # an integer base with a negative power computes in the model's float type
            vm3 = last(sol[:vm3])
            @test eltype(vm3) === T
            @test all(isapprox.(vm3, Float64.(last(sol[:vol])) .^ -3; rtol = 3 * eps(T)))
        end
        # the generated code: no `^` for a constant integer (also an integer-valued float);
        # a float or a parameter exponent still calls `^`
        @potts_model IntPowers begin
            @kinds medium A
            @variables y(cell) = 1.0 z(cell) = 1.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @equations begin
                D(y) ~ 2.0 * z^4 / (0.5^4 + z^5) - 0.3 * y^7 + y^2.0
                D(z) ~ -0.2 * z^-3
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        @potts_model FloatPower begin
            @kinds medium A
            @variables y(cell) = 1.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @equations D(y) ~ 0.1 * y^2.5
            @sweep Metropolis(; temperature = 1.0)
        end
        @potts_model ParameterPower begin
            @kinds medium A
            @parameters k = 1.5
            @variables y(cell) = 1.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @equations D(y) ~ 0.1 * y^k
            @sweep Metropolis(; temperature = 1.0)
        end
        is_pow(x) = x isa Expr && x.head === :call && (x.args[1] === :^ || x.args[1] === ^)
        has(x, pred) = x isa Union{Tuple, NamedTuple, AbstractVector} ? any(y -> has(y, pred), x) : _has_ast(x, pred)
        code(M) = generated_code(M(; name = :m))
        @test !has(code(IntPowers), is_pow)
        # the negative power of the integer `volume` takes a float base in the model's type
        reads_volume(x) = x == :(st.cell.volume)
        function is_float_volume_power(x)
            return x isa Expr && x.head === :call && x.args[1] == :(Potts.LatticeFields.Compile.powi) &&
                _has_ast(x.args[2], reads_volume) && _has_ast(x.args[2], y -> y == :(Potts._tofloat))
        end
        @test has(code(PowerValues), is_float_volume_power)
        @test has(code(FloatPower), is_pow) && has(code(ParameterPower), is_pow)
    end
end


@testitem "rebuilding a problem reuses the generated code" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "rebuilding a problem reuses the generated code" begin
        a = symbolic_wortel_problem(; seed = 1)
        b = symbolic_wortel_problem(; seed = 2)
        @test typeof(a.f) === typeof(b.f)
        @test a.f.fingerprint == b.f.fingerprint
    end
end


@testitem "remake with symbolic maps; the sweep law" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "remake with symbolic maps; the sweep law" begin
        prob = symbolic_graner_problem(; nmcs = 5)
        λ = first(filter(x -> Potts.info(x).name === :λ, Potts.declared_parameters(getfield(SORTING, :sys))))
        q = remake(prob; p = [λ => 3.0])
        @test q.p.λ == 3.0 && q.p.V₀ == prob.p.V₀ && q.f === prob.f
        @test remake(prob; p = Dict(:T => 2)).p.T === 2.0              # converted to the scalar type
        @test_throws ArgumentError remake(prob; p = [:nope => 1.0])
        σ, kinds = graner_state()
        r = remake(prob; u0 = [ownership => circshift(σ, (3, 0)), kind => kinds])
        @test r.u0.ownership == circshift(σ, (3, 0)) && r.u0.cell.volume == prob.u0.cell.volume
        @test prob.f.acceptance === Metropolis()
    end
end


@testitem "remake: whole parameter objects, keep sentinels, non-maps" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "remake: whole parameter objects, keep sentinels, non-maps" begin
        prob = symbolic_graner_problem(; nmcs = 5)
        # a whole object of this problem's type is taken as given
        q = remake(prob; p = [:λ => 3.0])
        @test remake(prob; p = q.p).p === q.p
        # another model's object: an ArgumentError naming the differing names, not a later failure
        other = symbolic_wortel_problem()
        err = try
            remake(prob; p = other.p); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test prob.p.λ == symbolic_graner_problem(; nmcs = 5).p.λ        # source unchanged
        # a Float32 problem's object: values taken, converted to this problem's scalar type
        p32 = remake(symbolic_graner_problem(; nmcs = 5, T = Float32); p = [:λ => 4.0, :T => 3.0])
        @test eltype(p32.p.V₀) === Float32
        r = remake(prob; p = p32.p)
        @test typeof(r.p) === typeof(prob.p)
        @test r.p.λ === 4.0 && r.p.T === 3.0 && r.p.V₀ == Float64.(p32.p.V₀)
        @test solve(remake(r; tspan = (0, 1)), SequentialCPM()).u[end].cell.volume isa AbstractVector
        # SciML keep sentinels
        @test remake(q; p = missing).p === q.p
        @test remake(q; p = nothing).p === q.p
        @test remake(prob; u0 = nothing).u0.ownership == prob.u0.ownership
        @test remake(prob; u0 = missing).u0.cell.volume == prob.u0.cell.volume
        integ = init(prob, SequentialCPM())
        step!(integ)
        reinit!(integ, nothing)
        @test integ.state.ownership == prob.u0.ownership && integ.t == 0
        # non-states and non-maps: ArgumentErrors, not MethodErrors or silent replacement
        @test_throws ArgumentError remake(prob; u0 = 3.0)
        @test_throws ArgumentError remake(prob; u0 = [1, 2])
        @test_throws ArgumentError reinit!(integ, "state")
        @test_throws ArgumentError remake(prob; p = 3.0)
    end
end


@testitem "Float32 models never touch Float64" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "Float32 models never touch Float64" begin
        @potts_model FloatModel begin
            @kinds medium A
            @parameters begin
                λ = 1.0
                T = 8.0
            end
            @lattice Lattice((16, 16); neighborhood = Moore(1))
            @energy cells(A) => λ * (surface - 4 * sqrt(volume))^2 + log(2) * volume / 3
            @fields c = SyPDE.float() (SyPDE.src => kind == A)
            @drive copy => -2 * (c[target] - c[source]) / 3
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 16, 16); σ[5:10, 5:10] .= 1
        prob = PottsProblem(FloatModel(; name = :fm), [ownership => σ, kind => [1]], (0, 2); T = Float32, field_solver = ExplicitEuler())
        ctx = ctx_of(prob)
        prop = CorePotts.Proposal(4 + 16 * 5, 5 + 16 * 5, (4, 6), 1, Int32(0), Int32(1))
        io = IOBuffer()
        code_llvm(io, prob.f.delta_H, typeof.((prob.u0, prob.p, prop, ctx)); debuginfo = :none)
        @test !occursin("double", String(take!(io)))
        @test prob.f.delta_H(prob.u0, prob.p, prop, ctx) isa Float32
        @test selfcheck(PottsProblem(FloatModel(; name = :fm), [ownership => σ, kind => [1]], (0, 2); field_solver = ExplicitEuler())) < 1.0e-9
    end
end


@testitem "macro: plain Julia stays plain; keyword overrides" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "macro: plain Julia stays plain; keyword overrides" begin
        @potts_model Helpers begin
            @kinds medium A
            firstor0(v) = isempty(v) ? 0.0 : v[1]            # plain Julia: lazy ternary, real indexing
            w = zeros(2)
            w[1] = 3.0                                        # indexed assignment is not rewritten
            total = sum(w[i] for i in eachindex(w))           # an ordinary generator
            ok = w[1] > 0 && firstor0(Float64[]) == 0.0       # short-circuit on real values
            @parameters begin
                λ = firstor0(w) + total
                T = ok ? 5.0 : 1.0
            end
            @lattice Lattice((8, 8); neighborhood = Moore(1))
            @energy cells(A) => λ * volume
            @sweep Metropolis(; temperature = T)
        end

        sys = Helpers(; name = :h)
        vals = Dict(Potts.info(p).name => Potts.info(p).default for p in Potts.declared_parameters(sys))
        @test vals[:λ] == 6.0 && vals[:T] == 5.0
        sys2 = Helpers(; name = :h, λ = 2.0)
        @test Potts.info(first(Potts.declared_parameters(sys2))).default == 2.0
        # constructing a model twice yields the same generated code (gathers numbered per model)
        σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1
        a = PottsProblem(WortelAct(; name = :w, lattice = (8, 8)), [ownership => σ, kind => [1]], (0, 1))
        b = PottsProblem(WortelAct(; name = :w, lattice = (8, 8)), [ownership => σ, kind => [1]], (0, 1))
        @test a.f.fingerprint == b.f.fingerprint && typeof(a.f) === typeof(b.f)
    end
end


@testitem "model variables, populations, observed and SII" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "model variables, populations, observed and SII" begin
        σ, kinds = two_kind_blocks()
        sys = Census(; name = :census)
        prob = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 6))
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = [2, 4, 6])
        named(n) = only(filter(x -> Potts.info(x).name === n, vcat(Potts.declared_variables(sys), [o.lhs for o in Potts._p(sys, :observed)], Potts.declared_parameters(sys))))
        live(u) = findall(>(0), u.cell.volume)
        @test sol[named(:total)] == [sum(u.site.act) for u in sol.u]
        @test sol[named(:ndark)][2:end] == [count(c -> kinds[c] == 1, live(u)) for u in sol.u[2:end]]   # t = 0: default
        @test sol[named(:ndark)][1] == 0
        @test sol[named(:mean_volume)] ≈ [sum(u.cell.volume[live(u)]) / length(live(u)) for u in sol.u]
        @test sol[named(:dark_area)] == [sum(u.cell.volume[c] for c in live(u) if kinds[c] == 1; init = 0) for u in sol.u]
        @test sol[named(:big)][end] == (sol.u[end].cell.volume .> 25)
        @test sol[named(:excess)] == sol[named(:dark_area)] .- 25 .* sol[named(:ndark)]
        @test prob.p isa Potts.PottsParameters && isbits(prob.p)
        @test sol[Potts.kind][1] == kinds                                   # built-ins observe too
        @test sol[named(:act)][end] == sol.u[end].site.act
        @test observe(prob, named(:mean_volume)) ≈ 25.0
        SII = Potts.SymbolicIndexingInterface
        @test SII.getp(prob, named(:λ))(prob) == 1.0
        @test SII.getp(sol, named(:T))(sol) == 10.0
    end
end


@testitem "library one-liners, per-kind temperature, frozen kinds" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "library one-liners, per-kind temperature, frozen kinds" begin
        @potts_model LibrarySorting begin
            @kinds medium dark light
            @parameters begin
                λ = 1.0
                V₀ = 40.0
                T = 10.0
                J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
            end
            @lattice Lattice((72, 72); boundary = Periodic(), neighborhood = Moore(1))
            @energy begin
                Volume(dark, light; target = V₀, strength = λ)
                Adhesion(J)
            end
            @sweep Metropolis(; temperature = T)
        end

        a = symbolic_graner_problem(; nmcs = 5)
        σ, kinds = graner_state()
        b = PottsProblem(LibrarySorting(; name = :lib), [ownership => σ, kind => kinds], (0, 5))
        @test all(
            ((u, prop),) -> a.f.delta_H(u, a.p, prop, ctx_of(a)) == b.f.delta_H(u, b.p, prop, ctx_of(b)),
            proposal_states(a; mcs = (0, 5), n = 200)
        )

        σk = zeros(Int32, 24, 24); σk[:, 1:2] .= 1                 # a wall along one side
        for (c, (i, j)) in enumerate(Iterators.product(2:6:20, 6:6:18))
            σk[i:(i + 4), j:(j + 4)] .= c + 1
        end
        n = maximum(σk)
        kinds = [c == 1 ? :wall : isodd(c) ? :dark : :light for c in 1:n]
        prob = PottsProblem(KindTemperature(; name = :kt), [ownership => σk, kind => kinds], (0, 20))
        ctx = ctx_of(prob)
        Tof(old, new) = prob.f.temperature(prob.u0, prob.p, CorePotts.Proposal(1, 2, (1, 1), 1, Int32(old), Int32(new)), ctx)
        dark_cell = findfirst(==(:dark), kinds); light_cell = findfirst(==(:light), kinds)
        @test Tof(dark_cell, light_cell) == 5.0 && Tof(light_cell, dark_cell) == 5.0     # min of the two
        @test Tof(0, light_cell) == 20.0 && Tof(dark_cell, 0) == 5.0                     # medium never contributes
        u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
        @test u.ownership[:, 1:2] == σk[:, 1:2] && u.cell.volume[1] == 48                       # the wall never moves
        @test u.ownership != σk
    end
end


@testitem "symbolic setters: setp and setu on integrators" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "symbolic setters: setp and setu on integrators" begin
        σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
        p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 6); seed = 2)
        integ = init(p, SequentialCPM())
        step!(integ)
        # parameters: same isbits type (nothing recompiles), effective from the next MCS
        P = typeof(integ.p)
        integ.ps[:μ] = 700
        @test integ.ps[:μ] === 700.0 && typeof(integ.p) === P
        setp(integ, :μ)(integ, 800.0)
        @test getp(integ, :μ)(integ) == 800.0
        setp(p, :μ)(p, 1.0)                                                  # problems too (SII)
        @test getp(p, :μ)(p) == 1.0
        # state: declared variables write through to the live state; built-ins are read-only
        integ[:px] = [0.5]
        @test integ.state.cell.px == [0.5] && integ[:px] == [0.5] && getu(integ, :px)(integ) == [0.5]
        setu(integ, :py)(integ, -0.25)
        @test integ.state.cell.py == [-0.25]
        @test_throws DimensionMismatch (integ[:px] = [1.0, 2.0])
        err_vol = try
            integ[:volume] = [3]
            nothing
        catch err
            err
        end
        @test err_vol isa ErrorException
        # a built-in in a list setter is read-only, not unknown (D-116); nothing is set
        for f in (() -> setu(integ, [:kind, :μ]), () -> setp(integ, [:μ, :volume]))
            e = try
                f(); nothing
            catch err
                err
            end
            @test e isa ArgumentError
        end
        e = try
            setu(integ, [:zz, :μ]); nothing
        catch err
            err
        end
        @test e isa ArgumentError   # control: unknown
        @test integ.ps[:μ] == 800.0
        sol = solve!(integ)
        @test sol[:x][end][1] ≈ sol.u[end].cell.cx[1]                     # observed still derived
        @test sol[:px][end] == sol.u[end].cell.px
        SII = Potts.SymbolicIndexingInterface
        @test SII.is_variable(p.f.sys, :px) && !SII.is_variable(p.f.sys, :volume) && SII.is_observed(p.f.sys, :volume)
        @potts_model Counter begin
            @kinds medium A
            @variables n(model) = 0.0
            @lattice Lattice((8, 8))
            @after_mcs n ~ Pre(n) + 1
            @sweep Metropolis(; temperature = 1.0)
        end
        σc = zeros(Int32, 8, 8); σc[3:5, 3:5] .= 1
        ic = init(PottsProblem(Counter(; name = :c), [ownership => σc, kind => [1]], (0, 5)), SequentialCPM())
        step!(ic); step!(ic)
        @test ic[:n] == 2
        ic[:n] = 10
        step!(ic)
        @test ic[:n] == 11
    end
end


@testitem "computed parameters: read-only, derived from their inputs" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "computed parameters: read-only, derived from their inputs" begin
        σ = zeros(Int32, 6, 6)
        σ[2:3, 2:3] .= 1
        prob = PottsProblem(ParamDiamond(; name = :pd), Any[ownership => σ, kind => [:A]], (0, 1))
        vals(q) = map(n -> getp(q, n)(q), (p₁ = :p₁, p₂ = :p₂, p₃ = :p₃, p₄ = :p₄, p₅ = :p₅, λ = :λ))
        @test vals(prob) == (p₁ = 1.0, p₂ = 2.0, p₃ = 3.0, p₄ = 5.0, p₅ = 15.0, λ = 1.0)
        @test vals(remake(prob; p = [:p₁ => 2.0])) == (p₁ = 2.0, p₂ = 4.0, p₃ = 3.0, p₄ = 7.0, p₅ = 15.0, λ = 1.0)
        @test vals(remake(prob; p = [:p₃ => 1.0])) == (p₁ = 1.0, p₂ = 2.0, p₃ = 1.0, p₄ = 3.0, p₅ = 5.0, λ = 1.0)
        # a write of a computed parameter names it, its expression and its base inputs; a list
        # naming one is refused whole
        function err(f)
            return try
                f(); ""
            catch e
                e isa ArgumentError || rethrow()
                sprint(showerror, e)
            end
        end
        e = err(() -> remake(prob; p = [:p₄ => 0.0, :p₁ => 3.0]))
        @test !isempty(e)
        @test !isempty(
            err(
                () -> PottsProblem(
                    ParamDiamond(; name = :pd),
                    Any[ownership => σ, kind => [:A], :p₂ => 1.0], (0, 1)
                )
            )
        )
        integ = init(prob, SequentialCPM())
        integ.ps[:p₃] = 2.0
        @test (integ.ps[:p₂], integ.ps[:p₄], integ.ps[:p₅]) == (2.0, 4.0, 10.0)
        for write in (
                () -> (integ.ps[:p₂] = 9.0), () -> setp(integ, :p₅)(integ, 1.0), () -> setp(integ, [:p₁, :p₄])(integ, [2.0, 0.0]),
                () -> Potts.SymbolicIndexingInterface.setsym(integ, [:p₁, :p₄])(integ, [2.0, 0.0]),
                () -> Potts.SymbolicIndexingInterface.remake_buffer(prob, prob.p, [:p₅], [1.0]),
            )
            @test !isempty(err(write))
            @test (integ.ps[:p₁], integ.ps[:p₂], integ.ps[:p₄]) == (1.0, 2.0, 4.0)     # nothing set
        end
        @test !Potts.SymbolicIndexingInterface.is_parameter(integ, :p₄) && Potts.SymbolicIndexingInterface.is_observed(integ, :p₄)
        # the fixed-value route: a constructor keyword makes `p₄` a base parameter (a new type)
        fixed = PottsProblem(ParamDiamond(; name = :pd, p₄ = 9.0), Any[ownership => σ, kind => [:A]], (0, 1))
        @test getp(fixed, :p₄)(fixed) == 9.0 && typeof(fixed.p) !== typeof(prob.p)
        @test getp(remake(fixed; p = [:p₄ => 4.0]), :p₄)(remake(fixed; p = [:p₄ => 4.0])) == 4.0
        @test Potts.SymbolicIndexingInterface.is_parameter(init(fixed, SequentialCPM()), :p₄)
        @test vals(prob) == (p₁ = 1.0, p₂ = 2.0, p₃ = 3.0, p₄ = 5.0, p₅ = 15.0, λ = 1.0)   # source unchanged
    end
end

# `setp` with several names is one change, whatever the order of the names and whatever it
# was built on (integrator, problem, function, model description); `integ.ps[[x, y]] = v` too.


@testitem "setp with several parameters is one change" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "setp with several parameters is one change" begin
        σ = zeros(Int32, 6, 6)
        σ[2:3, 2:3] .= 1
        prob = PottsProblem(ParamDiamond(; name = :pd), Any[ownership => σ, kind => [:A]], (0, 1))
        fresh() = init(prob, SequentialCPM())
        state(i) = (i.ps[:p₁], i.ps[:p₂], i.ps[:p₃], i.ps[:p₄], i.ps[:p₅])
        for build in (identity, _ -> prob, _ -> prob.f, _ -> prob.f.sys)
            i = fresh()
            setp(build(i), [:p₃, :p₁])(i, [0.0, 3.0])
            @test state(i) == (3.0, 6.0, 0.0, 6.0, 0.0)
            i = fresh()
            setp(build(i), (:p₁, :p₃))(i, (3.0, 0.0))
            @test state(i) == (3.0, 6.0, 0.0, 6.0, 0.0)
        end
        i = fresh()
        i.ps[[:p₃, :p₁]] = [0.0, 3.0]
        @test state(i) == (3.0, 6.0, 0.0, 6.0, 0.0)
        # all or nothing: a bad value leaves the parameters unchanged
        i = fresh()
        @test_throws ArgumentError setp(i, [:p₁, :nope])
        @test_throws DimensionMismatch setp(i, [:p₁, :p₃])(i, [3.0])
        @test state(i) == (1.0, 2.0, 3.0, 5.0, 15.0)
    end
end


@testitem "div and ÷ in energies; variable defaults with functions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "div and ÷ in energies; variable defaults with functions" begin
        @potts_model DivEnergy begin
            @kinds medium A
            @parameters begin
                n = 7.0
                λ = 1.0
            end
            @variables begin
                goal(cell) = sqrt(n + 2)
            end
            @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
            @energy begin
                cells(A) => λ * (volume - n ÷ 2 - goal)^2 + div(volume, 4)
            end
            @sweep Metropolis(; temperature = 10.0)
        end

        σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[8:9, 8:9] .= 2
        prob = PottsProblem(DivEnergy(; name = :x), [ownership => σ, kind => [:A, :A]], (0, 20); seed = 3)
        @test prob.u0.cell.goal[1:2] == [3.0, 3.0]                       # sqrt(7 + 2)
        oracle(V, n) = sum((v - div(n, 2) - 3)^2 + div(v, 4) for v in V if v > 0)
        @test total_energy(prob) == oracle([9, 4], 7.0)                     # 9 + 2 + 4 + 1
        @test total_energy(remake(prob; p = [:n => 4.0])) == oracle([9, 4], 4.0)
        worst = 0.0
        for (u, prop) in proposal_states(prob; mcs = (0, 5), n = 300)
            a = deepcopy(u); a.ownership[prop.target] = prop.new
            prob.f.commit!(a, prob.p, prop, ctx_of(prob))
            worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
        end
        @test worst < 1.0e-9
        sol = solve(prob, SequentialCPM())
        @test total_energy(prob, sol.u[end]) ≈ oracle(sol.u[end].cell.volume[1:2], 7.0)
        # on numbers: Julia's `div` (integers stay integers; floats in their own type)
        @test Potts._intdiv(7, 2) === 3 && Potts._intdiv(Int32(7), 2) === 3 && Potts._intdiv(7.0, 2) === 3.0
        @test Potts._intdiv(7.5f0, 2.0f0) === 3.0f0 && Potts._intdiv(-7.5f0, 2) === -3.0f0
        # equal to Base where the quotient is exact in Float32 (|a / b| < 2^24)
        xs = Float32[0.3, -7.5, 1.0f5, 12.0, 5.0f-3, 9.0, -9.5]
        @test all(((a, b),) -> Potts._intdiv(a, b) === div(a, b), Iterators.product(xs, Float32[0.1, 2, -3, 1.5]))
        # zero derivative (piecewise constant)
        a, b = Potts.Symbolics.@variables a b
        @test isequal(Potts.Symbolics.derivative(Potts._intdiv(a, b), a), 0)
    end
end


@testitem "a model may not define its own `div` or `÷`" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "a model may not define its own `div` or `÷`" begin
        for def in (
                :(div(a, b) = a), :(
                    function ÷(a::T, b) where {T}
                        a
                    end
                ), :(div = max),
            )
            err = try
                macroexpand(
                    @__MODULE__, :(
                        @potts_model LocalDiv begin
                            $def
                            @kinds medium A
                        end
                    )
                )
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
        end
        # a field named `div` in a named tuple is not a definition
        @test Potts._div_definition(:(f(x) = (div = x ÷ 2,))) === nothing
    end
end

@testitem "symbolic-only helpers throw ArgumentError; compile refusals throw PottsCompileError" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "symbolic-only helpers and PottsCompileError" begin
        @test_throws ArgumentError Potts.gather(:n, :a, :b, :c)
        @test_throws ArgumentError Potts.population(:n, :b, :c)
        @test_throws ArgumentError Potts.cell_centroid(1)
        @test_throws ArgumentError Potts.copy_displacement(1, 1)
        @test_throws ArgumentError Potts.random_normal(1)
        @test_throws ArgumentError Potts.random_normal_above(1, 0.0, 1.0, 0.0)
        @test_throws ArgumentError Potts.count_contacts(:n, :a, :b)

        err = Potts.PottsCompileError("cannot lower expression")
        @test err isa Exception
        @test occursin("cannot lower expression", sprint(showerror, err))
    end
end
