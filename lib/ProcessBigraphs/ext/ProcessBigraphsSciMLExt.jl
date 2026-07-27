module ProcessBigraphsSciMLExt

import CommonSolve
import ProcessBigraphs
import SciMLBase

const CONTRACT_VERSION = "process-bigraphs-sciml-extension-v1"
const CHECKPOINT_VERSION = "sciml-periodic-field-checkpoint-v1"

struct P16FixedEuler
    steps::Int
    function P16FixedEuler(steps::Integer)
        steps > 0 || throw(ArgumentError(
            "SciML fixed Euler requires a positive step count"))
        new(Int(steps))
    end
end

struct P16SciMLSolution{U,T}
    u::U
    t::T
    retcode::Symbol
end

function CommonSolve.solve(
    problem::SciMLBase.ODEProblem,
    algorithm::P16FixedEuler;
    kwargs...,
)
    isempty(kwargs) ||
        throw(ArgumentError(
            "bounded SciML field solver rejects undeclared solver keywords"))
    start, target = problem.tspan
    target > start ||
        throw(ArgumentError(
            "bounded SciML field solve requires a positive interval"))
    dt = (target - start) / algorithm.steps
    state = copy(problem.u0)
    derivative = similar(state)
    time = start
    for _ in 1:algorithm.steps
        problem.f(derivative, state, problem.p, time)
        @. state = state + dt * derivative
        time += dt
    end
    P16SciMLSolution(state, target, :Success)
end

function _field_rhs!(derivative, state, parameters, time)
    problem, forcing = parameters
    values = reshape(state, size(problem.initial_values))
    output = reshape(derivative, size(problem.initial_values))
    for index in CartesianIndices(values)
        @inbounds center = values[index]
        @inbounds output[index] =
            problem.diffusion *
                ProcessBigraphs._periodic_laplacian(
                    values, index, problem.spacing) +
            forcing[index] -
            problem.decay * center
    end
    nothing
end

struct SciMLFieldAdapter{
        P<:ProcessBigraphs.BoundedCartesianFieldProblem} <:
        ProcessBigraphs.AbstractEngineAdapter
    problem::P
end

ProcessBigraphs.sciml_field_adapter(
    problem::ProcessBigraphs.BoundedCartesianFieldProblem,
) = SciMLFieldAdapter(problem)

ProcessBigraphs.engine_semantic_version(::SciMLFieldAdapter) = "1.0.0"
ProcessBigraphs.engine_semantic_parameters(adapter::SciMLFieldAdapter) = (
    contract_version=CONTRACT_VERSION,
    problem_fingerprint=adapter.problem.fingerprint,
    problem_type="SciMLBase.ODEProblem",
    algorithm="bounded-fixed-euler",
)

function ProcessBigraphs.sciml_field_declaration(
    problem::ProcessBigraphs.BoundedCartesianFieldProblem,
)
    precision = eltype(problem.initial_values) === Float32 ?
        :float32 : :float64
    ProcessBigraphs.EngineDeclaration(
        problem.id,
        SciMLFieldAdapter(problem);
        capabilities=ProcessBigraphs.EngineCapabilities(
            operation_families=(:interval_advance,),
            problem_envelopes=(
                "sciml-odeproblem-periodic-cartesian-diffusion-decay",),
            backends=(:cpu,),
            precisions=(precision,),
            residencies=(:host,),
            input_modes=(:frozen,),
            boundary_kinds=(:periodic,),
            continuation_actions=(:preserve, :reconstruct, :reject),
            replay_class=:exact,
            cancellation=false,
            diagnostics=true,
            resize=false,
            bridges=(),
        ),
    )
end

mutable struct SciMLFieldInstance{
        P<:ProcessBigraphs.BoundedCartesianFieldProblem,A<:Array} <:
        ProcessBigraphs.AbstractEngineInstance
    problem::P
    published::A
    forcing::A
    prior_forcing::Union{Nothing,A}
    candidate::A
    time_tick::Int64
    target_tick::Int64
    publication_epoch::UInt64
    active_invocation::Union{Nothing,String}
end

function _sciml_instance(
    problem::ProcessBigraphs.BoundedCartesianFieldProblem,
    values,
    forcing,
    time_tick::Integer,
    publication_epoch::Integer,
)
    published = Array(values)
    normalized_forcing = Array(forcing)
    size(published) == size(problem.initial_values) &&
        eltype(published) == eltype(problem.initial_values) ||
        throw(ArgumentError("SciML field checkpoint state is incompatible"))
    size(normalized_forcing) == size(published) &&
        eltype(normalized_forcing) == eltype(published) ||
        throw(ArgumentError("SciML field checkpoint forcing is incompatible"))
    SciMLFieldInstance(
        problem,
        published,
        normalized_forcing,
        nothing,
        published,
        Int64(time_tick),
        Int64(time_tick),
        UInt64(publication_epoch),
        nothing,
    )
end

function ProcessBigraphs.prepare_engine(
    adapter::SciMLFieldAdapter,
    declaration::ProcessBigraphs.EngineDeclaration,
)
    _sciml_instance(
        adapter.problem,
        adapter.problem.initial_values,
        zeros(eltype(adapter.problem.initial_values),
            size(adapter.problem.initial_values)),
        adapter.problem.initial_tick,
        0,
    )
end

struct SciMLCompletion <: ProcessBigraphs.AbstractCompletionHandle
    invocation_id::String
    target::ProcessBigraphs.LogicalTime
end

struct SciMLCandidate
    invocation_id::String
    target_tick::Int64
    publication_epoch::UInt64
end

function ProcessBigraphs.stage_operation!(
    instance::SciMLFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
)
    operation = invocation.operation
    operation isa ProcessBigraphs.IntervalAdvance ||
        throw(ArgumentError(
            "bounded SciML field supports only interval advance"))
    isnothing(instance.active_invocation) ||
        throw(ArgumentError(
            "bounded SciML field already has an active candidate"))
    operation.start_time == ProcessBigraphs.LogicalTime(
        instance.time_tick, instance.problem.time_scale) ||
        throw(ArgumentError(
            "SciML field and ProcessBigraphs clocks disagree"))
    ProcessBigraphs._bounded_resource_authorization(
        instance, invocation)
    forcing = ProcessBigraphs._bounded_forcing(instance, invocation)
    instance.prior_forcing = copy(instance.forcing)
    copyto!(instance.forcing, forcing)
    ProcessBigraphs._bounded_field_stability(instance.problem)
    ticks = operation.target_time.tick - operation.start_time.tick
    steps = Base.Checked.checked_mul(
        ticks, instance.problem.substeps_per_tick)
    duration = convert(eltype(instance.published), ticks) *
        instance.problem.tick_duration
    ode_problem = SciMLBase.ODEProblem(
        _field_rhs!,
        vec(copy(instance.published)),
        (zero(duration), duration),
        (instance.problem, copy(instance.forcing)),
    )
    try
        solution = CommonSolve.solve(
            ode_problem, P16FixedEuler(steps))
        solution.retcode === :Success ||
            throw(ArgumentError(
                "bounded SciML field solver did not succeed"))
        candidate = reshape(
            copy(solution.u), size(instance.published))
        all(isfinite, candidate) &&
            (!instance.problem.reject_negative ||
             all(>=(zero(eltype(candidate))), candidate)) ||
            throw(ArgumentError(
                "bounded SciML field produced an invalid candidate"))
        instance.candidate = candidate
    catch
        copyto!(instance.forcing, instance.prior_forcing)
        instance.prior_forcing = nothing
        rethrow()
    end
    instance.target_tick = operation.target_time.tick
    instance.active_invocation = invocation.id
    SciMLCompletion(invocation.id, operation.target_time)
end

function ProcessBigraphs.complete_operation!(
    instance::SciMLFieldInstance,
    handle::SciMLCompletion,
)
    instance.active_invocation == handle.invocation_id ||
        throw(ArgumentError(
            "SciML completion does not own the staged candidate"))
    token = SciMLCandidate(
        handle.invocation_id,
        instance.target_tick,
        Base.Checked.checked_add(
            instance.publication_epoch, UInt64(1)),
    )
    ProcessBigraphs.EngineCandidate(
        handle.target,
        token;
        effects=(:field_state => (
            target_tick=token.target_tick,
            publication_epoch=token.publication_epoch,
        ),),
        diagnostics=(backend=:cpu, algorithm=:sciml_fixed_euler),
        fingerprint=ProcessBigraphs.canonical_fingerprint((
            CONTRACT_VERSION,
            token.invocation_id,
            token.target_tick,
            token.publication_epoch,
        )),
    )
end

function ProcessBigraphs.publish_candidate!(
    instance::SciMLFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
    candidate::ProcessBigraphs.EngineCandidate{<:SciMLCandidate},
)
    instance.active_invocation == invocation.id &&
        candidate.payload.invocation_id == invocation.id ||
        throw(ArgumentError(
            "SciML candidate belongs to another invocation"))
    instance.published = instance.candidate
    instance.time_tick = instance.target_tick
    instance.publication_epoch =
        candidate.payload.publication_epoch
    instance.prior_forcing = nothing
    instance.active_invocation = nothing
    (
        time_tick=instance.time_tick,
        publication_epoch=instance.publication_epoch,
    )
end

function ProcessBigraphs.discard_candidate!(
    instance::SciMLFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
    candidate,
)
    if instance.active_invocation == invocation.id
        instance.candidate = instance.published
        instance.target_tick = instance.time_tick
        if !isnothing(instance.prior_forcing)
            copyto!(instance.forcing, instance.prior_forcing)
        end
        instance.prior_forcing = nothing
        instance.active_invocation = nothing
    end
    nothing
end

function ProcessBigraphs.engine_checkpoint_payload(
    instance::SciMLFieldInstance,
    declaration::ProcessBigraphs.EngineDeclaration,
)
    isnothing(instance.active_invocation) ||
        throw(ArgumentError(
            "SciML field checkpoint requires a settled boundary"))
    ProcessBigraphs.CheckpointComponent(
        declaration.id,
        CHECKPOINT_VERSION,
        :exact,
        (
            declaration_fingerprint=declaration.fingerprint,
            values=copy(instance.published),
            forcing=copy(instance.forcing),
            time_tick=instance.time_tick,
            publication_epoch=instance.publication_epoch,
        ),
    )
end

function ProcessBigraphs.restore_engine_checkpoint(
    adapter::SciMLFieldAdapter,
    declaration::ProcessBigraphs.EngineDeclaration,
    payload::NamedTuple,
)
    payload.declaration_fingerprint == declaration.fingerprint ||
        throw(ArgumentError(
            "SciML field declaration changed during restore"))
    _sciml_instance(
        adapter.problem,
        payload.values,
        payload.forcing,
        payload.time_tick,
        payload.publication_epoch,
    )
end

sciml_field_snapshot(instance::SciMLFieldInstance) =
    copy(instance.published)
ProcessBigraphs.field_engine_snapshot(instance::SciMLFieldInstance) =
    sciml_field_snapshot(instance)

end
