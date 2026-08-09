# G5H-5 quantitative comparison

Status: measured candidate evidence; exact G5H-5 commit pending

Date: 2026-08-08

Authority: G5H-5 in `spec/symbolic-potts-v1-hardening.md`

## Decision

The final architecture does not have a blanket performance win over G5H-0.
On one identical 32 x 32 serial CPU model, total first-use construction time is
12.3% lower and median MCS time is 6.6% lower. Total first-use allocation is
8.6% higher, warmed MCS allocation is 15.0% higher, and logical checkpoint
creation is materially more expensive. The checkpoint increase accompanies
the final exact replay, capability, scheduled-system, lifecycle, and native
extension envelope; it is accepted as an exposed cost, not described as an
optimization.

The baseline predates `BulkComponentStatePool`, so a component-pool ratio
would be fictitious. Final absolute pool evidence instead measures exactly 16
bytes per `Float64` state-scalar-by-capacity-slot across its two banks, plus
12.25 bytes of metadata per capacity slot. The final lifecycle workspace has
the same 25,548-byte reachable heap in the common comparison fixture. Larger
site/cell-capacity measurements and whole-cell planning projections remain in
`g5h1-quantitative-memory-and-scaling-evidence.md`.

These results satisfy the required comparison by reporting both improvements
and costs. They do not establish a universal speedup, an interactive-latency
target, a GPU result, or a whole-cell memory estimate.

## Reproduction

The common harness is `benchmark/src/g5h5_comparison_probe.jl`. It constructs
the same periodic 32 x 32 model with one 8 x 8 cell, a volume term, a dormant
lifecycle transition, and a 12-MCS protocol. Both candidates use the final
source vocabulary retained at G5H-0. Only the executable boundary differs:
G5H-0 uses its then-public `compile(...; engine=SequentialEngine())`; the final
candidate uses structural `mtkcompile` and selects `SequentialCPM` at `init`.

Final candidate:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=. --threads=1 --check-bounds=yes \
  benchmark/src/g5h5_comparison_probe.jl
```

G5H-0 baseline:

```sh
git worktree add --detach /private/tmp/potts-g5h0-comparison \
  9afcf6f1ec44cf84525d8b023c2d1b705560e365
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=/private/tmp/potts-g5h0-comparison -e \
  'using Pkg; Pkg.instantiate()'
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=/private/tmp/potts-g5h0-comparison \
  --threads=1 --check-bounds=yes \
  benchmark/src/g5h5_comparison_probe.jl
```

The last command uses the harness from the final tree at the same absolute
path. G5H-0 had no committed root manifest. Its exact source tree was therefore
run with a compatible 2026-08-08 resolution, including ModelingToolkitBase
1.59.0, SciMLBase 3.41.0, SymbolicIndexingInterface 0.3.51, and Symbolics
7.35.0. Package precompilation completed before either recorded process; the
timers include first-call Julia compilation but exclude package loading.

## Common-fixture results

| Measurement | G5H-0 | Final candidate | Final / G5H-0 |
|:--|--:|--:|--:|
| `complete` time | 6.826948 s | 4.604417 s | 0.674x |
| `complete` allocation | 512,133,496 B | 500,640,280 B | 0.978x |
| structural compile time | 8.723654 s | 0.104649 s | 0.012x |
| structural compile allocation | 788,664,032 B | 28,837,440 B | 0.037x |
| problem construction time | 1.405224 s | 0.032917 s | 0.023x |
| problem construction allocation | 121,758,016 B | 2,043,264 B | 0.017x |
| `init` time | 0.684903 s | 10.721709 s | 15.655x |
| `init` allocation | 11,441,952 B | 1,025,262,112 B | 89.603x |
| four-phase total time | 17.640729 s | 15.463692 s | 0.877x |
| four-phase total allocation | 1,433,997,496 B | 1,556,783,096 B | 1.086x |
| median warmed time/MCS | 0.000116791 s | 0.000109084 s | 0.934x |
| minimum warmed time/MCS | 0.000112583 s | 0.000103459 s | 0.919x |
| median warmed allocation/MCS | 14,176 B | 16,304 B | 1.150x |
| runtime reachable heap | 37,271 B | 35,704 B | 0.958x |
| lifecycle workspace heap | 25,548 B | 25,548 B | 1.000x |
| checkpoint time | 0.000883 s | 0.063789 s | 72.231x |
| checkpoint allocation | 220,224 B | 9,692,416 B | 44.012x |
| checkpoint reachable heap | 4,904 B | 6,242 B | 1.273x |
| serialized checkpoint | 5,169 B | 6,966 B | 1.348x |

Each warmed runtime row follows one untimed warmup MCS and reports seven
single-MCS samples with an explicit garbage collection before each sample.
Checkpoint creation is warmed once and then measured once. The first-use rows
are one fresh process per candidate; their phase split is architecturally
meaningful, while the total is the fair author-visible comparison.

## Final component-pool and lifecycle evidence

The exact final implementation measurements already established by the G5H-1
and G5H-4 harnesses remain the authoritative absolute evidence:

- component pool sizes span 7,712 B for capacity 256/width 1 through
  4,207,328 B for capacity 1,024/width 256;
- the two distinct banks scale at 16 bytes per `Float64` scalar-slot and pool
  metadata at 12.25 bytes per capacity slot;
- a staged component transaction adds 72 B reachable heap and allocates 80 B
  after warmup in the measured fixture;
- a 128 x 128 Core runtime with 4,096 cell/relationship slots measures
  1,550,153 B, of which the incremental lifecycle workspace is 566,772 B;
- fixed-degree relationship validation and full transaction preparation have
  zero warmed allocations in their measured fixtures; and
- the admitted width-8 and width-16 batched CPU component profiles improve
  the 32-cell serial component reference by 17.3% and 16.8% respectively while
  reducing allocations by 10.5% and 11.2%.

The G5H-0 tree has no `BulkComponentStatePool` or equivalent first-class
per-cell native component pool. “Not present” is therefore the baseline
disposition for that category. The final absolute numbers expose capacity
risk without inventing a cross-feature ratio.

## Environment and limitations

| Field | Value |
|:--|:--|
| Target | MacBook Pro `MacBookPro18,3` |
| CPU | Apple M1 Pro, 8 cores |
| Memory | 16 GiB |
| Julia | 1.12.1 |
| Julia threads | 1 |
| Bound checks | yes |
| G5H-0 commit/tree | `9afcf6f1ec44cf84525d8b023c2d1b705560e365` / `a8b0ce43489e558e1770f4982dece97ef4c6eca7` |
| Final commit/tree | pending implementation freeze |

`@timed` allocation is process-local Julia allocation, not RSS. Reachable heap
uses `Base.summarysize`; serialized size uses Julia `Serialization` and is not
a stable wire format. The small runtime fixture is a regression probe, not a
scientific workload. JIT measurements are sensitive to Julia and dependency
versions, thermal state, and cache state. GPU performance remains governed by
the exact real-Metal G5H-4 evidence, not this CPU comparison.
