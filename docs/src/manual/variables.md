# [Variables and scopes: `@variables`](@id manual-variables)

`@variables` declares the state of a model. Every variable has a **scope**, written like an
argument, that says where it lives:

| Declaration | Scope | One value per | Typical use |
|---|---|---|---|
| `act(site) = 0.0` | site | lattice site | memory of protrusions, labels |
| `c(field) = 0.0` | field | lattice site, integrated by a PDE | chemicals |
| `V_target(cell) = 25.0` | cell | cell | target sizes, clocks, protein levels |
| `g(model) = 0.0` | model | whole model | global signals, counters |
| `rest(bond) = 6.0` | edge of relationship `bond` | link | rest lengths of links |

The value after `=` is the default initial value. Initial values can also be given in the
operating point: `:c => c0` (an array over the lattice for site and field variables, a
vector over cells for cell variables, a number for any scope).

Options go in brackets after the default:

- `[clear_on_ownership_change = true]` (site variables): the value at a site is reset to
  0 whenever the site changes owner. This is how the "act" memory of the Act model forgets
  the previous cell.
- `[unit = u"…"]`: a unit, see [Parameters](@ref manual-parameters).
- `[guess = g]` (cell and model variables): the starting point when
  `@initialization_equations` solve for the variable, see below. A variable with a guess and
  no value is written `r(cell), [guess = -1.0]`.

A vector variable `p(cell)[1:2] = [0.0, 0.0]` has components `p_1`, `p_2`; `p ~ …`, `Pre(p)`,
`dot`, `norm` and `normalize` work component-wise.

## Initialization equations: `@initialization_equations`

Some initial values follow from others: a target volume twice the starting volume, a
protein level at its steady state, a variable that makes an algebraic quantity start at a
given value. `@initialization_equations` states them as equations, in ModelingToolkit's
syntax (MTK's `initialization_eqs`), and Potts solves them for every cell when the problem is
built, before the first MCS:

- An equation is `lhs ~ rhs`, explicit or implicit, linear or nonlinear. It reads the cell's
  own variables (bare), its built-ins `volume`, `id` and `kind`, parameters, model
  variables, and `D(x)` of a cell or model ODE variable `x`, its rate at the start
  (`D(x) ~ 0` is a steady start).
- A variable declared **without a value** (`Vt(cell)`) is solved for when an equation of its
  scope names it; otherwise it starts at 0.0, as before. A **written value**, `= 0.0`
  included, or a value in the operating point fixes the variable, as in ModelingToolkit.
- Every solved variable needs exactly one equation: too many conditions ("overdetermined",
  for example a fixed variable that an equation also determines) and too few
  ("underdetermined") are errors naming a variable, and so is an equation without a solution.
- A nonlinear equation is solved from the variable's guess (`[guess = g]`, else 0.0), which
  picks the root: `r^2 ~ volume` gives `-√volume` with `guess = -1.0`.
- An equation that reads no cell quantity is a model equation. The model is initialized first,
  and cell equations read its values.
- An operating-point value for an algebraic variable (`y ~ expr` in `@equations`) is the
  condition `y ~ value`, so the variables of its definition are solved for.
- Initialization runs when the problem is built and again on `remake(prob; u0 = map)`. A
  saved state passed as `u0` keeps its values. Daughter cells are not initialized.
- Equations read one cell (or the model). Reads of another cell (`x[j]`), neighbour gathers,
  folds over cells, and site, field and edge variables are errors for now.

```@example vars
@potts_model Initialized begin
    @kinds medium cell
    @parameters begin
        α = 0.1
        κ = 0.5
    end
    @variables begin
        V_target(cell)
        p(cell)
        r(cell), [guess = -1.0]
    end
    @lattice Lattice((30, 30))
    @energy cells(cell) => (volume - V_target)^2
    @equations D(p) ~ α * volume - κ * p
    @initialization_equations begin
        V_target ~ 2volume                # explicit
        D(p) ~ 0                          # steady start: p = α volume / κ
        r^2 ~ volume                      # the root picked by the guess
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named initialized = Initialized()
σ = zeros(Int32, 30, 30); σ[5:8, 5:8] .= 1; σ[15:17, 15:17] .= 2
prob = PottsProblem(initialized, [ownership => σ, kind => [:cell, :cell]], (0, 10))
(V_target = prob.u0.cell.V_target, p = prob.u0.cell.p, r = prob.u0.cell.r)
```

Each scope's equations are a ModelingToolkit system:
[`Potts.initialization_system(mtkcompile(sys), :cell)`](@ref Potts.initialization_system)
(`:model` for the model) is a complete `System` whose `initialization_equations` are the
equations as written, with the variables they name as unknowns and inputs such as `volume`
as parameters. Potts builds MTK's `InitializationProblem` of each scope once per problem and
solves it for every cell.

## Reading variables inside a model

What a name means depends on where it is read:

- In a **cell** context (a `cells(…)` energy term, a cell update, a division rule), a
  bare cell variable `x` is the value of the current cell, and `x[c]` of cell `c`
  (`x[owner[s]]` for the owner of site `s`).
- In a **site** context (a `sites` term, a site update, a field equation), a bare site or
  field variable is the value at the current site, `kind` the kind of its owner.
- In a **copy** context (drives, constraints, on-copy updates), sites are `source` and
  `target` and cells `new` and `old`: `c[target]`, `x[new]`, `kind[old]`.
- In a **contact** term, `x` and `x′` are a site variable's values on the two sides of the
  pair.

```@example vars
using Potts

@potts_model Scopes begin
    @kinds medium cell
    @variables begin
        mark(site) = 0.0, [clear_on_ownership_change = true]
        age(cell) = 0.0
        ncells(model) = 0.0
        pol(cell)[1:2] = [1.0, 0.0]
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells(cell) => (volume - 25.0)^2
        contacts => 8.0 * (kind != kind′)
    end
    @on_copy mark[target] ~ 1.0                       # copy scope: a site written
    @after_mcs begin
        age += 1                                       # cell scope
        ncells ~ count(true for c in cells)            # model scope: a population fold
        pol ~ normalize(Pre(pol) .+ [0.0, 0.1])        # a vector, component-wise
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named scopes = Scopes()
op = layout(Tiling((5, 5); region = (6:25, 6:25), spacing = 1, kinds = [:cell]), scopes)
sol = solve(PottsProblem(scopes, [op; :age => 10.0], (0, 20)), SequentialCPM())
(age = sol[:age][end][1], ncells = sol[:ncells][end], marked = count(>(0), sol[:mark][end]),
 pol = (sol[:pol_1][end][1], sol[:pol_2][end][1]))
```

## Built-in quantities

These names are always available where they make sense:

| Name | Meaning | Where |
|---|---|---|
| `volume`, `surface` | sites of the cell; bonds to other owners | cell |
| `kind`, `id`, `generation` | kind, number and generation of the cell | cell |
| `major_length` | length of the cell's long axis | cell, energies |
| `centroid(k)` | coordinate `k` of the centroid | cell (not energies) |
| `integral(x)` | sum of the site expression `x` over the cell's sites | cell (not energies, drives, constraints or on-copy updates) |
| `owner`, `kind`, `position` | owner, its kind, coordinates (`position[1]`) of a site | site |
| `kind′`, `owner′`, `weight` | the other side of a contact pair, the relation weight | contacts |
| `source`, `target`, `new`, `old` | the sites and cells of a copy | drives, constraints, on-copy |
| `displacement(c, k)` | shift of cell `c`'s centroid along `k` if the copy is accepted | drives |
| `a`, `b`, `distance` | the two cells of a link, their centroid distance | edges, link rules |
| `mcs`, `time` | the current MCS, and the time (`mcs × mcs_duration`) | updates, equations, rules |
| `cluster`, `cluster_volume`, `cluster_surface` | compartments (see [Energy](@ref manual-energy)) | cell |
