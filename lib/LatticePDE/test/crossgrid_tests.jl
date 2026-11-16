# F3-22 (F3 design §5 F3-22; batch 6 review r1 S3, r2 N3): a spatial operator whose operand lives
# on another grid than its row. A fine field in a coarse row: the block mean of the fine operator
# (the net flux through the faces of the block over its volume). A coarse field in a fine row:
# the coarse operator at the node of the site's block. Both are the aux field of the manual route
# (`L ~ Δ(c)` on the grid of `c`) that `crossgrid_form` adds, so the oracle is the route itself
# (bitwise), a hand computation, and a dense implicit step (the term is a cross term, exact in
# solve order). Base 5316bf1c (~/lpwork/f322/nc-*.log): the direct form is refused ("a spatial
# operator reads its field on that field's own grid"), so every testset here errors.

@testsetup module LP_crossgrid
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
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
include("shared/cranknicolson.jl")
include("shared/grids.jl")
include("shared/maskswitch.jl")
include("shared/coupled.jl")
include("shared/clock.jl")
include("shared/numbers.jl")
include("shared/coarse.jl")
include("shared/crossgrid.jl")
include("shared/export_all.jl")
end

@testitem "F3-22: the direct form is the manual route, bitwise, for every operator and both directions" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "the direct form is the manual route, bitwise, for every operator and both directions" begin
        alg = ExplicitEuler(; dt = XT, substeps = 1)
        for (name, op) in XOPS
            p = xpair(op)
            for (dir, rt, row) in ((p.cf.dir, p.cf.route, xu), (p.fc.dir, p.fc.route, xcc))
                sd = solve(xown(dir, (16, 16)), alg; saveat = [0.01])
                sr = solve(xown(rt, (16, 16)), alg; saveat = [0.01])
                a = sd[xe(row), 2]
                @test a == sr[xe(row), 2] && maximum(abs, a) > 0       # (the row moved: a real comparison)
                @test size(a) == (row === xu ? (16, 16) : (4, 4))
                # the other row of the system (its own operator is on its own grid)
                @test sd[xe(row === xu ? xcc : xv), 2] == sr[xe(row === xu ? xcc : xv), 2]
        end
    end
    end

end

@testitem "F3-22: hand computation: the block mean of the fine Laplacian, and the coarse Laplacian at the node" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "hand computation: the block mean of the fine Laplacian, and the coarse Laplacian at the node" begin
        alg = ExplicitEuler(; dt = XT, substeps = 1)
        # a fine field that does not move: the coarse row gets `dt a mean(Δv)` in one step
        v0 = [sin(7 * xctr(16)[i]) * cos(5 * xctr(16)[j]) for i in 1:16, j in 1:16]
        sys = PDESystem(
            [D(xe(xv)) ~ 0, D(xe(xcc)) ~ 0.5 * Δ(xe(xv))], [xv(0, x, y) ~ sin(7x) * cos(5y), xcc(0, x, y) ~ 0.0],
            xdom(), [t, x, y], [xe(xv), xe(xcc)], Num[]; name = :xh1
        )
        c1 = solve(xown(sys, (16, 16)), alg; saveat = [XT])[xe(xcc), 2]
        L = reshape(xL2(16) * vec(v0), 16, 16)                      # the fine zero-flux Laplacian
        hand = XT * 0.5 .* reshape(XR * vec(L), 4, 4)
        @test c1 ≈ hand rtol = 1.0e-12
        # conservative: the block mean times the block size is the net flux through the block's faces
        # (the faces inside the block cancel), summed from the face differences by hand
        h = 1 / 16
        flux(I, J) = begin
            s = 0.0
            for j in 1:4, i in 1:4
                a, b = 4 * (I - 1) + i, 4 * (J - 1) + j
                i == 1 && a > 1 && (s += (v0[a - 1, b] - v0[a, b]) / h^2)
                i == 4 && a < 16 && (s += (v0[a + 1, b] - v0[a, b]) / h^2)
                j == 1 && b > 1 && (s += (v0[a, b - 1] - v0[a, b]) / h^2)
                j == 4 && b < 16 && (s += (v0[a, b + 1] - v0[a, b]) / h^2)
            end
            s
        end
        @test [flux(I, J) for I in 1:4, J in 1:4] ≈ 16 .* reshape(XR * vec(L), 4, 4) rtol = 1.0e-10
        @test abs(sum(c1) * 16 / (XT * 0.5)) < 1.0e-10 * maximum(abs, L) * 256          # no flux through the box
        # a coarse field that does not move: the fine row reads the coarse Laplacian at its block's node
        c0 = [xctr(4)[i]^2 + xctr(4)[j] for i in 1:4, j in 1:4]
        sys2 = PDESystem(
            [D(xe(xcc)) ~ 0, D(xe(xu)) ~ 0.5 * Δ(xe(xcc))], [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ 0.0],
            xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xh2
        )
        u1 = solve(xown(sys2, (16, 16)), alg; saveat = [XT])[xe(xu), 2]
        Lc = reshape(xL2(4) * vec(c0), 4, 4)
        @test u1 ≈ XT * 0.5 .* reshape(XP * vec(Lc), 16, 16) rtol = 1.0e-12
        @test all(u1[1:4, 1:4] .== u1[1, 1])                          # constant over a block
    end

end

@testitem "F3-22: 3D and a hexagonal lattice: the direct form is the route" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "3D and a hexagonal lattice: the direct form is the route" begin
        @parameters z
        dom3 = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0), z ∈ Interval(0.0, 1.0)]
        c3, L3, w3, v3, X3 = xlev(:xc3, 2), xlev(:xL3, 2), xfine(:xw3), xfine(:xv3), xfine(:xX3)
        e3(f) = f(t, x, y, z)
        ic = [c3(0, x, y, z) ~ x^2 + sin(3y) * z, w3(0, x, y, z) ~ 0.0]
        ic2 = [v3(0, x, y, z) ~ sin(7x) * cos(5y) * z, c3(0, x, y, z) ~ 0.0]
        d1 = PDESystem([D(e3(c3)) ~ 0.01 * Δ(e3(c3)), D(e3(w3)) ~ 0.5 * Δ(e3(c3)) - e3(w3)], ic, dom3, [t, x, y, z], [e3(c3), e3(w3)], Num[]; name = :x3a)
        r1 = PDESystem(
            [D(e3(c3)) ~ 0.01 * Δ(e3(c3)), e3(L3) ~ Δ(e3(c3)), D(e3(w3)) ~ 0.5 * e3(L3) - e3(w3)], ic, dom3, [t, x, y, z],
            [e3(c3), e3(L3), e3(w3)], Num[]; name = :x3b
        )
        d2 = PDESystem([D(e3(v3)) ~ 0.01 * Δ(e3(v3)), D(e3(c3)) ~ 0.5 * Δ(e3(v3)) - e3(c3)], ic2, dom3, [t, x, y, z], [e3(v3), e3(c3)], Num[]; name = :x3c)
        r2 = PDESystem(
            [D(e3(v3)) ~ 0.01 * Δ(e3(v3)), e3(X3) ~ Δ(e3(v3)), D(e3(c3)) ~ 0.5 * e3(X3) - e3(c3)], ic2, dom3, [t, x, y, z],
            [e3(v3), e3(X3), e3(c3)], Num[]; name = :x3d
        )
        own3(s) = discretize(s, LatticeDiscretization(Grid((8, 8, 8))))
        alg = ExplicitEuler(; dt = XT, substeps = 1)
        for (a, b, f) in ((d1, r1, w3), (d2, r2, c3))
            sa, sb = solve(own3(a), alg; saveat = [0.01]), solve(own3(b), alg; saveat = [0.01])
            @test sa[e3(f), 2] == sb[e3(f), 2] && maximum(abs, sa[e3(f), 2]) > 0
        end
        @test size(solve(own3(d2), alg; saveat = [0.01])[e3(c3), 2]) == (4, 4, 4)
        hx(s) = discretize(s, LatticeDiscretization(Grid((16, 16); geometry = HEX)))
        halg = ExplicitEuler(; dt = 0.0005, substeps = 1)
        p = xpair(c -> Δ(c))
        for (pr, row) in ((p.cf, xu), (p.fc, xcc))
            sa, sb = solve(hx(pr.dir), halg; saveat = [0.002]), solve(hx(pr.route), halg; saveat = [0.002])
            @test sa[xe(row), 2] == sb[xe(row), 2] && maximum(abs, sa[xe(row), 2]) > 0
    end
    end

end

@testitem "F3-22: the :ode path: the direct form is the route" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "the :ode path: the direct form is the route" begin
        p = xpair(c -> Δ(c))
        for (pr, row) in ((p.cf, xu), (p.fc, xcc))
            od(s) = discretize(s, LatticeDiscretization(Grid((16, 16))))
            sa = solve(od(pr.dir), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10, saveat = [0.05])
            sb = solve(od(pr.route), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10, saveat = [0.05])
            @test sa.u[end] == sb.u[end] && maximum(abs, sa.u[end]) > 0
        end
    end

end

@testitem "F3-22: implicit methods: the cross-grid term is exact in the operator (a dense step, no warning)" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "implicit methods: the cross-grid term is exact in the operator (a dense step, no warning)" begin
        dt = 0.05
        tight = DevicePCG(; rtol = 1.0e-12, budget = 64)
        mk(A) = A(; dt, substeps = 1, inner = tight)
        Lc, Lu = xL2(4), xL2(16)
        c0 = vec([xctr(4)[i]^2 + xctr(4)[j] for i in 1:4, j in 1:4])
        v0 = vec([sin(7 * xctr(16)[i]) * cos(5 * xctr(16)[j]) for i in 1:16, j in 1:16])
        M1 = [0.01 * Lc zeros(16, 256); 0.5 * XP * Lc 0.2 * Lu - I]; x01 = [c0; zeros(256)]      # c (coarse) → u (fine)
        M2 = [0.01 * Lu zeros(256, 16); 0.5 * XR * Lu -I(16)]; x02 = [v0; zeros(16)]          # v (fine) → c (coarse)
        s1 = PDESystem(
            [D(xe(xcc)) ~ 0.01 * Δ(xe(xcc)), D(xe(xu)) ~ 0.2 * Δ(xe(xu)) + 0.5 * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xi1
        )
        s2 = PDESystem(
            [D(xe(xv)) ~ 0.01 * Δ(xe(xv)), D(xe(xcc)) ~ 0.5 * Δ(xe(xv)) - xe(xcc)],
            [xv(0, x, y) ~ sin(7x) * cos(5y), xcc(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xv), xe(xcc)], Num[]; name = :xi2
        )
        # steady rows `0 ~ rhs` (under BackwardEuler: the window's start state of the other field, as for a same-grid cross term)
        s3 = PDESystem(
            [D(xe(xcc)) ~ 0.01 * Δ(xe(xcc)), 0 ~ 0.2 * Δ(xe(xu)) + 0.5 * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xi3
        )
        s4 = PDESystem(
            [D(xe(xv)) ~ 0.01 * Δ(xe(xv)), 0 ~ 0.2 * Δ(xe(xcc)) + 0.5 * Δ(xe(xv)) - xe(xcc)],
            [xv(0, x, y) ~ sin(7x) * cos(5y), xcc(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xv), xe(xcc)], Num[]; name = :xi4
        )
        xrun(sys, alg, n = 1) = Test.@test_logs(min_level = Base.CoreLogging.Warn, solve(xown(sys, (16, 16)), alg; saveat = dt .* (1:n)))
        gather(s, a, b, k) = [vec(s[xe(a), k]); vec(s[xe(b), k])]
        # one window; Crank–Nicolson starts with two half backward Euler steps (its damped start)
        @test gather(xrun(s1, mk(BackwardEuler)), xcc, xu, 2) ≈ (I - dt * M1) \ x01 atol = 1.0e-9
        @test gather(xrun(s2, mk(BackwardEuler)), xv, xcc, 2) ≈ (I - dt * M2) \ x02 atol = 1.0e-9
        half(M, x0) = (I - dt / 2 * M) \ ((I - dt / 2 * M) \ x0)
        @test gather(xrun(s1, mk(CrankNicolson)), xcc, xu, 2) ≈ half(M1, x01) atol = 1.0e-9
        @test gather(xrun(s2, mk(CrankNicolson)), xv, xcc, 2) ≈ half(M2, x02) atol = 1.0e-9
        # BDF2: the second window, from a backward Euler start
        b1 = (I - dt * M1) \ x01
        @test gather(xrun(s1, mk(BDF2), 2), xcc, xu, 3) ≈ (1.5I - dt * M1) \ (2b1 - 0.5x01) atol = 1.0e-9
        b2 = (I - dt * M2) \ x02
        @test gather(xrun(s2, mk(BDF2), 2), xv, xcc, 3) ≈ (1.5I - dt * M2) \ (2b2 - 0.5x02) atol = 1.0e-9
        # steady rows
        cb = (I - dt * 0.01 * Lc) \ c0
        @test gather(xrun(s3, mk(BackwardEuler)), xcc, xu, 2) ≈ [cb; (I - 0.2 * Lu) \ (0.5 * XP * Lc * c0)] atol = 1.0e-9
        vb = (I - dt * 0.01 * Lu) \ v0
        @test gather(xrun(s4, mk(BackwardEuler)), xv, xcc, 2) ≈ [vb; (I - 0.2 * Lc) \ (0.5 * XR * Lu * v0)] atol = 1.0e-9
        # QuasiSteady: every row steady, the second reads the first's new steady state (review r1 of F3-22)
        qs = QuasiSteady(; dt, inner = tight)
        s5 = PDESystem(
            [D(xe(xcc)) ~ 0.05 * Δ(xe(xcc)) - xe(xcc) + x + y, D(xe(xu)) ~ 0.2 * Δ(xe(xu)) + 0.5 * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ 0.0, xu(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xi5
        )
        s6 = PDESystem(
            [D(xe(xv)) ~ 0.05 * Δ(xe(xv)) - xe(xv) + sin(7x) * cos(5y), D(xe(xcc)) ~ 0.2 * Δ(xe(xcc)) + 0.5 * Δ(xe(xv)) - xe(xcc)],
            [xv(0, x, y) ~ 0.0, xcc(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xv), xe(xcc)], Num[]; name = :xi6
        )
        cq = (I - 0.05 * Lc) \ vec([xctr(4)[i] + xctr(4)[j] for i in 1:4, j in 1:4])
        vq = (I - 0.05 * Lu) \ v0
        @test gather(xrun(s5, qs), xcc, xu, 2) ≈ [cq; (I - 0.2 * Lu) \ (0.5 * XP * Lc * cq)] atol = 1.0e-9
        @test gather(xrun(s6, qs), xv, xcc, 2) ≈ [vq; (I - 0.2 * Lc) \ (0.5 * XR * Lu * vq)] atol = 1.0e-9
    end

end

@testitem "F3-22: a cycle across the grids is not in the operator: warned with the term as written, converges with newton = k" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "a cycle across the grids is not in the operator: warned with the term as written, converges with newton = k" begin
        dt = 0.05
        tight = DevicePCG(; rtol = 1.0e-12, budget = 64)
        Lc, Lu = xL2(4), xL2(16)
        c0 = vec([xctr(4)[i]^2 + xctr(4)[j] for i in 1:4, j in 1:4])
        u0 = vec([sin(5 * xctr(16)[i]) for i in 1:16, j in 1:16])
        M = [0.01 * Lc 0.1 * XR * Lu; 0.5 * XP * Lc 0.2 * Lu - I]
        ref = (I - dt * M) \ [c0; u0]
        sys = PDESystem(
            [D(xe(xcc)) ~ 0.01 * Δ(xe(xcc)) + 0.1 * Δ(xe(xu)), D(xe(xu)) ~ 0.2 * Δ(xe(xu)) + 0.5 * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ sin(5x)], xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xcy
        )
        err(nw) = (
            s = solve(xown(sys, (16, 16)), BackwardEuler(; dt, substeps = 1, newton = nw, inner = tight); saveat = [dt]);
            maximum(abs, [vec(s[xe(xcc), 2]); vec(s[xe(xu), 2])] .- ref)
        )
        Test.@test_logs (:warn, r"`0\.1Δ\(xuu\)` \(in the rate of `xcc`\) is not in the implicit operator") match_mode = :any min_level = Base.CoreLogging.Warn begin
            solve(xown(sys, (16, 16)), BackwardEuler(; dt, substeps = 1, inner = tight); saveat = [dt])
        end
        e4, e12 = Test.@test_logs(min_level = Base.CoreLogging.Error, (err(4), err(12)))
        @test e12 < 1.0e-5 && e12 < e4 / 10
    end

end

@testitem "F3-22: same grid: a term of aux fields is a cross term in solve order (review r1 of F3-22)" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "same grid: a term of aux fields is a cross term in solve order (review r1 of F3-22)" begin
        # `L ~ b²` read by `a`, with `b` after `a` in state order: the row order follows the aux
        # kernel, and the term is a source of the new `b` (newton = 1, no warning). An aux chain
        # `L2 ~ 2 L`, `L ~ Δ(b)` reads `b` through both. Base 33e960cf~1: unseen, `newton = 4` and a warning
        dt = 0.05
        tight = DevicePCG(; rtol = 1.0e-13, budget = 200)
        fa, fb, fL, fL2 = xfine(:xsa), xfine(:xsb), xfine(:xsL), xfine(:xsL2)
        Lu, Id = xL2(16), Matrix(1.0I, 256, 256)
        Ma = 0.1 * Lu - Id
        a0 = vec([sin(3 * xctr(16)[i]) * cos(2 * xctr(16)[j]) for i in 1:16, j in 1:16])
        b0 = vec([xctr(16)[i]^2 + xctr(16)[j] for i in 1:16, j in 1:16])
        ic = [fa(0, x, y) ~ sin(3x) * cos(2y), fb(0, x, y) ~ x^2 + y]
        sq = PDESystem(
            [D(xe(fa)) ~ 0.1 * Δ(xe(fa)) - xe(fa) + 0.5 * xe(fL), xe(fL) ~ xe(fb)^2, D(xe(fb)) ~ 0.1 * Δ(xe(fb)) - xe(fb)],
            ic, xdom(), [t, x, y], [xe(fa), xe(fL), xe(fb)], Num[]; name = :xsq
        )
        ch = PDESystem(
            [
                D(xe(fa)) ~ 0.1 * Δ(xe(fa)) - xe(fa) + 0.5 * xe(fL2), xe(fL2) ~ 2 * xe(fL), xe(fL) ~ Δ(xe(fb)),
                D(xe(fb)) ~ 0.1 * Δ(xe(fb)) - xe(fb),
            ], ic, xdom(), [t, x, y], [xe(fa), xe(fL2), xe(fL), xe(fb)], Num[]; name = :xsc
        )
        b1 = (Id - dt * Ma) \ b0
        for (sys, rhs) in ((sq, 0.5 * b1 .^ 2), (ch, Lu * b1))
            s = Test.@test_logs(
                min_level = Base.CoreLogging.Warn,
                solve(xown(sys, (16, 16)), BackwardEuler(; dt, substeps = 1, inner = tight); saveat = [dt])
            )
            @test vec(s[xe(fb), 2]) ≈ b1 atol = 1.0e-12
            @test vec(s[xe(fa), 2]) ≈ (Id - dt * Ma) \ (a0 + dt * rhs) atol = 1.0e-12
        end
        # a cycle through the chain (`b` reads `a`): the chain's term is warned with its text
        cy = PDESystem(
            [
                D(xe(fa)) ~ 0.1 * Δ(xe(fa)) - xe(fa) + 0.5 * xe(fL2), xe(fL2) ~ 2 * xe(fL), xe(fL) ~ Δ(xe(fb)),
                D(xe(fb)) ~ 0.1 * Δ(xe(fb)) - xe(fb) + 0.2 * xe(fa),
            ], ic, xdom(), [t, x, y], [xe(fa), xe(fL2), xe(fL), xe(fb)], Num[]; name = :xsy
        )
        Test.@test_logs (:warn, r"`0\.5xsL2` \(in the rate of `xsa`\) is not in the implicit operator") match_mode = :any min_level = Base.CoreLogging.Warn begin
            solve(xown(cy, (16, 16)), BackwardEuler(; dt, substeps = 1, inner = tight); saveat = [dt])
        end
    end

end

@testitem "F3-22: two terms of one operator and operand: the second aux prints as written" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "two terms of one operator and operand: the second aux prints as written" begin
        # (`DivKGrad(xkc)#2` is the second aux field's name; a warning prints `DivKGrad(xkc)`)
        kc, ku = xlev(:xkc, 4), xfine(:xku)
        sys = PDESystem(
            [
                D(xe(kc)) ~ 0.01 * Δ(xe(kc)) + 0.1 * Δ(xe(ku)),
                D(xe(ku)) ~ DivKGrad(:harmonic)(1 + x, xe(kc)) + DivKGrad(:arithmetic)(1 + y, xe(kc)) - xe(ku),
            ],
            [kc(0, x, y) ~ x^2 + y, ku(0, x, y) ~ sin(5x)], xdom(), [t, x, y], [xe(kc), xe(ku)], Num[]; name = :xk2
        )
        tl = Test.TestLogger(min_level = Base.CoreLogging.Warn)
        Base.CoreLogging.with_logger(tl) do
            solve(xown(sys, (16, 16)), BackwardEuler(; dt = 0.002, substeps = 1, inner = DevicePCG(; rtol = 1.0e-12, budget = 64)); saveat = [0.002])
        end
        msgs = [string(r.message) for r in tl.logs]
        @test (occursin("`DivKGrad(xkc)` (in the rate of `xku`)", join(msgs)) && !occursin("var\"", join(msgs)) && !occursin("#2", join(msgs))) ||
            (foreach(println, msgs); false)
    end

end

@testitem "F3-22: ExplicitEuler's default count: a cross-grid term read one way is bounded, a loop is refused" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "ExplicitEuler's default count: a cross-grid term read one way is bounded, a loop is refused" begin
        # (review r1: the rows read one way, so the Jacobian is block triangular and the dominance
        # test does not apply; D-C7a item 2 amended. Base 9afaac05: "no automatic substeps")
        one = PDESystem(
            [D(xe(xcc)) ~ 0.01 * Δ(xe(xcc)), D(xe(xu)) ~ 0.2 * Δ(xe(xu)) + 0.5 * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xe1
        )
        p = xown(one, (16, 16))
        # the u row: 0.2 · 4 · 2 · 16² + 1 + 0.5 · 4 · 2 · 4² (the coarse Laplacian's row sum)
        @test p.stability(p.p) ≈ 0.2 * 2048 + 1 + 0.5 * 128
        s = Test.@test_logs(min_level = Base.CoreLogging.Warn, solve(p, ExplicitEuler(; dt = 0.05); saveat = [0.05]))
        n = ceil(Int, 0.05 * (0.2 * 2048 + 1 + 0.5 * 128) / 1.8)
        @test substep_counts(s)[1] == n && s[xe(xu), 2] == solve(p, ExplicitEuler(; dt = 0.05, substeps = n); saveat = [0.05])[xe(xu), 2]
        # a loop across the grids: refused, naming both rows
        loop = PDESystem(
            [D(xe(xcc)) ~ 0.01 * Δ(xe(xcc)) + 0.1 * Δ(xe(xu)), D(xe(xu)) ~ 0.2 * Δ(xe(xu)) + 0.5 * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xcc), xe(xu)], Num[]; name = :xe2
        )
        m = try
            solve(xown(loop, (16, 16)), ExplicitEuler(; dt = 0.05)); ""
        catch e
            sprint(showerror, e)
        end
        @test occursin("no automatic substeps", m) && occursin("which read each other in a loop", m) && occursin("`xcc`", m) && occursin("`xuu`", m)
    end

end

@testitem "F3-22: Duals: ∂/∂p of a cross-grid run against finite differences" setup = [LP_crossgrid] tags = [:latticepde, :crossgrid] begin
    using .LP_crossgrid: fd, kron
    @testset "Duals: ∂/∂p of a cross-grid run against finite differences" begin
        tight = DevicePCG(; rtol = 1.0e-13, budget = 64)
        pidx(prob, s) = LatticePDE.Problems.SII.parameter_index(prob, s)
        withp(p, i, val) = (q = collect(promote_type(eltype(p), typeof(val)), p); q[i] = val; q)
        s1 = PDESystem(
            [D(xe(xcc)) ~ xDq * Δ(xe(xcc)), D(xe(xu)) ~ 0.2 * Δ(xe(xu)) + xaq * Δ(xe(xcc)) - xe(xu)],
            [xcc(0, x, y) ~ x^2 + y, xu(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xcc), xe(xu)], [xDq, xaq]; name = :xdu1
        )
        s2 = PDESystem(
            [D(xe(xv)) ~ xDq * Δ(xe(xv)), D(xe(xcc)) ~ xaq * Δ(xe(xv)) - xe(xcc)],
            [xv(0, x, y) ~ sin(7x) * cos(5y), xcc(0, x, y) ~ 0.0], xdom(), [t, x, y], [xe(xv), xe(xcc)], [xDq, xaq]; name = :xdu2
        )
        for (sys, fld) in ((s1, xu), (s2, xcc)), alg in (ExplicitEuler(; dt = XT, substeps = 1), BackwardEuler(; dt = 0.01, substeps = 1, inner = tight))
            prob = xown(sys, (16, 16))
            for s in (xDq, xaq)
                i = pidx(prob, s)
                J(val) = sum(abs2, solve(remake(prob; p = withp(prob.p, i, val)), alg; saveat = [0.02])[xe(fld), 2])
                v0 = prob.p[i]
                h = 1.0e-6
                @test ForwardDiff.derivative(J, v0) ≈ (J(v0 + h) - J(v0 - h)) / 2h rtol = 1.0e-7
        end
    end
end
end
