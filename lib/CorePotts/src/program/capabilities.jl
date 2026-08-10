# Structured CorePotts mechanism capability profiles.

@enum CapabilitySupportStatus::UInt8 begin
    Unsupported = 0x00
    Experimental = 0x01
    Supported = 0x02
end

@enum CapabilityMaturity::UInt8 begin
    InterfaceOnly = 0x00
    Compiles = 0x01
    Functional = 0x02
    ReplayQualified = 0x03
    PerformanceQualified = 0x04
end

@enum CapabilityEngine::UInt8 begin
    SequentialEngine = 0x00
    CheckerboardEngine = 0x01
end

@enum CapabilityBackend::UInt8 begin
    CPUBackend = 0x00
    AdaptedBackend = 0x01
end

@enum CapabilityBoundaryTopology::UInt8 begin
    ClosedBoundary = 0x00
    PeriodicBoundary = 0x01
end

@enum CapabilityReplayClass::UInt8 begin
    ExactConfigurationReplay = 0x00
    PortableLogicalRestart = 0x01
    StatisticalRestart = 0x02
end

struct CapabilityMathPolicy
    math::Symbol
    reductions::Symbol
    bounds::Symbol
end

struct CapabilityLifecycleProfile
    family::Symbol
    effect_mask::UInt8
    division_variant_mask::UInt16
    relationship_action_mask::UInt8
    state_action_masks::NTuple{5, UInt16}
    fingerprint::String
end

struct CapabilityComponentStateProfile
    scope::Symbol
    identities::Tuple
    domains::Tuple
    schema_fingerprint::String
end

"""
Exact execution-mechanism facts carried by a program capability key.

The fingerprints are inspection identities for the complete, concrete plans;
`qualification_family` is assigned only after the whole conjunction satisfies
one closed CorePotts protocol family.  Individual mechanisms never authorize
execution independently.
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
    qualification_family::Symbol
end

const _REVIEWED_MECHANISM_AUTHORITIES = ((
    authority = :PottsToolkit,
    package = (
        name = :PottsToolkit,
        uuid = "e4c62a4c-8889-4cc8-ad3a-75efc86c53b9",
        version = v"0.2.0",
    ),
    suite = :g5h1_potts_compiler_mechanisms,
    revision = v"1.0.0",
),)

# Exact replay evidence is deliberately finite. Other environments may still
# execute a functionally admitted CPU profile, but cannot acquire a replay row
# merely by hashing their current process. Additions require retained review
# evidence for the complete environment identity.
const _REVIEWED_EXACT_ENVIRONMENT_DIGESTS = (
    # Canonical Julia 1.12.1, one thread, default bounds policy. This is the
    # production/reproduction row recorded by the G5H-1 quantitative audit.
    "c869ed68289ea1a641d8ed8c05e684693b08b2bb0b90fc2cc211e0b9da48a969",
    # The same reviewed environment with `--check-bounds=yes`, which is the
    # policy used by Julia's authoritative `Pkg.test` harness. Keeping this as
    # a separate closed row preserves the exact-environment replay boundary;
    # the test process does not acquire evidence by hashing itself.
    "80d86547549b8803a75311c347e74e4e44fbe1c550e1f20bc937003d850baefe",
    # LW-0 qualification candidate on the same Apple M1 Pro host under Julia
    # 1.12.6, one thread, default bounds policy. This row remains subject to
    # the exact-candidate LW-R0 preservation review.
    "281cfbf41f362e63ec7005a8b5b9f536b67cd51d1d79a6847d60e63069f1f38b",
    # The matching Julia 1.12.6 `Pkg.test` process with `--check-bounds=yes`.
    # It is a separate closed identity rather than a wildcarded environment.
    "0b1726268dbde8e3f38c9186ed2eb07a684bc04818c3ba38793da886eb035d1a",
)

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
            _capability_package_identity(AcceleratedKernels),
            _capability_package_identity(Adapt),
            _capability_package_identity(Atomix),
            _capability_package_identity(KernelAbstractions),
            _capability_package_identity(LinearAlgebra),
            _capability_package_identity(SHA),
        ),
    )
end

"""
The exact CorePotts mechanism conjunction covered by one capability row.

PottsToolkit may compose this with native-problem, component-solver, and
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

"""Stable identity of the evidence attached to one exact mechanism row."""
struct CapabilityEvidenceIdentity
    authority::Symbol
    suite::Symbol
    revision::VersionNumber
    profile_fingerprint::String
end

"""
A structured CorePotts capability row plus non-authorizing mechanism details.

The `state_domains`, `stage_effects`, relationship, tracker, and checkerboard
fields are inspection facts. They are deliberately not independent support
flags and cannot be combined to manufacture a broader profile claim.
"""
struct ProgramCapabilityReport{K <: ProgramCapabilityKey}
    key::K
    status::CapabilitySupportStatus
    maturity::CapabilityMaturity
    reason::String
    evidence::Union{Nothing, CapabilityEvidenceIdentity}
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
        ", maturity=", report.maturity,
        ", engine=", key.engine,
        ", backend=", key.backend,
        ", device=", key.device,
        ", dimension=", Int(key.dimension),
        ", topology=", key.topology,
        ", scalar_type=", key.scalar_type,
        ", replay=", key.replay,
        ", environment=", _capability_digest(key.environment),
        ", mechanism_family=", key.mechanisms.qualification_family,
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

@inline function _capability_supports_cpu_engine(
        support::DescriptorSupport, engine::CapabilityEngine
    )
    return support.cpu && (
        engine === SequentialEngine ? support.sequential : support.checkerboard
    )
end

@inline function _capability_supports_cpu_engine(
        support::TrackerSupport, engine::CapabilityEngine
    )
    return support.cpu && (
        engine === SequentialEngine ? support.sequential : support.checkerboard
    )
end

@inline _capability_supports_cpu_engine(_, ::CapabilityEngine) = false

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

function _capability_mechanism_qualification(program, admitted::Bool)
    admitted || return (:unqualified, (), nothing)
    identities = _capability_external_code_identities(
        program.descriptor_plan,
        program.stage_plan,
        program.tracker_plan,
        program.lifecycle_plan,
    )
    isempty(identities) && return (
        :core_execution_protocol_v1, identities, nothing
    )
    authority = program.mechanism_authority
    reviewed = authority in _REVIEWED_MECHANISM_AUTHORITIES
    reviewed && all(==(authority.package), identities) && return (
        :evidenced_execution_protocol_v1, identities, authority
    )
    return (:external_execution_protocol_v1, identities, authority)
end

function _capability_descriptor_family_admitted(
        plan::DescriptorExecutionPlan, engine::CapabilityEngine
    )
    return all(
        _capability_supports_cpu_engine(
            descriptor_support(descriptor), engine
        )
        for group in plan.groups
        for descriptor in group.launch.instances
    )
end
_capability_descriptor_family_admitted(_, ::CapabilityEngine) = false

function _capability_stage_family_admitted(
        plan::StageExecutionPlan, engine::CapabilityEngine
    )
    return all(
        _capability_supports_cpu_engine(
            descriptor_support(descriptor), engine
        )
        for groups in (plan.accepted_copy, plan.after_mcs)
        for group in groups
        for descriptor in group.instances
    )
end
_capability_stage_family_admitted(_, ::CapabilityEngine) = false

function _capability_tracker_family_admitted(
        plan::TrackerExecutionPlan, engine::CapabilityEngine
    )
    return all(
        _capability_supports_cpu_engine(tracker_support(descriptor), engine)
        for descriptor in plan.descriptors
    )
end
_capability_tracker_family_admitted(_, ::CapabilityEngine) = false

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
    admitted = _capability_mechanism_family_admitted(program, engine)
    qualification, identities, authority =
        _capability_mechanism_qualification(program, admitted)
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
        qualification,
    )
end

@inline function _capability_mechanism_family_admitted(
        program::CompiledPottsProgram, engine::CapabilityEngine
    )
    return _capability_descriptor_family_admitted(
        program.descriptor_plan, engine
    ) && _capability_stage_family_admitted(
        program.stage_plan, engine
    ) && _capability_tracker_family_admitted(
        program.tracker_plan, engine
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

const _SEQUENTIAL_CPU_QUALIFIED_EVIDENCE = CapabilityEvidenceIdentity(
    :CorePotts,
    :lw0_sequential_cpu_exact_replay_v1,
    v"1.0.0",
    bytes2hex(SHA.sha256(codeunits(
        "CorePotts/lw0/sequential-cpu/core-execution-protocol-v1"
    ))),
)

const _CHECKERBOARD_CPU_QUALIFIED_EVIDENCE = CapabilityEvidenceIdentity(
    :CorePotts,
    :lw0_checkerboard_random_color_cpu_exact_replay_v1,
    v"1.0.0",
    bytes2hex(SHA.sha256(codeunits(
        "CorePotts/lw0/checkerboard-random-color-cpu/core-execution-protocol-v1"
    ))),
)

# Closed authority rows.  These rows qualify a whole profile family; report
# fingerprints never create evidence identities dynamically.
const _QUALIFIED_CAPABILITY_FAMILIES = (
    (
        engine = SequentialEngine,
        backend = CPUBackend,
        device = :host_cpu,
        dimensions = (Int16(2),),
        topologies = (
            (ClosedBoundary, ClosedBoundary),
            (ClosedBoundary, PeriodicBoundary),
            (PeriodicBoundary, ClosedBoundary),
            (PeriodicBoundary, PeriodicBoundary),
        ),
        scalar_types = (Float32, Float64),
        math_policy = CapabilityMathPolicy(:accurate, :deterministic, :checked),
        lifecycle_families = (:none, :core_lifecycle_v1),
        component_scopes = (:none, :core_auxiliary_state),
        mechanism_families = (
            :core_execution_protocol_v1,
            :evidenced_execution_protocol_v1,
        ),
        rng_contract_versions = (RNG_CONTRACT_VERSION,),
        rng_lowering_identities = (RNG_LOWERING_IDENTITY,),
        environment_digests = _REVIEWED_EXACT_ENVIRONMENT_DIGESTS,
        replay = ExactConfigurationReplay,
        evidence = _SEQUENTIAL_CPU_QUALIFIED_EVIDENCE,
    ),
    (
        engine = CheckerboardEngine,
        backend = CPUBackend,
        device = :host_cpu,
        dimensions = (Int16(2),),
        topologies = (
            (ClosedBoundary, ClosedBoundary),
            (ClosedBoundary, PeriodicBoundary),
            (PeriodicBoundary, ClosedBoundary),
            (PeriodicBoundary, PeriodicBoundary),
        ),
        scalar_types = (Float32, Float64),
        math_policy = CapabilityMathPolicy(:accurate, :deterministic, :checked),
        lifecycle_families = (:none, :core_lifecycle_v1),
        component_scopes = (:none, :core_auxiliary_state),
        mechanism_families = (
            :core_execution_protocol_v1,
            :evidenced_execution_protocol_v1,
        ),
        rng_contract_versions = (RNG_CONTRACT_VERSION,),
        rng_lowering_identities = (RNG_LOWERING_IDENTITY,),
        environment_digests = _REVIEWED_EXACT_ENVIRONMENT_DIGESTS,
        replay = ExactConfigurationReplay,
        evidence = _CHECKERBOARD_CPU_QUALIFIED_EVIDENCE,
    ),
)

"""
Bind a reviewed parametric evidence suite to one complete capability key.

Family membership decides admission; hashing the exact key only identifies the
row that the already-selected suite covers. A program outside the closed
family never reaches this function and therefore cannot manufacture evidence
by changing a mechanism fingerprint.
"""
function _exact_capability_evidence(
        template::CapabilityEvidenceIdentity,
        key::ProgramCapabilityKey,
    )
    return CapabilityEvidenceIdentity(
        template.authority,
        template.suite,
        template.revision,
        _capability_key_fingerprint(key),
    )
end

function _functional_capability_evidence(key::ProgramCapabilityKey)
    external = key.mechanisms.qualification_family ===
        :external_execution_protocol_v1
    suite = if key.engine === SequentialEngine
        external ? :sequential_external_cpu_protocol_v1 :
            :sequential_cpu_protocol_v1
    else
        external ? :checkerboard_external_cpu_protocol_v1 :
            :checkerboard_cpu_protocol_v1
    end
    template = CapabilityEvidenceIdentity(
        :CorePotts,
        suite,
        v"1.0.0",
        bytes2hex(SHA.sha256(codeunits(string(:CorePotts, '/', suite)))),
    )
    return _exact_capability_evidence(template, key)
end

function _qualified_capability_family(key::ProgramCapabilityKey)
    for family in _QUALIFIED_CAPABILITY_FAMILIES
        key.engine === family.engine || continue
        key.backend === family.backend || continue
        key.device === family.device || continue
        key.dimension in family.dimensions || continue
        key.topology in family.topologies || continue
        key.scalar_type in family.scalar_types || continue
        key.math_policy == family.math_policy || continue
        key.lifecycle.family in family.lifecycle_families || continue
        key.component_state.scope in family.component_scopes || continue
        key.mechanisms.qualification_family in family.mechanism_families || continue
        key.mechanisms.rng_contract_version in
            family.rng_contract_versions || continue
        key.mechanisms.rng_lowering_identity in
            family.rng_lowering_identities || continue
        _capability_digest(key.environment) in family.environment_digests || continue
        key.replay === family.replay || continue
        return family
    end
    return nothing
end

function _cpu_capability_disposition(key::ProgramCapabilityKey)
    if key.dimension != 2
        return (
            Unsupported,
            Compiles,
            "The exact program is compiled, but CorePotts has no functional evidence for this lattice dimension.",
            nothing,
        )
    end
    if !(key.scalar_type === Float32 || key.scalar_type === Float64)
        return (
            Unsupported,
            Compiles,
            "The exact program is compiled, but CorePotts has no functional evidence for this scalar policy.",
            nothing,
        )
    end
    if key.lifecycle.family === :external
        return (
            Unsupported,
            Compiles,
            "External lifecycle-plan families have no CorePotts functional evidence row.",
            nothing,
        )
    end
    if key.mechanisms.qualification_family === :unqualified
        return (
            Unsupported,
            Compiles,
            "At least one descriptor, stage, relationship, tracker, or checkerboard mechanism lies outside the closed CorePotts CPU-qualified conjunction.",
            nothing,
        )
    end
    if key.mechanisms.qualification_family === :external_execution_protocol_v1
        return (
            Supported,
            Functional,
            "The external mechanism profile is functionally admitted for CPU execution, but it has no reviewed package/code and exact-environment replay evidence row.",
            _functional_capability_evidence(key),
        )
    end
    family = _qualified_capability_family(key)
    family === nothing && return (
        Supported,
        Functional,
        "The mechanism profile is functionally admitted for CPU execution, but this exact execution environment has no reviewed replay evidence row.",
        _functional_capability_evidence(key),
    )
    return (
        Supported,
        ReplayQualified,
        "Bounded CorePotts CPU execution and exact logical-continuation evidence cover this mechanism profile; performance qualification is not claimed.",
        _exact_capability_evidence(family.evidence, key),
    )
end

function adapted_device_capability_disposition(
        ::Val, key::ProgramCapabilityKey
    )
    return (
        Unsupported,
        InterfaceOnly,
        "Adaptation establishes storage transport only; no real-device evidence row qualifies this backend/device profile.",
        nothing,
    )
end

capability_key_fingerprint(key::ProgramCapabilityKey) =
    _capability_key_fingerprint(key)

function _capability_disposition(key::ProgramCapabilityKey)
    if key.backend === AdaptedBackend
        return adapted_device_capability_disposition(Val(key.device), key)
    end
    return _cpu_capability_disposition(key)
end

function program_capability_report(program::CompiledPottsProgram)
    key = _capability_key(program)
    status, maturity, reason, evidence = _capability_disposition(key)
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
        maturity,
        reason,
        evidence,
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
    key = ProgramCapabilityKey(
        source.engine,
        AdaptedBackend,
        Symbol(string(to)),
        source.topology,
        source.scalar_type,
        source.math_policy,
        source.lifecycle,
        source.component_state,
        source.mechanisms,
        source.replay,
        environment = source.environment,
    )
    status, maturity, reason, evidence = _capability_disposition(key)
    return ProgramCapabilityReport(
        key,
        status,
        maturity,
        reason,
        evidence,
        report.state_domains,
        report.stage_effects,
        report.relationships,
        report.trackers,
        report.checkerboard_plan,
    )
end

function capability_authorizes_execution(
        report::ProgramCapabilityReport; experimental::Bool = false
    )
    admitted_status = report.status === Supported ||
                      (experimental && report.status === Experimental)
    return admitted_status && Int(report.maturity) >= Int(Functional)
end

function capability_authorizes_replay(
        report::ProgramCapabilityReport;
        replay::CapabilityReplayClass = report.key.replay,
        experimental::Bool = false,
    )
    return capability_authorizes_execution(report; experimental) &&
           report.key.replay === replay &&
           Int(report.maturity) >= Int(ReplayQualified)
end

function _require_program_execution_capability(
        report::ProgramCapabilityReport;
        operation::Symbol = :execution,
        experimental::Bool = false,
    )
    capability_authorizes_execution(report; experimental) ||
        throw(ProgramCapabilityError(operation, report))
    return report
end

function _require_program_execution_capability(
        program::CompiledPottsProgram;
        operation::Symbol = :execution,
        experimental::Bool = false,
    )
    return _require_program_execution_capability(
        program_capability_report(program); operation, experimental
    )
end

function _require_program_replay_capability(
        report::ProgramCapabilityReport;
        operation::Symbol = :replay,
        replay::CapabilityReplayClass = ExactConfigurationReplay,
        experimental::Bool = false,
    )
    capability_authorizes_replay(report; replay, experimental) ||
        throw(ProgramCapabilityError(operation, report))
    return report
end

function _require_program_replay_capability(
        program::CompiledPottsProgram;
        operation::Symbol = :replay,
        replay::CapabilityReplayClass = ExactConfigurationReplay,
        experimental::Bool = false,
    )
    return _require_program_replay_capability(
        program_capability_report(program); operation, replay, experimental
    )
end
