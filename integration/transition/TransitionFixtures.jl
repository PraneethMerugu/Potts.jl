module TransitionFixtures

using TOML
using CorePotts
using ..TransitionKernelOracle
using ..CheckerboardOracle

export TransitionFixture, load_transition_manifest, empirical_fixture_rows,
       parse_owner_encoding, build_transition_fixture, oracle_kernel

const DEFAULT_MANIFEST = normpath(joinpath(@__DIR__, "..", "..", "design", "audits",
    "phase-13-fixture-manifest.toml"))

struct TransitionFixture{T <: AbstractFloat}
    id::String
    source_encoding::String
    temperature::Float64
    production_temperature::T
    production_domain
    proposal_relation
    contact_relation
    surface_relation
    boundary_tracker
    volume_component
    contact_component
    logical_state
    compiled_state
    scientific_state
    production_supported::Bool
    production_limitation::Union{Nothing, String}
    oracle_domain
    oracle_model
    oracle_state
    oracle_catalog
end

load_transition_manifest(path::AbstractString = DEFAULT_MANIFEST) = TOML.parsefile(path)

function empirical_fixture_rows(manifest::AbstractDict = load_transition_manifest())
    rows = NamedTuple[]
    for fixture in manifest["fixtures"]
        for (source_index, source) in pairs(fixture["empirical_source_states"])
            push!(rows, (; fixture, source_index, source = String(source),
                row_id = "$(fixture["id"])-source-$(source_index)"))
        end
    end
    return rows
end

function _parse_rational(value)
    value isa Real && return Float64(value)
    parts = split(String(value), '/'; limit = 2)
    length(parts) == 1 && return parse(Float64, only(parts))
    return parse(Float64, parts[1]) / parse(Float64, parts[2])
end

function parse_owner_encoding(encoding::AbstractString)
    owners = OracleOwner[]
    for token in split(encoding, ',')
        fields = split(strip(token), ':'; limit = 2)
        length(fields) == 2 || throw(ArgumentError("invalid transition-kernel owner token: $token"))
        id = parse(Int, fields[2])
        fields[1] == "cell" ? push!(owners, oracle_cell(id)) :
        fields[1] == "medium" ? push!(owners, oracle_medium(id)) :
        throw(ArgumentError("unknown transition-kernel owner kind: $(fields[1])"))
    end
    return Tuple(owners)
end

_production_owner(owner::OracleOwner) = owner.kind === OracleCellKind ?
    CellOwner(Int(owner.id)) : MediumOwner(Int(owner.id))

function _offsets(topology::AbstractString, dimension::Integer)
    if topology == "von_neumann"
        return Tuple(vcat(
            [ntuple(axis -> axis == direction ? -1 : 0, dimension)
                for direction in 1:dimension],
            [ntuple(axis -> axis == direction ? 1 : 0, dimension)
                for direction in 1:dimension]))
    elseif topology == "moore"
        return Tuple(Tuple(offset) for offset in Iterators.product(
            ntuple(_ -> -1:1, dimension)...) if any(!iszero, offset))
    end
    throw(ArgumentError("unknown transition-kernel topology: $topology"))
end

function _oracle_boundary(name::AbstractString)
    name == "periodic" && return OraclePeriodic
    name == "no_flux" && return OracleNoFlux
    throw(ArgumentError("unknown transition-kernel boundary: $name"))
end

function _production_boundary(name::AbstractString)
    name == "periodic" && return PeriodicBoundary()
    name == "no_flux" && return ClosedBoundary()
    throw(ArgumentError("unknown transition-kernel boundary: $name"))
end

function _production_number_type(manifest)
    name = String(manifest["empirical_sampling"]["production_real_type"])
    name == "Float32" && return Float32
    name == "Float64" && return Float64
    throw(ArgumentError("unsupported transition-kernel production real type: $name"))
end

function build_transition_fixture(row;
        manifest::AbstractDict = load_transition_manifest())
    fixture = row.fixture
    fixture["dimension"] in (2, 3) || throw(ArgumentError(
        "production transition-kernel fixtures must be two- or three-dimensional"))
    fixture["acceptance_law"] == "conventional_metropolis" || throw(ArgumentError(
        "checkerboard transition-kernel fixtures require conventional Metropolis acceptance"))

    dims = Tuple(Int.(fixture["dimensions"]))
    length(dims) == fixture["dimension"] || throw(ArgumentError(
        "fixture dimension and dimensions disagree"))
    oracle_owners = parse_owner_encoding(row.source)
    length(oracle_owners) == prod(dims) || throw(ArgumentError(
        "fixture owner encoding does not fill its dimensions"))
    labels = unique(collect(oracle_owners))
    cell_ids = sort!(unique!(Int[owner.id for owner in labels
        if owner.kind === OracleCellKind]))
    medium_ids = sort!(unique!(vcat(Int[owner.id for owner in labels
        if owner.kind === OracleMediumKind], Int(manifest["model"]["medium_owner_id"]))))
    for id in medium_ids
        owner = oracle_medium(id)
        owner in labels || push!(labels, owner)
    end

    production_type = _production_number_type(manifest)
    spacing = ntuple(_ -> one(production_type), length(dims))
    offsets = _offsets(fixture["topology"], length(dims))
    proposal_relation = static_relation(ProposalRole(), offsets;
        spacing, symmetric = true)
    contact_relation = static_relation(ContactRole(), offsets;
        spacing, symmetric = true)
    surface_relation = static_relation(SurfaceRole(), offsets;
        spacing, symmetric = true)
    boundaries = Tuple(_production_boundary(String(name)) for name in fixture["boundaries"])
    production_domain = CartesianDomain(dims; spacing,
        boundaries = Tuple(AxisBoundary(boundary) for boundary in boundaries))

    model = manifest["model"]
    energy_scale = _parse_rational(fixture["energy_scale"])
    volume = QuadraticVolumeHamiltonian(number_type = production_type)
    base = production_type.(_parse_rational.(model["contact_matrix_base_row_major"]))
    contact_matrix = permutedims(reshape(base, 2, 2)) .* production_type(energy_scale)
    medium_types = MediumTypeTable(MediumID(id) => CellTypeID(model["medium_type_id"])
        for id in medium_ids)
    contact = UnorderedContactHamiltonian(contact_matrix, medium_types, contact_relation)
    owners = reshape(_production_owner.(collect(oracle_owners)), dims)
    state = LogicalPottsState(owners, CellCapacity(model["cell_capacity"]);
        cell_types = Dict(CellID(id) => CellTypeID(model["cell_type_id"]) for id in cell_ids),
        medium_domains = MediumID.(medium_ids), property_schema = required_properties(volume))
    for id in cell_ids
        property_values(state, :target_volume)[id] =
            production_type(_parse_rational(model["target_volume"]))
        property_values(state, :volume_strength)[id] = production_type(energy_scale)
    end
    boundary_tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface_relation)
    compiled = compile_state(state)
    scientific = nothing
    limitation = nothing
    try
        validate_relation_domain(production_domain, proposal_relation)
        validate_relation_domain(production_domain, contact_relation)
        validate_relation_domain(production_domain, surface_relation)
        scientific = compile_scientific_state(state, production_domain, boundary_tracker)
    catch error
        error isa ArgumentError || rethrow()
        limitation = sprint(showerror, error)
    end

    oracle_boundaries = Tuple(_oracle_boundary(String(name)) for name in fixture["boundaries"])
    oracle_domain = OracleDomain(dims; boundaries = oracle_boundaries)
    oracle_relation = OracleRelation(offsets)
    targets = Dict(id => _parse_rational(model["target_volume"]) for id in cell_ids)
    strengths = Dict(id => energy_scale for id in cell_ids)
    oracle_volume = OracleVolumeEnergy(targets, strengths)
    owner_types = Dict(owner => owner.kind === OracleCellKind ?
        Int(model["cell_type_id"]) : Int(model["medium_type_id"]) for owner in labels)
    oracle_contact = OracleContactEnergy(contact_matrix, owner_types, oracle_relation)
    temperature = _parse_rational(fixture["temperature"])
    oracle_model = OracleModel(oracle_relation, (oracle_volume, oracle_contact);
        temperature)
    oracle_state = OracleMicrostate(oracle_owners)
    catalog = enumerate_states(oracle_domain, labels)

    return TransitionFixture(String(fixture["id"]), String(row.source), temperature,
        production_type(temperature),
        production_domain, proposal_relation, contact_relation, surface_relation,
        boundary_tracker, volume, contact, state, compiled, scientific,
        scientific !== nothing, limitation,
        oracle_domain, oracle_model, oracle_state, catalog)
end

function oracle_kernel(fixture::TransitionFixture, algorithm::Symbol)
    algorithm === :sequential && return sequential_mcs_kernel(fixture.oracle_catalog,
        fixture.oracle_domain, fixture.oracle_model)
    algorithm === :checkerboard && return checkerboard_mcs_kernel(fixture.oracle_catalog,
        fixture.oracle_domain, fixture.oracle_model)
    throw(ArgumentError("unknown transition-kernel algorithm: $algorithm"))
end

end
