# F4-E5, F4-E6, F4-E7 (research/field-compiler/f4/F4-ergonomics.md items 4, 5 and 9, user
# rulings 2026-11-10). Uses the definitions of fields_couple.jl (CpPDE, CpHost, CrHost2, cp_*).
#
# E5: a coupled PDESystem may leave out an axis interval; the axis takes the lattice's
# `[0, dims · spacing]`. A given interval must still match. Oracle: Merks (the B form of
# docs/models/src/merks_model.jl, its PDESystem built in a function of the lattice with
# `lattice_domain`) against the same PDESystem with no domain, bitwise.
# E7: `Potts.is_kind(model, :A, …)` is `kind == code` (one name) or a membership test (several);
# an unknown name is refused. Oracle: bitwise against `Potts.kind == Potts.lookup(model, :A)`
# and `ismember(Potts.kind, (1, 2))`.
# E6: the same Merks field from `LatticePDE.pdesystem` (no lists, no domain), bitwise.
# Negative controls: at the E4 commit with the base system.jl, "gives no interval for `x`" and
# "`is_kind` not defined" (~/lpwork/f4E/nc-e5e7.log); at 4ca38af7 `Potts.Fields` and
# `pdesystem` do not exist (~/lpwork/f4E/nc-e4e6.log).

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
# the short form: no domain (and `pdesystem` works out the lists)
const SHORT = Potts.LatticePDE.pdesystem([eq()], [c(0, x, y) ~ 0.0]; name = :merks_field)
const NODOM = PDESystem([eq()], [c(0, x, y) ~ 0.0], [], [t, x, y], [C, cell(t, x, y), ecm(t, x, y)], [Dc, σc, δc];
    name = :merks_field)
end

# the short vocabulary end to end: `using Potts.Fields`, `pdesystem` with no domain, Potts' own `x, y`
module FsShort
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2 s = 0.5 kd = 0.1
@variables c(..) = 0.0 endo(..)::Bool [input = true]
const C = c(t, x, y)
const SYS = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C]; name = :fields)
end

for (nm, sys) in ((:FsMerksLong, :(FsMerks.chemoattractant(lattice))), (:FsMerksShort, :(FsMerks.SHORT)),
                  (:FsMerksNoDom, :(FsMerks.NODOM)))
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
    @test cp_same(fs_run(FsMerksShort(; name = :m)), ref)
    # another lattice size: the function form follows it, the short form needs no change
    @test cp_same(fs_run(FsMerksShort(; name = :m, lattice = (40, 36))), fs_run(FsMerksLong(; name = :m, lattice = (40, 36))))
    # `Potts.couple` too (the lattice of `CpHost` is 24 × 20)
    host = CpHost(; name = :m)
    @test Potts.couple(host, FsShort.SYS; inputs = [FsShort.endo => Potts.kind == 1]) isa Potts.PottsSystem
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

@testset "F4-E7: Potts.is_kind" begin
    host = CpHost(; name = :m)
    @test isequal(Potts.is_kind(host, :A), Potts.kind == Potts.lookup(host, :A))
    @test isequal(Potts.is_kind(host, :medium), Potts.kind == 0)
    ma = Potts.couple(host, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.is_kind(host, :A)])
    ml = Potts.couple(host, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.kind == Potts.lookup(host, :A)])
    a, l = cp_run(ma, ExplicitEuler()), cp_run(ml, ExplicitEuler())
    @test cp_same(a, l) && maximum(a.u[end].site.c) > 0.1
    # in a mixed vector with a numeric binding (the E1 situation): a test, not a constant
    vol = Potts.at(Potts.B.volume, Potts.B.owner)
    mv = Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.is_kind(host, :A), CpPDE.vol => vol])
    @test count(==(1), Potts.field_inputs(PottsProblem(mv, cp_op(), (0, 1)))[:kind]) == 32   # (the kind numbers, F4-B6 review)
    # several kinds: a membership test, bitwise against `ismember`
    h2 = CrHost2(; name = :m)
    op2 = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :B]])
    mk = Potts.couple(h2, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.is_kind(h2, :A, :B)])
    mi = Potts.couple(h2, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.LatticePDE.ismember(Potts.kind, (1, 2))])
    mA = Potts.couple(h2, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.is_kind(h2, :A)])
    @test count(in((1, 2)), Potts.field_inputs(PottsProblem(mk, op2, (0, 1)))[:kind]) == 32
    @test count(==(1), Potts.field_inputs(PottsProblem(mA, op2, (0, 1)))[:kind]) == 16
    @test cp_same(cp_run(mk, ExplicitEuler(); op = op2), cp_run(mi, ExplicitEuler(); op = op2))
    # the short vocabulary end to end equals the long form (bitwise)
    ms = Potts.couple(host, FsShort.SYS; inputs = [FsShort.endo => Potts.is_kind(host, :A)])
    @test cp_same(cp_run(ms, ExplicitEuler()), l)
    # refusals: an unknown kind name, and no name
    e = cp_msg(() -> Potts.is_kind(host, :B))
    @test occursin("`B` is not a kind of `m`", e) && occursin("`medium`, `A`", e) || (println(e); false)
    @test occursin("give at least one kind name", cp_msg(() -> Potts.is_kind(host)))
end
