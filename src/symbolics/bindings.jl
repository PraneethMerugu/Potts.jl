"""
    ProposalContext(name)

A symbolic handle for the proposal snapshot. Property access constructs registered
Symbolics operations; it never reads mutable runtime state.
"""
struct ProposalContext
    name::Symbol
    token::Symbolics.Num
    function ProposalContext(name::Symbol)
        isempty(String(name)) &&
            throw(ArgumentError("a proposal binding name cannot be empty"))
        return new(name, Symbolics.variable(Symbol("__potts_proposal__", name)))
    end
    ProposalContext(name::Symbol, token::Symbolics.Num) = new(name, token)
end

"""
    RelationshipBinding(name, relationship)

A symbolic handle for one edge in a bounded relationship iteration domain.
"""
struct RelationshipBinding{R}
    name::Symbol
    relationship::R
    token::Symbolics.Num
    function RelationshipBinding(name::Symbol, relationship)
        isempty(String(name)) &&
            throw(ArgumentError("a relationship binding name cannot be empty"))
        token = Symbolics.variable(Symbol("__potts_relationship__", name))
        return new{typeof(relationship)}(name, relationship, token)
    end
    RelationshipBinding(name::Symbol, relationship, token::Symbolics.Num) =
        new{typeof(relationship)}(name, relationship, token)
end

Base.show(io::IO, binding::ProposalContext) = print(io, "ProposalContext(", repr(binding.name), ")")
Base.show(io::IO, binding::RelationshipBinding) =
    print(io, "RelationshipBinding(", repr(binding.name), ", ",
        repr(Symbol(statement_id(binding.relationship))), ")")

_binding_token(binding::ProposalContext) = getfield(binding, :token)
_binding_token(binding::RelationshipBinding) = getfield(binding, :token)

function Base.getproperty(binding::ProposalContext, name::Symbol)
    name === :name && return getfield(binding, :name)
    name === :token && return getfield(binding, :token)
    name === :source_site && return source_site(_binding_token(binding))
    name === :target_site && return target_site(_binding_token(binding))
    name === :source_cell && return source_cell(_binding_token(binding))
    name === :target_cell && return target_cell(_binding_token(binding))
    name === :source_kind && return source_kind(_binding_token(binding))
    name === :target_kind && return target_kind(_binding_token(binding))
    name === :is_extension && return is_extension(_binding_token(binding))
    name === :is_retraction && return is_retraction(_binding_token(binding))
    throw(ArgumentError("unknown ProposalContext binding `$name`"))
end

function Base.getproperty(binding::RelationshipBinding, name::Symbol)
    name === :name && return getfield(binding, :name)
    name === :relationship && return getfield(binding, :relationship)
    name === :token && return getfield(binding, :token)
    name === :a && return endpoint_a(_binding_token(binding))
    name === :b && return endpoint_b(_binding_token(binding))
    return edge_payload(_binding_token(binding), Val(name))
end

function map_symbolics(f, binding::ProposalContext)
    return ProposalContext(binding.name, f(_binding_token(binding)))
end

map_symbolics(f, binding::RelationshipBinding) =
    RelationshipBinding(binding.name, binding.relationship, f(_binding_token(binding)))
