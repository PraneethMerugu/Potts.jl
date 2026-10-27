# F3-16 (F3 design §3.9, FE-08): `[lattice_level = Coarse(k)]` in the IR and LatticePDE. A
# coarse field lives on level log2(k) of the program's hierarchy: its rate, conditions, masks,
# operator (`jac:`) and residual kernels run there with the spacing `k h`, and its fine reads
# (the inputs, an irregular domain) are folded over each node's block (an integer input at the
# block's plurality owner, a nonlinear part of a fine real read by its mean, a condition on a
# Bool input by Majority; review r1 M2, S1). The oracle is the hand-coarsened problem: the same
# system discretized on the coarse grid, with its inputs folded by hand; the two must agree
# bitwise under every algorithm. Base 85794414 (~/lpwork/f3b6-nc-lp.log): `Coarse` is not defined, and
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
# the owned problem of `sys` on `dims` with inputs `ins`
cown(sys, dims; T = Float64, ins = (), kw...) = discretize(sys, LatticeDiscretization(Grid(dims); T, problem = :owned, kw...);
    inputs = collect(Pair, ins))

# One system with the features a coarse field must carry: a face coefficient of the coordinates,
# a decay at a kind (the owner), a source at a kind, a moving masked Dirichlet, a Robin face, a
# Dirichlet face whose value reads the coordinates, a face value that reads an input (a field
# face), a table at the kind (the owner's entry) and a source from a real input (the mean)
@parameters cD = 0.02 ckd = 3.0 cs = 0.5 cSv[1:4] = [1.0, 2.0, 5.0, 3.0]
function csys(c, q, g; steady = false)
    ce, qe, ge = c(t, x, y), q(t, x, y), g(t, x, y)
    rhs = cD * DivKGrad(:harmonic)(1 + x, ce) - ckd * ce * ismember(qe, (2,)) + cs * (qe == 1) +
          0.1 * at(cSv, qe + 1) + 0.05 * ge
    eqs = steady ? [0 ~ rhs] : [D(ce) ~ rhs]
    bcs = [ce ~ masked(qe == 3, 1.0), 0.5 * c(t, 0, y) - 0.1 * Differential(x)(c(t, 0, y)) ~ 0.3,
        c(t, x, 1) ~ x, c(t, 1, y) ~ g(t, 1, y)]
    steady || push!(bcs, c(0, x, y) ~ x * y)
    return PDESystem(eqs, bcs, cdom(), [t, x, y], [ce, qe, ge], [cD, ckd, cs, cSv]; name = :cs)
end
const CQ1, CQ1c = ckinds(11)
const CQ2, CQ2c = ckinds(12)
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
# the plurality owner of each 4×4 block by hand (ties to the smallest nonzero kind, 0 last)
function cowner(Q; k = CK)
    [begin
         v = [Q[(I[1] - 1) * k + i, (I[2] - 1) * k + j] for j in 1:k for i in 1:k]
         n = maximum(count(==(u), v) for u in v)
         tied = sort!(unique([u for u in v if count(==(u), v) == n]))
         any(!=(0), tied) ? first(filter(!=(0), tied)) : Int32(0)
     end for I in CartesianIndices(size(Q) .÷ k)]
end

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
    pc = cown(csys(c, q, g; steady), CDIMS; T, ins = [q(t, x, y) => CQ1, g(t, x, y) => CG], kw...)
    ph = cown(csys(ch, q, g; steady), CDIMS .÷ CK; T, ins = [q(t, x, y) => CQ1c, g(t, x, y) => cmean(CG)], kw...)
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
                n == 4 && (ic[q(t, x, y)] = CQ2; ih[q(t, x, y)] = CQ2c)       # the mask moves
                step!(ic); step!(ih)
            end
            @test ic.retcode == ih.retcode == SciMLBase.ReturnCode.Success
            @test size(ic[c(t, x, y)]) == (4, 4)
            @test ic[c(t, x, y)] == ih[ch(t, x, y)]
            @test LatticePDE.substep_counts(ic) == LatticePDE.substep_counts(ih)
        end
        # the masked nodes hold the masked value, and only where the block's owner is kind 3
        ic = init(pc, BackwardEuler(; dt = 0.05)); step!(ic)
        @test all(ic[c(t, x, y)][CQ1c .== 3] .== 1.0) && any(ic[c(t, x, y)][CQ1c .!= 3] .!= 1.0)
    end

    @testset "steady rows, number types and the ODE path on a coarse grid" begin
        pc, ph, (c, ch, _...) = ctwins(; steady = true)
        sc, sh = solve(pc, QuasiSteady(; dt = 0.1)), solve(ph, QuasiSteady(; dt = 0.1))
        @test sc[c(t, x, y), length(sc.t)] == sh[ch(t, x, y), length(sh.t)]
        pc, ph, (c, ch, _...) = ctwins(; T = Float32)
        @test eltype(pc.u0) == Float32
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05))
            sc, sh = solve(pc, alg), solve(ph, alg)
            @test sc[c(t, x, y), length(sc.t)] == sh[ch(t, x, y), length(sh.t)]
        end
        pc, ph, (c, ch, _...) = ctwins(; storage = Float32)          # a declared storage on the owned path
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05))
            sc, sh = solve(pc, alg), solve(ph, alg)
            @test eltype(sc[c(t, x, y), 1]) == Float32
            @test sc[c(t, x, y), length(sc.t)] == sh[ch(t, x, y), length(sh.t)]
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
        osys(c) = PDESystem([D(c(t, x, y)) ~ cD * Δ(c(t, x, y)) - ckd * c(t, x, y) * ismember(q(t, x, y), (2,)) + 0.05 * g(t, x, y)],
            [c(0, x, y) ~ x * y], cdom(), [t, x, y], [c(t, x, y), q(t, x, y), g(t, x, y)], [cD, ckd]; name = :os)
        oc = discretize(osys(cc), LatticeDiscretization(Grid(CDIMS); problem = :ode); inputs = [q(t, x, y) => CQ1, g(t, x, y) => CG])
        oh = discretize(osys(ch2), LatticeDiscretization(Grid(CDIMS .÷ CK); problem = :ode);
            inputs = [q(t, x, y) => CQ1c, g(t, x, y) => cmean(CG)])
        du1, du2 = similar(oc.u0), similar(oh.u0)
        oc.f(du1, oc.u0, oc.p, 0.0); oh.f(du2, oh.u0, oh.p, 0.0)
        @test du1 == du2
    end

    @testset "the folds: the restriction conserves mass; Majority is the full owner rate" begin
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
        @test sum(Kv .- (CQ1c .== 2)) * CK^2 ≈ sum(G) rtol = 1e-14            # the mean; Majority: 0 or 1
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

    @testset "review r1 S1, S2: the block's plurality owner; the coarse-frame clamp at a face of the box" begin
        # blocks with ties: 8 P + 8 Q (owner P: the smaller kind), 9 P + 7 Q, 6 P + 6 Q + 4 medium,
        # 8 medium + 8 Q (owner Q: the medium loses a tie), 8 Q + 8 N, ...; `cowner` by hand
        Q, Qc = CQT, cowner(CQT)
        @test Qc[1:4, 1] == [1, 1, 1, 1] && Qc[1:4, 2] == [2, 0, 3, 2]
        # S1: two spellings of one kind-dependent rate agree at the owner; complementary
        # conditions never both fail (base cb20be97, ~/lpwork/f3b6r-nc-s1.log: the per-condition
        # Majority gives 0 on the 8 + 8 blocks and on 6 + 6 + 4, `at` the block mean)
        lvl(n) = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(Symbolics.variable(n; T = SymbolicUtils.FnType{Tuple, Real, Nothing})),
            LatticePDE.LatticeLevel, Coarse(CK)))
        cs1, K1, K2, M0, M1 = lvl(:cs1), lvl(:K1s1), lvl(:K2s1), lvl(:M0s1), lvl(:M1s1)
        q = first(@variables q(..)::Int32 [input = true])
        @parameters cR[1:4] = [0.0, 1.0, 0.5, 0.0]
        qe = q(t, x, y)
        sys = PDESystem([D(cs1(t, x, y)) ~ -cs1(t, x, y), K1(t, x, y) ~ (qe == 1) + 0.5 * (qe == 2), K2(t, x, y) ~ at(cR, qe + 1),
                M0(t, x, y) ~ (qe == 0), M1(t, x, y) ~ (qe != 0)], [cs1(0, x, y) ~ 0.0], cdom(), [t, x, y],
            [cs1(t, x, y), K1(t, x, y), K2(t, x, y), M0(t, x, y), M1(t, x, y), qe], [cR]; name = :s1)
        s = solve(cown(sys, CDIMS; ins = [qe => Q]), ExplicitEuler(; dt = 0.5))
        r(v) = s[v(t, x, y), length(s.t)]
        @test r(K1) == r(K2) == [0.0, 1.0, 0.5, 0.0][Qc .+ 1]
        @test r(M0) + r(M1) == ones(4, 4) && r(M0) == Float64.(Qc .== 0)
        # S2: a kind-dependent face coefficient (and a real one) at a face of the box equals the
        # hand-coarsened twin bitwise: the neighbor block clamped in the coarse frame (base
        # cb20be97, ~/lpwork/f3b6r-nc-s2.log: the fine-frame clamp reads the boundary layer)
        Ki = 0.5 .+ rand(Xoshiro(41), 16, 16)
        @parameters cKv[1:4] = [1.0, 4.0, 0.25, 2.0]
        ki = first(@variables ki(..) [input = true])
        for (lab, K, insf, insc) in (("kind", qq -> at(cKv, qq + 1), [qe => Q, ki(t, x, y) => Ki], [qe => Qc, ki(t, x, y) => cmean(Ki)]),
                                     ("real", qq -> ki(t, x, y), [qe => Q, ki(t, x, y) => Ki], [qe => Qc, ki(t, x, y) => cmean(Ki)]))
            c2 = lvl(Symbol(:cs2, lab))
            ch = first(@variables chs2(..))
            tsys(c) = PDESystem([D(c(t, x, y)) ~ 0.05 * DivKGrad(:harmonic)(K(qe), c(t, x, y)) - c(t, x, y)],
                [c(0, x, y) ~ x * y, c(t, 0, y) ~ 1.0, c(t, 1, y) ~ 0.0], cdom(), [t, x, y], [c(t, x, y), qe, ki(t, x, y)], [cKv];
                name = :s2)
            for alg in (ExplicitEuler(; dt = 0.05, substeps = 4), BackwardEuler(; dt = 0.05))
                sc, sh = solve(cown(tsys(c2), CDIMS; ins = insf), alg), solve(cown(tsys(ch), CDIMS .÷ CK; ins = insc), alg)
                @test sc[c2(t, x, y), length(sc.t)] == sh[ch(t, x, y), length(sh.t)] ||
                      (println("S2 ", lab, " ", alg, " ", maximum(abs, sc[c2(t, x, y), length(sc.t)] .- sh[ch(t, x, y), length(sh.t)])); false)
            end
        end
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
        dsys(c) = PDESystem([D(c(t, x, y)) ~ 0.02 * Δ(c(t, x, y)) - c(t, x, y) * ismember(q(t, x, y), (2,)) + 0.5 * (q(t, x, y) == 1) +
                              0.05 * g(t, x, y)],
            [c(0, x, y) ~ x + y, c(t, x, y) ~ masked(q(t, x, y) == 3, 1.0)], cdom(), [t, x, y],
            [c(t, x, y), cdm(t, x, y), q(t, x, y), g(t, x, y)], Num[]; name = :dm)
        pc = cown(dsys(cdo), CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1, g(t, x, y) => CG])
        ph = cown(dsys(cdh), CDIMS .÷ CK; domain = cdm, ins = [cdm(t, x, y) => Dc, q(t, x, y) => CQ1c, g(t, x, y) => cmean(CG)])
        for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05), CrankNicolson(; dt = 0.05))
            sc, sh = solve(pc, alg), solve(ph, alg)
            @test sc[cdo(t, x, y), length(sc.t)] == sh[cdh(t, x, y), length(sh.t)]
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
        # a spatial operator of a coarse field in a fine row: no single meaning; the route (an aux
        # field on the coarse grid) works and reads the coarse Laplacian at each block
        u = first(@variables uref(..))
        L = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables Lref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        bad = PDESystem([D(cc(t, x, y)) ~ 0.01 * Δ(cc(t, x, y)), D(u(t, x, y)) ~ Δ(cc(t, x, y))],
            [cc(0, x, y) ~ x, u(0, x, y) ~ 0.0], cdom(), [t, x, y], [cc(t, x, y), u(t, x, y)], Num[]; name = :b)
        m = cmsg(() -> cown(bad, (16, 16)))
        @test occursin("a spatial operator reads its field on that field's own grid", m) && occursin("`L ~ Δ(cref)`", m)
        good = PDESystem([D(cc(t, x, y)) ~ 0.01 * Δ(cc(t, x, y)), L(t, x, y) ~ Δ(cc(t, x, y)), D(u(t, x, y)) ~ L(t, x, y)],
            [cc(0, x, y) ~ x^2, u(0, x, y) ~ 0.0], cdom(), [t, x, y], [cc(t, x, y), L(t, x, y), u(t, x, y)], Num[]; name = :g)
        sg = solve(cown(good, (16, 16)), ExplicitEuler(; dt = 0.01, substeps = 1); saveat = [0.01])
        @test size(sg[L(t, x, y), 1]) == (4, 4) && size(sg[u(t, x, y), 2]) == (16, 16)
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
