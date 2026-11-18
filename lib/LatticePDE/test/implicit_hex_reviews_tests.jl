# Split from implicit_tests.jl (Wave T3b); uses LP_implicit setup.

@testitem "F3-20: one BackwardEuler window on a hexagonal lattice equals the hand BE matrix" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-20: one BackwardEuler window on a hexagonal lattice equals the hand BE matrix" begin
        h = 0.05
        alg = BackwardEuler(; linsolve = BTIGHT)
        # numeric rows: closed with a mask and its value, and periodic
        for (bcs, per, mask) in (([bc(0, x, y) ~ x * y, bce ~ masked(bqe == 2, 1.5)], false, true), ([bc(0, x, y) ~ x * y; HEXPER], true, false))
            p = hexdisc(bsys([D(bce) ~ bD * laplacian(bce) - bk * bce + x], bcs, [bD, bk]))
            ig, u0, u = be_window(p, alg; dt = h)
            L, b = hex_hand(; D = 0.3, k = 2.0, f = (x, y) -> x, periodic = per)
            A, rhs = I - h * L, u0 .+ h .* b
            if mask
                for r in findall(vec(HEXKIND .== 2))
                    A[r, :] .= 0
                    A[r, r], rhs[r] = 1, 1.5
                end
            end
            @test maximum(abs, u .- A \ rhs) < 1.0e-9
            rt = only(ig.runtimes)
            @test rt.cache.exact && rt.cache.newton == 1 && length(rt.cache.rows[1].solver.op.face) == 2 &&
                rt.cache.rows[1].solver.op.diag ≈ 0.3 * 2 / (3 / HEXN^2)
        end
        # field rows (`jac:` writes w1, w2, w3): a site multiplier `value_at(W, q) laplacian(c)` (the row scaled by
        # 1/m; q = 0 reads 0: m = 0 rows in two stages), and an irregular domain (no face across its
        # edge, the diagonal included; a site outside keeps its value)
        mq(xx, yy) = (0.0, 0.5, 2.0)[HEXKIND[round(Int, xx * HEXN + 0.5), round(Int, yy * HEXN + 0.5)] + 1]
        p = hexdisc(bsys([D(bce) ~ value_at(bW, bqe) * laplacian(bce) - bk * bce + 1], [bc(0, x, y) ~ x * y], [bW, bk]))
        ig, u0, u = be_window(p, alg; dt = h)
        L, b = hex_hand(; m = mq, k = 2.0, f = (x, y) -> 1.0)
        @test maximum(abs, u .- (I - h * L) \ (u0 .+ h .* b)) < 1.0e-9
        rt = only(ig.runtimes)
        @test rt.cache.rows[1].op.field && rt.cache.rows[1].op.scaled && rt.cache.exact && rt.cache.newton == 1
        @variables hdm(..)::Bool [input = true]
        hdme = hdm(t, x, y)
        dm = [(i - 6.3)^2 + (j - 5.8)^2 + (i - 6.3) * (j - 5.8) < 18 for i in 1:HEXN, j in 1:HEXN]
        pd = discretize(
            PDESystem(
                [D(bce) ~ bD * laplacian(bce) - bk * bce + x], [bc(0, x, y) ~ x * y], bdom(1.0), [t, x, y], [bce, hdme], [bD, bk];
                name = :hexdom
            ), LatticeDiscretization(Grid((HEXN, HEXN); geometry = HEX); T = Float64, domain = hdm);
            inputs = [hdme => dm]
        )
        ig, u0, u = be_window(pd, alg; dt = h)
        L, b = hex_hand(; D = 0.3, k = 2.0, f = (x, y) -> x)
        out = findall(.!vec(dm))
        for r in axes(L, 1), c in axes(L, 2)            # no face across the domain's edge
            r != c && L[r, c] != 0 && (r in out || c in out) && (L[r, r] += L[r, c]; L[r, c] = 0)
        end
        A, rhs = I - h * L, u0 .+ h .* b
        for r in out
            A[r, :] .= 0
            A[r, r], rhs[r] = 1, u0[r]
        end
        @test maximum(abs, u .- A \ rhs) < 1.0e-9 && only(ig.runtimes).cache.rows[1].op.domain
    end
end

@testitem "F3-20 r1 M1: face conditions on a hexagonal lattice (explicit rate, BackwardEuler window)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-20 r1 M1: face conditions on a hexagonal lattice (explicit rate, BackwardEuler window)" begin
        # a Dirichlet face (axis 1 low), a Robin face (axis 2 low), zero flux elsewhere, a mask; each link
        # that leaves the box takes its face's ghost (a diagonal link axis 1's when it leaves along axis 1)
        faces = [bc(t, 0, y) ~ 1.0, 1.5 * bc(t, x, 0) - 0.5 * Differential(y)(bc(t, x, 0)) ~ 0.2]
        hf = Dict((1, -1) => (:dir, 1.0), (2, -1) => (:robin, 1.5, -0.5, 0.2))
        h = 0.05
        for (lab, rate, ps, m, mask) in (
                ("numeric", bD * laplacian(bce) - bk * bce + x, [bD, bk], (x, y) -> 1.0, true),
                ("field row", value_at(bW, bqe) * laplacian(bce) - bk * bce + x, [bW, bk], nothing, false),
            )
            mq(xx, yy) = (0.0, 0.5, 2.0)[HEXKIND[round(Int, xx * HEXN + 0.5), round(Int, yy * HEXN + 0.5)] + 1]
            bcs = [bc(0, x, y) ~ x * y; faces; mask ? [bce ~ masked(bqe == 2, 1.5)] : []]
            p = hexdisc(bsys([D(bce) ~ rate], bcs, ps))
            L, b = hex_hand(; D = m === nothing ? 1.0 : 0.3, m = something(m, mq), k = 2.0, f = (x, y) -> x, faces = hf)
            # the explicit rate at the start: `L u0 + b` (the ghosts of the face conditions)
            ie = init(p, ExplicitEuler(; substeps = 1); dt = 1.0e-7)
            u0 = copy(vec(ie[bce]))
            step!(ie)
            r = (vec(ie[bce]) .- u0) ./ 1.0e-7
            act = mask ? .!vec(HEXKIND .== 2) : trues(HEXN^2)
            @test maximum(abs, (r .- (L * u0 .+ b))[act]) < 1.0e-5 * maximum(abs, L * u0 .+ b) ||
                (println("hex face rate ", lab, " ", maximum(abs, (r .- (L * u0 .+ b))[act])); false)
            # one BackwardEuler window: the hand BE matrix
            ig, u0, u = be_window(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
            A, rhs = I - h * L, u0 .+ h .* b
            for q in findall(.!act)
                A[q, :] .= 0
                A[q, q], rhs[q] = 1, 1.5
            end
            @test maximum(abs, u .- A \ rhs) < 1.0e-9 || (println("hex face BE ", lab, " ", maximum(abs, u .- A \ rhs)); false)
            @test only(ig.runtimes).cache.exact && only(ig.runtimes).cache.newton == 1
        end
    end
end

@testitem "F3-20 r2 M1: an indefinite steady row on a hexagonal lattice is refused (Lanczos)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-20 r2 M1: an indefinite steady row on a hexagonal lattice is refused (Lanczos)" begin
        # `0 ~ 0.01Δc − k c + x` with Robin faces `−2c − ∂c/∂x ~ 0` on x = 0 and y = 0 (α, β of opposite signs).
        # k = 0.01: the dense max Re λ of the hex :ode Jacobian is +0.176 (cubic +0.076), refused on both
        # lattices; k = 0.3: −0.114 (cubic −0.214), the steady state is stable and runs on both.
        # Base (0f206d5c): the hex row skipped the check, and k = 0.01 returned Success
        for (k, ok) in ((0.01, false), (0.3, true))
            sys = PDESystem(
                [0 ~ 0.01 * laplacian(bce) - k * bce + x],
                [bc(0, x, y) ~ 0.0, -2.0 * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~ 0.0, -2.0 * bc(t, x, 0) - Differential(y)(bc(t, x, 0)) ~ 0.0],
                bdom(1.0), [t, x, y], [bce], Any[]; name = :hexind
            )
            for geometry in (HEX, LatticeFields.IR.CUBIC)
                p = discretize(sys, LatticeDiscretization(Grid((12, 12); geometry); T = Float64))
                if ok
                    @test solve(p, QuasiSteady(; linsolve = BTIGHT); dt = 0.1).retcode == ReturnCode.Success
                else
                    @test_throws "its steady operator is indefinite" init(p, QuasiSteady(); dt = 0.1)
                end
            end
        end
    end
end

@testitem "F3-24: a multiplier that reads the coordinates is a site multiplier in J̃ (BackwardEuler, QuasiSteady)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-24: a multiplier that reads the coordinates is a site multiplier in J̃ (BackwardEuler, QuasiSteady)" begin
        # `(1 + x) laplacian(c)` and `(1 + x) DivKGrad(1 + y, c)` (`Diffusion` terms whose multiplier varies by
        # site): the Jacobian row is `m_i Σ_f K_f (c_n − c_i)`, so the row is scaled by `1/m` (symmetric
        # faces `K_f`). Base (7f8001c3): the faces `m_i K_f` with `newton = 1`, not the BE step
        h = 0.05
        xm = (i, j) -> 0.3 * (1 + (i - 0.5) / BDIMS[1])
        for (rhs, K) in ((0.3 * (1 + x) * laplacian(bce), (x, y) -> 1.0), (0.3 * (1 + x) * DivKGrad(:harmonic)(1 + y, bce), (x, y) -> 1 + y))
            bcs = [bc(0, x, y) ~ sin(3x) * cos(2y), bc(t, 0, y) ~ 1.0]
            kw = (; m = xm, K, k = (x, y) -> 2.0, f = (x, y) -> y, faces = Dict((1, -1) => (:dir, 1.0)))
            ig, u0, u = be_window(bown(bsys([D(bce) ~ rhs - bk * bce + y], bcs, [bk])), BackwardEuler(; linsolve = BTIGHT); dt = h)
            @test maximum(abs, u .- be_hand(u0, h; kw...)) < 1.0e-9
            rt = only(ig.runtimes)
            @test rt.cache.exact && rt.cache.newton == 1 && rt.cache.op.rows[1].scaled
            L, b = hand_rate(; kw...)
            sq = solve(bown(bsys([0 ~ rhs - bk * bce + y], bcs, [bk])), QuasiSteady(; linsolve = BTIGHT); dt = 0.1)
            @test maximum(abs, vec(blast(sq)) .- (-L \ b)) < 1.0e-9
        end
        # a multiplier that is negative at some sites (anti-diffusion): the scaled row drops it there,
        # so the operator is not exact and Newton iterates (warned)
        # (S1: the warning names the cause and the routes, not the generic unseen text)
        p = bown(bsys([D(bce) ~ 0.3 * (x - 0.5) * laplacian(bce) - bk * bce], [bc(0, x, y) ~ x], [bk]))
        ig = @test_logs (:warn, r"multiplier .* is negative at some site centers .* anti-diffusion.*keep the multiplier ≥ 0") match_mode = :any init(p, BackwardEuler(); dt = h)
        @test !only(ig.runtimes).cache.exact && only(ig.runtimes).cache.newton > 1
        # r1 M1: bound exact (bg = 0.5), then a write that turns `0.3(bg + x)` negative (bg = −0.5) reclassifies
        # the row at the write, with the warning. Base (27b14031): exact, newton = 1, Success, 0.27 off
        p = bown(bsys([D(bce) ~ 0.3 * (bg + x) * laplacian(bce) - bk * bce], [bc(0, x, y) ~ x], [bg, bk]))
        ig = init(p, BackwardEuler(; linsolve = BTIGHT); dt = h)
        @test only(ig.runtimes).cache.exact && only(ig.runtimes).cache.newton == 1
        @test_logs (:warn, r"is negative at some site centers \(down to -0.") match_mode = :any (ig.ps[bg] = -0.5; step!(ig))
        @test !only(ig.runtimes).cache.exact && only(ig.runtimes).cache.newton > 1
    end
end

@testitem "F3-20 r1 M2: a kind set of three or more kinds in a rate (Cartesian, ExplicitEuler)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-20 r1 M2: a kind set of three or more kinds in a rate (Cartesian, ExplicitEuler)" begin
        # `ismember(q, set)` lowers to one OR node with an operand per kind; before F3-20 the emitter
        # kept two of them (32 sites instead of 48 for (0, 1, 2) here, all four 32 instead of 64)
        K = Int32[(i + j) % 4 for i in 1:8, j in 1:8]
        for set in ((0, 1, 2), (0, 1, 2, 3), (1, 2))
            sys = PDESystem([D(bce) ~ ismember(bqe, set)], [bc(0, x, y) ~ 0.0], bdom(1.0), [t, x, y], [bce, bqe], Any[]; name = :kset)
            p = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64); inputs = [bqe => K])
            ig = init(p, ExplicitEuler(); dt = 0.1)
            step!(ig)
            @test ig[bce] ./ 0.1 ≈ Float64.(in.(K, Ref(set)))
        end
    end
end

@testitem "F3-20: order 1 (BackwardEuler) and 2 (CrankNicolson, BDF2) on a hexagonal lattice; QuasiSteady" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-20: order 1 (BackwardEuler) and 2 (CrankNicolson, BDF2) on a hexagonal lattice; QuasiSteady" begin
        # the plane wave `cos(2π(x + y))` is an eigenvector of the periodic hexagonal Laplacian with
        # `λ = −2/(3h²) Σ_d (2 − 2cos θ_d)`, `θ = (2π/n, 2π/n, 0)`: the semi-discrete solution is
        # `e^{D λ t} u0`, so the error is the time error alone
        n = HEXN
        θ = 2π / n
        λ = -2 / (3 / n^2) * (2 * (2 - 2cos(θ)))
        sys = bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ cos(2π * (x + y)); HEXPER], [bD]; T = 0.2, dvs = [bce])
        p = hexdisc(sys; inputs = [])
        u0 = [cos(2π * ((i - 0.5) + (j - 0.5)) / n) for i in 1:n, j in 1:n]
        ex = exp(0.3λ * 0.2) .* u0
        err(alg; dt) = maximum(abs, blast(solve(p, alg; dt)) .- ex)
        eb = [err(BackwardEuler(; linsolve = BTIGHT); dt = 0.2 / 2^k) for k in 2:5]
        @test all(o -> abs(o - 1) < 0.1, log2.(eb[1:(end - 1)] ./ eb[2:end]))
        # exactly the BE map (1 − h D λ)^{-m}
        @test maximum(abs, blast(solve(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.05)) .- (1 - 0.05 * 0.3λ)^-4 .* u0) < 1.0e-12
        # (at h D |λ| ≤ 0.1: measured CN 2.04, 2.01, 2.00 and BDF2 2.11, 2.06, 2.03; larger steps are
        # not yet asymptotic)
        for alg in (CrankNicolson(; linsolve = BTIGHT), BDF2(; linsolve = BTIGHT))
            ec = [err(alg; dt = 0.2 / 2^k) for k in 4:7]
            @test all(o -> abs(o - 2) < 0.15, log2.(ec[1:(end - 1)] ./ ec[2:end])) || (println("hex order 2: ", ec); false)
        end
        # QuasiSteady: the steady state of `D Δ c − k c + f` (closed, a mask) is the hand solve
        qs = hexdisc(bsys([D(bce) ~ bD * laplacian(bce) - bk * bce + x], [bc(0, x, y) ~ 0.0, bce ~ masked(bqe == 2, 1.5)], [bD, bk]))
        s = solve(qs, QuasiSteady(; linsolve = BTIGHT); dt = 0.1)
        L, b = hex_hand(; D = 0.3, k = 2.0, f = (x, y) -> x)
        A, rhs = -L, copy(b)
        for r in findall(vec(HEXKIND .== 2))
            A[r, :] .= 0
            A[r, r], rhs[r] = 1, 1.5
        end
        @test s.retcode == ReturnCode.Success && maximum(abs, vec(blast(s)) .- A \ rhs) < 1.0e-9
    end
end

@testitem "F3-20: the coupled steady solve (F3-12d) on a hexagonal lattice" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "F3-20: the coupled steady solve (F3-12d) on a hexagonal lattice" begin
        # two steady rows that read each other: `LatticeGMRES` with the block preconditioner on the
        # hexagonal hierarchy equals the hand coupled solve
        operiodic = [bo(t, 0, y) ~ bo(t, 1, y), bo(t, x, 0) ~ bo(t, x, 1)]
        for per in (false, true)
            lp = PDESystem(
                [0 ~ 0.1 * laplacian(bce) - 1.0 * bce + 2.0 * boe + x, 0 ~ 0.2 * laplacian(boe) - 2.0 * boe - 1.5 * bce + y],
                [[bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.0]; per ? [HEXPER; operiodic] : []], bdom(1.0), [t, x, y], [bce, boe], Any[];
                name = :hexloop
            )
            p = discretize(lp, LatticeDiscretization(Grid((HEXN, HEXN); geometry = HEX); T = Float64))
            s = solve(p, QuasiSteady(; linsolve = LatticeGMRES(; reltol = 1.0e-12, maxiters = 200)); dt = 0.1)
            L1, b1 = hex_hand(; D = 0.1, k = 1.0, f = (x, y) -> x, periodic = per)
            L2, b2 = hex_hand(; D = 0.2, k = 2.0, f = (x, y) -> y, periodic = per)
            n2 = HEXN^2
            A = [L1 2.0 * I(n2); -1.5 * I(n2) L2]
            want = -A \ [b1; b2]
            got = [vec(s[bce, length(s.t)]); vec(s[boe, length(s.t)])]
            @test s.retcode == ReturnCode.Success && maximum(abs, got .- want) < 1.0e-8
        end
        # a growing mode of a hexagonal system is refused in words (by the growth check after the first solve)
        grow = PDESystem(
            [0 ~ 0.1 * laplacian(bce) + 1.0 * bce + 2.0 * boe, 0 ~ 0.1 * laplacian(boe) - 1.0 * boe + 2.0 * bce],
            [[bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 0.0]; HEXPER; operiodic], bdom(1.0),
            [t, x, y], [bce, boe], Any[]; name = :hexgrow
        )
        pg = discretize(grow, LatticeDiscretization(Grid((HEXN, HEXN); geometry = HEX); T = Float64))
        @test_throws "their coupled steady system has a growing mode" init(pg, QuasiSteady(); dt = 0.1)
    end
end

@testitem "r1 M5: π and ℯ lower in a source, a coefficient and a face value (both paths)" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r1 M5: π and ℯ lower in a source, a coefficient and a face value (both paths)" begin
        # base: "cannot lower `π`: `identity` has no lattice lowering" on every path
        sym = nlsys([D(bce) ~ π * laplacian(bce) - ℯ * bce + sin(π * x) + ℯ], [bc(0, x, y) ~ cos(π * y), bc(t, 0, y) ~ π / 2 + ℯ * y], [bce]; T = 0.2)
        num = nlsys(
            [D(bce) ~ Float64(π) * laplacian(bce) - Float64(ℯ) * bce + sin(Float64(π) * x) + Float64(ℯ)],
            [bc(0, x, y) ~ cos(Float64(π) * y), bc(t, 0, y) ~ Float64(π) / 2 + Float64(ℯ) * y], [bce]; T = 0.2
        )
        for alg in (ExplicitEuler(), BackwardEuler(; linsolve = r1tight()))
            a, b = blast(solve(nlown(sym; dims = (8, 8)), alg; dt = 0.05)), blast(solve(nlown(num; dims = (8, 8)), alg; dt = 0.05))
            @test maximum(abs, a .- b) < 1.0e-13
        end
        # `π laplacian(c)` is a numeric face coefficient (no field row)
        @test !only(only(init(nlown(sym; dims = (8, 8)), BackwardEuler(); dt = 0.05).runtimes).cache.rows).op.field
        ode(s) = discretize(s, LatticeDiscretization(Grid((8, 8)); T = Float64))
        pa, pb = ode(sym), ode(num)
        da, db = similar(pa.u0), similar(pb.u0)
        pa.f(da, pa.u0, pa.p, 0.1)
        pb.f(db, pb.u0, pb.p, 0.1)
        @test pa.u0 ≈ pb.u0 && maximum(abs, da .- db) < 1.0e-11
    end
end

@testitem "r1 M6, N2: a component field gets the operator of its scalar spelling" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r1 M6, N2: a component field gets the operator of its scalar spelling" begin
        @variables bu(..)[1:2]
        bue = bu(t, x, y)
        comp = nlsys(
            [D(bue[1]) ~ 0.05 * laplacian(bue[1]) - 40 * bue[1] / (0.025 + bue[1]) + 20, D(bue[2]) ~ 0.05 * laplacian(bue[2]) - bue[2] + bue[1]],
            [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3
        )
        scal = nlsys(
            [D(bce) ~ 0.05 * laplacian(bce) - 40 * bce / (0.025 + bce) + 20, D(boe) ~ 0.05 * laplacian(boe) - boe + bce],
            [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3
        )
        pc, ps = nlown(comp), nlown(scal)
        cc, cs = only(init(pc, BackwardEuler(); dt = 0.05).runtimes).cache, only(init(ps, BackwardEuler(); dt = 0.05).runtimes).cache
        # base: every term of both rows unseen, five warnings, newton = 4, no solve
        @test cc.newton == cs.newton == 1 && cc.exact && [r.op.iterate for r in cc.rows] == [r.op.iterate for r in cs.rows] == [true, false]
        @test all(r -> isempty(r.op.unseen), cc.rows) && [r.op.faces for r in cc.rows] == [r.op.faces for r in cs.rows]
        a = @test_logs min_level = WARN solve(pc, BackwardEuler(); dt = 0.05)
        b = solve(ps, BackwardEuler(); dt = 0.05)
        @test LatticePDE.Problems.field_stats(a) == LatticePDE.Problems.field_stats(b) && a.stats.solves == 12
        @test a[bue[1], length(a.t)] == b[bce, length(b.t)] && a[bue[2], length(a.t)] == b[boe, length(b.t)]
        # N2: a component read in a message is `u[1]` as written (base: `(bu)[1]`)
        pv = nlown(
            nlsys(
                [D(bue[1]) ~ 0.01 * laplacian(bue[1]) - Advect(Upwind1())([50 * (1 + x) + t, 0.0], bue[1]), D(bue[2]) ~ -bue[2]],
                [bu(0, x, y)[1] ~ x, bu(0, x, y)[2] ~ 0.0], [bue]
            )
        )
        @test_logs (:warn, r"`-Advect\(Upwind1\(\)\)\(\[.*, 0\.0\], bu\[1\]\)` \(in the rate of `bu\[1\]`\) is not in the implicit operator") match_mode = :any init(
            pv,
            BackwardEuler()
            ; dt = 0.1
        )
    end
end

@testitem "r1 S4, S6, N1: the failure route follows the cause; rule 2 on the sum; show" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r1 S4, S6, N1: the failure route follows the cause; rule 2 on the sum; show" begin
        alg = BackwardEuler()
        @test LFB.status_route(alg, :failure, 0x02) == LFB.status_route(alg, :failure, 0x06) ==
            "more substeps (`substeps = n`): a smaller step brings the Newton iteration into its contraction"
        @test LFB.status_route(alg, :failure, 0x01) == "more substeps (`substeps = n`) or a larger linear budget (`linsolve = LatticePCG(; maxiters = n)`)"
        # a Newton divergence in a run names that route (base: "… or a larger linear budget")
        p = nlown(nlsys([D(bce) ~ 0.01 * laplacian(bce) - Advect(Upwind1())([52 * (1 + x) + t, 0.0], bce)], [bc(0, x, y) ~ x * y], [bce]; T = 2.0))
        @test_logs (:warn, r"the Newton iteration diverged\), `ReturnCode.ConvergenceFailure`: the run stops; more substeps \(`substeps = n`\): a smaller step brings the Newton iteration into its contraction$") match_mode = :any solve(
            p,
            BackwardEuler()
            ; dt = 1.0
        )
        # S6: advection (ρ_adv = 48) and a cycle (κ_in = 2) in one group: n = ⌈2 · 0.25 · 50⌉ = 25,
        # so ρ_c = 1/2 and newton = 10 (base, rule 2 on the larger: n = 24, ρ_c = 0.52, newton = 11)
        @parameters bvx = 1.0
        p = nlown(
            PDESystem(
                [D(bce) ~ 0.01 * laplacian(bce) - Advect(Upwind1())([bvx, 0.5], bce) + 2 * boe, D(boe) ~ 0.1 * laplacian(boe) - 3 * boe + 1.5 * bce],
                [bc(0, x, y) ~ x * y, bo(0, x, y) ~ y], bdom(1.0), [t, x, y], [bce, boe], [bvx]; name = :s6
            )
        )
        ig = init(p, BackwardEuler(; linsolve = BTIGHT); dt = 0.25)
        c = only(ig.runtimes).cache
        @test c.cyclic && c.ρin == 50.0 && ig.substeps == 25 && c.newton == 10
        # the reviewer's write `vx = 8`: ρ_in = 2 (8 + 0.5) 16 + 2 = 274, n = 137, newton 10 at once
        # (R2-N3: the step follows the recount; base: newton 12 until the next window)
        ig.ps[bvx] = 8.0
        @test ig.substeps == 137 && c.h == 0.25 / 137 && c.newton == 10
        step!(ig)
        @test ig.substeps == 137 && c.newton == 10 && only(ig.runtimes).totals.newton_budget == 0
        # N1: `ExplicitEuler` prints by keyword, as `BackwardEuler` does
        @test eval(Meta.parse(sprint(show, ExplicitEuler(; substeps = 15)))) == ExplicitEuler(; substeps = 15)
        @test eval(Meta.parse(sprint(show, ExplicitEuler()))) == ExplicitEuler()
    end
end

@testitem "R2-M1: kept DivKGrad with left-out at*Δ contracts at θ ≤ 1/2" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "R2-M1: kept DivKGrad with left-out at*Δ contracts at θ ≤ 1/2" begin
        # the reviewer's case: `5 DivKGrad(1 + x)` kept (its bound is the larger), `value_at(W, q) laplacian(c)`
        # out with θ = 2 / (5 · (1 − 1/16)) = 0.43 ≤ 1/2: one substep, newton 1 + ⌈log 1e-3 / log θ⌉ = 10,
        # no budget hit, the direct BE (base 9585df2e: 410 substeps, 8,228 solves)
        sys, p, r2qe, kind = r2m1_prob([0.5, 2.0], (W, q) -> value_at(W, q) * laplacian(bce) + 5.0 * DivKGrad(:harmonic)(1 + x, bce) - bce)
        for alg in (BackwardEuler(; linsolve = r1tight()), BackwardEuler(; substeps = 1, linsolve = r1tight()))
            ig = init(p, alg; dt = 0.05)
            c = only(ig.runtimes).cache
            @test ig.substeps == 1 && c.θ ≈ 2 / (5 * 15 / 16) && c.ρin == 0 && c.newton == 10
            s = @test_logs min_level = WARN solve(p, alg; dt = 0.05)
            @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0 && s.stats.solves < 100
            @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, 1; inputs = [r2qe => kind])) < 1.0e-4
        end
    end
end

@testitem "R2-M1: θ > 1/2 falls back to Gershgorin bound and warns on small substeps" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "R2-M1: θ > 1/2 falls back to Gershgorin bound and warns on small substeps" begin
        # θ = 4 / 4.69 > 1/2: the term's Gershgorin bound counts (rule 2 raises the count), and a
        # requested count below it warns why
        sys, p, r2qe, kind = r2m1_prob([1.0, 4.0], (W, q) -> value_at(W, q) * laplacian(bce) + 5.0 * DivKGrad(:harmonic)(1 + x, bce) - bce)
        ig = init(p, BackwardEuler(; linsolve = r1tight()); dt = 0.05)
        c = only(ig.runtimes).cache
        @test c.θ == 0 && c.ρin > 0 && ig.substeps > 1
        n = ig.substeps
        ig = @test_logs (:warn, r"^BackwardEuler\(substeps = 1\): field `bc` takes \d+ substeps, more than the 1 requested: the terms out of the implicit operator \(`laplacian\(bc\)\*value_at\(r2W, r2q\)` \(in the rate of `bc`\)\) are corrected by Newton iterations, which converge only when the substep keeps their contraction at most 1/2; fewer substeps would not converge$") init(
            p,
            BackwardEuler(; substeps = 1, linsolve = r1tight())
            ; dt = 0.05
        )
        @test ig.substeps == n
        s = solve(p, BackwardEuler(; linsolve = r1tight()); dt = 0.05)
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, n; inputs = [r2qe => kind])) < 1.0e-4
    end
end

@testitem "R2-M1: kept multiplier with zero rows uses Gershgorin bound" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "R2-M1: kept multiplier with zero rows uses Gershgorin bound" begin
        # a kept multiplier with zero rows (`ifelse(q == 1, 0, 8) laplacian(c)` kept): no ratio, the bound counts
        sys, p, r2qe, kind = r2m1_prob([0.5, 2.0], (W, q) -> ifelse(q == 1, 0.0, 8.0) * laplacian(bce) + DivKGrad(:harmonic)(1 + x, bce) - bce)
        ig = init(p, BackwardEuler(; linsolve = r1tight()); dt = 0.05)
        c = only(ig.runtimes).cache
        @test c.θ == 0 && c.ρin > 0 && ig.substeps > 1
        s = solve(p, BackwardEuler(; linsolve = r1tight()); dt = 0.05)
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, ig.substeps; inputs = [r2qe => kind])) < 1.0e-4
    end
end

# Batch 3 review r3 N3: at rule 2's limit with θ > 0 the contraction bound is `ρ_c = (1 + θ)/2`
# (up to 3/4), which 12 iterations cannot bring to ε_N: the cap is 26 when θ > 0, so the count
# meets `ρ_c^(k − 1) ≤ ε_N` (base 69bef544: clamped at 12, `0.715^11 = 0.025`); with θ = 0 the
# count and its cap 12 are unchanged
@testitem "r3 N3: the Newton count meets the tolerance at rule 2's limit with θ > 0" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r3 N3: the Newton count meets the tolerance at rule 2's limit with θ > 0" begin
        θ = 0.43
        for (ρh, want) in ((0.5 * (1 - θ), 22), (0.1, 12), (0.0, 10))
            k = LFP._newton_count(false, false, true, ρh / 0.01, 1.0, 0.01, θ)
            ρc = ρh + θ
            @test k == want && ρc^(k - 1) <= LFP.NEWTON_EPS || (println("θ count ", (ρh, k)); false)
        end
        @test LFP._newton_count(false, false, true, 0.5 / 0.01, 1.0, 0.01, 0.0) == 10          # (θ = 0: unchanged)
        @test LFP._newton_count(false, false, true, 2.0 / 0.01, 1.0, 0.01, 0.0) == 12          # (ρ_c ≥ 1: the cap 12)
        # a run: the reviewer's left-out diffusion (θ = 0.43) with advection at the rule-2 count
        @variables r3q(..)::Int32 [input = true]
        r3qe = r3q(t, x, y)
        kind = Int32[(i + j) % 2 for i in 1:16, j in 1:16]
        @parameters r3W[1:2] = [0.5, 2.0]
        sys = PDESystem(
            [
                D(bce) ~ value_at(r3W, r3qe) * laplacian(bce) + 5.0 * DivKGrad(:harmonic)(1 + x, bce) - bce -
                    Advect(Upwind1())([2.0, 0.0], bce),
            ], [bc(0, x, y) ~ x], bdom(0.5), [t, x, y], [bce, r3qe],
            [r3W]; name = :r3
        )
        p = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64); inputs = [r3qe => kind])
        ig = init(p, BackwardEuler(; linsolve = r1tight()); dt = 0.05)
        c = only(ig.runtimes).cache
        @test c.θ > 0.4 && c.ρin > 0 && c.newton > 12
        s = @test_logs min_level = WARN solve(p, BackwardEuler(; linsolve = r1tight()); dt = 0.05)
        @test s.retcode == ReturnCode.Success && s.stats.newton_budget == 0
        @test r1rel(vec(blast(s)), direct_be(sys, (16, 16), 0.05, 0.5, ig.substeps; inputs = [r3qe => kind])) < 1.0e-4
    end
end

# A parameter write that changes the automatic count sets the step at once (R2-N3) from the new
# parameters: the shift of a numeric row reads them (base 69bef544: the bound parameters were
# copied after the recount, so the step's shift kept the old growth `g`: 6.58 against 8.82)
@testitem "r3: a write that changes the count sets the step from the new parameters" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r3: a write that changes the count sets the step from the new parameters" begin
        @parameters r3g = 1.0
        sg = bsys([D(bce) ~ bD * laplacian(bce) + r3g * bce], [bc(0, x, y) ~ x * y], [bD, r3g]; T = 2.0, dvs = [bce])
        pg = discretize(sg, LatticeDiscretization(Grid(BDIMS); T = Float64))
        ig = init(pg, BackwardEuler(; linsolve = BTIGHT); dt = 0.5)
        step!(ig)
        u = vec(ig[bce])
        ig.ps[r3g] = 4.0
        @test ig.substeps == 4
        step!(ig)
        fresh = init(remake(pg; u0 = u, p = [r3g => 4.0]), BackwardEuler(; linsolve = BTIGHT); dt = 0.5)
        step!(fresh)
        @test vec(ig[bce]) == vec(fresh[bce])
    end
end

@testitem "R2-N1: the operator build count starts at 0 in a fresh session" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "R2-N1: the operator build count starts at 0 in a fresh session" begin
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e "using LatticePDE; print(LatticePDE.OPERATOR_BUILDS[])"`
        @test read(cmd, String) == "0"                                   # (base: 1, the precompile workload's)
    end
end

@testitem "r3 N1: cross-diffusion in an implicit group is a defect term" setup = [LP_implicit] tags = [:latticepde, :implicit] begin
    @testset "r3 N1: cross-diffusion in an implicit group is a defect term" begin
        @variables xq(..)
        xqe = xq(t, x, y)
        sx = PDESystem(
            [D(bce) ~ 0.3 * laplacian(bce) + 0.1 * laplacian(xqe) - 2.0 * bce + x, D(xqe) ~ 0.3 * laplacian(xqe) - xqe + 0.5 * bce],
            [bc(0, x, y) ~ 0.0, xq(0, x, y) ~ 0.0], bdom(0.2), [t, x, y], [bce, xqe], Any[]; name = :cross
        )
        p = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
        r = @test_logs (:warn, r"`0.1laplacian\(xq\)` \(in the rate of `bc`\) is not in the implicit operator and no bound sees it") match_mode = :any solve(
            p,
            BackwardEuler(; linsolve = BTIGHT)
            ; dt = 0.1
        )
        @test r.retcode == ReturnCode.Success
        po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
        ro = SciMLBase.solve(po, ImplicitEuler(); adaptive = false, dt = 0.1, abstol = 1.0e-12, reltol = 1.0e-12)
        @test maximum(abs, ro.u[end] .- r.u[end]) < 1.0e-6 || (println("r3 N1 ", maximum(abs, ro.u[end] .- r.u[end])); false)
    end
end
