# The computed parameters of a problem: one compiled function from the
# base values to the computed values, shared by both coupled and standalone routes.

"""
    Derivation(f, base, computed)

The computed parameters of a model or system as one compiled function.

`d(vals)` maps the
base values `vals` (a tuple in the order of `d.base`: numbers and tables) to the computed
values (a tuple in the order of `d.computed`: a number, or an array for a kind table with
expression entries). `LatticePDE.derivation` builds it; a front end calls it after every
write of base values. Its rules: Base and registered functions, integer division, a lazy
`ifelse`, and a kind-table read by kind number (the medium is 0), in the number type of the
values given. An evaluation that fails is an `ArgumentError` that names the computed
parameter.

# Fields
- `f`: the compiled function, base tuple to computed tuple.
- `base::Vector{Symbol}`: the names of the base values, in order.
- `computed::Vector{Symbol}`: the names of the computed values, in order.

# Examples
```jldoctest
julia> using LatticeFields

julia> d = LatticeFields.Problems.Derivation(v -> (2 * v[1],), [:a], [:b]);

julia> d((3.0,))
(6.0,)
```

See also [`derive_at`](@ref), [`derive!`](@ref).
"""
struct Derivation{F}
    f::F
    base::Vector{Symbol}
    computed::Vector{Symbol}
end
(d::Derivation)(vals::Tuple) = d.f(vals)
Base.isempty(d::Derivation) = isempty(d.computed)

"""
    derive_at(name, t, ks...)

Entry `ks` of kind table `t` in a derivation, by kind numbers (the medium is 0, then the
kinds in order): `t[ks .+ 1...]`.

A table whose dimension is not `length(ks)`, a kind that is not an integer, or a kind
outside the table throws an `ArgumentError`.

# Arguments
- `name`: the computed parameter that reads the table, for the message.
- `t::AbstractArray`: the kind table.
- `ks...`: the kind numbers, one per table dimension.

# Returns
- The entry `t[ks .+ 1...]`.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Problems.derive_at(:J, [1.0 2.0; 3.0 4.0], 0, 1)
2.0
```
"""
function derive_at(name, t, ks...)
    t isa AbstractArray && ndims(t) == length(ks) || throw(
        ArgumentError(
            string(
                "it reads a kind table with ", length(ks),
                length(ks) == 1 ? " kind" : " kinds",
                "; the table takes ", t isa AbstractArray ? ndims(t) : 0
            )
        )
    )
    for k in ks
        k isa Real && isinteger(k) ||
            throw(ArgumentError("it reads a kind table at `$k`, not a kind number"))
    end
    i = map(k -> Int(k) + 1, ks)
    checkbounds(Bool, t, i...) ||
        throw(ArgumentError("it reads kind $(join(ks, ", ")) of a kind table with kinds \
            0:$(size(t, 1) - 1)"))
    return t[i...]
end

"""
    derive_fail(name, text, e)

Throw the error of a failed evaluation of computed parameter `name`.

# Arguments
- `name`: the computed parameter.
- `text`: its default, as written.
- `e`: the error that the evaluation threw. An `ArgumentError` gives its message.

# Returns
- Nothing: it always throws an `ArgumentError` that names `name` and `text`.
"""
function derive_fail(name, text, e)
    throw(
        ArgumentError(
            string(
                "parameter `", name, "` = `", text,
                "` fails on the parameter values: ", if e isa ArgumentError
                    e.msg
                else
                    sprint(showerror, e)
                end
            )
        )
    )
end

"""
    derive!(p, tables, ix) -> p

Write the computed slots of the parameter vector `p` from its base slots and tables.

The index's `derive` is `(d, sources, slots)`: a source is a slot number or a table key,
and a slot 0 is a computed parameter that no slot holds. An index with no `derive`, or an
`ix` that is not a [`LatticeIndex`](@ref), leaves `p` as it is.

# Arguments
- `p::AbstractVector`: the raw parameter vector, written in place.
- `tables`: the kind tables, `key => values`.
- `ix`: the symbol table of the problem.

# Returns
- `p`.

See also [`Derivation`](@ref).
"""
function derive!(p, tables, ix)
    ix isa LatticeIndex || return p
    ix.derive === nothing && return p
    d, src, slots = ix.derive
    # (a matrix table in its declared shape: an expression reads `J[i, j]`)
    vals = Tuple(
        if s isa Integer
            p[s]
        else
            _table_shaped(
                last(tables[findfirst(x -> first(x) == s, tables)]),
                get(ix.tableshapes, s, ())
            )
        end for s in src
    )
    for (i, v) in zip(slots, d(vals))
        i == 0 || (p[i] = v)                       # (0: a computed parameter with no slot)
    end
    return p
end
