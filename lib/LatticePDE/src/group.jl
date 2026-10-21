# `lower_group` (F2 design §2.5): a PDESystem's field group lowered once to the IR boundary,
# a `GroupSpec`: the rate program (no update: a `FieldGroup` fuses each algorithm's update
# into it, LatticeFields' `fuse_update`), its state, the fields it reads from other groups,
# the stability bound and the texts of the terms the bound does not see.

"""
    lower_group(pdesys, disc; fields = nothing, values = true, bound = true) -> GroupSpec

The field group of the state variables `fields` of `pdesys` (all of them by default),
lowered on the lattice `disc` to its [`GroupSpec`](@ref LatticeFields.Problems.GroupSpec):
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

**Bound.** With `bound = false` the stability bound is not built yet: the spec's `stability`
is a [`DeferredBound`](@ref), and [`resolve_bound`](@ref) builds it when the group is first
stepped (a front end that lowers a group to check it, before any problem exists, does not pay
for the bound).
"""
lower_group(sys::PDESystem, disc::LatticeDiscretization; fields = nothing, values::Bool = true, bound::Bool = true) =
    _lower_group(sys, disc; fields, values, bound).spec

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
(::DeferredBound)(p) = throw(ArgumentError("the group's stability bound is not built yet (`lower_group(…; bound = false)`); " *
                                           "build it with `LatticePDE.resolve_bound(spec)`"))

"""
    resolve_bound(spec) -> GroupSpec

`spec` with its stability bound built (and the terms the bound cannot see in `texts.terms`)
when it was lowered with `bound = false`; else `spec` itself.
"""
function resolve_bound(spec::Problems.GroupSpec)
    d = spec.stability
    d isa DeferredBound || return spec
    stab = stability_bound(d.cf, d.sys)
    return Problems.GroupSpec(spec.rate; spec.state, spec.external, spec.params, spec.tables, spec.inputs, spec.init,
        spec.kind, spec.clock, stability = stab, route = spec.texts.route, terms = copy(stab.terms), spec.linearity)
end

# `values = false`: the front end binds the parameter and table values itself (Potts: its
# parameter object, with its own computed parameters), so the system's defaults are neither
# folded (`_fold_computed`) nor checked (`_check_tables`)
function _lower_group(sys::PDESystem, disc::LatticeDiscretization; fields = nothing, values::Bool = true, bound::Bool = true)
    _check_parts(sys)
    derived, computed = Pair[], Pair[]
    values && ((sys, derived, computed) = _fold_computed(sys))
    external = String[]
    fields === nothing || ((sys, external) = _group_cut(sys, fields))
    cf = symbolic_discretize(sys, disc)                 # the rate form: no update
    values && _check_tables(cf, sys)
    s = cf.program
    hasmap = any(k -> startswith(k.key, "map:"), s.kernels)
    stab = hasmap ? (p -> NaN) : bound ? stability_bound(cf, sys) : DeferredBound(cf, sys)
    spec = Problems.GroupSpec(s; state = _states(s), external, kind = hasmap ? :map : :rate,
        init = [k.key for k in s.kernels if startswith(k.key, "mask:")], stability = stab,
        params = String[string(p) for p in cf.params], tables = String[first(t) for t in cf.tables],
        inputs = String[f.key for f in s.fields if f.role == :input],
        terms = stab isa StabilityBound ? copy(stab.terms) : String[], linearity = cf.linearity)
    return (; spec, cf, sys, derived, computed)
end

# The system of the group of `fields`: every other state variable an input (read from its
# array), with its equations and its conditions (faces, masks, initial values) left out
function _group_cut(sys::PDESystem, fields)
    keep = Any[_opof(f) for f in fields]
    dvops = Any[_opof(v) for v in sys.dvs]
    for (f, op) in zip(fields, keep)
        any(o -> isequal(o, op), dvops) || _dverr("`fields`: `$f` is not a dependent variable of `$(nameof(sys))`")
    end
    cut, external = Any[], String[]
    dvs = map(sys.dvs) do v
        u = unwrap(v)
        op = _opof(u)
        (ModelingToolkitBase.isinput(u) || any(o -> isequal(o, op), keep)) && return v
        push!(cut, op)
        push!(external, _name(op))
        return Symbolics.wrap(SymbolicUtils.setmetadata(u, ModelingToolkitBase.VariableInput, true))
    end
    isempty(cut) && return sys, external
    mine(eq) = (l = unwrap(eq.lhs); !(_reads(l, cut) && !_reads(l, keep)))
    ics = _ics(sys)
    ic2 = Dict(k => v for (k, v) in ics if !any(o -> isequal(o, _opof(k)), cut))
    out = PDESystem(filter(mine, sys.eqs), filter(mine, sys.bcs), getfield(sys, :domain), sys.ivs, dvs, _params(sys);
        name = nameof(sys), initial_conditions = ic2)
    return out, external
end
