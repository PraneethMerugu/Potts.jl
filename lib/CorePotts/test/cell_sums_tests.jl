# A float `CellReduce` sum is an exact Int64 fixed-point sum, so it does not depend on the
# order of the sites (thread count, backend). The order test permutes the lattice sites with their values:
# a cell sum reads only `σ[i]` and `v[i]`, so any permutation is the same sum in another order.
# Negative controls: the float-atomic path (`CorePotts._FLOAT_ATOMICS`, the code before
# integer cell sums) gives different last bits on the permuted lattice; the old max/min CAS loop (copied below)
# loses a NaN in one order.

@testsetup module CP_cell_sums
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include("shared/cell_sums.jl")
include("shared/export_all.jl")
end

@testitem "float cell sums are exact fixed-point sums" setup = [CP_cell_sums] tags = [:corepotts, :cell_sums] begin
@testset "float cell sums are exact fixed-point sums" begin
    dims = (96, 80)
    σ = cs_owners(dims)
    n = Int(maximum(σ))
    v = cs_values(dims)

    @testset "order: a permutation of the sites gives the same bits ($T)" for T in (Float64, Float32, Float16)
        vT = T.(clamp.(v, -6e4, 6e4))
        a = cs_run!(cs_state(σ, vT, n; T))
        for seed in 1:3
            P = randperm(Random.Xoshiro(seed), length(σ))
            b = cs_run!(cs_state(reshape(σ[P], dims), reshape(vT[P], dims), n; T))
            @test a == b
        end
        # the run length of the host passes (sites per work item) changes no bit
        for r in (1, 7, 4096)
            CorePotts._CR_RUN_HOST[] = r
            try
                @test cs_run!(cs_state(σ, vT, n; T)) == a
            finally
                CorePotts._CR_RUN_HOST[] = 256
            end
        end
        # negative control: the float atomics of the code before integer cell sums depend on the order
        T === Float16 && continue                                        # (a Float16 sum overflows its column)
        CorePotts._FLOAT_ATOMICS[] = true
        try
            a0 = cs_run!(cs_state(σ, vT, n; T))
            P = randperm(Random.Xoshiro(1), length(σ))
            b0 = cs_run!(cs_state(reshape(σ[P], dims), reshape(vT[P], dims), n; T))
            @test a0 != b0
        finally
            CorePotts._FLOAT_ATOMICS[] = false
        end
    end

    @testset "accuracy: within the fixed-point resolution of the exact sum" begin
        a = cs_run!(cs_state(σ, v, n))
        L = CorePotts._reduce_bits(length(σ))
        @test L == 13                                                    # 7680 sites ≤ 2^13
        for c in 1:n
            owned = findall(==(c), σ)
            isempty(owned) && continue
            exact = sum(big.(v[owned]))
            m = maximum(abs, v[owned])
            # half a unit (≤ m·N·2^−62, here 2^(13 − 62) of m) per term, then one rounding to Float64
            bound = length(owned) * m * 2.0^(L - 62) + eps(abs(Float64(exact)))
            @test abs(a[c] - exact) <= bound
            # the cell average (`integral(v) / volume`) against the exact average
            avg = exact / length(owned)
            @test abs(a[c] / length(owned) - avg) <= bound / length(owned) + eps(abs(Float64(avg)))
        end
        @test all(iszero, a[setdiff(1:n, unique(σ))])                    # empty slots: the identity
            @test_throws ArgumentError CorePotts._reduce_bits(2^61 + 1)
        @test CorePotts._reduce_bits(2^61) == 61 && CorePotts._reduce_bits(1) == 0 && CorePotts._reduce_bits(5) == 3
    end

    @testset "non-finite values stay visible" begin
        w = copy(v)
        c1, c2, c3, c4 = 1, 2, 3, 4                                      # NaN; +Inf; −Inf; +Inf and −Inf
        w[findfirst(==(c1), σ)] = NaN
        w[findfirst(==(c2), σ)] = Inf
        w[findfirst(==(c3), σ)] = -Inf
        o4 = findall(==(c4), σ); w[o4[1]] = Inf; w[o4[end]] = -Inf
        a = cs_run!(cs_state(σ, w, n))
        @test isnan(a[c1]) && a[c2] == Inf && a[c3] == -Inf && isnan(a[c4])
        @test all(isfinite, a[5:n])                                      # the other cells keep their sums
        @test a[5:n] == cs_run!(cs_state(σ, v, n))[5:n]
        b = cs_run!(cs_state(σ, w, n), CellReduce((:cell, :x), (st, p, ctx, key, mcs, i) -> st.site.v[i]; op = max))
        @test isnan(b[c1]) && b[c2] == Inf && b[c3] < Inf && b[c4] == Inf
    end

    @testset "max/min keep a NaN in every order" begin
        vals = [1.0, NaN, 3.0, -2.0]
        for P in ([1, 2, 3, 4], [4, 3, 2, 1], [2, 1, 4, 3], [3, 2, 1, 4])
            a = [-Inf]
            foreach(k -> CorePotts._atomic!(max, a, 1, vals[k]), P)
            @test isnan(a[1])
            b = [Inf]
            foreach(k -> CorePotts._atomic!(min, b, 1, vals[k]), P)
            @test isnan(b[1])
        end
        x = [-Inf]; foreach(k -> CorePotts._atomic!(max, x, 1, k), [-0.0, 0.0]); y = [-Inf]
        foreach(k -> CorePotts._atomic!(max, y, 1, k), [0.0, -0.0])
        @test x[1] === y[1] === 0.0
        # negative control: the old loop overwrites the NaN with a later value
        old = [-Inf]; foreach(k -> cs_old_max!(old, 1, vals[k]), [1, 2, 3, 4])
        @test !isnan(old[1])
    end

    @testset "the paired 32-bit form (no 64-bit atomics) equals the Int64 form" begin
        for T in (Float64, Float32)
            vT = T.(v)
            a = cs_run!(cs_state(σ, vT, n; T))
            CorePotts._FORCE_PAIRED[] = true
            try
                st = cs_state(σ, vT, n; T)
                @test cs_run!(st) == a
                # the high and low words hold the Int64 sum (negative sums and low-word carries included)
                sc = CorePotts._cr(st)
                @test any(<(0), sc.hi) && all(iszero, sc.acc)
                CorePotts._FORCE_PAIRED[] = false
                st2 = cs_state(σ, vT, n; T); cs_run!(st2)
                @test [CorePotts._cr_acc(sc, c, Val(true)) for c in 1:n] == CorePotts._cr(st2).acc
            finally
                CorePotts._FORCE_PAIRED[] = false
            end
        end
    end

    @testset "a sum beyond its column's number type is ±Inf and warns" begin
        σ2 = zeros(Int32, 4, 4); σ2[1:2, :] .= 1; σ2[3:4, :] .= 2
        v2 = fill(3.0f38, 4, 4); v2[3:4, :] .= 1.0f0
        st = cs_state(σ2, v2, 2; T = Float32)
        a = cs_run!(st)
        @test a[1] == Inf32 && a[2] == 8.0f0                             # the other cell is exact
        w = Array(st.model[REDUCE_STATUS])[1]
        @test w & STATUS_SUM_RANGE != 0 && keys(st.cell)[w >> 8] === :x          # the column's position
        # in a run: the integrator warns at its read points in words, clears the word, continues
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
            phases = Phases(after_mcs = (CS_SUM,)))
        prob = PottsProblem(f, cs_state(σ2, v2, 2; T = Float32), Lattice((4, 4)), (0, 2), gg_params())
        msg = r"the cell sum `x` \(`integral`, `CellReduce`\) exceeded floatmax\(Float32\) = 3.4028235e38 by MCS 2 and is stored as ±Inf; build the problem in Float64 \(`PottsProblem\(…; T = Float64\)`\) or rescale the summed expression"
            sol = @test_logs (:warn, msg) solve(prob, SequentialCPM(); save_start = false, save_everystep = false)
        @test sol.retcode == ReturnCode.Success && sol.u[end].cell.x[1] == Inf32
        # a finite run does not warn
        ok = PottsProblem(f, cs_state(σ2, fill(1.0f0, 4, 4), 2; T = Float32), Lattice((4, 4)), (0, 2), gg_params())
        @test_logs solve(ok, SequentialCPM())
    end

    @testset "other number types; the missing scratch; backends without 64-bit atomics" begin
        # a BigFloat column: summed in site order on the host
        st = initial_state(σ, ones(Int32, n); site = (; v = big.(v)), cell = (; x = zeros(BigFloat, n)))
        a = cs_run!(st)
        @test all(c -> a[c] == sum(big.(v)[σ .== c]; init = big(0.0)), 1:n)
        # integer columns keep their atomics (no scratch needed)
        st = initial_state(σ, ones(Int32, n); site = (; v), cell = (; x = zeros(Int64, n)))
        @test cs_run!(st, CellReduce((:cell, :x), (st, p, ctx, key, mcs, i) -> 1)) == [count(==(c), σ) for c in 1:n]
        # a float column without the scratch: refused at the first sum, with the route
        st = initial_state(σ, ones(Int32, n); site = (; v), cell = (; x = zeros(n)))
            @test_throws ArgumentError cs_run!(st)
        # a backend without 64-bit atomics (Metal, which cannot be tested here) takes the paired
        # form; a BigFloat sum is refused on any device
        nob = CS_NoAtomic64()
        @test CorePotts._paired(nob) && !CorePotts._paired(CPU())
        st = initial_state(σ, ones(Int32, n); site = (; v = big.(v)), cell = (; x = zeros(BigFloat, n)))
            @test_throws ArgumentError cs_run!(st; backend = nob)
        # the scratch is not copied to a daughter, and is grown with the state
        @test CorePotts._is_scratch_column(Symbol("#cr_acc")) && !CorePotts._is_scratch_column(:x)
        g = with_capacity(cs_state(σ, v, n), n + 5)
        @test length(CorePotts._cr(g).acc) == n + 5 && cs_run!(g)[1:n] == cs_run!(cs_state(σ, v, n))
    end

    # The contact table of a weighted relation is a sum of integer weight units
    # (`_units_for`): every measure is the exact sum of the quantized weights, rounded once,
    # whatever the order (the lattice is above `HOST_GRAIN` sites: threaded). Negative control:
    # the float atomics (in site order here) miss the once-rounded sum somewhere.
    @testset "weighted contact tables are exact sums (ContactPhase)" begin
        dims = (192, 192)
        @test prod(dims) > CorePotts.Exec.HOST_GRAIN
        σc = zeros(Int32, dims)
        k = 0
        for j in 1:40:161, i in 1:40:161
            k += 1
            σc[i:(i + 31), j:(j + 31)] .= k                      # 32 × 32 cells, medium between,
            σc[(i + 32):min(i + 39, dims[1]), j:(j + 15)] .= k   # each touching the next one down
        end
        lat = Lattice(dims)
        rel = relation(Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o))), lat)
        ctx = (; lattice = lat, touch = rel)
        table(ctl) = begin
            st = initial_state(σc, ones(Int32, k); cell = empty_contacts(12, k; T = Float32))
            CorePotts._FLOAT_ATOMICS[] = ctl
            try
                @test ContactPhase(:touch)(st, nothing, ctx, RNGKey(0), 0, CPU()) == (ctl ? 5 : 6)
            finally
                CorePotts._FLOAT_ATOMICS[] = false
            end
            @test all(iszero, st.cell.contact_overflow) && all(iszero, st.cell[Symbol("#ct_acc")])
            st.cell
        end
        u = CorePotts._weight_units(rel, length(σc))
        exact = Dict{Tuple{Int, Int}, Int64}()
        for i in eachindex(σc)
            a = Int(σc[i]); a == 0 && continue
            x = coordinates(lat, i)
            for q in 1:length(rel)
                inside, y = shift(lat, x, rel.offsets[q])
                inside || continue
                b = Int(σc[linear_index(lat, y)])
                b == a || (exact[(a, b)] = get(exact, (a, b), 0) + u.q[q])
            end
        end
        once(a, b) = Float32(ldexp(Float32(get(exact, (a, b), 0)), -u.e))
        t = table(false)
        @test all(((a, b),) -> contact_measure(t, a, b) == once(a, b), keys(exact))
        @test count(((a, b),) -> b != 0, keys(exact)) > 10
        t0 = table(true)
        @test any(((a, b),) -> contact_measure(t0, a, b) != once(a, b), keys(exact))
        # the scratch is not copied to a daughter; a table without it is refused for weights
        @test CorePotts._is_scratch_column(Symbol("#ct_acc"))
        bare = initial_state(σc, ones(Int32, k); cell = (; contact_nbr = zeros(Int32, 12, k),
            contact_measure = zeros(Float32, 12, k), contact_medium = zeros(Float32, k), contact_overflow = zeros(Int32, k)))
            @test_throws ArgumentError ContactPhase(:touch)(bare, nothing, ctx, RNGKey(0), 0, CPU())
    end
end
end
