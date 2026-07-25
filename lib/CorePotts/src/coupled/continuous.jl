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
    amount = dynamics.clock isa ContinuousClock ?
        interval_value(dynamics.clock, interval) :
        interval isa OneMCS ? dynamics.clock.scale :
        interval isa HalfMCS ? dynamics.clock.scale / 2 :
        interval isa ContinuousInterval ? interval.value :
        dynamics.clock.scale * interval
    advance_field!(target, dynamics, amount, potts_snapshot)
    return nothing
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
