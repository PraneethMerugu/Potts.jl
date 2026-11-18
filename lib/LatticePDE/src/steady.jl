# Steady rows and time-free systems (F3-12b; F3 design §3.5). A steady equation `0 ~ rhs` is
# solved for the field it determines: a state field with no other equation that the row
# reads, preferably under a spatial operator (`laplacian`, `DivKGrad`, `Advect`, `Differential`). The
# pass rewrites each such row as the rate `D(c) ~ rhs` of its field, so the rest of the lowering
# is the rate form, and returns the steady field keys: their groups take `QuasiSteady` only
# (which solves `0 = rhs` each window, the meaning of `QuasiSteady` for a rate row too). A
# system with no time (its variables are the grid's axes only) is a steady system: every read
# gains the time, the time spans `(0, 0)`, and the problem is solved once (`steady_form`).

# a field slot (op, component; 0 for a scalar field) of every state dependent variable, in the
# order of `dvs`
function _state_slots(sys::PDESystem, isin)
    slots = Tuple{Any, Int}[]
    for v in sys.dvs
        op = _opof(v)
        isin[op] && continue
        st = SymbolicUtils.symtype(unwrap(v))
        st <: AbstractArray ? append!(slots, [(op, i) for i in 1:length(v)]) : push!(slots, (op, 0))
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
determines, and the keys of those fields (`"c"`, `"u[1]"`), in equation order. A row's field is
a state field with no other equation that the row reads, preferably under a spatial operator:
a row with one such field takes it, and the others follow (each field once); fields that two
rows could take in the same way go in the order of the dependent variables. A steady field
with no initial value starts at 0 (the steady solve's cold start). A row that reads no free
field is refused, naming the fields that have no equation.
"""
function steady_rows(sys::PDESystem)
    any(eq -> _iszero(eq.lhs), sys.eqs) || return sys, String[]
    ivs = unwrap.(sys.ivs)
    isin = Dict{Any, Bool}(_opof(v) => ModelingToolkitBase.isinput(v) for v in sys.dvs)
    slots = _state_slots(sys, isin)
    taken = [s for eq in sys.eqs if !_iszero(eq.lhs) for s in (_lhs_slot(eq, isin),) if s !== nothing]
    free = [s for s in slots if !_hasslot(taken, s)]
    rows = [i for (i, eq) in enumerate(sys.eqs) if _iszero(eq.lhs)]
    choice = map(rows) do i
        r = _slot_reads(sys.eqs[i].rhs, isin)
        (Int[k for (k, f) in enumerate(free) if _hasslot(r.ops, f)], Int[k for (k, f) in enumerate(free) if _hasslot(r.all, f)])
    end
    picks, bad = steady_choice(first.(choice), last.(choice), length(free))
    if bad != 0
        eq = sys.eqs[rows[bad]]
        left = [free[k] for k in eachindex(free) if !(k in picks)]
        _dverr(string("equation `", eq, "`: a steady equation `0 ~ rhs` is solved for a field that it reads and that ",
            "has no other equation, and it reads none", isempty(left) ? " (every field has an equation)" :
            string(" of the fields with no equation (", join(("`$(_slotkey(f))`" for f in left), ", "), ")"),
                "; write the field's operator into the row (`0 ~ D * laplacian(c) - k * c + s` for `c`)"
            )
        )
    end
    pick = Dict{Int, Tuple{Any, Int}}(q => free[picks[q]] for q in eachindex(rows))
    term(s) = (v = sys.dvs[findfirst(v -> isequal(_opof(v), s[1]), sys.dvs)]; s[2] == 0 ? v : Symbolics.wrap(v)[s[2]])
    Dt = Differential(sys.ivs[1])
    eqs = Equation[eq for eq in sys.eqs]
    for (q, i) in enumerate(rows)
        # (the sign that makes the row's operator, or its local term, a decay: r3 S3)
        tm = term(pick[q])
        eqs[i] = Dt(tm) ~ steady_sign(eqs[i].rhs, unwrap(tm)) * eqs[i].rhs
    end
    steady = String[_slotkey(pick[q]) for q in eachindex(rows)]
    # the cold start of a steady field with no initial value
    ic = _ics(sys)
    bcs = Equation[b for b in sys.bcs]
    t0 = leftendpoint(sys.domain[findfirst(d -> isequal(unwrap(d.variables), ivs[1]), sys.domain)].domain)
    for q in eachindex(rows)
        s = pick[q]
        has = any(sys.bcs) do b
            r = _fieldread(b.lhs, isin)
            r !== nothing && isequal(r.op, s[1]) && r.comp == s[2] && !isempty(r.args) && _cval(r.args[1]) !== nothing
        end
        v = sys.dvs[findfirst(v -> isequal(_opof(v), s[1]), sys.dvs)]
        given = has || s[2] == 0 && (_icvalue(ic, v) !== nothing || _icvalue(ic, s[1]) !== nothing)
        given && continue
        at0 = s[1](t0, ivs[2:end]...)
        push!(bcs, (s[2] == 0 ? Symbolics.wrap(at0) : Symbolics.wrap(at0)[s[2]]) ~ 0.0)
    end
    out = PDESystem(eqs, bcs, getfield(sys, :domain), sys.ivs, sys.dvs, _params(sys); name = nameof(sys),
        initial_conditions = ic)
    return out, steady
end

"""
    steady_choice(ops, reads, n) -> (picks, bad)

The field each steady row is solved for, the one rule of both front ends (F3-12b; r3 S4). The
`n` free fields (state fields with no other equation) are numbered in the order of the
dependent variables; `ops[q]` are the free fields row `q` reads under a spatial operator and
`reads[q]` every free field it reads. A row's candidates are its `ops`, else its `reads`; a row
with one live candidate takes it first, then the first row in turn takes its first live one
(each field once). `picks[q]` is the field of row `q`; `bad` is a row left with no candidate
(0: none), which the front end refuses in its words.
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
positive coefficient of `laplacian(c)`, of `K` in `DivKGrad(K, c)`) or, with no operator on `c`, its
local derivative `∂rhs/∂c` negative (a decay): `0 ~ k c − D laplacian(c) − s` and `0 ~ q − c²` (for `q`)
are the rows `0 ~ D laplacian(c) − k c + s` and `0 ~ c² − q` (r3 S3). The coefficients are judged at 1
for every parameter, coordinate and other field; a sign that this does not settle is left as
written (then the steady refusals judge the row at its values).
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
                                                     operation(unwrap(a[1])) isa Differential && isequal(unwrap(arguments(unwrap(a[1]))[1]), c))
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
    at(vz, vc) = try
        e = substitute(substitute(rhs, ops; fold = Val(false)), Dict{Any, Any}(c => vc, z => vz); fold = Val(false))
        num(substitute(e, Dict{Any, Any}(v => 1.0 for v in Symbolics.get_variables(e)); fold = Val(true)))
    catch
        nothing
    end
    hasop = any(v -> !(v isa Number), values(ops))            # (an operator on `c`: `z` or `z K`)
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
(no time) gains the time `t` over `(0, 0)` in every read (a time-free system, F3 design §3.5),
and its steady rows become rates (`steady_rows`). A time-free system has only steady
rows and aux fields (`K ~ rhs`).
"""
function steady_form(sys::PDESystem, N::Int)
    # (a system with a rate or a map has a time: its first variable, however many axes)
    timefree = length(sys.ivs) == N && !any(eq -> (l = unwrap(eq.lhs); iscall(l) && operation(l) isa Union{Differential, Shift}),
        sys.eqs)
    timefree && (sys = _timed(sys))
    sys, steady = steady_rows(sys)
    return sys, steady, timefree
end

const _STEADY_T = unwrap(ModelingToolkitBase.t_nounits)
const _STEADY_Z = unwrap(only(Symbolics.@variables __steady_z))
function _timed(sys::PDESystem)
    tt = _STEADY_T
    any(v -> isequal(unwrap(v), tt), sys.ivs) && _dverr("the system's variables $(Tuple(sys.ivs)) have no time but use " *
        "`$tt` as an axis; name the axes otherwise (a time-free system gains the time `$tt`)")
    ops = Any[_opof(v) for v in sys.dvs]
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
    for eq in [sys.eqs; sys.bcs]
        walk(eq.lhs)
        walk(eq.rhs)
    end
    foreach(walk, sys.dvs)
    # `substitute` does not enter a `Differential` (a Robin face's `∂c/∂y`): each derivative is
    # a rule of its own, inner ones first (review r4 N4: a time-free Robin face)
    for u in Iterators.reverse(ders)
        rule[u] = operation(u)(substitute(only(arguments(u)), rule; fold = Val(false)))
    end
    sub(x) = substitute(x, rule; fold = Val(false))
    ic = Dict{Any, Any}((haskey(rule, unwrap(k)) ? rule[unwrap(k)] : k) => v for (k, v) in _ics(sys))
    for eq in sys.eqs
        _iszero(eq.lhs) || _fieldread(eq.lhs, Dict{Any, Bool}(o => true for o in ops)) !== nothing ||
            _dverr(string("equation `", eq, "`: a system with no time has steady rows `0 ~ rhs` and aux fields `K ~ rhs` only"))
    end
    dom = [tt ∈ Interval(0.0, 0.0); getfield(sys, :domain)]
    return PDESystem([sub(eq.lhs) ~ sub(eq.rhs) for eq in sys.eqs], [sub(b.lhs) ~ sub(b.rhs) for b in sys.bcs], dom,
        Any[tt; unwrap.(sys.ivs)], Any[sub(v) for v in sys.dvs], _params(sys); name = nameof(sys), initial_conditions = ic)
end
