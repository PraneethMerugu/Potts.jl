# [Models: `@potts_model`](@id manual-models)

A model is written with `@potts_model Name begin … end`. The block holds **sections**, each
a macro call such as `@kinds` or `@energy`. The macro defines a constructor function
`Name(; name, kwargs...)` that builds the model, a `PottsSystem`, in the same way that
ModelingToolkit's `@mtkmodel` defines a constructor for a system.

## The sections

| Section | Purpose | Page |
|---|---|---|
| `@structural_parameters` | values fixed when the model is built (lattice size, switches) | this page |
| `@kinds` | cell kinds; the first is the medium; `[frozen]` marks obstacles | [Kinds](@ref manual-kinds) |
| `@parameters` | numbers of the model, scalars or kind-indexed tables | [Parameters](@ref manual-parameters) |
| `@variables` | state with a scope: `x(site)`, `x(cell)`, `x(model)`, `c(field)`, `e(rel)` | [Variables and scopes](@ref manual-variables) |
| `@lattice`, `@relations` | the grid and the neighbourhoods | [Lattices and relations](@ref manual-lattice) |
| `@energy` | the terms of the Hamiltonian | [Energy](@ref manual-energy) |
| `@drive` | non-energetic biases of copy attempts | [Drives](@ref manual-drive) |
| `@constraint` | hard rules on copy attempts | [Constraints](@ref manual-constraint) |
| `@before_mcs`, `@after_mcs`, `@on_copy` | discrete updates | [Updates](@ref manual-updates) |
| `@equations` | PDEs for fields, ODEs for cells and the model, component couplings | [Equations and solvers](@ref manual-equations) |
| `@components` | ModelingToolkit systems in every cell or once in the model | [Equations and solvers](@ref manual-equations) |
| `@divide` | cell and cluster division | [Lifecycle](@ref manual-lifecycle) |
| `@relationship`, `@link`, `@unlink` | links between cells | [Relationships](@ref manual-relationships) |
| `@observed` | derived quantities | [Observables](@ref manual-observables) |
| `@sweep` | acceptance rule, temperature, MCS duration | [Sweep](@ref manual-sweep) |
| `@extend` | build on another model | this page |

`@lattice` and `@sweep` are required (an extension may inherit them). Other lines in the
block are ordinary Julia, evaluated when the model is built; use them for helper functions.

## Building a model

```@example models
using Potts

@potts_model Blobs begin
    @structural_parameters begin
        n = 40                        # lattice size
    end
    @kinds medium blob
    @parameters begin
        λ = 1.0
        V₀ = 30.0
        T = 8.0
    end
    @lattice Lattice((n, n); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        contacts => 10.0 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = T)
end

@named blobs = Blobs()
```

`@named x = Name(...)` passes `name = :x`; `Name(; name = :x)` is the same. Keyword
arguments change structural parameters and parameter defaults:

```@example models
big = Blobs(; name = :big, n = 80, V₀ = 50.0)
big.lattice.dims
```

**Structural parameters** are fixed when the model is built: they size the lattice or
switch sections on and off. **Parameters** can also be changed later, per problem, with
`remake`, without rebuilding anything.

## Conditional sections

An `if` whose branches hold sections is evaluated when the model is built, so a structural
parameter can switch statements on or off:

```@example models
@potts_model MaybeConnected begin
    @structural_parameters begin
        connected = false
    end
    @kinds medium blob
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 30.0)^2
        contacts => 10.0 * (kind != kind′)
    end
    if connected
        @constraint connectivity(blob)
    end
    @sweep Metropolis(; temperature = 8.0)
end

length(MaybeConnected(; name = :a).constraints), length(MaybeConnected(; name = :b, connected = true).constraints)
```

Declaring sections (`@structural_parameters`, `@kinds`, `@parameters`, `@variables`,
`@extend`) cannot be conditional.

## Extending a model

`@extend` builds on another model, like ModelingToolkit's `@extend`:

```@example models
@potts_model StickyBlobs begin
    @extend λ, V₀, blob = base = Blobs(; n = 50)
    @parameters μ = 0.5
    @energy cells(blob) => μ * volume       # added to the base's terms
end

@named sticky = StickyBlobs()
```

- `base = Blobs(; n = 50)` builds the base model with keyword overrides.
- `λ, V₀, blob = …` binds names of the base for use in the extension: parameters, variables,
  kinds, relations.
- Terms, drives, constraints and rules accumulate, base first. An update or equation of
  the same variable replaces the base's.
- An extension without `@lattice`, `@sweep` or `@kinds` inherits the base's. An extension
  that adds kinds lists the base's first: `@kinds medium blob wall[frozen]`.
- Redeclaring a base name in its own category overrides it: `@parameters λ = 3.0` gives the
  base's `λ` a new default, `@variables x(cell) = 1.0` replaces the base's variable `x`. A
  base name cannot change category (a base parameter `x` and an extension variable `x(cell)`):
  that is an error that names both (see [Names](#Names)). A name bound by `@extend` and
  redeclared takes the extension's default (or the extension's keyword), and every
  expression that reads it uses that one value.

`extend(sys, base)` is the functional form.

## Inspecting a model

Printing a model lists its parts. `parameters(sys)` and `variables(sys)` return the
declared symbols, and `Potts.lookup(sys, :λ)` finds a quantity by name.
`generated_code(sys)` returns the code Potts generates (the energy change of a copy,
updates, and so on) as Julia expressions, for the curious.

```@example models
parameters(sticky)
```

## Names

Some names are built in (`volume`, `surface`, `kind`, `kind′`, `owner`, `source`,
`target`, `new`, `old`, `mcs`, `position`, `distance`, `id`, …) and cannot be declared. `a`
and `b` are reserved for the two cells of a link. `t` and `D` are the time variable and
derivative of ModelingToolkit. Declaring any of these is an error that names the clash.

A model has one namespace: a name is a kind, a parameter, a variable, an observed quantity,
a relation, a relationship or a component, never two of these. This holds for the names a
model inherits through `@extend` (or `extend`), for the components of a vector and for a
component's quantities. A vector `w[1:2]` also names its components `w_1` and `w_2`, so no
other quantity may be called `w_1`, not even a scalar parameter (an extension overrides a
vector as a whole, and the new vector may be longer than the base's but not shorter:
`@parameters w[1:3] = …` over `w[1:2]`). The unknown `y` of the component `clk` is
`clk₊y`, and no parameter or variable may take that name. A name in two categories is an
error that names both.

A model constructor is a Julia function in your module, so avoid names that clash with
functions you load (for example `Toggle`, `Axis` or `Label` from Makie): Julia warns about
such a clash, and the plotting function stops working.
