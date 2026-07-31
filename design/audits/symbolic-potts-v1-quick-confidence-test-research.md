# Symbolic Potts V1 Quick Confidence-Test Research

Date: 2026-07-30

Status: owner-accepted research disposition; normative requirements are consolidated into
CCV1-024 through CCV1-026; does not authorize production implementation or expand V1
paper-reproduction scope

## Owner disposition

On 2026-07-30, the owner accepted the recommendations in this report with the direction: “add
them.”

Acceptance means:

- the blocking test families are normative through CCV1-024 and CCV1-026;
- the three bounded proof-model statistical dispositions are normative through CCV1-025;
- the scheduled and explicitly rejected categories remain outside ordinary blocking CI;
- the tests use normal Julia `Test` entry points and the shared backend-agnostic GPU harness; and
- this acceptance changes test authority only. It is not the implementation send-off required by
  the compiler-construction contract.

## Question

Are there additional tests that would materially increase confidence in Symbolic Potts V1 without
recreating the expensive evidence system, adding flaky statistical gates, or turning ordinary
package CI into a performance laboratory?

## Executive answer

Yes.

The strongest remaining additions are not longer simulations. They are exact finite-state,
metamorphic, stage-trace, and backend-conformance microfixtures. They target seams where the
current tests and CCV1-024 through CCV1-026 remain broad:

- the entire finite transition matrix rather than one sampled outcome vector;
- acceptance and rejection boundary behavior;
- rollback of every state family after a null or rejected proposal;
- algebraic invariance through normalization, grouping, and lowering;
- bounded-access and launch-boundary behavior;
- exact RNG addressing;
- proof-model-specific masks, neighborhoods, stage order, and lifecycle rules; and
- fresh-process package and extension behavior.

Most of the recommended CPU tests should take milliseconds individually. Fresh-process and GPU
witness tests are still small, but will cost seconds or job startup time. No recommendation depends
on renewing evidence, comparing against the removed engine, maintaining a vendor-specific duplicate
suite, or running a large Monte Carlo campaign.

The restrained recommendation is:

1. add the twelve blocking test families in this report;
2. select at most one primary short statistical endpoint for each proof model, as already required
   by CCV1-025;
3. keep PDE convergence, equilibrium calibration, compiler profiling, and multi-vendor execution
   scheduled or release-level; and
4. explicitly reject tests that claim equilibrium, isotropy, trajectory equivalence, or monotonic
   relaxation where the model does not guarantee them.

## Research method

Three independent tracks were audited:

1. universal CPM transition, geometry, field, and statistical invariants;
2. Wortel activity, Merks elongation/chemotaxis, and focal-point-plasticity semantics; and
3. Julia/SciML compiler, KernelAbstractions, AcceleratedKernels, adaptation, extension, and package
   quality practices.

The findings were then compared with:

- the current 26-clause compiler construction contract;
- the current CorePotts V1 tests;
- the current visible Wortel, Merks, and focal fixtures; and
- focused tests from the previous engine available on `main`.

The previous engine supplied test intent only. It is not proposed as an oracle.

## Existing coverage and the real gaps

The current contract is already strong. CCV1-024 requires compiler-layer verification,
independent energy/tracker checks, external extensibility, targeted inference, allocation and
device checks, and specialization-growth inspection. CCV1-025 governs reproducible statistical
experiments and prevents statistical checks from substituting for exact semantics. CCV1-026
requires analytic transition, geometry, field, chemotaxis, activity, elongation, and relationship
conformance.

The current executable tests are earlier and narrower:

- Core tests cover replay, replica divergence, lifecycle retirement, checkpoint continuation,
  bounded histories, a broad allocation ceiling, and relationship transaction atomicity.
- The Wortel fixture covers replay, divergence, activity bounds, history, observation, and symbolic
  indexing, but not the paper's exact Act neighborhood reduction or accepted-copy stage order.
- The Merks fixture covers replay, divergence, basic field production, finiteness, and stencil
  cardinality, but not masked secretion/decay balance, local-connectivity cases, analytic
  elongation, or chemotaxis sign.
- The focal fixture covers replay, divergence, some transaction conflicts, stale generations, and
  checkpoint continuation, but not activation-path semantics, spring deltas, threshold equality,
  per-endpoint removal order, or periodic geometry.
- Aqua and ExplicitImports already run for PottsToolkit. They should be retained, not reinvented.

The additions below therefore sharpen accepted requirements. They do not establish a new testing
program.

## Recommended blocking test families

| Rank | Test family | Confidence | Cost | Flake risk | Increment over CCV1 |
|---:|---|---|---|---|---|
| 1 | Complete deterministic micro-transition matrix | Very high | Tiny | None | Strengthens one sampled row into all finite states |
| 2 | Rejection/no-op atomicity and acceptance seams | Very high | Tiny | None | Makes proposal failure behavior exact |
| 3 | Compiler algebra and structural repeatability | Very high | Tiny | None | Adds end-to-end metamorphisms |
| 4 | Proof-model exact stage and truth tables | Very high | Tiny | None | Pins paper/source semantics |
| 5 | RNG address and raw-word conformance | Very high | Tiny | None | Pins parallel stochastic identity |
| 6 | Bounded-access sentinels | Very high | Tiny | None | Proves locality without timing |
| 7 | Kernel boundary and workgroup shapes | Very high | Small | Low | Exercises tail/barrier/index seams |
| 8 | Checkerboard commit commutativity | Very high | Tiny | None | Pins deterministic concurrent mutation |
| 9 | Exact field modes, masks, and budgets | Very high | Tiny | None | Strengthens generic diffusion checks |
| 10 | Geometry, lattice, and tracker enumeration | High | Tiny–small | None | Pins discrete rather than continuum geometry |
| 11 | Adapt and CPU/GPU differential microprograms | Very high | Small | Low | Proves the device boundary and no fallback |
| 12 | Fresh-process load and extension conformance | High | Small | Low | Proves ordinary Julia package behavior |

These are families, not twelve new frameworks. They should share small public-path fixtures and
independent calculation helpers.

### 1. Complete deterministic micro-transition matrix

Enumerate every admitted state of a two- to four-site fixture. Independently construct every row of
the transition matrix `P`, including actionable copies, null attempts, boundary attempts,
proposal multiplicities, constraint rejection, and acceptance.

Assert:

- every entry is nonnegative;
- every row sums to one;
- forbidden transitions have zero probability;
- null mass is correct;
- the compiled one-step executor agrees with every row; and
- independently enumerated two-step probabilities agree with `P * P`.

Before this consolidation, CCV1-026 required a complete empirical outcome vector from one finite
fixture. Full row enumeration catches state-dependent reverse multiplicities and constraint
behavior with less sampling and no flake risk.

On a separate explicitly proven reversible fixture, compute
`π(x) ∝ exp(-H(x) / T)` and assert `πP = π` and pairwise flux equality. This must remain opt-in:
common modified CPM dynamics need not satisfy detailed balance.

### 2. Rejection/no-op atomicity and acceptance seams

Inject deterministic uniform values immediately below, equal to, and immediately above the
declared acceptance threshold. Include probability zero, probability one, favorable, neutral,
unfavorable, zero-temperature, underflow, and proposal-ratio cases.

For same-owner attempts, boundary nulls, energy rejection, failed constraints, and losing
checkerboard conflicts, assert exact pre/post equality for:

- lattice ownership;
- all trackers and auxiliary state;
- relationship payloads and generations;
- request and workspace logical contents;
- lifecycle state; and
- observations.

RNG consumption must be checked separately against the declared semantic-address policy. A rejected
attempt may consume an assigned draw while still being scientifically atomic.

### 3. Compiler algebra and structural repeatability

Through the public completion and compile paths, assert:

- normalization and completion are idempotent;
- alpha-renaming and legal namespacing preserve qualified semantics;
- permutations preserve results only for statements whose semantics are unordered;
- compiling the same completed model twice produces the same public structural plan;
- permuting RNG-free Hamiltonian term declarations preserves total energy, every local delta, and
  transition probabilities under the numerical policy;
- inserting a zero term changes no scientific result;
- splitting one term into algebraically equivalent contributions changes no scientific result; and
- regrouping repeated occurrences leaves them as data with the same evaluator-group identities.

At occurrence counts `1`, `32`, and `1024` with fixed group structure `G`, the compiler-owned report
should retain the same `G`, evaluator signatures, descriptor groups, and kernel families. This is
stronger and more stable than counting Julia `MethodInstance`s or snapshotting generated code.

### 4. Proof-model exact stage and truth tables

#### Wortel

- Evaluate the exact same-cell Moore-neighborhood geometric mean for hand-built source/target
  neighborhoods, including foreign-cell pixels, zeros, unequal counts, and a periodic seam.
- Force a sequence of accepted extensions, accepted retractions, rejected attempts, same-owner
  attempts, and one end-of-MCS decay. Verify which site is activated or cleared, write visibility,
  one decay per positive value, and flooring at zero after every stage.

These tests pin equations 7–8 and the activity lifecycle without requiring a trajectory.

#### Merks

- On a mixed endothelial/ECM mask, verify the exact one-substep mass balance
  `ΔΣc = Δt(α Ncell_sites - ε Σ_ECM c)`, plus sitewise secretion and decay masks.
- Transcribe the complete local-connectivity truth table from the paper, including its documented
  conservative false rejection.
- Verify inertia moments, largest-eigenvalue length, translation/rotation/reflection covariance,
  target energy, and exact add/remove delta for small analytic shapes.
- Verify exact chemotaxis sign, magnitude, extension predicate, constant-offset invariance, and
  linearity in strength for the declared linear response.

#### Focal-point plasticity

- Exercise the proposal/accepted-copy truth table for medium, self, same-cluster,
  unsupported-kind, existing-link, degree/capacity, rejected, and accepted cases.
- Prove activation energy is present at proposal time, activation does not double-count the
  ordinary spring path, and only acceptance creates one canonical link with the declared payload.
- Pin lifecycle boundaries: equality at maximum persists, greater-than maximum breaks, extinction
  removes incident links, and at most the declared number of links is removed per affected
  endpoint in the declared order.
- Translate a linked pair across a periodic seam and reverse endpoint order. Energy, local delta,
  and break behavior must agree with an independent unwrapped calculation.
- Keep Wang-specific retuning cadence and visibility in an explicitly Wang-qualified fixture,
  rather than defining it as universal focal semantics.

### 5. RNG address and raw-word conformance

Freeze a small set of raw integer known-answer vectors for the package-owned counter RNG. Exhaust a
small domain of `(seed, replica, sweep, color, site, draw-slot, term)` and assert:

- semantic addresses are unique where the contract requires unique draws;
- address-to-word mapping is unchanged by evaluation order and legal workgroup size;
- checkpoint continuation yields the uninterrupted raw words; and
- converting words to floating values is tested separately from the generator.

Do not test Julia's default RNG stream, run BigCrush in package CI, or maintain a different RNG
battery per GPU vendor.

### 6. Bounded-access sentinels

Use counting array/index wrappers on the CPU reference path. A local proposal delta must perform the
same bounded number of reads on a small and a large lattice. Relationship work must scale with
incident degree rather than total relationship count. Tracker updates must not scan the whole
lattice.

This is a deterministic architectural performance test. It catches accidental `O(lattice)` or
`O(edges)` work without wall-clock thresholds, dedicated hardware, or benchmark baselines.

### 7. Kernel boundary and workgroup shapes

For every kernel family, run logical sizes `1`, `W-1`, `W`, `W+1`, another nonmultiple of `W`, and
a rectangular multidimensional domain. Vary admitted workgroup sizes.

Run the suite on the KernelAbstractions CPU backend in ordinary CI and through the same injected
backend harness on the V1 functional GPU witness. Always synchronize before observing results.

This targets tail masks, linear/cartesian index conversions, boundary guards, workgroup barriers,
and illegal assumptions about launch geometry.

### 8. Checkerboard commit commutativity

Construct a set of accepted proposals with disjoint declared footprints. Every permutation within
one color must yield exactly the same:

- committed lattice;
- tracker state;
- relationship state;
- request ordering after canonicalization; and
- observations.

Add a conflicting pair with an independently calculated deterministic winner. This directly tests
the relationship/footprint language used to make concurrent mutation deterministic.

### 9. Exact field modes, masks, and budgets

On a periodic grid, initialize an exact discrete Fourier mode. Verify the selected Laplacian's
one-step amplification factor and its multi-step power. Also verify:

- the declared stable-step condition;
- positivity or the maximum principle where the scheme guarantees it;
- exact source/sink/boundary mass accounting; and
- the Merks mixed-mask balance described above.

The discrete propagator is the authority. An early-time continuum Gaussian is not.

### 10. Geometry, lattice, and tracker enumeration

Enumerate connected polyominoes up to a small fixed area. Independently calculate:

- bond/contact counts for every admitted lattice-symmetry orientation and periodic seam;
- volume, boundary, centroid, moments, and elongation;
- total energy and every add/remove local delta; and
- the exact connectivity decision for every candidate add/remove.

This produces an explicit lattice-anisotropy fingerprint. It must not assert arbitrary-angle
continuum isotropy on a square lattice.

For `H_V = λ(V - V*)²`, also assert exact add/remove deltas and second finite difference `2λ`. On a
passive zero-temperature fixture, every accepted move must have nonincreasing total energy and the
sum of component deltas must match independently recomputed global energy.

### 11. Adapt and CPU/GPU differential microprograms

Use a synthetic CPU adaptor to replace every storage leaf while preserving wrapper and descriptor
structure. In the functional GPU witness, perform host-to-device-to-host adaptation and launch
every generated kernel family, including rare branches and the external downstream descriptor.

For deterministic, conflict-free microprograms, compare CPU and GPU:

- discrete state;
- raw RNG words;
- accepted proposal identities;
- request ordering; and
- tracker values.

Floating energies and fields follow the declared replay/tolerance class. Repeat with more than one
legal workgroup size. The harness must make scalar indexing or host fallback fail rather than
silently pass.

### 12. Fresh-process load and extension conformance

In isolated processes:

- precompile and load the base package without a vendor backend;
- load optional dependencies before and after PottsToolkit;
- activate the ModelingToolkit and selected backend extension;
- compile two independent external term types in one model; and
- verify the downstream extension path does not edit CorePotts.

Retain Aqua and ExplicitImports in ordinary package CI. Assert stable diagnostic codes and source
provenance for a compact invalid-fixture matrix, not full error-message snapshots.

## Short statistical decisions

CCV1-025 already limits V1 to one primary nondegenerate statistic per proof model. This research
does not justify multiplying that count.

The best candidate refinements are:

| Model | Recommended primary or secondary endpoint | Disposition |
|---|---|---|
| Wortel | Independently calibrated speed–persistence contrast; activity-strength speed ordering only as a secondary endpoint | Keep existing primary direction |
| Merks | Short-lag major/minor displacement-variance ratio for an elongated cell versus matched round ablation | Strong candidate for the primary blocking statistic |
| Focal | Eligible-candidate exchangeability on a symmetric finite fixture | Strong candidate for the primary transition-level statistic |

The Merks anisotropy endpoint is closer to the paper's reported mechanism than a reduced network
branch-count test. The focal exchangeability endpoint detects enumeration-order bias and has a
finite symmetric expectation. Both still require independent calibration and detection-power
demonstration under CCV1-025.

Do not add a second blocking Wortel campaign merely because speed is easy to observe. The exact Act
tests plus the already accepted speed–persistence endpoint are sufficient for V1.

## Scheduled or release-level checks

The following are useful but should not block ordinary pull requests:

- manufactured heat-equation boundary solutions and a three-grid convergence-order check;
- equilibrium droplet means/variances on a separately proven reversible model;
- full Wortel speed–persistence curves;
- Merks network morphology, lacuna, branch, and remodeling distributions;
- focal stationary link-length distributions without an independently proven stationary law;
- package-wide JET analysis;
- SnoopCompile invalidation and reinference trends;
- targeted AllocCheck qualification;
- compile latency, trace-compile volume, native/device code size, GPU registers/occupancy, and
  end-to-end throughput; and
- the shared backend-agnostic GPU suite across the later CUDA/AMDGPU/Metal release matrix.

These checks may diagnose or qualify a release. They must not create freshness ledgers or absolute
wall-clock PR gates.

## Tests to reject explicitly

The following would reduce trust by asserting the wrong science or by adding brittle authority:

- general detailed balance or Boltzmann equilibrium for active, constrained,
  relationship-mutating, or checkerboard CPMs;
- sequential/checkerboard trajectory or distribution equality without a separately proven
  equivalence;
- arbitrary-angle rotational isotropy on a discrete square lattice;
- universal linear mean-squared displacement for an unbiased cell;
- short-horizon monotonic volume/perimeter improvement at finite temperature;
- continuum Gaussian equality for an early discrete diffusion step;
- universal linear chemotactic response outside a declared linear unsaturated law;
- heat-capacity or fluctuation-response identities without reversibility and equilibration;
- bitwise floating reduction equality across backends unless the numerical policy guarantees it;
- whole-IR, LLVM, or native-code snapshots;
- exact internal method-instance counts;
- mandatory package-wide JET;
- duplicated vendor-specific scientific tests;
- per-backend RNG batteries; and
- hard PR timing thresholds.

## Primary and official research basis

### Scientific semantics

- [Wortel et al., *Local actin dynamics couple speed and persistence in a cellular Potts model of
  cell migration*](https://pmc.ncbi.nlm.nih.gov/articles/PMC8390880/)
- [Wortel source archive, v1.0.0](https://doi.org/10.5281/zenodo.4738810)
- [Merks et al., *Cell elongation is key to in silico replication of in vitro vasculogenesis and
  subsequent remodeling*](https://pmc.ncbi.nlm.nih.gov/articles/PMC2562951/)
- [CompuCell3D 4.2.5 focal-point-plasticity source](https://github.com/CompuCell3D/CompuCell3D/tree/4.2.5/CompuCell3D/core/CompuCell3D/plugins/FocalPointPlasticity)
- [CompuCell3D focal-point-plasticity manual](https://compucell3dreferencemanual.readthedocs.io/en/4.9.0/focal_point_plasticity.html)
- [Wang et al. focal-point-plasticity model](https://doi.org/10.1016/j.bpj.2025.04.010)
- [Wang source archive](https://doi.org/10.5281/zenodo.14928214)
- [Durand and Guesnet, detailed-balance analysis of common CPM algorithms](https://arxiv.org/abs/1609.03832)
- [Chen et al., parallel CPM conflicts and checkerboarding](https://doi.org/10.1016/j.cpc.2010.12.011)

### Julia, SciML, and GPU engineering

- [Julia `Test.@inferred`](https://docs.julialang.org/en/v1/stdlib/Test/#Test.@inferred)
- [Julia performance guidance](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [Julia RNG reproducibility](https://docs.julialang.org/en/v1/stdlib/Random/#Reproducibility)
- [KernelAbstractions quick start](https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/)
- [AcceleratedKernels](https://juliagpu.github.io/AcceleratedKernels.jl/stable/)
- [Adapt](https://github.com/JuliaGPU/Adapt.jl)
- [CUDA kernel requirements](https://cuda.juliagpu.org/stable/development/kernel/)
- [SciMLStyle](https://docs.sciml.ai/SciMLStyle/)
- [Julia package extensions](https://pkgdocs.julialang.org/dev/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions))
- [Aqua](https://juliatesting.github.io/Aqua.jl/stable/)
- [ExplicitImports](https://github.com/JuliaTesting/ExplicitImports.jl)

## Consolidation disposition

No new top-level specification subsystem is needed.

The accepted consolidation made only focused edits:

1. CCV1-024 now includes compiler metamorphisms, access-count sentinels, RNG known answers, kernel
   boundary shapes, adaptation, and fresh-process load tests;
2. CCV1-026 now includes the exact Wortel, Merks, focal, field-mode, and finite-state microfixtures;
3. CCV1-025 selects the Merks anisotropy and focal exchangeability endpoints, subject to
   independent calibration; and
4. CCV1-024 through CCV1-026 record the scheduled and rejected categories so they cannot quietly
   become ordinary CI obligations.

That would increase V1 confidence substantially while keeping the repository recognizably standard:
ordinary `Test` files, normal `Pkg.test`, one backend-agnostic GPU contract, a small functional GPU
witness, and no evidence bureaucracy.
