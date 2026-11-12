# MTK-native symbols (field-compiler cutover C3; v3 §5.1, §7.2; D-257 item 5): parameters are
# MTK parameters and kind tables array parameters, built-ins are MTK inputs `x(t)`, every
# model quantity carries its `potts_entity`, table and site reads are LatticePDE's `at`/`at2`,
# and a kind set in `@equations` is `ismember`, never `∈`.


# SciMLStructures on `PottsParameters` (cutover C9; P5 C7a-11, C3/4-1): `Tunable` = the scalar
# parameters, `Constants` = the kind tables; `replace` converts to each entry's type and refuses
# a Dual by name (CPM parameters are plain numbers), never promoting.



# F2-14 (F2 design §2.11, FE-18): `@parameters` takes MTK's metadata. `tunable = false` moves a
# parameter from `SciMLStructures.Tunable` to `Constants`; `bounds = (lo, hi)` is checked at build
# and at every write, atomically, naming the bound; `description` is MTK's and `show` prints it.
# A component's MTK binding `k2 = 2k` is a computed parameter, and an initial value `y => 2k`
# its default. Base (244d58e7): "parameter options: only `unit` is supported" (PO33); component
# bindings and expression initial values refused (PO84, PO85).


# F2-15: no paper model has a computed parameter (Foam's `ω = 2π / 4000` is a number when the
# macro evaluates it), so D-F2-1 changes none of them


# Review of batch 5 (F2-15): a component's computed parameter gives a route that works (M1),
# `integ[β] = v` of a computed β is the read-only message (M3), a discrete binding prints as
# written (S3), and a bound on a computed parameter names the inputs to change (S4)

@testsetup module MTKNativeTests
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))


using Potts, Test

using Potts: LatticePDE

using Potts.ModelingToolkitBase: ModelingToolkitBase as MTKB

using Potts.SymbolicUtils: iscall, operation, arguments

using Potts.Symbolics: Symbolics, unwrap


function mn_error(f)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        return e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
    end
    return nothing
end

mn_build(ex::Expr, M::Symbol) = mn_error(() -> (Core.eval(@__MODULE__, ex);
                                                Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))))

has(msg, parts...) = msg !== nothing && all(p -> occursin(p, msg), parts)

named(xs, n) = only(filter(x -> Potts.info(x).name === n, collect(xs)))


@potts_model MNModel begin
    @kinds medium tip stalk endothelial = (tip, stalk)
    @parameters begin
        λ = 2.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        Dk[kind] = [0.0, 0.5, 0.25]
    end
    @variables q(cell) = 0.0
    @lattice Lattice((12, 12))
    @energy begin
        cells => λ * (volume - 9)^2
        contacts => J[kind, kind′]
    end
    @equations D(q) ~ Dk[kind] - 0.1 * q
    @sweep Metropolis(; temperature = 2.0)
end


# the field rates (F4-B4t): the kind set is the binding of the input `e`
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module MnPDE
using .FieldPDE
@variables c(..) e(..)::Bool [input = true]
const C, E = c(t, x, y), e(t, x, y)
reaction(k) = pdesys([Dt(C) ~ 0.1 * Δ(C) - k * C * E], [c(0, x, y) ~ 0.0], (12, 12), [C, E])
diffusion() = pdesys([Dt(C) ~ 0.1 * E * Δ(C)], [c(0, x, y) ~ 0.0], (12, 12), [C, E])
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testsetup module PottsParametersStructures
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))


using Potts, Test, PottsModels

using SciMLStructures: SciMLStructures as SS

using ForwardDiff: ForwardDiff


@potts_model C9Computed begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = 2λ
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


@potts_model C9Computed3 begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = 3λ
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


module C9ModA
using Potts.Symbolics: Symbolics, @register_symbolic
f(x) = 2x
@register_symbolic f(x)
end

module C9ModB
using Potts.Symbolics: Symbolics, @register_symbolic
f(x) = 3x
@register_symbolic f(x)
end

@potts_model C9FA begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = C9ModA.f(λ)
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end

@potts_model C9FB begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = C9ModB.f(λ)
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end


@potts_model C9Sweep begin
    @structural_parameters begin
        s = 2
    end
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        λ2 = s * λ
    end
    @energy cells => λ2 * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testsetup module F2MetadataParity
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))


using Potts, Test

using SciMLStructures: SciMLStructures as SS

using Potts.ModelingToolkitBase: ModelingToolkitBase as MTKB

using Potts.SymbolicIndexingInterface: getp, setp

@potts_model F2Meta begin
    @kinds medium cell
    @parameters begin
        T = 1.0, [tunable = false]
        λ = 2.0, [bounds = (0, 5), description = "volume strength"]
        V₀ = 9.0
    end
    @energy cells => λ * (volume - V₀)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end

@potts_model F2NoMeta begin
    @kinds medium cell
    @parameters begin
        T = 1.0
        λ = 2.0
        V₀ = 9.0
    end
    @energy cells => λ * (volume - V₀)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = T)
end

emsg(f) = try
    f(); ""
catch e
    e isa ArgumentError || rethrow()
    sprint(showerror, e)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testsetup module F2ComputedPaper
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))


using Potts, Test, PottsModels
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testsetup module F2ComputedReview
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))


using Potts, Test

using Potts.ModelingToolkitBase: ModelingToolkitBase as MTKB

using Potts.SymbolicIndexingInterface: getp, setp

@potts_model F2BoundChain begin
    @kinds medium cell
    @parameters begin
        α = 0.3
        β = 2α
        γ = β + 0.05, [bounds = (0, 1)]
    end
    @energy cells => γ * (volume - 9.0)^2
    @lattice Lattice((12, 12))
    @sweep Metropolis(; temperature = 1.0)
end

emsg(f) = try
    f(); ""
catch e
    e isa ArgumentError || return "not an ArgumentError: " * sprint(showerror, e)
    sprint(showerror, e)
end

function compmodel(sys; scope = :(cells(A)))
    decl = Expr(:macrocall, Symbol("@components"), LineNumberNode(@__LINE__, Symbol(@__FILE__)), scope, :(comp = $sys))
    m = Base.invokelatest(Core.eval, @__MODULE__, quote
        @potts_model F2CompRoute begin
            @kinds medium A
            $decl
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        F2CompRoute(; name = :cr)
    end)
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    return PottsProblem(m, [ownership => σ, kind => [:A]], (0, 2))
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "MTK-native: parameters are MTK parameters, kind tables array parameters" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: parameters are MTK parameters, kind tables array parameters" begin
        sys = MNModel(; name = :mn)
        ps = Potts.parameters(sys)
        @test all(MTKB.isparameter, ps)
        λ, J, Dk = named(ps, :λ), named(ps, :J), named(ps, :Dk)
        @test J isa Symbolics.Arr && size(J) == (3, 3) && size(Dk) == (3,)
        @test !(λ isa Symbolics.Arr)
        @test Potts.info(J).role === :kindtable && Potts.info(λ).role === :param
        # negative control: a variable is not a parameter
        q = named(Potts.variables(sys), :q)
        @test !MTKB.isparameter(q)
        # a kind table's shape is its default's: a scalar default is refused when the model is built
        @test has(mn_build(:(@potts_model MNScalarTable begin
            @kinds medium cell
            @parameters J[kind, kind] = 3.0
            @lattice Lattice((8, 8))
            @energy contacts => J[kind, kind′]
            @sweep Metropolis(; temperature = 1.0)
        end), :MNScalarTable), "kind table `J` takes a vector", "or a matrix")
    end
end

@testitem "MTK-native: potts_entity metadata and input built-ins" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: potts_entity metadata and input built-ins" begin
        sys = MNModel(; name = :mn)
        q = named(Potts.variables(sys), :q)
        e = LatticePDE.get_potts_entity(q)
        @test e isa Potts.Entity && e.role === :cell && e.name === :q
        @test e === Potts.info(q)                        # one record: the metadata key is LatticePDE's
        for n in (:volume, :kind, :kind′, :source, :target, :id)
            b = unwrap(getfield(Potts.B, n))
            @test iscall(b) && isequal(only(arguments(b)), unwrap(Potts.t))      # `volume(t)`
            @test nameof(operation(b)) === n
            @test MTKB.isinput(b)
            @test LatticePDE.get_potts_entity(b) == Potts.Builtin(n)
        end
        # negative controls: parameters and declared variables are not inputs
        @test !any(MTKB.isinput, Potts.parameters(sys))
        @test !MTKB.isinput(q)
        @test LatticePDE.get_potts_entity(Potts.t) === nothing
        # a built-in has no previous value: `Pre(w[new])` keeps `Pre` on `w` only (MTK's `Pre`
        # distributes over the read's arguments and would keep `Pre(new(t))`)
        w = only(MTKB.@variables w(Potts.t))
        isPre(y) = iscall(y) && operation(y) isa MTKB.Pre
        r = unwrap(Potts._pre(Potts.at(w, Potts.B.new)))
        @test operation(r) === LatticePDE.at && isPre(arguments(r)[1]) && isequal(arguments(r)[2], unwrap(Potts.B.new))
        @test isPre(arguments(unwrap(MTKB.Pre(Potts.at(w, Potts.B.new))))[2])     # negative control: MTK's own Pre
    end
end

@testitem "MTK-native: reads are LatticePDE's at/at2" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: reads are LatticePDE's at/at2" begin
        @test Potts.at === LatticePDE.at && Potts.at2 === LatticePDE.at2
        @test parentmodule(Potts.at) === LatticePDE
        sys = MNModel(; name = :mn)
        ops = Any[]
        walk(u) = (u = unwrap(u); iscall(u) && (push!(ops, operation(u)); foreach(walk, arguments(u))))
        foreach(p -> walk(p.second), Potts.hamiltonian(sys))
        @test LatticePDE.at2 in ops
        # the cell ODE reads its kind-table entry through `at` (S-4): its template compiles with the
        # kind as an input, and the rate the problem steps is Dk[kind] - 0.1q
        csys = mtkcompile(sys)
        osys = Potts.ode_system(csys, :cell)
        @test length(MTKB.unknowns(osys)) == 1
        σ = zeros(Int32, 12, 12)
        σ[2:4, 2:4] .= 1
        σ[8:10, 8:10] .= 2
        prob = PottsProblem(sys, [ownership => σ, kind => [:tip, :stalk]], (0, 3))
        sol = solve(prob, SequentialCPM())
        q = sol.u[end].cell.q
        # q' = Dk[kind] - 0.1q from 0: a tip (Dk = 0.5) rises twice as fast as a stalk (0.25)
        @test q[1] > 0 && q[2] > 0 && isapprox(q[1], 2 * q[2]; rtol = 1e-6)
    end
end

@testitem "MTK-native: a kind set in @equations is `ismember`, never `∈` (D-257 item 5)" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: a kind set in @equations is `ismember`, never `∈` (D-257 item 5)" begin
        model(M, eq) = :(@potts_model $M begin
            @kinds medium tip stalk fluid endothelial = (tip, stalk)
            @variables q(cell) = 0.0
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9)^2
            @equations $eq
            @sweep Metropolis(; temperature = 2.0)
        end)
        msg = mn_build(model(:MNIn, :(D(q) ~ 0.25 * (kind ∈ endothelial))), :MNIn)
        @test has(msg, "@equations", "∈", "ismember(kind, endothelial)")
        @test has(mn_build(model(:MNNotIn, :(D(q) ~ 0.25 * (kind ∉ endothelial))), :MNNotIn), "!ismember(kind, endothelial)")
        @test has(mn_build(model(:MNInTuple, :(D(q) ~ 0.25 * (kind ∈ (tip, stalk)))), :MNInTuple), "ismember(kind, (tip, stalk))")
        # controls: `∈` outside @equations builds, and so does the `ismember` form
        @test mn_build(:(@potts_model MNEnergyIn begin
            @kinds medium tip stalk endothelial = (tip, stalk)
            @lattice Lattice((12, 12))
            @energy sites => 1.0 * (kind ∈ endothelial)
            @sweep Metropolis(; temperature = 2.0)
        end), :MNEnergyIn) === nothing
        @test mn_build(model(:MNIsMember, :(D(q) ~ 0.25 * ismember(kind, endothelial))), :MNIsMember) === nothing
        @test mn_build(model(:MNIsMemberTuple, :(D(q) ~ 0.25 * ismember(kind, (tip, stalk)))), :MNIsMemberTuple) === nothing
        @test mn_build(model(:MNSpelled, :(D(q) ~ 0.25 * ((kind == tip) | (kind == stalk)))), :MNSpelled) === nothing
        # `ismember(kind, g)` is the spelled-out `|` of equalities: the same generated code
        code(M) = string(generated_code(Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))).phases)
        @test code(:MNIsMember) == code(:MNSpelled) == code(:MNIsMemberTuple)
        # negative control: another set gives other code
        @test mn_build(model(:MNOther, :(D(q) ~ 0.25 * ismember(kind, (tip, fluid)))), :MNOther) === nothing
        @test code(:MNOther) != code(:MNSpelled)
    end
end

@testitem "MTK-native: `ismember` in a field rate is analysed as its `|` of equalities" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: `ismember` in a field rate is analysed as its `|` of equalities" begin
        # host-side analysis (the stable substep count, ∂f/∂x) reads the spelled-out form: an opaque
        # `ismember` term would bound nothing (a reaction bound of 0, or a refused diffusion bound)
        fieldmodel(M, sys, bind) = :(@potts_model $M begin
            @kinds medium tip stalk endothelial = (tip, stalk)
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9)^2
            @fields $sys (MnPDE.e => $bind)
            @sweep Metropolis(; temperature = 2.0)
        end)
        code(M) = (g = generated_code(Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m)); field_solver = ExplicitEuler(substeps = 2));
                   string(Base.remove_linenums!(deepcopy(Any[g.delta_H, g.commit!, g.phases...]))))
        im, sp = :(ismember(kind, endothelial)), :((kind == tip) | (kind == stalk))
        for (tag, sys) in (("reaction", :(MnPDE.reaction(0.3))), ("diffusion", :(MnPDE.diffusion())))
            A, Bm = Symbol(:MNField_im_, tag), Symbol(:MNField_sp_, tag)
            @test mn_build(fieldmodel(A, sys, im), A) === nothing
            @test mn_build(fieldmodel(Bm, sys, sp), Bm) === nothing
            @test code(A) == code(Bm)
        end
        # negative control: another reaction rate changes the code (the comparison can fail)
        @test mn_build(fieldmodel(:MNField_other, :(MnPDE.reaction(0.6)), im), :MNField_other) === nothing
        @test code(:MNField_other) != code(:MNField_sp_reaction)
    end
end

@testitem "MTK-native: descriptions and errors name built-ins as written" setup = [MTKNativeTests] tags = [:potts, :mtk_native] begin
    @testset "MTK-native: descriptions and errors name built-ins as written" begin
        @test Potts._describe(Potts.divide(Potts.cells(1); when = Potts.B.volume >= 4)) == "@divide cells(1) when = volume >= 4"
        @test Potts._builtin_text("kind′(t) == 0 and cluster_volume(t) and x(t)") == "kind′ == 0 and cluster_volume and x(t)"
    end
end

@testitem "SciMLStructures on PottsParameters" setup = [PottsParametersStructures] tags = [:potts, :mtk_native] begin
    @testset "SciMLStructures on PottsParameters" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1; σ[7:10, 7:10] .= 2
        prob = PottsProblem(GranerGlazier(; name = :gg, lattice = (12, 12)), [ownership => σ, kind => [1, 2]], (0, 2))
        p = prob.p
        @test p isa Potts.PottsParameters
        @test SS.isscimlstructure(p) && !SS.ismutablescimlstructure(p)
        @test SS.hasportion(SS.Tunable(), p) && SS.hasportion(SS.Constants(), p) && !SS.hasportion(SS.Caches(), p)
        nt = NamedTuple(p)
        scal = [k for k in keys(nt) if nt[k] isa Number]
        tabs = [k for k in keys(nt) if !(nt[k] isa Number)]
        @test !isempty(scal) && !isempty(tabs)
        v, repack, alias = SS.canonicalize(SS.Tunable(), p)
        @test !alias && v == [Float64(nt[k]) for k in scal]
        @test repack(v) == p && typeof(repack(v)) === typeof(p)                     # round trip, same type
        w = 2 .* v
        q = SS.replace(SS.Tunable(), p, w)
        @test typeof(q) === typeof(p) && [getproperty(q, k) for k in scal] == w
        @test all(getproperty(q, k) == getproperty(p, k) for k in tabs)              # tables untouched
        c, crepack, _ = SS.canonicalize(SS.Constants(), p)
        @test length(c) == sum(length(nt[k]) for k in tabs)
        @test crepack(c) == p
        @test_throws ArgumentError SS.replace(SS.Tunable(), p, w[1:end-1])          # wrong length
        # a Dual is refused by name, never promoted (P5 C3/4-1)
        d = ForwardDiff.Dual.(v, 1.0)
        e = try
            SS.replace(SS.Tunable(), p, d)
        catch err
            err
        end
        @test e isa ArgumentError && occursin("no Duals", sprint(showerror, e))
        @test SS.canonicalize(SS.Caches(), p) === (nothing, nothing, nothing)        # absent portions
        @test SS.canonicalize(SS.Discrete(), p) === (nothing, nothing, nothing)
        # remake with the replaced object (same type): the values are taken, the tables checked
        r = Potts.SciMLBase.remake(prob; p = q)
        @test typeof(r.p) === typeof(p) && [getproperty(r.p, k) for k in scal] == w
        @test Symbol(solve(r, SequentialCPM()).retcode) === :Success
        # an asymmetric contact table through `Constants` is refused when it enters the problem
        asym = collect(Float64, c)
        asym[2] += 1.0                                       # J[2, 1] ≠ J[1, 2]
        @test_throws ArgumentError Potts.SciMLBase.remake(prob; p = crepack(asym))
    end
end

@testitem "SciMLStructures: computed parameters are re-derived by replace; remake takes an object as given" setup = [PottsParametersStructures] tags = [:potts, :mtk_native] begin
    @testset "SciMLStructures: computed parameters are re-derived by replace; remake takes an object as given" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1
        prob = PottsProblem(C9Computed(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        p = prob.p
        v, repack, _ = SS.canonicalize(SS.Tunable(), p)
        @test v == [1.0, 2.0]                                # T, λ; not the computed λ2
        q = repack([1.0, 3.0])
        @test q.λ == 3.0 && q.λ2 == 6.0                      # replace re-derives λ2 = 2λ
        @test SS.replace(SS.Tunable(), p, [1.0, 3.0]) == q
        r = Potts.SciMLBase.remake(prob; p = q)
        @test r.p == q && typeof(r.p) === typeof(p)
        # D-F2-1 (amends D-115): an object gives its base values and λ2 is derived again; a
        # checkpoint restores bitwise, and a hand-edited λ2 = 7 gets the consistent 6 (no silent mix)
        ck = Potts.SciMLBase.remake(prob; p = [:λ => 3.0]).p
        @test ck.λ == 3.0 && ck.λ2 == 6.0
        @test Potts.SciMLBase.remake(prob; p = ck).p === ck
        hand = Potts._with_values(ck, merge(NamedTuple(ck), (λ2 = 7.0,)))
        @test Potts.SciMLBase.remake(prob; p = hand).p.λ2 == 6.0
        @test_throws ArgumentError Potts.SciMLBase.remake(prob; p = [:λ => 3.0, :λ2 => 7.0])
        # a Float32 problem: a Float64 vector repacks like a Float32 one; an object of the Float64
        # problem is taken as given, converted (different-type path), the same as same-type
        p32 = PottsProblem(C9Computed(; name = :c), [ownership => σ, kind => [1]], (0, 2); T = Float32)
        _, repack32, _ = SS.canonicalize(SS.Tunable(), p32.p)
        q1, q2 = repack32([1.0, 3.0]), repack32(Float32[1, 3])
        @test q1 == q2 && typeof(q1) === typeof(q2) === typeof(p32.p) && q1.λ2 === 6.0f0
        @test Potts.SciMLBase.remake(p32; p = q).p == q1
        @test Potts.SciMLBase.remake(p32; p = ck).p.λ2 === 6.0f0
        # entries that are not floats are Constants; an entry that cannot hold a value exactly is a
        # named ArgumentError, not an InexactError; a BigFloat rounds to the entry's type
        pi_ = Potts.PottsParameters((n = 3, x = 1.0))
        @test SS.canonicalize(SS.Tunable(), pi_)[1] == [1.0] && SS.canonicalize(SS.Constants(), pi_)[1] == [3]
        e = try
            SS.replace(SS.Constants(), pi_, [2.5])
        catch err
            err
        end
        @test e isa ArgumentError && occursin("does not convert", sprint(showerror, e))
        @test SS.replace(SS.Tunable(), pi_, [big"0.1"]).x === 0.1
        # models with other defaults (λ2 = 2λ, λ2 = 3λ) have other parameter types (the type carries a
        # fingerprint of the defaults): each `repack` re-derives its own value, whatever else was built
        prob3 = PottsProblem(C9Computed3(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        @test typeof(prob3.p) !== typeof(p)
        @test SS.canonicalize(SS.Tunable(), prob3.p)[2]([1.0, 3.0]).λ2 == 9.0
        @test SS.canonicalize(SS.Tunable(), p)[2]([1.0, 3.0]).λ2 == 6.0
        # remake with the other model's object takes the different-type path: its base values, and
        # λ2 derived by this model's rule (2λ = 4, not the other model's 3λ = 6; D-F2-1)
        rb = Potts.SciMLBase.remake(prob; p = prob3.p)
        @test typeof(rb.p) === typeof(p) && rb.p.λ2 == 4.0 && prob3.p.λ2 == 6.0
        # an object of a type no problem in this process was built with: refused by name
        stray = Potts.PottsParameters((T = 1.0, λ = 2.0, λ2 = 4.0), ((:λ2,), UInt64(0x1234)))
        e = try
            SS.replace(SS.Tunable(), stray, [1.0, 3.0])
        catch err
            err
        end
        @test e isa ArgumentError && occursin("build the problem in this process", sprint(showerror, e))
        # a constructor keyword overriding a non-computed default keeps one type (no recompile)
        @test typeof(PottsProblem(C9Computed(; name = :c, T = 2.0), [ownership => σ, kind => [1]], (0, 2)).p) === typeof(p)
        # the collision guard: one type, other raw computed defaults (forged: B's parameters under A's type)
        ps3 = Potts._p(Potts.ModelingToolkitBase.mtkcompile(C9Computed3(; name = :c)).sys, :parameters)
        e = try
            Potts._register_derivation!(ps3, Float64, p)
        catch err
            err
        end
        @test e isa ArgumentError && occursin("fingerprint collision", sprint(showerror, e))
        # the guard itself: a pair whose fingerprint text is equal but whose values are not `isequal`
        N_ = Potts.Symbolics.Num
        a13, f13 = [(:a, N_(1 // 3))], [(:a, N_(1 / 3))]
        @test Potts._canon_default(a13[1][2]) == Potts._canon_default(f13[1][2])     # alike as text
        @test !Potts._same_defaults(a13, f13)
        @test Potts._same_defaults(a13, [(:a, N_(1 // 3))]) && Potts._same_defaults([(:a, N_(0))], [(:a, N_(0.0))])   # controls
        # two functions named `f` in two modules (2x, 3x): never a silent wrong derivation. Either
        # their types differ and each re-derives its own value, or the second model is refused by name
        pb = PottsProblem(C9FB(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        pa = try
            PottsProblem(C9FA(; name = :c), [ownership => σ, kind => [1]], (0, 2))
        catch err
            err
        end
        rep(q) = SS.canonicalize(SS.Tunable(), q.p)[2]([1.0, 3.0]).λ2
        refused = pa isa ArgumentError && occursin("fingerprint collision", sprint(showerror, pa))
        distinct = pa isa Potts.CorePotts.PottsProblem && typeof(pa.p) !== typeof(pb.p) && rep(pa) == 6.0 && rep(pb) == 9.0
        @info "C9 A.f/B.f" refused distinct (pa isa Exception ? sprint(showerror, pa) : typeof(pa.p).parameters[2]) typeof(pb.p).parameters[2]
        @test refused || distinct
        @test rep(pb) == 9.0                       # the model built first keeps its own derivation either way
        # a structural sweep (λ2 = s·λ with s = 2, then s = 3, in one process)
        for (sv, want) in ((2, 6.0), (3, 9.0))
            ps = PottsProblem(C9Sweep(; name = :sw, s = sv), [ownership => σ, kind => [1]], (0, 2))
            @test SS.canonicalize(SS.Tunable(), ps.p)[2]([1.0, 3.0]).λ2 == want
        end
    end
end

@testitem "F2-14: tunable, bounds, description" setup = [F2MetadataParity] tags = [:potts, :mtk_native] begin
    @testset "F2-14: tunable, bounds, description" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1
        op = [ownership => σ, kind => [1]]
        sys = F2Meta(; name = :m)
        prob = PottsProblem(sys, op, (0, 2))
        # `tunable = false`: T is a constant (control: the model without metadata tunes T)
        @test SS.canonicalize(SS.Tunable(), prob.p)[1] == [2.0, 9.0]
        @test SS.canonicalize(SS.Constants(), prob.p)[1] == [1.0]
        p0 = PottsProblem(F2NoMeta(; name = :m), op, (0, 2)).p
        @test SS.canonicalize(SS.Tunable(), p0)[1] == [1.0, 2.0, 9.0] && typeof(p0) == typeof(Potts.PottsParameters(NamedTuple(p0)))
        # the metadata is MTK's
        λs = only(x for x in MTKB.parameters(sys) if Symbol(x) === :λ)
        Ts = only(x for x in MTKB.parameters(sys) if Symbol(x) === :T)
        @test MTKB.getbounds(λs) == (0, 5) && MTKB.getdescription(λs) == "volume strength" && !MTKB.istunable(Ts)
        @test occursin("λ (\"volume strength\")", sprint(show, MIME"text/plain"(), sys))
        # `bounds`: refused at build, by `remake`, `setp`, `integ.ps`, `replace`; nothing changes
        bound(e) = occursin("parameter `λ` = 7.0 is outside its declared bounds (0, 5)", e)
        @test bound(emsg(() -> PottsProblem(sys, [op; :λ => 7.0], (0, 2))))
        @test bound(emsg(() -> Potts.SciMLBase.remake(prob; p = [:λ => 7.0])))
        integ = init(prob, SequentialCPM())
        @test bound(emsg(() -> setp(integ, :λ)(integ, 7.0))) && getp(integ, :λ)(integ) == 2.0
        @test bound(emsg(() -> (integ.ps[:λ] = 7.0))) && integ.ps[:λ] == 2.0
        @test bound(emsg(() -> setp(integ, [:V₀, :λ])(integ, [4.0, 7.0]))) && integ.ps[:V₀] == 9.0   # a list: none set
        @test bound(emsg(() -> SS.replace(SS.Tunable(), prob.p, [7.0, 9.0])))
        @test occursin("is outside its declared bounds", emsg(() -> F2Meta(; name = :m, λ = -1.0) |> m -> PottsProblem(m, op, (0, 2))))
        integ.ps[:λ] = 5.0                                  # the bound itself is in
        @test integ.ps[:λ] == 5.0
        # options that are not MTK's are named
        @test occursin("option `tunabel`", emsg(() -> Potts._potts_model(:Bad, quote
            @kinds medium cell
            @parameters k = 1.0, [tunabel = false]
        end, @__MODULE__)))
    end
end

@testitem "F2-14: component bindings and initial values of parameters" setup = [F2MetadataParity] tags = [:potts, :mtk_native] begin
    @testset "F2-14: component bindings and initial values of parameters" begin
        t = Potts.t
        σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
        op = [ownership => σ, kind => [:A]]
        function run(sys; stmts = ())
            decl = Expr(:macrocall, Symbol("@components"), LineNumberNode(@__LINE__, Symbol(@__FILE__)), :(cells(A)), :(comp = $sys))
            m = Base.invokelatest(Core.eval, @__MODULE__, quote
                @potts_model BindParity begin
                    @kinds medium A
                    $decl
                    $(stmts...)
                    @lattice Lattice((10, 10))
                    @energy cells => (volume - 9.0)^2
                    @sweep Metropolis(; temperature = 1.0e-6)
                end
                BindParity(; name = :bp)
            end)
            return solve(PottsProblem(m, op, (0, 2)), SequentialCPM())
        end
        MTKB.@parameters k = 0.3
        MTKB.@parameters k2 = 2k
        MTKB.@parameters k3 = 3k2
        MTKB.@variables y(t) = 1.0 z(t) = 2k
        # a bound parameter equals the component written inline (base: refused naming `k2`)
        bound = run(MTKB.System([Potts.D(y) ~ -k2 * y], t, [y], [k, k2]; name = :comp))
        inline = run(MTKB.System([Potts.D(y) ~ -2k * y], t, [y], [k]; name = :comp))
        @test bound.u[end].cell.comp₊y == inline.u[end].cell.comp₊y ≈ [(1 - 0.6)^2]
        # a chain (`k3 = 3k2`), and the model reading `comp.k2`
        chain = run(MTKB.System([Potts.D(y) ~ -k3 * y / 6], t, [y], [k, k2, k3]; name = :comp);
            stmts = (:(@observed ok2(cell) ~ comp.k2),))
        @test chain.u[end].cell.comp₊y ≈ [(1 - 0.3)^2] && Potts.observe(chain, :ok2)[end][1] ≈ 0.6
        # an initial value of parameters (`z(t) = 2k`, base: refused naming `2k`) and the same as
        # `initial_conditions`
        s = run(MTKB.System([Potts.D(z) ~ -k * z], t, [z], [k]; name = :comp))
        @test s.u[1].cell.comp₊z ≈ [0.6] && s.u[end].cell.comp₊z ≈ [0.6 * 0.7^2]
        MTKB.@variables w(t)
        s = run(MTKB.System([Potts.D(w) ~ -k * w], t, [w], [k]; name = :comp, initial_conditions = [w => 2k]))
        @test s.u[1].cell.comp₊w ≈ [0.6]
        # negative control: an initial value that reads an unknown is still refused, naming it
        MTKB.@variables o(t)
        e = try
            run(MTKB.System([o ~ 2y, Potts.D(y) ~ -k * o], t; name = :comp, initial_conditions = [y => 2o]))
            ""
        catch err
            sprint(showerror, err)
        end
        @test occursin("component `comp`", e) && occursin("more than the component's parameters", e)
    end
end

@testitem "F2-15: Foam has no computed parameter" setup = [F2ComputedPaper] tags = [:potts, :mtk_native] begin
    @testset "F2-15: Foam has no computed parameter" begin
        c = Potts.ModelingToolkitBase.mtkcompile(ShearedFoam(; name = :f, lattice = (32, 32)))
        @test isempty(Potts._computed_params(Potts._p(c.sys, :parameters)))
    end
end

@testitem "F2-15 review: routes and messages of computed parameters" setup = [F2ComputedReview] tags = [:potts, :mtk_native] begin
    @testset "F2-15 review: routes and messages of computed parameters" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1
        prob = PottsProblem(F2BoundChain(; name = :b), [ownership => σ, kind => [1]], (0, 2))
        # S4: γ = 2α + 0.05 out of its bound names α (base: "give a value in them, or change `bounds`")
        e = emsg(() -> Potts.SciMLBase.remake(prob; p = [:α => 1.0]))
        @test occursin("parameter `γ` = 2.05 is outside its declared bounds (0, 1): `γ` is computed from `α`", e) &&
              occursin("set `α`", e)
        # M3: a write of a computed parameter through `integ[…]` (base: SII's "Invalid symbol β")
        ig = init(prob, SequentialCPM())
        e = emsg(() -> (ig[:β] = 1.0))
        @test occursin("`β` is computed from `α`", e) && !occursin("Invalid symbol", e)
        @test ig[:β] == 0.6                                           # a computed read is observed
        # M1: a component's bound parameter routes into the component, and the route works
        t = Potts.t
        MTKB.@parameters k = 0.3
        MTKB.@parameters k2 = 2k
        MTKB.@variables y(t) = 1.0
        pb = compmodel(MTKB.System([Potts.D(y) ~ -k2 * y], t, [y], [k, k2]; name = :comp))
        e = emsg(() -> Potts.SciMLBase.remake(pb; p = [:comp₊k2 => 1.0]))
        @test occursin("`comp₊k2` is computed from `comp₊k`", e) && occursin("give `k2` a number in `comp`'s parameters", e)
        MTKB.@parameters k2n = 1.0
        pr = compmodel(MTKB.System([Potts.D(y) ~ -k2n * y], t, [y], [k, k2n]; name = :comp))   # the route followed
        @test getp(Potts.SciMLBase.remake(pr; p = [:comp₊k2n => 0.5]), :comp₊k2n)(Potts.SciMLBase.remake(pr; p = [:comp₊k2n => 0.5])) == 0.5
        # S3: a discrete binding prints as written (base: `!Potts._nonzero(comp₊s)`)
        kk = MTKB.ShiftIndex(t, 0)
        MTKB.@parameters s::Bool = false
        MTKB.@parameters s2::Bool = !s
        MTKB.@variables X(t)::Bool = false
        pd = compmodel(MTKB.System([X(kk) ~ s2], t; name = :comp))
        e = emsg(() -> Potts.SciMLBase.remake(pd; p = [:comp₊s2 => true]))
        @test occursin("`comp₊s2 = !comp₊s`", e) && !occursin("_nonzero", e)
    end
end
