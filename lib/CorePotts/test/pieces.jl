# Whole-cell connectivity (P6.9a, `src/pieces.jl`): ordinary tests (D-048). `recompute_pieces`
# and the per-copy after-values against an independent flood fill; `global_keeps` (exact
# and windowed) and `global_gains` against brute force; the window's three outcomes on a
# loop. The model-level acceptance is PottsModels' frozen `p6_9a_global_connectivity.jl`.

using CorePotts: FloodScratch, GlobalExact, GlobalBoard, GlobalSearch, GlobalLocal,
                 global_keeps, global_gains,
                 pieces_after!, pieces_defer, commit_pieces!, GLOBAL_PASS, GLOBAL_WINDOW,
                 GLOBAL_REFUSED

# (pieces, largest) of the sites where M holds, by an independent flood (Dict-based)
function pieces_brute(M::AbstractArray{Bool}, lat, full::Bool)
    offs = CorePotts._adjacency_offsets(lat, Val(full))
    seen = Set{Int}()
    n = big = 0
    for i in eachindex(M)
        (M[i] && !(i in seen)) || continue
        n += 1
        q = [i]
        push!(seen, i)
        sz = 0
        while !isempty(q)
            s = pop!(q)
            sz += 1
            for o in offs
                ins, y = CorePotts.shift(lat, CorePotts.coordinates(lat, s), o)
                ins || continue
                r = CorePotts.linear_index(lat, y)
                (M[r] && !(r in seen)) || continue
                push!(seen, r)
                push!(q, r)
            end
        end
        big = max(big, sz)
    end
    return n, big
end

random_labels(dims, n, rng) = Int32.(rand(rng, 0:n, dims))

const PIECES_LATTICES = [
    Lattice((7, 6); boundary = Closed()), Lattice((7, 6); boundary = Periodic()),
    Lattice((7, 7); boundary = Closed(), geometry = Hexagonal()), Lattice((5, 4, 4); boundary = Periodic())]

@testset "pieces: recompute and per-copy after-values = flood fill" begin
    rng = Xoshiro(9)
    for lat in PIECES_LATTICES, full in (false, true), trial in 1:6
        σ = random_labels(lat.dims, 3, rng)
        P, L = recompute_pieces(σ, lat, Val(full), 3)
        @test all(c -> (P[c], L[c]) == pieces_brute(σ .== c, lat, full), 1:3)
        V = Int32[count(==(c), σ) for c in 1:3]
        ctx = (; lattice = lat, flood = FloodScratch(CPU(), lat, 1),
            global_mode = GlobalExact())
        bad = 0
        for t in 1:nsites(lat), k in 1:2

            x = CorePotts.coordinates(lat, t)
            ins, y = CorePotts.shift(lat, x, CorePotts.shell_offsets(lat)[mod1(t + k, end)])
            ins || continue
            s = CorePotts.linear_index(lat, y)
            σ[t] == σ[s] && continue
            prop = Proposal(t, s, x, 1, σ[t], σ[s])
            stamp = ctx.flood.stamp[1]
            po, lo, pn, ln = pieces_after!(σ, ctx, prop, P, L, V, Val(full), 1)
            # a copy the checkerboard does not defer needs no flood (the scratch is untouched)
            bad += !pieces_defer(σ, ctx, prop, P, V, Val(full)) &&
                   ctx.flood.stamp[1] != stamp
            σ1 = copy(σ)
            σ1[t] = σ[s]
            for (c, p, l) in ((prop.old, po, lo), (prop.new, pn, ln))
                c == 0 && continue
                bad += (p, l) != pieces_brute(σ1 .== c, lat, full)
            end
            # the stored values commit to the trackers
            P2, L2 = copy(P), copy(L)
            commit_pieces!(P2, L2, prop, ctx, 1)
            bad += prop.old != 0 && (P2[prop.old], L2[prop.old]) != (po, lo)
        end
        @test bad == 0
    end
end

@testset "Global: exact decision = brute force; gains" begin
    rng = Xoshiro(10)
    for lat in PIECES_LATTICES, full in (false, true), trial in 1:4
        σ = random_labels(lat.dims, 2, rng)
        ctx = (; lattice = lat, flood = FloodScratch(CPU(), lat, 0),
            global_mode = GlobalExact())
        n = agree = 0
        for t in 1:nsites(lat)
            σ[t] == 0 && continue
            x = CorePotts.coordinates(lat, t)
            for k in eachindex(CorePotts.shell_offsets(lat))
                ins, y = CorePotts.shift(lat, x, CorePotts.shell_offsets(lat)[k])
                ins || continue
                s = CorePotts.linear_index(lat, y)
                σ[s] == σ[t] && continue
                prop = Proposal(t, s, x, 1, σ[t], σ[s])
                σ1 = copy(σ)
                σ1[t] = σ[s]
                keeps = pieces_brute(σ1 .== σ[t], lat, full)[1] <=
                        pieces_brute(σ .== σ[t], lat, full)[1]
                gains = σ[s] == 0 ||
                        pieces_brute(σ1 .== σ[s], lat, full)[1] <=
                        pieces_brute(σ .== σ[s], lat, full)[1]
                n += 1
                agree += ((global_keeps(
                    σ, ctx, prop, Val(full), Val(nothing), Val(0), GlobalSearch()) ==
                           GLOBAL_PASS) == keeps) &
                         (global_gains(σ, ctx, prop, Val(full)) == gains)
            end
        end
        @test n > 0 && agree == n
    end
end

@testset "Global: the window's three outcomes (loop fixture)" begin
    # a one-wide square loop of side s: removing a site never splits it, but the way round
    # leaves the box of radius W unless s ≤ W + 1
    lat = Lattice((12, 12); boundary = Closed())
    loop(s) = (σ = zeros(Int32, 12, 12);
        for i in 4:(3 + s), j in 4:(3 + s)
            (i in (4, 3 + s) || j in (4, 3 + s)) && (σ[i, j] = 1)
        end; σ)
    for W in (2, 3)
        cap = CorePotts._box_size(lat, W)
        ctx = (; lattice = lat, flood = FloodScratch(CPU(), lat, 0),
            global_mode = GlobalBoard())
        for (s, want) in ((W + 1, GLOBAL_PASS), (W + 2, GLOBAL_WINDOW))
            σ = loop(s)
            t = CorePotts.linear_index(lat, (4, 5))           # a side site: its two touches meet round the loop
            prop = Proposal(
                t, CorePotts.linear_index(lat, (3, 5)), (4, 5), 1, Int32(1), Int32(0))
            @test global_keeps(σ, ctx, prop, Val(false), Val(W), Val(cap), GlobalLocal()) ==
                  GLOBAL_WINDOW   # undecided locally
            @test global_keeps(
                σ, ctx, prop, Val(false), Val(W), Val(cap), GlobalSearch()) == want
            # exact: always passes
            @test global_keeps(σ, merge(ctx, (; global_mode = GlobalExact())), prop,
                Val(false), Val(W), Val(cap), GlobalSearch()) ==
                  GLOBAL_PASS
        end
        # a bar's interior site is a true split inside the box: refused, not counted
        σ = zeros(Int32, 12, 12)
        σ[6, 5:7] .= 1
        t = CorePotts.linear_index(lat, (6, 6))
        prop = Proposal(
            t, CorePotts.linear_index(lat, (5, 6)), (6, 6), 1, Int32(1), Int32(0))
        @test global_keeps(σ, ctx, prop, Val(false), Val(W), Val(cap), GlobalSearch()) ==
              GLOBAL_REFUSED
    end
end
