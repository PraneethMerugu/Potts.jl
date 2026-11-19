# F3-17 (F3 design §3.9): `[lattice_level = Coarse(k)]` on a field of `@potts_model`. The
# field's array is its grid's (one value per node of k×k sites), its equation runs there
# through the same lowering as front end B (`Potts.fields` → `discretize`), and a CPM read of
# the field at a site reads the node whose block holds the site, so `integral(c) / volume` is
# the cell's average over its sites. With σ frozen the coupled model equals its PDESystem solved
# by LatticePDE (`Potts.fields` → `discretize`) bitwise. The fields are coupled with `@fields`
# (F4-B4t; before, written in `@equations`). Base 392dd404 (~/lpwork/f3b6-nc-a.log):
# `lattice_level` is not an option of `variable` (every model errors).

@testsetup module FieldsCoarseSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts: CorePotts


isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module FcoPDE
    using ..FieldPDE
    @variables c(..) [lattice_level = Coarse(4)] e(..) kA(..)::Bool [input = true] kB(..)::Bool [input = true]
    @variables u(..) kn(..) [input = true, lattice_input_name = "kind"]
    @variables g(..) sk(..) [input = true] v(..) X(..) L(..) [lattice_level = Coarse(4)] M(..) [lattice_level = Coarse(4)]
    @variables m1(..) [lattice_level = Coarse(4)] m2(..) [lattice_level = Coarse(4)] m3(..) [lattice_level = Coarse(4)]
    @variables m4(..) [lattice_level = Coarse(4)] m5(..) [lattice_level = Coarse(4)] m6(..) [lattice_level = Coarse(4)]
    const D = (16, 12)
    const X_ = (t, x, y)
    ics(fs...) = [f(0, x, y) ~ 0.0 for f in fs]
    function mix()
        @parameters Dc = 0.4 kd = 0.3 s = 0.5
        C, E = c(X_...), e(X_...)
        return pdesys(
            [Dt(C) ~ Dc * laplacian(C) - kd * C + s * kA(X_...) + 0.2 * E + 0.01 * x, Dt(E) ~ 0.1 * laplacian(E) - E + 0.5 * C],
            [ics(c, e); C ~ masked(kB(X_...), 2.0)], D, [C, E, kA(X_...), kB(X_...)], [Dc, kd, s]
        )
    end
    dom() = (C = c(X_...); pdesys([Dt(C) ~ 0.4 * laplacian(C) - 0.3 * C * kA(X_...) + 1.0], ics(c), D, [C, kA(X_...)]))
    function on_copy()
        @variables c(..) [lattice_level = Coarse(2)]
        C = c(X_...)
        return pdesys([Dt(C) ~ 0.1 * laplacian(C) - C], ics(c), (8, 8), [C])
    end
    function where_()
        @variables c(..)
        C, U = c(X_...), u(X_...)
        return pdesys(
            [Dt(C) ~ 0.1 * laplacian(C) - C, Dt(U) ~ kA(X_...) - U + 0.1 * laplacian(kn(X_...))], ics(c, u), (8, 8),
            [C, U, kA(X_...), kn(X_...)]
        )
    end
    function mass()
        G = g(X_...)
        ms = [m(X_...) for m in (m1, m2, m3, m4, m5, m6)]
        SK = sk(X_...)
        eqs = [
            G ~ 0.5 + 0.45 * sin(0.7 * x + 0.3 * y), Dt(ms[1]) ~ G, Dt(ms[2]) ~ max(G - 0.5, 0), Dt(ms[3]) ~ G^2,
            Dt(ms[4]) ~ exp(G), Dt(ms[5]) ~ SK * G, Dt(ms[6]) ~ G / (0.2 + G),
        ]
        return pdesys(eqs, ics(g, m1, m2, m3, m4, m5, m6), D, [G; ms; SK])
    end
    # a spatial operator across grids: direct (`xd`) and through aux fields, the manual route (`xr`)
    function xd()
        @parameters Dc = 0.4
        C, V, U = c(X_...), v(X_...), u(X_...)
        return pdesys(
            [
                Dt(V) ~ 0.1 * laplacian(V) - V + 0.5 * kA(X_...), Dt(C) ~ Dc * laplacian(C) - 0.3 * C + 0.5 * laplacian(V),
                Dt(U) ~ 0.2 * laplacian(U) - U + 0.5 * laplacian(C) + 0.1 * DivKGrad(:harmonic)(1 + x, C),
            ],
            ics(c, v, u), D, [C, V, U, kA(X_...)], [Dc]
        )
    end
    function xr()
        @parameters Dc = 0.4
        C, V, U, Xa, La, Ma = c(X_...), v(X_...), u(X_...), X(X_...), L(X_...), M(X_...)
        return pdesys(
            [
                Dt(V) ~ 0.1 * laplacian(V) - V + 0.5 * kA(X_...), Xa ~ laplacian(V), La ~ laplacian(C), Ma ~ DivKGrad(:harmonic)(1 + x, C),
                Dt(C) ~ Dc * laplacian(C) - 0.3 * C + 0.5 * Xa, Dt(U) ~ 0.2 * laplacian(U) - U + 0.5 * La + 0.1 * Ma,
            ],
            ics(c, X, L, M, v, u), D, [C, Xa, La, Ma, V, U, kA(X_...)], [Dc]
        )
    end
    # an operator on another group's field `v`, with a Dirichlet face (`cut`) or a Robin face (`cut_bcs`)
    function cut(face)
        C, V, U = c(X_...), v(X_...), u(X_...)
        return pdesys(
            [
                Dt(V) ~ 0.1 * laplacian(V) - V + 0.5 * kA(X_...), Dt(C) ~ 0.4 * laplacian(C) - 0.3 * C + 0.2 * V,
                Dt(U) ~ 0.2 * laplacian(U) - U + 0.5 * laplacian(V) + 0.3 * laplacian(C),
            ],
            [ics(c, v, u); face], D, [C, V, U, kA(X_...)]
        )
    end
    cut() = cut(v(t, 0, y) ~ 1.0)
    cut_bcs() = cut(1.0 * v(t, 0, y) - Differential(x)(v(t, 0, y)) ~ 0.5)
end


@potts_model FcMix begin
    @kinds medium A[frozen] B[frozen]
    @variables avg(cell) = 0.0
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @fields c = FcoPDE.mix() (FcoPDE.kA => kind == A, FcoPDE.kB => kind == B)
    @after_mcs avg ~ integral(c) / volume
    @sweep Metropolis(; temperature = 1.0)
end


# two frozen cells, A (rows 2:8, columns 2:6; 9 and 12 of 16 sites of blocks (1, 1) and (2, 1),
# 6 and 8 of (1, 2) and (2, 2): blocks A covers in part, so `kA` folds to 9/16, 12/16, 6/16 and
# 8/16 there) and B (rows 9:15, columns 6:12; only block (3, 3), sites 9:12 x 9:12, lies wholly in
# B, so the mask holds there only: D-F4-15b, a node is masked when its whole block is)
function fc_sigma(dims = (16, 12))
    σ = zeros(Int32, dims)
    σ[2:8, 2:6] .= 1
    σ[9:15, 6:12] .= 2
    return σ
end

fc_op() = [ownership => fc_sigma(), kind => [:A, :B]]

fc_kin(σ = fc_sigma()) = Int32[s == 0 ? 0 : s for s in σ]
# kind number per site (A = 1, B = 2)
# A's fields and `avg` after each of `k` MCS
function fc_runA(k; field_solver = BackwardEuler())
    integ = init(PottsProblem(FcMix(; name = :f), fc_op(), (0, k); field_solver), SequentialCPM(); save_start = false)
    out = [
        (step!(integ); st = current_state(integ); (copy(Array(st.site.c)), copy(Array(st.site.e)), copy(st.cell.avg)))
            for _ in 1:k
    ]
    return out, integ
end

function fc_runB(k; alg = BackwardEuler())
    bp = Potts.LatticePDE.discretize(
        Potts.fields(FcMix(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((16, 12)); T = Float64);
        u0 = [:c => zeros(4, 3), :e => zeros(16, 12)], tspan = (0, k), inputs = [:kind => fc_kin()]
    )
    s = Potts.LatticePDE.solve(bp, alg; dt = 1.0, saveat = 1.0)
    return [s[:c, i] for i in 2:length(s.t)], [s[:e, i] for i in 2:length(s.t)]
end


# an irregular domain (the lattice's) with a coarse field: a node is in it when most of its block is
@potts_model FcDom begin
    @structural_parameters begin
        domain = x -> x[2] <= 7.0 || x[1] <= 5.0
    end
    @kinds medium A[frozen]
    @lattice Lattice((16, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 9.0)^2
    @fields FcoPDE.dom() (FcoPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end


# Review r1 M2: a coarse field's source that reads a fine field nonlinearly receives the fine
# integral of the source (the mean of the whole subterm, each fine read at its site), in a model as in
# B. Base cb20be97 (~/lpwork/f3b6r-nc-m2a.log): `f(mean g)`, off by up to 75%.
@potts_model FcMass begin
    @kinds medium A[frozen] B[frozen]
    @parameters S[kind] = [1.0, 2.0, 5.0]
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @fields FcoPDE.mass() (FcoPDE.sk => S[kind])
    @sweep Metropolis(; temperature = 1.0)
end


# F3-22 (F3 design §5 F3-22): a spatial operator across grids in a model. `v` is fine, `c` is coarse:
# the coarse row reads the block mean of the fine Laplacian, and the fine row `u` the coarse
# `laplacian(c)` at its block's node. The direct form is the aux field of the manual route (bitwise),
# the model equals B (`Potts.fields`) bitwise, the added aux field is the binding's scratch (not in the
# state), and a ForwardDiff Dual runs through it (F3-21b's shadow store). Base 5316bf1c
# (~/lpwork/f322/nc-*.log): the direct form is refused ("a spatial operator reads its field on
# that field's own grid").
using ForwardDiff: ForwardDiff

@potts_model _Fc16x12 begin
    @structural_parameters begin
        sys_fn = FcoPDE.xd
    end
    @kinds medium A[frozen] B[frozen]
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @fields sys_fn() (FcoPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

FcXd(; name = :FcXd, kw...) = _Fc16x12(; sys_fn = FcoPDE.xd, name, kw...)
FcXr(; name = :FcXr, kw...) = _Fc16x12(; sys_fn = FcoPDE.xr, name, kw...)
FcCut(; name = :FcCut, kw...) = _Fc16x12(; sys_fn = FcoPDE.cut, name, kw...)
FcCutBcs(; name = :FcCutBcs, kw...) = _Fc16x12(; sys_fn = FcoPDE.cut_bcs, name, kw...)

@potts_model _FcOnCopy begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @fields c = FcoPDE.on_copy()
    @on_copy c[target] ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _FcWhere begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @fields FcoPDE.where_() (FcoPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

function fco_throws(T, pats, f)
    err = try
        f(); nothing
    catch e
        e
    end
    @test err isa T
    msg = sprint(showerror, err)
    for pat in pats
        @test occursin(pat, msg) || (println("Expected $(repr(pat)) in: ", msg); false)
    end
    return err
end

fx_run(M, k, fs; ps = Pair[]) = begin
    integ = init(PottsProblem(M(; name = :x), [fc_op(); ps], (0, k); field_solver = fs, seed = 3), SequentialCPM(); save_start = false)
    [(step!(integ); st = current_state(integ).site; map(a -> copy(Array(a)), (st.c, st.v, st.u))) for _ in 1:k]
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "TS1-1: coarse grid and domain coupled models equal LatticePDE owned run" setup = [FieldsCoarseSetup] tags = [:potts, :fields_coarse] begin
    @testset "TS1-1: coarse grid and domain coupled models equal LatticePDE owned run" begin
        # 1. Coarse(4) with BackwardEuler and ExplicitEuler
        k = 4
        for (fs, alg) in ((BackwardEuler(), BackwardEuler()), (ExplicitEuler(), ExplicitEuler()))
            a, _ = fc_runA(k; field_solver = fs)
            bc, be = fc_runB(k; alg)
            @test size(a[1][1]) == (4, 3) && size(a[1][2]) == (16, 12)
            @test [x[1] for x in a] == bc && [x[2] for x in a] == be
        end
        a1, _ = fc_runA(1)
        @test findall(==(2.0), a1[1][1]) == CartesianIndex.([(3, 3)])

        # 2. Irregular domain
        σ = zeros(Int32, 16, 12); σ[2:4, 2:4] .= 1
        integ = init(
            PottsProblem(FcDom(; name = :d), [ownership => σ, kind => [:A]], (0, 3); field_solver = BackwardEuler()),
            SequentialCPM(); save_start = false
        )
        ad = [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:3]
        dm = Array(current_state(integ).site.domain__in) .!= 0
        bp = Potts.LatticePDE.discretize(
            Potts.fields(FcDom(; name = :d)),
            Potts.LatticePDE.LatticeDiscretization(
                Potts.LatticePDE.Grid((16, 12)); T = Float64,
                domain = "domain__in"
            ); u0 = [:c => zeros(4, 3)], tspan = (0, 3),
            inputs = [:kind => Int32.(σ), :domain__in => dm]
        )
        @test ad == (s -> [s[:c, i] for i in 2:length(s.t)])(Potts.LatticePDE.solve(bp, BackwardEuler(); dt = 1.0, saveat = 1.0))
        out = [count(dm[(I[1] - 1) * 4 .+ (1:4), (I[2] - 1) * 4 .+ (1:4)]) <= 8 for I in CartesianIndices((4, 3))]
        @test any(out) && all(ad[end][out] .== 0.0) && all(ad[end][.!out] .> 0.0)
    end
end

@testitem "TS1-1: cross-grid operator coupled models equal LatticePDE owned run" setup = [FieldsCoarseSetup] tags = [:potts, :fields_coarse] begin
    @testset "TS1-1: cross-grid operator coupled models equal LatticePDE owned run" begin
        # Cross-grid operators (`FcXd`, `FcXr`, `FcCut`, `FcCutBcs`)
        tight = LatticePCG(; reltol = 1.0e-12, maxiters = 64)
        for fs in (ExplicitEuler(; substeps = 40), BackwardEuler(; linsolve = tight), CrankNicolson(; linsolve = tight))
            ax, rx = fx_run(FcXd, 3, fs), fx_run(FcXr, 3, fs)
            @test ax == rx && all(maximum(abs, ax[end][i]) > 0 for i in 1:3)
            @test size(ax[1][1]) == (4, 3) && size(ax[1][2]) == (16, 12)
        end
        st = current_state(init(PottsProblem(FcXd(; name = :x), fc_op(), (0, 1); field_solver = BackwardEuler()), SequentialCPM())).site
        @test !any(k -> occursin('(', string(k)), keys(st))
        fa = FieldGroups(:u => BackwardEuler(; linsolve = tight); default = ExplicitEuler(; substeps = 40))
        fb = FieldGroups(:u => BackwardEuler(; linsolve = tight); default = ExplicitEuler(; substeps = 40))
        for (M, fsA, fsB, tol) in (
                (FcXd, BackwardEuler(), BackwardEuler(), 0.0),
                (FcXd, ExplicitEuler(; substeps = 40), ExplicitEuler(; substeps = 40), 0.0),
                (FcCut, fa, fb, 1.0e-10),
                (FcCutBcs, fa, fb, 1.0e-10),
            )
            am = fx_run(M, 3, fsA)
            bpm = Potts.LatticePDE.discretize(
                Potts.fields(M(; name = :x)),
                Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((16, 12)); T = Float64),
                ; u0 = [:c => zeros(4, 3), :v => zeros(16, 12), :u => zeros(16, 12)], tspan = (0, 3), inputs = [:kind => fc_kin()]
            )
            sm = Potts.LatticePDE.solve(bpm, fsB; dt = 1.0, saveat = 1.0)
            @test [x[1] for x in am] == [sm[:c, i] for i in 2:length(sm.t)]
            @test [x[2] for x in am] == [sm[:v, i] for i in 2:length(sm.t)]
            if tol == 0.0
                @test [x[3] for x in am] == [sm[:u, i] for i in 2:length(sm.t)]
            else
                @test maximum(abs, am[end][3] - sm[:u, end]) < tol
            end
        end
    end
end

@testitem "F3-17: a site read of a coarse field reads its block's node; integral(c)/volume is the cell average" setup = [FieldsCoarseSetup] tags = [:potts, :fields_coarse] begin
    @testset "F3-17: a site read of a coarse field reads its block's node; integral(c)/volume is the cell average" begin
        a, integ = fc_runA(3)
        σ = fc_sigma()
        # (the default order runs `after_mcs` before `fields`: `avg` reads `c` of the MCS before)
        c, avg = a[end - 1][1], a[end][3]
        # the hand average: each site of the cell reads the node of its block
        hand = [sum(c[(i - 1) ÷ 4 + 1, (j - 1) ÷ 4 + 1] for i in 1:16, j in 1:12 if σ[i, j] == n) / count(==(n), σ) for n in 1:2]
        @test avg ≈ hand rtol = 1.0e-14
        # (not the average of the nodes the cell touches: cell A covers 35 sites over 4 blocks unevenly)
        touched = [
            sum(
                c[I] for I in unique(
                        CartesianIndex((i - 1) ÷ 4 + 1, (j - 1) ÷ 4 + 1)
                        for i in 1:16, j in 1:12 if σ[i, j] == n
                    )
            ) /
                length(unique(CartesianIndex((i - 1) ÷ 4 + 1, (j - 1) ÷ 4 + 1) for i in 1:16, j in 1:12 if σ[i, j] == n))
                for n in 1:2
        ]
        @test abs(avg[1] - touched[1]) > 1.0e-6
        @test Potts._coarse_site(LinearIndices((16, 12))[9, 5], (16, 12), 2) == LinearIndices((4, 3))[3, 2]
        @test Potts._coarse_site(LinearIndices((8, 1, 4))[6, 1, 3], (8, 1, 4), 1) == LinearIndices((4, 1, 2))[3, 1, 2]
    end
end

@testitem "F3-17: lattice_level in a model: arrays, refusals and routes" setup = [FieldsCoarseSetup] tags = [:potts, :fields_coarse] begin
    @testset "F3-17: lattice_level in a model: arrays, refusals and routes" begin
        # the operating point gives a coarse field its grid's array
        a0 = [Float64(i + 10j) for i in 1:4, j in 1:3]
        integ = init(PottsProblem(FcMix(; name = :f), [fc_op(); :c => a0], (0, 1)), SequentialCPM())
        # (the at-init clamp holds the masked value on B's whole blocks: as above, block (3, 3) only)
        kb = fc_kin() .== 2
        m = [all(kb[(I - 1) * 4 .+ (1:4), (J - 1) * 4 .+ (1:4)]) for I in 1:4, J in 1:3]
        @test findall(m) == CartesianIndex.([(3, 3)])
        @test Array(current_state(integ).site.c) == ifelse.(m, 2.0, a0)
        fco_throws(
            ArgumentError, ["`c` has `lattice_level = Coarse(4)`", "of size (4, 3)"],
            () -> PottsProblem(FcMix(; name = :f), [fc_op(); :c => zeros(16, 12)], (0, 1))
        )
        # a field of the lattice given a coarsened array is refused as before F3-17 (review r1 M1: cb20be97
        # built it, and its kernels wrote past the 8×6 array; ~/lpwork/f3b6r-nc-m1.log)
        fco_throws(
            ArgumentError, ["site quantity `e` has size (8, 6), lattice (16, 12)"],
            () -> PottsProblem(FcMix(; name = :f), [fc_op(); :e => zeros(8, 6)], (0, 1))
        )
        fco_throws(
            ArgumentError, ["site quantity `e` has size (16, 11), lattice (16, 12)"],
            () -> PottsProblem(FcMix(; name = :f), [fc_op(); :e => zeros(16, 11)], (0, 1))
        )
        # a state given as such skips those checks: the binding asserts each array's length
        p = PottsProblem(FcMix(; name = :f), fc_op(), (0, 1))
        st = p.u0
        bad = CorePotts.CPMState(st.ownership, st.cell, merge(st.site, (; e = zeros(8, 6))), st.model, st.history)
        fco_throws(
            ArgumentError, ["field array `e` has 48 values; its grid has 192 sites"],
            () -> init(remake(p; u0 = bad), SequentialCPM())
        )
        # a number is not a grid; a site variable has no level; a copy cannot write a node
        fco_throws(
            ArgumentError, ["`lattice_level = Coarse(4)`"],
            () -> Potts.variable(only(Potts.Symbolics.@variables q), :field; lattice_level = 4)
        )
        fco_throws(
            ArgumentError, ["`lattice_level` applies to fields"],
            () -> Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_level = Coarse(2))
        )
        fco_throws(
            ArgumentError, ["drop one of the two options"],
            () -> Potts.variable(
                only(Potts.Symbolics.@variables q), :field; lattice_level = Coarse(2),
                clear_on_ownership_change = true
            )
        )
        # a copy writes one site, which has no node of its own
        σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
        fco_throws(
            ArgumentError, ["@on_copy cannot assign `c`", "write the change as a source in its equation"],
            () -> PottsProblem(_FcOnCopy(; name = :o), [ownership => σ, kind => [:A]], (0, 1))
        )
        # review r1 N2: a refusal of the lowering names the equation it was lowering (not the first),
        # with a condition's parentheses and the kind's name (base cb20be97, ~/lpwork/f3b6r-nc-n2.log:
        # `in @equations Differential(t, 1)(c(t)) ~ kind == 1 - c(t) + …`)
        σw = zeros(Int32, 8, 8); σw[3:5, 3:5] .= 1
        # (batch-end review (d): the equation of its field in its PDESystem, as the user wrote it; base
        # ab34e226, ~/lpwork/f4BE/nc.log: `in @equations Differential(t, 1)(u(t)) ~ …`)
        err_w = fco_throws(
            ArgumentError,
            [
                "\n  in the equation of `u` in the PDESystem `fields`: `Differential(t)(u(t, x, y)) ~ ", "(kind == A)", "0.1laplacian(kind)",
                "- u(t, x, y)`",
            ],
            () -> PottsProblem(_FcWhere(; name = :w), [ownership => σw, kind => [:A]], (0, 1))
        )
        @test !occursin("@equations", sprint(showerror, err_w))
        # Coarse(1) is the lattice itself (no option kept)
        v = Potts.variable(only(Potts.Symbolics.@variables q), :field; lattice_level = Coarse(1))
        @test !haskey(Potts.info(v).options, :lattice_level)
    end
end

@testitem "review r1 M2: a coarse source of a fine field receives its fine integral (in a model)" setup = [FieldsCoarseSetup] tags = [:potts, :fields_coarse] begin
    @testset "review r1 M2: a coarse source of a fine field receives its fine integral (in a model)" begin
        integ = init(
            PottsProblem(FcMass(; name = :m), fc_op(), (0, 1); field_solver = ExplicitEuler()), SequentialCPM();
            save_start = false
        )
        step!(integ)
        st = current_state(integ)
        G = Array(st.site.g)
        @test size(G) == (16, 12) && size(Array(st.site.m1)) == (4, 3) && length(unique(G)) > 10
        Sk = [1.0, 2.0, 5.0][fc_kin() .+ 1]
        want = (sum(G), sum(max.(G .- 0.5, 0)), sum(G .^ 2), sum(exp.(G)), sum(Sk .* G), sum(G ./ (0.2 .+ G)))
        for (i, w) in enumerate(want)
            got = sum(Array(getproperty(st.site, Symbol(:m, i)))) * 16
            @test isapprox(got, w; rtol = 1.0e-13) || (println("M2 (A) m", i, ": ", got, " ", w); false)
        end
    end
end


@testitem "F3-22: a Dual runs through a cross-grid term in a model (against central differences)" setup = [FieldsCoarseSetup] tags = [:potts, :fields_coarse] begin
    @testset "F3-22: a Dual runs through a cross-grid term in a model (against central differences)" begin
        tight = LatticePCG(; reltol = 1.0e-11, maxiters = 60)
        W = [0.01 * (i + 2j) for i in 1:16, j in 1:12]
        q(sol) = sum(W .* sol.u[end].site.u)
        drun(fs, p) = solve(PottsProblem(FcXd(; name = :x), [fc_op(); :Dc => p], (0, 6); field_solver = fs, seed = 3), SequentialCPM(); saveat = 0:2:6)
        for fs in (ExplicitEuler(; substeps = 40), BackwardEuler(; linsolve = tight))
            d = drun(fs, ForwardDiff.Dual(0.4, 1.0))
            h = 1.0e-4 * 0.4
            fd = (q(drun(fs, 0.4 + h)) - q(drun(fs, 0.4 - h))) / 2h
            @test ForwardDiff.partials(q(d), 1) ≈ fd rtol = 1.0e-6
            @test abs(fd) > 0
            # the Dual run is the primal run: its field values, bit for bit
            @test ForwardDiff.value.(d.u[end].site.u) == drun(fs, 0.4).u[end].site.u
        end
    end
end
