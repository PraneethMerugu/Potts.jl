const PHASE14_SEMANTIC_KERNEL_VERSION = v"0.2.0"

"""
One canonical state declaration. Domain-specific state values lower to this record; they do not
own independent scheduling, persistence, or fingerprint semantics.
"""
struct StateSpec{S, I, L, A}
    id::Symbol
    owner::Symbol
    schema::S
    storage::Symbol
    initialization::I
    lifecycle::L
    persistence::Symbol
    adaptation::A
    version::VersionNumber
end

function StateSpec(id::Symbol; owner::Symbol, schema,
        storage::Symbol = :current, initialization,
        lifecycle, persistence::Symbol = :checkpointed,
        adaptation = (:cpu,), version::VersionNumber = PHASE14_SEMANTIC_KERNEL_VERSION)
    isempty(String(id)) && throw(ArgumentError("state identity must not be empty"))
    owner in (:global, :cell, :site, :field, :membrane, :relationship) ||
        throw(ArgumentError("unsupported semantic state owner `$owner`"))
    storage in (:current, :bounded_history, :delayed_history, :specialized) ||
        throw(ArgumentError("unsupported semantic storage policy `$storage`"))
    return StateSpec(id, owner, schema, storage, initialization,
        lifecycle, persistence, Tuple(adaptation), version)
end

"""
One canonical process declaration. The plan supplies cadence and order; this record supplies the
law, dependencies, snapshot, and commit boundary.
"""
struct ProcessSpec{L, N, R, C}
    id::Symbol
    reads::Tuple
    writes::Tuple
    law::L
    snapshot::Symbol
    commit::Symbol
    numerics::N
    rng::R
    conflicts::C
    lifecycle_requests::Bool
    failure::Symbol
    backends::Tuple
    version::VersionNumber
end

function ProcessSpec(id::Symbol; reads = (), writes = (), law,
        snapshot::Symbol, commit::Symbol, numerics = nothing, rng = (),
        conflicts = :not_applicable, lifecycle_requests::Bool = false,
        failure::Symbol = :terminal, backends = (:cpu,),
        version::VersionNumber = PHASE14_SEMANTIC_KERNEL_VERSION)
    isempty(String(id)) && throw(ArgumentError("process identity must not be empty"))
    snapshot in (:accepted_copy, :phase_entry, :process_entry,
        :completed_process, :completed_mcs) ||
        throw(ArgumentError("unsupported process snapshot `$snapshot`"))
    commit in (:accepted_copy_transaction, :atomic_synchronous,
        :ordered_sequential, :read_only) ||
        throw(ArgumentError("unsupported process commit mode `$commit`"))
    return ProcessSpec(id, Tuple(reads), Tuple(writes), law, snapshot, commit,
        numerics, Tuple(rng), conflicts, lifecycle_requests, failure,
        Tuple(backends), version)
end

"""One ordered entry in the exact global execution plan."""
struct PlanEntrySpec{T, A}
    id::Symbol
    kind::Symbol
    target::T
    cadence::UInt64
    snapshot::Symbol
    commit::Symbol
    activation::A
    priority::Int32
end

function PlanEntrySpec(id::Symbol, kind::Symbol; target = nothing,
        cadence::Integer = 1, snapshot::Symbol = :phase_entry,
        commit::Symbol = :atomic_synchronous, activation = :always,
        priority::Integer = 0)
    cadence > 0 || throw(ArgumentError("plan cadence must be positive"))
    kind in (:potts, :process, :lifecycle, :observation, :stable_boundary) ||
        throw(ArgumentError("unsupported plan-entry kind `$kind`"))
    return PlanEntrySpec(id, kind, target, UInt64(cadence),
        snapshot, commit, activation, Int32(priority))
end

"""The sole exact time/order authority for a coupled model."""
struct PlanSpec{E <: Tuple, T}
    entries::E
    mcs_duration::T
    version::VersionNumber
end

function PlanSpec(entries::Tuple; mcs_duration = 1//1,
        version::VersionNumber = PHASE14_SEMANTIC_KERNEL_VERSION)
    isempty(entries) && throw(ArgumentError("semantic plan must not be empty"))
    all(entry -> entry isa PlanEntrySpec, entries) ||
        throw(ArgumentError("semantic plan entries must be PlanEntrySpec values"))
    count(entry -> entry.kind === :potts, entries) == 1 ||
        throw(ArgumentError("semantic plan requires exactly one Potts entry"))
    count(entry -> entry.kind === :lifecycle, entries) == 1 ||
        throw(ArgumentError("semantic plan requires exactly one lifecycle entry"))
    count(entry -> entry.kind === :stable_boundary, entries) == 1 ||
        throw(ArgumentError("semantic plan requires exactly one stable boundary"))
    last(entries).kind === :stable_boundary ||
        throw(ArgumentError("the stable boundary must be the final plan entry"))
    return PlanSpec(entries, mcs_duration, version)
end

"""Canonical lifecycle transaction policy."""
struct LifecycleSpec{P}
    policy::P
    commit::Symbol
    version::VersionNumber
end
LifecycleSpec(policy = :frozen_phase13_lifecycle;
    commit::Symbol = :after_processes,
    version::VersionNumber = PHASE14_SEMANTIC_KERNEL_VERSION) =
    LifecycleSpec(policy, commit, version)

"""Canonical read-only observation declaration."""
struct ObservationSpec{T, S}
    id::Symbol
    inputs::Tuple
    transform::T
    snapshot::Symbol
    cadence::UInt64
    schema::S
    failure::Symbol
    version::VersionNumber
end

function ObservationSpec(id::Symbol; inputs = (), transform,
        snapshot::Symbol = :completed_mcs, cadence::Integer = 1,
        schema = (name = id, version = v"1.0.0"),
        failure::Symbol = :required,
        version::VersionNumber = PHASE14_SEMANTIC_KERNEL_VERSION)
    cadence > 0 || throw(ArgumentError("observation cadence must be positive"))
    snapshot === :completed_mcs || throw(ArgumentError(
        "the stable Phase 14 slice supports completed-MCS observations"))
    failure in (:required, :best_effort) ||
        throw(ArgumentError("unsupported observation failure policy `$failure`"))
    return ObservationSpec(id, Tuple(inputs), transform, snapshot,
        UInt64(cadence), schema, failure, version)
end

"""
The single immutable Phase 14 semantic authority. Runtime state, checkpoints, preflight, and
inspection are projections of this value.
"""
struct SemanticModel{S <: Tuple, P <: Tuple, E <: PlanSpec, L <: LifecycleSpec,
        O <: Tuple, R <: SpatialRoles, A}
    states::S
    processes::P
    plan::E
    lifecycle::L
    observations::O
    spatial_roles::R
    algorithm::A
    version::VersionNumber
end

function SemanticModel(states::Tuple, processes::Tuple, plan::PlanSpec;
        lifecycle::LifecycleSpec = LifecycleSpec(), observations::Tuple = (),
        spatial_roles::SpatialRoles = SpatialRoles(), algorithm,
        version::VersionNumber = PHASE14_SEMANTIC_KERNEL_VERSION)
    all(state -> state isa StateSpec, states) ||
        throw(ArgumentError("semantic model states must be StateSpec values"))
    all(process -> process isa ProcessSpec, processes) ||
        throw(ArgumentError("semantic model processes must be ProcessSpec values"))
    all(observation -> observation isa ObservationSpec, observations) ||
        throw(ArgumentError(
            "semantic model observations must be ObservationSpec values"))

    state_ids = Tuple(state.id for state in states)
    process_ids = Tuple(process.id for process in processes)
    length(unique(state_ids)) == length(state_ids) ||
        throw(ArgumentError("semantic state identities must be unique"))
    length(unique(process_ids)) == length(process_ids) ||
        throw(ArgumentError("semantic process identities must be unique"))
    for process in processes
        all(reference -> reference in state_ids, (process.reads..., process.writes...)) ||
            throw(ArgumentError(
                "process `$(process.id)` references an undeclared state"))
    end
    for entry in plan.entries
        entry.kind === :process || continue
        entry.target in process_ids || throw(ArgumentError(
            "plan entry `$(entry.id)` references an undeclared process"))
    end
    for observation in observations
        all(reference -> reference in state_ids, observation.inputs) ||
            throw(ArgumentError(
                "observation `$(observation.id)` references an undeclared state"))
    end
    return SemanticModel(states, processes, plan, lifecycle, observations,
        spatial_roles, algorithm, version)
end

canonical_coupled_model(model::SemanticModel) = model

# Lowering hooks used to prove that a runtime realization was derived from the same canonical
# declarations. Retained biological façades specialize these without creating a second IR.
canonical_state_spec(value) = nothing
canonical_process_law(value) = value
canonical_observation_transform(value) = value
