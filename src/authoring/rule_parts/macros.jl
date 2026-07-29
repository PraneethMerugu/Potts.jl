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
