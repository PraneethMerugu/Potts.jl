# `pdesystem(eqs, bcs = []; name, domain = [])` (F4-E6): a plain MTK `PDESystem` whose lists
# are worked out from its equations (MTK's constructor takes them all; a new `PDESystem` method
# from here would be piracy).

"""
    pdesystem(eqs, bcs = []; name, domain = [], kwargs...) -> PDESystem

A plain ModelingToolkit `PDESystem` of the equations `eqs` and conditions `bcs`, with its
independent variables, dependent variables and parameters worked out from them:

- the independent variables are the arguments of the dependent variables in `eqs` (`c(t, x, y)`
  gives `[t, x, y]`); every dependent variable an equation reads must have the same ones;
- the dependent variables are the applied callables (`@variables c(..)`): the left sides of
  the equations in order (the fields with equations), then the others (the inputs) sorted by
  name. The order of the inputs does not depend on the term order of an expression (`a + b`
  may be stored as `b + a`); it is the order the inputs keep in the coupling and in its
  fingerprint;
- the parameters are every other variable the equations and conditions read, in the order of
  their stored terms (SymbolicUtils' term order: stable for the same equations, but not always
  the order in which they are written).

```julia
@parameters x y Dc = 1.0 k = 0.1
@variables c(..) = 0.0 src(..)::Bool [input = true]
sys = pdesystem([Differential(t)(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) + src(t, x, y) - k * c(t, x, y)]; name = :sys)
# the same as PDESystem(eqs, [], [], [t, x, y], [c(t, x, y), src(t, x, y)], [Dc, k]; name = :sys)
```

`domain` is the `PDESystem`'s domain. A system coupled into a model (`@fields`,
`Potts.couple`) may leave it out: each axis takes the lattice's interval. `discretize` needs it
(`lattice_domain(t, (x, y), dims)`). Other keywords (`initial_conditions`, …) go to
`PDESystem`.
"""
function pdesystem(eqs, bcs = Equation[]; name, domain = Any[], kwargs...)
    eqs isa AbstractVector || (eqs = [eqs])
    isempty(eqs) && throw(ArgumentError("pdesystem: give at least one equation"))
    terms = Any[]                                      # the applied callables, by first appearance
    leaves = Any[]                                     # every other variable read
    seen(v, list) = any(w -> isequal(w, v), list)
    function walk(x)
        u = unwrap(x)
        u isa SymbolicUtils.BasicSymbolic || return
        SymbolicUtils.isconst(u) && return
        if iscall(u)
            op = operation(u)
            if op isa SymbolicUtils.BasicSymbolic          # `c(t, x, y)`, `c(0, x, y)`
                push!(terms, u)
                return
            end
            foreach(walk, arguments(u))
        else
            seen(u, leaves) || push!(leaves, u)
        end
    end
    for eq in eqs                                      # the left sides first: the fields with equations
        eq isa Equation || throw(ArgumentError("pdesystem: `$eq` is not an equation (`lhs ~ rhs`)"))
        walk(eq.lhs)
    end
    nlhs = length(terms)
    foreach(eq -> walk(eq.rhs), eqs)
    neq = length(terms)
    for b in bcs
        b isa Equation || throw(ArgumentError("pdesystem: the condition `$b` is not an equation (`lhs ~ rhs`)"))
        walk(b.lhs)
        walk(b.rhs)
    end
    # the independent variables: the arguments of the dependent variables of the equations
    isvar(a) = (w = unwrap(a); w isa SymbolicUtils.BasicSymbolic && !SymbolicUtils.isconst(w) && !iscall(w))
    k = findfirst(u -> all(isvar, arguments(u)), terms[1:neq])
    k === nothing && throw(ArgumentError("pdesystem: the equations read no dependent variable at its independent " *
                                         "variables (`c(t, x, y)`)"))
    ivs = Any[arguments(terms[k])...]
    for u in terms[1:neq]
        all(isvar, arguments(u)) || continue
        length(arguments(u)) == length(ivs) && all(i -> isequal(arguments(u)[i], ivs[i]), eachindex(ivs)) ||
            throw(ArgumentError(string("pdesystem: `", u, "` and `", terms[k], "` have different independent variables; ",
                "give every dependent variable the same ones, or use `PDESystem` with the lists")))
    end
    dvs, ops = Any[], Any[]
    for u in terms
        op = operation(u)
        any(o -> isequal(o, op), ops) && continue
        push!(ops, op)
        push!(dvs, all(i -> isequal(arguments(u)[i], ivs[i]), eachindex(ivs)) && length(arguments(u)) == length(ivs) ? u :
                   op(ivs...))
    end
    # the fields with equations in the order of the equations, then the inputs by name (the
    # term order of an expression is SymbolicUtils', F4-E6 review)
    isfield(u) = any(w -> isequal(operation(w), operation(u)), terms[1:nlhs])
    dvs = Any[filter(isfield, dvs); sort!(filter(!isfield, dvs); by = u -> string(nameof(operation(u))))]
    ps = Any[v for v in leaves if !seen(v, ivs)]
    return PDESystem(collect(eqs), collect(bcs), domain, Symbolics.wrap.(ivs), Symbolics.wrap.(dvs),
                     isempty(ps) ? Num[] : Symbolics.wrap.(ps); name, kwargs...)
end
