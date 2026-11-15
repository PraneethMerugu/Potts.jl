# TS2-2: SciML interface conformance across FieldProblem (owned path) and ODEProblem
# (OrdinaryDiffEq path), including callbacks mutating field parameters, reinit!, remake,
# SII state_values/parameter_values/current_time, and negative controls.

@testsetup module LP_sciml_conformance
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
    System, ODEProblem, t_nounits as t, D_nounits as D
using Symbolics: Num
using DomainSets: Interval
using SciMLBase: SciMLBase, solve, solve!, init, step!, reinit!, remake, ReturnCode, DiscreteCallback
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using LatticeFields: LatticeFields, Problems as LFP
using OrdinaryDiffEqTsit5: Tsit5
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
include("shared/export_all.jl")
end

@testitem "TS2-2: LatticePDE SciML conformance on FieldProblem and ODEProblem paths" setup = [LP_sciml_conformance] tags = [:latticepde, :sciml] begin
    @testset "TS2-2: LatticePDE SciML conformance" begin
        @parameters sD = 0.05 sk = 1.0
        @variables sc(..)
        sce = sc(t, x, y)
        sys = PDESystem(
            [D(sce) ~ sD * Δ(sce) - sk * sce],
            [sc(0, x, y) ~ 1.0 + x * y, sc(t, 0, y) ~ 0.0, sc(t, 1, y) ~ 0.0, sc(t, x, 0) ~ 0.0, sc(t, x, 1) ~ 0.0],
            [t ∈ Interval(0.0, 0.4), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
            [t, x, y], [sce], [sD, sk]; name = :sciml_conf
        )
        ode = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64))
        fp = LFP.field_problem(ode)
        @test ode isa SciMLBase.ODEProblem
        @test fp isa LFP.FieldProblem

        @testset "solve vs solve!(init), step!, reinit!, remake on both paths" begin
            for (label, prob, alg, kw) in (
                    ("FieldProblem ExplicitEuler", fp, ExplicitEuler(; dt = 0.02, substeps = 1), (;)),
                    ("FieldProblem BackwardEuler", fp, BackwardEuler(; dt = 0.02, inner = BTIGHT), (;)),
                    ("ODEProblem Tsit5", ode, Tsit5(), (; abstol = 1.0e-10, reltol = 1.0e-10)),
                )
                @testset "$label" begin
                    s1 = solve(prob, alg; saveat = 0.1, kw...)
                    s2 = solve!(init(prob, alg; saveat = 0.1, kw...))
                    @test SciMLBase.successful_retcode(s1)
                    @test s1.t == s2.t && s1.u == s2.u

                    integ = init(prob, alg; kw...)
                    @test SII.current_time(integ) == 0.0
                    @test SII.state_values(integ) == prob.u0
                    step!(integ, 0.15, true)
                    @test isapprox(SII.current_time(integ), 0.15; atol = 1.0e-12)
                    @test SII.state_values(integ) != prob.u0

                    reinit!(integ)
                    @test SII.current_time(integ) == 0.0
                    @test SII.state_values(integ) == prob.u0
                    s_re = solve!(integ)
                    s_full = solve(prob, alg; kw...)
                    @test s_re.u[end] ≈ s_full.u[end] rtol = 1.0e-12

                    u_alt = 0.5 .* prob.u0
                    reinit!(integ, u_alt)
                    s_re_alt = solve!(integ)
                    s_alt_ref = solve(remake(prob; u0 = u_alt), alg; kw...)
                    @test s_re_alt.u[end] ≈ s_alt_ref.u[end] rtol = 1.0e-12

                    r_p = remake(prob; p = [sk => 2.5])
                    @test SII.getp(r_p, sk)(r_p) == 2.5
                    @test SII.parameter_values(r_p) !== SII.parameter_values(prob)
                end
            end
        end

        @testset "parameter-mutating DiscreteCallback parity across FieldProblem and ODEProblem" begin
            cb = DiscreteCallback((u, t, i) -> t == 0.2, i -> (i.ps[sk] = 4.0; nothing); save_positions = (false, false))
            s_fp = solve(remake(fp; p = [sk => 1.0]), ExplicitEuler(; dt = 5.0e-5, substeps = 1); callback = cb, tstops = [0.2])
            s_ode = solve(remake(ode; p = [sk => 1.0]), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10, callback = cb, tstops = [0.2])
            @test maximum(abs, s_fp.u[end] .- s_ode.u[end]) < 1.0e-4
            # Compare against two chained solves on the ODE path
            a = solve(remake(ode; tspan = (0.0, 0.2)), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10)
            b = solve(remake(ode; u0 = a.u[end], tspan = (0.2, 0.4), p = [sk => 4.0]), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10)
            @test maximum(abs, s_ode.u[end] .- b.u[end]) < 1.0e-10
            # Negative control: without the callback, final state differs substantially
            s_nocb = solve(ode, Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10)
            @test maximum(abs, s_ode.u[end] .- s_nocb.u[end]) > 0.05
        end

        @testset "SII interface and negative controls" begin
            @test SII.state_values(ode) == ode.u0
            @test SII.parameter_values(ode) === ode.p
            @test SII.current_time(ode) == 0.0
            @test SII.getp(ode, sk)(ode) == 1.0

            ig_fp = init(fp, ExplicitEuler(; dt = 0.02))
            @test_throws ArgumentError reinit!(ig_fp, zeros(3))
            @test_throws ArgumentError step!(ig_fp, -0.02)
            @test_throws ArgumentError remake(fp; p = [:nonexistent_param => 1.0])
            @test_throws ArgumentError remake(ode; p = [:nonexistent_param => 1.0])
        end
    end
end
