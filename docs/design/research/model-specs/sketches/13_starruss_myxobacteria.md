# 13 — Starruß et al. 2007 myxobacteria: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** segmented rod cells with propulsion along the rod axis; collective migration
  controlled by the aspect ratio κ.
- **Paper:** J. Starruß, Th. Bley, L. Søgaard-Andersen, A. Deutsch, *J. Stat. Phys.* **128**
  (2007) 269–286 (no code).
- **Spec:** [`../13_starruss_myxobacteria.md`](../13_starruss_myxobacteria.md). Decisions Y1–Y6
  in README §4.10. Build step 6 (ROADMAP P6.6).
- **Date:** 2026-09-30.

Tags: `# [R#]` means a planned roadmap feature, and `# [NEW]` means a feature not on the
roadmap. Lines without a tag use syntax that exists today (`src/vocabulary.jl`,
`src/macro.jl`, AUTHORING §§1–12 "implemented").

## 1. Sketch

```julia
using Potts

@potts_model StarrussMyxobacteria begin
    @structural_parameters begin
        lattice = (256, 256)    # UNSPECIFIED (13 §3 L_x × L_y, §7 item 5): placeholder
        s = 8                   # segments per rod, 'xanthus' (13 §3, Table I). κ ≈ 0.86 s is a hypothesis (13 §2.8, Y6)
        unit_θ = true           # Y1: θ is the normalised chord (default); false gives the raw chord (13 §7 item 1)
    end
    @kinds medium segment
    @parameters begin
        A    = 12.0             # target segment area (13 §3, Table I)
        D    = sqrt(12.0)       # target COM spacing D = √A (Table I)
        λ    = 0.7              # per-segment area strength (Table I; Eq 5 term 2)
        ζ    = 35.0             # length sensitivity (Table I; Eq 4)
        ξ    = 300.0            # curvature sensitivity (Table I; Eq 3)
        ω    = 0.5              # propulsion strength (Table I; Eq 10)
        kT   = 0.8              # temperature (Table I)
        J_SS = 0.3              # adjacent segments of one rod (Eq 6, Table I)
        J[kind, kind] = [0.0 1.0; 1.0 3.0]   # J_CM = 1, J_CC = 3 (Eq 6, Table I)
    end
    @variables begin
        ν(cell) = 0.0           # segment index: 1 = head … s = tail (13 §2.1, Eq 1)
        prev(cell)::CellRef     # segment ν − 1 (0 at the head)                      # [R6]
        next(cell)::CellRef     # segment ν + 1 (0 at the tail)                      # [R6]
        pinned(cell) = 0.0      # 1 freezes a segment (Fig 3 snake test; mechanism UNSPECIFIED, 13 §7 item 9)
    end
    @lattice Lattice(lattice; geometry = Hexagonal(), boundary = Periodic(),
                     neighborhood = Hex(2))       # "second-nearest" = shells 1 + 2, 12 sites (13 §2.5; Y3)
    @relations proposal = Hex(1)                  # copies from the 6 nearest neighbours (13 §2.5)
    @relationship chain(cell, cell) capacity = 2  # consecutive segments of a rod (13 §2.1)

    # 1/R_curve of three COMs (Eq 2): 2 sin∠ / |S_a − S_b|, angle at the pivot
    inv_R = 2 * sin(angle) / norm(separation(a, b))                                  # [R9] [NEW separation]

    @energy begin
        cells(segment) => λ * (volume - A)^2                                         # Eq 5 term 2
        contacts => ifelse((cluster[owner] == cluster[owner′]) &&                    # Eq 6: same rod …
                           (abs(ν[owner] - ν[owner′]) == 1),                         # … and |Δν| = 1
                           J_SS, J[kind, kind′])                                     # else J_CM / J_CC (Y5)
        edges(chain) => ζ * (distance - D)^2                                         # Eq 4 (exact ΔH today)
        angles(chain) => ξ * inv_R^2                                                 # Eq 3   [R9]
    end

    # Propulsion (Eqs 8–10). d = target − source; θ is recomputed from the current COMs (Eq 9).
    # along(x, y) = d·θ with θ the chord from S_y to S_x (unit or raw, Y1)
    along(x, y) = unit_θ ? dot(direction, normalize(separation(x, y))) :           # [R1] [NEW separation]
                           dot(direction, separation(x, y))
    work(c) = ifelse(c == 0, 0.0,                                                    # medium: θ = 0
              ifelse(prev[c] == 0, along(c, next[next[c]]),                         # head: θ₁ = θ₂ = S₁ − S₃   [R6 2-hop]
              ifelse(next[c] == 0, along(prev[prev[c]], c),                         # tail: θ_s = θ_{s−1} = S_{s−2} − S_s
                                   along(prev[c], next[c]))))                       # interior: S_{ν−1} − S_{ν+1}
    @drive copy => -ω * (work(old) + work(new))          # Eq 10: loser + gainer terms, as printed (Y4)

    @constraint no_extinction                            # a rod never loses a segment (13 §6; D-066 item 7)
    @constraint (pinned[old] == 0) && (pinned[new] == 0) # Fig 3 only: a pinned head neither gains nor loses sites

    @observed begin
        E_curve ~ sum(ξ * inv_R^2 for _ in angles(chain))            # Fig 2 / V1          # [R9] [NEW fold over a domain]
        rod_x(cell) ~ cluster_centroid(1)                            # velocity, efficiency (unwrapped)   # [R7]
        rod_y(cell) ~ cluster_centroid(2)
    end
    @sweep Metropolis(; temperature = kT)   # Eq 7 with the minus sign restored (13 §7 item 2); 1 MCS = N attempts is UNSPECIFIED (§2.5)
end

# --- Setup: Fig 6 (100 randomly dropped rods) and Fig 8 (fill to 10/20/30 % of nodes) --------------
rod   = Chain(8; area = 12, spacing = sqrt(12), kinds = :segment,    # one rod: s blobs of area A on a line   # [R2]
              orientation = RandomDirection())                       # straight rods; shape UNSPECIFIED (13 §7 item 8)
fig6  = Scattered(100, rod; seed = 1)                                # 100 rods; overlap rule UNSPECIFIED     # [R2]
fig8  = InsertUntil(rod; occupied = 0.30, seed = 1)                  # density 10/20/30 % (Fig 8 caption)     # [R2]

@named myxo = StarrussMyxobacteria()
sys  = mtkcompile(myxo)
op   = layout(fig6, sys)          # ownership, kind, cluster, :ν, :prev, :next, :chain => pairs     # [R2] [NEW]
prob = PottsProblem(sys, op, (0, 50_000); seed = 1)              # run length UNSPECIFIED (13 §7 item 5)
sol  = solve(prob, SequentialCPM(); saveat = 0:100:50_000)       # Y2: sequential is the reference
ens  = EnsembleProblem(remake(prob; u0 = layout(fig8, sys)); trajectories = 15)   # Fig 5 uses n = 15   # [NEW u0 swap]

# --- Ψ̄ (Eqs 11–12), R16 analysis in the docs: largest aligned cluster / population ----------------
using Graphs
function largest_cluster_fraction(u; Dmax = 8.0, φmax = π / 4)
    S, head = segment_centroids(u), head_directions(u)   # rod → s×2 min-image COMs; rod → θ₁   # [R16]
    n = length(S); g = SimpleGraph(n)
    for α in 1:n, β in (α + 1):n
        near = minimum(periodic_norm(S[α][i, :] - S[β][j, :]) for i in 1:8, j in 1:8) < Dmax   # Eq 11
        acos(clamp(dot(head[α], head[β]), -1, 1)) < φmax && near && add_edge!(g, α, β)          # Eq 12
    end
    return maximum(length, connected_components(g)) / n
end
Ψ̄ = mean(largest_cluster_fraction(sol[t]) for t in 10_000:1_000:50_000)   # warm-up and sampling UNSPECIFIED
```

Proposed syntax used above, in brief:
- `angles(rel)`: every path `a – pivot – b` of length 2 in a relationship, counted once.
  It binds `a`, `b` (the ends), `pivot` and `angle` (∠(a, pivot, b)).
- `separation(x, y)`: the minimum-image vector `centroid[x] − centroid[y]`.
- `x(cell)::CellRef`: the D-066 item 5 reference form.

## 2. Line → source

| Sketch line | Spec | Paper |
|---|---|---|
| `lattice` Hexagonal, Periodic | 13 §2.6 | p.275 §2.3 |
| `neighborhood = Hex(2)` (contacts) | 13 §2.5, §7 item 4; Y3 | p.275 §2.3 ("second-nearest") |
| `proposal = Hex(1)` | 13 §2.5 | p.274 §2.2 ("nearest neighbours") |
| `cells(segment) => λ(volume − A)²` | 13 §2.2 term 2 | Eq 5, p.274; Table I p.276 |
| `contacts => ifelse(same rod && \|Δν\| = 1, J_SS, J)` | 13 §2.3; Y5 | Eq 6, p.274; Table I |
| `edges(chain) => ζ(distance − D)²` | 13 §2.2 term 3 | Eq 4, p.273; Eq 5 |
| `angles(chain) => ξ (1/R)²`, `inv_R` | 13 §2.2 term 4 | Eqs 2–3, p.273 |
| `work(c)` (θ head/tail/interior) | 13 §2.4; Y1 | Eq 9, p.275 |
| `@drive … −ω(work(old) + work(new))` | 13 §2.4; Y4 | Eqs 8, 10, pp.274–275 |
| `no_extinction` | 13 §6 row 1; D-066 item 7 | p.279 (segments "always remain connected") |
| `pinned` constraint | 13 §2.7, §6 (G15), §7 item 9 | Fig 3, pp.277–278 |
| `Metropolis(; temperature = kT)` | 13 §2.5 | Eq 7, p.274 (sign, §7 item 2) |
| `E_curve` | 13 §2.9 | Fig 2, p.277 |
| `rod_x`, `rod_y` (velocity, efficiency) | 13 §2.9 | Fig 5, p.279; footnotes 4, 8 |
| `Chain` / `Scattered(100, …)` / `InsertUntil(occupied)` | 13 §2.7 | p.276, p.280 (Fig 6), Fig 8 caption |
| `largest_cluster_fraction`, Ψ̄ | 13 §2.9 | Eqs 11–12, p.281; p.282 |

## 3. Status of primitives used

| Primitive | Status |
|---|---|
| `Hexagonal()` periodic lattice, `Hex(k)` relations, `@relations proposal` | exists (M2.1b; D-049 F-1) |
| `cells(k) => λ(volume − A)²`, `contacts => J[kind, kind′]`, `ifelse` | exists |
| `cluster[owner]`, cell variables `ν[owner′]` read in contact terms | exists (D-036; AUTHORING §4) |
| `@relationship chain`, `edges(chain) => f(distance)` with exact ΔH through partner centroids | exists (M2.9, D-058) |
| `@constraint no_extinction`, `@constraint <cell-var expr>` | exists (D-066 item 6 adds `no_extinction(k…)`) |
| `@observed`, population folds, `SequentialCPM`, `EnsembleProblem`, `Scattered` | exists (`Scattered` takes boxes today; taking a `Chain` is R2) |
| `direction` (copy vector d = target − source) | planned: R1, ROADMAP P6.4a |
| `x(cell)::CellRef`, `prev[c]`, and two hops `next[next[c]]` | planned: R6, P6.5a (two hops are not stated there) |
| `angles(rel)` 3-body domain with `angle`, `pivot` | planned: R9, P6.6 (no syntax proposed yet; this sketch's is new) |
| `cluster_centroid(k)` unwrapped; centroids readable in proposal scope | planned: R7, P6.6 |
| `Chain`, `InsertUntil`, a layout that emits cell columns and link lists | planned: R2 (`Chains`, `InsertUntil`), P6.2a / P6.6. Emitting columns and links is NEW |
| Ψ̄ analysis, `segment_centroids`, `head_directions` | planned: R16 (docs Julia, D-051 item 6) |
| `separation(x, y)`: minimum-image centroid difference vector | **NEW** |
| A fold over an energy domain in `@observed` (`sum(… for _ in angles(chain))`) | **NEW** |
| `remake(prob; u0 = operating point)` for layout-per-trajectory ensembles | **NEW** (unverified whether it exists) |

## 4. Friction found

1. **Four copies of the rod order.** The rod structure is stored in four places:
   - `cluster` (rod id);
   - `ν` (index), for the J_SS rule;
   - `prev`/`next` references, for θ;
   - `chain` links, for the exact length and curvature ΔH.

   The layout must keep all four consistent, and nothing checks that it does. Using the
   relationship alone is not enough, because links are unordered and θ needs head/tail
   direction. Using references alone is not enough either: a cell energy that reads
   `centroid[next]` makes ΔH depend on who points *to* `old`/`new`, a reverse lookup the
   compiler cannot do. Relationships already solve that problem (`link_delta`).

   **Proposal:** an *ordered* relationship, `@relationship chain(cell, cell) ordered`,
   with accessors `prev(chain, c)`, `next(chain, c)`, `rank(chain, c)` and a predicate
   `linked(chain, x, y)`. One store would replace ν, the references and the links. The J_SS
   rule becomes `linked(chain, owner, owner′)`. This is what R9's "chain order as a mutable
   cell index" needs to become concretely.
2. **Two-hop reads.** Eq 9's head and tail inherit θ from segment 2 and s−1, which needs
   `next[next[c]]`. The curvature ΔH of a copy also reads centroids two hops away: the
   triple centred on `old`'s partner reads that partner's other partner. So the claim set
   is the 2-hop chain neighbourhood of `old` and `new`. D-058 shared reads cover link
   partners at one hop only, and R6 says nothing about ref-of-ref.
   - Sequential is the reference (Y2), so this matters only for the checkerboard variant.
   - The footprint analysis must still derive a depth of 2 from the expressions (review §4
     [i], "declared footprints").
3. **Periodic vector differences.** Footnote 4 computes COMs "in non-periodic space".
   R7's *unwrapped* per-cell centroids do not make `centroid[x] − centroid[y]` safe,
   because two segments of one rod can be unwrapped into different images.
   - What the terms need is a minimum-image difference between two cells. `edges(…)`'s
     `distance` already does this for a scalar. This sketch proposes `separation(x, y)` as
     its vector form **[NEW]**.
   - On a hexagonal torus the lattice is rhombic, so the minimum image in Cartesian
     coordinates is not a per-axis wrap. That is non-trivial.
   - The paper's box shape is unknown, and a rhombic torus may add its own anisotropy.
4. **No vector `ifelse`.** θ is naturally a vector-valued function of a cell. Symbolic
   `ifelse` works only on scalars, so the drive has to be written as the scalar
   `work(c) = d·θ(c)`. That rewrite is readable here, but it will not generalise: a
   polarity update that stores θ would need the vector itself.
   **Proposal:** component-wise `ifelse` over `QuantityVector` **[NEW]**, a small change.
5. **The 3-body syntax is not designed yet.** R9 names the capability but proposes no
   syntax. This sketch proposes `angles(rel)` binding `a`, `b`, `pivot` and `angle`.
   - Using `c` for the third cell would clash with the common field name `c`.
   - Capacity 2 makes every interior segment a pivot exactly once, but a relationship with
     capacity > 2 has C(deg, 2) angles per pivot. The domain must say which pairs it
     enumerates (all pairs? consecutive pairs only?).
   - Degenerate triples: coincident COMs make the norm 0, so the term is 0/0 (13 §7 item
     11). The DSL has no guard idiom, so authors will write `ifelse(norm(…) > 0, …)`
     everywhere.
6. **Observing one energy term.** Fig 2 plots E_curve, which is one term of H. The
   sketch has to repeat the expression in `@observed`, and needs a fold over an energy
   domain there **[NEW]**.
   **Proposal:** named energy terms, `@energy curvature = angles(chain) => …`, with
   `sol[:curvature]` read through SII **[NEW]**. They would also give per-term
   decompositions for 09 (boundary lengths) and 12 (adhesion vs shape ΔE, "roughly equal",
   12b p.255).
7. **The layout protocol is too narrow.** `paint!(σ, kinds, l, lat)` can paint only
   ownership and kinds. A `Chain` layout must also emit `cluster`, `ν`, `prev`/`next` and
   the link list `:chain => pairs`.
   - R2 lists `Chains`, but the protocol needs to return arbitrary cell columns and
     initial links **[NEW detail of R2]**.
   - `Scattered`/`InsertUntil` of a composite, non-box object (rotated rods on a hexagonal
     lattice) also needs an overlap test on painted masks rather than on boxes.
8. **Pinning is coarser than the paper.** The cell-variable constraint freezes the head
   segment completely: it can neither gain nor lose sites. The paper's head is "fixed in
   the agar", and its mechanism is unknown. The constraint works (review §1), but it cannot
   express a pin that fixes the COM while letting the shape fluctuate.
9. **Ψ̄ is a pairwise, rod-level graph observable** (min over s × s segment distances plus
   a head angle, then connected components). The DSL has no pair folds over cells, and
   R11a's `neighbors(c)` is contact-based, not distance-based. It therefore lives in docs
   Julia with Graphs.jl (R16). This needs clean SII access to per-segment centroids
   grouped by rod, and to θ₁ per rod. Without an observed `θ` (see item 4), `head_directions`
   has to recompute Eq 9 on the host, a second implementation of the same law.
10. **Works today, worth noting:**
    - The contact rule of Eq 6 is exactly expressible now: a contact term reading
      `cluster` and a cell variable of both owners.
    - The length energy (Eq 4) is exactly `edges(chain) => ζ(distance − D)²` with exact ΔH
      through partner centroids. The only new energy work is the 3-body term.

## 5. Open choices

| Choice | Paper vs alternative | Spec default |
|---|---|---|
| θ normalisation (Eq 9 "‖·‖") | unit chord / raw chord (scale ≈ 2D ≈ 7) | **unit** (Y1); `unit_θ = false` variant |
| Eq 10 loser term | as printed / physically "retreat" sign | **as printed** (Y4) |
| "Second-nearest" contact shell | shells 1+2 (`Hex(2)`, 12 sites) / shell 2 only | **shells 1+2** (Y3) |
| Same-rod non-adjacent contact | J_CC (Eq 6 "else") / J_SS / 0 | **J_CC** (Y5) |
| κ(s) and Fig 6's κ ≈ 10 | s = 8 'xanthus' / other s | **s = 8**; κ ≈ 0.86 s labelled a hypothesis (Y6) |
| Sweep algorithm | sequential / checkerboard with 2-hop claims | **sequential** reference; checkerboard validated statistically (Y2) |
| Eq 7 exponent sign | +ΔH′/kT as printed / −ΔH′/kT | **−ΔH′/kT** (13 §2.5, §7 item 2) |
| θ from pre-copy or post-copy COMs | not stated | pre-copy (it is a drive; this sketch's choice, not in the spec) |
| Head pinning (Fig 3) | frozen segment / COM pin / suppressed copies | UNSPECIFIED (13 §7 item 9); the sketch freezes the segment |
| Lattice size, MCS definition, run and sampling windows | – | UNSPECIFIED (13 §3; §7 item 5) |
| Initial rods: straight, overlap rule | – | UNSPECIFIED (13 §7 item 8); the sketch uses straight rods and rejects overlaps |
