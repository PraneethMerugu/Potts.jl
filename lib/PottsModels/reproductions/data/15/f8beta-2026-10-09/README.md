# P6.15k: the Figure 8 β colonies (OpenVT monolayer, 9 Oct 2026 draft)

M's new Figure 8, "Tissue Snapshots with Area Inhibition", shows one colony at 10⁴ cells per
framework and Table 1 multiple (1.1×, 2×, 5×, 10×, 20× the uninhibited time), at that
multiple's β threshold with γ = 0. Cells are coloured yellow (no inhibition) or red
(area-inhibited, a < β), with the colony's concave hull in black (D-211 R2, D-212).

Our row is at our Table 1 β values (`sweeps-2026-10-08/table1.tsv`). These colonies were not
kept by the sweeps record, so each is **replayed**: replicate 1 of the sweeps record's run at
that β, rerun from its seed (160 000 000 + 100 q + 1, q = β × 10⁴) with the sweeps test's
own job function. A run is a pure function of its seed, and every run below stopped at the
same MCS with the same cell count as its sweeps row, so each colony is one of the six runs
behind its Table 1 point.

## Protocol

- Model: `OpenVTReferenceMonolayer` with the Table S1 defaults, γ = 0, β as below.
- `SequentialCPM(; skip_interior = true, proposal = Moore(1))` (equal in law to
  `SequentialCPM()`, D-177, D-198) on a closed 1400² lattice with
  `edge_guard(5; terminate = true)`; stop at the end of the first MCS
  with ≥ 10000 cells; cap 210335 MCS (20 × 13.57 cycles), never reached.
- O5 of the final state: centroid and radius in R from the lattice centre, `inhibited` =
  inhibition code i > 0 (at γ = 0 that is area inhibition, a < β).

## Result

| Multiple | β | Seed | Stop (MCS) | Cycles | N | Inhibited | Share | Edge gap (sites) |
|---|---|---|---|---|---|---|---|---|
| 1.1× | 0.625 | 160625001 | 11389 | 14.70 | 10005 | 4965 | 0.496 | 297 |
| 2× | 0.9375 | 160937501 | 20771 | 26.80 | 10001 | 8758 | 0.876 | 281 |
| 5× | 0.9875 | 160987501 | 52027 | 67.13 | 10001 | 9449 | 0.945 | 254 |
| 10× | 1.007 | 161007001 | 103498 | 133.55 | 10001 | 9655 | 0.965 | 217 |
| 20× | 1.0212 | 161021201 | 203045 | 261.99 | 10000 | 9794 | 0.979 | 216 |

Every run equals its row of `sweeps-2026-10-08/runs.tsv` (stop MCS, N, return code).

## Files

| File | Content |
|---|---|
| `run_f8beta.jl` | the runner (evaluates the frozen test's job definitions) |
| `plot_f8_grid.jl` | the figure and its tables, from `f8/` and `runs.tsv` |
| `f8/Potts.jl_beta_<β>_<MCS>MCS.csv` | O5 of each colony: `x_pos`, `y_pos`, `radius_i` (R), `inhibited` (0/1) |
| `runs.tsv` | one row per run: multiple, β, q, k, seed, lattice, return code, stop MCS, N, capped, closest approach to the edge, inhibited cells, wall time |
| `fig8_grid.png` | the Potts.jl row of M's Figure 8 grid |
| `fig8_grid.tsv`, `fig8_hull.tsv`, `fig8_grid.toml` | per colony N, inhibited, the hull's vertex count B and C/C_circle (metrics.cpp's concave hull, concavity 1.5); the hull vertices; the figure's form |
| `meta.toml`, `provenance.toml` | protocol and provenance |

The panels carry no number: M's panel label quantity is unstated and on our open question
list (D-211 R5). C/C_circle of each colony is in `fig8_grid.tsv`.

Run at commit `97c326bf` on AMD RYZEN AI MAX+ 395 w/ Radeon 8060S, 5 threads, Julia 1.12.6,
24.2 min in all.
