# Checkpoint/continuation and reinit! (ROADMAP M2.10): continuation is exact.

@testsetup module CP_checkpoint
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
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
        return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
               (is_extension(prop) ? chemotaxis_delta(st.site.c, prop, 3.0) : 0.0)
    end
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
    # a hand-written double-buffered field (zero flux): a site phase into `c_next`, then a publish
    function lap(c, lat, i)
        x, acc = CorePotts.coordinates(lat, i), 0.0
        for d in 1:2, s in (-1, 1)
            inside, y = CorePotts.shift(lat, x, ntuple(k -> Int32(k == d ? s : 0), 2))
            acc += (inside ? c[CorePotts.linear_index(lat, y)] : c[i]) - c[i]
        end
        return acc
    end
    diffuse!(st, p, ctx, key, mcs, i) = (@inbounds st.site.c_next[i] = st.site.c[i] + 0.1 * lap(st.site.c, ctx.lattice, i) +
                                                                      0.05 * (owner_kind(st, i) == 1) - 0.01 * st.site.c[i]; nothing)
    noise!(st, p, ctx, key, mcs, i) = (@inbounds st.site.n[i] = CorePotts.uniform(Float64,
        CorePotts.draw(key, mcs, i, CorePotts.stream_id("test.noise"))[1]); nothing)
    st = with_capacity(initial_state(σ, [1, 2]; cell = merge(init_moments(σ, lat, 2), (; target = [64.0, 36.0])),
        site = (; c = zeros(40, 40), c_next = zeros(40, 40), n = zeros(40, 40))), 32)
    f = CPMFunction(dH; commit!, temperature = gg_temperature, fingerprint = 0xabc,
        phases = Phases(before_mcs = (CellPhase(grow!),), after_mcs = (
            SitePhase(diffuse!), CopyPhase((:site, :c) => (:site, :c_next)), SitePhase(noise!))),
        lifecycle = Lifecycle(big; divide! = reset!))
    return PottsProblem(f, st, lat, (0, 30), gg_params(); seed = 5)
end
include("shared/export_all.jl")
end

@testitem "checkpoint and continuation are exact (nameof(typeof(alg)))" setup = [CP_checkpoint] tags = [:corepotts, :checkpoint] begin
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
        rest = solve!(init(prob, alg; checkpoint = ck, save_everystep = false))
    a, b = whole.u[end], rest.u[end]
    @test whole.stats.lifecycle.divisions >= 1
    @test a.ownership == b.ownership
    @test a.cell == b.cell
    @test a.site == b.site
    @test whole.stats.attempts == rest.stats.attempts
    @test whole.stats.lifecycle.divisions == rest.stats.lifecycle.divisions
    @test rest.t == [12, 30]
    bad = remake(prob; f = CPMFunction(prob.f.delta_H; temperature = gg_temperature))
        @test_throws ["ArgumentError", "checkpoint fingerprint", "does not match"] init(bad, alg; checkpoint = ck)

    # reinit! reuses the integrator and reproduces the run
    integ = init(prob, alg)
    solve!(integ)
    reinit!(integ)
    @test integ.t == 0 && integ.retcode == SciMLBase.ReturnCode.Default
    @test solve!(integ).u[end].ownership == a.ownership
end
end

@testitem "checkpoint format: a pre-cutover checkpoint is refused by name" setup = [CP_checkpoint] tags = [:corepotts, :checkpoint] begin
@testset "checkpoint format: a pre-cutover checkpoint is refused by name" begin
    prob = everything_problem()
    integ = init(prob, SequentialCPM())
    step!(integ)
    ck = checkpoint(integ)
    @test ck.format == CorePotts.CHECKPOINT_FORMAT == 2
    @test init(prob, SequentialCPM(); checkpoint = ck).t == 1                         # control: current format
    old = PottsCheckpoint(ck.state, ck.t, ck.seed, ck.replica, ck.repeat, ck.p, ck.fingerprint, ck.stats, 1)
    err = try
        init(prob, SequentialCPM(); checkpoint = old); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("format 1", err.msg) && occursin("cutover", err.msg)
    # a file that does not deserialize to a checkpoint of this format: a named error
    path = tempname()
    write(path, "not a checkpoint")
    err = try
        load_checkpoint(path); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("format $(CorePotts.CHECKPOINT_FORMAT)", err.msg)
    @test_throws SystemError load_checkpoint(tempname())                              # a missing file is not a format error
end
end
