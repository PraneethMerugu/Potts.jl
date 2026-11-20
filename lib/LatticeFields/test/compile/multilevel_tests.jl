# Multilevel lowering: RESTRICT over children (odd tails, axes of size 1), level +1 reads in the fine
# frame, the refusal of a level that coarsens an axis of size 1, block reductions and gates.
# Oracles are direct loops over the n ÷ 2 convention, independent of the emitter.

@testsetup module LF_compile_multilevel
using Test, LatticeFields
# imports an earlier file made in the old single Main
using Random: Xoshiro
include("../host_runner.jl")
include("../shared/compile_multilevel.jl")
include("../shared/export_all.jl")
end

@testitem "RESTRICT: children with odd tails and size-1 axes" setup = [LF_compile_multilevel] tags = [:latticefields, :compile] begin
@testset "RESTRICT: children with odd tails and size-1 axes" begin
    for dims in ((5,), (7, 4), (5, 3, 1), (6, 1, 5), (2, 3, 2))
        u0 = Float32.(rand(Xoshiro(3), 1:9, prod(dims)))
        A = reshape(u0, dims)
        nc = map(d -> d == 1 ? 1 : d ÷ 2, dims)
        want = map(CartesianIndices(nc)) do J
            sum(A[c] +
                2A[CartesianIndex(ntuple(d -> d == 1 ? mod1(c[1] + 1, dims[1]) : c[d], length(dims)))]
            for c in CartesianIndices(ntuple(d -> kids(J[d], dims[d]), length(dims))))
        end
        for got in ml_modes(restrict_case(dims), ("r" => u0,))
            @test reshape(got, nc) == want
        end
    end
    # max over U8 children: the Any fold
    m = UInt8[0, 0, 1, 0, 0, 0, 0]
    for got in ml_modes(restrict_case((7,); op = :max, lane = U8), ("r" => m,))
        @test got == UInt8[0, 1, 0]
    end
end
end

@testitem "level +1 reads: parent of the fine site x + o" setup = [LF_compile_multilevel] tags = [:latticefields, :compile] begin
@testset "level +1 reads: parent of the fine site x + o" begin
    pb = ProgramBuilder(Grid((5,)); periodic = (true,), levels = 2)
    e = field!(pb, "e"; role = :input, levels = [1])
    f = field!(pb, "v"; role = :output)
    kb = kernel(pb)
    store(kb, f, load(kb, e; level = 1, offset = (1,), policy = CLAMP))
    add!(pb, kb, "k")
    for got in ml_modes(pb, ("e" => Float32[10, 20],))
        @test got == Float32[10, 20, 20, 20, 10]          # parents of 2,3,4,5,1
    end
end
end

# `Coarse(k)` fields: an access m > 1 levels away. Before the fix (85794414):
# `legality` refused every case ("an access shifts more than one level").
@testitem "RESTRICT over m > 1 levels, mixed depths, level +m reads, divisibility" setup = [LF_compile_multilevel] tags = [:latticefields, :compile] begin
@testset "RESTRICT over m > 1 levels, mixed depths, level +m reads, divisibility" begin
    for (dims, m) in (((8, 4), 2), ((4, 1, 8), 2), ((16,), 3))
        N = length(dims)
        pb = ProgramBuilder(Grid(dims); levels = m + 1)
        r = field!(pb, "r"; role = :input)
        h = field!(pb, "h"; role = :input, levels = [1])          # one level below the kernel's parent
        v = field!(pb, "v"; role = :output, levels = [m])
        kb = kernel(pb, Space{N}(; level = m))
        # a child's fine value plus the level-1 node holding it (child >> (m − 1) at that level)
        store(kb, v, IR.restrict(load(kb, r; level = -m) + 100 * load(kb, h; level = 1 - m)))
        add!(pb, kb, "rs")
        u0 = Float32.(rand(Xoshiro(7), 1:9, prod(dims)))
        dh = map(d -> d == 1 ? 1 : d ÷ 2, dims)
        h0 = Float32.(rand(Xoshiro(8), 1:9, prod(dims) ÷ prod(dims .÷ dh)))
        A, H = reshape(u0, dims), reshape(h0, dh)
        nc = map(d -> d == 1 ? 1 : d >> m, dims)
        want = map(CartesianIndices(nc)) do J
            sum(A[c] + 100 * H[CartesianIndex(ntuple(d -> dims[d] == 1 ? 1 : (c[d] - 1) ÷ 2 + 1, N))]
                for c in CartesianIndices(ntuple(d -> dims[d] == 1 ? (1:1) : ((J[d] - 1) * 2^m + 1):(J[d] * 2^m), N)))
        end
        for got in ml_modes(pb, ("r" => u0, "h" => h0))
            @test reshape(got, nc) == want
        end
    end
    # level +2 reads: the node of the block that holds the site x + o (CLAMP in the fine frame)
    pb = ProgramBuilder(Grid((8,)); levels = 3)
    e = field!(pb, "e"; role = :input, levels = [2])
    f = field!(pb, "v"; role = :output)
    kb = kernel(pb)
    store(kb, f, load(kb, e; level = 2, offset = (1,), policy = CLAMP))
    add!(pb, kb, "k")
    for got in ml_modes(pb, ("e" => Float32[10, 20],))
        @test got == Float32[10, 10, 10, 20, 20, 20, 20, 20]     # blocks of 2..9, clamped to 8
    end
    # an axis that 2^m does not divide is refused, naming it (the front end refuses first)
    pb = ProgramBuilder(Grid((6, 8)); levels = 3)
    r = field!(pb, "r"; role = :input)
    v = field!(pb, "v"; role = :output, levels = [2])
    kb = kernel(pb, Space{2}(; level = 2))
    store(kb, v, IR.restrict(load(kb, r; level = -2)))
    add!(pb, kb, "rs")
    msg = ml_msg(() -> semantic(program(pb)))
    @test occursin("shifts 2 levels across axis 1 of size 6", msg)
end
end

@testitem "an axis of size 1 is never coarsened; a level that would is refused" setup = [LF_compile_multilevel] tags = [:latticefields, :compile] begin
@testset "an axis of size 1 is never coarsened; a level that would is refused" begin
    @test IR.leveldims(IR.Level(Grid((8, 1)), 3)) == (1, 1)
    @test IR.leveldims(IR.Level(Grid((300, 192)), 7)) == (2, 1)
    pb = ProgramBuilder(Grid((300, 192)); levels = 9)       # 192 >> 8 == 0
    field!(pb, "u")
    @test occursin("never coarsened", ml_msg(() -> semantic(program(pb))))
end
end

@testitem "reductions: 256-site workgroups, halving-tree sums, max; gate with pass-through" setup = [LF_compile_multilevel] tags = [:latticefields, :compile] begin
@testset "reductions: 256-site workgroups, halving-tree sums, max; gate with pass-through" begin
    n = 1000
    pb = ProgramBuilder(Grid((n,)); periodic = (true,))
    r = field!(pb, "r"; role = :input)
    u = field!(pb, "u"; buffers = 2)
    ps, pm, flag = table!(pb, "ps"; oob = :none), table!(pb, "pm"; oob = :none),
    table!(pb, "flag"; oob = :none)
    kb = kernel(pb)
    gate!(kb, eq(table(kb, flag, F32, constant(kb, 1, I32)), 0.0))
    x = load(kb, r)
    store(kb, u, load(kb, u) + 1.0)
    reduce!(kb, :sum, x, ps)
    reduce!(kb, :max, abs(x), pm)
    add!(pb, kb, "red")
    s, sp = build(pb)
    l = only(sp.launches)
    @test l.ndrange == (1024,)
    v = randn(Xoshiro(5), Float32, n)
    for gated in (false, true)
        st = HostStore(s)
        copyto!(current(st, s, "r"), v)
        for (i, t) in enumerate(s.tables)
            st.tables[Int32(i)] = zeros(Float32, t.key == "flag" ? 1 : 4)
        end
        st.tables[Int32(findfirst(t -> t.key == "flag", s.tables))][1] = gated
        run_step!(s, sp, st, ())
        tab(k) = st.tables[Int32(findfirst(t -> t.key == k, s.tables))]

        # oracle: the halving tree over each block of 256 (zero padded)
        pair(xs) = length(xs) == 1 ? xs[1] : pair(xs[1:(end ÷ 2)] .+ xs[(end ÷ 2 + 1):end])
        blocks = [Float32[i <= n ? v[i] : 0.0f0 for i in (256(b - 1) + 1):(256b)]
                  for b in 1:4]
        if gated
            @test all(iszero, tab("ps")) && all(==(-Inf32), tab("pm"))
            @test current(st, s, "u") == zeros(Float32, n)   # pass-through, not stale
        else
            @test tab("ps") == pair.(blocks)
            @test tab("pm") == [maximum(abs, b) for b in blocks]
            @test isapprox(sum(Float64, tab("ps")), sum(Float64, v); rtol = 1e-5)
            @test current(st, s, "u") == ones(Float32, n)
        end
        ps1 = copy(tab("ps"))
        HOST_REVERSE[] = true                         # race check: items backwards
        try
            run_step!(s, sp, st, ())
        finally
            HOST_REVERSE[] = false
        end
        @test tab("ps") == ps1
    end
end
end
