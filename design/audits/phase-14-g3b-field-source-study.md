# Phase 14 G3-B Wang/CC3D Field Source Study

Status: accepted source-derived splitting and stencil semantics; controlled Potts.jl fixtures are
the qualification mechanism; no live CC3D oracle required

Date: 2026-07-25

## Source identity

The study pins Wang source commit
`60ebcf013aafefdff39ebe566114ee79f2a6e54d` and CompuCell3D tag `4.2.5`, commit
`4ca1f2919a5da53111d2027d2e00b626aba1cd28`.

| Source | SHA-256 | Relevant symbols or lines |
|---|---|---|
| Wang radial XML | `50f2c66d58ff85532bad671d90e6a247a101444a86324cca2b486f5ff98a6ee9` | field declaration 91–126 |
| Wang steppables | `2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30` | uptake/calibration/publication 79–147 |
| `DiffusionSolverFE.cpp` | `f75f95843334a809af2a71f06d9486ddd839368455eded5462fd960a1537d130` | defaults 80–95; `Scale`, 136–183; periodic flags 255–272 |
| `DiffusionSolverFE_CPU.cpp` | `47cd9884780d9b964b432b7512006c591e0e40f54fcb0584583380d5c18de4ae` | constant concentration 346–448; `stepImpl`, 821–857; stencil 867–1275 |

## Decided source semantics

Wang declares a 256×256×1 `secretome` field with global diffusion coefficient 1, zero decay,
Medium constant concentration 1, and periodic X/Y PDE boundaries. These PDE boundaries are
independent of the no-flux Potts lattice.

For a square lattice, DiffusionSolverFE uses `maxStableDiffConstant=0.23`. `Scale` therefore
computes `ceil(1/0.23)=5` internal steps, divides diffusion by five, leaves constant concentration
unscaled, and records five extra calls per MCS. With unit `deltaT` and `deltaX`, each substep is the
Float32 forward-Euler four-neighbor update

`Cnew = C + 0.2*(Cleft + Cright + Cdown + Cup - 4C)`.

`stepImpl` applies boundary conditions, diffuses into scratch storage, swaps the arrays, and then
calls secretion functions on every internal substep. The Medium constant-concentration function
overwrites every Medium-owned site with exactly 1 after each diffusion substep. Thus a reset site
can influence a neighboring cell site on the next internal substep; a once-per-MCS reset is not
equivalent.

The z extent is one. The active diffusion geometry is the two-dimensional X/Y four-neighbor
stencil; Potts.jl represents the logical field as a matrix rather than storing CC3D's internal
singleton-z and ghost layers. This is a layout normalization, not a mathematical change.

## Coupled exchange

For source MCS 0:120, no uptake is published. For 121:209, Wang explicitly resets cell signal to
zero. At source MCS 210 it samples per-cell uptake, divides by volume, and calibrates a global
multiplier so the maximum signal is four. For source MCS 211 onward it repeats the uptake and
publishes the scaled signal. Under the source-to-target mapping these are target ranges 1:121
inactive, 122:210 reset, 211 calibrate, and 212:500 publish.

The field solve occurs before the registered Python exchange steppable. Potts.jl retains that
split as separate typed phases and stages field/cell/global writes atomically.

## Intentional normalizations

- Logical 256×256 matrix storage replaces CC3D's padded 256×256×1 array.
- Potts.jl fixes x-pair then y-pair grouping and uses preregistered Float32 tolerances instead of
  claiming compiler-level CC3D bit identity.
- CPU and portable kernels share the same five-substep arrays, reset timing, and publication ABI.
- Backend status and conditional commit make a nonfinite or invalid advance failure-atomic.

## Uncertainty register

1. CC3D OpenMP scheduling, compiler contraction, and installed binary flags are not pinned by the
   source archive, so final-bit equality is not claimed.
2. CC3D's padded memory layout and boundary-layer copy order are implementation details. Controlled
   impulse, periodic-edge, constant, and Medium-reset fixtures qualify the normalized logical
   result.
3. The inspected XML's 391-step stop is distinct from the preregistered 500-MCS closure workload;
   the latter extrapolates the same field law and schedule.

## Qualification mapping

- `lib/CorePotts/test/test_phase14_dynamic_state.jl` covers five-substep Medium reset, CPU/portable
  equality, stability rejection, nonfinite failure atomicity, publication, allocation, and
  exchange modes.
- `integration/conformance/test_phase14_wang_runtime.jl` exercises diffusion 1, decay 0, five
  substeps, periodic field boundaries, and the exact exchange windows through target MCS 500.

The CC3D source is the semantic authority. Potts.jl remains self-contained and is qualified by
source-derived controlled fixtures.
