# P6.15m m3 (D-220, D-223 item 2, D-226): the ΔH brute-force check of CheckerboardCPM, kept in
# citable form in the record. The D-220 investigation's script (P6.15m-loss `check.jl`) with
# two changes: the run uses this record's growth rate α = A₀/cycle (cycle from the main runner's
# <out>/calibration.toml, the P1b calibration, D-224), and the result is written as TOML.
#
# Mid-run in case (a) (1400², σ_X = 0.4, β = γ = 0), CPU, one thread: the plain-loop path of
# `checkerboard_mcs!`, which is the same colour loop the GPU kernels run (the record's chain
# replays reproduce the GPU runs exactly). Once the colony reaches TARGET live cells:
#   1. for NCHECK MCS, every committed copy's kernel ΔH against a brute-force ΔH (area term from
#      a σ recount at the colour start plus this colour's commits, adhesion from the Moore(1)
#      neighbours), the volume tracker against a σ recount at every colour start, and the claim
#      rule (no committed copy touches a cell an earlier copy of the colour touched);
#   2. for NTHIN MCS, accepted against committed copies (the thinning rate), and the sequential
#      accepted copies from the same state.
#
#     P615M_OUT=<dir> taskset -c 4 julia -t 1 --project=lib/PottsModels/test …/check_dH.jl check 1400 5000 3 20 <seed>
#     P615M_OUT=<dir> julia --project=lib/PottsModels/test …/check_dH.jl merge     # meta.toml [dH_check]
#     julia …/check_dH.jl stamp     # meta.toml [dH_check] runner_sha256 (D-227) without re-merging
# `runner_sha256` is the sha256 of this script as it stood at the check's commit (`git show`), so
# it identifies the version that ran even after later edits to this file.
using TOML, Dates, SHA
const OUT = get(ENV, "P615M_OUT", joinpath(@__DIR__, "parts"))
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
stamp!(d) = (d["runner_sha256"] = bytes2hex(sha256(read(Cmd(`git show $(d["commit"]):$(d["runner"])`; dir = ROOT)))); d)
if ARGS[1] in ("merge", "stamp")
    p = joinpath(@__DIR__, "meta.toml")
    meta = TOML.parsefile(p)
    d = ARGS[1] == "merge" ? TOML.parsefile(joinpath(OUT, "dH_check.toml")) : meta["dH_check"]
    meta["dH_check"] = stamp!(d)
    open(io -> TOML.print(io, meta), p, "w")
    println("meta.toml [dH_check]: ", d["copies"], " copies, ", d["mismatches"], " mismatches")
    exit(0)
end
ARGS[1] == "check" || error("check_dH.jl: check <L> <target> <ncheck> <nthin> <seed> | merge | stamp")
const CYCLE = TOML.parsefile(joinpath(OUT, "calibration.toml"))["cycle_mcs"]
const COMMIT, DIRTY = git("rev-parse", "HEAD"), !isempty(git("status", "--porcelain", "--untracked-files=no"))
using Potts, PottsModels, Printf, Statistics
using Potts: CorePotts
using .CorePotts: Proposal, color_site, linear_index, draw, bounded, shift, is_mobile, STREAM_PROPOSAL,
    _effective_dH, accept, uniform, STATUS_NONFINITE, _claim!, _won, has_reads, _unwritten

const L, TARGET, NCHECK, NTHIN, SEED = parse.(Int, ARGS[2:6])
@assert Threads.nthreads() == 1

const ON = Ref(false)          # brute-force check on
const COUNT = Ref(false)       # thinning counts on
const REC = zeros(Float64, 1_000_000)   # kernel ΔH per colour index
const ACC = Ref(0); const COM = Ref(0); const PROPOSED = Ref(0)
const LOSSHIST = Dict{Symbol, Int}()   # which claim a lost copy failed
const NCHK = Ref(0); const MAXERR = Ref(0.0); const NBAD = Ref(0); const NKILL = Ref(0)
const TRACKBAD = Ref(0); const TRACKCHK = Ref(0); const CLAIMBAD = Ref(0)
const SAMPLEDIFF = Float64[]
const VBF = Ref{Vector{Int}}(Int[])    # brute-force volumes (σ recount at colour start + this colour's commits)
const TOUCHED = Ref{Set{Int32}}(Set{Int32}())
const PROB = Ref{Any}(nothing)
const λ = 2.0
Jc(a, b) = a == b ? 0.0 : (a == 0 || b == 0) ? 10.0 : 20.0      # J[medium,cell] = 10, J[cell,cell] = 20

function recount(σ, n)
    v = zeros(Int, n)
    @inbounds for s in σ
        s > 0 && (v[s] += 1)
    end
    return v
end

@eval CorePotts @inline function propose_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key,
        mcs, color, idbits, tk = nothing)
    if j == 1 && $ON[]                       # colour start: tracker vs recount
        vb = $recount(st.σ, length(st.cell.volume))
        $TRACKCHK[] += 1
        $TRACKBAD[] += count(vb .!= st.cell.volume)
        $VBF[] = vb
        empty!($TOUCHED[])
    end
    lat = ctx.lattice
    x = color_site(color, j)
    t = linear_index(lat, x)
    rd, ra, rp, _ = draw(key, mcs, t, STREAM_PROPOSAL)
    dir = bounded(rd, length(ctx.proposal)) + 1
    inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
    won = UInt32(0)
    s = 0
    if inside && is_mobile(ctx.mobility, t) && is_mobile(ctx.mobility, linear_index(lat, y))
        s = linear_index(lat, y)
        a = @inbounds st.σ[t]
        b = @inbounds st.σ[s]
        if a != b
            $COUNT[] && ($PROPOSED[] += 1)
            prop = Proposal(t, s, x, dir, a, b)
            if f.constraint(st, p, prop, ctx)
                dH0 = f.delta_H(st, p, prop, ctx)
                temperature = f.temperature(st, p, prop, ctx)
                T = typeof(temperature)
                dH = _effective_dH(f, dH0, temperature, st, p, prop, ctx)
                if !isfinite(dH)
                    @inbounds Atomix.@atomic status[1] |= STATUS_NONFINITE
                elseif accept(law, T(dH), temperature, uniform(T, ra))
                    won = ((rp >> idbits) << idbits) | (j % UInt32)
                    $REC[j] = Float64(dH0)
                    $COUNT[] && ($ACC[] += 1)
                    _claim!(claim, a, won)
                    _claim!(claim, b, won)
                    writes = f.claims(st, p, prop, ctx)
                    for c in writes
                        _claim!(claim, Int32(c), won)
                    end
                    if has_reads(f)
                        _claim!(wclaim, a, won)
                        _claim!(wclaim, b, won)
                        for c in writes
                            _claim!(wclaim, Int32(c), won)
                        end
                        for c in f.reads(st, p, prop, ctx)
                            _claim!(claim, Int32(c), won)
                        end
                    end
                end
            end
        end
    end
    @inbounds prio[j] = won
    @inbounds source[j] = s
end

function bruteforce(st, t, s, a, b, lat)
    va, vb = VBF[][max(a, 1)], VBF[][max(b, 1)]
    A = st.cell.A_star
    dH = 0.0
    a > 0 && (dH += λ * ((va - 1 - A[a])^2 - (va - A[a])^2))
    b > 0 && (dH += λ * ((vb + 1 - A[b])^2 - (vb - A[b])^2))
    x = CorePotts.coordinates(lat, t)
    for dx in -1:1, dy in -1:1
        (dx == 0 && dy == 0) && continue
        y = (x[1] + dx, x[2] + dy)
        (1 <= y[1] <= L && 1 <= y[2] <= L) || continue
        n = st.σ[linear_index(lat, y)]
        dH += Jc(b, n) - Jc(a, n)
    end
    return dH
end

@eval CorePotts @inline function commit_body!(j, st, claim, next_claim, wclaim, next_wclaim, prio, source, f, p,
        ctx, color, nclear, nthreads, tk = nothing)
    c = j
    while c <= nclear
        @inbounds next_claim[c] = UInt32(0)
        has_reads(f) && (@inbounds next_wclaim[c] = UInt32(0))
        c += nthreads
    end
    won = @inbounds prio[j]
    if won != 0
        lat = ctx.lattice
        x = color_site(color, j)
        t = linear_index(lat, x)
        s = @inbounds source[j]
        a = @inbounds st.σ[t]
        b = @inbounds st.σ[s]
        prop = Proposal(t, s, x, 0, a, b)
        oka = _won(claim, a, won); okb = _won(claim, b, won)
        ok = oka && okb
        for extra in f.claims(st, p, prop, ctx)
            ok &= _won(claim, Int32(extra), won)
        end
        if has_reads(f)
            for r in f.reads(st, p, prop, ctx)
                ok &= _unwritten(wclaim, Int32(r), won)
            end
        end
        if $COUNT[]
            k = ok ? :committed : (!oka && !okb) ? :lost_both : !oka ? :lost_old : :lost_new
            $LOSSHIST[k] = get($LOSSHIST, k, 0) + 1
            ok && ($COM[] += 1)
        end
        if ok
            if $ON[]
                # claims: no earlier commit of this colour touched a or b
                ((a > 0 && a in $TOUCHED[]) || (b > 0 && b in $TOUCHED[])) && ($CLAIMBAD[] += 1)
                bf = $bruteforce(st, t, s, a, b, lat)
                err = abs(bf - $REC[j])
                $NCHK[] += 1
                $MAXERR[] = max($MAXERR[], err)
                err > 1e-6 && ($NBAD[] += 1)
                a > 0 && $VBF[][a] == 1 && ($NKILL[] += 1)
                # sampled full-H oracle (Potts.total_energy) on a few copies
                if $NCHK[] % 20000 == 1
                    H0 = $Potts.total_energy($PROB[], st)
                    @inbounds st.σ[t] = b
                    f.commit!(st, p, prop, ctx)
                    H1 = $Potts.total_energy($PROB[], st)
                    push!($SAMPLEDIFF, (H1 - H0) - $REC[j])
                else
                    @inbounds st.σ[t] = b
                    f.commit!(st, p, prop, ctx)
                end
                a > 0 && ($VBF[][a] -= 1)
                b > 0 && ($VBF[][b] += 1)
                a > 0 && push!($TOUCHED[], a); b > 0 && push!($TOUCHED[], b)
            else
                @inbounds st.σ[t] = b
                f.commit!(st, p, prop, ctx)
            end
        end
    end
end

sys = OpenVTReferenceMonolayer(; name = Symbol(:ovt, L), lattice = (L, L))
prob0 = remake(PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 40_000);
    capacity = 13_100, seed = SEED); p = [:β => 0.0, :γ => 0.0, :σ_X => 0.4, :α => 50 / CYCLE])
cb = CheckerboardCPM(; proposal = Moore(1))
integ = init(prob0, cb; save_start = false)
PROB[] = integ.prob
println("state fields: ", propertynames(integ.state.cell)); flush(stdout)
nlive() = count(>(0), integ.state.cell.volume)
t0 = time()
while nlive() < TARGET
    for _ in 1:100
        step!(integ)
    end
end
println(@sprintf("reached %d live at MCS %d (%.0f s)", nlive(), integ.t, time() - t0)); flush(stdout)

# 1. brute force on every committed copy for NCHECK MCS
ON[] = true
for _ in 1:NCHECK
    step!(integ)
end
ON[] = false
println(@sprintf("BRUTE FORCE: %d MCS, %d committed copies checked, max |ΔH_kernel - ΔH_bf| = %.3g, mismatches %d, killing copies %d",
    NCHECK, NCHK[], MAXERR[], NBAD[], NKILL[]))
println(@sprintf("  sampled full-H oracle (total_energy): %d copies, max |(H1-H0) - ΔH_kernel| = %.3g (killing copies differ by λA*²)",
    length(SAMPLEDIFF), isempty(SAMPLEDIFF) ? NaN : maximum(abs, SAMPLEDIFF)))
println(@sprintf("  volume tracker vs σ recount at %d colour starts: %d mismatching cells; claim violations (a/b touched earlier in colour): %d",
    TRACKCHK[], TRACKBAD[], CLAIMBAD[])); flush(stdout)

# 2. thinning over NTHIN MCS from here (checkerboard)
snap = deepcopy(integ.u)
COUNT[] = true
for _ in 1:NTHIN
    step!(integ)
end
COUNT[] = false
println(@sprintf("THINNING (checkerboard, %d MCS from MCS %d): non-null proposals/MCS %.0f, accepted/MCS %.0f, committed/MCS %.0f, committed/accepted %.3f",
    NTHIN, integ.t - NTHIN, PROPOSED[] / NTHIN, ACC[] / NTHIN, COM[] / NTHIN, COM[] / ACC[]))
println("  loss breakdown: ", LOSSHIST)
# 3. sequential from the same state
sprob = remake(integ.prob; u0 = snap, tspan = (integ.t - NTHIN, integ.t), seed = SEED)
sint = init(sprob, SequentialCPM(; proposal = Moore(1)); save_start = false)
for _ in 1:NTHIN
    step!(sint)
end
println(@sprintf("SEQUENTIAL from the same state: accepted/MCS %.0f; ratio checkerboard committed / sequential accepted = %.3f",
    sint.stats.accepted / NTHIN, (COM[] / NTHIN) / (sint.stats.accepted / NTHIN)))

# the record's form
open(joinpath(OUT, "dH_check.toml"), "w") do io
    TOML.print(io, Dict("copies" => NCHK[], "mismatches" => NBAD[], "max_abs_error" => MAXERR[], "killing_copies" => NKILL[],
        "tracker_checks" => TRACKCHK[], "tracker_mismatching_cells" => TRACKBAD[], "claim_violations" => CLAIMBAD[],
        "sampled_full_H" => length(SAMPLEDIFF), "check_mcs" => NCHECK, "case" => "a", "lattice" => L, "seed" => SEED,
        "live_at_start" => TARGET, "cycle_mcs" => CYCLE, "alpha_text" => "50/$CYCLE",
        "thinning_mcs" => NTHIN, "accepted_per_mcs" => ACC[] / NTHIN, "committed_per_mcs" => COM[] / NTHIN,
        "commit_fraction" => COM[] / ACC[], "sequential_accepted_per_mcs" => sint.stats.accepted / NTHIN,
        "algorithm" => "CheckerboardCPM(; proposal = Moore(1)), CPU one thread (the plain-loop colour path)",
        "runner" => relpath(@__FILE__, ROOT), "commit" => COMMIT, "dirty_tracked" => DIRTY,
        "source" => "re-run at this record's calibration (D-226); D-220's investigation found 16605 copies, 0 mismatches at α = 50/775"))
end
println("dH_check.toml written")
