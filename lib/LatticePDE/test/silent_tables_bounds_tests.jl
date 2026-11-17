# Split from silent_tests.jl (Wave T3b); uses LP_silent setup.

@testitem "an input's names never shadow another name (F1 round 3)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "an input's names never shadow another name (F1 round 3)" begin
        # round 2: silently misrouted (an input named `c` took `ig[:c] = …`, `kp` read the input
        # array, the last of two inputs with one name won)
        @variables ka(..)::Int32 [input = true, lattice_input_name = "c"] kb(..)::Int32 [input = true, lattice_input_name = "kp"]
        @variables kb2(..)::Int32 [input = true, lattice_input_name = "kp"]
        @parameters kp = 1.0
        on(k) = ifelse(k(t, x, y) == 1, 1.0, 0.0)
        err = emsg(() -> sown(ssys([D(ce) ~ on(ka)], [c(0, x, y) ~ 0.0], [ce, ka(t, x, y)], Num[]); inputs = [ka => 0]))
        @test occursin("also a field", err) && occursin("`c`", err)
        err = emsg(() -> sown(ssys([D(ce) ~ -kp * ce + on(kb)], [c(0, x, y) ~ 0.0], [ce, kb(t, x, y)], [kp]); inputs = [kb => 0]))
        @test occursin("also a parameter", err) && occursin("`kp`", err)
        err = emsg(
            () -> sown(
                ssys([D(ce) ~ on(kb) + on(kb2)], [c(0, x, y) ~ 0.0], [ce, kb(t, x, y), kb2(t, x, y)], Num[]);
                inputs = [kb => 0, kb2 => 0]
            )
        )
        @test occursin("two input fields", err) && occursin("kb", err) && occursin("kb2", err)
        # control: a name of its own is taken (`inputs = [:cc => …]`), and both unset are routed
        @variables kd2(..)::Int32 [input = true, lattice_input_name = "cc"]
        sk = ssys([D(ce) ~ on(kd2) + on(kq)], [c(0, x, y) ~ 0.0], [ce, kd2(t, x, y), qe], Num[])
        @test sown(sk; inputs = [:cc => 1, kq => 1]).inputs == sown(sk; inputs = [kd2 => 1, kq => 1]).inputs
        err = emsg(() -> solve(sown(sk), ExplicitEuler(); dt = 0.1))
        @test occursin(":cc => values", err) && occursin(":kq => values", err)       # (round 2: a route for the first only)
    end
end

@testitem "a table on the ODE path is the table (F1 round 3)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "a table on the ODE path is the table (F1 round 3)" begin
        # round 2 (both front ends): the ODE right side bound the table to the state: at u0 it was
        # −1 where −2, and Tsit5 gave c(1) = 0.5000 where exp(−2) = 0.1353
        @parameters Dq[1:2] = [1.0, 2.0]
        sys = ssys([D(ce) ~ -Dq[2] * ce], [c(0, x, y) ~ 1.0], [ce], [Dq])
        o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64))
        du = similar(o.u0)
        o.f(du, o.u0, o.p, 0.0)
        @test all(≈(-2.0), du)
        @test SciMLBase.solve(o, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10).u[end][1] ≈ exp(-2) rtol = 1.0e-6
        # the owned path (right before too), and a new table through remake (round 2: "`Dq[1:2]`
        # is not a parameter of the problem")
        p = sown(sys)
        alg = ExplicitEuler(; substeps = 1)
        @test solve(p, alg; dt = 0.01)[:c, end][1] ≈ 0.98^100
        @test solve(remake(p; p = [Dq => [1.0, 5.0]]), alg; dt = 0.01)[:c, end][1] ≈ 0.95^100
        @test p.tables == ["Dq" => [1.0, 2.0]]                       # the source is unchanged
        @test occursin("has 2 entries", emsg(() -> remake(p; p = [Dq => [1.0]])))
        # a remake gives the ODE problem a new table (F4-00; round 2: a silent no-op; base 3ed05c3b:
        # refused, "is a table"); an owned problem's `setp` names the table and its route
        @test SciMLBase.solve(remake(o; p = [Dq => [1.0, 5.0]]), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10).u[end][1] ≈ exp(-5) rtol = 1.0e-6
        ig = init(p, alg; dt = 0.01)
        @test occursin("table", emsg(() -> setp(p, Dq)(p, [1.0, 5.0])))
        # an integrator's table is set through `setp` (and `integ.ps`, F2-13)
        setp(ig, Dq)(ig, [1.0, 5.0])
        @test ig.ps[Dq] == [1.0, 5.0]
        # a typo is named on the ODE path too (round 2: ignored)
        err = emsg(() -> remake(o; p = [:typo => 3.0]))
        @test occursin("`typo` is not a parameter", err)
    end
end

@testitem "parameter keys, tables and input lists (F1 round 4)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "parameter keys, tables and input lists (F1 round 4)" begin
        @parameters Dq[1:2] = [1.0, 2.0] kr = 0.5
        sys = ssys([D(ce) ~ -Dq[2] * ce - kr * ce + ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 1.0], [ce, qe], [Dq, kr])
        p = sown(sys; inputs = [qe => 0])
        ix = p.index
        # an integer key is a slot of the parameter vector; an expression is no index (round 3:
        # both threw "is not a parameter of the problem", so `remake(p; p = [1 => …])` failed)
        @test SymbolicIndexingInterface.parameter_index(ix, 1) == 1
        @test occursin("out of range", emsg(() -> SymbolicIndexingInterface.parameter_index(ix, 9)))
        @test SymbolicIndexingInterface.parameter_index(ix, 2ce) === nothing
        @test remake(p; p = [1 => 0.25]).p == [0.25]
        @test occursin("`typo` is not a parameter", emsg(() -> remake(p; p = [:typo => 3.0])))   # names still refused
        # the table refusal names the table and the owned route (round 3: "`Dq[1]` is a table …
        # `remake(prob::FieldProblem; p = [Dq[1] => values])`", a route that fails)
        ig = init(p, ExplicitEuler(; substeps = 1); dt = 0.1)
        err = emsg(() -> setp(p, Dq)(p, [1.0, 5.0]))
        @test occursin("`Dq` is a table", err) && occursin("remake(prob; p = [Dq => values])", err) && !occursin("Dq[1]", err)
        # an entry as a key is refused, not a whole table set from one value (round 3: "the table
        # `Dq[2]` has 2 entries")
        err = emsg(() -> remake(p; p = [Dq[2] => 5.0]))
        @test occursin("entry 2 of the table `Dq`", err) && occursin("Dq => values", err)
        # tables read back (round 3: "`:Dq` names nothing of this problem"; getp "Invalid symbol")
        @test ig.ps[:Dq] == [1.0, 2.0] && ig.ps[Dq] == [1.0, 2.0] && ig.ps[Dq[2]] == 2.0
        @test getp(p, Dq)(p) == [1.0, 2.0] && getp(ig, Dq[1])(ig) == 1.0
        p5 = remake(p; p = [Dq => [1.0, 5.0]])
        @test getp(p5, Dq)(p5) == [1.0, 5.0] && getp(p, Dq)(p5) == [1.0, 5.0]
        @test getp(p, kr)(p) == 0.5                                   # a scalar parameter as before
        # a list with an input reads (round 3: "`kq` names nothing of this problem; its names: …, `kq`")
        l = ig[[ce, qe]]
        @test length(l) == 2 && l[1] == ones(4, 4) && l[2] == zeros(Int32, 4, 4)
        @test occursin("names nothing", emsg(() -> ig[[ce, :typo]]))
        # a Bool input holds 0/1 only (round 3: 2 was taken, read as true)
        dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
        err = emsg(() -> sown(dsys; domain = dm, inputs = [dm => fill(2, 4, 4)]))
        @test occursin("`dm` holds a Bool mask", err) && occursin("got 2", err)
        @test sown(dsys; domain = dm, inputs = [dm => fill(1, 4, 4)]).inputs == sown(dsys; domain = dm, inputs = [dm => trues(4, 4)]).inputs
        # the collision message names the variable and its name (round 3: "the input field `c` has the name `c`")
        @variables ka4(..)::Int32 [input = true, lattice_input_name = "c"]
        err = emsg(
            () -> sown(
                ssys([D(ce) ~ ifelse(ka4(t, x, y) == 1, 1.0, 0.0)], [c(0, x, y) ~ 0.0], [ce, ka4(t, x, y)], Num[]);
                inputs = [ka4 => 0]
            )
        )
        @test occursin("input field `ka4` has the name `c`", err) && occursin("also a field", err)
    end
end

@testitem "parameter keys, table lists and writes, input sites (F1 round 5)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "parameter keys, table lists and writes, input sites (F1 round 5)" begin
        @parameters Dq[1:2] = [1.0, 2.0] kr = 0.5
        sys = ssys([D(ce) ~ -Dq[2] * ce - kr * ce + ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 1.0], [ce, qe], [Dq, kr])
        alg = ExplicitEuler(; substeps = 1)
        # the ODE path refuses a key that is no parameter's name (round 4: `remake` skipped it
        # silently, the run kept kr = 0.5; `setp` gave "invalid index: nothing")
        o = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [qe => 0])
        for pm in ([kr + 1 => 1.0], [kr => 0.1, 2kr => 1.0], Dict(2kr => 1.0))
            err = emsg(() -> remake(o; p = pm))
            @test occursin("is not a parameter of the problem", err) && occursin("`kr`", err)
        end
        @test remake(o; p = [kr => 0.1]).p.values == [0.1]                  # control: a name is taken
        @test remake(o; p = Dict(kr => 0.2)).p.values == [0.2]
        err = emsg(() -> setp(o, 2kr))
        @test occursin("`2kr` is not a parameter", err) && !occursin("invalid index", err)
        p = sown(sys; inputs = [qe => 0])
        @test occursin("`2kr` is not a parameter", emsg(() -> remake(p; p = [2kr => 1.0])))
        # a Bool is no slot (round 4: `true` was taken as slot 1); one parameter is singular
        @test occursin("not a parameter", emsg(() -> SymbolicIndexingInterface.parameter_index(p.index, true)))
        @test occursin("not a parameter", emsg(() -> remake(p; p = [true => 0.3])))
        @test endswith(emsg(() -> SymbolicIndexingInterface.parameter_index(p.index, 9)), "has 1 parameter")
        # a list mixing tables and scalars reads (round 4: StackOverflowError)
        ig = init(p, alg; dt = 0.1)
        @test getp(p, [kr, Dq])(p) == [0.5, [1.0, 2.0]]
        @test getp(ig, (kr, Dq[1]))(ig) == (0.5, 1.0)
        @test occursin("`Dq`", emsg(() -> ig[:typo]))                # the names list the tables
        # an input value is named at its site (round 4: "at entry 7")
        K = zeros(4, 4); K[3, 2] = 2.5
        @test occursin("got 2.5 at site (3, 2)", emsg(() -> sown(sys; inputs = [qe => K])))
        # an integrator's table is written (round 4: "`Dq` names nothing of this problem"), and the
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

@testitem "table coefficients in the bound; problems built from ours (F1 round 6)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "table coefficients in the bound; problems built from ours (F1 round 6)" begin
        # round 5: the bound could not see `Dn[1] * Δ(c)`: Dn[1] = −1 ran (discretize, remake and
        # `ig[Dn] = …`), and `ig[Dn] = [1000, 2]` kept 1 substep (unstable, reported Success)
        @parameters Dn[1:2] = [1.0, 2.0] Dm[1:2] = [-1.0, 2.0]
        sys = ssys([D(ce) ~ Dn[1] * Δ(ce)], [c(0, x, y) ~ 1.0], [ce], [Dn])
        negsys = ssys([D(ce) ~ Dm[1] * Δ(ce)], [c(0, x, y) ~ 1.0], [ce], [Dm])
        alg = ExplicitEuler(; substeps = 1)
        neg(err) = occursin("is negative at these parameters", err)
        # ODE: at the first call of the right side (F4-01; base: at `discretize`)
        @test neg(emsg(() -> solve(discretize(negsys, LatticeDiscretization(Grid((4, 4)); T = Float64)), Tsit5())))
        @test neg(emsg(() -> solve(sown(negsys), alg; dt = 0.01)))                                            # owned: before a step
        p = sown(sys)
        @test neg(emsg(() -> solve(remake(p; p = [Dn => [-1.0, 2.0]]), alg; dt = 0.01)))
        ig = init(p, alg; dt = 0.01)
        @test neg(emsg(() -> (ig.ps[Dn] = [-1.0, 2.0]))) && ig.ps[Dn] == [1.0, 2.0]   # refused, nothing changed
        # the automatic count follows the table: ρ = Dn[1] · 4 Σ_d 1/h² = 128 Dn[1] (h = 1/4)
        n(D) = ceil(Int, 0.01 * 128 * D / 1.8)
        @test init(p, ExplicitEuler(); dt = 0.01).substeps == n(1.0) == 1
        @test init(remake(p; p = [Dn => [1000.0, 2.0]]), ExplicitEuler(); dt = 0.01).substeps == n(1000.0) == 712
        @test (ig.ps[Dn] = [1000.0, 2.0]; ig.substeps == 712)               # an explicit 1 is raised
        @test (ig.ps[Dn[1]] = 1.0; ig.substeps == 1)
        @test occursin("finite", emsg(() -> remake(p; p = [Dn => [NaN, 2.0]])))   # (round 5: taken)
        # writes: a Bool is no value, a tuple is a vector, `.=` names the table
        @test occursin("give one number", emsg(() -> (ig.ps[Dn[1]] = true)))
        @test (ig.ps[Dn] = (1.0, 3.0); ig.ps[Dn] == [1.0, 3.0])
        err = emsg(() -> (ig[Dn] .= 2.0))
        @test occursin("integ.ps[Dn] = values", err) && occursin("table", err) && !occursin("field", err)
        @test occursin("integ.ps[Dn] = values", emsg(() -> (ig.ps[Dn] .= 2.0)))
        # problems built from the ODE form refuse a key that names no parameter too (round 5: a
        # SteadyStateProblem and a NonlinearProblem of it kept the old value silently)
        @parameters k6 = 0.5
        o = discretize(ssys([D(ce) ~ -k6 * ce], [c(0, x, y) ~ 1.0], [ce], [k6]), LatticeDiscretization(Grid((4, 4)); T = Float64))
        ss = SciMLBase.SteadyStateProblem(o)
        nl = SciMLBase.NonlinearProblem(ss)
        for q in (ss, nl)
            @test occursin("`2k6` is not a parameter", emsg(() -> remake(q; p = [2k6 => 1.0])))
            @test remake(q; p = [k6 => 0.1]).p.values == [0.1]                    # control
        end
        # an untyped vector of pairs is a map (round 5: not checked)
        @test occursin("`2k6` is not a parameter", emsg(() -> remake(o; p = Any[k6 => 0.1, 2k6 => 1.0])))
        @test remake(o; p = Any[k6 => 0.1]).p.values == [0.1]
        # `setp` on an OrdinaryDiffEq integrator names it (round 5: "invalid index: nothing")
        oi = init(o, Tsit5())
        err = emsg(() -> setp(oi, 2k6))
        @test occursin("`2k6` is not a parameter", err) && !occursin("invalid index", err)
        setp(oi, k6)(oi, 0.2)
        @test oi.p.values == [0.2]
    end
end

@testitem "a table coefficient is bounded at every entry (F1 round 7)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "a table coefficient is bounded at every entry (F1 round 7)" begin
        # round 6: each read took only its smallest and largest entry, which under-bounds a
        # coefficient that is not affine in it: each run below was n = 1 and blew up with Success
        # (c(1) = 1.1e7, 1.2e24, 1.1e7); every site is kind 2 (entry 2), dt = 0.025. Index 0
        # reads 0 (round 8): `1 / at(Dv, …)` takes an index declared never 0 (`kb`, bounds (1, 3))
        @parameters Dq[1:3] = [0.0, 10.0, 20.0] Ds[1:3] = [0.0, π / 2, π] Dv[1:3] = [-1.0, 0.01, 1.0]
        K = fill(Int32(2), 4, 4)
        for (rate, tab, k, q) in (
                (-(at(Dq, qe) * (20 - at(Dq, qe))) * ce, Dq, 100.0, qe),   # values 0, 100, 0
                (-(200 * sin(at(Ds, qe))) * ce, Ds, 200.0, qe),             # 0, 200, ≈0
                (-(1 / at(Dv, qb)) * ce, Dv, 100.0, qb),
            )                     # 1, −100, −1
            sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, q], [tab])
            sol = solve(sown(sys; inputs = [q => K]), ExplicitEuler(); dt = 0.025)
            @test substep_counts(sol)[1] == ceil(Int, 0.025 * k / 1.8)
            @test SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 1.0e-20
        end
        # a zero entry under `1 / at(…)` that the inputs reach (a kind 1 at site (3, 2)) is not
        # finite: refused, naming the entry and saying to fix it (round 7: only "give an explicit
        # count"; F2 record (i): refused with or without a count). The entries the inputs do not
        # reach are not read (F2 record (h)): with kind 2 everywhere it runs
        @parameters Dz[1:3] = [0.0, 0.01, 1.0]
        K1 = copy(K); K1[3, 2] = 1
        sys = ssys([D(ce) ~ -(1 / at(Dz, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Dz])
        err = emsg(() -> solve(sown(sys; inputs = [qb => K1]), ExplicitEuler(); dt = 0.025))
        @test occursin("not finite where the inputs reach", err)
        @test occursin("`Dz[1]`", err) && occursin("make it nonzero", err) && !occursin("index 0", err)
        @test count("make it nonzero", err) == 1                      # (round 8: said twice)
        @test substep_counts(solve(sown(sys; inputs = [qb => K]), ExplicitEuler(); dt = 0.025))[1] == 2
        # … and with an index that is 0 at a site the message names both, with both routes
        # (49a986f1 named index 0 only and said "make the coefficient finite")
        sys = ssys([D(ce) ~ -(1 / at(Dz, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dz])
        K10 = copy(K1); K10[1, 1] = 0
        err = emsg(() -> solve(sown(sys; inputs = [qe => K10]), ExplicitEuler(); dt = 0.025))
        @test occursin("index 0", err) && occursin("`Dz[1]`", err) && occursin("make it nonzero", err) &&
            occursin("bounds = (1, n)", err) && occursin("index 0 reads 0", err)
        # a negative entry under `sqrt`: the route says so (round 8: "finite and nonzero")
        @parameters Dn9[1:3] = [-1.0, 1.0, 1.0]
        sys = ssys([D(ce) ~ -sqrt(at(Dn9, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Dn9])
        err = emsg(() -> solve(sown(sys; inputs = [qb => K1]), ExplicitEuler(); dt = 0.025))
        @test occursin("`Dn9[1]`", err) && occursin("≥ 0", err) && occursin("sqrt", err) && !occursin("nonzero", err)
    end
end

@testitem "a table read takes index 0 and clamped indices as the kernel does (F1 round 8)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "a table read takes index 0 and clamped indices as the kernel does (F1 round 8)" begin
        K5, K0 = fill(Int32(5), 4, 4), fill(Int32(0), 4, 4)
        # one index, tables of different lengths: the kernel clamps the index into each table's
        # own range, so at k = 5 `Db` reads 100 and `Da` its last entry 0 (round 7: the group took
        # the shortest table's entries: n = 1, Success, max|c(1)| = 1.1e7; f8f98e43: n = 2)
        @parameters Da[1:3] = [0.0, 0.0, 0.0] Db[1:5] = [0.0, 0.0, 0.0, 0.0, 100.0]
        sys = ssys([D(ce) ~ -(at(Db, qe) - at(Da, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Da, Db])
        sol = solve(sown(sys; inputs = [qe => K5]), ExplicitEuler(); dt = 0.025)
        @test substep_counts(sol)[1] == 2 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 1.0e-20
        # index 0 (an input value 0, or a literal 0) reads 0, so `100 − at(T3, k)` is 100 there
        # (round 7 and f8f98e43: index 0 was not evaluated; n = 1, Success, max|c(1)| = 1.1e7 where
        # the exact value is exp(−100) = 3.7e-44)
        @parameters T3[1:3] = [100.0, 100.0, 100.0]
        for (rate, ins) in ((-(100 - at(T3, qe)) * ce, [ce, qe]), (-(100 - at(T3, 0)) * ce, [ce]))
            sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], ins, [T3])
            sol = solve(sown(sys; inputs = length(ins) == 2 ? [qe => K0] : ()), ExplicitEuler(); dt = 0.025)
            @test substep_counts(sol)[1] == 2 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 1.0e-20
        end
        # the CPU `at` reads as the kernel does (round 7: `T[Int(k)]`, a BoundsError at 0)
        @test at([1.0, 2.0, 3.0], 0) == 0.0 && at([1.0, 2.0, 3.0], 5) == 3.0 && at([1.0, 2.0, 3.0], -1) == 1.0
        @test at([1.0, 2.0, 3.0], 2) == 2.0                                           # control
        # `1 / at(T, k)` with an index that is 0 at a site is not finite there: refused, saying so,
        # with the route (keep 0 out of the index); a count does not help (F2 record (i): 1fb097f2
        # ran a count). With no 0 in the map it takes an automatic count (F2 record (h))
        @parameters Dv8[1:3] = [-1.0, 0.01, 1.0]
        sys = ssys([D(ce) ~ -(1 / at(Dv8, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dv8])
        Kz = fill(Int32(2), 4, 4); Kz[3, 2] = 0
        for alg in (ExplicitEuler(), ExplicitEuler(; substeps = 2))
            err = emsg(() -> solve(sown(sys; inputs = [qe => Kz]), alg; dt = 0.025))
            @test occursin("index 0", err) && occursin("(3, 2)", err) && occursin("bounds = (1, n)", err)
        end
        sol = solve(sown(sys; inputs = [qe => fill(Int32(2), 4, 4)]), ExplicitEuler(); dt = 0.025)
        @test substep_counts(sol)[1] == 2 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 1.0e-20
        # a declared index range is checked: a 0 in a map declared (1, 3) is refused, naming the site
        sys = ssys([D(ce) ~ -(1 / at(Dv8, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Dv8])
        err = emsg(() -> sown(sys; inputs = [qb => Kz]))
        @test occursin("bounds (1, 3)", err) && occursin("(3, 2)", err)
        p8 = sown(sys; inputs = [qb => fill(Int32(2), 4, 4)])                          # control
        i8 = init(p8, ExplicitEuler(); dt = 0.025)
        @test occursin("bounds (1, 3)", emsg(() -> (i8[qb] = Kz)))
        @test (i8[qb] = fill(Int32(3), 4, 4); true)                                     # control
        # many index expressions: the evaluation count is a Float64 product (round 7: an Int
        # product, 16^16 == 0, passed the cap and the bound never finished). The index map holds
        # 0 … 15, so each read takes up to 16 entries
        @parameters T16[1:16] = collect(1.0:16.0)
        rate = -sum(at(T16, qe + i) for i in 1:16) * ce
        sys = ssys([D(ce) ~ rate], [c(0, x, y) ~ 1.0], [ce, qe], [T16]; T = 0.025)
        K015 = reshape(Int32.(0:15), 4, 4)
        err = emsg(() -> solve(sown(sys; inputs = [qe => K015]), ExplicitEuler(); dt = 0.025))
        @test occursin("4096", err) && occursin("substeps = n", err)
        @test first(substep_counts(solve(sown(sys; inputs = [qe => K015]), ExplicitEuler(; substeps = 2); dt = 0.025))) == 2
        # the interval of the index is over the current values: with 0 everywhere each read takes
        # one entry, under the cap (F2 record (m))
        @test first(substep_counts(solve(sown(sys; inputs = [qe => K0]), ExplicitEuler(); dt = 0.025))) == ceil(Int, 0.025 * 136 / 1.8)
    end
end

@testitem "an explicit count is raised by every term with a bound (F1 round 9)" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "an explicit count is raised by every term with a bound (F1 round 9)" begin
        # 1fb097f2: a coefficient with a non-finite value (index 0) or over the cap made the whole
        # bound NaN, and an explicit count stayed as given: each run below ended Success and blew up.
        # Since F2 record (i) a value that is not finite where the inputs reach is refused with or
        # without a count (the new bound-coverage testset); over the cap is the case left
        K = fill(Int32(2), 4, 4)
        K16 = reshape(Int32.(mod.(0:255, 16)), 16, 16)               # index values 0 … 15
        # P1: `1 / at(Dv, k)` at every entry 200 (1fb097f2: n = 2, Success, 1.2e14): raised to 3,
        # with no warning (no 0 in the map: the bound is finite, F2 record (h))
        @parameters Dv9[1:3] = fill(0.005, 3)
        sys = ssys([D(ce) ~ -(1 / at(Dv9, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dv9])
        sol = @test_logs solve(sown(sys; inputs = [qe => K]), ExplicitEuler(; substeps = 2); dt = 0.025)
        @test first(substep_counts(sol)) == 3 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 1.0e-20
        @test first(substep_counts(solve(sown(sys; inputs = [qe => K]), ExplicitEuler(); dt = 0.025))) == 3
        # P1x: diffusion of c on 16² needs 4; an unrelated field's term over the cap kept 2
        # (1fb097f2: 5.2e30)
        @parameters Dd9 = 0.125 Tw9[1:16] = zeros(16)
        sys = ssys(
            [D(ce) ~ Dd9 * Δ(ce), D(oe) ~ -sum(at(Tw9, qe + i) for i in 1:4) * oe],
            [c(0, x, y) ~ 1.0 + sin(1000x + 700y), o(0, x, y) ~ 1.0], [ce, oe, qe], [Dd9, Tw9]
        )
        sol = @test_logs (:warn, r"4096") match_mode = :any solve(
            sown(sys; n = 16, inputs = [qe => K16]),
            ExplicitEuler(; substeps = 2)
        ; dt = 0.025)
        @test first(substep_counts(sol)) == 4 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 3
        # P2: over the cap, the diffusion still raises the count (1fb097f2: n = 2, 5.2e30)
        @parameters Tz9[1:16] = zeros(16)
        sys = ssys([D(ce) ~ Dd9 * Δ(ce) - sum(at(Tz9, qe + i) for i in 1:4) * ce], [c(0, x, y) ~ 1.0 + sin(1000x + 700y)], [ce, qe], [Dd9, Tz9])
        sol = @test_logs (:warn, r"4096") match_mode = :any solve(
            sown(sys; n = 16, inputs = [qe => K16]),
            ExplicitEuler(; substeps = 2)
        ; dt = 0.025)
        @test first(substep_counts(sol)) == 4 && SciMLBase.successful_retcode(sol) && maximum(abs, sol[:c, end]) < 3
    end
end

@testitem "warnings once per term and cause; messages name every cause (F2 records (a), (b), (e))" setup = [LP_silent] tags = [:latticepde, :silent] begin
    @testset "warnings once per term and cause; messages name every cause (F2 records (a), (b), (e))" begin
        # (a) a sweep over the value of an entry the bound does not cover warned once per value
        # (bda31989: three here, and the set grew with every value). Since F2 record (i) such an
        # entry is refused at each value; a sweep past the cap (the cause left to warn) warns once:
        # the key is the program, the term and the cause, never a value
        K1 = fill(Int32(1), 4, 4)
        @parameters Ds2[1:3] = [-1.0, 1.0, 1.0]
        sys = ssys([D(ce) ~ -sqrt(at(Ds2, qb)) * ce], [c(0, x, y) ~ 1.0], [ce, qb], [Ds2])
        prob = sown(sys; inputs = [qb => K1])
        @test all(
            v -> occursin(
                "`Ds2[1]` ($v)", emsg(
                    () -> solve(
                        remake(prob; p = [Ds2 => [v, 1.0, 1.0]]),
                        ExplicitEuler(; substeps = 2)
                    ; dt = 0.025)
                )
            ), (-1.0, -2.0, -3.0)
        )
        @parameters Dd2 = 0.125 Tc2[1:16] = zeros(16)
        sys = ssys([D(ce) ~ Dd2 * Δ(ce) - sum(at(Tc2, qe + i) for i in 1:4) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dd2, Tc2])
        prob = sown(sys; inputs = [qe => reshape(Int32.(0:15), 4, 4)])
        logs, _ = Test.collect_test_logs() do
            for v in (0.125, 0.25, 0.5)
                solve(remake(prob; p = [Dd2 => v]), ExplicitEuler(; substeps = 2); dt = 0.025)
            end
        end
        @test count(l -> l.level == Base.CoreLogging.Warn && occursin("4096", string(l.message)), logs) == 1
        # (b) an unseen term and a coefficient with no finite bound in one rate: both are named
        # (bda31989: only the unseen term `-(c^3)`). A coefficient not finite where the inputs
        # reach is refused before (F2 record (i)); past the cap is the cause left here
        @parameters Tz2[1:16] = zeros(16)
        sys = ssys([D(ce) ~ -ce^3 - sum(at(Tz2, qe + i) for i in 1:4) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Tz2])
        err = emsg(() -> solve(sown(sys; inputs = [qe => reshape(Int32.(0:15), 4, 4)]), ExplicitEuler(); dt = 0.025))
        @test occursin("c^3", err) && occursin("4096", err) && occursin("Tz2", err)
        # (e) index 0 is an input value 0, not a "kind map" value (a LatticePDE input is any map)
        @parameters Dz3[1:3] = [1.0, 1.0, 1.0]
        sys = ssys([D(ce) ~ -(1 / at(Dz3, qe)) * ce], [c(0, x, y) ~ 1.0], [ce, qe], [Dz3])
        Ke0 = fill(Int32(2), 4, 4); Ke0[2, 2] = 0
        err = emsg(() -> solve(sown(sys; inputs = [qe => Ke0]), ExplicitEuler(); dt = 0.025))
        @test occursin("index 0 reads 0 (an input value 0", err) && !occursin("kind map", err)
    end
end
