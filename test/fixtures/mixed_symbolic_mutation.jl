using StaticArrays, Symbolics, ModelingToolkitBase, SymbolicIndexingInterface, DynamicQuantities

function _mixed_symbolic_mutation_contract(algorithms, backend)
    return @testset "mixed symbolic updates and pending parameter publication" begin
        @variables amount polarity[1:2]
        @parameters alpha = 1.0 beta = 2.0 temperature = 1.0
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        source = PottsSystem(
            name = :mixed_mutation,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    ModelState(amount; initial = 1.0),
                    ModelState(polarity; initial = SVector(1.0, 0.0)),
                    Synchronous(:advance, Assign(amount, amount + alpha + beta)),
                    ProposalConstraint(:held_ownership, false),
                    Protocol(Sweep(; temperature); name = :main),
                )
            ),
            unknowns = (amount, polarity), parameters = (alpha, beta, temperature),
        )
        labels = ones(Int32, 2, 2)
        initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
        problem = PottsProblem(source, initial, (0, 3); seed = 53)
        SII = SymbolicIndexingInterface
        for algorithm in algorithms, provider_kind in (:system, :problem, :integrator)
            @testset "$(typeof(algorithm)) / $provider_kind" begin
                integrator = init(problem, algorithm; backend, scalar_type = Float32)
                provider = provider_kind === :system ? problem.system : provider_kind === :problem ? problem : integrator
                @test_throws ArgumentError setp(provider, alpha)(problem, 9.0)
                @test_throws ArgumentError setu(provider, amount)(problem.system, 9.0)
                original_u = integrator.u
                history_length = length(integrator.parameter_history)
                read_parameters = getp(integrator, (alpha, beta, temperature))
                stage_alpha = setp(provider, alpha; run_hook = false)
                stage_alpha(integrator, 7.0)
                pending = copy(integrator.pending_parameters)
                @test read_parameters(integrator) == (1.0f0, 2.0f0, 1.0f0)
                @test integrator.u === original_u
                @test length(integrator.parameter_history) == history_length
                @test_throws ArgumentError setp(provider, (alpha, beta); run_hook = false)(integrator, (9.0, Inf))
                @test integrator.pending_parameters == pending
                beta_index = SII.parameter_index(problem.system, beta)
                @test_throws ArgumentError SII.set_parameter!(integrator, Inf, beta_index)
                @test integrator.pending_parameters == pending

                setu(provider, amount)(integrator, 3.0)
                @test integrator.pending_parameters == pending
                before = integrator.u
                @test_throws ArgumentError setu(provider, (amount, beta))(integrator, (9.0, Inf))
                @test_throws ArgumentError setu(provider, (amount, beta))(integrator, (9.0, 1.0u"m"))
                @test_throws ArgumentError setu(provider, (alpha, polarity))(integrator, (9.0, SVector(1, 2, 3)))
                # Finite but inadmissible acceptance parameters reach Core's public validator.
                @test_throws ArgumentError setu(provider, (amount, temperature))(integrator, (9.0, -1.0))
                @test integrator.u === before
                @test integrator.pending_parameters == pending
                @test read_parameters(integrator) == (1.0f0, 2.0f0, 1.0f0)
                @test length(integrator.parameter_history) == history_length
                @test integrator.t == 0

                setp(provider, temperature; run_hook = false)(integrator, -1.0)
                invalid_pending = copy(integrator.pending_parameters)
                @test_throws ArgumentError SII.finalize_parameters_hook!(integrator, (alpha, temperature))
                @test integrator.pending_parameters == invalid_pending
                @test read_parameters(integrator) == (1.0f0, 2.0f0, 1.0f0)
                @test integrator.u === before
                @test length(integrator.parameter_history) == history_length
                setp(provider, temperature; run_hook = false)(integrator, 1.0)
                @test integrator.pending_parameters == pending

                # Ordinary publication starts from published values, not staged alpha=7.
                setp(provider, (beta,))(integrator, 5.0)
                @test read_parameters(integrator) == (1.0f0, 5.0f0, 1.0f0)
                @test integrator.pending_parameters === nothing
                @test length(integrator.parameter_history) == history_length + 1
                # Preserve scalar/tuple/list replacement forms for one parameter.
                setp(provider, [beta])(integrator, [5.0])
                setp(provider, beta)(integrator, (5.0,))
                setp(provider, (beta,))(integrator, [5.0])
                @test read_parameters(integrator) == (1.0f0, 5.0f0, 1.0f0)
                stage_alpha(integrator, 6.0)
                setp(provider, beta; run_hook = false)(integrator, 8.0)
                before_finalize = length(integrator.parameter_history)
                SII.finalize_parameters_hook!(integrator, (alpha, beta))
                @test integrator.pending_parameters === nothing
                @test read_parameters(integrator) == (6.0f0, 8.0f0, 1.0f0)
                @test length(integrator.parameter_history) == before_finalize + 1
                step!(integrator)
                @test integrator.u[:amount] === 17.0f0

                stage_alpha(integrator, 19.0)
                setu(provider, (amount, polarity, alpha))(integrator, (10.0, SVector(0, 1), 2.0))
                @test integrator.pending_parameters === nothing
                @test read_parameters(integrator) == (2.0f0, 8.0f0, 1.0f0)
                @test integrator.u[:polarity] === SVector(0.0f0, 1.0f0)
                checkpoint_state = checkpoint(integrator)
                restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint_state)
                step!(integrator)
                step!(restored)
                @test restored.u[:amount] === integrator.u[:amount] === 20.0f0
                @test restored.u[:polarity] === integrator.u[:polarity]
                @test getp(restored, (alpha, beta, temperature))(restored) == read_parameters(integrator)
                @test restored.u.ownership == integrator.u.ownership == labels
                @test restored.t == integrator.t == 2
                @test original_u[:amount] === 1.0f0

                named = setu(provider, (value = amount, rate = alpha))
                named(integrator, (rate = 4.0,))
                @test integrator.u[:amount] === 20.0f0
                @test getp(integrator, alpha)(integrator) === 4.0f0
                @test_throws ArgumentError setp(provider, amount)
                @test_throws ArgumentError setu(provider, (alpha, alpha))

                # Owning-package commit-boundary witness: public setters normalize
                # first, so construct a detached invalid candidate via Core's public
                # storage API to exercise its later validation rejection directly.
                stage_alpha(integrator, 11.0)
                before_core_rejection = integrator.u
                pending_before_rejection = copy(integrator.pending_parameters)
                history_before_rejection = copy(integrator.parameter_history)
                parameters_before_rejection = Tuple(read_parameters(integrator))
                SPI = CorePotts.CompilerSPI
                descriptor_before = CorePotts.BackendSPI.program_snapshot_descriptor_state(CorePotts.program_snapshot(integrator.runtime))
                invalid_candidate = SPI.copy_auxiliary_state(descriptor_before)
                state_entry = integrator.plan.state_manifest[SII.variable_index(problem.system, amount)]
                fill!(SPI.state_block(invalid_candidate, state_entry.handle).values, Inf32)
                parameter_candidate = collect(SII.parameter_values(integrator))
                parameter_candidate[SII.parameter_index(problem.system, beta)] = 13.0f0
                @test_throws r"state block contains a nonfinite value" Potts._commit_symbolic_update!(
                    integrator; parameters = parameter_candidate,
                    descriptor_state = invalid_candidate, descriptor_before,
                )
                @test integrator.u === before_core_rejection
                @test integrator.u[:amount] === 20.0f0
                @test Tuple(read_parameters(integrator)) == parameters_before_rejection
                @test integrator.pending_parameters == pending_before_rejection
                @test integrator.parameter_history == history_before_rejection
                @test integrator.t == 2
                @test_throws r"finalize the staged parameter transaction" checkpoint(integrator)
                setp(provider, alpha)(integrator, 4.0)
                restored_after_rejection = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator))
                step!(integrator)
                step!(restored_after_rejection)
                @test restored_after_rejection.u[:amount] === integrator.u[:amount] === 32.0f0
                @test restored_after_rejection.u.ownership == integrator.u.ownership == labels
                @test restored_after_rejection.t == integrator.t == 3
            end
        end
    end
end
