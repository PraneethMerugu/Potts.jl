isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("fixtures/NeutralExternalTerms.jl")

struct G3CountingArray{T, N, A <: Array{T, N}} <: AbstractArray{T, N}
    data::A
    reads::Base.RefValue{Int}
end

G3CountingArray(data::Array{T, N}) where {T, N} =
    G3CountingArray{T, N, typeof(data)}(data, Ref(0))
Base.size(values::G3CountingArray) = size(values.data)
Base.IndexStyle(::Type{<:G3CountingArray}) = IndexCartesian()
@inline function Base.getindex(values::G3CountingArray, indices...)
    values.reads[] += 1
    return @inbounds getindex(values.data, indices...)
end
@inline Base.setindex!(values::G3CountingArray, value, indices...) =
    @inbounds setindex!(values.data, value, indices...)
Base.copy(values::G3CountingArray) =
    G3CountingArray(copy(values.data), values.reads)

function _g3_evaluate_proposal!(runtime, context)
    plan = runtime.program.descriptor_plan
    CorePotts.evaluate_proposal_contributions!(
        runtime.proposal_contributions, plan, context
    )
    return CorePotts.fold_proposal_contributions(
        plan, runtime.proposal_contributions
    )
end

function _g3_scripted_attempt!(runtime, source, target, draw)
    return CorePotts._attempt_selected!(
        runtime,
        source,
        target,
        1,
        0,
        Val(:scripted),
        draw,
    )
end

function _g3_role_model(; constraint = true, modifier = 0.25)
    @parameters weight = 3.0 drive = 0.5 temperature = 2.0
    cell = CellKind(:g3_cell)
    medium = MediumKind(:g3_medium)
    anchor = SiteBinding(:g3_site)
    proposal = ProposalContext(:g3_copy)
    @named model = PottsSystem(
        statements = StatementSet((
            Lattice((3, 3); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            HamiltonianTerm(
                :g3_site_energy;
                domain = sites(:lattice),
                anchor,
                expression = weight * occupancy(cell, anchor),
            ),
            ProposalDrive(
                :g3_directional_drive,
                ifelse(proposal.is_extension, drive, -drive),
            ),
            ProposalConstraint(:g3_constraint, constraint),
            ProposalModifier(:g3_modifier, modifier),
            Protocol(Sweep(; temperature); name = :main),
        )),
        parameters = [weight, drive, temperature],
    )
    executable = compile(
        complete(model);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    return executable, initial
end

@testset "G3 descriptor-driven sequential reference" begin
    @testset "scientific roles and acceptance seams" begin
        executable, initial = _g3_role_model()
        problem = PottsProblem(executable, initial, (0, 1); seed = 0x301)
        runtime = init(problem).runtime
        context = CorePotts._ProposalEvaluationContext(
            runtime,
            CartesianIndex(2, 2),
            CartesianIndex(2, 3),
            Int32(0),
            Int32(1),
            1,
            0,
        )
        evaluation = _g3_evaluate_proposal!(runtime, context)
        @test evaluation == CorePotts.ProposalEvaluation(
            3.0, 0.5, 0.25, true
        )
        _g3_evaluate_proposal!(runtime, context)
        @test @allocated(_g3_evaluate_proposal!(runtime, context)) == 0
        @test Core.Compiler.return_type(
            _g3_evaluate_proposal!,
            Tuple{typeof(runtime), typeof(context)},
        ) === CorePotts.ProposalEvaluation{Float64}

        neutral = CorePotts.ProposalEvaluation(0.0, 0.0, 0.0, true)
        favorable = CorePotts.ProposalEvaluation(-1.0, 0.0, 0.0, true)
        unfavorable = CorePotts.ProposalEvaluation(log(2.0), 0.0, 0.0, true)
        blocked = CorePotts.ProposalEvaluation(-1.0, 0.0, 0.0, false)
        biased = CorePotts.ProposalEvaluation(log(2.0), log(2.0), 0.0, true)
        modified = CorePotts.ProposalEvaluation(log(2.0), 0.0, log(2.0), true)
        @test CorePotts.proposal_acceptance_probability(neutral, 1.0) == 1.0
        @test CorePotts.proposal_acceptance_probability(favorable, 1.0) == 1.0
        @test CorePotts.proposal_acceptance_probability(unfavorable, 1.0) == 0.5
        @test CorePotts.proposal_acceptance_probability(blocked, 1.0) == 0.0
        @test CorePotts.proposal_acceptance_probability(biased, 1.0) == 1.0
        @test CorePotts.proposal_acceptance_probability(modified, 1.0) == 1.0
        @test CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(2.0, 0.0, 0.0, true), 4.0
        ) == CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(6.0, 0.0, 0.0, true), 12.0
        )
        @test CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(2.0, 0.0, 0.0, true), 1.0
        ) < CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(1.0, 0.0, 0.0, true), 1.0
        )
        @test CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(1.0, 0.0, 0.0, true), 2.0
        ) > CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(1.0, 0.0, 0.0, true), 1.0
        )
        @test CorePotts.proposal_acceptance_probability(favorable, 0.0) == 1.0
        @test CorePotts.proposal_acceptance_probability(unfavorable, 0.0) == 0.0
        @test_throws ArgumentError CorePotts.proposal_acceptance_probability(
            biased, 0.0
        )
        @test CorePotts.proposal_acceptance_decision(
            unfavorable, 1.0, prevfloat(0.5)
        )
        @test !CorePotts.proposal_acceptance_decision(
            unfavorable, 1.0, 0.5
        )
        @test !CorePotts.proposal_acceptance_decision(
            unfavorable, 1.0, nextfloat(0.5)
        )
        @test_throws ArgumentError CorePotts.proposal_acceptance_decision(
            neutral, 1.0, 0.0
        )
        @test_throws ArgumentError CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(NaN, 0.0, 0.0, true), 1.0
        )
    end

    @testset "complete finite one-attempt transition matrix" begin
        @parameters transition_weight = log(2.0) transition_temperature = 1.0
        cell = CellKind(:g3_transition_cell)
        medium = MediumKind(:g3_transition_medium)
        anchor = SiteBinding(:g3_transition_site)
        proposal = ProposalContext(:g3_transition_copy)
        @named transition_model = PottsSystem(
            statements = StatementSet((
                Lattice(
                    (3,);
                    boundary = Periodic(),
                    relations = (proposal = VonNeumann(),),
                ),
                cell,
                medium,
                HamiltonianTerm(
                    :g3_transition_energy;
                    domain = sites(:lattice),
                    anchor,
                    expression = transition_weight * occupancy(cell, anchor),
                ),
                ProposalConstraint(
                    :g3_preserve_both_domains,
                    ifelse(
                        proposal.is_extension,
                        cell_volume(proposal.source_cell) < 2,
                        ifelse(
                            proposal.is_retraction,
                            cell_volume(proposal.target_cell) > 1,
                            true,
                        ),
                    ),
                ),
                Protocol(
                    Sweep(; temperature = transition_temperature);
                    name = :main,
                ),
            )),
            parameters = [transition_weight, transition_temperature],
        )
        executable = compile(
            complete(transition_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )

        function runtime_for(mask)
            labels = reshape(
                Int32[(mask >> bit) & 1 for bit in 0:2], 3
            )
            cells = mask == 0 ? CellKind[] : [cell]
            initial = PottsInitialState(
                ownership = LabelledCells(labels; cells, medium),
            )
            return init(PottsProblem(
                executable, initial, (0, 1); seed = 0x304
            )).runtime
        end
        mask_of(runtime) = sum(
            (runtime.ownership[index] == 1 ? 1 : 0) << (index - 1)
            for index in eachindex(runtime.ownership)
        )
        tracker_matches(runtime) = isempty(runtime.volumes) ?
            count(>(0), runtime.ownership) == 0 :
            only(runtime.volumes) == count(==(Int32(1)), runtime.ownership)
        directions = (-1, 1)
        function analytic_row(mask)
            row = zeros(Float64, 8)
            for target in 1:3, offset in directions
                source = mod1(target + offset, 3)
                target_owner = (mask >> (target - 1)) & 1
                source_owner = (mask >> (source - 1)) & 1
                if target_owner == source_owner
                    row[mask + 1] += 1 / 6
                    continue
                end
                probability = source_owner == 1 ?
                              count_ones(mask) == 2 ? 0.0 : 0.5 :
                              count_ones(mask) == 1 ? 0.0 : 1.0
                accepted = source_owner == 1 ?
                           mask | (1 << (target - 1)) :
                           mask & ~(1 << (target - 1))
                row[accepted + 1] += probability / 6
                row[mask + 1] += (1 - probability) / 6
            end
            return row
        end
        transition = reduce(vcat, permutedims(analytic_row(mask)) for mask in 0:7)
        @test all(>=(0), transition)
        @test all(isapprox.(vec(sum(transition; dims = 2)), 1.0; atol = 1e-15))

        for mask in 0:7, target in 1:3, offset in directions
            source = mod1(target + offset, 3)
            target_owner = (mask >> (target - 1)) & 1
            source_owner = (mask >> (source - 1)) & 1
            source_index = CartesianIndex(source)
            target_index = CartesianIndex(target)
            if target_owner == source_owner
                runtime = runtime_for(mask)
                @test !_g3_scripted_attempt!(
                    runtime, source_index, target_index, 0.75
                )
                @test mask_of(runtime) == mask
                @test tracker_matches(runtime)
            elseif source_owner == 1
                allowed = count_ones(mask) < 2
                accepted_runtime = runtime_for(mask)
                @test _g3_scripted_attempt!(
                    accepted_runtime,
                    source_index,
                    target_index,
                    prevfloat(0.5),
                ) == allowed
                @test mask_of(accepted_runtime) == (allowed ?
                      mask | (1 << (target - 1)) : mask)
                @test tracker_matches(accepted_runtime)
                if allowed
                    rejected_runtime = runtime_for(mask)
                    @test !_g3_scripted_attempt!(
                        rejected_runtime, source_index, target_index, 0.5
                    )
                    @test mask_of(rejected_runtime) == mask
                    @test tracker_matches(rejected_runtime)
                end
            else
                runtime = runtime_for(mask)
                allowed = count_ones(mask) > 1
                @test _g3_scripted_attempt!(
                    runtime, source_index, target_index, 0.75
                ) == allowed
                @test mask_of(runtime) == (allowed ?
                      mask & ~(1 << (target - 1)) : mask)
                @test tracker_matches(runtime)
            end
        end

        two_step = zeros(Float64, 8, 8)
        for initial_mask in 0:7
            first_row = analytic_row(initial_mask)
            for middle_mask in 0:7
                first_probability = first_row[middle_mask + 1]
                iszero(first_probability) && continue
                second_row = analytic_row(middle_mask)
                for final_mask in 0:7
                    two_step[initial_mask + 1, final_mask + 1] +=
                        first_probability * second_row[final_mask + 1]
                end
            end
        end
        @test two_step ≈ transition * transition atol = 1e-15

        rotate(mask) = ((mask << 1) & 7) | ((mask >> 2) & 1)
        for initial_mask in 0:7, final_mask in 0:7
            @test transition[initial_mask + 1, final_mask + 1] ≈
                  transition[rotate(initial_mask) + 1, rotate(final_mask) + 1]
        end

        gibbs = zeros(Float64, 8)
        for mask in 1:6
            gibbs[mask + 1] = exp(-log(2.0) * count_ones(mask))
        end
        gibbs ./= sum(gibbs)
        @test vec(permutedims(gibbs) * transition) ≈ gibbs atol = 1e-15
        for first_mask in 1:6, second_mask in 1:6
            @test gibbs[first_mask + 1] *
                  transition[first_mask + 1, second_mask + 1] ≈
                  gibbs[second_mask + 1] *
                  transition[second_mask + 1, first_mask + 1] atol = 1e-15
        end

        allocation_runtime = runtime_for(1)
        source = CartesianIndex(1)
        target = CartesianIndex(2)
        _g3_scripted_attempt!(allocation_runtime, source, target, 0.5)
        @test @allocated(
            _g3_scripted_attempt!(allocation_runtime, source, target, 0.5)
        ) == 0
        @test Core.Compiler.return_type(
            _g3_scripted_attempt!,
            Tuple{
                typeof(allocation_runtime),
                typeof(source),
                typeof(target),
                Float64,
            },
        ) === Bool
    end

    @testset "semantic RNG raw words and address isolation" begin
        contract = CorePotts.Philox4x32x10V1()
        seed = UInt64(0x123456789abcdef0)
        addresses = (
            CorePotts.RNGAddress(
                stream = CorePotts.ProposalRecipientStream,
                mcs = 0,
                entity = 1,
            ),
            CorePotts.RNGAddress(
                stream = CorePotts.ProposalDirectionStream,
                mcs = 7,
                subround = 2,
                operation = 3,
                entity = 19,
                draw = 1,
            ),
            CorePotts.RNGAddress(
                stream = CorePotts.AcceptanceStream,
                mcs = 11,
                operation = 5,
                entity = 29,
            ),
        )
        expected = (
            (0xd5435ca6, 0xe6f8d826, 0x0a5be497, 0x655d2e74),
            (0x4bbab362, 0xc294cc98, 0xbc40f1d2, 0x1ee62536),
            (0x1da796db, 0xbb662cea, 0x65d4ed06, 0x91036c89),
        )
        @test map(
            address -> CorePotts._rng_words(contract, seed, address),
            addresses,
        ) == expected
        @test reverse(map(
            address -> CorePotts._rng_words(contract, seed, address),
            reverse(addresses),
        )) == expected

        semantic_coordinates = [
            (stream, mcs, subround, entity, draw)
            for stream in (
                CorePotts.ProposalRecipientStream,
                CorePotts.ProposalDirectionStream,
                CorePotts.AcceptanceStream,
            )
            for mcs in 0:2
            for subround in 0:1
            for entity in 1:4
            for draw in 0:1
        ]
        @test allunique(semantic_coordinates)
        raw_words = map(semantic_coordinates) do coordinates
            stream, mcs, subround, entity, draw = coordinates
            address = CorePotts.RNGAddress(
                stream = stream,
                mcs = mcs,
                subround = subround,
                entity = entity,
                draw = draw,
            )
            CorePotts._rng_words(contract, seed, address)
        end
        @test allunique(raw_words)
    end

    @testset "bounded external state access is lattice-size independent" begin
        function counted_external_proposal(shape)
            @variables counted_state
            @parameters counted_weight = 1.0
            cell = CellKind(:g3_counted_cell)
            medium = MediumKind(:g3_counted_medium)
            anchor = SiteBinding(:g3_counted_anchor)
            state = SiteState(
                counted_state;
                name = :g3_counted_state,
                initial = 1.0,
                owner = cell,
                lifecycle = PreserveOnOwnershipChange(),
            )
            term = NeutralExternalTerms.ExternalWeightedSiteTerm(
                :g3_counted_energy,
                counted_weight,
                counted_state,
                cell,
                anchor,
            )
            @named counted_model = PottsSystem(
                statements = StatementSet((
                    Lattice(shape; relations = (proposal = VonNeumann(),)),
                    cell,
                    medium,
                    state,
                    term,
                    Protocol(Sweep(; temperature = 1.0); name = :main),
                )),
                unknowns = [counted_state],
                parameters = [counted_weight],
            )
            executable = compile(
                complete(
                    counted_model;
                    registry = NeutralExternalTerms.registry(),
                );
                engine = SequentialEngine(),
                backend = CPUBackend(),
                scalar_type = Float64,
            )
            labels = zeros(Int, shape)
            center = CartesianIndex(ntuple(
                dimension -> max(1, shape[dimension] ÷ 2), length(shape)
            ))
            target = CartesianIndex(ntuple(
                dimension -> dimension == 1 ? center[dimension] + 1 :
                             center[dimension],
                length(shape),
            ))
            labels[center] = 1
            initial = PottsInitialState(
                ownership = LabelledCells(labels; cells = [cell], medium),
                values = [counted_state => ones(Float64, shape)],
            )
            core_initial = PottsToolkit._core_initial_state(executable, initial)
            handle = only(
                only(executable.core_program.descriptor_plan.groups).launch.state_handles
            )
            representation = CorePotts.handle_representation(handle)
            counting = G3CountingArray(ones(Float64, shape))
            block = CorePotts.DenseStateBlock(counting)
            blocks = (block,)
            bank = CorePotts.BlockBank{
                representation, typeof(blocks),
            }(blocks)
            descriptor_state = CorePotts.AuxiliaryState((bank,))
            counted_initial = CorePotts.ProgramInitialState(
                core_initial.ownership,
                core_initial.cell_kinds;
                scalar_type = Float64,
                cell_generations = core_initial.cell_generations,
                activity = core_initial.activity,
                field = core_initial.field,
                history = core_initial.history,
                stored_states = core_initial.stored_states,
                relationships = core_initial.relationships,
                descriptor_state,
            )
            runtime = CorePotts.initialize_program(
                executable.core_program,
                counted_initial,
                executable.core_program.parameter_defaults,
                UInt64(0x305),
                UInt32(1),
            )
            context = CorePotts._ProposalEvaluationContext(
                runtime,
                center,
                target,
                Int32(0),
                Int32(1),
                1,
                0,
            )
            runtime_counting = CorePotts.state_block(
                runtime.descriptor_state, handle
            ).values
            runtime_counting.reads[] = 0
            evaluation = _g3_evaluate_proposal!(runtime, context)
            return runtime_counting.reads[], evaluation
        end

        small_reads, small_evaluation = counted_external_proposal((4, 4))
        large_reads, large_evaluation = counted_external_proposal((64, 64))
        @test small_reads == large_reads == 2
        @test small_evaluation == large_evaluation ==
              CorePotts.ProposalEvaluation(1.0, 0.0, 0.0, true)
    end

    @testset "constraint rejection is scientifically atomic" begin
        executable, initial = _g3_role_model(; constraint = false, modifier = 0.0)
        problem = PottsProblem(executable, initial, (0, 3); seed = 0x302)
        initial_state = init(problem).u
        solution = solve(problem; save_everystep = true)
        @test all(state -> state.ownership == initial_state.ownership, solution.u)
        @test all(state -> state.volumes == initial_state.volumes, solution.u)
        @test all(state -> state.cell_kinds == initial_state.cell_kinds, solution.u)
    end

    @testset "neutral external term uses public solve and checkpoint" begin
        @variables g3_external_state
        @parameters g3_external_weight = 1.25 temperature = 1.5
        cell = CellKind(:g3_external_cell)
        medium = MediumKind(:g3_external_medium)
        anchor = SiteBinding(:g3_external_anchor)
        state = SiteState(
            g3_external_state;
            name = :g3_external_state,
            initial = 1.0,
            owner = cell,
            lifecycle = PreserveOnOwnershipChange(),
        )
        term = NeutralExternalTerms.ExternalWeightedSiteTerm(
            :g3_external_energy,
            g3_external_weight,
            g3_external_state,
            cell,
            anchor,
        )
        @named model = PottsSystem(
            statements = StatementSet((
                Lattice((4, 4); relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                state,
                term,
                Protocol(Sweep(; temperature); name = :main),
            )),
            unknowns = [g3_external_state],
            parameters = [g3_external_weight, temperature],
        )
        executable = compile(
            complete(model; registry = NeutralExternalTerms.registry());
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        labels = zeros(Int, 4, 4)
        labels[2:3, 2:3] .= 1
        initial_values = reshape(collect(1.0:16.0), 4, 4)
        initial = PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            values = [g3_external_state => initial_values],
        )
        problem = PottsProblem(executable, initial, (0, 3); seed = 0x303)
        uninterrupted = init(problem; save_everystep = true)
        step!(uninterrupted)
        saved = checkpoint(uninterrupted)
        continued = solve!(uninterrupted)
        resumed = solve(
            problem; checkpoint = saved, save_everystep = true
        )
        continued_final = last(continued.u)
        resumed_final = last(resumed.u)
        @test continued_final.ownership == resumed_final.ownership
        @test continued_final.cell_kinds == resumed_final.cell_kinds
        @test continued_final.volumes == resumed_final.volumes
        @test continued_final[:g3_external_state] ==
              resumed_final[:g3_external_state]
        @test continued.stats.accepted == resumed.stats.accepted
        @test continued.stats.rejected == resumed.stats.rejected
        @test continued.stats.null_attempts == resumed.stats.null_attempts
        fresh_runtime = init(problem).runtime
        state_handle = only(
            only(executable.core_program.descriptor_plan.groups).launch.state_handles
        )
        @test CorePotts.state_block(
            fresh_runtime.descriptor_state,
            state_handle,
        ).values == initial_values
    end
end
