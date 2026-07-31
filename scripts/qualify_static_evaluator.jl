using CorePotts
using CorePotts.KernelAbstractions: @index, @kernel
using InteractiveUtils
using SHA

const KA = CorePotts.KernelAbstractions
const USE_METAL = get(ENV, "POTTS_EVALUATOR_GPU", "") == "metal"
USE_METAL && (@eval using Metal)

# ---------------------------------------------------------------------------
# One host-only semantic fixture shared by every representation.

abstract type AbstractSemanticNode end

struct SemanticLeaf <: AbstractSemanticNode
    kind::Symbol
    value::Any
end

struct SemanticCall <: AbstractSemanticNode
    identity::Symbol
    operands::Vector{Int32}
end

struct SemanticFixture
    nodes::Vector{AbstractSemanticNode}
    root::Int32
    node_count::Int
    depth::Int
end

function _semantic_depth(nodes, index, memo)
    haskey(memo, index) && return memo[index]
    node = nodes[index]
    depth = node isa SemanticLeaf ? 1 :
            1 + maximum(
                operand -> _semantic_depth(nodes, operand, memo),
                node.operands;
                init = 0,
            )
    memo[index] = depth
    return depth
end

function semantic_fixture(
        total_nodes::Int;
        identity_wrappers::Int = 0,
    )
    total_nodes >= 16 ||
        throw(ArgumentError("qualification fixtures require at least 16 nodes"))
    identity_wrappers >= 0 ||
        throw(ArgumentError("identity wrapper count must be nonnegative"))
    extra_biases = total_nodes - 12 - identity_wrappers
    extra_biases >= 0 ||
        throw(ArgumentError("node budget is too small for requested depth"))
    nodes = AbstractSemanticNode[]
    leaf(kind, value = nothing) = (
        push!(nodes, SemanticLeaf(kind, value));
        Int32(length(nodes))
    )
    call(identity, operands...) = (
        push!(nodes, SemanticCall(identity, Int32[operands...]));
        Int32(length(nodes))
    )

    coefficient = leaf(:occurrence, :coefficient)
    parameter = leaf(:parameter)
    product = call(:multiply, coefficient, parameter)
    for _ in 1:identity_wrappers
        product = call(:depth_identity, product)
    end
    bias = leaf(:occurrence, :bias)
    offset = leaf(:occurrence, :offset)
    address = leaf(:occurrence, :address)
    minimum = leaf(:occurrence, :minimum)
    maximum = leaf(:occurrence, :maximum)
    random_value = call(:uniform_draw, address, minimum, maximum)
    draw_scale = leaf(:literal, 0.125f0)
    scaled_draw = call(:multiply, random_value, draw_scale)
    root_operands = Int32[product, bias, offset, bias, scaled_draw]
    for _ in 1:extra_biases
        push!(root_operands, leaf(:occurrence, :bias))
    end
    root = call(:add, root_operands...)
    length(nodes) == total_nodes ||
        error("semantic fixture node accounting failed")
    depth = _semantic_depth(nodes, root, Dict{Int32, Int}())
    return SemanticFixture(nodes, root, length(nodes), depth)
end

# ---------------------------------------------------------------------------
# Shared occurrence data, context, semantic RNG, and canonical interpreter.

struct QualificationOccurrence{T}
    coefficient::T
    bias::T
    offset::T
    minimum::T
    maximum::T
    parameter_index::Int32
    address::CorePotts.RNGAddress
    source_handle::Int32
end

struct QualificationContext{P}
    parameters::P
    seed::UInt64
end

CorePotts.Adapt.@adapt_structure QualificationContext

function qualification_occurrences(count::Int)
    return QualificationOccurrence{Float32}[
        QualificationOccurrence(
            Float32(0x1p24),
            1.0f0,
            -Float32(0x1p24),
            -0.5f0,
            0.5f0,
            Int32(mod1(index, 4)),
            CorePotts.RNGAddress(
                stream = CorePotts.ExplicitProposalDrawStream,
                mcs = index - 1,
                subround = mod(index - 1, 7),
                operation = mod(index + 15, 4095),
                entity_kind = CorePotts.SiteEntity,
                entity = index,
                generation = mod(index - 1, 11) + 1,
                invocation = mod(index - 1, 3),
                draw = mod(index - 1, 17),
            ),
            Int32(index),
        )
        for index in 1:count
    ]
end

const QUALIFICATION_SEED = UInt64(0x8b8b8b8b4d544b31)

@inline function qualification_uniform(
        context::QualificationContext,
        address::CorePotts.RNGAddress,
        minimum,
        maximum,
    )
    value = CorePotts.uniform_open01(
        Float32,
        CorePotts.Philox4x32x10V1(),
        context.seed,
        address,
    )
    return muladd(value, maximum - minimum, minimum)
end

function _canonical_value(
        fixture::SemanticFixture,
        index::Int32,
        occurrence,
        context,
        memo,
    )
    haskey(memo, index) && return memo[index]
    node = fixture.nodes[index]
    value = if node isa SemanticLeaf
        node.kind === :literal ? node.value :
        node.kind === :parameter ?
        @inbounds(context.parameters[occurrence.parameter_index]) :
        node.kind === :occurrence ?
        getproperty(occurrence, node.value) :
        error("unknown semantic leaf")
    else
        arguments = Tuple(
            _canonical_value(
                fixture, operand, occurrence, context, memo
            )
            for operand in node.operands
        )
        if node.identity === :add
            _ordered_fold(+, arguments)
        elseif node.identity === :multiply
            _ordered_fold(*, arguments)
        elseif node.identity === :depth_identity
            only(arguments)
        elseif node.identity === :uniform_draw
            qualification_uniform(context, arguments...)
        else
            error("unknown canonical operation $(node.identity)")
        end
    end
    memo[index] = value
    return value
end

canonical_value(fixture, occurrence, context) = _canonical_value(
    fixture,
    fixture.root,
    occurrence,
    context,
    Dict{Int32, Any}(),
)

@inline _ordered_fold(operation, arguments::Tuple) =
    _ordered_fold_tail(operation, first(arguments), Base.tail(arguments))
@inline _ordered_fold_tail(operation, value, ::Tuple{}) = value
@inline _ordered_fold_tail(operation, value, tail::Tuple) =
    _ordered_fold_tail(
        operation,
        operation(value, first(tail)),
        Base.tail(tail),
    )

# ---------------------------------------------------------------------------
# The R1 operation-execution decision: tag baseline versus callable hybrid.

struct TagExecution end
struct CallableExecution end

abstract type AbstractQualificationTag end
struct QualificationDrawTag <: AbstractQualificationTag end
struct DepthIdentityTag <: AbstractQualificationTag end
struct QualificationBuiltinTag{Identity} <: AbstractQualificationTag end

@inline qualification_tag_operation(
    ::QualificationDrawTag, arguments, context
) = qualification_uniform(context, arguments...)
@inline qualification_tag_operation(
    ::DepthIdentityTag, arguments, context
) = only(arguments)
@inline qualification_tag_operation(
    ::QualificationBuiltinTag{:add}, arguments, context
) = _ordered_fold(+, arguments)
@inline qualification_tag_operation(
    ::QualificationBuiltinTag{:multiply}, arguments, context
) = _ordered_fold(*, arguments)

struct OrderedFold{F}
    operation::F
end
@inline (fold::OrderedFold)(arguments::Tuple) =
    _ordered_fold(fold.operation, arguments)

struct QualificationDrawCallable end
@inline (::QualificationDrawCallable)(
    arguments::Tuple, context
) = qualification_uniform(context, arguments...)

struct DepthIdentityCallable end
@inline (::DepthIdentityCallable)(arguments::Tuple, context) =
    only(arguments)

@inline execute_candidate_operation(
    operation::AbstractQualificationTag,
    arguments::Tuple,
    context,
) = qualification_tag_operation(operation, arguments, context)
@inline execute_candidate_operation(
    operation::OrderedFold,
    arguments::Tuple,
    context,
) = operation(arguments)
@inline execute_candidate_operation(
    operation::QualificationDrawCallable,
    arguments::Tuple,
    context,
) = operation(arguments, context)
@inline execute_candidate_operation(
    operation::DepthIdentityCallable,
    arguments::Tuple,
    context,
) = operation(arguments, context)
@inline execute_candidate_operation(
    operation::Function,
    arguments::Tuple,
    context,
) = operation(arguments...)

function operation_value(::TagExecution, identity::Symbol)
    identity === :add &&
        return QualificationBuiltinTag{:add}()
    identity === :multiply &&
        return QualificationBuiltinTag{:multiply}()
    identity === :uniform_draw && return QualificationDrawTag()
    identity === :depth_identity && return DepthIdentityTag()
    error("unknown tag qualification operation $identity")
end

function operation_value(::CallableExecution, identity::Symbol)
    identity === :add && return OrderedFold(+)
    identity === :multiply && return OrderedFold(*)
    identity === :uniform_draw &&
        return QualificationDrawCallable()
    identity === :depth_identity && return DepthIdentityCallable()
    error("unknown callable qualification operation $identity")
end

# ---------------------------------------------------------------------------
# Three private representations consuming the same semantic fixture.

abstract type AbstractQualificationExpression end

struct QualificationLiteral{T} <: AbstractQualificationExpression
    value::T
end
struct QualificationField{Field} <: AbstractQualificationExpression end
struct QualificationParameter <: AbstractQualificationExpression end

struct RecursiveCall{O, A <: Tuple} <: AbstractQualificationExpression
    operation::O
    arguments::A
end

struct NaryCall{O, A <: Tuple} <: AbstractQualificationExpression
    operation::O
    arguments::A
end

@inline candidate_evaluate(
    expression::QualificationLiteral, occurrence, context
) = expression.value
@inline candidate_evaluate(
    ::QualificationField{Field}, occurrence, context
) where {Field} = getproperty(occurrence, Field)
@inline candidate_evaluate(
    ::QualificationParameter, occurrence, context
) = @inbounds context.parameters[occurrence.parameter_index]

@inline _evaluate_arguments(
    ::Tuple{}, occurrence, context
) = ()
@inline _evaluate_arguments(arguments::Tuple, occurrence, context) = (
    candidate_evaluate(first(arguments), occurrence, context),
    _evaluate_arguments(Base.tail(arguments), occurrence, context)...,
)

for call_type in (:RecursiveCall, :NaryCall)
    @eval @inline function candidate_evaluate(
            expression::$call_type, occurrence, context
        )
        arguments = _evaluate_arguments(
            expression.arguments, occurrence, context
        )
        return execute_candidate_operation(
            expression.operation, arguments, context
        )
    end
end

struct SSALiteral{T}
    value::T
end
struct SSAField{Field} end
struct SSAParameter end
struct SSAApply{References, O}
    operation::O
end
struct StaticSSA{I <: Tuple}
    instructions::I
end

function _ssa_expression(
        instruction_type::Type{<:SSALiteral},
        index,
        values,
    )
    return :(getfield(getfield(program.instructions, $index), :value))
end

function _ssa_expression(
        instruction_type::Type{<:SSAField},
        index,
        values,
    )
    field = instruction_type.parameters[1]
    return :(getproperty(occurrence, $(QuoteNode(field))))
end

_ssa_expression(
    ::Type{SSAParameter}, index, values
) = :(@inbounds context.parameters[occurrence.parameter_index])

function _ssa_expression(
        instruction_type::Type{<:SSAApply},
        index,
        values,
    )
    references = instruction_type.parameters[1]
    arguments = Expr(:tuple, (values[reference] for reference in references)...)
    return :(execute_candidate_operation(
        getfield(getfield(program.instructions, $index), :operation),
        $arguments,
        context,
    ))
end

@generated function candidate_evaluate(
        program::StaticSSA{I}, occurrence, context
    ) where {I}
    values = Any[]
    assignments = Any[]
    for (index, instruction_type) in enumerate(fieldtypes(I))
        name = Symbol(:qualification_value_, index)
        expression = _ssa_expression(
            instruction_type, index, values
        )
        push!(assignments, :($name = $expression))
        push!(values, name)
    end
    return quote
        $(assignments...)
        $(last(values))
    end
end

function _leaf_expression(node::SemanticLeaf)
    node.kind === :literal && return QualificationLiteral(node.value)
    node.kind === :parameter && return QualificationParameter()
    node.kind === :occurrence &&
        return QualificationField{node.value}()
    error("unknown qualification leaf")
end

function recursive_candidate(
        fixture::SemanticFixture, execution
    )
    values = Any[]
    for node in fixture.nodes
        if node isa SemanticLeaf
            push!(values, _leaf_expression(node))
            continue
        end
        operation = operation_value(execution, node.identity)
        arguments = Tuple(values[index] for index in node.operands)
        if node.identity === :add && length(arguments) > 2
            result = RecursiveCall(
                operation, (arguments[1], arguments[2])
            )
            for index in 3:length(arguments)
                result = RecursiveCall(
                    operation, (result, arguments[index])
                )
            end
            push!(values, result)
        else
            push!(values, RecursiveCall(operation, arguments))
        end
    end
    return values[fixture.root]
end

function _bounded_nary_call(operation, arguments::Tuple)
    length(arguments) <= 8 && return NaryCall(operation, arguments)
    result = NaryCall(operation, arguments[1:8])
    index = 9
    while index <= length(arguments)
        final = min(index + 6, length(arguments))
        result = NaryCall(
            operation, (result, arguments[index:final]...)
        )
        index = final + 1
    end
    return result
end

function nary_candidate(
        fixture::SemanticFixture, execution
    )
    values = Any[]
    for node in fixture.nodes
        if node isa SemanticLeaf
            push!(values, _leaf_expression(node))
            continue
        end
        operation = operation_value(execution, node.identity)
        arguments = Tuple(values[index] for index in node.operands)
        push!(
            values,
            node.identity in (:add, :multiply) ?
            _bounded_nary_call(operation, arguments) :
            NaryCall(operation, arguments),
        )
    end
    return values[fixture.root]
end

function ssa_candidate(
        fixture::SemanticFixture, execution
    )
    instructions = ()
    for node in fixture.nodes
        instruction = if node isa SemanticLeaf
            node.kind === :literal ? SSALiteral(node.value) :
            node.kind === :parameter ? SSAParameter() :
            node.kind === :occurrence ?
            SSAField{node.value}() :
            error("unknown SSA leaf")
        else
            references = Tuple(Int.(node.operands))
            operation = operation_value(execution, node.identity)
            SSAApply{references, typeof(operation)}(operation)
        end
        instructions = (instructions..., instruction)
    end
    return StaticSSA(instructions)
end

function representation_node_count(
        ::Union{
            QualificationLiteral,
            QualificationField,
            QualificationParameter,
        },
    )
    return 1
end
representation_node_count(expression::Union{RecursiveCall, NaryCall}) =
    1 + sum(representation_node_count, expression.arguments; init = 0)
representation_node_count(program::StaticSSA) =
    length(program.instructions)

representation_depth(
    ::Union{
        QualificationLiteral,
        QualificationField,
        QualificationParameter,
    },
) = 1
representation_depth(expression::Union{RecursiveCall, NaryCall}) =
    1 + maximum(representation_depth, expression.arguments; init = 0)
representation_depth(program::StaticSSA) = begin
    depths = Int[]
    for instruction in program.instructions
        if instruction isa Union{SSALiteral, SSAField, SSAParameter}
            push!(depths, 1)
        else
            references = typeof(instruction).parameters[1]
            push!(
                depths,
                1 + maximum(reference -> depths[reference], references),
            )
        end
    end
    last(depths)
end

# ---------------------------------------------------------------------------
# Actual occurrence-valued descriptor buffers and group launches.

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
@inline CorePotts.descriptor_evaluate_proposal(
    descriptor::QualificationDescriptor, context
) = candidate_evaluate(
    descriptor.evaluator, descriptor.occurrence, context
)
@inline CorePotts.descriptor_evaluate_energy(
    descriptor::QualificationDescriptor, context
) = candidate_evaluate(
    descriptor.evaluator, descriptor.occurrence, context
)
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
        CorePotts.FiniteSpatialFootprint((Int8(index),)),
    )
    roles = (
        CorePotts.HamiltonianRole(),
        CorePotts.ProposalDriveRole(),
        CorePotts.ProposalModifierRole(),
        CorePotts.ProposalConstraintRole(),
    )
    footprint = footprints[mod1(index, length(footprints))]
    role = roles[mod1(div(index - 1, length(footprints)) + 1, length(roles))]
    return CorePotts.ResourceAccess((), (), footprint), role
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
    return CorePotts.DescriptorGroup(
        CorePotts.adapt_descriptor_launch(Metal.MtlArray, group),
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
                    CorePotts.descriptor_evaluate_proposal(
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
    kernel = CorePotts.descriptor_group_probe_kernel!(backend)
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
    kernel = CorePotts.descriptor_group_probe_kernel!(backend)
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
            CorePotts.descriptor_group_probe_kernel!(backend),
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
                println("candidate=", result)
            catch error
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
            println("group_growth=", (
                execution = execution_label,
                representation = label,
                results,
            ))
        catch error
            println("group_growth_failure=", (
                execution = execution_label,
                representation = label,
                error_type = nameof(typeof(error)),
            ))
        end
    end
end
