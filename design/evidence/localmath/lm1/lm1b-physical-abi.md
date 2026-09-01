# LM-1B narrow physical ABI and launch deletion

Date: 2026-08-22

## Result

LM-1B was cut directly into the sole production Stage executor. Candidate and
Collect no longer pass `_CandidateStageRun` or `_CollectStageRun` into every
KernelAbstractions kernel. Evaluation alone retains the qualified evaluator
and access schema. Reset, validation, finalization, atomic work, and
publication receive phase-local physical arguments.

Canonical Reduce and Resolve now settle inside the destination-owned
publication operation after the unchanged validation/finalization barriers.
Their private `reduced` and `winners` arrays and the canonical settlement
launch were deleted. Relaxed atomic initialization and accumulation remain
separate.

Collect publication is candidate-owned. Existing scatter and sort kernels
populate one private candidate-to-position array; the gated publication kernel
writes either the final position or zero for each candidate. This deletes the
projection-clear launch without a cross-workgroup clear/write race and without
mutating published storage on failed work.

## Physical count

The four-stage CPU witness changed from:

```text
1 direct Unique + 8 Reduce + 8 Resolve + 7 Collect = 24 launches
```

to:

```text
1 direct Unique + 7 Reduce + 7 Resolve + 6 Collect = 21 launches
```

The corresponding Metal witness reports 23 launches because its two fixed
relations carry explicit dynamic content-receipt launches. These receipts were
not fused or weakened.

## Compiler evidence

The preceding final-source observation was approximately 20.35 seconds total,
including 9.51 seconds planning and 9.27 seconds preparation. Two fresh
final-source LM-1B observations reported:

| observation | planning | preparation | total compilation |
|---:|---:|---:|---:|
| 1 | 9.4470 s | 8.3065 s | 18.8806 s |
| 2 | 9.6146 s | 8.2234 s | 18.9480 s |

Warm execution remained approximately 45--48 microseconds with 11,024 host
bytes and zero Julia compilation. LM-1B materially reduces preparation and
does not transfer the cost into planning, but it does not yet pass the frozen
15.047-second four-stage ceiling.

Kaimon inspection confirmed:

- the four-stage physical count is 21;
- concrete preparation types shrink from 1,284/1,353/1,538 characters to
  1,250/1,319/1,517 for Reduce/Resolve/Collect;
- Candidate and Collect reset/finalization method signatures contain no
  evaluator or access type;
- repeated Reduce and Resolve schemas recover identical preparation types;
- concrete `_enqueue_stage!` returns `Nothing` with no `Any` slots.

## Scientific and GPU evidence

Focused CPU suites passed canonical and relaxed Reduce, Resolve tie/rank/error
semantics, Collect success/overflow atomicity, runtime routing, and relation
receipts. In particular, a failed Collect publication preserves its prior
source-position projection.

Real Apple Metal evidence passed:

- Candidate plus dynamic relationship receipt: 5/5;
- candidate-owned persistent Collect projection: 3/3;
- runtime-routed Reduce success and invalid-route failure: 4/4;
- the four-stage numerical witness: Reduce `592`, Resolve `4`, and Collect
  records `5:36`.

All physical work remains on the KernelAbstractions path. No backend branch,
qualification cache, scheduler, compatibility executor, or physical IR was
added.

## Subsequent closure

At this intermediate boundary the frozen ceiling was still missed by about
3.9 seconds. The subsequent tuple-local preparation edit removed that gap:
the retained three-run four-stage maximum is 14.654 seconds against the frozen
15.047-second ceiling. See `compiler-closure.md` for the final matrix and stop
rule.
