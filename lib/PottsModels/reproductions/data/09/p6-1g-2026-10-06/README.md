# Reproduction 09: late-stage coarsening pass (P6.1g, D-151)

Not a verdict run. The frozen page, the model and the frozen tests are untouched.

## Plan (stated before any run; committed before launch)

Fixture: the page's FULL replicate. That is `graner_glazier_aggregate(n; seed = start_seed, margin = 60)`
with `GranerGlazier` defaults (T = 10), `SequentialCPM(; proposal = Moore(1))`, 1 paper MCS = 16 MCS,
and runs to 2×10⁴ paper MCS. We save at 10, 100, 200, 500 and every 500 from 1000 to 2×10⁴.
At each save we measure the page's way: a copy annealed at T = 0 for 2 paper MCS with the run's
energies (seed 1), with `dark_clusters` copied verbatim from the page, plus the isolation guard.

| Set | What | Replicates | Start seeds / run seeds |
|---|---|---|---|
| dist | page parameters | 30 | 2001–2030 / 12001–12030 |
| Tscan (a) | T ∈ {5, 7, 14, 20} (factors ½, 0.7, 1.4, 2 around 10) | 16 per T | 2001–2016 / 12001–12016 (paired with dist) |
| equalsize (b) | V_d = 38.73, V_l = 41.27 (per-kind targets, chosen so Δa ≈ 0 against the page's −2.9), T = 10 | 16 | 2001–2016 / 12001–12016 (paired) |
| aggsize (c) | n ∈ {500, 1500} cells, T = 10 | 16 per n | 2001–2016 / 12001–12016 |
| fresh | page parameters, fresh seed set (control on seed-set luck) | 20 | 5001–5020 / 15001–15020 |

None of these seeds was used before. The earlier runs used starts 1–16 and run seeds 1 (ensemble), 101–103 and 111–116.
The relaxed-versus-Voronoi start was already tested in D-151 (null), so scan (c) varies the aggregate size only.

Per replicate we record:
- t₉₀, the first save with the largest dark cluster ≥ 0.90 of dark cells (right-censored at 2×10⁴);
- the largest share and the cluster count at 10, 10², 10³, 10⁴ and 2×10⁴;
- F_dM and F_dl at 10⁴.

The pool is the 30 dist replicates plus the 22 earlier ones: P6.1f's 10, read only at 10, 10², 10³ and 10⁴, and the 12 runs of the D-151 diagnostic.

A candidate counts as explaining the gap only if one of its scan points meets both conditions:
- it moves at least one of the following by more than 2 SE from the T = 10 / n = 1000 baseline (dist):
  - the mean largest share at 10⁴, by enough to reach ≥ 0.90;
  - the fraction with t₉₀ ≤ 5000;
  - the mean F_dl at 10⁴, to ≤ 0.055 (paper 0.050 PRE, 0.040 PRL);
- the move goes toward the paper while the earlier V-PRE1 trajectory (F_dl at 10, 100, 10³) stays inside the page's envelope.

No other scan points or metrics will be added after seeing the data.
