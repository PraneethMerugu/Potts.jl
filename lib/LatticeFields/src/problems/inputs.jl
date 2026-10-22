# Input fields of a problem (fields the program reads but never writes: a coupling, a
# domain mask, a kind map) and the parameter checks a front end supplies. An input has a value
# only when it is given: an unset input is an error at `init` (or when an ODE problem is
# built), never a silent zero.

# the input fields of `p`, in field order
_input_keys(p::Program) = String[f.key for f in p.fields if f.role == :input]

# the length of input `key`'s array (sites × components of its first level)
function _input_length(p::Program, key::AbstractString)
    f = p.fields[fieldid(p, key)]
    return nsites(p, f.levels[1]) * ncomp(f)
end

# a value given for input `key`: an array with one entry per site (and component), or a number
# for every site; returned as a flat host vector (`Bool` arrays are kept as given)
function _input_value(p::Program, key::AbstractString, v, name = key; bool::Bool = false,
        bounds::Tuple{Float64, Float64} = (-Inf, Inf))
    n = _input_length(p, key)
    v isa Number && (_check_integer(p, key, name, v; bool, bounds); return fill(v, n))
    v isa AbstractArray || throw(ArgumentError(
        "input `$name`: give an array with one value per site ($n) or a number; got a $(typeof(v))"))
    length(v) == n || throw(ArgumentError(
        "input `$name`: the array has $(length(v)) values; the field has $n (one per site$(n == nsites(p, 0) ? "" : " and component"))"))
    w = vec(collect(v))                       # on the host (a device array is copied here)
    _check_integer(p, key, name, w; bool, bounds)
    return w
end

"""
    resolve_inputs(p, index, given, base = nothing) -> Vector{Pair{String, Any}}

The value of every input field of program `p` (in field order): `base` (a previous list) or
unset (`nothing`), replaced by the `given` pairs (`symbol => values`, the symbol looked up in
`index`, or the field key).
"""
function resolve_inputs(p::Program, index, given, base = nothing)
    ks = _input_keys(p)
    vals = Dict{String, Any}(k => nothing for k in ks)
    base === nothing || foreach(((k, v),) -> vals[k] = v, base)
    for (s, v) in given
        k = index isa LatticeIndex ? input_key(index, s) : nothing
        k === nothing && s isa AbstractString && s in ks && (k = String(s))
        k === nothing && _not_input(s, [input_name(index, x) for x in ks])
        vals[k] = _input_value(p, k, v, input_name(index, k); bool = is_bool_input(index, k),
            bounds = input_bounds(index, k))
    end
    return Pair{String, Any}[k => vals[k] for k in ks]
end

# a symbol that is not an input: an array input (whose components are the inputs) asks for
# each component, else the inputs are listed
function _not_input(s, ks)
    m = match(r"^\(?([^\s(⋆\[]+)", string(s))
    name = m === nothing ? string(s) : m.captures[1]
    comps = [x for x in ks if startswith(x, name * "[")]
    isempty(comps) || throw(ArgumentError(string("`", name, "` is an array input: give each component, ",
        "`inputs = [", join(("$(_route(x)) => values" for x in comps), ", "), "]` (or the components of the array ",
        "variable)")))
    throw(ArgumentError(string("`", name, "` is not an input field of the problem",
        isempty(ks) ? " (it has none)" : " (its inputs: " * join(("`$x`" for x in ks), ", ") * ")")))
end

# an integer input (a kind map, a mask) takes integer values in its type's range, a Bool input
# (`bool`: declared `::Bool`) only Bool or 0/1; a bad value is named with its site
function _check_integer(p::Program, key::AbstractString, name, v; bool::Bool = false,
        bounds::Tuple{Float64, Float64} = (-Inf, Inf))
    f = p.fields[fieldid(p, key)]
    # the declared bounds (`bounds = (lo, hi)` metadata): the stability bound relies on them
    lo, hi = bounds
    out = (lo == -Inf && hi == Inf) ? nothing : findfirst(x -> !(lo <= x <= hi), v isa Number ? (v,) : v)
    out === nothing || throw(ArgumentError(string("input `", name, "` is declared with bounds (", _bnum(lo), ", ",
        _bnum(hi), "); got ", (v isa Number ? v : v[out]),
        (v isa Number ? "" : " at site $(Tuple(CartesianIndices(_input_dims(p, f))[out]))"),
        "; give values inside the bounds (or declare the bounds the values need)")))
    isfloat(f.storage) && return nothing
    T = juliatype(f.storage)
    ok(x) = x isa Bool || (bool ? (x == 0 || x == 1) : isinteger(x) && typemin(T) <= x <= typemax(T))
    bad = findfirst(!ok, v isa Number ? (v,) : v)
    bad === nothing && return nothing
    dims = _input_dims(p, f)
    throw(ArgumentError(string("input `", name, "` holds ", bool ? "a Bool mask (true/false or 0/1)" :
        "integer values (a kind map: $T)", "; got ", (v isa Number ? v : v[bad]),
        (v isa Number ? "" : " at site $(Tuple(CartesianIndices(dims)[bad]))"))))
end

# the spelling of input `name` in a route that runs: `:kind`, or `"vel[1]"` for a name that
# is not an identifier
_route(name::AbstractString) = Base.isidentifier(name) ? ":" * name : repr(String(name))

"""
    input_name(index, key) -> String

The name of input field `key` as the user writes it (`kind` for a generated `kind__in`, the
`input_name` metadata of its variable), else the key.
"""
input_name(ix::LatticeIndex, key::AbstractString) = get(ix.inputnames, key, String(key))
input_name(_, key::AbstractString) = String(key)
# the declared bounds `(lo, hi)` of input `key`, as the index records (`(-Inf, Inf)`: none)
input_bounds(ix::LatticeIndex, key::AbstractString) = get(ix.inputbounds, key, (-Inf, Inf))
input_bounds(_, ::AbstractString) = (-Inf, Inf)
_input_dims(p, f) = ncomp(f) == 1 ? leveldims(p, f.levels[1]) : (leveldims(p, f.levels[1])..., ncomp(f))
_bnum(x) = isinteger(x) && isfinite(x) ? string(Int(x)) : string(x)   # a bound or value as A prints it (`0`, not `0.0`)
# whether input `key` is declared Bool (a 0/1 mask), as the index records
is_bool_input(ix::LatticeIndex, key::AbstractString) = key in ix.boolinputs
is_bool_input(_, ::AbstractString) = false

# an input with no value is an error naming it; `built`: the problem exists already (an owned
# problem at `init`, which `remake(prob; inputs)` can still give values), else it is being
# built (an ODE problem, whose inputs are fixed when it is built); `index` gives the names
function check_inputs_set(inputs; built::Bool = true, index = nothing)
    unset = [input_name(index, k) for (k, v) in inputs if v === nothing]
    isempty(unset) || throw(ArgumentError(string("the input field",
        length(unset) == 1 ? " " : "s ", join(("`$k`" for k in unset), ", "), length(unset) == 1 ? " has" : " have",
        " no value (an unset input is not read as zero): give ", length(unset) == 1 ? "it" : "them",
        " with `inputs = [", join((_route(u) * " => values" for u in unset), ", "), "]` where the problem is built",
        built ? ", or `remake(prob; inputs = …)`" : "", "; a variable with a default ",
        "(`dom(..)::Bool = true [input = true]`) needs none")))
    return nothing
end

# upload the input values into the store's (only) slot of each input field
function upload_inputs!(st::FieldStore, p::Program, inputs; index = nothing)
    check_inputs_set(inputs; index)
    for (k, v) in inputs
        _set_input!(st, p, k, v)
    end
    return st
end
function _set_input!(st::FieldStore, p::Program, key::AbstractString, v)
    a = array(st, fieldid(p, key), :cur)
    copyto!(a, convert(Vector{eltype(a)}, v))
    return a
end

"""
    ParamsTables(p, tables, inputs = [])

The raw parameters `p` with the problem's tables (`key => values`) and the current host
values of the inputs the bound reads in an index (`key => array shaped by site`, or a
number; [`bound_inputs`](@ref)), as the stability hooks receive them ([`with_tables`](@ref)):
indexed like `p`, so a bound that reads only scalars needs no change; a front end's bound
reads the table values from `tables` (a coefficient `Dk[i]` or `at(Dk, kind)`) and the index
values from `inputs`. An input the front end fills on the device every step is not passed
(its declared bounds hold).
"""
struct ParamsTables{P}
    p::P
    tables::Vector{Pair{String, Vector{Float64}}}
    inputs::Vector{Pair{String, Any}}
end
ParamsTables(p, tables) = ParamsTables(p, tables, Pair{String, Any}[])
Base.getindex(w::ParamsTables, i...) = w.p[i...]
Base.length(w::ParamsTables) = length(w.p)
Base.iterate(w::ParamsTables, s...) = iterate(w.p, s...)
Base.eltype(::Type{ParamsTables{P}}) where {P} = eltype(P)
"""
    with_tables(p, tables; inputs = [])

`p` as the stability hooks take it: `ParamsTables(p, tables, inputs)` when there are tables
or inputs, else `p`. The hooks read the tables in Float64 on their primal values (a policy, as
for the parameters: a BigFloat table is rounded and a Dual table drops its derivative parts
here only; the problem keeps the values as given).
"""
with_tables(p, tables; inputs = ()) = isempty(tables) && isempty(inputs) ? p :
                                      ParamsTables(p, Pair{String, Vector{Float64}}[k => _primal64(v) for (k, v) in tables],
                                          Pair{String, Any}[inputs...])
_primal64(v::Vector{Float64}) = v
_primal64(v) = Float64[Float64(primal(x)) for x in v]

"""
    bound_inputs(stability) -> Vector{String}

The keys of the inputs whose current values the stability bound reads (an index of a table
read: the bound evaluates index 0 only where the values reach it). The default is none.
"""
bound_inputs(stability) = String[]

"""
    check_parameters(stability, p)

A front end's parameter check at raw parameters `p` (primal values), run before stepping and
at every parameter change: it throws for values no step count makes valid (LatticePDE:
negative diffusion). The default checks nothing.
"""
check_parameters(stability, p) = nothing

"""
    seen_bound(stability, p) -> Float64

A bound on the spectral radius over the terms the stability bound sees, used to raise an
explicit substep count (`NaN` when there is none). The default is `stability(p)`.
"""
seen_bound(stability, p) = Float64(stability(p))

"""
    unbounded_reason(stability, p) -> Union{Nothing, String}

Why `stability(p)` has no value (the terms it cannot see, by name), for the substep error; the
default gives none.
"""
unbounded_reason(stability, p) = nothing

"""
    unbounded_key(stability, p) -> Union{Nothing, String}

The same reason as [`unbounded_reason`](@ref) without values: the terms and the causes
only (no entry, no parameter value), so a warning keyed on it is given once per program,
term and cause, however many values a sweep sets. The default is `unbounded_reason`.
"""
unbounded_key(stability, p) = unbounded_reason(stability, p)

"""
    check_bounds(p, index)

The declared `bounds = (lo, hi)` of each parameter of `index` hold for the values `p` (F2-14,
FE-18): an `ArgumentError` names the first parameter outside them, in slot order, with its
bounds as front end A prints them (`(0, 2)`). Every write checks it before anything changes.
"""
function check_bounds(p, index)
    index isa LatticeIndex || return nothing
    # base parameters first (a write names the parameter written), then computed ones (F2-15)
    for i in sort!(collect(keys(index.parambounds)); by = i -> (computed_slot(index, i) !== nothing, i))
        lo, hi = index.parambounds[i]
        v = primal(p[i])
        isnan(v) || lo <= v <= hi || throw(ArgumentError(_bounds_message(index, i, v, lo, hi)))
    end
    return nothing
end
function _bounds_message(index, i, v, lo, hi)
    head = string("parameter `", parameter_name(index, i), "` = ", v, " is outside its declared bounds (", _bnum(lo), ", ",
        _bnum(hi), ")")
    # a computed parameter: the inputs to change (review S4 of batch 5)
    k = computed_slot(index, i)
    why = k === nothing ? nothing : get(index.derived, index.key(k), nothing)
    why === nothing || return string(head, ": ", why)
    return string(head, ": give a value in them, or change `bounds` in its declaration")
end
# the values `p` with the pairs `kv` (parameter → value) written, within their bounds (a write
# of the ODE path, refused before it happens)
function check_bounds(p, index, kv; tables = nothing)
    index isa LatticeIndex && !isempty(index.parambounds) || return nothing
    q = Vector{Any}(collect(p))
    for (k, v) in kv
        table_key(index, k) === nothing || continue
        i = SII.parameter_index(index, k)
        i isa Integer && v isa Real && (q[i] = v)
    end
    tables === nothing || derive!(q, tables, index)    # the computed slots follow (F2-15)
    return check_bounds(q, index)
end

# a parameter whose value is NaN (no value given) is an error naming it; `built` as for
# `check_inputs_set` (a problem being built has no `remake` yet)
function check_values(p, index; built::Bool = true)
    check_bounds(p, index)          # a declared `bounds = (lo, hi)` holds at every write (F2-14, FE-18)
    for i in eachindex(p)
        isnan(primal(p[i])) || continue
        name = index isa LatticeIndex ? parameter_name(index, i) : "#$i"
        throw(ArgumentError(string("parameter `", name, "` has no value (it is NaN): give it a default ",
            "(`@parameters ", name, " = v`)", built ? string(" or set it with `remake(prob; p = [", name, " => v])`, or on an integrator ",
                                                     "`setp(integ, ", name, ")(integ, v)`") :
                                              string(" or a value in the system's `initial_conditions` (`", name, " => v`)"))))
    end
    return nothing
end
