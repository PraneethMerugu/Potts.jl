# LW-R2 external-extension author review

## Review identity and scope

- Product commit: `ee395bd2f70d210fe98a0fb748e6530824c50671`
- Product tree: `b5ad1e71d73251fa6f932c8d275be8d1910f65fd`
- Qualification artifact: `design/hardening/lw4-final-qualification-bundle`
- Validated evidence digest payload: `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`
- Reviewer role: fresh external extension author, using only the public declaration/lifecycle API for successful work and deliberately hostile internal method additions for boundary testing
- Review write: this memo only. I did not modify `LocalWorksets`, production code, qualification tools, or evidence.

I independently read the public authoring documentation and the central admission, preparation, execution-cache, world-age, generic-result validation, provider, and inspection implementations. I then authored fresh operations in separate Julia processes rather than reusing the package's test operation types.

## Concrete external-author experience

The public four-step lifecycle was sufficient without a `LocalWorksets` source edit:

1. A concrete isbits `DirectScale` operation with an independent output planned as `family = :direct` and produced `Int32[18, 12, 15]` through a permuted route.
2. A concrete `BufferedPair` operation returning two emissions per item under `deterministic(+, Int32(0))` planned as `family = :buffered` and produced `Int32[21, 12]`.
3. A concrete heterogeneous operation returned independent edge state, two combined force emissions, and a conditionally resolved candidate in one call. It planned as `family = :buffered`, reported two launches and `operation_invocations = :once_per_active_item`, and produced exact results: edge `Int32[105, 103, 101]`, force `Int32[3, -3]`, and winner `UInt32[10, 30, 0]`.

The declaration vocabulary was adequate for all three cases. Named routes, destination counts, semantic IDs, rank bounds, tie-break order, empty values, fixed emission arity, and combination identity remained explicit. Automatic workspace preparation worked for both buffered examples, so a normal extension author did not need lowering-specific scratch knowledge.

Inspection was useful at each lifecycle boundary. In particular, it made the direct/buffered lowering choice, launch count, per-port laws, provider identity, workspace ownership, poison state, and once-per-item heterogeneous invocation rule observable without synchronizing or reaching into a second evidence model.

## Invalid-result and diagnostic experience

Fresh hostile result types rejected before launch and before any destination mutation:

- A direct-independent operation whose branches returned `emit(Int32)` and `emit(UInt32)` rejected at `stage = :prepare`, `contract = :operation_result_form`, `expected = :concrete_named_tuple`, with the inferred union in `actual`.
- The same nonconcrete result on a combined/buffered declaration rejected under the same structured contract.
- An operation lacking `(item::Int32, reads, values)` rejected with `actual = Union{}` and the actionable hint `define (operation)(item::Int32, reads, values)`.
- A result with the wrong named port rejected with `contract = :operation_result_ports` and exact expected/actual name tuples.
- A heterogeneous result with a `Float32` rank for an `Int32` resolved declaration rejected at `stage = :prepare`, `contract = :operation_result_rank_value_types`, `port = :winner`, with exact expected/actual rank-value type pairs.

All direct, buffered, and heterogeneous destination arrays retained their sentinels after these failures. The errors are compact in `showerror` and expose stable machine-readable fields for tooling.

## Admission and opaque-host-execution boundary

The extension boundary is enforced centrally rather than by convention:

- `plan` resolves and verifies the package-owned exact `Tuple{LocalWork, Any, Any}` admission method, then invokes that exact signature. My more-specific external `_central_admission` method was never entered; the same declaration received the package's normal direct lowering.
- Lowering evidence, topology fingerprints, workspace validation/preparation, workspace enumeration, provider creation/calls, and execution dispatch all verify that the selected method belongs to `LocalWorksets` before invoking it.
- I installed an exact external `_execute_lowering!` method that would have overwritten the output with `99`. `run!` rejected it prelaunch with `the execution lowering implementation is not centrally admitted`; output stayed `Int32[-1, -1]`, `submitted` stayed zero, leases stayed empty, and the preparation was not poisoned.
- Preparation records both package-owned callbacks and the exact external operation method. A later method-table change is checked against those identities before a new submission. Already-submitted provider tails drain in the last trusted world, so hostile later methods cannot replace the mandatory wait and strand retained work.
- Provider/backend evidence is also package-owned and fail-closed. A declaration of combination or resolution semantics is not an authorization for atomics, a provider, device transfer, synchronization, allocation, or a lowering.

The intentionally external operation callable is, of course, executable scientific code: that is the extension point. It is passed as data to a centrally created KernelAbstractions kernel after its concrete call/result form has been validated. I found no route for an extension to smuggle a separate opaque host executor into planning, preparation, launch orchestration, or waiting.

## Findings

### P0

None.

### P1

None.

### P2

1. Generic `resolved` authoring has one misleading constructor diagnostic. When I supplied `value_type`, `empty`, `rank`, and `tie_break` but accidentally omitted required `maximum`, dispatch reached the retained compatibility spelling and reported `legacy resolved output requires capacity`. The failure is safe and immediate, and the documented examples include `maximum`, so this is not a correctness or freeze blocker. A future diagnostic should identify the missing generic `maximum` or disambiguate the compatibility overload without changing the API.

## Future extraction and adoption

The implementation is ready for later standalone extraction/adoption without asking extension packages to share scheduler or provider internals. The public extension unit is a small concrete callable plus ordinary immutable declarations; output validation is shared across direct and buffered/heterogeneous paths; provider/lowering implementations remain package-owned; and production `LocalWorksets` has no CorePotts, PottsToolkit, or ModelingToolkit dependency. The module-owned admission checks should transfer naturally with the package.

Adopters should continue to keep domain physics, RNG, transactions, and settlement outside `LocalWorksets`; use public declarations and `inspect`; and treat lowering/workspace record layout as inspected version-specific detail rather than an extension API. New device-provider adoption properly requires centrally reviewed capability/evidence additions rather than an extension self-authorization hook. The current qualified runtime claim remains CPU and Apple M1 Metal, not generic CUDA/ROCm support.

## Verdict

**PASS.** The external operation seam is usable for direct, buffered, and heterogeneous work, invalid external results fail closed with actionable structured diagnostics, and hostile external methods cannot authorize or replace host-side admission, lowering, provider, execution, or wait behavior. The one P2 is bounded constructor-diagnostic debt and does not block the LW-4 freeze.
