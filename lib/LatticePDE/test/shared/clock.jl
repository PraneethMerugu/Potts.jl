# Definitions of clock_tests.jl that other test files use.
using LatticeFields: Problems as LFP
using LatticeFields.Compile: CompileOptions

@parameters kη = 0.5
@variables kc(..)
kce = kc(t, x, y)
kdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
kperiodic = [kc(t, 0, y) ~ kc(t, 1, y), kc(t, x, 0) ~ kc(t, x, 1)]
# the rate is the step index: c(T) = Σ over the windows of dt · k
function ksys(T; rate = step_index(t))
    return PDESystem([D(kce) ~ rate], [kc(0, x, y) ~ 0.0; kperiodic], kdom(T), [t, x, y], [kce], [kη];
        name = :k)
end
kdisc(; clock = 1.0) = LatticeDiscretization(Grid((4, 4)); T = Float64, clock)
function kerr(f)
    return try
            f(); ""
        catch e
            e isa ArgumentError || rethrow()
            sprint(showerror, e)
        end
end
