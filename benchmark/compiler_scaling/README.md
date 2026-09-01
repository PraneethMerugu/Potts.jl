# LocalMath compiler scaling

These focused workloads measure cold planning, preparation, and first execution
as the number of compatible stages grows. They are diagnostic benchmarks, not
machine-dependent pass/fail gates.

Run the synthetic stage-scaling workload with the LocalMath environment:

```sh
julia --project=lib/LocalMath --startup-file=no \
    benchmark/compiler_scaling/stage_scaling.jl --stages=8 --backend=cpu
```

Run the CorePotts flagship workload with the CorePotts environment:

```sh
julia --project=lib/CorePotts --startup-file=no \
    benchmark/compiler_scaling/corepotts_flagship.jl
```

Both workloads report structural launch and specialization facts alongside
timings. Compare results on the same machine and Julia environment; do not use
the retained historical samples as universal timing thresholds.
