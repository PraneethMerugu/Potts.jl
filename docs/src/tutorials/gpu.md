# [Tutorial 8: running on a GPU](@id tutorial-gpu)

The same model runs on a GPU without changes. You build the problem in single precision.
You then solve it with the parallel `CheckerboardCPM` algorithm on a GPU backend. You will
learn:

- what `CheckerboardCPM` does and how it differs from `SequentialCPM`;
- how to build a problem for a GPU with `T = Float32`;
- the two lines that move a run to the GPU.

!!! warning "This page runs on the CPU"
    The documentation is built on a machine without a GPU. Every block on this page runs on
    the CPU, except the two blocks marked **GPU only**. These two blocks show the lines to
    add.

GPU runs use any [KernelAbstractions](https://github.com/JuliaGPU/KernelAbstractions.jl)
backend. Potts.jl is tested on Apple GPUs, through [Metal.jl](https://github.com/JuliaGPU/Metal.jl).

## The checkerboard algorithm

`CheckerboardCPM` makes copy attempts in parallel. `SequentialCPM` makes one copy attempt
after another, which cannot be parallelized. `CheckerboardCPM` cuts the lattice into blocks
and makes copy attempts in all blocks at once, at sites far enough apart not to interact. It
samples the same model with kinetics close to `SequentialCPM`'s (see
[Kinetics](@ref manual-algorithms-checkerboard-time)).

- Use one algorithm throughout a study.
- On a GPU the same seed does not give the same run: the outcome depends on the timing of
  the parallel work. On the CPU it does.

`CheckerboardCPM` runs on the CPU too:

```@example gpu
using Potts, PottsModels, MakiePotts, CairoMakie
CairoMakie.activate!(type = "png") # hide

σ0, kinds0 = graner_glazier_state(2)                  # the paper's aggregate, 2×2 tiles
@named gg = GranerGlazier(; lattice = size(σ0))
prob = PottsProblem(gg, [ownership => σ0, kind => kinds0], (0, 1600); seed = 1, T = Float32)
sol = solve(prob, CheckerboardCPM(); saveat = 25)
record_potts("gpu_checkerboard.mp4", sol; framerate = 12, title = "", figure = (; size = (420, 420)))
nothing # hide
```

```@raw html
<video src="../gpu_checkerboard.mp4" controls autoplay loop muted playsinline width="420"></video>
```

This is the shipped Graner & Glazier model with the paper's parameters, on four tiles of
the paper's aggregate.

| | Paper | Here |
|---|---|---|
| Cells | one aggregate of about 1000 cells | 4 × 64 cells |
| Copy attempts | sequential | checkerboard |
| Run length | up to 10⁴ of its MCS (Monte Carlo steps) | 100 of its MCS |

`T = Float32` builds the generated code and the state in single precision. GPUs need it.
Apple GPUs have no double precision at all. Other GPUs are much faster in single precision.
`remake` converts the parameters you give it to the problem's type.

## Moving to the GPU

1. Load the GPU package.
2. Pass its backend to `solve`.

**GPU only** (not run when the documentation is built):

```julia
using Metal
sol = solve(prob, CheckerboardCPM(); backend = MetalBackend(), saveat = 25)
```

Everything else is unchanged. The state lives on the GPU during the run. Potts.jl
transfers every saved state back to the host, so `sol.u`, `sol[:volume]`, `record_potts`
and the rest work as on the CPU. Ensembles take the backend too. They run as many
trajectories at once as Julia has threads, each on its own GPU queue:

**GPU only**:

```julia
# start Julia with, for example, `julia -t 4`
solve(EnsembleProblem(prob), CheckerboardCPM(); backend = MetalBackend(), trajectories = 8)
```

One run alone often leaves the GPU partly idle, so several at once give more MCS per
second in total. On an AMD Ryzen AI Max+ 395, the OpenVT monolayer (1400²) ran at about
720 MCS/s alone and about 1,900 MCS/s in total with 4 or 8 runs at once. A run waiting for
the GPU keeps its CPU thread busy, so use no more threads than free CPUs. Pass
`EnsembleSerial()` to run the trajectories one after another.

On the CPU, use the same calls without `backend`, as above:

```@example gpu
ens = solve(EnsembleProblem(prob; output_func = (s, i) -> (total_energy(prob, s.u[end]), false)),
    CheckerboardCPM(); trajectories = 2)
ens.u
```

## Tips for fast GPU runs

- **Save sparingly.** Each saved state is a transfer from the GPU to the host. Save only
  the times you need (`saveat`). In an ensemble, you can instead reduce on the fly with an
  `output_func`.
- **Big lattices pay off.** A GPU is fast when there are many blocks to run at once. Small
  lattices are often faster on the CPU.
- **Run ensembles for many seeds.** Several runs at once fill the GPU better than one run
  alone (see above).
- **Use the same model.** Everything a model can express runs on the GPU: fields, cell and
  model ODEs with fixed-step solvers, divisions, links and components. An `Adaptive` ODE
  solver integrates on the host and transfers the state once per MCS.
- **Reproducibility.** Potts.jl draws the random numbers from counter-based streams keyed by
  the seed. A run therefore does not depend on thread scheduling.

## What you learned

- `CheckerboardCPM` is the parallel algorithm. It runs on the CPU and on GPUs.
- `PottsProblem(…; T = Float32)` builds a single-precision problem.
- `solve(prob, CheckerboardCPM(); backend = MetalBackend())` runs it on an Apple GPU.

The full run of the sorting model, as long as in the paper:

```@example gpu
Main.paper_run("graner_glazier", "../../") # hide
```

You have finished the tutorials. The [Workshop](@ref workshop) has exercises to practice
with, and the [Manual](@ref manual-models) describes every part of the model language.
