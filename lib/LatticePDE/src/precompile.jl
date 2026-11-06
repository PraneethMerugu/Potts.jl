# The precompile workload (F3 review round 2): a small owned CPU Float64 2D problem, discretized,
# initialized, stepped and solved with `ExplicitEuler` and `BackwardEuler`, so a first problem
# of that kind does not compile the front end, the bound, the group binding and the implicit
# solver in the user's session. (A user turns it off with PrecompileTools' preference
# `precompile_workload = false`.)
using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    t, D = ModelingToolkitBase.t_nounits, ModelingToolkitBase.D_nounits
    @compile_workload begin
        x, y = Symbolics.@variables x y
        Dc, k = ModelingToolkitBase.@parameters Dc = 0.3 k = 2.0
        c = only(Symbolics.@variables c(..))
        ce = c(t, x, y)
        sys = PDESystem([D(ce) ~ Dc * Δ(ce) - k * ce + x], [c(0, x, y) ~ x * y, c(t, 0, y) ~ 1.0],
            [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce], [Dc, k];
            name = :precompile)
        prob = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64))
        for alg in (ExplicitEuler(; dt = 0.01), BackwardEuler(; dt = 0.01))
            integ = init(prob, alg)
            step!(integ)
            solve(prob, alg)
        end
    end
end
