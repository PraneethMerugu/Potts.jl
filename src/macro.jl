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
    Symbol("@relationship"), Symbol("@link"), Symbol("@unlink"), Symbol("@observed"),
    Symbol("@extend"), Symbol("@components"))

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
    mod::Module                  # the calling module (globals shadowed by component names)
end

function _potts_model(name::Symbol, body::Expr, mod)
    body.head === :block || throw(ArgumentError("@potts_model $name expects a begin … end block"))
    parts = _Parts(Any[], Symbol[], Any[], mod)
    for ex in body.args
        ex isa LineNumberNode && (push!(parts.code, ex); continue)
        if ex isa Expr && ex.head === :macrocall && ex.args[1] in SECTIONS
            _section!(parts, ex.args[1], filter(a -> !(a isa LineNumberNode), ex.args[3:end]), ex.args[2])
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
        (; volume, surface, kind, kind′, owner, owner′, id, generation, weight, source, target, old, new, mcs, position, distance, cluster, cluster_volume, cluster_surface, time, site) = $P.B
        # gather variables and draws are numbered per model; a base built by `@extend` inside
        # another model continues the outer numbering (so the merged model has no collisions)
        $P._NESTING[] == 0 && ($P._GATHER_COUNT[] = 0)
        $P._DIM[] = 0                             # set by @lattice (vector builtins)
        t = $P.t
        D = $P._D
        Pre = $P._pre
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, keys(DSL)...)), :($P.DSL)))
        __kinds = Symbol[]
        __frozen = Int[]
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
        __observed = $P.ObservedEq[]
        __lattice = nothing
        __sweep = nothing
        __bases = $P.PottsSystem[]
        __sources = IdDict{Any, LineNumberNode}()
        __components = Any[]
    end
    structural = Expr(:tuple, Expr(:parameters, [Expr(:kw, k, k) for (k, _) in parts.structural]...))
    extends = any(ex -> ex isa Expr && ex.head === :macrocall && ex.args[1] === Symbol("@extend"), body.args)
    finish = :($P.PottsSystem(; name, kinds = __kinds, lattice = __lattice, parameters = __params,
        variables = __vars, relations = __relations, energies = __energies, drives = __drives,
        constraints = __constraints, updates = __updates, equations = __equations,
        divisions = __divisions, relationships = __relationships, link_rules = __links,
        observed = __observed, frozen_kinds = __frozen, sources = __sources, components = __components,
        sweep = __sweep, structural = $structural))
    return quote
        Base.@__doc__ function $name(; $(kws...))
            $preamble
            $(parts.code...)
            $(extends ? :(for b in __bases                # an extension inherits what it does not declare
                __lattice === nothing && (__lattice = b.lattice)
                __sweep === nothing && (__sweep = b.sweep)
                isempty(__kinds) && append!(__kinds, b.kinds)
            end) : nothing)
            __lattice === nothing && throw(ArgumentError($("model $name has no @lattice")))
            __sweep === nothing && throw(ArgumentError($("model $name has no @sweep")))
            $(extends ? :(foldl((s, b) -> $P.ModelingToolkitBase.extend(s, b; name), __bases; init = $finish)) : finish)
        end
    end
end

_lines(args) = length(args) == 1 && args[1] isa Expr && args[1].head === :block ?
               filter(a -> !(a isa LineNumberNode), args[1].args) : args
# lines with their source locations (a block's own line numbers, else the section's)
function _lines_ln(args, ln)
    length(args) == 1 && args[1] isa Expr && args[1].head === :block || return [(a, ln) for a in args]
    out = Tuple{Any, Any}[]
    for a in args[1].args
        a isa LineNumberNode ? (ln = a) : push!(out, (a, ln))
    end
    return out
end
# `push!(list, x)` recording where `x` was written (diagnostics)
_located_push(list, x, ln) = :(Potts._push_located!($list, __sources, $x, $(QuoteNode(ln))))
_push_located!(list, sources, x, ln) = push!(list, _source!(sources, x, ln))
_push_located!(list, sources, xs::AbstractVector, ln) = foreach(x -> _push_located!(list, sources, x, ln), xs)
# `lhs ~ rhs` → `Potts._eq(lhs, rhs)` (component-wise for vector quantities)
_rewrite_eq(l) = l isa Expr && l.head === :call && l.args[1] === :~ && length(l.args) == 3 ?
                 :(Potts._eq($(rewrite(l.args[2])), $(rewrite(l.args[3])))) : rewrite(l)
_is_range(ex) = ex isa Expr && ex.head === :call && ex.args[1] === :(:)

const _COMPOUND = (:+=, :-=, :*=, :/=)
"""
Compound assignments in an update block: `x += a` is `x ~ Pre(x) + a`, and every compound
write of one target folds into a single update reading the same previous value
(`x += a; x -= b` → `x ~ Pre(x) + a - b`). Mixing `~` and compound writes of one target, or
additive and multiplicative ones, is an error.
"""
function _combine_compound(lines)
    groups = Dict{String, Vector{Any}}()
    order = Any[]
    for (l, ln) in lines
        if l isa Expr && l.head in _COMPOUND
            key = string(l.args[1])
            if !haskey(groups, key)
                groups[key] = Any[]
                push!(order, (key, ln))
            end
            push!(groups[key], l)
        else
            push!(order, (l, ln))
        end
    end
    plain = Set(string(l.args[2]) for (l, _) in order if l isa Expr && l.head === :call && l.args[1] === :~)
    out = Tuple{Any, Any}[]
    for (item, ln) in order
        if item isa String
            ls = groups[item]
            item in plain && throw(ArgumentError("`$item` has both `~` and compound (`+=`, …) writes in one block"))
            ops = Set(l.head for l in ls)
            ops ⊆ Set((:+=, :-=)) || ops ⊆ Set((:*=, :/=)) ||
                throw(ArgumentError("`$item`: additive and multiplicative compound writes do not combine; write one equation"))
            lhs = ls[1].args[1]
            rhs = :(Pre($lhs))
            for l in ls
                op = Dict(:+= => :+, :-= => :-, :*= => :*, :/= => :/)[l.head]
                rhs = Expr(:call, op, rhs, l.args[2])
            end
            push!(out, (:($lhs ~ $rhs), ln))
        else
            push!(out, (item, ln))
        end
    end
    return out
end
_strip(ex) = ex isa Expr && ex.head === :block ? only(filter(a -> !(a isa LineNumberNode), ex.args)) : ex

function _section!(parts, sec, args, ln = nothing)
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
            if l isa Expr && l.head === :ref && l.args[2:end] == [:frozen]
                push!(code, :(push!(__frozen, $(length(names)))))    # `wall[frozen]`: an obstacle kind
                l = l.args[1]
            end
            l isa Symbol || throw(ArgumentError("@kinds lists kind names (optionally `name[frozen]`); the first is the medium"))
            push!(names, l)
        end
        for (i, k) in enumerate(names)
            push!(code, :($k = $(i - 1)), :(push!(__kinds, $(QuoteNode(k)))))
        end
    elseif sec === Symbol("@parameters")
        for l in _lines(args)
            lhs, val = l isa Expr && l.head === :(=) ? (l.args[1], _strip(l.args[2])) : (l, nothing)
            # `λ = 1.0, [unit = u"…"]` (MTK metadata)
            val, opts = val isa Expr && val.head === :tuple && length(val.args) == 2 && val.args[2] isa Expr &&
                        val.args[2].head === :vect ? (val.args[1], val.args[2]) : (val, nothing)
            kw = opts === nothing ? Any[] : [Expr(:kw, o.args[1], o.args[2]) for o in opts.args]
            all(k -> k.args[1] === :unit, kw) || throw(ArgumentError("parameter options: only `unit` is supported"))
            if lhs isa Expr && lhs.head === :ref && _is_range(lhs.args[2])     # `d[1:n]`: a vector
                k = lhs.args[1]
                push!(parts.params, k)
                push!(code, :($k = $P.vector_parameter($(QuoteNode(k)), $(lhs.args[2]), $k === nothing ? $val : $k; $(kw...))),
                    :(append!(__params, $k.components)))
                continue
            elseif lhs isa Expr && lhs.head === :ref
                k = lhs.args[1]
                push!(parts.params, k)
                push!(code, :($k = $P.kind_parameter($(QuoteNode(k)), $k === nothing ? $val : $k; $(kw...))))
            else
                k = lhs::Symbol
                push!(parts.params, k)
                push!(code, :($k = $P.parameter($(QuoteNode(k)), $k === nothing ? $(rewrite(val)) : $k; $(kw...))))
            end
            push!(code, :(push!(__params, $k)))
        end
    elseif sec === Symbol("@variables")
        for l in _lines(args)
            decl, rhs = l isa Expr && l.head === :(=) ? (l.args[1], _strip(l.args[2])) : (l, nothing)
            range = nothing
            if decl isa Expr && decl.head === :ref                         # `p(cell)[1:n]`: a vector
                range = decl.args[2]
                decl = decl.args[1]
            end
            decl isa Expr && decl.head === :call && length(decl.args) == 2 ||
                throw(ArgumentError("variables are declared with a scope: `x(site)`, `x(cell)`, `x(model)`, `c(field)`"))
            k, scope = decl.args
            default, opts = rhs isa Expr && rhs.head === :tuple ? (rhs.args[1], rhs.args[2]) : (rhs, nothing)
            kw = opts === nothing ? Any[] : [Expr(:kw, o.args[1], o.args[2]) for o in opts.args]
            default === nothing || push!(kw, Expr(:kw, :default, default))
            if range === nothing
                push!(code, :($k = $P.variable(only($P.Symbolics.@variables $k(t)), $(QuoteNode(scope)); $(kw...))),
                    :(push!(__vars, $k)))
            else
                push!(code, :($k = $P.vector_variable($(QuoteNode(k)), $range, $(QuoteNode(scope)); $(kw...))),
                    :(append!(__vars, $k.components)))
            end
        end
    elseif sec === Symbol("@extend")
        # `@extend Base()`, `@extend base = Base()` or `@extend a, b = base = Base()` (MTK)
        ex = only(args)
        names, rhs = Symbol[], ex
        if ex isa Expr && ex.head === :(=)
            lhs, rhs = ex.args
            if rhs isa Expr && rhs.head === :(=)       # names = base = Base()
                names = lhs isa Symbol ? [lhs] : Symbol[a for a in lhs.args]
                bname, rhs = rhs.args
            else
                bname = lhs
            end
        else
            bname = :__base
        end
        rhs isa Expr && rhs.head === :call || throw(ArgumentError("@extend expects a model call, e.g. `@extend λ = base = Sorting()`"))
        call = copy(rhs)
        any(a -> a isa Expr && a.head === :parameters, call.args) || insert!(call.args, 2, Expr(:parameters))
        params = call.args[findfirst(a -> a isa Expr && a.head === :parameters, call.args)]
        any(a -> a isa Expr && a.head === :kw && a.args[1] === :name, params.args) ||
            push!(params.args, Expr(:kw, :name, QuoteNode(bname)))
        push!(code, :($bname = $P._nested(() -> $call)), :(push!(__bases, $bname)))
        foreach(n -> push!(code, :($n = $P.lookup($bname, $(QuoteNode(n))))), names)
    elseif sec === Symbol("@components")
        # `@components clock = sys`, `@components cells(k) grn = sys`, or a block of `name = sys`
        domain = length(args) == 2 ? args[1] : :($P.cells)
        domain = domain === :model ? QuoteNode(:model) : :($P._domain($domain))   # `@components model drug = sys`
        for l in _lines(args[end:end])
            l isa Expr && l.head === :(=) && l.args[1] isa Symbol ||
                throw(ArgumentError("@components lines are `name = system`"))
            k = l.args[1]
            # `clock = clock`: the right-hand side means the caller's global, not the new local
            rhs = _globalize(l.args[2], k, parts.mod)
            # renamed, so `k.x` is `k₊x` whatever the system was called
            push!(code, :($k = $P.ModelingToolkitBase.rename($rhs, $(QuoteNode(k)))),
                :(push!(__components, $P.ComponentSpec($(QuoteNode(k)), $k, $domain))))
        end
    elseif sec === Symbol("@lattice")
        push!(code, :(__lattice = $(_replace_call(only(args), :Lattice, :($P.lattice_spec)))),
            :($P._DIM[] = length(__lattice.dims)))
    elseif sec === Symbol("@relations")
        for l in _lines(args)
            k = l.args[1]
            push!(code, :(__relations[$(QuoteNode(k))] = $(l.args[2])), :($k = $P.RelationRef($(QuoteNode(k)))))
        end
    elseif sec === Symbol("@energy")
        for (l, lln) in _lines_ln(args, ln)
            e = _located_push(:__energies, :($P.energy($(rewrite(l)))), lln)
            push!(code, _is_edges(l) ? _edge_scope(e) : e)
        end
    elseif sec === Symbol("@observed")
        for l in _lines(args)
            (l isa Expr && l.head === :call && l.args[1] === :~) || throw(ArgumentError("@observed lines are `name ~ expr`"))
            lhs = l.args[2]
            k = lhs isa Expr && lhs.head === :call ? lhs.args[1] : lhs      # `name(scope)` or `name`
            k isa Symbol || throw(ArgumentError("@observed: `$lhs` is not a name"))
            push!(code, :($k = $P.observed_var($(QuoteNode(k)))),
                _located_push(:__observed, :($P.ObservedEq($k, $(rewrite(l.args[3])))), ln))
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
        push!(code, _edge_scope(_located_push(:__links, :($P.link_rule($action, $(args[1]); $(kw...))), ln)))
    elseif sec === Symbol("@drive")
        foreach(((l, lln),) -> push!(code, _located_push(:__drives, :($P.drive($(rewrite(_replace_copy(l))))), lln)), _lines_ln(args, ln))
    elseif sec === Symbol("@constraint")
        foreach(((l, lln),) -> push!(code, _located_push(:__constraints, :($P.constraint($(rewrite(l)))), lln)), _lines_ln(args, ln))
    elseif sec in (Symbol("@on_copy"), Symbol("@after_mcs"), Symbol("@before_mcs"))
        phase = QuoteNode(Symbol(String(sec)[2:end]))
        every = length(args) == 2 ? args[1] : nothing
        for (l, lln) in _combine_compound(_lines_ln(args[end:end], ln))
            l = _rewrite_eq(l)
            push!(code, _located_push(:__updates, every === nothing ? :($P.update($phase, $l)) :
                                                  :($P.update($phase, $every, $l)), lln))
        end
    elseif sec === Symbol("@equations")
        foreach(((l, lln),) -> push!(code, _located_push(:__equations, _rewrite_eq(l), lln)), _lines_ln(args, ln))
    elseif sec === Symbol("@divide")
        domain = args[1]
        opts, rules = _options(args[2:end])
        kw = [Expr(:kw, k, rewrite(v)) for (k, v) in opts]
        push!(code, _located_push(:__divisions, :($P.divide($domain, $(map(rewrite, rules)...); $(kw...))), ln))
    elseif sec === Symbol("@sweep")
        ex = only(args)
        ex = _replace_call(ex, :Metropolis, :($P.sweep_spec), QuoteNode(:metropolis))
        ex = _replace_call(ex, :Barker, :($P.sweep_spec), QuoteNode(:barker))
        push!(code, :(__sweep = $(rewrite(ex))))
    end
    return parts
end

_globalize(ex, k, mod) = ex === k ? GlobalRef(mod, k) :
                         ex isa Expr ? Expr(ex.head, map(a -> _globalize(a, k, mod), ex.args)...) : ex

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
    # `k = v, rule` parses as `k = (v, rule)`; with no rule after a tuple value, `k = (1.0, 0.0)`
    # parses identically: the leading elements that are not rules/options form the value
    isrule(x) = x isa Expr && (x.head === :(=) || (x.head === :call && x.args[1] === :(=>)))
    function flatvalue(v)
        v isa Expr && v.head === :tuple || return flatitems(v)
        i = something(findfirst(isrule, v.args), length(v.args) + 1)
        lead = v.args[1:(i - 1)]
        isempty(lead) || push!(toks, length(lead) == 1 ? lead[1] : Expr(:tuple, lead...))
        foreach(x -> x isa Expr && x.head === :(=) ? flat(x) : push!(toks, x), v.args[i:end])
    end
    flat(e) = e isa Expr && e.head === :(=) ? (flatitems(e.args[1]); push!(toks, :__EQ); flatvalue(e.args[2])) :
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
    n isa Symbol || return plain
    condf = cond === nothing ? :nothing : :($n -> $(rewrite(cond)))
    # `R(s)` may be a relation at a site (a gather), `cells(k)`, or an ordinary call; other
    # iterators may be a population (`sites`, `cells(a, b)`): decided at run time
    (iter isa Expr && iter.head === :call && length(iter.args) == 2) ||
        return :($P._fold_iter($fold, $n -> $(rewrite(body)), $(rewrite(iter)), $condf))
    return :($P._fold_or_gather($fold, $n -> $(rewrite(body)), $(rewrite(iter.args[1])),
        $(rewrite(iter.args[2])), $condf))
end

"""A named relation declared in `@relations`."""
struct RelationRef
    name::Symbol
end
ContactDomain(r::RelationRef) = ContactDomain(r.name)
(d::ContactDomain)(r::RelationRef) = ContactDomain(r.name)
