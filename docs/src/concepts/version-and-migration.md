# [Version and migration guide](@id version-and-migration)

This manual targets PottsToolkit 0.1, CorePotts 0.1, MakiePotts 0.2, and Julia 1.12.6 on the current
development branch. Pin the package family together: a compatible solver does not imply that an
independently upgraded toolkit, visualization package, checkpoint, or experimental extension is
compatible.

## Before upgrading

1. Archive `Project.toml`, `Manifest.toml`, model and execution fingerprints, seeds, backend and
   numerical policy, observation declarations, and the exact checkpoint contract version.
2. Record the stable or experimental classification of every directly used public name.
3. Preserve a small deterministic smoke with a bounded expected statistic.
4. Upgrade in a branch or copied environment and retain the old environment until comparison is
   complete.

## After upgrading

1. Instantiate the pinned environment and run model validation.
2. Preflight the exact model, algorithm, backend, dimension, and scalar policy.
3. Run the deterministic smoke and compare fingerprints and typed observations.
4. Restore a checkpoint only when the compatibility report accepts its contract. Otherwise use an
   explicit import path and treat the result as a new run.
5. Re-run any qualification required by the claim. API compatibility alone does not preserve
   numerical or scientific equivalence.

## Stability determines the promise

| API class | Upgrade expectation |
|:--|:--|
| Stable user | Breaking changes require an intentional compatibility decision and migration note. |
| Stable extension | Protocol or conformance changes require an intentional compatibility decision and migration note. |
| Experimental | Names and contracts may change; pin exact revisions and expect source changes. |
| Internal export | No public migration promise; do not build user workflows around it. |
| Deprecated | Follow the named replacement and remove use within the stated transition window. |

The [Experimental API](@ref experimental-api) page is the live boundary; its contents must not be
inferred from export status alone.

## Current migration record

There is no version-specific stable-API migration recorded for this development snapshot. The
documentation redesign itself replaces stale page paths and untracked videos, not engine
semantics. No legacy-URL redirect is claimed before this snapshot is published. A release that
replaces previously published paths must add redirects where the host supports them or list the
changed paths in its release notes. Until then, use the task-oriented navigation in this manual.

If an upgrade fails, collect the evidence listed in [Troubleshooting](@ref troubleshooting) before
changing model defaults or substituting algorithms.
