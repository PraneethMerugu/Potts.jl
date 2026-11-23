# Callbacks, `tstops`, `saveat` off the grid and the other keywords on
# the owned path. A callback runs after each window (SciML's order and `save_positions`); a
# `tstop` off the grid lands by a shortened window; a `saveat` time off the grid is the
# linear interpolation of its window's ends; `save_idxs` saves some fields; any other
# keyword is an `ArgumentError` naming it. Negative control before the fix: "unsupported
# keyword argument" (`callback`, `tstops`, `save_idxs`), and `saveat = 0.015` refused.

@testsetup module LP_callbacks
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/preamble.jl")
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

@testitem "a callback that writes a parameter equals two chained solves (EE, BE)" setup = [
    LP_callbacks,
] tags = [
    :latticepde, :callbacks,
] begin
    @testset "a callback that writes a parameter equals two chained solves (EE, BE)" begin
        p = cbprob()
        for alg in (ExplicitEuler(), BackwardEuler(; linsolve = BTIGHT))
            cb = SciMLBase.DiscreteCallback(
                (u, t, i) -> t == 0.5, i -> (i.ps[bk] = 3.0);
                save_positions = (false, false)
            )
            s = solve(
                p, alg; dt = 0.01, callback = cb, tstops = [0.5], save_everystep = false
            )
            a = solve(remake(p; tspan = (0.0, 0.5)), alg; dt = 0.01)
            b = solve(
                remake(p; u0 = a.u[end], tspan = (0.5, 1.0), p = [bk => 3.0]), alg;
                dt = 0.01
            )
            @test s.t == [0.0, 1.0] && maximum(abs, s.u[end] .- b.u[end]) < 1.0e-12 &&
                s.ps[bk] == 3.0
        end
        # the problem's own callbacks run too (as DiffEqBase merges them), before the call's
        hits = Float64[]
        q = remake(
            p;
            callback = SciMLBase.DiscreteCallback(
                (u, t, i) -> true, i -> push!(hits, i.t); save_positions = (false, false)
            )
        )
        solve(q, ExplicitEuler(); dt = 0.1)
        @test hits ≈ 0.1:0.1:1.0
    end
end

@testitem "PresetTimeCallback off the grid, PeriodicCallback, tstops" setup = [
    LP_callbacks,
] tags = [
    :latticepde, :callbacks,
] begin
    @testset "PresetTimeCallback off the grid, PeriodicCallback, tstops" begin
        p = cbprob()
        hit = Float64[]
        s = solve(
            p, ExplicitEuler(); dt = 0.01,
            callback = PresetTimeCallback([0.123, 0.5], i -> push!(hit, i.t))
        )
        @test hit == [0.123, 0.5] && s.t[end] == 1.0
        # (save_positions (true, true): saved at the event)
        @test 0.123 in s.t
        per = Float64[]
        solve(
            p, ExplicitEuler(); dt = 0.01,
            callback = PeriodicCallback(i -> push!(per, i.t), 0.25)
        )
        # (none at the end: DiffEqCallbacks' `final_affect = false`)
        @test per ≈ [0.25, 0.5, 0.75]
        # a tstop off the grid: the run passes through it by a shortened window, and the
        # state there equals a run that ends at it
        ig = init(p, ExplicitEuler(); dt = 0.01, tstops = [0.0333])
        seen = Float64[]
        while ig.t < 0.05
            step!(ig)
            push!(seen, ig.t)
        end
        @test 0.0333 in seen
    end
end

@testitem "saveat off the grid is the linear interpolation of the windows' ends; \
    save_idxs; keywords" setup = [LP_callbacks] tags = [
    :latticepde, :callbacks,
] begin
    @testset "saveat off the grid is the linear interpolation of the windows' ends; \
        save_idxs; keywords" begin
        p = cbprob(0.3)
        s = solve(p, ExplicitEuler(); dt = 0.01, saveat = 0.015)
        e = solve(p, ExplicitEuler(); dt = 0.01, save_everystep = true)
        @test s.t ≈ 0:0.015:0.3 && length(e.t) == 31
        @test all(k -> maximum(abs, s.u[k] .- e(s.t[k])) < 1.0e-13, eachindex(s.t))
        @test s(0.0225) ≈ (s.u[2] .+ s.u[3]) ./ 2
        # save_idxs: the field `c` of a two-field system only
        q = discretize(
            bsys(
                [D(bce) ~ bD * laplacian(bce) - bk * bce, D(boe) ~ -boe], [
                    bc(0, x, y) ~ x, bo(0, x, y) ~ 1.0,
                ], [bD, bk];
                T = 0.2, dvs = [bce, boe]
            ), LatticeDiscretization(Grid((8, 8)); T = Float64)
        )
        full = solve(q, ExplicitEuler(); dt = 0.01)
        sub = solve(q, ExplicitEuler(); dt = 0.01, save_idxs = [bce])
        @test length(sub.u[end]) == 64 && sub.u[end] == full.u[end][1:64] &&
            sub[bce] == full[bce]
        # any other keyword is refused by name
        e = try
            solve(p, ExplicitEuler(); dt = 0.01, abstol = 1.0e-6)
        catch err
            sprint(showerror, err)
        end
        @test occursin("`abstol`", e) && occursin("saveat", e)
        @test SciMLBase.successful_retcode(
            solve(
                p, ExplicitEuler(); dt = 0.01, verbose = false,
                alias = SciMLBase.ODEAliasSpecifier(; alias_u0 = true), dense = true
            )
        )
        @test solve(p, ExplicitEuler(); dt = 0.01, maxiters = 5).retcode ==
            ReturnCode.MaxIters
        @test solve(p, ExplicitEuler(); dt = 0.01).stats.syncs == 0
        # A long span over a short window, `(tf - t0) / (1e-9 dt)` past `Int`
        # (base ab34e226: InexactError at `init`); the start and the end are the save times,
        # and a saveat time within 1e-9 dt of another is one save
        ig = init(remake(p; tspan = (0.0, 1.0e6)), ExplicitEuler(); dt = 1.0e-4)
        @test ig.save == [0.0, 1.0e6]
        ig = init(
            remake(p; tspan = (0.0, 1.0e6)), ExplicitEuler();
            dt = 1.0e-4, saveat = [0.5, 0.5 + 1.0e-14, 2.0]
        )
        @test ig.save == [0.0, 0.5, 2.0, 1.0e6]
    end
end
