abstract type AbstractSchema end

struct DynamicDimension end
const _DYNAMIC_DIMENSION = DynamicDimension()

struct NoDefault end
const _NO_DEFAULT = NoDefault()

"""
A structural leaf contract. Julia element type and shape are separate from
semantic metadata and publication policy.
"""
struct LeafSchema{T,N} <: AbstractSchema
    shape::NTuple{N,Union{Int,DynamicDimension}}
    default::Any
    required::Bool
    nominal_id::Union{Nothing,String}
    units::Union{Nothing,String}
    ontology::Union{Nothing,String}
    owner::Symbol
    conservation::Symbol
    update_law::Symbol
    division_law::Symbol
    persistence::Symbol
    continuation::Symbol
    residency::Symbol
    codec::Symbol
end

function LeafSchema(::Type{T};
    shape=(),
    default=_NO_DEFAULT,
    required::Bool=default === _NO_DEFAULT,
    nominal_id=nothing,
    units=nothing,
    ontology=nothing,
    owner::Symbol=:runtime,
    conservation::Symbol=:none,
    update_law::Symbol=:replace,
    division_law::Symbol=:unsupported,
    persistence::Symbol=:required,
    continuation::Symbol=:state,
    residency::Symbol=:cpu,
    codec::Symbol=:canonical_v1,
) where {T}
    normalized_shape = tuple(map(shape) do dimension
        dimension === _DYNAMIC_DIMENSION && return dimension
        dimension isa Integer ||
            _fail(:invalid_schema_shape, "shape entries must be integers or DynamicDimension";
                dimension)
        dimension >= 0 ||
            _fail(:invalid_schema_shape, "static dimensions must be nonnegative"; dimension)
        Int(dimension)
    end...)
    owner in (:runtime, :process, :shared, :external) ||
        _fail(:invalid_schema_owner, "unknown ownership policy"; owner)
    persistence in (:required, :transient, :derived) ||
        _fail(:invalid_persistence_policy, "unknown persistence policy"; persistence)
    residency in (:cpu, :metal, :rocm, :cuda, :agnostic) ||
        _fail(:invalid_residency, "unknown state residency"; residency)
    schema = LeafSchema{T,length(normalized_shape)}(
        normalized_shape,
        default === _NO_DEFAULT ? _NO_DEFAULT : deepcopy(default),
        required,
        isnothing(nominal_id) ? nothing : String(nominal_id),
        isnothing(units) ? nothing : String(units),
        isnothing(ontology) ? nothing : String(ontology),
        owner,
        conservation,
        update_law,
        division_law,
        persistence,
        continuation,
        residency,
        codec,
    )
    default === _NO_DEFAULT || validate_value(schema, default)
    schema
end

struct BranchSchema <: AbstractSchema
    children::Tuple{Vararg{Pair{String,AbstractSchema}}}
end

function BranchSchema(children::Union{NamedTuple,AbstractDict,AbstractVector,Tuple})
    child_pairs = Pair{String,AbstractSchema}[]
    iterable = children isa NamedTuple ? Base.pairs(children) : children
    for (name, schema) in iterable
        schema isa AbstractSchema ||
            _fail(:invalid_child_schema, "branch children must be schemas"; name, type=typeof(schema))
        push!(child_pairs, String(name) => schema)
    end
    sort!(child_pairs; by=first)
    names = first.(child_pairs)
    length(names) == length(unique(names)) ||
        _fail(:duplicate_schema_child, "branch child names must be unique")
    BranchSchema(tuple(child_pairs...))
end

BranchSchema(; children...) = BranchSchema((; children...))

function schema_at(schema::AbstractSchema, target::Path)
    current = schema
    for segment in target
        segment isa NameSegment ||
            _fail(:schema_path_mismatch, "schema branches use name segments"; target)
        current isa BranchSchema ||
            _fail(:schema_path_mismatch, "path descends through a leaf schema"; target)
        position = findfirst(pair -> first(pair) == segment.value, current.children)
        isnothing(position) &&
            _fail(:unknown_schema_path, "path is not declared by the schema"; target)
        current = last(current.children[position])
    end
    current
end

function schema_leaves(schema::AbstractSchema, prefix::Path=Path())
    schema isa LeafSchema && return (prefix => schema,)
    result = Pair{Path,LeafSchema}[]
    for (name, child_schema) in schema.children
        append!(result, schema_leaves(child_schema, child(prefix, name)))
    end
    tuple(result...)
end

function validate_value(schema::LeafSchema{T,N}, value) where {T,N}
    if N == 0
        value isa T ||
            _fail(:schema_type_mismatch, "scalar value has the wrong type";
                expected=string(T), actual=string(typeof(value)))
    else
        value isa AbstractArray ||
            _fail(:schema_rank_mismatch, "array schema requires an array value";
                expected_rank=N, actual=string(typeof(value)))
        eltype(value) <: T ||
            _fail(:schema_type_mismatch, "array element type is incompatible";
                expected=string(T), actual=string(eltype(value)))
        ndims(value) == N ||
            _fail(:schema_rank_mismatch, "array rank is incompatible";
                expected=N, actual=ndims(value))
        for (expected, actual) in zip(schema.shape, size(value))
            expected isa DynamicDimension || expected == actual ||
                _fail(:schema_shape_mismatch, "array shape is incompatible";
                    expected=schema.shape, actual=size(value))
        end
    end
    true
end

function _canonical(io::IO, schema::LeafSchema{T}) where {T}
    write(io, "LS")
    _canonical(io, string(T))
    _canonical(io, map(dimension -> dimension isa DynamicDimension ? :dynamic : dimension,
        schema.shape))
    _canonical(io, schema.default isa NoDefault ? :no_default : schema.default)
    _canonical(io, schema.required)
    _canonical(io, schema.nominal_id)
    _canonical(io, schema.units)
    _canonical(io, schema.ontology)
    _canonical(io, schema.owner)
    _canonical(io, schema.conservation)
    _canonical(io, schema.update_law)
    _canonical(io, schema.division_law)
    _canonical(io, schema.persistence)
    _canonical(io, schema.continuation)
    _canonical(io, schema.residency)
    _canonical(io, schema.codec)
end

function _canonical(io::IO, schema::BranchSchema)
    write(io, "BS")
    _canonical(io, schema.children)
end
