# LM-2B independent precompile baseline blocker

Observed before LM-2B receipt edits with Julia 1.12.6:

```text
julia --project=. --startup-file=no -e 'using PottsToolkit'
```

PottsToolkit precompilation enters `src/precompile.jl`'s public lifecycle solve
and fails in the existing CorePotts lifecycle execution with:

```text
LifecycleBackendFailure(
    cause = MethodError(KernelAbstractions.__index_Global_Linear, ...),
    first_possible_mcs = 0,
    last_possible_mcs = 0,
)
```

The failure occurs while KernelAbstractions CPU lifecycle kernels execute
inside package precompilation. LocalWorksets and CorePotts themselves
precompile successfully before the root workload reaches this failure.

This is an inherited lifecycle/KA precompile-context blocker. LM-2B does not
change the affected lifecycle kernel, suppress the precompile workload, add a
fallback, or count this failure as receipt work. Root-package precompile is
therefore not an LM-2B completion claim until the blocker is corrected by a
separate change.

The same command was repeated after the LM-2B receipt implementation. It still
fails at the same `KernelAbstractions.__index_Global_Linear` lifecycle call
with MCS bounds `0:0`, confirming that the receipt cutover neither disguised
nor moved the independent blocker.

## LM-2D resolution

LM-2D retains the same complete public construction-through-one-MCS workload
and places it inside `PrecompileTools.@compile_workload`. The workload remains
executable and is neither suppressed nor replaced by artificial method
declarations.

The final investigation also isolated the concrete kernel defect hidden by the
precompile context. The lifecycle compaction kernel nested KA's `@index` macro
inside an `Int32(...)` call. KA's CPU lowering did not rewrite that nested
macro, so execution reached the one-argument GPU intrinsic
`KernelAbstractions.__index_Global_Linear`. Hoisting `@index(Global, Linear)`
to its own local binding before conversion restores ordinary KA lowering on
CPU and GPU. No lifecycle semantics, launch, barrier, or fallback changed.

With both corrections present, a source-invalidated root load completed the
unchanged scientific workload and precompiled `PottsToolkit` successfully:

```text
JULIA_NUM_PRECOMPILE_TASKS=1 julia --project=. --startup-file=no \
    -e 'using PottsToolkit; println("source-invalidated-load-ok")'
source-invalidated-load-ok
```

The immediately following cached load also completed successfully. The root
fresh-process public construction-through-solution test passed 1/1. The
inherited LM-2B precompile blocker is therefore closed rather than suppressed.

The separate cold-compilation blocker is also closed by the 2026-08-23
workspace-template and validation consolidation. This does not reopen or alter
the precompile correction recorded here.
