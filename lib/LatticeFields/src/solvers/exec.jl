# The executor protocol on a KernelAbstractions backend: `Exec` runs the solvers (the
# production executor; tests also use host and device stand-ins). Site launches go through
# `Exec.launch!` (the host executor on the CPU, the guarded device wrapper elsewhere);
# workgroup launches through `Schedule.host_workgroups!` or `Schedule.workgroups!`.

alloc(b::KA.Backend, ::Type{T}, n) where {T} = fill!(KA.allocate(b, T, max(n, 1)), zero(T))
fetch(b::KA.Backend, A) = Exec.ishost(b) ? copy(A) : (KA.synchronize(b); Array(A))

# capability, not policy (P5 C2-1): a Float64 solver group runs where the hardware has
# Float64 (ROCm, CUDA, the host), so `solver_T = :auto` keeps its Float64 path on ROCm
Schedule.supports(b::KA.Backend, ::Type{S}) where {S} = Exec.supports(b, S)

_solver_site!(i, body::F, S, P, G) where {F} = (body(oftype(G.n, i), S, P, G); nothing)

function launch!(b::KA.Backend, l::Launch)
    if l.wg == 0
        Exec.launch!(b, _solver_site!, l.n, (l.body, l.S, l.P, l.G))
    elseif Exec.ishost(b)
        Schedule.host_workgroups!(l.body, l.n, l.wg, l.phases, l.lds, l.S, l.P, l.G)
    else
        Schedule.workgroups!(b, l.body, l.n, l.wg, l.phases, eltype(l.lds), l.ldslen, l.S, l.P, l.G)
    end
    return nothing
end
