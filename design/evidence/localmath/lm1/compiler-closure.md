# LM-1 compiler closure

Date: 2026-08-22

## Disposition

The production stage-local compiler spine passes the frozen LM-1 cold
compiler ceilings. No prototype executor, old/new selector, qualification
cache, physical IR, backend branch, or alternate execution route was retained.

The closing edits are deliberately narrow:

- Stage field, access, publication, component, and Collect workspace assembly
  use concrete tuple recursion instead of generated whole-tuple construction;
- Collect planning derives its physical ports and storages through the same
  tuple-local protocol;
- the final nontrivial hierarchical scan level is executed, fixing Collect
  extents above one workgroup on a real GPU;
- static relation content evidence rejects device storage lacking generation
  and status authority before any host scalar inspection;
- stale benchmark and test assertions now inspect the stage-local authority
  rather than deleted whole-program phase tuples.

An experiment that removed the existing stage binding slice increased the
four-stage cold observation from approximately 7.55 to 9.86 seconds of the
affected boundary and was reverted. It is not part of the retained design.

## Fresh-process synthetic evidence

Three independent Julia processes were retained at each matrix point. Times
below are the full reported host compilation total in seconds.

| stages | run 1 | run 2 | run 3 | physical launches | maximum warm bytes |
|---:|---:|---:|---:|---:|---:|
| 1 | 2.470 | 2.473 | 2.449 | 1 | 1,200 |
| 4 | 14.654 | 14.482 | 14.456 | 21 | 10,928 |
| 8 | 16.560 | 16.745 | 16.971 | 52 | 28,192 |
| 13 | 17.681 | 17.806 | 17.804 | 89 | 49,376 |
| 32 | 22.001 | 21.720 | 21.605 | 230 | 130,928 |

Every report contains seven warm samples and records zero warm Julia
compilation and recompilation. The one-stage maximum is
below the frozen 2.8509-second ceiling. The four-stage maximum is below the
frozen 15.047-second ceiling. Growth from 4 through 32 stages follows distinct
law schema count and modest per-occurrence preparation rather than
whole-program tuple specialization.

Raw reports and the complete manifest are in
`compiler-final-synthetic/`.

## Authentic CorePotts flagship

Three fresh processes completed the current lifecycle-selection boundary:

| run | host compilation | planning through first selection | process |
|---:|---:|---:|---:|
| 1 | 66.926 | 65.592 | 84.983 |
| 2 | 67.430 | 66.060 | 85.982 |
| 3 | 66.843 | 65.464 | 85.733 |

This witness now reports the architecture that actually exists after direct
deletion of the obsolete 13-stage selection prototype: one CorePotts-owned
transaction launch followed by one LocalWorksets Collect publication stage.
The boundary has nine physical launches in total, two independently prepared
banks agree exactly, the three publication callback facts remain current, and
seven-sample warm execution records zero Julia compilation or recompilation
with at most 26,080 host bytes. The approximately 3.3--3.8 millisecond
compilation of the combined evidence-only warmup wrapper is reported
separately and excluded from production warm samples.
The former 13-stage/39-launch identity is historical LM-0 evidence, not a
current semantic authority.

Raw reports and the complete manifest are in
`compiler-final-flagship/`.

## Correctness and device evidence

Focused CPU packets cover Unique, canonical and relaxed Reduce, Resolve,
Collect, relation receipts, and Stage lifecycle failure behavior. The final
observed test-set totals all passed, including 19 Collect execution assertions,
25 packed-relation generation assertions, and the complete lifecycle packet.

The production Metal StageProgram witness passed 38/38 assertions. It covers the four-law
program, a 513-item parameterized Collect (therefore the hierarchical scan),
persistent projection, OrderedFold, Candidate conflict behavior, dynamic
relationship receipts, successful execution, and intentionally failing
transactions. A focused Resolve packet passed 15/15 success, tie, and failure
assertions, and corrected public z-buffer and lattice-spring witnesses passed
2/2 with explicit device relationship authority. CPU and Metal use the same
packed-storage KernelAbstractions path.

## Stop rule

The last retained tuple-construction change moved the full cold result by less
than three percent. Further relation-view inference work would require moving
runtime relation ordinals into type identity or adding another caching or IR
layer. LM-1 stops here: its frozen ceilings pass, warm compilation is zero,
the GPU boundary is proven, and additional compiler machinery would no longer
be a proportionate simplification.
