function _write_length(io::IO, count::Integer)
    print(io, count, ':')
end

_canonical(io::IO, ::Nothing) = write(io, "N")
_canonical(io::IO, ::Missing) = write(io, "M")
_canonical(io::IO, value::Bool) = write(io, value ? "B1" : "B0")
_canonical(io::IO, value::Char) = (write(io, 'C'); _canonical(io, UInt32(value)))

function _canonical(io::IO, value::Rational)
    write(io, 'Q')
    _canonical(io, numerator(value))
    _canonical(io, denominator(value))
end

function _canonical(io::IO, value::Signed)
    write(io, 'I')
    _canonical(io, string(typeof(value)))
    _canonical(io, string(value))
end

function _canonical(io::IO, value::Unsigned)
    write(io, 'U')
    _canonical(io, string(typeof(value)))
    _canonical(io, string(value))
end

function _canonical(io::IO, value::Float16)
    write(io, "F16")
    _canonical(io, reinterpret(UInt16, value))
end

function _canonical(io::IO, value::Float32)
    write(io, "F32")
    _canonical(io, reinterpret(UInt32, value))
end

function _canonical(io::IO, value::Float64)
    write(io, "F64")
    _canonical(io, reinterpret(UInt64, value))
end

function _canonical(io::IO, value::AbstractString)
    bytes = codeunits(value)
    write(io, 'S')
    _write_length(io, length(bytes))
    write(io, bytes)
end

_canonical(io::IO, value::Symbol) = (write(io, 'Y'); _canonical(io, string(value)))

function _canonical(io::IO, value::NameSegment)
    write(io, "PN")
    _canonical(io, value.value)
end

function _canonical(io::IO, value::IndexSegment)
    write(io, "PI")
    _canonical(io, value.value)
end

function _canonical(io::IO, value::Path)
    write(io, 'P')
    _write_length(io, length(value))
    foreach(segment -> _canonical(io, segment), value)
end

function _canonical(io::IO, value::TimeScale)
    write(io, "TS")
    _canonical(io, value.numerator)
    _canonical(io, value.denominator)
    _canonical(io, value.unit)
end

function _canonical(io::IO, value::LogicalTime)
    write(io, "LT")
    _canonical(io, value.tick)
    _canonical(io, value.scale)
end

function _canonical(io::IO, value::Duration)
    write(io, "DU")
    _canonical(io, value.tick)
    _canonical(io, value.scale)
end

function _canonical(io::IO, value::Tuple)
    write(io, 'T')
    _write_length(io, length(value))
    foreach(element -> _canonical(io, element), value)
end

function _canonical(io::IO, value::NamedTuple)
    write(io, "NT")
    _canonical(io, keys(value))
    _canonical(io, Tuple(value))
end

function _canonical(io::IO, value::Pair)
    write(io, "KV")
    _canonical(io, first(value))
    _canonical(io, last(value))
end

function _canonical(io::IO, value::AbstractArray)
    write(io, 'A')
    _canonical(io, string(eltype(value)))
    _canonical(io, size(value))
    for element in value
        _canonical(io, element)
    end
end

function _canonical(io::IO, value::AbstractDict)
    write(io, 'D')
    encoded = [(canonical_bytes(key), key) for key in keys(value)]
    sort!(encoded; by=item -> bytes2hex(first(item)))
    _write_length(io, length(encoded))
    for (_, key) in encoded
        _canonical(io, key)
        _canonical(io, value[key])
    end
end

function _canonical(io::IO, value::AbstractSet)
    write(io, 'E')
    encoded = sort!(canonical_bytes.(collect(value)); by=bytes2hex)
    _write_length(io, length(encoded))
    foreach(bytes -> (write(io, "R"); _write_length(io, length(bytes)); write(io, bytes)), encoded)
end

function _canonical(io::IO, value)
    _fail(:unsupported_canonical_value,
        "value has no registered canonical encoding"; type=string(typeof(value)))
end

function canonical_bytes(value)
    io = IOBuffer()
    _canonical(io, value)
    take!(io)
end

canonical_fingerprint(value) = bytes2hex(sha256(canonical_bytes(value)))
