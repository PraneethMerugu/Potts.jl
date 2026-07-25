"""Immutable semantic rule phase with explicit predecessor dependencies."""
struct Phase
    name::SemanticName
    after::Tuple
end

function Phase(name::Symbol; namespace::Namespace = Namespace(), after = ())
    dependencies = after isa Phase ? (after,) : Tuple(after)
    all(value -> value isa Phase, dependencies) || throw(ArgumentError(
        "phase dependencies must be Phase values"))
    identities = Tuple(semantic_identity(value) for value in dependencies)
    length(unique(identities)) == length(identities) || throw(ArgumentError(
        "phase dependencies must be unique"))
    identity = SemanticName(name; namespace)
    identity in identities && throw(ArgumentError("a phase cannot depend on itself"))
    return Phase(identity, identities)
end

function Phase(name::Symbol, invocation::CorePotts.AbstractProcessInvocation,
        invocations::CorePotts.AbstractProcessInvocation...;
        namespace::Namespace = Namespace(), after = ())
    isempty(after) || throw(ArgumentError(
        "coupled process phases use explicit MCSPlan position, not rule-phase `after` dependencies"))
    identity = SemanticName(name; namespace)
    qualified = isempty(identity.namespace.parts) ? identity.name :
        Symbol(join(String.((identity.namespace.parts..., identity.name)), "__"))
    return CorePotts.CoupledPhase(
        qualified, (invocation, invocations...))
end

semantic_identity(phase::Phase) = phase.name

function Base.show(io::IO, phase::Phase)
    print(io, "Phase(", repr(phase.name.name))
    isempty(phase.name.namespace.parts) || print(io, "; namespace=", phase.name.namespace)
    isempty(phase.after) || print(io, "; after=", phase.after)
    print(io, ')')
end

abstract type AbstractRuleExpression end

struct RuleLiteral{T} <: AbstractRuleExpression
    value::T
    function RuleLiteral(value::T) where {T}
        isbitstype(T) || throw(ArgumentError(
            "Level 1 rule literals must be immutable isbits values"))
        return new{T}(value)
    end
end

struct OwnerReference <: AbstractRuleExpression
    name::Symbol
end

struct PropertyRead <: AbstractRuleExpression
    property::SemanticName
    owner::Symbol
end

struct CellParameterRead <: AbstractRuleExpression
    parameter::SemanticName
    owner::Symbol
end

struct ModelParameterRead <: AbstractRuleExpression
    parameter::SemanticName
end

abstract type AbstractScalarOperation end
struct AddOperation <: AbstractScalarOperation end
struct SubtractOperation <: AbstractScalarOperation end
struct MultiplyOperation <: AbstractScalarOperation end
struct DivideOperation <: AbstractScalarOperation end
struct PowerOperation <: AbstractScalarOperation end
struct LessOperation <: AbstractScalarOperation end
struct LessEqualOperation <: AbstractScalarOperation end
struct GreaterOperation <: AbstractScalarOperation end
struct GreaterEqualOperation <: AbstractScalarOperation end
struct EqualOperation <: AbstractScalarOperation end
struct NotEqualOperation <: AbstractScalarOperation end
struct AndOperation <: AbstractScalarOperation end
struct OrOperation <: AbstractScalarOperation end
struct NotOperation <: AbstractScalarOperation end
struct MinOperation <: AbstractScalarOperation end
struct MaxOperation <: AbstractScalarOperation end
struct ClampOperation <: AbstractScalarOperation end
struct AbsOperation <: AbstractScalarOperation end
struct SqrtOperation <: AbstractScalarOperation end
struct ExpOperation <: AbstractScalarOperation end
struct LogOperation <: AbstractScalarOperation end
struct SinOperation <: AbstractScalarOperation end
struct CosOperation <: AbstractScalarOperation end
struct TanOperation <: AbstractScalarOperation end
struct IfElseOperation <: AbstractScalarOperation end

struct ScalarCall{O <: AbstractScalarOperation, A <: Tuple} <: AbstractRuleExpression
    operation::O
    arguments::A
end

struct ConditionalExpression{C <: AbstractRuleExpression,
        T <: AbstractRuleExpression, F <: AbstractRuleExpression} <: AbstractRuleExpression
    condition::C
    if_true::T
    if_false::F
end

"""Explicitly report that a rule performs no write for one owner."""
struct NoChange <: AbstractRuleExpression end

abstract type AbstractDrawDistribution end

struct Bernoulli{P <: AbstractRuleExpression} <: AbstractDrawDistribution
    probability::P
end
Bernoulli(probability) = Bernoulli(_rule_expression(probability))

struct Uniform{L <: AbstractRuleExpression, U <: AbstractRuleExpression} <:
        AbstractDrawDistribution
    lower::L
    upper::U
end
Uniform(lower, upper) = Uniform(_rule_expression(lower), _rule_expression(upper))

struct Normal{M <: AbstractRuleExpression, S <: AbstractRuleExpression} <:
        AbstractDrawDistribution
    mean::M
    standard_deviation::S
end
Normal(mean, standard_deviation) =
    Normal(_rule_expression(mean), _rule_expression(standard_deviation))

struct UnitVector <: AbstractDrawDistribution
    dimensions::UInt8
    function UnitVector(dimensions::Integer)
        dimensions in (2, 3) || throw(ArgumentError(
            "unit-vector draws support two or three dimensions"))
        return new(UInt8(dimensions))
    end
end

"""Declarative addressed random draw; constructing it consumes no random state."""
struct RandomDraw{D <: AbstractDrawDistribution} <: AbstractRuleExpression
    distribution::D
    label::Union{Nothing, Symbol}
end

function draw(distribution::AbstractDrawDistribution; label::Union{Nothing, Symbol} = nothing)
    return RandomDraw(distribution, label)
end

_rule_expression(value::AbstractRuleExpression) = value
_rule_expression(value) = RuleLiteral(value)

function _rule_reference(property::CellProperty, owner::OwnerReference)
    return PropertyRead(semantic_identity(property), owner.name)
end

(property::CellProperty)(owner::OwnerReference) = _rule_reference(property, owner)

function _rule_reference(parameter::CellParameter, owner::OwnerReference)
    return CellParameterRead(semantic_identity(parameter), owner.name)
end

function _rule_reference(parameter::ModelParameter, owner::OwnerReference)
    return ModelParameterRead(semantic_identity(parameter))
end

(parameter::CellParameter)(owner::OwnerReference) = _rule_reference(parameter, owner)
(parameter::ModelParameter)(owner::OwnerReference) = _rule_reference(parameter, owner)

_as_rule_expression(value::AbstractRuleExpression) = value
_as_rule_expression(value) = RuleLiteral(value)

const RuleScalarOperand = Union{Number, AbstractRuleExpression}

Base.:+(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(AddOperation(), (left, _as_rule_expression(right)))
Base.:+(left::Number, right::AbstractRuleExpression) =
    ScalarCall(AddOperation(), (_as_rule_expression(left), right))
Base.:-(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(SubtractOperation(), (left, _as_rule_expression(right)))
Base.:-(left::AbstractRuleExpression) = ScalarCall(SubtractOperation(), (left,))
Base.:*(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(MultiplyOperation(), (left, _as_rule_expression(right)))
Base.:*(left::Number, right::AbstractRuleExpression) =
    ScalarCall(MultiplyOperation(), (_as_rule_expression(left), right))
Base.:/(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(DivideOperation(), (left, _as_rule_expression(right)))
Base.:^(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(PowerOperation(), (left, _as_rule_expression(right)))
Base.:>=(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(GreaterEqualOperation(), (left, _as_rule_expression(right)))
Base.:<=(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(LessEqualOperation(), (left, _as_rule_expression(right)))
Base.:>(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(GreaterOperation(), (left, _as_rule_expression(right)))
Base.:<(left::AbstractRuleExpression, right::RuleScalarOperand) =
    ScalarCall(LessOperation(), (left, _as_rule_expression(right)))

function _rule_reference(value, owner::OwnerReference)
    throw(ArgumentError(
        "$(typeof(value)) is not a registered Level 1 callable model reference"))
end

"""One immutable scalar property rule."""
struct Rule{E <: AbstractRuleExpression}
    name::SemanticName
    target::SemanticName
    cell_types::Tuple
    owner::Symbol
    expression::E
    phase::Phase
    source::Union{Nothing, SourceLocation}
end

function Rule(target::CellProperty, owner::Symbol, expression;
        phase::Phase, name::Union{Nothing, Symbol} = nothing,
        namespace::Namespace = Namespace(), source::Union{Nothing, SourceLocation} = nothing)
    identity = name === nothing ? Symbol(target.name.name, "__", phase.name.name, "__rule") : name
    return Rule(SemanticName(identity; namespace), semantic_identity(target),
        target.cell_types, owner, _rule_expression(expression), phase, source)
end

semantic_identity(rule::Rule) = rule.name

function Base.show(io::IO, rule::Rule)
    print(io, "Rule(", repr(rule.name.name), "; target=", rule.target,
        ", phase=", rule.phase.name, ')')
end

function Base.show(io::IO, ::MIME"text/plain", rule::Rule)
    println(io, "PottsToolkit rule ", _identity_text(rule.name))
    println(io, "  target:     ", _identity_text(rule.target), '(', rule.owner, ')')
    println(io, "  phase:      ", _identity_text(rule.phase.name))
    println(io, "  cell types: ", join((_identity_text(value) for value in rule.cell_types), ", "))
    reads = _expression_reads(rule.expression)
    println(io, "  reads:      ", isempty(reads) ? "none" :
        join((_identity_text(value) for value in reads), ", "))
    draws = _random_draws(rule.expression)
    println(io, "  draws:      ", isempty(draws) ? "none" : join((
        string(nameof(typeof(draw.distribution)), '[', something(draw.label, :draw), ']')
        for draw in draws), ", "))
    println(io, "  expression: ", nameof(typeof(rule.expression)))
    rule.source === nothing || print(io, "  source:     ", rule.source.file, ':',
        rule.source.line)
end

"""An atomic group of property rules that read one phase snapshot."""
struct RuleGroup{R <: Tuple}
    name::SemanticName
    rules::R
    phase::Phase
    source::Union{Nothing, SourceLocation}
end

function RuleGroup(rules::Tuple; name::Symbol = :rule_group,
        namespace::Namespace = Namespace(), source::Union{Nothing, SourceLocation} = nothing)
    isempty(rules) && throw(ArgumentError("a rule group must contain at least one rule"))
    all(rule -> rule isa Rule, rules) || throw(ArgumentError(
        "a rule group may contain only Rule values"))
    phases = unique(rule.phase for rule in rules)
    length(phases) == 1 || throw(ArgumentError(
        "every rule in an atomic group must use the same phase"))
    targets = map(rule -> rule.target, rules)
    length(unique(targets)) == length(targets) || throw(ArgumentError(
        "an atomic rule group cannot write one property more than once"))
    return RuleGroup(SemanticName(name; namespace), rules, only(phases), source)
end

semantic_identity(group::RuleGroup) = group.name
_flatten_declaration(group::RuleGroup) = group.rules

function Base.show(io::IO, group::RuleGroup)
    print(io, "RuleGroup(", repr(group.name.name), "; ", length(group.rules),
        " rules, phase=", group.phase.name, ')')
end

function Base.show(io::IO, ::MIME"text/plain", group::RuleGroup)
    println(io, "PottsToolkit rule group ", _identity_text(group.name))
    println(io, "  phase: ", _identity_text(group.phase.name))
    println(io, "  rules: ", length(group.rules))
    limit = min(length(group.rules), 20)
    for index in 1:limit
        println(io, "    - ", group.rules[index])
    end
    length(group.rules) > limit && println(io, "    … ",
        length(group.rules) - limit, " more")
end

"""A named pure state-dependent lifecycle predicate."""
struct TriggerRule{E <: AbstractRuleExpression}
    name::SemanticName
    owner::Symbol
    expression::E
    source::Union{Nothing, SourceLocation}
end

function TriggerRule(name::Symbol, owner::Symbol, expression;
        namespace::Namespace = Namespace(), source::Union{Nothing, SourceLocation} = nothing)
    return TriggerRule(SemanticName(name; namespace), owner,
        _rule_expression(expression), source)
end

semantic_identity(trigger::TriggerRule) = trigger.name

function Base.show(io::IO, trigger::TriggerRule)
    print(io, "TriggerRule(", repr(trigger.name.name), "; phase_snapshot_owner=",
        repr(trigger.owner), ')')
end

function Base.show(io::IO, ::MIME"text/plain", trigger::TriggerRule)
    println(io, "PottsToolkit trigger ", _identity_text(trigger.name))
    println(io, "  owner:      ", trigger.owner)
    reads = _expression_reads(trigger.expression)
    println(io, "  reads:      ", isempty(reads) ? "none" :
        join((_identity_text(value) for value in reads), ", "))
    println(io, "  expression: ", nameof(typeof(trigger.expression)))
    trigger.source === nothing || print(io, "  source:     ", trigger.source.file, ':',
        trigger.source.line)
end

function _property_at_least(expression::ScalarCall{GreaterEqualOperation})
    left, right = expression.arguments
    left isa PropertyRead && right isa RuleLiteral || return nothing
    right.value isa Real || return nothing
    return CorePotts.PropertyAtLeast(
        Symbol(_property_prefix(left.property)), right.value)
end

_property_at_least(expression) = nothing

function _lifecycle_trigger(trigger::TriggerRule)
    lowered = _property_at_least(trigger.expression)
    lowered === nothing && throw(ArgumentError(
        "the initial lifecycle trigger compiler supports `property(cell) >= literal`; " *
        "use a typed CorePotts trigger for another qualified predicate"))
    return lowered
end

EveryMCS() = CorePotts.EveryMCS()
function EveryMCS(period::Integer; start::Integer = period)
    return CorePotts.PeriodicMCS(start, period)
end
AtMCS(mcs::Integer) = CorePotts.OnceAtMCS(mcs)
AtMCS(boundaries) = CorePotts.AtMCS(boundaries)
BetweenMCS(start::Integer, stop::Integer; every::Integer = 1) =
    CorePotts.PeriodicMCS(start, every; stop)

_operation_value(::AddOperation, values...) = +(values...)
_operation_value(::SubtractOperation, left, right) = left - right
_operation_value(::SubtractOperation, value) = -value
_operation_value(::MultiplyOperation, values...) = *(values...)
_operation_value(::DivideOperation, left, right) = left / right
_operation_value(::PowerOperation, left, right) = left^right
_operation_value(::LessOperation, left, right) = left < right
_operation_value(::LessEqualOperation, left, right) = left <= right
_operation_value(::GreaterOperation, left, right) = left > right
_operation_value(::GreaterEqualOperation, left, right) = left >= right
_operation_value(::EqualOperation, left, right) = left == right
_operation_value(::NotEqualOperation, left, right) = left != right
_operation_value(::AndOperation, left, right) = left && right
_operation_value(::OrOperation, left, right) = left || right
_operation_value(::NotOperation, value) = !value
_operation_value(::MinOperation, values...) = min(values...)
_operation_value(::MaxOperation, values...) = max(values...)
_operation_value(::ClampOperation, value, lower, upper) = clamp(value, lower, upper)
_operation_value(::AbsOperation, value) = abs(value)
_operation_value(::SqrtOperation, value) = sqrt(value)
_operation_value(::ExpOperation, value) = exp(value)
_operation_value(::LogOperation, value) = log(value)
_operation_value(::SinOperation, value) = sin(value)
_operation_value(::CosOperation, value) = cos(value)
_operation_value(::TanOperation, value) = tan(value)
_operation_value(::IfElseOperation, condition, if_true, if_false) =
    ifelse(condition, if_true, if_false)

_reference_value(values::NamedTuple, identity::SemanticName) =
    getproperty(values, identity.name)
_reference_value(values::AbstractDict, identity::SemanticName) = values[identity]

evaluate(expression::RuleLiteral, values) = expression.value
evaluate(::OwnerReference, values) = values
evaluate(expression::PropertyRead, values) = _reference_value(values, expression.property)
evaluate(expression::CellParameterRead, values) =
    _reference_value(values, expression.parameter)
evaluate(expression::ModelParameterRead, values) =
    _reference_value(values, expression.parameter)
function evaluate(expression::ScalarCall, values)
    arguments = map(argument -> evaluate(argument, values), expression.arguments)
    return _operation_value(expression.operation, arguments...)
end
function evaluate(expression::ConditionalExpression, values)
    return evaluate(expression.condition, values) ?
        evaluate(expression.if_true, values) : evaluate(expression.if_false, values)
end
evaluate(::NoChange, values) = NoChange()
evaluate(::RandomDraw, values) = throw(ArgumentError(
    "reference evaluation of a RandomDraw requires an explicit addressed draw provider"))
evaluate(rule::Union{Rule, TriggerRule}, values) = evaluate(rule.expression, values)

_expression_reads(::RuleLiteral) = ()
_expression_reads(::OwnerReference) = ()
_expression_reads(expression::PropertyRead) = (expression.property,)
_expression_reads(expression::CellParameterRead) = (expression.parameter,)
_expression_reads(expression::ModelParameterRead) = (expression.parameter,)
_expression_reads(expression::ScalarCall) = Tuple(unique(identity
    for argument in expression.arguments for identity in _expression_reads(argument)))
_expression_reads(expression::ConditionalExpression) = Tuple(unique(identity
    for branch in (expression.condition, expression.if_true, expression.if_false)
    for identity in _expression_reads(branch)))
_expression_reads(::NoChange) = ()
_distribution_expressions(distribution::Bernoulli) = (distribution.probability,)
_distribution_expressions(distribution::Uniform) =
    (distribution.lower, distribution.upper)
_distribution_expressions(distribution::Normal) =
    (distribution.mean, distribution.standard_deviation)
_distribution_expressions(::UnitVector) = ()
_expression_reads(expression::RandomDraw) = Tuple(unique(identity
    for parameter in _distribution_expressions(expression.distribution)
    for identity in _expression_reads(parameter)))

_normalize_rule_expression(expression::RuleLiteral{<:AbstractFloat}, ::Type{T}) where {T} =
    RuleLiteral(T(expression.value))
_normalize_rule_expression(expression::RuleLiteral, ::Type) = expression
_normalize_rule_expression(expression::Union{OwnerReference, PropertyRead,
    CellParameterRead, ModelParameterRead, NoChange}, ::Type) = expression
function _normalize_rule_expression(expression::RandomDraw, type::Type)
    distribution = _normalize_distribution(expression.distribution, type)
    return RandomDraw(distribution, expression.label)
end
_normalize_distribution(distribution::Bernoulli, type::Type) =
    Bernoulli(_normalize_rule_expression(distribution.probability, type))
_normalize_distribution(distribution::Uniform, type::Type) = Uniform(
    _normalize_rule_expression(distribution.lower, type),
    _normalize_rule_expression(distribution.upper, type))
_normalize_distribution(distribution::Normal, type::Type) = Normal(
    _normalize_rule_expression(distribution.mean, type),
    _normalize_rule_expression(distribution.standard_deviation, type))
_normalize_distribution(distribution::UnitVector, ::Type) = distribution
function _normalize_rule_expression(expression::ScalarCall, type::Type)
    arguments = map(argument -> _normalize_rule_expression(argument, type),
        expression.arguments)
    return ScalarCall(expression.operation, arguments)
end
function _normalize_rule_expression(expression::ConditionalExpression, type::Type)
    return ConditionalExpression(
        _normalize_rule_expression(expression.condition, type),
        _normalize_rule_expression(expression.if_true, type),
        _normalize_rule_expression(expression.if_false, type))
end

function _normalize_component(rule::Rule, ::Type{T}) where {T <: AbstractFloat}
    expression = _normalize_rule_expression(rule.expression, T)
    return Rule(rule.name, rule.target, rule.cell_types, rule.owner,
        expression, rule.phase, rule.source)
end

_canonical_write(io::IO, phase::Phase) = _canonical_fields(io, phase)
function _canonical_write(io::IO, operation::AbstractScalarOperation)
    _canonical_open(io, operation)
    _canonical_write(io, Symbol(nameof(typeof(operation))))
    return _canonical_close(io)
end
_canonical_write(io::IO, expression::AbstractRuleExpression) = _canonical_fields(io, expression)
_canonical_write(io::IO, distribution::AbstractDrawDistribution) =
    _canonical_fields(io, distribution)
function _canonical_write(io::IO, rule::Rule)
    _canonical_open(io, rule)
    _canonical_write(io, rule.name)
    _canonical_write(io, rule.target)
    _canonical_write(io, rule.cell_types)
    _canonical_write(io, rule.owner)
    _canonical_write(io, rule.expression)
    _canonical_write(io, rule.phase)
    return _canonical_close(io)
end

function _validate_declaration(rule::Rule, context::_ValidationContext)
    diagnostics = ()
    target_index = findfirst(component -> semantic_identity(component) == rule.target,
        context.components)
    if target_index === nothing || !(context.components[target_index] isa CellProperty)
        diagnostics = (diagnostics..., Diagnostic(:error, :unknown_rule_target,
            "rule target must name a declared CellProperty";
            identity = rule.name, related = (rule.target,), source = rule.source,
            correction = "declare the property before constructing the model"))
    end
    for cell_type in rule.cell_types
        cell_type in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_cell_type, "rule scope references an undeclared cell type";
            identity = rule.name, related = (cell_type,), source = rule.source,
            correction = "declare the cell type or correct the target property scope")))
    end
    for identity in _expression_reads(rule.expression)
        index = findfirst(component -> semantic_identity(component) == identity,
            context.components)
        declaration = index === nothing ? nothing : context.components[index]
        declaration isa Union{
            CellProperty, CellParameter, ModelParameter} ||
            (diagnostics = (diagnostics..., Diagnostic(:error, :unknown_rule_read,
                "rule expression reads an undeclared or incompatible property";
                identity = rule.name, related = (identity,), source = rule.source,
                correction = "declare a compatible typed property reference")))
        if declaration isa CellParameter
            missing = Tuple(cell_type for cell_type in rule.cell_types
                if !haskey(declaration.bindings, cell_type))
            isempty(missing) || (diagnostics = (diagnostics..., Diagnostic(
                :error, :missing_cell_parameter_binding,
                "a cell parameter read must be bound for every cell type in the rule scope";
                identity = rule.name, related = (identity, missing...),
                source = rule.source,
                correction = "add the missing bindings or narrow the target property scope")))
        end
    end
    return (diagnostics..., _rule_expression_diagnostics(rule)...,
        _query_diagnostics(rule, context)...,
        _random_draw_diagnostics(rule)...,
        _rule_output_diagnostics(rule, context)...)
end

_declaration_value_type(declaration::CellProperty) = typeof(declaration.initial)
_declaration_value_type(::CellParameter{T}) where {T} = T
_declaration_value_type(::ModelParameter{T}) where {T} = T

function _referenced_value_type(identity::SemanticName, context::_ValidationContext)
    index = findfirst(component -> semantic_identity(component) == identity,
        context.components)
    index === nothing && return nothing
    declaration = context.components[index]
    return declaration isa Union{CellProperty, CellParameter, ModelParameter} ?
        _declaration_value_type(declaration) : nothing
end

_rule_result_types(expression::RuleLiteral, context) = (typeof(expression.value),)
function _rule_result_types(expression::PropertyRead, context)
    type = _referenced_value_type(expression.property, context)
    return type === nothing ? () : (type,)
end
function _rule_result_types(expression::CellParameterRead, context)
    type = _referenced_value_type(expression.parameter, context)
    return type === nothing ? () : (type,)
end
function _rule_result_types(expression::ModelParameterRead, context)
    type = _referenced_value_type(expression.parameter, context)
    return type === nothing ? () : (type,)
end
_rule_result_types(::OwnerReference, context) = ()
_rule_result_types(::NoChange, context) = ()

_nochange_only(::Any) = false
_nochange_only(::NoChange) = true
_nochange_only(expression::ConditionalExpression) =
    _nochange_only(expression.if_true) && _nochange_only(expression.if_false)
_scalar_function(::AddOperation) = +
_scalar_function(::SubtractOperation) = -
_scalar_function(::MultiplyOperation) = *
_scalar_function(::DivideOperation) = /
_scalar_function(::PowerOperation) = ^
_scalar_function(::LessOperation) = <
_scalar_function(::LessEqualOperation) = <=
_scalar_function(::GreaterOperation) = >
_scalar_function(::GreaterEqualOperation) = >=
_scalar_function(::EqualOperation) = ==
_scalar_function(::NotEqualOperation) = !=
_scalar_function(::MinOperation) = min
_scalar_function(::MaxOperation) = max
_scalar_function(::ClampOperation) = clamp
_scalar_function(::AbsOperation) = abs
_scalar_function(::SqrtOperation) = sqrt
_scalar_function(::ExpOperation) = exp
_scalar_function(::LogOperation) = log
_scalar_function(::SinOperation) = sin
_scalar_function(::CosOperation) = cos
_scalar_function(::TanOperation) = tan

function _concrete_result_types(type)
    type === Union{} && return ()
    types = Base.uniontypes(type)
    all(isconcretetype, types) || return ()
    return Tuple(types)
end

function _scalar_result_types(operation::Union{AndOperation, OrOperation}, types::Tuple)
    return length(types) == 2 && all(==(Bool), types) ? (Bool,) : ()
end

function _scalar_result_types(::NotOperation, types::Tuple)
    return types == (Bool,) ? (Bool,) : ()
end

function _scalar_result_types(::IfElseOperation, types::Tuple)
    length(types) == 3 && first(types) === Bool || return ()
    return Tuple(unique((types[2], types[3])))
end

function _scalar_result_types(operation::AbstractScalarOperation, types::Tuple)
    result = try
        Base.promote_op(_scalar_function(operation), types...)
    catch
        Union{}
    end
    return _concrete_result_types(result)
end

function _rule_result_types(expression::ScalarCall, context)
    argument_types = map(argument -> _rule_result_types(argument, context),
        expression.arguments)
    any(isempty, argument_types) && return ()
    results = DataType[]
    for types in Iterators.product(argument_types...)
        append!(results, _scalar_result_types(expression.operation, types))
    end
    return Tuple(unique(results))
end

function _rule_result_types(expression::ConditionalExpression, context)
    _rule_result_types(expression.condition, context) == (Bool,) || return ()
    return Tuple(unique((_rule_result_types(expression.if_true, context)...,
        _rule_result_types(expression.if_false, context)...)))
end

_rule_result_types(::RandomDraw{<:Bernoulli}, context) = (Bool,)

function _distribution_numeric_types(expressions, context)
    types = Tuple(type for expression in expressions
        for type in _rule_result_types(expression, context))
    length(types) == length(expressions) && all(type -> type <: Real, types) || return ()
    return types
end

function _rule_result_types(draw::RandomDraw{<:Uniform}, context)
    types = _distribution_numeric_types(
        _distribution_expressions(draw.distribution), context)
    isempty(types) && return ()
    return (float(promote_type(types...)),)
end

function _rule_result_types(draw::RandomDraw{<:Normal}, context)
    types = _distribution_numeric_types(
        _distribution_expressions(draw.distribution), context)
    isempty(types) && return ()
    return (float(promote_type(types...)),)
end

function _rule_result_types(draw::RandomDraw{<:UnitVector}, context)
    N = Int(draw.distribution.dimensions)
    T = _context_real_type(context)
    return (StaticArrays.SVector{N, T},)
end

_exact_automatic_conversion(source::Type, target::Type) = source === target
function _exact_automatic_conversion(source::Type{<:Integer}, target::Type{<:Integer})
    source === target && return true
    integer_types = (Bool, Int8, Int16, Int32, Int64, Int128,
        UInt8, UInt16, UInt32, UInt64, UInt128)
    source in integer_types && target in integer_types || return false
    return typemin(target) <= typemin(source) && typemax(source) <= typemax(target)
end
function _exact_automatic_conversion(source::Type{<:AbstractFloat},
        target::Type{<:AbstractFloat})
    source === target && return true
    source in (Float16, Float32, Float64) && target in (Float16, Float32, Float64) ||
        return false
    return sizeof(source) <= sizeof(target)
end
function _exact_automatic_conversion(source::Type{<:Integer},
        target::Type{<:AbstractFloat})
    source in (Bool, Int8, Int16, Int32, Int64, Int128,
        UInt8, UInt16, UInt32, UInt64, UInt128) || return false
    target in (Float16, Float32, Float64) || return false
    source_bits = source === Bool ? 1 : 8 * sizeof(source)
    return source_bits <= precision(target)
end

function _rule_output_diagnostics(rule::Rule, context::_ValidationContext)
    target_index = findfirst(component -> semantic_identity(component) == rule.target,
        context.components)
    target_index === nothing && return ()
    target = context.components[target_index]
    target isa CellProperty || return ()
    result_types = _rule_result_types(rule.expression, context)
    _nochange_only(rule.expression) && return ()
    isempty(result_types) && return (Diagnostic(:error,
        :unsupported_rule_output_type,
        "rule output type cannot be resolved to a portable concrete value";
        identity = rule.name, source = rule.source,
        correction = "use the closed scalar expression vocabulary with concrete typed values"),)
    target_type = typeof(target.initial)
    unsafe = Tuple(type for type in result_types
        if !_exact_automatic_conversion(type, target_type))
    isempty(unsafe) && return ()
    return (Diagnostic(:error, :unsafe_rule_output_conversion,
        "rule output requires narrowing, rounding, precision loss, or an undefined conversion";
        identity = rule.name, related = (unsafe..., target_type), source = rule.source,
        correction = "make the expression type match the property or declare a future named conversion policy"),)
end

_operation_arity(::Union{AddOperation, MultiplyOperation}) = 2:typemax(Int)
_operation_arity(::Union{DivideOperation, PowerOperation, LessOperation, LessEqualOperation, GreaterOperation,
    GreaterEqualOperation, EqualOperation, NotEqualOperation, AndOperation,
    OrOperation}) = 2:2
_operation_arity(::SubtractOperation) = 1:2
_operation_arity(::Union{NotOperation, AbsOperation, SqrtOperation, ExpOperation,
    LogOperation, SinOperation, CosOperation, TanOperation}) = 1:1
_operation_arity(::Union{MinOperation, MaxOperation}) = 1:typemax(Int)
_operation_arity(::Union{ClampOperation, IfElseOperation}) = 3:3

_scalar_calls(::Any) = ()
_scalar_calls(expression::ScalarCall) = (expression, Tuple(call
    for argument in expression.arguments for call in _scalar_calls(argument))...)
_scalar_calls(expression::ConditionalExpression) = Tuple(call
    for branch in (expression.condition, expression.if_true, expression.if_false)
    for call in _scalar_calls(branch))
_scalar_calls(expression::RandomDraw) = Tuple(call
    for parameter in _distribution_expressions(expression.distribution)
    for call in _scalar_calls(parameter))

function _rule_expression_diagnostics(rule::Rule)
    diagnostics = ()
    for call in _scalar_calls(rule.expression)
        length(call.arguments) in _operation_arity(call.operation) ||
            (diagnostics = (diagnostics..., Diagnostic(:error,
                :invalid_scalar_operation_arity,
                "a Level 1 scalar operation has an unsupported number of arguments";
                identity = rule.name,
                related = (Symbol(nameof(typeof(call.operation))),
                    length(call.arguments)), source = rule.source,
                correction = "use the ordinary Julia arity documented for this operation"),))
    end
    return diagnostics
end

_random_draws(::Any) = ()
_random_draws(draw::RandomDraw) = (draw,)
_random_draws(expression::ScalarCall) = Tuple(draw for argument in expression.arguments
    for draw in _random_draws(argument))
_random_draws(expression::ConditionalExpression) = Tuple(draw
    for branch in (expression.condition, expression.if_true, expression.if_false)
    for draw in _random_draws(branch))

function _random_draw_diagnostics(rule::Rule)
    draws = _random_draws(rule.expression)
    diagnostics = ()
    labels = Tuple(draw.label for draw in draws if draw.label !== nothing)
    length(unique(labels)) == length(labels) || (diagnostics = (diagnostics...,
        Diagnostic(:error, :duplicate_random_draw_label,
            "random draw labels must be unique within one rule";
            identity = rule.name, related = labels, source = rule.source,
            correction = "give every addressed draw a distinct stable label"),))
    count(draw -> draw.label === nothing, draws) <= 1 ||
        (diagnostics = (diagnostics..., Diagnostic(:error,
            :ambiguous_unlabelled_random_draw,
            "more than one unlabelled draw has no edit-stable semantic identity";
            identity = rule.name, source = rule.source,
            correction = "supply a distinct `label` for each draw"),))
    for draw in draws
        distribution = draw.distribution
        if distribution isa Bernoulli && distribution.probability isa RuleLiteral
            probability = distribution.probability.value
            probability isa Real && 0 <= probability <= 1 ||
                (diagnostics = (diagnostics..., Diagnostic(:error,
                    :invalid_distribution_parameter,
                    "Bernoulli probability must lie in the closed interval [0, 1]";
                    identity = rule.name, related = (probability,), source = rule.source,
                    correction = "use a probability between zero and one"),))
        end
        if distribution isa Uniform && distribution.lower isa RuleLiteral &&
                distribution.upper isa RuleLiteral
            lower = distribution.lower.value
            upper = distribution.upper.value
            lower isa Real && upper isa Real && isfinite(lower) && isfinite(upper) &&
                lower < upper ||
                (diagnostics = (diagnostics..., Diagnostic(:error,
                    :invalid_distribution_parameter,
                    "Uniform bounds must be finite real values with lower < upper";
                    identity = rule.name, related = (lower, upper), source = rule.source,
                    correction = "supply finite, strictly ordered Uniform bounds"),))
        end
        if distribution isa Normal &&
                distribution.standard_deviation isa RuleLiteral
            standard_deviation = distribution.standard_deviation.value
            standard_deviation isa Real && isfinite(standard_deviation) &&
                standard_deviation > 0 ||
                (diagnostics = (diagnostics..., Diagnostic(:error,
                    :invalid_distribution_parameter,
                    "Normal standard deviation must be a finite positive real value";
                    identity = rule.name, related = (standard_deviation,),
                    source = rule.source,
                    correction = "supply a finite standard deviation greater than zero"),))
        end
    end
    return diagnostics
end

function _rule_increment_expression(rule::Rule)
    expression = rule.expression
    expression isa ScalarCall{AddOperation} || return nothing
    length(expression.arguments) == 2 || return nothing
    left, right = expression.arguments
    left isa PropertyRead && left.property == rule.target && return right
    right isa PropertyRead && right.property == rule.target && return left
    return nothing
end


function _qualified_rule_increment(rule::Rule, context::_ValidationContext)
    increment = _rule_increment_expression(rule)
    increment isa RuleLiteral && return increment.value isa Real
    increment isa RandomDraw{<:Bernoulli} &&
        increment.distribution.probability isa RuleLiteral && return true
    identity = increment isa CellParameterRead ? increment.parameter :
        increment isa ModelParameterRead ? increment.parameter : nothing
    identity === nothing && return false
    index = findfirst(component -> semantic_identity(component) == identity,
        context.components)
    index === nothing && return false
    declaration = context.components[index]
    return declaration isa CellParameter || declaration isa ModelParameter
end

function _rule_increment(rule::Rule)
    increment = _rule_increment_expression(rule)
    return increment isa RuleLiteral && increment.value isa Real ? increment.value : nothing
end

_property_write_target(rule::Rule) = (rule.target, :value)
_lifecycle_event_id(::Rule) = nothing
_rule_program_event_id() =
    UInt16(_lifecycle_event_id(SemanticName(:level1_rule_program)))

_lower_component(::Rule, context::_LoweringContext) = _LoweredComponents()

function _declaration_report(rule::Rule)
    reads = _expression_reads(rule.expression)
    return DeclarationReport(rule.name, :property_rule,
        (rule.target, rule.cell_types..., reads...), (), (:simultaneous_property_write,), (),
        (:Level1Rule, :LifecycleEvent),
        (target = rule.target, owner = rule.owner, phase = rule.phase.name,
            after = rule.phase.after, reads, source = rule.source),
        CorePotts.ScientificCapabilities())
end

function _scope_declaration(rule::Rule, fragment::ModelFragment, mapping)
    target = _mapped_identity(mapping, rule.target)
    expression = _scope_rule_expression(rule.expression, mapping)
    phase = Phase(_mapped_identity(mapping, rule.phase.name),
        Tuple(_mapped_identity(mapping, value) for value in rule.phase.after))
    return Rule(_mapped_identity(mapping, rule.name), target,
        Tuple(_scope_biological(value, mapping) for value in rule.cell_types),
        rule.owner, expression, phase, rule.source)
end

_scope_rule_expression(expression::PropertyRead, mapping) =
    PropertyRead(_mapped_identity(mapping, expression.property), expression.owner)
_scope_rule_expression(expression::CellParameterRead, mapping) =
    CellParameterRead(_mapped_identity(mapping, expression.parameter), expression.owner)
_scope_rule_expression(expression::ModelParameterRead, mapping) =
    ModelParameterRead(_mapped_identity(mapping, expression.parameter))
function _scope_rule_expression(expression::RandomDraw, mapping)
    return RandomDraw(_scope_distribution(expression.distribution, mapping),
        expression.label)
end
_scope_distribution(distribution::Bernoulli, mapping) =
    Bernoulli(_scope_rule_expression(distribution.probability, mapping))
_scope_distribution(distribution::Uniform, mapping) = Uniform(
    _scope_rule_expression(distribution.lower, mapping),
    _scope_rule_expression(distribution.upper, mapping))
_scope_distribution(distribution::Normal, mapping) = Normal(
    _scope_rule_expression(distribution.mean, mapping),
    _scope_rule_expression(distribution.standard_deviation, mapping))
_scope_distribution(distribution::UnitVector, mapping) = distribution
function _scope_rule_expression(expression::ScalarCall, mapping)
    return ScalarCall(expression.operation,
        map(argument -> _scope_rule_expression(argument, mapping), expression.arguments))
end

function _validate_declaration(parameter::CellParameter, context::_ValidationContext)
    diagnostics = ()
    for binding in parameter.bindings
        binding.key in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_cell_type,
            "cell parameter binding references an undeclared cell type";
            identity = parameter.name, related = (binding.key,),
            correction = "declare the cell type or remove the binding")))
    end
    return diagnostics
end

_validate_declaration(::ModelParameter, context::_ValidationContext) = ()

function _normalize_component(parameter::CellParameter, ::Type{T}) where {T <: AbstractFloat}
    V = eltype(Tuple(values(parameter.bindings)))
    V <: AbstractFloat || return parameter
    entries = Tuple(Binding{CellType, T}(entry.key, T(entry.value))
        for entry in parameter.bindings)
    return CellParameter(parameter.name, BindingTable{CellType, T}(entries))
end

function _normalize_component(parameter::ModelParameter{V}, ::Type{T}) where {
        V <: AbstractFloat, T <: AbstractFloat}
    return ModelParameter(parameter.name, T(parameter.value))
end

_canonical_write(io::IO, parameter::Union{CellParameter, ModelParameter}) =
    _canonical_fields(io, parameter)

_lower_component(::Union{CellParameter, ModelParameter}, context::_LoweringContext) =
    _LoweredComponents()

function _declaration_report(parameter::CellParameter)
    return DeclarationReport(parameter.name, :cell_parameter,
        Tuple(keys(parameter.bindings)), (), (:immutable_parameter_read,), (), (),
        (bindings = Tuple((cell_type = semantic_identity(entry.key), value = entry.value)
            for entry in parameter.bindings),), CorePotts.ScientificCapabilities())
end

function _declaration_report(parameter::ModelParameter)
    return DeclarationReport(parameter.name, :model_parameter, (), (),
        (:immutable_parameter_read,), (), (), (value = parameter.value,),
        CorePotts.ScientificCapabilities())
end

function _scope_declaration(parameter::CellParameter{T}, fragment::ModelFragment,
        mapping) where {T}
    entries = Tuple(Binding{CellType, T}(_scope_biological(entry.key, mapping),
        entry.value) for entry in parameter.bindings)
    return CellParameter(_mapped_identity(mapping, parameter.name),
        BindingTable{CellType, T}(entries))
end

function _scope_declaration(parameter::ModelParameter, fragment::ModelFragment, mapping)
    return ModelParameter(_mapped_identity(mapping, parameter.name), parameter.value)
end
function _scope_rule_expression(expression::ConditionalExpression, mapping)
    return ConditionalExpression(
        _scope_rule_expression(expression.condition, mapping),
        _scope_rule_expression(expression.if_true, mapping),
        _scope_rule_expression(expression.if_false, mapping))
end
_scope_rule_expression(expression, mapping) = expression

function _phase_diagnostics(components::Tuple)
    rules = Tuple(component for component in components if component isa Rule)
    isempty(rules) && return ()
    diagnostics = ()

    draw_addresses = Dict{UInt16, Vector{Tuple{SemanticName, Symbol}}}()
    for rule in rules, draw in _random_draws(rule.expression)
        label = something(draw.label, :draw)
        operation = UInt16(_semantic_rng_code(rule.name, label, UInt16(0x03ff)))
        identities = get!(draw_addresses, operation, Tuple{SemanticName, Symbol}[])
        identity = (rule.name, label)
        identity in identities || push!(identities, identity)
    end
    for (operation, identities) in draw_addresses
        length(identities) <= 1 && continue
        diagnostics = (diagnostics..., Diagnostic(:error,
            :random_draw_rng_identity_collision,
            "Level 1 random draws collide in the compiled RNG operation domain";
            related = (operation, identities...),
            correction = "rename one rule or draw label to obtain a distinct semantic address"))
    end

    phases = Dict{SemanticName, Tuple}()
    sources = Dict{SemanticName, Union{Nothing, SourceLocation}}()
    for rule in rules
        identity = rule.phase.name
        if haskey(phases, identity) && phases[identity] != rule.phase.after
            diagnostics = (diagnostics..., Diagnostic(:error,
                :inconsistent_phase_definition,
                "one phase identity has conflicting predecessor definitions";
                identity, related = (phases[identity], rule.phase.after),
                source = rule.source,
                correction = "reuse one Phase value for every rule in that phase"))
        else
            phases[identity] = rule.phase.after
            sources[identity] = rule.source
        end
    end

    rules_by_phase = Dict(identity => Tuple(rule for rule in rules
        if rule.phase.name == identity) for identity in keys(phases))
    for (identity, phase_rules) in rules_by_phase
        targets = Tuple(rule.target for rule in phase_rules)
        duplicates = Tuple(unique(target for target in targets
            if count(==(target), targets) > 1))
        isempty(duplicates) || (diagnostics = (diagnostics..., Diagnostic(
            :error, :duplicate_phase_writer,
            "one rule phase cannot write the same property more than once";
            identity, related = duplicates, source = sources[identity],
            correction = "combine the writers explicitly or place them in ordered phases"),))
    end

    function precedes(first_identity, second_identity, visited = Set{SemanticName}())
        first_identity == second_identity && return true
        second_identity in visited && return false
        push!(visited, second_identity)
        return any(dependency -> dependency == first_identity ||
            precedes(first_identity, dependency, visited),
            get(phases, second_identity, ()))
    end

    identities = sort!(collect(keys(phases)))
    for first_index in eachindex(identities)
        for second_index in (first_index + 1):length(identities)
            first_identity = identities[first_index]
            second_identity = identities[second_index]
            precedes(first_identity, second_identity) ||
                precedes(second_identity, first_identity) || begin
                first_rules = rules_by_phase[first_identity]
                second_rules = rules_by_phase[second_identity]
                first_writes = Set(rule.target for rule in first_rules)
                second_writes = Set(rule.target for rule in second_rules)
                first_reads = Set(identity for rule in first_rules
                    for identity in _expression_reads(rule.expression))
                second_reads = Set(identity for rule in second_rules
                    for identity in _expression_reads(rule.expression))
                hazard = !isempty(intersect(first_writes,
                    union(second_writes, second_reads))) ||
                    !isempty(intersect(second_writes,
                        union(first_writes, first_reads)))
                hazard && (diagnostics = (diagnostics..., Diagnostic(
                    :error, :unordered_phase_dependency,
                    "unordered rule phases have a read/write or write/write dependency";
                    identity = first_identity,
                    related = (second_identity,), source = sources[first_identity],
                    correction = "declare one phase `after` the other"),))
            end
        end
    end

    function visit(identity, active::Set{SemanticName}, complete::Set{SemanticName})
        identity in complete && return false
        identity in active && return true
        push!(active, identity)
        for dependency in get(phases, identity, ())
            visit(dependency, active, complete) && return true
        end
        delete!(active, identity)
        push!(complete, identity)
        return false
    end
    complete = Set{SemanticName}()
    for identity in keys(phases)
        visit(identity, Set{SemanticName}(), complete) || continue
        diagnostics = (diagnostics..., Diagnostic(:error, :phase_dependency_cycle,
            "rule phase dependencies must form a directed acyclic graph";
            identity, source = sources[identity],
            correction = "remove one dependency from the reported phase cycle"))
    end
    return diagnostics
end

const _RULE_OPERATIONS = Dict{Symbol, DataType}(
    :+ => AddOperation, :- => SubtractOperation, :* => MultiplyOperation,
    :/ => DivideOperation, :^ => PowerOperation, :< => LessOperation,
    :<= => LessEqualOperation, :> => GreaterOperation, :>= => GreaterEqualOperation,
    :(==) => EqualOperation, :(!=) => NotEqualOperation, :! => NotOperation,
    :min => MinOperation, :max => MaxOperation, :clamp => ClampOperation,
    :abs => AbsOperation, :sqrt => SqrtOperation, :exp => ExpOperation,
    :log => LogOperation, :sin => SinOperation, :cos => CosOperation,
    :tan => TanOperation, :ifelse => IfElseOperation,
)

const _DRAW_DISTRIBUTIONS = Dict{Symbol, Type}(
    :Bernoulli => Bernoulli, :Uniform => Uniform,
    :Normal => Normal, :UnitVector => UnitVector)

function _macro_draw(expression::Expr, owner::Symbol)
    arguments = collect(@view expression.args[2:end])
    parameters = !isempty(arguments) && first(arguments) isa Expr &&
        first(arguments).head === :parameters ? popfirst!(arguments) : nothing
    length(arguments) == 1 || throw(ArgumentError(
        "`draw` requires exactly one registered distribution descriptor"))
    distribution = _macro_rule_expression(only(arguments), owner)
    label = :(nothing)
    if parameters !== nothing
        length(parameters.args) == 1 || throw(ArgumentError(
            "`draw` accepts only the `label` keyword"))
        keyword = only(parameters.args)
        keyword isa Expr && keyword.head === :kw && keyword.args[1] === :label ||
            throw(ArgumentError("`draw` accepts only the `label` keyword"))
        value = keyword.args[2]
        value isa QuoteNode && value.value isa Symbol || throw(ArgumentError(
            "a draw label must be a literal Symbol"))
        label = QuoteNode(value.value)
    end
    return :($(GlobalRef(@__MODULE__, :draw))($distribution; label = $label))
end

function _macro_distribution(expression::Expr, owner::Symbol)
    constructor = _DRAW_DISTRIBUTIONS[first(expression.args)]
    if constructor === UnitVector
        arguments = @view expression.args[2:end]
        length(arguments) == 1 || throw(ArgumentError(
            "`UnitVector` requires exactly one dimension"))
        dimension = only(arguments)
        if dimension isa Integer
            return :($constructor($(QuoteNode(dimension))))
        elseif dimension isa Expr && dimension.head === :$
            return :($constructor($(esc(only(dimension.args)))))
        end
        throw(ArgumentError(
            "a unit-vector dimension must be the literal 2 or 3, or an interpolated integer"))
    end
    arguments = map(value -> _macro_rule_expression(value, owner),
        @view(expression.args[2:end]))
    return :($constructor($(arguments...)))
end

function _macro_rule_expression(expression, owner::Symbol)
    expression isa LineNumberNode && return nothing
    expression isa QuoteNode && return _macro_rule_expression(expression.value, owner)
    expression isa Union{Number, Bool, Char} &&
        return :($(GlobalRef(@__MODULE__, :RuleLiteral))($(QuoteNode(expression))))
    expression isa Symbol && expression === owner &&
        return :($(GlobalRef(@__MODULE__, :OwnerReference))($(QuoteNode(owner))))
    expression isa Symbol && throw(ArgumentError(
        "bare name `$expression` is not a Level 1 value; call a typed reference or interpolate it"))
    expression isa Expr || throw(ArgumentError(
        "unsupported Level 1 rule literal $(repr(expression))"))

    if expression.head === :$
        return :($(GlobalRef(@__MODULE__, :_rule_expression))($(esc(only(expression.args)))))
    elseif expression.head === :&& || expression.head === :||
        operation = expression.head === :&& ? AndOperation : OrOperation
        arguments = map(value -> _macro_rule_expression(value, owner), expression.args)
        return :($(GlobalRef(@__MODULE__, :ScalarCall))($operation(), ($(arguments...),)))
    elseif expression.head === :if
        length(expression.args) == 3 || throw(ArgumentError(
            "Level 1 if expressions require an explicit else branch"))
        condition, if_true, if_false = map(
            value -> _macro_rule_expression(value, owner), expression.args)
        return :($(GlobalRef(@__MODULE__, :ConditionalExpression))(
            $condition, $if_true, $if_false))
    elseif expression.head === :block
        values = filter(value -> !(value isa LineNumberNode), expression.args)
        length(values) == 1 || throw(ArgumentError(
            "multi-expression rule blocks require the local-binding compiler"))
        return _macro_rule_expression(only(values), owner)
    elseif expression.head !== :call
        throw(ArgumentError("unsupported Level 1 syntax `$(expression.head)`"))
    end

    function_name = first(expression.args)
    arguments = @view expression.args[2:end]
    function_name === :draw && return _macro_draw(expression, owner)
    function_name isa Symbol && function_name in _SPATIAL_QUERY_FUNCTIONS &&
        return _macro_spatial_query(expression, owner)
    function_name isa Symbol && haskey(_DRAW_DISTRIBUTIONS, function_name) &&
        return _macro_distribution(expression, owner)
    function_name === :NoChange && isempty(arguments) &&
        return :($(GlobalRef(@__MODULE__, :NoChange))())
    if function_name isa Symbol && haskey(_RULE_OPERATIONS, function_name)
        operation = _RULE_OPERATIONS[function_name]
        lowered = map(value -> _macro_rule_expression(value, owner), arguments)
        return :($(GlobalRef(@__MODULE__, :ScalarCall))($operation(), ($(lowered...),)))
    end
    function_name isa Symbol || throw(ArgumentError(
        "Level 1 callable references must use a simple typed Julia binding"))
    length(arguments) == 1 || throw(ArgumentError(
        "a Level 1 property reference requires exactly one owner argument"))
    argument = _macro_rule_expression(only(arguments), owner)
    return :($(GlobalRef(@__MODULE__, :_rule_reference))(
        $(esc(function_name)), $argument))
end

function _macro_assignment(expression)
    expression isa Expr && expression.head === :(=) || throw(ArgumentError(
        "a Level 1 rule must use `property(owner) = expression`"))
    target, value = expression.args
    target isa Expr && target.head === :call && length(target.args) == 2 ||
        throw(ArgumentError("a Level 1 rule target must be `property(owner)`"))
    property, owner = target.args
    property isa Symbol && owner isa Symbol || throw(ArgumentError(
        "a Level 1 rule target must use simple property and owner bindings"))
    return property, owner, value
end

function _macro_phase(expression)
    expression isa Expr && expression.head === :(=) && expression.args[1] === :phase ||
        throw(ArgumentError("a Level 1 rule requires `phase = phase_value`"))
    return expression.args[2]
end

function _source_expression(source::LineNumberNode)
    return :($(GlobalRef(@__MODULE__, :SourceLocation))(
        $(string(source.file)), $(source.line)))
end

macro rule(phase_expression, assignment)
    phase = _macro_phase(phase_expression)
    property, owner, value = _macro_assignment(assignment)
    lowered = _macro_rule_expression(value, owner)
    source = _source_expression(__source__)
    return :($(GlobalRef(@__MODULE__, :Rule))(
        $(esc(property)), $(QuoteNode(owner)), $lowered;
        phase = $(esc(phase)), source = $source))
end

macro rules(phase_expression, block)
    phase = _macro_phase(phase_expression)
    block isa Expr && block.head === :block || throw(ArgumentError(
        "`@rules` requires a begin/end block"))
    assignments = filter(value -> !(value isa LineNumberNode), block.args)
    isempty(assignments) && throw(ArgumentError("`@rules` requires at least one assignment"))
    rules = map(assignments) do assignment
        property, owner, value = _macro_assignment(assignment)
        lowered = _macro_rule_expression(value, owner)
        :($(GlobalRef(@__MODULE__, :Rule))(
            $(esc(property)), $(QuoteNode(owner)), $lowered;
            phase = $(esc(phase)), source = $(_source_expression(__source__))))
    end
    return :($(GlobalRef(@__MODULE__, :RuleGroup))(($(rules...),);
        source = $(_source_expression(__source__))))
end

macro trigger(assignment)
    name, owner, value = _macro_assignment(assignment)
    lowered = _macro_rule_expression(value, owner)
    return :($(GlobalRef(@__MODULE__, :TriggerRule))(
        $(QuoteNode(name)), $(QuoteNode(owner)), $lowered;
        source = $(_source_expression(__source__))))
end
