<!--
P6.0br draft 4 of 4 (D-159). NOT POSTED. The maintainer reviews and posts it.
Target: a COMMENT on SciML/ModelingToolkit.jl#5139 ("Compile and generate code for whole-array
equation models without scalarizing per element (tracking)"). On 2026-10-07 it is OPEN (last
updated 2026-09-13), with one comment. Related: #5102 (array-aware tearing, draft, idle since
2026-09-09) and #5100 (closed).
It cites the mass-matrix issue (draft mtk-massmatrix-dense.md). File that one first and put its
number in place of #NNNN.
The text was machine-drafted. Add whatever AI-disclosure line you normally use. Verified on the PC
under `systemd-run --user --scope -p MemoryMax=16G`; ~/p6-0br-mwe/mwe4_field.jl and
mwe4b_periodic.jl. The PC had other jobs running (load average about 16 on 32 threads), so treat
the timings as ±30 %. RSS and allocation figures are exact.
Everything below the line is the comment body.
-->

Scaling data for the case this issue targets: a 2-D grid field written as array equations. It
compares today's two routes, the `complete`-only array path (#5148) and `mtkcompile`
(scalarizing), up to 10⁶ elements.

**Model.** Diffusion on an N × N grid with a frozen boundary ring, written as one interior array
equation plus four edge equations:

```julia
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

function field(N)
    @variables c(t)[1:N, 1:N]
    @parameters Dc = 0.1
    I = 2:(N - 1)
    eqs = [
        D(c[I, I]) ~ Dc .* (c[1:(N - 2), I] .+ c[3:N, I] .+ c[I, 1:(N - 2)] .+ c[I, 3:N] .- 4 .* c[I, I]),
        D(c[1, :]) ~ zeros(N), D(c[N, :]) ~ zeros(N),
        D(c[I, 1]) ~ zeros(N - 2), D(c[I, N]) ~ zeros(N - 2),
    ]
    System(eqs, t, [c], [Dc]; name = :f), c
end

N = 128
s, c = field(N)
@time sys = complete(s)                     # or mtkcompile(s)
@time prob = ODEProblem(sys, [c => rand(N, N)], (0.0, 1.0); build_initializeprob = false)
du = similar(prob.u0); prob.f(du, prob.u0, prob.p, 0.0)
@time prob.f(du, prob.u0, prob.p, 0.0)
```

The full timing script is the same, plus a warm-up at N = 4 and a loop over N, with each N in
its own process for peak RSS. On the `complete` path the result was checked against a
hand-written stencil (`f = M * u′`) at every N.

**Results** (ModelingToolkit 11.45.3 / ModelingToolkitBase 1.77.3 unless marked):

| N² (elements) | `complete`, as shipped: `complete` + `ODEProblem`, peak RSS | `complete` with sparse mass matrix (#NNNN): `complete` + `ODEProblem`, peak RSS | warm RHS on `complete`: ns/elt, alloc/call | `mtkcompile` + `ODEProblem`*, peak RSS | warm RHS on `mtkcompile`: ns/elt, alloc |
|---|---|---|---|---|---|
| 16² (256) | 0.01 + 0.20 s, 1.2 GB | 0.01 + 0.24 s | 17–21, 18 KiB | 0.09 + 2.1 s, 1.25 GB (196 eqs) | 8.4, 0 |
| 32² (1 024) | — | — | — | 0.85 + 15.2 s, 1.54 GB (900 eqs) | 4.3, 0 |
| 64² (4 096) | 0.15 + 1.15 s, 1.46 GB | 0.16 + 0.42 s, 1.21 GB | 9, 331 KiB | 2.45 + **212.6 s**, 2.46 GB (3 844 eqs) | 2.0, 0 |
| 128² (16 384) | 0.69 + 2.54 s, **5.37 GB** | 0.35 + 1.35 s, 1.31 GB | 13–19, 1.3 MiB | not attempted | |
| 181² (32 761) | 7.7 s, **17.6 GB** (1.77.0) | — | — | | |
| 256² (65 536) | 15–17 s, **≈ 62 GB**, OOM-killed in 2 of 4 runs (1.77.0) | 2.85 + 4.63 s, 1.60 GB | 14, 5.4 MiB | | |
| 512² (262 144) | — | 11.3 + 25.5 s, 2.44 GB | 32, 22 MiB | | |
| 1024² (1 048 576) | — | 55.5 + 113.3 s, 4.76 GB | 52–342, 88 MiB | | |

\* `mtkcompile` needs `build_initializeprob = true` here. With `false`, `ODEProblem` throws
`Cannot convert an object of type Missing to an object of type Float64`. So its column includes
building the initialization problem, and that is where nearly all of the 212 s goes.

What this shows, for the items in the issue:

1. **The `complete` path already gives O(1) code.** The interior block is the same
   `copyto!(view(du, …), vec(Dc .* (…)))` at every N, and only the edge rows are scalar. The
   remaining costs are in problem construction:
   - The dense `n × n` mass matrix in `calculate_massmatrix`, and `u0 .* u0'` in
     `concrete_massmatrix`, are O(n²) in memory (#NNNN). This alone is the 62 GB at 256².
   - With that removed, `complete` + `ODEProblem` is still superlinear: ×4.9 and then ×4.6
     time per ×4 elements from 256² to 1024², reaching 169 s at 10⁶. We have not profiled this part.
2. **Row order.** On the `complete` path rows are packed in *equation* order, so this model
   gets a permutation mass matrix (`M::Matrix`, or `SparseMatrixCSC` with the patch), not `I`.
   That excludes explicit solvers for a plain explicit ODE. `mtkcompile` reorders the unknowns
   and gets `M = I`. Keeping arrays through `mtkcompile` should keep that property.
3. **The warm RHS on the array path allocates.** The slice broadcasts materialize about 7
   temporaries per call: 331 KiB at 64², 88 MiB at 1024². The scalarized `mtkcompile` RHS
   allocates nothing and is 2–8 ns/elt. For array codegen to beat scalarizing at run time, the
   broadcasts over views need to fuse into `du` (cf. #5242).
4. **`mtkcompile` cost is construction-dominated.** The scalarized system has N² − 4N + 4
   equations, and `ODEProblem` with initialization grows from 2.2 s (256 elements) to 16 s
   (1 024) and 215 s (4 096): ×7, then ×13, per ×4 elements. That is the case for item 1 of the issue.
5. **Boundaries.** Only a frozen ring is expressible without scalarizing. A periodic or no-flux
   stencil needs one of these, and neither works:
   - wrap-around indices inside `@arrayop`. On both versions,
     `@arrayop (i, j) c[mod1(i + 1, N), j] - c[i, j]` is
     `MethodError: no method matching mod1(::BasicSymbolic, ::Int64)`.
   - concatenating slices. `vcat(c[N:N, :], c[1:N-1, :])` returns a `Matrix{Num}` (scalarized),
     and `ODEProblem` on `D(c) ~ Dc .* (up .+ dn .+ lf .+ rt .- 4 .* c)` built from those then
     fails in `_copy_broadcast!` (MTKB 1.77.0).

   A symbolic `mod1`/`mod` on array-op indices, or an array-level `circshift`, would cover
   periodic grids. A sparse Laplacian as an array parameter, `D(c) ~ L * c`, is the other
   route. It is densified symbolically: at 64², `complete` takes 274 s and `ODEProblem` 222 s
   at 10.8 GB, and 256² runs out of memory (MTKB 1.77.0). A `SparseMatrixCSC`-typed array
   parameter fails an assertion.

Versions:
- ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing 1.20.7,
  Symbolics 7.44.1, SymbolicUtils 4.49.0 and SciMLBase 3.57.0. Rows marked 1.77.0 are
  ModelingToolkit 11.45.1, ModelingToolkitBase 1.77.0, Symbolics 7.41.1 and SymbolicUtils
  4.48.0.
- Julia 1.12.6, x86_64-linux-gnu, AMD Ryzen AI Max+ 395 (pinned to 24 threads), 64 GB.
- The machine was shared with other jobs during the runs, so the timings are ±30 %; the
  1024² warm RHS figure in particular ranged from 52 to 342 ns/elt between runs.
