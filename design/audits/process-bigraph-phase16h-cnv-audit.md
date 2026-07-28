# ProcessBigraphs Phase 16.H CNV audit

Status: qualified CPU bounded assembly

Date: 2026-07-27

## Outcome

Phase 16.H delivers a runnable, source-bounded reimplementation of adhesion scenario 38,
simulation 902 from Shirinifard et al. (2012). It is not a quantitative reproduction, a
one-year ensemble, or a claim of CompuCell3D trajectory identity.

The authoritative source/mechanism map is
`spec/process-bigraph-phase16-cnv-trace-v1.toml`. Text S6 remains in a separate,
checksum-verified fetch lane and no foreign source or PIF asset is vendored.

## Ownership and schedule

ProcessBigraphs owns the one-MCS clock, immutable snapshots, four simultaneous field
invocations, step ordering, atomic publication, observation, checkpoint/restart, and rollback.
Each injected field declaration owns numerical reconstruction and stepping. CorePotts owns the
one-attempt-per-site CPM computation and the cell/relationship/degradation kernels.

The qualified split is:

1. advance oxygen, EC-derived VEGF, RPE-derived VEGF, and MMP through four managed field
   declarations;
2. execute one CorePotts CPM MCS from the four published field snapshots;
3. execute phenotype, timer, growth, division, death, relationship-retuning, and BrM updates;
4. derive frozen field-exchange inputs for the next MCS; and
5. publish observations and stable checkpoint state.

This resolves orchestration without transferring numerical ownership into ProcessBigraphs.

## Source-bounded implementation

The generated startup reconstructs the 40×40×35 Text-S6 geometry algebraically: 36 vascular
cells, 100 RPE cells, 16 POS units, 25 PIS units, one Tip cell, 3,200 one-voxel BrM structures,
and 1,600 source-static, high-penalty NonStick structures. It contains 4,978 active identities with source identity
ceiling 5,151. The deterministic face-contact pass creates 1,138 focal relationships using all
16 source parameter rows and per-pair junction limits.

The CPM phase uses the source seed, one attempt per site, order-4 proposal and contact
relations, the transcribed 11-type contact matrix, volume and face-surface penalties, and both
VEGF chemotaxis fields. The bounded reference uses a global temperature of 100; source
type-specific motilities are preserved in the fingerprint. Exact contact inhibition is covered
by a mechanism microfixture, while focal-link creation/retuning remains a distinct transactional
phase. These are explicit bounded-morphology approximations, not hidden parity claims.

The biology transaction covers the exact MCS-400 Tip-to-Stalk transition, oxygen threshold 49,
800-MCS hypoxia timers, contact-limited stalk growth, the source Hill law, division over volume
64, VEGF-dependent endothelial death, support-contact RPE death, focal-link retuning, and
0.075×MMP BrM degradation before MCS 500.

## Field profiles

All four fields use the generic `ManagedFieldAdvanceProcess`; callers may replace any
declaration with another qualified adapter. The native CPU profile maps source rates from one
MCS to the exact 216-second ProcessBigraphs tick. VEGF2's one normal plus 12 extra finite
difference passes are represented as 13 native substeps. The upper oxygen plane is driven
toward 18 mmHg through source-specific exchange while the generic stencil remains no-flux in z.

The custom Text-S6 oxygen solver is not silently declared equivalent: adaptive vascular source
state, convergence, and legacy empty-population behavior remain named ambiguity items. An
injected adapter may provide a stronger steady-state realization without changing the model
schedule.

## Qualification

The generated test suite passes 37 assertions:

- 17 startup, relationship, source-constant, and chemotaxis assertions;
- 10 phenotype, timer, division, death, and degradation assertions; and
- 10 managed four-field, CPM, observation, checkpoint/restart, and rollback assertions.

A separate full-domain qualification run constructed the complete 40×40×35 state, compiled
the same native assembly, and executed one full 143,360-attempt MCS. It retained all 4,978
identities, moved from 41,152 to 40,700 occupied voxels, and retained finite four-field state.
Ordinary CI uses generated reduced execution fixtures and the full startup generator; it does
not fetch Text S6.

The canonical encoder received a byte-identical numeric-array specialization because this
model exposed excessive allocation from rebuilding type/value strings per scalar. Five parity
fixtures prove the optimized encoding matches the prior elementwise byte stream for unsigned,
signed, Float32, and Float64 arrays. This is a shared persistence simplification, not a
model-specific checkpoint format.

## Claim boundary

Qualified:

- source/mechanism trace and checksum-only source lane;
- generated full-domain startup;
- bounded CPU CPM/four-field/lifecycle execution;
- reduced relationship, division, death, phenotype, and degradation fixtures;
- observation, exact restart, and rollback; and
- arbitrary field-declaration injection through the common solver protocol.

Not claimed:

- exact CompuCell3D 3.4.2 attempt/update order;
- exact custom oxygen-solver convergence;
- one-year or ten-replica execution;
- Figure 7/8 morphology classification or quantitative reproduction;
- type-specific-temperature trajectory parity; or
- Metal/ROCm CNV qualification.

Phase 16.C real-hardware rows remain independently open.
