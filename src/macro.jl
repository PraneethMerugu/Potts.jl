# `@potts_model Name begin … end`: sugar for a constructor `Name(; name, structural…,
# parameters…)` that builds a `PottsSystem` (as `@mtkmodel` builds an MTK system).
#
# Expressions are evaluated as ordinary Julia at construction time with the built-in names
# bound to symbols, after a syntactic rewrite (`rewrite`) that makes indexing,
# `&&`/`||`/`!`, ternaries and generator folds over relations symbolic.

const SECTIONS = (
    Symbol("@structural_parameters"), Symbol("@kinds"), Symbol("@parameters"),
    Symbol("@variables"), Symbol("@lattice"), Symbol("@relations"), Symbol("@energy"),
    Symbol("@drive"), Symbol("@constraint"), Symbol("@on_copy"), Symbol("@after_mcs"),
    Symbol("@before_mcs"), Symbol("@equations"), Symbol("@divide"), Symbol("@sweep"),
    Symbol("@relationship"), Symbol("@link"), Symbol("@unlink"), Symbol("@observed"),
    Symbol("@extend"), Symbol("@components"), Symbol("@schedule"),
    Symbol("@initialization_equations"), Symbol("@convert"), Symbol("@fields"),
    Symbol("@description"), Symbol("@metadata"),
)

"""
    @potts_model Name begin
        sections...
    end

Define a model constructor `Name(; name, kwargs...)` that builds a [`PottsSystem`](@ref).

The body is a sequence of sections (`@kinds`, `@parameters`, `@lattice`, `@energy`,
`@sweep` and the others). `@named m = Name()` passes `name`. Keyword arguments of the
constructor override structural parameters and parameter defaults. The section reference
is `docs/design/AUTHORING.md` and the manual.

# Arguments
- `Name`: the name of the constructor function.
- `body`: a `begin … end` block of sections.

# Returns
- The constructor function `Name`.

# Examples
```julia
@potts_model Sorting begin
    @structural_parameters begin
        dims = (72, 72)
    end
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = 16      # every entry not listed below
        J[medium, medium] = 0
        J[dark, dark] = 2
        J[dark, light] = 11     # also J[light, dark]: the table is symmetric
        J[light, light] = 14
    end
    @lattice Lattice(dims; boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = T)
end

@named sorting = Sorting(; T = 20.0)
```

See also [`PottsSystem`](@ref), [`CompiledPottsSystem`](@ref).
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
    # names bound by `@extend a, b = base = Base()` (kind class members)
    bound::Set{Symbol}
    kinds::Vector{Symbol}        # the kinds of `@kinds`, in order (for messages)
    extends::Base.RefValue{Bool}   # the model has an `@extend` (for messages)
end
function _Parts(structural, params, code, mod, declared)
    return _Parts(
        structural, params, code, mod, declared, Set{Symbol}(), Symbol[], Ref(false)
    )
end

# The names `@extend n₁, n₂ = base = Base()` binds before the first `@kinds` (the
# constructor runs the sections in order, so only those are bound when the classes are
# built).
function _extend_bound_names(body::Expr)
    out = Set{Symbol}()
    for ex in body.args
        ex isa Expr && ex.head === :macrocall || continue
        ex.args[1] === Symbol("@kinds") && break
        ex.args[1] === Symbol("@extend") || continue
        es = filter(a -> !(a isa LineNumberNode), ex.args[3:end])
        # malformed: the `@extend` section reports it
        length(es) == 1 || continue
        e = es[1]
        e isa Expr && e.head === :(=) && e.args[2] isa Expr && e.args[2].head === :(=) ||
            continue
        lhs = e.args[1]
        if lhs isa Symbol
            push!(out, lhs)
        else
            foreach(a -> a isa Symbol && push!(out, a), lhs.args)
        end
    end
    return out
end

# The hidden local holding parameter `k`'s constructor keyword. `@extend λ = base = Base()`
# rebinds the local `λ` to the base's symbol, so a redeclaration `@parameters λ = …` reads
# the keyword here (D-114). `#` keeps the name out of reach of user code.
_kw_local(k::Symbol) = Symbol("##kw#", k)

# Names the constructor binds itself: a declaration of one would be silently rebound.
const _BOUND_BUILTINS = (
    :volume, :surface, :kind, :neighbor_kind, :owner, :neighbor_owner, :id, :generation,
    :weight,
    :source, :target, :old, :new, :mcs, :position, :distance,
    :cluster, :cluster_volume, :cluster_surface,
    :time, :site, :major_length, :local_components, :ring_arcs,
    :ring_cells, :ring_medium, :direction, :euler,
    :largest_piece, :birth, :pivot, :angle, :curvature,
)
# Primed spellings of `neighbor_kind` and `neighbor_owner`, bound as aliases in model bodies
const _PRIMED_ALIASES = (
    Symbol("kind′") => :neighbor_kind, Symbol("owner′") => :neighbor_owner,
)
# `euler_full`, `pieces_full`, `largest_piece_full` are the columns of the `adjacency =
# :full` forms: reserved, not bound
function _reserved_names()
    return Set{Symbol}(
        [
            _BOUND_BUILTINS..., first.(_PRIMED_ALIASES)..., keys(DSL)..., :t,
            :D, :Pre, :name, :euler_full, :pieces_full,
            :largest_piece_full,
        ]
    )
end
# DSL names added after published models used them as structural parameters
# (`WortelAct(; connected)`): a structural parameter may take one of these names, and then
# it shadows the DSL name in its model (which cannot use that helper)
const _SHADOWABLE_DSL_NAMES = (
    :connected, :shell, :pieces, :distinct, :Local, :ArcOrPair, :Simple,
)
# The link endpoints `a`, `b` are reserved globally (D-075 Q8): no declaration (kind,
# parameter, variable, observed quantity, relation, relationship, component) may take their
# name, so nothing an edge term or link rule reads is shadowed (`_check_reserved_names`
# applies the same rule to a programmatic `PottsSystem`).
"""Record a declared name; reject built-in names and a second declaration of a name."""
function _declare!(parts::_Parts, k::Symbol, what::String)
    k in _reserved_names() &&
        !(what == "structural parameter" && k in _SHADOWABLE_DSL_NAMES) && throw(
        ArgumentError(
            "$what `$k` has the name of a built-in (`$k` means something else in \
                @potts_model); choose another name"
        )
    )
    k in _ENDPOINT_NAMES && throw(ArgumentError(_endpoint_message(what, k)))
    # `#…` names are the constructor's hidden locals (`_kw_local`)
    startswith(string(k), '#') &&
        throw(ArgumentError("$what `$k`: a name cannot start with `#`; choose another \
            name"))
    haskey(parts.declared, k) &&
        throw(ArgumentError("$what `$k`: `$k` is already declared \
            as $(_with_article(parts.declared[k]))"))
    parts.declared[k] = what
    return k
end

# the DSL names bound in a model body: all but those its structural parameters shadow
_dsl_bound(parts) = [k for k in keys(DSL) if !any(p -> first(p) === k, parts.structural)]
function _field_bound(parts)
    return [k for k in keys(FIELD_NAMES) if !any(p -> first(p) === k, parts.structural)]
end

# The model body binds the lattice coordinates `x`, `y`, `z`, which hide a
# global of the model's module with that name. When the module defines one, the body reads
# the name where no local binding of it is in scope and the model does not declare it, warn
# once at expansion, naming the binding and how to keep the global (before, the coordinate
# replaced it silently)
function _warn_coordinate_globals(name, body, parts)
    for s in (:x, :y, :z)
        isdefined(parts.mod, s) && !haskey(parts.declared, s) && !(s in parts.bound) &&
            !any(p -> first(p) === s, parts.structural) || continue
        _reads_free(body, s) && !_binds_top(body, s) || continue
        @warn string(
            "@potts_model ", name, ": `", s,
            "` in the model body is the lattice coordinate (bound in model ",
            "bodies for the fields' bindings); the global `", parts.mod, ".", s,
            "` is not read there. To use the global's ",
            "value, declare it, `@parameters ", s, " = …` (the model's own `", s,
            "` hides the coordinate), or rename ",
            "the global"
        ) _module = parts.mod
    end
    return nothing
end
# The names of a field's PDESystem (LatticePDE's operators and `masked`, MTK's
# `Differential` and `Shift`) are not names of the model body: a field is a PDESystem
# written with `using Potts.Fields` and coupled with `@fields`. A body that reads one the
# calling module does not define meets this error at expansion (a module that defines one
# reads its own, as Julia does)
const _FIELD_BODY_NAMES = (
    :laplacian, :Δ, :DivKGrad, :Advect, :Upwind1, :masked, :Differential, :Shift,
)
function _check_field_body_names(name, body, parts)
    for s in _FIELD_BODY_NAMES
        (
            isdefined(parts.mod, s) || haskey(parts.declared, s) || s in parts.bound ||
                any(p -> first(p) === s, parts.structural)
        ) &&
            continue
        _reads_free(body, s) && !_binds_top(body, s) || continue
        throw(
            ArgumentError(
                string(
                    "@potts_model ", name, ": `", s,
                    "` is not defined in the model body; a field and its ",
                    "operators (`laplacian`, `DivKGrad`, `Advect`, `masked`, \
                        `Differential`, …) are written as a PDESystem with ",
                    "`using Potts.Fields` and coupled into the model with `@fields c = \
                        pdesys (input => expression)`"
                )
            )
        )
    end
    return nothing
end
# The legacy section macros are not sections of a model body: a
# field's conditions are the second argument of its PDESystem. A body that uses one meets
# this error at expansion, with the route (a module that defines the macro uses its own)
const _OLD_BCS_TEXT = string(
    "a field's conditions are the second argument of its PDESystem (`using \
        Potts.Fields`): ",
    "`PDESystem(eqs, [c(t, 0, y) ~ v, Differential(x)(c(t, L, y)) ~ 0, c ~ masked(wall(t, \
        x, y), 0.0)], domain, ivs, ",
    "dvs, ps)` with `wall(..)::Bool [input = true]` among the dependent variables, \
        coupled into the model with ",
    "`@fields c = pdesys (wall => kind == border)`"
)
const _OLD_BOUNDARY_TEXT = string(
    "a face condition is an equation in the second argument of the field's PDESystem ",
    "(`using Potts.Fields`), coupled into the model with `@fields c = pdesys`. On the low \
        face of `x`: Dirichlet ",
    "`c(t, 0, y) ~ v`; NoFlux `Differential(x)(c(t, 0, y)) ~ 0` (a closed axis without a \
        condition has no flux); Robin ",
    "`α * c(t, 0, y) - β * Differential(x)(c(t, 0, y)) ~ g` (α c + β ∂c/∂n = g, n the \
        outward normal). On the high ",
    "face `x = L` the outward normal is `+x`: `c(t, L, y) ~ v`, `Differential(x)(c(t, L, \
        y)) ~ 0`, ",
    "`α * c(t, L, y) + β * Differential(x)(c(t, L, y)) ~ g`"
)
function _check_old_condition_sections(name, body, mod)
    for (s, text) in (
            (Symbol("@bcs"), _OLD_BCS_TEXT), (
                Symbol("@boundary"), _OLD_BOUNDARY_TEXT,
            ),
        )
        isdefined(mod, s) && continue
        _uses_macro(body, s) || continue
        throw(
            ArgumentError(
                string(
                    "@potts_model ", name, ": `", s, "` is not a section of a model body; ",
                    text
                )
            )
        )
    end
    return nothing
end
function _uses_macro(ex, s)
    return ex isa Expr &&
        (
        (ex.head === :macrocall && ex.args[1] === s) ||
            any(a -> _uses_macro(a, s), ex.args)
    )
end
# Whether `ex` reads `s` outside every scope that binds `s` itself (a
# helper `g(x) = 2x` binds `x` in its own body only, so a binding `src => g(1.0) * x` still
# reads the coordinate). Scopes: a function definition (its arguments, keywords included),
# an anonymous function, `let`, a `for` loop and a generator or comprehension. A keyword
# name (`h(x = 0.5)`) is not a read.
function _reads_free(ex, s)
    ex === s && return true
    ex isa Expr || return false
    h = ex.head
    h === :kw && return _reads_free(ex.args[2], s)
    if _is_fundef(ex)
        sig = ex.args[1]
        s in _sig_binders(sig) && return false
        return any(a -> _reads_free(a, s), _sig_defaults(sig)) || _reads_free(ex.args[2], s)
    end
    if h === :->
        s in _sig_binders(ex.args[1]) && return false
        return _reads_free(ex.args[2], s)
    end
    if h === :let || h === :for
        binds = ex.args[1]
        bs = binds isa Expr && binds.head === :block ? binds.args : Any[binds]
        any(b -> _assigns(b, s), bs) && return false
        return any(a -> _reads_free(a, s), ex.args)
    end
    if h === :generator
        any(b -> _assigns(b, s), _gen_binders(ex)) && return false
    end
    return any(a -> _reads_free(a, s), ex.args)
end
function _is_fundef(ex)
    return ex isa Expr && (ex.head === :function || ex.head === :(=)) &&
        length(ex.args) == 2 &&
        _sig_call(ex.args[1]) !== nothing
end
function _sig_call(sig)
    sig isa Expr || return nothing
    sig.head === :call && return sig
    sig.head in (:where, :(::)) && return _sig_call(sig.args[1])
    return nothing
end
# the names a signature binds: positional and keyword arguments, `x::T`, `x = v`, `x...`,
# tuples
function _sig_binders(sig)
    c = _sig_call(sig)
    args = if c === nothing
        sig isa Expr && sig.head === :tuple ? sig.args : Any[sig]
    else
        c.args[2:end]
    end
    out = Symbol[]
    foreach(a -> _arg_names!(out, a), args)
    return out
end
function _arg_names!(out, a)
    a isa Symbol && return push!(out, a)
    a isa Expr || return out
    a.head in (:kw, :(=), :(::), :..., :meta) && return _arg_names!(out, a.args[1])
    a.head in (:parameters, :tuple) && foreach(b -> _arg_names!(out, b), a.args)
    return out
end
# the default values in a signature (they are read where the function is defined)
function _sig_defaults(sig)
    c = _sig_call(sig)
    c === nothing && return Any[]
    out = Any[]
    function walk(a)
        a isa Expr || return
        if a.head === :kw
            push!(out, a.args[2])
        elseif a.head === :parameters
            foreach(walk, a.args)
        end
        return
    end
    foreach(walk, c.args[2:end])
    return out
end
function _gen_binders(ex)
    return Any[
        a.head === :filter ? a.args[2:end] : a for a in ex.args[2:end]
            if a isa Expr
    ] |>
        v -> reduce(vcat, (b isa Vector ? b : Any[b] for b in v); init = Any[])
end
function _assigns(b, s)
    return b isa Expr && b.head === :(=) &&
        (b.args[1] === s || s in _sig_binders(b.args[1]))
end
# whether a top-level statement of the body assigns `s` (`x = 2.0` or `x, y = …`): it hides
# the coordinate in the whole body
function _binds_top(body, s)
    return any(
        ex -> ex isa Expr && ex.head === :(=) && !_is_fundef(ex) && _assigns(ex, s),
        body.args
    )
end

function _potts_model(name::Symbol, body::Expr, mod)
    body.head === :block ||
        throw(ArgumentError("@potts_model $name expects a begin … end block"))
    d = _div_definition(body)
    d === nothing || throw(
        ArgumentError(
            "@potts_model $name defines `$d`: inside a model `div(a, b)` and `a ÷ b` " *
                "are integer division; give the helper another name"
        )
    )
    _check_old_condition_sections(name, body, mod)
    parts = _Parts(Any[], Symbol[], Any[], mod, Dict{Symbol, String}())
    union!(parts.bound, _extend_bound_names(body))
    parts.extends[] = any(
        ex -> ex isa Expr && ex.head === :macrocall && ex.args[1] === Symbol("@extend"),
        body.args
    )
    for ex in body.args
        ex isa LineNumberNode && (push!(parts.code, ex); continue)
        if ex isa Expr && ex.head === :macrocall && ex.args[1] in SECTIONS
            _section!(
                parts, ex.args[1],
                filter(a -> !(a isa LineNumberNode), ex.args[3:end]), ex.args[2]
            )
        elseif _conditional_sections(ex)
            push!(parts.code, _conditional!(parts, ex))
        else
            push!(parts.code, rewrite(ex))        # helper functions, local definitions
        end
    end
    _warn_coordinate_globals(name, body, parts)
    _check_field_body_names(name, body, parts)
    _check_fields_placement(body)
    # required, as in MTK (`@named m = Model()`)
    kws = Any[:name]
    for (k, v) in parts.structural
        k in parts.params &&
            throw(ArgumentError("`$k` is both a structural parameter and a parameter"))
        push!(kws, Expr(:kw, k, v))
    end
    for k in parts.params
        push!(kws, Expr(:kw, k, :nothing))        # `Model(; λ = 2.0)` overrides the default
    end
    # the parameters of `@fields` PDESystems are keywords too (`Model(; Dc = 1.0)`); their
    # names are known only when the constructor runs
    _has_section(body, Symbol("@fields")) && push!(kws, Expr(:..., :__fields_kw))
    P = :(Potts)
    # `@schedule` state only in models that use it (anywhere, conditionals included): a
    # model without it builds exactly as before (first-construction latency)
    sched = _has_section(body, Symbol("@schedule"))
    # likewise `@initialization_equations` (D-170)
    inits = _has_section(body, Symbol("@initialization_equations"))
    # likewise `@convert` (R8, D-233)
    convs = _has_section(body, Symbol("@convert"))
    # likewise `@fields` (a plain PDESystem's fields; its conditions are stored, printed and
    # classified by the field compiler)
    coupled = _has_section(body, Symbol("@fields"))
    # likewise `@description` and `@metadata` (MTK's `@mtkmodel` sections: the inner
    # System's)
    described = _has_section(body, Symbol("@description")) ||
        _has_section(body, Symbol("@metadata"))
    preamble = quote
        # each parameter keyword, kept before `@extend` may rebind its name (D-114)
        $([:($(_kw_local(k)) = $k) for k in parts.params]...)
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, _BOUND_BUILTINS...)), :($P.B)))
        # the primed spellings of the contact-pair built-ins (aliases inside the DSL only)
        $([:($a = $b) for (a, b) in _PRIMED_ALIASES]...)
        # gather variables and draws are numbered per build (`_in_build`); a base built by
        # `@extend` inside another model continues the outer numbering (no collisions)
        $P._set_dim!(0)                           # set by @lattice (vector builtins)
        t = $P.t
        D = $P._D
        Pre = $P._pre
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, _dsl_bound(parts)...)), :($P.DSL)))
        # the field equations' names: the lattice coordinates and `masked`
        $(
            Expr(
                :(=), Expr(:tuple, Expr(:parameters, _field_bound(parts)...)),
                :($P.FIELD_NAMES)
            )
        )
        __kinds = Symbol[]
        # a model without `@kinds` takes its base's kinds at `@extend` (its kind tables
        # read them)
        __own_kinds = $(_has_section(body, Symbol("@kinds")))
        __frozen = Int[]
        __classes = $P.KindClass[]
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
        __observed = $P.Equation[]
        __lattice = nothing
        __sweep = nothing
        $(sched ? :(__schedule = Any[]) : nothing)
        $(inits ? :(__init_eqs = $P.Equation[]) : nothing)
        $(convs ? :(__converts = $P.ConvertSpec[]) : nothing)
        $(described ? :(__description = nothing; __metadata = Pair{Any, Any}[]) : nothing)
        $(
            coupled ? :(
                    __bcs = $P.Equation[];
                    __field_inputs = Any[];
                    __bcs_origins = Pair{Any, Symbol}[];
                    __coupled = Symbol[];
                    __field_values = Dict{Symbol, Any}(pairs(__fields_kw));
                    __fields_brought = Dict{Symbol, String}()
                ) : nothing
        )
        __bases = $P.PottsSystem[]
        __sources = IdDict{Any, LineNumberNode}()
        __components = Any[]
        # set when an `@extend` base's constructor throws
        __base_failed = $(Ref{Bool})(false)
        # contact folds and bounded draws built (D-150)
        __features = $P._feature_counts()
    end
    structural = Expr(
        :tuple, Expr(
            :parameters, [
                Expr(:kw, k, k)
                    for (k, _) in parts.structural
            ]...
        )
    )
    extends = parts.extends[]
    finish = :(
        $P.PottsSystem(;
            name, kinds = __kinds, lattice = __lattice, parameters = __params,
            variables = $P._bind_edge_scope(__vars, __relationships, __bases),
            relations = __relations, energies = __energies, drives = __drives,
            constraints = __constraints, updates = __updates, equations = __equations,
            divisions = __divisions, relationships = __relationships, link_rules = __links,
            observed = __observed, frozen_kinds = __frozen, kind_classes = __classes,
            sources = __sources, components = __components,
            sweep = __sweep, $((sched ? (Expr(:kw, :schedule, :__schedule),) : ())...),
            $((inits ? (Expr(:kw, :initialization_eqs, :__init_eqs),) : ())...),
            $((convs ? (Expr(:kw, :converts, :__converts),) : ())...),
            $((coupled ? (Expr(:kw, :bcs, :__bcs),) : ())...),
            structural = $structural, metadata = $(
                coupled ?
                    :(
                        $P._with_field_inputs(
                            $P._built_metadata(__features), __field_inputs,
                            __bcs_origins, __coupled
                        )
                    ) :
                    :($P._built_metadata(__features))
            )
        )
    )
    targets = :(
        Dict{Symbol, String}(
            $(
                [
                    :($(QuoteNode(k)) => $v)
                        for (k, v) in _prime_targets(parts, body)
                ]...
            )
        )
    )
    return quote
        Base.@__doc__ function $name(; $(kws...))
            $P._in_build() do
                $preamble
                try
                    $(parts.code...)
                catch __e
                    # an error from inside a base propagates as the base raised it (D-133)
                    __base_failed[] || $P._prime_error(__e, $targets, __bases)
                    rethrow()
                end
                $(
                    extends ?
                        :(
                            # an extension inherits what it does not declare
                            for b in __bases
                                __lattice === nothing && (__lattice = $P._p(b, :lattice))
                                __sweep === nothing && (__sweep = $P._p(b, :sweep))
                                isempty(__kinds) && append!(__kinds, $P._p(b, :kinds))
                        end
                        ) : nothing
                )
                __lattice === nothing &&
                    throw(ArgumentError($("model $name has no @lattice; declare `@lattice \
                        Lattice(dims)` in the model body")))
                __sweep === nothing &&
                    throw(ArgumentError($("model $name has no @sweep; declare `@sweep \
                        Metropolis(; temperature = …)` in the model body")))
                $(
                    coupled ? :(
                            $P._fields_keywords_left(name, __field_values);
                            $P._check_fields_names(__params, __vars, __fields_brought)
                        ) : nothing
                )
                __built = $(
                    extends ?
                        :(
                            foldl(
                                (s, b) -> $P.ModelingToolkitBase.extend(s, b; name),
                                __bases; init = $finish
                            )
                        ) : finish
                )
                $(
                    described ? :($P._describe(__built, __description, __metadata)) :
                        :__built
                )
            end
        end
    end
end

# `@fields` at expansion: its bindings read kind names, so it comes after `@kinds`; a name
# it binds (`@fields c = pdesys`) is a local of the constructor from its line on, so a
# statement before that line that reads it would meet an unassigned local (an UndefVarError)
const _DECLARING = (
    Symbol("@structural_parameters"), Symbol("@kinds"), Symbol("@parameters"),
    Symbol("@variables"),
    Symbol("@extend"), Symbol("@relations"), Symbol("@observed"),
    Symbol("@components"), Symbol("@relationship"),
    Symbol("@fields"), Symbol("@lattice"),
)
function _check_fields_placement(body::Expr)
    args = body.args
    for (i, ex) in enumerate(args)
        _is_section(ex) && ex.args[1] === Symbol("@fields") || continue
        any(e -> _is_section(e) && e.args[1] === Symbol("@kinds"), args[(i + 1):end]) &&
            throw(
            ArgumentError(
                "@fields: write `@fields` after `@kinds` (its bindings read the kind \
                    names, `kind == A`)"
            )
        )
        a = filter(x -> !(x isa LineNumberNode), ex.args[3:end])
        isempty(a) && continue
        lhs = a[1] isa Expr && a[1].head === :(=) ? a[1].args[1] : nothing
        names = if lhs isa Symbol
            Any[lhs]
        elseif lhs isa Expr && lhs.head === :tuple
            lhs.args
        else
            Any[]
        end
        for n in names, e in args[1:(i - 1)]
            n isa Symbol && !(_is_section(e) && e.args[1] in _DECLARING) &&
                _reads_free(e, n) || continue
            throw(
                ArgumentError(
                    "`$n` is read on a line before `@fields $n = …`, which binds it on a " *
                        "later line; move the `@fields` line above the first use of `$n`"
                )
            )
        end
    end
    return nothing
end

# `x′` is bound only for a site or field variable `x` (the value at the other site of a
# contact pair; `@variables` declares it alongside `x`). Any other `x′` the section code
# reads is unbound, so the constructor fails with an `UndefVarError`; the constructor
# catches it and, when `x` is a declared or inherited quantity that is not a site/field
# variable, rethrows it as a Potts error (`_prime_error`). A local named `x′` (a `let`,
# generator or closure variable) never raises, so it stays valid Julia; the happy path pays
# nothing.
"""Name → description (`"a cell variable"`, `"a parameter"`, …) of the declared quantities
of the model being expanded whose prime is not bound (everything but site/field
variables)."""
function _prime_targets(parts::_Parts, body::Expr)
    scopes = Dict{Symbol, Any}()                 # declared variable → its scope
    for ex in body.args
        _is_section(ex) && ex.args[1] === Symbol("@variables") || continue
        for l in _lines(filter(a -> !(a isa LineNumberNode), ex.args[3:end]))
            decl = l isa Expr && l.head === :(=) ? l.args[1] : l
            decl isa Expr && decl.head === :tuple && length(decl.args) == 2 &&
                (decl = decl.args[1])   # `x(cell), [guess = g]`
            decl isa Expr && decl.head === :(::) && length(decl.args) == 2 &&
                (decl = decl.args[1])   # `x(cell)::CellRef`
            decl isa Expr && decl.head === :ref && (decl = decl.args[1])
            decl isa Expr && decl.head === :call && length(decl.args) == 2 &&
                (scopes[decl.args[1]] = decl.args[2])
        end
    end
    out = Dict{Symbol, String}()
    for (x, what) in parts.declared
        haskey(parts.declared, Symbol(x, '′')) && continue
        sc = get(scopes, x, nothing)
        out[x] = if sc isa Symbol
            sc in SCOPES ? _scope_description(sc, nothing) : _scope_description(:edge, sc)
        else
            _with_article(what)
        end
    end
    return out
end
_with_article(what) = (first(what) in "aeiou" ? "an " : "a ") * what
function _scope_description(role, rel)
    if role === :edge
        return rel === nothing ? "an edge variable" : "an edge variable of `$rel`"
    else
        return "a $role variable"
    end
end

"""
`F(args...; kws...)` for an `@extend` base `F` whose constructor raising sets `failed[]`:
the extending constructor then rethrows the error unchanged instead of translating it as one
of its own `x′` (each constructor call has its own flag, so nested or concurrent builds
never share it). The flag is set only on the error path, which leaves the extending
constructor.
"""
# Accepted trade-off: a closure the extension passes to a hand-written base runs inside the
# base's constructor, so an `x′` error raised in it is reported as the base's (the raw
# `UndefVarError`), not translated.
struct _BaseCall{F, R <: Ref{Bool}}
    f::F
    failed::R
end
function (c::_BaseCall)(args...; kws...)
    ok = false
    try
        r = c.f(args...; kws...)
        ok = true
        return r
    finally
        ok || (c.failed[] = true)
    end
end

"""What `x` is in one of `bases` (for `_prime_error`), or `nothing`."""
function _base_description(bases, x::Symbol)
    named(i) = i !== nothing && (i.name === x || get(i.options, :vector, nothing) === x)
    for b in bases
        for v in _p(b, :variables)
            i = info(v)
            named(i) || continue
            i.role in (:site, :field) && return nothing
            return _scope_description(i.role, get(i.options, :relationship, nothing))
        end
        any(p -> named(info(p)), _p(b, :parameters)) && return "a parameter"
        x in _p(b, :kinds) && return "a kind"
        any(o -> named(info(o.lhs)), _p(b, :observed)) && return "an observed quantity"
        haskey(_p(b, :relations), x) && return "a relation"
        any(r -> r.name === x, _p(b, :relationships)) && return "a relationship"
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
    hint = if what == "a cell variable"
        "; in a contact term, `$x[neighbor_owner]` reads it for the cell on the other side"
    else
        ""
    end
    throw(
        ArgumentError(
            "`$n`: primes exist only for site/field variables (`y′` is the value of a " *
                "site or field variable `y` at the other site of a contact pair), and `$x` \
                    is $what$hint"
        )
    )
end

# `if cond … else … end` around sections (conditions on structural parameters): the
# sections of the taken branch are added when the model is constructed. Declarations stay
# unconditional (the constructor's keywords are fixed when the macro expands).
const _UNCONDITIONAL = (
    Symbol("@structural_parameters"), Symbol("@kinds"), Symbol("@parameters"),
    Symbol("@variables"), Symbol("@extend"),
)
function _has_section(ex, sec)
    return ex isa Expr && (
        (ex.head === :macrocall && ex.args[1] === sec) ||
            any(a -> _has_section(a, sec), ex.args)
    )
end
_is_section(st) = st isa Expr && st.head === :macrocall && st.args[1] in SECTIONS
function _conditional_sections(ex)
    return ex isa Expr && ex.head in (:if, :elseif) && any(
        b -> b isa Expr && (
            if b.head === :block
                any(_is_section, b.args)
            else
                _conditional_sections(b)
            end
        ),
        ex.args[2:end]
    )
end
function _conditional!(parts::_Parts, ex)
    function branch(b)
        if b isa Expr && b.head in (:if, :elseif)
            return _conditional!(parts, b)
        else
            return begin
                sub = _Parts(
                    parts.structural, parts.params, Any[], parts.mod, parts.declared,
                    parts.bound, parts.kinds, parts.extends
                )
                for st in (b isa Expr && b.head === :block ? b.args : Any[b])
                    if st isa LineNumberNode
                        push!(sub.code, st)
                    elseif _is_section(st)
                        st.args[1] in _UNCONDITIONAL &&
                            throw(ArgumentError("$(st.args[1]) cannot be conditional; \
                                declare it unconditionally"))
                        _section!(
                            sub, st.args[1],
                            filter(a -> !(a isa LineNumberNode), st.args[3:end]),
                            st.args[2]
                        )
                    else
                        push!(sub.code, rewrite(st))
                    end
                end
                Expr(:block, sub.code...)
            end
        end
    end
    return Expr(ex.head, ex.args[1], map(branch, ex.args[2:end])...)
end

function _lines(args)
    if length(args) == 1 && args[1] isa Expr && args[1].head === :block
        return filter(a -> !(a isa LineNumberNode), args[1].args)
    else
        return args
    end
end
# lines with their source locations (a block's own line numbers, else the section's)
function _lines_ln(args, ln)
    length(args) == 1 && args[1] isa Expr && args[1].head === :block ||
        return [(a, ln) for a in args]
    out = Tuple{Any, Any}[]
    for a in args[1].args
        a isa LineNumberNode ? (ln = a) : push!(out, (a, ln))
    end
    return out
end
# `push!(list, x)` recording where `x` was written (diagnostics)
_located_push(list, x, ln) = :(Potts._push_located!($list, __sources, $x, $(QuoteNode(ln))))
_push_located!(list, sources, x, ln) = push!(list, _source!(sources, x, ln))
function _push_located!(list, sources, xs::AbstractVector, ln)
    return foreach(x -> _push_located!(list, sources, x, ln), xs)
end
# `lhs ~ rhs` → `Potts._eq(lhs, rhs)` (component-wise for vector quantities)
function _rewrite_eq(l)
    if l isa Expr && l.head === :call && l.args[1] === :~ && length(l.args) == 3
        return :(Potts._eq($(rewrite(l.args[2])), $(rewrite(l.args[3]))))
    else
        return rewrite(l)
    end
end
_is_range(ex) = ex isa Expr && ex.head === :call && ex.args[1] === :(:)
# `@equations` lines are MTK equations (D-257 item 5, V3-3): a kind set is the positional
# term `ismember(kind, g)`. `∈` has an MTK meaning of its own (a domain pairing; `∈ Set(…)`
# is `false` before any term exists, deleting the term), so it is refused here, while the
# line is still syntax, with the form to write.
function _no_membership_sugar(ex, what = "@equations", which = "an equation")
    ex isa Expr || return nothing
    if ex.head === :call && ex.args[1] in (:∈, :∉, :in) && length(ex.args) == 3
        a, g = ex.args[2], ex.args[3]
        # `Set([a, b])` and `[a, b]` are written as the tuple `(a, b)`
        g isa Expr && g.head === :call && g.args[1] === :Set && length(g.args) == 2 &&
            (g = g.args[2])
        g isa Expr && g.head === :vect && (g = Expr(:tuple, g.args...))
        form = ex.args[1] === :∉ ? "!ismember($a, $g)" : "ismember($a, $g)"
        throw(
            ArgumentError(
                "$what: `$ex` tests membership with `$(ex.args[1])`; $which writes a " *
                    "kind set as `$form`"
            )
        )
    end
    foreach(a -> _no_membership_sugar(a, what, which), ex.args)
    return nothing
end
# `kind == X` in an `@fields` binding, `X` a name: its value is checked against the model's
# kinds when the model is built (`kind == cells` reads the function `cells`, and is `false`)
function _checked_kind_names(ex)
    ex isa Expr || return ex
    if ex.head === :call && ex.args[1] in (:(==), :(!=)) && length(ex.args) == 3
        a, b = ex.args[2], ex.args[3]
        a === :kind && b isa Symbol &&
            return Expr(
            :call, ex.args[1], a,
            :(Potts._binding_kind(() -> $b, $(QuoteNode(b)), __kinds))
        )
        b === :kind && a isa Symbol &&
            return Expr(
            :call, ex.args[1],
            :(Potts._binding_kind(() -> $a, $(QuoteNode(a)), __kinds)), b
        )
    end
    return Expr(ex.head, map(_checked_kind_names, ex.args)...)
end

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
    plain = Set(
        string(l.args[2])
            for (l, _) in order if l isa Expr && l.head === :call && l.args[1] === :~
    )
    out = Tuple{Any, Any}[]
    for (item, ln) in order
        if item isa String
            ls = groups[item]
            item in plain &&
                throw(ArgumentError("`$item` has both `~` and compound (`+=`, …) writes \
                    in one block"))
            ops = Set(l.head for l in ls)
            ops ⊆ Set((:+=, :-=)) || ops ⊆ Set((:*=, :/=)) ||
                throw(ArgumentError("`$item`: additive and multiplicative compound writes \
                    do not combine; write one equation"))
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
function _strip(ex)
    return if ex isa Expr && ex.head === :block
        only(filter(a -> !(a isa LineNumberNode), ex.args))
    else
        ex
    end
end

function _section!(parts, sec, args, ln = nothing)
    P = :(Potts)
    code = parts.code
    if sec === Symbol("@structural_parameters")
        for l in _lines(args)
            l isa Expr && l.head === :(=) ||
                throw(ArgumentError("structural parameters are `name = default`"))
            _declare!(parts, l.args[1], "structural parameter")
            push!(parts.structural, (l.args[1], l.args[2]))
        end
    elseif sec === Symbol("@kinds")
        names = Symbol[]
        classes = Any[]
        for l in _lines(args)
            # `endothelial = (tip, stalk)`: a kind class
            if l isa Expr && l.head === :(=)
                g, m = l.args[1], _strip(l.args[2])
                g isa Symbol ||
                    throw(ArgumentError("@kinds: a kind class is `name = (kind, …)`"))
                members = m isa Expr && m.head === :tuple ? m.args : Any[m]
                all(x -> x isa Symbol, members) ||
                    throw(ArgumentError("@kinds: kind class `$g` lists kind or class \
                        names, `$g = (kind, …)`"))
                push!(classes, (g, members))
                continue
            end
            if l isa Expr && l.head === :ref && l.args[2:end] == [:frozen]
                isempty(names) &&
                    throw(ArgumentError("the medium (the first kind) cannot be frozen"))
                # `wall[frozen]`: an obstacle kind
                push!(code, :(push!(__frozen, $(length(names)))))
                l = l.args[1]
            end
            l isa Symbol ||
                throw(ArgumentError("@kinds lists kind names (optionally `name[frozen]`); \
                    the first is the medium"))
            push!(names, l)
        end
        for (i, k) in enumerate(names)
            _declare!(parts, k, "kind")
            push!(parts.kinds, k)
            push!(code, :($k = $(i - 1)), :(push!(__kinds, $(QuoteNode(k)))))
        end
        for (g, members) in classes
            # members resolve at expansion (D-135): a kind (of any @kinds), an earlier
            # class, or a name bound by `@extend`; anything else (a misspelling, a later
            # class, a global) is rejected here, naming it
            for m in members
                get(parts.declared, m, "") in ("kind", "kind class") || m in parts.bound ||
                    throw(
                    ArgumentError(
                        "kind class `$g`: `$m` is not a kind or an earlier kind class" *
                            (m === g ? " (a class cannot contain itself)" : "")
                    )
                )
            end
            _declare!(parts, g, "kind class")
            push!(
                code,
                :(
                    $g = $P._kind_class(
                        $(QuoteNode(g)), $(Tuple(members)),
                        ($(members...),)
                    )
                ),
                :(push!(__classes, $g))
            )
        end
    elseif sec === Symbol("@parameters")
        lines = map(_parameter_line, _lines(args))
        # kind tables: a declaration `J[kind, kind] = …` and entry lines `J[k₁, k₂] = v`,
        # gathered by table and built at the table's last line (one `_kind_table` call)
        tables = _kind_table_lines(parts, lines)
        for (n, (lhs, val, kw)) in enumerate(lines)
            # `d[1:n]`: a vector
            if lhs isa Expr && lhs.head === :ref && _is_range(lhs.args[2])
                k = lhs.args[1]
                _no_symmetric_option(k, kw)
                _declare!(parts, k, "parameter")
                push!(parts.params, k)
                push!(
                    code, :(
                        $k = $P.vector_parameter(
                            $(QuoteNode(k)), $(lhs.args[2]),
                            $(_kw_local(k)) === nothing ? $val : $(_kw_local(k)); $(kw...)
                        )
                    ),
                    :(append!(__params, $k.components))
                )
                continue
            elseif lhs isa Expr && lhs.head === :ref
                k = lhs.args[1]
                t = tables[k]
                n == t.last[] || continue
                _declare!(parts, k, "parameter")
                push!(parts.params, k)
                push!(code, _kind_table_code(parts, k, t))
            else
                k = lhs::Symbol
                _no_symmetric_option(k, kw)
                _declare!(parts, k, "parameter")
                push!(parts.params, k)
                push!(
                    code,
                    :(
                        $k = $P.parameter(
                            $(QuoteNode(k)),
                            $(_kw_local(k)) === nothing ? $(rewrite(val)) : $(_kw_local(k));
                            $(kw...)
                        )
                    )
                )
            end
            push!(code, :(push!(__params, $k)))
        end
    elseif sec === Symbol("@variables")
        for l in _lines(args)
            decl, rhs = if l isa Expr && l.head === :(=)
                (l.args[1], _strip(l.args[2]))
            else
                (l, nothing)
            end
            # `x(cell), [guess = g]`: options without a value (MTK's metadata syntax)
            if rhs === nothing && decl isa Expr && decl.head === :tuple &&
                    length(decl.args) == 2 &&
                    decl.args[2] isa Expr && decl.args[2].head === :vect
                decl, rhs = decl.args[1], Expr(:tuple, nothing, decl.args[2])
            end
            range = nothing
            type = nothing
            # `x(cell)::CellRef` (R6)
            if decl isa Expr && decl.head === :(::) && length(decl.args) == 2
                decl, type = decl.args
            end
            # `p(cell)[1:n]`: a vector
            if decl isa Expr && decl.head === :ref
                range = decl.args[2]
                decl = decl.args[1]
            end
            decl isa Expr && decl.head === :call && length(decl.args) == 2 || throw(
                ArgumentError(
                    "variables are declared with a scope: `x(site)`, `x(cell)`, " *
                        "`x(model)`, `e(edge)` or `e(rel)` for an edge variable of " *
                        "`@relationship rel`; a field is a dependent variable of a " *
                        "PDESystem, `@variables c(..) = 0.5 [bounds = (0, 1)]`, coupled \
                            into the model with `@fields`"
                )
            )
            k, scope = decl.args
            _declare!(parts, k, "variable")
            # `= default, [options…]`; a tuple without an options vector is the default
            # itself
            default, opts = if rhs isa Expr && rhs.head === :tuple &&
                    length(rhs.args) == 2 && rhs.args[2] isa Expr &&
                    rhs.args[2].head === :vect
                (rhs.args[1], rhs.args[2])
            else
                (rhs, nothing)
            end
            kw = if opts === nothing
                Any[]
            else
                [Expr(:kw, o.args[1], o.args[2]) for o in opts.args]
            end
            default === nothing || push!(kw, Expr(:kw, :default, default))
            if type !== nothing
                range === nothing ||
                    throw(ArgumentError("variable `$k`: a typed variable (`::$type`) is a \
                        scalar, not a vector"))
                push!(kw, Expr(:kw, :type, type))
            end
            if range === nothing
                push!(
                    code, :(
                        $k = $P.variable(
                            only($P.Symbolics.@variables $k(t)),
                            $(QuoteNode(scope)); $(kw...)
                        )
                    ),
                    :(push!(__vars, $k))
                )
            else
                push!(
                    code, :(
                        $k = $P.vector_variable(
                            $(QuoteNode(k)), $range,
                            $(QuoteNode(scope)); $(kw...)
                        )
                    ),
                    :(append!(__vars, $k.components))
                )
            end
            # `x′`: the value at s′ of a contact pair
            if scope in (:site, :field)
                k′ = _declare!(
                    parts, Symbol(k, '′'),
                    "variable (the contact-pair value of `$k`)"
                )
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
        rhs isa Expr && rhs.head === :call ||
            throw(ArgumentError("@extend expects a model call, e.g. `@extend λ = base = \
                Sorting()`"))
        call = copy(rhs)
        any(a -> a isa Expr && a.head === :parameters, call.args) ||
            insert!(call.args, 2, Expr(:parameters))
        params = call.args[findfirst(a -> a isa Expr && a.head === :parameters, call.args)]
        any(a -> a isa Expr && a.head === :kw && a.args[1] === :name, params.args) ||
            push!(params.args, Expr(:kw, :name, QuoteNode(bname)))
        # an extension without its own @lattice uses the base's dimension (vector builtins,
        # A-38) `_nested(F, args...; kws...)`: the arguments are evaluated before the base
        # is entered (the extension's own code); only an error the base's constructor raises
        # is marked `__base_failed`, so the extension does not relabel it (`_BaseCall`,
        # D-133)
        nested = Expr(
            :call, :($P._nested), params, :($P._BaseCall($(call.args[1]), __base_failed)),
            filter(x -> x !== params, call.args[2:end])...
        )
        push!(
            code, :($bname = $nested), :(push!(__bases, $bname)),
            :(__own_kinds || isempty(__kinds) && append!(__kinds, $P._p($bname, :kinds))),
            :($P._build().dim == 0 && $P._set_dim!(length($P._p($bname, :lattice).dims)))
        )
        foreach(n -> push!(code, :($n = $P.lookup($bname, $(QuoteNode(n))))), names)
        # a bound site or field variable `x` brings its contact-pair value `x′` along
        for n in names
            n′ = Symbol(n, '′')
            n′ in names && continue
            push!(
                code,
                :(
                    $P._is_site_quantity($bname, $(QuoteNode(n))) &&
                        ($n′ = $P.lookup($bname, $(QuoteNode(n′))))
                )
            )
        end
    elseif sec === Symbol("@components")
        # `@components clock = sys`, `@components cells(k) grn = sys`, or a block of `name =
        # sys`
        domain = length(args) == 2 ? args[1] : :($P.cells)
        # `@components model drug = sys`
        domain = domain === :model ? QuoteNode(:model) : :($P._domain($domain))
        for l in _lines(args[end:end])
            l isa Expr && l.head === :(=) && l.args[1] isa Symbol ||
                throw(ArgumentError("@components lines are `name = system`"))
            k = l.args[1]
            _declare!(parts, k, "component")
            # `clock = clock`: the right-hand side means the caller's global, not the new
            # local
            rhs = _globalize(l.args[2], k, parts.mod)
            # renamed, so `k.x` is `k₊x` whatever the system was called
            push!(
                code, :($k = $P.Symbolics.rename($rhs, $(QuoteNode(k)))),
                :(push!(__components, $P.ComponentSpec($(QuoteNode(k)), $k, $domain)))
            )
        end
    elseif sec === Symbol("@lattice")
        push!(
            code, :(__lattice = $(_replace_call(only(args), :Lattice, :($P.lattice_spec)))),
            :($P._set_dim!(length(__lattice.dims)))
        )
    elseif sec === Symbol("@relations")
        for l in _lines(args)
            k = l.args[1]
            k === :contact || _declare!(parts, k, "relation")
            push!(
                code, :(__relations[$(QuoteNode(k))] = $(l.args[2])),
                :($k = $P.RelationRef($(QuoteNode(k))))
            )
        end
    elseif sec === Symbol("@energy")
        for (l, lln) in _lines_ln(args, ln)
            e = _located_push(:__energies, :($P.energy($(rewrite(l)))), lln)
            push!(
                code, _is_edges(l) ? _edge_scope(e) : _is_angles(l) ? _angle_scope(e) : e
            )
        end
    elseif sec === Symbol("@observed")
        for l in _lines(args)
            (l isa Expr && l.head === :call && l.args[1] === :~) ||
                throw(ArgumentError("@observed lines are `name ~ expr`"))
            lhs = l.args[2]
            # `name(scope)` or `name`
            k = lhs isa Expr && lhs.head === :call ? lhs.args[1] : lhs
            k isa Symbol || throw(ArgumentError("@observed: `$lhs` is not a name"))
            _declare!(parts, k, "observed quantity")
            push!(
                code, :($k = $P.observed_var($(QuoteNode(k)))),
                _located_push(
                    :__observed,
                    :($P._observed_eq($k, $(_rewrite_arg(l.args[3])))), ln
                )
            )
        end
    elseif sec === Symbol("@relationship")
        decl = args[1]
        decl isa Expr && decl.head === :call ||
            throw(ArgumentError("@relationship name(cell, cell) capacity = k"))
        k = decl.args[1]
        _declare!(parts, k, "relationship")
        opts, _ = _options(args[2:end])
        kw = [Expr(:kw, o, v) for (o, v) in opts if o !== :distance]
        push!(
            code, :(push!(__relationships, $P.relationship($(QuoteNode(k)); $(kw...)))),
            :($k = $P.RelationshipRef($(QuoteNode(k))))
        )
    elseif sec in (Symbol("@link"), Symbol("@unlink"))
        action = QuoteNode(sec === Symbol("@link") ? :link : :unlink)
        # `rest`: a cadence `Every(n)`, checked by link_rule
        opts, rest = _options(args[2:end])
        kw = [Expr(:kw, o, rewrite(v)) for (o, v) in opts]
        push!(
            code,
            _edge_scope(
                _located_push(
                    :__links,
                    :(
                        $P.link_rule(
                            $action, $(args[1]), $(map(rewrite, rest)...);
                            $(kw...)
                        )
                    ),
                    ln
                )
            )
        )
    elseif sec === Symbol("@drive")
        foreach(
            ((l, lln),) -> push!(
                code,
                _located_push(:__drives, :($P.drive($(rewrite(_replace_copy(l))))), lln)
            ),
            _lines_ln(args, ln)
        )
    elseif sec === Symbol("@constraint")
        foreach(
            ((l, lln),) ->
            push!(
                code,
                _located_push(:__constraints, :($P.constraint($(rewrite(l)))), lln)
            ),
            _lines_ln(args, ln)
        )
    elseif sec in (Symbol("@on_copy"), Symbol("@after_mcs"), Symbol("@before_mcs"))
        phase = QuoteNode(Symbol(String(sec)[2:end]))
        every = length(args) == 2 ? args[1] : nothing
        for (l, lln) in _combine_compound(_lines_ln(args[end:end], ln))
            l = _rewrite_eq(l)
            # `a`, `b` are bound for edge updates (D-169); in any other update
            # `_check_names` rejects them, as it does every name outside the update's scope
            update = if every === nothing
                :($P.update($phase, $l))
            else
                :($P.update($phase, $every, $l))
            end
            push!(code, _edge_scope(_located_push(:__updates, update, lln)))
        end
    elseif sec === Symbol("@equations")
        # cell and model equations; a field's equation is refused when the line is built
        # (`_no_field_line`: whether its left side is a field is known then)
        foreach(
            ((l, lln),) -> (
                _no_membership_sugar(l);
                push!(
                    code,
                    _located_push(
                        :__equations,
                        :($P._no_field_line($(_rewrite_eq(l)), $(string(l)))), lln
                    )
                )
            ),
            _lines_ln(args, ln)
        )
    elseif sec === Symbol("@initialization_equations")
        foreach(
            ((l, lln),) -> push!(code, _located_push(:__init_eqs, _rewrite_eq(l), lln)),
            _lines_ln(args, ln)
        )
    elseif sec === Symbol("@fields")
        # `@fields c, u = pdesys (endo => kind == A, vol => volume[owner])`: the
        # PDESystem's fields, parameters, equations and conditions join the model here,
        # under their own names (as `Potts.couple`), each binding an input of it to a CPM
        # expression; the names before `=` are bound to those fields (or parameters) for the
        # statements after this line. The names and the bindings are optional.
        usage = "@fields takes optional field names, a PDESystem and its input bindings: " *
            "`@fields c = pdesys (inner => kind == A, vol => volume[owner])`"
        (length(args) in (1, 2) && !(args[1] isa Expr && args[1].head === :tuple)) ||
            throw(ArgumentError(usage))
        sysex, names = args[1], Symbol[]
        if sysex isa Expr && sysex.head === :(=)
            lhs, sysex = sysex.args[1], sysex.args[2]
            ls = lhs isa Expr && lhs.head === :tuple ? lhs.args : Any[lhs]
            all(n -> n isa Symbol, ls) || throw(
                ArgumentError(
                    "@fields: the names before `=` are names of the PDESystem's fields " *
                        "or parameters, `@fields c, u = pdesys (…)`; got `$lhs`"
                )
            )
            for n in ls
                n in names &&
                    throw(ArgumentError("@fields: the field `$n` is listed twice"))
                push!(names, n)
            end
        end
        sysex isa Expr && sysex.head === :(=) && throw(ArgumentError(usage))
        bs = if length(args) == 1
            Any[]
        elseif args[2] isa Expr && args[2].head === :tuple
            args[2].args
        else
            Any[args[2]]
        end
        pairs = map(bs) do b
            b isa Expr && b.head === :call && b.args[1] === :(=>) && length(b.args) == 3 ||
                throw(
                ArgumentError(
                    "@fields $(sysex): `$b` is not a binding; write `input => \
                        expression`, e.g. `inner => kind == A`"
                )
            )
            # a binding tests a kind set with `ismember`: `kind ∈ (a, b)` is an interval and
            # `kind ∈ Set(…)` the constant `false`
            _no_membership_sugar(b.args[3], "@fields $(sysex)", "a binding")
            # a bare-symbol key is an input's name first, its local value second
            k = b.args[2]
            :(
                $(k isa Symbol ? :($P._NamedKey($(QuoteNode(k)), () -> $k)) : k) =>
                    $(rewrite(_checked_kind_names(b.args[3])))
            )
        end
        foreach(n -> _declare!(parts, n, "field"), names)
        # a bound name is a local of the constructor: inside this line it still means the
        # global
        glob(ex) = foldl((e, n) -> _globalize(e, n, parts.mod), names; init = ex)
        fs = gensym(:fields_sys)
        fc = gensym(:fields_content)
        push!(
            code, :($fs = $(glob(sysex))),
            :(
                $fc = $P._fields_content(
                    name, __lattice, __kinds, __bases, __params,
                    __vars, $fs, Any[$(map(glob, pairs)...)],
                    __field_values
                )
            ),
            :(
                foreach(
                    x -> __fields_brought[$P.info(x).name] = string(
                        "the PDESystem `",
                        nameof($fs), "`"
                    ),
                    [$fc.parameters; $fc.variables]
                )
            ),
            :(append!(__vars, $fc.variables)), :(append!(__params, $fc.parameters)),
            :(append!(__equations, $fc.equations)), :(append!(__bcs, $fc.bcs)), :(
                append!(
                    __field_inputs, $fc.inputs
                )
            ),
            :(append!(__coupled, $P._coupled_names($fc.variables))),
            :(
                foreach(
                    b -> push!(__bcs_origins, b => nameof($fs)), [
                        $fc.bcs;
                        $fc.equations
                    ]
                )
            ),
            [:($n = $P._fields_name($fc, $(QuoteNode(n)), $fs)) for n in names]...
        )
    elseif sec === Symbol("@divide")
        domain = args[1]
        opts, rules = _options(args[2:end])
        kw = [Expr(:kw, k, rewrite(v)) for (k, v) in opts]
        push!(
            code,
            _located_push(
                :__divisions,
                :($P.divide($domain, $(map(rewrite, rules)...); $(kw...))), ln
            )
        )
    elseif sec === Symbol("@schedule")
        # `@schedule fields, sweep`: the phases of one MCS in order (D-145), checked here
        names = if length(args) == 1 && args[1] isa Expr && args[1].head === :tuple
            args[1].args
        else
            args
        end
        listed = Any[]
        for n in names
            if n isa Expr && n.head === :call && n.args[1] === :repeat
                push!(listed, schedule_repeat(n))
            else
                n isa Symbol || throw(
                    ArgumentError(
                        "@schedule lists phase names, e.g. `@schedule fields, sweep`, " *
                            "and at most one `repeat(n, sweep(fraction = 1//n), …)`; got \
                                `$n`"
                    )
                )
                push!(listed, n)
            end
        end
        isempty(listed) && throw(ArgumentError("@schedule lists at least one phase"))
        # the canonical phases are checked here; a name that is none of them may be a
        # `@convert` pass (this model's or a base's), checked when the model is compiled
        if all(n -> n in SCHEDULE_PHASES, _schedule_flat(listed))
            _placed_schedule(listed)
        else
            _schedule_names(listed)
        end
        items = map(
            x -> if x isa Symbol
                QuoteNode(x)
            else
                :($P.ScheduleRepeat($(x.n), Symbol[$(map(QuoteNode, x.names)...)]))
            end,
            listed
        )
        push!(
            code, :(
                isempty(__schedule) ||
                    throw(ArgumentError("@schedule is given twice; list the phases once"))
            ),
            :(append!(__schedule, Any[$(items...)]))
        )
    elseif sec === Symbol("@convert")
        push!(code, _convert_section(args, ln))
    elseif sec === Symbol("@description")
        length(args) == 1 ||
            throw(ArgumentError("@description takes one string: `@description \"what the \
                model is\"`"))
        push!(code, :(__description = $(args[1])))
    elseif sec === Symbol("@metadata")
        for l in _lines(args)
            l isa Expr && l.head === :(=) || throw(
                ArgumentError("@metadata entries are `Key = value`, with `Key` a type, as \
                    in MTK's `@mtkmodel`")
            )
            push!(code, :(push!(__metadata, $(l.args[1]) => $(l.args[2]))))
        end
    elseif sec === Symbol("@sweep")
        ex = only(args)
        ex = _replace_call(ex, :Metropolis, :($P.sweep_spec), QuoteNode(:metropolis))
        ex = _replace_call(ex, :Barker, :($P.sweep_spec), QuoteNode(:barker))
        push!(code, :(__sweep = $(rewrite(ex))))
    end
    return parts
end

# `@convert name domain begin … end` (R8, D-233): the block's keys `from`, `to`, `at`, `p`,
# its `transfer(…)` calls and compound writes, evaluated with `from` and `to` bound to the
# pass's cells (`created` is a DSL name)
function _convert_section(args, ln)
    P = :(Potts)
    (
        length(args) == 3 && args[1] isa Symbol && args[3] isa Expr &&
            args[3].head === :block
    ) || throw(
        ArgumentError(
            "@convert takes a name, a domain and a block: `@convert protrusion \
                clusters(cytoplasm) begin to = sibling(k); p = … end`"
        )
    )
    name, domain, blk = args
    kws = Any[]
    seen = Set{Symbol}()
    transfers = Any[]
    writes = Any[]
    for (l, _) in _lines_ln(Any[blk], ln)
        if l isa Expr && l.head === :(=) && l.args[1] in (:from, :to, :at, :p)
            k = l.args[1]
            k in seen && throw(ArgumentError("@convert $name: `$k` is given twice"))
            push!(seen, k)
            push!(kws, Expr(:kw, k, rewrite(_strip(l.args[2]))))
        elseif l isa Expr && l.head === :call && l.args[1] === :transfer
            push!(transfers, rewrite(l))
        elseif l isa Expr && l.head in (:+=, :-=)
            d = rewrite(l.args[2])
            push!(writes, :($(rewrite(l.args[1])) => $(l.head === :+= ? d : :(-($d)))))
        else
            throw(
                ArgumentError(
                    "@convert $name: `$l` is not a line of the block; write `from = …`, " *
                        "`to = …`, `at = …`, `p = …`, `transfer(x, from => to, per_site = \
                            …)` or a compound write `x[to] += …`"
                )
            )
        end
    end
    call = :(
        $P.convert_pass(
            $(QuoteNode(name)), $domain; $(kws...),
            transfers = Any[$(transfers...)], writes = Any[$(writes...)]
        )
    )
    return _located_push(
        :__converts, :(
            let from = $P.CONVERT_FROM, to = $P.CONVERT_TO
                $call
            end
        ), ln
    )
end

function _globalize(ex, k, mod)
    if ex === k
        return GlobalRef(mod, k)
    elseif ex isa Expr
        return Expr(ex.head, map(a -> _globalize(a, k, mod), ex.args)...)
    else
        return ex
    end
end

# Replace a call to `from(args…)` by `to([extra,] args…)` at the top of `ex`.
function _replace_call(ex, from, to, extra...)
    ex isa Expr && ex.head === :call && ex.args[1] === from || return ex
    params = filter(a -> a isa Expr && a.head === :parameters, ex.args[2:end])
    rest = filter(a -> !(a isa Expr && a.head === :parameters), ex.args[2:end])
    return Expr(:call, to, params..., extra..., rest...)
end

# Edge-scoped statements see the link endpoints `a`, `b` (bound only there). No
# declaration can be named `a`/`b` (`_ENDPOINT_NAMES`), so nothing is shadowed.
function _edge_scope(ex)
    return :(
        let a = Potts.B.a, b = Potts.B.b
            $ex
        end
    )
end

function _is_edges(l, domain = :edges)
    return l isa Expr && l.head === :call && l.args[1] === :(=>) &&
        l.args[2] isa Expr && l.args[2].head === :call && l.args[2].args[1] === domain
end

# Angle terms see the chain triple `a – pivot – b` and its `angle` and `curvature` (bound
# only there; reserved like `a`, `b`)
function _angle_scope(ex)
    return :(
        let a = Potts.B.a, b = Potts.B.b, pivot = Potts.B.pivot, angle = Potts.B.angle,
                curvature = Potts.B.curvature
            $ex
        end
    )
end
_is_angles(l) = _is_edges(l, :angles)

function _replace_copy(ex)
    if ex isa Expr && ex.head === :call && ex.args[1] === :(=>) && ex.args[2] === :copy
        return Expr(:call, :(=>), :(Potts.COPY), ex.args[3])
    else
        return ex
    end
end

# `when = a, along = b, x => 1` arrives as nested `=`/tuple chains; flatten to options +
# rules.
function _options(args)
    toks = Any[]
    # `k = v, rule` parses as `k = (v, rule)`; with no rule after a tuple value, `k = (1.0,
    # 0.0)` parses identically: the leading elements that are not rules/options form the
    # value
    isrule(x) = x isa Expr && (x.head === :(=) || (x.head === :call && x.args[1] === :(=>)))
    function flatvalue(v)
        v isa Expr && v.head === :tuple || return flatitems(v)
        i = something(findfirst(isrule, v.args), length(v.args) + 1)
        lead = v.args[1:(i - 1)]
        isempty(lead) || push!(toks, length(lead) == 1 ? lead[1] : Expr(:tuple, lead...))
        return foreach(
            x -> x isa Expr && x.head === :(=) ? flat(x) : push!(toks, x),
            v.args[i:end]
        )
    end
    function flat(e)
        if e isa Expr && e.head === :(=)
            return (flatitems(e.args[1]); push!(toks, :__EQ); flatvalue(e.args[2]))
        else
            return flatitems(e)
        end
    end
    function flatitems(e)
        if e isa Expr && e.head === :tuple
            return foreach(
                x -> x isa Expr && x.head === :(=) ? flat(x) : push!(toks, x),
                e.args
            )
        elseif e isa Expr && e.head === :(=)
            return flat(e)
        else
            return push!(toks, e)
        end
    end
    foreach(flat, args)
    opts = Pair{Symbol, Any}[]
    rules = Any[]
    i = 1
    while i <= length(toks)
        if i + 2 <= length(toks) && toks[i + 1] === :__EQ
            push!(opts, toks[i] => toks[i + 2])
            i += 3
        else
            push!(rules, toks[i])
            i += 1
        end
    end
    return opts, rules
end

# One line of `@parameters` as `(lhs, value, options)`: `λ = 1.0`, `λ = 1.0, [unit = u"…",
# tunable = false, bounds = (0, 2), description = "…"]` (MTK metadata), `J[kind, kind]`
# with `symmetric = false` among its options, and `x, [options]` without a value
function _parameter_line(l)
    lhs, val = if l isa Expr && l.head === :(=)
        (l.args[1], _strip(l.args[2]))
    elseif l isa Expr && l.head === :tuple && length(l.args) == 2 &&
            l.args[2] isa Expr && l.args[2].head === :vect
        (l.args[1], Expr(:tuple, nothing, l.args[2]))
    else
        (l, nothing)
    end
    val, opts = if val isa Expr && val.head === :tuple && length(val.args) == 2 &&
            val.args[2] isa Expr &&
            val.args[2].head === :vect
        (val.args[1], val.args[2])
    else
        (val, nothing)
    end
    name = lhs isa Expr && lhs.head === :ref ? lhs.args[1] : lhs
    all(
        o -> o isa Expr && o.head === :(=) && o.args[1] isa Symbol,
        opts === nothing ? () : opts.args
    ) || throw(
        ArgumentError(
            "@parameters $name: options are `[key = value, …]` with the keys `unit`, " *
                "`tunable`, `bounds`, `description` (and `symmetric` for a kind table)"
        )
    )
    kw = opts === nothing ? Any[] : Any[Expr(:kw, o.args[1], o.args[2]) for o in opts.args]
    for k in kw
        k.args[1] in (:unit, :tunable, :bounds, :description, :symmetric) || throw(
            ArgumentError(
                "@parameters $name: option `$(k.args[1])`; a parameter takes MTK's \
                    `unit`, `tunable`, `bounds` and `description`, and a kind table also \
                    `symmetric`"
            )
        )
    end
    return (lhs, val, kw)
end

function _no_symmetric_option(k, kw)
    any(o -> o.args[1] === :symmetric, kw) && throw(
        ArgumentError(
            "@parameters $k: `symmetric` is an option of a two-kind table, \
                `J[kind, kind] = …, [symmetric = false]`"
        )
    )
    return nothing
end

# A line `J[kind, kind] = …` declares a kind table; a line `J[dark, light] = v` (kind
# names) is one of its entries. The declaration is optional when every entry is listed.
# Each table: its kind axes, the declared value and options, its entries `(names, value)`
# and the index of its last line (where it is built).
function _kind_table_lines(parts, lines)
    tables = Dict{Symbol, Any}()
    for (n, (lhs, val, kw)) in enumerate(lines)
        lhs isa Expr && lhs.head === :ref && !_is_range(lhs.args[2]) || continue
        k = lhs.args[1]
        k isa Symbol || throw(ArgumentError("@parameters: `$lhs` is not a parameter name"))
        idx = lhs.args[2:end]
        decl = all(==(:kind), idx)
        text = string(lhs)
        length(idx) in (1, 2) || throw(
            ArgumentError(
                "@parameters `$text`: a kind table has one kind axis (`$k[kind]`) or two \
                    (`$k[kind, kind]`)"
            )
        )
        t = get!(
            () -> (;
                nd = length(idx), decl = Ref{Any}(nothing), declared = Ref(false),
                kw = Any[], entries = Any[], last = Ref(n),
            ), tables, k
        )
        length(idx) == t.nd || throw(
            ArgumentError(
                "@parameters `$text`: kind table `$k` has $(t.nd) kind \
                    $(t.nd == 1 ? "axis" : "axes"); write \
                    `$k[$(join(fill("…", t.nd), ", "))]`"
            )
        )
        t.last[] = n
        if decl
            t.declared[] && throw(
                ArgumentError(
                    "@parameters `$text`: kind table `$k` is declared twice; keep one \
                        declaration and give single entries as `$k[k₁, k₂] = v`"
                )
            )
            t.declared[] = true
            t.decl[] = val
            append!(t.kw, kw)
        else
            any(==(:kind), idx) && throw(
                ArgumentError(
                    "@parameters `$text`: write an entry with a kind name on every axis \
                        (`$k[dark, light] = v`), or declare the whole table with `kind` on \
                        every axis"
                )
            )
            val === nothing && throw(
                ArgumentError(
                    "@parameters `$text`: an entry needs a value, `$text = v`"
                )
            )
            isempty(kw) || throw(
                ArgumentError(
                    "@parameters `$text`: options go on the table's declaration, \
                        `$k[$(join(fill("kind", t.nd), ", "))] = …, [option = …]`"
                )
            )
            for m in idx
                _check_kind_name(parts, k, m, "`$text`")
            end
            push!(t.entries, (idx, val))
        end
    end
    for (k, t) in tables
        if any(o -> o.args[1] === :symmetric, t.kw)
            o = only(filter(o -> o.args[1] === :symmetric, t.kw))
            t.nd == 2 || throw(
                ArgumentError(
                    "@parameters $k[kind]: `symmetric` applies to a two-kind table \
                        `$k[kind, kind]`"
                )
            )
            o.args[2] isa Bool || throw(
                ArgumentError(
                    "@parameters $k[kind, kind]: `symmetric` is `true` or `false`; got \
                        `$(o.args[2])`"
                )
            )
        end
    end
    return tables
end

# the code that builds kind table `k`: `_kind_table` makes the array of every written form
# (a constructor keyword `Model(; J = …)` with a table or one number replaces the declared
# value and the entries; one with entries, `Model(; J = [(:dark, :light) => 1.0])`, sets
# them over the declared table), then `kind_parameter` the parameter
function _kind_table_code(parts, k, t)
    P = :(Potts)
    sym = findfirst(o -> o.args[1] === :symmetric, t.kw)
    symmetric = sym === nothing ? true : t.kw[sym].args[2]
    meta = [o for o in t.kw if o.args[1] !== :symmetric]
    sym === nothing || push!(meta, Expr(:kw, :symmetric, symmetric))
    value = t.decl[] === nothing ? :nothing : rewrite(t.decl[])
    entries = :(
        Pair{Any, Any}[
            $(
                [
                    :(($(names...),) => $(rewrite(v)))
                        for (names, v) in t.entries
                ]...
            ),
        ]
    )
    q, nd, s = QuoteNode(k), t.nd, symmetric
    return :(
        $k = $P.kind_parameter(
            $q,
            if $(_kw_local(k)) === nothing
                $P._kind_table($q, $nd, __kinds, $value, $entries; symmetric = $s)
            else
                $P._keyword_table(
                    $q, $nd, __kinds, $(_kw_local(k)), $value, $entries; symmetric = $s
                )
            end; $(meta...)
        )
    )
end

# A kind name `m` in an entry of kind table `k` (`where`, as written): a kind of `@kinds`
# (or one an `@extend` base binds, checked when built); a misspelling, a parameter, a kind
# class or another declared name is refused here, naming it
function _check_kind_name(parts, k, m, where)
    m isa Symbol || throw(
        ArgumentError(
            "kind table `$k`: `$m` in $where is not a kind name; name the kinds of \
                @kinds (the medium first), or declare the whole table with `kind` on \
                every axis, `$k[kind, kind] = …`"
        )
    )
    what = get(parts.declared, m, nothing)
    what == "kind" && return nothing
    what === nothing && m in parts.bound && return nothing
    known = isempty(parts.kinds) ? "" : "; the kinds are $(join(parts.kinds, ", "))"
    not_kind = if what === nothing && parts.extends[]
        "not a kind of @kinds or of the @extend line (a misspelling?)$known; to use a \
            kind of the base model, bind it in the @extend line, \
            `@extend $m, … = base = Base()`"
    elseif what === nothing && isempty(parts.kinds)
        "not a kind: no kinds are declared yet; declare @kinds before @parameters"
    elseif what === nothing
        "not a kind of @kinds (a misspelling?)$known"
    else
        "$(_with_article(what)), not a kind; an entry is indexed by kind names of @kinds"
    end
    throw(ArgumentError("kind table `$k`: `$m` in $where is " * not_kind))
end

# `integral(x; over = s)`: `s` is `cluster`; another name is refused here (it need not be
# bound)
function _check_integral_over(ex)
    for a in ex.args[2:end]
        kws = if a isa Expr && a.head === :parameters
            a.args
        elseif a isa Expr && a.head === :kw
            Any[a]
        else
            Any[]
        end
        for q in kws
            q isa Expr && q.head === :kw && q.args[1] === :over && q.args[2] isa Symbol &&
                q.args[2] !== :cluster && throw(
                ArgumentError(
                    "`integral(x; over = …)`: `over` is `cluster` (the alive members of " *
                        "the cell's compartment cluster); got `$(q.args[2])`"
                )
            )
        end
    end
    return nothing
end

"""
    rewrite(ex)

Make user syntax symbolic: `x[i…]` → `_index`, `&&`/`||`/`!` → symbolic logic, `c ? a : b`
→ `ifelse`, `div(a, b)`/`a ÷ b` → `_intdiv`, `euler(…)` → `_euler(…)`, and
`fold(body for n in R(s) if cond)` → a relation gather.
"""
function rewrite(ex)
    ex isa Expr || return ex
    P = :(Potts)
    h = ex.head
    h === :call && ex.args[1] === :integral && _check_integral_over(ex)
    if h === :ref
        # `v[end]`, `v[begin + 1]`: ordinary Julia indexing (`end` only means something in a
        # ref)
        _has_endbegin(ex.args[2:end]) &&
            return Expr(:ref, rewrite(ex.args[1]), ex.args[2:end]...)
        return Expr(:call, :($P._index), map(rewrite, ex.args)...)
    elseif h in (:(=), :+=, :-=, :*=, :/=) || (h === :function && length(ex.args) == 2)
        # assignment targets and function signatures are not expressions: leave them alone
        return Expr(h, ex.args[1], rewrite(ex.args[2]))
    elseif h === :&&
        return :($P._andq($(rewrite(ex.args[1])), () -> $(rewrite(ex.args[2]))))
    elseif h === :||
        return :($P._orq($(rewrite(ex.args[1])), () -> $(rewrite(ex.args[2]))))
    elseif h === :if && length(ex.args) == 3 && !_isblock(ex.args[2]) &&
            !_isblock(ex.args[3])
        # lazy on real conditions, `ifelse` on symbolic ones
        return :(
            $P._ifelseq(
                $(rewrite(ex.args[1])), () -> $(rewrite(ex.args[2])),
                () -> $(rewrite(ex.args[3]))
            )
        )
    elseif h === :call && ex.args[1] === :! && length(ex.args) == 2
        return Expr(:call, :($P._notq), rewrite(ex.args[2]))
    elseif h === :call && (ex.args[1] === :div || ex.args[1] === :÷) && length(ex.args) == 3
        return Expr(:call, :($P._intdiv), rewrite(ex.args[2]), rewrite(ex.args[3]))
    elseif h === :call && length(ex.args) == 2 && ex.args[2] isa Expr &&
            ex.args[2].head === :generator
        return _rewrite_gather(ex.args[1], ex.args[2])
    elseif h === :call && ex.args[1] === :euler
        # `euler(c; adjacency)`
        return Expr(:call, :($P._euler), map(rewrite, ex.args[2:end])...)
    elseif h === :call && ex.args[1] === :largest_piece
        # `largest_piece(c; adjacency)`
        return Expr(:call, :($P._largest_piece), map(rewrite, ex.args[2:end])...)
    elseif h === :call && length(ex.args) == 3 && _isparams(ex.args[2]) &&
            ex.args[3] isa Expr && ex.args[3].head === :generator
        # `pieces(n for n in … ; adjacency)`
        return _rewrite_gather(ex.args[1], ex.args[3], ex.args[2])
    elseif h === :call && ex.args[1] === :pieces && _relation_call(ex.args[end])
        # `pieces(c, R(s); …)`: `R(s)` is a relation at a site, checked by `pieces` (only
        # `shell`)
        r = ex.args[end]
        return Expr(
            :call, map(rewrite, ex.args[1:(end - 1)])...,
            :($P._around($(rewrite(r.args[1])), $(rewrite(r.args[2]))))
        )
    elseif h === :call && _rng_callee(ex.args[1]) !== nothing
        return _rewrite_rng(ex)                   # `Base.rand(…)`, `randexp(…)`, … (D-150)
    elseif h === :call && ex.args[1] === :rand &&
            any(a -> a isa Expr && a.head in (:parameters, :kw), ex.args[2:end])
        # `rand(; x = 1)`: named like the other forms
        return _rewrite_rng(ex, :rand)
    elseif h === :quote || h === :macrocall && ex.args[1] === Symbol("@variables")
        return ex
    elseif h === :call
        # a bare `pieces` argument is the cell-scope built-in; a call keeps its head
        return Expr(h, rewrite(ex.args[1]), map(_rewrite_arg, ex.args[2:end])...)
    end
    return Expr(h, map(_rewrite_arg, ex.args)...)
end
_rewrite_arg(a) = a === :pieces ? :(Potts._bare_pieces(pieces)) : rewrite(a)
_isblock(e) = e isa Expr && e.head === :block

# an RNG call in a model body: `Potts._rng_call(:name, args…; kws…)`, which keeps `rand()`
# and `randn(…)` as the model's draws and rejects every other form, naming it
function _rewrite_rng(ex, name = _rng_callee(ex.args[1]))
    args = map(rewrite, ex.args[2:end])
    params = filter(a -> a isa Expr && a.head === :parameters, args)
    rest = filter(a -> !(a isa Expr && a.head === :parameters), args)
    return Expr(:call, :(Potts._rng_call), params..., QuoteNode(name), rest...)
end

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
function _has_endbegin(x)
    return x === :end || x === :begin || (x isa Expr && any(_has_endbegin, x.args)) ||
        (x isa AbstractVector && any(_has_endbegin, x))
end

_isparams(e) = e isa Expr && e.head === :parameters
function _relation_call(e)
    return e isa Expr && e.head === :call && length(e.args) == 2 && !_isparams(e.args[2])
end

function _rewrite_gather(fold, gen, params = nothing)
    P = :(Potts)
    body = gen.args[1]
    kws = params === nothing ? () : (Expr(:parameters, map(rewrite, params.args)...),)
    plain = Expr(:call, fold, kws..., Expr(:generator, map(rewrite, gen.args)...))
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
        return :(
        $P._fold_iter(
            $(kws...), $fold, $n -> $(rewrite(body)), $(rewrite(iter)), $condf
        )
    )
    return :(
        $P._fold_or_gather(
            $(kws...), $fold, $n -> $(rewrite(body)), $(rewrite(iter.args[1])),
            $(rewrite(iter.args[2])), $condf
        )
    )
end

"""A named relation declared in `@relations`."""
struct RelationRef
    name::Symbol
end
ContactDomain(r::RelationRef) = ContactDomain(r.name)
(d::ContactDomain)(r::RelationRef) = ContactDomain(r.name)
