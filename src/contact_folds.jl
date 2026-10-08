# The cell-scope contact fold (D-150 G1): `count(pred for _ in contacts)` and
# `count(pred for _ in contacts(rel))` in cell scope are the cell's contact pairs (s, s′),
# s in the cell, s′ ∈ R(s) inside the lattice and owned by another cell or the medium, for
# which `pred` holds. `pred` reads the partner's kind `kind′` (the medium is kind 0) and
# constants, so it is a kind set fixed when the model is built.
#
# Each distinct fold (relation, kind set) is a CorePotts contact-count tracker: an `Int32`
# cell column named by content (`contacts_<relation>_<hash of pred>`), updated by every
# accepted copy (`CorePotts.commit_contact_count!`) and recomputed by the lifecycle
# (`ctx.contact_counts`, a `CorePotts.ContactCounts` among the problem's relations). A model
# that reads no fold generates none of this: its code and fingerprint are unchanged.

"""The bound variable of a contact fold (`_` in `count(pred for _ in contacts)`): not readable."""
const _CONTACT_PARTNER = _tag(_sym(:contact_partner), Info(:contact_partner, :_, nothing, (;)))

"""
    count_contacts(contact_partner, pred, relation)

A contact fold as [`Potts.updates`](@ref), [`Potts.hamiltonian`](@ref) and
[`Potts.drives`](@ref) print it: `count(pred for _ in contacts(relation))` in cell scope,
the number of the cell's contact pairs over `relation` whose partner satisfies `pred`.
`contact_partner` is the fold's bound variable, `pred` is `true` or an expression of the
partner's kind `kind′`, and `relation` is the relation's name (`:contact` for `contacts`).
Symbolic only: it describes the fold and is never called.
"""
count_contacts(n, pred, rel) = error("`count_contacts` is symbolic-only")
# `rel::Symbol`, so that a literal `pred = true` still builds the symbolic term
Symbolics.@register_symbolic count_contacts(n, pred, rel::Symbol)

# A fold's tracker symbol (`contacts_<relation>_<hash>`) as its description `count_contacts(…)`
_fold_description(i::Info) = _unwrap(count_contacts(_CONTACT_PARTNER, i.options.pred, i.options.relation))

"""
    _contact_fold(fold, body, d::ContactDomain, cond)

`fold(body(_) for _ in contacts(d.relation) if cond(_))` in cell scope: only `count`. The
predicate may read `kind′` and constants; the result is the cell quantity of the tracker.
"""
function _contact_fold(fold, body, d::ContactDomain, cond)
    nameof(fold) === :count || throw(ArgumentError(
        "`$(nameof(fold))(… for _ in contacts)`: over a cell's contact pairs only `count(pred for _ in contacts)` " *
        "is available (the number of pairs whose partner satisfies `pred`)"))
    pred = _fold_predicate(body(_CONTACT_PARTNER))
    if cond !== nothing
        c = _fold_predicate(cond(_CONTACT_PARTNER))
        pred = pred isa Bool ? (pred ? c : false) : c isa Bool ? (c ? pred : false) : pred & c
    end
    rel = d.relation
    Threads.atomic_add!(_FOLDS_BUILT, 1)
    name = Symbol(:contacts_, rel, :_, string(_fnv64(_symkey(pred)); base = 62))
    return Symbolics.wrap(_tag(_sym(name), Info(:contact_count, name, nothing, (; relation = rel, pred))))
end

# A predicate of a contact fold: `Bool` or a symbolic expression of `kind′` and constants
function _fold_predicate(p)
    p isa Bool && return p
    p isa Num || p isa SymbolicUtils.BasicSymbolic || throw(ArgumentError(
        "`count(pred for _ in contacts)`: the predicate must be true or false for each pair, got $(repr(p))"))
    _walk(p) do y
        i = info(y)
        if i !== nothing
            (i.role === :builtin && i.name === :kind′) || throw(ArgumentError(
                "`count(pred for _ in contacts)`: the predicate may read only `kind′` (the partner's kind; " *
                "the medium for owner 0) and constants, not `$(i.name)`"))
        elseif SymbolicUtils.issym(y)
            throw(ArgumentError("`count(pred for _ in contacts)`: the predicate reads `$y`; it may read only `kind′` and constants"))
        end
    end
    return _unwrap(p)
end

"""The kind set of predicate `pred` over the kinds `0:nk-1` (bit `k`: kind `k` counts)."""
function _fold_mask(pred, nk::Integer, name)
    nk <= 64 || throw(ArgumentError("`count(… for _ in contacts)` supports models with at most 63 cell kinds"))
    m = UInt64(0)
    for k in 0:(nk - 1)
        v = pred isa Bool ? pred : _unwrap(Symbolics.substitute(pred, Dict{Any, Any}(_unwrap(B.kind′) => k); fold = Val(true)))
        v isa SymbolicUtils.BasicSymbolic && SymbolicUtils.isconst(v) && (v = SymbolicUtils.unwrap_const(v))
        v isa Bool || throw(ArgumentError("`count(pred for _ in contacts)` (`$name`): the predicate is not true or " *
                                          "false for partner kind $k (it gives `$v`)"))
        v && (m |= UInt64(1) << k)
    end
    return m
end

"""The distinct contact folds read by the statements of `sys`, sorted by name: `(name, relation, pred)`."""
function _contact_folds(sys::PottsSystem)
    found = Dict{Symbol, Info}()
    xs = Any[(u.eq.rhs for u in getfield(sys, :updates))..., (u.eq.lhs for u in getfield(sys, :updates))...,
        (eq.rhs for eq in getfield(sys, :equations))..., (d.when for d in getfield(sys, :divisions))...,
        (r for d in getfield(sys, :divisions) for (_, r) in d.rules if !(r isa Split))...,
        (r.when for r in getfield(sys, :link_rules))..., (o.expr for o in getfield(sys, :observed))...,
        (e.expr for e in getfield(sys, :energies))..., (d.expr for d in getfield(sys, :drives))...,
        (c.expr for c in getfield(sys, :constraints) if c.kind === :expr)..., getfield(sys, :sweep).temperature,
        (x for b in getfield(sys, :discrete) for x in b.next)...]
    for x in xs
        _walk(x) do y
            i = info(y)
            i !== nothing && i.role === :contact_count && (found[i.name] = i)
        end
    end
    return [(i.name, i.options.relation, i.options.pred) for i in (found[k] for k in sort!(collect(keys(found))))]
end

"""
The contact-count trackers of a compiled model: `(name, relation, mask)` per fold, the
relation `:contact` (the contact neighbourhood) or a relation declared in `@relations`.
"""
_contact_trackers(c::CompiledPottsSystem) = c.contact_trackers

"""Relation spec of a fold over `rel` (checked by `_check_contact_folds`)."""
_fold_spec(rel::Symbol, relations, contact_spec) = rel === :contact ? contact_spec : relations[rel]

"""
Check the folds of `sys` at `mtkcompile`: their relations are declared, symmetric and exclude
the origin, the kinds fit the mask, and none is read by the sweep's temperature (it is read
between copies, while concurrent copies change the counts). Returns the largest relation
radius (the copy's footprint reads that far: the commit updates the target's neighbours'
counts) and the trackers `(name, relation, mask)`, which `mtkcompile` stores.
"""
function _check_contact_folds(sys::PottsSystem, relations, contact_spec, lat)
    none = (0, Tuple{Symbol, Symbol, UInt64}[])
    _may_have(sys, :folds) || return none
    folds = _contact_folds(sys)
    isempty(folds) && return none
    haskey(relations, :contact_counts) && throw(ArgumentError("the relation name `contact_counts` is reserved"))
    _walk(getfield(sys, :sweep).temperature) do y
        i = info(y)
        i !== nothing && i.role === :contact_count && throw(ArgumentError(
            "`count(… for _ in contacts)` is not available in the @sweep temperature: it is a cell quantity, exact " *
            "between sweeps, and the temperature is read during the sweep"))
    end
    nk = length(getfield(sys, :kinds))
    rad = 0
    trackers = Tuple{Symbol, Symbol, UInt64}[]
    for (name, rel, pred) in folds
        rel === :contact || haskey(relations, rel) || throw(ArgumentError(
            "`count(… for _ in contacts($rel))`: relation `$rel` is not declared in @relations"))
        r = CorePotts.relation(_fold_spec(rel, relations, contact_spec), lat)
        CorePotts.has_origin(r) && throw(ArgumentError("`count(… for _ in contacts$(rel === :contact ? "" : "($rel)"))`: " *
                                                       "the relation includes the origin (a site is not its own partner)"))
        CorePotts.is_symmetric(r) || throw(ArgumentError("`count(… for _ in contacts$(rel === :contact ? "" : "($rel)"))`: " *
                                                         "the relation is not symmetric (each offset needs its negation)"))
        push!(trackers, (name, rel, _fold_mask(pred, nk, name)))
        rad = max(rad, CorePotts.radius(r))
    end
    return rad, trackers
end

"""The per-copy updates of the model's contact counts (generated `commit!`)."""
_contact_count_commits(c::CompiledPottsSystem) =
    Any[:(CorePotts.commit_contact_count!(st.cell.$n, st.σ, st.cell.kind, $(r === :contact ? :(ctx.contact) : :(ctx.$r)),
              $m, ctx.lattice, prop)) for (n, r, m) in _contact_trackers(c)]

"""The initial count columns (`Int32`) of the model's folds, from σ."""
function _contact_count_columns(c::CompiledPottsSystem, σ, kinds, lat, ncell)
    return Pair{Symbol, Any}[n => CorePotts.recompute_contact_count(σ, kinds, lat,
                                     _fold_spec(r, c.relations, c.contact_spec), m, ncell)
                             for (n, r, m) in _contact_trackers(c)]
end

"""
`relations` with `contact_counts` (the lifecycle's rebuild list) when the model has folds.
Not specialised on the relations' type: one compiled method serves every model (a model
without folds only returns its argument).
"""
function _with_contact_counts(c::CompiledPottsSystem, @nospecialize(relations::NamedTuple))
    ts = _contact_trackers(c)
    isempty(ts) && return relations
    nk = length(getfield(c.sys, :kinds))
    cc = CorePotts.ContactCounts(Tuple(CorePotts.ContactCount(n, _fold_spec(r, c.relations, c.contact_spec), m; kinds = nk)
                                       for (n, r, m) in ts))
    return merge(relations, (; contact_counts = cc))
end

# One walker for every op set: the ops sit in a `Vector{Any}`, so all calls share one closure
# type and one compiled `_walk` (the precompile workload's `PottsProblem` compiles it).
# A closure capturing a function would compile a fresh walk per function: +0.1 s on a cold
# `PottsProblem` (P6.0o latency, D-137).
const _DRAW_OPS = Any[random_uniform, random_normal, random_normal_above]
const _BOUNDED_DRAW_OPS = Any[random_normal_above]
function _has_any_op(x, ops::Vector{Any})
    found = Ref(false)
    _walk(y -> (iscall(y) && _is_one_of(operation(y), ops) && (found[] = true)), x)
    return found[]
end

_is_one_of(op, ops::Vector{Any}) = any(o -> o === op, ops)

"""Whether `x` draws (`rand()`, `randn()`, `randn(μ, σ; lower)`)."""
_has_draw(x) = _has_any_op(x, _DRAW_OPS)

"""Whether the model has a bounded draw (`randn(μ, σ; lower)`): its state carries a status word."""
function _has_bounded_draw(sys::PottsSystem)
    _may_have(sys, :bounded) || return false
    hit(x) = _has_any_op(x, _BOUNDED_DRAW_OPS)
    any(u -> hit(u.eq.rhs), getfield(sys, :updates)) && return true
    any(eq -> hit(eq.rhs), getfield(sys, :equations)) && return true
    for d in getfield(sys, :divisions)
        hit(d.when) && return true
        any(((_, r),) -> !(r isa Split) && hit(r), d.rules) && return true
    end
    any(r -> hit(r.when), getfield(sys, :link_rules)) && return true
    return any(b -> any(hit, b.next), getfield(sys, :discrete))
end
