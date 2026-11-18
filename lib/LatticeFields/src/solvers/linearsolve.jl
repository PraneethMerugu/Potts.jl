# The lattice solvers as LinearSolve.jl algorithms: `LatticePCG`, `LatticeGMRES` and the stationary
# `LatticeMultigrid` take a `LinearProblem` through `init`/`solve!`, with their preconditioners
# given by LinearSolve's `precs` contract (`LatticeMultigrid`, `LatticeBlockSolve`). On a lattice
# field's operator (`BoundOperator`) with `precs = LatticeMultigrid(…)` (symmetric, 1 cycle),
# `LatticePCG` and `LatticeMultigrid` use the field's `FieldSolver` as their cache and keep the
# iteration and V-cycle fused into one program. Any other `precs` (including `precs = nothing`)
# or any other operator (OrdinaryDiffEq's `W`, `LatticeOperator`) takes the generic Krylov.jl path.

const FUSED_MAXITERS_CAP = 1024

"""
    BoundOperator(exec, op::CellOperator; T = Float32, solver_type = :auto, inputs = ())

A lattice field's operator `op` bound to an executor and to its coefficient arrays (the inputs
of [`FieldSolver`](@ref) other than the right-hand side `"in.f"`): the `A` of a
`LinearProblem(A, b)` that [`LatticePCG`](@ref), [`LatticeMultigrid`](@ref) and generic
LinearSolve algorithms (`KrylovJL_CG`, `KrylovJL_GMRES`) solve. It has a size, an element type
(`T`, the state type), `mul!` and `*` (one stencil kernel on `exec`, identity on masked sites).
"""
struct BoundOperator{T, N, E, I} <: SciMLOperators.AbstractSciMLOperator{T}
    exec::E
    op::CellOperator{N}
    solver_type::Any
    inputs::I
end
BoundOperator(exec, op::CellOperator{N}, ::Type{T}, solver_type, inputs) where {T, N} =
    BoundOperator{T, N, typeof(exec), typeof(inputs)}(exec, op, solver_type, inputs)
BoundOperator(exec, op::CellOperator; T = Float32, solver_type = :auto, inputs = ()) =
    BoundOperator(exec, op, T, solver_type, Tuple(inputs))
Base.size(A::BoundOperator) = (n = prod(A.op.dims); (n, n))
Base.size(A::BoundOperator, i::Integer) = size(A)[i]
Base.copy(A::BoundOperator) = A
SciMLOperators.islinear(::BoundOperator) = true
SciMLOperators.has_mul(::BoundOperator) = true
SciMLOperators.has_mul!(::BoundOperator) = true
SciMLOperators.has_concretization(::BoundOperator) = true
SparseArrays.sparse(A::BoundOperator) = sparse_operator(A)
function Base.convert(::Type{AbstractMatrix}, A::BoundOperator)
    _check_host_factorization(A.exec, BoundOperator)
    return sparse_operator(A)
end

function _is_cpu_exec(exec)
    exec isa KA.Backend && return exec isa KA.CPU
    return true
end
function _check_host_factorization(exec, alg)
    _is_cpu_exec(exec) && return nothing
    name = alg isa Type ? nameof(alg) : nameof(typeof(alg))
    throw(
        ArgumentError(
            string(
                "`", name, "` needs a concrete sparse matrix on the host and is not supported on device backend ",
                nameof(typeof(exec)), "; pass a matrix-free solver (`linsolve = LatticePCG()` or `linsolve = LatticeMultigrid()`)"
            )
        )
    )
end

function _bound_input(A::BoundOperator, key)
    key isa String || return nothing
    for (k, v) in A.inputs
        String(k) == key && return v
    end
    return nothing
end

@inline _bound_coords(idx::Int, dims::NTuple{1, Int32}) = (idx,)
@inline function _bound_coords(idx::Int, dims::NTuple{2, Int32})
    d1 = Int(dims[1])
    r = idx - 1
    return (mod(r, d1) + 1, div(r, d1) + 1)
end
@inline function _bound_coords(idx::Int, dims::NTuple{3, Int32})
    d1, d2 = Int(dims[1]), Int(dims[2])
    r = idx - 1
    c1 = mod(r, d1) + 1
    r2 = div(r, d1)
    return (c1, mod(r2, d2) + 1, div(r2, d2) + 1)
end
@inline function _bound_coords(idx::Int, dims::NTuple{N, Int32}) where {N}
    return Tuple(CartesianIndices(map(Int, dims))[idx])
end

function _bound_mul_body!(i, S, P, G)
    y, x, mask, sh, fs = S
    T = eltype(y)
    idx = Int(i)
    @inbounds begin
        if mask !== nothing && mask[idx] != 0
            y[idx] = T(x[idx])
            return nothing
        end
        x0 = T(x[idx])
        s0 = sh === nothing ? G.shift : T(sh[idx])
        acc = s0 * x0
        N = length(G.dims)
        coords = _bound_coords(idx, G.dims)
        for a in 1:N
            da = Int(G.dims[a])
            da == 1 && continue
            sa = Int(G.strides[a])
            fa = fs[a]
            wi = fa === nothing ? G.faces[a] : T(fa[idx])
            ca = coords[a]
            if ca > 1
                j = idx - sa
                wj = fa === nothing ? G.faces[a] : T(fa[j])
                xj = (mask !== nothing && mask[j] != 0) ? zero(T) : T(x[j])
                acc += wj * (x0 - xj)
            elseif G.per[a]
                j = idx + (da - 1) * sa
                wj = fa === nothing ? G.faces[a] : T(fa[j])
                xj = (mask !== nothing && mask[j] != 0) ? zero(T) : T(x[j])
                acc += wj * (x0 - xj)
            elseif G.dir[a][1]
                acc += T(2) * wi * x0
            elseif G.rob[a][1] != zero(T)
                acc += G.rob[a][1] * wi * x0
            end
            if ca < da
                j = idx + sa
                xj = (mask !== nothing && mask[j] != 0) ? zero(T) : T(x[j])
                acc += wi * (x0 - xj)
            elseif G.per[a]
                j = idx - (da - 1) * sa
                xj = (mask !== nothing && mask[j] != 0) ? zero(T) : T(x[j])
                acc += wi * (x0 - xj)
            elseif G.dir[a][2]
                acc += T(2) * wi * x0
            elseif G.rob[a][2] != zero(T)
                acc += G.rob[a][2] * wi * x0
            end
        end
        if G.hex && N == 2 && G.dims[1] > 1 && G.dims[2] > 1
            d1, d2 = Int(G.dims[1]), Int(G.dims[2])
            c1, c2 = coords[1], coords[2]
            f3 = fs[3]
            w3i = f3 === nothing ? G.faces[3] : T(f3[idx])
            in1 = G.per[1] || c1 < d1
            in2 = G.per[2] || c2 > 1
            if in1 && in2
                j = mod1(c1 + 1, d1) + (mod1(c2 - 1, d2) - 1) * d1
                xj = (mask !== nothing && mask[j] != 0) ? zero(T) : T(x[j])
                acc += w3i * (x0 - xj)
            else
                dg = !in1 ? (G.dir[1][2] ? T(2) : G.rob[1][2]) : (G.dir[2][1] ? T(2) : G.rob[2][1])
                acc += dg * w3i * x0
            end
            in1 = G.per[1] || c1 > 1
            in2 = G.per[2] || c2 < d2
            if in1 && in2
                j = mod1(c1 - 1, d1) + (mod1(c2 + 1, d2) - 1) * d1
                wj = f3 === nothing ? G.faces[3] : T(f3[j])
                xj = (mask !== nothing && mask[j] != 0) ? zero(T) : T(x[j])
                acc += wj * (x0 - xj)
            else
                dg = !in1 ? (G.dir[1][1] ? T(2) : G.rob[1][1]) : (G.dir[2][2] ? T(2) : G.rob[2][2])
                acc += dg * w3i * x0
            end
        end
        y[idx] = acc
    end
    return nothing
end

function LinearAlgebra.mul!(y::AbstractVector, A::BoundOperator{ET, N}, x::AbstractVector) where {ET, N}
    n = prod(A.op.dims)
    length(y) == n && length(x) == n ||
        throw(DimensionMismatch("BoundOperator has size ($n, $n); got y of length $(length(y)) and x of length $(length(x))"))
    _, mask, sh, fs, dims, strides, per, hex, s_scalar, f_scalars, dir, rob = _bound_stencil(A, eltype(y))
    G = (; n = Int32(n), dims, strides, per, hex, shift = s_scalar, faces = f_scalars, dir, rob)
    launch!(A.exec, Launch(_bound_mul_body!, n, (y, x, mask, sh, fs), (), G, "bound.mul"))
    return y
end

function _bound_stencil(A::BoundOperator{ET, N}, ::Type{T}) where {ET, N, T}
    op = A.op
    n = prod(op.dims)
    mask = _bound_input(A, op.mask)
    sh = _bound_input(A, op.shift)
    fs = map(f -> _bound_input(A, f), faces(op))
    dims = Int32.(op.dims)
    strides = ntuple(a -> Int32(prod(op.dims[1:(a - 1)])), N)
    rob = ntuple(a -> ntuple(k -> (r = op.robin[a][k]; r === nothing ? zero(T) : T(_robin_slots(op, r)[1])), 2), N)
    dir = ntuple(a -> ntuple(k -> op.dirichlet[a][k] !== nothing, 2), N)
    return n, mask, sh, fs, dims, strides, op.periodic, ishex(op),
        T(op.shift isa Real ? op.shift : 0), map(f -> T(f isa Real ? f : 0), faces(op)), dir, rob
end

function _visit_bound_entries(emit!, A::BoundOperator{ET, N}, ::Type{T}) where {ET, N, T}
    n, mask, sh, fs, dims, strides, per, hex, s_scalar, f_scalars, dir, rob = _bound_stencil(A, T)
    @inbounds for idx in 1:n
        if mask !== nothing && mask[idx] != 0
            emit!(idx, idx, one(T))
            coords = _bound_coords(idx, dims)
            for a in 1:N
                da = Int(dims[a])
                da == 1 && continue
                sa = Int(strides[a])
                ca = coords[a]
                if ca > 1
                    emit!(idx, idx - sa, zero(T))
                elseif per[a]
                    emit!(idx, idx + (da - 1) * sa, zero(T))
                end
                if ca < da
                    emit!(idx, idx + sa, zero(T))
                elseif per[a]
                    emit!(idx, idx - (da - 1) * sa, zero(T))
                end
            end
            if hex && N == 2 && dims[1] > 1 && dims[2] > 1
                d1, d2 = Int(dims[1]), Int(dims[2])
                c1, c2 = coords[1], coords[2]
                if (per[1] || c1 < d1) && (per[2] || c2 > 1)
                    emit!(idx, mod1(c1 + 1, d1) + (mod1(c2 - 1, d2) - 1) * d1, zero(T))
                end
                if (per[1] || c1 > 1) && (per[2] || c2 < d2)
                    emit!(idx, mod1(c1 - 1, d1) + (mod1(c2 + 1, d2) - 1) * d1, zero(T))
                end
            end
            continue
        end
        diag = sh === nothing ? s_scalar : T(sh[idx])
        coords = _bound_coords(idx, dims)
        for a in 1:N
            da = Int(dims[a])
            da == 1 && continue
            sa = Int(strides[a])
            fa = fs[a]
            wi = fa === nothing ? f_scalars[a] : T(fa[idx])
            ca = coords[a]
            if ca > 1 || per[a]
                j = ca > 1 ? idx - sa : idx + (da - 1) * sa
                wj = fa === nothing ? f_scalars[a] : T(fa[j])
                diag += wj
                emit!(idx, j, (mask !== nothing && mask[j] != 0) ? zero(T) : -wj)
            elseif dir[a][1]
                diag += T(2) * wi
            elseif rob[a][1] != zero(T)
                diag += rob[a][1] * wi
            end
            if ca < da || per[a]
                j = ca < da ? idx + sa : idx - (da - 1) * sa
                diag += wi
                emit!(idx, j, (mask !== nothing && mask[j] != 0) ? zero(T) : -wi)
            elseif dir[a][2]
                diag += T(2) * wi
            elseif rob[a][2] != zero(T)
                diag += rob[a][2] * wi
            end
        end
        if hex && N == 2 && dims[1] > 1 && dims[2] > 1
            d1, d2 = Int(dims[1]), Int(dims[2])
            c1, c2 = coords[1], coords[2]
            f3 = fs[3]
            w3i = f3 === nothing ? f_scalars[3] : T(f3[idx])
            in1 = per[1] || c1 < d1
            in2 = per[2] || c2 > 1
            if in1 && in2
                j = mod1(c1 + 1, d1) + (mod1(c2 - 1, d2) - 1) * d1
                diag += w3i
                emit!(idx, j, (mask !== nothing && mask[j] != 0) ? zero(T) : -w3i)
            else
                dg = !in1 ? (dir[1][2] ? T(2) : rob[1][2]) : (dir[2][1] ? T(2) : rob[2][1])
                diag += dg * w3i
            end
            in1 = per[1] || c1 > 1
            in2 = per[2] || c2 < d2
            if in1 && in2
                j = mod1(c1 - 1, d1) + (mod1(c2 + 1, d2) - 1) * d1
                wj = f3 === nothing ? f_scalars[3] : T(f3[j])
                diag += wj
                emit!(idx, j, (mask !== nothing && mask[j] != 0) ? zero(T) : -wj)
            else
                dg = !in1 ? (dir[1][1] ? T(2) : rob[1][1]) : (dir[2][2] ? T(2) : rob[2][2])
                diag += dg * w3i
            end
        end
        emit!(idx, idx, diag)
    end
    return nothing
end

function sparse_operator(A::BoundOperator{ET}) where {ET}
    _check_host_factorization(A.exec, BoundOperator)
    n = size(A, 1)
    I = Int[]
    J = Int[]
    V = ET[]
    est = (2 * length(A.op.dims) + 3) * n
    sizehint!(I, est)
    sizehint!(J, est)
    sizehint!(V, est)
    _visit_bound_entries(A, ET) do i, j, v
        push!(I, i)
        push!(J, j)
        push!(V, v)
    end
    return SparseArrays.sparse(I, J, V, n, n)
end
function _csc_add!(M::SparseArrays.SparseMatrixCSC{T}, i::Int, j::Int, v::T) where {T}
    rv = SparseArrays.rowvals(M)
    nz = SparseArrays.nonzeros(M)
    lo = Int(M.colptr[j])
    hi = Int(M.colptr[j + 1]) - 1
    k = searchsortedfirst(rv, i, lo, hi, Base.Order.Forward)
    @inbounds nz[k] += v
    return nothing
end
function sparse_operator!(M::SparseArrays.SparseMatrixCSC{T}, A::BoundOperator) where {T}
    _check_host_factorization(A.exec, BoundOperator)
    fill!(SparseArrays.nonzeros(M), zero(T))
    _visit_bound_entries(A, T) do i, j, v
        _csc_add!(M, i, j, v)
    end
    return M
end
function LinearAlgebra.mul!(y::AbstractVector, A::BoundOperator, x::AbstractVector, α::Number, β::Number)
    if α == 1 && β == 0
        return LinearAlgebra.mul!(y, A, x)
    end
    t = similar(y)
    LinearAlgebra.mul!(t, A, x)
    y .= α .* t .+ β .* y
    return y
end
Base.:*(A::BoundOperator, x::AbstractVector) =
    LinearAlgebra.mul!(similar(x, promote_type(eltype(A), eltype(x))), A, x)

"""
    FusedVCycle(cycle, cycles, op, cache)

What [`LatticeMultigrid`](@ref) returns as the left preconditioner of a [`BoundOperator`](@ref):
the V-cycle `cycle` on the hierarchy of the field solver. [`LatticePCG`](@ref) fuses one
symmetric cycle into its iteration; generic Krylov algorithms apply `cycles` V-cycles from
zero through `ldiv!`.
"""
struct FusedVCycle{A}
    cycle::VCycle
    cycles::Int
    op::A
    cache::Base.RefValue{Any}
end
FusedVCycle(cycle::VCycle, cycles::Int, op = nothing) = FusedVCycle(cycle, cycles, op, Ref{Any}(nothing))
(mg::LatticeMultigrid)(A::BoundOperator, p) =
    (FusedVCycle(mg.cycle, something(mg.cycles, 1), A, Ref{Any}(nothing)), LinearAlgebra.I)

function _homog_op(op::CellOperator{N}) where {N}
    dir = ntuple(a -> ntuple(k -> op.dirichlet[a][k] === nothing ? nothing : 0.0, 2), N)
    rob = ntuple(a -> ntuple(k -> (r = op.robin[a][k]; r === nothing ? nothing : (r[1], r[2], 0.0)), 2), N)
    return CellOperator(
        op.dims; periodic = op.periodic, face = faces(op), shift = op.shift,
        mask = op.mask, value = 0.0, dirichlet = dir, robin = rob, name = op.name,
        axes = op.axes, robin_full = op.robin_full, hex = ishex(op),
    )
end
function _homog_inputs(op::CellOperator, ins)
    op.value isa String || return ins
    return Tuple(p for p in ins if String(first(p)) != op.value)
end
function _copy_masked_body!(i, S, P, G)
    y, r, mask = S
    idx = Int(i)
    @inbounds mask[idx] != 0 && (y[idx] = eltype(y)(r[idx]))
    return nothing
end
function LinearAlgebra.ldiv!(y::AbstractVector, P::FusedVCycle{<:BoundOperator}, r::AbstractVector)
    A = P.op
    sv = P.cache[]
    if sv === nothing
        sv = FieldSolver(
            A.exec, _homog_op(A.op);
            linsolve = LatticeMultigrid(; cycle = P.cycle, cycles = P.cycles),
            T = eltype(A), solver_type = A.solver_type, inputs = _homog_inputs(A.op, A.inputs),
        )
        rebuild!(sv)
        P.cache[] = sv
    end
    copyto!(field(sv, "in.f"), r)
    wid = fid(sv, working_key(sv))
    foreach(a -> fill!(a, zero(eltype(a))), sv.bufs[wid])
    lift!(sv)
    solve!(sv; maxiters = P.cycles)
    copyto!(y, field(sv, solution_key(sv)))
    if A.op.mask !== nothing
        mask = _bound_input(A, A.op.mask)
        mask === nothing || launch!(A.exec, Launch(_copy_masked_body!, length(y), (y, r, mask), (), (;), "bound.mask"))
    end
    return y
end
LinearAlgebra.ldiv!(P::FusedVCycle{<:BoundOperator}, r::AbstractVector) =
    LinearAlgebra.ldiv!(r, P, copy(r))

"""
    LatticePCG(; precs = LatticeMultigrid(), maxiters = nothing, reltol = nothing)

Preconditioned conjugate gradients, a LinearSolve algorithm for a symmetric operator: a lattice
field's operator (the owned implicit steppers' `linsolve`, a [`BoundOperator`](@ref)), the
`W = J − M/γ` of an implicit SciML solver on a diffusion-reaction system, or the operator of a
linear system with no time.

On a lattice field's operator with `precs = LatticeMultigrid(; cycle = (ν, ν))` (one cycle per
iteration), the cache is the field's [`FieldSolver`](@ref): CG on device scalars with the
V-cycle from zero fused into each iteration, with no host wait. The stop test is
`‖r‖∞ ≤ reltol * max(‖b‖∞, floor)` (no `abstol`); the true residual is computed every
iteration. On a device the solve returns `ReturnCode.Default` with `iters = 0` (the status
stays in the device's status word); a host executor returns `Success`, `MaxIters` or
`ConvergenceFailure` with the iteration count. The iteration starts from the solver's last
solution (zero at the first solve). The fused solve unrolls `maxiters` into its plan (cap
`FUSED_MAXITERS_CAP`; default `8` when unset).

With `precs = nothing` or another preconditioner on a [`BoundOperator`](@ref), `LatticePCG`
takes the generic CG path. On any other operator it is CG on `−A` (positive definite for a
diffusion-reaction system), preconditioned by `precs`.

`maxiters` and `reltol` left out take the solve's `maxiters` and `reltol` (LinearSolve's
keywords); the owned steppers give 8 and 1e-6. A solve that stops at `maxiters` returns
`ReturnCode.MaxIters`, one that stops otherwise without converging `ReturnCode.ConvergenceFailure`.
`maxiters` is an integer ≥ 1 and `reltol` finite and > 0; any other value is an `ArgumentError`
naming the keyword.
"""
struct LatticePCG{P} <: LinearSolve.AbstractKrylovSubspaceMethod
    precs::P
    maxiters::Union{Nothing, Int}
    reltol::Union{Nothing, Float64}
    function LatticePCG(precs::P, maxiters, reltol) where {P}
        maxiters === nothing || _count(maxiters) || throw(
            ArgumentError(
                string(
                    "`LatticePCG(; maxiters = ", repr(maxiters),
                    ")`: `maxiters` is the most CG iterations per solve, an integer ≥ 1"
                )
            )
        )
        reltol === nothing || _positive(reltol) || throw(
            ArgumentError(
                string(
                    "`LatticePCG(; reltol = ", repr(reltol),
                    ")`: `reltol` is the relative residual a solve stops at, finite and > 0"
                )
            )
        )
        return new{P}(precs, maxiters === nothing ? nothing : Int(maxiters), reltol === nothing ? nothing : Float64(reltol))
    end
end
LatticePCG(; precs = LatticeMultigrid(), maxiters = nothing, reltol = nothing) = LatticePCG(precs, maxiters, reltol)
function Base.show(io::IO, d::LatticePCG)
    kws = Pair{Symbol, Any}[]
    d.precs isa LatticeMultigrid && d.precs == LatticeMultigrid() || push!(kws, :precs => d.precs)
    d.maxiters === nothing || push!(kws, :maxiters => d.maxiters)
    d.reltol === nothing || push!(kws, :reltol => d.reltol)
    return _show_kw(io, "LatticePCG", kws)
end

"""
    LatticeBlockSolve(linsolve = LatticePCG(; maxiters = 2))

The block-diagonal preconditioner of a [`LatticeGMRES`](@ref) solve, a LinearSolve `precs`
function: each field's own operator solved from zero by `linsolve` (a `LatticePCG(…)` or a
`LatticeMultigrid(…)`) on the field's multigrid hierarchy. Applies to coupled steady groups and
to the operators of a problem `LatticePDE.discretize` returned (`W` and `LatticeOperator`).
"""
struct LatticeBlockSolve{L}
    linsolve::L
    engines::Dict{Any, Any}
    lock::ReentrantLock
    function LatticeBlockSolve(linsolve::L, engines, lock) where {L}
        linsolve isa Union{LatticePCG, LatticeMultigrid} || throw(
            ArgumentError(
                string(
                    "`LatticeBlockSolve(", repr(linsolve), ")`: the block preconditioner solves each field with a ",
                    "`LatticePCG(…)` or a `LatticeMultigrid(…)` (for example `LatticeBlockSolve(LatticePCG(; maxiters = 4))`)"
                )
            )
        )
        return new{L}(linsolve, engines, lock)
    end
end
LatticeBlockSolve(linsolve) = LatticeBlockSolve(linsolve, Dict{Any, Any}(), ReentrantLock())
LatticeBlockSolve() = LatticeBlockSolve(LatticePCG(; maxiters = 2))
Base.:(==)(a::LatticeBlockSolve, b::LatticeBlockSolve) = a.linsolve == b.linsolve
Base.show(io::IO, b::LatticeBlockSolve) = b == LatticeBlockSolve() ? print(io, "LatticeBlockSolve()") :
    print(io, "LatticeBlockSolve(", b.linsolve, ")")
Base.:(==)(a::LatticePCG, b::LatticePCG) = a.precs == b.precs && a.maxiters == b.maxiters && a.reltol == b.reltol
Base.hash(a::LatticeBlockSolve, h::UInt) = hash(a.linsolve, hash(:LatticeBlockSolve, h))
Base.hash(a::LatticePCG, h::UInt) = hash((a.precs, a.maxiters, a.reltol), hash(:LatticePCG, h))

"""
    LatticeGMRES(; gmres_restart = 20, maxiters = nothing, reltol = nothing, precs = LatticeBlockSolve())

Restarted flexible GMRES (Krylov.jl's `fgmres!`), a LinearSolve algorithm. It is the coupled
solve of a `QuasiSteady` group whose fields read one another (the time steppers refuse it, their
fields take `LatticePCG` or `LatticeMultigrid`): its operator is the whole Jacobian of the
group's residual (every term of every row, cross terms included: a directional difference of the
residual kernels), its preconditioner `precs`, by default [`LatticeBlockSolve`](@ref)`()`
(block-diagonal: each field's own operator solved by `LatticePCG(; maxiters = 2)` on the
field's multigrid hierarchy). Each solve starts from zero (cold start, matching
`KrylovJL_GMRES()`'s default). Standalone `solve!` honors `cache.abstol` and `cache.reltol`.

`gmres_restart` is the Krylov basis size (an integer from 2 to 64), `maxiters` the most
iterations per solve (an integer ≥ 1; a restart computes the true residual), `reltol` the stop
`‖r‖₂ ≤ atol + reltol ‖b‖₂` (finite and > 0). Left out, `maxiters` and `reltol` take the
solve's values; the owned steppers give 60 and 1e-6. The coupled solve's dot products are block
partials summed in a fixed order (no atomics, no BLAS), so a run is bitwise repeatable, and the
CPU and a GPU give the same bits. Krylov.jl keeps its small least-squares problem on the host,
so on a GPU each dot product waits for its value (about `j + 1` waits at iteration `j` of a
cycle; the one exception to the field solvers' rule of no GPU wait in a step, user ruling
2026-11-01). Any other value is an `ArgumentError` naming the keyword.
"""
struct LatticeGMRES{P} <: LinearSolve.AbstractKrylovSubspaceMethod
    gmres_restart::Int
    maxiters::Union{Nothing, Int}
    reltol::Union{Nothing, Float64}
    precs::P
    function LatticeGMRES(gmres_restart, maxiters, reltol, precs::P) where {P}
        (gmres_restart isa Integer && !(gmres_restart isa Bool) && 2 <= gmres_restart <= 64) || throw(
            ArgumentError(
                string(
                    "`LatticeGMRES(; gmres_restart = ", repr(gmres_restart), ")`: `gmres_restart` is the Krylov basis size, an integer from 2 to 64"
                )
            )
        )
        maxiters === nothing || _count(maxiters) || throw(
            ArgumentError(
                string(
                    "`LatticeGMRES(; maxiters = ", repr(maxiters),
                    ")`: `maxiters` is the most GMRES iterations per solve, an integer ≥ 1"
                )
            )
        )
        reltol === nothing || _positive(reltol) || throw(
            ArgumentError(
                string(
                    "`LatticeGMRES(; reltol = ", repr(reltol),
                    ")`: `reltol` is the relative residual a solve stops at, finite and > 0"
                )
            )
        )
        return new{P}(
            Int(gmres_restart), maxiters === nothing ? nothing : Int(maxiters),
            reltol === nothing ? nothing : Float64(reltol), precs
        )
    end
end
LatticeGMRES(; gmres_restart = 20, maxiters = nothing, reltol = nothing, precs = LatticeBlockSolve()) =
    LatticeGMRES(gmres_restart, maxiters, reltol, precs)
function Base.show(io::IO, g::LatticeGMRES)
    kws = Pair{Symbol, Any}[]
    g.gmres_restart == 20 || push!(kws, :gmres_restart => g.gmres_restart)
    g.maxiters === nothing || push!(kws, :maxiters => g.maxiters)
    g.reltol === nothing || push!(kws, :reltol => g.reltol)
    g.precs isa LatticeBlockSolve && g.precs == LatticeBlockSolve() || push!(kws, :precs => g.precs)
    return _show_kw(io, "LatticeGMRES", kws)
end
Base.:(==)(a::LatticeGMRES, b::LatticeGMRES) =
    a.gmres_restart == b.gmres_restart && a.maxiters == b.maxiters && a.reltol == b.reltol && a.precs == b.precs
Base.hash(a::LatticeGMRES, h::UInt) = hash((a.gmres_restart, a.maxiters, a.reltol, a.precs), hash(:LatticeGMRES, h))

"""
The per-field solver of a `LatticeGMRES`'s block preconditioner (the default `LatticeBlockSolve()`:
two PCG iterations with one V(2, 2) cycle each).
"""
gmres_precond(g::LatticeGMRES) = g.precs isa LatticeBlockSolve ? g.precs.linsolve : LatticePCG(; maxiters = 2)

"""
    owned(alg[, op])

`alg` with the owned steppers' values of an unset `maxiters` and `reltol` (`LatticePCG`: 8 and
1e-6; `LatticeGMRES`: 60 and 1e-6; `LatticeMultigrid`: `reltol = 1e-6`, `warn_tol = 1e-6` or
`1e-3`, and with `op`, `maxiters = jumpy(op) ? 12 : 8`). Other algorithms are returned as given.
"""
owned(a::LatticePCG) = LatticePCG(a.precs, something(a.maxiters, 8), something(a.reltol, 1.0e-6))
owned(a::LatticeGMRES) = LatticeGMRES(a.gmres_restart, something(a.maxiters, 60), something(a.reltol, 1.0e-6), a.precs)
function owned(a::LatticeMultigrid)
    r = something(a.reltol, 1.0e-6)
    w = something(a.warn_tol, a.cycles === nothing ? r : 1.0e-3)
    return LatticeMultigrid(a.cycle, a.cycles, r, a.maxiters, w, a.engines, a.lock)
end
owned(a) = a
owned(a, ::CellOperator) = owned(a)
function owned(a::LatticeMultigrid, op::CellOperator)
    o = owned(a)
    o.cycles === nothing || return o
    m = something(o.maxiters, jumpy(op) ? 12 : 8)
    return LatticeMultigrid(o.cycle, nothing, o.reltol, m, o.warn_tol, o.engines, o.lock)
end
# … and back: the public algorithm of a field solver's resolved one (the owned budgets unset)
public_form(a::FusedPCG) = LatticePCG(
    LatticeMultigrid(; cycle = (a.precond.cycle.nu1, a.precond.cycle.nu2)),
    a.maxiters == 8 ? nothing : a.maxiters, a.reltol == 1.0e-6 ? nothing : a.reltol
)
function public_form(a::LatticeMultigrid)
    r = a.reltol == 1.0e-6 ? nothing : a.reltol
    wdef = a.cycles === nothing ? something(a.reltol, 1.0e-6) : 1.0e-3
    w = a.warn_tol == wdef ? nothing : a.warn_tol
    return LatticeMultigrid(a.cycle, a.cycles, r, a.maxiters, w, a.engines, a.lock)
end
public_form(a) = a

# ---- traits (in the module that owns the types, as LinearSolve requires) -----------------------
LinearSolve.needs_concrete_A(::LatticePCG) = false
LinearSolve.needs_concrete_A(::LatticeGMRES) = false
LinearSolve.needs_concrete_A(::LatticeMultigrid) = false
LinearSolve.default_alias_A(::LatticeMultigrid, ::Any, ::Any) = true
LinearSolve.default_alias_b(::LatticeMultigrid, ::Any, ::Any) = true
# each algorithm reads `cache.reltol` at solve time when its own `reltol` is unset
LinearSolve.update_tolerances_internal!(cache, ::LatticePCG, abstol, reltol) = nothing
LinearSolve.update_tolerances_internal!(cache, ::LatticeGMRES, abstol, reltol) = nothing
LinearSolve.update_tolerances_internal!(cache, ::LatticeMultigrid, abstol, reltol) = nothing

"""
    field_cache(exec, op::CellOperator, linsolve; T = Float32, solver_type = :auto, inputs) -> LinearCache

The linear solve of one field of the owned implicit steppers: `init(LinearProblem(A, b), alg)`
with `A` the [`BoundOperator`](@ref) of `op` and its coefficient `inputs`, `b` the input `"in.f"`
of `inputs`, and `alg` `linsolve` (`:auto`: `LatticePCG()`) with the owned values of an unset
`maxiters` and `reltol` ([`owned`](@ref)). Its cache (`cacheval`) is the field's
[`FieldSolver`](@ref) on the fused path; the owner rebuilds its hierarchy (`rebuild!`), so the
cache is not fresh.
"""
function bound_field_cache(exec, op::CellOperator, linsolve; T = Float32, solver_type = :auto, inputs = ())
    if linsolve === :auto || linsolve isa LatticeMultigrid ||
            (linsolve isa LatticePCG && linsolve.precs isa LatticeMultigrid) ||
            !(linsolve isa LinearSolve.SciMLLinearSolveAlgorithm)
        resolve_inner(op, linsolve)
    end
    alg = owned(linsolve === :auto ? LatticePCG() : linsolve, op)
    i = findfirst(p -> first(p) == "in.f", inputs)
    i === nothing && irerror("a field's linear solve needs its right-hand side `in.f` among the inputs")
    b = last(inputs[i])
    ins = Tuple(inputs[j] for j in eachindex(inputs) if j != i)
    if LinearSolve.needs_concrete_A(alg)
        _check_host_factorization(exec, alg)
        Aop = BoundOperator(exec, op, eltype(b), solver_type, ins)
        M = sparse_operator(Aop)
        c = CommonSolve.init(
            SciMLBase.LinearProblem(M, b), alg;
            alias = SciMLBase.LinearAliasSpecifier(alias_A = true, alias_b = true),
        )
        return c, Aop
    end
    A = BoundOperator(exec, op, T, solver_type, ins)
    c = CommonSolve.init(SciMLBase.LinearProblem(A, b), alg)
    c.isfresh = false
    return c, A
end
field_cache(exec, op::CellOperator, linsolve; T = Float32, solver_type = :auto, inputs = ()) =
    first(bound_field_cache(exec, op, linsolve; T, solver_type, inputs))

function update_linear_operator!(lin::LinearSolve.LinearCache, bop::BoundOperator)
    if LinearSolve.needs_concrete_A(lin.alg)
        sparse_operator!(lin.A, bop)
        lin.isfresh = true
    else
        lin.A = bop
        lin.isfresh = true
        lin.precsisfresh = true
    end
    return nothing
end

function _check_fused_cap(m::Int)
    m <= FUSED_MAXITERS_CAP || throw(
        ArgumentError(
            string(
                "the fused lattice solver unrolls `maxiters` into its solve plan (cap ", FUSED_MAXITERS_CAP,
                "); got `maxiters = ", m, "`: pass a smaller `maxiters`",
            )
        )
    )
    return m
end
function _fused_budget(alg_max, cache_max::Int, n::Int, default_m::Int)
    alg_max !== nothing && return _check_fused_cap(alg_max)
    return cache_max == n ? default_m : _check_fused_cap(cache_max)
end

# ---- the fused path: a lattice field's operator, the `FieldSolver` as the cache -----------------
function _field_solver(alg, A::BoundOperator, b, linsolve, bound)
    return FieldSolver(
        A.exec, A.op; linsolve, T = eltype(A), solver_type = A.solver_type,
        inputs = ("in.f" => b, A.inputs...), bound
    )
end
function LinearSolve.init_cacheval(
        alg::LatticePCG, A::BoundOperator, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
        assumptions::LinearSolve.OperatorAssumptions
    )
    (Pl isa FusedVCycle && Pl.cycle.nu1 == Pl.cycle.nu2 && Pl.cycles == 1) || return nothing
    m = _fused_budget(alg.maxiters, maxiters, length(b), 8)
    pcg = LatticePCG(
        LatticeMultigrid(; cycle = Pl.cycle, cycles = Pl.cycles), m,
        something(alg.reltol, Float64(reltol))
    )
    return _field_solver(alg, A, b, pcg, A)
end
function LinearSolve.init_cacheval(
        alg::LatticeMultigrid, A::BoundOperator, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
        assumptions::LinearSolve.OperatorAssumptions
    )
    default_m = jumpy(A.op) ? 12 : 8
    m = alg.cycles !== nothing ? _check_fused_cap(alg.cycles) :
        _fused_budget(alg.maxiters, maxiters, length(b), default_m)
    r = something(alg.reltol, Float64(reltol))
    w = something(alg.warn_tol, alg.cycles === nothing ? r : 1.0e-3)
    mg = LatticeMultigrid(alg.cycle, alg.cycles, r, m, w, alg.engines, alg.lock)
    return _field_solver(alg, A, b, mg, A)
end
LinearSolve.init_cacheval(
    ::LatticePCG, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
    assumptions::LinearSolve.OperatorAssumptions
) = nothing
LinearSolve.init_cacheval(
    ::LatticeMultigrid, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
    assumptions::LinearSolve.OperatorAssumptions
) = throw(
    ArgumentError(
        string(
            "`LatticeMultigrid` solves a lattice field's operator (a `BoundOperator`); got a ", nameof(typeof(A)),
            ": use `LatticePCG()`, `LatticeGMRES()`, or a Krylov method with `precs = LatticeMultigrid()`"
        )
    )
)

SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::LatticePCG; kwargs...) = _solve!(cache, alg, cache.cacheval)
SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::LatticeMultigrid; kwargs...) = _solve!(cache, alg, cache.cacheval)

# the fused solve: rebind a new right-hand side, the hierarchy after a new `A`, the tolerance;
# then `lift!` and the budgeted solve, as the owned steppers ran them
function _solve!(cache, alg, sv::FieldSolver)
    sv = _fused!(cache, alg, sv)
    retcode, iters = _retcode(sv)
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache; retcode, iters)
end
# (the solve without its `LinearSolution`: the owned steppers' warm steps allocate nothing)
function _fused!(cache, alg, sv::FieldSolver)
    cache.precsisfresh && (cache.precsisfresh = false)   # (the V-cycle is the solver's own hierarchy)
    if cache.isfresh
        if cache.A !== sv.bound                          # a new operator: a new solver
            sv = LinearSolve.init_cacheval(
                alg, cache.A, cache.b, cache.u, cache.Pl, cache.Pr, cache.maxiters,
                cache.abstol, cache.reltol, nothing, LinearSolve.OperatorAssumptions(true)
            )
            cache.cacheval = sv
        end
        rebuild!(sv)
        cache.isfresh = false
    end
    _bind_rhs!(sv, cache.b)
    budget = _budget!(sv, alg, cache)
    lift!(sv)
    solve!(sv; maxiters = budget)
    b = sv.bufs[sv.xid]
    _set_u!(cache, length(b) == 1 ? b[1] : b[sv.slot[sv.xid]])
    return sv
end
# the budget of this solve; a tolerance that differs from the held plans' drops them
function _budget!(sv::FieldSolver, alg::LatticePCG, cache)
    a = sv.alg::FusedPCG
    r = something(alg.reltol, Float64(cache.reltol))
    if r != a.reltol
        sv.alg = FusedPCG(a.precond, a.maxiters, r)
        empty!(sv.plans)
    end
    return _fused_budget(alg.maxiters, cache.maxiters, length(cache.b), 8)
end
function _budget!(sv::FieldSolver, alg::LatticeMultigrid, cache)
    a = sv.alg::LatticeMultigrid
    default_m = jumpy(sv.op) ? 12 : 8
    m = alg.cycles !== nothing ? _check_fused_cap(alg.cycles) :
        _fused_budget(alg.maxiters, cache.maxiters, length(cache.b), default_m)
    r = something(alg.reltol, Float64(cache.reltol))
    w = something(alg.warn_tol, alg.cycles === nothing ? r : 1.0e-3)
    if (a.cycles === nothing && (r != a.reltol || w != a.warn_tol)) ||
            (a.cycles !== nothing && w != a.warn_tol) || m != a.maxiters
        sv.alg = LatticeMultigrid(a.cycle, a.cycles, r, m, w, a.engines, a.lock)
        empty!(sv.plans)
    end
    return m
end
# a new right-hand side array is bound as `"in.f"` (the held plans read the old one)
function _bind_rhs!(sv::FieldSolver, b)
    bs = sv.bufs[sv.rhs]
    bs[1] === b && return nothing
    old = bs[1]
    (typeof(b) == typeof(old) && length(b) == length(old)) || _refuse(
        sv.op, "the right-hand side `b` is a ", typeof(b), " of ", length(b), " values; the solver's is a ",
        typeof(old), " of ", length(old)
    )
    bs[1] = b
    empty!(sv.plans)
    return nothing
end
# the solution into `cache.u`: the solver's own array (no copy) when its type is `u`'s
_set_u!(cache, x) = x isa typeof(cache.u) ? (cache.u === x || (cache.u = x); nothing) : (copyto!(cache.u, x); nothing)
# the return code and the iteration count: read on a host executor (free), else `Default` and 0
function _retcode(sv::FieldSolver)
    fixed = sv.alg isa LatticeMultigrid && sv.alg.cycles !== nothing
    return _retcode_scal(sv.exec, sv.scal, fixed)
end
function _retcode_scal(exec, scal, fixed::Bool)
    host_scalars(exec, scal) || return SciMLBase.ReturnCode.Default, 0
    code = _scal_int(scal, DONE)
    iters = _scal_int(scal, ITER)
    rc = code == 1 || (code == 0 && fixed) ? SciMLBase.ReturnCode.Success :
        code == 0 ? SciMLBase.ReturnCode.MaxIters : SciMLBase.ReturnCode.ConvergenceFailure
    return rc, iters
end
_scal_int(scal::Array, i) = @inbounds Int(scal[i])       # (i ≤ SCALARS = length(scal))

# ---- the generic path: CG on `A` (`BoundOperator`) or `−A` for any other operator -------------
struct NegatedOperator{A}
    a::A
end
Base.size(n::NegatedOperator) = size(n.a)
Base.size(n::NegatedOperator, i) = size(n.a, i)
Base.eltype(n::NegatedOperator) = eltype(n.a)
LinearAlgebra.mul!(y::AbstractVector, n::NegatedOperator, x::AbstractVector) = (LinearAlgebra.mul!(y, n.a, x); y .= .-y; y)
struct NegatedPreconditioner{P}
    p::P
end
LinearAlgebra.ldiv!(y::AbstractVector, n::NegatedPreconditioner, x::AbstractVector) =
    (LinearAlgebra.ldiv!(y, n.p, x); y .= .-y; y)

function _is_cpu_vec(x)
    x isa Array && return true
    hasfield(typeof(x), :backend) && return getfield(x, :backend) isa KA.CPU
    return try
        KA.get_backend(x) isa KA.CPU
    catch
        false
    end
end
function _check_precs_device(P, b)
    (P isa LinearAlgebra.Factorization || P isa Array) || return nothing
    _is_cpu_vec(b) && return nothing
    throw(
        ArgumentError(
            string(
                "the preconditioner (", nameof(typeof(P)), ") lives on the host while the linear problem's vectors ",
                "live on a device: pass a device preconditioner (`precs = LatticeMultigrid()`) or `precs = nothing`"
            )
        )
    )
end

function _solve!(cache, alg::LatticePCG, ::Nothing)
    if cache.precsisfresh
        if !isnothing(alg.precs)
            Pl, _ = alg.precs(cache.A, cache.p)
            cache.Pl = Pl
        end
        cache.precsisfresh = false
    end
    itmax = something(alg.maxiters, cache.maxiters)
    rtol = alg.reltol === nothing ? float(cache.reltol) : alg.reltol
    P = _krylov_precond(cache.Pl)
    _check_precs_device(P, cache.b)
    if cache.A isa BoundOperator
        x, stats = Krylov.cg(cache.A, cache.b; M = P, ldiv = true, atol = float(cache.abstol), rtol, itmax)
    else
        M = P === LinearAlgebra.I ? LinearAlgebra.I : NegatedPreconditioner(P)
        x, stats = Krylov.cg(NegatedOperator(cache.A), .-cache.b; M, ldiv = true, atol = float(cache.abstol), rtol, itmax)
    end
    copyto!(cache.u, x)
    # (not converged: `MaxIters` at the iteration limit, else `ConvergenceFailure`, as LinearSolve's
    # Krylov methods report it)
    retcode = stats.solved ? SciMLBase.ReturnCode.Success :
        stats.niter >= itmax ? SciMLBase.ReturnCode.MaxIters : SciMLBase.ReturnCode.ConvergenceFailure
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache; retcode, iters = stats.niter, stats)
end

# ---- LatticeGMRES: the FGMRES workspace as the cache ---------------------------------------------
function LinearSolve.init_cacheval(
        alg::LatticeGMRES, A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose,
        assumptions::LinearSolve.OperatorAssumptions
    )
    budget = something(alg.maxiters, maxiters)
    m = min(alg.gmres_restart, budget)
    ws = Krylov.FgmresWorkspace(Krylov.KrylovConstructor(b); memory = m)
    sizehint!(ws.stats.residuals, budget + cld(budget, m) + 2)
    return ws
end

# stop a solve whose residual is not finite (it cannot recover)
struct NonFiniteStop end
(::NonFiniteStop)(ws) = (r = ws.stats.residuals; !isempty(r) && !isfinite(@inbounds r[end]))
_krylov_precond(P) = P isa Union{LinearAlgebra.UniformScaling, SciMLOperators.IdentityOperator} ? LinearAlgebra.I : P

function SciMLBase.solve!(cache::LinearSolve.LinearCache, alg::LatticeGMRES; kwargs...)
    budget = _gmres!(cache, alg; owned_atol = false)
    st = cache.cacheval.stats
    retcode = st.solved ? SciMLBase.ReturnCode.Success :
        st.niter >= budget ? SciMLBase.ReturnCode.MaxIters : SciMLBase.ReturnCode.ConvergenceFailure
    return SciMLBase.build_linear_solution(alg, cache.u, nothing, cache; retcode, iters = st.niter)
end
function _gmres!(cache, alg::LatticeGMRES; owned_atol::Bool = false)
    if cache.precsisfresh
        if !isnothing(alg.precs)
            Pl, Pr = alg.precs(cache.A, cache.p)
            cache.Pl = Pl
            cache.Pr = Pr
        end
        cache.precsisfresh = false
    end
    ws = cache.cacheval
    K = eltype(cache.b)
    rtol = something(alg.reltol, Float64(cache.reltol))
    atol = owned_atol ? K(rtol * FLOOR) : K(cache.abstol)
    budget = something(alg.maxiters, cache.maxiters)
    M, N = _krylov_precond(cache.Pl), _krylov_precond(cache.Pr)
    _check_precs_device(M, cache.b)
    _check_precs_device(N, cache.b)
    Krylov.fgmres!(
        ws, cache.A, cache.b; M, N, ldiv = true,
        restart = true, rtol = K(rtol), atol, itmax = budget, history = true, callback = NonFiniteStop()
    )
    _set_u!(cache, ws.x)
    return budget
end

"""
    solve_owned!(cache::LinearSolve.LinearCache)

Internal zero-allocation solve for the owned steppers: runs the solve of `solve!(cache)`
without building a `LinearSolution` (so warm steps allocate nothing). The solution is written
to `cache.u` (and the field solver's solution buffer).
"""
solve_owned!(cache::LinearSolve.LinearCache) = (_solve_owned!(cache, cache.alg, cache.cacheval); nothing)
_solve_owned!(cache, alg::Union{LatticePCG, LatticeMultigrid}, sv::FieldSolver) = (_fused!(cache, alg, sv); nothing)
_solve_owned!(cache, alg::LatticeGMRES, ws) = (_gmres!(cache, alg; owned_atol = true); nothing)
_solve_owned!(cache, alg, cv) = (SciMLBase.solve!(cache); nothing)
