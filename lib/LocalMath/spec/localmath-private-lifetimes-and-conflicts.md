# LM-9: private lifetimes and exact conflict lowering

Status: implemented on the sole LocalMath execution path.

## Objective

Reduce administrative launches, compiler-private memory traffic, grouped
conflict work, and host submission bookkeeping without exposing a scheduler or
physical tuning language.

```text
LocalLaw and explicit storage observability
        -> automatic lifetime and conflict legality
        -> existing physical launch entries
        -> one KernelAbstractions CPU/GPU executor
```

Ordinary scientific Fields remain observable. Domain compilers may bind a
producer-initialized scratch Field with `LocalMath.Temporary()`. It is
package-owned, cannot be returned by `storage`, and must be totally produced on
every execution before its first read. A temporary wholly contained by a legal
physical segment may be forwarded without a global materialization; otherwise
it remains bounded package scratch.

Core state-bank copies are grouped by compatible extent, device, gate, and
nonaliasing proof and emitted as heterogeneous pointwise ports in groups of at
most four. Core owns no fusion planner.

Grouped `Unique` uses exact destination counts and minimum canonical ordinals
rather than global sorting. Validation retains conflict, coverage, route, and
diagnostic semantics before publication. Resolve may use exact multi-pass
32-bit rank/tie selection only where its complete ordering representation is
proved; other Resolve and every canonical Reduce retain ordered grouping.

Candidate ports may share grouping only when traversal, relation proof, route,
width, ordering, and participation are structurally identical. No author
annotation selects a physical algorithm.

The current carrier vocabulary proves no cross-port participation identity:
`Contribution` and `ResolutionValue` each carry an independent runtime
participation bit. Consequently no cross-port grouping is shared today. This
is an exact legality result, not an omitted heuristic; each port keeps its own
group until a future domain-neutral carrier supplies a real identity proof.

## Implemented physical rules

- `Temporary()` remains a non-array declaration through `bind`. `plan`
  materializes bounded private scratch on the declared backend. When the
  complete lifetime is contained in one pointwise segment, register forwarding
  suppresses the global write and inspection removes the Field from retained
  materializations.
- Compatible state-bank leaves of equal extent are copied through heterogeneous
  pointwise ports in chunks of four.
- conflict-aware `Unique` owns destination counts and minimum canonical winner
  ordinals. Its exact phase sequence is reset, evaluate, validate, and
  finalize/publish; it owns no sort, merge, or directory workspace.
- canonical-tie `Resolve` with `Int32` or `UInt32` rank uses an exact two-pass
  rank/winner selection. Explicit ties retain ordered grouping because their
  duplicate-complete-key error semantics cannot be inferred away.
- Candidate reset also resets dynamic-relation validation status. Validation
  and generation finalization remain later launches, preserving the
  grid-visible relationship barrier while deleting one prologue launch per
  concrete validator.

Candidate, Collect, OrderedFold, relationship, refreshed status, terminal
commit, lifecycle, rollback, authorization, checkpoint, and bank-publication
boundaries remain grid-visible barriers.

Inspection derives temporary ownership, materialization, physical family,
workspace, and launch facts from binding, lowering, and preparation. It does
not become an execution input.

Development uses ordinary package, scientific, compiler-scaling, allocation,
and real-Metal tests on the repository Julia version. Benchmarks guide physical
choices without machine-dependent pass/fail timing gates.

The 32×32 one-color CorePotts CPU witness moved from 126 to 86 body launches per
MCS. On the same local Julia 1.12.6 run its median was approximately 2.36 ms/MCS
with 61,856 host bytes/MCS, compared with the pre-cutover measurements of
approximately 3.17 ms and 72,672 bytes. These numbers are reproducible evidence,
not release thresholds.
