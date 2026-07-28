const CNV_2012_ASSEMBLY_VERSION = "shirinifard-cnv-s38-s902-assembly-v1"

const CNV_MEDIUM = UInt8(0)
const CNV_RPE = UInt8(1)
const CNV_HRPE = UInt8(2)
const CNV_BRM = UInt8(3)
const CNV_DRUSEN = UInt8(4)
const CNV_TIP = UInt8(5)
const CNV_STALK = UInt8(6)
const CNV_VASCULAR = UInt8(7)
const CNV_POS = UInt8(8)
const CNV_PIS = UInt8(9)
const CNV_NONSTICK = UInt8(10)

"""
Explicit numerical profile for source-runtime details that are not portable
from CompuCell3D 3.4.2. It is deliberately narrow: source constants remain
fixed while the oxygen steady-state implementation and equal-temperature CPM
fallback are visible in the model fingerprint.
"""
struct CNV2012AmbiguityProfile
    oxygen_solver::Symbol
    cpm_temperature_profile::Symbol
    runtime_order::Symbol
end

function CNV2012AmbiguityProfile(;
    oxygen_solver::Symbol=:bounded_native_relaxation,
    cpm_temperature_profile::Symbol=:source_type_values_recorded,
    runtime_order::Symbol=:fields_then_biology_then_exchange,
)
    oxygen_solver in (:bounded_native_relaxation, :injected_adapter) ||
        throw(ArgumentError("unsupported CNV oxygen solver profile"))
    cpm_temperature_profile === :source_type_values_recorded ||
        throw(ArgumentError("unsupported CNV motility profile"))
    runtime_order === :fields_then_biology_then_exchange ||
        throw(ArgumentError("unsupported CNV runtime-order profile"))
    CNV2012AmbiguityProfile(
        oxygen_solver, cpm_temperature_profile, runtime_order)
end

const _CNV_FPP_ROWS = (
    (CNV_VASCULAR, CNV_BRM, 200.0, 2.0, 4.0, 2),
    (CNV_VASCULAR, CNV_VASCULAR, 200.0, 4.0, 8.0, 3),
    (CNV_RPE, CNV_RPE, 300.0, 4.2, 8.0, 6),
    (CNV_RPE, CNV_HRPE, 300.0, 4.2, 8.0, 3),
    (CNV_HRPE, CNV_HRPE, 300.0, 4.2, 8.0, 6),
    (CNV_RPE, CNV_BRM, 60.0, 3.5, 7.0, 6),
    (CNV_HRPE, CNV_BRM, 60.0, 3.5, 7.0, 6),
    (CNV_VASCULAR, CNV_TIP, 50.0, 3.5, 7.0, 2),
    (CNV_STALK, CNV_STALK, 50.0, 4.5, 9.0, 2),
    (CNV_STALK, CNV_TIP, 50.0, 4.5, 9.0, 1),
    (CNV_STALK, CNV_VASCULAR, 150.0, 4.0, 8.0, 2),
    (CNV_STALK, CNV_BRM, 25.0, 2.5, 5.0, 2),
    (CNV_TIP, CNV_BRM, 25.0, 2.5, 5.0, 2),
    (CNV_POS, CNV_POS, 20.0, 10.0, 20.0, 6),
    (CNV_DRUSEN, CNV_BRM, 30.0, 2.0, 4.0, 1),
    (CNV_PIS, CNV_PIS, 20.0, 8.0, 16.0, 6),
)

function _cnv_fpp_parameters(left::UInt8, right::UInt8)
    for row in _CNV_FPP_ROWS
        if (row[1] == left && row[2] == right) ||
           (row[1] == right && row[2] == left)
            return row[3:6]
        end
    end
    nothing
end

function _cnv_fill_box!(
    labels, types, id::UInt32, type::UInt8,
    xr, yr, zr,
)
    labels[xr, yr, zr] .= id
    types[Int(id)] = type
    id
end

"""
Generate the Text-S6 simulation-902 startup without reading or embedding its
PIF asset. Coordinates are the algebraic rectangular tiling stated by that
asset; x/y wrap fragments retain one identity.
"""
function cnv2012_initial_state(;
    shape::NTuple{3,<:Integer}=(40, 40, 35),
    capacity::Integer=5200,
)
    dimensions = Int.(shape)
    Tuple(dimensions) == (40, 40, 35) ||
        throw(ArgumentError(
            "the qualified CNV startup is fixed at 40×40×35"))
    capacity >= 5151 ||
        throw(ArgumentError("CNV startup capacity must be at least 5151"))
    labels = zeros(UInt32, dimensions...)
    types = zeros(UInt8, capacity)

    # Choriocapillaris: two perpendicular 4×4×4 segmented vessels.
    for (base, x0) in ((UInt32(1), 11), (UInt32(11), 27))
        for segment in 0:9
            segment in (3, 7) && continue
            id = base + UInt32(segment)
            _cnv_fill_box!(labels, types, id, CNV_VASCULAR,
                x0:(x0 + 3), (4segment + 1):(4segment + 4), 3:6)
        end
    end
    for (base, y0) in ((UInt32(21), 13), (UInt32(31), 29))
        for segment in 0:9
            id = base + UInt32(segment)
            _cnv_fill_box!(labels, types, id, CNV_VASCULAR,
                (4segment + 1):(4segment + 4), y0:(y0 + 3), 3:6)
        end
    end

    # RPE: staggered 4×4×4 periodic tiling with the source identity gaps.
    for row in 0:9
        start_id = UInt32(201 + 10row + fld(row, 2))
        offset = isodd(row) ? 2 : 0
        for column in 0:9
            id = start_id + UInt32(column)
            x0 = offset + 4column
            if x0 + 3 < 40
                _cnv_fill_box!(labels, types, id, CNV_RPE,
                    (x0 + 1):(x0 + 4), (4row + 1):(4row + 4), 7:10)
            else
                labels[(x0 + 1):40, (4row + 1):(4row + 4), 7:10] .= id
                labels[1:(x0 + 4 - 40), (4row + 1):(4row + 4), 7:10] .= id
                types[Int(id)] = CNV_RPE
            end
        end
    end

    # Coarse-grained photoreceptor outer and inner segments.
    for (type, zrange, block, rows, start) in (
        (CNV_POS, 11:20, 10, 4, 306),
        (CNV_PIS, 21:28, 8, 5, 324),
    )
        next_id = start
        for row in 0:(rows - 1)
            offset = isodd(row) ? div(block, 2) : 0
            y0 = block * row
            for column in 0:(rows - 1)
                id = UInt32(next_id)
                x0 = offset + block * column
                if x0 + block - 1 < 40
                    _cnv_fill_box!(labels, types, id, type,
                        (x0 + 1):(x0 + block),
                        (y0 + 1):(y0 + block), zrange)
                else
                    labels[(x0 + 1):40, (y0 + 1):(y0 + block), zrange] .= id
                    labels[1:(x0 + block - 40),
                        (y0 + 1):(y0 + block), zrange] .= id
                    types[Int(id)] = type
                end
                next_id += 1
            end
            isodd(row) && (next_id += 1)
        end
    end

    next_id = UInt32(351)
    _cnv_fill_box!(labels, types, next_id, CNV_TIP, 19:21, 13:15, 3:4)
    next_id += UInt32(1)
    for z in 5:6, y in 1:40, x in 1:40
        labels[x, y, z] = next_id
        types[Int(next_id)] = CNV_BRM
        next_id += UInt32(1)
    end
    for y in 1:40, x in 1:40
        labels[x, y, 35] = next_id
        types[Int(next_id)] = CNV_NONSTICK
        next_id += UInt32(1)
    end
    next_id == UInt32(5152) ||
        error("CNV generated startup identity accounting changed")

    target_volume = zeros(Float64, capacity)
    volume_strength = zeros(Float64, capacity)
    target_surface = zeros(Float64, capacity)
    surface_strength = zeros(Float64, capacity)
    normoxia_timer = zeros(UInt32, capacity)
    hypoxia_timer = zeros(UInt32, capacity)
    for id in eachindex(types)
        type = types[id]
        if type in (CNV_RPE, CNV_HRPE)
            target_volume[id], volume_strength[id] = 67.0, 25.0
            target_surface[id], surface_strength[id] = 120.0, 25.0
            normoxia_timer[id] = UInt32(801)
        elseif type == CNV_VASCULAR
            target_volume[id], volume_strength[id] = 42.0, 12.0
            target_surface[id], surface_strength[id] = 70.0, 10.0
        elseif type == CNV_TIP
            target_volume[id], volume_strength[id] = 35.0, 12.0
            target_surface[id], surface_strength[id] = 70.0, 10.0
        elseif type == CNV_BRM
            target_volume[id], volume_strength[id] = 1.0, 1.0e12
            target_surface[id], surface_strength[id] = 6.0, 1.0e9
        elseif type == CNV_DRUSEN
            target_volume[id], volume_strength[id] = 36.0, 10.0
        elseif type == CNV_POS
            target_volume[id], volume_strength[id] = 1000.0, 25.0
            target_surface[id], surface_strength[id] = 900.0, 25.0
        elseif type == CNV_PIS
            target_volume[id], volume_strength[id] = 512.0, 12.0
            target_surface[id], surface_strength[id] = 600.0, 10.0
        elseif type == CNV_NONSTICK
            target_volume[id], volume_strength[id] = 1.0, 1.0e12
            target_surface[id], surface_strength[id] = 6.0, 1.0e9
        end
    end
    links = cnv2012_initial_relationships(labels, types)
    (
        labels=labels,
        cell_types=types,
        target_volume=target_volume,
        volume_strength=volume_strength,
        target_surface=target_surface,
        surface_strength=surface_strength,
        normoxia_timer=normoxia_timer,
        hypoxia_timer=hypoxia_timer,
        link_a=links.a,
        link_b=links.b,
        link_strength=links.strength,
        link_target=links.target,
        link_maximum=links.maximum,
        link_active=links.active,
    )
end

function cnv2012_initial_relationships(labels, types)
    pairs = Set{Tuple{UInt32,UInt32}}()
    dimensions = size(labels)
    for site in CartesianIndices(labels)
        left = labels[site]
        iszero(left) && continue
        for axis in 1:3
            coordinate = site[axis]
            next_coordinate = coordinate + 1
            if next_coordinate > dimensions[axis]
                axis <= 2 || continue
                next_coordinate = 1
            end
            neighbor = CartesianIndex(ntuple(i ->
                i == axis ? next_coordinate : site[i], 3))
            right = labels[neighbor]
            iszero(right) || left == right || push!(
                pairs, minmax(left, right))
        end
    end
    degree = Dict{Tuple{UInt32,UInt8,UInt8},Int}()
    a = UInt32[]
    b = UInt32[]
    strength = Float64[]
    target = Float64[]
    maximum = Float64[]
    for (left, right) in sort!(collect(pairs))
        parameters = _cnv_fpp_parameters(
            types[Int(left)], types[Int(right)])
        isnothing(parameters) && continue
        λ, equilibrium, max_distance, max_links = parameters
        type_pair = minmax(types[Int(left)], types[Int(right)])
        left_key = (left, type_pair...)
        right_key = (right, type_pair...)
        get(degree, left_key, 0) < max_links &&
            get(degree, right_key, 0) < max_links ||
            continue
        push!(a, left)
        push!(b, right)
        push!(strength, λ)
        push!(target, equilibrium)
        push!(maximum, max_distance)
        degree[left_key] = get(degree, left_key, 0) + 1
        degree[right_key] = get(degree, right_key, 0) + 1
    end
    (
        a=a, b=b, strength=strength, target=target, maximum=maximum,
        active=ones(UInt8, length(a)),
    )
end

@inline function cnv2012_chemotaxis_response(
    cell_type::UInt8,
    field::Symbol,
    donor::Real,
    recipient::Real;
    endothelial_contact::Bool=false,
)
    endothelial_contact && return 0.0
    if field === :EC_VEGF
        λ = cell_type in (CNV_TIP, CNV_STALK) ? 12000.0 :
            cell_type == CNV_VASCULAR ? 5000.0 : 0.0
        return λ * (Float64(recipient) - Float64(donor))
    elseif field === :RPE_VEGF
        cell_type in (CNV_TIP, CNV_STALK) || return 0.0
        response(value) = Float64(value) / (1 + 0.09 * Float64(value))
        return 2500.0 * (response(recipient) - response(donor))
    end
    throw(ArgumentError("unknown CNV chemotaxis field"))
end

function _cnv_order4_relation(role::AbstractSpatialRole)
    offsets = Tuple(offset
        for offset in Iterators.product(-2:2, -2:2, -2:2)
        if 0 < sum(abs2, offset) <= 4)
    static_relation(role, offsets; spacing=(1.0, 1.0, 1.0))
end

function _cnv_contact_matrix()
    matrix = zeros(Float64, 11, 11)
    set!(a, b, value) =
        (matrix[a, b] = matrix[b, a] = Float64(value))
    medium = 11
    for (a, b, value) in (
        (1, medium, 3), (1, 1, -40),
        (2, medium, 3), (2, 1, -40), (2, 2, -40),
        (3, medium, -1), (3, 3, -12), (3, 1, -28), (3, 2, -28),
        (4, medium, 0), (4, 4, 0), (4, 1, 0), (4, 2, 0), (4, 3, 0),
        (5, medium, 3), (5, 5, -20), (5, 1, -10), (5, 2, -10),
        (5, 3, -10), (5, 4, -10),
        (6, medium, 3), (6, 6, -20), (6, 5, -20), (6, 1, -10),
        (6, 2, -10), (6, 3, -10), (6, 4, -10),
        (7, medium, 3), (7, 7, -20), (7, 5, -20), (7, 6, -20),
        (7, 1, -10), (7, 2, -10), (7, 3, -10), (7, 4, -10),
        (8, medium, 3), (8, 8, -16), (8, 1, -16), (8, 2, -16),
        (8, 3, 0), (8, 4, 0), (8, 5, -5), (8, 6, -5), (8, 7, -5),
        (9, medium, 3), (9, 9, -16), (9, 1, -16), (9, 2, -16),
        (9, 3, 0), (9, 4, 0), (9, 5, -5), (9, 6, -5), (9, 7, -5),
        (9, 8, -15),
    )
        set!(a, b, value)
    end
    for other in 1:9
        set!(10, other, 25)
    end
    set!(10, medium, 0)
    matrix
end

struct CNV2012CPMStep{P<:CNV2012AmbiguityProfile} <:
       ProcessBigraphs.AbstractStep
    root_seed::UInt64
    profile::P
end

function CNV2012CPMStep(;
    root_seed::Integer=498377,
    profile::CNV2012AmbiguityProfile=CNV2012AmbiguityProfile(),
)
    0 <= root_seed <= typemax(UInt64) ||
        throw(ArgumentError("CNV CPM seed must fit UInt64"))
    CNV2012CPMStep(UInt64(root_seed), profile)
end

function ProcessBigraphs.ports(::CNV2012CPMStep)
    input(name, type) = ProcessBigraphs.PortSpec(
        type, name, :input; interval_behavior=:event_updated)
    (
        input(:labels, Array{UInt32,3}),
        input(:cell_types, Vector{UInt8}),
        input(:target_volume, Vector{Float64}),
        input(:volume_strength, Vector{Float64}),
        input(:target_surface, Vector{Float64}),
        input(:surface_strength, Vector{Float64}),
        input(:ec_vegf, Array{Float64,3}),
        input(:rpe_vegf, Array{Float64,3}),
        ProcessBigraphs.PortSpec(
            Array{UInt32,3}, :labels_out, :output;
            update_law=:replace),
    )
end

ProcessBigraphs.semantic_version(::CNV2012CPMStep) = "1.0.0"
ProcessBigraphs.semantic_parameters(step::CNV2012CPMStep) = (
    contract_version=CNV_2012_ASSEMBLY_VERSION,
    source_seed=step.root_seed,
    proposal_neighbor_order=4,
    contact_neighbor_order=4,
    surface_relation=:face_boundary_measure,
    attempts_per_site=1,
    bounded_reference_temperature=100.0,
    source_type_motilities=(
        Tip=100.0, Stalk=100.0, Vascular=20.0,
        RPE=200.0, HRPE=200.0, POS=100.0, PIS=100.0,
        Drusen=20.0),
    contact_matrix=_cnv_contact_matrix(),
    source_chemotaxis=(
        EC_VEGF=(Tip=12000.0, Stalk=12000.0, Vascular=5000.0),
        RPE_VEGF=(Tip=2500.0, Stalk=2500.0, saturation=0.09),
    ),
    bounded_kernel_approximations=(
        :one_global_acceptance_temperature,
        :contact_inhibition_qualified_as_separate_microfixture,
        :focal_springs_committed_in_relationship_phase,
    ),
)

function _cnv_chemotaxis_property(
    key::Symbol,
    requester::ComponentIdentity,
)
    PropertySchema(PropertyDescriptor(
        key,
        Float64,
        ConstantInitializer(0.0);
        requester,
        division=CloneOnDivision(),
        transition=PreserveOnTransition(),
        kind=BiologicalProperty,
    ))
end

function _cnv_run_cpm(
    step::CNV2012CPMStep,
    labels,
    types,
    target_volume,
    volume_strength,
    target_surface,
    surface_strength,
    ec_vegf,
    rpe_vegf,
    target_mcs::UInt64,
)
    present = falses(length(types))
    for id in labels
        iszero(id) || (present[Int(id)] = true)
    end
    cell_types = Dict(
        CellID(id) => CellTypeID(types[Int(id)])
        for id in UInt32(1):UInt32(length(types))
        if !iszero(types[Int(id)]) && present[Int(id)]
    )
    owners = map(labels) do label
        iszero(label) ? MediumOwner(1) : CellOwner(label)
    end
    volume = QuadraticVolumeHamiltonian(number_type=Float64)
    surface_relation = first_shell_relation(SurfaceRole(), Val(3))
    surface = QuadraticBoundaryHamiltonian(
        BoundaryEdgeCount(), surface_relation;
        target=:target_surface,
        strength=:surface_strength,
        number_type=Float64,
    )
    media = MediumTypeTable(MediumID(1) => CellTypeID(11))
    contact = UnorderedContactHamiltonian(
        _cnv_contact_matrix(), media,
        _cnv_order4_relation(ContactRole()))
    field_boundaries = (
        AxisFieldBoundary(PeriodicFieldBoundary()),
        AxisFieldBoundary(PeriodicFieldBoundary()),
        AxisFieldBoundary(ZeroNeumannFieldBoundary()),
    )
    ec_drive = ChemotaxisDrive(
        CellCenteredField(
            ec_vegf; boundaries=field_boundaries,
            interpolation=NearestFieldInterpolation(),
            semantic_time=Float64(target_mcs),
            synchronization_epoch=target_mcs),
        OwnerScalarCoupling(
            :cnv_ec_vegf_sensitivity, MediumID(1) => 0.0;
            number_type=Float64),
        LinearResponse(),
        ExtensionChemotaxis(),
    )
    rpe_drive = ChemotaxisDrive(
        CellCenteredField(
            rpe_vegf; boundaries=field_boundaries,
            interpolation=NearestFieldInterpolation(),
            semantic_time=Float64(target_mcs),
            synchronization_epoch=target_mcs),
        OwnerScalarCoupling(
            :cnv_rpe_vegf_sensitivity, MediumID(1) => 0.0;
            number_type=Float64),
        SaturationLinearResponse(0.09),
        ExtensionChemotaxis(),
    )
    schema = merge_property_schemas(
        required_properties(volume),
        required_properties(surface),
        _cnv_chemotaxis_property(
            :cnv_ec_vegf_sensitivity, component_identity(ec_drive)),
        _cnv_chemotaxis_property(
            :cnv_rpe_vegf_sensitivity, component_identity(rpe_drive)),
    )
    logical = LogicalPottsState(
        owners, CellCapacity(length(types));
        cell_types, medium_domains=(MediumID(1),),
        property_schema=schema)
    active = active_cell_ids(logical)
    indices = value.(active)
    property_values(logical, :target_volume)[indices] .=
        target_volume[indices]
    property_values(logical, :volume_strength)[indices] .=
        volume_strength[indices]
    property_values(logical, :target_surface)[indices] .=
        round.(Int64, target_surface[indices])
    property_values(logical, :surface_strength)[indices] .=
        surface_strength[indices]
    ec_sensitivity =
        property_values(logical, :cnv_ec_vegf_sensitivity)
    rpe_sensitivity =
        property_values(logical, :cnv_rpe_vegf_sensitivity)
    for id in active
        index = Int(value(id))
        type = types[index]
        ec_sensitivity[index] =
            type in (CNV_TIP, CNV_STALK) ? 120.0 :
            type == CNV_VASCULAR ? 250.0 : 0.0
        rpe_sensitivity[index] =
            type in (CNV_TIP, CNV_STALK) ? 25.0 : 0.0
    end
    domain = CartesianDomain(
        size(labels);
        boundaries=(
            AxisBoundary(PeriodicBoundary()),
            AxisBoundary(PeriodicBoundary()),
            AxisBoundary(ClosedBoundary()),
        ))
    scientific = compile_scientific_state(
        logical,
        domain,
        BoundaryMeasureTracker(
            BoundaryEdgeCount(), surface_relation))
    components = ScientificComponentSet(
        energies=(volume, contact, surface),
        drives=(ec_drive, rpe_drive),
    )
    integrator = init_scientific(
        scientific,
        _cnv_order4_relation(ProposalRole()),
        components,
        BudgetedSequentialCPM(
            AttemptsPerSite(1); temperature=100.0);
        seed=step.root_seed,
        plan=ExecutionPlan(KernelAbstractions.CPU()),
    )
    integrator.mcs = target_mcs - UInt64(1)
    perform_scientific_mcs!(integrator, integrator.algorithm)
    snapshot = logical_state(integrator)
    output = zeros(UInt32, size(labels))
    for site in eachindex(output)
        owner = owner_at(snapshot, site)
        output[site] =
            is_cell_owner(owner) ? owner.value : UInt32(0)
    end
    output
end

function ProcessBigraphs.invoke(
    step::CNV2012CPMStep,
    inputs::ProcessBigraphs.PortView,
    context::ProcessBigraphs.InvocationContext,
)
    target_mcs = UInt64(context.end_time.tick)
    labels = _cnv_run_cpm(
        step,
        inputs[:labels],
        inputs[:cell_types],
        inputs[:target_volume],
        inputs[:volume_strength],
        inputs[:target_surface],
        inputs[:surface_strength],
        inputs[:ec_vegf],
        inputs[:rpe_vegf],
        target_mcs,
    )
    ProcessBigraphs.InvocationResult((
        ProcessBigraphs.emit(
            context, :labels_out,
            ProcessBigraphs.ReplaceUpdate(), labels),
    ); diagnostics=(mcs=target_mcs, attempts=length(labels)))
end

function _cnv_centers_and_volumes(labels, capacity)
    volumes = zeros(Int, capacity)
    sums = zeros(Float64, capacity, 3)
    for site in CartesianIndices(labels)
        id = Int(labels[site])
        iszero(id) && continue
        volumes[id] += 1
        for axis in 1:3
            sums[id, axis] += site[axis]
        end
    end
    centers = zeros(Int, capacity, 3)
    for id in 1:capacity
        volumes[id] == 0 && continue
        for axis in 1:3
            centers[id, axis] = clamp(
                round(Int, sums[id, axis] / volumes[id]),
                1, size(labels, axis))
        end
    end
    centers, volumes
end

function _cnv_endothelial_contact(labels, types, id::UInt32)
    total = 0
    for site in CartesianIndices(labels)
        labels[site] == id || continue
        for axis in 1:3, delta in (-1, 1)
            coordinates = Tuple(site)
            value = coordinates[axis] + delta
            if !(1 <= value <= size(labels, axis))
                axis <= 2 || continue
                value = mod1(value, size(labels, axis))
            end
            neighbor = CartesianIndex(
                Base.setindex(coordinates, value, axis))
            neighbor_id = labels[neighbor]
            if !iszero(neighbor_id) &&
               types[Int(neighbor_id)] in
               (CNV_TIP, CNV_STALK, CNV_VASCULAR)
                total += 1
            end
        end
    end
    total
end

function _cnv_rpe_support_contact(labels, types, id::UInt32)
    total = 0
    for site in CartesianIndices(labels)
        labels[site] == id || continue
        for axis in 1:3, delta in (-1, 1)
            coordinates = Tuple(site)
            value = coordinates[axis] + delta
            if !(1 <= value <= size(labels, axis))
                axis <= 2 || continue
                value = mod1(value, size(labels, axis))
            end
            neighbor = CartesianIndex(
                Base.setindex(coordinates, value, axis))
            neighbor_id = labels[neighbor]
            !iszero(neighbor_id) &&
                types[Int(neighbor_id)] in
                (CNV_RPE, CNV_HRPE, CNV_BRM) && (total += 1)
        end
    end
    total
end

struct CNV2012BiologyStep{P<:CNV2012AmbiguityProfile} <:
       ProcessBigraphs.AbstractStep
    source_simulation::Int
    profile::P
end
CNV2012BiologyStep(
    profile::CNV2012AmbiguityProfile=CNV2012AmbiguityProfile(),
) = CNV2012BiologyStep(902, profile)

function ProcessBigraphs.ports(::CNV2012BiologyStep)
    input(name, type) = ProcessBigraphs.PortSpec(
        type, name, :input; interval_behavior=:event_updated)
    output(name, type) = ProcessBigraphs.PortSpec(
        type, name, :output; update_law=:replace)
    (
        input(:labels, Array{UInt32,3}),
        input(:cell_types, Vector{UInt8}),
        input(:target_volume, Vector{Float64}),
        input(:target_surface, Vector{Float64}),
        input(:normoxia_timer, Vector{UInt32}),
        input(:hypoxia_timer, Vector{UInt32}),
        input(:oxygen, Array{Float64,3}),
        input(:rpe_vegf, Array{Float64,3}),
        input(:mmp, Array{Float64,3}),
        input(:link_a, Vector{UInt32}),
        input(:link_b, Vector{UInt32}),
        input(:link_target, Vector{Float64}),
        input(:link_maximum, Vector{Float64}),
        input(:link_active, Vector{UInt8}),
        output(:labels_out, Array{UInt32,3}),
        output(:cell_types_out, Vector{UInt8}),
        output(:target_volume_out, Vector{Float64}),
        output(:target_surface_out, Vector{Float64}),
        output(:normoxia_timer_out, Vector{UInt32}),
        output(:hypoxia_timer_out, Vector{UInt32}),
        output(:link_target_out, Vector{Float64}),
        output(:link_maximum_out, Vector{Float64}),
    )
end

ProcessBigraphs.semantic_version(::CNV2012BiologyStep) = "1.0.0"
ProcessBigraphs.semantic_parameters(step::CNV2012BiologyStep) = (
    contract_version=CNV_2012_ASSEMBLY_VERSION,
    source_doi="10.1371/journal.pcbi.1002440",
    source_scenario=38,
    source_simulation=step.source_simulation,
    tip_to_stalk_mcs=400,
    hypoxia_threshold=49.0,
    timer_threshold_mcs=800,
    endothelial_death_threshold=1.0e-5,
    endothelial_death_after_mcs=1000,
    stalk_contact_limit=17,
    division_volume=64,
    brm_degradation_rate=0.075,
    ambiguity_profile=(
        oxygen_solver=step.profile.oxygen_solver,
        cpm_temperature_profile=step.profile.cpm_temperature_profile,
        runtime_order=step.profile.runtime_order,
    ),
)

function ProcessBigraphs.invoke(
    step::CNV2012BiologyStep,
    inputs::ProcessBigraphs.PortView,
    context::ProcessBigraphs.InvocationContext,
)
    mcs = context.end_time.tick
    labels = copy(inputs[:labels])
    types = copy(inputs[:cell_types])
    target_volume = copy(inputs[:target_volume])
    target_surface = copy(inputs[:target_surface])
    normoxia = copy(inputs[:normoxia_timer])
    hypoxia = copy(inputs[:hypoxia_timer])
    oxygen_field = inputs[:oxygen]
    rpe_vegf_field = inputs[:rpe_vegf]
    mmp_field = inputs[:mmp]
    link_a = inputs[:link_a]
    link_b = inputs[:link_b]
    link_active = inputs[:link_active]
    link_target = copy(inputs[:link_target])
    link_maximum = copy(inputs[:link_maximum])
    centers, volumes = _cnv_centers_and_volumes(labels, length(types))
    divisions = 0
    deaths = 0
    transitions = 0

    for id in eachindex(types)
        type = types[id]
        (iszero(type) || iszero(volumes[id])) && continue
        point = CartesianIndex(
            centers[id, 1], centers[id, 2], centers[id, 3])
        if type == CNV_TIP && mcs == 400
            types[id] = CNV_STALK
            type = CNV_STALK
            transitions += 1
        end
        if type in (CNV_VASCULAR, CNV_STALK)
            vegf = rpe_vegf_field[point]
            if type == CNV_STALK
                contact = _cnv_endothelial_contact(labels, types, UInt32(id))
                if contact < 17 && target_volume[id] - volumes[id] <= 2
                    increment = 0.426 * vegf / (0.005 + vegf)
                    target_volume[id] += increment
                    target_surface[id] += 2increment
                    for edge in eachindex(link_a)
                        link_active[edge] == UInt8(0) && continue
                        left, right = link_a[edge], link_b[edge]
                        other = left == id ? right : right == id ? left : UInt32(0)
                        iszero(other) && continue
                        types[Int(other)] in (CNV_VASCULAR, CNV_STALK) ||
                            continue
                        other_point = @view centers[Int(other), :]
                        dx = abs(other_point[1] - centers[id, 1])
                        dy = abs(other_point[2] - centers[id, 2])
                        dx = min(dx, size(labels, 1) - dx)
                        dy = min(dy, size(labels, 2) - dy)
                        dz = other_point[3] - centers[id, 3]
                        distance = sqrt(dx^2 + dy^2 + dz^2)
                        link_target[edge] = distance
                        link_maximum[edge] = 2distance
                    end
                end
            end
            if vegf < 1.0e-5 && mcs > 1000
                target_volume[id] = 0.0
                target_surface[id] = 0.0
                deaths += 1
            end
        elseif type in (CNV_RPE, CNV_HRPE)
            if _cnv_rpe_support_contact(labels, types, UInt32(id)) == 0 &&
               mcs > 10
                target_volume[id] = max(0.0, target_volume[id] - 0.5)
                target_surface[id] = max(0.0, target_surface[id] - 0.5)
                deaths += 1
            end
            oxygen = oxygen_field[point]
            if type == CNV_RPE && oxygen < 49 && normoxia[id] > 800
                types[id] = CNV_HRPE
                hypoxia[id] = UInt32(1)
                transitions += 1
            elseif type == CNV_RPE
                normoxia[id] += UInt32(1)
            elseif type == CNV_HRPE &&
                   (oxygen > 49 || hypoxia[id] > 800)
                types[id] = CNV_RPE
                hypoxia[id] = UInt32(0)
                normoxia[id] = UInt32(1)
                transitions += 1
            else
                hypoxia[id] += UInt32(1)
            end
        elseif type == CNV_BRM && mcs < 500
            target_volume[id] -= 0.075 * mmp_field[point]
        end
    end

    # Source mitosis threshold. The split is deterministic and bounded; it is
    # exercised by generated microfixtures, not by the canonical startup.
    for parent in eachindex(types)
        types[parent] in (CNV_TIP, CNV_STALK) || continue
        volumes[parent] > 64 || continue
        child = findfirst(i -> iszero(types[i]), eachindex(types))
        isnothing(child) && break
        sites = findall(==(UInt32(parent)), labels)
        sort!(sites; by=site -> (site[1], site[2], site[3]))
        for site in @view sites[(fld(length(sites), 2) + 1):end]
            labels[site] = UInt32(child)
        end
        types[child] = CNV_STALK
        target_volume[parent] = target_volume[child] = 35.0
        target_surface[parent] = target_surface[child] = 70.0
        normoxia[child] = normoxia[parent]
        hypoxia[child] = hypoxia[parent]
        divisions += 1
    end

    emit = ProcessBigraphs.emit
    replace = ProcessBigraphs.ReplaceUpdate()
    ProcessBigraphs.InvocationResult((
        emit(context, :labels_out, replace, labels),
        emit(context, :cell_types_out, replace, types),
        emit(context, :target_volume_out, replace, target_volume),
        emit(context, :target_surface_out, replace, target_surface),
        emit(context, :normoxia_timer_out, replace, normoxia),
        emit(context, :hypoxia_timer_out, replace, hypoxia),
        emit(context, :link_target_out, replace, link_target),
        emit(context, :link_maximum_out, replace, link_maximum),
    ); diagnostics=(mcs=mcs, divisions=divisions, deaths=deaths,
        transitions=transitions))
end

struct CNV2012ExchangeStep <: ProcessBigraphs.AbstractStep end

function ProcessBigraphs.ports(::CNV2012ExchangeStep)
    input(name, type) = ProcessBigraphs.PortSpec(
        type, name, :input; interval_behavior=:event_updated)
    output(name) = ProcessBigraphs.PortSpec(
        Array{Float64,3}, name, :output; update_law=:replace)
    (
        input(:labels, Array{UInt32,3}),
        input(:cell_types, Vector{UInt8}),
        input(:oxygen, Array{Float64,3}),
        input(:rpe_vegf, Array{Float64,3}),
        output(:oxygen_forcing),
        output(:ec_vegf_forcing),
        output(:ec_vegf_decay_weights),
        output(:rpe_vegf_forcing),
        output(:mmp_forcing),
    )
end

ProcessBigraphs.semantic_version(::CNV2012ExchangeStep) = "1.0.0"
ProcessBigraphs.semantic_parameters(::CNV2012ExchangeStep) = (
    contract_version=CNV_2012_ASSEMBLY_VERSION,
    source_fields=(:Oxygen, :VEGF1, :VEGF2, :MMP),
    canonical_names=(:oxygen, :EC_VEGF, :RPE_VEGF, :MMP),
    vegf2_finite_difference_passes_per_mcs=13,
)

function ProcessBigraphs.invoke(
    ::CNV2012ExchangeStep,
    inputs::ProcessBigraphs.PortView,
    context::ProcessBigraphs.InvocationContext,
)
    labels, types = inputs[:labels], inputs[:cell_types]
    prior_oxygen = inputs[:oxygen]
    prior_rpe_vegf = inputs[:rpe_vegf]
    oxygen = zeros(Float64, size(labels))
    ec_vegf = zeros(Float64, size(labels))
    ec_decay = ones(Float64, size(labels))
    rpe_vegf = zeros(Float64, size(labels))
    mmp = zeros(Float64, size(labels))
    for site in eachindex(labels)
        id = labels[site]
        iszero(id) && continue
        type = types[Int(id)]
        if type == CNV_VASCULAR
            oxygen[site] = 4.0 / 216
            ec_vegf[site] = 0.01 / 216
            ec_decay[site] = 0.0
        elseif type == CNV_STALK
            oxygen[site] = 0.01 / 216
            ec_vegf[site] = 0.01 / 216
            ec_decay[site] = 0.0
        elseif type == CNV_TIP
            ec_vegf[site] = 0.01 / 216
            ec_decay[site] = 0.0
            mmp[site] = 1.0 / 216
        elseif type == CNV_PIS
            oxygen[site] = -0.43 / 216
        end
        if type in (CNV_RPE, CNV_HRPE)
            rpe_vegf[site] +=
                (type == CNV_HRPE ? 0.13 : 0.065) / 216
        elseif type in (CNV_VASCULAR, CNV_STALK, CNV_TIP)
            rate = type == CNV_VASCULAR ? 0.28 : 0.56
            concentration = prior_rpe_vegf[site]
            rpe_vegf[site] -= min(rate, rate * concentration) / 216
        end
    end
    # Text S6 fixes the upper z plane at 18 mmHg while the lower face is
    # no-flux. The generic native adapter carries the homogeneous no-flux
    # stencil; this frozen exchange term applies the source-specific upper
    # face without creating a model-specific field solver.
    oxygen[:, :, end] .=
        (18.0 .- prior_oxygen[:, :, end]) ./ 216.0
    emit = ProcessBigraphs.emit
    replace = ProcessBigraphs.ReplaceUpdate()
    ProcessBigraphs.InvocationResult((
        emit(context, :oxygen_forcing, replace, oxygen),
        emit(context, :ec_vegf_forcing, replace, ec_vegf),
        emit(context, :ec_vegf_decay_weights, replace, ec_decay),
        emit(context, :rpe_vegf_forcing, replace, rpe_vegf),
        emit(context, :mmp_forcing, replace, mmp),
    ))
end

const CNV2012ObservationRecord = NamedTuple{
    (:mcs, :tip, :stalk, :rpe, :hrpe, :active_links,
        :brm_target_mass, :oxygen_minimum, :oxygen_maximum),
    Tuple{Int,Int,Int,Int,Int,Int,Float64,Float64,Float64},
}

struct CNV2012Observer <: ProcessBigraphs.AbstractObserver end
ProcessBigraphs.observer_semantic_version(::CNV2012Observer) = "1.0.0"
ProcessBigraphs.observer_semantic_parameters(::CNV2012Observer) = (
    contract_version=CNV_2012_ASSEMBLY_VERSION,
    source_output_cadence_mcs=100,
)

function ProcessBigraphs.observe(::CNV2012Observer, projection, context)
    types = projection[ProcessBigraphs.path("cell_types")]
    target_volume = projection[ProcessBigraphs.path("target_volume")]
    links = projection[ProcessBigraphs.path("link_active")]
    oxygen = projection[ProcessBigraphs.path("oxygen")]
    record = CNV2012ObservationRecord((
        Int(context.time.tick),
        count(==(CNV_TIP), types),
        count(==(CNV_STALK), types),
        count(==(CNV_RPE), types),
        count(==(CNV_HRPE), types),
        count(!iszero, links),
        sum(target_volume[i] for i in eachindex(types)
            if types[i] == CNV_BRM),
        minimum(oxygen),
        maximum(oxygen),
    ))
    ProcessBigraphs.ObservationResult(record)
end

function cnv2012_observation_plan(
    time_scale::ProcessBigraphs.TimeScale=
        ProcessBigraphs.TimeScale(216, 1, :second);
    cadence_mcs::Integer=1,
)
    cadence_mcs > 0 || throw(ArgumentError("CNV observation cadence must be positive"))
    observer = CNV2012Observer()
    spec = ProcessBigraphs.ObserverSpec(
        "cnv-state-observer",
        observer,
        (
            ProcessBigraphs.path("cell_types"),
            ProcessBigraphs.path("target_volume"),
            ProcessBigraphs.path("link_active"),
            ProcessBigraphs.path("oxygen"),
        ),
        ProcessBigraphs.PeriodicObservationSchedule(
            ProcessBigraphs.Duration(cadence_mcs, time_scale));
        record_schema=ProcessBigraphs.RecordSchema(
            CNV2012ObservationRecord;
            identity="cnv-state-observation-v1",
        ),
    )
    ProcessBigraphs.ObservationPlan((spec,))
end

function _cnv_field_defaults(state)
    shape = size(state.labels)
    oxygen = Array{Float64}(undef, shape)
    for site in CartesianIndices(oxygen)
        oxygen[site] = 80.0 + (18.0 - 80.0) * (site[3] - 1) / 34
    end
    zeros_field = zeros(Float64, shape)
    exchange_context = nothing
    oxygen, zeros_field
end

function _cnv_initial_exchange(state, rpe_vegf)
    labels, types = state.labels, state.cell_types
    oxygen = zeros(Float64, size(labels))
    ec = zeros(Float64, size(labels))
    ec_decay = ones(Float64, size(labels))
    rpe = zeros(Float64, size(labels))
    mmp = zeros(Float64, size(labels))
    for site in eachindex(labels)
        id = labels[site]
        iszero(id) && continue
        type = types[Int(id)]
        type == CNV_VASCULAR && (oxygen[site] = 4.0 / 216)
        type == CNV_PIS && (oxygen[site] = -0.43 / 216)
        if type in (CNV_TIP, CNV_STALK, CNV_VASCULAR)
            ec[site] = 0.01 / 216
            ec_decay[site] = 0.0
        end
        type == CNV_TIP && (mmp[site] = 1.0 / 216)
        type in (CNV_RPE, CNV_HRPE) &&
            (rpe[site] = (type == CNV_HRPE ? 0.13 : 0.065) / 216)
    end
    (oxygen=oxygen, ec=ec, ec_decay=ec_decay, rpe=rpe, mmp=mmp)
end

function cnv2012_composite(
    state::NamedTuple,
    field_declarations::NamedTuple;
    time_scale::ProcessBigraphs.TimeScale=
        ProcessBigraphs.TimeScale(216, 1, :second),
    resource_authorization::NamedTuple=(
        backend=:cpu, precision=:float64, residency=:host),
    initial_oxygen=nothing,
    initial_ec_vegf=zeros(Float64, size(state.labels)),
    initial_rpe_vegf=zeros(Float64, size(state.labels)),
    initial_mmp=zeros(Float64, size(state.labels)),
    profile::CNV2012AmbiguityProfile=CNV2012AmbiguityProfile(),
)
    keys(field_declarations) ==
        (:oxygen, :ec_vegf, :rpe_vegf, :mmp) ||
        throw(ArgumentError(
            "CNV requires oxygen, ec_vegf, rpe_vegf, and mmp declarations"))
    oxygen_default, _ = _cnv_field_defaults(state)
    oxygen_values = isnothing(initial_oxygen) ? oxygen_default : initial_oxygen
    exchange = _cnv_initial_exchange(state, initial_rpe_vegf)
    shape = size(state.labels)
    field_leaf(value; units="concentration") =
        ProcessBigraphs.LeafSchema(Float64; shape, default=copy(value),
            update_law=:replace, owner=:shared, units)
    vector_leaf(type, value) = ProcessBigraphs.LeafSchema(
        type; shape=(length(value),), default=copy(value),
        update_law=:replace, owner=:shared)
    schema = ProcessBigraphs.BranchSchema(
        labels=ProcessBigraphs.LeafSchema(
            UInt32; shape, default=copy(state.labels),
            update_law=:replace, owner=:shared),
        cell_types=vector_leaf(UInt8, state.cell_types),
        target_volume=vector_leaf(Float64, state.target_volume),
        volume_strength=vector_leaf(Float64, state.volume_strength),
        target_surface=vector_leaf(Float64, state.target_surface),
        surface_strength=vector_leaf(Float64, state.surface_strength),
        normoxia_timer=vector_leaf(UInt32, state.normoxia_timer),
        hypoxia_timer=vector_leaf(UInt32, state.hypoxia_timer),
        link_a=vector_leaf(UInt32, state.link_a),
        link_b=vector_leaf(UInt32, state.link_b),
        link_strength=vector_leaf(Float64, state.link_strength),
        link_target=vector_leaf(Float64, state.link_target),
        link_maximum=vector_leaf(Float64, state.link_maximum),
        link_active=vector_leaf(UInt8, state.link_active),
        oxygen=field_leaf(oxygen_values; units="mmHg"),
        oxygen_mcs=field_leaf(oxygen_values; units="mmHg"),
        oxygen_forcing=field_leaf(exchange.oxygen; units="mmHg/MCS"),
        oxygen_decay_weights=field_leaf(zeros(Float64, shape)),
        ec_vegf=field_leaf(initial_ec_vegf),
        ec_vegf_mcs=field_leaf(initial_ec_vegf),
        ec_vegf_forcing=field_leaf(exchange.ec),
        ec_vegf_decay_weights=field_leaf(exchange.ec_decay),
        rpe_vegf=field_leaf(initial_rpe_vegf),
        rpe_vegf_mcs=field_leaf(initial_rpe_vegf),
        rpe_vegf_forcing=field_leaf(exchange.rpe),
        rpe_vegf_decay_weights=field_leaf(ones(Float64, shape)),
        mmp=field_leaf(initial_mmp),
        mmp_mcs=field_leaf(initial_mmp),
        mmp_forcing=field_leaf(exchange.mmp),
        mmp_decay_weights=field_leaf(ones(Float64, shape)),
    )
    processes = Tuple(map(
        pair -> ProcessBigraphs.ProcessDeclaration(
            begin
                name = first(pair)
                "cnv-" * replace(String(name), "_" => "-")
            end,
            ProcessBigraphs.ManagedFieldAdvanceProcess(
                last(pair); resource_authorization),
            ProcessBigraphs.FixedSchedule(
                ProcessBigraphs.Duration(1, time_scale))),
        collect(pairs(field_declarations)),
    ))
    cpm = ProcessBigraphs.StepDeclaration(
        "cnv-cpm", CNV2012CPMStep(profile=profile))
    biology = ProcessBigraphs.StepDeclaration(
        "cnv-biology", CNV2012BiologyStep(profile);
        dependencies=("cnv-cpm",))
    exchange_step = ProcessBigraphs.StepDeclaration(
        "cnv-field-exchange", CNV2012ExchangeStep();
        dependencies=("cnv-biology",))
    bindings = ProcessBigraphs.PortBinding[]
    for name in keys(field_declarations)
        owner = "cnv-" * replace(String(name), "_" => "-")
        forcing_name = Symbol(name, :_forcing)
        weights_name = Symbol(name, :_decay_weights)
        push!(bindings,
            ProcessBigraphs.PortBinding(owner, :field,
                ProcessBigraphs.path(String(name))),
            ProcessBigraphs.PortBinding(owner, :forcing,
                ProcessBigraphs.path(String(forcing_name))),
            ProcessBigraphs.PortBinding(owner, :decay_weights,
                ProcessBigraphs.path(String(weights_name))),
            ProcessBigraphs.PortBinding(owner, :field_out,
                ProcessBigraphs.path(String(name))),
            ProcessBigraphs.PortBinding(owner, :mcs_field,
                ProcessBigraphs.path(String(name) * "_mcs")),
        )
    end
    cpm_bindings = (
        (:labels, :labels), (:cell_types, :cell_types),
        (:target_volume, :target_volume),
        (:volume_strength, :volume_strength),
        (:target_surface, :target_surface),
        (:surface_strength, :surface_strength),
        (:ec_vegf, :ec_vegf_mcs),
        (:rpe_vegf, :rpe_vegf_mcs),
        (:labels_out, :labels),
    )
    for (port, target) in cpm_bindings
        push!(bindings, ProcessBigraphs.PortBinding(
            "cnv-cpm", port, ProcessBigraphs.path(String(target))))
    end
    biology_bindings = (
        (:labels, :labels), (:cell_types, :cell_types),
        (:target_volume, :target_volume), (:target_surface, :target_surface),
        (:normoxia_timer, :normoxia_timer), (:hypoxia_timer, :hypoxia_timer),
        (:oxygen, :oxygen_mcs), (:rpe_vegf, :rpe_vegf_mcs), (:mmp, :mmp_mcs),
        (:link_a, :link_a), (:link_b, :link_b),
        (:link_target, :link_target), (:link_maximum, :link_maximum),
        (:link_active, :link_active),
        (:labels_out, :labels), (:cell_types_out, :cell_types),
        (:target_volume_out, :target_volume),
        (:target_surface_out, :target_surface),
        (:normoxia_timer_out, :normoxia_timer),
        (:hypoxia_timer_out, :hypoxia_timer),
        (:link_target_out, :link_target),
        (:link_maximum_out, :link_maximum),
    )
    for (port, target) in biology_bindings
        push!(bindings, ProcessBigraphs.PortBinding(
            "cnv-biology", port, ProcessBigraphs.path(String(target))))
    end
    exchange_bindings = (
        (:labels, :labels), (:cell_types, :cell_types),
        (:oxygen, :oxygen), (:rpe_vegf, :rpe_vegf),
        (:oxygen_forcing, :oxygen_forcing),
        (:ec_vegf_forcing, :ec_vegf_forcing),
        (:ec_vegf_decay_weights, :ec_vegf_decay_weights),
        (:rpe_vegf_forcing, :rpe_vegf_forcing),
        (:mmp_forcing, :mmp_forcing),
    )
    for (port, target) in exchange_bindings
        push!(bindings, ProcessBigraphs.PortBinding(
            "cnv-field-exchange", port,
            ProcessBigraphs.path(String(target))))
    end
    static = ProcessBigraphs.StaticComposite(
        schema, Dict(), time_scale;
        processes=Tuple(processes),
        steps=(cpm, biology, exchange_step),
        bindings=Tuple(bindings),
    )
    ProcessBigraphs.compile_composite(static)
end

function cnv2012_native_composite(
    state::NamedTuple=cnv2012_initial_state();
    time_scale::ProcessBigraphs.TimeScale=
        ProcessBigraphs.TimeScale(216, 1, :second),
    initial_oxygen=nothing,
    initial_ec_vegf=zeros(Float64, size(state.labels)),
    initial_rpe_vegf=zeros(Float64, size(state.labels)),
    initial_mmp=zeros(Float64, size(state.labels)),
    profile::CNV2012AmbiguityProfile=CNV2012AmbiguityProfile(),
)
    oxygen_default, _ = _cnv_field_defaults(state)
    oxygen_values = isnothing(initial_oxygen) ? oxygen_default : initial_oxygen
    shape = size(state.labels)
    geometry = NativeFieldGeometry(
        shape; spacing=(3.0, 3.0, 3.0), number_type=Float64)
    periodic = AxisFieldBoundary(PeriodicFieldBoundary())
    noflux_z = (
        periodic, periodic,
        AxisFieldBoundary(ZeroNeumannFieldBoundary()))
    declaration(name, values; boundaries=noflux_z,
        diffusion, decay=0.0, substeps=1) =
        corepotts_native_field_declaration(
            "cnv-native-" * replace(String(name), "_" => "-"),
            CorePottsNativeFieldAdapter(
                name, values;
                geometry, boundaries, diffusion, decay,
                tick_duration=216.0,
                substeps_per_tick=substeps,
                time_scale,
            ),
        )
    declarations = (
        oxygen=declaration(
            :oxygen, oxygen_values;
            boundaries=noflux_z,
            diffusion=0.18 / 216, decay=5.0e-12 / 216, substeps=8),
        ec_vegf=declaration(
            :ec_vegf, initial_ec_vegf;
            diffusion=0.06 / 216, decay=0.06 / 216, substeps=1),
        rpe_vegf=declaration(
            :rpe_vegf, initial_rpe_vegf;
            diffusion=1.56 / 216, decay=0.078 / 216, substeps=13),
        mmp=declaration(
            :mmp, initial_mmp;
            diffusion=0.0003 / 216, decay=0.06 / 216, substeps=1),
    )
    cnv2012_composite(
        state, declarations;
        time_scale, initial_oxygen=oxygen_values, initial_ec_vegf,
        initial_rpe_vegf, initial_mmp, profile,
    )
end
