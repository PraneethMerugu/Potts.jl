# F4-06 (F4 design §3.4, §5): `ContinuousCallback` on the owned path (Q3 (a): the condition at
# each window's end, the event located by linear interpolation, first order in time) and
# ensembles of owned solves. Negative control at the F4-05 commit (~/lpwork/f4b5/nc06.log): a
# `ContinuousCallback` never fires (only the discrete callbacks run); the ensembles <…>.

@testsetup module LP_events
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/callbacks.jl")
include("shared/export_all.jl")
end

@testitem "F4-06: a ContinuousCallback fires within one window of the event, at the interpolated state" setup = [LP_events] tags = [:latticepde, :events] begin
@testset "F4-06: a ContinuousCallback fires within one window of the event, at the interpolated state" begin
    p = cbprob()
    ev, st = Float64[], Vector{Float64}[]
    cb = SciMLBase.ContinuousCallback((u, t, i) -> maximum(u) - 0.5, i -> (push!(ev, i.t); push!(st, copy(i.u))))
    s = solve(p, ExplicitEuler(); dt = 0.01, callback = cb)
    # the reference: a fine run, the crossing of max(c) = 0.5 located between its steps
    f = solve(p, ExplicitEuler(); dt = 1e-4, save_everystep = true)
    g = [maximum(u) - 0.5 for u in f.u]
    k = findfirst(i -> sign(g[i]) != sign(g[i + 1]), 1:(length(g) - 1))
    tref = f.t[k] + g[k] / (g[k] - g[k + 1]) * (f.t[k + 1] - f.t[k])
    @test length(ev) == 1 && abs(ev[1] - tref) < 0.01 || (println("F4-06 event ", ev, " ref ", tref); false)
    e = solve(p, ExplicitEuler(); dt = 0.01, save_everystep = true)
    @test maximum(abs, st[1] .- e(ev[1])) < 1e-13 && ev[1] in s.t && s.t[end] == 1.0
    # a VectorContinuousCallback: the first crossing of each component, its index given
    hits = Int[]
    vc = SciMLBase.VectorContinuousCallback((out, u, t, i) -> (out[1] = maximum(u) - 0.5; out[2] = t - 0.3),
        (i, idx) -> push!(hits, idx), 2)
    solve(p, ExplicitEuler(); dt = 0.01, callback = vc)
    @test sort(hits) == [1, 2]
end
end

@testitem "F4-06: ensembles of owned solves equal the serial solves bitwise" setup = [LP_events] tags = [:latticepde, :events] begin
@testset "F4-06: ensembles of owned solves equal the serial solves bitwise" begin
    p = cbprob(0.3)
    ep = SciMLBase.EnsembleProblem(p; prob_func = (q, ctx) -> remake(q; p = [bk => 1.0 + ctx.sim_id]))
    alg = BackwardEuler(; linsolve = BTIGHT)
    ref = [solve(remake(p; p = [bk => 1.0 + i]), alg; dt = 0.01).u[end] for i in 1:4]
    for ea in (SciMLBase.EnsembleSerial(), SciMLBase.EnsembleThreads())
        es = solve(ep, alg, ea; dt = 0.01, trajectories = 4)
        @test all(i -> es.u[i].u[end] == ref[i] && es.u[i].ps[bk] == 1.0 + i, 1:4)
    end
end
end
