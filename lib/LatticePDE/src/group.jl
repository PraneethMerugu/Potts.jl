# `lower_group`: a PDESystem's field group lowered once to the IR boundary,
# a `GroupSpec`: the rate program (no update: a `FieldGroup` fuses each algorithm's update
# into it, LatticeFields' `fuse_update`), its state, the fields it reads from other groups,
# the stability bound and the texts of the terms the bound does not see.

"""
    lower_group(pdesys, disc; fields = nothing, values = true, bound = true, filled = (),
                steady = String[]) -> GroupSpec

The field group of the state variables `fields` of `pdesys` (all of them by default),
lowered on the lattice `disc` to its `GroupSpec` (`LatticeFields.Problems.GroupSpec`):
the rate program (`symbolic_discretize` in rate form: `rate:c` kernels store `∂c`), the
state keys, the kind (`:rate` or `:map`), the masks, the stability bound, the parameter,
table and input keys and the linearity classes.

**The group cut.** A state variable outside `fields` is read by the group from its own array:
it becomes an input of the group (its key in `spec.external`), and its equations, conditions
and initial values leave the group. Its terms in the group's rates are then sources of the
group's step (the bound of the group's rows does not count them), as a front end with two
field groups steps them (one after the other, each reading the other's current values).

**Values.** With `values = false` the caller binds the parameter and table values itself (a
front end with its own parameter object, such as Potts): the system's defaults are not read,
so a parameter whose default reads other parameters is not folded into the equations (it
stays a slot) and an array parameter needs no default.

**Slots.** The spec's parameter slots, tables and inputs keep the program's order (`string`
of each is its key). A slot holds its default when `values` (else `nothing`) and its role
(`:computed` with its expression for a computed default, `:clock` for the clock's slot); an
input holds its element type, its declared bounds, its default and whether it is `filled`:
the input keys in `filled` are written by the front end at every step (Potts' CPM reads).

**Bound.** With `bound = false` the stability bound is not built yet: the spec's `stability`
is a [`DeferredBound`](@ref), and [`resolve_bound`](@ref) builds it when the group is first
stepped (a front end that lowers a group to check it, before any problem exists, does not pay
for the bound).

**Steady rows.** A steady equation `0 ~ rhs` is lowered as the rate row of the field it
determines (`steady_rows`), and the spec's `steady` lists those fields: their groups
take `QuasiSteady` only. `steady` names more such fields (a front end that writes its steady
rows as rates itself). A system with no time is a steady system (`spec.timefree`).
"""
function lower_group(
        sys::PDESystem, disc::LatticeDiscretization; fields = nothing, values::Bool = true, bound::Bool = true,
        filled = (), steady = String[]
    )
    return _lower_group(sys, disc; fields, values, bound, filled, steady).spec
end

"""
    DeferredBound

The stability bound of a group lowered with `lower_group(…; bound = false)`, not built yet: it
holds the lowered system that [`resolve_bound`](@ref) builds the bound from. Calling it is an
error that names `resolve_bound`.
"""
struct DeferredBound
    cf::Any
    sys::Any
end
function (::DeferredBound)(p)
    throw(
        ArgumentError(
            "the group's stability bound is not built yet (`lower_group(…; bound = false)`); " *
                "build it with `LatticePDE.resolve_bound(spec)`"
        )
    )
end

"""
    resolve_bound(spec) -> GroupSpec

`spec` with its stability bound built (and the terms the bound cannot see in `texts.terms`)
when it was lowered with `bound = false`; else `spec` itself.
"""
function resolve_bound(spec::Problems.GroupSpec)
    d = spec.stability
    d isa DeferredBound || return spec
    stab = stability_bound(d.cf, d.sys)
    return Problems.GroupSpec(
        spec.rate; spec.state, spec.external, spec.params, spec.tables, spec.inputs, spec.init,
        spec.kind, spec.clock, stability = stab, route = spec.texts.route, terms = copy(stab.terms), spec.linearity,
        spec.operator, spec.steady, spec.timefree
    )
end

# `values = false`: the front end binds the parameter and table values itself (Potts: its
# parameter object, with its own computed parameters), so the system's computed defaults are
# not read (`_fold_computed`) and its tables not checked (`_check_tables`)
function _lower_group(
        sys::PDESystem, disc::LatticeDiscretization; fields = nothing, values::Bool = true, bound::Bool = true,
        filled = (), steady = String[], timefree::Bool = false
    )
    _check_parts(sys)
    sys, rows, tf = steady_form(sys, length(disc.grid.dims))
    steady, timefree = unique!(String[collect(String, steady); rows]), timefree || tf
    sys = crossgrid_form(sys)                           # an operator across `Coarse` grids as an aux field
    check_one_kind(sys)                                 # (the whole system, before any cut)
    derived, computed, defaults = Pair[], Pair[], Pair[]
    values && (sys = robin_slots(sys))                  # a Robin coefficient of parameters: a computed one
    values && ((sys, derived, computed, defaults) = _fold_computed(sys))
    external = String[]
    fields === nothing || ((sys, external) = _group_cut(sys, fields))
    cf = symbolic_discretize(sys, disc)                 # the rate form: no update
    _check_aux_offsets(cf.program, sys)                 # (an aux field read across a closed face)
    values && _check_tables(cf, sys)
    s = cf.program
    hasmap = any(k -> startswith(k.key, "map:"), s.kernels)
    stab = if hasmap
        p -> NaN
    elseif bound
        stability_bound(cf, sys)
    else
        DeferredBound(cf, sys)
    end
    spec = Problems.GroupSpec(
        s; state = _states(s), external, kind = hasmap ? :map : :rate, clock = disc.clock,
        init = [k.key for k in s.kernels if any(q -> startswith(k.key, q), ("mask:", "domain:"))], stability = stab,
        params = _param_slots(cf, defaults, values), tables = _table_specs(cf, values),
        inputs = _input_specs(cf, sys, s, filled),
        terms = stab isa StabilityBound ? copy(stab.terms) : String[], linearity = cf.linearity,
        operator = hasmap ? nothing : DeferredOperator(cf, sys, disc),
        steady = String[k for k in _states(s) if k in steady], timefree
    )
    return (; spec, cf, sys, derived, computed, defaults)
end

# The system of the group of `fields`: every other state variable an input (read from its
# array), with its equations and its conditions (faces, masks, initial values) left out
function _group_cut(sys::PDESystem, fields)
    keep = Any[_opof(f) for f in fields]
    dvops = Any[_opof(v) for v in get_dvs(sys)]
    for (f, op) in zip(fields, keep)
        any(o -> isequal(o, op), dvops) || _dverr("`fields`: `$f` is not a dependent variable of `$(nameof(sys))`")
    end
    cut, external = Any[], String[]
    dvs = map(get_dvs(sys)) do v
        u = unwrap(v)
        op = _opof(u)
        (ModelingToolkitBase.isinput(u) || any(o -> isequal(o, op), keep)) && return v
        push!(cut, op)
        push!(external, _name(op))
        return Symbolics.wrap(SymbolicUtils.setmetadata(u, ModelingToolkitBase.VariableInput, true))
    end
    isempty(cut) && return sys, external
    mine(eq) = (l = unwrap(eq.lhs); !(_reads(l, cut) && !_reads(l, keep)))
    eqs = filter(mine, get_eqs(sys))
    # a cut field that a spatial operator of the group reads keeps its face conditions
    faced = operand_reads(eqs, cut)
    dvs = map(dvs) do v
        any(o -> isequal(o, _opof(unwrap(v))), faced) || return v
        return Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(v), LatticeCutField, true))
    end
    bcmine(eq) = mine(eq) || _reads(unwrap(eq.lhs), faced)
    ics = _ics(sys)
    ic2 = Dict(k => v for (k, v) in ics if !any(o -> isequal(o, _opof(k)), cut))
    out = PDESystem(
        eqs, filter(bcmine, get_bcs(sys)), get_domain(sys), get_ivs(sys), dvs, _params(sys);
        name = nameof(sys), initial_conditions = ic2
    )
    return out, external
end

# The spec's slots, in the program's order: the parameter slots (the
# default as given when `values`; a computed parameter's expression as written), the tables
# (their values when `values`) and the inputs (element type, declared bounds, default, filled)
function _param_slots(cf::CompiledField, computed, values::Bool)
    comp = Dict{String, String}(string(first(c)) => as_written(string(last(c))) for c in computed)
    out = Problems.ParamSlot[]
    for (i, q) in enumerate(cf.params)
        k = string(q)
        d = values && i <= length(cf.defaults) ? cf.defaults[i] : nothing
        d isa AbstractFloat && isnan(d) && (d = nothing)
        role = if _isclock(q)
            :clock
        elseif haskey(comp, k)
            :computed
        else
            :base
        end
        push!(out, Problems.ParamSlot(k; text = _clocktext(k), default = d, role, derivation = get(comp, k, nothing)))
    end
    return out
end
function _table_specs(cf::CompiledField, values::Bool)
    return Problems.TableSpec[Problems.TableSpec(String(first(t)); values = values ? last(t) : nothing) for t in cf.tables]
end
function _input_specs(cf::CompiledField, sys::PDESystem, s, filled)
    fills = Set{String}(string(f) for f in filled)
    vars = Dict{String, Any}()
    for v in unwrap.(get_dvs(sys))
        ModelingToolkitBase.isinput(v) || continue
        ks = get(cf.keys, _opof(v), String[])
        for (i, k) in enumerate(ks)
            vars[k] = (v, length(ks) == 1 ? 0 : i)
        end
    end
    defaults = Dict{String, Any}(_input_defaults(cf, sys))
    out = Problems.InputSpec[]
    for f in s.fields
        f.role == :input || continue
        vi = get(vars, f.key, nothing)
        E, b, name = Real, (-Inf, Inf), f.key
        if vi !== nothing
            v, i = vi
            E = eltype(SymbolicUtils.symtype(v))
            E <: Bool || E <: Integer || (E = Real)
            i == 0 && (b = _input_bounds(v))
            n = get_lattice_input_name(v)
            n === nothing || (name = i == 0 ? n : "$n[$i]")
        end
        push!(
            out, Problems.InputSpec(
                f.key; name, eltype = E, bounds = b, default = get(defaults, f.key, nothing),
                filled = f.key in fills
            )
        )
    end
    return out
end
