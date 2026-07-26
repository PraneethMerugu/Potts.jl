"""
    ProcessBigraphError(code, message; context...)

Structured, stable failure used by the ProcessBigraphs declaration and serial
foundation. `code` is suitable for programmatic dispatch; `context` contains
only semantic identifiers and values, never Julia object addresses.
"""
struct ProcessBigraphError <: Exception
    code::Symbol
    message::String
    context::NamedTuple
end

ProcessBigraphError(code::Symbol, message::AbstractString; context...) =
    ProcessBigraphError(code, String(message), (; context...))

function Base.showerror(io::IO, error::ProcessBigraphError)
    print(io, "ProcessBigraphError(", error.code, "): ", error.message)
    isempty(error.context) || print(io, " ", error.context)
end

_fail(code::Symbol, message::AbstractString; context...) =
    throw(ProcessBigraphError(code, message; context...))
