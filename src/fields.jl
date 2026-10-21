# Fields (v3 §2.3, §7; cutover C8). A model's field equations `D(c) ~ rate` and its
# `@boundary` entries are a ModelingToolkitBase `PDESystem` (`Potts.fields(csys.sys)`) over
# the lattice's coordinates; LatticePDE discretizes it into a LatticeFields program and
# `CorePotts.FieldPhase` runs the program's step plan inside the MCS.
#
# The CPM enters a field equation through inputs: dependent variables `[input = true]` of the
# PDESystem, bound to site arrays of the state.
#   - a field or site variable that the group does not step is read from its own array;
#   - the site's kind (`kind`) is the input `kind__in(t, x, …)::Int32`;
#   - any other term that reads the CPM and no field (an owner's cell variable, `position`, a
#     helper over the neighbourhood, …) is one input `fieldₖ__in`, the term's value at each
#     site, written by one site phase before the field step every MCS.
# The clock (F2 design §2.6): the discretization's clock is `mcs_duration`. `mcs` is its step
# index, `LatticePDE.step_index(t)` (the reserved slot `clock__tick`, the MCS number at every
# substep), and `time` is the PDESystem's time `t`: the CPM's time at the start of the field
# window, advancing by `h` per substep.

# the spatial independent variables, one per lattice axis
const _FIELD_X = Tuple(Symbolics.unwrap(only(ModelingToolkitBase.@parameters $n)) for n in (:x, :y, :z))
# the names a model body binds for its field equations (F2 design §2.11): the lattice
# coordinates `x`, `y`, `z` (the PDESystem's spatial variables: `D(c) ~ x`, a raw flux
# `Differential(x)(K * Differential(x)(c))`), LatticePDE's `masked` and operators (`DivKGrad`,
# `Advect`, `Upwind1`; `Δ` is in `DSL`), and MTK's `Differential` and `Shift` (a map
# `Shift(t, 1)(m) ~ rhs`), so a model needs no import for them. A model that declares a
# quantity of one of these names keeps its own.
const FIELD_NAMES = (; x = Symbolics.wrap(_FIELD_X[1]), y = Symbolics.wrap(_FIELD_X[2]), z = Symbolics.wrap(_FIELD_X[3]),
    masked = LatticePDE.masked, DivKGrad = LatticePDE.DivKGrad, Advect = LatticePDE.Advect, Upwind1 = LatticePDE.Upwind1,
    Differential = Differential, Shift = ModelingToolkitBase.Shift)
_coordinate(u) = any(v -> v === u || isequal(v, u), _FIELD_X)

# a callable dependent variable `name(..)` of element type `E`, applied to the ivs
function _field_var(name::Symbol, ::Type{E}, ivs; input::Bool = false, entity = nothing, storage = nothing,
        username = nothing, bounds = nothing) where {E}
    f = Symbolics.unwrap(Symbolics.variable(name; T = SymbolicUtils.FnType{Tuple, E, Nothing}))
    v = f(ivs...)
    bounds === nothing || (v = SymbolicUtils.setmetadata(v, ModelingToolkitBase.VariableBounds, bounds))
    input && (v = SymbolicUtils.setmetadata(v, ModelingToolkitBase.VariableInput, true))
    username === nothing || (v = SymbolicUtils.setmetadata(v, LatticePDE.LatticeInputName, username))
    entity === nothing || (v = SymbolicUtils.setmetadata(v, PottsEntity, entity))
    S = storage === nothing && entity isa Entity ? get(entity.options, :lattice_storage, nothing) : storage
    S === nothing || (v = SymbolicUtils.setmetadata(v, LatticePDE.LatticeStorage, S))
    return v
end
# the `lattice_storage` of field `name` of `sys` (`nothing`: the state type)
_field_storage(sys, name) = (x = only(x for x in _p(sys, :variables) if info(x) !== nothing && info(x).name === name);
                             get(info(x).options, :lattice_storage, nothing))

# the calls the lattice compiler lowers: LatticePDE's one allowlist (F2 design §2.11), so a
# call lowers in `@equations` exactly when it lowers in a PDESystem
_field_op(f) = LatticePDE.lowers_call(f)
# LatticePDE's spatial operators, passed through to the PDESystem (F2 design §2.11)
_spatial_op(f) = f === Δ || f isa LatticePDE.DivKGrad || f isa LatticePDE.Advect || f isa Differential

"""
The CPM inputs of a model's fields: `(name, expr, eltype)` per filled input, in the canonical
order (`_canonical_filled`): `kind__in` first, then the CPM reads by their expression text
(`field1__in`, `field2__in`, … in that order), then `domain__in`.
"""
struct _FieldInputs
    filled::Vector{Tuple{Symbol, Any, Type}}
end

_is_field_name(sys, n) = any(x -> (i = info(x); i !== nothing && i.name === n && i.role in (:field, :site)), _p(sys, :variables))

# Whether `u` reads a field or site variable (anywhere inside)
function _reads_site_vars(u)
    hit = Ref(false)
    _walk_all(y -> (i = info(y); i !== nothing && i.role in (:field, :site) && (hit[] = true)), u)
    return hit[]
end

# the filled input of term `u`: its element type from the term's symbolic type
function _filled_type(u, T)
    st = SymbolicUtils.symtype(u)
    st <: Bool && return Bool
    st <: Integer && return Int32
    return T
end

"""
    _field_term(u, cv) -> term

The PDESystem form of the Potts term `u`. `cv` is the conversion state: `ivs`, `states`
(field name → applied dependent variable of the stepped group), `direct` (name → applied
input for a variable read from its own array), `filled` (the filled inputs, by expression),
`params` (the parameters read), `T` (the state type of real inputs).
"""
function _field_term(x, cv)
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return u
    SymbolicUtils.isconst(u) && return u
    i = info(u)
    if i !== nothing
        if i.role in (:field, :site)
            haskey(cv.states, i.name) && return cv.states[i.name]
            return get!(() -> _field_var(i.name, Real, cv.ivs; input = true, entity = i), cv.direct, i.name)
        elseif i.role in (:param, :kindtable)
            push!(cv.params, u)
            return u
        elseif i.role === :builtin && i.name === :mcs
            return _unwrap(LatticePDE.step_index(Symbolics.wrap(cv.ivs[1])))
        elseif i.role === :builtin && i.name === :time
            return cv.ivs[1]
        elseif i.role === :builtin && i.name === :kind
            return _filled_input!(cv, u, :kind__in, Int32)
        end
    end
    _coordinate(u) && return u                  # a lattice coordinate `x`, `y`, `z`
    iscall(u) || return _filled_or_refuse(cv, u)
    f, a = operation(u), arguments(u)
    if _spatial_op(f)
        # the operand of a spatial operator is a field (its last argument; `DivKGrad(K, c)`,
        # `Advect(u, c)`); the coefficient and the velocity are any lowered term
        _check_operand(u, f, a[end], cv)
        f isa Differential && _check_axis(u, f, cv)
        # a velocity written as a vector (`Advect(Upwind1())([ux, uy], c)`, a vector quantity)
        # converts per component
        conv(y) = (v = LatticePDE.velocity_terms(_unwrap(y));
                   v === nothing ? Symbolics.wrap(_field_term(y, cv)) : [Symbolics.wrap(_field_term(z, cv)) for z in v])
        return _unwrap(f(map(conv, a)...))
    elseif f === ismember
        return _unwrap(ismember(Symbolics.wrap(_field_term(a[1], cv)), SymbolicUtils.unwrap_const(a[2])))
    elseif f === at && info(a[1]) !== nothing && info(a[1]).role === :kindtable && length(a) == 2
        # Potts kind tables include the medium at entry 1 (kind 0); the lattice table is 1-based
        push!(cv.params, _unwrap(a[1]))
        return _unwrap(at(Symbolics.wrap(_unwrap(a[1])), Symbolics.wrap(_field_term(a[2], cv)) + 1))
    elseif _field_op(f)
        # an `ifelse` of CPM reads only (no field) that needs a filled input is filled whole:
        # the fill then evaluates only the taken branch (a neighbor fold under a kind test
        # runs on the sites of that kind only, as the CPM code does)
        f === ifelse && !_reads_fieldvar(u) && _has_cpm_fill(u) && return _filled_or_refuse(cv, u)
        return f === ifelse ? _unwrap(ifelse(map(y -> Symbolics.wrap(_field_term(y, cv)), a)...)) :
               _unwrap(f(map(y -> Symbolics.wrap(_field_term(y, cv)), a)...))
    elseif f isa ModelingToolkitBase.Shift
        # a map's own left side (`Shift(t, 1)(m) ~ rhs`); on a right side it has no meaning
        throw(ArgumentError("the term `$(_nopkg(_builtin_text(string(u))))` of a field equation reads `$(_nopkg(f))`: a " *
                            "`Shift` is the left side of a map, `Shift(t, 1)(m) ~ rhs` (the right side reads `m`, " *
                            "its value before the step)"))
    end
    return _filled_or_refuse(cv, u)
end
_nopkg(x) = LatticePDE.as_written(replace(string(x), "LatticePDE." => ""))   # as the model writes it

# The operand of a spatial operator (`Δ(c)`, `DivKGrad(K, c)`, `Advect(u, c)`, the inner end of a
# raw flux `Differential(x)(K * Differential(x)(c))`) is a field or site variable: an operator of
# a value the CPM writes once per MCS (a CPM read, `volume`) is refused, naming the operator
function _check_operand(u, f, y, cv)
    v = _unwrap(y)
    f isa Differential && iscall(v) && _has_operator(v, Differential) && return nothing   # the outer end of a flux
    _has_cpm_fill(v) && !_reads_fieldvar(v) || return nothing
    op = f isa Differential ? "Differential($(f.x))" : _nopkg(f)
    throw(ArgumentError("the term `$(_nopkg(_builtin_text(string(u))))` of a field equation applies `$op` to " *
                        "`$(_builtin_text(string(v)))`, a CPM read (a value the CPM writes once per MCS, not a field); " *
                        "a spatial operator applies to a field or site variable: hold the value in one " *
                        "(`@variables v(site)`, `@after_mcs v ~ $(_builtin_text(string(v)))`) and apply `$op` to it"))
end

# A raw derivative `Differential(x)` differentiates along a lattice axis: `x`, `y` or `z` of
# the model body (the PDESystem's spatial variables). A model that declares its own `x` keeps
# it, so `Differential(x)` there names that quantity, which is refused naming the clash
function _check_axis(u, f, cv)
    w = _unwrap(f.x)
    i = info(w)                                 # a quantity of the model (its own `x`) prints as `x` too
    i === nothing && any(v -> isequal(v, w), cv.ivs[2:end]) && return nothing
    name = i === nothing ? string(w) : string(i.name)
    clash = i !== nothing                       # the model's own quantity, else not an axis (`z` in 2D)
    axes = join(("`$(string(v))`" for v in cv.ivs[2:end]), ", ")
    throw(ArgumentError(clash ?
        "the term `$(_nopkg(_builtin_text(string(u))))` of a field equation differentiates along `$name`, but the model " *
        "declares its own `$name` (a $(i === nothing ? "quantity" : i.role === :param ? "parameter" : string(i.role, " variable"))), " *
        "which hides the lattice coordinate " *
        "`$name` inside the model; rename the model's `$name` (the lattice axes are $axes)" :
        "the term `$(_nopkg(_builtin_text(string(u))))` of a field equation differentiates along `$name`, which is not a " *
        "lattice axis; `Differential` takes an axis of the lattice: $axes"))
end

# whether `u` reads a field or site variable
function _reads_fieldvar(u)
    found = Ref(false)
    _walk(u) do y
        j = info(y)
        j !== nothing && j.role in (:field, :site) && (found[] = true)
    end
    return found[]
end

# whether lowering `u` (`_field_term`) makes a filled input other than `kind`
function _has_cpm_fill(x)
    u = _unwrap(x)
    u isa SymbolicUtils.BasicSymbolic || return false
    SymbolicUtils.isconst(u) && return false
    i = info(u)
    i === nothing || return !(i.role in (:field, :site, :param, :kindtable) || (i.role === :builtin && i.name in (:mcs, :time, :kind)))
    _coordinate(u) && return false
    iscall(u) || return true
    f, a = operation(u), arguments(u)
    _spatial_op(f) && return any(_has_cpm_fill, a)
    f === SymbolicUtils.array_literal && return any(_has_cpm_fill, something(LatticePDE.velocity_terms(u), a))
    f === ismember && return _has_cpm_fill(a[1])
    f === at && info(a[1]) !== nothing && info(a[1]).role === :kindtable && length(a) == 2 && return _has_cpm_fill(a[2])
    return _field_op(f) ? any(_has_cpm_fill, a) : true
end

function _filled_or_refuse(cv, u)
    _has_op(u, random_uniform) && throw(ArgumentError(
        "`rand()` in a field equation or boundary: the field compiler steps fields with no draws; draw in a " *
        "site update (`@after_mcs s ~ rand()`) and read the variable"))
    _reads_site_vars(u) && throw(ArgumentError(
        "the term `$(_builtin_text(string(u)))` of a field equation reads a field or site variable inside a CPM " *
        "read (a gather, a cell read, …); the field compiler lowers fields only through arithmetic, `Δ`, " *
        "`ismember`, `ifelse` and kind tables: compute the CPM part in a site update and read the variable"))
    # the model-wide list (`known`) names each term once, so every group binds the same array
    k = findfirst(e -> isequal(e[2], u), cv.filled)
    if k === nothing
        n = count(e -> e[1] !== :kind__in, cv.filled) + 1
        push!(cv.filled, (Symbol(:field, n, :__in), u, _filled_type(u, cv.T)))
        k = length(cv.filled)
    end
    return _filled_input!(cv, u, cv.filled[k][1], cv.filled[k][3])
end

function _filled_input!(cv, u, name, E)
    any(e -> e[1] === name, cv.filled) || push!(cv.filled, (name, u, E))
    # a kind is never negative: a kind table read `at(δ, kind + 1)` never takes index 0 (which
    # reads 0), and the stability bound leaves it out
    return get!(() -> _field_var(name, E === Bool ? Bool : E <: Integer ? Int32 : Real, cv.ivs; input = true,
            entity = Entity(:cpm_read, name, u, (;)), username = _input_word(name, u),
            bounds = name === :kind__in ? (0, Inf) : nothing), cv.inputs, name)
end
# the user's word for a generated input: `kind`, `domain`, or the CPM read as written (`volume`)
_input_word(name::Symbol, ex) = name === :kind__in ? "kind" : name === :domain__in ? "domain" :
                                _builtin_text(string(ex))

# a generated input goes by its word (`domain`, `kind`, a CPM read as written), and the field
# compiler routes reads and writes by name: a field, site variable or parameter with the same
# name is refused here, in the model's words (LatticeIndex would name the generated input)
function _refuse_input_words(cv, names, ps)
    taken = Dict{String, String}()
    foreach(n -> taken[string(n)] = "a field", names)
    foreach(k -> taken[string(k)] = "a site variable", keys(cv.direct))
    foreach(q -> taken[_builtin_text(string(q))] = "a parameter", ps)
    for e in cv.filled
        haskey(cv.inputs, e[1]) || continue
        w = _input_word(e[1], e[2])
        what = get(taken, w, nothing)
        what === nothing && continue
        src = e[1] === :domain__in ? "the lattice's domain mask" : e[1] === :kind__in ? "the site's kind" :
              "the CPM read `$w`"
        throw(ArgumentError("the field equations read `$w` ($src), and `$w` is also $what of the model; " *
                            "give the $(what[3:end]) another name"))
    end
    return nothing
end

# The canonical order of the filled inputs (R-F2b, 2026-10-20): `kind__in` first, then the CPM
# reads sorted by their expression text and numbered `field1__in`, `field2__in`, … in that
# order, then `domain__in`. The converter meets the reads in the hash order of a term's
# arguments (`*`, `+`), which changes with the package code; this order does not.
function _canonical_filled(raw)
    first_in = [e for e in raw if e[1] === :kind__in]
    last_in = [e for e in raw if e[1] === :domain__in]
    reads = sort!([e for e in raw if !(e[1] in (:kind__in, :domain__in))]; by = e -> string(e[2]))
    return Tuple{Symbol, Any, Type}[first_in;
                                    [(Symbol(:field, j, :__in), e[2], e[3]) for (j, e) in enumerate(reads)];
                                    last_in]
end

_field_conv(ivs, states, T, known) = (; ivs, states, direct = Dict{Symbol, Any}(),
    filled = Tuple{Symbol, Any, Type}[known...], inputs = Dict{Symbol, Any}(), params = Set{Any}(), T)

# The field equations of a model (F2 design §2.11): `(x, kind, op)` for a rate `D(c) ~ rhs`
# (`:rate`) or a map `Shift(t, 1)(m) ~ rhs` (`:map`, one application per MCS) of a field or
# site variable, or an aux definition `K ~ rhs` of a field variable (`:aux`, its value at every
# substep from the others); `op` is the left side's operator (`nothing` for aux); else `nothing`
function _field_lhs(eq)
    l = _unwrap(eq.lhs)
    if iscall(l) && (operation(l) isa Differential || operation(l) isa ModelingToolkitBase.Shift)
        x = arguments(l)[1]
        i = info(x)
        (i !== nothing && i.role in (:field, :site)) || return nothing
        return (x, operation(l) isa Differential ? :rate : :map, operation(l))
    end
    l isa SymbolicUtils.BasicSymbolic || return nothing
    i = info(l)                                 # a field variable `K(t)` itself
    return i !== nothing && i.role === :field ? (l, :aux, nothing) : nothing
end
# the stepped fields of a model, `(x, rhs, op)`: its rates and maps (`op` the `Differential` or
# the `Shift` of the left side)
_field_equations(sys::PottsSystem) = [(f[1], eq.rhs, f[3]) for eq in _p(sys, :equations)
                                      for f in (_field_lhs(eq),) if f !== nothing && f[2] !== :aux]
# the aux fields of a model, `(x, rhs)`: each group that steps fields computes them
_field_aux(sys::PottsSystem) = [(f[1], eq.rhs) for eq in _p(sys, :equations) for f in (_field_lhs(eq),)
                                if f !== nothing && f[2] === :aux]

"""
    _field_system(sys, names; T = Float64) -> (pdesys, cv)

The `PDESystem` of the fields `names` of model `sys` (all its fields by default): their
equations, their `@boundary` entries as bcs (faces, periodic pairs, masked conditions) and the
lattice as the domain (axis `d` spans `dims[d] · h[d]`). `cv` is the conversion state (its
inputs and parameters).
"""
function _field_system(sys::PottsSystem, names = Symbol[info(x).name for (x, _) in _field_equations(sys)]; T::Type = Float64,
        known = nothing)
    # the model-wide filled inputs in their canonical order: lowering finds each CPM read in
    # `known` by its expression, so the names and the order (the dvs, the fill phase) do not
    # depend on the order in which the converter meets the reads (R-F2b)
    known === nothing && (known = _canonical_filled(_field_system(sys; T, known = Tuple{Symbol, Any, Type}[])[2].filled))
    lat = _p(sys, :lattice)
    N = length(lat.dims)
    h = something(lat.spacing, ntuple(_ -> 1.0, N))
    tt = _unwrap(t)
    xs = collect(_FIELD_X[1:N])
    ivs = Any[tt; xs]
    aux = _field_aux(sys)
    auxnames = Symbol[info(x).name for (x, _) in aux]
    states = Dict{Symbol, Any}(n => _field_var(n, Real, ivs; storage = _field_storage(sys, n)) for n in [names; auxnames])
    cv = _field_conv(ivs, states, T, known)
    eqs = Equation[]
    for (x, rate, op) in _field_equations(sys)
        n = info(x).name
        n in names || continue
        lhs = op isa ModelingToolkitBase.Shift ? op(Symbolics.wrap(states[n])) : Differential(tt)(Symbolics.wrap(states[n]))
        push!(eqs, lhs ~ Symbolics.wrap(_field_term(rate, cv)))
    end
    # every group computes the aux fields from the values it reads (F2 design §2.11)
    for (x, rhs) in aux
        push!(eqs, Symbolics.wrap(states[info(x).name]) ~ Symbolics.wrap(_field_term(rhs, cv)))
    end
    core = core_lattice(lat)
    ext = ntuple(d -> lat.dims[d] * Float64(h[d]), N)
    at_face(n, d, v) = (args = Any[ivs...]; args[d + 1] = v; operation(states[n])(args...))
    bcs = Equation[]
    for n in names, d in 1:N
        core.periodic[d] && push!(bcs, Symbolics.wrap(at_face(n, d, 0.0)) ~ Symbolics.wrap(at_face(n, d, ext[d])))
    end
    for b in _p(sys, :boundaries)
        n = info(b.field).name
        n in names || continue
        if b.axis == 0
            push!(bcs, Symbolics.wrap(states[n]) ~ LatticePDE.masked(Symbolics.wrap(_field_term(b.mask, cv)),
                Symbolics.wrap(_field_term(b.value, cv))))
        else
            for (side, s) in zip((0.0, ext[b.axis]), b.sides)
                s isa Dirichlet || continue
                push!(bcs, Symbolics.wrap(at_face(n, b.axis, side)) ~ Symbolics.wrap(_field_term(s.value, cv)))
            end
        end
    end
    _has_domain(lat) && _filled_input!(cv, _DOMAIN_FILL, :domain__in, Bool)
    dvs = Any[[states[n] for n in [names; auxnames]]; [cv.direct[k] for k in sort!(collect(keys(cv.direct)))];
              [cv.inputs[e[1]] for e in cv.filled if haskey(cv.inputs, e[1])]]
    ps = sort!(collect(cv.params); by = string)
    _refuse_input_words(cv, names, ps)
    domain = [Symbolics.wrap(tt) ∈ LatticePDE.Interval(0.0, 1.0);
              [Symbolics.wrap(xs[d]) ∈ LatticePDE.Interval(0.0, ext[d]) for d in 1:N]]
    pdesys = ModelingToolkitBase.PDESystem(eqs, bcs, domain, ivs, dvs, ps; name = nameof(sys))
    return pdesys, cv
end

"""
The filled inputs of model `sys`: `(name, expr, eltype)`, the site arrays the CPM writes for
the fields every MCS (`T` is the state type).
"""
_field_inputs(sys::PottsSystem, T::Type = Float64) =
    isempty(_field_equations(sys)) ? Tuple{Symbol, Any, Type}[] :
    _canonical_filled(_field_system(sys; T, known = Tuple{Symbol, Any, Type}[])[2].filled)
# those of compiled model `c`, made once per state type (cached on `c`)
_field_inputs(c::CompiledPottsSystem, T::Type = Float64) =
    _field_cached(() -> _field_inputs(c.sys, T), c, (:inputs, T))

"""The masked fields of `sys` (each has a mask site array `name__mask`)."""
_masked_fields(sys::PottsSystem) = unique!(Symbol[info(b.field).name for b in _p(sys, :boundaries) if b.axis == 0])

# The lattice of the fields: a hexagonal lattice is a hexagonal grid (LatticePDE's six-neighbor
# `Δ`), and an irregular `domain` is the Bool input `domain__in` (written by the fill phase
# from the lattice's mask) with a zero-flux edge: as the old field path, a neighbor outside
# the domain or a closed face reads the site itself.
_has_domain(lat) = (m = core_lattice(lat).mask; m !== nothing && !all(m))
const _DOMAIN_FILL = :__domain__          # the fill expression of `domain__in`
_fill_value(ex, env) = ex === _DOMAIN_FILL ? :(CorePotts.in_domain(ctx.lattice, $(env.bind[:__site]))) : lower(ex, env)
function _field_disc(sys::PottsSystem, T)
    lat = _p(sys, :lattice)
    geometry = lat.geometry isa CorePotts.Hexagonal ? LatticeFields.IR.HEX : LatticeFields.IR.CUBIC
    # the clock is the MCS: `mcs` reads its step index (F2 design §2.6)
    return LatticePDE.LatticeDiscretization(LatticePDE.Grid(lat.dims; geometry); T,
        domain = _has_domain(lat) ? "domain__in" : nothing, clock = Float64(_p(sys, :sweep).mcs_duration))
end

# ---------------------------------------------------------------------------------------
# Field groups of a problem: one LatticeFields group (`GroupSpec`, `FieldGroup`) per solver group

"""
One stepped group: its fields, its `FieldGroup` (the `GroupSpec` from `LatticePDE.lower_group`,
the update of its algorithm fused by the IR pass, the plans), the algorithm, the semantic
program and the mask and step plans, the array bindings, the parameter and table bindings,
the substep rule, the fingerprint text and the compile options.
"""
struct _FieldGroup
    names::Vector{Symbol}
    group::Any
    alg::Any
    program::Any
    masks::Any
    step::Any
    arrays::Tuple
    tables::Vector{Pair{Int, Symbol}}
    params::Vector{Symbol}
    substeps::Any
    fingerprint::String
    options::Any
end

# The substep rule of a map group (F2 design §2.11): one application per field window (the
# MCS), whatever the parameters; a map has no stability bound
struct _MapSteps end
(::_MapSteps)(praw) = 1
# the least count and the bounded flag of a group's rule, as the fingerprint records them
_least(s) = s isa _MapSteps ? 1 : s.least
_bounded(s) = s isa _MapSteps || (isempty(s.bound.unbounded) && isempty(s.bound.expanded))

# the explicit Euler update of a substep, clipped below at `lower`, fused symbolically (the
# oracle of the update pass's byte-identity gate, test/fields_identity.jl)
struct _EulerUpdate
    lower::Union{Nothing, Float64}
end
function (u::_EulerUpdate)(kb, c, r)
    v = LatticePDE.euler_update(kb, c, r)
    return u.lower === nothing ? v : max(v, u.lower)
end

# The cache of the lowered field groups of a compiled model (`CompiledPottsSystem.field_specs`):
# `mtkcompile` lowers the group of all fields once, in Float64, and a `PottsProblem` whose
# partition and state type match reuses it (F2 design §2.5)
const _FIELD_SPEC_LOCK = ReentrantLock()
_field_cached(f, c::CompiledPottsSystem, key) = lock(() -> get!(f, c.field_specs, key), _FIELD_SPEC_LOCK)

# the number of `lower_group` calls of this session (a test counts them)
const _LOWER_GROUP_CALLS = Threads.Atomic{Int}(0)

"""
    _lower_field_group(sys, names, T; known) -> NamedTuple

The field group of the fields `names` of model `sys` in state type `T`, lowered once by
`LatticePDE.lower_group` to its `GroupSpec` (`spec`), with what front end A binds: the
parameter names of its slots (`params`), its tables by id (`tables`) and the generated inputs
(`filled`, to print a term in the model's words). The fields of other groups are inputs of
the group, read from their arrays (`_field_system`).
"""
function _lower_field_group(sys::PottsSystem, names::Vector{Symbol}, T::Type; known, bound::Bool = true)
    pdesys, cv = _field_system(sys, names; T, known)
    # rates and maps in one model are refused on both front ends (F1's message, with A's route)
    LatticePDE.check_one_kind(pdesys; route = "write each map as a site update that runs once per MCS (a site " *
                                               "variable `m(site)` with `@after_mcs m ~ rhs`)")
    Threads.atomic_add!(_LOWER_GROUP_CALLS, 1)
    spec = LatticePDE.lower_group(pdesys, _field_disc(sys, T); values = false, bound)
    # the model's parameter of each slot and table (the spec names them as the PDESystem prints
    # them); the clock's slot keeps its reserved name (the phase writes the MCS number there)
    pname(k) = k == LatticeFields.Problems.CLOCK_KEY ? Symbol(k) : info(only(q for q in getfield(pdesys, :ps) if string(q) == k)).name
    params = Symbol[pname(k) for k in spec.params]
    tables = Pair{Int, Symbol}[i => pname(tb.key) for (i, tb) in enumerate(spec.rate.tables)]
    return (; spec, params, tables, filled = copy(cv.filled), pdesys)
end
# cached on compiled model `c` by partition and state type; `mtkcompile`'s entry has its
# stability bound deferred (`LatticePDE.resolve_bound`), built here once, at the first problem
function _field_group_spec(c::CompiledPottsSystem, names::Vector{Symbol}, T::Type)
    return lock(_FIELD_SPEC_LOCK) do
        g = get!(() -> _lower_field_group(c.sys, names, T; known = _field_inputs(c, T)), c.field_specs, (names, T))
        g.spec.stability isa LatticePDE.DeferredBound || return g
        c.field_specs[(names, T)] = (; g..., spec = LatticePDE.resolve_bound(g.spec))
    end
end

"""
The substep count of a group at raw parameters `praw`: the smallest `n` with
`dt/n · ρ(p) ≤ 1.8` (`ρ` the Gershgorin bound of the rate Jacobian, LatticePDE's
`stability_bound`), and at least the requested `substeps` (D-C8 item 1).

With an explicit count, a term the bound cannot see (a nonlinear reaction) or a
coupled row that is not diagonally dominant does not lower the count: `n` is the largest of
the request and the bound over the terms it sees (diffusion at least, also inside an
`ifelse` gate whose condition reads no field, bounded arm by arm); the problem warns
at build (`_check_substeps`), once per group program and session. With no count, neither has a bound and the problem
throws (unseen terms at build in `_field_groups`, coupled rows here, at build and at every
parameter change). A negative diffusion coefficient (anti-diffusion: unstable at any step)
is refused. A coefficient that is not finite at a kind table entry it reads (`1 / τ[kind]`
with a zero entry, the medium's included) is refused with or without a count, naming the
entry. Past the bound's evaluation cap (more than 4096 kind table index combinations), a
group with no count is refused; an explicit count is raised by the bound over every term the
bound sees (`seen`: diffusion, the other terms and fields), and a warning names the terms past
the cap: the count is the user's for them.

A warning is given once per group, term and cause in a session (the group's fingerprint
text, the terms and the cause; never a value).
"""
struct _Substeps{B}
    bound::B
    dt::Float64
    least::Int
    explicit::Bool
    names::Vector{Symbol}
    key::String                    # the group's fingerprint text (the warning's once-key)
    unseen::Vector{String}         # the terms the bound cannot see, in the model's words
    cv::NamedTuple                 # the generated inputs (`filled`), to print a term in the model's words
    coupling::Any                  # with several groups: the whole field system's bound and the partition
end
_fieldlist(ks) = join(("`$k`" for k in ks), ", ")
function (s::_Substeps)(praw)
    n = _substep_count(s, praw)
    s.coupling === nothing || _check_group_coupling(s, praw)
    return n
end

# The coupling of a group to the other field groups (review of F2-06, ruling K-unsafe; round
# 2: loops only; the criterion and its reasoning are LatticeFields' `_check_coupling`): a group
# reads the fields of the others from their arrays, held over its window `dt` (the MCS, or its
# part in a `repeat`). A group in no loop of the group read graph (`group_loops`: a one-way
# chain) is not checked: the split system is block triangular. A group in a loop needs
# `κ = dt · max over the group's rows of Σ max|cross coefficient|` over the terms that read
# other groups' fields ≤ 1, at any substep count; a coefficient with no finite bound is refused
# with an automatic count and warns (once) with an explicit one. κ sums only the reads of groups
# in the same loop. A group with a term the bound cannot see that reads another field counts as
# reading every other group (a term on its own field alone couples nothing). The bound is the whole field system's
# (`coupling.bound`), at the parameters of the group mapped by name (a parameter the group does
# not read is `NaN`: no cross coefficient of its rows reads it; the read graph is the
# structure, so it needs no value).
function _check_group_coupling(s::_Substeps, praw)
    c = s.coupling
    pv = praw isa LatticeFields.Problems.ParamsTables ? praw.p : praw
    tabs = praw isa LatticeFields.Problems.ParamsTables ? praw.tables : Pair{String, Vector{Float64}}[]
    wp = Float64[(j = findfirst(==(n), c.pnames)) === nothing ? NaN : Float64(pv[j]) for n in c.wnames]
    pp = LatticeFields.Problems.with_tables(wp, tabs)
    parts = LatticeFields.Problems.lagged_coupling(c.bound, c.groups, pp)
    loops = LatticeFields.Problems.group_loops(parts)
    loop = loops[c.index]
    isempty(loop) && return nothing
    # only the reads inside the loop (a group outside it cannot feed growth back; round 3)
    parts = LatticeFields.Problems.lagged_coupling(c.bound, c.groups, pp; within = loops)
    q = parts[c.index]
    κ = s.dt * q.rate
    u(k) = string("`", k, "`")
    lf = reduce(vcat, c.groups[loop])                   # the fields of the loop
    if !isfinite(κ)
        s.explicit || throw(ArgumentError(string("the field", length(s.names) == 1 ? " " : "s ", _fieldlist(s.names),
            " read", length(s.names) == 1 ? "s " : " ", u(q.other), " of another solver group, in a loop of groups that ",
            "read one another (", _fieldlist(lf), "), and the coefficient `", _user_text(q.raw, s.cv), "` of that read ",
            "has no bound at these parameters; give ", _fieldlist(lf), " one solver (one group), or give `solvers` an ",
            "explicit `ExplicitEuler(; substeps = n)` for the group")))
        k = string(s.key, "#coupling#", q.row, "#", q.raw)
        if ccall(:jl_generating_output, Cint, ()) == 0 &&
           lock(() -> k in _SUBSTEP_WARNED ? false : (push!(_SUBSTEP_WARNED, k); true), _SUBSTEP_WARNED_LOCK)
            @warn "field$(length(s.names) == 1 ? "" : "s") $(_fieldlist(s.names)): the coupling to $(u(q.other)) of " *
                  "another solver group, in the loop of $(_fieldlist(lf)), has no bound (the coefficient " *
                  "`$(_user_text(q.raw, s.cv))`): the count is the user's"
        end
    elseif κ > 1 + 1e-12
        unseen = [k for h in loop if parts[h].unseen for k in c.groups[h]]
        # one solver for the loop: an automatic count needs dominant rows (a parameter of
        # another group has no value here: then the explicit route, which always holds)
        ρ = Float64(LatticeFields.Problems.restrict_bound(c.bound, lf)(pp))
        one = isfinite(ρ) && ρ >= 0 ? string("Give ", _fieldlist(lf), " one solver (one group; `solvers`)") :
              string("Give ", _fieldlist(lf), " one solver with an explicit count (one group, `ExplicitEuler(; ",
                     "substeps = n)`; their coupled rows have no automatic count)")
        throw(ArgumentError(string("the fields ", _fieldlist(lf), " are in solver groups that read one another in a ",
            "loop, each holding the others' values over each field window (", s.dt, " MCS): the terms of ", u(q.row),
            " that read other groups of the loop (the largest: the coefficient `", _user_text(q.raw, s.cv), "` of ", u(q.other),
            ") give window · Σ max|coefficient| = ", round(κ; sigdigits = 4), " > 1, and the loop can then grow ",
            "without bound at any substep count",
            isempty(unseen) ? "" : string(" (the terms of ", _fieldlist(unseen), " that the stability bound cannot ",
                                          "see and that read another field count as reading every other group)"),
            ". ", one, ", or step the fields over a shorter window (`repeat(n, …)` of the fields, or a smaller ",
            "`mcs_duration`; window ≤ ", floor(1 / q.rate; sigdigits = 4), ")")))
    end
    return nothing
end

function _substep_count(s::_Substeps, praw)
    r = LatticePDE.bound_parts(s.bound, praw)
    isempty(r.negative) || throw(ArgumentError(
        "the diffusion coefficient of the field$(length(r.negative) == 1 ? "" : "s") $(_fieldlist(r.negative)) " *
        "is negative at the current parameters (anti-diffusion: an ill-posed equation, unstable at any step and " *
        "with any solver); write the term with a coefficient ≥ 0 (`D * Δ(c)` with `D ≥ 0`; a decay is a reaction " *
        "term `-k * c`), or give the parameters values that make it ≥ 0"))
    if !s.explicit && !isempty(r.coupled)
        throw(ArgumentError(
            "the substep count of the field$(length(s.names) == 1 ? "" : "s") $(_fieldlist(s.names)) has no bound " *
            "from the parameters: the coupled rate$(length(r.coupled) == 1 ? "" : "s") of $(_fieldlist(r.coupled)) " *
            "(terms that read another field) $(length(r.coupled) == 1 ? "is" : "are") not diagonally dominant; give " *
            "`PottsProblem` `field_solver = ExplicitEuler(; substeps = n)` with `n ≥ mcs_duration · ρ / 1.8`"))
    end
    if !isfinite(r.ρ)
        # over the evaluation cap only: an explicit count is raised by the bound over every
        # term with a bound (`r.seen`: diffusion, the other terms and fields), and a warning
        # (once per group and session) names the terms it does not cover; a value that is not
        # finite at an entry the field reads is refused
        if s.explicit && !isempty(r.nonfinite) && all(x -> x[3] === :cap, r.nonfinite)
            n = isfinite(r.seen) ? max(s.least, ceil(Int, s.dt * r.seen / 1.8)) : s.least
            # once per group, term and cause (`:cap`) in a session: the key holds no value
            k = string(s.key, "#cap#", join(sort!([text for (_, text, _) in r.nonfinite]), "#"))
            if ccall(:jl_generating_output, Cint, ()) == 0 &&
               lock(() -> k in _SUBSTEP_WARNED ? false : (push!(_SUBSTEP_WARNED, k); true), _SUBSTEP_WARNED_LOCK)
                @warn "field$(length(s.names) == 1 ? "" : "s") $(_fieldlist(s.names)): $n substeps per field step " *
                      "(the requested $(s.least), or more for the terms the bound sees); the stability bound does not " *
                      "cover " * join((_nonfinite_text(text, w, s.cv; warning = true) for (_, text, w) in r.nonfinite), ", ") *
                      ": the count is the user's"
            end
            return n
        end
        throw(ArgumentError(string("the substep bound of the field$(length(s.names) == 1 ? "" : "s") ",
            _fieldlist(s.names), " is not finite at the current parameters: ",
            isempty(r.nonfinite) ? "a coefficient is not finite" :
            join((_nonfinite_text(text, w, s.cv) for (_, text, w) in r.nonfinite), "; "))))
    end
    return max(s.least, ceil(Int, s.dt * r.ρ / 1.8))
end

# why a coefficient has no finite bound, in the model's words: a kind table entry `e` is
# kind `e - 1` (entry 1 is the medium's), with the route
function _nonfinite_text(text, w, cv; warning::Bool = false)
    # a kind table read `at(τ, 1 + kind)` as the model writes it, `τ[kind]`
    u = replace(_user_text(text, cv), r"at\((\w+), (?:1 \+ kind|kind \+ 1)\)" => s"\1[kind]")
    t = "`" * u * "`"
    # past the cap: the error gives the route (a count), the warning (a count was given) none
    w === :cap && warning && return string(t, " (it reads more than 4096 kind table index combinations)")
    w === :cap && return string(t, " (it reads more than 4096 kind table index combinations; with no count, give ",
        "`PottsProblem` `field_solver = ExplicitEuler(; substeps = n)` with `n ≥ mcs_duration · ρ / 1.8`)")
    w isa Tuple || return string(t, " is not finite at the current parameters")
    combos, more = w
    all(isempty, combos) && return string(t, " is not finite; give its parameters values that make it finite")
    ent(tb, i) = i == 0 ? "index 0 of `$tb` (which reads 0)" :
                 i == 1 ? "the medium's entry of `$tb` (kind 0)" : "the entry of kind $(i - 1) of `$tb`"
    # the route by cause: a zero under a division, a negative value under `sqrt` or `log`
    fix(v) = v == 0 ? "make it nonzero (a zero entry: a division by it is not finite)" :
             v < 0 ? "make it ≥ 0 (a negative entry under `sqrt` or `log` is not finite)" :
             "give it a value where the coefficient is finite"
    rd = unique(reduce(vcat, combos))
    return string(t, " is not finite at ", join((join((ent(tb, i) for (tb, i, _) in c), " with ") for c in combos), ", at "),
        more > 0 ? " (and $more more)" : "", "; ",
        join(("$(ent(tb, i)) is $v: $(fix(v))" for (tb, i, v) in rd if i != 0), "; "),
        " (every kind's entry is read, the medium's too)")
end

# At build: the count at the problem's parameters (throws as above), and one warning when an
# explicit count is kept against terms the bound cannot see or coupled rows
const _SUBSTEP_WARNED = Set{String}()
const _SUBSTEP_WARNED_LOCK = ReentrantLock()
function _check_substeps(s::_Substeps, praw, key::AbstractString)
    n = s(praw)
    # once per group, term and cause in a session (`key`, the group's fingerprint text, with
    # the unseen terms and the coupled rows; no value), and not while precompiling (a
    # package's workload)
    s.explicit && ccall(:jl_generating_output, Cint, ()) == 0 || return n
    r = LatticePDE.bound_parts(s.bound, praw)
    unseen = s.unseen
    k = string(key, "#unseen#", join(sort(unseen), "#"), "#coupled#", join(sort(r.coupled), "#"))
    if lock(() -> k in _SUBSTEP_WARNED ? false : (push!(_SUBSTEP_WARNED, k); true), _SUBSTEP_WARNED_LOCK)
        if !isempty(unseen) || !isempty(r.coupled)
            @warn "field$(length(s.names) == 1 ? "" : "s") $(_fieldlist(s.names)): $n substeps per field step " *
                  "(the requested $(s.least), or more for the terms the bound sees); the stability bound does not " *
                  "cover " * join([("`" * t * "`" for t in unseen)...;
                                   (isempty(r.coupled) ? String[] : ["the coupled rates of $(_fieldlist(r.coupled))"])],
                                  ", ") * ": the count is the user's"
        end
    end
    return n
end

# A term of the field system in the model's words (F1, PO06): a generated input
# (`kind__in(t, x, y)`, `field1__in(…)`) prints as the CPM read it holds, a field read
# `c(t, x, y)` as `c`; the key's `"c: "` prefix is dropped
function _user_text(term::AbstractString, cv)
    out = replace(term, r"^[^:]+: " => "")
    for (name, ex, _) in cv.filled
        user = _input_word(name, ex)
        out = replace(out, Regex(string(name) * raw"\(t(, [xyz])*\)") => user)
    end
    out = replace(out, r"Potts\._intdiv\(([^,()]+), ([^()]+)\)" => s"(\1 ÷ \2)")   # the model's `÷`
    out = LatticePDE.as_written(replace(out, "LatticePDE." => ""))    # `Δ(c)`, `at(δ, …)`, `[ux, uy]` as written
    out = replace(out, r"\bstep_index\(t\)" => "mcs", r"\bclock__tick\b" => "mcs")   # the clock's step index
    out = replace(out, r"(\w+)\(t(, [xyz])*\)" => s"\1")
    # a kind table read `at(δ, 1 + kind)` as the model writes it, `δ[kind]`; the time `t` is `time`
    out = replace(out, r"at\((\w+), (?:1 \+ kind|kind \+ 1)\)" => s"\1[kind]")
    out = replace(out, r"at\((\w+), (\w+)\)" => s"\1[\2]")             # a CPM read `volume[owner]`
    return replace(out, r"\bt\b" => "time")
end

# The model time of one field phase: the MCS, or `1/n` of it inside a sub-MCS `repeat(n, …)`
function _field_dt(sys::PottsSystem)
    r = _schedule_repeat(_p(sys, :schedule))
    return Float64(_p(sys, :sweep).mcs_duration) / (r !== nothing && :fields in r.names ? r.n : 1)
end

"""
    _field_groups(c, T, spec) -> Vector{_FieldGroup}

The field groups of compiled model `c` for state type `T` and solvers `spec`: fields with
equal solvers (canonical form) form one group, in order of first appearance; inside a group
the plan orders the fields topologically by what they read (strongly connected fields step
together, Jacobi; v3 §6.1). A field of another group is read from its own array. Each group
is lowered once by `LatticePDE.lower_group` (cached on `c`: the group of all fields comes from
`mtkcompile`), and its algorithm's update is fused by the IR pass (`fuse_update`).
"""
function _field_groups(c::CompiledPottsSystem, T::Type, spec::SolverSpec)
    sys = c.sys
    order = Tuple{String, Any, Vector{Symbol}}[]
    for (x, _) in c.fields
        n = info(x).name
        s = spec.resolved[n]
        k = _canonical(s)
        j = findfirst(g -> g[1] == k, order)
        j === nothing ? push!(order, (k, s, Symbol[n])) : push!(order[j][3], n)
    end
    dt = _field_dt(sys)
    groups = _FieldGroup[]
    allnames = Symbol[info(x).name for (x, _) in _field_equations(sys)]
    # with several groups, the coupling between them (`_check_group_coupling`): the bound of
    # the whole field system (the group of all fields, in rate form), and the partition
    coupling = nothing
    if length(order) > 1
        whole = _field_group_spec(c, allnames, T)
        coupling = (; bound = whole.spec.stability, groups = [String[string(n) for n in g[3]] for g in order],
            wnames = whole.params)
    end
    # Cartesian indexing: the host loop hands each site its coordinates (a linear launch
    # decodes them with an integer division per site, about 3x slower on the CPU; PG-3)
    opts = LatticeFields.Compile.CompileOptions(; T, float64_ok = !(T <: Union{Float16, Float32}), lanes = :state,
        index = :cartesian)
    for (gi, (_, solver, names)) in enumerate(order)
        lg = _field_group_spec(c, names, T)
        gspec = lg.spec
        fused = LatticeFields.Compile.fuse_update(gspec.rate, LatticeFields.Problems.update_rule(solver))
        group = LatticeFields.Problems.FieldGroup(gspec; alg = solver, program = LatticeFields.Compile.semantic(fused))
        prog = group.program
        mplan, splan = LatticeFields.Problems.group_plans(group, solver, T, KernelAbstractions.CPU(), opts)
        arrays = Tuple(begin
                           k = f.key
                           if startswith(k, "mask:")
                               (CorePotts.Part((:site, Symbol(k[6:end], :__mask))), nothing)
                           elseif Symbol(k) in names
                               (CorePotts.Part((:site, Symbol(k))), CorePotts.Part((:site, Symbol(k, :__next))))
                           else
                               (CorePotts.Part((:site, Symbol(k))), nothing)
                           end
                       end for f in prog.fields)
        cv = (; filled = lg.filled)
        stab = gspec.stability
        if gspec.kind === :map
            # a map steps once per window: no substep count, no bound
            fp = LatticeFields.Compile.fingerprint_text(fused; T)
            push!(groups, _FieldGroup(names, group, solver, prog, mplan, splan, arrays, lg.tables, lg.params, _MapSteps(),
                fp, opts))
            continue
        end
        least = something(solver.substeps, 1)
        if !isempty(stab.unbounded) && solver.substeps === nothing
            throw(ArgumentError("the substep count of the field$(length(names) == 1 ? "" : "s") " *
                                "$(_fieldlist(names)) has no bound from the parameters (the term" *
                                "$(length(stab.terms) == 1 ? "" : "s") $(join(("`$(_user_text(t, cv))`" for t in stab.terms), ", ")), " *
                                "which the stability bound cannot see: a nonlinear or advection term, a diffusion multiplier " *
                                "that varies by site through a CPM value read directly (`volume[owner] * Δ(c)`; a kind table " *
                                "`δ[kind] * Δ(c)` or a kind set `ismember(kind, g) * Δ(c)` is bounded), or a coefficient " *
                                "that reads the state or `mcs`); give `PottsProblem` " *
                                "`field_solver = ExplicitEuler(; substeps = n)` with `n ≥ mcs_duration · ρ / 1.8`"))
        end
        fp = LatticeFields.Compile.fingerprint_text(fused; T)
        push!(groups, _FieldGroup(names, group, solver, prog, mplan, splan, arrays, lg.tables, lg.params,
            _Substeps(stab, dt, least, solver.substeps !== nothing, names, fp, String[_user_text(t, cv) for t in stab.terms],
                (; filled = copy(cv.filled)),
                coupling === nothing ? nothing : (; coupling..., index = gi, pnames = lg.params)), fp, opts))
    end
    return groups
end

# The site phase writing every filled input of the fields (one launch per MCS)
function _field_fill_phase(c::CompiledPottsSystem, T)
    filled = _field_inputs(c, T)
    isempty(filled) && return nothing
    env = _site_env(T, :i, c.gather_names; mcs = :mcs, key = :key)
    body = map(filled) do (name, ex, E)
        v = _fill_value(ex, env)
        E === Bool ? :(@inbounds st.site.$name[i] = UInt8($v)) : :(@inbounds st.site.$name[i] = $E($v))
    end
    return CorePotts.SitePhase(_rgf(:((st, p, ctx, key, mcs, i) -> begin
        $(body...)
        return nothing
    end)))
end

# the field phases of a problem (in group order) and their at-init clamps
function _field_phases(c::CompiledPottsSystem, T, spec::SolverSpec)
    isempty(c.fields) && return Any[], Any[]
    groups = _field_groups(c, T, spec)
    dt = _field_dt(c.sys)
    steps, clamps = Any[], Any[]
    fill = _field_fill_phase(c, T)
    fill === nothing || push!(steps, fill)
    log = _GENERATED[]
    for (j, g) in enumerate(groups)
        # the fingerprint hashes the semantic program of each group with its bindings (D-016)
        # (the last entry: no term outside the linearity classes, `ifelse` arms not expanded)
        log === nothing || push!(log, Expr(:field_program, g.fingerprint, string(g.arrays), string(g.params),
            string(g.tables), _canonical_value(_least(g.substeps)), string(_bounded(g.substeps))))
        ph = CorePotts.FieldPhase{Symbol(:__fields, j)}(g.group, g.alg, g.arrays; g.tables, g.params,
            substeps = g.substeps, dt, period = Float64(_p(c.sys, :sweep).mcs_duration), g.options, T)
        push!(steps, ph)
        isempty(g.masks.launches) || push!(clamps, CorePotts.field_clamp(ph))
    end
    return steps, (fill === nothing ? clamps : Any[fill; clamps])
end

# At build: each field phase's substep count at the problem's parameters (`_check_substeps`:
# the refusals, and the warning for an explicit count the bound does not cover)
function _check_field_substeps(f, p)
    for e in f.phases.mcs, t in (e isa CorePotts.Repeat ? e.entries : (e,))
        t isa Tuple || continue
        for ph in t
            ph isa CorePotts.FieldPhase && !ph.init && ph.substeps isa _Substeps || continue
            tabs = Pair{String, Vector{Float64}}[ph.program.tables[i].key => Float64.(vec(collect(getproperty(p, name))))
                                                 for (i, name) in ph.tables]
            praw = LatticeFields.Problems.with_tables(Float64[CorePotts._praw(ph, p)...], tabs)
            _check_substeps(ph.substeps, praw, ph.substeps.key)
        end
    end
    return nothing
end
