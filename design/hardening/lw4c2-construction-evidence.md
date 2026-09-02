# LW-4C2 construction and binding evidence

Status: complete; LW-4C3 may begin

Date: 2026-08-11

## Authoring result

The lifecycle remains exactly:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
event = run!(prepared)
wait(event)
```

C2 adds two bounded conveniences without adding a lifecycle value:

```julia
topology = LocalWorksets.topology(work;
    epoch = UInt64(1),
    routes,
    destination_counts,
    semantic_ids,
)

prepared = prepare(workplan, storage; lease_capacity = 2)
```

`topology(work; ...)` derives only `item_count` from the declared one-based item domain. Epoch,
route matrices, per-output destination counts and resolved semantic identities remain explicit.
In particular, an empty destination is not lost by inferring destination capacity from the maximum
route value.

When `workspace` is omitted, LocalWorksets walks the same package-owned workspace specification
used by validation and evidence, allocates each exact leaf through `KernelAbstractions.allocate`,
and creates a bounded host lease vector. Allocation happens only inside `prepare`; `plan`, `run!`,
`wait` and `inspect` do not allocate algorithmic scratch. Explicit caller workspace remains fully
supported, and specifying both an explicit workspace and `lease_capacity` is rejected.

Storage remains an ordinary named tuple. Static, mixed and entirely submission-bound storage use
the same exact element type, shape, stride, backend, device, access and alias checks. Missing and
extra bindings are reported separately.

`sequence((a, b))` is exact tuple-to-varargs sugar. The existing executable sequence test proves
provider program order and visibility without an intermediate wait. Automatic sequence workspace
is a tuple of per-stage bounded workspaces with uniquely qualified inspection names.

## Inspection and ownership

Prepared inspection now reports:

- `workspace_ownership = :package` or `:caller`;
- `allocation_class = :allocated_once_during_prepare` or `:caller_owned_prebound`;
- exact `algorithmic_workspace_bytes` from planned evidence; and
- a named `workspace_facts` record containing identity, element type, rank, size, strides, backend
  and device/context for every scratch array.

Inspection remains non-synchronizing. Preparation leaves `submitted == 0` and `wait_count == 0`.

## Qualification

- Complete standalone LocalWorksets suite: **pass**.
- Focused CPU direct, heterogeneous buffered, legacy resolved, conjunctive, sequence and entirely
  submission-bound automatic-workspace tests: **pass**.
- Caller-owned versus automatic parity and malformed explicit workspace rejection: **pass**.
- Source guard: automatic scratch uses `KernelAbstractions.allocate`; no `zeros`, aggregate Adapt,
  vendor constructor, host fallback, launch or synchronization is present: **pass**.
- Focused real-Metal conformance with `Metal.allowscalar(false)`: **pass**. Automatic scratch has
  the prepared Metal backend, preparation adds no launch/wait, execution matches the reference,
  sequence/order behavior remains intact and compiler-cache reuse remains stable.

No CUDA or ROCm runtime qualification is claimed.

