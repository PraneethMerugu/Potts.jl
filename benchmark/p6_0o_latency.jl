# P6.0o latency acceptance (D-137): `@potts_model` construction, `mtkcompile` and
# `PottsProblem` build time on the five gate models, and fresh-process time to first MCS.
#
#     tools/exclusive.sh julia --project=benchmark benchmark/p6_0o_latency.jl [reps] [warm] [base]
#
# Each repetition of each case is a fresh `julia` process (Potts and PottsModels already
# precompiled: one untimed process per checkout runs first). A child times, in order:
#   load   `using Potts, PottsModels`;
#   cold   the first construction (the constructor `@potts_model` generated), the first
#          `mtkcompile`, the first `PottsProblem` from the compiled system, and the first
#          `init` + `step!` (first MCS, `SequentialCPM`) — what a new session pays;
#   warm   the median of `warm` further constructions, `mtkcompile`s and `PottsProblem`s;
#   total  process start to exit (wall clock, measured by the parent; the child exits right
#          after its first MCS and the warm repetitions).
# The parent prints the median over `reps` of every number, per case. The D-047 case is
# Akeeb in Float32, Sequential then Checkerboard (the PottsModels compile workload's
# configuration; D-047 target: first MCS under 15 s). `benchmark/graner.jl` times the
# hand-written CorePotts Graner model and never loads Potts, so this script stands in for it.
#
# With a third argument, a base checkout (e.g. a `git worktree` of 33f681df with the
# workspace Manifest copied in), the children alternate base, this, base, this … and the
# script also prints the ratio this/base of every median. That paired form decides the
# acceptance (ROADMAP P6.0o: construction, `mtkcompile` and `PottsProblem` build time and
# the fresh-process time to first MCS each within +5 %), because absolute numbers move with
# machine load; the baseline recorded on 33f681df (D-137) is the reference for a quiet run.
#
# Baseline, 33f681df, 2026-10-04, Apple M1 Pro, Julia 1.12.6, 1 thread, under
# tools/exclusive.sh but NOT quiet (load average 6.5–8.6: two docs builds and another
# worktree's test run alive); medians of 5 fresh processes, 10 warm repetitions; seconds:
#   case                  to_first_mcs  load  construct  mtkcompile  problem  first_mcs  first_mcs_cb  warm_construct  warm_mtkcompile  warm_problem
#   graner_glazier_72          9.884   5.301     0.4009     0.05317   0.6251     0.3724        —          6.571e-05       0.0001404     0.001703
#   wortel_act_100            10.22    5.291     0.7337     0.2207    0.6338     0.5979        —          0.0002467       0.0005266     0.004107
#   merks_100                 10.40    5.289     0.6152     0.06134   0.9031     0.7414        —          0.0002096       0.0003744     0.004675
#   openvt_monolayer_100      12.49    5.289     0.6229     0.2685    1.527      2.000         —          0.0001459       0.0002858     0.002400
#   akeeb_99x60               13.62    5.299     1.026      0.2842    1.544      2.072         —          0.0002247       0.0004314     0.003168
#   akeeb_f32_first_mcs       14.69    5.328     1.025      0.2773    1.574      2.056       1.132        0.0002106       0.0004039     0.003235
# (to_first_mcs ranges over the 5 runs: 9.83–10.1, 10.1–10.7, 10.1–10.5, 12.3–12.5,
# 13.3–13.7, 14.5–14.8.)
const T0 = time()
const CHILD = get(ARGS, 1, "") == "child"
if CHILD
    using Potts, PottsModels
end
const LOAD = time() - T0
using Printf: @printf, @sprintf
median(x) = (y = sort(x); n = length(y); isodd(n) ? y[(n + 1) ÷ 2] : (y[n ÷ 2] + y[n ÷ 2 + 1]) / 2)

const CASES = ["graner_glazier_72", "wortel_act_100", "merks_100", "openvt_monolayer_100", "akeeb_99x60",
    "akeeb_f32_first_mcs"]

# the gate's cases (benchmark/gate.jl), split into constructor, operating point and keywords
function spec(case)
    if case == "graner_glazier_72"
        gg = graner_glazier_state()
        return () -> GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (;)
    elseif case == "wortel_act_100"
        σ = zeros(Int32, 100, 100)
        σ[40:62, 40:62] .= 1
        return () -> WortelAct(; name = :w, lattice = (100, 100)), [ownership => σ, kind => [:cell]], (;)
    elseif case == "merks_100"
        return () -> MerksVasculogenesis(; name = :m, lattice = (100, 100)), merks_state(; lattice = (100, 100), n = 25),
            (; field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
    elseif case == "openvt_monolayer_100"
        return () -> OpenVTGrowingMonolayer(; name = :o, lattice = (100, 100), τ = 1e6),
            openvt_monolayer_state(; lattice = (100, 100)), (; capacity = 64)
    else                                      # akeeb_99x60, akeeb_f32_first_mcs
        return () -> AkeebInvasion(; name = :a, lattice = (99, 60)), akeeb_state(; lattice = (99, 60)), (; capacity = 1000)
    end
end

function child(case, nwarm)
    T = case == "akeeb_f32_first_mcs" ? Float32 : Float64
    build, op, kw = spec(case)
    tc = @elapsed sys = build()
    tm = @elapsed c = mtkcompile(sys)
    tp = @elapsed prob = PottsProblem(c, op, (0, 10); T, kw...)
    tf = @elapsed begin
        integ = init(prob, SequentialCPM(); save_start = false)
        step!(integ)
    end
    tf2 = 0.0
    if case == "akeeb_f32_first_mcs"         # D-047: also the checkerboard's first MCS
        tf2 = @elapsed begin
            integ2 = init(prob, CheckerboardCPM(); save_start = false)
            step!(integ2)
        end
    end
    first_total = time() - T0
    wc, wm, wp = Float64[], Float64[], Float64[]
    for _ in 1:nwarm
        push!(wc, @elapsed(s = build()))
        push!(wm, @elapsed(cc = mtkcompile(s)))
        push!(wp, @elapsed(PottsProblem(cc, op, (0, 10); T, kw...)))
    end
    println("RESULT ", join(("load=$LOAD", "construct=$tc", "mtkcompile=$tm", "problem=$tp", "first_mcs=$tf",
        "first_mcs_checkerboard=$tf2", "to_first_mcs=$first_total", "warm_construct=$(median(wc))",
        "warm_mtkcompile=$(median(wm))", "warm_problem=$(median(wp))"), " "))
    return nothing
end

const KEYS = ["to_first_mcs", "total", "load", "construct", "mtkcompile", "problem", "first_mcs",
    "first_mcs_checkerboard", "warm_construct", "warm_mtkcompile", "warm_problem"]

function parent(reps, nwarm, other)
    jl = Base.julia_cmd()
    script = @__FILE__
    sides = ["this" => dirname(script)]
    other === nothing || pushfirst!(sides, "base" => joinpath(abspath(other), "benchmark"))
    for (_, proj) in sides                            # precompile, untimed
        run(`$jl --startup-file=no --project=$proj -e "using Potts, PottsModels"`)
    end
    results = Dict{Tuple{String, String}, Vector{Dict{String, Float64}}}()
    for r in 1:reps, case in CASES, (side, proj) in sides    # cases and sides interleaved
        cmd = `$jl --startup-file=no --project=$proj $script child $case $nwarm`
        local out
        wall = @elapsed out = read(cmd, String)
        line = only(filter(startswith("RESULT "), split(out, '\n')))
        d = Dict{String, Float64}(String(k) => parse(Float64, v) for (k, v) in (split(kv, '=') for kv in split(line)[2:end]))
        d["total"] = wall
        push!(get!(results, (side, case), Dict{String, Float64}[]), d)
        @printf("rep %d %-5s %-22s to_first_mcs %.2f s, total %.2f s\n", r, side, case, d["to_first_mcs"], wall)
    end
    med(side, case, k) = median(getindex.(results[(side, case)], k))
    println("\n# medians over $reps fresh processes ($nwarm warm repetitions each); seconds")
    println("side,case,", join(KEYS, ","))
    for (side, _) in sides, case in CASES
        println(side, ",", case, ",", join((@sprintf("%.4g", med(side, case, k)) for k in KEYS), ","))
    end
    if other !== nothing
        println("\n# ratio this/base of the medians (acceptance: construct, mtkcompile, problem, ",
            "warm_* and to_first_mcs each <= 1.05)")
        println("case,", join(KEYS, ","))
        for case in CASES
            println(case, ",", join((@sprintf("%.3f", med("this", case, k) / max(med("base", case, k), eps()))
                                     for k in KEYS), ","))
        end
    end
    println("\n# min,max of to_first_mcs per side and case")
    for (side, _) in sides, case in CASES
        t = getindex.(results[(side, case)], "to_first_mcs")
        @printf("%s,%s,%.3g,%.3g\n", side, case, minimum(t), maximum(t))
    end
    return nothing
end

if CHILD
    child(ARGS[2], parse(Int, ARGS[3]))
else
    parent(parse(Int, get(ARGS, 1, "5")), parse(Int, get(ARGS, 2, "10")), get(ARGS, 3, nothing))
end
