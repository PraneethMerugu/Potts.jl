struct StateIntervention{L<:AbstractUpdateLaw,T}
    id::Symbol
    owner::String
    store::Symbol
    target::Path
    schema::LeafSchema
    time::LogicalTime
    law::L
    payload::T
end

function StateIntervention(
    id::Union{Symbol,AbstractString},
    time::LogicalTime,
    store::StoreHandle,
    law::L,
    payload::T,
) where {L<:AbstractUpdateLaw,T}
    owner = getfield(store, :owner)
    owner isa AbstractString ||
        _fail(:unfinished_intervention_handle,
            "state interventions require a handle from a completed model")
    schema = getfield(store, :schema)
    schema isa LeafSchema ||
        _fail(:intervention_targets_branch,
            "state interventions must target a leaf store";
            store=getfield(store, :name))
    schema.update_law == law_identity(law) ||
        _fail(:intervention_update_law_mismatch,
            "state intervention law must match the store publication law";
            store=getfield(store, :name),
            expected=schema.update_law,
            actual=law_identity(law))
    law isa ReplaceUpdate && validate_value(schema, payload)
    canonical_bytes(payload)
    identity = Symbol(id)
    isempty(String(identity)) &&
        _fail(:empty_intervention_identity,
            "state intervention identity cannot be empty")
    StateIntervention(
        identity,
        String(owner),
        getfield(store, :name),
        getfield(store, :target),
        deepcopy(schema),
        time,
        law,
        deepcopy(payload))
end

function _canonical(io::IO, intervention::StateIntervention)
    write(io, "SI")
    _canonical(io, intervention.id)
    _canonical(io, intervention.owner)
    _canonical(io, intervention.store)
    _canonical(io, intervention.target)
    _canonical(io, intervention.schema)
    _canonical(io, intervention.time)
    _canonical(io, law_identity(intervention.law))
    _canonical(io, intervention.payload)
end

struct _StateInterventionProcess{L<:AbstractUpdateLaw,T} <: AbstractProcess
    id::Symbol
    value_type::Any
    law::L
    payload::T
end

ports(process::_StateInterventionProcess) = (
    OutputPort(
        process.value_type,
        :effect;
        update_law=law_identity(process.law)),
)

semantic_version(::_StateInterventionProcess) = "1.0.0"
semantic_parameters(process::_StateInterventionProcess) = (
    id=process.id,
    update_law=law_identity(process.law),
    payload_fingerprint=canonical_fingerprint(process.payload),
)

function invoke(
    process::_StateInterventionProcess,
    inputs,
    context,
)
    InvocationResult((
        emit(context, :effect, process.law, deepcopy(process.payload)),
    ))
end

struct SimulationProblem
    model::CompositeModel
    initial::Tuple
    parameters::Tuple
    observations::Tuple
    interventions::Tuple
    tspan::Union{Nothing,Tuple}
    seed::NormalizedRootSeed
    fingerprint::String
end

function Base.show(io::IO, problem::SimulationProblem)
    print(io, "SimulationProblem(:", problem.model.name,
        "; initial=", length(problem.initial),
        ", parameters=", length(problem.parameters),
        ", observations=", length(problem.observations),
        ", tspan=", problem.tspan,
        ", fingerprint=\"", first(problem.fingerprint, 12), "…\")")
end

function _semantic_bindings(
    values,
    kind::Symbol;
    model::Union{Nothing,CompositeModel}=nothing,
)
    pairs_value = values isa NamedTuple ? collect(pairs(values)) :
        values isa AbstractDict ? collect(values) :
        values isa Tuple || values isa AbstractVector ? collect(values) :
        _fail(:invalid_problem_binding,
            "problem bindings must be a NamedTuple, dictionary, or pairs";
            kind)
    normalized = Pair{Symbol,Any}[]
    for entry in pairs_value
        normalized_entry =
            kind === :observation && entry isa ObservableHandle ?
            entry => true : entry
        normalized_entry isa Pair ||
            _fail(:invalid_problem_binding,
                "every problem binding must be a pair"; kind)
        key = first(normalized_entry)
        if key isa AbstractAuthoringHandle && !isnothing(model)
            owner = getfield(key, :owner)
            owner == model.fingerprint ||
                _fail(:foreign_problem_handle,
                    "problem bindings must use a handle from the bound model";
                    kind, name=getfield(key, :name))
        end
        name = key isa AbstractAuthoringHandle ?
            getfield(key, :name) : Symbol(key)
        push!(normalized, name => deepcopy(last(normalized_entry)))
    end
    names = first.(normalized)
    length(names) == length(unique(names)) ||
        _fail(:duplicate_problem_binding,
            "problem binding repeats one semantic name"; kind)
    tuple(sort!(normalized; by=first)...)
end

function SimulationProblem(
    model::CompositeModel;
    initial=(),
    parameters=(),
    observations=(),
    interventions=(),
    tspan=nothing,
    seed=0,
)
    initial_values = _semantic_bindings(initial, :initial; model)
    parameter_values = _semantic_bindings(parameters, :parameter; model)
    observation_values = _semantic_bindings(observations, :observation; model)
    intervention_values = tuple(interventions...)
    declared_stores = Dict(store.name => store for store in model.stores)
    declared_parameters = Dict(parameter.name => parameter
        for parameter in getfield(model, :parameters))
    declared_observables = Set(observable.name
        for observable in getfield(model, :observables))
    for (name, value) in initial_values
        haskey(declared_stores, name) ||
            _fail(:unknown_problem_store,
                "problem initial condition names an unknown store"; name)
        validate_value(declared_stores[name].schema, value)
    end
    for (name, value) in parameter_values
        haskey(declared_parameters, name) ||
            _fail(:unknown_problem_parameter,
                "problem binding names an unknown parameter"; name)
        value isa typeof(declared_parameters[name].default) ||
            _fail(:problem_parameter_type_mismatch,
                "problem parameter must preserve its declared concrete type";
                name, expected=string(typeof(declared_parameters[name].default)),
                actual=string(typeof(value)))
    end
    for (name, _) in observation_values
        name in declared_observables ||
            _fail(:unknown_problem_observable,
                "problem requests an unknown observable"; name)
    end
    intervention_ids = Symbol[]
    for intervention in intervention_values
        intervention isa StateIntervention ||
            _fail(:unsupported_problem_intervention,
                "problem interventions must use a typed admitted intervention";
                actual=string(typeof(intervention)))
        intervention.owner == model.fingerprint ||
            _fail(:foreign_intervention_handle,
                "state intervention belongs to another semantic model";
                intervention=intervention.id)
        haskey(declared_stores, intervention.store) &&
            declared_stores[intervention.store].target ==
                intervention.target ||
            _fail(:unknown_intervention_store,
                "state intervention targets an unknown model store";
                intervention=intervention.id,
                store=intervention.store)
        canonical_fingerprint(
            declared_stores[intervention.store].schema) ==
                canonical_fingerprint(intervention.schema) ||
            _fail(:stale_intervention_schema,
                "state intervention store schema changed";
                intervention=intervention.id)
        intervention.time.scale == model.scale ||
            _fail(:time_scale_mismatch,
                "state intervention must use the model time scale";
                intervention=intervention.id)
        intervention.time.tick > 0 ||
            _fail(:nonpositive_intervention_time,
                "state interventions occur after the initial boundary";
                intervention=intervention.id)
        push!(intervention_ids, intervention.id)
    end
    length(intervention_ids) == length(unique(intervention_ids)) ||
        _fail(:duplicate_intervention_identity,
            "problem intervention identities must be unique")
    if !isnothing(tspan)
        tspan isa Tuple && length(tspan) == 2 &&
            all(time -> time isa LogicalTime, tspan) ||
            _fail(:invalid_problem_tspan,
                "problem tspan must contain two LogicalTime boundaries")
        first(tspan).scale == model.scale &&
            last(tspan).scale == model.scale ||
            _fail(:time_scale_mismatch,
                "problem tspan must use the model time scale")
        first(tspan).tick <= last(tspan).tick ||
            _fail(:invalid_problem_tspan,
                "problem tspan cannot run backward")
        for intervention in intervention_values
            first(tspan).tick <= intervention.time.tick <=
                    last(tspan).tick ||
                _fail(:intervention_outside_tspan,
                    "state intervention lies outside the problem time span";
                    intervention=intervention.id,
                    time=intervention.time.tick)
        end
    end
    normalized_seed = seed isa NormalizedRootSeed ?
        seed : NormalizedRootSeed(seed)
    fingerprint = canonical_fingerprint((
        :simulation_problem_v1,
        model.fingerprint,
        initial_values,
        parameter_values,
        observation_values,
        intervention_values,
        tspan,
        normalized_seed,
    ))
    SimulationProblem(model, initial_values, parameter_values,
        observation_values, intervention_values, tspan,
        normalized_seed, fingerprint)
end

problem_fingerprint(problem::SimulationProblem) = problem.fingerprint

function remake(
    problem::SimulationProblem;
    model::CompositeModel=problem.model,
    initial=problem.initial,
    parameters=problem.parameters,
    observations=problem.observations,
    interventions=problem.interventions,
    tspan=problem.tspan,
    seed=problem.seed,
)
    SimulationProblem(model;
        initial, parameters, observations, interventions, tspan, seed)
end

function remake(
    model::CompositeModel;
    initial=(),
)
    values = _semantic_bindings(initial, :initial; model)
    overrides = Dict(values)
    stores = tuple((
        haskey(overrides, store.name) ?
            SemanticStore(store.name, store.target, store.schema, true,
                overrides[store.name]) : store
        for store in model.stores
    )...)
    fingerprint = _composite_identity(
        model.name, model.scale, stores, model.actors, model.bindings,
        model.iterations, model.endpoints, getfield(model, :parameters),
        getfield(model, :observables), model.templates, model.mounts,
        model.mounted_bindings, model.profile)
    CompositeModel(
        model.contract_version, model.name, model.scale, stores,
        model.actors, model.bindings, model.iterations, model.endpoints,
        getfield(model, :parameters), getfield(model, :observables),
        model.templates, model.mounts,
        model.mounted_bindings, model.profile, fingerprint)
end

function _rename_model(model::CompositeModel, name::Symbol)
    fingerprint = _composite_identity(
        name, model.scale, model.stores, model.actors, model.bindings,
        model.iterations, model.endpoints, getfield(model, :parameters),
        getfield(model, :observables), model.templates, model.mounts,
        model.mounted_bindings, model.profile)
    CompositeModel(
        model.contract_version, name, model.scale, model.stores,
        model.actors, model.bindings, model.iterations, model.endpoints,
        getfield(model, :parameters), getfield(model, :observables),
        model.templates, model.mounts, model.mounted_bindings,
        model.profile, fingerprint)
end

function _bind_interventions(
    model::CompositeModel,
    interventions::Tuple,
)
    isempty(interventions) && return model
    actors = SemanticActor[model.actors...]
    bindings = SemanticBinding[model.bindings...]
    existing = Set{Symbol}(actor.name for actor in actors)
    for intervention in interventions
        actor_name = Symbol("__intervention__.", intervention.id)
        actor_name in existing &&
            _fail(:intervention_component_collision,
                "intervention identity collides with a model component";
                intervention=intervention.id)
        push!(existing, actor_name)
        leaf_type = _leaf_type(intervention.schema)
        process = _StateInterventionProcess(
            intervention.id,
            leaf_type,
            intervention.law,
            deepcopy(intervention.payload))
        push!(actors, SemanticActor(
            actor_name,
            process,
            :process,
            At(intervention.time),
            (),
            :cpu,
            nothing,
            "1"))
        push!(bindings, SemanticBinding(
            actor_name,
            :effect,
            intervention.target,
            nothing))
    end
    ordered_actors = tuple(sort!(actors; by=actor -> actor.name)...)
    ordered_bindings = tuple(sort!(bindings;
        by=binding ->
            (binding.component, binding.port, binding.target))...)
    fingerprint = _composite_identity(
        model.name,
        model.scale,
        model.stores,
        ordered_actors,
        ordered_bindings,
        model.iterations,
        model.endpoints,
        getfield(model, :parameters),
        getfield(model, :observables),
        model.templates,
        model.mounts,
        model.mounted_bindings,
        model.profile)
    CompositeModel(
        model.contract_version,
        model.name,
        model.scale,
        model.stores,
        ordered_actors,
        ordered_bindings,
        model.iterations,
        model.endpoints,
        getfield(model, :parameters),
        getfield(model, :observables),
        model.templates,
        model.mounts,
        model.mounted_bindings,
        model.profile,
        fingerprint)
end

function compile(
    problem::SimulationProblem;
    backend::Symbol=:serial,
)
    model = isempty(problem.initial) ? problem.model :
        remake(problem.model; initial=problem.initial)
    declared = Dict(parameter.name => deepcopy(parameter.default)
        for parameter in getfield(model, :parameters))
    for (name, value) in problem.parameters
        declared[name] = deepcopy(value)
    end
    actors = tuple((
        begin
            names = tuple(Symbol.(parameter_names(actor.law))...)
            values = (; (name => declared[name] for name in names)...)
            law = with_parameters(actor.law, values)
            law isa typeof(actor.law) ||
                _fail(:parameterized_component_type_change,
                    "with_parameters must preserve the concrete component type";
                    component=actor.name,
                    expected=string(typeof(actor.law)),
                    actual=string(typeof(law)))
            SemanticActor(
                actor.name, law, actor.kind, actor.schedule,
                actor.dependencies, actor.domain, actor.continuation,
                actor.continuation_version)
        end
        for actor in model.actors
    )...)
    if actors != model.actors
        fingerprint = _composite_identity(
            model.name, model.scale, model.stores, actors, model.bindings,
            model.iterations, model.endpoints,
            getfield(model, :parameters), getfield(model, :observables),
            model.templates, model.mounts, model.mounted_bindings,
            model.profile)
        model = CompositeModel(
            model.contract_version, model.name, model.scale, model.stores,
            actors, model.bindings, model.iterations, model.endpoints,
            getfield(model, :parameters), getfield(model, :observables),
            model.templates, model.mounts, model.mounted_bindings,
            model.profile, fingerprint)
    end
    compile(_bind_interventions(model, problem.interventions); backend)
end

function initialize_runtime(
    problem::SimulationProblem,
    executor=nothing,
)
    policy = isnothing(executor) ?
        SerialExecutor(
            qualification=:legacy_compatibility,
            root_seed=problem.seed) : executor
    policy.root_seed == problem.seed ||
        _fail(:problem_seed_mismatch,
            "a supplied executor must use the problem's master seed";
            expected=problem.seed.words, actual=policy.root_seed.words)
    initialize_runtime(compile(problem), policy)
end
