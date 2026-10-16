# The standalone MTK form of v3 §7.4, verbatim up to `discretize`: it builds, lowers to a
# LatticeFields program on a 512² grid and runs explicit steps through the host runner. The
# `solve(prob, ExplicitEuler(dt = 1f-2); saveat = 1)` line needs the steppers (C7a).
@testset "§7.4 standalone example" begin
    ex = quote
        using ModelingToolkitBase, LatticePDE
        @parameters t x y Dc = 1e-3 k = 0.1
        @variables c(..)
        @named rd = PDESystem(Differential(t)(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) - k * c(t, x, y),
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [t ∈ Interval(0, 10), x ∈ Interval(0, 1), y ∈ Interval(0, 1)], [t, x, y], [c(t, x, y)], [Dc, k])
        prob = discretize(rd, LatticeDiscretization(Grid((512, 512)); T = Float32, problem = :owned);
                          update = $euler)
    end
    m = Module(:Example74)
    foreach(e -> e isa LineNumberNode || Core.eval(m, e), ex.args)    # `using` before the macros expand
    prob = m.prob
    p = prob.program
    @test p.spacing == (1 / 512, 1 / 512) && p.periodic == (false, true)   # from the domain and the bc pair
    @test prob.defaults == [1e-3, 0.1] && only(values(prob.initial)) == 0.0
    s = semantic(p)
    sp = plan(s)                                                # Float32 bodies
    st = HostStore(s)
    dt = 0.2 / 512^2 / 1e-3                                     # inside the explicit stability limit
    foreach(_ -> run_step!(s, sp, st, prob.defaults; rt = (0.0, dt)), 1:20)
    v = reshape(current(st, s, "c"), 512, 512)
    @test all(isfinite, v) && v[1, 7] > v[2, 7] > v[3, 7] > 0 && v[100, 7] == 0   # fed at x = 0
    @test v[1, :] == fill(v[1, 1], 512)                          # periodic in y: no y dependence
    # the raw `Differential` spelling lowers to the same program (§7.4, P3-rev item 5)
    raw = Core.eval(m, quote
        Dx, Dy = Differential(x), Differential(y)
        @named rd2 = PDESystem(Differential(t)(c(t, x, y)) ~ Dc * (Dx(Dx(c(t, x, y))) + Dy(Dy(c(t, x, y)))) - k * c(t, x, y),
            rd.bcs, rd.domain, [t, x, y], [c(t, x, y)], [Dc, k])
        discretize(rd2, LatticeDiscretization(Grid((512, 512)); T = Float32); update = $euler)
    end)
    @test sprint(LatticeFields.IR.print_program, raw.program) == sprint(LatticeFields.IR.print_program, p)
end
