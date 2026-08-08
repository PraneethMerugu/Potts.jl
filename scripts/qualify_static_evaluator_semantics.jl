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
# The operation-execution decision: tag baseline versus callable hybrid.

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
