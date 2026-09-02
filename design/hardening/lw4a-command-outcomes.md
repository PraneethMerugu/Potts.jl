# LW-4A Exact Command Outcomes

Date: 2026-08-10

Candidate: post-remediation standalone `LocalWorksets` extraction cleared by fresh LW-R2A review.
Every command below ran after the complete admission, shared-failure-scope,
device-fingerprint, Core-evidence-authority, and concrete hot-path remediations.

## Qualified environment

- Julia 1.12.6, LLVM 18.1.7, macOS arm64 Darwin 24, Apple M1 Pro;
- KernelAbstractions 0.9.42, Adapt 4.7.0, Atomix 1.1.3;
- Metal 1.10.0 on the real Apple GPU with scalar indexing disabled;
- root test sandbox re-resolved compatible ModelingToolkit 11.38.2,
  ModelingToolkitBase 1.62.0, SciMLBase 3.44.0,
  SymbolicIndexingInterface 0.3.53, and Symbolics 7.36.0.

## Standalone package

Command:

```sh
julia --project=lib/LocalWorksets -e 'using Pkg; Pkg.test()'
```

Exit: 0. `LocalWorksets tests passed`.

| Test summary | Pass/total |
|---|---:|
| package quality and explicit ambiguity check | 11/11 |
| exact internal-first API | 20/20 |
| direct/do-block declarations and declaration rejection | 19/19 |
| typed slot bounds, storage templates and closed resolved profiles | 11/11 |
| non-CPM deterministic z-buffer | 111/111 |
| bounded two-key conjunctive resolution | 33/33 |
| rank sentinel, empty, mask, active selection | 9/9 |
| logical bindings and real workspace | 11/11 |
| submission storage slots | 3/3 |
| ordered stages and implicit visibility | 16/16 |
| rejection, freshness, capacity, task ownership | 25/25 |
| generated submission rejection remains prelaunch | 25/25 |
| synchronous shared-scope CPU failure | 10/10 |
| generic-substrate/full-source portability boundary | 29/29 |
| lifecycle/provider/kernel/execution/submission/binding/topology piracy rejection | 7/7 |
| capability piracy rejection | 2/2 |
| compiler-evidence piracy rejection | 1/1 |
| lowering-evidence piracy rejection | 1/1 |
| no replaceable admission wrapper | 4/4 |
| exact cached-execution replacement rejection | 5/5 |
| exact central-admission replacement rejection | 2/2 |
| **Total** | **355/355** |

The final hostile test intentionally emits Julia's method-overwrite warning after proving that the
exact central method is now owned by `Main`; `plan` then rejects before lowering or launch.

## CPU direct/candidate parity

Command:

```sh
julia --project=. benchmark/src/lw3_localworksets_parity.jl
```

Exit: 0.

| Fact | Result |
|---|---:|
| geometry | 128 x 128 |
| warm/measured batches | 10 / 50 |
| MCS per batch | 10 |
| paired bootstrap samples | 10,000 |
| direct median | 0.0256941670 s |
| candidate median | 0.0259340415 s |
| median ratio | 1.0093357570 |
| paired bootstrap upper 95% | 1.0123282545 <= 1.05 |
| direct median allocation | 1,318,176 bytes |
| candidate median allocation | 1,303,296 bytes |
| allocation delta | -14,880 bytes |
| direct/candidate settlements | 60 / 60 |
| LocalWorksets waits | 60 |
| submitted/drained claims | 600 / 600 |
| claim launches | 4 per color |
| topology transfer | 0 bytes |
| lease capacity | 12 |
| poison | false |
| final ownership checksum | 3,507,575 |

Final state, receipt, counter and tracker parity were exact.

## Complete CorePotts CPU suite

Command:

```sh
julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'
```

Exit: 0. `CorePotts tests passed`.

| Test summary | Pass/total |
|---|---:|
| narrow API and explicit SPIs | 13/13 |
| Philox answers/address isolation | 5/5 |
| independent scientific oracle | 109/109 |
| undeclared extinction rejection | 5/5 |
| attempt-budget identity | 4/4 |
| unbiased checkerboard colors | 16,389/16,389 |
| sequential/checkerboard units | 7/7 |
| lifecycle receipts | 18/18 |
| explicit program-step commit | 34/34 |
| descriptor-state atomicity | 23/23 |
| failure restoration | 14/14 |
| LocalWorksets queued CPU vertical | 55/55 |
| LocalWorksets evidence remains conjunctive with Core authority | 7/7 |
| whole-MCS lease prelaunch | 6/6 |
| scientific failure commit cut | 18/18 |
| provider poison mapping | 6/6 |
| trusted public run/wait adapter | 7/7 |
| cell moments | 10/10 |
| owned mutable inputs | 21/21 |
| bounded checkpoint histories | 3/3 |
| after-MCS transaction | 7/7 |
| compiled-program interface | 71/71 |
| evaluate before arbitration | 1/1 |
| inferred runtime barriers | 5/5 |
| external trackers | 29/29 |
| relationship transactions | 56/56 |
| settled host relationships | 31/31 |
| checkpoint continuation | 26/26 |
| initialization RNG address | 5/5 |
| external descriptor operation | 7/7 |
| storage-layout canonicalization | 13/13 |
| relationship specialization bound | 11/11 |
| surface ownership oracle | 40/40 |
| global energy oracles | 13/13 |
| incident-local lookup | 8/8 |
| descriptor-state backend SPI | 14/14 |
| shared acceptance law | 23/23 |
| acceptance/failure atomicity | 24/24 |
| capability profiles | 113/113 |
| checkpoint environment identity | 16/16 |
| external support cannot mint evidence | 11/11 |
| adaptation is not device evidence | 10/10 |
| CPU evidence/preflight | 27/27 |
| mechanism-key evidence | 6/6 |
| adapted-workspace preflight | 11/11 |
| lifecycle receipt generations | 28/28 |
| real Core receipt variants | 30/30 |
| bulk component receipts | 38/38 |
| component group prevalidation | 24/24 |
| package quality | 10/10 |
| **Total** | **17,462/17,462** |

The 55-assertion LocalWorksets vertical includes exact direct/candidate checkpoint continuation,
both cross-lowering restore rejections, and RNG-evidence mismatch rejection. The separate seven
authority assertions prove an unsupported direct base cannot mint candidate execution or replay
evidence.

## Authoritative PottsToolkit suite

Command:

```sh
julia --project=. -e 'using Pkg; Pkg.test("PottsToolkit")'
```

Exit: 0. `PottsToolkit tests passed`.

The sandbox reported `Test Successfully re-resolved`, then ran the authoritative closure through
public API, system contract, traversal/completion, units, `mtkcompile`, remake, runtime/SII,
native authoring and pools, SciML/public lifecycle, relationship transactions, external compiler
and scientific-operation SPIs, scientific witnesses, product programs, fresh-process boundaries,
Core SPI and package quality.

Final summary: `G5H-1 through G5H-3 authoritative package surface` **2,198/2,198** in 18m35.9s.

## Qualified real-Metal runner

Command:

```sh
julia --project=benchmark/backends/metal benchmark/backends/metal/runtests.jl
```

Exit: 0.

Key complete-run summaries and facts:

- fresh-process Metal extension orders: 2/2;
- G5H-4 real Metal native components: 37/37;
- generic LocalWorksets resolved lowering: four launches, 32 workspace bytes, 40 topology-transfer
  bytes and lease capacity 12;
- ordered sequence: eight launches with KernelAbstractions implicit order;
- same-schema compiler cache entries: 324 before and 324 after;
- backend `KernelException` observed at wait; isolated preparation poisoned;
- shared backend/device/owner-task failure witness: both preparations observed `KernelException`,
  both were poisoned, and neither claimed a selectively drained prefix;
- Core vertical: 12 submitted/committed MCS, 12 claim submissions, one synchronization;
- scientific failure: zero commit and no poison; provider failure: Core lifecycle failure and poison;
- unreviewed external Metal, relationship, surface and lifecycle mechanisms all rejected;
- cross-shape/workgroup native conformance, step/solve/resume, lifecycle, relationship, component,
  RNG and scientific failure witnesses completed before parity.

Fixed Metal parity:

| Fact | Result |
|---|---:|
| geometry | 128 x 128 |
| warm/measured batches | 10 / 50 |
| MCS per batch | 10 |
| paired bootstrap samples | 10,000 |
| direct median | 0.1107828535 s |
| candidate median | 0.1109990625 s |
| median ratio | 1.0019516468 |
| paired bootstrap upper 95% | 1.0052174352 <= 1.05 |
| direct median allocation | 17,678,968 bytes |
| candidate median allocation | 17,149,648 bytes |
| allocation delta | -529,320 bytes |
| direct/candidate settlements | 60 / 60 |
| LocalWorksets waits | 60 |
| submitted/drained claims | 600 / 600 |
| claim launches | 4 per color |
| topology transfer | 0 bytes |
| lease capacity | 12 |
| poison | false |
| final ownership checksum | 3,507,575 |

Final device state and lifecycle facts matched the direct oracle exactly.

## Static and isolated checks

The isolated `--startup-file=no --project=lib/LocalWorksets` process reported:

```text
Julia 1.12.6; macOS arm64 Darwin 24; 8 x Apple M1 Pro; LLVM 18.1.7; 1 Julia thread
forbidden_loaded = []
public = LocalWorksets plus the exact fourteen accepted public names
exports = [:LocalWorksets]
```

The final package-boundary script exited 0 and reported:

```text
source_files = 10
nonblank_noncomment = 4137
maximum_file_lines = 952
synchronize_file = lib/LocalWorksets/src/execution/localworksets_kernelabstractions.jl
forbidden_execution_hits = []
stale_nested_sources = []
runtime_dependencies = [Adapt, Atomix, KernelAbstractions, SHA]
```

Local-source resolution was explicit in every active environment:

- root: `lib/CorePotts`, `lib/LocalWorksets`;
- CorePotts: `../LocalWorksets`;
- Metal: `../../../lib/CorePotts`, `../../../lib/LocalWorksets`.

Final `git diff --check` exit: 0, with no output.

## Command records and retained transcripts

The post-remediation candidate's exact exit status and material result facts are preserved in:

- `lw4a-logs/standalone-remediated.txt`;
- `lw4a-logs/cpu-parity-remediated.txt`;
- `lw4a-logs/corepotts-remediated.txt`;
- `lw4a-logs/root-remediated.txt`;
- `lw4a-logs/metal-remediated.txt`; and
- `lw4a-logs/static-remediated.txt`.

The earlier full qualification transcripts remain as audit history, but do not substitute for the
post-remediation command records or hashes:

- `lw4a-logs/standalone-qualified.txt`;
- `lw4a-logs/cpu-parity-qualified.txt`;
- `lw4a-logs/corepotts-qualified.txt`;
- `lw4a-logs/root-qualified.txt`;
- `lw4a-logs/metal-qualified.txt`; and
- `lw4a-logs/static-qualified.txt`.

Earlier failed transcripts also remain in the same directory and are not cited as passing evidence.
