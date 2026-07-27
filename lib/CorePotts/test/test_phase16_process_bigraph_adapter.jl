import ProcessBigraphs as PB

function p16e_native_configuration(values)
    scale = PB.TimeScale(1, 100, :second)
    adapter = CorePotts.CorePottsNativeFieldAdapter(
        :phase16e_field,
        values;
        diffusion=0.1,
        decay=0.03,
        tick_duration=0.01,
        substeps_per_tick=1,
        block_size=64,
        time_scale=scale,
    )
    adapter, scale
end

function p16e_direct_native_field(values)
    CorePotts.NativeFieldEngine(
        :phase16e_field,
        values,
        ExecutionPlan(KernelAbstractions.CPU(); block_size=64);
        diffusion=0.1,
        decay=0.03,
        tick_duration=0.01,
        substeps_per_tick=1,
    )
end

function p16e_advance_managed!(runtime, target, forcing)
    PB.advance_managed_engine!(
        runtime,
        PB.LogicalTime(target, runtime.logical_time.scale);
        reason=:scheduled_field_advance,
        inputs=(:forcing => forcing,),
        resource_authorization=(
            backend=:cpu,
            precision=:float64,
            residency=:host,
        ),
        expected_outputs=(:field_state,),
        expected_diagnostics=(:backend, :precision),
    )
end

function p16e_empty_serial_runtime()
    scale = PB.TimeScale(1)
    schema = PB.BranchSchema(
        marker=PB.LeafSchema(Int; default=0, update_law=:replace),
    )
    composite = PB.compile_composite(PB.StaticComposite(
        schema, Dict(), scale))
    executor = PB.SerialExecutor(root_seed=1605)
    composite, executor, PB.initialize_runtime(composite, executor)
end

function p16e_legacy_integrator()
    energy = QuadraticVolumeHamiltonian(number_type=Float32)
    owners = fill(MediumOwner(1), 6, 6)
    fill!(view(owners, 2:5, 2:3), CellOwner(1))
    fill!(view(owners, 2:5, 4:5), CellOwner(2))
    logical = LogicalPottsState(
        owners,
        CellCapacity(4);
        cell_types=Dict(
            CellID(1) => CellTypeID(1),
            CellID(2) => CellTypeID(2),
        ),
        medium_domains=(MediumID(1),),
        property_schema=required_properties(energy),
    )
    property_values(logical, :target_volume)[1:2] .= Float32[8, 8]
    property_values(logical, :volume_strength)[1:2] .= Float32[1, 1]
    state = compile_scientific_state(
        logical,
        CartesianDomain((6, 6)),
        BoundaryMeasureTracker(
            BoundaryEdgeCount(),
            first_shell_relation(SurfaceRole(), Val(2)),
        ),
    )
    plan = ExecutionPlan(KernelAbstractions.CPU())
    init_scientific(
        state,
        first_shell_relation(ProposalRole(), Val(2)),
        ScientificComponentSet(energies=(energy,)),
        SequentialCPM(temperature=2.0f0);
        seed=0x7065727369737401,
        plan,
    )
end

function p16e_managed_trajectory(initial, forcings)
    adapter, scale = p16e_native_configuration(initial)
    runtime = CorePotts.process_bigraph_native_field_runtime(
        "phase16e-field",
        adapter;
        structural_epoch="domain-epoch-0",
    )
    results = Any[]
    states = Array{Float64,2}[]
    for (tick, forcing) in enumerate(forcings)
        push!(results, p16e_advance_managed!(runtime, tick, forcing))
        push!(states,
            CorePotts.process_bigraph_native_field_snapshot(runtime))
    end
    adapter, scale, runtime, results, states
end

function p16e_empty_coupled_checkpoint(base::CanonicalCheckpoint)
    protocol = (
        stage=:completed,
        stage_local_mcs=base.mcs,
        completed_mcs=base.mcs,
        global_time=Float64(base.mcs),
        plan=(),
        protocol=(),
    )
    observation = (
        completed_mcs=base.mcs,
        last_published=(),
        publication_epochs=(),
    )
    blocks = ()
    extension = CorePotts.CoupledCheckpointExtension(
        CorePotts.COUPLED_EXTENSION_BLOCK_VERSION,
        blocks,
        protocol,
        observation,
    )
    state_fingerprint = CorePotts._coupled_state_digest(
        blocks, protocol, observation)
    zero_digest = ntuple(_ -> UInt8(0), 32)
    provisional = CorePotts.CoupledCheckpoint(
        CorePotts.COUPLED_CHECKPOINT_SCHEMA_VERSION,
        true,
        base.mcs,
        UInt8(1),
        base,
        extension,
        zero_digest,
        zero_digest,
        base.initial_state_fingerprint,
        zero_digest,
        state_fingerprint,
        (),
        zero_digest,
    )
    CorePotts.CoupledCheckpoint(
        provisional.schema_version,
        provisional.complete,
        provisional.mcs,
        provisional.phase,
        provisional.base,
        provisional.extension,
        provisional.coupled_model_fingerprint,
        provisional.state_schema_fingerprint,
        provisional.initial_state_fingerprint,
        provisional.ancestry_fingerprint,
        provisional.state_fingerprint,
        provisional.warnings,
        CorePotts._coupled_envelope_digest(provisional),
    )
end

@testset "Phase 16.E CorePotts native-field strangler cutover" begin
    initial = reshape(Float64.(1:20), 4, 5)
    forcings = [
        fill(0.01 * tick, size(initial))
        for tick in 1:4
    ]
    direct = p16e_direct_native_field(initial)
    direct_states = Array{Float64,2}[]
    for (tick, forcing) in enumerate(forcings)
        copyto!(direct.forcing, forcing)
        CorePotts.advance_native_field!(direct, tick)
        push!(direct_states, CorePotts.native_field_snapshot(direct))
    end

    adapter, scale, managed, results, managed_states =
        p16e_managed_trajectory(initial, forcings)
    @test managed_states == direct_states
    @test managed.logical_time == PB.LogicalTime(4, scale)
    @test managed.instance.engine.time_tick == direct.time_tick
    @test managed.instance.engine.publication_epoch ==
        direct.publication_epoch
    @test all(result -> result.status === :published, results)
    @test all(result ->
        !any(name -> getfield(result.outcome.payload, name)
                isa AbstractArray,
            fieldnames(typeof(result.outcome.payload))),
        results)
    @test !(:fallback in fieldnames(typeof(adapter)))
    @test !(:scheduler in fieldnames(typeof(adapter)))

    unauthorized = CorePotts.process_bigraph_native_field_runtime(
        "phase16e-field",
        adapter;
        structural_epoch="domain-epoch-0",
    )
    before = CorePotts.process_bigraph_native_field_snapshot(unauthorized)
    forcing_before = copy(unauthorized.instance.engine.forcing)
    @test_throws PB.ProcessBigraphError PB.advance_managed_engine!(
        unauthorized,
        PB.LogicalTime(1, scale);
        inputs=(:forcing => forcings[1],),
        resource_authorization=(
            backend=:cpu,
            precision=:float64,
            residency=:host,
        ),
        expected_outputs=(:field_state,),
        expected_diagnostics=(:backend, :precision),
        authorize=(candidate, invocation) -> false,
    )
    @test CorePotts.process_bigraph_native_field_snapshot(unauthorized) ==
        before
    @test unauthorized.instance.engine.forcing == forcing_before
    @test unauthorized.logical_time == PB.LogicalTime(0, scale)
    @test unauthorized.publication_version == UInt64(0)
    @test !isnothing(unauthorized.last_failure)

    failing_adapter, _ = p16e_native_configuration(zeros(Float64, 4, 5))
    failing = CorePotts.process_bigraph_native_field_runtime(
        "phase16e-failing",
        failing_adapter;
        structural_epoch="domain-epoch-0",
    )
    @test_throws PB.ProcessBigraphError p16e_advance_managed!(
        failing, 1, fill(-1000.0, 4, 5))
    @test CorePotts.process_bigraph_native_field_snapshot(failing) ==
        zeros(Float64, 4, 5)
    @test failing.logical_time == PB.LogicalTime(0, scale)
    @test failing.instance.engine.publication_epoch == UInt64(0)
    @test failing.last_failure.code === :managed_engine_failure

    cell_request = CorePotts.corepotts_cell_structural_request(
        "divide-cell-3",
        7,
        :divide,
        CellID(3),
        CellGeneration(2);
        payload=(axis=:major,),
        priority=5,
    )
    @test cell_request.owner == "corepotts"
    @test cell_request.operation === :divide
    @test only(cell_request.targets).id == "3"
    @test only(cell_request.targets).generation == UInt64(2)
    @test only(PB.select_domain_structural_requests(
        (cell_request,)).selected) === cell_request
end

@testset "Phase 16.E CorePotts V3 restart differential" begin
    initial = reshape(Float64.(1:20), 4, 5)
    forcings = [
        reshape(Float64.(tick:(tick + 19)), 4, 5) .* 1e-3
        for tick in 1:4
    ]
    adapter, scale, baseline, _, baseline_states =
        p16e_managed_trajectory(initial, forcings)
    declaration = baseline.declaration
    composite, executor, serial = p16e_empty_serial_runtime()

    for cut in 0:3
        prefix = CorePotts.process_bigraph_native_field_runtime(
            "phase16e-field",
            adapter;
            structural_epoch="domain-epoch-0",
        )
        for tick in 1:cut
            p16e_advance_managed!(prefix, tick, forcings[tick])
        end
        checkpoint = PB.phase16_checkpoint(
            serial; managed_engines=(prefix,))
        encoded = PB.encode_checkpoint(checkpoint)
        decoded = PB.decode_phase16_checkpoint(encoded)
        restored = PB.restore_phase16_checkpoint(
            composite,
            executor,
            decoded;
            engine_declarations=(declaration,),
        )
        resumed = only(restored.engines).second
        for tick in (cut + 1):4
            p16e_advance_managed!(resumed, tick, forcings[tick])
        end
        @test CorePotts.process_bigraph_native_field_snapshot(resumed) ==
            last(baseline_states)
        @test resumed.logical_time == PB.LogicalTime(4, scale)
        @test resumed.instance.engine.publication_epoch == UInt64(4)
    end

    checkpoint = PB.phase16_checkpoint(
        serial; managed_engines=(baseline,))
    encoded = PB.encode_checkpoint(checkpoint)
    corrupted = copy(encoded)
    corrupted[end] ⊻= 0x01
    @test_throws PB.ProcessBigraphError PB.decode_phase16_checkpoint(
        corrupted)
end

@testset "Phase 16.E non-destructive CorePotts legacy conversion" begin
    source = capture_checkpoint(p16e_legacy_integrator())
    source_payload = checkpoint_storage_payload(source)
    composite, executor, serial = p16e_empty_serial_runtime()
    converted = PB.convert_legacy_checkpoint(
        serial,
        CorePotts.CorePottsCanonicalCheckpointConverter(),
        source,
    )
    @test checkpoint_storage_payload(source) == source_payload
    @test PB.decode_phase16_checkpoint(
        PB.encode_checkpoint(converted)).integrity == converted.integrity
    @test checkpoint_storage_payload(
        checkpoint_from_storage_payload(source_payload)) == source_payload

    coupled = p16e_empty_coupled_checkpoint(source)
    coupled_before = deepcopy(coupled)
    coupled_converted = PB.convert_legacy_checkpoint(
        serial,
        CorePotts.CorePottsCoupledCheckpointConverter(),
        coupled,
    )
    @test coupled.checksum == coupled_before.checksum
    @test coupled.base.checksum == coupled_before.base.checksum
    @test PB.decode_phase16_checkpoint(
        PB.encode_checkpoint(coupled_converted)).integrity ==
        coupled_converted.integrity
    @test validate_checkpoint(coupled) === coupled

    corrupt = CorePotts._checkpoint_with_checksum(
        source, ntuple(_ -> UInt8(0), 32))
    @test_throws CheckpointIntegrityError PB.convert_legacy_checkpoint(
        serial,
        CorePotts.CorePottsCanonicalCheckpointConverter(),
        corrupt,
    )
end
