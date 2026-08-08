backend, prototype, backend_name = qualification_backend()
host_context = QualificationContext(
    Float32[1, 1, 1, 1], QUALIFICATION_SEED
)
device_context = qualification_context(backend_name)

println("backend=", backend_name)
println("rng=", qualify_rng_words(backend, backend_name))

builders = (
    :recursive_typed_tree => recursive_candidate,
    :bounded_nary_typed_tree => nary_candidate,
    :static_ssa => ssa_candidate,
)
executions = (
    :corepotts_tags => TagExecution(),
    :concrete_callables => CallableExecution(),
)
fixtures = (
    semantic_fixture(16),
    semantic_fixture(32),
    semantic_fixture(64),
    semantic_fixture(64; identity_wrappers = 12),
    semantic_fixture(64; identity_wrappers = 44),
)
selected_failures = String[]
selected_shape_results = NamedTuple[]

for (execution_label, execution) in executions
    for fixture in fixtures
        for (label, builder) in builders
            try
                result = qualify_candidate(
                    label,
                    builder,
                    execution_label,
                    execution,
                    fixture,
                    host_context,
                    device_context,
                    backend,
                    prototype,
                )
                if execution_label === :concrete_callables &&
                        label === :bounded_nary_typed_tree
                    push!(selected_shape_results, result)
                end
                println("candidate=", result)
            catch error
                if execution_label === :concrete_callables &&
                        label === :bounded_nary_typed_tree
                    push!(
                        selected_failures,
                        "candidate nodes=$(fixture.node_count) " *
                        "depth=$(fixture.depth): " * sprint(showerror, error),
                    )
                end
                println("candidate_failure=", (
                    execution = execution_label,
                    representation = label,
                    semantic_nodes = fixture.node_count,
                    semantic_depth = fixture.depth,
                    error_type = nameof(typeof(error)),
                ))
            end
        end
    end
end


selected_depth_four = sort(
    filter(result -> result.semantic_depth == 4, selected_shape_results);
    by = result -> result.semantic_nodes,
)
length(selected_depth_four) == 3 || push!(
    selected_failures,
    "selected evaluator did not produce all 16/32/64-node depth-four results",
)
if length(selected_depth_four) == 3
    smallest = first(selected_depth_four)
    largest = last(selected_depth_four)
    largest.code_statements <= 4 * smallest.code_statements || push!(
        selected_failures,
        "selected evaluator host statement growth exceeded the 4x bound",
    )
    largest.host_llvm_bytes <= 4 * smallest.host_llvm_bytes || push!(
        selected_failures,
        "selected evaluator host LLVM growth exceeded the 4x bound",
    )
    if !ismissing(smallest.device_llvm_bytes) &&
            !ismissing(largest.device_llvm_bytes)
        largest.device_llvm_bytes <= 4 * smallest.device_llvm_bytes || push!(
            selected_failures,
            "selected evaluator device LLVM growth exceeded the 4x bound",
        )
    end
end

# Occurrence growth: one real homogeneous descriptor group at N=1/32/1024.
growth_fixture = semantic_fixture(32)
for (execution_label, execution) in executions
    for (label, builder) in builders
        try
            candidate = builder(growth_fixture, execution)
            signature_hashes = String[]
            results = NamedTuple[]
            for count in (1, 32, 1024)
                occurrences = qualification_occurrences(count)
                group = adapt_qualification_group(
                    qualification_group(candidate, occurrences, 1)
                )
                expected = Float32[
                    canonical_value(growth_fixture, item, host_context)
                    for item in occurrences
                ]
                launch = _launch_one(
                    group,
                    device_context,
                    backend,
                    prototype,
                    expected,
                )
                push!(signature_hashes, launch.signature_hash)
                push!(results, (
                    occurrences = count,
                    first_launch_seconds = launch.first_launch_seconds,
                    warm_launch_seconds = launch.warm_launch_seconds,
                    signature_hash = launch.signature_hash,
                ))
            end
            length(unique(signature_hashes)) == 1 ||
                error("occurrence growth changed a specialization signature")
            println("occurrence_growth=", (
                execution = execution_label,
                representation = label,
                fixed_specialization = true,
                results = Tuple(results),
            ))
        catch error
            if execution_label === :concrete_callables &&
                    label === :bounded_nary_typed_tree
                push!(
                    selected_failures,
                    "occurrence growth: " * sprint(showerror, error),
                )
            end
            println("occurrence_growth_failure=", (
                execution = execution_label,
                representation = label,
                error_type = nameof(typeof(error)),
            ))
        end
    end
end

# Group growth: actual heterogeneous tuples of G=1/4/8 launches at fixed N=32.
for (execution_label, execution) in executions
    for (label, builder) in builders
        try
            candidate = builder(growth_fixture, execution)
            occurrences = qualification_occurrences(32)
            results = Tuple(
                _aggregate_group_measurement(
                    candidate,
                    occurrences,
                    group_count,
                    host_context,
                    device_context,
                    backend,
                    prototype,
                    growth_fixture,
                )
                for group_count in (1, 4, 8)
            )
            getfield.(results, :specialization_count) == (1, 4, 8) ||
                error("actual group specialization count is incorrect")
            if execution_label === :concrete_callables &&
                    label === :bounded_nary_typed_tree
                last(results).runner_statements <=
                    8 * first(results).runner_statements || error(
                    "selected evaluator group runner growth exceeded the 8x bound"
                )
                if !ismissing(first(results).device_llvm_bytes)
                    last(results).device_llvm_bytes <=
                        9 * first(results).device_llvm_bytes || error(
                        "selected evaluator group device growth exceeded the 9x bound"
                    )
                end
            end
            println("group_growth=", (
                execution = execution_label,
                representation = label,
                results,
            ))
        catch error
            if execution_label === :concrete_callables &&
                    label === :bounded_nary_typed_tree
                push!(
                    selected_failures,
                    "group growth: " * sprint(showerror, error),
                )
            end
            println("group_growth_failure=", (
                execution = execution_label,
                representation = label,
                error_type = nameof(typeof(error)),
            ))
        end
    end
end

isempty(selected_failures) || error(
    "selected concrete-callable bounded-nary qualification failed:\n" *
    join(selected_failures, "\n"),
)
