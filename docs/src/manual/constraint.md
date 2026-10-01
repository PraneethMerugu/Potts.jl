# [Constraints: `@constraint`](@id manual-constraint)

A **constraint** rejects a copy attempt outright when it does not hold, before the
Metropolis test. Each line is a condition in the copy scope (the names of
[Drives](@ref manual-drive)), or one of the built-in rules:

| Statement | Meaning |
|---|---|
| `connectivity(k₁, k₂, …)` | the losing cell (of these kinds; all kinds if none) stays locally connected around the target: its sites there form exactly one piece (CompuCell3D's `Connectivity`). A cell under this rule cannot lose its last site. |
| `connectivity(k…; rule = :arc_or_pair)` | at most one arc of the losing cell on the target's neighbour ring, or exactly two cells on it; the last site can be taken. It is modelled on the ring rule of the Tissue Simulation Toolkit but is not identical to it: medium sites on the ring are ignored |
| `no_extinction` | no copy takes a cell's last site, so cells never disappear |
| any condition | e.g. `kind[target] != wall` or `volume[old] > 5` |

A soft version of a rule is a drive: `@drive copy => λ * (local_components > 1)` penalises
fragmentation instead of forbidding it.

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
