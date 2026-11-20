# Split from silent_tests.jl; uses LP_silent setup.

@testitem "an input's names never shadow another name" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "an input's names never shadow another name" begin
        # Silently misrouted (an input named `c` took `ig[:c] = …`, `kp` read the input
        # array, the last of two inputs with one name won)
        @variables ka(..)::Int32 [input = true, lattice_input_name = "c"] kb(..)::Int32 [
            input = true, lattice_input_name = "kp",
        ]
        @variables kb2(..)::Int32 [input = true, lattice_input_name = "kp"]
        @parameters kp = 1.0
        on(k) = ifelse(k(t, x, y) == 1, 1.0, 0.0)
        @test_throws ArgumentError sown(
            ssys([D(ce) ~ on(ka)], [c(0, x, y) ~ 0.0], [ce, ka(t, x, y)], Num[]);
            inputs = [ka => 0]
        )
        @test_throws ArgumentError sown(
            ssys([D(ce) ~ -kp * ce + on(kb)], [c(0, x, y) ~ 0.0], [ce, kb(t, x, y)], [kp]);
            inputs = [kb => 0]
        )
        @test_throws ArgumentError sown(
            ssys(
                [D(ce) ~ on(kb) + on(kb2)], [c(0, x, y) ~ 0.0], [
                    ce, kb(t, x, y), kb2(t, x, y),
                ], Num[]
            );
            inputs = [kb => 0, kb2 => 0]
        )
        # control: a name of its own is taken (`inputs = [:cc => …]`), and both unset are
        # routed
        @variables kd2(..)::Int32 [input = true, lattice_input_name = "cc"]
        sk = ssys(
            [D(ce) ~ on(kd2) + on(kq)], [c(0, x, y) ~ 0.0], [ce, kd2(t, x, y), qe],
            Num[]
        )
        @test sown(sk; inputs = [:cc => 1, kq => 1]).inputs ==
            sown(sk; inputs = [kd2 => 1, kq => 1]).inputs
        @test_throws ArgumentError solve(sown(sk), ExplicitEuler(); dt = 0.1)
    end
end

@testitem "a table on the ODE path is the table" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "a table on the ODE path is the table" begin
        # Formerly (coupled and standalone routes) the ODE right side bound the table to the
        # state: at u0 it was −1 where −2, and Tsit5 gave c(1) = 0.5000 where exp(−2) =
        # 0.1353
        @parameters Dq[1:2] = [1.0, 2.0]
        sys = ssys([D(ce) ~ -Dq[2] * ce], [c(0, x, y) ~ 1.0], [ce], [Dq])
        o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
        du = similar(o.u0)
        o.f(du, o.u0, o.p, 0.0)
        @test all(≈(-2.0), du)
        @test SciMLBase.solve(o, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10).u[end][1] ≈
            exp(-2) rtol = 1.0e-6
        # the owned path (right before too), and a new table through remake ("`Dq[1:2]`
        # is not a parameter of the problem")
        p = sown(sys)
        alg = ExplicitEuler(; substeps = 1)
        @test solve(p, alg; dt = 0.01)[:c, end][1] ≈ 0.98^100
        @test solve(remake(p; p = [Dq => [1.0, 5.0]]), alg; dt = 0.01)[:c, end][1] ≈
            0.95^100
        # the source is unchanged
        @test p.tables == ["Dq" => [1.0, 2.0]]
        @test_throws ArgumentError remake(p; p = [Dq => [1.0]])
        # a remake gives the ODE problem a new table
        @test SciMLBase.solve(
            remake(o; p = [Dq => [1.0, 5.0]]), Tsit5();
            abstol = 1.0e-10, reltol = 1.0e-10
        ).u[end][1] ≈ exp(-5) rtol = 1.0e-6
        ig = init(p, alg; dt = 0.01)
        @test_throws ArgumentError setp(p, Dq)(p, [1.0, 5.0])
        # an integrator's table is set through `setp` (and `integ.ps`)
        setp(ig, Dq)(ig, [1.0, 5.0])
        @test ig.ps[Dq] == [1.0, 5.0]
        # a typo is refused on the ODE path too
        @test_throws ArgumentError remake(o; p = [:typo => 3.0])
    end
end

@testitem "parameter keys, tables and input lists" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "parameter keys, tables and input lists" begin
        @parameters Dq[1:2] = [1.0, 2.0] kr = 0.5
        sys = ssys(
            [D(ce) ~ -Dq[2] * ce - kr * ce + ifelse(qe == 1, 1.0, 0.0)],
            [c(0, x, y) ~ 1.0], [ce, qe], [Dq, kr]
        )
        p = sown(sys; inputs = [qe => 0])
        ix = p.index
        # an integer key is a slot of the parameter vector; an expression is no index
        # (both threw "is not a parameter of the problem", so `remake(p; p = [1 => …])`
        # failed)
        @test SymbolicIndexingInterface.parameter_index(ix, 1) == 1
        @test_throws ArgumentError SymbolicIndexingInterface.parameter_index(ix, 9)
        @test SymbolicIndexingInterface.parameter_index(ix, 2ce) === nothing
        @test remake(p; p = [1 => 0.25]).p == [0.25]
        @test_throws ArgumentError remake(p; p = [:typo => 3.0])   # names still refused
        ig = init(p, ExplicitEuler(; substeps = 1); dt = 0.1)
        @test_throws ArgumentError setp(p, Dq)(p, [1.0, 5.0])
        @test_throws ArgumentError remake(p; p = [Dq[2] => 5.0])
        # tables read back
        @test ig.ps[:Dq] == [1.0, 2.0] && ig.ps[Dq] == [1.0, 2.0] && ig.ps[Dq[2]] == 2.0
        @test getp(p, Dq)(p) == [1.0, 2.0] && getp(ig, Dq[1])(ig) == 1.0
        p5 = remake(p; p = [Dq => [1.0, 5.0]])
        @test getp(p5, Dq)(p5) == [1.0, 5.0] && getp(p, Dq)(p5) == [1.0, 5.0]
        # a scalar parameter as before
        @test getp(p, kr)(p) == 0.5
        l = ig[[ce, qe]]
        @test length(l) == 2 && l[1] == ones(4, 4) && l[2] == zeros(Int32, 4, 4)
        @test_throws ArgumentError ig[[ce, :typo]]
        # a Bool input holds 0/1 only
        dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
        @test_throws ArgumentError sown(dsys; domain = dm, inputs = [dm => fill(2, 4, 4)])
        @test sown(dsys; domain = dm, inputs = [dm => fill(1, 4, 4)]).inputs ==
            sown(dsys; domain = dm, inputs = [dm => trues(4, 4)]).inputs
        # name collision is refused
        @variables ka4(..)::Int32 [input = true, lattice_input_name = "c"]
        @test_throws ArgumentError sown(
            ssys(
                [D(ce) ~ ifelse(ka4(t, x, y) == 1, 1.0, 0.0)], [c(0, x, y) ~ 0.0], [
                    ce, ka4(t, x, y),
                ], Num[]
            );
            inputs = [ka4 => 0]
        )
    end
end

@testitem "parameter keys, table lists and writes, input sites" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "parameter keys, table lists and writes, input sites" begin
        @parameters Dq[1:2] = [1.0, 2.0] kr = 0.5
        sys = ssys(
            [D(ce) ~ -Dq[2] * ce - kr * ce + ifelse(qe == 1, 1.0, 0.0)],
            [c(0, x, y) ~ 1.0], [ce, qe], [Dq, kr]
        )
        alg = ExplicitEuler(; substeps = 1)
        # the ODE path refuses a key that is no parameter's name (`remake` skipped it
        # silently, the run kept kr = 0.5; `setp` gave "invalid index: nothing")
        o = discretize(
            sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [
                qe =>
                    0,
            ]
        )
        for pm in ([kr + 1 => 1.0], [kr => 0.1, 2kr => 1.0], Dict(2kr => 1.0))
            @test_throws ArgumentError remake(o; p = pm)
        end
        # control: a name is taken
        @test remake(o; p = [kr => 0.1]).p.values == [0.1]
        @test remake(o; p = Dict(kr => 0.2)).p.values == [0.2]
        @test_throws ArgumentError setp(o, 2kr)
        p = sown(sys; inputs = [qe => 0])
        @test_throws ArgumentError remake(p; p = [2kr => 1.0])
        # a Bool is no slot
        @test_throws ArgumentError SymbolicIndexingInterface.parameter_index(p.index, true)
        @test_throws ArgumentError remake(p; p = [true => 0.3])
        @test_throws ArgumentError SymbolicIndexingInterface.parameter_index(p.index, 9)
        # a list mixing tables and scalars reads
        ig = init(p, alg; dt = 0.1)
        @test getp(p, [kr, Dq])(p) == [0.5, [1.0, 2.0]]
        @test getp(ig, (kr, Dq[1]))(ig) == (0.5, 1.0)
        @test_throws ArgumentError ig[:typo]
        # an out-of-range input value is refused
        K = zeros(4, 4)
        K[3, 2] = 2.5
        @test_throws ArgumentError sown(sys; inputs = [qe => K])
        # an integrator's table is written ("`Dq` names nothing of this problem"), and the
        # step reads it: c(0.1) = 1 − 0.1 (Dq[2] + kr)
        ig.ps[Dq[2]] = 4.0
        @test ig.ps[:Dq] == [1.0, 4.0] && p.tables == ["Dq" => [1.0, 2.0]]
        step!(ig)
        @test all(≈(1 - 0.1 * 4.5), ig[ce])
        ig.ps[Dq] = [1.0, 0.0]
        step!(ig)
        @test all(≈((1 - 0.45) * (1 - 0.05)), ig[ce])
        @test occursin("has 2 entries", emsg(() -> (ig.ps[Dq] = [1.0])))
    end
end

@testitem "table coefficients in the bound; problems built from ours" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "table coefficients in the bound; problems built from ours" begin
        # The bound could not see `Dn[1] * laplacian(c)`: Dn[1] = −1 ran (discretize, remake
        # and `ig[Dn] = …`), and `ig[Dn] = [1000, 2]` kept 1 substep (unstable, reported
        # Success)
        @parameters Dn[1:2] = [1.0, 2.0] Dm[1:2] = [-1.0, 2.0]
        sys = ssys([D(ce) ~ Dn[1] * laplacian(ce)], [c(0, x, y) ~ 1.0], [ce], [Dn])
        negsys = ssys([D(ce) ~ Dm[1] * laplacian(ce)], [c(0, x, y) ~ 1.0], [ce], [Dm])
        alg = ExplicitEuler(; substeps = 1)
        neg(err) = occursin("is negative at these parameters", err)
        # ODE: at the first call of the right side (base: at `discretize`)
        @test_throws ArgumentError solve(
            discretize(negsys, LatticeDiscretization(Grid((4, 4)); T = Float64)), Tsit5()
        )
        # owned: before a step
        @test_throws ArgumentError solve(sown(negsys), alg; dt = 0.01)
        p = sown(sys)
        @test_throws ArgumentError solve(remake(p; p = [Dn => [-1.0, 2.0]]), alg; dt = 0.01)
        ig = init(p, alg; dt = 0.01)
        @test_throws ArgumentError (ig.ps[Dn] = [-1.0, 2.0])
        @test ig.ps[Dn] == [1.0, 2.0]   # refused, nothing changed
        # the automatic count follows the table: ρ = Dn[1] · 4 Σ_d 1/h² = 128 Dn[1] (h =
        # 1/4)
        n(D) = ceil(Int, 0.01 * 128 * D / 1.8)
        @test init(p, ExplicitEuler(); dt = 0.01).substeps == n(1.0) == 1
        @test init(
                remake(p; p = [Dn => [1000.0, 2.0]]), ExplicitEuler();
                dt = 0.01
            ).substeps ==
            n(1000.0) == 712
        # an explicit 1 is raised
        @test (ig.ps[Dn] = [1000.0, 2.0]; ig.substeps == 712)
        @test (ig.ps[Dn[1]] = 1.0; ig.substeps == 1)
        @test_throws ArgumentError remake(p; p = [Dn => [NaN, 2.0]])
        # writes: a Bool is no value, a tuple is a vector, `.=` refused
        @test_throws ArgumentError (ig.ps[Dn[1]] = true)
        @test (ig.ps[Dn] = (1.0, 3.0); ig.ps[Dn] == [1.0, 3.0])
        @test_throws ArgumentError (ig[Dn] .= 2.0)
        @test_throws ArgumentError (ig.ps[Dn] .= 2.0)
        # problems built from the ODE form refuse a key that names no parameter too
        @parameters k6 = 0.5
        o = discretize(
            ssys([D(ce) ~ -k6 * ce], [c(0, x, y) ~ 1.0], [ce], [k6]),
            LatticeDiscretization(Grid((4, 4)); T = Float64)
        )
        ss = SciMLBase.SteadyStateProblem(o)
        nl = SciMLBase.NonlinearProblem(ss)
        for q in (ss, nl)
            @test_throws ArgumentError remake(q; p = [2k6 => 1.0])
            @test remake(q; p = [k6 => 0.1]).p.values == [0.1]                    # control
        end
        # an untyped vector of pairs is a map
        @test_throws ArgumentError remake(o; p = Any[k6 => 0.1, 2k6 => 1.0])
        @test remake(o; p = Any[k6 => 0.1]).p.values == [0.1]
        # `setp` on an OrdinaryDiffEq integrator
        oi = init(o, Tsit5())
        @test_throws ArgumentError setp(oi, 2k6)
        setp(oi, k6)(oi, 0.2)
        @test oi.p.values == [0.2]
    end
end

@testitem "a table coefficient is bounded at every entry" setup = [LP_silent] tags = [
    :latticepde, :silent,
] begin
    @testset "a table coefficient is bounded at every entry" begin
        # Each read took only its smallest and largest entry, which under-bounds a
        # coefficient that is not affine in it: each run below was n = 1 and blew up with
        # Success (c(1) = 1.1e7, 1.2e24, 1.1e7); every site is kind 2 (entry 2), dt = 0.025.
        # Index 0 reads 0: `1 / value_at(Dv, …)` takes an index declared never 0 (`kb`,
        # bounds (1, 3))
        @parameters Dq[1:3] = [0.0, 10.0, 20.0] Ds[1:3] = [0.0, π / 2, π] Dv[1:3] = [
            -1.0, 0.01, 1.0,
        ]
        K = fill(Int32(2), 4, 4)
        for (rate, tab, k, q) in (
                # values 0, 100, 0
                (-(value_at(Dq, qe) * (20 - value_at(Dq, qe))) * ce, Dq, 100.0, qe),
                # 0, 200, ≈0
                (-(200 * sin(value_at(Ds, qe))) * ce, Ds, 200.0, qe),
                (-(1 / value_at(Dv, qb)) * ce, Dv, 100.0, qb),
            )                     # 1, −100, −1
            sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, q], [tab])
            sol = solve(sown(sys; inputs = [q => K]), ExplicitEuler(); dt = 0.025)
            @test substep_counts(sol)[1] == ceil(Int, 0.025 * k / 1.8)
            @test SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 1.0e-20
        end
        # a zero entry under `1 / value_at(…)` that the inputs reach (a kind 1 at site (3,
        # 2)) is not finite: refused, naming the entry and saying to fix it (only "give an
        # explicit count"; F2 record (i): refused with or without a count). The entries the
        # inputs do not reach are not read: with kind 2 everywhere it runs
        @parameters Dz[1:3] = [0.0, 0.01, 1.0]
        K1 = copy(K)
        K1[3, 2] = 1
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dz, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb],
            [Dz]
        )
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qb => K1]), ExplicitEuler();
            dt = 0.025
        )
        @test substep_counts(
            solve(sown(sys; inputs = [qb => K]), ExplicitEuler(); dt = 0.025)
        )[1] ==
            2
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dz, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [Dz]
        )
        K10 = copy(K1)
        K10[1, 1] = 0
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qe => K10]), ExplicitEuler();
            dt = 0.025
        )
        @parameters Dn9[1:3] = [-1.0, 1.0, 1.0]
        sys = ssys(
            [D(ce) ~ -sqrt(value_at(Dn9, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb],
            [Dn9]
        )
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qb => K1]), ExplicitEuler();
            dt = 0.025
        )
    end
end

@testitem "a table read takes index 0 and clamped indices as the kernel does" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "a table read takes index 0 and clamped indices as the kernel does" begin
        K5, K0 = fill(Int32(5), 4, 4), fill(Int32(0), 4, 4)
        # one index, tables of different lengths: the kernel clamps the index into each
        # table's own range, so at k = 5 `Db` reads 100 and `Da` its last entry 0 (the group
        # took the shortest table's entries: n = 1, Success, max|c(1)| = 1.1e7; f8f98e43: n
        # = 2)
        @parameters Da[1:3] = [0.0, 0.0, 0.0] Db[1:5] = [0.0, 0.0, 0.0, 0.0, 100.0]
        sys = ssys(
            [D(ce) ~ -(value_at(Db, qe) - value_at(Da, qe)) * ce],
            [c(0, x, y) ~ 1.0], [ce, qe], [Da, Db]
        )
        sol = solve(sown(sys; inputs = [qe => K5]), ExplicitEuler(); dt = 0.025)
        @test substep_counts(sol)[1] == 2 && SciMLBase.successful_retcode(sol) &&
            maximum(abs, sol[:c, end]) < 1.0e-20
        # index 0 (an input value 0, or a literal 0) reads 0, so `100 − value_at(T3, k)` is
        # 100 there (before the fix, f8f98e43: index 0 was not evaluated; n = 1, Success,
        # max|c(1)| = 1.1e7 where the exact value is exp(−100) = 3.7e-44)
        @parameters T3[1:3] = [100.0, 100.0, 100.0]
        for (rate, ins) in (
                (-(100 - value_at(T3, qe)) * ce, [ce, qe]), (
                    -(100 - value_at(T3, 0)) * ce, [ce],
                ),
            )
            sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], ins, [T3])
            sol = solve(
                sown(sys; inputs = length(ins) == 2 ? [qe => K0] : ()),
                ExplicitEuler(); dt = 0.025
            )
            @test substep_counts(sol)[1] == 2 && SciMLBase.successful_retcode(sol) &&
                maximum(abs, sol[:c, end]) < 1.0e-20
        end
        # the CPU `value_at` reads as the kernel does (`T[Int(k)]`, a BoundsError at 0)
        @test value_at([1.0, 2.0, 3.0], 0) == 0.0 && value_at([1.0, 2.0, 3.0], 5) == 3.0 &&
            value_at([1.0, 2.0, 3.0], -1) == 1.0
        # control
        @test value_at([1.0, 2.0, 3.0], 2) == 2.0
        # `1 / value_at(T, k)` with an index that is 0 at a site is not finite there:
        # refused, saying so, with the route (keep 0 out of the index); a count does not
        # help (1fb097f2 ran a count). With no 0 in the map it takes an automatic count
        @parameters Dv8[1:3] = [-1.0, 0.01, 1.0]
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dv8, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [Dv8]
        )
        Kz = fill(Int32(2), 4, 4)
        Kz[3, 2] = 0
        for alg in (ExplicitEuler(), ExplicitEuler(; substeps = 2))
            @test_throws ArgumentError solve(
                sown(sys; inputs = [qe => Kz]), alg;
                dt = 0.025
            )
        end
        sol = solve(
            sown(sys; inputs = [qe => fill(Int32(2), 4, 4)]), ExplicitEuler();
            dt = 0.025
        )
        @test substep_counts(sol)[1] == 2 && SciMLBase.successful_retcode(sol) &&
            maximum(abs, sol[:c, end]) < 1.0e-20
        # a declared index range is checked
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dv8, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb],
            [Dv8]
        )
        @test_throws ArgumentError sown(sys; inputs = [qb => Kz])
        # control
        p8 = sown(sys; inputs = [qb => fill(Int32(2), 4, 4)])
        i8 = init(p8, ExplicitEuler(); dt = 0.025)
        @test_throws ArgumentError (i8[qb] = Kz)
        # control
        @test (i8[qb] = fill(Int32(3), 4, 4); true)
        # many index expressions: the evaluation count is a Float64 product
        @parameters T16[1:16] = collect(1.0:16.0)
        rate = -sum(value_at(T16, qe + i) for i in 1:16) * ce
        sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, qe], [T16]; T = 0.025)
        K015 = reshape(Int32.(0:15), 4, 4)
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qe => K015]), ExplicitEuler();
            dt = 0.025
        )
        @test first(
            substep_counts(
                solve(
                    sown(sys; inputs = [qe => K015]),
                    ExplicitEuler(; substeps = 2); dt = 0.025
                )
            )
        ) == 2
        # the interval of the index is over the current values: with 0 everywhere each read
        # takes one entry, under the cap
        @test first(
            substep_counts(
                solve(sown(sys; inputs = [qe => K0]), ExplicitEuler(); dt = 0.025)
            )
        ) ==
            ceil(Int, 0.025 * 136 / 1.8)
    end
end

@testitem "an explicit count is raised by every term with a bound" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "an explicit count is raised by every term with a bound" begin
        # 1fb097f2: a coefficient with a non-finite value (index 0) or over the cap made the
        # whole bound NaN, and an explicit count stayed as given: each run below ended
        # Success and blew up. Since F2 record (i) a value that is not finite where the
        # inputs reach is refused with or without a count (the new bound-coverage testset);
        # over the cap is the case left
        K = fill(Int32(2), 4, 4)
        K16 = reshape(Int32.(mod.(0:255, 16)), 16, 16)               # index values 0 … 15
        # P1: `1 / value_at(Dv, k)` at every entry 200 (1fb097f2: n = 2, Success, 1.2e14):
        # raised to 3, with no warning (no 0 in the map: the bound is finite)
        @parameters Dv9[1:3] = fill(0.005, 3)
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dv9, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [Dv9]
        )
        sol = @test_logs solve(
            sown(sys; inputs = [qe => K]), ExplicitEuler(; substeps = 2);
            dt = 0.025
        )
        @test first(substep_counts(sol)) == 3 && SciMLBase.successful_retcode(sol) &&
            maximum(abs, sol[:c, end]) < 1.0e-20
        @test first(
            substep_counts(
                solve(sown(sys; inputs = [qe => K]), ExplicitEuler(); dt = 0.025)
            )
        ) ==
            3
        # P1x: diffusion of c on 16² needs 4; an unrelated field's term over the cap kept 2
        # (1fb097f2: 5.2e30)
        @parameters Dd9 = 0.125 Tw9[1:16] = zeros(16)
        sys = ssys(
            [
                D(ce) ~ Dd9 * laplacian(ce), D(oe) ~
                    -sum(value_at(Tw9, qe + i) for i in 1:4) * oe,
            ],
            [c(0, x, y) ~ 1.0 + sin(1000x + 700y), o(0, x, y) ~ 1.0], [ce, oe, qe], [
                Dd9, Tw9,
            ]
        )
        sol = @test_logs (:warn, r"4096") match_mode = :any solve(
            sown(sys; n = 16, inputs = [qe => K16]),
            ExplicitEuler(; substeps = 2)
            ; dt = 0.025
        )
        @test first(substep_counts(sol)) == 4 && SciMLBase.successful_retcode(sol) &&
            maximum(abs, sol[:c, end]) < 3
        # P2: over the cap, the diffusion still raises the count (1fb097f2: n = 2, 5.2e30)
        @parameters Tz9[1:16] = zeros(16)
        sys = ssys(
            [D(ce) ~ Dd9 * laplacian(ce) - sum(value_at(Tz9, qe + i) for i in 1:4) * ce],
            [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qe], [Dd9, Tz9]
        )
        sol = @test_logs (:warn, r"4096") match_mode = :any solve(
            sown(sys; n = 16, inputs = [qe => K16]),
            ExplicitEuler(; substeps = 2)
            ; dt = 0.025
        )
        @test first(substep_counts(sol)) == 4 && SciMLBase.successful_retcode(sol) &&
            maximum(abs, sol[:c, end]) < 3
    end
end

@testitem "warnings once per term and cause; messages name every cause" setup = [
    LP_silent,
] tags = [
    :latticepde, :silent,
] begin
    @testset "warnings once per term and cause; messages name every cause" begin
        # (a) a sweep over the value of an entry the bound does not cover warned once per
        #     value
        # (bda31989: three here, and the set grew with every value). Since F2 record (i)
        # such an entry is refused at each value; a sweep past the cap (the cause left to
        # warn) warns once: the key is the program, the term and the cause, never a value
        K1 = fill(Int32(1), 4, 4)
        @parameters Ds2[1:3] = [-1.0, 1.0, 1.0]
        sys = ssys(
            [D(ce) ~ -sqrt(value_at(Ds2, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb],
            [Ds2]
        )
        prob = sown(sys; inputs = [qb => K1])
        for v in (-1.0, -2.0, -3.0)
            @test_throws ArgumentError solve(
                remake(prob; p = [Ds2 => [v, 1.0, 1.0]]),
                ExplicitEuler(; substeps = 2); dt = 0.025
            )
        end
        @parameters Dd2 = 0.125 Tc2[1:16] = zeros(16)
        sys = ssys(
            [D(ce) ~ Dd2 * laplacian(ce) - sum(value_at(Tc2, qe + i) for i in 1:4) * ce],
            [c(0, x, y) ~ 1.0], [ce, qe], [Dd2, Tc2]
        )
        prob = sown(sys; inputs = [qe => reshape(Int32.(0:15), 4, 4)])
        logs, _ = Test.collect_test_logs() do
            for v in (0.125, 0.25, 0.5)
                solve(
                    remake(prob; p = [Dd2 => v]), ExplicitEuler(; substeps = 2);
                    dt = 0.025
                )
            end
        end
        @test count(
            l -> l.level == Base.CoreLogging.Warn &&
                occursin("4096", string(l.message)), logs
        ) == 1
        # (b) an unseen term and a coefficient with no finite bound in one rate: both are
        #     named
        # (bda31989: only the unseen term `-(c^3)`). A coefficient not finite where the
        # inputs reach is refused before; past the cap is the cause left here
        @parameters Tz2[1:16] = zeros(16)
        sys = ssys(
            [D(ce) ~ -ce^3 - sum(value_at(Tz2, qe + i) for i in 1:4) * ce],
            [c(0, x, y) ~ 1.0], [ce, qe], [Tz2]
        )
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qe => reshape(Int32.(0:15), 4, 4)]),
            ExplicitEuler(); dt = 0.025
        )
        @parameters Dz3[1:3] = [1.0, 1.0, 1.0]
        sys = ssys(
            [D(ce) ~ -(1 / value_at(Dz3, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe],
            [Dz3]
        )
        Ke0 = fill(Int32(2), 4, 4)
        Ke0[2, 2] = 0
        @test_throws ArgumentError solve(
            sown(sys; inputs = [qe => Ke0]), ExplicitEuler();
            dt = 0.025
        )
    end
end
