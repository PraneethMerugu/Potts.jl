# The cases of convergence_orders_tests.jl: each function solves one manufactured problem
# at several time steps or grid sizes and returns a `convergence_case` record (the errors
# in the max norm against the exact or reference solution). The tests assert on the
# records; `write_convergence_data.jl` writes them to the committed data file of the
# convergence docs page, and the tests check that file against the records.
#
# Needs `observed_orders` and `observed_order` (test/shared/convergence_helpers.jl).
using LatticePDE
using ModelingToolkitBase: @parameters, @variables, Differential, PDESystem,
    t_nounits as t, D_nounits as D
using Symbolics: Num
using DomainSets: Interval
using SciMLBase: SciMLBase, solve
using LatticeFields: Problems as LFP
using OrdinaryDiffEqTsit5: Tsit5
using TOML: TOML

# the inner solver of the implicit steppers: tight, so that the time error dominates
const CONVERGENCE_LINSOLVE = LatticePCG(; reltol = 1.0e-12, maxiters = 64)

# The committed data file, at docs/src/fields/ of the repository
const CONVERGENCE_DATA_FILE = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "docs", "src", "fields", "convergence.toml")
)

"""
    convergence_case(name, kind, method, problem, variable, sizes, steps, errors, expected)

One convergence case: `kind` is `"solver"` (a time stepper; `variable` is `"dt"`) or
`"operator"` (a spatial operator; `variable` is `"h"`), `sizes` the grid size per level,
`steps` the time step or spacing per level, `errors` the max-norm error per level and
`expected` the order of the method.
"""
function convergence_case(
        name, kind, method, problem, variable, sizes, steps, errors, expected
    )
    return (;
        name = String(name), kind = String(kind), method = String(method),
        problem = String(problem), norm = "max", variable = String(variable),
        sizes = Int.(sizes), steps = Float64.(steps), errors = Float64.(errors),
        observed_orders = observed_orders(steps, errors),
        observed_order = observed_order(steps, errors), expected_order = Float64(expected),
    )
end

# Manufactured solution u(t, x, y) = exp(t) sin(pi x) sin(pi y) on [0, 1]^2 for
# u_t = D Δu + f; the reference is the semi-discrete solution on a 16 × 16 grid by Tsit5
# at 1e-12, so the errors are the time error of each stepper alone.
function temporal_convergence_cases()
    @parameters x y
    @variables u(..)
    ue = u(t, x, y)
    Dcoef = 0.005
    src = (1.0 + 2.0 * Dcoef * pi^2) * exp(t) * sin(pi * x) * sin(pi * y)
    sys = PDESystem(
        [D(ue) ~ Dcoef * laplacian(ue) + src],
        [
            u(0, x, y) ~ sin(pi * x) * sin(pi * y),
            u(t, 0, y) ~ 0.0, u(t, 1, y) ~ 0.0, u(t, x, 0) ~ 0.0, u(t, x, 1) ~ 0.0,
        ],
        [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
        [t, x, y], [ue], Num[]; name = :mms_time
    )
    prob = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64))
    ref = solve(prob, Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end]
    dts = [0.04, 0.02, 0.01]
    problem = "diffusion with a source, 16 × 16, to t = 0.2"
    return map(
        [
            ("ExplicitEuler", ExplicitEuler(; substeps = 1), 1.0),
            ("BackwardEuler", BackwardEuler(; linsolve = CONVERGENCE_LINSOLVE), 1.0),
            ("CrankNicolson", CrankNicolson(; linsolve = CONVERGENCE_LINSOLVE), 2.0),
            ("BDF2", BDF2(; linsolve = CONVERGENCE_LINSOLVE), 2.0),
        ]
    ) do (label, alg, expected)
        errs = [maximum(abs, solve(prob, alg; dt).u[end] .- ref) for dt in dts]
        convergence_case(
            label, "solver", label, problem, "dt", fill(16, 3), dts, errs, expected
        )
    end
end

# Two coupled fields stepped by FieldGroups: u explicit, v implicit (first order overall)
function imex_convergence_case()
    @parameters x y
    @variables u(..) v(..)
    ue, ve = u(t, x, y), v(t, x, y)
    Dcoef = 0.005
    src = (1.0 + 2.0 * Dcoef * pi^2) * exp(t) * sin(pi * x) * sin(pi * y)
    sys = PDESystem(
        [
            D(ue) ~ Dcoef * laplacian(ue) - 0.5 * ve + src,
            D(ve) ~ 0.2 * laplacian(ve) - ve + 0.5 * ue,
        ],
        [
            u(0, x, y) ~ sin(pi * x) * sin(pi * y),
            v(0, x, y) ~ x * (1 - x) * y * (1 - y),
            u(t, 0, y) ~ 0.0, u(t, 1, y) ~ 0.0, u(t, x, 0) ~ 0.0, u(t, x, 1) ~ 0.0,
            v(t, 0, y) ~ 0.0, v(t, 1, y) ~ 0.0, v(t, x, 0) ~ 0.0, v(t, x, 1) ~ 0.0,
        ],
        [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
        [t, x, y], [ue, ve], Num[]; name = :imex_time
    )
    prob = discretize(sys, LatticeDiscretization(Grid((12, 12)); T = Float64))
    ref = solve(prob, Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end]
    dts = [0.02, 0.01, 0.005]
    alg = FieldGroups(
        ue => ExplicitEuler(; substeps = 1),
        ve => BackwardEuler(; linsolve = CONVERGENCE_LINSOLVE)
    )
    errs = [maximum(abs, solve(prob, alg; dt).u[end] .- ref) for dt in dts]
    return convergence_case(
        "FieldGroups IMEX", "solver", "FieldGroups(ExplicitEuler, BackwardEuler)",
        "two coupled fields, 12 × 12, to t = 0.2", "dt", fill(12, 3), dts, errs, 1.0
    )
end

# the max-norm error of a solution vector on an `nx × ny` grid of [0, 1]^2 against
# `exact(x, y)` at the site centers
function site_error(u, nx, ny, exact)
    xs = ((1:nx) .- 0.5) ./ nx
    ys = ((1:ny) .- 0.5) ./ ny
    return maximum(abs, reshape(u, nx, ny) .- [exact(a, b) for a in xs, b in ys])
end

# Steady -div(K grad u) + u = f with K(x, y) = 1 + 0.5 x and the exact solution
# u = sin(pi x) sin(pi y); `mean_kind` is the face mean of K
function divkgrad_convergence_case(mean_kind::Symbol)
    @parameters x y
    @variables u(..)
    Kexpr = 1.0 + 0.5 * x
    exact(a, b) = sin(pi * a) * sin(pi * b)
    rhs = Kexpr * 2 * pi^2 * sin(pi * x) * sin(pi * y) -
        0.5 * pi * cos(pi * x) * sin(pi * y) + exact(x, y)
    sys = PDESystem(
        [0 ~ DivKGrad(mean_kind)(Kexpr, u(x, y)) - u(x, y) + rhs],
        [u(0, y) ~ 0.0, u(1, y) ~ 0.0, u(x, 0) ~ 0.0, u(x, 1) ~ 0.0],
        [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [u(x, y)], Num[];
        name = Symbol(:dkg_, mean_kind)
    )
    ns = [16, 32, 64]
    errs = map(ns) do N
        lp = discretize(sys, LatticeDiscretization(Grid((N, N)); T = Float64))
        sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
        site_error(sol.u, N, N, exact)
    end
    return convergence_case(
        "DivKGrad $mean_kind", "operator", "DivKGrad(:$mean_kind)",
        "steady variable-coefficient diffusion, Dirichlet", "h", ns, 1.0 ./ ns, errs, 2.0
    )
end

# Steady periodic advection-reaction 0 = -∂_x u - u + f with the exact u = sin(2 pi x)
function upwind_convergence_case()
    @parameters x y
    @variables u(..)
    sys = PDESystem(
        [
            0 ~
                -Advect(Upwind1())([1.0, 0.0], u(x, y)) - u(x, y) +
                2 * pi * cos(2 * pi * x) + sin(2 * pi * x),
        ],
        [u(0, y) ~ u(1, y), u(x, 0) ~ u(x, 1)],
        [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [u(x, y)], Num[];
        name = :upwind_order
    )
    ns = [16, 32, 64, 128]
    errs = map(ns) do N
        lp = discretize(sys, LatticeDiscretization(Grid((N, 8)); T = Float64))
        site_error(LFP.lattice_matrix(lp.A) \ lp.b, N, 8, (a, _) -> sin(2 * pi * a))
    end
    return convergence_case(
        "Advect Upwind1", "operator", "Advect(Upwind1())",
        "steady periodic advection-reaction", "h", ns, 1.0 ./ ns, errs, 1.0
    )
end

# Steady Δu - u = f with the exact u = x^2 + 1: a Robin face at x = 0, Dirichlet at x = 1,
# zero flux in y
function robin_convergence_case()
    @parameters x y
    @variables u(..)
    sys = PDESystem(
        [0 ~ laplacian(u(x, y)) - u(x, y) + (x^2 + 1 - 2)],
        [
            1.5 * u(0, y) - Differential(x)(u(0, y)) ~ 1.5, u(1, y) ~ 2.0,
            Differential(y)(u(x, 0)) ~ 0.0, Differential(y)(u(x, 1)) ~ 0.0,
        ],
        [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [u(x, y)], Num[];
        name = :robin_order
    )
    ns = [16, 32, 64]
    errs = map(ns) do N
        lp = discretize(sys, LatticeDiscretization(Grid((N, N)); T = Float64))
        sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
        site_error(sol.u, N, N, (a, _) -> a^2 + 1.0)
    end
    return convergence_case(
        "Robin face", "operator", "laplacian, Robin face",
        "steady reaction-diffusion with a Robin face", "h", ns, 1.0 ./ ns, errs, 2.0
    )
end

# Periodic Helmholtz problem on the axial hexagonal grid: Δ_hex u = (4/3) ∂_x^2 u for
# u = sin(2 pi x)
function hex_convergence_case()
    @parameters x y
    @variables u(..)
    sys = PDESystem(
        [0 ~ 0.75 * laplacian(u(x, y)) - u(x, y) + (4 * pi^2 + 1) * sin(2 * pi * x)],
        [u(0, y) ~ u(1, y), u(x, 0) ~ u(x, 1)],
        [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [u(x, y)], Num[];
        name = :hex_order
    )
    ns = [16, 32, 64]
    errs = map(ns) do N
        disc = LatticeDiscretization(Grid((N, N); geometry = HEX); T = Float64)
        sol = solve(discretize(sys, disc), LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
        site_error(sol.u, N, N, (a, _) -> sin(2 * pi * a))
    end
    return convergence_case(
        "Hexagonal Laplacian", "operator", "laplacian, HEX grid",
        "steady periodic Helmholtz problem", "h", ns, 1.0 ./ ns, errs, 2.0
    )
end

# Steady 0.3 Δw - 2 w + f = 0 with the exact w = sin(pi x) sin(pi y), solved by LatticePCG
# (multigrid-preconditioned); also returns the iteration counts and the success of each
# solve
function multigrid_convergence_case()
    @parameters x y
    @variables w(..)
    exact(a, b) = sin(pi * a) * sin(pi * b)
    rhs = (0.3 * 2 * pi^2 + 2.0) * sin(pi * x) * sin(pi * y)
    sys = PDESystem(
        [0 ~ 0.3 * laplacian(w(x, y)) - 2.0 * w(x, y) + rhs],
        [w(0, y) ~ 0.0, w(1, y) ~ 0.0, w(x, 0) ~ 0.0, w(x, 1) ~ 0.0],
        [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [x, y], [w(x, y)], Num[];
        name = :mg_mesh_indep
    )
    ns = [32, 64, 128]
    errs, iters, successes = Float64[], Int[], Bool[]
    for N in ns
        lp = discretize(sys, LatticeDiscretization(Grid((N, N)); T = Float64))
        sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
        push!(successes, SciMLBase.successful_retcode(sol))
        push!(iters, sol.iters)
        push!(errs, site_error(sol.u, N, N, exact))
    end
    case = convergence_case(
        "Laplacian (LatticePCG)", "operator", "laplacian",
        "steady reaction-diffusion, Dirichlet", "h", ns, 1.0 ./ ns, errs, 2.0
    )
    return (; case, iters, successes)
end

# every case, in the order of the data file
function convergence_cases()
    return [
        temporal_convergence_cases(); imex_convergence_case();
        divkgrad_convergence_case(:harmonic); divkgrad_convergence_case(:arithmetic);
        upwind_convergence_case(); robin_convergence_case(); hex_convergence_case();
        multigrid_convergence_case().case
    ]
end

const CONVERGENCE_FIELDS = (
    :name, :kind, :method, :problem, :norm, :variable, :sizes, :steps, :errors,
    :observed_orders, :observed_order, :expected_order,
)

"""
    write_convergence_data(path, cases)

Write `cases` to the TOML file `path`, one `[[case]]` table per case.
"""
function write_convergence_data(path::AbstractString, cases)
    open(path, "w") do io
        println(io, "# Observed convergence orders of LatticePDE (max-norm errors).")
        println(io, "# Written by lib/LatticePDE/test/write_convergence_data.jl;")
        println(io, "# do not edit by hand.")
        println(io, "# The LatticePDE convergence tests check this file against what")
        println(io, "# they compute.")
        for c in cases
            println(io, "\n[[case]]")
            data = Dict(String(k) => getfield(c, k) for k in CONVERGENCE_FIELDS)
            order = k -> findfirst(==(Symbol(k)), CONVERGENCE_FIELDS)
            TOML.print(io, data; sorted = true, by = order)
        end
    end
    return path
end

"""
    read_convergence_data(path) -> Vector{Dict{String, Any}}

The `[[case]]` tables of the data file `path`.
"""
read_convergence_data(path::AbstractString) = TOML.parsefile(path)["case"]

"""
    convergence_data_issues(committed, cases; rtol = 1.0e-4) -> Vector{String}

How the committed tables `committed` differ from the computed `cases` (matched by name):
a case missing on either side, a text field or a grid size that differs, or a step, error
or order that differs by more than `rtol` (relative). Empty when they agree.
"""
function convergence_data_issues(committed, cases; rtol = 1.0e-4)
    issues = String[]
    byname = Dict(String(row["name"]) => row for row in committed)
    for c in cases
        row = get(byname, c.name, nothing)
        if row === nothing
            push!(issues, "$(c.name): not in the data file")
            continue
        end
        for k in CONVERGENCE_FIELDS
            want, have = getfield(c, k), get(row, String(k), nothing)
            ok = if have === nothing
                false
            elseif want isa AbstractString || eltype(want) <: Integer
                have == want
            else
                length(have) == length(want) && all(isapprox.(have, want; rtol))
            end
            ok || push!(issues, "$(c.name): $k is $(repr(have)), computed $(repr(want))")
        end
    end
    for name in setdiff(keys(byname), [c.name for c in cases])
        push!(issues, "$name: in the data file, but not a case")
    end
    return issues
end
