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
    declared::Dict{Symbol, String}   # name → what declared it (collision checks)
end

# The hidden local holding parameter `k`'s constructor keyword. `@extend λ = base = Base()`
# rebinds the local `λ` to the base's symbol, so a redeclaration `@parameters λ = …` reads
# the keyword here (D-114). `#` keeps the name out of reach of user code.
_kw_local(k::Symbol) = Symbol("##kw#", k)

# Names the constructor binds itself: a declaration of one would be silently rebound.
const _BOUND_BUILTINS = (:volume, :surface, :kind, :kind′, :owner, :owner′, :id, :generation, :weight,
    :source, :target, :old, :new, :mcs, :position, :distance, :cluster, :cluster_volume, :cluster_surface,
    :time, :site, :major_length, :local_components, :ring_arcs, :ring_cells, :ring_medium)
_reserved_names() = Set{Symbol}([_BOUND_BUILTINS..., keys(DSL)..., :t, :D, :Pre, :name])
# The link endpoints `a`, `b` are reserved globally (D-075 Q8): no declaration (kind,
# parameter, variable, observed quantity, relation, relationship, component) may take their
# name, so nothing an edge term or link rule reads is shadowed (`_check_reserved_names`
# applies the same rule to a programmatic `PottsSystem`).
"""Record a declared name; reject built-in names and a second declaration of a name."""
function _declare!(parts::_Parts, k::Symbol, what::String)
    k in _reserved_names() && throw(ArgumentError(
        "$what `$k` has the name of a built-in (`$k` means something else in @potts_model); choose another name"))
    k in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message(what, k)))
    # `#…` names are the constructor's hidden locals (`_kw_local`)
    startswith(string(k), '#') && throw(ArgumentError("$what `$k`: a name cannot start with `#`; choose another name"))
    haskey(parts.declared, k) && throw(ArgumentError("$what `$k`: `$k` is already declared as $(_with_article(parts.declared[k]))"))
    parts.declared[k] = what
    return k
end

function _potts_model(name::Symbol, body::Expr, mod)
    body.head === :block || throw(ArgumentError("@potts_model $name expects a begin … end block"))
    d = _div_definition(body)
    d === nothing || throw(ArgumentError("@potts_model $name defines `$d`: inside a model `div(a, b)` and `a ÷ b` " *
                                         "are integer division; give the helper another name"))
    parts = _Parts(Any[], Symbol[], Any[], mod, Dict{Symbol, String}())
    for ex in body.args
        ex isa LineNumberNode && (push!(parts.code, ex); continue)
        if ex isa Expr && ex.head === :macrocall && ex.args[1] in SECTIONS
            _section!(parts, ex.args[1], filter(a -> !(a isa LineNumberNode), ex.args[3:end]), ex.args[2])
        elseif _conditional_sections(ex)
            push!(parts.code, _conditional!(parts, ex))
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
        # each parameter keyword, kept before `@extend` may rebind its name (D-114)
        $([:($(_kw_local(k)) = $k) for k in parts.params]...)
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, _BOUND_BUILTINS...)), :($P.B)))
        # gather variables and draws are numbered per build (`_in_build`); a base built by
        # `@extend` inside another model continues the outer numbering (no collisions)
        $P._set_dim!(0)                           # set by @lattice (vector builtins)
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
        variables = $P._bind_edge_scope(__vars, __relationships), relations = __relations, energies = __energies, drives = __drives,
        constraints = __constraints, updates = __updates, equations = __equations,
        divisions = __divisions, relationships = __relationships, link_rules = __links,
        observed = __observed, frozen_kinds = __frozen, sources = __sources, components = __components,
        sweep = __sweep, structural = $structural))
    targets = :(Dict{Symbol, String}($([:($(QuoteNode(k)) => $v) for (k, v) in _prime_targets(parts, body)]...)))
    return quote
        Base.@__doc__ function $name(; $(kws...))
          $P._in_build() do
            $preamble
            try
                $(parts.code...)
            catch __e
                $P._prime_error(__e, $targets, __bases)
                rethrow()
            end
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
end

# `x′` is bound only for a site or field variable `x` (the value at the other site of a
# contact pair; `@variables` declares it alongside `x`). Any other `x′` the section code
# reads is unbound, so the constructor fails with an `UndefVarError`; the constructor
# catches it and, when `x` is a declared or inherited quantity that is not a site/field
# variable, rethrows it as a Potts error (`_prime_error`). A local named `x′` (a `let`,
# generator or closure variable) never raises, so it stays valid Julia; the happy path pays
# nothing.
"""Name → description (`"a cell variable"`, `"a parameter"`, …) of the declared quantities of
the model being expanded whose prime is not bound (everything but site/field variables)."""
function _prime_targets(parts::_Parts, body::Expr)
    scopes = Dict{Symbol, Any}()                 # declared variable → its scope
    for ex in body.args
        _is_section(ex) && ex.args[1] === Symbol("@variables") || continue
        for l in _lines(filter(a -> !(a isa LineNumberNode), ex.args[3:end]))
            decl = l isa Expr && l.head === :(=) ? l.args[1] : l
            decl isa Expr && decl.head === :ref && (decl = decl.args[1])
            decl isa Expr && decl.head === :call && length(decl.args) == 2 && (scopes[decl.args[1]] = decl.args[2])
        end
    end
    out = Dict{Symbol, String}()
    for (x, what) in parts.declared
        haskey(parts.declared, Symbol(x, '′')) && continue
        sc = get(scopes, x, nothing)
        out[x] = sc isa Symbol ? (sc in SCOPES ? _scope_description(sc, nothing) : _scope_description(:edge, sc)) :
                 _with_article(what)
    end
    return out
end
_with_article(what) = (first(what) in "aeiou" ? "an " : "a ") * what
_scope_description(role, rel) = role === :edge ? (rel === nothing ? "an edge variable" : "an edge variable of `$rel`") :
                                "a $role variable"

"""What `x` is in one of `bases` (for `_prime_error`), or `nothing`."""
function _base_description(bases, x::Symbol)
    named(i) = i !== nothing && (i.name === x || get(i.options, :vector, nothing) === x)
    for b in bases
        for v in b.variables
            i = info(v)
            named(i) || continue
            i.role in (:site, :field) && return nothing
            return _scope_description(i.role, get(i.options, :relationship, nothing))
        end
        any(p -> named(info(p)), b.parameters) && return "a parameter"
        x in b.kinds && return "a kind"
        any(o -> named(info(o.var)), b.observed) && return "an observed quantity"
        haskey(b.relations, x) && return "a relation"
        any(r -> r.name === x, b.relationships) && return "a relationship"
    end
    return nothing
end

"""
Called by a `@potts_model` constructor that failed with `e`: if `e` is the `UndefVarError`
of `x′` for a quantity `x` that is not a site/field variable (declared in the model,
`targets`, or inherited from one of `bases`), throw the Potts error. Otherwise return, and
the caller rethrows `e`.
"""
function _prime_error(e, targets::Dict{Symbol, String}, bases)
    e isa UndefVarError || return nothing
    n = e.var
    s = String(n)
    endswith(s, '′') || return nothing
    x = Symbol(chop(s))
    what = get(targets, x, nothing)
    what === nothing && (what = _base_description(bases, x))
    what === nothing && return nothing
    hint = what == "a cell variable" ? "; in a contact term, `$x[owner′]` reads it for the cell on the other side" : ""
    throw(ArgumentError("`$n`: primes exist only for site/field variables (`y′` is the value of a site or " *
                        "field variable `y` at the other site of a contact pair), and `$x` is $what$hint"))
end

# `if cond … else … end` around sections (conditions on structural parameters): the
# sections of the taken branch are added when the model is constructed. Declarations stay
# unconditional (the constructor's keywords are fixed when the macro expands).
const _UNCONDITIONAL = (Symbol("@structural_parameters"), Symbol("@kinds"), Symbol("@parameters"),
    Symbol("@variables"), Symbol("@extend"))
_is_section(st) = st isa Expr && st.head === :macrocall && st.args[1] in SECTIONS
_conditional_sections(ex) = ex isa Expr && ex.head in (:if, :elseif) &&
                            any(b -> b isa Expr && (b.head === :block ? any(_is_section, b.args) : _conditional_sections(b)), ex.args[2:end])
function _conditional!(parts::_Parts, ex)
    branch(b) = b isa Expr && b.head in (:if, :elseif) ? _conditional!(parts, b) : begin
        sub = _Parts(parts.structural, parts.params, Any[], parts.mod, parts.declared)
        for st in (b isa Expr && b.head === :block ? b.args : Any[b])
            if st isa LineNumberNode
                push!(sub.code, st)
            elseif _is_section(st)
                st.args[1] in _UNCONDITIONAL &&
                    throw(ArgumentError("$(st.args[1]) cannot be conditional; declare it unconditionally"))
                _section!(sub, st.args[1], filter(a -> !(a isa LineNumberNode), st.args[3:end]), st.args[2])
            else
                push!(sub.code, rewrite(st))
            end
        end
        Expr(:block, sub.code...)
    end
    return Expr(ex.head, ex.args[1], map(branch, ex.args[2:end])...)
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
            _declare!(parts, l.args[1], "structural parameter")
            push!(parts.structural, (l.args[1], l.args[2]))
        end
    elseif sec === Symbol("@kinds")
        names = Symbol[]
        for l in _lines(args)
            if l isa Expr && l.head === :ref && l.args[2:end] == [:frozen]
                isempty(names) && throw(ArgumentError("the medium (the first kind) cannot be frozen"))
                push!(code, :(push!(__frozen, $(length(names)))))    # `wall[frozen]`: an obstacle kind
                l = l.args[1]
            end
            l isa Symbol || throw(ArgumentError("@kinds lists kind names (optionally `name[frozen]`); the first is the medium"))
            push!(names, l)
        end
        for (i, k) in enumerate(names)
            _declare!(parts, k, "kind")
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
                _declare!(parts, k, "parameter")
                push!(parts.params, k)
                push!(code, :($k = $P.vector_parameter($(QuoteNode(k)), $(lhs.args[2]), $(_kw_local(k)) === nothing ? $val : $(_kw_local(k)); $(kw...))),
                    :(append!(__params, $k.components)))
                continue
            elseif lhs isa Expr && lhs.head === :ref
                k = lhs.args[1]
                _declare!(parts, k, "parameter")
                push!(parts.params, k)
                push!(code, :($k = $P.kind_parameter($(QuoteNode(k)), $(_kw_local(k)) === nothing ? $(rewrite(val)) : $(_kw_local(k)); $(kw...))))
            else
                k = lhs::Symbol
                _declare!(parts, k, "parameter")
                push!(parts.params, k)
                push!(code, :($k = $P.parameter($(QuoteNode(k)), $(_kw_local(k)) === nothing ? $(rewrite(val)) : $(_kw_local(k)); $(kw...))))
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
                throw(ArgumentError("variables are declared with a scope: `x(site)`, `x(cell)`, `x(model)`, `c(field)`, " *
                                    "`e(edge)` or `e(rel)` for an edge variable of `@relationship rel`"))
            k, scope = decl.args
            _declare!(parts, k, "variable")
            # `= default, [options…]`; a tuple without an options vector is the default itself
            default, opts = rhs isa Expr && rhs.head === :tuple && length(rhs.args) == 2 && rhs.args[2] isa Expr &&
                            rhs.args[2].head === :vect ? (rhs.args[1], rhs.args[2]) : (rhs, nothing)
            kw = opts === nothing ? Any[] : [Expr(:kw, o.args[1], o.args[2]) for o in opts.args]
            default === nothing || push!(kw, Expr(:kw, :default, default))
            if range === nothing
                push!(code, :($k = $P.variable(only($P.Symbolics.@variables $k(t)), $(QuoteNode(scope)); $(kw...))),
                    :(push!(__vars, $k)))
            else
                push!(code, :($k = $P.vector_variable($(QuoteNode(k)), $range, $(QuoteNode(scope)); $(kw...))),
                    :(append!(__vars, $k.components)))
            end
            if scope in (:site, :field)                  # `x′`: the value at s′ of a contact pair
                k′ = _declare!(parts, Symbol(k, '′'), "variable (the contact-pair value of `$k`)")
                push!(code, :($k′ = $P._primed($k)))
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
        # an extension without its own @lattice uses the base's dimension (vector builtins, A-38)
        # `_nested(F, args...; kws...)`: the arguments are evaluated before the base is entered
        nested = Expr(:call, :($P._nested), params, call.args[1], filter(x -> x !== params, call.args[2:end])...)
        push!(code, :($bname = $nested), :(push!(__bases, $bname)),
            :($P._build().dim == 0 && $P._set_dim!(length($bname.lattice.dims))))
        foreach(n -> push!(code, :($n = $P.lookup($bname, $(QuoteNode(n))))), names)
        # a bound site or field variable `x` brings its contact-pair value `x′` along
        for n in names
            n′ = Symbol(n, '′')
            n′ in names && continue
            push!(code, :($P._is_site_quantity($bname, $(QuoteNode(n))) && ($n′ = $P.lookup($bname, $(QuoteNode(n′))))))
        end
    elseif sec === Symbol("@components")
        # `@components clock = sys`, `@components cells(k) grn = sys`, or a block of `name = sys`
        domain = length(args) == 2 ? args[1] : :($P.cells)
        domain = domain === :model ? QuoteNode(:model) : :($P._domain($domain))   # `@components model drug = sys`
        for l in _lines(args[end:end])
            l isa Expr && l.head === :(=) && l.args[1] isa Symbol ||
                throw(ArgumentError("@components lines are `name = system`"))
            k = l.args[1]
            _declare!(parts, k, "component")
            # `clock = clock`: the right-hand side means the caller's global, not the new local
            rhs = _globalize(l.args[2], k, parts.mod)
            # renamed, so `k.x` is `k₊x` whatever the system was called
            push!(code, :($k = $P.Symbolics.rename($rhs, $(QuoteNode(k)))),
                :(push!(__components, $P.ComponentSpec($(QuoteNode(k)), $k, $domain))))
        end
    elseif sec === Symbol("@lattice")
        push!(code, :(__lattice = $(_replace_call(only(args), :Lattice, :($P.lattice_spec)))),
            :($P._set_dim!(length(__lattice.dims))))
    elseif sec === Symbol("@relations")
        for l in _lines(args)
            k = l.args[1]
            k === :contact || _declare!(parts, k, "relation")
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
            _declare!(parts, k, "observed quantity")
            push!(code, :($k = $P.observed_var($(QuoteNode(k)))),
                _located_push(:__observed, :($P.ObservedEq($k, $(rewrite(l.args[3])))), ln))
        end
    elseif sec === Symbol("@relationship")
        decl = args[1]
        decl isa Expr && decl.head === :call || throw(ArgumentError("@relationship name(cell, cell) capacity = k"))
        k = decl.args[1]
        _declare!(parts, k, "relationship")
        opts, _ = _options(args[2:end])
        kw = [Expr(:kw, o, v) for (o, v) in opts if o !== :distance]
        push!(code, :(push!(__relationships, $P.relationship($(QuoteNode(k)); $(kw...)))),
            :($k = $P.RelationshipRef($(QuoteNode(k)))))
    elseif sec in (Symbol("@link"), Symbol("@unlink"))
        action = QuoteNode(sec === Symbol("@link") ? :link : :unlink)
        opts, rest = _options(args[2:end])      # `rest`: a cadence `Every(n)`, checked by link_rule
        kw = [Expr(:kw, o, rewrite(v)) for (o, v) in opts]
        push!(code, _edge_scope(_located_push(:__links, :($P.link_rule($action, $(args[1]), $(map(rewrite, rest)...); $(kw...))), ln)))
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

# Edge-scoped statements see the link endpoints `a`, `b` (bound only there). No
# declaration can be named `a`/`b` (`_ENDPOINT_NAMES`), so nothing is shadowed.
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
→ `ifelse`, `div(a, b)`/`a ÷ b` → `_intdiv`, and `fold(body for n in R(s) if cond)` → a relation gather.
"""
function rewrite(ex)
    ex isa Expr || return ex
    P = :(Potts)
    h = ex.head
    if h === :ref
        # `v[end]`, `v[begin + 1]`: ordinary Julia indexing (`end` only means something in a ref)
        _has_endbegin(ex.args[2:end]) && return Expr(:ref, rewrite(ex.args[1]), ex.args[2:end]...)
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
    elseif h === :call && (ex.args[1] === :div || ex.args[1] === :÷) && length(ex.args) == 3
        return Expr(:call, :($P._intdiv), rewrite(ex.args[2]), rewrite(ex.args[3]))
    elseif h === :call && length(ex.args) == 2 && ex.args[2] isa Expr && ex.args[2].head === :generator
        return _rewrite_gather(ex.args[1], ex.args[2])
    elseif h === :quote || h === :macrocall && ex.args[1] === Symbol("@variables")
        return ex
    end
    return Expr(h, map(rewrite, ex.args)...)
end
_isblock(e) = e isa Expr && e.head === :block

# `div`/`÷` defined in a model body (`div(a, b) = …`, `function ÷(a, b) … end`, `div = f`):
# the name it defines, or `nothing`. `rewrite` turns their calls into `_intdiv`.
function _div_definition(ex)
    ex isa Expr || return nothing
    if ex.head in (:(=), :function) && !isempty(ex.args)
        f = ex.args[1]
        while f isa Expr && f.head in (:where, :(::))
            f = f.args[1]
        end
        f isa Expr && f.head === :call && (f = f.args[1])
        f in (:div, :÷) && return f
    end
    for a in ex.args
        # `(div = 1,)` names a field, not a function
        ex.head === :tuple && a isa Expr && a.head === :(=) && (a = a.args[2])
        d = _div_definition(a)
        d === nothing || return d
    end
    return nothing
end
_has_endbegin(x) = x === :end || x === :begin || (x isa Expr && any(_has_endbegin, x.args)) ||
                   (x isa AbstractVector && any(_has_endbegin, x))

function _rewrite_gather(fold, gen)
    P = :(Potts)
    body = gen.args[1]
    plain = Expr(:call, fold, Expr(:generator, map(rewrite, gen.args)...))
    # several iterators (`for i in 1:2, j in 1:3`): ordinary Julia (A-40)
    length(gen.args) > 2 && return plain
    spec = gen.args[2]
    cond = nothing
    if spec isa Expr && spec.head === :filter
        length(spec.args) > 2 && return plain
        cond, spec = spec.args[1], spec.args[2]
    end
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
