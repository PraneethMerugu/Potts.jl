"""One typed semantic binding. Collection order is never scientific priority."""
struct Binding{K, V}
    key::K
    value::V
end

Binding(pair::Pair{K, V}) where {K, V} = Binding{K, V}(first(pair), last(pair))

"""
An immutable, canonically ordered binding collection whose public type does not encode its size.
The tuple is deliberately an abstract field: bindings are host authoring data and lower to concrete
device descriptors before execution.
"""
struct BindingTable{K, V}
    entries::Tuple

    function BindingTable{K, V}(entries::Tuple) where {K, V}
        all(entry -> entry isa Binding{K, V}, entries) || throw(ArgumentError(
            "every binding must have key type $K and value type $V"))
        keys = map(entry -> entry.key, entries)
        length(unique(keys)) == length(keys) || throw(ArgumentError(
            "duplicate semantic bindings are not allowed"))
        ordered = Tuple(sort!(collect(entries); by = entry -> _binding_sort_key(entry.key)))
        return new{K, V}(ordered)
    end
end

BindingTable(entries::Tuple{Binding{K, V}, Vararg{Binding{K, V}}}) where {K, V} =
    BindingTable{K, V}(entries)

function BindingTable(first_pair::Pair{K, V},
        remaining_pairs::Pair{K, V}...) where {K, V}
    pairs = (first_pair, remaining_pairs...)
    return BindingTable(Tuple(Binding(pair) for pair in pairs))
end

_binding_sort_key(key) = string(typeof(key), ':', repr(key))
_binding_sort_key(key::Union{CellType, Medium, SemanticName}) = _identity_text(key)

Base.length(table::BindingTable) = length(table.entries)
Base.isempty(table::BindingTable) = isempty(table.entries)
Base.iterate(table::BindingTable, state...) = iterate(table.entries, state...)
Base.keys(table::BindingTable) = map(entry -> entry.key, table.entries)
Base.values(table::BindingTable) = map(entry -> entry.value, table.entries)
Base.pairs(table::BindingTable) = table.entries

function Base.getindex(table::BindingTable, key)
    for entry in table.entries
        entry.key == key && return entry.value
    end
    throw(KeyError(key))
end

function Base.get(table::BindingTable{K}, key::K, default) where {K}
    for entry in table.entries
        entry.key == key && return entry.value
    end
    return default
end

Base.haskey(table::BindingTable, key) = any(entry -> entry.key == key, table.entries)

"""Canonical pair identity for directed or symmetric scientific laws."""
struct PairIdentity
    left::AbstractBiologicalType
    right::AbstractBiologicalType

    PairIdentity(left::AbstractBiologicalType, right::AbstractBiologicalType, ::Nothing) =
        new(left, right)
end

function PairIdentity(left::AbstractBiologicalType, right::AbstractBiologicalType;
        symmetric::Bool)
    if symmetric && _identity_text(right) < _identity_text(left)
        return PairIdentity(right, left, nothing)
    end
    return PairIdentity(left, right, nothing)
end

Base.:(==)(left::PairIdentity, right::PairIdentity) =
    left.left == right.left && left.right == right.right
Base.hash(pair::PairIdentity, seed::UInt) = hash((pair.left, pair.right), seed)
_binding_sort_key(pair::PairIdentity) =
    string(_identity_text(pair.left), "=>", _identity_text(pair.right))

function Base.show(io::IO, pair::PairIdentity)
    print(io, '(', _identity_text(pair.left), ", ", _identity_text(pair.right), ')')
end

"""Typed pairwise scientific values with explicit symmetry and missing-pair behavior."""
struct PairwiseLaw{T <: AbstractFloat}
    name::SemanticName
    values::BindingTable{PairIdentity, T}
    symmetric::Bool
    default::Union{Nothing, T}
end

function PairwiseLaw(pairs::Pair...; name::Symbol = :pairwise,
        namespace::Namespace = Namespace(), symmetric::Bool = true, default = nothing)
    isempty(pairs) && throw(ArgumentError("a pairwise law must declare at least one pair"))
    all(pair -> first(pair) isa Tuple && length(first(pair)) == 2 &&
        all(value -> value isa Union{AbstractBiologicalType, CellRole}, first(pair)) &&
        last(pair) isa Real,
        pairs) || throw(ArgumentError(
            "pairwise entries must be `(biological_type_or_cell_role, biological_type_or_cell_role) => real`"))
    T = float(promote_type(map(pair -> typeof(last(pair)), pairs)...,
        default === nothing ? Float32 : typeof(default)))
    converted = map(pairs) do pair
        left, right = first(pair)
        left = left isa CellRole ? _cell_reference(left) : left
        right = right isa CellRole ? _cell_reference(right) : right
        PairIdentity(left, right; symmetric) => T(last(pair))
    end
    entries = Tuple(Binding{PairIdentity, T}(first(pair), last(pair)) for pair in converted)
    table = BindingTable{PairIdentity, T}(entries)
    resolved_default = default === nothing ? nothing : T(default)
    all(entry -> isfinite(entry.value), table) || throw(ArgumentError(
        "pairwise values must be finite"))
    resolved_default === nothing || isfinite(resolved_default) || throw(ArgumentError(
        "the pairwise default must be finite"))
    return PairwiseLaw(SemanticName(name; namespace), table, symmetric, resolved_default)
end

semantic_identity(law::PairwiseLaw) = law.name
