# Inputs of a coupled PDESystem: face conditions other fields read, Bool inputs, kind and clock
# reads, domains and array solutions. Uses `cp_msg`, `cp_build_err`,
# `ArrayFieldsComponent` and `ce_op` of couple_testsetup.jl. Negative controls (the
# tests at the source of 11523b0b) fail.

@testitem "a face condition that another field's operator reads runs" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "a face condition that another field's operator reads runs" begin
        uw, un = input_u(InputFaceW), input_u(InputFaceN)
        @test maximum(abs, uw .- un) > 1.0e-3
        # the hand value (and the control: without the condition `u` stays 0)
        ee = ExplicitEuler(; substeps = 4)
        @test isapprox(input_u(InputFaceW; field_solver = ee), input_hand(); rtol = 1.0e-13) && iszero(input_u(InputFaceN; field_solver = ee))
    end
end

@testitem "a face condition that an aux field's operator reads runs" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "a face condition that an aux field's operator reads runs" begin
        # the aux kernel reads the ghosts the condition sets: the run equals the inlined one
        # (`D(u) ~ 0.5 * laplacian(c) - 0.1 * u`, InputFaceW) and the hand value, and differs from the run without
        # the condition
        ua, ui = input_u(InputAuxBcs), input_u(InputFaceW)
        @test ua == ui || (println("aux vs inlined maxdiff ", maximum(abs, ua .- ui)); false)
        @test isapprox(input_u(InputAuxBcs; field_solver = ExplicitEuler(; substeps = 4)), input_hand(); rtol = 1.0e-13)
        @test maximum(abs, ua .- input_u(InputAuxNo)) > 1.0e-3
    end
end

# --- an unbound input (m2) --------------------------------------------------------------------
@testitem "an unbound input leads with the binding route" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "an unbound input leads with the binding route" begin
        e = input_new(input_model(:(@fields c = Input.sec())))
        @test occursin("has the input `secreting(t, x, y)`, named `secreting`, which no binding fills", e) || (println(e); false)
        i, j = findfirst("@fields … (secreting => kind == cell)", e), findfirst("lattice_input_name", e)
        @test i !== nothing && j !== nothing && first(i) < first(j) || (println(e); false)
        @test occursin("`inputs = [secreting => Potts.is_kind(model, :cell)]` in `Potts.couple`", e) || (println(e); false)
    end
end

# --- membership mistakes (m5, m5b, m5c, m5d, m4b) ---------------------------------------------
@testitem "membership tests in bindings" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "membership tests in bindings" begin
        # `@fields`: `∈`/`in` is refused by syntax (m5b: the constant `false`; m5c: an interval)
        for (b, form) in (
                (:(secreting => kind ∈ Set([cell, other])), "ismember(kind, (cell, other))"),
                (:(secreting => kind ∈ (cell, other)), "ismember(kind, (cell, other))"),
                (:(secreting => in(kind, (cell, other))), "ismember(kind, (cell, other))"),
            )
            e = cp_build_err(input_model(:(@fields c = Input.sec() ($b))))
            @test occursin("tests membership with", e) && occursin("a binding writes a kind set as `$form`", e) || (println(e); false)
        end
        # the route builds and fills both kinds
        @test input_new(input_model(:(@fields c = Input.sec() (secreting => ismember(kind, (cell, other)))))) == "built"
        # `Potts.couple`: `Potts.kind ∈ (1, 2)` is an interval pairing
        host = InputHost(; name = :m)
        e = cp_msg(() -> Potts.couple(host, Input.sec(); inputs = [Input.secreting => Potts.kind ∈ (1, 2)]))
        @test occursin("is bound to `kind ∈ 1 .. 2`, which Symbolics builds as an interval pairing (a domain), not a membership test", e) &&
            occursin("Potts.is_kind(model, :cell, …)", e) || (println(e); false)
        # the constant `false`: both causes and the route
        for b in (Potts.kind == :cell, Potts.kind ∈ Set([1, 2]))
            e = cp_msg(() -> Potts.couple(host, Input.sec(); inputs = [Input.secreting => b]))
            @test occursin("bound to the constant `false`", e) && occursin("`Potts.kind == :cell`", e) &&
                occursin("`Potts.kind ∈ Set(…)`", e) && occursin("write `Potts.is_kind(model, :cell)`", e) || (println(e); false)
        end
        # m5: the key is a declared input that no equation reads (its `∈ Set(…)` term was deleted)
        e = input_new(input_model(:(@fields c = Input.inset() (Input.kin => kind))))
        @test occursin("`kin` is declared `[input = true]`, but no equation of the PDESystem `sec` reads it", e) &&
            occursin("`kin(t, x, y) ∈ Set(…)` is Julia's `false`, so its term is deleted", e) || (println(e); false)
        e = cp_msg(() -> Potts.couple(host, Input.inset(); inputs = [Input.kin => Potts.kind]))
        @test occursin("`kin` is declared `[input = true]`", e) || (println(e); false)
        # m5d: a listed input that nothing reads is a warning (it ran silently with max c = 0)
        Core.eval(@__MODULE__, input_model(:(@fields c = Input.insetlong())))
        @test_logs (:warn, r"the PDESystem `sec` lists the input `kinl`, which no equation or condition reads") match_mode = :any Base.invokelatest(() -> InputM(; name = :m))
    end
end

# --- a kind name that is not a kind (m1c) -----------------------------------------------------
@testitem "@fields checks a kind name in a binding" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "@fields checks a kind name in a binding" begin
        e = input_new(input_model(:(@fields c = Input.sec() (secreting => kind == cells)); kinds = :(@kinds medium cell)))
        @test occursin("@fields: the binding `kind == cells` compares the kind with `cells`, which is not a kind of the model (it is", e) &&
            occursin("; its kinds are `medium`, `cell`", e) || (println(e); false)
        e = input_new(input_model(:(@fields c = Input.sec() (secreting => kind == celll)); kinds = :(@kinds medium cell)))
        @test occursin("`celll`, which is not a kind of the model; its kinds are `medium`, `cell`", e) || (println(e); false)
        # a kind name and a kind number still bind
        @test input_new(input_model(:(@fields c = Input.sec() (secreting => kind == cell)))) == "built"
        @test input_new(input_model(:(@fields c = Input.sec() (secreting => 1 == kind)))) == "built"
    end
end

# --- a cell quantity read in a PDESystem (m4, m4c) --------------------------------------------
# At 11523b0b: "`kind(t)` and `c(t, x, y)` have different independent variables" (pdesystem), and
# "`time` is not available in a site term or site update" (the long form).
@testitem "a PDESystem that reads a cell quantity is refused with the input route" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "a PDESystem that reads a cell quantity is refused with the input route" begin
        for (q, n) in ((Potts.kind, "kind"), (Potts.B.volume, "volume"))
            e = cp_msg(() -> Input.cellread(q))
            @test occursin("pdesystem: the equations read `$n`, a quantity of the CPM; a PDESystem cannot read cell quantities", e) &&
                occursin("`@variables src(..)::Bool [input = true]`", e) && occursin("`@fields c = sys (src => kind == cell)`", e) ||
                (println(e); false)
        end
        e = input_new(input_model(:(@fields c = Input.kindlong())))
        @test occursin("@fields: the PDESystem `sec` reads `kind`, a quantity of the CPM; a PDESystem cannot read cell quantities", e) &&
            occursin("src => kind == cell", e) && occursin("Potts.is_kind(model, :cell)", e) || (println(e); false)
        e = cp_msg(() -> Potts.couple(InputHost(; name = :m), Input.kindlong()))
        @test occursin("Potts.couple: the PDESystem `sec` reads `kind`, a quantity of the CPM", e) || (println(e); false)
        # Potts' `time` and `mcs` (not `Base.time`): the route is the system's own time `t`
        for (q, n, route) in (
                (Potts.B.time, "time", "write its independent variable `t` (`Potts.t`)"),
                (Potts.B.mcs, "mcs", "write `step_index(t)` of its independent variable `t`"),
            )
            @test Potts.info(q).role === :builtin
            e = cp_msg(() -> Input.clockread(q))
            @test occursin("pdesystem: the equations read `$n`, the model's", e) && occursin(route, e) &&
                !occursin("cell quantities", e) || (println(e); false)
            e = input_new(input_model(:(@fields c = Input.clocklong(Potts.B.$(Symbol(n))))))
            @test occursin("@fields: the PDESystem `clk` reads `$n`, the model's", e) && occursin(route, e) &&
                !occursin("cell quantities", e) || (println(e); false)
        end
        # the routes couple
        @test input_new(input_model(:(@fields c = Input.timeroute()))) == "built"
        @test input_new(input_model(:(@fields c = Input.mcsroute()))) == "built"
        # m7: a long form whose parameter list is empty names the list and `pdesystem`
        e = input_new(input_model(:(@fields c = Input.nops())))
        @test occursin(
            "which is not one of its dependent variables, parameters or independent variables; list it " *
                "in the 6th argument of `PDESystem` (its parameters, empty here)", e
        ) && occursin("build the system with `pdesystem`", e) || (println(e); false)
    end
end

# --- a domain entry for another variable ---------------------------------------------------
@testitem "a domain entry for a variable that is not an independent variable" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "a domain entry for a variable that is not an independent variable" begin
        e = input_new(input_model(:(@fields c = Input.zdom())))
        @test occursin("gives the domain `zz ∈ 0.0 .. 1.0`, but `zz` is not one of its independent variables (t, x, y)", e) ||
            (println(e); false)
    end
end

# --- `sol[:u]` of an array field ------------------------------------------------------------
@testitem "sol[:u] of an array field names its components" setup = [CoupleSetup] tags = [:potts, :fields_couple_inputs] begin
    @testset "sol[:u] of an array field names its components" begin
        sol = solve(PottsProblem(ArrayFieldsComponent(; name = :m), ce_op((12, 10)), (0, 1); field_solver = BackwardEuler()), SequentialCPM())
        @test sol[:u_1][end] isa AbstractArray
        e = cp_msg(() -> sol[:u])
        @test occursin("`u` is a vector quantity of m: read its components (:u_1, :u_2)", e) || (println(e); false)
    end
end
