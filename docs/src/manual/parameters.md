# [Parameters: `@parameters`](@id manual-parameters)

`@parameters` declares the numbers of a model with their defaults. Parameters can be
changed per problem (`remake(prob; p = [...])`), per run (`integ.ps[:T] = 5.0` in a
callback) and per trajectory of an ensemble, without regenerating code.

| Form | Meaning |
|---|---|
| `λ = 1.0` | a scalar |
| `V₀ = 2A₀` | a default computed from other parameters |
| `J[kind, kind] = [0 16; 16 2]` | a table indexed by two kinds (medium first) |
| `V₀[kind] = [0.0, 40.0, 25.0]` | a table indexed by one kind |
| `J[kind, kind] = [0 Jx; Jx 2]` | a table whose entries are computed from other parameters |
| `d[1:2] = [1.0, 0.5]` | a vector; its components are `d_1`, `d_2` |
| `λ = 1.0, [unit = u"J"]` | a parameter with a unit (see below) |

```@example params
using Potts

@potts_model Params begin
    @kinds medium dark light
    @parameters begin
        A₀ = 20.0
        V_big = 2A₀                            # computed from A₀
        V₀[kind] = [0.0, V_big, A₀]            # a table computed from A₀
        λ = 1.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        drift[1:2] = [0.5, 0.0]
    end
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀[kind])^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 10.0)
end

@named params = Params(; λ = 2.0)          # keyword: a new default
op = layout(Tiling((5, 5); region = (11:30, 11:30), kinds = [:dark, :light]), params)
prob = PottsProblem(params, op, (0, 10))
prob.p
```

`prob.p` holds the values. Read one with `getp(prob, :λ)(prob)`; change them with `remake`,
by name or by symbol:

```@example params
prob2 = remake(prob; p = [:λ => 5.0, :J => [0 16 16; 16 2 14; 16 14 14]])
getp(prob2, :λ)(prob2), getp(prob2, :J)(prob2)[2, 3]
```

A computed default such as `V_big = 2A₀` follows its inputs: `remake` with a new `A₀` also
changes `V_big`. The entries of a kind table can be computed the same way
(`V₀[kind] = [0.0, V_big, A₀]` above, or `J[kind, kind] = [0 Jx Jx; Jx 2 Jx-5; Jx Jx-5 14]`),
and the table follows its inputs too.

```@example params
prob3 = remake(prob; p = [:A₀ => 30.0])
getp(prob3, :V_big)(prob3), getp(prob3, :V₀)(prob3)
```

A computed parameter is evaluated when the problem is built, from the operating point and
the other defaults. A value given explicitly (in the operating point of `PottsProblem`, by
`remake(prob; p = …)` or by a setter of a running integrator, `integ.ps[:A₀] = 25.0`)
replaces the expression and is kept until one of the expression's inputs changes. Each
`remake` and each setter is one change: it re-evaluates a computed parameter only if the
parameter is not given in that change and one of its inputs is given in it or is itself
re-evaluated by it. So after `remake(prob; p = [:V₀ => [0.0, 30.0, 30.0]])`, a later change
of `λ` keeps those numbers, while a change of an input of `V₀` evaluates `V₀` from its
expression again (give `V₀` in the same change to keep it). Chains follow their inputs: with
`β = 2α` and `γ = β + 1`, changing `α` re-evaluates `β` and `γ` even if `β` was set, and
changing `β` re-evaluates `γ`. The same holds for scalar computed defaults such as `V_big`.
A parameter object given whole (`remake(prob; p = checkpoint.p)`) sets every value.

The inputs of a computed default must be declared before it in `@parameters`. A contact
table (`J[kind, kind′]`) must be symmetric for the values it takes; an asymmetric one is an
`ArgumentError`.

Values are converted to the problem's number type (`Float64`, or `Float32` for GPU
problems), so a `remake` never changes the compiled code.

## Units

Parameters, variables and fields can carry units as ModelingToolkit metadata,
`λ = 1.0, [unit = u"J"]`. When the package DynamicQuantities is loaded, compiling the model
checks that every energy term, update and equation is dimensionally consistent. Built-in
quantities (`volume`, `surface`, distances) are in lattice units. Without DynamicQuantities
the units are ignored.
