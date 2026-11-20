# A Potts model answers ModelingToolkit's system interface as a plain MTK `System` does, and
# SymbolicIndexingInterface getters built from a model work on what it solves to.

@testsetup module MTKInterfaceSetup
using Test, Potts, PottsModels
using Potts.ModelingToolkitBase: ModelingToolkitBase, System, @variables, @parameters
using Potts.SymbolicIndexingInterface: SymbolicIndexingInterface as SII
include(joinpath(@__DIR__, "shared", "qa_common.jl"))

const M = ModelingToolkitBase

"""A plain MTK `System`: the reference the Potts models are compared with."""
function decay_system(; name)
    @parameters k = 0.5
    @variables y(Potts.t) = 1.0
    return System([Potts.D(y) ~ -k * y], Potts.t; name)
end

"""An MTK `System` that a model composes as a component."""
function clock_system(; name = :clock)
    @variables z(Potts.t) = 0.0
    return System([Potts.D(z) ~ 1.0], Potts.t; name)
end

"""A model whose quantities are named like the fields a compiled model holds."""
@potts_model FieldNamedQuantities begin
    @kinds medium host
    @parameters begin
        sys = 2.0
        footprint = 3.0
        T = 1.0
    end
    @variables drive(cell) = 1.0
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy cells(host) => sys * footprint * (volume - drive)^2
    @sweep Metropolis(; temperature = T)
end

"""A model with MTK's `@description` and `@metadata` sections."""
@potts_model DescribedModel begin
    @description "One cell kind held near a target volume."
    @metadata begin
        MTKInterfaceKey = :described
    end
    @kinds medium host
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy cells(host) => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

"""A name that is not a type, so not a metadata key."""
const MTKInterfaceNotAType = :key

"""A model whose `@metadata` key is not a type."""
@potts_model BadMetadataKey begin
    @metadata begin
        MTKInterfaceNotAType = 1
    end
    @kinds medium host
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy cells(host) => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "MTK's system interface: a plain System, a Potts model and a coupled Potts model" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    @testset "plain System" begin
        qa_mtk_system_interface(decay_system(; name = :decay); rebuild = decay_system, component = clock_system())
    end
    @testset "Potts model" begin
        qa_mtk_system_interface(GranerGlazier(; name = :gg); rebuild = GranerGlazier, component = clock_system())
    end
    @testset "Potts model with fields" begin
        merks(; name) = MerksVasculogenesis(; name, lattice = (8, 8))
        qa_mtk_system_interface(merks(; name = :merks); rebuild = merks, component = clock_system())
    end
    @testset "a system type missing an accessor fails the walk" begin
        qa_mtk_system_interface_control()
    end
end

@testitem "MTK's operations on Potts models: values and refusals" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    gg = GranerGlazier(; name = :gg)
    @test M.independent_variable(gg) === Potts.t || isequal(M.independent_variable(gg), Potts.t)
    @test M.iscomplete(gg) && !M.does_namespacing(gg) && M.complete(gg) === gg
    @test isequal(M.get_iv(gg), Potts.t)
    err = try
        M.complete(gg; split = false)
    catch e
        e
    end
    @test err isa ArgumentError
    # the metadata is the inner System's: the sweep is there, and a value set stays through mtkcompile
    @test M.getmetadata(gg, Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
    tagged = M.setmetadata(gg, MTKInterfaceKey, :tagged)
    @test M.getmetadata(Potts.inner(tagged), MTKInterfaceKey, nothing) === :tagged
    @test M.getmetadata(mtkcompile(tagged), MTKInterfaceKey, nothing) === :tagged
    @test M.getmetadata(gg, MTKInterfaceKey, nothing) === nothing           # `gg` is unchanged
    # a renamed model solves as the original does
    σ, kinds = graner_glazier_state()
    op = [ownership => σ, kind => kinds]
    renamed = M.rename(gg, :other)
    @test nameof(Potts.inner(renamed)) === :other
    @test PottsProblem(renamed, op, (0, 1)).f.fingerprint == PottsProblem(gg, op, (0, 1)).f.fingerprint
    # compose takes an MTK System as it is; a Potts model inside a plain System is refused
    @test :clock₊z in Symbol.(M.getname.(M.unknowns(compose(gg, [clock_system()]))))
    @test compose(gg) === gg
    @test_throws ArgumentError compose(clock_system(), [gg])
    @test_throws ArgumentError compose(clock_system(), gg)
    @test_throws ArgumentError compose(clock_system(), [decay_system(; name = :decay), gg])
    @test_throws ArgumentError M.System(M.Equation[], Potts.t; name = :outer, systems = [gg])
    @test_throws ArgumentError compose(gg, [1.0])
    # extend merges two Potts models; with a plain System, or an MTK keyword, it is refused
    @test_throws ArgumentError extend(gg, decay_system(; name = :decay))
    @test_throws ArgumentError extend(decay_system(; name = :decay), gg)
    @test_throws ArgumentError extend(gg, GranerGlazier(; name = :base); description = "merged")
    # mtkcompile: an MTK system that is complete; MTK's keywords are refused by name
    c = mtkcompile(gg)
    @test c isa CompiledPottsSystem && c isa M.AbstractSystem && M.iscomplete(c)
    @test isequal(M.parameters(c), M.parameters(gg)) && isequal(c.λ, gg.λ)
    @test mtkcompile(c) === c
    @test isequal(M.get_iv(c), Potts.t) && Potts.inner(c) isa M.System && nameof(Potts.inner(c)) === :gg
    # a compiled model is read-only: operations that build a new system name the model route
    for op in (
            () -> M.rename(c, :other), () -> compose(c, [clock_system()]), () -> clock_system() ∘ c,
            () -> M.setmetadata(c, MTKInterfaceKey, 1), () -> M.complete(c; split = false),
        )
        @test_throws ArgumentError op()
    end
    err = try
        mtkcompile(gg; simplify = false)
    catch e
        e
    end
    @test err isa ArgumentError
    # a compiled model is no ODE system either
    @test_throws ArgumentError M.ODEProblem(c, [], (0.0, 1.0))
    @test_throws ArgumentError Potts.SciMLBase.NonlinearProblem(c, [])
end

@testitem "getters and setters built from a model work on its problem, integrator and solution" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    gg = GranerGlazier(; name = :gg)
    c = mtkcompile(gg)
    σ, kinds = graner_glazier_state()
    prob = PottsProblem(gg, [ownership => σ, kind => kinds], (0, 2); seed = 1)
    integ = init(prob, SequentialCPM())
    sol = solve(prob, SequentialCPM())
    for sys in (gg, c)
        getT = SII.getp(sys, gg.T)
        @test getT(prob) == prob.ps[gg.T] == SII.getp(prob, gg.T)(prob)
        @test getT(integ) == integ.ps[gg.T]
        @test getT(sol) == sol.ps[gg.T]
        getvol = SII.getu(sys, Potts.B.volume)
        @test getvol(prob) == SII.getu(prob, Potts.B.volume)(prob)
        @test getvol(integ) == SII.getu(integ, Potts.B.volume)(integ)
        @test getvol(sol) == sol[Potts.B.volume]
        @test getvol(sol, 1) == sol[Potts.B.volume][1]
    end
    # a setter built from the model writes the integrator's parameters, and only those
    SII.setp(gg, gg.T)(integ, 7.0)
    @test integ.ps[gg.T] == 7.0 && prob.ps[gg.T] != 7.0
end

@testitem "parameter values are the inner System's initial conditions" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    value(x) = Potts.SymbolicUtils.unwrap_const(x)
    gg = GranerGlazier(; name = :gg, λ = 3.0)
    @test value(M.initial_conditions(gg)[M.unwrap(gg.λ)]) == 3.0
    @test SII.default_values(gg)[M.unwrap(gg.λ)] == 3.0
    # the default when no keyword overrides it, and the problem's value agrees
    plain = GranerGlazier(; name = :gg)
    σ, kinds = graner_glazier_state()
    prob = PottsProblem(plain, [ownership => σ, kind => kinds], (0, 1))
    @test value(M.initial_conditions(plain)[M.unwrap(plain.λ)]) == prob.ps[plain.λ]
    # a field model's parameters are there too
    merks = MerksVasculogenesis(; name = :merks, lattice = (8, 8))
    @test all(p -> haskey(M.initial_conditions(merks), M.unwrap(p)), M.parameters(merks))
end

@testitem "a compiled model's quantities are found by name, whatever the name" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    m = FieldNamedQuantities(; name = :m)
    c = mtkcompile(m)
    for n in (:sys, :footprint, :drive)
        @test isequal(getproperty(c, n), getproperty(m, n))
        @test M.getname(getproperty(c, n)) === n
    end
    # the compiled model still runs
    σ = zeros(Int32, 8, 8)
    σ[3:5, 3:5] .= 1
    prob = PottsProblem(c, [ownership => σ, kind => [:host]], (0, 2))
    @test prob.ps[c.sys] == 2.0 && prob.ps[c.footprint] == 3.0
    @test solve(prob, SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
end

@testitem "`@description` and `@metadata` set MTK's description and metadata" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    m = DescribedModel(; name = :m)
    @test M.description(m) == "One cell kind held near a target volume."
    @test M.getmetadata(m, MTKInterfaceKey, nothing) === :described
    @test M.description(FieldNamedQuantities(; name = :q)) == ""
    @test M.description(mtkcompile(m)) == M.description(m)
    @test_throws ArgumentError BadMetadataKey(; name = :b)
    # the model still runs
    σ = zeros(Int32, 8, 8)
    σ[3:5, 3:5] .= 1
    prob = PottsProblem(m, [ownership => σ, kind => [:host]], (0, 2))
    @test solve(prob, SequentialCPM()).retcode == Potts.SciMLBase.ReturnCode.Success
    @test_throws ArgumentError macroexpand(
        @__MODULE__, :(
            @potts_model BadDescription begin
                @description "a" "b"
                @kinds medium host
            end
        )
    )
end

@testitem "models, problems, integrators and states show in one line and name the lattice" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    m = DescribedModel(; name = :m)
    σ = zeros(Int32, 8, 8)
    σ[3:5, 3:5] .= 1
    prob = PottsProblem(m, [ownership => σ, kind => [:host]], (0, 2))
    integ = init(prob, SequentialCPM())
    for x in (m, mtkcompile(m), prob, integ, prob.u0)
        line = sprint(show, x)
        @test !occursin('\n', line) && length(line) < 200
        @test occursin("8×8", line)
        @test occursin("8×8", sprint(show, MIME"text/plain"(), x))
    end
    @test length(sprint(show, MIME"text/plain"(), prob)) < 400
    @test length(sprint(show, MIME"text/plain"(), integ)) < 400
    @test occursin("cell slot", sprint(show, prob.u0))
    # a seed past `typemax(Int)` shows as it is
    big = PottsProblem(m, [ownership => σ, kind => [:host]], (0, 2); seed = typemax(UInt64))
    @test occursin(string(typemax(UInt64)), sprint(show, MIME"text/plain"(), big))
end

@testitem "JumpProblem of a Potts model is refused for MTK's argument shapes" setup = [MTKInterfaceSetup] tags = [:potts, :mtk_interface] begin
    J = Potts.JumpProcesses.JumpProblem
    m = DescribedModel(; name = :m)
    σ = zeros(Int32, 8, 8)
    for sys in (m, mtkcompile(m))
        for args in (
                ([ownership => σ], (0, 2)), ([ownership => σ], nothing), ([ownership => σ], [0, 2]),
                (Dict(ownership => σ), (0, 2)), ([ownership => σ],), (ownership => σ,), (nothing,), (1.0,),
            )
            @test_throws ArgumentError J(sys, args...)
        end
    end
end
