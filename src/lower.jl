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
    keys::IdDict{Any, String}        # sort keys of the operand code lowered so far (`_code_key`)
end
LowerEnv(T, mode, bind, relname) = LowerEnv(T, mode, bind, relname, IdDict{Any, String}())

const _MODE_NAMES = Dict(:cell => "a cell term (`cells(…) => …`)", :site => "a site term or site update",
    :contact => "a contact term (`contacts => …`)", :model => "a model-scope expression (model update, observed)", :edge => "an edge term or link rule (`edges(rel) => …`, `@link`)", :edge_update => "an edge update (`@before_mcs`/`@after_mcs` writing an edge variable)", :proposal => "a copy-scoped expression (drive, constraint, on-copy update, temperature)")

_unwrap(x) = Symbolics.unwrap(x)

# ---------------------------------------------------------------------------------------
# Canonical order (D-107). Symbolics stores a sum or product as a dictionary and hands its
# operands out in the order of their hashes, which involve function identities (a
# Potts-registered operator's hash changes with each package build). Everything that
# reaches generated code is therefore put in an order read from the model alone: `lower`
# emits the operands of a commutative `+`/`*` sorted by their code (`_code_key`), and the
# names and slots numbered while compiling (hoisted folds, gather relations,
# integrals) follow `_symkey`, a printed form of a symbolic expression with commutative
# operands sorted. Neither key involves a hash.

"""Generated code `ex` as an S-expression string without line numbers (the sort key of
operands; cheaper than printing Julia syntax, and equal keys mean equal code). `memo` holds
the keys of sub-expressions already keyed (operands of inner sums and products), which are
copied rather than printed again: keying nested sums costs their size, not size × depth."""
function _code_key(ex, memo = nothing)
    ex isa Expr || return sprint(show, ex)
    memo !== nothing && haskey(memo, ex) && return memo[ex]
    io = IOBuffer()
    _code_key!(io, ex, memo)
    k = String(take!(io))
    memo === nothing || (memo[ex] = k)
    return k
end
function _code_key!(io, ex, memo)
    ex isa Expr || return show(io, ex)
    if memo !== nothing
        k = get(memo, ex, nothing)
        k === nothing || return print(io, k)
    end
    print(io, '(', ex.head)
    for a in ex.args
        a isa LineNumberNode && continue
        print(io, ' ')
        _code_key!(io, a, memo)
    end
    print(io, ')')
    return nothing
end

"""
Canonical printed form of symbolic `x`: commutative operands sorted, no hashes. A fold's
bound variable prints by its role and options, so equal folds over different variables print
alike; the sorted names of those variables (`c_3`, numbered in source order when the model
is built) follow as a tie-break, so textually equal but distinct folds keep distinct keys
in an order that does not depend on the walk.
"""
function _symkey(x)
    names = String[]
    k = _symkey!(names, x)
    return isempty(names) ? k : string(k, "|", join(sort!(names), ","))
end
function _symkey!(names, x)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return _symkey_value(x)
    SymbolicUtils.isconst(x) && return _symkey_value(SymbolicUtils.unwrap_const(x))
    i = info(x)
    if i !== nothing
        i.role in (:bound, :bound_cell, :bound_site) || return string(i.role, ":", i.name)
        push!(names, string(nameof(x)))
        return string(i.role, ":", i.name,
            _canonical_checked(() -> "the bound variable `$(i.name)` (its relation or options)", i.options))
    end
    issym(x) && return string("sym:", nameof(x))
    op = operation(x)
    ks = map(a -> _symkey!(names, a), arguments(x))
    (SymbolicUtils.isadd(x) || SymbolicUtils.ismul(x)) && sort!(ks)
    return string(_symop_key(op), "(", join(ks, ","), ")")
end
_symop_key(op::Function) = string(nameof(parentmodule(op)), ".", nameof(op))
_symop_key(op) = _canonical_checked(() -> "the operation `$(_key_string(op))`", op)
# a constant in an expression, printed canonically (an `ArgumentError` naming it if too deep, D-130)
_symkey_value(v) = _canonical_checked(() -> "the symbolic constant `$(_key_string(v))`", v)

"""64-bit FNV-1a of a string: a content hash fixed by its definition (names, not order)."""
function _fnv64(s::AbstractString)
    h = 0xcbf29ce484222325
    for b in codeunits(s)
        h = (h ⊻ b) * 0x00000100000001b3
    end
    return h
end

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
    op === _connected && return _lower_connected(args, env)
    op === population && return _lower_population(args, env)
    op === Δ && return _lower_laplacian(args[1], env)
    # cell references (R6, D-066 item 5): liveness, sources, the enclosing cell of a fold
    op === cell_alive && return :(Potts._alive_slot($(_refst(env)).cell.volume, $(lower(args[1], env))))
    if op === cluster_sibling
        cl, k = lower(args[1], env), lower(args[2], env)
        ctr = _ref_counter(_SIBLING_LABEL)
        ctr === nothing && return :(Potts._sibling(st.cell, $cl, Int32($k)))
        return :(Potts._sibling_counted(st.cell, $cl, Int32($k), $(ctr[1]), $(ctr[2])))
    end
    op === as_ref && return :(Int32($(lower(args[1], env))))
    if op === outer_value
        haskey(env.bind, :__outer) || error("`members(…)` is a fold domain: write `sum(… for m in members(cluster))`")
        return lower(args[1], env.bind[:__outer])
    end
    if op === cell_centroid
        haskey(env.bind, :__cell) || error("`centroid(k)` needs a cell: use it in cell updates, division conditions or observed quantities")
        k = Int(SymbolicUtils.unwrap_const(_unwrap(args[1])))
        return :(Potts._centroid_axis($(env.T), st.cell, ctx.lattice, $(env.bind[:__cell]), $k))
    end
    if op === copy_displacement
        env.mode === :proposal || error("`displacement(c, k)` is only available in drives and on-copy updates")
        k = Int(SymbolicUtils.unwrap_const(_unwrap(args[2])))
        return :(Potts._displacement_axis($(env.T), st.cell, ctx.lattice, prop, $(lower(args[1], env)), $k))
    end
    if op === cell_integral
        haskey(env.bind, :__cell) || error("`integral(x)` is per cell: use it in cell updates, division conditions or observed quantities")
        return :(Potts._cellval(st.cell.$(_integral_name(args[1])), $(env.bind[:__cell])))
    end
    if op === history_lag
        (haskey(env.bind, :mcs) && env.mode !== :proposal) || error("`Pre(x, k)` needs the MCS clock: use it in updates, equations, division conditions or link rules (not in $(_MODE_NAMES[env.mode]))")
        _walk(args[1]) do y
            i = info(y)
            i !== nothing && i.role === :cell &&
                error("`Pre($(i.name), k)`: lags of cell variables are not tracked; chain lag variables instead (`$(i.name)_1 ~ Pre($(i.name))`, `$(i.name)_2 ~ Pre($(i.name)_1)`, …)")
        end
        k = Int(SymbolicUtils.unwrap_const(_unwrap(args[2])))
        return _retarget_history(lower(args[1], env), env.bind[:mcs], k)
    end
    if op === random_uniform
        haskey(env.bind, :__draw) || error("`rand()` is only available in updates, equations, division conditions and rules (not in $(_MODE_NAMES[env.mode]))")
        key, mcs, entity = env.bind[:__draw]
        stream = CorePotts.stream_id("Potts.draw.$(SymbolicUtils.unwrap_const(_unwrap(args[1])))")
        return :(CorePotts.uniform($(env.T), CorePotts.draw($key, $mcs, $entity, $stream)[1]))
    end
    (op === random_normal || op === random_normal_above) && return _lower_normal(op, args, env)
    op isa ModelingToolkitBase.Pre && return lower(args[1], env)     # previous value
    # `_nonzero(at(_nonzero(v), j))` (`grn.A[j]` of a Bool node): the read is already a Bool
    op === _nonzero && _is_bool_node_read(args[1]) && return lower(args[1], env)
    op === ifelse && return :($(lower(args[1], env)) ? $(lower(args[2], env)) : $(lower(args[3], env)))
    if op === (^) && SymbolicUtils.isconst(_unwrap(args[2]))
        e = SymbolicUtils.unwrap_const(_unwrap(args[2]))
        if e isa Integer || (e isa Real && isinteger(e))
            return Expr(:call, :^, lower(args[1], env), Int(e))   # literal_pow, no float exponent
        end
    end
    # float-valued functions compute in the model's scalar type (no Float64 from Int args)
    if op in _FLOAT_OPS || op === (^)
        return Expr(:call, op, map(a -> :(Potts._tofloat($(env.T), $(lower(a, env)))), args)...)
    end
    # `+`/`*` as left-associated binary calls: varargs calls above 32 arguments allocate
    # (bitwise the same result: n-ary `+` is itself a left fold), D-014; a scalar sum or
    # product folds its operands in canonical order (D-107)
    if (SymbolicUtils.isadd(x) || SymbolicUtils.ismul(x)) && length(args) >= 2
        codes = map(a -> lower(a, env), args)
        return foldl((a, b) -> Expr(:call, op, a, b), codes[sortperm(map(c -> _code_key(c, env.keys), codes))])
    end
    if (op === (+) || op === (*)) && length(args) > 2
        return foldl((a, b) -> Expr(:call, op, a, b), map(a -> lower(a, env), args))
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
        r === :builtin && i.name === :direction &&
            error("`direction` is a vector: write its component `direction[k]` (k = 1, …, N)")
        r === :builtin && i.name === :position && env.mode === :proposal &&
            error("`position` in $(_MODE_NAMES[env.mode]) needs a site: write `position[target][k]` or `position[source][k]`")
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
    elseif r === :contact_count          # a contact fold (D-150): its tracker column
        haskey(env.bind, :__cell) || error("`count(… for _ in contacts)` is per cell: use it in cell updates, division conditions or observed quantities")
        return :($(env.T)(Potts._cellval(st.cell.$(i.name), $(env.bind[:__cell]))))
    end
    error("cannot lower `$x` (role $r)")
end

"""Site and model variable reads in `ex` → reads of their history ring `k` MCS back."""
function _retarget_history(ex, mcs, k)
    ex isa Expr || return ex
    if ex.head === :. && (ex.args[1] == :(st.site) || ex.args[1] == :(st.model))
        name = ex.args[2].value
        return :(Potts._LagView(st.history.$name, $mcs, $k))
    end
    return Expr(ex.head, (_retarget_history(a, mcs, k) for a in ex.args)...)
end

"""Read-only linear view of the ring-buffer slot holding a lag (`CorePotts.history_slot`)."""
struct _LagView{R}
    ring::R
    offset::Int
end
@inline function _LagView(ring, mcs, k)
    depth = size(ring, ndims(ring))
    return _LagView(ring, (CorePotts.history_slot(depth, Int(mcs), k) - 1) * (length(ring) ÷ depth))
end
Base.@propagate_inbounds Base.getindex(v::_LagView, i::Integer) = v.ring[i + v.offset]

"""Distinct site expressions `x` of `integral(x)` in the model's statements, as stored
(`_integral_operand`): those read by a statement other than `@observed`, and with
`observed = true` also those read only by `@observed`, after them."""
# Observed-only integrals have no cell column (D-120). The stored ones keep the order of the
# full gather, so models without observed-only integrals keep their layout and fingerprint.
_integrals(sys::PottsSystem; observed = false) = first(_integrals_folds(sys; observed))

# The stored operands and, per operand, the slots of its hoisted folds (`_integral_hoist`).
function _integrals_folds(sys::PottsSystem; observed = false)
    out = Any[]
    folds = Vector{Pair{Symbol, Any}}[]
    head = Any[(u.eq.rhs for u in getfield(sys, :updates))..., (eq.rhs for eq in getfield(sys, :equations))...,
        (d.when for d in getfield(sys, :divisions))..., (r for d in getfield(sys, :divisions) for (_, r) in d.rules if !(r isa Split))...,
        (r.when for r in getfield(sys, :link_rules))...]
    tail = Any[getfield(sys, :sweep).temperature, (x for b in getfield(sys, :discrete) for x in b.next)...]
    xs = Any[head..., (o.expr for o in getfield(sys, :observed))..., tail...]
    # operands read by a statement other than `@observed`
    stored = Any[]
    for x in Any[head..., tail...]
        _walk(x) do y
            iscall(y) && operation(y) === cell_integral || return
            a = first(_integral_hoist(arguments(y)[1]))
            any(z -> isequal(z, a), stored) || push!(stored, a)
        end
    end
    for x in xs
        new = Any[]
        newfolds = Vector{Pair{Symbol, Any}}[]
        _walk(x) do y
            iscall(y) && operation(y) === cell_integral || return
            a, fs = _integral_hoist(arguments(y)[1])
            any(z -> isequal(z, a), out) || any(z -> isequal(z, a), new) || (push!(new, a); push!(newfolds, fs))
        end
        perm = sortperm(map(_symkey, new))                 # canonical within a statement (D-107)
        append!(out, new[perm])
        append!(folds, newfolds[perm])
    end
    keep = [any(z -> isequal(z, a), stored) for a in out]
    order = observed ? [findall(keep); findall(!, keep)] : findall(keep)
    return out[order], folds[order]
end

"""Largest lag `k` of `Pre(x, k)` per site/model variable name in the model's statements."""
_history_depths(sys::PottsSystem) = _history_depths(Any[(u.eq.rhs for u in getfield(sys, :updates))..., (eq.rhs for eq in getfield(sys, :equations))...,
    (d.when for d in getfield(sys, :divisions))..., (r for d in getfield(sys, :divisions) for (_, r) in d.rules if !(r isa Split))...,
    (r.when for r in getfield(sys, :link_rules))..., (x for b in getfield(sys, :discrete) for x in b.next)...])
function _history_depths(xs::Vector{Any})
    depths = Dict{Symbol, Int}()
    for x in xs
        _walk(x) do y
            (iscall(y) && operation(y) === history_lag) || return
            k = Int(SymbolicUtils.unwrap_const(_unwrap(arguments(y)[2])))
            _walk(arguments(y)[1]) do z
                i = info(z)
                i !== nothing && i.role in (:site, :field, :model) && (depths[i.name] = max(get(depths, i.name, 0), k))
            end
        end
    end
    return depths
end

"""Centroid of cell `c` along axis `k` (0 for the medium and empty slots)."""
@inline function _centroid_axis(::Type{T}, cell, lat, c, k) where {T}
    (c == 0 || cell.volume[c] == 0) && return zero(T)
    return CorePotts.centroid_position(T, cell, lat, Int(c))[k]
end

"""Centroid displacement of cell `c` along axis `k` by copy `prop` (0 unless `c` is its old or new cell)."""
@inline function _displacement_axis(::Type{T}, cell, lat, prop, c, k) where {T}
    (c == 0 || (c != prop.new && c != prop.old)) && return zero(T)
    return CorePotts.embed(lat, CorePotts.centroid_shift(T, cell, lat, Int(c), prop.x, c == prop.new ? 1 : -1))[k]
end

"""Integers (and `Bool`s) in the model's scalar type; other numbers (dual numbers of an
implicit solver's Jacobian, already-typed floats) unchanged."""
@inline _tofloat(::Type{T}, x::Integer) where {T} = T(x)
@inline _tofloat(::Type{T}, x) where {T} = x

"""
Cartesian position of site `i`: the embedded lattice coordinates times the lattice
spacing (on a square lattice with unit spacing, the coordinates themselves).
"""
@inline function _position(::Type{T}, ctx, i) where {T}
    e = CorePotts.embed(ctx.lattice, map(T, CorePotts.coordinates(ctx.lattice, i)))
    return haskey(ctx, :spacing) ? map((x, h) -> x * T(h), e, ctx.spacing) : e
end

"""
Source→target offset of a copy (P6.4a1, D-188): the coordinate difference of `t` and `s`,
the minimum image along periodic axes (a plain difference along closed ones), embedded and
scaled as `_position`. A function of the two sites alone; the tie |d| = L/2 keeps `d`.
"""
@inline function _direction(::Type{T}, ctx, s, t) where {T}
    lat = ctx.lattice
    d = map(_min_image, CorePotts.coordinates(lat, t), CorePotts.coordinates(lat, s), lat.dims, lat.periodic)
    e = CorePotts.embed(lat, map(T, d))
    return haskey(ctx, :spacing) ? map((x, h) -> x * T(h), e, ctx.spacing) : e
end
@inline function _min_image(a::Int, b::Int, L::Int, periodic::Bool)
    v = a - b
    periodic || return v
    return 2v > L ? v - L : 2v < -L ? v + L : v
end

"""The number of completed MCS during a sweep (the sweep's `ctx.mcs`, P6.4a1); 0 outside one
(the host hook)."""
@inline _copy_mcs(ctx) = haskey(ctx, :mcs) ? ctx.mcs : 0

# whether `x` is `at(position, s)`: the position of site `s` (indexed again by an axis)
function _is_site_position(x)
    (x isa SymbolicUtils.BasicSymbolic && iscall(x) && operation(x) === at) || return false
    i = info(arguments(x)[1])
    return i !== nothing && i.role === :builtin && i.name === :position
end

"""Value of a cell array at `c`, zero for the medium (`c == 0`)."""
@inline _cellval(a, c) = c == 0 ? zero(eltype(a)) : @inbounds a[c]
"""Kind of cell `c` (`0` for the medium)."""
@inline _cellkind(st, c) = c == 0 ? Int32(0) : Int32(@inbounds st.cell.kind[c])

# ---------------------------------------------------------------------------------------
# Cell references (R6; D-066 item 5, D-231)

"""Whether `x` is a cell variable declared `::CellRef`."""
_is_ref_var(x) = (i = info(x); i !== nothing && i.role === :cell && get(i.options, :reference, false) === true)
# a stand-in for a reference's value (the on-copy value ΔH reads, `_oncopy_after`; a
# previous-value snapshot `x__pre`)
_is_ref_standin(x) = (i = info(x); i !== nothing && i.role !== :cell && get(i.options, :reference, false) === true)

"""
Whether the cell expression `x` is a reference, read as a referent when it indexes a cell
quantity: a `::CellRef` variable (bare, or read at a cell, as `partner[old]`, every hop of a
chain), `sibling(…)` or `root(…)`. Any other cell index (`old`, `owner[s]`, a fold's bound
cell) is read as it is.
"""
function _is_ref(x)
    x = _unwrap(x)
    x isa SymbolicUtils.BasicSymbolic || return false
    _is_ref_var(x) && return true
    _is_ref_standin(x) && return true
    iscall(x) || return false
    op = operation(x)
    (op === cluster_sibling || op === as_ref) && return true
    op isa ModelingToolkitBase.Pre && return _is_ref(arguments(x)[1])
    # `ifelse(c, a, b)` with a reference in a branch: read as a reference (guarded), whichever
    # branch is taken (a plain cell index such as `id` reads the same through the guard)
    op === ifelse && return any(_is_ref, arguments(x)[2:3])
    if op === at
        a = _unwrap(arguments(x)[1])
        iscall(a) && operation(a) isa ModelingToolkitBase.Pre && (a = _unwrap(arguments(a)[1]))
        return _is_ref_var(a)
    end
    return false
end

"""The references in `x` that index a cell quantity or are tested with `alive` (each hop of a
chain once), outermost first: the cells a copy's sweep functions read through references."""
function _ref_reads(x)
    out = Any[]
    _ref_reads!(out, _unwrap(x))
    return out
end
function _ref_reads!(out, y)
    y isa SymbolicUtils.BasicSymbolic || return out
    iscall(y) || return out
    (info(y) !== nothing && info(y).role in SCOPES) && return out
    op = operation(y)
    # a population fold reads every cell's referents, as a fold reads every cell (snapshot
    # or not): no per-copy claim, and its bound cells cannot be lowered outside it
    op === population && return out
    r = op === at && length(arguments(y)) == 2 && _is_ref(arguments(y)[2]) ? arguments(y)[2] :
        op === cell_alive ? arguments(y)[1] : nothing
    r === nothing || _push_ref!(out, r)
    foreach(a -> _ref_reads!(out, _unwrap(a)), arguments(y))
    return out
end
# `ifelse(c, a, b)`: each reference branch (both are claimed); others once
function _push_ref!(out, r)
    r = _unwrap(r)
    if r isa SymbolicUtils.BasicSymbolic && iscall(r) && operation(r) === ifelse
        foreach(b -> _is_ref(b) && _push_ref!(out, b), arguments(r)[2:3])
        return out
    end
    any(z -> isequal(z, r), out) || push!(out, r)
    return out
end
_reads_refs(x) = !isempty(_ref_reads(x))
# whether `x` reads through a reference anywhere, folds included
function _mentions_refs(x)
    found = Ref(false)
    _walk(x) do y
        iscall(y) || return
        op = operation(y)
        ((op === at && length(arguments(y)) == 2 && _is_ref(arguments(y)[2])) || op === cell_alive) && (found[] = true)
    end
    return found[]
end

# the state referents are read in: `st`, or the state bound as `:__refst` (the killing
# credit reads the readers' referents before the copy, `_vacated_energy_expr`)
_refst(env) = get(env.bind, :__refst, :st)

# Reference diagnostics (E4, E5; `track = (:references,)`): while a tracked problem's code is
# generated, `_REF_SLOTS` maps each term label to its slot of the state's counter
# `st.model[REF_COUNTS]`, and `_REF_TERM` names the term being lowered. Untracked (the
# default), both are `nothing` and the lowered code is unchanged.
const REF_COUNTS = Symbol("#ref_counts")
const _SIBLING_LABEL = "sibling(k) found several alive members of kind k (the lowest birth is used)"
const _REF_SLOTS = Base.ScopedValues.ScopedValue{Union{Nothing, Dict{String, Int}}}(nothing)
const _REF_TERM = Base.ScopedValues.ScopedValue{Union{Nothing, String}}(nothing)
_with_ref_term(f, label) = _REF_SLOTS[] === nothing ? f() : Base.ScopedValues.with(f, _REF_TERM => label)
# `(counter, slot)` for `label` (default: the term being lowered), or `nothing` (untracked)
function _ref_counter(label = _REF_TERM[])
    slots = _REF_SLOTS[]
    (slots === nothing || label === nothing) && return nothing
    j = get(slots, label, nothing)
    j === nothing && return nothing
    return (Expr(:., :(st.model), QuoteNode(REF_COUNTS)), j)
end

# `x[ref]` for a quantity `x` (Info `i`) of the referent `ref`
function _lower_deref(i::Info, ref, env)
    r = lower(ref, env)
    rs = _refst(env)
    ctr = _refst(env) === :st ? _ref_counter() : nothing
    # tracked: a dereference of a dead referent (nonzero, not alive) is counted for its term
    ctr === nothing || (r = :(Potts._count_dead($(ctr[1]), $(ctr[2]), $rs.cell.volume, $r)))
    if i.role === :cell
        return :(Potts._deref($rs.cell.$(i.name), $rs.cell.volume, $r, $(_ref_default(i, env))))
    elseif i.role in (:site, :field)
        error("site variable `$(i.name)` indexed by a reference (a cell); a site variable is read at a site")
    elseif i.role === :builtin
        n = i.name
        n === :kind && return :(Potts._deref_kind($rs.cell, $r))
        n === :volume && return :($(env.T)(Potts._deref_volume($rs.cell.volume, $r)))
        n === :birth && return :(Potts._deref_birth($rs.cell, $r))
        n === :cluster && return :(Potts._deref_cluster($rs.cell, $r))
        n in (:surface, :generation) &&
            return :(Potts._deref($rs.cell.$n, $rs.cell.volume, $r, zero(eltype($rs.cell.$n))))
        if n in (:euler, :euler_full) || n in _PIECES_NAMES
            col = n in _PIECES_NAMES ? _pieces_column(n) : _euler_column(n)
            return :($(env.T)(Potts._deref($rs.cell.$col, $rs.cell.volume, $r, zero(eltype($rs.cell.$col)))))
        end
        error("`$n[…]` cannot be read through a reference")
    end
    error("cannot index `$(i.name)` by a reference")
end

# the value a dead referent's cell variable reads as: its declared default (0 for a reference)
function _ref_default(i::Info, env)
    get(i.options, :reference, false) === true && return :(Int32(0))
    v = i.default
    v isa Bool && return env.T(v)
    v isa Real && return env.T(v)
    (v isa Union{Num, SymbolicUtils.BasicSymbolic} && _param_only(v)) && return :($(env.T)($(lower(v, env))))
    error("cell variable `$(i.name)` is read through a reference, so a dead referent reads its declared default; " *
          "give `$(i.name)` a scalar default (a number or an expression of parameters)")
end

"""Whether slot `r` (a reference) holds an alive cell: `0 < r ≤ capacity` and `volume[r] > 0`."""
@inline _alive_slot(vol, r) = (0 < r) & (r <= length(vol)) && @inbounds(vol[r] > 0)
"""The claim of a copy that reads referent `r`: `r` when it is an alive slot, else 0 (none)."""
@inline _ref_claim(vol, r) = _alive_slot(vol, r) ? Int32(r) : Int32(0)
"""Column `a` of referent `r`, or `d` (the medium's value) when `r` is 0 or dead."""
@inline _deref(a, vol, r, d) = _alive_slot(vol, r) ? @inbounds(a[r]) : d      # r checked by `_alive_slot`
@inline _deref_volume(vol, r) = _alive_slot(vol, r) ? @inbounds(vol[r]) : zero(eltype(vol))
@inline _deref_kind(cell, r) = _alive_slot(cell.volume, r) ? Int32(@inbounds cell.kind[r]) : Int32(0)
@inline _deref_cluster(cell, r) = _alive_slot(cell.volume, r) ? @inbounds(cell.cluster[r]) : Int32(0)
"""`birth` of cell `c` (D-066 item 3): its serial with a lifecycle (`cell.birth`), else its slot."""
# (`c` is a cell slot in 1:capacity: the env's cell, `_birth_at` with c ≠ 0, or a referent
# `_alive_slot` checked; every column has the capacity's length)
@inline _birth(cell, c) = haskey(cell, :birth) ? @inbounds(cell.birth[c]) : Int32(c)
@inline _birth_at(cell, c) = c == 0 ? Int32(0) : _birth(cell, c)
@inline _deref_birth(cell, r) = _alive_slot(cell.volume, r) ? _birth(cell, r) : Int32(0)
"""
The alive member of kind `k` of cluster `cl`, or 0. With several, the one with the lowest
`birth` (the oldest; E5); `_sibling_scan` also says whether there were several.
"""
@inline _sibling(cell, cl, k) = first(_sibling_scan(cell, cl, k))
@inline function _sibling_scan(cell, cl, k)
    best, bb, dup = Int32(0), typemax(Int32), false
    cl == 0 && return best, dup
    for m in 1:length(cell.kind)          # m ∈ 1:capacity: every column has that length
        if @inbounds(cell.volume[m]) > 0 && @inbounds(cell.cluster[m]) == cl && @inbounds(cell.kind[m]) == k
            dup |= best != 0
            b = Int32(_birth(cell, m))
            b < bb && ((best, bb) = (Int32(m), b))
        end
    end
    return best, dup
end
# tracked (E5): counts the scans that found several members
@inline function _sibling_counted(cell, cl, k, cnt, j)
    s, dup = _sibling_scan(cell, cl, k)
    dup && CorePotts._bump!(cnt, j)
    return s
end
# tracked (E4): `r`, counted in slot `j` when it names a dead cell (nonzero and not alive)
@inline function _count_dead(cnt, j, vol, r)
    (r != 0 && !_alive_slot(vol, r)) && CorePotts._bump!(cnt, j)
    return r
end

# Sort of an index expression: :site or :cell.
function _sort(x)
    x = _unwrap(x)
    i = info(x)
    if i !== nothing
        i.role in (:bound, :bound_site) && return :site
        i.role === :bound_cell && return :cell
        i.role === :builtin && return i.name in (:source, :target, :site, :site′) ? :site :
               i.name in (:old, :new, :owner, :owner′, :id, :a, :b) ? :cell : :unknown
    end
    if x isa SymbolicUtils.BasicSymbolic && iscall(x) && operation(x) === at
        a = info(arguments(x)[1])
        a !== nothing && a.role === :builtin && a.name === :owner && return :cell
    end
    return :unknown
end

# whether `x` is `at(_nonzero(v), …)` (or `at(Pre(_nonzero(v)), …)`): a Bool node read at an
# index, which `_lower_at` lowers to a Bool already
function _is_bool_node_read(x)
    x = _unwrap(x)
    (x isa SymbolicUtils.BasicSymbolic && iscall(x) && operation(x) === at) || return false
    a = _unwrap(arguments(x)[1])
    iscall(a) && operation(a) isa ModelingToolkitBase.Pre && (a = _unwrap(arguments(a)[1]))
    return iscall(a) && operation(a) === _nonzero
end

function _lower_at(args, env)
    x = _unwrap(args[1])
    # `Pre(x[i])` arrives as `at(Pre(x), i)`: the previous value is the stored one
    iscall(x) && operation(x) isa ModelingToolkitBase.Pre && (x = _unwrap(arguments(x)[1]))
    # a Bool node of a discrete component (`grn.A[new]`): its slot there, read as a Bool
    iscall(x) && operation(x) === _nonzero && return :(Potts._nonzero($(_lower_at(Any[arguments(x)[1], args[2:end]...], env))))
    # `position[s][k]` (P6.4a1): component `k` of site `s`'s position
    if _is_site_position(x)
        length(args) == 2 || error("`position[s][k]` takes one axis")
        return :(Potts._position($(env.T), ctx, $(lower(arguments(x)[2], env)))[$(lower(args[2], env))])
    end
    i = info(x)
    i === nothing && error("cannot index `$(_standin_var(x))`")
    # `x[ref]`: the referent's value, the medium's when it is dead or 0 (D-066 item 5)
    i.role !== :kindtable && length(args) == 2 && _is_ref(args[2]) && return _lower_deref(i, args[2], env)
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
        if i.name === :position
            s === :site && error("`position[$(args[2])]` is a vector: write its component `position[$(args[2])][k]`")
            if !haskey(env.bind, :position)
                env.mode === :proposal && error("`position` in $(_MODE_NAMES[env.mode]) needs a site: " *
                                                "write `position[target][k]` or `position[source][k]`")
                error("`position` is not available in $(_MODE_NAMES[env.mode])")
            end
            return :($(env.bind[:position])[$j])
        end
        if i.name === :direction
            haskey(env.bind, :direction) || error("`direction` is not available in $(_MODE_NAMES[env.mode]): it is the " *
                                                  "copy's source→target offset, read in drives, constraints, on-copy updates and " *
                                                  "the copy-scope @sweep temperature")
            return :($(env.bind[:direction])[$j])
        end
        if i.name === :kind
            s === :site && return :(CorePotts.owner_kind(st, $j))
            if haskey(env.bind, :__kind_of)                   # `kind[old]`/`kind[new]`: bound once
                for (c, k) in env.bind[:__kind_of]
                    j === c && return k
                end
            end
            s === :cell && return :(Potts._cellkind(st, $j))
            error("`kind[…]` needs a site (`source`, `target`) or a cell (`new`, `owner[s]`)")
        end
        i.name === :volume && return :($(env.T)(Potts._cellval(st.cell.volume, $j)))
        i.name in (:surface, :generation) && return :(Potts._cellval(st.cell.$(i.name), $j))
        if i.name === :birth
            s === :site && error("`birth[…]` needs a cell (`old`, `new`, a reference), not a site")
            return :(Potts._birth_at(st.cell, $j))
        end
        if i.name in (:euler, :euler_full)
            s === :site && error("`$(i.name)[…]` needs a cell (`old`, `new`, `owner[s]`), not a site")
            return :($(env.T)(Potts._cellval(st.cell.$(_euler_column(i.name)), $j)))
        end
        if i.name in _PIECES_NAMES
            s === :site && error("`$(i.name)[…]` needs a cell (`old`, `new`, `owner[s]`), not a site")
            return :($(env.T)(Potts._cellval(st.cell.$(_pieces_column(i.name)), $j)))
        end
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
            :birth => :(Potts._birth(st.cell, $nsym)),
            :euler => :($T(@inbounds st.cell.euler[$nsym])),
            :euler_full => :($T(@inbounds st.cell.$(_euler_column(:euler_full))[$nsym])),
            (n => :($T(@inbounds st.cell.$(_pieces_column(n))[$nsym])) for n in _PIECES_NAMES)...,
            :cluster => :(CorePotts.cluster_of(st.cell, $nsym)),
            :cluster_volume => :($T(Potts._cellval(st.cell.cluster_volume, CorePotts.cluster_of(st.cell, $nsym)))),
            :cluster_surface => :(Potts._cellval(st.cell.cluster_surface, CorePotts.cluster_of(st.cell, $nsym)))))
        range = :(1:length(st.cell.kind))
        skip = :((@inbounds st.cell.volume[$nsym]) > 0 && $(_kindtest(:(Potts._cellkind(st, $nsym)), ni.options.kinds)))
    else
        merge!(bind, Dict{Symbol, Any}(:owner => :(@inbounds st.σ[$nsym]), :kind => :(CorePotts.owner_kind(st, $nsym)),
            :__site => nsym, :position => :(Potts._position($T, ctx, $nsym)), :site => nsym))
        range = :(1:length(st.σ))
        skip = :(CorePotts.in_domain(ctx.lattice, $nsym))
    end
    bind[:__outer] = env                 # `members(cluster)`: the enclosing cell's `cluster`
    inner = LowerEnv(T, env.mode, bind, env.relname, env.keys)
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
    faces = get(env.bind, :__bc, _FACES[])
    (faces === nothing || !haskey(faces, i.name)) &&
        return :(CorePotts.laplacian(st.site.$(i.name), ctx, $(env.bind[:__site])))
    return :(CorePotts.laplacian(st.site.$(i.name), ctx, $(env.bind[:__site]); bc = $(_bc_code(faces[i.name], env))))
end

# The `bc` of a field's `@boundary` faces (D-145): one `(low, high)` pair of `GhostFace`s per
# axis (homogeneous, so kernels index it per axis without a union); an axis without an entry
# is zero flux. Values are lowered here, so a parameter value is read from `p` (a `remake`
# keeps the code).
function _bc_code(axes, env)
    T = env.T
    side(::Nothing) = :(CorePotts.GhostFace(false, zero($T)))
    side(::NoFlux) = side(nothing)
    side(d::Dirichlet) = :(CorePotts.GhostFace(true, $T($(lower(d.value, env)))))
    return Expr(:tuple, (Expr(:tuple, side(a === nothing ? nothing : a[1]), side(a === nothing ? nothing : a[2])) for a in axes)...)
end

function _lower_gather(args, env)
    n, anchor, body, cond = args
    _uses_builtin(anchor, :position) &&
        error("a gather is anchored at a site: use `site` (the current site), `source` or `target`, not `position`")
    ni = info(n)
    spec = ni.options.relation
    T = env.T
    # the target's shell (`shell(s)`, P6.3g) is a fixed offset table of the lattice, not a
    # context relation
    if spec isa ShellRelation
        len, offs = :(length(CorePotts.shell_offsets(ctx.lattice))), :(CorePotts.shell_offsets(ctx.lattice))
    else
        rel = spec isa RelationRef ? spec.name : env.relname[spec]
        len, offs = :(length(ctx.$rel)), :(ctx.$rel.offsets)
    end
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
    elseif op === :log1p_geomean
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
    elseif op === :pieces             # a mask of the shell positions, then their pieces
        :(UInt32(0)), :($acc |= UInt32(1) << ($k - 1)), :(CorePotts.shell_pieces(ctx.lattice, $acc, $(ni.options.full)))
    elseif op === :distinct           # counted at its first occurrence: no earlier site gives it
        nothing, nothing, acc
    end
    condc = lower(cond, env)
    bodyc = lower(body, env)
    if op === :distinct
        k2, y2, in2, dup = map(p -> Symbol(p, :_, nsym), (:k2, :y2, :in2, :dup))
        init = :(Int32(0))
        step = quote
            $dup = false
            for $k2 in 1:($k - 1)
                $in2, $y2 = CorePotts.shift(ctx.lattice, $x0, @inbounds $offs[$k2])
                $in2 && ($dup |= let $nsym = CorePotts.linear_index(ctx.lattice, $y2)
                    $condc && ($bodyc == $v)
                end)
            end
            $acc += Int32(!$dup)
        end
    end
    return quote
        let $x0 = CorePotts.coordinates(ctx.lattice, $(lower(anchor, env))), $acc = $init, $cnt = 0, $flag = false
            for $k in 1:$len
                $ins, $y = CorePotts.shift(ctx.lattice, $x0, @inbounds $offs[$k])
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

# `connected(c; rule)` (P6.3g): the rule's CorePotts kernel on the copy, for `old` or `new`
function _lower_connected(args, env)
    env.mode === :proposal || error("`connected(…)` and `connectivity(…)` read a copy: use them in @constraint or @drive")
    who = isequal(_unwrap(args[1]), _unwrap(B.old)) ? :old : :new
    code = Int(SymbolicUtils.unwrap_const(_unwrap(args[2])))
    g = _global_rule(code)
    g === nothing || return _lower_global(who, g)
    code <= 3 && return :(CorePotts.local_rule(st.σ, ctx, prop, $(isodd(code)), $(code >= 2)))
    code == 4 && return :(CorePotts.arc_or_pair(st.σ, ctx, prop))
    return :(CorePotts.simple_point(st.σ, ctx, prop, $who, $(code == 6)))
end

# `Global` (P6.9a) inline, in a drive or a constraint: exact on the host algorithms, in the
# window on the checkerboard (an undecided copy reads `false`); the gaining side is local
_lower_global(who, g) = who === :new ? :(CorePotts.global_gains(st.σ, ctx, prop, $(_global_adj(g)))) :
                        :(CorePotts.global_keeps(st.σ, ctx, prop, $(_global_vals(g)...), CorePotts.GlobalSearch()) == Int32(0))
# `Val(full)` (hex has one adjacency: `:face`), and with it `Val(window)`, `Val(box capacity)`
_global_adj(g) = :(Val($(g.adjacency === :full && !_PIECES_HEX[])))
function _global_vals(g)
    W = g.window
    cap = W === nothing ? 0 : prod(n -> min(n, 2W + 1), _LATTICE_DIMS[])
    return (_global_adj(g), :(Val($W)), :(Val($cap)))
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
# whether `x` reads `connected(…; rule = Global(…))` (P6.9a)
_reads_global(x) = (found = Ref(false); _walk(y -> (iscall(y) && operation(y) === _connected &&
    _global_rule(Int(SymbolicUtils.unwrap_const(_unwrap(arguments(y)[2])))) !== nothing && (found[] = true)), x); found[])
