# Frames written to disk during a run (`FrameWritingCallback`, `FrameFile`) and read back
# lazily (`PottsFrames`): read-back equals the in-memory saves, also when the writer is
# slower than the run, writer failures surface, the frames survive a failure, an interrupt
# and (up to the last checkpoint) a killed process, a custom writer works, and the reader
# indexes by frame and by MCS. Each property has a negative control.

@testsetup module CP_frames
using Test, CorePotts, StaticArrays, Random, JLD2
using SciMLBase: SciMLBase, ReturnCode
include("shared/gg_model.jl")
# PottsDevices: the device of the GPU group (test/shared/devices.jl)
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "devices.jl"))

# a Graner–Glazier run with a site and a model array that the frames must carry too
function frames_problem(; seed = 3, tf = 40)
    σ, kinds = blocks((40, 40), 6)
    st = initial_state(
        σ, kinds; site = (; c = rand(MersenneTwister(1), Float32, 40, 40)),
        model = (; m = [2.5])
    )
    return PottsProblem(
        GG, st, Lattice((40, 40)), (0, tf), gg_params(); contact = Moore(1), seed
    )
end

leaves(u::CPMState) = (
    u.ownership, values(u.cell)..., values(u.site)..., values(u.model)...,
    values(u.history)...,
)
# two states hold the same arrays under the same names
function same_state(a::CPMState, b::CPMState)
    return keys(a.cell) == keys(b.cell) && keys(a.site) == keys(b.site) &&
        keys(a.model) == keys(b.model) && all(map(isequal, leaves(a), leaves(b)))
end
function same_states(fr, sol)
    return fr.t == sol.t && all(same_state(fr[i], sol[i]) for i in eachindex(sol.t))
end

# a writer that fails once, at the frame of MCS `fail_at`, else writes to a new FrameFile
# at `path` for each run
mutable struct FailingWriter <: AbstractFrameWriter
    path::String
    fail_at::Int
    file::Union{Nothing, FrameFile}
end
FailingWriter(path, fail_at) = FailingWriter(path, fail_at, nothing)
function CorePotts.open_frames!(w::FailingWriter, u)
    w.file = FrameFile(w.path)
    return open_frames!(w.file, u)
end
function CorePotts.write_frame!(w::FailingWriter, t, u)
    t == w.fail_at && (w.fail_at = -1; error("disk full at MCS $t"))
    return write_frame!(w.file, t, u)
end
Base.close(w::FailingWriter) = close(w.file)

# a writer slower than the run (`delay` s per frame) that keeps a copy of each frame, or,
# with `copy = false`, the buffer itself; it fails at the frame of MCS `fail_at`
mutable struct SlowFrames <: AbstractFrameWriter
    delay::Float64
    copy::Bool
    fail_at::Int
    t::Vector{Int}
    u::Vector{Any}
end
SlowFrames(; delay = 0.02, copy = true, fail_at = -1) =
    SlowFrames(delay, copy, fail_at, Int[], Any[])
CorePotts.open_frames!(w::SlowFrames, u) = (empty!(w.t); empty!(w.u); nothing)
function CorePotts.write_frame!(w::SlowFrames, t, u)
    sleep(w.delay)
    t == w.fail_at && error("slow writer failed at MCS $t")
    push!(w.t, t)
    push!(w.u, w.copy ? deepcopy(u) : u)
    return nothing
end
CorePotts.frame_times(w::SlowFrames) = w.t
CorePotts.read_frame(w::SlowFrames, i) = w.u[i]

# a callback that copies the frame directory `dir` to `copy` at MCS `at`, once the writer
# task has had time to write the frames sent so far (a snapshot of a run that is killed)
function snapshot_at(at, dir, copy)
    function affect!(integ)
        sleep(0.5)
        cp(dir, copy; force = true)
        return nothing
    end
    return DiscreteCallback((u, t, i) -> t == at, affect!; save_positions = (false, false))
end

# an in-memory writer and reader
mutable struct MemoryFrames <: AbstractFrameWriter
    t::Vector{Int}
    u::Vector{Any}
    opened::Int
    closed::Int
end
MemoryFrames() = MemoryFrames(Int[], Any[], 0, 0)
CorePotts.open_frames!(w::MemoryFrames, u) = (empty!(w.t); empty!(w.u); w.opened += 1)
function CorePotts.write_frame!(w::MemoryFrames, t, u)
    push!(w.t, t)
    push!(w.u, deepcopy(u))
    return nothing
end
Base.close(w::MemoryFrames) = (w.closed += 1; nothing)
CorePotts.frame_times(w::MemoryFrames) = w.t
CorePotts.read_frame(w::MemoryFrames, i) = w.u[i]

struct NoMethodsWriter <: AbstractFrameWriter end

include("shared/export_all.jl")
end

@testitem "frames: read-back equals the in-memory saves" setup = [CP_frames] tags = [
    :corepotts,
] begin
    prob = frames_problem()
    mktempdir() do dir
        path = joinpath(dir, "run.jld2")
        cb = FrameWritingCallback(FrameFile(path); saveat = 10)
        sol = solve(prob, SequentialCPM(); saveat = 10, callback = cb)
        @test sol.t == [0, 10, 20, 30, 40]
        frames = PottsFrames(path)
        @test same_states(frames, sol)
        @test frames[1].site.c == prob.u0.site.c
        close(frames)
        # every MCS (the callback's default, as `solve`'s)
        cb = FrameWritingCallback(FrameFile(path))
        sol = solve(prob, SequentialCPM(); callback = cb)
        frames = PottsFrames(path)
        @test frames.t == collect(0:40)
        @test same_states(frames, sol)
        close(frames)
        # a few leaves only
        cb = FrameWritingCallback(FrameFile(path); saveat = 20, save_idxs = [:ownership])
        sol = solve(
            prob, SequentialCPM(); saveat = 20, save_idxs = [:ownership], callback = cb
        )
        frames = PottsFrames(path)
        @test same_states(frames, sol)
        @test isempty(frames[end].cell)
        close(frames)
        # negative control: another seed's frames differ from these saves
        cb = FrameWritingCallback(FrameFile(path); saveat = 20, save_idxs = [:ownership])
        solve(
            remake(prob; seed = 4), SequentialCPM(); save_everystep = false, callback = cb
        )
        frames = PottsFrames(path)
        @test frames.t == sol.t
        @test !same_states(frames, sol)
        close(frames)
    end
end

@testitem "frames: the callback leaves the solution's saving as it was" setup = [
    CP_frames,
] tags = [:corepotts] begin
    prob = frames_problem(; tf = 12)
    mktempdir() do dir
        cb = FrameWritingCallback(FrameFile(joinpath(dir, "a.jld2")); saveat = 4)
        # the default saves every MCS (SciML's `save_everystep = isempty(saveat)`)
        @test solve(prob, SequentialCPM(); callback = cb).t == collect(0:12)
        cb = FrameWritingCallback(FrameFile(joinpath(dir, "b.jld2")); saveat = 4)
        sol = solve(prob, SequentialCPM(); save_everystep = false, callback = cb)
        @test sol.t == [0, 12]
        # negative control: a callback that fires at the same MCS and saves (the default
        # `save_positions`) adds saves, which the check above would see
        saving = DiscreteCallback((u, t, i) -> t % 4 == 0, i -> nothing)
        @test count(
            ==(4), solve(
                prob, SequentialCPM(); save_everystep = false, callback = saving
            ).t
        ) == 2
    end
end

@testitem "frames: a writer failure surfaces and the file stays valid" setup = [
    CP_frames,
] tags = [:corepotts] begin
    prob = frames_problem()
    mktempdir() do dir
        path = joinpath(dir, "run.jld2")
        cb = FrameWritingCallback(FailingWriter(path, 20); saveat = 10)
        err = try
            solve(prob, SequentialCPM(); save_everystep = false, callback = cb)
            nothing
        catch e
            e
        end
        @test err isa FrameWriteError
        @test occursin("disk full at MCS 20", sprint(showerror, err))
        # the frames before the failure, in a closed file
        frames = PottsFrames(path)
        @test frames.t == [0, 10]
        @test frames[2].ownership isa Matrix{Int32}
        close(frames)
        # the same callback writes the next run (its writer fails only once)
        @test solve(prob, SequentialCPM(); save_everystep = false, callback = cb).retcode ==
            ReturnCode.Success
        frames = PottsFrames(path)
        @test frames.t == [0, 10, 20, 30, 40]
        close(frames)
        # negative control: a writer that fails at an MCS without a frame raises nothing
        cb = FrameWritingCallback(FailingWriter(path, 25); saveat = 10)
        @test solve(prob, SequentialCPM(); save_everystep = false, callback = cb).retcode ==
            ReturnCode.Success
    end
end

@testitem "frames: the file is valid after a failed or interrupted run" setup = [
    CP_frames,
] tags = [:corepotts] begin
    prob = frames_problem()
    mktempdir() do dir
        path = joinpath(dir, "run.jld2")
        for (ex, T) in (
                (InterruptException(), InterruptException), (
                    ErrorException("x"),
                    ErrorException,
                ),
            )
            boom = DiscreteCallback((u, t, i) -> t == 25, i -> throw(ex))
            cb = FrameWritingCallback(FrameFile(path); saveat = 10)
            @test_throws T solve(
                prob, SequentialCPM(); save_everystep = false,
                callback = CallbackSet(cb, boom)
            )
            frames = PottsFrames(path)
            @test frames.t == [0, 10, 20]
            close(frames)
        end
        # negative control: the files of a writer that is not closed hold no frames
        w = FrameFile(path)
        open_frames!(w, prob.u0)
        write_frame!(w, 0, prob.u0)
        @test_throws ArgumentError PottsFrames(w)       # (this writer is still writing)
        copy = joinpath(dir, "copy")
        cp(path, copy)
        frames = @test_logs (:warn, r"last segment") PottsFrames(copy)
        @test isempty(frames.t)
        close(w)
        frames = PottsFrames(w)
        @test frames.t == [0]
        close(frames)
    end
end

@testitem "frames: a killed run keeps the frames up to its last checkpoint" setup = [
    CP_frames,
] tags = [:corepotts] begin
    prob = frames_problem(; tf = 12)
    mktempdir() do dir
        path = joinpath(dir, "run")
        early, late = joinpath(dir, "early"), joinpath(dir, "late")
        # every MCS, a segment closed every 3 frames; byte copies of the open run's files
        # at MCS 1 (frames 0 and 1, no segment closed) and at MCS 7 (frames 0–7: 2 segments
        # closed, frames 6 and 7 in the open one), as a killed process would leave them
        cb = FrameWritingCallback(FrameFile(path; checkpoint = 3))
        sol = solve(
            prob, SequentialCPM();
            callback = CallbackSet(
                cb, snapshot_at(1, path, early), snapshot_at(7, path, late)
            )
        )
        frames = @test_logs (:warn, r"last segment") PottsFrames(late)
        @test frames.t == 0:5
        @test all(same_state(frames[i], sol[i]) for i in 1:6)
        close(frames)
        # the finished run holds every frame, in 5 segments
        frames = PottsFrames(path)
        @test same_states(frames, sol)
        @test count(endswith(".jld2"), readdir(path)) == 5
        close(frames)
        # negative control: before the first checkpoint, no frame survives
        frames = @test_logs (:warn, r"last segment") PottsFrames(early)
        @test isempty(frames.t)
        @test_throws ArgumentError FrameFile(path; checkpoint = 0)
    end
end

@testitem "frames: a writer slower than the run" setup = [CP_frames] tags = [
    :corepotts,
] begin
    prob = frames_problem(; tf = 20)
    # both buffers are busy at every MCS, and the run waits for the writer: the frames still
    # equal the saves, so no buffer is reused before its frame is written
    w = SlowFrames()
    sol = solve(prob, SequentialCPM(); callback = FrameWritingCallback(w))
    @test same_states(PottsFrames(w), sol)
    # a slow writer that fails while the run waits for a buffer: the failure surfaces
    w = SlowFrames(; fail_at = 5)
    @test_throws FrameWriteError solve(
        prob, SequentialCPM(); save_everystep = false, callback = FrameWritingCallback(w)
    )
    @test w.t == 0:4
    # negative control: a writer that keeps the buffer instead of a copy sees it reused
    w = SlowFrames(; copy = false)
    solve(prob, SequentialCPM(); save_everystep = false, callback = FrameWritingCallback(w))
    @test w.t == 0:20
    @test !same_states(PottsFrames(w), sol)
end

@testitem "frames: a custom writer and reader" setup = [CP_frames] tags = [:corepotts] begin
    prob = frames_problem()
    w = MemoryFrames()
    cb = FrameWritingCallback(w; saveat = [5, 15], save_start = false)
    sol = solve(prob, SequentialCPM(); saveat = [5, 15], save_start = false, callback = cb)
    @test (w.opened, w.closed) == (1, 1)
    @test w.t == [5, 15, 40]
    frames = PottsFrames(w)
    @test same_states(frames, sol)
    # `init`/`reinit!` start a new set of frames
    integ = init(prob, SequentialCPM(); save_everystep = false, callback = cb)
    step!(integ, 10)
    reinit!(integ)
    solve!(integ)
    @test (w.opened, w.closed) == (3, 3)
    @test w.t == [5, 15, 40]
    # one run at a time: a second integrator is refused while the first writes
    integ = init(prob, SequentialCPM(); save_everystep = false, callback = cb)
    @test_throws ArgumentError init(prob, SequentialCPM(); callback = cb)
    # a hand-driven run stops early with `terminate!` and `solve!`, which close the writer
    step!(integ, 20)
    terminate!(integ)
    solve!(integ)
    @test (w.opened, w.closed) == (4, 4)
    @test w.t == [5, 15, 20]
    # a restart that skips the callbacks' start writes nothing, with a warning
    reinit!(integ; reinit_callbacks = false)
    @test_logs (:warn, r"writes no frames") step!(integ)
    @test w.t == [5, 15, 20]
    # negative control: a writer without the interface methods is refused at the start
    err = try
        solve(prob, SequentialCPM(); callback = FrameWritingCallback(NoMethodsWriter()))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("open_frames!", sprint(showerror, err))
    @test_throws ArgumentError FrameWritingCallback(w; saveat = 0)
end

@testitem "frames: a FrameFile holds one run" setup = [CP_frames] tags = [:corepotts] begin
    prob = frames_problem(; tf = 10)
    mktempdir() do dir
        path = joinpath(dir, "run")
        cb = FrameWritingCallback(FrameFile(path); saveat = 5)
        solve(prob, SequentialCPM(); save_everystep = false, callback = cb)
        # a second run into the same FrameFile would replace the first: refused
        @test_throws ArgumentError solve(
            prob, SequentialCPM(); save_everystep = false, callback = cb
        )
        frames = PottsFrames(path)
        @test frames.t == [0, 5, 10]
        close(frames)
        # so is an ensemble whose trajectories share the callback
        ens = EnsembleProblem(prob)
        cb = FrameWritingCallback(FrameFile(joinpath(dir, "ens")); saveat = 5)
        @test_throws ArgumentError solve(
            ens, SequentialCPM(), EnsembleSerial(); trajectories = 2,
            save_everystep = false, callback = cb
        )
        # negative control: a callback per trajectory (built in `prob_func`) writes each
        function per_trajectory(p, ctx)
            path = joinpath(dir, "traj$(ctx.sim_id)")
            return remake(p; callback = FrameWritingCallback(FrameFile(path); saveat = 5))
        end
        sols = solve(
            EnsembleProblem(prob; prob_func = per_trajectory), SequentialCPM(),
            EnsembleSerial(); trajectories = 2, save_everystep = false
        )
        for i in 1:2
            frames = PottsFrames(joinpath(dir, "traj$i"))
            @test frames.t == [0, 5, 10]
            @test same_state(frames[end], sols.u[i].u[end])
            close(frames)
        end
    end
end

@testitem "frames: the reader indexes by frame and by MCS" setup = [CP_frames] tags = [
    :corepotts,
] begin
    prob = frames_problem()
    mktempdir() do dir
        path = joinpath(dir, "run.jld2")
        cb = FrameWritingCallback(FrameFile(path); saveat = 10)
        sol = solve(prob, SequentialCPM(); saveat = 10, callback = cb)
        frames = PottsFrames(path)
        @test length(frames) == 5
        @test same_state(frames(30), sol(30))
        @test same_state(frames[end], sol[end])
        @test same_state(frames.u[2], sol.u[2])
        @test length(frames[2:3]) == 2
        @test same_state(frames[2:3][2], sol[3])
        @test count(_ -> true, frames) == 5
        @test collect(eachindex(frames)) == 1:5
        @test occursin("5 frames", sprint(show, MIME"text/plain"(), frames))
        # negative controls: an MCS without a frame, a fraction of an MCS, past the end
        @test_throws ArgumentError frames(15)
        @test_throws ArgumentError frames(10.5)
        @test_throws BoundsError frames[6]
        close(frames)
        # negative controls: a JLD2 file, and a directory with a JLD2 segment that holds no
        # frames
        other = joinpath(dir, "other.jld2")
        jldsave(other; x = 1)
        @test_throws ArgumentError PottsFrames(other)
        mkdir(joinpath(dir, "fake"))
        jldsave(joinpath(dir, "fake", "frames-000001.jld2"); x = 1)
        @test_throws ArgumentError PottsFrames(joinpath(dir, "fake"))
    end
end

@testitem "device: frames read back equal to the in-memory saves" setup = [
    CP_frames,
] tags = [
    :corepotts, :gpu, :device, :gpu_only,
] begin
    if !PottsDevices.on_device()
        @test_skip "device (POTTS_GPU=metal|rocm)"
    else
        backend = PottsDevices.device_backend()
        σ, kinds = blocks((96, 96), 6)
        st = initial_state(
            σ, kinds; site = (; c = rand(MersenneTwister(1), Float32, 96, 96)),
            model = (; m = Float32[2.5])
        )
        prob = PottsProblem(
            GG, st, Lattice((96, 96)), (0, 30), gg_params(Float32); contact = Moore(1),
            seed = 5
        )
        alg = CheckerboardCPM(; proposal = Moore(1))
        mktempdir() do dir
            path = joinpath(dir, "run.jld2")
            for saveat in (10, 1)
                cb = FrameWritingCallback(FrameFile(path); saveat)
                sol = solve(prob, alg; backend, saveat, callback = cb)
                frames = PottsFrames(path)
                @test length(frames) == length(sol.t)
                @test same_states(frames, sol)
                close(frames)
            end
            # a writer slower than the run (both pinned buffers busy, the device copies in
            # flight): the frames equal the saves
            w = SlowFrames()
            sol = solve(prob, alg; backend, callback = FrameWritingCallback(w))
            @test same_states(PottsFrames(w), sol)
            # negative control: a writer that keeps the buffer sees it reused
            w = SlowFrames(; copy = false)
            solve(
                prob, alg; backend, save_everystep = false,
                callback = FrameWritingCallback(w)
            )
            @test !same_states(PottsFrames(w), sol)
            # a slow writer that fails while the run waits: the failure surfaces
            w = SlowFrames(; fail_at = 5)
            @test_throws FrameWriteError solve(
                prob, alg; backend, save_everystep = false,
                callback = FrameWritingCallback(w)
            )
            # a writer failure surfaces on the device path too, and the file stays valid
            cb = FrameWritingCallback(FailingWriter(path, 20); saveat = 10)
            @test_throws FrameWriteError solve(
                prob, alg; backend, save_everystep = false, callback = cb
            )
            frames = PottsFrames(path)
            @test frames.t == [0, 10]
            close(frames)
            # negative control: another seed's frames differ
            cb = FrameWritingCallback(FrameFile(path); saveat = 10)
            sol = solve(prob, alg; backend, saveat = 10)
            solve(
                remake(prob; seed = 6), alg; backend, save_everystep = false,
                callback = cb
            )
            frames = PottsFrames(path)
            @test !same_states(frames, sol)
            close(frames)
        end
    end
end
