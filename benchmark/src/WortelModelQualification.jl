const WORTEL_MODEL_EVIDENCE_SCHEMA = "1.0.0"

@kernel function _activity_energy_probe!(
        output, component, proposal, context)
    index = @index(Global, Linear)
    @inbounds if index == 1
        output[1] = proposal_energy_change(component, proposal, context)
    end
end

function _wortel_model_fixture(dims::NTuple{2, Int})
    spacing = (1.0f0, 1.0f0)
    volume = QuadraticVolumeHamiltonian(number_type = Float32)
    surface_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    schema = required_properties(volume)

    owners = fill(MediumOwner(1), dims)
    cell_side = max(4, min(8, minimum(dims) ÷ 12))
    pitch = cell_side + 2
    cell = 0
    for y in 2:pitch:(dims[2] - cell_side),
            x in 2:pitch:(dims[1] - cell_side)
        cell += 1
        fill!(
            view(owners, x:(x + cell_side - 1), y:(y + cell_side - 1)),
            CellOwner(cell))
    end
    cell > 0 || error("Wortel model qualification fixture contains no finite cells")
    logical = LogicalPottsState(owners, CellCapacity(cell);
        cell_types = Dict(CellID(index) => CellTypeID(2) for index in 1:cell),
        medium_domains = [MediumID(1)], property_schema = schema)
    property_values(logical, :target_volume) .= Float32(cell_side^2)
    property_values(logical, :volume_strength) .= 1.0f0

    domain = CartesianDomain(dims; spacing)
    proposal_relation = first_shell_relation(
        ProposalRole(), Val(2); spacing)
    contact_relation = first_shell_relation(
        ContactRole(), Val(2); spacing)
    contact = UnorderedContactHamiltonian(
        Float32[0 6; 6 2],
        MediumTypeTable(MediumID(1) => CellTypeID(1)),
        contact_relation)
    boundary_tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), surface_relation)
    compiled = compile_scientific_state(
        logical, domain, boundary_tracker)
    return (; logical, domain, proposal_relation, volume, contact,
        boundary_tracker, compiled, cells = cell, cell_side)
end

function _activity_program(
        algorithm::BudgetedSequentialCPM; observation_cadence::Int)
    relation = static_relation(
        SpatialQueryRole(), CorePotts.offsets(CorePotts.MooreTopology{2}());
        spacing = (1.0f0, 1.0f0))
    return ActivityProgram(
        maximum = 10.0f0,
        strength = 20.0f0,
        relation = relation,
        algorithm = algorithm,
        observation_cadence = observation_cadence)
end

function _build_wortel_model(name::String, dims::NTuple{2, Int};
        seed::UInt64, observation_cadence::Int,
        require_gpu_native::Bool = true)
    fixture = _wortel_model_fixture(dims)
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor, fixture.compiled)
    scientific_storage_valid(state) ||
        error("$name Wortel model scientific state is not one backend-resident array tree")
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    execution_plan = ExecutionPlan(backend; block_size = 128, metrics)
    algorithm = BudgetedSequentialCPM(
        AttemptsPerSite(1); temperature = 20.0f0)
    program = _activity_program(
        algorithm; observation_cadence)
    runtime = realize_activity(program, state)

    activity = runtime.state.values
    activity === runtime.workspace.site_states[1].values ||
        error("$name activity workspace did not reuse its backend-resident state array")
    activity === runtime.coupled_state.site_states[1].values ||
        error("$name coupled state did not reuse its backend-resident activity array")
    isequal(KernelAbstractions.get_backend(activity), backend) ||
        error("$name activity was not allocated directly on the scientific backend")
    if require_gpu_native
        probe = _activity_energy_probe!(backend, 1)
        device_workspace =
            KernelAbstractions.argconvert(probe, runtime.workspace)
        isbits(device_workspace) ||
            error("$name kernel-adapted coupled workspace is not a device-valid immutable value")
    end

    components = Adapt.adapt(adaptor, ScientificComponentSet(
        energies = (
            fixture.volume, fixture.contact, program.hamiltonian)))
    potts = init_scientific(
        state, fixture.proposal_relation, components, algorithm;
        seed, plan = execution_plan,
        algorithm_workspace = runtime.workspace)
    coupled = CorePotts.init_coupled(
        potts, runtime.plan, runtime.coupled_state;
        semantic_model = program.semantic_model)
    report = coupled_backend_report(
        runtime.plan, runtime.coupled_state,
        execution_plan.capabilities)
    report.executable ||
        error("$name rejected the exact Float32 Wortel GPU-native slice")
    if require_gpu_native
        all(row -> row.status === :qualified_gpu_native, report.rows) ||
            error("$name did not qualify every declared Wortel capability")
    end
    return (; fixture, adaptor, backend, metrics, algorithm, program,
        runtime, components, coupled, report)
end

function _actionable_proposal(fixture)
    for site in eachindex(lattice_storage(fixture.logical))
        for direction in 1:direction_count(fixture.proposal_relation)
            attempt = construct_copy_attempt(
                scientific_execution(fixture.compiled),
                fixture.compiled.domain, fixture.proposal_relation,
                site, direction; mcs = 1, semantic_id = site)
            attempt.outcome === ActionableCopy || continue
            proposal = actionable_proposal(attempt)
            is_cell_owner(proposal.gaining) || continue
            return proposal
        end
    end
    error("Wortel model qualification fixture has no finite-cell copy proposal")
end

function _energy_probe!(run)
    proposal = _actionable_proposal(run.fixture)
    transaction = stage_copy_transaction(
        run.fixture.compiled, run.fixture.boundary_tracker, proposal)

    host_runtime = realize_activity(
        run.program, run.fixture.compiled)
    host_values = host_runtime.state.values
    fill!(host_values, 1.0f0)
    host_values[proposal.donor] = 4.0f0
    host_values[proposal.recipient] = 9.0f0
    host_context = ScientificProposalContext(
        scientific_execution(run.fixture.compiled), transaction;
        algorithm_workspace = host_runtime.workspace)
    expected = proposal_energy_change(
        run.program.hamiltonian, proposal, host_context)

    copyto!(run.runtime.state.values, host_values)
    device_context = ScientificProposalContext(
        scientific_execution(run.coupled.potts.state), transaction;
        algorithm_workspace = run.runtime.workspace)
    kernel = _activity_energy_probe!(run.backend, 1)
    if !(run.backend isa KernelAbstractions.CPU)
        device_context_argument =
            KernelAbstractions.argconvert(kernel, device_context)
        isbits(device_context_argument) ||
            error("Wortel model activity energy context is not device-valid")
    end
    output = similar(run.runtime.state.values, Float32, 1)
    kernel(output, run.program.hamiltonian, proposal, device_context; ndrange = 1)
    KernelAbstractions.synchronize(run.backend)
    observed = only(Array(output))
    isapprox(observed, expected;
        rtol = 16eps(Float32), atol = 16eps(Float32)) ||
        error("Wortel model device geometric activity energy differs: $observed != $expected")
    fill!(run.runtime.state.values, 0.0f0)
    KernelAbstractions.synchronize(run.backend)
    return (expected = expected, observed = observed,
        tolerance = "rtol=atol=16eps(Float32)")
end

function _unobserved_and_observed_qualification!(run)
    energy = _energy_probe!(run)
    SciMLBase.step!(run.coupled)
    report = current_mcs_report(run.coupled.potts)
    report.accepted_copies > 0 ||
        error("Wortel model production trace exercised no accepted copies")
    report.acceptance_rejections > 0 ||
        error("Wortel model production trace exercised no acceptance rejection")
    report.same_owner_no_ops > 0 ||
        error("Wortel model production trace exercised no same-owner no-op")

    truth_checkpoint = capture_checkpoint(run.coupled)
    activity_block = only(block for block in truth_checkpoint.extension.blocks
        if block.family === :site_property && block.name === :activity)
    activity_values = activity_block.payload.values
    all(value -> value == 0.0f0 || value == 9.0f0, activity_values) ||
        error("accepted-copy/decay truth table produced a value outside {0, maximum-1}")
    any(==(9.0f0), activity_values) ||
        error("accepted finite-cell copies did not activate and decay activity")

    before = _metric_snapshot(run.metrics)
    KernelAbstractions.synchronize(run.backend)
    sample = @timed begin
        SciMLBase.step!(run.coupled, 3)
        KernelAbstractions.synchronize(run.backend)
    end
    after = _metric_snapshot(run.metrics)
    unobserved = _metric_delta(after, before)
    expected_unobserved_launches =
        run.backend isa KernelAbstractions.CPU ? 3 : 6
    unobserved["launches"] == expected_unobserved_launches ||
        error("three unobserved coupled MCS had an unexpected launch count")
    expected_unobserved_syncs =
        run.backend isa KernelAbstractions.CPU ? 3 : 0
    unobserved["host_synchronizations"] == expected_unobserved_syncs ||
        error("unobserved coupled MCS had an unexpected synchronization count")
    unobserved["host_to_device_transfers"] == 0 ||
        error("unobserved coupled MCS copied data to the device")
    unobserved["device_to_host_transfers"] == 0 ||
        error("unobserved coupled MCS copied data to the host")
    unobserved["device_allocations"] == 0 ||
        error("unobserved coupled MCS allocated CorePotts device storage")

    observation_before = _metric_snapshot(run.metrics)
    SciMLBase.step!(run.coupled)
    observation_after = _metric_snapshot(run.metrics)
    observation = _metric_delta(observation_after, observation_before)
    expected_observation_launches =
        run.backend isa KernelAbstractions.CPU ? 2 : 3
    observation["launches"] == expected_observation_launches ||
        error("observed coupled MCS had an unexpected launch count")
    expected_observation_syncs =
        run.backend isa KernelAbstractions.CPU ? 2 : 1
    observation["host_synchronizations"] == expected_observation_syncs ||
        error("activity observation had an unexpected synchronization count")
    expected_observation_transfers =
        run.backend isa KernelAbstractions.CPU ? 0 : 2
    observation["device_to_host_transfers"] ==
        expected_observation_transfers ||
        error("activity observation returned an unexpected transfer count")
    observation["host_to_device_transfers"] == 0 ||
        error("activity observation copied data to the device")
    observation["device_allocations"] == 0 ||
        error("activity observation allocated CorePotts device storage")
    record = only(run.coupled.observations.records)
    record.observation === :activity_summary ||
        error("Wortel model activity observation did not publish its declared record")

    return Dict(
        "geometric_energy_expected" => energy.expected,
        "geometric_energy_observed" => energy.observed,
        "geometric_energy_tolerance" => energy.tolerance,
        "accepted_copies" => report.accepted_copies,
        "acceptance_rejections" => report.acceptance_rejections,
        "same_owner_no_ops" => report.same_owner_no_ops,
        "activity_truth_table" => true,
        "decay_value_after_first_mcs" => 9.0,
        "unobserved_mcs_count" => 3,
        "unobserved_metrics" => unobserved,
        "observation_metrics" => observation,
        "seconds_per_unobserved_mcs" => sample.time / 3,
        "host_allocated_bytes_per_unobserved_mcs" => sample.bytes ÷ 3,
    )
end

function _replay_restart_qualification(
        name::String, dims::NTuple{2, Int})
    seed = UInt64(0x7068617365313402)
    require_gpu_native = name != "cpu"
    first = _build_wortel_model(
        name, dims; seed, observation_cadence = 1000,
        require_gpu_native)
    replay = _build_wortel_model(
        name, dims; seed, observation_cadence = 1000,
        require_gpu_native)
    SciMLBase.step!(first.coupled, 2)
    SciMLBase.step!(replay.coupled, 2)
    first_checkpoint = capture_checkpoint(first.coupled)
    replay_checkpoint = capture_checkpoint(replay.coupled)
    first_checkpoint.state_fingerprint == replay_checkpoint.state_fingerprint ||
        error("$name same-backend Wortel replay differs")
    first_checkpoint.base.state_fingerprint ==
        replay_checkpoint.base.state_fingerprint ||
        error("$name same-backend Potts replay differs")

    restored = restore_checkpoint(
        first_checkpoint, first.coupled; adaptor = first.adaptor)
    first_before = _metric_snapshot(first.coupled.potts.plan.metrics)
    restored_before = _metric_snapshot(restored.potts.plan.metrics)
    SciMLBase.step!(first.coupled, 2)
    SciMLBase.step!(restored, 2)
    first_after = _metric_snapshot(first.coupled.potts.plan.metrics)
    restored_after = _metric_snapshot(restored.potts.plan.metrics)
    for delta in (
            _metric_delta(first_after, first_before),
            _metric_delta(restored_after, restored_before))
        expected_syncs = name == "cpu" ? 2 : 0
        delta["host_synchronizations"] == expected_syncs ||
            error("$name continuation synchronized during unobserved MCS")
        delta["host_to_device_transfers"] == 0 ||
            error("$name continuation transferred to device during MCS")
        delta["device_to_host_transfers"] == 0 ||
            error("$name continuation transferred to host during MCS")
        delta["device_allocations"] == 0 ||
            error("$name continuation allocated device storage during MCS")
    end
    continued = capture_checkpoint(first.coupled)
    resumed = capture_checkpoint(restored)
    continued.state_fingerprint == resumed.state_fingerprint ||
        error("$name exact Wortel restart state differs")
    continued.base.state_fingerprint == resumed.base.state_fingerprint ||
        error("$name exact Wortel restart Potts state differs")
    return Dict(
        "same_backend_replay" => true,
        "exact_same_backend_restart" => true,
        "replay_mcs" => 2,
        "continuation_mcs" => 2,
        "dims" => collect(dims),
    )
end

function qualify_wortel_model_backend(
        name::String; profile::String = "paper")
    name in ("metal", "amdgpu") || throw(ArgumentError(
        "Wortel model G2 requires --backend=metal or --backend=amdgpu"))
    profile in ("smoke", "paper") || throw(ArgumentError(
        "Wortel model profile must be smoke or paper"))
    _, device = load_backend(name)
    extent = profile == "paper" ? 128 : 48
    dims = (extent, extent)
    main = _build_wortel_model(
        name, dims; seed = UInt64(0x7068617365313401),
        observation_cadence = 5)
    execution = _unobserved_and_observed_qualification!(main)
    replay_dims = (min(extent, 64), min(extent, 64))
    continuation = _replay_restart_qualification(
        name, replay_dims)
    backend_module = getfield(
        Main, name == "metal" ? :Metal : :AMDGPU)
    return Dict(
        "backend" => name,
        "device" => device,
        "profile" => profile,
        "dims" => collect(dims),
        "cells" => main.fixture.cells,
        "cell_side" => main.fixture.cell_side,
        "number_type" => "Float32",
        "algorithm" => "BudgetedSequentialCPM(AttemptsPerSite(1))",
        "semantic_rng" => "Philox4x32x10V1",
        "packages" => Dict(
            "backend" => string(Base.pkgversion(backend_module)),
            "CorePotts" => string(Base.pkgversion(CorePotts)),
            "KernelAbstractions" =>
                string(Base.pkgversion(KernelAbstractions)),
        ),
        "state_backend_reused_without_adaptation" => true,
        "workspace_shares_activity_allocation" => true,
        "coupled_preflight" => "qualified_gpu_native",
        "capabilities" => [String(row.capability) for row in main.report.rows],
        "scientific_state_bytes" => scientific_state_bytes(main.coupled.potts.state),
        "activity_state_bytes" => sizeof(Float32) * prod(dims),
        "execution" => execution,
        "continuation" => continuation,
    )
end

function wortel_model_result(
        name::String, qualification::Dict)
    return Dict(
        "schema_version" => WORTEL_MODEL_EVIDENCE_SCHEMA,
        "suite" => "phase14-wortel-gpu-native-qualification-v1",
        "generated_at_utc" => string(now(UTC)),
        "provenance" => provenance(name, qualification["device"]),
        "qualification" => qualification,
    )
end

function write_wortel_model_result(result::Dict)
    provenance_data = result["provenance"]
    qualification = result["qualification"]
    backend = qualification["backend"]
    profile = qualification["profile"]
    timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
    directory = joinpath(
        RESULTS_ROOT, provenance_data["subject_id"], backend)
    mkpath(directory)
    path = joinpath(
        directory, "$(timestamp)-wortel-gpu-native-$(profile).toml")
    open(path, "w") do io
        TOML.print(io, result; sorted = true)
    end
    return path
end
