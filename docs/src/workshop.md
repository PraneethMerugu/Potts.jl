# [Workshop: lab exercises](@id workshop)

These exercises practise the tutorials. Each one states a question, gives a starting point,
and hides an answer: click **Answer** to open it. Try first; the answers are one way to do
it, not the only one. Runs are kept short so that every exercise runs in seconds on a laptop.

Start every session with:

```@example workshop
using Potts, PottsModels, MakiePotts, CairoMakie
using Statistics: mean
CairoMakie.activate!(type = "png") # hide
nothing # hide
```

## Exercise 1: make sorting fail

Start from the Graner & Glazier (1992) model with the paper's parameters and aggregate.
The sorting depends on the order of the contact energies. **Change one entry of `J` so
that the aggregate no longer sorts**, and show it with a number.

Starting point (the paper's model; the run is 1600 MCS, 100 of the paper's MCS, instead
of the paper's 10⁴):

```@example workshop
σ0, kinds0 = graner_glazier_state()
@named gg = GranerGlazier(; lattice = size(σ0))
prob = PottsProblem(gg, [ownership => σ0, kind => kinds0], (0, 1600); seed = 1)
getp(prob, :J)(prob)          # rows and columns: medium, dark, light
```

The paper's run, for reference:

```@example workshop
Main.paper_run("graner_glazier", "../") # hide
```

!!! details "Hint"
    Sorting needs a positive surface tension between the kinds,
    ``J_{dl} - (J_{dd} + J_{ll})/2 > 0``. A measure of mixing is the fraction of
    dark–light contacts among all cell–cell contacts.

!!! details "Answer"
    With `J(dark, light) = 8` (paper: 11) the tension is zero, so mixing costs nothing. We
    compare the fraction of heterotypic contacts at the end of both runs:

    ```@example workshop
    function heterotypic_fraction(u)
        σ, k = u.σ, u.cell.kind
        mixed = total = 0
        for x in CartesianIndices(σ), step in ((1, 0), (0, 1), (1, 1), (1, -1))
            y = CartesianIndex(mod1.(Tuple(x) .+ step, size(σ)))
            a, b = σ[x], σ[y]
            (a == b || a == 0 || b == 0) && continue
            total += 1
            mixed += k[a] != k[b]
        end
        return mixed / total
    end
    paper = solve(prob, SequentialCPM())
    neutral = solve(remake(prob; p = [:J => [0 16 16; 16 2 8; 16 8 14]]), SequentialCPM())
    (start = heterotypic_fraction(prob.u0), paper = heterotypic_fraction(paper.u[end]),
     neutral = heterotypic_fraction(neutral.u[end]))
    ```

    In the paper's model the fraction falls; with the neutral table it stays near its
    starting value.

## Exercise 2: temperature

**How does the temperature change sorting?** Run the paper's model at `T = 2`, `10` (the
paper's value) and `40`, and compare the heterotypic fraction after 100 paper MCS.

!!! details "Answer"
    ```@example workshop
    [T => heterotypic_fraction(solve(remake(prob; p = [:T => T]), SequentialCPM()).u[end]) for T in (2.0, 10.0, 40.0)]
    ```

    At low temperature the membranes barely fluctuate and the cells are stuck: sorting is
    slow. At high temperature the fluctuations randomise the contacts and the aggregate
    starts to break up. Graner and Glazier scan the temperature in their 1993 paper.

## Exercise 3: add chemotaxis to one kind

Here is a generic teaching model with two kinds and a fixed gradient of `c`, increasing to
the right. **Make only the `leader` cells chemotactic** and show that they move right
while the followers do not.

```@example workshop
@potts_model Two begin
    @kinds medium leader follower
    @parameters begin
        χ = 0.0
        J[kind, kind] = [0 10 10; 10 8 8; 10 8 8]
    end
    @variables c(site) = 0.0
    @lattice Lattice((80, 40); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        Volume(leader, follower; target = 25.0, strength = 2.0)
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 8.0)
end
nothing # hide
```

!!! details "Answer"
    Extend the model with a chemotactic drive restricted to leaders, and set the gradient in
    the operating point:

    ```@example workshop
    @potts_model TwoChemo begin
        @extend χ, c, leader = base = Two()
        @drive Chemotaxis(c; strength = χ, kinds = (leader,))
    end
    @named twochemo = TwoChemo()
    op = layout(Scattered(12, (5, 5); region = (10:30, 1:40), kinds = [:leader, :follower], seed = 1), twochemo)
    c0 = [x / 80 for x in 1:80, y in 1:40]
    sol = solve(PottsProblem(twochemo, [op; :c => c0; :χ => 400.0], (0, 600); seed = 1), SequentialCPM())
    function mean_x(u, k)
        xs = [x[1] for x in CartesianIndices(u.σ) if u.σ[x] != 0 && u.cell.kind[u.σ[x]] == k]
        return mean(xs)
    end
    (leaders = (mean_x(sol.u[1], 1), mean_x(sol.u[end], 1)),
     followers = (mean_x(sol.u[1], 2), mean_x(sol.u[end], 2)))
    ```

## Exercise 4: scan a parameter with an ensemble

Using your answer to Exercise 3, **measure how far the leaders travel as a function of
`χ`**, with 2 replicates per value, in one `EnsembleProblem`.

!!! details "Answer"
    ```@example workshop
    base_prob = PottsProblem(twochemo, [op; :c => c0], (0, 400); seed = 1)
    χs = [0.0, 200.0, 400.0, 800.0]
    ens = EnsembleProblem(base_prob;
        prob_func = (p, ctx) -> remake(p; p = [:χ => χs[mod1(ctx.sim_id, length(χs))]]),
        output_func = (s, i) -> (mean_x(s.u[end], 1) - mean_x(s.u[1], 1), false))
    res = solve(ens, SequentialCPM(); trajectories = 2length(χs))
    travel = vec(mean(reshape(res.u, length(χs), 2); dims = 2))
    fig = Figure(size = (500, 280))
    ax = Axis(fig[1, 1]; xlabel = "χ", ylabel = "leader travel (sites)")
    scatterlines!(ax, χs, travel)
    fig
    ```

## Exercise 5: contact inhibition in a growing colony

The OpenVT growing monolayer (`OpenVTGrowingMonolayer`, Artistoo parameters) grows without
inhibition by default (`β = 0`); the benchmark's inhibited runs use `β = 0.9`. **Compare
the cell counts of both after 500 MCS.** (Benchmark lattice: 400×400; here: 80×80.)

!!! details "Answer"
    ```@example workshop
    @named openvt = OpenVTGrowingMonolayer(; lattice = (80, 80))
    start = openvt_monolayer_state(; lattice = (80, 80))
    p0 = PottsProblem(openvt, start, (0, 500); seed = 1, capacity = 200)
    count_cells(s) = count(>(0), s[:volume][end])
    (free = count_cells(solve(p0, SequentialCPM())),
     inhibited = count_cells(solve(remake(p0; p = [:β => 0.9]), SequentialCPM())))
    ```

    In a small, young colony the difference is small: inhibition matters once cells are
    crowded. Try a longer run on a larger lattice.

The benchmark's full run:

```@example workshop
Main.paper_run("openvt", "../") # hide
```

## Exercise 6: your own layout

**Write a layer that paints a ring of `n` square cells** around the centre of the lattice,
and use it to start a sorting model.

!!! details "Answer"
    ```@example workshop
    struct Ring <: AbstractLayout
        n::Int
        radius::Float64
        size::Int
        kinds::Vector{Symbol}
    end
    function Potts.paint!(op::Potts.LayoutState, r::Ring, lat)
        c = size(lat) ./ 2
        for i in 1:(r.n)
            θ = 2π * i / r.n
            x0 = round.(Int, c .+ r.radius .* (cos(θ), sin(θ)))
            id = Potts.new_cell!(op, r.kinds[mod1(i, length(r.kinds))])
            Potts.assign!(op, (x0[1]:(x0[1] + r.size - 1), x0[2]:(x0[2] + r.size - 1)), id)
        end
        Potts.record!(op; requested = r.n, painted = r.n)
        return nothing
    end
    ring = layout(Ring(12, 20.0, 5, [:dark, :light]), gg)
    frame = renderframe(PottsProblem(gg, ring, (0, 0)).u0)
    fig = Figure(size = (300, 300))
    ax = Axis(fig[1, 1]; aspect = DataAspect())
    hidedecorations!(ax)
    pottsplot!(ax, frame; boundaries = true)
    fig
    ```

## Going further

- Put a cell-cycle clock in the cells of the OpenVT model with `@components` and make cells
  divide when the clock completes, instead of at a fixed size ([Tutorial 5](@ref
  tutorial-cell-odes)).
- Link the leaders of Exercise 3 to followers on contact, and see whether they drag them
  along ([Tutorial 6](@ref tutorial-links)).
- Run Exercise 1 on the GPU, if you have one ([Tutorial 8](@ref tutorial-gpu)).
