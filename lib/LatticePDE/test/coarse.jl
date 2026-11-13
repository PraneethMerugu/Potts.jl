# F3-16 (F3 design §3.9, FE-08): `[lattice_level = Coarse(k)]` in the IR and LatticePDE. A
# coarse field lives on level log2(k) of the program's hierarchy: its rate, conditions, masks,
# operator (`jac:`) and residual kernels run there with the spacing `k h`, and its fine reads
# (the inputs, an irregular domain) are folded over each node's block (every fine read, an integer
# input too, by the mean of the part of the term that reads it; the domain by Majority; review r1
# M2, F4-15). A field with a mask whose predicate reads fine fields blends (F4-15b): a node is
# masked when its whole block is, and elsewhere its equation folds over the block's free children
# (the node holds the value of its free part). The oracle is the hand-coarsened problem: the same
# system discretized on the coarse grid, with its inputs folded by hand (a kind expression as the
# real input of its mean over the free children, the mask's kind only on whole blocks); the two
# agree to rounding under every algorithm. Base 85794414 (~/lpwork/f3b6-nc-lp.log): `Coarse` is not defined, and
# `lattice_level` was refused ("does not lower"), so every testset errors.
using LatticeFields.IR: print_program
using LinearAlgebra: I
using Random: Xoshiro, randperm

const CK = 4
const CDIMS = (16, 16)
cdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
cmsg(f) = try
    f(); ""
catch err
    err isa ArgumentError ? err.msg : sprint(showerror, err)
end
# a fine kind map whose every 4×4 block has a kind on 10 of its 16 sites (a strict majority),
# the others drawn from the remaining kinds: the Majority fold of `q == k` is the block's kind
function ckinds(seed; dims = CDIMS, k = CK)
    rng = Xoshiro(seed)
    Q = zeros(Int32, dims)
    Qc = Int32[rand(rng, 0:3) for _ in 1:(dims[1] ÷ k), _ in 1:(dims[2] ÷ k)]
    for J in CartesianIndices(Qc)
        sites = [CartesianIndex((J[1] - 1) * k + i, (J[2] - 1) * k + j) for i in 1:k for j in 1:k]
        own = randperm(rng, k^2)
        for (n, s) in enumerate(sites)
            Q[s] = own[n] <= 10 ? Qc[J] : rand(rng, setdiff(0:3, Qc[J]))
        end
    end
    return Q, Qc
end
# the block mean of a fine array (the children in the IR's order: axis 1 fastest)
function cmean(A, k = CK)
    nc = size(A) .÷ k
    return [sum(A[(I[1] - 1) * k + i, (I[2] - 1) * k + j] for j in 1:k for i in 1:k) / k^2 for I in CartesianIndices(nc)]
end
# the mean of a fine array over each block's free children (F4-15b: the children where `held` is
# false; in the IR's order, so a block with no held child gives `cmean`), over every child of a
# block no child of which is free
function cfree(A, held, k = CK)
    nc = size(A) .÷ k
    return map(CartesianIndices(nc)) do I
        ch = [CartesianIndex((I[1] - 1) * k + i, (I[2] - 1) * k + j) for j in 1:k for i in 1:k]
        fr = [c for c in ch if !held[c]]
        isempty(fr) ? sum(A[c] for c in ch) / k^2 : sum(A[c] for c in fr) / length(fr)
    end
end
# the number of free children of each block
cnfree(held, k = CK) = [count(!, held[((I[1] - 1) * k + 1):(I[1] * k), ((I[2] - 1) * k + 1):(I[2] * k)])
                        for I in CartesianIndices(size(held) .÷ k)]
# a fine kind map whose 4×4 blocks hold kind 3 (the mask's) on 16, 0, 1, 2, … 15 of their sites,
# the others drawn from 0:2 (F4-15b): masked, free and blended nodes
function cblendkinds(seed; dims = CDIMS, k = CK)
    rng = Xoshiro(seed)
    Q = zeros(Int32, dims)
    n3 = [16, 0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 12, 14, 15, 16, 0][randperm(rng, 16)]
    for (b, J) in enumerate(CartesianIndices(dims .÷ k))
        own = randperm(rng, k^2)
        for (n, (i, j)) in enumerate((i, j) for j in 1:k for i in 1:k)
            Q[(J[1] - 1) * k + i, (J[2] - 1) * k + j] = own[n] <= n3[b] ? 3 : rand(rng, 0:2)
        end
    end
    return Q
end
# the hand twin's mask input: kind 3 where the whole block is
cwhole(Q, k = CK) = Int32[all(==(3), Q[((I[1] - 1) * k + 1):(I[1] * k), ((I[2] - 1) * k + 1):(I[2] * k)]) ? 3 : 0
                          for I in CartesianIndices(size(Q) .÷ k)]
# the owned problem of `sys` on `dims` with inputs `ins`
# (F4-01: the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
cown(sys, dims; T = Float64, ins = (), kw...) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T, kw...);
    inputs = collect(Pair, ins)))

# One system with the features a coarse field must carry: a face coefficient of the coordinates,
# a decay at a kind, a source at a kind, a moving masked Dirichlet, a Robin face, a Dirichlet face
# whose value reads the coordinates, a face value that reads an input (a field face), a table at
# the kind and a source from a real input. With `hand` (the twin), the kind expressions are real
# inputs that hold their block means: `cf2` for `ismember(q, (2,))`, `cf1` for `q == 1`, `csv` for
# `at(cSv, q + 1)` (F4-15: a kind expression folds by its mean, as a real input does). The names are
# unique to this file: SymbolicUtils interns an applied term `sv(t, x, y)` whatever its function's
# metadata, and unseen_loop.jl's plain `sv` (included before device.jl) drops `input = true`
@parameters cD = 0.02 ckd = 3.0 cs = 0.5 cSv[1:4] = [1.0, 2.0, 5.0, 3.0]
@variables cf1(..) [input = true, bounds = (0, 1)] cf2(..) [input = true, bounds = (0, 1)] csv(..) [input = true, bounds = (1, 5)]
function csys(c, q, g; steady = false, hand = false)
    ce, qe, ge = c(t, x, y), q(t, x, y), g(t, x, y)
    k2, k1, tv = hand ? (cf2(t, x, y), cf1(t, x, y), csv(t, x, y)) : (ismember(qe, (2,)), qe == 1, at(cSv, qe + 1))
    rhs = cD * DivKGrad(:harmonic)(1 + x, ce) - ckd * ce * k2 + cs * k1 + 0.1 * tv + 0.05 * ge
    eqs = steady ? [0 ~ rhs] : [D(ce) ~ rhs]
    bcs = [ce ~ masked(qe == 3, 1.0), 0.5 * c(t, 0, y) - 0.1 * Differential(x)(c(t, 0, y)) ~ 0.3,
        c(t, x, 1) ~ x, c(t, 1, y) ~ g(t, 1, y)]
    steady || push!(bcs, c(0, x, y) ~ x * y)
    dvs = hand ? [ce, qe, ge, cf1(t, x, y), cf2(t, x, y), csv(t, x, y)] : [ce, qe, ge]
    return PDESystem(eqs, bcs, cdom(), [t, x, y], dvs, [cD, ckd, cs, cSv]; name = :cs)
end
# the hand twin's inputs for the fine kind map `Q`: the means of the kind expressions over the
# free children (the mask is `q == 3`; F4-15b)
chand(Q) = [cf1(t, x, y) => cfree(Float64.(Q .== 1), Q .== 3), cf2(t, x, y) => cfree(Float64.(Q .== 2), Q .== 3),
    csv(t, x, y) => cfree(Float64[1.0, 2.0, 5.0, 3.0][Q .+ 1], Q .== 3)]
# equal to rounding: the fold multiplies the block mean last in a product, the twin in its term order
capprox(a, b; rtol = 1e-13) = isapprox(a, b; rtol) || (println("coarse twin: max |Δ| ", maximum(abs, a .- b)); false)
const CQ1, CQ1c = ckinds(11)
const CQ2, CQ2c = ckinds(12)
const CQB1, CQB2 = cblendkinds(13), cblendkinds(14)
# a real input whose block sums are exact (integers): the mean is exact in both problems
const CG = Float64[(3i + 5j) % 7 for i in 1:16, j in 1:16]

# a kind map with ties (review r1 S1): blocks of 8 P + 8 Q (owner P: the smaller kind), 9 P + 7 Q,
# 6 P + 6 Q + 4 medium, 16 P, 8 medium + 8 Q (owner Q: the medium loses a tie), 16 medium,
# 7 Q + 9 N, 8 Q + 8 N, two three-way mixes, and random blocks
function ctiekinds(; seed = 31)
    rng = Xoshiro(seed)
    mixes = [[1 => 8, 2 => 8], [1 => 9, 2 => 7], [1 => 6, 2 => 6, 0 => 4], [1 => 16], [0 => 8, 2 => 8], [0 => 16],
        [2 => 7, 3 => 9], [2 => 8, 3 => 8], [3 => 5, 1 => 5, 0 => 6], [0 => 5, 3 => 5, 2 => 6]]
    Q = zeros(Int32, 16, 16)
    for (b, J) in enumerate(CartesianIndices((4, 4)))
        vals = b <= length(mixes) ? reduce(vcat, [fill(Int32(v), n) for (v, n) in mixes[b]]) : Int32[rand(rng, 0:3) for _ in 1:16]
        vals = vals[randperm(rng, 16)]
        for (n, (i, j)) in enumerate((i, j) for j in 1:4 for i in 1:4)
            Q[(J[1] - 1) * 4 + i, (J[2] - 1) * 4 + j] = vals[n]
        end
    end
    return Q
end
const CQT = ctiekinds()

# the coarse problem and its hand-coarsened twin (a 4×4 grid with the folded inputs)
function ctwins(; steady = false, T = Float64, storage = nothing, backend = nothing)
    nm = Symbol(:ctw, steady ? :s : :r, T, storage === nothing ? "" : storage)
    c = Symbolics.variable(nm; T = SymbolicUtils.FnType{Tuple, Real, Nothing})
    c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(c), LatticePDE.LatticeLevel, Coarse(CK)))
    storage === nothing || (c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(c), LatticePDE.LatticeStorage, storage)))
    ch = Symbolics.variable(Symbol(nm, :h); T = SymbolicUtils.FnType{Tuple, Real, Nothing})
    storage === nothing || (ch = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(ch), LatticePDE.LatticeStorage, storage)))
    q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
    kw = backend === nothing ? (;) : (; backend)
    pc = cown(csys(c, q, g; steady), CDIMS; T, ins = [q(t, x, y) => CQB1, g(t, x, y) => CG], kw...)
    ph = cown(csys(ch, q, g; steady, hand = true), CDIMS .÷ CK; T,
        ins = vcat([q(t, x, y) => cwhole(CQB1), g(t, x, y) => cfree(CG, CQB1 .== 3)], chand(CQB1)), kw...)
    return pc, ph, (c, ch, q, g)
end

@testset "F3-16: Coarse(k) in the IR and LatticePDE" begin
    @testset "Coarse(1) is the lattice itself, bitwise" begin
        # (distinct names per testset: SymbolicUtils interns an applied term `c(t, x, y)`
        # whatever its function's metadata, so a name reused in a session can drop it)
        c1 = first(@variables cone(..) [lattice_level = Coarse(1)])
        c0 = first(@variables cnil(..))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        p1 = cown(csys(c1, q, g), CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => CG])
        p0 = cown(csys(c0, q, g), CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => CG])
        @test replace(sprint(print_program, p1.program), "cone" => "cnil") == sprint(print_program, p0.program)
        for alg in (ExplicitEuler(; dt = 0.01), BackwardEuler(; dt = 0.05))
            s1, s0 = solve(p1, alg), solve(p0, alg)
            @test s1[c1(t, x, y), length(s1.t)] == s0[c0(t, x, y), length(s0.t)]
        end
        @test_throws ArgumentError Coarse(3)
        @test occursin("power of two", cmsg(() -> Coarse(0)))
    end

    @testset "a coarse field equals the hand-coarsened problem under every algorithm" begin
        # (blocks are mixed: the mean is not the majority; blocks are masked, free and blended)
        @test sum(Float64.(CQ1 .== 2)) != 16 * sum(CQ1c .== 2)
        @test sort(unique(16 .- cnfree(CQB1 .== 3))) == [0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 12, 14, 15, 16]
        pc, ph, (c, ch, q, g) = ctwins()
        @test size(pc.u0) == (16,) && length(ph.u0) == 16
        @test pc.u0 == ph.u0                                   # the initial values at the node centers
        # the stability bound reads the coarse spacing: the automatic counts agree
        @test LatticePDE.Problems.substeps(pc, ExplicitEuler(; dt = 0.05)) == LatticePDE.Problems.substeps(ph, ExplicitEuler(; dt = 0.05))
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05), CrankNicolson(; dt = 0.05), BDF2(; dt = 0.05),
                    BackwardEuler(; dt = 0.05, init = :steady), ExplicitEuler(; dt = 0.05, lower = 0.0),
                    BackwardEuler(; dt = 0.05, inner = Multigrid(; cycles = 4)))
            ic, ih = init(pc, alg), init(ph, alg)
            for n in 1:6
                if n == 4                                                       # the mask moves
                    ic[q(t, x, y)] = CQB2; ih[q(t, x, y)] = cwhole(CQB2); ih[g(t, x, y)] = cfree(CG, CQB2 .== 3)
                    foreach(((v, a),) -> ih[v] = a, chand(CQB2))
                end
                step!(ic); step!(ih)
            end
            @test ic.retcode == ih.retcode == SciMLBase.ReturnCode.Success
            @test size(ic[c(t, x, y)]) == (4, 4)
            @test capprox(ic[c(t, x, y)], ih[ch(t, x, y)]; rtol = alg isa ExplicitEuler ? 1e-13 : 1e-10)
            @test LatticePDE.substep_counts(ic) == LatticePDE.substep_counts(ih)
        end
        # the masked nodes hold the masked value, and only where the whole block is kind 3 (F4-15b;
        # 15 of 16 sites leave the node free)
        ic = init(pc, BackwardEuler(; dt = 0.05)); step!(ic)
        whole = cwhole(CQB1) .== 3
        @test count(whole) == 2 && all(ic[c(t, x, y)][whole] .== 1.0) && all(ic[c(t, x, y)][.!whole] .!= 1.0)
    end

    @testset "steady rows, number types and the ODE path on a coarse grid" begin
        pc, ph, (c, ch, _...) = ctwins(; steady = true)
        sc, sh = solve(pc, QuasiSteady(; dt = 0.1)), solve(ph, QuasiSteady(; dt = 0.1))
        @test capprox(sc[c(t, x, y), length(sc.t)], sh[ch(t, x, y), length(sh.t)]; rtol = 1e-10)
        pc, ph, (c, ch, _...) = ctwins(; T = Float32)
        @test eltype(pc.u0) == Float32
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05))
            sc, sh = solve(pc, alg), solve(ph, alg)
            @test capprox(sc[c(t, x, y), length(sc.t)], sh[ch(t, x, y), length(sh.t)]; rtol = 1e-5)
        end
        pc, ph, (c, ch, _...) = ctwins(; storage = Float32)          # a declared storage on the owned path
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05))
            sc, sh = solve(pc, alg), solve(ph, alg)
            @test eltype(sc[c(t, x, y), 1]) == Float32
            @test capprox(sc[c(t, x, y), length(sc.t)], sh[ch(t, x, y), length(sh.t)]; rtol = 1e-5)
        end
        # F3-ghost on the coarse grid: a face coefficient that reads the field takes its ghost value
        # at a Dirichlet face (the coarse ghost, from the coarse spacing)
        cgh = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cghost(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        hgh = first(@variables hghost(..))
        gsys(c) = PDESystem([D(c(t, x, y)) ~ DivKGrad(:harmonic)(0.02 * (1 + c(t, x, y)), c(t, x, y)) - c(t, x, y)],
            [c(0, x, y) ~ x * y, c(t, 0, y) ~ 2.0, 0.5 * c(t, 1, y) + Differential(x)(c(t, 1, y)) ~ 0.1], cdom(), [t, x, y],
            [c(t, x, y)], Num[]; name = :gh)
        for alg in (ExplicitEuler(; dt = 0.05, substeps = 4), BackwardEuler(; dt = 0.05))
            sc, sh = solve(cown(gsys(cgh), CDIMS), alg), solve(cown(gsys(hgh), CDIMS .÷ CK), alg)
            @test sc[cgh(t, x, y), length(sc.t)] == sh[hgh(t, x, y), length(sh.t)]
        end
        # problem = :ode: the coarse right side is the hand problem's (no masks there)
        cc = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables codec(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        ch2 = first(@variables codeh(..))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        osys(c, k2, extra) = PDESystem([D(c(t, x, y)) ~ cD * Δ(c(t, x, y)) - ckd * c(t, x, y) * k2 + 0.05 * g(t, x, y)],
            [c(0, x, y) ~ x * y], cdom(), [t, x, y], [c(t, x, y), g(t, x, y), extra], [cD, ckd]; name = :os)
        oc = discretize(osys(cc, ismember(q(t, x, y), (2,)), q(t, x, y)), LatticeDiscretization(Grid(CDIMS));
            inputs = [q(t, x, y) => CQ1, g(t, x, y) => CG])
        oh = discretize(osys(ch2, cf2(t, x, y), cf2(t, x, y)), LatticeDiscretization(Grid(CDIMS .÷ CK));
            inputs = [cf2(t, x, y) => cmean(Float64.(CQ1 .== 2)), g(t, x, y) => cmean(CG)])
        du1, du2 = similar(oc.u0), similar(oh.u0)
        oc.f(du1, oc.u0, oc.p, 0.0); oh.f(du2, oh.u0, oh.p, 0.0)
        @test capprox(du1, du2; rtol = 1e-14)
    end

    @testset "the folds: the restriction conserves mass, kind expressions included" begin
        # an aux field of a real input, `K ~ g`: Σ K · k² is the fine sum (the block mean)
        K = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables Kmass(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cmass(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        G = rand(Xoshiro(3), 16, 16)
        sys = PDESystem([D(c(t, x, y)) ~ g(t, x, y), K(t, x, y) ~ g(t, x, y) + ismember(q(t, x, y), (2,))],
            [c(0, x, y) ~ 0.0], cdom(), [t, x, y], [c(t, x, y), K(t, x, y), q(t, x, y), g(t, x, y)], Num[]; name = :m)
        p = cown(sys, CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => G])
        s = solve(p, ExplicitEuler(; dt = 0.25))
        Kv = s[K(t, x, y), length(s.t)]
        @test size(Kv) == (4, 4)
        @test sum(Kv) * CK^2 ≈ sum(G) + count(==(2), CQ1) rtol = 1e-14      # the means (F4-15: the kind's too)
        @test sum(s[c(t, x, y), length(s.t)]) * CK^2 ≈ sum(G) rtol = 1e-13    # Σ over the run (t = 1)
        # 3D, factor 2: 8 children per node
        c3 = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cmass3(..))), LatticePDE.LatticeLevel, Coarse(2)))
        @parameters z
        g3 = first(@variables g(..) [input = true])
        sys3 = PDESystem([D(c3(t, x, y, z)) ~ g3(t, x, y, z)], [c3(0, x, y, z) ~ 0.0],
            [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0), z ∈ Interval(0.0, 1.0)], [t, x, y, z],
            [c3(t, x, y, z), g3(t, x, y, z)], Num[]; name = :m3)
        G3 = rand(Xoshiro(4), 4, 6, 8)
        s3 = solve(cown(sys3, (4, 6, 8); ins = [g3(t, x, y, z) => G3]), ExplicitEuler(; dt = 0.5))
        v3 = s3[c3(t, x, y, z), length(s3.t)]
        @test size(v3) == (2, 3, 4)
        @test sum(v3) * 8 ≈ sum(G3) rtol = 1e-13
        @test v3[2, 3, 4] ≈ sum(G3[3:4, 5:6, 7:8]) / 8 rtol = 1e-14
    end

    @testset "review r1 M2: a nonlinear fine read is restricted by the mean of the whole subterm" begin
        # `D(c) ~ f` on Coarse(4) over 16²: Σ c · k² after t = 1 is the fine Σ f (base cb20be97,
        # ~/lpwork/f3b6r-nc-m2.log: `f(mean g)`, off by −25% for g², −75% for max(g − 0.5, 0),
        # −4% for exp(g), +2% for at(S, q) g, +25% for g/(0.2 + g))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        G = rand(Xoshiro(5), 16, 16)
        S = Float64[1.0, 2.0, 5.0, 3.0]
        srcs = [(qe, ge) -> ge => sum(G), (qe, ge) -> max(ge - 0.5, 0) => sum(max.(G .- 0.5, 0)),
            (qe, ge) -> ge^2 => sum(G .^ 2), (qe, ge) -> exp(ge) => sum(exp.(G)),
            (qe, ge) -> at(cSv, qe + 1) * ge => sum(S[CQ1 .+ 1] .* G), (qe, ge) -> ge / (0.2 + ge) => sum(G ./ (0.2 .+ G))]
        for (i, f) in enumerate(srcs)
            c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(Symbolics.variable(Symbol(:cm2_, i); T = SymbolicUtils.FnType{Tuple, Real, Nothing})),
                LatticePDE.LatticeLevel, Coarse(CK)))
            src, want = f(q(t, x, y), g(t, x, y))
            sys = PDESystem([D(c(t, x, y)) ~ src], [c(0, x, y) ~ 0.0], cdom(), [t, x, y], [c(t, x, y), q(t, x, y), g(t, x, y)],
                [cSv]; name = :m2)
            s = solve(cown(sys, CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => G]), ExplicitEuler(; dt = 0.25))
            got = sum(s[c(t, x, y), length(s.t)]) * CK^2
            @test isapprox(got, want; rtol = 1e-13) || (println("M2 ", src, ": ", got, " ", want); false)
        end
    end

    @testset "F4-15: a kind expression folds by its block mean (blocks a kind covers in part); S2: the coarse-frame clamp" begin
        # blocks with ties and mixes: 8 P + 8 Q, 9 P + 7 Q, 6 P + 6 Q + 4 medium, 8 medium + 8 Q,
        # 8 Q + 8 N, ... Every spelling of a kind-dependent rate is the block mean of its fine
        # values, so the coarse total times the block size is the fine total (exact: the means are
        # multiples of 1/16) and complementary conditions sum to 1. Base 5e972579
        # (~/lpwork/f4F15/nc.log): the block's plurality owner, off by up to the full rate
        Q = CQT
        lvl(n) = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(Symbolics.variable(n; T = SymbolicUtils.FnType{Tuple, Real, Nothing})),
            LatticePDE.LatticeLevel, Coarse(CK)))
        cs1, K1, K2, M0, M1 = lvl(:cs1), lvl(:K1s1), lvl(:K2s1), lvl(:M0s1), lvl(:M1s1)
        q = first(@variables q(..)::Int32 [input = true])
        @parameters cR[1:4] = [0.0, 1.0, 0.5, 0.0]
        qe = q(t, x, y)
        sys = PDESystem([D(cs1(t, x, y)) ~ (qe == 1) + 0.5 * (qe == 2), K1(t, x, y) ~ (qe == 1) + 0.5 * (qe == 2), K2(t, x, y) ~ at(cR, qe + 1),
                M0(t, x, y) ~ (qe == 0), M1(t, x, y) ~ (qe != 0)], [cs1(0, x, y) ~ 0.0], cdom(), [t, x, y],
            [cs1(t, x, y), K1(t, x, y), K2(t, x, y), M0(t, x, y), M1(t, x, y), qe], [cR]; name = :s1)
        s = solve(cown(sys, CDIMS; ins = [qe => Q]), ExplicitEuler(; dt = 0.5))
        r(v) = s[v(t, x, y), length(s.t)]
        fine = [0.0, 1.0, 0.5, 0.0][Q .+ 1]
        @test r(K1) == r(K2) == cmean(fine)
        @test sum(r(K1)) * CK^2 == sum(fine)                                   # conservation, exact
        @test sum(r(cs1)) * CK^2 == sum(fine)                                  # the source over t = 1
        @test r(M0) + r(M1) == ones(4, 4) && r(M0) == cmean(Float64.(Q .== 0))
        @test any(v -> 0 < v < 1, r(M0)) && any(v -> !(v in (0.0, 0.5, 1.0)), r(K1))   # (blocks a kind covers in part)
        # an indicator as an operator coefficient (`DivKGrad(ismember(kind, …), c)`) folds by its
        # mean at each face as a real input of the block means does
        cop, hop = lvl(:cops1), first(@variables hops1(..))
        kf = first(@variables kf(..) [input = true, bounds = (0, 1)])
        osys(c, K, dvs) = PDESystem([D(c(t, x, y)) ~ 0.05 * DivKGrad(:arithmetic)(0.5 + K, c(t, x, y))],
            [c(0, x, y) ~ x * y], cdom(), [t, x, y], [c(t, x, y); dvs], Num[]; name = :ops1)
        so = solve(cown(osys(cop, ismember(qe, (1, 2)), [qe]), CDIMS; ins = [qe => Q]), ExplicitEuler(; dt = 0.05, substeps = 4))
        sh = solve(cown(osys(hop, kf(t, x, y), [kf(t, x, y)]), CDIMS .÷ CK; ins = [kf(t, x, y) => cmean(Float64.(1 .<= Q .<= 2))]),
            ExplicitEuler(; dt = 0.05, substeps = 4))
        @test capprox(so[cop(t, x, y), length(so.t)], sh[hop(t, x, y), length(sh.t)]; rtol = 1e-14)
        # S2: a kind-dependent face coefficient (and a real one) at a face of the box equals the
        # hand-coarsened twin bitwise: the neighbor block clamped in the coarse frame (base
        # cb20be97, ~/lpwork/f3b6r-nc-s2.log: the fine-frame clamp reads the boundary layer)
        Ki = 0.5 .+ rand(Xoshiro(41), 16, 16)
        @parameters cKv[1:4] = [1.0, 4.0, 0.25, 2.0]
        ki = first(@variables ki(..) [input = true])
        # (the kind case: the twin reads the block means of `at(cKv, q + 1)` as the real input `ki`)
        for (lab, K, insf, insc) in (("kind", qq -> at(cKv, qq + 1), [qe => Q, ki(t, x, y) => Ki],
                                      [qe => Q[1:4, 1:4], ki(t, x, y) => cmean([1.0, 4.0, 0.25, 2.0][Q .+ 1])]),
                                     ("real", qq -> ki(t, x, y), [qe => Q, ki(t, x, y) => Ki], [qe => Q[1:4, 1:4], ki(t, x, y) => cmean(Ki)]))
            c2 = lvl(Symbol(:cs2, lab))
            ch = first(@variables chs2(..))
            tsys(c, Kx) = PDESystem([D(c(t, x, y)) ~ 0.05 * DivKGrad(:harmonic)(Kx, c(t, x, y)) - c(t, x, y)],
                [c(0, x, y) ~ x * y, c(t, 0, y) ~ 1.0, c(t, 1, y) ~ 0.0], cdom(), [t, x, y], [c(t, x, y), qe, ki(t, x, y)], [cKv];
                name = :s2)
            for alg in (ExplicitEuler(; dt = 0.05, substeps = 4), BackwardEuler(; dt = 0.05))
                sc, sh = solve(cown(tsys(c2, K(qe)), CDIMS; ins = insf), alg), solve(cown(tsys(ch, ki(t, x, y)), CDIMS .÷ CK; ins = insc), alg)
                @test sc[c2(t, x, y), length(sc.t)] == sh[ch(t, x, y), length(sh.t)] ||
                      (println("S2 ", lab, " ", alg, " ", maximum(abs, sc[c2(t, x, y), length(sc.t)] .- sh[ch(t, x, y), length(sh.t)])); false)
            end
        end
    end

    @testset "F4-15b: a mask blends on the blocks it covers in part" begin
        # A mask `masked(q == 0, v)` on Coarse(4): a node is masked where its whole block is kind 0;
        # elsewhere it holds the value of its free part (the children with q ≠ 0), its equation folded
        # over them. Base 7d101740 (~/lpwork/f4F15b/nc.log): the mask folds by Majority, so a node
        # with 9 or more medium children is held and its sources are lost, and the others fold over
        # the whole block.
        lvl(n) = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(Symbolics.variable(n; T = SymbolicUtils.FnType{Tuple, Real, Nothing})),
            LatticePDE.LatticeLevel, Coarse(CK)))
        q = first(@variables q(..)::Int32 [input = true])
        qe = q(t, x, y)
        # kind 1 (the source) next to the medium (kind 0) on blocks the medium covers in part: the
        # medium on 0, 4, 8, 9, 12, 15 or 16 of a block's sites, kind 1 on the sites next to it
        Q = zeros(Int32, CDIMS)
        nmed = [0, 4, 8, 9, 12, 15, 16, 9, 8, 4, 12, 15, 0, 16, 9, 12]
        for (b, J) in enumerate(CartesianIndices(CDIMS .÷ CK))
            sites = [CartesianIndex((J[1] - 1) * CK + i, (J[2] - 1) * CK + j) for j in 1:CK for i in 1:CK]
            for (n, st) in enumerate(sites)
                Q[st] = n <= nmed[b] ? 0 : n <= nmed[b] + 3 ? 1 : 2
            end
        end
        held = Q .== 0
        nf = cnfree(held)
        @test sort(unique(nf)) == [0, 1, 4, 7, 8, 12, 16]
        S = 0.7
        csrc = lvl(:cb15src)
        sys(c, v) = PDESystem([D(c(t, x, y)) ~ S * (qe == 1) + 0.25 * (qe == 2) * c(t, x, y)], [c(0, x, y) ~ 0.0, c(t, x, y) ~ masked(qe == 0, v)],
            cdom(), [t, x, y], [c(t, x, y), qe], Num[]; name = :b15)
        op = discretize(sys(csrc, 0.5), LatticeDiscretization(Grid(CDIMS)); inputs = [qe => Q])
        du = similar(op.u0); op.f(du, zero(op.u0), op.p, 0.0)
        du = reshape(du, 4, 4)
        # one blended node by hand: the rate is the mean over its free children, S #(q == 1) / #free
        for I in CartesianIndices(nf)
            nf[I] in (0, 16) && continue
            blk = Q[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]
            @test du[I] ≈ S * count(==(1), blk) / nf[I] rtol = 1e-15
        end
        # conservation: the free volume times the rate is the fine source total (every source site
        # is free); the Majority fold lost the sources of the blocks with 9 or more medium sites
        @test sum(nf[I] * du[I] for I in eachindex(nf) if nf[I] > 0) ≈ S * count(==(1), Q) rtol = 1e-14
        for alg in (ExplicitEuler(; dt = 0.25), BackwardEuler(; dt = 0.25))
            ic = init(cown(sys(csrc, 0.5), CDIMS; ins = [qe => Q]), alg)
            for _ in 1:4
                step!(ic)
            end
            u1 = ic[csrc(t, x, y)]
            @test all(u1[nf .== 0] .== 0.5)                                    # the masked nodes hold the value
            # the free content Σ #free u grows by the source and by the decay of the free part:
            # with c(0) = 0 and no diffusion each free node is the scalar ODE u' = a + b u
            a = [nf[I] == 0 ? 0.0 : S * count(==(1), Q[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]) / nf[I]
                 for I in CartesianIndices(nf)]
            b = [nf[I] == 0 ? 0.0 : 0.25 * count(==(2), Q[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]) / nf[I]
                 for I in CartesianIndices(nf)]
            ns = 4 * only(LatticePDE.substep_counts(ic))
            h = 1.0 / ns
            # (each substep: ExplicitEuler u + h(a + bu), BackwardEuler (u + ha)/(1 − hb))
            want = zeros(4, 4)
            for _ in 1:ns
                want = alg isa ExplicitEuler ? want .+ h .* (a .+ b .* want) : (want .+ h .* a) ./ (1 .- h .* b)
            end
            m = nf .> 0
            @test isapprox(u1[m], want[m]; rtol = 1e-12) || (println("F4-15b scalar ", alg, ": ", maximum(abs, u1[m] .- want[m])); false)
        end
        # f = 0 and f = 1: a node no child of which is held folds over the whole block bitwise (the
        # rate equals the unmasked system's), a node all of whose children are held is masked
        cnm = lvl(:cb15nomask)
        sysn = PDESystem([D(cnm(t, x, y)) ~ S * (qe == 1) + 0.25 * (qe == 2) * cnm(t, x, y)], [cnm(0, x, y) ~ 0.0], cdom(), [t, x, y],
            [cnm(t, x, y), qe], Num[]; name = :b15n)
        on = discretize(sysn, LatticeDiscretization(Grid(CDIMS)); inputs = [qe => Q])
        u0 = collect(range(0.1, 1.6; length = 16))
        du1, du2 = similar(op.u0), similar(on.u0)
        op.f(du1, u0, op.p, 0.0); on.f(du2, u0, on.p, 0.0)
        @test vec(nf .== 16) == (du1 .== du2 .&& vec(nf .== 16)) && any(nf .== 16)
        @test all(du1[vec(0 .< nf .< 16)] .!= du2[vec(0 .< nf .< 16)])
        # complementary masks on a block covered half by each (F4-15 review should-fix 3): neither
        # node is masked; each field holds the value of its own free part (its rate folds over its
        # own free children), so `masked(q == 0, 9)` sees the source and `masked(q != 0, 9)` does not
        Qh = zeros(Int32, CDIMS); Qh[1:4, 1:2] .= 1                      # block (1, 1): 8 of 16 sites kind 1
        c5, c6 = lvl(:cb15half0), lvl(:cb15half1)
        for (c, pr, want) in ((c5, qe == 0, 1.0), (c6, qe != 0, 0.0))
            hs = PDESystem([D(c(t, x, y)) ~ (qe == 1)], [c(0, x, y) ~ 0.0, c(t, x, y) ~ masked(pr, 9.0)], cdom(), [t, x, y],
                [c(t, x, y), qe], Num[]; name = :b15h)
            sl = solve(cown(hs, CDIMS; ins = [qe => Qh]), ExplicitEuler(; dt = 0.5))
            v = sl[c(t, x, y), length(sl.t)]
            @test v[1, 1] == want                                           # (t = 1: the free part's mean source)
        end
        # the ODE path (`discretize`'s right side) and every stepper of the owned path equal the
        # hand-coarsened twin on blended nodes ("a coarse field equals the hand-coarsened problem")
        cod, hod = lvl(:cb15ode), first(@variables hb15ode(..))
        kq = first(@variables kq(..) [input = true, bounds = (0, 1)])
        osys(c, k1, mq, dvs) = PDESystem([D(c(t, x, y)) ~ 0.02 * Δ(c(t, x, y)) - c(t, x, y) * k1 + 0.3 * k1],
            [c(0, x, y) ~ x * y, c(t, x, y) ~ masked(mq == 0, 0.5)], cdom(), [t, x, y], [c(t, x, y); dvs], Num[]; name = :b15o)
        oc = discretize(osys(cod, qe == 2, qe, [qe]), LatticeDiscretization(Grid(CDIMS)); inputs = [qe => Q])
        oh = discretize(osys(hod, kq(t, x, y), qe, [kq(t, x, y), qe]), LatticeDiscretization(Grid(CDIMS .÷ CK));
            inputs = [kq(t, x, y) => cfree(Float64.(Q .== 2), held), qe => Int32[n == 0 ? 0 : 1 for n in nf]])
        d1, d2 = similar(oc.u0), similar(oh.u0)
        oc.f(d1, oc.u0, oc.p, 0.0); oh.f(d2, oh.u0, oh.p, 0.0)
        @test capprox(d1, d2; rtol = 1e-14)

    end

    @testset "a fine field and a coarse field in one group: prolongation and restriction" begin
        # u (fine 8×8) reads c (Coarse(2), 4×4) at the node of its block; c reads u by the block
        # mean. One BackwardEuler window against the hand matrix of the coupled system.
        c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cmix(..))), LatticePDE.LatticeLevel, Coarse(2)))
        u = first(@variables umix(..))
        @parameters ka = 0.7 kb = 0.4
        sys = PDESystem([D(c(t, x, y)) ~ 0.05 * Δ(c(t, x, y)) - c(t, x, y) + ka * u(t, x, y),
                D(u(t, x, y)) ~ 0.02 * Δ(u(t, x, y)) - u(t, x, y) + kb * c(t, x, y)],
            [c(0, x, y) ~ x, u(0, x, y) ~ y], cdom(), [t, x, y], [c(t, x, y), u(t, x, y)], [ka, kb]; name = :mix)
        p = cown(sys, (8, 8))
        lap(n, h) = (L = zeros(n * n, n * n); li = LinearIndices((n, n));
                     for j in 1:n, i in 1:n, (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                         (1 <= i + di <= n && 1 <= j + dj <= n) || continue
                         L[li[i, j], li[i + di, j + dj]] += 1 / h^2; L[li[i, j], li[i, j]] -= 1 / h^2
                     end; L)
        # restriction R (mean over the 2×2 block) and prolongation P (the node of the block)
        R, P = zeros(16, 64), zeros(64, 16)
        lf, lc = LinearIndices((8, 8)), LinearIndices((4, 4))
        for j in 1:8, i in 1:8
            J = lc[(i + 1) ÷ 2, (j + 1) ÷ 2]
            R[J, lf[i, j]] = 1 / 4
            P[lf[i, j], J] = 1.0
        end
        A = [0.05*lap(4, 0.25)-I 0.7*R; 0.4*P 0.02*lap(8, 0.125)-I]
        h = 0.1
        for alg in (BackwardEuler(; dt = h, inner = DevicePCG(; rtol = 1e-12, budget = 64), newton = 30),
                    ExplicitEuler(; dt = h / 200, substeps = 1))
            ig = init(p, alg)
            for _ in 1:(alg isa BackwardEuler ? 1 : 200)
                step!(ig)
            end
            u0 = copy(p.u0)
            want = alg isa BackwardEuler ? (I - h * A) \ u0 : foldl((v, _) -> v + (h / 200) * A * v, 1:200; init = u0)
            got = [vec(ig[c(t, x, y)]); vec(ig[u(t, x, y)])]
            @test got ≈ want rtol = alg isa BackwardEuler ? 1e-9 : 1e-12
        end
    end

    @testset "an irregular domain on a coarse grid: the domain folded by Majority" begin
        # the fine domain: each 4×4 block in it on 10 of its 16 sites, or out of it on 10 (a strict
        # majority); the hand twin's domain is the block majority on the coarse grid
        rng = Xoshiro(21)
        Dc = Bool[rand(rng) < 0.6 for _ in 1:4, _ in 1:4]
        Dc[1, 1] = Dc[2, 2] = true; Dc[4, 4] = false
        Df = falses(16, 16)
        for J in CartesianIndices(Dc)
            own = randperm(rng, 16)
            for (n, (i, j)) in enumerate((i, j) for i in 1:4 for j in 1:4)
                Df[(J[1] - 1) * 4 + i, (J[2] - 1) * 4 + j] = own[n] <= 10 ? Dc[J] : !Dc[J]
            end
        end
        @variables cdm(..)::Bool [input = true]
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        cdo = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cdomf(..))), LatticePDE.LatticeLevel, Coarse(4)))
        cdh = first(@variables cdomh(..))
        # (the twin reads the kind expressions' block means as real inputs, F4-15)
        function dsys(c; hand = false)
            k2, k1 = hand ? (cf2(t, x, y), cf1(t, x, y)) : (ismember(q(t, x, y), (2,)), q(t, x, y) == 1)
            PDESystem([D(c(t, x, y)) ~ 0.02 * Δ(c(t, x, y)) - c(t, x, y) * k2 + 0.5 * k1 + 0.05 * g(t, x, y)],
                [c(0, x, y) ~ x + y, c(t, x, y) ~ masked(q(t, x, y) == 3, 1.0)], cdom(), [t, x, y],
                [[c(t, x, y), cdm(t, x, y), q(t, x, y), g(t, x, y)]; hand ? [cf1(t, x, y), cf2(t, x, y)] : Num[]], Num[]; name = :dm)
        end
        pc = cown(dsys(cdo), CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1, g(t, x, y) => CG])
        # (`ckinds` covers no block with kind 3 whole: no node is masked, each folds over its free children)
        ph = cown(dsys(cdh; hand = true), CDIMS .÷ CK; domain = cdm,
            ins = vcat([cdm(t, x, y) => Dc, q(t, x, y) => cwhole(CQ1), g(t, x, y) => cfree(CG, CQ1 .== 3)], chand(CQ1)[1:2]))
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05), CrankNicolson(; dt = 0.05))
            sc, sh = solve(pc, alg), solve(ph, alg)
            @test capprox(sc[cdo(t, x, y), length(sc.t)], sh[cdh(t, x, y), length(sh.t)]; rtol = alg isa ExplicitEuler ? 1e-13 : 1e-10)
        end
        # a node outside keeps its value (its block's majority is outside); nodes inside moved
        sc = solve(pc, BackwardEuler(; dt = 0.05))
        v0, v1 = sc[cdo(t, x, y), 1], sc[cdo(t, x, y), length(sc.t)]
        @test v1[.!Dc] == v0[.!Dc] && any(v1[Dc] .!= v0[Dc])
        # in a group of some fields only (FieldGroups): the group computes the domain of its
        # coarse field's level (a fine field `u` that the coarse one does not read, its own group)
        ug = first(@variables udomg(..))
        cdg = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cdomg(..))), LatticePDE.LatticeLevel, Coarse(4)))
        gsys = PDESystem([D(cdg(t, x, y)) ~ 0.02 * Δ(cdg(t, x, y)) + 0.5 * (q(t, x, y) == 1), D(ug(t, x, y)) ~ 0.1 * Δ(ug(t, x, y)) - ug(t, x, y)],
            [cdg(0, x, y) ~ x + y, ug(0, x, y) ~ x], cdom(), [t, x, y], [cdg(t, x, y), ug(t, x, y), cdm(t, x, y), q(t, x, y)], Num[]; name = :dg)
        pg = cown(gsys, CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1])
        sg = solve(pg, FieldGroups(cdg(t, x, y) => BackwardEuler(; dt = 0.05), ug(t, x, y) => ExplicitEuler(; dt = 0.05)))
        csys1 = PDESystem([D(cdg(t, x, y)) ~ 0.02 * Δ(cdg(t, x, y)) + 0.5 * (q(t, x, y) == 1)], [cdg(0, x, y) ~ x + y], cdom(),
            [t, x, y], [cdg(t, x, y), cdm(t, x, y), q(t, x, y)], Num[]; name = :d1)
        s1 = solve(cown(csys1, CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1]), BackwardEuler(; dt = 0.05))
        @test sg[cdg(t, x, y), length(sg.t)] ≈ s1[cdg(t, x, y), length(s1.t)] rtol = 1e-10
        @test sg[cdg(t, x, y), length(sg.t)][.!Dc] == sg[cdg(t, x, y), 1][.!Dc]
    end

    @testset "refusals name the cause and a route that works" begin
        q = first(@variables q(..)::Int32 [input = true])
        mk(c; n = (16, 16)) = cown(PDESystem([D(c(t, x, y)) ~ 0.01 * Δ(c(t, x, y)) - c(t, x, y) * ismember(q(t, x, y), (2,))],
            [c(0, x, y) ~ 1.0], cdom(), [t, x, y], [c(t, x, y), q(t, x, y)], Num[]; name = :r), n;
            ins = [q(t, x, y) => zeros(Int32, n)])
        # a level that is not a grid: the route `Coarse(k)`
        ci = first(@variables cint(..) [lattice_level = 4])
        m = cmsg(() -> mk(ci))
        @test occursin("`lattice_level = 4`", m) && occursin("`Coarse(4)`", m)
        # an axis that k does not divide: named, with its size and the route (which works)
        cc = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        m = cmsg(() -> mk(cc; n = (18, 16)))
        @test occursin("axis 1 (`x`) has 18 sites", m) && occursin("divisible by 4", m) && occursin("20 or 16", m)
        @test solve(mk(cc; n = (20, 16)), ExplicitEuler(; dt = 0.1)).retcode == SciMLBase.ReturnCode.Success
        @test solve(mk(cc; n = (16, 1)), ExplicitEuler(; dt = 0.1)).retcode == SciMLBase.ReturnCode.Success   # size 1: never coarsened
        # a spatial operator of a coarse field in a fine row: the coarse operator at the node of
        # the block (F3-22: the direct form is the aux field of the route, which also works)
        u = first(@variables uref(..))
        L = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables Lref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        direct = PDESystem([D(cc(t, x, y)) ~ 0.01 * Δ(cc(t, x, y)), D(u(t, x, y)) ~ Δ(cc(t, x, y))],
            [cc(0, x, y) ~ x^2, u(0, x, y) ~ 0.0], cdom(), [t, x, y], [cc(t, x, y), u(t, x, y)], Num[]; name = :b)
        good = PDESystem([D(cc(t, x, y)) ~ 0.01 * Δ(cc(t, x, y)), L(t, x, y) ~ Δ(cc(t, x, y)), D(u(t, x, y)) ~ L(t, x, y)],
            [cc(0, x, y) ~ x^2, u(0, x, y) ~ 0.0], cdom(), [t, x, y], [cc(t, x, y), L(t, x, y), u(t, x, y)], Num[]; name = :g)
        sg = solve(cown(good, (16, 16)), ExplicitEuler(; dt = 0.01, substeps = 1); saveat = [0.01])
        @test size(sg[L(t, x, y), 1]) == (4, 4) && size(sg[u(t, x, y), 2]) == (16, 16)
        sdir = solve(cown(direct, (16, 16)), ExplicitEuler(; dt = 0.01, substeps = 1); saveat = [0.01])
        @test sdir[u(t, x, y), 2] == sg[u(t, x, y), 2]
        # a mask on an aux field: refused (D-F4-15b Limits (4): an aux field follows its
        # expression), with the route (mask a rate field)
        am = PDESystem([D(cc(t, x, y)) ~ 0.01 * Δ(cc(t, x, y)), L(t, x, y) ~ Δ(cc(t, x, y))],
            [cc(0, x, y) ~ x^2, L(t, x, y) ~ masked(q(t, x, y) == 3, 1.0)], cdom(),
            [t, x, y], [cc(t, x, y), L(t, x, y), q(t, x, y)], Num[]; name = :am)
        m = cmsg(() -> cown(am, (16, 16); ins = [q(t, x, y) => zeros(Int32, 16, 16)]))
        @test occursin("aux field", m) && occursin("takes no mask", m) && occursin("rate field", m)
        # (in a substep a field reads the fields it depends on after their update: `L` from `cref`
        # after its step; the coarse Laplacian by hand, zero flux, spacing 1/4)
        lap(v) = (n = size(v, 1); [sum((1 <= i + a <= n && 1 <= j + b <= n ? v[i + a, j + b] - v[i, j] : 0.0)
                                       for (a, b) in ((1, 0), (-1, 0), (0, 1), (0, -1))) * 16 for i in 1:n, j in 1:n])
        c0 = [((i - 0.5) / 4)^2 for i in 1:4, j in 1:4]
        Lh = lap(c0 .+ 0.01 * 0.01 .* lap(c0))
        @test sg[u(t, x, y), 2] ≈ 0.01 .* repeat(Lh; inner = (4, 4)) rtol = 1e-12
        # a map's offset read counts fine sites: a coarse field's must be a multiple of k
        @parameters dx [lattice_spacing = 1]
        mm = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables mref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        msys(a) = PDESystem([Shift(t, 1)(mm(t, x, y)) ~ mm(t, x + a * dx, y)], [mm(0, x, y) ~ x], cdom(10.0), [t, x, y],
            [mm(t, x, y)], [dx]; name = :mp)
        m = cmsg(() -> cown(msys(1), (16, 16)))
        @test occursin("a multiple of 4 sites (`4 * dx`)", m)
        sm = solve(cown(msys(4), (16, 16)), ExplicitMap(); saveat = [1.0])
        @test sm[mm(t, x, y), 2][1:3, :] == sm[mm(t, x, y), 1][2:4, :]          # one node to the left
    end
end
