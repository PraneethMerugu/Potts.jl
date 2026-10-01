# 11 — Jafari Nivlouei 2021 multiscale tumour growth and angiogenesis (+ Andasari 2012 ODE conformance): target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model (11a):** a 2D CPM that couples three scales:
  - a per-cell Boolean signalling network (Table 1) used as the Fig 3 lookup table;
  - tumour phenotypes (M/P/Q/N) and endothelial cells (inactive/active);
  - two periodic reaction–diffusion fields (nutrient and VEGF), with ECM as the medium.
- **Conformance component (11b):** the Andasari 2012 E-cadherin/β-catenin ODE (Ramis-Conde
  2008), with contact-derivative inputs and a type switch. This is a G9 ODE conformance
  test, not a reproduction (11 §8).
- **Papers:**
  - 11a: Jafari Nivlouei et al., *PLoS Comput Biol* 17(6): e1009081 (2021); S1 Data XLSX.
  - 11b: Andasari et al., *PLoS ONE* 7(3): e33726 (2012).
- **Code:** neither paper has released model code.
- **Spec:** `../11_multiscale.md` (§2A, §2B, §3, §6 G9 interface, §7, §9). Decisions: README
  §4.8 (N1–N6), D-065 Q9 (Boolean networks as MTK discrete components, no Potts helper),
  ROADMAP P6.10, P6.0k.
- **Date:** 2026-09-30.

Tags: `# [R#]` means a planned roadmap feature. `# [P6.x]` means a planned ROADMAP step-0
item (composition fix or spike). `# [NEW]` means the feature is not on the roadmap. `# [?]`
means the primitives exist but this combination has not been tested. A line with no tag
uses only what exists at `monorepo` HEAD. `NaN` marks a value the paper does not give
(UNSPECIFIED); each such value carries its spec reference. Rates are converted to lattice
units (Δx = 4 μm, 1 MCS = 1 min).

```julia
using Potts, ModelingToolkit, OrdinaryDiffEq, LinearSolve
using ModelingToolkit: t_nounits as t, D_nounits as D

# ── Intracellular Boolean network (11a Table 1 p.8), an MTK clocked component (D-065 Q9) ──
# The unit test V11a-1 and the `grn = :network` variant use it. The runtime default is the Fig 3 table (N4).
k = ShiftIndex(Clock(1))                                                    # [P6.0k]
@parameters ITG::Bool RTK::Bool Wnt::Bool Cad::Bool APC::Bool = false NF1::Bool = false   # inputs; APC = NF1 = OFF (p.13)
@variables βcat(t)::Bool Grb2(t)::Bool Src(t)::Bool FAK(t)::Bool RhoA(t)::Bool ROCK(t)::Bool Rac1(t)::Bool Ras(t)::Bool
@variables Raf1(t)::Bool MEK(t)::Bool ERK(t)::Bool RSK(t)::Bool TSC(t)::Bool mTORC(t)::Bool MNK(t)::Bool eIF4E(t)::Bool
@variables MSK(t)::Bool Fos(t)::Bool Myc(t)::Bool PI3K(t)::Bool Akt(t)::Bool eNOS(t)::Bool NO(t)::Bool Casp(t)::Bool
@variables Mdm2(t)::Bool p53(t)::Bool Actin(t)::Bool SNAIL(t)::Bool
q(x) = x(k - 1)                                                             # synchronous update (p.11)
@named grn = System([
    βcat(k) ~ Wnt | (q(Akt) & !Cad & !APC),  Grb2(k) ~ RTK & q(Src),  Src(k) ~ q(FAK),  FAK(k) ~ ITG,   # βcat parse: 11 §7 item 9; "Scr" = Src
    RhoA(k) ~ q(FAK),  ROCK(k) ~ q(RhoA),  Rac1(k) ~ q(PI3K) & !q(RhoA),  Ras(k) ~ q(Grb2) & !NF1,
    Raf1(k) ~ q(Ras),  MEK(k) ~ q(Raf1) | q(Rac1),  ERK(k) ~ q(MEK),  RSK(k) ~ q(ERK),
    TSC(k) ~ !q(RSK) | !q(Akt),  mTORC(k) ~ !q(TSC),  MNK(k) ~ q(ERK),  eIF4E(k) ~ q(MNK),  MSK(k) ~ q(ERK),
    Fos(k) ~ q(MSK) & q(RSK),  Myc(k) ~ q(ERK) | q(βcat),  PI3K(k) ~ q(Ras),  Akt(k) ~ q(PI3K),
    eNOS(k) ~ q(Akt),  NO(k) ~ q(eNOS),  Casp(k) ~ !q(NO),  Mdm2(k) ~ q(Akt),  p53(k) ~ !q(Mdm2),
    Actin(k) ~ q(ROCK) | q(Rac1),  SNAIL(k) ~ q(βcat)], t)                  # [P6.0k] Bool-typed Shift system
# Outputs (Table 1): growth = eIF4E ∨ mTORC, proliferation = Fos ∧ Myc, apoptosis = Casp ∨ p53, migration = Actin ∧ SNAIL

# Fig 3 (p.12) as printed (bits: growth, proliferation, apoptosis, migration), including the 100/Cad-OFF cell (11 §7 item 9)
fig3 = Dict((1,1,1) => (0b1101, 0b1101), (1,0,1) => (0b0011, 0b0011), (0,1,1) => (0b0010, 0b0010), (0,0,1) => (0b0010, 0b0010),
            (1,1,0) => (0b1101, 0b1100), (1,0,0) => (0b0011, 0b0010), (0,1,0) => (0b0010, 0b0010), (0,0,0) => (0b0010, 0b0010))
bit(b) = [(fig3[(i, r, w)][c + 1] >> (4 - b)) & 1 == 1 for i in 0:1, r in 0:1, w in 0:1, c in 0:1]   # [ITG, RTK, Wnt, Cad]

@potts_model TumourAngiogenesis begin
    @structural_parameters begin
        lattice = (300, 300)                          # 300 × 300 × 1 = 1.44 mm², Δx = 4 μm (p.13; 11 §7 item 13)
        grn = :table                                  # N4: Fig 3 table | :network
    end
    @kinds matrix endothelial endothelial_active migrating proliferating quiescent necrotic   # τ = 0 is ECM (p.7); Table 2
    @kind_classes begin                               # [P6.0g]
        vessel = (endothelial, endothelial_active)
        tumour = (migrating, proliferating, quiescent)
        cancer = (migrating, proliferating, quiescent, necrotic)
    end
    @parameters begin
        T_m = 10.0;  γ_e = 8.0;  α = 300.0            # Table 2 (γ_e equal for M, P, Q, EC)
        A_Q = 32.0                                    # ≈ 32 voxels initial (Table 2 footnote); A_Q = initial area is our reading
        J[kind, kind] = [66 12 12 12 12 12 10; 12 5 5 30 30 30 30; 12 5 5 30 30 30 30; 12 30 30 8 8 8 10;
                         12 30 30 8 8 8 10; 12 30 30 8 8 8 10; 10 30 30 10 10 10 8]   # Table 2 (m, EC, ECa, M, P, Q, N); ECa = EC row, assumed
        χ_n = NaN;  χ_V = NaN                         # UNSPECIFIED (11 §7 item 7); calibrated to V11a-5 / V11a-2 (N3)
        D_n = 1e3 * 60 / 16;  D_V = 10 * 60 / 16      # 10³ and 10 μm²/s (Table 2) → 3750 and 37.5 px²/MCS
        k_V = 0.9375 / 60                             # VEGF decay, h⁻¹ → MCS⁻¹ (Table 2)
        β[kind] = [0, 0, 0, 5.17e-17, 5.17e-17, 2.41e-17, 0]   # mol/cell/s; β_M = β_P, β_N = 0 (Table 2)
        κ_β = NaN                                     # mol/cell/s → pg/cell/MCS: UNSPECIFIED (11 §7 item 1; N2)
        e_V = 0.001 * 60                              # EC VEGF uptake cap, pg/cell/s → /MCS (Table 2)
        s_V = 0.035                                   # pg/pixel, time unit as printed (Table 2; 11 §2A units)
        n₀ = 4.6;  n_vessel = NaN                     # S_0 (p.10); EC clamp value UNSPECIFIED ("n|ECs = S_n", 11 §7 items 1–2)
        T_RTK = 4.48e-3;  T_V = 9.5e-4;  T_ITG = 0.3;  T_cad = 0.3;  T_Wnt = 0.15   # Table 2
        n_hyp = NaN;  τ_nec = NaN                     # quiescence threshold, necrosis delay: UNSPECIFIED (11 §7 item 5)
        r_grow = NaN                                  # target growth per MCS: UNSPECIFIED (11 §7 item 6); calibrate to 1.03 d doubling
        therapy_day = Inf                             # 3, 5 or 6 (p.28)
        grow_tab[0:1, 0:1, 0:1, 0:1]::Bool = bit(1);  prol_tab[0:1, 0:1, 0:1, 0:1]::Bool = bit(2)   # [R13]
        apop_tab[0:1, 0:1, 0:1, 0:1]::Bool = bit(3);  migr_tab[0:1, 0:1, 0:1, 0:1]::Bool = bit(4)   # [R13]
    end
    @variables begin
        n(field) = n₀                                 # nutrient, pg/voxel (Eq 7; IC p.10)
        V(field) = 0.0                                # VEGF (Eq 8; IC p.11)
        V_target(cell) = A_Q
        itg(cell) = 0;  rtk(cell) = 0;  wnt(cell) = 0;  cad(cell) = 0   # Boolean inputs (p.12–13)
        grow(cell) = 0;  prol(cell) = 0;  apop(cell) = 0;  migr(cell) = 0
        hyp(cell) = 0.0                               # MCS spent below n_hyp
        blocked(model) = 0.0                          # therapy clamp
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = VonNeumann(1))   # periodic (p.10, p.13); order UNSPECIFIED (11 §2A)
    @relations proposal = VonNeumann(1)               # UNSPECIFIED; CC3D default order 1
    @energy begin
        contacts => J[kind, kind′]                                            # Eq 1
        cells(vessel, tumour) => γ_e * (volume - V_target)^2                  # Eq 2 [P6.0g]
    end
    @drive copy => α * ((old != 0) & (components(old; scope = Global()) > 1))   # Eq 3 continuity, exact BFS (N5 = B5) [R4]
    @drive copy => ifelse((kind[new] == migrating) | (kind[old] == migrating), -χ_n * (n[target] - n[source]), 0.0)   # Eq 4 (CC3D gate assumed)
    @drive copy => ifelse((kind[new] == endothelial_active) | (kind[old] == endothelial_active), -χ_V * (V[target] - V[source]), 0.0)  # Eq 5
    @equations solver = Adaptive(KenCarp4(linsolve = KrylovJL_GMRES())) begin   # D_n Δt/Δx² = 3750 [P6.0c][R14]
        D(n) ~ D_n * Δ(n) - uptake(n; max_amount = κ_β * β[kind], relative = 1, per = :cell, by = kind ∈ cancer)  # Eq 7: B = min(n, β) [R15][NEW per]
    end
    @equations solver = ExplicitEuler() begin     # substeps from the stability limit (≈ 150) [P6.0c]
        D(V) ~ D_V * Δ(V) - k_V * V - uptake(V; max_amount = e_V, relative = 1, per = :cell, by = kind ∈ vessel) +
               s_V * (kind == quiescent) * (1 - blocked)                         # Eq 8; hypoxic cells secrete (p.10–11, p.28) [R15]
    end
    @boundary n sites(vessel) => Dirichlet(n_vessel)  # N1: clamp at EC sites (p.10); S_n source-term variant [R5]
    # Cues → Boolean inputs, every step before the sweep (p.12). "Size" = surface and "local" = cell mean: UNSPECIFIED (11 §7 item 4; §6 G9)
    ecm  = sum(contact(c, o) for o in neighbors(c) if kind[o] == matrix) / surface   # [R11a]
    n̄, V̄ = integral(n) / volume, integral(V) / volume
    @before_mcs begin
        itg  ~ ecm >= T_ITG
        rtk  ~ (1 - blocked) * ifelse(kind ∈ vessel, V̄ >= T_V, n̄ >= T_RTK)    # EC: VEGF; tumour: nutrient (p.13). Clamped receptor UNSPECIFIED (11 §7 item 10)
        cad  ~ (1 - ecm) >= T_cad                                              # cell–cell contact fraction (p.12)
        wnt  ~ (1 - ecm) >= T_Wnt                                              # Wnt contact source UNSPECIFIED (11 §7 item 4)
        hyp  ~ ifelse(n̄ < n_hyp, Pre(hyp) + 1, 0.0)
    end
    if grn === :table
        @before_mcs begin                                                      # Fig 3 lookup (p.12; N4) [R13]
            grow ~ grow_tab[itg, rtk, wnt, cad];  prol ~ prol_tab[itg, rtk, wnt, cad]
            apop ~ apop_tab[itg, rtk, wnt, cad];  migr ~ migr_tab[itg, rtk, wnt, cad]
        end
    else
        @components cells(tumour, endothelial_active) net = grn                # [P6.0k][P6.0g] state survives transitions [R3]
        @equations begin net.ITG ~ itg; net.RTK ~ rtk; net.Wnt ~ wnt; net.Cad ~ cad end       # [P6.0k]
        @before_mcs begin                                                      # attractor needs ≥ depth ticks per MCS [NEW sub-clock]
            grow ~ net.eIF4E | net.mTORC;  prol ~ net.Fos & net.Myc
            apop ~ net.Casp | net.p53;     migr ~ net.Actin & net.SNAIL
        end
    end
    # Phenotype → kind (p.12, p.14, p.18). Rules and their priority are UNSPECIFIED beyond Fig 3 (11 §2A "Output mapping")
    @retire cells(tumour) when = apop == 1                                    # apoptosis: removal UNSPECIFIED; sites → matrix [R3]
    @transition cells(proliferating, migrating) => quiescent when = n̄ < n_hyp # hypoxia (p.14, p.18) [R3]
    @transition cells(quiescent) => necrotic when = hyp > τ_nec               # Fig 6F; rule UNSPECIFIED [R3]
    @transition cells(tumour) => migrating when = (migr == 1) & (n̄ >= n_hyp)  # 1101 → M: mapping UNSPECIFIED [R3]
    @transition cells(tumour) => proliferating when = (migr == 0) & (prol == 1) & (n̄ >= n_hyp)   # 1100 → P [R3]
    @transition cells(endothelial) => endothelial_active when = V̄ >= T_V      # p.13, Table 2 [R3]
    @after_mcs V_target ~ ifelse((grow == 1) & (kind ∈ (migrating, proliferating, endothelial_active)),
                                 min(Pre(V_target) + r_grow, 2A_Q), Pre(V_target))   # Eq 2: A^T = 2·A_Q (p.9) [P6.0g]
    @divide cells(migrating, proliferating, endothelial_active) when = (prol == 1) & (volume >= 2A_Q),   # trigger UNSPECIFIED (p.9)
        along = RandomPlane(), V_target => A_Q                               # plane, daughter target UNSPECIFIED; kind and state copied (p.9, p.22)
    @discrete_events (mcs == therapy_day * 1440) => [blocked ~ 1.0]           # therapy from day 3/5/6 (p.28) [R3]
    @observed begin
        area_tumour ~ 16 * sum(volume for c in cells(cancer))                 # μm² (Figs 9, 18) [P6.0g]
        n_viable    ~ count(true for c in cells(tumour))                      # Figs 10, 11, 13 [P6.0g]
        r_eq        ~ sqrt(area_tumour / 3.14)                                # Fig 5 (π ≈ 3.14; 11 §9.3 item 2)
    end
    @sweep Metropolis(; temperature = T_m)            # Eq 6 acceptance, T_m = 10 (p.7)
end

@named ta = TumourAngiogenesis()
tumour0 = VoronoiBall(4; radius = sqrt(131 / π), kinds = [:proliferating], seed = 1)  # 4 P cells, 131 px (p.13; S1 "Figure 9" B5) [R2]
vessel  = Tiling((8, 4); region = (1:300, 40:43), kinds = [:endothelial])      # vessel geometry UNSPECIFIED (11 §7 item 11): placeholder
prob = PottsProblem(ta, layout(overlay(vessel, tumour0), ta), (0, 15 * 1440); seed = 1)   # 15 days (Fig 9)
sol  = solve(prob, SequentialCPM(); saveat = 0:10:(15 * 1440))                 # S1 cadence 10 MCS (11 §9.1)
ens  = solve(EnsembleProblem(prob), SequentialCPM(), EnsembleThreads(); trajectories = 8)   # n = 8 (11 §5A policy)
therapy = [remake(prob; p = [:therapy_day => d]) for d in (3, 5, 6)]          # Fig 18 (V11a-10)

# ── 11b Andasari 2012: E-cad/β-cat ODE (Eqs 7–12), G9 ODE conformance component (11 §8) ──────────
@parameters ν = 100 αd = 0 kz = 1.5 k₋ = 19 k₂ = 1 k_m = 14 P_T = 21 E_T = 100 cᵢ = 0 dᵢ = 0 on = 0   # Table 1 p.4
@variables Ec(t) Eβ(t) β(t) C(t)                     # ICs UNSPECIFIED (SBML defaults; 11 §3B)
A1 = ν * (E_T - Ec - Eβ) * β - αd * Eβ               # Eqs 8–9 via the SBML ν/α swap (p.4–5); A2 = −A1
@named ecad = System([D(Ec) ~ on * (-cᵢ * Ec + dᵢ * Eβ), D(Eβ) ~ on * (A1 - dᵢ * Eβ),
    D(β) ~ on * (-A1 + dᵢ * Eβ - kz * β * (P_T - C) + k₋ * C + k_m), D(C) ~ on * (kz * β * (P_T - C) - k₋ * C - k₂ * C)], t)  # Eq 12

@potts_model EcadConformance begin                   # a 2D adaptation; every CPM value is UNSPECIFIED (11 §3B, §7 11b item 1)
    @kinds medium lowβ highβ                         # LowBetaCat / HighBetaCat (p.5)
    @parameters begin T = NaN; λ = NaN; V₀ = NaN; J[kind, kind] = fill(NaN, 3, 3); cT = 50.0; ρc = 200.0; ρd = 200.0 end
    @variables â(touch) = 0.0                        # contact area of the pair / surface of `a`, at the last MCS [NEW directed edge var]
    @relationship touch(cell, cell) capacity = 12    # per-neighbour memory of contacts
    @link touch when = new_contact(a, b)
    @unlink touch when = (contact(a, b) == 0) & (â == 0)                    # unlink one MCS after detachment is counted [R11a]
    @lattice Lattice((64, 64); boundary = Closed(), neighborhood = Moore(1))
    @energy begin cells(lowβ, highβ) => λ * (volume - V₀)^2; contacts => J[kind, kind′] end
    @components cells(lowβ, highβ) ec = ecad         # one state across the type switch (p.14) [R3]
    @equations begin
        ec.ν ~ ifelse(kind == lowβ, 100.0, 0.0);  ec.αd ~ ifelse(kind == lowβ, 0.0, 2.0)   # parameter swap (p.5)
        ec.on ~ mcs >= 20                                                    # integration starts at MCS 20 (p.3) [NEW activation window]
        ec.cᵢ ~ ρc * sum(max(contact(c, o) / surface - â[e], 0) for (o, e) in links(c, touch))   # Eq 10 [NEW incident-edge fold][R11a]
        ec.dᵢ ~ ρd * sum(max(â[e] - contact(c, o) / surface, 0) for (o, e) in links(c, touch))   # Eq 11 [NEW][R11a]
    end
    @after_mcs â ~ contact(a, b) / surface[a]       # [NEW edge-scope update][R11a]
    @transition cells(lowβ) => highβ when = ec.β > cT                        # EMT (p.5) [R3]
    @transition cells(highβ) => lowβ when = ec.β < cT                        # MET (p.5) [R3]
    @discrete_events (mcs == 70) => [ec.kz ~ 1.0]                            # layer-run trigger (p.5); 200 / 400 in other runs [R3]
    @sweep Metropolis(; temperature = T, mcs_duration = 0.05, ode_solver = Adaptive(Rodas5P()))   # Δt 0.05 (code p.14) vs 0.03 (p.11)
end
```

## Line → source

| Line / rule | Spec | Paper |
|---|---|---|
| `grn` equations (29 nodes, synchronous) | 11 §2A table, §7 item 9 | 11a Table 1 p.8; Fig 2 p.7; synchronous update p.11 |
| `APC = NF1 = false` | §2A "Fig 3 truth table" | p.13 |
| `fig3` / `*_tab` | §2A Fig 3 table; README §4.8 N4 | Fig 3 p.12, bits ordered as the Table 1 outputs (§7 item 9) |
| `lattice = (300, 300)`, `Periodic()` | §2A, §3A | p.10, p.13 |
| Neighbourhood and proposal order | §2A, §3A | UNSPECIFIED |
| `J` table | §3A | Table 2 p.14 |
| `γ_e`, `A_Q`, `V_target` → `2A_Q` | §2A Eq 2, §3A | Eq 2 p.9; Table 2 and footnote p.14 |
| Continuity drive, `α = 300` | §2A Eq 3; README §4.8 N5, §4.12 | Eq 3 p.9; Table 2 |
| Nutrient chemotaxis (migrating) | §2A Eqs 4–5 | Eq 4 p.9 ("with migration phenotype"); χ UNSPECIFIED |
| VEGF chemotaxis (active EC) | §2A Eqs 4–5 | Eq 5 p.9 |
| `D(n)` with capped uptake | §2A Eq 7; README N2 | Eq 7 p.10; Table 2 (β, D_n); IC S_0 p.10 |
| `@boundary n … Dirichlet` | §2A; README N1 | p.10 "n\|ECs = S_n" |
| `D(V)` with decay, EC uptake and hypoxic secretion | §2A Eq 8 | Eq 8 p.10–11; Table 2; therapy stops release p.28 |
| Solver per field | §2A "Solver", §7 item 3 | UNSPECIFIED ("integrated simultaneously", p.5) |
| Inputs `itg`, `cad`, `wnt` | §2A "Input mapping", §6 G9 | p.12; thresholds in Table 2 |
| Input `rtk` | §2A | p.13 (tumour: nutrient ≥ T_RTK; EC: VEGF ≥ T_V) |
| Table lookup before the sweep | §2A "Update order", §6 G9 "Cadence" | p.12–13 |
| `@retire` (apoptosis) | §2A "Output mapping" | Fig 3; p.13–14; removal UNSPECIFIED |
| Quiescence, necrosis | §2A | p.14, p.18, Fig 6F; thresholds UNSPECIFIED |
| EC activation | §2A | p.13, Table 2 (T_V) |
| `@divide` | §2A; §4B claim 8 | p.9 ("double their size"), p.22 (EC daughters) |
| Therapy event | §2A "Therapy"; §4B claim 10 | p.27–29, Figs 18–19 |
| Observables (area, count, r_eq) | §5A V11a-5, -6, -6b, -7, -8, -10; §9.3 items 2, 5 | Figs 5, 9, 10, 11, 13, 18; S1 Data |
| `VoronoiBall(4 …)`, 131 px | §2A "Initial conditions"; §9.1 | p.13, p.17; S1 "Figure 9" B5 |
| 15 days, 10-MCS saves | §3A, §9.1 | p.13 (1 MCS = 1 min); S1 cadence |
| `ecad` Eqs 7–12, Table 1 values | §2B, §3B | 11b Eqs 7–12 p.15–16; Table 1 p.4 |
| ν/α swap on type change | §2B "Threshold switching" | 11b p.4–5 |
| `cᵢ`, `dᵢ` from contact derivatives | §2B Eqs 10–11; §6 G3 (11b) | 11b p.15 |
| ODE start at MCS 20, `kz` 1.5 → 1.0 at MCS 70 | §2B "Triggers" | 11b p.3, p.5 |
| `mcs_duration = 0.05` | §2B; §4A claim 7 | 11b p.14 (code) vs p.11 (0.03 "for example") |

## Status of primitives used

| Primitive | Status |
|---|---|
| `@kinds`, kind-indexed `J[kind, kind]` and `β[kind]`, cell/field/model `@variables`, periodic lattice, `@relations proposal` | exists (1-D `x[kind]` tables are used in the 09 sketch) |
| `contacts`/`cells` energies; `@drive copy => ifelse(…)` on field values | exists |
| Field PDEs with `Δ`, masked source terms `(kind == q)` | exists (Merks) |
| `integral(n) / volume` in cell updates | exists (AUTHORING §12.3) |
| Cell `@before_mcs`/`@after_mcs` with `Pre`; population folds in `@observed` | exists |
| `@divide … RandomPlane()` | exists |
| `@components cells(k) name = sys` with an MTK ODE system; `@equations sys.p ~ cell expr` coupling | exists (D-038) |
| `@relationship`, `@link … new_contact(a, b)`, `@unlink`, edge variables | exists (P6.0b) |
| `ifelse`, `mcs` in cell equations | exists |
| Kind classes (`@kind_classes`, `kind ∈ class`, `cells(class)`) | planned **P6.0g** (step 0). The block syntax here is proposed |
| MTK clocked Boolean component (`ShiftIndex`, `Bool` unknowns, `&`/`\|`/`!`) lowered per cell; coupling of its inputs | planned **P6.0k** spike (D-065 Q9), then **R13** |
| Integer-indexed tables `tab[0:1, …]::Bool` indexed by cell expressions | planned **R13** |
| `components(old; scope = Global())` in a drive | planned **R4** |
| `uptake(…; max_amount, relative, by)` | planned **R15** (CC3D `Uptake` semantics, AUTHORING §12.9). `per = :cell` is **NEW** |
| `@boundary n sites(k) => Dirichlet(v)` (moving, kind-defined) | planned **R5** |
| Per-equation solvers (`@equations solver = … begin … end`) | planned **P6.0c**. The implicit field solver is **R14** |
| `neighbors(c)`, `contact(c, o)` (medium included) | planned **R11a** |
| `@transition`, `@retire`, `@discrete_events`; component state across transitions | planned **R3** (+ the R3 composition fix "scope across transitions") |
| `VoronoiBall` layout | exists in PottsModels; moves to core in P6.1a5 (**R2**) |
| Sub-clock: several Boolean ticks per MCS (run to the attractor) | **NEW** |
| Component activation window (`ec.on ~ mcs >= 20`) | the coupling exists. A first-class `start = 20` is **NEW** |
| Directed edge variables, incident-edge folds `links(c, rel)`, edge-scope `@after_mcs` | **NEW** |

## Friction found

1. **The nutrient PDE is stiff by three orders of magnitude.**
   - D_n = 10³ μm²/s at Δx = 4 μm and Δt = 1 min gives D Δt/Δx² = 3750. Explicit Euler
     needs ≥ 15,000 substeps per MCS: 1.35·10⁹ site updates per MCS, or about 8 h at 1 ns per update for one
     15-day run.
   - The spec's matrix (README §3) and ROADMAP P6.10 list only R5 for item 11. **R14
     (implicit/IMEX) and P6.0c (per-equation solvers) are required** (●), because VEGF
     (37.5, about 150 substeps) is fine explicit.
   - The quasi-steady `0 ~ …` form (R14) is a cheaper variant. The diffusion time over
     the domain is about 24 MCS, so it is an approximation, not an identity.
2. **The units are inconsistent in the paper and block unit checking.**
   - β is in mol/cell/s, n is in pg/voxel, and the clamp "n|ECs = S_n" uses a rate.
   - With DynamicQuantities loaded, `mtkcompile` would reject the model. The sketch
     therefore uses bare numbers with `κ_β` and `n_vessel` as `NaN` placeholders.
   - A per-cell capped uptake is not the CC3D `Uptake` (per site). N2 needs a
     `per = :cell` budget that is spread over the cell's sites (NEW keyword on R15).
3. **Boolean networks as MTK discrete components (P6.0k) need three things verified.**
   - (a) `Bool`-typed unknowns and `&`/`|`/`!` inside a `Shift` system. The workaround is
     0/1 reals with `min`/`max`/`1 − x`, recorded in DECISIONS per D-065 Q9.
   - (b) The input coupling `net.ITG ~ itg`: it exists for ODE components (D-038), but
     not for clocked ones.
   - (c) **"Run to the attractor" has no primitive.** The paper uses the attractor of each
     input combination (Fig 3). One `Shift` tick per MCS instead gives a network with
     signal delays of about 10 MCS (the path length ITG → FAK → … → Fos), which is a
     different model.
   - The `:network` variant therefore needs a sub-clock (k ticks per MCS, k ≥ the network
     depth) or a fixed-point iteration. Both are NEW. The table default (N4) avoids the
     problem, and the network stays a unit test (V11a-1).
4. **R13 tables.**
   - The natural object is one function `(itg, rtk, wnt, cad) → 4 bits`. Without integer
     bit operations in the DSL, it has to be split into four Bool tables indexed by Bool
     cell expressions (`0:1` axes).
   - Two ways to express it: accept a `@register_symbolic` pure Julia function with small
     integer arguments (device-safe via a constant table), or allow `NTuple` table
     values.
   - The printed Fig 3 cell (100 / Cad OFF = 0011) disagrees with the network (0010).
     The table must carry the printed value (N4) while the unit test expects 15/16.
5. **The contact fractions need R11a with the medium as a neighbour.** ITG uses cell–ECM
   contact, and ECM is the medium (τ = 0).
   - `neighbors(c)` must yield the medium "cell", and `contact(c, o)` must give its
     interface. AUTHORING §12.3's `exposure` example assumes this, but R11a is not yet
     specified that way.
   - The normalisation ("by the cell's size": surface or area) and the Wnt source are
     UNSPECIFIED.
   - A possible workaround today is `integral(count(kind[s] == matrix for s in
     VonNeumann(1)(site))) / surface`, a gather inside `integral` (untested).
6. **Phenotype = kind makes the decision logic N transition rules.**
   - The paper's rule is one function `(bits, n̄, hyp) → kind`. As `@transition` lines it
     becomes 5 rules whose priority ("stable model order") carries meaning: apoptosis must
     beat quiescence, which must beat migrating/proliferating.
   - A single discrete kind assignment, `@before_mcs kind ~ phenotype(…)` restricted to a
     kind class, would state it once (NEW; R3 could accept it as sugar that expands into
     transitions).
   - Every scope in this model is a **kind class** (P6.0g): energies, uptake, components
     and folds. The Boolean component must survive M ↔ P ↔ Q transitions (R3 composition
     fix [g]).
7. **The Fig 3 table cannot be applied to every cell as written.**
   - With RTK = 0 the table says apoptosis. Inactive ECs (VEGF below T_V) would therefore
     all die.
   - The sketch scopes `@retire` to tumour cells and uses only the growth/proliferation
     bits for active ECs. That is an unstated modelling choice that needs a flag in the
     tutorial's deviations table.
   - The same applies to 1101 (growth + proliferation + migration), which could map to M
     or to P: the M/P mapping is UNSPECIFIED.
8. **Eq 3 is an energy, but the planned R4 form is a drive on the loser.**
   - α(1 − δ_{a,a′}) summed over cells changes whenever *either* cell's connectedness
     changes. A copy can reconnect a fragmented `new` cell, so ΔH = −α.
   - `@drive copy => α*(components(old) > 1)` charges only the breaking side, and never
     charges a cell for *staying* fragmented.
   - The exact form needs `components` as a cell quantity with ΔH on both cells (NEW
     beyond R4). At α = 300, T = 10 the difference should be small, but it is not
     guaranteed for thin EC sprouts. Flag it, and test the exact version against the
     drive on a sprout fixture.
9. **Phase order is unspecified in the paper and implicit here.** The paper's per-step
   flow is cues → table → phenotype → CPM → fields. The sketch needs:
   - `@before_mcs` inputs → table → rules (R3 rules run "at the MCS boundary": before or
     after the before-MCS updates?);
   - then the sweep;
   - then fields, with clamp and uptake order.

   This is the R5 "explicit phase order" gap, and here it decides whether a cell that
   turns apoptotic secretes VEGF for one more MCS.
10. **The chemotaxis gate is unknown.** There is no code. The CC3D default (either cell,
    new first) is assumed, as in 10, and the `Chemotaxis` helper cannot express it
    (sketch 10, friction 1). "Only cells with migration phenotype" (p.9) could equally mean
    a gaining-only gate.
11. **Observables.**
    - The sprout-tip speed (V11a-2) needs the tip's identity across saves: a population
      `argmax` over active ECs of distance from the parent vessel. `argmax` is not a fold
      (NEW; the review names "tip = population argmax"). Tracking across saves is R16 docs
      work.
    - IVD (V11a-9) has an undefined x-axis (§9.3 item 6), so it cannot be written at all.
12. **Andasari (11b) needs per-neighbour, directed, lagged contact memory.**
    - â_ij is normalised by *i*'s surface, so â_ij ≠ â_ji. Relationship edges are
      symmetric, so a directed edge variable (or two per edge) is needed. Contact loss must
      be counted (dᵢ) *before* the link is dropped, which forces the two-step unlink
      condition in the sketch.
    - Needed: a fold over a cell's incident links (`links(c, rel)`), edge-scope
      `@after_mcs` updates, and `contact(a, b)` in link rules. None of these exists; all
      are NEW.
    - `Pre(x, k)` on cell variables (R12) does not help: the memory is per pair, including
      pairs that no longer touch.
    - Alternative: an R11a contact table with a one-MCS lag, i.e. `Pre(contact(c, o))`
      over the union of old and new neighbours. Either way it is a new primitive.
    - The integration window (start at MCS 20) is emulated by multiplying every right-hand
      side by `on`, which is ugly. A component `start`/`active` keyword would be cleaner.
13. **Scale of the unspecified parts.** 11 of the sketch's parameters and rules are `NaN`
    or UNSPECIFIED:
    - χ_n, χ_V, κ_β, n_vessel, n_hyp, τ_nec and r_grow;
    - the neighbour order, the division trigger and plane, the apoptosis removal and the
      M/P mapping.

    The model composes from general primitives. The reproduction, however, is a
    calibration exercise against S1 Data (N3), and the tutorial must say so.

## Open choices

| Choice | Default (spec / decision) | Variant |
|---|---|---|
| Nutrient source (N1) | Dirichlet clamp on EC sites | Source term S_n on EC sites (Eq 7 as printed) |
| Nutrient units (N2) | Per-cell conservative uptake, converted via the cell volume inferred from Table 4 (flagged) | Per-site `min(n, β)` as printed |
| χ values (N3) | Calibrated: χ_EC to V11a-2 sprout speed, χ_tumour to V11a-5 | — |
| Intracellular model (N4) | Fig 3 lookup table as printed (incl. 100/Cad-OFF = 0011) | Full Table 1 network, MTK clocked component; β-Catenin = Wnt ∨ (Akt ∧ ¬cad ∧ ¬APC) (§7 item 9) |
| Continuity (N5 = B5) | Exact global BFS penalty (README §4.12) | Local ring; exact two-sided energy (friction 8) |
| Targets (N6) | S1 Data sheet values | Text values recorded, not enforced |
| Nutrient solver | Implicit transient (R14) | Quasi-steady `0 ~ …` |
| Neighbour order | UNSPECIFIED; VN(1) as the CC3D default | Moore(1) / NeighborOrder(2) |
| Quiescence, necrosis, apoptosis rules | UNSPECIFIED; threshold + delay + instant removal placeholders | Calibrate to V11a-4 and V11a-7 timing |
| Division | UNSPECIFIED; `volume ≥ 2A_Q`, random plane, daughters reset to A_Q | Daughters inherit target volume (p.22, EC) |
| 1101 phenotype | → migrating | → proliferating, or a migrating kind that also divides |
| Therapy clamp | RTK (TKI) on all cells from day d | ITG (Volociximab); tumour cells only (11 §7 item 10) |
| Host (normal) cells | Omitted | A `host` kind with uptake β/3; J, γ_e and death rule UNSPECIFIED (11 §7 item 8) |
| Vessel geometry | Placeholder straight vessel | From figures (UNSPECIFIED, §7 item 11) |
| 11b ODE Δt | 0.05 (code excerpt p.14) | 0.03 (text p.11) |
| 11b trigger | `kz` 1.5 → 1.0 at MCS 70 (layer) | MCS 200 (tumour from layer), 400 (MTS, with c_T = 70 during growth) |
| 11b dimension | 2D adaptation (conformance only) | 3D as published (out of scope, 11 §8) |
