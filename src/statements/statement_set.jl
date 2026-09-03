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

"""Construct a `StatementSet` from statement expressions while retaining source provenance."""
macro statements(block)
    expressions = block isa Expr && block.head === :block ? block.args : Any[block]
    captured = Any[]
    line = __source__.line
    source_location = GlobalRef(@__MODULE__, :SourceLocation)
    capture_statement = GlobalRef(@__MODULE__, :_capture_statement)
    statement_set = GlobalRef(@__MODULE__, :StatementSet)
    for expression in expressions
        if expression isa LineNumberNode
            line = expression.line
            continue
        end
        source = :(
            $source_location(
                $(String(__source__.file)),
                $line,
                $(QuoteNode(nameof(__module__))),
                $(string(expression)),
            )
        )
        push!(captured, :($capture_statement($(esc(expression)), $source)))
    end
    return :($statement_set(($(captured...),)))
end
