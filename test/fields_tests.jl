# Fields after the field-compiler cutover (C8): a model's field (a coupled PDESystem) is lowered
# by the field compiler (LatticePDE → LatticeFields) and stepped by explicit Euler over each MCS.
# Oracles: the discrete Fourier factor of FTCS, mass conservation, a hand FTCS stepper; each
# with a negative control (D-048).

@testitem "fields: the Fourier factor of FTCS, with spacing (periodic)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: the Fourier factor of FTCS, with spacing (periodic)" begin
        dims, h = (16, 8), (2.0, 2.0)
        c0 = [cos(2π * (i - 1) / 16) for i in 1:16, j in 1:8]
        for (Dc, nexp) in ((1.0, 2), (4.0, 5))           # ρ = Dc·Σ 4/h² = 2Dc: n = ceil(2Dc/1.8)
            prob = PottsProblem(
                FdPeriodic(; name = :f), [fd_empty(dims); :c => c0; :Dc => Dc], (0, 1);
                field_solver = ExplicitEuler()
            )
            integ = init(prob, SequentialCPM())
            @test fd_n(integ) == nexp
            step!(integ)
            c = Array(current_state(integ).site.c)
            g = 1 - (1 / nexp) * Dc * (4 / h[1]^2) * sin(π / 16)^2      # the per-substep factor of mode 1
            @test maximum(abs.(c .- g^nexp .* c0)) < 1.0e-13
            @test maximum(abs.(c .- (1 - (1 / (nexp + 1)) * Dc * sin(π / 16)^2)^(nexp + 1) .* c0)) > 1.0e-6   # control: n + 1
        end
    end
end

@testitem "fields: auto substep counts, odd and even counts, the hand stepper" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: auto substep counts, odd and even counts, the hand stepper" begin
        dims = (12, 10)
        c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
        # ρ = Dc·8 + k: 5 at Dc = 1; 2 at Dc = 0.45; 3 with a reaction of 0.2
        for (Dc, k, nexp) in ((1.0, 0.0, 5), (0.45, 0.0, 2), (0.45, 0.2, 3))
            prob = PottsProblem(
                FdClosed(; name = :f), [fd_empty(dims); :c => c0; :Dc => Dc; :k => k], (0, 2);
                field_solver = ExplicitEuler()
            )
            integ = init(prob, SequentialCPM())
            @test fd_n(integ) == nexp
            step!(integ); step!(integ)
            hand = fd_ftcs(
                fd_ftcs(c0, Dc, (1, 1), 1.0, nexp; periodic = false, rate = (c, i, j) -> -k * c[i, j]),
                Dc, (1, 1), 1.0, nexp; periodic = false, rate = (c, i, j) -> -k * c[i, j]
            )
            @test maximum(abs.(Array(current_state(integ).site.c) .- hand)) < 1.0e-14
        end
        # an explicit count is a minimum: 3 (odd: the scratch is copied back) and 4 (even)
        for n in (3, 4)
            prob = PottsProblem(
                FdClosed(; name = :f), [fd_empty(dims); :c => c0; :Dc => 0.1], (0, 1);
                field_solver = ExplicitEuler(substeps = n)
            )
            integ = init(prob, SequentialCPM())
            @test fd_n(integ) == n
            step!(integ)
            c = Array(current_state(integ).site.c)
            @test maximum(abs.(c .- fd_ftcs(c0, 0.1, (1, 1), 1.0, n; periodic = false))) < 1.0e-15
            @test maximum(abs.(c .- fd_ftcs(c0, 0.1, (1, 1), 1.0, n + 1; periodic = false))) > 1.0e-8   # control
        end
    end
end

@testitem "fields: mass conservation (periodic and closed), a sink as control" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: mass conservation (periodic and closed), a sink as control" begin
        c0 = [1.0 + sin(i) * cos(2j) for i in 1:16, j in 1:8]
        sol = solve(
            PottsProblem(
                FdPeriodic(; name = :f), [fd_empty((16, 8)); :c => c0], (0, 5);
                field_solver = ExplicitEuler()
            ), SequentialCPM()
        )
        @test abs(sum(sol.u[end].site.c) - sum(c0)) < 1.0e-11 * sum(c0)
        @test maximum(abs.(sol.u[end].site.c .- c0)) > 1.0e-3                              # the field moved
        c1 = [1.0 + sin(i) * cos(2j) for i in 1:12, j in 1:10]
        closed(k) = solve(
            PottsProblem(
                FdClosed(; name = :f), [fd_empty((12, 10)); :c => c1; :k => k], (0, 5);
                field_solver = ExplicitEuler()
            ), SequentialCPM()
        ).u[end].site.c
        @test abs(sum(closed(0.0)) - sum(c1)) < 1.0e-11 * sum(c1)
        @test sum(closed(0.05)) < 0.9 * sum(c1)                                          # control: a sink
    end
end

@testitem "fields: CPM terms are filled inputs (a frozen source, hand oracle)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: CPM terms are filled inputs (a frozen source, hand oracle)" begin
        op = fd_source_op((12, 10))
        prob = PottsProblem(FdSource(; name = :f), op, (0, 3); field_solver = ExplicitEuler(substeps = 2))
        sol = solve(prob, SequentialCPM())
        src = op[1].second .== 1
        hand = zeros(12, 10)
        for _ in 1:3
            hand = fd_ftcs(hand, 0.2, (1, 1), 1.0, 2; periodic = false, rate = (c, i, j) -> 0.05 * src[i, j])
        end
        @test maximum(abs.(sol.u[end].site.c .- hand)) < 1.0e-15
        @test maximum(abs.(sol.u[end].site.c .- 2 .* hand)) > 1.0e-3                      # control
        # the filled input is a site array of the state
        @test any(k -> endswith(string(k), "__in"), keys(prob.u0.site))
    end
end

@testitem "fields: lower clip, also at init" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: lower clip, also at init" begin
        op = fd_empty((6, 6))
        clip = solve(
            PottsProblem(FdDecay(; name = :d), op, (0, 1); field_solver = ExplicitEuler(substeps = 1, lower_bound = 0.0)),
            SequentialCPM()
        ).u[end].site.c
        free = solve(
            PottsProblem(FdDecay(; name = :d), op, (0, 1); field_solver = ExplicitEuler(substeps = 1)),
            SequentialCPM()
        ).u[end].site.c
        @test all(==(0.0), clip)
        @test all(≈(-1.0), free)                                                          # control
    end
end

@testitem "fields: masked conditions, the at-init clamp on fresh states only" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: masked conditions, the at-init clamp on fresh states only" begin
        σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
        op = [ownership => σ, kind => [:wall]]
        wall = σ .== 1
        prob = PottsProblem(FdMask(; name = :m), op, (0, 4); field_solver = ExplicitEuler(substeps = 2))
        integ = init(prob, SequentialCPM())
        @test all(==(3.0), Array(current_state(integ).site.c)[wall])                      # clamped at init
        @test all(==(0.0), Array(current_state(integ).site.c)[.!wall])
        foreach(_ -> step!(integ), 1:2)
        u = current_state(integ)
        @test all(==(3.0), Array(u.site.c)[wall]) && sum(u.site.c[.!wall]) > 0
        # a restored state is not fresh: the clamp does not run at init
        ck = checkpoint(integ)
        ck.state.site.c[wall] .= 5.0
        again = init(prob, SequentialCPM(); checkpoint = ck)
        @test all(==(5.0), Array(current_state(again).site.c)[wall])
        step!(again)
        @test all(==(3.0), Array(current_state(again).site.c)[wall])                      # the mask of the next MCS
        # checkpoint continuation is exact
        whole = solve(prob, SequentialCPM()).u[end]
        integ = init(prob, SequentialCPM()); foreach(_ -> step!(integ), 1:2)
        rest = solve!(init(prob, SequentialCPM(); checkpoint = checkpoint(integ))).u[end]
        @test rest.ownership == whole.ownership && rest.site.c == whole.site.c
        # a new value through `remake` rebinds the mask value
        @test all(==(7.0), solve(remake(prob; p = [:v => 7.0]), SequentialCPM()).u[end].site.c[wall])
    end
end

@testitem "fields: a parameter change rebinds the substep count and the rates" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: a parameter change rebinds the substep count and the rates" begin
        c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
        prob = PottsProblem(FdClosed(; name = :f), [fd_empty((12, 10)); :c => c0], (0, 1); field_solver = ExplicitEuler())
        a = init(prob, SequentialCPM())
        b = init(remake(prob; p = [:Dc => 0.45]), SequentialCPM())
        @test fd_n(a) == 5 && fd_n(b) == 2
        step!(b)
        @test maximum(abs.(Array(current_state(b).site.c) .- fd_ftcs(c0, 0.45, (1, 1), 1.0, 2; periodic = false))) < 1.0e-15
        # in a running integrator: new parameter values are rebound at the next field phase
        a.p = remake(prob; p = [:Dc => 0.45]).p
        step!(a)
        @test fd_n(a) == 2
        @test maximum(abs.(Array(current_state(a).site.c) .- fd_ftcs(c0, 0.45, (1, 1), 1.0, 2; periodic = false))) < 1.0e-15
    end
end

@testitem "fields: setp, then reinit!, keeps the step's substeps (masked model)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: setp, then reinit!, keeps the step's substeps (masked model)" begin
        σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
        op = [ownership => σ, kind => [:wall]]
        prob = PottsProblem(FdMask(; name = :m), op, (0, 4); field_solver = ExplicitEuler(substeps = 2))
        fresh = init(remake(prob; p = [:v => 7.0]), SequentialCPM()); foreach(_ -> step!(fresh), 1:3)
        integ = init(prob, SequentialCPM()); step!(integ)
        setp(integ, :v)(integ, 7.0)                          # a parameter change, then a new start
        reinit!(integ, prob.u0)                              # the at-init clamp runs with the new parameters
        @test fd_n(integ) == 2                               # the step's count, not the clamp's one substep
        foreach(_ -> step!(integ), 1:3)
        u, w = current_state(integ), current_state(fresh)
        @test Array(u.ownership) == Array(w.ownership) && Array(u.site.c) == Array(w.site.c)
        @test sum(u.site.c[σ .== 0]) > 0                     # control: the field evolves
    end
end

@testitem "fields: only the field's own parameters and tables (by value) rebind its launches" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: only the field's own parameters and tables (by value) rebind its launches" begin
        σ = zeros(Int32, 10, 8); σ[:, 8] .= 1
        prob = PottsProblem(FdMask(; name = :m), [ownership => σ, kind => [:wall]], (0, 4); field_solver = ExplicitEuler(substeps = 2))
        integ = init(prob, SequentialCPM()); step!(integ)
        rt = CorePotts._runtime(integ.ctx.__fields1)
        even = rt.steps[1]
        setp(integ, :v)(integ, 3.0)                          # a new parameter object, equal values
        step!(integ)
        @test rt.steps[1] === even && rt.host.p === integ.p           # kept: nothing the field reads changed
        setp(integ, :v)(integ, 4.0)
        step!(integ)
        @test rt.steps[1] !== even                               # control: the mask value changed, rebound
        @test all(==(4.0), Array(current_state(integ).site.c)[σ .== 1])
        # a kind table: an equal table keeps the launches, a new one rebinds and is read
        tp = PottsProblem(FdTab(; name = :t), [ownership => σ, kind => [:A]], (0, 2); field_solver = ExplicitEuler(substeps = 1))
        a = init(tp, SequentialCPM()); step!(a)
        rt = CorePotts._runtime(a.ctx.__fields1); even = rt.steps[1]
        setp(a, :δ)(a, [0.5, 0.0])
        step!(a)
        @test rt.steps[1] === even
        s1 = deepcopy(current_state(a))
        setp(a, :δ)(a, [2.0, 0.0])
        step!(a)
        @test rt.steps[1] !== even
        b = init(remake(tp; u0 = s1, tspan = (2, 3), p = [:δ => [2.0, 0.0]]), SequentialCPM()); step!(b)
        @test Array(current_state(a).site.c) == Array(current_state(b).site.c)
        @test Array(current_state(a).site.c) != Array(s1.site.c)              # control
    end
end

@testitem "fields: an ifelse gate is bounded through its arms" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: an ifelse gate is bounded through its arms" begin
        op = [fd_empty((12, 10)); :c => fd_rand((12, 10))]
        auto = PottsProblem(FdGate(; name = :g), op, (0, 3); field_solver = ExplicitEuler())
        @test fd_n(init(auto, SequentialCPM())) == 5                         # ceil(1.0·8 / 1.8)
        one = @test_logs PottsProblem(FdGate(; name = :g), op, (0, 3); field_solver = ExplicitEuler(substeps = 1))
        integ = init(one, SequentialCPM())
        @test fd_n(integ) == 5                                               # the request 1 is a minimum
        setp(integ, :Dc)(integ, 2.0)
        step!(integ)
        @test fd_n(integ) == 9                                               # ceil(2.0·8 / 1.8)
        @test all(isfinite, Array(current_state(integ).site.c))
    end
end

@testitem "fields: hexagonal lattices (the old path's six-point Laplacian)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: hexagonal lattices (the old path's six-point Laplacian)" begin
        for boundary in (Periodic(), Closed())
            prob = PottsProblem(
                FdHex(; name = :h, boundary), [fd_empty((8, 6)); :c => fd_rand((8, 6))], (0, 3);
                field_solver = ExplicitEuler(substeps = 3)
            )
            u = fd_mcs(prob, 3)
            c = prob.u0.site.c
            for m in 1:3
                c = fd_oldpath(c, prob.lattice, 0.1, 3)
                @test maximum(abs.(u[m] .- c)) < 1.0e-14
            end
            @test sum(u[end]) ≈ sum(prob.u0.site.c)                                 # zero-sum stencil
            # negative control: the square 4-point stencil is a different field
            sq = fd_ftcs(prob.u0.site.c, 0.1, (1, 1), 1.0, 3; periodic = boundary isa Periodic)
            @test maximum(abs.(u[1] .- sq)) > 1.0e-3
        end
        # the stencil is exact for a quadratic: Δ|x|² = 4 (Euclidean positions of the axial sites)
        L = (24, 24)
        hl = CorePotts.Lattice(L; geometry = CorePotts.Hexagonal(), boundary = Closed())
        pos(x) = CorePotts.embed(hl, Float64.(Tuple(x)))
        f = [sum(abs2, pos(x)) for x in CartesianIndices(L)]
        prob = PottsProblem(
            FdHex(; name = :h, boundary = Closed(), dims = L), [fd_empty(L); :c => f], (0, 1);
            field_solver = ExplicitEuler(substeps = 1)
        )
        c1 = solve(prob, SequentialCPM(); save_start = false).u[1].site.c
        @test (c1[10, 12] - f[10, 12]) / 0.1 ≈ 4.0
        # the program reads the six axial neighbors, and only those (the IR's hexagonal offsets)
        prog = first(ph for t in prob.f.phases.mcs if t isa Tuple for ph in t if ph isa CorePotts.FieldPhase).program
        offs = Set(Tuple(Int.(a.offset.a)) for k in prog.kernels for a in k.accesses if any(!iszero, a.offset.a))
        @test offs == Set(FD_HEX6)
    end
end

@testitem "fields: an irregular domain (zero flux at its edge, as the old path)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: an irregular domain (zero flux at its edge, as the old path)" begin
        prob0 = PottsProblem(FdDomain(; name = :d), fd_empty((40, 40)), (0, 1); field_solver = ExplicitEuler(substeps = 2))
        lat = prob0.lattice
        inmask = [CorePotts.in_domain(lat, i) for i in 1:(40 * 40)]
        c0 = zeros(40, 40); c0[18:23, 18:23] .= 1.0; c0[1, 1] = 7.0                 # (1, 1) is outside
        prob = PottsProblem(FdDomain(; name = :d), [fd_empty((40, 40)); :c => c0], (0, 200); field_solver = ExplicitEuler(substeps = 2))
        u = solve(prob, SequentialCPM(); save_start = false).u
        @test sum(u[end].site.c[inmask]) ≈ 36.0                                   # conserved inside
        @test u[end].site.c[1, 1] == 7.0                                          # outside: no exchange
        @test maximum(u[end].site.c[inmask]) - minimum(u[end].site.c[inmask]) < 0.05  # equilibrates inside
        # the old path's numerics, MCS by MCS, on a random field (outside sites too)
        r = fd_rand((40, 40))
        pr = PottsProblem(FdDomain(; name = :d), [fd_empty((40, 40)); :c => r], (0, 3); field_solver = ExplicitEuler(substeps = 2))
        ur = fd_mcs(pr, 3)
        c = r
        for m in 1:3
            c = fd_oldpath(c, lat, 0.2, 2)
            @test maximum(abs.(ur[m] .- c)) < 1.0e-14
        end
        # negative control: the full box exchanges across the disk's edge
        full = PottsProblem(
            FdDomain(; name = :f, domain = x -> true), [fd_empty((40, 40)); :c => r], (0, 1);
            field_solver = ExplicitEuler(substeps = 2)
        )
        @test maximum(abs.(fd_mcs(full, 1)[1] .- ur[1])) > 1.0e-3
        # faces against the domain edge: the face value applies at the box face, not at the edge
        st = PottsProblem(FdStripe(; name = :s), fd_empty((9, 9)), (0, 1); field_solver = ExplicitEuler(substeps = 1))
        us = solve(st, SequentialCPM(); save_start = false).u[1].site.c
        @test us == fd_oldpath(zeros(9, 9), st.lattice, 0.1, 1; bc = ((0.0, 100.0), (nothing, nothing)))
        @test all(iszero, us)                                                     # x = 7 is the edge: zero flux
        # control: on the full box the same face drives the edge site
        @test fd_oldpath(
            zeros(9, 9), Potts.CorePotts.Lattice((9, 9); boundary = Closed()), 0.1, 1;
            bc = ((0.0, 100.0), (nothing, nothing))
        )[9, 5] ≈ 0.1 * 200.0
    end
end

@testitem "fields: refusals name the reason" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: refusals name the reason" begin
        @test occursin(
            "rand()", something(
                fd_err(
                    () -> PottsProblem(
                        FdRand(; name = :r), fd_empty((8, 6)), (0, 1);
                        field_solver = ExplicitEuler(substeps = 1)
                    )
                ), ""
            )
        )
        @test occursin(
            "field solver", something(
                fd_err(
                    () -> PottsProblem(
                        FdClosed(; name = :f), fd_empty((12, 10)), (0, 1);
                        field_solver = Potts.RK4()
                    )
                ), ""
            )
        )
    end
end

@testitem "fields: a warm MCS allocates nothing on the CPU" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: a warm MCS allocates nothing on the CPU" begin
        op = fd_source_op((12, 10))
        integ = init(
            PottsProblem(FdSource(; name = :f), op, (0, 100); field_solver = ExplicitEuler(substeps = 3)), SequentialCPM();
            save_start = false, save_end = false, save_everystep = false
        )
        step!(integ)
        @test (@allocated step!(integ)) == 0
    end
end

@testitem "parameters: a value that does not convert is named, with a role-neutral reason" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "parameters: a value that does not convert is named, with a role-neutral reason" begin
        err = fd_err(
            () -> PottsProblem(
                FdClosed(; name = :f), [fd_empty((12, 10)); :Dc => FdNotANumber()], (0, 1);
                field_solver = ExplicitEuler()
            )
        )
        @test occursin("`Dc`", something(err, "")) && occursin("scalar type", something(err, ""))
        @test occursin("A Dual goes to the problem", something(err, ""))     # (the route since F3-21b)
        @test !occursin("CPM parameters are plain numbers", something(err, ""))
    end
end

@testitem "fields: number types per role (lattice_storage, the backend's default T)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "fields: number types per role (lattice_storage, the backend's default T)" begin
        c0 = [exp(-((i - 6)^2 + (j - 5)^2) / 4) for i in 1:12, j in 1:10]
        for T in (Float64, Float32)
            prob = PottsProblem(
                FdHalf(; name = :h), [fd_empty((12, 10)); :c => c0], (0, 3); T,
                field_solver = ExplicitEuler(substeps = 8)
            )
            @test eltype(prob.u0.site.c) == Float16 && eltype(prob.u0.site.c__next) == Float16
            u = fd_mcs(prob, 3)
            @test eltype(u[end]) == Float16
            ref = fd_ftcs(Float64.(Float16.(c0)), 1.0, (1, 1), 3.0, 8 * 3; periodic = false)
            @test maximum(abs.(u[end] .- ref)) < 5.0e-3                     # Float16 rounding per substep
            # control: the same model stored in T differs by the rounding
            full = PottsProblem(
                FdClosed(; name = :f), [fd_empty((12, 10)); :c => c0], (0, 3); T,
                field_solver = ExplicitEuler(substeps = 8)
            )
            @test eltype(full.u0.site.c) == T && fd_mcs(full, 3)[end] != u[end]
        end
        let err = try
                Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_storage = Float16); nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("lattice_storage", sprint(showerror, err)) && occursin("applies to fields", sprint(showerror, err))
        end
        # the default state type follows the backend (host: Float64)
        @test eltype(
            PottsProblem(
                FdClosed(; name = :f), fd_empty((12, 10)), (0, 1);
                backend = CorePotts.KernelAbstractions.CPU(), field_solver = ExplicitEuler()
            ).u0.site.c
        ) == Float64
    end
end

@testitem "F1 SD-14, F4-12a: a boundary value is an expression of parameters" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 SD-14, F4-12a: a boundary value is an expression of parameters" begin
        # F1: refused at the model with the computed-parameter route ("… is an expression of
        # parameters; … `@parameters g = g1 + g2`"); F4-12a (FE-10): it runs, and equals the
        # computed parameter's run bitwise, also after a write
        @test fd_err(() -> FdExprFace(; name = :f)) === nothing
        run(M, p = []) = solve(PottsProblem(M(; name = :f), [fd_empty((8, 8)); p], (0, 2); field_solver = ExplicitEuler())).u[end].site.c
        a = run(FdExprFace)
        @test a == run(FdComputedFace) && maximum(a) > 0
        b = run(FdExprFace, [:g1 => 3.0])
        @test b == run(FdComputedFace, [:g1 => 3.0]) && maximum(b) > maximum(a)
    end
end

@testitem "F1 V13: Potts.fields returns the model's PDESystem" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 V13: Potts.fields returns the model's PDESystem" begin
        # base: `Potts.fields(model) === nothing` on a model with fields
        @test Potts.fields(FdClosed(; name = :f)) isa Potts.ModelingToolkitBase.PDESystem
        @test Potts.fields(mtkcompile(FdClosed(; name = :f))) isa Potts.ModelingToolkitBase.PDESystem
        @test isequal(
            Potts.ModelingToolkitBase.equations(Potts.fields(FdClosed(; name = :f))),
            Potts.ModelingToolkitBase.equations(Potts.fields(mtkcompile(FdClosed(; name = :f))))
        )
        # … with the model's defaults, so `discretize` takes it as it is (base, round 0: the field
        # and the parameters had no value, "no initial condition" / NaN): c(1) = 2 (1 − 0.05)^10
        LP = Potts.LatticePDE
        for m in (FdDefaults(; name = :f), mtkcompile(FdDefaults(; name = :f)))
            prob = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64))
            s = LP.solve(prob, LP.ExplicitEuler(; substeps = 1); dt = 0.1)
            @test s.retcode == Potts.SciMLBase.ReturnCode.Success && all(≈(2 * 0.95^10), s[:c, end])
            o = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64))
            @test o isa Potts.SciMLBase.ODEProblem && o.p.values == [1.0, 0.5] && all(==(2.0), o.u0)
        end
        # a computed parameter folds and reads (round 1: reading threw): c(1) = (1 − 0.1)^10
        prob = LP.discretize(
            Potts.fields(FdComputedRate(; name = :f)), LP.LatticeDiscretization(
                LP.Grid((6, 4));
                T = Float64
            )
        )
        @test LP.getp(prob, :k2)(prob) == 1.0
        @test all(≈(0.9^10), LP.solve(prob, LP.ExplicitEuler(; substeps = 1); dt = 0.1)[:c, end])
        @test LP.getp(LP.remake(prob; p = [:k => 1.0]), :k2)(LP.remake(prob; p = [:k => 1.0])) == 2.0
        # a kind table on the ODE path is the table (round 2: the right side read the state for
        # it); c = 1 on medium sites: dc/dt = −δ[medium] = −0.5
        o = LP.discretize(
            Potts.fields(FdTab(; name = :f)), LP.LatticeDiscretization(LP.Grid((10, 8)); T = Float64);
            inputs = [:kind => zeros(Int32, 10, 8)]
        )
        du = similar(o.u0)
        o.f(du, o.u0, o.p, 0.0)
        @test all(≈(-0.5), du)
        # a field named like a generated input is refused in the model's words (round 4 via A:
        # "the input field `domain__in` has the name `domain`")
        err = something(fd_err(() -> Potts.fields(FdDomainWord(; name = :f))), "(no error)")
        @test occursin("`domain` (the lattice's domain mask)", err) && occursin("also a field", err) && !occursin("__in", err)
        # … and reads back on the owned path (round 3: "`:δ` names nothing of this problem")
        po = LP.discretize(Potts.fields(FdTab(; name = :f)), LP.LatticeDiscretization(LP.Grid((10, 8)); T = Float64); inputs = [:kind => zeros(Int32, 10, 8)])
        ig = LP.init(po, LP.ExplicitEuler(; substeps = 1); dt = 0.1)
        @test ig.ps[:δ] == [0.5, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
        LP.setp(ig, :δ)(ig, [1.0, 0.0])                     # an integrator's table is set (F2-13)
        @test ig.ps[:δ] == [1.0, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
        # a problem's table is set as SciML sets a parameter, in place (F4-00; base: refused, "`δ` is a table")
        pw = LP.remake(po; p = [:δ => [0.5, 0.0]])
        LP.setp(pw, :δ)(pw, [1.0, 0.0])
        @test LP.getp(pw, :δ)(pw) == [1.0, 0.0] && LP.getp(po, :δ)(po) == [0.5, 0.0]
        # a CPM coupling is an input given by its key: one step of `s · (kind == A)` from c = 0
        K = zeros(Int32, 12, 10); K[3:5, 4:6] .= 1
        prob = LP.discretize(Potts.fields(FdSource(; name = :f)), LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64); inputs = [:kind => K])
        s = LP.solve(prob, LP.ExplicitEuler(; substeps = 1); dt = 0.1, saveat = 0.1)
        @test s[:c, 2] ≈ 0.1 * 0.05 .* (K .== 1)
        # … by the model's word (round 1: only the generated key "kind__in"); "kind" too, and the
        # messages print routes that run, never `__in`
        fe(f) = something(fd_err(f), "(no error)")
        fsrc = Potts.fields(FdSource(; name = :f))
        disc = LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)
        @test LP.discretize(fsrc, disc; inputs = ["kind" => K]).p.inputs == prob.p.inputs
        err = fe(() -> LP.solve(LP.discretize(fsrc, disc), LP.ExplicitEuler(); dt = 0.1))
        @test occursin("`kind`", err) && occursin(":kind => values", err) && !occursin("__in", err)
        # (F4-01: an unset input is named when the problem is solved, by a field algorithm or an
        # OrdinaryDiffEq solver; base: at `discretize` of the ODE problem)
        err = fe(() -> (q = LP.discretize(fsrc, LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)); q.f(similar(q.u0), q.u0, q.p, 0.0)))
        @test occursin(":kind => values", err) && !occursin("__in", err)
        err = fe(() -> LP.discretize(fsrc, disc; inputs = [:kd => K]))
        @test occursin("`kind`", err) && !occursin("__in", err)
        # (the input of a bound CPM read is named by the PDESystem's input bound to it, `volume`;
        # F4-B6 review: before, by the expression text "LatticePDE.value_at(volume, owner)")
        fvol = Potts.fields(FdVolumeRead(; name = :f))
        V = fill(2.0, 6, 4)
        s = LP.solve(
            LP.discretize(
                fvol, LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64);
                inputs = ["volume" => V]
            ), LP.ExplicitEuler(; substeps = 1); dt = 0.1, saveat = 0.1
        )
        @test all(≈(0.1 * 0.01 * 2.0), s[:c, 2])
        err = fe(() -> LP.solve(LP.discretize(fvol, LP.LatticeDiscretization(LP.Grid((6, 4)); T = Float64)), LP.ExplicitEuler(); dt = 0.1))
        @test occursin("volume", err) && occursin("=> values", err) && !occursin("__in", err) || (println("V13: ", err); false)
    end
end

@testitem "F1 messages: field terms in the model's words (PO02, PO06)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 messages: field terms in the model's words (PO02, PO06)" begin
        # PO06: the substep refusal names `kind`, not the generated input `kind__in(t, x, y)`
        err = something(
            fd_err(
                () -> PottsProblem(
                    FdKindNonlinear(; name = :f), fd_empty((8, 8)), (0, 1);
                    field_solver = ExplicitEuler()
                )
            ), ""
        )
        @test occursin("kind", err) && !occursin("kind__in", err) && occursin("substeps = n", err)
        # PO02: LatticePDE's operators lower in `@equations` (F2-10; F1 named them "does not lower",
        # base f9a77dd3: "reads a field or site variable inside a CPM read")
        @test fd_err(() -> mtkcompile(FdDivK(; name = :f))) === nothing
    end
end

@testitem "F1 V11: a Float64 problem on a device backend gives a notice" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F1 V11: a Float64 problem on a device backend gives a notice" begin
        prob = PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1); field_solver = ExplicitEuler())
        @test_logs (:warn, r"built in Float64") CorePotts._device_float_notice(prob, FdFakeDevice())
        # controls: the host backend, and a Float32 problem (base: no notice anywhere)
        @test_logs CorePotts._device_float_notice(prob, Potts.KernelAbstractions.CPU()) == false
        p32 = PottsProblem(FdClosed(; name = :f), fd_empty((12, 10)), (0, 1); field_solver = ExplicitEuler(), T = Float32)
        @test_logs CorePotts._device_float_notice(p32, FdFakeDevice()) == false
    end
end

# F2-12 (F2 design §2.8): `Potts.fields(model)` → `discretize(…; p = [:k => 2.0])` runs with no
# `remake` (base: a `MethodError`, the keyword did not exist)
@testitem "F2-12: Potts.fields then discretize with keywords" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-12: Potts.fields then discretize with keywords" begin
        LP = Potts.LatticePDE
        disc = LP.LatticeDiscretization(LP.Grid((12, 10)); T = Float64)
        prob = LP.discretize(Potts.fields(FdClosed(; name = :f)), disc; p = [:k => 0.5], u0 = [:c => 1.0], tspan = (0, 1))
        @test LP.getp(prob, :k)(prob) == 0.5 && all(==(1.0), prob.u0)
        # a uniform field decays by (1 − 0.1 k) per step: 0.95^10 (control: the default k = 0 keeps 1)
        @test all(≈(0.95^10; rtol = 1.0e-13), LP.solve(prob, LP.ExplicitEuler(; substeps = 1); dt = 0.1)[:c, end])
    end
end

@testitem "F2-15: computed parameters read-only and derived, in a model and in B" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-15: computed parameters read-only and derived, in a model and in B" begin
        LP, SII = Potts.LatticePDE, Potts.SymbolicIndexingInterface
        err(f) = something(fd_err(f), "")
        c0 = rand(StableRNG(15), 8, 6)
        # A computed face value through `Potts.fields`: B's owned run equals A's field (σ frozen,
        # no cell), bitwise, and both follow `g1`
        prob = PottsProblem(
            FdComputedFace(; name = :f), [fd_empty((8, 8)); :c => rand(StableRNG(4), 8, 8)], (0, 2);
            field_solver = ExplicitEuler(; substeps = 2)
        )
        a = solve(prob, SequentialCPM()).u[end].site.c
        bp = LP.discretize(Potts.fields(FdComputedFace(; name = :f)), LP.LatticeDiscretization(LP.Grid((8, 8)); T = Float64); u0 = [:c => prob.u0.site.c], tspan = (0, 2))
        @test LP.solve(bp, LP.ExplicitEuler(; substeps = 2); dt = 1.0)[:c, end] == a
        a3 = solve(Potts.remake(prob; p = [:g1 => 3.0]), SequentialCPM()).u[end].site.c
        @test LP.solve(LP.remake(bp; p = [:g1 => 3.0]), LP.ExplicitEuler(; substeps = 2); dt = 1.0)[:c, end] == a3 != a
        # one table of writes against the model, B owned and B ODE: equal values, equal refusals
        pa = PottsProblem(FdChainK(; name = :k), [fd_empty((8, 6)); :c => c0], (0, 1))
        sysb = Potts.fields(FdChainK(; name = :k))
        # (F4-01: `po` is the owned problem of the one problem `discretize` returns, `pd` that problem)
        disc() = LP.LatticeDiscretization(LP.Grid((8, 6)); T = Float64)
        po, pd = LP.Problems.field_problem(LP.discretize(sysb, disc())), LP.discretize(sysb, disc())
        reads(q) = (getp(q, :β)(q), getp(q, :γ)(q))
        for (write, want) in (([:α => 0.2], (0.4, 0.45)), ([:α => 0.0], (0.0, 0.05)), ([:Dc => 0.3], (0.2, 0.25)))
            @test reads(Potts.remake(pa; p = write)) == reads(LP.remake(po; p = write)) == reads(LP.remake(pd; p = write)) == want
        end
        for write in ([:β => 1.0], [:γ => 1.0], [:α => 0.2, :γ => 1.0])
            ea, eo, ed = err(() -> Potts.remake(pa; p = write)), err(() -> LP.remake(po; p = write)), err(() -> LP.remake(pd; p = write))
            n = String(first(last(write)))
            for e in (ea, eo, ed)
                @test occursin("`$n` is computed from `α`", e) && occursin("set `α`", e)
            end
        end
        # the derivation is transitive: α → β → γ moves γ, and the run reads it (A equals B's ODE
        # right side at the new values)
        ia = init(Potts.remake(pa; p = [:α => 0.3]), SequentialCPM())
        @test ia.ps[:γ] == 0.65 && !SII.is_parameter(ia, :γ) && SII.is_observed(ia, :γ)
        ib = LP.init(po, LP.ExplicitEuler(); dt = 1.0)
        ib.ps[:α] = 0.3
        @test ib.ps[:γ] == 0.65
        step!(ib)
        @test ib[:c] == LP.solve(LP.remake(po; p = [:α => 0.3]), LP.ExplicitEuler(); dt = 1.0)[:c, end]   # the step reads γ
        @test occursin("`γ` is computed from `α`", err(() -> (ib.ps[:γ] = 1.0))) && ib.ps[:γ] == 0.65
        # SciMLStructures: A's `replace` derives again; B's parameter vector, replaced whole with a
        # stale computed slot, is derived again by `remake`
        SS = Potts.SciMLStructures
        q = SS.replace(SS.Tunable(), pa.p, [0.3, 0.2])
        @test (q.α, q.β, q.γ) == (0.3, 0.6, 0.65)
        v = copy(po.p)
        v[SII.parameter_index(po, :α)] = 0.3
        v[findfirst(==(0.25), v)] = 99.0                    # γ's slot, stale
        r = LP.remake(po; p = v)
        @test getp(r, :γ)(r) == 0.65 && !(99.0 in r.p)
        @test LP.solve(r, LP.ExplicitEuler(); dt = 1.0)[:c, end] == LP.solve(LP.remake(po; p = [:α => 0.3]), LP.ExplicitEuler(); dt = 1.0)[:c, end]
    end
end
