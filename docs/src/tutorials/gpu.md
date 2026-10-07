# [Tutorial 8: running on a GPU](@id tutorial-gpu)

The same model runs on a GPU without changes: the problem is built in single precision and
solved with the parallel `CheckerboardCPM` algorithm on a GPU backend. You will learn:

- what `CheckerboardCPM` does and how it differs from `SequentialCPM`;
- how to build a problem for a GPU with `T = Float32`;
- the two lines that move a run to the GPU.

!!! warning "This page runs on the CPU"
    The documentation is built on a machine without a GPU. Every block on this page runs,
    on the CPU, except the two blocks marked **GPU only**, which show the lines to add.

GPU runs use any [KernelAbstractions](https://github.com/JuliaGPU/KernelAbstractions.jl)
backend; Apple GPUs through [Metal.jl](https://github.com/JuliaGPU/Metal.jl) are tested.

## The checkerboard algorithm

`SequentialCPM` makes one copy attempt after another, which cannot be parallelised.
`CheckerboardCPM` colours the lattice so that sites of one colour are far enough apart not
to interact, and tries all sites of a colour at once. It samples the same model with
slightly different dynamics, so use one algorithm throughout a study, and prefer
`SequentialCPM` when you compare with a paper that used sequential updates. It runs on the
CPU too:

```@example gpu
using Potts, PottsModels, MakiePotts, CairoMakie
CairoMakie.activate!(type = "png") # hide

σ0, kinds0 = graner_glazier_state(2)                  # the paper's aggregate, 2×2 copies
@named gg = GranerGlazier(; lattice = size(σ0))
prob = PottsProblem(gg, [ownership => σ0, kind => kinds0], (0, 1600); seed = 1, T = Float32)
sol = solve(prob, CheckerboardCPM(); saveat = 25)
record_potts("gpu_checkerboard.mp4", sol; framerate = 12, title = "", figure = (; size = (420, 420)))
nothing # hide
```

```@raw html
<video src="../gpu_checkerboard.mp4" controls autoplay loop muted playsinline width="420"></video>
```

This is the shipped Graner & Glazier model with the paper's parameters on four copies of
the paper's aggregate (paper: one aggregate of about 1000 cells, sequential updates, up to
10⁴ of its MCS; here: 4 × 64 cells, checkerboard updates, 100 of its MCS).

`T = Float32` builds the generated code and the state in single precision. GPUs need it:
Apple GPUs have no double precision at all, and other GPUs are much faster in single
precision. Parameters given later with `remake` are converted to the problem's type.

## Moving to the GPU

Load the GPU package and pass its backend to `solve`:

**GPU only** (not run when the documentation is built):

```julia
using Metal
sol = solve(prob, CheckerboardCPM(); backend = MetalBackend(), saveat = 25)
```

Everything else is unchanged. The state lives on the GPU during the run; every saved
state is copied back to the host, so `sol.u`, `sol[:volume]`, `record_potts` and the rest
work as on the CPU. Ensembles take the backend too and run their trajectories one after
another on the device:

**GPU only**:

```julia
solve(EnsembleProblem(prob), CheckerboardCPM(); backend = MetalBackend(), trajectories = 8)
```

On the CPU, the same calls without `backend` work, as above:

```@example gpu
ens = solve(EnsembleProblem(prob; output_func = (s, i) -> (total_energy(prob, s.u[end]), false)),
    CheckerboardCPM(); trajectories = 2)
ens.u
```

## Tips for fast GPU runs

- **Save sparingly.** Each saved state is a copy from the device to the host. Save only the
  times you need (`saveat`), or reduce on the fly with an `output_func` in an ensemble.
- **Big lattices pay off.** A GPU is fast when there are many sites per colour; small
  lattices are often faster on the CPU.
- **Use the same model.** Everything a model can express runs on the GPU: fields, cell and
  model ODEs with fixed-step solvers, divisions, links, components. An `Adaptive` ODE solver
  integrates on the host and copies the state once per MCS.
- **Reproducibility.** The random numbers are drawn from counter-based streams keyed by the
  seed, so a run does not depend on thread scheduling.

## What you learned

- `CheckerboardCPM` is the parallel algorithm; it runs on the CPU and on GPUs.
- `PottsProblem(…; T = Float32)` builds a single-precision problem.
- `solve(prob, CheckerboardCPM(); backend = MetalBackend())` runs it on an Apple GPU.

The full run of the sorting model, as long as in the paper:

```@example gpu
Main.paper_run("graner_glazier", "../../") # hide
```

You have finished the tutorials. The [Workshop](@ref workshop) has exercises to practise
with, and the [Manual](@ref manual-models) describes every part of the model language.
