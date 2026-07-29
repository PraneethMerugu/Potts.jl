struct _ActivityParameterization{M,H}
    model::M
    hamiltonian::H
end

function _with_activity_hamiltonian(
        components::ScientificComponentSet,
        hamiltonian::ActivityHamiltonian)
    existing = filter(component -> component isa ActivityHamiltonian,
        components.energies)
    if isempty(existing)
        return ScientificComponentSet(
            energies=(components.energies..., hamiltonian),
            drives=components.drives,
            constraints=components.constraints,
            kinetic_modifiers=components.kinetic_modifiers,
            mechanics=components.mechanics,
        )
    end
    length(existing) == 1 &&
        component_semantic_data(only(existing)) ==
            component_semantic_data(hamiltonian) ||
        throw(ArgumentError(
            "the Potts model contains an incompatible activity Hamiltonian"))
    return components
end

function (parameterization::_ActivityParameterization)(parameters)
    components = realize_components(parameterization.model, parameters)
    components isa ScientificComponentSet ||
        throw(ArgumentError(
            "activity base model must realize ScientificComponentSet"))
    return _with_activity_hamiltonian(
        components, parameterization.hamiltonian)
end

function _activity_augmented_problem(
        problem::PottsProblem,
        program::ActivityProgram)
    problem.model isa PottsModel || throw(ArgumentError(
        "ActivityPottsProblem currently requires a CorePotts.PottsModel"))
    problem.tspan[1] == 0 || throw(ArgumentError(
        "ActivityPottsProblem initialization must begin at MCS zero; " *
        "resume later boundaries with restore_checkpoint"))
    parameterization =
        _ActivityParameterization(problem.model, program.hamiltonian)
    parameterization(problem.p)
    model = PottsModel(
        proposal_relation(problem.model),
        boundary_tracker(problem.model);
        parameters=problem.p,
        parameterization,
        moment_tracker=moment_tracker(problem.model),
        lifecycle_events=lifecycle_events(problem.model),
        lifecycle_resolver=lifecycle_resolver(problem.model),
        observables=observable_symbols(problem.model),
    )
    return PottsProblem(
        model,
        problem.u0,
        problem.geometry,
        problem.tspan;
        p=problem.p,
        capacity=problem.capacity,
        seed=problem.seed,
    )
end

"""
    ActivityPottsProblem(problem, program)

Create the supported SciML problem for an [`ActivityProgram`](@ref) beside an
ordinary [`PottsProblem`](@ref). The façade adds the program's Act Hamiltonian
exactly once, validates semantic compatibility, and keeps coupled execution
plans and workspaces out of the user API.

Initialize with `SciMLBase.init`, advance with `SciMLBase.step!`, inspect with
[`logical_state`](@ref), [`site_property_value`](@ref),
[`current_mcs_report`](@ref), and
`ProcessBigraphs.observation_records`, and persist with
[`capture_checkpoint`](@ref) and [`restore_checkpoint`](@ref).
"""
struct ActivityPottsProblem{P<:PottsProblem,A<:ActivityProgram} <:
       AbstractPottsProblem
    potts_problem::P
    program::A
    function ActivityPottsProblem(
            potts_problem::P,
            program::A,
            ::Val{:validated}) where {P<:PottsProblem,A<:ActivityProgram}
        return new{P,A}(potts_problem, program)
    end
end

function ActivityPottsProblem(
        problem::PottsProblem,
        program::ActivityProgram)
    augmented = _activity_augmented_problem(problem, program)
    return ActivityPottsProblem(
        augmented, program, Val(:validated))
end

mutable struct ActivityPottsIntegrator{B,C,P,A}
    base::B
    coupled::C
    problem::P
    algorithm::A
end

Base.propertynames(::ActivityPottsIntegrator, private::Bool=false) = ()
function Base.getproperty(
        ::ActivityPottsIntegrator,
        name::Symbol)
    throw(ArgumentError(
        "ActivityPottsIntegrator representation is private; " *
        "use logical_state, site_property_value, current_mcs_report, " *
        "ProcessBigraphs.observation_records, capture_checkpoint, or restore_checkpoint " *
        "instead of accessing `$name`"))
end

_activity_algorithm(problem::ActivityPottsProblem) =
    problem.program.semantic_model.algorithm

function _validate_activity_algorithm(problem, algorithm)
    expected = _activity_algorithm(problem)
    typeof(algorithm) === typeof(expected) &&
        component_semantic_data(algorithm) ==
            component_semantic_data(expected) ||
        throw(ArgumentError(
            "activity algorithm must match the algorithm frozen in ActivityProgram"))
    return algorithm
end

function SciMLBase.init(
        problem::ActivityPottsProblem,
        algorithm::AbstractPottsAlgorithm,
        args...;
        kwargs...)
    _validate_activity_algorithm(problem, algorithm)
    source = problem.potts_problem.u0
    runtime = if source isa LogicalPottsState
        realize_activity(problem.program, lattice_storage(source))
    elseif source isa InitializedLogicalState
        realize_activity(
            problem.program, lattice_storage(logical_state(source)))
    elseif source isa CompiledScientificState
        realize_activity(problem.program, source)
    elseif source isa DeviceInitialState
        realize_activity(problem.program, source.state)
    else
        throw(ArgumentError(
            "unsupported activity initial-state source $(typeof(source))"))
    end
    base = _init_potts(
        problem.potts_problem,
        algorithm,
        args...;
        algorithm_workspace=runtime.workspace,
        kwargs...,
    )
    coupled = init_coupled(
        base.inner,
        runtime.plan,
        runtime.coupled_state;
        lifecycle=base.inner.lifecycle,
        semantic_model=problem.program.semantic_model,
    )
    return ActivityPottsIntegrator(
        base, coupled, problem, algorithm)
end

SciMLBase.init(
    problem::ActivityPottsProblem,
    args...;
    kwargs...,
) = SciMLBase.init(
    problem, _activity_algorithm(problem), args...; kwargs...)

function _activity_can_step(integrator::ActivityPottsIntegrator)
    coupled = getfield(integrator, :coupled)
    endpoint =
        getfield(getfield(integrator, :problem), :potts_problem).tspan[2]
    Int(getfield(coupled, :mcs)) < endpoint || throw(
        IntegratorTerminatedError(
            Int(getfield(coupled, :mcs)),
            SciMLBase.ReturnCode.Success,
        ))
    return coupled
end

function SciMLBase.step!(integrator::ActivityPottsIntegrator)
    coupled = _activity_can_step(integrator)
    SciMLBase.step!(coupled)
    base = getfield(integrator, :base)
    base.t = Int(getfield(coupled, :mcs))
    base.steps += 1
    if base.t >= base.prob.tspan[2]
        base.status = PottsSucceeded
        base.retcode = SciMLBase.ReturnCode.Success
    end
    return integrator
end

function SciMLBase.step!(
        integrator::ActivityPottsIntegrator,
        steps::Integer)
    steps >= 0 ||
        throw(ArgumentError("activity step count must be non-negative"))
    for _ in 1:steps
        SciMLBase.step!(integrator)
    end
    return integrator
end

logical_state(integrator::ActivityPottsIntegrator) =
    logical_state(getfield(getfield(integrator, :coupled), :potts))

current_mcs_report(integrator::ActivityPottsIntegrator) =
    current_mcs_report(getfield(getfield(integrator, :coupled), :potts))

"""
    site_property_value(integrator, site)

Return the activity value at one linear lattice site from a supported
`ActivityPottsProblem` integrator. This accessor performs bounds checking and
does not expose the coupled site-property storage.
"""
function site_property_value(
        integrator::ActivityPottsIntegrator,
        site::Integer)
    state = _state_by_name(
        getfield(getfield(integrator, :coupled), :state).site_states,
        :activity,
    )
    return site_property_value(state, site)
end

function ProcessBigraphs.observation_records(
        integrator::ActivityPottsIntegrator)
    records =
        getfield(getfield(integrator, :coupled), :observations).records
    return tuple(deepcopy(records)...)
end

struct _ActivityPottsCheckpoint{C,R}
    coupled::C
    records::R
end

function capture_checkpoint(
        integrator::ActivityPottsIntegrator;
        kwargs...)
    return _ActivityPottsCheckpoint(
        capture_checkpoint(getfield(integrator, :coupled); kwargs...),
        ProcessBigraphs.observation_records(integrator),
    )
end

function restore_checkpoint(
        checkpoint::_ActivityPottsCheckpoint,
        prototype::ActivityPottsIntegrator;
        adaptor=Array)
    restored = restore_checkpoint(
        checkpoint.coupled, getfield(prototype, :coupled); adaptor)
    append!(restored.observations.records, deepcopy(checkpoint.records))
    base = deepcopy(getfield(prototype, :base))
    base.inner = restored.potts
    base.t = Int(restored.mcs)
    base.status =
        base.t >= base.prob.tspan[2] ? PottsSucceeded : PottsRunning
    base.retcode =
        base.status === PottsSucceeded ?
            SciMLBase.ReturnCode.Success :
            SciMLBase.ReturnCode.Default
    return ActivityPottsIntegrator(
        base,
        restored,
        getfield(prototype, :problem),
        getfield(prototype, :algorithm),
    )
end

function Base.show(io::IO, integrator::ActivityPottsIntegrator)
    print(io,
        "ActivityPottsIntegrator(mcs=",
        getfield(getfield(integrator, :coupled), :mcs),
        ", algorithm=",
        nameof(typeof(getfield(integrator, :algorithm))),
        ")",
    )
end
