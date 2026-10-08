# Discrete components with and without full ModelingToolkit loaded (P6.0k, gap G1). Loading
# ModelingToolkit replaces MTKBase's `mtkcompile` for the whole session, so test/potts.jl runs
# this file in two fresh processes, `julia mtk_extension.jl mtk` and `julia mtk_extension.jl`,
# and compares what they print: the generated tick code and a short trajectory.
const WITH_MTK = get(ARGS, 1, "") == "mtk"
if WITH_MTK
    using ModelingToolkit: ModelingToolkit
end
using Potts, Test, Statistics
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

@testset "P6.0k2 review: stdlib frames are not Potts', brownians are rejected" begin
    # a stdlib frame (recorded under the build machine's path) is not Potts code
    bt = try
        Statistics.quantile([1.0], 2.0)
    catch
        catch_backtrace()
    end
    @test !Potts._raised_in_potts(bt)
    @variables y(Potts.t) = 1.0
    @parameters k = 0.3
    Potts.ModelingToolkitBase.@brownians B
    noisy = System([Potts.D(y) ~ -k * y + 5.0 * B], Potts.t; name = :noisy)
    err = try
        Potts._reject_ignored_features(Potts.ComponentSpec(:noisy, noisy, :model)); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("brownians", err.msg)
end

# Algebraic equations in `@equations` (P6.0bn): what is accepted, the generated code and the
# trajectories are the same whether or not full ModelingToolkit (with tearing, which solves
# implicit linear equations itself) is loaded
@potts_model MTKExtAlgebraic begin
    @kinds medium A
    @parameters begin
        k = 0.1
        r = 0.2
    end
    @variables begin
        x(cell) = 2.0
        xalias(cell) = 0.0
        g(cell) = 0.0
        m(model) = 0.0
        gap(model) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -k * xalias + 0.001 * g
        xalias ~ x
        g ~ sum(volume[owner[n]] for n in Moore(1)(42)) - volume
        D(m) ~ r * gap
        gap ~ 1 - m
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model MTKExtImplicit begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        q(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1 * q
        0 ~ q + x - 1.0
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model MTKExtCycle begin
    @kinds medium A
    @variables begin
        x(cell) = 2.0
        p(cell) = 0.0
        q(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -0.1p
        p ~ q + x
        q ~ p - x
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "algebraic equations ($(WITH_MTK ? "full ModelingToolkit" : "ModelingToolkitBase"))" begin
    σ = zeros(Int32, 12, 8)
    σ[3:6, 3:6] .= 1
    σ[7:10, 3:6] .= 2
    m = MTKExtAlgebraic(; name = :alg)
    c = mtkcompile(m)
    names(xs) = sort!([string(Potts.SymbolicIndexingInterface.getname(x)) for x in xs])
    cell = Potts.ode_system(c, :cell)
    @test names(Potts.ModelingToolkitBase.unknowns(cell)) == ["x"]
    code = canonical(Potts.generated_code(m; T = Float64).phases)
    sol = solve(PottsProblem(m, [ownership => σ, kind => [1, 1]], (0, 4)), SequentialCPM(); saveat = 0:4)
    println("P6BN|code|", hash(code), "|", [Tuple(u.cell.x) for u in sol.u], "|", [u.model.m[1] for u in sol.u])
    println("P6BN|observed|", names(o.lhs for o in Potts.ModelingToolkitBase.observed(cell)), "|", sol[:xalias] == sol[:x])
    # positive control: full ModelingToolkit's tearing solves the implicit equation that Potts
    # rejects (so the rejection below is Potts' own); ModelingToolkitBase alone keeps it
    @variables xi(Potts.t) = 2.0 qi(Potts.t)
    plain = Potts.ModelingToolkitBase.mtkcompile(System([Potts.D(xi) ~ -0.1 * qi, 0 ~ qi + xi - 1.0], Potts.t; name = :plain))
    @test ("qi" in names(Potts.ModelingToolkitBase.unknowns(plain))) == !WITH_MTK
    for M in (MTKExtImplicit, MTKExtCycle)
        err = try
            mtkcompile(M(; name = :r)); nothing
        catch e
            e
        end
        @test err isa ArgumentError && occursin("algebraic", sprint(showerror, err))
        println("P6BN|", nameof(M), "|", typeof(err))
    end
end

# Entity-local initialization (P6.0bo, D-170) is strict, so full ModelingToolkit (with its
# tearing and least-squares fallbacks) solves the same conditions to the same values and
# refuses the same under- and overdetermined ones
@potts_model MTKExtInit begin
    @kinds medium A
    @parameters begin
        α = 0.1
        κ = 0.5
    end
    @variables begin
        Vt(cell)
        w(cell) = 1.0
        r(cell), [guess = -1.0]
        a_u(cell)
        b_u(cell)
        xs(cell)
        m(model)
        z(cell)
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(xs) ~ α * volume - κ * xs
    @initialization_equations begin
        Vt ~ 2volume + id + w
        r^2 ~ volume
        a_u + b_u ~ volume
        a_u - b_u ~ id
        D(xs) ~ 0
        m ~ 3κ
        z ~ m + volume
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model MTKExtInitUnder begin
    @kinds medium A
    @variables begin
        alpha_u(cell)
        beta_u(cell)
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @initialization_equations alpha_u + beta_u ~ volume
    @sweep Metropolis(; temperature = 1.0)
end

@testset "initialization ($(WITH_MTK ? "full ModelingToolkit" : "ModelingToolkitBase"))" begin
    σ = zeros(Int32, 12, 8)
    σ[3:6, 3:6] .= 1
    σ[7:10, 3:5] .= 2
    op = [ownership => σ, kind => [1, 1]]
    prob = PottsProblem(MTKExtInit(; name = :init), op, (0, 2))
    vals = Dict(n => round.(Vector{Float64}(Array(getproperty(prob.u0.cell, n))); sigdigits = 10)
                for n in (:Vt, :r, :a_u, :b_u, :xs, :z))
    @test vals[:Vt] == [34.0, 27.0] && vals[:r] == [-4.0, round(-sqrt(12.0); sigdigits = 10)]
    println("P6BO|values|", sort!(collect(vals); by = first), "|", only(Array(prob.u0.model.m)))
    for (M, o) in ((MTKExtInitUnder, op), (MTKExtInit, [op; :Vt => [1.0, 2.0]]))
        err = try
            PottsProblem(M(; name = :r), o, (0, 1)); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        println("P6BO|", nameof(M), "|", err isa ArgumentError && occursin("determined", sprint(showerror, err)))
    end
end
