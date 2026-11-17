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
const FAM_INNER = DevicePCG(; reltol = 1e-12, maxiters = 64)
# (name, system, algorithm, the keywords of `solve`: the window `dt`)
const FAM_CASES = [("ExplicitEuler", fam_rate, ExplicitEuler(), (; dt = 0.01)),
    ("BackwardEuler", fam_rate, BackwardEuler(; linsolve = FAM_INNER), (; dt = 0.05)),
    ("CrankNicolson", fam_rate, CrankNicolson(; linsolve = FAM_INNER), (; dt = 0.05)),
    ("BDF2", fam_rate, BDF2(; linsolve = FAM_INNER), (; dt = 0.05)),
    ("QuasiSteady", fam_steady, BackwardEuler(; linsolve = FAM_INNER), (; dt = 0.05)),
    ("FieldGroups", fam_chain, FieldGroups(fam_u => ExplicitEuler(; substeps = 2),
        fam_v => BackwardEuler(; linsolve = FAM_INNER)), (; dt = 0.05)),
    ("ExplicitMap", fam_map, ExplicitMap(), (;))]
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
