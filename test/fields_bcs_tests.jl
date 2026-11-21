@testitem "conditions lowered: a Dirichlet face, Flux and Robin" setup = [
    FieldsSetup, FieldsOpBcsSetup,
] tags = [:potts, :fields] begin
    @testset "conditions lowered: a Dirichlet face, Flux and Robin" begin
        LP, MTKB = Potts.LatticePDE, Potts.ModelingToolkitBase
        dims, n = (8, 6), 4
        c0 = rand(StableRNG(5), dims...)
        function run(M; k = 2)
            integ = init(
                PottsProblem(
                    M(; name = :f), [fd_empty(dims); :c => c0], (0, k);
                    field_solver = ExplicitEuler(; substeps = n)
                ), SequentialCPM()
            )
            foreach(_ -> step!(integ), 1:k)
            return Array(current_state(integ).site.c)
        end
        # `c(t, 0, y) ~ 1` is the face value: the hand FTCS with the ghost `2 − c` (the face
        # value is the mean of the edge site and its ghost); without it the run differs
        a1 = run(FbBcsFace; k = 1)
        @test isapprox(
            a1,
            fb_ftcs(c0, 0.5, 1.0, 1.0, n, (d, s, ce) -> d == 1 && s < 0 ? 2.0 - ce : ce);
            rtol = 1.0e-13
        )
        @test run(FbBcsFace) != run(FbNone)
        # a flux and a Robin face: a hand FTCS with the ghost-node rule: low x, ∂c/∂n = q
        # gives c + q h; high x,
        a = run(FbFluxRobin; k = 1)
        # α (c + g′)/2 + β (g′ − c)/h = g gives g′ = (g − c (α/2 − β/h)) / (α/2 + β/h); y
        # zero flux
        function ghost(d, s, ce)
            if d == 2
                return ce
            elseif s < 0
                return ce + 0.2
            else
                return (0.5 - ce * (1.0 - 1.0)) / (1.0 + 1.0)
            end
        end
        hand = fb_ftcs(c0, 0.5, 1.0, 1.0, n, ghost)
        @test isapprox(a, hand; rtol = 1.0e-13)
        # (control: the low side's sign flipped misses the oracle)
        @test !isapprox(
            a,
            fb_ftcs(
                c0, 0.5, 1.0, 1.0, n,
                (d, s, ce) -> d == 1 && s < 0 ? ce - 0.2 : ghost(d, s, ce)
            );
            rtol = 1.0e-6
        )
        # a Neumann and a Robin face match LatticePDE's own run of the same PDESystem
        tt, DD = MTKB.t_nounits, MTKB.D_nounits
        Potts.ModelingToolkitBase.@parameters x y Dc = 0.5 q = 0.2 αr = 2.0 βr = 1.0 gr =
            0.5
        Potts.ModelingToolkitBase.@variables c(..)
        ce = c(tt, x, y)
        bsys = MTKB.PDESystem(
            [DD(ce) ~ Dc * LP.laplacian(ce)],
            [
                c(0, x, y) ~ 0.0, MTKB.Differential(x)(c(tt, 8, y)) ~ q,
                αr * c(tt, x, 0) - βr * MTKB.Differential(y)(c(tt, x, 0)) ~ gr,
            ],
            [
                tt ∈ LP.Interval(0.0, 2.0), x ∈ LP.Interval(0.0, 8.0), y ∈
                    LP.Interval(0.0, 6.0),
            ], [
                tt, x, y,
            ], [ce],
            [Dc, q, αr, βr, gr]; name = :b
        )
        bp = LP.discretize(bsys, LP.LatticeDiscretization(LP.Grid(dims); T = Float64))
        @test run(FbBcsNR) ==
            LP.solve(
            LP.remake(bp; u0 = vec(c0)), LP.ExplicitEuler(; substeps = n);
            dt = 1.0
        )[:c, end]
        # `Potts.fields` carries the conditions
        hasder(f) = any(b -> occursin("Differential(x", string(b)), getfield(f, :bcs))
        @test hasder(Potts.fields(FbFluxRobin(; name = :f))) &&
            hasder(Potts.fields(FbFluxRobinBcs(; name = :f)))
        @test any(
            b -> occursin("c(t, 0.0, y) ~ 1.0", string(b)) ||
                occursin("c(t, 0, y) ~ 1.0", string(b)),
            getfield(Potts.fields(FbBcsFace(; name = :f)), :bcs)
        )
    end
end

@testitem "off-face lines, a self-reading mask, h = 2" setup = [
    FieldsSetup,
    FieldsOpBcsSetup,
] tags = [
    :potts, :fields,
] begin
    @testset "off-face lines, a self-reading mask, h = 2" begin
        # S1: a condition off a face is `parse_bcs`'s, with the faces named (base: "the high
        # side of `x`, which `@boundary c` sets too"); the location names the PDESystem
        err = something(fd_err(() -> mtkcompile(FbInterior(; name = :f))), "")
        @test occursin("`x = 3`", err) || (println("S1: ", err); false)
        # (a): a mask that reads the field it clamps: clamped first, evaluated at each MCS
        # start on the clamped values, held over the MCS (hand oracle)
        c0 = rand(StableRNG(9), 8, 6)
        function run(M; k = 3, n = 1)
            return solve(
                PottsProblem(
                    M(; name = :f), [fd_empty((8, 6)); :c => c0], (0, k);
                    field_solver = ExplicitEuler(; substeps = n)
                ), SequentialCPM()
            ).u[end].site.c
        end
        hand = map(v -> v >= 0.8 ? 0.8 : v, c0)
        for _ in 1:3
            m = hand .>= 0.8
            hand = ifelse.(m, 0.8, hand .+ 0.1)
        end
        a = run(FbSelfMaskBcs)
        @test isapprox(a, hand; rtol = 1.0e-14)
        # R5: with 4 substeps and diffusion, the mask is held over the MCS: evaluated at the
        # window start (then clamped), the values clamped after each substep; the control
        # evaluates the mask at every substep and misses
        function selfmask(rule; n = 4, k = 3)
            c = map(v -> v >= 0.8 ? 0.8 : v, c0)                     # the clamp at init
            for _ in 1:k
                m = c .>= 0.8
                c[m] .= 0.8
                for _ in 1:n
                    rule === :substep && (m = c .>= 0.8)
                    c = fb_ftcs(c, 0.5, 1.0, 1 / n, 1, (d, s, ce) -> ce) .+ 0.1 / n
                    c[m] .= 0.8
                end
            end
            return c
        end
        a = run(FbSelfMaskDiffBcs; n = 4)
        @test isapprox(a, selfmask(:start); rtol = 1.0e-14)
        @test !isapprox(a, selfmask(:substep); rtol = 1.0e-6)
        # N1: `Flux` and `Robin` on both axes at h = 2 against the ghost-node FTCS (α/2 −
        # β/h ≠ 0); the control `q / h` for `q h` misses
        b = solve(
            PottsProblem(
                FbFluxRobin2(; name = :f), [fd_empty((8, 6)); :c => c0], (0, 1);
                field_solver = ExplicitEuler(; substeps = 4)
            ), SequentialCPM()
        ).u[end].site.c
        g2(d, s, ce) = s < 0 ? ce + 0.2 * 2.0 : (0.5 - ce * (1.5 - 0.5)) / (1.5 + 0.5)
        @test isapprox(b, fb_ftcs(c0, 0.5, 2.0, 1.0, 4, g2); rtol = 1.0e-13)
        @test !isapprox(
            b,
            fb_ftcs(
                c0, 0.5, 2.0, 1.0, 4, (d, s, ce) -> s < 0 ? ce + 0.2 / 2.0 : g2(d, s, ce)
            );
            rtol = 1.0e-6
        )
    end
end

# A mask reads the state at its group's
# window start. A mask on `c` that reads `e`, stepped after `c`, reads `e` before its step,
# with one solver group or two (`c`'s first), and equals LatticePDE's own run; a mask on `e`
# that reads `c`, stepped earlier in another solver group, reads `c` as stepped in this MCS
# (as a rate reads another group). The controls (the other oracle in each case) miss.
@testitem "a mask reads its group's window start" setup = [
    FieldsSetup,
    FieldsOpBcsSetup,
] tags = [
    :potts, :fields,
] begin
    @testset "a mask reads its group's window start" begin
        LP = Potts.LatticePDE
        dims, K, N = (8, 6), 3, 4
        c0 = rand(StableRNG(21), dims...)
        e0 = 0.6 .* rand(StableRNG(22), dims...)
        zf(d, s, ce) = ce
        function runA(M; kw...)
            integ = init(
                PottsProblem(
                    M(; name = :f), [fd_empty(dims); :c => c0; :e => e0], (0, K);
                    kw...
                ),
                SequentialCPM()
            )
            return [
                (
                    step!(integ); st = current_state(integ).site;
                    (Array(st.c), Array(st.e))
                ) for _ in 1:K
            ]
        end
        one = (; field_solver = ExplicitEuler(; substeps = N))
        two = (;
            solvers = [
                :c => ExplicitEuler(; substeps = N), :e => ExplicitEuler(; substeps = 2),
            ],
        )
        # the mask on `c` from `e` at the window start (`:start`) or after `e`'s step
        # (`:after`)
        function later(src)
            c, e = copy(c0), copy(e0)
            c[e .>= 0.5] .= 0.8                                       # the clamp at init
            out = Matrix{Float64}[]
            for _ in 1:K
                en = e .+ 0.1
                m = (src === :start ? e : en) .>= 0.5
                c[m] .= 0.8
                for _ in 1:N
                    c = fb_ftcs(c, 0.5, 1.0, 1 / N, 1, zf)
                    c[m] .= 0.8
                end
                e = en
                push!(out, copy(c))
            end
            return out
        end
        hs, ha = later(:start), later(:after)
        @test fd_err(() -> mtkcompile(FbMaskLaterBcs(; name = :f))) === nothing
        for kw in (one, two)
            a = runA(FbMaskLaterBcs; kw...)
            @test all(i -> isapprox(a[i][1], hs[i]; rtol = 1.0e-14), 1:K)
            # control: `e` after its step
            @test !isapprox(a[K][1], ha[K]; rtol = 1.0e-6)
        end
        # LatticePDE's own run (`Potts.fields` → `discretize`) equals the coupled one with
        # one solver group, bitwise
        pf = Potts.fields(FbMaskLaterBcs(; name = :f))
        bp = LP.discretize(
            pf, LP.LatticeDiscretization(LP.Grid(dims); T = Float64);
            u0 = [:c => c0, :e => e0], tspan = (0, K)
        )
        sbp = LP.solve(bp, LP.ExplicitEuler(; substeps = N); dt = 1.0, saveat = 1.0)
        b = [sbp[:c, i] for i in 2:length(sbp.t)]
        @test b == [x[1] for x in runA(FbMaskLaterBcs; one...)]
        # the mask on `e` from `c` at the window start or after `c`'s step
        function earlier(src)
            c, e = copy(c0), copy(e0)
            e[c .>= 0.5] .= 0.0
            out = Matrix{Float64}[]
            for _ in 1:K
                cn = copy(c)
                for _ in 1:N
                    cn = fb_ftcs(cn, 0.5, 1.0, 1 / N, 1, zf) .- (0.2 / N) .* cn
                end
                m = (src === :start ? c : cn) .>= 0.5
                e = ifelse.(m, 0.0, e .+ 0.1)
                c = cn
                push!(out, copy(e))
            end
            return out
        end
        gs, ga = earlier(:start), earlier(:after)
        a1, a2 = runA(FbMaskEarlier; one...), runA(FbMaskEarlier; two...)
        @test all(i -> isapprox(a1[i][2], gs[i]; rtol = 1.0e-14), 1:K) &&
            !isapprox(a1[K][2], ga[K]; rtol = 1.0e-6)
        @test all(i -> isapprox(a2[i][2], ga[i]; rtol = 1.0e-14), 1:K) &&
            !isapprox(a2[K][2], gs[K]; rtol = 1.0e-6)
    end
end

@testitem "a field periodic where the lattice is closed, closed where it wraps" setup = [
    FieldsSetup,
    FieldsOpBcsSetup,
] tags = [
    :potts, :fields,
] begin
    LP = Potts.LatticePDE
    dims, n = (8, 6), 4
    c0 = rand(StableRNG(7), dims...)
    function run(M; k = 2)
        integ = init(
            PottsProblem(
                M(; name = :f), [fd_empty(dims); :c => c0], (0, k);
                field_solver = ExplicitEuler(; substeps = n)
            ), SequentialCPM()
        )
        foreach(_ -> step!(integ), 1:k)
        return Array(current_state(integ).site.c)
    end
    function alone(sys; k = 2)
        p = LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(dims); T = Float64))
        s = LP.solve(
            LP.remake(p; u0 = vec(c0), tspan = (0.0, Float64(k))),
            LP.ExplicitEuler(; substeps = n); dt = 1.0
        )
        return s[:c, end]
    end
    # a pair on y of a closed lattice: `c` wraps on y and stays closed on x, as the same
    # PDESystem discretized on its own (base: refused, "per-field periodicity")
    @test run(FbPeriodicBcs) == alone(FieldsOpBcsSetup.FpPDE.periodic_bcs())
    @test sum(run(FbPeriodicBcs)) ≈ sum(c0) rtol = 1.0e-13
    @test run(FbPeriodicBcs) != run(FbNone)                         # control
    # a face on x of a periodic lattice: `c` is closed on x and wraps on y with the lattice
    @test run(FbFaceOnPeriodic) ==
        alone(FieldsOpBcsSetup.FpPDE.face_periodic_y())
    @test run(FbFaceOnPeriodic) != run(FbBcsFace)   # control
end
