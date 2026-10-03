# Code generation: a `CompiledPottsSystem` and a scalar type → the functions of a
# `CorePotts.CPMFunction` (RuntimeGeneratedFunctions, `drop_expr`'d so they are isbits and
# GPU-safe), plus the brute-force `total_energy` used for self-verification.

"""Compile a function expression to a RuntimeGeneratedFunction without its expression."""
function _rgf(ex)
    log = _GENERATED[]
    log === nothing || push!(log, ex)
    return RuntimeGeneratedFunctions.drop_expr(
        RuntimeGeneratedFunctions.RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))
end

# The expressions compiled while building one problem (D-016 fingerprints, `generated_code`)
const _GENERATED = Base.ScopedValues.ScopedValue{Union{Nothing, Vector{Any}}}(nothing)

"""Run `f()` and return `(result, exprs)`: every function expression compiled by `_rgf` in it."""
function _recording(f)
    log = Any[]
    r = Base.ScopedValues.with(f, _GENERATED => log)
    return r, log
end

"""Hash of generated code, independent of line numbers and the install path."""
_code_hash(exprs, h::UInt = zero(UInt)) =
    foldl((h, ex) -> hash(string(_commutative_order!(_strip_lines!(deepcopy(ex)))), h), exprs; init = h)

# Symbolics orders the terms of a sum or product by hashes that involve function identities,
# so the operand order of generated `+`/`*` calls can differ between builds of the same
# source, and so can their grouping into nested binary calls. The fingerprint reads them
# flattened across same-operator nesting and in a canonical order (by printed operand): the
# same model on another checkout or build fingerprints alike (order and grouping change
# rounding only, not the model).
function _commutative_order!(ex)
    ex isa Expr || return ex
    foreach(_commutative_order!, ex.args)
    if ex.head === :call && length(ex.args) > 2 && any(f -> ex.args[1] === f, (:+, :*, +, *))
        op = ex.args[1]
        flat = Any[]
        for a in @view ex.args[2:end]
            if a isa Expr && a.head === :call && length(a.args) > 2 && a.args[1] === op
                append!(flat, @view a.args[2:end])
            else
                push!(flat, a)
            end
        end
        sort!(flat; by = string)
        resize!(ex.args, 1)
        append!(ex.args, flat)
    end
    return ex
end

# Every line number out of an expression, including those macro calls carry (`@inbounds`
# records the generating file's path, which would tie the fingerprint to the checkout).
function _strip_lines!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(_strip_lines!, ex.args)
    return ex
end

# `key`: the RNG key in scope (functions of the MCS phases and lifecycle); enables `rand()`.
_draws(key, mcs, entity) = key === nothing ? () : (:__draw => (key, mcs, entity),)

_cell_env(T, c, relname; kind = :(Potts._cellkind(st, $c)), mcs = nothing, key = nothing, extra = ()) =
    LowerEnv(T, :cell, Dict{Symbol, Any}(_draws(key, mcs, c)..., :volume => :($T(@inbounds st.cell.volume[$c])),
        :surface => :(@inbounds st.cell.surface[$c]), :kind => kind, :id => c,
        :generation => :(@inbounds st.cell.generation[$c]), :__cell => c,
        :major_length => :(CorePotts.major_length($T, st.cell, ctx.lattice, $c)),
        :cluster => :(CorePotts.cluster_of(st.cell, $c)),
        :cluster_volume => :($T(Potts._cellval(st.cell.cluster_volume, CorePotts.cluster_of(st.cell, $c)))),
        :cluster_surface => :(Potts._cellval(st.cell.cluster_surface, CorePotts.cluster_of(st.cell, $c))),
        (mcs === nothing ? () : (:mcs => mcs,))..., extra...), relname)

# A cluster named by its root `r` (cluster terms): its trackers, the root's kind and variables.
_cluster_env(T, r, relname; δ = nothing) =
    LowerEnv(T, :cell, Dict{Symbol, Any}(:cluster_volume => :($T(@inbounds st.cell.cluster_volume[$r])),
        :cluster_surface => :(@inbounds st.cell.cluster_surface[$r]), :kind => :(Potts._cellkind(st, $r)),
        :id => r, :__cell => r, (δ === nothing ? () : (:δcluster_surface => δ,))...), relname)

_site_env(T, i, relname; mcs = nothing, key = nothing) =
    LowerEnv(T, :site, Dict{Symbol, Any}(_draws(key, mcs, i)..., :owner => :(@inbounds st.σ[$i]),
        :kind => :(CorePotts.owner_kind(st, $i)), :__site => i,
        :position => :(Potts._position($T, ctx, $i)), :site => i,
        (mcs === nothing ? () : (:mcs => mcs,))...), relname)

_proposal_env(T, relname) = LowerEnv(T, :proposal, Dict{Symbol, Any}(:source => :source,
    :target => :target, :old => :old, :new => :new, :__kind_of => (:old => :k_old, :new => :k_new),
    :local_components => :(Int32(CorePotts.local_components(st.σ, ctx, prop))),
    :ring_arcs => :(Int32(CorePotts.ring_arcs(st.σ, ctx, prop))),
    :ring_cells => :(Int32(CorePotts.ring_cells(st.σ, ctx, prop))),
    :ring_medium => :(Int32(CorePotts.ring_medium(st.σ, ctx, prop)))), relname)

# a contact pair (s, s′): owners `a`, `n`, their kinds, the relation weight, and the sites
# (site variables `x ≡ x[site]`, `x′ ≡ x[site′]`)
_contact_env(T, a, ka, n, kn, w, site, site′, relname; extra = ()) = LowerEnv(T, :contact,
    Dict{Symbol, Any}(:kind => ka, :kind′ => kn, :owner => a, :owner′ => n, :weight => w,
        :__site => site, :site => site, :site′ => site′, :__cell => a, extra...), relname)

_edge_env(T, a, b, k, d, relname; mcs = nothing) = LowerEnv(T, :edge,
    Dict{Symbol, Any}(:a => a, :b => b, :distance => d, :__edge => (k, a),
        (mcs === nothing ? () : (:mcs => mcs,))...), relname)

# Relationship `r`'s link store in cell state `cell` (CorePotts `relationships.jl`): a
# NamedTuple view of its adjacency and, with `payloads`, its edge-variable columns.
_adjacency(r::Symbol, cell = :(st.cell)) = :($cell.$(CorePotts.adjacency_name(r)))
function _link_store(c::CompiledPottsSystem, r::Symbol, cell = :(st.cell); payloads::Bool = false)
    cols = Any[Expr(:kw, :links, _adjacency(r, cell))]
    payloads && for x in c.edge_vars[r]
        n = Symbol(:link_, info(x).name)
        push!(cols, Expr(:kw, n, :($cell.$n)))
    end
    return Expr(:tuple, Expr(:parameters, cols...))
end
# Edge energies grouped by relationship, in declaration order.
_edge_energies(c::CompiledPottsSystem) =
    [(r.name, sum(E for (q, E) in c.edge_terms if q === r.name)) for r in c.relationships
     if any(t -> first(t) === r.name, c.edge_terms)]

_kindtest(k, kinds) = isempty(kinds) ? true : foldl((a, b) -> :($a || $b), [:($k == $x) for x in kinds])

const _PROP_LOCALS = quote
    old = prop.old
    new = prop.new
    target = prop.target
    source = prop.source
    k_old = Potts._cellkind(st, old)       # `kind[old]`/`kind[new]` read these (D-014)
    k_new = Potts._cellkind(st, new)
end

# ---------------------------------------------------------------------------------------
# delta_H

function _delta_H_expr(c::CompiledPottsSystem, T; drives::Bool = true)
    rn = c.gather_names
    body = Any[_PROP_LOCALS, :(dH = zero($T))]
    surf_rel = c.uses_surface ? :surface : nothing
    fused_surface = false
    if c.uses_surface
        push!(body, :(δs_old = zero(eltype(st.cell.surface))), :(δs_new = zero(eltype(st.cell.surface))))
    end
    # on-copy writes the energies read (D-045): the state after the copy has them applied
    after, oc_binds, oc_vals = _oncopy_after(c, T, rn)
    append!(body, oc_vals)
    # contact pairs around the target: site values stay with the copy except those written
    # at the target, which the after-copy pairs read (`x[site]` at `site = target`)
    contact_after = Dict{Any, Any}(_unwrap(at(Symbolics.wrap(x), B.site)) => v for (x, v) in after[:target])
    for (rel, E) in _sorted(c.contact_terms)
        R = rel === :contact ? :(ctx.contact) : :(ctx.$rel)
        ctxname = rel === :contact ? :contact : rel
        Ea = isempty(contact_after) ? E : Symbolics.substitute(E, contact_after; fold = Val(false))
        Enew = lower(Ea, _contact_env(T, :new, :k_new, :n, :k_n, :w, :target, :sn, rn; extra = oc_binds))
        Eold = lower(E, _contact_env(T, :old, :k_old, :n, :k_n, :w, :target, :sn, rn))
        fuse = c.uses_surface && !fused_surface && _same_relation(c, ctxname, :surface)
        fused_surface |= fuse
        surfacc = fuse ? quote
            ws = eltype(st.cell.surface)(w)
            δs_old += ifelse(n == old, ws, -ws)
            δs_new += ifelse(n == new, -ws, ws)
        end : nothing
        push!(body, quote
            for kk in 1:length($R)
                ins, y = CorePotts.shift(ctx.lattice, prop.x, @inbounds $R.offsets[kk])
                if ins
                    sn = CorePotts.linear_index(ctx.lattice, y)
                    n = @inbounds st.σ[sn]
                    w = CorePotts.weight($R, kk)
                    k_n = Potts._cellkind(st, n)
                    n != new && (dH += $Enew)
                    n != old && (dH -= $Eold)
                    $surfacc
                end
            end
        end)
    end
    if c.uses_surface && !fused_surface
        push!(body, :((δs_old, δs_new) = CorePotts.surface_change(st.σ, ctx, prop; T = eltype(st.cell.surface))))
    end
    # cell terms, grouped by kind filter
    groups = Dict{Vector{Int}, Any}()
    for (kinds, E) in c.cell_terms
        groups[kinds] = haskey(groups, kinds) ? groups[kinds] + E : E
    end
    for (side, dv, k, δs) in ((:old, -1, :k_old, :δs_old), (:new, +1, :k_new, :δs_new))
        terms = Any[]
        for (kinds, E) in _sorted(groups)
            ΔE = _cell_delta(E, dv; after = after[side])
            _nops(ΔE) == 0 && isequal(_unwrap(ΔE), 0) && continue
            env = _cell_env(T, side, rn; kind = k, extra = (:δsurface => δs,
                :δmajor_length => :(CorePotts.major_length_after($T, st.cell, ctx.lattice, $side, prop.x, $dv)), oc_binds...))
            push!(terms, :($(_kindtest(k, kinds)) && (dH += $(lower(ΔE, env)))))
        end
        isempty(terms) || push!(body, Expr(:&&, :($side != 0), Expr(:block, terms...)))
    end
    append!(body, _cluster_delta_code(c, T))
    for (r, E) in _edge_energies(c)
        Ecode = lower(E, _edge_env(T, :ea, :eb, :ek, :ed, rn))
        push!(body, :(dH += CorePotts.link_delta($T, st.cell, $(_link_store(c, r)), ctx, prop,
            (ea, eb, ek, ed) -> $Ecode)))
    end
    for E in c.site_terms
        Eafter = lower(isempty(after[:target]) ? E : Symbolics.substitute(E, after[:target]; fold = Val(false)),
            LowerEnv(T, :site, Dict{Symbol, Any}(:owner => :new, :kind => :k_new, :__site => :target,
            :position => :(Potts._position($T, ctx, target)), :site => :target, oc_binds...), rn))
        before = lower(E, LowerEnv(T, :site, Dict{Symbol, Any}(:owner => :old, :kind => :k_old, :__site => :target,
            :position => :(Potts._position($T, ctx, target)), :site => :target), rn))
        push!(body, :(dH += $Eafter - $before))
    end
    drives && c.drive !== nothing && push!(body, :(dH += $(lower(c.drive, _proposal_env(T, rn)))))
    push!(body, :(return $T(dH)))
    return :((st, p, prop, ctx) -> $(Expr(:block, body...)))
end

_group_terms(terms) = (g = Dict{Vector{Int}, Any}(); foreach(((k, E),) -> (g[k] = haskey(g, k) ? g[k] + E : E), terms); g)

# Cluster terms: the target moves from the cluster of `old` to that of `new` (nothing
# changes when both are the same cluster).
function _cluster_delta_code(c::CompiledPottsSystem, T)
    isempty(c.cluster_terms) && return Any[]
    rn = c.gather_names
    body = Any[:(cl_old = CorePotts.cluster_of(st.cell, old)), :(cl_new = CorePotts.cluster_of(st.cell, new))]
    c.uses_cluster_surface && push!(body,
        :(δc = CorePotts.cluster_surface_change(st.σ, st.cell, ctx, prop; T = eltype(st.cell.cluster_surface))))
    sides = Any[]
    for (side, dv, δ) in ((:cl_old, -1, :(δc[1])), (:cl_new, +1, :(δc[2])))
        terms = Any[]
        for (kinds, E) in _sorted(_group_terms(c.cluster_terms))
            ΔE = _cell_delta(E, dv)
            env = _cluster_env(T, side, rn; δ = c.uses_cluster_surface ? δ : nothing)
            push!(terms, :($(_kindtest(:(Potts._cellkind(st, $side)), kinds)) && (dH += $(lower(ΔE, env)))))
        end
        push!(sides, Expr(:&&, :($side != 0), Expr(:block, terms...)))
    end
    push!(body, Expr(:if, :(cl_old != cl_new), Expr(:block, sides...)))
    return body
end

# Deterministic iteration over Dicts used in codegen (the generated code must not depend on
# hash order, or rebuilding a model would produce a new function type).
_sorted(d::AbstractDict) = sort!(collect(d); by = x -> string(first(x)))

_same_relation(c::CompiledPottsSystem, a::Symbol, b::Symbol) =
    a === b || isequal(a === :contact ? c.contact_spec : get(c.relations, a, nothing),
        b === :contact ? c.contact_spec : get(c.relations, b, nothing))

"""
On-copy updates whose targets the energies read, as after-copy stand-ins: `after[side]`
maps a cell variable written at `new`/`old` (or a site variable written at `target`) to a
local holding its on-copy value, computed as `commit!` will. A site variable cleared on
ownership change (and not written) is its default after the copy.
"""
function _oncopy_after(c::CompiledPottsSystem, T, rn)
    after = Dict(:new => Dict{Any, Any}(), :old => Dict{Any, Any}(), :target => Dict{Any, Any}())
    binds = Pair{Symbol, Any}[]
    vals = Any[]
    read = Set{Symbol}(n for E in Any[last.(c.cell_terms)..., c.site_terms..., values(c.contact_terms)...]
                       for (r, n) in _uses(E) if r in SCOPES)
    for x in c.sys.variables                         # `commit!` resets these before the writes
        i = info(x)
        (i.role in (:site, :field) && i.name in read && get(i.options, :clear_on_ownership_change, false) === true) || continue
        after[:target][_unwrap(x)] = i.default isa Real ? T(i.default) : zero(T)
    end
    for (j, u) in enumerate(get(c.updates, (:on_copy, :proposal), Update[]))
        x, idx = arguments(_unwrap(u.eq.lhs))
        i = info(x)
        i.name in read || continue
        side = _oncopy_side(i, idx)
        side === nothing && continue                 # rejected by mtkcompile
        name = Symbol(:__oncopy_, j)
        after[side][_unwrap(x)] = _unwrap(_tag(_sym(name), Info(:builtin, name, nothing, (;))))
        push!(binds, name => Symbol(:v_oncopy_, j))
        push!(vals, :($(Symbol(:v_oncopy_, j)) = $(lower(u.eq.rhs, _proposal_env(T, rn)))))
    end
    return after, binds, vals
end

"""Where an on-copy write `x[idx]` lands for the energies: `:new`, `:old`, `:target` or `nothing`."""
function _oncopy_side(i::Info, idx)
    ii = info(idx)
    (ii === nothing || ii.role !== :builtin) && return nothing
    i.role === :cell && ii.name in (:new, :old) && return ii.name
    i.role in (:site, :field) && ii.name === :target && return :target
    return nothing
end

# ---------------------------------------------------------------------------------------
# commit!, constraint, temperature

function _commit_expr(c::CompiledPottsSystem, T)
    rn = c.gather_names
    env = _proposal_env(T, rn)
    body = Any[_PROP_LOCALS]
    vals = Any[]; writes = Any[]
    for (j, u) in enumerate(get(c.updates, (:on_copy, :proposal), Update[]))
        v = Symbol(:v_, j)
        push!(vals, :($v = $(lower(u.eq.rhs, env))))
        push!(writes, _write(_unwrap(u.eq.lhs), v, env))
    end
    append!(body, vals)
    c.uses_surface && push!(body, :(δs = CorePotts.surface_change(st.σ, ctx, prop; T = eltype(st.cell.surface))))
    push!(body, :(CorePotts.commit_volume!(st, p, prop, ctx)))
    c.uses_surface && push!(body, :(CorePotts.commit_surface!(st.cell.surface, prop, δs)))
    c.needs_moments && push!(body, :(CorePotts.commit_moments!(st.cell, ctx.lattice, prop)))
    c.uses_cluster_surface && push!(body, :(CorePotts.commit_cluster_surface!(st.cell, prop,
        CorePotts.cluster_surface_change(st.σ, st.cell, ctx, prop; T = eltype(st.cell.cluster_surface)))))
    c.uses_clusters && push!(body, :(CorePotts.commit_cluster_volume!(st.cell, prop)))
    # `clear_on_ownership_change`: the target's value resets to the default, before the
    # on-copy writes (which may set it again)
    for x in c.sys.variables
        i = info(x)
        get(i.options, :clear_on_ownership_change, false) === true || continue
        v = i.default isa Real ? T(i.default) : zero(T)
        push!(body, :(@inbounds st.site.$(i.name)[target] = $v))
    end
    append!(body, writes)
    push!(body, :(return nothing))
    return :((st, p, prop, ctx) -> $(Expr(:block, body...)))
end

# Write `v` into the target of an on-copy update `x[i] ~ …` (a cell index may be the
# medium, 0: then there is nothing to write).
function _write(lhs, v, env)
    x, i = arguments(lhs)
    xi = info(x)
    j = lower(i, env)
    if xi.role === :cell
        a = :(st.cell.$(xi.name))
        return :(($j) != 0 && (@inbounds $a[$j] = convert(eltype($a), $v)))
    elseif xi.role in (:site, :field)
        a = :(st.site.$(xi.name))
        return :(@inbounds $a[$j] = convert(eltype($a), $v))
    end
    error("@on_copy can assign site or cell variables, not `$(xi.name)`")
end

function _constraint_expr(c::CompiledPottsSystem, T)
    isempty(c.constraints) && return nothing
    env = _proposal_env(T, c.gather_names)
    tests = Any[]
    for k in c.constraints
        if k.kind === :expr
            push!(tests, lower(k.expr, env))
        elseif k.kind === :connectivity          # evaluated only for a losing cell of `kinds`
            push!(tests, :(old == 0 || !$(_kindtest(:k_old, k.kinds)) || $(lower(k.expr, env))))
        elseif k.kind === :no_extinction
            push!(tests, :(CorePotts.forbid_extinction(st.cell.volume, prop)))
        end
    end
    test = foldl((a, b) -> :($a && $b), tests)
    return :((st, p, prop, ctx) -> $(Expr(:block, _PROP_LOCALS, :(return $test))))
end

# The copy temperature: a copy-scope expression, or a cell-scope one evaluated for the
# gaining and losing cells and combined (`combine`, default `min`); the medium never
# contributes (CompuCell3D/Morpheus convention).
function _temperature_expr(c::CompiledPottsSystem, T)
    sw = c.sys.sweep
    rn = c.gather_names
    if _observed_scope(sw.temperature) === :cell
        tn = lower(sw.temperature, _cell_env(T, :new, rn; kind = :k_new))
        to = lower(sw.temperature, _cell_env(T, :old, rn; kind = :k_old))
        return :((st, p, prop, ctx) -> $(Expr(:block, _PROP_LOCALS, quote
            new == 0 && return $T($to)
            old == 0 && return $T($tn)
            return $T($(sw.combine)($tn, $to))
        end)))
    end
    return :((st, p, prop, ctx) -> $(Expr(:block, _PROP_LOCALS,
        :(return $T($(lower(sw.temperature, _proposal_env(T, rn))))))))
end

# ---------------------------------------------------------------------------------------
# Phases: synchronous updates, field equations, per-cell ODEs

"""One `CellReduce` per `integral(x)`: the site expression `x` summed over each cell."""
function _integral_phases(c::CompiledPottsSystem, T)
    env = _site_env(T, :i, c.gather_names; mcs = :mcs, key = :key)
    return Any[CorePotts.CellReduce((:cell, _integral_name(x)), _rgf(:((st, p, ctx, key, mcs, i) -> $(lower(x, env)))))
               for x in _integrals(c.sys)]
end

# Indices (into `_integrals(sys)`) of the integrals `integral(x)` read in the expressions `xs`.
function _integrals_read(xs, ints)
    out = Int[]
    for x in xs
        _walk(x) do y
            iscall(y) && operation(y) === cell_integral || return
            j = findfirst(z -> isequal(z, _unwrap(arguments(y)[1])), ints)
            j === nothing || j in out || push!(out, j)
        end
    end
    return out
end

# Names the stage writes (its updates' left sides).
_stage_writes(stage) = Set{Symbol}(_update_name(u) for u in stage.updates)

_phases(c::CompiledPottsSystem, T, values, spec::SolverSpec) = first(_phases_parts(c, T, values, spec))

# The phases, and the last cell update phase with the columns it writes (`(; phase, writes)`,
# or `nothing`): a candidate to run with the lifecycle trigger (`_fuse_before`)
function _phases_parts(c::CompiledPottsSystem, T, values, spec::SolverSpec)
    rn = c.gather_names
    cand = nothing
    integrals = _integral_phases(c, T)
    before = Any[]; after = Any[]
    # integrals: fresh at every MCS boundary (and at init). An update block reads them fresh
    # (D-042: a bare name in the block is its new value): the sweep moves σ, so each integral
    # the after-MCS updates, equations or lifecycle read is refreshed after it, and an
    # integral whose operand an update writes is refreshed after that write, just before
    # the stage that next reads it. Integrals whose operands no update writes cost exactly
    # the one refresh at the start of the after-MCS phases.
    s = c.sys
    ints = _integrals(s)
    post = Any[(eq.rhs for eq in s.equations)..., (d.when for d in s.divisions)...,
        (r for d in s.divisions for (_, r) in d.rules if !(r isa Split))..., (r.when for r in s.link_rules)...,
        (x for b in c.discrete for x in b.next)...]
    after_read = _integrals_read(Any[(u.eq.rhs for u in s.updates if u.phase === :after_mcs)..., post...], ints)
    operands = [Set(n for (n, pre, _) in _reads(x) if !pre) for x in ints]
    written(phase) = Set{Symbol}(_update_name(u) for u in s.updates if u.phase === phase)
    dirtied(phase) = [j for j in eachindex(ints) if !isempty(intersect(operands[j], written(phase)))]
    after_dirty = dirtied(:after_mcs)
    isempty(after_read) || append!(after, integrals[j] for j in eachindex(ints) if !(j in after_dirty))
    # update blocks (D-042): snapshots of previous values, then the ordered stages, each
    # after its hoisted population folds
    for phase in (:before_mcs, :after_mcs)
        dst = phase === :before_mcs ? before : after
        dirty = dirtied(phase)
        # stale integrals: the after-MCS ones not refreshed above (the sweep moved σ); none
        # before the MCS (the boundary refresh is fresh)
        stale = Set{Int}(phase === :after_mcs && !isempty(after_read) ? after_dirty : Int[])
        for (scope, n) in c.pre_snapshots[phase]
            push!(dst, CorePotts.CopyPhase((scope, Symbol(n, :__pre)) => (scope, n)))
        end
        for stage in c.schedule[phase]
            if !isempty(dirty)
                for j in _integrals_read(Any[(u.eq.rhs for u in stage.updates)..., (x for (_, x) in stage.pops)...], ints)
                    j in stale || continue
                    push!(dst, stage.every == 1 ? integrals[j] : _Gated(stage.every, integrals[j]))
                    stage.every == 1 && delete!(stale, j)      # a gated refresh leaves it stale
                end
            end
            if !isempty(stage.pops)
                ph = _slots_phase(T, stage.pops, rn)
                push!(dst, stage.every == 1 ? ph : _Gated(stage.every, ph))
            end
            if stage.scope === :site
                append!(dst, _site_update_phases(c, T, stage.updates, stage.every, rn))
            elseif stage.scope === :model
                push!(dst, CorePotts.ModelPhase(_rgf(_model_update_expr(c, T, stage.updates, stage.every, rn))))
            else
                ph = CorePotts.CellPhase(_rgf(_cell_update_expr(c, T, stage.updates, stage.every, rn)))
                push!(dst, ph)
                phase === :after_mcs && (cand = (; phase = ph, writes = _stage_writes(stage)))
            end
            if !isempty(dirty)
                w = _stage_writes(stage)
                foreach(j -> isempty(intersect(operands[j], w)) || push!(stale, j), dirty)
            end
        end
        # what reads the integrals after the block: the equations and lifecycle (after the
        # MCS) or the sweep's temperature (before it)
        if !isempty(stale)
            later = _integrals_read(phase === :after_mcs ? post : Any[s.sweep.temperature], ints)
            append!(dst, integrals[j] for j in sort!(collect(stale)) if j in later)
        end
    end
    # energy snapshots (D-041): after the before-MCS updates, constant during the sweep
    snapshots = isempty(c.energy_snapshots) ? () : (_slots_phase(T, c.energy_snapshots, rn),)
    append!(before, snapshots)
    # fields after the synchronous updates (MTK equations advance with the MCS clock)
    dt = c.sys.sweep.mcs_duration
    for (x, rate) in c.fields
        name = info(x).name
        f = _rgf(:((st, p, ctx, key, mcs, i, c) -> $(lower(rate, _site_env(T, :i, rn; mcs = :mcs, key = :key)))))
        solver = spec.resolved[name]
        sub = _auto_substeps(x, rate, values, dt, c.sys.lattice, solver.substeps)
        lowerclip = solver.lower
        push!(after, CorePotts.FieldStep((:site, name) => (:site, Symbol(name, :__next)), f;
            dt = T(dt), substeps = sub, lower = lowerclip === nothing ? nothing : T(lowerclip)))
    end
    # cell then model ODEs (model ODEs see the cells' new values; D-077 N3), one phase per
    # solver (`_ode_groups`; one group unless `solvers` sets a variable apart), after the
    # population folds their rates read. Several groups in a scope, or cell ODEs that read
    # another cell's unknowns (`_ode_scratch`), write scratch `x__ode`, published after the
    # scope's last group, so every rate reads the pre-step state (Jacobi, P6.0n).
    isempty(c.cell_ode_pops) || push!(after, _slots_phase(T, c.cell_ode_pops, rn))
    for scope in (:cell, :model)
        groups = _ode_groups(scope === :cell ? c.cell_odes : c.model_odes, spec)
        scratch = _ode_scratch(c, spec, scope)
        for (solver, odes) in groups
            # a host phase right after another one finds the queue idle (the previous one
            # synchronized and only copied since): it skips its sync (P6.0v3, D-101)
            sync = isempty(after) || !(last(after) isa _AdaptiveODE)
            push!(after, solver isa Adaptive ? _adaptive_phase(c, T, dt, scope, odes, solver; scratch, sync) :
                         scope === :cell ? CorePotts.CellPhase(_rgf(_cell_ode_expr(c, T, dt, odes, solver; scratch))) :
                         CorePotts.ModelPhase(_rgf(_model_ode_expr(c, T, dt, odes, solver; scratch))))
        end
        scratch || continue
        for (x, _) in (scope === :cell ? c.cell_odes : c.model_odes)
            n = info(x).name
            push!(after, CorePotts.CopyPhase((scope, n) => (scope, _ode_scratch_name(n))))
        end
    end
    append!(after, _discrete_phases(c, T))
    append!(after, _link_phases(c, T))
    # at the MCS boundary (after the lifecycle): integrals, then history rings take the values
    finish = Any[integrals...]
    for (n, _) in sort!(collect(_history_depths(c.sys)); by = first)
        scope = any(x -> info(x).name === n && info(x).role === :model, c.sys.variables) ? :model : :site
        push!(finish, CorePotts.HistoryPush(n => (scope, n)))
    end
    phases = CorePotts.Phases(; before_mcs = Tuple(before), after_mcs = Tuple(after), end_mcs = Tuple(finish),
        at_init = (integrals..., snapshots...))
    return phases, cand
end

# F1 (P6.0v3, D-101): when the last after-MCS phase is a cell update (`cand`) and the trigger
# reads the columns it writes only at the trigger's own cell, the update moves into the
# lifecycle as `Lifecycle.before`: on a device, update and trigger of a cell then run in one
# work item, one launch for both. Same code, same order (the host planner runs `before` as
# its own launch first); the expressions and so the fingerprint are unchanged.
function _fuse_before(c::CompiledPottsSystem, T, phases, lc, cand)
    (lc === nothing || cand === nothing || lc.before !== nothing) && return phases, lc
    after = phases.after_mcs
    (!isempty(after) && last(after) === cand.phase) || return phases, lc
    _reads_own_only(_trigger_expr(c, T).args[2], cand.writes) || return phases, lc     # the body
    fused = CorePotts.Lifecycle(lc.trigger, lc.normal, lc.cluster_normal, lc.kind, lc.divide!, lc.cluster_divide!,
        lc.rebuild!, lc.every, lc.rules, cand.phase.f!)
    return CorePotts.Phases(phases.before_mcs, Base.front(after), phases.end_mcs, phases.at_init), fused
end

# Whether generated cell code `ex` (of cell `c`) reads the cell columns `writes` only at its
# own cell: as `st.cell.x[c]` or `Potts._cellval(st.cell.x, c)`. Any other use of such a
# column, of the whole cell state (except a `_CELL_HELPER_READS` helper that reads none of
# them) or of the whole state (except `Potts._cellkind(st, c)` with `kind` unwritten) is not.
function _reads_own_only(ex, writes)
    ok = Ref(true)
    column(x) = x isa Expr && x.head === :. && length(x.args) == 2 && x.args[1] == :(st.cell) &&
                x.args[2] isa QuoteNode ? x.args[2].value : nothing
    own(col, i) = column(col) !== nothing && i === :c
    function visit(x)
        ok[] || return
        x === :st && (ok[] = false; return)                 # the whole state
        x isa Expr || return
        if x == :(st.cell)
            ok[] = false                                    # the whole cell state
        elseif (n = column(x)) !== nothing
            n in writes && (ok[] = false)                   # a written column, not at `c`
        elseif x.head === :. && x.args[1] === :st && x.args[2] isa QuoteNode
            return                                          # σ, site, model, history: never written
        elseif x.head === :ref && length(x.args) == 2 && own(x.args[1], x.args[2])
            return
        elseif x.head === :call && string(x.args[1]) == "Potts._cellval" && length(x.args) == 3 &&
               own(x.args[2], x.args[3])
            return
        elseif x.head === :call && string(x.args[1]) == "Potts._cellkind" && length(x.args) == 3 && x.args[2] === :st
            :kind in writes && (ok[] = false)
            visit(x.args[3])
        elseif x.head === :call && haskey(_CELL_HELPER_READS, string(x.args[1]))
            for a in x.args[2:end]
                a == :(st.cell) ? (isempty(intersect(_CELL_HELPER_READS[string(x.args[1])], writes)) || (ok[] = false)) :
                visit(a)
            end
        else
            foreach(visit, x.args)
        end
        return
    end
    visit(ex)
    return ok[]
end

"""One model phase computing the population folds `slots` (`name => fold`) into `st.model`."""
function _slots_phase(T, slots, rn)
    env = _model_env(T, rn; key = :key)
    body = [:(@inbounds st.model.$(n)[1] = $T($(lower(x, env)))) for (n, x) in slots]
    return CorePotts.ModelPhase(_rgf(:((st, p, ctx, key, mcs) -> $(Expr(:block, body..., :(return nothing))))))
end

# The cell ODEs `odes` of one solver (`D(x) ~ f` on cell variables, component equations;
# all of them unless `solvers` sets some apart) advance together, per cell, over one MCS of
# length `dt` with that fixed-step `solver` (a batched system over the cell dimension: one
# work item per cell, CPU or GPU). The state is read into locals `y_i`, the right-hand sides
# see them (and `time`), and the result is written back: to the variables, or with `scratch`
# (several solver groups, or reads of other cells' unknowns: `_ode_scratch`) to `x__ode`,
# where an empty cell slot copies its value through so the whole-array publish is exact.
function _cell_ode_expr(c::CompiledPottsSystem, T, dt, odes, solver; scratch = false)
    rn = c.gather_names
    ys, locals, bind = _ode_locals(odes)
    env = _cell_env(T, :c, rn; mcs = :mcs, key = :key, extra = (bind..., :time => :tt))
    names = [info(x).name for (x, _) in odes]
    outs = scratch ? _ode_scratch_name.(names) : names
    body = _ode_steps(solver, T, dt, ys, [lower(_substitute_locals(rate, locals), env) for (_, rate) in odes])
    live = scratch ? :(if !(@inbounds st.cell.volume[c] > 0)
                         $([:(@inbounds st.cell.$(outs[i])[c] = st.cell.$(names[i])[c]) for i in eachindex(ys)]...)
                         return nothing
                     end) : :(@inbounds st.cell.volume[c] > 0 || return nothing)
    return :((st, p, ctx, key, mcs, c) -> begin
        $live
        $([:($(ys[i]) = $T(@inbounds st.cell.$(names[i])[c])) for i in eachindex(ys)]...)
        $body
        $([:(@inbounds st.cell.$(outs[i])[c] = $(ys[i])) for i in eachindex(ys)]...)
        return nothing
    end)
end

# Model ODEs (`D(x) ~ rhs` on model variables): the same fixed-step solver, one work item.
function _model_ode_expr(c::CompiledPottsSystem, T, dt, odes, solver; scratch = false)
    ys, locals, bind = _ode_locals(odes)
    env = _model_env(T, c.gather_names; key = :key, extra = (bind..., :time => :tt))
    names = [info(x).name for (x, _) in odes]
    outs = scratch ? _ode_scratch_name.(names) : names
    body = _ode_steps(solver, T, dt, ys, [lower(_substitute_locals(rate, locals, :model), env) for (_, rate) in odes])
    return :((st, p, ctx, key, mcs) -> begin
        $([:($(ys[i]) = $T(@inbounds st.model.$(names[i])[1])) for i in eachindex(ys)]...)
        $body
        $([:(@inbounds st.model.$(outs[i])[1] = $(ys[i])) for i in eachindex(ys)]...)
        return nothing
    end)
end

# Adaptive host integration (`ode_solver = Adaptive(alg)`, or a `solvers` entry): an in-place
# SciML right-hand side `f!(du, u, (st, p, ctx, mcs, c), t)` from the same lowered rates of
# the ODEs `odes` of that solver, and a phase that keeps one integrator (created on first
# use) and re-initializes it per cell / per MCS.
function _adaptive_phase(c::CompiledPottsSystem, T, dt, scope, odes, solver; scratch = false, sync = true)
    ys, locals, bind = _ode_locals(odes)
    env = scope === :cell ? _cell_env(T, :c, c.gather_names; mcs = :mcs, extra = (bind..., :time => :tt)) :
          _model_env(T, c.gather_names; extra = (bind..., :time => :tt))
    rates = [lower(_substitute_locals(rate, locals, scope), env) for (_, rate) in odes]
    f = _rgf(:((du, u, P, tt) -> begin
        (st, p, ctx, mcs, c) = P
        $([:($(ys[i]) = u[$i]) for i in eachindex(ys)]...)
        $([:(du[$i] = $(rates[i])) for i in eachindex(ys)]...)
        return nothing
    end))
    names = [info(x).name for (x, _) in odes]
    return _AdaptiveODE(f, solver.alg, solver.kwargs, names, scratch ? _ode_scratch_name.(names) : names, scope, T,
        Float64(dt), _state_reads(rates), sync, Dict{UInt, Tuple{WeakRef, Any}}(), ReentrantLock())
end

# The state leaves generated host code reads (D-092): `nothing` when it uses the state in a
# way this scan does not follow (then the caller copies everything), else the leaves as
# `(; σ, cell, site, model, history)` (Bool and tuples of names). It follows `st.σ`,
# `st.<part>.<name>`, `alias.<name>` for `alias` bound to `st.cell` (a `HostPhase` body's
# `cell`), the cell helpers below given the whole cell state, and `Potts._cellkind` /
# `CorePotts.owner_kind`. `length`/`size` of a leaf read only its shape (not a read).
const _CELL_HELPER_READS = Dict{String, Tuple{Vararg{Symbol}}}(
    "CorePotts.centroid_distance" => (:volume, :anchor, :m1), "CorePotts.centroid" => (:volume, :anchor, :m1),
    "CorePotts.centroid_position" => (:volume, :anchor, :m1), "Potts._centroid_axis" => (:volume, :anchor, :m1),
    "Potts._displacement_axis" => (:volume, :anchor, :m1), "CorePotts.major_length" => (:volume, :m1, :m2),
    "CorePotts.cluster_of" => (:cluster,))
function _state_reads(exprs; alias::Union{Nothing, Symbol} = nothing)
    σ = Ref(false)
    whole = Ref(false)
    parts = Dict(p => Set{Symbol}() for p in (:cell, :site, :model, :history))
    iscell(x) = x == :(st.cell) || (alias !== nothing && x === alias)
    function leaf(x)                  # (part, name) of a leaf access, or nothing
        x isa Expr && x.head === :. && length(x.args) == 2 && x.args[2] isa QuoteNode || return nothing
        a, n = x.args[1], x.args[2].value
        a === :st && n === :σ && return (:σ, :σ)
        iscell(a) && return (:cell, n)
        a isa Expr && a.head === :. && a.args[1] === :st && a.args[2] isa QuoteNode && a.args[2].value in keys(parts) &&
            return (a.args[2].value, n)
        return nothing
    end
    function visit(x)
        whole[] && return
        if x === :st || (alias !== nothing && x === alias)
            whole[] = true
        elseif x isa Expr
            l = leaf(x)
            if l !== nothing
                l[1] === :σ ? (σ[] = true) : push!(parts[l[1]], l[2])
            elseif iscell(x)
                whole[] = true
            elseif x.head === :. && any(p -> x == Expr(:., :st, QuoteNode(p)), keys(parts))
                whole[] = true                          # a whole part passed somewhere
            elseif x.head === :call && x.args[1] in (:length, :size) && length(x.args) >= 2 && leaf(x.args[2]) !== nothing
                foreach(visit, x.args[3:end])           # the shape only
            elseif x.head === :call && string(x.args[1]) in ("Potts._cellkind", "CorePotts.owner_kind") &&
                   length(x.args) >= 2 && x.args[2] === :st
                push!(parts[:cell], :kind)
                string(x.args[1]) == "CorePotts.owner_kind" && (σ[] = true)
                foreach(visit, x.args[3:end])
            elseif x.head === :call && haskey(_CELL_HELPER_READS, string(x.args[1]))
                for a in x.args[2:end]
                    iscell(a) ? union!(parts[:cell], _CELL_HELPER_READS[string(x.args[1])]) : visit(a)
                end
            else
                foreach(visit, x.args)
            end
        end
        return
    end
    foreach(visit, exprs)
    whole[] && return nothing
    sorted(p) = Tuple(sort!(collect(parts[p])))
    return (; σ = σ[], cell = sorted(:cell), site = sorted(:site), model = sorted(:model), history = sorted(:history))
end

# One SciML integrator per trajectory, keyed by the identity of its live state array (held
# weakly; ensembles run trajectories concurrently through the same phase object), rebuilt if
# the parameter-tuple type changes (another algorithm, backend or relation set).
struct _AdaptiveODE{F, A, K, R}
    f::F
    alg::A
    kwargs::K
    names::Vector{Symbol}
    outs::Vector{Symbol}         # where the results go: `names`, or their `x__ode` scratch
    scope::Symbol
    T::Type
    dt::Float64
    reads::R                     # the state leaves the rates read (`_state_reads`; `nothing`: all)
    sync::Bool                   # synchronize first (`false`: right after another host phase,
                                 # which synchronized and enqueued nothing but its copies)
    integrators::Dict{UInt, Tuple{WeakRef, Any}}
    lock::ReentrantLock
end

(ph::_AdaptiveODE)(st, p, ctx, key, mcs, backend) = CorePotts._run_phase(ph, st, p, ctx, key, mcs, backend, nothing)

# `stats`: the integrator's `PottsStats`, counting the host copies (D-085)
function CorePotts._run_phase(ph::_AdaptiveODE, st, p, ctx, key, mcs, backend, stats)
    ph.sync && CorePotts._sync!(stats, backend)
    owner = st.σ                                   # identifies the trajectory
    cpu = backend isa KernelAbstractions.CPU
    host = cpu ? st : _adaptive_host_state(ph, stats, backend, st)
    hp = cpu ? p : CorePotts._adapt_host(stats, p)     # Potts' parameters are isbits: nothing to copy
    hctx = merge(ctx, (; lattice = CorePotts._host_lattice(stats, ctx.lattice)))
    part = ph.scope === :cell ? host.cell : host.model
    arrays = [getfield(part, n) for n in ph.names]
    outs = [getfield(part, n) for n in ph.outs]
    u = zeros(ph.T, length(arrays))
    t0 = mcs * ph.dt
    advance!(P, c) = begin
        integ = lock(() -> _cached_integrator(ph.integrators, owner), ph.lock)
        if integ === nothing || typeof(integ.p) !== typeof(P)
            prob = SciMLBase.ODEProblem{true}(ph.f, copy(u), (t0, t0 + ph.dt), P)
            integ = SciMLBase.init(prob, ph.alg; save_everystep = false, save_start = false, ph.kwargs...)
            lock(() -> _cache_integrator!(ph.integrators, owner, integ), ph.lock)
        else
            integ.p = P                       # before `reinit!`: its initial-dt guess evaluates the rate
            SciMLBase.reinit!(integ, u; t0, tf = t0 + ph.dt, erase_sol = true, reset_dt = true)
        end
        SciMLBase.solve!(integ)
        SciMLBase.successful_retcode(integ.sol) || error("Adaptive ODE integration failed at MCS $mcs" *
                                                         (c == 0 ? "" : " (cell $c)") * ": retcode $(integ.sol.retcode)")
        return integ.u
    end
    if ph.scope === :cell
        for c in 1:length(host.cell.kind)
            if !(host.cell.volume[c] > 0)
                ph.outs != ph.names && foreach(((o, a),) -> o[c] = a[c], zip(outs, arrays))
                continue
            end
            for (i, a) in enumerate(arrays)
                u[i] = a[c]
            end
            v = advance!((host, hp, hctx, mcs, c), c)
            for (i, o) in enumerate(outs)
                o[c] = v[i]
            end
        end
    else
        for (i, a) in enumerate(arrays)
            u[i] = a[1]
        end
        v = advance!((host, hp, hctx, mcs, 0), 0)
        for (i, o) in enumerate(outs)
            o[1] = v[i]
        end
    end
    if !cpu
        dst = ph.scope === :cell ? st.cell : st.model
        foreach(n -> CorePotts._copy!(stats, getfield(dst, n), getfield(part, n)), ph.outs)
    end
    return 0
end

# The host state of an adaptive solve on a device (D-092): the unknowns, the leaves the rates
# read and, for cell ODEs, `volume` (dead cells are skipped) come down; scratch outputs are
# host buffers (every entry is written); every other leaf stays on the device, unread.
function _adaptive_host_state(ph::_AdaptiveODE, stats, backend, st)
    r = ph.reads
    r === nothing && return CorePotts._snapshot(stats, backend, st)
    cell, model = ph.scope === :cell ? ((r.cell..., ph.names..., :volume), r.model) : (r.cell, (r.model..., ph.names...))
    host = CorePotts._host_leaves(stats, st; σ = r.σ, cell = unique(cell), model = unique(model), r.site, r.history)
    fresh = Tuple(n for n in ph.outs if !(n in (ph.scope === :cell ? cell : model)))    # not copied down
    isempty(fresh) && return host
    bufs(nt) = merge(nt, NamedTuple{fresh}(map(n -> CorePotts._host_buffer(getfield(nt, n)), fresh)))
    return ph.scope === :cell ? CorePotts.CPMState(host.σ, bufs(host.cell), host.site, host.model, host.history) :
           CorePotts.CPMState(host.σ, host.cell, host.site, bufs(host.model), host.history)
end

function _cached_integrator(cache, owner)
    e = get(cache, objectid(owner), nothing)
    return e !== nothing && e[1].value === owner ? e[2] : nothing
end
function _cache_integrator!(cache, owner, integ)
    filter!(kv -> kv[2][1].value !== nothing, cache)            # drop finished trajectories
    cache[objectid(owner)] = (WeakRef(owner), integ)
    return integ
end

# The ODE unknowns as local values `y_i` inside the step (Jacobi: every rate sees the state
# at the start of the stage).
function _ode_locals(odes)
    ys = [Symbol(:y_, i) for i in eachindex(odes)]
    locals = Dict{Any, Any}()
    bind = Dict{Symbol, Any}()
    for (i, (x, _)) in enumerate(odes)
        s = _tag(_sym(Symbol(:__y, i)), Info(:builtin, Symbol(:__y, i), nothing, (;)))
        locals[_unwrap(x)] = _unwrap(s)
        bind[Symbol(:__y, i)] = ys[i]
    end
    return ys, locals, bind
end

# The ODE locals replace the current entity's unknowns, but not inside population folds nor
# as the variable of an indexed read: `sum(h for c in cells)` and `h[j]` read the cells'
# stored values (the state at the start of the MCS step, D-029, held over the whole step
# through scratch `x__ode`, P6.0n), not `ncells` copies of this cell's local. The index of
# a read is this cell's expression, so it does see the locals (`w[ifelse(h > 0, id, j)]`
# follows the stepped `h`; `_index_reads!`). A literal `h[id]` is this cell's own
# unknown, so it is the local (`_own_read`). (Model unknowns are one value everywhere, so
# model ODEs substitute inside folds too.)
function _substitute_locals(rate, locals, scope = :cell)
    scope === :model && return Symbolics.substitute(rate, locals; fold = Val(false))
    subs = Dict{Any, Any}(locals)
    foreach(((x, l),) -> subs[_own_read(x)] = l, collect(locals))
    return _substitute_cell(rate, subs)
end

# The indexed reads `at(x, i)` outside population folds whose index `i` holds a local map
# to `at(x, i′)` (`_index_reads!`); one substitution then applies them with the locals. A
# rate without such reads substitutes exactly as before (same code).
function _substitute_cell(x, subs)
    x = _unwrap(x)
    reads = _index_reads!(Dict{Any, Any}(), x, subs)
    return Symbolics.substitute(x, isempty(reads) ? subs : merge(subs, reads); fold = Val(false),
        filterer = _outside_populations)
end
_outside_populations(ex) = !(iscall(ex) && operation(ex) in (population, at)) &&
                           SymbolicUtils.default_substitute_filter(ex)

function _index_reads!(out, x, subs)
    (x isa SymbolicUtils.BasicSymbolic && iscall(x)) || return out
    (haskey(subs, x) || operation(x) === population) && return out
    if operation(x) === at
        v, i = arguments(x)
        j = _substitute_cell(i, subs)
        isequal(j, i) || (out[x] = _unwrap(at(Symbolics.wrap(v), Symbolics.wrap(j))))
        return out
    end
    foreach(a -> _index_reads!(out, a, subs), arguments(x))
    return out
end

# `substeps` fixed steps of a fixed-step `solver` over one MCS (`dt`), on locals `ys`. The
# rates are expanded in place: each rate evaluation (Euler's stage, RK4's four) is the rates
# in a `let` binding `tt` and `ys`, plain code of the phase (D-103, D-104). There is no
# closure path: a `rhs` closure inside a RuntimeGeneratedFunction body is lowered by Julia
# 1.12 to an opaque closure, built on every call with its captures (`st`, `p`, `ctx`, `c`)
# on the heap whenever the compiler does not inline the rate (a gather's loop, a long sum,
# an `ifelse` chain, a Hill term, a population fold): 48–640 B per cell per MCS on the CPU,
# and a Metal compile failure (`jl_new_opaque_closure_jlcall`).
function _ode_steps(solver, T, dt, ys, rates)
    n = length(ys)
    substeps = something(solver.substeps, 1)
    h = :($T($dt / $substeps))
    bindings(t, args) = Expr(:block, :(tt = $t), [:($(ys[i]) = $(args[i])) for i in 1:n]...)
    call(t, args...) = Expr(:let, bindings(t, args), :(($(rates...),)))
    lowerclip = solver isa ExplicitEuler ? solver.lower : nothing
    clip(v) = lowerclip === nothing ? v : :(max($v, $T($lowerclip)))
    step = if solver isa RK4
        k(j) = [Symbol(:k, j, :_, i) for i in 1:n]
        quote
            ($(k(1)...),) = $(call(:tt, ys...))
            ($(k(2)...),) = $(call(:(tt + h / 2), [:($(ys[i]) + h / 2 * $(k(1)[i])) for i in 1:n]...))
            ($(k(3)...),) = $(call(:(tt + h / 2), [:($(ys[i]) + h / 2 * $(k(2)[i])) for i in 1:n]...))
            ($(k(4)...),) = $(call(:(tt + h), [:($(ys[i]) + h * $(k(3)[i])) for i in 1:n]...))
            ($(ys...),) = ($([clip(:($(ys[i]) + h / 6 * ($(k(1)[i]) + 2 * $(k(2)[i]) + 2 * $(k(3)[i]) + $(k(4)[i])))) for i in 1:n]...),)
        end
    else
        quote
            ($(Symbol.(:k1_, 1:n)...),) = $(call(:tt, ys...))
            ($(ys...),) = ($([clip(:($(ys[i]) + h * $(Symbol(:k1_, i)))) for i in 1:n]...),)
        end
    end
    return quote
        h = $h
        for s in 1:$substeps
            tt = $T(mcs) * $T($dt) + $T(s - 1) * h
            $step
        end
    end
end

# Discrete components (P6.0k, D-065 Q9): one fused phase per clock and scope, after the ODEs
# and before the links and the lifecycle. Every new value is computed from the pre-tick state
# before any slot is written (Jacobi; a same-step read `x(k)` arrives already substituted by
# `mtkcompile`), for live cells of each component's kinds. With several phases (cell and model
# scope, or several clocks that may tick at the same MCS) every phase first writes scratch
# slots `x__tick`, and the slots are published only after all of them ran, so no block ever
# reads another's post-tick value. A model with a single phase writes its slots directly.
_tick_groups(c::CompiledPottsSystem) = unique((b.scope, b.every, b.offset) for b in c.discrete)
_tick_scratch(c::CompiledPottsSystem) = length(_tick_groups(c)) > 1 || _reads_other_cells_slots(c)

# A cell-scope tick that reads a discrete slot of another cell (`x[j]`, a gather, a fold that is
# not hoisted, a link partner) must not see cells that already ticked: it needs scratch slots
# even in a single phase (review P6.0k round 2). Reads of the cell's own slots do not.
function _reads_other_cells_slots(c::CompiledPottsSystem)
    slots = Set{Symbol}(info(x).name for b in c.discrete if b.scope === :cell for x in b.slots)
    isempty(slots) && return false
    hit = Ref(false)
    reads_slot(y) = (found = Ref(false);
        _walk_all(z -> (i = info(z); i !== nothing && i.role === :cell && i.name in slots && (found[] = true)), y); found[])
    for b in c.discrete, x in b.next
        b.scope === :cell || continue
        _walk_all(x) do y
            hit[] && return
            iscall(y) && operation(y) in (at, at2, gather, population) && reads_slot(y) && (hit[] = true)
        end
    end
    return hit[]
end
_tick_scratch_name(n::Symbol) = Symbol(n, :__tick)

# MTK clock ticks at `t = offset + k·every` MCS happen after MCS `t - 1`: `mcs % every == mod(offset - 1, every)`
_clocked(every, offset, ph) = every == 1 && offset == 0 ? ph : _Gated(every, mod(offset - 1, every), ph)

function _discrete_phases(c::CompiledPottsSystem, T)
    isempty(c.discrete) && return Any[]
    rn = c.gather_names
    scratch = _tick_scratch(c)
    computes = Any[]
    commits = Any[]
    for key in _tick_groups(c)
        scope, every, offset = key
        bs = [b for b in c.discrete if (b.scope, b.every, b.offset) == key]
        if scope === :cell
            used = Set(n for b in bs for x in b.next for (r, n) in _uses(x) if r === :model)
            pops = [s for s in c.discrete_pops if s.first in used]
            isempty(pops) || push!(computes, _clocked(every, offset, _slots_phase(T, pops, rn)))
            push!(computes, _clocked(every, offset, CorePotts.CellPhase(_rgf(_tick_expr(bs, T, rn, :cell; scratch)))))
        else
            push!(computes, _clocked(every, offset, CorePotts.ModelPhase(_rgf(_tick_expr(bs, T, rn, :model; scratch)))))
        end
        scratch || continue
        for b in bs, x in b.slots
            n = info(x).name
            push!(commits, _clocked(every, offset, CorePotts.CopyPhase((scope, n) => (scope, _tick_scratch_name(n)))))
        end
    end
    return Any[computes..., commits...]
end

function _tick_expr(bs, T, rn, scope; scratch = false)
    env = scope === :cell ? _cell_env(T, :c, rn; mcs = :mcs, key = :key) : _model_env(T, rn; key = :key)
    arr(n) = scope === :cell ? :(st.cell.$n) : :(st.model.$n)
    idx = scope === :cell ? :c : 1
    dst(n) = arr(scratch ? _tick_scratch_name(n) : n)
    body = Any[]
    if scope === :cell
        # a dead cell does not tick (its scratch keeps its value, so publishing leaves it unchanged)
        keep = scratch ? [:(@inbounds $(dst(info(x).name))[c] = $(arr(info(x).name))[c]) for b in bs for x in b.slots] : Any[]
        push!(body, :(@inbounds st.cell.volume[c] > 0 || $(Expr(:block, keep..., :(return nothing)))))
        any(b -> !isempty(b.kinds), bs) && push!(body, :(kc = Potts._cellkind(st, c)))
    end
    writes = Any[]
    for (i, b) in enumerate(bs)
        gated = scope === :cell && !isempty(b.kinds)
        g = Symbol(:g_, i)
        gated && push!(body, :($g = $(_kindtest(:kc, b.kinds))))
        for (j, (x, r)) in enumerate(zip(b.slots, b.next))
            v = Symbol(:v_, i, :_, j)
            n = info(x).name
            a = arr(n)
            new = :(convert(eltype($a), $(lower(r, env))))
            # another kind keeps its value (the component is not instantiated there)
            push!(body, :($v = $(gated ? :($g ? $new : (@inbounds $a[$idx])) : new)))
            push!(writes, :(@inbounds $(dst(n))[$idx] = $v))
        end
    end
    args = scope === :cell ? :((st, p, ctx, key, mcs, c)) : :((st, p, ctx, key, mcs))
    return :($args -> $(Expr(:block, body..., writes..., :(return nothing))))
end

# `@link`/`@unlink` rules: host phases over the contact graph / existing links.
# D-066 boundary (c): each `@link`/`@unlink` host phase first drops every link of a dead
# cell (volume 0, killed by copies), before any condition is evaluated or link created, so
# a stale degree or `linked` never blocks creation and no 0/0 centroid reaches `distance`.
_drop_dead_links() = quote
    for ea in 1:length(cell.kind)
        cell.volume[ea] == 0 && CorePotts.remove_incident!(store, ea)
    end
end

function _link_phases(c::CompiledPottsSystem, T)
    rn = c.gather_names
    out = Any[]
    for r in c.link_rules
        store = _link_store(c, r.relationship, :cell; payloads = true)
        defaults = [Expr(:kw, info(x).name, T(info(x).default)) for x in c.edge_vars[r.relationship]]
        body = if r.action === :unlink
            cond = lower(r.when, _edge_env(T, :ea, :eb, :ek, :ed, rn; mcs = :mcs))
            quote
                store = $store
                $(_drop_dead_links())
                for ea in 1:length(cell.kind), ek in 1:size(store.links, 1)
                    eb = store.links[ek, ea]
                    eb > ea || continue
                    ed = CorePotts.centroid_distance($T, cell, ctx.lattice, ea, eb)
                    $cond && CorePotts.remove_link!(store, ea, eb)
                end
            end
        else
            ab = lower(r.when, LowerEnv(T, :edge, Dict{Symbol, Any}(:a => :ea, :b => :eb, :distance => :ed, :mcs => :mcs), rn))
            ba = lower(r.when, LowerEnv(T, :edge, Dict{Symbol, Any}(:a => :eb, :b => :ea, :distance => :ed, :mcs => :mcs), rn))
            quote
                store = $store
                $(_drop_dead_links())
                g = CorePotts.contact_graph(st.σ, ctx.lattice, ctx.contact, length(cell.kind))
                for ea in 1:length(cell.kind)
                    cell.volume[ea] > 0 || continue
                    for eb in CorePotts.neighbors(g, ea)
                        eb > ea || continue
                        CorePotts.linked(store, ea, eb) && continue
                        ed = CorePotts.centroid_distance($T, cell, ctx.lattice, ea, eb)
                        ($ab || $ba) && CorePotts.add_link!(store, ea, eb; $(defaults...))
                    end
                end
            end
        end
        f = _rgf(:((cell, st, p, ctx, mcs) -> $(Expr(:block, body, :(return nothing)))))
        # D-092: the body writes only its relationship's columns; it reads what the scan finds
        writes = (CorePotts.adjacency_name(r.relationship), (Symbol(:link_, info(x).name) for x in c.edge_vars[r.relationship])...)
        rd = _state_reads((body,); alias = :cell)
        reads = rd === nothing || !all(isempty, (rd.site, rd.model, rd.history)) ? nothing :
                Tuple(n for n in ((rd.σ ? (:σ,) : ())..., rd.cell...) if !(n in writes))
        push!(out, CorePotts.HostPhase(f; every = r.every, reads, writes))
    end
    return out
end


function _site_update_phases(c, T, us, every, rn)
    env = _site_env(T, :i, rn; mcs = :mcs, key = :key)
    names = [info(_unwrap(u.eq.lhs)).name for u in us]
    buffered = any(in(c.scratch), names)
    vals = [:($(Symbol(:v_, j)) = $(lower(u.eq.rhs, env))) for (j, u) in enumerate(us)]
    writes = [begin
        dst = buffered ? Symbol(n, :__next) : n
        :(@inbounds st.site.$dst[i] = $(Symbol(:v_, j)))
    end for (j, n) in enumerate(names)]
    gate = every == 1 ? nothing : :(mcs % $every == 0 || return nothing)
    f = _rgf(:((st, p, ctx, key, mcs, i) -> $(Expr(:block, gate, vals..., writes..., :(return nothing)))))
    phases = Any[CorePotts.SitePhase(f)]
    if buffered
        for n in names
            push!(phases, every == 1 ? CorePotts.CopyPhase((:site, n) => (:site, Symbol(n, :__next))) :
                          _Gated(every, CorePotts.CopyPhase((:site, n) => (:site, Symbol(n, :__next)))))
        end
    end
    return phases
end

"""
A phase that runs only after MCS `mcs` with `mcs % every == offset`: `Every(n)` (offset 0,
MCS 0, n, …) and the clocks of discrete components (`_clocked`).
"""
struct _Gated{P}
    every::Int
    offset::Int
    phase::P
end
_Gated(every::Integer, phase) = _Gated(every, 0, phase)
(g::_Gated{P})(st, p, ctx, key, mcs, backend) where {P} =
    CorePotts._run_phase(g, st, p, ctx, key, mcs, backend, nothing)
CorePotts._run_phase(g::_Gated{P}, st, p, ctx, key, mcs, backend, stats) where {P} =
    mcs % g.every == g.offset ? CorePotts._run_phase(g.phase, st, p, ctx, key, mcs, backend, stats) : 0

_model_env(T, rn; mcs = :mcs, key = nothing, extra = ()) =
    LowerEnv(T, :model, Dict{Symbol, Any}(:mcs => mcs, _draws(key, mcs, 0)..., extra...), rn)

function _model_update_expr(c, T, us, every, rn)
    env = _model_env(T, rn; key = :key)
    vals = [:($(Symbol(:v_, j)) = $(lower(u.eq.rhs, env))) for (j, u) in enumerate(us)]
    writes = [:(@inbounds st.model.$(info(_unwrap(u.eq.lhs)).name)[1] = $(Symbol(:v_, j))) for (j, u) in enumerate(us)]
    gate = every == 1 ? nothing : :(mcs % $every == 0 || return nothing)
    return :((st, p, ctx, key, mcs) -> $(Expr(:block, gate, vals..., writes..., :(return nothing))))
end

function _cell_update_expr(c, T, us, every, rn)
    env = _cell_env(T, :c, rn; mcs = :mcs, key = :key)
    vals = [:($(Symbol(:v_, j)) = $(lower(u.eq.rhs, env))) for (j, u) in enumerate(us)]
    writes = [:(@inbounds st.cell.$(info(_unwrap(u.eq.lhs)).name)[c] = $(Symbol(:v_, j))) for (j, u) in enumerate(us)]
    gate = every == 1 ? nothing : :(mcs % $every == 0 || return nothing)
    return :((st, p, ctx, key, mcs, c) -> $(Expr(:block, gate,
        :(@inbounds st.cell.volume[c] > 0 || return nothing), vals..., writes..., :(return nothing))))
end

# Explicit-Euler substeps from a bound on the diffusion coefficient D (the factor multiplying
# Δ(x)) and a bound k on the reaction's |∂f/∂x| (`_abs_bound`), `CorePotts.stable_substeps`,
# computed from the current parameters every MCS (a `remake(p = …)` keeps the step stable).
# An explicit `substeps = n` is a minimum: an unstable step silently diverges, so the stable
# count wins when it is larger. A coefficient with no bound from the parameters needs `n`.
# Only the field's own `Δ(x)` is its diffusion: `Δ(u)` of another field `u` is a source
# term here (fields are stepped one after another, so `u` is fixed during this step), with
# no part in ∂f/∂x.
function _auto_substeps(x, rate, values, dt, lattice, n = nothing)
    L = _unwrap(Symbolics.variable(:__Lap))
    lap = Dict{Any, Any}()
    xu = _unwrap(x)
    _walk(y -> (iscall(y) && operation(y) === Δ && isequal(_unwrap(arguments(y)[1]), xu) && (lap[y] = L)), rate)
    rate_L = _unwrap(Symbolics.substitute(rate, lap; fold = Val(false)))
    coef = isempty(lap) ? 0 : _unwrap(Symbolics.derivative(Symbolics.wrap(rate_L), Symbolics.wrap(L)))
    _warn_negative_diffusion(x, coef, values)
    h = something(lattice.spacing, ntuple(_ -> 1.0, length(lattice.dims)))
    env = _model_env(Float64, Dict{Any, Symbol}())
    db = _abs_bound(coef, env)
    if db !== nothing
        reaction = isempty(lap) ? rate_L : Symbolics.substitute(rate_L, Dict{Any, Any}(L => 0); fold = Val(false))
        kb = _rate_bound(x, reaction, env)
        if kb === nothing
            nm = info(x).name
            n === nothing && @warn "the substep count of the field `$nm` counts diffusion only: no bound on the " *
                                   "reaction's rate ∂f/∂$nm follows from the parameters (it is not linear in `$nm`, " *
                                   "or its coefficient of `$nm` reads other state such as variables or `mcs`). If the " *
                                   "reaction is fast, give `ExplicitEuler(; substeps = n)` with " *
                                   "`n ≥ mcs_duration · (D · Σ 4/h² + max|∂f/∂$nm|) / 1.8`."
            kb = 0.0
        end
        least = something(n, 1)
        return _rgf(:(p -> max($least, CorePotts.stable_substeps($db, $(Float64(dt)), $h, $kb))))
    end
    n === nothing || return n
    throw(ArgumentError("the diffusion coefficient of `$(info(x).name)` ($coef) is not bounded by the parameters; " *
                        "give `PottsProblem` `field_solver = ExplicitEuler(; substeps = n)` " *
                        "(or `solvers = [$(info(x).name) => ExplicitEuler(; substeps = n)]`)"))
end

# A diffusion coefficient below zero is anti-diffusion: the continuum problem is ill-posed
# (every short wavelength grows), whatever the step. Warned at build time from the values the
# problem is built with, for a parameter expression or a kind table `D[kind]`.
function _warn_negative_diffusion(x, coef, values)
    values === nothing && return
    neg = false
    if _param_only(coef)
        w = _unwrap(Symbolics.substitute(coef, values; fold = Val(true)))
        w = SymbolicUtils.isconst(w) ? SymbolicUtils.unwrap_const(w) : w
        neg = w isa Real && w < 0
    elseif iscall(coef) && (operation(coef) === at || operation(coef) === at2)
        i = info(_unwrap(arguments(coef)[1]))
        if i !== nothing && i.role === :kindtable
            v = get(values, _unwrap(arguments(coef)[1]), nothing)
            neg = v isa AbstractArray{<:Real} && any(<(0), v)
        end
    end
    neg && @warn "the diffusion coefficient of the field `$(info(x).name)` ($coef) is negative: that is " *
                 "anti-diffusion, an ill-posed problem whose short wavelengths grow without bound; " *
                 "no substep count makes it stable"
    return
end

# A host expression (in `p`) bounding |∂f/∂x| over every site and state, for the field's
# reaction `f` (the rate without its diffusion term), or `nothing` when no bound follows from
# the parameters alone (a reaction nonlinear in `x`, or a rate scaled by other state). For a
# reaction linear in `x` the derivative is a parameter expression, possibly weighted by
# indicators (`kind == medium`, `position[1] > 75`, each in {0, 1}), draws (`rand()`, in
# (0, 1)) and kind-table entries (`δ[kind]`, bounded by the largest |entry|): `−k x`,
# `−k x (kind == medium)` and `−k x rand()` are bounded by |k|.
function _rate_bound(x, reaction, env)
    d = try
        _unwrap(Symbolics.derivative(Symbolics.wrap(reaction), Symbolics.wrap(x)))
    catch
        return nothing
    end
    return _abs_bound(d, env)
end

const _INDICATOR_OPS = (==, !=, <, <=, >, >=, !, &, |, xor)
# operations a parameter-only expression may use (evaluated on the host from `p`)
const _HOST_OPS = (_FLOAT_OPS..., +, -, *, ^, abs, min, max, ifelse, _INDICATOR_OPS...)

"""Whether `x` reads only parameters and constants through plain arithmetic."""
function _param_only(x)
    ok = Ref(true)
    _walk(x) do y
        i = info(y)
        if i !== nothing
            i.role === :param || (ok[] = false)
        elseif iscall(y)
            operation(y) in _HOST_OPS || (ok[] = false)
        else
            SymbolicUtils.isconst(y) || (ok[] = false)
        end
    end
    return ok[]
end

function _abs_bound(d, env)
    d = _unwrap(d)
    d isa SymbolicUtils.BasicSymbolic || return d isa Real ? Float64(abs(d)) : nothing
    SymbolicUtils.isconst(d) && return _abs_bound(SymbolicUtils.unwrap_const(d), env)
    _param_only(d) && return :(abs(Float64($(lower(d, env)))))
    iscall(d) || return nothing
    op, args = operation(d), arguments(d)
    op in _INDICATOR_OPS && return 1.0
    op === random_uniform && return 1.0                       # a draw, uniform in (0, 1)
    if op === at || op === at2                                # a kind-table entry: the largest |entry|
        i = info(_unwrap(args[1]))
        return i !== nothing && i.role === :kindtable ? :(Float64(maximum(abs, p.$(i.name)))) : nothing
    end
    if op === ifelse
        a, b = _abs_bound(args[2], env), _abs_bound(args[3], env)
        return a === nothing || b === nothing ? nothing : :(max($a, $b))
    end
    if op === (/) && _param_only(args[2])
        a = _abs_bound(args[1], env)
        return a === nothing ? nothing : :($a / abs(Float64($(lower(args[2], env)))))
    end
    if op === (^) && SymbolicUtils.isconst(_unwrap(args[2]))
        e = SymbolicUtils.unwrap_const(_unwrap(args[2]))
        (e isa Real && isinteger(e) && e >= 0) || return nothing
        a = _abs_bound(args[1], env)
        return a === nothing ? nothing : :($a^$(Int(e)))
    end
    (op === (+) || op === (-) || op === (*)) || return nothing
    bs = map(a -> _abs_bound(a, env), args)
    any(isnothing, bs) && return nothing
    return Expr(:call, op === (*) ? :* : :+, bs...)
end

# ---------------------------------------------------------------------------------------
# Lifecycle

# Rule cadences (P6.0f). Every lifecycle rule has its own `Every(n)`: it is checked at MCS
# where `mcs % n == 0`. The whole lifecycle pass runs every `g = gcd(n…)` MCS
# (`Lifecycle.every`: the other MCS skip the trigger kernel and its host sync), and a rule
# whose `n` is not `g` is gated inside the trigger by `_cadence_gate`. A model whose rules
# share one cadence (the default `Every(1)` included) generates no modulo gate at all.
# Future lifecycle rules (`@remove`, `@transition`) that join the trigger take the same path:
# include their cadence in `_lifecycle_every` and prefix their test with `_gated`.
_lifecycle_every(rules) = isempty(rules) ? 1 : gcd((r.every for r in rules)...)
_cadence_gate(n, g) = n == g ? nothing : :(mcs % $n == 0)
_gated(gate, test) = gate === nothing ? test : :($gate && $test)

# Two rules of one domain that can fire for the same cell (their kinds overlap): only the
# rule that fired may run its daughter state rule, so the trigger reports which one it was
# (`CorePotts.ruled_event`) and the state rules take its index. The first matching rule
# (in model order) wins, its division and its state. Models without such overlaps generate
# plain events and kind-gated state rules (no rule index at all).
function _overlapping_rules(divisions)
    for (i, a) in enumerate(divisions), b in divisions[(i + 1):end]
        typeof(a.domain) == typeof(b.domain) && _kinds_overlap(a.domain, b.domain) && return true
    end
    return false
end

# The trigger: the event of cell `c` (the first rule that fires)
function _trigger_expr(c::CompiledPottsSystem, T)
    rn = c.gather_names
    env = _cell_env(T, :c, rn; mcs = :mcs, key = :key)
    g = _lifecycle_every(c.divisions)
    ruled = _overlapping_rules(c.divisions)
    event(e, i) = ruled ? :(CorePotts.ruled_event($e, $i)) : e
    # each rule divides by its own domain (P6.0a): cells(k…) → the cell alone, clusters(k…) →
    # the whole cluster of the root (only the root's rule fires; compile.jl keeps kinds disjoint)
    tests = map(enumerate(c.divisions)) do (i, d)
        gate = _cadence_gate(d.every, g)
        if d.domain isa ClusterDomain
            _gated(gate, :(CorePotts.cluster_of(st.cell, c) == c && $(_kindtest(:(Potts._cellkind(st, c)), d.domain.kinds)) &&
                           $(lower(d.when, env)) && return $(event(:(CorePotts.EVENT_DIVIDE_CLUSTER), i))))
        else
            _gated(gate, :($(_kindtest(:(Potts._cellkind(st, c)), d.domain.kinds)) && $(lower(d.when, env)) &&
                           return $(event(:(CorePotts.EVENT_DIVIDE), i))))
        end
    end
    return :((st, p, ctx, key, mcs, c) -> $(Expr(:block, tests..., :(return CorePotts.EVENT_NONE))))
end

function _lifecycle(c::CompiledPottsSystem, T)
    isempty(c.divisions) && return nothing
    rn = c.gather_names
    trigger = _rgf(_trigger_expr(c, T))
    g = _lifecycle_every(c.divisions)
    ruled = _overlapping_rules(c.divisions)
    ids = eachindex(c.divisions)
    cellids = filter(i -> c.divisions[i].domain isa CellDomain, ids)
    clusterids = filter(i -> c.divisions[i].domain isa ClusterDomain, ids)
    return CorePotts.Lifecycle(trigger; normal = _division_normal(c.divisions[cellids], T),
        cluster_normal = _division_normal(c.divisions[clusterids], T),
        divide! = _division_rules(c, cellids, T, :parent, ruled),
        cluster_divide! = _division_rules(c, clusterids, T, :(CorePotts.cluster_of(st.cell, parent)), ruled),
        every = g, rules = ruled)
end

# the plane of one domain's divisions (the rules of a domain share it)
function _division_normal(divisions, T)
    isempty(divisions) && return CorePotts.AlongMinorAxis{T}()
    alongs = unique(d -> d.along isa Tuple ? ("tuple", d.along) : typeof(d.along), divisions)
    length(alongs) == 1 || throw(ArgumentError("divisions of one domain with different planes are not supported yet"))
    along = divisions[1].along
    return along isa AlongMinor ? CorePotts.AlongMinorAxis{T}() :
           along isa AlongMajor ? CorePotts.AlongMajorAxis{T}() :
           along isa AlongRandom ? CorePotts.RandomPlane{T}() :
           _rgf(:((st, p, ctx, key, mcs, c) -> $(Expr(:tuple, map(v -> T(v), along)...))))
end

# daughter state rules of one domain (the rules `ids` of the model). Each runs for the rule
# that fired: gated by its kinds (the parent's kind for cell divisions, the kind of the
# parent's cluster root `who` for cluster divisions), which identify the rule when no two
# rules of a domain share a kind; else (`ruled`) by the firing rule's index `rule`.
function _division_rules(c::CompiledPottsSystem, ids, T, who, ruled)
    rn = c.gather_names
    rules = Any[]
    for i in ids
        d = c.divisions[i]
        block = Any[]
        for (x, r) in d.rules
            name = info(x).name
            role(x) === :cell || throw(ArgumentError("division rules set cell variables; `$name` is $(role(x))"))
            if r isa Split
                push!(block, :(@inbounds st.cell.$name[parent] /= 2), :(@inbounds st.cell.$name[daughter] = st.cell.$name[parent]))
            else
                v = lower(r, _cell_env(T, :parent, rn; mcs = :mcs, key = :key))
                push!(block, :(v = $v), :(@inbounds st.cell.$name[parent] = v), :(@inbounds st.cell.$name[daughter] = v))
            end
        end
        test = ruled ? :(rule == $i) : _kindtest(:(Potts._cellkind(st, $who)), d.domain.kinds)
        isempty(block) || push!(rules, Expr(:&&, test, Expr(:block, block...)))
    end
    isempty(rules) && return CorePotts.no_divide_rule
    args = ruled ? :((st, p, ctx, key, mcs, parent, daughter, rule)) : :((st, p, ctx, key, mcs, parent, daughter))
    return _rgf(:($args -> $(Expr(:block, rules..., :(return nothing)))))
end

# ---------------------------------------------------------------------------------------
# Total energy (host, brute force): the self-check of the derived ΔH. A dead cell leaves H
# (D-066 item 4, D-083): cell terms sum over alive cells, cluster terms over roots of
# clusters with an alive member, edge terms over links with two alive ends.

# the cell terms of one model, summed per kind group
function _cell_term_groups(c::CompiledPottsSystem)
    groups = Dict{Vector{Int}, Any}()
    for (kinds, E) in c.cell_terms
        groups[kinds] = haskey(groups, kinds) ? groups[kinds] + E : E
    end
    return _sorted(groups)
end

# `live[r]`: cluster root `r` has an alive member (one pass over the slots)
_live_roots_expr() = quote
    live = falses(length(st.cell.kind))
    for m in 1:length(st.cell.kind)
        rm = st.cell.cluster[m]
        (rm > 0 && st.cell.volume[m] > 0) && (live[rm] = true)
    end
end

function _total_energy_expr(c::CompiledPottsSystem, T)
    rn = c.gather_names
    body = Any[:(H = zero($T))]
    for (kinds, E) in _cell_term_groups(c)
        env = _cell_env(T, :c, rn; kind = :k)
        push!(body, quote
            for c in 1:length(st.cell.kind)           # alive cells only: a dead cell leaves H
                st.cell.volume[c] > 0 || continue
                k = Potts._cellkind(st, c)
                $(_kindtest(:k, kinds)) && (H += $(lower(E, env)))
            end
        end)
    end
    cterms = _sorted(_group_terms(c.cluster_terms))
    isempty(cterms) || push!(body, _live_roots_expr())
    for (kinds, E) in cterms
        e = lower(E, _cluster_env(T, :r, rn))
        push!(body, quote
            for r in 1:length(st.cell.kind)           # roots of clusters with an alive member
                (st.cell.cluster[r] == r && live[r]) || continue
                $(_kindtest(:(Potts._cellkind(st, r)), kinds)) && (H += $e)
            end
        end)
    end
    for (rel, E) in _sorted(c.contact_terms)
        R = rel === :contact ? :(ctx.contact) : :(ctx.$rel)
        e = lower(E, _contact_env(T, :a, :ka, :n, :kn, :w, :i, :j, rn))
        push!(body, quote
            for i in 1:length(st.σ)
                a = st.σ[i]
                ka = Potts._cellkind(st, a)
                x = CorePotts.coordinates(ctx.lattice, i)
                for kk in 1:length($R)
                    ins, y = CorePotts.shift(ctx.lattice, x, $R.offsets[kk])
                    ins || continue
                    j = CorePotts.linear_index(ctx.lattice, y)
                    n = st.σ[j]
                    n == a && continue
                    w = CorePotts.weight($R, kk)
                    kn = Potts._cellkind(st, n)
                    H += $e / 2
                end
            end
        end)
    end
    for (r, E) in _edge_energies(c)
        Ecode = lower(E, _edge_env(T, :ea, :eb, :ek, :ed, rn))
        L = _adjacency(r)
        push!(body, quote
            for ea in 1:length(st.cell.kind), ek in 1:size($L, 1)
                eb = $L[ek, ea]
                eb > ea || continue
                (st.cell.volume[ea] > 0 && st.cell.volume[eb] > 0) || continue   # both ends alive (D-066 item 5)
                ed = CorePotts.centroid_distance($T, st.cell, ctx.lattice, ea, eb)
                H += $Ecode
            end
        end)
    end
    for E in c.site_terms
        e = lower(E, _site_env(T, :i, rn))
        push!(body, :(for i in 1:length(st.σ)
            H += $e
        end))
    end
    push!(body, :(return H))
    return :((st, p, ctx) -> $(Expr(:block, body...)))
end

# The energy that leaves H when slot `o` dies, evaluated in `st` (the state after its death):
# o's cell terms, plus its cluster's terms when that cluster has no alive member left. A
# killing copy's ΔH pays the cell (and cluster) term change to the empty state, while H
# drops the dead cell, so ΔH == H(after) − H(before) + this (D-083; edges carry no credit).
# Host, internal: for the self-check helpers (`Potts._killing_credit`).
function _vacated_energy_expr(c::CompiledPottsSystem, T)
    rn = c.gather_names
    body = Any[:(H = zero($T))]
    for (kinds, E) in _cell_term_groups(c)
        push!(body, :($(_kindtest(:(Potts._cellkind(st, c)), kinds)) && (H += $(lower(E, _cell_env(T, :c, rn))))))
    end
    cterms = _sorted(_group_terms(c.cluster_terms))
    if !isempty(cterms)
        push!(body, :(r = st.cell.cluster[c]), _live_roots_expr())
        for (kinds, E) in cterms
            e = lower(E, _cluster_env(T, :r, rn))
            push!(body, :((r > 0 && !live[r] && $(_kindtest(:(Potts._cellkind(st, r)), kinds))) && (H += $e)))
        end
    end
    push!(body, :(return H))
    return :((st, p, ctx, c) -> $(Expr(:block, body...)))
end

struct _VacatedEnergy end     # `PottsModelInfo.cache` key of the compiled `_vacated_energy_expr`

"""
    Potts._killing_credit(prob, u, prop, a)

Self-check credit of copy `prop` from state `u` to state `a`: the energy that leaves
`H` with the cell the copy kills (`prop.old` owned one site), or zero when it kills none, so
that `energy_change(prob, u, prop) == total_energy(prob, a) − total_energy(prob, u) +
credit` for every copy. Internal, host.
"""
function _killing_credit(prob, u, prop, a)
    o = prop.old
    info = prob.f.sys
    (o == 0 || u.cell.volume[o] != 1) && return zero(info.T)
    f = lock(_OBSERVED_LOCK) do
        get!(() -> _rgf(_vacated_energy_expr(info.csys, info.T)), info.cache, _VacatedEnergy())
    end
    return f(a, prob.p, _host_ctx(prob), o)
end
