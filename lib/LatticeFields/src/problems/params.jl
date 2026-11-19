# The parameter object of `FieldProblem` and `discretize` SciML problems: the scalar
# parameters, the tables, the input arrays and the clock's step index in one container, so
# inputs and tables are written on every solver (`integ.ps[k] = v`, `remake(prob; p)`, a
# callback), not only on the owned one.

"""
    LatticeParameters(values, tables = [], inputs = []; tick = 0, fns = [])

The parameters of a field problem (F4 design §3.3): `values` the scalar parameters in raw
order (SciMLStructures' `Tunable` portion; Duals allowed), `tables` the kind tables as
`key => values` (`Constants`), `inputs` the input arrays as `key => values` (flat host
values, or `nothing` for an unset input) and `tick` the clock's step index (`Discrete`, with
the inputs). `stamp` counts the writes of tables and inputs: the right side of an ODE solver
uploads them again (and runs its masks and checks again) when it changes. `fns` are the
inputs given as functions of the time (`key => f`, F4-B1): every solver writes `f(t)` into the
input: the owned run at the start and after each window, an OrdinaryDiffEq solver's right
side at every call ([`InputRefresh`](@ref)).

Read and write it by symbol, as every SciML parameter object: `prob.ps[k]`, `integ.ps[Dk] =
values`, `integ.ps[kind] = K`, `remake(prob; p = [k => v, Dk => values, kind => K])`. A
table or input write checks the values (finite entries, one value per site, the input's
declared type and bounds); the stability bound runs at the next call of the right side.

An OrdinaryDiffEq integrator holds the problem's own `LatticeParameters` (SciML aliases `p` by
default), so `integ.ps[k] = v` on it writes `prob.p` too: `remake(prob)` (or `copy(prob.p)`)
gives a problem whose parameters a run does not change. An owned integrator holds a copy.
"""
mutable struct LatticeParameters{V <: AbstractVector, TB <: AbstractVector, IN <: AbstractVector}
    values::V
    tables::TB
    inputs::IN
    tick::Base.RefValue{Int}
    stamp::Base.RefValue{Int}
    fns::Vector{Pair{String, Any}}      # the inputs given as functions of the time, `key => f`
end
LatticeParameters(values::AbstractVector, tables = Pair{String, Vector{Float64}}[], inputs = Pair{String, Any}[];
    tick::Integer = 0, fns = Pair{String, Any}[]) = LatticeParameters(values, _table_list(tables),
    Pair{String, Any}[k => v for (k, v) in inputs], Ref(Int(tick)), Ref(0), Pair{String, Any}[k => f for (k, f) in fns])

# the scalar values of a parameter object (a raw vector is its own)
_pvals(p::LatticeParameters) = p.values
_pvals(p) = p
_ptables(p::LatticeParameters, fallback) = p.tables
_ptables(p, fallback) = fallback

Base.eltype(::Type{<:LatticeParameters{V}}) where {V} = eltype(V)
Base.copy(p::LatticeParameters) = LatticeParameters(copy(p.values), eltype(p.tables)[k => copy(v) for (k, v) in p.tables],
    Pair{String, Any}[k => (v === nothing ? v : copy(v)) for (k, v) in p.inputs], Ref(p.tick[]), Ref(p.stamp[]), copy(p.fns))
Base.:(==)(a::LatticeParameters, b::LatticeParameters) = a.values == b.values && a.tables == b.tables &&
                                                         a.inputs == b.inputs && a.tick[] == b.tick[] && a.fns == b.fns
# `isequal` and `hash` over the same fields `==` compares (the tick's value, not its `Ref`),
# so `isequal` objects hash equal (`-0.0` and `0.0` are `==` but not `isequal`)
Base.isequal(a::LatticeParameters, b::LatticeParameters) = isequal(a.values, b.values) && isequal(a.tables, b.tables) &&
    isequal(a.inputs, b.inputs) && isequal(a.tick[], b.tick[]) && isequal(a.fns, b.fns)
Base.hash(p::LatticeParameters, h::UInt) =
    hash(p.fns, hash(p.tick[], hash(p.inputs, hash(p.tables, hash(p.values, hash(:LatticeParameters, h))))))
# the same tables and inputs with other scalar values (SciMLStructures' `replace`, a remake)
with_values(p::LatticeParameters, v::AbstractVector) =
    LatticeParameters(v, eltype(p.tables)[k => copy(x) for (k, x) in p.tables],
        Pair{String, Any}[k => (x === nothing ? x : copy(x)) for (k, x) in p.inputs], Ref(p.tick[]), Ref(p.stamp[]),
        copy(p.fns))
function Base.show(io::IO, p::LatticeParameters)
    print(io, "LatticeParameters(", p.values)
    isempty(p.tables) || print(io, "; tables ", join(("`$k`" for (k, _) in p.tables), ", "))
    isempty(p.inputs) || print(io, "; inputs ", join(("`$k`" for (k, _) in p.inputs), ", "))
    print(io, ")")
end

"""
    TableSlot(key, entry)

The parameter index of a table (`entry = 0`) or of one entry of it, in a
[`LatticeParameters`](@ref).
"""
struct TableSlot
    key::String
    entry::Int
end
"""
    InputSlot(key, index)

The parameter index of an input field in a [`LatticeParameters`](@ref); `index` (the
[`LatticeIndex`](@ref)) gives its name, type and bounds for the checks of a write.
"""
struct InputSlot{X}
    key::String
    index::X
end

_tabpos(p::LatticeParameters, k) = (j = findfirst(x -> first(x) == k, p.tables);
                                    j === nothing ? throw(ArgumentError("`$k` is not a table of the problem")) : j)
_inpos(p::LatticeParameters, k) = (j = findfirst(x -> first(x) == k, p.inputs);
                                   j === nothing ? throw(ArgumentError("`$k` is not an input of the problem")) : j)

SII.parameter_values(p::LatticeParameters, i::Integer) = p.values[i]
SII.parameter_values(p::LatticeParameters, i::AbstractVector{<:Integer}) = p.values[i]
function SII.parameter_values(p::LatticeParameters, s::TableSlot)
    v = last(p.tables[_tabpos(p, s.key)])
    return s.entry == 0 ? copy(v) : v[s.entry]
end
function SII.parameter_values(p::LatticeParameters, s::InputSlot)
    v = last(p.inputs[_inpos(p, s.key)])
    v === nothing && return nothing
    return _input_shaped(s, v isa Number ? v : copy(v))
end
# an input's values shaped by site (as `integ[kind]` reads it), when the index knows its program
function _input_shaped(s::InputSlot, v)
    prog = s.index isa LatticeIndex ? s.index.program[] : nothing
    v isa AbstractArray && prog isa Program || return v
    a = reshape(v, _input_dims(prog, prog.fields[fieldid(prog, s.key)]))
    return is_bool_input(s.index, s.key) ? map(!iszero, a) : a
end

SII.set_parameter!(p::LatticeParameters, v, i::Integer) = (p.values[i] = v; v)
function SII.set_parameter!(p::LatticeParameters, v, s::TableSlot)
    j = _tabpos(p, s.key)
    vals = last(p.tables[j])
    if s.entry == 0
        v isa Union{AbstractArray, Tuple} && length(v) == length(vals) || throw(ArgumentError(string("the table `", s.key,
            "` has ", length(vals), " entries; give ", length(vals), " values (got ", v isa Union{AbstractArray, Tuple} ?
                                                                                     length(v) : repr(v), ")")))
        all(x -> x isa Real && isfinite(x), v) || throw(ArgumentError("the table `$(s.key)` must hold finite values (got $v)"))
        vals .= vec(collect(v))
    else
        v isa Real && isfinite(v) || throw(ArgumentError("the table `$(s.key)` must hold finite values (got $v)"))
        vals[s.entry] = v
    end
    p.stamp[] += 1
    return v
end
function SII.set_parameter!(p::LatticeParameters, v, s::InputSlot)
    any(x -> first(x) == s.key, p.fns) && _fn_write_error(input_name(s.index, s.key))
    j = _inpos(p, s.key)
    prog = s.index.program[]
    w = prog isa Program ? _input_value(prog, s.key, v, input_name(s.index, s.key); bool = is_bool_input(s.index, s.key),
                                bounds = input_bounds(s.index, s.key)) : v
    p.inputs[j] = s.key => w
    p.stamp[] += 1
    return v
end

# SciMLStructures: `Tunable` is the scalar values (one vector, so ForwardDiff and
# SciMLSensitivity see only them), `Constants` the tables (flat, in table order), `Discrete`
# the inputs (flat, in input order) and the step index (last)
SS.isscimlstructure(::LatticeParameters) = true
SS.ismutablescimlstructure(::LatticeParameters) = true
SS.hasportion(::Union{SS.Tunable, SS.Constants, SS.Discrete}, ::LatticeParameters) = true
function SS.canonicalize(::SS.Tunable, p::LatticeParameters)
    return p.values, v -> SS.replace(SS.Tunable(), p, v), true
end
SS.replace(::SS.Tunable, p::LatticeParameters, v) = with_values(p, collect(v))
function SS.replace!(::SS.Tunable, p::LatticeParameters, v)
    p.values .= v
    return nothing
end
_flat_tables(p::LatticeParameters) = reduce(vcat, (last(t) for t in p.tables); init = _tabeltype(p.tables)[])
function SS.canonicalize(::SS.Constants, p::LatticeParameters)
    return _flat_tables(p), v -> SS.replace(SS.Constants(), p, v), false
end
function SS.replace(::SS.Constants, p::LatticeParameters, v)
    q = copy(p)
    SS.replace!(SS.Constants(), q, v)
    return q
end
function SS.replace!(::SS.Constants, p::LatticeParameters, v)
    length(v) == sum(t -> length(last(t)), p.tables; init = 0) || throw(ArgumentError(string("the tables hold ",
        sum(t -> length(last(t)), p.tables; init = 0), " values; got ", length(v))))
    i = 0
    for (_, t) in p.tables
        t .= view(v, (i + 1):(i + length(t)))
        i += length(t)
    end
    p.stamp[] += 1
    return nothing
end
_set_inputs(p::LatticeParameters) = [(k, x) for (k, x) in p.inputs if x !== nothing]
function SS.canonicalize(::SS.Discrete, p::LatticeParameters)
    v = Float64[]
    for (_, x) in _set_inputs(p)
        x isa Number ? push!(v, Float64(x)) : append!(v, Float64.(x))
    end
    push!(v, p.tick[])
    return v, w -> SS.replace(SS.Discrete(), p, w), false
end
function SS.replace(::SS.Discrete, p::LatticeParameters, v)
    q = copy(p)
    SS.replace!(SS.Discrete(), q, v)
    return q
end
function SS.replace!(::SS.Discrete, p::LatticeParameters, v)
    n = sum(((_, x),) -> x isa Number ? 1 : length(x), _set_inputs(p); init = 0) + 1
    length(v) == n || throw(ArgumentError("the inputs and the step index hold $n values; got $(length(v))"))
    i = 0
    for (j, (k, x)) in enumerate(p.inputs)
        x === nothing && continue
        if x isa Number
            p.inputs[j] = k => convert(typeof(x), v[i + 1])
            i += 1
        else
            p.inputs[j] = k => convert(Vector{eltype(x)}, v[(i + 1):(i + length(x))])
            i += length(x)
        end
    end
    p.tick[] = round(Int, v[end])
    p.stamp[] += 1
    return nothing
end
