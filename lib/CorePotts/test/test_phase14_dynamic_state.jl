using SciMLBase
using CorePotts: AcceptedCopyManaged, AcceptedCopyUpdate, AdaptiveStep,
    AlgebraicAssignment, AlgebraicConstraint, AngularMembrane, AtMCSEnd,
    CellDomain, CellDynamics, CellEndpoint, CellHistory, CompatibilityItem,
    ContinuousClock, ContinuousEvent, ContinuousModelAdapter, ContinuousSystem,
    ContinuousSystemState, CoupledAttemptWorkspace, CoupledPhase, CoupledState,
    CreateRelationship, DelayState, DelayStateStorage, DifferentialEquation,
    DirectLaw, EventAssignment, EventRuntimeState, EveryGlobal,
    EvolvingFieldState, ExactSample, ExactSemanticMapping, ExplicitEuler,
    FieldDynamics, FieldExchange, FillMembrane, FixedStep,
    FromExecutionSnapshot, FromTriggerSnapshot, GlobalClock, GlobalDomain,
    GlobalProperty, Heun, HistoryLagUnavailableError, InputRef, Lag,
    LifecyclePhase, MCSDuration, MCSPlan, MCSRange, MembraneProperty,
    MissingUntilFull, MorpheusSemanticProfile, MultirateSchedule,
    ObservationPhase, ObservationTransform, OnRising, OnceWhenTrue,
    PhaseObservation, PottsAttempts, PreserveAtSite, ProtocolStage, RK4,
    ReactionDiffusion, RecordSchema, RelationshipCapacity,
    RelationshipDynamics, RelationshipSet, RelationshipState,
    RemoveRelationship, RepeatInitialSample, RetuneRelationship, RootTrigger,
    SampledTrigger, SaturatingSubtract, ScheduledEvent, ScheduledLifecycle,
    ScheduledParameter, ScheduledPotts, ScheduledProcess, ScheduledSystem,
    SetTo, SiteDynamics, SiteProperty, StagedProtocol, StateVariable,
    SteadyStateAdvance, SymbolIdentity, SymbolMap, SymbolRef, SynchronousRule,
    SystemClock, UnsupportedContinuousProfile, Update, Uptake,
    adapt_continuous_model, advance_continuous_system!, advance_field!,
    apply_field_exchange!, apply_relationship_dynamics!, apply_site_dynamics!,
    apply_symbol_map!, continuous_profile_report, create_relationship!,
    delay_value, execute_event!, global_property_value, global_time,
    history_value, init_coupled, initialize_cell_history,
    initialize_global_property, initialize_membrane_property,
    initialize_site_property, locate_root, maybe_history_value,
    membrane_values, relationship_payload, retire_relationship_endpoint!,
    retune_relationship!, sample_delay!, sample_history!, scheduled_value,
    set_global_property!, set_membrane_values!, stage_for, stage_local_mcs

@testset "Phase 14 contract versions and source attempt budget" begin
    versions = phase14_contract_versions()
    @test versions.contract_set == v"2.0.0"
    @test (
        versions.state, versions.process, versions.plan,
        versions.lifecycle, versions.observation,
        versions.spatial_roles, versions.potts_algorithm_identities) ==
        ntuple(_ -> v"0.2.0", 7)
    @test scientific_contract_versions().freeze_status == :phase13_frozen
    @test AttemptsPerSite(16).multiplier == 16
    @test_throws ArgumentError AttemptsPerSite(0)

    fixture = _scientific_fixture(Float32, (4, 4))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    state = compile_scientific_state(fixture.state, fixture.domain, tracker)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    algorithm = BudgetedSequentialCPM(
        AttemptsPerSite(2); temperature = 1000.0f0)
    @test CorePotts._checked_attempt_total(algorithm, 7) == 14
    @test CorePotts._attempt_total(algorithm, 7) == 14
    @test_throws OverflowError CorePotts._checked_attempt_total(
        algorithm, typemax(Int))
    integrator = init_scientific(state, fixture.proposal_relation,
        components, algorithm; seed = 0x1401)
    step!(integrator)
    report = current_mcs_report(integrator)
    @test report.activated_attempts == 2 * mutable_site_count(fixture.domain)
    @test report.activated_attempts ==
          report.same_owner_no_ops + report.boundary_no_ops +
          report.immutable_recipient_no_ops + report.constraint_rejections +
          report.acceptance_rejections + report.accepted_copies
    @test algorithm_guarantees(algorithm).backend_contract ==
        (:cpu, :metal, :amdgpu)
    @test component_identity(SequentialCPM()).key == :sequential_cpm
    @test algorithm_guarantees(SequentialCPM()).mcs_normalization ==
          :exact_n_independent_attempts
end

@testset "Phase 14 site state and accepted-copy transaction hook" begin
    fixture = _scientific_fixture(Float32, (4, 4))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    property = SiteProperty(:activity; initial = 0.0f0,
        ownership = AcceptedCopyManaged())
    fill_checks = Ref(0)
    validated_fill = SiteProperty(:validated_fill; initial = 2.0f0,
        invariant = value -> begin
            fill_checks[] += 1
            value >= 0.0f0
        end,
        ownership = PreserveAtSite())
    @test fill_checks[] == 1
    validated_fill_state = initialize_site_property(
        validated_fill, zeros(UInt8, fixture.domain.dims))
    @test fill_checks[] == 1
    @test all(==(2.0f0), validated_fill_state.values)
    @test_throws ArgumentError SiteProperty(:invalid_activity;
        initial = -1.0f0,
        invariant = CorePotts.ActivityBounds(0.0f0, 10.0f0),
        ownership = AcceptedCopyManaged())
    @test_throws ArgumentError SiteProperty(:invalid_nothing;
        initial = nothing, invariant = !isnothing,
        ownership = PreserveAtSite())
    site_state = initialize_site_property(
        property, zeros(UInt8, fixture.domain.dims))
    update = AcceptedCopyUpdate(
        :activate, property; gained = SetTo(1.0f0))
    workspace = CoupledAttemptWorkspace((site_state,), (update,))
    integrator = init_scientific(compiled, fixture.proposal_relation,
        components, SequentialCPM(temperature = 1000.0f0);
        seed = 0x1410, algorithm_workspace = workspace)
    step!(integrator)
    report = current_mcs_report(integrator)
    @test report.accepted_copies > 0
    @test count(==(1.0f0), site_state.values) > 0

    decay = SiteDynamics(:decay, property;
        update = SaturatingSubtract(0.25f0))
    @test apply_site_dynamics!(site_state, decay, 1)
    @test all(value -> 0.0f0 <= value <= 0.75f0, site_state.values)
end

@testset "Phase 14 Wortel Act semantic-kernel vertical slice" begin
    fixture = _scientific_fixture(Float32, (6, 6))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    activity_relation = static_relation(
        SpatialQueryRole(), CorePotts.offsets(CorePotts.MooreTopology{2}());
        spacing = (1.0f0, 1.0f0))
    algorithm = BudgetedSequentialCPM(
        AttemptsPerSite(1); temperature = 20.0f0)
    program = ActivityProgram(
        maximum = 10.0f0,
        strength = 20.0f0,
        relation = activity_relation,
        algorithm = algorithm,
        observation_cadence = 1)
    runtime = realize_activity(
        program, lattice_storage(fixture.state))
    compiled_runtime = realize_activity(program, compiled)

    @test runtime.state.values === runtime.workspace.site_states[1].values
    @test runtime.state.values ===
          runtime.coupled_state.site_states[1].values
    @test CorePotts.KernelAbstractions.get_backend(runtime.state.values) ==
          CorePotts.KernelAbstractions.get_backend(lattice_storage(fixture.state))
    @test length(compiled_runtime.state.values) ==
          prod(fixture.domain.dims)
    @test CorePotts.KernelAbstractions.get_backend(
              compiled_runtime.state.values) ==
          CorePotts.KernelAbstractions.get_backend(
              compiled.potts.storage.ownership.tags)
    @test canonical_coupled_model(program) === program.semantic_model
    @test only(program.semantic_model.states).id == :activity
    @test Tuple(process.id for process in program.semantic_model.processes) ==
        (:activity_on_accept, :activity_bias, :activity_decay)
    @test Tuple(entry.kind for entry in program.semantic_model.plan.entries) ==
        (:potts, :process, :lifecycle, :observation, :stable_boundary)
    @test semantic_model_fingerprint(program.semantic_model) ==
        semantic_model_fingerprint(deepcopy(program.semantic_model))

    # Locate one real owner-changing proposal and verify the source formula against a
    # hand-computed geometric neighborhood reduction.
    attempt = nothing
    for site in 1:prod(fixture.domain.dims)
        for direction in 1:direction_count(fixture.proposal_relation)
            candidate = construct_copy_attempt(
                scientific_execution(compiled), compiled.domain,
                fixture.proposal_relation, site, direction;
                mcs = 1, semantic_id = site)
            if candidate.outcome === ActionableCopy &&
                    CorePotts.is_cell_owner(candidate.gaining)
                attempt = candidate
                break
            end
        end
        attempt === nothing || break
    end
    @test attempt !== nothing
    proposal = actionable_proposal(attempt)
    transaction = stage_copy_transaction(compiled, tracker, proposal)
    context = ScientificProposalContext(
        scientific_execution(compiled), transaction;
        algorithm_workspace = runtime.workspace)
    values = runtime.state.values
    fill!(values, 1.0f0)
    values[proposal.donor] = 4.0f0
    values[proposal.recipient] = 9.0f0

    function geometric_at(site, owner)
        scientific = scientific_execution(compiled)
        CorePotts._proposal_owner_at(scientific, site) == owner || return 0.0f0
        selected = Float32[values[site]]
        for direction in 1:direction_count(activity_relation)
            neighbor = realize_neighbor(
                scientific.domain, activity_relation, site, direction)
            neighbor.kind === MutableNeighbor || continue
            CorePotts._proposal_owner_at(scientific, neighbor.site) == owner ||
                continue
            push!(selected, values[Int(neighbor.site)])
        end
        any(iszero, selected) && return 0.0f0
        return prod(selected)^(1 / length(selected))
    end
    expected_delta = 20.0f0 * (
        geometric_at(proposal.recipient, proposal.losing) -
        geometric_at(proposal.donor, proposal.gaining)) / 10.0f0
    @test proposal_energy_change(
        program.hamiltonian, proposal, context) ≈ expected_delta
    values[proposal.donor] = 0.0f0
    @test CorePotts._activity_geometric_mean(
        program.hamiltonian, proposal.donor, proposal.gaining, context) == 0

    # Accepted finite-cell copies activate once. A noncommitted rejection and no-op
    # construction leave activity unchanged.
    fill!(values, 0.0f0)
    before_rejection = copy(values)
    proposal_energy_change(program.hamiltonian, proposal, context)
    @test values == before_rejection
    CorePotts.commit_accepted_copy_updates!(
        runtime.workspace, proposal, transaction, scientific_execution(compiled))
    @test values[proposal.recipient] == 10.0f0
    no_op = nothing
    for site in 1:prod(fixture.domain.dims)
        for direction in 1:direction_count(fixture.proposal_relation)
            candidate = construct_copy_attempt(
                scientific_execution(compiled), compiled.domain,
                fixture.proposal_relation, site, direction;
                mcs = 1, semantic_id = 99)
            if candidate.outcome === SameOwnerAttempt
                no_op = candidate
                break
            end
        end
        no_op === nothing || break
    end
    @test no_op !== nothing
    before_no_op = copy(values)
    @test values == before_no_op

    fill!(values, 0.0f0)
    components = ScientificComponentSet(
        energies = (
            fixture.volume, fixture.contact, fixture.boundary,
            program.hamiltonian))
    potts = init_scientific(
        compiled, fixture.proposal_relation, components, algorithm;
        seed = 0x14a0, algorithm_workspace = runtime.workspace)
    coupled = init_coupled(
        potts, runtime.plan, runtime.coupled_state;
        semantic_model = program.semantic_model)
    @test step!(coupled) === coupled
    @test coupled.mcs == 1
    @test all(value -> 0.0f0 <= value <= 9.0f0, runtime.state.values)
    @test only(coupled.observations.records).observation == :activity_summary
    @test coupled.observations.last_published[:activity_summary] == 1
    @test coupled_manifest(coupled).plan ==
        CorePotts._semantic_record(program.semantic_model)
    @test inspect_coupled(coupled).semantic_model ==
        CorePotts._semantic_record(program.semantic_model)

    checkpoint = capture_checkpoint(coupled)
    restored = restore_checkpoint(checkpoint, coupled)
    step!(coupled)
    step!(restored)
    @test logical_state(restored.potts)._owners ==
        logical_state(coupled.potts)._owners
    @test restored.state.site_states[1].values ==
        coupled.state.site_states[1].values
    @test capture_checkpoint(restored).state_fingerprint ==
        capture_checkpoint(coupled).state_fingerprint

    unsupported_backend = BackendCapabilities(
        AMDGPUFamily, DeferredBackend, false, false, true, true, ())
    rejected_state = deepcopy(runtime.coupled_state)
    before_preflight = copy(rejected_state.site_states[1].values)
    @test_throws UnsupportedCoupledCapabilities preflight_coupled(
        runtime.plan, rejected_state, unsupported_backend)
    @test rejected_state.site_states[1].values == before_preflight
end

@testset "Phase 14 history and relationship state" begin
    history = CellHistory(:centroid_history; source = :centroid,
        length = 3, initial = MissingUntilFull())
    generations = [CellGeneration(1), CellGeneration(1)]
    state = initialize_cell_history(history, Float32[0, 0], generations)
    @test !maybe_history_value(
        state, CellID(1), CellGeneration(1), Lag(0)).available
    sample_history!(state, Float32[1, 2], Bool[true, true], generations, 1)
    sample_history!(state, Float32[3, 4], Bool[true, true], generations, 2)
    @test history_value(state, CellID(1), CellGeneration(1), Lag(0)) == 3
    @test history_value(state, CellID(1), CellGeneration(1), Lag(1)) == 1
    @test_throws HistoryLagUnavailableError history_value(
        state, CellID(1), CellGeneration(1), Lag(2))
    @test_throws ArgumentError history_value(
        state, CellID(1), CellGeneration(2), Lag(0))

    declaration = RelationshipSet(:junctions;
        edge = Float32, maximum_degree = 2,
        capacity = RelationshipCapacity(2))
    relationships = RelationshipState(declaration)
    first_endpoint = CellEndpoint(CellID(1), CellGeneration(1))
    second_endpoint = CellEndpoint(CellID(2), CellGeneration(1))
    create_relationship!(relationships, second_endpoint, first_endpoint, 1.0f0)
    @test only(relationships.edges).left == first_endpoint
    @test relationship_payload(
        relationships, first_endpoint, second_endpoint) == 1.0f0
    retune_relationship!(
        relationships, first_endpoint, second_endpoint, 2.0f0)
    @test relationship_payload(
        relationships, first_endpoint, second_endpoint) == 2.0f0
    retire_relationship_endpoint!(relationships, first_endpoint)
    @test isempty(relationships.edges)

    ownership = LogicalPottsState(
        reshape(OwnerRef[CellOwner(1), CellOwner(2)], 2, 1),
        CellCapacity(2);
        cell_types = Dict(
            CellID(1) => CellTypeID(1), CellID(2) => CellTypeID(1)),
        medium_domains = [MediumID(1)])
    create_law = DirectLaw(:create_junction,
        (graph, potts, mcs) -> (
            CreateRelationship(
                first_endpoint, second_endpoint, 3.0f0),
        ))
    dynamics = RelationshipDynamics(
        :junction_creation, declaration; law = create_law)
    apply_relationship_dynamics!(
        relationships, dynamics, ownership, 1)
    @test relationship_payload(
        relationships, first_endpoint, second_endpoint) == 3.0f0
    conflicting = DirectLaw(:conflicting_junction_updates,
        (graph, potts, mcs) -> (
            RetuneRelationship(
                first_endpoint, second_endpoint, 4.0f0),
            RemoveRelationship(first_endpoint, second_endpoint),
        ))
    @test_throws ArgumentError apply_relationship_dynamics!(
        relationships,
        RelationshipDynamics(
            :junction_conflict, declaration; law = conflicting),
        ownership, 2)
end

@testset "Phase 14 coupled checkpoint all authoritative state families" begin
    fixture = _scientific_fixture(Float32, (4, 4))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    potts = init_scientific(compiled, fixture.proposal_relation,
        components, SequentialCPM(temperature = 10.0f0); seed = 0x1413)

    site_declaration = SiteProperty(
        :checkpoint_site; initial = 1.0f0,
        ownership = PreserveAtSite())
    site_state = initialize_site_property(
        site_declaration, zeros(UInt8, 4, 4))
    history_declaration = CellHistory(:checkpoint_history;
        source = :target_volume, length = 2,
        initial = RepeatInitialSample())
    history_state = initialize_cell_history(
        history_declaration, Float32[4, 4],
        [CellGeneration(1), CellGeneration(1)])
    relationship_declaration = RelationshipSet(
        :checkpoint_edges; edge = Float32,
        maximum_degree = 2, capacity = RelationshipCapacity(2))
    relationship_state = RelationshipState(relationship_declaration)
    create_relationship!(relationship_state,
        CellEndpoint(CellID(1), CellGeneration(1)),
        CellEndpoint(CellID(2), CellGeneration(1)), 2.0f0)
    field_state = EvolvingFieldState(
        :checkpoint_field, ones(Float32, 4, 4))
    global_state = initialize_global_property(
        GlobalProperty(:checkpoint_global; initial = 2.0f0))
    membrane_declaration = MembraneProperty(
        :checkpoint_membrane, :cells;
        initial = FillMembrane(0.5f0),
        discretization = AngularMembrane(8))
    membrane_state = initialize_membrane_property(
        membrane_declaration,
        [CellGeneration(1), CellGeneration(1)])

    plan = MCSPlan(
        PottsAttempts(), LifecyclePhase(), ObservationPhase())
    coupled = init_coupled(potts, plan, CoupledState(
        site_states = (site_state,),
        histories = (history_state,),
        relationships = (relationship_state,),
        fields = (field_state,),
        globals = (global_state,),
        membranes = (membrane_state,)))
    checkpoint = capture_checkpoint(coupled)
    @test checkpoint.mcs == 0
    @test Set(block.family for block in checkpoint.extension.blocks) ==
        Set((:site_property, :cell_history, :relationship_set,
            :evolving_field, :global_property, :membrane_property))

    fill!(site_state.values, 9.0f0)
    fill!(history_state.values, 9.0f0)
    empty!(relationship_state.edges)
    fill!(field_state.values, 9.0f0)
    set_global_property!(global_state, 9.0f0)
    fill!(membrane_state.values, 9.0f0)

    restored = restore_checkpoint(checkpoint, coupled)
    @test all(==(1.0f0), restored.state.site_states[1].values)
    @test all(==(4.0f0), restored.state.histories[1].values)
    @test length(restored.state.relationships[1].edges) == 1
    @test all(==(1.0f0), restored.state.fields[1].values)
    @test global_property_value(restored.state.globals[1]) == 2.0f0
    @test all(==(0.5f0), restored.state.membranes[1].values)

    store = CoupledMemoryCheckpointStore()
    write_checkpoint!(store, "stable", checkpoint)
    @test_throws ErrorException write_checkpoint!(
        store, "stable", checkpoint; fail_after = :payload)
    @test read_checkpoint(store, "stable").checksum == checkpoint.checksum
end

@testset "Phase 14 coupled plan, protocol, and completed-MCS publication" begin
    @test_throws ArgumentError MCSPlan(
        PottsAttempts(), ObservationPhase(), LifecyclePhase())
    @test_throws ArgumentError MCSPlan(
        PottsAttempts(), LifecyclePhase(), LifecyclePhase(), ObservationPhase())
    @test_throws ArgumentError StagedProtocol(
        ProtocolStage(:one; mcs = MCSRange(1, 3)),
        ProtocolStage(:two; mcs = MCSRange(3, 5)))

    protocol = StagedProtocol(
        ProtocolStage(:relax; mcs = MCSRange(1, 1)),
        ProtocolStage(:active; mcs = MCSRange(2, 3)))
    parameter = ScheduledParameter(:strength, protocol;
        relax = 1.0f0, active = 2.0f0)
    @test scheduled_value(parameter, stage_for(protocol, 2)) == 2.0f0
    @test stage_local_mcs(stage_for(protocol, 3), 3) == 2
    @test_throws ArgumentError stage_for(protocol, 4)

    fixture = _scientific_fixture(Float32, (4, 4))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    property = SiteProperty(:activity; initial = 0.0f0,
        ownership = AcceptedCopyManaged())
    site_state = initialize_site_property(
        property, zeros(UInt8, fixture.domain.dims))
    activation = AcceptedCopyUpdate(
        :activate, property; gained = SetTo(1.0f0))
    decay = SiteDynamics(:decay, property;
        update = SaturatingSubtract(0.25f0))
    workspace = CoupledAttemptWorkspace((site_state,), (activation,))
    potts = init_scientific(compiled, fixture.proposal_relation,
        components, SequentialCPM(temperature = 1000.0f0);
        seed = 0x1411, algorithm_workspace = workspace)
    plan = MCSPlan(
        PottsAttempts(on_accept = (activation,)),
        CoupledPhase(:activity_decay, Update(decay)),
        LifecyclePhase(),
        ObservationPhase())
    coupled = init_coupled(potts, plan,
        CoupledState(site_states = (site_state,)); protocol)
    @test step!(coupled) === coupled
    @test coupled.mcs == 1
    @test coupled.potts.mcs == 1
    @test coupled.stage == :relax
    @test coupled.stage_local_mcs == 1
    @test coupled.observations.completed_mcs == 1
    @test all(value -> 0.0f0 <= value <= 0.75f0, site_state.values)
    @test step!(coupled) === coupled
    @test coupled.mcs == 2
    @test coupled.stage == :active
end

@testset "Phase 14 general continuous systems and field coupling" begin
    global_state = initialize_global_property(
        GlobalProperty(:stimulus; initial = 1.0))
    set_global_property!(global_state, 2.0; semantic_time = 1)
    @test global_property_value(global_state) == 2.0
    @test global_state.semantic_time == 1

    membrane = MembraneProperty(:receptor, :cells;
        initial = FillMembrane(0.0),
        discretization = AngularMembrane(8))
    membrane_state = initialize_membrane_property(
        membrane, [CellGeneration(1), CellGeneration(1)];
        active = [true, false])
    set_membrane_values!(membrane_state,
        CellID(1), CellGeneration(1), ones(8))
    @test sum(membrane_values(
        membrane_state, CellID(1), CellGeneration(1))) == 8
    @test_throws ArgumentError membrane_values(
        membrane_state, CellID(1), CellGeneration(2))

    clock = ContinuousClock(:physical_time; per_mcs = 1.0, unit = :second)
    rhs = DirectLaw(:unit_decay, (state, parameters, inputs, time) -> -state.x)
    for method in (ExplicitEuler(), Heun(), RK4())
        system = ContinuousSystem(:decay;
            domain = GlobalDomain(),
            state = (StateVariable(:x),),
            statements = (DifferentialEquation(:x, rhs),),
            solver = FixedStep(method; substeps = 100),
            clock)
        state = ContinuousSystemState(system, (x = 1.0,))
        advance_continuous_system!(state, 1.0)
        tolerance = method isa ExplicitEuler ? 6e-3 : 1e-4
        @test isapprox(state.values.x, exp(-1); atol = tolerance)
        @test state.time == 1.0
    end

    synchronous = ContinuousSystem(:swap;
        domain = GlobalDomain(),
        state = (StateVariable(:x), StateVariable(:y)),
        statements = (
            SynchronousRule(:x, :y),
            SynchronousRule(:y, :x),
        ),
        solver = FixedStep(ExplicitEuler(); substeps = 1),
        clock)
    synchronous_state = ContinuousSystemState(
        synchronous, (x = 1.0, y = 2.0))
    advance_continuous_system!(synchronous_state, 1.0)
    @test synchronous_state.values == (x = 2.0, y = 1.0)

    @test_throws ArgumentError ContinuousSystem(:assignment_cycle;
        domain = GlobalDomain(),
        state = (StateVariable(:x), StateVariable(:y)),
        statements = (
            AlgebraicAssignment(:x, :y; reads = (:y,)),
            AlgebraicAssignment(:y, :x; reads = (:x,)),
        ),
        solver = FixedStep(ExplicitEuler(); substeps = 1),
        clock)

    dae = ContinuousSystem(:dae_profile;
        domain = GlobalDomain(),
        state = (StateVariable(:x),),
        statements = (AlgebraicConstraint(
            DirectLaw(:zero_residual, (state, time) -> state.x)),),
        solver = FixedStep(ExplicitEuler(); substeps = 1),
        clock)
    @test !continuous_profile_report(dae).executable
    @test_throws UnsupportedContinuousProfile advance_continuous_system!(
        ContinuousSystemState(dae, (x = 0.0,)), 1.0)

    adaptive = ContinuousSystem(:adaptive_profile;
        domain = GlobalDomain(),
        state = (StateVariable(:x),),
        statements = (DifferentialEquation(:x, rhs),),
        solver = AdaptiveStep(:reference;
            abstol = 1e-8, reltol = 1e-6),
        clock)
    @test !continuous_profile_report(adaptive).executable
    @test_throws UnsupportedContinuousProfile advance_continuous_system!(
        ContinuousSystemState(adaptive, (x = 1.0,)), 1.0)

    field = EvolvingFieldState(:signal,
        reshape(Float64[1, 0, 0, 0, 0, 0, 0, 0, 0], 3, 3))
    dynamics = FieldDynamics(:signal_dynamics;
        field = :signal,
        law = ReactionDiffusion(diffusion = 0.1, decay = 0.0),
        method = FixedStep(ExplicitEuler(); substeps = 10),
        clock)
    initial_mass = sum(field.values)
    advance_field!(field, dynamics, 0.1)
    @test sum(field.values) ≈ initial_mass
    @test field.values[1, 1] < 1

    owners = reshape(OwnerRef[
        CellOwner(1), MediumOwner(1), MediumOwner(1), MediumOwner(1)
    ], 2, 2)
    ownership = LogicalPottsState(owners, CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = [MediumID(1)])
    exchange_field = EvolvingFieldState(:exchange, ones(Float64, 2, 2))
    exchange = FieldExchange(:uptake; field = :exchange,
        sinks = (Uptake(:cells; maximum = 1.0,
            relative_rate = 0.25),))
    apply_field_exchange!(exchange_field, exchange, ownership)
    @test exchange_field.forcing[1] == -0.25
    @test all(iszero, exchange_field.forcing[2:end])

    steady_field = EvolvingFieldState(:steady, zeros(Float64, 3, 3))
    fill!(steady_field.forcing, 1.0)
    steady = FieldDynamics(:steady_dynamics;
        field = :steady,
        law = ReactionDiffusion(diffusion = 0.1, decay = 1.0),
        method = SteadyStateAdvance(:jacobi;
            absolute_tolerance = 1e-10,
            relative_tolerance = 1e-10,
            maximum_iterations = 10_000),
        clock)
    advance_field!(steady_field, steady, 1.0)
    @test all(value -> isapprox(value, 1.0; atol = 1e-8),
        steady_field.values)
    @test steady_field.diagnostics.residual <=
        steady_field.diagnostics.threshold
end

@testset "Phase 14 delay, event, mapping, adapter, and multirate semantics" begin
    delay = DelayState(:past_x; source = :x, delay = 1.0,
        sampling = EveryGlobal(0.5), interpolation = ExactSample())
    delay_state = DelayStateStorage(delay, 0.0)
    sample_delay!(delay_state, 0.5, 0.5)
    sample_delay!(delay_state, 1.0, 1.0)
    @test delay_value(delay_state, 1.5) == 0.5
    @test_throws ArgumentError DelayState(:invalid_delay;
        source = :x, delay = 0.75, sampling = EveryGlobal(0.5),
        interpolation = ExactSample())

    clock = SystemClock(:event_clock; scale = 1.0, unit = :second)
    identity_law = DirectLaw(:identity, (state, time) -> state.x)
    system = ContinuousSystem(:event_system;
        domain = GlobalDomain(),
        state = (StateVariable(:x),),
        statements = (SynchronousRule(:x, identity_law),),
        solver = FixedStep(ExplicitEuler(); substeps = 1),
        clock)
    state = ContinuousSystemState(system, (x = 0.0,))
    condition = DirectLaw(:after_one, (state, time) -> time >= 1)
    assignment = DirectLaw(:set_two, (state, time) -> 2.0)
    event = ContinuousEvent(:fire;
        domain = GlobalDomain(), system = :event_system,
        trigger = SampledTrigger(condition, OnRising()),
        schedule = EveryGlobal(1.0),
        assignments = (EventAssignment(:x, assignment),))
    runtime = EventRuntimeState(event)
    execute_event!(runtime, state, 1.0)
    @test state.values.x == 2.0
    execute_event!(runtime, state, 2.0)
    @test state.values.x == 2.0

    delayed_assignment = EventAssignment(:x,
        DirectLaw(:increment, (state, time) -> state.x + 1))
    delayed_trigger = SampledTrigger(
        DirectLaw(:always, (state, time) -> true), OnceWhenTrue())
    trigger_snapshot_event = ContinuousEvent(:trigger_snapshot;
        domain = GlobalDomain(), system = :event_system,
        trigger = delayed_trigger, schedule = EveryGlobal(1.0),
        assignments = (delayed_assignment,), delay = 1.0,
        values = FromTriggerSnapshot())
    trigger_snapshot_runtime = EventRuntimeState(trigger_snapshot_event)
    trigger_snapshot_state = ContinuousSystemState(system, (x = 1.0,))
    execute_event!(trigger_snapshot_runtime, trigger_snapshot_state, 1.0)
    trigger_snapshot_state.values = (x = 10.0,)
    execute_event!(trigger_snapshot_runtime, trigger_snapshot_state, 2.0)
    @test trigger_snapshot_state.values.x == 2.0

    execution_snapshot_event = ContinuousEvent(:execution_snapshot;
        domain = GlobalDomain(), system = :event_system,
        trigger = delayed_trigger, schedule = EveryGlobal(1.0),
        assignments = (delayed_assignment,), delay = 1.0,
        values = FromExecutionSnapshot())
    execution_snapshot_runtime = EventRuntimeState(execution_snapshot_event)
    execution_snapshot_state = ContinuousSystemState(system, (x = 1.0,))
    execute_event!(execution_snapshot_runtime, execution_snapshot_state, 1.0)
    execution_snapshot_state.values = (x = 10.0,)
    execute_event!(
        execution_snapshot_runtime, execution_snapshot_state, 2.0)
    @test execution_snapshot_state.values.x == 11.0

    root = RootTrigger(time -> time - 0.25)
    @test locate_root(root, root.root, 0.0, 1.0) ≈ 0.25

    source_identity = SymbolIdentity(
        (:model,), :global, :source, :x, v"1.0.0")
    source_system = ContinuousSystem(:source;
        domain = GlobalDomain(), state = (StateVariable(:x),),
        statements = (SynchronousRule(:x, identity_law),),
        solver = FixedStep(ExplicitEuler(); substeps = 1), clock)
    destination_system = ContinuousSystem(:destination;
        domain = GlobalDomain(), state = (StateVariable(:input),),
        statements = (SynchronousRule(:input,
            DirectLaw(:input_identity, (state, time) -> state.input)),),
        solver = FixedStep(ExplicitEuler(); substeps = 1), clock)
    source_state = ContinuousSystemState(source_system, (x = 3.0,))
    destination_state = ContinuousSystemState(
        destination_system, (input = 0.0,))
    mapping = SymbolMap(:copy_x;
        source = SymbolRef(source_identity),
        destination = InputRef(:destination, :input))
    coupled_mapping_state = CoupledState(
        globals = (source_state, destination_state))
    apply_symbol_map!(coupled_mapping_state, mapping)
    @test destination_state.values.input == 3.0

    item = CompatibilityItem(:rule, ExactSemanticMapping(),
        "Morpheus rule", "SynchronousRule", "microfixture:rule")
    adapter = ContinuousModelAdapter(:morpheus_fixture;
        profile = MorpheusSemanticProfile(),
        lower = DirectLaw(:morpheus_fixture_lowering, source -> (
            declarations = (system,),
            items = (item,))))
    adapted = adapt_continuous_model(
        adapter, :fixture; checksum = "sha256:fixture")
    @test adapted.report.executable
    @test adapted.report.overall isa ExactSemanticMapping

    fixture = _scientific_fixture(Float32, (4, 4))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    potts = init_scientific(compiled, fixture.proposal_relation,
        components, SequentialCPM(temperature = 1000.0f0); seed = 0x1412)
    unit_rhs = DirectLaw(:unit_rhs,
        (state, parameters, inputs, time) -> 1.0)
    timed_system = ContinuousSystem(:timed;
        domain = GlobalDomain(), state = (StateVariable(:x),),
        statements = (DifferentialEquation(:x, unit_rhs),),
        solver = FixedStep(ExplicitEuler(); substeps = 1),
        clock = SystemClock(:timed; scale = 1.0, unit = :second))
    timed_state = ContinuousSystemState(timed_system, (x = 0.0,))
    timed_event = ContinuousEvent(:timed_event;
        domain = GlobalDomain(), system = :timed,
        trigger = SampledTrigger(
            DirectLaw(:after_half,
                (state, time) -> time >= 0.5), OnRising()),
        schedule = EveryGlobal(0.5),
        assignments = (EventAssignment(:x,
            DirectLaw(:retain_x, (state, time) -> state.x)),))
    timed_event_state = EventRuntimeState(timed_event)
    timed_delay = DelayState(:timed_delay;
        source = :x, delay = 0.5,
        sampling = EveryGlobal(0.5),
        interpolation = ExactSample())
    timed_delay_state = DelayStateStorage(timed_delay, 0.0)
    cell_system = CellDynamics(:target_growth;
        domain = CellDomain((CellTypeID(2),)),
        state = (StateVariable(:target; property = :target_volume),),
        statements = (DifferentialEquation(:target,
            DirectLaw(:target_growth_rhs,
                (state, parameters, inputs, time) -> 1.0f0)),),
        solver = FixedStep(ExplicitEuler(); substeps = 1),
        clock = SystemClock(
            :target_growth; scale = 1.0f0, unit = :second))
    timeline = MultirateSchedule(
        global_clock = GlobalClock(:physical_time; unit = :second),
        mcs_duration = MCSDuration(1.0),
        entries = (
            ScheduledSystem(timed_system, EveryGlobal(0.25); priority = 10),
            ScheduledEvent(timed_event, EveryGlobal(0.5); priority = 12),
            ScheduledProcess(timed_delay, EveryGlobal(0.5); priority = 13),
            ScheduledSystem(cell_system, EveryGlobal(1.0); priority = 15),
            ScheduledPotts(PottsAttempts(), AtMCSEnd(); priority = 20),
            ScheduledLifecycle(
                LifecyclePhase(), AtMCSEnd(); priority = 30),
        ))
    x_observation = PhaseObservation(:timed_x,
        DirectLaw(:read_timed_x,
            (coupled, potts, mcs) -> coupled.globals[1].values.x);
        schema = RecordSchema(:timed_x_v1, v"1.0.0"))
    plan = MCSPlan(timeline = timeline,
        observation = ObservationPhase(x_observation))
    coupled_state = CoupledState(
        globals = (timed_state,),
        delays = (timed_event_state, timed_delay_state))
    cpu_report = coupled_backend_report(
        plan, coupled_state,
        potts.plan.capabilities)
    @test cpu_report.executable
    @test all(row -> row.status == :qualified_reference, cpu_report.rows)
    unsupported_backend = BackendCapabilities(
        AMDGPUFamily, DeferredBackend, false, false, true, true, ())
    @test_throws UnsupportedCoupledCapabilities preflight_coupled(
        plan, coupled_state,
        unsupported_backend)
    coupled = init_coupled(
        potts, plan, coupled_state)
    step!(coupled)
    @test timed_state.values.x == 1.0
    @test timed_state.time == 1.0
    @test property_value(
        logical_state(coupled.potts), :target_volume, CellID(1)) == 5.0f0
    @test global_time(coupled) == 1//1
    @test coupled.potts.mcs == 1
    @test coupled.observations.completed_mcs == 1
    @test only(coupled.observations.records).value == 1.0
    @test coupled.observations.last_published[:timed_x] == 1
    @test delay_value(timed_delay_state, 1.0) == 0.5
    @test timed_event_state.previous_condition
    manifest = coupled_manifest(coupled)
    @test manifest.continuation == :exact_completed_mcs
    @test manifest.backend.executable
    inspection = inspect_coupled(coupled)
    @test inspection.completed_mcs == 1
    @test inspection.global_time == 1//1
    @test Set(block.family for block in inspection.state_blocks) ==
        Set((:continuous_system, :continuous_event, :delay_state))

    uncoupled_checkpoint = capture_checkpoint(coupled.potts)
    checkpoint = capture_checkpoint(coupled)
    @test checkpoint isa CoupledCheckpoint
    @test checkpoint.base.checksum == uncoupled_checkpoint.checksum
    @test checkpoint.mcs == 1
    @test validate_checkpoint(checkpoint) === checkpoint
    @test Set((block.family, block.name)
        for block in checkpoint.extension.blocks) == Set((
        (:continuous_system, :timed),
        (:continuous_event, :timed_event),
        (:delay_state, :timed_delay)))
    store = CoupledMemoryCheckpointStore()
    write_checkpoint!(store, "after_one", checkpoint)
    restored = restore_checkpoint(read_checkpoint(store, "after_one"), coupled)
    @test restored.mcs == coupled.mcs
    @test restored.state.globals[1].values == timed_state.values
    @test isempty(restored.observations.records)
    @test restored.observations.last_published[:timed_x] == 1
    step!(coupled)
    step!(restored)
    @test restored.state.globals[1].values ==
        coupled.state.globals[1].values
    @test property_value(
        logical_state(restored.potts), :target_volume, CellID(1)) ==
        property_value(
            logical_state(coupled.potts), :target_volume, CellID(1))
    @test logical_state(restored.potts)._owners ==
        logical_state(coupled.potts)._owners
    @test capture_checkpoint(restored).state_fingerprint ==
        capture_checkpoint(coupled).state_fingerprint
    @test only(restored.observations.records).mcs == 2

    transform = ObservationTransform(:isolated_double;
        maximum_work = 1,
        transform = DirectLaw(:double_private,
            (private_coupled, private_potts, mcs) -> begin
                value = private_coupled.globals[1].values.x
                private_coupled.globals[1].values = (x = -100.0,)
                2value
            end))
    before_transform = timed_state.values
    @test transform(coupled.state, logical_state(coupled.potts), coupled.mcs) ==
        2before_transform.x
    @test timed_state.values == before_transform

    @test_throws ArgumentError MCSPlan(timeline = MultirateSchedule(
        global_clock = GlobalClock(:bad; unit = :second),
        mcs_duration = MCSDuration(1.0),
        entries = (
            ScheduledPotts(PottsAttempts(), AtMCSEnd(); priority = 10),
            ScheduledLifecycle(
                LifecyclePhase(), AtMCSEnd(); priority = 10),
        )))
end
