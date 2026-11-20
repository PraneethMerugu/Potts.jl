# F4 wave 2 review fixes (the reviewers' programs ~/lpwork/rev-w2-probes/p14.jl and
# ~/lpwork/rev-w2u-progs/m*.jl, p2_array.jl). Uses `cp_msg` and `cp_build_err` of
# fields_couple.jl and `CeFiCompB`, `ce_op` of fields_couple_e11.jl. Negative controls (the
# tests at the src of 11523b0b): ~/lpwork/f4W2r/nc.log (there F4-E16 was named E17 to E19, and
# F4-E17 was E16).

@testitem "F4-E14 review: a face condition that another field's operator reads runs" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E14 review: a face condition that another field's operator reads runs" begin
        uw, un = w2_u(W2FaceW), w2_u(W2FaceN)
        @test maximum(abs, uw .- un) > 1e-3
        # the hand value (and the control: without the condition `u` stays 0)
        ee = ExplicitEuler(; substeps = 4)
        @test isapprox(w2_u(W2FaceW; field_solver = ee), w2_hand(); rtol = 1e-13) && iszero(w2_u(W2FaceN; field_solver = ee))
    end
end

@testitem "F4-E14 review: a face condition that an aux field's operator reads runs" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E14 review: a face condition that an aux field's operator reads runs" begin
        # the aux kernel reads the ghosts the condition sets: the run equals the inlined one
        # (`D(u) ~ 0.5 * laplacian(c) - 0.1 * u`, W2FaceW) and the hand value, and differs from the run without
        # the condition
        ua, ui = w2_u(W2AuxBcs), w2_u(W2FaceW)
        @test ua == ui || (println("aux vs inlined maxdiff ", maximum(abs, ua .- ui)); false)
        @test isapprox(w2_u(W2AuxBcs; field_solver = ExplicitEuler(; substeps = 4)), w2_hand(); rtol = 1e-13)
        @test maximum(abs, ua .- w2_u(W2AuxNo)) > 1e-3
    end
end

# --- an unbound input (m2) --------------------------------------------------------------------
@testitem "F4-E16: an unbound input leads with the binding route" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E16: an unbound input leads with the binding route" begin
        e = w2_new(w2_model(:(@fields c = W2.sec())))
        @test occursin("has the input `secreting(t, x, y)`, named `secreting`, which no binding fills", e) || (println(e); false)
        i, j = findfirst("@fields … (secreting => kind == cell)", e), findfirst("lattice_input_name", e)
        @test i !== nothing && j !== nothing && first(i) < first(j) || (println(e); false)
        @test occursin("`inputs = [secreting => Potts.is_kind(model, :cell)]` in `Potts.couple`", e) || (println(e); false)
    end
end

# --- membership mistakes (m5, m5b, m5c, m5d, m4b) ---------------------------------------------
@testitem "F4-E16: membership tests in bindings" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E16: membership tests in bindings" begin
        # `@fields`: `∈`/`in` is refused by syntax (m5b: the constant `false`; m5c: an interval)
        for (b, form) in ((:(secreting => kind ∈ Set([cell, other])), "ismember(kind, (cell, other))"),
                          (:(secreting => kind ∈ (cell, other)), "ismember(kind, (cell, other))"),
                          (:(secreting => in(kind, (cell, other))), "ismember(kind, (cell, other))"))
            e = cp_build_err(w2_model(:(@fields c = W2.sec() ($b))))
            @test occursin("tests membership with", e) && occursin("a binding writes a kind set as `$form`", e) || (println(e); false)
        end
        # the route builds and fills both kinds
        @test w2_new(w2_model(:(@fields c = W2.sec() (secreting => ismember(kind, (cell, other)))))) == "built"
        # `Potts.couple`: `Potts.kind ∈ (1, 2)` is an interval pairing
        host = W2Host(; name = :m)
        e = cp_msg(() -> Potts.couple(host, W2.sec(); inputs = [W2.secreting => Potts.kind ∈ (1, 2)]))
        @test occursin("is bound to `kind ∈ 1 .. 2`, which Symbolics builds as an interval pairing (a domain), not a membership test", e) &&
              occursin("Potts.is_kind(model, :cell, …)", e) || (println(e); false)
        # the constant `false`: both causes and the route
        for b in (Potts.kind == :cell, Potts.kind ∈ Set([1, 2]))
            e = cp_msg(() -> Potts.couple(host, W2.sec(); inputs = [W2.secreting => b]))
            @test occursin("bound to the constant `false`", e) && occursin("`Potts.kind == :cell`", e) &&
                  occursin("`Potts.kind ∈ Set(…)`", e) && occursin("write `Potts.is_kind(model, :cell)`", e) || (println(e); false)
        end
        # m5: the key is a declared input that no equation reads (its `∈ Set(…)` term was deleted)
        e = w2_new(w2_model(:(@fields c = W2.inset() (W2.kin => kind))))
        @test occursin("`kin` is declared `[input = true]`, but no equation of the PDESystem `sec` reads it", e) &&
              occursin("`kin(t, x, y) ∈ Set(…)` is Julia's `false`, so its term is deleted", e) || (println(e); false)
        e = cp_msg(() -> Potts.couple(host, W2.inset(); inputs = [W2.kin => Potts.kind]))
        @test occursin("`kin` is declared `[input = true]`", e) || (println(e); false)
        # m5d: a listed input that nothing reads is a warning (it ran silently with max c = 0)
        Core.eval(@__MODULE__, w2_model(:(@fields c = W2.insetlong())))
        @test_logs (:warn, r"the PDESystem `sec` lists the input `kinl`, which no equation or condition reads") match_mode = :any Base.invokelatest(() -> W2M(; name = :m))
    end
end

# --- a kind name that is not a kind (m1c) -----------------------------------------------------
@testitem "F4-E16: @fields checks a kind name in a binding" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E16: @fields checks a kind name in a binding" begin
        e = w2_new(w2_model(:(@fields c = W2.sec() (secreting => kind == cells)); kinds = :(@kinds medium cell)))
        @test occursin("@fields: the binding `kind == cells` compares the kind with `cells`, which is not a kind of the model (it is", e) &&
              occursin("; its kinds are `medium`, `cell`", e) || (println(e); false)
        e = w2_new(w2_model(:(@fields c = W2.sec() (secreting => kind == celll)); kinds = :(@kinds medium cell)))
        @test occursin("`celll`, which is not a kind of the model; its kinds are `medium`, `cell`", e) || (println(e); false)
        # a kind name and a kind number still bind
        @test w2_new(w2_model(:(@fields c = W2.sec() (secreting => kind == cell)))) == "built"
        @test w2_new(w2_model(:(@fields c = W2.sec() (secreting => 1 == kind)))) == "built"
    end
end

# --- a cell quantity read in a PDESystem (m4, m4c) --------------------------------------------
# At 11523b0b: "`kind(t)` and `c(t, x, y)` have different independent variables" (pdesystem), and
# "`time` is not available in a site term or site update" (the long form).
@testitem "F4-E17: a PDESystem that reads a cell quantity is refused with the input route" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E17: a PDESystem that reads a cell quantity is refused with the input route" begin
        for (q, n) in ((Potts.kind, "kind"), (Potts.B.volume, "volume"))
            e = cp_msg(() -> W2.cellread(q))
            @test occursin("pdesystem: the equations read `$n`, a quantity of the CPM; a PDESystem cannot read cell quantities", e) &&
                  occursin("`@variables src(..)::Bool [input = true]`", e) && occursin("`@fields c = sys (src => kind == cell)`", e) ||
                  (println(e); false)
        end
        e = w2_new(w2_model(:(@fields c = W2.kindlong())))
        @test occursin("@fields: the PDESystem `sec` reads `kind`, a quantity of the CPM; a PDESystem cannot read cell quantities", e) &&
              occursin("src => kind == cell", e) && occursin("Potts.is_kind(model, :cell)", e) || (println(e); false)
        e = cp_msg(() -> Potts.couple(W2Host(; name = :m), W2.kindlong()))
        @test occursin("Potts.couple: the PDESystem `sec` reads `kind`, a quantity of the CPM", e) || (println(e); false)
        # Potts' `time` and `mcs` (not `Base.time`): the route is the system's own time `t`
        for (q, n, route) in ((Potts.B.time, "time", "write its independent variable `t` (`Potts.t`)"),
                              (Potts.B.mcs, "mcs", "write `step_index(t)` of its independent variable `t`"))
            @test Potts.info(q).role === :builtin
            e = cp_msg(() -> W2.clockread(q))
            @test occursin("pdesystem: the equations read `$n`, the model's", e) && occursin(route, e) &&
                  !occursin("cell quantities", e) || (println(e); false)
            e = w2_new(w2_model(:(@fields c = W2.clocklong(Potts.B.$(Symbol(n))))))
            @test occursin("@fields: the PDESystem `clk` reads `$n`, the model's", e) && occursin(route, e) &&
                  !occursin("cell quantities", e) || (println(e); false)
        end
        # the routes couple
        @test w2_new(w2_model(:(@fields c = W2.timeroute()))) == "built"
        @test w2_new(w2_model(:(@fields c = W2.mcsroute()))) == "built"
        # m7: a long form whose parameter list is empty names the list and `pdesystem`
        e = w2_new(w2_model(:(@fields c = W2.nops())))
        @test occursin("which is not one of its dependent variables, parameters or independent variables; list it " *
                       "in the 6th argument of `PDESystem` (its parameters, empty here)", e) && occursin("build the system with `pdesystem`", e) || (println(e); false)
    end
end

# --- E5: a domain entry for another variable ---------------------------------------------------
@testitem "F4-E5 review: a domain entry for a variable that is not an independent variable" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E5 review: a domain entry for a variable that is not an independent variable" begin
        e = w2_new(w2_model(:(@fields c = W2.zdom())))
        @test occursin("gives the domain `zz ∈ 0.0 .. 1.0`, but `zz` is not one of its independent variables (t, x, y)", e) ||
              (println(e); false)
    end
end

# --- E11: `sol[:u]` of an array field ------------------------------------------------------------
@testitem "F4-E11 review: sol[:u] of an array field names its components" setup = [CoupleSetup] tags = [:potts, :fields_couple_w2] begin
    @testset "F4-E11 review: sol[:u] of an array field names its components" begin
        sol = solve(PottsProblem(CeFiCompB(; name = :m), ce_op((12, 10)), (0, 1); field_solver = BackwardEuler()), SequentialCPM())
        @test sol[:u_1][end] isa AbstractArray
        e = cp_msg(() -> sol[:u])
        @test occursin("`u` is a vector quantity of m: read its components (:u_1, :u_2)", e) || (println(e); false)
    end
end
