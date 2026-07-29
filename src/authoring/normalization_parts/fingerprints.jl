function _canonical_open(io::IO, value)
    print(io, nameof(typeof(value)), '{')
    return io
end

_canonical_close(io::IO) = (print(io, '}'); io)

function _canonical_write(io::IO, value::Symbol)
    _canonical_open(io, value)
    print(io, sizeof(String(value)), ':', String(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::AbstractString)
    _canonical_open(io, value)
    print(io, ncodeunits(value), ':', value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Type)
    _canonical_open(io, value)
    print(io, parentmodule(value), '.', nameof(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::AbstractFloat)
    _canonical_open(io, value)
    print(io, bitstring(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Union{Integer, Bool, VersionNumber})
    _canonical_open(io, value)
    print(io, value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Enum)
    _canonical_open(io, value)
    print(io, Int(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, ::Nothing)
    print(io, "Nothing{nothing}")
    return io
end

function _canonical_write(io::IO, value::Tuple)
    _canonical_open(io, value)
    for item in value
        _canonical_write(io, item)
        print(io, ';')
    end
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::NamedTuple)
    _canonical_open(io, value)
    for key in propertynames(value)
        _canonical_write(io, key)
        _canonical_write(io, getproperty(value, key))
    end
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Pair)
    _canonical_open(io, value)
    _canonical_write(io, first(value))
    _canonical_write(io, last(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::AbstractArray)
    _canonical_open(io, value)
    _canonical_write(io, eltype(value))
    _canonical_write(io, size(value))
    for item in value
        _canonical_write(io, item)
        print(io, ';')
    end
    return _canonical_close(io)
end

_canonical_write(io::IO, value::Namespace) =
    (_canonical_open(io, value); _canonical_write(io, value.parts); _canonical_close(io))

function _canonical_write(io::IO, value::SemanticName)
    _canonical_open(io, value)
    _canonical_write(io, value.namespace)
    _canonical_write(io, value.name)
    return _canonical_close(io)
end

_canonical_write(io::IO, value::Union{CellType, Medium}) =
    (_canonical_open(io, value); _canonical_write(io, semantic_identity(value));
     _canonical_close(io))

function _canonical_write(io::IO, value::Binding)
    _canonical_open(io, value)
    _canonical_write(io, value.key)
    _canonical_write(io, value.value)
    return _canonical_close(io)
end

_canonical_write(io::IO, value::BindingTable) =
    (_canonical_open(io, value); _canonical_write(io, value.entries); _canonical_close(io))

function _canonical_write(io::IO, value::PairIdentity)
    _canonical_open(io, value)
    _canonical_write(io, value.left)
    _canonical_write(io, value.right)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::PairwiseLaw)
    _canonical_open(io, value)
    _canonical_write(io, value.name)
    _canonical_write(io, value.values)
    _canonical_write(io, value.symmetric)
    _canonical_write(io, value.default)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::VolumeParameters)
    _canonical_open(io, value)
    _canonical_write(io, value.target)
    _canonical_write(io, value.strength)
    return _canonical_close(io)
end


function _canonical_write(io::IO, value::BoundaryParameters)
    _canonical_open(io, value)
    _canonical_write(io, value.target)
    _canonical_write(io, value.strength)
    return _canonical_close(io)
end

_canonical_write(io::IO, value::ElongationParameters) = _canonical_fields(io, value)

function _canonical_fields(io::IO, value)
    _canonical_open(io, value)
    for field in fieldnames(typeof(value))
        _canonical_write(io, getfield(value, field))
    end
    return _canonical_close(io)
end

_canonical_write(io::IO, value::VolumeConstraint) = _canonical_fields(io, value)
_canonical_write(io::IO, value::FluctuatingVolumeConstraint) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Elongation) = _canonical_fields(io, value)
_canonical_write(io::IO, value::BoundaryConstraint) = _canonical_fields(io, value)
_canonical_write(io::IO, value::FluctuatingBoundaryConstraint) =
    _canonical_fields(io, value)
_canonical_write(io::IO, value::PreserveConnectivity) = _canonical_fields(io, value)
_canonical_write(io::IO, value::LocalConnectivity) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Adhesion) = _canonical_fields(io, value)
_canonical_write(io::IO, value::PrescribedField) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Chemotaxis) = _canonical_fields(io, value)
_canonical_write(io::IO, value::PropertyUpdate) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Transition) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Division) = _canonical_fields(io, value)
_canonical_write(io::IO, value::ShrinkDeath) = _canonical_fields(io, value)
_canonical_write(io::IO, value::ImmediateDeath) = _canonical_fields(io, value)
_canonical_write(io::IO, value::NamedCoreComponent) = _canonical_fields(io, value)
_canonical_write(io::IO, value::CellProperty) = _canonical_fields(io, value)
_canonical_write(io::IO, value::ClosedPropertyInterval) = _canonical_fields(io, value)
_canonical_write(io::IO, value::CorePotts.FixedMechanicalNoise) = _canonical_fields(io, value)
_canonical_write(io::IO, value::CorePotts.AxisFieldBoundary) = _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.ElasticLinkParameters) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.AnyFiniteCellPair) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.RNGNamespaceIdentity) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.ReactionDiffusion) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.FixedStep) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.ExplicitEuler) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.ConstantConcentration) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.Uptake) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.ByCellVolume) =
    _canonical_fields(io, value)
_canonical_write(
    io::IO, value::CorePotts.OneMCS) =
    _canonical_fields(io, value)
function _canonical_write(
        io::IO, value::CorePotts.StaticCartesianRelation)
    version = CorePotts.canonicalization_version(
        value)
    data = (
        role = Symbol(nameof(typeof(value.role))),
        offsets = Tuple(Tuple(offset)
            for offset in value.offsets),
        weights = Tuple(value.weights),
        opposite = Tuple(value.opposite),
        symmetric = value.symmetric,
        version = (
            version.major,
            version.minor,
            version.patch),
    )
    _canonical_open(io, value)
    _canonical_write(io, data)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::CorePotts.NumericalPolicy)
    _canonical_open(io, value)
    _canonical_write(io, Symbol(string(CorePotts.real_type(value))))
    _canonical_write(io, Symbol(string(CorePotts.accumulation_type(value))))
    _canonical_write(io, Symbol(string(typeof(value.math))))
    _canonical_write(io, Symbol(string(typeof(value.reductions))))
    _canonical_write(io, Symbol(string(typeof(value.overflow))))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value)
    identity = _core_semantic_identity(value)
    identity === nothing && throw(ArgumentError(
        "$(typeof(value)) does not provide canonical semantic fingerprint data"))
    core_identity = CorePotts.component_identity(value)
    semantic_data = CorePotts.component_semantic_data(value)
    semantic_data === value && fieldcount(typeof(value)) != 0 && throw(ArgumentError(
        "parameterized CorePotts component $(typeof(value)) must provide the public component_semantic_data protocol"))
    _canonical_open(io, value)
    _canonical_write(io, identity)
    _canonical_write(io, core_identity.version)
    _canonical_write(io, core_identity.category)
    semantic_data === value || _canonical_write(io, semantic_data)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Bool)
    _canonical_open(io, value)
    print(io, value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Real)
    _canonical_open(io, value)
    print(io, value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::CorePotts.MechanicalInitialization)
    _canonical_open(io, value)
    print(io, Int(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Union{CorePotts.AlgorithmTemperatureNoise,
        CorePotts.ConstitutiveResetAfterDivision, CorePotts.PreserveMechanicalOnDivision,
        CorePotts.StationaryRedrawAfterDivision, CorePotts.EveryMCS,
        CorePotts.AlwaysLifecycleTrigger})
    _canonical_open(io, value)
    print(io, '}')
    return io
end


function _canonical_write(io::IO, value::Union{CorePotts.OnceAtMCS, CorePotts.AtMCS,
        CorePotts.PeriodicMCS, CorePotts.BernoulliCellTrigger,
        CorePotts.PropertyAtLeast, CorePotts.CellTypeIn,
        CorePotts.AllLifecycleTriggers})
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, value::Union{AbstractPropertyInvariant,
        CorePotts.AbstractDivisionPolicy, CorePotts.AbstractTransitionPolicy,
        CorePotts.AbstractRetirementPolicy, CorePotts.AbstractFieldBoundary,
        CorePotts.AbstractFieldInterpolation, CorePotts.AbstractFieldResponse,
        CorePotts.AbstractChemotaxisMode, CorePotts.AbstractBoundaryMetric,
        CorePotts.AbstractDivisionGeometry})
    fieldcount(typeof(value)) == 0 && return (
        _canonical_open(io, value); _canonical_close(io))
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, value::Union{
        CorePotts.AbstractSiteInitializer,
        CorePotts.AbstractSiteOwnershipPolicy,
        CorePotts.NoSiteInvariant,
        CorePotts.AbstractAcceptedCopyAssignment,
        CorePotts.AbstractSiteUpdateLaw,
        CorePotts.AbstractHistoryFill,
        CorePotts.AbstractHistoryDivisionPolicy,
        CorePotts.AbstractHistoryTransitionPolicy,
        CorePotts.AbstractEndpointLifecyclePolicy,
        CorePotts.RelationshipCapacity,
        CorePotts.AlwaysAcceptedCopy,
        CorePotts.CoupledPhase,
        CorePotts.PottsAttempts,
        CorePotts.LifecyclePhase,
        CorePotts.ObservationPhase,
        CorePotts.Advance,
        CorePotts.Exchange,
        CorePotts.Sample,
        CorePotts.Update,
        CorePotts.MCSRange,
        CorePotts.During,
        CorePotts.ProtocolStage,
        CorePotts.ContinuousInterval,
        CorePotts.OneMCS,
        CorePotts.HalfMCS,
        CorePotts.EveryGlobal,
        CorePotts.AbstractDelayInterpolation,
        CorePotts.RepeatInitialDelay,
        CorePotts.AbstractTriggerMemory,
        CorePotts.SampledTrigger,
        CorePotts.RootTrigger,
        CorePotts.EventAssignment,
        CorePotts.FromTriggerSnapshot,
        CorePotts.FromExecutionSnapshot,
        CorePotts.NoImmediateCascade,
        CorePotts.CascadeUntilStable,
        CorePotts.LifecycleRequest,
        CorePotts.SymbolIdentity,
        CorePotts.SymbolRef,
        CorePotts.InputRef,
        CorePotts.IdentityMap,
        CorePotts.AbstractCompatibilityLevel,
        CorePotts.CompatibilityItem,
        CorePotts.MorpheusSemanticProfile,
        CorePotts.SBMLSemanticProfile,
        CorePotts.GlobalClock,
        CorePotts.MCSDuration,
        CorePotts.AbstractMCSPosition,
        CorePotts.AbstractScheduledEntry,
        CorePotts.TimedLifecyclePhase,
        CorePotts.MultirateSchedule,
        CorePotts.AbstractObservationPhase,
        CorePotts.AbstractObservationFailurePolicy,
        CorePotts.AbstractObservationSchema})
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, law::CorePotts.DirectLaw)
    _canonical_open(io, law)
    _canonical_write(io, law.name)
    _canonical_write(io, law.version)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Union{
        CorePotts.AbstractContinuousDomain,
        CorePotts.AngularMembrane,
        CorePotts.FillMembrane,
        CorePotts.ConservativeMembraneRemap,
        CorePotts.PartitionMembraneByGeometry,
        CorePotts.PreserveMembrane,
        CorePotts.ResetMembrane,
        CorePotts.StateVariable,
        CorePotts.InputVariable,
        CorePotts.Constant,
        CorePotts.IntermediateVariable,
        CorePotts.ObservableVariable,
        CorePotts.TimeVariable,
        CorePotts.AbstractContinuousStatement,
        CorePotts.AbstractReactionInterpretation,
        CorePotts.AbstractFixedStepper,
        CorePotts.SystemStep,
        CorePotts.FixedStep,
        CorePotts.AdaptiveStep,
        CorePotts.SystemClock,
        CorePotts.ReactionDiffusion,
        CorePotts.ByCellVolume,
        CorePotts.ConstantConcentration,
        CorePotts.Uptake,
        CorePotts.SteadyStateAdvance})
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, value::Union{
        CorePotts.StableRelationshipPriority,
        CorePotts.AbstractRelationshipRequest,
        CorePotts.RelationshipPolicyBundle})
    return _canonical_fields(io, value)
end

function _semantic_fingerprint(numerics, cells, media, components)
    io = IOBuffer()
    print(io, "PottsToolkitNormalizedIR|", CorePotts.NORMALIZED_IR_CONTRACT_VERSION, '|')
    _canonical_write(io, numerics)
    _canonical_write(io, cells)
    _canonical_write(io, media)
    _canonical_write(io, components)
    digest = bytes2hex(SHA.sha256(take!(io)))
    return SemanticFingerprint(CorePotts.SEMANTIC_FINGERPRINT_VERSION, digest)
end

function _execution_write(io::IO, value::Tuple)
    print(io, "Tuple[")
    for item in value
        _execution_write(io, item)
        print(io, ';')
    end
    print(io, ']')
    return io
end

function _execution_write(io::IO, value::NamedTuple)
    print(io, "NamedTuple[")
    for key in propertynames(value)
        _execution_write(io, key)
        _execution_write(io, getproperty(value, key))
    end
    print(io, ']')
    return io
end

function _execution_write(io::IO, value::Union{Symbol, AbstractString, Number,
        VersionNumber, Enum, Nothing})
    print(io, nameof(typeof(value)), ':', repr(value), ';')
    return io
end

function _execution_write(io::IO, value::Type)
    print(io, parentmodule(value), '.', nameof(value), ';')
    return io
end

function _execution_write(io::IO, value)
    type = typeof(value)
    print(io, parentmodule(type), '.', nameof(type), '{')
    for field in fieldnames(type)
        print(io, field, '=')
        _execution_write(io, getfield(value, field))
    end
    print(io, '}')
    return io
end

"""Execution identity for cache keys, reports, and exact-replay qualification."""
function execution_fingerprint(model::NormalizedModel, algorithm, backend;
        dimensions::Integer,
        execution = CorePotts.DefaultPottsExecution())
    dimensions in (2, 3) || throw(ArgumentError(
        "execution fingerprints require a 2D or 3D model realization"))
    io = IOBuffer()
    print(io, "PottsToolkitExecution|", CorePotts.EXECUTION_FINGERPRINT_VERSION, '|')
    _execution_write(io, model.fingerprint.version)
    _execution_write(io, model.fingerprint.digest)
    _execution_write(io, model.numerics)
    _execution_write(io, CorePotts.component_identity(algorithm))
    _execution_write(io, CorePotts.algorithm_guarantees(algorithm))
    _execution_write(io, typeof(backend))
    _execution_write(io, CorePotts.backend_capabilities(backend))
    _execution_write(io, dimensions)
    _execution_write(io, execution)
    _execution_write(io, CorePotts.rng_contract_version(CorePotts.Philox4x32x10V1()))
    _execution_write(io, VERSION)
    _execution_write(io, Base.pkgversion(CorePotts))
    _execution_write(io, Base.pkgversion(parentmodule(@__MODULE__)))
    return ExecutionFingerprint(CorePotts.EXECUTION_FINGERPRINT_VERSION,
        bytes2hex(SHA.sha256(take!(io))))
end

execution_fingerprint(model::PottsModel, algorithm, backend; kwargs...) =
    execution_fingerprint(normalize(model), algorithm, backend; kwargs...)
