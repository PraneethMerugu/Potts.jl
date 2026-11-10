# F4 wave 2 review fixes (the reviewers' programs ~/lpwork/rev-w2-probes/p14.jl and
# ~/lpwork/rev-w2u-progs/m*.jl, p2_array.jl). Uses `cp_msg` and `cp_build_err` of
# fields_couple.jl and `CeFiCompB`, `ce_op` of fields_couple_e11.jl. Negative controls (the
# tests at the src of 11523b0b): ~/lpwork/f4W2r/nc.log (there F4-E16 was named E17 to E19, and
# F4-E17 was E16).

module W2
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.5 s = 0.4 k = 0.05
@variables c(..) = 0.0 u(..) = 0.0 secreting(..)::Bool [input = true] kin(..)::Int32 [input = true]
@variables kinl(..)::Int32 [input = true, lattice_input_name = "kind"]
const C, U = c(t, x, y), u(t, x, y)
# E14: the condition on `c` sets the ghosts that `Δ(c)` in the equation of `u` reads (p14.jl)
withbc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U], [c(t, 0, y) ~ 1.0];
    name = :wbc)
nobc() = pdesystem([Differential(t)(C) ~ -0.1 * C, Differential(t)(U) ~ 0.5 * Δ(C) - 0.1 * U]; name = :nbc)
sec() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * secreting(t, x, y) - k * C]; name = :sec)
# m5: `∈ Set(…)` is Julia's `false`; the source term is gone before `pdesystem` sees it
inset() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kin(t, x, y) ∈ Set([1, 2])) - k * C]; name = :sec)
# m5d: the long form that lists the input (it is filled by `kind`, but no equation reads it)
insetlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (kinl(t, x, y) ∈ Set([1, 2])) - k * C], [], [], [t, x, y],
    [C, kinl(t, x, y)], [Dc, s, k]; name = :sec)
# m4: a test of Potts' `kind` (or `volume`) inside the equation
cellread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * (q == 1) - k * C]; name = :sec)
# m4c: the long form that reads Potts' `kind` in its equation
kindlong() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * (Potts.kind == 1) - k * C], [], [], [t, x, y], [C], [Dc, s, k];
    name = :sec)
# a read of Potts' clock built-ins (`Potts.B.time`, `Potts.B.mcs`), and the route: the system's own `t`
clockread(q) = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(q) - k * C]; name = :clk)
clocklong(q) = PDESystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(q) - k * C], [], [], [t, x, y], [C], [Dc, s, k]; name = :clk)
timeroute() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(t) - k * C]; name = :clk)
mcsroute() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * sin(step_index(t)) - k * C]; name = :clk)
# m7: the long form with an empty parameter list
nops() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [], [t, x, y], [C], []; name = :sys)
# E5: a domain entry for a variable that is not an independent variable
@parameters zz
zdom() = PDESystem([Differential(t)(C) ~ Dc * Δ(C) - k * C], [], [zz ∈ Interval(0.0, 1.0)], [t, x, y], [C], [Dc, k];
    name = :sys)
end

@potts_model W2Host begin
    @kinds medium cell other
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
w2_op() = (σ = zeros(Int32, 12, 10); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:cell]])
w2_model(fields; kinds = :(@kinds medium cell other)) = :(@potts_model W2M begin
    $kinds
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells => (volume - 9.0)^2
    $fields
    @sweep Metropolis(; temperature = 1.0)
end)
w2_new(ex) = cp_msg(() -> (Core.eval(Main, ex); Base.invokelatest(() -> Main.W2M(; name = :m))))

# --- E14: a face condition read through another field's operator ------------------------------
# At 11523b0b the condition on `c` was refused although `Δ(c)` in the equation of `u` reads its
# ghost values (with E14 bypassed, the runs with and without it differ: p1415.log).
@potts_model W2FaceW begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.withbc()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model W2FaceN begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields W2.nobc()
    @sweep Metropolis(; temperature = 1.0)
end
# the same through `@boundary` (`_check_boundaries`) and `@bcs` in an `@potts_model`
@potts_model W2FaceBnd begin
    @kinds medium A
    @variables c(field) = 0.0 u(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations begin
        D(c) ~ -0.1 * c
        D(u) ~ 0.5 * Δ(c) - 0.1 * u
    end
    @boundary c begin
        x => (Dirichlet(1.0), NoFlux())
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model W2FaceBcs begin
    @kinds medium A
    @variables c(field) = 0.0 u(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations begin
        D(c) ~ -0.1 * c
        D(u) ~ 0.5 * Δ(c) - 0.1 * u
    end
    @bcs c(t, 0, y) ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end
w2_face_op() = (σ = zeros(Int32, 8, 6); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
w2_u(m) = (pr = PottsProblem(m(; name = :m), w2_face_op(), (0, 3); seed = 1); Array(solve(pr, SequentialCPM()).u[end].site.u))

@testset "F4-E14 review: a face condition that another field's operator reads runs" begin
    uw, un = w2_u(W2FaceW), w2_u(W2FaceN)
    @test maximum(abs, uw .- un) > 1e-3
    # `@boundary` and `@bcs` give the same run as the PDESystem's condition
    @test w2_u(W2FaceBnd) == uw
    @test w2_u(W2FaceBcs) == uw
end

# --- an unbound input (m2) --------------------------------------------------------------------
@testset "F4-E16: an unbound input leads with the binding route" begin
    e = w2_new(w2_model(:(@fields c = W2.sec())))
    @test occursin("has the input `secreting(t, x, y)`, named `secreting`, which no binding fills", e) || (println(e); false)
    i, j = findfirst("@fields … (secreting => kind == cell)", e), findfirst("lattice_input_name", e)
    @test i !== nothing && j !== nothing && first(i) < first(j) || (println(e); false)
    @test occursin("`inputs = [secreting => Potts.is_kind(model, :cell)]` in `Potts.couple`", e) || (println(e); false)
end

# --- membership mistakes (m5, m5b, m5c, m5d, m4b) ---------------------------------------------
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
    Core.eval(Main, w2_model(:(@fields c = W2.insetlong())))
    @test_logs (:warn, r"the PDESystem `sec` lists the input `kinl`, which no equation or condition reads") match_mode = :any Base.invokelatest(() -> W2M(; name = :m))
end

# --- a kind name that is not a kind (m1c) -----------------------------------------------------
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

# --- a cell quantity read in a PDESystem (m4, m4c) --------------------------------------------
# At 11523b0b: "`kind(t)` and `c(t, x, y)` have different independent variables" (pdesystem), and
# "`time` is not available in a site term or site update" (the long form).
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
