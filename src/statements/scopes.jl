"""
    scoped(f, domain, name)

Construct ordinary declarations in the named cell or site scope. The callback
receives a `CellBinding` or `SiteBinding` and returns a `StatementSet`. State
declared in that set retains the domain and anchor; processes resolve their
iteration domain from the declared targets during completion. Nested scopes
retain their own bindings. Imported references are not enrolled or copied.

Scope names are explicit lexical identities within a component, independent of
the Julia callback variable's name. Use distinct names for distinct nested
anchors. No construction state survives outside the returned declarations.
"""
function scoped(f, domain::Union{Cells, Sites}, name::Symbol)
    binding = domain isa Cells ? CellBinding(name, domain) : SiteBinding(name, domain)
    declarations = f(binding)
    declarations isa StatementSet || throw(ArgumentError("a scoped callback must return a StatementSet"))
    return StatementSet(_bind_declaration_scope(statement, binding) for statement in declarations)
end

function _bind_declaration_scope(statement::AbstractPottsStatement, binding)
    if statement isa SynchronousProcess
        options = _statement_options(statement)
        get(options, :anchor, nothing) === nothing || return statement
        return _with_scope_payload(statement; options = merge(options, (; anchor = binding)))
    end
    statement isa Union{CellState, SiteState, FieldState} || return statement
    options = _statement_options(statement)
    get(options, :scope, nothing) === nothing || return statement
    matches = binding isa CellBinding ? statement isa CellState : statement isa Union{SiteState, FieldState}
    matches || throw(ArgumentError("$(statement_kind(statement)) does not belong to this $(typeof(binding.domain)) scope"))
    return _with_scope_payload(statement; options = merge(options, (; scope = binding)))
end

function _with_scope_payload(
        statement::Union{SynchronousProcess, CellState, SiteState, FieldState};
        arguments = _statement_arguments(statement), options = _statement_options(statement)
    )
    core = getfield(statement, :core)
    constructor = statement isa SynchronousProcess ? SynchronousProcess :
        statement isa CellState ? CellState : statement isa SiteState ? SiteState : FieldState
    return constructor(StatementCore(core.id, arguments, options, core.source))
end

_declaration_scope(statement::AbstractPottsStatement) = _statement_option(statement, :scope, nothing)
