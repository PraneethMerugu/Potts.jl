const PHASE14_WANG_G3C_EVIDENCE_SCHEMA = "1.0.0"
const PHASE14_WANG_G3C_SUITE =
    "phase14-wang-g3c-gpu-native-qualification-v1"

include(joinpath(
    HARNESS_ROOT, "integration", "conformance",
    "phase14_wang_fixture.jl"))

function _phase14_wang_checkpoint_block(
        checkpoint, family::Symbol, name::Symbol)
    return only(block for block in checkpoint.extension.blocks
        if block.family === family && block.name === name)
end

function _phase14_wang_property(checkpoint, name::Symbol)
    return only(column.values for column in checkpoint.base.properties
        if column.key === name)
end

function _phase14_wang_backend_tree(run)
    arrays = (
        CorePotts._coupled_array_leaves(run.coupled.plan)...,
        CorePotts._coupled_array_leaves(run.coupled.state)...,
    )
    isempty(arrays) &&
        error("Wang qualification discovered no coupled storage arrays")
    all(array -> isbitstype(eltype(array)) &&
        isequal(KernelAbstractions.get_backend(array), run.backend), arrays) ||
        error("Wang coupled storage is not one backend-resident isbits array tree")
    return arrays
end

function _phase14_build_wang_g3c(
        name::String, side::Int)
    adaptor = _backend_adaptor(name)
    run = _wang_runtime_fixture(
        side; adaptor,
        execution_mode =
            CorePotts.PortableCoupledExecution())
    report = coupled_backend_report(
        run.coupled.plan, run.coupled.state,
        run.coupled.potts.plan.capabilities;
        potts = run.coupled.potts)
    report.executable ||
        error("$name rejected the frozen Wang G3-C profile")
    all(row -> row.status === :qualified_gpu_native,
        report.rows) ||
        error("$name left at least one Wang capability unqualified")
    arrays = _phase14_wang_backend_tree(run)
    return merge(run, (; report,
        coupled_array_count = length(arrays),
        coupled_array_bytes =
            sum(array -> sizeof(eltype(array)) * length(array),
                arrays; init = 0)))
end

function _phase14_wang_unobserved_metrics!(run)
    # Target MCS 1 compiles all always-active kernels and the due retune path.
    SciMLBase.step!(run.coupled)
    KernelAbstractions.synchronize(run.backend)
    before = _metric_snapshot(run.metrics)
    sample = @timed begin
        # Target MCS 2 is observation-free and has no scheduled migration
        # processes. Its only D2H traffic is the five declared bounded status
        # boundaries: accepted-copy, field, history, exchange, and cleanup.
        SciMLBase.step!(run.coupled)
        KernelAbstractions.synchronize(run.backend)
    end
    after = _metric_snapshot(run.metrics)
    delta = _metric_delta(after, before)
    delta["host_to_device_transfers"] == 0 ||
        error("unobserved Wang MCS copied state to the device")
    delta["device_allocations"] == 0 ||
        error("unobserved Wang MCS allocated CorePotts device storage")
    delta["device_to_host_transfers"] == 9 ||
        error("unobserved Wang MCS did not have exactly nine registered status-scalar transfers")
    delta["host_synchronizations"] == 5 ||
        error("unobserved Wang MCS did not have exactly five registered status boundaries")
    return Dict(
        "target_mcs" => 2,
        "metrics" => delta,
        "status_scalar_transfers" => 9,
        "status_boundaries" => 5,
        "scientific_payload_transfers" => 0,
        "seconds" => sample.time,
        "julia_heap_bytes" => sample.bytes,
    )
end

function _phase14_wang_replay_restart(
        name::String, side::Int)
    first = _phase14_build_wang_g3c(name, side)
    replay = _phase14_build_wang_g3c(name, side)
    SciMLBase.step!(first.coupled, 3)
    SciMLBase.step!(replay.coupled, 3)
    first_checkpoint = capture_checkpoint(first.coupled)
    replay_checkpoint = capture_checkpoint(replay.coupled)
    first_checkpoint.state_fingerprint ==
        replay_checkpoint.state_fingerprint ||
        error("$name Wang same-backend replay differs")
    first_checkpoint.base.state_fingerprint ==
        replay_checkpoint.base.state_fingerprint ||
        error("$name Wang Potts same-backend replay differs")

    restored = restore_checkpoint(
        first_checkpoint, first.coupled;
        adaptor = first.adaptor)
    SciMLBase.step!(first.coupled, 3)
    SciMLBase.step!(restored, 3)
    continued = capture_checkpoint(first.coupled)
    resumed = capture_checkpoint(restored)
    continued.state_fingerprint ==
        resumed.state_fingerprint ||
        error("$name Wang exact restart state differs")
    continued.base.state_fingerprint ==
        resumed.base.state_fingerprint ||
        error("$name Wang exact restart Potts state differs")
    return Dict(
        "same_backend_replay" => true,
        "completed_mcs_restart" => true,
        "capture_mcs" => 3,
        "continued_mcs" => 6,
        "mid_phase_capture_admitted" => false,
    )
end

function _phase14_wang_final_invariants(
        checkpoint, observation_state, target_mcs::Int)
    field = _phase14_wang_checkpoint_block(
        checkpoint, :evolving_field, :wang_secretome)
    history = _phase14_wang_checkpoint_block(
        checkpoint, :cell_history, :wang_centroid_history)
    exchange = _phase14_wang_checkpoint_block(
        checkpoint, :field_exchange_state, :uptake_multiplier)
    relationships = _phase14_wang_checkpoint_block(
        checkpoint, :relationship_set, :wang_junctions)
    rac = _phase14_wang_property(checkpoint, :rac)
    rac_time = _phase14_wang_property(checkpoint, :rac_time)
    all(isfinite, field.payload.values) ||
        error("Wang field contains nonfinite values")
    all(isfinite, rac) ||
        error("Wang intracellular state contains nonfinite values")
    history.payload.latest_sample_mcs == UInt64(target_mcs) ||
        error("Wang history did not publish at the final target MCS")
    target_mcs >= 212 &&
        only(exchange.payload.initialized) != UInt8(1) &&
        error("Wang exchange calibration did not initialize")
    expected_cell_records =
        target_mcs < 122 ? 0 : target_mcs - 121
    expected_geometry =
        (target_mcs >= 91 ? 1 : 0) +
        (target_mcs >= 271 ? 1 : 0)
    cell_records = count(record ->
        record.observation === :wang_cell_records,
        observation_state.records)
    geometry_records = count(record ->
        record.observation === :wang_geometry,
        observation_state.records)
    cell_records == expected_cell_records ||
        error("Wang cell-record publication count differs")
    geometry_records == expected_geometry ||
        error("Wang geometry publication count differs")
    relationships.payload.count <= UInt32(16) ||
        error("Wang relationship capacity was exceeded")
    return Dict(
        "completed_mcs" => target_mcs,
        "field_time" => field.payload.time,
        "field_sum" => sum(field.payload.values),
        "field_minimum" => minimum(field.payload.values),
        "field_maximum" => maximum(field.payload.values),
        "history_latest_sample_mcs" =>
            Int(history.payload.latest_sample_mcs),
        "exchange_initialized" =>
            Int(only(exchange.payload.initialized)),
        "exchange_publication_epoch" =>
            Int(only(exchange.payload.publication_epoch)),
        "relationship_count" => Int(relationships.payload.count),
        "cell_record_count" => cell_records,
        "geometry_record_count" => geometry_records,
        "rac_minimum" => minimum(rac),
        "rac_maximum" => maximum(rac),
        "rac_time_minimum" => minimum(rac_time),
        "rac_time_maximum" => maximum(rac_time),
    )
end

function _phase14_wang_cpu_comparison(
        device_checkpoint, side::Int, target_mcs::Int)
    oracle = _wang_runtime_fixture(side)
    SciMLBase.step!(oracle.coupled, target_mcs)
    checkpoint = capture_checkpoint(oracle.coupled)
    field_device = _phase14_wang_checkpoint_block(
        device_checkpoint, :evolving_field, :wang_secretome).payload.values
    field_cpu = _phase14_wang_checkpoint_block(
        checkpoint, :evolving_field, :wang_secretome).payload.values
    rac_device = _phase14_wang_property(device_checkpoint, :rac)
    rac_cpu = _phase14_wang_property(checkpoint, :rac)
    field_error = maximum(abs.(field_device .- field_cpu))
    rac_error = maximum(abs.(rac_device .- rac_cpu))
    field_scale = max(maximum(abs, field_cpu), 1.0f0)
    rac_scale = max(maximum(abs, rac_cpu), 1.0f0)
    field_error <= 5.0f-4 * field_scale ||
        error("Wang CPU/device field comparison exceeded its preregistered tolerance")
    rac_error <= 5.0f-4 * rac_scale ||
        error("Wang CPU/device intracellular comparison exceeded its preregistered tolerance")
    return Dict(
        "oracle" => "sequential-cpu-float32-identical-canonical-plan",
        "field_maximum_absolute_error" => field_error,
        "field_relative_tolerance" => 5.0e-4,
        "rac_maximum_absolute_error" => rac_error,
        "rac_relative_tolerance" => 5.0e-4,
        "integer_schedule_exact" =>
            checkpoint.mcs == device_checkpoint.mcs,
    )
end

function qualify_phase14_wang_g3c_backend(
        name::String; profile::String = "paper")
    name in ("metal", "amdgpu") || throw(ArgumentError(
        "Wang G3-C requires --backend=metal or --backend=amdgpu"))
    profile in ("smoke", "paper") || throw(ArgumentError(
        "Wang G3-C profile must be smoke or paper"))
    _, device = load_backend(name)
    side = profile == "paper" ? 256 : 32
    target_mcs = profile == "paper" ? 500 : 212
    run = _phase14_build_wang_g3c(name, side)
    unobserved = _phase14_wang_unobserved_metrics!(run)
    performance_before = _metric_snapshot(run.metrics)
    sample = @timed begin
        SciMLBase.step!(
            run.coupled, target_mcs - Int(run.coupled.mcs))
        KernelAbstractions.synchronize(run.backend)
    end
    performance_after = _metric_snapshot(run.metrics)
    checkpoint = capture_checkpoint(run.coupled)
    invariants = _phase14_wang_final_invariants(
        checkpoint, run.coupled.observations, target_mcs)
    continuation = _phase14_wang_replay_restart(
        name, min(side, 32))
    comparison = _phase14_wang_cpu_comparison(
        checkpoint, side, target_mcs)
    backend_module = getfield(
        Main, name == "metal" ? :Metal : :AMDGPU)
    return Dict(
        "backend" => name,
        "device" => device,
        "profile" => profile,
        "side" => side,
        "target_mcs" => target_mcs,
        "number_type" => "Float32",
        "algorithm" => "SequentialCPM",
        "semantic_rng" => "Philox4x32x10V1",
        "g3b_contract_revision" => 7,
        "coupled_preflight" => "qualified_gpu_native",
        "capabilities" =>
            [String(row.capability) for row in run.report.rows],
        "coupled_array_count" => run.coupled_array_count,
        "coupled_array_bytes" => run.coupled_array_bytes,
        "scientific_state_bytes" =>
            scientific_state_bytes(run.coupled.potts.state),
        "packages" => Dict(
            "backend" => string(Base.pkgversion(backend_module)),
            "CorePotts" => string(Base.pkgversion(CorePotts)),
            "KernelAbstractions" =>
                string(Base.pkgversion(KernelAbstractions)),
        ),
        "unobserved" => unobserved,
        "performance" => Dict(
            "measured_mcs" => target_mcs - 2,
            "seconds" => sample.time,
            "seconds_per_mcs" =>
                sample.time / (target_mcs - 2),
            "julia_heap_bytes" => sample.bytes,
            "metrics" => _metric_delta(
                performance_after, performance_before),
        ),
        "invariants" => invariants,
        "continuation" => continuation,
        "cpu_comparison" => comparison,
    )
end

function phase14_wang_g3c_result(
        name::String, qualification::Dict)
    return Dict(
        "schema_version" =>
            PHASE14_WANG_G3C_EVIDENCE_SCHEMA,
        "suite" => PHASE14_WANG_G3C_SUITE,
        "generated_at_utc" => string(now(UTC)),
        "provenance" =>
            provenance(name, qualification["device"]),
        "qualification" => qualification,
    )
end

function write_phase14_wang_g3c_result(result::Dict)
    provenance_data = result["provenance"]
    qualification = result["qualification"]
    backend = qualification["backend"]
    profile = qualification["profile"]
    timestamp = Dates.format(
        now(UTC), dateformat"yyyymmddTHHMMSS")
    directory = joinpath(
        RESULTS_ROOT, provenance_data["subject_id"], backend)
    mkpath(directory)
    path = joinpath(
        directory,
        "$(timestamp)-phase14-wang-g3c-$(profile).toml")
    open(path, "w") do io
        TOML.print(io, result; sorted = true)
    end
    return path
end
