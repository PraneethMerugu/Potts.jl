"""Immutable, ordered collection of uniquely identified Potts statements."""
struct StatementSet{T <: Tuple}
    values::T
    StatementSet(values::T, ::Val{:raw}) where {T <: Tuple} = new{T}(values)
end

StatementSet() = StatementSet((), Val(:raw))
StatementSet(statement::AbstractPottsStatement) = StatementSet((statement,))

function StatementSet(values)
    flattened = AbstractPottsStatement[]
    for value in values
        if value isa StatementSet
            append!(flattened, value.values)
        elseif value isa AbstractPottsStatement
            push!(flattened, value)
        else
            throw(ArgumentError(
                "StatementSet accepts Potts statements, got $(typeof(value))"
            ))
        end
    end
    return StatementSet(Tuple(flattened), Val(:raw))
end

statements(set::StatementSet) = set.values
statements(statement::AbstractPottsStatement) = (statement,)
Base.length(set::StatementSet) = length(set.values)
Base.isempty(set::StatementSet) = isempty(set.values)
Base.iterate(set::StatementSet, state...) = iterate(set.values, state...)
Base.getindex(set::StatementSet, index::Integer) = set.values[index]
Base.eltype(::Type{<:StatementSet}) = AbstractPottsStatement

function Base.show(io::IO, set::StatementSet)
    print(io, "StatementSet(", length(set), " statement")
    length(set) == 1 || print(io, "s")
    print(io, ")")
end

function _capture_statement(statement, source::SourceLocation)
    if statement isa StatementSet
        return StatementSet(with_source(item, source) for item in statement)
    elseif statement isa AbstractPottsStatement
        return with_source(statement, source)
    end
    throw(ArgumentError("@statements entries must construct Potts statements"))
end

function _statement_capture_source(expression, location, line, caller)
    return :(
        $(GlobalRef(@__MODULE__, :SourceLocation))(
            $(String(location.file)), $line, $(QuoteNode(nameof(caller))), $(string(expression)),
        )
    )
end

# Resolve only the binding explicitly named by a macro call. Never evaluate
# author code or classify a declaration by the spelling of its macro name.
function _statement_macro_binding(caller::Module, name)
    if name isa Symbol
        return isdefined(caller, name) ? getfield(caller, name) : nothing
    elseif name isa GlobalRef
        return isdefined(name.mod, name.name) ? getfield(name.mod, name.name) : nothing
    elseif name isa Expr && name.head === :. && length(name.args) == 2
        owner = _statement_macro_binding(caller, first(name.args))
        field = last(name.args)
        owner isa Module && field isa QuoteNode && field.value isa Symbol || return nothing
        return isdefined(owner, field.value) ? getfield(owner, field.value) : nothing
    end
    return nothing
end

function _statement_declaration_kind(caller, expression)
    expression isa Expr && expression.head === :macrocall || return nothing
    binding = _statement_macro_binding(caller, first(expression.args))
    binding === getfield(ModelingToolkitBase, Symbol("@parameters")) && return :parameters
    binding === getfield(Symbolics, Symbol("@variables")) && return :unknowns
    return nothing
end

function _capture_system_expression(constructor, block, location, caller)
    constructor isa Expr && constructor.head === :call ||
        throw(ArgumentError("@statements constructor form requires PottsSystem(; keywords...)"))
    keywords = Any[]
    for argument in constructor.args[2:end]
        if argument isa Expr && argument.head === :parameters
            append!(keywords, argument.args)
        elseif argument isa Expr && argument.head === :kw
            push!(keywords, argument)
        else
            throw(ArgumentError("@statements constructor accepts keyword arguments only"))
        end
    end
    captured, variables, parameters = gensym.((:statements, :unknowns, :parameters))
    body = Any[:($captured = Any[]), :($variables = Any[]), :($parameters = Any[])]
    expressions = block isa Expr && block.head === :block ? block.args : Any[block]
    line = location.line
    for expression in expressions
        if expression isa LineNumberNode
            line = expression.line
            continue
        end
        kind = _statement_declaration_kind(caller, expression)
        if kind !== nothing
            inventory = kind === :parameters ? parameters : variables
            push!(body, :(append!($inventory, $(esc(expression)))))
        else
            source = _statement_capture_source(expression, location, line, caller)
            push!(body, :(push!($captured, $(GlobalRef(@__MODULE__, :_capture_statement))($(esc(expression)), $source))))
        end
    end
    keyword_values = Expr(:tuple, Expr(:parameters, map(esc, keywords)...))
    push!(
        body, :(
            $(GlobalRef(@__MODULE__, :_assemble_declared_system))(
                $(esc(first(constructor.args))), $keyword_values,
                $(GlobalRef(@__MODULE__, :StatementSet))($captured), $variables, $parameters,
            )
        )
    )
    return Expr(:block, body...)
end

"""
Construct a `StatementSet` while retaining source provenance.

`@statements PottsSystem(; name, keywords...) begin ... end` also enrolls
top-level `@variables` and `@parameters` declarations in the ordinary system's
symbolic inventories. The block runs first, then constructor keywords, each
exactly once. Declaring a symbolic variable does not declare physical state.
"""
macro statements(arguments...)
    length(arguments) == 2 && return _capture_system_expression(arguments..., __source__, __module__)
    length(arguments) == 1 || throw(ArgumentError("@statements expects a block or a constructor and block"))
    block = only(arguments)
    expressions = block isa Expr && block.head === :block ? block.args : Any[block]
    captured = Any[]
    line = __source__.line
    capture_statement = GlobalRef(@__MODULE__, :_capture_statement)
    statement_set = GlobalRef(@__MODULE__, :StatementSet)
    for expression in expressions
        if expression isa LineNumberNode
            line = expression.line
            continue
        end
        source = _statement_capture_source(expression, __source__, line, __module__)
        push!(captured, :($capture_statement($(esc(expression)), $source)))
    end
    return :($statement_set(($(captured...),)))
end
