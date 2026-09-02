#!/usr/bin/env julia

# Fresh-process compiler-health evidence for the typed LocalMath stage waist.

const _COMPILER_PROCESS_START_NS = time_ns()
import KernelAbstractions
import LocalMath
import Statistics
import TOML

const _COMPILER_REQUESTED_BACKEND = let
    prefix = "--backend="
    index = findfirst(startswith(prefix), ARGS)
    index === nothing ? "cpu" : String(split(ARGS[index], "="; limit = 2)[2])
end
if _COMPILER_REQUESTED_BACKEND == "metal"
    import Metal
elseif _COMPILER_REQUESTED_BACKEND == "cuda"
    import CUDA
elseif _COMPILER_REQUESTED_BACKEND == "amdgpu"
    import AMDGPU
end

const _COMPILER_PACKAGE_LOAD_SECONDS = (time_ns() - _COMPILER_PROCESS_START_NS) / 1.0e9
const _COMPILER_STAGE_COUNTS = (1, 4, 8, 13, 32)

struct _CompilerItems end
struct _CompilerSingleton end

struct _CompilerUniqueEvaluator
    index::Int32
end
@inline function (evaluator::_CompilerUniqueEvaluator)(item::Int32, reads, parameters)
    value = something(@inbounds(reads[1][1].value)) + evaluator.index
    return (value = LocalMath.UniqueValue(value),)
end

struct _CompilerReduceEvaluator
    index::Int32
end
@inline function (evaluator::_CompilerReduceEvaluator)(item::Int32, reads, parameters)
    value = something(@inbounds(reads[1][1].value)) + evaluator.index
    return (value = LocalMath.Contribution(value),)
end

struct _CompilerResolveEvaluator
    index::Int32
end

struct _CompilerCollectEvaluator
    index::Int32
end
@inline function (evaluator::_CompilerCollectEvaluator)(item::Int32, reads, parameters)
    value = something(@inbounds(reads[1][1].value)) + evaluator.index
    return (value = LocalMath.CollectedValue(value),)
end

struct _CompilerFoldEvaluator
    index::Int32
end
@inline function (evaluator::_CompilerFoldEvaluator)(item::Int32, reads, parameters)
    value = something(@inbounds(reads[1][1].value)) + evaluator.index
    return (value = LocalMath.FoldValue(value),)
end

struct _CompilerFoldTransition end
@inline function (::_CompilerFoldTransition)(state, value::Int32, item::Int32, reads)
    next = @inbounds(state.accumulator[1]) + value
    writes = LocalMath.BoundedWrites(
        (Int32(1),), (next,), Int32(1))
    return LocalMath.FoldStep((accumulator = writes,))
end
@inline function (evaluator::_CompilerResolveEvaluator)(item::Int32, reads, parameters)
    value = something(@inbounds(reads[1][1].value)) + evaluator.index
    candidate = LocalMath.ResolutionValue(item, UInt32(item), value, true)
    return (value = candidate,)
end

_compiler_symbol(kind::Symbol, index::Int) = Symbol(:compiler_, kind, :_, lpad(index, 2, '0'))

function _compiler_stage(index::Int, item_count::Int, items, singleton, source, identity)
    kind = mod1(index, 5)
    label = kind == 1 ? :unique : kind == 2 ? :reduce : kind == 3 ? :resolve :
        kind == 4 ? :collect : :ordered_fold
    port = _compiler_symbol(label, index)
    collection = nothing
    initial = nothing
    if kind == 1
        output = LocalMath.Field(items, Int32)
        relation = identity
        evaluator = _CompilerUniqueEvaluator(Int32(index))
        law = LocalMath.Unique(Int32)
    elseif kind == 2
        output = LocalMath.Field(singleton, Int32)
        relation = LocalMath.FixedRelation(items => singleton; degree = 1)
        evaluator = _CompilerReduceEvaluator(Int32(index))
        law = LocalMath.Reduce(Int32, +;
            seed = LocalMath.IdentitySeed(Int32(0)))
    elseif kind == 3
        output = LocalMath.Field(singleton, Int32)
        relation = LocalMath.FixedRelation(items => singleton; degree = 1)
        evaluator = _CompilerResolveEvaluator(Int32(index))
        law = LocalMath.Resolve(Int32, Int32;
            direction = LocalMath.ArgMin(),
            tie = LocalMath.TieMin{UInt32}(),
            lower = Int32(1), upper = Int32(item_count),
            onempty = LocalMath.FillEmpty(Int32(0)))
    elseif kind == 4
        collection = LocalMath.Collection(Int32, item_count)
        output = nothing
        relation = nothing
        evaluator = _CompilerCollectEvaluator(Int32(index))
        law = LocalMath.Collect(Int32; maximum = 1)
    else
        initial = LocalMath.Field(singleton, Int32)
        output = LocalMath.Field(singleton, Int32)
        relation = nothing
        evaluator = _CompilerFoldEvaluator(Int32(index))
        state = LocalMath.InitializedState(
            accumulator = LocalMath.FoldComponent(output; from = initial))
        law = LocalMath.OrderedFold(
            Int32, state, _CompilerFoldTransition())
    end
    publication = kind <= 3 ? LocalMath.Publication((
            LocalMath.FieldPublication(output, relation,
                LocalMath.PublicationValue(:value)),), law) :
        kind == 4 ? LocalMath.Publication((
            LocalMath.CollectionPublication(collection,
                LocalMath.PublicationValue(:value)),), law) :
        LocalMath.Publication((LocalMath.FoldPublication(
            LocalMath.PublicationValue(:value)),), law)
    stage = LocalMath.Stage(items,
        (source = LocalMath.Access(source, identity),),
        (publication,), LocalMath.Evaluator(evaluator),
        LocalMath.Control(), LocalMath.SourceOrigin(:compiler_scaling_case, index))
    return LocalMath.LocalLaw(stage),
        (; kind = label, output, relation, collection, initial)
end

function _compiler_workload(stage_count::Int, item_count::Int)
    stage_count in _COMPILER_STAGE_COUNTS || error("compiler scaling stage count must be one of $(_COMPILER_STAGE_COUNTS)")
    items = LocalMath.Space(_CompilerItems, item_count)
    singleton = LocalMath.Space(_CompilerSingleton, 1)
    source = LocalMath.Field(items, Int32)
    identity = LocalMath.IdentityRelation(items)
    stages = ntuple(index -> _compiler_stage(index, item_count,
        items, singleton, source, identity), stage_count)
    return (law = LocalMath.sequence(map(first, stages)...),
        metadata = map(last, stages), source, identity, item_count)
end

function _compiler_backend(name::AbstractString)
    name = String(name)
    if name == "cpu"
        return (name = "cpu", backend = KernelAbstractions.CPU(),
            array_type = Array, hardware = Sys.CPU_NAME)
    elseif name == "metal"
        array_type, hardware = Metal.MtlArray, repr(Metal.device())
    elseif name == "cuda"
        array_type, hardware = CUDA.CuArray, repr(CUDA.device())
    elseif name == "amdgpu"
        array_type, hardware = AMDGPU.ROCArray, repr(AMDGPU.device())
    else
        error("unknown compiler scaling backend $name")
    end
    probe = array_type(zeros(Int32, 1))
    return (name, backend = KernelAbstractions.get_backend(probe), array_type, hardware)
end

function _compiler_bound(workload, array_type)
    field_pairs = (workload.source => array_type(Int32.(1:workload.item_count)),)
    relation_pairs = ()
    collection_pairs = ()
    for stage in workload.metadata
        if stage.output !== nothing
            size = stage.kind === :unique ? workload.item_count : 1
            field_pairs = (field_pairs...,
                stage.output => array_type(fill(Int32(-1), size)))
        end
        stage.initial === nothing || (field_pairs = (field_pairs...,
            stage.initial => array_type(fill(Int32(0), 1))))
        if stage.relation !== nothing && stage.relation !== workload.identity
            endpoints = array_type(reshape(fill(Int32(1), workload.item_count), 1, :))
            counts = array_type(fill(Int32(1), workload.item_count))
            storage = (; endpoints, counts)
            declaration = array_type === Array ? storage :
                LocalMath.MutableRelationStorage(storage;
                    generation = array_type(UInt64[1]),
                    status = array_type(Int32[0]),
                    validated_generations = array_type(UInt64[0]))
            relation_pairs = (
                relation_pairs..., stage.relation => declaration)
        end
        if stage.collection !== nothing
            capacity = Int(stage.collection.capacity)
            storage = LocalMath.CompactedStorage(
                array_type(fill(Int32(0), capacity)), array_type(zeros(Int32, 1)),
                nothing, array_type(zeros(Int32, capacity)),
                array_type(zeros(Int32, capacity)), nothing)
            collection_pairs = (collection_pairs..., stage.collection => storage)
        end
    end
    return LocalMath.bind(workload.law, field_pairs..., relation_pairs...,
        collection_pairs...)
end

function _compiler_timing(f)
    GC.gc()
    result = @timed f()
    return result.value, Dict("elapsed_seconds" => result.time,
        "compile_seconds" => result.compile_time,
        "recompile_seconds" => result.recompile_time,
        "allocated_bytes" => result.bytes, "gc_seconds" => result.gctime)
end

function _compiler_phase_marker(name::String, timing)
    println(stderr, "COMPILER_PHASE ", name,
        " elapsed=", timing["elapsed_seconds"],
        " compile=", timing["compile_seconds"])
    flush(stderr)
    return nothing
end

function _compiler_warm_samples(prepared, count::Int)
    elapsed, allocated = Float64[], Int[]
    compiled, recompiled = Float64[], Float64[]
    for _ in 1:count
        result = @timed wait(LocalMath.execute!(prepared))
        push!(elapsed, result.time); push!(allocated, result.bytes)
        push!(compiled, result.compile_time)
        push!(recompiled, result.recompile_time)
    end
    return Dict("samples" => count, "median_seconds" => Statistics.median(elapsed),
        "minimum_seconds" => minimum(elapsed), "maximum_seconds" => maximum(elapsed),
        "median_allocated_bytes" => Statistics.median(allocated),
        "maximum_allocated_bytes" => maximum(allocated),
        "maximum_compile_seconds" => maximum(compiled),
        "maximum_recompile_seconds" => maximum(recompiled))
end

function _compiler_argument(name::String, default::String)
    prefix = "--$name="
    argument = findfirst(startswith(prefix), ARGS)
    return argument === nothing ? default : split(ARGS[argument], "="; limit = 2)[2]
end

Base.@noinline function _compiler_emit_report(stage_count, item_count, backend_config,
        workload, prepared, construction, binding, planning, preparation,
        first_execution, warm)
    timed = (construction, binding, planning, preparation, first_execution)
    facts = LocalMath.inspect(prepared)
    options = Base.JLOptions()
    report = Dict{String,Any}(
        "schema_version" => 2, "profile" => "typed_stage_scaling",
        "stage_count" => stage_count, "item_count" => item_count,
        "backend" => backend_config.name,
        "backend_type" => string(typeof(backend_config.backend)),
        "hardware" => backend_config.hardware, "machine" => Sys.MACHINE,
        "kernel" => string(Sys.KERNEL), "cpu_threads" => Sys.CPU_THREADS,
        "total_memory_bytes" => Sys.total_memory(), "julia_version" => string(VERSION),
        "kernelabstractions_version" => string(Base.pkgversion(KernelAbstractions)),
        "localmath_version" => string(Base.pkgversion(LocalMath)),
        "threads" => Threads.nthreads(),
        "compile_mode" => "ordinary --compile=yes --optimize=2",
        "julia_options" => Dict("startupfile" => Int(options.startupfile),
            "compile_enabled" => Int(options.compile_enabled),
            "opt_level" => Int(options.opt_level),
            "use_compiled_modules" => Int(options.use_compiled_modules),
            "project" => something(Base.active_project(), "")),
        "program_arguments" => copy(ARGS),
        "cache_state" => "fresh process; package caches may be precompiled; workload methods cold",
        "package_load_seconds" => _COMPILER_PACKAGE_LOAD_SECONDS,
        "host_compile_seconds_total" => sum(x["compile_seconds"] for x in timed),
        "host_recompile_seconds_total" => sum(x["recompile_seconds"] for x in timed),
        "planning_through_first_execution_seconds" => sum(x["elapsed_seconds"] for x in
            (planning, preparation, first_execution)),
        "logical_stage_kinds" => collect(string.(getproperty.(workload.metadata, :kind))),
        "physical_launch_count" => facts.planning.base_provider_launch_count,
        "compiler_spine" => string(facts.planning.compiler),
        "construction" => construction, "binding" => binding,
        "planning" => planning, "preparation" => preparation,
        "first_execution" => first_execution, "warm_execution" => warm)
    TOML.print(stdout, report; sorted = true)
    return nothing
end

function _compiler_main()
    stage_count = parse(Int, _compiler_argument("stages", "13"))
    item_count = parse(Int, _compiler_argument("items", "16"))
    warm_samples = parse(Int, _compiler_argument("warm-samples", "7"))
    backend_config = _compiler_backend(_compiler_argument("backend", "cpu"))
    workload, construction = _compiler_timing(() -> _compiler_workload(stage_count, item_count))
    _compiler_phase_marker("construction", construction)
    bound, binding = _compiler_timing(() -> _compiler_bound(workload, backend_config.array_type))
    _compiler_phase_marker("binding", binding)
    plan, planning = _compiler_timing(() -> LocalMath.plan(bound;
        backend = backend_config.backend))
    _compiler_phase_marker("planning", planning)
    prepared, preparation = _compiler_timing(() -> LocalMath.prepare(plan))
    _compiler_phase_marker("preparation", preparation)
    _, first_execution = _compiler_timing(() -> wait(LocalMath.execute!(prepared)))
    _compiler_phase_marker("first_execution", first_execution)
    warm = _compiler_warm_samples(prepared, warm_samples)
    first_execution["provider_compile_upper_bound_seconds"] = max(0.0,
        first_execution["elapsed_seconds"] - first_execution["compile_seconds"] -
            warm["median_seconds"])
    return _compiler_emit_report(stage_count, item_count, backend_config, workload,
        prepared, construction, binding, planning, preparation, first_execution, warm)
end

abspath(PROGRAM_FILE) == (@__FILE__) && _compiler_main()
