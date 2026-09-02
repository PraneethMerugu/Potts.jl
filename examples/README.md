# Current examples

These examples are executable against the current public package interfaces:

- `wortel_2021_serial.jl` is the bounded Wortel integration witness used by the
  manual.
- `merks_2006_serial.jl` is the bounded Merks integration witness used by the
  manual.
- `openvt_monolayer_serial.jl` replaces the monolayer/OpenVT notebooks with a
  bounded 11-cell relaxation calibration, zero-adhesion monolayer, explicit
  free-surface contact-inhibition classification, and public lifecycle division.

Run them from this environment after instantiation, for example:

```sh
julia --project=examples examples/wortel_2021_serial.jl
```

The former research notebooks mixed those scientific purposes with retired
CorePotts interfaces, package-installation cells, and unsupported accelerator
selectors. The OpenVT example above is their current executable scientific
mapping; historical development records belong under `design/`, not in the
current examples inventory.
