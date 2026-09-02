#!/usr/bin/env julia

# One fresh-process observation of the authentic CorePotts lifecycle selection
# boundary. This is evidence tooling only and uses existing production
# constructors and execution entry points without altering their semantics.

const _Compiler_PROCESS_START_NS = time_ns()

import CorePotts
import KernelAbstractions
import LocalMath
import Statistics
import TOML

const _Compiler_PACKAGE_LOAD_SECONDS = (time_ns() - _Compiler_PROCESS_START_NS) / 1.0e9

function _empty_descriptor_plan()
    return CorePotts.DescriptorExecutionPlan(
        (),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        Int32(0),
        "compiler-empty-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
end

function _flagship_descriptor()
    return CorePotts.LifecycleDescriptor{2, Float64}(
        Int32(1),
        UInt64(101),
        UInt64(201),
        CorePotts.CellKindLifecycleDomain,
        Int16(2),
        Int32(1),
        CorePotts.EveryMCSLifecycleCadence,
        Int32(1),
        CorePotts.RemoveCellLifecycleEffect,
        Int32(0),
        CorePotts.ErrorLifecycleInadmissible,
        Int16(0),
        Int16(1),
        CorePotts.NoLifecyclePlacement,
        Int32(0),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(0),
        CorePotts.NoLifecyclePartition,
        Int32(0),
        false,
        (0.0, 0.0),
        (0.0, 0.0),
        CorePotts.CanonicalLifecycleSide,
        UInt16(0),
        UInt16(0),
        Int16(0),
        Int16(0),
        Int32(1),
        Int32(0),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        false,
    )
end

function _flagship_lifecycle_plan()
    return CorePotts.LifecycleExecutionPlan(
        CorePotts.LifecycleDescriptor{2, Float64}[_flagship_descriptor()],
        CorePotts.LifecycleEvaluatorStorage(
            Any[CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true))],
            Symbol[:lifecycle_trigger],
        ),
        CorePotts.LifecycleStateRuleStorage(Any[]),
        CorePotts.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        CorePotts.LifecycleRelationStorage(Any[], Val(2)),
        CorePotts.StablePriorityLifecycleConflicts,
        8,
        8,
        1,
        0,
        falses(2),
    )
end

function _flagship_fixture()
    offsets = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (CorePotts.OwnershipCountTracker(),),
        "compiler-ownership-count-v1",
    )
    lifecycle_plan = _flagship_lifecycle_plan()
    program = CorePotts.CompiledPottsProgram(
        (6, 6),
        (true, true),
        offsets,
        2,
        1,
        CorePotts.CompiledScalar(3.0),
        1,
        Float64[],
        (),
        tracker_plan,
        _empty_descriptor_plan(),
        CorePotts.StageExecutionPlan(),
        CorePotts.SequentialProgramEngine(),
        CorePotts.CPUProgramBackend(),
        "compiler-corepotts-lifecycle-flagship-v1";
        lifecycle_plan,
    )
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= Int32(1)
    cell_kinds = zeros(Int16, 8)
    cell_kinds[1] = Int16(2)
    cell_generations = zeros(UInt32, 8)
    cell_generations[1] = UInt32(1)
    initial = CorePotts.ProgramInitialState(
        ownership,
        cell_kinds;
        scalar_type = Float64,
        cell_generations,
    )
    return (; program, initial)
end

function _timing(f)
    GC.gc()
    result = @timed f()
    return result.value, Dict(
        "elapsed_seconds" => result.time,
        "compile_seconds" => result.compile_time,
        "recompile_seconds" => result.recompile_time,
        "allocated_bytes" => result.bytes,
        "gc_seconds" => result.gctime,
    )
end

Base.@noinline function _run_request_index!(runtime, workspace)
    return CorePotts._run_sequential_lifecycle_request_index!(runtime, workspace)
end

Base.@noinline function _run_selection_phase!(runtime, workspace)
    return CorePotts._run_sequential_lifecycle_selection!(runtime, workspace)
end

Base.@noinline function _run_selection!(runtime)
    Base.@nospecialize runtime
    workspace = runtime.lifecycle_workspace
    CorePotts._reset_lifecycle_workspace!(workspace)
    _run_request_index!(runtime, workspace)
    _run_selection_phase!(runtime, workspace)
    return workspace
end

function _warm_samples(runtime, count::Int)
    Base.@nospecialize runtime
    # The cold boundary deliberately times request indexing and selection
    # separately. Prime only the combined reporting wrapper before measuring
    # steady-state repetitions, and retain that compilation as explicit
    # harness evidence rather than charging it to production warm execution.
    warmup = @timed _run_selection!(runtime)
    elapsed = Float64[]
    allocated = Int[]
    compiled = Float64[]
    recompiled = Float64[]
    for _ in 1:count
        result = @timed _run_selection!(runtime)
        push!(elapsed, result.time)
        push!(allocated, result.bytes)
        push!(compiled, result.compile_time)
        push!(recompiled, result.recompile_time)
    end
    return Dict(
        "samples" => count,
        "median_seconds" => Statistics.median(elapsed),
        "minimum_seconds" => minimum(elapsed),
        "maximum_seconds" => maximum(elapsed),
        "median_allocated_bytes" => Statistics.median(allocated),
        "maximum_allocated_bytes" => maximum(allocated),
        "maximum_compile_seconds" => maximum(compiled),
        "maximum_recompile_seconds" => maximum(recompiled),
        "harness_warmup_compile_seconds" => warmup.compile_time,
        "harness_warmup_recompile_seconds" => warmup.recompile_time,
    )
end

function _flagship_physical_evidence(prepared)
    local_law = _flagship_stage_program(prepared)
    report = LocalMath.inspect(local_law)
    identities = hasproperty(prepared, :publication) ?
        ["CorePotts._lifecycle_selection_transaction_kernel!"] : String[]
    push!(identities, "stage_program_status_reset")
    for phases in report.planning.stage_phases, phase in phases
        append!(identities, fill(String(phase.kind), phase.count))
    end
    return (launch_count = length(identities), identities)
end

_flagship_stage_program(prepared) = hasproperty(prepared, :publication) ?
    getproperty(prepared, :publication) : prepared

Base.@noinline function _cold_evidence_summary(prepared_banks)
    Base.@nospecialize prepared_banks
    length(prepared_banks) == 2 || error(
        "sequential flagship expected two physical selection banks",
    )
    bank_evidence = map(prepared ->
        LocalMath.inspect(_flagship_stage_program(prepared)),
        prepared_banks)
    evidence = first(bank_evidence)
    lowering_identity = evidence.planning.compiler
    stage_program_banks = map(_flagship_stage_program, prepared_banks)
    physical = map(_flagship_physical_evidence, prepared_banks)
    launch_count = first(physical).launch_count
    phases = first(physical).identities
    for fact in bank_evidence
        fact.planning.compiler == lowering_identity || error(
            "flagship physical banks disagree on lowering identity",
        )
    end
    for fact in physical
        fact.identities == phases || error(
            "flagship physical banks disagree on phase identity")
        fact.launch_count == launch_count || error(
            "flagship physical banks disagree on launch count")
    end
    stages = evidence.stages
    logical_stage_count = length(stages)
    logical_stage_count == 1 || error(
        "authentic lifecycle publication has $logical_stage_count stages, expected 1",
    )
    stage_identities = String[]
    sizehint!(stage_identities, logical_stage_count)
    for stage in stages
        laws = join(string.(map(publication ->
            publication.details.law.kind, stage.publications)), "+")
        push!(stage_identities,
            string(stage.planning.executor, ":", laws))
    end
    phase_identities = String[]
    sizehint!(phase_identities, length(phases))
    for phase in phases
        push!(phase_identities, string(phase))
    end
    callback_summaries = Any[]
    for prepared in stage_program_banks
        callbacks = prepared.plan.lowering.callback_facts
        stage_counts = Dict{String, Int}()
        purpose_counts = Dict{String, Int}()
        admitted = 0
        methods_current = true
        for callback in callbacks
            stage = "1"
            purpose = string(getproperty(callback, :purpose))
            stage_counts[stage] = get(stage_counts, stage, 0) + 1
            purpose_counts[purpose] = get(purpose_counts, purpose, 0) + 1
            admitted += hasproperty(callback, :qualification)
            methods_current &= which(
                getproperty(callback, :callback),
                getproperty(callback, :signature),
            ) === getproperty(callback, :method)
        end
        push!(callback_summaries, (
            count = length(callbacks),
            stage_counts,
            purpose_counts,
            admitted,
            methods_current,
            world_current = getproperty(prepared, :operation_world) ==
                Base.get_world_counter(),
        ))
    end
    first_callbacks = first(callback_summaries)
    all(==(first_callbacks), callback_summaries) || error(
        "flagship physical banks disagree on callback admission facts",
    )
    first_callbacks.methods_current || error(
        "flagship callback method identity changed after preparation",
    )
    first_callbacks.world_current || error(
        "flagship callback world age changed during the probe",
    )
    return Dict{String, Any}(
        "logical_stage_count" => logical_stage_count,
        "physical_launch_count" => Int(launch_count),
        "physical_bank_count" => length(prepared_banks),
        "lowering_identity" => string(lowering_identity),
        "physical_phase_identities" => phase_identities,
        "logical_stage_identities" => stage_identities,
        "operation_fact_count" => first_callbacks.count,
        "operation_fact_stage_counts" => first_callbacks.stage_counts,
        "operation_fact_purpose_counts" => first_callbacks.purpose_counts,
        "admitted_operation_fact_count" => first_callbacks.admitted,
        "operation_methods_current" => first_callbacks.methods_current,
        "operation_world_current" => first_callbacks.world_current,
    )
end

function _argument(name::String, default::String)
    prefix = "--$name="
    argument = findfirst(startswith(prefix), ARGS)
    return argument === nothing ? default : split(ARGS[argument], "="; limit = 2)[2]
end

Base.@noinline function _emit_flagship_report(
        evidence, selection_succeeded, fixture_construction, initialization,
        first_request_index, first_selection, warm,
    )
    Base.@nospecialize evidence
    timed_boundaries = (
        fixture_construction,
        initialization,
        first_request_index,
        first_selection,
    )
    total_host_compile = sum(
        boundary["compile_seconds"] for boundary in timed_boundaries
    )
    options = Base.JLOptions()
    report = Dict{String, Any}(
        "schema_version" => 1,
        "profile" => "corepotts_lifecycle_flagship",
        "stage_count" => evidence["logical_stage_count"],
        "physical_launch_count" => evidence["physical_launch_count"],
        "physical_bank_count" => evidence["physical_bank_count"],
        "lowering_identity" => evidence["lowering_identity"],
        "physical_phase_identities" => evidence["physical_phase_identities"],
        "logical_stage_identities" => evidence["logical_stage_identities"],
        "operation_fact_count" => evidence["operation_fact_count"],
        "operation_fact_stage_counts" => evidence["operation_fact_stage_counts"],
        "operation_fact_purpose_counts" => evidence["operation_fact_purpose_counts"],
        "admitted_operation_fact_count" => evidence["admitted_operation_fact_count"],
        "operation_methods_current" => evidence["operation_methods_current"],
        "operation_world_current" => evidence["operation_world_current"],
        "selection_succeeded" => selection_succeeded,
        "backend" => "cpu",
        "backend_type" => string(typeof(KernelAbstractions.CPU())),
        "hardware" => Sys.CPU_NAME,
        "machine" => Sys.MACHINE,
        "kernel" => string(Sys.KERNEL),
        "cpu_threads" => Sys.CPU_THREADS,
        "total_memory_bytes" => Sys.total_memory(),
        "julia_version" => string(VERSION),
        "kernelabstractions_version" => string(Base.pkgversion(KernelAbstractions)),
        "corepotts_version" => string(Base.pkgversion(CorePotts)),
        "threads" => Threads.nthreads(),
        "compile_mode" => "ordinary --compile=yes --optimize=2",
        "julia_options" => Dict(
            "startupfile" => Int(options.startupfile),
            "compile_enabled" => Int(options.compile_enabled),
            "opt_level" => Int(options.opt_level),
            "use_compiled_modules" => Int(options.use_compiled_modules),
            "project" => something(Base.active_project(), ""),
        ),
        "program_arguments" => copy(ARGS),
        "cache_state" => "fresh process; package caches may be precompiled; workload methods cold",
        "package_load_seconds" => _Compiler_PACKAGE_LOAD_SECONDS,
        "host_compile_seconds_total" => total_host_compile,
        "planning_through_first_execution_seconds" =>
            initialization["elapsed_seconds"] +
            first_request_index["elapsed_seconds"] +
            first_selection["elapsed_seconds"],
        "fixture_construction" => fixture_construction,
        "initialization" => initialization,
        "first_request_index" => first_request_index,
        "first_selection" => first_selection,
        "warm_execution" => warm,
    )
    TOML.print(stdout, report; sorted = true)
    return nothing
end

function _main()
    warm_samples = parse(Int, _argument("warm-samples", "7"))
    fixture, fixture_construction = _timing(_flagship_fixture)
    runtime, initialization = _timing() do
        CorePotts.initialize_program(
            fixture.program,
            fixture.initial,
            Float64[],
            UInt64(0x6c6d305f73656564),
            UInt32(1),
        )
    end
    workspace = runtime.lifecycle_workspace
    CorePotts._reset_lifecycle_workspace!(workspace)
    _, first_request_index = _timing() do
        _run_request_index!(runtime, workspace)
    end
    selection_succeeded, first_selection = _timing() do
        _run_selection_phase!(runtime, workspace)
    end
    selection_succeeded || error("CorePotts flagship selection failed")
    warm = _warm_samples(runtime, warm_samples)

    compaction = runtime.engine_workspace.lifecycle_compaction
    prepared_banks = compaction.selection
    evidence = _cold_evidence_summary(prepared_banks)
    return _emit_flagship_report(
        evidence, selection_succeeded, fixture_construction, initialization,
        first_request_index, first_selection, warm,
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && _main()
