# P6.5a (ROADMAP Phase 6, step 5; first step of Fortuna, reproduction 14): R6 cell
# references, liveness per D-066 and claim widening. Frozen (AUTONOMY §7.3).
# Decisions: D-066 (liveness, `birth`, references, boundaries, self-check credits), D-065 Q7
# (sequential is the reference; the checkerboard is validated statistically), D-053 item 7
# (references widen claim sets automatically), D-058 (shared read claims, `reads`; zero cost
# when off), D-036 (clusters), D-075 / api-synthesis §2.6–2.7 (the reference vocabulary),
# D-209 (an energy may not read what a copy changes beyond ΔH), D-048 (oracles, negative
# controls).
#
# ROADMAP: "R6: cell references (`sibling`, `members`, `root`, `partner`, `x[ref]`);
# liveness per D-066 (alive ⇔ volume > 0; `birth` serial; `CellRef` references cleared at
# allocation boundaries; exact self-check credits); claim widening, with checkerboard
# validated statistically against sequential (D-065 Q7)."
#
# =========================================================================================
# THE PUBLIC API THESE TESTS EXPECT (names, signatures, semantics)
# =========================================================================================
#
# A. Reference variables. `@variables begin partner(cell)::CellRef end` declares a cell
#    variable holding a reference to another cell (D-066 item 5: "cell variables of a
#    declared reference type (e.g. `partner::CellRef`)"). `partner` is not a built-in: it is
#    the user's name, as `prev`/`next` in the myxobacteria sketch.
#    - `CellRef` is bound inside model bodies (a new `Potts.DSL` name; the implementer adds
#      it to `DSL_NAMES` in guardrails.jl).
#    - Default 0 (no reference, the medium). The operating point sets it by slot:
#      `:partner => [2, 3, 1, 3, 0, 6]`. A cell may reference itself.
#    - Stored as the integer column `u.cell.partner` (`eltype <: Integer`), one entry per slot.
#    - Daughters copy reference variables like every other cell variable (D-066 item 5).
#    - An update may write one: `@after_mcs nuc ~ sibling(nucleus)`.
#    - A reference compares with `==` against `id`, another reference or 0.
# B. Reference sources (api-synthesis §2.7; cell scope = updates, rules, `@observed`):
#    - `sibling(k)`: the alive member of kind `k` of the current cell's cluster (the cell
#      itself when it is of kind `k`), or 0 when the cluster has none. `sibling(c, k)` is the
#      same for cell `c` (inside population folds such as `for c in cells(cytoplasm)`).
#    - `root(cluster)`: the cluster's root (`cluster[c]`, D-036) as a reference; a lone cell
#      is its own root. A copy-killed root (still naming its cluster, D-066 item 4) reads as
#      a dead referent.
#    - `members(cluster)`, `members(cluster, k)`: a fold domain over the ALIVE cells of the
#      cluster (of kind `k`), the cell itself included; the bound name is the generator's
#      (`m` below): `sum(volume[m] for m in members(cluster))`,
#      `count(true for m in members(cluster, nucleus))`.
#    - Not pinned here: `sibling`/`members`/`root` inside `@energy`/`@drive` (no consumer
#      needs them in the sweep: Fortuna reads them at boundaries only, 14 sketch §4 item 11);
#      `sibling(k)` when a cluster has several alive members of kind `k`; the value of a raw
#      reference to a dead cell (only its dereference is pinned).
# C. Dereferencing, `x[ref]`: `q[ref]` (a cell variable), `kind[ref]`, `volume[ref]`,
#    `birth[ref]`, `alive(ref)`, and chains (`partner[partner[old]]`). A DEAD referent
#    (volume 0), and ref 0, read as the medium: kind 0, volume 0, `birth` 0, `alive` false,
#    and every cell variable at its declared DEFAULT (here `q(cell) = 5.0`, so the default is
#    distinguishable from 0) (D-066 item 5). In copy scope (`@drive`, `@constraint`)
#    `volume[partner[old]]` reads the referent's current volume.
# D. Energies (cell terms). A cell term may read through a reference only what no copy
#    changes: cell variables no `@on_copy` writes, `kind`, `birth`, `alive(ref)`, e.g.
#    `λ * (volume - V₀ - q[partner])^2 + μ[kind, kind[partner]] * volume`. Reading a
#    copy-varying quantity of a referent in an energy (`volume[partner]`) is refused at
#    `mtkcompile` with D-209's `ArgumentError` (its message contains "a copy changes" and
#    "in @energy cells"): ΔH evaluates only the copy's two cells, exactly as D-209 already
#    refuses `volume[id]` and as `cluster_volume` is not readable in cell energies. A
#    drive may read it (drives are copy-scope work terms, not part of H).
# E. ΔH and the self-check credits (D-066 item 4, extended). ΔH reads every referent in the
#    PRE-COPY state (one load and a select in reference-reading code, D-066 item 5: no
#    reverse lookup of readers). So a copy that kills a referent `o` changes the energy of
#    every alive cell that reads `o` (they now read the medium) without ΔH seeing it; the
#    gainer `n`, if it reads `o`, is evaluated with its after-values and `o` as before.
#    `total_energy` (H) dereferences in the state it is given: alive cells read their
#    referents, dead referents read as the medium. The self-check is exact:
#
#        energy_change(prob, u, prop) ==
#            total_energy(prob, a) − total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a)
#
#    for EVERY copy (|gap| < 1e-9), where `a` is the state after the copy and the credit is
#      E_cell(o, empty state)                      (as today, P6.0r / D-083)
#      + Σ_{c alive in a, c ≠ o} [ E_c(c's values in a; referents read in u) − E_c(a) ].
#    For a copy that kills nobody the second sum is 0. The credit is checked against an
#    independent oracle (the test's own E_c), and `total_energy` against the same oracle.
# F. Liveness and `birth` (D-066 items 1, 3).
#    - `alive(ref)` ≡ `volume[ref] > 0` (a read-only built-in).
#    - `birth`: a read-only cell-scope built-in, a monotone serial never reused. Initial cells
#      get 1:n. Each division daughter in a NEW slot gets the next serial (`next_birth`, a
#      counter stored in the state and checkpointed, not max+1); the parent keeps its slot and
#      its `birth`. `birth` is not copied to daughters. With slot reuse (lowest-first, D-066
#      item 3) a daughter in a dead cell's slot gets a new serial, never the dead cell's nor
#      its slot number. In a model with a lifecycle the serial is the column
#      `u.cell.birth::Vector{Int32}`; in a model without births `birth ≡ slot` (D-066 item 3).
#      `observe(prob, :bth, u)` with `@observed bth(cell) ~ birth` reads it per slot.
#    - Not pinned here (D-066 item 3's output mapping): SII `id`, `cluster` as `birth[root]`,
#      plots, `write_piff(…; ids = birth)`, `with_capacity`; a daughter that receives no site.
# G. Boundaries (D-066 item 5 (a)). In the lifecycle plan of an event MCS, BEFORE any id is
#    allocated, every reference to a dead cell is reset to 0, so a reference never aliases
#    the new cell that reuses the slot (and a daughter copies the reset value). On quiet MCS
#    the stored value is not pinned, only its dereference (C). (b), R8's routine, is P6.5b.
# H. Claim widening (D-053 item 7, D-058, D-065 Q7). For every copy, the cells that the
#    copy's sweep functions read through references (`partner[old]`, `partner[new]` and every
#    hop of a chain such as `partner[partner[old]]`, nonzero ones) are in
#    `prob.f.reads(st, p, prop, ctx) ∪ prob.f.claims(st, p, prop, ctx)` (shared reads, or
#    exclusive claims, which D-058 notes is also exact). A model whose sweep (energies,
#    drives, constraints) reads no reference keeps the plain kernel path:
#    `CorePotts.has_reads(prob.f) == false` and no extra claims (D-058 item 4, zero cost
#    when off), even when its updates and observables use references.
#    CheckerboardCPM is then validated STATISTICALLY against SequentialCPM (D-065 Q7), with
#    the pre-registered protocol of section 6, and the protocol must detect a deliberately
#    broken widening (the same problem with `reads`/`claims` stripped).
#
# =========================================================================================
# Statistical protocol (section 6), pre-registered
# =========================================================================================
# Fixture P65aPair: two cells of kind `cell` (V₀ = 30, λ = 1, J_cell,medium = 6,
# J_cell,cell = 2) on a closed 16×31 lattice, separated by a frozen wall column (column 16),
# so they never touch; `partner = [2, 1, 0]`. A drive couples their volumes:
#     κ(1 − 2(V_old − V_partner[old])) [old a cell] + κ(1 + 2(V_new − V_partner[new])) [new a cell]
# which is the exact ΔU of U = κ(V₁ − V₂)² for copies that change one of the two cells, so
# SequentialCPM samples exp(−(H + U)/T). κ = 6, T = 24. A checkerboard copy of cell 1 whose
# drive reads V₂ while a copy of cell 2 commits in the same colour sees a stale V₂; the
# widening forbids that pair.
#  - Statistic S (one value per replicate): the mean of (V₁ − V₂)² over the saved states at
#    MCS t = 50, 51, …, 400 (`saveat = 1`, `tspan = (0, 400)`).
#  - Replicates: seeds 1:32 for every arm. Arms: SequentialCPM (reference), CheckerboardCPM
#    (candidate), CheckerboardCPM on the problem with reads/claims stripped (negative
#    control), and SequentialCPM with seeds 33:64 (the test's null).
#  - Test: Welch t = (x̄ − ȳ)/√(s²ₓ/32 + s²ᵧ/32), critical value 3.89 (two-sided α = 1e-4
#    under the normal reference, as P6.4b1 FULL; the t reference at the Welch df ≈ 60 puts
#    1e-4 at ≈ 4.1, so 3.89 is slightly stricter for the agreement test). Agreement:
#    |t(candidate, reference)| ≤ 3.89. Null: |t(seq 33:64, seq 1:32)| ≤ 3.89. Negative
#    control: |t(stripped, reference)| > 3.89.
#  - Calibration on the freeze base, with a stub in which the partner was `3 − id` and the
#    widening was installed by hand as `reads = (partner[old], partner[new])` (the D-058
#    mechanism the implementation is expected to use): reference mean 1.87, candidate t =
#    −1.11 (seeds 1:32) and −0.66 (seeds 33:64), stripped t = +7.67 and +7.92. The exact
#    widening keeps a small checkerboard bias of its own (deferred copies): −2.4 % ± 0.5 %
#    over 200 × 1000 MCS; the broken one +16.4 % ± 0.5 %. Light tier: 128 runs of 400 MCS,
#    about 2 s.
#  - FULL tier (POTTS_FULL_REPRODUCTION=true or REPRO=full): seeds 1001:1200, `tspan =
#    (0, 1000)`, S over t = 100…1000; equivalence with a stated margin, because a powerful
#    difference test would reject the checkerboard's own −2.4 %: pass iff the two-sided
#    99.9 % interval (z = 3.29) of the relative difference (x̄_cb − x̄_seq)/x̄_seq lies inside
#    ±0.06; the stripped problem's interval must lie entirely outside ±0.06 (calibrated:
#    [−4.1 %, −0.8 %] and [+14.7 %, +18.0 %]). About 15 s.
#  - Device (POTTS_GPU set): CheckerboardCPM on the device (Float32) with seeds 1:32 against
#    the CPU SequentialCPM sample, |t| ≤ 3.89.
#
# Sections: 1 references and dereferencing (cluster fixture); 2 updates writing and reading
# references; 3 energies: H, ΔH and the exact self-check credits; 4 liveness, `birth`,
# boundaries (lifecycle fixture, checkpoint); 5 claim sets; 6 the statistical validation;
# 7 device. Fixtures that use the new syntax are defined through `p65a_define`, so a build
# failure today fails the testsets that use them instead of aborting the file.
using Test, Potts, PottsModels
using Potts: CorePotts
using Statistics: mean, var

const P65A_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"

# ---------------------------------------------------------------------------------------
# 0. Helpers

const P65A_DEFINE_ERRORS = Dict{Symbol, Any}()
function p65a_define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        P65A_DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
p65a_model(name::Symbol) = isdefined(@__MODULE__, name) ? getfield(@__MODULE__, name) :
                           error("P6.5a fixture $name did not build: $(get(P65A_DEFINE_ERRORS, name, "unknown"))")
p65a_system(name::Symbol; sysname = :m) = Base.invokelatest(p65a_model(name); name = sysname)

p65a_vol(u) = Array(u.cell.volume)
p65a_col(u, n) = Array(getfield(u.cell, n))
p65a_ctx(prob) = Potts._host_ctx(prob)

# every Moore(1) copy (target t takes source s's owner); `touching` restricts to copies
# whose old or new owner is in the set
function p65a_props(prob, u; touching = nothing)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    σ = Array(u.σ)
    out = CorePotts.Proposal{2}[]
    for t in eachindex(σ)
        x = CorePotts.coordinates(lat, t)
        for kk in 1:length(moore)
            ins, y = CorePotts.shift(lat, x, moore.offsets[kk])
            ins || continue
            s = CorePotts.linear_index(lat, y)
            σ[t] == σ[s] && continue
            touching === nothing || σ[t] in touching || σ[s] in touching || continue
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end

# the state after `prop`, as the self-check helpers apply a copy
function p65a_apply(prob, u, prop)
    a = deepcopy(u)
    a.σ[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, p65a_ctx(prob))
    return a
end
p65a_kills(u, prop) = prop.old != 0 && p65a_vol(u)[prop.old] == 1

# the cells a copy's sweep functions claim or read beyond old/new (nonzero)
function p65a_claimed(prob, u, prop)
    ctx = p65a_ctx(prob)
    r = Int[Int(c) for c in prob.f.reads(u, prob.p, prop, ctx)]
    w = Int[Int(c) for c in prob.f.claims(u, prob.p, prop, ctx)]
    return Set(filter(>(0), vcat(r, w)))
end
p65a_prop(prob, u, old, new) = first(filter(p -> p.old == old && p.new == new, p65a_props(prob, u)))

p65a_welch(x, y) = (mean(x) - mean(y)) / sqrt(var(x) / length(x) + var(y) / length(y))

# ---------------------------------------------------------------------------------------
# Fixtures

# F1. Cluster fixture (sections 1, 2, 5). Kinds: medium 0, cytoplasm 1, nucleus 2,
# lamellipodium 3. References appear only in updates and observables, never in the sweep.
p65a_define(:P65aClusters, quote
    @potts_model P65aClusters begin
        @kinds medium cytoplasm nucleus lamellipodium
        @parameters begin
            λ = 4.0
            V₀[kind] = [0.0, 32.0, 4.0, 1.0]
            T = 1.0
        end
        @variables begin
            q(cell) = 5.0
            nuc(cell)::CellRef
            w(cell) = 0.0
        end
        @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells => λ * (volume - V₀[kind])^2
            contacts => ifelse(cluster[owner] == cluster[owner′], 0.5, 1.0)
        end
        @after_mcs begin
            nuc ~ sibling(nucleus)
            w ~ q[sibling(nucleus)] + volume[sibling(lamellipodium)] + count(true for m in members(cluster))
        end
        @observed begin
            sn(cell) ~ q[sibling(nucleus)]
            sl(cell) ~ volume[sibling(lamellipodium)]
            al(cell) ~ ifelse(alive(sibling(lamellipodium)), 1.0, 0.0)
            isself(cell) ~ ifelse(sibling(cytoplasm) == id, 1.0, 0.0)
            rk(cell) ~ kind[root(cluster)]
            rq(cell) ~ q[root(cluster)]
            mv(cell) ~ sum(volume[m] for m in members(cluster))
            mn(cell) ~ count(true for m in members(cluster, nucleus))
            nq(cell) ~ q[nuc]
            tot ~ sum(volume[sibling(c, nucleus)] for c in cells(cytoplasm))
            tot2 ~ sum(q[sibling(c, lamellipodium)] for c in cells(cytoplasm))
            bth(cell) ~ birth
        end
        @sweep Metropolis(; temperature = T)
    end
end)

# cluster A: cytoplasm 1 (root, 6×6 minus the nucleus), nucleus 2 (2×2 inside), one-site
# lamellipodium 3 below it; cluster B: one-site cytoplasm root 4, nucleus 5 (2×2) beside
# it, no lamellipodium; cell 6: a lone cytoplasm (its own cluster).
const P65A_CL_Q = [1.0, 2.0, 3.0, 4.0, 6.0, 7.0]
function p65a_cluster_problem(; tspan = (0, 3), seed = 1)
    σ = zeros(Int32, 24, 24)
    σ[3:8, 3:8] .= 1
    σ[5:6, 5:6] .= 2
    σ[9, 5] = 3
    σ[15, 4] = 4
    σ[15:16, 5:6] .= 5
    σ[15:18, 15:18] .= 6
    sys = p65a_system(:P65aClusters; sysname = :cl)
    return PottsProblem(sys, [ownership => σ,
            kind => [:cytoplasm, :nucleus, :lamellipodium, :cytoplasm, :nucleus, :cytoplasm],
            cluster => [1, 1, 1, 4, 4, 6], :q => P65A_CL_Q], tspan; seed, capacity = 8)
end

# independent oracles on a state (alive = volume > 0; kinds 1 cyto, 2 nucleus, 3 lamel)
const P65A_CL_DEFAULT_Q = 5.0
function p65a_sibling(u, c, k)
    v = p65a_vol(u); kd = p65a_col(u, :kind); cl = p65a_col(u, :cluster)
    ms = [m for m in eachindex(v) if v[m] > 0 && cl[m] == cl[c] && kd[m] == k]
    @assert length(ms) <= 1
    return isempty(ms) ? 0 : ms[1]
end
p65a_members(u, c) = (v = p65a_vol(u); cl = p65a_col(u, :cluster); [m for m in eachindex(v) if v[m] > 0 && cl[m] == cl[c]])
p65a_qat(u, r) = (r > 0 && p65a_vol(u)[r] > 0) ? p65a_col(u, :q)[r] : P65A_CL_DEFAULT_Q
p65a_volat(u, r) = r > 0 ? p65a_vol(u)[r] : 0
p65a_kindat(u, r) = (r > 0 && p65a_vol(u)[r] > 0) ? Int(p65a_col(u, :kind)[r]) : 0
function p65a_cluster_oracle(u, c)
    v = p65a_vol(u); cl = p65a_col(u, :cluster); kd = p65a_col(u, :kind)
    sn = p65a_qat(u, p65a_sibling(u, c, 2))
    sl = p65a_volat(u, p65a_sibling(u, c, 3))
    al = p65a_sibling(u, c, 3) > 0 ? 1.0 : 0.0
    isself = p65a_sibling(u, c, 1) == c ? 1.0 : 0.0
    r = Int(cl[c])
    rk = p65a_kindat(u, r)
    rq = p65a_qat(u, r)
    ms = p65a_members(u, c)
    mv = sum(v[m] for m in ms)
    mn = count(m -> kd[m] == 2, ms)
    return (; sn, sl, al, isself, rk, rq, mv, mn)
end
function p65a_cluster_tot(u)
    v = p65a_vol(u); kd = p65a_col(u, :kind)
    cyto = [c for c in eachindex(v) if v[c] > 0 && kd[c] == 1]
    return (sum(p65a_volat(u, p65a_sibling(u, c, 2)) for c in cyto),
        sum(p65a_qat(u, p65a_sibling(u, c, 3)) for c in cyto))
end

# F2. Energy fixture (sections 3, 5). Kinds: medium 0, cell 1, other 2. Every cell term
# reads its partner's static values; `q` defaults to 5.0.
const P65A_E = (λ = 1.0, V₀ = 6.0, ν = 0.7, μ = [0.0 0.0 0.0; 0.3 0.5 0.7; 0.2 0.4 0.9], qdef = 5.0)
p65a_define(:P65aEnergy, quote
    @potts_model P65aEnergy begin
        @kinds medium cell other
        @parameters begin
            λ = 1.0
            V₀ = 6.0
            ν = 0.7
            T = 10.0
            μ[kind, kind] = [0.0 0.0 0.0; 0.3 0.5 0.7; 0.2 0.4 0.9]
            J[kind, kind] = [0 8 8; 8 2 4; 8 4 2]
        end
        @variables begin
            partner(cell)::CellRef
            q(cell) = 5.0
        end
        @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells => λ * (volume - V₀ - q[partner])^2 + μ[kind, kind[partner]] * volume +
                     ifelse(alive(partner), ν, 0.0) * volume
            contacts => J[kind, kind′]
        end
        @observed pal(cell) ~ ifelse(alive(partner), 1.0, 0.0)
        @sweep Metropolis(; temperature = T)
    end
end)

# the same contacts, no cell terms and no references: its H is the contact energy (oracle)
@potts_model P65aEnergyContacts begin
    @kinds medium cell other
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 8 8; 8 2 4; 8 4 2]
    end
    @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @sweep Metropolis(; temperature = T)
end

# 1: cell 3×3, partner 2. 2: other 3×3, partner 3 (adjacent to 3: a gainer that reads the
# cell it kills). 3: cell, ONE site between 1 and 2, partner 1 (the dying cell reads a live
# referent). 4: other 3×3 far away, partner 3 (a third-party reader). 5: cell 2×2, no
# partner. 6: cell 2×2, partner itself.
const P65A_E_KINDS = [:cell, :other, :cell, :other, :cell, :cell]
const P65A_E_PARTNER = [2, 3, 1, 3, 0, 6]
const P65A_E_Q = [1.0, 2.0, 3.0, 4.0, 6.0, 0.5]
function p65a_energy_sigma()
    σ = zeros(Int32, 20, 20)
    σ[3:5, 3:5] .= 1
    σ[3:5, 7:9] .= 2
    σ[4, 6] = 3
    σ[14:16, 14:16] .= 4
    σ[14:15, 4:5] .= 5
    σ[9:10, 14:15] .= 6
    return σ
end
p65a_energy_problem(; tspan = (0, 4), seed = 1, partner = P65A_E_PARTNER, q = P65A_E_Q, T = Float64) =
    PottsProblem(p65a_system(:P65aEnergy; sysname = :en), [ownership => p65a_energy_sigma(), kind => P65A_E_KINDS,
            :partner => partner, :q => q], tspan; seed, T, capacity = 8)
# (alive cells relabelled 1:n, kinds kept: the contact energy depends only on site kinds)
function p65a_contact_energy(u)
    σ = Array(u.σ)
    kd = p65a_col(u, :kind)
    ids = sort!(filter(>(0), unique(σ)))
    relabel = Dict(c => Int32(i) for (i, c) in enumerate(ids))
    σ2 = map(c -> c == 0 ? Int32(0) : relabel[c], σ)
    return total_energy(PottsProblem(P65aEnergyContacts(; name = :ec),
        [ownership => σ2, kind => [kd[c] == 1 ? :cell : :other for c in ids]], (0, 1)))
end

# E_c with c's own volume `vc`, its referent read in state `r` (alive ⇔ volume > 0)
function p65a_Ec(u, c, vc, r)
    E = P65A_E
    kd = p65a_col(u, :kind); q = p65a_col(u, :q); pr = Int(p65a_col(u, :partner)[c])
    live = pr > 0 && p65a_vol(r)[pr] > 0
    kr = live ? Int(p65a_col(r, :kind)[pr]) : 0
    qr = live ? p65a_col(r, :q)[pr] : E.qdef
    return E.λ * (vc - E.V₀ - qr)^2 + E.μ[Int(kd[c]) + 1, kr + 1] * vc + (live ? E.ν : 0.0) * vc
end
p65a_cell_energy(u) = sum(p65a_Ec(u, c, p65a_vol(u)[c], u) for c in 1:6 if p65a_vol(u)[c] > 0; init = 0.0)
# the credit of section E: ΔH (referents read in u) − (H(a) − H(u))
function p65a_credit(u, a, prop)
    o, n = Int(prop.old), Int(prop.new)
    va, vu = p65a_vol(a), p65a_vol(u)
    local_after = sum((p65a_Ec(u, c, va[c], u) for c in (o, n) if c != 0); init = 0.0)
    after = sum((p65a_Ec(a, c, va[c], a) for c in 1:6 if va[c] > 0); init = 0.0)
    others = sum((p65a_Ec(u, c, vu[c], u) for c in 1:6 if vu[c] > 0 && !(c in (o, n))); init = 0.0)
    return local_after - after + others
end
function p65a_gap(prob, u, prop; credit = :potts)
    a = p65a_apply(prob, u, prop)
    c = credit === :potts ? Potts._killing_credit(prob, u, prop, a) : credit === :oracle ? p65a_credit(u, a, prop) : 0.0
    return energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u)) - c
end

# a reference-reading energy that reads what a copy changes (refused, section D)
const P65A_BAD = quote
    @potts_model P65aBadEnergy begin
        @kinds medium cell
        @variables begin
            partner(cell)::CellRef
        end
        @lattice Lattice((12, 12))
        @energy cells => (volume - volume[partner])^2
        @sweep Metropolis(; temperature = 2.0)
    end
end
p65a_define(:P65aBadEnergy, P65A_BAD)

# F3. Lifecycle fixture (section 4). Kinds: medium 0, blob 1, doomed 2. Blob 1 (6×6) and
# blob 2 (6×6) divide at mcs == 20; the one-site doomed cell 3 (λd·volume², E(1) = 50) is
# eaten by the medium within a few MCS (each MCS it survives with probability ≈ e⁻¹, and
# growing costs +150 at T = 10). partner = [2, 3, 1]: cell 2 references the doomed cell,
# whose slot (the lowest free one) a daughter reuses at the event. `tq` is set by the
# division rule from the parent's referent; `tag` (copied) tells the daughters' parents.
p65a_define(:P65aLife, quote
    @potts_model P65aLife begin
        @kinds medium blob doomed
        @parameters begin
            λ = 1.0
            V₀ = 36.0
            λd = 50.0
            T = 10.0
            J[kind, kind] = [0 16 16; 16 2 16; 16 16 2]
        end
        @variables begin
            partner(cell)::CellRef
            q(cell) = 5.0
            tag(cell) = 0.0
            tq(cell) = 0.0
        end
        @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells(blob) => λ * (volume - V₀)^2
            cells(doomed) => λd * volume^2
            contacts => J[kind, kind′]
        end
        @divide cells(blob) when = mcs == 20, along = (1.0, 0.0), tq => q[partner] + 1.0
        @observed begin
            bth(cell) ~ birth
            pbth(cell) ~ birth[partner]
            pk(cell) ~ kind[partner]
            pq(cell) ~ q[partner]
            pa(cell) ~ ifelse(alive(partner), 1.0, 0.0)
        end
        @sweep Metropolis(; temperature = T)
    end
end)

function p65a_life_problem(; tspan = (0, 30), seed = 1, T = Float64)
    σ = zeros(Int32, 40, 30)
    σ[8:13, 5:10] .= 1
    σ[8:13, 20:25] .= 2
    σ[30, 15] = 3
    sys = p65a_system(:P65aLife; sysname = :life)
    return PottsProblem(sys, [ownership => σ, kind => [:blob, :blob, :doomed], :partner => [2, 3, 1],
            :q => [1.0, 2.0, 3.0], :tag => [10.0, 20.0, 30.0]], tspan; seed, T, capacity = 8)
end

# the save index (into sol.u) of the division event: the first state with 4 alive cells
p65a_event(sol) = findfirst(u -> count(>(0), p65a_vol(u)) == 4, sol.u)

# the post-event checks shared by the CPU, checkpoint and device runs
function p65a_post_event_checks(prob, u)
    v = p65a_vol(u)
    @test count(>(0), v) == 4
    @test all(>(0), v[1:4])                                       # parents 1, 2; daughters 3 (reused), 4
    @test v[3] > 0                                                # fixture: the doomed cell's slot is reused
    tag = p65a_col(u, :tag)
    d1 = findfirst(c -> c in (3, 4) && tag[c] == 10.0, 1:4)        # daughter of blob 1
    d2 = findfirst(c -> c in (3, 4) && tag[c] == 20.0, 1:4)        # daughter of blob 2
    @test d1 !== nothing && d2 !== nothing
    (d1 === nothing || d2 === nothing) && return nothing
    bth = observe(prob, :bth, u)
    @test bth[1] == 1 && bth[2] == 2                             # parents keep their serials
    @test Set(bth[[3, 4]]) == Set([4, 5])                        # new serials, never 3 (the dead cell's, and slot 3's)
    @test eltype(u.cell.birth) == Int32
    pr = p65a_col(u, :partner)
    @test eltype(pr) <: Integer
    @test pr[2] == 0                                             # reset at the event, before slot 3 was reallocated
    @test pr[d2] == 0                                            # the daughter copied the reset reference
    @test pr[1] == 2 && pr[d1] == 2                              # a live reference survives and is copied
    @test observe(prob, :pa, u)[2] == 0.0
    @test observe(prob, :pbth, u)[2] == 0
    @test observe(prob, :pbth, u)[1] == 2
    @test observe(prob, :pq, u)[d1] == 2.0
    tq = p65a_col(u, :tq)
    @test tq[d1] == 3.0                                          # rule read q[partner] = q[2] = 2
    @test tq[d2] == 6.0                                          # rule read a dead/cleared referent: default 5
    return (; d1, d2)
end

# F4. Claim-widening fixture (sections 5, 6): see the protocol above.
p65a_define(:P65aPair, quote
    @potts_model P65aPair begin
        @kinds medium wall[frozen] cell
        @parameters begin
            λ = 1.0
            V₀ = 30.0
            κ = 6.0
            T = 24.0
            J[kind, kind] = [0 0 6; 0 0 6; 6 6 2]
        end
        @variables begin
            partner(cell)::CellRef
        end
        @lattice Lattice((16, 31); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells(cell) => λ * (volume - V₀)^2
            contacts => J[kind, kind′]
        end
        @drive copy => ifelse(kind[old] == cell, κ * (1 - 2 * (volume[old] - volume[partner[old]])), 0.0) +
                       ifelse(kind[new] == cell, κ * (1 + 2 * (volume[new] - volume[partner[new]])), 0.0)
        @sweep Metropolis(; temperature = T)
    end
end)

function p65a_pair_problem(; seed = 1, tspan = (0, 400), T = Float64)
    σ = zeros(Int32, 16, 31)
    σ[6:11, 5:9] .= 1
    σ[6:11, 23:27] .= 2
    σ[:, 16] .= 3
    sys = p65a_system(:P65aPair; sysname = :pair)
    return PottsProblem(sys, [ownership => σ, kind => [:cell, :cell, :wall], :partner => [2, 1, 0]], tspan;
        seed, T)
end

# the negative control: the same problem with the widening removed (no reads, no claims)
function p65a_unwidened(prob)
    f = prob.f
    g = CorePotts.CPMFunction(f.delta_H, f.commit!, f.constraint, CorePotts.no_claims, CorePotts.no_claims,
        f.temperature, f.bias, f.phases, f.lifecycle, f.acceptance, f.footprint, f.fingerprint, f.sys, f.track,
        f.connectivity)
    return remake(prob; f = g)
end

p65a_stat(sol, burn) = mean(u -> Float64(p65a_vol(u)[1] - p65a_vol(u)[2])^2, sol.u[(burn + 1):end])
function p65a_sample(alg, seeds; tspan = (0, 400), burn = 50, broken = false, kw...)
    return [begin
                prob = p65a_pair_problem(; seed, tspan, kw...)
                p65a_stat(solve(broken ? p65a_unwidened(prob) : prob, alg; saveat = 1), burn)
            end
            for seed in seeds]
end

# F5. A two-hop chain in a drive (section 5).
p65a_define(:P65aHop, quote
    @potts_model P65aHop begin
        @kinds medium cell
        @parameters begin
            λ = 1.0
            V₀ = 9.0
            κ = 0.01
            T = 4.0
        end
        @variables begin
            partner(cell)::CellRef
        end
        @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
        @energy cells => λ * (volume - V₀)^2
        @drive copy => κ * (volume[partner[partner[old]]] + volume[partner[partner[new]]])
        @sweep Metropolis(; temperature = T)
    end
end)

function p65a_hop_problem()
    σ = zeros(Int32, 20, 20)
    σ[3:5, 3:5] .= 1
    σ[3:5, 12:14] .= 2
    σ[12:14, 3:5] .= 3
    σ[12:14, 12:14] .= 4
    return PottsProblem(p65a_system(:P65aHop; sysname = :hop), [ownership => σ, kind => fill(:cell, 4),
            :partner => [2, 3, 4, 1]], (0, 3); seed = 1)
end

# ---------------------------------------------------------------------------------------
# 1. References and dereferencing: sibling, members, root, x[ref], alive (cluster fixture)

@testset "P6.5a: the fixtures build" begin
    for name in (:P65aClusters, :P65aEnergy, :P65aBadEnergy, :P65aLife, :P65aPair, :P65aHop)
        @test isdefined(@__MODULE__, name)                       # DEFECT CHECK: `CellRef`, `sibling`, … unknown today
    end
end

@testset "P6.5a: sibling, members, root and x[ref] read the cluster (hand values)" begin
    prob = p65a_cluster_problem()
    u = prob.u0
    @test p65a_vol(u)[1:6] == [32, 4, 1, 1, 4, 16]
    @test p65a_col(u, :cluster)[1:6] == [1, 1, 1, 4, 4, 6]
    # hand values (kinds: cytoplasm 1, nucleus 2, lamellipodium 3; q default 5.0)
    @test observe(prob, :sn, u)[1:6] == [2.0, 2.0, 2.0, 6.0, 6.0, 5.0]       # q[sibling(nucleus)]
    @test observe(prob, :sl, u)[1:6] == [1, 1, 1, 0, 0, 0]                    # volume[sibling(lamellipodium)]
    @test observe(prob, :al, u)[1:6] == [1.0, 1.0, 1.0, 0.0, 0.0, 0.0]        # alive(sibling(lamellipodium))
    @test observe(prob, :isself, u)[1:6] == [1.0, 0.0, 0.0, 1.0, 0.0, 1.0]    # sibling(cytoplasm) == id
    @test observe(prob, :rk, u)[1:6] == [1, 1, 1, 1, 1, 1]                    # kind[root(cluster)]
    @test observe(prob, :rq, u)[1:6] == [1.0, 1.0, 1.0, 4.0, 4.0, 7.0]        # q[root(cluster)]
    @test observe(prob, :mv, u)[1:6] == [37, 37, 37, 5, 5, 16]                # Σ volume over members(cluster)
    @test observe(prob, :mn, u)[1:6] == [1, 1, 1, 1, 1, 0]                    # count over members(cluster, nucleus)
    @test observe(prob, :tot, u) == 8                                         # Σ volume[sibling(c, nucleus)], cytoplasms
    @test observe(prob, :tot2, u) == 3.0 + 5.0 + 5.0                          # Σ q[sibling(c, lamellipodium)]
end

@testset "P6.5a: dead referents read as the medium (sibling, root, members)" begin
    prob = p65a_cluster_problem()
    u = prob.u0
    # kill the lamellipodium 3 (medium takes its only site) and, separately, the root 4
    a3 = p65a_apply(prob, u, p65a_prop(prob, u, 3, 0))
    a4 = p65a_apply(prob, u, p65a_prop(prob, u, 4, 0))
    @test p65a_vol(a3)[3] == 0 && p65a_vol(a4)[4] == 0
    @test p65a_col(a4, :cluster)[5] == 4                         # the dead root still names its cluster
    # hand values after the deaths
    @test observe(prob, :sl, a3)[1:2] == [0, 0]
    @test observe(prob, :al, a3)[1:2] == [0.0, 0.0]
    @test observe(prob, :mv, a3)[1:2] == [36, 36]
    @test observe(prob, :tot2, a3) == 15.0                       # every cytoplasm now reads the default q
    @test observe(prob, :rk, a4)[5] == 0                         # kind of a dead root: medium
    @test observe(prob, :rq, a4)[5] == 5.0                       # its q: the default
    @test observe(prob, :sn, a4)[5] == 6.0                       # sibling(nucleus) of the nucleus is itself
    @test observe(prob, :mv, a4)[5] == 4 && observe(prob, :mn, a4)[5] == 1
    @test observe(prob, :tot, a4) == 4                           # cytoplasm 4 is dead: only cluster A counts
    # every observable against the independent oracle, on all three states
    for s in (u, a3, a4)
        v = p65a_vol(s)
        for c in 1:6
            v[c] > 0 || continue
            o = p65a_cluster_oracle(s, c)
            for k in keys(o)
                @test observe(prob, k, s)[c] == o[k]
            end
        end
        tot, tot2 = p65a_cluster_tot(s)
        @test observe(prob, :tot, s) == tot
        @test observe(prob, :tot2, s) == tot2
    end
    # negative control: the oracle sees the deaths (the checks above are not vacuous)
    @test p65a_cluster_oracle(u, 1).al == 1.0 && p65a_cluster_oracle(a3, 1).al == 0.0
    @test p65a_cluster_oracle(u, 5).rk == 1 && p65a_cluster_oracle(a4, 5).rk == 0
end

# ---------------------------------------------------------------------------------------
# 2. Updates write and read references

@testset "P6.5a: updates write a reference and read through references ($(nameof(typeof(alg))))" for alg in
                                                                                                    (SequentialCPM(), CheckerboardCPM())
    prob = p65a_cluster_problem(; tspan = (0, 3))
    sol = solve(prob, alg; saveat = 1)
    @test Symbol(sol.retcode) === :Success
    @test eltype(p65a_col(sol.u[end], :nuc)) <: Integer
    n = 0
    for u in sol.u[2:end]                                        # after each MCS's updates
        v = p65a_vol(u); nuc = p65a_col(u, :nuc); w = p65a_col(u, :w)
        nq = observe(prob, :nq, u)
        for c in 1:6
            v[c] > 0 || continue
            s = p65a_sibling(u, c, 2)
            @test nuc[c] == s                                    # nuc ~ sibling(nucleus)
            @test w[c] ≈ p65a_qat(u, s) + p65a_volat(u, p65a_sibling(u, c, 3)) + length(p65a_members(u, c)) atol = 1e-12
            @test nq[c] == p65a_qat(u, s)                        # q[nuc]: a written reference read back
            n += 1
        end
    end
    @test n >= 12                                                # ≥ 4 alive cells in each of the 3 states
    # the written reference is a slot, not a copy of the value: cluster A's cells name 2
    u = sol.u[end]
    p65a_vol(u)[2] > 0 && @test p65a_col(u, :nuc)[1] == 2
    @test p65a_col(u, :nuc)[6] == 0                              # a lone cell has no nucleus
end

# ---------------------------------------------------------------------------------------
# 3. Energies: H, ΔH and the exact self-check credits

@testset "P6.5a: H dereferences in its own state (independent oracle)" begin
    prob = p65a_energy_problem()
    u = prob.u0
    @test p65a_vol(u)[1:6] == [9, 9, 1, 9, 4, 4]
    @test p65a_col(u, :partner)[1:6] == P65A_E_PARTNER
    @test total_energy(prob, u) ≈ p65a_cell_energy(u) + p65a_contact_energy(u) atol = 1e-9
    # kill cell 3 (by the medium): its readers 2 and 4 now read the medium
    a = p65a_apply(prob, u, p65a_prop(prob, u, 3, 0))
    @test p65a_vol(a)[3] == 0
    @test total_energy(prob, a) ≈ p65a_cell_energy(a) + p65a_contact_energy(a) atol = 1e-9   # DEFECT CHECK
    # a dead referent reads exactly as ref 0 …
    a0 = deepcopy(a)
    a0.cell.partner[2] = 0
    a0.cell.partner[4] = 0
    @test total_energy(prob, a0) ≈ total_energy(prob, a) atol = 1e-9
    # … and its own values are not read
    a99 = deepcopy(a)
    a99.cell.q[3] = 99.0
    @test total_energy(prob, a99) ≈ total_energy(prob, a) atol = 1e-9
    # negative control: while 3 is alive its q IS read (by 2 and 4)
    u99 = deepcopy(u)
    u99.cell.q[3] = 99.0
    @test abs(total_energy(prob, u99) - total_energy(prob, u)) > 100.0
end

@testset "P6.5a: ΔH equals the H difference plus the credits, for every copy" begin
    prob = p65a_energy_problem()
    u = prob.u0
    props = p65a_props(prob, u)
    kills = filter(p -> p65a_kills(u, p), props)
    # fixture: cell 3 is killed by the medium (third-party readers 2 and 4), by 1 (a gainer
    # that does not read it) and by 2 (a gainer that reads it)
    @test any(p -> p.new == 0, kills) && any(p -> p.new == 1, kills) && any(p -> p.new == 2, kills)
    @test length(props) > 150
    worst_potts = worst_oracle = 0.0
    for p in props
        g1 = p65a_gap(prob, u, p; credit = :potts)
        g2 = p65a_gap(prob, u, p; credit = :oracle)
        worst_potts = max(worst_potts, abs(g1)); worst_oracle = max(worst_oracle, abs(g2))
        p65a_kills(u, p) && (@test abs(g1) < 1e-9; @test abs(g2) < 1e-9)       # DEFECT CHECK
    end
    @test worst_potts < 1e-9                                     # the suite's self-check helper is exact
    @test worst_oracle < 1e-9                                    # and the credit is the oracle's
    # the killing credits are not zero: the readers' terms really change (sensitivity)
    for p in kills
        a = p65a_apply(prob, u, p)
        cr = p65a_credit(u, a, p)
        @test abs(cr - p65a_Ec(u, 3, 0, u)) > 1.0                # beyond E_cell(3, empty state)
        @test Potts._killing_credit(prob, u, p, a) ≈ cr atol = 1e-9         # DEFECT CHECK
    end
    # ΔH reads the referent in the pre-copy state: the gainer 2 that kills its referent 3
    # pays its own term with 3 still alive (independent oracle of the local ΔH)
    p = first(filter(p -> p.new == 2, kills))
    a = p65a_apply(prob, u, p)
    local2 = p65a_Ec(u, 2, p65a_vol(a)[2], u) - p65a_Ec(u, 2, p65a_vol(u)[2], u)
    local3 = p65a_Ec(u, 3, 0, u) - p65a_Ec(u, 3, 1, u)
    dc = p65a_contact_energy(a) - p65a_contact_energy(u)
    @test energy_change(prob, u, p) ≈ local2 + local3 + dc atol = 1e-9
    # negative controls: without the reader credit the check fails by more than 1
    pm = first(filter(p -> p.new == 0, kills))
    am = p65a_apply(prob, u, pm)
    plain = energy_change(prob, u, pm) - (total_energy(prob, am) - total_energy(prob, u))
    vac = P65A_E.λ * (0 - P65A_E.V₀ - P65A_E_Q[1])^2           # E_cell(3, empty), partner 1 alive: μ[cell, cell]·0 + 0
    @test abs(plain - vac) > 1.0                                 # the cell credit alone is not enough
end

@testset "P6.5a: the self-check stays exact along runs ($(nameof(typeof(alg))))" for alg in
                                                                                      (SequentialCPM(), CheckerboardCPM())
    prob = p65a_energy_problem(; tspan = (0, 4))
    sol = solve(prob, alg; saveat = 1)
    @test Symbol(sol.retcode) === :Success
    worst = 0.0
    n = 0
    for u in sol.u, p in p65a_props(prob, u)
        worst = max(worst, abs(p65a_gap(prob, u, p; credit = :potts)))
        n += 1
    end
    @test n > 500
    @test worst < 1e-9
    @test all(u -> isapprox(total_energy(prob, u), p65a_cell_energy(u) + p65a_contact_energy(u); atol = 1e-8), sol.u)
end

@testset "P6.5a: an energy may not read what a copy changes through a reference (D-209)" begin
    e = try
        mtkcompile(p65a_system(:P65aBadEnergy))
        nothing
    catch err
        err
    end
    @test e isa ArgumentError
    msg = e === nothing ? "" : sprint(showerror, e)
    @test occursin("a copy changes", msg)
    @test occursin("in @energy cells", msg)
    # the static reads of the energy fixture compile (control)
    @test mtkcompile(p65a_system(:P65aEnergy)) isa CompiledPottsSystem
end

# ---------------------------------------------------------------------------------------
# 4. Liveness, `birth` and the allocation boundary (lifecycle fixture)

@testset "P6.5a: birth serials, dead referents and the boundary reset ($(nameof(typeof(alg))))" for alg in
                                                                                                    (SequentialCPM(), CheckerboardCPM())
    prob = p65a_life_problem()
    u0 = prob.u0
    @test observe(prob, :bth, u0)[1:3] == [1, 2, 3]
    @test observe(prob, :pbth, u0)[1:3] == [2, 3, 1]
    @test observe(prob, :pa, u0)[1:3] == [1.0, 1.0, 1.0]
    @test observe(prob, :pq, u0)[1:3] == [2.0, 3.0, 1.0]
    sol = solve(prob, alg; saveat = 1)
    @test Symbol(sol.retcode) === :Success
    vols3 = [p65a_vol(u)[3] for u in sol.u]
    i = findfirst(==(0), vols3)
    e = p65a_event(sol)
    @test i !== nothing && e !== nothing
    if i !== nothing && e !== nothing
        @test i < e - 2                                          # fixture: the doomed cell dies well before the event
        @test 20 <= sol.t[e] <= 21                               # the event is the mcs == 20 division
        # between the death and the event: cell 2's referent is dead and reads as the medium
        for u in sol.u[i:(e - 1)]
            @test observe(prob, :pa, u)[2] == 0.0
            @test observe(prob, :pk, u)[2] == 0
            @test observe(prob, :pq, u)[2] == 5.0                # the default, not q[3] = 3.0
            @test observe(prob, :pbth, u)[2] == 0
            @test observe(prob, :pa, u)[1] == 1.0                # (1's referent, 2, is alive)
            @test observe(prob, :bth, u)[1:2] == [1, 2]
        end
        # after the event
        for u in sol.u[e:end]
            p65a_post_event_checks(prob, u)
        end
        # negative control: a stale reference (never reset) would alias the daughter in slot 3
        u = sol.u[end]
        stale = deepcopy(u)
        stale.cell.partner[2] = 3
        @test observe(prob, :pa, stale)[2] == 1.0                # alive: the checks above would fail
        @test observe(prob, :pbth, stale)[2] in (4, 5)
        # and `birth ≡ slot` would give the reused slot's number 3
        @test 3 ∉ observe(prob, :bth, u)[1:4]
    end
end

@testset "P6.5a: next_birth survives a checkpoint" begin
    prob = p65a_life_problem()
    alg = SequentialCPM()
    full = solve(prob, alg)
    integ = init(prob, alg)
    for _ in 1:15
        step!(integ)
    end
    ck = checkpoint(integ)
    @test p65a_vol(ck.state)[3] == 0                             # fixture: the max-birth cell (3) died before
    path = joinpath(mktempdir(), "p65a.jls")
    save_checkpoint(path, ck)
    rest = solve!(init(prob, alg; checkpoint = load_checkpoint(path)))
    u = rest.u[end]
    @test Array(u.σ) == Array(full.u[end].σ)
    @test observe(prob, :bth, u) == observe(prob, :bth, full.u[end])
    @test p65a_col(u, :partner) == p65a_col(full.u[end], :partner)
    p65a_post_event_checks(prob, u)                              # serials 4, 5: not max(alive) + 1 = 3
end

@testset "P6.5a: birth ≡ slot without a lifecycle; alive ⇔ volume > 0" begin
    cl = p65a_cluster_problem()
    @test observe(cl, :bth, cl.u0)[1:6] == 1:6
    prob = p65a_energy_problem()
    u = prob.u0
    @test observe(prob, :partner, u)[1:6] == P65A_E_PARTNER        # the reference column, read by name
    @test eltype(p65a_col(u, :partner)) <: Integer
    a = p65a_apply(prob, u, p65a_prop(prob, u, 3, 0))
    for s in (u, a)
        v = p65a_vol(s)
        pr = p65a_col(s, :partner)
        want = [Float64(pr[c] > 0 && v[pr[c]] > 0) for c in 1:6]
        @test observe(prob, :pal, s)[1:6] == want
    end
    @test observe(prob, :pal, u)[[2, 4]] == [1.0, 1.0] && observe(prob, :pal, a)[[2, 4]] == [0.0, 0.0]
    @test observe(prob, :pal, u)[5] == 0.0                       # ref 0 is not alive
end

# ---------------------------------------------------------------------------------------
# 5. Claim sets

@testset "P6.5a: references widen the claim set (drive, energy, two hops)" begin
    # drive reading volume[partner[old]], volume[partner[new]]
    prob = p65a_pair_problem()
    u = prob.u0
    @test 2 in p65a_claimed(prob, u, p65a_prop(prob, u, 1, 0))  # old = 1 reads its partner 2
    @test 1 in p65a_claimed(prob, u, p65a_prop(prob, u, 0, 1))  # new = 1 … (medium old)
    @test 1 in p65a_claimed(prob, u, p65a_prop(prob, u, 2, 0))
    @test 2 in p65a_claimed(prob, u, p65a_prop(prob, u, 0, 2))
    # energy reading q[partner], kind[partner], alive(partner)
    pe = p65a_energy_problem()
    ue = pe.u0
    @test 3 in p65a_claimed(pe, ue, p65a_prop(pe, ue, 2, 0))    # partner[2] = 3
    @test 3 in p65a_claimed(pe, ue, p65a_prop(pe, ue, 0, 4))    # partner[4] = 3
    @test 2 in p65a_claimed(pe, ue, p65a_prop(pe, ue, 1, 0))    # partner[1] = 2
    # a chain: partner[partner[old]] claims both hops
    ph = p65a_hop_problem()
    uh = ph.u0
    @test issubset(Set([2, 3]), p65a_claimed(ph, uh, p65a_prop(ph, uh, 1, 0)))
    @test issubset(Set([4, 1]), p65a_claimed(ph, uh, p65a_prop(ph, uh, 0, 3)))
    @test all(alg -> Symbol(solve(ph, alg).retcode) === :Success, (SequentialCPM(), CheckerboardCPM()))
end

@testset "P6.5a: no widening when the sweep reads no reference (zero cost when off)" begin
    prob = p65a_cluster_problem()
    u = prob.u0
    @test !CorePotts.has_reads(prob.f)
    for p in p65a_props(prob, u; touching = (1, 2, 3, 4, 5))
        @test isempty(collect(prob.f.claims(u, prob.p, p, p65a_ctx(prob))))
    end
end

# ---------------------------------------------------------------------------------------
# 6. CheckerboardCPM against SequentialCPM, statistically (D-065 Q7; protocol in the header)

@testset "P6.5a: the checkerboard agrees with the sequential reference (light tier)" begin
    seq = p65a_sample(SequentialCPM(), 1:32)
    cb = p65a_sample(CheckerboardCPM(), 1:32)
    broken = p65a_sample(CheckerboardCPM(), 1:32; broken = true)
    null = p65a_sample(SequentialCPM(), 33:64)
    t_cb, t_broken, t_null = p65a_welch(cb, seq), p65a_welch(broken, seq), p65a_welch(null, seq)
    @info "P6.5a checkerboard vs sequential" mean_seq = mean(seq) mean_cb = mean(cb) mean_broken = mean(broken) t_cb t_broken t_null
    @test abs(t_null) <= 3.89                                    # the test's null holds
    @test abs(t_cb) <= 3.89                                      # agreement
    @test abs(t_broken) > 3.89                                   # negative control: a broken widening is detected
end

@testset "P6.5a: the checkerboard agrees with the sequential reference (FULL tier)" begin
    if P65A_FULL
        kw = (; tspan = (0, 1000), burn = 100)
        seq = p65a_sample(SequentialCPM(), 1001:1200; kw...)
        cb = p65a_sample(CheckerboardCPM(), 1001:1200; kw...)
        broken = p65a_sample(CheckerboardCPM(), 1001:1200; broken = true, kw...)
        ci(x) = (d = (mean(x) - mean(seq)) / mean(seq);
                 h = 3.29 * sqrt(var(x) / length(x) + var(seq) / length(seq)) / mean(seq); (d - h, d + h))
        lo, hi = ci(cb)
        blo, bhi = ci(broken)
        @info "P6.5a FULL checkerboard vs sequential" ci_cb = (lo, hi) ci_broken = (blo, bhi)
        @test -0.06 <= lo && hi <= 0.06                          # equivalence within ±6 %
        @test blo > 0.06 || bhi < -0.06                          # negative control
    else
        @test_skip "FULL tier: set POTTS_FULL_REPRODUCTION=true (offline, on the PC)"
    end
end

# ---------------------------------------------------------------------------------------
# 7. Device

@testset "P6.5a: references on the device" begin
    if isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM(; proposal = Moore(1))
        # the statistical validation: device checkerboard (Float32) against the CPU reference
        seq = p65a_sample(SequentialCPM(), 1:32)
        dev = [p65a_stat(solve(p65a_pair_problem(; seed, T = Float32), alg; backend, saveat = 1), 50) for seed in 1:32]
        @info "P6.5a device checkerboard vs CPU sequential" mean_seq = mean(seq) mean_dev = mean(dev) t = p65a_welch(dev, seq)
        @test abs(p65a_welch(dev, seq)) <= 3.89
        # births and the boundary reset in a device lifecycle
        prob = p65a_life_problem(; T = Float32)
        sol = solve(prob, alg; backend, saveat = 1)
        @test Symbol(sol.retcode) === :Success
        e = p65a_event(sol)
        @test e !== nothing
        e === nothing || p65a_post_event_checks(prob, sol.u[end])
        # a reference-reading energy runs on the device and its H stays finite
        pe = p65a_energy_problem(; T = Float32)
        sole = solve(pe, alg; backend, saveat = 1)
        @test Symbol(sole.retcode) === :Success
        @test isfinite(total_energy(pe, sole.u[end]))
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
