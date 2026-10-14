# Reproduction 04: the T1-neighbourhood check, 2026-10-13 (detector ruled out)

This is the pre-registered check of spec 04 §5.6, approved by the maintainer: "yes, run the T1 neighbourhood check". Each of the 75 runs is the frozen D-205 bulk-shear run: R1 at T → 0⁺, with the D-205 foams, τ = 3.4472, seeds and caps. T1s are counted on the same trajectory with two detectors:
- `vn1`: `VonNeumann(1)`, our current one;
- `no4`: `NeighborOrder(4)`, the 20-site shell of Eq 1.

The grid is κ_b = κ_D190·2^(i/2), i = −4, −2, 0, 2, 4 (0.62 to 10.0), times 5 β values times 3 replicates. The runner is `../run_t1_nbhd_check.jl` (sha256 `11288c7d…`, matching `provenance.toml`). It ran on 24 PC threads from 18:52 to 20:27, sharing cores with CI.

## Result
**Detector ruled out**, by the pre-registered reading.
- **No new yields.** In every one of the 45 runs where `vn1` records no T1 within the cap, `no4` records **no contact change at all** (`t1_total_no4 = 0`, `first_change_no4 = −1`). That covers all κ_b at β ≤ 10⁻³, and the lower κ_b at β = 5·10⁻³ and 0.01. The pinned foam never brings two non-adjacent bubbles within the 20-site shell, so its edges do not shrink towards a T1 at all.
- **Same yield times.** In the 30 runs where both detectors yield, t_first agrees to within 94 paper MCS, which is inside the one-window tolerance of 100 paper MCS. `no4` is never later and is usually 0–20 % earlier.
- **Different counts.** `no4` counts about 1.7× as many T1 events on average (range ≈ 1.2–3.2×). Near-contacts flicker in and out of the 20-site shell. This matters for the A-15 counting unit and for absolute N̄, but not for t_first or for any D-205 decision.

## Conclusion
The T1 neighbour relation does not explain the pinning. Under the paper's own interaction shell, the foam is just as stuck at low β. F1 stands as sharpened in spec 04 §5.5: the question is how the bulk shear was applied. The `vn1` default (§2.8) stays. The higher `no4` count is noted under A-15.
