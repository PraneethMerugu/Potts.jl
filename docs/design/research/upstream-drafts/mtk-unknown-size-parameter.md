<!--
P6.0br draft 2 of 4 (D-159). NOT POSTED. The maintainer reviews and files it.
Target: a NEW issue on SciML/ModelingToolkit.jl. A duplicate search on 2026-10-07
("ShapeVecT", "unknown shape", "Unknown shape parameter", "unknown size array parameter",
"variable length parameter", "Vector{Float64} parameter ODEProblem", in MTK, plus SymbolicUtils and
Symbolics) found nothing. The nearest item is #5259 (a binding with the wrong shape), which is
unrelated.

CORRECTION TO mtk-native-plan.md §1/§7 q7. The plan says an unknown-size parameter "fails at
ODEProblem". That holds only when ModelingToolkitBase is loaded without ModelingToolkit; the q7
probes used `using ModelingToolkitBase`. With `using ModelingToolkit`, `ODEProblem(complete(sys))`
works, and `remake` and `setp` to other lengths work too. What fails in both cases is `mtkcompile`.
Under ModelingToolkitBase alone, the default initialization system goes through ModelingToolkitBase's
own `mtkcompile`, which fails in the same way, so `ODEProblem` fails there unless
`build_initializeprob = false` is passed. The draft is written to that finding.

The unknown-size *unknown* (`@variables V(t)::Vector{Float64}`, `length(::Unknown)` at `System`) is
deliberately left out. It is a feature request (runtime-resizable state), not a bug, and belongs in
the population/operator RFC (INV §7.3 item 6) if that is ever sent.

The text was machine-drafted. Add whatever AI-disclosure line you normally use before filing.
Verified on the PC under `systemd-run --user --scope -p MemoryMax=16G`;
~/p6-0br-mwe/mwe2_final.jl and mwe2_probe.jl.
Everything below the line is the issue body.
Finalized 2026-10-07 (finalization pass, not yet filed): MWE already minimal (= mwe2_final.jl).
Added permalinks. ModelingToolkitTearing lives in JuliaComputing/StateSelection.jl
(lib/ModelingToolkitTearing); line 248 is unchanged on its main 2cc04c02. Its issues were searched
for ShapeVecT / Unknown shape too: nothing. The suggested fix is an untested sketch, and the body says so.
-->

**Title:** `mtkcompile` throws `TypeError: expected ShapeVecT, got Unknown` for an unknown-size array parameter (`@parameters w::Vector{Float64}`)

---

## Summary

`@parameters w::Vector{Float64}` creates a parameter of shape `Unknown(1)`, whose length is fixed
only by the value given at problem construction.

- On the `complete` path this already works end to end: `ODEProblem` builds, the RHS is right, and
  `remake` and `setp` to a *different* length work too.
- `mtkcompile` of the same system throws. Clock inference in ModelingToolkitTearing expands every
  array-shaped symbol with `SU.stable_eachindex`, which needs a known shape.
- With only ModelingToolkitBase loaded, `ODEProblem(complete(sys))` fails the same way, because it
  builds the initialization system with ModelingToolkitBase's `mtkcompile`, whose variable
  collection ([`systems.jl:249`](https://github.com/SciML/ModelingToolkit.jl/blob/fd0cbadb43dc273ef8d7e167d83a7236b394eec7/lib/ModelingToolkitBase/src/systems/systems.jl#L247-L253)) expands array symbols the same way.

## MWE

```julia
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

@variables x(t)
@parameters w::Vector{Float64}   # length not fixed: shape(w) == Unknown(1)

sys = System([D(x) ~ sum(w)], t, [x], [w]; name = :s)
prob = ODEProblem(complete(sys), [x => 0.0, w => [1.0, 2.0]], (0.0, 1.0))  # works; remake/setp to other lengths work too
simp = mtkcompile(sys)                                                     # throws
```

## Expected

`mtkcompile(sys)` returns a system equivalent to `complete(sys)` (there is nothing to simplify),
keeping `w` as one atomic parameter of runtime length, as the `complete` path already does.

## Actual

```
ERROR: LoadError: TypeError: in typeassert, expected SymbolicUtils.ShapeVecT, got a value of type Unknown
Stacktrace:
  [1] stable_eachindex
    @ SymbolicUtils/src/methods.jl:1033 [inlined]
  [2] (::ModelingToolkitTearing.InferVariableClosure)(var::SymbolicUtils.BasicSymbolicImpl.var"typeof(BasicSymbolicImpl)"{SymReal})
    @ ModelingToolkitTearing/src/clock_inference/clock_inference.jl:248
  [3] (::ModelingToolkitTearing.InferEquationClosure)(ieq::Int64, eq::Equation, is_initialization_equation::Bool)
    @ ModelingToolkitTearing/src/clock_inference/clock_inference.jl:358
  [4] infer_clocks!(ci::ModelingToolkitTearing.ClockInference{TearingState})
    @ ModelingToolkitTearing/src/clock_inference/clock_inference.jl:396
  [5] mtkcompile!(state::TearingState; ...)
    @ ModelingToolkit/src/systems/systemstructure.jl:147
  ...
 [11] mtkcompile(sys::System; ...)
    @ ModelingToolkitBase/src/systems/systems.jl:154
```

All outcomes (expected `du = [3.0]`; `[10.0]` after `remake` to length 4; `[15.0]` after `setp` to `[5, 5, 5]`):

| loaded | `ODEProblem(complete(sys))` | same, `build_initializeprob = false` | `remake` / `setp` to a new length | `mtkcompile(sys)` |
|---|---|---|---|---|
| `using ModelingToolkit` | OK | OK | OK | **TypeError** (above) |
| `using ModelingToolkitBase` only | **TypeError** at `systems.jl:249`, via `InitializationProblem` → `mtkcompile_initialization_system` → `__mtkcompile` | OK | OK | **TypeError** at `systems.jl:249` |

The same happens when `w` is used only inside a registered function
(`@register_symbolic mysum(w::AbstractVector)`, `w` marked `[tunable = false]`), so it is not
caused by `sum` being traced through `w`.

## Suggested fix (untested sketch)

Expand an array symbol only when its shape is concrete; otherwise keep it whole.

- [`clock_inference.jl:246-251`](https://github.com/JuliaComputing/StateSelection.jl/blob/ModelingToolkitTearing-v1.20.7/lib/ModelingToolkitTearing/src/clock_inference/clock_inference.jl#L246-L251) in ModelingToolkitTearing (JuliaComputing/StateSelection.jl):
  change the guard `if SU.is_array_shape(SU.shape(var)) end` to `if SU.shape(var) isa SU.ShapeVecT end`,
  so that an unknown-shape symbol falls through to `_ => return`, like any other non-clocked variable.
- [`systems.jl:247-253`](https://github.com/SciML/ModelingToolkit.jl/blob/fd0cbadb43dc273ef8d7e167d83a7236b394eec7/lib/ModelingToolkitBase/src/systems/systems.jl#L247-L253) in ModelingToolkitBase:

  ```julia
  if Symbolics.isarraysymbolic(v) && SU.shape(v) isa SU.ShapeVecT
      for i in SU.stable_eachindex(v)
          push!(_all_dvs, v[i])
      end
  else
      push!(_all_dvs, v)
  end
  ```

We have not checked whether later `mtkcompile` passes need the same guard.

## Why it matters

A parameter of runtime length is the natural way to pass a per-entity table (rates, positions,
lookup data) whose size depends on the data and not on the model, without rebuilding the system
for each size. `complete` already supports it, so this is the remaining step for anyone who needs
`mtkcompile`, e.g. a model with an algebraic equation.

## Versions

- ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing 1.20.7, Symbolics
  7.44.1, SymbolicUtils 4.49.0, SciMLBase 3.57.0 (latest registered on 2026-10-07).
- Also ModelingToolkit 11.45.1, ModelingToolkitBase 1.77.0, Symbolics 7.41.1, SymbolicUtils 4.48.0,
  SciMLBase 3.56.1, with the same outcome table.
- Both sites are unchanged on ModelingToolkit master `fd0cbadb` (2026-10-06) and StateSelection.jl
  `main` `2cc04c02`.
- Julia 1.12.6, x86_64-linux-gnu.
