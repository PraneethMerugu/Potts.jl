#!/usr/bin/env julia

# Longitudinal compiler, payload, and allocation evidence for the public
# maintained-site aggregate path. Raw counts and timings are observations, not
# machine-independent acceptance thresholds.

const _REPORT_PROCESS_STARTED_NS = time_ns()
const _REPORT_PACKAGE_LOAD = @timed begin
    @eval import Chairmarks
    @eval import CorePotts
    @eval import DynamicQuantities
    @eval import KernelAbstractions
    @eval import LocalMath
    @eval import ModelingToolkitBase
    @eval import Potts
    @eval import SHA
    @eval import StaticArrays
    @eval import SymbolicIndexingInterface
    @eval import Symbolics
end
const _REPORT_PACKAGE_LOAD_FINISHED_NS = time_ns()

include(joinpath(@__DIR__, "compiler_contract_schema.jl"))

function _aggregate_source(; author_prefix = nothing, gain_default = 2.0)
    author_name(name) = author_prefix === nothing ?
        name : Symbol(author_prefix, :_, name)
    gain = Symbolics.variable(author_name(:gain))
    signal = Symbolics.variable(author_name(:signal))
    amount = Symbolics.variable(author_name(:amount))
    repeated = Symbolics.variable(author_name(:repeated))
    lattice = Potts.LatticeDomain(
        author_name(:space);
        shape = (2, 2), spacing = (1.0, 1.0),
        boundary = Potts.Closed(), max_cells = 3,
    )
    kind = Potts.CellKind(
        author_name(:cell); extinction = Potts.ForbidExtinction(),
    )
    medium = Potts.MediumKind(author_name(:medium))
    declarations = Potts.scoped(
            Potts.sites(lattice), author_name(:locations),
        ) do site
        consumers = Potts.scoped(
                Potts.cells(kind), author_name(:owners),
            ) do cell
            quantity = Potts.aggregate(gain * signal; over = site, by = cell)
            Potts.StatementSet((
                Potts.CellState(amount; initial = 0.0),
                Potts.CellState(repeated; initial = 0.0),
                Potts.Synchronous(
                    author_name(:measure), Potts.Assign(amount, quantity),
                ),
                Potts.Synchronous(
                    author_name(:measure_again),
                    Potts.Assign(repeated, quantity),
                ),
            ))
        end
        Potts.StatementSet((
            Potts.FieldState(signal; initial = 0.0), consumers...,
        ))
    end
    system = Potts.PottsSystem(
        name = author_name(:maintained_signal),
        statements = Potts.StatementSet((
            lattice, kind, medium, declarations...,
            Potts.ProposalConstraint(author_name(:fixed_ownership), false),
            Potts.Protocol(
                Potts.Sweep(; temperature = 0.0); name = author_name(:main),
            ),
        )),
        unknowns = (signal, amount, repeated),
        parameters = (gain,),
    )
    labels = Int32[1 2; 1 0]
    values = reshape(Float32[1, 2, 3, 4], 2, 2)
    initial = Potts.PottsInitialState(
        ownership = Potts.LabelledCells(
            labels; cells = [kind, kind], medium,
        ),
        values = (signal => values,),
    )
    return (;
        system, initial, signal, amount, repeated, gain, labels, gain_default,
    )
end

function _problem(source)
    return Potts.PottsProblem(
        source.system, source.initial, (0, typemax(Int));
        p = (source.gain => source.gain_default,), seed = 17,
    )
end

function _aggregate_lowering_arguments(system)
    ir = Potts._analyze_completed_system(system)
    manifest = Potts._scheduled_data(system).parameters
    state_layout, state_handles =
        Potts._state_layout(ir, system, manifest, Float32)
    draw_handles = Potts._draw_operation_handles(ir)
    history_descriptors = Potts._lower_history_descriptors(
        ir, Float32, state_handles, state_layout,
    )
    keywords = (; state_layout, history_descriptors)
    positional = (ir, manifest, Float32, state_handles, draw_handles)
    return (; keywords, positional)
end

function _aggregate_kwcall(arguments)
    return Core.kwcall(
        arguments.keywords,
        Potts._lower_site_aggregate_trackers,
        arguments.positional...,
    )
end

function _aggregate_body_call(arguments)
    call_arguments = (
        arguments.keywords.state_layout,
        arguments.keywords.history_descriptors,
        Potts._lower_site_aggregate_trackers,
        arguments.positional...,
    )
    for name in names(Potts; all = true)
        startswith(String(name), "#_lower_site_aggregate_trackers#") ||
            continue
        function_value = getfield(Potts, name)
        applicable(function_value, call_arguments...) || continue
        return function_value, call_arguments
    end
    error("could not resolve the aggregate lowering keyword body")
end

function _observed_identity_count(values)
    representatives = Any[]
    for value in values
        any(existing -> existing === value, representatives) ||
            push!(representatives, value)
    end
    return length(representatives)
end

function _specialization_variant(
        label, function_value, call_arguments, baseline_instance, baseline_typed,
        aggregate_result, core_program,
    )
    argument_types = Tuple{map(typeof, call_arguments)...}
    typed_results = Base.code_typed(
        function_value, argument_types; optimize = true, debuginfo = :none,
    )
    instances = Base.method_instances(
        function_value, argument_types, Base.get_world_counter(),
    )
    instance = only(instances)
    info, return_type = only(typed_results)
    baseline_info, baseline_return = baseline_typed
    method = instance.def
    return Dict{String, Any}(
        "label" => label,
        "typed_method_matches" => length(typed_results),
        "method_instance_matches" => length(instances),
        "specialization_signature" => string(instance.specTypes),
        "same_method_instance_as_baseline" => instance === baseline_instance,
        "same_method_definition_as_baseline" =>
            method === baseline_instance.def,
        "typed_ir_equal_to_baseline" =>
            info.code == baseline_info.code &&
            info.ssavaluetypes == baseline_info.ssavaluetypes &&
            return_type == baseline_return,
        "typed_statements" => length(info.code),
        "typed_calls" => sum(_compiler_call_count, info.code; init = 0),
        "return_type" => string(return_type),
        "aggregate_descriptor_count" => length(aggregate_result.descriptors),
        "aggregate_descriptor_types" =>
            collect(string.(typeof.(aggregate_result.descriptors))),
        "aggregate_handle_container_type" =>
            string(typeof(aggregate_result.handles)),
        "core_program_type" => string(typeof(core_program)),
        "core_tracker_plan_type" => string(typeof(core_program.tracker_plan)),
        "method" => Dict(
            "name" => string(method.name),
            "module" => string(method.module),
            "file" => string(method.file),
            "line" => method.line,
            "declared_signature" => string(method.sig),
        ),
        "_instance" => instance,
    )
end

function _aggregate_specialization_report(variants)
    functions_and_calls = map(
        variant -> _aggregate_body_call(variant.arguments), variants,
    )
    function_value = first(first(functions_and_calls))
    all(pair -> first(pair) === function_value, functions_and_calls) || error(
        "aggregate variants resolved different lowering body functions",
    )
    calls = map(last, functions_and_calls)
    results = map(variant -> _aggregate_kwcall(variant.arguments), variants)
    baseline_types = map(typeof, first(calls))
    all(call -> map(typeof, call) == baseline_types, calls) || error(
        "author or numerical values changed aggregate lowering argument types",
    )
    baseline_type_tuple = Tuple{baseline_types...}
    baseline_instance = only(Base.method_instances(
        function_value, baseline_type_tuple, Base.get_world_counter(),
    ))
    baseline_typed = only(Base.code_typed(
        function_value, baseline_type_tuple;
        optimize = true, debuginfo = :none,
    ))
    records = map(eachindex(variants)) do index
        variant = variants[index]
        _specialization_variant(
            variant.label, function_value, calls[index], baseline_instance,
            baseline_typed, results[index], variant.plan.core_program,
        )
    end
    instances = [pop!(record, "_instance") for record in records]
    return Dict{String, Any}(
        "scope" => "explicitly exercised variants in this fresh process",
        "observed_unique_method_instances" =>
            _observed_identity_count(instances),
        "observed_method_definitions" => _observed_identity_count(
            map(instance -> instance.def, instances),
        ),
        "author_rename_reuses_baseline_instance" =>
            instances[2] === instances[1],
        "numerical_default_reuses_baseline_instance" =>
            instances[3] === instances[1],
        "all_variants_share_core_program_type" =>
            all(
                variant -> typeof(variant.plan.core_program) ===
                    typeof(first(variants).plan.core_program),
                variants,
            ),
        "author_rename_shares_core_program_type" =>
            typeof(variants[2].plan.core_program) ===
                typeof(variants[1].plan.core_program),
        "numerical_default_shares_core_program_type" =>
            typeof(variants[3].plan.core_program) ===
                typeof(variants[1].plan.core_program),
        "author_rename_shares_tracker_plan_type" =>
            typeof(variants[2].plan.core_program.tracker_plan) ===
                typeof(variants[1].plan.core_program.tracker_plan),
        "numerical_default_shares_tracker_plan_type" =>
            typeof(variants[3].plan.core_program.tracker_plan) ===
                typeof(variants[1].plan.core_program.tracker_plan),
        "variants" => records,
    )
end

function _fingerprint(path)
    isfile(path) || return Dict("path" => path, "sha256" => "missing")
    return Dict(
        "path" => path,
        "sha256" => bytes2hex(SHA.sha256(read(path))),
    )
end

function _git_directory(path)
    marker = joinpath(path, ".git")
    isdir(marker) && return marker
    isfile(marker) || return nothing
    line = strip(read(marker, String))
    startswith(line, "gitdir: ") || return nothing
    target = strip(line[9:end])
    return normpath(isabspath(target) ? target : joinpath(path, target))
end

function _git_revision(path)
    directory = _git_directory(path)
    directory === nothing && return "unavailable"
    head = strip(read(joinpath(directory, "HEAD"), String))
    startswith(head, "ref: ") || return head
    reference = strip(head[6:end])
    loose = joinpath(directory, reference)
    isfile(loose) && return strip(read(loose, String))
    common = isfile(joinpath(directory, "commondir")) ?
        normpath(joinpath(
            directory, strip(read(joinpath(directory, "commondir"), String)),
        )) : directory
    common_loose = joinpath(common, reference)
    isfile(common_loose) && return strip(read(common_loose, String))
    packed = joinpath(common, "packed-refs")
    isfile(packed) || return "unavailable"
    for line in eachline(packed)
        startswith(line, '#') && continue
        fields = split(line)
        length(fields) == 2 && fields[2] == reference && return fields[1]
    end
    return "unavailable"
end

function _dependency_record(package)
    source = pkgdir(package)
    return Dict(
        "version" => string(Base.pkgversion(package)),
        "source_path" => source,
        "git_revision" => _git_revision(source),
    )
end

function _timed_record(result)
    return Dict{String, Any}(
        "seconds" => result.time,
        "allocation_bytes" => result.bytes,
        "gc_seconds" => result.gctime,
        "compile_seconds" => result.compile_time,
        "recompile_seconds" => result.recompile_time,
    )
end

function _chairmarks_record(benchmark)
    samples = benchmark.samples
    return Dict{String, Any}(
        "sample_count" => length(samples),
        "minimum_seconds" => minimum(sample.time for sample in samples),
        "minimum_allocations" => minimum(sample.allocs for sample in samples),
        "minimum_allocation_bytes" => minimum(sample.bytes for sample in samples),
        "samples" => [
            Dict(
                "seconds" => sample.time,
                "allocations" => sample.allocs,
                "allocation_bytes" => sample.bytes,
                "compile_fraction" => sample.compile_fraction,
                "recompile_fraction" => sample.recompile_fraction,
            ) for sample in samples
        ],
    )
end

function _aggregate_output_payload(aggregate_result, plan)
    descriptor_origins = [
        Dict(
            "type" => string(typeof(descriptor)),
            "summary_bytes" => Base.summarysize(descriptor),
            "semantic_origin" =>
                "analyzed aggregate fact and normalized contribution",
        ) for descriptor in aggregate_result.descriptors
    ]
    return Dict{String, Any}(
        "aggregate_descriptors" => descriptor_origins,
        "aggregate_handles" => Dict(
            "type" => string(typeof(aggregate_result.handles)),
            "summary_bytes" => Base.summarysize(aggregate_result.handles),
            "semantic_origin" =>
                "node-aligned qualified tracker handle table",
        ),
        "core_tracker_plan" => Dict(
            "type" => string(typeof(plan.core_program.tracker_plan)),
            "summary_bytes" => Base.summarysize(plan.core_program.tracker_plan),
            "semantic_origin" =>
                "normalized aggregate descriptors plus shared tracker requirements",
        ),
        "core_program" => Dict(
            "type" => string(typeof(plan.core_program)),
            "summary_bytes" => Base.summarysize(plan.core_program),
            "semantic_origin" =>
                "sole prepared Core execution program after author identity erasure",
        ),
    )
end

function _report_environment(revision_label, evidence_reason)
    project = something(Base.active_project(), "")
    manifest = isempty(project) ? "" : joinpath(dirname(project), "Manifest.toml")
    return Dict{String, Any}(
        "revision_label" => revision_label,
        "evidence_method" => "optimized_code_typed_fallback",
        "kaimon_unavailable_reason" => evidence_reason,
        "julia" => string(VERSION),
        "project" => _fingerprint(project),
        "manifest" => _fingerprint(manifest),
        "potts" => _dependency_record(Potts),
        "corepotts" => _dependency_record(CorePotts),
        "localmath" => _dependency_record(LocalMath),
        "kernelabstractions" => _dependency_record(KernelAbstractions),
        "dynamicquantities" => _dependency_record(DynamicQuantities),
        "modelingtoolkitbase" => _dependency_record(ModelingToolkitBase),
        "symbolics" => _dependency_record(Symbolics),
        "staticarrays" => _dependency_record(StaticArrays),
        "chairmarks" => _dependency_record(Chairmarks),
    )
end

function resolved_aggregate_compiler_report(;
        revision_label = "not_supplied",
        evidence_reason = "not_supplied",
    )
    authoring = @timed _aggregate_source()
    source = authoring.value
    problem_construction = @timed _problem(source)
    problem = problem_construction.value
    aggregate_arguments = @timed _aggregate_lowering_arguments(problem.system)
    aggregate_lowering = @timed _aggregate_kwcall(aggregate_arguments.value)
    execution_lowering = @timed Potts._lower_scheduled_execution_plan(
        problem.system, Potts.CheckerboardSweepCPM(), Potts.CPUBackend(),
        Float32,
    )
    plan = execution_lowering.value
    preparation = @timed Potts.init(
        problem, Potts.CheckerboardSweepCPM(); scalar_type = Float32,
        save_everystep = false,
    )
    integrator = preparation.value
    first_execution = @timed Potts.step!(integrator)
    Array(integrator.u[:amount]) == Float32[6, 6, 0] || error(
        "resolved aggregate benchmark failed its independent numerical oracle",
    )
    warm_public = Chairmarks.@be Potts.step!($integrator) evals=1 samples=7

    core_integrator = Potts.init(
        _problem(_aggregate_source()), Potts.CheckerboardSweepCPM();
        scalar_type = Float32, save_everystep = false,
    )
    CorePotts.advance_mcs!(core_integrator.runtime)
    warm_core = Chairmarks.@be CorePotts.advance_mcs!($core_integrator.runtime) evals=1 samples=7

    update_source = _aggregate_source()
    update_integrator = Potts.init(
        _problem(update_source), Potts.CheckerboardSweepCPM();
        scalar_type = Float32, save_everystep = false,
    )
    source_setter = SymbolicIndexingInterface.setu(
        update_integrator, update_source.signal,
    )
    source_values = fill(5.0f0, 2, 2)
    first_source_update = @timed source_setter(update_integrator, source_values)
    warm_source_update = Chairmarks.@be $source_setter($update_integrator, $source_values) evals=1 samples=7
    parameter_setter = SymbolicIndexingInterface.setp(
        update_integrator, update_source.gain,
    )
    first_parameter_update = @timed parameter_setter(update_integrator, 3.0f0)
    warm_parameter_update = Chairmarks.@be $parameter_setter($update_integrator, 3.0f0) evals=1 samples=7

    rename_problem = _problem(_aggregate_source(author_prefix = :renamed))
    numerical_problem = _problem(_aggregate_source(gain_default = 5.0))
    variants = (
        (label = "baseline", arguments = aggregate_arguments.value, plan),
        (
            label = "author_only_rename",
            arguments = _aggregate_lowering_arguments(rename_problem.system),
            plan = Potts._lower_scheduled_execution_plan(
                rename_problem.system, Potts.CheckerboardSweepCPM(),
                Potts.CPUBackend(), Float32,
            ),
        ),
        (
            label = "numerical_default_change",
            arguments = _aggregate_lowering_arguments(numerical_problem.system),
            plan = Potts._lower_scheduled_execution_plan(
                numerical_problem.system, Potts.CheckerboardSweepCPM(),
                Potts.CPUBackend(), Float32,
            ),
        ),
    )
    aggregate_body, boundary_call =
        _aggregate_body_call(aggregate_arguments.value)
    empty_origins(count) = ntuple(_ -> Dict{String, String}(), count)
    return Dict{String, Any}(
        "schema_version" => 1,
        "profile" => "potts_resolved_aggregate_compiler_contract",
        "environment" => _report_environment(revision_label, evidence_reason),
        "stages" => Dict(
            "process_to_package_load_seconds" =>
                (_REPORT_PACKAGE_LOAD_FINISHED_NS -
                    _REPORT_PROCESS_STARTED_NS) / 1.0e9,
            "process_to_runtime_measurements_seconds" =>
                (time_ns() - _REPORT_PROCESS_STARTED_NS) / 1.0e9,
            "package_load" => _timed_record(_REPORT_PACKAGE_LOAD),
            "public_authoring" => _timed_record(authoring),
            "problem_completion_and_scheduling" =>
                _timed_record(problem_construction),
            "aggregate_argument_binding" => _timed_record(aggregate_arguments),
            "aggregate_recipe_lowering" => _timed_record(aggregate_lowering),
            "complete_execution_lowering" => _timed_record(execution_lowering),
            "runtime_preparation" => _timed_record(preparation),
            "first_cpu_execution" => _timed_record(first_execution),
            "first_source_update" => _timed_record(first_source_update),
            "first_parameter_update" => _timed_record(first_parameter_update),
            "warm_public_execution" => _chairmarks_record(warm_public),
            "warm_core_execution" => _chairmarks_record(warm_core),
            "warm_source_update" => _chairmarks_record(warm_source_update),
            "warm_parameter_update" => _chairmarks_record(warm_parameter_update),
        ),
        "aggregate_recipe_lowering" => _compiler_host_boundary_record(
            aggregate_body,
            (
                "state_layout", "history_descriptors", "lowering_function",
                "analyzed_ir", "parameter_manifest", "scalar_type",
                "state_handles", "draw_handles",
            ),
            boundary_call,
            (
                "normalized state storage layout",
                "normalized retained-history descriptors",
                "sole maintained-site aggregate lowering owner",
                "validated normalized semantic graph and analyzed facts",
                "scheduled parameter identities and reference units",
                "selected runtime scalar representation",
                "qualified runtime state bindings",
                "normalized addressed-random bindings",
            ),
            (
                Dict(
                    "entries" =>
                        "normalized state records and selected physical storage",
                ),
                Dict(
                    "entries" =>
                        "normalized retained-history declarations",
                ),
                Dict{String, String}(),
                Dict(
                    "source" => "completed source ownership graph",
                    "graph" => "normalized semantic expression graph",
                    "facts" => "node-aligned analyzed semantic facts",
                ),
                Dict(
                    "entries" => "scheduled public parameter declarations",
                    "reference_units" => "completion reference-unit contract",
                ),
                Dict{String, String}(),
                Dict(
                    "entries" => "normalized runtime state-layout bindings",
                ),
                Dict(
                    "entries" => "normalized addressed-random operations",
                ),
            );
            role = "changed resolved aggregate recipe-lowering boundary",
            signature = "keyword body of _lower_site_aggregate_trackers",
        ),
        "complete_execution_lowering" => _compiler_host_boundary_record(
            Potts._lower_scheduled_execution_plan,
            ("scheduled_system", "algorithm", "backend", "scalar_type"),
            (
                problem.system, Potts.CheckerboardSweepCPM(),
                Potts.CPUBackend(), Float32,
            ),
            (
                "completed and structurally scheduled public model",
                "selected public CPM algorithm",
                "selected public execution backend",
                "selected runtime scalar representation",
            ),
            (
                Dict(
                    "completion" => "validated completed semantic ownership",
                    "schedule" => "structurally scheduled public statements",
                ),
                Dict{String, String}(),
                Dict{String, String}(),
                Dict{String, String}(),
            );
            role = "host orchestration boundary containing aggregate lowering",
            signature = "_lower_scheduled_execution_plan",
        ),
        "unchanged_seed_normalization" => _compiler_host_boundary_record(
            Potts._normalize_seed,
            ("seed",),
            (UInt64(17),),
            ("public stochastic trajectory identity",),
            empty_origins(1);
            role = "unchanged public problem-construction leaf control",
            signature = "_normalize_seed",
        ),
        "specialization" => _aggregate_specialization_report(variants),
        "lowered_payload" =>
            _aggregate_output_payload(aggregate_lowering.value, plan),
        "claims" => Dict(
            "whole_mcs_zero_allocation" => false,
            "device_backend_qualified_by_this_report" => false,
            "timings_are_acceptance_thresholds" => false,
        ),
    )
end

function _argument(name, default)
    prefix = "--$name="
    index = findfirst(startswith(prefix), ARGS)
    return index === nothing ? default : split(ARGS[index], "="; limit = 2)[2]
end


function _main_resolved_aggregate_compiler_report()
    report = resolved_aggregate_compiler_report(
        ; revision_label = _argument("revision-label", "not_supplied"),
        evidence_reason = _argument("evidence-reason", "not_supplied"),
    )
    output = _argument("output", "")
    if isempty(output)
        emit_resolved_aggregate_compiler_report(report)
    else
        open(output, "w") do io
            emit_resolved_aggregate_compiler_report(report; io)
        end
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) &&
    _main_resolved_aggregate_compiler_report()
