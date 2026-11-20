# The owned integrator is a `SciMLBase.DEIntegrator`. `integ.t` is the
# current time and `integ.u` the current state; `step!(integ, dt, true)`, `add_tstop!` and the
# end of a time span off the window grid land by one shortened window (each group `⌈n w/dt⌉`
# substeps; an implicit group rebuilds for it, BDF2 starts again); `derivative_discontinuity!`
# drops the groups' history; `terminate!`, `savevalues!`, `done`. Negative control at 25d14c8a:
# every testset errors (`step!(integ, dt, true)` and the methods are
# MethodErrors, `integ.t` is the vector of saved times, a time span off the grid is refused).

@testsetup module LP_integrator
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
include("shared/cranknicolson.jl")
include("shared/export_all.jl")
end

@testitem "integ.t, integ.u and a shortened window, explicit (against a run at dt/2)" setup = [LP_integrator] tags = [:latticepde, :integrator] begin
    @testset "integ.t, integ.u and a shortened window, explicit (against a run at dt/2)" begin
        p, λ, u0 = eig_problem(16)
        ig = init(p, ExplicitEuler(); dt = 0.01)
        @test ig isa SciMLBase.DEIntegrator && ig.t == 0.0 && ig.u ≈ vec(u0) && ig.sol.t == [0.0]
        step!(ig, 0.05, true)
        @test ig.t == 0.05 && ig.iter == 5
        step!(ig, 0.005, true)                        # off the grid: one window of 0.005
        @test ig.t == 0.055 && ig.iter == 5 && ig.windows == 6
        # the counts: 4 substeps of 0.0025 in a window of 0.01, 2 in the shortened one; the run at
        # dt = 0.005 takes 2 of 0.0025 each window, so the two runs take the same substeps
        fine = init(p, ExplicitEuler(); dt = 0.005)
        step!(fine, 0.055, true)
        @test substep_counts(ig) == [4] && substep_counts(fine) == [2]
        @test fine.t == 0.055 && maximum(abs, ig.u .- fine.u) < 1.0e-12
        step!(ig)                                     # back on the grid
        @test ig.t ≈ 0.06 && ig.iter == 6
        step!(fine, 0.005, true)
        @test maximum(abs, ig.u .- fine.u) < 1.0e-12
        # a time span that is not a whole number of windows ends with a shortened window
        s = solve(remake(p; tspan = (0.0, 0.395)), ExplicitEuler(); dt = 0.01, save_everystep = false)
        f = solve(remake(p; tspan = (0.0, 0.395)), ExplicitEuler(); dt = 0.005)
        @test s.t == [0.0, 0.395] && maximum(abs, s.u[end] .- f.u[end]) < 1.0e-12
    end
end

@testitem "a shortened window of Backward Euler equals a chained run; BDF2 keeps order 2" setup = [LP_integrator] tags = [:latticepde, :integrator] begin
    @testset "a shortened window of Backward Euler equals a chained run; BDF2 keeps order 2" begin
        p, λ, u0 = eig_problem(16)
        ib = init(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.01)
        step!(ib, 0.055, true)
        c1 = init(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.01)
        step!(c1, 0.05, true)
        c2 = init(remake(p; u0 = copy(c1.u), tspan = (0.05, 0.4)), BackwardEuler(; linsolve = BTIGHT); dt = 0.005)
        step!(c2)
        @test ib.t == 0.055 && maximum(abs, ib.u .- c2.u) < 1.0e-10
        step!(ib)                                     # a shortened window back to the grid, then full ones
        step!(ib)
        @test ib.t ≈ 0.07 && only(ib.runtimes).cache.h == 0.01
        # BDF2 with one shortened window (a tstop off the grid, then the window back to it): each
        # change of the step starts BDF2 again, and the run keeps order 2
        function err(dt)
            ig = init(p, BDF2(; linsolve = BTIGHT); dt)
            step!(ig, 0.1234, true)
            solve!(ig)
            return maximum(abs, ig.u .- exp(0.3λ * 0.4) .* vec(u0))
        end
        es = [err(0.4 / 2^k) for k in 4:7]
        os = log2.(es[1:(end - 1)] ./ es[2:end])
        @test all(o -> abs(o - 2) < 0.15, os) || (println("BDF2 orders ", os, " ", es); false)
    end
end

@testitem "derivative_discontinuity! re-damps Crank–Nicolson; terminate!, add_tstop!, savevalues!" setup = [LP_integrator] tags = [:latticepde, :integrator] begin
    @testset "derivative_discontinuity! re-damps Crank–Nicolson; terminate!, add_tstop!, savevalues!" begin
        pe, _, _ = eig_problem(16)
        ig = init(pe, CrankNicolson(; linsolve = BTIGHT); dt = 0.05, save_everystep = false)
        step!(ig)
        step!(ig)
        @test !only(ig.runtimes).cache.start
        ig.u .= 0.5 .* ig.u .+ 0.1                    # a write into the state: the groups do not see it …
        @test !only(ig.runtimes).cache.start
        SciMLBase.derivative_discontinuity!(ig, true)  # … until this
        @test only(ig.runtimes).cache.start
        v = copy(ig.u)
        step!(ig)
        fresh = init(remake(pe; u0 = v), CrankNicolson(; linsolve = BTIGHT); dt = 0.05)   # (the heat operator reads no time)
        step!(fresh)
        @test ig.u == fresh.u                         # the damped start, as a fresh run's
        # the other methods
        @test_throws ArgumentError SciMLBase.add_tstop!(ig, 0.1)
        @test (SciMLBase.add_tstop!(ig, 0.3); SciMLBase.has_tstop(ig) && SciMLBase.first_tstop(ig) == 0.3)
        @test SciMLBase.get_proposed_dt(ig) == 0.05
        @test_throws ArgumentError SciMLBase.set_proposed_dt!(ig, 0.01)
        @test SciMLBase.savevalues!(ig) == (true, true) && ig.sol.t[end] == ig.t
        @test !SciMLBase.done(ig)
        SciMLBase.terminate!(ig)
        @test SciMLBase.done(ig) && ig.retcode == ReturnCode.Terminated
        s = solve!(ig)
        @test s.retcode == ReturnCode.Terminated && s.t[end] ≈ 0.15
    end
end
