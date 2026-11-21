# One derivation of computed parameters for Potts and discretize.

"""
    derivation(base, computed) -> LatticeFields.Problems.Derivation

The computed parameters `computed` (`name => default`, the default an expression of the
parameters, or an array with expression entries for a kind table) as one compiled function
of the base parameters `base` (names, in the order of the values the derivation takes).
Chains (`k3 = 2k2`, `k2 = 3a`) evaluate in their order; a cycle is an `ArgumentError`. The
rules are those of `LatticeFields.Problems.Derivation`: the expression is compiled as
written (Base and registered functions, `÷` as integer division, a lazy `ifelse`), and a
kind-table read `value_at(t, k)` or `value_at(t, k, l)` takes kind numbers (medium 0). Potts
and `discretize` call it; a caller that keeps computed values (Potts' parameter object,
`LatticePDE`'s computed slots) evaluates it after every write of base values.

# Arguments
- `base::AbstractVector`: the names of the base parameters, in the order of the values the
  derivation takes.
- `computed::AbstractVector`: the computed parameters, as `name => default` pairs.

# Returns
- The compiled `LatticeFields.Problems.Derivation`.
"""
function derivation(base::AbstractVector, computed::AbstractVector)
    names = Symbol[Symbol(first(c)) for c in computed]
    defs = Dict{Symbol, Any}(Symbol(first(c)) => last(c) for c in computed)
    function reads(e)
        if e isa AbstractArray
            return reduce(union, (reads(x) for x in e); init = Set{Symbol}())
        elseif _isterm(e)
            return Set{Symbol}(_varname(v) for v in Symbolics.get_variables(e))
        else
            return Set{Symbol}()
        end
    end
    deps = Dict(n => intersect(reads(defs[n]), names) for n in names)
    order, done = Symbol[], Set{Symbol}()
    while length(order) < length(names)
        k = findfirst(n -> !(n in done) && issubset(deps[n], done), names)
        k === nothing && throw(
            ArgumentError(
                "the computed parameters " *
                    join(("`$n = $(defs[n])`" for n in names if !(n in done)), ", ") *
                    " read one another in a cycle"
            )
        )
        push!(order, names[k])
        push!(done, names[k])
    end
    vs, er = gensym(:vals), gensym(:err)
    body = Any[:($(Symbol(b)) = $vs[$i]) for (i, b) in enumerate(base)]
    for n in order
        e = defs[n]
        ex = e isa AbstractArray ? _array_expr(n, e) : _derive_expr(n, e)
        push!(
            body, :(
                $n = try
                    $ex
                catch $er
                    $(isfatal)($er) && rethrow()
                    $(Problems.derive_fail)(
                        $(QuoteNode(n)), $(as_written(_deftext(e))),
                        $er
                    )
                end
            )
        )
    end
    fn = Expr(:->, vs, Expr(:block, body..., Expr(:tuple, names...)))
    return Problems.Derivation(Problems.rgf(fn), Symbol[Symbol(b) for b in base], names)
end
_isterm(e) = e isa Union{Num, SymbolicUtils.BasicSymbolic}
function _varname(v)
    (
        u = unwrap(v);
        if iscall(u) && operation(u) === getindex
            _varname(arguments(u)[1])
        else
            Symbol(string(u))
        end
    )
end
_deftext(e) = e isa AbstractArray ? string(e) : replace(string(e), "LatticePDE." => "")
# an entry or a scalar default as Julia code: `value_at` read by kind number
function _derive_expr(n, e)
    _isterm(e) || return e isa Number ? e : unwrap_const(e)
    u = unwrap(e)
    SymbolicUtils.isconst(u) && return unwrap_const(u)
    return _kind_reads(n, toexpr(e))
end
function _kind_reads(n, ex)
    ex isa Expr || return ex
    args = Any[_kind_reads(n, a) for a in ex.args]
    if ex.head === :call && (args[1] === value_at)
        return Expr(:call, Problems.derive_at, QuoteNode(n), args[2:end]...)
    end
    return Expr(ex.head, args...)
end
function _array_expr(n, e)
    return Expr(
        :call, reshape, Expr(:vect, (_derive_expr(n, x) for x in vec(e))...),
        size(e)
    )
end
