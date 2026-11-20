# GPU group (opt-in: COREPOTTS_GPU or POTTS_GPU = metal | rocm; the backend comes from
# test/shared/devices.jl, D-157). Trackers stay exact on the device; statistics
# agree with the CPU (D-029: statistical, not bitwise, CPU/GPU agreement).

@testsetup module CP_gpu
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
# PottsDevices (the old runner included it into Main)
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "devices.jl"))
# imports an earlier file made in the old single Main
using CorePotts: GlobalSearch
using CorePotts: Proposal
using CorePotts: global_gains
using CorePotts: global_keeps
include("shared/gg_model.jl")
include("shared/geometry.jl")
include("shared/phases.jl")
include("shared/drives.jl")
include("shared/cell_sums.jl")
include("shared/lifecycle.jl")
include("shared/compartments.jl")
include("shared/contact_counts.jl")
include("shared/euler.jl")
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "props.jl"))

# Whole-cell connectivity on the device (`pieces.jl`): the windowed veto (the parallel
# deferred kernel), the exact veto (the serial deferred kernel) and an inline exact search
# (the serial kernel over the flood scratch). Compiles every connectivity kernel (D-157).
# both cells: the gaining one locally, the losing one by the search
function global_post_window(st, p, prop, ctx, stage)
    if CorePotts.global_gains(st.ownership, ctx, prop, Val(false))
        return CorePotts.global_keeps(st.ownership, ctx, prop, Val(false), Val(2), Val(25), stage)
    else
        return Int32(2)
    end
end
function global_post_exact(st, p, prop, ctx, stage)
    if CorePotts.global_gains(st.ownership, ctx, prop, Val(false))
        return CorePotts.global_keeps(st.ownership, ctx, prop, Val(false), Val(nothing), Val(0), stage)
    else
        return Int32(2)
    end
end
global_defer_check(st, p, prop, ctx) = CorePotts.global_defer(st.ownership, ctx, prop, Val(false))
global_penalty_dH(st, p, prop, ctx) = gg_delta_H(st, p, prop, ctx) +
    40.0f0 * (CorePotts.global_keeps(st.ownership, ctx, prop, Val(false), Val(nothing), Val(0), CorePotts.GlobalSearch()) != Int32(0))

# ROCm, last: no `double` in any kernel this suite compiled (full scan of the kernel cache,
# D-157); the scan lives with the monorepo's shared test helpers
const DEVICE_IR_SCAN = joinpath(@__DIR__, "..", "..", "..", "test", "shared", "device_ir_scan.jl")

# Compile before enqueue: the staged lifecycle's compile set (`_CompileOnly`,
# `Exec.compile!` with `n = 0`) compiles exactly the kernels the launches then run, on host
# tasks, and writes nothing. Counted in the backend's kernel-instance cache.
@inline cp_compile_write!(i, a, v) = (@inbounds a[i] = v; nothing)      # i ≤ length(a)
include("shared/export_all.jl")
end

@testitem "device (PottsDevices.device_name()): surface, moments, and statistical parity" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    @testset "device ($(PottsDevices.device_name())): surface, moments, and statistical parity" begin
    backend = PottsDevices.device_backend()
    σ, kinds = blocks((64, 64), 6)
    σ = circshift(σ, (3, 3))
    lat = Lattice((64, 64))
    sspec = Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
    cell = merge(init_moments(σ, lat, length(kinds)),
        (; surface = recompute_surface(σ, lat, relation(sspec, lat), length(kinds); T = Float32)))
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
            commit_surface!(st.cell.surface, prop, surface_change(st.ownership, ctx, prop; T = Float32));
        commit_moments!(st.cell, ctx, prop))
    function delta_H(st, p, prop, ctx)
        J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
        E(v, c) = p.λ * (v - p.V0)^2
        S(s, c) = p.λs * (s - p.S0)^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                surface_delta(st.cell.surface, prop, surface_change(st.ownership, ctx, prop; T = Float32), S)
    end
    f = CPMFunction(delta_H; commit!, temperature = gg_temperature)
    p = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
        λs = 0.2f0, S0 = 22.0f0)
    prob = PottsProblem(f, initial_state(σ, kinds; cell), lat, (0, 50), p;
        relations = (; surface = sspec))
    sol = solve(prob, CheckerboardCPM(); backend)
    @test sol.retcode == ReturnCode.Success
    u = sol.u[end]
        @test u.ownership != σ
        @test u.cell.volume == [count(==(c), u.ownership) for c in eachindex(kinds)]
        @test u.cell.surface ≈ recompute_surface(u.ownership, lat, relation(sspec, lat), length(kinds); T = Float64) rtol = 1.0e-4
        ref = init_moments(u.ownership, lat, length(kinds))
    for c in eachindex(kinds)
        @test all(isapprox.(centroid(u.cell, lat, c), centroid(merge(ref, (; volume = u.cell.volume)), lat, c); atol = 1e-9))
    end

    # statistical parity of an observable, CPU vs device checkerboard
    function energy_proxy(u)          # mean |volume − V0|, a fast-relaxing observable
        sum(abs.(u.cell.volume .- 36)) / length(u.cell.volume)
    end
        n_ep = max(24, required_n(sqrt(2) * 0.4, 0.6; alpha = 1.0e-3, power = 0.9))
        xs = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:n_ep]
        ys = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 101:(100 + n_ep)]
        res = stat_accept(xs, ys; margin = 0.6, alpha = 1.0e-3)
        @info "CPU vs device" cpu = mean(xs) device = mean(ys) z = res.statistic pvalue = res.pvalue
        @test res.pass
        @test !stat_accept(xs, ys .+ 1.2; margin = 0.6, alpha = 1.0e-3).pass
    end
end

@testitem "device: phases on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "phases on the device" begin
        σp, kp = blocks((32, 32), 4)
        latp = Lattice((32, 32))
        u0 = Float32[sin(2π * i / 32) + cos(2π * j / 16) for i in 1:32, j in 1:32]
        st = initial_state(
            σp, kp; site = (; u = copy(u0), u_next = zero(u0)),
            history = (; u = history_buffer(u0, 2))
        )
        ph = Phases(
            after_mcs = (
                SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next)),
                HistoryPush(:u => (:site, :u)),
            )
        )
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pp = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 16.0f0, T = 10.0f0, D = 0.05f0)
        prob = PottsProblem(f, st, latp, (0, 5), pp)
        g = solve(prob, CheckerboardCPM(); backend).u[end]
        c = solve(prob, CheckerboardCPM()).u[end]
        @test g.site.u ≈ c.site.u rtol = 1.0e-5
        @test g.history.u ≈ c.history.u rtol = 1.0e-5
    end

end

@testitem "device: frozen sites and cell reductions on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "frozen sites and cell reductions on the device" begin
        σz, kz = blocks((32, 32), 5; gap = 0)
        latz = Lattice((32, 32))
        frozen = falses(32, 32); frozen[:, 1:2] .= true
        v = Float32[i + j for i in 1:32, j in 1:32]
        n = length(kz)
        sc = CorePotts.reduce_scratch(n)
        st = initial_state(
            σz, kz; site = (; v), cell = (; vsum = zeros(Float32, n), vmax = zeros(Float32, n), sc.cell...),
            model = sc.model
        )
        ph = Phases(
            after_mcs = (
                CellReduce((:cell, :vsum), (st, p, ctx, key, mcs, i) -> st.site.v[i]),
                CellReduce((:cell, :vmax), (st, p, ctx, key, mcs, i) -> st.site.v[i]; op = max),
            )
        )
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pz = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 20.0f0)
        u = solve(PottsProblem(f, st, latz, (0, 10), pz; frozen), CheckerboardCPM(); backend).u[end]
        @test u.ownership[frozen] == σz[frozen]
        for c in 1:n
            owned = findall(==(c), u.ownership)
            isempty(owned) && continue
            @test u.cell.vsum[c] ≈ sum(v[owned]) rtol = 1.0e-5
            @test u.cell.vmax[c] == maximum(v[owned])
        end
    end

end

@testitem "device: division on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "division on the device" begin
        latd = Lattice((48, 48))
        σd = zeros(Int32, 48, 48); σd[20:27, 20:27] .= 1
        grow!(st, p, ctx, key, mcs, c) = (@inbounds st.cell.target[c] += 1.0f0; nothing)
        big(st, p, ctx, key, mcs, c) = st.cell.volume[c] >= 80 ? EVENT_DIVIDE : EVENT_NONE
        reset!(st, p, ctx, key, mcs, parent, daughter) =
            (st.cell.target[parent] = 40.0f0; st.cell.target[daughter] = 40.0f0; nothing)
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - @inbounds(st.cell.target[c]))^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
        end
        commitD!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
        st = with_capacity(initial_state(σd, [1]; cell = merge(init_moments(σd, latd, 1), (; target = Float32[64]))), 64)
        f = CPMFunction(
            dH; commit! = commitD!, temperature = gg_temperature,
            phases = Phases(before_mcs = (CellPhase(grow!),)),
            lifecycle = Lifecycle(big; divide! = reset!, normal = AlongMinorAxis{Float32}())
        )
        pd = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, T = 10.0f0)
        sol = solve(PottsProblem(f, st, latd, (0, 120), pd), CheckerboardCPM(); backend)
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions >= 3
        @test u.cell.volume == [count(==(c), u.ownership) for c in 1:64]
        ref = init_moments(u.ownership, latd, 64)
        for c in findall(>(0), u.cell.volume)
            @test all(isapprox.(centroid(u.cell, latd, c), centroid(merge(ref, (; volume = u.cell.volume)), latd, c); atol = 1.0e-9))
        end
    end

end

@testitem "device: Act, chemotaxis, connectivity and bias on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "Act, chemotaxis, connectivity and bias on the device" begin
        latA = Lattice((64, 64))
        σA, kA = blocks((64, 64), 6; gap = 2)
        nA = length(kA)
        grad = Float32[i / 64 for i in 1:64, j in 1:64]
        function dHA(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            m(site, owner) = neighborhood_mean(st.site.act, st.ownership, ctx, site, owner; relation = ctx.act)
            act = -(p.λact / p.maxact) * (m(prop.source, prop.new) - m(prop.target, prop.old))
            chem = is_extension(prop) ? chemotaxis_delta(st.site.c, prop, p.χ) : 0.0f0
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) + act + chem
        end
        commitA!(st, p, prop, ctx) = (
            commit_volume!(st, p, prop, ctx);
            @inbounds st.site.act[prop.target] = prop.new == 0 ? 0.0f0 : p.maxact; nothing
        )
        decay!(st, p, ctx, key, mcs, i) = (@inbounds st.site.act[i] = max(st.site.act[i] - 1.0f0, 0.0f0); nothing)
        okA(st, p, prop, ctx) = locally_connected(st.ownership, ctx, prop) && forbid_extinction(st.cell.volume, prop)
        biasA(st, p, prop, ctx) = is_extension(prop) ? 0.05f0 : 0.0f0
        fA = CPMFunction(
            dHA; commit! = commitA!, temperature = gg_temperature, constraint = okA,
            bias = biasA, phases = Phases(after_mcs = (SitePhase(decay!),))
        )
        pA = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
            λact = 30.0f0, maxact = 20.0f0, χ = 200.0f0,
        )
        stA = initial_state(σA, kA; site = (; act = zeros(Float32, 64, 64), c = grad))
        probA = PottsProblem(fA, stA, latA, (0, 60), pA; contact = Moore(1), relations = (; act = Moore(1)))
        uA = solve(probA, CheckerboardCPM(); backend).u[end]
        @test uA.cell.volume == [count(==(c), uA.ownership) for c in 1:nA]
        @test all(c -> components(uA.ownership, latA, c) == 1, 1:nA)
        @test all(>(0), uA.cell.volume)
        @test any(>(0), uA.site.act)
        # chemotaxis moves mass up the gradient; CPU and the device agree on how far
        drift(u) = sum(i -> u.ownership[i] != 0 ? grad[i] : 0.0f0, eachindex(u.ownership)) / count(!=(0), u.ownership)
        d0 = drift(stA)
        n_act = max(16, required_n(sqrt(2) * 0.02, 0.03; alpha = 1.0e-3, power = 0.9))
        xs = [drift(solve(remake(probA; seed), CheckerboardCPM(); save_start = false).u[end]) - d0 for seed in 1:n_act]
        ys = [drift(solve(remake(probA; seed), CheckerboardCPM(); backend, save_start = false).u[end]) - d0 for seed in 101:(100 + n_act)]
        @test mean(xs) > 0 && mean(ys) > 0
        res = stat_accept(xs, ys; margin = 0.03, alpha = 1.0e-3)
        @info "Act/chemotaxis drift CPU vs device" cpu = mean(xs) device = mean(ys) z = res.statistic pvalue = res.pvalue
        @test res.pass
        @test !stat_accept(xs, ys .+ 0.06; margin = 0.03, alpha = 1.0e-3).pass
    end

end

@testitem "device: ring connectivity rule and Barker on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "ring connectivity rule and Barker on the device" begin
        σM, kM = blocks((48, 48), 5; gap = 1)
        latM = Lattice((48, 48))
        okM(st, p, prop, ctx) = ring_arcs(st.ownership, ctx, prop) <= 1 ||
            (ring_cells(st.ownership, ctx, prop) == 2 && ring_medium(st.ownership, ctx, prop) == 0)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = okM)
        pM = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 12.0f0)
        prob = PottsProblem(f, initial_state(σM, kM), latM, (0, 40), pM; contact = Moore(1))
        u = solve(prob, CheckerboardCPM(acceptance = Barker()); backend).u[end]
        @test u.cell.volume == [count(==(c), u.ownership) for c in eachindex(kM)]
        @test u.ownership != σM
        n_bk = max(16, required_n(sqrt(2) * 1.2, 2.0; alpha = 1.0e-3, power = 0.9))
        xs = [mean(solve(remake(prob; seed), CheckerboardCPM(acceptance = Barker()); save_start = false).u[end].cell.volume) for seed in 1:n_bk]
        ys = [mean(solve(remake(prob; seed), CheckerboardCPM(acceptance = Barker()); backend, save_start = false).u[end].cell.volume) for seed in 101:(100 + n_bk)]
        @test stat_accept(xs, ys; margin = 2.0, alpha = 1.0e-3).pass
        @test !stat_accept(xs, ys .+ 4.0; margin = 2.0, alpha = 1.0e-3).pass
    end

end

@testitem "device: 3D second-order neighbourhood with surface on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "3D second-order neighbourhood with surface on the device" begin
        lat3 = Lattice((24, 24, 24))
        σ3, k3 = blocks((24, 24, 24), 5; gap = 1)
        n3 = length(k3)
        sspec = NeighborOrder(2)
        cell = merge(
            init_moments(σ3, lat3, n3),
            (; surface = recompute_surface(σ3, lat3, relation(sspec, lat3), n3; T = Float32))
        )
        commit3!(st, p, prop, ctx) = (
            commit_volume!(st, p, prop, ctx);
            commit_surface!(st.cell.surface, prop, surface_change(st.ownership, ctx, prop; T = Float32));
            commit_moments!(st.cell, ctx, prop)
        )
        function dH3(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(s, c) = p.λs * (s - p.S0)^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                surface_delta(st.cell.surface, prop, surface_change(st.ownership, ctx, prop; T = Float32), S)
        end
        f = CPMFunction(dH3; commit! = commit3!, temperature = gg_temperature)
        p3 = (;
            J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 125.0f0, T = 10.0f0,
            λs = 0.01f0, S0 = 200.0f0,
        )
        prob = PottsProblem(
            f, initial_state(σ3, k3; cell), lat3, (0, 15), p3;
            contact = NeighborOrder(2), relations = (; surface = sspec)
        )
        u = solve(prob, CheckerboardCPM(); backend).u[end]
        @test u.ownership != σ3
        @test u.cell.volume == [count(==(c), u.ownership) for c in 1:n3]
        @test u.cell.surface ≈ recompute_surface(u.ownership, lat3, relation(sspec, lat3), n3; T = Float64) rtol = 1.0e-4
        ref = merge(init_moments(u.ownership, lat3, n3), (; volume = u.cell.volume))
        @test all(c -> all(isapprox.(centroid(u.cell, lat3, c), centroid(ref, lat3, c); atol = 1.0e-9)), 1:n3)
    end

end

@testitem "device: links, host rules and the contact table on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "links, host rules and the contact table on the device" begin
        latL = Lattice((60, 30))
        σL = zeros(Int32, 60, 30); σL[5:10, 12:17] .= 1; σL[40:45, 12:17] .= 2
        cellL = merge(init_moments(σL, latL, 2), empty_links(1, 2; rest = Float32))
        add_link!(cellL, 1, 2; rest = 12.0f0)
        function dHL(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                link_delta(Float32, st.cell, ctx, prop, S)
        end
        commitL!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
        f = CPMFunction(dHL; commit! = commitL!, temperature = gg_temperature)
        pL = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0, k = 2.0f0)
        ds = map(1:20) do seed
            u = solve(
                PottsProblem(f, initial_state(σL, [1, 1]; cell = cellL), latL, (0, 1000), pL; seed),
                CheckerboardCPM(); backend
            ).u[end]
            centroid_distance(Float64, u.cell, latL, 1, 2)
        end
        @test stat_accept(ds; mu0 = 12.0, margin = 3.0, alpha = 1.0e-3).pass
        @test !stat_accept(ds; mu0 = 20.0, margin = 3.0, alpha = 1.0e-3).pass

        σ, kinds = blocks((30, 30), 5; gap = 0)
        lat = Lattice((30, 30))
        n = length(kinds)
        vn = relation(VonNeumann(1), lat)
        function link_touching!(cell, st, p, ctx, mcs)
            g = contact_graph(st.ownership, ctx.lattice, vn, length(cell.kind))
            for a in eachindex(cell.kind), b in contact_neighbors(g, a)
                a < b && add_link!(cell, a, b; age = Int32(mcs))
            end
        end
        st = initial_state(σ, kinds; cell = merge(empty_links(8, n; age = Int32), empty_contacts(8, n)))
        fH = CPMFunction(
            gg_delta_H; temperature = gg_temperature,
            phases = Phases(after_mcs = (HostPhase(link_touching!; every = 100), ContactPhase()))
        )
        pH = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 10.0f0)
        u = solve(PottsProblem(fH, st, lat, (0, 3), pH; contact = VonNeumann(1)), CheckerboardCPM(); backend).u[end]
        g0 = contact_graph(σ, lat, vn, n)
        @test all(a -> all(b -> linked(u.cell, a, b), contact_neighbors(g0, a)), 1:n)
        g = contact_graph(u.ownership, lat, vn, n)
        @test all(iszero, u.cell.contact_overflow)
        for a in 1:n
            @test sort(filter(!=(0), u.cell.contact_nbr[:, a])) == collect(contact_neighbors(g, a))
            @test all(b -> contact_measure(u.cell, a, b) == contact_measure(g, a, b), contact_neighbors(g, a))
        end
    end

end

@testitem "device: link_delta skips a dead partner on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "link_delta skips a dead partner on the device" begin
        # the spring of the previous testset, plus cell 3: linked to cell 1 but owning no
        # site (copy-killed, volume 0, centroid 0/0). The kernel skips it: ΔH stays finite.
        latD = Lattice((60, 30))
        σD = zeros(Int32, 60, 30); σD[5:10, 12:17] .= 1; σD[40:45, 12:17] .= 2
        cellD = merge(init_moments(σD, latD, 3), empty_links(2, 3; rest = Float32))
        add_link!(cellD, 1, 2; rest = 12.0f0); add_link!(cellD, 1, 3; rest = 3.0f0)
        function dHD(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                link_delta(Float32, st.cell, ctx, prop, S)
        end
        commitD!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
        f = CPMFunction(dHD; commit! = commitD!, temperature = gg_temperature)
        pD = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0, k = 2.0f0)
        st0 = initial_state(σD, [1, 1, 1]; cell = cellD)
        @test st0.cell.volume[3] == 0
        ds = map(1:4) do seed
            sol = solve(PottsProblem(f, st0, latD, (0, 1000), pD; seed), CheckerboardCPM(); backend)
            @test sol.retcode == ReturnCode.Success                 # a NaN ΔH would fail the run
            u = sol.u[end]
            @test u.ownership != σD && u.cell.volume[3] == 0
            @test linked(u.cell, 1, 3)                              # no boundary here: the skip suffices
            centroid_distance(Float64, u.cell, latD, 1, 2)
        end
        @test abs(mean(ds) - 12.0) < 2.5                            # the live spring still acts
    end

end

@testitem "device: a killing copy removes the dying cell's links on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "a killing copy removes the dying cell's links on the device" begin
        # cell 2 owns one site, 22.5 from blob 1's centroid, on a spring of rest 3 and
        # stiffness 1 (≈ 380 stretched). Dying costs it +λd = 50 (E = λd·v(v − 2)), growing
        # +50, and medium contacts with it are free: at T = 1 only the killing copy, whose
        # ΔH drops the spring (≈ 50 − 380), is ever accepted (D-083).
        latK = Lattice((60, 30))
        σK = zeros(Int32, 60, 30); σK[4:9, 12:17] .= 1; σK[29, 15] = 2
        function dHK(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = @inbounds(st.cell.kind[c]) == 2 ? p.λd * v * (v - 2) : p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                link_delta(Float32, st.cell, ctx, prop, S)
        end
        commitK!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
        f = CPMFunction(dHK; commit! = commitK!, temperature = gg_temperature)
        pK = (;
            J = SMatrix{3, 3, Float32}(0, 16, 0, 16, 2, 16, 0, 16, 2), λ = 1.0f0, V0 = 36.0f0, λd = 50.0f0,
            T = 1.0f0, k = 1.0f0,
        )
        st(linkit) = (
            cell = merge(init_moments(σK, latK, 2), empty_links(1, 2; rest = Float32));
            linkit && add_link!(cell, 1, 2; rest = 3.0f0); initial_state(σK, [1, 2]; cell)
        )
        p0 = PottsProblem(f, st(true), latK, (0, 20), pK)
        li = LinearIndices(σK)
        props = [Proposal(li[29, 15 + j], li[29, 15], (29, 15 + j), 1, Int32(0), Int32(2)) for j in (-1, 1)]
        kill = Proposal(li[29, 15], li[30, 15], (29, 15), 1, Int32(2), Int32(0))
        ctxK = (; lattice = latK, contact = p0.contact)
        @test dHK(p0.u0, pK, kill, ctxK) < -40                       # the spring leaves with the cell
        @test all(q -> dHK(p0.u0, pK, q, ctxK) > 30, props)          # growth never pays
        for seed in 1:3
            sol = solve(remake(p0; seed), CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 1)
            @test sol.retcode == ReturnCode.Success
            @test sol.u[1].cell.volume[2] == 1 && sol.u[end].cell.volume[2] == 0
            @test all(u -> u.cell.volume[1] > 0, sol.u)
        end
        # negative control: unlinked, the cell is never killed
        free = PottsProblem(f, st(false), latK, (0, 20), pK; seed = 1)
        @test all(u -> u.cell.volume[2] == 1, solve(free, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 1).u)
    end

end

@testitem "device: checkpoint continuation on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "checkpoint continuation on the device" begin
        σc, kc = blocks((48, 48), 6)
        latc = Lattice((48, 48))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, fingerprint = 0x07)
        pc = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0)
        prob = PottsProblem(f, initial_state(σc, kc), latc, (0, 20), pc; seed = 3)
        # the device run is not reproducible (lockless): a checkpoint restores the state
        # it saved, and the continued run keeps its trackers
        integ = init(prob, CheckerboardCPM(); backend)
        for _ in 1:8
            step!(integ)
        end
        ck = checkpoint(integ)
        u8 = current_state(integ)
        cont = init(prob, CheckerboardCPM(); backend, checkpoint = ck)
        @test Array(current_state(cont).ownership) == Array(u8.ownership) && cont.t == integ.t
        rest = solve!(cont).u[end]
        @test rest.cell.volume == [count(==(c), rest.ownership) for c in eachindex(kc)]
    end

end

@testitem "device: transfer counters: exact counts of the helpers on the device" setup = [CP_gpu] tags = [:corepotts, :gpu, :device, :gpu_only] begin
    backend = PottsDevices.device_backend()
    @testset "transfer counters: exact counts of the helpers on the device" begin
        stats = CorePotts.PottsStats()
        counts() = (stats.syncs, stats.transfers, stats.transfer_bytes)
        d = PottsDevices.device_array(Float32[1, 2, 3, 4]); d2 = PottsDevices.device_array(zeros(Float32, 4))
        CorePotts.sync!(stats, backend)
        @test counts() == (1, 0, 0)
        @test CorePotts.to_host(stats, d) == Float32[1, 2, 3, 4]
        @test counts() == (1, 1, 16)
        CorePotts.counted_copy!(stats, d2, Float32[5, 6, 7, 8])                     # host → device
        @test counts() == (1, 2, 32)
        h = zeros(Float32, 4)
        CorePotts.counted_copy!(stats, h, d2)                                       # device → host
        @test h == Float32[5, 6, 7, 8] && counts() == (1, 3, 48)
        CorePotts.counted_copy!(stats, d, d2)                                       # device → device: not a transfer
        @test counts() == (1, 3, 48)
        @test CorePotts._readback(stats, PottsDevices.device_array(Int32[7])) == 7
        @test counts() == (1, 4, 52)
        # a snapshot: one transfer per device leaf
        st = CorePotts._to_backend(backend, initial_state(Int32[1 0; 0 2], Int32[1, 1]))
        before = counts()
        snap = CorePotts.snapshot(stats, backend, st)
        leaves = (st.ownership, values(st.cell)...)
        @test snap.ownership isa Array && snap.ownership == Array(st.ownership)
        @test counts() .- before == (0, length(leaves), sum(sizeof, leaves))
        # a lattice domain mask on the device: one transfer
        ml = CorePotts._to_backend(backend, Lattice((4, 4); domain = trues(4, 4)))
        before = counts()
        @test CorePotts.host_lattice(stats, ml).mask isa Array
        @test counts() .- before == (0, 1, 16)
        CorePotts.to_host(nothing, d)                                       # nothing counts into `nothing`
        @test counts() .- before == (0, 1, 16)
end

end

