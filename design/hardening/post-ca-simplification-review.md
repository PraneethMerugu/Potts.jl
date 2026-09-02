# Post-CA simplification implementation and review

Date: 2026-08-15

Status: **S0-S2 complete and qualified; committee PASS**

This record closes the bounded simplification authorized by the
[full audit](post-ca-full-simplification-audit.md). It compares against the
dirty-worktree baseline identity fingerprinted by
`post-ca-simplification-baseline.sha256`; the older Git `HEAD` is not the
behavioral baseline. The manifest authenticates identities but is not a
standalone reconstruction of those dirty pre-edit bytes; the per-slice ledger
below is therefore committee-attested from implementation checkpoints. No
LocalWorksets feature, CorePotts scientific operation, public API, SPI,
execution family, or PottsToolkit authoring behavior was added.

## Exact result

Production line counts use the same rules as the audit. "Executable" means a
nonblank Julia source line whose first non-whitespace token is not a comment.

| Boundary | Baseline raw | Final raw | Delta | Baseline executable | Final executable | Delta |
|---|---:|---:|---:|---:|---:|---:|
| LocalWorksets | 11,136 | 11,009 | -127 | 10,580 | 10,453 | -127 |
| CorePotts | 25,530 | 25,290 | -240 | 23,889 | 23,658 | -231 |
| PottsToolkit | 24,093 | 24,093 | 0 | 22,687 | 22,687 | 0 |
| **total** | **60,759** | **60,392** | **-367** | **57,156** | **56,798** | **-358** |

The committee-attested slice checkpoints recorded during implementation give
this exact ledger:

| Slice | Raw delta | Executable delta | Result |
|---|---:|---:|---|
| S0 | -313 | -289 | dead code deleted; no replacement abstraction |
| S1 | -30 | -34 | narrowed security-preserving LocalWorksets deduplication |
| S2 | -24 | -35 | typed CorePotts execution-profile and preparation consolidation |

The audit's 533-607-line estimate carried an original 500-600-line acceptance
band. The committee explicitly amended that numerical criterion after the exact
implementation and contradiction review; the original criterion was not met.
Several apparent duplicates proved to be concrete family-admission,
error-order, host/device-authority, or performance boundaries. They remain
explicit. The replacement acceptance rule requires every slice to be
independently net-negative in both measures and the complete zero-loss evidence
matrix to pass.

## Implemented scope

S0 removed the reviewed unreachable LocalWorksets validation/extraction
helpers, the ungated CorePotts lifecycle-copy family, superseded LocalWorksets
adapter constructors, and the unreachable checkerboard advance tail. The live
generated canonical-submission authority remains hostile-method tested.

S1 performs only the safe common intersection:

- one centrally admitted immutable workspace-array traversal is reused for
  identity, device, alias, topology, and prepared-state validation;
- concrete direct and buffered binding/access methods remain, while their
  identical derivation is centrally admitted;
- one typed workspace-tree constructor replaces the two construction walkers;
  and
- immutable independent-determinism and four-phase-resolution constants replace
  duplicated values without changing evidence field placement.

S1 deliberately did not merge active-prefix checks, static topology payloads,
topology transfer/compiler evidence, or concrete execution-family methods.
The pre-existing authority debt below `_determinism_report`, `_port_evidence`,
and winner-evidence helpers is unchanged and receives no simplification credit.

S2 now has:

- one private immutable `_LocalWorksetsExecutionProfile` schema for mechanism,
  lowering, provider, and compiler identity;
- exact-invoked claim and proposal extractors, including all-bank provider and
  compiler agreement checks;
- one exact capability builder with qualification-specific policy kept outside
  the identity serializer;
- one exact checkpoint serializer that consumes the typed profile directly;
- one exact-invoked checkerboard preparation validator for plan identity,
  offsets, epoch, batch bound, and backend;
- one normalized descriptor reference reused by provenance and bridge state;
  and
- removal of unused stored `maximum_batch` and `source_count` bridge fields.

Distinct queue, bank, lease, type, and first-error policies remain at their
concrete callers. Direct and LocalWorksets proposal science, publication,
Hamiltonian folding, RNG, settlement, lifecycle, and checkpoints remain
CorePotts-owned and independent.

## Exact identity oracle

The durable
[recreated-constructor/checkpoint oracle](post-ca-simplification-identity-oracle.jl)
feeds the captured pre-S2 serializer and the final serializer from the same
centrally validated profile. Run it with
`julia --project=lib/CorePotts design/hardening/post-ca-simplification-identity-oracle.jl`.
It passed 8/8 report, block, key-order, sealed-fingerprint, reason, and digest
comparisons. Static
review separately verified that the extractors preserve the pre-S2 facts and
diagnostic order.

| Profile | Capability fingerprint | Evidence-profile fingerprint | Checkpoint fingerprint |
|---|---|---|---|
| replay claim | `e331353c1e8a081a735c6665ffa9d3cc8dcc3086c90e23b8b38b889f9db82fb9` | `c0e6910a8774fe1e7b423e7bad3154834415b5b5609cc92f2b9b8881dfe237a9` | `13120ccaeb1fe2e651d63974d97ffb67f3e92b23c6e6b351c039b8286bb7d864` |
| promoted K02/K03 | `8fad5ac74658b1434722688ba70acd6d53e6858897b0ecdd81bed1a6184cf018` | `cb811e1adba4fb0ff628cbb33ac16ba2594a0a95e573f7be7b9b2403ab7e7933` | `1f960ceebe08e8fa5c35751238dfa25e73e8b5ca2a1325b9dcc3bea73989b9d7` |

## Selected final candidate identities

These path-sensitive composite hashes use the sorted SHA-256 record recipe
documented in the LW-5D evidence packet. File-level environment and Metal
extension identities are included so the qualified runtime surface is not
mistaken for an unrecorded dependency.

| Surface | SHA-256 |
|---|---|
| LocalWorksets production Julia | `0bba1bb4f965c37825d39f41a63dd7dc7cc7e288bf252b36e90665cce3e99ce5` |
| LocalWorksets tests | `a97b3d7f471e083fa8d4499bef2800d222a4dfb1780b2e2304987b88debb772b` |
| CorePotts production Julia | `8d9c056c417b45a5d0544606518108d8eede058979af7d4246ed484dcccf58de` |
| CorePotts tests | `ded08300528306fd839721d8853811a077c4366224d4a52c2bd841d0b999d037` |
| PottsToolkit production Julia | `c307aa522502a967bd8b060eb48e4424af28bdc7064a4fd89ae59d99aafe3ede` |
| PottsToolkit tests | `68431e77a14dced8b60c1ca99d185f776a73f50e597f65750df07f09f42c8fb9` |
| Metal Julia/project/manifest | `964b3d8e7467bf8bff22a9d5f24814989292069c6d4c1432aa00b050d7e0ceca` |
| PottsToolkit `Project.toml` | `dff6aba68029e2a5260422239d11bd346ce84dd7fd075e287e46a7d68d1179de` |
| PottsToolkit `Manifest.toml` | `847c48401d32bad935c8ec63694ca3d6a880e10115fdaf1aaacd431d456ef2bd` |
| CorePotts `Project.toml` | `acb0b9e2f2cf125329395bf90a210a47a8c8de6a322ea8f3e9d500af76e49033` |
| CorePotts `Manifest.toml` | `f4380bcbf3dfcc2ac3b10813574dde9875f316eb4db0bc545818c042d983f1ed` |
| LocalWorksets `Project.toml` | `a71dabb4f3bc0e38b7572d5e23826075b354f0e9d50fc2daf4be6dae371b6e4f` |
| LocalWorksets `Manifest.toml` | `2cbb706f605a60011a616443623a55dcaca3feae0112d0efa59bea6d1c7ce1f2` |
| `ext/PottsToolkitMetalExt.jl` | `e722f04cbf624aa47ff1f32dfbd88fb63a019a5fcb262986b9e28ddb785c83fb` |
| `ext/PottsToolkitMetalNativeExt.jl` | `c69eb1ad3506228cfa27cf11191e2b623a2a2d3e51503ded697b77750b1d64ce` |

## Qualification evidence

| Boundary | Result |
|---|---|
| LocalWorksets focused and complete CPU | PASS; complete package suite, including hostile exact-method replacement tests |
| CorePotts focused vertical | PASS; promoted restore, RNG/contribution exactness, topology identity, queue/lease/failure cuts |
| CorePotts complete CPU | PASS; package suite and both fresh-process method-world tests |
| PottsToolkit complete CPU | PASS, 2,667/2,667 in 19m27s |
| recreated legacy identity oracle | PASS, 8/8 exact comparisons, including six literal sealed-fingerprint assertions |
| qualified real Metal | PASS; complete `benchmark/backends/metal/runtests.jl` command exited zero |
| cross-domain Metal witnesses | PASS, 13/13 |
| native Metal components | PASS, 37/37 |
| queued promoted Metal profile | PASS; 12 MCS, 24 submissions, one synchronization, zero intermediate waits, exact receipt/RNG/failure parity |
| static | `git diff --check` PASS; deleted-symbol reachability PASS; CorePotts compile/load PASS |

No controlled performance campaign was rerun because S0-S2 changed no kernel,
launch schedule, synchronization path, device transfer, or measured hot path.
The committee therefore carried forward the controlled LW-5D allocation and
performance bounds through unchanged measured-path identities instead of
requiring strict equality from a new campaign. The complete Metal evidence
reconfirmed launch counts, workspace and topology-transfer accounting,
compiler-cache reuse, queueing, and one-final-wait behavior. Its recorded
warm-host allocation value is diagnostic and does not mint a new numerical
bound. This is an explicit evidence-route amendment to the audit matrix, not a
claim that a new controlled allocation comparison was performed.

## Committee review

The API/Julia reviewer, JuliaGPU/backend reviewer, and external-adopter red team
reviewed independently, then re-reviewed after contradiction remediation.

| Reviewer | Final ballot | P0 | P1 | P2 |
|---|---|---:|---:|---:|
| API and Julia design | PASS | 0 | 0 | 0 |
| JuliaGPU, authority and lifetime | PASS | 0 | 0 | 0 |
| external adopter and contradiction | PASS | 0 | 0 | 0 |

The round caught and corrected more-specific-dispatch interception in the first
S2 draft, an incomplete shared execution profile, repeated checkpoint profile
repacking, a new interpolated-string allocation, and two dead bridge fields.
No reviewer found functionality loss in the final candidate.
The external review's documentation-only ledger request was completed before
this final ballot table was sealed.

## Held debt and exit

The following receive no S0-S2 credit and remain held:

- pre-existing LocalWorksets evidence-helper authority seams;
- active-prefix, static-topology, topology-transfer, and compiler-evidence
  consolidation that could not preserve concrete ownership cleanly;
- private proposal-bridge `science`, `proposal_batch`, `proposal_read`, and
  `schedule` fields observed by active private tests and lifetime reasoning;
- the S3 public CompilerSPI ownership proposal; and
- all previously rejected scientific-oracle, settlement, execution-family,
  and candidate-ABI mergers.

S0-S2 is sealed. This record authorizes no new feature or migration by itself;
subsequent work must use the roadmap's next explicit gate.
