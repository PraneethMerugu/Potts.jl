import KernelAbstractions
import LocalMath
import StructArrays

struct _LocalMathParticleCellRecord
    cell::Int32
    particle::Int32
    mass::Int32
    x::Int32
    y::Int32
    z::Int32
end

@inline function _lw_particle_cell_aggregate(records)
    count = Int32(0)
    mass = Int32(0)
    for particle in records
        count += Int32(1)
        mass += particle[3]
    end
    return count, mass
end

const _LocalMathParticleCellTuple = Tuple{Int32,Int32,Int32,Int32,Int32,Int32}

function _lw_particle_cell_work(
        dims::NTuple{D, Int32}, particle_count::Int, maximum::Int;
        project::Bool,
    ) where {D}
    LM = LocalMath
    cell_count = prod(Int, dims)
    particles, cells = LM.Space(particle_count), LM.Space(cell_count)
    x, y, z = LM.Field(particles, Int32), LM.Field(particles, Int32), LM.Field(particles, Int32)
    mass, active = LM.Field(particles, Int32), LM.Field(particles, Bool)
    collection = LM.Collection(_LocalMathParticleCellTuple, particle_count)
    cell_mass, cell_count_field = LM.Field(cells,Int32), LM.Field(cells,Int32)
    particle_position = project ? LM.Field(particles,Int32) : nothing
    projection_mode = project ? :source_position : :none
    law = if D == 2
        LocalMath.@localmath begin
            @stage group(particle ∈ particles) begin
                cell = x[particle] + (y[particle] - Int32(1)) * dims[1]
                record = (cell, particle, mass[particle], x[particle],
                    y[particle], Int32(0))
                collection[particle] = bounded_collect(record; maximum=1,
                    group=cell, groups=cell_count, projection=projection_mode,
                    when=active[particle])
            end
            @stage aggregate(cell ∈ cells) begin
                records = bounded(collection[cell]; maximum=maximum)
                totals = _lw_particle_cell_aggregate(records)
                cell_count_field[cell] = totals[1]
                cell_mass[cell] = totals[2]
            end
        end
    else
        LocalMath.@localmath begin
            @stage group(particle ∈ particles) begin
                cell = x[particle] + (y[particle] - Int32(1)) * dims[1] +
                    (z[particle] - Int32(1)) * dims[1] * dims[2]
                record = (cell, particle, mass[particle], x[particle],
                    y[particle], z[particle])
                collection[particle] = bounded_collect(record; maximum=1,
                    group=cell, groups=cell_count, projection=projection_mode,
                    when=active[particle])
            end
            @stage aggregate(cell ∈ cells) begin
                records = bounded(collection[cell]; maximum=maximum)
                totals = _lw_particle_cell_aggregate(records)
                cell_count_field[cell] = totals[1]
                cell_mass[cell] = totals[2]
            end
        end
    end
    if project
        projection = LocalMath.@localmath particle ∈ particles begin
            particle_position[particle] =
                source_position(collection, particle; lane=1)
        end
        law = LM.sequence(law, projection)
    end
    return (; law, particles,
        x,y,z,mass,active,collection,cell_mass,cell_count=cell_count_field,particle_position)
end

function _lw_particle_cell_oracle(
        dims::NTuple{D, Int32},
        positions::Vector{NTuple{D, Int32}},
        active::Vector{Bool},
        masses::Vector{Int32},
    ) where {D}
    cell_count = prod(Int, dims)
    records = _LocalMathParticleCellRecord[]
    for particle in eachindex(positions)
        active[particle] || continue
        position = positions[particle]
        cell = Int32(LinearIndices(Tuple(Int.(dims)))[Tuple(Int.(position))...])
        z = D == 2 ? Int32(0) : position[3]
        push!(records, _LocalMathParticleCellRecord(
            cell, Int32(particle), masses[particle],
            position[1], position[2], z,
        ))
    end
    sort!(records; by = record -> (record.cell, record.particle))
    directory = fill(Int32(1), cell_count + 1)
    cursor = 1
    cell_mass = zeros(Int32, cell_count)
    cell_occupancy = zeros(Int32, cell_count)
    for cell in 1:cell_count
        directory[cell] = Int32(cursor)
        while cursor <= length(records) && records[cursor].cell == cell
            cell_mass[cell] += records[cursor].mass
            cell_occupancy[cell] += Int32(1)
            cursor += 1
        end
    end
    directory[end] = Int32(cursor)
    source_item = getfield.(records, :particle)
    source_lane = fill(Int32(1), length(records))
    source_position = zeros(Int32, length(positions))
    for (position, particle) in pairs(source_item)
        source_position[particle] = Int32(position)
    end
    return (;
        records,
        count = Int32[length(records)],
        directory,
        source_item,
        source_lane,
        source_position,
        cell_mass,
        cell_occupancy,
    )
end

_lw_particle_host_component(array::AbstractArray) = Array(array)
function _lw_particle_host_component(array::StructArrays.StructArray{T}) where {T}
    components = StructArrays.components(array)
    host = components isa NamedTuple ?
        NamedTuple{keys(components)}(map(
            _lw_particle_host_component, values(components)
        )) :
        map(_lw_particle_host_component, components)
    return StructArrays.StructArray{T}(host)
end

function _lw_particle_host_records(records::StructArrays.StructArray{T}) where {T}
    return collect(_lw_particle_host_component(records))
end

function _lw_particle_record_tuples(records)
    return [
        record isa Tuple ? record : (
            record.cell, record.particle, record.mass,
            record.x, record.y, record.z,
        )
        for record in records
    ]
end

function _lw_particle_cell_prepare(
        array_type,
        backend,
        dims::NTuple{D, Int32},
        positions::Vector{NTuple{D, Int32}},
        active::Vector{Bool},
        masses::Vector{Int32},
        maximum::Int;
        project::Bool,
        sentinel::Int32 = Int32(-1),
    ) where {D}
    LM = LocalMath
    model = _lw_particle_cell_work(
        dims, length(positions), maximum; project
    )
    cell_count = prod(Int, dims)
    storage = (
        x = array_type(Int32[position[1] for position in positions]),
        y = array_type(Int32[position[2] for position in positions]),
        active = array_type(active),
        mass = array_type(masses),
        cell_mass = array_type(fill(sentinel, cell_count)),
        cell_count = array_type(fill(sentinel, cell_count)),
    )
    if D == 3
        storage = merge(storage, (
            z = array_type(Int32[position[3] for position in positions]),
        ))
    end
    if project
        storage = merge(storage, (
            particle_position = array_type(fill(sentinel, length(positions))),
        ))
    end
    bindings = Any[model.x => storage.x, model.y => storage.y]
    D == 3 && push!(bindings, model.z => storage.z)
    append!(bindings, Any[
        model.mass => storage.mass, model.active => storage.active,
        model.cell_mass => storage.cell_mass,
        model.cell_count => storage.cell_count,
    ])
    project && push!(bindings,
        model.particle_position => storage.particle_position)
    push!(bindings, model.collection => LM.Allocate())
    prepared = LM.prepare(model.law, bindings...; backend)
    compacted = LM.storage(prepared, model.collection)
    return prepared.plan, prepared, merge(storage, (; particles=compacted))
end

function _lw_particle_cell_run_case(
        array_type,
        backend,
        name::Symbol,
        dims::NTuple{D, Int32},
        positions::Vector{NTuple{D, Int32}},
        active::Vector{Bool},
        masses::Vector{Int32};
        maximum::Int,
        project::Bool,
    ) where {D}
    LM = LocalMath
    oracle = _lw_particle_cell_oracle(dims, positions, active, masses)
    plan, prepared, storage = _lw_particle_cell_prepare(
        array_type, backend, dims, positions, active, masses, maximum; project
    )
    wait(LM.execute!(prepared))
    live_count = Int(only(Array(storage.particles.count)))
    actual_records = _lw_particle_host_records(storage.particles.records)[
        1:live_count
    ]
    actual = (
        records = actual_records,
        count = Array(storage.particles.count),
        directory = Array(storage.particles.segment_starts),
        source_item = Array(storage.particles.source_item)[1:live_count],
        source_lane = Array(storage.particles.source_lane)[1:live_count],
        source_position = storage.particles.source_position === nothing ?
            nothing : Array(storage.particles.source_position),
        cell_mass = Array(storage.cell_mass),
        cell_occupancy = Array(storage.cell_count),
        projected_position = project ? Array(storage.particle_position) : nothing,
    )
    _lw_particle_record_tuples(actual.records) ==
        _lw_particle_record_tuples(oracle.records) ||
        error("$name compacted record oracle mismatch")
    actual.count == oracle.count || error("$name compacted count mismatch")
    actual.directory == oracle.directory ||
        error("$name compacted segment directory mismatch")
    actual.source_item == oracle.source_item ||
        error("$name compacted source-item provenance mismatch")
    actual.source_lane == oracle.source_lane ||
        error("$name compacted source-lane provenance mismatch")
    actual.cell_mass == oracle.cell_mass ||
        error("$name per-cell mass mismatch")
    actual.cell_occupancy == oracle.cell_occupancy ||
        error("$name per-cell count mismatch")
    if project
        actual.source_position == oracle.source_position ||
            error("$name source-position projection mismatch")
        actual.projected_position == oracle.source_position ||
            error("$name sequenced source-position result mismatch")
    else
        actual.source_position === nothing ||
            error("$name allocated an undemanded source-position projection")
    end
    any(==(Int32(0)), oracle.cell_occupancy) ||
        error("$name lacks an empty-cell witness")
    any(==(Int32(maximum)), oracle.cell_occupancy) ||
        error("$name lacks a full-cell witness")
    any(==(Int32(1)), oracle.cell_occupancy) ||
        error("$name lacks a sparse-cell witness")

    return (
        name,
        dimension = D,
        dims,
        project,
        records = _lw_particle_record_tuples(actual.records),
        count = Tuple(actual.count),
        directory = Tuple(actual.directory),
        source_item = Tuple(actual.source_item),
        source_lane = Tuple(actual.source_lane),
        source_position = actual.source_position === nothing ? nothing :
            Tuple(actual.source_position),
        cell_mass = Tuple(actual.cell_mass),
        cell_occupancy = Tuple(actual.cell_occupancy),
    )
end

function _lw_particle_cell_invalid_bound(
        array_type,
        backend,
        dims::NTuple{D, Int32},
        positions::Vector{NTuple{D, Int32}},
        active::Vector{Bool},
        masses::Vector{Int32},
    ) where {D}
    LM = LocalMath
    plan, prepared, storage = _lw_particle_cell_prepare(
        array_type, backend, dims, positions, active, masses, 2;
        project = true,
        sentinel = Int32(707),
    )
    error_value = try
        wait(LM.execute!(prepared))
        nothing
    catch error
        error
    end
    error_value isa LM.LocalMathValidationError ||
        error("particle-cell invalid occupancy was not rejected")
    cell_count = prod(Int, dims)
    Array(storage.cell_mass) == fill(Int32(707), cell_count) ||
        error("particle-cell invalid occupancy published mass")
    Array(storage.cell_count) == fill(Int32(707), cell_count) ||
        error("particle-cell invalid occupancy published count")
    Array(storage.particle_position) == fill(Int32(707), length(positions)) ||
        error("particle-cell invalid occupancy published projection consumer")
    return (
        port = :particles,
        expected = (maximum_group_occupancy = Int32(2),),
        actual = (failure_class=:group_occupancy, group=Int32(1), occupancy=Int32(3)),
    )
end

function run_localmath_compacted_particle_cells_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    dims_2d = (Int32(3), Int32(2))
    positions_2d = Tuple{Int32, Int32}[
        (1, 1), (3, 2), (2, 1), (1, 1),
        (2, 2), (1, 1), (1, 2), (3, 2),
    ]
    active_2d = Bool[true, false, true, true, true, true, true, true]
    masses_2d = Int32[2, 99, 3, 5, 7, 17, 11, 13]
    case_2d = _lw_particle_cell_run_case(
        array_type, backend, :particle_cells_2d,
        dims_2d, positions_2d, active_2d, masses_2d;
        maximum = 3,
        project = true,
    )

    dims_3d = (Int32(2), Int32(2), Int32(2))
    positions_3d = Tuple{Int32, Int32, Int32}[
        (1, 1, 1), (2, 1, 1), (1, 2, 1), (1, 1, 1), (2, 2, 2),
        (1, 1, 2), (1, 1, 1), (2, 1, 2), (1, 2, 2), (2, 2, 1),
    ]
    active_3d = Bool[
        true, true, false, true, true, true, true, false, true, true,
    ]
    masses_3d = Int32[1, 2, 99, 4, 5, 6, 7, 99, 9, 10]
    case_3d = _lw_particle_cell_run_case(
        array_type, backend, :particle_cells_3d,
        dims_3d, positions_3d, active_3d, masses_3d;
        maximum = 3,
        project = false,
    )

    invalid_2d = _lw_particle_cell_invalid_bound(
        array_type, backend,
        dims_2d, positions_2d, active_2d, masses_2d,
    )
    invalid_3d = _lw_particle_cell_invalid_bound(
        array_type, backend,
        dims_3d, positions_3d, active_3d, masses_3d,
    )
    return (; cases = (case_2d, case_3d),
        diagnostics = (invalid_2d, invalid_3d))
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    println(run_localmath_compacted_particle_cells_witness())
end
