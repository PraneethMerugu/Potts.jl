# [Symbolic indexing](@id manual-indexing)

Potts implements [SymbolicIndexingInterface](https://docs.sciml.ai/SymbolicIndexingInterface/stable/),
as ModelingToolkit does: any quantity of a model can be read by name from a solution, a
problem or an integrator.

| Call | Returns |
|---|---|
| `sol[:x]` | `x` at every saved time |
| `sol[:x][i]` | at the `i`-th saved time |
| `getu(sol, :x)` | a fast reader function, `getu(sol, :x)(sol)` |
| `getp(prob, :λ)(prob)` | a parameter value |
| `integ[:x]`, `integ[:x] = v` | read or write a declared variable of a running integrator |
| `integ.ps[:λ]`, `integ.ps[:λ] = v` | read or write a parameter of a running integrator |
| `setu(integ, :x)(integ, v)`, `setp(integ, :λ)(integ, v)` | setter functions |

The shape of a value follows the scope of the quantity: a vector over cells for cell
quantities (dead cells and free slots included; filter with `volume > 0`), an array over
the lattice for site and field quantities, and a number for model quantities.

A setter for a list of names is one change. `setp(integ, [:α, :β])` sets parameters only (a
variable in its list is an error that points to `setu`). SymbolicIndexingInterface's
`setsym(integ, [:α, :β, :age])` (exported as its alias `setu`) sets the variables in its
list, and all the listed parameters together. A rejected value leaves every parameter as it
was. A problem built from a hand-written `CPMFunction` (no
model) whose parameter object is a NamedTuple has that tuple's fields as its parameter
names, so `getp(integ, :T)`, `setp(integ, :T)` and `integ.ps[:T]` work on it.

Names that work: declared variables (`:age`, `:c`), component variables (`:clock₊m`),
`@observed` quantities, and built-ins (`:volume`, `:kind`, `:generation`, and others the
model uses, such as `:surface`). Built-ins and observed quantities are read-only.

```@example indexing
using Potts

@potts_model Indexed begin
    @kinds medium cell
    @parameters λ = 1.0
    @variables begin
        age(cell) = 0.0
        c(site) = 0.0
        total(model) = 0.0
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells(cell) => λ * (volume - 25.0)^2
        contacts => 8.0 * (kind != kind′)
    end
    @after_mcs begin
        age += 1
        total ~ sum(volume for k in cells)
    end
    @observed big(cell) ~ volume > 25
    @sweep Metropolis(; temperature = 8.0)
end

@named indexed = Indexed()
op = layout(Tiling((5, 5); region = (6:25, 6:25), spacing = 1, kinds = [:cell]), indexed)
prob = PottsProblem(indexed, op, (0, 20))
sol = solve(prob, SequentialCPM(); saveat = 10)
(age = sol[:age][end][1:3], total = sol[:total], big = sol[:big][end][1:3],
 c = size(sol[:c][end]), λ = getp(prob, :λ)(prob))
```

A quantity that the model does not use is not tracked: `sol[:surface]` is an error in a
model without a surface term. To track it, add a surface term whose strength is a
parameter, and set that parameter to 0.
