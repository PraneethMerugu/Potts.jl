# R6 cell
# references and liveness per D-066.
# Decisions: D-066 (liveness, `birth`, references, boundaries, self-check credits), D-065 Q7
# (sequential is the reference; the checkerboard is validated statistically), D-036
# (clusters), D-075 / api-synthesis §2.6–2.7 (the reference vocabulary), D-209 (an energy
# may not read what a copy changes beyond ΔH), D-048 (oracles, negative controls).
#
# Scope: "R6: cell references (`sibling`, `members`, `root`, `partner`, `x[ref]`);
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
#    - `CellRef` is bound inside model bodies (a new `Potts.DSL` name; the implementer
#      documents it for guardrails_tests.jl's DSL docs check).
#    - Default 0 (no reference, the medium). The operating point sets it by slot:
#      `:partner => [2, 3, 1, 3, 0, 6]`. A cell may reference itself.
#    - Stored as the integer column `u.cell.partner` (`eltype <: Integer`), one entry per
#      slot.
#    - Daughters copy reference variables like every other cell variable (D-066 item 5).
#    - An update may write one: `@after_mcs nuc ~ sibling(nucleus)`.
#    - A reference compares with `==` against `id`, another reference or 0.
# B. Reference sources (api-synthesis §2.7; cell scope = updates, rules, `@observed`):
#    - `sibling(k)`: the alive member of kind `k` of the current cell's cluster (the cell
#      itself when it is of kind `k`), or 0 when the cluster has none. `sibling(c, k)` is
#      the same for cell `c` (inside population folds such as `for c in cells(cytoplasm)`).
#    - `root(cluster)`: the cluster's root (`cluster[c]`, D-036) as a reference; a lone cell
#      is its own root. A copy-killed root (still naming its cluster, D-066 item 4) reads as
#      a dead referent.
#    - `members(cluster)`, `members(cluster, k)`: a fold domain over the ALIVE cells of the
#      cluster (of kind `k`), the cell itself included; the bound name is the generator's
#      (`m` below): `sum(volume[m] for m in members(cluster))`,
#      `count(true for m in members(cluster, nucleus))`.
#    - Not pinned here: `sibling`/`members`/`root` inside `@energy`/`@drive` (no consumer
#      needs them in the sweep: Fortuna reads them at boundaries only, 14 sketch §4 item
#      11); `sibling(k)` when a cluster has several alive members of kind `k`; the value of
#      a raw reference to a dead cell (only its dereference is pinned).
# C. Dereferencing, `x[ref]`: `q[ref]` (a cell variable), `kind[ref]`, `volume[ref]`,
#    `birth[ref]`, `alive(ref)`, and chains (`partner[partner[old]]`). A DEAD referent
#    (volume 0), and ref 0, read as the medium: kind 0, volume 0, `birth` 0, `alive` false,
#    and every cell variable at its declared DEFAULT (here `q(cell) = 5.0`, so the default
#    is distinguishable from 0) (D-066 item 5). In copy scope (`@drive`, `@constraint`)
#    `volume[partner[old]]` reads the referent's current volume.
# D. Energies (cell terms). A cell term may read through a reference only what no copy
#    changes: cell variables no `@on_copy` writes, `kind`, `birth`, `alive(ref)`, e.g.
#    `λ * (volume - V₀ - q[partner])^2 + μ[kind, kind[partner]] * volume`. Reading a
#    copy-varying quantity of a referent in an energy (`volume[partner]`) is refused at
#    `mtkcompile` with a `PottsCompileError` (its message contains "a copy changes" and
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
#            total_energy(prob, a) − total_energy(prob, u) + Potts._killing_credit(prob, u,
#                prop, a)
#
#    for EVERY copy (|gap| < 1e-9), where `a` is the state after the copy and the credit is
#      E_cell(o, empty state)                      (as today, `killing_copy_energy_tests.jl`
#                                                  / D-083)
#      + Σ_{c alive in a, c ≠ o} [ E_c(c's values in a; referents read in u) − E_c(a) ].
#    For a copy that kills nobody the second sum is 0. The credit is checked against an
#    independent oracle (the test's own E_c), and `total_energy` against the same oracle.
# F. Liveness and `birth` (D-066 items 1, 3).
#    - `alive(ref)` ≡ `volume[ref] > 0` (a read-only built-in).
#    - `birth`: a read-only cell-scope built-in, a monotone serial never reused. Initial
#      cells get 1:n. Each division daughter in a NEW slot gets the next serial
#      (`next_birth`, a counter stored in the state and checkpointed, not max+1); the parent
#      keeps its slot and its `birth`. `birth` is not copied to daughters. With slot reuse
#      (lowest-first, D-066 item 3) a daughter in a dead cell's slot gets a new serial,
#      never the dead cell's nor its slot number. In a model with a lifecycle the serial is
#      the column `u.cell.birth::Vector{Int32}`; in a model without births `birth ≡ slot`
#      (D-066 item 3). `observe(prob, :bth, u)` with `@observed bth(cell) ~ birth` reads it
#      per slot.
#    - Not pinned here (D-066 item 3's output mapping): SII `id`, `cluster` as
#      `birth[root]`, plots, `write_piff(…; ids = birth)`, `with_capacity`; a daughter that
#      receives no site.
# G. Boundaries (D-066 item 5 (a)). In the lifecycle plan of an event MCS, BEFORE any id is
#    allocated, every reference to a dead cell is reset to 0, so a reference never aliases
#    the new cell that reuses the slot (and a daughter copies the reset value). On quiet MCS
#    the stored value is not pinned, only its dereference (C). (b), R8's routine, is
#    `convert_tests.jl`.
# H. Checkerboard (D-065 Q7). CheckerboardCPM is validated STATISTICALLY against
#    SequentialCPM, with the pre-registered protocol of section 6. The lockless checkerboard
#    claims nothing (D-271), so the claim-set tests of section 5 and the negative control
#    with `reads`/`claims` stripped are removed; section 5 keeps a two-hop chain run.
#
# =========================================================================================
# Statistical protocol (section 6), pre-registered
# =========================================================================================
# Fixture ReferencePair: two cells of kind `cell` (V₀ = 30, λ = 1, J_cell,medium = 6,
# J_cell,cell = 2) on a closed 16×31 lattice, separated by a frozen wall column (column 16),
# so they never touch; `partner = [2, 1, 0]`. A drive couples their volumes:
#     κ(1 − 2(V_old − V_partner[old])) [old a cell] + κ(1 + 2(V_new − V_partner[new])) [new
#     a cell]
# which is the exact ΔU of U = κ(V₁ − V₂)² for copies that change one of the two cells, so
# SequentialCPM samples exp(−(H + U)/T). κ = 6, T = 24. A checkerboard copy of cell 1 whose
# drive reads V₂ while a copy of cell 2 commits in the same colour sees a stale V₂; the
# widening forbids that pair.
#  - Statistic S (one value per replicate): the mean of (V₁ − V₂)² over the saved states at
#    MCS t = 50, 51, …, 400 (`saveat = 1`, `tspan = (0, 400)`).
#  - Replicates: seeds 1:32 for every arm. Arms: SequentialCPM (reference), CheckerboardCPM
#    (candidate), and SequentialCPM with seeds 33:64 (the test's null).
#  - Test: Welch t = (x̄ − ȳ)/√(s²ₓ/32 + s²ᵧ/32), critical value 3.89 (two-sided α = 1e-4
#    under the normal reference, as `boundary_site_proposal_tests.jl` FULL; the t reference
#    at the Welch df ≈ 60 puts 1e-4 at ≈ 4.1, so 3.89 is slightly stricter for the agreement
#    test). Agreement:
#    |t(candidate, reference)| ≤ 3.89. Null: |t(seq 33:64, seq 1:32)| ≤ 3.89.
#  - Calibration on the base commit, with a stub in which the partner was `3 − id` and the
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
#    ±0.06 (calibrated on the claiming checkerboard: [−4.1 %, −0.8 %]). About 15 s.
#  - Device (POTTS_GPU set): CheckerboardCPM on the device (Float32) with seeds 1:32 against
#    the CPU SequentialCPM sample, |t| ≤ 3.89.
#
# Sections: 1 references and dereferencing (cluster fixture); 2 updates writing and reading
# references; 3 energies: H, ΔH and the exact self-check credits; 4 liveness, `birth`,
# boundaries (lifecycle fixture, checkpoint); 5 a two-hop chain under both algorithms; 6 the
# statistical validation; 7 device. Fixtures that use the new syntax are defined through
# `define`, so a build failure today fails the testsets that use them instead of aborting
# the file.

@testsetup module CellReferencesSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
using Statistics: mean, var
const REFERENCE_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" ||
    get(ENV, "REPRO", "") == "full"
# ---------------------------------------------------------------------------------------
# 0. Helpers
const DEFINE_ERRORS = Dict{Symbol, Any}()
function define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
function model(name::Symbol)
    if isdefined(@__MODULE__, name)
        return getfield(@__MODULE__, name)
    else
        error("cell references fixture $name did not \
            build: $(get(DEFINE_ERRORS, name, "unknown"))")
    end
end
system(name::Symbol; sysname = :m) = Base.invokelatest(model(name); name = sysname)
vol(u) = Array(u.cell.volume)
col(u, n) = Array(getfield(u.cell, n))
ctx(prob) = Potts._host_ctx(prob)
# every Moore(1) copy (target t takes source s's owner); `touching` restricts to copies
# whose old or new owner is in the set
function reference_props(prob, u; touching = nothing)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    σ = Array(u.ownership)
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
function apply(prob, u, prop)
    a = deepcopy(u)
    a.ownership[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, ctx(prob))
    return a
end
reference_kills(u, prop) = prop.old != 0 && vol(u)[prop.old] == 1
function reference_prop(
        prob, u, old,
        new
    )
    return first(filter(p -> p.old == old && p.new == new, reference_props(prob, u)))
end
welch(x, y) = (mean(x) - mean(y)) / sqrt(var(x) / length(x) + var(y) / length(y))
# ---------------------------------------------------------------------------------------
# Fixtures

# F1. Cluster fixture (sections 1, 2, 5). Kinds: medium 0, cytoplasm 1, nucleus 2,
# lamellipodium 3. References appear only in updates and observables, never in the sweep.
define(
    :Clusters, quote
        @potts_model Clusters begin
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
                contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 0.5, 1.0)
            end
            @after_mcs begin
                nuc ~ sibling(nucleus)
                w ~
                    q[sibling(nucleus)] + volume[sibling(lamellipodium)] +
                    count(true for m in members(cluster))
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
    end
)
# cluster A: cytoplasm 1 (root, 6×6 minus the nucleus), nucleus 2 (2×2 inside), one-site
# lamellipodium 3 below it; cluster B: one-site cytoplasm root 4, nucleus 5 (2×2) beside
# it, no lamellipodium; cell 6: a lone cytoplasm (its own cluster).
const CL_Q = [1.0, 2.0, 3.0, 4.0, 6.0, 7.0]
function cluster_problem(; tspan = (0, 3), seed = 1)
    σ = zeros(Int32, 24, 24)
    σ[3:8, 3:8] .= 1
    σ[5:6, 5:6] .= 2
    σ[9, 5] = 3
    σ[15, 4] = 4
    σ[15:16, 5:6] .= 5
    σ[15:18, 15:18] .= 6
    sys = system(:Clusters; sysname = :cl)
    return PottsProblem(
        sys, [
            ownership => σ,
            kind =>
                [:cytoplasm, :nucleus, :lamellipodium, :cytoplasm, :nucleus, :cytoplasm],
            cluster => [1, 1, 1, 4, 4, 6], :q => CL_Q,
        ],
        tspan;
        seed,
        capacity = 8
    )
end
# independent oracles on a state (alive = volume > 0; kinds 1 cyto, 2 nucleus, 3 lamel)
const CL_DEFAULT_Q = 5.0
function reference_sibling(u, c, k)
    v = vol(u)
    kd = col(u, :kind)
    cl = col(u, :cluster)
    ms = [m for m in eachindex(v) if v[m] > 0 && cl[m] == cl[c] && kd[m] == k]
    @assert length(ms) <= 1
    return isempty(ms) ? 0 : ms[1]
end
function reference_members(u, c)
    v = vol(u)
    cl = col(u, :cluster)
    return [m for m in eachindex(v) if v[m] > 0 && cl[m] == cl[c]]
end
qat(u, r) = (r > 0 && vol(u)[r] > 0) ? col(u, :q)[r] : CL_DEFAULT_Q
volat(u, r) = r > 0 ? vol(u)[r] : 0
kindat(u, r) = (r > 0 && vol(u)[r] > 0) ? Int(col(u, :kind)[r]) : 0
function cluster_oracle(u, c)
    v = vol(u)
    cl = col(u, :cluster)
    kd = col(u, :kind)
    sn = qat(u, reference_sibling(u, c, 2))
    sl = volat(u, reference_sibling(u, c, 3))
    al = reference_sibling(u, c, 3) > 0 ? 1.0 : 0.0
    isself = reference_sibling(u, c, 1) == c ? 1.0 : 0.0
    r = Int(cl[c])
    rk = kindat(u, r)
    rq = qat(u, r)
    ms = reference_members(u, c)
    mv = sum(v[m] for m in ms)
    mn = count(m -> kd[m] == 2, ms)
    return (; sn, sl, al, isself, rk, rq, mv, mn)
end
function cluster_tot(u)
    v = vol(u)
    kd = col(u, :kind)
    cyto = [c for c in eachindex(v) if v[c] > 0 && kd[c] == 1]
    return (
        sum(volat(u, reference_sibling(u, c, 2)) for c in cyto),
        sum(qat(u, reference_sibling(u, c, 3)) for c in cyto),
    )
end
# F2. Energy fixture (sections 3, 5). Kinds: medium 0, cell 1, other 2. Every cell term
# reads its partner's static values; `q` defaults to 5.0.
const REFERENCE_E = (
    λ = 1.0, V₀ = 6.0, ν = 0.7, μ = [0.0 0.0 0.0; 0.3 0.5 0.7; 0.2 0.4 0.9], qdef = 5.0,
)
define(
    :Energy, quote
        @potts_model Energy begin
            @kinds medium cell other
            @parameters begin
                λ = 1.0
                V₀ = 6.0
                ν = 0.7
                T = 10.0
                μ[kind, kind] = [0.0 0.0 0.0; 0.3 0.5 0.7; 0.2 0.4 0.9],
                    [symmetric = false]
                J[kind, kind] = [0 8 8; 8 2 4; 8 4 2]
            end
            @variables begin
                partner(cell)::CellRef
                q(cell) = 5.0
            end
            @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
            @energy begin
                cells =>
                    λ * (volume - V₀ - q[partner])^2 + μ[kind, kind[partner]] * volume +
                    ifelse(alive(partner), ν, 0.0) * volume
                contacts => J[kind, neighbor_kind]
            end
            @observed pal(cell) ~ ifelse(alive(partner), 1.0, 0.0)
            @sweep Metropolis(; temperature = T)
        end
    end
)
# the same contacts, no cell terms and no references: its H is the contact energy (oracle)
@potts_model EnergyContacts begin
    @kinds medium cell other
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 8 8; 8 2 4; 8 4 2]
    end
    @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
    @energy contacts => J[kind, neighbor_kind]
    @sweep Metropolis(; temperature = T)
end
# 1: cell 3×3, partner 2. 2: other 3×3, partner 3 (adjacent to 3: a gainer that reads the
# cell it kills). 3: cell, ONE site between 1 and 2, partner 1 (the dying cell reads a live
# referent). 4: other 3×3 far away, partner 3 (a third-party reader). 5: cell 2×2, no
# partner. 6: cell 2×2, partner itself.
const E_KINDS = [:cell, :other, :cell, :other, :cell, :cell]
const E_PARTNER = [2, 3, 1, 3, 0, 6]
const E_Q = [1.0, 2.0, 3.0, 4.0, 6.0, 0.5]
function energy_sigma()
    σ = zeros(Int32, 20, 20)
    σ[3:5, 3:5] .= 1
    σ[3:5, 7:9] .= 2
    σ[4, 6] = 3
    σ[14:16, 14:16] .= 4
    σ[14:15, 4:5] .= 5
    σ[9:10, 14:15] .= 6
    return σ
end
function energy_problem(;
        tspan = (0, 4), seed = 1, partner = E_PARTNER, q = E_Q, T = Float64
    )
    return PottsProblem(
        system(:Energy; sysname = :en), [
            ownership => energy_sigma(), kind => E_KINDS,
            :partner => partner, :q => q,
        ],
        tspan; seed, T, capacity = 8
    )
end
# (alive cells relabelled 1:n, kinds kept: the contact energy depends only on site kinds)
function contact_energy(u)
    σ = Array(u.ownership)
    kd = col(u, :kind)
    ids = sort!(filter(>(0), unique(σ)))
    relabel = Dict(c => Int32(i) for (i, c) in enumerate(ids))
    σ2 = map(c -> c == 0 ? Int32(0) : relabel[c], σ)
    return total_energy(
        PottsProblem(
            EnergyContacts(; name = :ec),
            [ownership => σ2, kind => [kd[c] == 1 ? :cell : :other for c in ids]], (0, 1)
        )
    )
end
# E_c with c's own volume `vc`, its referent read in state `r` (alive ⇔ volume > 0)
function reference_Ec(u, c, vc, r)
    E = REFERENCE_E
    kd = col(u, :kind)
    q = col(u, :q)
    pr = Int(col(u, :partner)[c])
    live = pr > 0 && vol(r)[pr] > 0
    kr = live ? Int(col(r, :kind)[pr]) : 0
    qr = live ? col(r, :q)[pr] : E.qdef
    return E.λ * (vc - E.V₀ - qr)^2 + E.μ[Int(kd[c]) + 1, kr + 1] * vc +
        (live ? E.ν : 0.0) * vc
end
function cell_energy(u)
    return sum(
        reference_Ec(u, c, vol(u)[c], u) for c in 1:6 if vol(u)[c] > 0;
        init = 0.0
    )
end
# the credit of section E: ΔH (referents read in u) − (H(a) − H(u))
function reference_credit(u, a, prop)
    o, n = Int(prop.old), Int(prop.new)
    va, vu = vol(a), vol(u)
    local_after = sum((reference_Ec(u, c, va[c], u) for c in (o, n) if c != 0); init = 0.0)
    after = sum((reference_Ec(a, c, va[c], a) for c in 1:6 if va[c] > 0); init = 0.0)
    others = sum(
        (reference_Ec(u, c, vu[c], u) for c in 1:6 if vu[c] > 0 && !(c in (o, n)));
        init = 0.0
    )
    return local_after - after + others
end
function gap(prob, u, prop; credit = :potts)
    a = apply(prob, u, prop)
    c = if credit === :potts
        Potts._killing_credit(prob, u, prop, a)
    elseif credit === :oracle
        reference_credit(u, a, prop)
    else
        0.0
    end
    return energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u)) -
        c
end
# a reference-reading energy that reads what a copy changes (refused, section D)
const BAD = quote
    @potts_model BadEnergy begin
        @kinds medium cell
        @variables begin
            partner(cell)::CellRef
        end
        @lattice Lattice((12, 12))
        @energy cells => (volume - volume[partner])^2
        @sweep Metropolis(; temperature = 2.0)
    end
end
define(:BadEnergy, BAD)
# F3. Lifecycle fixture (section 4). Kinds: medium 0, blob 1, doomed 2. Blob 1 (6×6) and
# blob 2 (6×6) divide at mcs == 20; the one-site doomed cell 3 (λd·volume², E(1) = 50) is
# eaten by the medium within a few MCS (each MCS it survives with probability ≈ e⁻¹, and
# growing costs +150 at T = 10). partner = [2, 3, 1]: cell 2 references the doomed cell,
# whose slot (the lowest free one) a daughter reuses at the event. `tq` is set by the
# division rule from the parent's referent; `tag` (copied) tells the daughters' parents.
define(
    :Life, quote
        @potts_model Life begin
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
                contacts => J[kind, neighbor_kind]
            end
            @divide cells(blob) when = mcs == 20, along = (1.0, 0.0),
                tq => q[partner] + 1.0
            @observed begin
                bth(cell) ~ birth
                pbth(cell) ~ birth[partner]
                pk(cell) ~ kind[partner]
                pq(cell) ~ q[partner]
                pa(cell) ~ ifelse(alive(partner), 1.0, 0.0)
            end
            @sweep Metropolis(; temperature = T)
        end
    end
)
function life_problem(; tspan = (0, 30), seed = 1, T = Float64)
    σ = zeros(Int32, 40, 30)
    σ[8:13, 5:10] .= 1
    σ[8:13, 20:25] .= 2
    σ[30, 15] = 3
    sys = system(:Life; sysname = :life)
    return PottsProblem(
        sys, [
            ownership => σ, kind => [:blob, :blob, :doomed], :partner => [2, 3, 1],
            :q => [1.0, 2.0, 3.0], :tag => [10.0, 20.0, 30.0],
        ],
        tspan;
        seed,
        T,
        capacity = 8
    )
end
# the save index (into sol.u) of the division event: the first state with 4 alive cells
event(sol) = findfirst(u -> count(>(0), vol(u)) == 4, sol.u)
# the post-event checks shared by the CPU, checkpoint and device runs
function post_event_checks(prob, u)
    v = vol(u)
    @test count(>(0), v) == 4
    # parents 1, 2; daughters 3 (reused), 4
    @test all(>(0), v[1:4])
    # fixture: the doomed cell's slot is reused
    @test v[3] > 0
    tag = col(u, :tag)
    d1 = findfirst(c -> c in (3, 4) && tag[c] == 10.0, 1:4)        # daughter of blob 1
    d2 = findfirst(c -> c in (3, 4) && tag[c] == 20.0, 1:4)        # daughter of blob 2
    @test d1 !== nothing && d2 !== nothing
    (d1 === nothing || d2 === nothing) && return nothing
    bth = observe(prob, :bth, u)
    # parents keep their serials
    @test bth[1] == 1 && bth[2] == 2
    # new serials, never 3 (the dead cell's, and slot 3's)
    @test Set(bth[[3, 4]]) == Set([4, 5])
    @test eltype(u.cell.birth) == Int32
    pr = col(u, :partner)
    @test eltype(pr) <: Integer
    # reset at the event, before slot 3 was reallocated
    @test pr[2] == 0
    # the daughter copied the reset reference
    @test pr[d2] == 0
    # a live reference survives and is copied
    @test pr[1] == 2 && pr[d1] == 2
    @test observe(prob, :pa, u)[2] == 0.0
    @test observe(prob, :pbth, u)[2] == 0
    @test observe(prob, :pbth, u)[1] == 2
    @test observe(prob, :pq, u)[d1] == 2.0
    tq = col(u, :tq)
    # rule read q[partner] = q[2] = 2
    @test tq[d1] == 3.0
    # rule read a dead/cleared referent: default 5
    @test tq[d2] == 6.0
    return (; d1, d2)
end
# F4. Claim-widening fixture (sections 5, 6): see the protocol above.
define(
    :ReferencePair, quote
        @potts_model ReferencePair begin
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
                contacts => J[kind, neighbor_kind]
            end
            @drive copy =>
                ifelse(
                kind[old] == cell, κ *
                    (1 - 2 * (volume[old] - volume[partner[old]])), 0.0
            ) +
                ifelse(
                kind[new] == cell, κ *
                    (1 + 2 * (volume[new] - volume[partner[new]])), 0.0
            )
            @sweep Metropolis(; temperature = T)
        end
    end
)
function pair_problem(; seed = 1, tspan = (0, 400), T = Float64)
    σ = zeros(Int32, 16, 31)
    σ[6:11, 5:9] .= 1
    σ[6:11, 23:27] .= 2
    σ[:, 16] .= 3
    sys = system(:ReferencePair; sysname = :pair)
    return PottsProblem(
        sys, [ownership => σ, kind => [:cell, :cell, :wall], :partner => [2, 1, 0]], tspan;
        seed, T
    )
end
function reference_stat(sol, burn)
    return mean(
        u -> Float64(vol(u)[1] - vol(u)[2])^2,
        sol.u[(burn + 1):end]
    )
end
function sample(alg, seeds; tspan = (0, 400), burn = 50, kw...)
    return [
        reference_stat(solve(pair_problem(; seed, tspan, kw...), alg; saveat = 1), burn)
            for seed in seeds
    ]
end
# F5. A two-hop chain in a drive (section 5).
define(
    :Hop, quote
        @potts_model Hop begin
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
            @drive copy =>
                κ * (volume[partner[partner[old]]] + volume[partner[partner[new]]])
            @sweep Metropolis(; temperature = T)
        end
    end
)
function hop_problem()
    σ = zeros(Int32, 20, 20)
    σ[3:5, 3:5] .= 1
    σ[3:5, 12:14] .= 2
    σ[12:14, 3:5] .= 3
    σ[12:14, 12:14] .= 4
    return PottsProblem(
        system(:Hop; sysname = :hop), [
            ownership => σ, kind => fill(:cell, 4),
            :partner => [2, 3, 4, 1],
        ],
        (0, 3); seed = 1
    )
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "cell references: the fixtures build" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 1. References and dereferencing: sibling, members, root, x[ref], alive (cluster
    #    fixture)
    @testset "cell references: the fixtures build" begin
        for name in (:Clusters, :Energy, :BadEnergy, :Life, :ReferencePair, :Hop)
            # DEFECT CHECK: `CellRef`, `sibling`, … unknown today
            @test isdefined(@__MODULE__, name)
        end
    end
end

@testitem "cell references: sibling, members, root and x[ref] read the cluster (hand \
    values)" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: sibling, members, root and x[ref] read the cluster (hand \
        values)" begin
        prob = cluster_problem()
        u = prob.u0
        @test vol(u)[1:6] == [32, 4, 1, 1, 4, 16]
        @test col(u, :cluster)[1:6] == [1, 1, 1, 4, 4, 6]
        # hand values (kinds: cytoplasm 1, nucleus 2, lamellipodium 3; q default 5.0)
        # q[sibling(nucleus)]
        @test observe(prob, :sn, u)[1:6] == [2.0, 2.0, 2.0, 6.0, 6.0, 5.0]
        # volume[sibling(lamellipodium)]
        @test observe(prob, :sl, u)[1:6] == [1, 1, 1, 0, 0, 0]
        # alive(sibling(lamellipodium))
        @test observe(prob, :al, u)[1:6] == [1.0, 1.0, 1.0, 0.0, 0.0, 0.0]
        # sibling(cytoplasm) == id
        @test observe(prob, :isself, u)[1:6] == [1.0, 0.0, 0.0, 1.0, 0.0, 1.0]
        # kind[root(cluster)]
        @test observe(prob, :rk, u)[1:6] == [1, 1, 1, 1, 1, 1]
        # q[root(cluster)]
        @test observe(prob, :rq, u)[1:6] == [1.0, 1.0, 1.0, 4.0, 4.0, 7.0]
        # Σ volume over members(cluster)
        @test observe(prob, :mv, u)[1:6] == [37, 37, 37, 5, 5, 16]
        # count over members(cluster, nucleus)
        @test observe(prob, :mn, u)[1:6] == [1, 1, 1, 1, 1, 0]
        # Σ volume[sibling(c, nucleus)], cytoplasms
        @test observe(prob, :tot, u) == 8
        # Σ q[sibling(c, lamellipodium)]
        @test observe(prob, :tot2, u) == 3.0 + 5.0 + 5.0
    end
end

@testitem "cell references: dead referents read as the medium (sibling, root, \
    members)" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: dead referents read as the medium (sibling, root, \
        members)" begin
        prob = cluster_problem()
        u = prob.u0
        # kill the lamellipodium 3 (medium takes its only site) and, separately, the root 4
        a3 = apply(prob, u, reference_prop(prob, u, 3, 0))
        a4 = apply(prob, u, reference_prop(prob, u, 4, 0))
        @test vol(a3)[3] == 0 && vol(a4)[4] == 0
        # the dead root still names its cluster
        @test col(a4, :cluster)[5] == 4
        # hand values after the deaths
        @test observe(prob, :sl, a3)[1:2] == [0, 0]
        @test observe(prob, :al, a3)[1:2] == [0.0, 0.0]
        @test observe(prob, :mv, a3)[1:2] == [36, 36]
        # every cytoplasm now reads the default q
        @test observe(prob, :tot2, a3) == 15.0
        # kind of a dead root: medium
        @test observe(prob, :rk, a4)[5] == 0
        @test observe(prob, :rq, a4)[5] == 5.0                       # its q: the default
        # sibling(nucleus) of the nucleus is itself
        @test observe(prob, :sn, a4)[5] == 6.0
        @test observe(prob, :mv, a4)[5] == 4 && observe(prob, :mn, a4)[5] == 1
        # cytoplasm 4 is dead: only cluster A counts
        @test observe(prob, :tot, a4) == 4
        # every observable against the independent oracle, on all three states
        for s in (u, a3, a4)
            v = vol(s)
            for c in 1:6
                v[c] > 0 || continue
                o = cluster_oracle(s, c)
                for k in keys(o)
                    @test observe(prob, k, s)[c] == o[k]
                end
            end
            tot, tot2 = cluster_tot(s)
            @test observe(prob, :tot, s) == tot
            @test observe(prob, :tot2, s) == tot2
        end
        # negative control: the oracle sees the deaths (the checks above are not vacuous)
        @test cluster_oracle(u, 1).al == 1.0 && cluster_oracle(a3, 1).al == 0.0
        @test cluster_oracle(u, 5).rk == 1 && cluster_oracle(a4, 5).rk == 0
    end
end

@testitem "cell references: updates write a reference and read through references" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 2. Updates write and read references
    @testset "cell references: updates write a reference and read through references \
        ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        prob = cluster_problem(; tspan = (0, 3))
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        @test eltype(col(sol.u[end], :nuc)) <: Integer
        n = 0
        # after each MCS's updates
        for u in sol.u[2:end]
            v = vol(u)
            nuc = col(u, :nuc)
            w = col(u, :w)
            nq = observe(prob, :nq, u)
            for c in 1:6
                v[c] > 0 || continue
                s = reference_sibling(u, c, 2)
                # nuc ~ sibling(nucleus)
                @test nuc[c] == s
                @test w[c] ≈
                    qat(u, s) + volat(u, reference_sibling(u, c, 3)) +
                    length(reference_members(u, c)) atol = 1.0e-12
                # q[nuc]: a written reference read back
                @test nq[c] == qat(u, s)
                n += 1
            end
        end
        # ≥ 4 alive cells in each of the 3 states
        @test n >= 12
        # the written reference is a slot, not a copy of the value: cluster A's cells name 2
        u = sol.u[end]
        vol(u)[2] > 0 && @test col(u, :nuc)[1] == 2
        @test col(u, :nuc)[6] == 0                              # a lone cell has no nucleus
    end
end

@testitem "cell references: H dereferences in its own state (independent oracle)" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 3. Energies: H, ΔH and the exact self-check credits
    @testset "cell references: H dereferences in its own state (independent oracle)" begin
        prob = energy_problem()
        u = prob.u0
        @test vol(u)[1:6] == [9, 9, 1, 9, 4, 4]
        @test col(u, :partner)[1:6] == E_PARTNER
        @test total_energy(prob, u) ≈ cell_energy(u) + contact_energy(u) atol = 1.0e-9
        # kill cell 3 (by the medium): its readers 2 and 4 now read the medium
        a = apply(prob, u, reference_prop(prob, u, 3, 0))
        @test vol(a)[3] == 0
        # DEFECT CHECK
        @test total_energy(prob, a) ≈ cell_energy(a) + contact_energy(a) atol = 1.0e-9
        # a dead referent reads exactly as ref 0 …
        a0 = deepcopy(a)
        a0.cell.partner[2] = 0
        a0.cell.partner[4] = 0
        @test total_energy(prob, a0) ≈ total_energy(prob, a) atol = 1.0e-9
        # … and its own values are not read
        a99 = deepcopy(a)
        a99.cell.q[3] = 99.0
        @test total_energy(prob, a99) ≈ total_energy(prob, a) atol = 1.0e-9
        # negative control: while 3 is alive its q IS read (by 2 and 4)
        u99 = deepcopy(u)
        u99.cell.q[3] = 99.0
        @test abs(total_energy(prob, u99) - total_energy(prob, u)) > 100.0
    end
end

@testitem "cell references: ΔH equals the H difference plus the credits, for every \
    copy" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: ΔH equals the H difference plus the credits, for every \
        copy" begin
        prob = energy_problem()
        u = prob.u0
        props = reference_props(prob, u)
        kills = filter(p -> reference_kills(u, p), props)
        # fixture: cell 3 is killed by the medium (third-party readers 2 and 4), by 1 (a
        # gainer that does not read it) and by 2 (a gainer that reads it)
        @test any(p -> p.new == 0, kills) && any(p -> p.new == 1, kills) &&
            any(p -> p.new == 2, kills)
        @test length(props) > 150
        worst_potts = worst_oracle = 0.0
        for p in props
            g1 = gap(prob, u, p; credit = :potts)
            g2 = gap(prob, u, p; credit = :oracle)
            worst_potts = max(worst_potts, abs(g1))
            worst_oracle = max(worst_oracle, abs(g2))
            # DEFECT CHECK
            reference_kills(u, p) && (@test abs(g1) < 1.0e-9; @test abs(g2) < 1.0e-9)
        end
        # the suite's self-check helper is exact
        @test worst_potts < 1.0e-9
        # and the credit is the oracle's
        @test worst_oracle < 1.0e-9
        # the killing credits are not zero: the readers' terms really change (sensitivity)
        for p in kills
            a = apply(prob, u, p)
            cr = reference_credit(u, a, p)
            # beyond E_cell(3, empty state)
            @test abs(cr - reference_Ec(u, 3, 0, u)) > 1.0
            # DEFECT CHECK
            @test Potts._killing_credit(prob, u, p, a) ≈ cr atol = 1.0e-9
        end
        # ΔH reads the referent in the pre-copy state: the gainer 2 that kills its referent
        # 3 pays its own term with 3 still alive (independent oracle of the local ΔH)
        p = first(filter(p -> p.new == 2, kills))
        a = apply(prob, u, p)
        local2 = reference_Ec(u, 2, vol(a)[2], u) - reference_Ec(u, 2, vol(u)[2], u)
        local3 = reference_Ec(u, 3, 0, u) - reference_Ec(u, 3, 1, u)
        dc = contact_energy(a) - contact_energy(u)
        @test energy_change(prob, u, p) ≈ local2 + local3 + dc atol = 1.0e-9
        # negative controls: without the reader credit the check fails by more than 1
        pm = first(filter(p -> p.new == 0, kills))
        am = apply(prob, u, pm)
        plain = energy_change(prob, u, pm) -
            (total_energy(prob, am) - total_energy(prob, u))
        # E_cell(3, empty), partner 1 alive: μ[cell, cell]·0 + 0
        vac = REFERENCE_E.λ * (0 - REFERENCE_E.V₀ - E_Q[1])^2
        # the cell credit alone is not enough
        @test abs(plain - vac) > 1.0
    end
end

@testitem "cell references: the self-check stays exact along runs" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: the self-check stays exact along runs \
        ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        prob = energy_problem(; tspan = (0, 4))
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        worst = 0.0
        n = 0
        for u in sol.u, p in reference_props(prob, u)
            worst = max(worst, abs(gap(prob, u, p; credit = :potts)))
            n += 1
        end
        @test n > 500
        @test worst < 1.0e-9
        @test all(
            u -> isapprox(
                total_energy(prob, u), cell_energy(u) + contact_energy(u);
                atol = 1.0e-8
            ),
            sol.u
        )
    end
end

@testitem "cell references: an energy may not read what a copy changes through a \
    reference" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: an energy may not read what a copy changes through a \
        reference" begin
        @test_throws Potts.PottsCompileError mtkcompile(system(:BadEnergy))
        # the static reads of the energy fixture compile (control)
        @test mtkcompile(system(:Energy)) isa CompiledPottsSystem
    end
end

@testitem "cell references: birth serials, dead referents and the boundary reset" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 4. Liveness, `birth` and the allocation boundary (lifecycle fixture)
    @testset "cell references: birth serials, dead referents and the boundary reset \
        ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        prob = life_problem()
        u0 = prob.u0
        @test observe(prob, :bth, u0)[1:3] == [1, 2, 3]
        @test observe(prob, :pbth, u0)[1:3] == [2, 3, 1]
        @test observe(prob, :pa, u0)[1:3] == [1.0, 1.0, 1.0]
        @test observe(prob, :pq, u0)[1:3] == [2.0, 3.0, 1.0]
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        vols3 = [vol(u)[3] for u in sol.u]
        i = findfirst(==(0), vols3)
        e = event(sol)
        @test i !== nothing && e !== nothing
        if i !== nothing && e !== nothing
            # fixture: the doomed cell dies well before the event
            @test i < e - 2
            # the event is the mcs == 20 division
            @test 20 <= sol.t[e] <= 21
            # between the death and the event: cell 2's referent is dead and reads as the
            # medium
            for u in sol.u[i:(e - 1)]
                @test observe(prob, :pa, u)[2] == 0.0
                @test observe(prob, :pk, u)[2] == 0
                # the default, not q[3] = 3.0
                @test observe(prob, :pq, u)[2] == 5.0
                @test observe(prob, :pbth, u)[2] == 0
                # (1's referent, 2, is alive)
                @test observe(prob, :pa, u)[1] == 1.0
                @test observe(prob, :bth, u)[1:2] == [1, 2]
            end
            # after the event
            for u in sol.u[e:end]
                post_event_checks(prob, u)
            end
            # negative control: a stale reference (never reset) would alias the daughter in
            # slot 3
            u = sol.u[end]
            stale = deepcopy(u)
            stale.cell.partner[2] = 3
            # alive: the checks above would fail
            @test observe(prob, :pa, stale)[2] == 1.0
            @test observe(prob, :pbth, stale)[2] in (4, 5)
            # and `birth ≡ slot` would give the reused slot's number 3
            @test 3 ∉ observe(prob, :bth, u)[1:4]
        end
    end
end

@testitem "cell references: next_birth survives a checkpoint" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: next_birth survives a checkpoint" begin
        prob = life_problem()
        alg = SequentialCPM()
        full = solve(prob, alg)
        integ = init(prob, alg)
        for _ in 1:15
            step!(integ)
        end
        ck = checkpoint(integ)
        # fixture: the max-birth cell (3) died before
        @test vol(ck.state)[3] == 0
        path = joinpath(mktempdir(), "cell_refs.jls")
        save_checkpoint(path, ck)
        rest = solve!(init(prob, alg; checkpoint = load_checkpoint(path)))
        u = rest.u[end]
        @test Array(u.ownership) == Array(full.u[end].ownership)
        @test observe(prob, :bth, u) == observe(prob, :bth, full.u[end])
        @test col(u, :partner) == col(full.u[end], :partner)
        # serials 4, 5: not max(alive) + 1 = 3
        post_event_checks(prob, u)
    end
end

@testitem "cell references: birth ≡ slot without a lifecycle; alive ⇔ volume > 0" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: birth ≡ slot without a lifecycle; alive ⇔ volume > 0" begin
        cl = cluster_problem()
        @test observe(cl, :bth, cl.u0)[1:6] == 1:6
        prob = energy_problem()
        u = prob.u0
        # the reference column, read by name
        @test observe(prob, :partner, u)[1:6] == E_PARTNER
        @test eltype(col(u, :partner)) <: Integer
        a = apply(prob, u, reference_prop(prob, u, 3, 0))
        for s in (u, a)
            v = vol(s)
            pr = col(s, :partner)
            want = [Float64(pr[c] > 0 && v[pr[c]] > 0) for c in 1:6]
            @test observe(prob, :pal, s)[1:6] == want
        end
        @test observe(prob, :pal, u)[[2, 4]] == [1.0, 1.0] &&
            observe(prob, :pal, a)[[2, 4]] == [0.0, 0.0]
        @test observe(prob, :pal, u)[5] == 0.0                       # ref 0 is not alive
    end
end

@testitem "cell references: a reference chain runs under both algorithms" setup = [
    CellReferencesSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 5. A two-hop reference chain under both algorithms (the claim-set tests are removed,
    #    D-271)
    @testset "cell references: a reference chain runs under both algorithms" begin
        ph = hop_problem()
        @test all(
            alg -> Symbol(solve(ph, alg).retcode) === :Success, (
                SequentialCPM(), CheckerboardCPM(),
            )
        )
    end
end

@testitem "cell references: the checkerboard agrees with the sequential reference (light \
    tier)" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 6. CheckerboardCPM against SequentialCPM, statistically (D-065 Q7; protocol in the
    #    header)
    @testset "cell references: the checkerboard agrees with the sequential reference \
        (light tier)" begin
        seq = sample(SequentialCPM(), 1:32)
        cb = sample(CheckerboardCPM(), 1:32)
        null = sample(SequentialCPM(), 33:64)
        t_cb, t_null = welch(cb, seq), welch(null, seq)
        @info "cell references checkerboard vs sequential" mean_seq = mean(
            seq
        ) mean_cb = mean(cb) t_cb t_null
        @test abs(t_null) <= 3.89                                    # the test's null holds
        @test abs(t_cb) <= 3.89                                      # agreement
    end
end

@testitem "cell references: the checkerboard agrees with the sequential reference (FULL \
    tier)" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "cell references: the checkerboard agrees with the sequential reference \
        (FULL tier)" begin
        if REFERENCE_FULL
            kw = (; tspan = (0, 1000), burn = 100)
            seq = sample(SequentialCPM(), 1001:1200; kw...)
            cb = sample(CheckerboardCPM(), 1001:1200; kw...)
            function ci(x)
                d = (mean(x) - mean(seq)) / mean(seq)
                h = 3.29 * sqrt(var(x) / length(x) + var(seq) / length(seq)) / mean(seq)
                return (d - h, d + h)
            end
            lo, hi = ci(cb)
            @info "cell references FULL checkerboard vs sequential" ci_cb = (lo, hi)
            # equivalence within ±6 %
            @test -0.06 <= lo && hi <= 0.06
        else
            @test_skip "FULL tier: set POTTS_FULL_REPRODUCTION=true (offline, on the PC)"
        end
    end
end

@testitem "cell references: references on the device" setup = [CellReferencesSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 7. Device
    @testset "cell references: references on the device" begin
        if PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM(; proposal = Moore(1))
            # the statistical validation: device checkerboard (Float32) against the CPU
            # reference
            seq = sample(SequentialCPM(), 1:32)
            dev = [
                reference_stat(
                    solve(pair_problem(; seed, T = Float32), alg; backend, saveat = 1), 50
                )
                    for seed in 1:32
            ]
            @info "cell references device checkerboard vs CPU sequential" mean_seq = mean(
                seq
            ) mean_dev = mean(dev) t = welch(
                dev, seq
            )
            @test abs(welch(dev, seq)) <= 3.89
            # births and the boundary reset in a device lifecycle
            prob = life_problem(; T = Float32)
            sol = solve(prob, alg; backend, saveat = 1)
            @test Symbol(sol.retcode) === :Success
            e = event(sol)
            @test e !== nothing
            e === nothing || post_event_checks(prob, sol.u[end])
            # a reference-reading energy runs on the device and its H stays finite
            pe = energy_problem(; T = Float32)
            sole = solve(pe, alg; backend, saveat = 1)
            @test Symbol(sole.retcode) === :Success
            @test isfinite(total_energy(pe, sole.u[end]))
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end
