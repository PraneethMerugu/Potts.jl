# Structured CorePotts mechanism capability profiles.

"""Closed admission result for a typed execution capability key."""
@enum CapabilitySupportStatus::UInt8 begin
    Unsupported = 0x00
    Supported = 0x01
end
"""The typed execution contract is not admitted."""
Unsupported
"""The typed execution contract is admitted."""
Supported

"""Execution engine family encoded in a capability key."""
@enum CapabilityEngine::UInt8 begin
    SequentialEngine = 0x00
    CheckerboardEngine = 0x01
end
"""Host-sequential execution engine identity."""
SequentialEngine
"""Conflict-free checkerboard execution engine identity."""
CheckerboardEngine

"""Physical backend family encoded in a capability key."""
@enum CapabilityBackend::UInt8 begin
    CPUBackend = 0x00
    AdaptedBackend = 0x01
end
"""Host CPU backend identity."""
CPUBackend
"""Backend whose storage and execution are supplied by an adapter."""
AdaptedBackend

"""Per-dimension boundary topology encoded in a capability key."""
@enum CapabilityBoundaryTopology::UInt8 begin
    ClosedBoundary = 0x00
    PeriodicBoundary = 0x01
end
"""Nonwrapping boundary topology."""
ClosedBoundary
"""Wrapping periodic boundary topology."""
PeriodicBoundary

"""Replay guarantee class encoded in a capability key."""
@enum CapabilityReplayClass::UInt8 begin
    ExactConfigurationReplay = 0x00
end
"""Exact continuation for the recorded configuration and execution contract."""
ExactConfigurationReplay

"""Compiler math, reduction, and bounds semantics required by execution."""
struct CapabilityMathPolicy
    math::Symbol
    reductions::Symbol
    bounds::Symbol
end

"""Lifecycle features and fingerprint included in capability admission."""
struct CapabilityLifecycleProfile
    family::Symbol
    effect_mask::UInt8
    division_variant_mask::UInt16
    relationship_action_mask::UInt8
    state_action_masks::NTuple{5, UInt16}
    fingerprint::String
end

"""Component-state identities, domains, and schema included in admission."""
struct CapabilityComponentStateProfile
    scope::Symbol
    identities::Tuple
    domains::Tuple
    schema_fingerprint::String
end

"""
Exact execution-mechanism facts carried by a program capability key.

The fingerprints are inspection identities for the complete, concrete plans;
`support_family` identifies the typed execution protocol. `exact_replay`
records whether every non-Core mechanism has a durable package identity.
"""
struct CapabilityMechanismProfile
    proposal_fingerprint::String
    descriptor_fingerprint::String
    stage_fingerprint::String
    relationship_fingerprint::String
    tracker_fingerprint::String
    checkerboard_fingerprint::String
    rng_contract_version::VersionNumber
    rng_lowering_identity::Symbol
    code_identities::Tuple
    authority::Any
    support_family::Symbol
    exact_replay::Bool
end

function _capability_package_identity(module_value)
    root = Base.moduleroot(module_value)
    package = Base.identify_package(root, String(nameof(root)))
    return (
        name = package === nothing ? nameof(root) : Symbol(package.name),
        uuid = package === nothing ? "" : string(package.uuid),
        version = something(Base.pkgversion(root), v"0.0.0"),
    )
end

function _capability_environment_identity()
    options = Base.JLOptions()
    cpu_target = options.cpu_target == C_NULL ? "" :
                 unsafe_string(options.cpu_target)
    return (
        julia_version = VERSION,
        julia_commit = Base.GIT_VERSION_INFO.commit,
        julia_build_number = Base.GIT_VERSION_INFO.build_number,
        build_system_commit = Base.GIT_VERSION_INFO.build_system_commit,
        kernel = Sys.KERNEL,
        architecture = Sys.ARCH,
        machine = Sys.MACHINE,
        word_size = Sys.WORD_SIZE,
        byte_order = Base.ENDIAN_BOM == 0x04030201 ?
            :little_endian : :big_endian,
        cpu_name = Sys.CPU_NAME,
        cpu_threads = Sys.CPU_THREADS,
        cpu_target,
        julia_threads = Base.Threads.nthreads(),
        julia_threadpools = Base.Threads.nthreadpools(),
        llvm_version = Base.libllvm_version,
        compiler = (
            compile_enabled = Int(options.compile_enabled),
            opt_level = Int(options.opt_level),
            opt_level_min = Int(options.opt_level_min),
            debug_level = Int(options.debug_level),
            can_inline = Int(options.can_inline),
            polly = Int(options.polly),
            native_sysimage = Int(options.use_sysimage_native_code),
        ),
        math = (
            fast_math = Int(options.fast_math),
            check_bounds = Int(options.check_bounds),
        ),
        corepotts = _capability_package_identity(CorePotts),
        dependencies = (
            _capability_package_identity(Adapt),
            _capability_package_identity(Atomix),
            _capability_package_identity(KernelAbstractions),
            _capability_package_identity(LinearAlgebra),
            _capability_package_identity(SHA),
            _capability_package_identity(StaticArrays),
            _capability_package_identity(StructArrays),
        ),
    )
end

"""
The exact CorePotts mechanism conjunction covered by one capability row.

Potts may compose this with native-problem, component-solver, and
observation/event facts, but must not widen any field in this Core-owned key.
"""
struct ProgramCapabilityKey{
        N,
        T <: AbstractFloat,
        L <: CapabilityLifecycleProfile,
        C <: CapabilityComponentStateProfile,
        M <: CapabilityMechanismProfile,
        E <: NamedTuple,
    }
    engine::CapabilityEngine
    backend::CapabilityBackend
    device::Symbol
    dimension::Int16
    topology::NTuple{N, CapabilityBoundaryTopology}
    scalar_type::Type{T}
    math_policy::CapabilityMathPolicy
    lifecycle::L
    component_state::C
    mechanisms::M
    environment::E
    replay::CapabilityReplayClass
end

function ProgramCapabilityKey(
        engine::CapabilityEngine,
        backend::CapabilityBackend,
        device::Symbol,
        topology::NTuple{N, CapabilityBoundaryTopology},
        scalar_type::Type{T},
        math_policy::CapabilityMathPolicy,
        lifecycle::L,
        component_state::C,
        mechanisms::M,
        replay::CapabilityReplayClass,
        ; environment::E = _capability_environment_identity(),
    ) where {
        N,
        T <: AbstractFloat,
        L <: CapabilityLifecycleProfile,
        C <: CapabilityComponentStateProfile,
        M <: CapabilityMechanismProfile,
        E <: NamedTuple,
    }
    N <= typemax(Int16) || throw(ArgumentError(
        "capability-profile dimension exceeds Int16"
    ))
    return ProgramCapabilityKey{N, T, L, C, M, E}(
        engine,
        backend,
        device,
        Int16(N),
        topology,
        scalar_type,
        math_policy,
        lifecycle,
        component_state,
        mechanisms,
        environment,
        replay,
    )
end

"""
A structured CorePotts support report plus non-authorizing mechanism details.

The `state_domains`, `stage_effects`, relationship, tracker, and checkerboard
fields are inspection facts. They are deliberately not independent support
flags and cannot be combined to manufacture a broader profile claim.
"""
struct ProgramCapabilityReport{K <: ProgramCapabilityKey}
    key::K
    status::CapabilitySupportStatus
    reason::String
    exact_replay::Bool
    state_domains::Tuple
    stage_effects::Tuple
    relationships::Bool
    trackers::NamedTuple
    checkerboard_plan::Union{Nothing, NamedTuple}
end

"""Raised before an execution or replay boundary not covered by one admitted row."""
struct ProgramCapabilityError{R <: ProgramCapabilityReport} <: Exception
    operation::Symbol
    report::R
end

function Base.showerror(io::IO, error::ProgramCapabilityError)
    report = error.report
    key = report.key
    print(
        io,
        "CorePotts capability preflight rejected ",
        error.operation,
        ": status=", report.status,
        ", engine=", key.engine,
        ", backend=", key.backend,
        ", device=", key.device,
        ", dimension=", Int(key.dimension),
        ", topology=", key.topology,
        ", scalar_type=", key.scalar_type,
        ", replay=", key.replay,
        ", environment=", _capability_digest(key.environment),
        ", mechanism_family=", key.mechanisms.support_family,
        ", profile=", _capability_key_fingerprint(key),
        ". ", report.reason,
    )
end

@inline _capability_engine(::SequentialProgramEngine) = SequentialEngine
@inline _capability_engine(::CheckerboardProgramEngine) = CheckerboardEngine

@inline _capability_backend(::CPUProgramBackend) = CPUBackend
@inline _capability_backend(::AdaptedProgramBackend) = AdaptedBackend

@inline _capability_device(::CPUProgramBackend) = :host_cpu
@inline function _capability_device(::AdaptedProgramBackend{Name}) where {Name}
    return Name isa Symbol ? Name : Symbol(string(Name))
end

@inline _capability_boundary(periodic::Bool) =
    periodic ? PeriodicBoundary : ClosedBoundary

function _capability_lifecycle_profile(::NoLifecycleExecutionPlan)
    return CapabilityLifecycleProfile(
        :none,
        UInt8(0),
        UInt16(0),
        UInt8(0),
        ntuple(_ -> UInt16(0), 5),
        "none",
    )
end

function _capability_lifecycle_profile(plan::LifecycleExecutionPlan)
    return CapabilityLifecycleProfile(
        :core_lifecycle_v1,
        plan.effect_mask,
        plan.division_variant_mask,
        plan.relationship_action_mask,
        plan.state_action_masks,
        _lifecycle_plan_fingerprint(plan),
    )
end

function _capability_lifecycle_profile(plan::AbstractLifecycleExecutionPlan)
    fingerprint = bytes2hex(SHA.sha256(codeunits(repr((typeof(plan), plan)))))
    return CapabilityLifecycleProfile(
        :external,
        UInt8(0),
        UInt16(0),
        UInt8(0),
        ntuple(_ -> UInt16(0), 5),
        fingerprint,
    )
end

function _capability_component_state_profile(program::CompiledPottsProgram)
    schemas = map(
        entry -> entry.schema,
        program.descriptor_plan.state_layout.entries,
    )
    identities = Tuple(
        (
            path = Tuple(schema.identity.path),
            name = schema.identity.name,
            version = schema.version,
        )
        for schema in schemas
    )
    domains = Tuple(unique(schema.domain for schema in schemas))
    payload = Tuple(
        (
            identity = identities[index],
            domain = schema.domain,
            element_type = string(schema.element_type),
            shape = schema.shape,
            capacity = schema.capacity,
            layout = schema.layout,
            persistence = schema.persistence,
            lifecycle = repr(schema.lifecycle),
            read_policy = schema.read_policy,
            write_policy = schema.write_policy,
            adaptation = schema.adaptation,
            checkpoint_codec = schema.checkpoint_codec,
        )
        for (index, schema) in enumerate(schemas)
    )
    fingerprint = isempty(payload) ? "none" :
                  bytes2hex(SHA.sha256(codeunits(repr(payload))))
    scope = isempty(payload) ? :none : :core_auxiliary_state
    return CapabilityComponentStateProfile(
        scope, identities, domains, fingerprint
    )
end

@inline function _capability_digest(value)
    return bytes2hex(SHA.sha256(codeunits(repr(value))))
end

@inline function _capability_supports_engine_backend(
        support::DescriptorSupport,
        engine::CapabilityEngine,
        backend::CapabilityBackend,
    )
    device_supported = backend === CPUBackend ? support.cpu : support.gpu
    return device_supported && (
        engine === SequentialEngine ? support.sequential : support.checkerboard
    )
end

@inline function _capability_supports_engine_backend(
        support::TrackerSupport,
        engine::CapabilityEngine,
        backend::CapabilityBackend,
    )
    device_supported = backend === CPUBackend ? support.cpu : support.gpu
    return device_supported && (
        engine === SequentialEngine ? support.sequential : support.checkerboard
    )
end

@inline _capability_supports_engine_backend(
    _, ::CapabilityEngine, ::CapabilityBackend
) = false

function _capability_external_code_identities(values...)
    identities = NamedTuple[]
    stack = Any[values...]
    while !isempty(stack)
        value = pop!(stack)
        value === nothing && continue
        value isa Union{
            Bool,
            Number,
            AbstractString,
            Symbol,
            Char,
            VersionNumber,
            Type,
            Module,
        } && continue
        if value isa NamedTuple
            append!(stack, Base.values(value))
            continue
        elseif value isa Tuple
            append!(stack, value)
            continue
        elseif value isa Pair
            push!(stack, first(value), last(value))
            continue
        elseif value isa AbstractDict
            for (key, item) in value
                push!(stack, key, item)
            end
            continue
        elseif value isa AbstractArray
            append!(stack, value)
            continue
        end
        type = typeof(value)
        owner = Base.moduleroot(parentmodule(type))
        if !(owner === CorePotts || owner === Base || owner === Core)
            package = Base.identify_package(owner, String(nameof(owner)))
            identity = (
                name = package === nothing ? nameof(owner) : Symbol(package.name),
                uuid = package === nothing ? "" : string(package.uuid),
                version = try
                    Base.pkgversion(owner)
                catch
                    nothing
                end,
            )
            identity in identities || push!(identities, identity)
        end
        if isstructtype(type)
            for field in fieldnames(type)
                push!(stack, getfield(value, field))
            end
        end
    end
    sort!(identities; by = repr)
    return Tuple(identities)
end

function _capability_mechanism_support(program, admitted::Bool)
    admitted || return (:unsupported, (), nothing, false)
    identities = _capability_external_code_identities(
        program.descriptor_plan,
        program.stage_plan,
        program.tracker_plan,
        program.lifecycle_plan,
    )
    isempty(identities) &&
        return (:core_execution_protocol_v1, identities, nothing, true)
    authority = program.mechanism_authority
    identified = authority isa NamedTuple && hasproperty(authority, :package) &&
        all(==(authority.package), identities)
    return (:external_execution_protocol_v1, identities, authority, identified)
end

function _capability_descriptor_family_admitted(
        plan::DescriptorExecutionPlan,
        engine::CapabilityEngine,
        backend::CapabilityBackend,
    )
    return all(
        _capability_supports_engine_backend(
            descriptor_support(descriptor), engine, backend
        )
        for group in plan.groups
        for descriptor in group.launch.instances
    )
end
_capability_descriptor_family_admitted(
    _, ::CapabilityEngine, ::CapabilityBackend
) = false

function _capability_stage_family_admitted(
        plan::StageExecutionPlan,
        engine::CapabilityEngine,
        backend::CapabilityBackend,
    )
    return all(
        _capability_supports_engine_backend(
            descriptor_support(descriptor), engine, backend
        )
        for groups in (plan.accepted_copy, plan.after_mcs)
        for group in groups
        for descriptor in group.instances
    )
end
_capability_stage_family_admitted(
    _, ::CapabilityEngine, ::CapabilityBackend
) = false

function _capability_tracker_family_admitted(
        plan::TrackerExecutionPlan,
        engine::CapabilityEngine,
        backend::CapabilityBackend,
    )
    return all(
        _capability_supports_engine_backend(
            tracker_support(descriptor), engine, backend
        )
        for descriptor in plan.descriptors
    )
end
_capability_tracker_family_admitted(
    _, ::CapabilityEngine, ::CapabilityBackend
) = false

function _capability_relationship_family_admitted(relationships)
    return all(schema -> schema isa RelationshipStoreSchema, relationships)
end

@inline function _capability_checkerboard_family_admitted(
        ::NoCheckerboardPlan, engine::CapabilityEngine
    )
    return engine === SequentialEngine
end
@inline function _capability_checkerboard_family_admitted(
        ::CheckerboardPlan, engine::CapabilityEngine
    )
    return engine === CheckerboardEngine
end
_capability_checkerboard_family_admitted(_, ::CapabilityEngine) = false

function _capability_mechanism_profile(program::CompiledPottsProgram)
    engine = _capability_engine(program.engine)
    backend = _capability_backend(program.backend)
    admitted = _capability_mechanism_family_admitted(program, engine, backend)
    support_family, identities, authority, exact_replay =
        _capability_mechanism_support(program, admitted)
    proposal = (
        shape = program.shape,
        offsets = Matrix(program.proposal_offsets),
        kind_count = program.kind_count,
        medium_kind = program.medium_kind,
        medium_kinds = Tuple(program.medium_kinds),
        temperature = program.temperature,
        attempts_per_site = program.attempts_per_site,
        parameter_defaults = Tuple(program.parameter_defaults),
        ownership_change_handles = program.ownership_change_handles,
    )
    checkerboard = checkerboard_plan_report(program.checkerboard_plan)
    return CapabilityMechanismProfile(
        _capability_digest(proposal),
        _capability_digest(program.descriptor_plan),
        _capability_digest(program.stage_plan),
        _capability_digest(Tuple(program.relationships)),
        _capability_digest(program.tracker_plan),
        checkerboard === nothing ? "none" : _capability_digest(checkerboard),
        RNG_CONTRACT_VERSION,
        RNG_LOWERING_IDENTITY,
        identities,
        authority,
        support_family,
        exact_replay,
    )
end

@inline function _capability_mechanism_family_admitted(
        program::CompiledPottsProgram,
        engine::CapabilityEngine,
        backend::CapabilityBackend,
    )
    return _capability_descriptor_family_admitted(
        program.descriptor_plan, engine, backend
    ) && _capability_stage_family_admitted(
        program.stage_plan, engine, backend
    ) && _capability_tracker_family_admitted(
        program.tracker_plan, engine, backend
    ) && _capability_relationship_family_admitted(
        program.relationships
    ) && _capability_checkerboard_family_admitted(
        program.checkerboard_plan, engine
    )
end

function _capability_key(program::CompiledPottsProgram)
    return ProgramCapabilityKey(
        _capability_engine(program.engine),
        _capability_backend(program.backend),
        _capability_device(program.backend),
        map(_capability_boundary, program.periodic),
        eltype(program.parameter_defaults),
        CapabilityMathPolicy(:accurate, :deterministic, :checked),
        _capability_lifecycle_profile(program.lifecycle_plan),
        _capability_component_state_profile(program),
        _capability_mechanism_profile(program),
        ExactConfigurationReplay,
    )
end

function _capability_key_fingerprint(key::ProgramCapabilityKey)
    return bytes2hex(SHA.sha256(codeunits(repr(key))))
end

function _cpu_capability_disposition(key::ProgramCapabilityKey)
    if key.dimension != 2
        return (
            Unsupported,
            "CorePotts does not support execution for this lattice dimension.",
            false,
        )
    end
    if !(key.scalar_type === Float32 || key.scalar_type === Float64)
        return (
            Unsupported,
            "CorePotts does not support execution for this scalar policy.",
            false,
        )
    end
    if key.lifecycle.family === :external
        return (
            Unsupported,
            "CorePotts does not support this external lifecycle-plan family.",
            false,
        )
    end
    if key.mechanisms.support_family === :unsupported
        return (
            Unsupported,
            "At least one descriptor, stage, relationship, tracker, or checkerboard mechanism is unsupported by CorePotts.",
            false,
        )
    end
    return (
        Supported,
        "The typed CorePotts CPU execution contract supports this program.",
        key.mechanisms.exact_replay,
    )
end

"""Return an adapter's support status, reason, and replay guarantee for a key."""
function adapted_device_capability_disposition(
        ::Val, key::ProgramCapabilityKey
    )
    return (
        Unsupported,
        "Storage adaptation alone does not establish executable backend support.",
        false,
    )
end

"""Return the exact adapter environment identity incorporated into admission."""
adapted_device_environment(::Val{Name}, key::ProgramCapabilityKey) where {Name} =
    (provider = Name,)

"""Hash the complete typed capability key into a stable inspection identity."""
capability_key_fingerprint(key::ProgramCapabilityKey) =
    _capability_key_fingerprint(key)

function _capability_disposition(key::ProgramCapabilityKey)
    if key.backend === AdaptedBackend
        return adapted_device_capability_disposition(Val(key.device), key)
    end
    return _cpu_capability_disposition(key)
end

"""Report typed execution admission and exact-replay support for a compiled program."""
function program_capability_report(program::CompiledPottsProgram)
    key = _capability_key(program)
    status, reason, exact_replay = _capability_disposition(key)
    state_domains = key.component_state.domains
    stage_effects = Tuple(unique(
        nameof(typeof(descriptor.effect))
        for groups in (
            program.stage_plan.accepted_copy,
            program.stage_plan.after_mcs,
        )
        for group in groups
        for descriptor in group.instances
    ))
    return ProgramCapabilityReport(
        key,
        status,
        reason,
        exact_replay,
        state_domains,
        stage_effects,
        !isempty(program.relationships),
        tracker_plan_report(program.tracker_plan),
        checkerboard_plan_report(program.checkerboard_plan),
    )
end

function _adapted_program_capability_report(
        report::ProgramCapabilityReport, to
    )
    source = report.key
    device = nameof(to)
    environment = merge(source.environment, (
        adapted_backend = adapted_device_environment(Val(device), source),
    ))
    key = ProgramCapabilityKey(
        source.engine,
        AdaptedBackend,
        device,
        source.topology,
        source.scalar_type,
        source.math_policy,
        source.lifecycle,
        source.component_state,
        source.mechanisms,
        source.replay,
        ; environment,
    )
    status, reason, exact_replay = _capability_disposition(key)
    return ProgramCapabilityReport(
        key,
        status,
        reason,
        exact_replay,
        report.state_domains,
        report.stage_effects,
        report.relationships,
        report.trackers,
        report.checkerboard_plan,
    )
end

"""Return whether a capability report admits functional execution."""
capability_authorizes_execution(report::ProgramCapabilityReport) =
    report.status === Supported

"""Return whether a report admits exact checkpoint continuation."""
function capability_authorizes_replay(
        report::ProgramCapabilityReport;
        replay::CapabilityReplayClass = report.key.replay,
    )
    return capability_authorizes_execution(report) && report.exact_replay &&
           report.key.replay === replay &&
           replay === ExactConfigurationReplay
end

function _require_program_execution_capability(
        report::ProgramCapabilityReport;
        operation::Symbol = :execution,
    )
    capability_authorizes_execution(report) ||
        throw(ProgramCapabilityError(operation, report))
    return report
end

function _require_program_execution_capability(
        program::CompiledPottsProgram;
        operation::Symbol = :execution,
    )
    return _require_program_execution_capability(
        program_capability_report(program); operation
    )
end

function _require_program_replay_capability(
        report::ProgramCapabilityReport;
        operation::Symbol = :replay,
        replay::CapabilityReplayClass = ExactConfigurationReplay,
    )
    capability_authorizes_replay(report; replay) ||
        throw(ProgramCapabilityError(operation, report))
    return report
end

function _require_program_replay_capability(
        program::CompiledPottsProgram;
        operation::Symbol = :replay,
        replay::CapabilityReplayClass = ExactConfigurationReplay,
    )
    return _require_program_replay_capability(
        program_capability_report(program); operation, replay
    )
end
