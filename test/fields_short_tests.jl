# Shorter coupled PDESystems. Uses the definitions of couple_testsetup.jl (CpPDE, CpHost,
# CrHost2, cp_*).
#
# A coupled PDESystem may leave out an axis interval; the axis takes the lattice's
# `[0, dims · spacing]`. A given interval must still match. Oracle: Merks (the PDESystem
# form of docs/models/src/merks_model.jl, its PDESystem built in a function of the lattice
# with `lattice_domain`) against the same PDESystem with no domain, bitwise.
# `Potts.is_kind(model, :A, …)` is `kind == code` (one name) or a membership test (several);
# an unknown name is refused. Oracle: bitwise against `Potts.kind == Potts.lookup(model,
# :A)` and `ismember(Potts.kind, (1, 2))`. The same Merks field from `LatticePDE.pdesystem`
# (no lists, no domain), bitwise. Negative controls: before this feature, with the base
# system.jl, "gives no interval for `x`" and "`is_kind` not defined"; at 4ca38af7
# `Potts.Fields` and `pdesystem` do not exist.

@testitem "an axis a coupled PDESystem leaves out takes the lattice's interval" setup = [
    CoupleSetup,
] tags = [
    :potts, :fields_short,
] begin
    @testset "an axis a coupled PDESystem leaves out takes the lattice's interval" begin
        ref = fs_run(FsMerksLong(; name = :m))
        @test maximum(ref.u[end].site.c) > 0 && ref.u[end].ownership != ref.u[1].ownership
        # bitwise
        @test cp_same(fs_run(FsMerksNoDom(; name = :m)), ref)
        @test cp_same(fs_run(FsMerksShort(; name = :m)), ref)
        # another lattice size: the function form follows it, the short form needs no change
        @test cp_same(
            fs_run(FsMerksShort(; name = :m, lattice = (40, 36))),
            fs_run(FsMerksLong(; name = :m, lattice = (40, 36)))
        )
        # `Potts.couple` too (the lattice of `CpHost` is 24 × 20)
        host = CpHost(; name = :m)
        @test Potts.couple(
            host, FsShort.SYS; inputs = [
                FsShort.endo =>
                    Potts.kind == 1,
            ]
        ) isa Potts.PottsSystem
        # a given interval must still match: refused as before
        e = cp_msg(
            () -> Potts.couple(
                host, FsMerks.chemoattractant((40, 30));
                inputs = [FsMerks.cell => Potts.kind == 1, FsMerks.ecm => Potts.kind == 0]
            )
        )
        @test occursin("spans `x ∈ [0, 40]`", e) && occursin("axis 1 of the lattice", e) ||
            (println(e); false)
        # one axis given (matching), the other left out
        one = Potts.ModelingToolkitBase.PDESystem(
            [FsMerks.eq()], [], [FsMerks.x ∈ Potts.LatticePDE.Interval(0.0, 24.0)],
            [Potts.t, FsMerks.x, FsMerks.y], [
                FsMerks.C, FsMerks.cell(Potts.t, FsMerks.x, FsMerks.y),
                FsMerks.ecm(Potts.t, FsMerks.x, FsMerks.y),
            ],
            [FsMerks.Dc, FsMerks.σc, FsMerks.δc]; name = :one
        )
        ins = [FsMerks.cell => Potts.kind == 1, FsMerks.ecm => Potts.kind == 0]
        @test Potts.couple(host, one; inputs = ins) isa Potts.PottsSystem
        bad = Potts.ModelingToolkitBase.PDESystem(
            [FsMerks.eq()], [], [FsMerks.y ∈ Potts.LatticePDE.Interval(0.0, 5.0)],
            [Potts.t, FsMerks.x, FsMerks.y], [
                FsMerks.C, FsMerks.cell(Potts.t, FsMerks.x, FsMerks.y),
                FsMerks.ecm(Potts.t, FsMerks.x, FsMerks.y),
            ],
            [FsMerks.Dc, FsMerks.σc, FsMerks.δc]; name = :bad
        )
        e = cp_msg(() -> Potts.couple(host, bad; inputs = ins))
        @test occursin("spans `y ∈ [0, 5]`", e) || (println(e); false)
    end
end

@testitem "Potts.is_kind" setup = [CoupleSetup] tags = [:potts, :fields_short] begin
    @testset "Potts.is_kind" begin
        host = CpHost(; name = :m)
        @test isequal(Potts.is_kind(host, :A), Potts.kind == Potts.lookup(host, :A))
        @test isequal(Potts.is_kind(host, :medium), Potts.kind == 0)
        ma = Potts.couple(
            host, CpPDE.sys2(); inputs = [
                CpPDE.endo =>
                    Potts.is_kind(host, :A),
            ]
        )
        ml = Potts.couple(
            host, CpPDE.sys2(); inputs = [
                CpPDE.endo =>
                    Potts.kind == Potts.lookup(host, :A),
            ]
        )
        a, l = cp_run(ma, ExplicitEuler()), cp_run(ml, ExplicitEuler())
        @test cp_same(a, l) && maximum(a.u[end].site.c) > 0.1
        # in a mixed vector with a numeric binding (the mixed-vector case): a test, not a
        # constant
        vol = Potts.value_at(Potts.B.volume, Potts.B.owner)
        mv = Potts.couple(
            host, CpPDE.sys(); inputs = [
                CpPDE.endo => Potts.is_kind(host, :A), CpPDE.vol => vol,
            ]
        )
        @test count(==(1), Potts.field_inputs(PottsProblem(mv, cp_op(), (0, 1)))[:kind]) ==
            32   # (the kind numbers)
        # several kinds: a membership test, bitwise against `ismember`
        h2 = CrHost2(; name = :m)
        op2 = (
            σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1;
            σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :B]]
        )
        mk = Potts.couple(
            h2, CpPDE.sys2(); inputs = [
                CpPDE.endo =>
                    Potts.is_kind(h2, :A, :B),
            ]
        )
        mi = Potts.couple(
            h2, CpPDE.sys2();
            inputs = [CpPDE.endo => Potts.LatticePDE.ismember(Potts.kind, (1, 2))]
        )
        mA = Potts.couple(h2, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.is_kind(h2, :A)])
        @test count(in((1, 2)), Potts.field_inputs(PottsProblem(mk, op2, (0, 1)))[:kind]) ==
            32
        @test count(==(1), Potts.field_inputs(PottsProblem(mA, op2, (0, 1)))[:kind]) == 16
        @test cp_same(
            cp_run(mk, ExplicitEuler(); op = op2),
            cp_run(mi, ExplicitEuler(); op = op2)
        )
        # the short vocabulary end to end equals the long form (bitwise)
        ms = Potts.couple(
            host, FsShort.SYS; inputs = [
                FsShort.endo =>
                    Potts.is_kind(host, :A),
            ]
        )
        @test cp_same(cp_run(ms, ExplicitEuler()), l)
        # refusals: an unknown kind name, and no name
        e = cp_msg(() -> Potts.is_kind(host, :B))
        @test occursin("`B`", e)
        @test occursin("kind", cp_msg(() -> Potts.is_kind(host)))
    end
end
