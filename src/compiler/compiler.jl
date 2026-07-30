function _validate_compilation_choices(
        completed::PottsSystem,
        engine,
        backend,
        scalar_type,
    )
    iscomplete(completed) ||
        throw(ArgumentError("compile requires a completed PottsSystem"))
    engine isa AbstractPottsEngine ||
        throw(ArgumentError("engine must be SequentialEngine() or CheckerboardEngine()"))
    backend isa CPUBackend ||
        throw(ArgumentError("V1 currently admits only CPUBackend()"))
    scalar_type isa Type && scalar_type <: AbstractFloat ||
        throw(ArgumentError("scalar_type must be a concrete AbstractFloat type"))
    isconcretetype(scalar_type) ||
        throw(ArgumentError("scalar_type must be concrete"))
    capabilities = inspect(completed, Capabilities())
    engine isa SequentialEngine && !capabilities.sequential &&
        throw(ArgumentError("completed system is not admitted by SequentialEngine"))
    if engine isa CheckerboardEngine && !capabilities.checkerboard
        reasons = join(
            ("$(identity): $reason"
             for (identity, reason) in capabilities.checkerboard_rejections),
            "; ",
        )
        throw(ArgumentError(
            "completed system is not admitted by CheckerboardEngine: $reasons"
        ))
    end
    return nothing
end

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
    manifest = _build_parameter_manifest(completed, scalar_type)
    completion_fingerprint = completed_system_fingerprint(completed)
    seed = _sha256_hex(
        "potts-executable-seed-v1",
        completion_fingerprint.hex,
        nameof(typeof(engine)),
        nameof(typeof(backend)),
        scalar_type,
        Tuple((entry.name, entry.default, entry.required, entry.unit)
            for entry in manifest),
    )
    core_program, kinds = _lower_core_program(
        completed, engine, backend, scalar_type, manifest, seed
    )
    _assert_concrete_core_boundary(core_program)
    execution = CorePotts.program_execution_report(core_program)
    capability = CorePotts.program_capability_report(core_program)
    storage = _storage_report(core_program)
    workspace = _workspace_report(core_program)
    reports = (
        execution,
        capability,
        storage,
        workspace,
        schedule = inspect(completed, Schedule()),
        replay = (
            class = :exact_same_executable,
            cross_engine = false,
            addressed_rng = true,
        ),
        checkpoint = (schema = v"1.0.0", logical_only = true),
        kinds,
    )
    observations = Tuple(
        statement for statement in _all_system_statements(completed)
        if statement isa Observation
    )
    states = Tuple(
        (
            variable = _statement_arguments(statement).variable,
            name = Symbol(statement_id(statement)),
            kind = statement_kind(statement),
        )
        for statement in _all_system_statements(completed)
        if statement isa Union{
            SiteState, CellState, MediumState, ModelState, FieldState, HistoryState
        } && haskey(_statement_arguments(statement), :variable)
    )
    reports = merge(reports, (; states))
    fingerprint = ExecutableFingerprint(_sha256_hex(
        "potts-executable-v1", seed, core_program.fingerprint, reports
    ))
    return PottsExecutable(
        completed, core_program, manifest, reports, observations, fingerprint
    )
end
