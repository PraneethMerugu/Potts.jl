# Reproduction 04: the Eq 2 screen at higher T, 2026-10-13 (no pass; the cliff is gone)

This is the pre-registered follow-up to `../eq2-screen-2026-10-13/` (spec 04 §5.5). It tests R3 (the frozen displacement form, `P64RShearedFoam`) at T ∈ {3, 5}, with J = 3. T = 5 is the lowest of the paper's Fig 3(d) temperatures. The maintainer approved it: "yes, run the higher-T screen".
- The runner is `../run_eq2_screen.jl --only r3h` (sha256 `5767bd5b…`), at commit 05ed9bae plus that runner.
- The frozen D-205 test is included unchanged as the gate.
- The 5 ordered foams were reused from the first screen's job cache. They are deterministic, and τ = 3.4472 reproduces exactly.

| Reading | Grid | Runs | Decision |
|---|---|---|---|
| R3 at T = 3 | κ_D190·2^(i/2), i = −16:2:14 (0.0098 to 320) | 240 | no κ_b (`consistency`); κ̂ = 0.22 (β = 0.01) and 0.31 (β = 0.05) |
| R3 at T = 5 | same | 240 | no κ_b (`off_target`); κ̂ = 0.10 and 0.18 |
| β = 0 control at T = 3 | κ_b = 0 | 15 | 0 of 15 yielded, 0 T1s |
| β = 0 control at T = 5 | κ_b = 0 | 15 | 0 of 15 yielded, 0 T1s |

The run used 24 threads on the PC, from 16:17 to 18:09. The controls show that neither temperature is confounded: with no drive, the ordered foam has no T1s within the caps (2¹⁴–2¹⁶ paper MCS).

## What the tables show
- **The pinning cliff is gone at T ≥ J.** At fixed β, t_first now falls smoothly with κ_b, roughly halving per doubling. No reading jumps from "no yield" to fast yield within one step, as every reading did at T ≤ 1.5.
- **At T = 3, the two targets nearly coexist.** β = 0.01 → 4300 and β = 0.05 → 420 paper MCS are met at κ_b ≈ 0.22 and 0.31, and both lie within ±25 % at their geometric mean, κ̂ ≈ 0.26.
  - The rule then fails on consistency: β = 10⁻³ has no T1 at all within 2¹⁶ paper MCS at κ_b ≤ 0.31.
  - The paper's ordered foam yields there at about 4.4–5.5·10⁴ MCS (ε_y = 1.10, Fig 11a).
  - The β = 10⁻³ onset needs κ_b ≈ 0.6 (2 of 3) to 1.25 (3 of 3).
- **At T = 5, the two targets separate.** κ̂ = 0.10 and 0.18 (ratio 1.7), so `off_target`. Here the response is close to linear: at κ_b = 0.31, β·t_first is nearly the same for β = 5·10⁻³, 0.01 and 0.05. So the paper's drop in ε_y at β = 0.05 is lost.
- **The shape in yield-strain terms.** ε_y ∝ β·t_first, normalised to β = 0.01. The paper's ordered points are at β = 0.001, 0.005, 0.01, 0.02 and 0.05 (1.13, 1.10, 1.11, 0.80, 0.43); 0.02 is omitted here:

  | β | paper (Fig 11a) | R3, T = 3, κ_b = 0.31 | R3, T = 5, κ_b = 0.31 |
  |---|---|---|---|
  | 10⁻³ | 1.02 | > 2.4 (no yield) | ≈ 2.5 |
  | 5·10⁻³ | 0.99 | 1.33 | 1.05 |
  | 0.01 | 1 | 1 | 1 |
  | 0.05 | 0.39 | 0.76 | 0.96 |

  - The paper has a rate-independent plateau at low β and a drop at high β.
  - At T = 3, R3 has the high-β drop, but ε_y keeps climbing as β falls (sub-threshold creep).
  - At T = 5, it is flatter at high β, but still climbs at 10⁻³.
  - No single temperature gives both the plateau and the drop.

## Conclusion
No pass under the pre-registered rule. With §5.4, this covers R1/R3 at T ∈ {0⁺, 0.5, 1.5, 3, 5} and R2 at T = 0⁺:
- below about T = J, a β-proportional per-copy bias pins at a threshold;
- above it, the bias creeps, with a yield strain that rises without bound as β falls.

The paper instead reports a yield strain that "remains almost the same" from β = 10⁻³ to 0.01 (p.5827, Fig 11a). That plateau is what a rate-independent, strain-controlled yield would give, and a force-type bias at any of these temperatures does not produce it. Our inference, which is not a ruling, is that the bulk shear in the paper acted more like an imposed deformation than a per-copy energy bias.

That is the sharpened F1: "How was the bulk shear applied: as the Eq 2 energy with γ(y) = β·y at T = 0, or by another means (for example, moving spins or imposing a displacement)?" Foam's bulk-shear claims stay provisional.
