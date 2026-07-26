abstract type AbstractContinuousDomain end
struct GlobalDomain <: AbstractContinuousDomain end
struct CellDomain{S} <: AbstractContinuousDomain
    scope::S
end
struct FieldDomain{F} <: AbstractContinuousDomain
    field::F
end
struct MembraneDomain{S, D} <: AbstractContinuousDomain
    scope::S
    discretization::D
end

struct GlobalProperty{T, V}
    name::Symbol
    initial::T
    invariant::V
    version::VersionNumber
end
GlobalProperty(name::Symbol; initial, invariant = NoSiteInvariant(),
    version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION) =
    GlobalProperty(name, initial, invariant, version)
component_identity(property::GlobalProperty) =
    ComponentIdentity(property.name, property.version, :global_property)
component_semantic_data(property::GlobalProperty) = (
    initial = property.initial, invariant = property.invariant)

mutable struct GlobalPropertyState{D <: GlobalProperty, T, M}
    declaration::D
    value::T
    semantic_time::M
end
function initialize_global_property(property::GlobalProperty;
        semantic_time = UInt64(0))
    site_value_valid(property.invariant, property.initial) || throw(
        SiteInvariantError(property.name, 0, property.initial))
    return GlobalPropertyState(
        property, property.initial, semantic_time)
end
function set_global_property!(state::GlobalPropertyState, value;
        semantic_time = state.semantic_time)
    converted = convert(typeof(state.value), value)
    site_value_valid(state.declaration.invariant, converted) || throw(
        SiteInvariantError(state.declaration.name, 0, converted))
    state.value = converted
    state.semantic_time = semantic_time
    return state
end
global_property_value(state::GlobalPropertyState) = state.value

struct AngularMembrane
    points::UInt32
    function AngularMembrane(points::Integer)
        points >= 3 || throw(ArgumentError(
            "angular membrane discretization requires at least three points"))
        return new(UInt32(points))
    end
end
struct FillMembrane{T}
    value::T
end
struct ConservativeMembraneRemap end
struct PartitionMembraneByGeometry end
struct PreserveMembrane end
struct ResetMembrane end

struct MembraneProperty{T, S, D, R, V, X, E, I}
    name::Symbol
    scope::S
    initial::T
    discretization::D
    remapping::R
    division::V
    transition::X
    retirement::E
    invariant::I
    version::VersionNumber
end
function MembraneProperty(name::Symbol, scope; initial, discretization,
        remapping = ConservativeMembraneRemap(),
        remap = nothing,
        division = PartitionMembraneByGeometry(),
        transition = PreserveMembrane(),
        retirement = ResetMembrane(),
        invariant = NoSiteInvariant(),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    resolved_remapping = remap === nothing ? remapping : remap
    discretization isa AngularMembrane || throw(ArgumentError(
        "stable membrane reference requires AngularMembrane"))
    initial isa FillMembrane || throw(ArgumentError(
        "stable membrane reference requires FillMembrane"))
    return MembraneProperty(name, scope, initial, discretization,
        resolved_remapping, division, transition, retirement,
        invariant, version)
end
component_identity(property::MembraneProperty) =
    ComponentIdentity(property.name, property.version, :membrane_property)
component_semantic_data(property::MembraneProperty) = (
    scope = property.scope, initial = property.initial,
    discretization = property.discretization, remapping = property.remapping,
    division = property.division, transition = property.transition,
    retirement = property.retirement, invariant = property.invariant)

mutable struct MembranePropertyState{D <: MembraneProperty, T, M}
    declaration::D
    values::Matrix{T}
    generations::Vector{CellGeneration}
    active::BitVector
    semantic_time::M
end
function initialize_membrane_property(property::MembraneProperty,
        generations::AbstractVector{CellGeneration};
        active = trues(length(generations)), semantic_time = UInt64(0))
    length(active) == length(generations) || throw(DimensionMismatch(
        "membrane active mask must match cell capacity"))
    initial = property.initial.value
    site_value_valid(property.invariant, initial) || throw(
        SiteInvariantError(property.name, 0, initial))
    values = fill(initial, length(generations),
        Int(property.discretization.points))
    return MembranePropertyState(
        property, values, collect(generations),
        BitVector(active), semantic_time)
end

function membrane_values(state::MembranePropertyState,
        cell::CellID, generation_value::CellGeneration)
    slot = Int(value(cell))
    1 <= slot <= size(state.values, 1) || throw(BoundsError(
        state.values, slot))
    state.active[slot] || throw(ArgumentError(
        "membrane state requested for inactive cell"))
    state.generations[slot] == generation_value || throw(ArgumentError(
        "stale membrane cell generation"))
    return @view state.values[slot, :]
end

function set_membrane_values!(state::MembranePropertyState,
        cell::CellID, generation_value::CellGeneration, values)
    destination = membrane_values(state, cell, generation_value)
    length(values) == length(destination) || throw(DimensionMismatch(
        "membrane update must match declared angular resolution"))
    all(value -> site_value_valid(
        state.declaration.invariant, value), values) || throw(
        SiteInvariantError(
            state.declaration.name, Int(value(cell)), values))
    copyto!(destination, values)
    return state
end

function _publish_state!(destination::GlobalPropertyState,
        source::GlobalPropertyState)
    destination.value = source.value
    destination.semantic_time = source.semantic_time
    return destination
end
function _publish_state!(destination::MembranePropertyState,
        source::MembranePropertyState)
    copyto!(destination.values, source.values)
    copyto!(destination.generations, source.generations)
    copyto!(destination.active, source.active)
    destination.semantic_time = source.semantic_time
    return destination
end

struct StateVariable
    name::Symbol
    property::Symbol
end
StateVariable(name::Symbol; property::Symbol = name) =
    StateVariable(name, property)
struct InputVariable
    name::Symbol
end
struct Constant
    name::Symbol
end
struct IntermediateVariable
    name::Symbol
end
struct ObservableVariable
    name::Symbol
end
struct TimeVariable
    name::Symbol
    kind::Symbol
end

"""Function with an explicit semantic identity; the callable address is never fingerprint data."""
struct DirectLaw{F}
    name::Symbol
    version::VersionNumber
    function_value::F
end
DirectLaw(name::Symbol, function_value;
    version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION) =
    DirectLaw(name, version, function_value)
(law::DirectLaw)(args...) = law.function_value(args...)

_durable_continuous_law(value) =
    !(value isa Function) ||
    throw(ArgumentError(
        "stable continuous laws must use DirectLaw with explicit identity"))

abstract type AbstractContinuousStatement end
struct DifferentialEquation{R} <: AbstractContinuousStatement
    target::Symbol
    rhs::R
end
struct SynchronousRule{E} <: AbstractContinuousStatement
    target::Symbol
    expression::E
end
struct AlgebraicAssignment{E, R <: Tuple} <: AbstractContinuousStatement
    target::Symbol
    expression::E
    reads::R
end
AlgebraicAssignment(target::Symbol, expression; reads::Tuple = ()) =
    AlgebraicAssignment(target, expression, reads)
struct FunctionDefinition{E, A <: Tuple} <: AbstractContinuousStatement
    name::Symbol
    arguments::A
    expression::E
end
struct AlgebraicConstraint{R} <: AbstractContinuousStatement
    residual::R
end
struct StochasticDifferentialEquation{R, N} <: AbstractContinuousStatement
    target::Symbol
    drift::R
    noise::N
    interpretation::Symbol
end

abstract type AbstractReactionInterpretation end
struct DeterministicReaction <: AbstractReactionInterpretation end
struct DiscreteJumpProcess <: AbstractReactionInterpretation end
struct HybridReaction <: AbstractReactionInterpretation end
struct ReactionStatement{R, P, L, I <: AbstractReactionInterpretation} <:
        AbstractContinuousStatement
    reactants::R
    products::P
    law::L
    interpretation::I
end

abstract type AbstractFixedStepper end
struct ExplicitEuler <: AbstractFixedStepper end
struct Heun <: AbstractFixedStepper end
struct RK4 <: AbstractFixedStepper end
struct SystemStep{T <: AbstractFloat}
    value::T
    function SystemStep(value::T) where {T <: AbstractFloat}
        isfinite(value) && value > zero(T) || throw(ArgumentError(
            "system step must be finite and positive"))
        return new{T}(value)
    end
end

struct FixedStep{M <: AbstractFixedStepper, S}
    method::M
    step::S
    substeps::UInt32
end
function FixedStep(method::AbstractFixedStepper; step = nothing,
        substeps::Union{Nothing, Integer} = nothing)
    (step === nothing) ⊻ (substeps === nothing) || throw(ArgumentError(
        "FixedStep requires exactly one of step or substeps"))
    step === nothing || step isa SystemStep || throw(ArgumentError(
        "FixedStep step must be SystemStep"))
    count = substeps === nothing ? UInt32(0) : begin
        0 < substeps <= typemax(UInt32) || throw(ArgumentError(
            "FixedStep substeps must be positive and fit UInt32"))
        UInt32(substeps)
    end
    return FixedStep(method, step, count)
end

struct AdaptiveStep{M, T}
    method::M
    abstol::T
    reltol::T
end
function AdaptiveStep(method; abstol::T, reltol::T) where {T <: AbstractFloat}
    abstol > zero(T) && reltol >= zero(T) || throw(ArgumentError(
        "adaptive tolerances require abstol > 0 and reltol >= 0"))
    return AdaptiveStep(method, abstol, reltol)
end

struct SystemClock{T <: AbstractFloat}
    name::Symbol
    scale::T
    unit::Symbol
end
function SystemClock(name::Symbol; scale::T, unit::Symbol = :dimensionless) where {
        T <: AbstractFloat}
    isfinite(scale) && scale > zero(T) || throw(ArgumentError(
        "system-clock scale must be finite and positive"))
    return SystemClock(name, scale, unit)
end

"""General hand-authored continuous-system declaration shared by every owner domain."""
struct ContinuousSystem{D <: AbstractContinuousDomain, S <: Tuple, P, I,
        T <: Tuple, E <: Tuple, V, C}
    name::Symbol
    domain::D
    state::S
    parameters::P
    inputs::I
    statements::T
    events::E
    solver::V
    clock::C
    version::VersionNumber
end
function ContinuousSystem(name::Symbol; domain::AbstractContinuousDomain,
        state::Tuple, parameters = NamedTuple(), inputs = NamedTuple(),
        statements::Tuple, events::Tuple = (),
        solver, clock,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    isempty(state) && throw(ArgumentError(
        "ContinuousSystem requires at least one StateVariable"))
    all(value -> value isa StateVariable, state) || throw(ArgumentError(
        "ContinuousSystem state entries must be StateVariable values"))
    all(value -> value isa AbstractContinuousStatement, statements) ||
        throw(ArgumentError(
            "ContinuousSystem statements must use registered statement families"))
    for statement in statements
        for field in (:rhs, :expression, :residual, :drift, :noise, :law)
            hasproperty(statement, field) || continue
            _durable_continuous_law(getproperty(statement, field))
        end
    end
    names = Tuple(value.name for value in state)
    length(unique(names)) == length(names) || throw(ArgumentError(
        "ContinuousSystem state identities must be unique"))
    targets = Tuple(statement.target for statement in statements
        if hasproperty(statement, :target))
    all(target -> target in names ||
        any(value -> value.name === target, state), targets) ||
        throw(ArgumentError("continuous statement targets undeclared state"))
    _validate_assignment_graph(statements)
    solver isa Union{FixedStep, AdaptiveStep} || throw(ArgumentError(
        "ContinuousSystem solver must be FixedStep or AdaptiveStep"))
    return ContinuousSystem(name, domain, state, parameters, inputs,
        statements, events, solver, clock, version)
end

struct ContinuousProfileRow
    construct::Symbol
    status::Symbol
    diagnostic::String
end
struct ContinuousProfileReport
    system::Symbol
    rows::Tuple
    executable::Bool
end
struct UnsupportedContinuousProfile <: Exception
    system::Symbol
    rows::Tuple
end
function Base.showerror(io::IO, error::UnsupportedContinuousProfile)
    constructs = join((String(row.construct) for row in error.rows), ", ")
    print(io, "continuous system `", error.system,
        "` contains Experimental constructs without a qualified reference execution profile: ",
        constructs)
end

_statement_profile(::DifferentialEquation) = ContinuousProfileRow(
    :differential_equation, :stable, "fixed-step CPU reference")
_statement_profile(::SynchronousRule) = ContinuousProfileRow(
    :synchronous_rule, :stable, "common-snapshot CPU reference")
_statement_profile(::AlgebraicAssignment) = ContinuousProfileRow(
    :algebraic_assignment, :stable, "acyclic reactive assignment")
_statement_profile(::FunctionDefinition) = ContinuousProfileRow(
    :function_definition, :stable, "pure named expression")
_statement_profile(::AlgebraicConstraint) = ContinuousProfileRow(
    :dae_constraint, :experimental_unsupported,
    "DAE index/solver qualification is not claimed")
_statement_profile(::StochasticDifferentialEquation) = ContinuousProfileRow(
    :stochastic_differential_equation, :experimental_unsupported,
    "semantic stochastic solver qualification is not claimed")
_statement_profile(statement::ReactionStatement) =
    statement.interpretation isa DeterministicReaction ?
    ContinuousProfileRow(:deterministic_reaction,
        :experimental_unsupported,
        "reaction lowering requires an explicit stoichiometric reference profile") :
    ContinuousProfileRow(:jump_process,
        :experimental_unsupported,
        "jump/hybrid RNG and continuation qualification is not claimed")

function continuous_profile_report(system::ContinuousSystem)
    rows = Tuple(_statement_profile(statement)
        for statement in system.statements)
    if system.solver isa AdaptiveStep
        rows = (rows..., ContinuousProfileRow(
            :adaptive_step, :experimental_unsupported,
            "adaptive-controller exact continuation is not qualified"))
    end
    return ContinuousProfileReport(system.name, rows,
        all(row -> row.status === :stable, rows))
end

function preflight_continuous(system::ContinuousSystem)
    report = continuous_profile_report(system)
    unsupported = Tuple(row for row in report.rows
        if row.status !== :stable)
    isempty(unsupported) ||
        throw(UnsupportedContinuousProfile(system.name, unsupported))
    return report
end

component_identity(system::ContinuousSystem) =
    ComponentIdentity(system.name, system.version, :continuous_system)
component_semantic_data(system::ContinuousSystem) = (
    domain = system.domain, state = system.state,
    parameters = system.parameters, inputs = system.inputs,
    statements = system.statements, events = system.events,
    solver = system.solver, clock = system.clock)
component_effects(::ContinuousSystem) = (:continuous_state_advance,)
process_reads(system::ContinuousSystem) =
    ((:continuous_system, system.name),)
process_writes(system::ContinuousSystem) =
    ((:continuous_system, system.name),)

function _validate_assignment_graph(statements)
    assignments = Tuple(statement for statement in statements
        if statement isa AlgebraicAssignment)
    targets = Set(statement.target for statement in assignments)
    dependencies = Dict(statement.target =>
        Set(read for read in statement.reads if read in targets)
        for statement in assignments)
    remaining = Set(keys(dependencies))
    while !isempty(remaining)
        ready = Set(target for target in remaining
            if isempty(intersect(dependencies[target], remaining)))
        isempty(ready) && throw(ArgumentError(
            "reactive algebraic assignments contain a dependency cycle"))
        setdiff!(remaining, ready)
    end
    return statements
end

mutable struct ContinuousSystemState{D <: ContinuousSystem, N <: NamedTuple, T}
    declaration::D
    values::N
    time::T
    diagnostics::NamedTuple
end
function ContinuousSystemState(system::ContinuousSystem,
        values::NamedTuple; time = zero(Float64))
    expected = Tuple(variable.name for variable in system.state)
    Tuple(propertynames(values)) == expected || throw(ArgumentError(
        "continuous-system initial values must exactly match state declaration order"))
    return ContinuousSystemState(system, values, time, (; steps = 0))
end

_evaluate_expression(value::Number, state, parameters, inputs, time) = value
_evaluate_expression(value::Symbol, state, parameters, inputs, time) =
    hasproperty(state, value) ? getproperty(state, value) :
    hasproperty(parameters, value) ? getproperty(parameters, value) :
    hasproperty(inputs, value) ? getproperty(inputs, value) :
    value === :time ? time : throw(ArgumentError("unresolved continuous symbol `$value`"))
function _evaluate_expression(law::DirectLaw, state, parameters, inputs, time)
    expression = law.function_value
    applicable(expression, state, parameters, inputs, time) &&
        return expression(state, parameters, inputs, time)
    applicable(expression, state, parameters, time) &&
        return expression(state, parameters, time)
    applicable(expression, state, time) && return expression(state, time)
    applicable(expression, state) && return expression(state)
    throw(ArgumentError(
        "continuous law `$(law.name)` has no supported pure call signature"))
end
function _evaluate_expression(expression, state, parameters, inputs, time)
    applicable(expression, state, parameters, inputs, time) &&
        return expression(state, parameters, inputs, time)
    applicable(expression, state, parameters, time) &&
        return expression(state, parameters, time)
    applicable(expression, state, time) && return expression(state, time)
    applicable(expression, state) && return expression(state)
    throw(ArgumentError(
        "continuous expression $(typeof(expression)) has no supported pure call signature"))
end

_named_replace(state::NamedTuple, key::Symbol, value) =
    merge(state, NamedTuple{(key,)}((
        convert(typeof(getproperty(state, key)), value),)))
_state_scale(state::NamedTuple, factor) =
    NamedTuple{propertynames(state)}(map(value -> factor * value, Tuple(state)))
_state_add(left::NamedTuple, right::NamedTuple) =
    NamedTuple{propertynames(left)}(map(+, Tuple(left), Tuple(right)))

function _ode_derivative(system::ContinuousSystem, state::NamedTuple,
        inputs, time)
    names = propertynames(state)
    values = map(names) do name
        equation = findfirst(statement -> statement isa DifferentialEquation &&
            statement.target === name, system.statements)
        equation === nothing ? zero(getproperty(state, name)) :
        _evaluate_expression(system.statements[equation].rhs,
            state, system.parameters, inputs, time)
    end
    return NamedTuple{names}(values)
end

function _ode_step(system, state, inputs, time, dt, ::ExplicitEuler)
    return _state_add(state,
        _state_scale(_ode_derivative(system, state, inputs, time), dt))
end
function _ode_step(system, state, inputs, time, dt, ::Heun)
    k1 = _ode_derivative(system, state, inputs, time)
    trial = _state_add(state, _state_scale(k1, dt))
    k2 = _ode_derivative(system, trial, inputs, time + dt)
    return _state_add(state, _state_scale(_state_add(k1, k2), dt / 2))
end
function _ode_step(system, state, inputs, time, dt, ::RK4)
    k1 = _ode_derivative(system, state, inputs, time)
    k2 = _ode_derivative(system,
        _state_add(state, _state_scale(k1, dt / 2)), inputs, time + dt / 2)
    k3 = _ode_derivative(system,
        _state_add(state, _state_scale(k2, dt / 2)), inputs, time + dt / 2)
    k4 = _ode_derivative(system,
        _state_add(state, _state_scale(k3, dt)), inputs, time + dt)
    weighted = _state_add(_state_add(k1, _state_scale(k2, 2)),
        _state_add(_state_scale(k3, 2), k4))
    return _state_add(state, _state_scale(weighted, dt / 6))
end

function _materialize_substeps(method::FixedStep, interval)
    if method.step === nothing
        return Int(method.substeps), interval / method.substeps
    end
    ratio = interval / method.step.value
    count = round(Int, ratio)
    isapprox(ratio, count; rtol = 0, atol = 8eps(typeof(ratio))) || throw(
        ArgumentError("fixed SystemStep must tile the requested interval exactly"))
    return count, method.step.value
end

function _apply_synchronous_rules(system, state, inputs, time)
    snapshot = state
    candidate = state
    for statement in system.statements
        statement isa SynchronousRule || continue
        value = _evaluate_expression(
            statement.expression, snapshot, system.parameters, inputs, time)
        candidate = _named_replace(candidate, statement.target, value)
    end
    return candidate
end

function _ordered_assignments(system)
    assignments = [statement for statement in system.statements
        if statement isa AlgebraicAssignment]
    ordered = AlgebraicAssignment[]
    available = Set(Symbol[])
    while !isempty(assignments)
        index = findfirst(statement ->
            all(read -> !(read in Set(item.target for item in assignments)) ||
                read in available, statement.reads), assignments)
        index === nothing && throw(ArgumentError(
            "algebraic assignment graph cannot be ordered"))
        statement = popat!(assignments, index)
        push!(ordered, statement)
        push!(available, statement.target)
    end
    return ordered
end

function _apply_assignments(system, state, inputs, time)
    candidate = state
    for statement in _ordered_assignments(system)
        value = _evaluate_expression(statement.expression,
            candidate, system.parameters, inputs, time)
        candidate = _named_replace(candidate, statement.target, value)
    end
    return candidate
end

_all_finite(value::Number) = isfinite(value)
_all_finite(value) = all(_all_finite, value)
_all_finite(values::NamedTuple) = all(_all_finite, Tuple(values))

function advance_continuous_system!(state::ContinuousSystemState,
        interval; inputs = state.declaration.inputs)
    system = state.declaration
    preflight_continuous(system)
    method = system.solver
    count, dt = _materialize_substeps(method, interval)
    candidate = state.values
    initial_time = state.time
    time = initial_time
    for _ in 1:count
        candidate = _ode_step(
            system, candidate, inputs, time, dt, method.method)
        time += dt
        _all_finite(candidate) || throw(ArgumentError(
            "continuous-system step produced nonfinite state"))
    end
    candidate = _apply_synchronous_rules(system, candidate, inputs, time)
    candidate = _apply_assignments(system, candidate, inputs, time)
    state.values = candidate
    state.time = initial_time + interval
    state.diagnostics = (; steps = count, dt, endpoint = state.time)
    return state
end

function _publish_state!(destination::ContinuousSystemState,
        source::ContinuousSystemState)
    destination.values = source.values
    destination.time = source.time
    destination.diagnostics = source.diagnostics
    return destination
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, system::ContinuousSystem, target_mcs, stage, interval)
    source = _state_by_name(snapshot.globals, system.name)
    target = _state_by_name(candidate.globals, system.name)
    _publish_state!(target, source)
    clock = system.clock
    amount = clock isa ContinuousClock ?
        interval_value(clock, interval) :
        interval isa ContinuousInterval ? interval.value :
        interval isa OneMCS ? clock.scale :
        interval isa HalfMCS ? clock.scale / 2 :
        clock.scale * convert(typeof(clock.scale), interval)
    advance_continuous_system!(target, amount)
    return nothing
end

# Focused convenience declarations lower to the same numerical machinery.
struct CellDynamics{S <: ContinuousSystem}
    system::S
end
CellDynamics(name::Symbol; kwargs...) =
    begin
        system = ContinuousSystem(name; kwargs...)
        system.domain isa CellDomain || throw(ArgumentError(
            "CellDynamics requires a CellDomain"))
        CellDynamics(system)
    end
component_identity(dynamics::CellDynamics) = ComponentIdentity(
    dynamics.system.name, dynamics.system.version, :cell_dynamics)
component_semantic_data(dynamics::CellDynamics) =
    component_semantic_data(dynamics.system)
process_reads(dynamics::CellDynamics) = Tuple(
    (:cell_property, variable.property)
    for variable in dynamics.system.state)
process_writes(dynamics::CellDynamics) = process_reads(dynamics)

_cell_scope_matches(::Nothing, snapshot, cell) = true
_cell_scope_matches(scope::Symbol, snapshot, cell) = scope === :all
_cell_scope_matches(scope::Tuple, snapshot, cell) =
    cell_type(snapshot, cell) in scope
_cell_scope_matches(scope, snapshot, cell) =
    applicable(scope, snapshot, cell) ? Bool(scope(snapshot, cell)) :
    throw(ArgumentError("unsupported CellDomain scope $(typeof(scope))"))

function _cell_inputs(system, snapshot, cell, target_mcs)
    names = propertynames(system.inputs)
    values = map(names) do name
        source = getproperty(system.inputs, name)
        if source isa DirectLaw
            function_value = source.function_value
            applicable(function_value, snapshot, cell, target_mcs) ?
                function_value(snapshot, cell, target_mcs) :
                applicable(function_value, snapshot, cell) ?
                function_value(snapshot, cell) :
                throw(ArgumentError(
                    "cell input law `$(source.name)` has no supported snapshot signature"))
        elseif applicable(source, snapshot, cell, target_mcs)
            source(snapshot, cell, target_mcs)
        elseif applicable(source, snapshot, cell)
            source(snapshot, cell)
        else
            source
        end
    end
    return NamedTuple{names}(values)
end

function _continuous_interval_amount(clock, interval)
    return clock isa ContinuousClock ?
        interval_value(clock, interval) :
        interval isa ContinuousInterval ? interval.value :
        interval isa OneMCS ? clock.scale :
        interval isa HalfMCS ? clock.scale / 2 :
        clock.scale * convert(typeof(clock.scale), interval)
end

function execute_cell_dynamics!(candidate::LogicalPottsState,
        snapshot::LogicalPottsState, dynamics::CellDynamics,
        target_mcs, interval)
    system = dynamics.system
    system.domain isa CellDomain || throw(ArgumentError(
        "CellDynamics execution requires CellDomain"))
    amount = _continuous_interval_amount(system.clock, interval)
    property_keys = Tuple(variable.property for variable in system.state)
    names = Tuple(variable.name for variable in system.state)
    for cell in active_cell_ids(snapshot)
        _cell_scope_matches(
            system.domain.scope, snapshot, cell) || continue
        values = NamedTuple{names}(Tuple(
            property_value(snapshot, key, cell)
            for key in property_keys))
        local_state = ContinuousSystemState(system, values;
            time = (target_mcs - 1) * amount)
        inputs = _cell_inputs(system, snapshot, cell, target_mcs)
        advance_continuous_system!(local_state, amount; inputs)
        for (key, name) in zip(property_keys, names)
            set_cell_property!(
                candidate, key, cell, getproperty(local_state.values, name))
        end
    end
    return candidate
end

struct AffineCellAdvance{STATE, CONSTANT, INPUT, TIME, S, T}
    name::Symbol
    scope::S
    state::Symbol
    constant::Symbol
    input::Symbol
    time::Symbol
    decay::T
    duration::T
    version::VersionNumber
end
function AffineCellAdvance(name::Symbol, scope;
        state::Symbol, constant::Symbol, input::Symbol, time::Symbol,
        decay::T, duration::T,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isfinite(decay) && decay >= zero(T) || throw(ArgumentError(
        "affine cell decay must be finite and non-negative"))
    isfinite(duration) && duration > zero(T) || throw(ArgumentError(
        "affine cell duration must be finite and positive"))
    length(unique((state, constant, input, time))) == 4 || throw(ArgumentError(
        "affine cell property roles must be distinct"))
    return AffineCellAdvance{
        state, constant, input, time, typeof(scope), T}(
        name, scope, state, constant, input, time,
        decay, duration, version)
end
component_identity(process::AffineCellAdvance) =
    ComponentIdentity(process.name, process.version, :cell_dynamics)
component_semantic_data(process::AffineCellAdvance) = (
    scope = process.scope, state = process.state,
    constant = process.constant, input = process.input,
    time = process.time, decay = process.decay,
    duration = process.duration)
process_reads(process::AffineCellAdvance) = (
    (:cell_property, process.state),
    (:cell_property, process.constant),
    (:cell_property, process.input),
    (:cell_property, process.time))
process_writes(process::AffineCellAdvance) = (
    (:cell_property, process.state),
    (:cell_property, process.time))

@inline function _affine_columns(columns,
        ::AffineCellAdvance{STATE, CONSTANT, INPUT, TIME}) where {
        STATE, CONSTANT, INPUT, TIME}
    return (
        getproperty(columns, STATE),
        getproperty(columns, CONSTANT),
        getproperty(columns, INPUT),
        getproperty(columns, TIME))
end

struct AffineCellWorkspace{S <: AbstractVector, T <: AbstractVector,
        C <: AbstractVector, I <: AbstractVector, E <: AbstractVector}
    candidate_state::S
    candidate_time::T
    status::C
    failing_index::I
    publication_epoch::E
end

mutable struct AffineCellRuntime{W}
    name::Symbol
    workspace::W
end

function AffineCellWorkspace(state_values::AbstractVector,
        time_values::AbstractVector)
    length(state_values) == length(time_values) || throw(DimensionMismatch(
        "affine cell state and time capacities differ"))
    candidate_state = similar(state_values)
    candidate_time = similar(time_values)
    status = similar(state_values, UInt32, 1)
    failing_index = similar(state_values, UInt32, 1)
    publication_epoch = similar(state_values, UInt64, 1)
    fill!(candidate_state, zero(eltype(candidate_state)))
    fill!(candidate_time, zero(eltype(candidate_time)))
    fill!(status, UInt32(0))
    fill!(failing_index, UInt32(0))
    fill!(publication_epoch, UInt64(0))
    return AffineCellWorkspace(
        candidate_state, candidate_time,
        status, failing_index, publication_epoch)
end

AffineCellRuntime(
    process::AffineCellAdvance, state::LogicalPottsState) =
    AffineCellRuntime(
        process.name, AffineCellWorkspace(state, process))

function AffineCellWorkspace(
        state::LogicalPottsState, process::AffineCellAdvance)
    state_values, _, _, times =
        _affine_columns(state.properties.columns, process)
    return AffineCellWorkspace(state_values, times)
end

function Adapt.adapt_structure(to, workspace::AffineCellWorkspace)
    return AffineCellWorkspace(
        Adapt.adapt(to, workspace.candidate_state),
        Adapt.adapt(to, workspace.candidate_time),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_index),
        Adapt.adapt(to, workspace.publication_epoch))
end

Adapt.adapt_structure(to, runtime::AffineCellRuntime) =
    AffineCellRuntime(
        runtime.name, Adapt.adapt(to, runtime.workspace))

function _publish_state!(
        destination::AffineCellRuntime, source::AffineCellRuntime)
    copyto!(
        destination.workspace.publication_epoch,
        source.workspace.publication_epoch)
    return destination
end

@inline function _affine_cell_solution(
        state, constant, input, decay, duration)
    if iszero(decay)
        return muladd(duration, constant + input, state)
    end
    equilibrium = (constant + input) / decay
    return muladd(
        state - equilibrium, exp(-decay * duration), equilibrium)
end

function apply_affine_cell_advance!(
        state::LogicalPottsState, process::AffineCellAdvance,
        workspace::AffineCellWorkspace)
    state_values, constants, inputs, times =
        _affine_columns(state.properties.columns, process)
    slots = nslots(capacity(state))
    length(state_values) == slots &&
        length(constants) == slots &&
        length(inputs) == slots &&
        length(times) == slots &&
        length(workspace.candidate_state) == slots &&
        length(workspace.candidate_time) == slots ||
        throw(DimensionMismatch(
            "affine cell property/workspace capacities differ"))
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_index, UInt32(0))
    copyto!(workspace.candidate_state, state_values)
    copyto!(workspace.candidate_time, times)
    for slot in 1:slots
        cell = CellID(slot)
        is_active(state, cell) || continue
        _cell_scope_matches_exchange(
            process.scope, state, cell) || continue
        state_value = @inbounds state_values[slot]
        constant = @inbounds constants[slot]
        input = @inbounds inputs[slot]
        time = @inbounds times[slot]
        if !(isfinite(state_value) && isfinite(constant) &&
                isfinite(input) && isfinite(time))
            workspace.status[1] = UInt32(1)
            workspace.failing_index[1] = UInt32(slot)
            throw(ArgumentError(
                "affine cell input is nonfinite at slot $slot"))
        end
        advanced = _affine_cell_solution(
            state_value, constant, input,
            process.decay, process.duration)
        advanced_time = time + process.duration
        if !(isfinite(advanced) && isfinite(advanced_time))
            workspace.status[1] = UInt32(2)
            workspace.failing_index[1] = UInt32(slot)
            throw(ArgumentError(
                "affine cell advance is nonfinite at slot $slot"))
        end
        @inbounds begin
            workspace.candidate_state[slot] =
                convert(eltype(state_values), advanced)
            workspace.candidate_time[slot] =
                convert(eltype(times), advanced_time)
        end
    end
    copyto!(state_values, workspace.candidate_state)
    copyto!(times, workspace.candidate_time)
    workspace.publication_epoch[1] += UInt64(1)
    return state
end

function execute_affine_cell_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        process::AffineCellAdvance)
    source_runtime = _state_by_name(
        snapshot.globals, process.name)
    target_runtime = _state_by_name(
        candidate.globals, process.name)
    source_runtime isa AffineCellRuntime &&
        target_runtime isa AffineCellRuntime || throw(ArgumentError(
            "affine cell runtime is not realized"))
    _publish_state!(target_runtime, source_runtime)
    apply_affine_cell_advance!(
        potts_candidate, process, target_runtime.workspace)
    return (process.state, process.time)
end

@inline function _record_affine_device_failure!(
        status, failing_index, code, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_index[1], UInt32(index))
    return nothing
end

@kernel function _affine_cell_initialize!(
        candidate_state, candidate_time, state_values, times,
        status, failing_index)
    slot = @index(Global, Linear)
    @inbounds begin
        candidate_state[slot] = state_values[slot]
        candidate_time[slot] = times[slot]
        if slot == 1
            status[1] = UInt32(0)
            failing_index[1] = typemax(UInt32)
        end
    end
end

@kernel function _affine_cell_advance_kernel!(
        candidate_state, candidate_time,
        state_values, constants, inputs, times,
        active, cell_types, scope_type, decay, duration,
        status, failing_index)
    slot = @index(Global, Linear)
    @inbounds if active[slot] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[slot])
        state_value = state_values[slot]
        constant = constants[slot]
        input = inputs[slot]
        time = times[slot]
        if !(isfinite(state_value) && isfinite(constant) &&
                isfinite(input) && isfinite(time))
            _record_affine_device_failure!(
                status, failing_index, 1, slot)
        else
            advanced = _affine_cell_solution(
                state_value, constant, input, decay, duration)
            advanced_time = time + duration
            if isfinite(advanced) && isfinite(advanced_time)
                candidate_state[slot] = advanced
                candidate_time[slot] = advanced_time
            else
                _record_affine_device_failure!(
                    status, failing_index, 2, slot)
            end
        end
    end
end

@kernel function _affine_cell_commit!(
        state_values, times, candidate_state, candidate_time,
        publication_epoch, status)
    slot = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        state_values[slot] = candidate_state[slot]
        times[slot] = candidate_time[slot]
        slot == 1 && (publication_epoch[1] += UInt64(1))
    end
end

function apply_affine_cell_advance!(plan::ExecutionPlan,
        scientific::CompiledScientificState,
        process::AffineCellAdvance,
        workspace::AffineCellWorkspace)
    execution = scientific_execution(scientific)
    core = execution.core
    state_values, constants, inputs, times =
        _affine_columns(core.properties, process)
    arrays = (
        state_values, constants, inputs, times,
        core.active, core.cell_types,
        workspace.candidate_state, workspace.candidate_time,
        workspace.status, workspace.failing_index,
        workspace.publication_epoch)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable affine cell storage has a backend mismatch"))
    slots = length(core.active)
    all(==(slots), map(length, (
        state_values, constants, inputs, times,
        workspace.candidate_state, workspace.candidate_time))) ||
        throw(DimensionMismatch(
            "portable affine cell capacities differ"))
    scope_type = _portable_scope_type(process.scope)
    initialize = _execution_kernel(
        plan, _affine_cell_initialize!, slots)
    launch!(plan, initialize,
        workspace.candidate_state, workspace.candidate_time,
        state_values, times, workspace.status,
        workspace.failing_index; ndrange = slots)
    advance = _execution_kernel(
        plan, _affine_cell_advance_kernel!, slots)
    launch!(plan, advance,
        workspace.candidate_state, workspace.candidate_time,
        state_values, constants, inputs, times,
        core.active, core.cell_types, scope_type,
        process.decay, process.duration,
        workspace.status, workspace.failing_index;
        ndrange = slots)
    commit = _execution_kernel(
        plan, _affine_cell_commit!, slots)
    launch!(plan, commit,
        state_values, times,
        workspace.candidate_state, workspace.candidate_time,
        workspace.publication_epoch, workspace.status;
        ndrange = slots)
    return scientific
end

function synchronize_affine_cell_status!(
        plan::ExecutionPlan, workspace::AffineCellWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_index))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(ArgumentError(
        "affine cell advance failed with status $status at slot $failing"))
end

struct UniformCellInitialization{PROPERTY, S, T}
    name::Symbol
    scope::S
    property::Symbol
    lower::T
    upper::T
    namespace::RNGNamespaceIdentity
    version::VersionNumber
end
function UniformCellInitialization(name::Symbol, scope;
        property::Symbol, lower::T, upper::T,
        namespace::RNGNamespaceIdentity,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isfinite(lower) && isfinite(upper) && lower < upper ||
        throw(ArgumentError(
            "uniform cell initialization requires finite ordered bounds"))
    return UniformCellInitialization{
        property, typeof(scope), T}(
        name, scope, property, lower, upper, namespace, version)
end
component_identity(initializer::UniformCellInitialization) =
    ComponentIdentity(
        initializer.name, initializer.version, :cell_initialization)
component_semantic_data(initializer::UniformCellInitialization) = (
    scope = initializer.scope, property = initializer.property,
    lower = initializer.lower, upper = initializer.upper,
    namespace = initializer.namespace)
process_reads(::UniformCellInitialization) = ()
process_writes(initializer::UniformCellInitialization) =
    ((:cell_property, initializer.property),)

@inline _uniform_initialization_values(
    columns, ::UniformCellInitialization{PROPERTY}) where {PROPERTY} =
    getproperty(columns, PROPERTY)

function apply_uniform_cell_initialization!(
        state::LogicalPottsState,
        initializer::UniformCellInitialization,
        workspace::AffineCellWorkspace,
        master_seed::UInt64)
    values = _uniform_initialization_values(
        state.properties.columns, initializer)
    length(values) == length(workspace.candidate_state) ||
        throw(DimensionMismatch(
            "uniform initialization workspace capacity differs"))
    copyto!(workspace.candidate_state, values)
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_index, UInt32(0))
    contract = Philox4x32x10V1()
    operation = extension_rng_operation(initializer.namespace)
    span = initializer.upper - initializer.lower
    for slot in eachindex(values)
        cell = CellID(slot)
        is_active(state, cell) || continue
        _cell_scope_matches_exchange(
            initializer.scope, state, cell) || continue
        address = RNGAddress(
            AuxiliaryInitializationStream, UInt64(0), UInt8(0),
            operation, CellEntity, UInt32(slot),
            value(generation(state, cell)), UInt8(0), UInt16(0))
        uniform = uniform_open01(
            eltype(values), contract, master_seed, address)
        candidate = muladd(span, uniform, initializer.lower)
        if !isfinite(candidate)
            workspace.status[1] = UInt32(1)
            workspace.failing_index[1] = UInt32(slot)
            throw(ArgumentError(
                "uniform cell initialization is nonfinite at slot $slot"))
        end
        @inbounds workspace.candidate_state[slot] = candidate
    end
    copyto!(values, workspace.candidate_state)
    workspace.publication_epoch[1] += UInt64(1)
    return state
end

@kernel function _uniform_cell_initialization_kernel!(
        candidate, active, generations, cell_types,
        scope_type, lower, upper, namespace, master_seed,
        status, failing_index)
    slot = @index(Global, Linear)
    @inbounds if active[slot] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[slot])
        operation = extension_rng_operation(namespace)
        address = _rng_address_unchecked(
            AuxiliaryInitializationStream, UInt64(0), UInt8(0),
            operation, CellEntity, UInt32(slot), generations[slot],
            UInt8(0), UInt16(0))
        uniform = uniform_open01(
            eltype(candidate), Philox4x32x10V1(),
            master_seed, address)
        value = muladd(upper - lower, uniform, lower)
        if isfinite(value)
            candidate[slot] = value
        else
            _record_affine_device_failure!(
                status, failing_index, 1, slot)
        end
    end
end

@kernel function _uniform_cell_commit!(
        values, candidate, publication_epoch, status)
    slot = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        values[slot] = candidate[slot]
        slot == 1 && (publication_epoch[1] += UInt64(1))
    end
end

function apply_uniform_cell_initialization!(
        plan::ExecutionPlan, scientific::CompiledScientificState,
        initializer::UniformCellInitialization,
        workspace::AffineCellWorkspace, master_seed::UInt64)
    execution = scientific_execution(scientific)
    core = execution.core
    values = _uniform_initialization_values(
        core.properties, initializer)
    length(values) == length(workspace.candidate_state) ||
        throw(DimensionMismatch(
            "portable uniform initialization capacity differs"))
    arrays = (
        values, core.active, core.generations, core.cell_types,
        workspace.candidate_state, workspace.status,
        workspace.failing_index, workspace.publication_epoch)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable uniform initialization has a backend mismatch"))
    slots = length(values)
    initialize = _execution_kernel(
        plan, _affine_cell_initialize!, slots)
    launch!(plan, initialize,
        workspace.candidate_state, workspace.candidate_time,
        values, workspace.candidate_time,
        workspace.status, workspace.failing_index;
        ndrange = slots)
    kernel = _execution_kernel(
        plan, _uniform_cell_initialization_kernel!, slots)
    launch!(plan, kernel,
        workspace.candidate_state, core.active,
        core.generations, core.cell_types,
        _portable_scope_type(initializer.scope),
        initializer.lower, initializer.upper,
        initializer.namespace, master_seed,
        workspace.status, workspace.failing_index;
        ndrange = slots)
    commit = _execution_kernel(
        plan, _uniform_cell_commit!, slots)
    launch!(plan, commit,
        values, workspace.candidate_state,
        workspace.publication_epoch, workspace.status;
        ndrange = slots)
    return scientific
end

struct FieldAdvanceWorkspace{A <: AbstractArray,
        S <: AbstractVector, I <: AbstractVector}
    first::A
    second::A
    status::S
    failing_index::I
end

struct FieldAdvanceDiagnostics{T}
    steps::Int
    dt::T
    endpoint::T
    residual::T
    threshold::T
    iterations::Int
    converged::Bool
    mode::Symbol
end

function Adapt.adapt_structure(to, workspace::FieldAdvanceWorkspace)
    return FieldAdvanceWorkspace(
        Adapt.adapt(to, workspace.first),
        Adapt.adapt(to, workspace.second),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_index))
end

mutable struct EvolvingFieldState{A <: AbstractArray, T, B,
        E <: AbstractVector, W}
    name::Symbol
    values::A
    forcing::A
    spacing::T
    boundary::B
    time::T
    diagnostics::FieldAdvanceDiagnostics{T}
    publication_epoch::E
    workspace::W
end
function EvolvingFieldState(name::Symbol, values::AbstractArray{T};
        spacing = nothing, boundary = PeriodicFieldBoundary(),
        time = nothing) where {T <: AbstractFloat}
    resolved_spacing = spacing === nothing ? one(T) : convert(T, spacing)
    resolved_time = time === nothing ? zero(T) : convert(T, time)
    authoritative = copy(values)
    forcing = similar(authoritative)
    first = similar(authoritative)
    second = similar(authoritative)
    status = similar(authoritative, UInt32, 1)
    failing_index = similar(authoritative, UInt32, 1)
    publication_epoch = similar(authoritative, UInt64, 1)
    fill!(forcing, zero(T))
    fill!(first, zero(T))
    fill!(second, zero(T))
    fill!(status, UInt32(0))
    fill!(failing_index, UInt32(0))
    fill!(publication_epoch, UInt64(0))
    workspace = FieldAdvanceWorkspace(
        first, second, status, failing_index)
    diagnostics = FieldAdvanceDiagnostics(
        0, zero(T), resolved_time, zero(T), zero(T), 0, true, :uninitialized)
    return EvolvingFieldState(name, authoritative, forcing,
        resolved_spacing, boundary, resolved_time, diagnostics,
        publication_epoch, workspace)
end

function Adapt.adapt_structure(to, state::EvolvingFieldState)
    return EvolvingFieldState(
        state.name,
        Adapt.adapt(to, state.values),
        Adapt.adapt(to, state.forcing),
        state.spacing,
        state.boundary,
        state.time,
        state.diagnostics,
        Adapt.adapt(to, state.publication_epoch),
        Adapt.adapt(to, state.workspace))
end

struct ReactionDiffusion{T, R}
    diffusion::T
    decay::T
    reaction::R
end
function ReactionDiffusion(; diffusion::T, decay = nothing,
        reaction = nothing) where {T <: AbstractFloat}
    resolved_decay = decay === nothing ? zero(T) : convert(T, decay)
    return ReactionDiffusion(diffusion, resolved_decay, reaction)
end

struct FieldDynamics{L, M, C, P <: Tuple}
    name::Symbol
    field::Symbol
    law::L
    method::M
    clock::C
    post_substep::P
    version::VersionNumber
end
function FieldDynamics(name::Symbol; field::Symbol, law,
        method, clock, post_substep::Tuple = (),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    method isa Union{FixedStep, SteadyStateAdvance} || throw(ArgumentError(
        "FieldDynamics method must be FixedStep or SteadyStateAdvance"))
    return FieldDynamics(
        name, field, law, method, clock, post_substep, version)
end
component_identity(dynamics::FieldDynamics) =
    ComponentIdentity(dynamics.name, dynamics.version, :field_dynamics)
component_semantic_data(dynamics::FieldDynamics) = (
    field = dynamics.field, law = dynamics.law,
    method = dynamics.method, clock = dynamics.clock,
    post_substep = dynamics.post_substep)
process_reads(dynamics::FieldDynamics) = ((:field, dynamics.field),)
process_writes(dynamics::FieldDynamics) = ((:field, dynamics.field),)

function _field_neighbor(values, index::CartesianIndex, axis, delta,
        ::PeriodicFieldBoundary)
    coordinates = Tuple(index)
    size_axis = size(values, axis)
    shifted = Base.setindex(coordinates,
        mod1(coordinates[axis] + delta, size_axis), axis)
    return @inbounds values[shifted...]
end
function _field_neighbor(values, index::CartesianIndex, axis, delta,
        ::ZeroNeumannFieldBoundary)
    coordinates = Tuple(index)
    shifted = Base.setindex(coordinates,
        clamp(coordinates[axis] + delta, 1, size(values, axis)), axis)
    return @inbounds values[shifted...]
end
function _field_laplacian(values, boundary, spacing)
    result = similar(values)
    inverse_spacing2 = inv(spacing * spacing)
    for index in CartesianIndices(values)
        center = @inbounds values[index]
        value = zero(center)
        for axis in 1:ndims(values)
            value += _field_neighbor(values, index, axis, -1, boundary) +
                _field_neighbor(values, index, axis, 1, boundary) - 2center
        end
        @inbounds result[index] = value * inverse_spacing2
    end
    return result
end

@inline _field_reaction_value(::Nothing, value) = zero(value)
@inline _field_reaction_value(reaction, value) = reaction(value)

@inline function _periodic_reaction_diffusion_value(
        input, forcing, law, spacing, dt, row, column)
    rows, columns = size(input)
    left_column = column == 1 ? columns : column - 1
    right_column = column == columns ? 1 : column + 1
    down_row = row == 1 ? rows : row - 1
    up_row = row == rows ? 1 : row + 1
    @inbounds begin
        center = input[row, column]
        pair_x = input[row, left_column] + input[row, right_column]
        pair_y = input[down_row, column] + input[up_row, column]
        laplacian = ((pair_x + pair_y) - 4 * center) / (spacing * spacing)
        derivative = muladd(law.diffusion, laplacian,
            _field_reaction_value(law.reaction, center) +
            forcing[row, column] - law.decay * center)
        return muladd(dt, derivative, center)
    end
end

function _field_substep!(output::AbstractMatrix, input::AbstractMatrix,
        forcing, law, spacing, dt, ::PeriodicFieldBoundary,
        constraints::Tuple, ownership)
    for column in axes(input, 2), row in axes(input, 1)
        value = _periodic_reaction_diffusion_value(
            input, forcing, law, spacing, dt, row, column)
        @inbounds output[row, column] = _apply_field_constraints(
            constraints, value, CartesianIndex(row, column), ownership)
    end
    return output
end

function _field_substep!(output, input, forcing, law, spacing, dt,
        boundary, constraints::Tuple, ownership)
    inverse_spacing2 = inv(spacing * spacing)
    for index in CartesianIndices(input)
        center = @inbounds input[index]
        laplacian = zero(center)
        for axis in 1:ndims(input)
            laplacian += _field_neighbor(input, index, axis, -1, boundary) +
                _field_neighbor(input, index, axis, 1, boundary) - 2center
        end
        derivative = law.diffusion * laplacian * inverse_spacing2 -
            law.decay * center +
            _field_reaction_value(law.reaction, center) + forcing[index]
        candidate = muladd(dt, derivative, center)
        @inbounds output[index] = _apply_field_constraints(
            constraints, candidate, index, ownership)
    end
    return output
end

function _first_invalid_field_value(values)
    for index in eachindex(values)
        isfinite(@inbounds values[index]) || return Int(index)
    end
    return 0
end

function _validate_transient_field_profile(state, law, count, dt)
    count > 0 || throw(ArgumentError(
        "field advance requires at least one substep"))
    isfinite(dt) && dt > zero(dt) || throw(ArgumentError(
        "field substep must be finite and positive"))
    law.diffusion >= zero(law.diffusion) || throw(ArgumentError(
        "field diffusion must be non-negative"))
    law.decay >= zero(law.decay) || throw(ArgumentError(
        "field decay must be non-negative"))
    state.spacing > zero(state.spacing) && isfinite(state.spacing) ||
        throw(ArgumentError("field spacing must be finite and positive"))
    if law.diffusion > zero(law.diffusion)
        courant = law.diffusion * dt / (state.spacing * state.spacing)
        limit = inv(convert(typeof(courant), 2 * ndims(state.values)))
        courant <= limit || throw(ArgumentError(
            "explicit field step exceeds the declared diffusion stability limit"))
    end
    return nothing
end

function _advance_transient_field!(state::EvolvingFieldState,
        dynamics::FieldDynamics, interval, method::FixedStep, ownership)
    law = dynamics.law
    law isa ReactionDiffusion || throw(ArgumentError(
        "the stable field reference currently requires ReactionDiffusion"))
    count, dt = _materialize_substeps(method, interval)
    state.workspace.status[1] = UInt32(0)
    state.workspace.failing_index[1] = UInt32(0)
    try
        _validate_transient_field_profile(state, law, count, dt)
    catch
        state.workspace.status[1] = UInt32(2)
        rethrow()
    end
    input = state.values
    output = state.workspace.first
    for step in 1:count
        _field_substep!(output, input, state.forcing, law,
            state.spacing, dt, state.boundary,
            dynamics.post_substep, ownership)
        invalid = _first_invalid_field_value(output)
        if !iszero(invalid)
            state.workspace.status[1] = UInt32(1)
            state.workspace.failing_index[1] = UInt32(invalid)
            throw(ArgumentError(
                "field advance produced nonfinite values at canonical index $invalid"))
        end
        input = output
        output = isodd(step) ? state.workspace.second : state.workspace.first
    end
    copyto!(state.values, input)
    state.time += interval
    state.publication_epoch[1] += UInt64(1)
    state.diagnostics = FieldAdvanceDiagnostics(
        count, dt, state.time, zero(dt), zero(dt), 0, true, :transient)
    return state
end

function advance_field!(state::EvolvingFieldState,
        dynamics::FieldDynamics, interval, ownership = nothing)
    return _advance_field_method!(
        state, dynamics, interval, dynamics.method, ownership)
end

_advance_field_method!(state, dynamics, interval, method::FixedStep, ownership) =
    _advance_transient_field!(state, dynamics, interval, method, ownership)

function _publish_state!(destination::EvolvingFieldState,
        source::EvolvingFieldState)
    copyto!(destination.values, source.values)
    copyto!(destination.forcing, source.forcing)
    destination.time = source.time
    destination.diagnostics = source.diagnostics
    copyto!(destination.publication_epoch, source.publication_epoch)
    return destination
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, dynamics::FieldDynamics, target_mcs, stage, interval)
    source = _state_by_name(snapshot.fields, dynamics.field)
    target = _state_by_name(candidate.fields, dynamics.field)
    _publish_state!(target, source)
    amount = _field_interval_amount(dynamics, interval)
    advance_field!(target, dynamics, amount, potts_snapshot)
    return nothing
end

function _field_interval_amount(dynamics::FieldDynamics, interval)
    return dynamics.clock isa ContinuousClock ?
        interval_value(dynamics.clock, interval) :
        interval isa OneMCS ? dynamics.clock.scale :
        interval isa HalfMCS ? dynamics.clock.scale / 2 :
        interval isa ContinuousInterval ? interval.value :
        dynamics.clock.scale * interval
end

struct ByCellVolume end
struct ConstantConcentration{S, T}
    scope::S
    value::T
end

@inline _field_constraint_matches(::Nothing, owner, ownership) = false
@inline _field_constraint_matches(scope::Symbol, owner, ownership) =
    scope === :all ||
    (scope === :cells && is_cell_owner(owner)) ||
    (scope === :medium && is_medium_owner(owner))
@inline _field_constraint_matches(scope::CellTypeID, owner, ownership) =
    is_cell_owner(owner) &&
    cell_type(ownership, CellID(owner.value)) == scope
@inline function _field_constraint_matches(scope, owner, ownership)
    applicable(scope, owner, ownership) ||
        throw(ArgumentError(
            "unsupported field constraint scope $(typeof(scope))"))
    return Bool(scope(owner, ownership))
end

@inline _field_owner(ownership::Nothing, index) = nothing
@inline _field_owner(ownership::LogicalPottsState, index) =
    @inbounds lattice_storage(ownership)[index]

@inline _apply_field_constraints(::Tuple{}, value, index, ownership) = value
@inline function _apply_field_constraints(
        constraints::Tuple, value, index, ownership)
    constraint = first(constraints)
    constraint isa ConstantConcentration || throw(ArgumentError(
        "unsupported field post-substep constraint $(typeof(constraint))"))
    owner = _field_owner(ownership, index)
    constrained = _field_constraint_matches(
        constraint.scope, owner, ownership) ?
        convert(typeof(value), constraint.value) : value
    return _apply_field_constraints(
        Base.tail(constraints), constrained, index, ownership)
end
struct Uptake{S, T, N}
    scope::S
    maximum::T
    relative_rate::T
    normalize::N
    output::Union{Nothing, Symbol}
end
function Uptake(scope; maximum::T, relative_rate::T,
        normalize = ByCellVolume(), output = nothing) where {T}
    maximum >= zero(T) && relative_rate >= zero(T) || throw(ArgumentError(
        "uptake parameters must be non-negative"))
    return Uptake(scope, maximum, relative_rate, normalize, output)
end

struct MaximumCalibration{T}
    numerator::T
    state::Symbol
    function MaximumCalibration(numerator::T, state::Symbol) where {T <: AbstractFloat}
        isfinite(numerator) && numerator > zero(T) || throw(ArgumentError(
            "maximum calibration numerator must be finite and positive"))
        return new{T}(numerator, state)
    end
end

@enum FieldExchangeMode::UInt8 begin
    InactiveExchange = 0
    ResetExchange = 1
    CalibrateExchange = 2
    PublishExchange = 3
end

struct PlanModeSchedule{E <: Tuple}
    entries::E
end
function PlanModeSchedule(entries::Pair...)
    isempty(entries) && throw(ArgumentError(
        "plan mode schedule requires at least one range"))
    all(entry -> first(entry) isa MCSRange &&
                 last(entry) isa FieldExchangeMode, entries) ||
        throw(ArgumentError(
            "plan mode entries must map MCSRange to FieldExchangeMode"))
    ordered = Tuple(entries)
    for index in 2:length(ordered)
        previous = first(ordered[index - 1])
        current = first(ordered[index])
        previous.last < current.first || throw(ArgumentError(
            "plan mode ranges must be ordered and nonoverlapping"))
        previous.last + UInt64(1) == current.first || throw(ArgumentError(
            "plan mode schedule may not contain implicit gaps"))
    end
    return PlanModeSchedule(ordered)
end
function mode_at(schedule::PlanModeSchedule, target_mcs::Integer)
    for entry in schedule.entries
        target_mcs in first(entry) && return last(entry)
    end
    throw(ArgumentError(
        "target MCS $target_mcs is outside the plan mode schedule"))
end

@enum FieldExchangeFailureCode::UInt32 begin
    ExchangeSucceeded = 0
    ExchangeShapeMismatch = 1
    ExchangeInvalidVolume = 2
    ExchangeInvalidConcentration = 3
    ExchangeInvalidRemoval = 4
    ExchangeInvalidCalibration = 5
    ExchangeUninitializedCalibration = 6
    ExchangeInvalidGeneration = 7
end

struct FieldExchangeFailure <: Exception
    code::FieldExchangeFailureCode
    index::UInt32
end
function Base.showerror(io::IO, error::FieldExchangeFailure)
    print(io, "field exchange failed with ", Symbol(error.code))
    iszero(error.index) || print(io, " at canonical index ", error.index)
end

struct FieldExchangeWorkspace{R <: AbstractVector, S <: AbstractVector,
        C <: AbstractVector, I <: AbstractVector}
    raw_totals::R
    candidate_signal::S
    status::C
    failing_index::I
end

mutable struct FieldExchangeState{V <: AbstractVector, I <: AbstractVector,
        E <: AbstractVector, W}
    name::Symbol
    value::V
    initialized::I
    publication_epoch::E
    workspace::W
end

function FieldExchangeState(name::Symbol, field::EvolvingFieldState,
        ownership::LogicalPottsState; accumulator_type::Type{A} = Float64) where {
        A <: AbstractFloat}
    slots = nslots(capacity(ownership))
    value = similar(field.values, eltype(field.values), 1)
    initialized = similar(field.values, UInt8, 1)
    publication_epoch = similar(field.values, UInt64, 1)
    raw_totals = similar(field.values, A, slots)
    candidate_signal = similar(field.values, eltype(field.values), slots)
    status = similar(field.values, UInt32, 1)
    failing_index = similar(field.values, UInt32, 1)
    fill!(value, zero(eltype(value)))
    fill!(initialized, UInt8(0))
    fill!(publication_epoch, UInt64(0))
    fill!(raw_totals, zero(A))
    fill!(candidate_signal, zero(eltype(candidate_signal)))
    fill!(status, UInt32(ExchangeSucceeded))
    fill!(failing_index, UInt32(0))
    workspace = FieldExchangeWorkspace(
        raw_totals, candidate_signal, status, failing_index)
    return FieldExchangeState(
        name, value, initialized, publication_epoch, workspace)
end

function Adapt.adapt_structure(to, workspace::FieldExchangeWorkspace)
    return FieldExchangeWorkspace(
        Adapt.adapt(to, workspace.raw_totals),
        Adapt.adapt(to, workspace.candidate_signal),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_index))
end

function Adapt.adapt_structure(to, state::FieldExchangeState)
    return FieldExchangeState(
        state.name,
        Adapt.adapt(to, state.value),
        Adapt.adapt(to, state.initialized),
        Adapt.adapt(to, state.publication_epoch),
        Adapt.adapt(to, state.workspace))
end

function _publish_state!(
        destination::FieldExchangeState, source::FieldExchangeState)
    copyto!(destination.value, source.value)
    copyto!(destination.initialized, source.initialized)
    copyto!(destination.publication_epoch, source.publication_epoch)
    return destination
end

struct FieldExchange{S <: Tuple, K <: Tuple, C}
    name::Symbol
    field::Symbol
    sources::S
    sinks::K
    calibration::C
    version::VersionNumber
end
function FieldExchange(name::Symbol; field::Symbol,
        sources::Tuple = (), sinks::Tuple = (), calibration = nothing,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    calibration isa Union{Nothing, MaximumCalibration} || throw(ArgumentError(
        "unsupported field-exchange calibration declaration"))
    return FieldExchange(
        name, field, sources, sinks, calibration, version)
end
component_identity(exchange::FieldExchange) =
    ComponentIdentity(exchange.name, exchange.version, :field_exchange)
component_semantic_data(exchange::FieldExchange) = (
    field = exchange.field, sources = exchange.sources, sinks = exchange.sinks,
    calibration = exchange.calibration)
function process_reads(exchange::FieldExchange)
    calibration = exchange.calibration === nothing ? () :
        ((:global, exchange.calibration.state),)
    return ((:ownership, :lattice), (:field, exchange.field), calibration...)
end
function process_writes(exchange::FieldExchange)
    outputs = Tuple((:cell_property, sink.output)
        for sink in exchange.sinks if sink isa Uptake && sink.output !== nothing)
    calibration = exchange.calibration === nothing ? () :
        ((:global, exchange.calibration.state),)
    field_write = isempty(exchange.sinks) ? () : ((:field, exchange.field),)
    forcing_write = isempty(exchange.sources) ? () :
        ((:field_forcing, exchange.field),)
    return (field_write..., forcing_write..., outputs..., calibration...)
end

_scope_matches(::Nothing, owner, state) = true
_scope_matches(scope::Symbol, owner, state) =
    scope === :all || (scope === :cells && is_cell_owner(owner)) ||
    (scope === :medium && is_medium_owner(owner))
_scope_matches(scope::CellTypeID, owner, state) =
    is_cell_owner(owner) &&
    cell_type(state, CellID(owner.value)) == scope
function _scope_matches(scope, owner, state)
    applicable(scope, owner, state) || throw(ArgumentError(
        "unsupported field-exchange scope $(typeof(scope))"))
    return Bool(scope(owner, state))
end

_cell_scope_matches_exchange(::Nothing, state, cell) = true
_cell_scope_matches_exchange(scope::Symbol, state, cell) =
    scope === :all || scope === :cells
_cell_scope_matches_exchange(scope::CellTypeID, state, cell) =
    cell_type(state, cell) == scope
_cell_scope_matches_exchange(scope::Tuple, state, cell) =
    cell_type(state, cell) in scope
function _cell_scope_matches_exchange(scope, state, cell)
    applicable(scope, state, cell) || throw(ArgumentError(
        "unsupported cell-exchange scope $(typeof(scope))"))
    return Bool(scope(state, cell))
end

function _exchange_fail!(runtime::FieldExchangeState,
        code::FieldExchangeFailureCode, index::Integer)
    runtime.workspace.status[1] = UInt32(code)
    runtime.workspace.failing_index[1] = UInt32(index)
    throw(FieldExchangeFailure(code, UInt32(index)))
end

function _validate_direct_exchange(
        field, exchange, ownership, signal, runtime)
    size(field.values) == lattice_size(ownership) ||
        _exchange_fail!(runtime, ExchangeShapeMismatch, 0)
    slots = nslots(capacity(ownership))
    length(signal) == slots &&
        length(runtime.workspace.raw_totals) == slots &&
        length(runtime.workspace.candidate_signal) == slots ||
        _exchange_fail!(runtime, ExchangeShapeMismatch, 0)
    length(exchange.sources) == 0 || throw(ArgumentError(
        "direct uptake transaction does not admit forcing sources"))
    length(exchange.sinks) == 1 || throw(ArgumentError(
        "direct uptake transaction requires exactly one sink"))
    sink = only(exchange.sinks)
    sink isa Uptake || throw(ArgumentError(
        "direct uptake transaction requires Uptake"))
    sink.normalize isa ByCellVolume || throw(ArgumentError(
        "direct uptake transaction requires ByCellVolume normalization"))
    sink.output === nothing && throw(ArgumentError(
        "direct uptake transaction requires a named cell output"))
    return sink
end

function _prepare_exchange_workspace!(runtime, signal)
    fill!(runtime.workspace.status, UInt32(ExchangeSucceeded))
    fill!(runtime.workspace.failing_index, UInt32(0))
    fill!(runtime.workspace.raw_totals,
        zero(eltype(runtime.workspace.raw_totals)))
    copyto!(runtime.workspace.candidate_signal, signal)
    return runtime
end

function _publish_exchange_epoch!(runtime::FieldExchangeState)
    runtime.publication_epoch[1] += UInt64(1)
    return runtime
end

"""
Apply an immediate field/cell/global exchange as one failure-atomic CPU transaction.

The root plan supplies `mode`; the process contains no MCS-dependent scheduling branch.
The field's two existing staging grids serve as candidate concentration and per-site removal
workspace and are never checkpointed.
"""
function apply_field_exchange!(field::EvolvingFieldState,
        exchange::FieldExchange, ownership::LogicalPottsState,
        signal::AbstractVector, runtime::FieldExchangeState,
        mode::FieldExchangeMode, target_mcs::Integer)
    sink = _validate_direct_exchange(
        field, exchange, ownership, signal, runtime)
    _prepare_exchange_workspace!(runtime, signal)
    mode === InactiveExchange && return false

    slots = nslots(capacity(ownership))
    if mode === ResetExchange
        for slot in 1:slots
            cell = CellID(slot)
            is_active(ownership, cell) || continue
            _cell_scope_matches_exchange(sink.scope, ownership, cell) || continue
            runtime.workspace.candidate_signal[slot] =
                zero(eltype(runtime.workspace.candidate_signal))
        end
        copyto!(signal, runtime.workspace.candidate_signal)
        _publish_exchange_epoch!(runtime)
        return true
    end

    mode in (CalibrateExchange, PublishExchange) || throw(ArgumentError(
        "unsupported direct field-exchange mode"))
    exchange.calibration isa MaximumCalibration || throw(ArgumentError(
        "calibrate/publish exchange requires MaximumCalibration"))
    candidate_field = field.workspace.first
    removals = field.workspace.second
    copyto!(candidate_field, field.values)
    fill!(removals, zero(eltype(removals)))
    owners = lattice_storage(ownership)
    maximum_raw = zero(eltype(runtime.workspace.raw_totals))
    eligible_count = 0

    for slot in 1:slots
        cell = CellID(slot)
        is_active(ownership, cell) || continue
        _cell_scope_matches_exchange(sink.scope, ownership, cell) || continue
        eligible_count += 1
        volume = finite_volume(ownership, cell)
        volume > 0 || _exchange_fail!(
            runtime, ExchangeInvalidVolume, slot)
        total = zero(eltype(runtime.workspace.raw_totals))
        for site in eachindex(owners)
            owner = @inbounds owners[site]
            is_cell_owner(owner) && Int(owner.value) == slot || continue
            concentration = @inbounds field.values[site]
            isfinite(concentration) && concentration >= zero(concentration) ||
                _exchange_fail!(
                    runtime, ExchangeInvalidConcentration, site)
            removal = min(convert(typeof(concentration), sink.maximum),
                convert(typeof(concentration), sink.relative_rate) * concentration)
            isfinite(removal) &&
                zero(removal) <= removal <= concentration ||
                _exchange_fail!(runtime, ExchangeInvalidRemoval, site)
            @inbounds begin
                removals[site] = removal
                candidate_field[site] = concentration - removal
            end
            total += removal
        end
        raw = total / volume
        isfinite(raw) && raw >= zero(raw) ||
            _exchange_fail!(runtime, ExchangeInvalidRemoval, slot)
        runtime.workspace.raw_totals[slot] = raw
        maximum_raw = max(maximum_raw, raw)
    end

    eligible_count > 0 || _exchange_fail!(
        runtime, ExchangeInvalidCalibration, 0)
    calibration_value = runtime.value[1]
    if mode === CalibrateExchange
        maximum_raw > zero(maximum_raw) && isfinite(maximum_raw) ||
            _exchange_fail!(runtime, ExchangeInvalidCalibration, 0)
        calibration_value = convert(eltype(runtime.value),
            exchange.calibration.numerator / maximum_raw)
        isfinite(calibration_value) && calibration_value > zero(calibration_value) ||
            _exchange_fail!(runtime, ExchangeInvalidCalibration, 0)
    else
        runtime.initialized[1] == UInt8(1) ||
            _exchange_fail!(runtime, ExchangeUninitializedCalibration, 0)
        isfinite(calibration_value) && calibration_value > zero(calibration_value) ||
            _exchange_fail!(runtime, ExchangeInvalidCalibration, 0)
        for slot in 1:slots
            cell = CellID(slot)
            is_active(ownership, cell) || continue
            _cell_scope_matches_exchange(sink.scope, ownership, cell) || continue
            output = runtime.workspace.raw_totals[slot] * calibration_value
            isfinite(output) && output >= zero(output) ||
                _exchange_fail!(runtime, ExchangeInvalidRemoval, slot)
            runtime.workspace.candidate_signal[slot] =
                convert(eltype(signal), output)
        end
    end

    copyto!(field.values, candidate_field)
    mode === PublishExchange &&
        copyto!(signal, runtime.workspace.candidate_signal)
    if mode === CalibrateExchange
        runtime.value[1] = calibration_value
        runtime.initialized[1] = UInt8(1)
    end
    _publish_exchange_epoch!(runtime)
    return true
end

function execute_field_exchange!(candidate::CoupledState,
        snapshot::CoupledState, potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState, exchange::FieldExchange,
        schedule::PlanModeSchedule, target_mcs::Integer)
    exchange.calibration isa MaximumCalibration || throw(ArgumentError(
        "plan-resolved direct exchange requires MaximumCalibration"))
    sink = only(exchange.sinks)
    sink isa Uptake && sink.output !== nothing || throw(ArgumentError(
        "plan-resolved direct exchange requires one named Uptake output"))
    source_field = _state_by_name(snapshot.fields, exchange.field)
    target_field = _state_by_name(candidate.fields, exchange.field)
    source_runtime = _state_by_name(
        snapshot.globals, exchange.calibration.state)
    target_runtime = _state_by_name(
        candidate.globals, exchange.calibration.state)
    source_runtime isa FieldExchangeState &&
        target_runtime isa FieldExchangeState || throw(ArgumentError(
            "plan-resolved exchange calibration state is not realized"))
    _publish_state!(target_field, source_field)
    _publish_state!(target_runtime, source_runtime)
    source_signal = property_values(potts_snapshot, sink.output)
    target_signal = property_values(potts_candidate, sink.output)
    copyto!(target_signal, source_signal)
    apply_field_exchange!(
        target_field, exchange, potts_snapshot, target_signal,
        target_runtime, mode_at(schedule, target_mcs), target_mcs)
    return sink.output
end

function _portable_reduction_width(plan::ExecutionPlan)
    width = plan.block_size
    ispow2(width) && 2 <= width <= 256 || throw(ArgumentError(
        "portable fixed-tree reduction requires a power-of-two block size in 2:256"))
    return width
end

@inline function _record_exchange_device_failure!(
        status, failing_index, code::FieldExchangeFailureCode, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_index[1], UInt32(index))
    return nothing
end

@inline _portable_scope_type(::Nothing) = UInt32(0)
@inline _portable_scope_type(scope::Symbol) =
    scope in (:all, :cells) ? UInt32(0) :
    throw(ArgumentError(
        "portable uptake scope symbol must be :all or :cells"))
@inline _portable_scope_type(scope::CellTypeID) = value(scope)
@inline _portable_cell_eligible(scope_type, cell_type) =
    iszero(scope_type) | (scope_type == cell_type)

@kernel function _exchange_device_initialize_sites!(
        candidate_field, removals, field)
    site = @index(Global, Linear)
    @inbounds begin
        candidate_field[site] = field[site]
        removals[site] = zero(eltype(removals))
    end
end

@kernel function _exchange_device_initialize_cells!(
        raw_totals, candidate_signal, signal)
    cell = @index(Global, Linear)
    @inbounds begin
        raw_totals[cell] = zero(eltype(raw_totals))
        candidate_signal[cell] = signal[cell]
    end
end

@kernel function _exchange_device_clear_status!(status, failing_index)
    index = @index(Global, Linear)
    @inbounds if index == 1
        status[1] = UInt32(ExchangeSucceeded)
        failing_index[1] = typemax(UInt32)
    end
end

@kernel function _exchange_device_reduce_cells!(
        candidate_field, removals, raw_totals,
        field, owner_tags, owner_ids, active, cell_types, volumes,
        scope_type, maximum, relative_rate, status, failing_index,
        ::Val{Width}) where {Width}
    cell = @index(Group, Linear)
    lane = @index(Local, Linear)
    scratch = @localmem eltype(raw_totals) (Width,)
    total = zero(eltype(raw_totals))
    eligible = cell <= length(active) &&
        @inbounds(active[cell] != UInt8(0)) &&
        _portable_cell_eligible(
            scope_type, @inbounds(cell_types[cell]))
    if eligible
        site = lane
        while site <= length(field)
            if @inbounds(owner_tags[site] == _CELL_OWNER_TAG &&
                    owner_ids[site] == UInt32(cell))
                concentration = @inbounds field[site]
                if !(isfinite(concentration) &&
                        concentration >= zero(concentration))
                    _record_exchange_device_failure!(
                        status, failing_index,
                        ExchangeInvalidConcentration, site)
                else
                    removal = min(maximum, relative_rate * concentration)
                    if !(isfinite(removal) &&
                            zero(removal) <= removal <= concentration)
                        _record_exchange_device_failure!(
                            status, failing_index,
                            ExchangeInvalidRemoval, site)
                    else
                        @inbounds begin
                            removals[site] = removal
                            candidate_field[site] = concentration - removal
                        end
                        total += eltype(raw_totals)(removal)
                    end
                end
            end
            site += Width
        end
    end
    @inbounds scratch[lane] = total
    @synchronize
    if Width >= 256
        lane <= 128 && (@inbounds scratch[lane] += scratch[lane + 128])
        @synchronize
    end
    if Width >= 128
        lane <= 64 && (@inbounds scratch[lane] += scratch[lane + 64])
        @synchronize
    end
    if Width >= 64
        lane <= 32 && (@inbounds scratch[lane] += scratch[lane + 32])
        @synchronize
    end
    if Width >= 32
        lane <= 16 && (@inbounds scratch[lane] += scratch[lane + 16])
        @synchronize
    end
    if Width >= 16
        lane <= 8 && (@inbounds scratch[lane] += scratch[lane + 8])
        @synchronize
    end
    if Width >= 8
        lane <= 4 && (@inbounds scratch[lane] += scratch[lane + 4])
        @synchronize
    end
    if Width >= 4
        lane <= 2 && (@inbounds scratch[lane] += scratch[lane + 2])
        @synchronize
    end
    lane <= 1 && (@inbounds scratch[lane] += scratch[lane + 1])
    @synchronize
    if lane == 1
        if cell <= length(active) &&
                @inbounds(active[cell] != UInt8(0)) &&
                _portable_cell_eligible(
                    scope_type, @inbounds(cell_types[cell]))
            volume = @inbounds volumes[cell]
            if volume <= 0
                _record_exchange_device_failure!(
                    status, failing_index, ExchangeInvalidVolume, cell)
            else
                raw = @inbounds scratch[1] /
                    eltype(raw_totals)(volume)
                if !(isfinite(raw) && raw >= zero(raw))
                    _record_exchange_device_failure!(
                        status, failing_index,
                        ExchangeInvalidRemoval, cell)
                else
                    @inbounds raw_totals[cell] = raw
                end
            end
        end
    end
end

@kernel function _exchange_device_calibrate_maximum!(
        value, initialized, raw_totals, active, cell_types,
        scope_type, numerator, status, failing_index,
        ::Val{Width}) where {Width}
    lane = @index(Local, Linear)
    scratch = @localmem eltype(raw_totals) (Width,)
    local_maximum = zero(eltype(raw_totals))
    cell = lane
    while cell <= length(raw_totals)
        eligible = @inbounds(active[cell] != UInt8(0)) &&
            _portable_cell_eligible(
                scope_type, @inbounds(cell_types[cell]))
        eligible &&
            (local_maximum = max(
                local_maximum, @inbounds(raw_totals[cell])))
        cell += Width
    end
    @inbounds scratch[lane] = local_maximum
    @synchronize
    if Width >= 256
        lane <= 128 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 128]))
        @synchronize
    end
    if Width >= 128
        lane <= 64 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 64]))
        @synchronize
    end
    if Width >= 64
        lane <= 32 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 32]))
        @synchronize
    end
    if Width >= 32
        lane <= 16 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 16]))
        @synchronize
    end
    if Width >= 16
        lane <= 8 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 8]))
        @synchronize
    end
    if Width >= 8
        lane <= 4 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 4]))
        @synchronize
    end
    if Width >= 4
        lane <= 2 && (@inbounds scratch[lane] =
            max(scratch[lane], scratch[lane + 2]))
        @synchronize
    end
    lane <= 1 && (@inbounds scratch[lane] =
        max(scratch[lane], scratch[lane + 1]))
    @synchronize
    if lane == 1
        maximum_raw = @inbounds scratch[1]
        if !(isfinite(maximum_raw) && maximum_raw > zero(maximum_raw))
            _record_exchange_device_failure!(
                status, failing_index, ExchangeInvalidCalibration, 0)
        elseif @inbounds(status[1] == UInt32(ExchangeSucceeded))
            calibrated = numerator / maximum_raw
            if isfinite(calibrated) && calibrated > zero(calibrated)
                @inbounds begin
                    value[1] = calibrated
                    initialized[1] = UInt8(1)
                end
            else
                _record_exchange_device_failure!(
                    status, failing_index, ExchangeInvalidCalibration, 0)
            end
        end
    end
end

@kernel function _exchange_device_publish_signal!(
        candidate_signal, raw_totals, value, initialized,
        active, cell_types, scope_type, status, failing_index)
    cell = @index(Global, Linear)
    @inbounds if cell <= length(active) && active[cell] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[cell])
        if initialized[1] != UInt8(1)
            _record_exchange_device_failure!(
                status, failing_index,
                ExchangeUninitializedCalibration, 0)
        else
            output = raw_totals[cell] * value[1]
            if isfinite(output) && output >= zero(output)
                candidate_signal[cell] = output
            else
                _record_exchange_device_failure!(
                    status, failing_index,
                    ExchangeInvalidRemoval, cell)
            end
        end
    end
end

@kernel function _exchange_device_reset_signal!(
        candidate_signal, active, cell_types, scope_type)
    cell = @index(Global, Linear)
    @inbounds if cell <= length(active) && active[cell] != UInt8(0) &&
            _portable_cell_eligible(scope_type, cell_types[cell])
        candidate_signal[cell] = zero(eltype(candidate_signal))
    end
end

@kernel function _exchange_device_commit_field!(
        field, candidate_field, status)
    site = @index(Global, Linear)
    @inbounds status[1] == UInt32(ExchangeSucceeded) &&
        (field[site] = candidate_field[site])
end

@kernel function _exchange_device_commit_signal!(
        signal, candidate_signal, status)
    cell = @index(Global, Linear)
    @inbounds status[1] == UInt32(ExchangeSucceeded) &&
        (signal[cell] = candidate_signal[cell])
end

@kernel function _exchange_device_commit_epoch!(
        exchange_epoch, field_epoch, status)
    index = @index(Global, Linear)
    @inbounds if index == 1 &&
            status[1] == UInt32(ExchangeSucceeded)
        exchange_epoch[1] += UInt64(1)
        field_epoch[1] += UInt64(1)
    end
end

function _portable_exchange_arrays_match(
        plan::ExecutionPlan, field::EvolvingFieldState,
        runtime::FieldExchangeState, execution::ScientificExecutionState,
        signal)
    arrays = (
        field.values, field.workspace.first, field.workspace.second,
        field.publication_epoch,
        runtime.value, runtime.initialized, runtime.publication_epoch,
        runtime.workspace.raw_totals, runtime.workspace.candidate_signal,
        runtime.workspace.status, runtime.workspace.failing_index,
        execution.core.ownership.tags, execution.core.ownership.ids,
        execution.core.active, execution.core.cell_types,
        execution.trackers.finite_volumes, signal)
    all(array -> isbitstype(eltype(array)), arrays) || return false
    all(array -> isequal(
            KernelAbstractions.get_backend(array), plan.backend), arrays) ||
        return false
    return true
end

"""
Launch the portable fixed-tree immediate exchange without host scalar access or floating atomics.

Failure remains backend-resident. The stable observation/checkpoint boundary is responsible for
synchronizing once and translating a nonzero status into `FieldExchangeFailure`.
"""
function apply_field_exchange!(plan::ExecutionPlan,
        field::EvolvingFieldState, exchange::FieldExchange,
        scientific::CompiledScientificState,
        runtime::FieldExchangeState, mode::FieldExchangeMode,
        target_mcs::Integer)
    sink = only(exchange.sinks)
    sink isa Uptake && sink.output !== nothing || throw(ArgumentError(
        "portable exchange requires one named Uptake output"))
    sink.normalize isa ByCellVolume || throw(ArgumentError(
        "portable exchange requires ByCellVolume normalization"))
    exchange.calibration isa MaximumCalibration || throw(ArgumentError(
        "portable exchange requires MaximumCalibration"))
    T = eltype(field.values)
    T <: AbstractFloat &&
        eltype(runtime.workspace.raw_totals) === T ||
        throw(ArgumentError(
            "portable exchange requires matching floating field and reduction storage"))
    execution = scientific_execution(scientific)
    signal = getproperty(execution.core.properties, sink.output)
    _portable_exchange_arrays_match(
        plan, field, runtime, execution, signal) || throw(ArgumentError(
        "portable exchange storage has a backend or element-type mismatch"))
    size(field.values) == size(execution.core.ownership.tags) ||
        throw(ArgumentError(
            "portable exchange field and ownership shapes differ"))
    length(runtime.workspace.raw_totals) ==
        length(execution.core.active) || throw(ArgumentError(
            "portable exchange cell workspace capacity differs"))
    scope_type = _portable_scope_type(sink.scope)
    site_count = length(field.values)
    cell_count = length(execution.core.active)

    clear = _execution_kernel(plan, _exchange_device_clear_status!, 1)
    launch!(plan, clear,
        runtime.workspace.status, runtime.workspace.failing_index;
        ndrange = 1)
    mode === InactiveExchange && return false

    init_cells = _execution_kernel(
        plan, _exchange_device_initialize_cells!, cell_count)
    launch!(plan, init_cells,
        runtime.workspace.raw_totals,
        runtime.workspace.candidate_signal, signal;
        ndrange = cell_count)
    if mode === ResetExchange
        reset = _execution_kernel(
            plan, _exchange_device_reset_signal!, cell_count)
        launch!(plan, reset,
            runtime.workspace.candidate_signal,
            execution.core.active, execution.core.cell_types, scope_type;
            ndrange = cell_count)
        commit_signal = _execution_kernel(
            plan, _exchange_device_commit_signal!, cell_count)
        launch!(plan, commit_signal,
            signal, runtime.workspace.candidate_signal,
            runtime.workspace.status; ndrange = cell_count)
        commit_epoch = _execution_kernel(
            plan, _exchange_device_commit_epoch!, 1)
        launch!(plan, commit_epoch,
            runtime.publication_epoch, field.publication_epoch,
            runtime.workspace.status; ndrange = 1)
        return true
    end

    mode in (CalibrateExchange, PublishExchange) || throw(ArgumentError(
        "unsupported portable field-exchange mode"))
    init_sites = _execution_kernel(
        plan, _exchange_device_initialize_sites!, site_count)
    launch!(plan, init_sites,
        field.workspace.first, field.workspace.second, field.values;
        ndrange = site_count)
    reduction_width = _portable_reduction_width(plan)
    reduction_width_value = Val(reduction_width)
    reduce_cells = _fixed_execution_kernel(
        plan, _exchange_device_reduce_cells!)
    launch!(plan, reduce_cells,
        field.workspace.first, field.workspace.second,
        runtime.workspace.raw_totals,
        field.values, execution.core.ownership.tags,
        execution.core.ownership.ids, execution.core.active,
        execution.core.cell_types, execution.trackers.finite_volumes,
        scope_type, T(sink.maximum), T(sink.relative_rate),
        runtime.workspace.status, runtime.workspace.failing_index,
        reduction_width_value;
        ndrange = cell_count * reduction_width,
        workgroupsize = reduction_width)
    if mode === CalibrateExchange
        calibrate = _fixed_execution_kernel(
            plan, _exchange_device_calibrate_maximum!)
        launch!(plan, calibrate,
            runtime.value, runtime.initialized,
            runtime.workspace.raw_totals, execution.core.active,
            execution.core.cell_types, scope_type,
            T(exchange.calibration.numerator),
            runtime.workspace.status, runtime.workspace.failing_index,
            reduction_width_value;
            ndrange = reduction_width,
            workgroupsize = reduction_width)
    else
        publish = _execution_kernel(
            plan, _exchange_device_publish_signal!, cell_count)
        launch!(plan, publish,
            runtime.workspace.candidate_signal,
            runtime.workspace.raw_totals,
            runtime.value, runtime.initialized,
            execution.core.active, execution.core.cell_types,
            scope_type, runtime.workspace.status,
            runtime.workspace.failing_index;
            ndrange = cell_count)
    end
    commit_field = _execution_kernel(
        plan, _exchange_device_commit_field!, site_count)
    launch!(plan, commit_field,
        field.values, field.workspace.first,
        runtime.workspace.status; ndrange = site_count)
    if mode === PublishExchange
        commit_signal = _execution_kernel(
            plan, _exchange_device_commit_signal!, cell_count)
        launch!(plan, commit_signal,
            signal, runtime.workspace.candidate_signal,
            runtime.workspace.status; ndrange = cell_count)
    end
    commit_epoch = _execution_kernel(
        plan, _exchange_device_commit_epoch!, 1)
    launch!(plan, commit_epoch,
        runtime.publication_epoch, field.publication_epoch,
        runtime.workspace.status; ndrange = 1)
    return true
end

function synchronize_field_exchange_status!(
        plan::ExecutionPlan, runtime::FieldExchangeState)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, runtime.workspace.status))
    status == UInt32(ExchangeSucceeded) && return runtime
    failing = only(Adapt.adapt(Array, runtime.workspace.failing_index))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(FieldExchangeFailure(
        FieldExchangeFailureCode(status), failing))
end

@inline function _record_field_device_failure!(
        status, failing_index, index)
    Atomix.@atomic max(status[1], UInt32(1))
    Atomix.@atomic min(failing_index[1], UInt32(index))
    return nothing
end

@kernel function _field_device_clear_status!(status, failing_index)
    index = @index(Global, Linear)
    @inbounds if index == 1
        status[1] = UInt32(0)
        failing_index[1] = typemax(UInt32)
    end
end

@kernel function _periodic_field_device_substep!(
        output, input, forcing, owner_tags,
        law, spacing, dt, reset_medium, reset_value,
        status, failing_index)
    site = @index(Global, Linear)
    rows = size(input, 1)
    row = mod(site - 1, rows) + 1
    column = div(site - 1, rows) + 1
    candidate = _periodic_reaction_diffusion_value(
        input, forcing, law, spacing, dt, row, column)
    if reset_medium && @inbounds(owner_tags[site] == _MEDIUM_OWNER_TAG)
        candidate = reset_value
    end
    if isfinite(candidate)
        @inbounds output[site] = candidate
    else
        _record_field_device_failure!(
            status, failing_index, site)
    end
end

@kernel function _field_device_commit!(
        values, candidate, status)
    site = @index(Global, Linear)
    @inbounds status[1] == UInt32(0) &&
        (values[site] = candidate[site])
end

@kernel function _field_device_commit_epoch!(epoch, status)
    index = @index(Global, Linear)
    @inbounds if index == 1 && status[1] == UInt32(0)
        epoch[1] += UInt64(1)
    end
end

function _portable_field_constraint(
        constraints::Tuple, ::Type{T}) where {T}
    isempty(constraints) && return (false, zero(T))
    length(constraints) == 1 || throw(ArgumentError(
        "portable field advance currently admits one post-substep constraint"))
    constraint = only(constraints)
    constraint isa ConstantConcentration &&
        constraint.scope === :medium || throw(ArgumentError(
        "portable field advance requires a :medium ConstantConcentration"))
    return (true, convert(T, constraint.value))
end

function _portable_field_arrays_match(plan, state, ownership)
    arrays = (
        state.values, state.forcing,
        state.workspace.first, state.workspace.second,
        state.workspace.status, state.workspace.failing_index,
        state.publication_epoch, ownership.tags, ownership.ids)
    all(array -> isbitstype(eltype(array)), arrays) || return false
    return all(array -> isequal(
        KernelAbstractions.get_backend(array), plan.backend), arrays)
end

"""
Launch a descriptor-free periodic fixed-step field advance with conditional publication.

The host semantic time and diagnostics are finalized only by
`synchronize_field_advance_status!` at the stable boundary.
"""
function advance_field!(plan::ExecutionPlan,
        state::EvolvingFieldState, dynamics::FieldDynamics,
        interval, ownership::CompiledOwnership)
    dynamics.field === state.name || throw(ArgumentError(
        "portable field dynamics targets a different field"))
    state.values isa AbstractMatrix || throw(ArgumentError(
        "portable field advance currently requires a logical matrix"))
    state.boundary isa PeriodicFieldBoundary || throw(ArgumentError(
        "portable field advance currently requires periodic boundaries"))
    law = dynamics.law
    law isa ReactionDiffusion && law.reaction === nothing ||
        throw(ArgumentError(
            "portable field advance requires reaction-free ReactionDiffusion"))
    eltype(state.values) <: AbstractFloat || throw(ArgumentError(
        "portable field advance requires floating field storage"))
    count, dt = _materialize_substeps(dynamics.method, interval)
    _validate_transient_field_profile(state, law, count, dt)
    size(state.values) == size(ownership.tags) ||
        throw(ArgumentError(
            "portable field and ownership shapes differ"))
    _portable_field_arrays_match(plan, state, ownership) ||
        throw(ArgumentError(
            "portable field storage has a backend mismatch"))
    reset_medium, reset_value = _portable_field_constraint(
        dynamics.post_substep, eltype(state.values))
    site_count = length(state.values)
    clear = _execution_kernel(
        plan, _field_device_clear_status!, 1)
    launch!(plan, clear,
        state.workspace.status, state.workspace.failing_index;
        ndrange = 1)
    input = state.values
    output = state.workspace.first
    for step in 1:count
        substep = _execution_kernel(
            plan, _periodic_field_device_substep!, site_count)
        launch!(plan, substep,
            output, input, state.forcing, ownership.tags,
            law, state.spacing, dt, reset_medium, reset_value,
            state.workspace.status, state.workspace.failing_index;
            ndrange = site_count)
        input = output
        output = isodd(step) ?
            state.workspace.second : state.workspace.first
    end
    commit = _execution_kernel(
        plan, _field_device_commit!, site_count)
    launch!(plan, commit,
        state.values, input, state.workspace.status;
        ndrange = site_count)
    epoch = _execution_kernel(
        plan, _field_device_commit_epoch!, 1)
    launch!(plan, epoch,
        state.publication_epoch, state.workspace.status;
        ndrange = 1)
    return state
end

function synchronize_field_advance_status!(
        plan::ExecutionPlan, state::EvolvingFieldState,
        dynamics::FieldDynamics, interval)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, state.workspace.status))
    if !iszero(status)
        failing = only(Adapt.adapt(Array, state.workspace.failing_index))
        failing == typemax(UInt32) && (failing = UInt32(0))
        throw(ArgumentError(
            "portable field advance failed at canonical index $failing"))
    end
    count, dt = _materialize_substeps(dynamics.method, interval)
    state.time += interval
    state.diagnostics = FieldAdvanceDiagnostics(
        count, dt, state.time, zero(dt), zero(dt), 0, true, :transient)
    return state
end

function apply_field_exchange!(field::EvolvingFieldState,
        exchange::FieldExchange, ownership::LogicalPottsState)
    size(field.values) == lattice_size(ownership) || throw(ArgumentError(
        "initial field-exchange reference requires field and Potts lattice alignment"))
    forcing = zeros(eltype(field.values), size(field.values))
    owners = lattice_storage(ownership)
    for source in exchange.sources
        source isa ConstantConcentration || throw(ArgumentError(
            "unsupported field source in stable CPU reference"))
        for index in eachindex(owners)
            _scope_matches(source.scope, owners[index], ownership) || continue
            @inbounds forcing[index] += source.value - field.values[index]
        end
    end
    for sink in exchange.sinks
        sink isa Uptake || throw(ArgumentError(
            "unsupported field sink in stable CPU reference"))
        for index in eachindex(owners)
            _scope_matches(sink.scope, owners[index], ownership) || continue
            available = max(zero(eltype(field.values)), @inbounds field.values[index])
            removal = min(sink.maximum, sink.relative_rate * available)
            @inbounds forcing[index] -= removal
        end
    end
    copyto!(field.forcing, forcing)
    return field
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, exchange::FieldExchange, target_mcs, stage, interval)
    source = _state_by_name(snapshot.fields, exchange.field)
    target = _state_by_name(candidate.fields, exchange.field)
    _publish_state!(target, source)
    apply_field_exchange!(target, exchange, potts_snapshot)
    return nothing
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::FieldExchange, target_mcs, stage,
        schedule::PlanModeSchedule)
    output = execute_field_exchange!(
        candidate, snapshot, potts_candidate, potts_snapshot,
        process, schedule, target_mcs)
    return (output,)
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::AffineCellAdvance, target_mcs, stage, interval)
    return execute_affine_cell_process!(
        candidate, snapshot, potts_candidate, process)
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::FieldDynamics,
        target_mcs, stage, interval)
    field = _state_by_name(
        integrator.state.fields, process.field)
    amount = _field_interval_amount(process, interval)
    ownership = scientific_execution(
        integrator.potts.state).core.ownership
    advance_field!(
        integrator.potts.plan, field, process,
        amount, ownership)
    synchronize_field_advance_status!(
        integrator.potts.plan, field, process, amount)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::FieldExchange,
        target_mcs, stage,
        schedule::PlanModeSchedule)
    process.calibration isa MaximumCalibration ||
        throw(ArgumentError(
            "portable scheduled exchange requires MaximumCalibration"))
    field = _state_by_name(
        integrator.state.fields, process.field)
    runtime = _state_by_name(
        integrator.state.globals,
        process.calibration.state)
    runtime isa FieldExchangeState || throw(ArgumentError(
        "portable scheduled exchange runtime is not realized"))
    apply_field_exchange!(
        integrator.potts.plan, field, process,
        integrator.potts.state, runtime,
        mode_at(schedule, target_mcs), target_mcs)
    synchronize_field_exchange_status!(
        integrator.potts.plan, runtime)
    return ()
end

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::AffineCellAdvance,
        target_mcs, stage, interval)
    runtime = _state_by_name(
        integrator.state.globals, process.name)
    runtime isa AffineCellRuntime || throw(ArgumentError(
        "portable affine-cell runtime is not realized"))
    apply_affine_cell_advance!(
        integrator.potts.plan, integrator.potts.state,
        process, runtime.workspace)
    synchronize_affine_cell_status!(
        integrator.potts.plan, runtime.workspace)
    return ()
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::CellDynamics, target_mcs, stage, interval)
    execute_cell_dynamics!(
        potts_candidate, potts_snapshot, process,
        target_mcs, interval)
    return Tuple(variable.property for variable in process.system.state)
end

struct SteadyStateAdvance{M, T, R}
    method::M
    absolute_tolerance::T
    relative_tolerance::T
    maximum_iterations::UInt32
    residual_norm::R
end

struct MaximumAbsoluteResidual end
(::MaximumAbsoluteResidual)(residual) = maximum(abs, residual)

function SteadyStateAdvance(method;
        absolute_tolerance::T,
        relative_tolerance::T,
        maximum_iterations::Integer,
        residual_norm = MaximumAbsoluteResidual()) where {T <: AbstractFloat}
    absolute_tolerance > zero(T) || throw(ArgumentError(
        "steady-state absolute tolerance must be positive"))
    relative_tolerance >= zero(T) || throw(ArgumentError(
        "steady-state relative tolerance must be non-negative"))
    maximum_iterations > 0 || throw(ArgumentError(
        "steady-state iteration bound must be positive"))
    return SteadyStateAdvance(method, absolute_tolerance,
        relative_tolerance, UInt32(maximum_iterations), residual_norm)
end

function _field_residual(candidate, state, law)
    laplacian = _field_laplacian(
        candidate, state.boundary, state.spacing)
    reaction = law.reaction === nothing ? zero.(candidate) :
        map(law.reaction, candidate)
    return law.diffusion .* laplacian .-
        law.decay .* candidate .+ reaction .+ state.forcing
end

function _steady_jacobi_step(candidate, state, law)
    dimension = ndims(candidate)
    coefficient = law.diffusion / (state.spacing * state.spacing)
    diagonal = 2dimension * coefficient + law.decay
    diagonal > zero(diagonal) || throw(ArgumentError(
        "steady-state reaction-diffusion operator is singular without decay"))
    next = similar(candidate)
    for index in CartesianIndices(candidate)
        neighbors = zero(eltype(candidate))
        for axis in 1:dimension
            neighbors += _field_neighbor(
                candidate, index, axis, -1, state.boundary)
            neighbors += _field_neighbor(
                candidate, index, axis, 1, state.boundary)
        end
        reaction = law.reaction === nothing ? zero(eltype(candidate)) :
            law.reaction(@inbounds candidate[index])
        @inbounds next[index] = (
            coefficient * neighbors + reaction + state.forcing[index]) /
            diagonal
    end
    return next
end

function _advance_field_method!(state::EvolvingFieldState,
        dynamics::FieldDynamics, interval, method::SteadyStateAdvance,
        ownership)
    isempty(dynamics.post_substep) || throw(ArgumentError(
        "steady-state field advance does not support post-substep constraints"))
    law = dynamics.law
    law isa ReactionDiffusion || throw(ArgumentError(
        "stable steady-state field reference requires ReactionDiffusion"))
    method.method === :jacobi || throw(ArgumentError(
        "stable steady-state field reference supports only :jacobi"))
    candidate = copy(state.values)
    initial_norm = method.residual_norm(
        _field_residual(candidate, state, law))
    isfinite(initial_norm) || throw(ArgumentError(
        "steady-state initial residual is nonfinite"))
    threshold = method.absolute_tolerance +
        method.relative_tolerance * initial_norm
    residual = initial_norm
    iterations = 0
    while residual > threshold &&
            iterations < Int(method.maximum_iterations)
        candidate = _steady_jacobi_step(candidate, state, law)
        all(isfinite, candidate) || throw(ArgumentError(
            "steady-state field iteration produced nonfinite values"))
        residual = method.residual_norm(
            _field_residual(candidate, state, law))
        isfinite(residual) || throw(ArgumentError(
            "steady-state field residual is nonfinite"))
        iterations += 1
    end
    residual <= threshold || throw(ArgumentError(
        "steady-state field solver exceeded its iteration bound"))
    copyto!(state.values, candidate)
    state.time += interval
    state.publication_epoch[1] += UInt64(1)
    state.diagnostics = FieldAdvanceDiagnostics(
        0, zero(state.time), state.time, residual, threshold,
        iterations, true, :steady_state)
    return state
end
