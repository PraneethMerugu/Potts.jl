# [CorePotts API](@id corepotts-api)

Most users should author with PottsToolkit. CorePotts intentionally exposes a
narrow MTK-free runtime boundary:

- `ProgramInitialState`, `ProgramRuntime`, `ProgramSnapshot`;
- `initialize_program`, `advance_mcs!`, `program_snapshot`;
- parameter updates, execution/capability reports, and failure reports;
- `ProgramCheckpoint`, `program_checkpoint`, and
  `restore_program_checkpoint`; and
- generation-safe lifecycle identities, events, receipts, and receipt access.

Compiler and backend implementation protocols are quarantined in the named
`CorePotts.CompilerSPI` and `CorePotts.BackendSPI` modules. A downstream
extension should use the smallest public member of those modules and pass its
owner-package conformance suite. Private file topology and underscored helpers
are not extension points.

`CompilerSPI` constructs and inspects validated compiler IR. `BackendSPI`
implements admitted runtime, transaction, adaptation, and settlement behavior.
They are explicit facades over CorePotts bindings rather than parallel
implementations, and an extension should not mix them merely for convenience.
See [Extension boundary](@ref extension-boundary) for the role map.

```@example core_boundary
using CorePotts
runtime_api = Set((
    :ProgramInitialState,
    :ProgramRuntime,
    :initialize_program,
    :advance_mcs!,
    :program_checkpoint,
))
(
    all(name -> Base.ispublic(CorePotts, name), runtime_api),
    Base.ispublic(CorePotts, :CompilerSPI),
    Base.ispublic(CorePotts, :BackendSPI),
)
```

CorePotts owns numerical invariants and logical persistence; it does not own
symbolic biological authoring, ModelingToolkit systems, SciML solver
selection, or presentation.

## Reference

```@docs
CorePotts.CompilerSPI
CorePotts.BackendSPI
```

```@autodocs
Modules = [CorePotts]
Private = false
```
