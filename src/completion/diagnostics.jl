struct PottsDiagnostic
    kind::Symbol
    identity::Union{Nothing, QualifiedStatementID, Symbol}
    expression::String
    namespace::Tuple{Vararg{Symbol}}
    expected::String
    actual::String
    alternatives::Tuple{Vararg{String}}
    source::AbstractStatementSource
end

function Base.show(io::IO, diagnostic::PottsDiagnostic)
    print(io, diagnostic.kind)
    diagnostic.identity === nothing ||
        print(io, " at ", diagnostic.identity)
    isempty(diagnostic.expected) ||
        print(io, ": expected ", diagnostic.expected)
    isempty(diagnostic.actual) ||
        print(io, ", got ", diagnostic.actual)
    if diagnostic.source isa SourceLocation
        print(io, " (", diagnostic.source.file, ":", diagnostic.source.line, ")")
    end
end

struct PottsValidationError <: Exception
    stage::Symbol
    diagnostics::Tuple{Vararg{PottsDiagnostic}}
end

function Base.showerror(io::IO, error::PottsValidationError)
    count = length(error.diagnostics)
    print(io, "Potts ", error.stage, " failed with ", count, " diagnostic")
    count == 1 || print(io, "s")
    for diagnostic in error.diagnostics
        print(io, "\n- ")
        show(io, diagnostic)
    end
end

_diagnostic_sort_key(diagnostic::PottsDiagnostic) = (
    join(String.(diagnostic.namespace), "/"),
    diagnostic.identity === nothing ? "" : string(diagnostic.identity),
    String(diagnostic.kind),
    diagnostic.expression,
)

function _throw_diagnostics(stage::Symbol, diagnostics)
    isempty(diagnostics) && return nothing
    ordered = sort!(collect(diagnostics); by = _diagnostic_sort_key)
    throw(PottsValidationError(stage, Tuple(ordered)))
end

