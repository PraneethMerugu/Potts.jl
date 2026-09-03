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
"""Preserve ModelingToolkit initialization equations for a native component."""
struct PreserveNativeInitialization <: AbstractNativeInitializationPolicy end

"""Native continuous and discrete events remain owned by the MTK system."""
abstract type AbstractNativeEventPolicy end
"""Preserve declared native events structurally for capability preflight."""
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
"""Require the concrete native solver algorithm at `init` time."""
struct LateBoundNativeAlgorithm <: AbstractNativeAlgorithmPolicy end

"""Capability admission is checked against the complete late runtime profile."""
abstract type AbstractNativeCapabilityPolicy end
"""Use package-qualified structural, numerical, and backend capability rows."""
struct StandardNativeCapability <: AbstractNativeCapabilityPolicy end
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

"""Execution-mode family for native numerical solves."""
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
component) or a bounded group of `PerCell` lanes in one DiffEqGPU
KernelAbstractions kernel on
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

"""
    NativeSolveProfile(path, algorithm; profile_id=nothing,
                       execution=SerialNativeExecution(),
                       deterministic=false, exact_replay=false, options...)

Late numerical policy for exactly one native component. There is deliberately
no default native solver. Functional execution is admitted by structural,
numerical, and backend preflight. Exact replay additionally requires
`exact_replay=true`, an explicitly pinned `profile_id`, the author's
`deterministic=true` assertion, and a matching closed replay row. `execution`
selects serial versus per-cell batched numerical lanes; it never changes CPM
ordering or trajectory-ensemble identity. A profile with `exact_replay=false`
may execute but cannot checkpoint native state.
"""
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
