import KernelAbstractions
import LocalMath
import StructArrays

struct _LocalMathD2Q9Moments
    density::Float32
    squared_population_norm::Float32
end

const _LocalMath_D2Q9_VELOCITIES = (
    (0, 0), (1, 0), (0, 1), (-1, 0), (0, -1),
    (1, 1), (-1, 1), (-1, -1), (1, -1),
)

@inline function _localmath_d2q9_collision(source, equilibrium, omega)
    return ntuple(Val(9)) do lane
        value = source[lane]
        value - omega * (value - equilibrium[lane])
    end
end

@inline function _localmath_d2q9_moments(collided)
    density = collided[1] + collided[2] + collided[3] + collided[4] +
        collided[5] + collided[6] + collided[7] + collided[8] + collided[9]
    squared_population_norm = abs2(collided[1]) + abs2(collided[2]) +
        abs2(collided[3]) + abs2(collided[4]) + abs2(collided[5]) +
        abs2(collided[6]) + abs2(collided[7]) + abs2(collided[8]) +
        abs2(collided[9])
    return _LocalMathD2Q9Moments(density, squared_population_norm)
end

function _lw_d2q9_periodic_padding(source, nx::Int, ny::Int)
    padded = Array{Float32}(undef, nx + 2, ny + 2, 9)
    for lane in 1:9, padded_y in 1:(ny + 2), padded_x in 1:(nx + 2)
        x, y = mod1(padded_x - 1, nx), mod1(padded_y - 1, ny)
        cell = x + nx * (y - 1)
        padded[padded_x, padded_y, lane] = source[lane + 9 * (cell - 1)]
    end
    return padded
end

function _run_localmath_structured_average_witness(array_type, backend)
    nx, ny = 3, 2
    padded_values = reshape(Float32.(1:((nx + 2) * (ny + 2))),
        nx + 2, ny + 2)
    cells = LocalMath.Space((nx, ny))
    padded = LocalMath.Space(size(padded_values))
    source = LocalMath.Field(padded, Float32)
    output = LocalMath.Field(cells, Float32)
    neighbors = LocalMath.FixedRelation(cells => padded; degree = 5)
    endpoints = Matrix{Int32}(undef, 5, nx * ny)
    expected = zeros(Float32, nx * ny)
    for y in 1:ny, x in 1:nx
        item = x + nx * (y - 1)
        px, py = x + 1, y + 1
        coordinates = ((px, py), (px - 1, py), (px + 1, py),
            (px, py - 1), (px, py + 1))
        for lane in 1:5
            endpoints[lane, item] = LinearIndices(padded_values)[coordinates[lane]...]
        end
        expected[item] = sum(padded_values[coordinates[lane]...]
            for lane in 1:5) / 5f0
    end
    law = LocalMath.@localmath cell ∈ cells begin
        values = source[neighbors(cell)]
        output[cell] = (values[1] + values[2] + values[3] +
            values[4] + values[5]) / 5f0
    end
    source_storage = array_type(padded_values)
    output_storage = array_type(fill(-1f0, nx, ny))
    prepared = LocalMath.@prepare (law; backend) begin
        source = source_storage
        output = output_storage
        neighbors = array_type(endpoints)
    end
    wait(LocalMath.execute!(prepared))
    actual = vec(Array(output_storage))
    actual == expected || error("structured average witness mismatch")
    return (result = actual, reference = expected)
end

function run_localmath_d2q9_witness(
        array_type = Array; backend = KernelAbstractions.CPU())
    nx, ny = 4, 3
    cell_count = nx * ny
    cells = LocalMath.Space((nx, ny))
    padded = LocalMath.Space((nx + 2, ny + 2, 9))
    population_space = LocalMath.Space(9 * cell_count)
    source_field = LocalMath.Field(padded, Float32)
    moment_field = LocalMath.Field(cells, _LocalMathD2Q9Moments)
    population_field = LocalMath.Field(population_space, Float32)
    pull = LocalMath.FixedRelation(cells => padded; degree = 9)
    stream = LocalMath.FixedRelation(cells => population_space; degree = 9)
    pull_endpoints = Matrix{Int32}(undef, 9, cell_count)
    stream_endpoints = reshape(Int32.(1:(9 * cell_count)), 9, cell_count)
    padded_shape = (nx + 2, ny + 2, 9)
    for item in 1:cell_count, lane in 1:9
        x, y = mod1(item, nx), (item - 1) ÷ nx + 1
        dx, dy = _LocalMath_D2Q9_VELOCITIES[lane]
        px, py = mod1(x - dx, nx) + 1, mod1(y - dy, ny) + 1
        pull_endpoints[lane, item] = LinearIndices(padded_shape)[px, py, lane]
    end
    equilibrium = ntuple(lane -> Float32(lane) / 20f0, 9)
    omega = 0.75f0
    law = LocalMath.@localmath cell ∈ cells begin
        local_populations = source_field[pull(cell)]
        collided = _localmath_d2q9_collision(
            local_populations, equilibrium, omega)
        moment_field[cell] = _localmath_d2q9_moments(collided)
        population_field[stream(cell)] = collided
    end
    source = Float32[Float32(index % 17) / 7f0
        for index in 1:(9 * cell_count)]
    padded_values = _lw_d2q9_periodic_padding(source, nx, ny)
    expected = fill(Float32(NaN), length(source))
    expected_density = zeros(Float32, cell_count)
    expected_norm = zeros(Float32, cell_count)
    for item in 1:cell_count, lane in 1:9
        value = padded_values[pull_endpoints[lane, item]]
        collided = value - omega * (value - equilibrium[lane])
        expected[stream_endpoints[lane, item]] = collided
        expected_density[item] += collided
        expected_norm[item] += abs2(collided)
    end
    source_storage = array_type(padded_values)
    population_storage = array_type(fill(-1f0, length(source)))
    density_storage = array_type(fill(-1f0, nx, ny))
    norm_storage = array_type(fill(-1f0, nx, ny))
    moment_storage = StructArrays.StructArray{_LocalMathD2Q9Moments}((;
        density = density_storage, squared_population_norm = norm_storage))
    prepared = LocalMath.@prepare (law; backend, lease_capacity = 3) begin
        source_field = source_storage
        moment_field = moment_storage
        population_field = population_storage
        pull = array_type(pull_endpoints)
        stream = array_type(stream_endpoints)
    end
    wait(LocalMath.execute!(prepared))
    actual = Array(population_storage)
    actual_density = vec(Array(density_storage))
    actual_norm = vec(Array(norm_storage))
    actual == expected || error("D2Q9 population mismatch")
    actual_density == expected_density || error("D2Q9 density mismatch")
    actual_norm == expected_norm || error("D2Q9 norm mismatch")
    structured = _run_localmath_structured_average_witness(array_type, backend)
    return (name = :lbm_d2q9, result = actual, reference = expected,
        record_result = (density = actual_density,
            squared_population_norm = actual_norm), structured,
        semantics = LocalMath.inspect(law))
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_localmath_d2q9_witness()
