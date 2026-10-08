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
    (; key = "mac", cpu = r"^Apple M1 Pro", bench = Int[], work = "", memmax = ""),
    (; key = "nucbox", cpu = r"RYZEN AI MAX\+ 395"i,
        bench = [12, 13, 14, 15], work = "0-11,16-27",
        memmax = "8G")
]

cpu_model() = strip(Sys.cpu_info()[1].model)

slug(s) = strip(replace(lowercase(s), r"[^a-z0-9]+" => "-"), '-')

"""
The machine entry for this host (`POTTS_MACHINE` names one explicitly).
"""
function machine()
    k = strip(get(ENV, "POTTS_MACHINE", ""))
    for m in MACHINES
        (isempty(k) ? occursin(m.cpu, cpu_model()) : m.key == k) && return m
    end
    key = isempty(k) ? slug(cpu_model()) : k
    return (; key, cpu = r"", bench = Int[], work = "", memmax = "")
end

pins(m) = Sys.islinux() && !isempty(m.bench) && Sys.which("taskset") !== nothing

"""
Parse a Linux CPU list such as `0-11,16-27`.
"""
function cpulist(s)
    out = Int[]
    for part in split(strip(s), ','; keepempty = false)
        a, b = occursin('-', part) ? split(part, '-') : (part, part)
        append!(out, parse(Int, a):parse(Int, b))
    end
    return out
end

"""
The logical CPUs this process may run on (Linux), or `nothing`.
"""
function allowed_cpus()
    Sys.islinux() || return nothing
    for l in eachline("/proc/self/status")
        startswith(l, "Cpus_allowed_list:") && return cpulist(split(l, ':')[2])
    end
    return nothing
end

"""
The SMT siblings of logical CPU `c` (without `c`).
"""
function siblings(c)
    f = "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list"
    isfile(f) || return Int[]
    return filter(!=(c), cpulist(read(f, String)))
end

"""
The benchmark CPU to pin to: `POTTS_BENCH_CPU`, else the first reserved one.
"""
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
cap, no `systemd-run`, or no user service manager to talk to (`user_scope_works`): a CI job
runs under the runner's system service, which has no user bus, and there
`systemd-run --user` fails ("Failed to connect to bus"), which made every timed child of a
CI run fail (CI run 37721528049).
"""
function mem_cmd(m; works = user_scope_works)
    cap = strip(get(ENV, "POTTS_BENCH_MEMMAX", m.memmax))
    (isempty(cap) || cap == "0" || !Sys.islinux() ||
     Sys.which("systemd-run") === nothing) && return ``
    works() || return ``
    return `systemd-run --user --scope -q -p MemoryMax=$cap`
end

const USER_SCOPE = Ref{Union{Nothing, Bool}}(nothing)

"""
Can this process start a transient user scope (`systemd-run --user --scope true`)? Probed
once per process and cached; when it cannot, a warning says that children run without
the memory cap.
"""
function user_scope_works()
    USER_SCOPE[] === nothing || return USER_SCOPE[]
    ok = try
        success(pipeline(`systemd-run --user --scope -q true`; stdout = devnull,
            stderr = devnull))
    catch
        false
    end
    ok || @warn "systemd-run --user is unavailable here (no user service manager, e.g. " *
                "inside a CI job): timed children run without the memory cap"
    USER_SCOPE[] = ok
    return ok
end

"""
The prefix that pins a timed child process (empty where the machine does not pin).
"""
pin_cmd(m, c) = pins(m) ? `taskset -c $c` : ``

"""
The prefix for untimed work (precompilation) on this machine (empty where it does not pin).
"""
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

"""
Busy fraction of each logical CPU in `cpus` over `dt` seconds (Linux; else empty).
"""
function cpu_busy(cpus; dt = 0.5)
    Sys.islinux() || return Dict{Int, Float64}()
    a = _jiffies()
    sleep(dt)
    b = _jiffies()
    return Dict(c => (t = b[c][1] - a[c][1]; t == 0 ? 0.0 : 1 - (b[c][2] - a[c][2]) / t)
    for c in cpus if haskey(a, c))
end

"""
Is a GitHub Actions job running on this host (a `Runner.Worker` process)?
"""
function ci_job_running(; exclude = ancestors())
    Sys.islinux() || return false
    for p in readdir("/proc")
        all(isdigit, p) || continue
        parse(Int, p) in exclude && continue        # inside a CI job: not a disturbance
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
The PIDs of this process and all its ancestors (Linux; else empty).
"""
function ancestors(pid = getpid())
    out = Int[]
    Sys.islinux() || return out
    while pid > 1
        push!(out, pid)
        st = try
            read("/proc/$pid/stat", String)
        catch
            break
        end
        # fields after the parenthesised command name: state, ppid, …
        pid = parse(Int, split(st[(findlast(')', st) + 2):end])[2])
    end
    return out
end

"""
PIDs of processes holding the AMD GPU (ROCm KFD clients), other than `exclude`: this
process and its parent (a gate that re-ran itself pinned holds the GPU in the parent).
"""
function gpu_users(; exclude = (getpid(), Int(ccall(:getppid, Cint, ()))))
    d = "/sys/class/kfd/kfd/proc"
    isdir(d) || return Int[]
    return [parse(Int, p)
            for p in readdir(d) if all(isdigit, p) && !(parse(Int, p) in exclude)]
end

"""
Wait until no CI job runs on this host (`ci`) and, with `gpu`, no other process holds the
GPU, polling every `poll` s until `deadline` (a `time()` value). Returns `true` when the
machine is idle, `false` when the deadline passed while it was still busy (the caller then
times anyway and counts the run as disturbed). D-157: benchmarks on the NucBox run with the
runner idle; a CI job's GPU group made a ROCm Graner–Glazier MCS read 2500 instead of
47 ns/site (2026-10-07). Off Linux it returns at once.
"""
function wait_idle(; gpu = false, ci = true, poll = 30, deadline = time() + 4 * 3600)
    Sys.islinux() || return true
    said = ""
    while true
        why = busy_reasons(; gpu, ci)
        isempty(why) && return true
        msg = join(why, " and ")
        msg == said || (println("WAIT ", msg); flush(stdout); said = msg)
        time() > deadline && return false
        sleep(poll)
    end
end

"""
Why the machine is not idle for a timed run: a CI job (`ci`), other GPU clients (`gpu`).
"""
function busy_reasons(; gpu = false, ci = true)
    why = String[]
    ci && ci_job_running() && push!(why, "a CI job (Runner.Worker) is running")
    gpu && (u = gpu_users(); isempty(u) || push!(why, "other GPU clients $(u)"))
    return why
end

"""
What disturbs a timed run on logical CPU `c` right now: `busy_reasons`, plus a busy SMT
sibling of `c` (over 5 %) or a busy other reserved CPU (over 50 %; a benchmark there shares
the L3 and the power budget). Empty when nothing does.
"""
function disturbances(c, reserved; gpu = false, ci = true, dt = 0.5,
        busy = cpus -> cpu_busy(cpus; dt), siblings = siblings,
        linux = Sys.islinux(), reasons = () -> busy_reasons(; gpu, ci))
    why = reasons()
    linux && c >= 0 || return why
    sib = siblings(c)
    others = setdiff(reserved, [c; sib])
    others = unique([others; reduce(vcat, siblings.(others); init = Int[])])
    b = busy(unique([sib; others]))
    for (k, v) in sort(collect(b))
        k in sib && v > 0.05 &&
            push!(why, @sprintf("SMT sibling cpu%d %.0f%% busy", k, 100v))
        k in others && v > 0.5 &&
            push!(why, @sprintf("reserved cpu%d %.0f%% busy", k, 100v))
    end
    return why
end

"""
On a pinning machine, move this process (all its threads) to the CPUs for untimed work
(`m.work`), so the `ab.jl` parent and the lock's keeper, which inherit it, never run on the
reserved cores. Timed children are pinned explicitly.
"""
function pin_self_to_work!(m)
    pins(m) && !isempty(m.work) || return false
    p = run(pipeline(ignorestatus(`taskset -a -cp $(m.work) $(getpid())`); stdout = devnull))
    return success(p)
end

"""
On a pinning machine, re-run this script pinned to its benchmark CPU unless it already is
(or `POTTS_NO_PIN=1`). Returns the child's exit code, or `nothing` to go on in this process.
"""
function pin_or_reexec(m, args)
    pins(m) || return nothing
    get(ENV, "POTTS_NO_PIN", "") == "1" &&
        (@warn "POTTS_NO_PIN=1: timing unpinned"; return nothing)
    c = bench_cpu(m)
    allowed_cpus() == [c] && return nothing
    get(ENV, "POTTS_BENCH_PINNED", "") == "1" &&
        (@warn "POTTS_BENCH_PINNED=1 but this process may run on $(allowed_cpus())";
            return nothing)
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
# A/B time against a table of the same size and load. In bare Julia 1.12 (no packages) the
# table holds ~53k entries in 65536 slots and grows fourfold at about 60k (measured
# 2026-10-07 on the Mac); with Potts, PottsModels and BenchmarkTools loaded on the NucBox it
# holds 222k (CPU) to 243k (AMDGPU) entries in 262144 slots, close to its next fourfold
# growth. Where a session stands relative to a growth decides its probe
# lengths; 500k entries is past it (1048576 slots, ~48 % full) on every side, and far
# from the one after.

"""
`(entries, capacity)` of the global Tuple type cache.
"""
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

"""
The default number of Tuple-cache entries a timed process is seeded to.
"""
const SEED_ENTRIES = 500_000

"""
Fill the Tuple type cache with dummy types until it holds at least `entries` entries.
"""
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
