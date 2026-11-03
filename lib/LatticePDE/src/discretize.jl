# The discretizer (v3 §2.3, §5): `PDESystem` + `LatticeDiscretization` → a LatticeFields
# `Program`. PDEBase is not used (R2 F-2, S-5: its bc parsing and its symbolic discretizer
# interface do not fit a lattice IR); the analysis here is ours: operation-normalized keys,
# the BC parser, the linearity table, map and offset-read classification, and the lowering.

"""`FiniteVolume()`: the cell-centered finite-volume method (face-flux form, §5.2)."""
struct FiniteVolume end

"""
    LatticeDiscretization(grid; methods = Dict(), T = nothing, backend = nothing, problem = :auto, domain = nothing,
                          clock = nothing)

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
`(q, r)` are `(q ± 1, r)`, `(q, r ± 1)`, `(q + 1, r − 1)` and `(q − 1, r + 1)`) lowers `Δ(c)` to
`2/(3h²) Σₙ (cₙ − c)` over the six neighbors (`h` the spacing of axis 1; the axes must have
equal spacing). A neighbor outside the domain reads the site itself (zero flux); a neighbor
outside the box reads the ghost of the face condition its link leaves through (a diagonal link
`±(e₁ − e₂)` takes axis 1's face when it leaves along axis 1, else axis 2's), with the
condition applied along the link in lattice units. Only `Δ` is defined there.

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

`clock = τ` declares the discretization's clock (F2 design §2.6), of period `τ` (finite,
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
    problem::Symbol
    domain::Union{Nothing, String}
    clock::Union{Nothing, Float64}
end
function LatticeDiscretization(grid::Grid; methods = Dict(), T::Union{Type, Nothing} = nothing,
                               backend = nothing, problem::Symbol = :auto, domain = nothing, clock = nothing)
    clock === nothing || (clock isa Real && isfinite(clock) && clock > 0) ||
        throw(ArgumentError("clock = $(repr(clock)) must be a finite period > 0 (or left out: no clock)"))
    problem in (:auto, :owned, :ode, :linear) ||
        throw(ArgumentError("problem must be :auto, :owned, :ode or :linear; got $(repr(problem))"))
    grid.domain == 0 || throw(ArgumentError("give an irregular domain as `domain = dom` (a Bool input field), not in the grid"))
    grid.geometry == HEX && length(grid.dims) != 2 && throw(ArgumentError("a hexagonal grid is 2D"))
    key = domain === nothing ? nothing : domain isa Union{AbstractString, Symbol} ? String(domain) : _name(_opof(domain))
    return LatticeDiscretization(grid, methods, T, backend, problem, key, clock === nothing ? nothing : Float64(clock))
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
array literal), `Advect(Upwind1())` (not `LatticePDE.Advect{LatticePDE.Upwind1}(…)`) and `Δ(K)`
(not `LatticePDE.Δ(K)`). For a
front end that prints lowered terms in its messages (Potts); LatticePDE's own messages print
through it too.
"""
function as_written(s::AbstractString)
    s = replace(s, r"(?:LatticePDE\.)?Advect\{[\w.]+\}\(" => "Advect(", r"LatticePDE\.Upwind1\(" => "Upwind1(")
    s = replace(s, r"LatticePDE\.(Δ|DivKGrad)\(" => s"\1(")      # (`Δ(K)`, not `LatticePDE.Δ(K)`)
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
_opof(x) = (u = unwrap(x); iscall(u) ? (operation(u) === getindex ? _opof(arguments(u)[1]) : operation(u)) : u)
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
# The parts of a `PDESystem` beyond its six lowered fields (SX-21): `ps = NullParameters()`
# (MTKBase's default) is no parameters; `initial_conditions` give parameter values (over the
# variable defaults) and field initial values (where no `c(0, …) ~ v` condition gives one);
# subsystems and analytic solutions are refused by name, never ignored
_params(sys::PDESystem) = sys.ps isa NullParameters ? Any[] : collect(sys.ps)
_ics(sys::PDESystem) = getfield(sys, :initial_conditions)
function _check_parts(sys::PDESystem)
    sy = getfield(sys, :systems)
    isempty(sy) || _dverr("`$(nameof(sys))` has subsystems ($(join(("`$(nameof(x))`" for x in sy), ", "))); " *
                          "`discretize` lowers one flat PDESystem: write their equations into it")
    (getfield(sys, :analytic) === nothing && getfield(sys, :analytic_func) === nothing) ||
        _dverr("`$(nameof(sys))` has analytic solutions, which `discretize` does not use in this version " *
               "(no solution carries them); compare against them yourself and leave `analytic` out")
    # every `initial_conditions` key is a parameter or a dependent variable (a typo is not ignored)
    known = Any[unwrap.(_params(sys)); unwrap.(sys.dvs); [_opof(v) for v in sys.dvs]]
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
    return v isa Real && !(v isa Bool) ? v : v isa Bool ? Float64(v) : NaN
end
# values as one vector: the promotion of Float64 with each value's type (an integer is a Float64)
_promoted(vs) = (T = mapreduce(typeof, promote_type, vs; init = Float64); T.(vs))

# a face or mask value: a number, a parameter, or a number times a parameter (else `nothing`
# with `strict = false`: a value field, F3-07)
function _coef(v, params, scale = 1.0; strict::Bool = true)
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
    strict || return nothing
    _dverr("the boundary value `$v` must be a number, a parameter, or a number times a parameter")
end
# A face value or a masked value that is an expression (F3-07): of the time, the coordinates,
# the parameters and the inputs, never of a field of the state (the condition would be another
# equation). It is lowered into a value field the kernels read (`FaceRule.gfield`,
# `NodeValueRule.vfield`).
function _unpin_face_reads(bc, fids, ivs)
    reps = Dict{Any, Any}()
    walk(y) = iscall(y) && (haskey(fids, operation(y)) ? (reps[y] = unwrap(operation(y)(ivs...))) :
                                                        foreach(a -> walk(unwrap(a)), arguments(y)))
    walk(unwrap(bc.value))
    isempty(reps) && return bc
    return BC(bc.kind, bc.op, bc.comp, bc.axis, bc.side, bc.alpha, bc.beta,
        substitute(bc.value, reps; fold = Val(false)), bc.pred, bc.eq)
end
function _value_reads_state(v, eq, states, what)
    _reads(v, states) && _dverr(string("`", eq, "`: the ", what, " `", v, "` reads a field of the state; a ", what,
        " may read the time, the coordinates, the parameters and the inputs (a condition that reads the field ",
        "itself is a Robin condition `α c + β ∂c/∂n = g`, with α and β numbers or parameters)"))
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

# The clock's step index (F2 design §2.6): every `step_index(t)` of the equations and
# conditions becomes the reserved parameter slot `clock__tick` (appended to the parameters),
# which the steppers write at every launch; refused without a declared clock, with an argument
# other than the time, or when the system already has a parameter of that name
const _CLOCK_TICK = unwrap(only(ModelingToolkitBase.@parameters clock__tick = 0.0))
_isclock(p) = string(unwrap(p)) == Problems.CLOCK_KEY
function _clock_slot(sys::PDESystem, disc::LatticeDiscretization)
    ps = _params(sys)
    any(_isclock, ps) && throw(ArgumentError("`$(Problems.CLOCK_KEY)` is the reserved name of the clock's slot (the " *
                                             "`__tick` suffix is reserved); give the parameter another name"))
    tt = unwrap(sys.ivs[1])
    calls = Any[]
    walk(u) = iscall(u) && (operation(u) === step_index ? push!(calls, u) : foreach(walk, arguments(u)))
    foreach(eq -> (walk(unwrap(eq.lhs)); walk(unwrap(eq.rhs))), [sys.eqs; sys.bcs])
    isempty(calls) && return sys
    for u in calls
        isequal(unwrap(only(arguments(u))), tt) ||
            _dverr("`$u`: the argument of `step_index` is the time `$tt` (the clock's step index at the current time)")
    end
    disc.clock === nothing && _dverr("`step_index($tt)` reads the discretization's clock, and the `LatticeDiscretization` " *
                                     "declares none; give `LatticeDiscretization(…; clock = τ)` (the period of one step index)")
    rule = Dict{Any, Any}(u => _CLOCK_TICK for u in unique(calls))
    sub(x) = substitute(x, rule; fold = Val(false))
    return PDESystem([sub(eq.lhs) ~ sub(eq.rhs) for eq in sys.eqs], [sub(b.lhs) ~ sub(b.rhs) for b in sys.bcs],
        getfield(sys, :domain), sys.ivs, sys.dvs, Any[ps; _CLOCK_TICK]; name = nameof(sys),
        initial_conditions = _ics(sys))
end

function _scan_clock(sys)
    walk(u, eq) = iscall(u) && ((operation(u) isa Hold || operation(u) isa Sample ||
                                 (operation(u) isa Shift && operation(u).steps != 1)) &&
                                _dverr("`$eq`: `$(operation(u))` is not supported; only `Shift(t, 1)` maps are; $SHIFT_HINT");
                                foreach(a -> walk(a, eq), arguments(u)))
    foreach(eq -> (walk(unwrap(eq.lhs), eq); walk(unwrap(eq.rhs), eq)), [sys.eqs; sys.bcs])
end

# The `Coarse` level of each dependent variable (F3-16): `[lattice_level = Coarse(k)]` puts the
# field on the grid coarsened by `k`; every axis of the lattice but one of size 1 must have a
# size that `k` divides (a remainder would make the last block wider, where the stencil of
# spacing `k h` is inconsistent: refused, naming the axis and the route). `lattice_placement`
# is not lowered yet and is refused, never ignored. Returns `op => level` for the coarse ones.
function _field_levels(sys::PDESystem, disc::LatticeDiscretization{N}) where {N}
    lev = Dict{Any, Int}()
    ivs = unwrap.(sys.ivs)
    for v in sys.dvs
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
    sys = first(steady_form(sys, N))                # steady rows as rates; a time-free system timed (F3-12b)
    sys = _clock_slot(sys, disc)
    ps, ic = _params(sys), _ics(sys)
    any(p -> p isa Pair, ps) && _dverr("parameters are declared natively, `@parameters Dc = 1e-3`; " *
                                       "the `ps` entry `$(first(filter(p -> p isa Pair, ps)))` is a `Pair`")
    ivs = unwrap.(sys.ivs)
    length(ivs) == N + 1 || _dverr("the grid has $N axes but the system has $(length(ivs) - 1) spatial variables (the first variable is time)")
    ends = map(ivs) do v
        k = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        k === nothing && _dverr("no domain for `$v`")
        Float64.((leftendpoint(sys.domain[k].domain), rightendpoint(sys.domain[k].domain)))
    end
    T = _statetype(disc)
    lo = ntuple(d -> ends[d + 1][1], N)
    h = ntuple(d -> (ends[d + 1][2] - ends[d + 1][1]) / disc.grid.dims[d], N)
    # dependent variables, keyed by operation (the callable `c`, never the applied term)
    dvs = Dict{Any, Any}(_opof(v) => unwrap(v) for v in sys.dvs)
    isin = Dict{Any, Bool}(op => ModelingToolkitBase.isinput(v) for (op, v) in dvs)
    ncomp(v) = (st = SymbolicUtils.symtype(v); st <: AbstractArray ? length(v) : 0)
    keys = Dict{Any, Vector{String}}(op => (n = ncomp(v); n == 0 ? [_name(op)] : ["$(_name(op))[$i]" for i in 1:n])
                                     for (op, v) in dvs)
    key(op, comp) = keys[op][max(comp, 1)]
    lev = _field_levels(sys, disc)       # `lattice_level = Coarse(k)` (F3-16): op → level (fine ones absent)
    maxlev = maximum(values(lev); init = 0)
    for (k, m) in disc.methods
        op = _opof(k)
        haskey(dvs, op) || _dverr("the `methods` key `$k` matches no dependent variable")
        m isa FiniteVolume || _dverr("`$k`: the cutover lowers `FiniteVolume()` only; got `$m`")
    end
    # equations by field component
    eqs = Dict{String, Tuple{Symbol, Any, Int, Any}}()
    for eq in sys.eqs
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
    bcs = parse_bcs(sys.bcs, isin, ivs, ends)
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
    for (op, v) in dvs                   # `initial_conditions` entries of the fields (SX-21)
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
    for b in bcs
        b.kind in (:dirichlet, :neumann, :robin) || continue
        periodic[b.axis] && _dverr("`$(b.eq)` sets a face of axis $(b.axis), which a periodic pair makes periodic")
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
        S = get_lattice_storage(v)             # `lattice_storage` (v3 §5.1): the field's own storage
        S === nothing || S in (Float16, Float32, Float64) ||
            _dverr("field `$(_name(op))`: `lattice_storage = $S` is not a storage type; give Float16, Float32 or Float64 " *
                   "(a field stored in the problem's own type needs no `lattice_storage`)")
        lane = _lane(eltype(SymbolicUtils.symtype(v)), S === nothing ? T : S)
        # a declared Float32 or Float64 storage holds its own type whatever the problem's value
        # type (FE-17: `fixed`; Float16 is always its own)
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
    if disc.domain !== nothing
        dop = findfirst(op -> keys[op] == [disc.domain], collect(Base.keys(dvs)))
        dop === nothing && _dverr("`domain = \"$(disc.domain)\"` names no dependent variable")
        dop = collect(Base.keys(dvs))[dop]
        (isin[dop] && fids[dop][2] == U8) || _dverr("`domain = \"$(disc.domain)\"` must name a `Bool` input field")
        dom = fids[dop][1][1]
        push!(pb.masks, MaskDecl("domain", dom, STATIC))
        g = disc.grid
        pb.hierarchy[1] = Level(Grid(g.dims; geometry = g.geometry, domain = length(pb.masks)))
    end
    # a kernel on level `lv` (its field's `Coarse` level) and its environment, with that level's spacing
    kern(lv) = lv == 0 ? kernel(pb) : kernel(pb, Space{N}(FULL; level = lv))
    dims = ntuple(d -> Int(disc.grid.dims[d]), N)
    # the domain on each coarse level (F3-16): a node is in it when most of its block is (the
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
            store!(kb, df, U8, cast!(kb, _bool(e, lower(dvs[dop], e)), U8))
            add!(pb, kb, "domain:$lv")
            domlev[lv] = (df, Int32(length(pb.masks)))
        end
        for (k, (kind, op, comp, _)) in eqs
            kind == :rate || continue
            lv = flev[op]
            rule!(pb, DomainEdgeRule(fids[op][1][max(comp, 1)], :mirror, lv == 0 ? Int32(0) : domlev[lv][2]))
        end
    end
    # the plurality owner of each integer input on each coarse level whose terms read it (review
    # r1 S1): the most frequent value of a node's children (ties to the smallest nonzero value, 0
    # last), computed at a window's start with the masks; a coarse term reads it for the input
    # (`_owner_load`) outside a mean fold
    for lv in sort!(unique(l for (op, l) in flev if !isin[op] && l > 0)),
        op in sort!([op for op in Base.keys(dvs) if isin[op] && fids[op][2] in (I32, U32)]; by = o -> keys[o][1])
        rd(x) = x !== nothing && _reads(x, Any[op])
        any(k -> klev(k) == lv && rd(eqs[k][4]), Base.keys(eqs)) ||
            any(b -> b.kind != :initial && !isin[b.op] && flev[b.op] == lv && (rd(b.eq.lhs) || rd(b.eq.rhs)), bcs) || continue
        ok = string("owner:", keys[op][1], ":", lv)
        of = field!(pb, ok; storage = fids[op][2], role = :aux, epoch = PERSIGMA, levels = Int8[lv])
        kb = kern(lv)
        ld = load!(kb, fids[op][1][1], fids[op][2]; offset = ntuple(_ -> 0, N), level = -lv, policy = INSIDE)
        store!(kb, of, fids[op][2], node!(kb, RESTRICT, kb.nodes[ld].type, Int32[ld], 2))
        add!(pb, kb, ok)
        fids[(:owner, op, lv)] = (Int32[of], fids[op][2])
    end
    # the domain's field on level `lv` (0: no domain)
    dl(lv) = dom == 0 ? Int32(0) : domlev[lv][1]
    # the rate fields (each has a face rule on every non-periodic face): a face coefficient reads
    # them at the ghost site with the ghost value (F3-ghost)
    ghosted = Int32[fids[op][1][max(comp, 1)] for (_, (kind, op, comp, _)) in eqs if kind == :rate]
    # (a hexagonal grid: the fields with a face condition, whose links out of the box read its
    # ghost, `_hexlap`; the others are zero flux there)
    hex && filter!(f -> any(b -> b.kind in (:dirichlet, :neumann, :robin) && !isin[b.op] &&
                                 fids[b.op][1][max(b.comp, 1)] == f, bcs), ghosted)
    env(mapmode, kb, lv = 0) = Env(kb, fids, params, tables, spacing, ivs[1], ivs[2:end], lo, level_spacing(h, dims, lv),
                                  mapmode, ntuple(_ -> 0, N), RESOLVE, leaf, hex, dl(lv), ghosted, lv, flev, dims, 0)
    # face rules: α c + β ∂c/∂n = g in lattice units (outward normal; ∂/∂n = side · h ∂/∂x)
    for (k, (kind, op, comp, _)) in eqs
        kind == :rate || continue
        f = fids[op][1][max(comp, 1)]
        lv = klev(k)
        hL = level_spacing(h, dims, lv)
        for d in 1:N, s in (-1, 1)
            periodic[d] && continue
            b = findfirst(b -> b.kind in (:dirichlet, :neumann, :robin) && key(b.op, b.comp) == k &&
                                   b.axis == d && b.side == s, bcs)
            b === nothing && (rule!(pb, FaceRule(f, Int8(d), Int8(s), Coef(0.0), Coef(1.0), Coef(0.0))); continue)
            bc = bcs[b]
            α, β = _coef(bc.alpha, params), _coef(bc.beta, params, s / hL[d])
            val(c) = c.param == 0 ? c.value : c.value * defaults[c.param]     # parameter defaults bind here
            degenerate(val(α), val(β)) &&
                _dverr("`$(bc.eq)`: α/2 + β/h = 0 on this face leaves the ghost value undefined")
            g = _coef(bc.value, params; strict = false)
            # a field read at the face (`G(t, 1, y)`, an input) is read at the boundary site,
            # where the value field is evaluated (batch 5 review N5)
            g === nothing && (bc = _unpin_face_reads(bc, fids, ivs))
            if g === nothing
                # a value of the time, the coordinates, parameters or inputs: a value field,
                # computed at each site by a kernel at the step's time (the boundary sites read it)
                _value_reads_state(bc.value, bc.eq, [o for o in allops if !isin[o]], "face value")
                gk = string("face:", k, ":", d, s > 0 ? "+" : "-")
                gf = field!(pb, gk; storage = fids[op][2], role = :aux, levels = Int8[lv])
                kb = kern(lv)
                e = env(false, kb, lv)
                # the face's own coordinate where the condition pins it
                gx = substitute(bc.value, Dict(ivs[d + 1] => ends[d + 1][s > 0 ? 2 : 1]); fold = Val(false))
                store!(kb, gf, fids[op][2], _real(e, lower(gx, e)))
                add!(pb, kb, gk)
                rule!(pb, FaceRule(f, Int8(d), Int8(s), α, β, Coef(1.0), gf))
            else
                rule!(pb, FaceRule(f, Int8(d), Int8(s), α, β, g))
            end
        end
    end
    for b in bcs
        b.kind == :masked || continue
        k = key(b.op, b.comp)
        isin[b.op] && _dverr("`$(b.eq)`: an input cannot carry a condition")
        lv = flev[b.op]                   # (a coarse field's mask lives on its grid: its fine reads folded)
        mf = field!(pb, "mask:$k"; storage = U8, role = :aux, epoch = PERSIGMA, levels = Int8[lv])
        push!(pb.masks, MaskDecl("mask:$k", mf, PERSIGMA))
        mv = _coef(b.value, params; strict = false)
        vf = Int32(0)
        if mv === nothing
            # a value of the time, the coordinates, parameters or inputs: a value field, which
            # the mask's kernel computes with the mask (each masked site takes its own value)
            _value_reads_state(b.value, b.eq, [o for o in allops if !isin[o]], "masked value")
            vf = field!(pb, "maskvalue:$k"; storage = fids[b.op][2], role = :aux, epoch = PERSIGMA, levels = Int8[lv])
        end
        kb = kern(lv)
        pred = _bool(env(false, kb, lv), lower(b.pred, env(false, kb, lv)))
        dom == 0 || (pred = node!(kb, AND, BOOL, Int32[pred, _indomain(kb, dl(lv), N)]))   # the field lives in the domain
        store!(kb, mf, U8, cast!(kb, pred, U8))
        if mv === nothing
            store!(kb, vf, fids[b.op][2], _real(env(false, kb, lv), lower(b.value, env(false, kb, lv))))
            mv = Coef(1.0)
        end
        add!(pb, kb, "mask:$k")
        rule!(pb, NodeValueRule(fids[b.op][1][max(b.comp, 1)], Int32(length(pb.masks)), mv, :harmonic, vf))
    end
    lin = Dict{String, Vector{Pair{Any, Symbol}}}()
    states = [op for op in Base.keys(dvs) if !isin[op]]
    # the unknown fields of the linearity table: an array field by its components
    staterefs = Any[r for op in states for r in (SymbolicUtils.symtype(dvs[op]) <: AbstractArray ?
                                                 [_Comp(op, i) for i in eachindex(fids[op][1])] : [op])]
    for k in sort!(collect(Base.keys(eqs)))
        kind, op, comp, rhs = eqs[k]
        f, lane = fids[op][1][max(comp, 1)], fids[op][2]
        lv = flev[op]
        kb = kern(lv)
        e = env(kind == :map, kb, lv)
        # (the equation being lowered, for a front end that names it at a refusal: A's `@equations`
        # line, review r1 N2; cleared once it lowers)
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
    return CompiledField{N}(program(pb), keys, plist, defaults, tvals, initial, lin)
end

# An aux field read at a neighbor site across a closed face (`Δ(K)`, F3-02 review S6) has no
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
        ops = Any[o for o in (_opof(v) for v in sys.dvs) if o !== nothing && string(nameof(o)) == K]
        r = nothing
        for eq in sys.eqs
            r = _neighbor_read(eq.rhs, ops, sys.ivs, prog.periodic)
            r === nothing || break
        end
        what = kind == "aux" ? "the expression of the aux field" : kind == "map" ? "the map of" : "the rate of"
        _dverr(string(what, " `", k, "` reads the aux field `", K, "` at a neighbor site across a closed face of axis ", d,
            r === nothing ? "" : string(" (`", replace(as_written(string(r[1])), r"\(t(, \w+)*\)" => ""), "`)"),
            ": an aux field has no value beyond a ",
            "closed face (it takes no face condition). Write the term with the fields its expression reads (with ",
            "`K ~ k * c`, `Δ(K)` is `k * Δ(c)`), or make the axis periodic"))
    end
    return nothing
end

# the first term of `x` that reads one of `ops` at neighbor sites across a closed axis, and that
# axis: a spatial operator (`Δ`, `DivKGrad`, `Advect`: every axis; a `Differential` in a space
# variable: its axis) whose arguments read it; else `nothing`
function _neighbor_read(x, ops, ivs, periodic)
    u = unwrap(x)
    iscall(u) || return nothing
    f = operation(u)
    d = if f === Δ || f isa DivKGrad || f isa Advect
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
