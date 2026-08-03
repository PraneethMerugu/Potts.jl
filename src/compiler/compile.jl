# Top-level compiler orchestration only.

"""
    compile(completed; engine, backend, scalar_type)

Lower a completed symbolic system into one immutable, reusable executable.
All three execution choices are mandatory.
"""
function compile(
        completed::PottsSystem;
        engine,
        backend,
        scalar_type,
    )
    _validate_compilation_choices(completed, engine, backend, scalar_type)
    analyzed_ir = _analyze_completed_system(completed)
    diagnostics = PottsDiagnostic[]
    _validate_compilation_coverage!(diagnostics, completed)
    _validate_equation_and_event_coverage!(diagnostics, completed)
    _throw_diagnostics(:compilation, diagnostics)
    manifest = _build_parameter_manifest(completed, scalar_type)
    relationship_endpoint_policies =
        _compile_relationship_endpoint_policies(analyzed_ir)
    lowered_descriptors = _lower_descriptor_plan(
        analyzed_ir,
        manifest,
        scalar_type,
        relationship_endpoint_policies,
    )
    descriptor_plan = lowered_descriptors.plan
    stage_plan = _lower_stage_plan(
        analyzed_ir,
        manifest,
        scalar_type,
        lowered_descriptors.state_handles,
        lowered_descriptors.draw_handles,
        descriptor_plan.state_layout,
        relationship_endpoint_policies,
    )
    lifecycle_plan = _lower_lifecycle_plan(
        analyzed_ir,
        manifest,
        scalar_type,
        lowered_descriptors.state_handles,
        lowered_descriptors.draw_handles,
        descriptor_plan.state_layout,
        relationship_endpoint_policies,
    )
    _assert_concrete_core_boundary(
        descriptor_plan; path = "descriptor_plan"
    )
    _assert_concrete_core_boundary(stage_plan; path = "stage_plan")
    _assert_concrete_core_boundary(lifecycle_plan; path = "lifecycle_plan")
    completion_fingerprint = completed_system_fingerprint(completed)
    seed = _sha256_hex(
        "potts-executable-seed-v1",
        completion_fingerprint.hex,
        nameof(typeof(engine)),
        nameof(typeof(backend)),
        scalar_type,
        Tuple((entry.name, entry.required, entry.unit)
            for entry in manifest),
    )
    core_program, kinds, observation_manifest = _lower_core_program(
        analyzed_ir,
        engine,
        backend,
        scalar_type,
        manifest,
        descriptor_plan,
        stage_plan,
        lifecycle_plan,
        relationship_endpoint_policies,
        seed,
    )
    _assert_concrete_core_boundary(core_program)
    execution = CorePotts.program_execution_report(core_program)
    capability = CorePotts.program_capability_report(core_program)
    storage = _storage_report(core_program)
    workspace = _workspace_report(core_program)
    statement_manifest = _compiled_statement_manifest(completed)
    completion_fingerprints = inspect(completed, Fingerprints())
    compiled_schedule = NamedTuple[
        (
            identity = _manifest_identity(record.identity),
            phase = record.phase === nothing ? nothing : nameof(typeof(record.phase)),
        )
        for record in inspect(completed, Schedule())
    ]
    records = analyzed_ir.source.records
    states = _compiled_state_manifest(
        completed,
        records,
        manifest,
        descriptor_plan.state_layout,
        core_program.shape,
        scalar_type,
    )
    relationship_states = Tuple(
        let
            statement = _relationship_policy_record(
                analyzed_ir, endpoint_policy
            )
            payload = _statement_option(statement, :payload, NamedTuple())
            (
                name = _qualified_public_name(statement.identity),
                local_name = Symbol(statement.identity.local_id),
                identity = _qualified_resource_identity(statement.identity),
                capacity = Int(_numeric_value(
                    _statement_option(statement, :capacity)
                )),
                maximum_degree = Int(_numeric_value(
                    _statement_option(statement, :maximum_degree)
                )),
                endpoints = (
                    direction = endpoint_policy.direction,
                    kind_a = endpoint_policy.kind_a_name,
                    kind_b = endpoint_policy.kind_b_name,
                ),
                lifecycle = nameof(typeof(_statement_option(
                    statement, :lifecycle, RejectEndpointRetirement()
                ))),
                payload_units = NamedTuple{keys(payload)}(map(
                    value -> _compiled_value_unit(value, manifest),
                    values(payload),
                )),
            )
        end
        for endpoint_policy in relationship_endpoint_policies
    )
    time = _compiled_time_contract(records)
    external_io = _compiled_external_io(
        completed,
        manifest,
        states,
        observation_manifest,
        core_program.shape,
        scalar_type,
    )
    reports = (
        execution,
        capability,
        compiler = _compiler_analysis_report(analyzed_ir),
        descriptors = CorePotts.descriptor_plan_report(descriptor_plan),
        lifecycle = CorePotts.lifecycle_plan_report(lifecycle_plan),
        storage,
        workspace,
        statements = statement_manifest,
        variables = Tuple(
            _manifest_symbol(value)
            for value in inspect(completed, Variables())
        ),
        schedule = compiled_schedule,
        replay = (
            class = :exact_same_executable,
            cross_engine = false,
            addressed_rng = true,
        ),
        checkpoint = (schema = v"1.0.0", logical_only = true),
        kinds = Tuple(entry.name for entry in kinds),
        kind_identities = kinds,
        fingerprints = completion_fingerprints,
        states,
        relationship_states,
        external_io,
        time,
    )
    observations = observation_manifest
    fingerprint_states = Tuple(
        (
            key = state.key,
            name = state.name,
            kind = state.kind,
            role = state.role,
            storage = state.storage,
            shape = state.shape,
            scalar_type = state.scalar_type,
            unit = state.unit,
        )
        for state in states
    )
    fingerprint_reports = merge(reports, (states = fingerprint_states,))
    fingerprint = ExecutableFingerprint(_sha256_hex(
        "potts-executable-v1",
        seed,
        core_program.fingerprint,
        fingerprint_reports,
    ))
    executable = PottsExecutable(
        core_program,
        manifest,
        relationship_endpoint_policies,
        reports,
        observations,
        fingerprint,
    )
    _assert_concrete_core_boundary(executable; path = "executable")
    return executable
end
