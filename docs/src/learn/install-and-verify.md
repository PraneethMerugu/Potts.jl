# [Install and verify](@id install-and-verify)

This page establishes a CPU installation and verifies the same public authoring and execution
boundary used by the rest of the manual. GPU setup comes later; it should not be necessary to learn
or reproduce the CPU examples.

## Requirements

- Julia 1.12 or a later Julia 1.x release;
- Git when installing an unregistered checkout;
- a 64-bit macOS, Linux, or Windows host.

Until PottsToolkit is registered, install it from the repository:

```julia
using Pkg
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl", subdir = "lib/CorePotts")
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl")
```

Julia requires directly imported packages to be direct project dependencies. Install CorePotts
explicitly because execution pages use `import CorePotts`; relying on PottsToolkit's transitive
dependency is not sufficient. Install MakiePotts only when visualization is needed:

```julia
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl", subdir = "lib/MakiePotts")
```

For a source checkout, instantiate the documentation environment from the repository root:

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
```

The command is identical in macOS Terminal, a Linux shell, and PowerShell. In PowerShell, retain
the single quotes around the Julia expression. If a corporate proxy blocks package downloads,
configure Julia's package server or proxy before changing project files.

## Verify authoring and CPU preflight

The canonical smoke constructs one cell, validates the biological model, lowers it to a problem,
and preflights the CPU algorithm.

```@example install-and-verify
using PottsToolkit

medium = Medium(:medium)
cell = CellType(:cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 4, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 2,
    ),
)
problem = PottsProblem(
    model,
    CartesianDomain((4, 4)),
    Layout(LabelledCells(UInt64[1 1 0 0; 1 1 0 0; 0 0 0 0; 0 0 0 0],
        (1 => cell,)));
    capacity = 2,
    tspan = (0, 1),
    seed = 42,
)
algorithm = SequentialCPM(temperature = 0.0f0)
report = backend_report(problem, algorithm)

@assert isvalid(model)
@assert report.qualified
result = (; model_valid = true, backend_qualified = report.qualified,
    lattice = (4, 4))

(result.model_valid, result.backend_qualified, result.lattice)
```

The complete executable program is
[`docs/models/tutorials/install_and_verify.jl`](https://github.com/PraneethMerugu/Potts.jl/blob/main/docs/models/tutorials/install_and_verify.jl).
It deliberately stops after preflight; [First simulation](@ref first-simulation) adds execution and
visual output.

## Diagnose installation failures

Run `versioninfo()` and `Pkg.status()` before reporting a problem. A useful report includes the
operating system, Julia version, full exception, package manifest, and whether the failure occurred
during dependency installation, precompilation, model validation, or execution. See
[Troubleshooting](@ref troubleshooting) for symptom-oriented checks.

Successful import is not a backend qualification result. The verification above requires
`backend_report(...).qualified == true`, so unsupported combinations remain visible instead of
being silently substituted.
