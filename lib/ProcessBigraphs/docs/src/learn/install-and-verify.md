# [Install and verify the internal beta](@id install-and-verify)

> **Support level:** qualified unpublished internal beta.

**Outcome.** Verify the local package, exact logical-time arithmetic, canonical
encoding, and semantic identity in one standalone program.

**Prerequisites.** Julia 1.12.6 and a checkout of this repository.

```sh
julia --project=lib/ProcessBigraphs/docs -e 'using Pkg; Pkg.instantiate()'
```

## Complete executed source

The following is the complete canonical program. It has no hidden scientific
setup and the docs build evaluates it exactly as shown.

```@example install-and-verify
using ProcessBigraphs

scale = TimeScale(1, 10, :second)
deadline = LogicalTime(25, scale)
delay = Duration(5, scale)
target = deadline + delay

@assert physical_value(target) == 3
@assert decode_logical_value(encode_logical_value(target)) == target

result = (
    version=pkgversion(ProcessBigraphs),
    logical_time=target,
    seconds=physical_value(target),
    identity=canonical_fingerprint((:installation_probe, target)),
)
```

**Material defaults.** The scale is one tenth of a second; the probe is pure
and has no backend, runtime seed, or stochastic operation.

**Expected result.** `seconds == 3`, logical encoding round-trips exactly, and
the identity is a 64-character digest.

**Establishes.** This establishes that the pinned docs environment can load the
package and execute exact semantic primitives.

**Does not establish.** It does not qualify a model, engine, backend, or
scientific conclusion.

**Backend / runtime / seed.** CPU host Julia runtime; deterministic; no seed.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/install_and_verify.jl`

**Next step.** Continue to [the process-bigraph mental model](@ref mental-model).
