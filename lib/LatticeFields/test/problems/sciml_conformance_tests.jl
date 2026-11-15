# SciML interface conformance for FieldProblem and FieldIntegrator (TS2-2):
# solve vs solve!(init), step!(integ, dt, true), reinit!(integ) and reinit!(integ, u0),
# remake, SciMLStructures (Tunable), SymbolicIndexingInterface, and negative controls.

@testsetup module LF_problems_sciml
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/problems_owned.jl")
using CommonSolve: solve, solve!, init, step!
using SciMLBase: SciMLBase, reinit!, remake, ReturnCode
const SS = LatticeFields.Problems.SS
const SII = LatticeFields.Problems.SII
include("../shared/export_all.jl")
end

@testitem "FieldProblem SciML interface conformance (solve, step!, reinit!, remake, SS, SII)" setup = [LF_problems_sciml] tags = [:latticefields, :problems] begin
    using .LF_problems_sciml: SS, SII
    @testset "FieldProblem SciML interface conformance" begin
        dims = (10, 8)
        u0 = rand(Xoshiro(17), prod(dims))
        ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D => 1])
        prob = FieldProblem(
            euler2(dims; storage = LatticeFields.IR.F64), copy(u0), (0.0, 0.2), [0.5];
            state = ["u"], kind = :rate, index = ix
        )
        alg = ExplicitEuler(; dt = 0.05, substeps = 1)

        @testset "solve vs solve!(init) and step!(integ, dt, stop_at_tdt)" begin
            s_direct = solve(prob, alg; saveat = 0.05)
            s_init = solve!(init(prob, alg; saveat = 0.05))
            @test s_direct.t == s_init.t
            @test s_direct.u == s_init.u
            @test SciMLBase.successful_retcode(s_direct)

            integ = init(prob, alg)
            step!(integ, 0.075, true)
            @test isapprox(SII.current_time(integ), 0.075; atol = 1.0e-12)
            step!(integ, 0.125, true)
            @test isapprox(SII.current_time(integ), 0.2; atol = 1.0e-12)
            s_tstop = solve(prob, alg; tstops = [0.075])
            @test maximum(abs, SII.state_values(integ) .- s_tstop.u[end]) < 1.0e-12
        end

        @testset "reinit!(integ) and reinit!(integ, u0)" begin
            s_ref = solve(prob, alg; saveat = 0.05)
            integ = init(prob, alg; saveat = 0.05)
            step!(integ)
            @test SII.current_time(integ) > 0.0
            reinit!(integ)
            @test SII.current_time(integ) == 0.0
            @test integ.iter == 0
            @test integ.retcode == ReturnCode.Success
            @test length(integ.ts) == 1 && integ.ts[1] == 0.0
            @test integ.us[1] == u0
            s_re = solve!(integ)
            @test s_re.t == s_ref.t
            @test s_re.u == s_ref.u

            u1 = 2.0 .* u0 .+ 0.1
            s_u1 = solve(remake(prob; u0 = u1), alg; saveat = 0.05)
            reinit!(integ, u1)
            @test integ.us[1] == u1
            s_re1 = solve!(integ)
            @test s_re1.t == s_u1.t
            @test s_re1.u == s_u1.u

            # reinit! uses current parameters after in-place parameter write
            SII.setp(integ, :D)(integ, 0.25)
            reinit!(integ, u0)
            s_p = solve!(integ)
            s_p_ref = solve(remake(prob; p = [0.25]), alg; saveat = 0.05)
            @test s_p.u == s_p_ref.u
        end

        @testset "remake matches fresh FieldProblem" begin
            u2 = 0.5 .* u0
            r = remake(prob; u0 = u2, p = [:D => 0.8], tspan = (0.0, 0.1))
            f = FieldProblem(
                euler2(dims; storage = LatticeFields.IR.F64), copy(u2), (0.0, 0.1), [0.8];
                state = ["u"], kind = :rate, index = ix
            )
            @test solve(r, alg).u == solve(f, alg).u
        end

        @testset "SciMLStructures (Tunable)" begin
            @test SS.isscimlstructure(prob.p)
            vals, repack, aliases = SS.canonicalize(SS.Tunable(), prob.p)
            @test vals == [0.5]
            @test aliases
            p2 = repack([1.25])
            @test SII.parameter_values(p2, 1) == 1.25
            p3 = SS.replace(SS.Tunable(), prob.p, [2.0])
            @test SII.parameter_values(p3, 1) == 2.0
            @test SII.parameter_values(prob.p, 1) == 0.5
        end

        @testset "SymbolicIndexingInterface" begin
            @test SII.state_values(prob) == u0
            @test SII.parameter_values(prob) === prob.p
            @test SII.current_time(prob) == 0.0
            @test SII.getp(prob, :D)(prob) == 0.5
            integ = init(prob, alg)
            @test SII.state_values(integ) == u0
            @test SII.current_time(integ) == 0.0
            @test length(SII.getu(integ, :u)(integ)) == prod(dims)
            SII.setp(integ, :D)(integ, 0.9)
            @test SII.getp(integ, :D)(integ) == 0.9
        end

        @testset "negative controls" begin
            integ = init(prob, alg)
            err_u0 = try
                reinit!(integ, zeros(3))
                ""
            catch e
                sprint(showerror, e)
            end
            @test occursin("3 values", err_u0) && occursin("$(prod(dims))", err_u0)
            @test_throws ["ArgumentError", "step!(integ, dt)", "does not step back"] step!(integ, -0.05)
            @test_throws ["ArgumentError", "missing_param", "not a parameter"] remake(prob; p = [:missing_param => 1.0])
            @test_throws ErrorException SII.getp(prob, :missing_param)
            @test_throws ["ArgumentError", "missing_param", "not a parameter"] SII.setp(integ, :missing_param)
        end
    end
end
