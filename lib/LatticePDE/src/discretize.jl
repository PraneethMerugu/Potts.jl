# The discretizer (v3 §2.3, §5): `PDESystem` + `LatticeDiscretization` → a LatticeFields
# `Program`. PDEBase is not used (R2 F-2, S-5: its bc parsing and its symbolic discretizer
# interface do not fit a lattice IR); the analysis here is ours: operation-normalized keys,
# the BC parser, the linearity table, map and offset-read classification, and the lowering.

"""`FiniteVolume()`: the cell-centered finite-volume method (face-flux form, §5.2)."""
struct FiniteVolume end

"""
    LatticeDiscretization(grid; methods = Dict(), T = nothing, backend = nothing, problem = :auto)

How a `PDESystem` is put on a lattice. `grid = Grid(dims)` gives only the site counts: the
spacing is derived from the system's domain (`extent ./ dims`) and periodicity from its
periodic bc pairs, so there is one source of truth. `methods` maps a field (`c`, `c(t, x, y)`
or `u`; keys are normalized by operation) to its method; a field without an entry is
`FiniteVolume()`.

`T` is the state type (P5 role model: the only number-type keyword): `Float16`, `Float32`,
`Float64`, or `BigFloat` on the host (stored in F64 lanes that hold BigFloat). `nothing` (the
default) means Float64 on the host and Float32 on a device. Any other type is refused. After
`discretize`, the eltype of `u0` (and Dual parameters) decide; see `remake`.
"""
struct LatticeDiscretization{N, M, B} <: AbstractDiscretization
    grid::Grid{N}
    methods::M
    T::Union{Type, Nothing}
    backend::B
    problem::Symbol
end
function LatticeDiscretization(grid::Grid; methods = Dict(), T::Union{Type, Nothing} = nothing,
                               backend = nothing,
                               problem::Symbol = :auto)
    problem in (:auto, :owned, :ode, :linear) ||
        throw(ArgumentError("problem must be :auto, :owned, :ode or :linear; got $(repr(problem))"))
    return LatticeDiscretization(grid, methods, T, backend, problem)
end

"""
The lowered field system. `program` is the LatticeFields `Program` (before the semantic
passes); `keys[op]` are the field keys of each dependent variable (one per component);
`params[i]` is the parameter of slot `i` with its value `defaults[i]` (`lattice_spacing`
parameters take the grid spacing; `NaN` when there is no default); `tables` the array
parameters with their values; `initial` the initial-condition right sides by field key;
`linearity` the class of every rate term by field key.
"""
struct CompiledField{N}
    program::Program{N}
    keys::Dict{Any, Vector{String}}
    params::Vector{Any}
    defaults::Vector{Float64}
    tables::Vector{Pair{String, Vector{Float64}}}
    initial::Dict{String, Any}
    linearity::Dict{String, Vector{Pair{Any, Symbol}}}
end

"""Launch-varying slot of the time `t` (`G.rt[RUNTIME_T]`)."""
const RUNTIME_T = 1

_dverr(msg) = throw(ArgumentError(msg))
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
    return disc.backend === nothing || Exec.supports_float64(disc.backend) ? Float64 : Float32
end
_default(p) = ModelingToolkitBase.hasdefault(p) ? Float64(unwrap_const(ModelingToolkitBase.getdefault(p))) : NaN

# a face or mask value: a number, a parameter, or a number times a parameter
function _coef(v, params, scale = 1.0)
    u = unwrap(v)
    c = _cval(u)
    c !== nothing && return Coef(Float64(c) * scale + 0.0)          # no -0.0 in the printed rule
    haskey(params, u) && return Coef(scale, Int32(params[u]))
    if iscall(u) && operation(u) === (*)
        a = arguments(u)
        k = findfirst(y -> haskey(params, unwrap(y)), a)
        rest = _cval(prod(a[setdiff(eachindex(a), [k])]))
        k !== nothing && rest !== nothing && return Coef(Float64(rest) * scale, Int32(params[unwrap(a[k])]))
    end
    _dverr("the boundary value `$v` must be a number, a parameter, or a number times a parameter")
end

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
    _iszero(l) && _dverr("equation `$eq`: quasi-steady `0 ~ rhs` fields are lowered by the solver group, not by `symbolic_discretize`")
    _dverr("equation `$eq`: the left side must be `D(c)`, `Shift(t, 1)(c)` or a field `c`")
end

function _scan_clock(sys)
    walk(u, eq) = iscall(u) && ((operation(u) isa Hold || operation(u) isa Sample ||
                                 (operation(u) isa Shift && operation(u).steps != 1)) &&
                                _dverr("`$eq`: `$(operation(u))` is not supported; only `Shift(t, 1)` maps are; $SHIFT_HINT");
                                foreach(a -> walk(a, eq), arguments(u)))
    foreach(eq -> (walk(unwrap(eq.lhs), eq); walk(unwrap(eq.rhs), eq)), [sys.eqs; sys.bcs])
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
    any(p -> p isa Pair, sys.ps) && _dverr("parameters are declared natively, `@parameters Dc = 1e-3`; " *
                                           "the `ps` entry `$(first(filter(p -> p isa Pair, sys.ps)))` is a `Pair`")
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
    for b in bcs
        b.kind in (:dirichlet, :neumann, :robin) || continue
        periodic[b.axis] && _dverr("`$(b.eq)` sets a face of axis $(b.axis), which a periodic pair makes periodic")
        eqs[key(b.op, b.comp)][1] == :rate ||
            _dverr("`$(b.eq)`: face conditions apply to rate fields (a map's offset reads outside the box read 0)")
    end
    for (k, d) in pairs, (k2, (kind, _...)) in eqs
        kind in (:rate, :map) && !((k2, d) in pairs) &&
            _dverr("axis $d is periodic for `$k` but `$k2` has no periodic pair on it; periodicity is per axis")
    end
    # parameters: scalars by sorted name, spacing parameters valued from the grid; arrays → tables
    plist = sort!([unwrap(p) for p in sys.ps if !(SymbolicUtils.symtype(unwrap(p)) <: AbstractArray)]; by = string)
    params = Dict{Any, Int}(p => i for (i, p) in enumerate(plist))
    spacing = Dict{Any, Int}(p => get_lattice_spacing(p) for p in plist if get_lattice_spacing(p) !== nothing)
    defaults = [haskey(spacing, p) ? h[spacing[p]] : _default(p) for p in plist]
    arrays = sort!([unwrap(p) for p in sys.ps if SymbolicUtils.symtype(unwrap(p)) <: AbstractArray]; by = string)

    pb = ProgramBuilder(disc.grid; periodic, spacing = h, nparams = length(plist))
    tables = Dict{Any, Tuple{Int32, Scalar}}(p => (table!(pb, string(p); storage = _lane(Float64, T)), _lane(Float64, T))
                                             for p in arrays)
    fids = Dict{Any, Tuple{Vector{Int32}, Scalar}}()
    for (op, v) in dvs
        lane = _lane(eltype(SymbolicUtils.symtype(v)), T)
        fids[op] = (map(keys[op]) do k
                        isin[op] && return field!(pb, k; storage = lane, role = :input, epoch = PERSIGMA)
                        kind = eqs[k][1]
                        field!(pb, k; storage = lane, role = kind == :aux ? :aux : :state,
                               buffers = kind == :map || (kind == :rate && update !== nothing) ? 2 : 1)
                    end, lane)
    end
    env(mapmode, kb) = Env(kb, fids, params, tables, spacing, ivs[1], ivs[2:end], lo, h, mapmode,
                           ntuple(_ -> 0, N), RESOLVE, leaf)
    # face rules: α c + β ∂c/∂n = g in lattice units (outward normal; ∂/∂n = side · h ∂/∂x)
    for (k, (kind, op, comp, _)) in eqs
        kind == :rate || continue
        f = fids[op][1][max(comp, 1)]
        for d in 1:N, s in (-1, 1)
            periodic[d] && continue
            b = findfirst(b -> b.kind in (:dirichlet, :neumann, :robin) && key(b.op, b.comp) == k &&
                                   b.axis == d && b.side == s, bcs)
            b === nothing && (rule!(pb, FaceRule(f, Int8(d), Int8(s), Coef(0.0), Coef(1.0), Coef(0.0))); continue)
            bc = bcs[b]
            α, β = _coef(bc.alpha, params), _coef(bc.beta, params, s / h[d])
            val(c) = c.param == 0 ? c.value : c.value * defaults[c.param]     # parameter defaults bind here
            Problems.degenerate(val(α), val(β)) &&
                _dverr("`$(bc.eq)`: α/2 + β/h = 0 on this face leaves the ghost value undefined")
            rule!(pb, FaceRule(f, Int8(d), Int8(s), α, β, _coef(bc.value, params)))
        end
    end
    for b in bcs
        b.kind == :masked || continue
        k = key(b.op, b.comp)
        isin[b.op] && _dverr("`$(b.eq)`: an input cannot carry a condition")
        mf = field!(pb, "mask:$k"; storage = U8, role = :aux, epoch = PERSIGMA)
        push!(pb.masks, MaskDecl("mask:$k", mf, PERSIGMA))
        kb = kernel(pb)
        store!(kb, mf, U8, cast!(kb, _bool(env(false, kb), lower(b.pred, env(false, kb))), U8))
        add!(pb, kb, "mask:$k")
        rule!(pb, NodeValueRule(fids[b.op][1][max(b.comp, 1)], Int32(length(pb.masks)), _coef(b.value, params), :harmonic))
    end
    lin = Dict{String, Vector{Pair{Any, Symbol}}}()
    states = [op for op in Base.keys(dvs) if !isin[op]]
    for k in sort!(collect(Base.keys(eqs)))
        kind, op, comp, rhs = eqs[k]
        f, lane = fids[op][1][max(comp, 1)], fids[op][2]
        kb = kernel(pb)
        e = env(kind == :map, kb)
        r = lower(rhs, e)
        if kind == :rate
            lin[k] = linearity(rhs, dvs[op], states; inputs = [o for o in Base.keys(dvs) if isin[o]],
                               aux = unique([v[2] for v in values(eqs) if v[1] == :aux]))
            if update === nothing
                g = field!(pb, "∂$k"; storage = lane, role = :scratch)
                store!(kb, g, lane, _real(e, r))
            else
                c = load!(kb, f, lane)
                store!(kb, f, lane, update(kb, Ex(kb, c), Ex(kb, _real(e, r))).id)
            end
        else
            store!(kb, f, lane, isfloat(lane) ? _real(e, r) : cast!(kb, _num(e, [r])[1], lane))
        end
        add!(pb, kb, "$kind:$k")
    end
    tvals = [string(p) => (d = ModelingToolkitBase.hasdefault(p) ? ModelingToolkitBase.getdefault(p) : Float64[];
                           Float64.(collect(unwrap_const.(unwrap.(d))))) for p in arrays]
    return CompiledField{N}(program(pb), keys, plist, defaults, tvals, initial, lin)
end
