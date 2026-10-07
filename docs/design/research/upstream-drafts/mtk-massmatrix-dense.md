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
-->

**Title:** `calculate_massmatrix` allocates a dense `n × n` matrix (and `concrete_massmatrix` builds `u0 .* u0'`), so `ODEProblem` of an array ODE needs O(n²) memory

---

## Summary

#5148 lets `ODEProblem(complete(sys))` take whole-array differential equations without
scalarizing them. The equations and the generated code then stay O(1) in the array length. But
building the problem still needs **8n² bytes** of memory, because the mass matrix is built dense:

- `calculate_massmatrix` starts from `M = zeros(n, n)`, where `n` is the number of equation rows
  (`lib/ModelingToolkitBase/src/systems/codegen.jl:744` on master `fd0cbadb`). That allocation
  happens even when the result is then reduced to `I` or a `Diagonal`. `isdiag(M)` and `M == I`
  each scan all n² entries as well.
- If the rows are not in unknown order (see below), `M` stays a dense `Matrix`, and
  `concrete_massmatrix` then evaluates `ArrayInterface.restructure(u0 .* u0', M)`
  (`codegen.jl:779-790`). That adds at least one more dense `n × n` temporary.

At n = 32 768 the identity case allocates 8.0 GiB inside `calculate_massmatrix`. At n = 65 536
(a 256 × 256 grid) the non-identity case reached about 62 GB of RSS and was OOM-killed on a 64 GB
machine.

## MWE

```julia
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

# n independent decays as one array equation; `complete` only (array-equation path, #5148).
# permuted = true writes the same ODE as two equations whose rows are not in unknown order.
function decay(n; permuted = false)
    @variables x(t)[1:n]
    eqs = permuted ? [D(x[2:n]) ~ -x[2:n], D(x[1]) ~ -x[1]] : [D(x) ~ -x]
    complete(System(eqs, t, [x], []; name = :decay)), x
end

n = parse(Int, get(ENV, "N", "8192"))
permuted = get(ENV, "PERMUTED", "0") == "1"
let (s, y) = decay(4; permuted)   # warm-up, so the numbers below are not compilation
    ODEProblem(s, [y => ones(4)], (0.0, 1.0); build_initializeprob = false)
end
sys, x = decay(n; permuted)
a_mm = @allocated M = ModelingToolkit.calculate_massmatrix(sys)
t_p = @elapsed prob = ODEProblem(sys, [x => ones(n)], (0.0, 1.0); build_initializeprob = false)
println("n=$n permuted=$permuted | calculate_massmatrix: $(round(a_mm / 2^30, digits = 3)) GiB allocated, ",
    "returns $(nameof(typeof(M))) | ODEProblem: $(round(t_p, digits = 2)) s, ",
    "mass_matrix::$(nameof(typeof(prob.f.mass_matrix))) | peak RSS $(Sys.maxrss() ÷ 2^20) MiB")
```

Each size was run in its own process, so "peak RSS" belongs to that size. The baseline RSS after
loading and warm-up is about 1.1 GB.

## Expected

The mass matrix of `D(x) ~ -x` is `I`, and that of the permuted form is a permutation matrix
with `n` nonzeros. Building either should take O(n) time and memory, so array ODEs on the
`complete` path scale the way their O(1) symbolic size suggests.

## Actual

ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3:

| n | `D(x) ~ -x`: allocated in `calculate_massmatrix` | peak RSS | permuted: allocated in `calculate_massmatrix` | peak RSS | `mass_matrix` type (permuted) |
|---:|---:|---:|---:|---:|---|
| 1 024 | 0.008 GiB | 1.09 GB | 0.011 GiB | 1.12 GB | `Matrix{Float64}` |
| 4 096 | 0.127 GiB | 1.32 GB | 0.136 GiB | 1.47 GB | `Matrix{Float64}` |
| 8 192 | 0.505 GiB | 1.59 GB | 0.522 GiB | 2.64 GB | `Matrix{Float64}` |
| 16 384 | 2.01 GiB | 3.16 GB | 2.04 GiB | 7.30 GB | `Matrix{Float64}` |
| 23 170 | — | — | 4.06 GiB | 13.5 GB | `Matrix{Float64}` |
| 32 768 | 8.03 GiB | 9.50 GB | (not run: above our 16 GB cap) | | |

- The allocation in `calculate_massmatrix` is exactly 8n² bytes in both forms, even when the
  return value is `UniformScaling`.
- In the permuted form, peak RSS grows by about 3 × 8n²: the `zeros`, `u0 .* u0'` and the
  restructured copy. The `ODEProblem` then carries a dense `n × n` `Matrix` for what is a
  permutation.
- ModelingToolkit 11.45.1 / ModelingToolkitBase 1.77.0 give the same numbers to within 1 %.

On the realistic case (2-D diffusion on an N × N grid, written as one interior array equation
plus four edge equations, so the rows are permuted), `ODEProblem(complete(sys);
build_initializeprob = false)` gives:

| grid | elements | as shipped: `ODEProblem`, peak RSS | with the sparse patch below |
|---|---:|---|---|
| 64² | 4 096 | 1.15 s, 1.46 GB | 0.42 s, 1.21 GB |
| 128² | 16 384 | 2.54 s, 5.37 GB | 1.35 s, 1.31 GB |
| 181² | 32 761 | 7.7 s, 17.6 GB (MTKB 1.77.0) | — |
| 256² | 65 536 | 15–17 s, ≈ 62 GB; 2 of 4 runs OOM-killed (MTKB 1.77.0) | 4.63 s, 1.60 GB |
| 512² | 262 144 | not attempted | 25.5 s, 2.44 GB |

A profile at 128² put 201 of 427 `ODEProblem` samples in `calculate_massmatrix` and 82 in
`concrete_massmatrix`.

## Proposed fix

Build the mass matrix from its nonzeros. Each differential row has exactly one `1`, and each
algebraic row has none:

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
```

Add `concrete_massmatrix(M::SparseMatrixCSC; kw...) = M` as well, so that the dense `u0 .* u0'`
path is not taken. Checked by evaluating these two definitions into ModelingToolkitBase 1.77.3:

- On 4-element cases it returns `I` for `D(x) ~ -x`, the sparse permutation for the permuted
  form, and `Diagonal([1, 1, 1, 1, 0])` for `[D(x) ~ -x, 0 ~ z - sum(x)]`. Each equals the dense
  result of the current code.
- On the permuted MWE at n = 32 768, `calculate_massmatrix` allocates 94 MiB instead of 8 GiB.
  `ODEProblem` takes 2.15 s, peak RSS is 1.33 GB, and `mass_matrix` is a `SparseMatrixCSC`.
- On the 2-D field, the equivalent patch gives the right-hand column of the table above, with
  `f = M * u′` checked against a hand-written stencil at every size.

- If a dense `M` must be kept for non-`Vector` `u0` types, building it as `similar(u0, n, n)`
  filled from `M` avoids the `u0 .* u0'` temporary.
- `simplify` has nothing to do for a matrix of constant 0/1 entries.

Two related points, which may deserve their own issues:

- With `complete` (no `mtkcompile`), rows are packed in *equation* order. So unless the array
  equations happen to follow the unknowns' memory layout, an explicit ODE gets a permutation mass
  matrix, and explicit solvers then refuse it. `mtkcompile` instead reorders the unknowns and gets
  `M = I`. For example, `D(u[2:3]) ~ [1, 2]; D(u[1]) ~ 10; D(u[4]) ~ 20` gives
  `mass_matrix = [0 1 0 0; 0 0 1 0; 1 0 0 0; 0 0 0 1]`. Permuting the RHS rows instead (or the
  unknowns, as `mtkcompile` does) would keep `M = I` on the `complete` path too.
- Even with the patch, construction of the 2-D field is superlinear: 25.5 s at 512² and 97 s
  (MTKB 1.77.0) at 1024². That is tracked separately in #5139.

## Versions

- Reproduced on ModelingToolkit 11.45.3, ModelingToolkitBase 1.77.3, ModelingToolkitTearing
  1.20.7, Symbolics 7.44.1, SymbolicUtils 4.49.0 and SciMLBase 3.57.0: the latest registered
  versions on 2026-10-07.
- Also reproduced on ModelingToolkit 11.45.1, ModelingToolkitBase 1.77.0, Symbolics 7.41.1,
  SymbolicUtils 4.48.0 and SciMLBase 3.56.1.
- The code is unchanged on master `fd0cbadb` (2026-10-06).
- Julia 1.12.6, x86_64-linux-gnu, AMD Ryzen AI Max+ 395, 64 GB.
