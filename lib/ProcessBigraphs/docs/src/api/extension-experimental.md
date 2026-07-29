# [Extension and experimental API](@id extension-experimental-api)

> **Support level:** qualified extension API for the listed protocol;
> everything else on this page is experimental internal beta.

Extension bindings are Julia-`public` and intentionally unexported. Adapter
modules should import exactly the names they implement:

```julia
import ProcessBigraphs
import ProcessBigraphs: AbstractEngineAdapter, AbstractEngineInstance,
    AbstractCompletionHandle, EngineCandidate, prepare_engine,
    stage_operation!, complete_operation!, validate_candidate,
    publish_candidate!, discard_candidate!
```

This makes the dependency visible in source and prevents protocol names from
crowding ordinary model authoring.

## Component protocol

```@docs
ProcessBigraphs.AbstractProcess
ProcessBigraphs.AbstractStep
ProcessBigraphs.AbstractObserver
ProcessBigraphs.ports
ProcessBigraphs.capabilities
ProcessBigraphs.semantic_version
ProcessBigraphs.semantic_parameters
ProcessBigraphs.invoke
ProcessBigraphs.observe
ProcessBigraphs.observer_semantic_version
ProcessBigraphs.observer_semantic_parameters
ProcessBigraphs.observer_continuation_schema
```

Component methods describe semantic declarations. Runtime caches, sessions,
and buffers must not appear in `semantic_parameters`.

## Engine declaration and operations

```@docs
ProcessBigraphs.AbstractEngineAdapter
ProcessBigraphs.AbstractEngineInstance
ProcessBigraphs.AbstractEngineOperation
ProcessBigraphs.AbstractCompletionHandle
ProcessBigraphs.EngineCapabilities
ProcessBigraphs.EngineDeclaration
ProcessBigraphs.IntervalAdvance
ProcessBigraphs.BoundarySolve
ProcessBigraphs.DiscreteBatch
ProcessBigraphs.EngineInputProjection
ProcessBigraphs.EngineInvocation
ProcessBigraphs.EngineCandidate
ProcessBigraphs.EngineEarlyReturn
ProcessBigraphs.EngineEventRequest
ProcessBigraphs.EngineFailure
ProcessBigraphs.projection_value
```

An invocation contains immutable projections and explicit resource
authorization. An adapter stages work privately, then returns a candidate;
only ProcessBigraphs decides whether and when that candidate may publish.

## Required call order

1. `prepare_engine` constructs implementor-owned execution state.
2. `stage_operation!` starts or stages a candidate without publication.
3. `complete_operation!` resolves the completion handle.
4. `validate_candidate` checks time, outputs, diagnostics, and declaration
   compatibility.
5. `publish_candidate!` atomically installs an authorized candidate.
6. `discard_candidate!` cleans up every rejected or failed candidate.

```@docs
ProcessBigraphs.prepare_engine
ProcessBigraphs.stage_operation!
ProcessBigraphs.complete_operation!
ProcessBigraphs.validate_candidate
ProcessBigraphs.publish_candidate!
ProcessBigraphs.discard_candidate!
```

If staging, completion, validation, authorization, or publication fails, the
previously published engine state remains authoritative. An adapter must make
`discard_candidate!` safe for every candidate it can stage.

Concrete sessions, solver integrators, workspaces, caches, buffers, streams,
tasks, and device allocations are never part of the extension contract.
