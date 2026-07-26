abstract type AbstractPathSegment end

struct NameSegment <: AbstractPathSegment
    value::String
    function NameSegment(value::AbstractString)
        text = String(value)
        isempty(text) && _fail(:invalid_path_segment, "name segments cannot be empty")
        occursin('\0', text) &&
            _fail(:invalid_path_segment, "name segments cannot contain NUL")
        new(text)
    end
end

struct IndexSegment <: AbstractPathSegment
    value::Int64
    function IndexSegment(value::Integer)
        value < 0 && _fail(:invalid_path_segment, "index segments must be nonnegative";
            value)
        value <= typemax(Int64) ||
            _fail(:path_index_overflow, "index segment exceeds the Int64 identity range";
                value=string(value))
        new(Int64(value))
    end
end

"""
Canonical hierarchical path. Identity is the typed segment tuple, so the name
`"1"` and index `1` are distinct and display formatting is not semantic.
"""
struct Path
    parts::Tuple{Vararg{AbstractPathSegment}}
end

Path() = Path(())
Path(parts::AbstractPathSegment...) = Path(tuple(parts...))

_segment(segment::AbstractPathSegment) = segment
_segment(segment::Union{AbstractString,Symbol}) = NameSegment(string(segment))
_segment(segment::Integer) = IndexSegment(segment)

path(parts...) = Path(map(_segment, parts)...)
segments(value::Path) = value.parts

function parentpath(value::Path)
    isempty(value.parts) && _fail(:root_has_no_parent, "the root path has no parent")
    Path(Base.front(value.parts))
end

child(value::Path, parts...) = Path((value.parts..., map(_segment, parts)...)...)

function isprefixpath(prefix::Path, value::Path)
    length(prefix.parts) <= length(value.parts) || return false
    all(prefix.parts[index] == value.parts[index] for index in eachindex(prefix.parts))
end

Base.length(value::Path) = length(value.parts)
Base.isempty(value::Path) = isempty(value.parts)
Base.iterate(value::Path, state...) = iterate(value.parts, state...)
Base.getindex(value::Path, index::Integer) = value.parts[index]

_segment_order(segment::NameSegment) = (0, segment.value)
_segment_order(segment::IndexSegment) = (1, string(segment.value))

function Base.isless(left::Path, right::Path)
    for (a, b) in zip(left.parts, right.parts)
        a == b && continue
        return _segment_order(a) < _segment_order(b)
    end
    return length(left.parts) < length(right.parts)
end

Base.:(==)(left::Path, right::Path) = left.parts == right.parts
Base.hash(value::Path, seed::UInt) = hash(value.parts, seed)

function Base.show(io::IO, value::Path)
    print(io, '/')
    for (index, segment) in enumerate(value.parts)
        index == 1 || print(io, '/')
        if segment isa NameSegment
            print(io, replace(segment.value, "~" => "~0", "/" => "~1"))
        else
            print(io, '[', segment.value, ']')
        end
    end
end
