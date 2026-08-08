# G5H-4 native CPU component evidence

Status: qualified H4-B quantitative record

Date: 2026-08-08

Exact implementation candidate: `901faa546d0b21acca5dd56ecfd42f1ffae8dd64`

Exact tree: `e935bf919e59c86baa3f23a394d1eb06d497bc61`

Environment: target Mac, `arm64`, macOS 15.6.1, Julia 1.12.1,
`Sys.CPU_NAME == "apple-m1"`, four Julia threads. The pinned integration
environment supplies the exact MTK/SciML versions recorded in
`g5h-control.md`.

Reproduction command:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=integration --startup-file=no --threads=4 \
  benchmark/src/native_cpu_components.jl
```

The harness uses one fixed scheduled per-cell ODE (`dx/dt = drive`), a
32-slot pool, fixed `dt=0.01`, a frozen 8×8 CPM lattice, and an analytic final
state oracle. `first_seconds` includes first-use compilation. The allocation
and median time columns measure subsequent complete coupled MCS steps after
one warm step; medians use three samples. Numbers are observations from this
run, not portable guarantees.

## Fixed-capacity logical-pool memory

| Capacity | Unknown width | `summarysize` bytes |
|---:|---:|---:|
| 4 | 1 | 224 |
| 4 | 4 | 464 |
| 4 | 16 | 1,424 |
| 32 | 1 | 784 |
| 32 | 4 | 1,696 |
| 32 | 16 | 5,344 |
| 256 | 1 | 5,264 |
| 256 | 4 | 11,552 |
| 256 | 16 | 36,704 |

The representation scales with capacity × logical width as data. No cell or
lane count enters generated model type topology.

## Warm execution

| Live cells | Mode | First step (s) | Median warm step (s) | Warm allocation (B) | Cell-steps/s |
|---:|:---|---:|---:|---:|---:|
| 1 | serial | 3.916081 | 0.000341 | 189,480 | 2,929 |
| 1 | batch 4 | 2.663079 | 0.000314 | 172,208 | 3,185 |
| 1 | batch 8 | 0.000949 | 0.000311 | 182,128 | 3,212 |
| 1 | batch 16 | 0.000906 | 0.000450 | 172,208 | 2,223 |
| 8 | serial | 0.002526 | 0.001838 | 1,171,304 | 4,353 |
| 8 | batch 4 | 0.002459 | 0.001857 | 1,067,976 | 4,307 |
| 8 | batch 8 | 0.002687 | 0.001832 | 1,050,840 | 4,368 |
| 8 | batch 16 | 0.002335 | 0.001684 | 1,050,904 | 4,752 |
| 32 | serial | 0.008129 | 0.007490 | 4,593,720 | 4,272 |
| 32 | batch 4 | 0.007511 | 0.006870 | 4,180,056 | 4,658 |
| 32 | batch 8 | 0.008158 | 0.006383 | 4,111,896 | 5,013 |
| 32 | batch 16 | 0.007637 | 0.006415 | 4,077,624 | 4,988 |

At 32 live cells, batch width 8 improves measured throughput by 17.3% and
reduces warmed allocation by 10.5% relative to the serial reference. Width 16
improves throughput by 16.8% and reduces allocation by 11.2%. At one cell
there is no material reason to select
batching, so `SerialNativeExecution()` remains the default and batching is an
explicit late profile choice.

Only the first serial family and first batched family invocations show the
multi-second compilation cost. Later widths have sub-3 ms first steps in this
run. The retained runtime passes lanes in one vector and stores width as an
integer profile field; batch width and live count therefore remain data rather
than tuple arity or generated component topology.

## Rejected first design

The first implementation ran one ordinary solver per lane under
`Threads.@threads`. The same harness measured only 1,059 cell-steps/s at width
8 and 32 live cells, with 508,190,288 B allocated per warmed step; width 4
allocated more than 1 GB. It was removed rather than admitted. The retained
implementation constructs one fixed-shape flat ODE solve per batch and keeps a
separate MTK parameter buffer per lane, preserving heterogeneous cell inputs.
