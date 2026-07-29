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
