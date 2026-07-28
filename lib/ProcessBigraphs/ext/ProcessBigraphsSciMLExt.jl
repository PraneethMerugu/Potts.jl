module ProcessBigraphsSciMLExt

import CommonSolve
import ProcessBigraphs
import SciMLBase

const CONTRACT_VERSION = "process-bigraphs-sciml-extension-v2"
const CHECKPOINT_VERSION = "sciml-periodic-field-checkpoint-v2"
const QUALIFIED_SOLVER_OPTION_KEYS = (
    :abstol,
    :reltol,
    :adaptive,
    :dt,
    :dtmin,
    :dtmax,
    :maxiters,
)

function _normalized_solver_options(options::NamedTuple)
    supplied = Set(keys(options))
    allowed = Set(QUALIFIED_SOLVER_OPTION_KEYS)
    supplied <= allowed ||
        throw(ArgumentError(
            "unsupported SciML solver options: " *
            join(sort!(String.(collect(setdiff(supplied, allowed)))), ", ")))
    (:abstol in supplied && :reltol in supplied) ||
        throw(ArgumentError(
            "qualified SciML declarations require explicit abstol and reltol"))
    for key in (:abstol, :reltol)
        value = getproperty(options, key)
        value isa Real && isfinite(value) && value > zero(value) ||
            throw(ArgumentError("$(key) must be finite and positive"))
    end
    for key in (:dt, :dtmin, :dtmax)
        key in supplied || continue
        value = getproperty(options, key)
        value isa Real && isfinite(value) && value > zero(value) ||
            throw(ArgumentError("$(key) must be finite and positive"))
    end
    if :adaptive in supplied
        getproperty(options, :adaptive) isa Bool ||
            throw(ArgumentError("adaptive must be Bool"))
    end
    if :maxiters in supplied
        value = getproperty(options, :maxiters)
        value isa Integer && 0 < value <= typemax(Int) ||
            throw(ArgumentError("maxiters must fit positive Int"))
    end
    ordered = Pair{Symbol,Any}[]
    for key in QUALIFIED_SOLVER_OPTION_KEYS
        key in supplied &&
            push!(ordered, key => getproperty(options, key))
    end
    normalized = (;
        ordered...,
        save_everystep=false,
        save_start=false,
        save_end=false,
        dense=false,
    )
    ProcessBigraphs.encode_logical_value(normalized)
    normalized
end

function _algorithm_package_identity(algorithm)
    algorithm_module = parentmodule(typeof(algorithm))
    root_module = Base.moduleroot(algorithm_module)
    package_id = Base.PkgId(root_module)
    version = Base.pkgversion(root_module)
    (
        package=String(package_id.name),
        package_uuid=string(package_id.uuid),
        package_version=isnothing(version) ? "unversioned" : string(version),
        algorithm_type=string(typeof(algorithm)),
    )
end

struct SciMLFieldAdapter{
        P<:ProcessBigraphs.BoundedCartesianFieldProblem,A,O<:NamedTuple} <:
        ProcessBigraphs.AbstractEngineAdapter
    problem::P
    algorithm::A
    algorithm_id::String
    algorithm_package::String
    algorithm_package_uuid::String
    algorithm_package_version::String
    algorithm_type::String
    solver_options::O
end

function ProcessBigraphs.sciml_field_adapter(
    problem::ProcessBigraphs.BoundedCartesianFieldProblem,
    algorithm;
    algorithm_id::AbstractString,
    solver_options::NamedTuple,
)
    isempty(algorithm_id) &&
        throw(ArgumentError("SciML algorithm identity cannot be empty"))
    package = _algorithm_package_identity(algorithm)
    options = _normalized_solver_options(solver_options)
    SciMLFieldAdapter(
        problem,
        algorithm,
        String(algorithm_id),
        package.package,
        package.package_uuid,
        package.package_version,
        package.algorithm_type,
        options,
    )
end

ProcessBigraphs.engine_semantic_version(::SciMLFieldAdapter) = "2.0.0"
ProcessBigraphs.engine_semantic_parameters(adapter::SciMLFieldAdapter) = (
    contract_version=CONTRACT_VERSION,
    problem_fingerprint=adapter.problem.fingerprint,
    problem_type="SciMLBase.ODEProblem",
    algorithm_id=adapter.algorithm_id,
    algorithm_package=adapter.algorithm_package,
    algorithm_package_uuid=adapter.algorithm_package_uuid,
    algorithm_package_version=adapter.algorithm_package_version,
    algorithm_type=adapter.algorithm_type,
    solver_options=adapter.solver_options,
    exact_target_policy="CommonSolve.step!(integrator, duration, true)",
    continuation_policy="reconstruct_each_invocation",
    replay_class=:numerical,
)

function ProcessBigraphs.sciml_field_declaration(
    problem::ProcessBigraphs.BoundedCartesianFieldProblem,
    algorithm;
    algorithm_id::AbstractString,
    solver_options::NamedTuple,
)
    adapter = ProcessBigraphs.sciml_field_adapter(
        problem,
        algorithm;
        algorithm_id,
        solver_options,
    )
    precision = eltype(problem.initial_values) === Float32 ?
        :float32 : :float64
    ProcessBigraphs.EngineDeclaration(
        problem.id,
        adapter;
        capabilities=ProcessBigraphs.EngineCapabilities(
            operation_families=(:interval_advance,),
            problem_envelopes=(
                "sciml-odeproblem-periodic-cartesian-diffusion-decay",),
            backends=(:cpu,),
            precisions=(precision,),
            residencies=(:host,),
            input_modes=(:frozen,),
            boundary_kinds=(:periodic,),
            continuation_actions=(:reconstruct, :reject),
            replay_class=:numerical,
            cancellation=false,
            diagnostics=true,
            resize=false,
            bridges=(),
        ),
    )
end

mutable struct SciMLFieldInstance{
        D<:ProcessBigraphs.EngineDeclaration,A<:Array} <:
        ProcessBigraphs.AbstractEngineInstance
    declaration::D
    published::A
    forcing::A
    prior_forcing::Union{Nothing,A}
    candidate::A
    time_tick::Int64
    target_tick::Int64
    publication_epoch::UInt64
    active_invocation::Union{Nothing,String}
    last_retcode::String
end

function _sciml_instance(
    declaration::ProcessBigraphs.EngineDeclaration{<:SciMLFieldAdapter},
    values,
    forcing,
    time_tick::Integer,
    publication_epoch::Integer,
)
    problem = declaration.adapter.problem
    published = Array(values)
    normalized_forcing = Array(forcing)
    size(published) == size(problem.initial_values) &&
        eltype(published) == eltype(problem.initial_values) ||
        throw(ArgumentError("SciML field checkpoint state is incompatible"))
    size(normalized_forcing) == size(published) &&
        eltype(normalized_forcing) == eltype(published) ||
        throw(ArgumentError("SciML field checkpoint forcing is incompatible"))
    SciMLFieldInstance(
        declaration,
        published,
        normalized_forcing,
        nothing,
        published,
        Int64(time_tick),
        Int64(time_tick),
        UInt64(publication_epoch),
        nothing,
        "uninitialized",
    )
end

function ProcessBigraphs.prepare_engine(
    adapter::SciMLFieldAdapter,
    declaration::ProcessBigraphs.EngineDeclaration,
)
    declaration.adapter === adapter ||
        throw(ArgumentError("SciML declaration and adapter disagree"))
    _sciml_instance(
        declaration,
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
    retcode::String
end

@inline function _periodic_laplacian(
    input,
    index::CartesianIndex{N},
    spacing::NTuple{N},
) where {N}
    coordinates = Tuple(index)
    center = @inbounds input[index]
    laplacian = zero(center)
    for axis in 1:N
        low = Base.setindex(
            coordinates,
            mod1(coordinates[axis] - 1, size(input, axis)),
            axis,
        )
        high = Base.setindex(
            coordinates,
            mod1(coordinates[axis] + 1, size(input, axis)),
            axis,
        )
        @inbounds laplacian += (
            input[low...] + input[high...] - 2center
        ) / (spacing[axis] * spacing[axis])
    end
    laplacian
end

function _field_rhs!(derivative, state, parameters, _)
    problem, forcing = parameters
    values = reshape(state, size(problem.initial_values))
    output = reshape(derivative, size(problem.initial_values))
    for index in CartesianIndices(values)
        @inbounds center = values[index]
        @inbounds output[index] =
            problem.diffusion *
                _periodic_laplacian(values, index, problem.spacing) +
            forcing[index] -
            problem.decay * center
    end
    nothing
end

function _forcing(instance::SciMLFieldInstance, invocation)
    length(invocation.inputs) == 1 &&
        only(invocation.inputs).name === :forcing ||
        throw(ArgumentError(
            "SciML field advance requires one forcing projection"))
    forcing = ProcessBigraphs.projection_value(only(invocation.inputs))
    forcing isa AbstractArray &&
        size(forcing) == size(instance.forcing) &&
        eltype(forcing) == eltype(instance.forcing) ||
        throw(ArgumentError(
            "SciML field forcing has incompatible shape or precision"))
    forcing
end

function _authorize_resources(instance::SciMLFieldInstance, invocation)
    precision = eltype(instance.published) === Float32 ?
        :float32 : :float64
    expected = (backend=:cpu, precision, residency=:host)
    all(key -> haskey(invocation.resource_authorization, key) &&
        getproperty(invocation.resource_authorization, key) ==
            getproperty(expected, key), keys(expected)) ||
        throw(ArgumentError(
            "SciML field requires explicit CPU/precision/host authorization"))
    nothing
end

function ProcessBigraphs.stage_operation!(
    instance::SciMLFieldInstance,
    invocation::ProcessBigraphs.EngineInvocation,
)
    operation = invocation.operation
    operation isa ProcessBigraphs.IntervalAdvance ||
        throw(ArgumentError("SciML field supports only interval advance"))
    isnothing(instance.active_invocation) ||
        throw(ArgumentError("SciML field already has an active candidate"))
    problem = instance.declaration.adapter.problem
    operation.start_time == ProcessBigraphs.LogicalTime(
        instance.time_tick, problem.time_scale) ||
        throw(ArgumentError(
            "SciML field and ProcessBigraphs clocks disagree"))
    _authorize_resources(instance, invocation)
    forcing = _forcing(instance, invocation)
    instance.prior_forcing = copy(instance.forcing)
    copyto!(instance.forcing, forcing)
    ticks = operation.target_time.tick - operation.start_time.tick
    duration = convert(eltype(instance.published), ticks) *
        problem.tick_duration
    ode_problem = SciMLBase.ODEProblem(
        _field_rhs!,
        vec(copy(instance.published)),
        (zero(duration), duration),
        (problem, copy(instance.forcing)),
    )
    adapter = instance.declaration.adapter
    try
        integrator = CommonSolve.init(
            ode_problem,
            adapter.algorithm;
            adapter.solver_options...,
        )
        CommonSolve.step!(integrator, duration, true)
        integrator.t == duration ||
            throw(ArgumentError(
                "SciML solver failed to reach the exact authorized target"))
        retcode = SciMLBase.check_error(integrator)
        SciMLBase.successful_retcode(retcode) ||
            throw(ArgumentError(
                "SciML solver failed with return code $(retcode)"))
        candidate = reshape(
            copy(integrator.u), size(instance.published))
        all(isfinite, candidate) &&
            (!problem.reject_negative ||
             all(>=(zero(eltype(candidate))), candidate)) ||
            throw(ArgumentError(
                "SciML field produced an invalid candidate"))
        instance.candidate = candidate
        instance.last_retcode = string(retcode)
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
        instance.last_retcode,
    )
    adapter = instance.declaration.adapter
    ProcessBigraphs.EngineCandidate(
        handle.target,
        token;
        effects=(:field_state => (
            target_tick=token.target_tick,
            publication_epoch=token.publication_epoch,
        ),),
        diagnostics=(
            backend=:cpu,
            algorithm=Symbol(replace(adapter.algorithm_id, '-' => '_')),
            retcode=token.retcode,
        ),
        fingerprint=ProcessBigraphs.canonical_fingerprint((
            CONTRACT_VERSION,
            instance.declaration.fingerprint,
            token.invocation_id,
            token.target_tick,
            token.publication_epoch,
            token.retcode,
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
        :numerical,
        (
            declaration_fingerprint=declaration.fingerprint,
            values=copy(instance.published),
            forcing=copy(instance.forcing),
            time_tick=instance.time_tick,
            publication_epoch=instance.publication_epoch,
            continuation_policy=:reconstruct_each_invocation,
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
    payload.continuation_policy === :reconstruct_each_invocation ||
        throw(ArgumentError(
            "unsupported SciML continuation policy"))
    _sciml_instance(
        declaration,
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
