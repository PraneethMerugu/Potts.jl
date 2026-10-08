# P6.0bw (ROADMAP Phase 6, step 0; from P6.0bb): the library's device wait. Frozen
# (AUTONOMY §7.3). Decisions: D-171 (the paired A/B decides performance; the harness's ROCm
# stream spin), D-157 (backend-neutral device testing; heavy compute on the PC), D-158
# (our own code's results bitwise), D-085 (every host wait goes through `transfers.jl`),
# D-089 (no wait on a quiet MCS), D-048 (ordinary tests, no parity harness).
#
# Measured before the freeze (2026-10-08, NucBox, ROCm, AMDGPU 2.8.0, pinned to CPU 12
# under the machine lock; Float32 checkerboard gate cases):
#  - `step!` itself waits nowhere: 0 syncs and 0 transfers per MCS (200 MCS, no save) on
#    Graner–Glazier 72², the OpenVT monolayer 100², Merks 100² and the OpenVT reference
#    100². The wait cost is all at host read points: saves, `integ.u`, checkpoints.
#  - A read point right after `step!` (`integ.u`, i.e. `current_state`; also what a
#    callback or a hand-written integrator loop reads), 600 reads per process, two
#    processes per mode. "default" is the library today: `_sync!` is
#    `KernelAbstractions.synchronize`, i.e. AMDGPU's default `synchronize` (256 spins,
#    then a HIP host callback through Julia's event loop), and every device→host
#    `copyto!` waits the same way inside AMDGPU. "spin" is a `hipStreamQuery` spin in
#    `_sync!` with the copies enqueued `async = true` and waited on by the same spin:
#        model (MCS GPU µs)        default: median / reads > 1 ms     spin: median / > 1 ms
#        OpenVT monolayer (77)     12.9 ms / 600 of 600               0.12 ms / 1–2 of 600
#        OpenVT reference (113)    12.9 ms / 462–466 of 600           0.19 ms / 1 of 600
#        Merks (276)               0.12 ms / 0 of 600                 0.12–0.13 ms / 0–1
#    One read costs ~110–170 MCS of GPU time on the two lifecycle models. (Interleaving
#    the modes in one process gave 12–31 % of default reads over 1 ms, against 0–0.2 %.)
#  - Whole solves saving every 10 MCS (500 MCS, 10 solves per mode, interleaved): the
#    medians agree within 1 % (Merks 4.5 % faster with the spin), with rare slow solves
#    on both sides; there the first wait of each save is the status read-back's copy,
#    which happened to take the fast path. The cost is real where the integrator is
#    read directly; this file pins the fast path at every read point.
#
# What is pinned.
#  (W) A backend-neutral wait helper, internal:
#        CorePotts._device_wait(backend; timeout = <default>) -> nothing
#      waits until every operation queued on `backend` has finished. On the CPU it is a
#      no-op and on Metal `KernelAbstractions.synchronize`; on ROCm it spins on the
#      stream's `hipStreamQuery` with a GC safepoint every turn and a `yield` every few
#      thousand turns, raises a clear error after `timeout` seconds, and ends with a
#      blocking stream synchronize (which then returns at once and reports a stream
#      error). Zero allocations (A) rule out AMDGPU's `HIP.isdone` and
#      `synchronize(; blocking = true)` (16 B per call, measured); raw `hipStreamQuery` and
#      `hipStreamSynchronize` calls through a callable struct allocate nothing (checked
#      against a stub before the freeze). Its spinning core is the generic, backend-free
#        CorePotts._spin_until(done, timeout) -> nothing
#      which returns once `done()` is true and throws an exception whose message names
#      the timeout (the number of seconds and the word "time") once more than `timeout`
#      seconds have passed. Every explicit library wait (`_sync!`) and every device→host
#      copy the integrator makes (`_to_host`, `_copy!`, `_readback`, `_snapshot`) waits
#      through `_device_wait`.
#  (S) Spinning keeps the process alive: another task runs while `_spin_until` spins (the
#      yield; on one thread it could not otherwise), another thread's `GC.gc()` completes
#      while it spins (the safepoint; checked when Julia runs with more than one thread).
#  (T) The timeout: a never-completing wait (`done = () -> false`) raises after at least
#      `timeout` and well before a hang; the message names the timeout.
#  (H) Hostcalls (ROCm): a kernel whose every `hostcall!` waits for the host's service task
#      to answer completes under `_device_wait` within its timeout, with the answers in
#      place. Negative control, where the service task can only run on this thread
#      (`Threads.maxthreadid() == 1`; Julia 1.12's default `-t 1,1` runs it on the other
#      thread): a spin that never yields cannot finish the same kernel, and `_device_wait`
#      then does.
#  (R) Results unchanged (D-158), on the device backend for every gate case
#      (`benchmark/gate.jl`, Float32 checkerboard) and on the CPU for Graner–Glazier: a
#      run that saves after every MCS (a wait and device→host copies every MCS), a run
#      that saves every 4 MCS and a run stepped with no wait until the end are bitwise
#      equal in every leaf at every shared time, and each saved state equals `integ.u` of
#      an independent run stepped to the same MCS. A stale read (a copy not waited for) or
#      a wait that changed work would show up here. A wait cannot change the trajectory, so
#      equality with the pre-change code follows: the trajectory is the kernels', and they
#      are not touched by this item.
#  (A) Allocations: a warm `_device_wait` allocates 0 bytes on the CPU and on ROCm, idle and
#      with work in flight; on Metal it allocates no more than `KernelAbstractions.
#      synchronize` (Metal.jl's own wait allocates ~240 B); `_spin_until` with `done`
#      already true allocates 0. (A warm `step!` stays allocation-free on the CPU: gate.jl.)
#  (P) Performance (ROCm only; skipped cleanly elsewhere): on the OpenVT monolayer, Merks
#      and OpenVT reference cases, of 300 reads `integ.u` right after a `step!`, at most
#      6 (2 %) take over 1 ms; and of 300 `step!`s that each save, at most 6 take over
#      3 ms (a guard: this path is fast today). Today 12–100 % of the reads on the two
#      lifecycle models take over 1 ms (table above); Merks is a control that passes today.
#      The ROCm paired A/B (`benchmark/ab.jl <base> <cand> all cpu,rocm`, D-171) is the
#      merge gate for "no regression" and must exit 0. Its timed expression is `step!`
#      plus the harness's own spin, and `step!` has no library wait, so the expected A/B
#      ratio is 1.00 within the controls; the speed-up is in runs that save: measured
#      whole solves with `saveat` every 10 MCS are reported with the implementation.
#
# Where this file lives. Under `lib/PottsModels/test/acceptance/` (not `benchmark/test/`):
# it pins library behaviour (a CorePotts helper, the results of the published models, the
# integrator's read points), and it must run in the PottsModels suite (CPU parts, every
# platform) and in the GPU group on Metal and ROCm (`test/gpu.jl` includes it, as it does
# the other device acceptance files). `benchmark/test/` holds the harness's own tooling
# tests (ab.jl, gate.jl, exclusive.sh), which CI runs separately and which do not load a
# device backend.
#
# Checked before the freeze against a stub of (W) (the spin above in `_device_wait`,
# `_sync!` and `_to_host` on ROCm): CPU 17 pass + 1 skip (julia -t 2), Metal 33 pass +
# 2 skips, ROCm 43 pass + 1 skip (the one-thread hostcall control; (P) 0 slow reads of
# 300 per model, at most 1 slow saving step).
#
# Today this file fails because `CorePotts._device_wait` and `CorePotts._spin_until` do not
# exist (W, S, T, H, A error); (R) holds today and pins what the change must keep; (P)
# fails on ROCm for the OpenVT monolayer and reference cases.
using Potts: CorePotts
using Test

const P60BW_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()
const P60BW_DEVICE = P60BW_ON_DEVICE ? Main.PottsDevices.device_name() : ""
const P60BW_KA = CorePotts.KernelAbstractions

# --- every leaf of a host state, in a fixed order (numbers, symbols and arrays) ----------
function p60bw_leaves!(out, x)
    if x isa AbstractArray
        push!(out, Array(x))
    elseif x isa Union{Number, Symbol, Nothing, AbstractString, Bool}
        push!(out, x)
    elseif x isa Union{NamedTuple, Tuple}
        foreach(v -> p60bw_leaves!(out, v), values(x))
    elseif isstructtype(typeof(x)) && fieldcount(typeof(x)) > 0
        foreach(n -> p60bw_leaves!(out, getfield(x, n)), fieldnames(typeof(x)))
    else
        push!(out, x)
    end
    return out
end
p60bw_leaves(u) = p60bw_leaves!(Any[], u)
p60bw_same(a, b) = (la = p60bw_leaves(a); lb = p60bw_leaves(b);
    length(la) == length(lb) && all(isequal(x, y) for (x, y) in zip(la, lb)))

# --- the gate cases (benchmark/gate.jl `cases`, D-171), as functions of T and tspan -------
function p60bw_cases(T, tspan)
    gg = graner_glazier_state()
    return [
        "graner_glazier_72" =>
            () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], tspan; T),
        "wortel_act_100" =>
            () -> (σ = zeros(Int32, 100, 100); σ[40:62, 40:62] .= 1;
                PottsProblem(WortelAct(; name = :w, lattice = (100, 100)), [ownership => σ, kind => [:cell]], tspan; T)),
        "merks_100" =>
            () -> PottsProblem(MerksVasculogenesis(; name = :m, lattice = (100, 100)),
                merks_state(; lattice = (100, 100), n = 25), tspan; T,
                field_solver = ExplicitEuler(substeps = 15, lower = 0.0)),
        "openvt_monolayer_100" =>
            () -> PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (100, 100), τ = 1e6),
                openvt_monolayer_state(; lattice = (100, 100)), tspan; T, capacity = 64),
        "akeeb_99x60" =>
            () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)),
                akeeb_state(; lattice = (99, 60)), tspan; T, capacity = 1000),
        "openvt_reference_100" =>
            () -> (σ = zeros(Int32, 100, 100);
                foreach(((k, (a, b)),) -> σ[29 + 7a .+ (1:7), 29 + 7b .+ (1:7)] .= k,
                    enumerate(Iterators.product(0:5, 0:5)));
                PottsProblem(OpenVTReferenceMonolayer(; name = :r, lattice = (100, 100)),
                    [ownership => σ, kind => fill(:cell, 36), :σ_X => 0.0], tspan; T, capacity = 128)),
        "merks2006_100" =>
            () -> PottsProblem(Merks2006(; name = :m6, lattice = (100, 100)),
                layout(merks2006_layout(; lattice = (100, 100), n = 25), (100, 100)), tspan; T,
                field_solver = ExplicitEuler(substeps = 15)),
        "merks2008_202" =>
            () -> PottsProblem(Merks2008(; name = :m8),
                [layout(merks2008_sprout(), (202, 202)); :t_relax => 0.0], tspan; T,
                field_solver = ExplicitEuler(substeps = 15)),
    ]
end

# (R) for one problem on one backend (`nothing`: the CPU default)
const P60BW_N = 12
function p60bw_results_unchanged(prob, alg, backend)
    kw = backend === nothing ? (;) : (; backend)
    prob = remake(prob; tspan = (0, P60BW_N))
    every = solve(prob, alg; saveat = 1:P60BW_N, save_start = false, save_end = false, kw...)  # a wait every MCS
    fourth = solve(prob, alg; saveat = 4:4:P60BW_N, save_start = false, save_end = false, kw...)
    integ = init(prob, alg; save_start = false, save_end = false, kw...)
    for _ in 1:P60BW_N
        step!(integ)                                                         # no wait at all
    end
    uend = integ.u
    ok = Bool[]
    push!(ok, every.t == collect(1:P60BW_N), fourth.t == collect(4:4:P60BW_N))
    push!(ok, p60bw_same(every.u[end], uend), p60bw_same(fourth.u[end], uend))
    push!(ok, !p60bw_same(every.u[1], uend))                # negative control: the state moves
    for (j, t) in enumerate(fourth.t)
        push!(ok, p60bw_same(fourth.u[j], every.u[t]))
    end
    for t in (1, 7)
        ind = init(prob, alg; save_start = false, save_end = false, kw...)
        for _ in 1:t
            step!(ind)
        end
        push!(ok, p60bw_same(every.u[t], ind.u))
    end
    return ok
end

# ROCm: a kernel that makes hostcalls (AMDGPU's `HostCallHolder` / `hostcall!`, the
# mechanism behind its device printing, malloc and exceptions). Each call waits on the
# device until the host's service task has answered, so the kernel cannot finish while the
# host thread spins without yielding (on one thread). `@rocprintf` is not used: printing
# does not wait for the host, so it would not tell a yielding wait from a non-yielding one
# (measured 2026-10-08). The source is evaluated only where AMDGPU is loaded (its macros
# must resolve when the code is expanded).
if P60BW_DEVICE == "rocm"
    const P60BW_AMDGPU = Main.PottsDevices.device_package()
    include_string(@__MODULE__, """
    function p60bw_hostcall_kernel(b, hc, n)
        for i in Int32(1):n
            @inbounds b[i] = P60BW_AMDGPU.Device.hostcall!(hc, Float32(i))::Float32
        end
        return nothing
    end
    p60bw_hostcall_holder() =
        P60BW_AMDGPU.Device.HostCallHolder(Float32, Tuple{Float32}; continuous = true) do x
            x + 1.0f0
        end
    p60bw_launch_hostcalls(b, hc, n) =
        (P60BW_AMDGPU.@roc groupsize = 1 gridsize = 1 p60bw_hostcall_kernel(b, hc, Int32(n)); nothing)
    """)
end

p60bw_allocs_wait(backend) = @allocated CorePotts._device_wait(backend)
p60bw_allocs_ka(backend) = @allocated P60BW_KA.synchronize(backend)
const P60BW_TRUE = () -> true
p60bw_allocs_spin() = @allocated CorePotts._spin_until(P60BW_TRUE, 1.0)

@testset "P6.0bw: the library's device wait" begin
    @testset "(W) the helper exists, is internal, and waits on the CPU" begin
        @test isdefined(CorePotts, :_device_wait)
        @test isdefined(CorePotts, :_spin_until)
        @test !Base.ispublic(CorePotts, :_device_wait) && !Base.ispublic(CorePotts, :_spin_until)
        @test CorePotts._device_wait(P60BW_KA.CPU()) === nothing
        @test CorePotts._device_wait(P60BW_KA.CPU(); timeout = 5.0) === nothing
        @test CorePotts._spin_until(() -> true, 1.0) === nothing
    end

    @testset "(S) spinning yields to other tasks and lets GC run" begin
        flag = Threads.Atomic{Bool}(false)
        t = @async (flag[] = true)
        t0 = time()
        CorePotts._spin_until(() -> flag[], 30.0)
        @test flag[] && istaskdone(t) && time() - t0 < 30.0
        # a task that needs several turns: the spin must yield repeatedly
        n = Threads.Atomic{Int}(0)
        t2 = @async for _ in 1:5
            Threads.atomic_add!(n, 1); yield()
        end
        CorePotts._spin_until(() -> n[] >= 5, 30.0)
        @test n[] == 5
        if Threads.maxthreadid() > 1
            gcdone = Threads.Atomic{Bool}(false)
            t3 = Threads.@spawn (GC.gc(); gcdone[] = true)
            CorePotts._spin_until(() -> gcdone[], 60.0)
            @test gcdone[]
            wait(t3)
        else
            @test_skip "GC from another thread (needs a second thread)"
        end
    end

    @testset "(T) a never-completing wait times out with a clear error" begin
        t0 = time()
        err = try
            CorePotts._spin_until(() -> false, 0.25)
            nothing
        catch e
            e
        end
        dt = time() - t0
        @test err isa Exception && !(err isa InterruptException)
        @test 0.25 <= dt < 20.0
        msg = err === nothing ? "" : sprint(showerror, err)
        @test occursin("0.25", msg) && occursin(r"time"i, msg)
        # the process is usable afterwards
        @test CorePotts._spin_until(() -> true, 1.0) === nothing
    end

    @testset "(A) allocations (CPU)" begin
        b = P60BW_KA.CPU()
        p60bw_allocs_wait(b); p60bw_allocs_spin()
        @test p60bw_allocs_wait(b) == 0
        @test p60bw_allocs_spin() == 0
    end

    @testset "(R) results unchanged on the CPU (Graner–Glazier)" begin
        mk = Dict(p60bw_cases(Float64, (0, 10^6)))
        prob = mk["graner_glazier_72"]()
        for alg in (CheckerboardCPM(), SequentialCPM())
            ok = p60bw_results_unchanged(prob, alg, nothing)
            @test all(ok)
        end
    end

    if P60BW_ON_DEVICE
        backend = Main.PottsDevices.device_backend()

        @testset "(W) the helper on the device ($P60BW_DEVICE)" begin
            a = P60BW_KA.zeros(backend, Float32, 1 << 20)
            for k in 1:3
                a .+= 1f0                                   # enqueued, not waited for
                @test CorePotts._device_wait(backend) === nothing
                h = Array{Float32}(undef, length(a))
                copyto!(h, a)
                @test all(==(Float32(k)), h)
            end
            @test CorePotts._device_wait(backend; timeout = 30.0) === nothing
        end

        @testset "(A) allocations on the device ($P60BW_DEVICE)" begin
            a = P60BW_KA.zeros(backend, Float32, 1 << 20)
            a .+= 1f0; p60bw_allocs_wait(backend); p60bw_allocs_ka(backend)
            idle = p60bw_allocs_wait(backend)
            a .+= 1f0
            busy = p60bw_allocs_wait(backend)
            a .+= 1f0
            ka = p60bw_allocs_ka(backend)
            if P60BW_DEVICE == "rocm"
                @test idle == 0
                @test busy == 0
            else
                @test busy <= max(ka, 0) + 64
                @test idle <= max(ka, 0) + 64
            end
        end

        @testset "(R) results unchanged on the device, every gate case ($P60BW_DEVICE)" begin
            for (name, make) in p60bw_cases(Float32, (0, 10^6))
                ok = p60bw_results_unchanged(make(), CheckerboardCPM(), backend)
                @test all(ok)
                all(ok) || @info "P6.0bw (R) differs" name ok
            end
        end

        if P60BW_DEVICE == "rocm"
            @testset "(P) read points do not take the slow wait path (ROCm)" begin
                mk = Dict(p60bw_cases(Float32, (0, 10^6)))
                for name in ("openvt_monolayer_100", "merks_100", "openvt_reference_100")
                    prob = mk[name]()
                    integ = init(prob, CheckerboardCPM(); backend, save_start = false, save_end = false)
                    for _ in 1:5
                        step!(integ); integ.u
                    end
                    reads = Float64[]
                    for _ in 1:300
                        step!(integ)
                        t = time_ns(); integ.u; push!(reads, (time_ns() - t) / 1e9)
                    end
                    saving = init(remake(prob; tspan = (0, 400)), CheckerboardCPM(); backend,
                        saveat = 1:400, save_start = false)
                    for _ in 1:5
                        step!(saving)
                    end
                    steps = Float64[]
                    for _ in 1:300
                        t = time_ns(); step!(saving); push!(steps, (time_ns() - t) / 1e9)
                    end
                    slow_reads = count(>(1e-3), reads)
                    slow_steps = count(>(3e-3), steps)
                    @info "P6.0bw (P)" name slow_reads slow_steps median_read_us = 1e6 * sort(reads)[150] max_read_ms = 1e3 * maximum(reads)
                    @test slow_reads <= 6
                    @test slow_steps <= 6
                end
            end
            @testset "(H) a hostcall kernel completes under the wait (ROCm)" begin
                AMDGPU = P60BW_AMDGPU
                hc = p60bw_hostcall_holder()
                b = AMDGPU.ROCArray(zeros(Float32, 16))
                p60bw_launch_hostcalls(b, hc, 2)            # compile
                CorePotts._device_wait(backend; timeout = 300.0)
                fill!(b, 0.0f0)
                CorePotts._device_wait(backend)
                t0 = time()
                p60bw_launch_hostcalls(b, hc, 16)
                @test CorePotts._device_wait(backend; timeout = 60.0) === nothing
                @test time() - t0 < 60.0
                @test Array(b) == Float32.(2:17)
                # negative control (one thread: the service task runs only when this one
                # yields): a spin that never yields cannot finish the kernel; the helper then does
                if Threads.maxthreadid() == 1
                    fill!(b, 0.0f0)
                    CorePotts._device_wait(backend)
                    s = AMDGPU.stream()
                    p60bw_launch_hostcalls(b, hc, 16)
                    function p60bw_noyield(s, timeout)
                        t0 = time_ns()
                        while !AMDGPU.HIP.isdone(s)
                            ccall(:jl_cpu_pause, Cvoid, ())
                            (time_ns() - t0) > timeout * 1e9 && return false
                        end
                        return true
                    end
                    @test p60bw_noyield(s, 3.0) == false
                    @test CorePotts._device_wait(backend; timeout = 60.0) === nothing
                    @test AMDGPU.HIP.isdone(s)
                    @test Array(b) == Float32.(2:17)
                else
                    @test_skip "the non-yielding control needs one thread"
                end
                AMDGPU.Device.finish!(hc)
                AMDGPU.synchronize(; stop_hostcalls = true)
            end

        else
            @test_skip "ROCm (POTTS_GPU=rocm): hostcalls (H) and the read-point timing (P)"
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
