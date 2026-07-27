const LOGICAL_VALUE_CODEC_VERSION = "process-bigraph-logical-value-v1"
const _LOGICAL_MAGIC = UInt8[0x50, 0x42, 0x56, 0x31] # PBV1

mutable struct _LogicalReader
    bytes::Vector{UInt8}
    position::Int
end

function _write_u64(io::IO, value::UInt64)
    for shift in 0:8:56
        write(io, UInt8((value >> shift) & 0xff))
    end
end

function _read_exact(reader::_LogicalReader, count::Int)
    count >= 0 || _fail(:logical_codec_length,
        "logical codec requested a negative length")
    last_position = reader.position + count - 1
    last_position <= length(reader.bytes) ||
        _fail(:logical_codec_truncated,
            "logical value payload is truncated";
            position=reader.position, requested=count)
    bytes = reader.bytes[reader.position:last_position]
    reader.position = last_position + 1
    bytes
end

function _read_u8(reader::_LogicalReader)
    only(_read_exact(reader, 1))
end

function _read_u64(reader::_LogicalReader)
    bytes = _read_exact(reader, 8)
    value = UInt64(0)
    for (index, byte) in enumerate(bytes)
        value |= UInt64(byte) << (8 * (index - 1))
    end
    value
end

function _write_blob(io::IO, bytes)
    _write_u64(io, UInt64(length(bytes)))
    write(io, bytes)
end

_read_blob(reader::_LogicalReader) =
    _read_exact(reader, Int(_read_u64(reader)))

function _write_text(io::IO, value::AbstractString)
    _write_blob(io, codeunits(value))
end

_read_text(reader::_LogicalReader) = String(_read_blob(reader))

const _LOGICAL_TYPES = Dict{String,DataType}(
    "Any" => Any,
    "Bool" => Bool,
    "Int8" => Int8,
    "Int16" => Int16,
    "Int32" => Int32,
    "Int64" => Int64,
    "Int128" => Int128,
    "UInt8" => UInt8,
    "UInt16" => UInt16,
    "UInt32" => UInt32,
    "UInt64" => UInt64,
    "UInt128" => UInt128,
    "Float16" => Float16,
    "Float32" => Float32,
    "Float64" => Float64,
    "String" => String,
    "Symbol" => Symbol,
    "Char" => Char,
)

function _logical_type(name::AbstractString)
    haskey(_LOGICAL_TYPES, String(name)) ||
        _fail(:unsupported_logical_type,
            "logical codec does not admit the encoded concrete type";
            type=String(name))
    _LOGICAL_TYPES[String(name)]
end

function _encode_logical(io::IO, ::Nothing)
    write(io, UInt8(0x00))
end

function _encode_logical(io::IO, ::Missing)
    write(io, UInt8(0x01))
end

function _encode_logical(io::IO, value::Bool)
    write(io, UInt8(0x02), UInt8(value))
end

function _encode_logical(io::IO, value::Signed)
    write(io, UInt8(0x03))
    _write_text(io, string(typeof(value)))
    _write_text(io, string(value))
end

function _encode_logical(io::IO, value::Unsigned)
    write(io, UInt8(0x04))
    _write_text(io, string(typeof(value)))
    _write_text(io, string(value))
end

function _encode_logical(io::IO, value::Float16)
    write(io, UInt8(0x05))
    _write_u64(io, UInt64(reinterpret(UInt16, value)))
end

function _encode_logical(io::IO, value::Float32)
    write(io, UInt8(0x06))
    _write_u64(io, UInt64(reinterpret(UInt32, value)))
end

function _encode_logical(io::IO, value::Float64)
    write(io, UInt8(0x07))
    _write_u64(io, reinterpret(UInt64, value))
end

function _encode_logical(io::IO, value::AbstractString)
    write(io, UInt8(0x08))
    _write_text(io, value)
end

function _encode_logical(io::IO, value::Symbol)
    write(io, UInt8(0x09))
    _write_text(io, String(value))
end

function _encode_logical(io::IO, value::Char)
    write(io, UInt8(0x0a))
    _write_u64(io, UInt64(UInt32(value)))
end

function _encode_logical(io::IO, value::Rational)
    write(io, UInt8(0x0b))
    _encode_logical(io, numerator(value))
    _encode_logical(io, denominator(value))
end

function _encode_logical(io::IO, value::Tuple)
    write(io, UInt8(0x10))
    _write_u64(io, UInt64(length(value)))
    foreach(item -> _encode_logical(io, item), value)
end

function _encode_logical(io::IO, value::NamedTuple)
    write(io, UInt8(0x11))
    _write_u64(io, UInt64(length(value)))
    for (name, item) in pairs(value)
        _write_text(io, String(name))
        _encode_logical(io, item)
    end
end

function _encode_logical(io::IO, value::Pair)
    write(io, UInt8(0x12))
    _encode_logical(io, first(value))
    _encode_logical(io, last(value))
end

function _encode_logical(io::IO, value::AbstractArray)
    write(io, UInt8(0x13))
    _write_text(io, string(eltype(value)))
    _write_u64(io, UInt64(ndims(value)))
    for dimension in size(value)
        _write_u64(io, UInt64(dimension))
    end
    for item in value
        _encode_logical(io, item)
    end
end

function _encode_logical(io::IO, value::AbstractDict)
    write(io, UInt8(0x14))
    _write_text(io, string(keytype(value)))
    _write_text(io, string(valtype(value)))
    encoded = [(encode_logical_value(key), key) for key in keys(value)]
    sort!(encoded; by=item -> bytes2hex(first(item)))
    _write_u64(io, UInt64(length(encoded)))
    for (_, key) in encoded
        _encode_logical(io, key)
        _encode_logical(io, value[key])
    end
end

function _encode_logical(io::IO, value::AbstractSet)
    write(io, UInt8(0x15))
    _write_text(io, string(eltype(value)))
    encoded = sort!(encode_logical_value.(collect(value)); by=bytes2hex)
    _write_u64(io, UInt64(length(encoded)))
    for bytes in encoded
        _write_blob(io, bytes)
    end
end

function _encode_logical(io::IO, value::Path)
    write(io, UInt8(0x16))
    _write_u64(io, UInt64(length(value)))
    for segment in segments(value)
        if segment isa NameSegment
            write(io, UInt8(0x00))
            _write_text(io, segment.value)
        else
            write(io, UInt8(0x01))
            _write_u64(io, UInt64(segment.value))
        end
    end
end

function _encode_logical(io::IO, value::TimeScale)
    write(io, UInt8(0x17))
    _encode_logical(io, value.numerator)
    _encode_logical(io, value.denominator)
    _encode_logical(io, value.unit)
end

function _encode_logical(io::IO, value::LogicalTime)
    write(io, UInt8(0x18))
    _encode_logical(io, value.tick)
    _encode_logical(io, value.scale)
end

function _encode_logical(io::IO, value::Duration)
    write(io, UInt8(0x19))
    _encode_logical(io, value.tick)
    _encode_logical(io, value.scale)
end

function _encode_logical(io::IO, schema::LeafSchema{T}) where {T}
    write(io, UInt8(0x1a))
    _write_text(io, string(T))
    _encode_logical(io, tuple((
        dimension isa DynamicDimension ? nothing : dimension
        for dimension in schema.shape
    )...))
    _encode_logical(io, !(schema.default isa NoDefault))
    schema.default isa NoDefault ||
        _encode_logical(io, schema.default)
    _encode_logical(io, schema.required)
    _encode_logical(io, schema.nominal_id)
    _encode_logical(io, schema.units)
    _encode_logical(io, schema.ontology)
    _encode_logical(io, schema.owner)
    _encode_logical(io, schema.conservation)
    _encode_logical(io, schema.update_law)
    _encode_logical(io, schema.division_law)
    _encode_logical(io, schema.persistence)
    _encode_logical(io, schema.continuation)
    _encode_logical(io, schema.residency)
    _encode_logical(io, schema.codec)
end

function _encode_logical(io::IO, schema::BranchSchema)
    write(io, UInt8(0x1b))
    _encode_logical(io, schema.children)
end

function _encode_logical(io::IO, capability::CapabilitySet)
    write(io, UInt8(0x1c))
    _encode_logical(io, capability.domains)
    _encode_logical(io, capability.purity)
    _encode_logical(io, capability.idempotent)
    _encode_logical(io, capability.continuation_codec)
    _encode_logical(io, capability.replay_class)
end

function _encode_logical(io::IO, transfer::TransferDeclaration)
    write(io, UInt8(0x1d))
    _encode_logical(io, transfer.source)
    _encode_logical(io, transfer.destination)
    _encode_logical(io, transfer.max_bytes)
    _encode_logical(io, transfer.cadence)
    _encode_logical(io, transfer.precision)
    _encode_logical(io, transfer.synchronization)
end

function _encode_logical(io::IO, value)
    _fail(:unsupported_logical_value,
        "value has no registered logical checkpoint codec";
        type=string(typeof(value)))
end

function encode_logical_value(value)
    io = IOBuffer()
    write(io, _LOGICAL_MAGIC)
    _encode_logical(io, value)
    take!(io)
end

function _decode_logical(reader::_LogicalReader)
    tag = _read_u8(reader)
    tag == 0x00 && return nothing
    tag == 0x01 && return missing
    tag == 0x02 && return _read_u8(reader) == 0x01
    if tag == 0x03
        type = _logical_type(_read_text(reader))
        return parse(type, _read_text(reader))
    elseif tag == 0x04
        type = _logical_type(_read_text(reader))
        return parse(type, _read_text(reader))
    elseif tag == 0x05
        return reinterpret(Float16, UInt16(_read_u64(reader)))
    elseif tag == 0x06
        return reinterpret(Float32, UInt32(_read_u64(reader)))
    elseif tag == 0x07
        return reinterpret(Float64, _read_u64(reader))
    elseif tag == 0x08
        return _read_text(reader)
    elseif tag == 0x09
        return Symbol(_read_text(reader))
    elseif tag == 0x0a
        return Char(UInt32(_read_u64(reader)))
    elseif tag == 0x0b
        return _decode_logical(reader) // _decode_logical(reader)
    elseif tag == 0x10
        return tuple((_decode_logical(reader)
            for _ in 1:Int(_read_u64(reader)))...)
    elseif tag == 0x11
        count = Int(_read_u64(reader))
        name_values = Pair{Symbol,Any}[]
        for _ in 1:count
            push!(name_values,
                Symbol(_read_text(reader)) => _decode_logical(reader))
        end
        names = tuple((first(pair) for pair in name_values)...)
        values = tuple((last(pair) for pair in name_values)...)
        return NamedTuple{names}(values)
    elseif tag == 0x12
        return _decode_logical(reader) => _decode_logical(reader)
    elseif tag == 0x13
        type = _logical_type(_read_text(reader))
        dimensions = ntuple(_ -> Int(_read_u64(reader)),
            Int(_read_u64(reader)))
        count = prod(dimensions; init=1)
        values = Vector{type}(undef, count)
        for index in eachindex(values)
            values[index] = _decode_logical(reader)
        end
        return reshape(values, dimensions)
    elseif tag == 0x14
        key_type = _logical_type(_read_text(reader))
        value_type = _logical_type(_read_text(reader))
        result = Dict{key_type,value_type}()
        for _ in 1:Int(_read_u64(reader))
            key = _decode_logical(reader)
            value = _decode_logical(reader)
            result[key] = value
        end
        return result
    elseif tag == 0x15
        type = _logical_type(_read_text(reader))
        result = Set{type}()
        for _ in 1:Int(_read_u64(reader))
            push!(result, decode_logical_value(_read_blob(reader)))
        end
        return result
    elseif tag == 0x16
        values = AbstractPathSegment[]
        for _ in 1:Int(_read_u64(reader))
            segment_tag = _read_u8(reader)
            if segment_tag == 0x00
                push!(values, NameSegment(_read_text(reader)))
            elseif segment_tag == 0x01
                push!(values, IndexSegment(Int(_read_u64(reader))))
            else
                _fail(:logical_codec_tag,
                    "unknown path-segment tag"; tag=segment_tag)
            end
        end
        return Path(tuple(values...))
    elseif tag == 0x17
        return TimeScale(
            _decode_logical(reader),
            _decode_logical(reader),
            _decode_logical(reader),
        )
    elseif tag == 0x18
        return LogicalTime(_decode_logical(reader), _decode_logical(reader))
    elseif tag == 0x19
        return Duration(_decode_logical(reader), _decode_logical(reader))
    elseif tag == 0x1a
        type = _logical_type(_read_text(reader))
        encoded_shape = _decode_logical(reader)
        shape = tuple((isnothing(dimension) ?
            _DYNAMIC_DIMENSION : dimension
            for dimension in encoded_shape)...)
        has_default = _decode_logical(reader)
        default = has_default ? _decode_logical(reader) : _NO_DEFAULT
        return LeafSchema(
            type;
            shape,
            default,
            required=_decode_logical(reader),
            nominal_id=_decode_logical(reader),
            units=_decode_logical(reader),
            ontology=_decode_logical(reader),
            owner=_decode_logical(reader),
            conservation=_decode_logical(reader),
            update_law=_decode_logical(reader),
            division_law=_decode_logical(reader),
            persistence=_decode_logical(reader),
            continuation=_decode_logical(reader),
            residency=_decode_logical(reader),
            codec=_decode_logical(reader),
        )
    elseif tag == 0x1b
        return BranchSchema(_decode_logical(reader))
    elseif tag == 0x1c
        return CapabilitySet(
            _decode_logical(reader);
            purity=_decode_logical(reader),
            idempotent=_decode_logical(reader),
            continuation_codec=_decode_logical(reader),
            replay_class=_decode_logical(reader),
        )
    elseif tag == 0x1d
        return TransferDeclaration(
            _decode_logical(reader),
            _decode_logical(reader);
            max_bytes=_decode_logical(reader),
            cadence=_decode_logical(reader),
            precision=_decode_logical(reader),
            synchronization=_decode_logical(reader),
        )
    end
    _fail(:logical_codec_tag, "unknown logical value tag"; tag)
end

function decode_logical_value(bytes::AbstractVector{UInt8})
    payload = Vector{UInt8}(bytes)
    length(payload) >= length(_LOGICAL_MAGIC) ||
        _fail(:logical_codec_truncated,
            "logical value payload omits its version header")
    payload[1:length(_LOGICAL_MAGIC)] == _LOGICAL_MAGIC ||
        _fail(:logical_codec_version,
            "logical value codec version is unsupported")
    reader = _LogicalReader(payload, length(_LOGICAL_MAGIC) + 1)
    value = _decode_logical(reader)
    reader.position == length(payload) + 1 ||
        _fail(:logical_codec_trailing_bytes,
            "logical value payload contains trailing bytes";
            remaining=length(payload) - reader.position + 1)
    value
end
