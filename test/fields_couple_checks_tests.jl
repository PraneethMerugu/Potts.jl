# Checks of the single field front end: refusals of the removed sections, round trips of the
# inputs, hex faces and axis derivatives. Uses `CoupleChecksSetup`. Negative controls: these
# tests fail at the source of 071a1cc7.

@testitem "the old @bcs and @boundary sections are refused with the route" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "the old @bcs and @boundary sections are refused with the route" begin
        e = chk_build_err(
            quote
            @potts_model ChkBcs begin
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
        e = chk_build_err(
            quote
            @potts_model ChkBoundary begin
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

@testitem "Potts.fields and Potts.field_inputs name the same inputs (round trip)" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "Potts.fields and Potts.field_inputs name the same inputs (round trip)" begin
        @test chk_names(ChkFine(; name = :m)) == ["kind", "vol"]
        @test chk_names(ChkScaled(; name = :m)) == ["volume[owner]"]
        @test chk_names(ChkCoarse(; name = :m)) == ["kind"]
        for fs in (ExplicitEuler(), BackwardEuler())
            for (m, f) in ((ChkFine(; name = :m), :c), (ChkScaled(; name = :m), :c), (ChkCoarse(; name = :m), :cc))
                err, integ = chk_round_trip(m, fs, f)
                @test Set(String.(keys(Potts.field_inputs(integ)))) == Set(chk_names(m))
                @test err <= chk_tol(fs) || (println("round trip $(nameof(m)) $fs: $err"); false)
                @test maximum(getproperty(current_state(integ).site, f)) > 0.01
            end
        end
        fi = Potts.field_inputs(PottsProblem(ChkFine(; name = :m), chk_op(), (0, 1)))
        σ = first(chk_op()).second
        @test fi[:kind] == Int32.(σ .!= 0) && eltype(fi[:kind]) === Int32
        @test fi[:vol] == [s == 0 ? 0.0 : 16.0 for s in σ]
        @test Potts.field_inputs(PottsProblem(ChkScaled(; name = :m), chk_op(), (0, 1)))[Symbol("volume[owner]")] == fi[:vol]
    end
end

@testitem "Δ of a bound input is refused in the model's words, with a route" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "Δ of a bound input is refused in the model's words, with a route" begin
        e = chk_build_err(
            quote
            @potts_model ChkLap begin
                @kinds medium A
                @lattice Lattice((8, 8); boundary = Closed())
                @energy cells(A) => (volume - 4.0)^2
                @fields c = Chk.lapin() (Chk.sec => kind == A)
                @sweep Metropolis(; temperature = 1.0)
            end
            Potts.mtkcompile(ChkLap(; name = :m))
            end, Potts.PottsCompileError
        )
        @test occursin("applies `laplacian` to `kind == A`, a CPM value", e) && occursin("an input of the PDESystem bound to `kind == A`", e) &&
              occursin("`@after_mcs v ~ kind == A`", e) && !occursin("kind__in", e) && !occursin("cannot lower", e) ||
            (println(e); false)
        @test occursin("\n  in the equation of `c` in the PDESystem `lapin`: `Differential(t)(c(t, x, y)) ~ ", e) &&
            occursin("laplacian(c(t, x, y))", e) && !occursin("@equations", e) && !occursin("c(t))", e) || (println(e); false)
        σ = zeros(Int32, 8, 8); σ[1:3, 3:5] .= 1
        integ = init(
            PottsProblem(
                ChkLapSite(; name = :m), [ownership => σ, kind => [:A]], (0, 4);
            field_solver = ExplicitEuler(; substeps = 1)), SequentialCPM())
        step!(integ); step!(integ)
        c2, v2 = copy(Array(current_state(integ).site.c)), copy(Array(current_state(integ).site.v))
        step!(integ)
        lap(a) = [sum(a[clamp(i + di, 1, 8), clamp(j + dj, 1, 8)] - a[i, j] for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                  for i in 1:8, j in 1:8]
        @test v2 == Float64.(σ .!= 0)
        @test maximum(abs, Array(current_state(integ).site.c) .- (c2 .+ 0.1 .* lap(c2) .+ 0.1 .* lap(v2))) <= 1.0e-14
        @test maximum(abs, Array(current_state(integ).site.c)) > 0.01
    end
end

@testitem "a site variable under Δ, x closed and y periodic" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "a site variable under Δ, x closed and y periodic" begin
        σ = zeros(Int32, 8, 8); σ[1:2, [8, 1, 2]] .= 1
        integ = init(PottsProblem(ChkLapMix(; name = :m), [ownership => σ, kind => [:A]], (0, 4);
            field_solver = ExplicitEuler(; substeps = 1)), SequentialCPM())
        step!(integ); step!(integ)
        c2, v2 = copy(Array(current_state(integ).site.c)), copy(Array(current_state(integ).site.v))
        step!(integ)
        lap(a) = [sum(a[clamp(i + di, 1, 8), mod1(j + dj, 8)] - a[i, j] for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                  for i in 1:8, j in 1:8]
        @test v2 == Float64.(σ .!= 0)
        @test maximum(abs, Array(current_state(integ).site.c) .- (c2 .+ 0.1 .* lap(c2) .+ 0.1 .* lap(v2))) <= 1.0e-14
        @test maximum(abs, Array(current_state(integ).site.c)) > 0.01
    end
end

@testitem "the equation a field refusal names" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "the equation a field refusal names" begin
        m = ChkOde(; name = :m)
        eq = Potts._field_equation_of(m, nothing)
        @test eq isa Potts.Symbolics.Equation && Potts.info(Potts._field_lhs(eq, m)[1]).name === :c
        @test Potts._field_equation_of(m, "c") === eq
    end
end

@testitem "hex faces (Dirichlet, Robin) equal LatticePDE's own HEX run; the hand rate" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "hex faces (Dirichlet, Robin) equal LatticePDE's own HEX run; the hand rate" begin
        op0 = [ownership => zeros(Int32, 8, 8), kind => Symbol[]]
        fs = ExplicitEuler(; substeps = 4)
        integ = init(PottsProblem(ChkHex(; name = :h), op0, (0, 3); field_solver = fs), SequentialCPM())
        prob = CHK_LP.discretize(Chk.faces_owned(), CHK_LP.LatticeDiscretization(CHK_LP.Grid((8, 8); geometry = CHK_LP.HEX); T = Float64))
        err = 0.0
        for _ in 1:3
            u0 = vec(Array(current_state(integ).site.c))
            step!(integ)
            o = CHK_LP.solve(CHK_LP.remake(prob; u0, tspan = (0.0, 1.0)), ExplicitEuler(; substeps = 4); dt = 1.0).u[end]
            err = max(err, maximum(abs, o .- vec(Array(current_state(integ).site.c))))
        end
        @test err == 0 || (println("hex faces: $err"); false)
        h = 2.0^-10
        one = CHK_LP.solve(CHK_LP.remake(prob; u0 = ones(64), tspan = (0.0, h)), ExplicitEuler(; substeps = 1); dt = h).u[end]
        hand = 0.3 * 2 / 3 * (2 * (-1 - 1)) - 0.2 + 0.05 * 0.5
        @test abs((one[1 + 3 * 8] - 1) / h - hand) <= 1e-12 || (println("hex rate: ", (one[1 + 3 * 8] - 1) / h, " vs ", hand); false)
    end
end

@testitem "Differential(x) of a PDESystem with the model's own `x`; a non-axis" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "Differential(x) of a PDESystem with the model's own `x`; a non-axis" begin
        op0 = [ownership => zeros(Int32, 8, 8), kind => Symbol[]]
        a = solve(PottsProblem(ChkX(; name = :m), op0, (0, 3)), SequentialCPM()).u[end].site.c
        b = solve(PottsProblem(ChkNoX(; name = :m), op0, (0, 3)), SequentialCPM()).u[end].site.c
        @test a == b && maximum(a) > 0.01
        e = chk_build_err(
            quote
            @potts_model ChkZ begin
                @kinds medium A
                @lattice Lattice((8, 8); boundary = Closed())
                @energy cells(A) => (volume - 4.0)^2
                @fields c = Chk.zflux()
                @sweep Metropolis(; temperature = 1.0)
            end
            Potts.mtkcompile(ChkZ(; name = :m))
            end
        )
        @test occursin("differentiates along `z`, which is not one of its independent variables", e) &&
              !occursin("declares its own", e) || (println(e); false)
    end
end

@testitem "B wording in refusals" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "B wording in refusals" begin
        e = chk_build_err(
            quote
                @potts_model ChkDriveLap begin
                    @kinds medium A
                    @lattice Lattice((20, 20); boundary = Closed())
                    @energy cells(A) => (volume - 16.0)^2
                    @fields c = Chk.plain()
                    @drive copy => -1.0 * (laplacian(c)[target] - laplacian(c)[source])
                    @sweep Metropolis(; temperature = 4.0)
                end
                Potts.mtkcompile(ChkDriveLap(; name = :m))
            end,
            Potts.PottsCompileError,
        )
        @test occursin("`laplacian(c)` is a field operator", e) && occursin("aux field `L(t, x, y) ~ laplacian(c(t, x, y))`", e) &&
              occursin("read `L[target]`", e) && !occursin("cannot index", e) || (println(e); false)
        σ = zeros(Int32, 20, 20); σ[8:11, 8:11] .= 1
        @test string(solve(PottsProblem(ChkAux(; name = :m), [ownership => σ, kind => [:A]], (0, 2)), SequentialCPM()).retcode) == "Success"
        for (a, w) in ((:(Chk.u(Chk.t, Chk.x, Chk.y)), "u(t, x, y)"), (:(Chk.u(Chk.t, 0, Chk.y)), "u(t, 0, y)"))
            e = chk_build_err(
                quote
                @potts_model ChkRobin begin
                    @kinds medium A
                    @lattice Lattice((20, 10); boundary = Closed())
                    @energy cells(A) => (volume - 9.0)^2
                    @fields Chk.robinu($a)
                    @sweep Metropolis(; temperature = 1.0)
                end
                Potts.mtkcompile(ChkRobin(; name = :m))
                end, Potts.PottsCompileError
            )
            @test occursin("Robin coefficient", e) && occursin("the PDESystem `fac`", e) || (println(e); false)
        end
        e = chk_build_err(
            quote
            @potts_model ChkNonlin begin
                @kinds medium A
                @lattice Lattice((20, 10); boundary = Closed())
                @energy cells(A) => (volume - 9.0)^2
                @fields Chk.nonlin()
                @sweep Metropolis(; temperature = 1.0)
            end
            PottsProblem(ChkNonlin(; name = :m), [ownership => zeros(Int32, 20, 10), kind => Symbol[]], (0, 1))
            end
        )
        @test occursin("`@variables c(..) = 0.5 [bounds = (0, 1)]` in its PDESystem", e) && !occursin("c(field)", e) || (println(e); false)
        e = chk_msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :site; bounds = (0, 1)))
        @test occursin("`@variables c(..) = 0.5 [bounds = (0, 1)]` in a PDESystem", e) && !occursin("q(field)", e) || (println(e); false)
        e = chk_msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_level = Coarse(2)))
        @test occursin("`@variables c(..) = 0.5 [lattice_level = Coarse(4)]` in a PDESystem", e) || (println(e); false)
        e = chk_build_err(
            quote
            @potts_model ChkScope begin
                @kinds medium A
                @variables q = 1.0
                @lattice Lattice((8, 8); boundary = Closed())
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        @test occursin("a field is a dependent variable of a PDESystem, `@variables c(..) = 0.5 [bounds = (0, 1)]`", e) &&
            !occursin("`c(field)`", e) || (println(e); false)
        q = Potts.Symbolics.variable(:q)
        @test Potts._describe(Potts._BcsLine(q ~ 1.0), [:medium, :A]) == "the condition `q ~ 1.0` of the fields' PDESystem"
    end
end

@testitem "Potts.field_inputs(integ, pdesys), the user's PDESystem and Potts.fields" setup = [CoupleChecksSetup] tags = [:potts, :fields_couple_checks] begin
    @testset "Potts.field_inputs(integ, pdesys), the user's PDESystem and Potts.fields" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            for (m, pde, f, op) in ((ChkFine(; name = :m), Chk.att(), :c, chk_op()), (ChkCoarse(; name = :m), Chk.coarse(), :cc, chk_op()))
                σ = first(op).second
                err, fi, integ = chk_pde_round_trip(m, pde, fs, f; op)
                @test err <= max(chk_tol(fs), 1.0e-14) || (println("user round trip $(nameof(pde)) $fs: $err"); false)
                @test fi[:sec] == (σ .!= 0) && eltype(fi[:sec]) === Bool
                @test Set(keys(fi)) == (f === :c ? Set([:sec, :vol]) : Set([:sec]))
                @test Potts.field_inputs(integ, Potts.fields(m)) == Potts.field_inputs(integ)
            end
        end
        σ = first(chk_op()).second
        fi = Potts.field_inputs(PottsProblem(ChkFine(; name = :m), chk_op(), (0, 1)), Chk.att())
        @test fi[:vol] == [s == 0 ? 0.0 : 16.0 for s in σ]
        odd = (σ = zeros(Int32, 24, 20); σ[2:6, 3:9] .= 1; σ[7:7, 10:10] .= 2; σ[9:14, 4:8] .= 3; σ[15:19, 13:18] .= 4;
               [ownership => σ, kind => [:A, :A, :A, :A]])
        meet = (σ = zeros(Int32, 24, 20); σ[3:8, 3:8] .= 1; σ[9:13, 3:8] .= 2; σ[4:9, 11:15] .= 3; [ownership => σ, kind => [:A, :A, :A]])
        for op in (chk_op(), odd, meet), fs in (ExplicitEuler(), BackwardEuler())
            err, fi, _ = chk_pde_round_trip(ChkCoarse(; name = :m), Chk.coarse(), fs, :cc; op)
            @test any(((I, J),) -> (b = fi[:sec][I:(I + 1), J:(J + 1)]; any(b) && !all(b)), Iterators.product(1:2:24, 1:2:20))
            @test err <= max(chk_tol(fs), 1.0e-14) || (println("partial blocks $fs: $err"); false)
        end
        for op in (chk_op(), odd, meet), fs in (ExplicitEuler(), BackwardEuler())
            integ = init(PottsProblem(ChkConserve(; name = :m), op, (0, 3); field_solver = fs, seed = 3), SequentialCPM())
            foreach(_ -> step!(integ), 1:3)
            tot = sum(Array(current_state(integ).site.cc)) * 4
            want = 3 * 0.5 * count(!=(0), first(op).second)
            @test isapprox(tot, want; rtol = fs isa ExplicitEuler ? 1e-14 : 1e-9) || (println("conservation $fs: $tot vs $want"); false)
        end
        F = Potts.fields(ChkFine(; name = :m))
        @test occursin("vol(t, x, y)", string(F.eqs)) && !occursin("field1__in", string(F.eqs)) || (println(F.eqs); false)
        @test chk_names(ChkFine(; name = :m)) == ["kind", "vol"]
        integ = init(PottsProblem(ChkFine(; name = :m), chk_op(), (0, 5); seed = 3), SequentialCPM())
        rep = sprint(
            field_report, CHK_LP.discretize(
                F, CHK_LP.LatticeDiscretization(CHK_LP.Grid((24, 20)); T = Float64);
            inputs = collect(Potts.field_inputs(integ))))
        @test occursin(r"inputs: [^\n]*\bvol\b", rep) && !occursin("field1__in", rep) || (println(rep); false)
        σ8 = zeros(Int32, 8, 8); σ8[1:3, 3:5] .= 1
        integ2 = init(PottsProblem(ChkLapSite(; name = :m), [ownership => σ8, kind => [:A]], (0, 4)), SequentialCPM())
        step!(integ2)
        @test Potts.field_inputs(integ2, Chk.lapsite())[:v] == Array(current_state(integ2).site.v)
        e = chk_msg(() -> Potts.field_inputs(integ, Chk.scaled()))
        @test occursin("the inputs of the PDESystem `scaled` (`w`)", e) && occursin("`att`", e) && occursin("`kind`, `vol`", e) ||
              (println(e); false)
        e = chk_msg(
            () -> CHK_LP.discretize(
                chk_owned(Chk.att()), CHK_LP.LatticeDiscretization(CHK_LP.Grid((24, 20)); T = Float64);
            inputs = collect(Potts.field_inputs(integ))))
        @test occursin("`kind` is not an input field of the problem", e) && occursin("Potts.field_inputs(integ, pdesys)", e) ||
              (println(e); false)
    end
end
