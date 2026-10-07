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

*Definition used in the analysis:* t₉₀ is read from the 500 save on. Before about 200, the dark cells of a
50:50 mix still percolate through cell adjacency, so the largest share can exceed 0.90 at 10–100 before any sorting
(`t90_any` in `replicates.tsv` keeps the raw first save).

## Results (all 192 runs completed; the isolation guard held at every save; no cell was lost)

### 1. Distribution of t₉₀ at the page's parameters

The new runs are dist (30) and fresh (20), k = 50, saved every 500 paper MCS:

| | value |
|---|---|
| single (≥ 0.90) by 5000 | 20/50 = **0.40 ± 0.07** |
| single by 10⁴ | 26/50 = **0.52 ± 0.07** |
| single by 2×10⁴ | 38/50 = 0.76 ± 0.06 |
| t₉₀ median [IQR] | **8500 [1500, 20000]** |
| t₉₀ restricted mean (censored at 2×10⁴) | 9870; mean over those that reach it: 6671 |
| largest share at 10⁴ | mean 0.836 ± 0.027 |
| F_dl at 10⁴ | mean 0.0706 ± 0.0016, min 0.0471; ≤ 0.050 in 2 of 50; ≤ 0.040 in 0 |

Pooled with the 22 earlier runs (k = 72; P6.1f is read only at 10³ and 10⁴):
- single by 5000: 25/70 = 0.36 ± 0.06;
- single by 10⁴: 34/72 = 0.47 ± 0.06;
- t₉₀ median 12 000, IQR [2000, > 2×10⁴], over the 62 runs saved at least every 1000 paper MCS;
- largest share at 10⁴: 0.816 ± 0.022;
- F_dl at 10⁴: 0.0712 ± 0.0013. 2 of 72 are ≤ 0.050 (PRE) and 0 are ≤ 0.040 (PRL).

The two published runs fall in the bottom 4 of 74 values, which by exchangeability has a chance of ≈ C(4,2)/C(74,2) ≈ 0.002.

**Reading.** The paper's run is single from ≈ 5000. Our runs are single by 5000 36–40 % of the time, so in dark-cluster terms the paper run is unremarkable: it sits near our 40th percentile.

What fails is the frozen ensemble-mean bound:
- A 10-replicate page ensemble reaches a mean largest share ≥ 0.90 at 10⁴ with probability ≈ 0.075 (bootstrap over the pooled 72).
- The fresh 10-seed sets give 0.876 (5001–5010) and 0.824 (5011–5020).

The robust gap is the heterotypic fraction F_dl at 10⁴, not the time to a single cluster.

### 2. Scans (`scan.tsv`; Δ vs dist, two-sided permutation p; 16 replicates per point, dist 30)

| point | largest @10⁴ | frac t₉₀ ≤ 5000 | F_dl @10⁴ | F_dl @10 / 10² / 10³ (envelope: [.303,.39] / [.176,.275] / [.092,.166]) | Δa @10³ |
|---|---|---|---|---|---|
| dist (T 10, n 1000) | 0.826 ± 0.036 | 0.37 ± 0.09 | 0.0697 ± 0.0023 | .371 / .247 / .133 | −2.81 |
| (a) T = 5 | 0.674 ± 0.051 (−0.15, p .016) | 0.12 (−0.24, p .10) | 0.121 (+0.051, p < .001) | .387 / .297 / **.187 (outside)** | −2.82 |
| (a) T = 7 | 0.719 ± 0.043 (−0.11, p .07) | 0.00 (−0.37, p .008) | 0.097 (+0.027, p < .001) | .379 / .267 / .155 | −2.88 |
| (a) T = 14 | 0.904 ± 0.041 (+0.08, p .18) | **0.75 (+0.38, p .027)** | 0.064 (−0.006, p .10) | .366 / .235 / .123 | −2.73 |
| (a) T = 20 | **0.979 ± 0.021 (+0.15, p .004)** | **0.75 (+0.38, p .027)** | 0.068 (−0.001, p .73) | .362 / .230 / .124 | −2.75 |
| (b) equal sizes | 0.738 ± 0.038 (−0.09, p .12) | 0.12 (−0.24, p .10) | 0.075 (+0.005, p .11) | .373 / .248 / .136 | −0.16 |
| (c) n = 500 | 0.898 ± 0.042 (+0.07, p .22) | 0.62 (+0.26, p .13) | 0.080 (+0.010, p .02) | .363 / .244 / .136 | −2.63 |
| (c) n = 1500 | 0.814 ± 0.042 (−0.01, p .84) | 0.25 (−0.12, p .51) | 0.070 (+0.001, p .88) | .379 / .249 / .135 | −2.90 |
| fresh (page) | 0.850 ± 0.041 (+0.02, p .67) | 0.45 (+0.08, p .77) | 0.072 (+0.002, p .48) | .375 / .244 / .136 | −2.86 |

- **(a) T is a strong, monotone lever.** At T ≥ 14 the dark mass merges fast:
  - t₉₀ median is 500 at T = 14 and 1500 at T = 20, against 8500 at T = 10;
  - every T = 14 or T = 20 replicate is single by 2×10⁴;
  - the early V-PRE1 curve stays inside the two-run envelope.

  T = 14 and T = 20 therefore meet the pre-stated rule for the cluster clause. However, F_dl at 10⁴ does *not* move toward the paper (0.064 and 0.068, against ≤ 0.055 needed): a hotter run merges domains sooner but keeps rougher heterotypic interfaces.

  The paper states T = 10 with the same Hamiltonian, Moore(1) bonds counted once. T is a *cause* only if our temperature scale differs from the paper's by ≈ 1.5–2×. The sorting curves up to 10³ cannot tell T = 10 from T = 20 (both sit inside the envelope; PRE is closer to T = 10 and PRL closer to T = 20). So this is a sensitivity, not an identified cause. An independent check of the T scale is V-PRE7's T = 40 plateau and T = 80 disintegration, a pre-registered row not yet on the page. T = 5 leaves the envelope at 10³, which rules out the "paper double-counts bonds" reading (T_eff = 5).
- **(b) Equal sizes** removes the size difference (Δa −2.81 → −0.16) but does not speed coarsening. If anything it is slower (largest share −0.09, p = 0.12). The V-GG6 size difference is not the cause; the paper reports it too.
- **(c) Aggregate size.** 1500 cells changes nothing. 500 cells merge somewhat sooner, though not significantly, and raise F_dl at 10⁴ (more interface per cell). The paper's ≈ 1000 cells sit between them, so size is not the cause.
- **Fresh seeds** (5001–5020) are indistinguishable from dist on every metric (p ≥ 0.48). The seed set is not the cause: our model fails the frozen mean bound for ≈ 92 % of 10-seed sets.

### 3. Post hoc, descriptive: light inclusions (`light_inclusions.tsv`; the dist seeds re-run, 30/30 trajectories identical)

A light inclusion is a connected light cluster with no medium contact, i.e. trapped inside the dark mass.
- The last inclusion clears by 5000 in 19 of 30 runs (median 2500; the paper says ≈ 5000) and by 2×10⁴ in 26 of 30.
- F_dl at 10⁴ by state:

  | state at 10⁴ | runs | F_dl at 10⁴ | range |
  |---|---|---|---|
  | one dark cluster and no inclusion | 8 | 0.054 ± 0.002 | 0.047–0.065 |
  | one dark cluster with an inclusion | 3 | 0.071 | |
  | several dark clusters | 19 | 0.076 ± 0.002 | |

So most of the F_dl gap comes from the runs that are not yet fully sorted. A fully sorted run gives F_dl ≈ the PRE value of 0.050, while PRL's 0.040 is below every run. By 2×10⁴ the sorted runs reach 0.047–0.050.

## Conclusion

No candidate cause is clearly found, so V-PRE5 stays a reported deviation.
- The size difference, the aggregate size and seed-set luck are excluded.
- T is a lever, not a demonstrated cause: T ≥ 14 reproduces the paper's cluster timing within the V-PRE1 envelope, but the paper says T = 10, and T does not close the F_dl@10⁴ gap.
- At the page's parameters, the paper run's time to a single cluster (≈ 5000) is at our ≈ 40th percentile. The frozen ensemble-mean form of the bound is what fails (P ≈ 0.075 per 10-seed set), as D-151 anticipated.

## Files

| file | contents |
|---|---|
| `runs/*.tsv` | one file per replicate (192): every save, with bond fractions, dark clusters, isolation guard, mean areas by kind and alive counts; `incl_*` add light inclusions |
| `replicates.tsv` | per-replicate summary: t₉₀, t₉₀ from any save, t of count = 1, largest share and count at 10, 10², 10³, 10⁴, 2×10⁴, F_dl, F_dM, Δa, guard |
| `scan.tsv` | the scan table, with permutation p values |
| `pooled.txt` | the pooled distribution, bootstrap and fresh-seed ensembles, inclusion summary |
| `light_inclusions.tsv` | the post-hoc inclusion table |
| `provenance.toml` | commit, machine, processes and pinning, wall times, seeds, script hashes |
| `scripts/` | `replicate.jl`, `replicate_inclusions.jl`, launchers, job lists, `analyze.py` |
