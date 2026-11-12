# Definitions of families_tests.jl that other test files use (moved here by TS1b).
using SciMLBase: SciMLBase, remake
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P
using OrdinaryDiffEqBDF: FBDF
using KernelAbstractions: KernelAbstractions as KA

@parameters fDc = 0.2 fk = 1.0
@parameters fdx [lattice_spacing = 1]
@variables fu(..) fv(..) fN(..)
fam_u, fam_v, fam_N = fu(t, x, y), fv(t, x, y), fN(t, x, y)
fam_dom = [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
fam_faces = [fu(t, 0, y) ~ 1.0, fu(t, x, 0) ~ fu(t, x, 1)]
fam_rate = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u + x * y], [fu(0, x, y) ~ x; fam_faces], fam_dom, [t, x, y],
    [fam_u], [fDc, fk]; name = :famr)
fam_steady = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u + fam_v, 0 ~ 0.1 * Δ(fam_v) - fam_v + fam_u],
    [fu(0, x, y) ~ x; fam_faces; fv(t, x, 0) ~ fv(t, x, 1)], fam_dom, [t, x, y], [fam_u, fam_v], [fDc, fk]; name = :fams)
fam_chain = PDESystem([D(fam_u) ~ fDc * Δ(fam_u) - fk * fam_u, D(fam_v) ~ 0.5 * Δ(fam_v) - fam_v + fam_u],
    [fu(0, x, y) ~ x; fv(0, x, y) ~ y; fam_faces; fv(t, x, 0) ~ fv(t, x, 1)], fam_dom, [t, x, y], [fam_u, fam_v], [fDc, fk]; name = :famc)
fam_map = PDESystem([Shift(t, 1)(fam_N) ~ (fN(t, x + fdx, y) + fN(t, x - fdx, y)) / 2], [fN(0, x, y) ~ x],
    [t ∈ Interval(0.0, 3.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [fam_N], [fdx]; name = :famm)
const FAM_INNER = DevicePCG(; rtol = 1e-12, budget = 64)
const FAM_CASES = [("ExplicitEuler", fam_rate, ExplicitEuler(; dt = 0.01)),
    ("BackwardEuler", fam_rate, BackwardEuler(; dt = 0.05, inner = FAM_INNER)),
    ("CrankNicolson", fam_rate, CrankNicolson(; dt = 0.05, inner = FAM_INNER)),
    ("BDF2", fam_rate, BDF2(; dt = 0.05, inner = FAM_INNER)),
    ("QuasiSteady", fam_steady, BackwardEuler(; dt = 0.05, inner = FAM_INNER)),
    ("FieldGroups", fam_chain, FieldGroups(fam_u => ExplicitEuler(; dt = 0.05, substeps = 2),
        fam_v => BackwardEuler(; dt = 0.05, inner = FAM_INNER))),
    ("ExplicitMap", fam_map, ExplicitMap())]
fam_digest(u) = (repr(sum(u)), repr(u[1]), repr(u[end]))
# the base's owned solves (`problem = :owned` at 3ed05c3b, ~/lpwork/f4b1/pins.jl on the PC):
# `(sum, first, last)` of the final state, printed exactly
const FAM_PINS = Dict{String, NTuple{3, String}}(
    "ExplicitEuler" => ("40.083782220091095", "0.8464843838279211", "0.7229504422497087"),
    "BackwardEuler" => ("39.58397959572821", "0.8208813249422733", "0.7369070815165802"),
    "CrankNicolson" => ("39.98320671764459", "0.8429541456996491", "0.7266335083499864"),
    "BDF2" => ("39.98795542318008", "0.8509726321471082", "0.7289081501820648"),
    "QuasiSteady" => ("83.97825902430269", "0.8510960053524306", "0.6964964497644828"),
    "FieldGroups" => ("70.23816581681162", "0.8442336499283419", "0.5305929833215783"),
    "ExplicitMap" => ("24.0", "0.1015625", "0.2734375"))
fam_disc() = LatticeDiscretization(Grid((8, 8)); T = Float64)
fmsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end

# a backend that is not the problem's (SX-12): an array type whose backend is a stand-in GPU
struct FamFakeGPU <: KA.GPU end
struct FamDevVec <: AbstractVector{Float64}
    v::Vector{Float64}
end
Base.size(a::FamDevVec) = size(a.v)
Base.getindex(a::FamDevVec, i::Int) = a.v[i]
KA.get_backend(::FamDevVec) = FamFakeGPU()
