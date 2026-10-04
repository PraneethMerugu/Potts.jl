# Symbolic models on Metal (POTTS_GPU=metal): generated code with T = Float32 runs on the
# device with exact trackers and CPU-equivalent statistics (D-029).
using Metal
using Statistics: mean, var

@testset "symbolic models on Metal" begin
    backend = MetalBackend()
    σ, kinds = graner_state()
    prob = symbolic_graner_problem(; nmcs = 40, T = Float32)
    u = solve(prob, CheckerboardCPM(); backend).u[end]
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
    xs = [total_energy(prob, solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:8]
    ys = [total_energy(prob, solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 11:18]
    t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8)
    @info "symbolic Graner H, CPU vs Metal" cpu = mean(xs) metal = mean(ys) t
    @test abs(t) < 4
    for (label, p) in (
            ("wortel", PottsProblem(WORTEL, [ownership => wortel_state(), kind => [1, 1]], (0, 20); T = Float32)),
            ("merks", PottsProblem(MERKS, [ownership => merks_state(), kind => [1, 1]], (0, 20); T = Float32,
                field_solver = MERKS_SOLVER)),
            ("growing monolayer", PottsProblem(OpenVTGrowingMonolayer(; name = :g, lattice = (40, 40)),
                [openvt_monolayer_state(; lattice = (40, 40)); :τ => 10.0], (0, 60); T = Float32, capacity = 64)),
            ("openvt", PottsProblem(MONOLAYER, [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [1]], (0, 10);
                T = Float32, capacity = 8)))
        v = solve(p, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test v.cell.volume == [count(==(c), v.σ) for c in eachindex(v.cell.volume)]
    end
    σs = zeros(Int32, 60, 30); σs[5:10, 12:17] .= 1; σs[40:45, 12:17] .= 2
    sp = PottsProblem(Spring(; name = :spring), [ownership => σs, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000); T = Float32)
    ds = [CorePotts.centroid_distance(Float64, solve(remake(sp; seed), CheckerboardCPM(); backend).u[end].cell, sp.lattice, 1, 2) for seed in 1:4]
    @test abs(sum(ds) / 4 - 12.0) < 2.5
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
    @test Array(uk.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(uk.σ), cl)
    @test Array(uk.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(uk.σ), cl, kp.lattice, Moore(1); T = Float32)
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
    @test Array(um.cell.volume)[1] == count(==(1), Array(um.σ))
    # setters write through to device memory
    im = init(pm, CheckerboardCPM(); backend)
    im[:px] = [0.25]; im.ps[:μ] = 0.0
    @test Array(im.state.cell.px) == Float32[0.25] && im.p.μ === 0.0f0 && im[:px] == Float32[0.25]
    # a batched `setsym` (a state and a parameter, D-116) writes through too, and the run goes on
    CorePotts.SymbolicIndexingInterface.setsym(im, [:μ, :px])(im, [2.0, [0.5]])
    @test Array(im.state.cell.px) == Float32[0.5] && im.p.μ === 2.0f0
    step!(im)
    @test im.t == 1 && Array(im.state.cell.volume)[1] == count(==(1), Array(im.state.σ))
    # history rings: pushed and read on the device
    σl = zeros(Int32, 8, 8); σl[3:5, 3:5] .= 1
    ul = solve(PottsProblem(Lags(; name = :l), [ownership => σl, kind => [1]], (0, 7); T = Float32),
        CheckerboardCPM(); backend).u[end]
    @test Array(ul.model.lag3) == Float32[4] && all(==(-1), Array(ul.site.wlag))
    # integral(x): atomic per-cell reductions on the device
    σi = zeros(Int32, 20, 20); σi[3:6, 3:6] .= 1; σi[12:15, 12:15] .= 2
    wi = [Float32(i + j) / 40 for i in 1:20, j in 1:20]
    ui = solve(PottsProblem(Integrals(; name = :i), [ownership => σi, kind => [1, 1], :w => wi], (0, 5); T = Float32),
        CheckerboardCPM(); backend).u[end]
    σh = Array(ui.σ)
    @test Array(ui.cell.mass) ≈ [sum(wi[σh .== k]) for k in 1:2]
    # integral(x) with site-independent folds: computed once into model slots on the device
    σf, wf = p60ai_init((16, 16))
    wf = Float32.(wf)
    solf = solve(PottsProblem(P60aiRefresh(; name = :x), [ownership => σf, kind => [:A, :A], :w => wf], (0, 3);
            T = Float32, seed = 5), CheckerboardCPM(); backend)
    uf = solf.u[end]
    σh, Vf = Array(uf.σ), Array(uf.cell.volume)
    perf(f) = [sum((f(i) for i in findall(==(k), σh)); init = 0.0) for k in eachindex(Vf)]
    vf = sum(Array(uf.cell.v)[Vf .> 0])
    @test vf == 6
    @test Array(uf.cell.s2) ≈ perf(i -> wf[i] * vf) rtol = 1e-5                       # fresh in MCS 3
    mvf = sum(Vf[Vf .> 0]) / count(>(0), Vf)
    # the observed-only integral has no column (D-120): computed from the saved state, its
    # hoisted fold included
    xo = last(Potts._integrals(mtkcompile(P60aiRefresh(; name = :x)).sys; observed = true))
    @test !hasproperty(uf.cell, Potts._integral_name(xo))
    @test Array(solf[:o][end]) ≈ perf(i -> wf[i] * mvf)                               # at the MCS boundary
    # model-scope ODEs and a model component (single-item kernel)
    σs2 = zeros(Int32, 20, 20); σs2[2:4, 2:4] .= 1; σs2[10:12, 10:12] .= 2; σs2[15:17, 3:5] .= 3
    us = solve(PottsProblem(Systemic(; name = :s), [ownership => σs2, kind => [1, 1, 1]], (0, 10); T = Float32,
            ode_solver = RK4(substeps = 4)),
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
    σhh = Array(uh.σ)
    @test Array(uh.cell.volume) == [count(==(k), σhh) for k in 1:nh]
    @test Array(uh.cell.surface) ≈ CorePotts.recompute_surface(σhh, ph.lattice, ph.relations.surface, nh; T = Float32)
end

# P6.0b: two relationships, each with its own store, law and shared read claims, on the device
@potts_model MetalSprings begin
    @kinds medium blob
    @parameters begin
        k₁ = 2.0
        k₂ = 2.0
        J[kind, kind] = [0 16; 16 2]
    end
    @variables begin
        rest(bond) = 12.0
        len(tether) = 18.0
    end
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((64, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 36)^2
        contacts => J[kind, kind′]
        edges(bond) => k₁ * (distance - rest)^2
        edges(tether) => k₂ * (distance - len)^2
    end
    @sweep Metropolis(; temperature = 10.0)
end

@testset "several relationships on Metal (Float32)" begin
    backend = MetalBackend()
    σ = zeros(Int32, 64, 30); σ[5:10, 12:17] .= 1; σ[30:35, 12:17] .= 2; σ[55:60, 12:17] .= 3
    mp = PottsProblem(MetalSprings(; name = :ms), [ownership => σ, kind => [:blob, :blob, :blob],
        :bond => [(1, 2)], :tether => [(2, 3)]], (0, 1500); T = Float32)
    @test eltype(mp.u0.cell.link_rest) == Float32 && eltype(mp.u0.cell.link_len) == Float32
    @test CorePotts.has_reads(mp.f)
    d = map(1:4) do seed
        u = solve(remake(mp; seed), CheckerboardCPM(); backend).u[end]
        @test Array(u.cell.volume) == [count(==(c), Array(u.σ)) for c in 1:3]
        @test Array(u.cell.links__bond) == mp.u0.cell.links__bond          # sweeps never touch links
        (CorePotts.centroid_distance(Float64, u.cell, mp.lattice, 1, 2),
            CorePotts.centroid_distance(Float64, u.cell, mp.lattice, 2, 3))
    end
    @info "two relationships on Metal" bond = mean(first.(d)) tether = mean(last.(d))
    @test abs(mean(first.(d)) - 12.0) < 2.5
    @test abs(mean(last.(d)) - 18.0) < 2.5
end

@testset "Akeeb invasion on Metal (Float32) agrees with the CPU (Float64)" begin
    # A-77: leaders' mean height after 150 MCS (the invasion) and the trackers
    lat = (99, 60)
    function leader_y(backend, T, seed)
        op = PottsModels.akeeb_state(; lattice = lat, seed)
        prob = PottsProblem(PottsModels.AkeebInvasion(; name = :a, lattice = lat), op, (0, 150); capacity = 1000, seed, T)
        u = solve(prob, CheckerboardCPM(; proposal = VonNeumann(1)); backend).u[end]
        σ = Array(u.σ); kinds = Array(u.cell.kind); vol = Array(u.cell.volume)
        @test vol == [count(==(c), σ) for c in eachindex(vol)]
        @test all(>(0), vol[1:length(op[2].second)])                    # no extinction
        ys = [i[2] for i in CartesianIndices(σ) if σ[i] > 0 && kinds[σ[i]] == 1]
        return mean(ys)
    end
    cpu = [leader_y(CorePotts.CPU(), Float64, s) for s in 1:4]
    gpu = [leader_y(MetalBackend(), Float32, s) for s in 11:14]
    t = (mean(cpu) - mean(gpu)) / sqrt(var(cpu) / 4 + var(gpu) / 4)
    @info "Akeeb leader height, CPU vs Metal" cpu = mean(cpu) metal = mean(gpu) t
    @test abs(t) < 4
    @test all(>(20), gpu)          # leaders invade (start ≈ 11; ≈ 15.5 at 200 MCS without the cue)
end

@testset "P6.0e contact terms reading site values on Metal (Float32)" begin
    backend = MetalBackend()
    sys = SiteContacts(; name = :sq)
    p64 = site_contact_problem(sys, (24, 24); tspan = (0, 60))
    p32 = site_contact_problem(sys, (24, 24); tspan = (0, 60), T = Float32)
    u = solve(p32, CheckerboardCPM(); backend).u[end]
    @test eltype(u.site.cue) === Float32 && Array(u.site.cue) == p32.u0.site.cue       # site values stay put
    @test Array(u.cell.volume) == [count(==(c), Array(u.σ)) for c in eachindex(Array(u.cell.volume))]
    xs = [total_energy(p64, solve(remake(p64; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:8]
    ys = [total_energy(p64, solve(remake(p32; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 11:18]
    t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 8 + var(ys) / 8)
    @info "P6.0e site-value contacts H, CPU vs Metal" cpu = mean(xs) metal = mean(ys) t
    @test abs(t) < 4
    # an on-copy write read by the contact term, on the device
    σ, kinds, cue = site_contact_state((20, 20); side = 4)
    oc = PottsProblem(SiteContactsOnCopy(; name = :oc), [ownership => σ, kind => fill(:A, length(kinds)), :mark => cue,
        :tag => 2 .* cue], (0, 20); T = Float32)
    v = solve(oc, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
    @test Array(v.cell.volume) == [count(==(c), Array(v.σ)) for c in eachindex(Array(v.cell.volume))]
    @test any(!=(0.5f0), Array(v.site.tag)) && count(==(0.5f0), Array(v.site.tag)) > 0   # copies cleared tags
end

@testset "P6.0f per-rule cadence on Metal (Float32)" begin
    backend = MetalBackend()
    σ, kinds = rule_cadence_state((48, 32))
    for (na, nb) in ((2, 3), (2, 4), (3, 3))
        prob = PottsProblem(RuleCadences(; name = :rc, na, nb), [ownership => σ, kind => kinds], (0, 5); T = Float32, capacity = 128)
        u = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend).u[end]
        @test live_kinds(u) == (cadence_oracle(na, 5), cadence_oracle(nb, 5))
        @test Array(u.cell.volume) == [count(==(c), Array(u.σ)) for c in eachindex(Array(u.cell.volume))]
    end
end

@testset "P6.0f rule-carrying events on Metal (Float32)" begin
    backend = MetalBackend()
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
        @test Array(u.cell.volume) == [count(==(c), Array(u.σ)) for c in eachindex(Array(u.cell.volume))]
    end
end

# P6.0k: the frozen Boolean-network acceptance file, whose Metal testset runs only where Metal
# is loaded (here), and discrete components with couplings and model scope on the device.
module P60kOnMetal
using Test, Potts
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0k_boolean_network.jl"))
end

@testset "P6.0k discrete components on Metal (Float32)" begin
    backend = MetalBackend()
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

@testset "P6.0k scratch-published ticks on Metal (Float32)" begin
    prob = PottsProblem(GPUDiscreteScratch(; name = :s), [ownership => _discrete_blocks(2), kind => [1, 1]], (0, 5); T = Float32)
    sol = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend = MetalBackend(), saveat = 0:5)
    Z = [isodd(t ÷ 2) for t in 0:5]
    @test [Array(u.model.mm₊dM)[1] for u in sol.u] == Float32[0; fill(3, 5)]
    @test [Array(u.cell.cc₊dX)[1] for u in sol.u] == Float32[0, 0, 1, 1, 1, 1]
    @test [Array(u.cell.zz₊dZ)[2] for u in sol.u] == Float32.(Z)
    @test [Array(u.cell.yy₊dY)[2] for u in sol.u] == Float32.([false; Z[1:5]])
end

@testset "P6.0k Jacobi across cells on Metal (shift register, Float32)" begin
    prob = PottsProblem(DiscreteShiftRegister(; name = :s), [ownership => _discrete_blocks(6, 16), kind => fill(1, 6)], (0, 4);
        T = Float32)
    sol = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend = MetalBackend(), saveat = 0:4)
    @test [Array(u.cell.xc₊dX) for u in sol.u] == [Float32.(shift_register_oracle(m)) for m in 0:4]
    ua = solve(PottsProblem(DiscreteArray(; name = :a), [ownership => _discrete_blocks(1, 8), kind => [1]], (0, 5); T = Float32),
        CheckerboardCPM(; proposal = Moore(1)); backend = MetalBackend(), saveat = 0:5)
    @test [(Array(u.cell.ar₊dz_1)[1], Array(u.cell.ar₊dz_2)[1]) for u in ua.u] ==
          Tuple{Float32, Float32}[(0, 1), (0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]
end

# P6.0c: several ODE solver groups step through scratch `x__ode` on the device (fixed-step
# kernels) and through the host (adaptive), then publish: the CPU result in Float32.
@testset "solver groups on Metal (Jacobi scratch)" begin
    backend = MetalBackend()
    sys = SolverTriple(; name = :t)
    v(n) = solver_var(sys, n)
    for kw in ((; solvers = [v(:s) => RK4(), v(:h) => RK4()]),
               (; solvers = [v(:s) => RK4(), v(:w) => Adaptive(Tsit5(); reltol = 1e-6)]))
        prob = PottsProblem(sys, solver_op(), (0, 5); T = Float32, kw...)
        @test haskey(prob.u0.cell, :s__ode)
        cpu = solve(prob, CheckerboardCPM()).u[end]
        gpu = solve(prob, CheckerboardCPM(); backend).u[end]
        @test Array(gpu.σ) == Array(cpu.σ)
        for n in (:y, :s, :w)
            @test Array(getproperty(gpu.cell, n)) ≈ Array(getproperty(cpu.cell, n)) rtol = 1e-5
        end
        @test Array(gpu.model.g) ≈ Array(cpu.model.g) rtol = 1e-5
        @test Array(gpu.model.h) ≈ Array(cpu.model.h) rtol = 1e-5
    end
end

# P6.0d: the frozen acceptance scenario on Metal (Float32, CheckerboardCPM). The `[frozen]`
# kinds are the standard rule, so the mask is rebuilt on the device after the transition.
module P60dOnMetal
using Test, Potts
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0d_frozen_kind_mask.jl"))
end

@testset "P6.0d frozen-kind transitions on Metal (Float32, device-built mask)" begin
    M = P60dOnMetal
    backend = MetalBackend()
    σ = zeros(Int32, 30, 30); σ[5:10, 5:10] .= 1; σ[18:23, 18:23] .= 2
    function metal_problem(moves...)
        prob = PottsProblem(M.P60dKinds(; name = :p60d), [ownership => σ, kind => [:cell, :wall]], (0, M.P60D_T1);
            seed = 1, T = Float32)
        f = prob.f
        sw = M.P60dSwitch(moves)
        lc = Lifecycle(M.P60dTrigger(sw); kind = M.P60dKind(sw), normal = AlongMinorAxis{Float32}())
        g = CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads, f.temperature, f.bias, f.phases,
            lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys)
        return remake(prob; f = g)
    end
    prob = metal_problem(M.P60D_CELL => M.P60D_WALL, M.P60D_WALL => M.P60D_CELL)
    @test Potts.CorePotts.frozen_varies(prob.f.sys) && Potts.CorePotts.frozen_kinds(prob.f.sys) == (M.P60D_WALL,)
    sol = solve(prob, CheckerboardCPM(); backend, saveat = 1)
    @test Symbol(sol.retcode) === :Success && sol.stats.lifecycle.transitions == 2
    @test sol.stats.refreshes == 1
    @test M.p60d_moved(sol, 1, M.P60D_BEFORE) >= length(M.P60D_BEFORE) ÷ 2
    @test M.p60d_moved(sol, 2, M.P60D_BEFORE) == 0
    @test M.p60d_moved(sol, 1, M.P60D_AFTER) == 0                       # frozen after the transition
    @test M.p60d_moved(sol, 2, M.P60D_AFTER) >= length(M.P60D_AFTER) ÷ 2   # released
    @test frozen_sites(prob, sol.u[end]) == (Array(sol.u[end].σ) .== 1)
    # negative control: the transition into a free kind keeps moving
    ctl = solve(metal_problem(M.P60D_CELL => M.P60D_OTHER), CheckerboardCPM(); backend, saveat = 1)
    @test M.p60d_moved(ctl, 1, M.P60D_AFTER) >= length(M.P60D_AFTER) ÷ 2
    @test M.p60d_moved(ctl, 2, 2:(M.P60D_T1 + 1)) == 0
end

# P6.0v: the frozen transfer-counter acceptance file, whose Metal testset runs only where
# Metal is loaded (here)
module P60vOnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0v_transfer_counters.jl"))
end

# P6.0v2: the frozen column-copy acceptance file (Metal testsets run only here)
module P60v2OnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0v2_column_copies.jl"))
end

# P6.0v2b: the frozen custom-rule refresh acceptance file (Metal testsets run only here)
module P60v2bOnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0v2b_frozen_refresh_bytes.jl"))
end

# P6.0v1: the frozen device-lifecycle acceptance file, whose Metal testsets run only where
# Metal is loaded (here). It wraps `Metal.wait_cmdbuf!` for its own wait count;
# `transfer_counts.jl` below re-wraps it for its own.
module P60v1OnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0v1_device_lifecycle.jl"))
end

# P6.0v3 (with P6.0v8): launch fusion and no hidden GPU wait. The acceptance file's Metal
# testsets run only where Metal is loaded (here); it wraps `Metal.wait_cmdbuf!` for its own
# wait count, and `transfer_counts.jl` below re-wraps it for its own.
module P60v3OnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0v3_launch_fusion.jl"))
end

# P6.0ag: every fixed-step ODE system expanded in place. The acceptance file's Metal testsets
# (each rate shape compiles on the device and equals the CPU Float32 run; a gather ODE runs)
# P6.0ao: `÷`/`div` in generated code stays in Float32 on the device (Base's Float32 `div`
# goes through Float64): a parameter, a variable, a literal and the Int32 `volume`, in an
# energy and in updates, against `div` on the host.
@potts_model MetalIntDiv begin
    @kinds medium A
    @parameters begin
        n = 7.5
    end
    @variables begin
        h(cell) = 0.0
        q(cell) = 0.0
        r(cell) = 0.0
        s(cell) = 9.5
    end
    @lattice Lattice((16, 16); neighborhood = VonNeumann(1))
    @energy cells(A) => (volume - n ÷ 2 - div(volume, 3))^2
    @after_mcs begin
        h ~ volume ÷ 2
        q ~ div(volume + 0.5, n)
        r ~ s ÷ 1.5
    end
    @sweep Metropolis(; temperature = 10.0)
end

@testset "÷ and div on Metal (Float32)" begin
    σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1; σ[9:12, 9:11] .= 2
    prob = PottsProblem(MetalIntDiv(; name = :d), [ownership => σ, kind => [:A, :A]], (0, 4); seed = 1, T = Float32)
    @test total_energy(prob) == sum((v - 3 - div(v, 3))^2 for v in (9, 12))
    u = solve(prob, CheckerboardCPM(); backend = MetalBackend()).u[end]
    V = Array(u.cell.volume)[1:2]
    @test all(>(0), V)
    @test Array(u.cell.h)[1:2] == Float32.(div.(V, 2))
    @test Array(u.cell.q)[1:2] == div.(Float32.(V) .+ 0.5f0, 7.5f0)
    @test Array(u.cell.r)[1:2] == [6.0f0, 6.0f0]                           # 9.5 ÷ 1.5
    @test eltype(u.cell.q) === Float32
    @test total_energy(prob, u) == sum((v - 3 - div(v, 3))^2 for v in V)
end

# run only where Metal is loaded (here).
module P60agOnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0ag_ode_expand_all.jl"))
end

# P6.0af: the staged-form handover after the fused `before` ran (D-108); Metal testsets here
module P60afOnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0af_lifecycle_followups.jl"))
end

# P6.0q: a population fold reading `time` inside a cell ODE (unhoisted) on Metal (D-119);
# the acceptance file's Metal testsets run only where Metal is loaded (here)
module P60qOnMetal
using Test, Potts, PottsModels
include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "acceptance", "p6_0q_time_fold_metal.jl"))
end

# P6.0v: exact host-transfer counts of the current device paths (an ordinary test; P6.0v1/v2
# update its formulas)
include("transfer_counts.jl")
