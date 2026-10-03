# P6.0ai (ROADMAP Phase 6, step 0): a population fold inside `integral(expr)` that reads
# neither the cell nor the site is re-evaluated at every site, once per tracker: each
# integral's site phase runs the whole fold (a loop over every cell) at every lattice site,
# O(sites × cells) per MCS, where the same fold factored out of the integral by hand is
# computed once per MCS (a model-scope slot, `_hoist_populations`). Frozen (AUTONOMY §7.3).
#
# Fixtures: a 200 × 200 lattice tiled by 400 cells of 10 × 10 (cell 20i + j + 1 holds
# x = 10i+1:10i+10, y = 10j+1:10j+10), a site variable `w` set to the smooth non-uniform
# field 1 + 0.5 sin(x/7) cos(y/11) (never written), and two cell trackers per model:
#   P60aiUnfactored   s ~ integral(w * mean(volume[c] for c in cells))
#                     r ~ integral(exp(-w) * sum(surface[c] for c in cells) +
#                                  sin(w) * sum(volume[c]^2 for c in cells) / 1e4)
#   P60aiFactored     s ~ integral(w) * mean(volume[c] for c in cells)
#                     r ~ integral(exp(-w)) * sum(surface[c] for c in cells) +
#                         integral(sin(w)) * sum(volume[c]^2 for c in cells) / 1e4
# The three folds read only the cells they iterate (inside a fold over `cells`, `volume`
# etc. denote the bound cell), so they are the same at every site. `s` and `r` feed nothing
# back (the energy is the volume constraint only), so both models move σ identically.
#
# Measured on the code before the change (feat/p6-0ai at 2f54c1e9, Julia 1.12, this file run
# alone on an Apple-silicon laptop, one thread):
#   - item 1 passes: σ equal at every save; s, r equal between the forms to ≤ 1.7e-15
#     relative, and equal to the oracle to ≤ 1.1e-15;
#   - item 2 fails: a warm `step!` (SequentialCPM) costs 29 ms unfactored against 1.3 ms
#     factored on an idle machine (22×), 86 ms against 2.5 ms under load (34–35× in each
#     of the 3 attempts); limit 1.2×. With the unfactored trackers replaced by the factored
#     form (a stand-in for the hoist), the ratio is 1.00–1.02 and the file passes;
#   - items 3 and 4 pass (they pin what must not change).
#
# Pinned here:
#  1. Equal results. Same seed, 10 MCS, SequentialCPM and CheckerboardCPM: σ equal at every
#     save (precondition), and at every save 1–10 the unfactored `s`, `r` equal the factored
#     ones within rounding (relative 1e-12; the sums are associated differently) and equal
#     an oracle computed from the saved state: per cell k, Σ_{σ = k} w · (mean volume) and
#     Σ_{σ = k} (exp(-w) · Σ surface + sin(w) · Σ volume² / 1e4), over the live cells.
#  2. Cost. The per-MCS time of a warm `step!` (SequentialCPM, Float64, after two warm-up
#     steps) of the unfactored model is at most 1.2× that of the factored one. Each sample
#     times 5 consecutive steps; the two models alternate over 10 rounds and each keeps its
#     minimum (robust to load from other processes). Up to 3 attempts; the check passes
#     if one attempt is within 1.2× (noise can only spoil an attempt, never rescue a 22×).
#  3. Names stay canonical (D-107). Under salted hashes of the Potts operators
#     (`population`, `gather`, `at`, `at2`) and separately of `sin`, `cos`, `exp` (salts 1–4,
#     the P6.0ah mechanism), the unfactored model's `generated_code` (line numbers
#     stripped), its problem fingerprint and its state layout (the names of the cell and
#     model columns, i.e. the integral trackers and any hoisted slots) are identical to the
#     unsalted ones, and so are they over four repeated builds in one session.
#  4. Negative control: folds that read the site are not hoisted. In `P60aiSiteFold` (a
#     40 × 40 lattice, 16 cells of 10 × 10), a fold whose body reads the site variable `w`
#     (`sum(w * volume[c] for c in cells)`), one whose condition reads it
#     (`count(volume[c] > 100w for c in cells)`), and an integrand mixing a hoistable fold
#     with a site-reading one, all equal their per-site oracle at every save (relative 1e-12;
#     the count exactly), on both algorithms. (A fold over `cells` cannot read the enclosing
#     cell: inside it every cell name denotes the bound cell; and a fold over `sites` that
#     names a cell quantity is rejected. So "reads the site" is the expressible case.)
using Test, Potts, PottsModels

# ---------------------------------------------------------------------------------------
# Fixtures

@potts_model P60aiUnfactored begin
    @kinds medium A
    @variables begin
        w(site) = 1.0
        s(cell) = 0.0
        r(cell) = 0.0
    end
    @lattice Lattice((200, 200))
    @energy cells => (volume - 100.0)^2
    @after_mcs begin
        s ~ integral(w * mean(volume[c] for c in cells))
        r ~ integral(exp(-w) * sum(surface[c] for c in cells) + sin(w) * sum(volume[c]^2 for c in cells) / 1e4)
    end
    @sweep Metropolis(; temperature = 2.0)
end

@potts_model P60aiFactored begin
    @kinds medium A
    @variables begin
        w(site) = 1.0
        s(cell) = 0.0
        r(cell) = 0.0
    end
    @lattice Lattice((200, 200))
    @energy cells => (volume - 100.0)^2
    @after_mcs begin
        s ~ integral(w) * mean(volume[c] for c in cells)
        r ~ integral(exp(-w)) * sum(surface[c] for c in cells) + integral(sin(w)) * sum(volume[c]^2 for c in cells) / 1e4
    end
    @sweep Metropolis(; temperature = 2.0)
end

@potts_model P60aiSiteFold begin
    @kinds medium A
    @variables begin
        w(site) = 1.0
        pw(cell) = 0.0
        qw(cell) = 0.0
        mw(cell) = 0.0
    end
    @lattice Lattice((40, 40))
    @energy cells => (volume - 100.0)^2
    @after_mcs begin
        pw ~ integral(sum(w * volume[c] for c in cells))
        qw ~ integral(count(volume[c] > 100w for c in cells))
        mw ~ integral(w * mean(volume[c] for c in cells) + sum(w * surface[c] for c in cells))
    end
    @sweep Metropolis(; temperature = 2.0)
end

const P60AI_ALGS = (SequentialCPM(), CheckerboardCPM())

"""Ownership: an L × L lattice tiled by (L/10)² cells of 10 × 10."""
function p60ai_sigma(L)
    n = L ÷ 10
    σ = zeros(Int32, L, L)
    for i in 0:(n - 1), j in 0:(n - 1)
        σ[(10i + 1):(10i + 10), (10j + 1):(10j + 10)] .= n * i + j + 1
    end
    return σ
end
p60ai_w(L) = [1.0 + 0.5 * sin(x / 7) * cos(y / 11) for x in 1:L, y in 1:L]
p60ai_problem(M, L; n = 10, seed = 3) =
    PottsProblem(M(; name = :x), Any[ownership => p60ai_sigma(L), kind => fill(:A, (L ÷ 10)^2), :w => p60ai_w(L)], (0, n); seed)

p60ai_relerr(a, b) = maximum(abs.(a .- b) ./ max.(abs.(b), 1e-300))

# ---------------------------------------------------------------------------------------
# 1. Equal results

@testset "P6.0ai: factored and unfactored integrals agree ($(nameof(typeof(alg))))" for alg in P60AI_ALGS
    su = solve(p60ai_problem(P60aiUnfactored, 200), alg; saveat = 0:10)
    sf = solve(p60ai_problem(P60aiFactored, 200), alg; saveat = 0:10)
    @test length(su.u) == length(sf.u) == 11
    @test all(Array(a.σ) == Array(b.σ) for (a, b) in zip(su.u, sf.u))      # precondition
    for k in 2:11
        a, b = su.u[k], sf.u[k]
        @test p60ai_relerr(Array(a.cell.s), Array(b.cell.s)) <= 1e-12
        @test p60ai_relerr(Array(a.cell.r), Array(b.cell.r)) <= 1e-12
        # oracle from the saved state
        σ, w = Array(a.σ), Array(a.site.w)
        V, S = Array(a.cell.volume), Array(a.cell.surface)
        live = V .> 0
        @test count(live) == 400                       # nobody dies at this temperature
        mv = sum(V[live]) / count(live)
        ΣS, ΣV2 = sum(S[live]), sum(Float64.(V[live]) .^ 2)
        s_or = [sum(w[σ .== c]) * mv for c in 1:400]
        r_or = [sum(exp.(-w[σ .== c])) * ΣS + sum(sin.(w[σ .== c])) * ΣV2 / 1e4 for c in 1:400]
        @test p60ai_relerr(Array(a.cell.s)[1:400], s_or) <= 1e-12
        @test p60ai_relerr(Array(a.cell.r)[1:400], r_or) <= 1e-12
    end
    @test Array(su.u[end].σ) != p60ai_sigma(200)       # the cells moved: the check is live
end

# ---------------------------------------------------------------------------------------
# 2. Cost

"""Minimum per-MCS seconds of warm `step!`s of each problem, alternating."""
function p60ai_costs(probs; rounds = 10, k = 5)
    integs = map(p -> init(p, SequentialCPM(); save_start = false, save_end = false), probs)
    foreach(i -> (step!(i); step!(i)), integs)
    best = fill(Inf, length(integs))
    for _ in 1:rounds, (j, i) in enumerate(integs)
        t0 = time_ns()
        for _ in 1:k
            step!(i)
        end
        best[j] = min(best[j], (time_ns() - t0) / 1e9 / k)
    end
    return best
end

@testset "P6.0ai: an integral of a fold costs what the factored form costs" begin
    probs = (p60ai_problem(P60aiUnfactored, 200; n = 10_000), p60ai_problem(P60aiFactored, 200; n = 10_000))
    ratios = Float64[]
    for attempt in 1:3
        tu, tf = p60ai_costs(probs)
        push!(ratios, tu / tf)
        @info "P6.0ai: warm MCS unfactored $(round(tu * 1e3; digits = 3)) ms, factored $(round(tf * 1e3; digits = 3)) ms, ratio $(round(tu / tf; digits = 2))"
        ratios[end] <= 1.2 && break
    end
    @test minimum(ratios) <= 1.2
end

# ---------------------------------------------------------------------------------------
# 3. Names stay canonical (the P6.0ah salted-hash mechanism; shared when that file ran first)

if isdefined(@__MODULE__, :p60ah_salted) && isdefined(@__MODULE__, :P60AH_POTTS_OPS)
    const p60ai_salted = p60ah_salted
    const P60AI_POTTS_OPS = P60AH_POTTS_OPS
    const P60AI_BASE_OPS = P60AH_BASE_OPS
else
    const P60AI_SALT = Ref{UInt}(0)
    const P60AI_SALTED = Ref{Tuple}(())
    const P60AI_POTTS_OPS = (Potts.population, Potts.gather, Potts.at, Potts.at2)
    const P60AI_BASE_OPS = (sin, cos, exp)
    for f in (P60AI_POTTS_OPS..., P60AI_BASE_OPS...)
        @eval function Base.hash(g::typeof($f), h::UInt)
            (P60AI_SALT[] == 0 || !any(x -> x === g, P60AI_SALTED[])) && return invoke(hash, Tuple{Function, UInt}, g, h)
            return hash(P60AI_SALT[], hash(:p60ah_salt, h))
        end
    end
    function p60ai_salted(f, ops, s)
        P60AI_SALTED[] = ops
        P60AI_SALT[] = s
        try
            return f()
        finally
            P60AI_SALT[] = 0
            P60AI_SALTED[] = ()
        end
    end
end

function p60ai_strip!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing)
    foreach(p60ai_strip!, ex.args)
    return ex
end
p60ai_str(ex) = string(p60ai_strip!(deepcopy(ex)))

"""Generated code (as text), fingerprint and state layout of a model."""
function p60ai_build(M)
    g = Potts.generated_code(M(; name = :x))
    code = Pair{String, String}[]
    for k in propertynames(g)
        v = getproperty(g, k)
        v isa AbstractVector ? append!(code, ("$k[$i]" => p60ai_str(x) for (i, x) in enumerate(v))) :
        push!(code, String(k) => p60ai_str(v))
    end
    prob = p60ai_problem(M, 200; n = 2)
    u = prob.u0
    return (; code, fingerprint = prob.f.fingerprint, cell = propertynames(u.cell), model = propertynames(u.model))
end

@testset "P6.0ai: names stay canonical ($opl)" for (opl, ops) in (("Potts operators", P60AI_POTTS_OPS), ("sin, cos, exp", P60AI_BASE_OPS))
    base = p60ai_build(P60aiUnfactored)
    @test any(n -> startswith(String(n), "integral_"), base.cell)        # the trackers are in the layout
    for s in 1:4
        b = p60ai_salted(() -> p60ai_build(P60aiUnfactored), ops, s)
        @test b.code == base.code
        @test b.fingerprint == base.fingerprint
        @test b.cell == base.cell
        @test b.model == base.model
    end
end

@testset "P6.0ai: repeated builds are identical" begin
    base = p60ai_build(P60aiUnfactored)
    for _ in 1:3
        GC.gc(true)
        @test p60ai_build(P60aiUnfactored) == base
    end
end

# ---------------------------------------------------------------------------------------
# 4. Negative control: site-reading folds stay per site

@testset "P6.0ai: folds that read the site are not hoisted ($(nameof(typeof(alg))))" for alg in P60AI_ALGS
    sol = solve(p60ai_problem(P60aiSiteFold, 40; n = 4), alg; saveat = 0:4)
    @test length(sol.u) == 5
    @test Array(sol.u[end].σ) != p60ai_sigma(40)
    for u in sol.u[2:end]
        σ, w = Array(u.σ), Array(u.site.w)
        V, S = Array(u.cell.volume), Array(u.cell.surface)
        live = findall(>(0), V)
        @test length(live) == 16
        ΣV, ΣS, mv = sum(V[live]), sum(S[live]), sum(V[live]) / length(live)
        p_or = [sum(wi * ΣV for wi in w[σ .== c]; init = 0.0) for c in 1:16]
        q_or = [sum(count(v -> v > 100wi, V[live]) for wi in w[σ .== c]; init = 0) for c in 1:16]
        m_or = [sum(wi * mv + wi * ΣS for wi in w[σ .== c]; init = 0.0) for c in 1:16]
        @test p60ai_relerr(Array(u.cell.pw)[1:16], p_or) <= 1e-12
        @test Array(u.cell.qw)[1:16] == q_or
        @test 0 < sum(q_or) < 16 * 1600                # the condition is live at both ends
        @test p60ai_relerr(Array(u.cell.mw)[1:16], m_or) <= 1e-12
    end
end
