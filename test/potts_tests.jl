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
        @test_throws ArgumentError repack(zeros(length(vals) + 1))
        @test_throws ["Tunable", "values; got"] repack(zeros(length(vals) + 1))

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

@testsetup module BoundaryRefusalSetup
using Potts, Test
using Potts: CorePotts

@potts_model VecParamModel begin
    @kinds medium A
    @parameters d[1:2] = [1.0, 2.0]
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CyclicObsModel begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @observed begin
        a ~ b + 1.0
        b ~ a + 1.0
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model NoLatModel begin
    @kinds medium A
    @energy cells => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model NoSweepModel begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
end

@potts_model BadEnergyCase begin
    @structural_parameters kind_case = :cluster_gather
    @kinds medium A
    @lattice Lattice((8, 8))
    if kind_case === :cluster_gather
        @energy clusters(A) => count_neighbors(true)
    elseif kind_case === :site_gather
        @energy sites => count_neighbors(true)
    elseif kind_case === :cell_medium
        @energy cells(medium) => volume
    end
    @sweep Metropolis(; temperature = 1.0)
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "TS2-3: user boundary refusals carry diagnosis and remedy" setup = [BoundaryRefusalSetup] tags = [:potts] begin
    @testset "TS2-3: user boundary refusals carry diagnosis and remedy" begin
        σ = zeros(Int32, 8, 8); σ[3:4, 3:4] .= 1
        prob = PottsProblem(VecParamModel(; name = :sc), [ownership => σ, kind => [:A]], (0, 2))
        @test_throws ArgumentError remake(prob; bogus_kw = 1)
        @test_throws ["unknown keyword", "supported keywords"] remake(prob; bogus_kw = 1)

        raw = CorePotts.PottsProblem(
            CorePotts.Lattice((8, 8)), zeros(Int32, 8, 8), (0, 1);
            hamiltonian = (u, s, c) -> 0.0, dH = (Δs, u, s, c) -> 0.0,
        )
        @test_throws ArgumentError total_energy(raw)
        @test_throws ["total_energy", "PottsSystem"] total_energy(raw)

        @test_throws ArgumentError PottsProblem(VecParamModel(; name = :vp), [ownership => σ, kind => [:A], :d => [1.0, 2.0, 3.0]], (0, 1))
        @test_throws ["2 components", "takes a number"] PottsProblem(
            VecParamModel(; name = :vp), [ownership => σ, kind => [:A], :d => [1.0, 2.0, 3.0]], (0, 1)
        )

        @test_throws ArgumentError Lattice((8, 8); geometry = Hexagonal(), spacing = (1.0, 2.0))
        @test_throws ["hexagonal lattice", "one spacing"] Lattice((8, 8); geometry = Hexagonal(), spacing = (1.0, 2.0))

        @test_throws ArgumentError mtkcompile(CyclicObsModel(; name = :cyc))
        @test_throws ["cyclic", "break the cycle"] mtkcompile(CyclicObsModel(; name = :cyc))

        @test_throws ArgumentError NoLatModel(; name = :nl)
        @test_throws ["no @lattice", "declare"] NoLatModel(; name = :nl)
        @test_throws ArgumentError NoSweepModel(; name = :ns)
        @test_throws ["no @sweep", "declare"] NoSweepModel(; name = :ns)

        @test_throws ArgumentError mtkcompile(BadEnergyCase(; name = :bc, kind_case = :cluster_gather))
        @test_throws ["cluster terms reading neighbors", "cells"] mtkcompile(
            BadEnergyCase(; name = :bc, kind_case = :cluster_gather)
        )
        @test_throws ArgumentError mtkcompile(BadEnergyCase(; name = :bs, kind_case = :site_gather))
        @test_throws ["site terms reading neighbors", "contacts"] mtkcompile(
            BadEnergyCase(; name = :bs, kind_case = :site_gather)
        )
        @test_throws ArgumentError mtkcompile(BadEnergyCase(; name = :bm, kind_case = :cell_medium))
        @test_throws ["medium kind", "kind 0"] mtkcompile(BadEnergyCase(; name = :bm, kind_case = :cell_medium))
    end
end
