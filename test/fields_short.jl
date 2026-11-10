# F4-E5 (research/field-compiler/f4/F4-ergonomics.md item 4, user ruling 2026-11-10). Uses the
# definitions of fields_couple.jl (CpPDE, CpHost, cp_*).
#
# E5: a coupled PDESystem may leave out an axis interval; the axis takes the lattice's
# `[0, dims · spacing]`. A given interval must still match. Oracle: Merks (the B form of
# docs/models/src/merks_model.jl, its PDESystem built in a function of the lattice with
# `lattice_domain`) against the same PDESystem with no domain, bitwise.
# Negative control at the E4 commit (~/lpwork/f4E/nc-e5e7.log): "gives no interval for `x`".

module FsMerks
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: Δ, lattice_domain
const t = Potts.t
@parameters x y Dc = 0.75 σc = 5.4e-3 δc = 5.4e-3
@variables c(..) cell(..)::Bool [input = true] ecm(..)::Bool [input = true]
const C = c(t, x, y)
eq() = Differential(t)(C) ~ Dc * Δ(C) + σc * cell(t, x, y) - δc * C * ecm(t, x, y)
# the current form: a function of the lattice
chemoattractant(lattice) = PDESystem([eq()], [c(0, x, y) ~ 0.0], lattice_domain(t, (x, y), lattice), [t, x, y],
    [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc]; name = :merks_field)
# the short form: no domain
const NODOM = PDESystem([eq()], [c(0, x, y) ~ 0.0], [], [t, x, y], [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc];
    name = :merks_field)
end

for (nm, sys) in ((:FsMerksLong, :(FsMerks.chemoattractant(lattice))), (:FsMerksNoDom, :(FsMerks.NODOM)))
    @eval @potts_model $nm begin
        @structural_parameters lattice = (40, 30)
        @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
        @kinds medium endothelial
        @parameters begin
            λ = 50.0
            V₀ = 25.0
            χ = 1000.0
            T = 50.0
        end
        @fields c = $sys (cell => kind == endothelial, ecm => kind == medium)
        @energy cells(endothelial) => λ * (volume - V₀)^2
        @drive copy => -χ * (c[target] - c[source])
        @sweep Metropolis(; temperature = T)
    end
end
fs_op(dims = (40, 30)) = (σ = zeros(Int32, dims...); σ[5:9, 5:9] .= 1; σ[20:24, 12:16] .= 2; σ[30:34, 20:24] .= 3;
    [ownership => σ, kind => fill(:endothelial, 3)])
fs_run(m; op = fs_op(Potts._p(m, :lattice).dims), k = 20) = solve(PottsProblem(m, op, (0, k); seed = 5), SequentialCPM(); saveat = 0:5:k)

@testset "F4-E5: an axis a coupled PDESystem leaves out takes the lattice's interval" begin
    ref = fs_run(FsMerksLong(; name = :m))
    @test maximum(ref.u[end].site.c) > 0 && ref.u[end].σ != ref.u[1].σ
    @test cp_same(fs_run(FsMerksNoDom(; name = :m)), ref)                       # bitwise
    # another lattice size: the function form follows it, the short form needs no change
    @test cp_same(fs_run(FsMerksNoDom(; name = :m, lattice = (40, 36))), fs_run(FsMerksLong(; name = :m, lattice = (40, 36))))
    host = CpHost(; name = :m)
    # a given interval must still match: refused as before
    e = cp_msg(() -> Potts.couple(host, FsMerks.chemoattractant((40, 30));
        inputs = [FsMerks.cell => Potts.kind == 1, FsMerks.ecm => Potts.kind == 0]))
    @test occursin("spans `x ∈ [0, 40]`", e) && occursin("axis 1 of the lattice", e) || (println(e); false)
    # one axis given (matching), the other left out
    one = Potts.ModelingToolkitBase.PDESystem([FsMerks.eq()], [], [FsMerks.x ∈ Potts.LatticePDE.Interval(0.0, 24.0)],
        [Potts.t, FsMerks.x, FsMerks.y], [FsMerks.C, FsMerks.cell(Potts.t, FsMerks.x, FsMerks.y), FsMerks.ecm(Potts.t, FsMerks.x, FsMerks.y)],
        [FsMerks.Dc, FsMerks.σc, FsMerks.δc]; name = :one)
    ins = [FsMerks.cell => Potts.kind == 1, FsMerks.ecm => Potts.kind == 0]
    @test Potts.couple(host, one; inputs = ins) isa Potts.PottsSystem
    bad = Potts.ModelingToolkitBase.PDESystem([FsMerks.eq()], [], [FsMerks.y ∈ Potts.LatticePDE.Interval(0.0, 5.0)],
        [Potts.t, FsMerks.x, FsMerks.y], [FsMerks.C, FsMerks.cell(Potts.t, FsMerks.x, FsMerks.y), FsMerks.ecm(Potts.t, FsMerks.x, FsMerks.y)],
        [FsMerks.Dc, FsMerks.σc, FsMerks.δc]; name = :bad)
    e = cp_msg(() -> Potts.couple(host, bad; inputs = ins))
    @test occursin("spans `y ∈ [0, 5]`", e) || (println(e); false)
end
