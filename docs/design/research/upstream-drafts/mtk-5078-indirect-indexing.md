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
Finalized 2026-10-07 (finalization pass, not yet posted): #5078 still OPEN, one comment (the bot's
"Taking this"); #5235 still OPEN at 529f9b69. The "Invalid symbol table[1] for setsym" quote was
checked against #5235's body ("Not verified / remaining for #5078"). Dropped the mtkcompile
`Missing` side observation; it is unrelated to indexing, and draft 4 already reports it.
-->

The same `StableIndex{Int}` typeassert also hits plain **equations** (no events) when an array is
indexed by an `Int` parameter. Behind it is a second bug that already shows on released versions
with `build_initializeprob = false`, and that remains on #5235's head: the generated RHS refers to
the bare array symbol, which is never bound in the function. Reproducer, `complete` only:

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

Every case should print `OK`. Instead:

| case | init | MTK 11.45.3 / MTKB 1.77.3 (same on 11.45.1 / 1.77.0) | #5235 head `529f9b69` |
|---|---|---|---|
| `D(y) ~ J[k]` | true | `TypeError: expected Int64, got BasicSymbolic` (`StableIndex{Int64}` ← `get_possibly_indexed`, `atomic_array_dict.jl:173` ← `add_observed_equations!`, `problem_utils.jl:198` ← `InitializationProblem`) | `UndefVarError: J` |
| `D(y) ~ J[k]` | false | `UndefVarError: J` | `UndefVarError: J` |
| `D(x[1]) ~ x[k]` | true | same `TypeError` | `UndefVarError: x` |
| `D(x[1]) ~ x[k]` | false | `UndefVarError: x` | `UndefVarError: x` |
| `D(x[i]) ~ x[s[i]] - x[i]` | both | `UndefVarError: x` (`System` and `ODEProblem` build; the error is at the first `f` call) | `UndefVarError: x` |

So #5235 fixes the lookup, as intended, and what remains is codegen.
`generate_rhs(complete(sys_a); expression = Val{true})` on #5235's head contains:

```julia
__mtk_arg_2 = ___mtkparameters___[1]      # tunables, where J lives as J[1], J[2], J[3]
...
__mtk_arg_4 = ___mtkparameters___[3]      # the Int buffer, where k lives
local var"##cse#1" = J                    # <- free symbol: J is never bound as a whole array
local var"##cse#2" = __mtk_arg_4[1]       # k
local var"##cse#3" = var"##cse#1"[var"##cse#2"]
```

The `x[s[i]]` case is the same with an unknown: the code reads the free symbol `x` (and calls it
with `t`) instead of a view of `___mtkunknowns___`. A constant index is rewritten to its buffer
slot, but a symbolic index needs the whole array bound to a view of its buffer (the tunable slice
for `J`, the `u` slice for `x`), and codegen never emits that binding. This is presumably the same
gap as #5235's remaining `Invalid symbol table[1] for setsym` on the affect side.

Plain Symbolics handles it when the arrays are passed whole:

```julia
using Symbolics
@variables σ[1:2]::Int τ[1:3]::Int J[1:3, 1:3]
f = build_function(J[τ[σ[1]], τ[σ[2]]], σ, τ, J; expression = Val{false})
f([1, 2], [1, 2, 3], [0.0 1 2; 1 0 3; 2 3 0])   # 1.0, correct
```

So what MTK needs is: whenever an array symbol appears under a non-constant index, bind it as a
whole (`J = view(tunables, idxs_of_J)`, `x = view(u, idxs_of_x)`).

The use case is lookup tables indexed by discrete state. In our setting that is a contact energy
`J[τ[σ[i]], τ[σ[j]]]`, where `σ` maps sites to entities and `τ` maps entities to types; the scalar
affect in this issue is the simplest member of that family. A test for `J[k]` in an equation as
well as in an affect would keep the two paths from drifting apart.

Workaround for equations: `mtkcompile` scalarizes, and `D(x[1]) ~ x[k]` then gives the right
`du = [2.0, 0.0, 0.0]` (with the default `build_initializeprob = true`).

Versions: ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing 1.20.7,
Symbolics 7.44.1, SymbolicUtils 4.49.0, SciMLBase 3.57.0; also ModelingToolkit 11.45.1,
ModelingToolkitBase 1.77.0, Symbolics 7.41.1, SymbolicUtils 4.48.0; and #5235 at `529f9b69`
(ModelingToolkitBase 1.77.2 from that tree). Julia 1.12.6, x86_64-linux-gnu.
