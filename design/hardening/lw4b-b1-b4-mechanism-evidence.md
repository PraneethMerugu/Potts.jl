# LW-4B B1-B4 Mechanism Evidence

Date: 2026-08-11

Status: mechanism evidence only; not B5 qualification and not an LW-R2B ballot

## Implemented boundary

- provisional independent, deterministic combined, explicit fast combined and generic resolved
  declarations;
- fixed `emit` and `candidate` results, named heterogeneous ports and bounded multi-emission;
- one direct and one buffered internal execution family;
- canonical `(item, local-slot)` combination order and topology-owned resolved identities;
- caller-bound record workspaces with exact type/capacity/backend/alias validation;
- backend-neutral KernelAbstractions kernels using implicit ordering and the existing single final
  provider synchronize; and
- device-isbits declaration values, with the specialized z-buffer and CorePotts conjunctive paths
  preserved as oracles.

## CPU evidence

`julia --project=lib/LocalWorksets -e 'using Pkg; Pkg.test()'`

Result: **418/418 passed**. The 42 generic assertions comprise heterogeneous
independent/combined/resolved 11/11, deterministic/fast combination 13/13, direct independent
13/13 and partial bounded multi-emission 5/5. Package-quality, legacy mechanisms, ordering,
lifetime, poison and hostile-admission tests also pass. Every non-comment production review unit
remains at or below 1,000 lines.

`julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'`

Result: **17,462/17,462 passed**, including the adopted checkerboard vertical, exact checkpoint
continuation, replay/RNG evidence, lifecycle and failure settlement.

## Reviewed real-Metal smoke evidence

The exact centrally reviewed Apple M1/Metal row was used with `Metal.allowscalar(false)` and one
final `wait` per witness:

1. direct independent permutation: one launch, exact result;
2. heterogeneous independent + deterministic combined + resolved: two launches, exact disjoint,
   sum, winner and empty-destination results; and
3. explicit fast Float32 addition: two launches, exact small reference and inspection explicitly
   reporting `not_claimed_for_fast_ports` replay determinism.

The first Metal attempt correctly rejected declaration objects containing non-bitstype `Symbol`
and `Type` fields. Route/type/order facts were moved into concrete type parameters while preserving
their public properties. The same vendor-neutral source then compiled and passed; no extension or
vendor branch was added.

## Candidate hashes before this evidence document

```text
7388f8a4cc38f268ddff7a89215f588dc651039697d524bc7aa8096d586225da  lib/LocalWorksets/src/LocalWorksets.jl
053d33b94de85086026f5c34fbb86dd04459a8f6b646635fb6a910ee4269b911  lib/LocalWorksets/src/model.jl
1b1753e03da62695e341beb0945c3373f3e92a0114d18a2096b997d6e8a23a79  lib/LocalWorksets/src/inspection.jl
fb2ab7f176615339b0aabd20a0e8b6a6e0f17309e885a010f4e5207a7c58d5b8  lib/LocalWorksets/src/execution/mechanism_support.jl
9fd32ec0aabec72f6f0fb5ac775394dd624626d581c168d90008bd81eba0ef85  lib/LocalWorksets/src/execution/localworksets_generic.jl
527f583d63b7b58d3814072595cc3049f112be4caa12b06f29902cfebfa0507f  lib/LocalWorksets/src/execution/localworksets_combined.jl
1e05e6c1bb00e58c4307ddd9a755a3cbe242b3087c5a478865211a4157a2ca68  lib/LocalWorksets/src/execution/localworksets_combined_evidence.jl
f9cd88089f3c2a3451af2675809cb3a338f0b8d165ed0c85723a0d558f93b983  lib/LocalWorksets/src/execution/localworksets_resolved.jl
36c1f06a1e0801a5f55291213c9f75e079cbdb13fa2f59f353ba7bc106b49abe  lib/LocalWorksets/src/execution/localworksets_kernelabstractions.jl
9cd9392408dcb92a93ee327971b37fdae1777e291799032c12d05b8afbc481d1  lib/LocalWorksets/test/test_api.jl
1bb82e7df70dc97d052b16f3d90c764c7b20642ac81167bbf1b51b1c99b4f8b3  lib/LocalWorksets/test/test_generic.jl
```

Any source/test correction requires fresh hashes.

## Deliberately unclaimed

- B5 durable D2Q9/spring/FEM/z-buffer files and direct/reference benchmarks;
- the complete authoritative root and real-Metal suites for this exact candidate;
- warm allocation, compiler-cache and paired-bootstrap throughput qualification;
- CUDA or ROCm runtime support;
- arbitrary external law execution;
- a frozen Level-1 authoring surface; or
- LW-R2B/LW-R2 clearance.
