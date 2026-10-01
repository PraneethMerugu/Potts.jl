# Discrete components with and without full ModelingToolkit loaded (P6.0k, gap G1). Loading
# ModelingToolkit replaces MTKBase's `mtkcompile` for the whole session, so test/potts.jl runs
# this file in two fresh processes, `julia mtk_extension.jl mtk` and `julia mtk_extension.jl`,
# and compares what they print: the generated tick code and a short trajectory.
const WITH_MTK = get(ARGS, 1, "") == "mtk"
if WITH_MTK
    using ModelingToolkit: ModelingToolkit
end
using Potts, Test
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables, @parameters

const t = Potts.t
@variables A(t)::Bool = false B(t)::Bool = false C(t)::Bool = false z(t) = 1.0
@parameters wnt::Bool = false

function network(k; ordered = false)
    return System(
        [A(k) ~ wnt | (B(k - 1) & !C(k - 1)), B(k) ~ A(k - 1),
            C(k) ~ (ordered ? !(A(k) | B(k - 1)) : !(A(k - 1) | B(k - 1)))],
        t;
        name = :grn)
end
const NETWORKS = (
    "jacobi" => network(ShiftIndex(t, 0)),
    "ordered" => network(ShiftIndex(t, 0); ordered = true),
    "clock2" => network(ShiftIndex(Clock(2.0))),
    "lag2" => System(
        [z(ShiftIndex(Clock(1.0))) ~
         z(ShiftIndex(Clock(1.0)) - 1) + z(ShiftIndex(Clock(1.0)) - 2)],
        t;
        name = :grn)
)
const SYSTEM = Ref{Any}(nothing)

function model(sys)
    SYSTEM[] = sys
    @potts_model MTKExtNetwork begin
        @kinds medium host
        @variables input(cell) = 0.0
        @components cells(host) grn = SYSTEM[]
        @lattice Lattice((16, 16))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    return MTKExtNetwork(; name = :net)
end

canonical(exs) = join((string(Base.remove_linenums!(deepcopy(ex))) for ex in exs), "\n")

@testset "discrete components ($(WITH_MTK ? "full ModelingToolkit" : "ModelingToolkitBase"))" begin
    ext = Base.get_extension(Potts, :PottsModelingToolkitExt)
    @test (ext !== nothing) == WITH_MTK
    if WITH_MTK
        @test ext.check_compatible() === nothing           # the MTK hook is present
        # the gap the extension closes: full MTK's own compiler rejects a clocked system
        @test_throws ModelingToolkit.HybridSystemNotSupportedException Potts.ModelingToolkitBase.mtkcompile(last(NETWORKS[3]))
    end
    σ = zeros(Int32, 16, 16)
    σ[2:4, 2:4] .= 1
    σ[8:10, 8:10] .= 2
    for (label, sys) in NETWORKS
        m = model(sys)
        code = canonical(Potts.generated_code(m; T = Float32).phases)
        op = Pair{Any, Any}[ownership => σ, kind => [1, 1]]
        label == "lag2" ? push!(op, Symbol("grn₊zₜ₋₁") => 0.0) :
        push!(op, Symbol("grn₊B") => [true, false])
        sol = solve(PottsProblem(m, op, (0, 6)), SequentialCPM(); saveat = 0:6)
        slots = sort!(filter(n -> startswith(string(n), "grn₊"), collect(propertynames(sol.u[1].cell))))
        traj = [Tuple(getproperty(u.cell, n)[1] for n in slots) for u in sol.u]
        println("P60K|", label, "|", slots, "|", hash(code), "|", traj)
    end
end

# P6.0k2 F4: `_compile_discrete` turns ModelingToolkit's compile errors into `ArgumentError`s
# naming the component, but an error raised in Potts' own code (a Potts bug, e.g. in the
# extension's pass, which MTK calls) propagates unchanged
@testset "discrete compile errors: MTK's relabelled, Potts' own propagate ($(WITH_MTK ? "full ModelingToolkit" : "ModelingToolkitBase"))" begin
    comp = Potts.ComponentSpec(:grn, last(NETWORKS[1]), :model)
    # an MTK failure (an unknown with no update) names the component
    @variables X(t)::Bool = false Y(t)::Bool = false
    bad = Potts.ComponentSpec(:grn, System([X(ShiftIndex(t, 0)) ~ Y(ShiftIndex(t, 0) - 1)], t; name = :grn), :model)
    err = try
        Potts._compile_discrete(bad); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("component `grn`", sprint(showerror, err))
    # a non-Potts error raised inside the compile call: relabelled
    err = try
        Potts._mtk_compile_call(sys -> throw(DomainError(sys, "outside Potts")), comp); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("ModelingToolkit cannot compile", sprint(showerror, err))
    # a Potts internal broken on purpose (a MethodError raised in components.jl): unchanged
    err = try
        Potts._mtk_compile_call(sys -> Potts._clock_cadence(comp, nothing, Any[], 1.0), comp); nothing
    catch e
        e
    end
    @test err isa MethodError
    err = try
        Potts._mtk_compile_call(sys -> Potts._discrete_plan(comp, nothing, 1.0), comp); nothing
    catch e
        e
    end
    @test err isa MethodError
    if WITH_MTK
        # the extension's pass, called by MTK's compile of a clocked system (`Clock(2)`: MTK
        # partitions it and calls the pass), broken on purpose (no system to re-enter)
        ext = Base.get_extension(Potts, :PottsModelingToolkitExt)
        clocked = Potts.ComponentSpec(:grn, last(NETWORKS[3]), :model)
        @test Potts._mtk_compile_call(ext.compile_discrete, clocked) !== nothing      # control: intact pass
        broken(sys) = Potts.ModelingToolkitBase.mtkcompile(sys; additional_passes = Any[ext.PottsDiscretePass(nothing)])
        err = try
            Potts._mtk_compile_call(broken, clocked); nothing
        catch e
            e
        end
        @test err isa MethodError
    end
end
