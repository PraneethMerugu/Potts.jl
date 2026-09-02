# LM-1 host-erased spine prototype

> Historical prototype evidence. The qualified representation was cut directly
> into production on 2026-08-22, and the disposable prototype source was
> deleted. Current authority: `production-stage-local-spine.md`.

Date: 2026-08-22

## Question

Can the complete-program and complete-group tuple spine be replaced by one
host-only erased sequence while retaining concrete per-stage dispatch into the
existing KernelAbstractions execution path?

This is a disposable compiler witness, not a second production path. Its source
is `benchmark/lm0/host_erased_spine_prototype.jl`.

## Shape

The prototype:

- stores lowering entries and prepared launches in host vectors;
- resolves each Stage against a compact stage-local compiler slice in one pass,
  without synthesizing another `LocalWork` or `_BoundWork`;
- reuses globally validated storage facts and relation proofs instead of
  revalidating the slice;
- dynamically dispatches once per stage at a no-inline host function barrier;
- retains concrete stage, status, and relation-guard types inside each launch;
- reuses the existing admission, preparation, qualification, and
  KernelAbstractions stage executors;
- derives a one-launch Candidate specialization only for the proven
  item-local Identity--Unique form: total coverage, plain `_UniqueValue`, no
  controls, no Collection access, no dynamic relation guard, identity reads,
  and one identity destination per source;
- introduces no scheduler, task graph, device-side abstract value, new scientific
  semantics, or backend-specific kernel;
- gives plans and prepared programs non-parametric outer types;
- uses stage-local workspace paths rather than rewriting every leaf through a
  global occurrence index.

The final prototype is 483 lines including comments and definitions.

Two domain-neutral production edits accompany it:

- destination bounds validation moved into the local-sort prologue, deleting
  one distinct grouping kernel and launch;
- OrderedFold effect analysis now replaces nested device-backed fold-read
  wrappers with host-array surrogates during cold typed inspection.

## Cold compiler evidence

Kaimon supplied persistent, Revise-aware decomposition while developing the
prototype. Final qualification used new OS processes with the exact LM-0
compiler options: `--startup-file=no`,
`--project=lib/LocalWorksets`, `--compiled-modules=existing`,
`--compile=yes`, and `--optimize=2`. Total compile time includes
construction, binding, planning, preparation, and first execution.

| stages | final fresh-process compile (s) | frozen host ceiling (s) | result |
|---:|---:|---:|:---|
| 1 | 5.6632 | 2.8510 | fail |
| 4 | 21.7203 | 15.0472 | fail |
| 8 | 24.5895 | 31.309 | pass |
| 32 | 28.4194 | 128.8786 | pass |

Final fresh-process phase compiler times were:

| stages | construction | binding | planning | preparation | first execution |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.9601 | 0.1877 | 2.8960 | 1.4656 | 0.1538 |
| 4 | 1.4849 | 0.2442 | 10.6870 | 9.1886 | 0.1156 |
| 8 | 1.8049 | 0.4285 | 11.3495 | 10.8985 | 0.1080 |
| 32 | 2.6262 | 0.8512 | 13.7087 | 11.1217 | 0.1115 |

The final fresh-process curve is nearly flat after all five law shapes appear:
the additional 24 occurrences from 8 to 32 stages add 2.36 s of planning and
0.22 s of preparation compilation. The earlier Kaimon decomposition fell from
60.21 s to 9.91 s of 32-stage planning, but those persistent-process values are
diagnostic rather than frozen-gate evidence.

Repeated-schema inspection confirms that entries 1/6, 2/7, and 3/8 have
identical concrete entry types. Julia can therefore reuse their method
instances without an explicit compilation cache.

A separate fresh-process witness containing 32 independently constructed
Unique stages produced one concrete entry type for all 32 occurrences:

| construction | binding | planning | preparation | first execution | total |
|---:|---:|---:|---:|---:|---:|
| 1.4975 | 0.4928 | 4.2637 | 1.4539 | 0.1150 | 7.8230 |

Compared with the one-stage witness, 31 additional occurrences add only
approximately 1.37 s of planning compilation and effectively no preparation
compilation in the fresh-process accounting. This directly rejects
position-based stage recompilation as a remaining problem.

## Warm and type evidence

- direct one-stage CPU: about 8.5 microseconds, 736 bytes, zero compilation;
- eight-stage CPU: about 218 microseconds, 27,488 bytes, zero compilation;
- eight-stage Metal: about 3.32 milliseconds, 388,096 host bytes, zero
  compilation.

Typed inspection of the four concrete launch barriers returned `Nothing`,
contained no `Any` slots, and produced small typed bodies of 26--28
statements. Abstract storage is confined to the host vector; dispatch recovers
the concrete launch before the existing KernelAbstractions executor is called.

## Scientific parity

An eight-stage execution checked the first witness of every law family:

- unique output: `Int32.(2:17)`;
- reduction: `168`;
- resolved value: `4`;
- collected records: `Int32.(5:20)`, count `16`;
- ordered fold: `216`.

All observed values matched the independent expectations.

## GPU status

A real Apple Metal device executed the eight-stage witness through
`MetalBackend`. Unique, Reduce, Resolve, Collect, and OrderedFold outputs all
matched the CPU expectations, and the repeated warm run performed zero Julia
compilation.

The qualification exposed and corrected three GPU-boundary defects:

1. device fixed relations in the compiler witness now carry device-resident
   generation/status authority rather than requesting a host fingerprint;
2. nested OrderedFold read wrappers use ordinary host-array types only for
   cold effect-analysis surrogates;
3. the narrow direct-evaluation argument has an `Adapt` definition, so KA
   passes device views rather than host `MtlArray` owners into the kernel.

There is no Metal-specific execution branch and no host conversion in warm
execution.

## Verdict

**The planning, physical simplification, scientific, and real-GPU hypotheses
qualify. The complete prototype still does not qualify for production
cutover.**

The local capsule removed position-based specialization without an explicit
cache or new IR. The proven direct form reduced a fresh-process one-stage
prototype from the current production path's 9.81 s to 5.66 s, and the grouping
fusion deleted a distinct kernel while retaining invalid-route diagnostics and
multi-workgroup canonical order.

The frozen host compiler ceiling still rejects one and four stages. Their
complete fresh-child elapsed times remain inside the separate frozen
fresh-process envelope, but that does not waive the host-compiler failure.
Further work belongs to the fixed cost of validation, evaluator admission, and
the first physical schema—not program-length planning.

No production cutover should occur until:

1. every frozen stage-count ceiling passes;
2. the prototype representation directly replaces and deletes the production
   tuple/group spine;
3. Metal warm host allocation is reviewed against the richer physical launch
   count;
4. source deletion from the production tuple/group spine exceeds the compact
   replacement rather than leaving both representations.

## Fixed-entrance follow-up

The post-review optimization removed two per-occurrence semantic wrappers.
Stage projection now accepts the validated structural binding and the existing
program `ParameterSchema` directly; draft construction accepts the validated
binding directly. The compiler slice still renumbers Stage-local slots, but it
no longer creates a one-stage `LocalWork` or `_BoundWork` merely to call those
operations.

Removing the compiler slice entirely was measured and rejected. Although the
final entry types remained reusable, draft compilation saw the complete global
binding tuple and a 32-stage persistent-session probe took approximately 75
seconds. Restoring the small slice retained the function barrier while keeping
the semantic wrapper deletion.

The review also found that the original direct eligibility was too broad:

- Collection accesses require runtime `_collection_accesses_valid` failure
  semantics that the one-launch kernel does not provide;
- identity publication does not make a non-local read of the published Field
  race-free.

The direct form now requires ordinary Stage accesses with exact identity
relation views. Collection and non-local accesses remain on the buffered
Candidate executor. Because this admitted form cannot produce a Stage-local
runtime validation failure, its unused private validation matrix was deleted;
the shared predecessor/program gate remains authoritative.

After precompiling the current LocalWorksets package, final fresh-process CPU
measurements with the same compiler options were:

| stages | construction | binding | planning | preparation | execution | total | ceiling | result |
|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| 1 | 0.0939 | 0.1960 | 1.9397 | 0.4788 | 0.0982 | 2.8066 | 2.8510 | pass |
| 4 | 0.4605 | 0.3129 | 9.3347 | 8.7648 | 0.0908 | 18.9638 | 15.0472 | fail |
| 8 | 0.7701 | 0.3517 | 10.7801 | 10.3415 | 0.0926 | 22.3359 | 31.309 | pass |
| 32 | 1.8681 | 0.7809 | 13.2242 | 10.1194 | 0.0865 | 26.0791 | 128.8786 | pass |

The one-stage fixed entrance now passes and is approximately 50% smaller than
the preceding 5.6632-second result. The remaining four-stage failure is not
caused by repeated occurrence planning: isolated Reduce, Resolve, and Collect
fresh witnesses spend 3.25--4.07 seconds in exact preparation and 3.97--6.03
seconds in their first general-law planning schemas. The next compiler target
is therefore the ABI and physical-schema cost shared by those law executors,
not another Identity-only shortcut.

A real Apple Metal device executed the final item-local direct form through the
same KernelAbstractions kernel and produced exactly `Int32.(2:17)`.
