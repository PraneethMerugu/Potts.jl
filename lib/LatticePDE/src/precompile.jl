# The precompile workload: two small owned CPU 2D problems, one with
# a source and a Dirichlet face only, one reaction–diffusion form (`Dc Δc − k c` with a Dirichlet
# face, a Neumann face and a periodic pair). Each is discretized, initialized, stepped and
# solved with `ExplicitEuler` and `BackwardEuler` in Float64 and Float32 and read back by name,
# with one call of the ODE right side and one `field_report`, so a first problem of that kind
# does not compile the front end, the bound, the group binding, the implicit solver, the
# solution and the report in the user's session. A generated kernel is cached by its
# expression, so a user problem whose kernels match one of these (the same terms and faces)
# also reuses the compiled kernels. (A user turns the workload off with PrecompileTools'
# preference `precompile_workload = false`.) The tests call it too.

function _precompile_workload()
    t, D = ModelingToolkitBase.t_nounits, ModelingToolkitBase.D_nounits
    x, y = Symbolics.@variables x y
    Dc, k = ModelingToolkitBase.@parameters Dc = 0.3 k = 2.0
    c = only(Symbolics.@variables c(..))
    ce = c(t, x, y)
    dom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    forms = (
        (D(ce) ~ Dc * laplacian(ce) - k * ce + x, [c(0, x, y) ~ x * y, c(t, 0, y) ~ 1.0]),
        (
            D(ce) ~ Dc * laplacian(ce) - k * ce,
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
        ),
    )
    for (eq, bc) in forms, T in (Float64, Float32)
        sys = PDESystem([eq], bc, dom, [t, x, y], [ce], [Dc, k]; name = :precompile)
        prob = discretize(sys, LatticeDiscretization(Grid((8, 8)); T))
        du = similar(prob.u0)
        prob.f(du, prob.u0, prob.p, zero(T))                         # the ODE right side
        for alg in (ExplicitEuler(), BackwardEuler())
            integ = init(prob, alg; dt = T(0.01))
            step!(integ)
            integ[ce]
            sol = solve(prob, alg; dt = T(0.01), saveat = T(0.5))
            sol[ce]
            field_report(devnull, sol)
        end
    end
    return nothing
end

@setup_workload begin
    @compile_workload begin
        _precompile_workload()
    end
end
