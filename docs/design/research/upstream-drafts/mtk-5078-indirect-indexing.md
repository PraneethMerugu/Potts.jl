<!--
P6.0br draft 3 of 4 (D-159). NOT POSTED. The maintainer reviews and posts it.
Target: a COMMENT on SciML/ModelingToolkit.jl#5078 ("Indexing an array parameter with a discrete
Int in a symbolic affect fails in mtkcompile (StableIndex typeassert)"). On 2026-10-07 it is OPEN
(last updated 2026-09-30, labelled bot-unreviewed). Its fix PR #5235 is OPEN, head
ChrisRackauckas-Claude/ModelingToolkit.jl@529f9b69.

CORRECTION TO mtk-native-plan.md §1 (3b) / §7 q10. q10's Symbolics-only line,
`build_function(J[τ[σ[1]], τ[σ[2]]], collect(σ), collect(τ), J)` → `UndefVarError: τ`, comes from
passing `collect(τ)`: the scalars τ[1..3] are arguments, but the array τ is not. Passing the arrays
whole (`build_function(ex, σ, τ, J)`) generates `J[τ[σ[1]], τ[σ[2]]]` and returns the right value.
So plain Symbolics handles indirect indexing, and the bug is in ModelingToolkit's codegen and problem
construction. The comment is written to that finding.

The text was machine-drafted. Add whatever AI-disclosure line you normally use. Verified on the PC
under `systemd-run --user --scope -p MemoryMax=16G`; ~/p6-0br-mwe/mwe3_indirect.jl,
mwe3_code.jl and mwe3_arr.jl. Three environments were used: latest registered, the workspace pin,
and PR #5235's head.
Everything below the line is the comment body.
-->

The same `StableIndex{Int}` typeassert also hits plain **equations** (no events) when an array
is indexed by an `Int` parameter. On #5235's head, the typeassert goes away and the next failure
appears: the generated RHS refers to the bare array symbol, which is not bound in the function.
Reproducer, using `complete` only:

```julia
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

@variables y(t) x(t)[1:3]
@parameters J[1:3] = [10.0, 20.0, 30.0] k::Int = 2 s[1:3]::Int = [2, 3, 1]

cases = [   # label => (system, u0, expected du)
    "D(y) ~ J[k]" => (System([D(y) ~ J[k]], t, [y], [J, k]; name = :a), [y => 0.0], [20.0]),
    "D(x[1]) ~ x[k]" => (System([D(x[1]) ~ x[k], D(x[2]) ~ 0, D(x[3]) ~ 0], t, [x], [k]; name = :b),
        [x => [1.0, 2.0, 3.0]], [2.0, 0.0, 0.0]),
    "D(x[i]) ~ x[s[i]] - x[i]" => (System([D(x[i]) ~ x[s[i]] - x[i] for i in 1:3], t, [x], [s]; name = :c),
        [x => [1.0, 2.0, 3.0]], [1.0, 1.0, -2.0]),
]
for (label, (sys, u0, expected)) in cases, init in (true, false)
    result = try
        prob = ODEProblem(complete(sys), u0, (0.0, 1.0); build_initializeprob = init)
        du = zero(prob.u0); prob.f(du, prob.u0, prob.p, 0.0)
        du ≈ expected ? "OK $du" : "WRONG $du, expected $expected"
    catch e
        "$(nameof(typeof(e))): " * first(split(sprint(showerror, e), '\n'))[1:min(end, 100)]
    end
    println(rpad(label, 26), "build_initializeprob=", rpad(init, 6), result)
end
```

Every case should print `OK`. What it prints instead:

| case | init | MTK 11.45.3 / MTKB 1.77.3 (also 11.45.1 / 1.77.0) | PR #5235 head `529f9b69` |
|---|---|---|---|
| `D(y) ~ J[k]` | true | `TypeError: expected Int64, got BasicSymbolic` (`StableIndex{Int64}` ← `get_possibly_indexed`, `atomic_array_dict.jl:173` ← `add_observed_equations!`, `problem_utils.jl:198` ← `InitializationProblem`) | `UndefVarError: J not defined in ModelingToolkitBase` |
| `D(y) ~ J[k]` | false | `UndefVarError: J` | `UndefVarError: J` |
| `D(x[1]) ~ x[k]` | true | same `TypeError` as the first row | `UndefVarError: x` |
| `D(x[1]) ~ x[k]` | false | `UndefVarError: x` | `UndefVarError: x` |
| `D(x[i]) ~ x[s[i]] - x[i]` | both | `UndefVarError: x` (the `System` and the `ODEProblem` both build, with either init setting; the error is at the first `f` call) | `UndefVarError: x` |

So #5235 fixes the lookup, as intended, and the remaining problem is codegen.
`generate_rhs(complete(sys_a); expression = Val{true})` on #5235's head contains:

```julia
__mtk_arg_2 = ___mtkparameters___[1]      # tunables, where J lives as J[1], J[2], J[3]
...
__mtk_arg_4 = ___mtkparameters___[3]      # the Int buffer, where k lives
local var"##cse#1" = J                    # <- free symbol: J is never bound as a whole array
local var"##cse#2" = __mtk_arg_4[1]       # k
local var"##cse#3" = var"##cse#1"[var"##cse#2"]
```

For the `x[s[i]]` case it emits `x(t)` the same way, as `local var"##cse#1" = x` applied to `t`,
instead of a view of `___mtkunknowns___`. A constant index is rewritten to the buffer slot. A
symbolic index needs the whole array bound to a view of its buffer (the tunable slice for `J`,
the `u` slice for `x`), and the codegen does not do that. That is presumably the same gap as
#5235's remaining `Invalid symbol table[1] for setsym`, on the affect side.

Plain Symbolics handles this when the arrays are passed whole:

```julia
using Symbolics
@variables σ[1:2]::Int τ[1:3]::Int J[1:3, 1:3]
f = build_function(J[τ[σ[1]], τ[σ[2]]], σ, τ, J; expression = Val{false})
f([1, 2], [1, 2, 3], [0.0 1 2; 1 0 3; 2 3 0])   # 1.0, correct
```

So what MTK needs is a binding: whenever an array symbol appears under a non-constant index,
bind it as a whole (`J = view(tunables, idxs_of_J)`, `x = view(u, idxs_of_x)`).

The use case is lookup tables indexed by discrete state. In our setting that is a contact energy
`J[τ[σ[i]], τ[σ[j]]]`, where `σ` maps sites to entities and `τ` maps entities to types. The
scalar affect in #5078 is the simplest member of that family. A test covering `J[k]` in an
equation, as well as in an affect, would keep the two paths from drifting apart.

Two side observations from `mtkcompile`. They may be separate bugs, and we did not reduce them
further:

- `D(x[1]) ~ x[k]` with `mtkcompile` and the default `build_initializeprob = true` gives the
  right `du = [2.0, 0.0, 0.0]`.
- With `build_initializeprob = false`, the same system fails with `MethodError: Cannot convert
  an object of type Missing to an object of type Float64`. A 2-D array diffusion system with no
  symbolic index does the same.

Versions:
- ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing 1.20.7,
  Symbolics 7.44.1, SymbolicUtils 4.49.0 and SciMLBase 3.57.0;
- ModelingToolkit 11.45.1, ModelingToolkitBase 1.77.0, Symbolics 7.41.1 and SymbolicUtils
  4.48.0;
- #5235 at `529f9b69`, with ModelingToolkitBase 1.77.2 from that tree.

All on Julia 1.12.6, x86_64-linux-gnu.
