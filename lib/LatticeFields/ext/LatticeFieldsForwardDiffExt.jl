# ForwardDiff Duals through emitted bodies and problems (P5 number types).
module LatticeFieldsForwardDiffExt

using ForwardDiff: ForwardDiff, Dual, Partials, partials, value
using LatticeFields: Compile, Problems
using SparseArrays: SparseMatrixCSC, nonzeros, nzrange, rowvals

@inline function Compile.lanecast(::Type{T}, d::Dual{G, V, N}) where {T <: AbstractFloat, G, V, N}
    return Dual{G}(Compile.lanecast(T, value(d)),
        Partials(map(x -> Compile.lanecast(T, x), partials(d).values)))
end
Compile.value_type(::Type{<:Dual{G, V}}) where {G, V} = Compile.value_type(V)
@inline Compile.primal(d::Dual) = Compile.primal(value(d))
function Compile.withvaltype(::Type{Dual{G, W, N}}, ::Type{V}) where {G, W, N, V}
    return Dual{G, Compile.withvaltype(W, V), N}
end
Compile.npartials(::Type{<:Dual{G, V, N}}) where {G, V, N} = N
@inline Compile.dvalue(d::Dual) = value(d)
@inline Compile.dpartial(d::Dual, j) = @inbounds partials(d).values[j]
@inline function Compile.dsetpartial(d::Dual{G, V, N}, j, v) where {G, V, N}
    ps = partials(d).values
    return Dual{G}(value(d), Partials(ntuple(q -> q == j ? convert(V, v) : (@inbounds ps[q]), Val(N))))
end
@inline Compile.dreplace(d::Dual{G, V, N}, v) where {G, V, N} = Dual{G}(convert(V, v), partials(d))
function Compile.promote_dual(::Type{E}, ::Type{P}) where {E, P <: Dual}
    return promote_type(E, Compile.withvaltype(P, Compile.value_type(E)))
end

# The Jacobian-vector product of a lattice right side (F4-07): one evaluation on Duals with one
# partial, `u + ε v`, on the problem's backend (the arrays are kept per Dual type)
function Problems.lattice_jvp!(Jv, j::Problems.LatticeJVP, v, u, p, t)
    D = Dual{typeof(ForwardDiff.Tag(Problems.lattice_jvp!, eltype(u))), eltype(u), 1}
    return lock(j.lock) do
        ud, dud = get!(() -> (similar(u, D), similar(u, D)), j.cache, D)::Tuple{typeof(similar(u, D)), typeof(similar(u, D))}
        ud .= D.(u, Partials.(tuple.(v)))
        Problems.LatticeFunction(j.meta)(dud, ud, p, t)
        Jv .= partials.(dud, 1)
        return Jv
    end
end

# The colored Dual Jacobian (F4-07): per chunk of `K` colors, one evaluation with partial `q`
# seeded on the columns of color `c0 + q`; each stored entry `(i, j)` of the pattern reads row
# `i`'s partial of `j`'s color (no other column of that color is in row `i`)
function Problems.colored_jacobian!(J, jac::Problems.LatticeJacobian, u, p, t)
    K = jac.chunk
    colors, P = jac.colors, jac.pattern
    nc = maximum(colors; init = 0)
    E = eltype(u)
    D = Dual{typeof(ForwardDiff.Tag(Problems.colored_jacobian!, E)), E, K}
    same = J isa SparseMatrixCSC && J.colptr == P.colptr && rowvals(J) == rowvals(P)
    same || fill!(J, zero(eltype(J)))
    rv = rowvals(P)
    lock(jac.lock) do
        ud, dud = get!(() -> (Vector{D}(undef, length(u)), Vector{D}(undef, length(u))), jac.cache, D)::Tuple{Vector{D}, Vector{D}}
        uh = u isa Vector ? u : Array(u)
        f = Problems.LatticeFunction(jac.meta)
        for c0 in 0:K:(nc - 1)
            for i in eachindex(uh)
                q = colors[i] - c0
                ud[i] = D(uh[i], Partials(ntuple(r -> r == q ? one(E) : zero(E), Val(K))))
            end
            f(dud, ud, p, t)
            for col in axes(P, 2)
                q = colors[col] - c0
                1 <= q <= K || continue
                for k in nzrange(P, col)
                    v = partials(dud[rv[k]], q)
                    same ? (nonzeros(J)[k] = v) : (J[rv[k], col] = v)
                end
            end
        end
    end
    return J
end

end # module LatticeFieldsForwardDiffExt
