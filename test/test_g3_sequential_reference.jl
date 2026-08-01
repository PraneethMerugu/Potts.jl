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
        underflow_edge = CorePotts.ProposalEvaluation(
            744.3, 0.0, 0.0, true
        )
        smallest_draw = nextfloat(0.0)
        @test CorePotts.proposal_acceptance_probability(
            underflow_edge, 1.0
        ) == smallest_draw
        @test CorePotts.proposal_acceptance_decision(
            underflow_edge, 1.0, smallest_draw
        )
        deep_underflow = CorePotts.ProposalEvaluation(
            1.0e6, 0.0, 0.0, true
        )
        @test CorePotts.proposal_acceptance_probability(
            deep_underflow, 1.0
        ) == 0.0
        @test !CorePotts.proposal_acceptance_decision(
            deep_underflow, 1.0, smallest_draw
        )

        log_runtime = init(problem).runtime
        log_runtime.parameters .= (744.3, 0.0, 1.0)
        @test _g3_scripted_attempt!(
            log_runtime,
            CartesianIndex(2, 2),
            CartesianIndex(2, 3),
            smallest_draw,
        )
        @test log_runtime.accepted == 1
        @test log_runtime.energy_rejections == 0

        retirement_runtime = init(problem).runtime
        @test _g3_scripted_attempt!(
            retirement_runtime,
            CartesianIndex(2, 3),
            CartesianIndex(2, 2),
            0.75,
        )
        @test retirement_runtime.retired_cells == 0
        CorePotts._retire_extinct_cells!(retirement_runtime)
        @test retirement_runtime.retired_cells == 1
        @test only(retirement_runtime.cell_kinds) == 0
        @test_throws ArgumentError CorePotts.proposal_acceptance_decision(
            neutral, 1.0, 0.0
        )
        @test_throws ArgumentError CorePotts.proposal_acceptance_probability(
            CorePotts.ProposalEvaluation(NaN, 0.0, 0.0, true), 1.0
        )

        energy_drive = CorePotts.ProposalEvaluation(
            0.0, 2.0, 0.0, 0.0, true
        )
        dimensionless_drive = CorePotts.ProposalEvaluation(
            0.0, 0.0, 2.0, 0.0, true
        )
        @test CorePotts.proposal_log_acceptance_ratio(
            energy_drive, 4.0
        ) == -0.5
        @test CorePotts.proposal_log_acceptance_ratio(
            dimensionless_drive, 4.0
        ) == 2.0
    end

    @testset "compiled Act and chemotaxis drives" begin
        @variables activity_drive_state
        act_cell = CellKind(:act_cell)
        foreign_cell = CellKind(:foreign_cell)
        act_medium = MediumKind(:act_medium)
        activity = SiteState(
            activity_drive_state;
            name = :act_state,
            initial = 0.0,
            owner = act_cell,
            lifecycle = ClearOnOwnershipChange(),
        )
        @named act_model = PottsSystem(
            statements = StatementSet((
                Lattice(
                    (5, 5);
                    boundary = Closed(),
                    relations = (
                        proposal = VonNeumann(),
                        activity_neighborhood = Moore(),
                    ),
                ),
                act_cell,
                foreign_cell,
                act_medium,
                activity,
                ActEnergy(
                    act_cell,
                    activity_drive_state;
                    maximum = 10.0,
                    strength = 2.0,
                    reduction = :activity_neighborhood,
                ),
                Protocol(Sweep(; temperature = 4.0); name = :main),
            )),
            unknowns = [activity_drive_state],
        )
        act_executable = compile(
            complete(act_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        act_labels = zeros(Int, 5, 5)
        act_labels[3, 2] = 1
        act_labels[2, 2] = 1
        act_labels[3, 4] = 2
        act_values = zeros(Float64, 5, 5)
        act_values[3, 2] = 3.0
        act_values[2, 2] = 8.0
        act_initial = PottsInitialState(
            ownership = LabelledCells(
                act_labels;
                cells = [act_cell, foreign_cell],
                medium = act_medium,
            ),
            values = [activity_drive_state => act_values],
        )
        act_runtime = init(PottsProblem(
            act_executable, act_initial, (0, 1); seed = 0x30a
        )).runtime
        act_context = CorePotts._ProposalEvaluationContext(
            act_runtime,
            CartesianIndex(3, 2),
            CartesianIndex(3, 3),
            Int32(0),
            Int32(1),
            1,
            0,
        )
        act_evaluation = _g3_evaluate_proposal!(act_runtime, act_context)
        @test act_evaluation.delta_h == 0.0
        @test act_evaluation.drive_energy ≈ -1.0
        @test act_evaluation.drive_log_bias == 0.0
        @test act_evaluation.kinetic_modifier == 0.0
        @test act_evaluation.constraints_allowed
        @test any(
            descriptor.role isa CorePotts.ProposalEnergyDriveRole
            for group in act_executable.core_program.descriptor_plan.groups
            for descriptor in group.launch.instances
        )
        foreign_context = CorePotts._ProposalEvaluationContext(
            act_runtime,
            CartesianIndex(3, 4),
            CartesianIndex(3, 3),
            Int32(0),
            Int32(2),
            2,
            0,
        )
        @test _g3_evaluate_proposal!(
            act_runtime, foreign_context
        ).drive_energy == 0.0
        retraction_context = CorePotts._ProposalEvaluationContext(
            act_runtime,
            CartesianIndex(3, 3),
            CartesianIndex(3, 2),
            Int32(1),
            Int32(0),
            3,
            0,
        )
        @test _g3_evaluate_proposal!(
            act_runtime, retraction_context
        ).drive_energy == 0.0
        _g3_evaluate_proposal!(act_runtime, act_context)
        @test @allocated(_g3_evaluate_proposal!(
            act_runtime, act_context
        )) == 0

        @variables chemo_state
        chemo_cell = CellKind(:chemo_cell)
        nonresponding_cell = CellKind(:nonresponding_cell)
        chemo_medium = MediumKind(:chemo_medium)
        field = FieldState(
            chemo_state;
            name = :chemo_field,
            initial = 0.0,
        )
        @named chemo_model = PottsSystem(
            statements = StatementSet((
                Lattice(
                    (5, 5);
                    boundary = Closed(),
                    relations = (proposal = VonNeumann(),),
                ),
                chemo_cell,
                nonresponding_cell,
                chemo_medium,
                field,
                Chemotaxis(
                    chemo_cell,
                    field;
                    strength = 2.0,
                    mode = ExtensionsOnly(),
                    sample = Nearest(),
                ),
                Protocol(Sweep(; temperature = 4.0); name = :main),
            )),
            unknowns = [chemo_state],
        )
        chemo_executable = compile(
            complete(chemo_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        chemo_labels = zeros(Int, 5, 5)
        chemo_labels[3, 2] = 1
        chemo_labels[3, 4] = 2
        chemo_values = zeros(Float64, 5, 5)
        chemo_values[3, 2] = 1.0
        chemo_values[3, 3] = 4.0
        chemo_initial = PottsInitialState(
            ownership = LabelledCells(
                chemo_labels;
                cells = [chemo_cell, nonresponding_cell],
                medium = chemo_medium,
            ),
            values = [chemo_state => chemo_values],
        )
        chemo_runtime = init(PottsProblem(
            chemo_executable, chemo_initial, (0, 1); seed = 0x30b
        )).runtime
        chemo_context = CorePotts._ProposalEvaluationContext(
            chemo_runtime,
            CartesianIndex(3, 2),
            CartesianIndex(3, 3),
            Int32(0),
            Int32(1),
            1,
            0,
        )
        @test _g3_evaluate_proposal!(
            chemo_runtime, chemo_context
        ).drive_energy == -6.0
        chemo_foreign_context = CorePotts._ProposalEvaluationContext(
            chemo_runtime,
            CartesianIndex(3, 4),
            CartesianIndex(3, 3),
            Int32(0),
            Int32(2),
            2,
            0,
        )
        @test _g3_evaluate_proposal!(
            chemo_runtime, chemo_foreign_context
        ).drive_energy == 0.0
        chemo_retraction_context = CorePotts._ProposalEvaluationContext(
            chemo_runtime,
            CartesianIndex(3, 3),
            CartesianIndex(3, 2),
            Int32(1),
            Int32(0),
            3,
            0,
        )
        @test _g3_evaluate_proposal!(
            chemo_runtime, chemo_retraction_context
        ).drive_energy == 0.0
        _g3_evaluate_proposal!(chemo_runtime, chemo_context)
        @test @allocated(_g3_evaluate_proposal!(
            chemo_runtime, chemo_context
        )) == 0
    end

    @testset "external generic staged state effects" begin
        @variables external_tracer
        tracer_cell = CellKind(:tracer_cell)
        tracer_medium = MediumKind(:tracer_medium)
        tracer = SiteState(
            external_tracer;
            name = :external_tracer_state,
            initial = 0.0,
            owner = tracer_cell,
            lifecycle = ClearOnOwnershipChange(),
        )
        copy = ProposalContext(:external_tracer_copy)
        @named tracer_model = PottsSystem(
            statements = StatementSet((
                Lattice(
                    (3, 3);
                    boundary = Closed(),
                    relations = (proposal = VonNeumann(),),
                ),
                tracer_cell,
                tracer_medium,
                tracer,
                AcceptedCopy(
                    :external_refresh,
                    Assign(external_tracer, 7.0);
                    when = copy.is_extension,
                ),
                Synchronous(
                    :external_relaxation,
                    Assign(external_tracer, max(external_tracer - 2.0, 0.0));
                    phase = AfterMCS(),
                ),
                Protocol(Sweep(; temperature = 1.0); name = :main),
            )),
            unknowns = [external_tracer],
        )
        tracer_executable = compile(
            complete(tracer_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        @test tracer_executable.core_program.stage_plan.accepted_count == 1
        @test tracer_executable.core_program.stage_plan.after_mcs_count == 1
        labels = zeros(Int, 3, 3)
        labels[2, 2] = 1
        tracer_values = zeros(Float64, 3, 3)
        tracer_values[2, 2] = 4.0
        tracer_values[2, 3] = 99.0
        initial = PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [tracer_cell], medium = tracer_medium
            ),
            values = [external_tracer => tracer_values],
        )
        runtime = init(PottsProblem(
            tracer_executable, initial, (0, 1); seed = 0x30c
        )).runtime
        accepted_descriptor = only(only(
            tracer_executable.core_program.stage_plan.accepted_copy
        ).instances)
        state_handle = accepted_descriptor.effect.target
        state_values = CorePotts.state_block(
            runtime.descriptor_state, state_handle
        ).values
        @test _g3_scripted_attempt!(
            runtime,
            CartesianIndex(2, 2),
            CartesianIndex(2, 3),
            0.5,
        )
        @test state_values[2, 3] == 7.0
        @test runtime.ownership[2, 3] == 1
        CorePotts._execute_after_mcs_stage!(runtime)
        @test state_values[2, 2] == 2.0
        @test state_values[2, 3] == 5.0
        CorePotts._execute_after_mcs_stage!(runtime)
        @test @allocated(CorePotts._execute_after_mcs_stage!(runtime)) == 0
        @test Core.Compiler.return_type(
            CorePotts._execute_after_mcs_stage!,
            Tuple{typeof(runtime)},
        ) === Nothing
        @test CorePotts.program_checkpoint(runtime).snapshot.descriptor_state !==
              runtime.descriptor_state
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
                @test runtime.null_attempts == 1
                @test runtime.accepted == 0
                @test runtime.constraint_rejections == 0
                @test runtime.energy_rejections == 0
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
                @test accepted_runtime.accepted == Int(allowed)
                @test accepted_runtime.constraint_rejections == Int(!allowed)
                @test accepted_runtime.energy_rejections == 0
                @test accepted_runtime.rejected == Int(!allowed)
                if allowed
                    rejected_runtime = runtime_for(mask)
                    @test !_g3_scripted_attempt!(
                        rejected_runtime, source_index, target_index, 0.5
                    )
                    @test mask_of(rejected_runtime) == mask
                    @test tracker_matches(rejected_runtime)
                    @test rejected_runtime.accepted == 0
                    @test rejected_runtime.constraint_rejections == 0
                    @test rejected_runtime.energy_rejections == 1
                    @test rejected_runtime.rejected == 1
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
                @test runtime.accepted == Int(allowed)
                @test runtime.constraint_rejections == Int(!allowed)
                @test runtime.energy_rejections == 0
                @test runtime.rejected == Int(!allowed)
            end
        end

        function direct_attempt_outcomes(mask, target, offset)
            source = mod1(target + offset, 3)
            target_owner = (mask >> (target - 1)) & 1
            source_owner = (mask >> (source - 1)) & 1
            target_owner == source_owner && return ((mask, 1.0),)
            allowed = source_owner == 1 ?
                      count_ones(mask) < 2 : count_ones(mask) > 1
            allowed || return ((mask, 1.0),)
            accepted_mask = source_owner == 1 ?
                            mask | (1 << (target - 1)) :
                            mask & ~(1 << (target - 1))
            acceptance = source_owner == 1 ? 0.5 : 1.0
            isone(acceptance) && return ((accepted_mask, 1.0),)
            return (
                (accepted_mask, acceptance),
                (mask, 1 - acceptance),
            )
        end

        two_step = zeros(Float64, 8, 8)
        for initial_mask in 0:7
            for first_target in 1:3, first_offset in directions
                first_outcomes = direct_attempt_outcomes(
                    initial_mask, first_target, first_offset
                )
                for (middle_mask, first_probability) in first_outcomes
                    for second_target in 1:3, second_offset in directions
                        second_outcomes = direct_attempt_outcomes(
                            middle_mask, second_target, second_offset
                        )
                        for (final_mask, second_probability) in second_outcomes
                            two_step[initial_mask + 1, final_mask + 1] +=
                                first_probability * second_probability / 36
                        end
                    end
                end
            end
        end
        @test two_step ≈ transition * transition atol = 1e-15

        next_acceptance(runtime) = CorePotts._program_uniform(
            Float64,
            runtime,
            CorePotts.AcceptanceStream,
            3,
            2;
            subround = 0,
        )
        reference_next_draw = next_acceptance(runtime_for(1))
        branch_cases = (
            (runtime_for(1), CartesianIndex(1), CartesianIndex(1), 0.75),
            (runtime_for(3), CartesianIndex(2), CartesianIndex(3), 0.75),
            (runtime_for(1), CartesianIndex(1), CartesianIndex(2), 0.5),
            (
                runtime_for(1),
                CartesianIndex(1),
                CartesianIndex(2),
                prevfloat(0.5),
            ),
        )
        for (branch_runtime, source, target, draw) in branch_cases
            _g3_scripted_attempt!(branch_runtime, source, target, draw)
            @test next_acceptance(branch_runtime) == reference_next_draw
        end

        accounting_integrator = init(PottsProblem(
            executable,
            PottsInitialState(
                ownership = LabelledCells(
                    reshape(Int32[1, 0, 0], 3); cells = [cell], medium
                ),
            ),
            (0, 1);
            seed = 0x30a,
        ))
        step!(accounting_integrator)
        accounting = PottsToolkit.runtime_statistics(accounting_integrator)
        @test accounting.candidate_attempts == 3
        @test accounting.candidate_attempts ==
              accounting.accepted + accounting.null_attempts +
              accounting.constraint_rejections + accounting.energy_rejections
        @test accounting.rejected ==
              accounting.constraint_rejections + accounting.energy_rejections
        @test accounting.retired_cells <= accounting.accepted

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
            bank = CorePotts.BlockBank{
                representation, typeof(counting),
            }(counting)
            descriptor_state = CorePotts.AuxiliaryState((bank,))
            counted_initial = CorePotts.ProgramInitialState(
                core_initial.ownership,
                core_initial.cell_kinds;
                scalar_type = Float64,
                cell_generations = core_initial.cell_generations,
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
            runtime_values = CorePotts.state_block(
                runtime.descriptor_state, handle
            ).values
            runtime_counting = parent(runtime_values)
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

    @testset "endpoint retirement is an ordinary compiled constraint" begin
        cell = CellKind(:g3_linked_cell)
        medium = MediumKind(:g3_linked_medium)
        links = RelationshipState(
            :g3_links;
            endpoints = Undirected(cell, cell),
            payload = (strength = 0.0, target = 1.0, maximum = 8.0),
            capacity = 8,
            maximum_degree = 2,
            lifecycle = RejectEndpointRetirement(),
        )
        @named relationship_model = PottsSystem(statements = StatementSet((
            Lattice(
                (4, 3);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            links,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )))
        completed = complete(relationship_model)
        derived = only(filter(
            statement -> statement isa ProposalConstraint &&
                         PottsToolkit._statement_option(
                             statement, :derived_from, nothing
                         ) === :reject_endpoint_retirement,
            statements(completed),
        ))
        @test Symbol(statement_id(derived)) ===
              :__potts_endpoint_retirement_g3_links
        executable = compile(
            completed;
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        @test !isdefined(CorePotts, :_relationship_allows_extinction)
        constraint_descriptor = only([
            descriptor
            for group in executable.core_program.descriptor_plan.groups
            for descriptor in group.launch.instances
            if executable.core_program.descriptor_plan.source_table[
                descriptor.source_handle
            ].local_id == statement_id(derived)
        ])
        @test CorePotts.descriptor_role(constraint_descriptor) isa
              CorePotts.ProposalConstraintRole
        @test CorePotts.descriptor_resource_access(
            constraint_descriptor
        ).footprint == CorePotts.IncidentRelationshipFootprint(2)

        labels = zeros(Int, 4, 3)
        labels[2, 2] = 1
        labels[4, 2] = 2
        function relationship_runtime(initial_edges)
            initial = PottsInitialState(
                ownership = LabelledCells(
                    labels; cells = [cell, cell], medium
                ),
                values = [links => initial_edges],
            )
            return init(PottsProblem(
                executable, initial, (0, 1); seed = 0x306
            )).runtime
        end
        source = CartesianIndex(1, 2)
        target = CartesianIndex(2, 2)
        linked_runtime = relationship_runtime([(1, 2)])
        linked_context = CorePotts._ProposalEvaluationContext(
            linked_runtime,
            source,
            target,
            Int32(1),
            Int32(0),
            1,
            0,
        )
        linked_evaluation = _g3_evaluate_proposal!(
            linked_runtime, linked_context
        )
        @test !linked_evaluation.constraints_allowed
        _g3_evaluate_proposal!(linked_runtime, linked_context)
        @test @allocated(
            _g3_evaluate_proposal!(linked_runtime, linked_context)
        ) == 0
        before_ownership = copy(linked_runtime.ownership)
        before_volumes = copy(linked_runtime.volumes)
        before_relationships = copy(only(linked_runtime.relationships))
        @test !_g3_scripted_attempt!(
            linked_runtime, source, target, 0.5
        )
        @test linked_runtime.ownership == before_ownership
        @test linked_runtime.volumes == before_volumes
        linked_relationships = only(linked_runtime.relationships)
        @test linked_relationships.active == before_relationships.active
        @test linked_relationships.endpoint_a ==
              before_relationships.endpoint_a
        @test linked_relationships.endpoint_b ==
              before_relationships.endpoint_b
        @test linked_relationships.generation_a ==
              before_relationships.generation_a
        @test linked_relationships.generation_b ==
              before_relationships.generation_b
        @test linked_relationships.payload == before_relationships.payload
        @test linked_relationships.degree == before_relationships.degree
        @test linked_relationships.incident_edges ==
              before_relationships.incident_edges

        unlinked_runtime = relationship_runtime(Tuple{Int, Int}[])
        unlinked_context = CorePotts._ProposalEvaluationContext(
            unlinked_runtime,
            source,
            target,
            Int32(1),
            Int32(0),
            1,
            0,
        )
        @test _g3_evaluate_proposal!(
            unlinked_runtime, unlinked_context
        ).constraints_allowed
        @test _g3_scripted_attempt!(
            unlinked_runtime, source, target, 0.5
        )
        @test unlinked_runtime.ownership[target] == 0
        @test unlinked_runtime.volumes[1] == 0
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
                Observation(:g3_external_state_snapshot, g3_external_state),
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
        uninterrupted = init(
            problem;
            save_everystep = true,
            observables = (:g3_external_state_snapshot,),
        )
        step!(uninterrupted)
        saved = checkpoint(uninterrupted)
        continued = solve!(uninterrupted)
        resumed = solve(
            problem;
            checkpoint = saved,
            save_everystep = true,
            observables = (:g3_external_state_snapshot,),
        )
        continued_final = last(continued.u)
        resumed_final = last(resumed.u)
        @test continued_final.ownership == resumed_final.ownership
        @test continued_final.cell_kinds == resumed_final.cell_kinds
        @test continued_final.volumes == resumed_final.volumes
        @test continued_final[:g3_external_state] ==
              resumed_final[:g3_external_state]
        @test continued_final[:g3_external_state_snapshot] ==
              continued_final[:g3_external_state]
        @test resumed_final[:g3_external_state_snapshot] ==
              resumed_final[:g3_external_state]
        @test continued.stats.accepted == resumed.stats.accepted
        @test continued.stats.rejected == resumed.stats.rejected
        @test continued.stats.null_attempts == resumed.stats.null_attempts
        @test continued.stats.constraint_rejections ==
              resumed.stats.constraint_rejections
        @test continued.stats.energy_rejections ==
              resumed.stats.energy_rejections
        @test continued.stats.retired_cells == resumed.stats.retired_cells
        @test continued.stats.candidate_attempts ==
              resumed.stats.candidate_attempts
        fresh_runtime = init(problem).runtime
        state_handle = only(
            only(executable.core_program.descriptor_plan.groups).launch.state_handles
        )
        @test CorePotts.state_block(
            fresh_runtime.descriptor_state,
            state_handle,
        ).values == initial_values
    end


    @testset "external relationship policy uses generic topology effects" begin
        @parameters pair_weight = 1.25 temperature = 1.5
        cell = CellKind(:g3_external_pair_cell)
        medium = MediumKind(:g3_external_pair_medium)
        proposal = ProposalContext(:g3_external_pair_copy)
        fixture = NeutralExternalTerms.bounded_pair_fixture(
            cell, pair_weight, proposal
        )
        relationship = only(filter(
            statement -> statement isa RelationshipState,
            collect(fixture),
        ))
        retune_edge = RelationshipBinding(:g3_retune_edge, relationship)
        retune_process = LifecycleProcess(
            :retune_neutral_pairs;
            domain = edges(relationship),
            expression =
                (retune_edge.score >= retune_edge.cutoff) &
                (retune_edge.marker > zero(pair_weight)),
            effects = (Retune(
                relationship,
                retune_edge;
                payload = (
                    score = retune_edge.score + pair_weight,
                    cutoff = retune_edge.cutoff,
                    marker = zero(pair_weight),
                ),
            ),),
            phase = Lifecycle(),
        )
        duplicate_create = AcceptedCopy(
            :request_neutral_pair_duplicate,
            Create(
                relationship,
                proposal.source_cell,
                proposal.target_cell;
                payload = (
                    score = 2 * pair_weight,
                    cutoff = zero(pair_weight),
                    marker = 2 * pair_weight,
                ),
            );
            when = new_contact(
                proposal.source_cell, proposal.target_cell
            ) & !linked(
                relationship,
                proposal.source_cell,
                proposal.target_cell,
            ),
        )
        @named model = PottsSystem(
            statements = StatementSet((
                Lattice((5, 5); relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                fixture,
                retune_process,
                duplicate_create,
                Protocol(Sweep(; temperature); name = :main),
            )),
            parameters = [pair_weight, temperature],
        )
        executable = compile(
            complete(model; registry = NeutralExternalTerms.registry());
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        @test keys(only(executable.reports.relationship_states).payload_units) ==
              (:score, :cutoff, :marker)
        create_descriptors = [
            descriptor
            for group in executable.core_program.stage_plan.accepted_copy
            for descriptor in group.instances
            if descriptor.effect isa CorePotts.RelationshipCreateEffect
        ]
        remove_descriptors = [
            descriptor
            for group in executable.core_program.stage_plan.after_mcs
            for descriptor in group.instances
            if descriptor.effect isa CorePotts.RelationshipRemoveEffect
        ]
        retune_descriptors = [
            descriptor
            for group in executable.core_program.stage_plan.after_mcs
            for descriptor in group.instances
            if descriptor.effect isa CorePotts.RelationshipRetuneEffect
        ]
        @test length(create_descriptors) == 2
        @test all(
            descriptor -> descriptor.effect.relationship_slot == 1,
            create_descriptors,
        )
        @test length(remove_descriptors) == 2
        @test length(retune_descriptors) == 1
        @test only(retune_descriptors).effect.relationship_slot == 1

        labels = zeros(Int, 5, 5)
        labels[2, 2] = 1
        labels[2, 3:4] .= 2
        initial = PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [cell, cell], medium
            ),
        )
        runtime = init(PottsProblem(
            executable, initial, (0, 1); seed = 0x30a
        )).runtime
        source = CartesianIndex(2, 2)
        target = CartesianIndex(2, 3)
        create_context = CorePotts._ProposalEvaluationContext(
            runtime,
            source,
            target,
            Int32(2),
            Int32(1),
            1,
            0,
        )
        CorePotts._emit_accepted_copy_stage!(runtime, create_context)
        @test @allocated(
            CorePotts._emit_accepted_copy_stage!(runtime, create_context)
        ) == 0
        @test Core.Compiler.return_type(
            CorePotts._emit_accepted_copy_stage!,
            Tuple{typeof(runtime), typeof(create_context)},
        ) === typeof(runtime.stage_buffers.accepted_copy)
        @test _g3_scripted_attempt!(
            runtime, source, target, 0.5
        )
        runtime_relationships = only(runtime.relationships)
        @test count(runtime_relationships.active) == 1
        @test map(values -> values[1], runtime_relationships.payload) ==
              (1.25, 0.0, 1.25)

        lifecycle_initial = PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [cell, cell], medium
            ),
            values = [
                relationship => [(
                    1,
                    2,
                    (score = -1.0, cutoff = 0.0, marker = 7.0),
                )],
            ],
        )
        lifecycle_problem = PottsProblem(
            executable, lifecycle_initial, (0, 1); seed = 0x30b
        )
        lifecycle_integrator = init(lifecycle_problem; save_start = false)
        saved = checkpoint(lifecycle_integrator)
        step!(lifecycle_integrator)
        @test count(only(
            lifecycle_integrator.runtime.relationships
        ).active) == 0
        resumed = init(
            lifecycle_problem; checkpoint = saved, save_start = false
        )
        step!(resumed)
        @test only(resumed.runtime.relationships).active ==
              only(lifecycle_integrator.runtime.relationships).active

        allocation_initial = PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [cell, cell], medium
            ),
            values = [
                relationship => [(
                    1,
                    2,
                    (score = 1.0, cutoff = 0.0, marker = 7.0),
                )],
            ],
        )
        allocation_runtime = init(PottsProblem(
            executable, allocation_initial, (0, 1); seed = 0x30c
        )).runtime
        CorePotts._execute_after_mcs_stage!(allocation_runtime)
        @test map(values -> values[1], only(
            allocation_runtime.relationships
        ).payload) == (2.25, 0.0, 0.0)
        @test @allocated(
            CorePotts._execute_after_mcs_stage!(allocation_runtime)
        ) == 0
        @test Core.Compiler.return_type(
            CorePotts._execute_after_mcs_stage!,
            Tuple{typeof(allocation_runtime)},
        ) === Nothing
    end

    @testset "multiple relationship stores remain independently addressable" begin
        @parameters multi_weight = 1.5 multi_temperature = 2.0
        cell = CellKind(:g3_multi_cell)
        medium = MediumKind(:g3_multi_medium)
        proposal = ProposalContext(:g3_multi_copy)
        score_links = RelationshipState(
            :g3_score_links;
            endpoints = Undirected(cell, cell),
            payload = (score = multi_weight,),
            capacity = 4,
            maximum_degree = 2,
            lifecycle = RemoveWithEndpoint(),
        )
        elastic_links = RelationshipState(
            :g3_elastic_links;
            endpoints = Undirected(cell, cell),
            payload = (
                stiffness = multi_weight,
                rest_length = zero(multi_weight),
            ),
            capacity = 5,
            maximum_degree = 3,
            lifecycle = RemoveWithEndpoint(),
        )
        score_edge = RelationshipBinding(:g3_multi_score_edge, score_links)
        retune_score = LifecycleProcess(
            :g3_multi_retune_score;
            domain = edges(score_links),
            expression = score_edge.score > zero(multi_weight),
            effects = (Retune(
                score_links,
                score_edge;
                payload = (score = score_edge.score + multi_weight,),
            ),),
            phase = Lifecycle(),
        )
        @named model = PottsSystem(
            statements = StatementSet((
                Lattice((5, 5); relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                score_links,
                elastic_links,
                AcceptedCopy(
                    :create_score_link,
                    Create(
                        score_links,
                        proposal.source_cell,
                        proposal.target_cell;
                        payload = (score = multi_weight,),
                    );
                    when = new_contact(
                        proposal.source_cell, proposal.target_cell
                    ) & !linked(
                        score_links,
                        proposal.source_cell,
                        proposal.target_cell,
                    ),
                ),
                AcceptedCopy(
                    :create_elastic_link,
                    Create(
                        elastic_links,
                        proposal.source_cell,
                        proposal.target_cell;
                        payload = (
                            stiffness = 2 * multi_weight,
                            rest_length = zero(multi_weight),
                        ),
                    );
                    when = new_contact(
                        proposal.source_cell, proposal.target_cell
                    ) & !linked(
                        elastic_links,
                        proposal.source_cell,
                        proposal.target_cell,
                    ),
                ),
                retune_score,
                Observation(:g3_score_degree, degree(score_links, 1)),
                Observation(:g3_elastic_degree, degree(elastic_links, 1)),
                Protocol(Sweep(; temperature = multi_temperature); name = :main),
            )),
            parameters = [multi_weight, multi_temperature],
        )
        executable = compile(
            complete(model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        @test length(executable.core_program.relationships) == 2
        @test length(executable.reports.relationship_states) == 2
        @test Tuple(
            entry.name for entry in executable.reports.relationship_states
        ) == (:g3_elastic_links, :g3_score_links)
        create_descriptors = [
            descriptor
            for group in executable.core_program.stage_plan.accepted_copy
            for descriptor in group.instances
            if descriptor.effect isa CorePotts.RelationshipCreateEffect
        ]
        @test sort(Int[
            descriptor.effect.relationship_slot
            for descriptor in create_descriptors
        ]) == [1, 2]

        labels = zeros(Int, 5, 5)
        labels[2, 2] = 1
        labels[2, 3:4] .= 2
        problem = PottsProblem(
            executable,
            PottsInitialState(ownership = LabelledCells(
                labels; cells = [cell, cell], medium
            )),
            (0, 1);
            seed = 0x30d,
        )
        integrator = init(problem; save_start = false)
        source = CartesianIndex(2, 2)
        target = CartesianIndex(2, 3)
        create_context = CorePotts._ProposalEvaluationContext(
            integrator.runtime,
            source,
            target,
            Int32(2),
            Int32(1),
            1,
            0,
        )
        CorePotts._emit_accepted_copy_stage!(
            integrator.runtime, create_context
        )
        transactions = integrator.runtime.stage_buffers.relationship_transactions
        CorePotts._reset_relationship_transactions!(
            transactions, integrator.runtime.relationships
        )
        reset_bytes = @allocated CorePotts._reset_relationship_transactions!(
            transactions, integrator.runtime.relationships
        )
        CorePotts._emit_accepted_copy_groups!(
            integrator.runtime.stage_buffers.accepted_copy,
            integrator.runtime.program.stage_plan.accepted_copy,
            create_context,
        )
        CorePotts._reset_relationship_transactions!(
            transactions, integrator.runtime.relationships
        )
        emit_bytes = @allocated CorePotts._emit_accepted_copy_groups!(
            integrator.runtime.stage_buffers.accepted_copy,
            integrator.runtime.program.stage_plan.accepted_copy,
            create_context,
        )
        CorePotts._prepare_relationship_transactions!(
            transactions,
            integrator.runtime.cell_kinds,
            integrator.runtime.cell_generations,
            integrator.runtime.program.relationships,
        )
        CorePotts._reset_relationship_transactions!(
            transactions, integrator.runtime.relationships
        )
        CorePotts._emit_accepted_copy_groups!(
            integrator.runtime.stage_buffers.accepted_copy,
            integrator.runtime.program.stage_plan.accepted_copy,
            create_context,
        )
        prepare_bytes = @allocated CorePotts._prepare_relationship_transactions!(
            transactions,
            integrator.runtime.cell_kinds,
            integrator.runtime.cell_generations,
            integrator.runtime.program.relationships,
        )
        @test (reset_bytes, emit_bytes, prepare_bytes) == (0, 0, 0)
        @test Core.Compiler.return_type(
            CorePotts._emit_accepted_copy_stage!,
            Tuple{typeof(integrator.runtime), typeof(create_context)},
        ) === typeof(integrator.runtime.stage_buffers.accepted_copy)
        @test _g3_scripted_attempt!(
            integrator.runtime, source, target, 0.5
        )
        elastic_state, score_state = integrator.runtime.relationships
        @test count(score_state.active) == 1
        @test count(elastic_state.active) == 1
        @test map(values -> values[1], score_state.payload) == (1.5,)
        @test map(values -> values[1], elastic_state.payload) == (3.0, 0.0)
        CorePotts._execute_after_mcs_stage!(integrator.runtime)
        @test @allocated(
            CorePotts._execute_after_mcs_stage!(integrator.runtime)
        ) == 0
        @test map(values -> values[1], score_state.payload) == (4.5,)
        @test map(values -> values[1], elastic_state.payload) == (3.0, 0.0)

        saved = checkpoint(integrator)
        resumed = init(
            problem;
            checkpoint = saved,
            save_start = false,
            observables = (:g3_score_degree, :g3_elastic_degree),
        )
        @test resumed.u[:g3_score_degree] == 1
        @test resumed.u[:g3_elastic_degree] == 1
        @test resumed.runtime.relationships[1].payload == elastic_state.payload
        @test resumed.runtime.relationships[2].payload == score_state.payload
        @test resumed.runtime.relationships[1].active == elastic_state.active
        @test resumed.runtime.relationships[2].active == score_state.active
    end
end
