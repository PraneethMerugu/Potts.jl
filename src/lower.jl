# Lowering: symbolic expressions → Julia `Expr` reading the CorePotts state.
#
# Generated functions see `st` (CPMState), `p` (parameters NamedTuple), `ctx` (lattice and
# relations) and, per function kind, `prop` or an index. A `LowerEnv` says which built-in
# names are bound in the current mode and to what code; everything else follows the role
# recorded in each symbol's metadata.

using SymbolicUtils: iscall, operation, arguments, issym

const CP = CorePotts

const _FLOAT_OPS = (sqrt, cbrt, exp, exp2, exp10, expm1, log, log2, log10, log1p, sin, cos, tan,
    sinh, cosh, tanh, asin, acos, atan, (/), inv, hypot)

struct LowerEnv
    T::Type                          # scalar type of the generated code
    mode::Symbol                     # :cell, :site, :contact, :proposal
    bind::Dict{Symbol, Any}          # built-in name (or :__site/:__cell) → code
    relname::Dict{Any, Symbol}       # gather relation spec → ctx field
end

const _MODE_NAMES = Dict(:cell => "a cell term (`cells(…) => …`)", :site => "a site term or site update",
    :contact => "a contact term (`contacts => …`)", :model => "a model-scope expression (model update, observed)", :edge => "an edge term or link rule (`edges(rel) => …`, `@link`)", :proposal => "a copy-scoped expression (drive, constraint, on-copy update, temperature)")

_unwrap(x) = Symbolics.unwrap(x)

"""Julia code for the value of symbolic `x` in `env`."""
function lower(x, env::LowerEnv)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return _literal(x, env)
    SymbolicUtils.isconst(x) && return _literal(SymbolicUtils.unwrap_const(x), env)
    i = info(x)
    if i !== nothing && !(i.role in (:bound, :bound_cell, :bound_site))
        return _lower_named(x, i, env)
    end
    if issym(x)
        i === nothing && error("unknown symbol `$x` in $(_MODE_NAMES[env.mode]); declare it in @parameters or @variables")
        return Symbol(nameof(x))                    # a gather's bound site
    end
    op = operation(x)
    args = arguments(x)
    (op === at || op === at2) && return _lower_at(args, env)
    op === gather && return _lower_gather(args, env)
    op === population && return _lower_population(args, env)
    op === Δ && return _lower_laplacian(args[1], env)
    op isa ModelingToolkitBase.Pre && return lower(args[1], env)     # previous value
    op === ifelse && return :($(lower(args[1], env)) ? $(lower(args[2], env)) : $(lower(args[3], env)))
    if op === (^) && SymbolicUtils.isconst(_unwrap(args[2]))
        e = SymbolicUtils.unwrap_const(_unwrap(args[2]))
        if e isa Integer || (e isa Real && isinteger(e))
            return Expr(:call, :^, lower(args[1], env), Int(e))   # literal_pow, no float exponent
        end
    end
    # float-valued functions compute in the model's scalar type (no Float64 from Int args)
    if op in _FLOAT_OPS || op === (^)
        return Expr(:call, op, map(a -> :($(env.T)($(lower(a, env)))), args)...)
    end
    return Expr(:call, op, map(a -> lower(a, env), args)...)
end

function _literal(v, env)
    v isa Bool && return v
    v isa Integer && return v
    v isa Real && return env.T(v)
    v isa Tuple && return Expr(:tuple, map(x -> _literal(x, env), v)...)
    error("cannot lower constant $v")
end

function _lower_named(x, i::Info, env::LowerEnv)
    r = i.role
    r === :param && return :(p.$(i.name))
    r === :kindtable && error("kind table `$(i.name)` must be indexed by kinds, e.g. `$(i.name)[kind, kind′]`")
    if r === :builtin || r === :delta
        key = r === :delta ? Symbol(:δ, i.name) : i.name
        haskey(env.bind, key) || error("`$(i.name)` is not available in $(_MODE_NAMES[env.mode])")
        return env.bind[key]
    end
    if r === :site || r === :field
        haskey(env.bind, :__site) || error("site variable `$(i.name)` needs a site: write `$(i.name)[target]` or `$(i.name)[source]`")
        return :(@inbounds st.site.$(i.name)[$(env.bind[:__site])])
    elseif r === :cell
        haskey(env.bind, :__cell) || error("cell variable `$(i.name)` needs a cell: write `$(i.name)[new]` or `$(i.name)[owner[target]]`")
        return :(Potts._cellval(st.cell.$(i.name), $(env.bind[:__cell])))
    elseif r === :model
        return :(@inbounds st.model.$(i.name)[1])
    elseif r === :edge
        haskey(env.bind, :__edge) || error("edge variable `$(i.name)` is only available in edge terms and link rules")
        k, a = env.bind[:__edge]
        return :(@inbounds st.cell.$(Symbol(:link_, i.name))[$k, $a])
    end
    error("cannot lower `$x` (role $r)")
end

"""Value of a cell array at `c`, zero for the medium (`c == 0`)."""
@inline _cellval(a, c) = c == 0 ? zero(eltype(a)) : @inbounds a[c]
"""Kind of cell `c` (`0` for the medium)."""
@inline _cellkind(st, c) = c == 0 ? Int32(0) : Int32(@inbounds st.cell.kind[c])

# Sort of an index expression: :site or :cell.
function _sort(x)
    x = _unwrap(x)
    i = info(x)
    if i !== nothing
        i.role in (:bound, :bound_site) && return :site
        i.role === :bound_cell && return :cell
        i.role === :builtin && return i.name in (:source, :target) ? :site :
               i.name in (:old, :new, :owner, :owner′, :id, :a, :b) ? :cell : :unknown
    end
    if x isa SymbolicUtils.BasicSymbolic && iscall(x) && operation(x) === at
        a = info(arguments(x)[1])
        a !== nothing && a.role === :builtin && a.name === :owner && return :cell
    end
    return :unknown
end

function _lower_at(args, env)
    x = _unwrap(args[1])
    i = info(x)
    i === nothing && error("cannot index `$x`")
    idx = map(a -> lower(a, env), args[2:end])
    if i.role === :kindtable
        return :(@inbounds p.$(i.name)[$(map(k -> :(Int($k) + 1), idx)...)])
    end
    length(idx) == 1 || error("`$(i.name)` takes one index")
    j = only(idx)
    s = _sort(args[2])
    if i.role === :site || i.role === :field
        s === :cell && error("site variable `$(i.name)` indexed by a cell")
        return :(@inbounds st.site.$(i.name)[$j])
    elseif i.role === :cell
        s === :site && error("cell variable `$(i.name)` indexed by a site; use `$(i.name)[owner[s]]`")
        return :(Potts._cellval(st.cell.$(i.name), $j))
    elseif i.role === :builtin
        i.name === :owner && return :(@inbounds st.σ[$j])
        if i.name === :kind
            s === :site && return :(CorePotts.owner_kind(st, $j))
            s === :cell && return :(Potts._cellkind(st, $j))
            error("`kind[…]` needs a site (`source`, `target`) or a cell (`new`, `owner[s]`)")
        end
        i.name === :volume && return :($(env.T)(Potts._cellval(st.cell.volume, $j)))
        i.name in (:surface, :generation) && return :(Potts._cellval(st.cell.$(i.name), $j))
        if i.name === :cluster
            s === :site && error("`cluster[…]` needs a cell; write `cluster[owner[s]]`")
            return :(CorePotts.cluster_of(st.cell, $j))
        end
    end
    error("cannot index `$(i.name)`")
end

# Fold over live cells (optionally of some kinds) or over all sites; the body sees the bound
# cell/site as the implicit index (`volume`, `x`, `kind` refer to it).
function _lower_population(args, env)
    n, body, cond = args
    ni = info(n)
    T = env.T
    nsym = Symbol(nameof(_unwrap(n)))
    acc, cnt, flag, v = map(p -> Symbol(p, :_, nsym), (:acc, :cnt, :zero, :v))
    bind = copy(env.bind)
    if ni.role === :bound_cell
        merge!(bind, Dict{Symbol, Any}(:volume => :($T(@inbounds st.cell.volume[$nsym])),
            :surface => :(@inbounds st.cell.surface[$nsym]), :kind => :(Potts._cellkind(st, $nsym)),
            :id => nsym, :generation => :(@inbounds st.cell.generation[$nsym]), :__cell => nsym,
            :cluster => :(CorePotts.cluster_of(st.cell, $nsym)),
            :cluster_volume => :($T(Potts._cellval(st.cell.cluster_volume, CorePotts.cluster_of(st.cell, $nsym)))),
            :cluster_surface => :(Potts._cellval(st.cell.cluster_surface, CorePotts.cluster_of(st.cell, $nsym)))))
        range = :(1:length(st.cell.kind))
        skip = :((@inbounds st.cell.volume[$nsym]) > 0 && $(_kindtest(:(Potts._cellkind(st, $nsym)), ni.options.kinds)))
    else
        merge!(bind, Dict{Symbol, Any}(:owner => :(@inbounds st.σ[$nsym]), :kind => :(CorePotts.owner_kind(st, $nsym)),
            :__site => nsym, :position => :(CorePotts.coordinates(ctx.lattice, $nsym))))
        range = :(1:length(st.σ))
        skip = true
    end
    inner = LowerEnv(T, env.mode, bind, env.relname)
    op = ni.options.op
    init, step, fin = if op === :sum
        :(zero($T)), :($acc += $v), acc
    elseif op === :mean
        :(zero($T)), :($acc += $v), :($cnt == 0 ? zero($T) : $acc / $T($cnt))
    elseif op === :minimum
        :(typemax($T)), :($acc = min($acc, $T($v))), acc
    elseif op === :maximum
        :(typemin($T)), :($acc = max($acc, $T($v))), acc
    elseif op === :count
        :(Int32(0)), :($acc += Int32($v)), acc
    elseif op === :any
        false, :($acc |= $v), acc
    elseif op === :all
        true, :($acc &= $v), acc
    end
    return quote
        let $acc = $init, $cnt = 0
            for $nsym in $range
                if $skip && $(lower(cond, inner))
                    $v = $(lower(body, inner))
                    $step
                    $cnt += 1
                end
            end
            $fin
        end
    end
end

function _lower_laplacian(c, env)
    i = info(c)
    (i !== nothing && i.role === :field) || error("`Δ` applies to field variables")
    haskey(env.bind, :__site) || error("`Δ($(i.name))` needs a site")
    return :(CorePotts.laplacian(st.site.$(i.name), ctx, $(env.bind[:__site])))
end

function _lower_gather(args, env)
    n, anchor, body, cond = args
    ni = info(n)
    spec = ni.options.relation
    rel = spec isa RelationRef ? spec.name : env.relname[spec]
    T = env.T
    nsym = Symbol(nameof(_unwrap(n)))
    # names derived from the (unique) bound variable: deterministic, so rebuilding a problem
    # yields the same generated function and never recompiles
    acc, cnt, flag, x0, y, k, v, ins = map(p -> Symbol(p, :_, nsym), (:acc, :cnt, :zero, :x0, :y, :k, :v, :in))
    op = ni.options.op
    init, step, fin = if op === :sum
        :(zero($T)), :($acc += $v), acc
    elseif op === :prod
        :(one($T)), :($acc *= $v), acc
    elseif op === :mean
        :(zero($T)), :($acc += $v), :($cnt == 0 ? zero($T) : $acc / $T($cnt))
    elseif op === :geomean
        :(zero($T)), :(($v > 0 ? ($acc += log($T($v))) : ($flag = true))),
        :(($cnt == 0 || $flag) ? zero($T) : exp($acc / $T($cnt)))
    elseif op === :geomean_shifted
        :(zero($T)), :($acc += log1p(max(zero($T), $T($v)))), :($cnt == 0 ? zero($T) : expm1($acc / $T($cnt)))
    elseif op === :minimum
        :(typemax($T)), :($acc = min($acc, $T($v))), acc
    elseif op === :maximum
        :(typemin($T)), :($acc = max($acc, $T($v))), acc
    elseif op === :count
        :(Int32(0)), :($acc += Int32($v)), acc
    elseif op === :any
        false, :($acc |= $v), acc
    elseif op === :all
        true, :($acc &= $v), acc
    end
    condc = lower(cond, env)
    bodyc = lower(body, env)
    return quote
        let $x0 = CorePotts.coordinates(ctx.lattice, $(lower(anchor, env))), $acc = $init, $cnt = 0, $flag = false
            for $k in 1:length(ctx.$rel)
                $ins, $y = CorePotts.shift(ctx.lattice, $x0, @inbounds ctx.$rel.offsets[$k])
                if $ins
                    $nsym = CorePotts.linear_index(ctx.lattice, $y)
                    if $condc
                        $v = $bodyc
                        $step
                        $cnt += 1
                    end
                end
            end
            $fin
        end
    end
end

# ---------------------------------------------------------------------------------------
# Analysis helpers

"""All symbolic leaves and operations of `x` (depth-first), for validation and analysis."""
function _walk(f, x)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return
    f(x)
    if iscall(x) && !(info(x) !== nothing && info(x).role in SCOPES)
        foreach(a -> _walk(f, a), arguments(x))
    end
    return
end

"""Named quantities (by role) referenced in `x`."""
function _uses(x)
    out = Set{Tuple{Symbol, Symbol}}()
    _walk(x) do y
        i = info(y)
        i === nothing || push!(out, (i.role, i.name))
    end
    return out
end
_uses_builtin(x, name) = (:builtin, name) in _uses(x)

"""Gathers in `x`: (bound variable info, anchor)."""
function _gathers(x)
    out = Any[]
    _walk(x) do y
        iscall(y) && operation(y) === gather && push!(out, (info(arguments(y)[1]), arguments(y)[2]))
    end
    return out
end

_has_op(x, op) = (found = Ref(false); _walk(y -> (iscall(y) && operation(y) === op && (found[] = true)), x); found[])
