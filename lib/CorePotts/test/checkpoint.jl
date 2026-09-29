# Checkpoint/continuation and reinit! (ROADMAP M2.10): continuation is exact.

function everything_problem()
    lat = Lattice((40, 40))
    σ = zeros(Int32, 40, 40); σ[15:22, 15:22] .= 1; σ[5:10, 30:35] .= 2
    grow!(st, p, ctx, key, mcs, c) = (@inbounds st.cell.target[c] += 0.5; nothing)
    big(st, p, ctx, key, mcs, c) = st.cell.volume[c] >= 70 ? EVENT_DIVIDE : EVENT_NONE
    reset!(st, p, ctx, key, mcs, parent, daughter) =
        (st.cell.target[parent] = 36.0; st.cell.target[daughter] = 36.0; nothing)
    function dH(st, p, prop, ctx)
        J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
        E(v, c) = p.λ * (v - @inbounds(st.cell.target[c]))^2
        return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
               (is_extension(prop) ? chemotaxis_delta(st.site.c, prop, 3.0) : 0.0)
    end
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
    rate(st, p, ctx, key, mcs, i, c) = 0.1 * laplacian(c, ctx, i) + 0.05 * (owner_kind(st, i) == 1) - 0.01c[i]
    noise!(st, p, ctx, key, mcs, i) = (@inbounds st.site.n[i] = CorePotts.uniform(Float64,
        CorePotts.draw(key, mcs, i, CorePotts.stream_id("test.noise"))[1]); nothing)
    st = with_capacity(initial_state(σ, [1, 2]; cell = merge(init_moments(σ, lat, 2), (; target = [64.0, 36.0])),
        site = (; c = zeros(40, 40), c_next = zeros(40, 40), n = zeros(40, 40))), 32)
    f = CPMFunction(dH; commit!, temperature = gg_temperature, fingerprint = 0xabc,
        phases = Phases(before_mcs = (CellPhase(grow!),), after_mcs = (
            FieldStep((:site, :c) => (:site, :c_next), rate; substeps = 2), SitePhase(noise!))),
        lifecycle = Lifecycle(big; divide! = reset!))
    return CPMProblem(f, st, lat, (0, 30), gg_params(); seed = 5)
end

@testset "checkpoint and continuation are exact ($(nameof(typeof(alg))))" for alg in (
        SequentialCPM(), CheckerboardCPM())
    prob = everything_problem()
    whole = solve(prob, alg)
    integ = init(prob, alg)
    for _ in 1:12
        step!(integ)
    end
    path = tempname()
    save_checkpoint(path, checkpoint(integ))
    ck = load_checkpoint(path)
    @test ck.t == 12
    rest = solve!(init(prob, alg; checkpoint = ck))
    a, b = whole.u[end], rest.u[end]
    @test whole.stats.lifecycle.divisions >= 1
    @test a.σ == b.σ
    @test a.cell == b.cell
    @test a.site == b.site
    @test whole.stats.attempts == rest.stats.attempts
    @test whole.stats.lifecycle.divisions == rest.stats.lifecycle.divisions
    @test rest.t == [12, 30]
    bad = remake(prob; f = CPMFunction(prob.f.delta_H; temperature = gg_temperature))
    @test_throws ArgumentError init(bad, alg; checkpoint = ck)

    # reinit! reuses the integrator and reproduces the run
    integ = init(prob, alg)
    solve!(integ)
    reinit!(integ)
    @test integ.t == 0 && integ.retcode == SciMLBase.ReturnCode.Default
    @test solve!(integ).u[end].σ == a.σ
end
