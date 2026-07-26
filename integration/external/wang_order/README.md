# Wang CompuCell3D 4.2.5 Order Oracle

This is a clean-room foreign-runtime microfixture for the execution order used by the pinned
Wang et al. collective-migration source. It contains no upstream model code or paper assets.

The fixture has two independent sentinels:

1. a `runBeforeMCS` steppable resets an integer to `1`; normal Python steppables registered in
   order append `2`, `3`, and, at frequency 10, `4`. The recorder must observe `1234` at MCS 0
   and 10 and `123` otherwise; and
2. the pre-MCS steppable writes `3` into a field. The XML `DiffusionSolverFE` applies a constant
   concentration of `7` to the all-medium lattice. Normal Python must therefore observe `7`.

These operations do not commute. A trace cannot pass by merely containing the expected stages.
The fixture complements the source-level proof that `Simulator::step` executes Potts Metropolis
before the XML steppable registry.

Run it with the official CompuCell3D 4.2.5 command-line runner. On a first launch,
`run_cc3d_isolated.py` can redirect CC3D's preferences into a disposable directory without
changing the user's home:

```sh
CC3D/python37/bin/python run_cc3d_isolated.py /tmp/cc3d-settings \
  CC3D/lib/site-packages/cc3d/run_script.py \
  -i /absolute/path/to/wang_order_oracle.cc3d -o /tmp/wang-order-output
```

The run writes `wang_order_trace.csv`. Validate a captured trace with:

```sh
julia --project=. scripts/validate_wang_order_oracle.jl \
  /tmp/wang-order-output/wang_order_trace.csv
```

The committed evidence record identifies the exact binary and trace used for the accepted audit.
Generated output is not written into this directory.
