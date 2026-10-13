# P6.5b (ROADMAP Phase 6, step 5; second step of Fortuna, reproduction 14), part 1 of 2:
# `@convert`, site conversion as a per-MCS kernel pass. Frozen (AUTONOMY §7.3).
# Part 2, `p6_5b_ownership.jl`, holds the shared ownership-delta routine (priority), the
# ownership hooks (`clear_on_ownership_change`, no `@on_copy`) and A-17.
#
# Decisions: D-233 (the maintainer's and spec owner's scope for P6.5b, relayed by the
# coordinator 2026-10-13: independent per-site conversion with p evaluated at the START of
# the pass, counter-addressed draws, generated kernels, no host round trip per MCS; it
# supersedes api-synthesis §2.9's `order = Shuffled()` and per-candidate re-evaluation),
# D-075 (`@convert` block form, `Fresh`, `created`, named `@schedule` phase; D-035 as
# amended), D-145 (`@schedule` placement rule), D-066 (liveness, X2 "born on its first
# site", `birth`, references reset before allocation, item 5 (b)), D-089 (device lifecycle
# planner, lowest-first allocation), D-231 (P6.5a references), D-209, D-048 (oracles and
# negative controls), D-016 (fingerprint).
#
# ROADMAP: "R8: the shared ownership-delta routine (priority remove > convert > transition >
# divide > create); `@convert` (block form with `Fresh`, `created`, `budget`, each one a
# named `@schedule` phase costed per D-035 as amended by D-075); ownership hooks apply
# `clear_on_ownership_change`, and `@on_copy` never fires from the lifecycle (D-075 clarify).
# Fixes A-17."
#
# Fortuna (spec 14 §2.5, paper over code, 14a p.2806): after each MCS every cytoplasm site
# touching the substrate converts to lamellipodium INDEPENDENTLY with p = c·(1 − V₃/V₃ᵗ), V₃
# the lamellipodium's ACTUAL volume at the start of the pass, clamped at 0; c is unstated and
# is not pinned. The 14a code's sequential, shuffled, re-evaluated form is a recorded variant,
# not built. The fixtures below are synthetic (hand-checkable), not Fortuna's.
#
# =========================================================================================
# THE PUBLIC API THESE TESTS EXPECT (names, signatures, semantics)
# =========================================================================================
#
# A. The section. Inside `@potts_model`:
#
#        @convert name domain begin
#            from = <reference expression>                        # default: see below
#            to   = <reference expression>                        # `sibling(k)`, `… | Fresh(k)`
#            at   = <site condition>                              # default: all of from's sites
#            p    = <probability expression>                      # default 1; clamped to [0, 1]
#            transfer(x, from => to, per_site = <expr>)           # once per entity, × the count
#            x[to] += <expr>; m += <expr>                         # compound writes, per conversion
#        end
#
#    - `name` (a Symbol) names the pass. `domain` is `clusters(k…)` (one pass entity per
#      cluster whose root is of kind k, visited in root order) or `cells(k…)` (one per alive
#      cell of kind k, in slot order). Only `clusters(…)` is exercised here.
#    - New DSL names (the implementer adds them to `DSL_NAMES`/`DSL_KEYWORDS` in
#      guardrails.jl, and `@convert` to SECTIONS): `@convert`, `Fresh`, `created`, `transfer`
#      (`from`, `to`, `at`, `p`, `per_site` are keys of the block).
#    - `from`, `to` are cell references in the entity's scope (P6.5a: `sibling(k)`, …); the
#      entity's names (`cluster`, `id`, cell quantities of the entity) are bound.
#      DEFAULT `from` (ergonomics review E3): the entity's member of the declared domain kind,
#      i.e. `clusters(cytoplasm)` gives `from = sibling(cytoplasm)`.
#    - `at` is a site-scope condition (`site`, site variables, `kind`, `owner`, neighbour folds
#      such as `count(true for n in VonNeumann(1)(site) if kind[n] == substrate) > 0`, model-local
#      helper functions of `site`, with `from`, `to` bound). The CANDIDATES of an entity are
#      the sites OWNED BY `from` for which `at` holds: a site the condition selects but `from`
#      does not own is never converted (tested: the medium and the other cells on the masked
#      rows). DEFAULT `at`: true (all of `from`'s sites).
#    - ALLOCATION. `to = sibling(k)` and `to = sibling(k) | Fresh(k)` are equivalent: when the
#      referent is 0 (absent or dead) the pass allocates a new member of kind `k` for the
#      entity, ONLY IF at least one of its candidates converts (D-066 X2: born on its first
#      site; no conversion, no cell, no serial). One cell per entity per pass: every
#      conversion of that pass goes to it. (The coordinator's contract (b): "allocation for
#      clusters that have conversions but no target member"; the E3 block names no `Fresh`.)
# B. Semantics of one pass (D-233). For each entity:
#    - `p` is evaluated ONCE PER CANDIDATE ON THE START-OF-PASS STATE: every cell quantity
#      (volumes, cell variables, references) is the value before any conversion of this pass,
#      so conversions in one pass never change p within that pass. `p` may read site names
#      (14c's tanh bias reads the site), so it may differ between candidates.
#    - CLAMP (E3): p is clamped to [0, 1] by the runtime, so the paper's formula is written
#      verbatim (`p = c * (1 - volume[to] / V_target[to])`, negative past the target).
#    - Each candidate converts INDEPENDENTLY iff  u < clamp(p, 0, 1),  where
#          u = CorePotts.uniform(T, CorePotts.draw(key, mcs, site,
#                  CorePotts.stream_id("Potts.convert.<name>"))[1])
#      `key` the integrator's `RNGKey(seed, replica, repeat)`, `mcs` the phases' `mcs` (the
#      number of completed MCS, `t` during the step t → t + 1, D-188), `site` the linear index
#      into σ, `T` the problem's float type. u ∈ (0, 1): p ≤ 0 never converts, p ≥ 1 always.
#    - A converted site's owner becomes `to`; trackers (volume, surface, moments, cluster
#      volume, contact counts) stay exact (a full recount from σ agrees after every pass).
#    - `transfer(x, from => to, per_site = a)` (E3): after the decide step, ONCE per entity
#      with its conversion count n: x[from] -= a·n, x[to] += a·n (x a cell variable; nothing
#      when n = 0). So Σ x over the entity's `from` and `to` is conserved by a pass.
#    - Compound writes (`+=`, `-=`) of cell or model variables run once per conversion; their
#      sum over the pass is order-free. `created` is true for exactly one conversion of an
#      entity in the pass that allocated its `to` (the birthing conversion), false otherwise
#      (`births += created` adds 1 per creation).
#    - A created cell: the lowest free slot (as division daughters, D-066 item 3), its
#      generation + 1, the next `birth` serial, kind `k`, `cluster` = the entity's cluster
#      root (it joins the cluster), every cell variable at its DECLARED DEFAULT evaluated
#      for that slot's kind (E1, section G; nothing is copied from a dead predecessor in the
#      slot), then `transfer` and the writes.
#    - Before any allocation, references to dead cells are reset to 0 (D-066 item 5 (b),
#      P6.5a's `release`), so a reference never aliases the new cell.
#    - A cell emptied by copies dies (D-066); the next pass that converts for its entity
#      creates a new one.
#    - Draws are counter-addressed, so results do not depend on the thread count, the
#      algorithm (`SequentialCPM`/`CheckerboardCPM`) or the backend beyond the float type.
# C. Schedule (D-075, D-145). Each `@convert name` is a named phase: `@schedule` may list
#    `name` among the canonical phases (`@schedule sweep, protrusion, after_mcs`). An
#    unlisted `@convert` runs, in declaration order, right before `lifecycle` (its default
#    place in the canonical order: `before_mcs, sweep, after_mcs, fields, components,
#    operators, <converts>, lifecycle, end_mcs`), so the D-145 placement rule extends
#    unchanged. Errors (`ArgumentError` naming the offender, when the constructor runs or at
#    `mtkcompile`): an unknown schedule name, a `@convert` named like a canonical phase,
#    two `@convert`s with one name. The schedule and the pass are hashed (D-016): a different
#    `p` or placement gives a different fingerprint.
# D. `@extend` replacement. Redeclaring `@convert name …` in an extension REPLACES the
#    base's pass of that name as a whole (14c replaces 14a's `protrusion`): only the
#    extension's statements run.
# E. Cost (D-035 as amended by D-075, made stricter by D-233). The pass is generated
#    KernelAbstractions code, one implementation for CPU and device: a decide kernel
#    (counter-addressed draws, per-entity conversion counts with atomics), the allocation
#    through the device division planner (D-089), and a paint kernel through the shared
#    ownership-delta routine with atomic tracker updates. On a device a pass costs NO host
#    round trip: 0 syncs, 0 transfers, 0 bytes per MCS (D-085 counters), including the MCS
#    that allocates. Zero cost when off: a model with no `@convert` keeps its generated code
#    and fingerprint (pinned below on a convert-free fixture, as computed on the freeze
#    base), and a quiet pass allocates nothing on the CPU (0 bytes per warm `step!`).
# F. Not pinned here: `budget` (see the report: per-entity budgets need an order among
#    independent candidates, which D-233 removed; the coordinator rules on it), `gate`,
#    `when`, `order`, `Every(n)` on `@convert`, `cells(…)` domains with allocation, `to = 0`
#    (conversion to medium), `Fresh(k)` without a reference, a pass whose `from` dies.
# G. Kind-conditional, expression-valued cell-variable defaults (ergonomics review E1; NOT
#    supported on the freeze base: `ifelse(kind == nucleus, …)` in a default is
#    "Condition of `ifelse` must be a `Bool`"):
#        @variables V_target(cell) = ifelse(kind == nucleus, φ_n,
#                                      ifelse(kind == lamellipodium, φ_l, 1 - φ_n - φ_l)) * V_cell
#    The default is evaluated PER SLOT from the slot's kind and the parameters: at problem
#    construction for every initial cell the operating point gives no value (an explicit
#    `:V_target => …` still wins), and for every slot a `@convert` allocates. Division
#    daughters keep COPYING the parent's cell variables (D-066 item 5, existing behaviour, not
#    re-pinned here). A dereference of a dead referent (or 0) reads the default for kind 0
#    (the medium); the fixture's medium branch is nonzero, and only `volume[to] = 0` ⇒ p = c is
#    pinned for an absent `to`.
# Sections: 1 fixtures; 2 one pass by hand (start-of-pass p, `Fresh`, `created`, `transfer`);
# 3 the exact draw oracle over seeds (independence, determinism, algorithms); 4 negative
# controls; 5 trackers and the ΔH self-check after every pass; 6 birth, death, the
# reference reset and re-creation; 7 schedule; 8 `@extend` replacement and a site-dependent
# p, the `from`/`at` defaults; 9 zero cost when off; 10 thread counts (FULL tier); 11 device;
# 12 the Fortuna-shaped block (E3) and kind-conditional defaults (E1); 13 the clamp at 1.
#
# Fixtures that use the new syntax are defined through `p65b_define`, so a build failure
# today fails the testsets that use them instead of aborting the file.
using Test, Potts, PottsModels
using Potts: CorePotts
using Statistics: mean

const P65B_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P65B_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()

# ---------------------------------------------------------------------------------------
# 0. Helpers

const P65B_DEFINE_ERRORS = Dict{Symbol, Any}()
const P65B_SRC = Dict{Symbol, Expr}()
function p65b_define(name::Symbol, ex::Expr)
    P65B_SRC[name] = ex
    try
        Core.eval(@__MODULE__, ex)
    catch e
        P65B_DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
p65b_model(name::Symbol) = isdefined(@__MODULE__, name) ? getfield(@__MODULE__, name) :
                           error("P6.5b fixture $name did not build: $(get(P65B_DEFINE_ERRORS, name, "unknown"))")
p65b_system(name::Symbol; sysname = :m) = Base.invokelatest(p65b_model(name); name = sysname)
# the build error of a source (nothing if it builds), for the error-message tests
function p65b_build_error(ex::Expr; compile = true)
    try
        mod = Module()
        Core.eval(mod, Expr(:toplevel, :(using Potts), ex))
        m = Base.invokelatest(getfield, mod, ex.args[3])
        compile && Base.invokelatest(mtkcompile, Base.invokelatest(m; name = :x))
        return nothing
    catch e
        return e isa LoadError ? e.error : e
    end
end

p65b_vol(u) = Array(u.cell.volume)
p65b_col(u, n) = Array(getfield(u.cell, n))
p65b_ctx(prob) = Potts._host_ctx(prob)

const P65B_DIMS = (20, 20)
const P65B_KINDS = (:cytoplasm, :lamellipodium, :nucleus)    # kind indices 1, 2, 3
const P65B_CYTO, P65B_LAMEL, P65B_NUC = 1, 2, 3
const P65B_STREAM = "Potts.convert.protrusion"

# The model body. `convert`: the `@convert` statements (or nothing); `schedule`: a
# `@schedule` statement (or nothing); `refs`: the reference variables and their updates.
const P65B_CONVERT = quote
    @convert protrusion clusters(cytoplasm) begin
        from = sibling(cytoplasm)
        to = sibling(lamellipodium) | Fresh(lamellipodium)
        at = sub > 0.5
        p = c * (1 - volume[to] / Vt3)
        transfer(V_target, from => to, per_site = 1.0)
        births += created
        nconv += 1
    end
end
function p65b_body(; convert = P65B_CONVERT, schedule = nothing, refs = true)
    stmts = Any[
        :(@kinds medium cytoplasm lamellipodium nucleus),
        :(@parameters begin
            c = 1.0
            Vt3 = 4.0
            λ = 1.0
            mobile = 0.0
            T = 4.0
        end),
        refs ? :(@variables begin
            sub(site) = 0.0
            V_target(cell) = 0.0
            seen(cell) = 0.0
            lam(cell)::CellRef
            keep(cell)::CellRef
            births(model) = 0.0
            nconv(model) = 0.0
        end) : :(@variables begin
            sub(site) = 0.0
            V_target(cell) = 0.0
            births(model) = 0.0
            nconv(model) = 0.0
        end),
        :(@lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))),
        :(@energy begin
            cells => λ * (volume - V_target)^2 + 0.25 * surface
            contacts => ifelse(cluster[owner] == cluster[owner′], 1.0, 3.0)
        end),
        # the sweep is frozen unless `mobile > 0.5`: only the pass moves sites
        :(@constraint mobile > 0.5),
    ]
    refs && push!(stmts, :(@after_mcs begin
        seen ~ volume[sibling(lamellipodium)]
        lam ~ sibling(lamellipodium)
    end))
    push!(stmts, refs ? :(@observed begin
        bth(cell) ~ birth
        cx(cell) ~ centroid(1)
        cy(cell) ~ centroid(2)
        lb(cell) ~ birth[lam]
        kb(cell) ~ birth[keep]
        la(cell) ~ ifelse(alive(sibling(lamellipodium)), 1.0, 0.0)
    end) : :(@observed begin
        cx(cell) ~ centroid(1)
        cy(cell) ~ centroid(2)
    end))
    convert === nothing || append!(stmts, filter(s -> !(s isa LineNumberNode), convert.args))
    schedule === nothing || push!(stmts, schedule)
    push!(stmts, :(@sweep Metropolis(; temperature = T)))
    return Expr(:block, stmts...)
end
p65b_src(name; kw...) = Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :p65b), name, p65b_body(; kw...))

# ---------------------------------------------------------------------------------------
# Fixtures

# F1. The convert fixture (default schedule).
p65b_define(:P65bConvert, p65b_src(:P65bConvert))
# F2. The same, the pass listed before the after-MCS updates.
p65b_define(:P65bEarly, p65b_src(:P65bEarly; schedule = :(@schedule sweep, protrusion, after_mcs)))
# F3. Convert-free controls: the same body without the pass (with and without references).
p65b_define(:P65bNoConvert, p65b_src(:P65bNoConvert; convert = nothing))
p65b_define(:P65bPlain, p65b_src(:P65bPlain; convert = nothing, refs = false))
# F4. 14c-style replacement through `@extend`: a site-dependent p, the `from`/`at` defaults
# (every site of the cytoplasm is a candidate; p selects), a half-site transfer and a count.
p65b_define(:P65bReplaced, quote
    @potts_model P65bReplaced begin
        @extend cytoplasm, lamellipodium, sub, nconv, V_target = base = P65bConvert()
        @convert protrusion clusters(cytoplasm) begin            # `from` and `at` by default
            to = sibling(lamellipodium)
            p = ifelse(sub > 1.5, 1.0, 0.0)
            transfer(V_target, from => to, per_site = 0.5)
            nconv += 1
        end
    end
end)

# The initial state. Cluster A: cytoplasm 1 (σ[3:8, 3:10] minus the nucleus, 44 sites,
# root) and nucleus 2 (σ[5:6, 6:7]); NO lamellipodium. Cluster B: cytoplasm 3 (σ[12:14, 3:6],
# 12 sites, root) and lamellipodium 4 (σ[15, 3:4], 2 sites). Lone cytoplasm 5 (σ[2:5,
# 14:17]), off the mask. `sub` = 1 on rows 8 and 14 (every column): A's candidates are
# σ[8, 3:10] (8 sites), B's σ[14, 3:6] (4 sites); the medium on those rows is masked but not
# owned by any `from`. In the replacement fixture (F4) `sub` = 2 on σ[8, 3:6] and σ[14, 3:4].
function p65b_sigma()
    σ = zeros(Int32, P65B_DIMS)
    σ[3:8, 3:10] .= 1
    σ[5:6, 6:7] .= 2
    σ[12:14, 3:6] .= 3
    σ[15, 3:4] .= 4
    σ[2:5, 14:17] .= 5
    return σ
end
function p65b_sub(; replaced = false)
    s = zeros(P65B_DIMS)
    s[8, :] .= 1.0
    s[14, :] .= 1.0
    if replaced
        s[8, 3:6] .= 2.0
        s[14, 3:4] .= 2.0
    end
    return s
end
const P65B_KIND0 = [:cytoplasm, :nucleus, :cytoplasm, :lamellipodium, :cytoplasm]
const P65B_VT0 = [40.0, 4.0, 10.0, 2.0, 16.0]
p65b_op(; replaced = false) = [ownership => p65b_sigma(), kind => P65B_KIND0, cluster => [1, 1, 3, 3, 5],
    :sub => p65b_sub(; replaced), :V_target => P65B_VT0]
function p65b_problem(name::Symbol = :P65bConvert; seed = 1, tspan = (0, 3), T = Float64, replaced = false, kw...)
    prob = PottsProblem(p65b_system(name; sysname = :cv), p65b_op(; replaced), tspan; seed, T, capacity = 8)
    return isempty(kw) ? prob : remake(prob; p = [k => v for (k, v) in kw])
end

# ---------------------------------------------------------------------------------------
# Independent oracle of one pass (section B), on a state `u`, during the step t → t + 1.
# Returns the converted sites of each entity (root => sites) and, per root, the start-of-pass
# p used, from the fixture's p = c·(1 − V₃/Vt3) (or `pfun(site)` when given).

p65b_u(seed, t, s, ::Type{T}) where {T} =
    CorePotts.uniform(T, CorePotts.draw(CorePotts.RNGKey(seed), t, s, CorePotts.stream_id(P65B_STREAM))[1])

function p65b_oracle(u, t, seed; T = Float64, c = 1.0, Vt3 = 4.0, pfun = nothing)
    σ = Array(u.σ); v = p65b_vol(u); kd = p65b_col(u, :kind); cl = p65b_col(u, :cluster)
    sub = Array(u.site.sub)
    out = Dict{Int, Vector{Int}}()
    ps = Dict{Int, Float64}()
    for r in eachindex(v)
        (v[r] > 0 && cl[r] == r && kd[r] == P65B_CYTO) || continue
        ms = [m for m in eachindex(v) if v[m] > 0 && cl[m] == r]
        from = only(filter(m -> kd[m] == P65B_CYTO, ms))
        lam = filter(m -> kd[m] == P65B_LAMEL, ms)
        V3 = isempty(lam) ? 0 : v[only(lam)]
        p = c * (1 - V3 / Vt3)                                   # start of pass: once per entity
        ps[r] = p
        conv = Int[]
        for s in eachindex(σ)
            (σ[s] == from && sub[s] > 0.5) || continue
            q = pfun === nothing ? p : pfun(s)
            p65b_u(seed, t, s, T) < q && push!(conv, s)
        end
        out[r] = conv
    end
    return out, ps
end

# the sequential, re-evaluated reading (the 14a code's form, a recorded variant, NOT built):
# p recomputed after each conversion, candidates in index order. The negative control of the
# start-of-pass rule.
function p65b_sequential_count(u, t, seed; c = 1.0, Vt3 = 4.0, root = 1)
    σ = Array(u.σ); sub = Array(u.site.sub)
    V3 = 0; n = 0
    for s in eachindex(σ)
        (σ[s] == root && sub[s] > 0.5) || continue
        if p65b_u(seed, t, s, Float64) < c * (1 - V3 / Vt3)
            V3 += 1; n += 1
        end
    end
    return n
end

# every Moore(1) copy (target t takes source s's owner), as in P6.5a
function p65b_props(prob, u)
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
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end
function p65b_apply(prob, u, prop)
    a = deepcopy(u)
    a.σ[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, p65b_ctx(prob))
    return a
end
function p65b_gap(prob, u, prop)
    a = p65b_apply(prob, u, prop)
    return energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u)) -
           Potts._killing_credit(prob, u, prop, a)
end

# A full recount (section B): the alive cells relabelled 1:n into a fresh convert-free
# problem, whose trackers are computed from σ at construction.
function p65b_recount(u)
    σ = Array(u.σ); v = p65b_vol(u); kd = p65b_col(u, :kind); cl = p65b_col(u, :cluster)
    ids = sort!(filter(>(0), unique(σ)))
    rl = Dict(c => i for (i, c) in enumerate(ids))
    σ2 = map(c -> c == 0 ? Int32(0) : Int32(rl[c]), σ)
    fresh = PottsProblem(p65b_system(:P65bPlain; sysname = :rc), [ownership => σ2,
            kind => [P65B_KINDS[kd[c]] for c in ids], cluster => [rl[cl[c]] for c in ids],
            :sub => Array(u.site.sub), :V_target => p65b_col(u, :V_target)[ids]], (0, 1); capacity = 8)
    return fresh, ids
end
function p65b_tracker_checks(prob, u)
    fresh, ids = p65b_recount(u)
    f0 = fresh.u0
    n = length(ids)
    @test p65b_vol(u)[ids] == p65b_vol(f0)[1:n]
    @test all(c -> p65b_vol(u)[c] == 0, setdiff(1:8, ids))
    @test p65b_vol(u)[ids] == [count(==(c), Array(u.σ)) for c in ids]          # σ itself
    @test p65b_col(u, :surface)[ids] ≈ p65b_col(f0, :surface)[1:n] atol = 1e-9
    @test observe(prob, :cx, u)[ids] ≈ observe(fresh, :cx, f0)[1:n] atol = 1e-9
    @test observe(prob, :cy, u)[ids] ≈ observe(fresh, :cy, f0)[1:n] atol = 1e-9
    cl = p65b_col(u, :cluster)
    @test p65b_col(u, :cluster_volume) == CorePotts.recompute_cluster_volume(Array(u.σ), cl)
    @test total_energy(prob, u) ≈ total_energy(fresh, f0) atol = 1e-9
    return nothing
end

# ---------------------------------------------------------------------------------------
# 1. The fixtures build

@testset "P6.5b convert: the fixtures build" begin
    for name in (:P65bConvert, :P65bEarly, :P65bReplaced)            # the Fortuna fixtures are checked in section 12, after their definition
        @test isdefined(@__MODULE__, name)                       # DEFECT CHECK: `@convert`, `Fresh`, `created` unknown today
    end
    @test isdefined(@__MODULE__, :P65bNoConvert) && isdefined(@__MODULE__, :P65bPlain)   # controls build today
    @test mtkcompile(p65b_system(:P65bConvert)) isa CompiledPottsSystem
end

# ---------------------------------------------------------------------------------------
# 2. One pass by hand: start-of-pass p, `Fresh`, `created`, the writes

@testset "P6.5b convert: one pass by hand (start-of-pass p, Fresh, created, writes)" begin
    prob = p65b_problem(; seed = 1, tspan = (0, 3))
    u0 = prob.u0
    @test p65b_vol(u0)[1:5] == [44, 4, 12, 2, 16]                # fixture
    @test observe(prob, :bth, u0)[1:5] == [1, 2, 3, 4, 5]
    sol = solve(prob, SequentialCPM(); saveat = 1)
    @test Symbol(sol.retcode) === :Success
    u1 = sol.u[2]
    σ0, σ1 = p65b_sigma(), Array(u1.σ)
    v1 = p65b_vol(u1); kd = p65b_col(u1, :kind); cl = p65b_col(u1, :cluster)
    # cluster A: no lamellipodium, V₃ = 0, p = 1 for ALL 8 candidates (start of pass). Read
    # sequentially (p recomputed after each conversion) it could never pass V₃ = Vt3 = 4.
    @test p65b_sequential_count(u0, 0, 1) <= 4                  # negative control: the 14a-code reading
    @test count(==(6), σ1) == 8                                  # DEFECT CHECK: all 8 converted, in one pass
    @test all(==(6), σ1[8, 3:10])                                # the created cell: the lowest free slot, 6
    @test v1[6] == 8 && kd[6] == P65B_LAMEL && cl[6] == 1        # kind `k`, joins A's cluster (root 1 unchanged)
    @test cl[1] == 1 && cl[2] == 1
    @test v1[1] == 36                                            # 44 − 8: the cytoplasm lost its candidates
    @test observe(prob, :bth, u1)[6] == 6                        # the next serial (initial cells 1:5)
    @test p65b_col(u1, :generation)[6] == p65b_col(u0, :generation)[6] + 1
    # `transfer`: once, 1.0 × 8 conversions; the created cell starts at its declared default 0
    vt = p65b_col(u1, :V_target)
    @test vt[6] == 8.0
    @test vt[1] == 40.0 - 8.0                                    # conserved over from and to
    # cluster B: V₃ = 2, p = 1/2 for each of its 4 candidates, by the draw oracle
    conv, ps = p65b_oracle(u0, 0, 1)
    @test ps[1] == 1.0 && ps[3] == 0.5 && ps[5] == 1.0           # (5 has no candidates)
    @test isempty(conv[5])
    nB = length(conv[3])
    @test Set(findall(==(4), vec(σ1))) == Set(vcat(LinearIndices(σ0)[15, 3:4], conv[3]))
    @test v1[4] == 2 + nB && v1[3] == 12 - nB
    @test vt[4] == 2.0 + nB && vt[3] == 10.0 - nB                # B's existing `to`
    @test vt[2] == 4.0 && vt[5] == 16.0                          # nobody else's target moves
    # only candidates moved: owned by `from` and selected by `at`
    changed = findall(vec(σ0 .!= σ1))
    @test Set(changed) == Set(vcat(LinearIndices(σ0)[8, 3:10], conv[3]))
    @test all(s -> σ0[s] in (1, 3), changed)                     # never the medium on the masked rows, nor 2, 4, 5
    @test u1.model.births[1] == 1.0                              # one creation (A): `created` on one conversion of 8
    @test u1.model.nconv[1] == 8 + nB
    # pass 2: A's V₃ = 8 ≥ Vt3, p = 1 − 8/4 < 0 converts nothing (the clamp); B by the oracle
    u2 = sol.u[3]
    conv2, ps2 = p65b_oracle(u1, 1, 1)
    @test ps2[1] == -1.0 && isempty(conv2[1])
    @test count(==(6), Array(u2.σ)) == 8
    @test p65b_vol(u2)[4] == v1[4] + length(conv2[3])
    @test u2.model.births[1] == 1.0                              # no second creation for A
    # the other cells are untouched (frozen sweep)
    @test all(s -> σ1[s] == σ0[s], findall(vec((σ0 .== 2) .| (σ0 .== 5))))
end

# ---------------------------------------------------------------------------------------
# 3. The exact draw oracle: independence, start-of-pass p, determinism, both algorithms

@testset "P6.5b convert: every pass equals the counter-addressed oracle ($(nameof(typeof(alg))))" for alg in
                                                                                                         (SequentialCPM(), CheckerboardCPM())
    nB = Int[]
    for seed in 1:16
        prob = p65b_problem(; seed, tspan = (0, 3))
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        for t in 0:2
            u, w = sol.u[t + 1], sol.u[t + 2]
            conv, _ = p65b_oracle(u, t, seed)
            σu, σw = Array(u.σ), Array(w.σ)
            moved = findall(vec(σu .!= σw))
            @test Set(moved) == Set(reduce(vcat, values(conv); init = Int[]))   # DEFECT CHECK
            # every moved site went to its entity's lamellipodium
            for (r, ss) in conv, s in ss
                @test p65b_col(w, :kind)[σw[s]] == P65B_LAMEL && p65b_col(w, :cluster)[σw[s]] == r
            end
            # `transfer`: once per entity, 1.0 × its count; the targets are conserved
            vu, vw = p65b_col(u, :V_target), p65b_col(w, :V_target)
            @test sum(vw) == sum(P65B_VT0)
            for (r, ss) in conv
                isempty(ss) && continue
                to = σw[first(ss)]
                before = p65b_vol(u)[to] > 0 ? vu[to] : 0.0      # a created cell starts at 0
                @test vw[to] - before == length(ss)
                @test vu[r] - vw[r] == length(ss)
            end
            t == 0 && push!(nB, length(conv[3]))
        end
        # the same seed gives the same trajectory (counter-addressed: nothing else enters)
        again = solve(p65b_problem(; seed, tspan = (0, 3)), alg; saveat = 1)
        @test all(i -> Array(again.u[i].σ) == Array(sol.u[i].σ), eachindex(sol.u))
    end
    # the draws matter (the oracle is not vacuous): B's first-pass count varies over seeds
    @test length(unique(nB)) >= 3
    @test abs(mean(nB) - 2) < 1.0                                # Bin(4, 1/2) over 16 seeds (sd of the mean 0.25)
end

@testset "P6.5b convert: the two algorithms give identical passes (frozen sweep)" begin
    for seed in 1:4
        a = solve(p65b_problem(; seed), SequentialCPM(); saveat = 1)
        b = solve(p65b_problem(; seed), CheckerboardCPM(); saveat = 1)
        @test all(i -> Array(a.u[i].σ) == Array(b.u[i].σ) && p65b_col(a.u[i], :V_target) == p65b_col(b.u[i], :V_target),
            eachindex(a.u))
    end
end

# ---------------------------------------------------------------------------------------
# 4. Negative controls

@testset "P6.5b convert: p = 0 and V₃ ≥ target convert nothing" begin
    # c = 0: p = 0 everywhere
    prob = p65b_problem(; c = 0.0)
    sol = solve(prob, SequentialCPM(); saveat = 1)
    @test Symbol(sol.retcode) === :Success
    u = sol.u[end]
    @test Array(u.σ) == p65b_sigma()
    @test p65b_vol(u)[6:8] == [0, 0, 0]                          # no cell, no slot used (X2)
    @test u.model.births[1] == 0.0 && u.model.nconv[1] == 0.0
    @test u.model[Symbol("#next_birth")][1] == 6                 # no serial consumed
    @test p65b_col(u, :V_target)[1:5] == P65B_VT0
    # Vt3 = 2: B's V₃ = 2 is at its target, p = 0; A (V₃ = 0) still converts all 8
    sol2 = solve(p65b_problem(; Vt3 = 2.0), SequentialCPM(); saveat = 1)
    u2 = sol2.u[end]
    @test p65b_vol(u2)[4] == 2 && p65b_vol(u2)[3] == 12          # DEFECT CHECK (control A below)
    @test count(==(6), Array(u2.σ)) == 8
    # Vt3 = 1: B's p = 1 − 2 < 0, clamped: nothing
    sol3 = solve(p65b_problem(; Vt3 = 1.0), SequentialCPM(); saveat = 1)
    @test p65b_vol(sol3.u[end])[4] == 2
    # control: the oracle agrees that these are the only differences
    @test isempty(p65b_oracle(prob.u0, 0, 1; c = 0.0)[1][1])
    @test isempty(p65b_oracle(prob.u0, 0, 1; Vt3 = 1.0)[1][3])
end

# ---------------------------------------------------------------------------------------
# 5. Trackers and the ΔH self-check after every pass

@testset "P6.5b convert: trackers equal a full recount, and ΔH stays exact, after every pass" begin
    for seed in 1:3
        prob = p65b_problem(; seed, tspan = (0, 3))
        sol = solve(prob, SequentialCPM(); saveat = 1)
        @test Symbol(sol.retcode) === :Success
        for u in sol.u[2:end]
            p65b_tracker_checks(prob, u)                         # DEFECT CHECK
            worst = 0.0
            n = 0
            for pr in p65b_props(prob, u)
                (pr.old in (1, 3, 4, 6) || pr.new in (1, 3, 4, 6)) || continue
                worst = max(worst, abs(p65b_gap(prob, u, pr)))
                n += 1
            end
            @test n > 100
            @test worst < 1e-9
        end
    end
    # negative control: a stale tracker is detected by the recount
    prob = p65b_problem(; tspan = (0, 1))
    u = solve(prob, SequentialCPM()).u[end]
    bad = deepcopy(u)
    bad.cell.volume[1] += 1
    fresh, ids = p65b_recount(bad)
    @test p65b_vol(bad)[ids] != p65b_vol(fresh.u0)[1:length(ids)]
end

# ---------------------------------------------------------------------------------------
# 6. Birth on the first conversion, death when emptied, the reference reset, re-creation

@testset "P6.5b convert: birth, death by emptying, reference reset before allocation, re-creation" begin
    prob = p65b_problem(; seed = 1, tspan = (0, 2))
    sol = solve(prob, SequentialCPM(); saveat = 1)
    u1 = sol.u[2]
    @test count(==(6), Array(u1.σ)) == 8                         # A's lamellipodium is born in slot 6
    g1 = p65b_col(u1, :generation)[6]
    # the created cell is read through references (P6.5a): the after-MCS updates of MCS 2
    u2 = sol.u[3]
    @test p65b_col(u2, :lam)[1] == 6 && observe(prob, :lb, u2)[1] == 6
    @test observe(prob, :la, u2)[1] == 1.0
    @test p65b_col(u2, :seen)[1] == 8                            # volume[sibling(lamellipodium)]
    # empty slot 6 by copies of the cytoplasm (the copies commit like the sweep's)
    a = deepcopy(u1)
    while p65b_vol(a)[6] > 0
        pr = first(filter(q -> q.old == 6 && q.new == 1, p65b_props(prob, a)))
        a = p65b_apply(prob, a, pr)
    end
    @test p65b_vol(a)[6] == 0 && observe(prob, :la, a)[1] == 0.0  # dead: `sibling` reads 0
    @test count(==(1), Array(a.σ)) == 44
    a.cell.keep[1] = 6                                           # a stale reference to the dead cell
    a.cell.keep[3] = 4                                           # a live one (B's lamellipodium), kept
    prob2 = remake(prob; u0 = a, tspan = (1, 2))
    sol2 = solve(prob2, SequentialCPM(); saveat = 1)
    @test Symbol(sol2.retcode) === :Success
    w = sol2.u[end]
    # p = 1 again (no lamellipodium): all 8 convert into a NEW cell in the lowest free slot, 6
    @test count(==(6), Array(w.σ)) == 8                          # DEFECT CHECK
    @test p65b_col(w, :kind)[6] == P65B_LAMEL && p65b_col(w, :cluster)[6] == 1
    @test p65b_col(w, :generation)[6] == g1 + 1                  # a reused slot: a new generation
    @test observe(prob, :bth, w)[6] == 7                         # a new serial, never 6 again
    @test p65b_col(w, :V_target)[6] == 8.0                       # declared default 0, then 8 × 1.0: not 8 + 8
    @test w.model.births[1] == 2.0
    # the reset ran before the allocation: the stale reference does not alias the new cell
    @test p65b_col(w, :keep)[1] == 0
    @test observe(prob, :kb, w)[1] == 0
    @test p65b_col(w, :keep)[3] == 4 && observe(prob, :kb, w)[3] == 4
    # negative control: an unreset reference would read the new cell
    stale = deepcopy(w)
    stale.cell.keep[1] = 6
    @test observe(prob, :kb, stale)[1] == 7
    p65b_tracker_checks(prob, w)
end

# ---------------------------------------------------------------------------------------
# 7. Schedule: a named phase, its default place, errors, fingerprints

@testset "P6.5b convert: `@convert name` is a named @schedule phase" begin
    # default place: after `after_mcs` (right before `lifecycle`): the update of MCS 1 sees no
    # lamellipodium yet; listed before `after_mcs`, it sees the 8 sites
    d = solve(p65b_problem(:P65bConvert; tspan = (0, 1)), SequentialCPM()).u[end]
    e = solve(p65b_problem(:P65bEarly; tspan = (0, 1)), SequentialCPM()).u[end]
    @test count(==(6), Array(d.σ)) == 8 && count(==(6), Array(e.σ)) == 8
    @test p65b_col(d, :seen)[1] == 0
    @test p65b_col(e, :seen)[1] == 8                             # DEFECT CHECK
    @test p65b_col(e, :lam)[1] == 6 && p65b_col(d, :lam)[1] == 0
    # hashed (D-016)
    @test p65b_problem(:P65bConvert).f.fingerprint != p65b_problem(:P65bEarly).f.fingerprint
    @test p65b_problem(:P65bConvert).f.fingerprint != p65b_problem(:P65bNoConvert).f.fingerprint
    # listing it in its default place is no schedule, bit for bit
    p65b_define(:P65bListed, p65b_src(:P65bListed; schedule = :(@schedule sweep, after_mcs, protrusion, lifecycle)))
    l = solve(p65b_problem(:P65bListed; tspan = (0, 3)), SequentialCPM(); saveat = 1)
    c = solve(p65b_problem(:P65bConvert; tspan = (0, 3)), SequentialCPM(); saveat = 1)
    @test all(i -> Array(l.u[i].σ) == Array(c.u[i].σ) && p65b_col(l.u[i], :seen) == p65b_col(c.u[i], :seen), eachindex(c.u))
end

@testset "P6.5b convert: schedule and naming errors name the offender" begin
    # an unknown name in the schedule
    e1 = p65b_build_error(p65b_src(:P65bTypo; schedule = :(@schedule sweep, protrusoin)))
    @test e1 isa ArgumentError && occursin("protrusoin", sprint(showerror, e1))
    # a pass named like a canonical phase
    bad = Base.deepcopy(P65B_CONVERT)
    bad.args[2].args[3] = :lifecycle
    e2 = p65b_build_error(p65b_src(:P65bCanon; convert = bad))
    @test e2 isa ArgumentError && occursin("lifecycle", sprint(showerror, e2))
    # two passes with one name
    twice = Expr(:block, P65B_CONVERT.args..., P65B_CONVERT.args...)
    e3 = p65b_build_error(p65b_src(:P65bTwice; convert = twice))
    @test e3 isa ArgumentError && occursin("protrusion", sprint(showerror, e3))
    # control: the plain source builds
    @test p65b_build_error(p65b_src(:P65bOk)) === nothing
end

# ---------------------------------------------------------------------------------------
# 8. `@extend` replaces a pass by name; p may read the site

@testset "P6.5b convert: @extend replaces the named pass; a site-dependent p" begin
    prob = p65b_problem(:P65bReplaced; replaced = true, tspan = (0, 1))
    u = solve(prob, SequentialCPM()).u[end]
    σ0, σ = p65b_sigma(), Array(u.σ)
    # only the `sub = 2` candidates convert (p = 1 there, 0 elsewhere): A 4, B 2
    moved = findall(vec(σ0 .!= σ))
    @test Set(moved) == Set(vcat(LinearIndices(σ0)[8, 3:6], LinearIndices(σ0)[14, 3:4]))   # DEFECT CHECK
    @test p65b_vol(u)[4] == 4                                    # B's existing lamellipodium
    @test count(==(6), σ) == 4                                   # A's created one
    @test u.model.nconv[1] == 6.0
    # the extension's transfer (0.5 per site), not the base's (1.0); the base's pass did not
    # also run (it would have taken all of A's 8 and counted a birth)
    vt = p65b_col(u, :V_target)
    @test vt[6] == 2.0 && vt[1] == 38.0                          # A: 4 × 0.5
    @test vt[4] == 3.0 && vt[3] == 9.0                           # B: 2 × 0.5
    @test vt[2] == 4.0 && vt[5] == 16.0
    @test u.model.births[1] == 0.0
    # the `from` default is the cytoplasm, the `at` default all its sites: the lone cytoplasm 5
    # (sub = 0, p = 0) and the nuclei never convert; only the 6 selected sites moved (above)
    @test prob.f.fingerprint != p65b_problem(:P65bConvert).f.fingerprint
end

# ---------------------------------------------------------------------------------------
# 9. Zero cost when off

# The fingerprint of the convert-free fixture P65bPlain on the freeze base (feat/p6-5a at
# bd6b647e): the implementation must not change the generated model of a model without
# `@convert`.
const P65B_PLAIN_FP = 0x8377d27787d7b4a5

@testset "P6.5b convert: zero cost when no @convert is declared" begin
    plain = p65b_problem(:P65bPlain)
    @test plain.f.fingerprint == P65B_PLAIN_FP
    # a quiet pass (p ≤ 0 everywhere: c = 0) allocates nothing on a warm CPU step
    prob = p65b_problem(; c = 0.0, tspan = (0, 50))
    integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
    for _ in 1:3
        step!(integ)
    end
    @test minimum(_ -> (@allocated step!(integ)), 1:3) == 0       # DEFECT CHECK
    # and after the passes have converted (A full, B at or past its target: quiet from then on)
    integ2 = init(p65b_problem(; tspan = (0, 50)), SequentialCPM(); save_start = false, save_end = false)
    for _ in 1:6
        step!(integ2)
    end
    @test count(==(6), Array(integ2.u.σ)) == 8                  # control: the pass did convert
    @test minimum(_ -> (@allocated step!(integ2)), 1:3) == 0
end

# ---------------------------------------------------------------------------------------
# 12. The Fortuna-shaped block (E3) and kind-conditional defaults (E1)

# Kinds: medium 0, substrate 1 (frozen), cytoplasm 2, lamellipodium 3, nucleus 4. The block
# is the ergonomics review's, verbatim but for `touches_substrate`, written with the existing
# neighbour-fold vocabulary (`count(true for n in VonNeumann(1)(s) if kind[n] == substrate)`,
# as the Bauer 2009 `near` folds) as a model-local helper.
const P65B_FORTUNA_BODY = quote
    @kinds medium substrate[frozen] cytoplasm lamellipodium nucleus
    @parameters begin
        c = 1.0
        V_cell = 40.0
        φ_n = 0.1
        φ_l = 0.1
        λ = 1.0
        mobile = 0.0
        T = 4.0
    end
    @variables begin
        V_target(cell) = ifelse(kind == nucleus, φ_n, ifelse(kind == lamellipodium, φ_l, 1 - φ_n - φ_l)) * V_cell
    end
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0
    @energy begin
        cells(cytoplasm, lamellipodium, nucleus) => λ * (volume - V_target)^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 1.0, 3.0)
    end
    @constraint mobile > 0.5
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = touches_substrate(site)
        p = c * (1 - volume[to] / V_target[to])
    end
    @observed bth(cell) ~ birth
    @sweep Metropolis(; temperature = T)
end
p65b_define(:P65bFortuna, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :p65b), :P65bFortuna, P65B_FORTUNA_BODY))
# the same with the explicit `| Fresh(lamellipodium)`
let body = Base.deepcopy(P65B_FORTUNA_BODY)
    blk = only(filter(a -> a isa Expr && a.head === :macrocall && a.args[1] === Symbol("@convert"), body.args)).args[end]
    for (i, a) in enumerate(blk.args)
        a isa Expr && a.head === :(=) && a.args[1] === :to && (blk.args[i] = :(to = sibling(lamellipodium) | Fresh(lamellipodium)))
    end
    p65b_define(:P65bFortunaFresh, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :p65b), :P65bFortunaFresh, body))
end

# substrate cell 3 on row 16; cytoplasm 1 σ[10:15, 4:11] minus nucleus 2 σ[11:12, 7:8] (44
# sites); the 8 cytoplasm sites of row 15 touch the substrate. No `:V_target` in the
# operating point: the kind defaults give cytoplasm 0.8·40 = 32, nucleus 4, a lamellipodium 4.
function p65b_fortuna_problem(name = :P65bFortuna; seed = 1, tspan = (0, 3), T = Float64, op = [])
    σ = zeros(Int32, 16, 16)
    σ[10:15, 4:11] .= 1
    σ[11:12, 7:8] .= 2
    σ[16, :] .= 3
    return PottsProblem(p65b_system(name; sysname = :fo), [ownership => σ, kind => [:cytoplasm, :nucleus, :substrate],
            cluster => [1, 1, 3], op...], tspan; seed, T, capacity = 6)
end

@testset "P6.5b convert: the Fortuna-shaped block builds and runs; kind-conditional defaults" begin
    @test isdefined(@__MODULE__, :P65bFortuna) && isdefined(@__MODULE__, :P65bFortunaFresh)   # DEFECT CHECK (E1 defaults, E3 block)
    prob = p65b_fortuna_problem()
    u0 = prob.u0
    # E1: the defaults per slot, from the kind, at construction
    @test p65b_col(u0, :V_target)[1:2] == [32.0, 4.0]            # DEFECT CHECK
    # an explicit value still wins
    pe = p65b_fortuna_problem(; op = [:V_target => [30.0, 5.0, 0.0]])
    @test p65b_col(pe.u0, :V_target)[1:2] == [30.0, 5.0]
    sol = solve(prob, SequentialCPM(); saveat = 1)
    @test Symbol(sol.retcode) === :Success
    u1, u2, u3 = sol.u[2], sol.u[3], sol.u[4]
    σ1 = Array(u1.σ)
    # pass 1: no lamellipodium (volume[to] = 0): p = c = 1, all 8 substrate-touching
    # cytoplasm sites convert into a lamellipodium allocated in slot 4 (implicit allocation)
    @test all(==(4), σ1[15, 4:11]) && count(==(4), σ1) == 8
    @test p65b_col(u1, :kind)[4] == 3 && p65b_col(u1, :cluster)[4] == 1
    @test observe(prob, :bth, u1)[4] == 4
    @test p65b_col(u1, :V_target)[4] == 4.0                      # E1: the default for the new slot's kind
    @test p65b_col(u1, :V_target)[1] == 32.0                     # no transfer in this block
    @test p65b_vol(u1)[1] == 36
    # pass 2: V₃ = 8 > V₃ᵗ = 4, p = 1 − 2 = −1, clamped to 0: nothing (and nothing later)
    @test Array(u2.σ) == σ1 && Array(u3.σ) == σ1
    # the explicit `| Fresh` form is the same pass
    pf = p65b_fortuna_problem(:P65bFortunaFresh)
    sf = solve(pf, SequentialCPM(); saveat = 1)
    @test all(i -> Array(sf.u[i].σ) == Array(sol.u[i].σ), eachindex(sol.u))
    # c = 1/2: by the draw oracle (8 candidates, p = 1/2 at the start of the pass)
    ph = remake(prob; p = [:c => 0.5])
    sh = solve(ph, SequentialCPM(); saveat = 1)
    σ0 = Array(u0.σ)
    want = [s for s in LinearIndices(σ0)[15, 4:11] if p65b_u(1, 0, s, Float64) < 0.5]
    @test Set(findall(vec(σ0 .!= Array(sh.u[2].σ)))) == Set(want)
    # E1 on its own (no `@convert`): a kind-conditional default builds and compiles
    @test p65b_build_error(Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :p65b), :P65bE1Only,
        quote
            @kinds medium cytoplasm nucleus
            @parameters V_cell = 40.0
            @variables V_target(cell) = ifelse(kind == nucleus, 0.1, 0.9) * V_cell
            @lattice Lattice((8, 8))
            @energy cells => (volume - V_target)^2
            @sweep Metropolis(; temperature = 1.0)
        end)) === nothing
end

# ---------------------------------------------------------------------------------------
# 13. The clamp at 1

@testset "P6.5b convert: p > 1 converts every candidate (the clamp at 1)" begin
    for seed in 1:8
        # c = 2.5: A's p = 2.5, B's p = 2.5 · (1 − 2/4) = 1.25: every candidate converts
        sol = solve(p65b_problem(; seed, c = 2.5, tspan = (0, 2)), SequentialCPM(); saveat = 1)
        u1 = sol.u[2]
        @test p65b_vol(u1)[4] == 6 && p65b_vol(u1)[3] == 8       # DEFECT CHECK: all 4 of B's
        @test count(==(6), Array(u1.σ)) == 8
        # pass 2: B's p = 2.5 · (1 − 6/4) < 0: nothing
        @test Array(sol.u[3].σ) == Array(u1.σ)
    end
end

# ---------------------------------------------------------------------------------------
# 10. Thread counts (FULL tier: two subprocesses)

@testset "P6.5b convert: bitwise equal across thread counts (FULL tier)" begin
    if P65B_FULL
        dir = mktempdir()
        src = joinpath(dir, "model.jl")
        write(src, string(P65B_SRC[:P65bConvert]))
        script = joinpath(dir, "run.jl")
        write(script, """
            using Potts, PottsModels, Serialization
            include($(repr(src)))
            σ = zeros(Int32, 20, 20); σ[3:8, 3:10] .= 1; σ[5:6, 6:7] .= 2; σ[12:14, 3:6] .= 3; σ[15, 3:4] .= 4; σ[2:5, 14:17] .= 5
            s = zeros(20, 20); s[8, :] .= 1.0; s[14, :] .= 1.0
            out = Any[]
            for seed in 1:32
                prob = PottsProblem(P65bConvert(; name = :cv), [ownership => σ,
                    kind => [:cytoplasm, :nucleus, :cytoplasm, :lamellipodium, :cytoplasm], cluster => [1, 1, 3, 3, 5],
                    :sub => s, :V_target => [40.0, 4.0, 10.0, 2.0, 16.0]], (0, 4); seed, capacity = 8)
                for alg in (SequentialCPM(), CheckerboardCPM())
                    sol = solve(prob, alg; saveat = 1)
                    push!(out, [(Array(u.σ), Array(u.cell.V_target), Array(u.cell.birth)) for u in sol.u])
                end
            end
            serialize(ARGS[1], out)
            """)
        proj = dirname(Base.active_project())
        res = map((1, 4)) do nt
            path = joinpath(dir, "t$nt.jls")
            run(`$(Base.julia_cmd()) -t $nt --project=$proj $script $path`)
            deserialize(path)
        end
        @test res[1] == res[2]
    else
        @test_skip "FULL tier: set POTTS_FULL_REPRODUCTION=true"
    end
    @info "P6.5b convert: light tier ran with $(Threads.nthreads()) thread(s); the exact oracle of section 3 is thread-count free"
end

# ---------------------------------------------------------------------------------------
# 11. Device

@testset "P6.5b convert: the pass on the device (Float32)" begin
    if P65B_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM(; proposal = Moore(1))
        # CPU and device, both Float32, frozen sweep: bitwise equal states (the draws are
        # counter-addressed and u is the same Float32 value on both; the fixture's p are
        # exact binary fractions, so no comparison is at a rounding boundary)
        for seed in 1:4
            cpu = solve(p65b_problem(; seed, T = Float32), SequentialCPM(); saveat = 1)
            dev = solve(p65b_problem(; seed, T = Float32), alg; backend, saveat = 1)
            @test Symbol(dev.retcode) === :Success
            for i in eachindex(cpu.u)
                a, b = cpu.u[i], dev.u[i]
                @test Array(a.σ) == Array(b.σ)
                for n in (:kind, :volume, :cluster, :generation, :birth, :V_target, :surface)
                    @test p65b_col(a, n) == p65b_col(b, n)
                end
                @test Array(a.model.births) == Array(b.model.births)
            end
            # and the Float32 oracle
            for t in 0:2
                conv, _ = p65b_oracle(dev.u[t + 1], t, seed; T = Float32)
                moved = findall(vec(Array(dev.u[t + 1].σ) .!= Array(dev.u[t + 2].σ)))
                @test Set(moved) == Set(reduce(vcat, values(conv); init = Int[]))
            end
        end
        # D-233 cost: no host round trip per MCS, including the MCS that allocates
        integ = init(p65b_problem(; T = Float32, tspan = (0, 5)), alg; backend, save_start = false, save_end = false)
        counts = NTuple{3, Int}[]
        for _ in 1:4
            c0 = (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes)
            step!(integ)
            push!(counts, (integ.stats.syncs, integ.stats.transfers, integ.stats.transfer_bytes) .- c0)
        end
        @test all(==((0, 0, 0)), counts)
        u = integ.u                                              # control: the passes ran (a read point)
        @test count(==(6), Array(u.σ)) == 8
        @test integ.stats.transfers > 0                          # control: the counters are live
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
