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
