# The discretizer: `PDESystem` + `LatticeDiscretization` → a LatticeFields
# `Program`. PDEBase is not used (its bc parsing and its symbolic discretizer
# interface do not fit a lattice IR); the analysis here is ours: operation-normalized keys,
# the BC parser, the linearity table, map and offset-read classification, and the lowering.

"""`FiniteVolume()`: the cell-centered finite-volume method (face-flux form, §5.2)."""
struct FiniteVolume end

"""
    LatticeDiscretization(grid; methods = Dict(), T = nothing, backend = nothing, domain = nothing, clock = nothing)

How a `PDESystem` is put on a lattice. `grid = Grid(dims)` gives only the site counts: the
spacing is derived from the system's domain (`extent ./ dims`) and periodicity from its
periodic bc pairs, so there is one source of truth. `methods` maps a field (`c`, `c(t, x, y)`
or `u`; keys are normalized by operation) to its method; a field without an entry is
`FiniteVolume()`.

`T` is the state type (P5 role model: the only number-type keyword): `Float16`, `Float32`,
`Float64`, or `BigFloat` on the host (stored in F64 lanes that hold BigFloat). `nothing` (the
default) means Float64 on the host and Float32 on a device. Any other type is refused. After
`discretize`, the eltype of `u0` (and Dual parameters) decide; see `remake`.

A hexagonal grid (`Grid(dims; geometry = HEX)`, 2D, axial coordinates: the neighbors of
`(q, r)` are `(q ± 1, r)`, `(q, r ± 1)`, `(q + 1, r − 1)` and `(q − 1, r + 1)`) lowers `laplacian(c)` to
`2/(3h²) Σₙ (cₙ − c)` over the six neighbors (`h` the spacing of axis 1; the axes must have
equal spacing). A neighbor outside the domain reads the site itself (zero flux); a neighbor
outside the box reads the ghost of the face condition its link leaves through (a diagonal link
`±(e₁ − e₂)` takes axis 1's face when it leaves along axis 1, else axis 2's), with the
condition applied along the link in lattice units. Only `laplacian` is defined there.

`domain` names a `Bool` input field (the variable `dom`, or its key `"dom"` or `:dom`) that marks an
irregular domain inside the box; give its values like any input (`discretize(…; inputs)`).
The fields live in the domain: a site outside keeps its value (its rate is 0, its masked
conditions do not hold), and neighbor reads across the domain's edge read the site itself
(zero flux; `LatticeFields.IR.DomainEdgeRule`). Face conditions still apply at the faces of
the box.

A field with `[lattice_level = Coarse(k)]` ([`Coarse`](@ref)) lives on the grid coarsened by
`k`: the program holds one level per factor, and the field's kernels (rate, conditions, masks,
operator and residual) run on its level with the spacing `k h`. Its fine reads are folded over
each node's block, and a fine field reads a coarse one at the node of its block; with a
`domain`, a node is in it when most of its block is. Every algorithm, the stability bound and
the number types apply per field, on its own grid.

`clock = τ` declares the discretization's clock, of period `τ` (finite,
> 0). It sets the window of the owned steppers (`ExplicitEuler()` with no `dt` steps windows
of `τ`; a given `dt` must divide `τ`) and the step index `k` that an equation reads as
[`step_index(t)`](@ref): `k = 0` over the first period from the start of the time span,
then `1`, `2`, …, kept as an integer by the stepper (never computed from a float time).
Without a clock, `ExplicitEuler` needs `dt`, and `step_index` is refused.
"""
struct LatticeDiscretization{N, M, B} <: AbstractDiscretization
    grid::Grid{N}
    methods::M
    T::Union{Type, Nothing}
    backend::B
    domain::Union{Nothing, String}
    clock::Union{Nothing, Float64}
end
function LatticeDiscretization(grid::Grid; methods = Dict(), T::Union{Type, Nothing} = nothing,
                               backend = nothing, domain = nothing, clock = nothing, kw...)
    isempty(kw) || throw(ArgumentError(string("`LatticeDiscretization` takes `methods`, `T`, `backend`, `domain` and ",
        "`clock`; got ", join(("`$k`" for k in keys(kw)), ", "), ". The problem is chosen by the algorithm: ",
        "`discretize` returns one SciML problem, which `solve` takes with a field algorithm or an OrdinaryDiffEq solver")))
    clock === nothing || (clock isa Real && isfinite(clock) && clock > 0) ||
        throw(ArgumentError("clock = $(repr(clock)) must be a finite period > 0 (or left out: no clock)"))
    grid.domain == 0 || throw(ArgumentError("give an irregular domain as `domain = dom` (a Bool input field), not in the grid"))
    grid.geometry == HEX && length(grid.dims) != 2 && throw(ArgumentError("a hexagonal grid is 2D"))
    key = if domain === nothing
        nothing
    elseif domain isa Union{AbstractString, Symbol}
        String(domain)
    else
        _name(_opof(domain))
    end
    return LatticeDiscretization(grid, methods, T, backend, key, clock === nothing ? nothing : Float64(clock))
end

"""
    lattice_domain(t, (x, y), dims; spacing = 1, tspan = (0.0, 1.0))
    lattice_domain((x, y), dims; spacing = 1)

The domain of a `PDESystem` on a lattice of `dims` sites: `[t ∈ Interval(tspan...), x ∈
Interval(0, dims[1] * spacing), y ∈ Interval(0, dims[2] * spacing)]`. Give it as the
`PDESystem`'s domain, so you do not compute the extents yourself:

```julia
dom = lattice_domain(t, (x, y), (64, 48); spacing = 0.5)   # x ∈ [0, 32], y ∈ [0, 24]
@named sys = PDESystem(eqs, bcs, dom, [t, x, y], [c(t, x, y)], [D])
discretize(sys, LatticeDiscretization(Grid((64, 48))))
```

`spacing` is one number for every axis or one per axis (each finite and > 0). The
discretization derives the spacing back from the domain (`extent / dims`). A model's
lattice uses the same rule: axis `d` spans `[0, dims[d] * spacing[d]]`. `tspan` is the time
interval, which is the default time span of `discretize`. The form without `t` is the domain
of a system with no time (a steady system).
"""
lattice_domain(t, xs, dims; spacing = 1, tspan = (0.0, 1.0)) =
    [_time_interval(t, tspan); lattice_domain(xs, dims; spacing)]
function lattice_domain(xs, dims; spacing = 1)
    xs isa Union{Tuple, AbstractVector} || throw(ArgumentError(string("lattice_domain: give the coordinates as a ",
        "tuple, `(x, y)`; got ", repr(xs))))
    N = length(xs)
    dims isa Union{Tuple, AbstractVector} && length(dims) == N && all(d -> d isa Integer && !(d isa Bool) && d > 0, dims) ||
        throw(ArgumentError(string("lattice_domain: `dims` is the site count of each of the ", N, " axes ",
            "(positive integers, as `Grid(dims)` takes them); got ", repr(dims))))
    h = spacing isa Real ? ntuple(_ -> spacing, N) : spacing
    h isa Union{Tuple, AbstractVector} && length(h) == N && all(s -> s isa Real && isfinite(s) && s > 0, h) ||
        throw(ArgumentError(string("lattice_domain: `spacing` is one number or one per axis (", N, "), each finite ",
            "and > 0; got ", repr(spacing))))
    return [xs[d] ∈ Interval(0.0, dims[d] * Float64(h[d])) for d in 1:N]
end
function _time_interval(t, tspan)
    tspan isa Union{Tuple, AbstractVector} && length(tspan) == 2 && all(v -> v isa Real && isfinite(v), tspan) &&
        tspan[1] < tspan[2] || throw(ArgumentError(string("lattice_domain: `tspan` is the time interval `(t₀, t₁)`, ",
        "two finite numbers with t₀ < t₁; got ", repr(tspan))))
    return t ∈ Interval(_float_span(tspan[1], tspan[2])...)
end

"""
The lowered field system. `program` is the LatticeFields `Program` (before the semantic
passes); `keys[op]` are the field keys of each dependent variable (one per component);
`params[i]` is the parameter of slot `i` with its value `defaults[i]` (`lattice_spacing`
parameters take the grid spacing; `NaN` when there is no default); `tables` the array
parameters with their values; `initial` the initial-condition right sides by field key;
`linearity` the class of every rate term by field key. The defaults and the table values keep
the number type they are declared in (a `big"1"/3` default stays BigFloat; the vector is the
promotion of Float64 with every value's type), as a problem's parameters do.
"""
struct CompiledField{N}
    program::Program{N}
    keys::Dict{Any, Vector{String}}
    params::Vector{Any}
    defaults::Vector
    tables::Vector
    initial::Dict{String, Any}
    linearity::Dict{String, Vector{Pair{Any, Symbol}}}
    # the Robin coefficients that vary by site or in time, by `(key, axis, side)`:
    # `(α, β)` in lattice units at the face's own coordinate, each an expression or `nothing`
    # (a number or a parameter, held by the face rule)
    sitecoefs::Dict{Tuple{String, Int, Int}, Tuple{Any, Any}}
    # the coarse fields that blend: by key, the mask predicate, which reads fine fields
    free::Dict{String, Any}
    # the irregular domain's Bool input when it is finer than a blending row's grid: the row's
    # fold intersects the free support with the in-domain children
    domfree::Any
end

"""Launch-varying slot of the time `t` (`G.rt[RUNTIME_T]`)."""
const RUNTIME_T = 1

_dverr(msg) = throw(ArgumentError(_clocktext(msg)))
# the clock's slot as the user wrote it (`step_index(t)`), in every message of a lowered system;
# a velocity vector as written (`[ux, 0.0]`, not its symbolic literal) and `Advect(Upwind1())`
_clocktext(s::AbstractString) = as_written(replace(s, r"\bclock__tick\b" => "step_index(t)"))
"""
    as_written(text) -> String

A lowered term's text as the user wrote it: a velocity vector `[ux, uy]` (not its symbolic
array literal), `Advect(Upwind1())` (not `LatticePDE.Advect{LatticePDE.Upwind1}(…)`) and `laplacian(K)`
(not `LatticePDE.laplacian(K)`). For a
front end that prints lowered terms in its messages (Potts); LatticePDE's own messages print
through it too.
"""
function as_written(s::AbstractString)
    s = replace(s, r"(?:LatticePDE\.)?Advect\{[\w.]+\}\(" => "Advect(", r"LatticePDE\.Upwind1\(" => "Upwind1(")
    s = replace(s, r"LatticePDE\.(laplacian|value_at|DivKGrad)\(" => s"\1(")      # (`laplacian(K)`, not `LatticePDE.laplacian(K)`)
    s = replace(s, r"var\"([^\"]+\))(?:#\d+)?\"\(t(, \w+)*\)" => s"\1")   # an aux field added for an operator across grids: `laplacian(c)`, and `DivKGrad(c)#2` as `DivKGrad(c)`
    key = "SymbolicUtils.array_literal("
    while (r = findfirst(key, s)) !== nothing
        j = last(r)                                   # its `(`
        depth, k = 1, j
        while depth > 0 && k < lastindex(s)
            k = nextind(s, k)
            s[k] == '(' ? (depth += 1) : s[k] == ')' && (depth -= 1)
        end
        inner = replace(s[nextind(s, j):prevind(s, k)], r"^\(\d+(, \d+)*,?\), " => "")   # the shape first
        s = string(s[1:prevind(s, first(r))], "[", inner, "]", s[nextind(s, k):end])
    end
    return s
end
_name(op) = string(nameof(op))
_opof(x) = (u = unwrap(x); if iscall(u)
    operation(u) === getindex ? _opof(arguments(u)[1]) : operation(u)
else
    u
end)
function _lane(st, T)
    st <: Bool && return U8
    st <: Integer && return st <: Unsigned ? U32 : I32
    T === Float64 && return F64
    T === Float32 && return F32
    T === Float16 && return F16
    T === BigFloat && return F64          # host only: an F64 lane holds BigFloat (`lanetype`)
    _dverr("T = $T is not a state type: use Float16, Float32, Float64 or BigFloat (host)")
end
# the state type: `disc.T`, else Float64 on a host backend and Float32 on a device
function _statetype(disc::LatticeDiscretization)
    disc.T === nothing || return disc.T
    return disc.backend === nothing ? Float64 : Exec.default_float(disc.backend)
end
# The parts of a `PDESystem` beyond its six lowered fields: `ps = NullParameters()`
# (MTKBase's default) is no parameters; `initial_conditions` give parameter values (over the
# variable defaults) and field initial values (where no `c(0, …) ~ v` condition gives one);
# subsystems and analytic solutions are refused by name, never ignored
_params(sys::PDESystem) = get_ps(sys) isa NullParameters ? Any[] : collect(get_ps(sys))
_ics(sys::PDESystem) = get_initial_conditions(sys)
function _check_parts(sys::PDESystem)
    sy = get_systems(sys)
    isempty(sy) || _dverr("`$(nameof(sys))` has subsystems ($(join(("`$(nameof(x))`" for x in sy), ", "))); " *
                          "`discretize` lowers one flat PDESystem: write their equations into it")
    # (`analytic`, `analytic_func`: read as properties, which `PDESystem`'s `getproperty` gives;
    # switch to `get_analytic` once a ModelingToolkitBase release has it, SciML/ModelingToolkit.jl#5420)
    (sys.analytic === nothing && sys.analytic_func === nothing) ||
        _dverr("`$(nameof(sys))` has analytic solutions, which `discretize` does not use in this version " *
               "(no solution carries them); compare against them yourself and leave `analytic` out")
    # every `initial_conditions` key is a parameter or a dependent variable (a typo is not ignored)
    known = Any[unwrap.(_params(sys)); unwrap.(get_dvs(sys)); [_opof(v) for v in get_dvs(sys)]]
    for k in keys(_ics(sys))
        any(q -> isequal(q, unwrap(k)), known) && continue
        _dverr("`initial_conditions` gives `$k` a value, but `$k` is neither a parameter nor a dependent variable " *
               "of `$(nameof(sys))`")
    end
    return nothing
end
# the value given for `x` in the system's `initial_conditions`, else `nothing`
_icvalue(ic, x) = (u = unwrap(x); haskey(ic, u) ? ic[u] : nothing)

# a parameter's numeric value, in the type it is given in (a BigFloat default stays BigFloat):
# its `initial_conditions` entry, else its default, else NaN (none, or a computed value such as
# `2a`, which `discretize` folds into the equations)
function _default(p, ic = Dict())
    d = _icvalue(ic, p)
    d === nothing && !ModelingToolkitBase.hasdefault(p) && return NaN
    v = unwrap_const(unwrap(d === nothing ? ModelingToolkitBase.getdefault(p) : d))
    if v isa Real && !(v isa Bool)
        return v
    elseif v isa Bool
        return Float64(v)
    else
        return NaN
    end
end
# values as one vector: the promotion of Float64 with each value's type (an integer is a Float64)
_promoted(vs) = (T = mapreduce(typeof, promote_type, vs; init = Float64); T.(vs))

# a face coefficient, face value or mask value: a number, a parameter, or a number times a
# parameter, else `nothing` (a value field, and a Robin coefficient that reads the
# coordinates or the time, one of parameters is a computed parameter by then, `robin_slots`)
function _coef(v, params, scale = 1.0)
    u = unwrap(v)
    c = _cval(u)
    c !== nothing && return Coef(Float64(c) * scale + 0.0)          # no -0.0 in the printed rule
    haskey(params, u) && return Coef(scale, Int32(params[u]))
    if iscall(u) && operation(u) === (*)
        a = arguments(u)
        k = findfirst(y -> haskey(params, unwrap(y)), a)
        rest = k === nothing ? nothing : _cval(prod(a[setdiff(eachindex(a), [k])]))
        k !== nothing && rest !== nothing && return Coef(Float64(rest) * scale, Int32(params[unwrap(a[k])]))
    end
    return nothing
end
# A face value or a masked value that is an expression: of the time, the coordinates,
# the parameters and the inputs, never of a field of the state (the condition would be another
# equation). It is lowered into a value field the kernels read (`FaceRule.gfield`,
# `NodeValueRule.vfield`).
function _unpin_face_reads(bc, fids, ivs)
    reps = Dict{Any, Any}()
    function walk(y)
        iscall(y) || return
        if haskey(fids, operation(y))
            reps[y] = unwrap(operation(y)(ivs...))
        else
            foreach(a -> walk(unwrap(a)), arguments(y))
        end
        return
    end
    walk(unwrap(bc.value))
    isempty(reps) && return bc
    return BC(bc.kind, bc.op, bc.comp, bc.axis, bc.side, bc.alpha, bc.beta,
        substitute(bc.value, reps; fold = Val(false)), bc.pred, bc.eq)
end
# A Robin coefficient `v` of condition `bc` (`what`: "α" or "β", times `scale` into lattice
# units) that reads the coordinates or the time: a value field `face:<key>:<axis><side>:<what>`
# computed at each site by a kernel at the step's time, at the face's own coordinate (the
# boundary sites read it). A read of an input is read at the boundary site; a read of the
# state is refused (the condition would be another equation)
function _coef_field!(pb, bc, v, scale, what, k, d, s, op, lv, fids, ivs, ends, allops, isin, kern::K, env::E) where {K, E}
    _value_reads_state(v, bc.eq, [o for o in allops if !isin[o]], "Robin coefficient")
    w = _unpin_face_reads(BC(bc.kind, bc.op, bc.comp, bc.axis, bc.side, bc.alpha, bc.beta, v, bc.pred, bc.eq), fids, ivs).value
    fk = string("face:", k, ":", d, s > 0 ? "+" : "-", ":", what)
    lane = fids[op][2]
    ff = field!(pb, fk; storage = lane, role = :aux, levels = Int8[lv])
    kb = kern(lv)
    e = env(false, kb, lv)
    wx = substitute(w, Dict(ivs[d + 1] => ends[d + 1][s > 0 ? 2 : 1]); fold = Val(false))
    x = unwrap(scale * wx)
    store!(kb, ff, lane, _real(e, lower(x, e)))
    add!(pb, kb, fk)
    return ff, x
end
# The time derivative of a masked value `v`: the inputs and the step index are
# piecewise constant in time (rate 0 between writes), the coordinates and parameters constant;
# `nothing` when it is 0 or has no symbolic derivative (then the value is held between steps
# and the mask callback writes it)
function _time_rate(v, tt, isinput)
    reps, back = Dict{Any, Any}(), Dict{Any, Any}()
    function walk(y)
        iscall(y) || return
        o = operation(y)
        if isinput(o) || o === step_index
            haskey(reps, y) && return
            z = unwrap(Symbolics.variable(Symbol("__lattice_hold_", length(reps) + 1)))
            reps[y] = z
            back[z] = y
        else
            foreach(a -> walk(unwrap(a)), arguments(y))
        end
    end
    walk(unwrap(v))
    w = isempty(reps) ? v : substitute(v, reps; fold = Val(false))
    d = try
        Symbolics.expand_derivatives(Differential(tt)(w))
    catch err
        err isa ArgumentError || rethrow()
        return nothing
    end
    u = unwrap(d)
    z = unwrap_const(u)
    z isa Number && return iszero(z) ? nothing : d
    _has_differential(u) && return nothing
    return isempty(back) ? d : substitute(d, back; fold = Val(false))
end
_has_differential(u) = iscall(u) && (operation(u) isa Differential || any(a -> _has_differential(unwrap(a)), arguments(u)))
function _value_reads_state(v, eq, states, what)
    _reads(v, states) && _dverr(string("`", eq, "`: the ", what, " `", v, "` reads a field of the state; a ", what,
        " may read the time, the coordinates, the parameters and the inputs (a condition that reads the field ",
        "itself is a Robin condition `α c + β ∂c/∂n = g`, with α and β expressions of the time, the coordinates and the parameters)"))
    return nothing
end

# whether the site is in the irregular domain (its Bool input, field id `dom`)
_indomain(kb, dom, N, o = ntuple(_ -> 0, N)) = node!(kb, NOT, BOOL, Int32[compare!(kb, EQ,
    cast!(kb, load!(kb, dom, U8; offset = o, policy = all(iszero, o) ? INSIDE : CLAMP), I32), constant!(kb, 0, I32))])

"""Kind of an equation: (:rate | :map | :aux, field read on the left at `(t, x, …)`)."""
function _eqkind(eq, fields, ivs)
    l = unwrap(eq.lhs)
    bad(form) = _dverr("equation `$eq`: the left side must be $form")
    plain(u) = (r = _fieldread(u, fields); r !== nothing && length(r.args) == length(ivs) &&
                                            all(isequal.(r.args, ivs)))
    if iscall(l) && operation(l) isa Differential
        f = operation(l)
        (f.order == 1 && isequal(f.x, ivs[1]) && plain(arguments(l)[1])) || bad("`D(c($(join(ivs, ", "))))`, a time rate")
        return :rate, arguments(l)[1]
    elseif iscall(l) && operation(l) isa Shift
        s = operation(l)
        s.steps == 1 && isequal(s.t, ivs[1]) ||
            _dverr("equation `$eq`: only one-step maps `Shift(t, 1)(c) ~ rhs` in time are supported; $SHIFT_HINT")
        plain(arguments(l)[1]) || bad("`Shift(t, 1)(c($(join(ivs, ", "))))`")
        return :map, arguments(l)[1]
    elseif iscall(l) && (operation(l) isa Hold || operation(l) isa Sample)
        _dverr("equation `$eq`: `$(operation(l))` is a clock operator with no lattice meaning; $SHIFT_HINT")
    elseif _fieldread(l, fields) !== nothing
        plain(l) || bad("a field read `c($(join(ivs, ", ")))`")
        return :aux, l
    end
    _dverr("equation `$eq`: the left side must be `D(c)`, `Shift(t, 1)(c)`, a field `c` or `0` (a steady row)")
end

# The clock's step index: every `step_index(t)` of the equations and
# conditions becomes the reserved parameter slot `clock__tick` (appended to the parameters),
# which the steppers write at every launch; refused without a declared clock, with an argument
# other than the time, or when the system already has a parameter of that name
const _CLOCK_TICK = unwrap(only(ModelingToolkitBase.@parameters clock__tick = 0.0))
_isclock(p) = string(unwrap(p)) == Problems.CLOCK_KEY
function _clock_slot(sys::PDESystem, disc::LatticeDiscretization)
    ps = _params(sys)
    any(_isclock, ps) && throw(ArgumentError("`$(Problems.CLOCK_KEY)` is the reserved name of the clock's slot (the " *
                                             "`__tick` suffix is reserved); give the parameter another name"))
    tt = unwrap(get_ivs(sys)[1])
    calls = Any[]
    walk(u) = iscall(u) && (operation(u) === step_index ? push!(calls, u) : foreach(walk, arguments(u)))
    foreach(eq -> (walk(unwrap(eq.lhs)); walk(unwrap(eq.rhs))), [get_eqs(sys); get_bcs(sys)])
    isempty(calls) && return sys
    for u in calls
        isequal(unwrap(only(arguments(u))), tt) ||
            _dverr("`$u`: the argument of `step_index` is the time `$tt` (the clock's step index at the current time)")
    end
    disc.clock === nothing && _dverr("`step_index($tt)` reads the discretization's clock, and the `LatticeDiscretization` " *
                                     "declares none; give `LatticeDiscretization(…; clock = τ)` (the period of one step index)")
    rule = Dict{Any, Any}(u => _CLOCK_TICK for u in unique(calls))
    sub(x) = substitute(x, rule; fold = Val(false))
    return PDESystem(
        [sub(eq.lhs) ~ sub(eq.rhs) for eq in get_eqs(sys)], [sub(b.lhs) ~ sub(b.rhs) for b in get_bcs(sys)],
        get_domain(sys), get_ivs(sys), get_dvs(sys), Any[ps; _CLOCK_TICK]; name = nameof(sys),
        initial_conditions = _ics(sys))
end

function _scan_clock(sys)
    walk(u, eq) = iscall(u) && ((operation(u) isa Hold || operation(u) isa Sample ||
                                 (operation(u) isa Shift && operation(u).steps != 1)) &&
                                _dverr("`$eq`: `$(operation(u))` is not supported; only `Shift(t, 1)` maps are; $SHIFT_HINT");
                                foreach(a -> walk(a, eq), arguments(u)))
    return foreach(eq -> (walk(unwrap(eq.lhs), eq); walk(unwrap(eq.rhs), eq)), [get_eqs(sys); get_bcs(sys)])
end

# The `Coarse` level of each dependent variable: `[lattice_level = Coarse(k)]` puts the
# field on the grid coarsened by `k`; every axis of the lattice but one of size 1 must have a
# size that `k` divides (a remainder would make the last block wider, where the stencil of
# spacing `k h` is inconsistent: refused, naming the axis and the route). `lattice_placement`
# is not lowered yet and is refused, never ignored. Returns `op => level` for the coarse ones.
function _field_levels(sys::PDESystem, disc::LatticeDiscretization{N}) where {N}
    lev = Dict{Any, Int}()
    ivs = unwrap.(get_ivs(sys))
    for v in get_dvs(sys)
        m = get_lattice_placement(v)
        m === nothing || _dverr("`$v` has `lattice_placement = $m`, which this version does not lower (every field " *
                                "lives at the cell centers); remove the metadata")
        L = get_lattice_level(v)
        L === nothing && continue
        L isa Coarse || _dverr(string("`", v, "` has `lattice_level = ", repr(L), "`, which is not a grid: give `Coarse(k)`, ",
            "the grid coarsened by `k` sites per axis (", L isa Integer && L >= 1 && ispow2(L) ? "`Coarse($L)`" : "`Coarse(4)`",
            "; k a power of two), or leave the metadata out (the lattice itself)"))
        l = level_of(L)
        l == 0 && continue
        for d in 1:N
            n = Int(disc.grid.dims[d])
            (n == 1 || n % L.k == 0) && continue
            _dverr(string("`", _name(_opof(v)), "` has `lattice_level = ", L, "`, which needs every axis of the lattice ",
                "divisible by ", L.k, "; axis ", d, " (`", length(ivs) == N + 1 ? ivs[d + 1] : d, "`) has ", n, " sites (",
                n, " = ", L.k, " × ", n ÷ L.k, " + ", n % L.k, "): give the lattice a size divisible by ", L.k,
                " on that axis (", L.k * cld(n, L.k), " or ", L.k * fld(n, L.k) > 0 ? L.k * fld(n, L.k) : L.k, "), or a smaller factor"))
        end
        lev[_opof(v)] = l
    end
    return lev
end

"""
    symbolic_discretize(pdesys, disc::LatticeDiscretization; update = nothing, leaf = nothing)

Lower `pdesys` to a [`CompiledField`](@ref). Rate equations `D(c) ~ rhs` become kernels
`rate:c` that store `rhs` in a scratch field `∂c` (the ODE right side) or, given
`update(kb, c, r)`, store its value in `c` itself (a stepper; `c`, `r` and the result are
IR handles). Map equations `Shift(t, 1)(c) ~ rhs` become kernels `map:c` that store `rhs`
in `c`; algebraic `K ~ expr` become kernels `aux:K`. Masked conditions declare a mask field
`mask:c`, its predicate kernel and a node-value rule; face conditions become face rules
(a face with no condition has zero flux).
"""
function symbolic_discretize(sys::PDESystem, disc::LatticeDiscretization{N};
                             update::U = nothing, leaf::L = nothing) where {N, U, L}
    check_vocabulary(sys)
    _scan_clock(sys)
    _check_parts(sys)
    sys = first(steady_form(sys, N))                # steady rows as rates; a time-free system timed
    sys = crossgrid_form(sys)                       # an operator across `Coarse` grids as an aux field
    sys = _clock_slot(sys, disc)
    ps, ic = _params(sys), _ics(sys)
    any(p -> p isa Pair, ps) && _dverr("parameters are declared natively, `@parameters Dc = 1e-3`; " *
                                       "the `ps` entry `$(first(filter(p -> p isa Pair, ps)))` is a `Pair`")
    ivs = unwrap.(get_ivs(sys))
    length(ivs) == N + 1 || _dverr("the grid has $N axes but the system has $(length(ivs) - 1) spatial variables (the first variable is time)")
    ends = map(ivs) do v
        k = findfirst(d -> isequal(unwrap(d.variables), v), get_domain(sys))
        k === nothing && _dverr("no domain for `$v`")
        Float64.((leftendpoint(get_domain(sys)[k].domain), rightendpoint(get_domain(sys)[k].domain)))
    end
    T = _statetype(disc)
    lo = ntuple(d -> ends[d + 1][1], N)
    h = ntuple(d -> (ends[d + 1][2] - ends[d + 1][1]) / disc.grid.dims[d], N)
    # dependent variables, keyed by operation (the callable `c`, never the applied term)
    dvs = Dict{Any, Any}(_opof(v) => unwrap(v) for v in get_dvs(sys))
    isin = Dict{Any, Bool}(op => ModelingToolkitBase.isinput(v) for (op, v) in dvs)
    # another group's field read by a spatial operator: an input with its face conditions
    cut = Dict{Any, Bool}(op => isin[op] && _meta(v, LatticeCutField) === true for (op, v) in dvs)
    ncomp(v) = (st = SymbolicUtils.symtype(v); st <: AbstractArray ? length(v) : 0)
    keys = Dict{Any, Vector{String}}(op => (n = ncomp(v); n == 0 ? [_name(op)] : ["$(_name(op))[$i]" for i in 1:n])
                                     for (op, v) in dvs)
    key(op, comp) = keys[op][max(comp, 1)]
    lev = _field_levels(sys, disc)       # `lattice_level = Coarse(k)`: op → level (fine ones absent)
    maxlev = maximum(values(lev); init = 0)
    for (k, m) in disc.methods
        op = _opof(k)
        haskey(dvs, op) || _dverr("the `methods` key `$k` matches no dependent variable")
        m isa FiniteVolume || _dverr("`$k`: the cutover lowers `FiniteVolume()` only; got `$m`")
    end
    # equations by field component
    eqs = Dict{String, Tuple{Symbol, Any, Int, Any}}()
    for eq in get_eqs(sys)
        kind, l = _eqkind(eq, isin, ivs)
        r = _fieldread(l, isin)
        isin[r.op] && _dverr("equation `$eq`: an input is set by the CPM, not by an equation")
        haskey(eqs, key(r.op, r.comp)) && _dverr("field `$(key(r.op, r.comp))` has two equations")
        kind == :aux && _reads(eq.rhs, (r.op,)) &&
            _dverr("equation `$eq`: an algebraic field cannot read itself")
        eqs[key(r.op, r.comp)] = (kind, r.op, r.comp, eq.rhs)
    end
    for (op, ks) in keys, k in ks
        isin[op] || haskey(eqs, k) || _dverr("field `$k` has no equation")
    end
    # boundary conditions; periodicity from the pairs, shared by every field
    bcs = parse_bcs(get_bcs(sys), Dict{Any, Bool}(op => isin[op] && !cut[op] for op in Base.keys(isin)), ivs, ends)
    filter!(b -> !(cut[b.op] && b.kind in (:masked, :initial)), bcs)   # (its own group's)
    seen = Set{Tuple{String, Symbol, Int, Int}}()
    for b in bcs                         # one condition per face, mask and start of each field
        slot = (key(b.op, b.comp), b.kind in (:dirichlet, :neumann, :robin) ? :face : b.kind, b.axis, b.side)
        slot in seen && _dverr("`$(b.eq)`: field `$(slot[1])` already has a condition there")
        push!(seen, slot)
    end
    pairs = [(key(b.op, b.comp), b.axis) for b in bcs if b.kind == :periodic]
    periodic = ntuple(d -> any(p -> p[2] == d, pairs), N)
    allops = collect(Base.keys(dvs))
    for b in bcs
        b.kind == :initial || continue
        eqs[key(b.op, b.comp)][1] in (:rate, :map) ||
            _dverr("`$(b.eq)`: only rate and map fields take an initial condition")
        _reads(b.value, allops) && _dverr("`$(b.eq)`: an initial value cannot read a field")
    end
    initial = Dict{String, Any}(key(b.op, b.comp) => something(_cval(b.value), b.value) for b in bcs if b.kind == :initial)
    for (op, v) in dvs                   # `initial_conditions` entries of the fields
        d = something(_icvalue(ic, v), _icvalue(ic, op), Some(nothing))
        d === nothing && continue
        isin[op] && _dverr("`initial_conditions` gives the input `$(_name(op))` a value; give input values to `discretize(…; inputs)`")
        ncomp(v) == 0 || _dverr("`initial_conditions` gives the array field `$(_name(op))` a value; give each component a condition `$(_name(op))(0, …)[i] ~ v`")
        k = key(op, 0)
        haskey(initial, k) && _dverr("field `$k` has an initial value in `initial_conditions` and a condition `$k(0, …) ~ v`; give one")
        eqs[k][1] in (:rate, :map) || _dverr("`initial_conditions` gives `$k` a value, but only rate and map fields take an initial value")
        _reads(d, allops) && _dverr("the initial value of `$k` in `initial_conditions` reads a field")
        initial[k] = something(_cval(d), d)
    end
    # a field's default (`@variables c(..) = v`) is its initial value where no condition
    # `c(0, …) ~ v` and no `initial_conditions` entry gives one; a condition wins, as in the
    # coupling into a model. An aux field has no initial value, so its default is unused.
    for (op, v) in dvs
        (isin[op] || ncomp(v) != 0 || haskey(initial, key(op, 0))) && continue
        haskey(eqs, key(op, 0)) && eqs[key(op, 0)][1] in (:rate, :map) || continue
        d = ModelingToolkitBase.hasdefault(v) ? ModelingToolkitBase.getdefault(v) : nothing
        d === nothing && continue
        _reads(d, allops) && _dverr("the default of `$(key(op, 0))` reads a field; give its initial value as a condition " *
                                    "`$(key(op, 0))(0, …) ~ v`")
        initial[key(op, 0)] = something(_cval(d), d)
    end
    for b in bcs
        b.kind in (:dirichlet, :neumann, :robin) || continue
        periodic[b.axis] && _dverr("`$(b.eq)` sets a face of axis $(b.axis), which a periodic pair makes periodic")
        cut[b.op] && continue                       # (another group's rate field: its group checked it)
        kb = eqs[key(b.op, b.comp)][1]
        kb == :aux && _dverr("`$(b.eq)`: `$(key(b.op, b.comp))` is an aux field (`$(key(b.op, b.comp)) ~ rhs`), whose values " *
                             "follow its expression: it takes no face condition; give the faces to the fields its expression reads")
        kb == :rate ||
            _dverr("`$(b.eq)`: face conditions apply to rate fields (a map's offset reads outside the box read 0)")
    end
    for (k, d) in pairs, (k2, (kind, _...)) in eqs
        kind in (:rate, :map) && !((k2, d) in pairs) &&
            _dverr("axis $d is periodic for `$k` but `$k2` has no periodic pair on it; periodicity is per axis")
    end
    # parameters: scalars by sorted name, spacing parameters valued from the grid; arrays → tables
    plist = sort!([unwrap(p) for p in ps if !(SymbolicUtils.symtype(unwrap(p)) <: AbstractArray)]; by = string)
    params = Dict{Any, Int}(p => i for (i, p) in enumerate(plist))
    spacing = Dict{Any, Int}(p => get_lattice_spacing(p) for p in plist if get_lattice_spacing(p) !== nothing)
    defaults = _promoted(Any[haskey(spacing, p) ? h[spacing[p]] : _default(p, ic) for p in plist])
    arrays = sort!([unwrap(p) for p in ps if SymbolicUtils.symtype(unwrap(p)) <: AbstractArray]; by = string)

    pb = ProgramBuilder(disc.grid; periodic, spacing = h, nparams = length(plist), levels = maxlev + 1)
    tables = Dict{Any, Tuple{Int32, Scalar}}(p => (table!(pb, string(p); storage = _lane(Float64, T)), _lane(Float64, T))
                                             for p in arrays)
    fids = Dict{Any, Tuple{Vector{Int32}, Scalar}}()
    for (op, v) in dvs
        S = get_lattice_storage(v)             # `lattice_storage`: the field's own storage
        S === nothing || S in (Float16, Float32, Float64) ||
            _dverr("field `$(_name(op))`: `lattice_storage = $S` is not a storage type; give Float16, Float32 or Float64 " *
                   "(a field stored in the problem's own type needs no `lattice_storage`)")
        lane = _lane(eltype(SymbolicUtils.symtype(v)), S === nothing ? T : S)
        # a declared Float32 or Float64 storage holds its own type whatever the problem's value
        # type (`fixed`; Float16 is always its own)
        fixed = S === Float32 || S === Float64
        levels = Int8[get(lev, op, 0)]
        fids[op] = (map(keys[op]) do k
                        isin[op] && return field!(pb, k; storage = lane, role = :input, epoch = PERSIGMA, fixed, levels)
                        kind = eqs[k][1]
                        field!(pb, k; storage = lane, role = kind == :aux ? :aux : :state,
                               buffers = kind == :map || (kind == :rate && update !== nothing) ? 2 : 1, fixed, levels)
                    end, lane)
    end
    # each field's level by its operation, and the level of each equation's field (by key)
    flev = Dict{Any, Int}(op => get(lev, op, 0) for op in Base.keys(dvs))
    klev(k) = flev[eqs[k][2]]
    hex = disc.grid.geometry == HEX
    hex && !(h[2] ≈ h[1]) && _dverr("a hexagonal grid needs equal spacing on both axes; the domain gives $h")
    # the irregular domain: a mask over its Bool input, and a zero-flux edge rule per rate field
    dom = Int32(0)
    dompred = nothing
    if disc.domain !== nothing
        dop = findfirst(op -> keys[op] == [disc.domain], collect(Base.keys(dvs)))
        dop === nothing && _dverr("`domain = \"$(disc.domain)\"` names no dependent variable")
        dop = collect(Base.keys(dvs))[dop]
        dompred = dvs[dop]
        (isin[dop] && fids[dop][2] == U8) || _dverr("`domain = \"$(disc.domain)\"` must name a `Bool` input field")
        dom = fids[dop][1][1]
        push!(pb.masks, MaskDecl("domain", dom, STATIC))
        g = disc.grid
        pb.hierarchy[1] = Level(Grid(g.dims; geometry = g.geometry, domain = length(pb.masks)))
    end
    # a kernel on level `lv` (its field's `Coarse` level) and its environment, with that level's spacing
    kern(lv) = lv == 0 ? kernel(pb) : kernel(pb, Space{N}(FULL; level = lv))
    dims = ntuple(d -> Int(disc.grid.dims[d]), N)
    # the domain on each coarse level: a node is in it when most of its block is (the
    # Majority fold of the Bool input), computed at a window's start with the masks; its mask
    # is the coarse field's domain edge
    domlev = Dict{Int, Tuple{Int32, Int32}}(0 => (dom, Int32(dom == 0 ? 0 : length(pb.masks))))
    if dom != 0
        for lv in sort!(unique(l for (op, l) in flev if !isin[op] && l > 0))
            df = field!(pb, "domain:$lv"; storage = U8, role = :aux, epoch = PERSIGMA, levels = Int8[lv])
            push!(pb.masks, MaskDecl("domain:$lv", df, PERSIGMA))
            kb = kern(lv)
            e = Env(kb, fids, params, tables, spacing, ivs[1], ivs[2:end], lo, level_spacing(h, dims, lv), false,
                ntuple(_ -> 0, N), RESOLVE, leaf, hex, Int32(0), Int32[], lv, flev, dims, 0)
            store!(kb, df, U8, cast!(kb, _cond(dvs[dop], e), U8))
            add!(pb, kb, "domain:$lv")
            domlev[lv] = (df, Int32(length(pb.masks)))
        end
        for (k, (kind, op, comp, _)) in eqs
            kind == :rate || continue
            lv = flev[op]
            rule!(pb, DomainEdgeRule(fids[op][1][max(comp, 1)], :mirror, lv == 0 ? Int32(0) : domlev[lv][2]))
        end
    end
    # the domain's field on level `lv` (0: no domain)
    dl(lv) = dom == 0 ? Int32(0) : domlev[lv][1]
    # the rate fields (each has a face rule on every non-periodic face): a face coefficient reads
    # them at the ghost site with the ghost value
    ghosted = Int32[fids[op][1][max(comp, 1)] for (_, (kind, op, comp, _)) in eqs if kind == :rate]
    # (and another group's field that an operator reads, with its own group's faces)
    faced = Tuple{String, Any, Int}[(k, op, comp) for (k, (kind, op, comp, _)) in eqs if kind == :rate]
    for (op, ks) in keys
        cut[op] || continue
        for (i, k) in enumerate(ks)
            push!(faced, (k, op, length(ks) == 1 ? 0 : i))
            push!(ghosted, fids[op][1][i])
        end
    end
    # (a hexagonal grid: the fields with a face condition, whose links out of the box read its
    # ghost, `_hexlap`; the others are zero flux there)
    hex && filter!(f -> any(b -> b.kind in (:dirichlet, :neumann, :robin) && (!isin[b.op] || cut[b.op]) &&
                                 fids[b.op][1][max(b.comp, 1)] == f, bcs), ghosted)
    env(mapmode, kb, lv = 0, free = nothing, domfree = nothing) = Env(kb, fids, params, tables, spacing, ivs[1], ivs[2:end], lo,
        level_spacing(h, dims, lv), mapmode, ntuple(_ -> 0, N), RESOLVE, leaf, hex, dl(lv), ghosted, lv, flev, dims, 0, free, domfree)
    # the coarse fields whose mask predicate reads fine fields blend: their equations fold
    # over each block's free children, and their mask holds a node when every child is masked
    free = Dict{String, Any}(key(b.op, b.comp) => b.pred for b in bcs
                             if b.kind == :masked && !isin[b.op] && reads_fine(b.pred, flev, flev[b.op]))
    # face rules: α c + β ∂c/∂n = g in lattice units (outward normal; ∂/∂n = side · h ∂/∂x)
    sitecoefs = Dict{Tuple{String, Int, Int}, Tuple{Any, Any}}()
    for (k, op, comp) in faced
        f = fids[op][1][max(comp, 1)]
        lv = flev[op]
        hL = level_spacing(h, dims, lv)
        # (a blending field's face values fold over the free children, as its rate does)
        fenv = let fr = get(free, k, nothing)
            (m, kb, l) -> env(m, kb, l, fr, dompred)
        end
        for d in 1:N, s in (-1, 1)
            periodic[d] && continue
            b = findfirst(b -> b.kind in (:dirichlet, :neumann, :robin) && key(b.op, b.comp) == k &&
                                   b.axis == d && b.side == s, bcs)
            b === nothing && (rule!(pb, FaceRule(f, Int8(d), Int8(s), Coef(0.0), Coef(1.0), Coef(0.0))); continue)
            bc = bcs[b]
            α, β = _coef(bc.alpha, params), _coef(bc.beta, params, s / hL[d])
            # a Robin coefficient that reads the coordinates or the time: a value field
            # computed at each site at the step's time, as a face value (in lattice units)
            af, ax = if α === nothing
                _coef_field!(pb, bc, bc.alpha, 1.0, "α", k, d, s, op, lv, fids, ivs, ends, allops, isin, kern, fenv)
            else
                (Int32(0), nothing)
            end
            bf, bx = if β === nothing
                _coef_field!(pb, bc, bc.beta, s / hL[d], "β", k, d, s, op, lv, fids, ivs, ends, allops, isin, kern, fenv)
            else
                (Int32(0), nothing)
            end
            (af == 0 && bf == 0) || (sitecoefs[(k, d, s)] = (ax, bx))
            α, β = something(α, Coef(1.0)), something(β, Coef(1.0))
            val(c) = c.param == 0 ? c.value : c.value * defaults[c.param]     # parameter defaults bind here
            af == 0 && bf == 0 && degenerate(val(α), val(β)) &&
                _dverr("`$(bc.eq)`: α/2 + β/h = 0 on this face leaves the ghost value undefined")
            g = _coef(bc.value, params)
            # a field read at the face (`G(t, 1, y)`, an input) is read at the boundary site,
            # where the value field is evaluated
            g === nothing && (bc = _unpin_face_reads(bc, fids, ivs))
            if g === nothing
                # a value of the time, the coordinates, parameters or inputs: a value field,
                # computed at each site by a kernel at the step's time (the boundary sites read it)
                _value_reads_state(bc.value, bc.eq, [o for o in allops if !isin[o]], "face value")
                gk = string("face:", k, ":", d, s > 0 ? "+" : "-")
                gf = field!(pb, gk; storage = fids[op][2], role = :aux, levels = Int8[lv])
                kb = kern(lv)
                e = fenv(false, kb, lv)
                # the face's own coordinate where the condition pins it
                gx = substitute(bc.value, Dict(ivs[d + 1] => ends[d + 1][s > 0 ? 2 : 1]); fold = Val(false))
                store!(kb, gf, fids[op][2], _real(e, lower(gx, e)))
                add!(pb, kb, gk)
                rule!(pb, FaceRule(f, Int8(d), Int8(s), α, β, Coef(1.0), gf, af, bf))
            else
                rule!(pb, FaceRule(f, Int8(d), Int8(s), α, β, g, Int32(0), af, bf))
            end
        end
    end
    for b in bcs
        b.kind == :masked || continue
        k = key(b.op, b.comp)
        isin[b.op] && _dverr("`$(b.eq)`: an input cannot carry a condition")
        eqs[key(b.op, b.comp)][1] == :aux &&
            _dverr("`$(b.eq)`: `$k` is an aux field (`$k ~ rhs`), whose values follow its expression: it takes no mask; " *
                   "mask a rate field, or read the aux field in a rate field and mask that")
        lv = flev[b.op]                   # (a coarse field's mask lives on its grid: its fine reads folded)
        mf = field!(pb, "mask:$k"; storage = U8, role = :aux, epoch = PERSIGMA, levels = Int8[lv])
        push!(pb.masks, MaskDecl("mask:$k", mf, PERSIGMA))
        mv = _coef(b.value, params)
        vf = Int32(0)
        if mv === nothing
            # a value of the time, the coordinates, parameters or inputs: a value field, which
            # the mask's kernel computes with the mask (each masked site takes its own value)
            _value_reads_state(b.value, b.eq, [o for o in allops if !isin[o]], "masked value")
            vf = field!(pb, "maskvalue:$k"; storage = fids[b.op][2], role = :aux, epoch = PERSIGMA, levels = Int8[lv])
        end
        # a value that reads the time: its rate `∂v/∂t` too, the masked sites'
        # rate on an OrdinaryDiffEq solver (the owned steppers write the value at each step)
        dv = vf == 0 ? nothing : _time_rate(b.value, ivs[1], o -> get(isin, o, false))
        rf = if dv === nothing
            Int32(0)
        else
            field!(pb, "maskrate:$k"; storage = fids[b.op][2], role = :aux, epoch = PERSIGMA, levels = Int8[lv])
        end
        kb = kern(lv)
        # (on a coarse grid a node is masked when its whole block is, a block masked in
        # part is free, and the field's equation folds over its free children)
        pred = _cond(b.pred, env(false, kb, lv); fold = :all)
        dom == 0 || (pred = node!(kb, AND, BOOL, Int32[pred, _indomain(kb, dl(lv), N)]))   # the field lives in the domain
        store!(kb, mf, U8, cast!(kb, pred, U8))
        if mv === nothing
            store!(kb, vf, fids[b.op][2], _real(env(false, kb, lv), lower(b.value, env(false, kb, lv))))
            mv = Coef(1.0)
            dv === nothing || store!(kb, rf, fids[b.op][2], _real(env(false, kb, lv), lower(dv, env(false, kb, lv))))
        end
        add!(pb, kb, "mask:$k")
        rule!(pb, NodeValueRule(fids[b.op][1][max(b.comp, 1)], Int32(length(pb.masks)), mv, :harmonic, vf))
    end
    lin = Dict{String, Vector{Pair{Any, Symbol}}}()
    states = [op for op in Base.keys(dvs) if !isin[op]]
    # the unknown fields of the linearity table: an array field by its components
    function staterefs_of(op)
        SymbolicUtils.symtype(dvs[op]) <: AbstractArray || return [op]
        return [_Comp(op, i) for i in eachindex(fids[op][1])]
    end
    staterefs = Any[r for op in states for r in staterefs_of(op)]
    for k in sort!(collect(Base.keys(eqs)))
        kind, op, comp, rhs = eqs[k]
        f, lane = fids[op][1][max(comp, 1)], fids[op][2]
        lv = flev[op]
        kb = kern(lv)
        e = env(kind == :map, kb, lv, kind in (:rate, :map) ? get(free, k, nothing) : nothing,
                kind in (:rate, :map) ? dompred : nothing)
        # (the equation being lowered, for callers that name it at a refusal; cleared once it lowers)
        task_local_storage(:lattice_equation, k)
        r = lower(rhs, e)
        delete!(task_local_storage(), :lattice_equation)
        if kind == :rate
            lin[k] = linearity(rhs, comp == 0 ? dvs[op] : _Comp(op, comp), staterefs; inputs = [o for o in Base.keys(dvs) if isin[o]],
                               aux = unique([v[2] for v in values(eqs) if v[1] == :aux]))
            # with a domain the field lives in it: a site outside keeps its value
            if update === nothing
                g = field!(pb, "∂$k"; storage = lane, role = :scratch, levels = Int8[lv])
                v = _real(e, r)
                dom == 0 || (v = select!(kb, _indomain(kb, dl(lv), N), v, constant!(kb, 0.0)))
                store!(kb, g, lane, v)
            else
                c = load!(kb, f, lane)
                v = update(kb, Ex(kb, c), Ex(kb, _real(e, r))).id
                dom == 0 || (v = select!(kb, _indomain(kb, dl(lv), N), v, c))
                store!(kb, f, lane, v)
            end
        else
            v = isfloat(lane) ? _real(e, r) : cast!(kb, _num(e, [r])[1], lane)
            dom == 0 || kind != :map || (v = select!(kb, _indomain(kb, dl(lv), N), v, load!(kb, f, lane)))
            store!(kb, f, lane, v)
        end
        add!(pb, kb, "$kind:$k")
    end
    tvals = [string(p) => (d = something(_icvalue(ic, p), Some(ModelingToolkitBase.hasdefault(p) ? ModelingToolkitBase.getdefault(p) : Float64[]));
                           _promoted(collect(unwrap_const.(unwrap.(d))))) for p in arrays]
    return CompiledField{N}(program(pb), keys, plist, defaults, tvals, initial, lin, sitecoefs, free, dompred)
end

# An aux field read at a neighbor site across a closed face (`laplacian(K)`) has no
# value there: an aux field takes no face rule (its values follow its expression), so the IR
# would find no ghost value. Refused at the build (`discretize`, `lower_group`; the symbolic
# form stays readable) in the equation's words, with the route. A read that needs no ghost (a
# `DivKGrad` coefficient, a periodic axis) is not refused.
function _check_aux_offsets(prog::Program{N}, sys::PDESystem) where {N}
    aux = Set(k.key[5:end] for k in prog.kernels if startswith(k.key, "aux:"))
    isempty(aux) && return nothing
    for kern in prog.kernels, a in kern.accesses
        K = prog.fields[a.field].key
        (a.policy == RESOLVE && K in aux && a.offset.cond == 0) || continue
        d = findfirst(e -> a.offset.a[e] != 0 && !prog.periodic[e], 1:N)
        d === nothing && continue
        kind, k = split(kern.key, ":"; limit = 2)
        ops = Any[o for o in (_opof(v) for v in get_dvs(sys)) if o !== nothing && string(nameof(o)) == K]
        r = nothing
        for eq in get_eqs(sys)
            r = _neighbor_read(eq.rhs, ops, get_ivs(sys), prog.periodic)
            r === nothing || break
        end
        what = if kind == "aux"
            "the expression of the aux field"
        elseif kind == "map"
            "the map of"
        else
            "the rate of"
        end
        _dverr(string(what, " `", k, "` reads the aux field `", K, "` at a neighbor site across a closed face of axis ", d,
            r === nothing ? "" : string(" (`", replace(as_written(string(r[1])), r"\(t(, \w+)*\)" => ""), "`)"),
            ": an aux field has no value beyond a ",
            "closed face (it takes no face condition). Write the term with the fields its expression reads (with ",
                "`K ~ k * c`, `laplacian(K)` is `k * laplacian(c)`), or make the axis periodic"
            )
        )
    end
    return nothing
end

# the first term of `x` that reads one of `ops` at neighbor sites across a closed axis, and that
# axis: a spatial operator (`laplacian`, `DivKGrad`, `Advect`: every axis; a `Differential` in a space
# variable: its axis) whose arguments read it; else `nothing`
function _neighbor_read(x, ops, ivs, periodic)
    u = unwrap(x)
    iscall(u) || return nothing
    f = operation(u)
    d = if f === laplacian || f isa DivKGrad || f isa Advect
        findfirst(!, periodic)
    elseif f isa Differential
        j = findfirst(v -> isequal(unwrap(f.x), unwrap(v)), ivs)
        j === nothing || j == 1 || periodic[j - 1] ? nothing : j - 1
    end
    d !== nothing && any(a -> _reads(a, ops), arguments(u)) && return (u, d)
    for a in arguments(u)
        r = _neighbor_read(a, ops, ivs, periodic)
        r === nothing || return r
    end
    return nothing
end
