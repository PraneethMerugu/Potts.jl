import KernelAbstractions
import LocalMath
import StructArrays

struct _CompactedActiveFEMRecord
    source_element::Int32
    active_ordinal::Int32
    refinement_level::Int32
    node_1::Int32
    node_2::Int32
    node_3::Int32
    node_4::Int32
    coefficient::Float32
end

const _CompactedActiveFEMTuple = Tuple{Int32,Int32,Int32,Int32,Int32,Int32,
    Int32,Float32,Float32}

@inline function _compacted_active_fem_measure(
        x1, y1, x2, y2, x3, y3, ::Val{2})
    ax = x2 - x1
    ay = y2 - y1
    bx = x3 - x1
    by = y3 - y1
    return abs(ax * by - bx * ay)
end

@inline function _compacted_active_fem_measure(
        x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, ::Val{3})
    ax, ay, az = x2 - x1, y2 - y1, z2 - z1
    bx, by, bz = x3 - x1, y3 - y1, z3 - z1
    cx, cy, cz = x4 - x1, y4 - y1, z4 - z1
    return abs(ax * (by * cz - bz * cy) -
        ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx))
end

function _compacted_active_fem_fixture(::Val{2})
    return (
        dimension = 2,
        x = Float32[0, 2, 0, 2, 4, 4],
        y = Float32[0, 0, 1, 2, 0, 2],
        z = zeros(Float32, 6),
        element_nodes = Int32[
            1 2 2 4
            2 4 5 5
            3 3 4 6
        ],
        refinement_level = Int32[0, 1, 1, 2],
        coefficient = Float32[1, 2, 3, 4],
    )
end

function _compacted_active_fem_fixture(::Val{3})
    return (
        dimension = 3,
        x = Float32[0, 1, 0, 0, 1, 1],
        y = Float32[0, 0, 1, 0, 1, 0],
        z = Float32[0, 0, 0, 1, 0, 1],
        element_nodes = Int32[
            1 1 2
            2 2 3
            3 5 5
            4 6 6
        ],
        refinement_level = Int32[0, 1, 2],
        coefficient = Float32[1, 3, 2],
    )
end

function _compacted_active_fem_masks(dimension::Int)
    count = dimension == 2 ? 4 : 3
    masked = dimension == 2 ?
        Bool[false, true, true, false] : Bool[true, false, true]
    return (
        empty = fill(false, count),
        full = fill(true, count),
        masked = masked,
    )
end

function _compacted_active_fem_record(
        fixture, item::Integer, active_ordinal::Integer
    )
    node_4 = fixture.dimension == 3 ? fixture.element_nodes[4, item] : Int32(0)
    return _CompactedActiveFEMRecord(
        Int32(item),
        Int32(active_ordinal),
        fixture.refinement_level[item],
        fixture.element_nodes[1, item],
        fixture.element_nodes[2, item],
        fixture.element_nodes[3, item],
        node_4,
        fixture.coefficient[item],
    )
end

function _compacted_active_fem_scalar_quantity(fixture, item::Integer)
    nodes = @view fixture.element_nodes[:, item]
    x_1, y_1, z_1 = fixture.x[nodes[1]], fixture.y[nodes[1]], fixture.z[nodes[1]]
    a_x = fixture.x[nodes[2]] - x_1
    a_y = fixture.y[nodes[2]] - y_1
    b_x = fixture.x[nodes[3]] - x_1
    b_y = fixture.y[nodes[3]] - y_1
    measure = if fixture.dimension == 2
        abs(a_x * b_y - b_x * a_y)
    else
        a_z = fixture.z[nodes[2]] - z_1
        b_z = fixture.z[nodes[3]] - z_1
        c_x = fixture.x[nodes[4]] - x_1
        c_y = fixture.y[nodes[4]] - y_1
        c_z = fixture.z[nodes[4]] - z_1
        abs(
            a_x * (b_y * c_z - b_z * c_y) -
            a_y * (b_x * c_z - b_z * c_x) +
            a_z * (b_x * c_y - b_y * c_x),
        )
    end
    return fixture.coefficient[item] * measure
end

function _compacted_active_fem_oracle(fixture, active_element)
    source_item = Int32[
        item for item in eachindex(active_element) if active_element[item]
    ]
    records = [
        _compacted_active_fem_record(fixture, item, active_ordinal)
        for (active_ordinal, item) in enumerate(source_item)
    ]
    quantities = Float32[
        _compacted_active_fem_scalar_quantity(fixture, item)
        for item in source_item
    ]
    directory = Int32[
        min(group, length(records) + 1)
        for group in 1:(length(active_element) + 1)
    ]
    return (
        count = Int32[length(records)],
        records,
        source_item,
        source_lane = fill(Int32(1), length(records)),
        directory,
        quantities,
    )
end

function _compacted_active_fem_ordinals(active_element)
    active_ordinal = zeros(Int32, length(active_element))
    ordinal = Int32(0)
    for item in eachindex(active_element)
        active_element[item] || continue
        ordinal += Int32(1)
        active_ordinal[item] = ordinal
    end
    return active_ordinal
end

function _compacted_active_fem_work(fixture, active_element)
    LM = LocalMath
    dimension = fixture.dimension
    element_count = length(active_element)
    node_count = length(fixture.x)
    elements, nodes = LM.Space(element_count), LM.Space(node_count)
    connectivity = LM.FixedRelation(elements => nodes; degree = dimension + 1)
    x, y, z = LM.Field(nodes, Float32), LM.Field(nodes, Float32), LM.Field(nodes, Float32)
    ordinal, level = LM.Field(elements, Int32), LM.Field(elements, Int32)
    coefficient, active = LM.Field(elements, Float32), LM.Field(elements, Bool)
    collection = LM.Collection(_CompactedActiveFEMTuple, element_count)
    output = LM.Field(elements, Float32)
    law = if dimension == 2
        LocalMath.@localmath begin
            @stage compact(element ∈ elements) begin
                node = indices(x[connectivity(element)])
                xs = x[connectivity(element)]
                ys = y[connectivity(element)]
                measure = _compacted_active_fem_measure(
                    xs[1], ys[1], xs[2], ys[2], xs[3], ys[3], Val(2))
                record = (element, ordinal[element], level[element],
                    node[1], node[2], node[3], Int32(0), coefficient[element],
                    coefficient[element] * measure)
                collection[element] = bounded_collect(record; maximum=1,
                    group=ordinal[element], groups=element_count,
                    when=active[element])
            end
            @stage apply(element ∈ elements; prefix=count(collection)) begin
                records = bounded(collection[element]; maximum=1)
                output[element] = records[1][9]
            end
        end
    else
        LocalMath.@localmath begin
            @stage compact(element ∈ elements) begin
                node = indices(x[connectivity(element)])
                xs = x[connectivity(element)]
                ys = y[connectivity(element)]
                zs = z[connectivity(element)]
                measure = _compacted_active_fem_measure(
                    xs[1], ys[1], zs[1], xs[2], ys[2], zs[2],
                    xs[3], ys[3], zs[3], xs[4], ys[4], zs[4], Val(3))
                record = (element, ordinal[element], level[element],
                    node[1], node[2], node[3], node[4], coefficient[element],
                    coefficient[element] * measure)
                collection[element] = bounded_collect(record; maximum=1,
                    group=ordinal[element], groups=element_count,
                    when=active[element])
            end
            @stage apply(element ∈ elements; prefix=count(collection)) begin
                records = bounded(collection[element]; maximum=1)
                output[element] = records[1][9]
            end
        end
    end
    return (; law, elements, connectivity, x, y, z, ordinal, level, coefficient,
        active, collection, output)
end

function _compacted_active_fem_host_records(records)
    tuples = collect(StructArrays.StructArray{_CompactedActiveFEMTuple}(
        map(Array, StructArrays.components(records))))
    return [_CompactedActiveFEMRecord(record[1:8]...) for record in tuples]
end

function _run_compacted_active_fem_case(
        fixture, case_name::Symbol, active_element, array_type, backend
    )
    oracle = _compacted_active_fem_oracle(fixture, active_element)
    model = _compacted_active_fem_work(fixture, active_element)
    active_ordinal = _compacted_active_fem_ordinals(active_element)
    untouched = Float32(-12_345)
    storage = (
        active_ordinal = array_type(active_ordinal),
        refinement_level = array_type(fixture.refinement_level),
        coefficient = array_type(fixture.coefficient),
        active_element = array_type(active_element),
        x = array_type(fixture.x),
        y = array_type(fixture.y),
        z = array_type(fixture.z),
        element_quantity = array_type(fill(untouched, length(active_element))),
    )
    endpoints = array_type(fixture.element_nodes)
    counts = array_type(fill(Int32(fixture.dimension + 1), length(active_element)))
    bindings = Any[
        model.x => storage.x, model.y => storage.y,
        model.ordinal => storage.active_ordinal,
        model.level => storage.refinement_level,
        model.coefficient => storage.coefficient,
        model.active => storage.active_element,
        model.output => storage.element_quantity,
        model.connectivity => (; endpoints, counts),
        model.collection => LocalMath.Allocate(),
    ]
    fixture.dimension == 3 && push!(bindings, model.z => storage.z)
    prepared = LocalMath.prepare(model.law, bindings...;
        backend, lease_capacity=2)
    wait(LocalMath.execute!(prepared))

    compacted = LocalMath.storage(prepared, model.collection)
    count = Int(only(Array(compacted.count)))
    host_records = _compacted_active_fem_host_records(compacted.records)
    records = host_records[1:count]
    source_item = Array(compacted.source_item)[1:count]
    source_lane = Array(compacted.source_lane)[1:count]
    directory = Array(compacted.segment_starts)
    result = Array(storage.element_quantity)
    expected_result = fill(untouched, length(active_element))
    expected_result[1:length(oracle.quantities)] = oracle.quantities
    count == only(oracle.count) || error("active FEM count mismatch")
    records == oracle.records || error("active FEM record ordering mismatch")
    source_item == oracle.source_item || error("active FEM source-item mismatch")
    source_lane == oracle.source_lane || error("active FEM source-lane mismatch")
    directory == oracle.directory || error("active FEM directory mismatch")
    result == expected_result || error("active FEM quantity mismatch")

    return (
        name = :compacted_active_fem,
        dimension = fixture.dimension,
        case = case_name,
        result,
        reference = expected_result,
        compacted = (
            count = Int32[count],
            records,
            source_item,
            source_lane,
            directory,
        ),
        oracle,
    )
end

function run_localmath_compacted_active_fem_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    reports = map((Val(2), Val(3))) do dimension
        fixture = _compacted_active_fem_fixture(dimension)
        masks = _compacted_active_fem_masks(fixture.dimension)
        map(Tuple(pairs(masks))) do pair
            _run_compacted_active_fem_case(
                fixture, pair.first, pair.second, array_type, backend
            )
        end
    end
    return (; name = :compacted_active_fem, cases = reports)
end

abspath(PROGRAM_FILE) == (@__FILE__) &&
    println(run_localmath_compacted_active_fem_witness())
