# Digitised figures of Merks et al. 2008 ("01b")

R.M.H. Merks, E.D. Perryn, A. Shirinifard, J.A. Glazier, "Contact-Inhibited Chemotaxis in De Novo and Sprouting Blood-Vessel Growth", *PLoS Comput Biol* 4(9): e1000163 (2008), doi:10.1371/journal.pcbi.1000163. These files contain numbers only. No figure images and no source PDFs are included.

The targets in `test/reproductions/01_merks_01b.jl` (P6.3f) are copied from these files, and its always tier checks that the two still agree.

| File | Figure (PDF page) | Curves | x | y |
|---|---|---|---|---|
| `fig05.tsv` | Fig 5 (p. 6) | CI | χcc/χcM, 0.01–0.99 | C at 10⁴ MCS, mean ± SD (error bars, n = 10) |
| `fig07.tsv` | Fig 7 (p. 8) | CI, noCI | J_cc | C at 5000 MCS |
| `fig08.tsv` | Fig 8 (p. 8) | CI, noCI | χcM | C at 5000 MCS |
| `fig09.tsv` | Fig 9 (p. 8) | CI, noCI | s | C at 5000 MCS |
| `fig10.tsv` | Fig 10 (p. 9) | CI128, CI1024, noCI128 | D (10⁻¹³ m²/s) | C at 5000 MCS |
| `fig12.tsv` | Fig 12 (p. 10) | ER50, ER200, EO200 | t (MCS) | C |
| `fig13.tsv` | Fig 13 (p. 10) | ER50, ER200, EO200 | t (MCS) | H − H0 (10⁸) |

ER and EO are the extension–retraction and extension-only chemotaxis modes, and the number is T.

**Columns.** `figure, page, panel, curve, x_name, x, x_unit, y_name, y, y_unit, sd, sd_source, unc_x, unc_y, note`.
- `sd` is the paper's spread: the error-bar half-length (Fig 5), or the grey ±1 SD curve read at that x (Figs 7–10, 12). `NA` means it was not read.
- `unc_x` and `unc_y` are our digitisation uncertainty, in the axis units.

**Method (2026-10-09, P6.3f test author).**
1. The figures are 150-ppi raster images embedded in the publisher PDF. They were extracted losslessly with `pdfimages -png`.
2. Each axis was calibrated from its tick marks, located to the pixel; the residual is under 0.5 px on every axis.
3. Fig 5 (error bars). Each bar is the longest dark vertical run within ±1 px of the bar's x. The mean is the run's midpoint and the SD is its half-length. Two readings were taken, one with a black threshold and one with a grey-inclusive threshold, and they agree to 0.002. At 0.77 the longest run is an inset's leader line, so the bar value from the black-threshold reading is used. The bar at 0.98 is found only by the grey-inclusive reading. Bars at 0 and 1 are hidden by the frame.
4. Line figures. Each point is a local linear fit through the centres of the dark (curve) pixel runs within a few columns of x, assigned to its curve by inspection. Legend, inset and label pixels are masked. Dashed-line gaps were bridged from neighbouring dashes, as noted in the `note` column. The read points were overlaid on the figures and checked by eye.
5. The SD curves (grey, dotted) were read at selected x from the grey pixel runs on either side of the mean curve. They carry about ±0.01 of reading error.

**Uncertainty.**
- On flat stretches `unc_y` is 0.005 in C (one pixel is 0.002–0.004).
- On steep stretches `unc_y` is larger (up to 0.03), because there it is the slope times `unc_x`.
- Fig 13 points are ±0.03–0.05 × 10⁸.
- Values marked "read at 4950" were extended to 5000 by the local slope.

**Readings to know.**
- Fig 10: the legend draws the 1024-cell curve solid, while the caption says dashed-dotted. The flatter of the two solid curves is read as the 1024-cell one, because the text says 1024-cell clusters sprout for D > 3·10⁻¹³ and 128-cell clusters do not.
- Fig 12: the curves move during the first ≈ 100 MCS, before any chemoattractant exists. This suggests the time axis includes the 100 relaxation MCS.
- Fig 13: up to ≈ 1100 MCS the ER50 and ER200 curves overlap.
