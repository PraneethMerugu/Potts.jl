# OpenVT monolayer manuscript: the Potts.jl contribution (draft)

This draft is the text Potts.jl contributes to the OpenVT monolayer benchmark manuscript:
- the "Implementation in Potts.jl" subsection;
- Potts.jl rows for Table 1 and Table S5;
- a table of Potts.jl-specific settings;
- the Code Availability entry.

Every number comes from the committed records in `lib/PottsModels/reproductions/data/15/` and
from `lib/PottsModels/src/openvt_reference.jl`.

---

## Implementation in Potts.jl

Potts.jl is an open-source Julia package for Cellular Potts models (MIT licence). A model is
written declaratively with the `@potts_model` macro: its kinds, parameters, per-cell variables,
lattice, copy neighbourhood, energy terms, growth rules and division rule. A symbolic layer
built on ModelingToolkit compiles the declaration into specialised update kernels. The same
declaration runs on CPU and GPU backends. All results reported here were computed on CPU.

The monolayer reference model is a direct transcription of the schema and Table S1
(`lib/PottsModels/src/openvt_reference.jl`):

```julia
@potts_model OpenVTReferenceMonolayer begin
    @structural_parameters begin
        lattice = (1400, 1400)
    end
    @kinds medium cell
    @parameters begin
        A₀ = 50.0
        λ = 2.0
        T = 20.0
        α = 50 / 775
        μ_X = 2.0
        σ_X = 0.4
        β = 0.0
        γ = 0.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @variables begin
        A_star(cell) = A₀
        X(cell) = 0.0                  # 0: not drawn yet (drawn at the first MCS)
        f(cell) = 1.0
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - A_star)^2
        contacts => J[kind, kind′]
    end
    @before_mcs X ~ ifelse(Pre(X) > 0, Pre(X), randn(μ_X, σ_X; lower = 0.0))
    @after_mcs begin
        f ~ ifelse(count(true for _ in contacts) > 0,
            count(kind′ == medium for _ in contacts) / count(true for _ in contacts), 1.0)
        A_star ~ ifelse((volume / Pre(A_star) >= β) && (f >= γ), Pre(A_star) + α, Pre(A_star))
    end
    @divide cells(cell) when = volume >= X * A₀, along = RandomPlane(), A_star => Split(),
        X => randn(μ_X, σ_X; lower = 0.0)
    @sweep Metropolis(; temperature = T)
end
```

**Dynamics.** One Monte Carlo step (MCS) is N copy attempts, where N is the number of lattice
sites.
- Each attempt picks a target site uniformly at random and a source site uniformly among its
  eight Moore neighbours.
- It accepts the copy with the Metropolis probability of Eq. (9) at T = 20.
- Adhesion (Eq. 10) is summed over the same eight-site Moore neighbourhood, once per unlike
  pair. Energies are real-valued.
- In the long sweep runs, attempts on sites whose whole neighbourhood has a single owner (cell
  or medium) are skipped and accounted for exactly. Such attempts can never change the lattice,
  so the dynamics are statistically identical to the plain sweep.

**Order within an MCS.**
1. Any cell without a division threshold draws its Xᵢ.
2. The copy sweep runs.
3. Each cell updates its free-surface fraction fᵢ: its Moore cell–medium pairs over its Moore
   unlike pairs, as in Fig. 4.
4. A cell grows only if Aᵢ/A\*ᵢ ≥ β (type 1) and fᵢ ≥ γ (type 2). Growth uses the updated fᵢ,
   and it raises the preferred area by α = A\*(0)/(5T) = 50/775 px.
5. Division is checked.

One cell cycle 5T is therefore 775 MCS.

**Division.** A cell divides when its actual area reaches Xᵢ·A\*(0).
- The cut is along a uniformly random line through its centroid.
- Each daughter takes half of the mother's preferred area and draws a new Xᵢ ~ N(2, 0.4²). Draws
  of Xᵢ ≤ 0 are redrawn.
- Setting σ_X = 0 gives the deterministic mode Xᵢ ≡ 2. Fig. 3 shows both the deterministic mode
  and σ_X = 0.4.

**Initial state and domain.**
- A single disc-shaped cell of radius R = √(A\*(0)/π) at the centre of a closed square lattice.
  The lattice is 400² for the 1000-cell runs, 1400² for 10⁴ cells and 1800² for the γ sweep.
- A guard stops any run in which a cell comes within five sites of the edge. No run triggered
  it: the closest approach was 33 sites.
- The unbounded plane of the schema is therefore approximated by a lattice the colony never
  reaches.

**Analysis.** The DATA ANALYSIS quantities (Categories 1–3, Figs. 3 and 9) are computed by a
Julia port of the consortium's `metrics.cpp`. It is checked against `metrics.cpp` built with
`-ffp-contract=off` on the consortium's own centroid files.
- **Agreement.** It gives identical results on 53 of 54 frames.
- **Convex-hull sort.** On frames where the outcome of `metrics.cpp`'s convex-hull sort depends
  on rounding, the port uses exact orientation tests. It reproduces the result of the reference
  build, independent of sort order.
- **The remaining frame.** It differs only through the concave-hull candidate pruning of
  `concaveman`. There the port equals `metrics.cpp` with that pruning disabled.

**Calibration.** The relaxation tests of Fig. 2 reproduce the Table S1 time scale. With 100
replicates per λ, the fitted T(λ) is 297, 156, 111 and 77 MCS for λ = 1, 2, 3 and 5 (Table S5).
That is within 3% of the consortium values. The choice λ = 2 of Table S1 is used throughout.

Table S1 lists the simulation parameters. Table S6 gives the Potts.jl-specific settings.

## Implementation in Potts.jl (checkerboard)

The second Potts.jl entry runs the same `OpenVTReferenceMonolayer` declaration, parameters and
MCS clock under the package's parallel `CheckerboardCPM` algorithm, on a GPU (AMD, ROCm via
KernelAbstractions).
- **Colouring.** Lattice sites are coloured so that sites of one colour lie outside each other's
  read and write neighbourhoods. One MCS visits every site once, colour by colour in a random
  order.
- **Within a colour.** All sites propose in parallel, with a uniform Moore source and the
  Metropolis rule of Eq. (9).
- **Conflicts.** Accepted copies claim the cells they touch with a random priority, and a copy
  commits only if it wins all its claims, so every cell changes at most once per colour.
- **Per-cell areas and contacts** are updated between colours.

The time scale T was calibrated separately on the 1D chains (Table S5 row "Potts.jl
(checkerboard)") ⟨value to be filled from the checkerboard calibration record⟩. Its seeds are
disjoint from the sequential entry's.

The differences from the sequential entry come from the update order, from the per-cell totals
lagging within a colour, and from conflicting copies being dropped. Each difference larger than
the seed-to-seed spread is listed with its cause in ⟨table to be filled from the
characterisation record⟩.

---

## Table rows

**Table 1 (inferred inhibition thresholds), Potts.jl row.**
- Thresholds are relative to the 13.57 × 5T reference.
- They come from 160 sweep runs, with the bracket ends topped up to 6 replicates.
- Each is the sampled value whose time is nearest the target.

| | 1.1 | 2 | 5 | 10 | 20 |
|---|---|---|---|---|---|
| β | 0.625 | 0.9375 | 0.9875 | 1.007 | 1.0212 |
| γ | — | — | 0.1625 | 0.5375 | 0.7625 |

Notes:
- **The "—" entries.** The smallest nonzero γ sampled, γ = 10⁻⁴, already takes 58.8 × 5T to
  reach 10⁴ cells. That is well past both the 1.1× (14.93) and 2× (27.14) targets. The step from
  γ = 0 (14.9 × 5T) to γ = 10⁻⁴ passes both targets at once, so no sampled γ lies near them.
- **Uninhibited time.** The Potts.jl uninhibited model reaches 10⁴ cells in 14.945 × 5T on
  average (range 14.48–15.31), 1.10× the 13.57 × 5T reference. Potts.jl divides on the actual
  area as the schema specifies. The released TST model divides on the target area
  (sbr-shakibi/Tissue-Simulation-Toolkit@7ae1636, `src/models/openvt-monolayer-type1-tst.cpp:169`),
  which plausibly accounts for the faster growth past 10³ cells there.

**Table S5 (λ optimisation), Potts.jl row.** 100 replicates per λ.

| λ | T (MCS) | MSE |
|---|---|---|
| 1 | 297 | 1.28 × 10⁻³ |
| 2 | 156 | 1.02 × 10⁻³ |
| 3 | 111 | 4.06 × 10⁻³ |
| 5 | 77 | 1.05 × 10⁻² |

**Table S6 (new): Potts.jl-specific settings.** These settings are not in Table S1.

| Setting | Value |
|---|---|
| Copy neighbourhood | Moore (8 sites), uniform |
| Adhesion and free-surface neighbourhood | Moore (8 sites) |
| Attempts per MCS | N = number of lattice sites |
| Acceptance | Metropolis, ΔH ≤ 0 always accepted |
| Lattice | closed square: 400² (10³ cells), 1400² (10⁴ cells), 1800² (γ sweep); edge guard 5 sites |
| Initial cell | disc of radius R = √(50/π) ≈ 3.99 px (52 sites) |
| Division plane | uniformly random through the centroid |
| X draw | N(2, 0.4²), redrawn if ≤ 0; σ_X = 0 for the deterministic runs |
| Order within an MCS | X draw, copy sweep, fᵢ update, growth, division |
| Output cadence | MCS 0, every 39 MCS, and the stop |
| Replicates | Fig. 2: 100 per λ; Figs. 3 and 5: 100; Fig. 9: 10 per case; Fig. 6: 160 runs across both sweeps; Figs. 7 and 8: one colony per threshold |

---

## Code Availability (Potts.jl entry)

> Potts.jl is available at https://github.com/PraneethMerugu/Potts.jl under the MIT licence.
> - The monolayer model is `OpenVTReferenceMonolayer` in `lib/PottsModels/src/openvt_reference.jl`.
> - The scripts, seeds, per-run data and provenance for every figure are in
>   `lib/PottsModels/reproductions/data/15/` at commit ⟨to be fixed at submission⟩.
> - The submitted files are generated from these records by
>   `PottsModels.openvt_submission_package`.
