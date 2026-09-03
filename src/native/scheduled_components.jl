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

"""Return the fully qualified tuple path of a native component."""
native_component_path(component::CompletedNativeComponent) = getfield(component, :path)
native_component_path(component::ScheduledNativeComponent) = getfield(component, :path)

"""Return the original ModelingToolkit system retained after scheduling."""
native_original_system(component::ScheduledNativeComponent) =
    getfield(component, :original_system)
"""Return the structurally compiled ModelingToolkit system."""
native_scheduled_system(component::ScheduledNativeComponent) =
    getfield(component, :scheduled_system)
"""Return the ordered Potts/native coupling endpoint schemas."""
native_coupling_endpoints(component::ScheduledNativeComponent) =
    getfield(component, :endpoints)
"""Return the fingerprint of the original native system."""
native_original_fingerprint(component::ScheduledNativeComponent) =
    getfield(component, :original_fingerprint)
"""Return the fingerprint of the scheduled native system."""
native_scheduled_fingerprint(component::ScheduledNativeComponent) =
    getfield(component, :scheduled_fingerprint)

"""The scheduled MTK system is the native SymbolicIndexingInterface provider."""
native_index_provider(component::ScheduledNativeComponent) =
    native_scheduled_system(component)

"""Return the extension-owned constructor for the native numerical problem."""
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
