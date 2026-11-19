# `PottsProblem(…; discretization)`: the fields of a model under any SciML discretization.
# A `LatticeDiscretization` of the model's lattice is the fused lattice path itself (the run
# equals the default); any other steps `discretize(Potts.fields(model), d; inputs)` over each MCS
# window. Oracle: a reference finite-difference discretizer written here (five-point Laplacian,
# zero flux at the closed edges, as the lattice fields), solved by Tsit5, gives the same field
# statistics as the default run by a paired TOST over seeds. The chemotaxis drive reads the
# field, so the two runs share the CPM path only until the solvers' rounding differs.

@testsetup module RefFDSetup
using Potts: Potts
using SciMLBase: SciMLBase
const SII = Potts.SymbolicIndexingInterface

# A reference discretization of `Dt(c) ~ Dc Δc + s (kind == 1) − kd c` on an `n × m` lattice
# with unit spacing; the CPM input is `kind`
export RefFD
struct RefFD <: SciMLBase.AbstractDiscretization
    dims::NTuple{2, Int}
end

mutable struct RefParams
    Dc::Float64
    s::Float64
    kd::Float64
    kind::Matrix{Int32}
end

# its symbolic index: the field `c` is the whole state, `Dc`, `s`, `kd` and `kind` are parameters
struct RefIndex
    n::Int
end
SII.is_variable(::RefIndex, sym) = sym === :c
SII.variable_index(ix::RefIndex, sym) = sym === :c ? (1:(ix.n)) : nothing
SII.variable_symbols(::RefIndex) = [:c]
SII.is_parameter(::RefIndex, sym) = sym in (:Dc, :s, :kd, :kind)
SII.parameter_index(::RefIndex, sym) = sym in (:Dc, :s, :kd, :kind) ? sym : nothing
SII.parameter_symbols(::RefIndex) = [:Dc, :s, :kd, :kind]
SII.is_independent_variable(::RefIndex, sym) = sym === :t
SII.independent_variable_symbols(::RefIndex) = [:t]
SII.is_observed(::RefIndex, sym) = false
SII.is_time_dependent(::RefIndex) = true
SII.constant_structure(::RefIndex) = true
SII.all_variable_symbols(ix::RefIndex) = SII.variable_symbols(ix)
SII.all_symbols(ix::RefIndex) = [:c, :Dc, :s, :kd, :kind, :t]
SII.default_values(::RefIndex) = Dict()
SII.parameter_values(p::RefParams, i::Symbol) = getfield(p, i)
SII.set_parameter!(p::RefParams, v, i::Symbol) = (i === :kind ? copyto!(p.kind, v) : setfield!(p, i, Float64(v)); v)

function rhs!(du, u, p::RefParams, t)
    c, dc = reshape(u, size(p.kind)), reshape(du, size(p.kind))
    n, m = size(c)
    @inbounds for j in 1:m, i in 1:n
        x = c[i, j]
        lap = (i > 1 ? c[i - 1, j] : x) + (i < n ? c[i + 1, j] : x) + (j > 1 ? c[i, j - 1] : x) + (j < m ? c[i, j + 1] : x) - 4x
        dc[i, j] = p.Dc * lap + p.s * (p.kind[i, j] == 1) - p.kd * x
    end
    return nothing
end

function SciMLBase.discretize(::Potts.ModelingToolkitBase.PDESystem, d::RefFD; inputs)
    kind = Int32.(Dict(inputs)[:kind])
    size(kind) == d.dims || throw(DimensionMismatch("the input `kind` is $(size(kind)), the grid $(d.dims)"))
    f = SciMLBase.ODEFunction{true}(rhs!; sys = RefIndex(prod(d.dims)))
    return SciMLBase.ODEProblem(f, zeros(prod(d.dims)), (0.0, 1.0), RefParams(0.2, 0.5, 0.1, kind))
end
end

@testitem "discretization: a LatticeDiscretization of the lattice is the default run" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    m = CpSame(; name = :m)
    d = LP.LatticeDiscretization(LP.Grid((24, 20)))
    for fs in (ExplicitEuler(), BackwardEuler())
        @test cp_same(cp_run(m, fs; discretization = d), cp_run(m, fs))
    end
    @test cp_run(m, ExplicitEuler(); discretization = LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float64, clock = 1.0)).u[end].site.c ==
        cp_run(m, ExplicitEuler()).u[end].site.c
    # (control: the field moved)
    @test maximum(cp_run(m, ExplicitEuler()).u[end].site.c) > 0.5
    # what the problem sets is refused, naming the keyword
    for (bad, token) in ((LP.LatticeDiscretization(LP.Grid((20, 24))), "grid"),
                         (LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float32), "T = Float32"),
                         (LP.LatticeDiscretization(LP.Grid((24, 20)); clock = 2.0), "mcs_duration"))
        @test_throws ArgumentError cp_run(m, ExplicitEuler(); discretization = bad)
        @test occursin(token, cp_msg(() -> PottsProblem(m, cp_op(), (0, 1); discretization = bad)))
    end
    @test_throws ArgumentError PottsProblem(CpHost(; name = :m), cp_op(), (0, 1); discretization = d)
    @test_throws ArgumentError PottsProblem(m, cp_op(), (0, 1); discretization = :lattice)
end

@testitem "discretization: a reference finite-difference discretizer gives the default's field statistics" setup = [CoupleSetup, RefFDSetup] tags = [:potts, :fields_couple] begin
    isdefined(@__MODULE__, :stat_accept) || include(joinpath(@__DIR__, "shared", "stats_helpers.jl"))
    m = CpSame(; name = :m)
    d = RefFD((24, 20))
    run(seed, k = 20; kw...) = solve(PottsProblem(m, cp_op(), (0, k); seed, kw...), SequentialCPM())
    ref(seed, k = 20) = run(seed, k; discretization = d, field_solver = Tsit5())
    # the first window, from the same sweep, against the lattice fields at many substeps
    a, b = run(1, 1; field_solver = ExplicitEuler(substeps = 400)).u[end].site.c, ref(1, 1).u[end].site.c
    @test b ≈ a rtol = 5e-3
    @test maximum(b) > 0.1
    # paired over seeds: the mean and the largest field value at MCS 20, against the lattice
    # fields stepped finely in time (the default's one Euler step per MCS has a time error of
    # about 1.6 % in the mean here, which is not the discretization's)
    seeds = 1:24
    stats(sol) = (c = sol.u[end].site.c; (sum(c) / length(c), maximum(c)))
    runs = [(stats(run(s; field_solver = ExplicitEuler(substeps = 50))), stats(ref(s))) for s in seeds]
    for (k, margin) in ((1, 0.01), (2, 0.05))
        diffs = [(r[k] - q[k]) / q[k] for (q, r) in runs]
        res = stat_accept(diffs; margin)
        @test res.pass || (println("discretization TOST statistic $k: ", res); false)
    end
    # remake switches the discretization; the fingerprint follows it
    p = PottsProblem(m, cp_op(), (0, 20); seed = 1, discretization = d, field_solver = Tsit5())
    q = remake(p; discretization = nothing, field_solver = ExplicitEuler())
    @test solve(q, SequentialCPM()).u[end].site.c == run(1).u[end].site.c
    # a discretization takes a SciML algorithm, the fields solved together
    @test_throws ArgumentError PottsProblem(m, cp_op(), (0, 1); discretization = d)
    @test_throws ArgumentError PottsProblem(m, cp_op(), (0, 1); discretization = d, field_solver = Tsit5(), solvers = [:c => ExplicitEuler()])
end
