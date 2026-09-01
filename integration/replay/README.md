# Exact replay integration

This project pins the complete dependency and Julia version used by the native
checkpoint/restart witnesses. Run it with Julia 1.12.1:

```sh
julia +1.12.1 --project=integration/replay integration/replay/runtests.jl
```

The ordinary `integration` project tests functional execution across its
compatible dependency ranges. Exact replay is the stronger, opt-in contract;
changing a pinned package or Julia version creates a different replay profile.
