# F4-11 (F4 design §3.8 FE-15b): a plain `PDESystem` composes into a model as fields.
# `compose(model, Potts.component(:drug, pdesys, model))` equals the same field coupled
# with `@fields`, bitwise on the CPU with
# σ frozen (one group); the component reads
# `kind` by its user word; its fields take `FieldGroups` pairs by name; a domain other than the
# lattice's (in the model's length unit, `@lattice spacing`) is refused naming both.
# Base (the F4-10 commit, ~/lpwork/f4c/nc11-base.log): `Potts.component` takes no PDESystem
# (a MethodError in every testset that builds one); a component carrying a PDESystem is refused
# with "has a PDESystem; a component's fields are not compiled".

@testsetup module FieldsComponentsSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts, Test


module FcPDE
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, System, Equation, Differential, @variables, @parameters
const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
const t = Potts.t
const Dt = Differential(t)
@parameters x y Dd = 0.2 kd = 0.5
@variables u(..) kin(..)::Int32 [input = true, lattice_input_name = "kind"]
@variables nut(..) [input = true, lattice_input_name = "nutrient"]
@variables kind(..)::Int32 [input = true]
@variables vol(..) [input = true, lattice_input_name = "volume"]
@variables zq(t) = 1.0
zz() = System([Dt(zq) ~ -zq], t; name = :zz)
# `D(u) ~ Dd Δu − kd u` with the conditions `bcs` (review fixups: names, start values, ivs)
const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 12.0), y ∈ Interval(0.0, 10.0)]
plain(bcs; name = :drug, ivs = [t, x, y], ps = [Dd, kd], dom = DOM) =
        PDESystem([Dt(u(t, x, y)) ~ Dd * Potts.LatticePDE.laplacian(u(t, x, y)) - kd * u(t, x, y)], bcs, dom, ivs, [u(t, x, y)], ps; name)
const Dx = Differential(x)
# `D(u) ~ Dd Δu − kd u + [kind = 1]`, `u = 1` on the low x face, zero flux on the others
function drug(L; name = :drug, extra = Equation[], dvs = [u(t, x, y), kin(t, x, y)],
            rhs = Dd * Potts.LatticePDE.laplacian(u(t, x, y)) - kd * u(t, x, y) + ifelse(kin(t, x, y) == 1, 1.0, 0.0)
        )
    return PDESystem([Dt(u(t, x, y)) ~ rhs], [u(0, x, y) ~ 0.0; u(t, 0, y) ~ 1.0; extra],
        [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, L[1]), y ∈ Interval(0.0, L[2])], [t, x, y], dvs, [Dd, kd]; name)
end
# the references, coupled with `@fields` (F4-B4t): `drug` with the kind as the bound input `kA`
@variables kA(..)::Bool [input = true]
ref(L) = drug(L; name = :fields, dvs = [u(t, x, y), kA(t, x, y)],
        rhs = Dd * Potts.LatticePDE.laplacian(u(t, x, y)) - kd * u(t, x, y) + ifelse(kA(t, x, y), 1.0, 0.0)
    )
# a host field `zz` with its own `kd`, and a host field `u`
function hostk()
    @parameters kd = 0.9
    @variables zz(..)
    Z = zz(t, x, y)
    return PDESystem([Dt(Z) ~ -kd * Z], [zz(0, x, y) ~ 3.0], DOM, [t, x, y], [Z], [kd]; name = :fields)
end
hostu() = PDESystem([Dt(u(t, x, y)) ~ -u(t, x, y)], [u(0, x, y) ~ 3.0], DOM, [t, x, y], [u(t, x, y)], Any[]; name = :fields)
end


# the reference: the same field coupled with `@fields`; and the host without it
@potts_model FcRef begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FcPDE.ref((12, 10)) (FcPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcHost begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# with a lattice spacing (one length unit per model: the component spans dims × spacing)
@potts_model FcRefH begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed(), spacing = (0.5, 0.5))
    @energy cells(A) => (volume - 9.0)^2
    @fields FcPDE.ref((6, 5)) (FcPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcHostH begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed(), spacing = (0.5, 0.5))
    @energy cells(A) => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end


fcm_op() = (σ = zeros(Int32, 12, 10); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

fc_run(m, field, k; op = fcm_op(), kw...) =
    Array(getproperty(solve(PottsProblem(m, op, (0, k); seed = 1, kw...), SequentialCPM()).u[end].site, field))

fc_msg(f) = try
    f()
    "built"
catch e
    e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
end


# F4-11 review fixups: names the model has already are refused (they were appended: a host
# `kd = 0.9` and a PDESystem `kd = 0.5` gave the parameters [kd, Dd, kd], and one field read
# the wrong kd); the initial value from a start condition `u(0, x, y) ~ v`; a condition at
# another fixed time, `Pair` parameters, a time that is not the first variable and a CPM word
# a site does not read are refused at compose, naming the PDESystem.
# Base (a457bf8a, ~/lpwork/f4c/nc11r-base.log): 4 pass, 6 fail (both clashes, the time-5 condition,
# the `Pair`, the time last, `volume`); the start-value cases already held (a test gap).
@potts_model FcHostK begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FcPDE.hostk()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcHostU begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FcPDE.hostu()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcRefIC begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FcPDE.plain([FcPDE.u(0, FcPDE.x, FcPDE.y) ~ 0.7]; name = :fields)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcRefIC2 begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FcPDE.plain([FcPDE.u(0, FcPDE.x, FcPDE.y) ~ 1.4FcPDE.kd]; name = :fields)
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "F4-11: a component that carries a PDESystem composes" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components] begin
    @testset "F4-11: a component that carries a PDESystem composes" begin
        # (before F4-11: "has a PDESystem; a component's fields are not compiled")
        host = FcHost(; name = :m)
        w = Potts.wrap_system(
            :drug, FcPDE.System(FcPDE.Equation[], FcPDE.t; name = :drug), FcPDE.drug((12, 10)),
            Potts.part(Potts.component(:zz, FcPDE.zz(), host)))
        e = fc_msg(() -> fc_run(compose(host, w), :drug₊u, 3))
        @test e == "built" || (println(e); false)
    end
end

@testitem "F4-11: a PDESystem component equals the coupled field (bitwise, σ frozen)" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components] begin
    @testset "F4-11: a PDESystem component equals the coupled field (bitwise, σ frozen)" begin
        host = FcHost(; name = :m)
        comp = Potts.component(:drug, FcPDE.drug((12, 10)), host)
        m = compose(host, comp)
        @test any(x -> Potts.info(x).name === :drug₊u, Potts.declared_variables(m))
        @test Set(Potts.info(q).name for q in Potts.declared_parameters(m)) == Set([:drug₊Dd, :drug₊kd])
        ref = FcRef(; name = :m)
        for fs in (ExplicitEuler(), BackwardEuler())
            a = fc_run(m, :drug₊u, 6; field_solver = fs)
            b = fc_run(ref, :u, 6; field_solver = fs)
            @test a == b && maximum(a) > 0.5 && sum(a) > 0
        end
        # its fields by name in a `FieldGroups` pair, and its parameters in the operating point
        a = fc_run(m, :drug₊u, 4; op = [fcm_op(); :drug₊Dd => 0.4], field_solver = FieldGroups(:drug₊u => BackwardEuler()))
        b = fc_run(ref, :u, 4; op = [fcm_op(); :Dd => 0.4], field_solver = FieldGroups(:u => BackwardEuler()))
        @test a == b
        @test a != fc_run(ref, :u, 4; field_solver = BackwardEuler())          # (the write took effect)
        # the composed model's PDESystem is the reference's, under the component's names
        @test length(getfield(Potts.fields(m), :eqs)) == 1 && length(getfield(Potts.fields(m), :bcs)) == 1
        # a model wrapped with its own PDESystem compiles it under its own names (the refusal of a
        # PDESystem its payload does not build is gone)
        hw = Potts.wrap_system(:m, Potts.inner(host), FcPDE.drug((12, 10); name = :m), Potts.part(host))
        @test fc_run(hw, :u, 6; field_solver = ExplicitEuler()) == fc_run(ref, :u, 6; field_solver = ExplicitEuler())
        # composed with an MTK component in one call, in either order
        m2 = compose(host, Potts.component(:zz, FcPDE.zz(), host), comp)
        sol = solve(PottsProblem(m2, fcm_op(), (0, 3); seed = 1), SequentialCPM())
        @test Array(sol.u[end].site.drug₊u) == fc_run(ref, :u, 3) && sol.u[end].model.zz₊zq[1] < 1
    end
end

@testitem "F4-11: the domain is the lattice's, in the model's length unit" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components] begin
    @testset "F4-11: the domain is the lattice's, in the model's length unit" begin
        host, hosth = FcHost(; name = :m), FcHostH(; name = :m)
        # lattice units on a lattice without spacing; dims × spacing on one with spacing
        wide = fc_msg(() -> compose(host, Potts.component(:drug, FcPDE.drug((24, 10)), host)))
        @test occursin("spans `x ∈ [0, 24]`", wide) && occursin("spans [0, 12]", wide) && occursin("drug", wide)
        a = fc_run(compose(hosth, Potts.component(:drug, FcPDE.drug((6, 5)), hosth)), :drug₊u, 5)
        @test a == fc_run(FcRefH(; name = :m), :u, 5)
        lat = fc_msg(() -> compose(hosth, Potts.component(:drug, FcPDE.drug((12, 10)), hosth)))
        @test occursin("spans `x ∈ [0, 12]`", lat) && occursin("spans [0, 6]", lat) && occursin("spacing 0.5", lat)
    end
end

# F4-B1: `lattice_domain(t, (x, y), dims; spacing)` is the domain the check takes. Negative
# control at 8c3f01cf: `lattice_domain` is not defined (an UndefVarError).
@testitem "F4-B1: lattice_domain passes the component's domain check" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components] begin
    @testset "F4-B1: lattice_domain passes the component's domain check" begin
        hosth = FcHostH(; name = :m)
        T, X, Y = FcPDE.t, FcPDE.x, FcPDE.y
        hand = FcPDE.drug((6, 5))
        with(dom) = FcPDE.PDESystem(getfield(hand, :eqs), getfield(hand, :bcs), dom, getfield(hand, :ivs),
            getfield(hand, :dvs), getfield(hand, :ps); name = :drug)
        a = fc_run(
            compose(
                hosth, Potts.component(
                    :drug, with(
                        Potts.LatticePDE.lattice_domain(
                            T, (X, Y), (12, 10);
            spacing = 0.5)), hosth)), :drug₊u, 5)
        @test a == fc_run(FcRefH(; name = :m), :u, 5)
        # (control: the lattice's sites without its spacing are refused, naming the spacing)
        e = fc_msg(
            () -> compose(
                hosth, Potts.component(
                    :drug, with(
                        Potts.LatticePDE.lattice_domain(
                            T, (X, Y),
            (12, 10))), hosth)))
        @test occursin("spans [0, 6]", e) && occursin("spacing 0.5", e)
    end
end

@testitem "F4-11: inputs by their CPM word; refusals name the PDESystem" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components] begin
    @testset "F4-11: inputs by their CPM word; refusals name the PDESystem" begin
        host = FcHost(; name = :m)
        # an input with no word the CPM fills
        bad = FcPDE.drug((12, 10); dvs = [FcPDE.u(FcPDE.t, FcPDE.x, FcPDE.y), FcPDE.nut(FcPDE.t, FcPDE.x, FcPDE.y)],
            rhs = -FcPDE.kd * FcPDE.u(FcPDE.t, FcPDE.x, FcPDE.y) + FcPDE.nut(FcPDE.t, FcPDE.x, FcPDE.y))
        e = fc_msg(() -> compose(host, Potts.component(:drug, bad, host)))
        @test occursin("`nutrient`", e) && occursin("lattice_input_name = \"kind\"", e)
        # an input with no `lattice_input_name` goes by its own name: `kind`
        T, X, Y, kd = FcPDE.t, FcPDE.x, FcPDE.y, FcPDE.kd
        pk = FcPDE.drug((12, 10); dvs = [FcPDE.u(T, X, Y), FcPDE.kind(T, X, Y)],
            rhs = FcPDE.Dd * Potts.LatticePDE.laplacian(FcPDE.u(T, X, Y)) - kd * FcPDE.u(T, X, Y) + ifelse(FcPDE.kind(T, X, Y) == 1, 1.0, 0.0)
        )
        @test fc_run(compose(host, Potts.component(:drug, pk, host)), :drug₊u, 3) == fc_run(FcRef(; name = :m), :u, 3)
        # the PDESystem's name is the component's (as `Potts.wrap_system`)
        @test !isempty(fc_msg(() -> Potts.component(:other, FcPDE.drug((12, 10)), host)))
        # a component's CPM statements are still refused
        @test occursin(
            "energies", fc_msg(
                () -> compose(
                    host, Potts.wrap_system(
                        :drug,
            FcPDE.System(FcPDE.Equation[], FcPDE.t; name = :drug), FcPDE.drug((12, 10)), Potts.part(host)))))
    end
end

@testitem "F4-11: a PDESystem component on the device agrees with the CPU" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components, :device] begin
    @testset "F4-11: a PDESystem component on the device agrees with the CPU" begin
        if isdefined(@__MODULE__, :PottsDevices) && PottsDevices.on_device() && PottsDevices.device_name() == "rocm"
            backend = PottsDevices.device_backend()
            host = FcHost(; name = :m)
            m = compose(host, Potts.component(:drug, FcPDE.drug((12, 10)), host))
            for fs in (ExplicitEuler(), BackwardEuler())
                prob = PottsProblem(m, fcm_op(), (0, 6); field_solver = fs, T = Float32, seed = 1)
                a = solve(prob, CheckerboardCPM()).u[end].site.drug₊u
                b = solve(prob, CheckerboardCPM(); backend).u[end].site.drug₊u
                @test Array(b) ≈ a rtol = 1e-5
            end
        end
    end
end

@testitem "F4-11 review: names, start values and compose-time refusals" setup = [FieldsComponentsSetup] tags = [:potts, :fields_components] begin
    @testset "F4-11 review: names, start values and compose-time refusals" begin
        T, X, Y, u, kd = FcPDE.t, FcPDE.x, FcPDE.y, FcPDE.u, FcPDE.kd
        host = FcHost(; name = :m)
        # a parameter or field name the model has already (a hand-wrapped PDESystem keeps its names)
        hk, hu = FcHostK(; name = :m), FcHostU(; name = :m)
        pk = fc_msg(() -> Potts.ModelingToolkitBase.mtkcompile(Potts.wrap_system(:m, Potts.inner(hk), FcPDE.plain([u(0, X, Y) ~ 0.7]; name = :m), Potts.part(hk))))
        @test occursin("the PDESystem `m` declares the parameter `kd`", pk) && occursin("a parameter `kd`", pk) &&
              occursin("Potts.component", pk)
        pu = fc_msg(() -> Potts.ModelingToolkitBase.mtkcompile(Potts.wrap_system(:m, Potts.inner(hu), FcPDE.plain([u(0, X, Y) ~ 0.7]; name = :m), Potts.part(hu))))
        @test occursin("the PDESystem `m` declares the field `u`", pu) && occursin("a field `u`", pu)
        # (namespaced as a component, the same PDESystem composes)
        @test fc_msg(() -> compose(hk, Potts.component(:drug, FcPDE.plain([u(0, X, Y) ~ 0.7]), hk))) == "built"
        # the initial value from a start condition, bitwise against the coupled one (before F4-B4t,
        # A's default): a number, a parameter expression, and that expression after an
        # operating-point write
        run(pde, k; op = fcm_op()) = fc_run(compose(host, Potts.component(:drug, pde, host)), :drug₊u, k; op)
        @test run(FcPDE.plain([u(0, X, Y) ~ 0.7]), 3) == fc_run(FcRefIC(; name = :m), :u, 3)
        @test run(FcPDE.plain([u(0, X, Y) ~ 1.4kd]), 3) == fc_run(FcRefIC2(; name = :m), :u, 3)
        a = run(FcPDE.plain([u(0, X, Y) ~ 1.4kd]), 3; op = [fcm_op(); :drug₊kd => 1.0])
        @test a == fc_run(FcRefIC2(; name = :m), :u, 3; op = [fcm_op(); :kd => 1.0]) && a != fc_run(FcRefIC2(; name = :m), :u, 3)
        # a condition at another fixed time
        e = fc_msg(() -> compose(host, Potts.component(:drug, FcPDE.plain([u(5.0, X, Y) ~ 2.0]), host)))
        @test occursin("a value at the time 5.0", e) && occursin("the PDESystem `drug`", e)
        # `Pair` parameters (B's rule)
        e = fc_msg(() -> compose(host, Potts.component(:drug, FcPDE.plain([u(0, X, Y) ~ 0.0]; ps = [FcPDE.Dd => 0.2, kd]), host)))
        @test occursin("is a `Pair`", e) && occursin("the PDESystem `drug`", e)
        # the time is the first independent variable
        e = fc_msg(() -> compose(host, Potts.component(:drug, FcPDE.plain(FcPDE.Equation[]; ivs = [X, Y, T]), host)))
        @test occursin("the time is the first independent variable", e) && occursin("the PDESystem `drug`", e)
        # a cell property is no site word: refused at compose, with the site-variable route
        vol = FcPDE.vol
        pv = FcPDE.drug((12, 10); dvs = [u(T, X, Y), vol(T, X, Y)], rhs = 0.01 * vol(T, X, Y) - kd * u(T, X, Y))
        e = fc_msg(() -> compose(host, Potts.component(:drug, pv, host)))
        @test occursin("`volume`", e) && occursin("@after_mcs s ~ volume[owner]", e)
    end
end
