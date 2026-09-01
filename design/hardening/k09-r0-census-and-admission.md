# K09 corrected direct baseline, schema census, and admission decision

Date: 2026-08-15  
Status: **K09-0/K09-1 complete; K09-2 and K09-3 rejected**  
Authority: [K09 adoption plan](k09-adoption-plan.md)

## Decision

Retain K09 as a direct CorePotts operation. Do not build a LocalWorksets K09
candidate.

The direct cleanup removed the two selected-gated state self-copies and
replaced the type-by-type state copier with one copy-unit projection. The
review then exposed a pre-existing CPU relationship bug: assigning a
`ProgramRelationshipState` copied its nested array references and destroyed
transaction-bank isolation. The corrected direct path now uses one
CPU-qualified, field-wise KernelAbstractions copy unit for each unpacked
relationship representation bank. Adapted backends continue to use packed
scalar-array units.

That correction is also the decisive admission result. A supported CPU schema
requires a specialized direct copy unit which the accepted LocalWorksets
independent-output profile cannot represent. Retaining that direct fallback
eliminates the required deletion unit and triggers the K09 stop rule.

## Exact vocabulary

- `P`: number of mutable physical array leaves. These establish ownership,
  nested alias, and construction-time schema facts.
- `U`: number of direct copy units and therefore the pre-MCS K09 launch count.
  An unpacked CPU relationship vector is one unit containing several physical
  leaves.
- `g`: number of fully admissible LocalWorksets groups after storage, shape,
  type, backend, and mechanism validation. A length histogram is not `g`.
- `delta`: the separate due-gated scan-tail copy. It remains direct and is not
  included in `U`.

The old `L == launches` notation is retired. It is false for the corrected CPU
relationship representation.

## Corrected direct contract

The frozen implementation establishes all of the following before execution:

1. every lifecycle staging field is identical to its containing bank's science
   field;
2. the primary and alternate banks have the same complete copy-unit schema;
3. unit storage type, axes, backend, and every nested CPU relationship field
   match before the first launch;
4. every physical leaf in one bank is identity- and alias-disjoint from every
   physical leaf in the other bank, including empty arrays; and
5. unpacked relationship units are CPU-only, while device paths receive packed
   scalar arrays.

Submission uses concrete tuple recursion on the host. The device executes only
the ordinary array-copy kernel or the CPU relationship field-copy kernel.
Both use the same lifecycle gate helper. No wait, synchronization, native
queue, event layer, or vendor branch was added. KernelAbstractions implicit
ordering remains the visibility mechanism.

The test oracle covers nested equality, post-copy mutation isolation,
cross-position aliases, identical empty aliases, mismatched axes and value
types before launch, a closed lifecycle gate, post-MCS checkerboard bank
isolation, and relationship-bearing checkpoint continuation.

## CPU schema census

All rows were constructed through the production compiler and checkerboard
initializer. `eligible U` means the unit itself is already a one-dimensional
CPU `Array` with an isbits element type; it does not imply that a complete
LocalWorksets work declaration has been admitted.

| Profile | P | U | Unit lengths | Eligible U | Decisive facts |
|---|---:|---:|---|---:|---|
| minimal | 4 | 4 | `16, 2, 2, 2` | 3 | ownership is a 2-D unit |
| lifecycle-rich trackers/moments | 7 | 7 | `36, 2, 2, 2, 4, 8, 2` | 4 | ownership and moment matrices need a separately qualified linear binding |
| descriptor-heavy | 6 | 6 | `36, 36, 36, 36, 36, 72` | 5 | ownership remains 2-D; the other units happen to be linear arrays |
| relationship-heavy | 15 | 6 | `25, 25, 25, 25, 1, 8` | 4 | one `Vector{ProgramRelationshipState}` contains ten nested leaves and is non-isbits |
| active lifecycle + relationship policy | 12 | 6 | `16, 10, 10, 10, 1, 5` | 4 | one unpacked relationship unit contains seven nested leaves |

The lifecycle-rich diagnostic length histogram is four values
`(2, 4, 8, 36)`. It is deliberately reported as a preliminary histogram, not
as an admissible group count.

The packed adapted relationship census remains useful evidence, but it does
not rescue cross-backend adoption: the previously measured packed profile has
`P == U == 12` and three length groups, whereas the supported CPU profile must
retain the field-wise direct relationship unit.

## Why current LocalWorksets cannot replace K09

The accepted independent-output mechanism requires a concrete isbits value
type. The reviewed CPU root-storage policy admits ordinary `Array` storage,
not `BitVector`. Therefore neither of the possible CPU encodings closes:

- bind the unpacked relationship unit: its element type is the non-isbits
  `ProgramRelationshipState`; or
- flatten it into physical ports: the `active` leaf is a `BitVector`, and the
  resulting dynamic per-record schema needs representation-specific binding
  machinery.

The 2-D science units also need an explicit, reviewed linear-storage binding;
matching `length` alone is insufficient. Adding a storage representation,
generated schema framework, special LocalWorksets API, or CPU direct fallback
is forbidden by K09-1. A Metal-only candidate would fail the required common
CPU/Metal boundary.

## Direct source and launch ledger

The three opening production files contained 2,884 raw lines. The initial
alias/self-copy cleanup and direct projection reduced them to 2,819 (`-65`).
The committee-discovered relationship-isolation correction brings the exact
correct implementation to 2,958 (`+74` relative to the opening, `+139`
relative to the initially simplified but scientifically invalid oracle).

This growth is accepted because it closes a real transaction-isolation defect,
not because complexity is intrinsically valuable. It cannot be credited to a
LocalWorksets candidate. The two redundant self-copy passes remain deleted:
the genuine pre-MCS path now submits exactly `U` copy launches rather than the
old three passes (`3U`), plus the separately due-gated `delta` scan-tail copy.

For the lifecycle-rich CPU queue witness:

```text
queued MCSs                 12
P / U                       7 / 7
copy-unit lengths           (36, 2, 2, 2, 4, 8, 2)
warm enqueue allocations    67,200 bytes for each of ten measured MCSs
settlements                 1
provider synchronizations   1
committed MCSs              12
```

## Admission outcome

K09-1 fails the mandatory common-representation and net-source-deletion holds.
Consequently:

- K09-2 is rejected rather than frozen;
- K09-3 never opens and no disposable candidate exists to remove;
- no LocalWorksets mechanism, API, evidence row, capability identity, or
  checkpoint identity is added; and
- K01, L01, later operation families, G6, and MethodOfLines input fields remain
  closed.

The corrected direct implementation proceeds to K09-R1 only for qualification
and committee seal, not for a second attempt to tune the admission threshold.
