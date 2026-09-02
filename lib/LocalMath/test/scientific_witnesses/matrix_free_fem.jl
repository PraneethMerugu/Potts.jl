import KernelAbstractions
import LocalMath

function run_localmath_matrix_free_fem_witness(
        array_type = Array; backend = KernelAbstractions.CPU())
    endpoints = Int32[1 2 3; 2 3 5; 4 4 6; 5 6 7]
    elements = LocalMath.Space(3)
    nodes = LocalMath.Space(8)
    values = LocalMath.Field(nodes, Float32)
    residual = LocalMath.Field(nodes, Float32)
    incidence = LocalMath.FixedRelation(elements => nodes; degree = 4)
    law = LocalMath.@localmath element ∈ elements begin
        nodal_values = values[incidence(element)]
        residual[incidence(element)] += (
            nodal_values[1] * 1f0,
            nodal_values[2] * 2f0,
            nodal_values[3] * 3f0,
            nodal_values[4] * 4f0,
        )
    end

    global_values = Float32[1, 2, 3, 4, 5, 6, 7, 0]
    expected = fill(0f0, 8)
    for item in 1:3, lane in 1:4
        expected[endpoints[lane, item]] +=
            global_values[endpoints[lane, item]] * Float32(lane)
    end
    value_storage = array_type(global_values)
    residual_storage = array_type(zeros(Float32, 8))
    prepared = LocalMath.@prepare (law; backend, lease_capacity = 2) begin
        values = value_storage
        residual = residual_storage
        incidence = array_type(endpoints)
    end
    wait(LocalMath.execute!(prepared))
    actual = Array(residual_storage)
    actual == expected || error("matrix-free FEM witness mismatch")
    semantics = LocalMath.inspect(law)
    return (name = :matrix_free_fem, result = actual, reference = expected,
        semantics)
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_localmath_matrix_free_fem_witness()
