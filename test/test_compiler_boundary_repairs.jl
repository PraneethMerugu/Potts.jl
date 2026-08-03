struct AdversarialPayload end

struct StaticOverrideOperation end
@inline (::StaticOverrideOperation)(value) = value

const StaticOverrideExpression = CorePotts.OperationExpression{
    StaticOverrideOperation,
    Tuple{CorePotts.LiteralExpression{Float64}},
}

@inline _boundary_override_value(context, value) =
    context isa CorePotts.HamiltonianEvaluationContext &&
    context.view isa CorePotts.AfterProposalView ? value : 0.0

@inline CorePotts.evaluate_static(
    ::CorePotts.StaticEvaluator{StaticOverrideExpression}, context
) = _boundary_override_value(context, 12345.0)

@inline CorePotts.evaluate_expression(
    ::StaticOverrideExpression, context
) = _boundary_override_value(context, 23456.0)

@inline CorePotts.execute_operation(
    ::StaticOverrideOperation, arguments::Tuple, context
) = _boundary_override_value(context, 34567.0)

@testset "relationship composition and endpoint contracts" begin
    relationship_a = CellKind(:a; extinction = RetireAtZero())
    relationship_b = CellKind(:b; extinction = RetireAtZero())
    relationship_medium = MediumKind(:medium)
    relationship_links = RelationshipState(
        :links;
        endpoints = Undirected(relationship_a, relationship_a),
        capacity = 4,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    @named relationship_child = PottsSystem(statements = StatementSet((
        Lattice((5, 5); relations = (proposal = VonNeumann(),)),
        relationship_a,
        relationship_b,
        relationship_medium,
        relationship_links,
        Protocol(Sweep(); name = :main),
    )))
    direct = compile(
        complete(relationship_child);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @named relationship_parent = PottsSystem()
    composed = compile(
        complete(compose(relationship_parent, [relationship_child]));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test size(direct.core_program.proposal_offsets) ==
          size(composed.core_program.proposal_offsets)
    @test length(direct.core_program.relationships) ==
          length(composed.core_program.relationships) == 1
    relationship_report = only(composed.reports.relationship_states)
    endpoint_policy = only(composed.relationship_endpoint_policies)
    @test relationship_report.name === :relationship_child₊links
    @test endpoint_policy.identity == relationship_report.identity
    @test endpoint_policy.slot == 1
    @test endpoint_policy.direction === :undirected
    @test endpoint_policy.direction ===
          relationship_report.endpoints.direction
    @test (endpoint_policy.kind_a_name, endpoint_policy.kind_b_name) ==
          (
              relationship_report.endpoints.kind_a,
              relationship_report.endpoints.kind_b,
          )

    labels = zeros(Int32, 5, 5)
    labels[2, 2] = 1
    labels[4, 4] = 2
    invalid = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [relationship_a, relationship_b],
            medium = relationship_medium,
        ),
        values = [relationship_links => [(1, 2)]],
    )
    @test_throws ArgumentError PottsToolkit._core_initial_state(
        composed, invalid
    )
    valid = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [relationship_a, relationship_a],
            medium = relationship_medium,
        ),
        values = [relationship_links => [(1, 2)]],
    )
    valid_core = PottsToolkit._core_initial_state(composed, valid)
    valid_runtime = CorePotts.initialize_program(
        composed.core_program,
        valid_core,
        composed.core_program.parameter_defaults,
        UInt64(0x727),
        UInt32(1),
    )
    @test only(valid_runtime.relationships).active[1]

    directed_links = RelationshipState(
        :directed_links;
        endpoints = Directed(relationship_a, relationship_b),
        capacity = 2,
        maximum_degree = 1,
    )
    @named directed_model = PottsSystem(statements = StatementSet((
        relationship_a,
        relationship_b,
        directed_links,
    )))
    directed_error = try
        complete(directed_model)
        nothing
    catch caught
        caught
    end
    @test directed_error isa PottsToolkit.PottsValidationError
    @test only(directed_error.diagnostics).kind ===
          :unsupported_relationship_direction

    sibling_a = CellKind(:a; extinction = RetireAtZero())
    sibling_medium = MediumKind(:medium)
    @named left_relationships = PottsSystem(statements = StatementSet((
        RelationshipState(
            :links;
            endpoints = Undirected(sibling_a, sibling_a),
            capacity = 2,
            maximum_degree = 1,
        ),
    )))
    @named right_relationships = PottsSystem(statements = StatementSet((
        RelationshipState(
            :links;
            endpoints = Undirected(sibling_a, sibling_a),
            capacity = 2,
            maximum_degree = 1,
        ),
    )))
    @named relationship_root = PottsSystem(statements = StatementSet((
        Lattice((5, 5); relations = (proposal = VonNeumann(),)),
        sibling_a,
        sibling_medium,
        Protocol(Sweep(); name = :main),
    )))
    sibling_executable = compile(
        complete(compose(
            relationship_root, [left_relationships, right_relationships]
        ));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test Tuple(
        entry.name for entry in sibling_executable.reports.relationship_states
    ) == (:left_relationships₊links, :right_relationships₊links)
    @test getfield.(
        sibling_executable.relationship_endpoint_policies, :slot
    ) == Int32[1, 2]
    @test getfield.(
        sibling_executable.relationship_endpoint_policies, :identity
    ) == collect(getfield.(
        sibling_executable.reports.relationship_states, :identity
    ))
end

struct PoisonedParameters <: AbstractVector{Float64}
    values::Vector{Float64}
end

Base.IndexStyle(::Type{PoisonedParameters}) = IndexLinear()
Base.size(parameters::PoisonedParameters) = size(parameters.values)
Base.getindex(parameters::PoisonedParameters, index::Int) =
    parameters.values[index]

@inline CorePotts.evaluator_parameters(
    context::CorePotts.EvaluatorProbeContext{PoisonedParameters, V, S, W}
) where {V, S, W} = fill(-1.0, length(context.parameters))

function CorePotts.descriptor_adapt(
        to,
        ::CorePotts.ProposalDescriptor{
            E, A, S, H, W, R, AdversarialPayload,
        },
    ) where {E, A, S, H, W, R}
    error("extension-owned descriptor adaptation entered production")
end

@inline function _boundary_descriptor_delta(descriptor, context)
    return CorePotts._compiled_hamiltonian_delta(
        descriptor.evaluator,
        descriptor.role,
        context,
        context.runtime.program.descriptor_plan.domain_resources,
    )
end

function _boundary_runtime(executable, ownership, cell_kinds; relationships = ())
    initial = CorePotts.ProgramInitialState(
        ownership,
        cell_kinds;
        scalar_type = eltype(executable.core_program.parameter_defaults),
        relationships,
    )
    return CorePotts.initialize_program(
        executable.core_program,
        initial,
        executable.core_program.parameter_defaults,
        UInt64(0x721),
        UInt32(1),
    )
end

function _boundary_proposal_context(runtime, source, target, attempt = 1)
    return CorePotts._ProposalEvaluationContext(
        runtime,
        source,
        target,
        @inbounds(runtime.ownership[target]),
        @inbounds(runtime.ownership[source]),
        attempt,
        0,
    )
end

@testset "repaired compiler adversarial boundaries" begin
    @testset "contact Hamiltonians consume their bound relation" begin
        cell = CellKind(:relation_cell; extinction = RetireAtZero())
        medium = MediumKind(:relation_medium)
        @named relation_model = PottsSystem(statements = StatementSet((
            Lattice(
                (5, 5);
                relations = (
                    proposal = VonNeumann(),
                    contact = VonNeumann(),
                    surface = Moore(),
                ),
            ),
            cell,
            medium,
            ContactEnergy(
                [(cell ↔ medium) => 3.0]; relation = :surface,
            ),
            Protocol(Sweep(); name = :main),
        )))
        executable = compile(
            complete(relation_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        ownership = zeros(Int32, 5, 5)
        ownership[3, 3] = 1
        runtime = _boundary_runtime(executable, ownership, Int16[2])
        context = _boundary_proposal_context(
            runtime, CartesianIndex(3, 3), CartesianIndex(3, 4)
        )
        plan = executable.core_program.descriptor_plan
        contributions = zeros(Float64, length(plan.source_table))
        CorePotts.evaluate_hamiltonian_contributions!(
            contributions, plan, context
        )
        local_delta = CorePotts.fold_hamiltonian_contributions(
            plan, contributions
        )

        moore = Tuple(
            CartesianIndex(row, column)
            for row in -1:1 for column in -1:1
            if !(row == 0 && column == 0)
        )
        function independent_contact_energy(labels)
            linear = LinearIndices(labels)
            seen = Set{Tuple{Int, Int}}()
            energy = 0.0
            for site in CartesianIndices(labels), offset in moore
                neighbor = CartesianIndex(
                    mod1(site[1] + offset[1], size(labels, 1)),
                    mod1(site[2] + offset[2], size(labels, 2)),
                )
                contact = minmax(linear[site], linear[neighbor])
                contact in seen && continue
                push!(seen, contact)
                labels[site] == labels[neighbor] || (energy += 3.0)
            end
            return energy
        end
        after = copy(ownership)
        after[context.target] = context.new_owner
        @test local_delta ==
              independent_contact_energy(after) -
              independent_contact_energy(ownership)
        contact_role = only([
            descriptor.role
            for group in plan.groups
            for descriptor in group.launch.instances
            if descriptor.role isa CorePotts.HamiltonianRole
        ])
        @test contact_role.affected.maximum == 8
    end

    @testset "Hamiltonian state reads honor representation banks" begin
        schema(name, element_type) = CorePotts.StateBlockSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            :site,
            element_type,
            (1,),
            1,
            :structure_of_arrays,
            :provided_or_zero,
            :shape_and_finite,
            :logical,
            :preserve,
            :declared,
            :bounded_write,
            :adapt_storage,
            :copy,
            :logical_copy,
            :qualified,
            true,
        )
        layout = CorePotts.StateLayout([
            schema(:first_bank, Float64),
            schema(:second_bank, Float32),
        ])
        auxiliary = CorePotts.allocate_auxiliary_state(
            layout, ([11.0], Float32[22])
        )
        handle = only(
            entry.handle
            for entry in layout.entries
            if CorePotts.handle_bank(entry.handle) == 2
        )
        runtime = (
            parameters = Float64[],
            stored_states = (first = [11.0], second = [22.0]),
            descriptor_state = auxiliary,
        )
        view = CorePotts.BeforeProposalView(
            runtime, Int32(1), Int32(1), Int32(1)
        )
        context = CorePotts.HamiltonianEvaluationContext(
            view, Int32(1), nothing
        )
        @test CorePotts.handle_slot(handle) == 1
        @test CorePotts.state_value(context, handle, 1) == 22
    end

    @testset "extension payloads cannot replace compiled evaluation" begin
        cell = CellKind(:payload_cell; extinction = RetireAtZero())
        medium = MediumKind(:payload_medium)
        anchor = SiteBinding(:payload_site)
        @named payload_model = PottsSystem(statements = StatementSet((
            Lattice((3, 3); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            HamiltonianTerm(
                :payload_energy;
                domain = sites(:lattice),
                anchor,
                expression = 5.0 * occupancy(cell, anchor),
                mechanism = :external_probe,
            ),
            Protocol(Sweep(); name = :main),
        )))
        executable = compile(
            complete(payload_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        original_plan = executable.core_program.descriptor_plan
        original = only(only(original_plan.groups).launch.instances)
        adversarial = CorePotts.ProposalDescriptor(
            original.evaluator,
            original.access,
            original.support,
            original.state_handles,
            original.workspace_handles,
            original.role,
            original.source_handle,
            AdversarialPayload(),
        )
        groups = PottsToolkit._descriptor_groups([adversarial])
        adapted = CorePotts.adapt_descriptor_launch(
            nothing, only(groups)
        )
        @test only(adapted.instances).evaluator === adversarial.evaluator
        adversarial_plan = CorePotts.DescriptorExecutionPlan(
            groups,
            original_plan.state_layout,
            original_plan.workspace_layout,
            original_plan.constraints,
            original_plan.source_table,
            original_plan.occurrence_count,
            original_plan.fingerprint,
            original_plan.domain_resources,
        )
        ownership = zeros(Int32, 3, 3)
        ownership[2, 2] = 1
        runtime = _boundary_runtime(executable, ownership, Int16[2])
        context = _boundary_proposal_context(
            runtime, CartesianIndex(2, 2), CartesianIndex(2, 3)
        )
        contributions = zeros(Float64, length(adversarial_plan.source_table))
        CorePotts.evaluate_hamiltonian_contributions!(
            contributions, adversarial_plan, context
        )
        @test CorePotts.fold_hamiltonian_contributions(
            adversarial_plan, contributions
        ) == 5.0
    end

    @testset "public evaluator dispatch cannot replace production" begin
        cell = CellKind(:closed_evaluator_cell; extinction = RetireAtZero())
        medium = MediumKind(:closed_evaluator_medium)
        anchor = SiteBinding(:closed_evaluator_site)
        @named closed_evaluator_model = PottsSystem(
            statements = StatementSet((
                Lattice((3, 3); relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                HamiltonianTerm(
                    :closed_evaluator_energy;
                    domain = sites(:lattice),
                    anchor,
                    expression = 5.0 * occupancy(cell, anchor),
                ),
                Protocol(Sweep(); name = :main),
            )),
        )
        executable = compile(
            complete(closed_evaluator_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        ownership = zeros(Int32, 3, 3)
        ownership[2, 2] = 1
        runtime = _boundary_runtime(executable, ownership, Int16[2])
        proposal = _boundary_proposal_context(
            runtime, CartesianIndex(2, 2), CartesianIndex(2, 3)
        )
        role = only(only(
            executable.core_program.descriptor_plan.groups
        ).launch.instances).role
        evaluator = CorePotts.StaticEvaluator(
            CorePotts.OperationExpression(
                StaticOverrideOperation(),
                CorePotts.LiteralExpression(5.0),
            ),
        )
        before = CorePotts.BeforeProposalView(
            runtime,
            proposal.target,
            proposal.old_owner,
            proposal.new_owner,
        )
        after = CorePotts.AfterProposalView(
            runtime,
            proposal.target,
            proposal.old_owner,
            proposal.new_owner,
        )
        before_context = CorePotts.HamiltonianEvaluationContext(
            before, proposal.target, proposal
        )
        after_context = CorePotts.HamiltonianEvaluationContext(
            after, proposal.target, proposal
        )
        @test CorePotts.evaluate_static(evaluator, after_context) -
              CorePotts.evaluate_static(evaluator, before_context) == 12345.0
        @test CorePotts.evaluate_expression(
            evaluator.expression, after_context
        ) == 23456.0
        @test CorePotts.execute_operation(
            StaticOverrideOperation(), (5.0,), after_context
        ) == 34567.0
        @test CorePotts._compiled_hamiltonian_delta(
            evaluator,
            role,
            proposal,
            executable.core_program.descriptor_plan.domain_resources,
        ) == 0.0
    end

    @testset "public parameter access cannot replace production" begin
        @parameters closed_weight = 5.0 positive_scale = 2.0
        cell = CellKind(:closed_parameter_cell; extinction = RetireAtZero())
        medium = MediumKind(:closed_parameter_medium)
        anchor = SiteBinding(:closed_parameter_site)
        @named closed_parameter_model = PottsSystem(
            statements = StatementSet((
                Lattice((3, 3); relations = (proposal = VonNeumann(),)),
                cell,
                medium,
                HamiltonianTerm(
                    :closed_parameter_energy;
                    domain = sites(:lattice),
                    anchor,
                    expression = closed_weight * occupancy(cell, anchor),
                ),
                HamiltonianTerm(
                    :closed_parameter_constraint;
                    domain = sites(:lattice),
                    anchor,
                    expression = log(positive_scale),
                ),
                Protocol(Sweep(); name = :main),
            )),
            parameters = [closed_weight, positive_scale],
        )
        executable = compile(
            complete(closed_parameter_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        plan = executable.core_program.descriptor_plan
        function has_parameter(expression, index)
            expression isa CorePotts.ParameterExpression &&
                return expression.index == index
            expression isa CorePotts.OperationExpression || return false
            return any(
                argument -> has_parameter(argument, index),
                expression.arguments,
            )
        end
        descriptor = only([
            descriptor
            for group in plan.groups
            for descriptor in group.launch.instances
            if has_parameter(descriptor.evaluator.expression, 1)
        ])
        ownership = zeros(Int32, 3, 3)
        ownership[2, 2] = 1
        runtime = _boundary_runtime(executable, ownership, Int16[2])
        proposal = _boundary_proposal_context(
            runtime, CartesianIndex(2, 2), CartesianIndex(2, 3)
        )
        @test _boundary_descriptor_delta(descriptor, proposal) == 5.0

        constraint = only(only(plan.constraints).instances)
        public_probe = CorePotts.EvaluatorProbeContext(
            PoisonedParameters(Float64[5.0, 2.0]), NamedTuple()
        )
        @test CorePotts.evaluate_static(
            constraint.evaluator, public_probe
        ) == -1.0
        @test CorePotts.validate_parameters(
            plan, Float64[5.0, 2.0]
        ) === nothing
    end

    @testset "cell domains exclude extinct after-view anchors" begin
        cell = CellKind(:extinct_cell; extinction = RetireAtZero())
        medium = MediumKind(:extinct_medium)
        @named extinction_model = PottsSystem(statements = StatementSet((
            Lattice((3, 3); boundary = Closed()),
            cell,
            medium,
            Volume(cell; target = 2.0, strength = 3.0),
            Protocol(Sweep(); name = :main),
        )))
        executable = compile(
            complete(extinction_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        ownership = zeros(Int32, 3, 3)
        ownership[2, 2] = 1
        runtime = _boundary_runtime(executable, ownership, Int16[2])
        context = _boundary_proposal_context(
            runtime, CartesianIndex(1, 2), CartesianIndex(2, 2)
        )
        descriptor = only(only(
            executable.core_program.descriptor_plan.groups
        ).launch.instances)
        @test _boundary_descriptor_delta(descriptor, context) == -3.0
    end

    @testset "relationship energies are total at endpoint extinction" begin
        cell = CellKind(:linked_cell; extinction = RetireAtZero())
        medium = MediumKind(:linked_medium)
        links = RelationshipState(
            :links;
            endpoints = Undirected(cell, cell),
            payload = (strength = 2.0, target = 1.0, maximum = 8.0),
            capacity = 64,
            maximum_degree = 2,
            lifecycle = RemoveWithEndpoint(),
        )
        edge = RelationshipBinding(:link, links)
        @named relationship_model = PottsSystem(statements = StatementSet((
            Lattice((5, 3); boundary = Closed()),
            cell,
            medium,
            links,
            RelationshipEnergy(
                :link_energy,
                edge,
                edge.strength * (
                    distance(
                        unwrapped_center(edge.a),
                        unwrapped_center(edge.b),
                    ) - edge.target
                )^2,
            ),
            Protocol(Sweep(); name = :main),
        )))
        executable = compile(
            complete(relationship_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        ownership = zeros(Int32, 5, 3)
        ownership[2, 2] = 1
        ownership[4, 2] = 2
        initial = PottsInitialState(
            ownership = LabelledCells(
                ownership;
                cells = [cell, cell],
                medium,
            ),
            values = [links => [(1, 2)]],
        )
        core_initial = PottsToolkit._core_initial_state(executable, initial)
        runtime = CorePotts.initialize_program(
            executable.core_program,
            core_initial,
            executable.core_program.parameter_defaults,
            UInt64(0x722),
            UInt32(1),
        )
        descriptor = only([
            descriptor
            for group in executable.core_program.descriptor_plan.groups
            for descriptor in group.launch.instances
            if descriptor.role isa CorePotts.HamiltonianRole
        ])
        context = _boundary_proposal_context(
            runtime, CartesianIndex(1, 2), CartesianIndex(2, 2)
        )
        before_energy = 2.0 * (2.0 - 1.0)^2
        @test _boundary_descriptor_delta(descriptor, context) == -before_energy
        @test size(only(runtime.relationships).incident_edges) ==
            (2, length(runtime.cell_kinds))
        @test only(runtime.relationships).degree[1:2] == Int16[1, 1]
        @test all(iszero, only(runtime.relationships).degree[3:end])
    end

    @testset "relationship affected anchors are a canonical bounded union" begin
        cell = CellKind(:union_cell; extinction = RetireAtZero())
        medium = MediumKind(:union_medium)
        links = RelationshipState(
            :union_links;
            endpoints = Undirected(cell, cell),
            payload = (strength = 1.25, target = 1.0, maximum = 20.0),
            capacity = 64,
            maximum_degree = 2,
            lifecycle = RemoveWithEndpoint(),
        )
        edge = RelationshipBinding(:union_edge, links)
        @named union_model = PottsSystem(statements = StatementSet((
            Lattice((7, 5); boundary = Closed()),
            cell,
            medium,
            links,
            RelationshipEnergy(
                :union_energy,
                edge,
                edge.strength * (
                    distance(
                        unwrapped_center(edge.a),
                        unwrapped_center(edge.b),
                    ) - edge.target
                )^2,
            ),
            Protocol(Sweep(); name = :main),
        )))
        executable = compile(
            complete(union_model);
            engine = SequentialEngine(),
            backend = CPUBackend(),
            scalar_type = Float64,
        )
        ownership = zeros(Int32, 7, 5)
        ownership[3, 2:3] .= 1
        ownership[4, 2:3] .= 2
        ownership[6, 3:4] .= 3
        initial = PottsInitialState(
            ownership = LabelledCells(
                ownership;
                cells = [cell, cell, cell],
                medium,
            ),
            values = [links => [(1, 2), (1, 3), (2, 3)]],
        )
        core_initial = PottsToolkit._core_initial_state(executable, initial)
        runtime = CorePotts.initialize_program(
            executable.core_program,
            core_initial,
            executable.core_program.parameter_defaults,
            UInt64(0x723),
            UInt32(1),
        )
        descriptor = only(only(
            executable.core_program.descriptor_plan.groups
        ).launch.instances)
        context = _boundary_proposal_context(
            runtime, CartesianIndex(4, 2), CartesianIndex(3, 2)
        )
        function global_relationship_energy(labels)
            centers = Dict{Int32, NTuple{2, Float64}}()
            for owner in Int32(1):Int32(3)
                sites = findall(==(owner), labels)
                centers[owner] = ntuple(2) do dimension
                    sum(site[dimension] - 0.5 for site in sites) /
                        length(sites)
                end
            end
            return sum(pair -> begin
                a, b = pair
                first_center = centers[a]
                second_center = centers[b]
                distance = sqrt(sum(
                    (first_center[index] - second_center[index])^2
                    for index in 1:2
                ))
                1.25 * (distance - 1.0)^2
            end, ((Int32(1), Int32(2)),
                  (Int32(1), Int32(3)),
                  (Int32(2), Int32(3))))
        end
        after = copy(ownership)
        after[context.target] = context.new_owner
        expected = global_relationship_energy(after) -
                   global_relationship_energy(ownership)
        @test _boundary_descriptor_delta(descriptor, context) ≈ expected
        @test descriptor.role.affected.maximum == 4
        @test only(runtime.relationships).incident_edges[:, 1] == Int32[1, 2]
        @test only(runtime.relationships).incident_edges[:, 2] == Int32[1, 3]
        @test only(runtime.relationships).incident_edges[:, 3] == Int32[2, 3]
        _boundary_descriptor_delta(descriptor, context)
        @test @allocated(
            _boundary_descriptor_delta(descriptor, context)
        ) == 0
    end

    @test !isdefined(CorePotts, :ProgramCall)
    @test !isdefined(CorePotts, :descriptor_evaluate_energy)
    @test !isdefined(CorePotts, :descriptor_evaluate_proposal)
    @test !isdefined(PottsToolkit, :_lower_program_expression)
end

@testset "qualified source graph owns composed lowering" begin
    @variables boundary_composed_t boundary_composed_state(boundary_composed_t)
    composed_cell = CellKind(:cell; extinction = RetireAtZero())
    composed_medium = MediumKind(:medium)
    composed_state = SiteState(
        boundary_composed_state;
        name = :state,
        owner = composed_cell,
        initial = 0.0,
        lifecycle = PreserveOnOwnershipChange(),
    )
    @named boundary_child = PottsSystem(
        statements = StatementSet((
            Lattice(
                (5, 5);
                relations = (
                    proposal = Moore(),
                    contact = VonNeumann(),
                ),
            ),
            composed_cell,
            composed_medium,
            composed_state,
            ContactEnergy(
                [(composed_cell ↔ composed_medium) => 1.0];
                relation = :contact,
            ),
            Observation(:state_snapshot, boundary_composed_state),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [boundary_composed_state],
        independent_variables = [boundary_composed_t],
    )
    direct = compile(
        complete(boundary_child);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @named boundary_parent = PottsSystem()
    composed = compile(
        complete(compose(boundary_parent, [boundary_child]));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )

    @test size(direct.core_program.proposal_offsets, 2) == 8
    @test size(composed.core_program.proposal_offsets, 2) == 8
    @test direct.core_program.descriptor_plan.domain_resources.contact_counts ==
          composed.core_program.descriptor_plan.domain_resources.contact_counts
    @test 4 in composed.core_program.descriptor_plan.domain_resources.contact_counts
    @test composed.reports.kinds == (:boundary_child₊medium, :boundary_child₊cell)
    @test only(composed.observations).name === :boundary_child₊state_snapshot

    labels = zeros(Int32, 5, 5)
    labels[3, 3] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [composed_cell],
            medium = composed_medium,
        ),
        values = [boundary_composed_state => ones(5, 5)],
    )
    runtime = init(PottsProblem(
        composed, initial, (0, 1); seed = 0x724
    ); observables = (:boundary_child₊state_snapshot,)).runtime
    handle = only(composed.reports.states).handle
    @test CorePotts.state_block(runtime.descriptor_state, handle).values ==
          ones(5, 5)

    @variables boundary_left_state(boundary_composed_t) boundary_right_state(boundary_composed_t)
    left_cell = CellKind(:cell; extinction = RetireAtZero())
    right_cell = CellKind(:cell; extinction = RetireAtZero())
    @named left = PottsSystem(
        statements = StatementSet((
            left_cell,
            SiteState(
                boundary_left_state;
                name = :state,
                owner = left_cell,
                initial = 0.0,
                lifecycle = PreserveOnOwnershipChange(),
            ),
        )),
        unknowns = [boundary_left_state],
        independent_variables = [boundary_composed_t],
    )
    @named right = PottsSystem(
        statements = StatementSet((
            right_cell,
            SiteState(
                boundary_right_state;
                name = :state,
                owner = right_cell,
                initial = 0.0,
                lifecycle = PreserveOnOwnershipChange(),
            ),
        )),
        unknowns = [boundary_right_state],
        independent_variables = [boundary_composed_t],
    )
    sibling_medium = MediumKind(:medium)
    @named sibling_root = PottsSystem(
        statements = StatementSet((
            Lattice((5, 5); relations = (proposal = VonNeumann(),)),
            sibling_medium,
            Protocol(Sweep(); name = :main),
        )),
        independent_variables = [boundary_composed_t],
    )
    siblings = compile(
        complete(compose(sibling_root, [left, right]));
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    @test siblings.reports.kinds == (:medium, :left₊cell, :right₊cell)
    @test Set(entry.name for entry in siblings.reports.states) ==
          Set((:left₊state, :right₊state))
    ambiguous = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [:cell], medium = sibling_medium
        ),
    )
    @test_throws ArgumentError PottsToolkit._core_initial_state(
        siblings, ambiguous
    )
    qualified = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [:left₊cell], medium = sibling_medium
        ),
        values = [boundary_left_state => fill(2.0, 5, 5)],
    )
    sibling_initial = PottsToolkit._core_initial_state(siblings, qualified)
    @test sibling_initial.cell_kinds == Int16[2]
end
