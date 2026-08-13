# LW-R2 numerical correctness and determinism review

Review date: 2026-08-12 (America/New_York)

Disposition: **PASS**

Severity count: **P0 = 0, P1 = 0, P2 = 0**

This is a bounded numerical/determinism ballot. It does not reopen the architecture and it
authorizes no production, qualification-tool, evidence, decision, or seal edit.

## Exact reviewed identities

- Product commit: `ee395bd2f70d210fe98a0fb748e6530824c50671`
- Product tree: `b5ad1e71d73251fa6f932c8d275be8d1910f65fd`
- Evidence digest: `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`
- Workload digest: `c7bd404d26f42db0a887094aa125f377e043fc196e54a8ca95fd8e1b1a1dfe69`
- Original Freeze qualification-tool SHA-256:
  `8a99ff0e698a635396899596d07f04b9667ca8b393701c540b0f6037f560f4ee`
- Revalidation-tool commit: `3c40628517db2b29b5e6f95dec4d51fece0875d6`
- Revalidation-tool tree: `42f2f739dc71f065d1f5f7e7b5cbca88594f670e`
- Revalidation-tool SHA-256: `32ade4fefc9ad35314acecad045f3ddd9923414ab1e77a73c5295e68bb5b9fdf`
- Revalidation record: `review/tool-revalidation.toml`, disposition `pass`, artifact digest
  `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`
- Qualification profile: normal; 1,000 paired microbenchmark samples; 10,000 bootstrap
  resamples; one-sided upper bound threshold 1.05
- Host identity: Julia 1.12.6, KernelAbstractions 0.9.42, Darwin/aarch64,
  `arm64-apple-darwin24.0.0`, Apple M1, one Julia thread
- Reviewed Metal row: Metal.jl 1.10.0, Apple M1 Pro (14 GPU cores), macOS 15.6.1 /
  Darwin 24.6.0, Metal 3.2, AIR 2.7, metallib 1.2.8

The preserved artifact's product commit/tree and original qualification-tool hash agree with its
identity record. `HEAD` and `HEAD^{tree}` agree with the revalidation-tool commit/tree above, and
the current tracked validator hashes to the value recorded in `review/tool-revalidation.toml`.
The bundle is untracked review input and does not alter either committed tree. I ran the current
documented validator; it exited zero and reconstructed the exact preserved evidence digest above.
I separately validated the revalidation record; it exited zero. A fresh current-tool self-test and
validation of its temporary tool record also exited zero.

## Independent numerical checks

I deserialized the raw machine records and independently recomputed the comparisons and all five
performance decisions from the ordered samples and recorded seeds.

### Scientific results and determinism

- All five CPU reports and all five real-Metal reports equal their own references. The observed
  CPU and Metal result values also happen to be equal for D2Q9, deterministic spring, fast spring,
  matrix-free FEM, and z-buffer. That observation is not elevated to a cross-backend guarantee.
- D2Q9 is an exact nine-lane disjoint permutation and rejects a duplicate destination. Matrix-free
  FEM exactly matches the serial reference, including publication of the zero identity at the
  empty destination. Z-buffer exactly matches total rank plus semantic-identity tie resolution and
  publishes the explicit empty value.
- The deterministic spring policy is exact for edge state, force, and fracture. Its recorded force
  error is exactly zero. The fast spring keeps exact edge/fracture checks and the fixed force
  tolerance `8eps(Float32) == 9.536743f-7`; its recorded maximum force error is zero on both CPU
  and Metal. Fast mode still reports replay, scheduling, workgroup, same-backend bitwise, and
  numerical guarantees as not claimed.
- Deterministic combined publication folds buffered values in canonical item/local-slot record
  order. The standalone bit witness matches the serial Float32 fold by representation, and the
  spring/FEM witnesses exercise the same canonical mechanism. Resolved publication compares a
  total rank and unique `UInt32` semantic tie identity; the spring and z-buffer hostile duplicate
  identities reject during planning on CPU and real Metal.
- Every determinism report that contains `cross_backend_bitwise` records `:not_claimed`. The
  package README likewise limits runtime qualification to CPU and the reviewed Apple M1 Metal row.
  There is no CUDA, ROCm, other-device, other-environment, or cross-backend-bitwise conclusion in
  this ballot.

### Checkpoint continuation and RNG identity

The frozen CorePotts test process passed the 65-assertion private LocalWorksets vertical. Direct and
candidate execution settle twelve queued MCSs to exact equality of counters, ownership, cell
kinds/generations, trackers, relationships, descriptor state, rank/identity scratch, and commit
facts. Direct and replay-qualified candidate checkpoints reject cross-restore. A candidate
checkpoint whose outer checksum is recomputed after replacing only the RNG lowering identity is
rejected specifically at the RNG-contract boundary. Restoring the matching direct and candidate
checkpoints and continuing through MCS 16 again gives exact equality of the complete recorded
state. The ordinary checkpoint suite separately passed exact uninterrupted/restored continuation
for both sequential and checkerboard engines.

### Recomputed performance decisions

| Row | pairs | candidate/direct median | recomputed upper 95% | decision |
|---|---:|---:|---:|---|
| CPU D2Q9 | 1,000 | 0.9526084046 | 0.9529322491 | pass |
| CPU z-buffer | 1,000 | 0.9982776533 | 0.9984557417 | pass |
| Metal D2Q9 | 1,000 | 1.0198044196 | 1.0207628835 | pass |
| Metal z-buffer | 1,000 | 1.0114169358 | 1.0143378194 | pass |
| CorePotts Metal parity | 50 | 0.9985898448 | 1.0023289080 | pass |

The CPU and Metal microbenchmarks use the same fixed randomized order vectors. Each direct and
candidate microbenchmark row has 16,080 submitted and drained batches, positive waits, and equal
launch counts (one for D2Q9, two for z-buffer). The CorePotts row reconstructs from seed
`0x6c77335f626f6f74`, has 600 submitted/drained LocalWorksets claims and 60 waits, and retains its
fixed 32-byte algorithmic workspace. Allocation facts are evidence, not a universal improvement:
the candidate uses more host allocation bytes for CPU z-buffer and both Metal microbenchmarks,
while CPU D2Q9 and the CorePotts Metal batch are lower. Only the fixed latency noninferiority rules
pass.

## Contradiction history — initial P1 withdrawn

My initial ballot was **BLOCK** with one P1. The original validator did not bind an exact ordered
witness/mode roster and selected the exact-versus-tolerant spring force policy from the report's
own mutable `force_mode`. It also did not reconstruct the determinism report. Against that earlier
tool I demonstrated four accepted hostile substitutions without editing the artifact:

1. a second fast spring report in the deterministic spring slot;
2. a deterministic-to-fast relabel plus a one-Float32-ULP force error (`2.3841858f-7`);
3. FEM and z-buffer slots replaced by additional D2Q9 reports; and
4. an affirmative replacement for `cross_backend_bitwise.guarantee = :not_claimed`.

Commit `3c40628517db2b29b5e6f95dec4d51fece0875d6` closes that exact finding. The current validator
binds this ordered roster exactly:

```text
lbm_d2q9
lattice_spring / deterministic
lattice_spring / fast
matrix_free_fem
zbuffer
```

For every non-LBM record it reconstructs the complete eight-dimensional determinism report from
the exact witness, mode, and qualified backend. That reconstruction pins lowering identity, port
modes, canonical/fast guarantees, `rng_trajectory = :domain_owned`, and
`cross_backend_bitwise = :not_claimed`. LBM must carry no determinism claim, and all four reporting
witnesses must name one consistent qualified backend, either `:CPU` or `:MetalBackend`.

I repeated the original adversarial probes against the current committed validator. The duplicate
fast report, deterministic-to-fast relabel, and missing-domain substitutions each rejected with
`wrong ordered cross-domain witness roster`. The inflated cross-backend claim rejected with
`witness determinism report does not reconstruct`. An additional mixed CPU/Metal report rejected
with `mixed cross-domain witness backends`. The current tool self-test passed and covers the fixed
roster/policy and inflated-claim rejection classes. Finally, the bound revalidation record verifies
the new validator SHA-256 and the preserved artifact digest, and the new validator reconstructs the
preserved raw artifact successfully.

The initial P1 is therefore **withdrawn**, not downgraded. No raw product result changed, no
architecture was reopened, and no CPU/Metal performance rerun was necessary under the established
tool-only revalidation workflow.

## Ballot

- P0: 0
- P1: 0 — the initial semantic-validator P1 is closed and withdrawn after exact adversarial
  recheck against the revalidation tool
- P2: 0
- Raw numerical correctness: pass for the exact recorded CPU and Apple M1 Pro Metal rows
- Raw deterministic/resolved/checkpoint/performance evidence: pass within the explicitly recorded
  scopes
- Final numerical/determinism disposition: **PASS**
