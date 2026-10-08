<!--
P6.0br draft 1 of 4 (D-159). NOT POSTED. The maintainer reviews and files it.
Target: a NEW issue on SciML/ModelingToolkit.jl. A duplicate search on 2026-10-07
("mass matrix", "massmatrix", "calculate_massmatrix", "concrete_massmatrix", "mass_matrix memory",
issues and PRs) found nothing open on this. The nearest items are #957 (SDE mass matrices, unrelated)
and #1026 (2021, an earlier calculate_massmatrix optimisation).
The text was machine-drafted. Add whatever AI-disclosure line you normally use before filing.
Verified on the PC (Ryzen AI Max+ 395) under `systemd-run --user --scope -p MemoryMax=16G`;
scripts are in ~/p6-0br-mwe/ there (mwe1_massmatrix.jl, mwe4_field.jl).
Everything below the line is the issue body.
Finalized 2026-10-07 (finalization pass, not yet filed): MWE trimmed to a REPL-style
~/p6-0br-mwe/mwe1_trim.jl and re-run on latest and pinned (2 158 080 856 bytes allocated;
permuted form Matrix{Float64}, 5.1 GiB peak RSS). The scaling table still comes from the
per-process harness mwe1_massmatrix.jl. Duplicate search repeated on 2026-10-07, issues and PRs:
nothing new. #5242 touches codegen.jl but only the implicit residual, not the mass matrix.
-->

**Title:** `calculate_massmatrix` allocates a dense `n × n` matrix even when it returns `I`, so `ODEProblem` of an array ODE needs O(n²) memory

---

## Summary

Since #5148, `ODEProblem(complete(sys))` accepts whole-array differential equations without
scalarizing them, and the equations and generated code stay O(1) in the array length. Building the
problem still takes **8n² bytes**, because the mass matrix is built dense:

- [`calculate_massmatrix`](https://github.com/SciML/ModelingToolkit.jl/blob/fd0cbadb43dc273ef8d7e167d83a7236b394eec7/lib/ModelingToolkitBase/src/systems/codegen.jl#L739-L770)
  starts from `M = zeros(n, n)` (`n` = number of equation rows), even when it then returns `I` or a
  `Diagonal`. `isdiag(M)` and `M == I` each scan all n² entries too.
- If the rows are not in unknown order, `M` stays a dense `Matrix`, and
  [`concrete_massmatrix`](https://github.com/SciML/ModelingToolkit.jl/blob/fd0cbadb43dc273ef8d7e167d83a7236b394eec7/lib/ModelingToolkitBase/src/systems/codegen.jl#L779-L790)
  evaluates `ArrayInterface.restructure(u0 .* u0', M)`: at least one more dense `n × n` temporary.

At n = 32 768 the identity case allocates 8.03 GiB in `calculate_massmatrix`. A 256 × 256 diffusion
grid (n = 65 536, permuted rows) peaked at about 62 GB and was OOM-killed on a 64 GB machine.

## MWE

```julia
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

# n decays as array equations, `complete` only (the array-equation path of #5148).
# `permuted = true` writes the same ODE as two equations whose rows are not in unknown order.
function decay(n; permuted = false)
    @variables x(t)[1:n]
    eqs = permuted ? [D(x[2:n]) ~ -x[2:n], D(x[1]) ~ -x[1]] : [D(x) ~ -x]
    return complete(System(eqs, t, [x], []; name = :decay)), x
end
ModelingToolkit.calculate_massmatrix(decay(4)[1])  # compile first

n = 16_384
sys, x = decay(n)
@show @allocated ModelingToolkit.calculate_massmatrix(sys)  # 2.16e9 bytes = 8n², and it returns I

sys, x = decay(n; permuted = true)
prob = ODEProblem(sys, [x => ones(n)], (0.0, 1.0); build_initializeprob = false)
@show typeof(prob.f.mass_matrix) Sys.maxrss() / 2^30  # Matrix{Float64} (a permutation), ≈ 5 GiB
```

## Expected

The mass matrix of `D(x) ~ -x` is `I`; that of the permuted form is a permutation with `n`
nonzeros. Building either should take O(n) time and memory.

## Actual

Scaling, each `n` in a fresh process (`calculate_massmatrix`, then `ODEProblem`, on the same form;
baseline RSS after loading is about 1.1 GB), ModelingToolkit 11.45.3 / ModelingToolkitBase 1.77.3:

| n | `D(x) ~ -x`: allocated in `calculate_massmatrix` | peak RSS | permuted: allocated in `calculate_massmatrix` | peak RSS | `mass_matrix` (permuted) |
|---:|---:|---:|---:|---:|---|
| 1 024 | 0.008 GiB | 1.09 GB | 0.011 GiB | 1.12 GB | `Matrix{Float64}` |
| 4 096 | 0.127 GiB | 1.32 GB | 0.136 GiB | 1.47 GB | `Matrix{Float64}` |
| 8 192 | 0.505 GiB | 1.59 GB | 0.522 GiB | 2.64 GB | `Matrix{Float64}` |
| 16 384 | 2.01 GiB | 3.16 GB | 2.04 GiB | 7.30 GB | `Matrix{Float64}` |
| 23 170 | — | — | 4.06 GiB | 13.5 GB | `Matrix{Float64}` |
| 32 768 | 8.03 GiB | 9.50 GB | not run (above our 16 GB cap) | | |

- `calculate_massmatrix` allocates 8n² bytes in both forms, even when it returns `UniformScaling`.
- In the permuted form, peak RSS grows by about 3 × 8n² (`zeros`, `u0 .* u0'`, the restructured
  copy), and the `ODEProblem` carries a dense `n × n` `Matrix` for a permutation.
- ModelingToolkit 11.45.1 / ModelingToolkitBase 1.77.0 give the same numbers to within 1 %.

On a realistic case, 2-D diffusion on an N × N grid written as one interior array equation plus
four edge equations (so the rows are permuted), `ODEProblem(complete(sys); build_initializeprob = false)` gives:

| grid | n | as shipped: `ODEProblem`, peak RSS | with the sparse fix below |
|---|---:|---|---|
| 64² | 4 096 | 1.15 s, 1.46 GB | 0.42 s, 1.21 GB |
| 128² | 16 384 | 2.54 s, 5.37 GB | 1.35 s, 1.31 GB |
| 181² | 32 761 | 7.7 s, 17.6 GB † | — |
| 256² | 65 536 | 15–17 s, ≈ 62 GB, OOM-killed in 2 of 4 runs † | 4.63 s, 1.60 GB |
| 512² | 262 144 | not attempted | 25.5 s, 2.44 GB |

† ModelingToolkit 11.45.1 / ModelingToolkitBase 1.77.0. A profile at 128² put 201 of 427
`ODEProblem` samples in `calculate_massmatrix` and 82 in `concrete_massmatrix`.

## Proposed fix

Build the mass matrix from its nonzeros. Each differential row has exactly one `1`; each algebraic
row has none:

```julia
function calculate_massmatrix(sys::System; simplify = false)
    eqs = equations(sys)
    n = count_equation_rows(eqs)
    rows = Int[]; cols = Int[]; i = 0
    for eq in eqs
        if iscall(eq.lhs) && operation(eq.lhs) isa Differential
            x = only(arguments(eq.lhs))
            if SU.is_array_shape(SU.shape(x))
                for idx in SU.stable_eachindex(x)
                    i += 1; push!(rows, i); push!(cols, variable_index(sys, x[idx]))
                end
            else
                i += 1; push!(rows, i); push!(cols, variable_index(sys, var_from_nested_derivative(eq.lhs)[1]))
            end
        else
            _iszero(eq.lhs) ||
                error("Only semi-explicit constant mass matrices are currently supported. Faulty equation: $eq.")
            i += equation_row_count(eq)
        end
    end
    rows == cols || return SparseArrays.sparse(rows, cols, ones(length(rows)), n, n)  # e.g. a permutation
    length(rows) == n && return I                                                    # identity
    d = zeros(n); d[rows] .= 1
    return Diagonal(d)                                                               # DAE: 0 on algebraic rows
end

concrete_massmatrix(M::SparseArrays.SparseMatrixCSC; kw...) = M  # skip the dense `u0 .* u0'` path
```

Checked by evaluating both definitions into ModelingToolkitBase 1.77.3:

- On 4-element cases it returns `I` for `D(x) ~ -x`, the sparse permutation for the permuted form,
  and `Diagonal([1, 1, 1, 1, 0])` for `[D(x) ~ -x, 0 ~ z - sum(x)]`, each equal to the current dense
  result.
- Permuted MWE at n = 32 768: `calculate_massmatrix` allocates 94 MiB instead of 8 GiB;
  `ODEProblem` takes 2.15 s at 1.33 GB peak RSS, with a `SparseMatrixCSC` mass matrix.
- 2-D field: the right-hand column above, with `f = M * u′` checked against a hand-written
  stencil at every size.

`simplify` has nothing to do on constant 0/1 entries. If a dense `M` must be kept for
non-`Vector` `u0` types, filling `similar(u0, n, n)` from `M` would still avoid the `u0 .* u0'`
temporary.

## Related

- With `complete` (no `mtkcompile`), rows are packed in *equation* order, so unless the array
  equations follow the unknowns' memory layout, an explicit ODE gets a permutation mass matrix and
  explicit solvers refuse it. For example, `D(u[2:3]) ~ [1, 2]; D(u[1]) ~ 10; D(u[4]) ~ 20` gives
  `mass_matrix = [0 1 0 0; 0 0 1 0; 1 0 0 0; 0 0 0 1]`, while `mtkcompile` reorders the unknowns
  and gets `M = I`. Permuting the RHS rows (or the unknowns) on the `complete` path would keep
  `M = I` there too. Happy to split this into its own issue.
- Even with the fix, building the 2-D field is superlinear (25.5 s at 512², 113 s at 1024²);
  scaling data is on #5139.

## Versions

- ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing 1.20.7, Symbolics
  7.44.1, SymbolicUtils 4.49.0, SciMLBase 3.57.0 (latest registered on 2026-10-07).
- Also ModelingToolkit 11.45.1, ModelingToolkitBase 1.77.0, Symbolics 7.41.1, SymbolicUtils 4.48.0,
  SciMLBase 3.56.1.
- The code is unchanged on master `fd0cbadb` (2026-10-06).
- Julia 1.12.6, x86_64-linux-gnu, AMD Ryzen AI Max+ 395, 64 GB.
