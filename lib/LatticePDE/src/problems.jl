# `discretize`: a `PDESystem` on a lattice becomes a problem (v3 §5, §7.4, §8).
#   :owned  FieldProblem: the fused rate + Euler update kernels (`c + dt · rhs`), stepped by
#           ExplicitEuler (rates) or ExplicitMap (maps) through prebuilt launches.
#   :ode    ODEProblem: the rate kernels (`∂c = rhs`) as `LatticeRHS`, for SciML solvers.
#   :auto   ODEProblem for transient FV, FieldProblem when a discrete map is present.
#   :linear LinearProblem for steady systems: planned (F4; refused). A steady system (`0 ~ rhs`
#           rows, no time) is a FieldProblem solved once (F3-12b).

"""The explicit Euler update `c + dt · r` of the owned stepper (`dt = G.rt[2]`)."""
euler_update(kb, c, r) = c + Ex(kb, runtime!(kb, RT_DT)) * r

# symbol table keys: a `Symbol` or string names a field or parameter; any other symbol is
# looked up as its unwrapped term
_symkey(x::Union{Symbol, AbstractString}) = Symbol(x)
_symkey(x) = unwrap(x)

function _domain_ends(sys::PDESystem)
    return map(unwrap.(sys.ivs)) do v
        k = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        Float64.((leftendpoint(sys.domain[k].domain), rightendpoint(sys.domain[k].domain)))
    end
end

# a coefficient expression as a function of the raw parameter vector, over every 0/1
# assignment of its indicator terms (kind sets, comparisons): an indicator is 0 or 1 at each
# site, and the coefficient is not monotone in it (`k (1 − χ)` is largest at χ = 0), so each
# assignment is evaluated. A table read is evaluated at every index it can read, as the
# kernel reads it: index 0 reads 0 and any other index is clamped into `1:length` (the
# table's last entry above it, its first below 1). `Dk[2]` and `at(Dk, 2)` read their own
# entry; the `at` reads with one index expression `k` (the same site's kind) take one index
# together, `0` and `1:L` with `L` the longest table of the group (`at(Da, k) - at(Db, k)`
# per kind), and a read that appears twice is one read. A group takes the indices of the
# integer interval of its index expression (`+ − * min max abs`, `ifelse` as the hull of its
# arms, parameters at their values), over the declared bounds of its inputs (`bounds = (lo,
# hi)` metadata, which the input values are checked against) and, when `p` carries them, the
# current values of host-written inputs (`ParamsTables.inputs`): index 0 only when the
# interval holds 0 and, where it does, the index's values at the sites (when the host arrays
# give them) say whether a site reaches it; the entries are those the nonzero values clamp
# to (F2 records (h), (m)). This covers every value the coefficient takes at a site, for any expression of
# the reads (`at(Dq, k) (20 − at(Dq, k))`, `sin(at(Ds, k))`, `1 / at(Dv, k)`), with the
# indicators taken independently of the entries (a superset). A non-finite value (`1 / 0`)
# gives a non-finite bound, which is no bound. `c(p)` is the largest magnitude, `_hi`/`_lo`
# the largest and smallest signed values; `p` carries the tables (`Problems.ParamsTables`),
# and with table reads but no tables the values are `NaN`. `nothing` when the expression
# reads anything but scalar parameters and tables, keeps a call that is not plain arithmetic
# (a registered operator such as `Δ`), or has more than `_MAXIND` distinct indicators; more
# than `_MAXEVALS` evaluations (assignments × indices) give `NaN`, no bound.
struct CoefBound
    fs::Vector{Any}                         # one compiled function of the parameters per assignment
    reads::Vector{Tuple{String, Int, Int}}  # per read, in argument order: table, literal index, group (0: literal)
    groups::Vector{Any}                     # per group: its index expression as an interval tree (`_ivtree`)
    text::String                            # the coefficient, for messages
end
_pv(p) = p isa Problems.ParamsTables ? p.p : p

# ---- the interval of an integer index expression (F2 records (h), (m))
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
        return (:cmp, operation(u), _ivtree(arguments(u)[1], params, ivars), _ivtree(arguments(u)[2], params, ivars))
    end
    return (:anycond,)
end
const _IVANY = (-Inf, Inf)
_ivmul(a, b) = (q = (a[1] * b[1], a[1] * b[2], a[2] * b[1], a[2] * b[2]);
                any(isnan, q) ? _IVANY : (minimum(q), maximum(q)))
# the current values of input `k` that `p` carries (`Problems.ParamsTables` inputs), or nothing
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
        return (max(b[1], now[1]), min(b[2], now[2]))       # the values hold their bounds (checked)
    end
    h === :any && return _IVANY
    h === :ifelse && (a = (_ival(t[3], p), _ival(t[4], p)); return (min(a[1][1], a[2][1]), max(a[1][2], a[2][2])))
    a = map(x -> _ival(x, p), t[2:end])
    h === :+ && return (sum(first, a), sum(last, a))
    h === :* && return foldl(_ivmul, a)
    h === :neg && return (-a[1][2], -a[1][1])
    h === :min && return (minimum(first, a), minimum(last, a))
    h === :max && return (maximum(first, a), maximum(last, a))
    if h === :abs
        lo, hi = a[1]
        return lo >= 0 ? (lo, hi) : hi <= 0 ? (-hi, -lo) : (0.0, max(-lo, hi))
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
            out = sort!(unique!([x == 0 ? 0 : clamp(round(Int, x), 1, max(L, 1)) for x in v]))
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
# the value of an index expression at every site (a vector over the sites, or a number when it
# reads no input array), from the host input arrays `p` carries; `nothing` when an input has
# no host value or a part has no value per site (`:any`, a condition that is not a comparison).
# Whole-array operations: a few arrays per call, never one allocation per site
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
        x, y, a, b = _site_vals(c[3], p), _site_vals(c[4], p), _site_vals(t[3], p), _site_vals(t[4], p)
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
    s = v isa Number ? (v == i ? 1 : nothing) : findfirst(==(i), v)
    return s === nothing ? nothing : Tuple(CartesianIndices(sz)[s])
end
# a table read as the kernel does it (emit.jl TABLE, `oob = :zero_at_0`)
_tabread(v, i::Integer) = i == 0 ? 0.0 : Float64(v[clamp(i, 1, length(v))])
# a value of the coefficient; a domain error (`sqrt` of a negative entry) is `NaN`
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
    maxl = [maximum((length(tv[j]) for j in eachindex(c.reads) if c.reads[j][3] == g); init = 0) for g in eachindex(c.groups)]
    rs = [_group_indices(c.groups[g], p, maxl[g]) for g in eachindex(c.groups)]
    # in Float64: an integer product of many lengths overflows (16^16 == 0)
    length(c.fs) * prod(Float64 ∘ length, rs; init = 1.0) <= _MAXEVALS || return nothing
    return tv, rs
end
_indices(c::CoefBound, is) = (((_, e, g),) -> g == 0 ? e : is[g]).(c.reads)
function _vals(c::CoefBound, p)
    isempty(c.reads) && return (_val(f, p) for f in c.fs)
    r = _ranges(c, p)
    r === nothing && return (NaN,)
    tv, rs = r
    q = _pv(p)
    return (_val(f, (q..., (_tabread(tv[j], i) for (j, i) in enumerate(_indices(c, is)))...))
            for f in c.fs for is in Iterators.product(rs...))
end
(c::CoefBound)(p) = maximum(abs, _vals(c, p))
# the largest finite magnitude: the bound over the values that are finite (0 over the cap or
# with no tables), which an explicit count must still meet
_seen(c::CoefBound, p) = maximum((abs(v) for v in _vals(c, p) if isfinite(v)); init = 0.0)
_hi(c::CoefBound, p) = maximum(_vals(c, p))
_lo(c::CoefBound, p) = minimum(_vals(c, p))
"""
    _why(c::CoefBound, p) -> nothing | :cap | :tables | (combos, more)

Why `c` has no finite bound at `p`: `nothing` when it has one; `:cap` over the evaluation
cap; `:tables` table reads with no tables; else the distinct read combinations with a value
that is not finite, each a vector of `(table, index, value read)` (index 0 reads 0; empty when
no table is read), at most `_MAXWHY` of them, and how many more there are.
"""
function _why(c::CoefBound, p)
    all(isfinite, _vals(c, p)) && return nothing
    isempty(c.reads) && return ([Tuple{String, Int, Float64}[]], 0)
    p isa Problems.ParamsTables || return :tables
    r = _ranges(c, p)
    r === nothing && return :cap
    tv, rs = r
    q = _pv(p)
    combos = Vector{Tuple{String, Int, Float64}}[]
    for f in c.fs, is in Iterators.product(rs...)
        ix = _indices(c, is)
        isfinite(_val(f, (q..., (_tabread(tv[j], i) for (j, i) in enumerate(ix))...))) && continue
        # the index each read takes, clamped as the kernel clamps it
        w = unique!([(c.reads[j][1], i == 0 ? 0 : clamp(i, 1, length(tv[j])), _tabread(tv[j], i)) for (j, i) in enumerate(ix)])
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
const _PLAIN = (+, -, *, /, ^, inv, abs, sqrt, cbrt, exp, log, sin, cos, tan, tanh, min, max, identity)   # (`identity`: an irrational, `identity(Const(π))`)
_plainop(f) = any(g -> f === g, _PLAIN)
function _coef_bound(x, params, tabs = Dict{Any, String}(), ivars = ())
    u0 = unwrap(x)
    # the table reads, each a fresh variable; the `at` reads grouped by index expression: a
    # group takes one index for all its reads
    reads, tvars, reps = Tuple{String, Int, Int}[], Any[], Dict{Any, Any}()
    gkeys = Any[]
    function walkt(y)
        iscall(y) || return nothing
        f, a = operation(y), arguments(y)
        if (f === getindex || f === at) && length(a) == 2 && haskey(tabs, unwrap(a[1]))
            any(k -> isequal(k, y), keys(reps)) && return nothing
            k = tabs[unwrap(a[1])]
            i = unwrap_const(unwrap(a[2]))
            if i isa Integer || (i isa AbstractFloat && isinteger(i))   # a literal index reads its own entry
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
        foreach(walkt, a)
    end
    walkt(u0)
    isempty(reps) || (u0 = unwrap(substitute(u0, reps; fold = Val(false))))
    inds = Any[]
    walk(y) = iscall(y) && ((operation(y) === ismember || operation(y) in (==, <, <=, >, >=)) ?
                            (any(z -> isequal(z, y), inds) || push!(inds, y)) : foreach(walk, arguments(y)))
    walk(u0)
    length(inds) <= _MAXIND || return nothing
    plain(y) = !iscall(y) || (_plainop(operation(y)) && all(plain, arguments(y)))
    args = Any[params; tvars]
    fs = Any[]
    for bits in Iterators.product(ntuple(_ -> (0, 1), length(inds))...)
        # an `ifelse` whose condition the indicators decide takes its arm (the condition is a
        # Bool); every other indicator is an arithmetic factor, 0 or 1 (F2 record (j))
        u = isempty(inds) ? u0 : _arms(u0, inds, bits)
        u = isempty(inds) ? u : unwrap(substitute(u, Dict{Any, Any}(zip(inds, bits)); fold = Val(true)))
        plain(u) || return nothing
        all(v -> any(q -> isequal(q, v), args), Symbolics.get_variables(u)) || return nothing
        push!(fs, Symbolics.build_function(u, args...; expression = Val(false)))
    end
    return CoefBound(fs, reads, Any[_ivtree(k, params, ivars) for k in gkeys], string(x))
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
        foreach(walk, arguments(y))
    end
    walk(u)
    isempty(reps) && return u
    return _arms(unwrap(substitute(u, reps; fold = Val(false))), inds, bits)
end

# the multiplier of a diffusion term: the operator call replaced by its coefficient (1 for
# Δ and Dx(Dx(c)), K for DivKGrad(K, c) and Dx(K Dx(c)))
function _diffusion_coefficient(term)
    reps = Dict{Any, Any}()
    walk(y) = iscall(y) && (f = operation(y);
                            f === Δ ? (reps[y] = 1) :
                            f isa DivKGrad ? (reps[y] = arguments(y)[1]) :
                            f isa Differential ? (r = _raw_flux(y); reps[y] = r === nothing || r[1] === nothing ? 1 : r[1]) :
                            foreach(walk, arguments(y)))
    walk(unwrap(term))
    return substitute(term, reps; fold = Val(false))
end

# a site-varying diffusion term `m Op(c)` (`:SiteDiffusion`): the center multiplier `m` (the
# operator replaced by 1), read at the row's own site, and the face coefficient `K` (1 for
# `Δ`, `K` of `DivKGrad(K, c)` or of `Dx(K Dx(c))`), read through face means of two sites
function _site_parts(term)
    reps, K = Dict{Any, Any}(), Any[]
    walk(y) = iscall(y) && (f = operation(y);
                            f === Δ ? (reps[y] = 1; push!(K, 1)) :
                            f isa DivKGrad ? (reps[y] = 1; push!(K, arguments(y)[1])) :
                            f isa Differential ? (r = _raw_flux(y); reps[y] = 1;
                                                  push!(K, r === nothing || r[1] === nothing ? 1 : r[1])) :
                            foreach(walk, arguments(y)))
    walk(unwrap(term))
    length(K) == 1 || return nothing
    return substitute(term, reps; fold = Val(false)), only(K)
end

"""
    StabilityBound

`ρ(p)`: a bound on the spectral radius of the rate Jacobian at raw parameters `p` (v3 §6.2,
the Gershgorin bound; for one diffusing field `D Σ 4/h² + |k|`), built from the linearity
table. Per rate field (one Jacobian row):
- `Diffusion` terms give `D = Σ D_i(p)` times `Σ_d 4/h_d²`, plus `|D| max(0, |r| − 1)/h_d²`
  for a parameter-dependent Robin face on axis `d` (the ghost value's cell coefficient
  `r = (α/2 − β)/(α/2 + β)` stiffens the boundary row);
- `LinearLocal` terms (`k c`) add `|k|`;
- `CrossLinear` terms add their off-diagonal row sum: `|k|` for `k o`, and
  `|D₂| (Σ_d 4/h_d² + Robin terms of o)` for cross-diffusion `D₂ Δ(o)`.
- `SiteDiffusion` terms `m Op(c)` (a multiplier `m` that reads inputs through table reads
  and indicators only, F2 record (g)) give `max|m| · max K` times `Σ_d 4/h_d²` (and the Robin
  terms): the center multiplier `m` is evaluated jointly over its reads (one site), the face
  coefficient `K` (1 for `Δ`) independently, because a face mixes two sites' indices. For
  `M = diag(m) ≥ 0` and the symmetric `A`, `M A` is similar to `M^½ A M^½` on the rows with
  `m > 0`, so its spectrum is real and bounded by `max m · ρ(A)`.
A coefficient with kind sets or comparisons (indicators, 0 or 1 per site) is evaluated at
every 0/1 assignment of them: the largest magnitude enters `ρ`, the largest signed value
the diagonal. An `ifelse` whose condition the indicators decide takes its arm. A coefficient that reads a table (`Dk[2] * Δ(c)`, `at(Dk, kind) * Δ(c)`) is
evaluated at every index each read can take, as the kernel reads it (the entry itself for
`Dk[2]`; for `at`, index 0, which reads 0 unless the index is an input declared never 0, and
every entry, clamped into each table; reads with one index take one index together), from
the tables `p` carries
(`Problems.ParamsTables`): any expression of the reads is covered, a negative entry is
negative diffusion, a large one raises the bound, and a non-finite value (`1 / 0`) is no bound
(F1).
A switch `ifelse(cond, a, b)` (class `Other`) whose condition reads no unknown field (a
gate such as `t ≥ t_relax`) is bounded arm by arm: each choice of a row's switch arms is a
row of its own (at most 64 per row), the bound is the worst, and the dominance test below
holds for every choice (listed in `expanded`).

`NaN` (no bound) when:
- a field has a term the bound cannot see (`unbounded`: `Other`, `Advection`,
  `LaggedSwitch`, or a coefficient that reads more than scalar parameters and tables, or a
  coefficient with more than 6 distinct kind sets and comparisons);
- a coefficient takes a non-finite value at some index or assignment, or its indicator
  assignments times table indices exceed 4096, the evaluation cap (the bound is `Inf` or
  `NaN`; `bound_parts` says which, and where);
- a needed parameter has no value;
- a row with `CrossLinear` terms is not diagonally dominant with a nonpositive diagonal. The
  step limit `dt ρ ≤ 1.8` holds for real, dissipative spectra only; coupled rows such as
  `c' = a o, o' = −a c` have imaginary eigenvalues, which forward Euler amplifies at any
  step. Until the disk test of v3 §6.2 lands (C7c), such systems are refused instead of
  given the §6.2 warning fallback (a provisional decision).

With no bound, `ExplicitEuler` requires a user substep count. Until the IR tangent and
interval evaluator replace it (C7c), this is the stability analysis of the explicit steppers.
"""
# The terms of one row of the Jacobian under one choice of the arms of its `ifelse` switches
struct RowTerms
    diffusion::Vector{CoefBound}
    sitediffusion::Vector{Tuple{CoefBound, CoefBound}}   # center multiplier m, face coefficient K
    linear::Vector{CoefBound}
    crosslinear::Vector{Tuple{CoefBound, Int}}      # coefficient, index of the other field (0: not a row)
    crossdiffusion::Vector{Tuple{CoefBound, Int}}   # coefficient, index of the other field
end
RowTerms() = RowTerms(CoefBound[], Tuple{CoefBound, CoefBound}[], CoefBound[], Tuple{CoefBound, Int}[], Tuple{CoefBound, Int}[])
Base.copy(r::RowTerms) = RowTerms(copy(r.diffusion), copy(r.sitediffusion), copy(r.linear), copy(r.crosslinear),
    copy(r.crossdiffusion))
# a site-diffusion term's parts at `p`: max|m| max|K| (the independent bound) and the seen
# product
_sd(f, p) = f[1](p) * f[2](p)
_sdseen(f, p) = _seen(f[1], p) * _seen(f[2], p)
const _MAXARMS = 64                       # row alternatives (arm choices) before giving up

struct StabilityBound
    invh2::Vector{Float64}
    keys::Vector{String}
    rows::Vector{Vector{RowTerms}}        # per row, one entry per choice of its switches' arms
    faces::Vector{Vector{Tuple{Int, Coef, Coef}}}
    unbounded::Vector{String}
    terms::Vector{String}                 # the terms it cannot see, as `"key: term"`
    expanded::Vector{String}              # the `ifelse` terms bounded arm by arm
    inputs::Vector{String}                # the inputs an index reads (`Problems.bound_inputs`)
    crossunseen::Vector{String}           # the rows with an unseen term that reads another unknown field
end
# the input keys of an interval tree
function _tree_inputs!(acc, t)
    h = t[1]
    h === :in && return push!(acc, t[2])
    h in (:c, :p, :any, :anycond) && return acc
    h === :cmp && (_tree_inputs!(acc, t[3]); _tree_inputs!(acc, t[4]); return acc)
    foreach(x -> _tree_inputs!(acc, x), t[2:end])         # `:ifelse` holds its condition first
    return acc
end
function _row_inputs(rows)
    acc = String[]
    for alts in rows, r in alts
        for f in Iterators.flatten((r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion), r.linear,
                first.(r.crosslinear), first.(r.crossdiffusion))), t in f.groups
            _tree_inputs!(acc, t)
        end
    end
    return sort!(unique!(acc))
end
Problems.bound_inputs(b::StabilityBound) = b.inputs
_cv(c::Coef, p) = c.param == 0 ? c.value : c.value * Float64(p[c.param])
# Σ_d max(0, |r| − 1)/h_d², the worst Robin face of each axis of field `i`
function _face_excess(b::StabilityBound, i, p)
    return sum(eachindex(b.invh2); init = 0.0) do d
        b.invh2[d] * maximum((max(0.0, abs(Problems.face_ratio(_cv(α, p), _cv(β, p))) - 1)
                              for (ax, α, β) in b.faces[i] if ax == d); init = 0.0)
    end
end
# the same over the axes whose excess is finite (an axis with a degenerate Robin face, a ratio
# that is not finite, counts 0): the seen bound keeps every finite part of a row (F2 record (f))
function _face_excess_seen(b::StabilityBound, i, p)
    return sum(eachindex(b.invh2); init = 0.0) do d
        x = b.invh2[d] * maximum((max(0.0, abs(Problems.face_ratio(_cv(α, p), _cv(β, p))) - 1)
                                  for (ax, α, β) in b.faces[i] if ax == d); init = 0.0)
        isfinite(x) ? x : 0.0
    end
end
function (b::StabilityBound)(p)
    isempty(b.unbounded) || return NaN
    r = bound_parts(b, p)
    return isempty(r.coupled) ? r.ρ : NaN
end

# The bound of the rows `keep` alone (a field group, F2 design §2.6): a cross term that reads a
# field outside the group reads its array, which does not change during the group's step (a
# source, as front end A's group sees it); the other terms are the row's own
function Problems.restrict_bound(b::StabilityBound, keep)
    idx = [i for i in eachindex(b.keys) if b.keys[i] in keep]
    length(idx) == length(b.keys) && return b
    new = Dict(i => j for (j, i) in enumerate(idx))
    cut(ts) = [(f, j == 0 ? 0 : new[j]) for (f, j) in ts if j == 0 || haskey(new, j)]
    rows = [[RowTerms(r.diffusion, r.sitediffusion, r.linear, cut(r.crosslinear), cut(r.crossdiffusion))
             for r in b.rows[i]] for i in idx]
    ks = b.keys[idx]
    mine(t) = any(k -> startswith(t, "$k: "), ks)
    return StabilityBound(b.invh2, ks, rows, b.faces[idx], [k for k in b.unbounded if k in ks],
        filter(mine, b.terms), filter(mine, b.expanded), _row_inputs(rows), [k for k in b.crossunseen if k in ks])
end

# The lagged coupling of field groups (`Problems.lagged_coupling`; review of F2-06): per
# group, the largest over its rows (and their switch arms) of Σ max|coefficient| over the
# cross terms that read a field of another group (a cross diffusion `a Δ(o)` with its
# `4 Σ 1/h²` and Robin parts, as in the row bound), with the worst term. A coefficient with no
# finite bound makes the rate `NaN` (or `Inf`), kept over any finite row. The group read graph
# (round 2): `reads`, the groups whose fields a seen cross term reads, whatever its value (the
# structure, so the graph does not change with the parameters); `unseen`, a row of the group
# has a term the bound cannot see that reads another unknown field (a state of another row, or
# an aux field, which may carry any state; round 3: a term on the row's own field alone, such
# as `-a^3`, couples no group). `within` (round 3): per group, the groups whose reads the rate
# sums (the group's loop); `nothing`, every other group.
# `text` is the coefficient as the user wrote it (`at(Kt, q)`), `raw` the bound's text (front
# end A prints it in the model's words).
function Problems.lagged_coupling(b::StabilityBound, groups, p; within = nothing)
    gof = Dict{String, Int}(k => g for (g, ks) in enumerate(groups) for k in ks)
    s4 = 4 * sum(b.invh2)
    out = [(; rate = 0.0, row = "", other = "", text = "", raw = "", reads = Int[],
              unseen = any(k -> k in b.crossunseen, ks)) for ks in groups]
    for i in eachindex(b.keys)
        g = get(gof, b.keys[i], 0)
        g == 0 && continue
        for r in b.rows[i]
            for (_, j) in Iterators.flatten((r.crosslinear, r.crossdiffusion))
                h = j == 0 ? 0 : get(gof, b.keys[j], 0)
                (h == 0 || h == g || h in out[g].reads) || push!(out[g].reads, h)
            end
            tot, worst, wj, wt = 0.0, -Inf, 0, ""
            terms = Iterators.flatten((((f, j, f(p)) for (f, j) in r.crosslinear if j != 0),
                                       ((f, j, f(p) * (s4 + _face_excess(b, j, p))) for (f, j) in r.crossdiffusion if j != 0)))
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
                (out[g] = (; out[g]..., rate = tot, row = b.keys[i], other = b.keys[wj], text = _coef_text(wt), raw = wt))
        end
    end
    foreach(q -> sort!(q.reads), out)
    return out
end

"""
    bound_parts(b::StabilityBound, p) -> (; ρ, seen, coupled, negative, nonfinite)

The parts of `b(p)`: `ρ`, the Gershgorin bound over the terms `b` sees (a term in
`b.terms` is left out); `seen`, the same bound over the finite values of each coefficient
only (a coefficient over the evaluation cap counts 0; `seen == ρ` when `ρ` is finite), which
raises an explicit count; `coupled`, the keys of the rows with cross terms that are not
diagonally dominant with a nonpositive diagonal (`b(p)` is `NaN` for them); `negative`, the
keys of the rows with a diffusion coefficient below zero at `p` (at some indicator
assignment); `nonfinite`, when `ρ` is not finite, a `(key, coefficient, why)` per coefficient
with no finite bound (`why`: `:cap` over the evaluation cap, `:tables` no tables given, or
`(combos, more)`: up to 4 distinct read combinations `[(table, index, value), …]` with a value that is
not finite, index 0 reading 0, and how many more). `b(p) == ρ`
when `b.unbounded` and `coupled` are empty.
"""
function bound_parts(b::StabilityBound, p)
    s4 = 4 * sum(b.invh2)
    ρ = seen = 0.0
    coupled, negative = String[], String[]
    for i in eachindex(b.keys)
        # each choice of the row's switch arms is a row of its own: the bound is the worst,
        # and the row is coupled when any choice is not diagonally dominant
        for r in b.rows[i]
            (any(f -> _lo(f, p) < 0, r.diffusion) || any(f -> _lo(f[1], p) < 0 || _lo(f[2], p) < 0, r.sitediffusion)) &&
                push!(negative, b.keys[i])
            # a site-varying multiplier m and a face coefficient K are bounded independently,
            # max|m| · max K: a face mixes two sites' indices (F2 record (g))
            Dmag = sum(f(p) for f in r.diffusion; init = 0.0) + sum(_sd(f, p) for f in r.sitediffusion; init = 0.0)
            own = Dmag * (s4 + _face_excess(b, i, p))
            lin = sum(f(p) for f in r.linear; init = 0.0)
            cross = sum(f(p) for (f, _) in r.crosslinear; init = 0.0) +
                    sum(f(p) * (s4 + _face_excess(b, j, p)) for (f, j) in r.crossdiffusion; init = 0.0)
            if !isempty(r.crosslinear) || !isempty(r.crossdiffusion)
                # the diagonal at its largest over the indicator assignments. A row of `M A` (site
                # diffusion) is balanced: its diagonal m_i Σ K / h² equals its off-diagonal sum,
                # so the same bound enters both sides and cancels (the row test is the rest of
                # the row: the reaction against the cross terms and the Robin faces)
                diag = -2 * sum(b.invh2) * (sum(_lo(f, p) for f in r.diffusion; init = 0.0) +
                                            sum(_sd(f, p) for f in r.sitediffusion; init = 0.0)) +
                       sum(_hi(f, p) for f in r.linear; init = 0.0)
                offd = Dmag * (s4 / 2 + _face_excess(b, i, p)) + cross
                diag <= 0 && -diag >= offd || push!(coupled, b.keys[i])
            end
            ρ = max(ρ, own + lin + cross)
            # the same over the finite values only (a term over the cap counts 0, an axis whose
            # face excess is not finite counts 0): every row, term and field that has a bound
            # still raises an explicit count, and a part that is not finite never drops the rest
            # of its row
            Ds = sum(_seen(f, p) for f in r.diffusion; init = 0.0) + sum(_sdseen(f, p) for f in r.sitediffusion; init = 0.0)
            sv = Ds * (s4 + _face_excess_seen(b, i, p)) + sum(_seen(f, p) for f in r.linear; init = 0.0) +
                 sum(_seen(f, p) for (f, _) in r.crosslinear; init = 0.0) +
                 sum(_seen(f, p) * (s4 + _face_excess_seen(b, j, p)) for (f, j) in r.crossdiffusion; init = 0.0)
            seen = max(seen, sv)
        end
    end
    nonfinite = Tuple{String, String, Any}[]
    if !isfinite(ρ)
        for i in eachindex(b.keys), r in b.rows[i]
            for f in Iterators.flatten((r.diffusion, first.(r.sitediffusion), last.(r.sitediffusion), r.linear,
                    first.(r.crosslinear), first.(r.crossdiffusion)))
                w = _why(f, p)
                # a read at index 0: the first site where it is (from the host input arrays)
                w isa Tuple && any(c -> any(x -> x[2] == 0, c), w[1]) && (w = (w..., _zero_site(f, p)))
                w === nothing || any(x -> x[1] == b.keys[i] && x[2] == f.text, nonfinite) ||
                    push!(nonfinite, (b.keys[i], f.text, w))
            end
        end
    end
    return (; ρ, seen, coupled = unique!(coupled), negative = unique!(negative), nonfinite)
end

# the declared bounds `(lo, hi)` of a scalar input (`bounds` metadata); `(-Inf, Inf)` without
# them or for an array input
function _input_bounds(v)
    b = ModelingToolkitBase.getbounds(v)
    return b[1] isa Real && b[2] isa Real ? (Float64(b[1]), Float64(b[2])) : (-Inf, Inf)
end
_input_lower(v) = first(_input_bounds(v))

# why a coefficient has no finite bound, in words (`_why`)
function _why_text(text, w)
    w === :cap && return "`$text` reads more than $(_MAXEVALS) table index combinations"
    w === :tables && return "`$text` reads tables that were not given"
    combos, more = w
    all(isempty, combos) && return "`$text` is not finite at these parameters"
    site = length(w) >= 3 ? w[3] : nothing
    # with no site, the index's interval (its declared bounds, an `ifelse` hull) holds 0 and no
    # site value says otherwise: the bound is conservative there
    read(t, i) = i == 0 ? (site === nothing ? "index 0 of `$t` (the index's interval holds 0; no site value is known, so this is conservative)" :
                           "index 0 of `$t` (at site $site)") : "`$t[$i]`"
    return string("`$text` is not finite at ", join((join((read(t, i) for (t, i, _) in c), " with ") for c in combos), ", at "),
        more > 0 ? " (and $more more)" : "")
end
# what to change about an entry that makes a coefficient not finite, by its value
_entry_fix(v) = v == 0 ? "make it nonzero (a zero entry: a division by it is not finite)" :
                v < 0 ? "make it ≥ 0 (a negative entry under `sqrt` or `log` is not finite)" :
                "give it a value where the coefficient is finite"
# the route for a coefficient that is not finite: fix each entry it names, keep 0 out of an
# index that reaches 0
function _why_route(w)
    w isa Tuple || return ""
    rd = unique(reduce(vcat, w[1]; init = Tuple{String, Int, Float64}[]))
    isempty(rd) && return "; give its parameters values that make it finite"
    parts = String[]
    any(x -> x[2] == 0, rd) && push!(parts, "index 0 reads 0 (an input value 0, or a literal 0), and the " *
                                            "coefficient is not finite there: keep 0 out of the index (write no 0 " *
                                            "into the input, or declare it `bounds = (1, n)`)")
    for (t, i, v) in rd
        i == 0 || push!(parts, "for `$t[$i]` ($v), $(_entry_fix(v))")
    end
    return "; " * join(parts, "; ")
end

"""
    stability_bound(cf::CompiledField, sys) -> StabilityBound

The [`StabilityBound`](@ref) of the rate fields of `cf`; call it with a parameter vector.
"""
function stability_bound(cf::CompiledField{N}, sys::PDESystem) where {N}
    ks = sort!(collect(keys(cf.linearity)))
    # the clock's slot is not a value fixed at bind (F2 design §2.6, rule 3): as the time `t`,
    # a coefficient that reads it is a term the bound cannot see, and an `ifelse` gate on it
    # is bounded through both arms; a stand-in that no coefficient can read keeps the slots
    params = Any[_isclock(q) ? unwrap(Symbolics.variable(:__clock_slot)) : q for q in cf.params]
    states = Set(_states(cf.program))
    dvs = Dict{String, Any}()            # state key → its term (inputs and aux are not rows)
    for v in sys.dvs, (op, kk) in cf.keys
        isequal(_opof(v), op) || continue
        u = unwrap(v)
        for (i, k) in enumerate(kk)
            k in states && (dvs[k] = length(kk) == 1 ? u : unwrap(Symbolics.wrap(u)[i]))
        end
    end
    stateops = unique([_opof(v) for v in values(dvs)])
    staterefs = unique([_ref(v) for v in values(dvs)])          # (an array field by its components)
    others = [v for v in unwrap.(sys.dvs) if !any(o -> isequal(o, _opof(v)), stateops)]
    inputops = unique([_opof(v) for v in others if ModelingToolkitBase.isinput(v)])
    auxops = unique([_opof(v) for v in others if !ModelingToolkitBase.isinput(v)])   # `K ~ expr` fields
    unknownops = [staterefs; auxops]
    rows = Vector{RowTerms}[]
    faces, unbounded, terms, expanded = Vector{Tuple{Int, Coef, Coef}}[], String[], String[], String[]
    crossunseen = String[]
    # the array parameters (tables) by their symbols: a coefficient may read them
    tabs = Dict{Any, String}(unwrap(q) => string(unwrap(q)) for q in _params(sys)
                             if string(unwrap(q)) in first.(cf.tables))
    # the scalar inputs with their keys and declared bounds: an index expression's interval is
    # taken over these and over the current values a host-written input carries
    ivars = Tuple{Any, String, Tuple{Float64, Float64}}[]
    for v in unwrap.(sys.dvs)
        ModelingToolkitBase.isinput(v) || continue
        op = _opof(v)
        vk = get(cf.keys, op, nothing)
        vk === nothing || length(vk) != 1 || push!(ivars, (v, only(vk), _input_bounds(v)))
    end
    for k in ks
        # one term added to every alternative of the row: `false` when the bound cannot see
        # it. A switch `ifelse(cond, a, b)` whose condition reads no unknown field (a gate
        # such as `t ≥ t_relax`) doubles the alternatives: one with the terms of `a`, one with
        # those of `b` (each choice checked on its own: a decaying arm never certifies a
        # rotation in the other)
        function add!(alts, term, class, depth)
            fs = [kk for (kk, v) in dvs if _reads(term, (_ref(v),))]
            if class == :Diffusion
                c = _coef_bound(_diffusion_coefficient(term), params, tabs, ivars)
                c === nothing && return false
                foreach(r -> push!(r.diffusion, c), alts)
            elseif class == :SiteDiffusion
                parts = _site_parts(term)
                parts === nothing && return false
                cm = _coef_bound(parts[1], params, tabs, ivars)
                cK = _coef_bound(parts[2], params, tabs, ivars)
                (cm === nothing || cK === nothing) && return false
                foreach(r -> push!(r.sitediffusion, (cm, cK)), alts)
            elseif class == :LinearLocal || class == :CrossLinear
                length(fs) == 1 || return false
                if class == :CrossLinear &&
                   _linclass(unwrap(term), _ref(dvs[fs[1]]), staterefs, inputops) == :Diffusion
                    j = findfirst(==(fs[1]), ks)
                    c = j === nothing ? nothing : _coef_bound(_diffusion_coefficient(term), params, tabs, ivars)
                    c === nothing && return false
                    foreach(r -> push!(r.crossdiffusion, (c, j)), alts)
                else
                    c = _coef_bound(substitute(term, Dict(dvs[fs[1]] => 1); fold = Val(false)), params, tabs, ivars)
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
                (depth < 4 && iscall(u) && operation(u) === ifelse && !_reads(arguments(u)[1], unknownops)) || return false
                out = RowTerms[]
                for arm in arguments(u)[2:3]
                    branch = map(copy, alts)
                    # classified as the rate's own terms: a term reading an aux field is Other
                    for (t2, c2) in linearity(arm, _ref(dvs[k]), unknownops; inputs = inputops, aux = auxops)
                        add!(branch, t2, c2, depth + 1) || return false
                    end
                    append!(out, branch)
                end
                length(out) <= _MAXARMS || return false
                empty!(alts); append!(alts, out)
                push!(expanded, "$k: $(term)")
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
                push!(unbounded, k); push!(terms, "$k: $(term)")
                # an unseen term that reads another unknown field (a state of another row, or
                # any aux field, which may carry any state) can couple field groups
                own = _ref(dvs[k])
                _reads(term, [op for op in unknownops if !isequal(op, own)]) && push!(crossunseen, k)
            end
        end
        push!(rows, alts)
        push!(faces, [(Int(r.axis), r.alpha, r.beta) for r in cf.program.rules
                      if r isa FaceRule && cf.program.fields[r.field].key == k])
    end
    return StabilityBound([1 / h^2 for h in cf.program.spacing], ks, rows, faces,
        sort!(unique!(unbounded)), unique!(terms), unique!(expanded), _row_inputs(rows), sort!(unique!(crossunseen)))
end

# initial values of the state fields, flat in `state` order, evaluated at cell centers in
# the state type `T`
function _initial(cf::CompiledField{N}, sys::PDESystem, state, ::Type{T}) where {N, T}
    ends = _domain_ends(sys)
    ivs = unwrap.(sys.ivs)
    h = cf.program.spacing
    dims = Int.(cf.program.hierarchy[1].grid.dims)
    vals = Dict{Any, Any}(p => d for (p, d) in zip(cf.params, cf.defaults) if !isnan(d))
    vals[ivs[1]] = ends[1][1]
    out = T[]
    for k in state
        haskey(cf.initial, k) || _dverr("field `$k` has no initial condition `$k(0, …) ~ value`")
        v = cf.initial[k]
        if v isa Number
            append!(out, fill(T(v), prod(dims)))
            continue
        end
        e = substitute(v, vals; fold = Val(true))
        xs = ivs[2:end]
        free = [u for u in Symbolics.get_variables(e) if !any(x -> isequal(x, u), xs)]
        isempty(free) || _dverr("the initial value of `$k` does not reduce to a number: `$v` reads $(join(free, ", "))")
        f = Symbolics.build_function(e, xs...; expression = Val(false))   # compiled once, not per site
        centers = ntuple(d -> T(ends[d + 1][1]) .+ (T.(1:dims[d]) .- T(1) / 2) .*
                              ((T(ends[d + 1][2]) - T(ends[d + 1][1])) / dims[d]), N)
        append!(out, vec([T(f(Tuple(I)...)) for I in Iterators.product(centers...)]))
    end
    return out
end

function _index(cf::CompiledField, sys::PDESystem, s, state; derived = Pair[], computed = Pair[], cdefaults = Pair[],
        free = nothing)
    slots = Problems.state_layout(s, [fieldid(s, k) for k in state])
    # a system with no time (F3-12b): each field also reads by its time-free term `c(x, y)`
    alias(v, i, n) = free === nothing ? () : (o = free[findfirst(w -> isequal(unwrap(w), unwrap(v)), sys.dvs)];
                                             (n == 1 ? unwrap(o) : unwrap(Symbolics.wrap(unwrap(o))[i]),))
    dims = Int.(cf.program.hierarchy[1].grid.dims)
    vars, inputs, inputnames, boolinputs, inputbounds, aux = Pair[], Pair[], Pair[], String[], Pair[], Pair[]
    for v in sys.dvs, (op, ks) in cf.keys
        isequal(_opof(v), op) || continue
        for (i, k) in enumerate(ks)
            term = length(ks) == 1 ? unwrap(v) : unwrap(Symbolics.wrap(unwrap(v))[i])
            if ModelingToolkitBase.isinput(unwrap(v))
                # an input: its term, its key and (one component) the variable itself
                # … and its user-facing name (`lattice_input_name`), which messages print
                n = get_lattice_input_name(unwrap(v))
                n === nothing || (n = length(ks) == 1 ? n : "$n[$i]"; push!(inputnames, k => n))
                syms = length(ks) == 1 ? Any[term, alias(v, i, 1)..., Symbol(k), op] : Any[term, alias(v, i, 2)..., Symbol(k)]
                n === nothing || push!(syms, Symbol(n))
                push!(inputs, Tuple(syms) => k)
                eltype(SymbolicUtils.symtype(unwrap(v))) <: Bool && push!(boolinputs, k)
                b = _input_bounds(unwrap(v))
                b == (-Inf, Inf) || push!(inputbounds, k => b)
            elseif k in state
                push!(vars, (term, alias(v, i, length(ks))..., Symbol(k)) => FieldSlot(slots[fieldid(s, k)], dims))
            elseif any(q -> q.key == "aux:$k", s.kernels)
                # an aux field `K ~ rhs` (F3 design §3.12): read by `sol[K]` and `integ[K]`
                push!(aux, (term, alias(v, i, length(ks))..., Symbol(k)) => k)
            end
        end
    end
    # (the clock's slot is the stepper's, not a parameter of the problem)
    # (a computed parameter holds a slot but is not a parameter: it is read-only, D-F2-1)
    iscomp(p) = any(k -> isequal(unwrap(first(k)), unwrap(p)), cdefaults)
    params = [(p, Symbol(string(p))) => i for (i, p) in enumerate(cf.params) if !_isclock(p) && !iscomp(p)]
    # a parameter's declared `bounds` (MTK metadata), checked at every write (F2-14)
    parambounds = Pair[i => b for (i, p) in enumerate(cf.params) if !_isclock(p)
                       for b in (_input_bounds(unwrap(p)),) if b != (-Inf, Inf)]
    defaults = Dict{Any, Any}(p => d for (p, d) in zip(cf.params, cf.defaults))
    # a computed parameter reads as its folded expression of the parameter slots (SII observed)
    ps, tt = Any[unwrap(q) for q in cf.params], unwrap(sys.ivs[1])
    observed = Pair[syms => Symbolics.build_function(unwrap(e), ps, tt; expression = Val(true)) for (syms, e) in computed]
    # the computed slots (F2-15): a derivation from the base slots and the tables
    # (every computed parameter is derived, so a chain through one without a slot evaluates;
    # slot 0: none)
    comp = Dict{Any, Any}(unwrap(k) => d for (k, d) in cdefaults)
    derive = nothing
    if any(q -> haskey(comp, unwrap(q)), cf.params)
        base = [(Symbol(string(q)), i) for (i, q) in enumerate(cf.params) if !haskey(comp, unwrap(q)) && !_isclock(q)]
        tabs = [(Symbol(k), String(k)) for (k, _) in cf.tables]
        cks = collect(keys(comp))
        d = derivation(Symbol[first(b) for b in [base; tabs]], Pair[Symbol(string(k)) => comp[k] for k in cks])
        slot(k) = (i = findfirst(q -> isequal(unwrap(q), k), cf.params); i === nothing ? 0 : i)
        derive = (d, Any[last(b) for b in [base; tabs]], Int[slot(k) for k in cks])
    end
    return LatticeIndex(; key = _symkey, variables = vars, parameters = params,
        independent_variables = [unwrap(sys.ivs[1])], defaults, inputs, inputnames, boolinputs, inputbounds, derived,
        observed, parambounds, derive, aux,
        tables = Pair[[Any[unwrap(q), Symbol(k)] => k for (k, _) in cf.tables for q in _params(sys) if string(unwrap(q)) == k];
                      [e => (k, i) for (k, _) in cf.tables for q in _params(sys) if string(unwrap(q)) == k
                       for (i, e) in enumerate(Symbolics.scalarize(unwrap(q)))]])
end

# the declared defaults of the input fields (`dom(..)::Bool = true [input = true]`), as
# `key => value` pairs; an input without one has no value until it is given
function _input_defaults(cf::CompiledField, sys::PDESystem)
    out = Pair{String, Any}[]
    for v in sys.dvs
        u = unwrap(v)
        ModelingToolkitBase.isinput(u) || continue
        op = _opof(u)
        d = ModelingToolkitBase.hasdefault(u) ? ModelingToolkitBase.getdefault(u) :
            ModelingToolkitBase.hasdefault(op) ? ModelingToolkitBase.getdefault(op) : nothing
        d === nothing && continue
        d = unwrap_const(unwrap(d))
        d isa Number || _dverr("input `$(_name(op))`: its default `$d` is not a number (one value for every site)")
        foreach(k -> push!(out, k => d), cf.keys[op])
    end
    return out
end

# Computed parameter defaults (`@parameters k2 = 2a`; F2 design §2.7, D-F2-1): the parameter
# stays a parameter slot of the program, read-only, and the problem's derivation
# (`derivation`, `_index`) fills it from the base parameters after every write. So a face or
# mask value may read it (`Dirichlet(g)` with `g = g1 + g2`). Returns the system (its field
# initial values that read a computed parameter take its expression), the `derived` messages of
# the index, `computed` (each computed parameter with its expression of base parameters, for
# reads) and the raw defaults (for the derivation).
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
        any(c -> _reads_term(x, c), keys(comp)) && _dverr("the computed parameter `$k = $e` depends on itself")
        resolved[k] = x
    end
    plain = Set(unwrap(p) for p in ps if !haskey(comp, unwrap(p)))
    tabs = Set(unwrap(p) for p in ps if !scalar(p))
    for (k, e) in resolved
        free = [v for v in Symbolics.get_variables(e) if !(v in plain) && !(_tabof(v) in tabs) &&
                                                          !any(iv -> isequal(iv, v), unwrap.(sys.ivs))]
        isempty(free) || _dverr("the computed parameter `$k = $(comp[k])` reads $(join(("`$f`" for f in free), ", ")), " *
                                "which $(length(free) == 1 ? "is not a parameter" : "are not parameters") of the system")
    end
    sub(x) = substitute(x, resolved; fold = Val(false))
    symb(v) = v isa Union{Num, SymbolicUtils.BasicSymbolic}
    ic2 = Dict(k => (symb(v) ? sub(v) : v) for (k, v) in ic if !haskey(comp, k))   # field values read them too
    derived = Pair[(k, Symbol(string(k))) => _computed_message(k, comp[k], resolved[k], plain) for k in keys(comp)]
    new = PDESystem(sys.eqs, sys.bcs, getfield(sys, :domain), sys.ivs, sys.dvs, ps; name = nameof(sys),
        initial_conditions = merge(ic2, Dict(k => v for (k, v) in ic if haskey(comp, k))))
    computed = Pair[(k, Symbol(string(k))) => e for (k, e) in resolved]
    return new, derived, computed, Pair[k => comp[k] for k in keys(comp)]
end
_tabof(v) = (u = unwrap(v); iscall(u) && operation(u) === getindex ? unwrap(arguments(u)[1]) : u)
# the refusal of a write of computed parameter `k` (D-F2-1): its expression and inputs, the route
function _computed_message(k, e, resolved, _)
    ins = sort!(unique!(String[string(_tabof(v)) for v in Symbolics.get_variables(resolved)]))
    return string("`", k, "` is computed from ", join(("`$i`" for i in ins), ", "), " (`", k, " = ", e,
        "`): set ", length(ins) == 1 ? "`$(only(ins))`" : "its inputs", "; for a fixed `", k,
        "`, declare it with a number (`@parameters ", k, " = v`)")
end
_reads_term(x, v) = any(y -> isequal(y, v), Symbolics.get_variables(x))

# Values every problem needs before it runs: array parameters (tables) with a value of their
# declared size. Scalar parameters with no value are refused where the problem is stepped.
function _check_tables(cf::CompiledField, sys::PDESystem)
    for (k, vals) in cf.tables
        p = only(q for q in _params(sys) if string(unwrap(q)) == k)
        n = length(Symbolics.scalarize(unwrap(p)))
        isempty(vals) && _dverr("the array parameter `$k` has no value (a table is not read as zeros): give it a " *
                                "default, `@parameters $k[1:$n] = [v₁, …]`")
        length(vals) == n || _dverr("the array parameter `$k` is declared with $n entries; its default has $(length(vals))")
    end
end

# The parameter checks of LatticePDE's stability bound (LatticeFields hooks, F1): negative
# diffusion is refused at every parameter value a problem steps with; an explicit substep
# count is raised to the bound over the terms the bound sees; the substep error names the
# terms the bound cannot see.
function Problems.check_parameters(b::StabilityBound, p)
    r = bound_parts(b, p)
    neg = r.negative
    isempty(neg) && return _check_finite(r)
    _dverr("the diffusion coefficient of the field$(length(neg) == 1 ? "" : "s") $(join(("`$k`" for k in neg), ", ")) " *
           "is negative at these parameters (anti-diffusion: an ill-posed equation, unstable at any step and with any " *
           "solver); write the term with a coefficient ≥ 0 (`D * Δ(c)` with `D ≥ 0`; a decay is a reaction term `-k * c`)")
end
# A coefficient that is not finite at an entry the inputs reach (a zero under a division, a
# negative entry under `sqrt`, a parameter that makes it infinite) gives a rate that is not
# finite there, whatever the substep count or the solver: refused on every path, the owned
# one (count or not) and the ODE one (F2 record (i)). Over the evaluation cap, or without
# tables, there is no value to refuse.
function _check_finite(r)
    bad = [(k, text, w) for (k, text, w) in r.nonfinite if w isa Tuple]
    isempty(bad) && return nothing
    _dverr(string("a rate is not finite where the inputs reach (whatever the substep count or the solver): ",
        join((string(_why_text(_coef_text(text), w), " (in the rate of `", k, "`)", _why_route(w)) for (k, text, w) in bad),
            "; ")))
end
Problems.seen_bound(b::StabilityBound, p) = bound_parts(b, p).seen
# the parts the one substep policy decides on (F3-01): the bound's parts and its unseen terms
function Problems.bound_report(b::StabilityBound, p)
    r = bound_parts(b, p)
    return (; r.negative, r.coupled, r.nonfinite, terms = b.terms, r.seen, r.ρ)
end
function Problems.unbounded_reason(b::StabilityBound, p)
    parts = String[]
    isempty(b.terms) || push!(parts, "the term$(length(b.terms) == 1 ? "" : "s") " *
                                     join((_term_text(t) for t in b.terms), ", ") * ", which the bound cannot see")
    any(isnan, p) && push!(parts, "a parameter without a value")
    r = bound_parts(b, p)
    if !any(isnan, p) && !isfinite(r.ρ)
        for (k, text, w) in r.nonfinite
            push!(parts, string("a coefficient with no finite bound: ", _why_text(_coef_text(text), w), " (in the rate of `$k`)",
                _why_route(w)))
        end
        isempty(r.nonfinite) && push!(parts, "a coefficient with no finite bound")
    end
    c = r.coupled
    isempty(c) || push!(parts, "the coupled rows of $(join(("`$k`" for k in c), ", ")), which are not diagonally " *
                               "dominant (their spectrum may be complex)")
    return isempty(parts) ? nothing : join(parts, "; ")
end

# the reason without values, the warning's once-key (`Problems.unbounded_key`): the terms the
# bound cannot see, and per coefficient with no finite bound its rate, its text and the cause
# (`:cap`, `:tables`, or not finite at some entry), never an entry or a parameter value
function Problems.unbounded_key(b::StabilityBound, p)
    parts = String["unseen: " * t for t in b.terms]
    any(isnan, p) && push!(parts, "a parameter without a value")
    if !any(isnan, p)
        r = bound_parts(b, p)
        for (k, text, w) in r.nonfinite
            push!(parts, string("nonfinite: ", k, ": ", text, " (", w isa Symbol ? w : :entries, ")"))
        end
        isempty(r.coupled) || push!(parts, "coupled: " * join(r.coupled, ", "))
    end
    return isempty(parts) ? nothing : join(sort!(parts), "; ")
end

# a `"key: term"` entry of the bound as the user wrote it: the term, a field read `c(t, x, y)`
# as `c`, and the field whose rate holds it
# a coefficient as the user wrote it: a field read `c(t, x, y)` as `c`
_coef_text(t::AbstractString) = _clocktext(_comptext(replace(t, r"(\w+)\(t(, \w+)*\)" => s"\1", "LatticePDE." => "")))
# a component read `(u(t, x, y))[1]` (once `u(t, x, y)` is `u`) as the user writes it: `u[1]`
_comptext(t) = replace(t, r"\((\w+)\)\[" => s"\1[")
function _term_text(t::AbstractString)
    i = findfirst(": ", t)
    i === nothing && return "`$t`"
    term = _clocktext(_comptext(replace(t[(last(i) + 1):end], r"(\w+)\(t(, \w+)*\)" => s"\1")))
    return "`$term` (in the rate of `$(t[1:(first(i) - 1)])`)"
end

_states(p) = [f.key for f in p.fields if f.role == :state]

"""
    discretize(pdesys, disc::LatticeDiscretization; inputs = (), u0 = nothing, p = nothing, tspan = nothing)

The problem of `pdesys` on the lattice (`disc.problem`):
- `:owned`: a `FieldProblem` (the owned fast path), solved with `ExplicitEuler(; dt,
  substeps)` for rate equations or `ExplicitMap()` for maps;
- `:ode`: an `ODEProblem` whose function is the compiled right side (`LatticeRHS`) with the
  symbol table as `sys`, for SciML solvers;
- `:auto`: `:ode` for rate equations, `:owned` when a discrete map, a masked condition
  (`c ~ masked(pred, v)`, which only the owned path lowers) or a steady row `0 ~ rhs` is
  present, or when the system has only aux equations `K ~ rhs` (no state: the owned path
  evaluates them once per window and `sol[K]`, `integ[K]` read them, F3 design §3.12);
- `:linear`: planned (a `LinearProblem`, F4); refused.

**Steady rows** (F3-12b). `0 ~ rhs` is solved for the field it determines: a state field with
no other equation that the row reads, preferably under a spatial operator (`0 ~ D * Δ(c) - k * c
+ s` is `c`'s); see `steady_rows`. Its group takes `QuasiSteady` only, by default too:
`solve(prob, BackwardEuler(; dt))` steps the other fields with `BackwardEuler` and the steady
ones with `QuasiSteady` at the same window, solved first in each window. A steady field with no
initial value starts at 0. On `:ode` a steady row (a DAE) is planned (F4) and refused.

**Systems with no time** (F3-12b). A system whose variables are the axes only (`[x, y]`, every
row `0 ~ rhs` or an aux field) is a steady system: the problem has `tspan = (0, 0)`, and
`solve(prob)` (or `solve(prob, QuasiSteady(; inner, newton))`) solves it once from the cold
`u0`, with the inner solver to `rtol = 1e-6` within 64 iterations unless `inner` is given. It
returns a one-state solution at t = 0, read by the time-free symbol (`sol[c(x, y)]`). On `:ode`
it is the `SteadyStateProblem` of the right side.

The time span is the domain of the first variable. Fields index solutions and integrators
by symbol (`sol[c(t, x, y)]`, `sol[:c]`) as grid-shaped arrays.

**Keywords** (SciML's `discretize`; the same set on both problem kinds; F2 design §2.8):
- `u0`: the initial values, a flat vector of the state, or `field => values` pairs (an array
  with one value per site, or a number) that override the fields they name;
- `p`: the parameter values, a vector of every parameter, or `parameter => value` pairs (a
  table as `Dk => values`), with `remake`'s rule (a plain value is written into the
  parameter type, a Dual promotes it; under `T = BigFloat` with Float64 defaults a pair's
  BigFloat value rounds to Float64, so declare BigFloat defaults or give a BigFloat vector); a
  computed parameter is refused, naming why;
- `tspan`: the time span `(t₀, t₁)`, over the domain of the first variable;
- `inputs`: the input values (below).
Any other keyword is an `ArgumentError` naming it (the `ODEFunction` keywords `jac` and
`sparse` are planned). `discretize(sys, disc; p = [k => 2.0])` is `remake(discretize(sys,
disc); p = [k => 2.0])`, with no second problem built.

**Inputs.** Input fields (`kindₛ(..)::Int32 [input = true]`, a `domain` mask) are read and
never written by the equations. Give their values with `inputs = [kindₛ => K, dom => M]`
(an array with one value per site, or a number); on the owned path, also later with
`remake(prob; inputs = …)` or `integ[kindₛ] = K` during a run (the masks follow). An input
with a declared default (`dom(..)::Bool = true [input = true]`) needs no value; any other
unset input is an error naming it (at `init` on the owned path, here on the ODE path). An
input is never read as zero.

**Parameters.** A parameter with a default that reads other parameters (`@parameters k2 =
2a`) is computed (D-F2-1): it is read-only and follows `a` at every `remake` and `setp`
(evaluated again from the base parameters, through one compiled [`derivation`](@ref)). Reads
work (`getp(prob, k2)`, `integ.ps[k2]`, `sol.ps[k2]`); a write is an error naming its inputs,
and a face or mask value may read it (`c(t, 0, y) ~ g` with `g = g1 + g2`). An array parameter needs a default of its
declared size. A scalar parameter with no value is an error naming it before the problem
steps (at `init` on the owned path, here on the ODE path, which has no `init`); on the owned
path `remake(prob; p = [k => v])` gives it one. A negative diffusion coefficient, or a NaN
value, is refused at every parameter value a problem steps with: on the ODE path at the first
call of the right side with new values (`remake`, `setp` on an integrator), so `solve` or
`step!` throws and never runs them.

A system mixes no rate equations (`D(c) ~ …`) and maps (`Shift(t, 1)(m) ~ …`) in this
version: one problem steps one kind (split stepping is planned).
"""
function discretize(sys::PDESystem, disc::LatticeDiscretization{N}; inputs = (), u0 = nothing, p = nothing,
        tspan = nothing, kw...) where {N}
    isempty(kw) || _dverr(string("`discretize` takes `inputs`, `u0`, `p`, `tspan`; got ", join(("`$k`" for k in keys(kw)), ", "),
        any(k -> k in (:jac, :sparse), keys(kw)) ? " (the `ODEFunction` keywords `jac` and `sparse` are planned)" : "",
        ": give the other settings to the discretization (`LatticeDiscretization(…; T, problem, clock)`) or to `solve`"))
    _check_parts(sys)
    kind = disc.problem
    kind == :linear && _dverr("problem = :linear (a `LinearProblem` of a steady system) is planned (F4); a steady " *
                              "system (`0 ~ rhs` rows, no time) is solved on the owned path: leave `problem` out and " *
                              "`solve(prob)`")
    # steady rows `0 ~ rhs` as rates of their fields, a system with no time timed (F3-12b)
    free = sys.dvs
    sys, steady, timefree = steady_form(sys, N)
    timefree && tspan !== nothing && _dverr("`tspan`: the system has no time (a steady system, solved once); leave `tspan` out")
    hasmap = check_one_kind(sys)
    hasmask = any(b -> (r = unwrap(b.rhs); iscall(r) && operation(r) === masked), sys.bcs)
    # the clock's step index needs the owned steppers, which land on its boundaries
    hasclock = _reads_step_index(sys)
    # aux equations only (`K ~ rhs`, no state): the owned path evaluates them once per window
    auxonly = !isempty(sys.eqs) && all(eq -> (l = unwrap(eq.lhs); !(iscall(l) && operation(l) isa Union{Differential, Shift})), sys.eqs)
    kind == :auto && (kind = hasmap || hasmask || hasclock || auxonly || !isempty(steady) ? :owned : :ode)
    kind == :ode && hasclock && _dverr("`step_index(t)` needs problem = :owned in this version: an ODE solver does not " *
                                       "land on the clock's boundaries (a discrete parameter updated at them, with " *
                                       "`tstops`, is planned: F4); use problem = :owned or leave `problem` out")
    kind == :ode && hasmap && _dverr("discrete maps have no ODE form; use problem = :owned")
    backend = disc.backend === nothing ? KernelAbstractions.CPU() : disc.backend
    T = _statetype(disc)
    # Cartesian indexing on the host: the host loop hands each site its coordinates (a linear
    # launch decodes them with an integer division per site; D5, as front end A); the option
    # is outside the fingerprint
    options = CompileOptions(; T, index = Exec.ishost(backend) ? :cartesian : :auto)
    span = tspan === nothing ? _domain_ends(sys)[1] : _given_tspan(tspan)
    # the group, lowered once in rate form (the update is fused by the group, per algorithm)
    g = _lower_group(sys, disc; steady, timefree)
    cf, sys, spec = g.cf, g.sys, g.spec
    s = cf.program
    state = spec.state
    index = _index(cf, sys, s, state; g.derived, g.computed, cdefaults = g.defaults, free = timefree ? free : nothing)
    x0 = _given_u0(_initial(cf, sys, state, T), index, u0)
    pv, tables = _given_p(cf.defaults, cf.tables, index, p)
    Problems.derive!(pv, tables, index)                  # the computed slots (F2-15)
    Problems.check_bounds(pv, index)                     # … within their bounds too
    ins = Pair[_input_defaults(cf, sys); collect(inputs)]
    if kind == :owned
        _check_fusion(s, sys, disc)
        return FieldProblem(spec, x0, span, pv; index, tables, inputs = ins, backend, options)
    end
    isempty(spec.init) || _dverr("masked conditions (`c ~ masked(pred, v)`) need problem = :owned in this version")
    !timefree && !isempty(spec.steady) && _dverr(string("problem = :ode: the steady rows of ",
        join(("`$k`" for k in spec.steady), ", "), " make the system a DAE (a mass matrix with zero rows), which is ",
        "planned (F4); solve it on the owned path: leave `problem` out (`QuasiSteady` steps the steady fields), or write ",
        "the rows as rates `D(c) ~ rhs`"))
    rates = Dict(k => "∂$k" for k in state)
    return ode_problem(s, x0, span, pv; state, rates, init = spec.init, index,
        tables, inputs = ins, stability = spec.stability, backend, options, steady = timefree)
end

"""
    check_one_kind(sys; route) -> Bool

Whether `sys` has maps (`Shift(t, 1)(m) ~ rhs`); a system with rate equations and maps both is
refused, naming the fields of each (F1; F2 design §2.11), with the front end's route
(`route`; LatticePDE's: two systems). One problem steps one kind in this version, in both front
ends and however its fields are grouped: a map steps one unit of time, which would step the
rates with no bound, and separate groups would be split stepping (planned, FE-04).
"""
function check_one_kind(sys::PDESystem; route = "discretize them as two systems")
    lhs(eq) = unwrap(eq.lhs)
    name(eq) = (r = lhs(eq); a = iscall(r) ? arguments(r)[1] : r; string(_name(_opof(a))))
    maps = [name(eq) for eq in sys.eqs if iscall(lhs(eq)) && operation(lhs(eq)) isa Shift]
    isempty(maps) && return false
    rate = [name(eq) for eq in sys.eqs if iscall(lhs(eq)) && operation(lhs(eq)) isa Differential]
    isempty(rate) || _dverr("the system mixes rate equations (of $(join(("`$f`" for f in rate), ", "))) and maps " *
                            "(of $(join(("`$f`" for f in maps), ", "))); one problem steps one kind in this version " *
                            "(a map steps at dt = 1, which would step the rates with no bound): $route (split " *
                            "stepping is planned)")
    return true
end

# `discretize`'s keywords (SX-03, F2 design §2.8): the time span, the initial values and the
# parameter values, given as `remake` takes them
function _given_tspan(ts)
    ts isa Union{Tuple, AbstractVector} && length(ts) == 2 && all(v -> v isa Real, ts) ||
        _dverr("`tspan` is `(t₀, t₁)`, two numbers; got $(repr(ts))")
    return (Float64(ts[1]), Float64(ts[2]))
end
function _given_u0(x0, index, u0)
    u0 === nothing && return x0
    if u0 isa AbstractVector{<:Real}
        length(u0) == length(x0) || _dverr("`u0` has $(length(u0)) values; the state has $(length(x0))")
        return collect(u0)
    end
    u0 isa Union{AbstractVector{<:Pair}, Tuple, AbstractDict} ||
        _dverr("`u0` is a flat vector of the state or `field => values` pairs; got a $(typeof(u0))")
    # a Dual value promotes the state, as a Dual parameter does
    E = foldl((T, x) -> last(x) isa Real ? promote_dual(T, typeof(last(x))) :
                        last(x) isa AbstractArray ? promote_dual(T, eltype(last(x))) : T, u0; init = eltype(x0))
    out = Vector{E}(x0)
    for (k, v) in u0
        slot = get(index.vars, index.key(k), nothing)
        Problems.input_key(index, k) === nothing ||
            _dverr("`u0`: `$(_keytext(k))` is an input, not a field of the state: give it with `inputs = [$(_keytext(k)) => values]`")
        slot === nothing && _dverr("`u0`: `$(_keytext(k))` is not a field of the state; its fields: " *
                                   join(("`$(_keytext(f))`" for f in index.varsyms), ", "))
        if v isa Real
            out[slot.range] .= v
        elseif v isa AbstractArray && length(v) == length(slot.range)
            out[slot.range] .= vec(collect(v))
        else
            _dverr("`u0`: give `$k` one value per site ($(length(slot.range))) or a number; got " *
                   (v isa AbstractArray ? "$(length(v)) values" : repr(v)))
        end
    end
    return out
end
function _given_p(defaults, tables, index, p)
    p === nothing && return defaults, tables
    if p isa AbstractVector{<:Real}
        length(p) == length(defaults) || _dverr("`p` has $(length(p)) values; the system has $(length(defaults)) parameters")
        Problems.check_bounds(p, index)              # a declared bound, at the write (F2-14)
        return collect(p), tables
    end
    p isa Union{AbstractVector{<:Pair}, Tuple, AbstractDict} ||
        _dverr("`p` is a vector of every parameter or `parameter => value` pairs; got a $(typeof(p))")
    # a plain value is written into the parameter type, a Dual promotes it (`remake`'s rule)
    P = foldl((T, x) -> last(x) isa Real ? promote_dual(T, typeof(last(x))) : T, p; init = eltype(defaults))
    pv = Vector{P}(defaults)
    tabs = Pair{String, Any}[k => v for (k, v) in tables]
    for (k, v) in p
        t = Problems.table_key(index, k)
        if t !== nothing
            e = Problems.table_entry(index, k)
            e == 0 || _dverr("`p`: `$k` is entry $e of the table `$t`: give the whole table, `$t => values`")
            j = findfirst(x -> first(x) == t, tabs)
            n = length(last(tabs[j]))
            v isa AbstractArray && length(v) == n || _dverr("`p`: the table `$t` has $n entries; give $n values")
            tabs[j] = t => vec(collect(v))
            continue
        end
        i = parameter_index(index, k)                    # a computed parameter, or an unknown name, is an error naming it
        i === nothing && _dverr("`p`: `$(_keytext(k))` is not a parameter of the system")
        pv[i] = v
    end
    Problems.check_bounds(pv, index)                 # a declared bound, at the write (F2-14)
    return pv, tabs
end

# a key as the user wrote it (`c`, not `c(t, x, y)`; `:c` as `c`)
_keytext(k) = replace(string(k), r"\(t(, \w+)*\)" => "", "⋆" => "")

# whether an equation or condition of `sys` reads the clock's step index
function _reads_step_index(sys::PDESystem)
    hit(u) = iscall(u) && (operation(u) === step_index || any(hit, arguments(u)))
    return any(eq -> hit(unwrap(eq.lhs)) || hit(unwrap(eq.rhs)), [sys.eqs; sys.bcs])
end

# The byte-identity gate of the update pass (F2-07; F2 design §2.5), on request: with
# `LATTICEPDE_CHECK_FUSION=1` in the environment, every owned problem checks that its rate
# program with the Euler update fused by the IR pass (`fuse_update`, with and without a clip)
# prints the same semantic program as the symbolic fusion (`symbolic_discretize(…; update)`),
# at Float64 and Float32, and throws otherwise (the test suites run with it)
function _check_fusion(rate::Program, sys::PDESystem, disc)
    get(ENV, "LATTICEPDE_CHECK_FUSION", "") == "1" || return nothing
    any(k -> startswith(k.key, "map:"), rate.kernels) && return nothing
    for lower in (nothing, 0.0)
        alg = ExplicitEuler(; lower)
        sym = symbolic_discretize(sys, disc; update = (kb, c, r) -> (v = euler_update(kb, c, r);
                                                                        lower === nothing ? v : max(v, lower))).program
        pass = fuse_update(rate, Problems.update_rule(alg))
        for T in (Float64, Float32)
            fingerprint_text(pass; T) == fingerprint_text(sym; T) ||
                error("the update pass differs from the symbolic fusion (`$(nameof(sys))`, lower = $lower, T = $T)")
        end
    end
    return nothing
end
