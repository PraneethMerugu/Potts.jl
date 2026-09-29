import KernelAbstractions
import LocalMath

function _localmath_stencil_witness(D::Int, array_type, backend)
    shape = D == 1 ? (6,) : D == 2 ? (4, 5) : D == 3 ? (4, 4, 4) :
        throw(ArgumentError("Cartesian stencil dimension must be 1, 2, or 3"))
    cells = D == 1 ? LocalMath.Space(only(shape)) : LocalMath.Space(shape)
    input = LocalMath.Field(cells, Float32)
    output = LocalMath.Field(cells, Float32)
    periodic_law, interior_law, reference = if D == 1
        periodic_law = LocalMath.@localmath i ∈ periodic(cells) begin
            output[i] = input[i - 1] + input[i + 1]
        end
        interior_law = LocalMath.@localmath i ∈ interior(cells, 1) begin
            output[i] = input[i - 1] + input[i + 1]
        end
        values = reshape(Float32.(1:prod(shape)), shape)
        periodic_reference = circshift(values, (1,)) + circshift(values, (-1,))
        periodic_law, interior_law, periodic_reference
    elseif D == 2
        periodic_law = LocalMath.@localmath (i, j) ∈ periodic(cells) begin
            output[i, j] = input[i - 1, j] + input[i + 1, j] +
                input[i, j - 1] + input[i, j + 1]
        end
        interior_law = LocalMath.@localmath (i, j) ∈ interior(cells, 1) begin
            output[i, j] = input[i - 1, j] + input[i + 1, j] +
                input[i, j - 1] + input[i, j + 1]
        end
        values = reshape(Float32.(1:prod(shape)), shape)
        periodic_reference = circshift(values, (1, 0)) +
            circshift(values, (-1, 0)) + circshift(values, (0, 1)) +
            circshift(values, (0, -1))
        periodic_law, interior_law, periodic_reference
    else
        periodic_law = LocalMath.@localmath (i, j, k) ∈ periodic(cells) begin
            output[i, j, k] = input[i - 1, j, k] + input[i + 1, j, k] +
                input[i, j - 1, k] + input[i, j + 1, k] +
                input[i, j, k - 1] + input[i, j, k + 1]
        end
        interior_law = LocalMath.@localmath (i, j, k) ∈ interior(cells, 1) begin
            output[i, j, k] = input[i - 1, j, k] + input[i + 1, j, k] +
                input[i, j - 1, k] + input[i, j + 1, k] +
                input[i, j, k - 1] + input[i, j, k + 1]
        end
        values = reshape(Float32.(1:prod(shape)), shape)
        periodic_reference = circshift(values, (1, 0, 0)) +
            circshift(values, (-1, 0, 0)) + circshift(values, (0, 1, 0)) +
            circshift(values, (0, -1, 0)) + circshift(values, (0, 0, 1)) +
            circshift(values, (0, 0, -1))
        periodic_law, interior_law, periodic_reference
    end
    input_values = reshape(Float32.(1:prod(shape)), shape)
    input_storage = array_type(input_values)
    periodic_storage = array_type(fill(-1f0, shape))
    periodic_prepared = LocalMath.@prepare (periodic_law; backend) begin
        input = input_storage
        output = periodic_storage
    end
    wait(LocalMath.execute!(periodic_prepared))
    periodic_result = Array(periodic_storage)
    periodic_result == reference || error("$(D)D periodic stencil mismatch")

    interior_storage = array_type(fill(-1f0, shape))
    interior_prepared = LocalMath.@prepare (interior_law; backend) begin
        input = input_storage
        output = interior_storage
    end
    wait(LocalMath.execute!(interior_prepared))
    interior_result = Array(interior_storage)
    interior_reference = fill(-1f0, shape)
    interior_indices = ntuple(axis -> 2:(shape[axis] - 1), D)
    interior_reference[interior_indices...] = reference[interior_indices...]
    interior_result == interior_reference ||
        error("$(D)D interior stencil mismatch")
    return (; periodic=vec(periodic_result), interior=vec(interior_result))
end

function _localmath_scatter_witness(
        width::Int, name::Symbol, array_type, backend)
    particles = LocalMath.Space(4)
    grid = LocalMath.Space(5)
    deposition = LocalMath.FixedRelation(particles => grid; degree = width)
    output = LocalMath.Field(grid, Float32)
    weights = ntuple(lane -> Float32(lane) / Float32(sum(1:width)), width)
    work = if width == 2
        LocalMath.@localmath p ∈ particles begin
            output[deposition(p)] +=
                (Float32(p) * weights[1], Float32(p) * weights[2])
        end
    else
        LocalMath.@localmath p ∈ particles begin
            output[deposition(p)] +=
                (Float32(p) * weights[1], Float32(p) * weights[2],
                 Float32(p) * weights[3])
        end
    end
    endpoints = Matrix{Int32}(undef, width, 4)
    for item in 1:4, lane in 1:width
        endpoints[lane, item] = Int32(mod1(item + lane - 1, 5))
    end
    result_storage = array_type(zeros(Float32, 5))
    endpoint_storage = array_type(endpoints)
    prepared = LocalMath.@prepare (work; backend) begin
        output = result_storage
        deposition = endpoint_storage
    end
    wait(LocalMath.execute!(prepared))
    reference = zeros(Float32, 5)
    for item in 1:4, lane in 1:width
        reference[endpoints[lane, item]] += Float32(item) * weights[lane]
    end
    result = Array(result_storage)
    result ≈ reference || error("authored $(name) mismatch")
    return result
end

function _localmath_graph_witness(array_type, backend)
    vertices = LocalMath.Space(4)
    edges = LocalMath.Space(3)
    endpoints_relation = LocalMath.FixedRelation(edges => vertices; degree = 2)
    vertex_value = LocalMath.Field(vertices, Float32)
    edge_value = LocalMath.Field(edges, Float32)
    inverse_value = LocalMath.Field(vertices, Float32)
    gathered = LocalMath.@localmath e ∈ edges begin
        endpoints_value = vertex_value[endpoints_relation(e)]
        edge_value[e] = endpoints_value[2] - endpoints_value[1]
    end
    endpoints = Int32[1 2 3; 2 3 4]
    vertex_storage = array_type(Float32[1, 4, 9, 16])
    edge_storage = array_type(zeros(Float32, 3))
    endpoint_storage = array_type(endpoints)
    gathered_prepared = LocalMath.@prepare (gathered; backend) begin
        vertex_value = vertex_storage
        edge_value = edge_storage
        endpoints_relation = endpoint_storage
    end
    wait(LocalMath.execute!(gathered_prepared))
    Array(edge_storage) == Float32[3, 5, 7] || error("authored graph gather mismatch")
    scattered = LocalMath.@localmath e ∈ edges begin
        inverse_value[endpoints_relation(e)] +=
            (edge_value[e], edge_value[e])
    end
    inverse_storage = array_type(zeros(Float32, 4))
    scattered_prepared = LocalMath.@prepare (scattered; backend) begin
        edge_value = edge_storage
        inverse_value = inverse_storage
        endpoints_relation = endpoint_storage
    end
    wait(LocalMath.execute!(scattered_prepared))
    Array(inverse_storage) == Float32[3, 8, 12, 7] ||
        error("authored graph inverse scatter mismatch")
    return (; forward = Array(edge_storage), inverse = Array(inverse_storage))
end

function _localmath_potts_proposal_witness(array_type, backend)
    proposals = LocalMath.Space(3)
    targets = LocalMath.Space(2)
    label = LocalMath.Field(proposals, Int32)
    volume = LocalMath.Field(proposals, Int32)
    energy = LocalMath.Field(proposals, Float32)
    winner = LocalMath.Field(targets, Int32)
    target = LocalMath.FixedRelation(proposals => targets; degree = 1)
    work = LocalMath.@localmath proposal ∈ proposals begin
        label_value = label[proposal]
        volume_value = volume[proposal]
        ordered_energy = label_value == Int32(1) ? 1.0f7 : 0.0f0
        ordered_energy += -1.0f7
        ordered_energy += Float32(volume_value)
        energy[proposal] = ordered_energy
        winner[target(proposal)] = resolve_to(;
            score = volume_value, payload = proposal,
            lower = Int32(1), upper = Int32(4),
            when = label_value != Int32(0))
    end
    label_values = Int32[1, 0, 1]
    volume_values = Int32[1, 3, 2]
    label_storage = array_type(label_values)
    volume_storage = array_type(volume_values)
    energy_storage = array_type(zeros(Float32, 3))
    winner_storage = array_type(fill(Int32(-1), 2))
    endpoints = reshape(Int32[1, 1, 2], 1, 3)
    target_storage = array_type(endpoints)
    prepared = LocalMath.@prepare (work; backend) begin
        label = label_storage
        volume = volume_storage
        energy = energy_storage
        winner = winner_storage
        target = target_storage
    end
    wait(LocalMath.execute!(prepared))
    energy_reference = map(eachindex(label_values)) do item
        value = label_values[item] == 1 ? 1.0f7 : 0.0f0
        value += -1.0f7
        value += volume_values[item]
        value
    end
    energy_result = Array(energy_storage)
    winner_result = Array(winner_storage)
    energy_result == energy_reference ||
        error("authored Potts Hamiltonian order mismatch")
    winner_result == Int32[1, 3] ||
        error("authored Potts resolution mismatch")
    return (; energy = energy_result, winner = winner_result,
        semantics = LocalMath.inspect(work))
end

function run_localmath_authored_domain_witness(
        array_type = Array; backend = KernelAbstractions.CPU())
    stencil1 = _localmath_stencil_witness(1, array_type, backend)
    stencil2 = _localmath_stencil_witness(2, array_type, backend)
    stencil3 = _localmath_stencil_witness(3, array_type, backend)
    cic = _localmath_scatter_witness(2, :cic, array_type, backend)
    tsc = _localmath_scatter_witness(3, :tsc, array_type, backend)
    graph = _localmath_graph_witness(array_type, backend)
    potts = _localmath_potts_proposal_witness(array_type, backend)
    return (; stencil1, stencil2, stencil3, cic, tsc, graph, potts)
end
