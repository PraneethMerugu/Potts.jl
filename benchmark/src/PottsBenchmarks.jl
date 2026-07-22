module PottsBenchmarks

include("Phase12Comparison.jl")

using Adapt
using BenchmarkTools
using CorePotts
using Dates
using KernelAbstractions
using SHA
using SciMLBase
using StaticArrays
using Statistics
using TOML
import PottsToolkit
import CorePotts: LegacyPottsProblem, PottsState, PottsParameters, PottsCache,
                  SequentialMetropolis, ParallelMetropolis, CheckerboardMetropolis,
                  IntrinsicCheckerboardMetropolis

struct Phase10QualificationEnergy{T <: AbstractFloat} <: AbstractEnergy
    value::T
end
CorePotts.component_identity(::Phase10QualificationEnergy) =
    ComponentIdentity(:phase10_qualification_energy, v"1.0.0", :energy)
CorePotts.energy_change(component::Phase10QualificationEnergy,
    proposal::CopyProposal, state::LogicalPottsState) = component.value
CorePotts.proposal_energy_change(component::Phase10QualificationEnergy,
    proposal::CopyProposal, context::ScientificProposalContext) = component.value
CorePotts.scientific_access(::Phase10QualificationEnergy) = SnapshotScientificAccess()
CorePotts.component_semantic_data(component::Phase10QualificationEnergy) =
    (value = component.value,)

# A downstream package's polished Level 1 constructor is ordinary Julia. The returned component
# enters PottsToolkit through CorePotts's public scientific protocol and needs no central registry.
Phase11ExtensionEnergy(value::Real) = Phase10QualificationEnergy(Float32(value))

const SCHEMA_VERSION = "1.0.0"
const PHASE10_SCHEMA_VERSION = "2.1.0"
const PHASE12_WORKLOAD_SET_VERSION = "paper-core-1.0.0"
const HARNESS_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const REPOSITORY_ROOT = normpath(get(
    ENV, "POTTS_BENCHMARK_SUBJECT_ROOT", HARNESS_ROOT))
const RESULTS_ROOT = joinpath(REPOSITORY_ROOT, "benchmark", "results")

struct LifecycleQualificationDouble{Key} <: AbstractLifecycleEffect end
LifecycleQualificationDouble(key::Symbol) = LifecycleQualificationDouble{key}()
CorePotts.compiled_effect_category(::LifecycleQualificationDouble) = CompiledCustomEffect()
function CorePotts.compiled_apply_effect!(::LifecycleQualificationDouble{Key}, state,
        cell, properties, mcs, rng, seed) where {Key}
    values = getproperty(state.core.properties, Key)
    @inbounds values[cell] *= 2
    return nothing
end

struct InitializationQualificationLayout{N, S <: Tuple} <: AbstractInitialLayout
    provisional_id::ProvisionalCellID
    cell_type::CellTypeID
    sites::S
end
function InitializationQualificationLayout(provisional_id::ProvisionalCellID,
        cell_type::CellTypeID, sites::Tuple{Vararg{CartesianIndex{N}}}) where {N}
    return InitializationQualificationLayout{N, typeof(sites)}(
        provisional_id, cell_type, sites)
end
CorePotts.initial_layout_requirements(::InitializationQualificationLayout{N}) where {N} =
    InitialLayoutRequirements(N)
function CorePotts.emit_initial_claims!(collector::InitialClaimCollector{N},
        layout::InitializationQualificationLayout{N}) where {N}
    declare_initial_cell!(collector, layout.provisional_id, layout.cell_type)
    for site in layout.sites
        emit_initial_cell_claim!(collector, site, layout.provisional_id)
    end
    return collector
end

struct LifecycleQualificationOddMCS <: AbstractMCSSchedule end
CorePotts.is_due(::LifecycleQualificationOddMCS, mcs::Integer) =
    mcs > 0 ? isodd(mcs) : throw(ArgumentError("MCS must be positive"))
@inline CorePotts.compiled_schedule_due(
    ::LifecycleQualificationOddMCS, mcs::UInt64) = isodd(mcs)

struct LifecycleQualificationAtLeast{Key, T} <: AbstractLifecycleTrigger
    threshold::T
end
LifecycleQualificationAtLeast(key::Symbol, threshold::T) where {T} =
    LifecycleQualificationAtLeast{key, T}(threshold)
function CorePotts.lifecycle_triggered(
        trigger::LifecycleQualificationAtLeast{Key}, snapshot::PreLifecycleSnapshot,
        id::CellID) where {Key}
    return property_value(snapshot.state, Key, id) >= trigger.threshold
end
@inline function CorePotts.compiled_lifecycle_triggered(
        trigger::LifecycleQualificationAtLeast{Key}, state, cell, mcs,
        rng, seed, event_id) where {Key}
    return @inbounds(getproperty(state.core.properties, Key)[cell]) >= trigger.threshold
end

struct LifecycleQualificationOffsetPlane <: AbstractDivisionGeometry
    offset::Float32
end
@inline function CorePotts.division_region(geometry::LifecycleQualificationOffsetPlane,
        context::DivisionSiteContext)
    return context.coordinate[1] - context.center[1] < geometry.offset ? UInt8(1) : UInt8(2)
end

struct LifecycleQualificationVolumeSplit <: AbstractDivisionPolicy end
function CorePotts.division_property_update(::LifecycleQualificationVolumeSplit,
        descriptor, value, context::DivisionPropertyContext)
    child = convert(typeof(value), context.child_volume)
    return DivisionPropertyUpdate(value - child, child)
end
@inline function CorePotts.compiled_division_property_update(
        ::LifecycleQualificationVolumeSplit, value, default,
        context::DivisionPropertyContext)
    child = convert(typeof(value), context.child_volume)
    return DivisionPropertyUpdate(value - child, child)
end

struct LifecycleQualificationSiteSumTracker end
struct LifecycleQualificationSiteSumStorage{A}
    values::A
end
struct LifecycleQualificationSiteSumDelta
    site::Int64
end

Adapt.adapt_structure(to, storage::LifecycleQualificationSiteSumStorage) =
    LifecycleQualificationSiteSumStorage(Adapt.adapt(to, storage.values))

function CorePotts.rebuild_tracker(::LifecycleQualificationSiteSumTracker,
        state::LogicalPottsState, domain::CartesianDomain)
    values = zeros(Int64, nslots(capacity(state)))
    for site in eachindex(lattice_storage(state))
        owner = owner_at(state, site)
        is_cell_owner(owner) && (values[Int(value(cell_id(owner)))] += Int64(site))
    end
    return LifecycleQualificationSiteSumStorage(values)
end
CorePotts.compile_derived_observable(tracker::LifecycleQualificationSiteSumTracker,
    state, domain) = rebuild_tracker(tracker, state, domain)
CorePotts.derived_observable_arrays(storage::LifecycleQualificationSiteSumStorage) =
    (storage.values,)
@inline CorePotts.stage_derived_observable_delta(
    ::LifecycleQualificationSiteSumTracker, state, proposal) =
    LifecycleQualificationSiteSumDelta(Int64(proposal.recipient))
@inline function CorePotts.apply_derived_observable_delta!(
        storage::LifecycleQualificationSiteSumStorage,
        moments::LifecycleQualificationSiteSumDelta, delta)
    delta.losing_cell != 0 &&
        (@inbounds storage.values[Int(delta.losing_cell)] -= moments.site)
    delta.gaining_cell != 0 &&
        (@inbounds storage.values[Int(delta.gaining_cell)] += moments.site)
    return nothing
end
@inline function CorePotts.compiled_prepare_derived_division!(
        storage::LifecycleQualificationSiteSumStorage, state, parent, child)
    @inbounds begin
        storage.values[parent] = Int64(0)
        storage.values[child] = Int64(0)
    end
    return nothing
end
@inline function CorePotts.compiled_accumulate_derived_division!(
        storage::LifecycleQualificationSiteSumStorage, context, state, site,
        label, parent, child)
    destination = label == UInt8(1) ? parent : child
    @inbounds storage.values[destination] += Int64(site)
    return nothing
end
@inline function CorePotts.compiled_retire_derived!(
        storage::LifecycleQualificationSiteSumStorage, state, cell)
    @inbounds storage.values[cell] = Int64(0)
    return nothing
end

@kernel function _semantic_rng_probe!(output, addresses, contract, seed)
    index = @index(Global, Linear)
    if index <= length(addresses)
        words = rng_words(contract, seed, addresses[index])
        base = 4 * (index - 1)
        output[base + 1] = words[1]
        output[base + 2] = words[2]
        output[base + 3] = words[3]
        output[base + 4] = words[4]
    end
end

@kernel function _semantic_distribution_probe!(floating_output, integer_output,
        addresses, table, contract, seed)
    index = @index(Global, Linear)
    if index <= length(addresses)
        address = addresses[index]
        floating_output[2 * index - 1] = uniform_open01(Float32, contract, seed, address)
        floating_output[2 * index] = normal_box_muller(Float32, contract, seed, address)
        integer_output[5 * index - 4] = Int32(bounded_uint(
            contract, seed, address, UInt32(17)))
        integer_output[5 * index - 3] = Int32(categorical_index(
            table, contract, seed, address))
        integer_output[5 * index - 2] = bernoulli(
            contract, seed, address, 0.375f0) ? Int32(1) : Int32(0)
        integer_output[5 * index - 1] = Int32(poisson_inversion(
            contract, seed, address, 4.0f0))
        integer_output[5 * index] = Int32(poisson_normal_approx(
            contract, seed, address, 100.0f0))
    end
end

@kernel function _semantic_permutation_probe!(output, addresses, contract, seed)
    index = @index(Global, Linear)
    if index <= length(addresses)
        permutation = MVector{8, UInt16}(undef)
        small_permutation!(permutation, contract, seed, addresses[index])
        base = 8 * (index - 1)
        for element in 1:8
            @inbounds output[base + element] = permutation[element]
        end
    end
end

@kernel function _semantic_float64_probe!(floating_output, poisson_output,
        addresses, contract, seed)
    index = @index(Global, Linear)
    if index <= length(addresses)
        address = addresses[index]
        floating_output[2 * index - 1] = uniform_open01(Float64, contract, seed, address)
        floating_output[2 * index] = normal_box_muller(Float64, contract, seed, address)
        poisson_output[index] = Int32(poisson_inversion(
            contract, seed, address, 4.0))
    end
end

@kernel function _execution_stage_one!(output, input)
    index = @index(Global, Linear)
    @inbounds output[index] = input[index] + UInt32(1)
end

@kernel function _execution_stage_two!(output, input)
    index = @index(Global, Linear)
    @inbounds output[index] = input[index] * UInt32(2)
end

@kernel function _scientific_phase6_probe!(output, metadata, state, proposal_relation,
        components, transaction, recipient, direction)
    index = @index(Global, Linear)
    if index == 1
        attempt = construct_copy_attempt(
            state, state.domain, proposal_relation, recipient, direction)
        metadata[1] = UInt32(attempt.outcome)
        metadata[2] = attempt.forward_multiplicity
        metadata[3] = attempt.reverse_multiplicity
        if is_actionable(attempt)
            proposal = actionable_proposal(attempt)
            volume = components.energies[1]
            contact = components.energies[2]
            boundary = components.energies[3]
            field_energy = components.energies[4]
            focal = components.energies[5]
            drive = components.drives[1]
            output[1] = energy_change(volume, proposal, state)
            output[2] = energy_change(contact, proposal, state, state.domain)
            output[3] = energy_change(boundary, proposal, state)
            output[4] = energy_change(field_energy, proposal, state, state.domain)
            output[5] = drive_log_bias(drive, proposal, state, state.domain)
            output[6] = energy_change(focal, proposal, state, transaction)
        end
    end
end

@kernel function _scientific_evaluation_probe!(output, metadata, state, components,
        proposal, transaction, connectivity_workspace)
    index = @index(Global, Linear)
    if index == 1
        context = ScientificProposalContext(
            state, transaction, connectivity_workspace, UInt32(4))
        evaluation = evaluate_copy(components, proposal, context, Float32)
        output[1] = evaluation.delta_h
        output[2] = evaluation.drive_log_bias
        output[3] = evaluation.kinetic_modifier
        output[4] = evaluation.yield_barrier
        metadata[1] = evaluation.constraints_allowed ? UInt32(1) : UInt32(0)
    end
end

@kernel function _scientific_query_probe!(output, metadata, state, connectivity,
        connectivity_proposal, connectivity_workspace, query_relation,
        medium_types, neighbor_workspace)
    index = @index(Global, Linear)
    if index == 1
        metadata[1] = is_allowed(connectivity, connectivity_proposal, state,
            connectivity_workspace, UInt32(1)) ? UInt32(1) : UInt32(0)
        metadata[2] = UInt32(contact_edge_count(state, state.domain, query_relation,
            CellOwner(1), AnyFiniteCell(), medium_types))
        metadata[3] = UInt32(boundary_site_count(state, state.domain, query_relation,
            CellOwner(1), AnyFiniteCell(), medium_types))
        output[1] = contact_measure(state, state.domain, query_relation,
            CellOwner(1), AnyFiniteCell(), medium_types)
        metadata[4] = UInt32(neighbor_cell_count(neighbor_workspace, state,
            state.domain, query_relation, CellOwner(1), AnyFiniteCell(), medium_types,
            UInt32(1)))
        output[2] = neighbor_property_sum(state, CellPropertyRef(:volume_strength),
            neighbor_workspace, state.domain, query_relation, CellOwner(1),
            AnyFiniteCell(), medium_types, UInt32(2))
        metadata[5] = UInt32(global_interface_measure(state, state.domain,
            query_relation, AnyFiniteCell(), AnyFiniteCell(),
            medium_types))
    end
end

@kernel function _normalized_surface_probe!(output, state, component, proposal)
    index = @index(Global, Linear)
    if index == 1
        output[1] = energy_change(component, proposal, state)
    end
end

function _backend_adaptor(name::String)
    name == "cpu" && return Array
    module_name = name == "metal" ? :Metal :
                  name == "cuda" ? :CUDA :
                  name == "amdgpu" ? :AMDGPU :
                  throw(ArgumentError(
        "Unknown backend `$name`"))
    isdefined(Main, module_name) ||
        error("$module_name must be loaded before RNG qualification")
    backend_module = getfield(Main, module_name)
    array_name = name == "metal" ? :MtlArray : name == "cuda" ? :CuArray : :ROCArray
    return getproperty(backend_module, array_name)
end

function _backend_array(name::String, values)
    name == "cpu" && return copy(values)
    return Base.invokelatest(_backend_adaptor(name), values)
end

"""Execute the Phase 5 raw-word probe and require exact CPU/backend identity."""
function qualify_rng_backend(name::String)
    contract = Philox4x32x10V1()
    seed = UInt64(0x706f7474732d7631)
    addresses = [RNGAddress(stream = ProposalDirectionStream, mcs = 11,
                     subround = 3, operation = 7, entity_kind = SiteEntity, entity = index,
                     invocation = 2, draw = 5) for index in 1:257]
    expected = reduce(vcat, collect(rng_words(contract, seed, address))
    for address in addresses)
    device_addresses = _backend_array(name, addresses)
    output = similar(device_addresses, UInt32, 4 * length(addresses))
    backend = KernelAbstractions.get_backend(device_addresses)
    kernel = _semantic_rng_probe!(backend, 128)
    kernel(output, device_addresses, contract, seed; ndrange = length(addresses))
    KernelAbstractions.synchronize(backend)
    observed = Array(output)
    observed == expected || error("$name Philox words differ from the CPU contract")

    distribution_addresses = [RNGAddress(stream = AuxiliaryEvolutionStream, mcs = 23,
                                  subround = 2, operation = 9,
                                  entity_kind = SiteEntity, entity = index,
                                  draw = 11) for index in 1:4096]
    device_distribution_addresses = _backend_array(name, distribution_addresses)
    table = CategoricalTable((1.0f0, 2.0f0, 3.0f0))
    floating_output = similar(device_distribution_addresses, Float32,
        2 * length(distribution_addresses))
    integer_output = similar(device_distribution_addresses, Int32,
        5 * length(distribution_addresses))
    distribution_kernel = _semantic_distribution_probe!(backend, 128)
    distribution_kernel(
        floating_output, integer_output, device_distribution_addresses, table,
        contract, seed; ndrange = length(distribution_addresses))
    KernelAbstractions.synchronize(backend)
    observed_floating = Array(floating_output)
    observed_integer = Array(integer_output)
    expected_floating = Vector{Float32}(undef, 2 * length(distribution_addresses))
    expected_integer = Vector{Int32}(undef, 5 * length(distribution_addresses))
    for (index, address) in pairs(distribution_addresses)
        expected_floating[2 * index - 1] = uniform_open01(Float32, contract, seed, address)
        expected_floating[2 * index] = normal_box_muller(Float32, contract, seed, address)
        expected_integer[5 * index - 4] = Int32(bounded_uint(
            contract, seed, address, UInt32(17)))
        expected_integer[5 * index - 3] = Int32(categorical_index(
            table, contract, seed, address))
        expected_integer[5 * index - 2] = bernoulli(
            contract, seed, address, 0.375f0) ? Int32(1) : Int32(0)
        expected_integer[5 * index - 1] = Int32(poisson_inversion(
            contract, seed, address, 4.0f0))
        expected_integer[5 * index] = Int32(poisson_normal_approx(
            contract, seed, address, 100.0f0))
    end
    bitwise_indices = reduce(vcat,
        (5 * index - 4):(5 * index - 2) for index in eachindex(distribution_addresses))
    observed_integer[bitwise_indices] == expected_integer[bitwise_indices] || error(
        "$name bitwise discrete distribution outputs differ from the CPU contract")
    all(isapprox.(observed_floating, expected_floating; rtol = 8eps(Float32), atol = 0)) ||
        error("$name floating distribution outputs exceed the numerical profile")

    permutation_output = similar(device_distribution_addresses, UInt16,
        8 * length(distribution_addresses))
    permutation_kernel = _semantic_permutation_probe!(backend, 128)
    permutation_kernel(permutation_output, device_distribution_addresses, contract, seed;
        ndrange = length(distribution_addresses))
    KernelAbstractions.synchronize(backend)
    observed_permutations = Array(permutation_output)
    expected_permutations = similar(observed_permutations)
    for (index, address) in pairs(distribution_addresses)
        small_permutation!(view(expected_permutations, (8 * index - 7):(8 * index)),
            contract, seed, address)
    end
    observed_permutations == expected_permutations || error(
        "$name small permutations differ from the CPU contract")

    normals32 = observed_floating[2:2:end]
    poisson_exact32 = observed_integer[4:5:end]
    poisson_approx32 = observed_integer[5:5:end]
    abs(mean(normals32)) < 0.06 ||
        error("$name Float32 normal mean is outside qualification")
    abs(var(normals32) - 1) < 0.10 || error(
        "$name Float32 normal variance is outside qualification")
    abs(mean(poisson_exact32) - 4) < 0.12 || error(
        "$name exact Poisson mean is outside qualification")
    abs(var(poisson_exact32) - 4) < 0.25 || error(
        "$name exact Poisson variance is outside qualification")
    abs(mean(poisson_approx32) - 100) < 0.5 || error(
        "$name approximate Poisson mean is outside qualification")
    abs(var(poisson_approx32) - 100) < 5 || error(
        "$name approximate Poisson variance is outside qualification")

    capabilities = backend_capabilities(backend)
    float64_report = if capabilities.device_float64
        floating64 = similar(device_distribution_addresses, Float64,
            2 * length(distribution_addresses))
        poisson64 = similar(device_distribution_addresses, Int32,
            length(distribution_addresses))
        float64_kernel = _semantic_float64_probe!(backend, 128)
        float64_kernel(
            floating64, poisson64, device_distribution_addresses, contract, seed;
            ndrange = length(distribution_addresses))
        KernelAbstractions.synchronize(backend)
        observed64 = Array(floating64)
        poisson_observed64 = Array(poisson64)
        normal64 = observed64[2:2:end]
        abs(mean(normal64)) < 0.06 ||
            error("$name Float64 normal mean is outside qualification")
        abs(var(normal64) - 1) < 0.10 || error(
            "$name Float64 normal variance is outside qualification")
        abs(mean(poisson_observed64) - 4) < 0.12 || error(
            "$name Float64 Poisson mean is outside qualification")
        Dict("status" => "qualified", "samples" => length(distribution_addresses))
    else
        Dict("status" => "unsupported", "reason" => "backend capability forbids Float64")
    end
    return Dict(
        "backend" => name,
        "contract" => string(rng_contract_version(contract)),
        "addresses" => length(addresses),
        "raw_words" => length(observed),
        "bitwise_identity" => true,
        "bitwise_distributions" => ["bounded_uint", "bernoulli", "categorical",
            "small_permutation"],
        "statistical_distributions" => ["normal_box_muller", "poisson_inversion",
            "poisson_normal_approx"],
        "floating_distribution_tolerance" => "8eps(Float32)",
        "distribution_samples" => length(distribution_addresses),
        "float64" => float64_report
    )
end

"""Qualify ordered launches, one explicit observation, and reusable storage on one backend."""
function qualify_execution_backend(name::String)
    input_host = UInt32.(1:257)
    input = _backend_array(name, input_host)
    stage = similar(input)
    output = similar(input)
    backend = KernelAbstractions.get_backend(input)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    first_kernel = _execution_stage_one!(backend, 128)
    second_kernel = _execution_stage_two!(backend, 128)

    launch!(plan, first_kernel, stage, input; ndrange = length(input))
    launch!(plan, second_kernel, output, stage; ndrange = length(input))
    metrics.host_synchronizations == 0 || error(
        "$name execution pipeline synchronized before its observation boundary")
    synchronize_observation!(plan)
    observed = Array(output)
    expected = 2 .* (input_host .+ UInt32(1))
    observed == expected ||
        error("$name ordered execution pipeline produced incorrect output")

    state_metrics = ExecutionMetrics()
    state_plan = ExecutionPlan(backend; block_size = 128, metrics = state_metrics)
    logical = LogicalPottsState(fill(MediumOwner(1), 2, 2), CellCapacity(0);
        medium_domains = MediumID[MediumID(1)])
    compiled = compile_state(logical)
    adapted = adapt_execution(state_plan, _backend_adaptor(name), compiled)
    device_storage_valid(adapted.storage) || error(
        "$name adapted compiled state contains invalid or mixed-backend values")
    requirements = WorkspaceRequirements(4, 0;
        scratch_uint32 = 4, scratch_float32 = 0, flags = 0)
    allocate_workspace(state_plan, adapted, requirements)
    snapshot = logical_snapshot(state_plan, adapted)
    lattice_storage(snapshot) == lattice_storage(logical) || error(
        "$name compiled state does not round-trip to its logical snapshot")

    warm_launch_host_bytes = name == "cpu" ?
                             @allocated(launch!(
        plan, first_kernel, stage, input; ndrange = length(input))) : missing
    name == "cpu" && synchronize_observation!(plan)
    capabilities = plan.capabilities
    return Dict(
        "backend" => name,
        "family" => string(capabilities.family),
        "contract_status" => string(capabilities.contract_status),
        "functional" => capabilities.functional,
        "ordered_launches" => capabilities.ordered_launches,
        "declared_semantic_rng_v1" => v"1.0.0" in capabilities.qualified_rng_contracts,
        "launches_before_observation" => 2,
        "internal_host_synchronizations" => 0,
        "observation_synchronizations" => 1,
        "corepotts_steady_state_scratch_allocations" => 0,
        "backend_runtime_warm_launch_host_bytes" => warm_launch_host_bytes,
        "compiled_state_roundtrip" => true,
        "workspace_bytes" => workspace_bytes(requirements),
        "initialization_host_allocations" => state_metrics.host_allocations,
        "initialization_device_allocations" => state_metrics.device_allocations,
        "initialization_host_to_device_transfers" => state_metrics.host_to_device_transfers,
        "snapshot_device_to_host_transfers" => state_metrics.device_to_host_transfers,
        "snapshot_synchronizations" => state_metrics.host_synchronizations,
        "elements" => length(observed)
    )
end

function _phase6_fixture(::Val{N}) where {N}
    dims = ntuple(_ -> 4, Val(N))
    volume = QuadraticVolumeHamiltonian(number_type = Float32)
    spacing = ntuple(_ -> 1.0f0, Val(N))
    surface_relation = first_shell_relation(SurfaceRole(), Val(N); spacing)
    boundary = QuadraticBoundaryHamiltonian(BoundaryEdgeCount(), surface_relation;
        number_type = Float32)
    schema = merge_property_schemas(required_properties(volume), required_properties(boundary))
    owners = fill(MediumOwner(1), dims)
    first_base = ntuple(_ -> 1, Val(N))
    first_axis = Base.setindex(first_base, 2, 1)
    first_second_axis = Base.setindex(first_base, 2, 2)
    second_base = Base.setindex(first_base, 3, 1)
    second_axis = Base.setindex(first_base, 4, 1)
    second_second_axis = Base.setindex(second_base, 2, 2)
    owners[first_base...] = owners[first_axis...] = owners[first_second_axis...] = CellOwner(1)
    owners[second_base...] = owners[second_axis...] = owners[second_second_axis...] = CellOwner(2)
    logical = LogicalPottsState(owners, CellCapacity(2);
        cell_types = Dict(CellID(1) => CellTypeID(2), CellID(2) => CellTypeID(2)),
        medium_domains = [MediumID(1)], property_schema = schema)
    property_values(logical, :target_volume) .= 4.0f0
    property_values(logical, :volume_strength) .= 1.25f0
    property_values(logical, :target_boundary) .= 8
    property_values(logical, :boundary_strength) .= 0.75f0
    domain = CartesianDomain(dims; spacing)
    proposal_relation = first_shell_relation(ProposalRole(), Val(N);
        spacing = domain.spacing)
    contact_relation = first_shell_relation(ContactRole(), Val(N);
        spacing = domain.spacing)
    query_relation = first_shell_relation(SpatialQueryRole(), Val(N);
        spacing = domain.spacing, symmetric = true)
    connectivity_relation = first_shell_relation(ConnectivityRole(), Val(N);
        spacing = domain.spacing)
    contact = UnorderedContactHamiltonian(Float32[0 3; 3 1],
        MediumTypeTable(MediumID(1) => CellTypeID(1)), contact_relation)
    boundary_tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface_relation)
    moment_tracker = UnwrappedMomentTracker(
        connectivity_relation, (CellID(1), CellID(2)); number_type = Float32)
    compiled = compile_scientific_state(logical, domain, boundary_tracker; moment_tracker)
    coupling = OwnerScalarCoupling(:volume_strength, MediumID(1) => 0.0f0;
        number_type = Float32)
    field = CellCenteredField(reshape(Float32.(1:prod(dims)), dims);
        interpolation = NearestFieldInterpolation())
    field_energy = ExternalFieldOccupancyHamiltonian(field, coupling; energy_scale = 1.0f0)
    drive = ChemotaxisDrive(field, coupling, LinearResponse(), ExtensionChemotaxis())
    selected = nothing
    for recipient in eachindex(lattice_storage(logical))
        for direction in 1:direction_count(proposal_relation)
            candidate = construct_copy_attempt(
                logical, domain, proposal_relation, recipient, direction)
            if is_actionable(candidate)
                proposal = actionable_proposal(candidate)
                if is_medium_owner(proposal.losing) && is_cell_owner(proposal.gaining)
                    selected = (candidate, recipient, direction)
                    break
                end
            end
        end
        selected === nothing || break
    end
    selected === nothing &&
        error("internal Phase 6 qualification has no extension proposal")
    attempt, recipient, direction = selected
    proposal = actionable_proposal(attempt)
    transaction = stage_copy_transaction(
        compiled, boundary_tracker, proposal; moment_tracker)
    focal = FocalPointSpringHamiltonian(FocalPointLink(logical, CellID(1), CellID(2);
        strength = 1.25f0, target_length = 2.0f0))
    connectivity = PreserveConnectedCells(connectivity_relation)
    linear = LinearIndices(dims)
    bridge_recipient = linear[first_base...]
    bridge_donor = linear[second_axis...]
    connectivity_proposal = CopyProposal(bridge_recipient, bridge_donor,
        CellOwner(1), CellOwner(2))
    medium_types = MediumTypeTable(MediumID(1) => CellTypeID(1))
    return (; logical, domain, proposal_relation, volume, contact, boundary,
        boundary_tracker, moment_tracker, compiled, field_energy, drive, focal,
        proposal, transaction, recipient, direction, connectivity,
        connectivity_proposal, query_relation, medium_types,
        connectivity_workspace = ConnectivityWorkspace(prod(dims)),
        neighbor_workspace = DistinctNeighborWorkspace(nslots(capacity(logical))))
end

function _phase6_normalized_surface_fixture(::Val{N}) where {N}
    dims = ntuple(_ -> 6, Val(N))
    spacing = ntuple(_ -> 1.0f0, Val(N))
    domain = CartesianDomain(dims; spacing)
    relation = normalized_kernel_relation(Val(N); spacing = domain.spacing)
    metric = NormalizedKernelMeasure(domain, relation)
    component = QuadraticBoundaryHamiltonian(metric, relation;
        target = :target_normalized_boundary,
        strength = :normalized_boundary_strength, number_type = Float32)
    owners = fill(MediumOwner(1), dims)
    first = ntuple(_ -> 2, Val(N))
    second = Base.setindex(first, 3, 1)
    third = Base.setindex(first, 3, 2)
    owners[first...] = owners[second...] = owners[third...] = CellOwner(1)
    logical = LogicalPottsState(owners, CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)), medium_domains = [MediumID(1)],
        property_schema = required_properties(component))
    property_values(logical, :target_normalized_boundary)[1] = 5.0f0
    property_values(logical, :normalized_boundary_strength)[1] = 0.75f0
    proposal_relation = first_shell_relation(ProposalRole(), Val(N);
        spacing = domain.spacing)
    proposal = nothing
    for recipient in eachindex(lattice_storage(logical))
        for direction in 1:direction_count(proposal_relation)
            attempt = construct_copy_attempt(
                logical, domain, proposal_relation, recipient, direction)
            if is_actionable(attempt)
                proposal = actionable_proposal(attempt)
                break
            end
        end
        proposal === nothing || break
    end
    proposal === nothing && error(
        "internal Phase 6 normalized-surface qualification has no proposal")
    tracker = BoundaryMeasureTracker(metric, relation)
    compiled = compile_scientific_state(logical, domain, tracker)
    transaction = stage_copy_transaction(compiled, tracker, proposal)
    return (; logical, domain, component, tracker, compiled, proposal, transaction)
end

"""Qualify the Phase 6 proposal, component, field, and staged-commit device path."""
function qualify_scientific_backend(name::String)
    adaptor = _backend_adaptor(name)
    compiled_bytes = Dict{String, Int}()
    workspace_byte_counts = Dict{String, Int}()
    for N in (2, 3)
        fixture = _phase6_fixture(Val(N))
        normalized = _phase6_normalized_surface_fixture(Val(N))
        runtime = scientific_execution(fixture.compiled)
        oracle_neighbor_workspace = DistinctNeighborWorkspace(
            nslots(capacity(fixture.logical)))
        oracle_connectivity_workspace = ConnectivityWorkspace(prod(fixture.domain.dims))
        host_components = ScientificComponentSet(
            energies = (fixture.volume, fixture.contact, fixture.boundary,
                fixture.field_energy, fixture.focal),
            drives = (fixture.drive,),
            constraints = (fixture.connectivity,
                FixedFocalEndpointConstraint(fixture.focal)),
            kinetic_modifiers = (PositiveYield(0.75f0),)
        )
        oracle_context = ScientificProposalContext(runtime, fixture.transaction;
            connectivity_workspace = oracle_connectivity_workspace, workspace_epoch = 4)
        oracle_evaluation = evaluate_copy(
            host_components, fixture.proposal, oracle_context, Float32)
        expected_components = Float32[
            energy_change(fixture.volume, fixture.proposal, fixture.logical),
            energy_change(fixture.contact, fixture.proposal, fixture.logical, fixture.domain),
            energy_change(fixture.boundary, fixture.proposal, fixture.logical, fixture.domain),
            energy_change(fixture.field_energy, fixture.proposal, fixture.logical, fixture.domain),
            drive_log_bias(fixture.drive, fixture.proposal, fixture.logical, fixture.domain),
            energy_change(fixture.focal, fixture.proposal, fixture.compiled,
                fixture.transaction)
        ]
        expected_evaluation = Float32[
            oracle_evaluation.delta_h,
            oracle_evaluation.drive_log_bias,
            oracle_evaluation.kinetic_modifier,
            oracle_evaluation.yield_barrier
        ]
        expected_queries = Float32[
            contact_measure(runtime, runtime.domain, fixture.query_relation,
                CellOwner(1), AnyFiniteCell(), fixture.medium_types),
            neighbor_property_sum(runtime, CellPropertyRef(:volume_strength),
                oracle_neighbor_workspace, runtime.domain, fixture.query_relation,
                CellOwner(1), AnyFiniteCell(), fixture.medium_types, UInt32(2))
        ]
        expected_proposal_metadata = UInt32[
            1,
            fixture.proposal.forward_multiplicity,
            fixture.proposal.reverse_multiplicity
        ]
        expected_evaluation_metadata = UInt32[
            oracle_evaluation.constraints_allowed ? 1 : 0,
        ]
        expected_query_metadata = UInt32[
            is_allowed(fixture.connectivity, fixture.connectivity_proposal, runtime,
                oracle_connectivity_workspace, UInt32(1)) ? 1 : 0,
            contact_edge_count(runtime, runtime.domain, fixture.query_relation,
                CellOwner(1), AnyFiniteCell(), fixture.medium_types),
            boundary_site_count(runtime, runtime.domain, fixture.query_relation,
                CellOwner(1), AnyFiniteCell(), fixture.medium_types),
            neighbor_cell_count(oracle_neighbor_workspace, runtime, runtime.domain,
                fixture.query_relation, CellOwner(1), AnyFiniteCell(), fixture.medium_types,
                UInt32(3)),
            global_interface_measure(runtime, runtime.domain, fixture.query_relation,
                AnyFiniteCell(), AnyFiniteCell(), fixture.medium_types)
        ]
        adapted = Adapt.adapt(adaptor, fixture.compiled)
        scientific_storage_valid(adapted) || error(
            "$name adapted scientific state contains invalid or mixed-backend values")
        components = Adapt.adapt(adaptor, host_components)
        connectivity_workspace = Adapt.adapt(adaptor, fixture.connectivity_workspace)
        neighbor_workspace = Adapt.adapt(adaptor, fixture.neighbor_workspace)
        validate_workspace(connectivity_workspace, scientific_execution(adapted))
        validate_workspace(neighbor_workspace, scientific_execution(adapted))
        component_output = _backend_array(
            name, zeros(Float32, length(expected_components)))
        proposal_metadata = _backend_array(
            name, zeros(UInt32, length(expected_proposal_metadata)))
        evaluation_output = _backend_array(
            name, zeros(Float32, length(expected_evaluation)))
        evaluation_metadata = _backend_array(
            name, zeros(UInt32, length(expected_evaluation_metadata)))
        query_output = _backend_array(name, zeros(Float32, length(expected_queries)))
        query_metadata = _backend_array(
            name, zeros(UInt32, length(expected_query_metadata)))
        backend = KernelAbstractions.get_backend(component_output)
        probe = _scientific_phase6_probe!(backend, 1)
        probe(component_output, proposal_metadata, scientific_execution(adapted),
            fixture.proposal_relation, components, fixture.transaction,
            fixture.recipient, fixture.direction;
            ndrange = 1)
        evaluation_probe = _scientific_evaluation_probe!(backend, 1)
        evaluation_probe(evaluation_output, evaluation_metadata,
            scientific_execution(adapted), components, fixture.proposal,
            fixture.transaction, connectivity_workspace; ndrange = 1)
        query_probe = _scientific_query_probe!(backend, 1)
        query_probe(query_output, query_metadata, scientific_execution(adapted),
            fixture.connectivity, fixture.connectivity_proposal,
            connectivity_workspace, fixture.query_relation, fixture.medium_types,
            neighbor_workspace; ndrange = 1)
        KernelAbstractions.synchronize(backend)
        observed_components = Array(component_output)
        observed_evaluation = Array(evaluation_output)
        observed_queries = Array(query_output)
        all(isapprox.(observed_components, expected_components;
            rtol = 16eps(Float32), atol = 16eps(Float32))) || error(
            "$name Phase 6 $N-D component outputs differ from the CPU oracle")
        all(isapprox.(observed_evaluation, expected_evaluation;
            rtol = 16eps(Float32), atol = 16eps(Float32))) || error(
            "$name Phase 6 $N-D generic evaluation differs from the CPU oracle")
        all(isapprox.(observed_queries, expected_queries;
            rtol = 16eps(Float32), atol = 16eps(Float32))) || error(
            "$name Phase 6 $N-D query outputs differ from the CPU oracle")
        Array(proposal_metadata) == expected_proposal_metadata || error(
            "$name Phase 6 $N-D proposal metadata differs from the CPU oracle")
        Array(evaluation_metadata) == expected_evaluation_metadata || error(
            "$name Phase 6 $N-D evaluation metadata differs from the CPU oracle")
        Array(query_metadata) == expected_query_metadata || error(
            "$name Phase 6 $N-D query metadata differs from the CPU oracle")

        normalized_expected = energy_change(normalized.component, normalized.proposal,
            normalized.logical, normalized.domain)
        adapted_normalized = Adapt.adapt(adaptor, normalized.compiled)
        scientific_storage_valid(adapted_normalized) || error(
            "$name adapted normalized-surface state contains invalid values")
        normalized_output = _backend_array(name, zeros(Float32, 1))
        normalized_backend = KernelAbstractions.get_backend(normalized_output)
        normalized_probe = _normalized_surface_probe!(normalized_backend, 1)
        normalized_probe(normalized_output, scientific_execution(adapted_normalized),
            normalized.component, normalized.proposal; ndrange = 1)
        normalized_metrics = ExecutionMetrics()
        normalized_plan = ExecutionPlan(
            normalized_backend; block_size = 1, metrics = normalized_metrics)
        launch_staged_commit!(normalized_plan, adapted_normalized,
            normalized.transaction; accepted = true)
        normalized_metrics.host_synchronizations == 0 || error(
            "$name Phase 6 normalized-surface path introduced a host synchronization")
        KernelAbstractions.synchronize(normalized_backend)
        isapprox(Array(normalized_output)[1], normalized_expected;
            rtol = 16eps(Float32), atol = 16eps(Float32)) || error(
            "$name Phase 6 $N-D normalized-surface delta differs from the CPU oracle")
        normalized_oracle = compile_scientific_state(
            normalized.logical, normalized.domain, normalized.tracker)
        commit_staged!(normalized_oracle, normalized.transaction; accepted = true)
        all(isapprox.(Array(adapted_normalized.trackers.boundary_measures),
            normalized_oracle.trackers.boundary_measures;
            rtol = 16eps(Float32), atol = 16eps(Float32))) || error(
            "$name Phase 6 $N-D normalized-surface commit differs from recomputation")

        metrics = ExecutionMetrics()
        plan = ExecutionPlan(backend; block_size = 1, metrics)
        launch_staged_commit!(plan, adapted, fixture.transaction; accepted = true)
        metrics.host_synchronizations == 0 || error(
            "$name Phase 6 staged commit introduced an internal host synchronization")
        KernelAbstractions.synchronize(backend)
        expected_compiled = compile_scientific_state(fixture.logical, fixture.domain,
            fixture.boundary_tracker; moment_tracker = fixture.moment_tracker)
        commit_staged!(expected_compiled, fixture.transaction; accepted = true)
        Array(adapted.potts.storage.ownership.ids) ==
        expected_compiled.potts.storage.ownership.ids || error(
            "$name staged ownership commit differs from the CPU oracle")
        Array(adapted.trackers.finite_volumes) ==
        expected_compiled.trackers.finite_volumes || error(
            "$name staged volume commit differs from the CPU oracle")
        Array(adapted.trackers.boundary_measures) ==
        expected_compiled.trackers.boundary_measures || error(
            "$name staged boundary commit differs from the CPU oracle")
        all(map(==, map(Array, adapted.trackers.moments.coordinate_sums),
            expected_compiled.trackers.moments.coordinate_sums)) || error(
            "$name staged moment commit differs from the CPU oracle")
        compiled_bytes[string(N, "D")] = scientific_state_bytes(adapted)
        workspace_byte_counts[string(N, "D")] = workspace_bytes(connectivity_workspace) +
                                                workspace_bytes(neighbor_workspace)
    end

    return Dict(
        "backend" => name,
        "dimensions" => [2, 3],
        "number_type" => "Float32",
        "proposal_conformance" => true,
        "volume_delta_conformance" => true,
        "contact_delta_conformance" => true,
        "boundary_delta_conformance" => true,
        "normalized_surface_conformance" => true,
        "field_energy_conformance" => true,
        "chemotaxis_conformance" => true,
        "focal_point_conformance" => true,
        "connectivity_conformance" => true,
        "spatial_query_conformance" => true,
        "transaction_conformance" => true,
        "internal_host_synchronizations" => 0,
        "compiled_bytes" => compiled_bytes,
        "workspace_bytes" => workspace_byte_counts
    )
end

function _phase7_components(fixture)
    return ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary),
        constraints = (fixture.connectivity,),
        kinetic_modifiers = (PositiveYield(0.75f0),)
    )
end

function _phase7_sequential_run(name::String, fixture, seed::UInt64)
    adaptor = _backend_adaptor(name)
    compiled = compile_scientific_state(
        fixture.logical, fixture.domain, fixture.boundary_tracker)
    state = Adapt.adapt(adaptor, compiled)
    components = Adapt.adapt(adaptor, _phase7_components(fixture))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    integrator = init_scientific(state, fixture.proposal_relation, components,
        SequentialCPM(temperature = 5.0f0); seed, plan)
    SciMLBase.step!(integrator, 3)
    metrics.host_synchronizations == 0 || error(
        "$name SequentialCPM synchronized before an observation boundary")
    report = current_mcs_report(integrator)
    expected_attempts = UInt64(mutable_site_count(fixture.domain))
    report.mcs == 3 || error("$name SequentialCPM reported the wrong MCS")
    report.scheduler_candidates == expected_attempts || error(
        "$name SequentialCPM scheduler count differs from the mutable-site count")
    report.activated_attempts == expected_attempts || error(
        "$name SequentialCPM did not execute exactly N attempts")
    report.realized_proposals == report.constraint_rejections +
        report.acceptance_rejections + report.accepted_copies || error(
        "$name SequentialCPM proposal accounting does not reconcile")
    report.activated_attempts == report.same_owner_no_ops + report.boundary_no_ops +
        report.immutable_recipient_no_ops + report.constraint_rejections +
        report.acceptance_rejections + report.accepted_copies || error(
        "$name SequentialCPM attempt accounting does not partition one MCS")
    snapshot = logical_state(integrator)
    isempty(state_invariant_errors(snapshot)) || error(
        "$name SequentialCPM produced an invalid logical state")
    host_state = Adapt.adapt(Array, integrator.state)
    isempty(tracker_conformance_errors(
        host_state, fixture.boundary_tracker, snapshot)) || error(
        "$name SequentialCPM tracker caches differ from recomputation")
    return (; report, snapshot, host_state, metrics)
end

"""Qualify exact sequential accounting, replay, and scientific commits on one backend."""
function qualify_sequential_backend(name::String)
    dimensions = Int[]
    for N in (2, 3)
        fixture = _phase6_fixture(Val(N))
        first_run = _phase7_sequential_run(
            name, fixture, UInt64(0x7068617365370000) + UInt64(N))
        second_run = _phase7_sequential_run(
            name, fixture, UInt64(0x7068617365370000) + UInt64(N))
        first_run.report == second_run.report || error(
            "$name SequentialCPM $N-D report replay differs for the same seed")
        lattice_storage(first_run.snapshot) == lattice_storage(second_run.snapshot) || error(
            "$name SequentialCPM $N-D state replay differs for the same seed")
        first_run.host_state.trackers.finite_volumes ==
        second_run.host_state.trackers.finite_volumes || error(
            "$name SequentialCPM $N-D volume replay differs for the same seed")
        first_run.host_state.trackers.boundary_measures ==
        second_run.host_state.trackers.boundary_measures || error(
            "$name SequentialCPM $N-D boundary replay differs for the same seed")
        push!(dimensions, N)
    end
    return Dict(
        "backend" => name,
        "algorithm" => "SequentialCPM",
        "dimensions" => dimensions,
        "number_type" => "Float32",
        "normalized_attempt_accounting" => true,
        "same_backend_replay" => true,
        "scientific_component_path" => true,
        "connectivity_workspace" => true,
        "tracker_conformance" => true,
        "internal_host_synchronizations" => 0
    )
end

function _phase7_checkerboard_components(fixture)
    return ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary),
        kinetic_modifiers = (PositiveYield(0.75f0),)
    )
end

function _phase7_checkerboard_run(name::String, fixture, seed::UInt64)
    adaptor = _backend_adaptor(name)
    compiled = compile_scientific_state(
        fixture.logical, fixture.domain, fixture.boundary_tracker)
    state = Adapt.adapt(adaptor, compiled)
    components = Adapt.adapt(adaptor, _phase7_checkerboard_components(fixture))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    integrator = init_scientific(state, fixture.proposal_relation, components,
        CheckerboardSweepCPM(temperature = 5.0f0); seed, plan)
    initialization_synchronizations = metrics.host_synchronizations
    SciMLBase.step!(integrator, 3)
    metrics.host_synchronizations == initialization_synchronizations || error(
        "$name CheckerboardSweepCPM synchronized inside an MCS")
    report = current_mcs_report(integrator)
    expected_attempts = UInt64(mutable_site_count(fixture.domain))
    report.mcs == 3 || error("$name CheckerboardSweepCPM reported the wrong MCS")
    report.scheduler_candidates == expected_attempts || error(
        "$name CheckerboardSweepCPM scheduler count differs from the mutable-site count")
    report.activated_attempts == expected_attempts || error(
        "$name CheckerboardSweepCPM did not visit every mutable site exactly once")
    report.realized_proposals == report.dynamic_conflicts +
        report.constraint_rejections + report.acceptance_rejections +
        report.accepted_copies || error(
        "$name CheckerboardSweepCPM proposal accounting does not reconcile")
    report.activated_attempts == report.same_owner_no_ops + report.boundary_no_ops +
        report.immutable_recipient_no_ops + report.dynamic_conflicts +
        report.constraint_rejections + report.acceptance_rejections +
        report.accepted_copies || error(
        "$name CheckerboardSweepCPM attempt accounting does not partition one MCS")
    snapshot = logical_state(integrator)
    isempty(state_invariant_errors(snapshot)) || error(
        "$name CheckerboardSweepCPM produced an invalid logical state")
    host_state = Adapt.adapt(Array, integrator.state)
    isempty(tracker_conformance_errors(
        host_state, fixture.boundary_tracker, snapshot)) || error(
        "$name CheckerboardSweepCPM tracker caches differ from recomputation")
    return (; report, snapshot, host_state, metrics, initialization_synchronizations)
end

"""Qualify exact colored sweeps, replay, conflicts, and tracker commits on one backend."""
function qualify_checkerboard_backend(name::String)
    dimensions = Int[]
    initialization_synchronizations = Int[]
    for N in (2, 3)
        fixture = _phase6_fixture(Val(N))
        seed = UInt64(0x7068617365371000) + UInt64(N)
        first_run = _phase7_checkerboard_run(name, fixture, seed)
        second_run = _phase7_checkerboard_run(name, fixture, seed)
        first_run.report == second_run.report || error(
            "$name CheckerboardSweepCPM $N-D report replay differs for the same seed")
        lattice_storage(first_run.snapshot) == lattice_storage(second_run.snapshot) || error(
            "$name CheckerboardSweepCPM $N-D state replay differs for the same seed")
        first_run.host_state.trackers.finite_volumes ==
        second_run.host_state.trackers.finite_volumes || error(
            "$name CheckerboardSweepCPM $N-D volume replay differs for the same seed")
        first_run.host_state.trackers.boundary_measures ==
        second_run.host_state.trackers.boundary_measures || error(
            "$name CheckerboardSweepCPM $N-D boundary replay differs for the same seed")
        push!(dimensions, N)
        push!(initialization_synchronizations, first_run.initialization_synchronizations)
    end
    return Dict(
        "backend" => name,
        "algorithm" => "CheckerboardSweepCPM",
        "dimensions" => dimensions,
        "number_type" => "Float32",
        "exact_once_per_site_accounting" => true,
        "realized_graph_coloring" => true,
        "deterministic_conflicts" => true,
        "linear_fixed_capacity_conflict_pipeline" => true,
        "same_backend_replay" => true,
        "tracker_conformance" => true,
        "initialization_host_synchronizations" => initialization_synchronizations,
        "internal_host_synchronizations" => 0
    )
end

function _phase7_lottery_run(name::String, fixture, seed::UInt64)
    adaptor = _backend_adaptor(name)
    compiled = compile_scientific_state(
        fixture.logical, fixture.domain, fixture.boundary_tracker)
    state = Adapt.adapt(adaptor, compiled)
    components = Adapt.adapt(adaptor, _phase7_checkerboard_components(fixture))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    integrator = init_scientific(state, fixture.proposal_relation, components,
        LotteryCPM(temperature = 5.0f0); seed, plan)
    initialization_synchronizations = metrics.host_synchronizations
    SciMLBase.step!(integrator, 3)
    metrics.host_synchronizations == initialization_synchronizations || error(
        "$name LotteryCPM synchronized inside an MCS")
    report = current_mcs_report(integrator)
    expected_sites = UInt64(mutable_site_count(fixture.domain))
    report.mcs == 3 || error("$name LotteryCPM reported the wrong MCS")
    report.scheduler_candidates == expected_sites * report.internal_rounds || error(
        "$name LotteryCPM scheduler accounting differs from sites times rounds")
    report.realized_proposals == report.dynamic_conflicts +
        report.constraint_rejections + report.acceptance_rejections +
        report.accepted_copies || error(
        "$name LotteryCPM proposal accounting does not reconcile")
    report.activated_attempts == report.same_owner_no_ops + report.boundary_no_ops +
        report.immutable_recipient_no_ops + report.dynamic_conflicts +
        report.constraint_rejections + report.acceptance_rejections +
        report.accepted_copies || error(
        "$name LotteryCPM activated-attempt accounting does not reconcile")
    snapshot = logical_state(integrator)
    isempty(state_invariant_errors(snapshot)) || error(
        "$name LotteryCPM produced an invalid logical state")
    host_state = Adapt.adapt(Array, integrator.state)
    isempty(tracker_conformance_errors(
        host_state, fixture.boundary_tracker, snapshot)) || error(
        "$name LotteryCPM tracker caches differ from recomputation")
    return (; report, snapshot, host_state, metrics, initialization_synchronizations)
end

"""Qualify topology-calibrated lottery accounting, replay, and commits on one backend."""
function qualify_lottery_backend(name::String)
    dimensions = Int[]
    initialization_synchronizations = Int[]
    for N in (2, 3)
        fixture = _phase6_fixture(Val(N))
        seed = UInt64(0x7068617365372000) + UInt64(N)
        first_run = _phase7_lottery_run(name, fixture, seed)
        second_run = _phase7_lottery_run(name, fixture, seed)
        first_run.report == second_run.report || error(
            "$name LotteryCPM $N-D report replay differs for the same seed")
        lattice_storage(first_run.snapshot) == lattice_storage(second_run.snapshot) || error(
            "$name LotteryCPM $N-D state replay differs for the same seed")
        first_run.host_state.trackers.finite_volumes ==
        second_run.host_state.trackers.finite_volumes || error(
            "$name LotteryCPM $N-D volume replay differs for the same seed")
        first_run.host_state.trackers.boundary_measures ==
        second_run.host_state.trackers.boundary_measures || error(
            "$name LotteryCPM $N-D boundary replay differs for the same seed")
        push!(dimensions, N)
        push!(initialization_synchronizations, first_run.initialization_synchronizations)
    end
    return Dict(
        "backend" => name,
        "algorithm" => "LotteryCPM",
        "dimensions" => dimensions,
        "number_type" => "Float32",
        "topology_derived_rounds" => true,
        "equal_per_site_expected_activation" => true,
        "deterministic_conflicts" => true,
        "same_backend_replay" => true,
        "tracker_conformance" => true,
        "initialization_host_synchronizations" => initialization_synchronizations,
        "internal_host_synchronizations" => 0
    )
end

function _phase7_mechanical_clock_fixture(::Val{N}) where {N}
    dims = N == 2 ? (4, 4) : (3, 3, 3)
    spacing = ntuple(_ -> 1.0f0, N)
    surface_relation = first_shell_relation(SurfaceRole(), Val(N); spacing)
    volume = FluctuatingVolumePressure(; eta = 1.25f0,
        noise = FixedMechanicalNoise(0.0f0),
        initialization = PreserveMechanicalInitialization,
        instance_id = 1)
    surface = FluctuatingSurfaceTension(BoundaryEdgeCount(), surface_relation;
        eta = 0.75f0, noise = FixedMechanicalNoise(0.0f0),
        initialization = PreserveMechanicalInitialization,
        instance_id = 2)
    schema = merge_property_schemas(
        required_properties(volume), required_properties(surface))
    logical = LogicalPottsState(fill(CellOwner(1), dims), CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = [MediumID(1)], property_schema = schema)
    property_values(logical, :target_volume)[1] = Float32(prod(dims) - 6)
    property_values(logical, :volume_strength)[1] = 2.0f0
    property_values(logical, :target_boundary)[1] = 4
    property_values(logical, :boundary_strength)[1] = 1.5f0
    domain = CartesianDomain(dims; spacing)
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface_relation)
    proposal_relation = first_shell_relation(ProposalRole(), Val(N); spacing)
    components = ScientificComponentSet(mechanics = (volume, surface))
    return (; logical, domain, tracker, proposal_relation, components)
end

function _phase7_mechanical_clock_run(name::String, ::Val{N}, algorithm,
        seed::UInt64) where {N}
    fixture = _phase7_mechanical_clock_fixture(Val(N))
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor, compile_scientific_state(
        fixture.logical, fixture.domain, fixture.tracker))
    components = Adapt.adapt(adaptor, fixture.components)
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    integrator = init_scientific(state, fixture.proposal_relation, components,
        algorithm; seed, plan)
    initialization_synchronizations = metrics.host_synchronizations
    SciMLBase.step!(integrator)
    metrics.host_synchronizations == initialization_synchronizations || error(
        "$name $(nameof(typeof(algorithm))) synchronized inside mechanical MCS execution")
    snapshot = logical_state(integrator)
    pressure = property_values(snapshot, :volume_pressure)[1]
    tension = property_values(snapshot, :surface_tension)[1]
    expected_pressure = 24.0f0 * (1.0f0 - exp(-1.25f0))
    expected_tension = -12.0f0 * (1.0f0 - exp(-0.75f0))
    isapprox(pressure, expected_pressure; rtol = 16eps(Float32)) || error(
        "$name $(nameof(typeof(algorithm))) $N-D volume-pressure clock is not one MCS")
    isapprox(tension, expected_tension; rtol = 16eps(Float32)) || error(
        "$name $(nameof(typeof(algorithm))) $N-D surface-tension clock is not one MCS")
    return (; pressure, tension, initialization_synchronizations)
end

function _phase7_stationary_pressure_sample(name::String)
    dims = (64, 64)
    slot_count = prod(dims)
    component = FluctuatingVolumePressure(; eta = 1.0f0,
        initialization = StationaryMechanicalInitialization, instance_id = 9)
    owners = reshape(
        OwnerRef[CellOwner(CellID(index)) for index in 1:slot_count], dims)
    cell_types = Dict(CellID(index) => CellTypeID(1) for index in 1:slot_count)
    logical = LogicalPottsState(owners, CellCapacity(slot_count);
        cell_types, medium_domains = [MediumID(1)],
        property_schema = required_properties(component))
    property_values(logical, :target_volume) .= 1.0f0
    property_values(logical, :volume_strength) .= 2.0f0
    spacing = (1.0f0, 1.0f0)
    domain = CartesianDomain(dims; spacing)
    surface_relation = first_shell_relation(SurfaceRole(), Val(2); spacing)
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface_relation)
    proposal_relation = first_shell_relation(ProposalRole(), Val(2); spacing)
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor,
        compile_scientific_state(logical, domain, tracker))
    components = Adapt.adapt(adaptor,
        ScientificComponentSet(mechanics = (component,)))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    init_scientific(state, proposal_relation, components,
        SequentialCPM(temperature = 3.0f0); seed = 0x61757873746174, plan)
    metrics.host_synchronizations == 0 || error(
        "$name stationary mechanical initialization synchronized internally")
    KernelAbstractions.synchronize(backend)
    samples = Array(state.potts.storage.properties.volume_pressure)
    sample_mean = mean(samples)
    sample_variance = var(samples; corrected = false)
    abs(sample_mean) < 0.2f0 || error(
        "$name stationary volume-pressure mean exceeds its qualification margin")
    abs(sample_variance - 12.0f0) < 0.6f0 || error(
        "$name stationary volume-pressure variance exceeds its qualification margin")

    evolution_component = FluctuatingVolumePressure(; eta = 1.0f0,
        initialization = PreserveMechanicalInitialization, instance_id = 10)
    evolution_state = Adapt.adapt(adaptor,
        compile_scientific_state(logical, domain, tracker))
    evolution_backend = KernelAbstractions.get_backend(
        evolution_state.potts.storage.active)
    evolution_metrics = ExecutionMetrics()
    evolution_plan = ExecutionPlan(
        evolution_backend; block_size = 128, metrics = evolution_metrics)
    evolution_integrator = init_scientific(evolution_state, proposal_relation,
        Adapt.adapt(adaptor,
            ScientificComponentSet(mechanics = (evolution_component,))),
        SequentialCPM(temperature = 3.0f0);
        seed = 0x65766f6c7574696f, plan = evolution_plan)
    CorePotts._advance_mechanics!(evolution_integrator, UInt64(1), UInt8(0),
        UInt8(0), 1.0f0)
    evolution_metrics.host_synchronizations == 0 || error(
        "$name mechanical evolution synchronized internally")
    KernelAbstractions.synchronize(evolution_backend)
    evolution_samples = Array(
        evolution_state.potts.storage.properties.volume_pressure)
    evolution_mean = mean(evolution_samples)
    evolution_variance = var(evolution_samples; corrected = false)
    expected_variance = 12.0f0 * (1.0f0 - exp(-2.0f0))
    abs(evolution_mean) < 0.2f0 || error(
        "$name evolving volume-pressure mean exceeds its qualification margin")
    abs(evolution_variance - expected_variance) < 0.6f0 || error(
        "$name evolving volume-pressure variance exceeds its qualification margin")
    return (; sample_mean, sample_variance, evolution_mean, evolution_variance)
end

"""Qualify stable volume-pressure and surface-tension mechanics on one backend."""
function qualify_mechanics_backend(name::String)
    algorithms = (
        SequentialCPM(temperature = 5.0f0),
        CheckerboardSweepCPM(temperature = 5.0f0),
        LotteryCPM(temperature = 5.0f0),
    )
    synchronization_counts = Dict{String, Vector{Int}}()
    for algorithm in algorithms
        label = string(nameof(typeof(algorithm)))
        synchronization_counts[label] = Int[]
        for N in (2, 3)
            seed = UInt64(0x7068617365373000) + UInt64(16N) +
                   UInt64(length(synchronization_counts))
            first_run = _phase7_mechanical_clock_run(
                name, Val(N), algorithm, seed)
            second_run = _phase7_mechanical_clock_run(
                name, Val(N), algorithm, seed)
            first_run.pressure == second_run.pressure || error(
                "$name $label $N-D volume-pressure replay differs")
            first_run.tension == second_run.tension || error(
                "$name $label $N-D surface-tension replay differs")
            push!(synchronization_counts[label],
                first_run.initialization_synchronizations)
        end
    end
    stationary = _phase7_stationary_pressure_sample(name)
    return Dict(
        "backend" => name,
        "families" => ["FluctuatingVolumePressure", "FluctuatingSurfaceTension"],
        "algorithms" => collect(keys(synchronization_counts)),
        "dimensions" => [2, 3],
        "exact_frozen_observable_ou" => true,
        "normalized_mcs_clock" => true,
        "same_backend_replay" => true,
        "stationary_initialization_mean" => stationary.sample_mean,
        "stationary_initialization_variance" => stationary.sample_variance,
        "evolution_mean" => stationary.evolution_mean,
        "evolution_variance" => stationary.evolution_variance,
        "initialization_host_synchronizations" => synchronization_counts,
        "internal_host_synchronizations" => 0,
    )
end

function _phase8_lifecycle_fixture(::Val{N}; geometry = nothing) where {N}
    dims = ntuple(_ -> 4, Val(N))
    provenance = ComponentIdentity(:phase8_lifecycle_qualification, v"1.0.0", :benchmark)
    schema = PropertySchema(
        PropertyDescriptor(:target, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = SplitOnDivision(),
            transition = PreserveOnTransition()),
        PropertyDescriptor(:age, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = CloneOnDivision(),
            transition = PreserveOnTransition()))
    logical = LogicalPottsState(fill(CellOwner(1), dims), CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = schema)
    property_values(logical, :target)[1] = Int32(prod(dims))
    property_values(logical, :age)[1] = Int32(7)
    domain = CartesianDomain(dims; spacing = ntuple(_ -> 1.0f0, Val(N)))
    proposal_relation = first_shell_relation(ProposalRole(), Val(N);
        spacing = domain.spacing)
    surface_relation = first_shell_relation(SurfaceRole(), Val(N);
        spacing = domain.spacing)
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface_relation)
    direction = ntuple(axis -> axis == 1 ? 1.0f0 : 0.0f0, Val(N))
    division_geometry = geometry === nothing ? VectorDivision(direction) : geometry
    growth = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), AddCellProperty(:target, Int32(2)); semantic_id = 801)
    division = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:target, Int32(prod(dims))),
        DivideCell(division_geometry); semantic_id = 802)
    custom = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        PropertyAtLeast(:age, Int32(7)), LifecycleQualificationDouble(:age);
        semantic_id = 800)
    return (; logical, domain, proposal_relation, tracker,
        events = (division, growth, custom))
end

function _phase8_lifecycle_run(name::String, ::Val{N}, algorithm, seed::UInt64;
        reverse_declaration::Bool = false, geometry = nothing) where {N}
    fixture = _phase8_lifecycle_fixture(Val(N); geometry)
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor, compile_scientific_state(
        fixture.logical, fixture.domain, fixture.tracker))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    events = reverse_declaration ? reverse(fixture.events) : fixture.events
    lifecycle = compile_lifecycle(events, state, plan)
    integrator = init_scientific(state, fixture.proposal_relation,
        ScientificComponentSet(), algorithm; seed, plan, lifecycle)
    initialization_synchronizations = metrics.host_synchronizations
    SciMLBase.step!(integrator)
    lifecycle_synchronizations = metrics.host_synchronizations -
        initialization_synchronizations
    lifecycle_synchronizations == 1 || error(
        "$name lifecycle must expose exactly one identity-transaction failure boundary")
    report = current_lifecycle_report(integrator)
    snapshot = logical_state(integrator)
    host_state = Adapt.adapt(Array, integrator.state)
    isempty(state_invariant_errors(snapshot)) || error(
        "$name $N-D lifecycle produced an invalid logical state")
    isempty(tracker_conformance_errors(host_state, fixture.tracker, snapshot)) || error(
        "$name $N-D lifecycle tracker caches differ from recomputation")
    n_cells(snapshot) == 2 || error("$name $N-D lifecycle division did not commit")
    property_values(snapshot, :target)[1:2] ==
        fill(Int32((prod(fixture.domain.dims) + 2) ÷ 2), 2) || error(
        "$name $N-D lifecycle property inheritance differs from the contract")
    property_values(snapshot, :age)[1:2] == Int32[14, 14] || error(
        "$name $N-D lifecycle extension effect or clone policy differs from the contract")
    report.successful_divisions == 1 || error(
        "$name $N-D lifecycle report omitted the committed division")
    return (; snapshot, report, lifecycle_synchronizations,
        workspace_bytes = compiled_lifecycle_bytes(lifecycle))
end

function _phase8_lifecycle_failure_qualification(name::String)
    fixture = _phase8_lifecycle_fixture(Val(2))
    adaptor = _backend_adaptor(name)
    function build(events; logical = fixture.logical,
            resolver = RejectLifecycleConflicts())
        state = Adapt.adapt(adaptor, compile_scientific_state(
            logical, fixture.domain, fixture.tracker))
        backend = KernelAbstractions.get_backend(state.potts.storage.active)
        plan = ExecutionPlan(backend; block_size = 128, metrics = ExecutionMetrics())
        lifecycle = compile_lifecycle(events, state, plan; resolver)
        return init_scientific(state, fixture.proposal_relation,
            ScientificComponentSet(), SequentialCPM(temperature = 0.0f0);
            seed = 0x7068617365382000, plan, lifecycle)
    end

    transition = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), TransitionCell(CellTypeID(3));
        semantic_id = 830, priority = 1)
    death = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), RemoveCellImmediately(MediumID(1));
        semantic_id = 831, priority = 2)
    conflict = build((transition, death))
    conflict_error = try
        run_compiled_lifecycle!(conflict, conflict.lifecycle, UInt64(1))
        nothing
    catch caught
        caught
    end
    conflict_error isa CompiledLifecycleError && conflict_error.code == UInt32(1) ||
        error("$name lifecycle conflict did not surface its bounded device failure")
    conflict_snapshot = logical_state(conflict)
    lattice_storage(conflict_snapshot) == lattice_storage(fixture.logical) || error(
        "$name lifecycle conflict mutated ownership before failure")
    property_values(conflict_snapshot, :age) == property_values(fixture.logical, :age) ||
        error("$name lifecycle conflict mutated properties before failure")

    selected = build((transition, death); resolver = StableLifecyclePriority())
    run_compiled_lifecycle!(selected, selected.lifecycle, UInt64(1))
    selected_snapshot = logical_state(selected)
    n_cells(selected_snapshot) == 0 || error(
        "$name stable lifecycle priority did not commit the winning death effect")
    generation(selected_snapshot, CellID(1)) == CellGeneration(1) || error(
        "$name lifecycle death did not advance the slot generation")

    full = LogicalPottsState(fill(CellOwner(1), fixture.domain.dims), CellCapacity(1);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),),
        property_schema = fixture.logical.properties.schema)
    property_values(full, :target)[1] = Int32(prod(fixture.domain.dims))
    property_values(full, :age)[1] = Int32(7)
    capacity_event = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), DivideCell(VectorDivision((1.0f0, 0.0f0)));
        semantic_id = 832)
    capacity_integrator = build((capacity_event,); logical = full)
    capacity_error = try
        run_compiled_lifecycle!(capacity_integrator, capacity_integrator.lifecycle,
            UInt64(1))
        nothing
    catch caught
        caught
    end
    capacity_error isa CompiledLifecycleError && capacity_error.code == UInt32(2) ||
        error("$name lifecycle capacity failure did not surface from the device")
    lattice_storage(logical_state(capacity_integrator)) == lattice_storage(full) || error(
        "$name lifecycle capacity failure mutated ownership")
    return Dict(
        "conflict_failure_code" => 1,
        "capacity_failure_code" => 2,
        "rollback" => true,
        "stable_priority_death" => true,
        "generation_advanced" => true,
    )
end

function _phase8_moment_lifecycle_qualification(name::String)
    adaptor = _backend_adaptor(name)
    for N in (2, 3)
        dims = ntuple(_ -> 6, Val(N))
        provenance = ComponentIdentity(:phase8_moment_qualification, v"1.0.0", :benchmark)
        schema = PropertySchema(PropertyDescriptor(:age, Int32,
            ConstantInitializer(Int32(0)); requester = provenance,
            division = CloneOnDivision(), transition = PreserveOnTransition()))
        owners = fill(MediumOwner(1), dims)
        fill!(view(owners, ntuple(_ -> 2:5, Val(N))...), CellOwner(1))
        logical = LogicalPottsState(owners, CellCapacity(3);
            cell_types = Dict(CellID(1) => CellTypeID(1)),
            medium_domains = (MediumID(1),), property_schema = schema)
        domain = CartesianDomain(dims; spacing = ntuple(_ -> 1.0f0, Val(N)))
        proposal = first_shell_relation(ProposalRole(), Val(N); spacing = domain.spacing)
        surface = first_shell_relation(SurfaceRole(), Val(N); spacing = domain.spacing)
        connectivity = first_shell_relation(ConnectivityRole(), Val(N);
            spacing = domain.spacing)
        boundary_tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
        moment_tracker = UnwrappedMomentTracker(connectivity, (CellID(1),);
            number_type = Float32)
        state = Adapt.adapt(adaptor, compile_scientific_state(
            logical, domain, boundary_tracker; moment_tracker))
        backend = KernelAbstractions.get_backend(state.potts.storage.active)
        plan = ExecutionPlan(backend; block_size = 128, metrics = ExecutionMetrics())
        direction = ntuple(axis -> axis == 1 ? 1.0f0 : 0.0f0, Val(N))
        event = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
            AlwaysLifecycleTrigger(), DivideCell(VectorDivision(direction));
            semantic_id = 840 + N)
        lifecycle = compile_lifecycle((event,), state, plan)
        integrator = init_scientific(state, proposal, ScientificComponentSet(),
            SequentialCPM(temperature = 0.0f0);
            seed = UInt64(0x7068617365383000) + UInt64(N),
            plan, lifecycle, moment_tracker)
        run_compiled_lifecycle!(integrator, lifecycle, UInt64(1))
        snapshot = logical_state(integrator)
        observed = Adapt.adapt(Array, integrator.state).trackers.moments
        rebuilt = rebuild_tracker(moment_tracker, snapshot, domain)
        observed.tracked == rebuilt.tracked || error(
            "$name $N-D lifecycle moment tracking flags differ from reconstruction")
        observed.coordinate_sums == rebuilt.coordinate_sums || error(
            "$name $N-D lifecycle moment sums differ from reconstruction")
    end
    return Dict("dimensions" => [2, 3], "number_type" => "Float32",
        "independent_reconstruction" => true, "child_tracking" => "explicit_only")
end

function _phase8_mechanical_lifecycle_run(name::String, ::Val{N}, division,
        seed::UInt64) where {N}
    dims = ntuple(_ -> 4, Val(N))
    domain = CartesianDomain(dims; spacing = ntuple(_ -> 1.0f0, Val(N)))
    proposal = first_shell_relation(ProposalRole(), Val(N); spacing = domain.spacing)
    surface = first_shell_relation(SurfaceRole(), Val(N); spacing = domain.spacing)
    metric = BoundaryEdgeCount()
    boundary_tracker = BoundaryMeasureTracker(metric, surface)
    pressure = FluctuatingVolumePressure(number_type = Float32,
        initialization = PreserveMechanicalInitialization, division = division,
        noise = FixedMechanicalNoise(1.0f0), instance_id = 1)
    tension = FluctuatingSurfaceTension(metric, surface; number_type = Float32,
        initialization = PreserveMechanicalInitialization,
        target_division = SplitOnDivision(), division = division,
        noise = FixedMechanicalNoise(1.0f0), instance_id = 2)
    schema = merge_property_schemas(required_properties(pressure),
        required_properties(tension))
    logical = LogicalPottsState(fill(CellOwner(1), dims), CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = schema)
    property_values(logical, :target_volume)[1] = Float32(prod(dims))
    property_values(logical, :volume_strength)[1] = 2.0f0
    property_values(logical, :volume_pressure)[1] = 99.0f0
    property_values(logical, :target_boundary)[1] = Int64(0)
    property_values(logical, :boundary_strength)[1] = 1.5f0
    property_values(logical, :surface_tension)[1] = 77.0f0
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor, compile_scientific_state(
        logical, domain, boundary_tracker))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    plan = ExecutionPlan(backend; block_size = 128, metrics = ExecutionMetrics())
    direction = ntuple(axis -> axis == 1 ? 1.0f0 : 0.0f0, Val(N))
    event = LifecycleEvent(ActiveCellsTarget(), OnceAtMCS(1),
        AlwaysLifecycleTrigger(), DivideCell(VectorDivision(direction));
        semantic_id = 850 + N)
    lifecycle = compile_lifecycle((event,), state, plan)
    components = Adapt.adapt(adaptor,
        ScientificComponentSet(mechanics = (pressure, tension)))
    integrator = init_scientific(state, proposal, components,
        SequentialCPM(temperature = 3.0f0); seed, plan, lifecycle)
    run_compiled_lifecycle!(integrator, lifecycle, UInt64(1))
    snapshot = logical_state(integrator)
    host_state = Adapt.adapt(Array, integrator.state)
    return (; snapshot, host_state, boundary_tracker)
end

function _phase8_mechanical_lifecycle_qualification(name::String)
    policies = (
        ConstitutiveResetAfterDivision(),
        PreserveMechanicalOnDivision(),
        StationaryRedrawAfterDivision(),
    )
    labels = String[]
    for policy in policies
        label = string(nameof(typeof(policy)))
        push!(labels, label)
        for N in (2, 3)
            seed = UInt64(0x7068617365384000) + UInt64(16N) + UInt64(length(label))
            first_run = _phase8_mechanical_lifecycle_run(name, Val(N), policy, seed)
            replay = _phase8_mechanical_lifecycle_run(name, Val(N), policy, seed)
            first_pressure = property_values(first_run.snapshot, :volume_pressure)[1:2]
            first_tension = property_values(first_run.snapshot, :surface_tension)[1:2]
            first_pressure == property_values(replay.snapshot, :volume_pressure)[1:2] ||
                error("$name $label $N-D pressure inheritance replay differs")
            first_tension == property_values(replay.snapshot, :surface_tension)[1:2] ||
                error("$name $label $N-D tension inheritance replay differs")
            if policy isa ConstitutiveResetAfterDivision
                all(iszero, first_pressure) || error(
                    "$name constitutive pressure repair differs from its post-division mean")
                for cell in 1:2
                    expected = 3.0f0 * Float32(
                        first_run.host_state.trackers.boundary_measures[cell])
                    first_tension[cell] == expected || error(
                        "$name constitutive tension repair differs from its post-division mean")
                end
            elseif policy isa PreserveMechanicalOnDivision
                first_pressure == Float32[99, 99] || error(
                    "$name intensive pressure preservation failed")
                first_tension == Float32[77, 77] || error(
                    "$name intensive tension preservation failed")
            else
                first_pressure != Float32[99, 99] || error(
                    "$name stationary pressure redraw did not execute")
                first_tension != Float32[77, 77] || error(
                    "$name stationary tension redraw did not execute")
            end
        end
    end
    return Dict("dimensions" => [2, 3], "families" =>
        ["FluctuatingVolumePressure", "FluctuatingSurfaceTension"],
        "policies" => labels, "same_backend_replay" => true)
end

function _phase8_initialization_qualification(name::String)
    adaptor = _backend_adaptor(name)
    for N in (2, 3)
        dims = ntuple(_ -> 8, Val(N))
        provenance = ComponentIdentity(:phase8_initialization_qualification,
            v"1.0.0", :benchmark)
        schema = PropertySchema(PropertyDescriptor(:age, Int32,
            ConstantInitializer(Int32(0)); requester = provenance,
            division = CloneOnDivision(), transition = PreserveOnTransition()))
        custom = InitializationQualificationLayout(ProvisionalCellID(10),
            CellTypeID(1), (CartesianIndex(ntuple(_ -> 1, Val(N))),
                CartesianIndex(ntuple(_ -> 8, Val(N)))))
        shape = ShapeCellLayout(20, 2, ntuple(_ -> 4, Val(N)), LatticeBall(1.0f0))
        properties = InitialCellProperties(20, 2, (age = Int32(9),); dimensions = N)
        seeds = UniformSiteSeeds(
            [ProvisionalCellID(30) => CellTypeID(1),
                ProvisionalCellID(40) => CellTypeID(2)], trues(dims);
            operation = 860)
        layouts = (custom, shape, properties, seeds)
        first_state = finalize_initial_state(dims, layouts...; capacity = CellCapacity(8),
            medium_domains = (MediumID(1),), property_schema = schema,
            seed = UInt64(0x7068617365385000) + UInt64(N))
        permuted_state = finalize_initial_state(dims, reverse(layouts)...;
            capacity = CellCapacity(8), medium_domains = (MediumID(1),),
            property_schema = schema,
            seed = UInt64(0x7068617365385000) + UInt64(N))
        first = logical_state(first_state)
        permuted = logical_state(permuted_state)
        lattice_storage(first) == lattice_storage(permuted) || error(
            "$name $N-D host-finalized initialization depends on declaration order")
        initialization_report(first_state).provisional_to_runtime ==
            initialization_report(permuted_state).provisional_to_runtime || error(
            "$name $N-D initialization identity compaction depends on declaration order")
        domain = CartesianDomain(dims; spacing = ntuple(_ -> 1.0f0, Val(N)))
        surface = first_shell_relation(SurfaceRole(), Val(N); spacing = domain.spacing)
        tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
        adapted = Adapt.adapt(adaptor, compile_scientific_state(first, domain, tracker))
        scientific_storage_valid(adapted) || error(
            "$name $N-D initialized state did not lower to one valid backend array tree")
        backend = KernelAbstractions.get_backend(adapted.potts.storage.active)
        metrics = ExecutionMetrics()
        plan = ExecutionPlan(backend; block_size = 128, metrics)
        roundtrip = logical_snapshot(plan, adapted.potts)
        lattice_storage(roundtrip) == lattice_storage(first) || error(
            "$name $N-D host-finalized initialization changed during device lowering")
        metrics.host_synchronizations == 1 || error(
            "$name initialization roundtrip must synchronize only at explicit observation")
    end
    return Dict("dimensions" => [2, 3], "execution_capability" => "host_finalized",
        "device_native_claim" => false, "single_construction_transfer" => true,
        "custom_layout" => true, "random_replay" => true,
        "declaration_permutation_invariant" => true, "hidden_host_fallback" => false)
end

function _phase8_downstream_protocol_run(name::String, ::Val{N}, seed::UInt64;
        reverse_declaration::Bool = false) where {N}
    dims = ntuple(_ -> 4, Val(N))
    provenance = ComponentIdentity(:phase8_downstream_protocol_qualification,
        v"1.0.0", :benchmark)
    schema = PropertySchema(
        PropertyDescriptor(:target, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = LifecycleQualificationVolumeSplit(),
            transition = PreserveOnTransition()),
        PropertyDescriptor(:age, Int32, ConstantInitializer(Int32(0));
            requester = provenance, division = CloneOnDivision(),
            transition = PreserveOnTransition()),
    )
    sites = Tuple(CartesianIndices(dims))
    layout = InitializationQualificationLayout(
        ProvisionalCellID(10), CellTypeID(1), sites)
    initialized = finalize_initial_state(dims, layout; capacity = CellCapacity(4),
        medium_domains = (MediumID(1),), property_schema = schema, seed)
    logical = logical_state(initialized)
    property_values(logical, :target)[1] = Int32(prod(dims))
    property_values(logical, :age)[1] = Int32(3)
    domain = CartesianDomain(dims; spacing = ntuple(_ -> 1.0f0, Val(N)))
    proposal = first_shell_relation(ProposalRole(), Val(N); spacing = domain.spacing)
    surface = first_shell_relation(SurfaceRole(), Val(N); spacing = domain.spacing)
    boundary_tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    derived_tracker = LifecycleQualificationSiteSumTracker()
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor, compile_scientific_state(
        logical, domain, boundary_tracker; moment_tracker = derived_tracker))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    schedule = LifecycleQualificationOddMCS()
    division = LifecycleEvent(ActiveCellsTarget(), schedule,
        LifecycleQualificationAtLeast(:target, Int32(prod(dims))),
        DivideCell(LifecycleQualificationOffsetPlane(0.0f0)); semantic_id = 881)
    custom = LifecycleEvent(ActiveCellsTarget(), schedule,
        LifecycleQualificationAtLeast(:age, Int32(3)),
        LifecycleQualificationDouble(:age); semantic_id = 880)
    events = reverse_declaration ? (division, custom) : (custom, division)
    lifecycle = compile_lifecycle(events, state, plan)
    integrator = init_scientific(state, proposal, ScientificComponentSet(),
        SequentialCPM(temperature = 0.0f0); seed, plan, lifecycle,
        moment_tracker = derived_tracker)
    SciMLBase.step!(integrator)
    snapshot = logical_state(integrator)
    n_cells(snapshot) == 2 || error(
        "$name $N-D downstream geometry did not divide the initialized cell")
    property_values(snapshot, :target)[1:2] ==
        fill(Int32(prod(dims) ÷ 2), 2) || error(
        "$name $N-D downstream property lifecycle policy differs")
    property_values(snapshot, :age)[1:2] == Int32[6, 6] || error(
        "$name $N-D downstream schedule/trigger/effect combination differs")
    host_state = Adapt.adapt(Array, integrator.state)
    rebuilt = rebuild_tracker(derived_tracker, snapshot, domain)
    host_state.trackers.moments.values == rebuilt.values || error(
        "$name $N-D downstream derived observable differs from reconstruction")
    checkpoint = capture_checkpoint(integrator)
    restored = restore_checkpoint(checkpoint, integrator; adaptor)
    SciMLBase.step!(integrator, 2)
    SciMLBase.step!(restored, 2)
    restored_snapshot = logical_state(restored)
    lattice_storage(restored_snapshot) == lattice_storage(logical_state(integrator)) ||
        error("$name $N-D downstream protocols do not survive exact restoration")
    restored_host = Adapt.adapt(Array, restored.state)
    restored_rebuilt = rebuild_tracker(derived_tracker, restored_snapshot, domain)
    restored_host.trackers.moments.values == restored_rebuilt.values || error(
        "$name $N-D restored downstream derived observable differs from reconstruction")
    current_mcs_report(restored).accepted_copies > 0 || error(
        "$name $N-D downstream derived observable did not exercise copy-commit updates")
    return (; snapshot, derived = host_state.trackers.moments.values,
        initialization_report = initialization_report(initialized),
        workspace_bytes = compiled_lifecycle_bytes(lifecycle))
end

function _phase8_downstream_protocol_qualification(name::String)
    workspaces = Int[]
    for N in (2, 3)
        seed = UInt64(0x7068617365385500) + UInt64(N)
        first_run = _phase8_downstream_protocol_run(name, Val(N), seed)
        permuted = _phase8_downstream_protocol_run(name, Val(N), seed;
            reverse_declaration = true)
        lattice_storage(first_run.snapshot) == lattice_storage(permuted.snapshot) ||
            error("$name $N-D downstream declaration permutation differs")
        first_run.derived == permuted.derived || error(
            "$name $N-D downstream derived observable permutation differs")
        first_run.initialization_report.provisional_to_runtime ==
            permuted.initialization_report.provisional_to_runtime || error(
            "$name $N-D downstream layout identity compaction differs")
        push!(workspaces, first_run.workspace_bytes)
    end
    return Dict(
        "dimensions" => [2, 3],
        "custom_schedule" => true,
        "custom_trigger" => true,
        "custom_effect" => true,
        "custom_division_geometry" => true,
        "custom_property_lifecycle" => true,
        "custom_derived_observable" => true,
        "custom_layout" => true,
        "exact_restore" => true,
        "declaration_permutation_invariant" => true,
        "workspace_bytes" => workspaces,
        "core_edits_required_by_fixture" => 0,
    )
end

"""Qualify complete device-resident lifecycle transactions on one backend."""
function qualify_lifecycle_backend(name::String)
    algorithms = (
        SequentialCPM(temperature = 0.0f0),
        CheckerboardSweepCPM(temperature = 0.0f0),
        LotteryCPM(temperature = 0.0f0),
    )
    workspace_bytes = Dict{String, Vector{Int}}()
    qualified_geometries = String["vector"]
    for algorithm in algorithms
        label = string(nameof(typeof(algorithm)))
        workspace_bytes[label] = Int[]
        for N in (2, 3)
            seed = UInt64(0x7068617365380000) + UInt64(16N) +
                   UInt64(length(workspace_bytes))
            first_run = _phase8_lifecycle_run(name, Val(N), algorithm, seed)
            replay = _phase8_lifecycle_run(name, Val(N), algorithm, seed)
            permuted = _phase8_lifecycle_run(name, Val(N), algorithm, seed;
                reverse_declaration = true)
            lattice_storage(first_run.snapshot) == lattice_storage(replay.snapshot) || error(
                "$name $label $N-D lifecycle replay differs")
            lattice_storage(first_run.snapshot) == lattice_storage(permuted.snapshot) || error(
                "$name $label $N-D lifecycle declaration permutation differs")
            push!(workspace_bytes[label], first_run.workspace_bytes)
        end
    end
    for geometry in (RandomOrientationDivision(820), MajorAxisDivision(),
            MinorAxisDivision())
        label = string(nameof(typeof(geometry)))
        for N in (2, 3)
            seed = UInt64(0x7068617365381000) + UInt64(16N) + UInt64(length(label))
            first_run = _phase8_lifecycle_run(name, Val(N),
                SequentialCPM(temperature = 0.0f0), seed; geometry)
            replay = _phase8_lifecycle_run(name, Val(N),
                SequentialCPM(temperature = 0.0f0), seed; geometry)
            lattice_storage(first_run.snapshot) == lattice_storage(replay.snapshot) || error(
                "$name $label $N-D division geometry replay differs")
        end
        push!(qualified_geometries, label)
    end
    failure_qualification = _phase8_lifecycle_failure_qualification(name)
    moment_qualification = _phase8_moment_lifecycle_qualification(name)
    mechanical_qualification = _phase8_mechanical_lifecycle_qualification(name)
    initialization_qualification = _phase8_initialization_qualification(name)
    downstream_qualification = _phase8_downstream_protocol_qualification(name)
    return Dict(
        "backend" => name,
        "algorithms" => collect(keys(workspace_bytes)),
        "dimensions" => [2, 3],
        "division_geometries" => qualified_geometries,
        "complete_device_transaction" => true,
        "same_backend_replay" => true,
        "declaration_permutation_invariant" => true,
        "tracker_conformance" => true,
        "bounded_workspace_bytes" => workspace_bytes,
        "identity_failure_boundary_synchronizations" => 1,
        "failure_qualification" => failure_qualification,
        "derived_moment_qualification" => moment_qualification,
        "mechanical_lifecycle_qualification" => mechanical_qualification,
        "initialization_qualification" => initialization_qualification,
        "downstream_protocol_qualification" => downstream_qualification,
        "hidden_host_fallback" => false,
    )
end

function _phase8_persistence_integrator(name::String, ::Val{N}, algorithm,
        seed::UInt64; with_lifecycle::Bool = true) where {N}
    dims = ntuple(_ -> 6, Val(N))
    spacing = ntuple(_ -> 1.0f0, Val(N))
    domain = CartesianDomain(dims; spacing)
    proposal = first_shell_relation(ProposalRole(), Val(N); spacing)
    surface = first_shell_relation(SurfaceRole(), Val(N); spacing)
    boundary_tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    volume = QuadraticVolumeHamiltonian(number_type = Float32)
    pressure = FluctuatingVolumePressure(; eta = 0.5f0,
        noise = FixedMechanicalNoise(0.25f0),
        initialization = PreserveMechanicalInitialization,
        number_type = Float32, instance_id = 71)
    provenance = ComponentIdentity(:phase8_persistence_qualification,
        v"1.0.0", :benchmark)
    age_schema = PropertySchema(PropertyDescriptor(:age, Int32,
        ConstantInitializer(Int32(0)); requester = provenance,
        division = CloneOnDivision(), transition = PreserveOnTransition()))
    schema = merge_property_schemas(required_properties(volume),
        required_properties(pressure), age_schema)

    owners = fill(MediumOwner(1), dims)
    first_region = ntuple(axis -> axis == 1 ? (2:3) : (2:4), Val(N))
    second_region = ntuple(axis -> axis == 1 ? (4:5) : (2:4), Val(N))
    fill!(view(owners, first_region...), CellOwner(1))
    fill!(view(owners, second_region...), CellOwner(2))
    logical = LogicalPottsState(owners, CellCapacity(4);
        cell_types = Dict(CellID(1) => CellTypeID(1), CellID(2) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = schema)
    initial_volume = Float32(prod(length, first_region))
    property_values(logical, :target_volume)[1:2] .= initial_volume
    property_values(logical, :volume_strength)[1:2] .= 1.0f0
    property_values(logical, :volume_pressure)[1:2] .= Float32[0.5, -0.25]
    property_values(logical, :age)[1:2] .= Int32[3, 5]

    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor,
        compile_scientific_state(logical, domain, boundary_tracker))
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = 128, metrics)
    event = LifecycleEvent(ActiveCellsTarget(), EveryMCS(),
        AlwaysLifecycleTrigger(), AddCellProperty(:age, Int32(1)); semantic_id = 870)
    lifecycle = with_lifecycle ? compile_lifecycle((event,), state, plan) :
                NoCompiledLifecycle()
    components = Adapt.adapt(adaptor,
        ScientificComponentSet(energies = (volume,), mechanics = (pressure,)))
    return init_scientific(state, proposal, components, algorithm;
        seed, plan, lifecycle)
end

function _phase8_persistence_run(name::String, ::Val{N}, algorithm,
        seed::UInt64) where {N}
    adaptor = _backend_adaptor(name)
    uninterrupted = _phase8_persistence_integrator(name, Val(N), algorithm, seed)
    backend = KernelAbstractions.get_backend(
        uninterrupted.state.potts.storage.active)
    root = capture_checkpoint(uninterrupted)
    root.profile.backend == uninterrupted.plan.capabilities.family || error(
        "$name $N-D MCS-0 checkpoint recorded the wrong backend family")
    SciMLBase.step!(uninterrupted, 2)
    before_capture = uninterrupted.plan.metrics.host_synchronizations
    checkpoint = capture_checkpoint(uninterrupted; ancestry = root)
    capture_synchronizations = uninterrupted.plan.metrics.host_synchronizations -
                               before_capture
    capture_synchronizations == 1 || error(
        "$name $N-D checkpoint capture must have one explicit observation synchronization")
    checkpoint.initial_state_fingerprint == root.initial_state_fingerprint || error(
        "$name $N-D checkpoint lost its MCS-0 ancestry")
    resumed = restore_checkpoint(checkpoint, uninterrupted; adaptor)
    resumed.mcs == uninterrupted.mcs == UInt64(2) || error(
        "$name $N-D exact restore resumed at the wrong MCS")
    resumed.plan.capabilities.family == checkpoint.profile.backend || error(
        "$name $N-D exact restore changed backend family")
    scientific_storage_valid(resumed.state) || error(
        "$name $N-D restored state is not a valid single-backend array tree")

    uninterrupted_syncs = uninterrupted.plan.metrics.host_synchronizations
    resumed_syncs = resumed.plan.metrics.host_synchronizations
    SciMLBase.step!(uninterrupted, 3)
    SciMLBase.step!(resumed, 3)
    uninterrupted_internal_syncs = uninterrupted.plan.metrics.host_synchronizations -
                                   uninterrupted_syncs
    resumed_internal_syncs = resumed.plan.metrics.host_synchronizations - resumed_syncs
    uninterrupted_internal_syncs == resumed_internal_syncs == 0 || error(
        "$name $N-D exact continuation introduced a hidden synchronization")
    KernelAbstractions.synchronize(backend)
    expected = logical_state(uninterrupted)
    observed = logical_state(resumed)
    lattice_storage(observed) == lattice_storage(expected) || error(
        "$name $(nameof(typeof(algorithm))) $N-D restored ownership trajectory differs")
    for key in property_keys(expected.properties.schema)
        property_values(observed, key) == property_values(expected, key) || error(
            "$name $(nameof(typeof(algorithm))) $N-D restored property `$key` differs")
    end
    current_mcs_report(resumed) == current_mcs_report(uninterrupted) || error(
        "$name $(nameof(typeof(algorithm))) $N-D restored MCS report differs")
    current_lifecycle_report(resumed) == current_lifecycle_report(uninterrupted) || error(
        "$name $(nameof(typeof(algorithm))) $N-D restored lifecycle report differs")
    host_state = Adapt.adapt(Array, resumed.state)
    isempty(tracker_conformance_errors(
        host_state, uninterrupted.state.boundary_tracker, observed)) || error(
        "$name $(nameof(typeof(algorithm))) $N-D restored tracker differs from reconstruction")
    return (; capture_synchronizations, continuation_mcs = resumed.mcs,
        internal_host_synchronizations = resumed_internal_syncs)
end

"""Qualify canonical exact continuation without weakening the device execution profile."""
function qualify_persistence_backend(name::String)
    algorithms = (
        SequentialCPM(temperature = 2.0f0),
        CheckerboardSweepCPM(temperature = 2.0f0),
        LotteryCPM(temperature = 2.0f0),
    )
    profiles = Dict{String, Any}()
    for algorithm in algorithms
        label = string(nameof(typeof(algorithm)))
        profiles[label] = Dict{String, Any}()
        for N in (2, 3)
            seed = UInt64(0x7068617365386000) + UInt64(16N) +
                   UInt64(length(profiles))
            result = _phase8_persistence_run(name, Val(N), algorithm, seed)
            profiles[label]["$(N)d"] = Dict(
                "capture_observation_synchronizations" =>
                    result.capture_synchronizations,
                "continuation_mcs" => result.continuation_mcs,
                "internal_host_synchronizations" =>
                    result.internal_host_synchronizations,
            )
        end
    end
    return Dict(
        "backend" => name,
        "algorithms" => collect(keys(profiles)),
        "dimensions" => [2, 3],
        "profiles" => profiles,
        "canonical_host_record" => true,
        "same_backend_exact_continuation" => true,
        "rng_continuation" => true,
        "auxiliary_state_continuation" => true,
        "lifecycle_descriptor_reconstruction" => true,
        "workspace_and_cache_reconstruction" => true,
        "hidden_host_fallback" => false,
    )
end

struct Phase9QualificationCounter{A} <: AbstractPottsDeviceCallback
    values::A
end
CorePotts.device_callback_requirements(::Phase9QualificationCounter) = ()
CorePotts.device_callback_effects(::Phase9QualificationCounter) =
    (DeviceObservationEffect(),)
CorePotts.device_callback_priority(::Phase9QualificationCounter) = 0

struct Phase9QualificationParameterization{V}
    volume::V
end
(parameterization::Phase9QualificationParameterization)(parameters) =
    ScientificComponentSet(energies = (parameterization.volume,),
        kinetic_modifiers = (PositiveYield(parameters.yield),))
CorePotts.device_callback_due(::Phase9QualificationCounter, mcs::Integer) = isodd(mcs)
@kernel function _phase9_counter_kernel!(values)
    index = @index(Global, Linear)
    index == 1 && (@inbounds values[1] += UInt32(1))
end
function CorePotts.execute_device_callback!(callback::Phase9QualificationCounter, integrator)
    kernel = _phase9_counter_kernel!(integrator.inner.plan.backend, 1)
    launch!(integrator.inner.plan, kernel, callback.values; ndrange = 1)
    return integrator
end

function _phase9_problem(::Val{N}; tspan = (0, 3), seed::UInt64 = 0x7068617365390001) where {N}
    dims = ntuple(_ -> 6, Val(N))
    spacing = ntuple(_ -> 1.0f0, Val(N))
    domain = CartesianDomain(dims; spacing)
    proposal = first_shell_relation(ProposalRole(), Val(N); spacing)
    surface = first_shell_relation(SurfaceRole(), Val(N); spacing)
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    volume = QuadraticVolumeHamiltonian(number_type = Float32)
    owners = fill(MediumOwner(1), dims)
    region = ntuple(_ -> 2:4, Val(N))
    fill!(view(owners, region...), CellOwner(1))
    logical = LogicalPottsState(owners, CellCapacity(3);
        cell_types = Dict(CellID(1) => CellTypeID(1)),
        medium_domains = (MediumID(1),), property_schema = required_properties(volume))
    property_values(logical, :target_volume)[1] = Float32(prod(length, region))
    property_values(logical, :volume_strength)[1] = 1.0f0
    components = ScientificComponentSet(energies = (volume,))
    model = PottsModel(proposal, tracker; components, observables = (:cell_count,))
    problem = PottsProblem(model, logical, domain, tspan; seed)
    return (; problem, logical, domain, proposal, tracker, components)
end

function _phase9_direct_integrator(name::String, fixture, algorithm)
    adaptor = _backend_adaptor(name)
    state = Adapt.adapt(adaptor, compile_scientific_state(
        deepcopy(fixture.problem.u0), fixture.domain, fixture.tracker))
    components = Adapt.adapt(adaptor, fixture.components)
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    plan = ExecutionPlan(backend; block_size = 128, metrics = ExecutionMetrics())
    integrator = init_scientific(state, fixture.proposal, components, algorithm;
        seed = fixture.problem.seed, plan)
    return integrator, backend, adaptor
end

function _phase9_interface_run(name::String, ::Val{N}, algorithm,
        seed::UInt64) where {N}
    fixture = _phase9_problem(Val(N); seed)
    direct, backend, adaptor = _phase9_direct_integrator(name, fixture, algorithm)
    wrapped = init(fixture.problem, algorithm; backend, adaptor, verbose = false,
        save_start = false, save_end = false)
    report = compatibility_report(fixture.problem, algorithm, backend)
    report.qualified || error("$name $(nameof(typeof(algorithm))) $N-D compatibility failed")
    direct_launches = direct.plan.metrics.launches
    wrapped_launches = wrapped.inner.plan.metrics.launches
    direct_syncs = direct.plan.metrics.host_synchronizations
    wrapped_syncs = wrapped.inner.plan.metrics.host_synchronizations
    direct_transfers = direct.plan.metrics.device_to_host_transfers
    wrapped_transfers = wrapped.inner.plan.metrics.device_to_host_transfers
    SciMLBase.step!(direct)
    SciMLBase.step!(wrapped)
    direct_launch_delta = direct.plan.metrics.launches - direct_launches
    wrapper_launch_delta = wrapped.inner.plan.metrics.launches - wrapped_launches
    direct_launch_delta == wrapper_launch_delta || error(
        "$name $(nameof(typeof(algorithm))) $N-D wrapper changed the launch graph")
    direct.plan.metrics.host_synchronizations - direct_syncs == 0 || error(
        "$name direct MCS introduced a host synchronization")
    wrapped.inner.plan.metrics.host_synchronizations - wrapped_syncs == 0 || error(
        "$name wrapped MCS introduced a host synchronization")
    direct.plan.metrics.device_to_host_transfers - direct_transfers == 0 || error(
        "$name direct MCS introduced a device-to-host transfer")
    wrapped.inner.plan.metrics.device_to_host_transfers - wrapped_transfers == 0 || error(
        "$name wrapped MCS introduced a device-to-host transfer")
    KernelAbstractions.synchronize(backend)
    lattice_storage(logical_state(direct)) == lattice_storage(logical_state(wrapped)) ||
        error("$name $(nameof(typeof(algorithm))) $N-D wrapper trajectory differs")

    checkpoint = capture_checkpoint(wrapped)
    restored = restore_checkpoint(checkpoint, fixture.problem, algorithm;
        backend, adaptor, verbose = false, save_start = false, save_end = false)
    SciMLBase.step!(wrapped)
    SciMLBase.step!(restored)
    KernelAbstractions.synchronize(backend)
    lattice_storage(logical_state(wrapped)) == lattice_storage(logical_state(restored)) ||
        error("$name $(nameof(typeof(algorithm))) $N-D wrapper restore differs")

    saved = solve(fixture.problem, algorithm; backend, adaptor, verbose = false,
        saveat = (1, 2), save_start = true, save_end = true)
    saved.t == [0, 1, 2, 3] || error(
        "$name $(nameof(typeof(algorithm))) $N-D save schedule differs")
    saved.u[1].state === saved.u[2].state && error(
        "$name $(nameof(typeof(algorithm))) $N-D snapshots alias")
    return Dict(
        "direct_launches_per_mcs" => direct_launch_delta,
        "wrapper_launches_per_mcs" => wrapper_launch_delta,
        "wrapper_extra_host_synchronizations" => 0,
        "wrapper_extra_device_to_host_transfers" => 0,
        "checkpoint_restore_exact" => true,
        "backend_resident_snapshots" => all(
            entry -> entry.residency == (name == "cpu" ? :host : :device), saved.u),
    )
end

"""Qualify the final SciML wrapper on the same CPU/Metal/ROCm semantic matrix."""
function qualify_phase9_backend(name::String)
    algorithms = (SequentialCPM(temperature = 2.0f0),
        CheckerboardSweepCPM(temperature = 2.0f0), LotteryCPM(temperature = 2.0f0))
    profiles = Dict{String, Any}()
    for (algorithm_index, algorithm) in enumerate(algorithms)
        label = string(nameof(typeof(algorithm)))
        dimensions = Dict{String, Any}()
        for N in (2, 3)
            seed = UInt64(0x7068617365391000) + UInt64(16algorithm_index + N)
            dimensions["$(N)d"] = _phase9_interface_run(name, Val(N), algorithm, seed)
        end
        profiles[label] = dimensions
    end

    fixture = _phase9_problem(Val(2); tspan = (0, 2))
    _, backend, adaptor = _phase9_direct_integrator(name, fixture, SequentialCPM())
    counter = _backend_array(name, zeros(UInt32, 1))
    callback_solution = solve(fixture.problem, SequentialCPM(temperature = 2.0f0);
        backend, adaptor, verbose = false, callback = Phase9QualificationCounter(counter),
        save_start = false, save_end = false)
    Array(counter)[1] == 1 || error("$name device callback did not remain executable")
    callback_solution.stats.host_callback_boundaries == 0 || error(
        "$name device callback introduced a host callback boundary")

    observable = solve(fixture.problem, SequentialCPM(temperature = 2.0f0);
        backend, adaptor, verbose = false, save_start = false,
        snapshot_policy = ObservableSnapshotPolicy(integrator ->
            (cell_count = n_cells(logical_state(integrator)),)))
    observable[PottsObservableHandle(:cell_count)] == [1] || error(
        "$name observable snapshot differs")

    parameter_model = PottsModel(fixture.proposal, fixture.tracker;
        parameters = (yield = 1.0f0,),
        parameterization = Phase9QualificationParameterization(
            first(fixture.components.energies)))
    parameter_problem = PottsProblem(parameter_model, fixture.logical,
        fixture.domain, (0, 2); seed = fixture.problem.seed)
    parameter_integrator = init(parameter_problem, SequentialCPM(temperature = 2.0f0);
        backend, adaptor, verbose = false, save_start = false, save_end = false)
    before_parameter_syncs = parameter_integrator.inner.plan.metrics.host_synchronizations
    before_parameter_transfers =
        parameter_integrator.inner.plan.metrics.device_to_host_transfers
    set_parameter!(parameter_integrator, PottsParameterHandle(:yield), 2.0f0)
    parameter_integrator.p[PottsParameterHandle(:yield)] == 2.0f0 || error(
        "$name typed parameter update did not commit")
    parameter_integrator.inner.plan.metrics.host_synchronizations ==
        before_parameter_syncs || error(
        "$name typed parameter update introduced a host synchronization")
    parameter_integrator.inner.plan.metrics.device_to_host_transfers ==
        before_parameter_transfers || error(
        "$name typed parameter update introduced a device-to-host transfer")
    solve!(parameter_integrator)

    ensemble = EnsembleProblem(fixture.problem; seed = fixture.problem.seed)
    ensemble_solution = solve(ensemble, SequentialCPM(temperature = 2.0f0),
        EnsembleSerial(); trajectories = 2, backend, adaptor, verbose = false,
        save_start = false, save_end = false)
    expected_seeds = [ensemble_seed(EnsembleSeedDerivationV1(),
        fixture.problem.seed, index) for index in 1:2]
    [solution.provenance.seed for solution in ensemble_solution.u] == expected_seeds ||
        error("$name semantic ensemble seeds differ")

    return Dict(
        "backend" => name,
        "algorithms" => collect(keys(profiles)),
        "dimensions" => [2, 3],
        "profiles" => profiles,
        "device_callback_zero_host_boundaries" => true,
        "explicit_observable_boundary" => true,
        "typed_parameter_update_gpu_compatible" => true,
        "serial_ensemble_semantic_seeds" => true,
        "same_device_threaded_gpu_qualified" => name == "cpu",
        "hidden_host_fallback" => false,
    )
end

function _phase10_problem(::Val{N}; tspan = (0, 2), seed = 0x7068617365310001) where {N}
    L2 = PottsToolkit.Authoring
    medium = L2.Medium(:Medium)
    cell = L2.CellType(:Cell)
    volume = L2.VolumeConstraint(cell => (target = 8.0, strength = 2.0))
    fluctuating = L2.FluctuatingVolumeConstraint(
        cell => (target = 8.0, strength = 1.0);
        eta = 0.5, noise = FixedMechanicalNoise(0.25f0))
    adhesion = L2.Adhesion(
        (medium, medium) => 0.0,
        (medium, cell) => 4.0,
        (cell, cell) => 1.0)
    age = L2.CellProperty(:age, cell; initial = 0.0,
        invariant = L2.ClosedPropertyInterval(0.0, 100.0),
        division = CloneOnDivision(), transition = PreserveOnTransition())
    growth = L2.StochasticPropertyUpdate(volume, cell; name = :growth,
        amount = 0.5, probability = 1.0)
    aging = L2.StochasticPropertyUpdate(age, cell; name = :aging,
        role = :value, amount = 1.0, probability = 1.0)
    downstream = Phase10QualificationEnergy(0.125f0)
    model = L2.PottsModel(
        medium, cell, volume, fluctuating, adhesion, age, growth, aging, downstream)
    dims = ntuple(_ -> 6, Val(N))
    mask = falses(dims)
    region = ntuple(_ -> 2:3, Val(N))
    fill!(view(mask, region...), true)
    problem = L2.problem(model, dims, L2.CellLayout(cell, 1, mask);
        capacity = 4, tspan, seed)
    return (; model, problem, cell, initial_target = 8.0f0)
end

function _phase10_direct_problem(problem::PottsProblem)
    return PottsProblem(problem.model, problem.u0, problem.geometry, problem.tspan;
        p = problem.p, capacity = problem.capacity, seed = problem.seed)
end

function _phase10_elongation_division_problem(::Val{N}; seed) where {N}
    L2 = PottsToolkit.Authoring
    medium = L2.Medium(:Medium)
    cell = L2.CellType(:DividingElongatedCell)
    region = N == 2 ? ntuple(_ -> 3:6, Val(N)) : ntuple(_ -> 2:4, Val(N))
    target_volume = prod(length, region)
    volume = L2.VolumeConstraint(
        cell => (target = target_volume, strength = 2.0))
    elongation = L2.Elongation(
        cell => (target = 2.0, strength = 4.0);
        target_division = CloneOnDivision())
    direction = ntuple(axis -> axis == 1 ? 1.0f0 : 0.0f0, Val(N))
    division = L2.Division(cell;
        geometry = VectorDivision(direction), schedule = OnceAtMCS(1))
    model = L2.PottsModel(medium, cell, volume, elongation, division)
    dims = ntuple(_ -> N == 2 ? 8 : 6, Val(N))
    mask = falses(dims)
    fill!(view(mask, region...), true)
    return L2.problem(model, dims, L2.CellLayout(cell, 1, mask);
        capacity = 4, tspan = (0, 1), seed)
end

function _phase10_reference_workloads()
    references = PottsToolkit.ReferenceModels
    return (
        ("biased_migration", references.single_cell_biased_migration_problem(
            (12, 12); target_volume = 4, capacity = 4,
            tspan = (0, 1), seed = 0x7068617365312101), false, 1, 1),
        ("chemotaxis_linear", references.chemotaxis_problem(
            (12, 12); profile = :linear, target_volume = 4, capacity = 4,
            tspan = (0, 1), seed = 0x7068617365312102), false, 1, 1),
        ("chemotaxis_half_normal", references.chemotaxis_problem(
            (12, 12); profile = :half_normal, target_volume = 4, capacity = 4,
            tspan = (0, 1), seed = 0x7068617365312103), false, 1, 1),
        ("chemotaxis_exponential", references.chemotaxis_problem(
            (12, 12); profile = :exponential, target_volume = 4, capacity = 4,
            tspan = (0, 1), seed = 0x7068617365312104), false, 1, 1),
        ("monolayer_growth", references.monolayer_growth_problem(
            (12, 12); target_volume = 4, division_target = 6,
            capacity = 8, tspan = (0, 1), seed = 0x7068617365312105), true, 1, 1),
        ("differential_adhesion", references.differential_adhesion_problem(
            (12, 12); cells_per_population = 2, capacity = 8,
            tspan = (0, 1), seed = 0x7068617365312106), false, 4, 4),
        ("angiogenesis_2d", references.elongation_driven_angiogenesis_problem(
            (12, 12); cells = 3, capacity = 8, target_volume = 4,
            target_elongation = 1.5, tspan = (0, 1),
            seed = 0x7068617365312107), false, 3, 3),
        ("angiogenesis_3d", references.elongation_driven_angiogenesis_problem(
            (8, 8, 8); cells = 2, capacity = 4, target_volume = 16,
            target_elongation = 1.5, tspan = (0, 1),
            seed = 0x7068617365312108), false, 2, 2),
        ("elongation_division_2d", _phase10_elongation_division_problem(
            Val(2); seed = 0x7068617365312109), true, 1, 2),
        ("elongation_division_3d", _phase10_elongation_division_problem(
            Val(3); seed = 0x7068617365312110), true, 1, 2),
    )
end

function _qualify_phase10_reference_workloads(name, backend, adaptor)
    results = Dict{String, Any}()
    for (label, problem, requires_failure_observation,
            initial_active_cells, expected_active_cells) in _phase10_reference_workloads()
        parentmodule(typeof(problem)) === CorePotts || error(
            "$name $label introduced a PottsToolkit runtime problem wrapper")
        n_cells(problem.u0) == initial_active_cells || error(
            "$name $label initial finite-cell count differs")
        algorithm = SequentialCPM(temperature = 2.0f0)
        report = PottsToolkit.backend_report(problem, algorithm, backend)
        report.qualified || error(
            "$name $label failed backend preflight: $(report.diagnostics)")
        integrator = init(problem, algorithm;
            backend, adaptor, verbose = false, save_start = false, save_end = false)
        metrics = integrator.inner.plan.metrics
        before_syncs = metrics.host_synchronizations
        before_transfers = metrics.device_to_host_transfers
        before_allocations = metrics.device_allocations
        before_launches = metrics.launches
        step!(integrator)
        synchronization_delta = metrics.host_synchronizations - before_syncs
        transfer_delta = metrics.device_to_host_transfers - before_transfers
        allocation_delta = metrics.device_allocations - before_allocations
        expected_syncs = requires_failure_observation ? 1 : 0
        expected_transfers = requires_failure_observation &&
            !(backend isa KernelAbstractions.CPU) ? 1 : 0
        synchronization_delta == expected_syncs || error(
            "$name $label warm MCS host synchronization differs from its declared observation boundary")
        transfer_delta == expected_transfers || error(
            "$name $label warm MCS transfer differs from its declared observation boundary")
        allocation_delta == 0 || error(
            "$name $label warm MCS introduced device allocation")
        KernelAbstractions.synchronize(backend)
        integrator.t == 1 || error("$name $label did not advance exactly one MCS")
        snapshot = logical_state(integrator)
        n_cells(snapshot) == expected_active_cells || error(
            "$name $label finite-cell count changed unexpectedly")
        results[label] = Dict(
            "dimensions" => ndims(lattice_storage(snapshot)),
            "algorithm" => string(nameof(typeof(algorithm))),
            "warm_mcs_launches" => metrics.launches - before_launches,
            "warm_mcs_host_synchronizations" => synchronization_delta,
            "warm_mcs_device_to_host_transfers" => transfer_delta,
            "warm_mcs_device_allocations" => allocation_delta,
            "required_failure_observation" => requires_failure_observation,
            "active_cells_after_smoke" => n_cells(snapshot),
        )
    end
    return results
end

"""Qualify Level 2 lowering plus resident scientific, mechanical, and lifecycle execution."""
function qualify_phase10_backend(name::String)
    adaptor = _backend_adaptor(name)
    probe = _backend_array(name, zeros(UInt8, 1))
    backend = KernelAbstractions.get_backend(probe)
    profiles = Dict{String, Any}()
    for N in (2, 3)
        fixture = _phase10_problem(Val(N); seed = 0x7068617365310000 + N)
        construction = @elapsed lowered = PottsToolkit.Authoring.lower(
            fixture.model; dimensions = N)
        normalization = @elapsed PottsToolkit.Authoring.normalize(fixture.model)
        direct_problem = _phase10_direct_problem(fixture.problem)
        typeof(fixture.problem) === typeof(direct_problem) || error(
            "$name Phase 10 $N-D authoring changed the concrete CorePotts problem type")
        parentmodule(typeof(fixture.problem)) === CorePotts || error(
            "$name Phase 10 $N-D introduced a PottsToolkit runtime problem wrapper")
        algorithm = LotteryCPM(temperature = 2.0f0)
        integrator = init(fixture.problem, algorithm;
            backend, adaptor, verbose = false, save_start = false, save_end = false)
        direct = init(direct_problem, algorithm;
            backend, adaptor, verbose = false, save_start = false, save_end = false)
        metrics = integrator.inner.plan.metrics
        direct_metrics = direct.inner.plan.metrics
        before_syncs = metrics.host_synchronizations
        before_transfers = metrics.device_to_host_transfers
        before_allocations = metrics.device_allocations
        before_launches = metrics.launches
        direct_before_syncs = direct_metrics.host_synchronizations
        direct_before_transfers = direct_metrics.device_to_host_transfers
        direct_before_allocations = direct_metrics.device_allocations
        direct_before_launches = direct_metrics.launches
        step!(integrator)
        step!(direct)
        synchronization_delta = metrics.host_synchronizations - before_syncs
        transfer_delta = metrics.device_to_host_transfers - before_transfers
        allocation_delta = metrics.device_allocations - before_allocations
        launch_delta = metrics.launches - before_launches
        direct_synchronization_delta =
            direct_metrics.host_synchronizations - direct_before_syncs
        direct_transfer_delta =
            direct_metrics.device_to_host_transfers - direct_before_transfers
        direct_allocation_delta = direct_metrics.device_allocations - direct_before_allocations
        direct_launch_delta = direct_metrics.launches - direct_before_launches
        synchronization_delta == 0 || error(
            "$name Phase 10 $N-D warm MCS introduced host synchronization")
        transfer_delta == 0 || error(
            "$name Phase 10 $N-D warm MCS introduced device-to-host transfer")
        allocation_delta == 0 || error(
            "$name Phase 10 $N-D warm MCS introduced device allocation")
        direct_synchronization_delta == synchronization_delta || error(
            "$name Phase 10 $N-D authoring changed warm-MCS synchronization")
        direct_transfer_delta == transfer_delta || error(
            "$name Phase 10 $N-D authoring changed warm-MCS transfer behavior")
        direct_allocation_delta == allocation_delta || error(
            "$name Phase 10 $N-D authoring changed warm-MCS device allocation")
        direct_launch_delta == launch_delta || error(
            "$name Phase 10 $N-D authoring changed the warm-MCS launch graph")
        KernelAbstractions.synchronize(backend)
        snapshot = logical_state(integrator)
        direct_snapshot = logical_state(direct)
        lattice_storage(snapshot) == lattice_storage(direct_snapshot) || error(
            "$name Phase 10 $N-D authoring trajectory differs from direct CorePotts")
        property_values(snapshot, :volume__target) ==
            property_values(direct_snapshot, :volume__target) || error(
            "$name Phase 10 $N-D authoring property transaction differs from direct CorePotts")
        property_values(snapshot, :age) == property_values(direct_snapshot, :age) || error(
            "$name Phase 10 $N-D custom property differs from direct CorePotts")
        property_value(snapshot, :volume__target, CellID(1)) == 8.5f0 || error(
            "$name Phase 10 $N-D stochastic lifecycle property update differs")
        property_value(snapshot, :age, CellID(1)) == 1.0f0 || error(
            "$name Phase 10 $N-D custom-property transaction differs")
        profiles["$(N)d"] = Dict(
            "semantic_fingerprint" => lowered.normalized.fingerprint.digest,
            "normalization_seconds" => normalization,
            "lowering_seconds" => construction,
            "warm_mcs_launches" => launch_delta,
            "warm_mcs_host_synchronizations" => synchronization_delta,
            "warm_mcs_device_to_host_transfers" => transfer_delta,
            "warm_mcs_device_allocations" => allocation_delta,
            "matched_direct_launches" => direct_launch_delta,
            "matched_direct_exact_state" => true,
            "runtime_problem_wrapper" => false,
            "stochastic_property_transaction" => true,
            "mechanical_component" => true,
            "downstream_component" => true,
            "custom_property" => true,
        )
    end
    reference_workloads = _qualify_phase10_reference_workloads(name, backend, adaptor)
    return Dict(
        "backend" => name,
        "dimensions" => [2, 3],
        "profiles" => profiles,
        "reference_workloads" => reference_workloads,
        "required_reference_families" => [
            "biased_migration", "chemotaxis", "monolayer_growth",
            "differential_adhesion", "elongation_driven_angiogenesis"],
        "public_corepotts_lowering" => true,
        "hidden_host_fallback" => false,
    )
end

"""Qualify ordered, simultaneous, addressed Level 1 rules on the selected real backend."""
function qualify_phase11_backend(name::String)
    adaptor = _backend_adaptor(name)
    probe = _backend_array(name, zeros(UInt8, 1))
    backend = KernelAbstractions.get_backend(probe)
    profiles = Dict{String, Any}()
    for N in (2, 3)
        medium = PottsToolkit.Medium(Symbol(:phase11_medium_, N))
        cell = PottsToolkit.CellType(Symbol(:phase11_cell_, N))
        phase11_age = PottsToolkit.CellProperty(:phase11_age, cell;
            initial = 0.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_target = PottsToolkit.CellProperty(:phase11_target, cell;
            initial = 2.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_uniform = PottsToolkit.CellProperty(:phase11_uniform, cell;
            initial = 0.5f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_normal = PottsToolkit.CellProperty(:phase11_normal, cell;
            initial = 0.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_direction = PottsToolkit.CellProperty(:phase11_direction, cell;
            initial = zero(SVector{N, Float32}), division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_edges = PottsToolkit.CellProperty(:phase11_edges, cell;
            initial = Int64(0), division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_boundary_sites = PottsToolkit.CellProperty(:phase11_boundary_sites, cell;
            initial = Int64(0), division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_contact_measure = PottsToolkit.CellProperty(
            :phase11_contact_measure, cell;
            initial = 0.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_exact_widen = PottsToolkit.CellProperty(:phase11_exact_widen, cell;
            initial = Int64(0), division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_neighbor_count = PottsToolkit.CellProperty(:phase11_neighbor_count, cell;
            initial = Int64(0), division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_neighbor_signal = PottsToolkit.CellProperty(:phase11_neighbor_signal, cell;
            initial = 5.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_neighbor_sum = PottsToolkit.CellProperty(:phase11_neighbor_sum, cell;
            initial = 0.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_neighbor_mean = PottsToolkit.CellProperty(:phase11_neighbor_mean, cell;
            initial = 0.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_scalar_inventory = PottsToolkit.CellProperty(
            :phase11_scalar_inventory, cell;
            initial = 2.0f0, division = CloneOnDivision(),
            transition = PreserveOnTransition())
        phase11_field = PottsToolkit.Field(:phase11_field;
            boundary = PottsToolkit.FixedValue(0.0f0),
            interpolation = PottsToolkit.Nearest())
        phase11_cell_role = PottsToolkit.CellRole(:phase11_cells)
        phase11_field_role = PottsToolkit.FieldRole(:phase11_signal)
        phase11_role_chemotaxis = PottsToolkit.Chemotaxis(
            phase11_field_role, phase11_cell_role => 0.0f0;
            response = PottsToolkit.MichaelisMentenResponse(1.0f0),
            mode = PottsToolkit.RetractionChemotaxis())
        phase11_coupling = PottsToolkit.bind(PottsToolkit.ModelFragment(
                :phase11_coupling, phase11_role_chemotaxis;
                requires = (phase11_cell_role, phase11_field_role),
                exports = (phase11_role_chemotaxis,)),
            phase11_cell_role => cell, phase11_field_role => phase11_field)
        phase11_rate = PottsToolkit.CellParameter(:phase11_rate, cell => 0.5f0)
        phase11_extension = Phase11ExtensionEnergy(0.0f0)
        first_phase = PottsToolkit.Phase(:phase11_first)
        second_phase = PottsToolkit.Phase(:phase11_second; after = first_phase)
        aging = PottsToolkit.@rule phase = first_phase phase11_age(owner) =
            phase11_age(owner) + phase11_rate(owner) +
            draw(Bernoulli(1.0f0); label = :aging)
        uniform_rule = PottsToolkit.@rule phase = first_phase phase11_uniform(owner) =
            draw(Uniform(0.0f0, 1.0f0); label = :uniform)
        normal_rule = PottsToolkit.@rule phase = first_phase phase11_normal(owner) =
            draw(Normal(0.0f0, 1.0f0); label = :normal)
        direction_rule = PottsToolkit.@rule phase = first_phase phase11_direction(owner) =
            draw(UnitVector($N); label = :direction)
        edge_rule = PottsToolkit.@rule phase = first_phase phase11_edges(owner) =
            contact_edge_count(owner, Contacting(), AnyFiniteCell())
        boundary_site_rule = PottsToolkit.@rule phase = first_phase phase11_boundary_sites(owner) =
            boundary_site_count(owner, Contacting(), AnyFiniteCell())
        contact_measure_rule = PottsToolkit.@rule phase = first_phase phase11_contact_measure(owner) =
            contact_measure(owner, Contacting(), CellTypeFilter(cell))
        exact_widen_rule = PottsToolkit.Rule(
            phase11_exact_widen, :owner, PottsToolkit.RuleLiteral(Int32(7));
            phase = first_phase)
        neighbor_count_rule = PottsToolkit.@rule phase = first_phase phase11_neighbor_count(owner) =
            neighbor_cell_count(owner, Contacting(), AnyFiniteCell())
        neighbor_sum_rule = PottsToolkit.@rule phase = first_phase phase11_neighbor_sum(owner) =
            neighbor_property_sum(
                phase11_neighbor_signal, owner, Contacting(), AnyFiniteCell())
        neighbor_mean_rule = PottsToolkit.@rule phase = first_phase phase11_neighbor_mean(owner) =
            neighbor_property_mean(phase11_neighbor_signal, owner,
                Contacting(), AnyFiniteCell(); empty = 0.0f0)
        scalar_inventory_rule = PottsToolkit.@rule phase = first_phase phase11_scalar_inventory(owner) =
            if phase11_scalar_inventory(owner) >= 2.0f0 &&
                    !(phase11_scalar_inventory(owner) == 3.0f0)
                clamp(max(abs(-phase11_scalar_inventory(owner)), sqrt(4.0f0)),
                    0.0f0, 10.0f0) + exp(0.0f0) + log(1.0f0) + sin(0.0f0) +
                    cos(0.0f0) + tan(0.0f0)
            else
                ifelse(phase11_scalar_inventory(owner) != 0.0f0,
                    min(phase11_scalar_inventory(owner)^2 / 2.0f0, 5.0f0), 0.0f0)
            end
        dependent = PottsToolkit.@rule phase = second_phase phase11_target(owner) =
            clamp(phase11_age(owner) + 2, 0, 100)
        model = PottsToolkit.PottsModel(
            medium, cell, phase11_age, phase11_target, phase11_uniform,
            phase11_normal, phase11_direction, phase11_edges,
            phase11_boundary_sites, phase11_contact_measure, phase11_exact_widen,
            phase11_neighbor_count, phase11_neighbor_signal, phase11_neighbor_sum,
            phase11_neighbor_mean, phase11_scalar_inventory, phase11_field,
            phase11_coupling, phase11_rate, phase11_extension,
            aging, uniform_rule, normal_rule, direction_rule, edge_rule,
            boundary_site_rule, contact_measure_rule, exact_widen_rule,
            neighbor_count_rule, neighbor_sum_rule, neighbor_mean_rule,
            scalar_inventory_rule, dependent)
        shape = ntuple(_ -> N == 2 ? 6 : 4, Val(N))
        labels = fill(UInt64(1), shape)
        for site in CartesianIndices(labels)
            site[1] > shape[1] ÷ 2 && (labels[site] = UInt64(2))
        end
        domain = PottsToolkit.CartesianDomain(shape)
        problem = PottsToolkit.PottsProblem(
            model, domain,
            PottsToolkit.Layout(PottsToolkit.LabelledCells(
                labels, (1 => cell, 2 => cell)));
            fields = (phase11_field => fill(1.0f0, shape),),
            capacity = 2, tspan = (0, 2), seed = 0x7068617365311000 + N)
        algorithm = CheckerboardSweepCPM(temperature = 1.0f0)
        integrator = init(problem, algorithm;
            backend, adaptor, verbose = false,
            save_start = false, save_end = false)
        metrics = integrator.inner.plan.metrics
        before_syncs = metrics.host_synchronizations
        before_transfers = metrics.device_to_host_transfers
        before_allocations = metrics.device_allocations
        before_launches = metrics.launches
        step!(integrator)
        synchronization_delta = metrics.host_synchronizations - before_syncs
        transfer_delta = metrics.device_to_host_transfers - before_transfers
        allocation_delta = metrics.device_allocations - before_allocations
        launch_delta = metrics.launches - before_launches
        synchronization_delta == 0 || error(
            "$name Phase 11 $N-D rule execution introduced host synchronization")
        transfer_delta == 0 || error(
            "$name Phase 11 $N-D rule execution introduced device-to-host transfer")
        allocation_delta == 0 || error(
            "$name Phase 11 $N-D rule execution introduced device allocation")
        KernelAbstractions.synchronize(backend)
        snapshot = logical_state(integrator)
        property_value(snapshot, :phase11_age, CellID(1)) == 1.5f0 || error(
            "$name Phase 11 $N-D parameter/Bernoulli rule produced the wrong value")
        property_value(snapshot, :phase11_target, CellID(1)) == 3.5f0 || error(
            "$name Phase 11 $N-D ordered phase did not observe the prior phase commit")
        property_value(snapshot, :phase11_exact_widen, CellID(1)) == Int64(7) || error(
            "$name Phase 11 $N-D exact integer widening produced the wrong value")
        property_value(snapshot, :phase11_neighbor_count, CellID(1)) == Int64(1) || error(
            "$name Phase 11 $N-D distinct-neighbor count produced the wrong value")
        property_value(snapshot, :phase11_neighbor_sum, CellID(1)) == 5.0f0 || error(
            "$name Phase 11 $N-D distinct-neighbor property sum produced the wrong value")
        property_value(snapshot, :phase11_neighbor_mean, CellID(1)) == 5.0f0 || error(
            "$name Phase 11 $N-D distinct-neighbor property mean produced the wrong value")
        property_value(snapshot, :phase11_scalar_inventory, CellID(1)) == 4.0f0 || error(
            "$name Phase 11 $N-D closed scalar inventory produced the wrong value")
        uniform_value = property_value(snapshot, :phase11_uniform, CellID(1))
        0.0f0 < uniform_value < 1.0f0 || error(
            "$name Phase 11 $N-D Uniform rule violated its open interval")
        normal_value = property_value(snapshot, :phase11_normal, CellID(1))
        isfinite(normal_value) || error(
            "$name Phase 11 $N-D Normal rule produced a non-finite value")
        direction_value = property_value(snapshot, :phase11_direction, CellID(1))
        isapprox(sum(abs2, direction_value), 1.0f0; atol = 8eps(Float32)) || error(
            "$name Phase 11 $N-D unit-vector rule produced a non-unit vector")
        query_relation = first_shell_relation(
            SpatialQueryRole(), Val(N); spacing = domain.spacing)
        medium_types = MediumTypeTable(MediumID(1) => CellTypeID(2))
        for id in (CellID(1), CellID(2))
            owner = CellOwner(id)
            expected_edges = contact_edge_count(snapshot, domain, query_relation,
                owner, CorePotts.AnyFiniteCell(), medium_types)
            expected_boundary_sites = boundary_site_count(snapshot, domain,
                query_relation, owner, CorePotts.AnyFiniteCell(), medium_types)
            expected_measure = contact_measure(snapshot, domain, query_relation,
                owner, CorePotts.CellTypeFilter(CellTypeID(1)), medium_types)
            property_value(snapshot, :phase11_edges, id) == expected_edges || error(
                "$name Phase 11 $N-D contact-edge query differs from the oracle")
            property_value(snapshot, :phase11_boundary_sites, id) ==
                expected_boundary_sites || error(
                "$name Phase 11 $N-D boundary-site query differs from the oracle")
            property_value(snapshot, :phase11_contact_measure, id) ==
                expected_measure || error(
                "$name Phase 11 $N-D contact-measure query differs from the oracle")
        end
        profiles["$(N)d"] = Dict(
            "ordered_phase_value" => 3.5,
            "addressed_draw_value" => 1.0,
            "cell_parameter_value" => 0.5,
            "exact_output_conversion" => true,
            "closed_scalar_inventory" => true,
            "exact_distinct_neighbor_queries" => true,
            "level1_nearest_fixed_field" => true,
            "typed_fragment_roles" => true,
            "downstream_custom_physics" => true,
            "uniform_open_interval" => true,
            "normal_finite" => true,
            "unit_vector_norm" => sum(abs2, direction_value),
            "exact_spatial_queries" => true,
            "warm_mcs_launches" => launch_delta,
            "warm_mcs_host_synchronizations" => synchronization_delta,
            "warm_mcs_device_to_host_transfers" => transfer_delta,
            "warm_mcs_device_allocations" => allocation_delta,
            "isbits_rule_effect" => isbits(only(lifecycle_events(problem.model)).effect),
        )
    end
    return Dict(
        "backend" => name,
        "dimensions" => [2, 3],
        "profiles" => profiles,
        "simultaneous_snapshot_commit" => true,
        "explicit_phase_order" => true,
        "semantic_rng_addressing" => true,
        "hidden_host_fallback" => false,
    )
end

"""Measure Level 2 host work separately from identical CorePotts warm execution."""
function measure_phase10_backend(name::String; steps::Int = 5)
    steps > 0 || throw(ArgumentError("Phase 10 steady-state sample size must be positive"))
    adaptor = _backend_adaptor(name)
    construction_seconds = @elapsed fixture = _phase10_problem(Val(2);
        tspan = (0, 2 * steps + 4), seed = 0x7068617365311000)
    normalization_seconds = @elapsed normalized = PottsToolkit.Authoring.normalize(fixture.model)
    lowering_seconds = @elapsed lowered = PottsToolkit.Authoring.lower(
        fixture.model; dimensions = 2)
    direct_problem = _phase10_direct_problem(fixture.problem)
    prototype = _backend_array(name, zeros(UInt8, 1))
    backend = KernelAbstractions.get_backend(prototype)
    algorithm = LotteryCPM(temperature = 2.0f0)
    level2_initialization_seconds = @elapsed level2 = init(fixture.problem, algorithm;
        backend, adaptor, verbose = false, save_start = false, save_end = false)
    direct_initialization_seconds = @elapsed direct = init(direct_problem, algorithm;
        backend, adaptor, verbose = false, save_start = false, save_end = false)
    _timed_phase9_steps!(level2, 1)
    _timed_phase9_steps!(direct, 1)
    level2_metrics = level2.inner.plan.metrics
    direct_metrics = direct.inner.plan.metrics
    level2_launches_before = level2_metrics.launches
    level2_syncs_before = level2_metrics.host_synchronizations
    level2_transfers_before = level2_metrics.device_to_host_transfers
    level2_allocations_before = level2_metrics.device_allocations
    direct_launches_before = direct_metrics.launches
    level2_steady_seconds = _timed_phase9_steps!(level2, steps)
    direct_steady_seconds = _timed_phase9_steps!(direct, steps)
    KernelAbstractions.synchronize(backend)
    level2_metrics.launches - level2_launches_before ==
        direct_metrics.launches - direct_launches_before || error(
        "$name Phase 10 benchmark detected an authoring-dependent warm launch graph")
    level2_metrics.host_synchronizations == level2_syncs_before || error(
        "$name Phase 10 benchmark detected a warm host synchronization")
    level2_metrics.device_to_host_transfers == level2_transfers_before || error(
        "$name Phase 10 benchmark detected a warm device-to-host transfer")
    level2_metrics.device_allocations == level2_allocations_before || error(
        "$name Phase 10 benchmark detected a warm device allocation")
    return Dict(
        "backend" => name,
        "dimension" => 2,
        "algorithm" => string(nameof(typeof(algorithm))),
        "steps_per_steady_sample" => steps,
        "level2_problem_type" => string(parentmodule(typeof(fixture.problem)), ".",
            nameof(typeof(fixture.problem))),
        "direct_problem_type" => string(parentmodule(typeof(direct_problem)), ".",
            nameof(typeof(direct_problem))),
        "runtime_problem_wrapper" => false,
        "construction_seconds" => construction_seconds,
        "normalization_seconds" => normalization_seconds,
        "lowering_seconds" => lowering_seconds,
        "level2_initialization_seconds" => level2_initialization_seconds,
        "direct_initialization_seconds" => direct_initialization_seconds,
        "level2_steady_mcs_seconds" => level2_steady_seconds,
        "direct_steady_mcs_seconds" => direct_steady_seconds,
        "level2_to_direct_steady_ratio" => level2_steady_seconds / direct_steady_seconds,
        "level2_warm_launches" => level2_metrics.launches - level2_launches_before,
        "direct_warm_launches" => direct_metrics.launches - direct_launches_before,
        "level2_warm_host_synchronizations" =>
            level2_metrics.host_synchronizations - level2_syncs_before,
        "level2_warm_device_to_host_transfers" =>
            level2_metrics.device_to_host_transfers - level2_transfers_before,
        "level2_warm_device_allocations" =>
            level2_metrics.device_allocations - level2_allocations_before,
        "semantic_fingerprint" => normalized.fingerprint.digest,
        "lowered_semantic_fingerprint" => lowered.normalized.fingerprint.digest,
        "timed_regions_backend_synchronized" => true,
        "interpretation" =>
            "Level 2 has no runtime wrapper; dedicated paper workloads set regression thresholds",
    )
end

function _phase10_reference_measurement_specs(profile::String, horizon::Int)
    references = PottsToolkit.ReferenceModels
    if profile == "smoke"
        migration_shape = (24, 24)
        sorting_shape = (24, 24)
        angiogenesis_2d_shape = (24, 24)
        angiogenesis_3d_shape = (12, 12, 12)
        target_volume = 16
        sorting_cells = 2
        angiogenesis_2d_cells = 3
        angiogenesis_3d_cells = 2
        angiogenesis_3d_target = 32
        growth_capacity = 16
        sorting_capacity = 8
        angiogenesis_2d_capacity = 8
        angiogenesis_3d_capacity = 4
    elseif profile == "full"
        migration_shape = (48, 48)
        sorting_shape = (32, 32)
        angiogenesis_2d_shape = (48, 48)
        angiogenesis_3d_shape = (24, 24, 24)
        target_volume = 32
        sorting_cells = 8
        angiogenesis_2d_cells = 12
        angiogenesis_3d_cells = 8
        angiogenesis_3d_target = 64
        growth_capacity = 128
        sorting_capacity = 64
        angiogenesis_2d_capacity = 64
        angiogenesis_3d_capacity = 32
    elseif profile == "throughput"
        migration_shape = (256, 256)
        sorting_shape = (256, 256)
        angiogenesis_2d_shape = (256, 256)
        angiogenesis_3d_shape = (64, 64, 64)
        target_volume = 32
        sorting_cells = 16
        angiogenesis_2d_cells = 16
        angiogenesis_3d_cells = 8
        angiogenesis_3d_target = 64
        growth_capacity = 128
        sorting_capacity = 64
        angiogenesis_2d_capacity = 64
        angiogenesis_3d_capacity = 32
    else
        throw(ArgumentError("Phase 12 profile must be smoke, full, or throughput"))
    end

    measurement_spec(; label, family, dimensions, requires_lifecycle_observation,
        model_builder, problem_builder, problem_binding_required = false,
        problem_binding_builder = identity,
        compatible_algorithms = (:SequentialCPM, :SequentialEquilibrium,
            :CheckerboardSweepCPM, :LotteryCPM)) = (
        label,
        family,
        scale = profile,
        dimensions,
        requires_lifecycle_observation,
        problem_binding_required,
        compatible_algorithms,
        model_builder,
        problem_binding_builder,
        problem_builder,
    )

    chemotaxis_spec(label, family, profile_name, seed) = measurement_spec(;
        label, family, dimensions = length(migration_shape),
        requires_lifecycle_observation = false,
        problem_binding_required = true,
        compatible_algorithms = (:SequentialCPM, :CheckerboardSweepCPM, :LotteryCPM),
        model_builder = () -> references.chemotaxis_model(; target_volume),
        problem_binding_builder = model ->
            PottsToolkit.Authoring._realize_problem_fields(model,
                PottsToolkit.CartesianDomain(migration_shape),
                (references._chemotaxis_field_binding(
                    model, migration_shape, profile_name),)),
        problem_builder = () -> references.chemotaxis_problem(
            migration_shape; profile = profile_name, target_volume,
            capacity = 4, tspan = (0, horizon), seed),
    )
    return (
        chemotaxis_spec("biased_migration", "single_cell_migration", :linear,
            0x7068617365313101),
        chemotaxis_spec("chemotaxis_linear", "prescribed_gradient_chemotaxis", :linear,
            0x7068617365313102),
        chemotaxis_spec("chemotaxis_half_normal", "prescribed_gradient_chemotaxis",
            :half_normal, 0x7068617365313103),
        chemotaxis_spec("chemotaxis_exponential", "prescribed_gradient_chemotaxis",
            :exponential, 0x7068617365313104),
        measurement_spec(;
            label = "monolayer_growth",
            family = "monolayer_growth",
            dimensions = length(migration_shape),
            requires_lifecycle_observation = true,
            compatible_algorithms = (:SequentialCPM, :CheckerboardSweepCPM, :LotteryCPM),
            model_builder = () -> references.monolayer_growth_model(
                target_volume = 8, division_target = 16),
            problem_builder = () -> references.monolayer_growth_problem(
                migration_shape; target_volume = 8, division_target = 16,
                capacity = growth_capacity,
                tspan = (0, horizon), seed = 0x7068617365313105),
        ),
        measurement_spec(;
            label = "differential_adhesion",
            family = "differential_adhesion_sorting",
            dimensions = length(sorting_shape),
            requires_lifecycle_observation = false,
            compatible_algorithms = (:SequentialCPM, :SequentialEquilibrium,
                :CheckerboardSweepCPM, :LotteryCPM),
            model_builder = () -> references.differential_adhesion_model(
                target_volume = profile == "smoke" ? 16 : 20),
            problem_builder = () -> references.differential_adhesion_problem(
                sorting_shape; cells_per_population = sorting_cells,
                target_volume = profile == "smoke" ? 16 : 20,
                capacity = sorting_capacity,
                tspan = (0, horizon), seed = 0x7068617365313106),
        ),
        measurement_spec(;
            label = "angiogenesis_2d",
            family = "elongation_driven_angiogenesis",
            dimensions = length(angiogenesis_2d_shape),
            requires_lifecycle_observation = false,
            compatible_algorithms = (:SequentialCPM, :SequentialEquilibrium),
            model_builder = () -> references.elongation_driven_angiogenesis_model(
                target_volume = 16,
                target_elongation = profile == "smoke" ? 1.5 : 3),
            problem_builder = () -> references.elongation_driven_angiogenesis_problem(
                angiogenesis_2d_shape; cells = angiogenesis_2d_cells,
                target_volume = 16,
                target_elongation = profile == "smoke" ? 1.5 : 3,
                capacity = angiogenesis_2d_capacity,
                tspan = (0, horizon), seed = 0x7068617365313107),
        ),
        measurement_spec(;
            label = "angiogenesis_3d",
            family = "elongation_driven_angiogenesis",
            dimensions = length(angiogenesis_3d_shape),
            requires_lifecycle_observation = false,
            compatible_algorithms = (:SequentialCPM, :SequentialEquilibrium),
            model_builder = () -> references.elongation_driven_angiogenesis_model(
                target_volume = angiogenesis_3d_target,
                target_elongation = profile == "smoke" ? 1.5 : 3),
            problem_builder = () -> references.elongation_driven_angiogenesis_problem(
                angiogenesis_3d_shape; cells = angiogenesis_3d_cells,
                target_volume = angiogenesis_3d_target,
                target_elongation = profile == "smoke" ? 1.5 : 3,
                capacity = angiogenesis_3d_capacity,
                tspan = (0, horizon), seed = 0x7068617365313108),
        ),
    )
end

_metric_snapshot(metrics::ExecutionMetrics) = (
    launches = metrics.launches,
    host_synchronizations = metrics.host_synchronizations,
    host_to_device_transfers = metrics.host_to_device_transfers,
    device_to_host_transfers = metrics.device_to_host_transfers,
    host_allocations = metrics.host_allocations,
    device_allocations = metrics.device_allocations,
    host_allocated_bytes = metrics.host_allocated_bytes,
    device_allocated_bytes = metrics.device_allocated_bytes,
)

function _metric_delta(after, before)
    return Dict(string(key) => getproperty(after, key) - getproperty(before, key)
        for key in keys(after))
end

function _timed_phase10_sample!(integrator::PottsIntegrator, steps::Int)
    KernelAbstractions.synchronize(integrator.inner.plan.backend)
    sample = @timed begin
        SciMLBase.step!(integrator, steps)
        KernelAbstractions.synchronize(integrator.inner.plan.backend)
    end
    return (seconds_per_mcs = sample.time / steps,
        host_allocated_bytes_per_mcs = sample.bytes / steps)
end

_component_array_bytes(::StaticArrays.StaticArray) = 0
_component_array_bytes(value::AbstractArray) = sizeof(eltype(value)) * length(value)
_component_array_bytes(values::Tuple) = sum(_component_array_bytes, values; init = 0)
_component_array_bytes(values::NamedTuple) = sum(_component_array_bytes, values; init = 0)
function _component_array_bytes(value)
    type = typeof(value)
    isprimitivetype(type) && return 0
    value isa Union{AbstractString, Symbol, Type, Function, Module} && return 0
    isstructtype(type) || return 0
    return sum(index -> _component_array_bytes(getfield(value, index)),
        1:fieldcount(type); init = 0)
end

function _phase10_residency(inner::ScientificPottsIntegrator)
    metrics = inner.plan.metrics
    state_bytes = scientific_state_bytes(inner.state)
    component_bytes = _component_array_bytes(inner.components)
    workspace_bytes = inner.plan.backend isa KernelAbstractions.CPU ?
                      metrics.host_allocated_bytes : metrics.device_allocated_bytes
    return Dict(
        "scientific_state_bytes" => state_bytes,
        "component_array_bytes" => component_bytes,
        "tracked_workspace_bytes" => workspace_bytes,
        "backend_resident_bytes" => state_bytes + component_bytes + workspace_bytes,
        "device_resident_bytes" => inner.plan.backend isa KernelAbstractions.CPU ?
                                   0 : state_bytes + component_bytes + workspace_bytes,
        "lifecycle_workspace_bytes" => compiled_lifecycle_bytes(inner.lifecycle),
    )
end

function _phase10_kernel_resource_evidence(name::String)
    return Dict(
        "kernel_compilation_qualified" => true,
        "dynamic_device_invocation_rejected_by_ci" => true,
        "numeric_register_count_available" => false,
        "measurement_boundary" => name == "cpu" ? "not applicable to the CPU backend" :
            "KernelAbstractions exposes no portable per-kernel register-count interface",
        "full_resource_capture" =>
            "Phase 12 backend-native profiling; never infer register counts from occupancy",
    )
end

function _validate_reference_mcs_report(name, label, algorithm, report, sites)
    expected_sites = UInt64(sites)
    if algorithm isa AbstractSequentialCPMAlgorithm || algorithm isa CheckerboardSweepCPM
        report.scheduler_candidates == expected_sites || error(
            "$name $label $(nameof(typeof(algorithm))) scheduler budget differs from mutable sites")
        report.activated_attempts == expected_sites || error(
            "$name $label $(nameof(typeof(algorithm))) did not activate exactly one attempt per mutable site")
    elseif algorithm isa LotteryCPM
        report.scheduler_candidates == expected_sites * report.internal_rounds || error(
            "$name $label LotteryCPM scheduler accounting differs from sites times rounds")
    else
        error("Phase 12 reference accounting is undefined for $(typeof(algorithm))")
    end
    report.realized_proposals == report.dynamic_conflicts +
        report.constraint_rejections + report.acceptance_rejections +
        report.accepted_copies || error(
        "$name $label $(nameof(typeof(algorithm))) proposal accounting does not reconcile")
    report.activated_attempts == report.same_owner_no_ops + report.boundary_no_ops +
        report.immutable_recipient_no_ops + report.dynamic_conflicts +
        report.constraint_rejections + report.acceptance_rejections +
        report.accepted_copies || error(
        "$name $label $(nameof(typeof(algorithm))) attempt accounting does not reconcile")
    return nothing
end

"""Measure compatible mandatory reference families for one scientific algorithm."""
function measure_phase10_reference_backend(name::String; profile::String = "smoke",
        algorithm::AbstractPottsAlgorithm = SequentialCPM(temperature = 2.0f0),
        skip_incompatible::Bool = false,
        real_type::Type{<:AbstractFloat} = Float32)
    samples, steps, warmup_steps = profile == "smoke" ? (2, 1, 1) :
                                     profile == "throughput" ? (10, 1, 2) :
                                     (10, 5, 2)
    horizon = 1 + warmup_steps + samples * steps
    adaptor = _backend_adaptor(name)
    probe = _backend_array(name, zeros(UInt8, 1))
    backend = KernelAbstractions.get_backend(probe)
    workloads = Dict{String, Any}()
    exclusions = Dict{String, Any}()

    for spec in _phase10_reference_measurement_specs(profile, horizon)
        algorithm_name = nameof(typeof(algorithm))
        if algorithm_name ∉ spec.compatible_algorithms
            skip_incompatible || error(
                "$name $(spec.label) is not scientifically compatible with $algorithm_name")
            exclusions[spec.label] = [
                "$algorithm_name is outside this workload's scientific guarantee profile"]
            continue
        end
        model_timing = @timed SciMLBase.remake(spec.model_builder();
            numerics = CorePotts.NumericalPolicy(real_type))
        model = model_timing.value
        normalization_timing = @timed PottsToolkit.Authoring.normalize(model)
        normalized = normalization_timing.value
        problem_binding_timing = @timed spec.problem_binding_builder(model)
        problem_bound_model = problem_binding_timing.value
        bound_normalization_timing =
            @timed PottsToolkit.Authoring.normalize(problem_bound_model)
        bound_normalized = bound_normalization_timing.value
        dimensions = spec.dimensions
        lowering_timing =
            @timed PottsToolkit.Authoring.lower(problem_bound_model; dimensions)
        lowered = lowering_timing.value
        problem_timing = @timed SciMLBase.remake(spec.problem_builder();
            model = lowered.core_model)
        problem = problem_timing.value
        parentmodule(typeof(problem)) === CorePotts || error(
            "$name $(spec.label) introduced a runtime authoring wrapper")
        backend_report = PottsToolkit.backend_report(problem, algorithm, backend)
        if !backend_report.qualified
            skip_incompatible || error(
                "$name $(spec.label) failed performance preflight: $(backend_report.messages)")
            exclusions[spec.label] = collect(backend_report.messages)
            continue
        end

        initialization_timing = @timed init(problem, algorithm;
            backend, adaptor, verbose = false, save_start = false, save_end = false)
        integrator = initialization_timing.value
        first_mcs = _timed_phase10_sample!(integrator, 1)
        _timed_phase10_sample!(integrator, warmup_steps)
        metrics = integrator.inner.plan.metrics
        warm_before = _metric_snapshot(metrics)
        steady_samples = [_timed_phase10_sample!(integrator, steps) for _ in 1:samples]
        warm_after = _metric_snapshot(metrics)
        seconds = getproperty.(steady_samples, :seconds_per_mcs)
        host_bytes = getproperty.(steady_samples, :host_allocated_bytes_per_mcs)

        observation_before = _metric_snapshot(metrics)
        report = current_mcs_report(integrator)
        snapshot = logical_state(integrator)
        observation_after = _metric_snapshot(metrics)
        report === nothing && error("$name $(spec.label) produced no completed-MCS report")
        median_seconds = median(seconds)
        warm_delta = _metric_delta(warm_after, warm_before)
        observation_delta = _metric_delta(observation_after, observation_before)
        sites = length(lattice_storage(snapshot))
        expected_lifecycle_observations = spec.requires_lifecycle_observation ?
                                          samples * steps : 0
        expected_lifecycle_transfers = spec.requires_lifecycle_observation &&
            !(backend isa KernelAbstractions.CPU) ? samples * steps : 0
        warm_delta["host_synchronizations"] == expected_lifecycle_observations || error(
            "$name $(spec.label) introduced an undeclared warm host synchronization")
        warm_delta["device_to_host_transfers"] == expected_lifecycle_transfers || error(
            "$name $(spec.label) introduced an undeclared warm device-to-host transfer")
        warm_delta["host_to_device_transfers"] == 0 || error(
            "$name $(spec.label) introduced a warm host-to-device transfer")
        warm_delta["device_allocations"] == 0 || error(
            "$name $(spec.label) introduced a warm device allocation")
        observation_delta["host_synchronizations"] == 2 || error(
            "$name $(spec.label) diagnostic observations must use two explicit boundaries")
        if backend isa KernelAbstractions.CPU
            observation_delta["device_to_host_transfers"] == 0 || error(
                "$name $(spec.label) CPU observation introduced a device transfer")
        else
            observation_delta["device_to_host_transfers"] > 0 || error(
                "$name $(spec.label) GPU observation did not record materialized arrays")
        end
        observation_delta["host_to_device_transfers"] == 0 || error(
            "$name $(spec.label) diagnostic observation wrote state to the backend")
        observation_delta["device_allocations"] == 0 || error(
            "$name $(spec.label) diagnostic observation allocated device storage")
        report.mcs == UInt64(integrator.t) || error(
            "$name $(spec.label) report MCS differs from integrator time")
        _validate_reference_mcs_report(name, spec.label, algorithm, report, sites)
        bound_normalized.fingerprint.digest ==
            lowered.normalized.fingerprint.digest || error(
                "$name $(spec.label) lowering changed the semantic fingerprint")
        binding_changed_fingerprint = normalized.fingerprint.digest !=
                                      bound_normalized.fingerprint.digest
        binding_changed_fingerprint == spec.problem_binding_required || error(
            "$name $(spec.label) problem-binding fingerprint contract was violated")
        if profile == "smoke"
            n_cells(snapshot) >= n_cells(problem.u0) || error(
                "$name $(spec.label) lost a finite cell in the timing smoke fixture")
        end
        workloads[spec.label] = Dict(
            "family" => spec.family,
            "scale" => spec.scale,
            "dimensions" => collect(size(lattice_storage(snapshot))),
            "dimension_count" => dimensions,
            "sites" => sites,
            "initial_cells" => n_cells(problem.u0),
            "final_cells" => n_cells(snapshot),
            "algorithm" => string(nameof(typeof(algorithm))),
            "semantic_fingerprint" => normalized.fingerprint.digest,
            "problem_bound_semantic_fingerprint" =>
                bound_normalized.fingerprint.digest,
            "lowered_semantic_fingerprint" => lowered.normalized.fingerprint.digest,
            "problem_binding_required" => spec.problem_binding_required,
            "problem_binding_changed_fingerprint" => binding_changed_fingerprint,
            "model_construction_seconds" => model_timing.time,
            "model_construction_host_bytes" => model_timing.bytes,
            "normalization_seconds" => normalization_timing.time,
            "normalization_host_bytes" => normalization_timing.bytes,
            "problem_binding_seconds" => problem_binding_timing.time,
            "problem_binding_host_bytes" => problem_binding_timing.bytes,
            "problem_bound_normalization_seconds" => bound_normalization_timing.time,
            "problem_bound_normalization_host_bytes" => bound_normalization_timing.bytes,
            "lowering_seconds" => lowering_timing.time,
            "lowering_host_bytes" => lowering_timing.bytes,
            "problem_construction_seconds" => problem_timing.time,
            "problem_construction_host_bytes" => problem_timing.bytes,
            "initialization_seconds" => initialization_timing.time,
            "initialization_host_bytes" => initialization_timing.bytes,
            "first_mcs_seconds" => first_mcs.seconds_per_mcs,
            "first_mcs_host_bytes" => first_mcs.host_allocated_bytes_per_mcs,
            "steady_raw_seconds_per_mcs" => seconds,
            "steady_minimum_seconds_per_mcs" => minimum(seconds),
            "steady_median_seconds_per_mcs" => median_seconds,
            "steady_mean_seconds_per_mcs" => mean(seconds),
            "steady_maximum_seconds_per_mcs" => maximum(seconds),
            "steady_median_mcs_per_second" => inv(median_seconds),
            "steady_raw_host_allocated_bytes_per_mcs" => host_bytes,
            "steady_median_host_allocated_bytes_per_mcs" => median(host_bytes),
            "last_mcs_scheduler_candidates" => Int(report.scheduler_candidates),
            "last_mcs_activated_attempts" => Int(report.activated_attempts),
            "last_mcs_realized_proposals" => Int(report.realized_proposals),
            "last_mcs_accepted_copies" => Int(report.accepted_copies),
            "median_activated_attempts_per_second" =>
                report.activated_attempts / median_seconds,
            "median_realized_proposals_per_second" =>
                report.realized_proposals / median_seconds,
            "median_accepted_copies_per_second" =>
                report.accepted_copies / median_seconds,
            "last_mcs_acceptance_fraction" => report.realized_proposals == 0 ? 0.0 :
                report.accepted_copies / report.realized_proposals,
            "warm_execution_metrics" => warm_delta,
            "explicit_observation_metrics" => observation_delta,
            "residency" => _phase10_residency(integrator.inner),
            "runtime_problem_wrapper" => false,
            "declared_lifecycle_observation_per_mcs" =>
                spec.requires_lifecycle_observation,
            "timed_regions_backend_synchronized" => true,
        )
    end
    return Dict(
        "profile" => profile,
        "samples" => samples,
        "steps_per_sample" => steps,
        "warmup_steps" => warmup_steps,
        "algorithm" => string(nameof(typeof(algorithm))),
        "precision" => string(real_type),
        "workloads" => workloads,
        "incompatible_workloads" => exclusions,
        "required_families" => [
            "single_cell_migration", "prescribed_gradient_chemotaxis",
            "monolayer_growth", "differential_adhesion_sorting",
            "elongation_driven_angiogenesis"],
        "kernel_resource_evidence" => _phase10_kernel_resource_evidence(name),
    )
end

function measure_phase12_reference_backend(name::String; profile::String = "smoke",
        sequential_reference = nothing,
        real_type::Type{<:AbstractFloat} = Float32)
    algorithms = (
        SequentialCPM(temperature = real_type(2)),
        SequentialEquilibrium(temperature = real_type(2)),
        CheckerboardSweepCPM(temperature = real_type(2)),
        LotteryCPM(temperature = real_type(2)),
    )
    measurements = Dict{String, Any}()
    workloads = Dict{String, Any}()
    exclusions = Dict{String, Any}()
    for algorithm in algorithms
        algorithm_name = string(nameof(typeof(algorithm)))
        measurement = algorithm isa SequentialCPM && sequential_reference !== nothing ?
                      sequential_reference : measure_phase10_reference_backend(
            name; profile, algorithm, skip_incompatible = true, real_type)
        isempty(measurement["workloads"]) && error(
            "$name Phase 12 algorithm $algorithm_name has no compatible reference workload")
        measurements[algorithm_name] = measurement
        exclusions[algorithm_name] = measurement["incompatible_workloads"]
        for (label, workload) in measurement["workloads"]
            workloads["$(algorithm_name)__$(label)"] = workload
        end
    end
    reference = first(values(measurements))
    return Dict(
        "profile" => profile,
        "samples" => reference["samples"],
        "steps_per_sample" => reference["steps_per_sample"],
        "warmup_steps" => reference["warmup_steps"],
        "precision" => string(real_type),
        "workloads" => workloads,
        "required_families" => reference["required_families"],
        "required_algorithms" => collect(keys(measurements)),
        "incompatible_workloads" => exclusions,
        "kernel_resource_evidence" => reference["kernel_resource_evidence"],
    )
end

function phase10_result(name::String, profile::String, device::String;
        qualification, direct_comparison, reference_performance, checkpoint_performance)
    return Dict(
        "schema_version" => PHASE10_SCHEMA_VERSION,
        "recorded_at_utc" => string(now(UTC)),
        "provenance" => provenance(name, device),
        "profile" => profile,
        "qualification" => qualification,
        "direct_corepotts_comparison" => direct_comparison,
        "reference_performance" => reference_performance,
        "checkpoint_performance" => checkpoint_performance,
        "measurement_contract" => Dict(
            "public_time_unit" => "MCS",
            "actual_proposal_counters" => true,
            "construction_compilation_and_warm_execution_separated" => true,
            "diagnostic_observations_excluded_from_warm_timing" => true,
            "declared_lifecycle_safety_observations_retained_in_warm_timing" => true,
            "gpu_timing_is_backend_synchronized" => true,
            "state_evolves_across_steady_samples" => true,
        ),
    )
end

function write_phase10_result(result)
    provenance_data = result["provenance"]
    backend = provenance_data["backend"]
    profile = result["profile"]
    timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
    directory = joinpath(RESULTS_ROOT, provenance_data["baseline_id"], backend)
    mkpath(directory)
    path = joinpath(directory, "$(timestamp)-phase10-reference-suite-$(profile).toml")
    open(path, "w") do io
        TOML.print(io, result; sorted = true)
    end
    return path
end

function _phase12_workloads(reference_performance)
    workloads = deepcopy(reference_performance["workloads"])
    timed_mcs = reference_performance["samples"] * reference_performance["steps_per_sample"]
    for workload in values(workloads)
        workload["reusable_semantic_fingerprint"] = workload["semantic_fingerprint"]
        workload["semantic_fingerprint"] = workload["problem_bound_semantic_fingerprint"]
        workload["timed_mcs"] = timed_mcs
    end
    return workloads
end

function _phase12_process_id()
    return get(ENV, "POTTS_BENCHMARK_PROCESS_ID",
        string(Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS.sss"), "-", getpid()))
end

function _phase12_tuning_policy()
    policy = get(ENV, "POTTS_BENCHMARK_TUNING_POLICY", "conservative")
    policy in ("conservative", "tuned") || throw(ArgumentError(
        "POTTS_BENCHMARK_TUNING_POLICY must be conservative or tuned"))
    return policy
end

"""Build one fresh-process Phase 12 performance record from qualified measurements."""
function phase12_result(name::String, profile::String, device::String;
        qualification, direct_comparison, reference_performance, checkpoint_performance)
    provenance_data = provenance(name, device)
    return Dict(
        "schema_version" => Phase12Comparison.PHASE12_SCHEMA_VERSION,
        "record_kind" => "phase12-performance-run",
        "recorded_at_utc" => string(now(UTC)),
        "comparison_identity" => Dict(
            "contract_version" => Phase12Comparison.PHASE12_CONTRACT_VERSION,
            "workload_set_version" => PHASE12_WORKLOAD_SET_VERSION,
            "harness_tree_sha256" => provenance_data["harness_tree_sha256"],
            "backend" => name,
            "hardware_id" => provenance_data["hardware_id"],
            "julia_version" => string(VERSION),
            "architecture" => string(Sys.ARCH),
            "os" => string(Sys.KERNEL),
            "julia_threads" => Threads.nthreads(),
            "precision" => reference_performance["precision"],
            "profile" => profile,
            "tuning_policy" => _phase12_tuning_policy(),
        ),
        "run" => Dict(
            "process_id" => _phase12_process_id(),
            "independence_unit" => "fresh Julia process",
            "samples_per_workload" => reference_performance["samples"],
            "steps_per_sample" => reference_performance["steps_per_sample"],
            "warmup_steps" => reference_performance["warmup_steps"],
        ),
        "provenance" => provenance_data,
        "workloads" => _phase12_workloads(reference_performance),
        "qualification" => qualification,
        "direct_corepotts_comparison" => direct_comparison,
        "checkpoint_performance" => checkpoint_performance,
        "kernel_resource_evidence" => reference_performance["kernel_resource_evidence"],
        "measurement_contract" => Dict(
            "public_time_unit" => "MCS",
            "actual_proposal_counters" => true,
            "fresh_process_record" => true,
            "cold_tiers_require_separate_subprocess_records" => true,
            "first_mcs_field_is_order_dependent_diagnostic" => true,
            "diagnostic_observations_excluded_from_warm_timing" => true,
            "declared_lifecycle_safety_observations_retained_in_warm_timing" => true,
            "gpu_timing_is_backend_synchronized" => true,
            "state_evolves_across_steady_samples" => true,
            "regression_threshold_fraction" => 0.05,
            "memory_threshold_fraction" => 0.05,
        ),
    )
end

function write_phase12_result(result)
    issues = Phase12Comparison.validate_record(result)
    isempty(issues) || error("refusing to write invalid Phase 12 result:\n- " *
                             join(issues, "\n- "))
    provenance_data = result["provenance"]
    backend = result["comparison_identity"]["backend"]
    profile = result["comparison_identity"]["profile"]
    timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
    directory = joinpath(RESULTS_ROOT, provenance_data["subject_id"], backend)
    mkpath(directory)
    path = joinpath(directory,
        "$(timestamp)-phase12-performance-$(profile)-$(result["run"]["process_id"]).toml")
    open(path, "w") do io
        TOML.print(io, result; sorted = true)
    end
    return path
end

function _timed_scientific_steps!(integrator, steps::Int)
    KernelAbstractions.synchronize(integrator.plan.backend)
    elapsed = @elapsed begin
        SciMLBase.step!(integrator, steps)
        KernelAbstractions.synchronize(integrator.plan.backend)
    end
    return elapsed / steps
end

function _timed_phase9_steps!(integrator::PottsIntegrator, steps::Int)
    KernelAbstractions.synchronize(integrator.inner.plan.backend)
    elapsed = @elapsed begin
        SciMLBase.step!(integrator, steps)
        KernelAbstractions.synchronize(integrator.inner.plan.backend)
    end
    return elapsed / steps
end

"""Measure direct-versus-SciML steady execution and construction overhead."""
function measure_phase9_backend(name::String)
    algorithms = (SequentialCPM(temperature = 2.0f0),
        CheckerboardSweepCPM(temperature = 2.0f0), LotteryCPM(temperature = 2.0f0))
    results = Dict{String, Any}()
    for (index, algorithm) in enumerate(algorithms)
        fixture = _phase9_problem(Val(2); tspan = (0, 20),
            seed = UInt64(0x7068617365392000) + UInt64(index))
        direct_construction = @elapsed direct, backend, adaptor =
            _phase9_direct_integrator(name, fixture, algorithm)
        wrapper_construction = @elapsed wrapped = init(fixture.problem, algorithm;
            backend, adaptor, verbose = false, save_start = false, save_end = false)
        _timed_scientific_steps!(direct, 1)
        _timed_phase9_steps!(wrapped, 1)
        direct_seconds = _timed_scientific_steps!(direct, 5)
        wrapper_seconds = _timed_phase9_steps!(wrapped, 5)
        results[string(nameof(typeof(algorithm)))] = Dict(
            "direct_construction_seconds" => direct_construction,
            "wrapper_construction_seconds" => wrapper_construction,
            "direct_steady_mcs_seconds" => direct_seconds,
            "wrapper_steady_mcs_seconds" => wrapper_seconds,
            "wrapper_to_direct_ratio" => wrapper_seconds / direct_seconds,
            "direct_launches" => direct.plan.metrics.launches,
            "wrapper_launches" => wrapped.inner.plan.metrics.launches,
            "wrapper_host_synchronizations" => wrapped.inner.plan.metrics.host_synchronizations,
            "wrapper_device_to_host_transfers" =>
                wrapped.inner.plan.metrics.device_to_host_transfers,
        )
    end
    return Dict(
        "backend" => name,
        "dimension" => 2,
        "steps_per_steady_sample" => 5,
        "algorithms" => results,
        "timed_regions_backend_synchronized" => true,
        "semantic_baseline" => "direct qualified scientific integrator",
        "regression_threshold" => "5% on dedicated paper workloads; smoke results are diagnostic",
    )
end

function _checkpoint_material_bytes(checkpoint::CanonicalCheckpoint)
    payload = checkpoint_storage_payload(checkpoint)
    arrays = (
        payload.dims, payload.ownership_tags, payload.ownership_ids, payload.active,
        payload.generations, payload.cell_types, payload.reusable_slots,
        payload.medium_ids, payload.model_fingerprint, payload.schema_fingerprint,
        payload.topology_fingerprint, payload.initial_state_fingerprint,
        payload.ancestry_fingerprint, payload.state_fingerprint, payload.checksum,
        payload.property_values...,
    )
    return sum(array -> sizeof(eltype(array)) * length(array), arrays)
end

"""Measure the Phase 8 lifecycle and checkpoint boundaries on a qualified backend."""
function measure_phase8_backend(name::String)
    algorithms = (
        SequentialCPM(temperature = 2.0f0),
        CheckerboardSweepCPM(temperature = 2.0f0),
        LotteryCPM(temperature = 2.0f0),
    )
    results = Dict{String, Any}()
    adaptor = _backend_adaptor(name)
    for (index, algorithm) in enumerate(algorithms)
        label = string(nameof(typeof(algorithm)))
        seed = UInt64(0x7068617365387000) + UInt64(index)
        baseline_construction = @elapsed baseline = _phase8_persistence_integrator(
            name, Val(2), algorithm, seed; with_lifecycle = false)
        lifecycle_construction = @elapsed lifecycle = _phase8_persistence_integrator(
            name, Val(2), algorithm, seed; with_lifecycle = true)
        KernelAbstractions.synchronize(baseline.plan.backend)
        KernelAbstractions.synchronize(lifecycle.plan.backend)
        baseline_first = _timed_scientific_steps!(baseline, 1)
        lifecycle_first = _timed_scientific_steps!(lifecycle, 1)
        _timed_scientific_steps!(baseline, 1)
        _timed_scientific_steps!(lifecycle, 1)
        baseline_steady = _timed_scientific_steps!(baseline, 5)
        lifecycle_steady = _timed_scientific_steps!(lifecycle, 5)
        baseline_snapshot = logical_state(baseline)
        lifecycle_snapshot = logical_state(lifecycle)
        lattice_storage(baseline_snapshot) == lattice_storage(lifecycle_snapshot) ||
            error("$name $label lifecycle performance fixture changed the proposal trajectory")

        before_transfers = lifecycle.plan.metrics.device_to_host_transfers
        checkpoint_seconds = @elapsed checkpoint = capture_checkpoint(lifecycle)
        checkpoint_transfers = lifecycle.plan.metrics.device_to_host_transfers - before_transfers
        restore_seconds = @elapsed restored = restore_checkpoint(
            checkpoint, lifecycle; adaptor)
        KernelAbstractions.synchronize(restored.plan.backend)
        results[label] = Dict(
            "construction_seconds_without_lifecycle" => baseline_construction,
            "construction_seconds_with_lifecycle" => lifecycle_construction,
            "first_mcs_seconds_without_lifecycle" => baseline_first,
            "first_mcs_seconds_with_lifecycle" => lifecycle_first,
            "steady_mcs_seconds_without_lifecycle" => baseline_steady,
            "steady_mcs_seconds_with_lifecycle" => lifecycle_steady,
            "steady_lifecycle_ratio" => lifecycle_steady / baseline_steady,
            "lifecycle_workspace_bytes" => compiled_lifecycle_bytes(lifecycle.lifecycle),
            "checkpoint_capture_seconds" => checkpoint_seconds,
            "checkpoint_restore_seconds" => restore_seconds,
            "checkpoint_material_bytes" => _checkpoint_material_bytes(checkpoint),
            "checkpoint_device_to_host_transfers" => checkpoint_transfers,
            "checkpoint_observation_synchronizations" => 1,
        )
    end
    return Dict(
        "backend" => name,
        "dimension" => 2,
        "steps_per_steady_sample" => 5,
        "algorithms" => results,
        "timed_regions_backend_synchronized" => true,
        "semantic_baseline" => "same scientific model without compiled lifecycle",
        "construction_and_first_use_order" =>
            ["without_lifecycle", "with_lifecycle"],
        "first_use_note" =>
            "one-process JIT-cache-sensitive diagnostic; not a cold-start comparison",
        "regression_threshold" => "report-only until paper hardware is frozen",
    )
end

struct WorkloadSpec{N}
    name::String
    dimensions::NTuple{N, Int}
    cells::Int
    radius::Int
    adhesion::Bool
    class::String
end

const WORKLOADS = Dict(
    "volume_2d_small" => WorkloadSpec(
        "volume_2d_small", (64, 64), 16, 4, false, "latency"),
    "adhesion_2d_medium" => WorkloadSpec(
        "adhesion_2d_medium", (128, 128), 64, 4, true, "throughput"),
    "volume_3d_small" => WorkloadSpec(
        "volume_3d_small", (32, 32, 32), 8, 3, false, "three_dimensional"),
    "adhesion_2d_publication" => WorkloadSpec(
        "adhesion_2d_publication", (256, 256), 100, 5, true, "publication")
)

function evenly_spaced_centers(spec::WorkloadSpec{N}) where {N}
    per_axis = ceil(Int, spec.cells^(1 / N))
    coordinates = ntuple(N) do dimension
        lo = spec.radius + 2
        hi = spec.dimensions[dimension] - spec.radius - 1
        unique(round.(Int, range(lo, hi; length = per_axis)))
    end
    return collect(Iterators.take(Iterators.product(coordinates...), spec.cells))
end

function build_workload(spec::WorkloadSpec{N}) where {N}
    grid = zeros(UInt32, spec.dimensions)
    volume = VolumePenalty(Float32[0, 2])
    penalties = if spec.adhesion
        contact = AdhesionPenalty(Float32[0 10; 10 2])
        (volume, contact)
    else
        (volume,)
    end
    trackers = (VolumeTracker(), SurfaceAreaTracker())
    cell_data = build_cell_data(grid, spec.cells, penalties, trackers)

    for (cell_id, center) in enumerate(evenly_spaced_centers(spec))
        spawn_hypersphere!(
            grid, size(grid), Tuple(center), spec.radius, UInt32(cell_id))
        cell_data.cell_types[cell_id] = UInt8(1)
    end

    state = PottsState(grid, cell_data, Int32[spec.cells])
    topology = MooreTopology{N}()
    parameters = PottsParameters(topology, penalties, trackers)
    cache = PottsCache(state, topology)
    CorePotts.sync_cell_data!(state, parameters, cache, spec.cells)
    return LegacyPottsProblem(state, (0, 1_000), parameters)
end

function load_backend(name::String)
    if name == "cpu"
        return (identity, "KernelAbstractions.CPU")
    elseif name == "metal"
        isdefined(Main, :Metal) || error("Metal must be loaded before PottsBenchmarks")
        metal = getfield(Main, :Metal)
        Base.invokelatest(getproperty(metal, :functional)) ||
            error("Metal loaded but is not functional on this host")
        array_type = getproperty(metal, :MtlArray)
        adapt_problem = problem -> Base.invokelatest(Adapt.adapt, array_type, problem)
        device = Base.invokelatest(getproperty(metal, :device))
        return (adapt_problem, string(device))
    elseif name == "cuda"
        isdefined(Main, :CUDA) || error("CUDA must be loaded before PottsBenchmarks")
        cuda = getfield(Main, :CUDA)
        Base.invokelatest(getproperty(cuda, :functional)) ||
            error("CUDA loaded but is not functional on this host")
        array_type = getproperty(cuda, :CuArray)
        adapt_problem = problem -> Base.invokelatest(Adapt.adapt, array_type, problem)
        device = Base.invokelatest(getproperty(cuda, :device))
        return (adapt_problem, string(device))
    elseif name == "amdgpu"
        isdefined(Main, :AMDGPU) || error("AMDGPU must be loaded before PottsBenchmarks")
        amdgpu = getfield(Main, :AMDGPU)
        Base.invokelatest(getproperty(amdgpu, :functional)) ||
            error("AMDGPU loaded but is not functional on this host")
        array_type = getproperty(amdgpu, :ROCArray)
        adapt_problem = problem -> Base.invokelatest(Adapt.adapt, array_type, problem)
        device = Base.invokelatest(getproperty(amdgpu, :device))
        return (adapt_problem, string(device))
    end
    throw(ArgumentError("Unknown backend `$name`; expected cpu, metal, cuda, or amdgpu"))
end

function algorithm_configuration(name::String, dimensions::Int)
    active_fraction, sweeps = dimensions == 3 ? (0.025f0, 40) : (0.1f0, 10)
    common = (; T = 1.0f0, active_fraction, sweeps_per_step = sweeps)
    if name == "sequential"
        return SequentialMetropolis(; common...)
    elseif name == "lottery"
        return ParallelMetropolis(; common...)
    elseif name == "checkerboard"
        return CheckerboardMetropolis(; common...)
    elseif name == "intrinsic"
        return IntrinsicCheckerboardMetropolis(; common...)
    end
    throw(ArgumentError(
        "Unknown algorithm `$name`; expected sequential, lottery, checkerboard, or intrinsic"))
end

function synchronize_state(state)
    KernelAbstractions.synchronize(KernelAbstractions.get_backend(state.grid))
    return nothing
end

function timed_step!(integrator)
    SciMLBase.step!(integrator)
    synchronize_state(integrator.u)
    return nothing
end

function bytes_of(array)
    host = Array(array)
    return reinterpret(UInt8, vec(host))
end

function state_checksum(state)
    bytes = UInt8[]
    append!(bytes, bytes_of(state.grid))
    for property in sort!(collect(propertynames(state.cell_data)); by = string)
        append!(bytes, codeunits(string(property)))
        append!(bytes, bytes_of(getproperty(state.cell_data, property)))
    end
    append!(bytes, bytes_of(state.N_cells))
    append!(bytes, bytes_of(state.free_list))
    append!(bytes, bytes_of(state.free_list_count))
    return bytes2hex(sha256(bytes))
end

function state_invariants(state)
    synchronize_state(state)
    grid = Array(state.grid)
    volumes = Array(state.cell_data.volumes)
    occupied = count(!iszero, grid)
    active_volume = sum(volumes)
    capacity = length(volumes)
    maximum_owner = isempty(grid) ? 0 : maximum(grid)
    return Dict(
        "occupied_sites" => occupied,
        "tracked_volume" => active_volume,
        "volume_matches_occupancy" => active_volume == occupied,
        "owners_within_capacity" => maximum_owner <= capacity,
        "nonnegative_volumes" => all(>=(0), volumes),
        "maximum_owner" => Int(maximum_owner),
        "capacity" => capacity
    )
end

function implementation_files()
    roots = [
        joinpath(REPOSITORY_ROOT, "Project.toml"),
        joinpath(REPOSITORY_ROOT, "src"),
        joinpath(REPOSITORY_ROOT, "ext"),
        joinpath(REPOSITORY_ROOT, "lib"),
        joinpath(REPOSITORY_ROOT, "test"),
        joinpath(REPOSITORY_ROOT, "integration")
    ]
    files = String[]
    for root in roots
        if isfile(root)
            push!(files, root)
        elseif isdir(root)
            for (directory, _, names) in walkdir(root)
                for name in names
                    if endswith(name, ".jl") || name == "Project.toml"
                        push!(files, joinpath(directory, name))
                    end
                end
            end
        end
    end
    return sort!(files)
end

function source_tree_checksum()
    bytes = UInt8[]
    for file in implementation_files()
        append!(bytes, codeunits(relpath(file, REPOSITORY_ROOT)))
        append!(bytes, read(file))
    end
    return bytes2hex(sha256(bytes))
end

function benchmark_harness_files()
    roots = [
        joinpath(HARNESS_ROOT, "benchmark", "performance_worker.jl"),
        joinpath(HARNESS_ROOT, "benchmark", "src"),
    ]
    files = String[]
    for root in roots
        if isfile(root)
            push!(files, root)
        elseif isdir(root)
            for (directory, _, names) in walkdir(root), name in names
                endswith(name, ".jl") && push!(files, joinpath(directory, name))
            end
        end
    end
    return sort!(files)
end

function benchmark_environment_files()
    roots = [joinpath(REPOSITORY_ROOT, "benchmark")]
    files = String[]
    for root in roots
        for (directory, _, names) in walkdir(root), name in names
            name in ("Project.toml", "Manifest.toml") &&
                push!(files, joinpath(directory, name))
        end
    end
    return sort!(files)
end

function file_set_checksum(files, root = REPOSITORY_ROOT)
    bytes = UInt8[]
    for file in files
        append!(bytes, codeunits(relpath(file, root)))
        append!(bytes, read(file))
    end
    return bytes2hex(sha256(bytes))
end

function _cpu_model()
    models = unique(info.model for info in Sys.cpu_info())
    return isempty(models) ? "unknown" : join(models, "; ")
end

function _hardware_id(backend, device, cpu_model)
    explicit = get(ENV, "POTTS_BENCHMARK_HARDWARE_ID", "")
    isempty(explicit) || return explicit
    identity = join((backend, device, string(Sys.KERNEL), string(Sys.ARCH), cpu_model,
        string(Sys.CPU_THREADS)), "\0")
    return "derived-" * first(bytes2hex(sha256(codeunits(identity))), 16)
end

function command_output(command; default = "unknown")
    try
        return strip(read(command, String))
    catch
        return default
    end
end

function provenance(backend::String, device::String)
    commit = command_output(`git -C $REPOSITORY_ROOT rev-parse HEAD`)
    harness_commit = command_output(`git -C $HARNESS_ROOT rev-parse HEAD`)
    implementation_commit = command_output(`git -C $REPOSITORY_ROOT log -1 --format=%H -- Project.toml src ext lib test integration`)
    dirty_status = command_output(`git -C $REPOSITORY_ROOT status --short`; default = "")
    harness_dirty_status = command_output(
        `git -C $HARNESS_ROOT status --short`; default = "")
    source_checksum = source_tree_checksum()
    harness_checksum = file_set_checksum(benchmark_harness_files(), HARNESS_ROOT)
    environment_checksum = file_set_checksum(benchmark_environment_files())
    cpu_model = _cpu_model()
    return Dict(
        "git_commit" => commit,
        "harness_commit" => harness_commit,
        "implementation_commit" => implementation_commit,
        "git_dirty" => !isempty(dirty_status),
        "harness_git_dirty" => !isempty(harness_dirty_status),
        "source_tree_sha256" => source_checksum,
        "implementation_tree_sha256" => source_checksum,
        "harness_tree_sha256" => harness_checksum,
        "benchmark_environment_sha256" => environment_checksum,
        "baseline_id" => string(first(commit, min(12, length(commit))), "-",
            first(source_checksum, 12)),
        "subject_id" => string(first(implementation_commit,
            min(12, length(implementation_commit))), "-", first(source_checksum, 12)),
        "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL),
        "architecture" => string(Sys.ARCH),
        "cpu_model" => cpu_model,
        "cpu_threads" => Sys.CPU_THREADS,
        "julia_threads" => Threads.nthreads(),
        "backend" => backend,
        "device" => device,
        "hardware_id" => _hardware_id(backend, device, cpu_model),
        "power_mode" => get(ENV, "POTTS_BENCHMARK_POWER_MODE", "unreported"),
        "thermal_state" => get(ENV, "POTTS_BENCHMARK_THERMAL_STATE", "unreported"),
        "cpu_affinity_policy" => get(ENV, "POTTS_BENCHMARK_CPU_AFFINITY",
            "unreported"),
        "kernel_intrinsics_source" => "https://github.com/PraneethMerugu/KernelIntrinsics.jl.git",
        "kernel_intrinsics_commit" => "b3a02b6e80f0839082a02f1838af7e10e992062c"
    )
end

function benchmark_case(
        workload_name::String, algorithm_name::String, backend_name::String;
        samples::Int = 10, seconds::Float64 = 30.0, warmup_steps::Int = 2)
    haskey(WORKLOADS, workload_name) ||
        throw(ArgumentError("Unknown workload `$workload_name`"))
    backend_name != "cpu" && algorithm_name == "sequential" &&
        throw(ArgumentError("The current sequential baseline is CPU-only"))

    spec = WORKLOADS[workload_name]
    adapt_problem, device = load_backend(backend_name)

    build_seconds = @elapsed cpu_problem = build_workload(spec)
    initial_checksum = state_checksum(cpu_problem.u0)
    adaptation_seconds = @elapsed problem = adapt_problem(cpu_problem)
    algorithm = algorithm_configuration(algorithm_name, length(spec.dimensions))

    initialization_seconds = @elapsed integrator = SciMLBase.init(
        problem, algorithm; save_everystep = false, save_start = false, save_end = false)
    initial_invariants = state_invariants(integrator.u)
    first_mcs_seconds = @elapsed timed_step!(integrator)

    for _ in 1:warmup_steps
        timed_step!(integrator)
    end

    benchmarkable = BenchmarkTools.@benchmarkable timed_step!($integrator) evals = 1
    trial = BenchmarkTools.run(benchmarkable; samples, seconds)
    times_seconds = Float64.(trial.times) ./ 1.0e9
    final_invariants = state_invariants(integrator.u)
    expected_attempts = prod(spec.dimensions) * Float64(algorithm.active_fraction) *
                        Int(algorithm.sweeps_per_step)

    metrics = Dict(
        "samples" => length(times_seconds),
        "raw_seconds" => times_seconds,
        "minimum_seconds_per_mcs" => minimum(times_seconds),
        "median_seconds_per_mcs" => median(times_seconds),
        "mean_seconds_per_mcs" => mean(times_seconds),
        "maximum_seconds_per_mcs" => maximum(times_seconds),
        "median_mcs_per_second" => inv(median(times_seconds)),
        "expected_attempts_per_public_step" => expected_attempts,
        "median_expected_attempts_per_second" => expected_attempts / median(times_seconds),
        "benchmark_host_memory_bytes" => trial.memory,
        "benchmark_host_allocations" => trial.allocs,
        "workload_build_seconds" => build_seconds,
        "backend_adaptation_seconds" => adaptation_seconds,
        "integrator_initialization_seconds" => initialization_seconds,
        "first_mcs_seconds" => first_mcs_seconds
    )

    return Dict(
        "schema_version" => SCHEMA_VERSION,
        "recorded_at_utc" => string(now(UTC)),
        "provenance" => provenance(backend_name, device),
        "workload" => Dict(
            "name" => spec.name,
            "class" => spec.class,
            "dimensions" => collect(spec.dimensions),
            "sites" => prod(spec.dimensions),
            "initial_cells" => spec.cells,
            "radius" => spec.radius,
            "adhesion" => spec.adhesion,
            "initial_checksum" => initial_checksum
        ),
        "algorithm" => Dict(
            "name" => algorithm_name,
            "type" => string(typeof(algorithm)),
            "temperature" => Float64(algorithm.T),
            "active_fraction" => Float64(algorithm.active_fraction),
            "sweeps_per_step" => Int(algorithm.sweeps_per_step),
            "semantic_warning" => "Legacy public-step accounting; not accepted normalized-MCS semantics"
        ),
        "initial_invariants" => initial_invariants,
        "final_invariants" => final_invariants,
        "final_checksum" => state_checksum(integrator.u),
        "metrics" => metrics,
        "known_limitations" => [
            "Current engine exposes no actual proposal or acceptance counters",
            "Kernel launches, transfers, device allocations, and implicit waits are not yet instrumented",
            "State evolves across steady-state benchmark samples",
            "Current RNG has no public semantic master seed"
        ]
    )
end

function write_result(result)
    provenance_data = result["provenance"]
    workload = result["workload"]["name"]
    algorithm = result["algorithm"]["name"]
    backend = provenance_data["backend"]
    timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
    directory = joinpath(RESULTS_ROOT, provenance_data["baseline_id"], backend)
    mkpath(directory)
    path = joinpath(directory, "$(timestamp)-$(workload)-$(algorithm).toml")
    open(path, "w") do io
        TOML.print(io, result; sorted = true)
    end
    return path
end

function parse_arguments(arguments)
    options = Dict(
        "backend" => "cpu",
        "workload" => "volume_2d_small",
        "algorithm" => "checkerboard",
        "samples" => "10",
        "seconds" => "30",
        "warmup" => "2"
    )
    for argument in arguments
        startswith(argument, "--") ||
            throw(ArgumentError("Expected --key=value, received `$argument`"))
        parts = split(argument[3:end], "="; limit = 2)
        length(parts) == 2 || throw(ArgumentError("Expected --key=value"))
        haskey(options, parts[1]) || throw(ArgumentError("Unknown option --$(parts[1])"))
        options[parts[1]] = parts[2]
    end
    return options
end

function main(arguments)
    try
        options = parse_arguments(arguments)
        result = benchmark_case(
            options["workload"], options["algorithm"], options["backend"];
            samples = parse(Int, options["samples"]),
            seconds = parse(Float64, options["seconds"]),
            warmup_steps = parse(Int, options["warmup"])
        )
        path = write_result(result)
        println("BASELINE_RESULT=", path)
        println("BASELINE_ID=", result["provenance"]["baseline_id"])
        println("MEDIAN_MCS_PER_SECOND=", result["metrics"]["median_mcs_per_second"])
        return 0
    catch error
        showerror(stderr, error, catch_backtrace())
        println(stderr)
        return 1
    end
end

end
