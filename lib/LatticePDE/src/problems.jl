# `discretize`: a `PDESystem` on a lattice becomes one SciML problem: an `ODEProblem` of
# rates or a `DiscreteProblem` of maps, whose metadata holds the owned problem (the fused
# update kernels the field algorithms step) and whose function is the compiled right side
# (`∂c = rhs`, or the next state of a map) that SciML's solvers call, built at its first
# call.

"""The explicit Euler update `c + dt · r` of the owned stepper (`dt = G.rt[2]`)."""
euler_update(kb, c, r) = c + Ex(kb, runtime!(kb, RT_DT)) * r

# symbol table keys: a `Symbol` or string names a field or parameter; any other symbol is
# looked up as its unwrapped term
_symkey(x::Union{Symbol, AbstractString}) = Symbol(x)
_symkey(x) = unwrap(x)

function _domain_ends(sys::PDESystem)
    return map(unwrap.(get_ivs(sys))) do v
        k = findfirst(d -> isequal(unwrap(d.variables), v), get_domain(sys))
        Float64.(
            (
                leftendpoint(get_domain(sys)[k].domain),
                rightendpoint(get_domain(sys)[k].domain),
            )
        )
    end
end
# a time span in its own float type, the promotion of its ends (SciML's `tType`)
_float_span(a, b) = (T = float(promote_type(typeof(a), typeof(b))); (T(a), T(b)))
# the time span of the domain of the first variable, in its own float type
function _time_ends(sys::PDESystem)
    v = unwrap(first(get_ivs(sys)))
    k = findfirst(d -> isequal(unwrap(d.variables), v), get_domain(sys))
    return _float_span(
        leftendpoint(get_domain(sys)[k].domain),
        rightendpoint(get_domain(sys)[k].domain)
    )
end

# a coefficient expression as a function of the raw parameter vector, over every 0/1
# assignment of its indicator terms (kind sets, comparisons): an indicator is 0 or 1 at each
# site, and the coefficient is not monotone in it (`k (1 − χ)` is largest at χ = 0), so each
# assignment is evaluated. A table read is evaluated at every index it can read, as the
# kernel reads it: index 0 reads 0 and any other index is clamped into `1:length` (the
# table's last entry above it, its first below 1). `Dk[2]` and `value_at(Dk, 2)` read their
# own entry; the `value_at` reads with one index expression `k` (the same site's kind) take
# one index together, `0` and `1:L` with `L` the longest table of the group (`value_at(Da,
# k) - value_at(Db, k)` per kind), and a read that appears twice is one read. A group takes
# the indices of the integer interval of its index expression (`+ − * min max abs`, `ifelse`
# as the hull of its arms, parameters at their values), over the declared bounds of its
# inputs (`bounds = (lo, hi)` metadata, which the input values are checked against) and,
# when `p` carries them, the current values of host-written inputs (`ParamsTables.inputs`):
# index 0 only when the interval holds 0 and, where it does, the index's values at the sites
# (when the host arrays give them) say whether a site reaches it; the entries are those the
# nonzero values clamp to. This covers every value the coefficient takes at a site, for any
# expression of the reads (`value_at(Dq, k) (20 − value_at(Dq, k))`, `sin(value_at(Ds, k))`,
# `1 / value_at(Dv, k)`), with the indicators taken independently of the entries (a
# superset). A non-finite value (`1 / 0`) gives a non-finite bound, which is no bound.
# `c(p)` is the largest magnitude, `_hi`/`_lo` the largest and smallest signed values; `p`
# carries the tables (`Problems.ParamsTables`), and with table reads but no tables the
# values are `NaN`. `nothing` when the expression reads anything but scalar parameters and
# tables, keeps a call that is not plain arithmetic (a registered operator such as
# `laplacian`), or has more than `_MAXIND` distinct indicators; more than `_MAXEVALS`
# evaluations (assignments × indices) give `NaN`, no bound.
struct CoefBound
    # one compiled function of the parameters per assignment
    fs::Vector{Any}
    # per read, in argument order: table, literal index, group (0: literal)
    reads::Vector{Tuple{String, Int, Int}}
    # per group: its index expression as an interval tree (`_ivtree`)
    groups::Vector{Any}
    text::String                            # the coefficient, for messages
    # the intervals it reads (a coordinate, a declared field or input interval), as `(name,
    # (lo, hi))`; empty: exact
    box::Vector{Tuple{String, Tuple{Float64, Float64}}}
    ghosts::Vector{String}                  # the ghost values it is also taken at, in words
end
function CoefBound(fs, reads, groups, text)
    return CoefBound(fs, reads, groups, text, Tuple{String, Tuple{Float64, Float64}}[])
end
CoefBound(fs, reads, groups, text, box) = CoefBound(fs, reads, groups, text, box, String[])
# An interval coefficient: `iv(args)` encloses its values over
# the intervals it reads (`_interval`, the evaluator of the implicit operator's bounds), so
# a value is the pair of its ends
struct _IvCoef{F}
    iv::F
end
_pv(p) = p isa Problems.ParamsTables ? p.p : p

# ---- the interval of an integer index expression
# A tree of the index expression: `(:c, v)` a literal, `(:p, i)` parameter `i`, `(:in, key,
# (lo, hi))` an input with its declared bounds, `(op, args...)` for `+ * neg min max abs`,
# `(:ifelse, cond, a, b)` (its interval is the hull of the arms; `cond` is `(:cmp, f, x, y)`
# for a comparison, else `(:anycond,)`), `(:any,)` anything else (any integer). Only forms
# that lower are here (`÷` and `clamp` of an index do not lower today, so they are `:any`).
function _ivtree(u, params, ivars)
    u = unwrap(u)
    v = unwrap_const(u)
    v isa Real && return (:c, Float64(v))
    for (x, k, b) in ivars
        isequal(x, u) && return (:in, k, b)
    end
    for (i, q) in enumerate(params)
        isequal(unwrap(q), u) && return (:p, i)
    end
    iscall(u) || return (:any,)
    f, a = operation(u), arguments(u)
    t(y) = _ivtree(y, params, ivars)
    f === (+) && return (:+, map(t, a)...)
    f === (*) && return (:*, map(t, a)...)
    f === (-) && return length(a) == 1 ? (:neg, t(a[1])) : (:+, t(a[1]), (:neg, t(a[2])))
    f === min && return (:min, map(t, a)...)
    f === max && return (:max, map(t, a)...)
    f === abs && return (:abs, t(a[1]))
    f === ifelse && return (:ifelse, _condtree(a[1], params, ivars), t(a[2]), t(a[3]))
    return (:any,)
end
const _CMPS = (==, !=, <, <=, >, >=)
function _condtree(c, params, ivars)
    u = unwrap(c)
    if iscall(u) && any(g -> operation(u) === g, _CMPS) && length(arguments(u)) == 2
        return (
            :cmp, operation(u), _ivtree(arguments(u)[1], params, ivars),
            _ivtree(arguments(u)[2], params, ivars),
        )
    end
    return (:anycond,)
end
const _IVANY = (-Inf, Inf)
function _ivmul(a, b)
    q = (a[1] * b[1], a[1] * b[2], a[2] * b[1], a[2] * b[2])
    return any(isnan, q) ? _IVANY : (minimum(q), maximum(q))
end
# the current values of input `k` that `p` carries (`Problems.ParamsTables` inputs), or
# nothing
function _input_now(p, k)
    p isa Problems.ParamsTables || return nothing
    j = findfirst(x -> first(x) == k, p.inputs)
    j === nothing && return nothing
    v = last(p.inputs[j])
    v isa Number && return (Float64(v), Float64(v))
    isempty(v) && return nothing
    lo, hi = extrema(v)
    return (Float64(lo), Float64(hi))
end
function _ival(t, p)
    h = t[1]
    h === :c && return (t[2], t[2])
    h === :p && (v = Float64(_pv(p)[t[2]]); return isnan(v) ? _IVANY : (v, v))
    if h === :in
        b = t[3]
        now = _input_now(p, t[2])
        now === nothing && return b
        # the values hold their bounds (checked)
        return (max(b[1], now[1]), min(b[2], now[2]))
    end
    h === :any && return _IVANY
    h === :ifelse && (
        a = (_ival(t[3], p), _ival(t[4], p));
        return (min(a[1][1], a[2][1]), max(a[1][2], a[2][2]))
    )
    a = map(x -> _ival(x, p), t[2:end])
    h === :+ && return (sum(first, a), sum(last, a))
    h === :* && return foldl(_ivmul, a)
    h === :neg && return (-a[1][2], -a[1][1])
    h === :min && return (minimum(first, a), minimum(last, a))
    h === :max && return (maximum(first, a), maximum(last, a))
    if h === :abs
        lo, hi = a[1]
        if lo >= 0
            return (lo, hi)
        elseif hi <= 0
            return (-hi, -lo)
        else
            return (0.0, max(-lo, hi))
        end
    end
    return _IVANY
end
# the indices a read group takes, as the kernel reads them: 0 when the index can be 0, and
# the entries `1:L` the nonzero values clamp to (`L` the longest table of the group). The
# interval decides; where it holds 0, the index's values at the sites decide when the host
# input arrays give them (an `ifelse` hull is conservative: `ifelse(k == 1, 0, k)` with no
# site of kind 1 never reads index 0)
function _group_indices(t, p, L)
    lo, hi = _ival(t, p)
    lo, hi = floor(lo), ceil(hi)
    if lo <= 0 <= hi
        v = _site_vals(t, p)
        if v !== nothing && all(isfinite, v)
            out = sort!(
                unique!([x == 0 ? 0 : clamp(round(Int, x), 1, max(L, 1)) for x in v])
            )
            return out
        end
    end
    out = Int[]
    lo <= 0 <= hi && push!(out, 0)
    if lo <= -1 || hi >= 1
        a = lo >= 1 ? Int(min(lo, L)) : 1
        b = hi >= 1 ? Int(min(hi, L)) : 1
        append!(out, a:b)
    end
    return out
end
# the value of an index expression at every site (a vector over the sites, or a number when
# it reads no input array), from the host input arrays `p` carries; `nothing` when an input
# has no host value or a part has no value per site (`:any`, a condition that is not a
# comparison). Whole-array operations: a few arrays per call, never one allocation per site
function _site_vals(t, p)
    h = t[1]
    h === :c && return t[2]
    h === :p && return Float64(_pv(p)[t[2]])
    if h === :in
        p isa Problems.ParamsTables || return nothing
        j = findfirst(x -> first(x) == t[2], p.inputs)
        j === nothing && return nothing
        v = last(p.inputs[j])
        return v isa Number ? Float64(v) : Float64.(vec(v))
    end
    if h === :ifelse
        c = t[2]
        c[1] === :cmp || return nothing
        x, y, a, b = _site_vals(c[3], p), _site_vals(c[4], p), _site_vals(t[3], p),
            _site_vals(t[4], p)
        any(isnothing, (x, y, a, b)) && return nothing
        return ifelse.(c[2].(x, y), a, b)
    end
    h in (:+, :*, :neg, :min, :max, :abs) || return nothing
    a = Any[_site_vals(x, p) for x in t[2:end]]
    any(isnothing, a) && return nothing
    h === :+ && return reduce((x, y) -> x .+ y, a)
    h === :* && return reduce((x, y) -> x .* y, a)
    h === :neg && return .-(a[1])
    h === :min && return reduce((x, y) -> min.(x, y), a)
    h === :max && return reduce((x, y) -> max.(x, y), a)
    return abs.(a[1])
end
# the first site (a tuple, from the shape of an input array `p` carries) where the index of
# group `t` is `i`, or nothing
function _site_of(t, p, i)
    p isa Problems.ParamsTables || return nothing
    k = findfirst(x -> last(x) isa AbstractArray, p.inputs)
    k === nothing && return nothing
    sz = size(last(p.inputs[k]))
    v = _site_vals(t, p)
    v === nothing && return nothing
    s = if v isa Number
        v == i ? 1 : nothing
    else
        findfirst(==(i), v)
    end
    return s === nothing ? nothing : Tuple(CartesianIndices(sz)[s])
end
# a table read as the kernel does it (emit.jl TABLE, `oob = :zero_at_0`)
_tabread(v, i::Integer) = i == 0 ? 0.0 : Float64(v[clamp(i, 1, length(v))])
# a value of the coefficient; a domain error (`sqrt` of a negative entry) is `NaN`; an
# interval coefficient gives the ends of its enclosure
_val(f::_IvCoef, args) = (q = f.iv(args); (Float64(q[1]), Float64(q[2])))
_isfin(v) = all(isfinite, v)
_push_val!(out, v::Real) = push!(out, v)
_push_val!(out, v::Tuple) = append!(out, v)
function _val(f, args)
    try
        return Float64(f(args...))
    catch e
        e isa DomainError && return NaN
        rethrow()
    end
end
# the table values per read, and the index ranges per group (`nothing`: over the cap or no
# tables)
function _ranges(c::CoefBound, p)
    p isa Problems.ParamsTables || return nothing
    tv = [last(p.tables[findfirst(x -> first(x) == k, p.tables)]) for (k, _, _) in c.reads]
    any(isempty, tv) && return nothing
    maxl = [
        maximum((length(tv[j]) for j in eachindex(c.reads) if c.reads[j][3] == g); init = 0)
            for g in eachindex(c.groups)
    ]
    rs = [_group_indices(c.groups[g], p, maxl[g]) for g in eachindex(c.groups)]
    # in Float64: an integer product of many lengths overflows (16^16 == 0)
    length(c.fs) * prod(Float64 ∘ length, rs; init = 1.0) <= _MAXEVALS || return nothing
    return tv, rs
end
_indices(c::CoefBound, is) = (((_, e, g),) -> g == 0 ? e : is[g]).(c.reads)
function _vals(c::CoefBound, p)
    out = Float64[]
    if isempty(c.reads)
        foreach(f -> _push_val!(out, _val(f, p)), c.fs)
        return out
    end
    r = _ranges(c, p)
    r === nothing && return [NaN]
    tv, rs = r
    q = _pv(p)
    for f in c.fs, is in Iterators.product(rs...)
        _push_val!(
            out, _val(
                f, (
                    q..., (_tabread(tv[j], i) for (j, i) in enumerate(_indices(c, is)))...,
                )
            )
        )
    end
    return out
end
(c::CoefBound)(p) = maximum(abs, _vals(c, p))
# the largest finite magnitude: the bound over the values that are finite (0 over the cap or
# with no tables), which an explicit count must still meet
_seen(c::CoefBound, p) = maximum((abs(v) for v in _vals(c, p) if isfinite(v)); init = 0.0)
_hi(c::CoefBound, p) = maximum(_vals(c, p))
_lo(c::CoefBound, p) = minimum(_vals(c, p))
"""
    _why(c::CoefBound, p) -> nothing | :cap | :tables | _IntervalWhy | (combos, more)

Why `c` has no finite bound at `p`: `nothing` when it has one; `:cap` over the evaluation
cap; `:tables` table reads with no tables; `_IntervalWhy(box)` an interval coefficient whose
enclosure over the intervals it reads is not finite (`1 / (x - 0.5)`: not a value that is
infinite, so never refused); else the distinct read combinations with a value
that is not finite, each a vector of `(table, index, value read)` (index 0 reads 0; empty
when no table is read), at most `_MAXWHY` of them, and how many more there are.
"""
function _why(c::CoefBound, p)
    all(isfinite, _vals(c, p)) && return nothing
    isempty(c.box) || return _IntervalWhy(c.box)
    isempty(c.reads) && return ([Tuple{String, Int, Float64}[]], 0)
    p isa Problems.ParamsTables || return :tables
    r = _ranges(c, p)
    r === nothing && return :cap
    tv, rs = r
    q = _pv(p)
    combos = Vector{Tuple{String, Int, Float64}}[]
    for f in c.fs, is in Iterators.product(rs...)
        ix = _indices(c, is)
        _isfin(_val(f, (q..., (_tabread(tv[j], i) for (j, i) in enumerate(ix))...))) &&
            continue
        # the index each read takes, clamped as the kernel clamps it
        w = unique!(
            [
                (
                    c.reads[j][1], i == 0 ? 0 : clamp(i, 1, length(tv[j])),
                    _tabread(tv[j], i),
                ) for (j, i) in enumerate(ix)
            ]
        )
        w in combos || push!(combos, w)
    end
    return (combos[1:min(end, _MAXWHY)], max(0, length(combos) - _MAXWHY))
end
# a site where a read of `c` takes index 0 (from the input arrays `p` carries), for messages
function _zero_site(c::CoefBound, p)
    for g in eachindex(c.groups)
        s = _site_of(c.groups[g], p, 0)
        s === nothing || return s
    end
    return nothing
end
const _MAXWHY = 4
const _MAXIND = 6
const _MAXEVALS = 4096
const _PLAIN = (
    +, -, *, /, ^, inv, abs, sqrt, cbrt, exp, log, sin, cos, tan, tanh, min, max, identity,
)   # (`identity`: an irrational, `identity(Const(π))`)
_plainop(f) = any(g -> f === g, _PLAIN)
function _coef_bound(x, params, tabs = Dict{Any, String}(), ivars = (); box = ())
    u0 = unwrap(x)
    # the table reads, each a fresh variable; the `value_at` reads grouped by index
    # expression: a group takes one index for all its reads
    reads, tvars, reps = Tuple{String, Int, Int}[], Any[], Dict{Any, Any}()
    gkeys = Any[]
    function walkt(y)
        iscall(y) || return nothing
        f, a = operation(y), arguments(y)
        if (f === getindex || f === value_at) && length(a) == 2 &&
                haskey(tabs, unwrap(a[1]))
            any(k -> isequal(k, y), keys(reps)) && return nothing
            k = tabs[unwrap(a[1])]
            i = unwrap_const(unwrap(a[2]))
            # a literal index reads its own entry
            if i isa Integer || (i isa AbstractFloat && isinteger(i))
                push!(reads, (k, Int(i), 0))
            else
                g = findfirst(j -> isequal(gkeys[j], unwrap(a[2])), eachindex(gkeys))
                g === nothing && (push!(gkeys, unwrap(a[2])); g = length(gkeys))
                push!(reads, (k, 0, g))
            end
            v = unwrap(Symbolics.variable(:__table_read, length(reads)))
            push!(tvars, v)
            reps[y] = v
            return nothing
        end
        return foreach(walkt, a)
    end
    walkt(u0)
    isempty(reps) || (u0 = unwrap(substitute(u0, reps; fold = Val(false))))
    inds = Any[]
    function walk(y)
        iscall(y) || return
        if operation(y) === ismember || operation(y) in (==, <, <=, >, >=)
            any(z -> isequal(z, y), inds) || push!(inds, y)
        else
            foreach(walk, arguments(y))
        end
        return
    end
    walk(u0)
    length(inds) <= _MAXIND || return nothing
    plain(y) = !iscall(y) || (_plainop(operation(y)) && all(plain, arguments(y)))
    args = Any[params; tvars]
    argidx = Dict{Any, Int}(unwrap(q) => i for (i, q) in enumerate(args))
    fs = Any[]
    read = Dict{String, Tuple{Float64, Float64}}()  # the intervals read
    inbox(v) = findfirst(b -> isequal(b[1], v), box)
    for bits in Iterators.product(ntuple(_ -> (0, 1), length(inds))...)
        # an `ifelse` whose condition the indicators decide takes its arm (the condition is
        # a Bool); every other indicator is an arithmetic factor, 0 or 1
        u = isempty(inds) ? u0 : _arms(u0, inds, bits)
        u = if isempty(inds)
            u
        else
            unwrap(substitute(u, Dict{Any, Any}(zip(inds, bits)); fold = Val(true)))
        end
        vs = Symbolics.get_variables(u)
        if plain(u) && all(v -> any(q -> isequal(q, v), args), vs)
            push!(fs, Symbolics.build_function(u, args...; expression = Val(false)))
            continue
        end
        # a coefficient that reads a coordinate or a field or input with a declared
        # interval: its enclosure over those intervals, by the interval evaluator
        all(v -> any(q -> isequal(q, v), args) || inbox(v) !== nothing, vs) ||
            return nothing
        iv = _interval(u, argidx, Dict{Any, String}(), [(b[1], b[2]) for b in box])
        iv === nothing && return nothing
        for v in vs
            j = inbox(v)
            j === nothing || (read[box[j][3]] = box[j][2])
        end
        push!(fs, _IvCoef(iv))
    end
    return CoefBound(
        fs, reads, Any[_ivtree(k, params, ivars) for k in gkeys], string(x),
        sort!([k => b for (k, b) in read]; by = first) |>
            v -> Tuple{String, Tuple{Float64, Float64}}[(first(q), last(q)) for q in v]
    )
end

# `u` with every `ifelse` whose condition the indicator values `bits` decide replaced by its
# arm (the indicators as Bools in the condition), nested switches included
function _arms(u, inds, bits)
    vals = Dict{Any, Any}(zip(inds, Bool.(bits)))
    reps = Dict{Any, Any}()
    function walk(y)
        iscall(y) || return nothing
        if operation(y) === ifelse
            c = unwrap_const(unwrap(substitute(arguments(y)[1], vals; fold = Val(true))))
            if c isa Bool
                reps[y] = arguments(y)[c ? 2 : 3]
                return nothing
            end
        end
        return foreach(walk, arguments(y))
    end
    walk(u)
    isempty(reps) && return u
    return _arms(unwrap(substitute(u, reps; fold = Val(false))), inds, bits)
end

# the multiplier of a diffusion term: the operator call replaced by its coefficient (1 for
# Δ and Dx(Dx(c)), K for DivKGrad(K, c) and Dx(K Dx(c)))
function _diffusion_coefficient(term)
    reps = Dict{Any, Any}()
    function walk(y)
        return iscall(y) && (
            f = operation(y);
            if f === laplacian
                reps[y] = 1
            elseif f isa DivKGrad
                reps[y] = arguments(y)[1]
            elseif f isa Differential
                (r = _raw_flux(y); reps[y] = r === nothing || r[1] === nothing ? 1 : r[1])
            else
                foreach(walk, arguments(y))
            end
        )
    end
    walk(unwrap(term))
    return substitute(term, reps; fold = Val(false))
end

# a site-varying diffusion term `m Op(c)` (`:SiteDiffusion`): the center multiplier `m` (the
# operator replaced by 1), read at the row's own site, and the face coefficient `K` (1 for
# `laplacian`, `K` of `DivKGrad(K, c)` or of `Dx(K Dx(c))`), read through face means of two
# sites
function _site_parts(term)
    reps, K = Dict{Any, Any}(), Any[]
    function walk(y)
        return iscall(y) && (
            f = operation(y);
            if f === laplacian
                (reps[y] = 1; push!(K, 1))
            elseif f isa DivKGrad
                (reps[y] = 1; push!(K, arguments(y)[1]))
            elseif f isa Differential
                (
                    r = _raw_flux(y); reps[y] = 1;
                    push!(K, r === nothing || r[1] === nothing ? 1 : r[1])
                )
            else
                foreach(walk, arguments(y))
            end
        )
    end
    walk(unwrap(term))
    length(K) == 1 || return nothing
    return substitute(term, reps; fold = Val(false)), only(K)
end

# The terms of one row of the Jacobian under one choice of the arms of its `ifelse` switches
struct RowTerms
    diffusion::Vector{CoefBound}
    # center multiplier m, face coefficient K
    sitediffusion::Vector{Tuple{CoefBound, CoefBound}}
    linear::Vector{CoefBound}
    # coefficient, index of the other field (0: not a row)
    crosslinear::Vector{Tuple{CoefBound, Int}}
    crossdiffusion::Vector{Tuple{CoefBound, Int}}   # coefficient, index of the other field
    # `m v_a` of an upwind advection term, its axis
    advection::Vector{Tuple{CoefBound, Int}}
end
function RowTerms()
    return RowTerms(
        CoefBound[], Tuple{CoefBound, CoefBound}[], CoefBound[],
        Tuple{CoefBound, Int}[], Tuple{CoefBound, Int}[],
        Tuple{CoefBound, Int}[]
    )
end
function Base.copy(r::RowTerms)
    return RowTerms(
        copy(r.diffusion), copy(r.sitediffusion), copy(r.linear), copy(r.crosslinear),
        copy(r.crossdiffusion), copy(r.advection)
    )
end
# a site-diffusion term's parts at `p`: max|m| max|K| (the independent bound) and the seen
# product
_sd(f, p) = f[1](p) * f[2](p)
_sdseen(f, p) = _seen(f[1], p) * _seen(f[2], p)
const _MAXARMS = 64                       # row alternatives (arm choices) before giving up

# A time span `[lo, hi]` that an interval bound reads at each evaluation (the window of an
# explicit group's count)
mutable struct TimeSpan
    lo::Float64
    hi::Float64
    # the parameters, tables and inputs of the last count (`Problems.bound_params`)
    params::Any
end
"""
    StabilityBound

`ρ(p)`: a bound on the spectral radius of the rate Jacobian at raw parameters `p` (the
Gershgorin bound; for one diffusing field `D Σ 4/h² + |k|`), built from the linearity
table. Per rate field (one Jacobian row):
- `Diffusion` terms give `D = Σ D_i(p)` times `Σ_d 4/h_d²`, plus `|D| max(0, |r| − 1)/h_d²`
  for a parameter-dependent Robin face on axis `d` (the ghost value's cell coefficient
  `r = (α/2 − β)/(α/2 + β)` stiffens the boundary row);
- `LinearLocal` terms (`k c`) add `|k|`;
- `CrossLinear` terms add their off-diagonal row sum: `|k|` for `k o`, and
  `|D₂| (Σ_d 4/h_d² + Robin terms of o)` for cross-diffusion `D₂ laplacian(o)`.
- `SiteDiffusion` terms `m Op(c)` (a multiplier `m` that reads inputs through table reads
  and indicators only) give `max|m| · max K` times `Σ_d 4/h_d²` (and the Robin
  terms): the center multiplier `m` is evaluated jointly over its reads (one site), the face
  coefficient `K` (1 for `laplacian`) independently, because a face mixes two sites'
  indices. For `M = diag(m) ≥ 0` and the symmetric `A`, `M A` is similar to `M^½ A M^½` on
  the rows with `m > 0`, so its spectrum is real and bounded by `max m · ρ(A)`.
A coefficient with kind sets or comparisons (indicators, 0 or 1 per site) is evaluated at
every 0/1 assignment of them: the largest magnitude enters `ρ`, the largest signed value
the diagonal. An `ifelse` whose condition the indicators decide takes its arm. A coefficient
that reads a table (`Dk[2] * laplacian(c)`, `value_at(Dk, kind) * laplacian(c)`) is
evaluated at every index each read can take, as the kernel reads it (the entry itself for
`Dk[2]`; for `value_at`, index 0, which reads 0 unless the index is an input declared never
0, and every entry, clamped into each table; reads with one index take one index together),
from the tables `p` carries (`Problems.ParamsTables`): any expression of the reads is
covered, a negative entry is negative diffusion, a large one raises the bound, and a
non-finite value (`1 / 0`) is no bound. A switch `ifelse(cond, a, b)` (class `Other`) whose
condition reads no unknown field (a gate such as `t ≥ t_relax`) is bounded arm by arm: each
choice of a row's switch arms is a row of its own (at most 64 per row), the bound is the
worst, and the dominance test below holds for every choice (listed in `expanded`).

**Intervals**. A coefficient that reads the coordinates, or a
field (state, aux or input) with declared finite `bounds = (lo, hi)` (MTK's metadata), is
bounded over those intervals by the interval evaluator of the implicit operator's bounds:
the coordinates over the cell centers, or one ghost layer past the faces for a velocity and
for a face coefficient on an axis whose faces carry a value or a flux (a face mean there
reads the ghost site; on an axis of zero-flux or periodic faces a face coefficient is
bounded over the centers). With them:
- a diffusion `m Op(K, c)` whose `m` or `K` reads them is bounded as a site diffusion
  (`max|m| · max|K|`; `DivKGrad(:harmonic)(c, c)` over c's bounds, the frozen coefficient);
- upwind advection `m Advect(v, c)` adds `Σ_a 2 max|m v_a| / h_a` to its row (the CFL
  limit), and to the dominance test its compression part (`max|m v_a| / h_a` per axis for a
  constant velocity, twice that otherwise); a velocity or multiplier that reads the advected
  field itself (Burgers) stays unseen: its flux Jacobian's part `∂v/∂c · c` is central at
  the face mean, so the rows are not dominant;
- a local term (no spatial operator) enters through its Jacobian entries `∂f/∂u`, each
  bounded over the intervals it reads: a switch's arms by its indicator (`a max(c − c_T, 0)`
  gives `a` or 0, no interval needed), a nonlinear term over its field's declared bounds;
- a term that reads an aux field `K ~ rhs` is bounded through `rhs`.
The declared intervals are checked: a constant face or mask value outside
them is refused (`Problems.check_declared`), a write of a state field outside them too, and
a run checks that the fields whose interval a coefficient bound read stay inside
(`Problems.check_declared!`: `ReturnCode.Unstable` past them). An enclosure is not a value:
a diffusion coefficient whose interval reaches below zero and above it has no bound (the
reason names its interval), not a refusal (one below zero everywhere is negative diffusion),
and an enclosure that is not finite (`1/(x − 0.5)`) is no bound either, never a refused
value.

`NaN` (no bound) when:
- a field has a term the bound cannot see (`unbounded`: an `Other`, `Advection` or
  `LaggedSwitch` term that none of the rules above bounds, or a coefficient that reads more
  than scalar parameters, tables and the intervals above, or a coefficient with more than 6
  distinct kind sets and comparisons);
- a coefficient takes a non-finite value at some index or assignment, or its indicator
  assignments times table indices exceed 4096, the evaluation cap (the bound is `Inf` or
  `NaN`; `bound_parts` says which, and where);
- a needed parameter has no value;
- a row with `CrossLinear` terms on a loop of cross reads (it reads a row that reads it
  back, directly or through others) is not diagonally dominant with a nonpositive diagonal.
  A row off every loop is not tested: the Jacobian is block triangular there, with the
  eigenvalues of the rows' own blocks. The step limit `dt ρ ≤ 1.8` holds for real,
  dissipative spectra only; coupled rows such as `c' = a o, o' = −a c` have imaginary
  eigenvalues, which forward Euler amplifies at any step. Until a test of the stability
  region lands, such systems are refused instead of given a warning (a provisional
  decision).

With no bound, `ExplicitEuler` requires a user substep count. Until the IR tangent and
interval evaluator replace it, this is the stability analysis of the explicit steppers.
"""
struct StabilityBound
    # per row, 1/h_a² of its grid (a `Coarse` field's: `k h`)
    invh2::Vector{Vector{Float64}}
    keys::Vector{String}
    # per row, one entry per choice of its switches' arms
    rows::Vector{Vector{RowTerms}}
    faces::Vector{Vector{Tuple{Int, Coef, Coef}}}
    unbounded::Vector{String}
    terms::Vector{String}                 # the terms it cannot see, as `"key: term"`
    expanded::Vector{String}              # the `ifelse` terms bounded arm by arm
    # the inputs an index reads (`Problems.bound_inputs`)
    inputs::Vector{String}
    # the rows with an unseen term that reads another unknown field
    crossunseen::Vector{String}
    # per row, its grid's sites per axis (the steady gain)
    dims::Vector{Vector{Int}}
    # per row, its faces `(axis, side, α, β)`, or `nothing` on an irregular domain (whose
    # edges may cut a face off)
    anchors::Vector{Any}
    # the declared finite bounds of the state and aux fields, the keys whose
    # interval a coefficient bound read, and each constant face or mask value of a field
    # with declared bounds as `(key, where, numerator, denominator)` (a value `num/den` at
    # the parameters)
    declared::Vector{Tuple{String, Tuple{Float64, Float64}}}
    used::Vector{String}
    facevals::Vector{Tuple{String, String, Coef, Coef}}
    # per row, its Robin faces whose α or β varies by site or in time, as `(axis, f,
    # where)`: `f` a function of the parameters giving the ghost diagonal `d = α/(α/2 + β)`
    # over the face's sites at any time (`(NaN, NaN)`: no bound), `where` the face in the
    # user's words
    sitefaces::Vector{Vector{Tuple{Int, Any, String}}}
    # whether a face of `sitefaces` reads the time, and the time span its
    # bound is taken over (`Problems.bound_window!`: an explicit group sets each window's;
    # the system's start time until then)
    timed::Bool
    window::TimeSpan
    # each unseen term's reads, structurally: `(row key, "key: term", state keys)`,
    # the state fields it reads (its own included; an aux field's read through its
    # definition)
    unseenreads::Vector{Tuple{String, String, Vector{String}}}
end
Problems.reads_time(b::StabilityBound) = b.timed
Problems.unseen_reads(b::StabilityBound) = b.unseenreads
Problems.bound_params!(b::StabilityBound, pp) = (b.window.params = pp; nothing)
Problems.bound_params(b::StabilityBound) = b.window.params
Problems.bound_window(b::StabilityBound) = (b.window.lo, b.window.hi)
function Problems.bound_window!(b::StabilityBound, t0, t1)
    (b.window.lo = Float64(t0); b.window.hi = Float64(t1); nothing)
end
# the input keys of an interval tree
function _tree_inputs!(acc, t)
    h = t[1]
    h === :in && return push!(acc, t[2])
    h in (:c, :p, :any, :anycond) && return acc
    h === :cmp && (_tree_inputs!(acc, t[3]); _tree_inputs!(acc, t[4]); return acc)
    # `:ifelse` holds its condition first
    foreach(x -> _tree_inputs!(acc, x), t[2:end])
    return acc
end
function _row_inputs(rows)
    acc = String[]
    for alts in rows, r in alts
        for f in Iterators.flatten(
                    (
                        r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion),
                        r.linear,
                        first.(r.crosslinear), first.(r.crossdiffusion),
                        first.(r.advection),
                    )
                ),
                t in f.groups

            _tree_inputs!(acc, t)
        end
    end
    return sort!(unique!(acc))
end
Problems.bound_inputs(b::StabilityBound) = b.inputs
_cv(c::Coef, p) = c.param == 0 ? c.value : c.value * Float64(p[c.param])
# Σ_d max(0, |r| − 1)/h_d², the worst Robin face of each axis of field `i` (a face that
# varies by site: its worst site, `|r| = |d − 1|` over the diagonal's interval; Inf with no
# bound)
function _face_excess(b::StabilityBound, i, p)
    return sum(eachindex(b.invh2[i]); init = 0.0) do d
        b.invh2[i][d] * max(
            maximum(
                (
                    max(0.0, abs(Problems.face_ratio(_cv(α, p), _cv(β, p))) - 1)
                        for (ax, α, β) in b.faces[i] if ax == d
                ); init = 0.0
            ),
            maximum(
                (_site_excess(f(p)) for (ax, f, _) in b.sitefaces[i] if ax == d);
                init = 0.0
            )
        )
    end
end
_site_excess(q) = isnan(q[1]) ? Inf : max(0.0, abs(q[1] - 1) - 1, abs(q[2] - 1) - 1)
# the same over the axes whose excess is finite (an axis with a degenerate Robin face, a
# ratio that is not finite, counts 0): the seen bound keeps every finite part of a row
function _face_excess_seen(b::StabilityBound, i, p)
    return sum(eachindex(b.invh2[i]); init = 0.0) do d
        x = b.invh2[i][d] * maximum(
            (
                max(0.0, abs(Problems.face_ratio(_cv(α, p), _cv(β, p))) - 1)
                    for (ax, α, β) in b.faces[i] if ax == d
            ); init = 0.0
        )
        y = b.invh2[i][d] *
            maximum(
            (_site_excess(f(p)) for (ax, f, _) in b.sitefaces[i] if ax == d);
            init = 0.0
        )
        (isfinite(x) ? x : 0.0) + (isfinite(y) ? y : 0.0)
    end
end
function (b::StabilityBound)(p)
    isempty(b.unbounded) || return NaN
    r = bound_parts(b, p)
    return isempty(r.coupled) ? r.ρ : NaN
end

# The bound of the rows `keep` alone (a field group): a cross term that reads a
# field outside the group reads its array, which does not change during the group's step (a
# source, as the group sees it); the other terms are the row's own
function Problems.restrict_bound(b::StabilityBound, keep)
    idx = [i for i in eachindex(b.keys) if b.keys[i] in keep]
    length(idx) == length(b.keys) && return b
    new = Dict(i => j for (j, i) in enumerate(idx))
    cut(ts) = [(f, j == 0 ? 0 : new[j]) for (f, j) in ts if j == 0 || haskey(new, j)]
    rows = [
        [
            RowTerms(
                r.diffusion, r.sitediffusion, r.linear,
                cut(r.crosslinear), cut(r.crossdiffusion), r.advection
            )
                for r in b.rows[i]
        ] for i in idx
    ]
    ks = b.keys[idx]
    mine(t) = any(k -> startswith(t, "$k: "), ks)
    return StabilityBound(
        b.invh2[idx], ks, rows, b.faces[idx], [k for k in b.unbounded if k in ks],
        filter(mine, b.terms), filter(mine, b.expanded), _row_inputs(rows),
        [k for k in b.crossunseen if k in ks], b.dims[idx],
        b.anchors[idx], b.declared, _used_keys(rows, b.declared),
        [f for f in b.facevals if f[1] in ks], b.sitefaces[idx],
        b.timed && any(!isempty, b.sitefaces[idx]), b.window, [
            u
                for u in b.unseenreads
                if u[1] in ks
        ]
    )
end

# The lagged coupling of field groups (`Problems.lagged_coupling`): per
# group, the largest over its rows (and their switch arms) of Σ max|coefficient| over the
# cross terms that read a field of another group (a cross diffusion `a laplacian(o)` with
# its `4 Σ 1/h²` and Robin parts, as in the row bound), with the worst term. A coefficient
# with no finite bound makes the rate `NaN` (or `Inf`), kept over any finite row. The group
# read graph: `reads`, the groups whose fields a seen cross term reads, whatever its value
# (the structure, so the graph does not change with the parameters); `unseen`, a row of the
# group has a term the bound cannot see that reads another unknown field (a state of another
# row, or an aux field, which may carry any state; a term on the row's own field alone, such
# as `-a^3`, couples no group). `within`: per group, the groups whose reads the rate sums
# (the group's loop); `nothing`, every other group. `text` is the coefficient as the user
# wrote it (`value_at(Kt, q)`), `raw` the bound's text (a front end can print it in the
# model's words).
function Problems.lagged_coupling(b::StabilityBound, groups, p; within = nothing)
    gof = Dict{String, Int}(k => g for (g, ks) in enumerate(groups) for k in ks)
    out = [
        (;
            rate = 0.0, row = "", other = "", text = "", raw = "", reads = Int[],
            unseen = any(k -> k in b.crossunseen, ks),
        ) for ks in groups
    ]
    for i in eachindex(b.keys)
        g = get(gof, b.keys[i], 0)
        g == 0 && continue
        for r in b.rows[i]
            for (_, j) in Iterators.flatten((r.crosslinear, r.crossdiffusion))
                h = j == 0 ? 0 : get(gof, b.keys[j], 0)
                (h == 0 || h == g || h in out[g].reads) || push!(out[g].reads, h)
            end
            tot, worst, wj, wt = 0.0, -Inf, 0, ""
            terms = Iterators.flatten(
                (
                    ((f, j, f(p)) for (f, j) in r.crosslinear if j != 0),
                    (
                        (f, j, f(p) * (4 * sum(b.invh2[j]) + _face_excess(b, j, p)))
                            for (f, j) in r.crossdiffusion if j != 0
                    ),
                )
            )
            for (f, j, v) in terms
                h = get(gof, b.keys[j], 0)
                (h == 0 || h == g || (within !== nothing && !(h in within[g]))) && continue
                tot += v
                # the worst term: the largest, or the first whose bound is not finite
                if wj == 0 || (isfinite(worst) && !(v <= worst))
                    worst, wj, wt = v, j, f.text
                end
            end
            wj == 0 && continue
            cur = out[g].rate
            # a rate that is not finite stays; else the larger
            (isfinite(cur) && !(tot <= cur)) &&
                (
                out[g] = (;
                    out[g]..., rate = tot, row = b.keys[i],
                    other = b.keys[wj], text = _coef_text(wt), raw = wt,
                )
            )
        end
    end
    foreach(q -> sort!(q.reads), out)
    return out
end

# The steady gain of row `i`: a bound on ‖A⁻¹‖∞ of its
# steady operator `A = s − ∇·(D ∇)` at the worst case, the smallest shift `s` (decay) over
# the reachable values, the smallest diffusion `D`, its Dirichlet and Robin faces, and no
# mask (a mask moves with σ, and an anchor left out only raises the gain). `A` is an
# M-matrix, so ‖A⁻¹‖∞ = max A⁻¹1. For an axis `a` with a face anchor, `w_a = (s + A_a)⁻¹ 1`
# (one tridiagonal along `a`) is constant along the other axes, whose faces only add a
# diagonal ≥ 0 there, so `A w_a ≥ 1` and `A⁻¹1 ≤ w_a`: the gain is at most the smallest `max
# w_a`, and `1/s` with a shift. `Inf` when nothing bounds it (no decay and no face anchor: a
# mask anchor does not count); `nothing` when a Robin face has a negative diagonal (`A` is
# no M-matrix there). Advection: an upwind row with a constant velocity sums to zero off its
# shift (`A` stays row dominant, so `1/s` holds, but not the face's tridiagonal);
# `:advection` when the velocity varies by site (a compressive row is not dominant) or with
# advection and no decay.
function _steady_gain(b::StabilityBound, i, p)
    an = b.anchors[i]
    g = 0.0
    for r in b.rows[i]
        s = max(0.0, -sum((_hi(f, p) for f in r.linear); init = 0.0))
        D = sum((_lo(f, p) for f in r.diffusion); init = 0.0) +
            sum(
            (max(_lo(f[1], p), 0.0) * max(_lo(f[2], p), 0.0) for f in r.sitediffusion);
            init = 0.0
        )
        best = s > 0 ? 1 / s : Inf
        if !isempty(r.advection)
            (s > 0 && all(f -> _constant(first(f)), r.advection)) || return :advection
            g = max(g, best)
            continue
        end
        if an !== nothing && D > 0
            for a in unique(first.(an))
                w, n = D * b.invh2[i][a], b.dims[i][a]
                d = fill(s + 2w, n)
                anchored = false
                for (side, k) in ((-1, 1), (1, n))
                    j = findfirst(x -> x[1] == a && x[2] == side, an)
                    if j !== nothing && an[j][4] === nothing
                        # a face whose α or β varies by site or in time: its
                        # smallest diagonal over the sites from the start on (no bound: no
                        # gain)
                        q = an[j][3](p)[1]
                        isnan(q) && return nothing
                    else
                        α, β = if j === nothing
                            (0.0, 0.0)
                        else
                            (_cv(an[j][3], p), _cv(an[j][4], p))
                        end
                        # the ghost rule's diagonal (Dirichlet 2, no flux 0)
                        q = α == 0 ? 0.0 : α / (α / 2 + β)
                    end
                    q < 0 && return nothing
                    anchored |= q > 0
                    d[k] += w * q - w
                end
                anchored && (best = min(best, maximum(_tridiag_ones(d, w))))
            end
        end
        g = max(g, best)
    end
    return g
end
# The response of a steady group's fields to a unit lagged input: `X = (I − M)⁻¹ (G ∘ e)`,
# `M = diag(G) k` (`k` the group's reads of its own fields), when `I − M` is an M-matrix
# (every pivot of its elimination without pivoting positive, which for a Z-matrix is `ρ(M) <
# 1`); `nothing` when it is not (the group's own couplings are too strong for this bound)
function _steady_response(G::Vector{Float64}, e::Vector{Float64}, k::Matrix{Float64})
    n = length(G)
    A = [(i == j ? 1.0 : 0.0) - G[i] * k[i, j] for i in 1:n, j in 1:n]
    x = G .* e
    for c in 1:n
        A[c, c] > 1.0e-12 || return nothing
        for r in (c + 1):n
            m = A[r, c] / A[c, c]
            m == 0 && continue
            A[r, c:n] .-= m .* A[c, c:n]
            x[r] -= m * x[c]
        end
    end
    for r in n:-1:1
        x[r] = (x[r] - sum((A[r, j] * x[j] for j in (r + 1):n); init = 0.0)) / A[r, r]
    end
    return all(v -> isfinite(v) && v >= 0, x) ? x : nothing
end
# the solution of the tridiagonal system with diagonal `d`, off-diagonal `−w` and right side
# 1
function _tridiag_ones(d::Vector{Float64}, w::Float64)
    n = length(d)
    c, x = zeros(n), ones(n)
    c[1], x[1] = -w / d[1], 1 / d[1]
    for k in 2:n
        m = d[k] + w * c[k - 1]
        k < n && (c[k] = -w / m)
        x[k] = (1 + w * x[k - 1]) / m
    end
    for k in (n - 1):-1:1
        x[k] -= c[k] * x[k + 1]
    end
    return x
end

# The QuasiSteady gain in the coupling rule (`Problems.steady_loop_rates`): a steady group
# `q` answers its lagged inputs at once. Each of its fields `i` (row gain `G_i`,
# `_steady_gain`) reads the loop's other groups with a row sum `e_i` and the group's own
# fields `j` with `k_ij` (the group's rows solved together, or one by one in the order of
# their reads; either way its steady state), so `|δq_i| ≤ G_i (e_i |δu| + Σ_j k_ij
# |δq_j|)`: with `M = G k` (`M_ij = G_i k_ij`) of spectral radius below 1 (`I − M` an
# M-matrix), the response of field `i` is at most `X_i |δu|`, `X = (I − M)⁻¹ (G ∘ e)` (one
# field reading nothing of its group: `X = G e`). A group `g` of the loop that is not steady
# reads field `j` of `q` with coefficient `k_in`, so its lagged rate is `Σ k_in X_j` over
# its reads of steady fields plus its own reads of the other groups (`κ_QS = dt Σ k_in k_out
# / s_min` when the gain is the decay's). The rule does not bound a steady group that reads
# a steady field of another steady group of the loop, a group whose own couplings make `ρ(M)
# ≥ 1`, nor a term it cannot see: `why` names that, and the loop is refused.
function Problems.steady_loop_rates(b::StabilityBound, groups, p, steady, loops)
    n = length(groups)
    gof = Dict{String, Int}(k => g for (g, ks) in enumerate(groups) for k in ks)
    rowof = Dict{String, Int}(k => i for (i, k) in enumerate(b.keys))
    function terms(r, i)
        return Iterators.flatten(
            (
                ((f, j, f(p)) for (f, j) in r.crosslinear if j != 0),
                (
                    (f, j, f(p) * (4 * sum(b.invh2[j]) + _face_excess(b, j, p)))
                        for (f, j) in r.crossdiffusion if j != 0
                ),
            )
        )
    end
    G, K = zeros(n), zeros(n)
    # each steady field's response per unit lagged input
    X = Dict{String, Float64}()
    why = Any[nothing for _ in 1:n]
    for h in 1:n
        steady[h] && !isempty(loops[h]) || continue
        ks = groups[h]
        nk = length(ks)
        Gi, ei, kin = zeros(nk), zeros(nk), zeros(nk, nk)
        for (a, k) in enumerate(ks)
            i = get(rowof, k, 0)
            i == 0 && (why[h] = (:unseen, k, ""); continue)
            k in b.crossunseen && why[h] === nothing && (why[h] = (:unseen, k, ""))
            gi = _steady_gain(b, i, p)
            gi === nothing && why[h] === nothing && (why[h] = (:robin, k, ""))
            gi === :advection && why[h] === nothing && (why[h] = (:advection, k, ""))
            gi isa Real && (Gi[a] = gi; G[h] = max(G[h], gi))
            for r in b.rows[i]
                tot = 0.0
                own = zeros(nk)
                for (f, j, v) in terms(r, i)
                    hj = get(gof, b.keys[j], 0)
                    (hj == 0 || !(hj in loops[h])) && continue
                    if hj == h                  # (the group's own field: solved with it)
                        own[findfirst(==(b.keys[j]), ks)] += v
                    elseif steady[hj]
                        why[h] === nothing && (why[h] = (:steady, k, b.keys[j]))
                    else
                        tot += v
                    end
                end
                (isfinite(tot) && all(isfinite, own)) || why[h] !== nothing ||
                    (why[h] = (:coef, k, ""))
                ei[a] = max(ei[a], tot)
                kin[a, :] .= max.(kin[a, :], own)
                K[h] = max(K[h], tot)
            end
        end
        isfinite(G[h]) || why[h] !== nothing || (why[h] = (:island, first(ks), ""))
        why[h] === nothing || continue
        xs = _steady_response(Gi, ei, kin)
        xs === nothing && (
            why[h] = (
                :coupled, first(ks),
                join(
                    [
                        k
                            for (a, k) in enumerate(ks)
                            if any(!iszero, kin[a, :]) ||
                            any(!iszero, kin[:, a])
                    ], "`, `"
                ),
            ); continue
        )
        for (a, k) in enumerate(ks)
            X[k] = xs[a]
        end
    end
    out = map(1:n) do g
        l = loops[g]
        base = (;
            rate = 0.0, row = "", other = "", text = "", raw = "",
            gain = 0.0, kout = 0.0, qs = "", why = nothing,
        )
        (isempty(l) || !any(h -> steady[h], l)) && return base
        all(h -> steady[h], l) && return (; base..., why = (:steady_only, "", ""))
        w = something(
            (why[h] for h in l if steady[h] && why[h] !== nothing)...,
            Some(nothing)
        )
        w === nothing || return (; base..., why = w)
        steady[g] && return base
        any(k -> k in b.crossunseen, groups[g]) && return (;
            base...,
            why = (:unseen, first(k for k in groups[g] if k in b.crossunseen), ""),
        )
        q = base
        for k in groups[g]
            i = get(rowof, k, 0)
            i == 0 && continue
            for r in b.rows[i]
                tot, worst, best = 0.0, -Inf, nothing
                for (f, j, v) in terms(r, i)
                    hj = get(gof, b.keys[j], 0)
                    (hj == 0 || hj == g || !(hj in l)) && continue
                    c = steady[hj] ? v * X[b.keys[j]] : v
                    tot += c
                    (best === nothing || (isfinite(worst) && !(c <= worst))) &&
                        (worst = c; best = (f, j, hj))
                end
                best === nothing && continue
                isfinite(q.rate) && !(tot <= q.rate) || continue
                f, j, hj = best
                # (the message's gain: the field's response over its group's largest read of
                # the loop)
                kq = steady[hj] ? K[hj] : 0.0
                gain = if !steady[hj]
                    0.0
                elseif kq > 0
                    X[b.keys[j]] / kq
                else
                    G[hj]
                end
                q = (;
                    q..., rate = tot, row = k, other = b.keys[j],
                    text = _coef_text(f.text), raw = f.text,
                    gain, kout = kq, qs = steady[hj] ? b.keys[j] : "",
                )
            end
        end
        isfinite(q.rate) || return (; q..., why = (:coef, q.row, q.other))
        return q
    end
    return out
end

# the rows on a loop of cross reads: row `i` reads row `j` through a cross term
# or through a coefficient bounded over `j`'s declared interval (a site multiplier, a face
# coefficient `K`, a velocity), and `j` reads `i` back, directly or through other
# rows. A row off every loop sits in a block triangular Jacobian, whose eigenvalues are
# those of the rows' own blocks, so its cross terms need no dominance test (a loop such as
# `c' = a o, o' = −a c` can make them complex)
function _loop_rows(b::StabilityBound)
    n = length(b.keys)
    out = [Set{Int}() for _ in 1:n]
    for i in 1:n, r in b.rows[i]
        for (_, j) in Iterators.flatten((r.crosslinear, r.crossdiffusion))
            (j == 0 || j == i) || push!(out[i], j)
        end
        for f in Iterators.flatten(
                    (
                        r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion),
                        r.linear,
                        first.(r.crosslinear), first.(r.crossdiffusion),
                        first.(r.advection),
                    )
                ),
                (nm, _) in f.box

            for j in 1:n
                j != i && (b.keys[j] == nm || startswith(b.keys[j], nm * "[")) &&
                    push!(out[i], j)
            end
        end
    end
    function reaches(a, z)
        seen, todo = Set{Int}(), [a]
        while !isempty(todo)
            q = pop!(todo)
            q == z && return true
            q in seen && continue
            push!(seen, q)
            append!(todo, out[q])
        end
        return false
    end
    return [any(j -> reaches(j, i), out[i]) for i in 1:n]
end
"""
    bound_parts(b::StabilityBound, p) -> (; ρ, seen, coupled, negative, nonfinite, worst)

The parts of `b(p)`: `ρ`, the Gershgorin bound over the terms `b` sees (a term in
`b.terms` is left out); `seen`, the same bound over the finite values of each coefficient
only (a coefficient over the evaluation cap counts 0; `seen == ρ` when `ρ` is finite), which
raises an explicit count; `coupled`, the keys of the rows on a loop of cross reads with
cross terms that are not diagonally dominant with a nonpositive diagonal (`b(p)` is `NaN`
for them); `negative`, the keys of the rows with a diffusion coefficient below zero at `p`
(at some indicator assignment); `nonfinite`, when `ρ` is not finite, a
`(key, coefficient, why)` per coefficient with no finite bound (`why`: `:cap` over the
evaluation cap, `:tables` no tables given, or `(combos, more)`: up to 4 distinct read
combinations `[(table, index, value), …]` with a value that is not finite, index 0 reading
0, and how many more); `worst`, the row that gives `ρ` and its parts
`(; key, diffusion, advection, reaction, cross)` (diffusion with its faces, upwind
advection, the reaction terms of the row's own field, the terms that read other fields; they
sum to `ρ`), or `nothing` with no row. `b(p) == ρ` when `b.unbounded` and `coupled` are
empty.
"""
function bound_parts(b::StabilityBound, p)
    ρ = seen = 0.0
    worst = nothing
    coupled, negative = String[], String[]
    loop = _loop_rows(b)
    # interval diffusion coefficients of unknown sign
    unsure = Tuple{String, String, Any}[]
    for i in eachindex(b.keys)
        ih2 = b.invh2[i]                        # (the row's grid)
        s4 = 4 * sum(ih2)
        # each choice of the row's switch arms is a row of its own: the bound is the worst,
        # and the row is coupled when any choice is not diagonally dominant
        for r in b.rows[i]
            # a diffusion coefficient below zero is refused; an interval coefficient only
            # when its enclosure is below zero everywhere: an enclosure that holds 0 inside
            # does not show a negative value (it encloses), so that coefficient has no bound
            # instead
            neg(f) = _lo(f, p) < 0 && (isempty(f.box) || _hi(f, p) < 0)
            (any(neg, r.diffusion) || any(f -> neg(f[1]) || neg(f[2]), r.sitediffusion)) &&
                push!(negative, b.keys[i])
            for f in Iterators.flatten(
                    (
                        r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion),
                    )
                )
                isempty(f.box) || neg(f) || !(_lo(f, p) < 0) ||
                    any(x -> x[1] == b.keys[i] && x[2] == f.text, unsure) ||
                    push!(unsure, (b.keys[i], f.text, _Unsure(f.box, _lo(f, p), f.ghosts)))
            end
            # a site-varying multiplier m and a face coefficient K are bounded
            # independently, max|m| · max K: a face mixes two sites' indices
            Dmag = sum(f(p) for f in r.diffusion; init = 0.0) +
                sum(_sd(f, p) for f in r.sitediffusion; init = 0.0)
            # upwind advection: each axis's faces give the row `|m v_a| / h_a` twice at
            # most, `Σ_a 2 max|m v_a| / h_a`
            adv = sum(2 * f(p) * sqrt(ih2[a]) for (f, a) in r.advection; init = 0.0)
            dif = Dmag * (s4 + _face_excess(b, i, p))
            own = dif + adv
            lin = sum(f(p) for f in r.linear; init = 0.0)
            cross = sum(f(p) for (f, _) in r.crosslinear; init = 0.0) +
                sum(
                f(p) * (4 * sum(b.invh2[j]) + _face_excess(b, j, p))
                    for (f, j) in r.crossdiffusion;
                init = 0.0
            )
            if loop[i] && (!isempty(r.crosslinear) || !isempty(r.crossdiffusion))
                # the diagonal at its largest over the indicator assignments. A row of `M A`
                # (site diffusion) is balanced: its diagonal m_i Σ K / h² equals its
                # off-diagonal sum, so the same bound enters both sides and cancels (the row
                # test is the rest of the row: the reaction against the cross terms and the
                # Robin faces)
                diag = -2 * sum(ih2) *
                    (
                    sum(_lo(f, p) for f in r.diffusion; init = 0.0) +
                        sum(_sd(f, p) for f in r.sitediffusion; init = 0.0)
                ) +
                    sum(_hi(f, p) for f in r.linear; init = 0.0)
                # advection's part of the row test: its off-diagonal sum past its diagonal
                # is the discrete compression `−∇·v`, at most `max|m v_a| / h_a` per axis
                # for a constant velocity (a row at a closed face) and `2 max|m v_a| / h_a`
                # otherwise
                short = sum(
                    (_constant(f) ? 1 : 2) * f(p) * sqrt(ih2[a])
                        for (f, a) in r.advection; init = 0.0
                )
                offd = Dmag * (s4 / 2 + _face_excess(b, i, p)) + cross + short
                diag <= 0 && -diag >= offd || push!(coupled, b.keys[i])
            end
            # (the row that gives ρ, and its parts: the report's split)
            (worst === nothing || own + lin + cross > ρ) &&
                (
                worst = (;
                    key = b.keys[i], diffusion = dif,
                    advection = adv, reaction = lin, cross,
                )
            )
            ρ = max(ρ, own + lin + cross)
            # the same over the finite values only (a term over the cap counts 0, an axis
            # whose face excess is not finite counts 0): every row, term and field that has
            # a bound still raises an explicit count, and a part that is not finite never
            # drops the rest of its row
            Ds = sum(_seen(f, p) for f in r.diffusion; init = 0.0) +
                sum(_sdseen(f, p) for f in r.sitediffusion; init = 0.0)
            sv = Ds * (s4 + _face_excess_seen(b, i, p)) +
                sum(_seen(f, p) for f in r.linear; init = 0.0) +
                sum(2 * _seen(f, p) * sqrt(ih2[a]) for (f, a) in r.advection; init = 0.0) +
                sum(_seen(f, p) for (f, _) in r.crosslinear; init = 0.0) +
                sum(
                _seen(f, p) * (4 * sum(b.invh2[j]) + _face_excess_seen(b, j, p))
                    for (f, j) in r.crossdiffusion;
                init = 0.0
            )
            seen = max(seen, sv)
        end
    end
    isempty(unsure) || (ρ = NaN)
    nonfinite = Tuple{String, String, Any}[]
    append!(nonfinite, unsure)
    if !isfinite(ρ)
        for i in eachindex(b.keys), r in b.rows[i]
            for f in Iterators.flatten(
                    (
                        r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion),
                        r.linear,
                        first.(r.crosslinear), first.(r.crossdiffusion),
                        first.(r.advection),
                    )
                )
                w = _why(f, p)
                # a read at index 0: the first site where it is (from the host input arrays)
                w isa Tuple && any(c -> any(x -> x[2] == 0, c), w[1]) &&
                    (w = (w..., _zero_site(f, p)))
                w === nothing || any(x -> x[1] == b.keys[i] && x[2] == f.text, nonfinite) ||
                    push!(nonfinite, (b.keys[i], f.text, w))
            end
        end
    end
    if !isfinite(ρ)
        for i in eachindex(b.keys), (_, f, where) in b.sitefaces[i]
            isnan(f(p)[1]) && push!(nonfinite, (b.keys[i], where, :robin))
        end
    end
    return (;
        ρ, seen, coupled = unique!(coupled),
        negative = unique!(negative), nonfinite, worst,
    )
end

# why an interval diffusion coefficient has no bound: its enclosure over the intervals it
# reads (`box`) reaches `lo < 0`, so its sign is not known
struct _Unsure
    box::Vector{Tuple{String, Tuple{Float64, Float64}}}
    lo::Float64
    ghosts::Vector{String}                  # the face ghost values the bound also takes
end
# why an interval coefficient has no finite bound (`_why`): its enclosure over `box` is not
# finite
struct _IntervalWhy
    box::Vector{Tuple{String, Tuple{Float64, Float64}}}
end
# a coefficient with one value at every site and index: no table read, no indicator, no
# interval
_constant(f::CoefBound) = isempty(f.reads) && isempty(f.box) && length(f.fs) == 1

# the declared bounds `(lo, hi)` of a scalar input (`bounds` metadata); `(-Inf, Inf)`
# without them or for an array input
function _input_bounds(v)
    b = ModelingToolkitBase.getbounds(v)
    return b[1] isa Real && b[2] isa Real ? (Float64(b[1]), Float64(b[2])) : (-Inf, Inf)
end
_input_lower(v) = first(_input_bounds(v))

# the intervals an interval coefficient reads, in words: `x ∈ [-0.03125, 1.031]` (the
# coordinates over the lattice's sites and one ghost layer, a field or input over its
# declared bounds)
function _box_text(box)
    return join(
        (
            string(
                "`", k, "` ∈ [", round(b[1]; sigdigits = 4),
                ", ", round(b[2]; sigdigits = 4), "]"
            )
                for (k, b) in box
        ), ", "
    )
end
# why a coefficient has no finite bound, in words (`_why`)
function _why_text(text, w)
    w === :cap && return "`$text` reads more than $(_MAXEVALS) table index combinations"
    w === :tables && return "`$text` reads tables that were not given"
    w === :robin && return string(
        "the Robin coefficients α and β of ", text,
        " give the ghost value no finite bound ",
        "(α/2 + β/h may vanish at a site, or a coefficient has no finite bound in time)"
    )
    w isa _IntervalWhy &&
        return string("`$text` has no finite bound over ", _box_text(w.box))
    if w isa _Unsure
        ghosts = if isempty(w.ghosts)
            ""
        else
            string(
                " and at the ghost values of the faces with a value or a flux (",
                join(w.ghosts, ", "), ", where a face coefficient reads the field)"
            )
        end
        return string(
            "the diffusion coefficient `$text` may be negative over ", _box_text(w.box),
            ghosts, " (its interval bound reaches ", round(w.lo; sigdigits = 4),
            "), and the bound needs it ≥ 0"
        )
    end
    combos, more = w
    all(isempty, combos) && return "`$text` is not finite at these parameters"
    site = length(w) >= 3 ? w[3] : nothing
    # with no site, the index's interval (its declared bounds, an `ifelse` hull) holds 0 and
    # no site value says otherwise: the bound is conservative there
    function read(t, i)
        if i == 0
            if site === nothing
                return "index 0 of `$t` (the index's interval holds 0; no site value is \
                    known, so this is conservative)"
            else
                return "index 0 of `$t` (at site $site)"
            end
        else
            return "`$t[$i]`"
        end
    end
    return string(
        "`$text` is not finite at ", join(
            (join((read(t, i) for (t, i, _) in c), " with ") for c in combos), ", at "
        ),
        more > 0 ? " (and $more more)" : ""
    )
end
# what to change about an entry that makes a coefficient not finite, by its value
function _entry_fix(v)
    if v == 0
        return "make it nonzero (a zero entry: a division by it is not finite)"
    elseif v < 0
        return "make it ≥ 0 (a negative entry under `sqrt` or `log` is not finite)"
    else
        return "give it a value where the coefficient is finite"
    end
end
# the route for a coefficient that is not finite: fix each entry it names, keep 0 out of an
# index that reaches 0
function _why_route(w)
    w isa Tuple || return ""
    rd = unique(reduce(vcat, w[1]; init = Tuple{String, Int, Float64}[]))
    isempty(rd) && return "; give its parameters values that make it finite"
    parts = String[]
    any(x -> x[2] == 0, rd) && push!(
        parts, "index 0 reads 0 (an input value 0, or a literal 0), and the " *
            "coefficient is not finite there: keep 0 out of the index (write no 0 " *
            "into the input, or declare it `bounds = (1, n)`)"
    )
    for (t, i, v) in rd
        i == 0 || push!(parts, "for `$t[$i]` ($v), $(_entry_fix(v))")
    end
    return "; " * join(parts, "; ")
end

# The intervals of the interval bound, as `(term, (lo, hi),
# name)`: each coordinate over the lattice's cell centers (`ghost = false`: a value at the
# site), or with one ghost layer (`ghost = true`: a face coefficient or a velocity reads a
# site past a face of the box, `[lo − h/2, hi + h/2]`), and each state, aux or input field
# with declared finite `bounds = (lo, hi)`. A declared interval is a statement about the
# field's values: the bound holds while the field stays inside it (the docs say so)
function _bound_box(
        cf::CompiledField{N}, sys::PDESystem; ghost::Bool,
        axes = ntuple(_ -> true, N)
    ) where {N}
    box = Tuple{Any, Tuple{Float64, Float64}, String}[]
    ends = _domain_ends(sys)
    ivs = unwrap.(get_ivs(sys))
    h = cf.program.spacing
    # the ghost sites lie half a spacing past the box on the coarsest grid a field lives on
    # (a `Coarse` field's ghost is `k h / 2` out); the fine centers enclose every grid's
    hg = level_spacing(
        h, Int.(Tuple(cf.program.hierarchy[1].grid.dims)), length(cf.program.hierarchy) -
            1
    )
    for (a, v) in enumerate(ivs[(end - N + 1):end])
        lo, hi = ends[length(ivs) - N + a]
        g = ghost && axes[a]
        push!(
            box, (
                v, g ? (lo - hg[a] / 2, hi + hg[a] / 2) : (lo + h[a] / 2, hi - h[a] / 2),
                string(v),
            )
        )
    end
    for v in unwrap.(get_dvs(sys))
        b = _declared_bounds(v)
        b === nothing || push!(box, (v, b, _fieldname(v)))
    end
    return box
end
# The axes whose faces carry a flux that reads the coefficient past the face: a face
# with a value or a flux (Dirichlet, Robin, a Neumann flux). On an axis whose faces
# are all zero flux or periodic, a face coefficient at the boundary multiplies a zero
# difference (or reads the other side's center), so a diffusion coefficient is bounded over
# the centers
function _ghost_axes(cf::CompiledField{N}) where {N}
    s = cf.program
    return ntuple(
        a -> !s.periodic[a] && any(
            r -> r isa FaceRule && Int(r.axis) == a &&
                !(r.alpha.value == 0 && r.g.value == 0 && r.gfield == 0), s.rules
        ), N
    )
end
# the declared finite bounds of a scalar dependent variable, or nothing
function _declared_bounds(v)
    ModelingToolkitBase.hasbounds(v) || return nothing
    b = ModelingToolkitBase.getbounds(v)
    (b[1] isa Real && b[2] isa Real && isfinite(b[1]) && isfinite(b[2]) && b[1] <= b[2]) ||
        return nothing
    return (Float64(b[1]), Float64(b[2]))
end
_fieldname(v) = (u = unwrap(v); iscall(u) ? string(nameof(operation(u))) : string(u))
# the spatial operator call of a term `± m · Op(…) / d` (`laplacian`, `DivKGrad`, `Advect`,
# a `Differential`), when it is the term's one operator and a factor of it; else nothing
function _isop(y)
    return iscall(y) && (
        f = operation(y);
        f === laplacian || f isa DivKGrad || f isa Advect || f isa Differential
    )
end
_has_op(u) = iscall(u) && (_isop(u) || any(x -> _has_op(unwrap(x)), arguments(u)))
function _op_factor(u)
    _isop(u) && return u
    iscall(u) || return nothing
    f, a = operation(u), arguments(u)
    if f === (*)
        k = findall(x -> _has_op(unwrap(x)), a)
        return length(k) == 1 ? _op_factor(unwrap(a[k[1]])) : nothing
    elseif f === (/)
        return _has_op(unwrap(a[2])) ? nothing : _op_factor(unwrap(a[1]))
    elseif f === (-) && length(a) == 1
        return _op_factor(unwrap(a[1]))
    end
    return nothing
end
# whether the operator call `opc` acts on the field read `c` (its operand)
function _op_operand_is(opc, c)
    f, a, o = operation(opc), arguments(opc), _ref(c)
    f === laplacian && return _isread(a[1], o)
    f isa DivKGrad && return _isread(a[end], o)
    f isa Advect && return _isread(a[2], o)
    r = _raw_flux(opc)
    return r !== nothing && _isread(r[2], o)
end
# whether a term reads anything away from its site: a spatial operator, a site read
# `value_at(c, i)` of a field, a `Shift`
function _has_spatial(u)
    iscall(u) || return false
    f = operation(u)
    # a field or input read at the site
    f isa SymbolicUtils.BasicSymbolic && return false
    (
        f === laplacian || f === value_at && iscall(unwrap(arguments(u)[1])) ||
            !(f isa Function)
    ) && return true
    return any(x -> _has_spatial(unwrap(x)), arguments(u))
end

"""
    stability_bound(cf::CompiledField, sys) -> StabilityBound

The [`StabilityBound`](@ref) of the rate fields of `cf`; call it with a parameter vector.
"""
function stability_bound(cf::CompiledField{N}, sys::PDESystem) where {N}
    ks = sort!(collect(keys(cf.linearity)))
    # the clock's slot is not a value fixed at bind (rule 3): as the time `t`,
    # a coefficient that reads it is a term the bound cannot see, and an `ifelse` gate on it
    # is bounded through both arms; a stand-in that no coefficient can read keeps the slots
    params = Any[
        _isclock(q) ? unwrap(Symbolics.variable(:__clock_slot)) : q
            for q in cf.params
    ]
    states = Set(_states(cf.program))
    # state key → its term (inputs and aux are not rows)
    dvs = Dict{String, Any}()
    for v in get_dvs(sys), (op, kk) in cf.keys
        isequal(_opof(v), op) || continue
        u = unwrap(v)
        for (i, k) in enumerate(kk)
            k in states && (dvs[k] = length(kk) == 1 ? u : unwrap(Symbolics.wrap(u)[i]))
        end
    end
    stateops = unique([_opof(v) for v in values(dvs)])
    # (an array field by its components)
    staterefs = unique([_ref(v) for v in values(dvs)])
    others = [v for v in unwrap.(get_dvs(sys)) if !any(o -> isequal(o, _opof(v)), stateops)]
    inputops = unique([_opof(v) for v in others if ModelingToolkitBase.isinput(v)])
    # `K ~ expr` fields
    auxops = unique([_opof(v) for v in others if !ModelingToolkitBase.isinput(v)])
    unknownops = [staterefs; auxops]
    rows = Vector{RowTerms}[]
    faces, unbounded, terms, expanded = Vector{Tuple{Int, Coef, Coef}}[],
        String[], String[], String[]
    anchors = Any[]
    sitefaces = Vector{Tuple{Int, Any, String}}[]
    pidx = Dict{Any, Int}(unwrap(q) => i for (i, q) in enumerate(params))
    ivs, ends = unwrap.(get_ivs(sys)), _domain_ends(sys)
    # (the start time)
    window = TimeSpan(Float64(ends[1][1]), Float64(ends[1][1]), nothing)
    timed = any(
        sc -> any(x -> x !== nothing && _reads_term(x, ivs[1]), sc),
        values(cf.sitecoefs)
    )
    crossunseen = String[]
    unseenreads = Tuple{String, String, Vector{String}}[]
    # the array parameters (tables) by their symbols: a coefficient may read them
    tabs = Dict{Any, String}(
        unwrap(q) => string(unwrap(q))
            for q in _params(sys)
            if string(unwrap(q)) in first.(cf.tables)
    )
    # the scalar inputs with their keys and declared bounds: an index expression's interval
    # is taken over these and over the current values a host-written input carries
    ivars = Tuple{Any, String, Tuple{Float64, Float64}}[]
    for v in unwrap.(get_dvs(sys))
        ModelingToolkitBase.isinput(v) || continue
        op = _opof(v)
        vk = get(cf.keys, op, nothing)
        vk === nothing || length(vk) != 1 || push!(ivars, (v, only(vk), _input_bounds(v)))
    end
    box = _bound_box(cf, sys; ghost = true)      # (a velocity, a cross diffusion)
    # (a value at the site: a multiplier, a local coefficient)
    cbox = _bound_box(cf, sys; ghost = false)
    # (a face coefficient of a row's own diffusion)
    kbox = _bound_box(cf, sys; ghost = true, axes = _ghost_axes(cf))
    # a face coefficient at a face with a value or a flux reads the rate fields at their
    # ghost values: its bound is over the coefficient at the site and at each face's ghost
    frules = Dict{Tuple{String, Int, Int}, FaceRule}()
    for r in cf.program.rules
        r isa FaceRule &&
            (frules[(cf.program.fields[r.field].key, Int(r.axis), Int(r.side))] = r)
    end
    function facecoef(K)
        return _face_coef_bound(
            K, dvs, frules, params, tabs, ivars, kbox, cf.program.periodic
        )
    end
    # the aux definitions `K ~ rhs`: a term that reads an aux field is bounded through its
    # definition, as the aux kernel evaluates it inside the substep from the state before it
    auxdefs = Dict{Any, Any}()
    for eq in get_eqs(sys)
        l = unwrap(eq.lhs)
        iscall(l) && any(o -> isequal(o, operation(l)), auxops) &&
            (auxdefs[l] = unwrap(eq.rhs))
    end
    for k in ks
        # one term added to every alternative of the row: `false` when the bound cannot see
        # it. A switch `ifelse(cond, a, b)` whose condition reads no unknown field (a gate
        # such as `t ≥ t_relax`) doubles the alternatives: one with the terms of `a`, one
        # with those of `b` (each choice checked on its own: a decaying arm never certifies
        # a rotation in the other)
        function add!(alts, term, class, depth)
            fs = [kk for (kk, v) in dvs if _reads(term, (_ref(v),))]
            if class == :Diffusion
                c = _coef_bound(_diffusion_coefficient(term), params, tabs, ivars)
                # (a coefficient that reads the coordinates: the interval bound)
                c === nothing && return interval_term!(alts, term, depth)
                foreach(r -> push!(r.diffusion, c), alts)
            elseif class == :SiteDiffusion
                parts = _site_parts(term)
                parts === nothing && return false
                cm = _coef_bound(parts[1], params, tabs, ivars; box = cbox)
                cK = facecoef(parts[2])
                (cm === nothing || cK === nothing) && return false
                foreach(r -> push!(r.sitediffusion, (cm, cK)), alts)
            elseif class == :LinearLocal || class == :CrossLinear
                length(fs) == 1 || return false
                if class == :CrossLinear &&
                        _linclass(unwrap(term), _ref(dvs[fs[1]]), staterefs, inputops) ==
                        :Diffusion
                    j = findfirst(==(fs[1]), ks)
                    c = if j === nothing
                        nothing
                    else
                        _coef_bound(_diffusion_coefficient(term), params, tabs, ivars; box)
                    end
                    c === nothing && return false
                    foreach(r -> push!(r.crossdiffusion, (c, j)), alts)
                else
                    c = _coef_bound(
                        substitute(term, Dict(dvs[fs[1]] => 1); fold = Val(false)),
                        params, tabs, ivars; box = cbox
                    )
                    c === nothing && return false
                    if class == :CrossLinear
                        j = something(findfirst(==(fs[1]), ks), 0)
                        foreach(r -> push!(r.crosslinear, (c, j)), alts)
                    else
                        foreach(r -> push!(r.linear, c), alts)
                    end
                end
            elseif class == :Source
                return true
            else
                u = unwrap(term)
                # the condition reads no unknown (a state or an aux field of the states)
                if depth < 4 && iscall(u) && operation(u) === ifelse &&
                        !_reads(arguments(u)[1], unknownops)
                    out = RowTerms[]
                    ok = true
                    for arm in arguments(u)[2:3]
                        branch = map(copy, alts)
                        # classified as the rate's own terms: a term reading an aux field is
                        # Other
                        for (t2, c2) in linearity(
                                arm, _ref(dvs[k]), unknownops; inputs = inputops,
                                aux = auxops
                            )
                            add!(branch, t2, c2, depth + 1) || (ok = false; break)
                        end
                        ok || break
                        append!(out, branch)
                    end
                    if ok && length(out) <= _MAXARMS
                        empty!(alts)
                        append!(alts, out)
                        push!(expanded, "$k: $(term)")
                        return true
                    end
                end
                # the interval bound: through an aux field's definition, advection,
                # a diffusion whose coefficient reads the coordinates or a field with a
                # declared interval, or the Jacobian entries of a local term
                return depth < 8 && interval_term!(alts, term, depth)
            end
            return true
        end
        own = dvs[k]
        function interval_term!(alts, term, depth)
            u = unwrap(term)
            if _reads(u, auxops)
                v = u
                for _ in 1:8
                    _reads(v, auxops) || break
                    v = unwrap(substitute(v, auxdefs; fold = Val(false)))
                end
                _reads(v, auxops) && return false
                trial = map(copy, alts)
                for (t2, c2) in linearity(
                        v, _ref(own), unknownops; inputs = inputops, aux = auxops
                    )
                    add!(trial, t2, c2, depth + 1) || return false
                end
                empty!(alts)
                append!(alts, trial)
                return true
            end
            opc = _op_factor(u)
            if opc !== nothing && _op_operand_is(opc, own)
                m = unwrap(substitute(u, Dict(opc => 1); fold = Val(false)))
                f = operation(opc)
                if f isa Advect
                    # upwind advection `m Advect(v, c)`: the row's Gershgorin part is `Σ_a 2
                    # max|m v_a| / h_a`
                    comps = velocity_terms(unwrap(arguments(opc)[1]))
                    (comps === nothing || length(comps) != N) && return false
                    # a velocity or multiplier that reads the advected field (Burgers,
                    # `Advect([c, 0], c)`) stays unseen, as in the implicit operator: its
                    # flux Jacobian has the part `∂v/∂c · c`, central at the face mean, so
                    # its rows are not diagonally dominant and no step is certified from the
                    # frozen velocity (where `v` vanishes, as `[1 − c, 0]` at c = 1, forward
                    # Euler grows at any step)
                    (
                        _reads(m, (_ref(own),)) ||
                            any(ca -> _reads(ca, (_ref(own),)), comps)
                    ) && return false
                    cbs = [_coef_bound(m * comps[a], params, tabs, ivars; box) for a in 1:N]
                    any(isnothing, cbs) && return false
                    foreach(r -> append!(r.advection, [(cbs[a], a) for a in 1:N]), alts)
                    return true
                end
                # a diffusion `m Op(K, c)` with `m` or `K` reading the coordinates or a
                # field with a declared interval: the multiplier at the site and the face
                # coefficient bounded independently (the face mean mixes two sites), as a
                # site diffusion
                K = if f === laplacian
                    1
                elseif f isa DivKGrad
                    arguments(opc)[1]
                else
                    (r = _raw_flux(opc); r[1] === nothing ? 1 : r[1])
                end
                cm = _coef_bound(m, params, tabs, ivars; box = cbox)
                cK = facecoef(K)
                (cm === nothing || cK === nothing) && return false
                foreach(r -> push!(r.sitediffusion, (cm, cK)), alts)
                return true
            end
            # a local term (no spatial operator): its Jacobian entries `∂term/∂f` for each
            # field `f` it reads at the site, bounded over the intervals they read (a
            # switch's arms by its indicator; a nonlinear term over the declared interval of
            # its field)
            _has_spatial(u) && return false
            fs = [kk for (kk, v) in dvs if _reads(u, (_ref(v),))]
            isempty(fs) && return false
            parts = Tuple{CoefBound, Int}[]
            for kk in fs
                d = _local_derivative(u, dvs[kk])
                d === nothing && return false
                cb = _coef_bound(d, params, tabs, ivars; box = cbox)
                cb === nothing && return false
                push!(parts, (cb, kk == k ? -1 : something(findfirst(==(kk), ks), 0)))
            end
            for (cb, j) in parts
                if j == -1
                    foreach(r -> push!(r.linear, cb), alts)
                else
                    foreach(r -> push!(r.crosslinear, (cb, j)), alts)
                end
            end
            return true
        end
        alts = [RowTerms()]
        for (term, class) in cf.linearity[k]
            # a term the bound cannot see leaves the alternatives as they were
            trial = map(copy, alts)
            if add!(trial, term, class, 0)
                alts = trial
            else
                push!(unbounded, k)
                push!(terms, "$k: $(term)")
                # an unseen term that reads another unknown field (a state of another row,
                # or any aux field, which may carry any state) can couple field groups
                own = _ref(dvs[k])
                _reads(term, [op for op in unknownops if !isequal(op, own)]) &&
                    push!(crossunseen, k)
                push!(
                    unseenreads, (
                        k, "$k: $(term)", _state_reads(term, dvs, auxops, auxdefs),
                    )
                )
            end
        end
        push!(rows, alts)
        push!(
            faces, [
                (Int(r.axis), r.alpha, r.beta)
                    for r in cf.program.rules
                    if r isa FaceRule && cf.program.fields[r.field].key == k &&
                    !sitecoefs(r)
            ]
        )
        mine(r) = cf.program.fields[r.field].key == k
        # (a face whose α or β varies by site or in time anchors by its smallest diagonal
        # over the sites from the start time on: `(axis, side, f, nothing)`)
        function anchor(r)
            sitecoefs(r) || return (Int(r.axis), Int(r.side), r.alpha, r.beta)
            box = [cbox; (ivs[1], (Float64(ends[1][1]), Inf), "")]
            return (
                Int(r.axis), Int(r.side),
                _site_diag(cf, k, Int(r.axis), Int(r.side), pidx, tabs, box), nothing,
            )
        end
        edged = any(r -> r isa DomainEdgeRule && mine(r), cf.program.rules)
        if edged
            push!(anchors, nothing)
        else
            push!(
                anchors, Any[
                    anchor(r)
                        for r in cf.program.rules if r isa FaceRule && mine(r)
                ]
            )
        end
        push!(
            sitefaces, [
                (
                    a, _site_diag(
                        cf, k, a, sd, pidx, tabs, [cbox; (ivs[1], window, "")]
                    ),
                    string(
                        "the face ", ivs[end - N + a], " = ",
                        ends[length(ivs) - N + a][sd > 0 ? 2 : 1]
                    ),
                )
                    for (kk, a, sd) in sort!(collect(keys(cf.sitecoefs))) if kk == k
            ]
        )
    end
    declared = _declared_fields(cf, sys)
    # each row's grid (a `Coarse` field's: spacing `k h`)
    rlev(k) = cf.program.fields[fieldid(cf.program, k)].levels[1]
    fdims = Int.(Tuple(cf.program.hierarchy[1].grid.dims))
    return StabilityBound(
        [[1 / h^2 for h in level_spacing(cf.program.spacing, fdims, rlev(k))] for k in ks],
        ks, rows, faces,
        sort!(unique!(unbounded)), unique!(terms), unique!(expanded), _row_inputs(rows),
        sort!(unique!(crossunseen)),
        [collect(Int, leveldims(cf.program, rlev(k))) for k in ks], anchors, declared,
        _used_keys(
            rows, declared
        ),
        _face_values(cf, sys, declared), sitefaces, timed, window, unseenreads
    )
end
# the state fields a term reads (by key, sorted): its state reads, and through an aux field
# `K ~ rhs` the state fields its definition reads (an aux of an aux too)
function _state_reads(term, dvs, auxops, auxdefs, seen = Set{Any}())
    out = String[k for (k, v) in dvs if _reads(term, [_ref(v)])]
    for op in auxops
        (op in seen || !_reads(term, [op])) && continue
        push!(seen, op)
        for (l, r) in auxdefs
            isequal(operation(l), op) &&
                append!(out, _state_reads(r, dvs, auxops, auxdefs, seen))
        end
    end
    return sort!(unique!(out))
end

# The bound of a face coefficient `K`: at a face with a value or a flux the face
# mean reads each rate field at its ghost value, `2g/α − c` (Dirichlet), `c + g/β` (a flux)
# or `(g − (α/2 − β) c)/(α/2 + β)` (Robin), so the bound is over `K` at the site and `K`
# with those ghosts, each over the box (one `CoefBound` with both sets of values: its
# magnitude is the larger, its sign the lower). A zero-flux face's ghost is the site value;
# a face value that reads the time, the coordinates or an input (a value field) has no
# static ghost: no bound.
function _face_coef_bound(K, dvs, frules, params, tabs, ivars, box, periodic)
    c0 = _coef_bound(K, params, tabs, ivars; box)
    c0 === nothing && return nothing
    reads = [kk for (kk, v) in dvs if _reads(K, (_ref(v),))]
    isempty(reads) && return c0
    sym(c::Coef) = c.param == 0 ? c.value : c.value * params[c.param]
    out = c0
    for a in eachindex(periodic), sd in (-1, 1)
        periodic[a] && continue
        reps = Dict{Any, Any}()
        gtext = String[]
        for kk in reads
            r = get(frules, (kk, a, sd), nothing)
            r === nothing && continue
            (r.alpha.value == 0 && r.g.value == 0 && r.gfield == 0) && continue
            (r.gfield == 0 && !sitecoefs(r)) || return nothing
            c = dvs[kk]
            α, β, g = sym(r.alpha), sym(r.beta), sym(r.g)
            reps[c] = if r.beta.value == 0
                2g / α - c
            elseif r.alpha.value == 0
                c + g / β
            else
                (g - (α / 2 - β) * c) / (α / 2 + β)
            end
            push!(
                gtext,
                string(
                    "`", kk, "` → `",
                    replace(as_written(string(reps[c])), r"\(t(, \w+)*\)" => ""), "`"
                )
            )
        end
        isempty(reps) && continue
        cg = _coef_bound(substitute(K, reps; fold = Val(false)), params, tabs, ivars; box)
        cg === nothing && return nothing
        (cg.reads == out.reads && isequal(cg.groups, out.groups)) || return nothing
        out = CoefBound(
            [out.fs; cg.fs], out.reads, out.groups, out.text, sort!(
                unique!(
                    [
                        out.box;
                        cg.box
                    ]
                ); by = first
            ),
            unique!([out.ghosts; gtext])
        )
    end
    return out
end

# The state and aux fields with declared finite `bounds = (lo, hi)`, by key
function _declared_fields(cf::CompiledField, sys::PDESystem)
    out = Tuple{String, Tuple{Float64, Float64}}[]
    for v in unwrap.(get_dvs(sys))
        ModelingToolkitBase.isinput(v) && continue
        b = _declared_bounds(v)
        b === nothing && continue
        ks = get(cf.keys, _opof(v), nothing)
        (ks === nothing || length(ks) != 1) && continue
        push!(out, (only(ks), b))
    end
    return out
end
# the keys of `declared` whose interval a coefficient bound of `rows` read
function _used_keys(rows, declared)
    acc = String[]
    for alts in rows, r in alts
        for f in Iterators.flatten(
                    (
                        r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion),
                        r.linear,
                        first.(r.crosslinear), first.(r.crossdiffusion),
                        first.(r.advection),
                    )
                ),
                (k, _) in f.box

            any(d -> d[1] == k, declared) && push!(acc, k)
        end
    end
    return sort!(unique!(acc))
end
# The constant face and mask values of the fields with declared bounds: a
# Dirichlet or Robin face `α c + β ∂c/∂n = g` with α ≠ 0 holds the value `g/α` (a Robin face
# pulls the field to it), a masked condition its value. A value that reads the time, the
# coordinates or an input (a value field) is not constant: the run's check sees it
function _face_values(cf::CompiledField{N}, sys::PDESystem, declared) where {N}
    out = Tuple{String, String, Coef, Coef}[]
    isempty(declared) && return out
    s = cf.program
    ivs = unwrap.(get_ivs(sys))
    ends = _domain_ends(sys)
    for r in s.rules
        k = s.fields[r.field].key
        any(d -> d[1] == k, declared) || continue
        if r isa FaceRule && r.gfield == 0 && !sitecoefs(r) && r.alpha.value != 0
            a = Int(r.axis)
            e = ends[length(ivs) - N + a][r.side > 0 ? 2 : 1]
            push!(
                out,
                (
                    k,
                    string("its condition on the face `", ivs[end - N + a], " = ", e, "`"),
                    r.g,
                    r.alpha,
                )
            )
        elseif r isa NodeValueRule && r.vfield == 0
            push!(out, (k, "its masked condition", r.value, Coef(1.0)))
        end
    end
    return out
end

# initial values of the state fields, flat in `state` order, evaluated at cell centers in
# the state type `T`
function _initial(cf::CompiledField{N}, sys::PDESystem, state, ::Type{T}) where {N, T}
    ends = _domain_ends(sys)
    ivs = unwrap.(get_ivs(sys))
    vals = Dict{Any, Any}(p => d for (p, d) in zip(cf.params, cf.defaults) if !isnan(d))
    vals[ivs[1]] = ends[1][1]
    # a Dual initial value (a condition's or a default's) promotes the state, as a Dual `u0`
    # does
    E = foldl(
        (S, k) -> if haskey(cf.initial, k) && cf.initial[k] isa Real
            promote_dual(S, typeof(cf.initial[k]))
        else
            S
        end,
        state; init = T
    )
    out = E[]
    for k in state
        haskey(cf.initial, k) ||
            _dverr("field `$k` has no initial condition `$k(0, …) ~ value`")
        # (a `Coarse` field at its nodes' centers)
        dims = Int.(
            leveldims(cf.program, cf.program.fields[fieldid(cf.program, k)].levels[1])
        )
        v = cf.initial[k]
        if v isa Number
            append!(out, fill(E(v), prod(dims)))
            continue
        end
        e = substitute(v, vals; fold = Val(true))
        xs = ivs[2:end]
        free = [u for u in Symbolics.get_variables(e) if !any(x -> isequal(x, u), xs)]
        isempty(free) ||
            _dverr("the initial value of `$k` does not reduce to a number: `$v` \
                reads $(join(free, ", "))")
        # compiled once, not per site
        f = Symbolics.build_function(e, xs...; expression = Val(false))
        centers = ntuple(
            d -> T(ends[d + 1][1]) .+
                (T.(1:dims[d]) .- T(1) / 2) .*
                ((T(ends[d + 1][2]) - T(ends[d + 1][1])) / dims[d]), N
        )
        append!(out, vec([T(f(Tuple(I)...)) for I in Iterators.product(centers...)]))
    end
    return out
end

# The switches of the moving mask sets. A masked predicate that reads the time
# switches where one of its comparisons changes sign. A comparison (`<`, `≤`, `>`, `≥`)
# whose sides read only the time, scalar parameters and constants is an event `lhs - rhs` of
# `(p, t)`: an OrdinaryDiffEq solve locates its root (a continuous callback) and the masks
# take their values there. A predicate that reads the time in any other way (a comparison
# with a field, an input or a coordinate, an equality, a bare `t`) has no such event:
# `unlocated`. A read of `step_index(t)` switches at the clock's boundaries, which the
# clock's callback lands on.
function _mask_events(sys::PDESystem, ps, tt)
    evs, unlocated = Any[], false
    sym(y) = y isa SymbolicUtils.BasicSymbolic
    # `y` reads the time outside `step_index(t)` and outside a field read `c(t, x, y)`
    function bare(y)
        return isequal(y, tt) ||
            (
            iscall(y) && operation(y) !== step_index && !sym(operation(y)) &&
                any(bare, arguments(y))
        )
    end
    clocked(y) = iscall(y) && (operation(y) === step_index || any(clocked, arguments(y)))
    isp(v) = isequal(v, tt) || any(q -> isequal(q, v), ps)
    function walk(y)
        bare(y) || return true
        iscall(y) || return false
        op = operation(y)
        if op in (<, <=, >, >=)
            a, b = arguments(y)
            (clocked(y) || !all(isp, Symbolics.get_variables(y))) && return false
            push!(
                evs,
                Symbolics.build_function(unwrap(a - b), ps, tt; expression = Val(true))
            )
            return true
        end
        op in (&, |, !, xor) || return false
        return all(walk, arguments(y))
    end
    for eq in get_bcs(sys)
        r = unwrap(eq.rhs)
        iscall(r) && operation(r) === masked || continue
        walk(unwrap(arguments(r)[1])) || (unlocated = true)
    end
    return evs, unlocated
end

function _index(
        cf::CompiledField, sys::PDESystem, s, state; derived = Pair[], computed = Pair[],
        cdefaults = Pair[],
        free = nothing
    )
    slots = Problems.state_layout(s, [fieldid(s, k) for k in state])
    # a system with no time: each field also reads by its time-free term `c(x, y)`
    function alias(v, i, n)
        if free === nothing
            return ()
        else
            return (
                o = free[findfirst(w -> isequal(unwrap(w), unwrap(v)), get_dvs(sys))];
                (n == 1 ? unwrap(o) : unwrap(Symbolics.wrap(unwrap(o))[i]),)
            )
        end
    end
    # (a `Coarse` field's grid)
    dims(k) = Int.(leveldims(s, s.fields[fieldid(s, k)].levels[1]))
    vars, inputs, inputnames, boolinputs, inputbounds, aux = Pair[],
        Pair[], Pair[], String[], Pair[], Pair[]
    for v in get_dvs(sys), (op, ks) in cf.keys
        isequal(_opof(v), op) || continue
        for (i, k) in enumerate(ks)
            term = length(ks) == 1 ? unwrap(v) : unwrap(Symbolics.wrap(unwrap(v))[i])
            if ModelingToolkitBase.isinput(unwrap(v))
                # an input: its term, its key and (one component) the variable itself
                # … and its user-facing name (`lattice_input_name`), which messages print
                n = get_lattice_input_name(unwrap(v))
                n === nothing ||
                    (n = length(ks) == 1 ? n : "$n[$i]"; push!(inputnames, k => n))
                syms = if length(ks) == 1
                    Any[term, alias(v, i, 1)..., Symbol(k), op]
                else
                    Any[term, alias(v, i, 2)..., Symbol(k)]
                end
                n === nothing || push!(syms, Symbol(n))
                push!(inputs, Tuple(syms) => k)
                eltype(SymbolicUtils.symtype(unwrap(v))) <: Bool && push!(boolinputs, k)
                b = _input_bounds(unwrap(v))
                b == (-Inf, Inf) || push!(inputbounds, k => b)
            elseif k in state
                # (the bare callable `c` too, one component: `sol[c]`)
                push!(
                    vars, (
                        term, alias(v, i, length(ks))..., Symbol(k),
                        (length(ks) == 1 ? (op,) : ())...,
                    ) =>
                        FieldSlot(slots[fieldid(s, k)], dims(k))
                )
            elseif any(q -> q.key == "aux:$k", s.kernels)
                # an aux field `K ~ rhs`: read by `sol[K]` and `integ[K]`
                push!(
                    aux,
                    (
                        term, alias(v, i, length(ks))..., Symbol(k),
                        (length(ks) == 1 ? (op,) : ())...,
                    ) => k
                )
            end
        end
    end
    # (the clock's slot is the stepper's, not a parameter of the problem)
    # (a computed parameter holds a slot but is not a parameter: it is read-only)
    iscomp(p) = any(k -> isequal(unwrap(first(k)), unwrap(p)), cdefaults)
    params = [
        (p, Symbol(string(p))) => i
            for (i, p) in enumerate(cf.params) if !_isclock(p) && !iscomp(p)
    ]
    # a parameter's declared `bounds` (MTK metadata), checked at every write
    parambounds = Pair[
        i => b for (i, p) in enumerate(cf.params) if !_isclock(p)
            for b in (_input_bounds(unwrap(p)),) if b != (-Inf, Inf)
    ]
    defaults = Dict{Any, Any}(p => d for (p, d) in zip(cf.params, cf.defaults))
    # a computed parameter reads as its folded expression of the parameter slots (SII
    # observed)
    ps, tt = Any[unwrap(q) for q in cf.params], unwrap(get_ivs(sys)[1])
    observed = Pair[
        syms =>
            Symbolics.build_function(unwrap(e), ps, tt; expression = Val(true))
            for (syms, e) in computed
    ]
    # the computed slots: a derivation from the base slots and the tables
    # (every computed parameter is derived, so a chain through one without a slot evaluates;
    # slot 0: none)
    comp = Dict{Any, Any}(unwrap(k) => d for (k, d) in cdefaults)
    derive = nothing
    if any(q -> haskey(comp, unwrap(q)), cf.params)
        base = [
            (Symbol(string(q)), i)
                for (i, q) in enumerate(cf.params)
                if !haskey(comp, unwrap(q)) && !_isclock(q)
        ]
        tabs = [(Symbol(k), String(k)) for (k, _) in cf.tables]
        cks = collect(keys(comp))
        d = derivation(
            Symbol[first(b) for b in [base; tabs]], Pair[
                Symbol(string(k)) =>
                    comp[k]
                    for k in cks
            ]
        )
        function slot(k)
            i = findfirst(q -> isequal(unwrap(q), k), cf.params)
            return i === nothing ? 0 : i
        end
        derive = (d, Any[last(b) for b in [base; tabs]], Int[slot(k) for k in cks])
    end
    # the site centers of each spatial coordinate (`sol[x]`, `sol(t, x, y)`)
    ends, d0 = _domain_ends(sys), Int.(leveldims(s, 0))
    coordinates = Pair[
        (unwrap(q), Symbol(string(unwrap(q)))) =>
            range(
            ends[d + 1][1] +
                (ends[d + 1][2] - ends[d + 1][1]) / (2d0[d]);
            step = (ends[d + 1][2] - ends[d + 1][1]) / d0[d], length = d0[d]
        ) for (d, q) in enumerate(get_ivs(sys)[2:end])
    ]
    # the masks' switch times on an OrdinaryDiffEq solve
    maskevents, maskunlocated = _mask_events(sys, ps, tt)
    return LatticeIndex(;
        key = _symkey, variables = vars, parameters = params,
        independent_variables = [unwrap(get_ivs(sys)[1])], defaults, inputs, inputnames,
        boolinputs, inputbounds, derived,
        observed, parambounds, derive, aux, coordinates, maskevents, maskunlocated,
        tables = Pair[
            [
                Any[unwrap(q), Symbol(k)] => k for (k, _) in cf.tables
                    for q in _params(sys) if string(unwrap(q)) == k
            ];
            [
                e => (k, i) for (k, _) in cf.tables
                    for q in _params(sys) if string(unwrap(q)) == k
                    for (i, e) in enumerate(Symbolics.scalarize(unwrap(q)))
            ]
        ]
    )
end

# the declared defaults of the input fields (`dom(..)::Bool = true [input = true]`), as
# `key => value` pairs; an input without one has no value until it is given
function _input_defaults(cf::CompiledField, sys::PDESystem)
    out = Pair{String, Any}[]
    for v in get_dvs(sys)
        u = unwrap(v)
        ModelingToolkitBase.isinput(u) || continue
        op = _opof(u)
        d = if ModelingToolkitBase.hasdefault(u)
            ModelingToolkitBase.getdefault(u)
        elseif ModelingToolkitBase.hasdefault(op)
            ModelingToolkitBase.getdefault(op)
        else
            nothing
        end
        d === nothing && continue
        d = unwrap_const(unwrap(d))
        d isa Number ||
            _dverr("input `$(_name(op))`: its default `$d` is not a number (one value for \
                every site)")
        foreach(k -> push!(out, k => d), cf.keys[op])
    end
    return out
end

# Computed parameter defaults (`@parameters k2 = 2a`): the parameter
# stays a parameter slot of the program, read-only, and the problem's derivation
# (`derivation`, `_index`) fills it from the base parameters after every write. So a face or
# mask value may read it (`Dirichlet(g)` with `g = g1 + g2`). Returns the system (its field
# initial values that read a computed parameter take its expression), the `derived` messages
# of the index, `computed` (each computed parameter with its expression of base parameters,
# for reads) and the raw defaults (for the derivation).
function _fold_computed(sys::PDESystem)
    scalar(p) = !(SymbolicUtils.symtype(unwrap(p)) <: AbstractArray)
    comp = Dict{Any, Any}()
    ps, ic = _params(sys), _ics(sys)
    for p in ps
        u = unwrap(p)
        g = _icvalue(ic, u)
        scalar(u) && (g !== nothing || ModelingToolkitBase.hasdefault(u)) || continue
        d = unwrap_const(unwrap(g === nothing ? ModelingToolkitBase.getdefault(u) : g))
        d isa Number || (comp[u] = d)
    end
    isempty(comp) && return sys, Pair[], Pair[], Pair[]
    # resolve chains (`k3 = 2k2`, `k2 = 3a`) to expressions of plain parameters
    resolved = Dict{Any, Any}()
    for (k, e) in comp
        x = e
        for _ in 1:(length(comp) + 1)
            any(c -> _reads_term(x, c), keys(comp)) || break
            x = substitute(x, comp; fold = Val(false))
        end
        any(c -> _reads_term(x, c), keys(comp)) &&
            _dverr("the computed parameter `$k = $e` depends on itself")
        resolved[k] = x
    end
    plain = Set(unwrap(p) for p in ps if !haskey(comp, unwrap(p)))
    tabs = Set(unwrap(p) for p in ps if !scalar(p))
    for (k, e) in resolved
        free = [
            v
                for v in Symbolics.get_variables(e)
                if !(v in plain) && !(_tabof(v) in tabs) &&
                !any(iv -> isequal(iv, v), unwrap.(get_ivs(sys)))
        ]
        isempty(free) || _dverr(
            "the computed parameter `$k = $(comp[k])` reads " *
                "$(join(("`$f`" for f in free), ", ")), which " *
                "$(length(free) == 1 ? "is not a parameter" : "are not parameters") of " *
                "the system"
        )
    end
    sub(x) = substitute(x, resolved; fold = Val(false))
    symb(v) = v isa Union{Num, SymbolicUtils.BasicSymbolic}
    # field values read them too
    ic2 = Dict(k => (symb(v) ? sub(v) : v) for (k, v) in ic if !haskey(comp, k))
    derived = Pair[
        (k, Symbol(string(k))) =>
            _computed_message(k, comp[k], resolved[k], plain)
            for k in keys(comp)
    ]
    new = PDESystem(
        get_eqs(sys), get_bcs(sys), get_domain(sys), get_ivs(sys), get_dvs(sys), ps;
        name = nameof(sys),
        initial_conditions = merge(ic2, Dict(k => v for (k, v) in ic if haskey(comp, k)))
    )
    computed = Pair[(k, Symbol(string(k))) => e for (k, e) in resolved]
    return new, derived, computed, Pair[k => comp[k] for k in keys(comp)]
end
function _tabof(v)
    (u = unwrap(v); iscall(u) && operation(u) === getindex ? unwrap(arguments(u)[1]) : u)
end
# the refusal of a write of computed parameter `k`: its expression and inputs, the route
function _computed_message(k, e, resolved, _)
    ins = sort!(
        unique!(String[string(_tabof(v)) for v in Symbolics.get_variables(resolved)])
    )
    return string(
        "`", k, "` is computed from ", join(("`$i`" for i in ins), ", "), " (`", k, " = ",
        e,
        "`): set ", length(ins) == 1 ? "`$(only(ins))`" : "its inputs", "; for a fixed `",
        k,
        "`, declare it with a number (`@parameters ", k, " = v`)"
    )
end
_reads_term(x, v) = any(y -> isequal(y, v), Symbolics.get_variables(x))

# Values every problem needs before it runs: array parameters (tables) with a value of their
# declared size. Scalar parameters with no value are refused where the problem is stepped.
function _check_tables(cf::CompiledField, sys::PDESystem)
    for (k, vals) in cf.tables
        p = only(q for q in _params(sys) if string(unwrap(q)) == k)
        n = length(Symbolics.scalarize(unwrap(p)))
        isempty(vals) && _dverr(
            "the array parameter `$k` has no value (a table is not read as zeros): give " *
                "it a default, `@parameters $k[1:$n] = [v₁, …]`"
        )
        length(vals) == n ||
            _dverr("the array parameter `$k` is declared with $n entries; its default \
                has $(length(vals))")
    end
    return
end

# The parameter checks of LatticePDE's stability bound (LatticeFields hooks): negative
# diffusion is refused at every parameter value a problem steps with; an explicit substep
# count is raised to the bound over the terms the bound sees; the substep error names the
# terms the bound cannot see.
function Problems.check_parameters(b::StabilityBound, p)
    r = bound_parts(b, p)
    neg = r.negative
    isempty(neg) && return _check_finite(r)
    return _dverr(
        "the diffusion coefficient of the " *
            "field$(length(neg) == 1 ? "" : "s") $(join(("`$k`" for k in neg), ", ")) is " *
            "negative at these parameters (anti-diffusion: an ill-posed equation, unstable \
                at any step and with any solver); write the term with a coefficient ≥ 0 \
                (`D * laplacian(c)` with `D ≥ 0`; a decay is a reaction term `-k * c`)"
    )
end
# The declared intervals against the constant face and mask values: a value
# outside its field's declared bounds drives the field out of the interval the bound takes
function Problems.check_declared(b::StabilityBound, p)
    for (k, where, num, den) in b.facevals
        v = _cv(num, p) / _cv(den, p)
        i = findfirst(d -> d[1] == k, b.declared)
        i === nothing && continue
        lo, hi = b.declared[i][2]
        (isnan(v) || lo <= v <= hi) && continue
        throw(
            ArgumentError(
                string(
                    "field `", k, "`: ", where, " holds ", round(v; sigdigits = 6),
                    ", outside the field's declared bounds (", lo, ", ", hi,
                    "): the stability bound takes that interval for the ",
                    "coefficients that read `", k,
                    "`, and a boundary value outside it drives the field out of it; widen \
                        `bounds` in ",
                    "the field's declaration to hold ", round(v; sigdigits = 6),
                    ", or remove them"
                )
            )
        )
    end
    return nothing
end
Problems.declared_intervals(b::StabilityBound) = b.declared
Problems.used_intervals(b::StabilityBound) = b.used
# A coefficient that is not finite at an entry the inputs reach (a zero under a division, a
# negative entry under `sqrt`, a parameter that makes it infinite) gives a rate that is not
# finite there, whatever the substep count or the solver: refused on every path, the owned
# one (count or not) and the ODE one. Over the evaluation cap, or without
# tables, there is no value to refuse.
function _check_finite(r)
    bad = [(k, text, w) for (k, text, w) in r.nonfinite if w isa Tuple]
    isempty(bad) && return nothing
    return _dverr(
        string(
            "a rate is not finite where the inputs reach (whatever the substep count or \
                the solver): ",
            join(
                (
                    string(
                        _why_text(_coef_text(text), w),
                        " (in the rate of `", k, "`)", _why_route(w)
                    ) for (k, text, w) in bad
                ),
                "; "
            )
        )
    )
end
Problems.seen_bound(b::StabilityBound, p) = bound_parts(b, p).seen
# the parts the one substep policy decides on: the bound's parts and its unseen terms
function Problems.bound_report(b::StabilityBound, p)
    r = bound_parts(b, p)
    return (; r.negative, r.coupled, r.nonfinite, terms = b.terms, r.seen, r.ρ, r.worst)
end
# the reason tag of a rate that is not finite (`_why`)
_nonfinite_tag(w::Symbol) = w
_nonfinite_tag(::_Unsure) = :sign
_nonfinite_tag(::_IntervalWhy) = :interval
_nonfinite_tag(w) = :entries
function Problems.unbounded_reason(b::StabilityBound, p)
    parts = String[]
    isempty(b.terms) || push!(
        parts, "the term$(length(b.terms) == 1 ? "" : "s") " *
            join((_term_text(t) for t in b.terms), ", ") *
            ", which the bound cannot see"
    )
    any(isnan, p) && push!(parts, "a parameter without a value")
    r = bound_parts(b, p)
    if !any(isnan, p) && !isfinite(r.ρ)
        for (k, text, w) in r.nonfinite
            push!(
                parts, string(
                    "a coefficient with no finite bound: ", _why_text(_coef_text(text), w),
                    " (in the rate of `$k`)",
                    _why_route(w)
                )
            )
        end
        isempty(r.nonfinite) && push!(parts, "a coefficient with no finite bound")
    end
    c = r.coupled
    isempty(c) || push!(
        parts, "the coupled rows of $(join(("`$k`" for k in c), ", ")), which read each " *
            "other in a loop and are not diagonally dominant (their spectrum may be \
                complex)"
    )
    return isempty(parts) ? nothing : join(parts, "; ")
end

# the reason without values, the warning's once-key (`Problems.unbounded_key`): the terms
# the bound cannot see, and per coefficient with no finite bound its rate, its text and the
# cause (`:cap`, `:tables`, or not finite at some entry), never an entry or a parameter
# value
function Problems.unbounded_key(b::StabilityBound, p)
    parts = String["unseen: " * t for t in b.terms]
    any(isnan, p) && push!(parts, "a parameter without a value")
    if !any(isnan, p)
        r = bound_parts(b, p)
        for (k, text, w) in r.nonfinite
            push!(parts, string("nonfinite: ", k, ": ", text, " (", _nonfinite_tag(w), ")"))
        end
        isempty(r.coupled) || push!(parts, "coupled: " * join(r.coupled, ", "))
    end
    return isempty(parts) ? nothing : join(sort!(parts), "; ")
end

# a `"key: term"` entry of the bound as the user wrote it: the term, a field read `c(t, x,
# y)` as `c`, and the field whose rate holds it a coefficient as the user wrote it: a field
# read `c(t, x, y)` as `c`
function _coef_text(t::AbstractString)
    return _clocktext(
        _comptext(replace(t, r"(\w+)\(t(, \w+)*\)" => s"\1", "LatticePDE." => ""))
    )
end
# a component read `(u(t, x, y))[1]` (once `u(t, x, y)` is `u`) as the user writes it:
# `u[1]`
_comptext(t) = replace(t, r"\((\w+)\)\[" => s"\1[")
function _term_text(t::AbstractString)
    i = findfirst(": ", t)
    i === nothing && return "`$t`"
    term = _clocktext(
        _comptext(
            replace(
                t[(last(i) + 1):end], r"(\w+)\(t(, \w+)*\)" =>
                    s"\1"
            )
        )
    )
    return "`$term` (in the rate of `$(t[1:(first(i) - 1)])`)"
end

_states(p) = [f.key for f in p.fields if f.role == :state]

"""
    discretize(pdesys, disc::LatticeDiscretization; inputs = (), u0 = nothing, p = nothing,
        tspan = nothing)

The SciML problem of `pdesys` on the lattice: one problem, which every
algorithm takes.
- Rate equations `D(c) ~ rhs` (with aux fields `K ~ rhs`, masked conditions and steady rows
  `0 ~ rhs`) give an `ODEProblem`. The field algorithms step it, `solve(prob,
  BackwardEuler(); dt)` (`ExplicitEuler`, `CrankNicolson`, `BDF2`, `QuasiSteady`,
  `FieldGroups`), and so do OrdinaryDiffEq's solvers, `solve(prob, Rodas5P())`, through its
  compiled right side, which is built at their first call (a problem only field algorithms
  step never builds it).
- Maps `Shift(t, 1)(m) ~ rhs` give a `DiscreteProblem`, stepped by `ExplicitMap()` (or
  `FunctionMap()`, through the compiled map).
- `solve(prob)` with no algorithm takes `ExplicitEuler()` for rates (it needs `dt`, or the
  discretization's `clock`), `QuasiSteady()` when every row is steady, `ExplicitMap()` for
  maps.

The problem's `p` is a `LatticeParameters`: the scalar parameters, the tables, the inputs
and the clock's step index. Read and write them by symbol on the problem, an integrator or a
solution: `prob.ps[k]`, `integ.ps[Dk] = values`, `integ.ps[kind] = K`,
`remake(prob; p = [k => v], inputs = [kind => K])`.

On an OrdinaryDiffEq solver: a masked site holds its value (its rate is 0; the masks
are run again after each accepted step, so a mask that reads `t` or moves with an input
write is first-order in time); `step_index(t)` adds a `tstop` at every boundary of the
clock, where the step index changes; steady rows `0 ~ rhs` give the problem a `mass_matrix`
(0 on their fields), for a mass-matrix solver (`Rodas5P()`, `FBDF()`).

**Steady rows**. `0 ~ rhs` is solved for the field it determines: a state field with
no other equation that the row reads, preferably under a spatial operator
(`0 ~ D * laplacian(c) - k * c
+ s` is `c`'s); see `steady_rows`. Its group takes `QuasiSteady` only, by default too:
`solve(prob, BackwardEuler(); dt)` steps the other fields with `BackwardEuler` and the
steady ones with `QuasiSteady` at the same window, solved first in each window. A steady
field with no initial value starts at 0.

**Systems with no time**. A system whose variables are the axes only (`[x, y]`, every
row `0 ~ rhs` or an aux field) is a steady system, and
`solve(prob)` (or `solve(prob, QuasiSteady(; linsolve, nlsolve))`) solves it once from the
cold `u0`, with the inner solver to `reltol = 1e-6` within 64 iterations unless `linsolve`
is given. It returns a one-state solution at t = 0, read by the time-free symbol
(`sol[c(x, y)]`). The problem is a `LinearProblem` when every row is linear (`A` a
`LatticeOperator`, which applies the compiled right side, and `b` the constant part:
`A u = b` is the steady state; building it runs the right side once), else a
`NonlinearProblem` of the right side.

The time span is the domain of the first variable. Fields index solutions and integrators
by symbol (`sol[c(t, x, y)]`, `sol[:c]`) as grid-shaped arrays.

**Keywords** (SciML's `discretize`):
- `u0`: the initial values, a flat vector of the state, or `field => values` pairs (an array
  with one value per site, or a number) that override the fields they name;
- `p`: the parameter values, a vector of every parameter, or `parameter => value` pairs (a
  table as `Dk => values`, an input as `kind => K`), with `remake`'s rule (a plain value is
  written into the parameter type, a Dual promotes it; under `T = BigFloat` with Float64
  defaults a pair's BigFloat value rounds to Float64, so declare BigFloat defaults or give a
  BigFloat vector); a computed parameter is refused, naming why;
- `tspan`: the time span `(t₀, t₁)`, over the domain of the first variable;
- `inputs`: the input values (below);
- `jvp = true`, `sparse = false`, `jac = false`: the Jacobian of the right side for implicit
  OrdinaryDiffEq solvers. `jvp` is the Jacobian-vector product (one Dual evaluation),
  which Krylov linear solvers use (`linsolve = KrylovJL_GMRES()`); on a device it is also
  the `jac_prototype`, a matrix-free operator. `sparse = true` sets `jac_prototype` to the
  sparse pattern the IR gives (`field_jacobian_sparsity`) and `colorvec` to its coloring, so
  `Rodas5P()` or `FBDF()` form the Jacobian with one evaluation per color (5 to 7 for a
  5-point stencil) instead of a dense one. `jac = true` sets `jac` to the colored Dual
  Jacobian. Both are host only (no KernelAbstractions sparse matrix exists); a device takes
  `jvp`.
Any other keyword is an `ArgumentError` naming it. `discretize(sys, disc; p = [k => 2.0])`
is `remake(discretize(sys, disc); p = [k => 2.0])`, with no second problem built.

Write a kind set as `ismember(k, (1, 2))`, never with `∈`: see the warning in the manual's
"Fields from a `PDESystem`" (`k ∈ Set(…)` deletes the term).

**Inputs.** Input fields (`kindₛ(..)::Int32 [input = true]`, a `domain` mask) are read and
never written by the equations. Give their values with `inputs = [kindₛ => K, dom => M]`
(an array with one value per site, or a number), later with `remake(prob; inputs = …)`, and
during a run with `integ.ps[kindₛ] = K` (the masks follow). An input that changes in time is
given as a function of the time, `inputs = [q => t -> f(t)]`, which returns an array with
one value per site or a number (any value that is not an array or a number is called as
`v(t)`, so an interpolation object works too). A field algorithm writes `v(t)` into the
input at the start and at the end of each window, as a callback that writes
`integ.ps[q] = v(integ.t)` would, and the value holds over the window: a time-varying input
is first order in time on the owned path, implicit algorithms included (use an
OrdinaryDiffEq solver, or a smaller `dt`, for a higher order). An OrdinaryDiffEq solver's
right side evaluates `v` at the time of every call (each stage, the Jacobian-vector product,
`LatticeMultigrid`), so the solver sees the input at its own times; under a Rosenbrock
solver (`Rodas5P`) the time derivative `∂f/∂t` does not see the input's own change in time.
The masks follow on both; on an OrdinaryDiffEq solver a masked value jumps where the input
switches (written after the step), so a mask that reads such an input needs `dtmax` or
`tstops`, as a mask whose switch has no event does. A write of `integ.ps[q]` holds until the
next window of an owned run, or the next call of the right side; a value given to
`remake(prob; inputs = [q => K])` makes the input constant again. An input with a declared
default (`dom(..)::Bool = true [input = true]`) needs no value; any other unset input is an
error naming it when the problem is solved. An input is never read as zero.

**Parameters.** A parameter with a default that reads other parameters (`@parameters k2 =
2a`) is computed: it is read-only and follows `a` at every `remake` and `setp`
(evaluated again from the base parameters, through one compiled [`derivation`](@ref)). Reads
work (`getp(prob, k2)`, `integ.ps[k2]`, `sol.ps[k2]`); a write is an error naming its
inputs, and a face or mask value may read it (`c(t, 0, y) ~ g` with `g = g1 + g2`). An array
parameter needs a default of its declared size. A scalar parameter with no value is an error
naming it before the problem steps; `remake(prob; p = [k => v])` gives it one. A negative
diffusion coefficient, or a NaN value, is refused at every parameter value a problem steps
with: at `init` of a field algorithm, and at the first call of the right side with new
values for an OrdinaryDiffEq solver (`remake`, `setp` on an integrator), so `solve` or
`step!` throws and never runs them.

A system mixes no rate equations (`D(c) ~ …`) and maps (`Shift(t, 1)(m) ~ …`) in this
version: one problem steps one kind (split stepping is planned).
"""
function discretize(
        sys::PDESystem, disc::LatticeDiscretization{N}; inputs = (), u0 = nothing,
        p = nothing,
        tspan = nothing, jac::Bool = false, sparse::Bool = false, jvp::Bool = true, kw...
    ) where {N}
    isempty(kw) || _dverr(
        string(
            "`discretize` takes `inputs`, `u0`, `p`, `tspan`, `jac`, `sparse`, `jvp`; got ",
            join(("`$k`" for k in keys(kw)), ", "),
            ": give the other settings to the discretization (`LatticeDiscretization(…; \
                T, backend, clock)`) or to `solve`"
        )
    )
    _check_parts(sys)
    # steady rows `0 ~ rhs` as rates of their fields, a system with no time timed
    free = get_dvs(sys)
    sys, steady, timefree = steady_form(sys, N)
    timefree && tspan !== nothing &&
        _dverr("`tspan`: the system has no time (a steady system, solved once); leave \
            `tspan` out")
    check_one_kind(sys)
    backend = disc.backend === nothing ? KernelAbstractions.CPU() : disc.backend
    T = _statetype(disc)
    # Cartesian indexing on the host: the host loop hands each site its coordinates (a
    # linear launch decodes them with an integer division per site); the option is outside
    # the fingerprint
    options = CompileOptions(; T, index = Exec.ishost(backend) ? :cartesian : :auto)
    span = tspan === nothing ? _time_ends(sys) : _given_tspan(tspan)
    # the group, lowered once in rate form (the update is fused by the group, per algorithm)
    g = _lower_group(sys, disc; steady, timefree)
    cf, sys, spec = g.cf, g.sys, g.spec
    s = cf.program
    state = spec.state
    index = _index(
        cf, sys, s, state; g.derived, g.computed,
        cdefaults = g.defaults, free = timefree ? free : nothing
    )
    x0 = _given_u0(_initial(cf, sys, state, T), index, u0)
    _check_state_bounds(x0, cf, sys, index)
    pv, tables, pins = _given_p(cf.defaults, cf.tables, index, p)
    Problems.derive!(pv, tables, index)                  # the computed slots
    Problems.check_bounds(pv, index)                     # … within their bounds too
    # a constant face or mask value outside its field's declared bounds
    Problems.check_declared(spec.stability, Problems.with_tables(map(primal, pv), tables))
    ins = Pair[_input_defaults(cf, sys); collect(inputs); pins]
    _check_fusion(s, sys, disc)
    # the owned problem of the group (its plans and checks), held by the SciML problem's
    # metadata
    return Problems.lattice_problem(
        FieldProblem(spec, x0, span, pv; index, tables, inputs = ins, backend, options);
        jac, sparse, jvp
    )
end

"""
    check_one_kind(sys; route) -> Bool

Whether `sys` has maps (`Shift(t, 1)(m) ~ rhs`); a system with rate equations and maps both
is refused, naming the fields of each, with the front end's route (`route`; LatticePDE's:
two systems). One problem steps one kind in this version, in both front ends and however its
fields are grouped: a map steps one unit of time, which would step the rates with no bound,
and separate groups would be split stepping (planned).
"""
function check_one_kind(sys::PDESystem; route = "discretize them as two systems")
    lhs(eq) = unwrap(eq.lhs)
    name(eq) = (r = lhs(eq); a = iscall(r) ? arguments(r)[1] : r; string(_name(_opof(a))))
    maps = [
        name(eq)
            for eq in get_eqs(sys) if iscall(lhs(eq)) && operation(lhs(eq)) isa Shift
    ]
    isempty(maps) && return false
    rate = [
        name(eq)
            for eq in get_eqs(sys)
            if iscall(lhs(eq)) && operation(lhs(eq)) isa Differential
    ]
    isempty(rate) || _dverr(
        "the system mixes rate equations (of $(join(("`$f`" for f in rate), ", "))) and " *
            "maps (of $(join(("`$f`" for f in maps), ", "))); one problem steps one kind " *
            "in this version (a map steps at dt = 1, which would step the rates with no " *
            "bound): $route (split stepping is planned)"
    )
    return true
end

# `discretize`'s keywords: the time span, the initial values and the
# parameter values, given as `remake` takes them
function _given_tspan(ts)
    ts isa Union{Tuple, AbstractVector} && length(ts) == 2 && all(v -> v isa Real, ts) ||
        _dverr("`tspan` is `(t₀, t₁)`, two numbers; got $(repr(ts))")
    return _float_span(ts[1], ts[2])
end
# The initial values of the fields with declared `bounds = (lo, hi)`: the stability
# bound takes the declared interval for a coefficient that reads the field, so a field that
# starts outside it is refused, naming the first site
function _check_state_bounds(x0, cf::CompiledField, sys::PDESystem, index)
    for v in unwrap.(get_dvs(sys))
        ModelingToolkitBase.isinput(v) && continue
        b = _declared_bounds(v)
        b === nothing && continue
        ks = get(cf.keys, _opof(v), nothing)
        (ks === nothing || length(ks) != 1) && continue
        slot = get(index.vars, index.key(Symbol(only(ks))), nothing)
        slot isa FieldSlot || continue
        vals = view(x0, slot.range)
        i = findfirst(x -> !(b[1] <= primal(x) <= b[2]), vals)
        i === nothing && continue
        site = Tuple(CartesianIndices(Tuple(slot.dims))[i])
        _dverr(
            string(
                "field `", only(ks), "` starts at ", primal(vals[i]),
                " at site ", site, ", outside its declared ",
                "bounds (", b[1], ", ", b[2],
                "): the stability bound takes that interval for the coefficients that \
                    read `",
                only(ks), "`; give it initial values in its bounds, or change `bounds` in \
                    its declaration"
            )
        )
    end
    return nothing
end
# the element type `T` promoted by a given value (a Dual value promotes the state)
_promote_value(T, v::Real) = promote_dual(T, typeof(v))
_promote_value(T, v::AbstractArray) = promote_dual(T, eltype(v))
_promote_value(T, v) = T
function _given_u0(x0, index, u0)
    u0 === nothing && return x0
    if u0 isa AbstractVector{<:Real}
        length(u0) == length(x0) ||
            _dverr("`u0` has $(length(u0)) values; the state has $(length(x0))")
        return collect(u0)
    end
    u0 isa Union{AbstractVector{<:Pair}, Tuple, AbstractDict} ||
        _dverr("`u0` is a flat vector of the state or `field => values` pairs; got \
            a $(typeof(u0))")
    # a Dual value promotes the state, as a Dual parameter does
    E = foldl((T, x) -> _promote_value(T, last(x)), u0; init = eltype(x0))
    out = Vector{E}(x0)
    for (k, v) in u0
        slot = get(index.vars, index.key(k), nothing)
        Problems.input_key(index, k) === nothing ||
            _dverr("`u0`: `$(_keytext(k))` is an input, not a field of the state: give it \
                with `inputs = [$(_keytext(k)) => values]`")
        slot === nothing && _dverr(
            "`u0`: `$(_keytext(k))` is not a field of the state; its fields: " *
                join(("`$(_keytext(f))`" for f in index.varsyms), ", ")
        )
        if v isa Real
            out[slot.range] .= v
        elseif v isa AbstractArray && length(v) == length(slot.range)
            out[slot.range] .= vec(collect(v))
        else
            _dverr(
                "`u0`: give `$k` one value per site ($(length(slot.range))) or a number; \
                    got " *
                    (v isa AbstractArray ? "$(length(v)) values" : repr(v))
            )
        end
    end
    return out
end
function _given_p(defaults, tables, index, p)
    p === nothing && return defaults, tables, Pair[]
    if p isa AbstractVector{<:Real}
        length(p) == length(defaults) ||
            _dverr("`p` has $(length(p)) values; the system has $(length(defaults)) \
                parameters")
        Problems.check_bounds(p, index)              # a declared bound, at the write
        return collect(p), tables, Pair[]
    end
    p isa Union{AbstractVector{<:Pair}, Tuple, AbstractDict} ||
        _dverr("`p` is a vector of every parameter or `parameter => value` pairs; got \
            a $(typeof(p))")
    # a plain value is written into the parameter type, a Dual promotes it (`remake`'s rule)
    P = foldl(
        (T, x) -> last(x) isa Real ? promote_dual(T, typeof(last(x))) : T, p;
        init = eltype(defaults)
    )
    pv = Vector{P}(defaults)
    tabs = Pair{String, Any}[k => v for (k, v) in tables]
    # an input is a parameter too: `kind => K`
    ins = Pair[]
    for (k, v) in p
        t = Problems.table_key(index, k)
        if t !== nothing
            e = Problems.table_entry(index, k)
            e == 0 ||
                _dverr("`p`: `$k` is entry $e of the table `$t`: give the whole table, \
                    `$t => values`")
            j = findfirst(x -> first(x) == t, tabs)
            n = length(last(tabs[j]))
            v isa AbstractArray && length(v) == n ||
                _dverr("`p`: the table `$t` has $n entries; give $n values")
            tabs[j] = t => vec(collect(v))
            continue
        end
        # a computed parameter, or an unknown name, is an error naming it
        i = parameter_index(index, k)
        i === nothing && _dverr("`p`: `$(_keytext(k))` is not a parameter of the system")
        i isa Problems.InputSlot && (push!(ins, k => v); continue)
        pv[i] = v
    end
    Problems.check_bounds(pv, index)                 # a declared bound, at the write
    return pv, tabs, ins
end

# a key as the user wrote it (`c`, not `c(t, x, y)`; `:c` as `c`)
_keytext(k) = replace(string(k), r"\(t(, \w+)*\)" => "", "⋆" => "")

# The byte-identity gate of the update pass, on request: with
# `LATTICEPDE_CHECK_FUSION=1` in the environment, every owned problem checks that its rate
# program with the Euler update fused by the IR pass (`fuse_update`, with and without a
# clip) prints the same semantic program as the symbolic fusion (`symbolic_discretize(…;
# update)`), at Float64 and Float32, and throws otherwise (the test suites run with it)
function _check_fusion(rate::Program, sys::PDESystem, disc)
    get(ENV, "LATTICEPDE_CHECK_FUSION", "") == "1" || return nothing
    any(k -> startswith(k.key, "map:"), rate.kernels) && return nothing
    for lower in (nothing, 0.0)
        alg = ExplicitEuler(; lower_bound = lower)
        sym = symbolic_discretize(
            sys, disc;
            update = (kb, c, r) -> (
                v = euler_update(kb, c, r);
                lower === nothing ? v : max(v, lower)
            )
        ).program
        pass = fuse_update(rate, Problems.update_rule(alg))
        for T in (Float64, Float32)
            fingerprint_text(pass; T) == fingerprint_text(sym; T) ||
                throw(AssertionError("the update pass differs from the symbolic fusion \
                    (`$(nameof(sys))`, lower = $lower, T = $T) (internal error: please \
                        report it)"))
        end
    end
    return nothing
end
