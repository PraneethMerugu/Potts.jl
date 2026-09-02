# Potts 0.3.0-rc1

- Renames the pre-release `PottsToolkit` package to `Potts` while preserving its UUID.
- Uses independently versioned LocalMath 0.2 and CorePotts 0.2 dependencies.
- Breaks compatibility with pre-release checkpoint extension identities; old checkpoints reject explicitly.
- Supports CPU and the qualified Metal profile. CUDA and ROCm are not release-qualified.
- Keeps symbolic authoring, SciML integration, published models, and exact replay in the Potts repository.
