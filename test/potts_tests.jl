@testitem "Potts re-exports CorePotts" tags = [:potts] begin
    using Potts
    @testset "Potts re-exports CorePotts" begin
        @test isdefined(Potts, :PottsProblem)
        @test Potts.PottsProblem === Potts.CorePotts.PottsProblem
    end
end

@testsetup module PottsInterfaceSetup
using Potts, Test
using Potts: CorePotts

@potts_model ScimlConforming begin
    @kinds medium A
    @parameters begin
        λ = 2.0
        T = 4.0
        J[kind, kind] = [0 8; 8 2]
    end
    @variables y(cell) = 1.0
    @lattice Lattice((12, 12))
    @energy begin
        cells => λ * (volume - 16.0)^2
        contacts => J[kind, kind′]
    end
    @equations D(y) ~ -0.1 * y
    @sweep Metropolis(; temperature = T)
end

function sciml_op(p = [])
    σ = zeros(Int32, 12, 12)
    σ[2:5, 2:5] .= 1
    σ[7:10, 7:10] .= 2
    return [ownership => σ, kind => [:A, :A], p...]
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "TS2-2: PottsProblem SciML interface conformance" setup = [PottsInterfaceSetup] tags = [:potts] begin
    SS = Potts.SciMLStructures
    SII = Potts.SymbolicIndexingInterface
    @testset "TS2-2: PottsProblem SciML interface conformance" begin
        prob = PottsProblem(ScimlConforming(; name = :sc), sciml_op(), (0, 6); seed = 11)
        for alg in (SequentialCPM(), CheckerboardCPM())
            sol_solve = solve(prob, alg)
            sol_init = solve!(init(prob, alg))
            @test sol_solve.u[end].σ == sol_init.u[end].σ
            @test sol_solve.u[end].cell.y == sol_init.u[end].cell.y

            integ = init(prob, alg)
            step!(integ)
            reinit!(integ)
            sol_reinit = solve!(integ)
            @test sol_reinit.u[end].σ == sol_solve.u[end].σ
            @test sol_reinit.u[end].cell.y == sol_solve.u[end].cell.y

            integ_step = init(prob, alg)
            t0 = integ_step.t
            step!(integ_step)
            @test integ_step.t == t0 + 1
            terminate!(integ_step)
            @test_throws ArgumentError step!(integ_step)
        end

        prob_rm = remake(prob; p = [:λ => 5.0])
        prob_fresh = PottsProblem(ScimlConforming(; name = :sc), sciml_op([:λ => 5.0]), (0, 6); seed = 11)
        @test solve(prob_rm, SequentialCPM()).u[end].σ == solve(prob_fresh, SequentialCPM()).u[end].σ

        @test SS.isscimlstructure(prob.p)
        vals, repack, _ = SS.canonicalize(SS.Tunable(), prob.p)
        p2 = repack(vals .* 2.0)
        @test p2.λ == 2.0 * prob.p.λ && p2.T == 2.0 * prob.p.T
        @test_throws Exception repack(zeros(length(vals) + 1))

        @test SII.is_parameter(prob, :λ) && SII.is_parameter(prob, :T)
        @test SII.is_variable(prob, :y)
        @test !SII.is_parameter(prob, :nonexistent_param)
        @test !SII.is_variable(prob, :nonexistent_var)
        @test SII.getp(prob, :λ)(prob) == 2.0

        integ_sii = init(prob, SequentialCPM())
        SII.setp(integ_sii, :λ)(integ_sii, 3.5)
        @test SII.getp(integ_sii, :λ)(integ_sii) == 3.5
        @test SII.getu(integ_sii, :y)(integ_sii) == integ_sii.state.cell.y

        cb_term = DiscreteCallback((u, t, integ) -> t == 3, terminate!)
        sol_term = solve(prob, SequentialCPM(); callback = cb_term)
        @test sol_term.retcode == Potts.SciMLBase.ReturnCode.Terminated && sol_term.t[end] == 3

        cb_never = DiscreteCallback((u, t, integ) -> false, integ -> error("must not fire"))
        @test solve(prob, SequentialCPM(); callback = cb_never).retcode == Potts.SciMLBase.ReturnCode.Success
    end
end
