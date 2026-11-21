# Input fields of a problem (fields the program reads but never writes: a coupling, a
# domain mask, a kind map) and the parameter checks a front end supplies. An input has a
# value only when it is given: an unset input is an error at `init` (or when an ODE problem
# is built), never a silent zero.

# the input fields of `p`, in field order
_input_keys(p::Program) = String[f.key for f in p.fields if f.role == :input]

# the length of input `key`'s array (sites × components of its first level)
function _input_length(p::Program, key::AbstractString)
    f = p.fields[fieldid(p, key)]
    return nsites(p, f.levels[1]) * ncomp(f)
end

# a value given for input `key`: an array with one entry per site (and component), or a
# number for every site; returned as a flat host vector (`Bool` arrays are kept as given)
function _input_value(
        p::Program, key::AbstractString, v, name = key; bool::Bool = false,
        bounds::Tuple{Float64, Float64} = (-Inf, Inf)
    )
    n = _input_length(p, key)
    v isa Number && (_check_integer(p, key, name, v; bool, bounds); return fill(v, n))
    is_input_function(v) && throw(
        ArgumentError(
            string(
                "input `", name, "`: a function of the time is given where ",
                "the problem is built, `discretize(sys, disc; inputs = [", name,
                " => t -> values])` or `remake(prob; inputs = …)`; ",
                "a write on an integrator takes an array with one value per site (", n,
                ") or a number"
            )
        )
    )
    v isa AbstractArray || throw(
        ArgumentError(
            "input `$name`: give an array with one value per site ($n) or a number; got \
                a $(typeof(v))"
        )
    )
    length(v) == n || throw(
        ArgumentError(
            "input `$name`: the array has $(length(v)) values; the field has $n (one per \
                site$(n == nsites(p, 0) ? "" : " and component"))"
        )
    )
    w = vec(collect(v))                       # on the host (a device array is copied here)
    _check_integer(p, key, name, w; bool, bounds)
    return w
end

"""
    resolve_inputs(p, index, given, base = nothing; t0 = nothing)
        -> Vector{Pair{String, Any}}

The value of every input field of program `p`, in field order.

Each value is `base` (a previous list) or unset (`nothing`), replaced by the `given` pairs.
A value that is a function of the time ([`is_input_function`](@ref)) gives its value at
`t0`; [`input_functions`](@ref) keeps the function. A given value is checked: one value
per site (or a number), the input's integer type, Bool declaration and bounds.

# Arguments
- `p::Program`: the field program.
- `index`: the symbol table, a [`LatticeIndex`](@ref), or another value for keys only.
- `given`: `symbol => values` pairs; the symbol is looked up in `index`, or is the field
  key.
- `base = nothing`: a previous list of `key => value` pairs.

# Keywords
- `t0 = nothing`: the start time. A problem with no start time takes no function of the
  time: such a value throws an `ArgumentError`.

# Returns
- `key => value` pairs, one per input field: a flat host vector, or `nothing` for an unset
  input.
"""
function resolve_inputs(p::Program, index, given, base = nothing; t0 = nothing)
    ks = _input_keys(p)
    vals = Dict{String, Any}(k => nothing for k in ks)
    base === nothing || foreach(((k, v),) -> vals[k] = v, base)
    for (s, v) in given
        k = _given_input_key(p, index, s, ks)
        name = input_name(index, k)
        if is_input_function(v)
            t0 === nothing && throw(
                ArgumentError(
                    string(
                        "input `", name, "`: this problem takes input values, ",
                        "not a function of the time; give an array with one value per \
                            site or a number"
                    )
                )
            )
            vals[k] = _host_input(p, k, _call_input(v, t0, name), name, index)
        else
            vals[k] = _input_value(
                p, k, v, name; bool = is_bool_input(index, k),
                bounds = input_bounds(index, k)
            )
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

Whether an input value `v` is a function of the time.

Anything that is not a number, an array or `nothing` is one: an anonymous function
`t -> values`, a named function, an interpolation object. The run calls it as `v(t)`, which
returns an array with one value per site or a number.

# Arguments
- `v`: the input value.

# Returns
- `true` if `v` is not a `Number`, an `AbstractArray` or `nothing`.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Problems.is_input_function(t -> 2t)
true

julia> LatticeFields.Problems.is_input_function([1.0])
false
```
"""
is_input_function(v) = !(v isa Union{Number, AbstractArray, Nothing})

"""
    input_functions(p, index, given, base = []) -> Vector{Pair{String, Any}}

The inputs of `given` that are functions of the time, `key => f`, over those of `base`.

A function replaces the input's previous one, and a value removes it (the input is constant
again).

# Arguments
- `p::Program`: the field program.
- `index`: the symbol table that looks up the given symbols.
- `given`: `symbol => value` pairs.
- `base = []`: the previous `key => f` pairs.

# Returns
- The `key => f` pairs of the inputs that are functions of the time.

See also [`resolve_inputs`](@ref), [`is_input_function`](@ref).
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

# the value of input function `f` at time `t`, refused in the user's words when `f` takes no
# time
function _call_input(f::F, t, name) where {F}
    applicable(f, t) || throw(
        ArgumentError(
            string(
                "input `", name, "`: a value that is not an array or a number is ",
                "a function of the time, called as `f(t)`; the given `", typeof(f),
                "` takes no time argument. Give ",
                "`", name, " => t -> values`"
            )
        )
    )
    return f(t)
end
# the host values of an input function's result: a vector of the input's host type (Float64
# for a float field, its integer type for a kind map or a mask), so later results are
# written into it in place
function _host_input(p::Program, key::AbstractString, v, name, index)
    _check_plain(v, name)
    w = _input_value(
        p, key, v, name; bool = is_bool_input(index, key),
        bounds = input_bounds(index, key)
    )
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
        _input_value(
            p, key, v, input_name(index, key); bool = is_bool_input(index, key),
            bounds = input_bounds(index, key)
        )
        throw(
            ArgumentError(
                string(
                    "input `", input_name(index, key), "`: the function returned a ",
                    typeof(v)
                )
            )
        )
    end
    return nothing
end
function _input_ok(
        p::Program, key::AbstractString, v, bool::Bool, bounds::Tuple{Float64, Float64}
    )
    st = p.fields[fieldid(p, key)].storage
    return _values_ok(v, isfloat(st), _int_range(st), bool, bounds)
end
# the values of an integer storage type, as Float64 (a type-stable `typemin`/`typemax`)
function _int_range(st)
    if st == U8
        return (0.0, 255.0)
    elseif st == I32
        return (Float64(typemin(Int32)), Float64(typemax(Int32)))
    elseif st == U32
        return (0.0, Float64(typemax(UInt32)))
    else
        return (-Inf, Inf)
    end
end
_values_ok(v::Number, fl, r, bool, bounds) = _value_ok(v, fl, r, bool, bounds)
function _values_ok(v::AbstractArray, fl, r, bool, bounds)
    # (a device array is checked on a host copy: no scalar indexing)
    v isa Union{Array, AbstractRange} || KA.get_backend(v) isa KA.CPU ||
        return _values_ok(Array(v), fl, r, bool, bounds)
    for x in v
        _value_ok(x, fl, r, bool, bounds) || return false
    end
    return true
end
function _value_ok(
        x, fl::Bool, r::Tuple{Float64, Float64},
        bool::Bool, bounds::Tuple{Float64, Float64}
    )
    _plain(x) || return false
    bounds[1] <= x <= bounds[2] || return false
    fl && return true
    return x isa Bool || (bool ? (x == 0 || x == 1) : isinteger(x) && r[1] <= x <= r[2])
end
# a write of an input that a function of the time gives (the function would take it over)
@noinline function _fn_write_error(name)
    throw(
        ArgumentError(
            string(
                "input `", name, "` is given as a function of the time, ",
                "which sets it at every window or call; give it a constant with \
                    `remake(prob; inputs = [", _route(name),
                " => K])` (or another function the same way)"
            )
        )
    )
end

# an input's values are plain numbers: a value with derivative parts (a ForwardDiff Dual
# that an input function closes over) has no input store to go to in this version
_plain(x) = x isa Union{AbstractFloat, Integer, Rational}
function _check_plain(v, name)
    x = if v isa AbstractArray
        isempty(v) ? 0.0 : first(v isa Union{Array, AbstractRange} ? v : Array(v))
    else
        v
    end
    v isa Union{Number, AbstractArray} && !_plain(x) && throw(
        ArgumentError(
            string(
                "input `", name, "`: the function ",
                "returned values of type ", typeof(x),
                "; an input holds plain numbers (no derivative parts): to differentiate ",
                "through a time-dependent input, write it in the equations with a \
                    parameter (`a * sin(ω * t)`) and ",
                "differentiate with respect to that parameter"
            )
        )
    )
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
    isempty(comps) || throw(
        ArgumentError(
            string(
                "`", name, "` is an array input: give each component, ",
                "`inputs = [", join(("$(_route(x)) => values" for x in comps), ", "),
                "]` (or the components of the array ",
                "variable)"
            )
        )
    )
    known = if isempty(ks)
        " (it has none)"
    else
        " (its inputs: " * join(("`$x`" for x in ks), ", ") * ")"
    end
    cpm = if _cpm_word(string(s)) || _cpm_word(name)
        string(
            "; `", name, "` is a name `Potts.fields(model)` gives a CPM ",
            "input, and a coupled PDESystem's inputs are its own: \
                `Potts.field_inputs(integ, pdesys)` gives the values of ",
            "exactly the inputs of `pdesys`"
        )
    else
        ""
    end
    throw(
        ArgumentError(
            string(
                "`", name, "` is not an input field of the problem", known, cpm
            )
        )
    )
end
# a name a Potts model's `Potts.fields` gives a CPM input: a CPM word, or a
# CPM read as the model writes it (`volume[owner]`)
function _cpm_word(n::AbstractString)
    return n in ("kind", "domain", "owner", "position", "site", "mcs", "time") ||
        occursin(r"^\w+\[\w+\]$", n)
end

# an integer input (a kind map, a mask) takes integer values in its type's range, a Bool
# input (`bool`: declared `::Bool`) only Bool or 0/1; a bad value is named with its site
function _check_integer(
        p::Program, key::AbstractString, name, v; bool::Bool = false,
        bounds::Tuple{Float64, Float64} = (-Inf, Inf)
    )
    f = p.fields[fieldid(p, key)]
    # the declared bounds (`bounds = (lo, hi)` metadata): the stability bound relies on them
    lo, hi = bounds
    out = if lo == -Inf && hi == Inf
        nothing
    else
        findfirst(x -> !(lo <= x <= hi), v isa Number ? (v,) : v)
    end
    out === nothing || throw(
        ArgumentError(
            string(
                "input `", name, "` is declared with bounds (", _bnum(lo), ", ",
                _bnum(hi), "); got ", (v isa Number ? v : v[out]),
                (
                    if v isa Number
                        ""
                    else
                        " at site $(Tuple(CartesianIndices(_input_dims(p, f))[out]))"
                    end
                ),
                "; give values inside the bounds (or declare the bounds the values need)"
            )
        )
    )
    isfloat(f.storage) && return nothing
    T = juliatype(f.storage)
    function ok(x)
        return x isa Bool ||
            (bool ? (x == 0 || x == 1) : isinteger(x) && typemin(T) <= x <= typemax(T))
    end
    bad = findfirst(!ok, v isa Number ? (v,) : v)
    bad === nothing && return nothing
    dims = _input_dims(p, f)
    holds = bool ? "a Bool mask (true/false or 0/1)" : "integer values (a kind map: $T)"
    throw(
        ArgumentError(
            string(
                "input `", name, "` holds ", holds, "; got ", (v isa Number ? v : v[bad]),
                (v isa Number ? "" : " at site $(Tuple(CartesianIndices(dims)[bad]))")
            )
        )
    )
end

# the spelling of input `name` in a route that runs: `:kind`, or `"vel[1]"` for a name that
# is not an identifier
_route(name::AbstractString) = Base.isidentifier(name) ? ":" * name : repr(String(name))

"""
    input_name(index, key) -> String

The name of input field `key` as the user writes it, else the key.

The name is `kind` for a generated `kind__in`, or the `input_name` metadata of its variable.

# Arguments
- `index`: the symbol table, a [`LatticeIndex`](@ref). Any other value gives the key.
- `key::AbstractString`: the input field key.

# Returns
- The name as a `String`.
"""
input_name(ix::LatticeIndex, key::AbstractString) = get(ix.inputnames, key, String(key))
input_name(_, key::AbstractString) = String(key)
# the declared bounds `(lo, hi)` of input `key`, as the index records (`(-Inf, Inf)`: none)
input_bounds(ix::LatticeIndex, key::AbstractString) = get(ix.inputbounds, key, (-Inf, Inf))
input_bounds(_, ::AbstractString) = (-Inf, Inf)
function _input_dims(p, f)
    if ncomp(f) ==
            1
        return leveldims(p, f.levels[1])
    else
        return (leveldims(p, f.levels[1])..., ncomp(f))
    end
end
# a bound or value as A prints it (`0`, not `0.0`)
_bnum(x) = isinteger(x) && isfinite(x) ? string(Int(x)) : string(x)
# whether input `key` is declared Bool (a 0/1 mask), as the index records
is_bool_input(ix::LatticeIndex, key::AbstractString) = key in ix.boolinputs
is_bool_input(_, ::AbstractString) = false

"""
    check_inputs_set(inputs; built = true, index = nothing)

Throw an `ArgumentError` that names every input with no value.

An unset input is never read as zero.

# Arguments
- `inputs`: `key => value` pairs; `nothing` is an unset input.

# Keywords
- `built::Bool = true`: the problem exists already (an owned problem at `init`, which
  `remake(prob; inputs)` can still give values). `false`: it is being built (an ODE
  problem, whose inputs are fixed when it is built), and the message gives no `remake`
  route.
- `index = nothing`: the symbol table that gives the input names.

# Returns
- `nothing`.
"""
function check_inputs_set(inputs; built::Bool = true, index = nothing)
    unset = [input_name(index, k) for (k, v) in inputs if v === nothing]
    isempty(unset) || throw(
        ArgumentError(
            string(
                "the input field",
                length(unset) == 1 ? " " : "s ", join(("`$k`" for k in unset), ", "),
                if length(unset) ==
                        1
                    " has"
                else
                    " have"
                end,
                " no value (an unset input is not read as zero): give ",
                if length(unset) == 1
                    "it"
                else
                    "them"
                end,
                " with `inputs = [", join((_route(u) * " => values" for u in unset), ", "),
                "]` where the problem is built",
                built ? ", or `remake(prob; inputs = …)`" : "",
                "; a variable with a default ",
                "(`dom(..)::Bool = true [input = true]`) needs none"
            )
        )
    )
    return nothing
end

"""
    upload_inputs!(st, p, inputs; index = nothing) -> st

Copy the input values into the store's (only) slot of each input field.

It first checks that every input has a value ([`check_inputs_set`](@ref)).

# Arguments
- `st::FieldStore`: the field store, written in place.
- `p::Program`: the field program.
- `inputs`: `key => values` pairs.

# Keywords
- `index = nothing`: the symbol table that gives the input names for the messages.

# Returns
- `st`.
"""
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
# (on the host an elementwise copy: no conversion buffer, so an input write allocates
# nothing)
function _copy_input!(a, v)
    return if a isa Array || eltype(v) === eltype(a)
        copyto!(a, v)
    else
        copyto!(a, convert(Vector{eltype(a)}, v))
    end
end

"""
    ParamsTables(p, tables, inputs = [])

The raw parameters `p` with the problem's tables (`key => values`) and the current host
values of the inputs the bound reads in an index (`key => array shaped by site`, or a
number; [`bound_inputs`](@ref)), as the stability hooks receive them
([`with_tables`](@ref)): indexed like `p`, so a bound that reads only scalars needs no
change; a front end's bound reads the table values from `tables` (a coefficient `Dk[i]` or
`value_at(Dk, kind)`) and the index values from `inputs`. An input the front end fills on
the device every step is not passed (its declared bounds hold).

# Fields
- `p`: the raw parameters.
- `tables::Vector{Pair{String, Vector{Float64}}}`: the tables, `key => values`.
- `inputs::Vector{Pair{String, Any}}`: the input values the bound reads.
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
    with_tables(p, tables; inputs = ())

`p` as the stability hooks take it: `ParamsTables(p, tables, inputs)` when there are tables
or inputs, else `p`.

The hooks read the tables in Float64 on their primal values (a policy, as for the
parameters: a BigFloat table is rounded and a Dual table drops its derivative parts here
only; the problem keeps the values as given).

# Arguments
- `p`: the raw parameters.
- `tables`: the tables, `key => values`.

# Keywords
- `inputs = ()`: the input values the bound reads, `key => values`.

# Returns
- A [`ParamsTables`](@ref), or `p` when `tables` and `inputs` are empty.

# Examples
```jldoctest
julia> using LatticeFields

julia> w = LatticeFields.Problems.with_tables([1.0, 2.0], ["D" => [0.5]]);

julia> w[2], w.tables
(2.0, ["D" => [0.5]])
```
"""
function with_tables(p, tables; inputs = ())
    if isempty(tables) && isempty(inputs)
        return p
    else
        return ParamsTables(
            p, Pair{String, Vector{Float64}}[k => _primal64(v) for (k, v) in tables],
            Pair{String, Any}[inputs...]
        )
    end
end
_primal64(v::Vector{Float64}) = v
_primal64(v) = Float64[Float64(primal(x)) for x in v]

"""
    bound_inputs(stability) -> Vector{String}

The keys of the inputs whose current values the stability bound reads.

Such an input is the index of a table read: the bound evaluates index 0 only where the
values reach it.

# Arguments
- `stability`: the stability bound of the problem.

# Returns
- The input keys. The default is none.
"""
bound_inputs(stability) = String[]

"""
    check_parameters(stability, p)

A front end's parameter check at raw parameters `p` (primal values).

It runs before stepping and at every parameter change. It throws for values no step count
makes valid (LatticePDE: negative diffusion).

# Arguments
- `stability`: the stability bound of the problem.
- `p`: the raw parameters.

# Returns
- `nothing`. The default checks nothing.
"""
check_parameters(stability, p) = nothing

"""
    check_declared(stability, p)

The declared intervals of the stability bound against the constant face and mask values at
raw parameters `p`: a value outside its field's declared `bounds` drives
the field out of the interval the bound takes, and is refused in the user's words
(LatticePDE). Run with [`check_parameters`](@ref)'s policy, before stepping and at every
parameter change.

# Arguments
- `stability`: the stability bound of the problem.
- `p`: the raw parameters.

# Returns
- `nothing`. The default checks nothing.
"""
check_declared(stability, p) = nothing

"""
    declared_intervals(stability) -> Vector{Tuple{String, Tuple{Float64, Float64}}}

The fields (state or aux, by key) with declared finite `bounds = (lo, hi)`.

A write of a state field outside its interval is refused, as at the start.

# Arguments
- `stability`: the stability bound of the problem.

# Returns
- `(key, (lo, hi))` tuples. The default is none.
"""
declared_intervals(stability) = Tuple{String, Tuple{Float64, Float64}}[]

"""
    used_intervals(stability) -> Vector{String}

The keys of [`declared_intervals`](@ref) whose interval a coefficient bound read.

A run checks that those fields stay in their intervals where it reads its status.

# Arguments
- `stability`: the stability bound of the problem.

# Returns
- The field keys. The default is none.
"""
used_intervals(stability) = String[]

"""
    seen_bound(stability, p) -> Float64

A bound on the spectral radius over the terms the stability bound sees.

It is used to raise an explicit substep count.

# Arguments
- `stability`: the stability bound of the problem.
- `p`: the raw parameters.

# Returns
- The bound as a `Float64`, or `NaN` when there is none. The default is `stability(p)`.
"""
seen_bound(stability, p) = Float64(stability(p))

"""
    bound_report(stability, p) -> NamedTuple

The parts of the stability bound at raw parameters `p` that the substep policy decides on
([`substeps`](@ref)).

# Arguments
- `stability`: the stability bound of the problem.
- `p`: the raw parameters.

# Returns
- `(; negative, coupled, nonfinite, terms)`: the keys of the rows with a diffusion
  coefficient below zero, the keys of the coupled rows that are not diagonally dominant, a
  `(key, coefficient, why)` per coefficient with no finite bound (`why`: `:cap`,
  `:tables`, or a `Tuple` of the entries where it is not finite), and the terms the bound
  cannot see (`"key: term"`). A bound may add `worst`, the row that gives the bound and its
  parts `(; key, diffusion, advection, reaction, cross)`, which the report prints. The
  default reports none (LatticePDE's `StabilityBound` reports them).
"""
function bound_report(stability, p)
    return (;
        negative = String[], coupled = String[], nonfinite = Tuple{String, String, Any}[],
        terms = String[],
    )
end

"""
    unbounded_reason(stability, p) -> Union{Nothing, String}

Why `stability(p)` has no value (the terms it cannot see, by name), for the substep error.

# Arguments
- `stability`: the stability bound of the problem.
- `p`: the raw parameters.

# Returns
- The reason as a `String`, or `nothing`. The default gives `nothing`.
"""
unbounded_reason(stability, p) = nothing

"""
    unbounded_key(stability, p) -> Union{Nothing, String}

The same reason as [`unbounded_reason`](@ref) without values.

It holds the terms and the causes only (no entry, no parameter value), so a warning keyed
on it is given once per program, term and cause, however many values a sweep sets.

# Arguments
- `stability`: the stability bound of the problem.
- `p`: the raw parameters.

# Returns
- The key as a `String`, or `nothing`. The default is `unbounded_reason(stability, p)`.
"""
unbounded_key(stability, p) = unbounded_reason(stability, p)

"""
    check_bounds(p, index)

Check that the declared `bounds = (lo, hi)` of each parameter of `index` hold for the
values `p`.

An `ArgumentError` names the first parameter outside them, base parameters first and then
computed ones, in slot order, with its bounds as `PottsProblem` prints them (`(0, 2)`). A
NaN value passes. Every write checks it before anything changes.

# Arguments
- `p`: the raw parameter values.
- `index`: the symbol table. An `index` that is not a [`LatticeIndex`](@ref) checks nothing.

# Returns
- `nothing`.
"""
function check_bounds(p, index)
    index isa LatticeIndex || return nothing
    # base parameters first (a write names the parameter written), then computed ones
    for i in sort!(
            collect(keys(index.parambounds)); by = i -> (
                computed_slot(index, i) !== nothing, i,
            )
        )
        lo, hi = index.parambounds[i]
        v = primal(p[i])
        isnan(v) || lo <= v <= hi ||
            throw(ArgumentError(_bounds_message(index, i, v, lo, hi)))
    end
    return nothing
end
function _bounds_message(index, i, v, lo, hi)
    head = string(
        "parameter `", parameter_name(index, i), "` = ", v,
        " is outside its declared bounds (", _bnum(lo), ", ",
        _bnum(hi), ")"
    )
    # a computed parameter: the inputs to change
    k = computed_slot(index, i)
    why = k === nothing ? nothing : get(index.derived, index.key(k), nothing)
    why === nothing || return string(head, ": ", why)
    return string(head, ": give a value in them, or change `bounds` in its declaration")
end
# the values `p` with the pairs `kv` (parameter → value) written, within their bounds (a
# write of the ODE path, refused before it happens)
function check_bounds(p, index, kv; tables = nothing)
    index isa LatticeIndex && !isempty(index.parambounds) || return nothing
    q = Vector{Any}(collect(p))
    for (k, v) in kv
        table_key(index, k) === nothing || continue
        i = SII.parameter_index(index, k)
        i isa Integer && v isa Real && (q[i] = v)
    end
    tables === nothing || derive!(q, tables, index)    # the computed slots follow
    return check_bounds(q, index)
end

"""
    check_values(p, index; built = true)

Check the parameter values `p`: their declared bounds hold ([`check_bounds`](@ref)), and a
NaN value (no value given) throws an `ArgumentError` that names the parameter.

# Arguments
- `p`: the raw parameter values.
- `index`: the symbol table that gives the names.

# Keywords
- `built::Bool = true`: as for [`check_inputs_set`](@ref). A problem being built has no
  `remake` yet, so the message gives the system's `initial_conditions` instead.

# Returns
- `nothing`.
"""
function check_values(p, index; built::Bool = true)
    check_bounds(p, index)          # a declared `bounds = (lo, hi)` holds at every write
    for i in eachindex(p)
        isnan(primal(p[i])) || continue
        name = index isa LatticeIndex ? parameter_name(index, i) : "#$i"
        route = if built
            string(
                " or set it with `remake(prob; p = [", name,
                " => v])`, or on an integrator ",
                "`setp(integ, ", name, ")(integ, v)`"
            )
        else
            string(" or a value in the system's `initial_conditions` (`", name, " => v`)")
        end
        throw(
            ArgumentError(
                string(
                    "parameter `", name, "` has no value (it is NaN): give it a default ",
                    "(`@parameters ", name, " = v`)", route
                )
            )
        )
    end
    return nothing
end
