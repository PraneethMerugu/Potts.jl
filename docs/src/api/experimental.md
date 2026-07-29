# [Experimental API](@id experimental-api)

!!! warning "Experimental surface"
    These names may change without the stable migration policy. Successful execution does not
    promote them or establish scientific qualification.

## Act

The `Act` facade remains experimental because
`design/audits/phase-14-public-api-v2.toml` is still
`wortel-vertical-slice-provisional`. Its Persistent Wanderer and Selective Migration Through a
Dense Monolayer examples are therefore not part of the required gallery or normal navigation.

Promotion requires an explicit API-registry decision. Documentation will not create stability by
showing the examples first.

## Experimental algorithms and visualization

- `SequentialEquilibrium` requires its own equilibrium evidence.
- `TiledCheckerboardCPM` has an experimental scheduler contract and is not a sequential substitute.
- `PottsVolume`, `PottsExplorer`, and `RerunController` are experimental MakiePotts reference
  implementations.

## ProcessBigraph boundary

Dynamic hierarchy, structural add/remove/divide/move/rewire transactions, and the
ProcessBigraphs–Potts adapter are qualified for the unpublished internal beta but remain outside
the public Potts workflow until a separate API promotion. Internal qualification is not a public
runtime release.

## Using experimental names responsibly

Pin the package revision, record the experimental contract identity, isolate usage behind a local
adapter, and expect migration work. Do not use an experimental example as evidence for a stable
published model or backend claim.

See [Capability status](@ref capability-status) for the complete support matrix.

## Provisional reference

### PottsToolkit

```@autodocs
Modules = [PottsToolkit.Authoring]
Filter = is_experimental_pottstoolkit
```

### CorePotts

```@autodocs
Modules = [CorePotts]
Filter = is_experimental_corepotts
```

### MakiePotts

```@autodocs
Modules = [MakiePotts]
Filter = is_experimental_makiepotts
```
