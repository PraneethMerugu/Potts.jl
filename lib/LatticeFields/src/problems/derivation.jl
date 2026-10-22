# The computed parameters of a problem (F2 design §2.7, D-F2-1): one compiled function from the
# base values to the computed values, shared by both front ends.

"""
    Derivation

The computed parameters of a model or system as one compiled function (F2 design §2.7,
D-F2-1). `d(vals)` maps the base values `vals` (a tuple in the order of `d.base`: numbers and
tables) to the computed values (a tuple in the order of `d.computed`: a number, or an array for
a kind table with expression entries). `LatticePDE.derivation` builds it; a front end calls it
after every write of base values. Its rules are D-117's: Base and registered functions,
integer division, a lazy `ifelse`, and a kind-table read by kind number (the medium is 0), in
the number type of the values given. An evaluation that fails is an `ArgumentError` that names
the computed parameter.
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

Entry `ks` of kind table `t` in a derivation, by kind numbers (the medium is 0, then the kinds
in order): `t[ks .+ 1...]`. `name` is the computed parameter that reads it, for the message.
"""
function derive_at(name, t, ks...)
    t isa AbstractArray && ndims(t) == length(ks) ||
        throw(ArgumentError(string("it reads a kind table with ", length(ks), length(ks) == 1 ? " kind" : " kinds",
            "; the table takes ", t isa AbstractArray ? ndims(t) : 0)))
    for k in ks
        k isa Real && isinteger(k) || throw(ArgumentError("it reads a kind table at `$k`, not a kind number"))
    end
    i = map(k -> Int(k) + 1, ks)
    checkbounds(Bool, t, i...) ||
        throw(ArgumentError("it reads kind $(join(ks, ", ")) of a kind table with kinds 0:$(size(t, 1) - 1)"))
    return t[i...]
end

# an evaluation of computed parameter `name` (its default written `text`) that failed
derive_fail(name, text, e) = throw(ArgumentError(string("parameter `", name, "` = `", text,
    "` fails on the parameter values: ", e isa ArgumentError ? e.msg : sprint(showerror, e))))

# the computed slots of a problem's parameter vector `p`, from its base slots and tables (B:
# the index's `derive`, `(d, sources, slots)`; a source is a slot number or a table key, a
# slot 0 a computed parameter that no slot holds)
function derive!(p, tables, ix)
    ix isa LatticeIndex || return p
    ix.derive === nothing && return p
    d, src, slots = ix.derive
    vals = Tuple(s isa Integer ? p[s] : last(tables[findfirst(x -> first(x) == s, tables)]) for s in src)
    for (i, v) in zip(slots, d(vals))
        i == 0 || (p[i] = v)                       # (0: a computed parameter with no slot)
    end
    return p
end
