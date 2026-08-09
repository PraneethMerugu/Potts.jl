# G5H-R0 current-state and impact freeze

Status: passed on exact R0 candidate

Exact candidate: `6cb6847a2ee408a3920be0c8d2d1dae661c7cb61`

Exact tree: `5b2063924941b53721f588d104d3f7302f721750`

Date: 2026-08-09

Authority:
[Symbolic Potts V1 Native Moving-Field Research and Amendment Gate](../../spec/symbolic-potts-v1-native-moving-field-research.md)

## Purpose and boundary

This record closes only G5H-R0. It freezes the implementation, package resolution, accepted G5H
claims, Merks program, and research-only mutation boundary that G5H-R1 must investigate. It does not
select a native field-input representation, amend a capability row, reopen an implementation gate,
or authorize production work.

The production baseline entering this gate is R2H-C record commit
`185bf8366c36a348792346fe0e20af915f4b70ee`, tree
`8f32abaa2a5923093aef9702baf4e409c2c03352`. The only changes between that checkpoint and this R0
candidate establish Decision 0045, the G5H-R contract and control record, authority/navigation
pointers, and this audit. No file under `src/`, `ext/`, `lib/`, `examples/`, `test/`, `integration/`,
`docs/src/`, `benchmark/`, or any `Project.toml`/`Manifest.toml` is modified.

The exact R0 candidate is commit `6cb6847a2ee408a3920be0c8d2d1dae661c7cb61`, tree
`5b2063924941b53721f588d104d3f7302f721750`. This subsequent record-only binding follows the
existing G5H freeze protocol and makes the candidate a passed checkpoint without changing any
production, package, test, example, or environment file.

## Target machine and resolved environments

The freeze was inspected and reproduced on:

| Property | Frozen value |
|:--|:--|
| Machine | MacBook Pro `MacBookPro18,3` |
| Processor | Apple M1 Pro, 8 cores: 6 performance and 2 efficiency |
| Memory | 16 GB |
| Architecture | `arm64` |
| Operating system | macOS 15.6.1, build `24G90`; Darwin 24.6.0 |
| Julia executable | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia` |
| Julia version | 1.12.1 |

The shell has no unqualified `julia` executable on `PATH`; all evidence commands therefore use the
absolute executable above. Commands use `--compiled-modules=existing` so the R0 reproduction does
not mutate package environments or compiled-cache state.

### CPU MethodOfLines environment

`integration/Manifest.toml` and `docs/Manifest.toml` resolve the same reviewed CPU stack:

| Package | Version |
|:--|:--|
| MethodOfLines | 0.11.19 |
| ModelingToolkit | 11.37.1 |
| ModelingToolkitBase | 1.58.1 |
| OrdinaryDiffEqTsit5 | 2.1.2 |
| SciMLBase | 3.39.1 |
| SymbolicIndexingInterface | 0.3.51 |
| Symbolics | 7.34.1 |
| DomainSets | 0.8.1 |

The docs environment pins these exact versions. Root and integration compat are broader:
MethodOfLines `0.11.12`, ModelingToolkit `11`, ModelingToolkitBase `1.51`, OrdinaryDiffEqTsit5 `2`,
SciMLBase `3`, SymbolicIndexingInterface `0.3`, and Symbolics `7`. G5H-R1 must decide whether a new
public input path works across that declared range or whether compat must narrow; R0 makes no such
claim.

The package keeps ModelingToolkit and MethodOfLines as weak dependencies. The MOL extension loads
only for `MethodOfLines + ModelingToolkit`; base PottsToolkit remains independent of full MTK and
MOL.

### Metal comparison environment

The existing real-device environment contains DiffEqGPU 3.16.0, Metal 1.10.0, ModelingToolkit
11.38.0, SciMLBase 3.41.0, and SymbolicIndexingInterface 0.3.51. It does not contain MethodOfLines
and is not MethodOfLines GPU evidence. The accepted MOL profile remains CPU-only.

## Frozen implementation facts

### MethodOfLines construction and capability

The 126-line `PottsToolkitMethodOfLinesExt` currently:

1. obtains the dependent-variable and coordinate grids through `MethodOfLines.get_discrete`;
2. checks one ordered, scalarized, fixed grid;
3. calls `SciMLBase.symbolic_discretize` while constructing `MethodOfLinesComponent`;
4. creates exactly one `NativeFieldOutput`;
5. wraps the semidiscrete system as one global `ODEComponent`; and
6. admits exact replay only for the pinned CPU Tsit5/MethodOfLines/MTK stack.

The evidence function explicitly requires `isempty(native_inputs(declaration))`. It also excludes
Metal by provenance: the generic checked Metal field row cannot be borrowed by a MOL component.

Conclusion: spatial discretization is already outside the per-MCS runtime path. No existing test or
source path calls `symbolic_discretize` during a coupled step. This does not prove that the candidate
native-input representations can preserve that property; R1 must instrument them.

### Native IO declaration boundary

The current declaration types are intentionally asymmetric:

- `NativeInput` carries one symbolic `Num` or `Arr`, but its Potts endpoint must be `ModelState` or
  `CellState`;
- a global component further restricts every `NativeInput` endpoint to `ModelState`;
- `NativeOutput` is scalar and targets `ModelState` or `CellState` according to scope;
- `NativeFieldOutput` scalarizes a fixed native array and targets `FieldState`; and
- there is no `NativeFieldInput`, occupancy projection declaration, or field-input source policy.

Runtime resolution makes the same boundary executable. `_read_native_endpoint` accepts
`FieldState` only when the port is `NativeFieldOutput` and reports that fields are output-only.
`_native_input_pairs` gathers only `NativeInput`, so no field or occupancy array can reach native
problem construction.

Full-MTK preflight also rejects any retained `Symbolics.Arr` among scheduled unknowns or parameters
and requires every coupling variable to be scalar `Symbolics.Num`. A viable R1 representation must
either remain scalarized or justify and qualify a bounded change to these fixed-dimension checks.

### Structural compilation and numerical continuation

`mtkcompile_native` passes the declared inputs and outputs to upstream
`ModelingToolkitBase.mtkcompile`, retains the returned system, and does not reconstruct its
equations. That structural pass occurs when the enclosing `PottsSystem` is scheduled.

The current numerical continuation is logical-state based, not persistent-integrator based:

1. `NativeLogicalState` stores copied native `u`, `p`, optional `du`, `t`, and retcode;
2. every due global component calls `_native_continuation_problem`;
3. that path constructs a new standard `ODEProblem` or `DAEProblem` over the next interval;
4. `advance_native_component` calls `SciMLBase.init` and `solve!`; and
5. only the resulting logical values are retained for the next MCS.

Thus the current path does not rediscretize the PDE per MCS, but it does rebuild a problem and
solver integrator per due interval. R0 does not label this correct or defective. R1 must compare it
with a persistent-integrator design using call-count, allocation, atomicity, and replay evidence.

### Coupled ordering and atomic publication

The existing `CPMThenComponents` transaction already supplies a useful candidate boundary:

1. CorePotts stages one complete MCS and exposes its staged snapshot and lifecycle receipt;
2. all due native islands read the same staged descriptor snapshot;
3. component states and output updates are accumulated without publication;
4. failures abort component and Core transactions; and
5. after all validation, assignment-only publication commits Core state, component transactions,
   native logical states, and completed MCS.

A moving occupancy input would therefore naturally be derived from the staged post-MCS ownership
snapshot, not the previous published state. This is an observed current ordering fact, not yet an
accepted occupancy projection contract. R1 must prove the exact snapshot, hold interval, and failure
behavior for every candidate representation.

### Checkpoint boundary

The native checkpoint block currently stores system/profile/evidence fingerprints and logical
`u/p/du/t/retcode`; per-cell blocks additionally store capacity, masks, generations, kinds, and
states. It does not store an OrdinaryDiffEq integrator cache. Restore initializes the reviewed
native path and then reconstructs logical state from the checkpoint.

An occupancy mask derived deterministically from the canonical staged Core ownership is not a
second checkpoint authority under the current model. Whether a persistent integrator requires
additional stored state, or can be reconstructed exactly from the existing logical checkpoint,
remains an R1 question.

## Frozen Merks implementation

The executable Merks integration witness is an 8 by 8 closed, serial CPU CPM with:

- one endothelial cell initialized on a 3 by 3 block;
- volume, extension-only chemotaxis, and local connectivity;
- a `FieldState` evolved by `DiscreteFieldEuler`;
- a von Neumann field stencil, two Euler substeps per MCS, duration 1.0;
- diffusion 0.08, secretion 0.02, and decay 0.01; and
- secretion recomputed site-by-site from the staged owner and the compiled endothelial kind.

The Euler operation is an `AfterMCS` site stage, reads the staged site owner/kind, applies
`D*laplacian - decay*center + source`, clamps at zero, and is explicitly CPU-only. This is the
current moving-occupancy behavior that a native MOL replacement must preserve scientifically.

The current product assertions establish successful completion, finite and positive field mass,
observation equality, deterministic ownership, and deterministic final concentration. The
independent field oracle establishes periodic/closed/frozen-border diffusion and exact restart.
Neither the product test nor the output-only MOL test is a controlled moving-source translation and
disappearance oracle. That missing stronger witness belongs to R1, not R0.

## Reproduced current witnesses

All commands ran from the repository root on the machine above.

### Direct Merks execution

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=. --startup-file=no --compiled-modules=existing \
  -e 'include("examples/merks_2006_serial.jl"); result = Merks2006Serial.run_merks_2006(); final = last(result.solution); @assert final.mcs == 2; println((retcode=result.solution.retcode, mcs=final.mcs, occupied=count(!iszero, final.ownership), field_total=sum(final[:concentration])))'
```

Result: success at MCS 2, five occupied sites, field total `0.23800699125`.

### Final Wortel/Merks product suite

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=. --startup-file=no --compiled-modules=existing \
  -e 'using Test, PottsToolkit, SciMLBase; include("test/test_product_programs.jl")'
```

Result: 9/9 passed in 1 minute 20.9 seconds.

### Checked output-only MethodOfLines adapter

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=integration --startup-file=no --compiled-modules=existing \
  -e 'using Test, PottsToolkit, Symbolics; import ModelingToolkit; using ModelingToolkitBase: @named, @parameters, @variables; include("integration/test_method_of_lines_field.jl")'
```

Result: 9/9 passed in 1 minute 21.2 seconds. MethodOfLines emitted its existing warning that systems
with interface boundaries are not transformed. The warning is frozen as an upstream behavior that
R1 must understand; it is not treated as a test failure or silently suppressed.

## Frozen capability and claim boundary

The accepted matrix remains unchanged throughout pre-committee research:

| Path | Frozen disposition |
|:--|:--|
| `DiscreteFieldEuler`, sequential CPU | Replay-qualified only for its tested fixed-grid mechanism conjunction |
| `DiscreteFieldEuler`, GPU | Unsupported; operation transfer declares `gpu=false` |
| Generic checked `NativeFieldOutput`, Metal | Replay-qualified only for its fixed 2D `Float32` evidence row |
| Generic checked `NativeFieldOutput`, sequential CPU | Unsupported without the MOL evidence authority |
| `MethodOfLinesComponent`, sequential CPU | Replay-qualified for one scalarized fixed output grid, `Float64`, fixed-step pinned Tsit5 and exact stack |
| MethodOfLines, Metal/GPU | Unsupported |
| MethodOfLines native inputs, multiple outputs, remeshing, interpolation, events, and unreviewed solver profiles | Unsupported |

G5H-R research cannot be cited to alter these claims. Only a committee-reviewed, owner-accepted
amendment followed by implementation evidence can do so.

## Candidate G5H impact map

R0 identifies possible touch points without deciding that they reopen:

| Authority | Why R1 may affect it | Required R1 disposition |
|:--|:--|:--|
| Native MTK component-island invariant | A new field input changes typed cross-domain IO while MTK must retain PDE/equation ownership | Confirm the smallest public MTK-owned boundary and prohibit equation assimilation |
| Time and coupling invariant | Moving occupancy needs an exact staged snapshot and piecewise-time meaning | Specify snapshot, zero-order hold or alternative, cadence, discontinuity, and publication order |
| Capability profiles | CPU, Metal, solver, scalar, replay, and ensemble conjunctions differ | Produce separate rows and explicit preflight rejections |
| G5H-3 and R2H-B | Generic native IO, problem lifecycle, initialization, checkpoint, and failure behavior may change | Decide whether the architecture gate and review reopen |
| G5H-4 | Fields, MOL, backend profiles, ensembles, and exact evidence are directly affected | Define the new field-input and runtime qualification work |
| G5H-5 and R2H-C | Merks authorship, docs, quantitative comparison, capability text, and final product review may change | Define migration, removal, benchmark, docs, and rereview work |
| G6 handoff | G6 cannot freeze an unresolved field integration spine | Keep G6 blocked through every accepted reopened route |

The potentially affected implementation-matrix rows are H5-B, H5-E, H5-F, H5-G, H5-Q, and
R2H-C. The potentially affected preservation rows are:

- primary: PR13 typed IO, PR14 field solver, PR15 Merks, and PR27 MTK/MOL ownership;
- runtime/replay: PR05 fingerprints, PR09 atomicity, PR10 problem/integrator lifecycle, PR11
  checkpoint, PR12 ensembles, PR17 capability/no fallback, PR23 identities, and PR24 settlement;
- integration/product: PR18 parameter and extension behavior, PR25 package/load-order quality, and
  PR30 scientific witnesses.

The potentially stale capability rows are the sequential global native ODE row if its continuation
lifecycle changes, every field/PDE row, native logical checkpoint/continuation, and ensemble rows if
input-buffer or integrator ownership changes. Existing rows remain valid until an accepted amendment
marks them reopened.

## Frozen content identities

The following SHA-256 values bind the high-risk inputs to R1:

| File | SHA-256 |
|:--|:--|
| `Project.toml` | `e9740402e720a1f4465d39965d4293b538f2762b36b3906efa01dccd2ece4976` |
| `integration/Project.toml` | `24d0fdcdab2f36b1f5ee83a8b4bc19c3ce11494128418758e73598aaf2879fa3` |
| `integration/Manifest.toml` | `5ce1056ffaf160e18db4ffa0edf50d8b06645d106fa3d5e40f70db8f66ea9c6c` |
| `docs/Project.toml` | `d3f03fa0d7772c2ed026bf3a01f727e7d9e672c551c410603b97e0f84d3f9255` |
| `docs/Manifest.toml` | `904545b0856f96ca0a1f3f1d59e298647ee1eacb72f37bb25b077127aea6ac25` |
| `ext/PottsToolkitMethodOfLinesExt.jl` | `8478d21ac0e4b60b3f837d627c77c924c8134bda0b3f22c5359f087bec29a8c4` |
| `ext/PottsToolkitModelingToolkitExt.jl` | `ca05526bd2e1e7369ff212777ce8a48b1543273d4c513b73fe788a890e0de17c` |
| `src/native/declarations.jl` | `7bd09646d6e022c9cba17f30e70d49318fab039a40b3ad150cb42536c803d7fd` |
| `src/native/runtime.jl` | `0907f7ac86da8e0a475fdc9dd34152716ebbe4aab4cfa3f59c55455c7bf55c08` |
| `src/runtime/integrator.jl` | `6a1cb6a21a3268ddb9e2ba172df66cdef67f4ddf49df1add1084cbde30234b4d` |
| `src/operation_library/numerics.jl` | `5e4b0ce63af79bd48d8279e48d2d3d184537f4215e7231c81daf93e9701ff420` |
| `examples/merks_2006_serial.jl` | `bd776574cce475d5d3f9085df979930fc441483cf544f1cbac6a8f81b5f19988` |
| `docs/src/published-models/merks-2006.md` | `328209811dc2942cbdba7c88ccd62aeb1fb3d1836a44610baee4da5ac4c5a7ec` |
| `integration/test_method_of_lines_field.jl` | `a79c8242caf362c0313b9ed11d46f08935d51e9537bf7c077495541965ef0037` |
| `design/hardening/g5h4-capability-matrix.md` | `236e58fa56356366806d48d1fa5200bde022de9e73b6836701d8d4b46d8bd63c` |
| `design/hardening/g5h5-preservation-closure.md` | `14ef07fa960653fc9c6afb30c7e0e3c61585f003e78759981b0aee841c8a2fd6` |

The G5H and G5H-R contract hashes are omitted from this table because the later binding commit must
update this record and its control status without pretending a file can contain its own final hash.
Their identities are covered by the exact candidate tree.

## Research-only mutation boundary

Before R2H-D committee review, G5H-R1 may add or edit only:

- `design/hardening/g5h-r*.md` research, risk, impact, and control records;
- `benchmark/research/g5h-r/**` isolated benchmarks and their dedicated environment;
- `integration/research/g5h-r/**` isolated executable upstream probes and their dedicated
  environment; and
- `scripts/research/g5h-r/**` non-production instrumentation used only by those probes.

The following remain frozen before an accepted amendment:

- `src/**`, `ext/**`, and `lib/**` production code;
- root exports and every root/library `Project.toml` or `Manifest.toml`;
- `examples/**`, `docs/src/**`, `docs/make.jl`, and stable product claims;
- existing root, Core, Makie, integration, backend, and product tests;
- `design/hardening/g5h4-capability-matrix.md` and passed G5H evidence;
- CI/workflow and release surfaces; and
- Merks and Wortel implementations.

An isolated probe must use a distinct module or process, must not be included by a package or the
authoritative test runners, and cannot satisfy a support claim. A probe that requires production
changes stops R1 and reports that requirement to the committee; it does not cross the boundary.

## R0 exit checklist

| Obligation | Result |
|:--|:--|
| Exact predecessor and production boundary frozen | Complete |
| Current MOL adapter and evidence row audited | Complete |
| Native declaration, preflight, continuation, transaction, and checkpoint paths audited | Complete |
| Current Merks mechanism and witnesses audited | Complete |
| CPU and Metal environments identified without conflating their claims | Complete |
| G5H clause, capability, preservation, implementation, and review impact map recorded | Complete |
| Research-only mutation boundary recorded | Complete |
| Current Merks, product, and MOL witnesses reproduced | Complete |
| Production/public/capability behavior changed | No |
| Exact candidate commit and tree bound | Complete: `6cb6847a2ee408a3920be0c8d2d1dae661c7cb61` / `5b2063924941b53721f588d104d3f7302f721750` |

R0 passes because the exact candidate is committed, the binding values are recorded, static
integrity checks pass on that candidate, and the living control record opens G5H-R1. No R1
technical conclusion is required or implied by R0 passage.

## Exact-candidate integrity closure

The exact candidate passed:

- `git diff --check`;
- an empty production/path diff from the R2H-C predecessor across `src`, `ext`, `lib`, `examples`,
  `test`, `integration`, `docs/src`, `benchmark`, and root package/environment files;
- all 16 frozen SHA-256 identities above;
- local-link resolution for all 231 Markdown files visible to Git;
- parse of all 150 tracked TOML files; and
- the three reproduced current-behavior witnesses recorded above.

These checks qualify the R0 freeze only. They do not qualify a candidate native field input.
