# IC-SYM Symbolics evaluator feasibility sub-gate

Status: passed; adoption vetoed

Date: 2026-08-13

Decision: **defer or reject because net complexity does not improve**.

This is a bounded IC feasibility result, not a compiler redesign. It changes no
production evaluator, public API, fingerprint, dependency, checkpoint, or
LocalWorksets code. The disposable probes live outside the repository and are
not product artifacts.

## Preserved ownership

- PottsToolkit continues to own symbolic authoring, normalization, analysis,
  validation, resource proofs, structural identity, and lowering.
- CorePotts continues to own typed proposal/lifecycle contexts, trusted leaf
  access, before/after proposal views, semantic draws, evaluator execution,
  Hamiltonian source-order folding, admission, and checkpoints.
- LocalWorksets remains uninvolved in symbolic construction and continues to
  own only validated local execution and conflict mechanisms.

Symbolics and SymbolicUtils are not added to CorePotts or LocalWorksets.
PottsToolkit already directly depends on Symbolics. It does not directly depend
on SymbolicUtils or RuntimeGeneratedFunctions, and this sub-gate adds neither.

## Primary API facts

The installed qualification environment contains Symbolics 7.34.1,
SymbolicUtils 4.43.0, and RuntimeGeneratedFunctions 0.5.23. The probes use the
documented [`Symbolics.build_function`](https://docs.sciml.ai/Symbolics/stable/manual/build_function/)
entry point with:

```julia
expression = Val{true}  # inspectable Expr
expression = Val{false} # RuntimeGeneratedFunction
nanmath = false
cse = false
```

No simplify, CSE, fast math, sharding, threading, or SymbolicUtils rewrite is
used. The documented [RuntimeGeneratedFunctions contract](https://docs.sciml.ai/RuntimeGeneratedFunctions/dev/)
confirms that a retained RGF stores its expression and can be serialized,
whereas `drop_expr` releases that expression and cannot independently
reconstruct it in another process.

## What could actually disappear

The authoritative input would remain the analyzed normalized graph. Symbolic
generation cannot replace source identity, operation-transfer validation,
purity/domain proofs, resource footprints, affected anchors, state/workspace
layouts, context admission, descriptor construction, grouping, backend
evidence, structural fingerprints, or source-order contribution folding.

Only the following implementation region is even a candidate:

| Current region | Arithmetic island | Complete evaluator |
| --- | --- | --- |
| Pure `OperationExpression` interiors | Potentially generated from typed scalar inputs. | Potentially generated. |
| Literal embedding | Potentially generated. | Potentially generated. |
| `_bounded_static_operation` shaping | Could disappear only for generated pure interiors. | Could disappear. |
| Context/resource/state/workspace/proposal/lifecycle/draw access | Retained as trusted leaf evaluation. | Must be restated as generated accessor calls. |
| `StaticEvaluator` and descriptor ownership | Retained. | Requires a new callable-bearing evaluator and reconstruction contract. |
| Recursive trusted walker | Still required for contextual leaf subtrees and non-generated cases. | Could disappear only by reproducing its dispatch in generated expressions. |
| Public CompilerSPI evaluator vocabulary | Cannot be removed in this behavior-preserving gate. | Would require a compatibility and hostile-dispatch redesign. |

Consequently, adopting an island while retaining the present SPI creates two
evaluator representations. Removing the old one is outside IC and would break
existing extension contracts.

## Real-model inventory

The frozen LW-3 fixture was compiled with Volume, ContactEnergy, Elongation,
three explicit site Hamiltonians, a registered external Hamiltonian, ordinary
state and parameter reads, and the built-in proposal constraint. Its eight
proposal descriptors contain 106 concrete evaluator nodes in six expression
types:

| Source | Role | Nodes | Pure operation nodes | Scalar/trusted island inputs | Nodes still recursively evaluated inside trusted leaves |
| ---: | --- | ---: | ---: | ---: | ---: |
| 8 | proposal constraint | 12 | 5 | 3 | 4 |
| 9 | ContactEnergy | 55 | 20 | 12 | 24 |
| 10 | Elongation | 8 | 3 | 1 | 2 |
| 11--13 | site Hamiltonians | 5 each | 1 each | 1 each | 3 each |
| 14 | registered external Hamiltonian with parameter and state reads | 8 | 1 | 3 | 7 |
| 15 | Volume | 8 | 3 | 1 | 2 |

These counts describe node instances in one model, not removable source lines.
The generic recursive walker implements all of them with a small fixed method
set. Generating the 35 pure-operation instances therefore does not remove 35
implementations. It adds callable identity, typed input extraction,
serialization, reconstruction, inspection, and mixed-mode fallback machinery.

Source/destination context, current before/after proposal views, lifecycle
contexts, and semantic draws necessarily remain trusted CorePotts leaves.
Semantic-draw expressions remain wholly outside generated arithmetic because
the required exact draw and eager-evaluation ordering has not been separately
proved. Existing external-operation admission also cannot require authors to
implement arithmetic over Symbolics `Num` merely to retain an already valid
CorePotts callable.

## Disposable arithmetic-island result

A 21-input scalar island exercised Volume-like, ContactEnergy-like,
Elongation-like, parameter/state, source/destination context, boolean,
conditional, registered-Hamiltonian-like, and ordinary external pure
arithmetic. On CPU:

- Expr construction took 3.51 seconds cold and emitted 1,184 characters from a
  340-character symbolic expression;
- the subsequent RGF construction took 0.42 seconds;
- Expr-evaluated, retained-RGF, and dropped-RGF callables were inferred and
  returned the same `52.375f0` result for the representative case;
- warmed scalar calls allocated zero bytes;
- all three ran through a KernelAbstractions CPU kernel using the normal launch
  followed by one backend synchronization;
- Expr-evaluated and dropped-RGF values were isbits; the retained RGF was not
  isbits because it retained an `Expr`; and
- generated LLVM text measured 10,142 bytes for the Expr callable, 3,779 bytes
  for retained RGF, and 3,208 bytes for dropped RGF in this probe.

Those are encouraging mechanism facts, but they do not establish adoption.
The RGF variants introduce a hard choice: retain an inspectable/serializable
expression that is not isbits, or drop it to obtain an isbits value whose
reconstruction must occur from the authoritative graph. Direct use of
`drop_expr` would also require RuntimeGeneratedFunctions as an explicit
PottsToolkit dependency rather than access through Symbolics internals.

### Exact-order veto

The same required configuration fails exact ordered arithmetic. Constructing
`foldl(+, (x[3], x[1], x[2]))` produced the canonical symbolic expression
`x[1] + x[2] + x[3]`. For values
`Float32[1.0f8, -1.0f8, 0.375f0]`, CorePotts source order returns `0.0f0`, while
the generated function returns `0.375f0`.

`cse=false` and `nanmath=false` govern code generation, not the ordinary
Symbolics construction-time canonicalization already applied to `+`.
Hamiltonian contribution folding remains independently protected in CorePotts,
but operation arguments also use `OrderedFold` precisely to preserve their
compiled order. Treating every ordered add/multiply as an opaque trusted leaf
would preserve semantics, but eliminates most of the prospective island in
Volume, Elongation, site terms, and the registered Hamiltonian.

## Disposable complete-evaluator result

The stable numerical-variable path does not honestly represent an arbitrary
CorePotts context: a registered symbolic call rejects an `Any`-typed context
placeholder because the wrapper requires a real symbolic argument. A manually
constructed public `Symbolics.term` can emit a call over a nominally real token
and the resulting generic Julia function can accept a context object. That
probe worked, but its generated code contained a global call to the manually
provided accessor and required the return type to be restated in a second IR.

Production use would therefore require one of three unacceptable choices:

1. generated code calls public evaluator generics, reopening the hostile
   dispatch boundary that CorePotts' private compiled walker closes;
2. PottsToolkit reaches private CorePotts compiled accessors; or
3. CorePotts expands CompilerSPI with a generated-evaluator accessor ABI and
   PottsToolkit duplicates every context/result-type rule in symbolic terms.

The third option is the current evaluator rewritten as generated Expr
machinery. It is not materially smaller or clearer, and it expands rather than
consolidates the SPI. Complete-evaluator generation is rejected.

## Required-case disposition

| Case | Result |
| --- | --- |
| Volume, ContactEnergy, Elongation | Present in the real descriptor census; ordered arithmetic prevents exact replacement for Volume/Elongation. |
| Parameters and ordinary state | Present together in registered source 14; remain typed trusted inputs. |
| Source/destination context | Present in the proposal constraint and existing proposal-context qualification; remain Core-owned. |
| Current before/after views | Cannot move: affected-anchor energy evaluation constructs these CorePotts views around each descriptor. |
| Boolean constraints and conditionals | Representative island compiled and ran; this small region alone does not earn a second evaluator. |
| Registered external Hamiltonian | Present in source 14; its contextual operation remains a trusted leaf and its ordered multiplication cannot be translated ordinarily. |
| Registered external non-Hamiltonian | Generic pure arithmetic can compile, but accepted extensions are not required to accept `Num`; fail-closed fallback would preserve the recursive path. |
| Lifecycle-dependent operations | Use distinct trusted CorePotts contexts and evaluator storage; generated access would duplicate their ABI. |
| Semantic draw | Explicitly excluded until exact call/draw order is independently proved. |
| Hostile dispatch | Whole-evaluator calls would bypass or duplicate the existing exact compiled boundary; vetoed. |
| Fingerprints/checkpoints | Frozen graph can remain authoritative, but RGF reconstruction adds a new versioned artifact with no compensating deletion. |
| Real Metal | The exact probe was attempted, but Metal became unavailable after the preceding complete suite. No GPU claim is made. CPU semantic failure already vetoes adoption; a successful simple GPU kernel could not repair it. |

## Final ballot

| Option | Ballot | Reason |
| --- | --- | --- |
| Adopt arithmetic-island generation | **reject for the present architecture** | Exact ordered arithmetic fails; opaque ordered folds leave too little removable machinery and require mixed evaluators. |
| Adopt complete evaluator generation | **reject** | Recreates trusted context dispatch as generated IR, expands SPI, and weakens ownership/inspection. |
| Use bounded SymbolicUtils host rewrites | **reject** | No necessary closed rewrite was identified; the normalized analyzed graph already owns semantics and proofs. |
| Defer/reject because net complexity does not improve | **adopt** | Preserves the smaller typed evaluator and every existing boundary without adding dependencies or parallel architectures. |

The sub-gate may be reopened only if an order-preserving stable Symbolics route
can replace, rather than coexist with, a meaningful evaluator region while
retaining external-callable compatibility and exact CorePotts trust. Generated
code elegance or GPU compilation alone is not sufficient.
