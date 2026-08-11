_topology_epoch(topology) =
    hasproperty(topology, :epoch) ? getproperty(topology, :epoch) : UInt64(0)

function _topology_identity(topology)
    return ismutabletype(typeof(topology)) ? objectid(topology) :
           hash(typeof(topology), UInt(0))
end

function _topology_fingerprint(topology, lowering)
    throw(LocalWorkValidationError(
        "the admitted lowering does not define structural topology evidence"
    ))
end

function _centrally_qualified_topology_fingerprint(topology, lowering)
    signature = Tuple{typeof(topology), typeof(lowering)}
    method = which(_topology_fingerprint, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the topology-fingerprint implementation is not centrally admitted"
    ))
    return invoke(_topology_fingerprint, signature, topology, lowering)
end

function _topology_fingerprint(topology, lowering::_SequenceLowering)
    fingerprints = map(
        stage -> invoke(
            _centrally_qualified_topology_fingerprint,
            Tuple{Any, Any},
            topology,
            stage,
        ),
        lowering.stages,
    )
    all(==(first(fingerprints)), fingerprints) ||
        throw(LocalWorkValidationError(
            "ordered stages disagree about structural topology evidence"
        ))
    return first(fingerprints)
end

function _validate_fresh_topology(
        workplan::WorkPlan; structural::Bool = true
    )
    evidence = workplan.evidence
    invoke(_topology_identity, Tuple{Any}, workplan.topology) ==
        evidence.topology_identity &&
        invoke(_topology_epoch, Tuple{Any}, workplan.topology) ==
        evidence.topology_epoch ||
        throw(LocalWorkValidationError(
            "the WorkPlan topology identity or epoch is stale"
        ))
    structural && invoke(
        _centrally_qualified_topology_fingerprint,
        Tuple{Any, Any},
        workplan.topology,
        workplan.lowering,
    ) != evidence.topology_fingerprint &&
        throw(LocalWorkValidationError(
            "the WorkPlan structural topology fingerprint is stale"
        ))
    return nothing
end

function _central_admission end

function _validate_sequence(stages, works, topology, backend)
    length(stages) == length(works) || error("invalid internal sequence")
    all(work -> work.items == first(works).items, works) ||
        throw(LocalWorkValidationError(
            "ordered stages require one compatible item domain in LW-1"
        ))
    output_names = map(work -> Tuple(keys(work.outputs)), works)
    flattened_outputs = reduce(vcat, collect.(output_names))
    length(unique(flattened_outputs)) == length(flattened_outputs) ||
        throw(LocalWorkValidationError(
            "ordered stages require unique named output ports"
        ))
    producer = Dict(
        name => stage_index for (stage_index, names) in
            enumerate(output_names) for name in names
    )
    for (stage_index, work) in enumerate(works)
        for binding in values(work.reads)
            binding isa Symbol || continue
            producer_index = get(producer, binding, 0)
            producer_index == 0 && continue
            producer_index < stage_index || throw(LocalWorkValidationError(
                "stage $stage_index reads output $binding before it is visible"
            ))
        end
    end
    return nothing
end

function _lowering_evidence end
function _required_bindings end
function _binding_access end
function _validate_binding_schema end
function _validate_workspace end
function _prepare_lowering end
function _execute_lowering! end
function _lowering_inspection end

_provider_compiler_identity(backend) = (
    julia = VERSION,
    kernelabstractions = Base.pkgversion(KernelAbstractions),
)

function _centrally_qualified_provider_compiler_identity(backend)
    signature = Tuple{typeof(backend)}
    method = which(_provider_compiler_identity, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the provider compiler identity is not centrally admitted"
    ))
    return invoke(_provider_compiler_identity, signature, backend)
end

function _centrally_admitted_lowering_call(
        callback::Function, arguments::Tuple, purpose::Symbol
    )
    signature = Tuple{map(Core.Typeof, arguments)...}
    method = which(callback, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the $purpose lowering implementation is not centrally admitted"
    ))
    return invoke(callback, signature, arguments...)
end

_stage_works(work::LocalWork) = (work,)
_stage_works(work::LocalWork{<:Any, <:Any, <:Any, <:Any, <:_SequenceOperation}) =
    work.operation.works

function _lowering_evidence(
        lowering::_SequenceLowering, work::LocalWork, topology, backend
    )
    stages = map(lowering.stages, work.operation.works) do stage, stage_work
        invoke(
            _centrally_qualified_lowering_evidence,
            Tuple{Any, LocalWork, Any, Any},
            stage, stage_work, topology, backend
        )
    end
    launch_count = foldl(stages; init = 0) do total, stage
        invoke(
            _checked_int_sum,
            Tuple{Integer, Integer, Any},
            total,
            stage.launch_count,
            :sequence_launch_count,
        )
    end
    topology_transfer_bytes = foldl(stages; init = 0) do total, stage
        invoke(
            _checked_int_sum,
            Tuple{Integer, Integer, Any},
            total,
            stage.topology_transfer_bytes,
            :sequence_topology_transfer_bytes,
        )
    end
    return (
        family = :ordered_sequence,
        lowering_identity = Symbol(
            "sequence_",
            join(string.(getproperty.(stages, :lowering_identity)), "_"),
        ),
        launch_count,
        workspace = (; stages = getproperty.(stages, :workspace)),
        topology_transfer_bytes,
        capability = getproperty.(stages, :capability),
        determinism = getproperty.(stages, :determinism),
        stages,
        phases = reduce(
            (left, right) -> (left..., right...),
            getproperty.(stages, :phases);
            init = (),
        ),
    )
end

function _operation_call_facts(
        lowering::_SequenceLowering, work::LocalWork, storage, schema
    )
    stage_facts = map(
        lowering.stages, work.operation.works
    ) do stage, stage_work
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _operation_call_facts,
            (stage, stage_work, storage, schema),
            :operation_call_facts,
        )
    end
    return reduce(
        (left, right) -> (left..., right...), stage_facts; init = ()
    )
end

function _unique_symbols(symbols)
    result = Symbol[]
    for symbol in symbols
        symbol in result || push!(result, symbol)
    end
    return Tuple(result)
end

function _required_bindings(lowering::_SequenceLowering, work::LocalWork)
    stage_names = map(
        lowering.stages, work.operation.works
    ) do stage, stage_work
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _required_bindings,
            (stage, stage_work),
            :required_bindings,
        )
    end
    return invoke(
        _unique_symbols,
        Tuple{Any},
        reduce(vcat, collect.(stage_names)),
    )
end

function _merge_access(left::Symbol, right::Symbol)
    left === right && return left
    left === :read && right === :read && return :read
    return :readwrite
end

function _binding_access(lowering::_SequenceLowering, work::LocalWork)
    names = invoke(
        _required_bindings,
        Tuple{_SequenceLowering, LocalWork},
        lowering,
        work,
    )
    return NamedTuple{names}(map(names) do name
        access = nothing
        for (stage, stage_work) in zip(
                lowering.stages, work.operation.works
            )
            stage_access = invoke(
                _centrally_admitted_lowering_call,
                Tuple{Function, Tuple, Symbol},
                _binding_access,
                (stage, stage_work),
                :binding_access,
            )
            hasproperty(stage_access, name) || continue
            value = getproperty(stage_access, name)
            access = access === nothing ? value : invoke(
                _merge_access,
                Tuple{Symbol, Symbol},
                access,
                value,
            )
        end
        something(access)
    end)
end

function _sequence_stage_workspaces(workspace, count)
    hasproperty(workspace, :stages) || throw(LocalWorkValidationError(
        "ordered work requires a stages tuple in prepared workspace"
    ))
    stages = getproperty(workspace, :stages)
    stages isa Tuple && length(stages) == count ||
        throw(LocalWorkValidationError(
            "prepared sequence workspace has the wrong stage count"
        ))
    return stages
end

function _validate_workspace(
        lowering::_SequenceLowering, work, workspace, backend
    )
    stages = invoke(
        _sequence_stage_workspaces,
        Tuple{Any, Any},
        workspace,
        length(lowering.stages),
    )
    for index in eachindex(lowering.stages)
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _validate_workspace,
            (
                lowering.stages[index],
                work.operation.works[index],
                stages[index],
                backend,
            ),
            :workspace_validation,
        )
    end
    return nothing
end

function _prepare_lowering(
        lowering::_SequenceLowering, work, storage, workspace, backend
    )
    stages = invoke(
        _sequence_stage_workspaces,
        Tuple{Any, Any},
        workspace,
        length(lowering.stages),
    )
    return map(lowering.stages, work.operation.works, stages) do stage,
            stage_work, stage_workspace
        invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _prepare_lowering,
            (stage, stage_work, storage, stage_workspace, backend),
            :preparation,
        )
    end
end

function _execute_lowering!(
        runtime::Tuple,
        lowering::_SequenceLowering,
        work,
        storage,
        workspace,
        submission,
    )
    stages = invoke(
        _sequence_stage_workspaces,
        Tuple{Any, Any},
        workspace,
        length(runtime),
    )
    appended = 0
    for index in eachindex(runtime)
        appended += invoke(
            _centrally_admitted_lowering_call,
            Tuple{Function, Tuple, Symbol},
            _execute_lowering!,
            (
                runtime[index],
                lowering.stages[index],
                work.operation.works[index],
                storage,
                stages[index],
                submission,
            ),
            :execution,
        )
    end
    return appended
end

function _lowering_inspection(
        runtime::Tuple, lowering::_SequenceLowering, work, workspace
    )
    stages = invoke(
        _sequence_stage_workspaces,
        Tuple{Any, Any},
        workspace,
        length(runtime),
    )
    return (
        family = :ordered_sequence,
        stages = map(
                runtime,
                lowering.stages,
                work.operation.works,
                stages,
            ) do stage_runtime, stage, stage_work, stage_workspace
            invoke(
                _centrally_admitted_lowering_call,
                Tuple{Function, Tuple, Symbol},
                _lowering_inspection,
                (stage_runtime, stage, stage_work, stage_workspace),
                :inspection,
            )
        end,
    )
end

function _centrally_qualified_lowering_evidence(
        lowering, work::LocalWork, topology, backend
    )
    method = which(
        _lowering_evidence,
        Tuple{
            typeof(lowering), typeof(work), typeof(topology), typeof(backend),
        },
    )
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the lowering-evidence implementation is not centrally admitted"
    ))
    signature = Tuple{
        typeof(lowering), typeof(work), typeof(topology), typeof(backend),
    }
    return invoke(
        _lowering_evidence, signature, lowering, work, topology, backend
    )
end

"""
    plan(work::LocalWork, topology; backend)

Validate a declaration against explicit topology and a backend, then lower it
centrally into a reusable `WorkPlan`. This call does not bind concrete storage
or authorize externally supplied execution methods.
"""
function plan(work::LocalWork, topology; backend)
    admission_signature = Tuple{LocalWork, Any, Any}
    admission_method = which(_central_admission, admission_signature)
    admission_method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the central admission implementation is not package-owned"
    ))
    lowering = invoke(
        _central_admission,
        admission_signature,
        work,
        topology,
        backend,
    )
    lowering_evidence = invoke(
        _centrally_qualified_lowering_evidence,
        Tuple{Any, LocalWork, Any, Any},
        lowering,
        work,
        topology,
        backend,
    )
    evidence = merge((
        topology_identity = invoke(_topology_identity, Tuple{Any}, topology),
        topology_epoch = invoke(_topology_epoch, Tuple{Any}, topology),
        topology_fingerprint = invoke(
            _centrally_qualified_topology_fingerprint,
            Tuple{Any, Any},
            topology,
            lowering,
        ),
        backend_type = typeof(backend),
    ), lowering_evidence)
    return WorkPlan(
        _CONSTRUCTION_TOKEN, work, topology, backend, lowering, evidence
    )
end

function _make_provider_lane(backend, storage)
    throw(LocalWorkValidationError(
        "no centrally admitted provider-lane adapter exists for $(typeof(backend))"
    ))
end

function _central_make_provider_lane(backend, storage)
    signature = Tuple{typeof(backend), typeof(storage)}
    method = which(_make_provider_lane, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the provider-lane adapter is not centrally admitted"
    ))
    return invoke(_make_provider_lane, signature, backend, storage)
end

function _validate_lane_current! end
function _validate_provider_capacity end
function _wait_lane! end
function _poison_lane! end
function _lane_provider end
function _lane_device end
function _lane_identity end
function _lane_wait_scope end
function _lane_transfer_law end
function _lane_cumulative end
function _lane_selective end
function _lane_error_observation end
function _lane_wait_count end
function _lane_poisoned end
function _lane_poison_reason end

function _centrally_admitted_provider_call(
        callback::Function, arguments::Tuple, purpose::Symbol
    )
    signature = Tuple{map(Core.Typeof, arguments)...}
    method = which(callback, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the $purpose provider implementation is not centrally admitted"
    ))
    return invoke(callback, signature, arguments...)
end
