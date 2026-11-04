# ForwardDiff Duals through emitted bodies and problems (P5 number types).
module LatticeFieldsForwardDiffExt

using ForwardDiff: Dual, Partials, partials, value
using LatticeFields: Compile

@inline function Compile.lanecast(::Type{T}, d::Dual{G, V, N}) where {T <: AbstractFloat, G, V, N}
    return Dual{G}(Compile.lanecast(T, value(d)),
        Partials(map(x -> Compile.lanecast(T, x), partials(d).values)))
end
Compile.valtype(::Type{<:Dual{G, V}}) where {G, V} = Compile.valtype(V)
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
    return promote_type(E, Compile.withvaltype(P, Compile.valtype(E)))
end

end # module LatticeFieldsForwardDiffExt
