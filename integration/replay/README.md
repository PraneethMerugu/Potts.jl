# Exact replay integration

This project pins the complete dependency and Julia version used by the native
checkpoint/restart witnesses. The qualified native replay profile uses Julia
1.12.6 on ARM macOS (`aarch64`, Julia machine
`arm64-apple-darwin24.0.0`), as exercised by the `macos-15` CI runner. Run it on
that platform:

```sh
julia +1.12.6 --project=integration/replay integration/replay/runtests.jl
```

The ordinary `integration` project tests functional execution across its
compatible dependency ranges. Exact replay is the stronger, opt-in contract;
changing a pinned package, Julia version, or platform creates a different
replay profile. Matching package versions on Linux does not admit the native
exact-replay guarantee.

The checked-in manifest is release evidence, not a development convenience.
Its `LocalMath` and `CorePotts` entries must name immutable Git revisions from
their standalone repositories; sibling filesystem paths are invalid. The
`Potts` entry may point at this checkout because this environment validates the
package containing it. Regenerate the manifest only after the audited upstream
commits are selected.
