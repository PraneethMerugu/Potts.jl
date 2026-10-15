# D-253 (P6.0cd Accept): the index math of the conversion pass and the floods at real site
# indices above 2³¹ − 1 and 2³². The forced-width tests run on small lattices, where a
# reintroduced `% Int32` or `Int32(r)` cannot show; here the kernel bodies run on a 2³²- or
# 2³³-site lattice whose site arrays are sparse (only the touched entries are stored).

using CorePotts: FloodScratch, GlobalExact, GlobalBoard, GlobalSearch, global_keeps, GLOBAL_REFUSED, Proposal

struct SparseSites{T} <: AbstractVector{T}
    n::Int
    d::Dict{Int, T}
    default::T
end
sparse_sites(::Type{T}, n, pairs...) where {T} = SparseSites{T}(n, Dict{Int, T}(pairs...), zero(T))
Base.size(a::SparseSites) = (a.n,)
Base.IndexStyle(::Type{<:SparseSites}) = IndexLinear()
Base.getindex(a::SparseSites, i::Int) = get(a.d, i, a.default)
Base.setindex!(a::SparseSites, v, i::Int) = (a.d[i] = v; a)

@testset "site index math above 2³¹ − 1 and 2³² sites (D-253)" begin
    @testset "@convert: the lowest converted site and `created`" begin
        lat = Lattice((2^16, 2^17))                      # 2³³ sites, no mask
        n = nsites(lat)
        lo, i1, i2 = 10, 2^31 + 10, 2^32 + 10              # i2 ≡ lo (mod 2³²): an Int32 index wraps onto it
        # cell 1 is entity 1, converting into slot 2, allocated this pass (`new`)
        function pass(sites)
            st = (; σ = sparse_sites(Int32, n, (i => Int32(1) for i in sites)...))
            sc = (; src = Int32[1, 0], to = Int32[2, 0], from = Int32[1, 0], new = Int32[1, 0], n = Int32[0, 0],
                first = fill(typemax(Int64), 2), flag = zeros(Int64, 4), site = sparse_sites(Int32, n))
            ctx = (; lattice = lat)
            for i in sites
                CorePotts._cv_decide_body!(i, (st, p, ctx, key, mcs, i, c, t) -> true, st, nothing, ctx, nothing, 0, sc, Int32(0))
            end
            created = Int[]
            w!(st, p, ctx, key, mcs, i, f, t, c) = (c && push!(created, i); nothing)
            for i in sites
                CorePotts._cv_writes_body!(i, w!, st, nothing, ctx, nothing, 0, sc)
            end
            return sc.first[1], created, sc.flag[CorePotts._FLAG_CONVERTED]
        end
        @test pass([i2, i1]) == (i1, [i1], 2)            # the lowest is exact above 2³¹ − 1
        @test pass([i2, lo]) == (lo, [lo], 2)            # one `created`, not also at the wrapped i2
        @test pass([i1, i2, lo]) == (lo, [lo], 3)
    end

    @testset "floods: the exact flood and the window's search" begin
        lat = Lattice((2^16, 2^16); boundary = Closed())  # 2³² sites
        n = nsites(lat)
        y = 40_000                                        # sites ≈ 2.6·10⁹ > 2³¹ − 1
        a, b, c = (CorePotts.linear_index(lat, (x, y)) for x in 100:102)
        @test a > typemax(Int32)
        σ = sparse_sites(Int32, n, a => Int32(1), b => Int32(1), c => Int32(1))
        scratch(T) = FloodScratch(sparse_sites(UInt32, n), sparse_sites(T, n), UInt32[0], nothing)
        # the exact flood reaches the three sites; with an Int32 stack it cannot store them
        for (T, ok) in ((Int64, true), (Int32, false))
            fl = scratch(T)
            S = CorePotts._stamps!(fl, UInt32(2))
            fl.mark[a] = S
            flood() = CorePotts._flood!(σ, lat, fl, a, Int32(1), 0, S, Val(false), 0, 0)[1]
            ok ? (@test flood() == 3) : (@test_throws InexactError flood())   # negative control
        end
        # removing the middle site splits the cell: refused, exactly and in the window
        prop = Proposal(b, CorePotts.linear_index(lat, (101, y + 1)), (101, y), 1, Int32(1), Int32(0))
        cap = Val(CorePotts._box_size(lat, 2))
        for mode in (GlobalExact(), GlobalBoard())
            ctx = (; lattice = lat, flood = scratch(Int64), global_mode = mode)
            @test global_keeps(σ, ctx, prop, Val(false), Val(2), cap, GlobalSearch()) == GLOBAL_REFUSED
        end
    end
end
