# LW-2 bounded conjunctive-resolution amendment

Date: 2026-08-10

Status: Accepted for implementation; LW-2 remains unpassed until the exact implementation and
evidence below pass. This amendment does not clear LW-R1.

Authority:

- [LocalWorksets V1 normative contract](../../spec/localworksets-v1.md)
- [LocalWorksets V1 implementation gate](../../spec/localworksets-v1-implementation-gate.md)
- [LW-1 implementation matrix](lw1-implementation-matrix.md)
- [LW-1 implementation review](lw1-review.md)

## Decision

LW-1 remains a correct, deliberately narrow one-key resolved lowering. It cannot express the
checkerboard proposal's requirement to win both its old-owner and new-owner claims. LW-2 therefore
admits one additional, bounded resolved profile and no broader migration.

The new profile processes an active prefix of fixed-capacity items. Each eligible item emits at
most two signed `Int32` keys. Nonpositive keys emit nothing. Each positive key is resolved by exact
`UInt32` maximum rank and then canonical minimum `UInt32` identity. An item is selected only when
it wins every key it emitted; an item that emits no key is selected vacuously. The result is
item-aligned: selected and ineligible items preserve their value, while an eligible loser receives
the explicitly declared empty value.

This is a new layout of `resolved`, not an `independent` write and not a `combined` numerical
reduction. Inspection must say `result_layout = :items`, `selection = :all_emitted_destinations`,
and `maximum_emissions = 2`. Keyed winner tables remain private workspace.

## Exact declaration profile

The executable declaration is inspectable data. It contains no caller callback:

```julia
resolved((:claim_a, :claim_b);
    empty = losing_value,
    rank = (
        type = UInt32,
        order = :max,
        lower = UInt32(0),
        upper = typemax(UInt32),
    ),
    tie_break = (
        input_type = Int32,
        type = UInt32,
        order = :min,
        transform = :checked_unsigned,
        proof = :strictly_increasing_active_prefix,
    ),
    capacity = item_capacity,
    key_type = Int32,
    value_type = UInt8,
    skipped_keys = :nonpositive,
    result = (
        layout = :items,
        selection = :all,
        zero_claim = :selected,
        selected = :preserve,
        ineligible = :preserve,
    ),
)
```

The operation declaration names the value binding, a literal equality eligibility rule, and one
Boolean gate binding. CorePotts supplies its accepted and conflict bytes as ordinary declaration
values; LocalWorksets contains no Core status constants or meanings.

Required bindings are exactly two dense item-aligned `Int32` key arrays, one dense `UInt32` rank
array, one dense `Int32` identity array, one dense pointwise `UInt8` read/write value array, one
one-element Boolean gate, and one bounded `Int32` active count. Workspace is exactly two dense
`UInt32` arrays of destination capacity: winning rank and winning identity.

Dynamic key and identity contents are not topology and are never copied at preparation. Topology
owns item capacity, destination capacity, route arity two, the nonpositive-absent law, the active
bound, result layout, and epoch/fingerprint.

## Canonical identity ruling

Core's direct semantic identity for the admitted unit-attempt checkerboard algorithm is the target
linear site. Candidate generation writes those identities before arbitration on the same
KernelAbstractions lane. The LocalWorksets identity kernel consumes the existing `Int32` identity
binding and, for the complete active prefix, proves:

```text
identity[i] > 0
i == 1 || identity[i - 1] < identity[i]
```

It then converts the value exactly to `UInt32`. The proof is fused into the existing identity
launch. Invalid input raises a provider failure before unsafe indexing or arbitration publication.
This preserves the direct `cell_min_identity` bytes while preventing duplicate or caller-chosen
noncanonical tie identities from silently producing multiple winners.

No host scan, extra validation launch, external self-certification field, or unchecked dynamic
identity is admitted. The Core wrapper additionally proves that every canonical checkerboard color
is stored in increasing linear-site order and that its candidate-produced prefix equals the direct
semantic identity formula.

The committee considered centrally deriving local item identity. That is a valid future generic
profile, but it was rejected here because it changes the direct winning-identity scratch. It also
considered topology-owned per-color identity tables; those preserve bytes but add transfer/storage
and complicate one-preparation lease drainage without improving this checked bounded profile.

## Eligibility and live failure gate

Item eligibility is the declared literal equality on the existing `UInt8` value binding. No
per-item Boolean eligibility allocation is permitted.

CorePotts supplies one immutable, non-owning `AbstractVector{Bool}` of length one. Its device
`getindex` evaluates the live conjunction represented by `_program_backend_open`: program status
is successful and lifecycle status is successful. The no-lifecycle variant evaluates the program
status only. The view retains its parent status arrays, delegates backend/device identity to them,
adapts before execution, and must compile to an isbits CPU/Metal kernel argument. LocalWorksets sees
only a Boolean storage read and has no dependency on `ProgramStatus`, lifecycle types, or status
codes.

All four kernels read the gate before mutating scratch or reading item data. KernelAbstractions 0.9
implicit ordering makes the preceding Core acceptance-status write visible without an intermediate
wait. A false gate is an ordinary no-op and does not poison.

## Exact lowering and Core boundary

The lowering is exactly four launches:

1. gated clear of keyed rank/identity scratch;
2. gated atomic maximum rank over at most two positive keys per eligible item;
3. gated identity proof, conversion, and atomic minimum identity;
4. gated conjunctive selection and pointwise loser publication.

Positive keys outside `1:destination_count` fail before indexing in every consuming kernel.
Nonpositive keys emit nothing. Duplicate keys within one item are idempotent. Rank zero remains a
valid candidate because the cleared identity sentinel distinguishes an empty destination.

The same value array is read and written only under the centrally proved pointwise `i -> i` alias
law. Clear/rank/identity do not write it; selection reads and may write only its own item. All other
mutable aliases reject.

Only the existing Core claim block may dispatch to this lowering:

```text
clear claims -> maximum-priority claims -> minimum-identity claims
             -> conjunctive item selection
```

Candidate generation, RNG, Hamiltonian evaluation and canonical source-order folding, acceptance,
accepted-copy stages, commit, trackers, relationships, report, banks, lifecycle, checkpoints,
publication, and scientific settlement remain CorePotts-owned. The frozen direct path remains the
oracle and public default.

The checkerboard launch trace remains exactly `1 + 9C`: one Core bulk clear and, per realized
color, five unchanged Core launches surrounding the four LocalWorksets claim launches. There are
no intermediate waits. The last cumulative LocalWorksets receipt replaces the existing settlement
synchronize; it never supplements it. Its backend-tail synchronization covers later Core commit,
report, lifecycle, and bank-publication launches on the same implicit-order lane.

Profiles with host accepted-copy work are candidate-ineligible and select direct before the first
launch. The private candidate preflights enough leases for the whole MCS. Its reviewed queue
capacity is at least twelve complete MCSs:

```text
lease_capacity = 12 * attempts_per_site * color_count
```

Exhaustion rejects before the MCS state-copy launch and does not poison.

## Admission and hot-path qualification

The new lowering is centrally admitted for only the exact types, address spaces, operations,
workspace, four-launch implementation, and reviewed CPU/Metal environments above. External
methods may describe data but cannot authorize capability, replace lowering/provider callbacks,
or execute opaque host code.

Trusted callback origin discovery must be cached after concrete preparation. The cache records the
selected central methods, their `invoke` signatures, the exact concrete signatures checked against
hostile specializations, and one Julia world counter. An unchanged world uses statically dispatched
`invoke` adapters without `which` or signature-tuple construction. A changed world revalidates all
cached methods before acquiring a lease or launching; a replacement rejects prelaunch and leaves
the preparation unpoisoned. Schema, identity, alias, device, lane, active-bound, workspace, and
lease validation remain live.

## LW-2 acceptance evidence

| ID | Required pass condition |
|---|---|
| LW2-C01 | Source/diff inspection proves that only the four claim stages can dispatch to LocalWorksets; all surrounding Core stages and public behavior remain direct. |
| LW2-C02 | Domain-neutral zero-, one-, two-, duplicate-, and nonpositive-key fixtures prove conjunctive semantics; old-only win, new-only win, both win, and neither win match direct Core fixtures. |
| LW2-C03 | Rank `0` and `typemax(UInt32)`, equal-rank ties, strict identity endpoints, loser-empty publication, zero-claim selection, and inactive/ineligible preservation pass. |
| LW2-C04 | Nonpositive keys skip; positive out-of-range keys and nonpositive, duplicate, decreasing, or overflow identities fail at the provider boundary and poison only after append. Inactive tails are unread. |
| LW2-C05 | Exact type, shape, stride, backend, device, active bound, pointwise alias, gate, workspace, and one-element-short rejection pass before launch where statically knowable. |
| LW2-C06 | Program failure, lifecycle failure, both-open, and no-lifecycle gate variants match `_program_backend_open`; a preceding acceptance failure makes all four launches byte-preserving no-ops. |
| LW2-C07 | The declaration, plan, preparation, and inspection report dynamic two-key routing, item result layout, exact identity proof, pointwise read/write law, four launches, workspace bytes, zero dynamic-topology transfer, and qualified determinism. |
| LW2-C08 | One preparation handles changing colors, active counts, banks, gates, and same-schema values without replanning, Adapt, compiler-cache growth, host fallback, or workspace growth. |
| LW2-C09 | CPU and real Metal record exactly four claim launches, `1 + 9C` total checkerboard launches, zero intermediate waits, and one final synchronization. |
| LW2-C10 | Candidate-ineligible accepted-copy and capability profiles choose direct before any candidate launch. The public direct capability/evidence/fingerprint and checkpoint block remain exact. |
| LW2-C11 | The private experimental candidate requires exact evidence, has a distinct mechanism identity, and is not exposed through a public selector. Direct-to-candidate and candidate-to-direct restore reject. |
| LW2-C12 | At least twelve queued MCSs settle once with exact submitted, drained, committed, materialized, bank, counter, lease, and settlement values. |
| LW2-C13 | Expected Core scientific failure at MCS `k` leaves LocalWorksets unpoisoned and matches the direct `k-1` commit cut. A real provider failure poisons and maps to the existing Core backend-failure path without publishing the inactive bank. |
| LW2-C14 | Every realized color proves candidate identities are positive/strictly increasing and equal direct semantic IDs. Exact direct/candidate `cell_max_priority`, `cell_min_identity`, and dispositions match on adversarial collision fixtures. |
| LW2-C15 | Focused, full CorePotts CPU, authoritative root, and qualified real-Metal suites pass; fresh hashes and environment evidence identify the exact candidate. |

## LW-3 and LW-R1 preservation

LW-3 must still prove full scientific state, Hamiltonian, RNG, checkpoint, failure-cut, launch,
workspace, allocation, compilation, and paired performance parity under the existing matrix. This
amendment does not weaken the one-sided 95% paired-bootstrap upper bound of `1.05`, manufacture
CUDA/ROCm support from portable source, promote the candidate, or permit deletion of the direct
oracle.

LW-R1 remains a fresh exact-hash committee review after the actual vertical and LW-3 evidence.

## Committee record and preserved dissent

The Julia API/package-boundary, JuliaGPU/backend, and semantic/determinism reviewers independently
agreed on the bounded four-launch boundary, live gate, direct disposition eligibility, no extra
scratch/wait, private selector, and retained Core ownership. Their exact unchanged LW-1 ballot was
unanimous PASS with P0=0, P1=0, P2=0 and no general-library obstruction.

The contradiction round disagreed on identity representation. One reviewer preferred derived item
identity for the strongest central proof; the chair preferred prepared exact topology identities;
the semantic reviewer preferred checked dynamic semantic IDs for exact scratch and one reusable
preparation. This amendment adopts the checked dynamic profile because it preserves exact direct
bytes and detects its complete uniqueness/order law within an existing launch. Unchecked dynamic
identity remains a P0 veto. The alternative views are preserved here rather than presented as
consensus.

No reviewer treated this amendment, its design, or the bounded LW-1 pass as LW-R1.
