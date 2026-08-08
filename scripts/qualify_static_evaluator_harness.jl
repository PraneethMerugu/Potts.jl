struct QualificationDescriptor{E, O, A, R}
    evaluator::E
    occurrence::O
    access::A
    role::R
end

CorePotts.descriptor_state_requirements(::QualificationDescriptor) = ()
CorePotts.descriptor_workspace_requirements(::QualificationDescriptor) = ()
CorePotts.descriptor_resource_access(descriptor::QualificationDescriptor) =
    descriptor.access
CorePotts.descriptor_stage(::QualificationDescriptor) = :proposal
CorePotts.descriptor_role(descriptor::QualificationDescriptor) =
    descriptor.role
CorePotts.descriptor_dependencies(::QualificationDescriptor) = ()
CorePotts.descriptor_support(::QualificationDescriptor) =
    CorePotts.DescriptorSupport(true, true, true, true)
@inline qualification_descriptor_evaluate(
    descriptor::QualificationDescriptor, context
) = candidate_evaluate(
    descriptor.evaluator, descriptor.occurrence, context
)

@kernel function qualification_descriptor_group_probe_kernel!(
        output,
        launch,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(launch.instances)
        descriptor = @inbounds launch.instances[index]
        @inbounds output[index] = qualification_descriptor_evaluate(
            descriptor, context
        )
    end
end
CorePotts.descriptor_adapt(to, descriptor::QualificationDescriptor) =
    descriptor
CorePotts.descriptor_evaluator_node_count(
    descriptor::QualificationDescriptor
) = representation_node_count(descriptor.evaluator)
CorePotts.descriptor_source_handle(
    descriptor::QualificationDescriptor
) = descriptor.occurrence.source_handle
CorePotts.descriptor_checkpoint_policy(::QualificationDescriptor) =
    :reconstruct_from_executable
CorePotts.descriptor_checkpoint_encode(::QualificationDescriptor) = nothing
CorePotts.descriptor_checkpoint_reconstruct(
    descriptor::QualificationDescriptor, ::Nothing
) = descriptor
CorePotts.descriptor_inspection(
    descriptor::QualificationDescriptor
) = (
    family = :qualification_descriptor,
    source_handle = descriptor.occurrence.source_handle,
)

function _group_variant(index::Int)
    footprints = (
        CorePotts.EmptyFootprint(),
        CorePotts.ProposalContextFootprint(),
        CorePotts.OwnerFootprint(),
        CorePotts.CompilerSPI.FiniteSpatialFootprint(
            CorePotts.CompilerSPI.IterationSiteFootprintAnchor(),
            (Int8(index),),
        ),
    )
    roles = (
        CorePotts.HamiltonianRole(),
        CorePotts.ProposalDriveRole(),
        CorePotts.ProposalModifierRole(),
        CorePotts.ProposalConstraintRole(),
    )
    footprint = footprints[mod1(index, length(footprints))]
    role = roles[mod1(div(index - 1, length(footprints)) + 1, length(roles))]
    return CorePotts.CompilerSPI.ResourceAccess(
        (),
        (),
        footprint,
        CorePotts.CompilerSPI.EmptyFootprint(),
        CorePotts.CompilerSPI.NoWriteAccess(),
    ), role
end

function qualification_group(candidate, occurrences, index::Int)
    access, role = _group_variant(index)
    descriptors = [
        QualificationDescriptor(candidate, occurrence, access, role)
        for occurrence in occurrences
    ]
    descriptor_type = eltype(descriptors)
    strategy = CorePotts.DescriptorKernelStrategy{
        descriptor_type,
        typeof(candidate),
        typeof(access.footprint),
        typeof(role),
        Val{:qualification},
    }()
    launch = CorePotts.DescriptorLaunch(
        strategy, descriptors, (), ()
    )
    return CorePotts.DescriptorGroup(
        launch,
        (
            descriptor = :QualificationDescriptor,
            evaluator = nameof(typeof(candidate)),
            footprint = nameof(typeof(access.footprint)),
            role = nameof(typeof(role)),
            stage = :proposal,
        ),
    )
end

function adapt_qualification_group(group)
    USE_METAL || return group
    launch = group.launch
    adapted_instances = CorePotts.Adapt.adapt(
        Metal.MtlArray, launch.instances
    )
    return CorePotts.DescriptorGroup(
        CorePotts.DescriptorLaunch(
            launch.strategy,
            adapted_instances,
            launch.state_handles,
            launch.workspace_handles,
        ),
        group.split,
    )
end

function qualification_backend()
    if USE_METAL
        Metal.functional() ||
            error("the selected Metal witness is not functional")
        prototype = Metal.zeros(Float32, 1)
        return KA.get_backend(prototype), prototype, :metal
    end
    prototype = zeros(Float32, 1)
    return KA.CPU(), prototype, :cpu
end

function qualification_context(backend_name)
    parameters = Float32[1, 1, 1, 1]
    backend_name === :metal &&
        (parameters = Metal.MtlArray(parameters))
    return QualificationContext(parameters, QUALIFICATION_SEED)
end

function _warm_median(samples)
    ordered = sort(samples)
    return ordered[cld(length(ordered), 2)]
end

function _signature_hash(value)
    return bytes2hex(sha256(string(value)))[1:16]
end

function _typed_metrics(candidate, occurrence, context)
    signature = (
        typeof(candidate),
        typeof(occurrence),
        typeof(context),
    )
    compile_seconds = @elapsed precompile(
        candidate_evaluate, signature
    )
    typed = only(code_typed(
        candidate_evaluate, signature; optimize = true
    ))
    code = first(typed)
    slot_types = code.slottypes === nothing ? Any[] : code.slottypes
    io = IOBuffer()
    code_llvm(
        io,
        candidate_evaluate,
        signature;
        optimize = true,
        debuginfo = :none,
    )
    return (
        compile_seconds,
        inferred = last(typed),
        code_statements = length(code.code),
        any_slots = count(==(Any), slot_types),
        host_llvm_bytes = sizeof(take!(io)),
    )
end

device_llvm_bytes(kernel, output, launch, context) = missing
pipeline_metrics(output, launch, context) = (
    static_threadgroup_memory = missing,
    maximum_threads = missing,
    execution_width = missing,
    registers = missing,
)

if USE_METAL
    @eval begin
        function device_llvm_bytes(kernel, output, launch, context)
            io = IOBuffer()
            Metal.@device_code_llvm io=io kernel(
                output, launch, context; ndrange = length(output)
            )
            KA.synchronize(KA.get_backend(output))
            return sizeof(take!(io))
        end

        function _qualification_metal_kernel!(output, launch, context)
            index = Int(Metal.thread_position_in_grid_1d())
            if index <= length(output)
                @inbounds output[index] =
                    qualification_descriptor_evaluate(
                        launch.instances[index], context
                    )
            end
            return nothing
        end

        function pipeline_metrics(output, launch, context)
            kernel = Metal.@metal launch=false _qualification_metal_kernel!(
                output, launch, context
            )
            return (
                static_threadgroup_memory = kernel.tgmem,
                maximum_threads = kernel.maxthreads,
                execution_width = kernel.exec_width,
                registers = missing,
            )
        end
    end
end

function _launch_one(
        group,
        context,
        backend,
        prototype,
        expected,
    )
    launch = group.launch
    output = similar(prototype, Float32, length(launch.instances))
    kernel = qualification_descriptor_group_probe_kernel!(backend)
    first_launch = @elapsed begin
        kernel(output, launch, context; ndrange = length(output))
        KA.synchronize(backend)
    end
    warm_samples = Float64[]
    for _ in 1:10
        push!(warm_samples, @elapsed begin
            kernel(output, launch, context; ndrange = length(output))
            KA.synchronize(backend)
        end)
    end
    actual = Array(output)
    reinterpret(UInt32, actual) == reinterpret(UInt32, expected) ||
        error("qualification launch changed ordered stochastic semantics")
    signature = (
        evaluator = typeof(first(Array(launch.instances)).evaluator),
        descriptor = eltype(launch.instances),
        launch = typeof(launch),
        kernel_arguments = (
            typeof(output), typeof(launch), typeof(context)
        ),
    )
    return (
        first_launch_seconds = first_launch,
        warm_launch_seconds = _warm_median(warm_samples),
        device_llvm_bytes =
            device_llvm_bytes(kernel, output, launch, context),
        pipeline = pipeline_metrics(output, launch, context),
        signature_hash = _signature_hash(signature),
        signature,
    )
end

function _launch_groups!(
        ::Tuple{},
        ::Tuple{},
        context,
        backend,
    )
    return nothing
end

function _launch_groups!(
        groups::Tuple,
        outputs::Tuple,
        context,
        backend,
    )
    group = first(groups)
    output = first(outputs)
    kernel = qualification_descriptor_group_probe_kernel!(backend)
    kernel(
        output,
        group.launch,
        context;
        ndrange = length(output),
    )
    return _launch_groups!(
        Base.tail(groups),
        Base.tail(outputs),
        context,
        backend,
    )
end

function _aggregate_group_measurement(
        candidate,
        occurrences,
        group_count,
        host_context,
        device_context,
        backend,
        prototype,
        fixture,
    )
    ranges = [
        (
            floor(Int, (index - 1) * length(occurrences) / group_count) + 1
        ):floor(Int, index * length(occurrences) / group_count)
        for index in 1:group_count
    ]
    host_groups = Tuple(
        qualification_group(candidate, occurrences[range], index)
        for (index, range) in enumerate(ranges)
    )
    groups = Tuple(adapt_qualification_group(group) for group in host_groups)
    outputs = Tuple(
        similar(prototype, Float32, length(group.launch.instances))
        for group in groups
    )
    expected = Tuple(
        Float32[
            canonical_value(fixture, occurrence, host_context)
            for occurrence in occurrences[range]
        ]
        for range in ranges
    )
    first_launch = @elapsed begin
        _launch_groups!(groups, outputs, device_context, backend)
        KA.synchronize(backend)
    end
    warm_samples = Float64[]
    for _ in 1:10
        push!(warm_samples, @elapsed begin
            _launch_groups!(groups, outputs, device_context, backend)
            KA.synchronize(backend)
        end)
    end
    for (output, reference) in zip(outputs, expected)
        reinterpret(UInt32, Array(output)) ==
            reinterpret(UInt32, reference) ||
            error("aggregate group launch changed semantics")
    end
    signature = Tuple(
        (
            evaluator = typeof(
                first(Array(group.launch.instances)).evaluator
            ),
            descriptor = eltype(group.launch.instances),
            launch = typeof(group.launch),
            kernel_arguments = (
                typeof(output),
                typeof(group.launch),
                typeof(device_context),
            ),
        )
        for (group, output) in zip(groups, outputs)
    )
    runner_typed = only(code_typed(
        _launch_groups!,
        Tuple{
            typeof(groups),
            typeof(outputs),
            typeof(device_context),
            typeof(backend),
        };
        optimize = true,
    ))
    device_bytes = sum(
        device_llvm_bytes(
            qualification_descriptor_group_probe_kernel!(backend),
            output,
            group.launch,
            device_context,
        )
        for (group, output) in zip(groups, outputs);
        init = 0,
    )
    return (
        groups = group_count,
        occurrences = length(occurrences),
        first_launch_seconds = first_launch,
        warm_launch_seconds = _warm_median(warm_samples),
        runner_statements = length(first(runner_typed).code),
        device_llvm_bytes = device_bytes,
        specialization_count = length(unique(signature)),
        signature_hash = _signature_hash(signature),
    )
end

# Exact raw Philox CPU/device witness, independent of evaluator arithmetic.
@kernel function _rng_words_probe!(output, addresses, seed)
    index = @index(Global, Linear)
    if index <= length(addresses)
        words = CorePotts._rng_words(
            CorePotts.Philox4x32x10V1(),
            seed,
            @inbounds(addresses[index]),
        )
        for lane in 1:4
            @inbounds output[lane, index] = words[lane]
        end
    end
end

function qualify_rng_words(backend, backend_name)
    occurrences = qualification_occurrences(32)
    addresses = getfield.(occurrences, :address)
    expected = reduce(hcat, (
        collect(CorePotts._rng_words(
            CorePotts.Philox4x32x10V1(),
            QUALIFICATION_SEED,
            address,
        ))
        for address in addresses
    ))
    device_addresses = backend_name === :metal ?
                       Metal.MtlArray(addresses) : addresses
    output = backend_name === :metal ?
             Metal.zeros(UInt32, 4, length(addresses)) :
             zeros(UInt32, 4, length(addresses))
    kernel = _rng_words_probe!(backend)
    kernel(
        output,
        device_addresses,
        QUALIFICATION_SEED;
        ndrange = length(addresses),
    )
    KA.synchronize(backend)
    Array(output) == expected ||
        error("raw semantic RNG words differ across backend")
    return (
        addresses = length(addresses),
        dimensions = (
            :mcs, :subround, :operation, :entity, :generation,
            :invocation, :draw,
        ),
        exact_words = true,
    )
end

function qualify_candidate(
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
    construction_allocation = @allocated begin
        construction_seconds = @elapsed candidate =
            builder(fixture, execution)
    end
    occurrence = first(qualification_occurrences(1))
    expected = canonical_value(fixture, occurrence, host_context)
    candidate_evaluate(candidate, occurrence, host_context) === expected ||
        error("$label changed canonical ordered semantics")
    typed = _typed_metrics(candidate, occurrence, host_context)
    candidate_evaluate(candidate, occurrence, host_context)
    warm_allocation = @allocated candidate_evaluate(
        candidate, occurrence, host_context
    )
    if execution_label === :concrete_callables &&
            label === :bounded_nary_typed_tree
        typed.inferred === Float32 || error(
            "selected evaluator no longer infers Float32"
        )
        typed.any_slots == 0 || error(
            "selected evaluator contains Any-typed compiler slots"
        )
        warm_allocation == 0 || error(
            "selected evaluator allocates after warmup"
        )
    end

    occurrences = qualification_occurrences(32)
    host_group = qualification_group(candidate, occurrences, 1)
    device_group = adapt_qualification_group(host_group)
    expected_vector = Float32[
        canonical_value(fixture, item, host_context)
        for item in occurrences
    ]
    launch = _launch_one(
        device_group,
        device_context,
        backend,
        prototype,
        expected_vector,
    )
    return (
        execution = execution_label,
        representation = label,
        semantic_nodes = fixture.node_count,
        semantic_depth = fixture.depth,
        representation_nodes = representation_node_count(candidate),
        representation_depth = representation_depth(candidate),
        construction_seconds,
        construction_allocation,
        host_compile_seconds = typed.compile_seconds,
        inferred = typed.inferred,
        any_slots = typed.any_slots,
        warm_allocation,
        code_statements = typed.code_statements,
        host_llvm_bytes = typed.host_llvm_bytes,
        device_llvm_bytes = launch.device_llvm_bytes,
        first_launch_seconds = launch.first_launch_seconds,
        warm_launch_seconds = launch.warm_launch_seconds,
        pipeline = launch.pipeline,
        signature_hash = launch.signature_hash,
        exact_ordered_semantics = true,
    )
end
