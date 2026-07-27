abstract type AbstractExecutor end

"""
Production immutable-topology serial execution policy.

The value contains only semantic policy. Mutable execution state belongs to
`SerialRuntime`. Explicit construction is fail-closed (`qualification=:strict`);
the one-argument `initialize_runtime` compatibility façade uses
`:legacy_compatibility` solely to preserve PB0/15.A/15.B evidence.
"""
struct SerialExecutor <: AbstractExecutor
    contract_version::String
    qualification::Symbol
    root_seed::NormalizedRootSeed
    observation_plan::ObservationPlan
    continuation_schemas::Tuple
    activation_bound::Int
    failure_injection::FailureInjection
end

function SerialExecutor(;
    qualification::Symbol=:strict,
    root_seed=0,
    observation_plan::ObservationPlan=ObservationPlan(),
    continuation_schemas=(),
    activation_bound::Integer=1024,
    failure_injection::FailureInjection=FailureInjection(),
)
    qualification in (:strict, :legacy_compatibility) ||
        _fail(:invalid_executor_qualification,
            "executor qualification must be strict or legacy_compatibility")
    activation_bound > 0 ||
        _fail(:invalid_activation_bound,
            "reactive activation bound must be positive")
    activation_bound <= typemax(Int) ||
        _fail(:activation_bound_overflow,
            "reactive activation bound exceeds Int")
    seed = root_seed isa NormalizedRootSeed ?
        root_seed : NormalizedRootSeed(root_seed)
    schemas = tuple(continuation_schemas...)
    all(pair -> pair isa Pair && first(pair) isa AbstractString &&
        last(pair) isa ContinuationSchema, schemas) ||
        _fail(:invalid_continuation_registry,
            "continuation schemas must be owner => ContinuationSchema pairs")
    owners = String[String(first(pair)) for pair in schemas]
    length(owners) == length(unique(owners)) ||
        _fail(:duplicate_continuation_spec,
            "continuation registry contains duplicate owners")
    SerialExecutor(
        "serial-executor-v1",
        qualification,
        seed,
        observation_plan,
        tuple(sort!(collect(schemas);
            by=pair -> String(first(pair)))...),
        Int(activation_bound),
        failure_injection,
    )
end

function _registered_schema(executor::SerialExecutor, owner::AbstractString)
    position = findfirst(pair -> String(first(pair)) == owner,
        executor.continuation_schemas)
    isnothing(position) ? nothing :
        last(executor.continuation_schemas[position])
end

_schedule_identity(schedule::AbstractSchedule) =
    canonical_fingerprint((:schedule_contract_v1, schedule))
_schedule_identity(::StepDeclaration) =
    canonical_fingerprint((:reactive_step_schedule_v1,))

function _continuation_spec(executor::SerialExecutor, declaration)
    registered = _registered_schema(executor, declaration.id)
    schema = if !isnothing(registered)
        registered
    else
        declared = continuation_schema(declaration.law)
        if executor.qualification === :legacy_compatibility &&
                declared.codec isa NoContinuationCodec
            ContinuationSchema(
                "legacy-untracked-any",
                LegacyUntrackedContinuation{Any}();
                version=declaration.continuation_version,
                invalidated_by=(:owner_version, :schedule, :schema),
            )
        else
            declared
        end
    end
    schedule_identity = declaration isa ProcessDeclaration ?
        _schedule_identity(declaration.schedule) :
        _schedule_identity(declaration)
    bind_continuation(
        declaration.id,
        semantic_version(declaration.law),
        schedule_identity,
        schema,
    )
end

function _runtime_policy_identity(
    executor::SerialExecutor,
    composite::CompiledComposite,
)
    process_specs = tuple(((
        entry.declaration.id,
        _continuation_spec(executor, entry.declaration),
    ) for entry in composite.plan.processes)...)
    step_specs = tuple(((
        entry.declaration.id,
        _continuation_spec(executor, entry.declaration),
    ) for entry in composite.plan.steps)...)
    (
        executor.contract_version,
        executor.qualification,
        model_fingerprint(composite),
        execution_plan_fingerprint(composite),
        SEMANTIC_RNG_ALGORITHM,
        SEMANTIC_RNG_ADDRESS_SCHEMA,
        executor.root_seed,
        executor.observation_plan.fingerprint,
        process_specs,
        step_specs,
        composite.plan.iterations,
        executor.activation_bound,
    )
end

runtime_fingerprint(
    executor::SerialExecutor,
    composite::CompiledComposite,
) = canonical_fingerprint((
    :serial_runtime_policy_v1,
    _runtime_policy_identity(executor, composite),
))

function _validate_executor(
    executor::SerialExecutor,
    composite::CompiledComposite,
)
    scale = composite.plan.scale
    process_ids = Set(entry.declaration.id
        for entry in composite.plan.processes)
    step_ids = Set(entry.declaration.id for entry in composite.plan.steps)
    observer_ids = Set(observer.id
        for observer in executor.observation_plan.observers)
    admitted = union(process_ids, step_ids, observer_ids)
    for pair in executor.continuation_schemas
        owner = String(first(pair))
        owner in admitted || _fail(:unknown_continuation_owner,
            "continuation registry references an unknown owner"; owner)
    end
    for entry in composite.plan.processes
        schedule = entry.declaration.schedule
        schedule.first_due.scale == scale ||
            _fail(:time_scale_mismatch,
                "process schedule does not use the compiled time scale";
                process=entry.declaration.id)
        spec = _continuation_spec(executor, entry.declaration)
        validate_continuation(
            spec,
            entry.declaration.id,
            entry.declaration.continuation,
        )
        if executor.qualification === :strict && !alpha_eligible(spec)
            _fail(:unqualified_continuation,
                "strict serial execution rejects legacy untracked continuation";
                owner=entry.declaration.id)
        end
    end
    for entry in composite.plan.steps
        spec = _continuation_spec(executor, entry.declaration)
        validate_continuation(
            spec,
            entry.declaration.id,
            entry.declaration.continuation,
        )
        executor.qualification === :strict && !alpha_eligible(spec) &&
            _fail(:unqualified_continuation,
                "strict serial execution rejects legacy untracked continuation";
                owner=entry.declaration.id)
    end
    for observer in executor.observation_plan.observers
        schedule = observer.schedule
        if schedule isa PeriodicObservationSchedule
            schedule.cadence.scale == scale &&
                schedule.first_due.scale == scale ||
                _fail(:time_scale_mismatch,
                    "observer schedule does not use the compiled time scale";
                    observer=observer.id)
        elseif schedule isa AtTimesObservationSchedule
            all(time -> time.scale == scale && time.tick >= 0,
                schedule.times) ||
                _fail(:time_scale_mismatch,
                    "observer at-times schedule is outside the compiled time domain";
                    observer=observer.id)
        end
        for target in observer.paths
            schema_at(composite.plan.schema, target)
        end
        validate_continuation(observer.continuation_spec, observer.id,
            observer.continuation)
        executor.qualification === :strict &&
                !alpha_eligible(observer.continuation_spec) &&
            _fail(:unqualified_continuation,
                "strict serial execution rejects legacy observer continuation";
                owner=observer.id)
    end
    runtime_fingerprint(executor, composite)
end

function _canonical(io::IO, executor::SerialExecutor)
    write(io, "SE")
    _canonical(io, executor.contract_version)
    _canonical(io, executor.qualification)
    _canonical(io, executor.root_seed)
    _canonical(io, executor.observation_plan.fingerprint)
    _canonical(io, executor.continuation_schemas)
    _canonical(io, executor.activation_bound)
end
