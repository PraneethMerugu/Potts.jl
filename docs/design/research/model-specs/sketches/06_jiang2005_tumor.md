# 06 — Jiang, Pjesivac-Grbovic, Cantrell & Freyer 2005, multiscale avascular tumour: target authoring sketch

> **Draft input, superseded by `api-synthesis.md` (D-075).** Kept for audit; the syntax here is not the ratified API.

> **DRAFT — not final.** Target authoring sketch; syntax for unbuilt features is proposed, not decided.

- **Model:** an EMT6/Ro spheroid grown from one cell in 3D.
  - Cells: a Potts model with adhesion + volume and no surface term. Kinds are
    proliferating (P), quiescent (Q) and necrotic (N).
  - A per-cell Boolean G1/S network (Fig 2) gates the cycle through a sigmoidal factor
    level (Eq 4).
  - Five reaction–diffusion fields (O₂, glucose, lactate, growth factor, inhibitor) live
    on a ×4 coarse grid, with a moving Dirichlet boundary on the medium.
  - One iteration is ¼ MCS of copies, then 45 min of chemistry, then the network and the
    rules (Fig 3).
  - Dead cells join one rigid necrotic core. Surface cells shed.
- **Paper:** Jiang Y et al., Biophys J 89(6): 3884–3894 (2005); erratum Biophys J 91(2):775
  (2006).
- **Spec:** `../06_jiang2005_tumor.md` (§2, §3, §6, §7). Decisions: README §4.4 (J1–J8),
  D-051 items 2 and 4, D-065 Q9, D-066 item 7. Roadmap: ROADMAP P6.11 (3D, R10 fractional
  attempts, R5 coarse grids + moving Dirichlet, R14 implicit transient, R13 Boolean, R8
  `sites => ref`, R15). **Gate:** J3 (Rb → E2F polarity).
- **Date:** 2026-09-30.

Tags: `# [R#]` is a planned roadmap feature. `# [NEW]` is not on the roadmap. `# [?]` means
the primitives exist but this combination is untested. A line with no tag uses only what
exists at `monorepo` HEAD. `UNSPECIFIED` is a placeholder that must be set before a run.

**Time convention in this sketch.** With `attempts = 1//4` one Potts *step* is one Fig 3
iteration: ¼ paper MCS, 45 min. `mcs`, `Pre`, `Every` and the after-MCS rules all count
steps: 4 steps = 1 paper MCS = 3 h, and 32 steps = 1 day.

```julia
using Potts, ModelingToolkit, OrdinaryDiffEq, LinearSolve
using ModelingToolkit: t_nounits as t
const UNSPECIFIED = NaN

# Subcellular scale: the Fig 2 network as an MTK clocked component (R13; D-065 Q9: no Potts helper)
function G1SNetwork(; name, rb_e2f = :inhibitory)       # J3 BLOCKING: drawn stimulatory, provisional inhibitory
    k = ShiftIndex(Clock(1))                              # [R13] one tick per Potts step
    @variables GSK3b(t)=1 TGFb(t)=1 SCF(t)=1 SMAD(t)=0 P15(t)=0 P27(t)=0 P21(t)=0 CycD(t)=0 CycE(t)=0 Rb(t)=0 E2F(t)=0
    @parameters F θ stage u[1:8]                          # factor level (Eq 4), threshold, G1 stage, uniform draws
    # tier τ updates at G1 stage τ (06 §2.4 inference); above θ the rule is deterministic, below it the
    # rule applies with probability F (reading (a) of three; UNSPECIFIED, 06 §7.2)
    gate(x, rule, τ, i) = ifelse(stage == τ, ifelse((F > θ) | (u[i] < F), rule, x(k - 1)), x(k - 1))
    on(x) = x(k - 1)
    off(x) = 1 - x(k - 1)
    eqs = [GSK3b(k) ~ on(GSK3b), TGFb(k) ~ on(TGFb), SCF(k) ~ on(SCF),        # tier 1: later cycles UNSPECIFIED
        SMAD(k) ~ gate(SMAD, on(TGFb), 2, 1),                                  # TGFb → SMAD
        P15(k) ~ gate(P15, on(SMAD), 3, 2),                                    # SMAD → P15
        P27(k) ~ gate(P27, on(SMAD) * on(SCF), 3, 3),                          # SMAD → P27, SCF → P27 (all stimulatory: AND)
        P21(k) ~ gate(P21, on(SCF), 3, 4),                                     # SCF → P21
        CycD(k) ~ gate(CycD, off(GSK3b) * off(P15) * off(P27), 4, 5),          # all inhibitory: on iff all inputs off
        CycE(k) ~ gate(CycE, off(P27) * off(P21), 4, 6),
        Rb(k) ~ gate(Rb, off(CycD) * off(CycE), 5, 7),
        E2F(k) ~ gate(E2F, rb_e2f === :inhibitory ? off(Rb) : on(Rb), 6, 8)]   # J3
    return System(eqs, t; name)
end

@potts_model Jiang2005Spheroid begin
    @structural_parameters begin
        lattice = UNSPECIFIED       # voxels, 3D (06 §2.1); Fig 4 ≈ 1300 µm (read from figure); J8: use a larger one
        Δx = cbrt(1200 / 64)        # ≈ 2.66 µm/voxel (06 §3.2)
        erratum = false             # J1: b₀(P) = 162 (default) | 216 (erratum 06b)
        chart_death = false         # J2: text (P → Q, Q → N) default | Fig 3 chart (P dies)
    end
    @kinds medium proliferating quiescent necrotic         # 06 §2.3
    @parameters begin
        T = UNSPECIFIED                                    # 06 §2.2
        #                 M    P    Q            N          (06 p.6 [3889])
        J[kind, kind] = [0   16   14           12;
                         16  28   28           24;
                         14  28   UNSPECIFIED  22;          # J_QQ UNSPECIFIED
                         12  24   22           UNSPECIFIED] # J_NN moot: one core cell
        γ_P = UNSPECIFIED            # "usually … between 1 and 3" (06 p.6)
        γ_N = UNSPECIFIED            # "large", rigid (06 p.3)
        V_init = UNSPECIFIED         # 27 ("typical") vs 32 (2 × initial ≤ 64) (06 §7.1 item 6)
        tol_vol = UNSPECIFIED        # volume-checkpoint tolerance (06 §2.4)
        α_F = UNSPECIFIED            # Eq 4 slope
        θ_F = UNSPECIFIED            # Eq 4 threshold
        a₀[kind] = [0.0, 108.0, 50.0, 0.0]                        # O₂ mM/h (Table 1; unit per erratum)
        b₀[kind] = [0.0, erratum ? 216.0 : 162.0, 80.0, 0.0]      # glucose (J1)
        C₀[kind] = [0.0, 240.0, 110.0, 0.0]                       # lactate production
        d₀[kind] = [0.0, 1.0, 0.5, 0.0]                           # GF, %/h/cm³ (unit open, 06 §7.1 item 5)
        e₀[kind] = [0.0, 0.0, 1.0, 2.0]                           # IF; N only within 24 h of death (J6)
        w_N = 10.0                                                # necrotic waste, mM/h for 24 h (06 p.10)
        D_O2 = 5.94e-2 * 1e8; D_n = 1.52e-3 * 1e8; D_w = 2.124e-3 * 1e8   # µm²/h (Table 1)
        D_gf = 1e-6 * 1e8; D_if = 1e-6 * 1e8                     # J5: Table 1 (text: 10⁻⁷ for one)
        uO_O2 = 0.28; uO_n = 5.5                                  # optimal concentrations (06 p.9)
        uT_O2 = 0.02; uT_n = 0.06; uW = 8.0                       # necrosis thresholds = u^T (06 p.6; §2.5 reading)
        u0_O2 = 0.08; u0_n = 5.5                                  # medium: calibration (Fig 5); prediction 0.28 / 16.5 (Fig 8)
        p_shed = 0.2; R_shed = 300.0 / Δx                         # 20 % once R > 0.03 cm (06 p.5)
        window = 32                                               # 24 h in steps (06 p.4)
    end
    @variables begin
        O2(field) = 0.0, [grid = Coarse(4)]                       # [R5] ×4 coarse grid (06 p.10); none inside at t = 0 (06 p.9)
        glc(field) = 0.0, [grid = Coarse(4)]                      # [R5]
        lac(field) = 0.0, [grid = Coarse(4)]                      # [R5]
        gf(field) = 0.0, [grid = Coarse(4)]                       # [R5]
        inh(field) = 0.0, [grid = Coarse(4)]                      # [R5]
        alive_at(site) = 0.0                                      # last step the site was not necrotic
        V_target(cell) = 2V_init                                  # P: twice the initial volume (06 p.3)
        γ(cell) = γ_P
        stage(cell) = 1.0                                         # 1–16: G1 1–6, S 7–12, G2/M 13–16 (06 p.4)
        R_sph(model) = 0.0
    end
    @components cells(proliferating, quiescent) grn = G1SNetwork()   # [R13][R3] kind-set scope, survives P → Q
    @lattice Lattice(lattice; spacing = Δx, boundary = Closed(), neighborhood = Moore(1))   # order UNSPECIFIED (06 §2.1)

    @energy begin
        contacts => J[kind, kind′]                                          # Eq 1, no surface term (06 §2.3)
        cells(proliferating, quiescent, necrotic) => γ * (volume - V_target)^2   # medium has no target
    end

    fO2 = (O2 - uT_O2) / (uO_O2 - uT_O2)                   # a/a₀ (Appendix, 06 p.9); uncapped (06 §7.1 item 7)
    fn = (glc - uT_n) / (uO_n - uT_n)                      # b/b₀
    fresh = (kind == necrotic) * (mcs - alive_at <= window)   # [?] 24 h after death (06 p.4, p.10)
    @equations begin                                       # signs inferred (06 §3.3)
        D(O2) ~ D_O2 * Δ(O2) - a₀[kind] * fO2
        D(glc) ~ D_n * Δ(glc) - b₀[kind] * fn
        D(lac) ~ D_w * Δ(lac) + C₀[kind] * (fO2 + fn) / 2 + w_N * fresh      # c = C₀(a/a₀ + b/b₀)/2
        D(gf) ~ D_gf * Δ(gf) - d₀[kind]
        D(inh) ~ D_if * Δ(inh) + e₀[kind] * ifelse(kind == necrotic, fresh, 1.0)
    end
    @boundary (kind == medium) => [O2 => u0_O2, glc => u0_n, lac => 0.0, gf => 1.0, inh => 0.0]   # [R5] moving Dirichlet (06 p.9)

    cmean(u) = integral(u) / volume                        # "average of the grid points within that cell" (06 p.10); Friction 3
    hostile = (cmean(O2) < uT_O2) | (cmean(glc) < uT_n) | (cmean(lac) > uW)   # J4: OR
    @equations begin                                       # [R13] couple the network to cell scope
        grn.F ~ 1 / (1 + exp(-α_F * ((cmean(gf) - cmean(inh)) / 1.0 - θ_F)))   # Eq 4, initGF = 1 (relative, 06 p.5)
        grn.θ ~ θ_F
        grn.stage ~ stage
        grn.u ~ [rand() for _ in 1:8]                      # [NEW] vector of addressed draws into a component
    end
    @after_mcs begin
        alive_at ~ ifelse(kind == necrotic, Pre(alive_at), mcs)
        stage ~ ifelse((kind == proliferating) & (Pre(stage) < 16), Pre(stage) + 1, Pre(stage))
        R_sph ~ cbrt(3 / 4π * sum(volume[c] for c in cells(proliferating, quiescent, necrotic)))   # radius def. UNSPECIFIED
    end

    checkpoint = (stage == 6) | (stage == 12) | (stage == 16)                 # end of each phase (06 p.4)
    arrest = ((stage == 6) & (grn.E2F < 0.5)) |                               # E2F off → quiescent (06 p.4); check timing UNSPECIFIED
             (checkpoint & (volume < V_init * (1 + stage / 16) * (1 - tol_vol)))   # "proportional to the time"
    dying = chart_death ? (kind == proliferating) & hostile : (kind == quiescent) & hostile   # J2
    no_core = count(true for c in cells(necrotic)) == 0
    @transition cells(proliferating) => quiescent when = arrest | (hostile & !chart_death),   # [R3] 06 p.4
        V_target => volume, γ => 4γ                                           # 06 p.6
    @transition cells(proliferating, quiescent) => necrotic when = dying & no_core,   # [R3] first death becomes the core (D-066)
        V_target => volume, γ => γ_N                                          # 06 p.3
    @retire cells(proliferating, quiescent) when = dying & !no_core,         # [R3][R8] later deaths join the core
        sites => the(necrotic), V_target[the(necrotic)] += volume            # [R8][NEW the] "volume added to the core" (06 p.4)

    ready = (stage >= 16) & (volume >= V_target)                              # clock and volume (06 p.3)
    on_surface = any(kind[n] == medium for n in neighbors(c))                 # [R11a] "surface" UNSPECIFIED (06 §7.2)
    @retire cells(proliferating) when = ready & on_surface & (R_sph > R_shed) & (rand() < p_shed)   # [R3] shedding (06 p.5)
    @divide cells(proliferating) when = ready, along = RandomPlane(),        # half the volume to a new id (06 p.3); plane UNSPECIFIED
        stage => 1.0                                                          # "inherit all properties": all else Copy()

    @observed begin
        n_viable(model) ~ count(true for c in cells(proliferating, quiescent))              # Fig 5
        g1(model) ~ count(true for c in cells(proliferating) if stage[c] <= 6) / n_viable   # Fig 6
    end
    @sweep Metropolis(; temperature = T, attempts = 1 // 4,                   # [R10] ¼ MCS per iteration (Fig 3; D-051 item 2)
        mcs_duration = 0.75,                                                  # h: "solve … for 45 minutes" (Fig 3)
        field_solver = Adaptive(ImplicitEuler(linsolve = KrylovJL_CG())),     # [R14] J7 implicit transient
        order = (Sweep(), Fields(), Components(), Lifecycle()))               # [R5][NEW syntax] Fig 3 order
end

@named sys = Jiang2005Spheroid(; lattice = UNSPECIFIED)
c = sys.lattice.dims .÷ 2
op = layout(Tiling((3, 3, 3); region = map(i -> (i - 1):(i + 1), c), kinds = [:proliferating]), sys)   # one cell, centre (06 p.4)
prob = PottsProblem(sys, op, (0, 32 * 30))            # 30 days in steps (saturation ≈ 28–30 d, 06 §5 T2)
sol = solve(EnsembleProblem(prob; trajectories = 10), SequentialCPM(); saveat = 0:32:960)   # ≥ 10 seeds (06 §5)
```

## Line → source

| Line / rule | Spec | Paper |
|---|---|---|
| `contacts => J`, J values | 06 §2.3, §3.1 | Eq 1 (p.3 [3886]); J values p.6 [3889] |
| `cells(P, Q, N) => γ (volume − V_target)²` | 06 §2.3 | Eq 1; "medium does not have a target volume" (p.3) |
| `V_target = 2V_init` (P) | 06 §2.3, §3.1 | p.3 [3886] |
| P → Q: `V_target => volume`, `γ => 4γ` | 06 §2.3 | p.6 [3889] |
| first death → necrotic, `γ => γ_N`; later deaths `sites => core`, `V_target += volume` | 06 §2.3, §6 G10/G14; D-066 item 7 | p.3 [3886], p.4 [3887] |
| G1SNetwork edges and node rule | 06 §2.4 | Fig 2 (p.4 [3887]); update rule text p.4 |
| `rb_e2f = :inhibitory` | 06 §7.1 item 2; README J3 | Fig 2 draws Rb → E2F |
| factor level `grn.F` | 06 §2.4 | Eq 4 (p.4 [3887]) |
| `stage`, 16 stages, `checkpoint`, `arrest` | 06 §2.4 | p.4 [3887] §Simulation; Fig 3 |
| `hostile` (O₂ < 0.02, glc < 0.06, lac > 8, OR) | 06 §2.4, §3.1; README J4 | p.6 [3889], p.8 [3891] |
| `dying` (text vs chart) | 06 §7.1 item 1; README J2 | p.4 text vs Fig 3 (p.5 [3888]) |
| `ready`, `@divide` | 06 §2.4 | p.3 [3886] |
| shedding `@retire` | 06 §2.4, §3.1 | p.4–5 [3887–3888] |
| five `D(u) ~ …` fields | 06 §2.5 | Eq 3 (p.3); Appendix (p.9 [3892]) |
| `fO2`, `fn`, lactate `(fO2 + fn)/2` | 06 §2.5 | Appendix a, b, c (p.9) |
| Table 1 rates, erratum 216 | 06 §3.1, §3.4; README J1 | Table 1 (p.5 [3888]); erratum 06b |
| necrotic secretion window `fresh`, `w_N`, `e₀[N]` | 06 §2.4, §3.1; README J6 | p.4 [3887]; p.10 [3893]; Table 1 |
| `@boundary (kind == medium) => …` | 06 §2.5 | Appendix BCs (p.9) |
| `grid = Coarse(4)`, `cmean` | 06 §2.5 | p.10 [3893] |
| `attempts = 1//4`, 45 min, order | 06 §2.1, §2.4 (loop), §2.5 | Fig 3 (p.5 [3888]); p.4 [3887]; 4 MCS = 12 h (p.5) |
| implicit transient | 06 §2.5, §3.2; README J7 | Fig 3 |
| `Δx = cbrt(1200/64)` | 06 §3.2 | p.5 [3888] |
| one central cell | 06 §2.4, §6 G13 | p.4 [3887] |

## Status of primitives used

| Primitive | Status |
|---|---|
| 3D `Lattice`, `J[kind, kind]`, per-kind vectors `a₀[kind]`, cell variables with parameter defaults, `Pre`, `integral`, `rand()`, population `count`/`sum` folds, `@divide … RandomPlane()`, `Tiling` layout, `@components cells(k)` (ODE, D-038), coupling `@equations comp.p ~ expr` | exists |
| site variables on necrotic sites via `@after_mcs` (`alive_at`) | exists `[?]` (update order against the lifecycle is untested) |
| `cells(k1, k2)` component scope that survives `@transition` | planned R3 ("scope across transitions", README §2.4) |
| MTK clocked discrete component per cell (`ShiftIndex`, `Clock`) | planned R13 / P6.0k spike (D-065 Q9) |
| vector coupling `grn.u ~ [rand() for _ in 1:8]` | NEW |
| `attempts = 1//4` | planned R10 (P6.4b; D-051 item 2) |
| `[grid = Coarse(4)]` variable metadata | planned R5 (D-051 item 4); the spelling is NEW |
| `@boundary (kind == medium) => [...]` over several fields | planned R5 (moving kind-defined Dirichlet); the multi-field form is NEW |
| `Adaptive(...)` as `field_solver` | planned R14 (today `field_solver` must be `ExplicitEuler`) |
| `order = (Sweep(), Fields(), Components(), Lifecycle())` | planned R5 (explicit phase order); the spelling is NEW |
| `@transition` with state rules | planned R3 (P6.4c) |
| `@retire … sites => ref`, scatter-add `V_target[ref] += volume` | planned R8 (P6.5b / P6.11) |
| `the(kind)` (the unique live cell of a kind) | NEW (or an R6 model-scope `CellRef` variable) |
| `neighbors(c)` in a rule's `when` | planned R11a (AUTHORING §12.3 shows it only in `@observed`) |

## Friction found

1. **Step vs MCS naming.** With `attempts = 1//4`, every DSL clock counts ¼-MCS steps:
   - `mcs`, `Pre(x, k)`, `Every(n)`, the after-MCS phase and the lifecycle cadence;
   - `mcs_duration`, which here is the 45 min per step.

   The model reads cleanly in steps, but the paper's "4 MCS to double" and "1 MCS = 3 h"
   must be converted by hand, and the name `mcs` is misleading. Proposal: a `step` alias,
   or report both `mcs` (fractional) and `step`. Decide this in R10.
2. **Necrotic core bootstrap race.** The D-066 route is:
   - the first death `@transition`s into the core;
   - later deaths `@retire … sites => core`.

   It breaks when several cells die in the step where no core exists yet. All of them
   pass `no_core`, so several necrotic cells appear. R8's priority (remove > transition)
   evaluates the retire first, but `no_core` is still true for everyone. From then on,
   `sites => the(necrotic)` is ambiguous. Needed:
   - a way to name the core: a model-scope `core::CellRef` (R6) written by the
     transition, or `the(kind)` [NEW];
   - either a "fire for at most one cell" option on `@transition` (`limit = 1`, [NEW]) or
     a follow-up merge rule `@retire cells(necrotic) when = id != min_id, sites => …`.

   `V_target[ref] += volume` is a cross-cell scatter-add from a cell rule. It is in R8
   ("scatter-add rules"), but it has no spelling yet.
3. **Coarse-grid semantics are undefined** (R5, D-051 item 4). The model needs four
   answers:
   - what a fine-site read `O2` returns (injection or trilinear prolongation);
   - how the kind-dependent sources `a₀[kind]` restrict (the average of the 64 fine-site
     sources);
   - which coarse nodes the moving Dirichlet `kind == medium` clamps (any, majority or all
     medium fine sites);
   - what the paper's "average of the grid points within the cell" means. With injection,
     `integral(u)/volume` is volume-weighted, which is not the same thing.

   Each field needs a declared restriction/prolongation pair, plus a coarse-node
   predicate rule for boundary masks.
4. **The printed rate law divides by zero.** c = C₀(a/a₀ + b/b₀)/2 is 0/0 for necrotic
   cells (a₀ = 0). The sketch rewrites it through fO2 and fn. The law is also uncapped
   above uO (b ≈ 3b₀ at 16.5 mM) and turns negative, i.e. into production, below uT.
   Neither case is specified (06 §7.1 item 7). A `clamp` is one keyword, but which clamp
   applies is an author question.
5. **Boolean network plumbing (R13).**
   - The node rule needs 8 fresh uniforms per cell per step. An MTK component cannot call
     Potts' addressed `rand()`, so the draws enter as a vector parameter coupled from cell
     scope. That vector coupling is new syntax.
   - `Clock(1)` must be *defined* as one Potts step, including under fractional attempts.
   - The tier gate needs `stage` to be read consistently: the component reads `grn.stage`
     before or after the `@after_mcs` increment, depending on the phase order.
   - Top-tier states after the first cycle and in daughters are UNSPECIFIED. `Copy()`
     keeps the parent's final network state.
   - D-065 Q9 forbids a Potts truth-table helper, so the `gate` closure is user code. It
     is readable, but the family (Jafari, 11) will rewrite it. A tiny *MTK-side* helper
     library would be appropriate.
6. **Per-cell rigidity changes.** `γ => 4γ` on P → Q and `γ => γ_N` on death require R3
   state rules to evaluate their right-hand sides on the **pre-transition** cell, as
   `@divide` rules do. This must be stated in R3. A per-kind `γ[kind]` cannot express
   "4 × its prior value".
7. **Shedding and division share one event.** They are two rules on the same `ready`
   condition. Exclusivity relies on R8's priority (remove before divide). `rand()` in the
   retire rule is its own stream, so the draw is fine, but the model silently depends on
   the priority order. A single rule with branches (`@divide … unless = shed`) would state
   the intent.
8. **Neighbour-cell iteration in rules.** "Surface cell" is `any(kind[n] == medium for n in neighbors(c))`.
   R11a plans `neighbors(c)` at MCS cadence for `@observed`; rule `when` scope must also
   be covered. With a Dirichlet medium, `integral(any(kind[n] == medium for n in Moore(1)(site)))`
   would also work, but only if gathers are allowed inside `integral` bodies (same gap as
   05, Friction 5).
9. **Site "time of death".** A naive `@on_copy died[target] ~ mcs` misses both
   `@transition` (a kind change with no ownership change) and `@retire … sites => core`
   (an ownership change outside the sweep, unless R8 fires the hooks). The sketch sidesteps
   this with a per-step site update (`alive_at`), which is exact but costs a pass over all
   sites every step. An ownership/kind-change hook on sites would be cheaper. R8 promises
   hooks for ownership changes only, not kind changes.
10. **Field stiffness and solver.** D_O₂ ≈ 2.5×10⁶ voxel²/MCS (06 §3.2). On the coarse
    grid that is still ≈ 4×10⁴ node²/step, so the 45-min transient must be implicit. That
    needs R14 fields plus P6.0c per-field solvers (all five are implicit here, so one
    global solver would do).
11. **Phase order.** Fig 3 fixes sweep → chemistry → network → decisions. Today the order
    of `@equations` fields, component updates, `@after_mcs` and the lifecycle is not a
    user choice (README §2.4 "explicit phase order"). The spelling (`order = (...)`) is
    NEW.
12. **Local helper expressions.** `hostile`, `ready`, `fO2` and the others are plain
    Julia bindings in the model body. Functions like `act_mean` are already used this way
    (`wortel_act.jl`), but reusing a bound symbolic *expression* across several sections
    (energy, rules, equations) is assumed to work. That is `[?]`, worth a test.
13. **J_QQ is needed; the paper says adhesion is irrelevant.** The one-J variant (T11)
    is the natural fallback until the author answers.

## Open choices

| Choice | Default (spec / README) | Variant |
|---|---|---|
| b₀(P) | 162 (J1) | `erratum = true` → 216 |
| Death branch | text: P → Q, Q → N (J2) | `chart_death = true`: P dies |
| Rb → E2F | **blocking** (J3); provisional inhibitory | as drawn (stimulatory) |
| Necrosis conditions | OR (J4) | AND |
| GF/IF diffusivity | Table 1: 10⁻⁶ both (J5) | text: 10⁻⁷ / 10⁻⁶; sweep for T10 |
| Necrotic IF secretion | Table 1: 2 %/h/cm³ (J6) | Appendix: 0.1 ml/h |
| Field solve | implicit 45-min transient (J7) | quasi-steady `0 ~ …` per step |
| Lattice size | larger than the paper's (J8) | – |
| Below-threshold network update | reading (a): the rule applies with probability F | node on with probability F; node flips with probability F |
| E2F check | end of G1 (stage 6) | every G1 stage |
| Initial cell volume | UNSPECIFIED: 27 (typical) | 32 (= half of the 64 maximum) |
| Rate cap above optimum | uncapped (as printed) | cap at a₀, b₀ |
| Quiescence | irreversible (re-entry UNSPECIFIED) | Q → P when favourable |
| Seeds | ≥ 10 seeds, initial stage 1 (sketch) | random initial stage (06 §5, as the authors suggest); single run (as the paper) |
