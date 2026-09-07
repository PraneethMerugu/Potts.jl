# Potts 0.3.0-rc2

- `PottsProblem` accepts authored, completed, or scheduled `PottsSystem` values.
  Unscheduled input passes through the sole idempotent `mtkcompile` authority;
  scheduled input is retained without another source traversal.
- Ordinary tutorials now proceed directly from model declaration to problem
  construction. Explicit `mtkcompile` remains available for compiler inspection
  and domain-compiler workflows.
- Adds an executable complete-model tutorial combining transparent scalar
  functions, gathered reductions, tracker projections, field and cell state,
  relationship/lifecycle behavior, checkpoint continuation, and failure
  diagnosis.

## Potts 0.3.0-rc1

- Renames the pre-release `PottsToolkit` package to `Potts` while preserving its UUID.
- Uses independently versioned LocalMath 0.2 and CorePotts 0.2 dependencies.
- Breaks compatibility with pre-release checkpoint extension identities; old checkpoints reject explicitly.
- Supports CPU and the qualified Metal profile. CUDA and ROCm are not release-qualified.
- Keeps symbolic authoring, SciML integration, published models, and exact replay in the Potts repository.
