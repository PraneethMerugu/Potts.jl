# Update scheduling (D-042) and population snapshots (D-041).
#
# An update block (`@before_mcs`, `@after_mcs`) follows MTK discrete semantics:
#
# - `Pre(x)` is the value before the block. A variable written in the block and read through
#   `Pre` anywhere other than its own entity in its own update is snapshotted into
#   `x__pre` at the start of the block (one copy per MCS). A bare self-reference
#   (`x ~ x + 1`, or a sibling component in `g ~ normalize(g)`) is the previous value, as
#   `Pre(x)`.
# - A bare `y` written in the same block is y's new value: the reader runs after y's
#   writer. Updates are ordered by these dependencies (cycles are errors) and grouped into
#   stages of one scope and cadence, each one phase.
# - Population folds inside cell and site updates (and cell ODEs) are hoisted into
#   model-scope slots computed just before their stage: one O(N) fold instead of one per
#   cell or site, and no reads of values the stage is writing.
#
# Population folds inside energies are snapshots: computed at initialization and after the
# before-MCS updates (just before the sweep), constant during the sweep, so the derived ΔH
# is exact.

"""A group of updates of one scope and cadence, run as one phase after the folds `pops`."""
struct Stage
    scope::Symbol                         # :cell, :site, :model
    every::Int
    updates::Vector{Update}               # right-hand sides rewritten (snapshots, slots)
    pops::Vector{Pair{Symbol, Any}}       # model slot => population fold, before the stage
end

const _VAR_ROLES = (:site, :field, :cell, :model)

# Variable reads in `x` as (name, through Pre, non-local): non-local reads are inside a
# gather, population, index or Laplacian, i.e. possibly at another entity. With
# `integral_pre = false`, `Pre` reads inside an `integral` are left out: `integral(Pre(w))`
# is its own cell slot, refreshed at the start of the block's phases while `w` still holds
# its block-start value (D-042), so it needs neither a snapshot nor a writer dependency.
function _reads!(out, x, pre::Bool = false, nonlocal::Bool = false, inint::Bool = false;
        integral_pre::Bool = true)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return out
    i = info(x)
    if i !== nothing && i.role in _VAR_ROLES
        (pre && inint && !integral_pre) || push!(out, (i.name, pre, nonlocal))
        return out
    end
    iscall(x) || return out
    op = operation(x)
    op === history_lag && return out                  # reads the ring, not the variable
    p = pre || op isa ModelingToolkitBase.Pre
    nl = nonlocal || op === gather || op === population || op === at || op === at2 || op === Δ
    ii = inint || op === cell_integral
    foreach(a -> _reads!(out, a, p, nl, ii; integral_pre), arguments(x))
    return out
end
_reads(x) = _reads!(Tuple{Symbol, Bool, Bool}[], x)
# The reads that order an update block and decide its snapshots (see `_reads!`).
_block_reads(x) = _reads!(Tuple{Symbol, Bool, Bool}[], x; integral_pre = false)

# Whether `x` reads a variable through `Pre` inside an `integral`.
function _integral_pre(x)
    found = Ref(false)
    _walk(x) do y
        iscall(y) && operation(y) === cell_integral &&
            any(r -> r[2], _reads(arguments(y)[1])) && (found[] = true)
    end
    return found[]
end

# A symbolic stand-in read as a stored array `st.<scope>.name` (role :site/:cell/:model).
_standin(role::Symbol, name::Symbol) = _unwrap(_tag(_sym(name), Info(role, name, nothing, (;))))

# Replace `Pre(x)` (and bare `x` when `self(x)`) for snapshotted names by their snapshot.
# Integrals are left intact: `integral(Pre(x))` and `integral(x)` are cell slots of their
# own (refreshed by the phase schedule, D-042/D-076), and a rewritten operand would name a
# slot that does not exist.
function _to_snapshots(x, snap::Dict{Symbol, Any}, self)
    isempty(snap) && return x
    sub = Dict{Any, Any}()
    inside = Set{Any}()                                # matches inside an integral: kept
    function visit(y, inint)
        y = _unwrap(y)
        y isa SymbolicUtils.BasicSymbolic || return
        key = nothing
        if iscall(y) && operation(y) isa ModelingToolkitBase.Pre
            i = info(_unwrap(arguments(y)[1]))
            i !== nothing && haskey(snap, i.name) && (key = snap[i.name])
        else
            i = info(y)
            i !== nothing && i.role in _VAR_ROLES && self(i.name) && haskey(snap, i.name) && (key = snap[i.name])
        end
        key === nothing || (inint ? push!(inside, y) : (sub[y] = key))
        iscall(y) && foreach(a -> visit(a, inint || operation(y) === cell_integral), arguments(y))
        return
    end
    visit(x, false)
    isempty(sub) && return x
    any(in(inside), keys(sub)) || return _unwrap(Symbolics.substitute(x, sub; fold = Val(false)))
    # a term both outside and inside an integral: shield the integrals from the substitution
    ints = Dict{Any, Any}()
    _walk_all(x) do y
        iscall(y) && operation(y) === cell_integral && !haskey(ints, y) &&
            (ints[y] = _unwrap(_sym(Symbol(:__integral_, length(ints) + 1))))
    end
    y = _unwrap(Symbolics.substitute(x, ints; fold = Val(false)))
    y = _unwrap(Symbolics.substitute(y, sub; fold = Val(false)))
    return _unwrap(Symbolics.substitute(y, Dict{Any, Any}(v => k for (k, v) in ints); fold = Val(false)))
end

# Whether a population fold can be computed once, outside any cell or site (its body does
# not read the enclosing entity).
function _hoistable(pop, rn)
    try
        lower(pop, _model_env(Float64, rn; key = :key))
        return true
    catch
        return false
    end
end

# Replace hoistable population folds in `x` by model slots (named `prefix1`, `prefix2`, … in
# statement order and, within `x`, in canonical order (`_symkey`, D-107); equal folds share
# a slot). Folds inside `integral(…)` stay: the integral's own refresh computes them
# (`_integral_hoist`).
function _hoist_populations(x, slots::Vector{Pair{Symbol, Any}}, rn, prefix::Symbol; strict = false)
    pops = Any[]
    function visit(y)
        y = _unwrap(y)
        (y isa SymbolicUtils.BasicSymbolic && iscall(y)) || return
        operation(y) === cell_integral && return
        operation(y) === population && push!(pops, y)
        foreach(visit, arguments(y))
    end
    visit(x)
    isempty(pops) && return x
    length(pops) > 1 && (pops = pops[sortperm(map(_symkey, pops))])
    sub = Dict{Any, Any}()
    for p in pops
        _hoistable(p, rn) || (strict ? throw(ArgumentError(
            "a population fold in an energy is computed once per MCS, so its body must not read " *
            "the current cell or site; got `$p`")) : continue)
        j = findfirst(s -> isequal(s.second, p), slots)
        if j === nothing
            push!(slots, Symbol(prefix, length(slots) + 1) => p)
            j = length(slots)
        end
        sub[p] = _standin(:model, slots[j].first)
    end
    isempty(sub) && return x
    return _unwrap(Symbolics.substitute(x, sub; fold = Val(false), filterer = _outside_integrals))
end
_outside_integrals(ex) = !(iscall(ex) && operation(ex) === cell_integral) && SymbolicUtils.default_substitute_filter(ex)

# Population folds in the operand of `integral(x)` that read neither the site nor the cell
# (D-110) are the same at every site: each is computed once per refresh of the integral, into
# a model slot named after the fold's content (`_symkey`, D-107), and the operand reads the
# slot. Only outermost folds are candidates (an inner fold may read the outer one's bound
# variable), and not folds that draw random numbers (a draw per site is not one per MCS).
# Returns the operand with the folds substituted and the slots (`name => fold`).
function _integral_hoist(x)
    x = _unwrap(x)
    slots = Pair{Symbol, Any}[]
    sub = Dict{Any, Any}()
    function visit(y)
        y = _unwrap(y)
        (y isa SymbolicUtils.BasicSymbolic && iscall(y)) || return
        if operation(y) === population
            (haskey(sub, y) || !_integral_hoistable(y)) && return
            n = Symbol(:__ifold_, string(_fnv64(_symkey(y)); base = 62))
            any(s -> s.first === n, slots) || push!(slots, n => y)
            sub[y] = _standin(:model, n)               # (a `count`, `any`, `all` stored exactly)
            return
        end
        foreach(visit, arguments(y))
    end
    visit(x)
    isempty(sub) && return x, slots
    sort!(slots; by = first)                           # by content, not by walk order (D-107)
    return _unwrap(Symbolics.substitute(x, sub; fold = Val(false))), slots
end

"""The operand of `integral(x)` as stored: `x` with its site-independent folds read from slots."""
_integral_operand(x) = first(_integral_hoist(x))

function _integral_hoistable(pop)
    _has_op(pop, random_uniform) && return false
    rn = Dict{Any, Symbol}(ni.options.relation => :__gather for (ni, _) in _gathers(pop)
                           if !(ni.options.relation isa RelationRef))
    return _hoistable(pop, rn)
end

# An integral that reads a variable written in the block both through `Pre` (block-start
# values) and bare (new values) has no single refresh point: reject it.
function _check_integral_pre(sys, u::Update, writers)
    _walk(u.eq.rhs) do y
        iscall(y) && operation(y) === cell_integral || return
        rs = filter(r -> haskey(writers, r[1]), _reads(arguments(y)[1]))
        pres = unique(first(r) for r in rs if r[2])
        bares = unique(first(r) for r in rs if !r[2])
        (isempty(pres) || isempty(bares)) && return
        _located(sys, u) do
            throw(ArgumentError("`$(replace(string(y), r"\S*cell_integral" => "integral"))` reads $(join(pres, ", ")) through `Pre` (the values before the block) " *
                                "and $(join(bares, ", ")) bare (the block's new values), all written in the " *
                                "same block; split it into `integral(…Pre…)` and `integral(…)` terms, or keep " *
                                "`Pre(x)` in a site variable (`xp ~ Pre(x)`) and fold that"))
        end
    end
    return nothing
end

_update_scope(u::Update) = (r = info(_unwrap(u.eq.lhs)).role; r === :field ? :site : r)
_update_name(u::Update) = info(_unwrap(u.eq.lhs)).name

"""
    _schedule_block(sys, us, rn, popslots) -> (stages, snapshots)

Order the updates `us` of one block by their new-value dependencies, group them into
stages, and rewrite their right-hand sides (snapshots, hoisted folds). `snapshots` are
`(scope, name)` pairs to copy into `name__pre` at the start of the block.
"""
function _schedule_block(sys, us::Vector{Update}, rn, popslots::Vector{Pair{Symbol, Any}})
    isempty(us) && return Stage[], Tuple{Symbol, Symbol}[]
    names = map(_update_name, us)
    # the components of a vector are one quantity: reading a sibling is a self-reference
    unit = Dict{Symbol, Symbol}()
    for u in us
        i = info(_unwrap(u.eq.lhs))
        unit[i.name] = haskey(i.options, :vector) ? i.options.vector : i.name
    end
    same(n, j) = get(unit, n, n) === unit[names[j]]
    writers = Dict{Symbol, Vector{Int}}()
    for (j, n) in enumerate(names)
        push!(get!(writers, n, Int[]), j)
    end
    deps = [Int[] for _ in us]
    snapnames = Set{Symbol}()
    for (j, u) in enumerate(us)
        _check_integral_pre(sys, u, writers)
        for (n, pre, nl) in _block_reads(u.eq.rhs)
            haskey(writers, n) || continue
            if pre || same(n, j)
                # a previous-value read: free only at the writer's own entity
                (same(n, j) && !nl) || push!(snapnames, n)
            else
                append!(deps[j], filter(!=(j), writers[n]))
            end
        end
        # several writers of one variable (different cadences) run in declaration order
        append!(deps[j], filter(<(j), writers[names[j]]))
    end
    level = zeros(Int, length(us))
    state = zeros(Int, length(us))                   # 0 new, 1 visiting, 2 done
    function visit(j, path)
        state[j] == 2 && return level[j]
        if state[j] == 1
            cyc = names[path[findfirst(==(j), path):end]]
            _located(sys, us[j]) do
                throw(ArgumentError("updates depend on each other's new values in a cycle " *
                                    "($(join([cyc; names[j]], " → "))); read one of them through `Pre`"))
            end
        end
        state[j] = 1
        push!(path, j)
        level[j] = 1 + maximum(d -> visit(d, path), deps[j]; init = 0)
        pop!(path)
        state[j] = 2
        return level[j]
    end
    foreach(j -> visit(j, Int[]), eachindex(us))

    roles = Dict(_update_name(u) => info(_unwrap(u.eq.lhs)).role for u in us)
    snap = Dict{Symbol, Any}(n => _standin(roles[n] === :field ? :site : roles[n], Symbol(n, :__pre))
                             for n in snapnames)
    order = Dict(:model => 1, :cell => 2, :site => 3)
    groups = Dict{Tuple{Int, Int, Int}, Vector{Int}}()
    for (j, u) in enumerate(us)
        push!(get!(groups, (level[j], order[_update_scope(u)], u.every), Int[]), j)
    end
    stages = Stage[]
    for key in sort!(collect(keys(groups)))
        idx = groups[key]
        scope = _update_scope(us[first(idx)])
        pops = Pair{Symbol, Any}[]
        rewritten = map(idx) do j
            u = us[j]
            rhs = _to_snapshots(_unwrap(u.eq.rhs), snap, n -> same(n, j))
            if scope !== :model                        # a model update is one work item already
                before = length(popslots)
                rhs = _hoist_populations(rhs, popslots, rn, :__pop)
                used = Set(n for (n, _, _) in _reads(rhs))
                for s in popslots
                    s.first in used && !any(q -> q.first === s.first, pops) && push!(pops, s)
                end
            end
            Update(u.phase, Equation(u.eq.lhs, rhs), u.every)
        end
        push!(stages, Stage(scope, key[3], rewritten, pops))
    end
    snaps = sort!([(roles[n] === :field ? :site : roles[n], n) for n in snapnames]; by = last)
    return stages, snaps
end
