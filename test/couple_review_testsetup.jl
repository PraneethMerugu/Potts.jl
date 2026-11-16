@testsetup module CoupleReviewSetup
using Potts, Test

module CrPDE
    using Potts: Potts
    using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
    const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
    const t = Potts.t
    const Dt = Differential(t)
    const Δ = Potts.LatticePDE.Δ
    const masked = Potts.LatticePDE.masked
    @parameters x y Dc = 0.2 s = 0.5 kd = 0.1 kq = 1.0
    @variables c(..) q(..) w(..) cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)]
    @variables endo(..)::Bool [input = true] isB(..)::Bool [input = true] vol(..) [input = true] cin(..) [input = true]
    @variables cnm(..) [input = true, lattice_input_name = "c"]
    @variables kr(..) [input = true, lattice_input_name = "kind"]
    const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 24.0), y ∈ Interval(0.0, 20.0)]
    C, Q, W = c(t, x, y), q(t, x, y), w(t, x, y)
    rich() = PDESystem(
        [Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C + 0.01 * vol(t, x, y), 0 ~ 0.5 * Δ(Q) - kq * Q + C],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 0.5, Differential(x)(c(t, 24, y)) ~ 0.0, C ~ masked(isB(t, x, y) == 1, 1.0)],
        DOM, [t, x, y], [C, Q, endo(t, x, y), isB(t, x, y), vol(t, x, y)], [Dc, s, kd, kq]; name = :rich
    )
    first_sys() = PDESystem(
        [Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
        [C, endo(t, x, y)], [Dc, s, kd]; name = :one
    )
    second_unbound() = PDESystem(
        [Dt(W) ~ 0.3 * Δ(W) - W + 0.7 * cnm(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
        [W, cnm(t, x, y)], Any[]; name = :two
    )
    second_bound() = PDESystem(
        [Dt(W) ~ 0.3 * Δ(W) - W + 0.7 * cin(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
        [W, cin(t, x, y)], Any[]; name = :twob
    )
    coarse_sys() = PDESystem(
        [Dt(cc(t, x, y)) ~ Dc * Δ(cc(t, x, y)) + s * endo(t, x, y) - kd * cc(t, x, y)], [cc(0, x, y) ~ 0.0],
        DOM, [t, x, y], [cc(t, x, y), endo(t, x, y)], [Dc, s, kd]; name = :crs
    )
    kind_real() = PDESystem(
        [Dt(C) ~ Dc * Δ(C) + s * kr(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
        [C, kr(t, x, y)], [Dc, s, kd]; name = :krs
    )
end

@potts_model CrLife begin
    @kinds medium A B
    @variables V_target(cell) = 40.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy begin
        cells => 4.0 * (volume - V_target)^2
        contacts => 2.0 * (kind != kind′)
    end
    @fields CrPDE.rich() (CrPDE.endo => kind == A, CrPDE.isB => kind == B, CrPDE.vol => volume[owner])
    @divide cells(A) when = volume >= 30
    @after_mcs V_target ~ ifelse((mcs >= 2) && (id == 2), 0.0, 40.0)
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model _CrSingleKind begin
    @structural_parameters variant = :two_u
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    if variant === :two_u
        @fields CrPDE.first_sys() (CrPDE.endo => kind == A)
        @fields CrPDE.second_unbound()
    elseif variant === :two_b
        @fields c = CrPDE.first_sys() (CrPDE.endo => kind == A)
        @fields CrPDE.second_bound() (CrPDE.cin => c)
    elseif variant === :coarse
        @fields CrPDE.coarse_sys() (CrPDE.endo => kind == A)
    else
        throw(ArgumentError("unknown Cr variant: $variant"))
    end
    @sweep Metropolis(; temperature = 4.0)
end

CrTwoU(; name = :CrTwoU, kw...) = _CrSingleKind(; variant = :two_u, name, kw...)
CrTwoB(; name = :CrTwoB, kw...) = _CrSingleKind(; variant = :two_b, name, kw...)
CrCrs(; name = :CrCrs, kw...) = _CrSingleKind(; variant = :coarse, name, kw...)

@potts_model CrKindReal begin
    @kinds medium A B
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @fields CrPDE.kind_real()
    @sweep Metropolis(; temperature = 4.0)
end

_cr_default_op() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])

cr_rich_op() = (
    σ = zeros(Int32, 24, 20); σ[3:7, 3:7] .= 1; σ[12:16, 4:8] .= 2; σ[6:10, 12:16] .= 3; σ[16:20, 13:17] .= 4;
    [ownership => σ, kind => [:A, :B, :A, :A]]
)

cr_kop() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :B]])

cr_run(m, fs, k = 10; op = _cr_default_op(), seed = 5) =
    solve(PottsProblem(m, op, (0, k); field_solver = fs, seed), SequentialCPM(); saveat = 0:2:k)

cr_hand(σ, kind) = [
    :endo => [s != 0 && kind[s] == 1 for s in σ], :isB => [s != 0 && kind[s] == 2 for s in σ],
    :vol => [s == 0 ? 0.0 : Float64(count(==(s), σ)) for s in σ],
]

cr_divided(σ0, σ) = maximum(σ) != maximum(σ0)

cr_partial(σ, k) = count(
    ((I, J),) -> (b = σ[I:(I + k - 1), J:(J + k - 1)]; any(!=(0), b) && any(==(0), b)),
    Iterators.product(1:k:size(σ, 1), 1:k:size(σ, 2))
)

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
