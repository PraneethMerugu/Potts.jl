# [Capability status, migration, and troubleshooting](@id capability-migration-troubleshooting)

> **Support level:** this page is the operational boundary for the qualified
> unpublished internal beta.

## Status vocabulary

| Label | Meaning |
|---|---|
| supported internal beta | ordinary user API retained through explicit migration |
| qualified extension | public dispatch protocol with conformance obligations |
| experimental internal beta | inspectable but outside the admitted stable boundary |
| deprecated compatibility | retained reader or call shape with a migration target |
| internal | representation; downstream use is unsupported |

The [API pages](@ref user-authoring-api) show the owning task and support label
for admitted bindings. Export alone is not a scientific or compatibility
claim.

## Migration discipline

1. Name the old and new semantic versions.
2. Record preserved parameters and intentional changes.
3. Provide an explicit archive reader or reject with a migration-required
   error.
4. Compare canonical meaning and bounded behavior where equivalence is claimed.
5. Requalify docs, tests, oracles, performance, and browser evidence affected
   by the change.

## Troubleshooting

| Symptom | First check |
|---|---|
| `ModelValidationError` | read every diagnostic location and suggestion; missing schedule and binding errors may coexist |
| incompatible port/store | compare type, shape, units, ontology, update law, residency |
| engine authorization rejected | compare backend, precision, residency with declared capabilities |
| partial horizon rejected | choose a compatible horizon or declare partial support |
| checkpoint rejected | compare schema, model, plan, continuation, and runtime policy identities |
| observer cannot read a path | add the path explicitly to its `ObserverSpec` |
| stale structure request | rebuild it against the current structural epoch and generation |

For defects, report the package version, Julia version, reproduction program,
semantic and plan fingerprints, backend authorization, seed, and full
diagnostic—without private scientific data.

**Next:** use the [API by task](@ref user-authoring-api) or return to the
[example gallery](@ref examples-index).
