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
    is_input_function(v) && throw(ArgumentError(string("input `", name, "`: a function of the time is given where ",
        "the problem is built, `discretize(sys, disc; inputs = [", name, " => t -> values])` or `remake(prob; inputs = …)`; ",
        "a write on an integrator takes an array with one value per site (", n, ") or a number")))
    v isa AbstractArray || throw(ArgumentError(
        "input `$name`: give an array with one value per site ($n) or a number; got a $(typeof(v))"))
    length(v) == n || throw(ArgumentError(
        "input `$name`: the array has $(length(v)) values; the field has $n (one per site$(n == nsites(p, 0) ? "" : " and component"))"))
    w = vec(collect(v))                       # on the host (a device array is copied here)
    _check_integer(p, key, name, w; bool, bounds)
    return w
end

"""
    resolve_inputs(p, index, given, base = nothing; t0 = nothing) -> Vector{Pair{String, Any}}

The value of every input field of program `p` (in field order): `base` (a previous list) or
unset (`nothing`), replaced by the `given` pairs (`symbol => values`, the symbol looked up in
`index`, or the field key). A value that is a function of the time ([`is_input_function`](@ref))
gives its value at `t0` (a problem with no start time takes none); [`input_functions`](@ref)
keeps the function.
"""
function resolve_inputs(p::Program, index, given, base = nothing; t0 = nothing)
    ks = _input_keys(p)
    vals = Dict{String, Any}(k => nothing for k in ks)
    base === nothing || foreach(((k, v),) -> vals[k] = v, base)
    for (s, v) in given
        k = _given_input_key(p, index, s, ks)
        name = input_name(index, k)
        if is_input_function(v)
            t0 === nothing && throw(ArgumentError(string("input `", name, "`: this problem takes input values, ",
                "not a function of the time; give an array with one value per site or a number")))
            vals[k] = _host_input(p, k, _call_input(v, t0, name), name, index)
        else
            vals[k] = _input_value(p, k, v, name; bool = is_bool_input(index, k), bounds = input_bounds(index, k))
        end
    end
    return Pair{String, Any}[k => vals[k] for k in ks]
end
# the field key of the input a given pair names (its symbol in `index`, or the key itself)
function _given_input_key(p::Program, index, s, ks = _input_keys(p))
    k = index isa LatticeIndex ? input_key(index, s) : nothing
    k === nothing && s isa AbstractString && s in ks && (k = String(s))
    k === nothing && _not_input(s, [input_name(index, x) for x in ks])
    return k
end

"""
    is_input_function(v) -> Bool

Whether an input value `v` is a function of the time (F4-B1): anything that is not a number,
an array or `nothing` (an anonymous function `t -> values`, a named function, an
interpolation object). The run calls it as `v(t)`, which returns an array with one value per
site or a number.
"""
is_input_function(v) = !(v isa Union{Number, AbstractArray, Nothing})

"""
    input_functions(p, index, given, base = []) -> Vector{Pair{String, Any}}

The inputs of `given` that are functions of the time, `key => f`, over those of `base`: a
function replaces the input's previous one, and a value removes it (the input is constant
again).
"""
function input_functions(p::Program, index, given, base = Pair{String, Any}[])
    out = Pair{String, Any}[k => f for (k, f) in base]
    ks = _input_keys(p)
    for (s, v) in given
        k = _given_input_key(p, index, s, ks)
        filter!(x -> first(x) != k, out)
        is_input_function(v) && push!(out, k => v)
    end
    return out
end

# the value of input function `f` at time `t`, refused in the user's words when `f` takes no time
function _call_input(f::F, t, name) where {F}
    applicable(f, t) || throw(ArgumentError(string("input `", name, "`: a value that is not an array or a number is ",
        "a function of the time, called as `f(t)`; the given `", typeof(f), "` takes no time argument. Give ",
        "`", name, " => t -> values`")))
    return f(t)
end
# the host values of an input function's result: a vector of the input's host type (Float64 for
# a float field, its integer type for a kind map or a mask), so later results are written into it
# in place
function _host_input(p::Program, key::AbstractString, v, name, index)
    _check_plain(v, name)
    w = _input_value(p, key, v, name; bool = is_bool_input(index, key), bounds = input_bounds(index, key))
    f = p.fields[fieldid(p, key)]
    return convert(Vector{isfloat(f.storage) ? Float64 : juliatype(f.storage)}, w)
end

# the checks of an input function's result `v` at a write, with no allocation (the work of
# `_input_value` and `_check_integer` on a value that passes)
function check_input_result(p::Program, key::AbstractString, v, index)
    n = _input_length(p, key)
    ok = v isa Number || (v isa AbstractArray && length(v) == n)
    if !ok || !_input_ok(p, key, v, is_bool_input(index, key), input_bounds(index, key))
        _check_plain(v, input_name(index, key))
        # the error in the user's words (`_input_value` throws it)
        _input_value(p, key, v, input_name(index, key); bool = is_bool_input(index, key),
            bounds = input_bounds(index, key))
        throw(ArgumentError(string("input `", input_name(index, key), "`: the function returned a ", typeof(v))))
    end
    return nothing
end
function _input_ok(p::Program, key::AbstractString, v, bool::Bool, bounds::Tuple{Float64, Float64})
    st = p.fields[fieldid(p, key)].storage
    return _values_ok(v, isfloat(st), _int_range(st), bool, bounds)
end
# the values of an integer storage type, as Float64 (a type-stable `typemin`/`typemax`)
_int_range(st) = st == U8 ? (0.0, 255.0) : st == I32 ? (Float64(typemin(Int32)), Float64(typemax(Int32))) :
                 st == U32 ? (0.0, Float64(typemax(UInt32))) : (-Inf, Inf)
_values_ok(v::Number, fl, r, bool, bounds) = _value_ok(v, fl, r, bool, bounds)
function _values_ok(v::AbstractArray, fl, r, bool, bounds)
    # (a device array is checked on a host copy: no scalar indexing)
    v isa Union{Array, AbstractRange} || KA.get_backend(v) isa KA.CPU || return _values_ok(Array(v), fl, r, bool, bounds)
    for x in v
        _value_ok(x, fl, r, bool, bounds) || return false
    end
    return true
end
function _value_ok(x, fl::Bool, r::Tuple{Float64, Float64}, bool::Bool, bounds::Tuple{Float64, Float64})
    _plain(x) || return false
    bounds[1] <= x <= bounds[2] || return false
    fl && return true
    return x isa Bool || (bool ? (x == 0 || x == 1) : isinteger(x) && r[1] <= x <= r[2])
end
# a write of an input that a function of the time gives (the function would take it over)
@noinline _fn_write_error(name) = throw(ArgumentError(string("input `", name, "` is given as a function of the time, ",
    "which sets it at every window or call; give it a constant with `remake(prob; inputs = [", _route(name),
    " => K])` (or another function the same way)")))

# an input's values are plain numbers: a value with derivative parts (a ForwardDiff Dual that an
# input function closes over) has no input store to go to in this version (F4-B1 review)
_plain(x) = x isa Union{AbstractFloat, Integer, Rational}
function _check_plain(v, name)
    x = v isa AbstractArray ? (isempty(v) ? 0.0 : first(v isa Union{Array, AbstractRange} ? v : Array(v))) : v
    v isa Union{Number, AbstractArray} && !_plain(x) && throw(ArgumentError(string("input `", name, "`: the function ",
        "returned values of type ", typeof(x), "; an input holds plain numbers (no derivative parts): to differentiate ",
        "through a time-dependent input, write it in the equations with a parameter (`a * sin(ω * t)`) and ",
        "differentiate with respect to that parameter")))
    return nothing
end

# write the result `v` of an input function into the host vector `x` in place
_write_host!(x::AbstractVector, v::Number) = fill!(x, v)
_write_host!(x::AbstractVector, v::AbstractArray) = copyto!(x, v)

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
        isempty(ks) ? " (it has none)" : " (its inputs: " * join(("`$x`" for x in ks), ", ") * ")",
        _cpm_word(string(s)) || _cpm_word(name) ? string("; `", name, "` is a name `Potts.fields(model)` gives a CPM ",
            "input, and a coupled PDESystem's inputs are its own: `Potts.field_inputs(integ, pdesys)` gives the values of ",
            "exactly the inputs of `pdesys`") : "")))
end
# a name a Potts model's `Potts.fields` gives a CPM input (batch-end review S3): a CPM word, or a
# CPM read as the model writes it (`volume[owner]`)
_cpm_word(n::AbstractString) = n in ("kind", "domain", "owner", "position", "site", "mcs", "time") ||
                               occursin(r"^\w+\[\w+\]$", n)

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
    return _copy_input!(array(st, fieldid(p, key), :cur), v)
end
# (on the host an elementwise copy: no conversion buffer, so an input write allocates nothing)
_copy_input!(a, v) = a isa Array || eltype(v) === eltype(a) ? copyto!(a, v) : copyto!(a, convert(Vector{eltype(a)}, v))

"""
    ParamsTables(p, tables, inputs = [])

The raw parameters `p` with the problem's tables (`key => values`) and the current host
values of the inputs the bound reads in an index (`key => array shaped by site`, or a
number; [`bound_inputs`](@ref)), as the stability hooks receive them ([`with_tables`](@ref)):
indexed like `p`, so a bound that reads only scalars needs no change; a front end's bound
reads the table values from `tables` (a coefficient `Dk[i]` or `value_at(Dk, kind)`) and the index
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
    check_declared(stability, p)

The declared intervals of the stability bound against the constant face and mask values at
raw parameters `p` (batch 5 review M2): a value outside its field's declared `bounds` drives
the field out of the interval the bound takes, and is refused in the user's words (LatticePDE).
Run with [`check_parameters`](@ref)'s policy, before stepping and at every parameter change.
The default checks nothing.
"""
check_declared(stability, p) = nothing

"""
    declared_intervals(stability) -> Vector{Tuple{String, Tuple{Float64, Float64}}}

The fields (state or aux, by key) with declared finite `bounds = (lo, hi)` (batch 5 review M2):
a write of a state field outside its interval is refused, as at the start. The default is none.
"""
declared_intervals(stability) = Tuple{String, Tuple{Float64, Float64}}[]

"""
    used_intervals(stability) -> Vector{String}

The keys of [`declared_intervals`](@ref) whose interval a coefficient bound read (batch 5 review
M2): a run checks that those fields stay in their intervals where it reads its status. The
default is none.
"""
used_intervals(stability) = String[]

"""
    seen_bound(stability, p) -> Float64

A bound on the spectral radius over the terms the stability bound sees, used to raise an
explicit substep count (`NaN` when there is none). The default is `stability(p)`.
"""
seen_bound(stability, p) = Float64(stability(p))

"""
    bound_report(stability, p) -> NamedTuple

The parts of the stability bound at raw parameters `p` that the substep policy decides on
([`substeps`](@ref)), `(; negative, coupled, nonfinite, terms)`: the keys of the rows with a
diffusion coefficient below zero, the keys of the coupled rows that are not diagonally
dominant, a `(key, coefficient, why)` per coefficient with no finite bound (`why`: `:cap`,
`:tables`, or a `Tuple` of the entries where it is not finite), and the terms the bound cannot
see (`"key: term"`). A bound may add `worst`, the row that gives the bound and its parts
`(; key, diffusion, advection, reaction, cross)`, which the report prints. The default reports
none (LatticePDE's `StabilityBound` reports them).
"""
bound_report(stability, p) = (; negative = String[], coupled = String[], nonfinite = Tuple{String, String, Any}[],
    terms = String[])

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
