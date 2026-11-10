# F3-18 (F3 design §5, v3 §7.3 (b)): a Jiang-like integration test. The structure of Jiang et
# al. 2005 (spec 06 §2.5): five fields on the lattice coarsened by 4 (paper p. 10), O₂ and
# glucose consumed above their thresholds by the viable cells (the switch `max(u − u_T, 0)`),
# lactate produced from both consumptions (it reads O₂ and glucose), a growth factor consumed
# and an inhibitor produced by kind, each field held at its medium value on the medium (the
# moving masked Dirichlet: the tumor-medium interface), BackwardEuler, and four field windows
# per MCS between quarter sweeps (Fig. 3: `repeat(4, sweep(fraction = 1//4), fields)`). The
# rates are the paper's ratios in lattice units, with O₂'s diffusion scaled so that its shift
# `h²/(D dt)` on the coarse grid is about 0.022 (v3 §6.3). The cell average of O₂ is read through
# `integral(o) / volume`. With σ frozen the model equals B (`Potts.fields` → `discretize`) bitwise.
# Base 392dd404 (~/lpwork/f3b6-nc-a.log): `lattice_level` is not an option of `variable`.

isdefined(Main, :JiangLike) || include(joinpath(@__DIR__, "fields_jiang_model.jl"))

@testset "F3-18: a Jiang-like model equals B bitwise (σ frozen, CPU)" begin
    σ, kinds = jiang_state(JG_DIMS)
    @test Set(kinds) == Set([:N, :Q, :P])
    k = 2
    integ = init(PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, k);
        field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
    names = (:o, :g, :l, :gf, :inh)
    a = [(step!(integ); st = current_state(integ); (; (n => copy(Array(getproperty(st.site, n))) for n in names)...,
                                                     ocell = copy(st.cell.ocell))) for _ in 1:k]
    @test integ.retcode in (Potts.SciMLBase.ReturnCode.Default, Potts.SciMLBase.ReturnCode.Success)
    @test size(a[1].o) == JG_DIMS .÷ 4
    # B: the same fields at the same window (a quarter MCS), the kind map of the frozen cells
    kmap = Int32[s == 0 ? 0 : findfirst(==(kinds[s]), [:P, :Q, :N]) for s in σ]
    bp = Potts.LatticePDE.discretize(Potts.fields(JiangLike(; name = :j)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64);
        u0 = [n => zeros(JG_DIMS .÷ 4) for n in names], tspan = (0, k), inputs = [:kind => kmap])
    sb = Potts.LatticePDE.solve(bp, BackwardEuler(; dt = 0.25); saveat = 1.0)
    for n in names
        @test [x[n] for x in a] == [sb[n, i] for i in 2:length(sb.t)]
    end
    # the fields are not trivial: O₂ falls from the medium value into the spheroid; lactate is
    # produced; the inhibitor grows in the core
    o = a[end].o
    @info "F3-18 (CPU, 32³ lattice, 8³ fields): O₂ $(extrema(o)), lactate max $(maximum(a[end].l)), inhibitor max $(maximum(a[end].inh))"
    @test maximum(o) == 0.08 && minimum(o) < 0.04
    @test maximum(a[end].l) > 0 && maximum(a[end].inh) > 0
    # the cell average of O₂ through the coarse read (`after_mcs` runs after the MCS's field windows)
    o1 = a[2].o
    hand = [sum(o1[((Tuple(I) .- 1) .÷ 4 .+ 1)...] for I in CartesianIndices(σ) if σ[I] == n) / count(==(n), σ)
            for n in 1:length(kinds)]
    @test a[2].ocell ≈ hand rtol = 1e-13
end

# Review r1 M3: lactate's source reads O₂ and glucose (switches of other rows' fields) and no
# lactate, so it is known when lactate is solved after them: the default BackwardEuler operator
# is exact, newton = 2 (the switch rows) with no warning, and equals newton = 12 (base cb20be97:
# the term is unseen, newton = 4 and the warning; ~/lpwork/f3b6r-nc-m3.log)
@testset "F3-18: the Jiang-like default BackwardEuler is exact (newton = 2, no warning)" begin
    σ, kinds = jiang_state(JG_DIMS)
    @test_logs min_level = Base.CoreLogging.Warn init(PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 1);
        field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
    # F3-22 review r1: lactate reads O₂ and glucose one way (they do not read it back), so the
    # default ExplicitEuler count is bounded (D-C7a item 2 amended; base 9afaac05: refused with
    # the route `field_solver = BackwardEuler()`, now checked on a loop in audit.jl)
    m = try
        PottsProblem(JiangLike(; name = :j), [ownership => σ, kind => kinds], (0, 1)); ""
    catch err
        sprint(showerror, err)
    end
    @test m == ""
    kmap = Int32[s == 0 ? 0 : findfirst(==(kinds[s]), [:P, :Q, :N]) for s in σ]
    names = (:o, :g, :l, :gf, :inh)
    bp = Potts.LatticePDE.discretize(Potts.fields(JiangLike(; name = :j)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(JG_DIMS); T = Float64);
        u0 = [n => zeros(JG_DIMS .÷ 4) for n in names], tspan = (0, 2), inputs = [:kind => kmap])
    shifted = [circshift(kmap, (s, 0, 0)) for s in 0:3]
    function run(alg)
        ig = init(bp, alg)
        for w in 1:8
            ig[:kind] = shifted[mod1(w, 4)]
            step!(ig)
        end
        return ig
    end
    a = @test_logs min_level = Base.CoreLogging.Warn run(BackwardEuler(; dt = 0.25))
    c = only(a.runtimes).cache
    @test c.newton == 2 && c.exact && !c.cyclic
    @test Potts.LatticeFields.Problems.field_stats(a).newton_budget == 0
    # the two Newton steps are the converged BE step: with a tight inner solve they equal twelve
    # (~1e-15 measured, ~/lpwork/f3b6r/j2.log; with the default inner tolerance the inner
    # solves, not the Newton count, set the difference, 3.9e-9 on `l` here)
    tight = Potts.LatticePDE.DevicePCG(; rtol = 1e-12, budget = 64)
    a2 = run(BackwardEuler(; dt = 0.25, inner = tight))
    @test only(a2.runtimes).cache.newton == 2
    b = run(BackwardEuler(; dt = 0.25, newton = 12, inner = tight))
    for n in names
        @test maximum(abs, a2[n] .- b[n]) < 1e-10
    end
end
