# Definitions of unseen_loop_tests.jl that other test files use (moved here by TS1b).
using Logging: Logging
using Test: collect_test_logs

@parameters sF = 0.035 sk = 0.065
@variables su(..) sv(..) bu(..) [bounds = (0.0, 1.0)] bv(..) [bounds = (0.0, 1.0)]
sue, sve, bue, bve = su(t, x, y), sv(t, x, y), bu(t, x, y), bv(t, x, y)
sdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
# Gray-Scott, periodic: `u v²` is a term the bound cannot see
function gsys(u, v, ue, ve; name)
    return PDESystem(
        [D(ue) ~ 2.0e-5 * laplacian(ue) - ue * ve^2 + sF * (1 - ue), D(ve) ~ 1.0e-5 * laplacian(ve) + ue * ve^2 - (sF + sk) * ve],
        [u(0, x, y) ~ 1.0 - 0.5x, v(0, x, y) ~ 0.25x, u(t, 0, y) ~ u(t, 1, y), u(t, x, 0) ~ u(t, x, 1),
         v(t, 0, y) ~ v(t, 1, y), v(t, x, 0) ~ v(t, x, 1)], sdom(4.0), [t, x, y], [ue, ve], [sF, sk]; name)
end
# the loop warnings a call gives (the other warnings, such as each unseen term's, are left out)
function loopwarns(f)
    logs, _ = collect_test_logs(f; min_level = Logging.Warn)
    return [string(l.message) for l in logs if occursin("read one another in a loop through terms", string(l.message)) ||
                                                    occursin("counts as reading every group", string(l.message))]
end
swarm(ig) = (step!(ig); step!(ig); @allocated step!(ig))
