# The scheduled manifest owns logical parameter identity, shape, units and the
# flat scalar slots consumed by Core. Numerical precision is selected later.
struct ReferenceUnitDescriptor
    name::Symbol
    dimension::String
    scale::Float64
end

struct RuntimeParameter
    name::Symbol
    identity::NamedTuple
    symbolic::Any
    default::Any
    required::Bool
    unit::Union{Nothing, ReferenceUnitDescriptor}
    shape::Tuple
    first_slot::Int
    input::Bool
    output::Bool
end

struct ParameterManifest
    entries::Vector{RuntimeParameter}
    structural::Vector{NamedTuple}
    reference_units::Tuple
end

Base.length(manifest::ParameterManifest) = length(manifest.entries)
Base.iterate(manifest::ParameterManifest, state...) = iterate(manifest.entries, state...)
Base.getindex(manifest::ParameterManifest, index::Integer) = manifest.entries[index]

_parameter_width(entry::RuntimeParameter) = isempty(entry.shape) ? 1 : prod(entry.shape)
_parameter_slots(entry::RuntimeParameter) = entry.first_slot:(entry.first_slot + _parameter_width(entry) - 1)
_parameter_slot_count(manifest::ParameterManifest) = sum(_parameter_width, manifest.entries; init = 0)

struct ParameterComponentIndex
    parameter::Int
    component::Int
end

_parameter_owner(index::Integer) = Int(index)
_parameter_owner(index::ParameterComponentIndex) = index.parameter
_parameter_slots(manifest::ParameterManifest, index::Integer) = _parameter_slots(manifest[index])
function _parameter_slots(manifest::ParameterManifest, index::ParameterComponentIndex)
    entry = manifest[index.parameter]
    1 <= index.component <= _parameter_width(entry) || throw(BoundsError(entry.shape, index.component))
    slot = entry.first_slot + index.component - 1
    return slot:slot
end

function _parameter_shape(value)
    SymbolicIndexingInterface.symbolic_type(value) isa SymbolicIndexingInterface.ArraySymbolic || return ()
    shape = Tuple(size(value))
    length(shape) == 1 && only(shape) isa Integer && only(shape) > 0 || throw(
        ArgumentError(
            "runtime array parameters currently require a declared nonempty fixed-vector shape"
        )
    )
    return shape
end

function _parameter_logical_value(entry::RuntimeParameter, values)
    isempty(entry.shape) && return only(values)
    return StaticArrays.SVector{only(entry.shape)}(Tuple(values))
end

function _validate_parameter_shape(name, shape, value)
    isempty(shape) && return nothing
    value isa AbstractArray && Tuple(size(value)) == shape || throw(
        ArgumentError(
            "parameter `$name` requires logical shape $shape"
        )
    )
    return nothing
end

function _parameter_values(manifest::ParameterManifest, buffer)
    return Tuple(_parameter_logical_value(entry, view(buffer, _parameter_slots(entry))) for entry in manifest)
end

function _saved_parameters(manifest::ParameterManifest, buffer::AbstractVector{T}) where {T}
    values = _parameter_values(manifest, buffer)
    named = NamedTuple{Tuple(entry.name for entry in manifest)}(values)
    return PottsParameters{T, typeof(values), typeof(named)}(values, named)
end
