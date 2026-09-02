# LW-0 corrected CorePotts baseline

Date: 2026-08-09

Status: Frozen; LW-R0 passed, LW-1 not begun

Authority: [LocalWorksets V1 Implementation and Review Gate](../../spec/localworksets-v1-implementation-gate.md)

## Candidate scope

This is the direct CorePotts implementation that LW-R0 reviews and, if accepted, LW-3 uses as its
comparison baseline. No LocalWorksets implementation or checkerboard migration is present.

The candidate closes the three LW-0 blockers without changing domain ownership:

- **CP-B1:** checkerboard colors use an unbiased Fisher--Yates permutation in preallocated host
  storage. Its semantic RNG address is stream `CheckerboardColorOrderStream`, MCS `state.mcs + 1`,
  subround `1`, operation `5`, global entity, and permutation position. CPU and Metal use the same
  generated order; every launch receives one immutable scalar color argument.
- **CP-B2:** `SequentialCPM` and `CheckerboardSweepCPM` admit exactly
  `AttemptsPerSite(1)`. Other values reject before runtime construction rather than changing an
  existing algorithm's normalization or kinetics.
- **CP-B3:** RNG contract `1.2.0` and lowering identity
  `philox4x32x10_semantic_address_fisher_yates_v1` are part of capability and checkpoint identity.
  Restore rejects a checksum-valid checkpoint with either identity changed.

The existing asynchronous checkerboard contract remains intact: no intermediate waits were added,
multiple MCS submissions remain ordered on one KernelAbstractions lane, color-order storage is
preallocated, and arbitration, double-buffer publication, settlement, failure, and scientific
commit remain CorePotts-owned.

Hamiltonian authoring is unchanged. `HamiltonianTerm`, `Volume`, `ContactEnergy`, `Elongation`, and
registered external Hamiltonians still pass through `complete` and `mtkcompile`; before/after
proposal views and canonical source-order Hamiltonian folding remain CorePotts authorities.

## Exact qualification

All passing rows below ran on the candidate worktree under Julia 1.12.6 with one Julia thread on the
Apple M1 Pro. The real-device environment is a finite closed row: Metal 1.10.0, Julia 1.12.6,
Darwin/aarch64, 64-bit, `arm64-apple-darwin24.0.0`. The earlier exact Julia 1.12.1 row remains
enumerated; no version range or wildcard admission was added.

| Lane | Command | Result |
|:--|:--|:--|
| Complete CorePotts CPU | `julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'` | Exit 0. The full package suite passed, including 16,389 randomized-color assertions, 4/4 attempt-budget rejections, sequential/checkerboard scientific comparison, 26/26 logical checkpoint continuation, 113/113 structured capability assertions, 16/16 exact-environment checkpoint assertions, failure atomicity, lifecycle transactions, API checks, and 10/10 Aqua checks. |
| Complete PottsToolkit CPU integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | The pre-final zero-length-launch correction candidate passed runner closure 411/411 and the authoritative package surface 2,194/2,194 in 23m25.2s. The later correction is confined to suppressing zero-range backend lifecycle launches and exact Metal environment rows; this result is preservation evidence, not the required exact-candidate CorePotts admission row. |
| Qualified real Metal | `julia --project=benchmark/backends/metal benchmark/backends/metal/runtests.jl` | Exit 0 on the exact candidate. Fresh extension orders passed 2/2; native components passed 37/37; all checkerboard boundary sizes and workgroup sizes, constraints/energy branches, lifecycle, checkpoint, queued failure/publication, policy, and closed external-mechanism rejection rows passed. No CPU fallback was accepted. |
| Focused zero-request Metal regression | Same environment, loading `lifecycle_policy_execution.jl` and calling `run_forbid_extinction_execution(Metal.MtlArray; backend_name=:metal)` | Exit 0; seed 1, one constraint rejection. The complete Metal runner independently passed the same row afterward. |
| CPU baseline | `julia --project=. benchmark/src/lw0_corepotts_baseline.jl` | Exit 0; exact values below. |
| Metal coupled baseline | `julia --project=benchmark/backends/metal benchmark/backends/metal/native_component_performance.jl` | Exit 0; native qualification repeated at 37/37 and exact values below. |

Checkpoint mismatch coverage for CP-B3 constructs checksum-valid forged payloads. Both an altered
RNG contract version and an altered lowering identity reject specifically as RNG-contract
mismatches before environment or model restoration can proceed.

## Quantitative baseline

The CPU fixture is a 32 x 32 periodic lattice, 1,024 attempted sites per MCS, one cell, `Float32`,
12 warmed samples after one complete warmup step.

| Algorithm | Median seconds/MCS | Minimum seconds/MCS | Median host bytes/MCS | Throughput | Capability |
|:--|--:|--:|--:|--:|:--|
| SequentialCPM | 0.0000982085 | 0.0000926660 | 15,984 | 10,182.42 MCS/s; 10.4268 million attempted sites/s | Supported, ReplayQualified |
| CheckerboardSweepCPM | 0.0002520625 | 0.0002498750 | 89,632 | 3,967.27 MCS/s; 4.0625 million attempted sites/s | Supported, ReplayQualified |

For the one-color fixture, the direct checkerboard body performs exactly 10 launches per MCS: one
bulk clear plus nine launches per realized color, or `1 + 9C`. This count deliberately excludes
the surrounding state-copy, lifecycle, publication, and settlement envelope; there is no total
provider-launch counter, so this record does not invent one. The same body structure is used by CPU
and Metal.

After warmup plus 12 measured checkerboard steps, execution counters were exactly
submitted/drained/committed/materialized `13/13/13/13`, with 13 settlements, 13 synchronizations,
13 control transfers, 13 snapshot transfers, and zero lifecycle transfers. Separate conformance
rows queue multiple MCSs before one settlement and prove the same logical commit cut under an early
failure. The new zero-request `ForbidExtinction` row records `1/1/1/1`, no failure, and a full
snapshot without an intermediate wait.

The retained coupled real-Metal fixture uses two live per-cell native lanes in capacity four. Six
measured MCSs took 0.091408709 s (0.0152347848 s/MCS, 65.64 MCS/s) and allocated 7,284,656 host
bytes in total. After one warmup plus six measured steps it recorded 7 settlements, 14
synchronizations, and 7 control, snapshot, and lifecycle transfers. This is the qualified coupled
boundary cost, not a claim that raw checkerboard kernels themselves allocate that amount.

## Failures found during qualification

Admission and evidence rules were not weakened to make failures disappear:

1. The first complete CPU run rejected Julia 1.12.6 because only the older exact environment was
   reviewed. LW-0 adds separate exact default and bounds-checked 1.12.6 digests; arbitrary current
   processes still cannot manufacture replay evidence.
2. An accidental Julia 1.10 invocation failed during dependency precompile. The Metal project
   explicitly requires Julia 1.12, so this is an invalid command, not candidate evidence.
3. The first correctly invoked Metal run rejected Julia 1.12.6 against its exact 1.12.1 row. The
   candidate preserves 1.12.1 and adds a second fully enumerated 1.12.6 environment/stack row.
4. The complete Metal lifecycle suite exposed zero-capacity request scan and zero-range emission,
   marking, and compaction launches. CorePotts now treats only those empty ranges as no-ops; status,
   finalization, nonempty lifecycle execution, and admission remain unchanged. Focused Metal,
   complete CorePotts CPU, and complete Metal reruns pass after the correction.

## LW-R0 handoff

LW-R0 was required to review the exact submitted worktree, including the finite environment
additions and both zero-range guards. Its scope included CP-B1--CP-B3, scientific and asynchronous
preservation, checkpoint identity, capability closure, launch/allocation/throughput baselines, and
the unchanged Hamiltonian authoring boundary. P0/P1 would have blocked LW-1; P2 would have required
an explicit disposition.

## LW-R0 outcome

The fresh independent read-only reviewer verified base HEAD
`45ce4173e06ec9079f3ea39223ddd62bb7e0607c`, tracked binary patch SHA-256
`afe14f6dcf804a5b33862f354bb95bc8ed37bb0d31e4777076a9f7d81ef60152`, and every submitted
untracked artifact hash. Its ballot was **PASS** with P0=0, P1=0, P2=0, P3=0, and no substantive
dissent. It accepted the predecessor-only 2,194/2,194 root result strictly as preservation context,
not exact-candidate admission, because the required exact-candidate complete CorePotts CPU and
qualified real-Metal rows pass independently.

The reviewer confirmed CP-B1--CP-B3, finite fail-closed environment admission, asynchronous/Core
ownership, Hamiltonian preservation, the zero-capacity lifecycle correction, the normative
LocalWorksets contract, and the unchanged MethodOfLines deferral. LW-0 is therefore frozen. This
record does not begin LW-1.
