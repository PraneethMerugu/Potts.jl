# LW-5B4O O0 pre-change baseline

Date: 2026-08-13

Status: **FROZEN BEFORE O1 SOURCE CHANGES**

This record binds the dirty-tree B4 candidate that precedes LW-5B4O. It does
not claim that B4 passed. Existing direct kernels remain the independent
oracles and production-selected paths.

## Source identities

```text
2edb2987deeb38f01b3aa22fdb46ccfc3ac5aa4c2466d913ae90636f729ade35  lib/CorePotts/src/execution/localworksets_candidate_bridge.jl
231ad468de21409b29482d95b285a9a38774596ad656cc4bdd3371df6fc7ef72  lib/CorePotts/src/execution/localworksets_checkerboard_view.jl
659ef2ac9db272e0ed3814503738555ca7518278e18481984d9b5c9903f795dc  lib/CorePotts/src/execution/localworksets_adapter.jl
4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8  lib/CorePotts/src/execution/checkerboard_kernels.jl
e7aef6c16ce8a95fcea27f31f404d19395b414e0c6974ced642ea3767adc0df5  lib/CorePotts/src/execution/checkerboard_program.jl
9d3d12b343ce80b6c3ab2087270f4b2e6fef24756c426ed4e850d54b11857c3c  lib/CorePotts/src/rng/semantic.jl
5b4280683e9c3adc62d6a12af64015a6a8d8920300111fecd37f3231e6fb6ffb  lib/LocalWorksets/src/execution.jl
adf82ba92309516b2c55bc4770af97e9857c8564f8ea179d39c556eb1b10378c  lib/LocalWorksets/src/execution/localworksets_generic.jl
747fea2abafaa3f54d749c1ec21d595b01c4d95d46021dc5e94c6cf5bb556241  lib/LocalWorksets/src/execution/localworksets_combined.jl
5e799c9e84e72815c6170f854587df8a0af72b397b8086f532eeb1d81c4a53cf  lib/LocalWorksets/src/execution/localworksets_single_resolved.jl
b2e7b6529457f28faac2e049190c53b0cf2627ae0abe7dc19571ecf1797357a3  lib/LocalWorksets/src/preparation.jl
a0fa0c1604316e9467cdddcd7bb9625de0f676d3b0ca47018855aac9c95f4456  lib/CorePotts/Project.toml
dc480d9172382dc02fd37368a51d7880ba1d1cc948441e062a47538d28e9eca1  lib/LocalWorksets/Project.toml
```

The worktree already contains the uncommitted B0/B2/B3/B4 implementation and
evidence files. LW-5B4O preserves those changes and does not use a reset,
checkout or destructive cleanup.

## Dependency baseline

- CorePotts direct dependencies do not include StructArrays or StaticArrays.
- LocalWorksets direct dependencies do not include StructArrays or
  StaticArrays.
- StaticArrays 1.9.18 is present transitively in both package manifests.
- StructArrays 0.7.3 is present in the examples environment but not either
  package environment.

## Available B3/B4 evidence

- Corrected B3 is the last reviewed performance baseline: CPU
  `upper95=0.9970121927685043` and qualified real-Metal
  `upper95=1.0052519529521557`, both under the unchanged 1.05 rule.
- The initial isolated K02/B4 read-only diagnostic reported direct
  `0.0040093125` seconds, candidate `0.006148229` seconds, median ratio about
  `1.5335`, and upper95 about `1.5549`. This was not yet a durable B4 evidence
  run and must be reproduced by the frozen final protocol; it is preserved as
  adverse attribution evidence rather than a qualification claim.
- The same diagnostic reported direct 1,318,176 bytes/10,227 allocations and
  candidate 1,384,256 bytes/10,630 allocations across twenty submissions: a
  candidate delta of 66,080 bytes and 403 allocations.
- The pre-change K02 lowering has seven partial-independent scalar ports, one
  launch, zero algorithmic workspace and seven copies of the same logical
  identity route in each bank-local preparation.

## Known pre-change blockers

1. `active_count` is bounded only by maximum color capacity rather than tied
   to the selected color's exact realized size.
2. canonical and executing checkerboard/proposal-offset validation proves
   summary fields and dimensions rather than complete logical content.
3. the topology epoch includes proposal-offset contents but not complete
   checkerboard sites/color offsets/conflict displacement contents.
4. the seven-port lowering repeats identity-route transfer, route loads,
   conditional-mask checks and adapter schema assembly.
5. warm submission retains repeated validation/projection and boxed lease
   payload work that must be separately attributed before removal.

O1 repairs items 1 through 3 before any physical representation change.
