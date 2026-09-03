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

"""Return the native symbolic variable represented by a coupling port."""
native_variable(port::Union{NativeInput, NativeOutput}) =
    getfield(port, :native_variable)
native_variable(port::NativeFieldOutput) = getfield(port, :native_variables)
native_variables(port::Union{NativeInput, NativeOutput}) = (native_variable(port),)
native_variables(port::NativeFieldOutput) = native_variable(port)
"""Return the Potts-side identity represented by a coupling port."""
potts_endpoint(port::NativeInput) = getfield(port, :from)
potts_endpoint(port::NativeOutput) = getfield(port, :to)
potts_endpoint(port::NativeFieldOutput) = getfield(port, :to)
"""Return the concrete value type required by a coupling port."""
native_value_type(port::_NativePort) = getfield(port, :value_type)
native_variable(endpoint::CouplingEndpointSchema) = native_variable(endpoint.port)
potts_endpoint(endpoint::CouplingEndpointSchema) = endpoint.potts_identity
native_value_type(endpoint::CouplingEndpointSchema) = native_value_type(endpoint.port)

"""Internal token that restricts construction to the validating outer constructor."""
struct _NativeConstructionToken end
const _NATIVE_CONSTRUCTION_TOKEN = _NativeConstructionToken()

