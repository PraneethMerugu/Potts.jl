# F4-B6 review fixes (the reviewers' programs ~/lpwork/rb6/p1.jl, p2.jl and
# ~/lpwork/f4/rev-b6u/progs*.jl). Uses `cp_msg`, `cp_build_err`, `cp_own`, `cp_tol` and `LP` of
# fields_couple.jl. Negative controls (these tests at the src of 071a1cc7):
# ~/lpwork/f4B6r/nc.log.

@testitem "F4-B6 review: the old @bcs and @boundary sections are refused with the route" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "F4-B6 review: the old @bcs and @boundary sections are refused with the route" begin
        e = cp_build_err(quote
            @potts_model B6Bcs begin
                @kinds medium cell
                @lattice Lattice((20, 20); boundary = Closed())
                @energy cells(cell) => (volume - 16.0)^2
                @bcs c(t, 0, y) ~ 1.0
                @sweep Metropolis(; temperature = 4.0)
            end
        end)
        @test occursin("`@bcs` is not a section of a model body", e) && occursin("second argument of its PDESystem", e) &&
              occursin("[c(t, 0, y) ~ v, Differential(x)(c(t, L, y)) ~ 0, c ~ masked(wall(t, x, y), 0.0)]", e) &&
              occursin("@fields c = pdesys (wall => kind == border)", e) && !occursin("UndefVarError", e) || (println(e); false)
        e = cp_build_err(quote
            @potts_model B6Boundary begin
                @kinds medium cell
                @lattice Lattice((20, 20); boundary = Closed())
                @energy cells(cell) => (volume - 16.0)^2
                if true
                    @boundary c begin
                        x => (Dirichlet(1.0), NoFlux())
                    end
                end
                @sweep Metropolis(; temperature = 4.0)
            end
        end)
        @test occursin("`@boundary` is not a section of a model body", e) && occursin("Dirichlet `c(t, 0, y) ~ v`", e) &&
              occursin("NoFlux `Differential(x)(c(t, 0, y)) ~ 0`", e) &&
              occursin("Robin `α * c(t, 0, y) - β * Differential(x)(c(t, 0, y)) ~ g`", e) &&
              occursin("`α * c(t, L, y) + β * Differential(x)(c(t, L, y)) ~ g`", e) || (println(e); false)
    end
end

@testitem "F4-B6 review: Potts.fields and Potts.field_inputs name the same inputs (round trip)" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "F4-B6 review: Potts.fields and Potts.field_inputs name the same inputs (round trip)" begin
        # the names: `kind` for the kind binding, the binding's name for a bare CPM read, the read as
        # the model writes it for a read inside arithmetic
        @test b6_names(B6Fine(; name = :m)) == ["kind", "vol"]
        @test b6_names(B6Scaled(; name = :m)) == ["volume[owner]"]
        @test b6_names(B6Coarse(; name = :m)) == ["kind"]
        for fs in (ExplicitEuler(), BackwardEuler())
            for (m, f) in ((B6Fine(; name = :m), :c), (B6Scaled(; name = :m), :c), (B6Coarse(; name = :m), :cc))
                err, integ = b6_round_trip(m, fs, f)
                @test Set(String.(keys(Potts.field_inputs(integ)))) == Set(b6_names(m))
                @test err <= cp_tol(fs) || (println("round trip $(nameof(m)) $fs: $err"); false)
                @test maximum(getproperty(integ.u.site, f)) > 0.01                        # (the source is on)
            end
        end
        # the values: the kind number of each site, the owner's volume
        fi = Potts.field_inputs(PottsProblem(B6Fine(; name = :m), b6_op(), (0, 1)))
        σ = first(b6_op()).second
        @test fi[:kind] == Int32.(σ .!= 0) && eltype(fi[:kind]) === Int32
        @test fi[:vol] == [s == 0 ? 0.0 : 16.0 for s in σ]
        @test Potts.field_inputs(PottsProblem(B6Scaled(; name = :m), b6_op(), (0, 1)))[Symbol("volume[owner]")] == fi[:vol]
    end
end

@testitem "F4-B6 review: Δ of a bound input is refused in the model's words, with a route" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "F4-B6 review: Δ of a bound input is refused in the model's words, with a route" begin
        e = cp_build_err(quote
            @potts_model B6Lap begin
                @kinds medium A
                @lattice Lattice((8, 8); boundary = Closed())
                @energy cells(A) => (volume - 4.0)^2
                @fields c = B6.lapin() (B6.sec => kind == A)
                @sweep Metropolis(; temperature = 1.0)
            end
            Potts.mtkcompile(B6Lap(; name = :m))
        end)
        @test occursin("applies `Δ` to `kind == A`, a CPM value", e) && occursin("an input of the PDESystem bound to `kind == A`", e) &&
              occursin("`@after_mcs v ~ kind == A`", e) && !occursin("kind__in", e) && !occursin("cannot lower", e) ||
              (println(e); false)
        # the location (batch-end review (d)): the equation of `c` in the PDESystem `lapin`, as written
        # (base ab34e226, ~/lpwork/f4BE/nc.log: `in @equations Differential(t, 1)(c(t)) ~ …`)
        @test occursin("\n  in the equation of `c` in the PDESystem `lapin`: `Differential(t)(c(t, x, y)) ~ ", e) &&
              occursin("Δ(c(t, x, y))", e) && !occursin("@equations", e) && !occursin("c(t))", e) || (println(e); false)
        # the route: the value in a site variable, read by the PDESystem as an unbound input. Its
        # closed faces have no flux (before, LatticeFields refused it: "field `v` has no boundary
        # rule"). Hand oracle with the cell on the low face of `x` and σ frozen: from MCS 2 on, `v` is
        # 1 on the cell, and one explicit substep per MCS gives c' = c + 0.1 Δc + 0.1 Δv with the
        # mirrored ghost (a neighbor past a closed face reads the site itself)
        @eval @potts_model B6LapSite begin
            @kinds medium A[frozen]
            @variables v(site) = 0.0
            @lattice Lattice((8, 8); boundary = Closed())
            @energy cells(A) => (volume - 4.0)^2
            @fields c = B6.lapsite()
            @after_mcs v ~ kind == A                                # (the form the message gives)
            @sweep Metropolis(; temperature = 1.0)
        end
        σ = zeros(Int32, 8, 8); σ[1:3, 3:5] .= 1
        integ = init(PottsProblem(Base.invokelatest(B6LapSite; name = :m), [ownership => σ, kind => [:A]], (0, 4);
            field_solver = ExplicitEuler(; substeps = 1)), SequentialCPM())
        step!(integ); step!(integ)
        c2, v2 = copy(Array(integ.u.site.c)), copy(Array(integ.u.site.v))
        step!(integ)
        lap(a) = [sum(a[clamp(i + di, 1, 8), clamp(j + dj, 1, 8)] - a[i, j] for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                  for i in 1:8, j in 1:8]
        @test v2 == Float64.(σ .!= 0)
        @test maximum(abs, Array(integ.u.site.c) .- (c2 .+ 0.1 .* lap(c2) .+ 0.1 .* lap(v2))) <= 1e-14
        @test maximum(abs, Array(integ.u.site.c)) > 0.01
    end
end

@testitem "batch-end review (a): a site variable under Δ, x closed and y periodic" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "batch-end review (a): a site variable under Δ, x closed and y periodic" begin
        σ = zeros(Int32, 8, 8); σ[1:2, [8, 1, 2]] .= 1
        integ = init(PottsProblem(B6LapMix(; name = :m), [ownership => σ, kind => [:A]], (0, 4);
            field_solver = ExplicitEuler(; substeps = 1)), SequentialCPM())
        step!(integ); step!(integ)
        c2, v2 = copy(Array(integ.u.site.c)), copy(Array(integ.u.site.v))
        step!(integ)
        lap(a) = [sum(a[clamp(i + di, 1, 8), mod1(j + dj, 8)] - a[i, j] for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                  for i in 1:8, j in 1:8]
        @test v2 == Float64.(σ .!= 0)
        @test maximum(abs, Array(integ.u.site.c) .- (c2 .+ 0.1 .* lap(c2) .+ 0.1 .* lap(v2))) <= 1e-14
        @test maximum(abs, Array(integ.u.site.c)) > 0.01
    end
end

@testitem "batch-end review (d): the equation a field refusal names" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "batch-end review (d): the equation a field refusal names" begin
        m = B6Ode(; name = :m)
        eq = Potts._field_equation_of(m, nothing)
        @test eq isa Potts.Symbolics.Equation && Potts.info(Potts._field_lhs(eq, m)[1]).name === :c
        @test Potts._field_equation_of(m, "c") === eq
    end
end

@testitem "F4-B6 review: hex faces (Dirichlet, Robin) equal LatticePDE's own HEX run; the hand rate" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "F4-B6 review: hex faces (Dirichlet, Robin) equal LatticePDE's own HEX run; the hand rate" begin
        op0 = [ownership => zeros(Int32, 8, 8), kind => Symbol[]]
        fs = ExplicitEuler(; substeps = 4)
        integ = init(PottsProblem(B6Hex(; name = :h), op0, (0, 3); field_solver = fs), SequentialCPM())
        prob = LP.discretize(B6.faces_owned(), LP.LatticeDiscretization(LP.Grid((8, 8); geometry = LP.HEX); T = Float64))
        err = 0.0
        for _ in 1:3
            u0 = vec(Array(integ.u.site.c))
            step!(integ)
            o = LP.solve(LP.remake(prob; u0, tspan = (0.0, 1.0)), ExplicitEuler(; dt = 1.0, substeps = 4)).u[end]
            err = max(err, maximum(abs, o .- vec(Array(integ.u.site.c))))
        end
        @test err == 0 || (println("hex faces: $err"); false)
        # the rate at site (1, 4) from c = 1: its two links across the low face of `x` read the
        # Dirichlet ghost 2·0 − 1 = −1 (the hex Laplacian's weight is 2D/(3h²)); site (1, 4) is off the
        # Robin face. One explicit step of h = 2⁻¹⁰ of LatticePDE's HEX run (which the coupled run equals)
        # gives c = 1 + h · rate (the rounding of 1 + h · rate bounds the error by 2⁻⁵³/h ≈ 1.1e-13)
        h = 2.0^-10
        one = LP.solve(LP.remake(prob; u0 = ones(64), tspan = (0.0, h)), ExplicitEuler(; dt = h, substeps = 1)).u[end]
        hand = 0.3 * 2 / 3 * (2 * (-1 - 1)) - 0.2 + 0.05 * 0.5
        @test abs((one[1 + 3 * 8] - 1) / h - hand) <= 1e-12 || (println("hex rate: ", (one[1 + 3 * 8] - 1) / h, " vs ", hand); false)
    end
end

@testitem "F4-B6 review: Differential(x) of a PDESystem with the model's own `x`; a non-axis" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "F4-B6 review: Differential(x) of a PDESystem with the model's own `x`; a non-axis" begin
        op0 = [ownership => zeros(Int32, 8, 8), kind => Symbol[]]
        a = solve(PottsProblem(B6X(; name = :m), op0, (0, 3)), SequentialCPM()).u[end].site.c
        b = solve(PottsProblem(B6NoX(; name = :m), op0, (0, 3)), SequentialCPM()).u[end].site.c
        @test a == b && maximum(a) > 0.01
        e = cp_build_err(quote
            @potts_model B6Z begin
                @kinds medium A
                @lattice Lattice((8, 8); boundary = Closed())
                @energy cells(A) => (volume - 4.0)^2
                @fields c = B6.zflux()
                @sweep Metropolis(; temperature = 1.0)
            end
            Potts.mtkcompile(B6Z(; name = :m))
        end)
        @test occursin("differentiates along `z`, which is not one of its independent variables", e) &&
              !occursin("declares its own", e) || (println(e); false)
    end
end

@testitem "F4-B6 review: B wording in refusals" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "F4-B6 review: B wording in refusals" begin
        # Δ in a model line: the route is an aux field of the PDESystem, read by the model
        e = try
            mod = Module(:B6Lines)
            Core.eval(mod, :(using Potts, Potts.Fields))
            Core.eval(mod, quote
                @potts_model B6DriveLap begin
                    @kinds medium A
                    @lattice Lattice((20, 20); boundary = Closed())
                    @energy cells(A) => (volume - 16.0)^2
                    @fields c = B6.plain()
                    @drive copy => -1.0 * (Δ(c)[target] - Δ(c)[source])
                    @sweep Metropolis(; temperature = 4.0)
                end
                Potts.mtkcompile(B6DriveLap(; name = :m))
            end)
            "built"
        catch err
            sprint(showerror, err)
        end
        @test occursin("`Δ(c)` is a field operator", e) && occursin("aux field `L(t, x, y) ~ Δ(c(t, x, y))`", e) &&
              occursin("read `L[target]`", e) && !occursin("cannot index", e) || (println(e); false)
        σ = zeros(Int32, 20, 20); σ[8:11, 8:11] .= 1
        @test string(solve(PottsProblem(B6Aux(; name = :m), [ownership => σ, kind => [:A]], (0, 2)), SequentialCPM()).retcode) == "Success"
        # a Robin coefficient that reads a field (at the site, or at a point): the time is `t`, the
        # field as the PDESystem writes it
        for (a, w) in ((:(B6.u(B6.t, B6.x, B6.y)), "u(t, x, y)"), (:(B6.u(B6.t, 0, B6.y)), "u(t, 0, y)"))
            e = cp_build_err(quote
                @potts_model B6Robin begin
                    @kinds medium A
                    @lattice Lattice((20, 10); boundary = Closed())
                    @energy cells(A) => (volume - 9.0)^2
                    @fields B6.robinu($a)
                    @sweep Metropolis(; temperature = 1.0)
                end
                Potts.mtkcompile(B6Robin(; name = :m))
            end)
            @test occursin("the PDESystem `fac`: the Robin coefficient `1 + $w` reads `$w`", e) &&
                  occursin("the coordinates `x`, `y`, `z` and the time `t`", e) && !occursin("`mcs`", e) || (println(e); false)
        end
        # the route of the stability bound: `bounds` in the PDESystem's declaration
        e = cp_build_err(quote
            @potts_model B6Nonlin begin
                @kinds medium A
                @lattice Lattice((20, 10); boundary = Closed())
                @energy cells(A) => (volume - 9.0)^2
                @fields B6.nonlin()
                @sweep Metropolis(; temperature = 1.0)
            end
            PottsProblem(B6Nonlin(; name = :m), [ownership => zeros(Int32, 20, 10), kind => Symbol[]], (0, 1))
        end)
        @test occursin("`@variables c(..) = 0.5 [bounds = (0, 1)]` in its PDESystem", e) && !occursin("c(field)", e) || (println(e); false)
        # `bounds` and `lattice_level` on a variable that is not a field; a variable without a scope
        e = cp_msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :site; bounds = (0, 1)))
        @test occursin("`@variables c(..) = 0.5 [bounds = (0, 1)]` in a PDESystem", e) && !occursin("q(field)", e) || (println(e); false)
        e = cp_msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_level = Coarse(2)))
        @test occursin("`@variables c(..) = 0.5 [lattice_level = Coarse(4)]` in a PDESystem", e) || (println(e); false)
        e = cp_build_err(quote
            @potts_model B6Scope begin
                @kinds medium A
                @variables q = 1.0
                @lattice Lattice((8, 8); boundary = Closed())
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        @test occursin("a field is a dependent variable of a PDESystem, `@variables c(..) = 0.5 [bounds = (0, 1)]`", e) &&
              !occursin("`c(field)`", e) || (println(e); false)
        # a condition with no recorded PDESystem is named as a condition of the fields' PDESystem
        q = Potts.Symbolics.variable(:q)
        @test Potts._describe(Potts._BcsLine(q ~ 1.0), [:medium, :A]) == "the condition `q ~ 1.0` of the fields' PDESystem"
    end
end

# (Coarse(2): a coarse row of the user's PDESystem reads the Bool input `sec` by its block mean,
# and the coupled model folds `kind == A` by the same rule (F4-15), so the two agree on blocks a
# cell covers in part: b6_op's second cell starts on odd rows, and the CPM moves both cells)
@testitem "batch-end review (b): Potts.field_inputs(integ, pdesys), the user's PDESystem and Potts.fields" setup = [CoupleSetup] tags = [:potts, :fields_couple_b6] begin
    @testset "batch-end review (b): Potts.field_inputs(integ, pdesys), the user's PDESystem and Potts.fields" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            for (m, pde, f, op) in ((B6Fine(; name = :m), B6.att(), :c, b6_op()), (B6Coarse(; name = :m), B6.coarse(), :cc, b6_op()))
                σ = first(op).second
                err, fi, integ = b6_pde_round_trip(m, pde, fs, f; op)
                @test err <= max(cp_tol(fs), 1e-14) || (println("user round trip $(nameof(pde)) $fs: $err"); false)
                @test fi[:sec] == (σ .!= 0) && eltype(fi[:sec]) === Bool
                @test Set(keys(fi)) == (f === :c ? Set([:sec, :vol]) : Set([:sec]))
                # `Potts.fields(m)`: its own inputs, as `field_inputs(integ)` gives them
                @test Potts.field_inputs(integ, Potts.fields(m)) == Potts.field_inputs(integ)
            end
        end
        σ = first(b6_op()).second
        fi = Potts.field_inputs(PottsProblem(B6Fine(; name = :m), b6_op(), (0, 1)), B6.att())
        @test fi[:vol] == [s == 0 ? 0.0 : 16.0 for s in σ]
        # F4-15: the coupled coarse field equals the user's PDESystem on blocks a cell covers in part
        # (base 5e972579, ~/lpwork/f4F15/nc.log: 0.25 apart there), for layouts that cover blocks in
        # part on purpose: odd offsets, a cell of one site, cells that meet inside a block
        odd = (σ = zeros(Int32, 24, 20); σ[2:6, 3:9] .= 1; σ[7:7, 10:10] .= 2; σ[9:14, 4:8] .= 3; σ[15:19, 13:18] .= 4;
               [ownership => σ, kind => [:A, :A, :A, :A]])
        meet = (σ = zeros(Int32, 24, 20); σ[3:8, 3:8] .= 1; σ[9:13, 3:8] .= 2; σ[4:9, 11:15] .= 3; [ownership => σ, kind => [:A, :A, :A]])
        for op in (b6_op(), odd, meet), fs in (ExplicitEuler(), BackwardEuler())
            err, fi, _ = b6_pde_round_trip(B6Coarse(; name = :m), B6.coarse(), fs, :cc; op)
            @test any(((I, J),) -> (b = fi[:sec][I:(I + 1), J:(J + 1)]; any(b) && !all(b)), Iterators.product(1:2:24, 1:2:20))
            @test err <= max(cp_tol(fs), 1e-14) || (println("partial blocks $fs: $err"); false)
        end
        # F4-15 conservation: the coupled coarse source over blocks a cell covers in part is the fine
        # total, `s` times the cells' sites per MCS (base 5e972579, ~/lpwork/f4F15/nc.log: the
        # owner's count of whole blocks, 4·(blocks owned by A))
        for op in (b6_op(), odd, meet), fs in (ExplicitEuler(), BackwardEuler())
            integ = init(PottsProblem(B6Conserve(; name = :m), op, (0, 3); field_solver = fs, seed = 3), SequentialCPM())
            foreach(_ -> step!(integ), 1:3)
            tot = sum(Array(integ.u.site.cc)) * 4
            want = 3 * 0.5 * count(!=(0), first(op).second)
            @test isapprox(tot, want; rtol = fs isa ExplicitEuler ? 1e-14 : 1e-9) || (println("conservation $fs: $tot vs $want"); false)
        end
        # S2: the bound read is the variable `vol` of `Potts.fields(m)`, in its equation and its report
        F = Potts.fields(B6Fine(; name = :m))
        @test occursin("vol(t, x, y)", string(F.eqs)) && !occursin("field1__in", string(F.eqs)) || (println(F.eqs); false)
        @test b6_names(B6Fine(; name = :m)) == ["kind", "vol"]
        integ = init(PottsProblem(B6Fine(; name = :m), b6_op(), (0, 5); seed = 3), SequentialCPM())
        rep = sprint(field_report, LP.discretize(F, LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float64);
            inputs = collect(Potts.field_inputs(integ))))
        @test occursin(r"inputs: [^\n]*\bvol\b", rep) && !occursin("field1__in", rep) || (println(rep); false)
        # an unbound input (a site variable) holds the model's array
        σ8 = zeros(Int32, 8, 8); σ8[1:3, 3:5] .= 1
        integ2 = init(PottsProblem(B6LapSite(; name = :m), [ownership => σ8, kind => [:A]], (0, 4)), SequentialCPM())
        step!(integ2)
        @test Potts.field_inputs(integ2, B6.lapsite())[:v] == Array(integ2.u.site.v)
        # a PDESystem the model did not couple is refused, naming both lists
        e = cp_msg(() -> Potts.field_inputs(integ, B6.scaled()))
        @test occursin("the inputs of the PDESystem `scaled` (`w`)", e) && occursin("`att`", e) && occursin("`kind`, `vol`", e) ||
              (println(e); false)
        # S3: the inputs of `Potts.fields` given to the user's PDESystem name the route
        e = cp_msg(() -> LP.discretize(b6_owned(B6.att()), LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float64);
            inputs = collect(Potts.field_inputs(integ))))
        @test occursin("`kind` is not an input field of the problem", e) && occursin("Potts.field_inputs(integ, pdesys)", e) ||
              (println(e); false)
    end
end
