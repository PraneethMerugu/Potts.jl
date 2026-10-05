# Drives, biases and local connectivity (ROADMAP M2.5, M2.6).

"""Independent check: the owner's sites in the Moore neighbourhood of x (minus x) form one
face-connected component (flood fill over explicit coordinates); none at all is not one."""
function brute_local(σ, lat::Lattice{N}, x, a) where {N}
    nb = [o for o in Iterators.product(ntuple(_ -> -1:1, N)...) if any(!=(0), o)]
    own = Set{NTuple{N, Int}}()
    for o in nb
        inside, y = shift(lat, x, Int32.(o))
        inside && σ[linear_index(lat, y)] == a && push!(own, o)
    end
    isempty(own) && return false
    seen = Set([first(own)]); stack = [first(own)]
    while !isempty(stack)
        o = pop!(stack)
        for d in 1:N, s in (-1, 1)
            q = ntuple(k -> k == d ? o[k] + s : o[k], N)
            (q in own && !(q in seen)) && (push!(seen, q); push!(stack, q))
        end
    end
    return length(seen) == length(own)
end

"""Number of face-connected components of cell c (global)."""
function components(σ, lat::Lattice{N}, c) where {N}
    sites = Set(i for i in 1:nsites(lat) if σ[i] == c)
    n = 0
    vn = relation(VonNeumann(1), lat)
    while !isempty(sites)
        n += 1
        stack = [pop!(sites)]
        while !isempty(stack)
            i = pop!(stack)
            for off in vn.offsets
                inside, y = shift(lat, coordinates(lat, i), off)
                j = linear_index(lat, y)
                (inside && j in sites) && (delete!(sites, j); push!(stack, j))
            end
        end
    end
    return n
end

# A custom `track` (CPMFunction's hook): the effective ΔH, bias included.
struct EffectiveTrack end
(::EffectiveTrack)(st, p, prop, ctx, dH) = dH - p.T * p.b * (prop.new == 0 ? -1.0 : 1.0)
CorePotts.track_eltype(::EffectiveTrack) = Float64
# a custom track without `track_eltype`: fine sequentially, a clear error on the checkerboard
struct UntypedTrack end
(::UntypedTrack)(st, p, prop, ctx, dH) = dH

@testset "drives and connectivity" begin
    @testset "proposal predicates and chemotaxis" begin
        p1 = Proposal(3, 4, (3, 1), 1, Int32(0), Int32(2))
        p2 = Proposal(3, 4, (3, 1), 1, Int32(2), Int32(0))
        @test is_extension(p1) && !is_retraction(p1)
        @test is_retraction(p2) && !is_extension(p2)
        c = [0.0, 0.0, 5.0, 2.0]
        @test chemotaxis_delta(c, p1, 2.0) == -2.0 * (5.0 - 2.0)   # up-gradient is favoured
        @test chemotaxis_delta(c, p1, 2.0; response = saturating(1.0)) ≈ -2.0 * (5 / 6 - 2 / 3)
        @test chemotaxis_delta(c, p1, 2.0; response = saturating_linear(0.5)) ≈ -2.0 * (5 / 3.5 - 2 / 2)
    end

    @testset "neighbourhood means" begin
        lat = Lattice((5, 5))
        σ = zeros(Int32, 5, 5); σ[2:4, 2:4] .= 1; σ[3, 4] = 2
        x = zeros(5, 5); x[2:4, 2:4] .= 4.0; x[3, 3] = 1.0
        ctx = (; lattice = lat)
        rel = relation(Moore(1), lat)
        centre = linear_index(lat, (3, 3))
        vals = [x[i, j] for i in 2:4, j in 2:4 if σ[i, j] == 1]       # owner-filtered
        @test neighborhood_mean(x, σ, ctx, centre, 1; relation = rel) ≈ exp(sum(log, vals) / length(vals))
        @test neighborhood_mean(x, σ, ctx, centre, 1; relation = rel, fold = ArithmeticMean()) ≈ sum(vals) / length(vals)
        @test neighborhood_mean(x, σ, ctx, centre, 1; relation = rel, fold = Log1pGeometricMean()) ≈
              expm1(sum(log1p, vals) / length(vals))
        x[2, 2] = 0.0
        @test neighborhood_mean(x, σ, ctx, centre, 1; relation = rel) == 0.0      # a zero kills the GM
        @test neighborhood_mean(x, σ, ctx, centre, 0; relation = rel) == 0.0      # the medium's mean is zero
        x[2, 2] = -3.0                                                   # log1p fold clips at zero
        @test neighborhood_mean(x, σ, ctx, centre, 1; relation = rel, fold = Log1pGeometricMean()) ≈
              expm1(sum(log1p ∘ (v -> max(v, 0.0)), [x[i, j] for i in 2:4, j in 2:4 if σ[i, j] == 1]) / length(vals))
    end

    @testset "locally_connected equals a flood fill ($(N)-D)" for N in (2, 3)
        lat = Lattice(ntuple(_ -> 7, N); boundary = N == 2 ? Closed() : Periodic())
        rng = Random.Xoshiro(3)
        agree = 0
        trials = Ref(0)
        for trial in 1:3000
            σ = Int32.(rand(rng, 0:2, lat.dims))
            x = ntuple(_ -> rand(rng, 1:7), N)
            t = linear_index(lat, x)
            σ[t] == 0 && continue
            prop = Proposal(t, t, x, 1, σ[t], Int32(0))
            trials[] += 1
            agree += locally_connected(σ, (; lattice = lat), prop) == brute_local(σ, lat, x, σ[t])
        end
        @test agree == trials[]
    end

    @testset "ring arcs and ring cells" begin
        lat = Lattice((5, 5); boundary = Closed())
        ctx = (; lattice = lat)
        σ = zeros(Int32, 5, 5)
        σ[2, 2:4] .= 1; σ[3, 3] = 1                     # one arc above the target (3,3)
        prop = Proposal(linear_index(lat, (3, 3)), 0, (3, 3), 1, Int32(1), Int32(0))
        @test ring_arcs(σ, ctx, prop) == 1 && ring_cells(σ, ctx, prop) == 1
        @test local_components(σ, ctx, prop) == 1
        σ[4, 3] = 1                                      # a second arc below: split
        @test ring_arcs(σ, ctx, prop) == 2 && local_components(σ, ctx, prop) == 2
        σ[3, 2] = 2                                      # a second cell on the ring
        @test ring_cells(σ, ctx, prop) == 2
        edge = Proposal(linear_index(lat, (1, 3)), 0, (1, 3), 1, Int32(1), Int32(0))
        σ[1, 3] = 1
        @test ring_arcs(σ, ctx, edge) == 1               # out-of-domain ring sites are not the cell
        # ring of (1,3): 3 out of domain, (1,2)=0 (2,2)=1 (2,3)=1 (2,4)=1 (1,4)=0
        @test ring_medium(σ, ctx, edge) == 2 && ring_cells(σ, ctx, edge) == 1
        # ring of (3,3): (2,2:4)=1 (3,4)=0 (4,4)=0 (4,3)=1 (4,2)=0 (3,2)=2
        @test ring_medium(σ, ctx, prop) == 3
        corner = Proposal(linear_index(lat, (1, 1)), 0, (1, 1), 1, Int32(0), Int32(0))
        @test ring_medium(σ, ctx, corner) == 2           # 5 of 8 ring sites out of domain, (2,2) is 1
        latP = Lattice((5, 5))                           # periodic: the ring wraps onto medium
        @test ring_medium(σ, (; lattice = latP), edge) == 5
        medium = Proposal(linear_index(lat, (5, 5)), 0, (5, 5), 1, Int32(0), Int32(1))
        @test ring_arcs(σ, ctx, medium) == 0 && local_components(σ, ctx, medium) == 0
    end

    @testset "local_components counts flood-fill pieces ($(N)-D)" for N in (2, 3)
        lat = Lattice(ntuple(_ -> 7, N); boundary = Closed())
        rng = Random.Xoshiro(5)
        for _ in 1:500
            σ = Int32.(rand(rng, 0:1, lat.dims))
            x = ntuple(_ -> 4, N)
            σ[x...] = 1
            prop = Proposal(linear_index(lat, x), 1, x, 1, Int32(1), Int32(0))
            offs = [o for o in Iterators.product(ntuple(_ -> -1:1, N)...) if any(!iszero, o) && σ[(x .+ o)...] == 1]
            comps = 0; left = Set(offs)
            while !isempty(left)
                comps += 1; front = [pop!(left)]
                while !isempty(front)
                    a = pop!(front)
                    for b in collect(left)
                        sum(abs.(a .- b)) == 1 && (delete!(left, b); push!(front, b))
                    end
                end
            end
            @test local_components(σ, (; lattice = lat), prop) == comps
        end
    end

    @testset "local connectivity keeps every cell connected ($(length(dims))-D)" for dims in (
            (40, 40), (14, 14, 14))
        σ, kinds = blocks(dims, length(dims) == 2 ? 6 : 4)
        lat = Lattice(dims)
        connected(st, p, prop, ctx) = locally_connected(st.σ, ctx, prop)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = connected)
        hot = merge(gg_params(), (; T = 40.0, V0 = length(dims) == 2 ? 36.0 : 64.0))
        for alg in (SequentialCPM(), CheckerboardCPM())
            u = solve(PottsProblem(f, initial_state(σ, kinds), lat, (0, 30), hot), alg).u[end]
            @test u.σ != σ
            @test all(c -> u.cell.volume[c] == 0 || components(u.σ, lat, c) == 1, eachindex(kinds))
        end
        # without the constraint, hot cells fragment
        f0 = CPMFunction(gg_delta_H; temperature = gg_temperature)
        u0 = solve(PottsProblem(f0, initial_state(σ, kinds), lat, (0, 30), hot), SequentialCPM()).u[end]
        @test any(c -> components(u0.σ, lat, c) > 1, eachindex(kinds))
    end

    @testset "forbid extinction" begin
        σ = zeros(Int32, 12, 12); σ[2, 2] = 1; σ[6:8, 6:8] .= 2
        lat = Lattice((12, 12))
        keep(st, p, prop, ctx) = forbid_extinction(st.cell.volume, prop)
        shrink(st, p, prop, ctx) = volume_delta(st.cell.volume, prop, (v, c) -> 5.0 * v)   # favours loss
        for (f, alive) in ((CPMFunction(shrink; temperature = gg_temperature, constraint = keep), true),
                (CPMFunction(shrink; temperature = gg_temperature), false))
            u = solve(PottsProblem(f, initial_state(σ, [1, 1]), lat, (0, 40), gg_params()),
                SequentialCPM()).u[end]
            @test all(>(0), u.cell.volume) == alive
        end
    end

    @testset "bias adds to log α exactly like −T·bias in ΔH" begin
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        b(st, p, prop, ctx) = p.b * (prop.new == 0 ? -1.0 : 1.0)
        dH(st, p, prop, ctx) = gg_delta_H(st, p, prop, ctx) - gg_temperature(st, p, prop, ctx) * b(st, p, prop, ctx)
        pb = merge(gg_params(), (; b = 0.3))
        fb = CPMFunction(gg_delta_H; temperature = gg_temperature, bias = b)
        fe = CPMFunction(dH; temperature = gg_temperature)
        for alg in (SequentialCPM(), CheckerboardCPM())
            ub = solve(PottsProblem(fb, initial_state(σ, kinds), lat, (0, 10), pb), alg).u[end]
            ue = solve(PottsProblem(fe, initial_state(σ, kinds), lat, (0, 10), pb), alg).u[end]
            @test ub.σ == ue.σ
        end
    end

    @testset "3D shell values against a brute-force shell ($(periodic ? "Periodic" : "Closed"))" for periodic in (true, false)
        lat = Lattice((6, 5, 7); boundary = periodic ? Periodic() : Closed())
        ctx = (; lattice = lat)
        shell = [o for o in Iterators.product(-1:1, -1:1, -1:1) if o != (0, 0, 0)]
        rng = Random.Xoshiro(11)
        seen = Set{Int}()
        n = 0
        for _ in 1:400
            σ = Int32.(rand(rng, 0:3, lat.dims))
            x = (rand(rng, 1:6), rand(rng, 1:5), rand(rng, 1:7))
            t = linear_index(lat, x)
            prop = Proposal(t, t, x, 1, σ[t], Int32(0))
            own = Int[]; mine = NTuple{3, Int}[]
            for o in shell
                inside, y = shift(lat, x, Int32.(o))
                inside || continue
                c = Int(σ[linear_index(lat, y)])
                push!(own, c)
                (σ[t] != 0 && c == σ[t]) && push!(mine, o)
            end
            pieces = 0; left = Set(mine)                 # BFS over face-adjacent shell sites
            while !isempty(left)
                pieces += 1; front = [pop!(left)]
                while !isempty(front)
                    a = pop!(front)
                    for b in collect(left)
                        sum(abs.(a .- b)) == 1 && (delete!(left, b); push!(front, b))
                    end
                end
            end
            @test ring_arcs(σ, ctx, prop) == pieces == local_components(σ, ctx, prop)
            @test ring_cells(σ, ctx, prop) == length(unique(filter(>(0), own)))
            @test ring_medium(σ, ctx, prop) == count(==(0), own)
            push!(seen, pieces); n += 1
        end
        @test length(seen) >= 4                           # several piece counts occur
        # the shell is 26 sites: a closed corner sees 7, a periodic one all 26
        σ = zeros(Int32, lat.dims)
        corner = Proposal(1, 1, (1, 1, 1), 1, Int32(0), Int32(0))
        @test ring_medium(σ, ctx, corner) == (periodic ? 26 : 7)
    end

    @testset "track: Σ accepted ΔH = H(end) − H(start) ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 15), gg_params())
        b(st, p, prop, ctx) = p.b * (prop.new == 0 ? -1.0 : 1.0)
        pb = merge(gg_params(), (; b = 0.4))
        on = CPMFunction(gg_delta_H; temperature = gg_temperature, bias = b, track = CorePotts.TrackDeltaH{Float64}())
        off = CPMFunction(gg_delta_H; temperature = gg_temperature, bias = b)
        a = solve(PottsProblem(off, initial_state(σ, kinds), lat, (0, 15), pb), alg)
        sol = solve(PottsProblem(on, initial_state(σ, kinds), lat, (0, 15), pb), alg)
        u0, u = sol.u[1], sol.u[end]
        H(u) = total_H(u, lat, prob.contact, gg_params())
        # the bias is not part of ΔH: integer energies, so the sum is exact
        @test sol.stats.accepted_ΔH == H(u) - H(u0)
        @test abs(H(u) - H(u0)) > 100                      # non-vacuous
        @test a.stats.accepted_ΔH === nothing
        @test a.u[end].σ == u.σ && a.stats.accepted == sol.stats.accepted   # nothing else changes
        # negative control: a track of the effective ΔH (bias included) misses the oracle
        eff = CPMFunction(gg_delta_H; temperature = gg_temperature, bias = b, track = EffectiveTrack())
        se = solve(PottsProblem(eff, initial_state(σ, kinds), lat, (0, 15), pb), alg)
        @test se.u[end].σ == u.σ
        @test abs(se.stats.accepted_ΔH - (H(u) - H(u0))) > 1
        # warm steps allocate nothing, tracked or not (the checkerboard reduces only at read points)
        for f in (off, on)
            integ = init(PottsProblem(f, initial_state(σ, kinds), lat, (0, 15), pb), alg; save_start = false)
            step!(integ); step!(integ)
            @test minimum(_ -> @allocated(step!(integ)), 1:3) == 0
        end
        # a custom track: sums on both algorithms (here the effective one, `track_eltype`
        # given); without `track_eltype` only the checkerboard refuses, naming it
        @test se.stats.accepted_ΔH isa Float64
        un = PottsProblem(CPMFunction(gg_delta_H; temperature = gg_temperature, bias = b, track = UntypedTrack()),
            initial_state(σ, kinds), lat, (0, 15), pb)
        if alg isa SequentialCPM
            @test solve(un, alg).stats.accepted_ΔH == sol.stats.accepted_ΔH
        else
            e = try
                solve(un, alg); nothing
            catch err
                err
            end
            @test e isa ArgumentError && occursin("track_eltype", sprint(showerror, e))
        end
        # a checkpoint continues only into an equally tracked run (hand-written: fingerprint 0
        # either way), in both directions
        pon = PottsProblem(on, initial_state(σ, kinds), lat, (0, 15), pb)
        poff = PottsProblem(off, initial_state(σ, kinds), lat, (0, 15), pb)
        @test pon.f.fingerprint == poff.f.fingerprint
        for (from, into) in ((poff, pon), (pon, poff))
            i = init(from, alg); step!(i)
            ck = checkpoint(i)
            e = try
                init(into, alg; checkpoint = ck); nothing
            catch err
                err
            end
            @test e isa ArgumentError && occursin("tracking", sprint(showerror, e))
        end
        i = init(pon, alg); step!(i); step!(i)                  # control: the same track continues
        @test solve!(init(pon, alg; checkpoint = checkpoint(i))).stats.accepted_ΔH == sol.stats.accepted_ΔH
        # merge adds; `nothing` wins
        @test merge(sol.stats, sol.stats).accepted_ΔH == 2 * sol.stats.accepted_ΔH
        @test merge(sol.stats, a.stats).accepted_ΔH === nothing
    end
end
