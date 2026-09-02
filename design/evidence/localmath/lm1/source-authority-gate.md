# LM-1 source-authority gate evidence

Date: 2026-08-22

The direct LM-1 source gate was run from the repository root:

```text
$ julia --project=. scripts/check_localmath_lm1_gate.jl
LocalMath LM-1 machine gate: source authorities green; compiler review remains red
```

The green result covers all 19 required ledger rows, global forbidden
authorities, deleted API call sites in production/tests/benchmarks, exact public
exports, the exact 38-name LocalWorksets KernelAbstractions kernel inventory,
the sealed RelationProof construction inventory, required relation-family
anchors, absence of raw vendor-kernel APIs, and the cold-only
ProgramRelationshipState allowlist with canonical PackedRelationshipBank warm
storage.

PackedRelation generation/status declarations are not trusted as content
evidence. The existing relation-receipt execution family constructs a typed
`_PackedRelationContentValidator` and queues the same three KernelAbstractions
content-validation kernels used by other mutable relation representations.
Before publishing `validated_generation`, they check the selected packed
offset/count segment, declared capacity, active-slot bounds, endpoint-lane
bounds, and every active endpoint against the proved codomain. No kernel was
added: the exact LocalWorksets inventory remains 38 names, and failures publish
through the sole stage-qualified first-failure/status buffer.

Focused CPU evidence after this cutover is green: the PackedRelation packet
passes 25/25 assertions and the complete relation-receipt file passes 69/69,
covering valid content, inactive slots, malformed count, malformed offset,
segment overflow, invalid active endpoints, lifecycle succession, inverse and
Ghost validation, and exact relation-failure provenance. The CPU D2Q9 witness
also passes after the qualification-buffer edit.

The first focused Metal PackedRelation attempt did not reach the content
validator: exact backend qualification rejected the generic status-helper loop
used by `_stage_backend_qualification_gate_kernel!`. That qualification-only
kernel now writes all six status rows explicitly with the backend-native KA
linear index, removing the checked/dynamic helper path. On the stabilized exact
source, the real-Metal D2Q9 Stage-program witness passed and reported
`(:lbm_d2q9, :stage_program, (1,))`. CPU and GPU use the same
KernelAbstractions execution architecture.

The edited CorePotts lifecycle compaction source and backend-conformance
witness parse, `CorePotts` loads with `--compiled-modules=no` in its package
environment, and `git diff --check` is green. The focused root-environment
conformance invocation was not run because the root Manifest's LocalWorksets
entry predates the UUIDs dependency now declared by LocalWorksets. The Manifest
was intentionally not resolved or altered for this evidence step. Independent
GPU/performance and scientific-modeling reviewers approved the stabilized
source. The compiler/Julia reviewer rejected it: corrected four-stage host
compilation was 50.90 seconds against the frozen approximately 15.05-second
ceiling, and the corrected physical-launch identity is not comparable to the
old LM-0 harness. The ledger therefore records
`implementation_complete_review_rejected_compiler_gate`; LM-1 is not complete.
