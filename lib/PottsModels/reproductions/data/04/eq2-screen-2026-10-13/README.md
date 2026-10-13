# Reproduction 04: the Eq 2 screen, 2026-10-13 (a negative result)

This is the pre-registered screen of two alternative readings of Eq 2 under bulk shear (spec 04 §5.4). The maintainer lifted the D-210 hold for it. The runner is `../run_eq2_screen.jl` (sha256 `9405f7b9…`), at commit 05ed9bae, with the frozen D-205 test included unchanged as the gate.

The runs are the same as D-205's:
- the 5 ordered foams;
- τ = 3.4472, identical to D-205's;
- β ∈ {10⁻⁴, 10⁻³, 5·10⁻³, 0.01, 0.05};
- 3 replicates each, with the D-205 seeds and caps.

The frozen rule `p64kb_analyse` is applied unchanged to each table.

| Reading | Grid | Runs | Decision |
|---|---|---|---|
| R2, force on bubble centroids | κ_D190·2^(i/2), i = 0…30 (2.50 to 8.2·10⁴) | 465 | no κ_b (`pinning_cliff`) |
| R3, displacement form at T = 0.5 | i = −8:2:14 (0.156 to 320) | 180 | no κ_b (`pinning_cliff`) |
| R3, displacement form at T = 1.5 | i = −8:2:14 | 180 | no κ_b (`pinning_cliff`) |

The runs used 24 threads on the PC, from 13:28 to 16:09 (plus 82 minutes earlier on 8 threads). `decision.toml` and `provenance.toml` hold the decisions and the run details. Each `<reading>/scan.tsv` uses the D-205 columns.

## What the tables show
- **Every reading has the same threshold.** No run yields within the cap until the model drive κ_b·β passes a threshold. That threshold is about 0.01 for R3 at both temperatures (β = 10⁻³ needs κ_b ≥ 10–20; β = 0.01 needs κ_b ≥ 1.25–2.5). For R2 it sits at κ_b·β ≈ 0.6–0.8 in R2's own units.
  - Just past the threshold, t_first falls from "no yield" to a few hundred to a couple of thousand paper MCS within one √2–2× step of κ_b.
  - The β = 0.01 target of about 4300 MCS therefore sits inside the cliff for every reading.
- **Temperature softens the cliff but does not remove it.** At T = 1.5 (T/J = ½), β = 0.01 at κ_b = 1.25 gives about 1210 MCS, and β = 0.05 gives about 110. The ratio is 11, against the paper's ≈ 10.2, but both are about 3.6× too fast. One step down in κ_b (0.62), β = 0.01 never yields.
- **The consistency check fails the same way.** T1s at β = 10⁻³ need κ_b at least 20× the value that matches β = 0.05.
- **The paper says low T does not change the results qualitatively** (04b p.5823). In our model, T changes where the threshold sits, so this is consistent with the authors' implementation not having this threshold at all.

## Conclusion
A per-copy bias proportional to β depins at a threshold. That holds whether it acts on walls (R1, D-205) or on bubble centroids (R2), and at T up to J/2 (R3). The paper's smooth β dependence down to 10⁻⁴ therefore needs something these readings lack. Candidates are:
- a drive scale that is not proportional to β as Eq 7 states;
- a different bulk-shear implementation;
- or a temperature well above J/2.

None of these is inferable from the text. F1 goes to Dr Jiang, sharpened by this result (PI sheet). Further variants run only as pre-registered screens. The next candidate is R3 at higher T (the cliff softens from T = 0.5 to T = 1.5; the paper sweeps T up to 15 in Fig 3d).
