# The operator of an implicit group (F3 design §3.4): the symmetric Helmholtz part `J̃` of each
# row's rate Jacobian, from the linearity table, as a LatticeFields `OperatorSpec`. A row whose
# coefficients are numbers and parameters is numeric (`Coef` sums); a row whose face
# coefficient, multiplier or local coefficient varies by site (coordinates, inputs, tables at
# inputs), or that lives in an irregular domain, gets a `jac:<key>` kernel that writes them per
# site. Built once per group, at its first implicit use (`DeferredOperator`), never for
# explicit groups (S12).

"""
    DeferredOperator

The operator of a group, not built yet: the lowered system that `build_operator` extracts the
`OperatorSpec` from at the group's first implicit use (once: the result is kept).
`OPERATOR_BUILDS` counts the builds of this session (a test reads it: an explicit group builds
none; it starts at 0, the precompile workload's build not counted).
"""
mutable struct DeferredOperator
    cf::Any
    sys::Any
    disc::Any
    built::Any
end
DeferredOperator(cf, sys, disc) = DeferredOperator(cf, sys, disc, nothing)
const OPERATOR_BUILDS = Threads.Atomic{Int}(0)
const _OPERATOR_LOCK = ReentrantLock()

function Problems.build_operator(d::DeferredOperator, spec::Problems.GroupSpec)
    return lock(_OPERATOR_LOCK) do
        d.built === nothing || return d.built
        Threads.atomic_add!(OPERATOR_BUILDS, 1)
        d.built = _build_operator(d.cf, d.sys, d.disc)
    end
end

# a diffusion term `m Op(c)` in parts: the multiplier `m` (the operator replaced by 1), the face
# coefficient `K` (1 for `Δ`), the axes it acts on (every axis for `Δ` and `DivKGrad`, its own
# for a raw `Dx(K Dx(c))`), the face mean and the term itself; `nothing` for more than one operator
function _diffusion_parts(term, xs)
    reps, parts = Dict{Any, Any}(), Any[]
    walk(y) = iscall(y) && (f = operation(y);
                            f === Δ ? (reps[y] = 1; push!(parts, (1, :all, :harmonic))) :
                            f isa DivKGrad ? (reps[y] = 1; push!(parts, (arguments(y)[1], :all, f.mean))) :
                            f isa Differential ? (r = _raw_flux(y); reps[y] = 1;
                                                  push!(parts, (r === nothing || r[1] === nothing ? 1 : r[1],
                                                      findfirst(v -> isequal(v, unwrap(f.x)), xs), :harmonic))) :
                            foreach(walk, arguments(y)))
    walk(unwrap(term))
    length(parts) == 1 || return nothing
    K, ax, mean = only(parts)
    return (m = substitute(term, reps; fold = Val(false)), K, axes = ax, mean, term)
end

_freeof(x, ops) = !_reads(x, ops)
# a term of the rate of `k` in the user's words (`_term_text`), with `Advect`'s scheme type and
# a velocity literal as written (`Advect(Upwind1())([ux, uy], c)`)
function _optext(k, term)
    t = replace(string(term), r"Advect\{\w+\}\(" => "Advect(", "LatticePDE." => "", r"var\"([^\"]+\))(?:#\d+)?\"\(t(, \w+)*\)" => s"\1")
    while (i = findfirst("SymbolicUtils.array_literal(", t)) !== nothing
        j = last(i) + 1                                     # past the opening parenthesis
        depth, q = 1, j
        while depth > 0 && q <= lastindex(t)
            t[q] == '(' && (depth += 1)
            t[q] == ')' && (depth -= 1)
            depth > 0 && (q = nextind(t, q))
        end
        inner = replace(t[j:prevind(t, q)], r"^\(\d+,\), " => "")    # (the shape first)
        t = string(t[1:prevind(t, first(i))], "[", inner, "]", t[nextind(t, q):end])
    end
    return _term_text(string(k, ": ", t))
end

# whether `term` is local in the field `c` (F3-09a): it reads `c` at the site only (offset 0),
# the inputs `I` at the site only, no other field (`others`), and no spatial operator
function _local_term(term, c, I, ivs, others)
    _reads(term, others) && return false
    cref = _ref(c)                              # (a component `u[i]`: its own reads only)
    function ok(u)
        iscall(u) || return true
        f = operation(u)
        _hit(cref, u) && return isequal(u, c)
        any(o -> isequal(f, o), I) && return isequal(collect(arguments(u)), collect(ivs))
        (f === Δ || !(f isa Function)) && return false        # Δ, DivKGrad, Advect, Differential, Shift, …
        return all(a -> ok(unwrap(a)), arguments(u))
    end
    return ok(unwrap(term))
end
# `∂term/∂c` of a local term, by `Symbolics.derivative` (`c` replaced by a plain variable), or
# nothing when a derivative stays unexpanded (a registered function of `c` with no rule)
function _local_derivative(term, c)
    v = Symbolics.variable(:__f3_u)
    d = Symbolics.derivative(substitute(term, Dict(c => v); fold = Val(false)), v)
    _hasdiff(unwrap(d)) && return nothing
    return substitute(d, Dict(unwrap(v) => c); fold = Val(false))
end
_hasdiff(u) = iscall(u) && (operation(u) isa Differential || any(a -> _hasdiff(unwrap(a)), arguments(u)))

# The bound of an advection term `m Advect(u, c)` for the defect correction (F3-09b, FE-11): the
# upwind Gershgorin bound `Σ_a 2 |m u_a| / h_a` as one `Coef` per axis (`2 m u_a / h_a`; its
# absolute value counts), when the multiplier and each velocity component are numbers or a
# number times a parameter; else nothing (a velocity field or an expression: no bound sees it)
function _advection_bound(term, params, h)
    found = Any[]
    walk(y) = iscall(y) && (operation(y) isa Advect ? push!(found, y) : foreach(a -> walk(unwrap(a)), arguments(y)))
    walk(unwrap(term))
    length(found) == 1 || return nothing
    adv = only(found)
    comps = velocity_terms(unwrap(arguments(adv)[1]))
    (comps === nothing || length(comps) != length(h)) && return nothing
    m = substitute(term, Dict(adv => 1); fold = Val(false))
    out = Coef[]
    for (a, ua) in enumerate(comps)
        cu = _coefof(unwrap(substitute(m * ua, Dict(); fold = Val(true))), params)
        cu === nothing && return nothing
        push!(out, Coef(2 * cu.value / h[a], cu.param))
    end
    return out
end
# The same bound for a velocity that varies by site (F3-13; batch 3 review R2: `50(1 + x)`): per
# axis `(; f, text)`, `f(pp) = 2 max|m u_a| / h_a` over the box by the interval evaluator (NaN
# when not finite); nothing when a velocity component or the multiplier reads a field (its
# Jacobian has a cross part the bound does not see) or has no interval rule
function _advection_ibound(k, term, params, tabs, box, h)
    found = Any[]
    walk(y) = iscall(y) && (operation(y) isa Advect ? push!(found, y) : foreach(a -> walk(unwrap(a)), arguments(y)))
    walk(unwrap(term))
    length(found) == 1 || return nothing
    adv = only(found)
    comps = velocity_terms(unwrap(arguments(adv)[1]))
    (comps === nothing || length(comps) != length(h)) && return nothing
    m = substitute(term, Dict(adv => 1); fold = Val(false))
    text = _optext(k, term)
    out = Any[]
    for (a, ua) in enumerate(comps)
        iv = _interval(unwrap(m * ua), params, tabs, box)
        iv === nothing && return nothing
        push!(out, (; f = pp -> (q = iv(pp); v = 2 * max(abs(q[1]), abs(q[2])) / h[a]; isfinite(v) ? v : NaN), text))
    end
    return out
end
# whether `u` applies a spatial operator to a read of `o`
_operator_of(u, o) = iscall(u) && ((f = operation(u); (f === Δ || f isa DivKGrad || f isa Advect || f isa Differential) &&
                                    _reads(u, (o,))) || any(a -> _operator_of(unwrap(a), o), arguments(u)))
# a cross term `a · o` (`CrossLinear`, `o` another field) as (the field's key, `a` as a `Coef`
# or `Coef(NaN)` when it is not a number or a number times a parameter, its text)
function _cross_bound(k, term, others, cf, params, bysite)
    for o in others
        _reads(term, (o,)) || continue
        kk = o isa _Comp ? (ks = get(cf.keys, o.op, nothing); ks === nothing ? nothing : [ks[o.i]]) : get(cf.keys, o, nothing)
        (kk === nothing || length(kk) != 1) && return ("", Coef(NaN), _optext(k, term))
        c = nothing
        u = unwrap(term)
        # an operator of the other field (`D Δ(o)`, cross-diffusion): no coefficient bounds it
        # here; it stays in the residual (a defect term the Newton check covers, r3 N1)
        _operator_of(u, o) && return (only(kk), Coef(NaN), _optext(k, term))
        # `a · o(t, x, y)`: the coefficient is the term with the read replaced by 1
        reads = Any[]
        w(y) = iscall(y) && (_hit(o, y) ? push!(reads, y) : foreach(a -> w(unwrap(a)), arguments(y)))
        w(u)
        if length(reads) == 1
            a = substitute(term, Dict(only(reads) => 1); fold = Val(false))
            c = bysite(a) || _reads(a, (o,)) ? nothing : _coefof(unwrap(substitute(a, Dict(); fold = Val(true))), params)
        end
        return (only(kk), c === nothing ? Coef(NaN) : c, _optext(k, term))
    end
    return ("", Coef(NaN), _optext(k, term))
end
# a cross diffusion term `m Op(o)` of another field `o` (key `key`) with a numeric face
# coefficient (a number or a number times a parameter, free of the coordinates and the inputs):
# its faces per axis `m K / h_a²` (a hexagonal lattice: per face direction, `2m/(3h²)`) as `Coef`s (F3-12d: the coupled steady system's modes);
# `nothing` otherwise
function _cross_faces(term, key, xs, params, bysite, h, N; hex::Bool = false)
    key == "" && return nothing
    p = _diffusion_parts(term, xs)
    (p === nothing || bysite(p.m) || bysite(p.K)) && return nothing
    mK = _coefof(unwrap(substitute(p.m * p.K, Dict(); fold = Val(true))), params)
    mK === nothing && return nothing
    faces = [Coef[] for _ in 1:(hex ? 3 : N)]       # (a hexagonal lattice: its three face directions)
    for a in (hex ? (1:3) : p.axes === :all ? (1:N) : (p.axes,))
        push!(faces[a], Coef(mK.value * (hex ? 2 / (3 * h[1]^2) : 1 / h[a]^2), mK.param))
    end
    return faces
end
# An interval bound of a coefficient (M3): a function `pp -> (lo, hi)` of the parameters (a
# `Problems.ParamsTables`, or the raw vector: a table read is then unbounded), with a parameter
# at its value, a coordinate over the box, a table read over the table's entries (and the 0 an
# index 0 reads), an indicator in [0, 1] and a switch over both arms; `nothing` when the
# coefficient reads anything else (the time, a field, an input outside a table read) or keeps
# a call with no interval rule
_ihull(a, b) = (min(a[1], b[1]), max(a[2], b[2]))
_iabs(a) = a[1] >= 0 ? a : a[2] <= 0 ? (-a[2], -a[1]) : (0.0, max(-a[1], a[2]))
function _imul(a, b)
    v = (a[1] * b[1], a[1] * b[2], a[2] * b[1], a[2] * b[2])
    any(isnan, v) && return (-Inf, Inf)
    return (minimum(v), maximum(v))
end
_iinv(a) = a[1] > 0 || a[2] < 0 ? (1 / a[2], 1 / a[1]) : (-Inf, Inf)
function _ipow(a, n)
    if n isa Integer || (n isa AbstractFloat && isinteger(n))
        k = Int(n)
        k == 0 && return (1.0, 1.0)
        k < 0 && return _ipow(_iinv(a), -k)
        iseven(k) && return (b = _iabs(a); (b[1]^k, b[2]^k))
        return (a[1]^k, a[2]^k)
    end
    a[1] >= 0 || return (-Inf, Inf)
    return n >= 0 ? (a[1]^n, a[2]^n) : (a[2]^n, a[1]^n)
end
function _interval(x, params::Dict{Any, Int}, tabs, box)
    u = unwrap(x)
    v = unwrap_const(_unid(u))
    v isa Real && return _ -> (Float64(v), Float64(v))
    haskey(params, u) && return (i = params[u]; pp -> (v = Float64(primal(pp[i])); (v, v)))
    for (xv, b) in box
        # (a `TimeSpan` is read at each evaluation: the time window of F4-12b)
        isequal(xv, u) && return b isa TimeSpan ? (_ -> (b.lo, b.hi)) : (_ -> b)
    end
    iscall(u) || return nothing
    f, a = operation(u), arguments(u)
    if (f === at || f === getindex) && length(a) == 2 && haskey(tabs, unwrap(a[1]))
        k = tabs[unwrap(a[1])]
        return pp -> begin
            pp isa Problems.ParamsTables || return (-Inf, Inf)
            j = findfirst(q -> first(q) == k, pp.tables)
            (j === nothing || isempty(last(pp.tables[j]))) && return (-Inf, Inf)
            w = last(pp.tables[j])
            (min(0.0, Float64(minimum(w))), max(0.0, Float64(maximum(w))))
        end
    end
    (f === ismember || f in (==, <, <=, >, >=, !=)) && return _ -> (0.0, 1.0)
    f === identity && length(a) == 1 && return _interval(a[1], params, tabs, box)
    if f === ifelse
        b2, b3 = _interval(a[2], params, tabs, box), _interval(a[3], params, tabs, box)
        (b2 === nothing || b3 === nothing) && return nothing
        return pp -> _ihull(b2(pp), b3(pp))
    end
    bs = [_interval(y, params, tabs, box) for y in a]
    any(isnothing, bs) && return nothing
    f === (+) && return pp -> foldl((r, b) -> (q = b(pp); (r[1] + q[1], r[2] + q[2])), bs; init = (0.0, 0.0))
    f === (*) && return pp -> foldl((r, b) -> _imul(r, b(pp)), bs; init = (1.0, 1.0))
    f === (-) && length(bs) == 1 && return pp -> (q = bs[1](pp); (-q[2], -q[1]))
    f === (-) && return pp -> (q = bs[1](pp); w = bs[2](pp); (q[1] - w[2], q[2] - w[1]))
    f === (/) && return pp -> _imul(bs[1](pp), _iinv(bs[2](pp)))
    if f === (^)
        n = unwrap_const(_unid(unwrap(a[2])))
        n isa Real && return pp -> _ipow(bs[1](pp), n)
        return nothing
    end
    f === abs && return pp -> _iabs(bs[1](pp))
    f === exp && return pp -> (q = bs[1](pp); (exp(q[1]), exp(q[2])))
    f === sqrt && return pp -> (q = bs[1](pp); q[1] >= 0 ? (sqrt(q[1]), sqrt(q[2])) : (-Inf, Inf))
    f === min && return pp -> (qs = map(b -> b(pp), bs); (minimum(first, qs), minimum(last, qs)))
    f === max && return pp -> (qs = map(b -> b(pp), bs); (maximum(first, qs), maximum(last, qs)))
    (f === sin || f === cos) && return _ -> (-1.0, 1.0)
    return nothing
end
# the Gershgorin bound of a diffusion term out of the operator, `4 max|m| max|K| Σ_a 1/h_a²`
# over its axes, as a function of the parameters (NaN when it is not finite); nothing when its
# multiplier or face coefficient has no interval bound
function _diffusion_bound(p, params, tabs, box, h)
    bm, bK = _interval(p.m, params, tabs, box), _interval(p.K, params, tabs, box)
    (bm === nothing || bK === nothing) && return nothing
    s = p.axes === :all ? sum(1 / x^2 for x in h) : 1 / h[p.axes]^2
    return pp -> (v = 4 * s * _iabs(bm(pp))[2] * _iabs(bK(pp))[2]; isfinite(v) ? v : NaN)
end
# The face-wise ratio θ of a diffusion term `p` left out of a scaled row to the row's kept
# term `q` (R2-M1): `max|m_p| max|K_p| / (min m_q min K_q)` over the box, as a function of the
# parameters (NaN when the kept term's multiplier or face coefficient is not bounded below by
# a positive value there, or the ratio is not finite); nothing when the left-out term acts on
# an axis the kept one does not, or a coefficient has no interval bound. With
# `L_out ≼ θ L_kept`, the defect correction contracts by `θ` at any step size
function _diffusion_ratio(p, q, params, tabs, box)
    q.axes === :all || p.axes == q.axes || return nothing
    bm, bK = _interval(p.m, params, tabs, box), _interval(p.K, params, tabs, box)
    qm, qK = _interval(q.m, params, tabs, box), _interval(q.K, params, tabs, box)
    any(isnothing, (bm, bK, qm, qK)) && return nothing
    return pp -> begin
        lm, lK = qm(pp)[1], qK(pp)[1]
        (lm > 0 && lK > 0) || return NaN
        v = _iabs(bm(pp))[2] * _iabs(bK(pp))[2] / (lm * lK)
        isfinite(v) ? v : NaN
    end
end
# The largest face coefficient of a field row on each axis (rate units: `Σ max|m| max|K| / h_a²`
# over the row's operator terms), as a function of the parameters (NaN entries when not finite),
# or nothing when a coefficient has no interval bound: it bounds the part `w |d⁻|` of a Robin
# face with a negative diagonal left out of the operator (R2-S1)
function _face_max(diff, params, tabs, box, h, N)
    parts = Any[]
    for p in diff
        bm, bK = _interval(p.m, params, tabs, box), _interval(p.K, params, tabs, box)
        (bm === nothing || bK === nothing) && return nothing
        push!(parts, (bm, bK, p.axes))
    end
    return pp -> ntuple(N) do a
        v = 0.0
        for (bm, bK, ax) in parts
            (ax === :all || ax == a) || continue
            v += _iabs(bm(pp))[2] * _iabs(bK(pp))[2] / h[a]^2
        end
        isfinite(v) ? v : NaN
    end
end
# a coefficient as a `Coef` (a number, a parameter, a number times a parameter), or nothing
_coefof(x, params) = (x isa Number ? Coef(Float64(x)) : _coef(x, params))

function _build_operator(cf::CompiledField{N}, sys::PDESystem, disc::LatticeDiscretization) where {N}
    s = cf.program
    ivs = unwrap.(sys.ivs)
    xs = ivs[2:end]
    states = Set(_states(s))
    params = Dict{Any, Int}(unwrap(q) => i for (i, q) in enumerate(cf.params))
    dvs = Dict{String, Any}()
    for v in sys.dvs, (op, kk) in cf.keys
        isequal(_opof(v), op) || continue
        u = unwrap(v)
        for (i, k) in enumerate(kk)
            k in states && (dvs[k] = length(kk) == 1 ? u : unwrap(Symbolics.wrap(u)[i]))
        end
    end
    # a hexagonal lattice (F3-20): its Laplacian `2/(3h²) Σₙ (cₙ − c)` has three face directions,
    # `+e₁`, `+e₂` and `+e₁ − e₂`, each with the face `2/(3h²)` (only `Δ` lowers there)
    hex = s.hierarchy[1].grid.geometry == HEX
    NF = hex ? 3 : N
    domain = s.hierarchy[1].grid.domain != 0
    # the coordinates and the inputs: a coefficient that reads them varies by site
    inputops = unique([_opof(v) for v in unwrap.(sys.dvs) if ModelingToolkitBase.isinput(v)])
    siteops = Any[inputops; xs]
    tabs = Set(unwrap(q) for q in _params(sys) if SymbolicUtils.symtype(unwrap(q)) <: AbstractArray)
    readsx(x) = any(v -> any(y -> isequal(y, v), xs), Symbolics.get_variables(x))
    bysite(x) = _reads(x, siteops) || _reads(x, collect(tabs)) || any(v -> any(y -> isequal(y, v), xs), Symbolics.get_variables(x))
    # the fields a term may read besides the row's own: the states (an array field by its
    # components) and the aux fields
    # the bounds of a diffusion term left out of a scaled row's operator: the parameters by
    # slot, the tables by key, the coordinates over the box and one spacing past it (the
    # ghost sites), and the defaults that choose the term kept
    tabset = Dict{Any, String}(u => string(u) for u in tabs if string(u) in first.(cf.tables))
    # each row's grid spacing (a `Coarse` field's `k h`, F3-16); the box reaches one spacing of the
    # coarsest grid past the domain
    fdims = Int.(Tuple(s.hierarchy[1].grid.dims))
    rowh(k) = level_spacing(s.spacing, fdims, s.fields[fieldid(s, k)].levels[1])
    hg = level_spacing(s.spacing, fdims, length(s.hierarchy) - 1)
    box = map(xs) do v
        kk = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        a = findfirst(isequal(v), xs)
        v => (Float64(leftendpoint(sys.domain[kk].domain)) - hg[a], Float64(rightendpoint(sys.domain[kk].domain)) + hg[a])
    end
    # the site centers' box (a multiplier is read at the row's own site; a coarse row's centers lie inside)
    cbox = map(xs) do v
        kk = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        a = findfirst(isequal(v), xs)
        v => (Float64(leftendpoint(sys.domain[kk].domain)) + s.spacing[a] / 2, Float64(rightendpoint(sys.domain[kk].domain)) - s.spacing[a] / 2)
    end
    pp0 = Problems.ParamsTables(collect(Any, cf.defaults),
        Pair{String, Vector{Float64}}[first(q) => Float64.(collect(last(q))) for q in cf.tables])
    staterefs = unique([_ref(v) for v in values(dvs)])     # the group's own states (no aux field, no input)
    allops = Any[unique([_ref(v) for v in values(dvs)]);
                 unique([_opof(v) for v in unwrap.(sys.dvs) if !haskey(cf.keys, _opof(v)) ||
                                                               !any(k -> k in states, cf.keys[_opof(v)])])]
    # the group's states each aux field reads, through the aux fields it reads in turn (a term
    # that reads an aux field is a cross term of those states, or a source when it reads none:
    # `0.5 L` with `L ~ Δ(c)`, F3-22; the residual kernel of a row evaluates the aux kernels it
    # reads at the stored values, so in solve order the term is exact in an acyclic group)
    auxdef = Tuple{Any, Any}[]                  # (aux field, its right side)
    for eq in sys.eqs
        l = unwrap(eq.lhs)
        (iscall(l) && !(operation(l) isa Union{Differential, Shift})) || continue
        o = _opof(l)
        (any(r -> isequal(r, o), staterefs) || any(i -> isequal(i, o), inputops)) || push!(auxdef, (o, eq.rhs))
    end
    auxrd = [Any[] for _ in auxdef]
    for _ in 0:length(auxdef)                   # a fixpoint over the aux chain
        for (j, (_, rhs)) in enumerate(auxdef), q in staterefs
            _reads(rhs, (q,)) && !any(x -> isequal(x, q), auxrd[j]) && push!(auxrd[j], q)
        end
        for (j, (_, rhs)) in enumerate(auxdef), (j2, (o2, _)) in enumerate(auxdef)
            _reads(rhs, (o2,)) || continue
            foreach(q -> any(x -> isequal(x, q), auxrd[j]) || push!(auxrd[j], q), auxrd[j2])
        end
    end
    auxof(term) = [j for (j, (o, _)) in enumerate(auxdef) if _reads(term, (o,))]
    t0 = Float64(_domain_ends(sys)[1][1])     # (a face's time from the system's start, F4-12b)
    rows = Problems.RowOperator[]
    plans = Dict{String, Any}()                 # field rows: what their `jac:` kernel writes
    for k in _states(s)
        haskey(cf.linearity, k) || continue
        c = dvs[k]
        hk = rowh(k)
        faces = [Coef[] for _ in 1:NF]
        jloc = Coef[]
        diff = Any[]                            # (multiplier, K, axes, mean) of the row's diffusion terms
        jterms = Any[]                          # the local coefficients
        inexact = String[]
        scaled = false
        field = domain
        iterate = switch = false                # a local Jacobian at the iterate; a switch term
        others = [o for o in allops if !isequal(o, _ref(c)) && !any(i -> isequal(i, o), inputops)]
        adv = Any[]                             # the advection bound (F3-09b, F3-13), per term and axis
        cross = Tuple{String, Coef, String}[]   # the cross terms: (field, coefficient, text)
        crossfaces = Tuple{String, Vector{Vector{Coef}}}[]  # a cross diffusion `D Δ(o)`: (field, faces per axis)
        unseen = String[]                       # terms out of the operator that no bound sees
        # linear in the group's state: every term's class is (F3-12d: the coupled solve's
        # directional difference is then exact at any step)
        linear = all(x -> last(x) in (:Diffusion, :SiteDiffusion, :LinearLocal, :Advection, :CrossLinear, :Source), cf.linearity[k])
        for (term, class) in cf.linearity[k]
            if class in (:Diffusion, :SiteDiffusion)
                p = _diffusion_parts(term, xs)
                if p === nothing
                    push!(inexact, _optext(k, term))
                    push!(unseen, _optext(k, term))
                    continue
                end
                # a multiplier that reads the coordinates (`(1 + x) Δ(c)`, a `Diffusion` term) is a
                # site multiplier as well: its Jacobian row is `m_i Σ_f K_f (c_n − c_i)`, not a
                # symmetric face `m K` (F3-24), so the row is scaled by `1/m` as `SiteDiffusion`
                (class == :SiteDiffusion || readsx(p.m)) && (scaled = true)
                push!(diff, p)
            elseif class == :LinearLocal
                push!(jterms, substitute(term, Dict(c => 1); fold = Val(false)))
            elseif class == :Source
                continue                        # residual only, exact
            elseif class == :CrossLinear
                # residual only, exact in solve order; its coefficient bounds a cycle's correction
                cb = _cross_bound(k, term, others, cf, params, bysite)
                push!(cross, cb)
                cfc = _cross_faces(term, cb[1], xs, params, bysite, hk, N; hex)
                cfc === nothing || push!(crossfaces, (cb[1], cfc))
            elseif class == :Advection && (ab = something(_advection_bound(term, params, hk),
                                                          _advection_ibound(k, term, params, tabset, box, hk), Some(nothing))) !== nothing
                # out of the operator (a defect correction) with a bound: the count rule 2 (a
                # velocity that varies by site, bounded over the box: F3-13, review R2 of batch 3)
                push!(inexact, _optext(k, term))
                append!(adv, ab)
            elseif class in (:LaggedSwitch, :Other) && _local_term(term, c, inputops, ivs, others) &&
                   (dj = _local_derivative(term, c)) !== nothing
                # a local nonlinear term `f(c)` or a switch: `∂f/∂c` at the iterate (F3-09a),
                # exact as a Newton step; the `jac:` kernel runs at every Newton iteration
                push!(jterms, dj)
                iterate = true
                switch |= class == :LaggedSwitch
            elseif class === :Other && !_reads(term, (_ref(c),)) && !isempty(auxof(term)) &&
                   (rd = unique(vcat([auxrd[j] for j in auxof(term)]..., Any[o for o in staterefs if _reads(term, (o,))]));
                    !any(o -> isequal(o, _ref(c)), rd))
                # a term of aux fields: a cross term of the states they read, none when they read
                # no state (a source). Exact in solve order, like any cross term; a cycle leaves it unseen
                for o in rd
                    push!(cross, (first(_cross_bound(k, term, (o,), cf, params, bysite)), Coef(NaN), _optext(k, term)))
                end
            elseif class in (:LaggedSwitch, :Other) && !_reads(term, (_ref(c),)) &&
                   (rd = [o for o in others if _reads(term, (o,))]; !isempty(rd) && all(o -> any(r -> isequal(r, o), staterefs), rd))
                # a term of other rows' fields only, whatever its form (design §3.4, review r1 M3):
                # a source when the row is solved after them (exact in an acyclic group); one
                # cross entry per field it reads, with no coefficient (a cycle leaves it unseen)
                for o in rd
                    push!(cross, (first(_cross_bound(k, term, (o,), cf, params, bysite)), Coef(NaN), _optext(k, term)))
                end
            else
                push!(inexact, _optext(k, term))
                push!(unseen, _optext(k, term))
            end
        end
        # a scaled row (`m Δ(c)`): one face operator; terms with the same face coefficient
        # combine (`m Δ(c) + D Δ(c)` is `(m + D) Δ(c)`). The face coefficient kept is the one
        # whose terms have the largest bound at the defaults (a term with no bound counts as
        # the largest: no bound could cover it out of the operator); the others stay out with
        # their Gershgorin bound (count rule 2), or unseen when they have none (M3), and their
        # face-wise ratio θ to the kept term (R2-M1: with a kept multiplier bounded below, the
        # correction contracts by θ at any step, and the bound is used only when θ > 1/2)
        bounds = Tuple{Any, String, Any}[]
        msign = Tuple{Any, String, String}[]
        if scaled
            same(p, q) = isequal(unwrap(p.K), unwrap(q.K)) && p.axes == q.axes && p.mean == q.mean
            bs = [_diffusion_bound(p, params, tabset, box, hk) for p in diff]
            size_(i) = (b = bs[i]; b === nothing ? Inf : (v = b(pp0); isnan(v) ? Inf : v))
            heads = unique(i -> findfirst(j -> same(diff[j], diff[i]), eachindex(diff)), eachindex(diff))
            groupsize(i) = sum(size_(j) for j in eachindex(diff) if same(diff[j], diff[i]))
            best = heads[argmax([groupsize(i) for i in heads])]
            keep = [p for p in diff if same(p, diff[best])]
            b0 = diff[best]
            kept = (m = sum(p.m for p in keep), K = b0.K, axes = b0.axes, mean = b0.mean, term = keep[1].term)
            for (i, p) in enumerate(diff)
                same(p, diff[best]) && continue
                push!(inexact, _optext(k, p.term))
                bs[i] === nothing ? push!(unseen, _optext(k, p.term)) :
                push!(bounds, (bs[i], _optext(k, p.term), _diffusion_ratio(p, kept, params, tabset, box)))
            end
            diff = Any[kept]
            # a coordinate multiplier that may be negative over the site centers (F3-24): the
            # scaled row drops the diffusion at a site with `m < 0`, so the operator is not the
            # Jacobian there; its smallest value at the parameters, checked at bind and at writes
            if readsx(kept.m)
                im = _interval(unwrap(kept.m), params, tabset, cbox)
                f = im === nothing ? (_ -> NaN) : (pp -> (v = Float64(im(pp)[1]); isnan(v) ? NaN : v))
                push!(msign, (f, _term_text(string(kept.m)), _optext(k, kept.term)))
            end
        end
        for p in diff
            mK = scaled ? nothing : _coefof(unwrap(substitute(p.m * p.K, Dict(); fold = Val(true))), params)
            if !scaled && !bysite(p.m) && !bysite(p.K) && mK !== nothing
                for a in (hex ? (1:3) : p.axes === :all ? (1:N) : (p.axes,))
                    push!(faces[a], Coef(mK.value * (hex ? 2 / (3 * hk[1]^2) : 1 / hk[a]^2), mK.param))
                end
            else
                field = true
            end
        end
        for j in jterms
            cj = bysite(j) ? nothing : _coefof(unwrap(j), params)
            cj === nothing ? (field = true) : push!(jloc, cj)
        end
        field |= scaled | iterate
        # a Robin face whose α or β varies by site or in time (F4-12b): the row writes its
        # boundary diagonal per site (its `jac:` kernel evaluates the coefficients there)
        field |= any(q -> q[1] == k, Base.keys(cf.sitecoefs))
        # a numeric row needs a face on every axis that has neighbors (a raw `Dx(Dx(c))` in 2D
        # has none on `y`): such a row writes its faces per site (zero faces are allowed there)
        hasdiff = !isempty(diff)
        if hasdiff && !field && any(a -> s.hierarchy[1].grid.dims[a] > 1 && isempty(faces[a]), 1:N)
            field = true
        end
        local_only = !hasdiff
        facemax = field && hasdiff ? _face_max(diff, params, tabset, box, hk, N) : nothing
        # a field row's largest local Jacobian over the box (F3-13: `8(1 + x) c`), so count rule 1
        # keeps its growth out of the shift instead of the clamp
        jmax = nothing
        if field && !isempty(jterms)
            # (the local Jacobian at the iterate reads the field: over its declared interval)
            fbox = [box; [(q[1], q[2]) for q in _bound_box(cf, sys; ghost = true) if !any(x -> isequal(x, q[1]), xs)]]
            ij = _interval(sum(jterms), params, tabset, fbox)
            ij === nothing || (jmax = pp -> (v = ij(pp)[2]; isfinite(v) ? max(v, 0.0) : NaN))
        end
        if field
            plans[k] = (; diff, jterms, scaled, local_only)
        end
        # the faces whose α or β varies by site or in time: the ghost diagonal over the face's
        # sites at any time (F4-12b)
        sitefaces = Tuple{Int, Int, Any}[(a, side < 0 ? 1 : 2, _site_diag(cf, k, a, side, params, tabset,
                                              Any[cbox; (ivs[1], (t0, Inf), "")]))
                                         for (kk, a, side) in sort!(collect(Base.keys(cf.sitecoefs))) if kk == k]
        push!(rows, Problems.RowOperator(k, faces, jloc, field, scaled, domain, local_only, isempty(inexact), inexact,
            iterate, switch, adv, cross, unseen, bounds, facemax, jmax, linear, crossfaces, msign, sitefaces))
    end
    jac = isempty(plans) ? nothing : _jac_program(cf, sys, disc, plans, params, xs)
    return Problems.OperatorSpec{N}(rows, jac)
end

# The operator program: the rate program's fields (no scratch `∂c`, no kernels, no rules) and
# per field row a kernel `jac:<key>` that writes its site values (F3 design §3.4): the faces
# `jac:<key>.w<a>` (to `+e_a`, `K_f/h_a²`, 0 across the edge of an irregular domain; a
# boundary face of the box is not a face of the solver), the local Jacobian `.j`, the boundary
# diagonal `.d` of the face conditions (`w_b d⁺`, `w_b` the boundary face `K(i)/h²` and `d⁺`
# the positive part of the ghost rule, `Solvers.robin_parts`: Dirichlet 2), with `scaled` the
# multiplier `.m`, and with a domain its indicator `.dom`
function _jac_program(cf::CompiledField{N}, sys::PDESystem, disc::LatticeDiscretization, plans, params, xs) where {N}
    s = cf.program
    hex = s.hierarchy[1].grid.geometry == HEX
    pb = ProgramBuilder(s.hierarchy[1].grid; periodic = s.periodic, spacing = s.spacing, nparams = s.nparams)
    pb.hierarchy = copy(s.hierarchy)
    for f in s.fields
        startswith(f.key, "∂") && continue
        push!(pb.fields, f)
    end
    append!(pb.tables, s.tables)
    append!(pb.masks, [MaskDecl(m.key, fieldid_in(pb, s.fields[m.field].key), m.epoch) for m in s.masks
                       if !startswith(s.fields[m.field].key, "∂")])
    # the lowering's environment over these fields
    fids = Dict{Any, Tuple{Vector{Int32}, Scalar}}()
    for (op, ks) in cf.keys
        all(k -> any(f -> f.key == k, pb.fields), ks) || continue
        ids = Int32[fieldid_in(pb, k) for k in ks]
        fids[op] = (ids, pb.fields[ids[1]].storage)
    end
    tables = Dict{Any, Tuple{Int32, Scalar}}()
    for q in _params(sys)
        u = unwrap(q)
        SymbolicUtils.symtype(u) <: AbstractArray || continue
        i = findfirst(t -> t.key == string(u), pb.tables)
        i === nothing || (tables[u] = (Int32(i), pb.tables[i].storage))
    end
    spacing = Dict{Any, Int}(p => get_lattice_spacing(p) for p in keys(params) if !(SymbolicUtils.symtype(p) <: AbstractArray) &&
                                                                    get_lattice_spacing(p) !== nothing)
    ends = map(xs) do v
        kk = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        Float64(leftendpoint(sys.domain[kk].domain))
    end
    lo = ntuple(d -> ends[d], N)
    h = s.spacing
    domid = s.hierarchy[1].grid.domain == 0 ? Int32(0) : fieldid_in(pb, s.fields[s.masks[s.hierarchy[1].grid.domain].field].key)
    # a row's kernel runs on its field's grid (a `Coarse` field's, with its spacing, F3-16)
    fdims = ntuple(d -> Int(s.hierarchy[1].grid.dims[d]), N)
    flev = Dict{Any, Int}(op => Int(pb.fields[ids[1]].levels[1]) for (op, (ids, _)) in fids if !(op isa Tuple))
    # the domain on a row's level (a coarse row's: the domain folded onto its grid, F3-16)
    domat(L) = domid == 0 || L == 0 ? domid : fieldid_in(pb, "domain:$L")
    env(kb, L) = Env(kb, fids, params, tables, spacing, unwrap(sys.ivs[1]), xs, lo, level_spacing(h, fdims, L), false,
        ntuple(_ -> 0, N), RESOLVE, nothing, false, domat(L), Int32[], L, flev, fdims, 0)
    for (k, pl) in sort!(collect(plans); by = first)
        id = fieldid_in(pb, k)
        lane = pb.fields[id].storage
        L = Int(pb.fields[id].levels[1])
        dlid = domat(L)
        # the operator's site values in the row's solve type: a declared Float32 or Float64
        # storage's own (`fixed`), a Float16 field's the problem's value type (it is solved in it)
        fx = pb.fields[id].fixed
        lane == F16 && (lane = F32)
        out(name; storage = lane) = field!(pb, "jac:$k.$name"; storage, role = :aux, levels = Int8[L], fixed = fx && storage != U8)
        wids = pl.local_only ? Int32[] : Int32[out("w$a") for a in 1:(hex ? 3 : N)]
        jid = isempty(pl.jterms) ? Int32(0) : out("j")
        did = pl.local_only ? Int32(0) : out("d")
        mid = pl.scaled ? out("m") : Int32(0)
        dmid = dlid == 0 ? Int32(0) : out("dom"; storage = U8)
        kb = L == 0 ? kernel(pb) : kernel(pb, Space{N}(FULL; level = L))
        e = env(kb, L)
        zero_ = constant!(kb, 0.0)
        indom(o) = dlid == 0 ? nothing : _indomain(kb, dlid, N, o)
        inside(o) = node!(kb, INSIDE_OP, BOOL, Int32[], access!(kb, Access{N}(id, Int8(0), Sel(Int16(1)),
            Sel(NTuple{N, Int16}(o)), Int8(0), INSIDE)))
        if !pl.local_only && hex
            # a hexagonal lattice: the three faces `m · 2/(3h²)` (`Δ` alone lowers there, `K = 1`),
            # 0 across the box or the domain's edge; the boundary diagonal `w d⁺` of each link that
            # leaves the box, with the condition of the face it leaves through (axis 1's for a
            # diagonal link that leaves along axis 1, else axis 2's: `_hexlap`, `Solvers._hexghost`)
            p = pl.scaled ? only(pl.diff) : nothing
            wl = zero_
            for q in pl.diff
                mult = pl.scaled ? constant!(kb, 1.0) : _real(e, lower(q.m, e))
                wl = _op(e, ADD, wl, _op(e, MUL, constant!(kb, 2 / (3 * e.h[1]^2)), mult))
            end
            for (a, o) in enumerate(((1, 0), (0, 1), (1, -1)))
                w = wl
                all(s.periodic) || (w = select!(kb, inside(o), w, zero_))
                dlid == 0 || (w = select!(kb, node!(kb, AND, BOOL, Int32[indom((0, 0)), indom(o)]), w, zero_))
                store!(kb, wids[a], lane, w)
            end
            function dplus(a, side)            # the ghost rule's `d⁺` of face (a, side), or nothing
                s.periodic[a] && return nothing
                r = findfirst(x -> x isa FaceRule && x.field == fieldid(s, k) && x.axis == a && x.side == side, s.rules)
                r === nothing && return nothing
                fr = s.rules[r]
                (fr.alpha.param == 0 && fr.alpha.value == 0) && return nothing
                α, β = _facecoefs(e, kb, cf, k, a, side, fr)
                return _op(e, MAX, _op(e, DIV, α, _op(e, ADD, _op(e, MUL, constant!(kb, 0.5), α), β)), zero_)
            end
            dsum = zero_
            for o in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
                if all(!iszero, o)
                    d1, d2 = dplus(1, o[1]), dplus(2, o[2])
                    (d1 === nothing && d2 === nothing) && continue
                    t2 = d2 === nothing ? zero_ : select!(kb, inside((0, o[2])), zero_, d2)
                    dd = select!(kb, inside((o[1], 0)), t2, d1 === nothing ? zero_ : d1)
                else
                    a = o[1] != 0 ? 1 : 2
                    d0 = dplus(a, o[a])
                    d0 === nothing && continue
                    dd = select!(kb, inside(o), zero_, d0)
                end
                dsum = _op(e, ADD, dsum, _op(e, MUL, wl, dd))
            end
            store!(kb, did, lane, dsum)
            pl.scaled && store!(kb, mid, lane, _real(e, lower(p.m, e)))
        elseif !pl.local_only
            p = pl.scaled ? only(pl.diff) : nothing     # (a scaled row: the combined term)
            dsum = zero_
            for a in 1:N
                o = _unit(e, a, 1)
                w = zero_
                wb = (zero_, zero_)             # the boundary faces' K(i)/h², low and high
                for q in pl.diff
                    (q.axes === :all || q.axes == a) || continue
                    mult = pl.scaled ? constant!(kb, 1.0) : _real(e, lower(q.m, e))
                    one_ = q.K isa Number && q.K == 1
                    Kc = one_ ? constant!(kb, 1.0) : _real(e, lower(q.K, e))
                    # the face to offset `oo` as the rate's lowering forms it (`_secdiff`: the
                    # coefficient at the neighbor, a ghost site at a face of the box)
                    function facecoef(oo)
                        Kn = one_ ? constant!(kb, 1.0) : _real(e, lower(q.K, _shift(e, oo)))
                        sum_ = _op(e, ADD, Kc, Kn)
                        face = q.mean === :arithmetic ? _op(e, MUL, constant!(kb, 0.5), sum_) :
                               select!(kb, _cmp(e, EQ, sum_, constant!(kb, 0.0)), constant!(kb, 0.0),
                                   _op(e, DIV, _op(e, MUL, constant!(kb, 2.0), Kc, Kn), sum_))
                        return _op(e, MUL, constant!(kb, 1 / e.h[a]^2), mult, face)
                    end
                    w = _op(e, ADD, w, facecoef(o))
                    wb = (_op(e, ADD, wb[1], facecoef(_unit(e, a, -1))), _op(e, ADD, wb[2], facecoef(o)))
                end
                # no face across the box (the solver's zero flux) or across the domain's edge
                s.periodic[a] || (w = select!(kb, inside(o), w, zero_))
                dlid == 0 || (w = select!(kb, node!(kb, AND, BOOL, Int32[indom(ntuple(_ -> 0, N)), indom(o)]), w, zero_))
                store!(kb, wids[a], lane, w)
                s.periodic[a] && continue
                # the face conditions of the box: the ghost rule's diagonal `w_b d⁺`
                for (j, side) in enumerate((-1, 1))
                    r = findfirst(x -> x isa FaceRule && x.field == fieldid(s, k) && x.axis == a && x.side == side, s.rules)
                    r === nothing && continue
                    fr = s.rules[r]
                    (fr.alpha.param == 0 && fr.alpha.value == 0) && continue
                    α, β = _facecoefs(e, kb, cf, k, a, side, fr)
                    dd = _op(e, DIV, α, _op(e, ADD, _op(e, MUL, constant!(kb, 0.5), α), β))
                    dd = _op(e, MAX, dd, zero_)
                    term = select!(kb, inside(_unit(e, a, side)), zero_, _op(e, MUL, wb[j], dd))
                    dsum = _op(e, ADD, dsum, term)
                end
            end
            store!(kb, did, lane, dsum)
            pl.scaled && store!(kb, mid, lane, _real(e, lower(p.m, e)))
        end
        if jid != 0
            jv = zero_
            for j in pl.jterms
                jv = _op(e, ADD, jv, _real(e, lower(j, e)))
            end
            store!(kb, jid, lane, jv)
        end
        dmid == 0 || store!(kb, dmid, U8, cast!(kb, indom(ntuple(_ -> 0, N)), U8))
        add!(pb, kb, "jac:$k")
    end
    return program(pb)
end
# The ghost diagonal `d = α/(α/2 + β)` of field `k`'s face (axis `a`, `side`) whose α or β
# varies by site or in time (F4-12b), bounded over `box` (the coordinates along the face, the
# time; the clock, a count from 0, over [0, ∞)): a function of the parameters giving `(lo, hi)`,
# `(NaN, NaN)` when no interval bounds it or `α/2 + β` may vanish (`|r| = |d − 1|` is the ghost
# ratio of the explicit bound). α and β of one sign at every site (not both 0) give `0 ≤ d ≤ 2`
# whatever their size (`1 + t` has no finite bound, and its face is still bounded)
function _site_diag(cf::CompiledField, k, a, side, params, tabs, box)
    s = cf.program
    r = findfirst(x -> x isa FaceRule && s.fields[x.field].key == k && x.axis == a && x.side == side, s.rules)
    fr = s.rules[r]
    sc = cf.sitecoefs[(k, a, side)]
    ck = unwrap(Symbolics.variable(:__clock_box))
    reps = Dict{Any, Any}(unwrap(q) => ck for q in cf.params if _isclock(q))
    ex(x) = Symbolics.wrap(isempty(reps) ? x : substitute(x, reps; fold = Val(false)))
    sym(c::Coef, x) = (c.param == 0 ? c.value : c.value * Symbolics.wrap(cf.params[c.param])) * (x === nothing ? 1 : ex(x))
    α, β = sym(fr.alpha, sc[1]), sym(fr.beta, sc[2])
    bx = Any[collect(box); (ck, (0.0, Inf), "")]
    ia, ib, id = (_interval(unwrap(y), params, tabs, bx) for y in (α, β, α / (α / 2 + β)))
    ev(f, pp) = f === nothing ? (NaN, NaN) : (q = f(pp); (Float64(q[1]), Float64(q[2])))
    return pp -> _diag_bounds(ev(ia, pp), ev(ib, pp), ev(id, pp))
end
function _diag_bounds(A, B, D)
    same = (A[1] >= 0 && B[1] >= 0 && (A[1] > 0 || B[1] > 0)) || (A[2] <= 0 && B[2] <= 0 && (A[2] < 0 || B[2] < 0))
    fin = all(isfinite, D)
    same && return fin ? (max(D[1], 0.0), min(D[2], 2.0)) : (0.0, 2.0)
    return fin ? D : (NaN, NaN)
end
# A face's Robin coefficients `(α, β)` as nodes of the `jac:` kernel: a number or a parameter
# from the face rule, a coefficient that varies by site or in time (F4-12b) lowered from its
# expression at the site (so an operator whose face reads the time is `timed`: rebuilt at each
# stage's end time, F4 ruling Q16)
function _facecoefs(e, kb, cf::CompiledField, k, a, side, fr)
    sc = get(cf.sitecoefs, (k, a, side), (nothing, nothing))
    node(c, x) = x === nothing ? _coefnode(kb, c) : _op(e, MUL, _coefnode(kb, c), _real(e, lower(x, e)))
    return node(fr.alpha, sc[1]), node(fr.beta, sc[2])
end
fieldid_in(pb::ProgramBuilder, key) = Int32(findfirst(f -> f.key == key, pb.fields))
_coefnode(kb, c::Coef) = c.param == 0 ? constant!(kb, c.value) :
                         arith!(kb, MUL, constant!(kb, c.value), cast!(kb, param!(kb, c.param), REAL))
