# The lattice multigrid as a preconditioner of SciML's linear solves (F4-08; F4 design §3.7,
# SX-15, Q-A (b)): `LatticeMG()` is a LinearSolve `precs` function. Given the `W = J − M/γ`
# of an implicit OrdinaryDiffEq solver (or the operator `A` of a linear system with no time),
# it binds the owned implicit runtime of the problem (the rows' operators `J̃` of F3-07, with
# the shift `1/γ`) at the solver's state, and applies one V-cycle per field as `ldiv!`: the
# block-diagonal preconditioner of the coupled steady solve (F3-12d), on the problem's backend.

"""
    LatticeMG(; cycle = V(2, 2), cycles = 1)

A preconditioner for the linear solves of implicit SciML solvers on a lattice problem (F4-08):
a LinearSolve `precs` function, as in

    solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMG(), gmres_restart = 10)))

For `W = J − M/γ` it extracts each field's Helmholtz part `J̃` (its diffusion, its linear local
terms, its faces and masks; the operator of the field algorithms, F3-07) with the shift `1/γ`
(a steady row `0 ~ rhs`, `M = 0`, takes none), and applies `cycles` V-cycles (`cycle` its
smoothing steps) of the lattice multigrid per field from zero: a fixed linear operator, so
GMRES and CG keep their convergence theory. The other terms (advection, cross terms, nonlinear
local terms) are left to the Krylov method. A masked site (and a site outside the domain) is
inverted exactly. The operator is rebuilt at each new `W` (state, time, `γ`); on a device it
runs there, with no host wait.

Give GMRES a small memory, `gmres_restart = 10`. With this preconditioner GMRES takes a few
iterations per linear solve (3 to 4 for a diffusion–reaction system), and LinearSolve currently
allocates a new workspace of about `gmres_restart` state vectors at each new `W`
(`gmres_restart = 0`, the default, takes 20; SciML/LinearSolve.jl#1378 keeps the workspace). For FBDF at 512², 10 instead of the default allocates 17% less, with the
same steps and iterations. When the terms left to the Krylov method are strong (advection,
cross terms), increase it.
"""
struct LatticeMG
    cycle::Solvers.V
    cycles::Int
    engines::Dict{Any, Any}
    lock::ReentrantLock
end
function LatticeMG(; cycle = Solvers.V(2, 2), cycles::Integer = 1)
    cycles >= 1 || throw(ArgumentError("`LatticeMG(; cycles = $cycles)`: `cycles` is the number of V-cycles per field, an integer ≥ 1"))
    return LatticeMG(Solvers._cycle(cycle), Int(cycles), Dict{Any, Any}(), ReentrantLock())
end
Base.show(io::IO, mg::LatticeMG) = print(io, "LatticeMG(; cycle = (", mg.cycle.nu1, ", ", mg.cycle.nu2, "), cycles = ", mg.cycles, ")")

"""
    MGPreconditioner

What [`LatticeMG`](@ref) returns as the left preconditioner: the owned implicit runtime of a
lattice problem bound at a state, time and shift; `ldiv!(y, P, r)` applies its V-cycles.
"""
mutable struct MGPreconditioner{I, B}
    integ::I                           # the owned integrator of the runtime (`BackwardEuler`, steady rows `QuasiSteady`)
    rows::Vector{Any}                  # (implicit row, its state range, steady row?)
    backend::B
    p::Any                             # the parameters it was built at …
    stamp::Int                         # … at their write count
    values::Vector{Float64}            # … and their primal values
    γ::Float64                         # the shift's step `γ` (Inf: no shift)
    applies::Int                       # the `ldiv!` calls (a test reads it)
end

# the metadata of the problem behind an operator a SciML solver hands to `precs`
_mg_meta(x::LatticeJVP) = x.meta
_mg_meta(x::LatticeJacobian) = x.meta
_mg_meta(x::LatticeOperator) = x.f.meta
_mg_meta(x::SciMLBase.AbstractSciMLFunction) = lattice_metadata((; f = x))
_mg_meta(x::SciMLOperators.FunctionOperator) = _mg_meta(x.op)
function _mg_meta(x::SciMLOperators.WOperator)
    m = x.jacvec === nothing ? nothing : _mg_meta(x.jacvec)
    return m === nothing ? _mg_meta(x.J) : m
end
_mg_meta(x) = hasproperty(x, :f) ? _mg_meta(getproperty(x, :f)) : nothing
# … and its `γ` (`W = J − M/γ`; a linear system's `A = J`: no shift)
# (a solver's prototype `W` may hold a placeholder `γ`, such as 0, before its first step)
_mg_gamma(x::SciMLOperators.WOperator) = (γ = Float64(primal(x.gamma)); γ > 0 && isfinite(γ) ? γ : 1.0)
_mg_gamma(::LatticeOperator) = Inf

function (mg::LatticeMG)(W, p)
    m = _mg_meta(W)
    m isa LatticeMetadata || throw(ArgumentError(string("`LatticeMG()` preconditions the linear solves of a problem ",
        "`discretize` returned (its `W = J − M/γ`, or the operator of a system with no time); got a ", nameof(typeof(W)))))
    γ = _mg_gamma(W)
    fp = m.problem
    u, q, t = p isa Tuple && length(p) == 4 ? (p[2], p[3], p[4]) : (nothing, p, fp.tspan[1])
    lp = q isa LatticeParameters ? q : m.problem.p isa LatticeParameters ? m.problem.p :
         LatticeParameters(copy(fp.p), fp.tables, fp.inputs; fns = fp.inputfns)
    P = lock(mg.lock) do
        key = (objectid(m), current_task())
        e = get(mg.engines, key, nothing)
        if e === nothing || !_mg_current(e, lp)
            e = _mg_engine(mg, m, lp)
            mg.engines[key] = e
        end
        e
    end
    _mg_bind!(P, u === nothing ? fp.u0 : u, lp, Float64(primal(t)), γ)
    return (P, LinearAlgebra.I)
end
_mg_current(e::MGPreconditioner, lp::LatticeParameters) =
    e.p === lp && e.stamp == lp.stamp[] && e.values == Float64[primal(v) for v in lp.values]

# the owned implicit runtime of `m`'s problem at the parameters `lp`
function _mg_engine(mg::LatticeMG, m::LatticeMetadata, lp::LatticeParameters)
    fp = m.problem
    # (a system with no time: one window of a unit span, which `QuasiSteady` takes)
    span = fp.group.spec.timefree ? (0.0, 1.0) : fp.tspan
    g = _field_problem(fp.program, fp.state, Array(fp.u0), span, Vector{Float64}(map(primal, lp.values)), lp.tables,
        lp.inputs, fp.backend, fp.index, fp.faces, fp.stability, fp.kind, fp.initkeys, fp.options, fp.group)
    inner = Solvers.Multigrid(; cycle = mg.cycle, cycles = mg.cycles)
    st = fp.group.spec.steady
    h = 1.0
    be = BackwardEuler(; dt = h, substeps = 1, newton = 1, inner)
    qs = QuasiSteady(; dt = h, newton = 1, inner)
    alg = fp.group.spec.timefree ? qs : isempty(st) ? be : FieldGroups((k => qs for k in st)...; default = be)
    integ = CommonSolve.init(g, alg; save_start = false, save_end = false)
    s = fp.program
    slots = state_layout(s, Int[fieldid(s, k) for k in fp.state])
    rows = Any[]
    for rt in integ.runtimes
        c = rt.cache
        c isa ImplicitCache || continue
        for r in c.rows
            push!(rows, (r, slots[fieldid(s, r.key)], rt.alg isa QuasiSteady))
        end
    end
    return MGPreconditioner(integ, rows, fp.backend, lp, lp.stamp[], Float64[primal(v) for v in lp.values], Inf, 0)
end

# bind the runtime at the solver's state `u`, time `t` and step `γ`: the state in both slots,
# each row's shift `1/γ` (a steady row's none), the operator program at `u` and the hierarchies
function _mg_bind!(P::MGPreconditioner, u, lp, t, γ)
    ig = P.integ
    _load_state!(ig.store, u)
    # the inputs given as functions of the time, at the time of the bind (F4-B1), as the right side
    lp isa LatticeParameters && !isempty(lp.fns) && _mg_inputs!(ig, lp, t)
    k = lp.tick[]
    for rt in ig.runtimes
        c = rt.cache
        c isa ImplicitCache || continue
        steady = rt.alg isa QuasiSteady            # (no time-step term: `1/(γh) = 0`, built so)
        steady || _set_step!(c, rt, γ)
        _rebuild!(c, rt, 1, t, steady ? Inf : γ, k)
    end
    P.γ = γ
    return P
end

function _mg_inputs!(ig::FieldIntegrator, lp::LatticeParameters, t)
    prob = ig.prob
    s = Float64(primal(t))
    for (k, g) in lp.fns
        v = g(s)
        check_input_result(prob.program, k, v, prob.index)
        a = array(ig.store, fieldid(prob.program, k), :cur)
        v isa Number ? fill!(a, v) : _copy_input!(a, v)
    end
    _rerun_init!(ig, ig.pgood)
    return nothing
end

# `y = P r`: each field's V-cycles from zero on its part of `r` (`(I/γ − J̃) x = r`, and `W⁻¹ r ≈
# −x`), a row with no diffusion `−r/s`; a masked site or one outside the domain `−s r` (its row
# of `W` is `−1/γ`, or `−1` for a steady row's `0 = v − u`)
function LinearAlgebra.ldiv!(y::AbstractVector, P::MGPreconditioner, r::AbstractVector)
    b = P.backend
    γ = P.γ
    for (row, rng, steady) in P.rows
        n = length(rng)
        off = first(rng) - 1
        T = eltype(y)
        sfix = T(steady || isinf(γ) ? 1.0 : γ)
        if row.solver === nothing
            Exec.launch!(b, _mg_local_body!, n, (y, off, r, row.s, row.mask, row.dom, sfix))
            continue
        end
        Exec.launch!(b, _cs_pin_body!, n, (row.resarr, r, off))
        if row.f !== nothing
            F = eltype(row.f)
            ih = steady || isinf(γ) ? zero(F) : F(1 / γ)
            Exec.launch!(b, _cs_rhs_body!, n, (row.f, row.v, row.resarr, row.j, row.m, row.smask, row.rmask, row.dom, ih, ih / 2))
        end
        for w in row.work
            Exec.launch!(b, _zero_body!, length(w), (w,))
        end
        sv = row.solver
        Solvers.lift!(sv)
        Solvers.solve!(sv)
        x = sv.slot[row.xid] == 1 ? row.xs[1] : row.xs[2]
        Exec.launch!(b, _mg_out_body!, n, (y, off, x, r, row.mask, row.dom, sfix))
    end
    P.applies += 1
    return y
end
LinearAlgebra.ldiv!(P::MGPreconditioner, r::AbstractVector) = LinearAlgebra.ldiv!(r, P, copy(r))
Base.eltype(P::MGPreconditioner) = eltype(P.integ.prob)

# i ≤ n: the row's part at offset `off` (`x` the solver's solution, `r` the right side)
function _mg_out_body!(i, y, off, x, r, mask, dom, s)
    @inbounds y[off + i] = _cs_fixed(mask, dom, i) ? -s * r[off + i] : -eltype(y)(x[i])
    return nothing
end
function _mg_local_body!(i, y, off, r, sh, mask, dom, s)
    @inbounds begin
        K = eltype(y)
        d = K(_at(sh, i))
        y[off + i] = _cs_fixed(mask, dom, i) ? -s * r[off + i] : (d > 0 ? -r[off + i] / d : -r[off + i])
    end
    return nothing
end

"""
    LatticePCG(; precs = LatticeMG(), rtol, budget)

A LinearSolve algorithm for a symmetric `W` (a diffusion–reaction system: `W = J − M/γ` with
`J` symmetric, or the operator of a linear system with no time): preconditioned conjugate
gradients on `−W` with [`LatticeMG`](@ref)'s V-cycles, matrix-free (F4-08). Defined when
LinearSolve is loaded (its extension).
"""
function LatticePCG end
