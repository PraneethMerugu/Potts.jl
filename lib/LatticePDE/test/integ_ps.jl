# F2-13 (F2 design §2.13): integrator parameter access by SciML's convention. `integ.ps[x]`
# reads and writes scalars, whole tables and table entries, through the checks of `setp` and of
# a table write (validation, the substep count, the masks and clamps run again, `reset!`).
# `integ[p]` and `integ[p] = v` of a parameter or table are errors that give the `integ.ps`
# route. Base (244d58e7): `ig.ps` a FieldError; `integ[Dk] = values` wrote the table and
# `integ[k]` read the parameter.
psmsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end

@testset "F2-13: integ.ps reads and writes; integ[p] gives the route" begin
    @parameters Dp[1:2] = [1.0, 2.0] kp = 0.5 mvp = 1.0
    pdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    sys = PDESystem([D(ce) ~ Dp[1] * Δ(ce) - kp * ce], [c(0, x, y) ~ 1.0], pdom, [t, x, y], [ce], [Dp, kp]; name = :ps)
    p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64, problem = :owned))
    ig = init(p, ExplicitEuler(; dt = 0.01, substeps = 1))
    # reads: a scalar (as a symbol too), a table, an entry
    @test ig.ps[kp] == 0.5 && ig.ps[:kp] == 0.5 && ig.ps[Dp] == [1.0, 2.0] && ig.ps[Dp[2]] == 2.0
    # writes: a scalar, a whole table, an entry; the problem keeps its own values
    ig.ps[kp] = 0.25
    ig.ps[Dp] = [1.0, 3.0]
    ig.ps[Dp[1]] = 2.0
    @test ig.ps[kp] == 0.25 && ig.ps[Dp] == [2.0, 3.0] && p.tables == ["Dp" => [1.0, 2.0]] && p.p == [0.5]
    # the step reads them: a uniform field decays by (1 − dt kp / n)ⁿ (Δ = 0)
    n = ig.substeps
    step!(ig)
    @test all(≈((1 - 0.01 * 0.25 / n)^n; rtol = 1e-14), ig[ce])
    # the checks: a negative coefficient is refused and nothing changes; the count follows
    neg(err) = occursin("is negative at these parameters", err)
    @test neg(psmsg(() -> (ig.ps[Dp] = [-1.0, 2.0]))) && ig.ps[Dp] == [2.0, 3.0]
    @test neg(psmsg(() -> (ig.ps[Dp[1]] = -1.0))) && ig.ps[Dp[1]] == 2.0
    @test (ig.ps[Dp] = [1000.0, 2.0]; ig.substeps == 712)       # ρ = 128 Dp[1] + kp, dt = 0.01
    @test (ig.ps[Dp[1]] = 1.0; ig.substeps == 1)
    # `integ[p]` and `integ[p] = v` of a parameter or table: the route, never SciML's deprecation
    for (f, want) in ((() -> ig[kp], "`kp` is a parameter: read `integ.ps[kp]`"),
            (() -> ig[:kp], "read `integ.ps[:kp]`"), (() -> (ig[kp] = 1.0), "write `integ.ps[kp] = v`"),
            (() -> ig[Dp], "`Dp` is a table: read `integ.ps[Dp]`"), (() -> (ig[Dp] = [1.0, 2.0]), "write `integ.ps[Dp] = values`"),
            (() -> (ig[Dp[2]] = 1.0), "write `integ.ps[Dp[2]] = v`"), (() -> ig[[ce, kp]], "`kp` is a parameter"))
        err = psmsg(f)
        @test occursin(want, err) && !occursin("deprecated", err)
    end
    @test ig.ps[Dp] == [1.0, 2.0] && ig.ps[kp] == 0.25            # the refused writes changed nothing
    # fields and inputs index as before: a state write, an input write (the mask follows)
    ig[ce] = fill(0.5, 4, 4)
    @test all(==(0.5), ig[ce])
    K = Int32[i <= 2 ? 1 : 0 for i in 1:4, j in 1:4]
    sv = PDESystem([D(ce) ~ Δ(ce)], [c(0, x, y) ~ 0.0, ce ~ masked(qe == 0, mvp)], pdom, [t, x, y], [ce, qe], [mvp]; name = :pm)
    iv = init(discretize(sv, LatticeDiscretization(Grid((4, 4)); T = Float64, problem = :owned); inputs = [qe => K]),
        ExplicitEuler(; dt = 0.001))
    @test iv[ce][3, 1] == 1.0 && iv[ce][1, 1] == 0.0
    # a `ps` write of the mask's value moves the masked sites at once (the init and clamps run again)
    iv.ps[mvp] = 3.0
    @test iv[ce][3, 1] == 3.0 && iv[ce][1, 1] == 0.0
    iv[qe] = zeros(Int32, 4, 4)
    @test all(==(3.0), iv[ce])
    # a `ps` write drops the algorithm's history (`reset!`), as `setp` does
    igs = init(p, GStub(0.01, 0))
    cs = only(igs.runtimes).cache
    igs.ps[Dp[2]] = 5.0
    @test cs.resets == 1
    igs.ps[kp] = 0.1
    @test cs.resets == 2
end
