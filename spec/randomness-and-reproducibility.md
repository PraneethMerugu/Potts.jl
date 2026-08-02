# Randomness and Reproducibility

Status: Accepted, except where explicitly marked Provisional or Under Investigation

## Purpose

Randomness is part of the scientific model. This document defines ownership of stochastic state,
the identity of random draws, isolation among stochastic mechanisms, reproducibility claims,
distribution requirements, ensemble behavior, and continuation requirements.

An implementation MAY reorganize kernels, workgroups, command queues, storage, or other execution
details. Such changes MUST NOT change a random draw whose complete semantic address is unchanged.

## Master Seed

Every problem MUST have one realized master seed. The master seed controls both stochastic
initialization and stochastic simulation behavior.

- A user-supplied seed MUST deterministically select the same semantic random stream under the same
  RNG contract version.
- When the seed is omitted, the canonical `PottsProblem` constructor uses `UInt64(0)`. Construction
  is therefore deterministic by default and never consults ambient entropy.
- A user who wants operating-system entropy MUST request it explicitly through a typed seed source
  or supply a realized seed. Such a source is sampled exactly once during problem construction; the
  resulting `UInt64` is stored in the problem and reported in solution provenance.
- PottsToolkit and CorePotts MUST NOT use Julia's default or task-local RNG for model randomness.
- Ordinary single-trajectory `init` and `solve` MUST NOT override the problem seed. A different
  trajectory uses `remake(prob; seed = ...)`; ensemble master-seed selection follows the ensemble
  contract below.
- `remake` SHOULD support replacing the master seed without requiring reconstruction of unrelated
  model semantics.

Arbitrary stateful `AbstractRNG` values MAY be used by explicitly host-side user workflows. They MUST
NOT define device dynamics or imply scheduling-independent, cross-backend, or exact-continuation
guarantees.

## RNG Contract Version

The mapping from a semantic address to random bits MUST have a public version identifier. The
identifier covers:

- The counter-based generator and its round count
- Key derivation and counter packing
- Stream identifiers
- Integer-to-float conversions
- Distribution transformations
- Rejection and retry behavior

Any change that can alter generated values for an existing address MUST introduce a new RNG contract
version. Implementations SHOULD retain selectable historical versions needed to reproduce published
work. A package version alone is not an adequate RNG version.

`Philox4x32x10V1` is the accepted default RNG contract. Its Philox4x32-10 primitive, Potts semantic
address packing, and version `1.0.0` have known-answer and raw-word qualification on CPU, Metal, and
ROCm. Later changes that alter any mapped word require a new RNG contract version.

## Counter-Based Addressing

Model randomness MUST be counter based. A draw is conceptually a pure function of:

```text
(master seed, RNG version, stream, MCS, semantic subround,
 entity identity, operation identity, invocation, draw index)
```

The concrete key and counter packing is an implementation contract belonging to the RNG version.
It MUST prevent two valid built-in semantic addresses from intentionally mapping to the same
generator input.

The following MUST NOT determine a random value:

- Host task or thread identity
- GPU thread, lane, warp, workgroup, or compute-unit identity
- Kernel launch ordering
- Atomic arrival ordering
- Command-queue scheduling
- Storage address
- Backend-specific occupancy decisions

Internal rounds or subrounds MAY appear in an address only when they are scientifically defined by a
named algorithm. Kernel launches alone never define a random subround.

## Entity and Operation Identity

A site-addressed draw MUST use the canonical logical site index or coordinate defined by the topology
contract.

A cell-addressed draw MUST use both the visible cell ID and the internal slot generation. Reusing a
retired ID MUST NOT reuse the former cell's random identity.

A model-domain lifecycle draw before destination allocation MUST use the qualified lifecycle rule,
bounded occurrence identity, MCS, policy, and lexical draw identity. A destination-initialization
draw MUST occur only for a surviving allocated request and MUST additionally include destination
cell ID/generation and descendant role. Cell and model-lifecycle identities are distinct semantic
entity kinds; they MUST NOT be encoded as disguised site identities.

Compiled events, rules, properties, penalties, and other stochastic components MUST receive stable
operation identities within the compiled model. Their mapping MUST be represented in the model
fingerprint or provenance.

Each lexical random expression in a compiled rule MUST receive a distinct draw identity. For example,
two `rand()` expressions evaluated for the same cell and MCS MUST be distinct draws. Conditional
execution MUST NOT shift a mutable stream used by later expressions.

The rule language SHOULD support explicit user labels for common-random-number experiments. Reusing
an explicit label in an ambiguous scope MUST be a compilation error.

## Named Stream Families

Independent named stream families MUST exist for at least:

- Layout placement and permutation
- Proposal recipient selection
- Proposal direction selection
- Acceptance sampling
- Lottery activation and ticketing
- Checkerboard color ordering and deterministic transaction priority, in separate streams
- Auxiliary initialization and evolution as separate streams, partitioned by stable component instance identity
- Rule-language randomness
- Event triggers
- Division orientation
- Property inheritance
- Conserved stochastic rounding
- Stochastic type transitions
- Lifecycle placement and binary partition
- Ensemble trajectory derivation

Built-in scientific code MUST NOT partition streams with undocumented numeric offsets. Adding,
removing, or reordering one stochastic component MUST NOT shift random values in an unrelated named
stream.

Named streams isolate generator inputs; they do not assert statistical independence beyond the
quality guarantees of the selected counter-based generator.

### Extension RNG Namespaces

The built-in numeric stream encoding is closed within one RNG contract version. An extension gains
randomness through a stable 128-bit semantic namespace identity and domain-separated key derivation,
combined with its instance identity, operation label, entity identity, and contract version. It MUST
NOT select an undocumented raw numeric stream offset.

The compiler-assigned mapping MUST be injective over the supported model domain and recorded in the
model fingerprint or provenance. Adding, removing, or reordering an unrelated extension MUST NOT
change an existing component's complete address. If the accepted address representation cannot
express a collision-free mapping, the RNG contract MUST be revised rather than silently aliasing
streams.

Duplicate namespace identities within one compiled model are a compilation error. The stable
identity, derivation contract, and resolved namespace mapping are included in provenance so extension
draws remain auditable.

A stochastic lifecycle trigger or division geometry declares its operation labels before lowering.
Its device result remains a pure function of the pre-lifecycle snapshot and addressed draws; branch
behavior MUST NOT shift random identities belonging to other targets or operations.

Lifecycle filtering, conflict loss, declaration permutation, descriptor grouping, workgroup
tuning, and backend launch decomposition MUST NOT shift unrelated addresses. If the current packed
address cannot encode the admitted cell/model/occurrence domains injectively, the RNG contract
version MUST change before support is claimed.

Stochastic layout placement is addressed by stable layout-instance, provisional-entity, logical
site or candidate, operation, invocation, and draw identities before runtime cell IDs exist.
Overlap rejection and removal of an empty provisional entity MUST NOT shift draws belonging to an
unrelated entity. Biological and auxiliary property initialization draws occur only for finalized
surviving runtime identities and include their slot generations.

Uniform site seeding and sequential rejection shape placement use distinct operation identities.
Site seeding defines an unbiased without-replacement sampling algorithm. Rejection placement uses a
local candidate-attempt index for each provisional entity; rejection never consumes another
entity's addresses. Randomizing canonical entity order, when explicitly requested, uses a separate
layout-permutation operation identity.

## Distribution Semantics

Every public random primitive MUST specify:

- Its mathematical distribution and parameter domain
- Its return type and precision
- Whether interval endpoints are open or closed
- Its integer-to-real mapping
- Its behavior at exact boundary parameters
- Its rejection, retry, and failure behavior
- Its handling of NaN, infinity, overflow, and invalid parameters
- Whether it is exact or approximate
- Its bitwise and statistical portability profile

Bounded integer sampling MUST be unbiased. Direction and categorical selection MUST NOT use a biased
remainder mapping unless divisibility makes that mapping exactly uniform.

Bernoulli sampling MUST make `p = 0` always false and `p = 1` always true. Values outside the accepted
probability domain MUST raise an error during validation rather than silently clamp.

Normal, Poisson, categorical, permutation, and other higher-level transforms remain under
`SEM-RNG-005`. An approximate distribution MUST have a name distinguishable from its exact
counterpart. In particular, a Poisson sampler MUST NOT silently switch to a normal approximation as
its parameter changes.

Variable-length rejection algorithms MUST address retries by a local invocation or attempt index.
Their execution MUST NOT consume or shift draws belonging to other entities or operations.

## Reproducibility Vocabulary

Documentation and APIs MUST qualify reproducibility claims using the following vocabulary.

### Distribution Correctness

All first-class backends MUST sample the documented distributions within the specified statistical
validation criteria.

### Random-Stream Reproducibility

For the same RNG version and complete semantic address, all first-class backends MUST produce the same
raw random bits. Raw-stream results MUST be independent of workgroup size and asynchronous scheduling.

### Trajectory Reproducibility

Trajectory reproducibility means repeated runs produce identical observable state and diagnostics.
It requires deterministic state transitions and numerical operations in addition to reproducible
random bits.

An algorithm MUST NOT claim trajectory reproducibility until its algorithm-specific profile resolves
`SEM-RNG-004`. Claims MUST state their scope, including backend family, device constraints, numeric
mode, workgroup-size constraints, package version, and model fingerprint where applicable.

### Continuation Reproducibility

Continuation reproducibility means a run resumed from an exact checkpoint produces the same remaining
trajectory as an uninterrupted run under the checkpoint's declared trajectory profile.

### Cross-Backend Equivalence

CPU, Metal, and AMDGPU MUST be statistically equivalent under common model and algorithm
semantics. Cross-backend bitwise trajectory equality is not required. Raw addressed random bits are
still required to match; later distribution transforms or state evolution MAY differ only as allowed
by their numerical and portability profiles.

The unqualified phrase "reproducible simulation" SHOULD NOT appear in normative documentation.

## Algorithm Guarantee Profiles

Reproducibility is an algorithm-specific claim, not a project-wide property. Every named algorithm
MUST expose a guarantee profile containing its proposal process, equilibrium status, kinetic
interpretation, transaction semantics, MCS normalization, reproducibility scope, compatible
component scopes, and validation evidence.

The word "exact" MUST be qualified. Distinct claims include an exact reference proposal process, an
exact invariant distribution, exact tracker transactions, an exact proposal budget, exact kinetics,
and a strictly reproducible trajectory. Establishing one does not establish the others.

### Sequential Reference Process

Sequential Metropolis is the executable reference process. One MCS performs exactly `N` independent
recipient selections with replacement on an `N`-site lattice, including same-owner selections and
invalid boundary directions as no-op attempts. It MUST offer strict CPU trajectory reproducibility
and remain available as a scientific oracle.

Different named algorithms need not reproduce the sequential trajectory for the same seed. They
share documented units and applicable target distributions, but use algorithm-specific schedules and
random streams.

### Checkerboard Algorithms

`CheckerboardSweepCPM` dynamics are not the reference sequential kinetics. Each mutable site is
scheduled exactly once without replacement, and each MCS uses an unbiased random permutation of
colors. A color observes one common snapshot, commits through its documented transaction, and the
next color observes the committed state.

Checkerboard equilibrium correctness remains under `SEM-ALG-001`. It MUST NOT be described as
equilibrium-exact until its transition kernel is derived for shared cell state, trackers, boundaries,
and randomized color order.

GPU intrinsics are an implementation technique rather than scientific semantics. Generic and
intrinsic implementations MAY share one algorithm name only when they implement the same
transactions and produce the same trajectory under the requested profile. If subgroup aggregation
changes results, it is a separately named algorithm with a separate guarantee profile. Subgroup width
MUST NOT define scientific batches, conflicts, or random identities in strict mode.

### Lottery Algorithms

Lottery tickets and tie-breaking MUST be pure functions of the seed, MCS, scientifically defined
internal round, and site identity. The selected set MUST be independent of scheduling and workgroup
structure.

Stable Cartesian `LotteryCPM` compares the complete four-word Philox block lexicographically. Since
Philox is a bijection and semantic site addresses pack injectively, distinct sites in one round have
distinct 128-bit tickets; finite-width ticket collisions and canonical-identity activation bias are
therefore absent. A separately stored first word may be reused as deterministic dynamic-conflict
priority after activation, where exact ties are resolved by canonical proposal identity.

Topology determines activation and internal rounds. One public step advances one normalized MCS by
expected activated-attempt normalization with equal per-site expectation. The compiled schedule is
independent of evolving model state. Each round observes the previous round's committed state;
proposals within a round use one common snapshot and transaction law. A dynamic conflict loser
consumes its activated attempt as a no-op and MUST NOT be resampled. Residual-round placement and
semantically meaningful round order use addressed algorithm streams.

Lottery kinetics are distinct parallel kinetics and MUST NOT be called exact sequential kinetics.
Equilibrium correctness remains under `SEM-ALG-002` until its composed transition kernel, including
shared-cell conflicts, is derived.

### Capability Checking

Every algorithm MUST publish a component capability matrix. If a penalty, tracker, event, rule, or
other feature invalidates its proof or transaction law, model compilation MUST fail with an
explanation and compatible alternatives. Strict and fastest implementations MAY share an algorithm
name only when they are proven semantically equivalent.

## Deterministic Parallel Transactions

Every component participating in parallel state evolution MUST declare its semantic read and write
scope. Standard scopes include site-local, neighborhood-local, cell-wide, type-wide, field-wide, and
global. A custom component that cannot provide an auditable scope is conservatively global.

The compiled model MUST derive a conservative proposal-conflict relation from all participating
components. Lattice coloring alone is insufficient when distant proposals can read or write the same
cell-wide state.

The default deterministic parallel transaction is:

1. Generate candidate proposals from one common snapshot.
2. Determine their declared read and write identities.
3. Assign each candidate a random priority from a dedicated semantic stream.
4. Select a conflict-free subset by priority, breaking exact ties by canonical proposal identity.
5. Evaluate and accept the selected proposals against the snapshot.
6. Commit accepted, mutually compatible transactions.

A rejected conflict winner continues to block losing candidates for that subround. Losing candidates
MUST NOT be retried or resampled. Two proposals that write the same cell state MUST conflict unless a
separately derived joint rule proves they may be processed together.

Snapshot semantics do not require a physical full-state copy. Coloring, versioned buffers,
disjointness proofs, or other optimized implementations MAY be used when they preserve the same
observable reads and commits.

Compilation errors MUST identify the incompatible component, its access scope, the violated
guarantee, and suitable algorithms or profiles. Debug conformance mode SHOULD expose candidate
identity, priority, conflict outcome, energy change, acceptance draw, and committed deltas.

## Numerical Determinism

Integer atomics MAY be used in strict mode only when their operation is associative and commutative,
overflow behavior is defined, and arrival order cannot affect a later read in the transaction.
Order-sensitive floating-point atomics MUST NOT define strict reductions.

Strict floating-point reductions use a fixed tree over canonical logical indices. A backend MAY
decompose that tree into workgroups, but workgroup structure MUST NOT alter the contracted order.

Every stateful numerical component MUST declare its storage type, accumulation type, conversion
point, overflow behavior, and portability profile. Strict profiles MUST specify fused-multiply-add
contraction, reassociation, transcendental behavior, subnormal handling, and any other operation that
can change future state. Backends MUST NOT silently substitute precision.

General fast math is excluded from strict profiles. Relaxed arithmetic MAY be offered under a
separately identified numerical profile. If strict execution is unsupported or its workspace cannot
be allocated, execution MUST fail rather than silently downgrade.

Integer proposal diagnostics MUST be exact and deterministic. Floating diagnostic reductions MUST
state their numerical profile. Hardware dispatch is allowed only among implementations conforming to
the requested algorithm and guarantee profile.

## Trajectory Reproducibility Scope

For an identical-trajectory claim, every observable state value and diagnostic MUST match bit for bit
at every integer MCS. Hidden state capable of affecting continuation is included.

Strict random streams and strict algorithm trajectories MUST be independent of workgroup size, CPU
thread count, asynchronous scheduling, and kernel timing. Exact trajectories are not generally
promised across different device models, even within one backend family. An implementation MAY
publish a stronger validated device scope.

Patch releases MUST preserve trajectories promised by an existing strict RNG, algorithm, and
numerical contract. Intentional changes require incrementing the affected contract version.
Historical contracts SHOULD remain selectable when needed for published work.

Fully integer-defined uniform, Bernoulli, bounded-integer, categorical, and permutation operations
MUST match across supported backends once their transforms are accepted. Transcendental distribution
transforms are only statistically portable unless their profile proves bitwise portability.

Built-in components participate in strict guarantees. Custom stochastic components MUST use semantic
streams and declare access, numerical, and conformance metadata. Undeclared external or global
randomness makes strict preflight fail.

## Public Reproducibility Interface

The primary high-level interface SHOULD center on `seed` and a requested profile:

```julia
prob = PottsProblem(system, layout, grid_size; seed = 42)
sol = solve(prob, alg; reproducibility = :strict)
```

Paper-facing supported algorithms default to strict reproducibility. Statistical or relaxed
execution requires an explicit request. If the backend cannot honor the requested profile, execution
MUST throw an informative error and MUST NOT continue under a weaker profile.

Seeds SHOULD be displayed as fixed-width hexadecimal. Advanced users MAY select a retained RNG
contract version. Replicate seeds MUST use versioned derivation rather than naive seed addition.

Potts.jl SHOULD provide a `reproducibility_report(prob, alg, backend)` preflight operation. It reports
the promised level, contract versions, unsupported components, reasons for limitations, numerical
mode, and estimated deterministic workspace. A run that cannot preserve the preflight promise MUST
terminate rather than complete with a silent downgrade.

Problem and solution displays SHOULD include the realized seed, RNG version, model-fingerprint
prefix, algorithm guarantee, backend profile, and exact-continuation availability.

## Ensembles

An ensemble trajectory seed MUST be derived deterministically from the ensemble master seed,
trajectory identity, and rerun identity. It MUST NOT depend on batch size, worker assignment,
completion order, host task scheduling, or ensemble execution strategy.

`EnsembleSeedDerivationV1` uses the semantic Philox machinery and domain separation over the
realized `UInt64` master seed, stable trajectory identity, rerun identity, and derivation version.
An explicit ensemble `seed` is the master; when omitted, the template problem seed is the master.
Supplying an ensemble `rng` consumes exactly one `UInt64` master value before scheduling and stores
that value in provenance.

The user's SciML `prob_func` runs first and MUST return a `PottsProblem`; automatic seed `remake`
runs afterward so ordinary parameter sweeps cannot accidentally duplicate streams. An explicit
`UserManagedEnsembleSeeds()` policy disables automatic derivation and records that the user owns
trajectory-seed uniqueness.

Serial, threaded, distributed, split-threaded, and GPU ensemble execution MUST assign the same
trajectory seed to the same semantic trajectory identity. A rerun MUST receive a distinct derived
seed while retaining its relationship to the original trajectory in provenance.

Common-random-number experiments are a first-class use case. Named streams, explicit DSL draw labels,
and stable trajectory identities SHOULD support paired comparisons without promising identical
complete trajectories after a model change.

## Snapshots, Checkpoints, and Provenance

The authoritative capture boundary, canonical schema, restore, import, integrity, and storage rules
are defined in [Snapshots, Checkpoints, Restore, and Logical Storage](persistence.md). This section
defines the RNG and reproducibility content of that contract.

A saved observation that omits continuation data is a snapshot and MUST NOT be advertised as an exact
checkpoint.

An exact checkpoint MUST contain or identify:

- The realized master seed
- RNG contract version
- Current integer MCS
- Algorithm-defined semantic counters
- Cell slot generations
- Never-used/active/reusable slot status and cell-ID high-water mark
- Complete biological and auxiliary state
- Model and schema fingerprint
- Algorithm and sampler identity
- Backend family, device constraints, and numeric mode required by the trajectory profile
- Potts.jl, Julia, and dependency version provenance needed by that profile

Counter-based draws SHOULD be reconstructible from semantic state rather than serialized per-thread
RNG states.

Solutions MUST expose at least the realized seed, RNG version, model fingerprint, algorithm identity,
and applicable reproducibility profile.

The model fingerprint MUST cover all semantically relevant compiled structure, parameters,
schedules, stream identities, initial state, and contract versions. It MUST exclude output paths,
visualization configuration, memory addresses, and kernel launch configuration. Logically unordered
collections are canonicalized; order is retained where order has accepted semantics. The realized
initial state MUST also have an independent checksum.

Solution provenance MUST include requested and achieved profiles, backend and device identity,
numeric types and math profile, workgroup configuration, package and Julia versions, dependency or
manifest identity, MCS interval, checkpoint ancestry, and conformance warnings. Environment files MAY
be bundled once rather than duplicated into every observation.

Checkpoint writing MUST be transactional: an incomplete artifact is written and validated before it
is published as complete. Loading verifies checksums and semantic compatibility before mutating a
simulation. Incompatible exact continuation MUST be rejected; an explicit state import MAY start a
run with a weaker guarantee.

Stable exact checkpoints are captured only at finalized MCS `0` or completed positive integer-MCS
boundaries. They reconstruct replaceable caches and execution workspaces rather than serializing
backend machinery.

Same-compatible-profile checkpoint continuation is exact. Moving a checkpoint to a different
backend is a logically valid import when supported, but provides statistical rather than exact
trajectory continuation unless a stronger profile has been validated.

Reproduction helpers MUST NOT silently install packages or mutate the active Julia environment. They
MAY create an isolated environment description and report version mismatches.

PottsToolkit SHOULD provide a publication-bundle helper containing the declarative model, seed list,
contract versions, environment identity or files, hardware report, initial-state checksum,
diagnostics, output checksums, and optional exact checkpoint.

## Conformance Evidence

Acceptance requires:

- Published known-answer vectors for the raw generator
- Raw-bit identity on CPU, Metal, and AMDGPU
- Workgroup-size and asynchronous-scheduling invariance tests
- Static or generated auditing that built-in semantic addresses do not collide
- Multiple-random-expression rule tests
- Named-stream isolation tests
- Cell-ID reuse and slot-generation tests
- Exact uninterrupted-versus-checkpointed continuation tests
- Ensemble scheduling and rerun derivation tests
- Statistical validation of every distribution transform
- Golden trajectories for every algorithm and scope claiming trajectory reproducibility
- Exact small-system stationary-distribution and transition-flow comparisons where applicable
- Predefined kinetic-observable comparisons against the sequential reference where meaningful
- Cross-backend ensemble equivalence tests with predefined margins and confidence intervals
- Generated release-level conformance reports

Statistical tests MUST define sample sizes, statistics, tolerances, and false-positive control. A fixed
golden trajectory alone is not evidence of distribution correctness.

Validation is tiered into deterministic per-commit tests, moderate fixed CI batteries, and large
scheduled or release campaigns. Multiple tests MUST use explicit false-positive control. Tolerances
MUST NOT be widened after observing failure without scientific justification and a recorded decision.

An affected release or guarantee MUST be blocked when required validation fails. Strict performance
is also a release concern: deterministic transactions, scans, compaction, sorting, and reductions
MUST be benchmarked on all first-class backends.

A paper-quality claim requires accepted algorithm profiles, reference comparisons, cross-backend
statistical validation, checkpoint continuation tests, reproducibility reports, strict and fastest
valid performance results, and a generated conformance artifact.

All documented stochastic examples SHOULD use explicit seeds unless demonstrating entropy-derived
seed behavior is the example's purpose.

Random address exhaustion or counter overflow MUST raise an error and MUST NOT wrap into a previously
used address.
