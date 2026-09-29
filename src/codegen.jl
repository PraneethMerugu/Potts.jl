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

"""Hash of generated code, independent of line numbers and the install path (D-016)."""
_code_hash(exprs, h::UInt = zero(UInt)) =
    foldl((h, ex) -> hash(string(Base.remove_linenums!(deepcopy(ex))), h), exprs; init = h)

# `key`: the RNG key in scope (functions of the MCS phases and lifecycle); enables `rand()`.
_draws(key, mcs, entity) = key === nothing ? () : (:__draw => (key, mcs, entity),)

_cell_env(T, c, relname; kind = :(Potts._cellkind(st, $c)), mcs = nothing, key = nothing, extra = ()) =
    LowerEnv(T, :cell, Dict{Symbol, Any}(_draws(key, mcs, c)..., :volume => :($T(@inbounds st.cell.volume[$c])),
        :surface => :(@inbounds st.cell.surface[$c]), :kind => kind, :id => c,
        :generation => :(@inbounds st.cell.generation[$c]), :__cell => c,
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
    :target => :target, :old => :old, :new => :new, :__kind_of => (:old => :k_old, :new => :k_new)), relname)

_contact_env(T, a, ka, n, kn, w, site, relname) = LowerEnv(T, :contact,
    Dict{Symbol, Any}(:kind => ka, :kind′ => kn, :owner => a, :owner′ => n, :weight => w,
        :__site => site, :__cell => a), relname)

_edge_env(T, a, b, k, d, relname; mcs = nothing) = LowerEnv(T, :edge,
    Dict{Symbol, Any}(:a => a, :b => b, :distance => d, :__edge => (k, a),
        (mcs === nothing ? () : (:mcs => mcs,))...), relname)

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
    for (rel, E) in _sorted(c.contact_terms)
        R = rel === :contact ? :(ctx.contact) : :(ctx.$rel)
        ctxname = rel === :contact ? :contact : rel
        Enew = lower(E, _contact_env(T, :new, :k_new, :n, :k_n, :w, :target, rn))
        Eold = lower(E, _contact_env(T, :old, :k_old, :n, :k_n, :w, :target, rn))
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
                    n = @inbounds st.σ[CorePotts.linear_index(ctx.lattice, y)]
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
    # on-copy writes the energies read (D-045): the state after the copy has them applied
    after, oc_binds, oc_vals = _oncopy_after(c, T, rn)
    append!(body, oc_vals)
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
            env = _cell_env(T, side, rn; kind = k, extra = (:δsurface => δs, oc_binds...))
            push!(terms, :($(_kindtest(k, kinds)) && (dH += $(lower(ΔE, env)))))
        end
        isempty(terms) || push!(body, Expr(:&&, :($side != 0), Expr(:block, terms...)))
    end
    append!(body, _cluster_delta_code(c, T))
    if !isempty(c.edge_terms)
        Ecode = lower(sum(c.edge_terms), _edge_env(T, :ea, :eb, :ek, :ed, rn))
        push!(body, :(dH += CorePotts.link_delta($T, st.cell, ctx, prop, (ea, eb, ek, ed) -> $Ecode)))
    end
    for E in c.site_terms
        after = lower(isempty(after[:target]) ? E : Symbolics.substitute(E, after[:target]; fold = Val(false)),
            LowerEnv(T, :site, Dict{Symbol, Any}(:owner => :new, :kind => :k_new, :__site => :target,
            :position => :(Potts._position($T, ctx, target)), :site => :target, oc_binds...), rn))
        before = lower(E, LowerEnv(T, :site, Dict{Symbol, Any}(:owner => :old, :kind => :k_old, :__site => :target,
            :position => :(Potts._position($T, ctx, target)), :site => :target), rn))
        push!(body, :(dH += $after - $before))
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
local holding its on-copy value, computed as `commit!` will.
"""
function _oncopy_after(c::CompiledPottsSystem, T, rn)
    after = Dict(:new => Dict{Any, Any}(), :old => Dict{Any, Any}(), :target => Dict{Any, Any}())
    binds = Pair{Symbol, Any}[]
    vals = Any[]
    read = Set{Symbol}(n for E in Any[last.(c.cell_terms)..., c.site_terms...] for (r, n) in _uses(E) if r in SCOPES)
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
        elseif k.kind === :connectivity
            push!(tests, :(old == 0 || !$(_kindtest(:k_old, k.kinds)) ||
                           CorePotts.locally_connected(st.σ, ctx, prop)))
        elseif k.kind === :merks_connectivity
            push!(tests, :(old == 0 || !$(_kindtest(:k_old, k.kinds)) ||
                           CorePotts.merks_connectivity(st.σ, ctx, prop)))
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

function _phases(c::CompiledPottsSystem, T, values)
    rn = c.gather_names
    integrals = _integral_phases(c, T)
    before = Any[]; after = Any[]
    # integrals: fresh at every MCS boundary (and at init); refreshed after the sweep too when
    # the after-MCS updates, equations or lifecycle read them
    s = c.sys
    after_reads = Any[(u.eq.rhs for u in s.updates if u.phase === :after_mcs)..., (eq.rhs for eq in s.equations)...,
        (d.when for d in s.divisions)..., (r for d in s.divisions for (_, r) in d.rules if !(r isa Split))...,
        (r.when for r in s.link_rules)...]
    any(x -> _has_op(x, cell_integral), after_reads) && append!(after, integrals)
    # update blocks (D-042): snapshots of previous values, then the ordered stages, each
    # after its hoisted population folds
    for phase in (:before_mcs, :after_mcs)
        dst = phase === :before_mcs ? before : after
        for (scope, n) in c.pre_snapshots[phase]
            push!(dst, CorePotts.CopyPhase((scope, Symbol(n, :__pre)) => (scope, n)))
        end
        for stage in c.schedule[phase]
            if !isempty(stage.pops)
                ph = _slots_phase(T, stage.pops, rn)
                push!(dst, stage.every == 1 ? ph : _Gated(stage.every, ph))
            end
            if stage.scope === :site
                append!(dst, _site_update_phases(c, T, stage.updates, stage.every, rn))
            elseif stage.scope === :model
                push!(dst, CorePotts.ModelPhase(_rgf(_model_update_expr(c, T, stage.updates, stage.every, rn))))
            else
                push!(dst, CorePotts.CellPhase(_rgf(_cell_update_expr(c, T, stage.updates, stage.every, rn))))
            end
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
        sub = c.sys.sweep.field_solver.substeps
        sub === nothing && (sub = _auto_substeps(x, rate, values, dt, c.sys.lattice))
        lowerclip = c.sys.sweep.field_solver.lower
        push!(after, CorePotts.FieldStep((:site, name) => (:site, Symbol(name, :__next)), f;
            dt = T(dt), substeps = sub, lower = lowerclip === nothing ? nothing : T(lowerclip)))
    end
    if c.sys.sweep.ode_solver isa Adaptive
        isempty(c.cell_ode_pops) || push!(after, _slots_phase(T, c.cell_ode_pops, rn))
        isempty(c.cell_odes) || push!(after, _adaptive_phase(c, T, dt, :cell))
        isempty(c.model_odes) || push!(after, _adaptive_phase(c, T, dt, :model))
    else
        isempty(c.cell_ode_pops) || push!(after, _slots_phase(T, c.cell_ode_pops, rn))
        isempty(c.cell_odes) || push!(after, CorePotts.CellPhase(_rgf(_cell_ode_expr(c, T, dt))))
        isempty(c.model_odes) || push!(after, CorePotts.ModelPhase(_rgf(_model_ode_expr(c, T, dt))))
    end
    append!(after, _link_phases(c, T))
    # at the MCS boundary (after the lifecycle): integrals, then history rings take the values
    finish = Any[integrals...]
    for (n, _) in sort!(collect(_history_depths(c.sys)); by = first)
        scope = any(x -> info(x).name === n && info(x).role === :model, c.sys.variables) ? :model : :site
        push!(finish, CorePotts.HistoryPush(n => (scope, n)))
    end
    return CorePotts.Phases(; before_mcs = Tuple(before), after_mcs = Tuple(after), end_mcs = Tuple(finish),
        at_init = (integrals..., snapshots...))
end

"""One model phase computing the population folds `slots` (`name => fold`) into `st.model`."""
function _slots_phase(T, slots, rn)
    env = _model_env(T, rn; key = :key)
    body = [:(@inbounds st.model.$(n)[1] = $T($(lower(x, env)))) for (n, x) in slots]
    return CorePotts.ModelPhase(_rgf(:((st, p, ctx, key, mcs) -> $(Expr(:block, body..., :(return nothing))))))
end

# All cell ODEs (`D(x) ~ f` on cell variables, component equations) advance together, per
# cell, over one MCS of length `dt` with the sweep's `ode_solver` (a batched system over the
# cell dimension: one work item per cell, CPU or GPU). The state is read into locals
# `y_i`, the right-hand sides see them (and `time`), and the result is written back.
function _cell_ode_expr(c::CompiledPottsSystem, T, dt)
    rn = c.gather_names
    ys, locals, bind = _ode_locals(c.cell_odes)
    env = _cell_env(T, :c, rn; mcs = :mcs, key = :key, extra = (bind..., :time => :tt))
    names = [info(x).name for (x, _) in c.cell_odes]
    body = _ode_steps(c.sys.sweep.ode_solver, T, dt, ys, [lower(_substitute_locals(rate, locals), env) for (_, rate) in c.cell_odes])
    return :((st, p, ctx, key, mcs, c) -> begin
        @inbounds st.cell.volume[c] > 0 || return nothing
        $([:($(ys[i]) = $T(@inbounds st.cell.$(names[i])[c])) for i in eachindex(ys)]...)
        $body
        $([:(@inbounds st.cell.$(names[i])[c] = $(ys[i])) for i in eachindex(ys)]...)
        return nothing
    end)
end

# Model ODEs (`D(x) ~ rhs` on model variables): the same fixed-step solver, one work item.
function _model_ode_expr(c::CompiledPottsSystem, T, dt)
    ys, locals, bind = _ode_locals(c.model_odes)
    env = _model_env(T, c.gather_names; key = :key, extra = (bind..., :time => :tt))
    names = [info(x).name for (x, _) in c.model_odes]
    body = _ode_steps(c.sys.sweep.ode_solver, T, dt, ys, [lower(_substitute_locals(rate, locals, :model), env) for (_, rate) in c.model_odes])
    return :((st, p, ctx, key, mcs) -> begin
        $([:($(ys[i]) = $T(@inbounds st.model.$(names[i])[1])) for i in eachindex(ys)]...)
        $body
        $([:(@inbounds st.model.$(names[i])[1] = $(ys[i])) for i in eachindex(ys)]...)
        return nothing
    end)
end

# Adaptive host integration (`ode_solver = Adaptive(alg)`): an in-place SciML right-hand side
# `f!(du, u, (st, p, ctx, mcs, c), t)` from the same lowered rates, and a phase that keeps one
# integrator (created on first use) and re-initializes it per cell / per MCS.
function _adaptive_phase(c::CompiledPottsSystem, T, dt, scope)
    odes = scope === :cell ? c.cell_odes : c.model_odes
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
    solver = c.sys.sweep.ode_solver
    return _AdaptiveODE(f, solver.alg, solver.kwargs, [info(x).name for (x, _) in odes], scope, T, Float64(dt),
        Dict{UInt, Tuple{WeakRef, Any}}(), ReentrantLock())
end

# One SciML integrator per trajectory, keyed by the identity of its live state array (held
# weakly; ensembles run trajectories concurrently through the same phase object), rebuilt if
# the parameter-tuple type changes (another algorithm, backend or relation set).
struct _AdaptiveODE{F, A, K}
    f::F
    alg::A
    kwargs::K
    names::Vector{Symbol}
    scope::Symbol
    T::Type
    dt::Float64
    integrators::Dict{UInt, Tuple{WeakRef, Any}}
    lock::ReentrantLock
end

function (ph::_AdaptiveODE)(st, p, ctx, key, mcs, backend)
    KernelAbstractions.synchronize(backend)
    owner = st.σ                                   # identifies the trajectory
    cpu = backend isa CorePotts.CPU
    host = cpu ? st : CorePotts._snapshot(backend, st)
    hp = cpu ? p : Adapt.adapt(Array, p)
    hctx = merge(ctx, (; lattice = CorePotts.host_lattice(ctx.lattice)))
    part = ph.scope === :cell ? host.cell : host.model
    arrays = [getfield(part, n) for n in ph.names]
    u = zeros(ph.T, length(arrays))
    t0 = mcs * ph.dt
    advance!(P, c) = begin
        integ = lock(() -> _cached_integrator(ph.integrators, owner), ph.lock)
        if integ === nothing || typeof(integ.p) !== typeof(P)
            prob = SciMLBase.ODEProblem{true}(ph.f, copy(u), (t0, t0 + ph.dt), P)
            integ = SciMLBase.init(prob, ph.alg; save_everystep = false, save_start = false, ph.kwargs...)
            lock(() -> _cache_integrator!(ph.integrators, owner, integ), ph.lock)
        else
            SciMLBase.reinit!(integ, u; t0, tf = t0 + ph.dt, erase_sol = true, reset_dt = true)
            integ.p = P
        end
        SciMLBase.solve!(integ)
        SciMLBase.successful_retcode(integ.sol) || error("Adaptive ODE integration failed at MCS $mcs" *
                                                         (c == 0 ? "" : " (cell $c)") * ": retcode $(integ.sol.retcode)")
        return integ.u
    end
    if ph.scope === :cell
        for c in 1:length(host.cell.kind)
            host.cell.volume[c] > 0 || continue
            for (i, a) in enumerate(arrays)
                u[i] = a[c]
            end
            v = advance!((host, hp, hctx, mcs, c), c)
            for (i, a) in enumerate(arrays)
                a[c] = v[i]
            end
        end
    else
        for (i, a) in enumerate(arrays)
            u[i] = a[1]
        end
        v = advance!((host, hp, hctx, mcs, 0), 0)
        for (i, a) in enumerate(arrays)
            a[1] = v[i]
        end
    end
    if !cpu
        dst = ph.scope === :cell ? st.cell : st.model
        foreach(n -> copyto!(getfield(dst, n), getfield(part, n)), ph.names)
    end
    return 0
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

# The ODE locals replace the current entity's unknowns, but not inside population folds:
# `sum(h for c in cells)` reads every cell's stored value (the state at the start of the MCS
# step, D-029), not `ncells` copies of this cell's local.
# (Model unknowns are one value everywhere, so model ODEs substitute inside folds too.)
_substitute_locals(rate, locals, scope = :cell) = scope === :model ?
    Symbolics.substitute(rate, locals; fold = Val(false)) :
    Symbolics.substitute(rate, locals; fold = Val(false), filterer = _outside_populations)
_outside_populations(ex) = !(iscall(ex) && operation(ex) === population) &&
                           SymbolicUtils.default_substitute_filter(ex)

# `substeps` fixed steps of the sweep's `ode_solver` over one MCS (`dt`), on locals `ys`.
function _ode_steps(solver, T, dt, ys, rates)
    n = length(ys)
    substeps = something(solver.substeps, 1)
    h = :($T($dt / $substeps))
    f = :(rhs = (tt, $(ys...)) -> ($(rates...),))
    lowerclip = solver isa ExplicitEuler ? solver.lower : nothing
    clip(v) = lowerclip === nothing ? v : :(max($v, $T($lowerclip)))
    step = if solver isa RK4
        k(j) = [Symbol(:k, j, :_, i) for i in 1:n]
        quote
            ($(k(1)...),) = rhs(tt, $(ys...))
            ($(k(2)...),) = rhs(tt + h / 2, $([:($(ys[i]) + h / 2 * $(k(1)[i])) for i in 1:n]...))
            ($(k(3)...),) = rhs(tt + h / 2, $([:($(ys[i]) + h / 2 * $(k(2)[i])) for i in 1:n]...))
            ($(k(4)...),) = rhs(tt + h, $([:($(ys[i]) + h * $(k(3)[i])) for i in 1:n]...))
            ($(ys...),) = ($([clip(:($(ys[i]) + h / 6 * ($(k(1)[i]) + 2 * $(k(2)[i]) + 2 * $(k(3)[i]) + $(k(4)[i])))) for i in 1:n]...),)
        end
    else
        quote
            ($(Symbol.(:k1_, 1:n)...),) = rhs(tt, $(ys...))
            ($(ys...),) = ($([clip(:($(ys[i]) + h * $(Symbol(:k1_, i)))) for i in 1:n]...),)
        end
    end
    return quote
        h = $h
        $f
        for s in 1:$substeps
            tt = $T(mcs) * $T($dt) + $T(s - 1) * h
            $step
        end
    end
end

# `@link`/`@unlink` rules: host phases over the contact graph / existing links.
function _link_phases(c::CompiledPottsSystem, T)
    rn = c.gather_names
    out = Any[]
    defaults = [Expr(:kw, info(x).name, T(info(x).default)) for x in c.sys.variables if info(x).role === :edge]
    for r in c.link_rules
        body = if r.action === :unlink
            cond = lower(r.when, _edge_env(T, :ea, :eb, :ek, :ed, rn; mcs = :mcs))
            quote
                for ea in 1:length(cell.kind), ek in 1:size(cell.links, 1)
                    eb = cell.links[ek, ea]
                    eb > ea || continue
                    ed = CorePotts.centroid_distance($T, cell, ctx.lattice, ea, eb)
                    $cond && CorePotts.remove_link!(cell, ea, eb)
                end
            end
        else
            ab = lower(r.when, LowerEnv(T, :edge, Dict{Symbol, Any}(:a => :ea, :b => :eb, :distance => :ed, :mcs => :mcs), rn))
            ba = lower(r.when, LowerEnv(T, :edge, Dict{Symbol, Any}(:a => :eb, :b => :ea, :distance => :ed, :mcs => :mcs), rn))
            quote
                g = CorePotts.contact_graph(st.σ, ctx.lattice, ctx.contact, length(cell.kind))
                for ea in 1:length(cell.kind)
                    cell.volume[ea] > 0 || continue
                    for eb in CorePotts.neighbors(g, ea)
                        eb > ea || continue
                        CorePotts.linked(cell, ea, eb) && continue
                        ed = CorePotts.centroid_distance($T, cell, ctx.lattice, ea, eb)
                        ($ab || $ba) && CorePotts.add_link!(cell, ea, eb; $(defaults...))
                    end
                end
            end
        end
        f = _rgf(:((cell, st, p, ctx, mcs) -> $(Expr(:block, body, :(return nothing)))))
        push!(out, CorePotts.HostPhase(f; every = r.every))
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

"""A phase that runs only every `every` MCS."""
struct _Gated{P}
    every::Int
    phase::P
end
(g::_Gated{P})(st, p, ctx, key, mcs, backend) where {P} =
    mcs % g.every == 0 ? g.phase(st, p, ctx, key, mcs, backend) : 0

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

# Explicit-Euler substeps from the diffusion coefficient (the factor multiplying Δ(x)),
# computed from the current parameters every MCS (a `remake(p = …)` keeps the step stable).
# A coefficient that varies in space is taken at its build-time value where constant.
function _auto_substeps(x, rate, values, dt, lattice)
    L = _unwrap(Symbolics.variable(:__Lap))
    lap = Dict{Any, Any}()
    _walk(y -> (iscall(y) && operation(y) === Δ && (lap[y] = L)), rate)
    isempty(lap) && return 1
    coef = _unwrap(Symbolics.derivative(Symbolics.substitute(rate, lap; fold = Val(false)), Symbolics.wrap(L)))
    h = something(lattice.spacing, ntuple(_ -> 1.0, length(lattice.dims)))
    if all(u -> first(u) === :param, _uses(coef))
        body = lower(coef, _model_env(Float64, Dict{Any, Symbol}()))
        return _rgf(:(p -> CorePotts.stable_substeps(abs(Float64($body)), $(Float64(dt)), $h)))
    end
    throw(ArgumentError("the diffusion coefficient of `$(info(x).name)` ($coef) is not a parameter expression; " *
                        "set `field_solver = ExplicitEuler(; substeps = n)` explicitly"))
end

# ---------------------------------------------------------------------------------------
# Lifecycle

function _lifecycle(c::CompiledPottsSystem, T)
    isempty(c.divisions) && return nothing
    rn = c.gather_names
    alongs = unique(d -> d.along isa Tuple ? ("tuple", d.along) : typeof(d.along), c.divisions)
    length(alongs) == 1 || throw(ArgumentError("divisions with different planes are not supported yet"))
    env = _cell_env(T, :c, rn; mcs = :mcs, key = :key)
    tests = [:($(_kindtest(:(Potts._cellkind(st, c)), d.domain.kinds)) && $(lower(d.when, env)) && return CorePotts.EVENT_DIVIDE)
             for d in c.divisions]
    trigger = _rgf(:((st, p, ctx, key, mcs, c) -> $(Expr(:block, tests..., :(return CorePotts.EVENT_NONE)))))
    along = c.divisions[1].along
    normal = along isa AlongMinor ? CorePotts.AlongMinorAxis{T}() :
             along isa AlongMajor ? CorePotts.AlongMajorAxis{T}() :
             along isa AlongRandom ? CorePotts.RandomPlane{T}() :
             _rgf(:((st, p, ctx, key, mcs, c) -> $(Expr(:tuple, map(v -> T(v), along)...))))
    rules = Any[]
    for d in c.divisions
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
        # each division's rules apply to its own kinds (the parent keeps its kind)
        # cluster divisions: every member, gated by the kind of its cluster's root
        who = c.cluster_division ? :(CorePotts.cluster_of(st.cell, parent)) : :parent
        isempty(block) || push!(rules, Expr(:&&, _kindtest(:(Potts._cellkind(st, $who)), d.domain.kinds), Expr(:block, block...)))
    end
    divide! = isempty(rules) ? CorePotts.no_divide_rule :
              _rgf(:((st, p, ctx, key, mcs, parent, daughter) -> $(Expr(:block, rules..., :(return nothing)))))
    return CorePotts.Lifecycle(trigger; normal, divide!, clusters = c.cluster_division)
end

# ---------------------------------------------------------------------------------------
# Total energy (host, brute force): the self-check of the derived ΔH

function _total_energy_expr(c::CompiledPottsSystem, T)
    rn = c.gather_names
    body = Any[:(H = zero($T))]
    groups = Dict{Vector{Int}, Any}()
    for (kinds, E) in c.cell_terms
        groups[kinds] = haskey(groups, kinds) ? groups[kinds] + E : E
    end
    for (kinds, E) in _sorted(groups)
        env = _cell_env(T, :c, rn; kind = :k)
        push!(body, quote
            for c in 1:length(st.cell.kind)           # every slot, empty ones at E(0): consistent with ΔH
                k = Potts._cellkind(st, c)
                $(_kindtest(:k, kinds)) && (H += $(lower(E, env)))
            end
        end)
    end
    for (kinds, E) in _sorted(_group_terms(c.cluster_terms))
        e = lower(E, _cluster_env(T, :r, rn))
        push!(body, quote
            for r in 1:length(st.cell.kind)           # every root (free slots are their own cluster)
                st.cell.cluster[r] == r || continue
                $(_kindtest(:(Potts._cellkind(st, r)), kinds)) && (H += $e)
            end
        end)
    end
    for (rel, E) in _sorted(c.contact_terms)
        R = rel === :contact ? :(ctx.contact) : :(ctx.$rel)
        e = lower(E, _contact_env(T, :a, :ka, :n, :kn, :w, :i, rn))
        push!(body, quote
            for i in 1:length(st.σ)
                a = st.σ[i]
                ka = Potts._cellkind(st, a)
                x = CorePotts.coordinates(ctx.lattice, i)
                for kk in 1:length($R)
                    ins, y = CorePotts.shift(ctx.lattice, x, $R.offsets[kk])
                    ins || continue
                    n = st.σ[CorePotts.linear_index(ctx.lattice, y)]
                    n == a && continue
                    w = CorePotts.weight($R, kk)
                    kn = Potts._cellkind(st, n)
                    H += $e / 2
                end
            end
        end)
    end
    if !isempty(c.edge_terms)
        Ecode = lower(sum(c.edge_terms), _edge_env(T, :ea, :eb, :ek, :ed, rn))
        push!(body, quote
            for ea in 1:length(st.cell.kind), ek in 1:size(st.cell.links, 1)
                eb = st.cell.links[ek, ea]
                eb > ea || continue
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
