#!/usr/bin/env julia

# Reproducible compiler/allocation evidence for the warm sparse-key boundary.
import KernelAbstractions
import LocalMath
import TOML

struct KeyedCompilerNode end
struct KeyedCompilerEvaluator end
@inline (::KeyedCompilerEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution(
        (UInt32(isodd(item)), UInt32(item)), Int32(1)))

struct CollectCompilerEvaluator end
@inline (::CollectCompilerEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.CollectedValue(item))

struct KeyedCompilerSubtract end
@inline (::KeyedCompilerSubtract)(left::Int32, right::Int32) = left - right

function keyed_compiler_preparation(capacity::Int;
        operation = +, retention = LocalMath.DropIdentityKeys(),
        seed = LocalMath.NewKeyIdentity(Int32(0)))
    source = LocalMath.Space(KeyedCompilerNode, 3)
    key_type = Tuple{UInt32,UInt32}
    collection = LocalMath.Collection(
        LocalMath.KeyedValue{key_type,Int32}, capacity)
    stage = LocalMath.Stage(source, NamedTuple(), (
        LocalMath.Publication(collection,
            LocalMath.KeyedReduce(key_type, Int32, operation;
                seed, retention);
            value = :delta),),
        LocalMath.Evaluator(KeyedCompilerEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:keyed_reduce_compiler, 1))
    return LocalMath.prepare(LocalMath.LocalLaw(stage),
        collection => LocalMath.Allocate();
        backend = KernelAbstractions.CPU())
end

function collect_compiler_preparation(capacity::Int)
    source = LocalMath.Space(KeyedCompilerNode, 3)
    collection = LocalMath.Collection(Int32, capacity)
    stage = LocalMath.Stage(source, NamedTuple(), (
        LocalMath.Publication(collection,
            LocalMath.Collect(Int32; maximum = 1); value = :delta),),
        LocalMath.Evaluator(CollectCompilerEvaluator()), LocalMath.Control(),
        LocalMath.SourceOrigin(:collect_compiler_control, 1))
    return LocalMath.prepare(LocalMath.LocalLaw(stage),
        collection => LocalMath.Allocate();
        backend = KernelAbstractions.CPU())
end

function code_info_metrics(info, return_type, method_instance_count,
        method_specialization_count)
    calls = count(statement -> statement isa Expr &&
        statement.head in (:call, :invoke), info.code)
    any_indices = filter(index -> info.ssavaluetypes[index] === Any,
        eachindex(info.code))
    control_flow = statement -> statement isa Union{
        Core.GotoNode,Core.GotoIfNot,Core.ReturnNode}
    statement_kinds = Dict{String,Int}()
    for statement in info.code
        kind = statement isa Expr ? string(statement.head) :
            string(nameof(typeof(statement)))
        statement_kinds[kind] = get(statement_kinds, kind, 0) + 1
    end
    return Dict(
        "statement_count" => length(info.code),
        "call_count" => calls,
        "any_ssa_count" => length(any_indices),
        "any_control_flow_count" => count(
            index -> control_flow(info.code[index]), any_indices),
        "any_value_count" => count(
            index -> !control_flow(info.code[index]), any_indices),
        "ssa_count" => length(info.ssavaluetypes),
        "slot_count" => length(info.slotnames),
        "method_instance_count" => method_instance_count,
        "method_specialization_count" => method_specialization_count,
        "statement_kinds" => statement_kinds,
        "return_type" => string(return_type),
    )
end

function typed_metrics(callable, signature)
    full_signature = Tuple{typeof(callable),signature.parameters...}
    method = which(callable, signature)
    info, return_type = only(Base.code_typed_by_type(
        full_signature; optimize = true))
    return code_info_metrics(info, return_type,
        length(Base.method_instances(
            callable, signature, Base.get_world_counter())),
        count(instance -> instance isa Core.MethodInstance,
            Base.specializations(method)))
end


function kernel_typed_metrics(kernel, signature;
        ndrange::Int, workgroupsize::Int)
    launch_ndrange, launch_workgroupsize, iterspace, dynamic =
        KernelAbstractions.launch_config(
            kernel, ndrange, workgroupsize)
    block = @inbounds KernelAbstractions.blocks(iterspace)[1]
    context = KernelAbstractions.mkcontext(kernel, block, launch_ndrange,
        iterspace, dynamic)
    transformed_signature = Tuple{typeof(context),signature.parameters...}
    method = which(kernel.f, transformed_signature)
    info, return_type = only(KernelAbstractions.ka_code_typed(
        kernel, signature; ndrange, workgroupsize, optimize = true))
    return code_info_metrics(info, return_type,
        length(Base.method_instances(kernel.f, transformed_signature,
            Base.get_world_counter())),
        count(instance -> instance isa Core.MethodInstance,
            Base.specializations(method)))
end

function warm_public_execution_allocations(prepared)
    wait(LocalMath.execute!(prepared))
    return minimum(@allocated(wait(LocalMath.execute!(prepared))) for _ in 1:5)
end

function keyed_compiler_metrics(prepared)
    launch = only(getfield(getfield(prepared, :runtime), :launches))
    stage = getfield(launch, :stage)
    validation = LocalMath._ProgramValidationTarget(
        getfield(getfield(prepared, :runtime), :execution_gate), Int32(1))
    signature = Tuple{typeof(stage),Tuple{},Int32,Tuple{},
        typeof(getfield(launch, :guard)),typeof(validation)}
    host = typed_metrics(LocalMath._execute_keyed_reduce_stage!, signature)
    execution = getfield(stage, :execution)
    plan = getfield(execution, :plan)
    states = getfield(execution, :states)
    emission = LocalMath.KeyedContribution(
        (UInt32(1), UInt32(1)), Int32(1))
    extent = max(Int(plan.bounds.candidate_count), 1)
    reset_kernel = LocalMath._keyed_reduce_reset_kernel!(
        KernelAbstractions.CPU(), min(extent, LocalMath._COMPACTED_BLOCK),
        extent)
    reset_signature = Tuple{typeof(plan.bounds),typeof(states.reset),
        typeof(execution.storage),typeof(getfield(stage, :validation)),Int32}
    segment_kernel = LocalMath._keyed_reduce_segments_kernel!(
        KernelAbstractions.CPU(), min(extent, LocalMath._COMPACTED_BLOCK),
        extent)
    segment_signature = Tuple{typeof(plan.key_order),typeof(states.segment),
        typeof(states.ordering.order_a),Int32,Int32}
    semantic_signature = Tuple{typeof(plan.emission),typeof(states.emission),
        typeof(emission),Int32}
    semantic = typed_metrics(LocalMath._keyed_reduce_materialize!,
        semantic_signature)
    allocated = warm_public_execution_allocations(prepared)
    return Dict(
        "host_orchestration" => host,
        "emission_boundary" => semantic,
        "reset_kernel_boundary" => kernel_typed_metrics(
            reset_kernel, reset_signature; ndrange = extent,
            workgroupsize = min(extent, LocalMath._COMPACTED_BLOCK)),
        "sort_boundary" => typed_metrics(LocalMath._compacted_ordinal_less,
            Tuple{typeof(plan.key_order),typeof(states.ordering),Int32,Int32}),
        "fold_boundary" => typed_metrics(LocalMath._keyed_reduce_fold_segment!,
            Tuple{typeof(plan.fold),typeof(states.fold),
                typeof(states.ordering.order_a),Int32,Int32}),
        "segment_kernel_boundary" => kernel_typed_metrics(
            segment_kernel, segment_signature; ndrange = extent,
            workgroupsize = min(extent, LocalMath._COMPACTED_BLOCK)),
        "publish_boundary" => typed_metrics(LocalMath._keyed_reduce_publish_record!,
            Tuple{typeof(plan.publication),typeof(states.publication),
                typeof(execution.storage),Int32,Int32}),
        "warm_public_execution_allocated_bytes" => allocated,
        "host_any_classes" => [
            "KernelAbstractions launch construction (_svec_ref and kwcall)",
            "compacted scan/order launch calls whose host return is unused",
            "host control-flow and return nodes represented as Any by CodeInfo",
        ],
        "allocation_root_classes" => [
            "shared ExecutionReceipt and validation-status grouping",
            "KernelAbstractions Kernel, NDRange, keyword, and argument tuples per launch",
        ],
        "prepared_stage_type" => string(typeof(stage)),
    )
end

function collect_compiler_metrics(prepared)
    launch = only(getfield(getfield(prepared, :runtime), :launches))
    stage = getfield(launch, :stage)
    validation = LocalMath._ProgramValidationTarget(
        getfield(getfield(prepared, :runtime), :execution_gate), Int32(1))
    signature = Tuple{typeof(stage),Tuple{},Int32,Tuple{},
        typeof(getfield(launch, :guard)),typeof(validation)}
    return typed_metrics(LocalMath._execute_collect_stage!, signature)
end

preparations = map(capacity -> keyed_compiler_preparation(capacity), (4, 8))
variants = (
    keyed_compiler_preparation(4; operation = +,
        retention = LocalMath.DropIdentityKeys()),
    keyed_compiler_preparation(4; operation = +,
        retention = LocalMath.RetainAllKeys()),
    keyed_compiler_preparation(4; operation = KeyedCompilerSubtract(),
        retention = LocalMath.DropIdentityKeys()),
    keyed_compiler_preparation(4; operation = KeyedCompilerSubtract(),
        retention = LocalMath.RetainAllKeys()),
)
metrics = keyed_compiler_metrics(first(preparations))
metrics["measured_revision"] = get(
    ENV, "LOCALMATH_COMPILER_REVISION", "working_tree")
control = collect_compiler_preparation(4)
metrics["collect_host_orchestration"] = collect_compiler_metrics(control)
control_allocated = warm_public_execution_allocations(control)
metrics["collect_control_allocated_bytes"] = control_allocated
metrics["keyed_incremental_allocated_bytes"] =
    metrics["warm_public_execution_allocated_bytes"] - control_allocated
metrics["capacity_specialization_count"] = length(unique(typeof(
    getfield(only(getfield(getfield(prepared, :runtime), :launches)), :stage))
    for prepared in preparations))
variant_parts = map(variants) do prepared
    execution = getfield(getfield(only(getfield(
        getfield(prepared, :runtime), :launches)), :stage), :execution)
    (; plan = execution.plan, states = execution.states,
        storage = execution.storage)
end
metrics["operation_retention_specializations"] = Dict(
    "bounds" => length(unique(typeof(part.plan.bounds) for part in variant_parts)),
    "emission" => length(unique(typeof(part.plan.emission) for part in variant_parts)),
    "sort" => length(unique((typeof(part.plan.key_order),
        typeof(part.states.ordering)) for part in variant_parts)),
    "segment" => length(unique((typeof(part.plan.key_order),
        typeof(part.states.segment)) for part in variant_parts)),
    "fold" => length(unique((typeof(part.plan.fold),
        typeof(part.states.fold)) for part in variant_parts)),
    "finalize" => length(unique((typeof(part.plan.bounds),
        typeof(part.states.final)) for part in variant_parts)),
    "publish" => length(unique((typeof(part.plan.publication),
        typeof(part.states.publication), typeof(part.storage))
        for part in variant_parts)),
)
if isdefined(LocalMath, :RebuildFromIdentity)
    seed_variants = (
        keyed_compiler_preparation(4;
            seed = LocalMath.NewKeyIdentity(Int32(0))),
        keyed_compiler_preparation(4;
            seed = LocalMath.RebuildFromIdentity(Int32(0))),
    )
    seed_variant_parts = map(seed_variants) do prepared
        stage = getfield(only(getfield(
            getfield(prepared, :runtime), :launches)), :stage)
        execution = getfield(stage, :execution)
        (; stage, plan = execution.plan, states = execution.states,
            storage = execution.storage)
    end
    metrics["seed_policy_specializations"] = Dict(
        "prepared_stage" => length(unique(typeof(part.stage)
            for part in seed_variant_parts)),
        "bounds" => length(unique(typeof(part.plan.bounds)
            for part in seed_variant_parts)),
        "emission" => length(unique(typeof(part.plan.emission)
            for part in seed_variant_parts)),
        "sort" => length(unique((typeof(part.plan.key_order),
            typeof(part.states.ordering)) for part in seed_variant_parts)),
        "fold" => length(unique((typeof(part.plan.fold),
            typeof(part.states.fold)) for part in seed_variant_parts)),
        "publish" => length(unique((typeof(part.plan.publication),
            typeof(part.states.publication), typeof(part.storage))
            for part in seed_variant_parts)),
    )
    metrics["seed_policy_warm_public_execution_allocated_bytes"] = Dict(
        "incremental" => warm_public_execution_allocations(
            first(seed_variants)),
        "rebuild" => warm_public_execution_allocations(last(seed_variants)),
    )
end
TOML.print(stdout, Dict("keyed_reduce" => metrics); sorted = true)
println()
