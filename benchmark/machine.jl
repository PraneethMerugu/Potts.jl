# The benchmark machine (D-157, P6.0bb): which machine this is, how timed processes are
# pinned on it, and the global Tuple type cache seeding of every timed process (D-145).
#
# Included by `gate.jl`, `ab.jl` and `ab_one.jl`. Uses the standard library only: `ab.jl`
# runs without a project.
#
# Machines are matched by CPU model (`Sys.cpu_info()`), or named with `POTTS_MACHINE`. An
# unknown machine gets a key derived from its CPU model and no pinning. Its rows in
# `baseline.toml` are its own: each machine reads and writes only the table of its key.
#
#   key     machine                                  benchmark CPUs   everything else
#   mac     Apple M1 Pro (the maintainer's laptop)   –                –
#   nucbox  GMKtec NucBox EVO-X2, Ryzen AI Max+ 395  12–15            0-11,16-27
#
# On the NucBox (16 cores / 32 threads; logical n and n + 16 share physical core n), a timed
# process is pinned to one logical CPU of the reserved cores 12–15, whose SMT sibling
# (n + 16) stays idle; CI jobs and FULL runs use `taskset -c 0-11,16-27` (D-157). Unpinned
# timings under load are bimodal there (Akeeb sequential 40 or 71 ns/site, depending on
# SMT sharing).
module BenchMachine

using Printf: @sprintf

const MACHINES = [
    (; key = "mac", cpu = r"^Apple M1 Pro", bench = Int[], work = "", control_bound = 0.03, memmax = ""),
    (; key = "nucbox", cpu = r"RYZEN AI MAX\+ 395"i, bench = [12, 13, 14, 15], work = "0-11,16-27",
        control_bound = 0.01, memmax = "8G"),
]

cpu_model() = strip(Sys.cpu_info()[1].model)

slug(s) = strip(replace(lowercase(s), r"[^a-z0-9]+" => "-"), '-')

"""The machine entry for this host (`POTTS_MACHINE` names one explicitly)."""
function machine()
    k = strip(get(ENV, "POTTS_MACHINE", ""))
    for m in MACHINES
        (isempty(k) ? occursin(m.cpu, cpu_model()) : m.key == k) && return m
    end
    key = isempty(k) ? slug(cpu_model()) : k
    return (; key, cpu = r"", bench = Int[], work = "", control_bound = 0.03, memmax = "")
end

pins(m) = Sys.islinux() && !isempty(m.bench) && Sys.which("taskset") !== nothing

"""Parse a Linux CPU list such as `0-11,16-27`."""
function cpulist(s)
    out = Int[]
    for part in split(strip(s), ','; keepempty = false)
        a, b = occursin('-', part) ? split(part, '-') : (part, part)
        append!(out, parse(Int, a):parse(Int, b))
    end
    return out
end

"""The logical CPUs this process may run on (Linux), or `nothing`."""
function allowed_cpus()
    Sys.islinux() || return nothing
    for l in eachline("/proc/self/status")
        startswith(l, "Cpus_allowed_list:") && return cpulist(split(l, ':')[2])
    end
    return nothing
end

"""The SMT siblings of logical CPU `c` (without `c`)."""
function siblings(c)
    f = "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list"
    isfile(f) || return Int[]
    return filter(!=(c), cpulist(read(f, String)))
end

"""The benchmark CPU to pin to: `POTTS_BENCH_CPU`, else the first reserved one."""
function bench_cpu(m)
    s = strip(get(ENV, "POTTS_BENCH_CPU", ""))
    c = isempty(s) ? first(m.bench) : parse(Int, s)
    c in m.bench || @warn "POTTS_BENCH_CPU = $c is not one of the reserved CPUs $(m.bench)"
    return c
end

"""
The prefix that caps a heavy child's memory (the NucBox is shared with CI and other agents,
and processes there have been OOM-killed): `systemd-run --user --scope -p MemoryMax=<cap>`,
the cap from `POTTS_BENCH_MEMMAX` (`0` = none), else the machine's. Empty where there is no
cap or no `systemd-run`.
"""
function mem_cmd(m)
    cap = strip(get(ENV, "POTTS_BENCH_MEMMAX", m.memmax))
    (isempty(cap) || cap == "0" || !Sys.islinux() || Sys.which("systemd-run") === nothing) && return ``
    return `systemd-run --user --scope -q -p MemoryMax=$cap`
end

"""The prefix that pins a timed child process (empty where the machine does not pin)."""
pin_cmd(m, c) = pins(m) ? `taskset -c $c` : ``

"""The prefix for untimed work (precompilation) on this machine (empty where it does not pin)."""
work_cmd(m) = pins(m) && !isempty(m.work) ? `taskset -c $(m.work)` : ``

function _jiffies()
    d = Dict{Int, Tuple{Int, Int}}()
    for l in eachline("/proc/stat")
        mm = match(r"^cpu(\d+)\s+(.*)$", l)
        mm === nothing && continue
        v = parse.(Int, split(mm[2]))
        idle = v[4] + (length(v) >= 5 ? v[5] : 0)
        d[parse(Int, mm[1])] = (sum(v), idle)
    end
    return d
end

"""Busy fraction of each logical CPU in `cpus` over `dt` seconds (Linux; else empty)."""
function cpu_busy(cpus; dt = 0.5)
    Sys.islinux() || return Dict{Int, Float64}()
    a = _jiffies(); sleep(dt); b = _jiffies()
    return Dict(c => (t = b[c][1] - a[c][1]; t == 0 ? 0.0 : 1 - (b[c][2] - a[c][2]) / t) for c in cpus if haskey(a, c))
end

"""Is a GitHub Actions job running on this host (a `Runner.Worker` process)?"""
function ci_job_running()
    Sys.islinux() || return false
    for p in readdir("/proc")
        all(isdigit, p) || continue
        f = joinpath("/proc", p, "comm")
        s = try
            strip(read(f, String))
        catch
            ""
        end
        s == "Runner.Worker" && return true
    end
    return false
end

"""
PIDs of processes holding the AMD GPU (ROCm KFD clients), other than `exclude`: this
process and its parent (a gate that re-ran itself pinned holds the GPU in the parent).
"""
function gpu_users(; exclude = (getpid(), Int(ccall(:getppid, Cint, ()))))
    d = "/sys/class/kfd/kfd/proc"
    isdir(d) || return Int[]
    return [parse(Int, p) for p in readdir(d) if all(isdigit, p) && !(parse(Int, p) in exclude)]
end

"""
Wait until no CI job runs on this host (and, with `gpu`, no other process holds the GPU),
polling every `poll` s for at most `maxwait` s (then go on with a warning). D-157:
benchmarks on the NucBox run with the runner idle; a CI job's GPU group made a ROCm
Graner–Glazier MCS read 2500 instead of 47 ns/site (2026-10-07). `POTTS_BENCH_NOWAIT=1`
skips the wait; `POTTS_BENCH_WAIT=gpu` waits only for other GPU clients (CI jobs' CPU work
is pinned off the reserved cores, so a CPU-only A/B can run beside it, flagged).
"""
function wait_idle(; gpu = false, ci = true, poll = 30, maxwait = 4 * 3600)
    Sys.islinux() || return true
    get(ENV, "POTTS_BENCH_NOWAIT", "") == "1" && return true
    ci = ci && get(ENV, "POTTS_BENCH_WAIT", "") != "gpu"
    t0 = time()
    said = ""
    while true
        why = String[]
        ci && ci_job_running() && push!(why, "a CI job (Runner.Worker)")
        gpu && (u = gpu_users(); isempty(u) || push!(why, "GPU clients $(u)"))
        isempty(why) && return true
        msg = join(why, " and ")
        msg == said || (println("   waiting: ", msg, " running"); flush(stdout); said = msg)
        time() - t0 > maxwait && (@warn "still busy after $(maxwait) s ($msg); timing anyway"; return false)
        sleep(poll)
    end
end

"""Warn when the benchmark CPU `c` or its SMT siblings are busy, or a CI job runs."""
function check_quiet(c; reserved = Int[], dt = 0.5, limit = 0.05)
    Sys.islinux() || return ""
    sib = siblings(c)
    others = setdiff(reserved, [c; sib])
    others = unique([others; reduce(vcat, siblings.(others); init = Int[])])
    busy = cpu_busy(unique([c; sib; others]); dt)
    mine = filter(p -> first(p) in [c; sib], busy)
    msg = join([@sprintf("cpu%d %.0f%%", k, 100v) for (k, v) in sort(collect(mine))], ", ")
    any(>(limit), values(mine)) && @warn "benchmark CPU or its SMT sibling is busy: $msg"
    near = sort([k for (k, v) in busy if k in others && v > 0.5])
    if !isempty(near)
        msg *= "; other reserved CPUs busy: " * join(near, ", ")
        @warn "another job runs on reserved CPUs $(near): a benchmark there shares the L3 and the power budget"
    end
    ci_job_running() && (msg *= "; CI job running";
        @warn "a CI job (Runner.Worker) is running on this machine (D-157: benchmark with the runner idle)")
    return msg
end

"""
On a pinning machine, re-run this script pinned to its benchmark CPU unless it already is
(or `POTTS_NO_PIN=1`). Returns the child's exit code, or `nothing` to go on in this process.
"""
function pin_or_reexec(m, args)
    pins(m) || return nothing
    get(ENV, "POTTS_NO_PIN", "") == "1" && (@warn "POTTS_NO_PIN=1: timing unpinned"; return nothing)
    c = bench_cpu(m)
    allowed_cpus() == [c] && return nothing
    get(ENV, "POTTS_BENCH_PINNED", "") == "1" &&
        (@warn "POTTS_BENCH_PINNED=1 but this process may run on $(allowed_cpus())"; return nothing)
    proj = Base.active_project()
    cmd = `$(mem_cmd(m)) $(pin_cmd(m, c)) $(Base.julia_cmd()) --startup-file=no --project=$(dirname(proj)) $(abspath(PROGRAM_FILE)) $args`
    println("pinning to logical CPU $c (machine $(m.key)); siblings $(siblings(c)) left idle")
    p = run(ignorestatus(setenv(cmd, merge(ENV, Dict("POTTS_BENCH_PINNED" => "1")))))
    return p.exitcode
end

# --------------------------------------------------------------------- Tuple type cache
# Steady-state speed depends on the global Tuple type cache (D-145, P6.0bc): kernel launches
# look up Tuple types, and a lookup in a nearly full hash table probes further. A session
# that happens to have created more unrelated types reads up to ~10 % different (the Metal
# OpenVT A/B read 1.07–1.115 unseeded, 0.996 seeded). Every timed process therefore first
# fills the cache with dummy types up to the same number of entries, so both sides of an
# A/B time against a table of the same size and load. With Julia 1.12 and the packages
# loaded the table holds ~55–60k entries in 65536 slots and grows fourfold at about 60k
# (measured 2026-10-07, bare Julia on the Mac); with Potts, PottsModels and BenchmarkTools
# loaded on the NucBox it holds 222k (CPU) to 243k (AMDGPU) entries in 262144 slots, close
# to its next fourfold growth. Where a session stands relative to a growth decides its probe
# lengths; 500k entries is past it (1048576 slots, ~48 % full) on every side, and far
# from the one after.

"""`(entries, capacity)` of the global Tuple type cache."""
function type_cache_stats()
    # read the field at run time: the cache vector is replaced when it grows, and a load
    # from the constant `Tuple.name` may otherwise be folded to the vector seen at compile time
    c = getfield(Base.inferencebarrier(Tuple.name), :cache)
    c isa Core.SimpleVector || return (0, 0)
    n = 0
    for i in 1:length(c)
        isassigned(c, i) && c[i] !== nothing && (n += 1)
    end
    return (n, length(c))
end

"""The default number of Tuple-cache entries a timed process is seeded to."""
const SEED_ENTRIES = 500_000

"""Fill the Tuple type cache with dummy types until it holds at least `entries` entries."""
function seed_type_cache!(entries = SEED_ENTRIES)
    i = 0
    for _ in 1:8
        n, _ = type_cache_stats()
        n >= entries && break
        for _ in 1:(entries - n)
            i += 1
            Core.apply_type(Tuple, Val{i}, Val{:potts_type_cache_seed})
        end
    end
    n, cap = type_cache_stats()
    return (; entries = n, capacity = cap, added = i)
end

end # module BenchMachine
