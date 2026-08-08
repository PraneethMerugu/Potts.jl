"""Problem family selected explicitly for a native MTK component."""
abstract type AbstractNativeComponentFamily end

"""A native component lowered through the standard MTK ODE problem path."""
struct ODEComponent <: AbstractNativeComponentFamily end

"""A native component lowered through the standard MTK DAE problem path."""
struct DAEComponent <: AbstractNativeComponentFamily end

"""Storage and lifecycle scope of a native component."""
abstract type AbstractNativeComponentScope end

"""One native system state shared by the complete Potts trajectory."""
struct Global <: AbstractNativeComponentScope end

"""One native system state for each live finite Potts cell identity."""
struct PerCell <: AbstractNativeComponentScope end

"""Clock policy relating completed Potts MCS values to physical component time."""
abstract type AbstractNativeTimePolicy end

"""
    FixedPhysicalTime(origin, duration_per_mcs)

Map completed Potts MCS `m` to `origin + m * duration_per_mcs`. The duration
must be positive and both values must be finite. Values retain their concrete
quantity types; no unit-stripping or conversion occurs at declaration time.
"""
struct FixedPhysicalTime{O, D} <: AbstractNativeTimePolicy
    origin::O
    duration_per_mcs::D

    function FixedPhysicalTime(origin::O, duration_per_mcs::D) where {O, D}
        _require_finite_native_time(origin, "origin")
        _require_finite_native_time(duration_per_mcs, "duration_per_mcs")
        positive = try
            duration_per_mcs > zero(duration_per_mcs)
        catch
            false
        end
        positive === true || throw(ArgumentError(
            "FixedPhysicalTime duration_per_mcs must be positive"
        ))
        try
            origin + duration_per_mcs
        catch
            throw(ArgumentError(
                "FixedPhysicalTime origin and duration_per_mcs must have " *
                "compatible physical dimensions"
            ))
        end
        return new{O, D}(origin, duration_per_mcs)
    end
end

function _require_finite_native_time(value, label::AbstractString)
    finite = try
        isfinite(value)
    catch
        false
    end
    finite === true || throw(ArgumentError(
        "FixedPhysicalTime $label must be a finite concrete value"
    ))
    return nothing
end

"""Return the physical time at a settled, completed-MCS boundary."""
function native_time_at(clock::FixedPhysicalTime, completed_mcs::Integer)
    completed_mcs >= 0 || throw(ArgumentError(
        "completed MCS must be nonnegative"
    ))
    return clock.origin + completed_mcs * clock.duration_per_mcs
end

"""Coupled publication-order policy for a native component."""
abstract type AbstractNativeSplitPolicy end

"""
The default Lie split: stage one CPM MCS, advance every due native component
from the same staged Core snapshot, then atomically publish both domains. Due
native components therefore have simultaneous (Jacobi) island semantics: one
island cannot observe another island's output from the current coupled step.
"""
struct CPMThenComponents <: AbstractNativeSplitPolicy end

"""Initialization is delegated to the native system and standard MTK problem."""
abstract type AbstractNativeInitializationPolicy end
struct PreserveNativeInitialization <: AbstractNativeInitializationPolicy end

"""Native continuous and discrete events remain owned by the MTK system."""
abstract type AbstractNativeEventPolicy end
struct PreserveNativeEvents <: AbstractNativeEventPolicy end

"""Lifecycle behavior of native component state."""
abstract type AbstractNativeLifecyclePolicy end

"""A global component has no per-cell create, divide, or retire semantics."""
struct GlobalNativeLifecycle <: AbstractNativeLifecyclePolicy end

"""
    PerCellNativeLifecycle(; creation, transition, division)

Explicit lifecycle policy for a `PerCell()` native component. Removal and
retirement always delete the corresponding native state. Every other Core
lifecycle event must name an admitted, deterministic state action.
"""
struct PerCellNativeLifecycle{C, T, D} <: AbstractNativeLifecyclePolicy
    creation::C
    transition::T
    division::D

    function PerCellNativeLifecycle(creation::C, transition::T, division::D) where {C, T, D}
        creation isa Union{PreserveNativeInitialization, Unsupported} ||
            throw(ArgumentError(
                "PerCell native creation must use " *
                "PreserveNativeInitialization() or Unsupported()"
            ))
        transition isa Union{Preserve, ResetTo, Transform, Unsupported} ||
            throw(ArgumentError(
                "PerCell native transition must use Preserve(), ResetTo(...), " *
                "Transform(...), or Unsupported()"
            ))
        division isa Union{
            CopyToDaughters, PreserveParentResetDaughter, ResetBoth,
            SplitConservatively, TransformDaughters, Unsupported,
        } || throw(ArgumentError(
            "PerCell native division must use CopyToDaughters(), " *
            "PreserveParentResetDaughter(...), ResetBoth(...), " *
            "SplitConservatively(...), TransformDaughters(...), or Unsupported()"
        ))
        return new{C, T, D}(creation, transition, division)
    end
end

PerCellNativeLifecycle(; creation, transition, division) =
    PerCellNativeLifecycle(creation, transition, division)

"""Numerical algorithms are selected at `init`, never by the declaration."""
abstract type AbstractNativeAlgorithmPolicy end
struct LateBoundNativeAlgorithm <: AbstractNativeAlgorithmPolicy end

"""Capability admission is checked against the complete late runtime profile."""
abstract type AbstractNativeCapabilityPolicy end
struct RequireQualifiedNativeCapability <: AbstractNativeCapabilityPolicy end
"""Internal provenance marker for components produced by MethodOfLines."""
struct _MethodOfLinesNativeCapability <: AbstractNativeCapabilityPolicy end

function _qualified_native_path(path, owner::AbstractString)
    normalized = if path isa Tuple
        path
    elseif path isa AbstractVector
        Tuple(path)
    else
        throw(ArgumentError(
            "$owner requires a fully qualified Tuple of component names"
        ))
    end
    length(normalized) >= 2 || throw(ArgumentError(
        "$owner requires a fully qualified path `(root, ..., component)`"
    ))
    all(name -> name isa Symbol && !isempty(String(name)), normalized) ||
        throw(ArgumentError(
            "$owner path entries must be nonempty Symbols"
        ))
    return Tuple(Symbol(name) for name in normalized)
end

function _native_pair_tuple(values, owner::AbstractString)
    values === nothing && return ()
    tuple = if values isa Pair
        (values,)
    elseif values isa AbstractDict
        Tuple(pairs(values))
    elseif values isa NamedTuple
        Tuple(name => getproperty(values, name) for name in keys(values))
    else
        try
            Tuple(values)
        catch
            throw(ArgumentError("$owner must be an iterable of pairs"))
        end
    end
    all(value -> value isa Pair, tuple) || throw(ArgumentError(
        "$owner entries must be pairs"
    ))
    result = Pair{Any, Any}[]
    for pair in tuple
        any(prior -> isequal(first(prior), first(pair)), result) &&
            throw(ArgumentError("$owner contains a duplicate symbolic key"))
        push!(result, _defensive_copy(first(pair)) => _defensive_copy(last(pair)))
    end
    sort!(result; by = pair -> (
        _canonical_value(first(pair)),
        string(typeof(first(pair))),
        repr(first(pair)),
    ))
    return Tuple(result)
end

"""
    NativeOperatingPoint(path; values=(), guesses=())

Initial values and initialization guesses for one fully qualified native MTK
component. `values` is passed to the component's standard MTK problem
constructor. Potts-coupled inputs override matching entries at the initial
boundary. No equations, defaults, or initialization rules are copied.
"""
struct NativeOperatingPoint{P <: Tuple, V <: Tuple, G <: Tuple}
    path::P
    values::V
    guesses::G
end

function NativeOperatingPoint(path; values = (), guesses = ())
    normalized_path = _qualified_native_path(path, "NativeOperatingPoint")
    normalized_values = _native_pair_tuple(
        values, "NativeOperatingPoint values"
    )
    normalized_guesses = _native_pair_tuple(
        guesses, "NativeOperatingPoint guesses"
    )
    return NativeOperatingPoint(
        normalized_path, normalized_values, normalized_guesses
    )
end

function _native_profile_value(value, owner::AbstractString)
    value isa Union{
        Nothing, Missing, Bool, Integer, AbstractFloat, Symbol,
        AbstractString, VersionNumber, Enum,
    } && return value
    if value isa Tuple
        return map(item -> _native_profile_value(item, owner), value)
    elseif value isa NamedTuple
        mapped = map(item -> _native_profile_value(item, owner), values(value))
        return NamedTuple{keys(value)}(mapped)
    elseif value isa Pair
        return _native_profile_value(first(value), owner) =>
               _native_profile_value(last(value), owner)
    elseif value isa AbstractArray
        isbitstype(eltype(value)) || throw(ArgumentError(
            "$owner arrays must have an isbits element type"
        ))
        return copy(value)
    end
    throw(ArgumentError(
        "$owner must contain only deterministic logical values; got $(typeof(value))"
    ))
end

"""
    NativeSolveProfile(path, algorithm; profile_id=nothing,
                       execution=SerialNativeExecution(),
                       deterministic=false, exact_replay=false, options...)

Late numerical policy for exactly one native component. There is deliberately
no default native solver. Execution and checkpoint/restore admit only a closed
capability row: exact replay requires `exact_replay=true`, an explicitly pinned
`profile_id`, and the author's `deterministic=true` assertion. `execution`
selects serial versus per-cell batched numerical lanes; it never changes CPM
ordering or trajectory-ensemble identity. A profile with `exact_replay=false`
can represent an unsupported candidate for inspection and preflight
diagnostics, but it cannot initialize a native solver.
"""
abstract type AbstractNativeExecutionMode end

"""One native solve at a time in deterministic component/slot order."""
struct SerialNativeExecution <: AbstractNativeExecutionMode end

"""
    BatchedNativeExecution(width)

Advance fixed-shape per-cell ODE lanes in deterministic batches of at most
`width`. Lanes may execute concurrently on CPU, but publication remains one
ordered, atomic component transaction. This is distinct from a SciML
`EnsembleProblem`, whose lanes are complete Potts trajectories.
"""
struct BatchedNativeExecution <: AbstractNativeExecutionMode
    width::Int

    function BatchedNativeExecution(width::Integer)
        1 < width <= typemax(Int32) || throw(ArgumentError(
            "BatchedNativeExecution width must be in 2:typemax(Int32)"
        ))
        return new(Int(width))
    end
end

"""
    MetalNativeExecution(width=1)

Execute one fixed-shape ODE lane (`width == 1`, including a `Global`
component) or a bounded group of `PerCell` lanes in one DiffEqGPU kernel on
Apple Metal. Device transfers occur only at the documented coupled-state
boundary; this mode never silently falls back to CPU execution.
"""
struct MetalNativeExecution <: AbstractNativeExecutionMode
    width::Int

    function MetalNativeExecution(width::Integer = 1)
        1 <= width <= typemax(Int32) || throw(ArgumentError(
            "MetalNativeExecution width must be in 1:typemax(Int32)"
        ))
        return new(Int(width))
    end
end

struct NativeSolveProfile{
        P <: Tuple, A, O <: NamedTuple, E <: AbstractNativeExecutionMode,
    }
    path::P
    algorithm::A
    options::O
    execution::E
    profile_id::Union{Nothing, String}
    deterministic::Bool
    exact_replay::Bool
end

function NativeSolveProfile(
        path,
        algorithm;
        profile_id = nothing,
        execution::AbstractNativeExecutionMode = SerialNativeExecution(),
        deterministic::Bool = false,
        exact_replay::Bool = false,
        options...,
    )
    normalized_path = _qualified_native_path(path, "NativeSolveProfile")
    algorithm === nothing && throw(ArgumentError(
        "NativeSolveProfile requires an explicit SciML algorithm"
    ))
    algorithm isa Union{Function, Module, Task, IO} && throw(ArgumentError(
        "NativeSolveProfile algorithm cannot contain executable host context"
    ))
    ismutabletype(typeof(algorithm)) && throw(ArgumentError(
        "NativeSolveProfile algorithm must be an immutable pinned value"
    ))
    forbidden = intersect(
        Set(keys(options)),
        Set((:callback, :prob_func, :output_func, :reduction)),
    )
    isempty(forbidden) || throw(ArgumentError(
        "NativeSolveProfile does not admit external callback/context option$(length(forbidden) == 1 ? "" : "s"): " *
        join(string.(sort!(collect(forbidden); by = String)), ", ")
    ))
    option_names = Tuple(sort!(collect(keys(options)); by = String))
    normalized_options = NamedTuple{option_names}(map(
        value -> _native_profile_value(
            value, "NativeSolveProfile option"
        ),
        Tuple(options[name] for name in option_names),
    ))
    normalized_id = profile_id === nothing ? nothing : String(profile_id)
    normalized_id === nothing || !isempty(normalized_id) || throw(ArgumentError(
        "NativeSolveProfile profile_id cannot be empty"
    ))
    exact_replay && (!deterministic || normalized_id === nothing) &&
        throw(ArgumentError(
            "exact native replay requires deterministic=true and a pinned profile_id"
        ))
    return NativeSolveProfile(
        normalized_path,
        algorithm,
        normalized_options,
        execution,
        normalized_id,
        deterministic,
        exact_replay,
    )
end

"""A typed value entering an MTK system from a Potts statement endpoint."""
struct NativeInput{V, P <: AbstractPottsStatement, T}
    native_variable::V
    from::P
    value_type::Type{T}

    function NativeInput(
            native_variable::V, from::P, ::Type{T}) where {
            V, P <: AbstractPottsStatement, T,
        }
        _require_native_symbolic_reference(native_variable, "input")
        from isa Union{ModelState, CellState} || throw(ArgumentError(
            "NativeInput endpoints must be symbolic ModelState or CellState declarations"
        ))
        isconcretetype(T) || throw(ArgumentError(
            "NativeInput value type must be concrete; got $T"
        ))
        return new{V, P, T}(native_variable, from, T)
    end
end

"""A typed value leaving an MTK system for a Potts statement endpoint."""
struct NativeOutput{V, P <: AbstractPottsStatement, T}
    native_variable::V
    to::P
    value_type::Type{T}

    function NativeOutput(
            native_variable::V, to::P, ::Type{T}) where {
            V, P <: AbstractPottsStatement, T,
        }
        _require_native_symbolic_reference(native_variable, "output")
        to isa Union{ModelState, CellState} || throw(ArgumentError(
            "NativeOutput endpoints must be symbolic ModelState or CellState declarations"
        ))
        isconcretetype(T) || throw(ArgumentError(
            "NativeOutput value type must be concrete; got $T"
        ))
        return new{V, P, T}(native_variable, to, T)
    end
end

NativeInput(native_variable, from::AbstractPottsStatement; value_type::Type) =
    NativeInput(native_variable, from, value_type)
NativeOutput(native_variable, to::AbstractPottsStatement; value_type::Type) =
    NativeOutput(native_variable, to, value_type)

"""A fixed scalarized native grid published atomically to one `FieldState`."""
struct NativeFieldOutput{V <: Tuple, P <: FieldState, S <: Tuple, C <: Tuple, T}
    native_variables::V
    to::P
    shape::S
    coordinates::C
    value_type::Type{T}
end

"""Extension constructor for a checked MethodOfLines field component."""
function MethodOfLinesComponent end
function _native_field_profile_evidence end

function NativeFieldOutput(
        variables::AbstractArray,
        to::FieldState;
        coordinates,
        value_type::Type,
    )
    isconcretetype(value_type) || throw(ArgumentError(
        "NativeFieldOutput value type must be concrete; got $value_type"
    ))
    isempty(variables) && throw(ArgumentError(
        "NativeFieldOutput variables must be nonempty"
    ))
    normalized_variables = map(Symbolics.Num, variables)
    coordinate_tuple = Tuple(Tuple(axis) for axis in coordinates)
    length(coordinate_tuple) == ndims(variables) || throw(ArgumentError(
        "NativeFieldOutput requires one coordinate axis per grid dimension"
    ))
    all(index -> length(coordinate_tuple[index]) == size(variables, index),
        eachindex(coordinate_tuple)) || throw(ArgumentError(
        "NativeFieldOutput coordinate lengths must equal the variable-grid shape"
    ))
    for axis in coordinate_tuple
        all(value -> value isa Real && isfinite(value), axis) ||
            throw(ArgumentError(
                "NativeFieldOutput coordinates must be finite real values"
            ))
        all(index -> axis[index] < axis[index + 1], 1:(length(axis) - 1)) ||
            throw(ArgumentError(
                "NativeFieldOutput coordinate axes must be strictly increasing"
            ))
    end
    return NativeFieldOutput(
        Tuple(vec(normalized_variables)), to, size(variables), coordinate_tuple,
        value_type,
    )
end

function _require_native_symbolic_reference(value, direction::AbstractString)
    value isa Union{Symbolics.Num, Symbolics.Arr} || throw(ArgumentError(
        "Native$direction endpoints require the original MTK Num or Arr, " *
        "not $(typeof(value))"
    ))
    return nothing
end

const _NativePort = Union{NativeInput, NativeOutput, NativeFieldOutput}

"""
    CouplingEndpointSchema

A resolved coupling endpoint. `component_path` identifies the declaration in
the scheduled Potts hierarchy while `port` retains both the original MTK
symbolic value and the typed Potts statement reference.
"""
struct CouplingEndpointSchema{P <: _NativePort}
    component_path::Tuple{Vararg{Symbol}}
    port::P
    potts_identity::QualifiedStatementID
    potts_kind::Symbol

    function CouplingEndpointSchema(
            component_path::Tuple{Vararg{Symbol}},
            port::P,
            potts_identity::QualifiedStatementID,
            potts_kind::Symbol,
        ) where {P <: _NativePort}
        isempty(component_path) && throw(ArgumentError(
            "a coupling endpoint requires a nonempty component path"
        ))
        any(name -> isempty(String(name)), component_path) && throw(ArgumentError(
            "a coupling endpoint component path cannot contain an empty name"
        ))
        return new{P}(component_path, port, potts_identity, potts_kind)
    end
end

native_variable(port::Union{NativeInput, NativeOutput}) =
    getfield(port, :native_variable)
native_variable(port::NativeFieldOutput) = getfield(port, :native_variables)
native_variables(port::Union{NativeInput, NativeOutput}) = (native_variable(port),)
native_variables(port::NativeFieldOutput) = native_variable(port)
potts_endpoint(port::NativeInput) = getfield(port, :from)
potts_endpoint(port::NativeOutput) = getfield(port, :to)
potts_endpoint(port::NativeFieldOutput) = getfield(port, :to)
native_value_type(port::_NativePort) = getfield(port, :value_type)
native_variable(endpoint::CouplingEndpointSchema) = native_variable(endpoint.port)
potts_endpoint(endpoint::CouplingEndpointSchema) = endpoint.potts_identity
native_value_type(endpoint::CouplingEndpointSchema) = native_value_type(endpoint.port)

"""
    NativeComponent(source; name, family, time, ...)

Declare a native ModelingToolkit component without translating it into Potts
equations. `Global()` stores one state for the trajectory; `PerCell()` stores
one state for every live finite Potts cell. `source` is retained by identity.
Its hierarchy, defaults, initialization equations, observations, and events
remain under MTK ownership.
"""
struct _NativeConstructionToken end
const _NATIVE_CONSTRUCTION_TOKEN = _NativeConstructionToken()

struct NativeComponent{
        S <: ModelingToolkitBase.AbstractSystem,
        F <: AbstractNativeComponentFamily,
        SC <: AbstractNativeComponentScope,
        TP <: AbstractNativeTimePolicy,
        C <: AbstractCadence,
        SP <: AbstractNativeSplitPolicy,
        I <: Tuple,
        O <: Tuple,
        IP <: AbstractNativeInitializationPolicy,
        EP <: AbstractNativeEventPolicy,
        LP <: AbstractNativeLifecyclePolicy,
        AP <: AbstractNativeAlgorithmPolicy,
        CP <: AbstractNativeCapabilityPolicy,
    }
    name::Symbol
    source::S
    family::F
    scope::SC
    time::TP
    cadence::C
    split::SP
    inputs::I
    outputs::O
    initialization::IP
    events::EP
    lifecycle::LP
    algorithm::AP
    capabilities::CP

    function NativeComponent(
            ::_NativeConstructionToken,
            name::Symbol,
            source::S,
            family::F,
            scope::SC,
            time::TP,
            cadence::C,
            split::SP,
            inputs::I,
            outputs::O,
            initialization::IP,
            events::EP,
            lifecycle::LP,
            algorithm::AP,
            capabilities::CP,
        ) where {
            S <: ModelingToolkitBase.AbstractSystem,
            F <: AbstractNativeComponentFamily,
            SC <: AbstractNativeComponentScope,
            TP <: AbstractNativeTimePolicy,
            C <: AbstractCadence,
            SP <: AbstractNativeSplitPolicy,
            I <: Tuple,
            O <: Tuple,
            IP <: AbstractNativeInitializationPolicy,
            EP <: AbstractNativeEventPolicy,
            LP <: AbstractNativeLifecyclePolicy,
            AP <: AbstractNativeAlgorithmPolicy,
            CP <: AbstractNativeCapabilityPolicy,
        }
        return new{S, F, SC, TP, C, SP, I, O, IP, EP, LP, AP, CP}(
            name,
            source,
            family,
            scope,
            time,
            cadence,
            split,
            inputs,
            outputs,
            initialization,
            events,
            lifecycle,
            algorithm,
            capabilities,
        )
    end
end

function NativeComponent(
        source::ModelingToolkitBase.AbstractSystem;
        name,
        family::AbstractNativeComponentFamily,
        time::AbstractNativeTimePolicy,
        scope::AbstractNativeComponentScope = Global(),
        cadence::AbstractCadence = EveryMCS(),
        split::AbstractNativeSplitPolicy = CPMThenComponents(),
        inputs = (),
        outputs = (),
        initialization::AbstractNativeInitializationPolicy =
            PreserveNativeInitialization(),
        events::AbstractNativeEventPolicy = PreserveNativeEvents(),
        lifecycle::AbstractNativeLifecyclePolicy = GlobalNativeLifecycle(),
        algorithm::AbstractNativeAlgorithmPolicy = LateBoundNativeAlgorithm(),
        capabilities::AbstractNativeCapabilityPolicy =
            RequireQualifiedNativeCapability(),
    )
    name isa Symbol || throw(ArgumentError(
        "NativeComponent requires a Symbol `name`"
    ))
    isempty(String(name)) && throw(ArgumentError(
        "NativeComponent name cannot be empty"
    ))
    scope isa Union{Global, PerCell} || throw(ArgumentError(
        "native component scope must be Global() or PerCell()"
    ))
    time isa FixedPhysicalTime || throw(ArgumentError(
        "G5H-3 native components require FixedPhysicalTime"
    ))
    split isa CPMThenComponents || throw(ArgumentError(
        "G5H-3 admits only the CPMThenComponents split"
    ))
    cadence isa Union{EveryMCS, Every} || throw(ArgumentError(
        "native component cadence must be EveryMCS() or Every(n)"
    ))
    initialization isa PreserveNativeInitialization || throw(ArgumentError(
        "G5H-3 preserves native MTK initialization semantics"
    ))
    events isa PreserveNativeEvents || throw(ArgumentError(
        "G5H-3 preserves native MTK event semantics"
    ))
    if scope isa Global
        lifecycle isa GlobalNativeLifecycle || throw(ArgumentError(
            "Global native components require GlobalNativeLifecycle()"
        ))
    else
        lifecycle isa PerCellNativeLifecycle || throw(ArgumentError(
            "PerCell native components require an explicit PerCellNativeLifecycle"
        ))
    end
    algorithm isa LateBoundNativeAlgorithm || throw(ArgumentError(
        "native numerical algorithms must remain late-bound"
    ))
    capabilities isa Union{
        RequireQualifiedNativeCapability, _MethodOfLinesNativeCapability,
    } || throw(ArgumentError(
        "native execution requires a package-owned late capability policy"
    ))
    input_ports = _native_port_tuple(inputs, NativeInput, "inputs")
    output_ports = _native_port_tuple(
        outputs, Union{NativeOutput, NativeFieldOutput}, "outputs"
    )
    _validate_native_ports(input_ports, output_ports)
    _validate_native_scope_ports(scope, input_ports, output_ports)
    return NativeComponent(
        _NATIVE_CONSTRUCTION_TOKEN,
        name,
        source,
        family,
        scope,
        time,
        cadence,
        split,
        input_ports,
        output_ports,
        initialization,
        events,
        lifecycle,
        algorithm,
        capabilities,
    )
end

function _validate_native_scope_ports(scope::Global, inputs::Tuple, outputs::Tuple)
    all(port -> potts_endpoint(port) isa ModelState, inputs) ||
        throw(ArgumentError("Global native inputs must target ModelState declarations"))
    all(port -> port isa NativeFieldOutput ||
        potts_endpoint(port) isa ModelState, outputs) || throw(ArgumentError(
        "Global native outputs must target ModelState or use NativeFieldOutput"
    ))
    return nothing
end

function _validate_native_scope_ports(scope::PerCell, inputs::Tuple, outputs::Tuple)
    all(port -> potts_endpoint(port) isa Union{ModelState, CellState}, inputs) ||
        throw(ArgumentError(
            "PerCell native inputs must target ModelState or CellState declarations"
        ))
    all(port -> potts_endpoint(port) isa CellState, outputs) ||
        throw(ArgumentError(
            "PerCell native outputs must target CellState declarations"
        ))
    return nothing
end

function _native_port_tuple(values, ::Type{P}, label::AbstractString) where {P}
    tuple = values isa P ? (values,) : try
        Tuple(values)
    catch
        throw(ArgumentError("NativeComponent $label must be an iterable of $P"))
    end
    all(value -> value isa P, tuple) || throw(ArgumentError(
        "NativeComponent $label must contain only $P values"
    ))
    return tuple
end

function _validate_native_ports(inputs::Tuple, outputs::Tuple)
    _assert_unique_native_values(inputs, "input")
    _assert_unique_native_values(outputs, "output")
    for input in inputs, output in outputs
        isempty(intersect(
            collect(native_variables(input)), collect(native_variables(output))
        )) || throw(ArgumentError(
            "an MTK symbolic value cannot be both a NativeInput and NativeOutput"
        ))
    end
    for (index, output) in pairs(outputs), prior in Iterators.take(outputs, index - 1)
        isequal(potts_endpoint(output), potts_endpoint(prior)) || continue
        throw(ArgumentError(
            "a Potts endpoint may have only one NativeOutput writer"
        ))
    end
    return nothing
end

function _assert_unique_native_values(ports::Tuple, label::AbstractString)
    for (index, port) in pairs(ports), prior in Iterators.take(ports, index - 1)
        isempty(intersect(
            collect(native_variables(port)), collect(native_variables(prior))
        )) || throw(ArgumentError("duplicate native $label symbolic value"))
    end
    return nothing
end

native_source(component::NativeComponent) = getfield(component, :source)
native_family(component::NativeComponent) = getfield(component, :family)
native_inputs(component::NativeComponent) = getfield(component, :inputs)
native_outputs(component::NativeComponent) = getfield(component, :outputs)
Base.nameof(component::NativeComponent) = getfield(component, :name)

function _rebuild_native_component(
        component::NativeComponent;
        name = nameof(component),
        inputs = native_inputs(component),
        outputs = native_outputs(component),
    )
    return NativeComponent(
        native_source(component);
        name,
        family = getfield(component, :family),
        scope = getfield(component, :scope),
        time = getfield(component, :time),
        cadence = getfield(component, :cadence),
        split = getfield(component, :split),
        inputs,
        outputs,
        initialization = getfield(component, :initialization),
        events = getfield(component, :events),
        lifecycle = getfield(component, :lifecycle),
        algorithm = getfield(component, :algorithm),
        capabilities = getfield(component, :capabilities),
    )
end

function _map_native_potts_endpoints(f, component::NativeComponent; name = nameof(component))
    inputs = Tuple(
        NativeInput(native_variable(port), f(potts_endpoint(port)), native_value_type(port))
        for port in native_inputs(component)
    )
    outputs = Tuple(
        port isa NativeFieldOutput ? NativeFieldOutput(
            reshape(collect(native_variables(port)), getfield(port, :shape)),
            f(potts_endpoint(port));
            coordinates = getfield(port, :coordinates),
            value_type = native_value_type(port),
        ) : NativeOutput(
            native_variable(port), f(potts_endpoint(port)), native_value_type(port)
        )
        for port in native_outputs(component)
    )
    return _rebuild_native_component(component; name, inputs, outputs)
end

native_time_at(component::NativeComponent, completed_mcs::Integer) =
    native_time_at(getfield(component, :time), completed_mcs)

function native_cadence_stride(component::NativeComponent)
    cadence = getfield(component, :cadence)
    cadence isa EveryMCS && return 1
    return Int(getfield(cadence, :cadence))
end

function native_due(component::NativeComponent, completed_mcs::Integer)
    completed_mcs >= 0 || throw(ArgumentError(
        "completed MCS must be nonnegative"
    ))
    completed_mcs == 0 && return false
    return mod(completed_mcs, native_cadence_stride(component)) == 0
end

"""Return the physical interval ending at a due completed-MCS boundary."""
function native_time_interval(component::NativeComponent, completed_mcs::Integer)
    native_due(component, completed_mcs) || throw(ArgumentError(
        "native component $(repr(component.name)) is not due at MCS $completed_mcs"
    ))
    stride = native_cadence_stride(component)
    clock = getfield(component, :time)
    return (
        native_time_at(clock, completed_mcs - stride),
        native_time_at(clock, completed_mcs),
    )
end

function _assert_single_native_writers(endpoints)
    outputs = filter(endpoint ->
        endpoint.port isa Union{NativeOutput, NativeFieldOutput}, endpoints)
    for (index, endpoint) in pairs(outputs), prior in Iterators.take(outputs, index - 1)
        isequal(potts_endpoint(endpoint), potts_endpoint(prior)) || continue
        throw(ArgumentError(
            "Potts coupling endpoint has multiple native writers at " *
            "$(prior.component_path) and $(endpoint.component_path)"
        ))
    end
    return nothing
end

"""Deterministic identity of a preserved native MTK system."""
struct NativeSourceFingerprint
    hex::String
end

Base.string(value::NativeSourceFingerprint) = value.hex
Base.:(==)(left::NativeSourceFingerprint, right::NativeSourceFingerprint) =
    left.hex == right.hex
Base.hash(value::NativeSourceFingerprint, seed::UInt) = hash(value.hex, seed)
Base.show(io::IO, value::NativeSourceFingerprint) =
    print(io, "NativeSourceFingerprint(\"", value.hex, "\")")

"""One native declaration after its Potts endpoints have been resolved."""
struct CompletedNativeComponent{C <: NativeComponent, E <: Tuple}
    path::Tuple{Vararg{Symbol}}
    declaration::C
    endpoints::E
    source_fingerprint::NativeSourceFingerprint

    function CompletedNativeComponent(
            path::Tuple{Vararg{Symbol}},
            declaration::C,
            endpoints::E,
            source_fingerprint::NativeSourceFingerprint,
        ) where {C <: NativeComponent, E <: Tuple}
        isempty(path) && throw(ArgumentError(
            "a completed native component requires a qualified path"
        ))
        path[end] === nameof(declaration) || throw(ArgumentError(
            "completed native component path must end in its declaration name"
        ))
        all(endpoint -> endpoint.component_path == path, endpoints) ||
            throw(ArgumentError(
                "completed native component endpoints must share its path"
            ))
        return new{C, E}(path, declaration, endpoints, source_fingerprint)
    end
end

"""
The result of full-MTK native structural compilation. Both `original_system`
and `scheduled_system` are retained explicitly; accessors are never copied into
a Potts surrogate.
"""
struct ScheduledNativeComponent{C <: NativeComponent, O, S, E <: Tuple}
    path::Tuple{Vararg{Symbol}}
    declaration::C
    original_system::O
    scheduled_system::S
    endpoints::E
    original_fingerprint::NativeSourceFingerprint
    scheduled_fingerprint::NativeSourceFingerprint

    function ScheduledNativeComponent(
            path::Tuple{Vararg{Symbol}},
            declaration::C,
            original_system::O,
            scheduled_system::S,
            endpoints::E,
            original_fingerprint::NativeSourceFingerprint,
            scheduled_fingerprint::NativeSourceFingerprint,
        ) where {C <: NativeComponent, O, S, E <: Tuple}
        isempty(path) && throw(ArgumentError(
            "a scheduled native component requires a qualified path"
        ))
        path[end] === nameof(declaration) || throw(ArgumentError(
            "scheduled native component path must end in its declaration name"
        ))
        all(endpoint -> endpoint.component_path == path, endpoints) ||
            throw(ArgumentError(
                "scheduled native component endpoints must share its path"
            ))
        original_system === native_source(declaration) || throw(ArgumentError(
            "scheduled native component must retain its original source by identity"
        ))
        return new{C, O, S, E}(
            path,
            declaration,
            original_system,
            scheduled_system,
            endpoints,
            original_fingerprint,
            scheduled_fingerprint,
        )
    end
end

native_component_path(component::CompletedNativeComponent) = getfield(component, :path)
native_component_path(component::ScheduledNativeComponent) = getfield(component, :path)

native_original_system(component::ScheduledNativeComponent) =
    getfield(component, :original_system)
native_scheduled_system(component::ScheduledNativeComponent) =
    getfield(component, :scheduled_system)
native_coupling_endpoints(component::ScheduledNativeComponent) =
    getfield(component, :endpoints)
native_original_fingerprint(component::ScheduledNativeComponent) =
    getfield(component, :original_fingerprint)
native_scheduled_fingerprint(component::ScheduledNativeComponent) =
    getfield(component, :scheduled_fingerprint)

"""The scheduled MTK system is the native SymbolicIndexingInterface provider."""
native_index_provider(component::ScheduledNativeComponent) =
    native_scheduled_system(component)

native_problem_constructor(component::ScheduledNativeComponent) =
    native_problem_constructor(native_family(getfield(component, :declaration)))
native_problem_constructor(::ODEComponent) = SciMLBase.ODEProblem
native_problem_constructor(::DAEComponent) = SciMLBase.DAEProblem

"""
Extension hook implemented only when full ModelingToolkit is loaded. The hook
must call the public upstream `ModelingToolkitBase.mtkcompile` implementation.
"""
function mtkcompile_native end

"""Full-MTK extension hook for deterministic native source identity."""
function native_source_fingerprint end

"""Full-MTK hook for path-qualified runtime capability preflight."""
function preflight_native_component end

"""Full-MTK hook that initializes one native logical state."""
function initialize_native_component end

"""Extension-owned initialization after one completed public preflight."""
function _initialize_preflighted_native_component end

"""Full-MTK hook that advances one native logical state through one due interval."""
function advance_native_component end

"""Full-MTK hook that evaluates a native symbolic value from logical state."""
function native_component_value end

"""Full-MTK hook that constructs an SII-compatible logical-state view."""
function native_state_view end

"""Closed-suite solver evidence lookup; implemented by the full-MTK extension."""
function _native_profile_evidence end

# Full ModelingToolkit owns compilation of symbolic per-cell lifecycle maps.
# Base declares only this late extension seam so lifecycle events consume an
# already-compiled fixed-shape policy.
function _lower_native_cell_state_policy end

# Full ModelingToolkit owns the numerical lane implementation for an admitted
# batched per-cell profile. Base owns deterministic lane selection/publication.
function _advance_native_cell_batch end

# Full MTK constructs the standard continuation problem; backend extensions
# consume it without copying or reimplementing MTK initialization semantics.
function _native_continuation_problem end

# Full MTK constructs the standard initialization problem for backend
# extensions whose numerical algorithm is device-only.
function _native_initial_problem end

# Full MTK maps a solver result back into the stable logical checkpoint schema.
function _native_logical_from_problem_solution end

"""Exact package stack behind a native runtime row; extension-owned."""
function _native_runtime_stack_identity end

"""Audited logical-restart schema behind a native runtime row."""
function _native_replay_schema end
