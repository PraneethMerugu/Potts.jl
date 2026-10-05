# [Constraints: `@constraint`](@id manual-constraint)

A **constraint** rejects a copy attempt outright when it does not hold, before the
Metropolis test. Each line is a condition in the copy scope (the names of
[Drives](@ref manual-drive)), or one of the built-in rules:

| Statement | Meaning |
|---|---|
| `connectivity(k₁, k₂, …)` | the losing cell (of these kinds; all kinds if none) stays locally connected around the target: its sites there form exactly one piece (CompuCell3D's `Connectivity`). A cell under this rule cannot lose its last site. |
| `connectivity(k…; rule = :arc_or_pair)` | at most one piece of the losing cell on the target's neighbour shell, or else exactly two cells and no medium on it (the ring rule of the Tissue Simulation Toolkit); the last site can be taken |
| `no_extinction` | no copy takes a cell's last site, so cells never disappear |
| any condition | e.g. `kind[target] != wall` or `volume[old] > 5` |

Conditions follow the rules of drives: `rand()` and `integral` are not allowed; keep an
integral in a cell variable updated `@before_mcs` and read it as `s[new]`, `s[old]` (see
[Drives](@ref manual-drive)).

Both rules read the target's **neighbour shell**, whatever the model's neighbourhood: the 8
surrounding sites on a square lattice, the 6 on a hexagonal one, the 26 on a cubic 3D one.
`local_components` (and `ring_arcs`, the same count) is the number of pieces the losing
cell's shell sites form, two sites joined when they are lattice face neighbours; on a 2D
ring these pieces are its arcs. `ring_cells` and `ring_medium` count the cells and the
medium sites on the shell. Sites outside the lattice (a closed face) are neither; a periodic
axis wraps. So both rules work on every geometry, in 2D and 3D.

A soft version of a rule is a drive: `@drive copy => λ * (local_components > 1)` penalises
fragmentation instead of forbidding it. The soft arc-or-pair rule, the `E₀` threshold of
Merks et al. (TST's `conn_diss`), charges `E₀` to every copy the hard rule would refuse:

```julia
@drive copy => E₀ * ((kind[old] == A) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))
```

These rules are local: they see only the shell around each copy, so a cell can still
become a ring or lose a piece far away. The global count, `components(old; scope =
Global())`, is a reserved name: a model using it is an `ArgumentError` when it is built,
until it is implemented.

```@example constraint
using Potts

@potts_model Fragile begin
    @structural_parameters begin
        connected = true
    end
    @kinds medium cell
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        cells(cell) => 0.2 * (volume - 60.0)^2
        contacts => 2.0 * (kind != kind′)
    end
    if connected
        @constraint connectivity(cell)
    end
    @sweep Metropolis(; temperature = 30.0)
end

# number of pieces of cell 1, on 4-neighbour steps
function pieces(σ, c)
    seen = falses(size(σ)); n = 0
    for x in CartesianIndices(σ)
        (σ[x] == c && !seen[x]) || continue
        n += 1; stack = [x]; seen[x] = true
        while !isempty(stack)
            y = pop!(stack)
            for d in (CartesianIndex(1, 0), CartesianIndex(-1, 0), CartesianIndex(0, 1), CartesianIndex(0, -1))
                z = y + d
                checkbounds(Bool, σ, z) && σ[z] == c && !seen[z] && (seen[z] = true; push!(stack, z))
            end
        end
    end
    return n
end

op = layout(Tiling((8, 8); region = (17:24, 17:24), kinds = [:cell]), Fragile(; name = :f))
[pieces(solve(PottsProblem(Fragile(; name = :f, connected = c), op, (0, 100); seed = 1),
              SequentialCPM()).u[end].σ, 1) for c in (true, false)]
```

At this high temperature the unconstrained cell breaks into pieces; with
`connectivity(cell)` it stays whole. Connectivity is checked locally around each copy, so
it is cheap, and works on the GPU.
