# Solver test geometries (the reference cases of the masked-multigrid study, P3-mg/P4-mg42):
# a masked disk or sphere (Dirichlet value 1 in the medium and on the box layer), a box with
# face Dirichlet on x (0 at the low face, 1 at the high face) and periodic y, optionally with
# masked islands, and a periodic box. Face coefficients 1, shift `s` (scaled form).

using Random
using LatticeFields.Solvers: CellOperator, FieldSolver, LatticePCG, LatticeMultigrid, LatticeBlockSolve, VCycle, steady!,
                             field, scalars, rebuild!, lift!, solve!, lkey, RuleWeights,
                             solution_key

"""
Masked ball of radius `R` (cells) centered at `ctr`, box layer masked: `(op, inputs)`.
"""
function ball_case(dims::NTuple{N, Int}; s, R = 0.4 * dims[1],
        ctr = ntuple(d -> dims[d] / 2 + 0.31, N)) where {N}
    act = [sum(abs2, (Tuple(c) .- 0.5) .- ctr) < R^2 &&
               all(d -> 1 < c[d] < dims[d], 1:N) for c in CartesianIndices(dims)]
    op = CellOperator(dims; shift = s, mask = "in.mask", value = 1.0)
    return op, ("in.mask" => vec(UInt8.(.!act)),)
end

"""
Face Dirichlet on x (g = 0 low, 1 high), periodic y; `islands` masks that fraction of the
box with discs of radius 3 (value 0), drawn as in the reference study.
"""
function box_case(nx, ny; s, islands = 0.0, rad = 3.0, seed = 1)
    act = trues(nx, ny)
    if islands > 0
        rng = MersenneTwister(seed)
        while count(.!act) < islands * nx * ny
            cx = rand(rng) * (nx - 8rad) + 4rad
            cy = rand(rng) * ny
            for c in CartesianIndices(act)
                dy = abs(c[2] - 0.5 - cy)
                dy = min(dy, ny - dy)
                (c[1] - 0.5 - cx)^2 + dy^2 < rad^2 && (act[c] = false)
            end
        end
    end
    op = CellOperator((nx, ny); periodic = (false, true), shift = s,
        mask = islands > 0 ? "in.mask" : nothing, value = 0.0,
        dirichlet = ((0.0, 1.0), (nothing, nothing)))
    return op, islands > 0 ? ("in.mask" => vec(UInt8.(.!act)),) : ()
end

"""
Fully periodic box, right-hand side 1 on the low half of x.
"""
function periodic_case(nx, ny; s)
    f = zeros(nx, ny)
    f[1:(nx ÷ 2), :] .= 1
    return CellOperator((nx, ny); periodic = (true, true), shift = s), ("in.f" => vec(f),)
end

"""
A solver for a case with its inputs copied in.
"""
function case_solver(case, T; linsolve = :auto, rule = RuleWeights(), kw...)
    op, inputs = case
    sv = FieldSolver(HostExec(), op; T, linsolve, rule, kw...)
    for (k, v) in inputs
        copyto!(field(sv, k), v)
    end
    return sv
end

"""
Reference iteration counts `(PCG, stationary V(2,2))` to ‖r‖∞ ≤ 1e-6‖b‖∞ from zero, from the
Float64 reference implementation of the masked-multigrid study at the same depth (coarsest
level of one site where the dims allow, direct coarsest solve, rule M, Any fold).
"""
const REFERENCE = Dict(
    ("disk128", 5.5e-6) => (8, 10), ("disk128", 1.9e-3) => (7, 10),
    ("disk128", 0.022) => (6, 8), ("disk128", 0.063) => (6, 7),
    ("disk256", 5.5e-6) => (8, 11), ("disk256", 1.9e-3) => (7, 10),
    ("disk256", 0.022) => (7, 9), ("disk256", 0.063) => (6, 8),
    ("disk512", 5.5e-6) => (9, 19), ("disk512", 1.9e-3) => (8, 17),
    ("disk512", 0.022) => (7, 12), ("disk512", 0.063) => (7, 9),
    ("sphere42", 5.5e-6) => (7, 9), ("sphere42", 1.9e-3) => (7, 9),
    ("sphere42", 0.022) => (6, 8), ("sphere42", 0.063) => (6, 7),
    ("sphere64", 5.5e-6) => (7, 10), ("sphere64", 0.022) => (6, 8),
    ("box300x192", 5.5e-6) => (7, 9), ("box300x192", 1.9e-3) => (6, 8),
    ("box128", 5.5e-6) => (6, 9), ("box512", 5.5e-6) => (6, 9),
    ("box+isl256", 5.5e-6) => (8, 10), ("per256", 5.5e-6) => (8, 12),
    ("per300", 5.5e-6) => (12, 20))

function named_case(name, s)
    m = match(r"^disk(\d+)$", name)
    m === nothing || return ball_case((parse(Int, m[1]), parse(Int, m[1])); s)
    name == "sphere42" &&
        return ball_case((42, 42, 42); s, R = 15.8, ctr = (21.13, 20.87, 21.41))
    name == "sphere64" && return ball_case((64, 64, 64); s, R = 25.0)
    name == "box300x192" && return box_case(300, 192; s)
    name == "box+isl256" && return box_case(256, 256; s, islands = 0.1)
    m = match(r"^box(\d+)$", name)
    m === nothing || return box_case(parse(Int, m[1]), parse(Int, m[1]); s)
    m = match(r"^per(\d+)$", name)
    return periodic_case(parse(Int, m[1]), parse(Int, m[1]); s)
end

"""
Iterations of PCG and stationary V(2,2) from zero (host-checked, at most `maxiter`); PCG
undeflated by default, as in the reference implementation.
"""
function counts(case, T; maxiter = 40, deflate = false)
    return (
        steady!(case_solver(case, T; linsolve = LatticePCG(), deflate); maxiter),
        steady!(case_solver(case, T; linsolve = LatticeMultigrid()); maxiter),
    )
end

"""
Asymptotic factor of stationary cycles, (‖r₃₀‖∞/‖r₅‖∞)^(1/25), from a random error with
zero right-hand side (Dirichlet values 0).
"""
function cycle_factor(case; rule = RuleWeights(), cycle = VCycle(2, 2), T = Float64)
    op0, inputs = case
    op = CellOperator(
        op0.dims; periodic = op0.periodic, face = op0.face, shift = op0.shift,
        mask = op0.mask, value = 0.0,
        dirichlet = map(d -> map(g -> g === nothing ? nothing : 0.0, d), op0.dirichlet))
    sv = case_solver((op, inputs), T; linsolve = LatticeMultigrid(; cycle), rule)
    rebuild!(sv)
    lift!(sv)
    act = field(sv, lkey(0, "active")) .!= 0
    copyto!(field(sv, lkey(0, "x")), T.(rand(Xoshiro(3), length(act)) .- 0.5) .* act)
    rs = Float64[]
    for _ in 1:30
        solve!(sv; host = true, maxiters = 1)
        push!(rs, scalars(sv).rnorm)
    end
    return (rs[30] / rs[5])^(1 / 25)
end

"""
Assembled operator of level `l` over its active sites (Float64 host loop, flux form).
"""
function level_matrix(sv, l)
    d = Tuple(sv.ctx.dims[l + 1])
    N, per = length(d), sv.op.periodic
    act = field(sv, lkey(l, "active")) .!= 0
    w = [field(sv, lkey(l, "w$a")) for a in 1:N]
    s = field(sv, lkey(l, "s")) .+ field(sv, lkey(l, "sbox")) .+ field(sv, lkey(l, "sint"))
    cells = findall(act)
    idx = zeros(Int, prod(d))
    idx[cells] .= 1:length(cells)
    A = zeros(length(cells), length(cells))
    CI, LI = CartesianIndices(d), LinearIndices(d)
    for (q, i) in enumerate(cells)
        A[q, q] += s[i]
        for a in 1:N, σ in (1, -1)

            c = Tuple(CI[i])
            v = c[a] + σ
            (1 <= v <= d[a]) || per[a] || continue
            j = LI[CartesianIndex(ntuple(k -> k == a ? mod1(v, d[a]) : c[k], N))]
            wf = σ > 0 ? w[a][i] : w[a][j]
            A[q, q] += wf
            act[j] && (A[q, idx[j]] -= wf)
        end
    end
    return A
end

"""
The true residual `b − A x` over active sites (Float64, the same host loop as
`level_matrix`, unassembled) of `xs`, by default the solver's solution array.
"""
function true_residual(sv, xs = field(sv, Solvers.solution_key(sv)))
    d = Tuple(sv.ctx.dims[1])
    N, per = length(d), sv.op.periodic
    act = field(sv, lkey(0, "active")) .!= 0
    w = [Float64.(field(sv, lkey(0, "w$a"))) for a in 1:N]
    s = Float64.(field(sv, lkey(0, "s")) .+ field(sv, lkey(0, "sbox")) .+
                 field(sv, lkey(0, "sint")))
    b = Float64.(field(sv, sv.alg isa Solvers.FusedPCG ? "pcg.b" : lkey(0, "b")))
    x = Float64.(xs)
    CI, LI = CartesianIndices(d), LinearIndices(d)
    r = Float64[]
    for i in findall(act)
        Ax = s[i] * x[i]
        for a in 1:N, σ in (1, -1)

            c = Tuple(CI[i])
            v = c[a] + σ
            (1 <= v <= d[a]) || per[a] || continue
            j = LI[CartesianIndex(ntuple(k -> k == a ? mod1(v, d[a]) : c[k], N))]
            wf = σ > 0 ? w[a][i] : w[a][j]
            Ax += wf * (x[i] - (act[j] ? x[j] : 0.0))
        end
        push!(r, b[i] - Ax)
    end
    return r
end

"""
The solution in the solver's own precision (before conversion to the state type), as
Float64: under deflation `pcg.x − mean(pcg.x) + c`, else the working field.
"""
function solver_solution(sv)
    x = Float64.(field(sv, Solvers.working_key(sv)))
    sv.deflate || return x
    return x .- sum(x) / length(x) .+ scalars(sv).mean
end
