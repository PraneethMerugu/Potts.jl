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
# gather, population, index or Laplacian, i.e. possibly at another entity.
function _reads!(out, x, pre::Bool = false, nonlocal::Bool = false)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return out
    i = info(x)
    if i !== nothing && i.role in _VAR_ROLES
        push!(out, (i.name, pre, nonlocal))
        return out
    end
    iscall(x) || return out
    op = operation(x)
    op === history_lag && return out                  # reads the ring, not the variable
    p = pre || op isa ModelingToolkitBase.Pre
    nl = nonlocal || op === gather || op === population || op === at || op === at2 || op === Δ
    foreach(a -> _reads!(out, a, p, nl), arguments(x))
    return out
end
_reads(x) = _reads!(Tuple{Symbol, Bool, Bool}[], x)

# A symbolic stand-in read as a stored array `st.<scope>.name` (role :site/:cell/:model).
_standin(role::Symbol, name::Symbol) = _unwrap(_tag(_sym(name), Info(role, name, nothing, (;))))

# Replace `Pre(x)` (and bare `x` when `self(x)`) for snapshotted names by their snapshot.
function _to_snapshots(x, snap::Dict{Symbol, Any}, self)
    isempty(snap) && return x
    sub = Dict{Any, Any}()
    _walk_all(x) do y
        if iscall(y) && operation(y) isa ModelingToolkitBase.Pre
            a = _unwrap(arguments(y)[1])
            i = info(a)
            i !== nothing && haskey(snap, i.name) && (sub[y] = snap[i.name])
        else
            i = info(y)
            i !== nothing && i.role in _VAR_ROLES && self(i.name) && haskey(snap, i.name) &&
                (sub[y] = snap[i.name])
        end
    end
    isempty(sub) && return x
    return _unwrap(Symbolics.substitute(x, sub; fold = Val(false)))
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
# first-seen order; equal folds share a slot).
function _hoist_populations(x, slots::Vector{Pair{Symbol, Any}}, rn, prefix::Symbol; strict = false)
    pops = Any[]
    _walk_all(y -> (iscall(y) && operation(y) === population && push!(pops, y)), x)
    isempty(pops) && return x
    sub = Dict{Any, Any}()
    for p in pops
        _hoistable(p, rn) || (strict ? throw(ArgumentError(
            "a population fold in an energy is computed once per MCS (D-041), so its body must not read " *
            "the current cell or site; got `$p`")) : continue)
        j = findfirst(s -> isequal(s.second, p), slots)
        if j === nothing
            push!(slots, Symbol(prefix, length(slots) + 1) => p)
            j = length(slots)
        end
        sub[p] = _standin(:model, slots[j].first)
    end
    isempty(sub) && return x
    return _unwrap(Symbolics.substitute(x, sub; fold = Val(false)))
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
        for (n, pre, nl) in _reads(u.eq.rhs)
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
