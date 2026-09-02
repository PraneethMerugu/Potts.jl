# LW-R2 consolidated chair red-team

Date: 2026-08-12 (America/New_York)

Role: nonvoting final LW-R2 chair

Review disposition: **FREEZE**

Consolidated severity: **P0 = 0, P1 = 0, P2 = 2**

This is the single consolidated contradiction/red-team round. It does not
reopen architecture or naming, alter product/tool/evidence, or seal the
artifact.

## Bound identities

- Product commit: `ee395bd2f70d210fe98a0fb748e6530824c50671`
- Product tree: `b5ad1e71d73251fa6f932c8d275be8d1910f65fd`
- Preserved raw-evidence digest:
  `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`
- Post-evidence qualification-tool commit:
  `3c40628517db2b29b5e6f95dec4d51fece0875d6`
- Bound revalidation record: `review/tool-revalidation.toml`, disposition
  `pass`, validator SHA-256
  `32ade4fefc9ad35314acecad045f3ddd9923414ab1e77a73c5295e68bb5b9fdf`,
  and the exact preserved raw-evidence digest above

I confirmed that the product commit resolves to the stated product tree. The
current validator reconstructed the preserved artifact and exact evidence
digest, and the current validator separately accepted the bound
tool-revalidation record.

## Specialty ballots

| Role | Disposition | P0 | P1 | P2 |
|---|---|---:|---:|---:|
| scientific-api | pass | 0 | 0 | 1 |
| julia-api | pass | 0 | 0 | 0 |
| gpu-backend | pass | 0 | 0 | 0 |
| numerical-determinism | pass | 0 | 0 | 0 |
| external-extension | pass | 0 | 0 | 1 |

All five final memos bind the same product and evidence identities and issue a
pass ballot with no P0 or P1. The chair adopts the union of retained P2
findings rather than allowing a zero-P2 specialty ballot to erase dissent in
another specialty.

## Consolidated contradiction disposition

1. The scientific-api review's earlier P1 for bottom or nonconcrete external
   operation results is closed in the exact product candidate. The final memo
   verifies structured, prelaunch rejection across direct, buffered, and
   heterogeneous paths, including `Union{}`, without destination mutation.
   That closure is product-candidate behavior covered by the preserved product
   evidence; it is not attributed to the later validator hardening.

2. The gpu-backend review's initial P1 is withdrawn, not downgraded. The exact
   documented outer validator command works without an undocumented outer
   `--startup-file=no`, while each recorded product child command contains the
   required canonical flag exactly once. This was a contradiction in the
   initial interpretation of the command boundary; no post-evidence product or
   raw-result change was used to close it.

3. The numerical-determinism review's initial P1 was a qualification-tool
   semantic-validation defect: hostile witness-roster, force-policy, domain,
   and determinism-claim substitutions could pass the original validator.
   Commit `3c406285` hardened the tool and its self-tests. Under the LW-4Q
   invalidation rules this tool-only change invalidated tool validation, not
   the unchanged raw product execution. The bound revalidation record proves
   that the hardened validator reconstructs evidence digest `49002d...641`;
   repeated adversarial substitutions now reject. The original P1 is therefore
   closed and withdrawn without pretending that the product candidate moved
   from `ee395bd2` or that the preserved raw evidence was regenerated.

4. The Julia/package-boundary memo reports no P2 while the scientific and
   external-author memos each retain one. These are not blocking ballot
   contradictions: the Julia memo assesses the high-value package boundary,
   while the other reviewers preserve narrower diagnostic-quality defects.
   The chair records both as dissent below.

No surviving contradiction changes any role's final P0/P1 count. Consolidated
blocking severity is therefore P0 = 0 and P1 = 0, satisfying the decision
schema's condition for a chair disposition of `freeze`.

## Preserved P2 dissent

1. **Scientific topology diagnostics:** duplicate resolved semantic identities
   and competing independent writers fail closed, but at least one ordinary
   topology error leaves the structured fields of
   `LocalWorkValidationError` unset. Carry stable plan-stage contracts and
   field assertions into LW-5; no pre-freeze product change is required.

2. **External resolved-constructor diagnostic:** omitting generic resolved
   `maximum` can dispatch through the retained compatibility spelling and
   report `legacy resolved output requires capacity`. The error is immediate
   and safe but misleading. Improve diagnostic disambiguation in follow-up
   without changing the frozen API.

These two P2s are nonblocking diagnostic debt. They authorize neither silent
finding deletion nor a product/evidence edit during this review.

## Chair decision and LW-5 gate

The nonvoting chair records **FREEZE** for the review decision: five passes,
consolidated P0 = 0, and consolidated P1 = 0.

This decision is not itself the operational freeze announcement. The
authoritative LW-4Q workflow requires the exact review state to be sealed,
committed, and accepted by `--verify-final` before LW-R2 is announced frozen.
This task deliberately performs no seal. Consequently LW-5 remains gated for
now; it may start once those separately authorized finalization steps succeed
without changing the bound product, evidence, or substantive review findings.
