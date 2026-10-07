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
Finalized 2026-10-07 (finalization pass, not yet posted). Changes: the wide table is split in two;
the 181²/256² 1.77.0 rows are `ODEProblem` time only (plan §3.3 q1b) and are now labelled so;
dropped the unsourced "SparseMatrixCSC-typed parameter fails an assertion" (no saved message);
#5242 is cited as the implicit-residual analogue, not as the fix. #NNNN still needs the
mass-matrix issue number.
-->

Scaling data for the case this issue targets: a 2-D grid field written as array equations, up to
10⁶ elements, through today's two routes, the `complete`-only array path (#5148) and `mtkcompile`
(scalarizing).

**Model.** Diffusion on an N × N grid with a frozen boundary ring: one interior array equation
plus four edge equations.

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

Each N ran in its own process (for peak RSS) after a warm-up at N = 4. On the `complete` path
`f = M * u′` was checked against a hand-written stencil at every N.

**`complete` path** (ModelingToolkit 11.45.3 / ModelingToolkitBase 1.77.3 unless marked †):

| N² (elements) | as shipped: `complete` + `ODEProblem`, peak RSS | with a sparse mass matrix (#NNNN): `complete` + `ODEProblem`, peak RSS | warm RHS: ns/elt, alloc/call |
|---|---|---|---|
| 16² (256) | 0.01 + 0.20 s, 1.2 GB | 0.01 + 0.24 s | 17–21, 18 KiB |
| 64² (4 096) | 0.15 + 1.15 s, 1.46 GB | 0.16 + 0.42 s, 1.21 GB | 9, 331 KiB |
| 128² (16 384) | 0.69 + 2.54 s, **5.37 GB** | 0.35 + 1.35 s, 1.31 GB | 13–19, 1.3 MiB |
| 181² (32 761) | `ODEProblem` 7.7 s, **17.6 GB** † | — | — |
| 256² (65 536) | `ODEProblem` 15–17 s, **≈ 62 GB**, OOM-killed in 2 of 4 runs † | 2.85 + 4.63 s, 1.60 GB | 14, 5.4 MiB |
| 512² (262 144) | — | 11.3 + 25.5 s, 2.44 GB | 32, 22 MiB |
| 1024² (1 048 576) | — | 55.5 + 113.3 s, 4.76 GB | 52–342, 88 MiB |

† ModelingToolkit 11.45.1 / ModelingToolkitBase 1.77.0.

**`mtkcompile` path** (11.45.3 / 1.77.3):

| N² (elements) | equations after `mtkcompile` | `mtkcompile` + `ODEProblem`* | peak RSS | warm RHS: ns/elt, alloc |
|---|---|---|---|---|
| 16² (256) | 196 | 0.09 + 2.1 s | 1.25 GB | 8.4, 0 |
| 32² (1 024) | 900 | 0.85 + 15.2 s | 1.54 GB | 4.3, 0 |
| 64² (4 096) | 3 844 | 2.45 + **212.6 s** | 2.46 GB | 2.0, 0 |
| 128² (16 384) | not attempted | | | |

\* Needs `build_initializeprob = true`: with `false`, `ODEProblem` throws `Cannot convert an object
of type Missing to an object of type Float64` (cf. item 7). So this column includes building the
initialization problem, which is nearly all of the 212 s.

What this shows, against the items in the issue:

1. **The `complete` path already gives O(1) code.** The interior block is the same
   `copyto!(view(du, …), vec(Dc .* (…)))` at every N; only the edge rows are scalar. The remaining
   costs are in problem construction:
   - The dense `n × n` mass matrix is O(n²) in memory: that alone is the 62 GB at 256² (#NNNN).
   - With it fixed, `complete` + `ODEProblem` is still superlinear: ×4.9, then ×4.6 time per ×4
     elements from 256² to 1024², reaching 169 s at 10⁶. We have not profiled this part.
2. **Row order.** On the `complete` path rows are packed in *equation* order, so this model gets a
   permutation mass matrix, not `I`, which excludes explicit solvers for a plain explicit ODE.
   `mtkcompile` reorders the unknowns and gets `M = I`; keeping arrays through `mtkcompile` should
   keep that property.
3. **The warm RHS on the array path allocates.** The slice broadcasts materialize about 7
   temporaries per call (331 KiB at 64², 88 MiB at 1024²), while the scalarized `mtkcompile` RHS
   allocates nothing and runs at 2–8 ns/elt. For array codegen to beat scalarizing at run time, the
   broadcasts over views need to fuse into `du`; #5242 does the analogous view binding for `du` in
   implicit residuals.
4. **`mtkcompile` cost is construction-dominated.** The scalarized system has N² − 4N + 4
   equations, and `mtkcompile` + `ODEProblem` grows from 2.2 s (256 elements) to 16 s (1 024) and
   215 s (4 096): ×7, then ×13, per ×4 elements. That is the case for item 1.
5. **Boundaries.** Only a frozen ring is expressible without scalarizing. A periodic or no-flux
   stencil needs one of these, and none works:
   - Wrap-around indices in `@arrayop`: `@arrayop (i, j) c[mod1(i + 1, N), j] - c[i, j]` throws
     `MethodError: no method matching mod1(::BasicSymbolic, ::Int64)` (both versions).
   - Concatenated slices: `vcat(c[N:N, :], c[1:N-1, :])` returns a scalarized `Matrix{Num}`, and
     `ODEProblem` on `D(c) ~ Dc .* (up .+ dn .+ lf .+ rt .- 4 .* c)` built from them fails in
     `_copy_broadcast!` (MTKB 1.77.0).
   - A sparse Laplacian as an array parameter, `D(c) ~ L * c`: it is densified symbolically. At
     64², `complete` takes 274 s and `ODEProblem` 222 s at 10.8 GB; 256² runs out of memory
     (MTKB 1.77.0).

   A symbolic `mod1`/`mod` on array-op indices, or an array-level `circshift`, would cover periodic
   grids.

Versions: ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing 1.20.7,
Symbolics 7.44.1, SymbolicUtils 4.49.0, SciMLBase 3.57.0; rows marked † are ModelingToolkit
11.45.1, ModelingToolkitBase 1.77.0, Symbolics 7.41.1, SymbolicUtils 4.48.0. Julia 1.12.6,
x86_64-linux-gnu, AMD Ryzen AI Max+ 395 (pinned to 24 threads), 64 GB. The machine was shared with
other jobs, so timings are ±30 %; the 1024² warm RHS ranged from 52 to 342 ns/elt between runs.
Allocation and RSS figures are not affected.
