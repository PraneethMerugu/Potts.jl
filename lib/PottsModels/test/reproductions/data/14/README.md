# Reference transcriptions for reproduction 14 (Fortuna et al. 2020, Biophys J 118:2801)

Inputs, not run outputs. Read by `reproductions/data/14/protocol.jl` (the
`fig5_displacement/` and `table2/` rows) and
`test/reproductions/14_fortuna_protocol_tests.jl`. Source: Fortuna et al. 2020, Biophys J
118:2801, Table 2 (p.2810) and Fig 5 (p.2808). Transcribed 2026-10-15.
The TSV reader takes the first line as the header and every other non-empty line as a row,
so the TSVs carry no comments. This file holds the notes.

## table2.tsv: Table 2, p.2810 (40 rows; columns R phi lambda S P D)

- Units as printed: R in lattice sites^(1/3), P in MCS, D in R_cell²/MCS, S dimensionless.
- Method: `pdftotext -layout` (it drops minus signs), with every value checked against a
  400 dpi render of the page (`pdftoppm -r 400 -f 10 -l 10`).
- The values are transcribed as printed, with no corrections. Only the notation is
  normalized so that `parse(Float64, ·)` reads it:
  - thousands commas are removed (16,840 → 16840);
  - typographic minus signs become ASCII;
  - the exponent digits are kept as printed (`3.93E-04`, `6.73E-02`);
  - four printed entries lack the "E": D `2.65–5` (R15 φ0.05 λ125), D `6.25–3` (R15 φ0.05
    λ175), D `2.83–4` and S `9.68–3` (R15 φ0.10 λ150). These are written as `2.65E-5`,
    `6.25E-3`, `2.83E-4` and `9.68E-3`.
- The last printed column, 2DP/(1−S), is not stored. Recomputing it from the stored S, P
  and D gives the following disagreements beyond rounding:

  | Set | Recomputed | Printed |
  |---|---|---|
  | R15 φ0.10 λ150 | 3.93 | 1.98 |
  | R15 φ0.20 λ150 | 0.48 | 0.69 |
  | R15 φ0.30 λ160 | 1.92 | 2.77 |
  | R10 φ0.20 λ150 | 3.66 | 3.17 |
  | R10 φ0.20 λ175 | 2.80 | 28.01 |

  The protocol treats all five rows separately: the first four take ×2 extra slack on P
  and D. For λ175, the printed D of 3.60E−4 looks like a ×10 typo for 3.60E−3, so that row's D
  is info only. All five rows are kept as printed.
  The other 35 rows agree to within the rounding of the printed column.

## fig5.tsv: Fig 5, p.2808 (59 points; columns R phi lambda disp se; R_cell units)

- **59 points, not 60.** Panel φ_l = 0.05 has no R = 10 marker at λ_F = 200: the black line
  ends at λ = 175, and the 6× zoom shows no hidden marker, line or error bar. This matches
  Table 2, which lists R10 φ0.05 only up to λ = 175. The protocol's `FIG5_SETS` therefore
  has 59 keys and `fig5_displacement/` has 59 points: there is no R = 10, φ_l = 0.05,
  λ_F = 200 marker. No row was invented.
- Source image: the embedded raster (JPEG, 1330×1322 px, 300 ppi), extracted with
  `pdfimages`. That is the native resolution, so a higher-dpi page render adds no detail.
  Pixels were read in pure Python, and ambiguous points were checked on 4× zooms.
- Axes: x is linear and y is log10. The panel frames are at x 163–705 / 779–1320 and
  y 15–564 / 639–1187 (image px). Tick calibration:
  - x: λ 100/150/200 at px 284.5/484.0/683.5 on the left panels and 900.0/1099.5/1299.0
    on the right panels (99.75 px per 25);
  - y on the top panels: 100/10/1 at px 16.5/219.0/421.0;
  - y on the bottom panels: 640.0/842.0/1044.5;
  - one decade is 202.25 px, and the minor ticks (2–9) agree to ±1 px.
- Reading. The bars are mean ± SE (caption: 5 replicas), so they are symmetric in linear
  units. For each point, the upper and lower cap rows (series color, about 20 px wide) were
  located, and then:
  - disp = (upper + lower)/2;
  - se = (upper − lower)/2.

  The marker-box center is an independent check. It agrees with disp within 1.8 % at 57 of
  59 points. The two exceptions are R10 φ0.05 λ175 (−3.1 %; the black square is half hidden
  by the red circle) and R15 φ0.30 λ125 (+3.9 %; the circle is partly occluded).
- Hidden caps, located on zooms or by bar continuity:
  - R15 φ0.05 λ100 lower (under the green triangle);
  - R15 φ0.05 λ150 lower (merged with the green upper cap);
  - R10 φ0.10 λ100 lower and R10 φ0.10 λ150 upper (end of a continuous bar);
  - R10 φ0.10 λ200 lower (y 215);
  - R10 φ0.20 λ125 lower (under the red circle);
  - R10 φ0.20 λ200 lower (y 836).
- Uncertainty: 1 px is 1.15 % in value. With the cap localization of ±1–2 px, disp is good to
  about ±3 % and se to about ±5 %. For the occluded-cap points above, allow about ±5 % on
  disp and ±10 % on se. Values are given to 3 significant figures.
