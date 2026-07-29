module RealisticScaleRunner

using Statistics
using TOML
using Random
using CorePotts
using PottsToolkit
using KernelAbstractions
using ..TransitionEmpirical

export load_realistic_manifest, realistic_workload, build_realistic_problem,
       realistic_identity_applicable, derive_replica_seeds, run_realistic_replica

const DEFAULT_MANIFEST = normpath(joinpath(@__DIR__, "..", "..", "design", "audits",
    "phase-13-realistic-workload-manifest.toml"))

load_realistic_manifest(path::AbstractString = DEFAULT_MANIFEST) = TOML.parsefile(path)

function realistic_workload(id::AbstractString,
        manifest::AbstractDict = load_realistic_manifest())
    index = findfirst(workload -> workload["id"] == id, manifest["workloads"])
    index === nothing && throw(ArgumentError("unknown transition-kernel realistic workload: $id"))
    return manifest["workloads"][index]
end

"""Whether an algorithm/backend pair belongs to the registered realistic qualification domain."""
function realistic_identity_applicable(algorithm, backend,
        manifest::AbstractDict = load_realistic_manifest())
    algorithm_name = String(algorithm)
    backend_name = lowercase(String(backend))
    if !haskey(manifest, "qualification_identities")
        return algorithm_name in String.(manifest["algorithms"]) &&
            backend_name in lowercase.(String.(manifest["backends"]))
    end
    identities = manifest["qualification_identities"]
    return any(identity -> identity["algorithm"] == algorithm_name &&
        backend_name in lowercase.(String.(identity["backends"])), identities)
end

const _LAYOUT_SEED_TAG = UInt64(0x13a70113a70113a7)
const _DYNAMICS_SEED_TAG = UInt64(0x13d90113d90113d9)

function _splitmix64(value::UInt64)
    value += UInt64(0x9e3779b97f4a7c15)
    value = xor(value, value >> 30) * UInt64(0xbf58476d1ce4e5b9)
    value = xor(value, value >> 27) * UInt64(0x94d049bb133111eb)
    return xor(value, value >> 31)
end

"""Derive independent, stable layout and dynamics seeds from one replica identity."""
function derive_replica_seeds(replica_seed::Integer)
    0 <= replica_seed <= typemax(UInt64) || throw(ArgumentError(
        "replica seed must fit UInt64"))
    identity = UInt64(replica_seed)
    return (; layout = _splitmix64(xor(identity, _LAYOUT_SEED_TAG)),
        dynamics = _splitmix64(xor(identity, _DYNAMICS_SEED_TAG)))
end

function _jittered_block_layout(workload, authoring_model, model_data, layout_seed)
    dims = Tuple(Int.(workload["dimensions"]))
    cells = Int(workload["cell_count"])
    iseven(cells) || throw(ArgumentError("two-population workload requires an even cell count"))
    grid_side = isqrt(cells)
    grid_side^2 == cells || throw(ArgumentError(
        "registered jittered block layouts require a square cell count"))
    sites_per_cell = round(Int, model_data["target_volume"])
    block_side = isqrt(sites_per_cell)
    block_side^2 == sites_per_cell || throw(ArgumentError(
        "registered square blocks require a square integer target volume"))
    all(dimension -> dimension % grid_side == 0, dims) || throw(ArgumentError(
        "each lattice dimension must be divisible by the layout grid side"))
    spacing = ntuple(axis -> dims[axis] ÷ grid_side, 2)
    jitter = ntuple(axis -> fld(spacing[axis] - block_side, 2), 2)
    all(>=(1), jitter) || throw(ArgumentError(
        "registered blocks require at least one lattice site of jitter clearance"))
    labels = zeros(UInt64, dims)
    rng = Xoshiro(UInt64(layout_seed))
    for row in 1:grid_side, column in 1:grid_side
        identity = (row - 1) * grid_side + column
        slot = (row, column)
        start = ntuple(axis -> begin
            centered = (slot[axis] - 1) * spacing[axis] +
                fld(spacing[axis] - block_side, 2) + 1
            centered + rand(rng, -jitter[axis]:jitter[axis])
        end, 2)
        ranges = ntuple(axis -> start[axis]:(start[axis] + block_side - 1), 2)
        all(iszero, @view labels[ranges...]) || error(
            "registered jittered blocks unexpectedly overlap")
        labels[ranges...] .= UInt64(identity)
    end
    populations = Tuple(value for value in authoring_model.declarations
        if value isa PottsToolkit.CellType)
    assignment = workload["type_assignment"]
    declarations = Pair{UInt64, PottsToolkit.CellType}[]
    for row in 1:grid_side, column in 1:grid_side
        identity = (row - 1) * grid_side + column
        population = if assignment == "checkerboard_two_type"
            1 + mod(row + column, 2)
        elseif assignment == "alternating"
            1 + mod(identity - 1, 2)
        else
            throw(ArgumentError("unsupported two-population assignment: $assignment"))
        end
        push!(declarations, UInt64(identity) => populations[population])
    end
    return PottsToolkit.CellLabelLayout(labels, declarations)
end

function _sorting_problem(workload, layout_seed, dynamics_seed, manifest)
    dims = Tuple(Int.(workload["dimensions"]))
    cells = Int(workload["cell_count"])
    model_data = manifest["model"]
    interactions = reshape(Float64.(model_data["contact_matrix_row_major"]), 3, 3)'
    model = PottsToolkit.ReferenceModels.differential_adhesion_model(
        target_volume = model_data["target_volume"],
        volume_strength = model_data["volume_strength"],
        medium_contact = interactions[1, 2],
        within_a = interactions[2, 2], within_b = interactions[3, 3],
        between = interactions[2, 3])
    layout = _jittered_block_layout(workload, model, model_data, layout_seed)
    return PottsToolkit.problem(model, dims, layout; capacity = cells,
        tspan = (0, Int(workload["burn_in_mcs"]) + Int(workload["measured_mcs"])),
        seed = dynamics_seed)
end

function _migration_problem(workload, dynamics_seed, manifest)
    dims = Tuple(Int.(workload["dimensions"]))
    model_data = manifest["model"]
    medium = PottsToolkit.Medium(:Medium)
    cell = PottsToolkit.CellType(:MigratingCell)
    volume = PottsToolkit.Volume(cell => (
        target = model_data["target_volume"], strength = model_data["volume_strength"]))
    interactions = reshape(Float64.(model_data["contact_matrix_row_major"]), 3, 3)'
    law = PottsToolkit.PairwiseLaw(:contact_energy,
        (medium, medium) => interactions[1, 1],
        (medium, cell) => interactions[1, 2],
        (cell, cell) => interactions[2, 2])
    authoring_model = PottsToolkit.PottsModel(medium, cell, volume,
        PottsToolkit.Adhesion(law))
    mask = falses(dims)
    side = max(1, round(Int, sqrt(model_data["target_volume"])))
    starts = ntuple(axis -> max(1, fld(dims[axis] - side, 2) + 1), 2)
    mask[starts[1]:(starts[1] + side - 1), starts[2]:(starts[2] + side - 1)] .= true
    return PottsToolkit.problem(authoring_model, dims,
        PottsToolkit.CellLayout(cell, 1, mask); capacity = 1,
        tspan = (0, Int(workload["burn_in_mcs"]) + Int(workload["measured_mcs"])),
        seed = dynamics_seed)
end

function build_realistic_problem(workload::AbstractDict, replica_seed::Integer;
        manifest::AbstractDict = load_realistic_manifest())
    seeds = derive_replica_seeds(replica_seed)
    id = workload["id"]
    if id in ("adhesion_volume_relaxation", "differential_adhesion_sorting")
        return _sorting_problem(workload, seeds.layout, seeds.dynamics, manifest)
    elseif id == "single_cell_migration"
        return _migration_problem(workload, seeds.dynamics, manifest)
    end
    throw(ArgumentError("unsupported transition-kernel realistic workload: $id"))
end

function _algorithm(value, temperature)
    text = lowercase(String(value))
    text in ("sequential", "sequentialcpm") &&
        return CorePotts.SequentialCPM(temperature = Float32(temperature))
    text in ("checkerboard", "checkerboardsweepcpm") &&
        return CorePotts.CheckerboardSweepCPM(temperature = Float32(temperature))
    throw(ArgumentError("unknown realistic-scale algorithm: $value"))
end

function _global_energy(integrator, state)
    domain = integrator.prob.geometry
    result = 0.0
    for component in integrator.inner.components.energies
        value = if applicable(CorePotts.global_energy, component, state, domain)
            CorePotts.global_energy(component, state, domain)
        elseif applicable(CorePotts.global_energy, component, state)
            CorePotts.global_energy(component, state)
        else
            throw(ArgumentError("no global energy implementation for $(typeof(component))"))
        end
        result += Float64(value)
    end
    return result
end

function _volume_summary(state)
    volumes = Float64[CorePotts.finite_volume(state, id)
        for id in CorePotts.active_cell_ids(state)]
    isempty(volumes) && return (; mean = 0.0, standard_deviation = 0.0,
        coefficient_of_variation = 0.0)
    average = mean(volumes)
    deviation = length(volumes) == 1 ? 0.0 : std(volumes)
    return (; mean = average, standard_deviation = deviation,
        coefficient_of_variation = iszero(average) ? 0.0 : deviation / average)
end

function _boundary_summary(integrator, state)
    values = CorePotts.rebuild_tracker(CorePotts.boundary_tracker(integrator.prob.model),
        state, integrator.prob.geometry)
    active = Int[CorePotts.value(id) for id in CorePotts.active_cell_ids(state)]
    selected = Float64[values[index] for index in active]
    isempty(selected) && return (; mean = 0.0, standard_deviation = 0.0)
    return (; mean = mean(selected),
        standard_deviation = length(selected) == 1 ? 0.0 : std(selected))
end

function _sorting_summary(integrator, state)
    domain = integrator.prob.geometry
    relation = CorePotts.proposal_relation(integrator.prob.model)
    heterotypic = 0
    finite_edges = 0
    for site in eachindex(CorePotts.lattice_storage(state))
        left = CorePotts.owner_at(state, site)
        CorePotts.is_cell_owner(left) || continue
        for direction in 1:CorePotts.direction_count(relation)
            neighbor = CorePotts.realize_neighbor(domain, relation, site, direction)
            neighbor.kind === CorePotts.MutableNeighbor || continue
            Int(neighbor.site) > site || continue
            right = CorePotts.owner_at(state, Int(neighbor.site))
            CorePotts.is_cell_owner(right) || continue
            finite_edges += 1
            left_type = CorePotts.cell_type(state, CorePotts.cell_id(left))
            right_type = CorePotts.cell_type(state, CorePotts.cell_id(right))
            left_type == right_type || (heterotypic += 1)
        end
    end
    fraction = iszero(finite_edges) ? 0.0 : heterotypic / finite_edges
    return (; heterotypic_contact_fraction = fraction,
        segregation_index = 1 - fraction, finite_contact_edges = finite_edges)
end

function _cell_center(state, id::CorePotts.CellID)
    dims = CorePotts.lattice_size(state)
    coordinates = Tuple{Int, Int}[]
    for site in eachindex(CorePotts.lattice_storage(state))
        CorePotts.owner_at(state, site) == CorePotts.CellOwner(id) || continue
        push!(coordinates, Tuple(CartesianIndices(dims)[site]))
    end
    isempty(coordinates) && return (NaN, NaN)
    return ntuple(2) do axis
        angles = 2pi .* (getindex.(coordinates, axis) .- 1) ./ dims[axis]
        angle = atan(mean(sin.(angles)), mean(cos.(angles)))
        1 + mod(angle, 2pi) * dims[axis] / (2pi)
    end
end

function _wrapped_displacement(first, last, dims)
    return ntuple(axis -> begin
        delta = last[axis] - first[axis]
        delta > dims[axis] / 2 && (delta -= dims[axis])
        delta < -dims[axis] / 2 && (delta += dims[axis])
        delta
    end, 2)
end

function _mixing_time(energies, cadence, terminal_window)
    isempty(energies) && return 0
    window = min(terminal_window, length(energies))
    rolling = [mean(@view energies[max(1, index - window + 1):index])
        for index in eachindex(energies)]
    target = last(rolling)
    tolerance = 0.05 * max(abs(target), eps(Float64))
    for index in eachindex(rolling)
        all(abs(value - target) <= tolerance for value in @view rolling[index:end]) &&
            return index * cadence
    end
    return length(energies) * cadence
end

function run_realistic_replica(workload::AbstractDict, algorithm_value;
        seed::Integer, backend = KernelAbstractions.CPU(),
        manifest::AbstractDict = load_realistic_manifest())
    problem = build_realistic_problem(workload, seed; manifest)
    derived_seeds = derive_replica_seeds(seed)
    algorithm = _algorithm(algorithm_value, manifest["model"]["temperature"])
    integrator = CorePotts.SciMLBase.init(problem, algorithm; backend,
        save_start = false, save_end = false)
    initial_checkpoint = CorePotts.capture_checkpoint(integrator.inner)
    model_fingerprint = bytes2hex(collect(initial_checkpoint.model_fingerprint))
    initial_state_fingerprint = bytes2hex(
        collect(initial_checkpoint.initial_state_fingerprint))
    burn_in = Int(workload["burn_in_mcs"])
    measured = Int(workload["measured_mcs"])
    cadence = Int(workload["observation_cadence_mcs"])
    measured % cadence == 0 || throw(ArgumentError(
        "measured MCS must be divisible by observation cadence"))
    CorePotts.SciMLBase.step!(integrator, burn_in)

    energies = Float64[]
    volume_cv = Float64[]
    boundary_mean = Float64[]
    heterotypic = Float64[]
    segregation = Float64[]
    centers = Tuple{Float64, Float64}[]
    sync_before = integrator.inner.plan.metrics.host_synchronizations
    transfer_before = integrator.inner.plan.metrics.device_to_host_transfers
    elapsed = @elapsed for _ in 1:(measured ÷ cadence)
        CorePotts.SciMLBase.step!(integrator, cadence)
        state = CorePotts.logical_state(integrator)
        active_count = length(CorePotts.active_cell_ids(state))
        active_count == Int(workload["cell_count"]) || error(
            "realistic workload retired finite cells during its registered observation window")
        push!(energies, _global_energy(integrator, state) / prod(workload["dimensions"]))
        volume = _volume_summary(state)
        boundary = _boundary_summary(integrator, state)
        push!(volume_cv, volume.coefficient_of_variation)
        push!(boundary_mean, boundary.mean)
        if workload["id"] == "differential_adhesion_sorting"
            sorting = _sorting_summary(integrator, state)
            push!(heterotypic, sorting.heterotypic_contact_fraction)
            push!(segregation, sorting.segregation_index)
        elseif workload["id"] == "single_cell_migration"
            push!(centers, _cell_center(state, CorePotts.CellID(1)))
        end
    end
    observations = length(energies)
    syncs = integrator.inner.plan.metrics.host_synchronizations - sync_before
    syncs == observations || error(
        "realistic runner synchronized outside declared observation boundaries")
    transfers = integrator.inner.plan.metrics.device_to_host_transfers - transfer_before
    maximum_lag = min(Int(manifest["analysis"]["maximum_autocorrelation_lag"]),
        max(1, observations - 1))
    energy_tau = observations >= 4 ? integrated_autocorrelation_time(energies;
        maximum_lag) : 1.0
    morphology_tau = observations >= 4 ? integrated_autocorrelation_time(volume_cv;
        maximum_lag) : 1.0
    result = Dict{String, Any}(
        "workload" => workload["id"],
        "algorithm" => string(nameof(typeof(algorithm))),
        "backend" => string(nameof(typeof(backend))),
        "model_fingerprint" => string("sha256:", model_fingerprint),
        "initial_state_fingerprint" => string("sha256:", initial_state_fingerprint),
        "seed_hex" => string("0x", string(UInt64(seed); base = 16, pad = 16)),
        "layout_seed_hex" => string("0x",
            string(derived_seeds.layout; base = 16, pad = 16)),
        "dynamics_seed_hex" => string("0x",
            string(derived_seeds.dynamics; base = 16, pad = 16)),
        "burn_in_mcs" => burn_in,
        "measured_mcs" => measured,
        "observation_cadence_mcs" => cadence,
        "observation_count" => observations,
        "observation_synchronizations" => syncs,
        "device_to_host_transfers" => transfers,
        "elapsed_measured_seconds" => elapsed,
        "measured_mcs_per_second" => measured / elapsed,
        "energy_per_mutable_site_mean" => mean(energies),
        "energy_per_mutable_site_terminal" => last(energies),
        "volume_coefficient_of_variation_mean" => mean(volume_cv),
        "boundary_measure_mean" => mean(boundary_mean),
        "energy_integrated_autocorrelation_time" => energy_tau,
        "morphology_integrated_autocorrelation_time" => morphology_tau,
        "energy_effective_sample_size" => observations / energy_tau,
        "morphology_effective_sample_size" => observations / morphology_tau,
        "mixing_time_mcs" => _mixing_time(energies, cadence,
            Int(manifest["analysis"]["terminal_window_observations"])))
    if !isempty(heterotypic)
        result["heterotypic_contact_fraction_mean"] = mean(heterotypic)
        result["heterotypic_contact_fraction_terminal"] = last(heterotypic)
        result["segregation_index_mean"] = mean(segregation)
        result["segregation_index_terminal"] = last(segregation)
        if length(heterotypic) >= 4
            sorting_tau = integrated_autocorrelation_time(heterotypic; maximum_lag)
            result["sorting_integrated_autocorrelation_time"] = sorting_tau
            result["sorting_effective_sample_size"] = observations / sorting_tau
        end
    end
    if length(centers) >= 2
        dims = Tuple(Int.(workload["dimensions"]))
        displacement = _wrapped_displacement(first(centers), last(centers), dims)
        steps = [_wrapped_displacement(centers[index - 1], centers[index], dims)
            for index in 2:length(centers)]
        distances = [hypot(step...) for step in steps]
        result["net_displacement"] = hypot(displacement...)
        result["mean_squared_displacement"] = mean(sum(abs2, step) for step in steps)
        result["speed"] = mean(distances) / cadence
        result["persistence"] = sum(distances) == 0 ? 0.0 :
            hypot(displacement...) / sum(distances)
        if length(distances) >= 4
            velocity_tau = integrated_autocorrelation_time(distances;
                maximum_lag = min(maximum_lag, length(distances) - 1))
            result["velocity_integrated_autocorrelation_time"] = velocity_tau
            result["velocity_effective_sample_size"] = length(distances) / velocity_tau
        end
    end
    return result
end

end
