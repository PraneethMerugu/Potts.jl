# Symbolic models on the device (POTTS_GPU = metal | rocm; test/shared/devices.jl, D-157):
# generated code with T = Float32 runs on the device with exact trackers and CPU-equivalent
# statistics (D-029).


@testitem "symbolic models on the device" setup = [GpuSetup, PortsSetup, SymbolicSetup, AdaptiveSetup] tags = [:potts, :gpu, :device] begin
    @testset "symbolic models on the device" begin
        backend = PottsDevices.device_backend()
        σ, kinds = graner_state()
        prob = symbolic_graner_problem(; nmcs = 40, T = Float32)
        u = solve(prob, CheckerboardCPM(); backend).u[end]
        @test u.cell.volume == [count(==(c), u.ownership) for c in eachindex(kinds)]
        n_gg = max(8, required_n(sqrt(2) * 220.0, 800.0; alpha = 1.0e-3, power = 0.9))
        xs = [total_energy(prob, solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:n_gg]
        ys = [total_energy(prob, solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 11:(10 + n_gg)]
        margin = 0.03 * abs(mean(xs))
        res = stat_accept(xs, ys; margin, alpha = 1.0e-3)
        @info "symbolic Graner H, CPU vs device" cpu = mean(xs) device = mean(ys) z = res.statistic pvalue = res.pvalue
        @test res.pass
        # negative control: a wrong temperature is rejected
        xs_hot = [total_energy(prob, solve(remake(prob; seed, p = [:T => 50.0f0]), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:n_gg]
        @test !stat_accept(xs, xs_hot; margin, alpha = 1.0e-3).pass
        for (label, p) in (
                ("wortel", PottsProblem(WORTEL, [ownership => wortel_state(), kind => [1, 1]], (0, 20); T = Float32)),
                ("merks", PottsProblem(MERKS, [ownership => merks_state(), kind => [1, 1]], (0, 20); T = Float32,
                    field_solver = MERKS_SOLVER)),
                ("growing monolayer", PottsProblem(OpenVTGrowingMonolayer(; name = :g, lattice = (40, 40)),
                    [openvt_monolayer_state(; lattice = (40, 40)); :τ => 10.0], (0, 60); T = Float32, capacity = 64)),
                ("openvt", PottsProblem(MONOLAYER, [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [1]], (0, 10);
                    T = Float32, capacity = 8)))
            v = solve(p, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
            @test v.cell.volume == [count(==(c), v.ownership) for c in eachindex(v.cell.volume)]
        end
        # Merks with `BackwardEuler` on the device (the implicit runtime's launches, the
        # status word read at the saves), 20 MCS
        sb = solve(PottsProblem(MERKS, [ownership => merks_state(), kind => [1, 1]], (0, 20); T = Float32,
                field_solver = BackwardEuler(lower_bound = 0.0)
            ), CheckerboardCPM(; proposal = Moore(1)); backend
        )
        cb = Array(sb.u[end].site.c)
        @test sb.retcode == Potts.SciMLBase.ReturnCode.Success && all(isfinite, cb) && minimum(cb) >= 0 && maximum(cb) > 0
        # Crank–Nicolson and BDF2 (their right-side and history launches), 20 MCS
        for fs in (CrankNicolson(lower_bound = 0.0), BDF2(lower_bound = 0.0))
            sx = solve(PottsProblem(MERKS, [ownership => merks_state(), kind => [1, 1]], (0, 20); T = Float32,
                field_solver = fs), CheckerboardCPM(; proposal = Moore(1)); backend)
            cx = Array(sx.u[end].site.c)
            @test sx.retcode == Potts.SciMLBase.ReturnCode.Success && all(isfinite, cx) && minimum(cx) >= 0 && maximum(cx) > 0
        end
        # QuasiSteady (the steady stage, its status checks), 20 MCS; no clip: the steady
        # solve's nonnegativity holds to the solver's tolerance. V₀ = 9.0 is the port's value
        # (test/ports/models.jl:40): the model's V₀ = 100.0 puts the two cells' target volume at the
        # 144-site box's whole medium, which empties `ecm`, removes the `-δc * C * ecm` decay and
        # leaves the steady solve without a unique state (D-276).
        sq = solve(PottsProblem(MERKS, [ownership => merks_state(), kind => [1, 1], :V₀ => 9.0], (0, 20); T = Float32,
            field_solver = QuasiSteady()), CheckerboardCPM(; proposal = Moore(1)); backend)
        cq = Array(sq.u[end].site.c)
        @test sq.retcode == Potts.SciMLBase.ReturnCode.Success && all(isfinite, cq) && minimum(cq) >= -1e-4 * maximum(cq) && maximum(cq) > 0
        σs = zeros(Int32, 60, 30); σs[5:10, 12:17] .= 1; σs[40:45, 12:17] .= 2
        sp = PottsProblem(Spring(; name = :spring), [ownership => σs, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000); T = Float32)
        n_spring = max(12, required_n(1.5, 2.0; alpha = 1.0e-3, power = 0.9))
        ds = [CorePotts.centroid_distance(Float64, solve(remake(sp; seed), CheckerboardCPM(); backend).u[end].cell, sp.lattice, 1, 2) for seed in 1:n_spring]
        @test stat_accept(ds; mu0 = 12.0, margin = 3.0, alpha = 1.0e-3).pass
        @test !stat_accept(ds; mu0 = 20.0, margin = 3.0, alpha = 1.0e-3).pass
        # model-scope updates run as a single-item kernel on the device
        σc, kc = two_kind_blocks()
        cp = PottsProblem(Census(; name = :census), [ownership => σc, kind => kc], (0, 5); T = Float32)
        uc = solve(cp, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test uc.model.total[1] == sum(uc.site.act)
        @test uc.model.ndark[1] == count(c -> kc[c] == 1 && uc.cell.volume[c] > 0, eachindex(kc))
        # compartments: cluster energies, trackers and cluster division on the device
        σk, kk, gk = compartment_state()
        kp = PottsProblem(Compartments(; name = :comp), [ownership => σk, kind => kk, cluster => gk], (0, 4); T = Float32)
        uk = solve(kp, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        cl = Array(uk.cell.cluster)
        @test Array(uk.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(uk.ownership), cl)
        @test Array(uk.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(uk.ownership), cl, kp.lattice, Moore(1); T = Float32)
        @test count(>(0), Array(uk.cell.volume)) == 36
        # components: the batched RK4 cell-ODE kernel in Float32 on the device
        σo = zeros(Int32, 20, 20); σo[3:7, 3:7] .= 1; σo[12:16, 12:16] .= 2
        po = remake(PottsProblem(component_model(), [ownership => σo, kind => [:A, :B]], (0, 10); T = Float32,
                ode_solver = Potts.RK4(substeps = 2));
            p = [:T => 1.0f-9])
        yo = solve(po, CheckerboardCPM(); backend).u[end].cell.decay₊y_c
        @test Array(yo)[1:2] ≈ fill(Float32((1 - 0.15 + 0.15^2 / 2 - 0.15^3 / 6 + 0.15^4 / 24)^20), 2) rtol = 1e-5
        # centroid/displacement: moment trackers read in the proposal and cell kernels
        σm = zeros(Int32, 48, 48); σm[22:26, 22:26] .= 1
        pm = remake(PottsProblem(Persistent(; name = :pm), [ownership => σm, kind => [1]], (0, 20); T = Float32);
            p = [:μ => 1000.0f0])
        um = solve(pm, CheckerboardCPM(); backend).u[end]
        cm = CorePotts.centroid(Float64, map(Array, um.cell), pm.lattice, 1)
        @test Array(um.cell.cx)[1] ≈ cm[1] && Array(um.cell.cy)[1] ≈ cm[2]
        @test Array(um.cell.volume)[1] == count(==(1), Array(um.ownership))
        # setters write through to device memory
        im = init(pm, CheckerboardCPM(); backend)
        im[:px] = [0.25]; im.ps[:μ] = 0.0
        @test Array(im.state.cell.px) == Float32[0.25] && im.p.μ === 0.0f0 && im[:px] == Float32[0.25]
        # a batched `setsym` (a state and a parameter, D-116) writes through too, and the run goes on
        CorePotts.SymbolicIndexingInterface.setsym(im, [:μ, :px])(im, [2.0, [0.5]])
        @test Array(im.state.cell.px) == Float32[0.5] && im.p.μ === 2.0f0
        step!(im)
        @test im.t == 1 && Array(im.state.cell.volume)[1] == count(==(1), Array(im.state.ownership))
        # history rings: pushed and read on the device
        σl = zeros(Int32, 8, 8); σl[3:5, 3:5] .= 1
        ul = solve(PottsProblem(Lags(; name = :l), [ownership => σl, kind => [1]], (0, 7); T = Float32),
            CheckerboardCPM(); backend).u[end]
        @test Array(ul.model.lag3) == Float32[4] && all(==(-1), Array(ul.site.wlag))
        # integral(x): exact per-cell reductions on the device (Int64 fixed point)
        σi = zeros(Int32, 20, 20); σi[3:6, 3:6] .= 1; σi[12:15, 12:15] .= 2
        wi = [Float32(i + j) / 40 for i in 1:20, j in 1:20]
        ui = solve(PottsProblem(Integrals(; name = :i), [ownership => σi, kind => [1, 1], :w => wi], (0, 5); T = Float32),
            CheckerboardCPM(); backend).u[end]
        σh = Array(ui.ownership)
        @test Array(ui.cell.mass) ≈ [sum(wi[σh .== k]) for k in 1:2]
        # integral(x) with site-independent folds: computed once into model slots on the device
        σf, wf = hoisted_init((16, 16))
        wf = Float32.(wf)
        solf = solve(
            PottsProblem(
                HoistedRefresh(; name = :x), [ownership => σf, kind => [:A, :A], :w => wf], (0, 3);
                T = Float32, seed = 5), CheckerboardCPM(); backend)
        uf = solf.u[end]
        σh, Vf = Array(uf.ownership), Array(uf.cell.volume)
        perf(f) = [sum((f(i) for i in findall(==(k), σh)); init = 0.0) for k in eachindex(Vf)]
        vf = sum(Array(uf.cell.v)[Vf .> 0])
        @test vf == 6
        @test Array(uf.cell.s2) ≈ perf(i -> wf[i] * vf) rtol = 1e-5                       # fresh in MCS 3
        mvf = sum(Vf[Vf .> 0]) / count(>(0), Vf)
        # the observed-only integral has no column (D-120): computed from the saved state, its
        # hoisted fold included
        xo = last(Potts._integrals(getfield(mtkcompile(HoistedRefresh(; name = :x)), :sys); observed = true))
        @test !hasproperty(uf.cell, Potts._integral_name(xo))
        @test Array(solf[:o][end]) ≈ perf(i -> wf[i] * mvf)                               # at the MCS boundary
        # model-scope ODEs and a model component (single-item kernel)
        σs2 = zeros(Int32, 20, 20); σs2[2:4, 2:4] .= 1; σs2[10:12, 10:12] .= 2; σs2[15:17, 3:5] .= 3
        us = solve(PottsProblem(Systemic(; name = :s), [ownership => σs2, kind => [1, 1, 1]], (0, 10); T = Float32,
                ode_solver = Potts.RK4(substeps = 4)
            ),
            CheckerboardCPM(); backend).u[end]
        @test Array(us.model.pk₊drug_c)[1] ≈ 3 / 0.2 * (1 - exp(-0.2 * 10)) rtol = 1e-4
        # adaptive host ODEs with a device state (copied once per MCS)
        σa = zeros(Int32, 20, 20); σa[3:6, 3:6] .= 1; σa[12:15, 12:15] .= 2
        ua = solve(PottsProblem(adaptive_model(), [ownership => σa, kind => [:A, :B]], (0, 5);
            T = Float32, ode_solver = Adaptive(Tsit5(); reltol = 1e-6)), CheckerboardCPM(); backend).u[end]
        @test Array(ua.cell.y)[1:2] ≈ fill(exp(-0.3 * 5), 2) rtol = 1e-4
        @test Array(ua.model.g)[1] ≈ 2 - exp(-2.5) rtol = 1e-4
        # hexagonal lattice on the device
        σh = zeros(Int32, 30, 30); nh = 0
        for q in 4:6:26, r in 4:6:26
            nh += 1
            for x in CartesianIndices(σh)
                CorePotts._hexdist(Tuple(x) .- (q, r)) <= 2 && (σh[x] = nh)
            end
        end
        ph = PottsProblem(HexSorting(; name = :h), [ownership => σh, kind => [isodd(k) ? :dark : :light for k in 1:nh]], (0, 20); T = Float32,
            field_solver = ExplicitEuler())
        uh = solve(ph, CheckerboardCPM(proposal = Hex(1)); backend).u[end]
        σhh = Array(uh.ownership)
        @test Array(uh.cell.volume) == [count(==(k), σhh) for k in 1:nh]
        @test Array(uh.cell.surface) ≈ CorePotts.recompute_surface(σhh, ph.lattice, ph.relations.surface, nh; T = Float32)
        # the hexagonal field equals the host run (Float32)
        @test Array(uh.site.c) == solve(ph, CheckerboardCPM(proposal = Hex(1))).u[end].site.c
        # a field on an irregular domain (the domain mask is a filled input); the state type
        # follows the backend (P5 C3/4-2: Float32 on a device)
        σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= first(two_kind_blocks())
        pd = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => last(two_kind_blocks())], (0, 10);
            backend, field_solver = ExplicitEuler())
        @test eltype(pd.u0.site.c) == Float32
        ud = solve(pd, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        uc = solve(pd, CheckerboardCPM(; proposal = Moore(1))).u[end]
        @test Array(ud.ownership) == uc.ownership && Array(ud.site.c) == uc.site.c && sum(uc.site.c) > 0
        # a copy taken before the first step, while the field kernels still compile on a host task
        # in the run context: each integrator steps its own launches, both equal the plain run
        hold = Base.Event()
        CorePotts._COMPILE_HOLD[] = hold                     # the compile task waits until the copy is taken
        i1, i2 = try
            i = init(pd, CheckerboardCPM(; proposal = Moore(1)); backend)
            t = CorePotts._runtime(i.ctx.__fields1).pending
            @test t isa Task && !istaskdone(t)
            i, deepcopy(i)
        finally
            CorePotts._COMPILE_HOLD[] = nothing
            notify(hold)
        end
        foreach(_ -> step!(i2), 1:10)
        foreach(_ -> step!(i1), 1:10)
        for i in (i1, i2)
            @test Array(current_state(i).ownership) == Array(ud.ownership) && Array(current_state(i).site.c) == Array(ud.site.c)
        end
    end
end

@testitem "several relationships on the device (Float32)" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    @testset "several relationships on the device (Float32)" begin
        backend = PottsDevices.device_backend()
        σ = zeros(Int32, 64, 30); σ[5:10, 12:17] .= 1; σ[30:35, 12:17] .= 2; σ[55:60, 12:17] .= 3
        mp = PottsProblem(MetalSprings(; name = :ms), [ownership => σ, kind => [:blob, :blob, :blob],
            :bond => [(1, 2)], :tether => [(2, 3)]], (0, 1500); T = Float32)
        @test eltype(mp.u0.cell.link_rest) == Float32 && eltype(mp.u0.cell.link_len) == Float32
        n_ms = max(16, required_n(1.5, 1.9; alpha = 1.0e-3, power = 0.9))
        d = map(1:n_ms) do seed
            u = solve(remake(mp; seed), CheckerboardCPM(); backend).u[end]
            @test Array(u.cell.volume) == [count(==(c), Array(u.ownership)) for c in 1:3]
            @test Array(u.cell.links__bond) == mp.u0.cell.links__bond          # sweeps never touch links
            (CorePotts.centroid_distance(Float64, u.cell, mp.lattice, 1, 2),
                CorePotts.centroid_distance(Float64, u.cell, mp.lattice, 2, 3))
        end
        @info "two relationships on the device" bond = mean(first.(d)) tether = mean(last.(d))
        @test stat_accept(first.(d); mu0 = 12.0, margin = 3.0, alpha = 1.0e-3).pass
        @test !stat_accept(first.(d); mu0 = 20.0, margin = 3.0, alpha = 1.0e-3).pass
        @test stat_accept(last.(d); mu0 = 18.0, margin = 3.0, alpha = 1.0e-3).pass
        @test !stat_accept(last.(d); mu0 = 26.0, margin = 3.0, alpha = 1.0e-3).pass
    end
end

@testitem "Akeeb invasion on the device (Float32) agrees with the CPU (Float64)" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    @testset "Akeeb invasion on the device (Float32) agrees with the CPU (Float64)" begin
        # A-77: leaders' mean height after 150 MCS (the invasion) and the trackers
        lat = (99, 60)
        function leader_y(backend, T, seed)
            op = PottsModels.akeeb_state(; lattice = lat, seed)
            prob = PottsProblem(PottsModels.AkeebInvasion(; name = :a, lattice = lat), op, (0, 150); capacity = 1000, seed, T)
            u = solve(prob, CheckerboardCPM(; proposal = VonNeumann(1)); backend).u[end]
            σ = Array(u.ownership); kinds = Array(u.cell.kind); vol = Array(u.cell.volume)
            @test vol == [count(==(c), σ) for c in eachindex(vol)]
            @test all(>(0), vol[1:length(op[2].second)])                    # no extinction
            ys = [i[2] for i in CartesianIndices(σ) if σ[i] > 0 && kinds[σ[i]] == 1]
            return mean(ys)
        end
        n_ak = max(12, required_n(sqrt(2) * 1.6, 3.0; alpha = 1.0e-3, power = 0.9))
        cpu = [leader_y(CorePotts.CPU(), Float64, s) for s in 1:n_ak]
        gpu = [leader_y(PottsDevices.device_backend(), Float32, s) for s in 101:(100 + n_ak)]
        res = stat_accept(cpu, gpu; margin = 3.0, alpha = 1.0e-3)
        @info "Akeeb leader height, CPU vs device" cpu = mean(cpu) device = mean(gpu) z = res.statistic pvalue = res.pvalue
        @test res.pass
        @test !stat_accept(cpu, gpu .- 6.0; margin = 3.0, alpha = 1.0e-3).pass
        @test all(>(20), gpu)          # leaders invade (start ≈ 11; ≈ 15.5 at 200 MCS without the cue)
    end
end

@testitem "contact terms reading site values on the device (Float32)" setup = [GpuSetup, SymbolicSetup] tags = [:potts, :gpu, :device] begin
    @testset "contact terms reading site values on the device (Float32)" begin
        backend = PottsDevices.device_backend()
        sys = SiteContacts(; name = :sq)
        p64 = site_contact_problem(sys, (24, 24); tspan = (0, 60))
        p32 = site_contact_problem(sys, (24, 24); tspan = (0, 60), T = Float32)
        u = solve(p32, CheckerboardCPM(); backend).u[end]
        @test eltype(u.site.cue) === Float32 && Array(u.site.cue) == p32.u0.site.cue       # site values stay put
        @test Array(u.cell.volume) == [count(==(c), Array(u.ownership)) for c in eachindex(Array(u.cell.volume))]
        n_sc = max(12, required_n(sqrt(2) * 150.0, 300.0; alpha = 1.0e-3, power = 0.9))
        xs = [total_energy(p64, solve(remake(p64; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:n_sc]
        ys = [total_energy(p64, solve(remake(p32; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 101:(100 + n_sc)]
        margin = 0.1 * abs(mean(xs))
        res = stat_accept(xs, ys; margin, alpha = 1.0e-3)
        @info "site-value contacts H, CPU vs device" cpu = mean(xs) device = mean(ys) z = res.statistic pvalue = res.pvalue
        @test res.pass
        @test !stat_accept(xs, ys .+ 0.25 * abs(mean(xs)); margin, alpha = 1.0e-3).pass
        # an on-copy write read by the contact term, on the device
        σ, kinds, cue = site_contact_state((20, 20); side = 4)
        oc = PottsProblem(SiteContactsOnCopy(; name = :oc), [ownership => σ, kind => fill(:A, length(kinds)), :mark => cue,
            :tag => 2 .* cue], (0, 20); T = Float32)
        v = solve(oc, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test Array(v.cell.volume) == [count(==(c), Array(v.ownership)) for c in eachindex(Array(v.cell.volume))]
        @test any(!=(0.5f0), Array(v.site.tag)) && count(==(0.5f0), Array(v.site.tag)) > 0   # copies cleared tags
    end
end

@testitem "per-rule cadence on the device (Float32)" setup = [GpuSetup, SymbolicSetup] tags = [:potts, :gpu, :device] begin
    @testset "per-rule cadence on the device (Float32)" begin
        backend = PottsDevices.device_backend()
        σ, kinds = rule_cadence_state((48, 32))
        for (na, nb) in ((2, 3), (2, 4), (3, 3))
            prob = PottsProblem(RuleCadences(; name = :rc, na, nb), [ownership => σ, kind => kinds], (0, 5); T = Float32, capacity = 128)
            u = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
            @test live_kinds(u) == (cadence_oracle(na, 5), cadence_oracle(nb, 5))
            @test Array(u.cell.volume) == [count(==(c), Array(u.ownership)) for c in eachindex(Array(u.cell.volume))]
        end
    end
end

@testitem "rule-carrying events on the device (Float32)" setup = [GpuSetup, SymbolicSetup] tags = [:potts, :gpu, :device] begin
    @testset "rule-carrying events on the device (Float32)" begin
        backend = PottsDevices.device_backend()
        σ = zeros(Int32, 48, 32); σ[2:13, 2:13] .= 1
        function run(sys, tspan)
            prob = PottsProblem(sys, [ownership => σ, kind => [:ka]], tspan; capacity = 32, T = Float32)
            u = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
            live = findall(>(0), Array(u.cell.volume))
            return length(live), unique(Array(u.cell.x)[live])
        end
        sys = SameKindCadences(; name = :s)
        @test run(sys, (0, 1)) == (2, [1.0f0])
        @test run(sys, (0, 4)) == (8, [2.0f0])
        @test run(SameKindCadences(; name = :s, na = 1, nb = 2, wb = 10^9), (0, 1)) == (2, [1.0f0])
        # cluster rules: members take their root's rule
        σc, kinds, groups = compartment_state()
        cp = PottsProblem(ClusterCadences(; name = :cc), [ownership => σc, kind => kinds, cluster => groups], (0, 1);
            capacity = 128, T = Float32)
        for (tspan, mass) in (((0, 1), 3.0f0), ((0, 3), 5.0f0))
            u = solve(remake(cp; tspan), CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
            live = findall(>(0), Array(u.cell.volume))
            @test unique(Array(u.cell.mass)[live]) == [mass]
            @test Array(u.cell.volume) == [count(==(c), Array(u.ownership)) for c in eachindex(Array(u.cell.volume))]
        end
    end
end

@testitem "discrete components on the device (Float32)" setup = [GpuSetup, SymbolicSetup] tags = [:potts, :gpu, :device] begin
    @testset "discrete components on the device (Float32)" begin
        backend = PottsDevices.device_backend()
        σ = _discrete_blocks(2)
        prob = PottsProblem(DiscreteHybrid(; name = :h), [ownership => σ, kind => [1, 1], Symbol("tg₊dA") => [false, true]], (0, 8);
            T = Float32)
        cpu = solve(prob, CheckerboardCPM(; proposal = Moore(1)); saveat = 0:8)
        gpu = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 0:8)
        for n in (:tg₊dA, :smp₊dB, :seen)
            @test [Array(getproperty(u.cell, n)) for u in gpu.u] == [getproperty(u.cell, n) for u in cpu.u]
        end
        @test [Array(u.cell.rel₊yx) for u in gpu.u] ≈ [u.cell.rel₊yx for u in cpu.u] rtol = 1e-6
        σ3 = _discrete_blocks(3)
        mp = PottsProblem(discrete_counter_model(ShiftIndex(Clock(2.0)); scope = :model), [ownership => σ3, kind => [1, 1, 1]], (0, 8);
            T = Float32)
        sol = solve(mp, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 0:8)
        @test [Array(u.model.ctr₊dn)[1] for u in sol.u] == [3.0f0 * (t ÷ 2) for t in 0:8]
    end
end

@testitem "scratch-published ticks on the device (Float32)" setup = [GpuSetup, SymbolicSetup] tags = [:potts, :gpu, :device] begin
    @testset "scratch-published ticks on the device (Float32)" begin
        # several tick phases (cell and model scope, two clocks): scratch slots published on the device
        @potts_model GPUDiscreteScratch begin
            @kinds medium A
            @components cells(A) cc = xcell
            @components model mm = mmodel
            @components cells(A) zz = zslow
            @components cells(A) yy = yfast
            @equations begin
                cc.ds ~ mm.dM > 0.5
                mm.dq ~ 1.0 + count(true for c in cells)
                yy.dw ~ zz.dZ
            end
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6)
        end
        prob = PottsProblem(GPUDiscreteScratch(; name = :s), [ownership => _discrete_blocks(2), kind => [1, 1]], (0, 5); T = Float32)
        sol = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend = PottsDevices.device_backend(), saveat = 0:5)
        Z = [isodd(t ÷ 2) for t in 0:5]
        @test [Array(u.model.mm₊dM)[1] for u in sol.u] == Float32[0; fill(3, 5)]
        @test [Array(u.cell.cc₊dX)[1] for u in sol.u] == Float32[0, 0, 1, 1, 1, 1]
        @test [Array(u.cell.zz₊dZ)[2] for u in sol.u] == Float32.(Z)
        @test [Array(u.cell.yy₊dY)[2] for u in sol.u] == Float32.([false; Z[1:5]])
    end
end

@testitem "Jacobi across cells on the device (shift register, Float32)" setup = [GpuSetup, SymbolicSetup] tags = [:potts, :gpu, :device] begin
    @testset "Jacobi across cells on the device (shift register, Float32)" begin
        prob = PottsProblem(DiscreteShiftRegister(; name = :s), [ownership => _discrete_blocks(6, 16), kind => fill(1, 6)], (0, 4);
            T = Float32)
        sol = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend = PottsDevices.device_backend(), saveat = 0:4)
        @test [Array(u.cell.xc₊dX) for u in sol.u] == [Float32.(shift_register_oracle(m)) for m in 0:4]
        ua = solve(PottsProblem(DiscreteArray(; name = :a), [ownership => _discrete_blocks(1, 8), kind => [1]], (0, 5); T = Float32),
            CheckerboardCPM(; proposal = Moore(1)); backend = PottsDevices.device_backend(), saveat = 0:5)
        @test [(Array(u.cell.ar₊dz_1)[1], Array(u.cell.ar₊dz_2)[1]) for u in ua.u] ==
              Tuple{Float32, Float32}[(0, 1), (0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]
    end
end

# Several ODE solver groups step through scratch `x__ode` on the device (fixed-step
# kernels) and through the host (adaptive), then publish: the CPU result in Float32.
@testitem "solver groups on the device (Jacobi scratch)" setup = [GpuSetup, SolversSetup] tags = [:potts, :gpu, :device] begin
    @testset "solver groups on the device (Jacobi scratch)" begin
        backend = PottsDevices.device_backend()
        sys = SolverTriple(; name = :t)
        v(n) = solver_var(sys, n)
        for kw in (
                (; solvers = [v(:s) => Potts.RK4(), v(:h) => Potts.RK4()]),
                (; solvers = [v(:s) => Potts.RK4(), v(:w) => Adaptive(Tsit5(); reltol = 1.0e-6)]),
            )
            prob = PottsProblem(sys, solver_op(), (0, 5); T = Float32, kw...)
            @test haskey(prob.u0.cell, :s__ode)
            cpu = solve(prob, CheckerboardCPM()).u[end]
            gpu = solve(prob, CheckerboardCPM(); backend).u[end]
            @test Array(gpu.ownership) == Array(cpu.ownership)
            for n in (:y, :s, :w)
                @test Array(getproperty(gpu.cell, n)) ≈ Array(getproperty(cpu.cell, n)) rtol = 1e-5
            end
            @test Array(gpu.model.g) ≈ Array(cpu.model.g) rtol = 1e-5
            @test Array(gpu.model.h) ≈ Array(cpu.model.h) rtol = 1e-5
        end
    end
end

@testitem "frozen-kind transitions on the device (Float32, device-built mask)" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    # The frozen acceptance scenario on the device (Float32, CheckerboardCPM). The `[frozen]`
    # kinds are the standard rule, so the mask is rebuilt on the device after the transition.
    module FrozenKindMaskOnDevice
    include(joinpath(@__DIR__, "shared", "pottsmodels_test_file.jl"))
    PottsModelsTestFile.run_file(@__MODULE__, joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "frozen_kind_mask_tests.jl"))
    end
    @testset "frozen-kind transitions on the device (Float32, device-built mask)" begin
        M = FrozenKindMaskOnDevice.FrozenKindMaskSetup
        backend = PottsDevices.device_backend()
        σ = zeros(Int32, 30, 30); σ[5:10, 5:10] .= 1; σ[18:23, 18:23] .= 2
        function device_problem(moves...)
            prob = PottsProblem(
                M.Kinds(; name = :frozen), [ownership => σ, kind => [:cell, :wall]], (0, M.FROZEN_T1);
                seed = 1, T = Float32)
            f = prob.f
            sw = M.Switch(moves)
            lc = Lifecycle(M.Trigger(sw); kind = M.Kind(sw), normal = AlongMinorAxis{Float32}())
            g = CPMFunction(f.delta_H; f.commit!, f.constraint, f.temperature, f.bias, f.phases,
                lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys)
            return remake(prob; f = g)
        end
        prob = device_problem(M.CELL => M.WALL, M.WALL => M.CELL)
        @test Potts.CorePotts.frozen_varies(prob.f.sys) && Potts.CorePotts.frozen_kinds(prob.f.sys) == (M.WALL,)
        sol = solve(prob, CheckerboardCPM(); backend, saveat = 1)
        @test Symbol(sol.retcode) === :Success && sol.stats.lifecycle.transitions == 2
        @test sol.stats.refreshes == 1
        @test M.moved(sol, 1, M.BEFORE) >= length(M.BEFORE) ÷ 2
        @test M.moved(sol, 2, M.BEFORE) == 0
        @test M.moved(sol, 1, M.AFTER) == 0                       # frozen after the transition
        @test M.moved(sol, 2, M.AFTER) >= length(M.AFTER) ÷ 2   # released
        @test frozen_sites(prob, sol.u[end]) == (Array(sol.u[end].ownership) .== 1)
        # negative control: the transition into a free kind keeps moving
        ctl = solve(device_problem(M.CELL => M.OTHER), CheckerboardCPM(); backend, saveat = 1)
        @test M.moved(ctl, 1, M.AFTER) >= length(M.AFTER) ÷ 2
        @test M.moved(ctl, 2, 2:(M.FROZEN_T1 + 1)) == 0
    end
end

@testitem "÷ and div on the device (Float32)" setup = [GpuSetup] tags = [:potts, :gpu, :device] begin
    @testset "÷ and div on the device (Float32)" begin
        σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1; σ[9:12, 9:11] .= 2
        prob = PottsProblem(MetalIntDiv(; name = :d), [ownership => σ, kind => [:A, :A]], (0, 4); seed = 1, T = Float32)
        @test total_energy(prob) == sum((v - 3 - div(v, 3))^2 for v in (9, 12))
        u = solve(prob, CheckerboardCPM(); backend = PottsDevices.device_backend()).u[end]
        V = Array(u.cell.volume)[1:2]
        @test all(>(0), V)
        @test Array(u.cell.h)[1:2] == Float32.(div.(V, 2))
        @test Array(u.cell.q)[1:2] == div.(Float32.(V) .+ 0.5f0, 7.5f0)
        @test Array(u.cell.r)[1:2] == [6.0f0, 6.0f0]                           # 9.5 ÷ 1.5
        @test eltype(u.cell.q) === Float32
        @test total_energy(prob, u) == sum((v - 3 - div(v, 3))^2 for v in V)
    end
end
