# F4-B2 (F4 design §11, research/front-end-b-only.md §1a, §2): a plain MTK `PDESystem` couples
# into a model, `Potts.couple(model, pdesys; inputs)` or `@fields pdesys (bindings…)` in
# `@potts_model`. Its fields join the model under their own names (`c`, not `name₊c`); each
# input of the PDESystem (a plain 0/1 or numeric input field) is bound to a CPM expression
# (`kind == A`, `volume[owner]`), filled per site by the field compiler. Oracles: the same field
# written in `@equations` (bitwise); a model that extends the coupled one reads the field by
# name in a drive (bitwise against the `@equations` model with the same drive); ForwardDiff
# against central differences at a fixed CPM path (F3-21b's shadow store); the ODE path, the
# PDESystem solved by Tsit5 with `Potts.field_inputs(integ)` against the owned explicit run at
# 400 substeps (max difference 4.05e-5, tolerance 6e-5), and the inputs against hand-computed
# site arrays (F4-09).
# Negative controls: at the base 4d025fa8 `Potts.couple`, `Potts.field_inputs` and `@fields` do
# not exist (a LoadError, ~/lpwork/f4B2/nc-base.log). A mutation that gives each of two bound
# inputs the other's expression fails the bitwise testsets (~/lpwork/f4B2/nc-swap.log), and a
# wrong binding (`kind == medium`) is checked to differ in this file.
using Potts, Test
using ForwardDiff: ForwardDiff
using OrdinaryDiffEqTsit5: Tsit5

module CpPDE
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
const t = Potts.t
const Dt = Differential(t)
const Δ = Potts.LatticePDE.Δ
@parameters x y Dc = 0.2 s = 0.5 kd = 0.1 av = 0.01
@variables c(..) u(..) endo(..)::Bool [input = true] vol(..) [input = true] med(..)::Bool [input = true]
const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 24.0), y ∈ Interval(0.0, 20.0)]
# `D(c) ~ Dc Δc + s·endo − kd·c + av·vol`: endo is 0/1 and vol a number, both plain inputs
sys(; name = :fields, dom = DOM) = PDESystem(
    [Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y) + av * vol(t, x, y)],
    [c(0, x, y) ~ 0.0], dom, [t, x, y], [c(t, x, y), endo(t, x, y), vol(t, x, y)], [Dc, s, kd, av]; name)
# two fields: `u` reads `c`
sys3(; name = :fields) = PDESystem([Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y),
        Dt(u(t, x, y)) ~ 0.3 * Δ(u(t, x, y)) + 0.2 * c(t, x, y) - 0.2 * u(t, x, y)],
    [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], DOM, [t, x, y], [c(t, x, y), u(t, x, y), endo(t, x, y)], [Dc, s, kd]; name)
# the same without `vol` (for the derivative and ODE-path checks)
sys2(; name = :fields) = PDESystem([Dt(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + s * endo(t, x, y) - kd * c(t, x, y)],
    [c(0, x, y) ~ 0.0], DOM, [t, x, y], [c(t, x, y), endo(t, x, y)], [Dc, s, kd]; name)
end

# the references: the same field in `@equations`, with and without a drive that reads it
@potts_model CpRef begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        s = 0.5
        kd = 0.1
        av = 0.01
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) + s * (kind == A) - kd * c + av * volume[owner]
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CpRefDrive begin
    @kinds medium A
    @parameters begin
        χ = 400.0
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @equations D(c) ~ Dc * Δ(c) + s * (kind == A) - kd * c
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CpHost begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end
# `@fields` in the model body: the bindings read the model's own words (`kind == A`, `volume[owner]`)
@potts_model CpFields begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys() (CpPDE.endo => kind == A, CpPDE.vol => volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CpFields2 begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys2() (CpPDE.endo => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end
# a model that extends the coupled one reads its field `c` by name in a drive
@potts_model CpDrive begin
    @extend c, A = base = CpFields2()
    @parameters χ = 400.0
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
end
# the field named in `@fields` and read by a drive in the same body (user ruling 2026-11-10)
@potts_model CpSame begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end
# a list of names; and one name, the other field reached by name
@potts_model CpList begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, u = CpPDE.sys3() (CpPDE.endo => kind == A)
    @drive Chemotaxis(u; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CpOne begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CpPDE.sys3() (CpPDE.endo => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CpRefTwo begin
    @kinds medium A
    @parameters begin
        χ = 400.0
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @drive Chemotaxis(u; strength = χ, kinds = (A,))
    @equations begin
        D(c) ~ Dc * Δ(c) + s * (kind == A) - kd * c
        D(u) ~ 0.3 * Δ(u) + 0.2 * c - 0.2 * u
    end
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CpRefTwoC begin
    @kinds medium A
    @parameters begin
        χ = 400.0
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @equations begin
        D(c) ~ Dc * Δ(c) + s * (kind == A) - kd * c
        D(u) ~ 0.3 * Δ(u) + 0.2 * c - 0.2 * u
    end
    @sweep Metropolis(; temperature = 4.0)
end
# a wrong binding (the medium, not `A`): the in-file control of the bitwise oracles
@potts_model CpWrong begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys() (CpPDE.endo => kind == medium, CpPDE.vol => volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end
# frozen cells (σ fixed: the ODE-path oracle)
@potts_model CpFrozen begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys2() (CpPDE.endo => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

cp_op() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])
cp_run(m, fs, k = 12; op = cp_op(), kw...) =
    solve(PottsProblem(m, op, (0, k); field_solver = fs, seed = 3, kw...), SequentialCPM(); saveat = 0:3:k)
cp_msg(f) = try
    f()
    "built"
catch e
    e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
end
const CP_W = [0.01 * (i + 2j) for i in 1:24, j in 1:20]
cp_q(sol) = sum(CP_W .* sol.u[end].site.c)
# the ODE-path tolerance: the owned explicit run's time error at 400 substeps (first order in
# the substep). Measured 4.05e-5 on the CPU (2026-11-10); the bound leaves 1.5x room
const CP_ODE_TOL = 6e-5

@testset "F4-B2: Potts.couple equals the field in @equations (bitwise), under its own names" begin
    T, X, Y = CpPDE.t, CpPDE.x, CpPDE.y
    vol = Potts.at(Potts.B.volume, Potts.B.owner)
    # keys as the callable, the applied variable and the name
    for ins in ([CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol],
                [CpPDE.endo(T, X, Y) => Potts.kind == 1, :vol => vol])
        m = Potts.couple(CpHost(; name = :m), CpPDE.sys(); inputs = ins)
        @test any(x -> Potts.info(x).name === :c, Potts.variables(m))                 # `c`, not `fields₊c`
        @test Set(Potts.info(q).name for q in Potts.parameters(m)) == Set([:Dc, :s, :kd, :av])
        for fs in (ExplicitEuler(), BackwardEuler())
            a, b = cp_run(m, fs), cp_run(CpRef(; name = :m), fs)
            @test all(a.u[i].σ == b.u[i].σ for i in eachindex(b.u))
            @test all(a.u[i].site.c == b.u[i].site.c for i in eachindex(b.u)) && maximum(b.u[end].site.c) > 0.5
        end
    end
    # its parameters by name in the operating point, its field in a `FieldGroups` pair
    m = Potts.couple(CpHost(; name = :m), CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol])
    a = cp_run(m, FieldGroups(:c => BackwardEuler()); op = [cp_op(); :s => 0.9])
    b = cp_run(CpRef(; name = :m), FieldGroups(:c => BackwardEuler()); op = [cp_op(); :s => 0.9])
    @test a.u[end].site.c == b.u[end].site.c && a.u[end].site.c != cp_run(CpRef(; name = :m), BackwardEuler()).u[end].site.c
    @test a[:c][end] == b[:c][end]
end

@testset "F4-B2: @fields in @potts_model; a drive reads the field by name" begin
    for fs in (ExplicitEuler(), BackwardEuler())
        a, b = cp_run(CpFields(; name = :m), fs), cp_run(CpRef(; name = :m), fs)
        @test all(a.u[i].site.c == b.u[i].site.c for i in eachindex(b.u))
        # the drive reads `c` (the CPM path depends on the field), bitwise against `@equations`
        d, r = cp_run(CpDrive(; name = :m), fs), cp_run(CpRefDrive(; name = :m), fs)
        @test all(d.u[i].σ == r.u[i].σ for i in eachindex(r.u)) && all(d.u[i].site.c == r.u[i].site.c for i in eachindex(r.u))
        # (control: the drive moves the path)
        @test r.u[end].σ != cp_run(CpRef(; name = :m), fs).u[end].σ
    end
    # the operating point reaches the coupled parameters as any others
    @test cp_run(CpFields(; name = :m), ExplicitEuler(); op = [cp_op(); :kd => 0.3]).u[end].site.c ==
          cp_run(CpRef(; name = :m), ExplicitEuler(); op = [cp_op(); :kd => 0.3]).u[end].site.c
    # and so do the constructor keywords (S1 of the F4-B2 review); an unknown keyword is refused
    k = cp_run(CpFields(; name = :m, kd = 0.3), ExplicitEuler()).u[end].site.c
    @test k == cp_run(CpRef(; name = :m, kd = 0.3), ExplicitEuler()).u[end].site.c
    @test k != cp_run(CpRef(; name = :m), ExplicitEuler()).u[end].site.c
    @test occursin("has no keyword `zz`", cp_msg(() -> CpFields(; name = :m, zz = 1.0)))
end

cp_same(r, a) = all(r.u[i].σ == a.u[i].σ for i in eachindex(r.u)) &&
                all(r.u[i].site == a.u[i].site for i in eachindex(r.u))
cp_build_err(ex) = try
    Core.eval(Main, ex)
    "built"
catch err
    sprint(showerror, err)
end

@testset "F4-B2: @fields c = pdesys binds the field for the statements after it" begin
    for fs in (ExplicitEuler(), BackwardEuler())
        # the drive in the same body: bitwise the `@extend` route and the `@equations` model
        a, d, r = cp_run(CpSame(; name = :m), fs), cp_run(CpDrive(; name = :m), fs), cp_run(CpRefDrive(; name = :m), fs)
        @test cp_same(r, a) && cp_same(d, a)
        @test r.u[end].σ != cp_run(CpRef(; name = :m), fs).u[end].σ             # (control: the drive moves the path)
        # a list of names; one name with the other field reached by name
        @test cp_same(cp_run(CpRefTwo(; name = :m), fs), cp_run(CpList(; name = :m), fs))
        o, ro = cp_run(CpOne(; name = :m), fs), cp_run(CpRefTwoC(; name = :m), fs)
        @test cp_same(ro, o) && maximum(o[:u][end]) > 0
    end
    # control: a wrong binding is caught by the bitwise oracle
    @test cp_run(CpWrong(; name = :m), ExplicitEuler()).u[end].site.c != cp_run(CpRef(; name = :m), ExplicitEuler()).u[end].site.c
    body(line; pre = :(), post = :()) = quote
        @potts_model CpBadNames begin
            @kinds medium A
            $pre
            @lattice Lattice((24, 20); boundary = Closed())
            $line
            $post
            @sweep Metropolis(; temperature = 4.0)
        end
        CpBadNames(; name = :m)
    end
    # a name that is not a field of the PDESystem (an input is not a field)
    for n in (:w, :endo)
        e = cp_build_err(body(:(@fields $n = CpPDE.sys2() (CpPDE.endo => kind == A))))
        @test occursin("`$n` is not a field of the PDESystem `fields`; its fields are `c`", e) || (println(e); false)
    end
    # a field listed twice
    e = cp_build_err(body(:(@fields c, c = CpPDE.sys3() (CpPDE.endo => kind == A))))
    @test occursin("the field `c` is listed twice", e) || (println(e); false)
    # a name that clashes with the model: declared before, after, or one the PDESystem brings in
    e = cp_build_err(body(:(@fields c = CpPDE.sys2() (CpPDE.endo => kind == A)); pre = :(@parameters c = 1.0)))
    @test occursin("`c` is already declared as a parameter", e) || (println(e); false)
    e = cp_build_err(body(:(@fields c = CpPDE.sys2() (CpPDE.endo => kind == A)); post = :(@variables c(field) = 0.0)))
    @test occursin("`c` is already declared as a field", e) || (println(e); false)
    e = cp_build_err(body(:(@fields c = CpPDE.sys2() (CpPDE.endo => kind == A)); pre = :(@parameters kd = 1.0)))
    @test occursin("already has a parameter `kd`", e) || (println(e); false)
    # before the lattice
    e = cp_build_err(quote
        @potts_model CpBadNames begin
            @kinds medium A
            @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
            @lattice Lattice((24, 20); boundary = Closed())
            @sweep Metropolis(; temperature = 4.0)
        end
        CpBadNames(; name = :m)
    end)
    @test occursin("write `@fields` after `@lattice`", e) || (println(e); false)
end

@testset "F4-B2: refusals name the input and the PDESystem" begin
    host = CpHost(; name = :m)
    vol = Potts.at(Potts.B.volume, Potts.B.owner)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.med => Potts.kind == 0]))
    @test occursin("`med` is not a dependent variable of the PDESystem `fields`", e) && occursin("`endo`, `vol`", e)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.c => Potts.kind == 0]))
    @test occursin("not an input", e) && occursin("[input = true]", e)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, :endo => Potts.kind == 0]))
    @test occursin("`endo` is bound twice", e)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => vol]))
    @test occursin("`endo` is a `Bool`", e) && occursin("not a truth value", e)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.vol => CpPDE.kd]))
    @test occursin("reads `kd`, not a quantity of `m`", e)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol, 3]))
    @test occursin("pairs `input => expression`", e)
    # an unbound input with no CPM word is refused as before (`vol` is not a word the CPM fills)
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1]))
    @test occursin("`vol`", e) && occursin("does not fill at a site", e)
    # a name the model has already: refused (a namespaced component is the route)
    e = cp_msg(() -> Potts.couple(CpRef(; name = :m), CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol]))
    @test occursin("already has a parameter `Dc`", e) || occursin("already has a field `c`", e)
    # `@fields` syntax
    e = try
        @eval @potts_model CpBadFields begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @fields CpPDE.sys() (CpPDE.endo, CpPDE.vol => volume[owner])
            @sweep Metropolis(; temperature = 4.0)
        end
        ""
    catch err
        sprint(showerror, err)
    end
    @test occursin("is not a binding; write `input => expression`", e)
    # the `:field` scope of `ode_system`: still refused with "field", now naming the route
    cs = mtkcompile(CpFields2(; name = :m))
    e = cp_msg(() -> Potts.ode_system(cs, :field))
    @test occursin("field", e) && occursin("Potts.field_inputs(integ)", e) && occursin("Potts.fields(csys)", e)
    @test !occursin("field_inputs", cp_msg(() -> Potts.ode_system(cs, :site)))
end

# F3-21b's shadow store through the coupling: a Dual parameter of the PDESystem runs, the CPM
# path stays primal, and the derivative matches central differences at the same seed
@testset "F4-B2: field derivatives of a coupled model against central differences" begin
    tight = DevicePCG(; rtol = 1e-11, budget = 60)
    for fs in (ExplicitEuler(), BackwardEuler(; inner = tight)), M in (CpFields2, CpDrive)
        base = cp_run(M(; name = :m), fs)
        for (name, v) in ((:s, 0.5), (:kd, 0.1), (:Dc, 0.2))
            d = cp_run(M(; name = :m), fs; op = [cp_op(); name => ForwardDiff.Dual(v, 1.0)])
            @test all(d.u[i].σ == base.u[i].σ for i in eachindex(base.u))
            @test all(ForwardDiff.value.(d.u[i].site.c) == base.u[i].site.c for i in eachindex(base.u))
            @test eltype(d.u[end].site.c) <: ForwardDiff.Dual
            h = 1e-4 * v
            rp = cp_run(M(; name = :m), fs; op = [cp_op(); name => v + h])
            rm = cp_run(M(; name = :m), fs; op = [cp_op(); name => v - h])
            @test all(rp.u[i].σ == base.u[i].σ == rm.u[i].σ for i in eachindex(base.u))   # the path is fixed
            fd = (cp_q(rp) - cp_q(rm)) / 2h
            @test ForwardDiff.partials(cp_q(d), 1) ≈ fd rtol = 1e-6
            @test abs(fd) > 1e-6                                                          # (not a zero derivative)
        end
    end
    # `ForwardDiff.derivative` through `solve` of a `Potts.couple` model
    m = Potts.couple(CpHost(; name = :m), CpPDE.sys2(); inputs = [CpPDE.endo => Potts.kind == 1])
    f(k) = cp_q(cp_run(m, ExplicitEuler(); op = [cp_op(); :kd => k]))
    @test ForwardDiff.derivative(f, 0.1) ≈ (f(0.1 + 1e-5) - f(0.1 - 1e-5)) / 2e-5 rtol = 1e-6
end

# F4-09 through the coupling: the PDESystem stays a plain MTK system, and
# `Potts.field_inputs(integ)` gives its inputs at the CPM state of an integrator
@testset "F4-B2: Potts.field_inputs and the ODE path (Tsit5) of the coupled PDESystem" begin
    # the inputs at MCS 5 of a moving run, against site arrays computed by hand
    integ = init(PottsProblem(CpFields(; name = :m), cp_op(), (0, 10); seed = 3), SequentialCPM())
    for _ in 1:5
        step!(integ)
    end
    inp = Potts.field_inputs(integ)
    σ = Array(integ.u.σ)
    k = Array(integ.u.cell.kind)
    V = [count(==(j), σ) for j in 1:length(k)]
    @test Set(keys(inp)) == Set([:endo, :vol])
    @test eltype(inp[:endo]) === Bool && inp[:endo] == [s != 0 && k[s] == 1 for s in σ]
    @test eltype(inp[:vol]) === Float64 && inp[:vol] == [s == 0 ? 0.0 : Float64(V[s]) for s in σ]
    @test σ != cp_op()[1][2]                                                            # (the cells moved)
    # the initial state of a problem; a model without coupled inputs
    p = PottsProblem(CpFields(; name = :m), cp_op(), (0, 1))
    @test Potts.field_inputs(p)[:endo] == (cp_op()[1][2] .!= 0)
    @test isempty(Potts.field_inputs(PottsProblem(CpRef(; name = :m), cp_op(), (0, 1))))
    # the ODE path: σ frozen, the PDESystem discretized with those inputs and solved by Tsit5 over
    # one MCS from the field at MCS 5, against the owned explicit run at many substeps
    integ = init(PottsProblem(CpFrozen(; name = :m), cp_op(), (0, 6); seed = 3, field_solver = ExplicitEuler(; substeps = 400)),
        SequentialCPM())
    for _ in 1:5
        step!(integ)
    end
    c5 = copy(Array(integ.u.site.c))
    prob = Potts.LatticePDE.discretize(CpPDE.sys2(), Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((24, 20)); T = Float64);
        inputs = collect(Potts.field_inputs(integ)))
    s = solve(remake(prob; u0 = vec(c5), tspan = (0.0, 1.0)), Tsit5(); abstol = 1e-11, reltol = 1e-11)
    step!(integ)
    c6 = Array(integ.u.site.c)
    err = maximum(abs, reshape(s.u[end], 24, 20) .- c6)
    @info "F4-B2 ODE path: Tsit5 vs the owned run at 400 substeps, max difference $err"
    @test err < CP_ODE_TOL
    @test maximum(abs, c6 .- c5) > 1e-2                                                 # (the field moved)
end

# ---------------------------------------------------------------------------------------------
# F4-B2 review (2026-11-10, probes ~/lpwork/f4w1-rev/b1.jl, b2.jl, u1.jl): richer models
# bitwise against `@equations`, and the regressions M1 (an unbound `Bool` input filled by a
# non-Bool word), M2 (a parameter declared again after `@fields`) and M3 (`kind == :A` in
# `Potts.couple`, always false: refused with the route). Each M testset fails at 5d86cc6e (~/lpwork/f4B2/nc-rev.log).
module CpRev
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
const t = Potts.t
const Dt = Differential(t)
const Δ = Potts.LatticePDE.Δ
const masked = Potts.LatticePDE.masked
@parameters x y Dc = 0.2 s = 0.5 kd = 0.1 kq = 1.0
@variables c(..) q(..) w(..) cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)]
@variables endo(..)::Bool [input = true] isB(..)::Bool [input = true] vol(..) [input = true] cin(..) [input = true]
@variables cnm(..) [input = true, lattice_input_name = "c"]
@variables kb(..)::Bool [input = true, lattice_input_name = "kind"] kr(..) [input = true, lattice_input_name = "kind"]
const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 24.0), y ∈ Interval(0.0, 20.0)]
C, Q, W = c(t, x, y), q(t, x, y), w(t, x, y)
# a Dirichlet face, a Neumann face, a mask on the B cells and a steady companion `q`
rich() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C + 0.01 * vol(t, x, y), 0 ~ 0.5 * Δ(Q) - kq * Q + C],
    [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 0.5, Differential(x)(c(t, 24, y)) ~ 0.0, C ~ masked(isB(t, x, y) == 1, 1.0)],
    DOM, [t, x, y], [C, Q, endo(t, x, y), isB(t, x, y), vol(t, x, y)], [Dc, s, kd, kq]; name = :rich)
first_sys() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, endo(t, x, y)], [Dc, s, kd]; name = :one)
second_unbound() = PDESystem([Dt(W) ~ 0.3 * Δ(W) - W + 0.7 * cnm(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
    [W, cnm(t, x, y)], Any[]; name = :two)
second_bound() = PDESystem([Dt(W) ~ 0.3 * Δ(W) - W + 0.7 * cin(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
    [W, cin(t, x, y)], Any[]; name = :twob)
coarse_sys() = PDESystem([Dt(cc(t, x, y)) ~ Dc * Δ(cc(t, x, y)) + s * endo(t, x, y) - kd * cc(t, x, y)], [cc(0, x, y) ~ 0.0],
    DOM, [t, x, y], [cc(t, x, y), endo(t, x, y)], [Dc, s, kd]; name = :crs)
# an unbound input filled by the word `kind`: a `Bool` one (refused) and a number
kind_bool() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * kb(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, kb(t, x, y)], [Dc, s, kd]; name = :kbs)
kind_real() = PDESystem([Dt(C) ~ Dc * Δ(C) + s * kr(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
    [C, kr(t, x, y)], [Dc, s, kd]; name = :krs)
end

@potts_model CrLifeRef begin
    @kinds medium A B
    @parameters begin
        Dc = 0.2
        s = 0.5
        kd = 0.1
        kq = 1.0
    end
    @variables begin
        c(field) = 0.0
        q(field) = 0.0
        V_target(cell) = 40.0
    end
    @lattice Lattice((24, 20); boundary = Closed())
    @energy begin
        cells => 4.0 * (volume - V_target)^2
        contacts => 2.0 * (kind != kind′)
    end
    @equations begin
        D(c) ~ Dc * Δ(c) + s * (kind == A) - kd * c + 0.01 * volume[owner]
        0 ~ 0.5 * Δ(q) - kq * q + c
    end
    @bcs begin
        c(t, 0, y) ~ 0.5
        Differential(x)(c(t, 24, y)) ~ 0.0
        c ~ masked(kind == B, 1.0)
    end
    @divide cells(A) when = volume >= 30
    @after_mcs V_target ~ ifelse((mcs >= 2) && (id == 2), 0.0, 40.0)
    @sweep Metropolis(; temperature = 6.0)
end
@potts_model CrLife begin
    @kinds medium A B
    @variables V_target(cell) = 40.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy begin
        cells => 4.0 * (volume - V_target)^2
        contacts => 2.0 * (kind != kind′)
    end
    @fields CpRev.rich() (CpRev.endo => kind == A, CpRev.isB => kind == B, CpRev.vol => volume[owner])
    @divide cells(A) when = volume >= 30
    @after_mcs V_target ~ ifelse((mcs >= 2) && (id == 2), 0.0, 40.0)
    @sweep Metropolis(; temperature = 6.0)
end
@potts_model CrTwoRef begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables begin
        c(field) = 0.0
        w(field) = 0.0
    end
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(c) ~ Dc * Δ(c) + s * (kind == A) - kd * c
        D(w) ~ 0.3 * Δ(w) - w + 0.7 * c
    end
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrTwoU begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CpRev.first_sys() (CpRev.endo => kind == A)
    @fields CpRev.second_unbound()
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrTwoB begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields c = CpRev.first_sys() (CpRev.endo => kind == A)
    @fields CpRev.second_bound() (CpRev.cin => c)
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrCrsRef begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables cc(field) = 0.0, [lattice_level = Coarse(2)]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @equations D(cc) ~ Dc * Δ(cc) + s * (kind == A) - kd * cc
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrCrs begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CpRev.coarse_sys() (CpRev.endo => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrKindRef begin
    @kinds medium A B
    @parameters begin
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) + s * kind - kd * c
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrKindReal begin
    @kinds medium A B
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CpRev.kind_real()
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CrHost2 begin
    @kinds medium A B
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end

cr_rich_op() = (σ = zeros(Int32, 24, 20); σ[3:7, 3:7] .= 1; σ[12:16, 4:8] .= 2; σ[6:10, 12:16] .= 3; σ[16:20, 13:17] .= 4;
                [ownership => σ, kind => [:A, :B, :A, :A]])
cr_kop() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :B]])
cr_run(m, fs, k = 10; op = cp_op(), seed = 5) =
    solve(PottsProblem(m, op, (0, k); field_solver = fs, seed), SequentialCPM(); saveat = 0:2:k)

@testset "F4-B2 review: lifecycle, faces, mask, steady rows, two PDESystems and Coarse(2), bitwise" begin
    for fs in (ExplicitEuler(), BackwardEuler(), FieldGroups(:c => BackwardEuler(), :q => QuasiSteady()))
        a, b = cr_run(CrLife(; name = :m), fs, 20; op = cr_rich_op()), cr_run(CrLifeRef(; name = :m), fs, 20; op = cr_rich_op())
        @test cp_same(b, a)
        # (the run divides cells and kills cell 2)
        live = [length(setdiff(unique(u.σ), 0)) for u in b.u]
        @test live[end] > live[1] && any(u -> count(==(2), u.σ) == 0, b.u)
    end
    for fs in (ExplicitEuler(), BackwardEuler())
        r = cr_run(CrTwoRef(; name = :m), fs)
        @test cp_same(r, cr_run(CrTwoU(; name = :m), fs)) && cp_same(r, cr_run(CrTwoB(; name = :m), fs))
        @test maximum(r.u[end].site.w) > 0.1
        c = cr_run(CrCrs(; name = :m), fs)
        @test cp_same(cr_run(CrCrsRef(; name = :m), fs), c) && size(c.u[end].site.cc) == (12, 10)
    end
end

@testset "F4-B2 review M1: an unbound Bool input filled by a non-Bool word is refused" begin
    e = cp_build_err(quote
        @potts_model CrKindBool begin
            @kinds medium A B
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells => (volume - 16.0)^2
            @fields CpRev.kind_bool()
            @sweep Metropolis(; temperature = 4.0)
        end
        CrKindBool(; name = :m)
    end)
    @test occursin("`Bool` input `kind`", e) && occursin("bind it: `kb => kind == A`", e) || (println(e); false)
    e = cp_msg(() -> Potts.couple(CrHost2(; name = :m), CpRev.kind_bool()))
    @test occursin("bind it: `kb => Potts.kind == :A`", e) || (println(e); false)
    # a numeric input filled by `kind` reads the kind number; `field_inputs` gives the same values
    a = cr_run(CrKindReal(; name = :m), ExplicitEuler(); op = cr_kop())
    @test cp_same(cr_run(CrKindRef(; name = :m), ExplicitEuler(); op = cr_kop()), a)
    fi = Potts.field_inputs(PottsProblem(CrKindReal(; name = :m), cr_kop(), (0, 1)))
    @test fi[:kind][6, 6] === 1.0 && fi[:kind][15, 11] === 2.0 && fi[:kind][1, 1] === 0.0
end

@testset "F4-B2 review M2: a name @fields brought in, declared again after it, is refused" begin
    e = cp_build_err(quote
        @potts_model CrAfter begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells => (volume - 16.0)^2
            @fields CpRev.first_sys() (CpRev.endo => kind == A)
            @parameters kd = 5.0
            @sweep Metropolis(; temperature = 4.0)
        end
        CrAfter(; name = :m)
    end)
    @test occursin("`kd` is already declared by `@fields` (the PDESystem `one`)", e) || (println(e); false)
    e = cp_build_err(quote
        @potts_model CrAfterField begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells => (volume - 16.0)^2
            @fields CpRev.first_sys() (CpRev.endo => kind == A)
            @variables c(site) = 0.0
            @sweep Metropolis(; temperature = 4.0)
        end
        CrAfterField(; name = :m)
    end)
    @test occursin("`c` is already declared by `@fields`", e) || (println(e); false)
end

# (`Potts.kind == :A` is Julia's constant `false`: the name cannot be resolved, so a binding to a
# constant truth value is refused with the route, and the route gives the `kind == 1` model)
@testset "F4-B2 review M3: kind names in Potts.couple" begin
    host = CrHost2(; name = :m)
    e = cp_msg(() -> Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => Potts.kind == :A]))
    @test occursin("bound to the constant `false`", e) && occursin("a binding to a constant is the same at every site", e) &&
          occursin("Potts.kind == Potts.lookup(model, :A)", e) ||
          (println(e); false)
    e = cp_msg(() -> Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => true]))
    @test occursin("a binding to a constant is the same at every site", e) && !occursin("kind name", e) || (println(e); false)
    ma = Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => Potts.kind == Potts.lookup(host, :A)])
    m1 = Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => Potts.kind == 1])
    a, b = cr_run(ma, ExplicitEuler(); op = cr_kop()), cr_run(m1, ExplicitEuler(); op = cr_kop())
    @test cp_same(b, a) && maximum(a.u[end].site.c) > 0.5
    @test Potts.field_inputs(PottsProblem(ma, cr_kop(), (0, 1)))[:endo][6, 6] === true
end

@testset "F4-B2 review S2: messages name the @fields binding and line order" begin
    hdr(line; first = :(@kinds medium A)) = quote
        @potts_model CrMsg begin
            $first
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells => (volume - 16.0)^2
            $line
            @sweep Metropolis(; temperature = 4.0)
        end
        CrMsg(; name = :m)
    end
    e = cp_build_err(hdr(:(@fields CpPDE.sys() (CpPDE.endo => kind == A, CpPDE.vol => volume))))
    @test occursin("@fields: the input `vol` is bound to `volume`", e) && occursin("`volume[owner]`", e) &&
          !occursin("@equations", e) || (println(e); false)
    # a name read before the line that binds it
    e = cp_build_err(quote
        @potts_model CrEarly begin
            @kinds medium A
            @parameters χ = 400.0
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells(A) => (volume - 16.0)^2
            @drive Chemotaxis(c; strength = χ, kinds = (A,))
            @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
            @sweep Metropolis(; temperature = 4.0)
        end
    end)
    @test occursin("`c` is read on a line before `@fields c = …`", e) && occursin("move the `@fields` line above", e) ||
          (println(e); false)
    # before `@kinds`
    e = cp_build_err(quote
        @potts_model CrNoKinds begin
            @lattice Lattice((24, 20); boundary = Closed())
            @fields CpPDE.sys2() (CpPDE.endo => kind == A)
            @kinds medium A
            @sweep Metropolis(; temperature = 4.0)
        end
    end)
    @test occursin("write `@fields` after `@kinds`", e) || (println(e); false)
end
