# The frame writer with the writer task on its own thread: a writer slower than the run
# (both buffers busy) still writes frames equal to the saves, and a slow writer that fails
# while the run waits raises `FrameWriteError`. Negative control: a writer that keeps the
# buffer sees it reused.

@testsetup module FramesThreadsSetup
using Test
using CorePotts

kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
function dH(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
const MODEL = CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T)

function threads_problem()
    σ = zeros(Int32, 40, 40)
    for (c, (i, j)) in enumerate(Iterators.product(1:7:35, 1:7:35))
        σ[i:(i + 5), j:(j + 5)] .= c
    end
    kinds = Int32[isodd(c) ? 1 : 2 for c in 1:25]
    p = (; J = [0.0 16 16; 16 2 11; 16 11 14], λ = 1.0, V0 = 40.0, T = 10.0)
    return PottsProblem(
        MODEL, initial_state(σ, kinds), Lattice((40, 40)), (0, 20), p; contact = Moore(1),
        seed = 3
    )
end

# a writer slower than the run that keeps a copy of each frame (or, with `copy = false`,
# the buffer itself) and fails at the frame of MCS `fail_at`
mutable struct SlowWriter <: AbstractFrameWriter
    copy::Bool
    fail_at::Int
    t::Vector{Int}
    u::Vector{Any}
end
SlowWriter(; copy = true, fail_at = -1) = SlowWriter(copy, fail_at, Int[], Any[])
CorePotts.open_frames!(w::SlowWriter, u) = (empty!(w.t); empty!(w.u); nothing)
function CorePotts.write_frame!(w::SlowWriter, t, u)
    sleep(0.02)
    t == w.fail_at && error("slow writer failed at MCS $t")
    push!(w.t, t)
    push!(w.u, w.copy ? deepcopy(u) : u)
    return nothing
end

same(a, b) = a.ownership == b.ownership && a.cell == b.cell
export threads_problem, SlowWriter, same
end

@testitem "frames: a slow writer on its own thread" setup = [FramesThreadsSetup] tags = [
    :multithreaded,
] begin
    Threads.nthreads() >= 4 ||
        error("This testitem requires at least 4 Julia threads \
            (got $(Threads.nthreads())); run GROUP=Multithreaded with `julia -t 4`")
    using CorePotts
    prob = threads_problem()
    sol = solve(prob, SequentialCPM())
    w = SlowWriter()
    solve(prob, SequentialCPM(); save_everystep = false, callback = FrameWritingCallback(w))
    @test w.t == sol.t
    @test all(same(w.u[i], sol.u[i]) for i in eachindex(sol.t))
    # a slow writer that fails while the run waits for a buffer
    w = SlowWriter(; fail_at = 5)
    @test_throws FrameWriteError solve(
        prob, SequentialCPM(); save_everystep = false, callback = FrameWritingCallback(w)
    )
    @test w.t == 0:4
    # negative control: a writer that keeps the buffer sees it reused
    w = SlowWriter(; copy = false)
    solve(prob, SequentialCPM(); save_everystep = false, callback = FrameWritingCallback(w))
    @test !all(same(w.u[i], sol.u[i]) for i in eachindex(sol.t))
end
