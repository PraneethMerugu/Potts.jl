module ProductionTransitionSampler

using CorePotts
using KernelAbstractions
using ..TransitionKernelOracle
using ..CheckerboardOracle
using ..TransitionFixtures
using ..TransitionEmpirical

export ProductionRowSample, algorithm_symbol, oracle_probability_row,
       sample_production_row, evaluate_production_sample

struct ProductionRowSample
    fixture_id::String
    source_encoding::String
    algorithm::Symbol
    backend::String
    replicas::Int
    first_seed::UInt64
    last_seed::UInt64
    source_id::Int
    counts::Vector{Int}
    launches::Int
    observation_synchronizations::Int
end

function algorithm_symbol(value)
    value isa Symbol && value in (:sequential, :checkerboard) && return value
    text = lowercase(String(value))
    text in ("sequential", "sequentialcpm") && return :sequential
    text in ("checkerboard", "checkerboardsweepcpm") && return :checkerboard
    throw(ArgumentError("unknown transition-kernel production algorithm: $value"))
end

_algorithm(::Val{:sequential}, temperature) = SequentialCPM(temperature = temperature)
_algorithm(::Val{:checkerboard}, temperature) =
    CheckerboardSweepCPM(temperature = temperature)

function _backend_name(backend)
    backend isa KernelAbstractions.CPU && return "cpu"
    name = lowercase(string(typeof(backend)))
    occursin("metal", name) && return "metal"
    occursin("roc", name) && return "rocm"
    return name
end

function _copy_mutable_state!(destination, source)
    for (target, pristine) in zip(CorePotts._storage_arrays(destination.potts.storage),
            CorePotts._storage_arrays(source.potts.storage))
        copyto!(target, pristine)
    end
    for (target, pristine) in zip(CorePotts._tracker_arrays(destination.trackers),
            CorePotts._tracker_arrays(source.trackers))
        copyto!(target, pristine)
    end
    return destination
end

function _oracle_owner(tag, id)
    owner = OwnerRef(tag, id)
    return is_cell_owner(owner) ? oracle_cell(Int(value(cell_id(owner)))) :
           oracle_medium(Int(value(medium_id(owner))))
end

function _observed_state(integrator)
    synchronize_observation!(integrator.plan)
    storage = integrator.state.potts.storage.ownership
    if !(integrator.plan.backend isa KernelAbstractions.CPU)
        record_transfer!(integrator.plan, :device_to_host)
        record_transfer!(integrator.plan, :device_to_host)
    end
    tags = Array(storage.tags)
    ids = Array(storage.ids)
    return OracleMicrostate(Tuple(_oracle_owner(tags[index], ids[index])
        for index in eachindex(ids)))
end

function _prepared_integrator(fixture::TransitionFixture, algorithm::Symbol, backend;
        block_size::Integer)
    fixture.production_supported || throw(ArgumentError(
        "fixture $(fixture.id) is outside the production relation domain: " *
        String(fixture.production_limitation)))
    adaptor = execution_adaptor(backend)
    pristine = CorePotts.Adapt.adapt(adaptor, deepcopy(fixture.scientific_state))
    state = CorePotts.Adapt.adapt(adaptor, deepcopy(fixture.scientific_state))
    components = CorePotts.Adapt.adapt(adaptor, ScientificComponentSet(
        energies = (fixture.volume_component, fixture.contact_component)))
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size, metrics)
    algorithm_value = _algorithm(Val(algorithm), fixture.production_temperature)
    integrator = init_scientific(state, fixture.proposal_relation, components,
        algorithm_value; seed = 0, plan)
    return (; integrator, pristine)
end

function sample_production_row(fixture::TransitionFixture, algorithm_value;
        replicas::Integer,
        seed_base::Integer = UInt64(0x1300000000000000),
        backend = KernelAbstractions.CPU(), block_size::Integer = 128)
    replicas > 0 || throw(ArgumentError("replicas must be positive"))
    algorithm = algorithm_symbol(algorithm_value)
    seed_base >= 0 || throw(ArgumentError("seed_base must be nonnegative"))
    last_seed_wide = UInt128(seed_base) + UInt128(replicas - 1)
    last_seed_wide <= typemax(UInt64) || throw(OverflowError("replica seed range"))
    first_seed = UInt64(seed_base)
    last_seed = UInt64(last_seed_wide)
    prepared = _prepared_integrator(fixture, algorithm, backend; block_size)
    integrator = prepared.integrator
    counts = zeros(Int, length(fixture.oracle_catalog.states))

    for replica in 1:Int(replicas)
        _copy_mutable_state!(integrator.state, prepared.pristine)
        integrator.seed = first_seed + UInt64(replica - 1)
        integrator.mcs = UInt64(0)
        CorePotts.SciMLBase.step!(integrator)
        observed = _observed_state(integrator)
        counts[state_id(fixture.oracle_catalog, observed)] += 1
    end

    metrics = integrator.plan.metrics
    return ProductionRowSample(fixture.id, fixture.source_encoding, algorithm,
        _backend_name(backend), Int(replicas), first_seed, last_seed,
        state_id(fixture.oracle_catalog, fixture.oracle_state), counts,
        metrics.launches, metrics.host_synchronizations)
end

function oracle_probability_row(fixture::TransitionFixture, algorithm_value)
    kernel = oracle_kernel(fixture, algorithm_symbol(algorithm_value))
    return vec(Float64.(Array(transition_row(kernel, fixture.oracle_state))))
end

function evaluate_production_sample(fixture::TransitionFixture,
        sample::ProductionRowSample; plan::TransitionSamplingPlan =
            TransitionSamplingPlan(replicas = sample.replicas))
    plan.replicas == sample.replicas || throw(ArgumentError(
        "sampling plan replica count differs from the production sample"))
    oracle = oracle_probability_row(fixture, sample.algorithm)
    return evaluate_empirical_row(oracle, sample.counts, sample.source_id; plan)
end

end
