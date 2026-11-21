# Fields. A model's field equations `D(c) ~ rate` and their
# conditions, from its coupled PDESystems (`@fields`, `Potts.couple`, `compose`), are a
# ModelingToolkitBase `PDESystem` (`Potts.fields(csys)`) over
# the lattice's coordinates; LatticePDE discretizes it into a LatticeFields program and
# `CorePotts.FieldPhase` runs the program's step plan inside the MCS.
#
# The CPM enters a field equation through inputs: dependent variables `[input = true]` of
# the PDESystem, bound to site arrays of the state.
#   - a field or site variable that the group does not step is read from its own array;
#   - the site's kind (`kind`) is the input `kind__in(t, x, …)::Int32`;
#   - any other term that reads the CPM and no field (an owner's cell variable, `position`,
#     a helper over the neighbourhood, …) is one input `fieldₖ__in`, the term's value at
#     each site, written by one site phase before the field step every MCS.
# The clock: the discretization's clock is `mcs_duration`. `mcs` is its step
# index, `LatticePDE.step_index(t)` (the reserved slot `clock__tick`, the MCS number at
# every substep), and `time` is the PDESystem's time `t`: the CPM's time at the start of the
# field window, advancing by `h` per substep.

# the spatial independent variables, one per lattice axis
const _FIELD_X = Tuple(
    Symbolics.unwrap(only(ModelingToolkitBase.@parameters $n))
        for n in (:x, :y, :z)
)
# the lattice coordinates `x`, `y`, `z`, the spatial variables of the fields'
# PDESystem: a model body binds them (an `@fields` binding may read them), and
# `Potts.Fields` exports them. A model that declares a quantity of one of these names keeps
# its own.
const FIELD_NAMES = (;
    x = Symbolics.wrap(_FIELD_X[1]),
    y = Symbolics.wrap(_FIELD_X[2]), z = Symbolics.wrap(_FIELD_X[3]),
)
_coordinate(u) = any(v -> v === u || isequal(v, u), _FIELD_X)

# A field read at a face in a condition, `c(t, 0, y)`: a coupled PDESystem's
# face read of a field goes through `_bcs_call` (`_pde_read`), which builds the read when
# the callee is a field variable (a call of a callable symbol named as the field, tagged
# `_FieldAt`, printed as written) and calls the callee otherwise
struct _FieldAt end
function _bcs_call(f, args...)
    u = _unwrap(f)
    i = u isa SymbolicUtils.BasicSymbolic ? info(u) : nothing
    (i !== nothing && i.role === :field) || return f(args...)
    g = SymbolicUtils.setmetadata(
        Symbolics.unwrap(
            Symbolics.variable(
                i.name; T = SymbolicUtils.FnType{
                    Tuple, Real, Nothing,
                }
            )
        ),
        _FieldAt, true
    )
    return Symbolics.wrap(g(map(_unwrap, args)...))
end
function _is_field_at(f)
    return f isa SymbolicUtils.BasicSymbolic && SymbolicUtils.hasmetadata(f, _FieldAt)
end
_field_at_name(u) = Symbol(nameof(operation(u)))

# a callable dependent variable `name(..)` of element type `E`, applied to the ivs
function _field_var(
        name::Symbol, ::Type{E}, ivs; input::Bool = false, entity = nothing,
        storage = nothing,
        username = nothing, bounds = nothing, level = nothing
    ) where {E}
    f = Symbolics.unwrap(
        Symbolics.variable(
            name; T = SymbolicUtils.FnType{
                Tuple, E, Nothing,
            }
        )
    )
    v = f(ivs...)
    bounds === nothing ||
        (v = SymbolicUtils.setmetadata(v, ModelingToolkitBase.VariableBounds, bounds))
    input && (v = SymbolicUtils.setmetadata(v, ModelingToolkitBase.VariableInput, true))
    username === nothing ||
        (v = SymbolicUtils.setmetadata(v, LatticePDE.LatticeInputName, username))
    entity === nothing || (v = SymbolicUtils.setmetadata(v, PottsEntity, entity))
    S = if storage === nothing && entity isa Entity
        get(entity.options, :lattice_storage, nothing)
    else
        storage
    end
    S === nothing || (v = SymbolicUtils.setmetadata(v, LatticePDE.LatticeStorage, S))
    # `[lattice_level = Coarse(k)]`: the field's grid
    L = if level === nothing && entity isa Entity
        get(entity.options, :lattice_level, nothing)
    else
        level
    end
    L === nothing || (v = SymbolicUtils.setmetadata(v, LatticePDE.LatticeLevel, L))
    return v
end
# the variable info of field `name` of `sys`
function _field_info(sys, name)
    return info(
        only(
            x
                for x in _p(sys, :variables) if info(x) !== nothing && info(x).name === name
        )
    )
end
# the `lattice_level` of field `name` of `sys` (`nothing`: the lattice itself)
function _field_level(sys, name)
    x = only(x for x in _p(sys, :variables) if info(x) !== nothing && info(x).name === name)
    return get(info(x).options, :lattice_level, nothing)
end
# the dims of a site array of variable info `i` on lattice dims `dims` (a coarse field's:
# its grid)
function _site_dims(i, dims)
    L = get(i.options, :lattice_level, nothing)
    return L === nothing ? dims : map(n -> n == 1 ? 1 : n ÷ L.k, dims)
end
# the `lattice_storage` of field `name` of `sys` (`nothing`: the state type)
function _field_storage(sys, name)
    x = only(x for x in _p(sys, :variables) if info(x) !== nothing && info(x).name === name)
    return get(info(x).options, :lattice_storage, nothing)
end
# the declared `bounds` of field `name` of `sys` (`nothing`: none), MTK's bounds metadata
# of the PDESystem's field, which the stability bound reads
function _field_bounds(sys, name)
    x = only(x for x in _p(sys, :variables) if info(x) !== nothing && info(x).name === name)
    return get(info(x).options, :bounds, nothing)
end

# the calls the lattice compiler lowers: LatticePDE's one allowlist, so a
# call lowers in `@equations` exactly when it lowers in a PDESystem
_field_op(f) = LatticePDE.lowers_call(f)
# LatticePDE's spatial operators, passed through to the PDESystem
function _spatial_op(f)
    return f === laplacian || f isa LatticePDE.DivKGrad || f isa LatticePDE.Advect ||
        f isa Differential
end
# whether `rate` applies a spatial operator to the field `n` (`laplacian`, `DivKGrad`,
# `Advect`, a raw flux `Differential(x)(K * Differential(x)(c))`): the operators whose ghost
# values a face condition sets
function _has_spatial_op(rate, n::Symbol)
    found = Ref(false)
    _walk_all(rate) do y
        iscall(y) && _spatial_op(operation(y)) || return
        o = _unwrap(arguments(y)[end])
        info(o) !== nothing && info(o).name === n && (found[] = true)
    end
    return found[]
end

function _is_field_name(sys, n)
    return any(
        x -> (i = info(x); i !== nothing && i.name === n && i.role in (:field, :site)),
        _p(sys, :variables)
    )
end

# Whether `u` reads a field or site variable (anywhere inside)
function _reads_site_vars(u)
    hit = Ref(false)
    _walk_all(
        y -> (
            i = info(y); i !== nothing && i.role in (:field, :site) && (hit[] = true)
        ), u
    )
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
            return get!(
                () -> _field_var(
                    i.name, Real, cv.ivs; input = true, entity = i,
                    bounds = get(i.options, :bounds, nothing)
                ), cv.direct, i.name
            )
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
    _is_field_at(f) && return _field_at_term(u, cv)
    if f === LatticePDE.masked                   # a masked condition
        return _unwrap(
            LatticePDE.masked(
                Symbolics.wrap(_field_term(a[1], cv)), Symbolics.wrap(_field_term(a[2], cv))
            )
        )
    elseif _spatial_op(f)
        # the operand of a spatial operator is a field (its last argument; `DivKGrad(K, c)`,
        # `Advect(u, c)`); the coefficient and the velocity are any lowered term
        _check_operand(u, f, a[end], cv)
        f isa Differential && _check_axis(u, f, cv)
        # a velocity written as a vector (`Advect(Upwind1())([ux, uy], c)`, a vector
        # quantity) converts per component
        function conv(y)
            v = LatticePDE.velocity_terms(_unwrap(y))
            return if v === nothing
                Symbolics.wrap(_field_term(y, cv))
            else
                [Symbolics.wrap(_field_term(z, cv)) for z in v]
            end
        end
        return _unwrap(f(map(conv, a)...))
    elseif f === ismember
        return _unwrap(
            ismember(
                Symbolics.wrap(_field_term(a[1], cv)),
                SymbolicUtils.unwrap_const(a[2])
            )
        )
    elseif f === value_at && info(a[1]) !== nothing && info(a[1]).role === :kindtable &&
            length(a) == 2
        # Potts kind tables include the medium at entry 1 (kind 0); the lattice table is
        # 1-based
        push!(cv.params, _unwrap(a[1]))
        return _unwrap(
            value_at(
                Symbolics.wrap(_unwrap(a[1])), Symbolics.wrap(_field_term(a[2], cv)) +
                    1
            )
        )
    elseif _field_op(f)
        # an `ifelse` of CPM reads only (no field) that needs a filled input is filled
        # whole: the fill then evaluates only the taken branch (a neighbor fold under a kind
        # test runs on the sites of that kind only, as the CPM code does)
        f === ifelse && !_reads_fieldvar(u) && _has_cpm_fill(u) &&
            return _filled_or_refuse(cv, u)
        if f === ifelse
            return _unwrap(ifelse(map(y -> Symbolics.wrap(_field_term(y, cv)), a)...))
        else
            return _unwrap(f(map(y -> Symbolics.wrap(_field_term(y, cv)), a)...))
        end
    elseif f isa ModelingToolkitBase.Shift
        # a map's own left side (`Shift(t, 1)(m) ~ rhs`); on a right side it has no meaning
        throw(
            PottsCompileError(
                "the term `$(_nopkg(_builtin_text(string(u))))` of a field equation " *
                    "reads `$(_nopkg(f))`: a `Shift` is the left side of a map, " *
                    "`Shift(t, 1)(m) ~ rhs` (the right side reads `m`, its value before \
                        the step)"
            )
        )
    end
    return _filled_or_refuse(cv, u)
end
# as the model writes it
_nopkg(x) = LatticePDE.as_written(replace(string(x), "LatticePDE." => ""))

# The operand of a spatial operator (`laplacian(c)`, `DivKGrad(K, c)`, `Advect(u, c)`, the
# inner end of a raw flux `Differential(x)(K * Differential(x)(c))`) is a field or site
# variable: an operator of a value the CPM writes once per MCS (a CPM read, `volume`, or a
# kind expression, `kind == A`: an input of the PDESystem bound to one is that value) is
# refused in the model's words, naming the operator and the route
function _check_operand(u, f, y, cv)
    v = _unwrap(y)
    # the outer end of a flux
    f isa Differential && iscall(v) && _has_operator(v, Differential) && return nothing
    (_has_cpm_fill(v) || _reads_kind(v)) && !_reads_fieldvar(v) || return nothing
    op = f isa Differential ? "Differential($(f.x))" : _nopkg(f)
    function text(x)
        s = _nopkg(_builtin_text(string(x)))
        return cv.kinds === nothing ? s : _bc_text(s, cv.kinds)
    end
    w = text(v)
    throw(
        PottsCompileError(
            "the term `$(text(u))` of a field equation applies `$op` to `$w`, a CPM " *
                "value (a value the CPM writes once per MCS, not a field; an input of " *
                "the PDESystem bound to `$w` is that value); a spatial operator applies " *
                "to a field or site variable: hold the value in a site variable " *
                "(`@variables v(site) = 0.0` and `@after_mcs v ~ $w` in the model), read \
                    it in the PDESystem as an input `v(..) [input = true]` left unbound \
                    (the CPM fills it by its name), and apply `$op` to it"
        )
    )
end
# whether `v` reads the site's kind
function _reads_kind(v)
    hit = Ref(false)
    _walk(
        y -> (
            i = info(y); i !== nothing && i.role === :builtin && i.name === :kind &&
                (hit[] = true)
        ), v
    )
    return hit[]
end

# A raw derivative `Differential(x)` differentiates along a lattice axis, a spatial variable
# of the PDESystem (`x`, `y`, `z`); any other variable (`z` on a 2D lattice) is refused. (A
# model quantity of the same name never reaches here: the PDESystem's `x` is its own
# variable.)
function _check_axis(u, f, cv)
    w = _unwrap(f.x)
    any(v -> isequal(v, w), cv.ivs[2:end]) && return nothing
    axes = join(("`$(string(v))`" for v in cv.ivs[2:end]), ", ")
    throw(
        PottsCompileError(
            "the term `$(_nopkg(_builtin_text(string(u))))` of a field equation " *
                "differentiates along `$(string(w))`, which is not a lattice axis; \
                    `Differential` takes an axis of the lattice: $axes"
        )
    )
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
    i === nothing || return !(
        i.role in (:field, :site, :param, :kindtable) ||
            (i.role === :builtin && i.name in (:mcs, :time, :kind))
    )
    _coordinate(u) && return false
    iscall(u) || return true
    f, a = operation(u), arguments(u)
    _is_field_at(f) && return false
    _spatial_op(f) && return any(_has_cpm_fill, a)
    f === SymbolicUtils.array_literal &&
        return any(_has_cpm_fill, something(LatticePDE.velocity_terms(u), a))
    f === ismember && return _has_cpm_fill(a[1])
    f === value_at && info(a[1]) !== nothing && info(a[1]).role === :kindtable &&
        length(a) == 2 && return _has_cpm_fill(a[2])
    return _field_op(f) ? any(_has_cpm_fill, a) : true
end

function _filled_or_refuse(cv, u)
    _has_op(u, random_uniform) && throw(
        PottsCompileError(
            "`rand()` in a field equation or condition: the field compiler steps fields " *
                "with no draws; draw in a site update (`@after_mcs s ~ rand()`) and bind \
                    the input to that variable"
        )
    )
    _reads_site_vars(u) && throw(
        PottsCompileError(
            "the term `$(_builtin_text(string(u)))` of a field equation reads a field or " *
                "site variable inside a CPM read (a gather, a cell read, …); the field " *
                "compiler lowers fields only through arithmetic, `laplacian`, `ismember`, \
                    `ifelse` and kind tables: compute the CPM part in a site update and \
                    read the variable"
        )
    )
    # the model-wide list (`known`) names each term once, so every group binds the same
    # array
    k = findfirst(e -> isequal(e[2], u), cv.filled)
    if k === nothing
        n = count(e -> e[1] !== :kind__in, cv.filled) + 1
        push!(cv.filled, (Symbol(:field, n, :__in), u, _filled_type(u, cv.T)))
        k = length(cv.filled)
    end
    return _filled_input!(cv, u, cv.filled[k][1], cv.filled[k][3])
end

# the number type of an input read as `E`: `Bool`, `Int32` for an integer, else `other`
function _input_number_type(E, other)
    E <: Bool && return Bool
    E <: Integer && return Int32
    return other
end
function _filled_input!(cv, u, name, E)
    any(e -> e[1] === name, cv.filled) || push!(cv.filled, (name, u, E))
    # a kind is never negative: a kind table read `value_at(δ, kind + 1)` never takes index
    # 0 (which reads 0), and the stability bound leaves it out
    return get!(
        () -> _field_var(
            name, _input_number_type(E, Real), cv.ivs; input = true,
            entity = Entity(:cpm_read, name, u, (;)), username = _input_word(name, u),
            bounds = name === :kind__in ? (0, Inf) : nothing
        ), cv.inputs, name
    )
end
# the user's word for a generated input: `kind`, `domain`, or the CPM read as written
# (`volume`)
function _input_word(name::Symbol, ex)
    if name === :kind__in
        return "kind"
    elseif name === :domain__in
        return "domain"
    else
        return _builtin_text(string(ex))
    end
end

# a generated input goes by its word (`domain`, `kind`, a CPM read as written), and the
# field compiler routes reads and writes by name: a field, site variable or parameter with
# the same name is refused here, in the model's words (LatticeIndex would name the generated
# input)
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
        src = if e[1] === :domain__in
            "the lattice's domain mask"
        elseif e[1] === :kind__in
            "the site's kind"
        else
            "the CPM read `$w`"
        end
        throw(
            PottsCompileError(
                "the field equations read `$w` ($src), and `$w` is also $what of the " *
                    "model; give the $(what[3:end]) another name"
            )
        )
    end
    return nothing
end

# The canonical order of the filled inputs (2026-10-20): `kind__in` first, then the CPM
# reads sorted by their expression text and numbered `field1__in`, `field2__in`, … in that
# order, then `domain__in`. The converter meets the reads in the hash order of a term's
# arguments (`*`, `+`), which changes with the package code; this order does not.
function _canonical_filled(raw)
    first_in = [e for e in raw if e[1] === :kind__in]
    last_in = [e for e in raw if e[1] === :domain__in]
    reads = sort!(
        [e for e in raw if !(e[1] in (:kind__in, :domain__in))];
        by = e -> string(e[2])
    )
    return Tuple{Symbol, Any, Type}[
        first_in;
        [
            (Symbol(:field, j, :__in), e[2], e[3])
                for (j, e) in enumerate(reads)
        ];
        last_in
    ]
end

function _field_conv(ivs, states, T, known, kinds = nothing)
    return (;
        ivs, states, direct = Dict{Symbol, Any}(), kinds,
        filled = Tuple{Symbol, Any, Type}[known...], inputs = Dict{Symbol, Any}(),
        params = Set{Any}(), T,
        bcsrc = Pair{Any, Any}[],
    )
end           # each translated condition => the condition as written

# The field equations of a model: `(x, kind, op)` for a rate `D(c) ~ rhs`
# (`:rate`) or a map `Shift(t, 1)(m) ~ rhs` (`:map`, one application per MCS) of a field or
# site variable, an aux definition `K ~ rhs` of a field variable (`:aux`, its value at every
# substep from the others), or a steady row `0 ~ rhs` (`:rate` with `op = :steady`, solved
# by `QuasiSteady` for the field its operator acts on); `op` is the left side's operator
# (`nothing` for aux); else `nothing`
function _field_lhs(eq, sys = nothing)
    l = _unwrap(eq.lhs)
    if _zero_lhs(eq)
        # (no field read: not a field equation)
        isempty(_steady_reads(eq).all) && return nothing
        # the field: the model's one rule with B (`LatticePDE.steady_choice`); with no
        # model at hand, the row is a field row (its field unknown here)
        sys === nothing && return (nothing, :rate, :steady)
        k = findfirst(p -> p[1] === eq || isequal(p[1], eq), _steady_assign(sys))
        return (_steady_assign(sys)[k][2], :rate, :steady)
    end
    if iscall(l) &&
            (operation(l) isa Differential || operation(l) isa ModelingToolkitBase.Shift)
        x = arguments(l)[1]
        i = info(x)
        (i !== nothing && i.role in (:field, :site)) || return nothing
        return (x, operation(l) isa Differential ? :rate : :map, operation(l))
    end
    l isa SymbolicUtils.BasicSymbolic || return nothing
    i = info(l)                                 # a field variable `K(t)` itself
    return i !== nothing && i.role === :field ? (l, :aux, nothing) : nothing
end
_zero_lhs(eq) = (v = SymbolicUtils.unwrap_const(_unwrap(eq.lhs)); v isa Number && iszero(v))
# The field variables a steady row reads (`all`), and those under a spatial operator (`ops`:
# `laplacian(c)`, the last argument of `DivKGrad` and `Advect`, a `Differential`)
function _steady_reads(eq)
    all, ops = Any[], Any[]
    function walk(u, under)
        u = _unwrap(u)
        i = u isa SymbolicUtils.BasicSymbolic ? info(u) : nothing
        if i !== nothing && i.role === :field
            any(y -> isequal(y, u), all) || push!(all, u)
            under && !any(y -> isequal(y, u), ops) && push!(ops, u)
            return nothing
        end
        iscall(u) || return nothing
        f, a = operation(u), arguments(u)
        if f isa LatticePDE.DivKGrad || f isa LatticePDE.Advect
            foreach(y -> walk(y, under), a[1:(end - 1)])
            walk(a[end], true)
        else
            foreach(y -> walk(y, under || _spatial_op(f)), a)
        end
        return nothing
    end
    walk(eq.rhs, false)
    return (; all, ops)
end
# The field of each steady row of model `sys` (`row => x`, in equation order), by the shared
# rule (`LatticePDE.steady_choice`): a field variable with no other equation that the row
# reads, preferably under a spatial operator; ties in declaration order
function _steady_assign(sys::PottsSystem)
    eqs = _p(sys, :equations)
    rows = [eq for eq in eqs if _zero_lhs(eq) && !isempty(_steady_reads(eq).all)]
    isempty(rows) && return Pair{Any, Any}[]
    taken = Any[
        f[1] for eq in eqs if !_zero_lhs(eq)
            for f in (_field_lhs(eq),) if f !== nothing
    ]
    free = Any[
        x
            for x in _p(sys, :variables)
            if (i = info(x); i !== nothing && i.role === :field) &&
            !any(y -> isequal(y, x), taken)
    ]
    idx(list) = Int[k for (k, x) in enumerate(free) if any(y -> isequal(y, x), list)]
    reads = [_steady_reads(eq) for eq in rows]
    picks, bad = LatticePDE.steady_choice(
        [idx(r.ops) for r in reads], [idx(r.all) for r in reads], length(free)
    )
    if bad != 0
        left = [info(free[k]).name for k in eachindex(free) if !(k in picks)]
        unread = if isempty(left)
            " (every field has an equation)"
        else
            string(
                " of the fields with no equation (", join(("`$n`" for n in left), ", "),
                ")"
            )
        end
        throw(
            PottsCompileError(
                string(
                    "`", rows[bad],
                    "`: a steady row `0 ~ rhs` is solved for a field that it reads and \
                        that ",
                    "has no other equation, and it reads none", unread,
                    "; write the field's operator into the row (`0 ~ D * laplacian(c) - k \
                        * c + …` for `c`)"
                )
            )
        )
    end
    return Pair{Any, Any}[rows[q] => free[picks[q]] for q in eachindex(rows)]
end
# the stepped fields of a model, `(x, rhs, op)`: its rates, maps and steady rows (`op` the
# `Differential` or the `Shift` of the left side, or `:steady`)
function _field_equations(sys::PottsSystem)
    return [
        (f[1], eq.rhs, f[3]) for eq in _p(sys, :equations)
            for f in (_field_lhs(eq, sys),) if f !== nothing && f[2] !== :aux
    ]
end
"""
    steady_fields(model) -> Vector{Pair{String, Symbol}}

The steady rows `0 ~ rhs` of `model` and the field each is solved for (`row => field`), by
the shared rule (`LatticePDE.steady_choice`).
"""
function LatticeFields.Problems.steady_fields(sys::PottsSystem)
    return Pair{
        String,
        Symbol,
    }[string(eq) => info(x).name for (eq, x) in _steady_assign(sys)]
end
# the steady fields (`0 ~ rhs`) among `names`, as the group's state keys
function _steady_names(sys::PottsSystem, names)
    return String[
        string(info(x).name)
            for (x, _, op) in _field_equations(sys)
            if op === :steady && info(x).name in names
    ]
end
# the aux fields of a model, `(x, rhs)`: each group that steps fields computes them
function _field_aux(sys::PottsSystem)
    return [
        (f[1], eq.rhs) for eq in _p(sys, :equations)
            for f in (_field_lhs(eq),)
            if f !== nothing && f[2] === :aux
    ]
end

# a condition's field read `c(t, 0, y)` as the group's state read: its arguments are the
# time `t`, the coordinates or numbers (a face)
function _field_at_term(u, cv)
    n = _field_at_name(u)
    # (or another group's field whose face conditions come along: marked `LatticeCutField`)
    f = haskey(cv.states, n) ? cv.states[n] : get(cv.direct, n, nothing)
    cut = f !== nothing &&
        SymbolicUtils.getmetadata(f, LatticePDE.LatticeCutField, false) === true
    (haskey(cv.states, n) || cut) || throw(
        PottsCompileError(
            string(
                "`", _builtin_text(string(u)), "` reads the field `", n,
                "` of another solver group; a condition reads the field it sets (give the \
                    fields one solver)"
            )
        )
    )
    args = map(arguments(u)) do y
        w = _unwrap(y)
        isequal(w, cv.ivs[1]) && return cv.ivs[1]
        _coordinate(w) && return w
        v = SymbolicUtils.isconst(w) ? SymbolicUtils.unwrap_const(w) : w
        v isa Real && return v
        throw(
            PottsCompileError(
                string(
                    "`", _builtin_text(string(u)), "` reads `", n, "` at `", y,
                    "`; a field is read ",
                    "at `t` and the coordinates, a face fixing one of them to a number \
                        (`", n, "(t, 0, y)`)"
                )
            )
        )
    end
    return operation(f)(args...)
end

# The conditions of the fields `names` as PDESystem conditions, after the
# checks that need the model's words: an initial condition is refused (a field's initial
# value is its default). Periodicity is per field: a periodic pair makes its field wrap on
# its axis, a face condition closes its field there, whatever the lattice does. `own`
# collects each `(field, axis)` that has a condition of its own (a pair or a face): the
# lattice's pair is added only for the others
function _bcs_equations(
        sys, names, cv, core, ext; faced = Symbol[],
        own = Set{Tuple{Symbol, Int}}()
    )
    out = Equation[]
    kinds = _p(sys, :kinds)
    N = length(ext)
    stepped = Symbol[info(x).name for (x, _) in _field_equations(sys)]
    for b in _p(sys, :bcs)
        eq = _located(
            () -> _bcs_equation(sys, b, names, cv, core, ext, kinds, N, stepped, own),
            sys, _BcsLine(b)
        )
        # a face condition of another group's field that an operator here reads (`faced`):
        # it comes along (its masked conditions stay with its group)
        if eq === nothing && !isempty(faced) && first(_bcs_reads(b, ext)[1]) in faced &&
                !(iscall(_unwrap(b.rhs)) && operation(_unwrap(b.rhs)) === LatticePDE.masked)
            eq = _located(
                () -> _bcs_equation(sys, b, faced, cv, core, ext, kinds, N, stepped, own),
                sys, _BcsLine(b)
            )
        end
        eq === nothing && continue
        push!(out, eq)
        push!(cv.bcsrc, eq => b)
    end
    return out
end
# one condition's checks and its translation (`nothing`: another group's)
function _bcs_equation(sys, b, names, cv, core, ext, kinds, N, stepped, own)
    text = "`" * _bc_text(b, kinds) * "`"
    fields, pins = _bcs_reads(b, ext)
    isempty(fields) && throw(
        PottsCompileError(
            "the condition $text reads no field: a condition sets a field (`c(t, 0, y) ~ " *
                "v`, `c ~ masked(pred, v)`)"
        )
    )
    n = first(fields)
    n in stepped || throw(
        PottsCompileError(
            "the condition $text sets `$n`, which has no equation " *
                "`Differential(t)($n($(join(("t", _AXIS_NAMES[1:N]...), ", ")))) ~ …` " *
                "(or map); a condition applies to a field the model steps"
        )
    )
    n in names || return nothing                 # a field of another group: its own system
    any(p -> p[1] == 1, pins) && throw(
        PottsCompileError(
            "the condition $text sets an initial value; a field's " *
                "initial value is its default (`@variables $n(..) = v`) or the operating " *
                "point (`:$n => values`): remove the condition"
        )
    )
    axes = unique(p[1] - 1 for p in pins)
    r = _unwrap(b.rhs)
    periodic = iscall(r) && _is_field_at(operation(r))
    masked = iscall(r) && operation(r) === LatticePDE.masked
    # (a pair or a face of `n` on axis `d`: the lattice's pair is not added for it)
    masked || foreach(d -> push!(own, (n, d)), axes)
    # a face condition sets the ghost values of a spatial operator of `n`: with none in any
    # field's equation (`D(u) ~ laplacian(n)` reads the ghosts of `n` too, and so does an
    # aux field `K ~ laplacian(n)`) it would do nothing
    if !periodic && !masked && !isempty(axes)
        any(f -> _has_spatial_op(f[2], n), _field_equations(sys)) ||
            any(f -> _has_spatial_op(f[2], n), _field_aux(sys)) || throw(
            PottsCompileError(
                "the condition $text sets a face of `$n`, which sets the ghost values of " *
                    "a spatial operator of `$n`, but the equation of `$n` has no " *
                    "`laplacian($n)` nor another spatial operator of `$n` " *
                    "(`DivKGrad(…)(K, $n)`, `Advect(…)(u, $n)`, a raw flux " *
                    "`Differential(x)(K * Differential(x)($n))`), and no other field's \
                        equation or aux definition `K ~ …` has one; the condition would do \
                        nothing: drop it, or hold sites with a masked condition `$n ~ \
                        masked(pred, v)`"
            )
        )
    end
    masked || periodic || _check_robin_coefs(b, N)
    return Symbolics.wrap(_field_term(b.lhs, cv)) ~ Symbolics.wrap(_field_term(b.rhs, cv))
end
# the fields a condition reads (its face reads `c(t, 0, y)` and its bare field
# variables) and the pinned arguments of its face reads: `(argument index, -1 | +1)`, by
# comparing each number with the low end 0
_extent_text(v) = isinteger(v) ? string(Int(v)) : string(v)
function _bcs_reads(b, ext)
    fields, pins = Symbol[], Tuple{Int, Int}[]
    _walk_all(
        y -> begin
            if iscall(y) && _is_field_at(operation(y))
                push!(fields, _field_at_name(y))
                for (k, a) in enumerate(arguments(y))
                    w = _unwrap(a)
                    v = SymbolicUtils.isconst(w) ? SymbolicUtils.unwrap_const(w) : w
                    # a face only at 0 or the extent; another number is `parse_bcs`'s to
                    # name
                    v isa Real || continue
                    if k == 1
                        push!(pins, (1, -1))
                    elseif iszero(v)
                        push!(pins, (k, -1))
                    else
                        k - 1 <= length(ext) && isapprox(v, ext[k - 1]) &&
                            push!(pins, (k, 1))
                    end
                end
            else
                i = info(y)
                i !== nothing && i.role === :field && push!(fields, i.name)
            end
        end, _unwrap(b.lhs)
    )
    # the field the condition sets comes first: a term's own read, not a read in a
    # coefficient (`(1 + u(t, 0, y)) * c(t, 0, y)` sets `c` whatever the order of the
    # product's factors)
    own = _bcs_own(_unwrap(b.lhs))
    unique!(fields)
    return [filter(in(own), fields); filter(!in(own), fields)], unique!(pins)
end
# the fields that the terms of a condition's left side read as their own: `c(t, 0, y)`,
# `Differential(x)(c(t, 0, y))`, a bare field `c`, or one of these as a factor of a
# product, the numerator of a quotient or the base of a power
function _bcs_own(lhs)
    own = Symbol[]
    function own_read(f)
        return if iscall(f) && _is_field_at(operation(f))
            push!(own, _field_at_name(f))
        elseif iscall(f) && operation(f) isa Differential
            own_read(_unwrap(first(arguments(f))))
        elseif iscall(f) && operation(f) === (*)
            foreach(g -> own_read(_unwrap(g)), arguments(f))
        elseif iscall(f) && (operation(f) === (/) || operation(f) === (^))
            own_read(_unwrap(first(arguments(f))))
        else
            i = info(f)
            i !== nothing && i.role === :field && push!(own, i.name)
        end
    end
    terms = iscall(lhs) && operation(lhs) === (+) ? arguments(lhs) : (lhs,)
    foreach(tm -> own_read(_unwrap(tm)), terms)
    return own
end

"""
    _field_system(sys, names; T = Float64) -> (pdesys, cv)

The `PDESystem` of the fields `names` of model `sys` (all its fields by default): their
equations, their conditions as bcs (faces, periodic pairs, masked conditions) and the
lattice as the domain (axis `d` spans `dims[d] · h[d]`). `cv` is the conversion state (its
inputs and parameters).
"""
function _field_system(
        sys::PottsSystem, names = Symbol[info(x).name for (x, _) in _field_equations(sys)];
        T::Type = Float64,
        known = nothing
    )
    # the model-wide filled inputs in their canonical order: lowering finds each CPM read in
    # `known` by its expression, so the names and the order (the dvs, the fill phase) do not
    # depend on the order in which the converter meets the reads
    known === nothing && (
        known = _canonical_filled(
            _field_system(
                sys; T, known = Tuple{
                    Symbol, Any, Type,
                }[]
            )[2].filled
        )
    )
    lat = _p(sys, :lattice)
    N = length(lat.dims)
    h = something(lat.spacing, ntuple(_ -> 1.0, N))
    tt = _unwrap(t)
    xs = collect(_FIELD_X[1:N])
    ivs = Any[tt; xs]
    aux = _field_aux(sys)
    auxnames = Symbol[info(x).name for (x, _) in aux]
    states = Dict{Symbol, Any}(
        n => _field_var(
            n, Real, ivs; storage = _field_storage(sys, n),
            bounds = _field_bounds(sys, n),
            level = _field_level(sys, n)
        )
            for n in [names; auxnames]
    )
    cv = _field_conv(ivs, states, T, known, _p(sys, :kinds))
    eqs = Equation[]
    for (x, rate, op) in _field_equations(sys)
        n = info(x).name
        n in names || continue
        # (a refusal of a term names this field's equation, not the first one)
        r = Symbolics.wrap(
            _located(() -> _field_term(rate, cv), sys, _field_equation_of(sys, string(n)))
        )
        # (a steady row stays `0 ~ rhs`: LatticePDE solves it for the same field, the one
        # free field its operator acts on in the group)
        op === :steady && (push!(eqs, 0 ~ r); continue)
        lhs = if op isa ModelingToolkitBase.Shift
            op(Symbolics.wrap(states[n]))
        else
            Differential(tt)(Symbolics.wrap(states[n]))
        end
        push!(eqs, lhs ~ r)
    end
    # every group computes the aux fields from the values it reads
    for (x, rhs) in aux
        push!(
            eqs, Symbolics.wrap(states[info(x).name]) ~
                Symbolics.wrap(_field_term(rhs, cv))
        )
    end
    core = core_lattice(lat)
    ext = ntuple(d -> lat.dims[d] * Float64(h[d]), N)
    # another group's field that a spatial operator here reads (`laplacian(v)`, v stepped
    # elsewhere): an input that carries its face conditions, so its ghost values are its own
    # group's. A site variable or a field with no equation that an operator reads is such an
    # input too, with no face conditions: a closed face has no flux (before, LatticeFields
    # refused it for want of a boundary rule). On a lattice periodic on every axis it needs
    # none, and its program stays as it was
    stepped = Symbol[info(x).name for (x, _) in _field_equations(sys)]
    others = [
        n
            for n in keys(cv.direct)
            if !(n in names) && (n in stepped || !all(core.periodic))
    ]
    hit = LatticePDE.operand_reads(eqs, Any[operation(cv.direct[n]) for n in others])
    faced = Symbol[n for n in others if any(o -> isequal(o, operation(cv.direct[n])), hit)]
    for n in faced
        cv.direct[n] = SymbolicUtils.setmetadata(
            cv.direct[n], LatticePDE.LatticeCutField,
            true
        )
    end
    fvar(n) = haskey(states, n) ? states[n] : cv.direct[n]
    at_face(n, d, v) = (args = Any[ivs...]; args[d + 1] = v; operation(fvar(n))(args...))
    # the conditions: each condition of a field of this group, translated as the
    # equations are, so `lower_group` parses it with `parse_bcs` as LatticePDE does
    own = Set{Tuple{Symbol, Int}}()
    fbcs = _bcs_equations(sys, names, cv, core, ext; faced, own)
    # the lattice's periodic pairs, for each field (and another group's field read here)
    # with no condition of its own on that axis
    bcs = Equation[]
    for n in [names; faced], d in 1:N
        core.periodic[d] && !((n, d) in own) && push!(
            bcs, Symbolics.wrap(at_face(n, d, 0.0)) ~
                Symbolics.wrap(at_face(n, d, ext[d]))
        )
    end
    append!(bcs, fbcs)
    _has_domain(lat) && _filled_input!(cv, _DOMAIN_FILL, :domain__in, Bool)
    dvs = Any[
        [states[n] for n in [names; auxnames]];
        [cv.direct[k] for k in sort!(collect(keys(cv.direct)))];
        [cv.inputs[e[1]] for e in cv.filled if haskey(cv.inputs, e[1])]
    ]
    ps = sort!(collect(cv.params); by = string)
    _refuse_input_words(cv, names, ps)
    domain = [
        Symbolics.wrap(tt) ∈ LatticePDE.Interval(0.0, 1.0);
        [Symbolics.wrap(xs[d]) ∈ LatticePDE.Interval(0.0, ext[d]) for d in 1:N]
    ]
    pdesys = ModelingToolkitBase.PDESystem(
        eqs, bcs, domain, ivs, dvs, ps; name = nameof(sys)
    )
    return pdesys, cv
end

"""
The filled inputs of model `sys`: `(name, expr, eltype)`, the site arrays the CPM writes for
the fields every MCS (`T` is the state type).
"""
function _field_inputs(sys::PottsSystem, T::Type = Float64)
    if isempty(_field_equations(sys)) && isempty(_field_aux(sys))
        return Tuple{Symbol, Any, Type}[]
    else
        return _canonical_filled(
            _field_system(sys; T, known = Tuple{Symbol, Any, Type}[])[2].filled
        )
    end
end
# those of compiled model `c`, made once per state type (cached on `c`)
function _field_inputs(c::CompiledPottsSystem, T::Type = Float64)
    return _field_cached(() -> _field_inputs(getfield(c, :sys), T), c, (:inputs, T))
end

"""The masked fields of `sys` (each has a mask site array `name__mask`): the masked
conditions (`c ~ masked(pred, v)`)."""
function _masked_fields(sys::PottsSystem)
    out = Symbol[]
    for b in _p(sys, :bcs)
        r, l = _unwrap(b.rhs), _unwrap(b.lhs)
        iscall(r) && operation(r) === LatticePDE.masked || continue
        i = info(l)
        i !== nothing && i.role === :field && push!(out, i.name)
    end
    return unique!(out)
end

# The lattice of the fields: a hexagonal lattice is a hexagonal grid (LatticePDE's
# six-neighbor `laplacian`), and an irregular `domain` is the Bool input `domain__in`
# (written by the fill phase from the lattice's mask) with a zero-flux edge: as the old
# field path, a neighbor outside the domain or a closed face reads the site itself.
_has_domain(lat) = (m = core_lattice(lat).mask; m !== nothing && !all(m))
const _DOMAIN_FILL = :__domain__          # the fill expression of `domain__in`
function _fill_value(ex, env)
    return if ex === _DOMAIN_FILL
        :(CorePotts.in_domain(ctx.lattice, $(env.bind[:__site])))
    else
        lower(ex, env)
    end
end
function _field_disc(sys::PottsSystem, T)
    lat = _p(sys, :lattice)
    geometry = if lat.geometry isa CorePotts.Hexagonal
        LatticeFields.IR.HEX
    else
        LatticeFields.IR.CUBIC
    end
    # the clock is the MCS: `mcs` reads its step index
    return LatticePDE.LatticeDiscretization(
        LatticePDE.Grid(lat.dims; geometry); T,
        domain = _has_domain(lat) ? "domain__in" : nothing,
        clock = Float64(_p(sys, :sweep).mcs_duration)
    )
end

# ---------------------------------------------------------------------------------------
# Field groups of a problem: one LatticeFields group (`GroupSpec`, `FieldGroup`) per solver
# group

"""
One stepped group: its fields, its `FieldGroup` (the `GroupSpec` from
`LatticePDE.lower_group`, the update of its algorithm fused by the IR pass, the plans), the
algorithm, the semantic program and the mask and step plans, the array bindings, the
parameter and table bindings, the substep rule, the fingerprint text and the compile
options.
"""
_has_aux(g) = any(k -> startswith(k.key, "aux:"), g.program.kernels)
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
    # the whole system's tables the substep rule reads
    rule_tables::Vector{Pair{String, Symbol}}
end
function _FieldGroup(
        names, group, alg, program, masks, step, arrays,
        tables, params, substeps, fingerprint, options
    )
    return _FieldGroup(
        names, group, alg, program, masks, step, arrays,
        tables, params, substeps, fingerprint, options,
        Pair{String, Symbol}[]
    )
end

# The substep rule of a map group: one application per field window (the
# MCS), whatever the parameters; a map has no stability bound
struct _MapSteps end
(::_MapSteps)(praw) = 1
# The substep rule of the group of a model whose only fields are aux fields `K ~ rhs`: no
# state, so no substep; the phase evaluates them once per MCS
struct _AuxSteps end
(::_AuxSteps)(praw) = 0
# the least count and the bounded flag of a group's rule, as the fingerprint records them
function _least(s)
    if s isa _MapSteps
        return 1
    elseif s isa _AuxSteps
        return 0
    else
        return something(_given_count(s.alg), 1)
    end
end
# the count an algorithm was given (`substeps = n`), or `nothing` (automatic, or no such
# keyword)
_given_count(a) = hasproperty(a, :substeps) ? a.substeps : nothing
function _bounded(s)
    return s isa Union{_MapSteps, _AuxSteps} ||
        (isempty(s.spec.stability.unbounded) && isempty(s.spec.stability.expanded))
end
# whether compiled model `c` has fields: stepped ones, or aux fields only (one group with no
# state)
function _has_fields(c::CompiledPottsSystem)
    return !isempty(getfield(c, :fields)) || !isempty(_field_aux(getfield(c, :sys)))
end

# The cache of the lowered field groups of a compiled model
# (`CompiledPottsSystem.field_specs`): `mtkcompile` lowers the group of all fields once, in
# Float64, and a `PottsProblem` whose partition and state type match reuses it
const _FIELD_SPEC_LOCK = ReentrantLock()
function _field_cached(f, c::CompiledPottsSystem, key)
    return lock(() -> get!(f, getfield(c, :field_specs), key), _FIELD_SPEC_LOCK)
end

# the number of `lower_group` calls of this session (a test counts them)
const _LOWER_GROUP_CALLS = Threads.Atomic{Int}(0)

"""
    _lower_field_group(sys, names, T; known) -> NamedTuple

The field group of the fields `names` of model `sys` in state type `T`, lowered once by
`LatticePDE.lower_group` to its `GroupSpec` (`spec`), with what `Potts` binds: the
parameter names of its slots (`params`), its tables by id (`tables`) and the generated
inputs (`filled`, to print a term in the model's words). The fields of other groups are
inputs of the group, read from their arrays (`_field_system`).
"""
function _lower_field_group(
        sys::PottsSystem, names::Vector{Symbol}, T::Type; known, bound::Bool = true
    )
    pdesys, cv = _field_system(sys, names; T, known)
    # rates and maps in one model are refused everywhere
    LatticePDE.check_one_kind(
        pdesys; route = "write each map as a site update that runs once per MCS (a site " *
            "variable `m(site)` with `@after_mcs m ~ rhs`)"
    )
    Threads.atomic_add!(_LOWER_GROUP_CALLS, 1)
    spec = try
        LatticePDE.lower_group(
            pdesys, _field_disc(sys, T); values = false, bound,
            filled = (string(e[1]) for e in cv.filled),
            steady = _steady_names(sys, names)
        )
    catch e
        # an error about a condition (`parse_bcs`, a second condition on a face) names the
        # condition and its PDESystem
        e isa ArgumentError || rethrow()
        i = findfirst(p -> occursin("`$(p[1])`", e.msg), cv.bcsrc)
        i === nothing && rethrow()
        _located(() -> throw(e), sys, _BcsLine(cv.bcsrc[i][2]))
    end
    # the model's parameter of each slot and table (the spec names them as the PDESystem
    # prints them); the clock's slot keeps its reserved name (the phase writes the MCS
    # number there)
    function pname(k)
        return if k == LatticeFields.Problems.CLOCK_KEY
            Symbol(k)
        else
            info(only(q for q in ModelingToolkitBase.get_ps(pdesys) if string(q) == k)).name
        end
    end
    params = Symbol[pname(k.name) for k in spec.params]
    tables = Pair{Int, Symbol}[
        i => pname(tb.key)
            for (i, tb) in enumerate(spec.rate.tables)
    ]
    return (; spec, params, tables, filled = copy(cv.filled), pdesys)
end
# cached on compiled model `c` by partition and state type; `mtkcompile`'s entry has its
# stability bound deferred (`LatticePDE.resolve_bound`), built here once, at the first
# problem
function _field_group_spec(c::CompiledPottsSystem, names::Vector{Symbol}, T::Type)
    return lock(_FIELD_SPEC_LOCK) do
        g = get!(
            () -> _lower_field_group(
                getfield(c, :sys), names, T;
                known = _field_inputs(c, T)
            ),
            getfield(c, :field_specs),
            (names, T)
        )
        g.spec.stability isa LatticePDE.DeferredBound || return g
        getfield(c, :field_specs)[(names, T)] = (;
            g..., spec = LatticePDE.resolve_bound(g.spec),
        )
    end
end

# The substep rule of a group is LatticeFields' one policy (`Problems.GroupSubsteps`: the
# count, the refusals, the warnings and the coupling between groups). `Potts` gives
# its words (`_PottsTexts`): the fields of the group, its route (`PottsProblem`
# `field_solver`, the MCS as the window) and its terms in the model's words (`_user_text`).
# A warning is given once per group, term and cause in a session (the group's fingerprint
# text with the policy's value-free reason).
struct _PottsTexts <: LatticeFields.Problems.AbstractPolicyTexts
    names::Vector{Symbol}
    # the generated inputs (`filled`), to print a term in the model's words
    cv::NamedTuple
end
_fieldlist(ks) = join(("`$k`" for k in ks), ", ")
_fs(t::_PottsTexts) = length(t.names) == 1 ? "" : "s"
const _POTTS_ROUTE = "`PottsProblem` `field_solver = ExplicitEuler(; substeps = n)` with \
    `n ≥ mcs_duration · ρ / 1.8`"
# an advection whose velocity reads the field it moves (`Advect(…)([c, 0.0], c)`, Burgers):
# no interval bounds it (the velocity grows with the field), so `bounds` is not a route for
# it
function _self_advection(x::AbstractString)
    m = match(r"Advect\(.*\)\(\[(.*)\],\s*([^\s\)]+)\)", x)
    m === nothing && return false
    return occursin(
        Regex(string("(?<![\\w₊])", m.captures[2], "(?![\\w₊])")),
        m.captures[1]
    )
end
function LatticeFields.Problems.unbounded_text(t::_PottsTexts, c)
    r = c.r
    texts = [_user_text(x, t.cv) for x in r.terms]
    if !isempty(texts) && all(_self_advection, texts)
        return "the substep count of the field$(_fs(t)) $(_fieldlist(t.names)) has no " *
            "bound (the " *
            "term$(length(texts) == 1 ? "" : "s") $(join(("`$x`" for x in texts), ", ")): \
                an advection whose velocity reads the field it moves, which no interval \
                bounds); give " * _POTTS_ROUTE *
            ", or step the field" *
            "$(_fs(t)) with `field_solver = BackwardEuler()`"
    end
    if !isempty(r.terms)
        return "the substep count of the field$(_fs(t)) $(_fieldlist(t.names)) has no " *
            "bound from the parameters (the " *
            "term$(length(r.terms) == 1 ? "" : "s") " *
            "$(join(("`$(_user_text(x, t.cv))`" for x in r.terms), ", ")), which the " *
            "stability bound cannot see: a nonlinear term or a coefficient " *
            "that reads a field with no finite declared `bounds`, an advection whose " *
            "velocity reads the field it moves, a diffusion multiplier that varies by " *
            "site through a CPM value read directly (`volume[owner] * laplacian(c)`; a " *
            "kind table `δ[kind] * laplacian(c)` or a kind set `ismember(kind, g) * \
                laplacian(c)` is bounded), or a coefficient that reads `mcs`)" *
            _infinite_text(t) *
            "; declare finite `bounds = (lo, hi)` on a field whose " *
            "values stay in an interval (`@variables c(..) = 0.5 [bounds = (0, 1)]` in " *
            "its PDESystem: the bound then sees its nonlinear terms and coefficients), or \
                give " * _POTTS_ROUTE
    elseif !isempty(r.coupled)
        return "the substep count of the field$(_fs(t)) $(_fieldlist(t.names)) has no " *
            "bound from the parameters: the coupled " *
            "rate$(length(r.coupled) == 1 ? "" : "s") of $(_fieldlist(r.coupled)) (terms " *
            "that read another field, which reads it " *
            "back) $(length(r.coupled) == 1 ? "is" : "are") not diagonally dominant; step \
                the field$(_fs(t)) with `field_solver = BackwardEuler()` (it solves the \
                fields in the order they read each other, with no substep bound), or \
                give " * _POTTS_ROUTE
    end
    why = if isempty(r.nonfinite)
        "a coefficient is not finite"
    else
        join((_nonfinite_text(text, w, t.cv) for (_, text, w) in r.nonfinite), "; ")
    end
    return string(
        "the substep bound of the field$(_fs(t)) ", _fieldlist(t.names),
        " is not finite at the current parameters: ",
        why
    )
end
# the fields of a group whose declared bounds are not finite (`bounds = (0, Inf)`), in words
function _infinite_text(t::_PottsTexts)
    inf = get(t.cv, :infinite, Symbol[])
    isempty(inf) && return ""
    return string(
        " (", _fieldlist(inf),
        length(inf) == 1 ? " declares bounds that are" : " declare bounds that are",
        " not finite: the bound needs both ends)"
    )
end
function LatticeFields.Problems.uncovered_text(t::_PottsTexts, c)
    r = c.r
    what = String[
        ["`" * _user_text(x, t.cv) * "`" for x in r.terms];
        (
            if isempty(r.coupled)
                String[]
            else
                ["the coupled rates of $(_fieldlist(r.coupled))"]
            end
        );
        [
            _nonfinite_text(text, w, t.cv; warning = true)
                for (_, text, w) in r.nonfinite
        ]
    ]
    return "field$(_fs(t)) $(_fieldlist(t.names)): $(c.n) substeps per field step (the " *
        "requested $(c.least), or more for the terms the bound sees); the stability bound \
            does not cover " *
        join(what, ", ") * ": the count is the user's"
end
function LatticeFields.Problems.refuse_parameters(t::_PottsTexts, c)
    r = c.r
    isempty(r.negative) || throw(
        ArgumentError(
            "the diffusion coefficient of the " *
                "field$(length(r.negative) == 1 ? "" : "s") $(_fieldlist(r.negative)) is " *
                "negative at the current parameters (anti-diffusion: an ill-posed " *
                "equation, unstable at any step and with any solver); write the term with \
                    a coefficient ≥ 0 (`D * laplacian(c)` with `D ≥ 0`; a decay is a \
                    reaction term `-k * c`), or give the parameters values that make it ≥ 0"
        )
    )
    throw(
        ArgumentError(
            LatticeFields.Problems.unbounded_text(
                _PottsTexts(t.names, t.cv), (;
                    c..., r = (;
                        r..., terms = String[],
                        coupled = String[],
                    ),
                )
            )
        )
    )
end
# (`LatticePDE.StabilityBound` tracks cross terms across callers)
function LatticeFields.Problems.coupling_unknown_text(t::_PottsTexts, c; refuse::Bool)
    return "the stability bound of the fields $(_fieldlist(t.names)) does not see their \
        coupling to the other solver groups" *
        (
        if refuse
            "; give `solvers` an explicit `ExplicitEuler(; substeps = n)` for the group"
        else
            ": the count is the user's"
        end
    )
end
function LatticeFields.Problems.coupling_unbounded_text(t::_PottsTexts, c; refuse::Bool)
    q, lf, n = c.q, c.lf, length(t.names)
    u(k) = string("`", k, "`")
    refuse && return string(
        "the field", n == 1 ? " " : "s ", _fieldlist(t.names),
        " read", n == 1 ? "s " : " ", u(q.other),
        " of another solver group, in a loop of groups that ",
        "read one another (", _fieldlist(lf), "), and the coefficient `",
        _user_text(q.raw, t.cv), "` of that read ",
        "has no bound at these parameters; give ", _fieldlist(lf),
        " one solver (one group), or give `solvers` an ",
        "explicit `ExplicitEuler(; substeps = n)` for the group"
    )
    return "field$(n == 1 ? "" : "s") $(_fieldlist(t.names)): the coupling " *
        "to $(u(q.other)) of another solver group, in the loop of $(_fieldlist(lf)), has " *
        "no bound (the coefficient `$(_user_text(q.raw, t.cv))`): the count is the user's"
end
function LatticeFields.Problems.steady_loop_text(t::_PottsTexts, c)
    w = c.why[1]
    one = if w in (:steady_only, :steady)
        string(
            "Give ", _fieldlist(c.qs), " one `QuasiSteady` solver (one group, whose ",
            "steady rows are solved together), or give "
        )
    else
        "Give "
    end
    return string(
        "the fields ", _fieldlist(c.lf),
        " are in solver groups that read one another in a loop, and ",
        _fieldlist(c.qs), length(c.qs) == 1 ? " is" : " are",
        " solved with `QuasiSteady`: a steady field answers its ",
        "inputs at once, with the gain of its steady solve, so the lag of one field \
            window between the groups can grow ",
        "without bound, and here the coupling rule has no bound for that gain: ",
        LatticeFields.Problems.steady_why_text(c.why),
        ". ", one, _fieldlist(c.lf), " one `BackwardEuler` solver (one group), or step ",
        _fieldlist(c.qs), " with ",
        "`BackwardEuler` (a fast field relaxes to its steady state within a few \
            MCS)", LatticeFields.Problems.rows0_route(c)
    )
end
function LatticeFields.Problems.steady_gain_text(t::_PottsTexts, c)
    x = c.x
    via = if isempty(x.qs)
        ""
    else
        string(
            " (`", x.qs, "` answers at once with a gain up to ",
            round(x.gain; sigdigits = 6),
            ", from its smallest decay and its faces, times ", round(x.kout; sigdigits = 6),
            ", the sum of its reads of the loop)"
        )
    end
    return string(
        "the fields ", _fieldlist(c.lf),
        " are in solver groups that read one another in a loop, and ",
        _fieldlist(c.qs), length(c.qs) == 1 ? " is" : " are",
        " solved with `QuasiSteady`, each group holding the others' ",
        "values over each field window (", c.dt, " MCS): the terms of `", x.row,
        "` that read other groups of the loop (the ",
        "largest: the coefficient `", _user_text(x.raw, t.cv), "` of `", x.other,
        "`", via, ") give window · Σ k_in · gain · ",
        "k_out = ", round(c.κ; sigdigits = 4),
        " > 1, and the loop can then grow without bound. Give ", _fieldlist(c.lf),
        " one `BackwardEuler` solver (one group), or step ", _fieldlist(c.qs),
        " with `BackwardEuler`, or step the fields ",
        "over a shorter window (`repeat(n, …)` of the fields, or a smaller \
            `mcs_duration`; window ≤ ",
        floor(1 / x.rate; sigdigits = 4), ")", LatticeFields.Problems.rows0_route(c)
    )
end
function LatticeFields.Problems.loop_text(t::_PottsTexts, c)
    q, κ, lf = c.q, c.κ, c.lf
    u(k) = string("`", k, "`")
    unseen = [k for h in c.loops[c.g] if c.parts[h].unseen for k in c.keys[h]]
    # one solver for the loop: an automatic count needs dominant rows (a parameter of
    # another group has no value here: then the explicit route, which always holds)
    ρ = Float64(LatticeFields.Problems.restrict_bound(c.stability, lf)(c.pp))
    one = if isfinite(ρ) && ρ >= 0
        string("Give ", _fieldlist(lf), " one solver (one group; `solvers`)")
    else
        string(
            "Give ", _fieldlist(lf),
            " one solver with an explicit count (one group, `ExplicitEuler(; ",
            "substeps = n)`; their coupled rows have no automatic count)"
        )
    end
    unseen_note = if isempty(unseen)
        ""
    else
        string(
            " (the terms of ", _fieldlist(unseen), " that the stability bound cannot ",
            "see and that read another field count as reading every other group)"
        )
    end
    return string(
        "the fields ", _fieldlist(lf), " are in solver groups that read one another in a ",
        "loop, each holding the others' values over each field window (", c.dt,
        " MCS): the terms of ", u(q.row),
        " that read other groups of the loop (the largest: the coefficient `",
        _user_text(q.raw, t.cv), "` of ", u(q.other),
        ") give window · Σ max|coefficient| = ", round(κ; sigdigits = 4),
        " > 1, and the loop can then grow ",
        "without bound at any substep count",
        unseen_note,
        ". ", one,
        ", or step the fields over a shorter window (`repeat(n, …)` of the fields, or a \
            smaller ",
        "`mcs_duration`; window ≤ ", floor(1 / q.rate; sigdigits = 4), ")"
    )
end

# why a coefficient has no finite bound, in the model's words: a kind table entry `e` is
# kind `e - 1` (entry 1 is the medium's), with the route
function _nonfinite_text(text, w, cv; warning::Bool = false)
    # a kind table read `value_at(τ, 1 + kind)` as the model writes it, `τ[kind]`
    u = replace(
        _user_text(text, cv), r"value_at\((\w+), (?:1 \+ kind|kind \+ 1)\)" =>
            s"\1[kind]"
    )
    # (a Robin face whose coefficients vary by site or in time: the face in words)
    w === :robin && return string(
        "the Robin coefficients of ", u,
        " give the ghost value no finite bound (α/2 + β/h ",
        "may vanish at a site, or a coefficient grows without bound in time)"
    )
    t = "`" * u * "`"
    # past the cap: the error gives the route (a count), the warning (a count was given)
    # none
    w === :cap && warning &&
        return string(t, " (it reads more than 4096 kind table index combinations)")
    w === :cap && return string(
        t, " (it reads more than 4096 kind table index combinations; with no count, give ",
        "`PottsProblem` `field_solver = ExplicitEuler(; substeps = n)` with `n ≥ \
            mcs_duration · ρ / 1.8`)"
    )
    w isa Tuple || return string(t, " is not finite at the current parameters")
    combos, more = w
    all(isempty, combos) &&
        return string(t, " is not finite; give its parameters values that make it finite")
    function ent(tb, i)
        if i == 0
            return "index 0 of `$tb` (which reads 0)"
        elseif i == 1
            return "the medium's entry of `$tb` (kind 0)"
        else
            return "the entry of kind $(i - 1) of `$tb`"
        end
    end
    # the route by cause: a zero under a division, a negative value under `sqrt` or `log`
    function fix(v)
        if v == 0
            return "make it nonzero (a zero entry: a division by it is not finite)"
        elseif v < 0
            return "make it ≥ 0 (a negative entry under `sqrt` or `log` is not finite)"
        else
            return "give it a value where the coefficient is finite"
        end
    end
    rd = unique(reduce(vcat, combos))
    return string(
        t, " is not finite at ",
        join((join((ent(tb, i) for (tb, i, _) in c), " with ") for c in combos), ", at "),
        more > 0 ? " (and $more more)" : "", "; ",
        join(("$(ent(tb, i)) is $v: $(fix(v))" for (tb, i, v) in rd if i != 0), "; "),
        " (every kind's entry is read, the medium's too)"
    )
end

# A term of the field system in the model's words: a generated input
# (`kind__in(t, x, y)`, `field1__in(…)`) prints as the CPM read it holds, a field read
# `c(t, x, y)` as `c`; the key's `"c: "` prefix is dropped
function _user_text(term::AbstractString, cv)
    out = replace(term, r"^[^:]+: " => "")
    for (name, ex, _) in cv.filled
        user = _input_word(name, ex)
        out = replace(out, Regex(string(name) * raw"\(t(, [xyz])*\)") => user)
    end
    # the model's `÷`
    out = replace(out, r"Potts\._intdiv\(([^,()]+), ([^()]+)\)" => s"(\1 ÷ \2)")
    # `laplacian(c)`, `value_at(δ, …)`, `[ux, uy]` as written
    out = LatticePDE.as_written(replace(out, "LatticePDE." => ""))
    # the clock's step index
    out = replace(out, r"\bstep_index\(t\)" => "mcs", r"\bclock__tick\b" => "mcs")
    out = replace(out, r"(\w+)\(t(, [xyz])*\)" => s"\1")
    # a kind table read `value_at(δ, 1 + kind)` as the model writes it, `δ[kind]`; the time
    # `t` is `time`
    out = replace(out, r"value_at\((\w+), (?:1 \+ kind|kind \+ 1)\)" => s"\1[kind]")
    # a CPM read `volume[owner]`
    out = replace(out, r"value_at\((\w+), (\w+)\)" => s"\1[\2]")
    return replace(out, r"\bt\b" => "time")
end

# The model time of one field phase: the MCS, or `1/n` of it inside a sub-MCS `repeat(n, …)`
function _field_dt(sys::PottsSystem)
    r = _schedule_repeat(_p(sys, :schedule))
    return Float64(_p(sys, :sweep).mcs_duration) /
        (r !== nothing && :fields in r.names ? r.n : 1)
end

"""
    _field_groups(c, T, spec) -> Vector{_FieldGroup}

The field groups of compiled model `c` for state type `T` and solvers `spec`: fields with
equal solvers (canonical form) form one group, in order of first appearance; inside a group
the plan orders the fields topologically by what they read (strongly connected fields step
together, Jacobi). A field of another group is read from its own array. Each group
is lowered once by `LatticePDE.lower_group` (cached on `c`: the group of all fields comes
from `mtkcompile`), and its algorithm's update is fused by the IR pass (`fuse_update`).
"""
function _field_groups(c::CompiledPottsSystem, T::Type, spec::SolverSpec)
    sys = getfield(c, :sys)
    order = Tuple{String, Any, Vector{Symbol}}[]
    for (x, _) in getfield(c, :fields)
        n = info(x).name
        s = spec.resolved[n]
        k = _canonical(s)
        j = findfirst(g -> g[1] == k, order)
        j === nothing ? push!(order, (k, s, Symbol[n])) : push!(order[j][3], n)
    end
    # the QuasiSteady groups first: a steady field is solved before the
    # transient fields that read it, from their MCS-start values
    qs(g) = g[2] isa LatticeFields.Problems.QuasiSteady
    order = [filter(qs, order); filter(!qs, order)]
    dt = _field_dt(sys)
    groups = _FieldGroup[]
    # aux fields only: one group with no state, stepped by the default
    # algorithm (no `field_solver` applies), with no substep
    isempty(order) && return [_aux_group(c, T, dt)]
    allnames = Symbol[info(x).name for (x, _) in _field_equations(sys)]
    # with several groups, the coupling between them (`Problems.check_coupling`): the bound
    # of the whole field system (the group of all fields, in rate form), and the partition
    coupling = nothing
    if length(order) > 1
        whole = _field_group_spec(c, allnames, T)
        coupling = (;
            bound = whole.spec.stability, groups = [
                String[string(n) for n in g[3]]
                    for g in order
            ],
            wnames = whole.params, wtables = Pair{String, Symbol}[
                whole.spec.rate.tables[i].key =>
                    n
                    for (i, n) in whole.tables
            ],
        )
    end
    # Cartesian indexing: the host loop hands each site its coordinates (a linear launch
    # decodes them with an integer division per site, about 3x slower on the CPU)
    for (gi, (_, solver, names)) in enumerate(order)
        lg = _field_group_spec(c, names, T)
        opts = _field_options(c, T, solver, lg.spec.rate)
        gspec = lg.spec
        fused = LatticeFields.Compile.fuse_update(
            gspec.rate,
            LatticeFields.Problems.update_rule(solver)
        )
        group = LatticeFields.Problems.FieldGroup(
            gspec; alg = solver, program = LatticeFields.Compile.semantic(fused)
        )
        prog = group.program
        mplan, splan = LatticeFields.Problems.group_plans(
            group, solver, T, KernelAbstractions.CPU(), opts
        )
        arrays = Tuple(
            begin
                k = f.key
                if startswith(k, "mask:")
                    (CorePotts.Part((:site, Symbol(k[6:end], :__mask))), nothing)
                elseif startswith(k, "face:") || startswith(k, "maskvalue:") ||
                        startswith(k, "domain:") ||
                        _hidden_aux(k)
                    # a value field, or the domain on a coarse level: the binding's own
                    (CorePotts.BindingScratch(), nothing)
                elseif Symbol(k) in names
                    (
                        CorePotts.Part((:site, Symbol(k))),
                        CorePotts.Part((:site, Symbol(k, :__next))),
                    )
                else
                    (CorePotts.Part((:site, Symbol(k))), nothing)
                end
            end
                for f in prog.fields
        )
        cv = (; filled = lg.filled)
        stab = gspec.stability
        if gspec.kind === :map
            # a map steps once per window: no substep count, no bound
            fp = LatticeFields.Compile.fingerprint_text(fused; T)
            push!(
                groups, _FieldGroup(
                    names, group, solver, prog, mplan, splan,
                    arrays, lg.tables, lg.params, _MapSteps(),
                    fp, opts
                )
            )
            continue
        end
        # the substep rule: LatticeFields' policy phrased for Potts; with
        # several groups, the coupling of this group to the others at the whole system's
        # parameters, mapped by name (a parameter the group does not read is `NaN`: no cross
        # coefficient of its rows reads it; the read graph is the structure, so it needs no
        # value). An implicit group's fingerprint is its residual program's (the program it
        # runs)
        fp = if solver isa LatticeFields.Problems.AbstractImplicitFieldAlgorithm
            LatticeFields.Compile.fingerprint_text(
                LatticeFields.Compile.fuse_residual(
                    gspec.rate,
                    LatticeFields.Problems.residual_rule(solver); widen16 = true
                ); T
            )
        else
            LatticeFields.Compile.fingerprint_text(fused; T)
        end
        # with a QuasiSteady group among several, every group's phase holds the whole
        # system's parameters (after its own, which its launches read by slot): the steady
        # gain in the coupling rule reads the steady rows' decay and faces, which another
        # group's rule needs
        withqs = coupling !== nothing &&
            any(o -> o[2] isa LatticeFields.Problems.QuasiSteady, order)
        params = if withqs
            [lg.params; [n for n in coupling.wnames if !(n in lg.params)]]
        else
            lg.params
        end
        rtabs = if withqs
            Pair{String, Symbol}[
                k => n
                    for (k, n) in coupling.wtables if !(n in last.(lg.tables))
            ]
        else
            Pair{String, Symbol}[]
        end
        cp = if coupling === nothing
            nothing
        else
            (;
                stability = coupling.bound, coupling.groups,
                explicit = [
                    i == gi && _given_count(solver) !== nothing
                        for i in eachindex(order)
                ],
                index = gi, whole = _WholeParams(coupling.wnames, params),
                steady = [
                    order[i][2] isa LatticeFields.Problems.QuasiSteady
                        for i in eachindex(order)
                ],
                rows0 = _steady_names(sys, allnames),
            )
        end
        rule = LatticeFields.Problems.GroupSubsteps(
            gspec, solver, dt; key = fp,
            texts = _PottsTexts(
                names, (;
                    filled = copy(cv.filled), infinite = _infinite_bounds(c, names),
                )
            ),
            coupling = cp
        )
        push!(
            groups,
            _FieldGroup(
                names, group, solver, prog, mplan, splan, arrays,
                lg.tables, params, rule, fp, opts, rtabs
            )
        )
    end
    return groups
end

# the fields of `names` whose declared `bounds` are not finite
function _infinite_bounds(c::CompiledPottsSystem, names)
    out = Symbol[]
    for x in _p(getfield(c, :sys), :variables)
        i = info(x)
        (i === nothing || i.role !== :field || !(i.name in names)) && continue
        b = get(i.options, :bounds, nothing)
        b === nothing || all(isfinite, b) || push!(out, i.name)
    end
    return out
end

# The group of a model whose only fields are aux fields `K ~ rhs`: no state
# field, only `aux:` kernels; its phase evaluates them once per MCS (`_AuxSteps`: 0
# substeps) The compile options of a field group (planned on the host for every backend):
# Float64 in its kernels only for a Float64 state, or when the group declares it (a
# `compute_type` or a field's `lattice_storage` of Float64), and then its kernels are
# registered as declared Float64 (the D-157 carve-out of the device scan). Cartesian
# indexing: the host loop hands each site its coordinates (a linear launch decodes them with
# an integer division per site, about 3x slower on the CPU)
function _field_options(c::CompiledPottsSystem, T::Type, solver, rate)
    narrow = T <: Union{Float16, Float32}
    # the group's own program: its fields (its own and those it reads) declared Float64
    # (not every group of the model when one field declares it)
    wide = LatticeFields.Problems.compute_type(solver, T) <: Float64 ||
        any(f -> f.fixed && f.storage == LatticeFields.IR.F64, rate.fields)
    return LatticeFields.Compile.CompileOptions(;
        T, float64_ok = !narrow || wide, lanes = :state, index = :cartesian,
        declared = narrow && wide
    )
end
# an aux field that LatticePDE added for a spatial operator across `Coarse` grids
# (`laplacian(c)`): no model variable holds it, so the binding allocates it and its `aux:`
# kernel fills it every window
_hidden_aux(k::AbstractString) = LatticePDE.is_crossgrid_key(k)
function _aux_group(c::CompiledPottsSystem, T::Type, dt)
    solver = ExplicitEuler()
    lg = _field_group_spec(c, Symbol[], T)
    gspec = lg.spec
    opts = _field_options(c, T, solver, gspec.rate)
    fused = LatticeFields.Compile.fuse_update(
        gspec.rate,
        LatticeFields.Problems.update_rule(solver)
    )
    group = LatticeFields.Problems.FieldGroup(
        gspec; alg = solver, program = LatticeFields.Compile.semantic(fused)
    )
    prog = group.program
    mplan, splan = LatticeFields.Problems.group_plans(
        group, solver, T, KernelAbstractions.CPU(), opts
    )
    function field_array(f)
        hidden = startswith(f.key, "domain:") || _hidden_aux(f.key)
        return (
            hidden ? CorePotts.BindingScratch() : CorePotts.Part((:site, Symbol(f.key))),
            nothing,
        )
    end
    arrays = Tuple(field_array(f) for f in prog.fields)
    fp = LatticeFields.Compile.fingerprint_text(fused; T)
    return _FieldGroup(
        Symbol[], group, solver, prog, mplan, splan, arrays,
        lg.tables, lg.params, _AuxSteps(), fp, opts
    )
end

# The parameters of the whole field system from a group's raw parameters (`praw`, with its
# tables), by name: a parameter the group does not read is `NaN`
struct _WholeParams
    wnames::Vector{Symbol}
    pnames::Vector{Symbol}
end
function (w::_WholeParams)(praw)
    pv = praw isa LatticeFields.Problems.ParamsTables ? praw.p : praw
    tabs = if praw isa LatticeFields.Problems.ParamsTables
        praw.tables
    else
        Pair{String, Vector{Float64}}[]
    end
    wp = Float64[
        (j = findfirst(==(n), w.pnames)) === nothing ? NaN : Float64(pv[j])
            for n in w.wnames
    ]
    return LatticeFields.Problems.with_tables(wp, tabs)
end

# The site phase writing every filled input of the fields (one launch per MCS)
function _field_fill_phase(c::CompiledPottsSystem, T)
    filled = _field_inputs(c, T)
    isempty(filled) && return nothing
    env = _site_env(T, :i, getfield(c, :gather_names); mcs = :mcs, key = :key)
    body = map(filled) do (name, ex, E)
        v = _fill_value(ex, env)
        # bounds: the site phase runs over i ∈ 1:nsites, every site column's length
        if E <: Bool
            :(@inbounds st.site.$name[i] = UInt8($v))
        else
            :(@inbounds st.site.$name[i] = $E($v))
        end
    end
    return CorePotts.SitePhase(
        _rgf(
            :(
                (st, p, ctx, key, mcs, i) -> begin
                    $(body...)
                    return nothing
                end
            )
        )
    )
end

# the field phases of a problem (in group order) and their at-init clamps
function _field_phases(c::CompiledPottsSystem, T, spec::SolverSpec)
    _has_fields(c) || return Any[], Any[]
    spec.discretization === nothing || return _discretized_phases(c, T, spec)
    groups = _field_groups(c, T, spec)
    dt = _field_dt(getfield(c, :sys))
    steps, clamps = Any[], Any[]
    fill = _field_fill_phase(c, T)
    fill === nothing || push!(steps, fill)
    log = _GENERATED[]
    for (j, g) in enumerate(groups)
        # the fingerprint hashes the semantic program of each group with its bindings
        # (D-016) (the last entry: no term outside the linearity classes, `ifelse` arms not
        # expanded)
        log === nothing || push!(
            log, Expr(
                :field_program, g.fingerprint, string(g.arrays), string(g.params),
                string(g.tables), _canonical_value(_least(g.substeps)),
                string(_bounded(g.substeps))
            )
        )
        ph = CorePotts.FieldPhase{Symbol(:__fields, j)}(
            g.group, g.alg, g.arrays; g.tables, g.params,
            substeps = g.substeps, dt,
            period = Float64(_p(getfield(c, :sys), :sweep).mcs_duration),
            g.options, T, g.rule_tables
        )
        push!(steps, ph)
        # the at-init phase: the masked-condition clamp (one substep of length zero; it also
        # evaluates the group's aux fields). For a group with aux fields (`K ~ rhs`) and no
        # mask, the aux fields evaluated at t0, so the first sweep reads `rhs`, not the
        # declared value: a group with no state takes its own step (0 substeps); a rate
        # group with state its `aux:` kernels alone, which never write the state (no update
        # rule, no `lower_bound` clip); a map group none (it would apply the map)
        mcs = Float64(_p(getfield(c, :sys), :sweep).mcs_duration)
        start = LatticeFields.Problems.starts_steady(g.alg)
        if !isempty(g.masks.launches) || g.substeps isa _AuxSteps
            push!(clamps, CorePotts.field_clamp(ph))
        end
        # the steady start (`init = :steady`): the group's steady state solved once by
        # `QuasiSteady` on the step's arrays, after the clamp (the masked values hold), then
        # its aux fields evaluated from it
        if start
            qa = LatticeFields.Problems.steady_start(g.alg)
            rule = LatticeFields.Problems.StartSubsteps(
                LatticeFields.Problems.GroupSubsteps(
                    g.group.spec, qa, dt;
                    key = g.fingerprint, texts = g.substeps.texts
                ), String[string(n) for n in g.names]
            )
            push!(
                clamps, CorePotts.FieldPhase{Symbol(:__fields, j, :_start)}(
                    g.group, qa, g.arrays; g.tables, g.params,
                    substeps = rule, dt, period = mcs, g.options, T, start = true
                )
            )
        end
        if _has_aux(g) && !(g.substeps isa _MapSteps) && !(g.substeps isa _AuxSteps) &&
                (start || isempty(g.masks.launches))
            push!(
                clamps, CorePotts.FieldPhase{Symbol(:__fields, j, :_aux)}(
                    g.group, ExplicitEuler(), g.arrays; g.tables,
                    g.params, substeps = _AuxSteps(), dt, period = mcs,
                    g.options, T, aux_only = true
                )
            )
        end
    end
    return steps, (fill === nothing ? clamps : Any[fill; clamps])
end

# The fields of a problem with a `discretization` other than the fused lattice one: the fill
# phase (the CPM inputs into their site arrays), then one host phase that steps the problem
# `discretize(Potts.fields(model), discretization; inputs)` over each MCS window with
# `field_solver`, from the fields' site arrays and back
function _discretized_phases(c::CompiledPottsSystem, T, spec::SolverSpec)
    sys = getfield(c, :sys)
    _field_dt(sys) == Float64(_p(sys, :sweep).mcs_duration) || throw(
        ArgumentError(
            string(
                "`discretization = ",
                repr(spec.discretization), "`: the fields of model `", nameof(sys),
                "` step in a sub-MCS `repeat`, which the ",
                "fused lattice fields run; leave `discretization` out"
            )
        )
    )
    F = fields(sys)
    filled = Dict{Symbol, Type}(n => E for (n, _, E) in _field_inputs(c, T))
    back = Dict{Symbol, Symbol}(Symbol(w) => g for (g, w) in _input_names(sys))
    inputs = Tuple{Symbol, Symbol, Type}[]
    for dv in ModelingToolkitBase.get_dvs(F)
        x = _unwrap(dv)
        ModelingToolkitBase.isinput(x) || continue
        op = Symbol(nameof(operation(x)))
        op = get(back, op, op)
        key = Symbol(something(LatticePDE.get_lattice_input_name(x), string(op)))
        st = SymbolicUtils.symtype(x)
        E = get(filled, op, _input_number_type(st, T))
        push!(inputs, (key, op, E))
    end
    names = Set{Symbol}(info(x).name for x in _p(sys, :parameters))
    params = Symbol[
        n
            for n in (
                Symbol(nameof(_unwrap(q)))
                for q in ModelingToolkitBase.get_ps(F)
            ) if n in names
    ]
    ph = _DiscretizedFields(
        F, spec.discretization, spec.field_solver,
        Symbol[info(x).name for (x, _) in getfield(c, :fields)],
        inputs, params, T, Float64(_p(sys, :sweep).mcs_duration),
        Dict{UInt, Tuple{WeakRef, Any}}(), ReentrantLock()
    )
    fill = _field_fill_phase(c, T)
    return fill === nothing ? (Any[ph], Any[]) : (Any[fill, ph], Any[fill])
end

# One integrator of the discretized fields per trajectory, keyed by the identity of its live
# state array (as `_AdaptiveODE`). The contract of a discretization (checked at build,
# `_check_discretized`): `discretize(pdesys, d; inputs = [name => array, …])` takes the CPM
# inputs by name, and its problem's integrator reads and writes each field by name
# (`getu`/`setu`) as a vector of the lattice's sites in column-major order, and sets each
# input and parameter by name (`setp`), as a `LatticeDiscretization`'s does.
struct _DiscretizedFields{D, A}
    pdesys::Any
    disc::D
    alg::A
    # the fields: their site arrays and their names in the problem
    fields::Vector{Symbol}
    # (name in the problem, site array, element type)
    inputs::Vector{Tuple{Symbol, Symbol, Type}}
    params::Vector{Symbol}                 # the model parameters the fields read
    T::Type
    dt::Float64                            # the MCS (`mcs_duration`)
    integrators::Dict{UInt, Tuple{WeakRef, Any}}
    lock::ReentrantLock
end

function (ph::_DiscretizedFields)(st, p, ctx, key, mcs, backend)
    return CorePotts.run_phase(ph, st, p, ctx, key, mcs, backend, nothing)
end

# the inputs by name, converted only when the site array's element type differs
function _input_values(ph::_DiscretizedFields, st)
    return [
        k => (a = getproperty(st.site, n); eltype(a) === E ? a : E.(a))
            for (k, n, E) in ph.inputs
    ]
end

function _discretized_refusal(ph::_DiscretizedFields, what)
    return ArgumentError(
        string(
            "`discretization = ", repr(ph.disc), "`: ", what,
            ". The contract: `discretize(Potts.fields(model), d; ",
            "inputs = [name => array, …])` returns a problem whose integrator reads and \
                writes each field by name as a vector ",
            "of the lattice's sites in column-major order (`getu`, `setu`) and sets each \
                input and parameter by name (`setp`)"
        )
    )
end

# the discretization's problem for the given inputs (a discretizer without `inputs` refused)
function _discretized_problem(ph::_DiscretizedFields, ins)
    hasmethod(
        SciMLBase.discretize, Tuple{typeof(ph.pdesys), typeof(ph.disc)},
        (:inputs,)
    ) ||
        throw(_discretized_refusal(ph, "`discretize` does not take `inputs` for this \
            discretization"))
    return SciMLBase.discretize(ph.pdesys, ph.disc; inputs = ins)
end

# At build and at `remake`: the problem of each discretized-fields phase meets the contract,
# for the state's input and field arrays
function _check_discretized(@nospecialize(f), st)
    SII = SymbolicIndexingInterface
    for e in f.phases.mcs, t in (e isa CorePotts.Repeat ? e.entries : (e,))
        for ph in (t isa Tuple ? t : (t,))
            ph isa _DiscretizedFields || continue
            # (a discretizer's own error, e.g. one taking `kwargs...` that cannot build this
            # system, refused as the contract)
            prob = try
                _discretized_problem(ph, _input_values(ph, st))
            catch err
                (isfatal(err) || err isa ArgumentError) && rethrow()
                throw(
                    _discretized_refusal(
                        ph, "its `discretize` failed: " *
                            sprint(showerror, err)
                    )
                )
            end
            for n in ph.fields
                SII.is_variable(prob, n) ||
                    throw(_discretized_refusal(ph, "its problem has no field `$n`"))
                l, sites = length(SII.getu(prob, n)(prob)), length(getproperty(st.site, n))
                l == sites ||
                    throw(_discretized_refusal(ph, "its field `$n` has $l values, the \
                        lattice $sites sites"))
            end
            for k in Iterators.flatten((first.(ph.inputs), ph.params))
                SII.is_parameter(prob, k) ||
                    throw(_discretized_refusal(ph, "its problem has no parameter or input \
                        `$k` to set"))
            end
        end
    end
    return nothing
end

# The integrator of a trajectory and the accessors built once with it
struct _DiscretizedIntegrator{I, SI, SP, SU, GU}
    integ::I
    set_inputs::SI      # one `setp` per input
    set_params::SP      # one `setp` per model parameter
    set_fields::SU      # one `setu` per field
    get_fields::GU      # one `getu` per field
    lastp::Ref{Any}                         # the parameter values last written
end

function _discretized_integrator(ph::_DiscretizedFields, ins, t0)
    SII = SymbolicIndexingInterface
    prob = SciMLBase.remake(_discretized_problem(ph, ins); tspan = (t0, t0 + ph.dt))
    # (nothing reads the solution: the fields are read from the integrator)
    integ = SciMLBase.init(
        prob, ph.alg; save_everystep = false, save_start = false, save_end = false
    )
    return _DiscretizedIntegrator(
        integ, Tuple(SII.setp(integ, k) for (k, _) in ins),
        Tuple(SII.setp(integ, n) for n in ph.params),
        Tuple(SII.setu(integ, n) for n in ph.fields), Tuple(
            SII.getu(integ, n)
                for n in ph.fields
        ), Ref{Any}(nothing)
    )
end

function CorePotts.run_phase(ph::_DiscretizedFields, st, p, ctx, key, mcs, backend, stats)
    backend isa KernelAbstractions.CPU || throw(
        ArgumentError(
            string(
                "`discretization = ", repr(ph.disc), "`: its ",
                "fields step on the host; run the problem on the CPU, or leave \
                    `discretization` out"
            )
        )
    )
    owner = st.ownership
    t0 = mcs * ph.dt
    ins = _input_values(ph, st)
    di = lock(() -> _cached_integrator(ph.integrators, owner), ph.lock)
    if di === nothing
        di = _discretized_integrator(ph, ins, t0)
        lock(() -> _cache_integrator!(ph.integrators, owner, di), ph.lock)
    end
    return _step_discretized!(di, ph, st, p, ins, t0, mcs, stats)
end

# One window on the cached integrator (a function barrier: `di` comes from an untyped cache)
function _step_discretized!(
        di::_DiscretizedIntegrator, ph::_DiscretizedFields, st, p, ins, t0, mcs, stats
    )
    integ = di.integ
    # the inputs, the model's parameter values when they change (`remake(prob; p)`,
    # `integ.ps[k] = v`), then the fields; `reinit!` from that state starts the window (and
    # its first step size) from them, whatever the algorithm keeps internally
    foreach(((s, (_, v)),) -> s(integ, v), zip(di.set_inputs, ins))
    if di.lastp[] !== p
        foreach(((s, n),) -> s(integ, p[n]), zip(di.set_params, ph.params))
        di.lastp[] = p
    end
    foreach(
        ((s, n),) -> s(integ, vec(getproperty(st.site, n))),
        zip(di.set_fields, ph.fields)
    )
    SciMLBase.reinit!(integ, copy(integ.u); t0, tf = t0 + ph.dt, erase_sol = true)
    SciMLBase.solve!(integ)
    if !SciMLBase.successful_retcode(integ.sol)
        LatticeFields.Exec.VERBOSE[] &&
            @warn "Fields failed at MCS $mcs: retcode $(integ.sol.retcode)"
        stats !== nothing && (stats.ode_code = integ.sol.retcode)
        return 0
    end
    # (host arrays: the phase refuses a device backend above)
    foreach(
        ((g, n),) -> vec(getproperty(st.site, n)) .= g(integ),
        zip(di.get_fields, ph.fields)
    )
    return 0
end

# At build: each field phase's substep count at the problem's parameters (the policy's
# refusals, and its warning for an explicit count the bound does not cover)
# (host, once per problem)
function _check_field_substeps(@nospecialize(f), @nospecialize(p); tspan = nothing)
    # (the steady starts too, `init = :steady`: their steady refusals)
    for e in (f.phases.mcs..., f.phases.at_init),
            t in (e isa CorePotts.Repeat ? e.entries : (e,))

        t isa Tuple || continue
        for ph in t
            ph isa CorePotts.FieldPhase && !ph.init &&
                ph.substeps isa Union{
                LatticeFields.Problems.GroupSubsteps, LatticeFields.Problems.StartSubsteps,
            } ||
                continue
            pp = LatticeFields.Problems.with_tables(
                Float64[CorePotts.praw(ph, p)...], CorePotts.table_values(ph, p)
            )
            # (the run's time span, MCS times the step length: a Robin face that reads the
            # time is checked over it)
            sp = if tspan === nothing ||
                    !(ph.substeps isa LatticeFields.Problems.GroupSubsteps)
                nothing
            else
                (Float64(tspan[1]) * ph.period, Float64(tspan[2]) * ph.period)
            end
            sp === nothing ? ph.substeps(pp) : ph.substeps(pp; span = sp)
        end
    end
    return nothing
end
