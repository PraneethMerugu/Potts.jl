# Reproduction 15: F1 (the Potts.jl panel and banner) and F4 (the free-surface schematic), 2026-10-08 (P6.15h)

This is the record pre-registered by D-175. The frozen test is `lib/PottsModels/test/reproductions/15_openvt_f1_f4.jl` (sha256 `a562c449…`). It passes 120/120, both on the Mac and inside the PC's `GROUP=PottsModels` run.

- **Figure functions.** `PottsModels.openvt_f4_figure(σ, c)` and `PottsModels.openvt_f1_figure(frame; window = 64)` are public and documented in PottsModels.
  - Their methods live in the `PottsModelsMakieExt` extension, whose weak dependencies are Makie and MakiePotts. Without those two, PottsModels loads no Makie code.
  - F4 draws no cell outlines (D-156): one `pottsplot` with `boundaries = false`, plus only full-length lattice lines (a white site grid) and the pair dashes.
  - F1 follows the other frameworks' close-ups (D-185, which amends D-156, D-172 and D-175 for the consortium figures): cells coloured by area with `coolwarm`, scaled to the panel's own cell-area min–max, and thin black boundaries along the pixel edges between unlike ids (`PottsModels.openvt_colony_panel!`).

## F4: M Fig 4, lattice panel (`G:results/free_surface.tex:31-110`)

`plot_f4.jl` renders the 7×7 configuration transcribed in the frozen test. It reads the test's `p615h_fig4` from source and runs on the Mac in seconds.

| File | Contents |
|---|---|
| `fig4.png` | `openvt_f4_figure(σ, 1)`: cell i with 13 magenta (medium) and 25 amber (cell) dashes, so fᵢ = 13/(13 + 25) = 0.342. This equals `openvt_snapshot(u).f[1]` (G1) and the .tex's drawn dashes |
| `fig4_cells.png` | The same figure for each of cells i, i−1, i+1 and i+2, with f = 13/38, 5/13, 0/14 and 2/13. These equal `openvt_snapshot` for all four cells |

- **Matched to the .tex.** The figure uses the .tex's colours and style:
  - medium `ma!10` = RGB(236,236,236);
  - cell fills `ca!60`, `cb!60`, `cc!60` and `cd!60`, passed as the `CellIdentityEncoding` palette when σ has at most four cells (ids 1–4);
  - dashes in `m` = RGB(231,41,138) and `c` = RGB(255,192,0), with the `mydash` on/off pattern and length 2L = 0.5;
  - a white site grid, a black panel frame, and the bold title "Lattice models".
- **Left out on purpose.**
  - The .tex's black outline of cell i and its partial boundaries (D-156).
  - The in-panel cell name labels ("Medium", "Cell i", …). Their positions are specific to the transcribed crop.
  - The caption gives the counts as numbers ("fᵢ = 13 / (13 + 25) = 0.342") instead of the .tex's coloured "#" glyphs.

## F1: M Fig 1, the Potts.jl panel and banner (`G:results/introduction.tex:50-92`)

- **Run.** `run_f1.jl` ran at commit `c6ca4bc4` on the PC (praneeth-NucBox-EVO-X2, AMD Ryzen AI Max+ 395, Julia 1.12.6).
  - It used one thread (`julia -t 1`) pinned to `taskset -c 0-11,16-27`, under `systemd-run --user --scope -p MemoryMax=12G`, in tmux. The workspace's checks ran alongside it.
  - The run took 477 s, and the whole script 540 s.
- **Protocol.** The script loads every `P615F_*` constant and `p615f_*` function from the frozen F3/F8 test (sha256 `da7d145f…`), the same way `../f3-f8-2026-10-08/run_f3_f8.jl` does. It then runs `p615f_run(p615f_problem(1400, 10⁴), 15701, P615F_CASES.a)`: case (a) run 1, the D-173 protocol, and the record's problem.
- **Check against the record.** The rerun stopped `Terminated` at **MCS 11600 with N = 10001**. That equals case (a) run 1 in `../f3-f8-2026-10-08/runs.tsv` (11600, 10001); the script compares the two and stops on a mismatch.
- **State.** The figure shows that stopping state, which is the first state with N ≥ 10⁴ (`stop_at_cells`).
- **Window.** `openvt_f1_figure(renderframe(u; mcs))` shows the unchanged 64×64 block at lattice offset (976, 974).
  - The block is centred where the 45° ray from the colony centroid leaves the colony, with the colony at lower left and medium at upper right.
  - It holds 41 cells and 1792 medium sites.
  - The script checks that the plotted block equals the state's ownership.
- **Banner.** RGB(8,29,88) (the Q18 proposal), 5/45 of the panel high and 1/45 of the panel above it, with "Potts.jl" in white bold.
- **Colours (D-185).** Each cell is coloured by its area with `coolwarm`, scaled to the min–max of the areas of the panel's 41 cells (30–116 sites), on a white medium, with thin black pixel-edge boundaries between unlike ids, as in the CompuCell3D, TST and Artistoo closeups (Spearman(area, red−blue) 0.995, 1.000 and 0.825). The areas are those of the full state, not of the window: 17 of the 41 cells are cut by the window.
  - The scale limits (the panel's own min–max) are our provisional reading; the consortium does not state its closeups' limits (Q10).
  - The first version (D-175) coloured cells per identity without outlines; that ruling is superseded for this figure.
  - The 64-site window (about 8 cell diameters) is an estimate from the TST closeup.
- **Full-state areas (D-185).** `window.tsv` holds only the block, so `run_f1_areas.jl` reran the same state on the PC (commit `234cb9a2`, one thread, `taskset -c 0-5,16-21`, `MemoryMax=32G`, 513 s). It stopped `Terminated` at MCS 11600 with N = 10001 again, its block equals `window.tsv` site for site (owners and generations), and it wrote `window_cells.tsv` (id, generation, full-state area, A\*, the O5 `inhibited` flag, sites outside the window) with its provenance in `window_cells.toml`.

| File | Contents |
|---|---|
| `fig1.png` | the Potts.jl panel and banner, 45 mm at 10 px/mm, saved at 2×; rendered by `plot_f1.jl` with `openvt_f1_figure(block; areas)` from `window.tsv` and `window_cells.tsv` |
| `fig1_panel.png` | the bare Potts.jl panel (no banner): the same 64×64 block, colours and scale as `fig1.png`, `openvt_f1_figure(block; banner = false, areas)`. The submission package (P6.15j) ships it as `results/Potts.jl/closeup.png` (D-180 amendment) |
| `fig1_colony.png` | the whole 10⁴-cell colony at the stop in the same style (area on `coolwarm`, here scaled to the whole colony's min–max), with the panel's block shaded (an unstroked translucent square); rendered by `plot_f1.jl` from the state `run_f1_areas.jl` serializes (outside git). For orientation only |
| `window.tsv` | the panel's block: lattice site (x, y), owner id (0 = medium) and generation, 64² rows |
| `window_cells.tsv`, `window_cells.toml` | the block's 41 cells with their full-state area, A\*, `inhibited` flag and sites outside the window; the rerun's provenance (`run_f1_areas.jl`) |
| `meta.toml`, `provenance.toml` | case, seed, stop MCS and N, the record's values and the match, the window; commit, hashes of the test, protocol test, record, runner and extension, Manifest hash, machine, timing |
| `run_f1.jl` | the runner (PC). `F1_STATE` optionally serializes the full render frame outside git |
| `compose_f1.jl` | opt-in: with `OPENVT_MONOLAYER_REPO` set to a G clone (54f375f), M Fig 1's ten closeups and banners (colours from `colors.tex`) with the Potts.jl panel after Artistoo. The panel is rebuilt from `window.tsv`. The output goes to `OPENVT_F1_OUT` and is **not committed** |
| `run_f1_areas.jl` | the full-state areas rerun (PC, D-185); `F1_STATE` optionally serializes the state outside git |
| `plot_f1.jl` | renders `fig1.png` and `fig1_panel.png` from `window.tsv` and `window_cells.tsv` (Mac, seconds), and `fig1_colony.png` when `F1_STATE` is set (it first checks the state against `window.tsv`) |
| `plot_f4.jl` | the F4 renderer (Mac) |

No G file and no G image entered git. The composite was rendered once on the PC, in `~/potts-ci/p6-15h-impl-out/compose/`, for review only.

- **Composite: what to compare.** The consortium closeups show about 5–7 cell diameters across, and more colony than medium. Our rim-centred 64-site block shows roughly equal parts colony and medium.
- **Composite: what may change.** The window and its centring are pre-registered (D-175). A larger window, or a centre moved inward, would match the other panels' framing more closely. That needs a ruling before any change.
