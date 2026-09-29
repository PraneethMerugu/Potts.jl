import KernelAbstractions
import LocalMath
import StructArrays

const _LocalMath_DEM_MAXIMUM_NEIGHBORS = 4
const _LocalMath_DEM_PARTICLE_COUNT = 5
const _LocalMath_DEM_GROUP_COUNT = 3
const _LocalMath_DEM_CONTACT_CAPACITY = 10

"""One exact narrow-phase contact retained from a bounded DEM broad phase."""
struct _LocalMathDEMContact
    cell::Int32
    key::UInt32
    identity::UInt32
    first::Int32
    second::Int32
    squared_distance::Float32
end

struct _LocalMathDEMContactFilter{D}
    cutoff_squared::Float32
    particle_count::Int32
end

function _lw_dem_contact_filter(dimension::Int, cutoff_squared::Float32)
    dimension in (2, 3) || throw(ArgumentError(
        "the DEM contact witness supports only two or three dimensions"
    ))
    return _LocalMathDEMContactFilter{dimension}(
        cutoff_squared, Int32(_LocalMath_DEM_PARTICLE_COUNT)
    )
end

@inline function _lw_dem_contact_value(
        operation::_LocalMathDEMContactFilter{D}, item::Int32, cell::Int32,
        lane::Int,
        x_first, y_first, z_first, neighbor,
        neighbor_x, neighbor_y, neighbor_z,
    ) where {D}
    owns_pair = neighbor_x.present && item < neighbor <= operation.particle_count
    x_second = owns_pair ? something(neighbor_x.value) : x_first
    y_second = owns_pair ? something(neighbor_y.value) : y_first
    dx = x_second - x_first
    dy = y_second - y_first
    squared_distance = dx * dx + dy * dy
    if D == 3
        z_second = owns_pair ? something(neighbor_z.value) : z_first
        dz = z_second - z_first
        squared_distance += dz * dz
    end
    record = (
        cell,
        UInt32(neighbor),
        UInt32((item - Int32(1)) * operation.particle_count + neighbor),
        item,
        neighbor,
        squared_distance,
    )
    return record, owns_pair && squared_distance <= operation.cutoff_squared
end

struct _LocalMathDEMOrder end
@inline (::_LocalMathDEMOrder)(record) = record[2]
struct _LocalMathDEMIdentity end
@inline (::_LocalMathDEMIdentity)(record) = record[3]

function _lw_dem_case(dimension::Int, case_name::Symbol)
    cutoff_squared = case_name === :empty ? Float32(0) :
        case_name === :full ? Float32(8) :
        case_name === :filter ? Float32(1.5625) :
        throw(ArgumentError("unknown DEM witness case :$case_name"))
    # Every unordered pair appears exactly once, but deliberately not in
    # canonical partner order. Zero is the inactive broad-phase sentinel.
    neighbors = reshape(Int32[
        5, 2, 4, 3,
        5, 4, 3, 0,
        5, 4, 0, 0,
        5, 0, 0, 0,
        0, 0, 0, 0,
    ], _LocalMath_DEM_MAXIMUM_NEIGHBORS, _LocalMath_DEM_PARTICLE_COUNT)
    return (
        dimension,
        case_name,
        cutoff_squared,
        x = Float32[0, 0.75, 2, 0.25, 1.5],
        y = Float32[0, 0, 0, 1, 1],
        z = Float32[0, 0.25, 0, 1, 0.5],
        cell = Int32[2, 1, 2, 1, 3],
        neighbors,
    )
end

const _LocalMathDEMContactTuple = Tuple{
    Int32,UInt32,UInt32,Int32,Int32,Float32,
}

@inline function _lw_dem_oracle_precedes(left, right)
    left_record = left.record
    right_record = right.record
    left_record.cell != right_record.cell &&
        return left_record.cell < right_record.cell
    left_record.key != right_record.key &&
        return left_record.key < right_record.key
    left_record.identity != right_record.identity &&
        return left_record.identity < right_record.identity
    return left.linear_position < right.linear_position
end

function _lw_dem_oracle(case)
    entries = NamedTuple[]
    for item in 1:_LocalMath_DEM_PARTICLE_COUNT
        for lane in 1:_LocalMath_DEM_MAXIMUM_NEIGHBORS
            neighbor = case.neighbors[lane, item]
            item < neighbor <= _LocalMath_DEM_PARTICLE_COUNT || continue
            dx = case.x[neighbor] - case.x[item]
            dy = case.y[neighbor] - case.y[item]
            squared_distance = dx * dx + dy * dy
            if case.dimension == 3
                dz = case.z[neighbor] - case.z[item]
                squared_distance += dz * dz
            end
            squared_distance <= case.cutoff_squared || continue
            record = _LocalMathDEMContact(
                case.cell[item],
                UInt32(neighbor),
                UInt32((item - 1) * _LocalMath_DEM_PARTICLE_COUNT + neighbor),
                Int32(item),
                neighbor,
                squared_distance,
            )
            push!(entries, (
                record,
                item = Int32(item),
                lane = Int32(lane),
                linear_position = Int32(
                    lane + _LocalMath_DEM_MAXIMUM_NEIGHBORS * (item - 1)
                ),
            ))
        end
    end

    # A direct stable insertion order is intentionally used instead of any
    # production ordering descriptor, extractor, or compacted helper.
    for index in 2:length(entries)
        entry = entries[index]
        position = index
        while position > 1 &&
                _lw_dem_oracle_precedes(entry, entries[position - 1])
            entries[position] = entries[position - 1]
            position -= 1
        end
        entries[position] = entry
    end

    directory = Vector{Int32}(undef, _LocalMath_DEM_GROUP_COUNT + 1)
    directory[1] = Int32(1)
    live = 0
    for group in 1:_LocalMath_DEM_GROUP_COUNT
        for entry in entries
            live += entry.record.cell == group
        end
        directory[group + 1] = Int32(live + 1)
    end
    return (
        records = _LocalMathDEMContact[entry.record for entry in entries],
        count = Int32(length(entries)),
        directory,
        source_item = Int32[entry.item for entry in entries],
        source_lane = Int32[entry.lane for entry in entries],
    )
end

function _lw_dem_host_records(storage, count::Int)
    components = StructArrays.components(storage.records)
    host_components = map(Array, components)
    records = StructArrays.StructArray{_LocalMathDEMContactTuple}(host_components)
    return map(collect(records)[1:count]) do record
        _LocalMathDEMContact(record...)
    end
end

function _lw_dem_snapshot(storage)
    count = Int(only(Array(storage.count)))
    return (
        records = _lw_dem_host_records(storage, count),
        count = Int32(count),
        directory = Array(storage.segment_starts),
        source_item = Array(storage.source_item)[1:count],
        source_lane = Array(storage.source_lane)[1:count],
    )
end

function _lw_dem_require(condition::Bool, message::AbstractString)
    condition || error(message)
    return nothing
end

function _lw_dem_expected_count(dimension::Int, case_name::Symbol)
    case_name === :empty && return Int32(0)
    case_name === :full && return Int32(10)
    dimension == 2 && case_name === :filter && return Int32(7)
    dimension == 3 && case_name === :filter && return Int32(2)
    error("missing DEM witness expected count")
end

function _lw_dem_check(case, storage, actual, expected)
    label = "$(case.dimension)D $(case.case_name) DEM contact case"
    _lw_dem_require(
        actual.count == _lw_dem_expected_count(case.dimension, case.case_name),
        "$label retained the wrong number of contacts",
    )
    _lw_dem_require(actual.count == expected.count, "$label count mismatch")
    _lw_dem_require(actual.records == expected.records, "$label record mismatch")
    _lw_dem_require(
        actual.directory == expected.directory, "$label directory mismatch"
    )
    _lw_dem_require(
        actual.source_item == expected.source_item,
        "$label source-item provenance mismatch",
    )
    _lw_dem_require(
        actual.source_lane == expected.source_lane,
        "$label source-lane provenance mismatch",
    )
    _lw_dem_require(
        storage.source_position === nothing,
        "$label unexpectedly allocated inverse provenance",
    )
    return nothing
end

function _lw_dem_run_case(array_type, backend, dimension::Int, case_name::Symbol)
    case = _lw_dem_case(dimension, case_name)
    expected = _lw_dem_oracle(case)
    source = LocalMath.Space(_LocalMath_DEM_PARTICLE_COUNT)
    neighbors = LocalMath.FixedRelation(
        source => source; degree = _LocalMath_DEM_MAXIMUM_NEIGHBORS,
    )
    x = LocalMath.Field(source, Float32)
    y = LocalMath.Field(source, Float32)
    z = LocalMath.Field(source, Float32)
    cell = LocalMath.Field(source, Int32)
    contacts = LocalMath.Collection(
        _LocalMathDEMContactTuple, _LocalMath_DEM_CONTACT_CAPACITY,
    )
    filter = _lw_dem_contact_filter(case.dimension, case.cutoff_squared)
    ordering = LocalMath.canonical_by(
        _LocalMathDEMOrder(), _LocalMathDEMIdentity())
    law = LocalMath.@localmath item ∈ source begin
        neighbor = indices(x[neighbors(item)])
        neighbor_x = samples(x[neighbors(item)])
        neighbor_y = samples(y[neighbors(item)])
        neighbor_z = samples(z[neighbors(item)])
        contact_1 = _lw_dem_contact_value(filter, item, cell[item], 1,
            x[item], y[item], z[item], neighbor[1],
            neighbor_x[1], neighbor_y[1], neighbor_z[1])
        contact_2 = _lw_dem_contact_value(filter, item, cell[item], 2,
            x[item], y[item], z[item], neighbor[2],
            neighbor_x[2], neighbor_y[2], neighbor_z[2])
        contact_3 = _lw_dem_contact_value(filter, item, cell[item], 3,
            x[item], y[item], z[item], neighbor[3],
            neighbor_x[3], neighbor_y[3], neighbor_z[3])
        contact_4 = _lw_dem_contact_value(filter, item, cell[item], 4,
            x[item], y[item], z[item], neighbor[4],
            neighbor_x[4], neighbor_y[4], neighbor_z[4])
        contacts[item] = bounded_collect((
                contact_1[1], contact_2[1], contact_3[1], contact_4[1],
            ); maximum=4, group=cell[item], groups=_LocalMath_DEM_GROUP_COUNT,
            order=ordering,
            when=(contact_1[2], contact_2[2], contact_3[2], contact_4[2]))
    end
    neighbor_counts = Int32[
        count(!=(Int32(0)), @view(case.neighbors[:, item]))
        for item in 1:_LocalMath_DEM_PARTICLE_COUNT
    ]
    storage = (
        x = array_type(case.x),
        y = array_type(case.y),
        z = array_type(case.z),
        cell = array_type(case.cell),
        neighbors = array_type(case.neighbors),
    )
    neighbor_storage = (;
        endpoints=storage.neighbors,
        counts=array_type(neighbor_counts),
    )
    prepared = LocalMath.@prepare (law; backend) begin
        x = storage.x
        y = storage.y
        z = storage.z
        cell = storage.cell
        neighbors = neighbor_storage
        contacts = allocate()
    end
    wait(LocalMath.execute!(prepared))
    contact_storage = LocalMath.storage(prepared, contacts)
    actual = _lw_dem_snapshot(contact_storage)
    _lw_dem_check(case, contact_storage, actual, expected)
    return (
        dimension,
        case = case_name,
        count = actual.count,
        records = Tuple(actual.records),
        directory = Tuple(actual.directory),
        source_item = Tuple(actual.source_item),
        source_lane = Tuple(actual.source_lane),
    )
end

"""
    run_localmath_compacted_dem_contacts_witness(array_type=Array; backend=CPU())

Run bounded 2D and 3D DEM broad-phase filtering through the production
LocalMath KernelAbstractions execution path. Each dimension covers empty,
full, and distance-filtered contact sets against an independent scalar oracle.
"""
function run_localmath_compacted_dem_contacts_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    cases = Tuple(
        _lw_dem_run_case(array_type, backend, dimension, case_name)
        for dimension in (2, 3)
        for case_name in (:empty, :full, :filter)
    )
    return (; name = :compacted_dem_contacts, cases)
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(run_localmath_compacted_dem_contacts_witness())
end
