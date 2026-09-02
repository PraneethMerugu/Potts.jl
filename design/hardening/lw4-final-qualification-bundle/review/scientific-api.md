# LW-R2 scientific API and usability review

Date: 2026-08-12

Reviewer role: scientific API/usability, fresh exact-candidate review

Ballot: **PASS**

Severity count: **P0 = 0, P1 = 0, P2 = 1**

LW-5 disposition: **may proceed after LW-R2 freeze**. The retained P2 is a
nonblocking diagnostic-quality follow-up, not a scientific-correctness or API
freeze objection.

## Exact identities

- Product commit: `ee395bd2f70d210fe98a0fb748e6530824c50671`
- Product tree: `b5ad1e71d73251fa6f932c8d275be8d1910f65fd`
- Freeze artifact: `design/hardening/lw4-final-qualification-bundle`
- Evidence digest: `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`
- Qualification profile: normal, 1,000 paired microbenchmark samples, Julia
  1.12.6, KernelAbstractions 0.9.42, CPU plus reviewed Apple M1 Pro Metal

I independently confirmed that `HEAD`, `HEAD^{tree}`, `identity.toml`, and the
requested identities agree. I ran the authoritative bundle validator; it
reconstructed the digest above, all environment/workload identities, raw
scientific reports, fixed comparison policy, summaries, and all six zero-exit
commands. Review files are outside that evidence digest by design.

## Independent checks

1. `julia --project=. benchmark/lw4_qualification.jl
   --validate=design/hardening/lw4-final-qualification-bundle` passed and
   returned the exact evidence digest and product identity above.
2. A fresh `julia --startup-file=no --project=lib/LocalWorksets -e 'using Pkg;
   Pkg.test()'` passed all 763 standalone assertions, including API inventory,
   Aqua/package quality, Level-1 desugaring, external operation authoring,
   construction, topology, storage, automatic workspace, inspection,
   heterogeneous mechanisms, numerical modes, and hostile admission cases.
3. I independently deserialized and compared all five CPU and five real-Metal
   cross-domain reports. Every result matched its reference; every invalid
   companion input rejected; all reports had positive launch/wait facts and
   nonnegative workspace/transfer facts.
4. I read the public implementation, README, focused authoring/admission tests,
   cross-domain witnesses, and exact Freeze logs rather than inheriting an
   earlier review ballot.
5. I reproduced the retained P2 with a minimal generic resolved declaration:
   duplicate semantic identities correctly reject at `plan`, but the resulting
   `LocalWorkValidationError` has `stage`, `contract`, `port`, `expected`, and
   `actual` all equal to `nothing`.

## Findings

### P0

None.

### P1

None.

The earlier P1 concerning bottom/nonconcrete external operation results is
closed on this exact product. `_validate_operation_result_form` handles
`Union{}` before accessing `NamedTuple` parameters and reports
`stage=:prepare`, `contract=:operation_result_form`,
`expected=:concrete_named_tuple`, `actual=Union{}`, plus an `item::Int32`
method hint. Other nonconcrete inferred results reject under the same contract.
The 46-assertion hostile-result testset covers:

- nonconcrete direct-independent results;
- a missing `item::Int32` method producing `Union{}`;
- nonconcrete buffered-combined results;
- nonconcrete heterogeneous results; and
- `Union{}` on the buffered path.

All reject during preparation, before submission, and preserve sentinel output
arrays. The Level-1 wrapper reaches the same result validation rather than a
second unchecked path. The fresh standalone run passed this testset.

The scientific comparison policy is also honest and mechanically fixed. D2Q9,
matrix-free FEM, and z-buffer use exact result/reference equality. Lattice
spring edge state and fracture are exact. Deterministic force is exact with
zero tolerance. Fast force alone is reported as relative-tolerance comparison
with the fixed `8eps(Float32)` value (`9.536743e-7`) and reconstructed maximum
absolute error. The validator rejects any different schema or policy. Both CPU
and Metal happened to produce zero force error, but the report retains the
weaker fast-mode policy; inspection likewise marks replay, scheduling, and
same-backend bitwise guarantees as not claimed for fast ports. Cross-backend
bitwise equality is not claimed.

### P2 — some ordinary topology faults are not yet structurally classified

The structured exception is useful on the main authoring paths: route
presence/shape/domain, result form/ports/arity/types, capability, binding,
workspace, submission, freshness, poison, and ownership errors expose stable
fields. However, at least one ordinary scientific topology error remains
message-only. Duplicate resolved semantic identities reject with
`LocalWorkValidationError("resolved semantic identities must be unique per
destination")` but leave every structured field unset. Competing independent
writers have the same limitation. The cross-domain invalid-topology witnesses
currently assert only that some exception occurred.

This is nonblocking because admission is fail-closed, the message is accurate,
no output is touched, and valid execution/report semantics are unaffected. It
should be carried into LW-5 as diagnostic debt: add `stage=:plan`, a stable
contract (for example semantic-identity uniqueness or independent-writer
uniqueness), the port, and useful expected/actual facts, then assert those
fields in a downstream authoring witness. I do not require a production change
before this freeze.

## Scientific API and usability assessment

### Level 1 and Level 2 authoring

Level 1 is credible concise Julia syntax: one `Pair{Symbol,...}` names a single
output while a concrete isbits wrapper converts the bare `emit`/`candidate`
result to the same named-port representation used by Level 2. The wrapper and
external callback are frozen at preparation, and the CPU test proves the
stored call is inferred. Independent, combined, and resolved Level-1 examples
all execute through the common lifecycle; the exact Metal artifact includes
the same Level-1 device compilation/execution path.

Level 2 makes scientifically relevant choices visible rather than implicit:
named reads and ports, fixed emission maxima, coverage, deterministic versus
fast combination, identity/empty values, bounded total rank, canonical
tie-break, conditional no-emission, and ordered stages. The lattice-spring
witness demonstrates independent edge state, combined nodal force, and
resolved fracture in one callback. External packages contribute an ordinary
concrete callable without LocalWorksets source edits while central admission
retains authority over executable profiles.

### Topology, storage, and workspace construction

`topology(work; ...)` derives only item count. Epoch, route matrices,
destination counts, and resolved semantic identities remain explicit. That is
the right scientific boundary: empty destinations, topology freshness, and
semantic tie identities cannot disappear through inference.

Static storage is an ordinary named tuple. `value_slot` and `storage_slot`
make submission-time scalar and array contracts explicit; array slots freeze
concrete array/element type, dimensions, size, strides, access, backend, and
device context. Automatic `prepare`-time workspace is available across direct,
buffered, sequence, and retained specialized mechanisms. Inspection reports
ownership, allocation class, bounded bytes, concrete workspace identities, and
topology-transfer bytes. Expert caller workspace remains possible and is
honestly documented as version-qualified internal record layout rather than a
second stable scientific DSL.

### Diagnostics, inspection, and `show`

Apart from the P2 above, preparation/run diagnostics expose the facts a caller
needs to repair a declaration or safely abandon poisoned work. `show` stays
short and oriented to lifecycle state. Qualified `LocalWorksets.inspect`
avoids a namespace collision and returns non-synchronizing, machine-readable
facts. The derived `summary`, `outputs`, `execution`, `memory`, and
`qualification` groups point to the same authoritative evidence fields rather
than duplicating scientific state. Per-port routes, counts, maxima, coverage,
law/identity/empty behavior, publication phase, failure visibility, and
determinism are inspectable; prepared/event reports add bindings, provider,
workspace, counters, poison, and cumulative receipt facts.

### Cross-domain reports

The evidence is meaningfully cross-domain rather than a single arbitration
demo:

| Witness | Semantics exercised | CPU / Metal result |
|---|---|---|
| D2Q9 stream/collide | nine-lane independent permutation; submission-bound source | exact / exact; one launch; zero algorithmic workspace |
| lattice spring deterministic | heterogeneous independent + canonical Float32 fold + resolved fracture | exact / exact; fixed exact force policy |
| lattice spring fast | heterogeneous independent + qualified fast Float32 addition + resolved fracture | within fixed tolerance / within fixed tolerance; actual error zero in both |
| matrix-free FEM | four contributions, canonical fold, explicit identity at empty node | exact / exact; empty node published zero |
| z-buffer | bounded rank, canonical identity tie, conditional candidate, explicit empty pixel | exact / exact |

These reports prove that the authoring and construction surface can express
several unrelated scientific shapes on both currently qualified providers.
They do not claim CUDA/ROCm qualification, cross-backend bitwise equality, or
that LW-5's eventual full operations already exist.

## Ballot and LW-5 recommendation

**PASS.** There is no scientific API, result-validation, comparison-policy,
construction, inspection, or report contradiction that should block the exact
LW-4 freeze. The previous `Union{}`/nonconcrete-result P1 is demonstrably
closed. The one retained P2 is bounded diagnostic debt and is preserved here
as dissent rather than silently erased.

After the complete LW-R2 decision and seal, LW-5 may proceed. Its job should be
the promised real-value test: author realistic operations through Level 1/2,
keep domain physics/RNG/transactions outside LocalWorksets, and use the public
inspection and fixed scientific comparison policies without internal
descriptor knowledge or manual scratch. No new LocalWorksets mechanism is
justified by this ballot.
