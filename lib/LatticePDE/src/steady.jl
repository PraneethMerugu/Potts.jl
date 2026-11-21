# Steady rows and time-free systems. A steady equation `0 ~ rhs` is
# solved for the field it determines: a state field with no other equation that the row
# reads, preferably under a spatial operator (`laplacian`, `DivKGrad`, `Advect`,
# `Differential`). The pass rewrites each such row as the rate `D(c) ~ rhs` of its field, so
# the rest of the lowering is the rate form, and returns the steady field keys: their groups
# take `QuasiSteady` only (which solves `0 = rhs` each window, the meaning of `QuasiSteady`
# for a rate row too). A system with no time (its variables are the grid's axes only) is a
# steady system: every read gains the time, the time spans `(0, 0)`, and the problem is
# solved once (`steady_form`).

# a field slot (op, component; 0 for a scalar field) of every state dependent variable, in
# the order of `dvs`
function _state_slots(sys::PDESystem, isin)
    slots = Tuple{Any, Int}[]
    for v in get_dvs(sys)
        op = _opof(v)
        isin[op] && continue
        st = SymbolicUtils.symtype(unwrap(v))
        if st <: AbstractArray
            append!(slots, [(op, i) for i in 1:length(v)])
        else
            push!(slots, (op, 0))
        end
    end
    return slots
end
_slotkey(s) = s[2] == 0 ? _name(s[1]) : string(_name(s[1]), "[", s[2], "]")
_hasslot(c, s) = any(x -> isequal(x[1], s[1]) && x[2] == s[2], c)

# the field slots `x` reads (`all`), and those it reads under a spatial operator (`ops`)
function _slot_reads(x, isin)
    all, ops = Tuple{Any, Int}[], Tuple{Any, Int}[]
    function walk(u, under)
        u = unwrap(u)
        iscall(u) || return nothing
        r = _fieldread(u, isin)
        if r !== nothing
            s = (r.op, r.comp)
            _hasslot(all, s) || push!(all, s)
            under && !_hasslot(ops, s) && push!(ops, s)
            return nothing
        end
        f, a = operation(u), arguments(u)
        if f === laplacian || f isa Differential
            foreach(y -> walk(y, true), a)
        elseif f isa DivKGrad || f isa Advect
            foreach(y -> walk(y, under), a[1:(end - 1)])
            walk(a[end], true)
        else
            foreach(y -> walk(y, under), a)
        end
        return nothing
    end
    walk(x, false)
    return (; all, ops)
end

# the slot of an equation's left side (a rate, a map or an aux field), or nothing
function _lhs_slot(eq, isin)
    l = unwrap(eq.lhs)
    a = iscall(l) && operation(l) isa Union{Differential, Shift} ? arguments(l)[1] : l
    r = _fieldread(a, isin)
    return r === nothing ? nothing : (r.op, r.comp)
end

"""
    steady_rows(sys) -> (sys, steady)

`sys` with every steady equation `0 ~ rhs` written as the rate `D(c) ~ rhs` of the field it
determines, and the keys of those fields (`"c"`, `"u[1]"`), in equation order. A row's field
is a state field with no other equation that the row reads, preferably under a spatial
operator: a row with one such field takes it, and the others follow (each field once);
fields that two rows could take in the same way go in the order of the dependent variables.
A steady field with no initial value starts at 0 (the steady solve's cold start). A row that
reads no free field is refused with an `ArgumentError`, naming the fields that have no
equation.

# Returns
- `(sys, steady)`: the rewritten system and the keys of the steady fields.
"""
function steady_rows(sys::PDESystem)
    any(eq -> _iszero(eq.lhs), get_eqs(sys)) || return sys, String[]
    ivs = unwrap.(get_ivs(sys))
    isin = Dict{Any, Bool}(_opof(v) => ModelingToolkitBase.isinput(v) for v in get_dvs(sys))
    slots = _state_slots(sys, isin)
    taken = [
        s for eq in get_eqs(sys) if !_iszero(eq.lhs)
            for s in (_lhs_slot(eq, isin),) if s !== nothing
    ]
    free = [s for s in slots if !_hasslot(taken, s)]
    rows = [i for (i, eq) in enumerate(get_eqs(sys)) if _iszero(eq.lhs)]
    choice = map(rows) do i
        r = _slot_reads(get_eqs(sys)[i].rhs, isin)
        (
            Int[k for (k, f) in enumerate(free) if _hasslot(r.ops, f)],
            Int[k for (k, f) in enumerate(free) if _hasslot(r.all, f)],
        )
    end
    picks, bad = steady_choice(first.(choice), last.(choice), length(free))
    if bad != 0
        eq = get_eqs(sys)[rows[bad]]
        left = [free[k] for k in eachindex(free) if !(k in picks)]
        unread = if isempty(left)
            " (every field has an equation)"
        else
            string(
                " of the fields with no equation (",
                join(("`$(_slotkey(f))`" for f in left), ", "), ")"
            )
        end
        _dverr(
            string(
                "equation `", eq,
                "`: a steady equation `0 ~ rhs` is solved for a field that it reads and \
                    that ",
                "has no other equation, and it reads none", unread,
                "; write the field's operator into the row (`0 ~ D * laplacian(c) - k * c \
                    + s` for `c`)"
            )
        )
    end
    pick = Dict{Int, Tuple{Any, Int}}(q => free[picks[q]] for q in eachindex(rows))
    function term(s)
        v = get_dvs(sys)[findfirst(v -> isequal(_opof(v), s[1]), get_dvs(sys))]
        return s[2] == 0 ? v : Symbolics.wrap(v)[s[2]]
    end
    Dt = Differential(get_ivs(sys)[1])
    eqs = Equation[eq for eq in get_eqs(sys)]
    for (q, i) in enumerate(rows)
        # (the sign that makes the row's operator, or its local term, a decay)
        tm = term(pick[q])
        eqs[i] = Dt(tm) ~ steady_sign(eqs[i].rhs, unwrap(tm)) * eqs[i].rhs
    end
    steady = String[_slotkey(pick[q]) for q in eachindex(rows)]
    # the cold start of a steady field with no initial value
    ic = _ics(sys)
    bcs = Equation[b for b in get_bcs(sys)]
    t0 = leftendpoint(
        get_domain(sys)[
            findfirst(d -> isequal(unwrap(d.variables), ivs[1]), get_domain(sys)),
        ].domain
    )
    for q in eachindex(rows)
        s = pick[q]
        has = any(get_bcs(sys)) do b
            r = _fieldread(b.lhs, isin)
            r !== nothing && isequal(r.op, s[1]) && r.comp == s[2] && !isempty(r.args) &&
                _cval(r.args[1]) !== nothing
        end
        v = get_dvs(sys)[findfirst(v -> isequal(_opof(v), s[1]), get_dvs(sys))]
        given = has ||
            s[2] == 0 && (_icvalue(ic, v) !== nothing || _icvalue(ic, s[1]) !== nothing)
        given && continue
        at0 = s[1](t0, ivs[2:end]...)
        push!(bcs, (s[2] == 0 ? Symbolics.wrap(at0) : Symbolics.wrap(at0)[s[2]]) ~ 0.0)
    end
    out = PDESystem(
        eqs, bcs, get_domain(sys), get_ivs(sys), get_dvs(sys), _params(sys);
        name = nameof(sys),
        initial_conditions = ic
    )
    return out, steady
end

"""
    steady_choice(ops, reads, n) -> (picks, bad)

The field each steady row is solved for, used across `discretize` and PDE groups. The
`n` free fields (state fields with no other equation) are numbered in the order of the
dependent variables; `ops[q]` are the free fields row `q` reads under a spatial operator and
`reads[q]` every free field it reads. A row's candidates are its `ops`, else its `reads`; a
row with one live candidate takes it first, then the first row in turn takes its first live
one (each field once).

# Arguments
- `ops::AbstractVector`: `ops[q]` are the free fields row `q` reads under a spatial
  operator.
- `reads::AbstractVector`: `reads[q]` is every free field row `q` reads.
- `n::Integer`: the number of free fields.

# Returns
- `(picks, bad)`: `picks[q]` is the field of row `q`; `bad` is a row left with no
  candidate (0: none), which the front end refuses in its words.

# Examples
```jldoctest
julia> using LatticePDE

julia> LatticePDE.steady_choice([[2], Int[]], [[1, 2], [1, 2]], 2)
([2, 1], 0)
```
"""
function steady_choice(ops::AbstractVector, reads::AbstractVector, n::Integer)
    cand = [sort!(unique(isempty(o) ? r : o)) for (o, r) in zip(ops, reads)]
    left = trues(n)
    picks = zeros(Int, length(cand))
    pending = collect(eachindex(cand))
    while !isempty(pending)
        live(q) = [k for k in cand[q] if left[k]]
        z = findfirst(q -> isempty(live(q)), pending)
        z === nothing || return picks, pending[z]
        j = something(findfirst(q -> length(live(q)) == 1, pending), 1)
        q = pending[j]
        picks[q] = first(live(q))
        left[picks[q]] = false
        deleteat!(pending, j)
    end
    return picks, 0
end

"""
    steady_sign(rhs, c) -> ±1

The sign that writes the steady row `0 ~ rhs` of field `c` with its operator a diffusion (a
positive coefficient of `laplacian(c)`, of `K` in `DivKGrad(K, c)`) or, with no operator on
`c`, its local derivative `∂rhs/∂c` negative (a decay): `0 ~ k c − D laplacian(c) − s` and
`0 ~ q − c²` (for `q`) are the rows `0 ~ D laplacian(c) − k c + s` and `0 ~ c² − q`. The
coefficients are judged at 1 for every parameter, coordinate and other field; a sign that
this does not settle is left as written (then the steady refusals judge the row at its
values).

# Returns
- `1` or `-1`.
"""
function steady_sign(rhs, c)
    z = _STEADY_Z
    ops, rule = Dict{Any, Any}(), Dict{Any, Any}()
    function walk(u)
        u = unwrap(u)
        iscall(u) || return nothing
        f, a = operation(u), arguments(u)
        if (f === laplacian && isequal(unwrap(a[1]), c)) || (
                f isa Differential && iscall(unwrap(a[1])) &&
                    operation(unwrap(a[1])) isa Differential &&
                    isequal(unwrap(arguments(unwrap(a[1]))[1]), c)
            )
            ops[u] = z
            return nothing
        elseif (f isa DivKGrad) && isequal(unwrap(a[end]), c)
            ops[u] = z * a[1]
            return nothing
        elseif f === laplacian || f isa DivKGrad || f isa Advect || f isa Differential
            ops[u] = 0
            return nothing
        end
        foreach(walk, a)
        return nothing
    end
    walk(rhs)
    num(x) = (v = _numval(unwrap(x)); v isa Real && isfinite(v) ? Float64(v) : nothing)
    # Symbolic probes (substituted expressions can raise DomainError, MethodError,
    # InexactError, etc.) fall back to the conservative steady sign rather than failing
    # analysis.
    function at(vz, vc)
        return try
            e = substitute(
                substitute(rhs, ops; fold = Val(false)),
                Dict{Any, Any}(c => vc, z => vz); fold = Val(false)
            )
            num(
                substitute(
                    e, Dict{Any, Any}(v => 1.0 for v in Symbolics.get_variables(e));
                    fold = Val(true)
                )
            )
        catch e
            isfatal(e) && rethrow()
            nothing
        end
    end
    # (an operator on `c`: `z` or `z K`)
    hasop = any(v -> !(v isa Number), values(ops))
    if hasop
        a, b = at(1.0, 1.0), at(0.0, 1.0)
        (a === nothing || b === nothing) && return 1
        return a - b < 0 ? -1 : 1
    end
    a, b = at(0.0, 1.5), at(0.0, 1.0)
    (a === nothing || b === nothing) && return 1
    return a - b > 0 ? -1 : 1
end

"""
    steady_form(sys, N) -> (sys, steady, timefree)

The lowering's form of `sys` on an `N`-axis grid: a system whose variables are the axes only
(no time) gains the time `t` over `(0, 0)` in every read (a time-free system),
and its steady rows become rates (`steady_rows`). A time-free system has only steady
rows and aux fields (`K ~ rhs`).

# Returns
- `(sys, steady, timefree)`: the rewritten system, the keys of its steady fields, and
  whether it has no time.
"""
function steady_form(sys::PDESystem, N::Int)
    # (a system with a rate or a map has a time: its first variable, however many axes)
    timefree = length(get_ivs(sys)) == N && !any(
        eq -> (
            l = unwrap(eq.lhs); iscall(l) && operation(l) isa Union{Differential, Shift}
        ),
        get_eqs(sys)
    )
    timefree && (sys = _timed(sys))
    sys, steady = steady_rows(sys)
    return sys, steady, timefree
end

const _STEADY_T = unwrap(ModelingToolkitBase.t_nounits)
const _STEADY_Z = unwrap(only(Symbolics.@variables __steady_z))
function _timed(sys::PDESystem)
    tt = _STEADY_T
    any(v -> isequal(unwrap(v), tt), get_ivs(sys)) && _dverr(
        "the system's variables $(Tuple(get_ivs(sys))) have no time but use " *
            "`$tt` as an axis; name the axes otherwise (a time-free system gains the time \
                `$tt`)"
    )
    ops = Any[_opof(v) for v in get_dvs(sys)]
    rule = Dict{Any, Any}()
    ders = Any[]
    function walk(u)
        u = unwrap(u)
        iscall(u) || return nothing
        f = operation(u)
        any(o -> isequal(o, f), ops) && (rule[u] = f(tt, arguments(u)...))
        f isa Differential && push!(ders, u)
        foreach(walk, arguments(u))
        return nothing
    end
    for eq in [get_eqs(sys); get_bcs(sys)]
        walk(eq.lhs)
        walk(eq.rhs)
    end
    foreach(walk, get_dvs(sys))
    # `substitute` does not enter a `Differential` (a Robin face's `∂c/∂y`): each derivative
    # is a rule of its own, inner ones first (a time-free Robin face)
    for u in Iterators.reverse(ders)
        rule[u] = operation(u)(substitute(only(arguments(u)), rule; fold = Val(false)))
    end
    sub(x) = substitute(x, rule; fold = Val(false))
    ic = Dict{Any, Any}(
        (haskey(rule, unwrap(k)) ? rule[unwrap(k)] : k) => v
            for (k, v) in _ics(sys)
    )
    for eq in get_eqs(sys)
        _iszero(eq.lhs) ||
            _fieldread(eq.lhs, Dict{Any, Bool}(o => true for o in ops)) !== nothing ||
            _dverr(
            string(
                "equation `",
                eq,
                "`: a system with no time has steady rows `0 ~ rhs` and aux fields `K ~ \
                    rhs` only"
            )
        )
    end
    dom = [tt ∈ Interval(0.0, 0.0); get_domain(sys)]
    return PDESystem(
        [sub(eq.lhs) ~ sub(eq.rhs) for eq in get_eqs(sys)], [
            sub(b.lhs) ~ sub(b.rhs)
                for b in get_bcs(sys)
        ], dom,
        Any[tt; unwrap.(get_ivs(sys))], Any[sub(v) for v in get_dvs(sys)], _params(sys);
        name = nameof(sys), initial_conditions = ic
    )
end
