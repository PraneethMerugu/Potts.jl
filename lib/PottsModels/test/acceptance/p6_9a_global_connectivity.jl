# P6.9a (ROADMAP Phase 6, the connectivity part of P6.9, Bauer 2009): the global
# connectivity rule value `Global(; window, adjacency)` and the cell-scope `pieces` and
# `largest_piece`. Decisions: D-075 (api-synthesis §8.1 Q6, the device BFS), D-140 (the
# `Global()` placeholder), D-189 (rulings 4, 8, 9 and the P6.9 amendment), D-193, D-196;
# research/connectivity-vocabulary.md §8.1, §8.2, §8.4, §9.3, §12; model specs 05 (Bauer
# 2009 Eq 1, the continuity term α(1 − δ_{a,a′})) and 11 (Jafari Nivlouei Eq 3). Frozen
# (AUTONOMY §7.3).
#
# A proposal copies `new = σ(source)` into the target x, whose owner was `old`. PIECES of a
# cell are the connected components of its sites under an ADJACENCY: `:face` (4 square, 6
# hex, 6 cubic) or `:full` (8 square, 26 cubic; on hex `:full` is `:face`, D-193). Periodic
# axes wrap (index space); off a closed face there is nothing.
#
# Semantics pinned here:
#
#  1. The rule value. `Global(; window = nothing, adjacency = :face)` is accepted wherever a
#     rule is: `connectivity(kinds…; rule = Global(…))` in `@constraint` (veto) and in
#     `@drive … penalty` (penalty), and `connected(c; rule = Global(…))` for c ∈ {old, new}.
#     "Under Global, cell c stays connected through the copy" means: c is the medium, or
#     pieces(c after the copy) ≤ pieces(c before) under `adjacency` ("does not increase",
#     D-189; an already fragmented cell stays movable; the last site may be taken). Both
#     sides are tested: the veto refuses when old ≠ 0 of `kinds` fails, or new ≠ 0 of `kinds`
#     fails, each cell against its own kind filter (as `Simple()`); the penalty form charges
#     `penalty` × [the veto refuses]. `connected` has no kind filter.
#  2. Post-acceptance evaluation (§9.3). The veto is evaluated in the order local → ΔH →
#     acceptance draw → Global, and the trajectory is BITWISE identical to evaluating Global
#     before ΔH: pinned on SequentialCPM against a test-side replay of `sequential_mcs!`
#     that takes the brute-force decision first (a twin model without the Global line).
#     The one documented difference (§9.3) is pinned too: a copy that Global refuses but
#     whose ΔH is not finite fails the run (STATUS_NONFINITE) on both algorithms, where a
#     pre-ΔH constraint would have skipped it.
#  3. Window (D-075 Q6). `window = W` is the "device window", used only by CheckerboardCPM
#     (CPU and device). SequentialCPM (and BoundarySiteCPM) are exact and ignore it (counter
#     0). Under W the losing cell passes iff its sites adjacent (under `adjacency`) to x are
#     connected through its own sites, x excluded, inside the index-space box of radius W
#     round x (|Δ| ≤ W on every axis, minimum image on periodic axes, clipped at closed
#     faces). This is sound (it implies "does not increase") and conservative; the gaining
#     side needs no search (gaining x does not increase new's pieces iff x is adjacent to
#     new) and is exact. `window = nothing` is exact on every algorithm.
#     Counter: `stats.connectivity_deferred` is `nothing` for a model without `Global`; else
#     an `Int`: the copies refused only for want of window (local test failed, every other
#     test and the acceptance draw passed, the touching pieces do not meet inside the box and
#     each leaves it). It is 0 on SequentialCPM and with `window = nothing`; it counts only
#     copies that passed the draw (so it is thinned by the acceptance probability, which is
#     how a pre-acceptance evaluation is caught).
#  4. Cell scope. `pieces` and `largest_piece` (site count of the largest piece; 0 for a dead
#     cell) are cell built-ins with exact after-values, as `euler` (D-192):
#      - cell scope (`@energy cells(k) => …`, `@observed q(cell) ~ …`): `pieces`,
#        `largest_piece` (`:face`) and `pieces(; adjacency)`, `largest_piece(; adjacency)`;
#      - copy scope: before-values `pieces[c]`, `largest_piece[c]`, `pieces(c; adjacency)`,
#        `largest_piece(c; adjacency)` for c ∈ {old, new}, the medium reading 0. A bare
#        `pieces`/`largest_piece` in a drive is an `ArgumentError` (as `volume`, `euler`).
#     The shell fold `pieces(c, shell(target); adjacency)` (P6.3g) is unchanged.
#     Exact after every MCS (SequentialCPM, CPU CheckerboardCPM) against a flood-fill oracle;
#     `energy_change`, `delta_H` and `total_energy` equal brute force on fresh and on evolved
#     states (a drifting tracker is caught), including Bauer 2009's α(largest_piece ≠ volume)
#     and the Jafari / §8.3 α(pieces > 1) with α = 300; Float64 and Float32.
#  5. Coverage: square 2D, hex and cubic 3D, Periodic and Closed; SequentialCPM and
#     CheckerboardCPM.
#  6. Cost: zero warm allocations per `step!` (CPU, both algorithms) with `Global` and with
#     cell-scope `pieces`; an AllocCheck proof of `CorePotts.sequential_mcs!` for both (the
#     same call as test/qa.jl). AllocCheck must be loadable from the PottsModels test
#     environment.
#  7. Device (POTTS_GPU=metal|rocm, else `@test_skip`): CheckerboardCPM in Float32 with
#     `Global(; window)`: the invariant, the window fixture and its counter; `pieces` and
#     `largest_piece` exact.
#
# Ambiguities resolved here (for the D-entry): (a) "does not increase" for both sides, so
# the gaining side is the local test "x adjacent to new"; (b) `window` applies to
# CheckerboardCPM only; (c) the window is an index-space box of radius W (hex included);
# (d) the counter counts draw-passed copies whose decision overflowed (not a comparison with
# the exact answer); (e) the non-finite ΔH of a Global-refused copy fails the run; (f)
# cell-scope `pieces`/`largest_piece` take no window and are exact on every algorithm; (g)
# the window semantics of the penalty form, `window = nothing` on a device, and the
# BoundarySiteCPM rows are not pinned.
#
# Negative controls. Test-side (they pass on the base and show the harness discriminates):
# the replay mirrors `sequential_mcs!` bit for bit; the reference's pre- and post-draw orders
# agree; each mutant decision changes the trajectory: a skipped `new` check, a local-only
# (shell) test, the wrong adjacency, "exactly one piece after" in place of "does not
# increase"; the window oracle is sound, equals the exact rule for a box covering the
# lattice, and the window fixture's predictions change under a wrong window (W − 1, W + 1,
# none). On the implementation: a pre-acceptance-only evaluation is caught by the counter's
# thinning and by the non-finite ordering; a wrong or ignored window by the loop fixture.
#
# On the base (5319166e) this file fails because `Global()` is an ArgumentError ("not
# available yet (P6.9)") in every model that uses it, and `pieces`/`largest_piece` are not
# cell built-ins (`largest_piece` is undefined); `PottsStats` has no `connectivity_deferred`;
# AllocCheck is not in the PottsModels test environment. The oracle, replay and mutant
# controls pass on the base.
using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Geometry (index space)

const P69A_HEX = ((1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1))
const P69A_SQ4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
const P69A_SQ8 = Tuple((i, j) for i in -1:1 for j in -1:1 if (i, j) != (0, 0))
const P69A_CU6 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
const P69A_CU26 = Tuple((i, j, k) for k in -1:1 for j in -1:1 for i in -1:1 if (i, j, k) != (0, 0, 0))

p69a_nbrs(geom, adj) = geom === :hex ? P69A_HEX : geom === :square ? (adj === :face ? P69A_SQ4 : P69A_SQ8) :
                       (adj === :face ? P69A_CU6 : P69A_CU26)
p69a_shell(geom) = geom === :hex ? P69A_HEX : geom === :square ? P69A_SQ8 : P69A_CU26
p69a_adjs(geom) = geom === :hex ? (:face,) : (:face, :full)
p69a_dual(adj) = adj === :face ? :full : :face

"""`y` wrapped on a periodic lattice; `nothing` off a closed one."""
function p69a_wrap(y, dims, periodic)
    periodic && return map(mod1, y, dims)
    all(k -> 1 <= y[k] <= dims[k], eachindex(y)) || return nothing
    return y
end

# ---------------------------------------------------------------------------------------
# Oracle: flood fills

"""(pieces, largest piece) of the sites where `M` holds, under the offsets `nbrs`."""
function p69a_flood(M::AbstractArray{Bool}, nbrs, periodic)
    dims = size(M)
    seen = falses(dims)
    n = 0
    big = 0
    for I in CartesianIndices(M)
        (M[I] && !seen[I]) || continue
        n += 1
        sz = 0
        stack = [Tuple(I)]
        seen[I] = true
        while !isempty(stack)
            j = pop!(stack)
            sz += 1
            for o in nbrs
                y = p69a_wrap(j .+ o, dims, periodic)
                y === nothing && continue
                (M[y...] && !seen[y...]) || continue
                seen[y...] = true
                push!(stack, y)
            end
        end
        big = max(big, sz)
    end
    return n, big
end

"""(pieces, largest piece) of cell `c` of `σ` (the medium and dead cells: (0, 0))."""
p69a_pieces(σ, c, geom, adj; periodic) =
    c == 0 ? (0, 0) : p69a_flood(σ .== c, p69a_nbrs(geom, adj), periodic)

"""Pieces of cell `c` after the copy x ← `new` (σ is restored)."""
function p69a_after(σ, x, new, c, geom, adj; periodic)
    was = σ[x...]
    σ[x...] = new
    out = p69a_pieces(σ, c, geom, adj; periodic)
    σ[x...] = was
    return out
end

"""`Global`'s per-cell test: `c` is the medium or its pieces do not increase."""
p69a_no_increase(σ, x, new, c, geom, adj; periodic) =
    c == 0 || p69a_after(σ, x, new, c, geom, adj; periodic)[1] <= p69a_pieces(σ, c, geom, adj; periodic)[1]

"""Pieces of `old`'s in-domain shell sites under `adj` (the local proxy, for a mutant)."""
function p69a_shell_pieces(σ, x, old, geom, adj; periodic)
    dims = size(σ)
    sites = [y for y in (p69a_wrap(x .+ o, dims, periodic) for o in p69a_shell(geom)) if y !== nothing && σ[y...] == old]
    sites = unique(sites)
    nb = p69a_nbrs(geom, adj)
    seen = falses(length(sites))
    n = 0
    for i in eachindex(sites)
        seen[i] && continue
        n += 1
        stack = [i]
        seen[i] = true
        while !isempty(stack)
            a = pop!(stack)
            for b in eachindex(sites)
                seen[b] && continue
                any(o -> p69a_wrap(sites[a] .+ o, dims, periodic) == sites[b], nb) || continue
                seen[b] = true
                push!(stack, b)
            end
        end
    end
    return n
end

"""The window decision for the losing cell: its sites adjacent to x are connected through
its own sites other than x inside the box |Δ| ≤ W round x (minimum image)."""
function p69a_window_ok(σ, x, geom, adj, W; periodic)
    old = Int(σ[x...])
    old == 0 && return true
    dims = size(σ)
    dist(y, k) = (d = abs(y[k] - x[k]); periodic ? min(d, dims[k] - d) : d)
    inbox(y) = all(k -> dist(y, k) <= W, eachindex(y))
    nb = p69a_nbrs(geom, adj)
    touch = unique([y for y in (p69a_wrap(x .+ o, dims, periodic) for o in nb) if y !== nothing && σ[y...] == old])
    length(touch) <= 1 && return true
    seen = Set{Any}([touch[1]])
    stack = Any[touch[1]]
    while !isempty(stack)
        j = pop!(stack)
        for o in nb
            y = p69a_wrap(j .+ o, dims, periodic)
            (y === nothing || y == x || y in seen || σ[y...] != old || !inbox(y)) && continue
            push!(seen, y)
            push!(stack, y)
        end
    end
    return all(in(seen), touch)
end

"""The veto's decision for the copy x ← `new` (old = σ[x]) with kinds `kinds` (per cell) and
the constrained kinds `cons`; `mutant` and `W` give the controls and the window."""
function p69a_veto_ok(σ, x, new, geom, adj; periodic, kinds, cons = (:A,), mutant = :none, W = nothing)
    old = Int(σ[x...])
    a = mutant === :wrong_adjacency ? p69a_dual(adj) : adj
    free(c) = c == 0 || !(kinds[c] in cons)
    function oldside()
        free(old) && return true
        mutant === :local_only && return p69a_shell_pieces(σ, x, old, geom, a; periodic) <= 1
        mutant === :exactly_one && return p69a_after(σ, x, new, old, geom, a; periodic)[1] <= 1
        W === nothing || return p69a_window_ok(σ, x, geom, a, W; periodic)
        return p69a_no_increase(σ, x, new, old, geom, a; periodic)
    end
    function newside()
        (mutant === :skip_new || free(new)) && return true
        mutant === :exactly_one && return p69a_after(σ, x, new, new, geom, a; periodic)[1] == 1
        return p69a_no_increase(σ, x, new, new, geom, a; periodic)
    end
    return oldside() && newside()
end

"""A deterministic random state of labels 0:n (medium about 1/(n+1)), every label present."""
function p69a_random_σ(dims, n, seed)
    st = UInt64(seed) * 0x9E3779B97F4A7C15 + 1
    σ = zeros(Int32, dims)
    for i in eachindex(σ)
        st = st * 6364136223846793005 + 1442695040888963407
        σ[i] = Int32((st >> 33) % (n + 1))
    end
    for c in 1:n
        σ[c] = c
    end
    return σ
end

# ---------------------------------------------------------------------------------------
# The replay: `CorePotts.sequential_mcs!` with a test-side Global decision `ok(σ, x, old,
# new)` taken before ΔH (`order = :pre`, the reference) or after the acceptance draw
# (`:post`), and `extra(σ, x, old, new)` added to ΔH (the penalty form). Runs the twin
# model's integrator (no Global in it) and returns (status, refused, refused with a
# non-finite ΔH).

function p69a_replay_mcs!(integ, mcs, ok; order = :pre, extra = nothing)
    st = integ.state
    f = integ.kf
    p = integ.p
    law = integ.law
    key = integ.key
    ctx = CorePotts.sweep_ctx(integ.ctx, mcs)
    σ = st.σ
    lat = ctx.lattice
    mob = ctx.mobility
    nsite = CorePotts.nmobile(mob, lat)
    K = length(ctx.proposal)
    refused = 0
    refused_inf = 0
    for attempt in 1:nsite
        rt, rd, ra, _ = CorePotts.draw(key, mcs, attempt, CorePotts.STREAM_SEQUENTIAL_TARGET)
        t = CorePotts.mobile_site(mob, CorePotts.bounded(rt, nsite) + 1)
        x = CorePotts.coordinates(lat, t)
        dir = CorePotts.bounded(rd, K) + 1
        inside, y = CorePotts.shift(lat, x, ctx.proposal.offsets[dir])
        inside || continue
        s = CorePotts.linear_index(lat, y)
        CorePotts.is_mobile(mob, s) || continue
        a = σ[t]
        b = σ[s]
        a == b && continue
        prop = CorePotts.Proposal(t, s, x, dir, a, b)
        f.constraint(st, p, prop, ctx) || continue
        X = Tuple(x)
        if order === :pre && !ok(σ, X, Int(a), Int(b))
            refused += 1
            isfinite(f.delta_H(st, p, prop, ctx)) || (refused_inf += 1)
            continue
        end
        dH0 = f.delta_H(st, p, prop, ctx)
        extra === nothing || (dH0 += extra(σ, X, Int(a), Int(b)))
        temperature = f.temperature(st, p, prop, ctx)
        T = typeof(temperature)
        dH = CorePotts._effective_dH(f, dH0, temperature, st, p, prop, ctx)
        isfinite(dH) || return CorePotts.STATUS_NONFINITE, refused, refused_inf
        if CorePotts.accept(law, T(dH), temperature, CorePotts.uniform(T, ra))
            if order === :post && !ok(σ, X, Int(a), Int(b))
                refused += 1
                continue
            end
            σ[t] = b
            f.commit!(st, p, prop, ctx)
        end
    end
    return UInt32(0), refused, refused_inf
end

"""Replays `n` MCS of the twin problem; the σ after each MCS and the total refusals."""
function p69a_replay(prob, n, ok; kw...)
    integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
    out = Array{Int32}[]
    refused = 0
    for t in 0:(n - 1)
        st, r, _ = p69a_replay_mcs!(integ, t, ok; kw...)
        refused += r
        st == 0 || error("replay: status $st")
        push!(out, copy(Array(integ.state.σ)))
    end
    return out, refused
end

"""The σ after each of `n` `step!`s of the real integrator."""
function p69a_run(prob, alg, n)
    integ = init(prob, alg; save_start = false, save_end = false)
    out = Array{Int32}[]
    for _ in 1:n
        step!(integ)
        push!(out, copy(Array(integ.state.σ)))
    end
    return out, integ
end

# ---------------------------------------------------------------------------------------
# Models

const P69A_GEOMS = [
    (:square, false) => (:(Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))), :(Moore(1)), (10, 10)),
    (:square, true) => (:(Lattice((10, 10); boundary = Periodic(), neighborhood = Moore(1))), :(Moore(1)), (10, 10)),
    (:hex, false) => (:(Lattice((10, 10); geometry = Hexagonal(), boundary = Closed(), neighborhood = Hex(1))), :(Hex(2)), (10, 10)),
    (:hex, true) => (:(Lattice((10, 10); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))), :(Hex(2)), (10, 10)),
    (:cubic, false) => (:(Lattice((6, 6, 6); boundary = Closed(), neighborhood = Moore(1))), :(Moore(1)), (6, 6, 6)),
    (:cubic, true) => (:(Lattice((6, 6, 6); boundary = Periodic(), neighborhood = Moore(1))), :(Moore(1)), (6, 6, 6)),
]
p69a_name(prefix, geom, periodic) = Symbol(prefix, uppercasefirst(string(geom)), periodic ? "Periodic" : "Closed")
p69a_model(prefix, geom, periodic) = getfield(@__MODULE__, p69a_name(prefix, geom, periodic))
p69a_bc(periodic) = periodic ? "Periodic" : "Closed"
const P69A_KINDS = [:A, :B, :A]

for ((geom, periodic), (lat, prop, dims)) in P69A_GEOMS
    V0 = prod(dims) ÷ 4
    # the twin: no Global (the replay's model, and the control)
    @eval @potts_model $(p69a_name("P69aTwin", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @relations proposal = $prop
        @energy cells => 0.0625 * (volume - $V0)^2
        @sweep Metropolis(; temperature = 2.0)
    end
    # the veto, face and full adjacency; with window 1 (ignored by SequentialCPM); a box
    # that covers the lattice (CheckerboardCPM: as exact as `nothing`)
    for (suffix, rule) in (("Veto", :(Global())), ("VetoFull", :(Global(; adjacency = :full))),
                           ("VetoW1", :(Global(; window = 1))), ("VetoWBig", :(Global(; window = $(maximum(dims))))))
        @eval @potts_model $(p69a_name("P69a" * suffix, geom, periodic)) begin
            @kinds medium A B
            @lattice $lat
            @relations proposal = $prop
            @energy cells => 0.0625 * (volume - $V0)^2
            @constraint connectivity(A; rule = $rule)
            @sweep Metropolis(; temperature = 2.0)
        end
    end
    # the penalty form
    @eval @potts_model $(p69a_name("P69aPen", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @relations proposal = $prop
        @energy cells => 0.0625 * (volume - $V0)^2
        @drive connectivity(A; rule = Global(), penalty = 2.0)
        @sweep Metropolis(; temperature = 2.0)
    end
    # every decision at once: delta_H = Σ 2^(i−1) [decision i refuses] (no energy)
    @eval @potts_model $(p69a_name("P69aBits", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @relations proposal = $prop
        @drive connectivity(A; rule = Global(), penalty = 1.0)
        @drive connectivity(A; rule = Global(; adjacency = :full), penalty = 2.0)
        @drive copy => 4.0 * !connected(old; rule = Global()) + 8.0 * !connected(new; rule = Global()) +
                       16.0 * !connected(old; rule = Global(; adjacency = :full)) +
                       32.0 * !connected(new; rule = Global(; adjacency = :full))
        @sweep Metropolis(; temperature = 1.0)
    end
    # cell scope: Bauer 2009 (A), Jafari / §8.3 (B), the full-adjacency values (all), the
    # copy-scope before-values (drive), read back through `@observed`
    @eval @potts_model $(p69a_name("P69aCell", geom, periodic)) begin
        @kinds medium A B
        @parameters begin
            α = 300.0
            β = 8.0
            μ = 0.5
            ν = 0.25
            ρ = 0.125
            κ = 2.0
        end
        @lattice $lat
        @relations proposal = $prop
        @energy begin
            cells => 0.0625 * (volume - $V0)^2 + μ * pieces(; adjacency = :full) +
                     ν * (volume - largest_piece(; adjacency = :full))
            cells(A) => α * (largest_piece != volume)
            cells(B) => β * (pieces > 1)
        end
        @drive copy => ρ * pieces[old] + κ * largest_piece(new; adjacency = :full)
        @observed begin
            np(cell) ~ pieces
            npf(cell) ~ pieces(; adjacency = :full)
            lp(cell) ~ largest_piece
            lpf(cell) ~ largest_piece(; adjacency = :full)
        end
        @sweep Metropolis(; temperature = 4.0)
    end
end

# the composed form, the medium and B exempt by hand (square periodic)
@potts_model P69aComposed begin
    @kinds medium A B
    @lattice Lattice((10, 10); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy cells => 0.0625 * (volume - 25)^2
    @constraint connected(old; rule = Global()) | (kind[old] == B)
    @sweep Metropolis(; temperature = 2.0)
end

p69a_problem(M, σ; tspan = (0, 10), kw...) =
    PottsProblem(M(; name = :p69a), [ownership => σ, kind => P69A_KINDS[1:maximum(σ)]], tspan; seed = 5, kw...)

# ---------------------------------------------------------------------------------------
# The oracle and the harness (pass on the base)

@testset "P6.9a: the oracle (reference shapes, window soundness)" begin
    σ = zeros(Int32, 8, 8)
    σ[2:3, 2:3] .= 1; σ[5:6, 5:6] .= 1                   # two blocks: 2 pieces, largest 4
    σ[2, 6] = 2; σ[3, 7] = 2                              # diagonal pair: face 2, full 1
    σ[8, 1] = 3; σ[1, 8] = 3                              # opposite corners: wrap joins them diagonally
    @test p69a_pieces(σ, 1, :square, :face; periodic = false) == (2, 4)
    @test p69a_pieces(σ, 2, :square, :face; periodic = false) == (2, 1)
    @test p69a_pieces(σ, 2, :square, :full; periodic = false) == (1, 2)
    @test p69a_pieces(σ, 3, :square, :full; periodic = false) == (2, 1)
    @test p69a_pieces(σ, 3, :square, :full; periodic = true) == (1, 2)
    @test p69a_pieces(σ, 0, :square, :face; periodic = false) == (0, 0)
    σ = zeros(Int32, 8, 8); σ[3, :] .= 1                  # a band: one piece either way
    @test p69a_pieces(σ, 1, :square, :face; periodic = true) == (1, 8)
    σ[3, 4] = 0                                           # cut once: still one piece on the torus
    @test p69a_pieces(σ, 1, :square, :face; periodic = true) == (1, 7)
    @test p69a_pieces(σ, 1, :square, :face; periodic = false) == (2, 4)
    # hex: a 6-ring is one piece; two sites at hex distance 2 are two
    σ = zeros(Int32, 9, 9); foreach(o -> σ[(4, 4) .+ o...] = 1, P69A_HEX); σ[8, 8] = 2; σ[6, 8] = 2
    @test p69a_pieces(σ, 1, :hex, :face; periodic = false) == (1, 6)
    @test p69a_pieces(σ, 2, :hex, :face; periodic = false) == (2, 1)
    # cubic: edge-diagonal voxels face 2 / full 1
    σ = zeros(Int32, 5, 5, 5); σ[2, 2, 2] = 1; σ[3, 3, 2] = 1
    @test p69a_pieces(σ, 1, :cubic, :face; periodic = false) == (2, 1)
    @test p69a_pieces(σ, 1, :cubic, :full; periodic = false) == (1, 2)
    # "does not increase": a bar's interior site splits it; its end does not; a fragmented
    # cell may lose an isolated piece (decrease) and may gain next to a piece
    σ = zeros(Int32, 9, 9); σ[5, 2:8] .= 1; σ[1, 1] = 1
    @test !p69a_no_increase(σ, (5, 5), 0, 1, :square, :face; periodic = false)
    @test p69a_no_increase(σ, (5, 8), 0, 1, :square, :face; periodic = false)
    @test p69a_no_increase(σ, (1, 1), 0, 1, :square, :face; periodic = false)
    @test p69a_no_increase(σ, (4, 5), 1, 1, :square, :face; periodic = false)              # attached gain
    @test p69a_no_increase(σ, (5, 5), 1, 0, :square, :face; periodic = false)              # the medium is exempt
    @test !p69a_no_increase(σ, (3, 5), 1, 1, :square, :face; periodic = false)             # detached gain
    @test !p69a_no_increase(σ, (4, 1), 1, 1, :square, :face; periodic = false)             # corner-only gain:
    @test p69a_no_increase(σ, (4, 1), 1, 1, :square, :full; periodic = false)              # refused under :face only
    # window soundness and exactness for a covering box, every geometry and boundary
    nfail = nwin = 0
    for ((geom, periodic), (_, _, dims)) in P69A_GEOMS, adj in p69a_adjs(geom), seed in 1:2
        σ = p69a_random_σ(dims, 3, 40 + seed)
        nsound = nexact = 0
        for I in CartesianIndices(σ)
            x = Tuple(I)
            σ[x...] == 0 && continue
            exact = p69a_no_increase(σ, x, 0, Int(σ[x...]), geom, adj; periodic)
            w = p69a_window_ok(σ, x, geom, adj, 1; periodic)
            nsound += !w || exact                         # window ⇒ exact
            nexact += p69a_window_ok(σ, x, geom, adj, maximum(dims); periodic) == exact
            nfail += !exact
            nwin += exact && !w                           # conservative refusals exist
        end
        n = count(!=(0), σ)
        @test nsound == n
        @test nexact == n
    end
    @test nfail > 0                                       # the rule refuses
    @test nwin > 0                                        # and a small window refuses more
end

@testset "P6.9a: the replay mirrors sequential_mcs! ($geom, $(p69a_bc(periodic)))" for ((geom, periodic), (_, _, dims)) in P69A_GEOMS
    prob = p69a_problem(p69a_model("P69aTwin", geom, periodic), p69a_random_σ(dims, 3, 7))
    want, _ = p69a_run(prob, SequentialCPM(), 4)
    got, refused = p69a_replay(prob, 4, (σ, x, a, b) -> true)
    @test got == want && refused == 0
    # the reference itself: Global before ΔH and after the draw give the same trajectory
    for adj in p69a_adjs(geom)
        ok = (σ, x, a, b) -> p69a_veto_ok(σ, x, b, geom, adj; periodic, kinds = P69A_KINDS)
        pre, rpre = p69a_replay(prob, 4, ok; order = :pre)
        post, _ = p69a_replay(prob, 4, ok; order = :post)
        @test pre == post
        @test rpre > 0                                    # the rule refuses something
        @test pre != want                                 # and it changes the run
    end
end

@testset "P6.9a: negative controls on the harness (mutants change the trajectory)" begin
    for (geom, periodic) in ((:square, true), (:hex, false), (:cubic, false))
        _, _, dims = Dict(P69A_GEOMS)[(geom, periodic)]
        prob = p69a_problem(p69a_model("P69aTwin", geom, periodic), p69a_random_σ(dims, 3, 7))
        dec(m) = (σ, x, a, b) -> p69a_veto_ok(σ, x, b, geom, :face; periodic, kinds = P69A_KINDS, mutant = m)
        ref, _ = p69a_replay(prob, 4, dec(:none))
        for m in (:skip_new, :local_only, :wrong_adjacency, :exactly_one)
            m === :wrong_adjacency && geom === :hex && continue   # hex has one adjacency
            @test p69a_replay(prob, 4, dec(m))[1] != ref
        end
    end
end

# ---------------------------------------------------------------------------------------
# Section 1: the rule's decisions through compiled drives (exact, host)

"""The six decisions (bit i−1 set when decision i refuses) by brute force."""
function p69a_bits(σ, x, new, geom; periodic)
    old = Int(σ[x...])
    full = geom === :hex ? :face : :full
    v(a; kw...) = p69a_veto_ok(σ, x, new, geom, a; periodic, kinds = P69A_KINDS, kw...)
    conn(c, a) = p69a_no_increase(σ, x, new, c, geom, a; periodic)
    r = (!v(:face), !v(full), !conn(old, :face), !conn(new, :face), !conn(old, full), !conn(new, full))
    return sum(r[i] << (i - 1) for i in 1:6)
end

"""Sources of the enumeration: the shell and distance 2 along each axis (detached gains)."""
p69a_sources(geom) = (p69a_shell(geom)...,
    (ntuple(k -> k == a ? s : 0, geom === :cubic ? 3 : 2) for a in 1:(geom === :cubic ? 3 : 2) for s in (-2, 2))...)

# the models' lattices (P69A_GEOMS): the enumerations run on the same dims
const P69A_ENUM_DIMS = Dict(:square => (10, 10), :hex => (10, 10), :cubic => (6, 6, 6))

@testset "P6.9a: Global's decisions = brute force ($geom, $(p69a_bc(periodic)))" for ((geom, periodic), _) in P69A_GEOMS
    M = p69a_model("P69aBits", geom, periodic)
    dims = P69A_ENUM_DIMS[geom]
    n = agree = 0
    seen = Set{Int}()
    firstbad = nothing
    for seed in 1:3
        σ = p69a_random_σ(dims, 3, 60 + seed)
        prob = PottsProblem(M(; name = :b), [ownership => σ, kind => P69A_KINDS], (0, 1))
        u = prob.u0
        ctx = Potts._host_ctx(prob)
        k = 0
        for I in CartesianIndices(σ), o in p69a_sources(geom)
            x = Tuple(I)
            k += 1
            k % 2 == 0 || continue
            y = p69a_wrap(x .+ o, dims, periodic)
            y === nothing && continue
            old, new = Int(σ[x...]), Int(σ[y...])
            old == new && continue
            prop = CorePotts.Proposal(CorePotts.linear_index(prob.lattice, x), CorePotts.linear_index(prob.lattice, y),
                x, 1, σ[x...], σ[y...])
            got = round(Int, prob.f.delta_H(u, prob.p, prop, ctx))
            want = p69a_bits(σ, x, new, geom; periodic)
            n += 1
            agree += got == want
            push!(seen, want)
            (got != want && firstbad === nothing) && (firstbad = (; x, y, old, new, got, want))
        end
    end
    firstbad === nothing || @info "P6.9a: first disagreement" geom periodic firstbad
    @test n >= 200
    @test agree == n
    @test length(seen) >= 6                               # many decision patterns occur
    # the last site may be taken (pieces fall to 0): a one-site A cell
    σ = zeros(Int32, dims); σ[2, 2, (geom === :cubic ? (2,) : ())...] = 1; σ[end, end, (geom === :cubic ? (4,) : ())...] = 2
    σ[end - 2, end - 2, (geom === :cubic ? (2,) : ())...] = 3
    prob = PottsProblem(M(; name = :b), [ownership => σ, kind => P69A_KINDS], (0, 1))
    x = (2, 2, (geom === :cubic ? (2,) : ())...)
    y = x .+ ntuple(k -> k == 1 ? 1 : 0, length(x))
    prop = CorePotts.Proposal(CorePotts.linear_index(prob.lattice, x), CorePotts.linear_index(prob.lattice, y), x, 1, σ[x...], σ[y...])
    @test round(Int, prob.f.delta_H(prob.u0, prob.p, prop, Potts._host_ctx(prob))) == 0
end

# ---------------------------------------------------------------------------------------
# Section 2: SequentialCPM = the pre-ΔH reference, bit for bit (post-acceptance identity)

@testset "P6.9a: SequentialCPM veto = pre-ΔH reference, bitwise ($geom, $(p69a_bc(periodic)))" for ((geom, periodic), (_, _, dims)) in P69A_GEOMS
    σ0 = p69a_random_σ(dims, 3, 9)
    twin = p69a_problem(p69a_model("P69aTwin", geom, periodic), σ0)
    rows = [("Veto", :face), ("VetoW1", :face)]           # window 1 is ignored here
    geom === :hex || push!(rows, ("VetoFull", :full))
    for (prefix, adj) in rows
        ref, refused = p69a_replay(twin, 6, (σ, x, a, b) -> p69a_veto_ok(σ, x, b, geom, adj; periodic, kinds = P69A_KINDS))
        got, integ = p69a_run(p69a_problem(p69a_model("P69a" * prefix, geom, periodic), σ0), SequentialCPM(), 6)
        @test got == ref
        @test refused > 0
        @test integ.stats.connectivity_deferred == 0
    end
    # the penalty form: ΔH += 2 × [the veto refuses]
    ref, _ = p69a_replay(twin, 6, (σ, x, a, b) -> true;
        extra = (σ, x, a, b) -> 2.0 * !p69a_veto_ok(σ, x, b, geom, :face; periodic, kinds = P69A_KINDS))
    @test p69a_run(p69a_problem(p69a_model("P69aPen", geom, periodic), σ0), SequentialCPM(), 6)[1] == ref
end

@testset "P6.9a: the composed form `connected(old; rule = Global()) | …` (SequentialCPM)" begin
    σ0 = p69a_random_σ((10, 10), 3, 9)
    twin = p69a_problem(P69aTwinSquarePeriodic, σ0)
    ref, refused = p69a_replay(twin, 6, (σ, x, a, b) -> a == 0 || P69A_KINDS[a] === :B ||
                                                          p69a_no_increase(σ, x, b, a, :square, :face; periodic = true))
    @test p69a_run(p69a_problem(P69aComposed, σ0), SequentialCPM(), 6)[1] == ref
    @test refused > 0
end

# ---------------------------------------------------------------------------------------
# Section 3: CheckerboardCPM (CPU): the invariant, and a covering window = no window

"""Pieces of every cell 1:3 under `adj`."""
p69a_counts(σ, geom, adj; periodic) = [p69a_pieces(σ, c, geom, adj; periodic)[1] for c in 1:3]

@testset "P6.9a: CheckerboardCPM: pieces of A never increase ($geom, $(p69a_bc(periodic)))" for ((geom, periodic), (_, _, dims)) in P69A_GEOMS
    σ0 = p69a_random_σ(dims, 3, 13)
    rows = [("Veto", :face)]
    geom === :hex || push!(rows, ("VetoFull", :full))
    down_A = up_B = 0                                     # non-vacuity, over the rows
    for (prefix, adj) in rows, alg in (CheckerboardCPM(), SequentialCPM())
        traj, integ = p69a_run(p69a_problem(p69a_model("P69a" * prefix, geom, periodic), σ0), alg, 10)
        prev = p69a_counts(σ0, geom, adj; periodic)
        up_A = 0
        for σ in traj
            now = p69a_counts(σ, geom, adj; periodic)
            up_A += (now[1] > prev[1]) + (now[3] > prev[3])
            down_A += (now[1] < prev[1]) + (now[3] < prev[3])
            up_B += now[2] > prev[2]
            prev = now
        end
        @test up_A == 0
        alg isa CheckerboardCPM && @test integ.stats.connectivity_deferred == 0
    end
    @test down_A > 0                                      # the runs move A
    @test up_B > 0                                        # control: the unconstrained B splits
    # a window covering the lattice is the exact rule: the same trajectory as no window
    a, ia = p69a_run(p69a_problem(p69a_model("P69aVeto", geom, periodic), σ0), CheckerboardCPM(), 8)
    b, ib = p69a_run(p69a_problem(p69a_model("P69aVetoWBig", geom, periodic), σ0), CheckerboardCPM(), 8)
    @test a == b
    @test ib.stats.connectivity_deferred == 0
end

# ---------------------------------------------------------------------------------------
# Section 4: the window. A one-wide square loop of side s (face adjacency): removing any of
# its sites keeps it one piece, but the way round leaves the box of radius W unless
# s ≤ W + 1. So under `window = W` the loop opens when s = W + 1 and never when s = W + 2
# (every such copy is a counted conservative refusal); SequentialCPM and `window = nothing`
# open both. Losing a site lowers H by 4, gaining one raises it by 4 at T = 0.25.

"""σ with a one-wide square loop of side `s` (cell 1) at `lo` in the plane (3D: z = 3)."""
function p69a_loop(dims, s, lo = 4)
    σ = zeros(Int32, dims)
    z = length(dims) == 3 ? (3,) : ()
    for i in lo:(lo + s - 1), j in lo:(lo + s - 1)
        (i in (lo, lo + s - 1) || j in (lo, lo + s - 1)) && (σ[i, j, z...] = 1)
    end
    return σ
end

const P69A_LOOP_LATS = [
    (:square, false, (12, 12)) => :(Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))),
    (:square, true, (12, 12)) => :(Lattice((12, 12); boundary = Periodic(), neighborhood = Moore(1))),
    (:cubic, false, (12, 12, 5)) => :(Lattice((12, 12, 5); boundary = Closed(), neighborhood = Moore(1))),
]
p69a_loopname(W, geom, periodic) = Symbol("P69aLoop", W === nothing ? "None" : string(W), uppercasefirst(string(geom)), p69a_bc(periodic))
for ((geom, periodic, _), lat) in P69A_LOOP_LATS, W in (2, 3, nothing)
    rule = W === nothing ? :(Global()) : :(Global(; window = $W))
    @eval @potts_model $(p69a_loopname(W, geom, periodic)) begin
        @kinds medium A
        @lattice $lat
        @relations proposal = Moore(1)
        @energy cells(A) => 4.0 * volume
        @constraint no_extinction
        @constraint connectivity(A; rule = $rule)
        @sweep Metropolis(; temperature = 0.25)
    end
end

@testset "P6.9a: the window oracle on the loop fixture (and wrong windows)" begin
    for ((geom, periodic, dims), _) in P69A_LOOP_LATS, W in (2, 3)
        for (s, opens) in ((W + 1, true), (W + 2, false))
            σ = p69a_loop(dims, s)
            sites = [Tuple(I) for I in CartesianIndices(σ) if σ[I] == 1]
            @test length(sites) == 4 * (s - 1)
            # exact: every site may go; under W: all or none, as predicted
            @test all(x -> p69a_no_increase(σ, x, 0, 1, geom, :face; periodic), sites)
            @test all(x -> p69a_window_ok(σ, x, geom, :face, W; periodic) == opens, sites)
            # a wrong window changes the prediction (caught by the runs below)
            opens && @test !any(x -> p69a_window_ok(σ, x, geom, :face, W - 1; periodic), sites)
            opens || @test all(x -> p69a_window_ok(σ, x, geom, :face, W + 1; periodic), sites)
        end
    end
end

@testset "P6.9a: window W on CheckerboardCPM ($geom, $(p69a_bc(periodic)))" for ((geom, periodic, dims), _) in P69A_LOOP_LATS
    for W in (2, 3)
        M = getfield(@__MODULE__, p69a_loopname(W, geom, periodic))
        open = p69a_loop(dims, W + 1)
        shut = p69a_loop(dims, W + 2)
        sol = solve(PottsProblem(M(; name = :l), [ownership => open, kind => [:A]], (0, 10); seed = 3), CheckerboardCPM())
        @test count(==(1), sol.u[end].σ) < count(==(1), open)                # s = W + 1 opens
        sol = solve(PottsProblem(M(; name = :l), [ownership => shut, kind => [:A]], (0, 10); seed = 3), CheckerboardCPM())
        @test Array(sol.u[end].σ) == shut                                    # s = W + 2 never does
        @test sol.stats.connectivity_deferred isa Int && sol.stats.connectivity_deferred > 0
        # SequentialCPM is exact: the window is ignored and nothing is counted
        sol = solve(PottsProblem(M(; name = :l), [ownership => shut, kind => [:A]], (0, 10); seed = 3), SequentialCPM())
        @test count(==(1), sol.u[end].σ) < count(==(1), shut)
        @test sol.stats.connectivity_deferred == 0
    end
    # no window: exact on the checkerboard
    M = getfield(@__MODULE__, p69a_loopname(nothing, geom, periodic))
    shut = p69a_loop(dims, 5)
    sol = solve(PottsProblem(M(; name = :l), [ownership => shut, kind => [:A]], (0, 10); seed = 3), CheckerboardCPM())
    @test count(==(1), sol.u[end].σ) < count(==(1), shut)
    @test sol.stats.connectivity_deferred == 0
end

# The counter counts only copies that passed the acceptance draw (post-acceptance
# evaluation): a static loop of side W + 2 whose losses cost δ. The proposals and draws are
# the same for every δ (the state never changes), so the count at acceptance probability ½
# is a thinned subset of the count at probability 1.
@potts_model P69aThin begin
    @kinds medium A
    @parameters δ = 0.0
    @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy cells(A) => 0.0625 * (volume - 12)^2
    @drive copy => δ * (old != 0) + 64.0 * (new != 0)
    @constraint connectivity(A; rule = Global(; window = 2))
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.9a: the counter is thinned by the acceptance draw (post-acceptance)" begin
    shut = p69a_loop((12, 12), 4)
    prob = PottsProblem(P69aThin(; name = :t), [ownership => shut, kind => [:A]], (0, 30); seed = 11)
    full = solve(remake(prob; p = [:δ => -0.0625]), CheckerboardCPM())          # ΔH = 0: always accepted
    half = solve(remake(prob; p = [:δ => log(2.0) - 0.0625]), CheckerboardCPM())  # accepted with probability ½
    @test Array(full.u[end].σ) == shut && Array(half.u[end].σ) == shut
    n1, nh = full.stats.connectivity_deferred, half.stats.connectivity_deferred
    @test n1 >= 60
    @test nh < n1
    @test 0.3 < nh / n1 < 0.7
end

# ---------------------------------------------------------------------------------------
# Section 5: the non-finite ΔH of a Global-refused copy fails the run (the order local →
# ΔH → draw → Global, §9.3). A bar's interior sites split it (Global refuses them) and their
# drive is 1/0; its ends and every gain are finite.

for (name, line) in ((:P69aInfGlobal, :(@constraint connectivity(A; rule = Global()))),
                     (:P69aInfLocal, :(@constraint (old == 0) | (pieces(old, shell(target)) < 2))),
                     (:P69aInfTwin, nothing))
    @eval @potts_model $name begin
        @kinds medium A
        @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
        @relations proposal = VonNeumann(1)
        @energy cells(A) => 0.0625 * (volume - 7)^2
        @drive copy => 1.0 / (1.0 * ((old == 0) | (pieces(old, shell(target)) < 2)))
        $(line === nothing ? :(@constraint no_extinction) : line)
        @sweep Metropolis(; temperature = 1.0)
    end
end

@testset "P6.9a: a Global-refused copy with a non-finite ΔH fails the run" begin
    bar = zeros(Int32, 12, 12); bar[6, 3:9] .= 1
    mk(M) = PottsProblem(M(; name = :inf), [ownership => bar, kind => [:A]], (0, 3); seed = 2)
    # the harness: the pre-ΔH reference skips the infinite copies, the post-draw order does not
    integ = init(mk(P69aInfTwin), SequentialCPM(); save_start = false, save_end = false)
    ok = (σ, x, a, b) -> a == 0 || p69a_no_increase(σ, x, b, a, :square, :face; periodic = false)
    st, refused, refused_inf = p69a_replay_mcs!(integ, 0, ok; order = :pre)
    @test st == 0 && refused_inf > 0
    integ = init(mk(P69aInfTwin), SequentialCPM(); save_start = false, save_end = false)
    @test p69a_replay_mcs!(integ, 0, ok; order = :post)[1] == CorePotts.STATUS_NONFINITE
    # control: a pre-ΔH (local) constraint guards the drive; the run succeeds
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test Symbol(solve(mk(P69aInfLocal), alg).retcode) === :Success
    end
    # Global is evaluated after the draw: the infinite ΔH is seen, the run fails
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test Symbol(solve(mk(P69aInfGlobal), alg).retcode) === :Failure
    end
end

# ---------------------------------------------------------------------------------------
# Section 6: cell-scope `pieces` and `largest_piece`

"""Oracle (pieces, largest) per cell 1:n and adjacency."""
p69a_cellvals(σ, n, geom, adj; periodic) = [p69a_pieces(σ, c, geom, adj; periodic) for c in 1:n]

"""Brute-force H of the P69aCell models (kinds A, B, A; V0 = N/4)."""
function p69a_energy(σ, geom; periodic)
    V0 = length(σ) ÷ 4
    full = geom === :hex ? :face : :full
    E = 0.0
    for (c, k) in enumerate(P69A_KINDS)
        v = count(==(c), σ)
        pf, lf = p69a_pieces(σ, c, geom, full; periodic)
        p1, l1 = p69a_pieces(σ, c, geom, :face; periodic)
        E += 0.0625 * (v - V0)^2 + 0.5 * pf + 0.25 * (v - lf)
        E += k === :A ? 300.0 * (l1 != v) : 8.0 * (p1 > 1)
    end
    return E
end

"""The drive ρ pieces[old] + κ largest_piece(new; :full) by brute force (medium 0)."""
p69a_drive(σ, old, new, geom; periodic) =
    0.125 * p69a_pieces(σ, old, geom, :face; periodic)[1] +
    2.0 * p69a_pieces(σ, new, geom, geom === :hex ? :face : :full; periodic)[2]

"""Every `step`-th copy of `u` (state of `prob`) checked against brute force; returns counts."""
function p69a_check_dh(prob, u, geom; periodic, step = 3, tol = 0.0)
    σ = Array(u.σ)
    dims = size(σ)
    ctx = Potts._host_ctx(prob)
    E0 = p69a_energy(σ, geom; periodic)
    n = nE = nD = nnz = 0
    k = 0
    for I in CartesianIndices(σ), o in p69a_shell(geom)
        x = Tuple(I)
        k += 1
        k % step == 0 || continue
        y = p69a_wrap(x .+ o, dims, periodic)
        y === nothing && continue
        old, new = Int(σ[x...]), Int(σ[y...])
        old == new && continue
        old != 0 && count(==(old), σ) == 1 && continue      # no killing copies (D-083)
        prop = CorePotts.Proposal(CorePotts.linear_index(prob.lattice, x), CorePotts.linear_index(prob.lattice, y),
            x, 1, σ[x...], σ[y...])
        σ1 = copy(σ); σ1[x...] = new
        dE = p69a_energy(σ1, geom; periodic) - E0
        ΔE = energy_change(prob, u, prop)
        ΔH = prob.f.delta_H(u, prob.p, prop, ctx)
        n += 1
        nnz += dE != 0
        nE += isapprox(ΔE, dE; atol = tol)
        nD += isapprox(ΔH - ΔE, p69a_drive(σ, old, new, geom; periodic); atol = tol)
    end
    return n, nE, nD, nnz, isapprox(total_energy(prob, u), E0; atol = tol * 10)
end

@testset "P6.9a: pieces and largest_piece exact after every MCS ($geom, $(p69a_bc(periodic)), $label)" for ((geom, periodic), (_, _, dims)) in P69A_GEOMS,
    (label, alg) in (("SequentialCPM", SequentialCPM()), ("CheckerboardCPM", CheckerboardCPM()))
    M = p69a_model("P69aCell", geom, periodic)
    prob = p69a_problem(M, p69a_random_σ(dims, 3, 17); tspan = (0, 10))
    full = geom === :hex ? :face : :full
    # t = 0 (the initial rebuild)
    u = prob.u0
    @test getu(prob, :np)(prob)[1:3] == first.(p69a_cellvals(Array(u.σ), 3, geom, :face; periodic))
    integ = init(prob, alg; save_start = false, save_end = false)
    bad = 0
    seen = Set{Int}()
    for _ in 1:10
        step!(integ)
        σ = Array(integ.state.σ)
        face = p69a_cellvals(σ, 3, geom, :face; periodic)
        fv = p69a_cellvals(σ, 3, geom, full; periodic)
        bad += collect(integ[:np])[1:3] != first.(face)
        bad += collect(integ[:lp])[1:3] != last.(face)
        bad += collect(integ[:npf])[1:3] != first.(fv)
        bad += collect(integ[:lpf])[1:3] != last.(fv)
        union!(seen, first.(face))
    end
    @test bad == 0
    @test length(seen) >= 3                               # pieces vary (non-vacuous)
    # the tracked values feed the energies: ΔH stays exact on the evolved state (drift)
    n, nE, nD, nnz, Hok = p69a_check_dh(prob, integ.state, geom; periodic, step = 1)   # every copy
    @test n >= 40 && nE == n && nD == n && Hok
end

const P69A_DH_ROWS = [[(g, p, Float64) for ((g, p), _) in P69A_GEOMS]; [(g, false, Float32) for g in (:square, :hex, :cubic)]]

@testset "P6.9a: ΔH = brute-force difference, fresh states ($geom, $(p69a_bc(periodic)), $T)" for (geom, periodic, T) in P69A_DH_ROWS
    M = p69a_model("P69aCell", geom, periodic)
    dims = P69A_ENUM_DIMS[geom]
    tol = T === Float64 ? 0.0 : 1.0e-2
    tot = Int[0, 0, 0, 0]
    allH = true
    for seed in 1:2
        σ = p69a_random_σ(dims, 3, 30 + seed)
        prob = PottsProblem(M(; name = :dh), [ownership => σ, kind => P69A_KINDS], (0, 1); T)
        n, nE, nD, nnz, Hok = p69a_check_dh(prob, prob.u0, geom; periodic, step = 2, tol)
        tot .+= (n, nE, nD, nnz)
        allH &= Hok
    end
    n, nE, nD, nnz = tot
    @test n >= 60
    @test nnz >= n ÷ 4
    @test nE == n
    @test nD == n
    @test allH
end

@testset "P6.9a: Bauer 2009 / Jafari continuity: a reconnecting copy is rewarded by −α" begin
    # A is a bar with a one-site gap; filling the gap joins its two pieces: ΔH = −300 plus
    # the other terms, which the brute force adds
    σ = zeros(Int32, 10, 10); σ[5, 2:4] .= 1; σ[5, 6:8] .= 1; σ[1, 1] = 2; σ[10, 10] = 3
    prob = PottsProblem(P69aCellSquareClosed(; name = :b), [ownership => σ, kind => P69A_KINDS], (0, 1))
    x, y = (5, 5), (5, 4)
    prop = CorePotts.Proposal(CorePotts.linear_index(prob.lattice, x), CorePotts.linear_index(prob.lattice, y), x, 1, σ[x...], σ[y...])
    σ1 = copy(σ); σ1[x...] = 1
    dE = p69a_energy(σ1, :square; periodic = false) - p69a_energy(σ, :square; periodic = false)
    @test energy_change(prob, prob.u0, prop) == dE
    @test dE <= -300.0 + 1.0                              # the continuity term dominates
end

# ---------------------------------------------------------------------------------------
# Section 7: build errors and the cost of not using it

"""The exception of building `@potts_model` `ex` into a problem (`nothing` if it builds)."""
function p69a_build(ex)
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    try
        M = Core.eval(@__MODULE__, ex)
        Base.invokelatest() do
            PottsProblem(M(; name = :b), [ownership => σ, kind => [:A]], (0, 1))
        end
        return nothing
    catch e
        while e isa LoadError
            e = e.error
        end
        return e
    end
end
const P69A_BUILD_N = Ref(0)
p69a_case(line) = (name = Symbol(:P69aBuild, P69A_BUILD_N[] += 1);
    :(@potts_model $name begin
        @kinds medium A
        @lattice Lattice((10, 10))
        @energy cells => (volume - 9)^2
        $line
        @sweep Metropolis(; temperature = 1.0)
    end))

@testset "P6.9a: surface and build errors" begin
    msg(e) = sprint(showerror, e)
    for line in (:(@constraint connectivity(A; rule = Global())), :(@constraint connectivity(A; rule = Global(; window = 4))),
                 :(@drive connectivity(A; rule = Global(; adjacency = :full), penalty = 3.0)),
                 :(@constraint connected(new; rule = Global()) | (volume[new] == 1)),
                 :(@energy cells(A) => 2.0 * (pieces > 1)), :(@energy cells => largest_piece(; adjacency = :full)),
                 :(@drive copy => pieces(old; adjacency = :full) + largest_piece[new]),
                 :(@observed q(cell) ~ largest_piece))
        @test p69a_build(p69a_case(line)) === nothing
    end
    # the shell fold is unchanged (control: builds on the base)
    @test p69a_build(p69a_case(:(@drive copy => pieces(old, shell(target))))) === nothing
    for line in (:(@energy cells => pieces(; adjacency = :diag)), :(@energy cells => largest_piece(; adjacency = :diag)))
        e = p69a_build(p69a_case(line))
        @test e isa ArgumentError && occursin(":face", msg(e)) && occursin(":full", msg(e))
    end
    for line in (:(@drive copy => largest_piece), :(@drive copy => 1.0 * largest_piece))
        e = p69a_build(p69a_case(line))
        @test e isa ArgumentError && occursin("largest_piece", msg(e))
    end
    # a model without Global has no counter
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(PottsProblem(P69aTwinSquareClosed(; name = :t), [ownership => σ, kind => [:A]], (0, 2)), alg)
        @test hasproperty(sol.stats, :connectivity_deferred) && sol.stats.connectivity_deferred === nothing
    end
end

# ---------------------------------------------------------------------------------------
# Section 8: zero warm allocations; the AllocCheck proof

"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function p69a_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    return [@allocated(step!(integ)) for _ in 1:5]
end

@testset "P6.9a: zero warm allocations ($geom, $(p69a_bc(periodic)))" for ((geom, periodic), (_, _, dims)) in P69A_GEOMS
    σ0 = p69a_random_σ(dims, 3, 23)
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test all(==(0), p69a_warm_allocs(p69a_problem(p69a_model("P69aTwin", geom, periodic), σ0), alg))   # control
        for prefix in ("P69aVeto", "P69aVetoW1", "P69aPen", "P69aCell")
            @test all(==(0), p69a_warm_allocs(p69a_problem(p69a_model(prefix, geom, periodic), σ0), alg))
        end
    end
end

const P69A_HAS_ALLOCCHECK = Base.find_package("AllocCheck") !== nothing
P69A_HAS_ALLOCCHECK && @eval using AllocCheck: check_allocs

@testset "P6.9a: AllocCheck: sequential_mcs! with Global and cell-scope pieces" begin
    @test P69A_HAS_ALLOCCHECK                            # in the PottsModels test environment
    if P69A_HAS_ALLOCCHECK
        for (M, σ0) in ((P69aVetoSquarePeriodic, p69a_random_σ((10, 10), 3, 23)), (P69aCellCubicClosed, p69a_random_σ((6, 6, 6), 3, 23)),
                        (P69aLoop2SquareClosed, p69a_loop((12, 12), 4)))
            prob = PottsProblem(M(; name = :ac), [ownership => σ0, kind => P69A_KINDS[1:maximum(σ0)]], (0, 3))
            integ = init(prob, SequentialCPM(); save_start = false)
            step!(integ)
            args = (integ.state, integ.kf, integ.p, integ.ctx, integ.law, integ.key, 1)
            @test isempty(Base.invokelatest(check_allocs, CorePotts.sequential_mcs!, typeof.(args)))
        end
    end
end

# ---------------------------------------------------------------------------------------
# Section 9: device (Float32)

const P69A_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()

@testset "P6.9a: Global and pieces on the device (CheckerboardCPM, Float32)" begin
    if P69A_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        # the window fixture and its counter
        for W in (2, 3)
            M = getfield(@__MODULE__, p69a_loopname(W, :square, false))
            sol = solve(PottsProblem(M(; name = :l), [ownership => p69a_loop((12, 12), W + 1), kind => [:A]], (0, 10); seed = 3, T = Float32),
                CheckerboardCPM(); backend)
            @test count(==(1), Array(sol.u[end].σ)) < 4W
            shut = p69a_loop((12, 12), W + 2)
            sol = solve(PottsProblem(M(; name = :l), [ownership => shut, kind => [:A]], (0, 10); seed = 3, T = Float32),
                CheckerboardCPM(); backend)
            @test Array(sol.u[end].σ) == shut
            @test sol.stats.connectivity_deferred > 0
        end
        # the invariant and the cell-scope values, square / hex / cubic
        for (geom, periodic) in ((:square, true), (:hex, false), (:cubic, false))
            _, _, dims = Dict(P69A_GEOMS)[(geom, periodic)]
            σ0 = p69a_random_σ(dims, 3, 13)
            prob = p69a_problem(p69a_model("P69aVeto", geom, periodic), σ0; T = Float32, tspan = (0, 10))
            integ = init(prob, CheckerboardCPM(); backend, save_start = false, save_end = false)
            prev = p69a_counts(σ0, geom, :face; periodic)
            up = 0
            for _ in 1:10
                step!(integ)
                now = p69a_counts(Array(integ.u.σ), geom, :face; periodic)
                up += (now[1] > prev[1]) + (now[3] > prev[3])
                prev = now
            end
            @test up == 0
            prob = p69a_problem(p69a_model("P69aCell", geom, periodic), σ0; T = Float32, tspan = (0, 10))
            integ = init(prob, CheckerboardCPM(); backend, save_start = false, save_end = false)
            bad = 0
            for _ in 1:10
                step!(integ)
                face = p69a_cellvals(Array(integ.u.σ), 3, geom, :face; periodic)
                bad += collect(integ[:np])[1:3] != first.(face)
                bad += collect(integ[:lp])[1:3] != last.(face)
            end
            @test bad == 0
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
