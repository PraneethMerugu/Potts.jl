# `@potts_model Name begin … end`: sugar for a constructor `Name(; name, structural…,
# parameters…)` that builds a `PottsSystem` (as `@mtkmodel` builds an MTK system).
#
# Expressions are evaluated as ordinary Julia at construction time with the built-in names
# bound to symbols, after a syntactic rewrite (`rewrite`) that makes indexing, `&&`/`||`/`!`,
# ternaries and generator folds over relations symbolic.

const SECTIONS = (Symbol("@structural_parameters"), Symbol("@kinds"), Symbol("@parameters"),
    Symbol("@variables"), Symbol("@lattice"), Symbol("@relations"), Symbol("@energy"),
    Symbol("@drive"), Symbol("@constraint"), Symbol("@on_copy"), Symbol("@after_mcs"),
    Symbol("@before_mcs"), Symbol("@equations"), Symbol("@divide"), Symbol("@sweep"),
    Symbol("@relationship"), Symbol("@link"), Symbol("@unlink"))

"""
    @potts_model Name begin
        @structural_parameters begin lattice = (72, 72) end
        @kinds medium dark light
        @parameters begin λ = 1.0; J[kind, kind] = [0 16 16; 16 2 11; 16 11 14] end
        @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
        @energy begin
            cells(dark, light) => λ * (volume - V₀)^2
            contacts           => J[kind, kind′]
        end
        @sweep Metropolis(; temperature = T)
    end

Define a model constructor `Name(; name = :Name, kwargs...)`; keyword arguments override
structural parameters and parameter defaults. See `docs/design/AUTHORING.md`.
"""
macro potts_model(name, body)
    return esc(_potts_model(name, body, __module__))
end

struct _Parts
    structural::Vector{Any}      # (name, default)
    params::Vector{Symbol}
    code::Vector{Any}
end

function _potts_model(name::Symbol, body::Expr, mod)
    body.head === :block || throw(ArgumentError("@potts_model $name expects a begin … end block"))
    parts = _Parts(Any[], Symbol[], Any[])
    for ex in body.args
        ex isa LineNumberNode && (push!(parts.code, ex); continue)
        if ex isa Expr && ex.head === :macrocall && ex.args[1] in SECTIONS
            _section!(parts, ex.args[1], filter(a -> !(a isa LineNumberNode), ex.args[3:end]))
        else
            push!(parts.code, rewrite(ex))        # helper functions, local definitions
        end
    end
    kws = Any[Expr(:kw, :name, QuoteNode(name))]
    for (k, v) in parts.structural
        k in parts.params && throw(ArgumentError("`$k` is both a structural parameter and a parameter"))
        push!(kws, Expr(:kw, k, v))
    end
    for k in parts.params
        push!(kws, Expr(:kw, k, :nothing))        # `Model(; λ = 2.0)` overrides the default
    end
    P = :(Potts)
    preamble = quote
        (; volume, surface, kind, kind′, owner, owner′, id, generation, weight, source, target, old, new, mcs, position, distance) = $P.B
        $P._GATHER_COUNT[] = 0                    # gather variables are numbered per model
        t = $P.t
        D = $P.D
        Pre = $P.Pre
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, keys(DSL)...)), :($P.DSL)))
        __kinds = Symbol[]
        __params = Any[]
        __vars = Any[]
        __relations = Dict{Symbol, Any}()
        __energies = $P.EnergyTerm[]
        __drives = $P.Drive[]
        __constraints = $P.Constraint[]
        __updates = $P.Update[]
        __equations = $P.Equation[]
        __divisions = $P.DivideRule[]
        __relationships = $P.RelationshipSpec[]
        __links = $P.LinkRule[]
        __lattice = nothing
        __sweep = nothing
    end
    structural = Expr(:tuple, Expr(:parameters, [Expr(:kw, k, k) for (k, _) in parts.structural]...))
    finish = :($P.PottsSystem(; name, kinds = __kinds, lattice = __lattice, parameters = __params,
        variables = __vars, relations = __relations, energies = __energies, drives = __drives,
        constraints = __constraints, updates = __updates, equations = __equations,
        divisions = __divisions, relationships = __relationships, link_rules = __links,
        sweep = __sweep, structural = $structural))
    return quote
        function $name(; $(kws...))
            $preamble
            $(parts.code...)
            __lattice === nothing && throw(ArgumentError($("model $name has no @lattice")))
            __sweep === nothing && throw(ArgumentError($("model $name has no @sweep")))
            $finish
        end
    end
end

_lines(args) = length(args) == 1 && args[1] isa Expr && args[1].head === :block ?
               filter(a -> !(a isa LineNumberNode), args[1].args) : args
_strip(ex) = ex isa Expr && ex.head === :block ? only(filter(a -> !(a isa LineNumberNode), ex.args)) : ex

function _section!(parts, sec, args)
    P = :(Potts)
    code = parts.code
    if sec === Symbol("@structural_parameters")
        for l in _lines(args)
            l isa Expr && l.head === :(=) || throw(ArgumentError("structural parameters are `name = default`"))
            push!(parts.structural, (l.args[1], l.args[2]))
        end
    elseif sec === Symbol("@kinds")
        names = Symbol[]
        for l in _lines(args)
            l isa Symbol || throw(ArgumentError("@kinds lists kind names; the first is the medium"))
            push!(names, l)
        end
        for (i, k) in enumerate(names)
            push!(code, :($k = $(i - 1)), :(push!(__kinds, $(QuoteNode(k)))))
        end
    elseif sec === Symbol("@parameters")
        for l in _lines(args)
            lhs, val = l isa Expr && l.head === :(=) ? (l.args[1], _strip(l.args[2])) : (l, nothing)
            if lhs isa Expr && lhs.head === :ref
                k = lhs.args[1]
                push!(parts.params, k)
                push!(code, :($k = $P.kind_parameter($(QuoteNode(k)), $k === nothing ? $val : $k)))
            else
                k = lhs::Symbol
                push!(parts.params, k)
                push!(code, :($k = $P.parameter($(QuoteNode(k)), $k === nothing ? $(rewrite(val)) : $k)))
            end
            push!(code, :(push!(__params, $k)))
        end
    elseif sec === Symbol("@variables")
        for l in _lines(args)
            decl, rhs = l isa Expr && l.head === :(=) ? (l.args[1], _strip(l.args[2])) : (l, nothing)
            decl isa Expr && decl.head === :call && length(decl.args) == 2 ||
                throw(ArgumentError("variables are declared with a scope: `x(site)`, `x(cell)`, `x(model)`, `c(field)`"))
            k, scope = decl.args
            default, opts = rhs isa Expr && rhs.head === :tuple ? (rhs.args[1], rhs.args[2]) : (rhs, nothing)
            kw = opts === nothing ? Any[] : [Expr(:kw, o.args[1], o.args[2]) for o in opts.args]
            default === nothing || push!(kw, Expr(:kw, :default, default))
            push!(code, :($k = $P.variable(only($P.Symbolics.@variables $k(t)), $(QuoteNode(scope)); $(kw...))),
                :(push!(__vars, $k)))
        end
    elseif sec === Symbol("@lattice")
        push!(code, :(__lattice = $(_replace_call(only(args), :Lattice, :($P.lattice_spec)))))
    elseif sec === Symbol("@relations")
        for l in _lines(args)
            k = l.args[1]
            push!(code, :(__relations[$(QuoteNode(k))] = $(l.args[2])), :($k = $P.RelationRef($(QuoteNode(k)))))
        end
    elseif sec === Symbol("@energy")
        for l in _lines(args)
            e = :(push!(__energies, $P.energy($(rewrite(l)))))
            push!(code, _is_edges(l) ? _edge_scope(e) : e)
        end
    elseif sec === Symbol("@relationship")
        decl = args[1]
        decl isa Expr && decl.head === :call || throw(ArgumentError("@relationship name(cell, cell) capacity = k"))
        k = decl.args[1]
        opts, _ = _options(args[2:end])
        kw = [Expr(:kw, o, v) for (o, v) in opts if o !== :distance]
        push!(code, :(push!(__relationships, $P.relationship($(QuoteNode(k)); $(kw...)))),
            :($k = $P.RelationshipRef($(QuoteNode(k)))))
    elseif sec in (Symbol("@link"), Symbol("@unlink"))
        action = QuoteNode(sec === Symbol("@link") ? :link : :unlink)
        opts, _ = _options(args[2:end])
        kw = [Expr(:kw, o, rewrite(v)) for (o, v) in opts]
        push!(code, _edge_scope(:(push!(__links, $P.link_rule($action, $(args[1]); $(kw...))))))
    elseif sec === Symbol("@drive")
        foreach(l -> push!(code, :(push!(__drives, $P.drive($(rewrite(_replace_copy(l))))))), _lines(args))
    elseif sec === Symbol("@constraint")
        foreach(l -> push!(code, :(push!(__constraints, $P.constraint($(rewrite(l)))))), _lines(args))
    elseif sec in (Symbol("@on_copy"), Symbol("@after_mcs"), Symbol("@before_mcs"))
        phase = QuoteNode(Symbol(String(sec)[2:end]))
        every = length(args) == 2 ? args[1] : nothing
        eqs = _lines(args[end:end])
        for l in eqs
            push!(code, every === nothing ? :(push!(__updates, $P.update($phase, $(rewrite(l))))) :
                        :(push!(__updates, $P.update($phase, $every, $(rewrite(l))))))
        end
    elseif sec === Symbol("@equations")
        foreach(l -> push!(code, :(push!(__equations, $(rewrite(l))))), _lines(args))
    elseif sec === Symbol("@divide")
        domain = args[1]
        opts, rules = _options(args[2:end])
        kw = [Expr(:kw, k, rewrite(v)) for (k, v) in opts]
        push!(code, :(push!(__divisions, $P.divide($domain, $(map(rewrite, rules)...); $(kw...)))))
    elseif sec === Symbol("@sweep")
        ex = only(args)
        ex = _replace_call(ex, :Metropolis, :($P.sweep_spec), QuoteNode(:metropolis))
        ex = _replace_call(ex, :Barker, :($P.sweep_spec), QuoteNode(:barker))
        push!(code, :(__sweep = $(rewrite(ex))))
    end
    return parts
end

# Replace a call to `from(args…)` by `to([extra,] args…)` at the top of `ex`.
function _replace_call(ex, from, to, extra...)
    ex isa Expr && ex.head === :call && ex.args[1] === from || return ex
    params = filter(a -> a isa Expr && a.head === :parameters, ex.args[2:end])
    rest = filter(a -> !(a isa Expr && a.head === :parameters), ex.args[2:end])
    return Expr(:call, to, params..., extra..., rest...)
end

# Edge-scoped statements see the link endpoints `a`, `b` (bound only there, so parameters
# named `a`/`b` elsewhere are unaffected).
_edge_scope(ex) = :(let a = Potts.B.a, b = Potts.B.b
    $ex
end)

_is_edges(l) = l isa Expr && l.head === :call && l.args[1] === :(=>) &&
               l.args[2] isa Expr && l.args[2].head === :call && l.args[2].args[1] === :edges

_replace_copy(ex) = ex isa Expr && ex.head === :call && ex.args[1] === :(=>) && ex.args[2] === :copy ?
                    Expr(:call, :(=>), :(Potts.COPY), ex.args[3]) : ex

# `when = a, along = b, x => 1` arrives as nested `=`/tuple chains; flatten to options + rules.
function _options(args)
    toks = Any[]
    flat(e) = e isa Expr && e.head === :(=) ? (flatitems(e.args[1]); push!(toks, :__EQ); flatitems(e.args[2])) :
              flatitems(e)
    flatitems(e) = e isa Expr && e.head === :tuple ? foreach(x -> x isa Expr && x.head === :(=) ? flat(x) : push!(toks, x), e.args) :
                   e isa Expr && e.head === :(=) ? flat(e) : push!(toks, e)
    foreach(flat, args)
    opts = Pair{Symbol, Any}[]; rules = Any[]
    i = 1
    while i <= length(toks)
        if i + 2 <= length(toks) && toks[i + 1] === :__EQ
            push!(opts, toks[i] => toks[i + 2]); i += 3
        else
            push!(rules, toks[i]); i += 1
        end
    end
    return opts, rules
end

"""
    rewrite(ex)

Make user syntax symbolic: `x[i…]` → `_index`, `&&`/`||`/`!` → symbolic logic, `c ? a : b`
→ `ifelse`, and `fold(body for n in R(s) if cond)` → a relation gather.
"""
function rewrite(ex)
    ex isa Expr || return ex
    P = :(Potts)
    h = ex.head
    if h === :ref
        return Expr(:call, :($P._index), map(rewrite, ex.args)...)
    elseif h in (:(=), :+=, :-=, :*=, :/=) || (h === :function && length(ex.args) == 2)
        # assignment targets and function signatures are not expressions: leave them alone
        return Expr(h, ex.args[1], rewrite(ex.args[2]))
    elseif h === :&&
        return :($P._andq($(rewrite(ex.args[1])), () -> $(rewrite(ex.args[2]))))
    elseif h === :||
        return :($P._orq($(rewrite(ex.args[1])), () -> $(rewrite(ex.args[2]))))
    elseif h === :if && length(ex.args) == 3 && !_isblock(ex.args[2]) && !_isblock(ex.args[3])
        # lazy on real conditions, `ifelse` on symbolic ones
        return :($P._ifelseq($(rewrite(ex.args[1])), () -> $(rewrite(ex.args[2])), () -> $(rewrite(ex.args[3]))))
    elseif h === :call && ex.args[1] === :! && length(ex.args) == 2
        return Expr(:call, :($P._notq), rewrite(ex.args[2]))
    elseif h === :call && length(ex.args) == 2 && ex.args[2] isa Expr && ex.args[2].head === :generator
        return _rewrite_gather(ex.args[1], ex.args[2])
    elseif h === :quote || h === :macrocall && ex.args[1] === Symbol("@variables")
        return ex
    end
    return Expr(h, map(rewrite, ex.args)...)
end
_isblock(e) = e isa Expr && e.head === :block

function _rewrite_gather(fold, gen)
    P = :(Potts)
    body = gen.args[1]
    spec = gen.args[2]
    cond = nothing
    if spec isa Expr && spec.head === :filter
        cond, spec = spec.args[1], spec.args[2]
    end
    plain = Expr(:call, fold, Expr(:generator, map(rewrite, gen.args)...))
    spec isa Expr && spec.head === :(=) || return plain
    n, iter = spec.args
    # `R(s)` may be a relation at a site (a gather) or an ordinary call: decided at run time
    (n isa Symbol && iter isa Expr && iter.head === :call && length(iter.args) == 2) || return plain
    condf = cond === nothing ? :nothing : :($n -> $(rewrite(cond)))
    return :($P._fold_or_gather($fold, $n -> $(rewrite(body)), $(rewrite(iter.args[1])),
        $(rewrite(iter.args[2])), $condf))
end

"""A named relation declared in `@relations`."""
struct RelationRef
    name::Symbol
end
ContactDomain(r::RelationRef) = ContactDomain(r.name)
(d::ContactDomain)(r::RelationRef) = ContactDomain(r.name)
