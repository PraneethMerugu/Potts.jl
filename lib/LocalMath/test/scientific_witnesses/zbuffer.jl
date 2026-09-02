import KernelAbstractions
import LocalMath
import StructArrays

struct _ZBufferFragment
    color::UInt32
    depth::Int32
    covered::Bool
    identity::UInt32
end

function run_localmath_zbuffer_witness(
        array_type = Array; backend = KernelAbstractions.CPU())
    pixel_endpoints = reshape(Int32[1, 1, 2, 2, 3], 1, 5)
    fragments = LocalMath.Space(5)
    pixels = LocalMath.Space(4)
    pixel_relation = LocalMath.FixedRelation(
        fragments => pixels; degree = 1)
    fragment_data = LocalMath.Field(fragments, _ZBufferFragment)
    output = LocalMath.Field(pixels, UInt32)
    law = LocalMath.@localmath fragment ∈ fragments begin
        value = fragment_data[fragment]
        output[pixel_relation(fragment)] = resolve_to(;
            score = value.depth,
            tie = value.identity,
            payload = value.color,
            lower = Int32(-100), upper = Int32(100),
            onempty = UInt32(0), when = value.covered)
    end
    depth_values = Int32[-2, -2, -1, -1, 4]
    color_values = UInt32[0x11, 0x22, 0x33, 0x44, 0x55]
    covered_values = Bool[true, true, true, false, true]
    identity_values = UInt32[50, 10, 30, 20, 40]
    expected = UInt32[0x22, 0x33, 0x55, 0x00]
    fragments_storage = StructArrays.StructArray(_ZBufferFragment[
        _ZBufferFragment(color_values[index], depth_values[index],
            covered_values[index], identity_values[index])
        for index in eachindex(color_values)
    ])
    output_storage = array_type(fill(UInt32(0xff), 4))
    prepared = LocalMath.@prepare (law; backend, lease_capacity = 2) begin
        fragment_data = allocate(fragments_storage)
        output = output_storage
        pixel_relation = array_type(pixel_endpoints)
    end
    wait(LocalMath.execute!(prepared))
    actual = Array(output_storage)
    actual == expected || error("z-buffer witness mismatch")
    semantics = LocalMath.inspect(law)
    return (name = :zbuffer, result = actual, reference = expected, semantics)
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_localmath_zbuffer_witness()
