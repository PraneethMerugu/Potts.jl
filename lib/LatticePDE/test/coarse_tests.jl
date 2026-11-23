# `[lattice_level = Coarse(k)]` in the IR and LatticePDE. A
# coarse field lives on level log2(k) of the program's hierarchy: its rate, conditions,
# masks, operator (`jac:`) and residual kernels run there with the spacing `k h`, and its
# fine reads (the inputs, an irregular domain) are folded over each node's block (every fine
# read, an integer input too, by the mean of the part of the term that reads it; the domain
# by Majority). A field with a mask whose predicate reads fine fields blends: a node is
# masked when its whole block is, and elsewhere its equation folds over the block's free
# children (the node holds the value of its free part). The oracle is the hand-coarsened
# problem: the same system discretized on the coarse grid, with its inputs folded by hand (a
# kind expression as the real input of its mean over the free children, the mask's kind only
# on whole blocks); the two agree to rounding under every algorithm. Before the fix
# (85794414): `Coarse` is not defined, and `lattice_level` was refused ("does not lower"),
# so every testset errors.

@testsetup module LP_coarse
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
# imports an earlier file made in the old single Main
using LinearAlgebra: LinearAlgebra
using Random: Random
include("shared/preamble.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/params.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/grids.jl")
include("shared/maskswitch.jl")
include("shared/numbers.jl")
include("shared/coarse.jl")
include("shared/export_all.jl")
end

@testitem "Coarse(1) is the lattice itself, bitwise" setup = [LP_coarse] tags = [
    :latticepde, :coarse,
] begin
    using .LP_coarse: fd
    @testset "Coarse(1) is the lattice itself, bitwise" begin
        # (distinct names per testset: SymbolicUtils interns an applied term `c(t, x, y)`
        # whatever its function's metadata, so a name reused in a session can drop it)
        c1 = first(@variables cone(..) [lattice_level = Coarse(1)])
        c0 = first(@variables cnil(..))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        p1 = cown(csys(c1, q, g), CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => CG])
        p0 = cown(csys(c0, q, g), CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => CG])
        @test replace(sprint(print_program, p1.program), "cone" => "cnil") ==
            sprint(print_program, p0.program)
        for (alg, dt) in ((ExplicitEuler(), 0.01), (BackwardEuler(), 0.05))
            s1, s0 = solve(p1, alg; dt), solve(p0, alg; dt)
            @test s1[c1(t, x, y), length(s1.t)] == s0[c0(t, x, y), length(s0.t)]
        end
        @test_throws ArgumentError Coarse(3)
        @test occursin("power of two", cmsg(() -> Coarse(0)))
    end
end

@testitem "a coarse field equals the hand-coarsened problem under every algorithm" setup = [
    LP_coarse,
] tags = [
    :latticepde, :coarse,
] begin
    using .LP_coarse: fd
    @testset "a coarse field equals the hand-coarsened problem under every algorithm" begin
        # (blocks are mixed: the mean is not the majority; blocks are masked, free and
        # blended)
        @test sum(Float64.(CQ1 .== 2)) != 16 * sum(CQ1c .== 2)
        @test sort(unique(16 .- cnfree(CQB1 .== 3))) ==
            [0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 12, 14, 15, 16]
        pc, ph, (c, ch, q, g) = ctwins()
        @test size(pc.u0) == (16,) && length(ph.u0) == 16
        # the initial values at the node centers
        @test pc.u0 == ph.u0
        # the stability bound reads the coarse spacing: the automatic counts agree
        @test LatticePDE.Problems.substeps(pc, ExplicitEuler(); dt = 0.05) ==
            LatticePDE.Problems.substeps(ph, ExplicitEuler(); dt = 0.05)
        for alg in (
                ExplicitEuler(), BackwardEuler(), CrankNicolson(), BDF2(),
                BackwardEuler(; init = :steady), ExplicitEuler(; lower_bound = 0.0),
                BackwardEuler(; linsolve = LatticeMultigrid(; cycles = 4)),
            )
            ic, ih = init(pc, alg; dt = 0.05), init(ph, alg; dt = 0.05)
            for n in 1:6
                # the mask moves
                if n == 4
                    ic[q(t, x, y)] = CQB2
                    ih[q(t, x, y)] = cwhole(CQB2)
                    ih[g(t, x, y)] = cfree(CG, CQB2 .== 3)
                    foreach(((v, a),) -> ih[v] = a, chand(CQB2))
                end
                step!(ic)
                step!(ih)
            end
            # in progress
            @test ic.retcode == ih.retcode == SciMLBase.ReturnCode.Default
            @test size(ic[c(t, x, y)]) == (4, 4)
            @test capprox(
                ic[c(t, x, y)], ih[ch(t, x, y)]; rtol = alg isa ExplicitEuler ?
                    1.0e-13 : 1.0e-10
            )
            @test LatticePDE.substep_counts(ic) == LatticePDE.substep_counts(ih)
        end
        # the masked nodes hold the masked value, and only where the whole block is kind 3
        # (15 of 16 sites leave the node free)
        ic = init(pc, BackwardEuler(); dt = 0.05)
        step!(ic)
        whole = cwhole(CQB1) .== 3
        @test count(whole) == 2 && all(ic[c(t, x, y)][whole] .== 1.0) &&
            all(ic[c(t, x, y)][.!whole] .!= 1.0)
    end
end

@testitem "steady rows, number types and the ODE path on a coarse grid" setup = [
    LP_coarse,
] tags = [
    :latticepde, :coarse,
] begin
    using .LP_coarse: fd
    @testset "steady rows, number types and the ODE path on a coarse grid" begin
        pc, ph, (c, ch, _...) = ctwins(; steady = true)
        sc, sh = solve(pc, QuasiSteady(); dt = 0.1), solve(ph, QuasiSteady(); dt = 0.1)
        @test capprox(
            sc[c(t, x, y), length(sc.t)], sh[ch(t, x, y), length(sh.t)];
            rtol = 1.0e-10
        )
        pc, ph, (c, ch, _...) = ctwins(; T = Float32)
        @test eltype(pc.u0) == Float32
        for alg in (ExplicitEuler(), BackwardEuler())
            sc, sh = solve(pc, alg; dt = 0.05), solve(ph, alg; dt = 0.05)
            @test capprox(
                sc[c(t, x, y), length(sc.t)], sh[ch(t, x, y), length(sh.t)];
                rtol = 1.0e-5
            )
        end
        # a declared storage on the owned path
        pc, ph, (c, ch, _...) = ctwins(; storage = Float32)
        for alg in (ExplicitEuler(), BackwardEuler())
            sc, sh = solve(pc, alg; dt = 0.05), solve(ph, alg; dt = 0.05)
            @test eltype(sc[c(t, x, y), 1]) == Float32
            @test capprox(
                sc[c(t, x, y), length(sc.t)], sh[ch(t, x, y), length(sh.t)];
                rtol = 1.0e-5
            )
        end
        # F3-ghost on the coarse grid: a face coefficient that reads the field takes its
        # ghost value at a Dirichlet face (the coarse ghost, from the coarse spacing)
        cgh = Symbolics.wrap(
            SymbolicUtils.setmetadata(
                unwrap(first(@variables cghost(..))), LatticePDE.LatticeLevel, Coarse(CK)
            )
        )
        hgh = first(@variables hghost(..))
        function gsys(c)
            return PDESystem(
                [
                    D(c(t, x, y)) ~
                        DivKGrad(:harmonic)(0.02 * (1 + c(t, x, y)), c(t, x, y)) -
                        c(t, x, y),
                ],
                [
                    c(0, x, y) ~ x * y, c(t, 0, y) ~ 2.0,
                    0.5 * c(t, 1, y) + Differential(x)(c(t, 1, y)) ~ 0.1,
                ], cdom(), [
                    t, x, y,
                ],
                [c(t, x, y)], Num[]; name = :gh
            )
        end
        for alg in (ExplicitEuler(; substeps = 4), BackwardEuler())
            sc, sh = solve(cown(gsys(cgh), CDIMS), alg; dt = 0.05),
                solve(cown(gsys(hgh), CDIMS .÷ CK), alg; dt = 0.05)
            @test sc[cgh(t, x, y), length(sc.t)] == sh[hgh(t, x, y), length(sh.t)]
        end
        # problem = :ode: the coarse right side is the hand problem's (no masks there)
        cc = Symbolics.wrap(
            SymbolicUtils.setmetadata(
                unwrap(first(@variables codec(..))), LatticePDE.LatticeLevel, Coarse(CK)
            )
        )
        ch2 = first(@variables codeh(..))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        function osys(c, k2, extra)
            return PDESystem(
                [
                    D(c(t, x, y)) ~
                        cD * laplacian(c(t, x, y)) - ckd * c(t, x, y) * k2 + 0.05 *
                        g(t, x, y),
                ],
                [c(0, x, y) ~ x * y], cdom(), [t, x, y], [c(t, x, y), g(t, x, y), extra], [
                    cD, ckd,
                ]; name = :os
            )
        end
        oc = discretize(
            osys(cc, ismember(q(t, x, y), (2,)), q(t, x, y)),
            LatticeDiscretization(Grid(CDIMS));
            inputs = [q(t, x, y) => CQ1, g(t, x, y) => CG]
        )
        oh = discretize(
            osys(ch2, cf2(t, x, y), cf2(t, x, y)), LatticeDiscretization(Grid(CDIMS .÷ CK));
            inputs = [cf2(t, x, y) => cmean(Float64.(CQ1 .== 2)), g(t, x, y) => cmean(CG)]
        )
        du1, du2 = similar(oc.u0), similar(oh.u0)
        oc.f(du1, oc.u0, oc.p, 0.0)
        oh.f(du2, oh.u0, oh.p, 0.0)
        @test capprox(du1, du2; rtol = 1.0e-14)
    end
end

@testitem "the folds: the restriction conserves mass, kind expressions included" setup = [
    LP_coarse,
] tags = [
    :latticepde, :coarse,
] begin
    using .LP_coarse: fd
    @testset "the folds: the restriction conserves mass, kind expressions included" begin
        # an aux field of a real input, `K ~ g`: Σ K · k² is the fine sum (the block mean)
        K = Symbolics.wrap(
            SymbolicUtils.setmetadata(
                unwrap(first(@variables Kmass(..))), LatticePDE.LatticeLevel, Coarse(CK)
            )
        )
        c = Symbolics.wrap(
            SymbolicUtils.setmetadata(
                unwrap(first(@variables cmass(..))), LatticePDE.LatticeLevel, Coarse(CK)
            )
        )
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        G = rand(Xoshiro(3), 16, 16)
        sys = PDESystem(
            [
                D(c(t, x, y)) ~ g(t, x, y), K(t, x, y) ~
                    g(t, x, y) + ismember(q(t, x, y), (2,)),
            ],
            [c(0, x, y) ~ 0.0], cdom(), [t, x, y],
            [c(t, x, y), K(t, x, y), q(t, x, y), g(t, x, y)], Num[]; name = :m
        )
        p = cown(sys, CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => G])
        s = solve(p, ExplicitEuler(); dt = 0.25)
        Kv = s[K(t, x, y), length(s.t)]
        @test size(Kv) == (4, 4)
        # the means (the kind's too)
        @test sum(Kv) * CK^2 ≈ sum(G) + count(==(2), CQ1) rtol = 1.0e-14
        # Σ over the run (t = 1)
        @test sum(s[c(t, x, y), length(s.t)]) * CK^2 ≈ sum(G) rtol = 1.0e-13
        # 3D, factor 2: 8 children per node
        c3 = Symbolics.wrap(
            SymbolicUtils.setmetadata(
                unwrap(first(@variables cmass3(..))), LatticePDE.LatticeLevel, Coarse(2)
            )
        )
        @parameters z
        g3 = first(@variables g(..) [input = true])
        sys3 = PDESystem(
            [D(c3(t, x, y, z)) ~ g3(t, x, y, z)], [c3(0, x, y, z) ~ 0.0],
            [
                t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0),
                y ∈ Interval(0.0, 1.0), z ∈ Interval(0.0, 1.0),
            ], [t, x, y, z],
            [c3(t, x, y, z), g3(t, x, y, z)], Num[]; name = :m3
        )
        G3 = rand(Xoshiro(4), 4, 6, 8)
        s3 = solve(
            cown(sys3, (4, 6, 8); ins = [g3(t, x, y, z) => G3]), ExplicitEuler();
            dt = 0.5
        )
        v3 = s3[c3(t, x, y, z), length(s3.t)]
        @test size(v3) == (2, 3, 4)
        @test sum(v3) * 8 ≈ sum(G3) rtol = 1.0e-13
        @test v3[2, 3, 4] ≈ sum(G3[3:4, 5:6, 7:8]) / 8 rtol = 1.0e-14
    end
end

@testitem "a nonlinear fine read is restricted by the mean of the whole subterm" setup = [
    LP_coarse,
] tags = [
    :latticepde, :coarse,
] begin
    using .LP_coarse: fd
    @testset "a nonlinear fine read is restricted by the mean of the whole subterm" begin
        # `D(c) ~ f` on Coarse(4) over 16²: Σ c · k² after t = 1 is the fine Σ f (before the
        # fix, cb20be97: `f(mean g)`, off by −25% for g², −75% for max(g − 0.5, 0), −4% for
        # exp(g), +2% for value_at(S, q) g, +25% for g/(0.2 + g))
        q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
        G = rand(Xoshiro(5), 16, 16)
        S = Float64[1.0, 2.0, 5.0, 3.0]
        srcs = [
            (qe, ge) -> ge => sum(G), (qe, ge) -> max(ge - 0.5, 0) =>
                sum(max.(G .- 0.5, 0)),
            (qe, ge) -> ge^2 => sum(G .^ 2), (qe, ge) -> exp(ge) => sum(exp.(G)),
            (qe, ge) -> value_at(cSv, qe + 1) * ge => sum(S[CQ1 .+ 1] .* G), (
                qe, ge
            ) -> ge / (0.2 + ge) => sum(G ./ (0.2 .+ G)),
        ]
        for (i, f) in enumerate(srcs)
            c = Symbolics.wrap(
                SymbolicUtils.setmetadata(
                    unwrap(
                        Symbolics.variable(
                            Symbol(:cm2_, i); T = SymbolicUtils.FnType{
                                Tuple, Real, Nothing,
                            }
                        )
                    ),
                    LatticePDE.LatticeLevel, Coarse(CK)
                )
            )
            src, want = f(q(t, x, y), g(t, x, y))
            sys = PDESystem(
                [D(c(t, x, y)) ~ src], [c(0, x, y) ~ 0.0], cdom(), [t, x, y],
                [c(t, x, y), q(t, x, y), g(t, x, y)],
                [cSv]; name = :m2
            )
            s = solve(
                cown(sys, CDIMS; ins = [q(t, x, y) => CQ1, g(t, x, y) => G]),
                ExplicitEuler(); dt = 0.25
            )
            got = sum(s[c(t, x, y), length(s.t)]) * CK^2
            @test isapprox(got, want; rtol = 1.0e-13) ||
                (println("M2 ", src, ": ", got, " ", want); false)
        end
    end
end

@testitem "a kind expression folds by its block mean (blocks a kind covers in part); the \
    coarse-frame clamp" setup = [LP_coarse] tags = [
    :latticepde, :coarse,
] begin
    using .LP_coarse: fd
    @testset "a kind expression folds by its block mean (blocks a kind covers in part); \
        the coarse-frame clamp" begin
        # blocks with ties and mixes: 8 P + 8 Q, 9 P + 7 Q, 6 P + 6 Q + 4 medium, 8 medium +
        # 8 Q, 8 Q + 8 N, ... Every spelling of a kind-dependent rate is the block mean of
        # its fine values, so the coarse total times the block size is the fine total
        # (exact: the means are multiples of 1/16) and complementary conditions sum to 1.
        # Base 5e972579: the block's plurality owner, off by up to the full rate
        Q = CQT
        function lvl(n)
            return Symbolics.wrap(
                SymbolicUtils.setmetadata(
                    unwrap(
                        Symbolics.variable(
                            n; T = SymbolicUtils.FnType{
                                Tuple, Real, Nothing,
                            }
                        )
                    ),
                    LatticePDE.LatticeLevel, Coarse(CK)
                )
            )
        end
        cs1, K1, K2, M0, M1 = lvl(:cs1), lvl(:K1s1), lvl(:K2s1), lvl(:M0s1), lvl(:M1s1)
        q = first(@variables q(..)::Int32 [input = true])
        @parameters cR[1:4] = [0.0, 1.0, 0.5, 0.0]
        qe = q(t, x, y)
        sys = PDESystem(
            [
                D(cs1(t, x, y)) ~ (qe == 1) + 0.5 * (qe == 2), K1(t, x, y) ~
                    (qe == 1) + 0.5 * (qe == 2),
                K2(t, x, y) ~ value_at(cR, qe + 1),
                M0(t, x, y) ~ (qe == 0), M1(t, x, y) ~ (qe != 0),
            ], [cs1(0, x, y) ~ 0.0], cdom(), [t, x, y],
            [cs1(t, x, y), K1(t, x, y), K2(t, x, y), M0(t, x, y), M1(t, x, y), qe], [cR];
            name = :s1
        )
        s = solve(cown(sys, CDIMS; ins = [qe => Q]), ExplicitEuler(); dt = 0.5)
        r(v) = s[v(t, x, y), length(s.t)]
        fine = [0.0, 1.0, 0.5, 0.0][Q .+ 1]
        @test r(K1) == r(K2) == cmean(fine)
        # conservation, exact
        @test sum(r(K1)) * CK^2 == sum(fine)
        # the source over t = 1
        @test sum(r(cs1)) * CK^2 == sum(fine)
        @test r(M0) + r(M1) == ones(4, 4) && r(M0) == cmean(Float64.(Q .== 0))
        # (blocks a kind covers in part)
        @test any(v -> 0 < v < 1, r(M0)) && any(v -> !(v in (0.0, 0.5, 1.0)), r(K1))
        # an indicator as an operator coefficient (`DivKGrad(ismember(kind, …), c)`) folds
        # by its mean at each face as a real input of the block means does
        cop, hop = lvl(:cops1), first(@variables hops1(..))
        kf = first(@variables kf(..) [input = true, bounds = (0, 1)])
        function osys(c, K, dvs)
            return PDESystem(
                [D(c(t, x, y)) ~ 0.05 * DivKGrad(:arithmetic)(0.5 + K, c(t, x, y))],
                [c(0, x, y) ~ x * y], cdom(), [t, x, y], [c(t, x, y); dvs], Num[];
                name = :ops1
            )
        end
        so = solve(
            cown(osys(cop, ismember(qe, (1, 2)), [qe]), CDIMS; ins = [qe => Q]),
            ExplicitEuler(; substeps = 4); dt = 0.05
        )
        sh = solve(
            cown(
                osys(hop, kf(t, x, y), [kf(t, x, y)]), CDIMS .÷ CK;
                ins = [kf(t, x, y) => cmean(Float64.(1 .<= Q .<= 2))]
            ),
            ExplicitEuler(; substeps = 4)
            ; dt = 0.05
        )
        @test capprox(
            so[cop(t, x, y), length(so.t)], sh[hop(t, x, y), length(sh.t)];
            rtol = 1.0e-14
        )
        # S2: a kind-dependent face coefficient (and a real one) at a face of the box equals
        # the hand-coarsened twin bitwise: the neighbor block clamped in the coarse frame
        # (base cb20be97: the fine-frame clamp reads the boundary layer)
        Ki = 0.5 .+ rand(Xoshiro(41), 16, 16)
        @parameters cKv[1:4] = [1.0, 4.0, 0.25, 2.0]
        ki = first(@variables ki(..) [input = true])
        # (the kind case: the twin reads the block means of `value_at(cKv, q + 1)` as the
        # real input `ki`)
        for (lab, K, insf, insc) in (
                (
                    "kind", qq -> value_at(cKv, qq + 1), [qe => Q, ki(t, x, y) => Ki],
                    [
                        qe => Q[1:4, 1:4],
                        ki(t, x, y) => cmean([1.0, 4.0, 0.25, 2.0][Q .+ 1]),
                    ],
                ),
                (
                    "real", qq -> ki(t, x, y), [qe => Q, ki(t, x, y) => Ki],
                    [qe => Q[1:4, 1:4], ki(t, x, y) => cmean(Ki)],
                ),
            )
            c2 = lvl(Symbol(:cs2, lab))
            ch = first(@variables chs2(..))
            function tsys(c, Kx)
                return PDESystem(
                    [
                        D(c(t, x, y)) ~
                            0.05 * DivKGrad(:harmonic)(Kx, c(t, x, y)) - c(t, x, y),
                    ],
                    [c(0, x, y) ~ x * y, c(t, 0, y) ~ 1.0, c(t, 1, y) ~ 0.0], cdom(), [
                        t, x, y,
                    ], [c(t, x, y), qe, ki(t, x, y)], [cKv];
                    name = :s2
                )
            end
            for alg in (ExplicitEuler(; substeps = 4), BackwardEuler())
                sc, sh = solve(cown(tsys(c2, K(qe)), CDIMS; ins = insf), alg; dt = 0.05),
                    solve(
                        cown(tsys(ch, ki(t, x, y)), CDIMS .÷ CK; ins = insc), alg;
                        dt = 0.05
                    )
                @test sc[c2(t, x, y), length(sc.t)] == sh[ch(t, x, y), length(sh.t)] ||
                    (
                    println(
                        "S2 ",
                        lab,
                        " ",
                        alg,
                        " ",
                        maximum(
                            abs, sc[c2(t, x, y), length(sc.t)] .-
                                sh[ch(t, x, y), length(sh.t)]
                        )
                    );
                    false
                )
            end
        end
    end
end
