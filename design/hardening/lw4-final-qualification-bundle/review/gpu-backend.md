# LW-R2 GPU/backend-lowering review

Date: 2026-08-12

Disposition: **PASS**

Final severity count: **P0 = 0, P1 = 0, P2 = 0**

## Exact reviewed identities

- Product commit: `ee395bd2f70d210fe98a0fb748e6530824c50671`
- Product tree: `b5ad1e71d73251fa6f932c8d275be8d1910f65fd`
- Evidence digest: `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`
- Workload digest: `c7bd404d26f42db0a887094aa125f377e043fc196e54a8ca95fd8e1b1a1dfe69`
- Qualification-tool SHA-256: `8a99ff0e698a635396899596d07f04b9667ca8b393701c540b0f6037f560f4ee`
- Freeze profile: normal, 1,000 paired samples, 10,000 bootstrap resamples, threshold 1.05
- Host row: Julia 1.12.6, Darwin/aarch64, `arm64-apple-darwin24.0.0`, `apple-m1`, one Julia thread
- Provider stack: KernelAbstractions 0.9.42, Atomix 1.1.3, Adapt 4.7.0
- Qualified Metal row: Metal.jl 1.10.0 on Apple M1 Pro (14 GPU cores), macOS 15.6.1 / Darwin 24.6.0, Metal 3.2, AIR 2.7, metallib 1.2.8; the exact reviewed source row also binds registry ID `0x000000010000099d`, built-in unified-memory device properties and the recorded provider preferences

`git rev-parse HEAD` and `HEAD^{tree}` matched the requested product identities. The bundle was
untracked review input, so it did not alter the candidate tree.

## Contradiction record: initial P1 withdrawn

My initial ballot classified the authoritative validator example as P1 because it contains no
outer `--startup-file=no`:

The exact final sequence in `design/hardening/lw4q-qualification.md` documents:

```sh
julia --project=. benchmark/lw4_qualification.jl --validate=ARTIFACT
```

I initially read the acceptance condition as requiring that literal flag in both the outer
validator example and every product-command ledger row. The contradiction round established that
this was stricter than the chair's actual requirement. The prior defect was that this documented
command failed unless the user supplied an undocumented outer flag. The corrected candidate must
make the documented command work exactly as written.

I reran that exact documented form, without an outer startup-file flag:

```sh
julia --project=. benchmark/lw4_qualification.jl \
  --validate=design/hardening/lw4-final-qualification-bundle
```

It exited zero and reconstructed evidence digest
`49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`.
The initial P1 is therefore withdrawn, not reclassified.

Concretely, `_canonical_julia_command` is used to construct Freeze/Check child commands. It removes
startup-file flags inherited through `Base.julia_cmd()`, preserves other material Julia flags, and
then each product child command explicitly receives exactly one `--startup-file=no`. Validation
uses that canonical construction to reconstruct the ledger; validate/seal/verify do not themselves
spawn product children. Requiring an outer flag in those examples is therefore unnecessary for the
qualified product-command contract. Every one of the six rows in `commands.tsv` contains exactly
one `--startup-file=no`, and the behavior is covered by the passing exact tool-validation record.

## GPU/backend-lowering assessment

The implementation itself passes this specialty review.

- Provider and lowering execution are vendor-neutral KernelAbstractions source. The only Metal
  names under production `LocalWorksets` are isolated constant qualification/probe data in
  `localworksets_evidence.jl`; that file has no functions, kernels or synchronization. The
  provider, topology transfer, allocation and lowerings have no Metal/CUDA/AMDGPU/ROCm branch.
- All execution families launch KernelAbstractions kernels directly and rely on backend implicit
  program order. Ordered sequences append stage launches without an intermediate host wait,
  barrier node, scheduler, stream, queue or native event.
- Production has one executable `KernelAbstractions.synchronize` call, in `_wait_lane!`. `run!`
  performs no host wait; `wait(WorkEvent)` synchronizes the cumulative lane tail once and releases
  the complete submitted prefix. Real-Metal evidence queues 12 MCSs and reports 12 submitted, 12
  committed and one synchronization. Failure evidence observes and poisons the shared
  backend/owner-task scope, with failed shared tails retaining zero drained counters.
- Static topology arrays transfer during preparation through package-owned `Adapt.adapt(backend,
  values)` (CPU uses `copy`). Algorithmic scratch allocates during preparation through
  `KernelAbstractions.allocate`; it is neither host-allocated-and-adapted nor vendor-constructed.
  Prepared array/backend/device/layout identities are validated, and warm execution reports fixed
  workspace and topology identities rather than hidden transfers or growth.
- GPU compilation is represented honestly. Structural and reviewed-provider checks happen before
  execution; because KernelAbstractions 0.9 has no portable compile-only operation, selected-device
  compilation is explicitly `:deferred_to_first_run`. The Metal runner uses real `MtlArray`
  storage with scalar indexing disabled, executes all retained kernels, and records unchanged
  same-schema compiler-cache size `361 -> 361` after warm-up. A device-kernel exception is observed
  only at the portable synchronize boundary and poisons the provider; there is no host fallback.

The source and evidence therefore support only the exact recorded CPU environment and the exact
Apple M1 Pro Metal row. They support a vendor-neutral source/portability intent, not CUDA, ROCm,
other Metal devices, other dependency versions, cross-backend bitwise identity, or a general GPU
support claim.

## Executable evidence and performance

The final contradiction-round validation command I ran was the documented command exactly:

```sh
julia --project=. benchmark/lw4_qualification.jl \
  --validate=design/hardening/lw4-final-qualification-bundle
```

It exited zero and reconstructed the exact evidence digest above. It verified the six successful
product commands, exact ordered command/environment ledger, ten Project/Manifest snapshots,
commit-owned workload objects, artifact inventory, raw result invariants, raw Metal/host identity
and summary reconstruction. The preserved Metal log includes fresh extension orders 2/2,
cross-domain witnesses 8/8 and native components 37/37.

| Lane | samples | ratio | upper 95% | bound | allocation evidence |
|---|---:|---:|---:|---:|---|
| CPU D2Q9 | 1,000 | 0.9526084046 | 0.9529322491 | 1.05 | candidate 4,400 B / 163 allocations; direct 5,632 B / 128 |
| CPU z-buffer | 1,000 | 0.9982776533 | 0.9984557417 | 1.05 | candidate 13,104 B / 419; direct 7,936 B / 208 |
| Metal D2Q9 | 1,000 | 1.0198044196 | 1.0207628835 | 1.05 | candidate 94,288 B / 1,900; direct 52,208 B / 1,214 |
| Metal z-buffer | 1,000 | 1.0114169358 | 1.0143378194 | 1.05 | candidate 145,888 B / 3,357; direct 100,480 B / 2,687 |
| CorePotts Metal parity | 50 | 0.9985898448 | 1.0023289080 | 1.05 | candidate median 17,146,064 B; direct 17,678,976 B |

All controlled latency bounds pass with useful margin. Launch counts equal their direct comparators
(one for D2Q9, two for z-buffer), and all 16,080 performance submissions in each candidate/direct
row are drained. The raw records retain launch, wait, allocation, submission/drain, topology-
transfer and workspace facts. Allocation is evidence, not a separate noninferiority gate: the
candidate has more host allocations in three of four microbenchmarks, so no allocation-improvement
claim is warranted beyond the lower CorePotts batch median and CPU D2Q9 bytes shown above.

Cross-domain witness transfer/workspace facts are nonzero where expected, automatic workspace is
package-owned, and each witness performs the documented launches and waits. This is adequate to
distinguish preparation-time transfer/allocation from warm launch/wait behavior.

## Eventual general-package room

The remediation does not obstruct the eventual general package. Concrete isbits operation/result
validation is the static form needed for device compilation; backend admission remains central;
topology transfer and workspace allocation are provider-generic; and a new reviewed backend row is
additive rather than a new scheduler or lowering family. Exact-environment whitelisting is narrow
qualification policy, not vendor coupling in execution source. Broader devices and dependency
versions still require their own reviewed evidence, and the legacy resolved compatibility path
remains removable only through its documented parity/migration rule.

## Ballot

- P0: 0
- P1: 0
- P2: 0
- GPU/backend implementation: pass
- Evidence/performance: pass for exact CPU and Apple M1 Pro Metal rows
- Initial P1: withdrawn after the documented validator command passed exactly and the child-command
  canonicalization boundary was reconciled
- Final specialty disposition: **PASS**
