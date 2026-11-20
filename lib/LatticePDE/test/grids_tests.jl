# Standalone `sol[c]` reads as SciML and coupled Potts read a variable, one grid
# per save, so `sol[c][end]` and `sol[c][i]` are grids; `field_series(sol, c)` is the lazy
# time-first array; `sol[c, i]` and `sol(t; idxs = c)` are grids. An owned solve, an
# OrdinaryDiffEq (Tsit5) solve and a FieldProblem solved directly agree on every spelling.
# `save_idxs` that hold part of a field name it when the field is read; `save_idxs = c` works
# under Tsit5 too. Negative control at 70400aba: `sol[c][end]`
# is a number on the owned and Tsit5 paths, `field_series` refuses a FieldSolution, a FieldSolution
# is not callable, a partial `save_idxs` is a BoundsError, Tsit5 with `save_idxs = c` a MethodError.

@testsetup module LP_grids
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
include("shared/grids.jl")
include("shared/export_all.jl")
end

@testitem "sol[c] is one grid per save on the owned, Tsit5 and FieldProblem paths" setup = [LP_grids] tags = [:latticepde, :grids] begin
    @testset "sol[c] is one grid per save on the owned, Tsit5 and FieldProblem paths" begin
    p = discretize(qsys(), LatticeDiscretization(Grid((6, 4)); T = Float64))
        so = solve(p, ExplicitEuler(); dt = 0.01, saveat = 0.1)
    st = solve(p, Tsit5(); saveat = 0.1, abstol = 1e-10, reltol = 1e-10)
        sf = solve(LFP.field_problem(p), ExplicitEuler(); dt = 0.01, saveat = 0.1)
        @test sf isa SciMLBase.ODESolution && so isa SciMLBase.ODESolution
    for s in (so, st, sf)
        v = s[qce]
        last = reshape(s.u[end], 6, 4)
        @test v isa AbstractVector && length(v) == length(s.t) == 4
        @test v[end] == last && v[2] == reshape(s.u[2], 6, 4)
            @test maximum(s[qce][end]) == maximum(last)          # a grid, not a number
        @test s[qce, 2] == v[2] && s[qce, length(s.t)] == last
        @test s(0.1; idxs = qce) ≈ v[2] && s(0.15; idxs = qce) ≈ (v[2] .+ v[3]) ./ 2
        f = field_series(s, qce)
        @test f isa LFP.FieldSeries && size(f) == (4, 6, 4) && f[end, :, :] == last && f[2, 3, 2] == v[2][3, 2]
        @test s[:qc] == v && s[qc] == v                        # the name and the bare callable
    end
    # the owned and the FieldProblem solutions are the same run
    @test so[qce] == sf[qce] && so.t == sf.t
    @test maximum(abs, so[qce][end] .- st[qce][end]) < 0.01   # (EE against Tsit5)
end
end

@testitem "save_idxs on owned and Tsit5 solves" setup = [LP_grids] tags = [:latticepde, :grids] begin
    @testset "save_idxs on owned and Tsit5 solves" begin
    p = discretize(qsys(), LatticeDiscretization(Grid((6, 4)); T = Float64))
    msg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    # a field saved whole: its grids, on both paths
        for alg in (ExplicitEuler(), Tsit5())
            s = solve(p, alg; dt = 0.01, saveat = 0.1, save_idxs = qce)
        @test length(s.u[1]) == 24 && size(s[qce][end]) == (6, 4) && s[qce][end] == reshape(s.u[end], 6, 4)
    end
    # part of a field: the read names `save_idxs` and the routes
        s = solve(p, ExplicitEuler(); dt = 0.01, saveat = 0.1, save_idxs = [2, 3])
        @test length(s.u[1]) == 2 && occursin("save_idxs", msg(() -> s[qce]))
end
end
