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
