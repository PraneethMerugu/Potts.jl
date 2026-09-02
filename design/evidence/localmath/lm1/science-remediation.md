# LM-1 scientific remediation evidence

Date: 2026-08-22

Disposition: **APPROVE**. Science remediation and the combined GPU-owned
relation-receipt gate are complete.

## Exact Ghost relation authority

Ghost mapping storage now follows the same sealed content-authority split as
the other stored relation families:

- immutable CPU mappings are range-validated against `0:ghost_count`, receive
  a package-minted SHA content fingerprint, and reject mutation at preparation
  or warm freshness validation;
- mutable or device-resident mappings require paired `UInt64` generation,
  `Int32` status, and validated-generation storage;
- the existing relation-receipt execution spine constructs a typed
  `_GhostRelationContentValidator` and validates every mapping entry with
  KernelAbstractions before recording the generation receipt;
- malformed positive or negative endpoints leave the validated generation at
  zero, close every dependent Stage through the existing prefix guard, and
  cannot be interpreted as an intentional missing boundary read;
- the prepared Ghost view accepts only proof-recorded static-fingerprint or
  device-validation authority. Caller-written status-only admission is gone.

This adds no Ghost-specific planner, executor, backend branch, or settlement
path.

## Exact relation-failure provenance

Cold Stage context now retains the ordered identities of its dynamic relation
dependencies. Runtime relation failure records continue to store the bounded
dependency ordinal, but settlement resolves that ordinal against the relation
tuple rather than the publication tuple. A relation-content failure therefore
reports the exact relation identity, dependency ordinal, Stage, and source
origin; it does not invent a publication port.

## Focused evidence

The following focused CPU evidence passed:

- structural binding and sealed relation proof: 58/58;
- fixed/inverse content authority: 6/6;
- Ghost mapping content authority: 4/4;
- parameter-schema composition: 3/3;
- packed receipt structural references: 11/11;
- stored-relation preparation: 11/11;
- computed composition and boundary preparation: 16/16;
- dynamic-degree preparation: 3/3;
- new KernelAbstractions Ghost malformed/mutation checks: 6/6;
- new relation-failure provenance checks: 6/6;
- Stage-program lifecycle and heterogeneous-law checks: 4/4, 7/7, 3/3,
  13/13, and 12/12.

The complete `test_relation_receipts.jl` packet passes 69/69. PackedRelation
content is now validated by a package-owned validator over the shared receipt
path; caller status cannot self-certify content. The focused Packed packet
passes 25/25, the Ghost malformed/mutation packet 6/6, and relation provenance
6/6.

## Scientific boundary result

No CPM, LBM, LSM, or FEM meaning moved into LocalWorksets. CorePotts continues
to own Hamiltonian meaning and source order, before/after proposal semantics,
semantic RNG, Metropolis acceptance, MCS scheduling, lifecycle transactions,
checkpoint continuation, and CPM capability claims. This remediation changes
only domain-neutral topology truth and its diagnostic provenance.

The independent scientific-modeling reviewer approved the stabilized exact
source with no remaining blocking finding.
