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
| `J[medium, cell] = 16` | one entry of a table, by kind name (below) |
| `J[kind, kind] = 0.0` | the value of every entry not listed by name |
| `μ[kind, kind] = 0.0, [symmetric = false]` | a two-kind table whose (k₁, k₂) and (k₂, k₁) entries differ |
| `d[1:2] = [1.0, 0.5]` | a vector; its components are `d_1`, `d_2` |
| `λ = 1.0, [unit = u"J"]` | a parameter with a unit (see below) |
| `T = 1.0, [tunable = false, bounds = (0, 10), description = "…"]` | a parameter with ModelingToolkit's other metadata (see below) |

Every parameter is a ModelingToolkit parameter (`ModelingToolkitBase.isparameter` is true). A
kind table is an array parameter, `J[1:n, 1:n]` for `n` kinds with the medium. A model reads a
table entry `J[kind, neighbor_kind]` as LatticePDE's registered read
`value_at(J, kind, neighbor_kind)` (`value_at(J, kind)` for a one-kind table). It never uses
ModelingToolkit's own indexing, because a compiled cell template cannot take an input as an
index. A field equation reads a pair table the same way, with two integer inputs as the
indices.

```@example params
using Potts
using Potts.Layouts

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
        contacts => J[kind, neighbor_kind]
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

`p` can be a NamedTuple (`remake(prob; p = (λ = 5.0,))`), a vector of pairs or a `Dict`;
all three mean the same change. A name that is not a parameter, or a value that is none of
these nor a whole parameter object (below), is an `ArgumentError`. A NamedTuple also works
for `u0`, as for the operating point. As in SciML, `p = missing` (or `nothing`) keeps the
problem's parameters, and `u0 = missing` (or `nothing`) keeps its state.

A computed default such as `V_big = 2A₀` follows its inputs: `remake` with a new `A₀` also
changes `V_big`. The entries of a kind table can be computed the same way
(`V₀[kind] = [0.0, V_big, A₀]` above, or `J[kind, kind] = [0 Jx Jx; Jx 2 Jx-5; Jx Jx-5 14]`),
and the table follows its inputs too.

```@example params
prob3 = remake(prob; p = [:A₀ => 30.0])
getp(prob3, :V_big)(prob3), getp(prob3, :V₀)(prob3)
```

A computed parameter is read-only, as in ModelingToolkit. It is evaluated when the problem is
built, from the operating point and the other defaults, and evaluated again from the base
parameters after every change: `remake`, a setter (`integ.ps[:A₀] = 25.0`), `setp` or
`SciMLStructures.replace`. Chains follow their inputs: with `β = 2α` and `γ = β + 1`, a new
`α` moves `β` and `γ`. Reads work everywhere (`getp(prob, :V_big)`, `integ.ps[:V_big]`,
`sol.ps[:V_big]`). A write of a computed parameter, in the operating point, `remake`, `setp`,
`integ.ps[x] = v` or `setsym`, is an `ArgumentError` that names its expression and its
inputs, and nothing is set; a list that names one is refused whole. For a fixed value,
declare the parameter with a number through the constructor keyword: `Params(; V_big = 50.0)`
makes `V_big` a base parameter (a new parameter type, so the model compiles once more).
A parameter object given whole (`remake(prob; p = checkpoint.p)`) gives its base values, and
the computed ones are evaluated again, so a checkpoint restores exactly. One with other
parameter names is an `ArgumentError`. Computed parameters are evaluated through one compiled
function, the same in a LatticePDE problem.

A computed default, scalar or table entry, is evaluated as a number. It may use Julia's
functions (`sqrt`, `exp`, `log`, `min`, `max`, `floor`, `mod`, `div` or `÷`, and so on),
comparisons with `ifelse`, `c ? a : b` and `&&`, constants such as `π`, and functions
registered with `@register_symbolic`. It may also read an entry of a kind table. A kind is
indexed by its number as everywhere in a model: the medium is 0, then the kinds follow in
`@kinds` order, and a kind's name stands for its number. With `@kinds medium dark light`,
`u = V₀[2] + 1` and `u = V₀[light] + 1` are the same. A default cannot read a variable or a
built-in such as `volume`, cannot draw `rand()`, and cannot read a kind outside the table.
Each of these is an `ArgumentError` that names the parameter. So is a function that fails on
the values, such as `sqrt` of a negative number. A call on literal numbers only, such as
`sqrt(-1.0)`, is evaluated by Julia when the model is built, so its error (here a
`DomainError`) comes from the model constructor. A model may not define its own `div` or
`÷`, since in a model these are integer division.

The inputs of a computed default must be declared before it in `@parameters`.

Values are converted to the problem's number type (`Float64`, or `Float32` for GPU
problems), so a `remake` never changes the compiled code.

## Tables by kind name

A table written as a matrix depends on the order of the kinds, and a swapped row is easy to
miss. Write each entry by its kind names instead, one line per entry:

```@example params
@potts_model Named begin
    @kinds medium dark light
    @parameters begin
        V₀[kind] = 0.0                   # every entry not listed below
        V₀[dark] = 40.0
        V₀[light] = 20.0
        J[medium, medium] = 0
        J[medium, dark] = 16
        J[medium, light] = 16
        J[dark, dark] = 2
        J[dark, light] = 11              # also J[light, dark]
        J[light, light] = 14
    end
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => (volume - V₀[kind])^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 10.0)
end

@named named = Named()
nprob = PottsProblem(named, layout(Tiling((5, 5); region = (11:30, 11:30),
    kinds = [:dark, :light]), named), (0, 10))
getp(nprob, :J)(nprob)
```

- An entry is `J[k₁, k₂] = v` (or `V₀[k] = v` for a one-kind table). `k₁` and `k₂` are kind
  names from `@kinds`, including the medium. `v` is a number or an expression of
  parameters, as in the matrix form.
- A two-kind table is symmetric: `J[dark, light] = v` sets both `J[dark, light]` and
  `J[light, dark]`. List one of the two.
- The line `J[kind, kind] = v` gives the value of every entry that is not listed. Without
  it, list every entry.
- The table becomes the same array as the matrix form. The parameter object, the generated
  code and `remake` are identical, so names cost nothing at run time.
- In a model that extends another (`@extend`) and has no `@kinds` of its own, the entries
  use the kind names the extension binds.

### Asymmetric tables

A table whose (k₁, k₂) and (k₂, k₁) entries differ, such as a cell-surface coefficient
indexed by a cell's kind and its neighbor's, is declared with the option
`symmetric = false` on its `kind, kind` line. An entry then sets one side only:

```julia
μ[kind, kind] = 1.0, [symmetric = false]
μ[dark, light] = 4.0                   # μ[light, dark] stays 1.0
μ[light, dark] = 9.0
```

The option applies to the matrix form too (`μ[kind, kind] = [1 2; 3 4], [symmetric = false]`).
A table without it must be symmetric for every value it takes: when the model is built, in
`remake`, in a setter and in the operating point. An asymmetric value is an `ArgumentError`
that names the two entries.

### Changing entries by name

`remake`, setters and the operating point take a table's entries by name. The entries not
listed keep their values, and a symmetric entry sets both sides:

```@example params
nprob2 = remake(nprob; p = [:J => [(:dark, :light) => 14.0], :V₀ => [:dark => 30.0]])
getp(nprob2, :J)(nprob2)[2, 3], getp(nprob2, :J)(nprob2)[3, 2], getp(nprob2, :V₀)(nprob2)
```

The same entries work in `integ.ps[:J] = [(:dark, :light) => 14.0]` and in the operating
point. A table with an entry computed from parameters (`J[dark, light] = Jx`) is a
computed parameter: change its inputs (`remake(prob; p = [:Jx => 14.0])`) instead.

### Errors

Each of the following is an `ArgumentError` when the model is defined or built. The message
names the table and the entry, and suggests the fix:

- a matrix of the wrong size. A matrix one row and one column short usually lacks the
  medium's row and column, and the message says so;
- named entries without a value for the medium, or for any other kind, when the table has
  no `J[kind, kind] = v` line;
- a name in an entry that is not a kind of `@kinds`, such as a misspelling, a parameter or
  a kind class;
- an entry given twice;
- in a symmetric table, `J[k₁, k₂]` and `J[k₂, k₁]` both listed. Two different values
  conflict; two equal values repeat. List one.

## Units

A parameter takes ModelingToolkit's metadata `tunable`, `bounds` and `description` too, and
`ModelingToolkitBase.istunable`, `getbounds` and `getdescription` read it:

- `tunable = false` moves the parameter from `SciMLStructures.Tunable` to `Constants`.
- `bounds = (lo, hi)` holds at every value the parameter takes: a value outside it, at
  build, in `remake`, in a setter or in `SciMLStructures.replace`, is an `ArgumentError` that
  names the bound, and nothing changes. A LatticePDE problem checks the bounds of a
  `PDESystem`'s parameters the same way.
- `description` is a string that `show` prints with the model's parameters.

A component's parameters keep their metadata. A component's ModelingToolkit binding of
parameters, `k2 = 2k`, is the computed parameter `comp₊k2` (see below), and an initial value
of parameters, `y(t) = 2k` or `initial_conditions = [y => 2k]`, is the cell variable's
default. An initial value that reads an unknown is an error that names the component.

Parameters, variables and fields can carry units as ModelingToolkit metadata,
`λ = 1.0, [unit = u"J"]`. When the package DynamicQuantities is loaded, compiling the model
checks that every energy term, update and equation is dimensionally consistent. Built-in
quantities (`volume`, `surface`, distances) are in lattice units. Without DynamicQuantities
the units are ignored.
