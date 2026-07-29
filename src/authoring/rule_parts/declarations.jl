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
