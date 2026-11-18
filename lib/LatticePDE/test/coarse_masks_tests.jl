# Split from coarse_tests.jl (Wave T3b); uses LP_coarse setup.

@testitem "F3-16: F4-15b: a mask blends on the blocks it covers in part" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
    @testset "F4-15b: a mask blends on the blocks it covers in part" begin
        # A mask `masked(q == 0, v)` on Coarse(4): a node is masked where its whole block is kind 0;
        # elsewhere it holds the value of its free part (the children with q ≠ 0), its equation folded
        # over them. Base 7d101740 (~/lpwork/f4F15b/nc.log): the mask folds by Majority, so a node
        # with 9 or more medium children is held and its sources are lost, and the others fold over
        # the whole block.
        lvl(n) = Symbolics.wrap(
            SymbolicUtils.setmetadata(
                unwrap(Symbolics.variable(n; T = SymbolicUtils.FnType{Tuple, Real, Nothing})),
                LatticePDE.LatticeLevel, Coarse(CK)
            )
        )
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
        sys(c, v) = PDESystem(
            [D(c(t, x, y)) ~ S * (qe == 1) + 0.25 * (qe == 2) * c(t, x, y)], [c(0, x, y) ~ 0.0, c(t, x, y) ~ masked(qe == 0, v)],
            cdom(), [t, x, y], [c(t, x, y), qe], Num[]; name = :b15
        )
        op = discretize(sys(csrc, 0.5), LatticeDiscretization(Grid(CDIMS)); inputs = [qe => Q])
        du = similar(op.u0); op.f(du, zero(op.u0), op.p, 0.0)
        du = reshape(du, 4, 4)
        # one blended node by hand: the rate is the mean over its free children, S #(q == 1) / #free
        for I in CartesianIndices(nf)
            nf[I] in (0, 16) && continue
            blk = Q[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]
            @test du[I] ≈ S * count(==(1), blk) / nf[I] rtol = 1.0e-15
        end
        # conservation: the free volume times the rate is the fine source total (every source site
        # is free); the Majority fold lost the sources of the blocks with 9 or more medium sites
        @test sum(nf[I] * du[I] for I in eachindex(nf) if nf[I] > 0) ≈ S * count(==(1), Q) rtol = 1.0e-14
        for alg in (ExplicitEuler(), BackwardEuler())
            ic = init(cown(sys(csrc, 0.5), CDIMS; ins = [qe => Q]), alg; dt = 0.25)
            for _ in 1:4
                step!(ic)
            end
            u1 = ic[csrc(t, x, y)]
            @test all(u1[nf .== 0] .== 0.5)                                    # the masked nodes hold the value
            # the free content Σ #free u grows by the source and by the decay of the free part:
            # with c(0) = 0 and no diffusion each free node is the scalar ODE u' = a + b u
            a = [
                nf[I] == 0 ? 0.0 : S * count(==(1), Q[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]) / nf[I]
                    for I in CartesianIndices(nf)
            ]
            b = [
                nf[I] == 0 ? 0.0 : 0.25 * count(==(2), Q[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]) / nf[I]
                    for I in CartesianIndices(nf)
            ]
            ns = 4 * only(LatticePDE.substep_counts(ic))
            h = 1.0 / ns
            # (each substep: ExplicitEuler u + h(a + bu), BackwardEuler (u + ha)/(1 − hb))
            want = zeros(4, 4)
            for _ in 1:ns
                want = alg isa ExplicitEuler ? want .+ h .* (a .+ b .* want) : (want .+ h .* a) ./ (1 .- h .* b)
            end
            m = nf .> 0
            @test isapprox(u1[m], want[m]; rtol = 1.0e-12) || (println("F4-15b scalar ", alg, ": ", maximum(abs, u1[m] .- want[m])); false)
        end
        # f = 0 and f = 1: a node no child of which is held folds over the whole block bitwise (the
        # rate equals the unmasked system's), a node all of whose children are held is masked
        cnm = lvl(:cb15nomask)
        sysn = PDESystem(
            [D(cnm(t, x, y)) ~ S * (qe == 1) + 0.25 * (qe == 2) * cnm(t, x, y)], [cnm(0, x, y) ~ 0.0], cdom(), [t, x, y],
            [cnm(t, x, y), qe], Num[]; name = :b15n
        )
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
            hs = PDESystem(
                [D(c(t, x, y)) ~ (qe == 1)], [c(0, x, y) ~ 0.0, c(t, x, y) ~ masked(pr, 9.0)], cdom(), [t, x, y],
                [c(t, x, y), qe], Num[]; name = :b15h
            )
            sl = solve(cown(hs, CDIMS; ins = [qe => Qh]), ExplicitEuler(); dt = 0.5)
            v = sl[c(t, x, y), length(sl.t)]
            @test v[1, 1] == want                                           # (t = 1: the free part's mean source)
        end
        # the ODE path (`discretize`'s right side) and every stepper of the owned path equal the
        # hand-coarsened twin on blended nodes ("a coarse field equals the hand-coarsened problem")
        cod, hod = lvl(:cb15ode), first(@variables hb15ode(..))
        kq = first(@variables kq(..) [input = true, bounds = (0, 1)])
        osys(c, k1, mq, dvs) = PDESystem(
            [D(c(t, x, y)) ~ 0.02 * laplacian(c(t, x, y)) - c(t, x, y) * k1 + 0.3 * k1],
            [c(0, x, y) ~ x * y, c(t, x, y) ~ masked(mq == 0, 0.5)], cdom(), [t, x, y], [c(t, x, y); dvs], Num[]; name = :b15o
        )
        oc = discretize(osys(cod, qe == 2, qe, [qe]), LatticeDiscretization(Grid(CDIMS)); inputs = [qe => Q])
        oh = discretize(
            osys(hod, kq(t, x, y), qe, [kq(t, x, y), qe]), LatticeDiscretization(Grid(CDIMS .÷ CK));
            inputs = [kq(t, x, y) => cfree(Float64.(Q .== 2), held), qe => Int32[n == 0 ? 0 : 1 for n in nf]]
        )
        d1, d2 = similar(oc.u0), similar(oh.u0)
        oc.f(d1, oc.u0, oc.p, 0.0); oh.f(d2, oh.u0, oh.p, 0.0)
        @test capprox(d1, d2; rtol = 1.0e-14)

    end

end

@testitem "F3-16: F4-15b: the free fold intersects the irregular domain" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
    @testset "F4-15b: the free fold intersects the irregular domain" begin
        # (ruling 2026-11-12: the free support is free ∩ in-domain; with no in-domain free child
        # the mean is over the in-domain children; an out-of-domain child never contributes. A
        # non-twin test: a hand value that the pre-fix fold misses, because the twin would
        # reproduce whatever the fold does. At 721d1efb (~/lpwork/f4F15b/cdom-nc.log) the two
        # cases read 100.0 and 44.875.)
        qd = first(@variables qd(..)::Int32 [input = true])
        kd = first(@variables kd(..) [input = true, bounds = (0, 100)])
        dmd = first(@variables dmd(..)::Bool [input = true])
        cdf = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cdomfree(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        Qd = fill(Int32(1), CDIMS); Kd = zeros(Float64, CDIMS); Dd = trues(CDIMS)
        sites(J) = [((J[1] - 1) * CK + i, (J[2] - 1) * CK + j) for j in 1:CK for i in 1:CK]
        # block (1, 1): 9 in-domain children, all masked (q = 0), kd 1..9; 7 out-of-domain
        # children, free (q = 1), kd 100. The support free ∩ in-domain is empty, so the value is
        # the mean over the 9 in-domain children, 5; the pre-fix fold read the 7 free
        # out-of-domain children, 100.
        for (n, s) in enumerate(sites((1, 1)))
            Qd[s...] = n <= 9 ? 0 : 1
            Kd[s...] = n <= 9 ? Float64(n) : 100.0
            Dd[s...] = n <= 9
        end
        # block (2, 1): 9 in-domain free children carry kd = 2; 7 out-of-domain free children
        # carry kd = 100. The support is the 9 in-domain free children, 2; the pre-fix fold took
        # all 16 free children, 44.875.
        for (n, s) in enumerate(sites((2, 1)))
            Qd[s...] = 1
            Kd[s...] = n <= 9 ? 2.0 : 100.0
            Dd[s...] = n <= 9
        end
        dsys(c) = PDESystem(
            [D(c(t, x, y)) ~ kd(t, x, y)], [c(0, x, y) ~ 0.0, c(t, x, y) ~ masked(qd(t, x, y) == 0, 1.0)],
            cdom(1.0e-6), [t, x, y], [c(t, x, y), dmd(t, x, y), qd(t, x, y), kd(t, x, y)], Num[]; name = :df
        )
        p = cown(dsys(cdf), CDIMS; domain = dmd, ins = [dmd(t, x, y) => Dd, qd(t, x, y) => Qd, kd(t, x, y) => Kd])
        # (u0 = 0, one explicit window: the state is h times the rate)
        s = solve(p, ExplicitEuler(; substeps = 1); dt = 1.0e-6)
        d = Array(s[cdf(t, x, y), length(s.t)]) ./ 1.0e-6
        @test isapprox(d[1, 1], 5.0; rtol = 1.0e-14) || (println("F4-15b domain case 1: ", d[1, 1], " (want 5: the in-domain children, not the free out-of-domain ones)"); false)
        @test isapprox(d[2, 1], 2.0; rtol = 1.0e-14) || (println("F4-15b domain case 2: ", d[2, 1], " (want 2: free ∩ in-domain)"); false)
    end

end

@testitem "F3-16: F4-15b review: the support is free ∩ in-domain, not one or the other" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
    @testset "F4-15b review: the support is free ∩ in-domain, not one or the other" begin
        # (review should-fix 1: a block whose free set and in-domain set are both proper subsets,
        # with masked-in, free-in, free-out and masked-out children. The fold reads the free-in
        # children only; the committed hand cases put the free set outside the domain or the
        # in-domain set wholly masked.)
        qd = first(@variables pr15qd(..)::Int32 [input = true])
        kd = first(@variables pr15kd(..) [input = true, bounds = (0, 100)])
        dmd = first(@variables pr15dmd(..)::Bool [input = true])
        cdf = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables pr15cdf(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        psites(J) = [((J[1] - 1) * CK + i, (J[2] - 1) * CK + j) for j in 1:CK for i in 1:CK]
        Qd = fill(Int32(1), CDIMS); Kd = fill(1.0, CDIMS); Dd = trues(CDIMS)
        # (block, in-domain children, free children, kd of free-in / masked-in / free-out / masked-out)
        plan = (
            ((1, 1), 1:13, [1, 2, 3, 14, 15], (2.0, 50.0, 100.0, 7.0)),
            ((2, 1), 1:12, [1, 2, 5, 9, 13, 14], (2.0, 50.0, 100.0, 7.0)),
            ((1, 2), 1:13, [2, 4, 6, 14, 15, 16], (3.0, 50.0, 100.0, 7.0)),
            ((2, 2), 1:16, 1:16, (4.0, 50.0, 100.0, 7.0)),
        )
        want = Dict{Tuple{Int, Int}, Float64}()
        for (J, ins, frs, (kfi, kmi, kfo, kmo)) in plan
            for (n, s) in enumerate(psites(J))
                inb, free = n in ins, n in frs
                Qd[s...] = free ? 1 : 0
                Kd[s...] = free ? (inb ? kfi : kfo) : (inb ? kmi : kmo)
                Dd[s...] = inb
            end
            want[Tuple(J)] = kfi
        end
        dsys(c) = PDESystem(
            [D(c(t, x, y)) ~ kd(t, x, y)],
            [c(0, x, y) ~ 0.0, c(t, x, y) ~ masked(qd(t, x, y) == 0, 1.0)], cdom(1.0e-6), [t, x, y],
            [c(t, x, y), dmd(t, x, y), qd(t, x, y), kd(t, x, y)], Num[]; name = :pr15
        )
        p = cown(dsys(cdf), CDIMS; domain = dmd, ins = [dmd(t, x, y) => Dd, qd(t, x, y) => Qd, kd(t, x, y) => Kd])
        s = solve(p, ExplicitEuler(; substeps = 1); dt = 1.0e-6)
        d = Array(s[cdf(t, x, y), length(s.t)]) ./ 1.0e-6
        for (J, v) in want
            @test isapprox(d[J...], v; rtol = 1.0e-14) ||
                (
                println(
                    "F4-15b P1 block ", J, ": ", d[J...], " (want ", v, " = free ∩ in-domain; the in-domain mean ",
                    cinfree(Kd, Qd .== 0, Dd)[J...], ", the free mean ", cfree(Kd, Qd .== 0)[J...],
                    ", the whole mean ", cmean(Kd)[J...], ")"
                ); false
            )
        end
        # on the straddling blocks the intersection is neither the free mean nor the in-domain mean
        for J in ((1, 1), (2, 1), (1, 2))
            @test !(cinfree(Kd, Qd .== 0, Dd)[J...] ≈ cfree(Kd, Qd .== 0)[J...]) &&
                !(cinfree(Kd, Qd .== 0, Dd)[J...] ≈ cmean(Kd)[J...])
        end
        # every other block is wholly in the domain and free: the whole mean, 1
        rest = [J for J in CartesianIndices((4, 4)) if !(Tuple(J) in first.(plan))]
        @test length(rest) == 12 && all(d[J] == 1.0 for J in rest)
    end

end

@testitem "F3-16: F4-15b review: the operator coefficient and the jac rows fold over free ∩ in-domain" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
    @testset "F4-15b review: the operator coefficient and the jac rows fold over free ∩ in-domain" begin
        # (review should-fix 2: a partial mask, an irregular domain and a spatial operator whose
        # coefficient reads a fine input. The coefficient folds at each face over the block's free
        # in-domain children, and the implicit operator's rows fold as the residual does.)
        q2 = first(@variables pr15q2(..)::Int32 [input = true])
        ki = first(@variables pr15ki(..) [input = true, bounds = (0.5, 4)])
        pki = first(@variables pr15pki(..) [input = true, bounds = (0.5, 4)])
        pk1 = first(@variables pr15pk1(..) [input = true, bounds = (0, 1)])
        dm2 = first(@variables pr15dm2(..)::Bool [input = true])
        cq = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables pr15cq(..))), LatticePDE.LatticeLevel, Coarse(CK)))
        ch = first(@variables pr15ch(..))
        psites(J) = [((J[1] - 1) * CK + i, (J[2] - 1) * CK + j) for j in 1:CK for i in 1:CK]
        rng = Xoshiro(13)
        Q = zeros(Int32, CDIMS)
        n3 = [16, 0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 12, 14, 15, 16, 0][randperm(rng, 16)]
        for (b, J) in enumerate(CartesianIndices(CDIMS .÷ CK))
            own = randperm(rng, 16)
            for (n, s) in enumerate(psites(J))
                Q[s...] = own[n] <= n3[b] ? 3 : rand(rng, 0:2)
            end
        end
        Ki = [0.5 + 3.5 * rand(rng) for _ in 1:CDIMS[1], _ in 1:CDIMS[2]]
        Df = [rand(rng) < 0.6 for _ in 1:CDIMS[1], _ in 1:CDIMS[2]]
        Dc = [
            count(Df[((I[1] - 1) * CK + 1):(I[1] * CK), ((I[2] - 1) * CK + 1):(I[2] * CK)]) > CK^2 ÷ 2
                for I in CartesianIndices(CDIMS .÷ CK)
        ]
        osys(c, K, kind1, dvs) = PDESystem(
            [D(c(t, x, y)) ~ 0.05 * DivKGrad(:harmonic)(K, c(t, x, y)) - c(t, x, y) * 0.3 * kind1],
            [c(0, x, y) ~ x * y, c(t, x, y) ~ masked(q2(t, x, y) == 3, 1.0)], cdom(), [t, x, y], [c(t, x, y); dvs], Num[]; name = :pr15o
        )
        pc = cown(
            osys(cq, ki(t, x, y), q2(t, x, y) == 1, [q2(t, x, y), ki(t, x, y), dm2(t, x, y)]), CDIMS; domain = dm2,
            ins = [q2(t, x, y) => Q, ki(t, x, y) => Ki, dm2(t, x, y) => Df]
        )
        ph = cown(
            osys(ch, pki(t, x, y), pk1(t, x, y), [q2(t, x, y), pki(t, x, y), pk1(t, x, y), dm2(t, x, y)]), CDIMS .÷ CK; domain = dm2,
            ins = [
                q2(t, x, y) => cwhole(Q), pki(t, x, y) => cinfree(Ki, Q .== 3, Df),
                pk1(t, x, y) => cinfree(Float64.(Q .== 1), Q .== 3, Df), dm2(t, x, y) => Dc,
            ]
        )
        @test !(cinfree(Ki, Q .== 3, Df) ≈ cmean(Ki))                 # (the fold is not the whole mean)
        @test !(cinfree(Ki, Q .== 3, Df) ≈ cfree(Ki, Q .== 3))        # (nor the domain-free mean)
        # an in-domain node with free children outside it: the support is a strict subset of its
        # free set there, the case the pre-fix fold misses
        strad = [
            I for I in CartesianIndices(CDIMS .÷ CK) if Dc[I] &&
                any(
                    (!Df[(I[1] - 1) * CK + i, (I[2] - 1) * CK + j]) &&
                    Q[(I[1] - 1) * CK + i, (I[2] - 1) * CK + j] != 3 for i in 1:CK, j in 1:CK
                )
        ]
        @test !isempty(strad)
        for alg in (ExplicitEuler(), BackwardEuler())
            sc, sh = solve(pc, alg; dt = 0.05), solve(ph, alg; dt = 0.05)
            @test sc.retcode == SciMLBase.ReturnCode.Success
            a, b = Array(sc[cq(t, x, y), length(sc.t)]), sh[ch(t, x, y), length(sh.t)]
            rt = alg isa ExplicitEuler ? 1.0e-13 : 1.0e-10
            @test isapprox(a, b; rtol = rt) || (println("F4-15b P2 ", alg, ": max |Δ| ", maximum(abs, a .- b)); false)
        end
    end

end

@testitem "F3-16: a fine field and a coarse field in one group: prolongation and restriction" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
    @testset "a fine field and a coarse field in one group: prolongation and restriction" begin
        # u (fine 8×8) reads c (Coarse(2), 4×4) at the node of its block; c reads u by the block
        # mean. One BackwardEuler window against the hand matrix of the coupled system.
        c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cmix(..))), LatticePDE.LatticeLevel, Coarse(2)))
        u = first(@variables umix(..))
        @parameters ka = 0.7 kb = 0.4
        sys = PDESystem(
            [
                D(c(t, x, y)) ~ 0.05 * laplacian(c(t, x, y)) - c(t, x, y) + ka * u(t, x, y),
                D(u(t, x, y)) ~ 0.02 * laplacian(u(t, x, y)) - u(t, x, y) + kb * c(t, x, y),
            ],
            [c(0, x, y) ~ x, u(0, x, y) ~ y], cdom(), [t, x, y], [c(t, x, y), u(t, x, y)], [ka, kb]; name = :mix
        )
        p = cown(sys, (8, 8))
        lap(n, h) = (
            L = zeros(n * n, n * n); li = LinearIndices((n, n));
            for j in 1:n, i in 1:n, (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                (1 <= i + di <= n && 1 <= j + dj <= n) || continue
                L[li[i, j], li[i + di, j + dj]] += 1 / h^2; L[li[i, j], li[i, j]] -= 1 / h^2
            end; L
        )
        # restriction R (mean over the 2×2 block) and prolongation P (the node of the block)
        R, P = zeros(16, 64), zeros(64, 16)
        lf, lc = LinearIndices((8, 8)), LinearIndices((4, 4))
        for j in 1:8, i in 1:8
            J = lc[(i + 1) ÷ 2, (j + 1) ÷ 2]
            R[J, lf[i, j]] = 1 / 4
            P[lf[i, j], J] = 1.0
        end
        A = [0.05 * lap(4, 0.25) - I 0.7 * R; 0.4 * P 0.02 * lap(8, 0.125) - I]
        h = 0.1
        for alg in (
                BackwardEuler(; linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64), nlsolve = LatticeNewton(; max_iter = 30)),
                ExplicitEuler(; substeps = 1),
            )
            ig = init(p, alg; dt = alg isa BackwardEuler ? h : h / 200)
            for _ in 1:(alg isa BackwardEuler ? 1 : 200)
                step!(ig)
            end
            u0 = copy(p.u0)
            want = alg isa BackwardEuler ? (I - h * A) \ u0 : foldl((v, _) -> v + (h / 200) * A * v, 1:200; init = u0)
            got = [vec(ig[c(t, x, y)]); vec(ig[u(t, x, y)])]
            @test got ≈ want rtol = alg isa BackwardEuler ? 1.0e-9 : 1.0e-12
        end
    end

end

@testitem "F3-16: an irregular domain on a coarse grid: the domain folded by Majority" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
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
            PDESystem(
                [D(c(t, x, y)) ~ 0.02 * laplacian(c(t, x, y)) - c(t, x, y) * k2 + 0.5 * k1 + 0.05 * g(t, x, y)],
                [c(0, x, y) ~ x + y, c(t, x, y) ~ masked(q(t, x, y) == 3, 1.0)], cdom(), [t, x, y],
                [[c(t, x, y), cdm(t, x, y), q(t, x, y), g(t, x, y)]; hand ? [cf1(t, x, y), cf2(t, x, y)] : Num[]], Num[]; name = :dm
            )
        end
        pc = cown(dsys(cdo), CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1, g(t, x, y) => CG])
        # (`ckinds` covers no block with kind 3 whole: no node is masked, each folds over its free
        # children; the hand inputs are the in-domain free means, as the fold's support is under
        # the domain ruling: at 721d1efb (~/lpwork/f4F15b/cdom-nc.log) the three comparisons fail)
        # (the hand inputs are the in-domain free means: the ruling's support is free ∩ in-domain)
        ph = cown(
            dsys(cdh; hand = true), CDIMS .÷ CK; domain = cdm,
            ins = [
                cdm(t, x, y) => Dc, q(t, x, y) => cwhole(CQ1), g(t, x, y) => cinfree(CG, CQ1 .== 3, Df),
                cf1(t, x, y) => cinfree(Float64.(CQ1 .== 1), CQ1 .== 3, Df),
                cf2(t, x, y) => cinfree(Float64.(CQ1 .== 2), CQ1 .== 3, Df),
            ]
        )
        for alg in (ExplicitEuler(), BackwardEuler(), CrankNicolson())
            sc, sh = solve(pc, alg; dt = 0.05), solve(ph, alg; dt = 0.05)
            @test capprox(sc[cdo(t, x, y), length(sc.t)], sh[cdh(t, x, y), length(sh.t)]; rtol = alg isa ExplicitEuler ? 1.0e-13 : 1.0e-10)
        end
        # a node outside keeps its value (its block's majority is outside); nodes inside moved
        sc = solve(pc, BackwardEuler(); dt = 0.05)
        v0, v1 = sc[cdo(t, x, y), 1], sc[cdo(t, x, y), length(sc.t)]
        @test v1[.!Dc] == v0[.!Dc] && any(v1[Dc] .!= v0[Dc])
        # in a group of some fields only (FieldGroups): the group computes the domain of its
        # coarse field's level (a fine field `u` that the coarse one does not read, its own group)
        ug = first(@variables udomg(..))
        cdg = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cdomg(..))), LatticePDE.LatticeLevel, Coarse(4)))
        gsys = PDESystem(
            [D(cdg(t, x, y)) ~ 0.02 * laplacian(cdg(t, x, y)) + 0.5 * (q(t, x, y) == 1), D(ug(t, x, y)) ~ 0.1 * laplacian(ug(t, x, y)) - ug(t, x, y)],
            [cdg(0, x, y) ~ x + y, ug(0, x, y) ~ x], cdom(), [t, x, y], [cdg(t, x, y), ug(t, x, y), cdm(t, x, y), q(t, x, y)], Num[]; name = :dg
        )
        pg = cown(gsys, CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1])
        sg = solve(pg, FieldGroups(cdg(t, x, y) => BackwardEuler(), ug(t, x, y) => ExplicitEuler()); dt = 0.05)
        csys1 = PDESystem(
            [D(cdg(t, x, y)) ~ 0.02 * laplacian(cdg(t, x, y)) + 0.5 * (q(t, x, y) == 1)], [cdg(0, x, y) ~ x + y], cdom(),
            [t, x, y], [cdg(t, x, y), cdm(t, x, y), q(t, x, y)], Num[]; name = :d1
        )
        s1 = solve(cown(csys1, CDIMS; domain = cdm, ins = [cdm(t, x, y) => Df, q(t, x, y) => CQ1]), BackwardEuler(); dt = 0.05)
        @test sg[cdg(t, x, y), length(sg.t)] ≈ s1[cdg(t, x, y), length(s1.t)] rtol = 1.0e-10
        @test sg[cdg(t, x, y), length(sg.t)][.!Dc] == sg[cdg(t, x, y), 1][.!Dc]
    end

end

@testitem "F3-16: refusals name the cause and a route that works" setup = [LP_coarse] tags = [:latticepde, :coarse] begin
    using .LP_coarse: fd
    @testset "refusals name the cause and a route that works" begin
        q = first(@variables q(..)::Int32 [input = true])
        mk(c; n = (16, 16)) = cown(
            PDESystem(
                [D(c(t, x, y)) ~ 0.01 * laplacian(c(t, x, y)) - c(t, x, y) * ismember(q(t, x, y), (2,))],
                [c(0, x, y) ~ 1.0], cdom(), [t, x, y], [c(t, x, y), q(t, x, y)], Num[]; name = :r
            ), n;
            ins = [q(t, x, y) => zeros(Int32, n)]
        )
        # a level that is not a grid: the route `Coarse(k)`
        ci = first(@variables cint(..) [lattice_level = 4])
        m = cmsg(() -> mk(ci))
        @test occursin("`lattice_level = 4`", m) && occursin("`Coarse(4)`", m)
        # an axis that k does not divide: named, with its size and the route (which works)
        cc = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        m = cmsg(() -> mk(cc; n = (18, 16)))
        @test occursin("axis 1 (`x`) has 18 sites", m) && occursin("divisible by 4", m) && occursin("20 or 16", m)
        @test solve(mk(cc; n = (20, 16)), ExplicitEuler(); dt = 0.1).retcode == SciMLBase.ReturnCode.Success
        @test solve(mk(cc; n = (16, 1)), ExplicitEuler(); dt = 0.1).retcode == SciMLBase.ReturnCode.Success   # size 1: never coarsened
        # a spatial operator of a coarse field in a fine row: the coarse operator at the node of
        # the block (F3-22: the direct form is the aux field of the route, which also works)
        u = first(@variables uref(..))
        L = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables Lref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        direct = PDESystem(
            [D(cc(t, x, y)) ~ 0.01 * laplacian(cc(t, x, y)), D(u(t, x, y)) ~ laplacian(cc(t, x, y))],
            [cc(0, x, y) ~ x^2, u(0, x, y) ~ 0.0], cdom(), [t, x, y], [cc(t, x, y), u(t, x, y)], Num[]; name = :b
        )
        good = PDESystem(
            [D(cc(t, x, y)) ~ 0.01 * laplacian(cc(t, x, y)), L(t, x, y) ~ laplacian(cc(t, x, y)), D(u(t, x, y)) ~ L(t, x, y)],
            [cc(0, x, y) ~ x^2, u(0, x, y) ~ 0.0], cdom(), [t, x, y], [cc(t, x, y), L(t, x, y), u(t, x, y)], Num[]; name = :g
        )
        sg = solve(cown(good, (16, 16)), ExplicitEuler(; substeps = 1); dt = 0.01, saveat = [0.01])
        @test size(sg[L(t, x, y), 1]) == (4, 4) && size(sg[u(t, x, y), 2]) == (16, 16)
        sdir = solve(cown(direct, (16, 16)), ExplicitEuler(; substeps = 1); dt = 0.01, saveat = [0.01])
        @test sdir[u(t, x, y), 2] == sg[u(t, x, y), 2]
        # a mask on an aux field: refused (D-F4-15b Limits (4): an aux field follows its
        # expression), with the route (mask a rate field)
        am = PDESystem(
            [D(cc(t, x, y)) ~ 0.01 * laplacian(cc(t, x, y)), L(t, x, y) ~ laplacian(cc(t, x, y))],
            [cc(0, x, y) ~ x^2, L(t, x, y) ~ masked(q(t, x, y) == 3, 1.0)], cdom(),
            [t, x, y], [cc(t, x, y), L(t, x, y), q(t, x, y)], Num[]; name = :am
        )
        m = cmsg(() -> cown(am, (16, 16); ins = [q(t, x, y) => zeros(Int32, 16, 16)]))
        @test occursin("aux field", m) && occursin("takes no mask", m) && occursin("rate field", m)
        # (in a substep a field reads the fields it depends on after their update: `L` from `cref`
        # after its step; the coarse Laplacian by hand, zero flux, spacing 1/4)
        lap(v) = (
            n = size(v, 1); [
                sum(
                    (1 <= i + a <= n && 1 <= j + b <= n ? v[i + a, j + b] - v[i, j] : 0.0)
                        for (a, b) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ) * 16 for i in 1:n, j in 1:n
            ]
        )
        c0 = [((i - 0.5) / 4)^2 for i in 1:4, j in 1:4]
        Lh = lap(c0 .+ 0.01 * 0.01 .* lap(c0))
        @test sg[u(t, x, y), 2] ≈ 0.01 .* repeat(Lh; inner = (4, 4)) rtol = 1.0e-12
        # a map's offset read counts fine sites: a coarse field's must be a multiple of k
        @parameters dx [lattice_spacing = 1]
        mm = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables mref(..))), LatticePDE.LatticeLevel, Coarse(4)))
        msys(a) = PDESystem(
            [Shift(t, 1)(mm(t, x, y)) ~ mm(t, x + a * dx, y)], [mm(0, x, y) ~ x], cdom(10.0), [t, x, y],
            [mm(t, x, y)], [dx]; name = :mp
        )
        m = cmsg(() -> cown(msys(1), (16, 16)))
        @test occursin("a multiple of 4 sites (`4 * dx`)", m)
        sm = solve(cown(msys(4), (16, 16)), ExplicitMap(); saveat = [1.0])
        @test sm[mm(t, x, y), 2][1:3, :] == sm[mm(t, x, y), 1][2:4, :]          # one node to the left
    end
end
