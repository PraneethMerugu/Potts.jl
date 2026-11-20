@testsetup module CoupleOracleSetup
using Potts, Test

module CrPDE
    using Potts: Potts
    using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
    const Interval = Potts.ModelingToolkitBase.DomainSets.Interval
    const t = Potts.t
    const Dt = Differential(t)
    const laplacian = Potts.LatticePDE.laplacian
    const masked = Potts.LatticePDE.masked
    @parameters x y Dc = 0.2 s = 0.5 kd = 0.1 kq = 1.0
    @variables c(..) q(..) w(..) cc(..) [lattice_level = Potts.LatticePDE.Coarse(2)]
    @variables endo(..)::Bool [input = true] isB(..)::Bool [input = true] vol(..) [input = true] cin(..) [input = true]
    @variables cnm(..) [input = true, lattice_input_name = "c"]
    @variables kr(..) [input = true, lattice_input_name = "kind"]
    const DOM = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 24.0), y ∈ Interval(0.0, 20.0)]
    C, Q, W = c(t, x, y), q(t, x, y), w(t, x, y)
    function rich()
        return PDESystem(
            [Dt(C) ~ Dc * laplacian(C) + s * endo(t, x, y) - kd * C + 0.01 * vol(t, x, y), 0 ~ 0.5 * laplacian(Q) - kq * Q + C],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 0.5, Differential(x)(c(t, 24, y)) ~ 0.0, C ~ masked(isB(t, x, y) == 1, 1.0)],
            DOM, [t, x, y], [C, Q, endo(t, x, y), isB(t, x, y), vol(t, x, y)], [Dc, s, kd, kq]; name = :rich
        )
    end
    function first_sys()
        return PDESystem(
            [Dt(C) ~ Dc * laplacian(C) + s * endo(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
            [C, endo(t, x, y)], [Dc, s, kd]; name = :one
        )
    end
    function second_unbound()
        return PDESystem(
            [Dt(W) ~ 0.3 * laplacian(W) - W + 0.7 * cnm(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
            [W, cnm(t, x, y)], Any[]; name = :two
        )
    end
    function second_bound()
        return PDESystem(
            [Dt(W) ~ 0.3 * laplacian(W) - W + 0.7 * cin(t, x, y)], [w(0, x, y) ~ 0.0], DOM, [t, x, y],
            [W, cin(t, x, y)], Any[]; name = :twob
        )
    end
    function coarse_sys()
        return PDESystem(
            [Dt(cc(t, x, y)) ~ Dc * laplacian(cc(t, x, y)) + s * endo(t, x, y) - kd * cc(t, x, y)], [cc(0, x, y) ~ 0.0],
            DOM, [t, x, y], [cc(t, x, y), endo(t, x, y)], [Dc, s, kd]; name = :crs
        )
    end
    function kind_real()
        return PDESystem(
            [Dt(C) ~ Dc * laplacian(C) + s * kr(t, x, y) - kd * C], [c(0, x, y) ~ 0.0], DOM, [t, x, y],
            [C, kr(t, x, y)], [Dc, s, kd]; name = :krs
        )
    end
end

@potts_model CrLife begin
    @kinds medium A B
    @variables V_target(cell) = 40.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy begin
        cells => 4.0 * (volume - V_target)^2
        contacts => 2.0 * (kind != neighbor_kind)
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

function cr_rich_op()
    σ = zeros(Int32, 24, 20)
    σ[3:7, 3:7] .= 1
    σ[12:16, 4:8] .= 2
    σ[6:10, 12:16] .= 3
    σ[16:20, 13:17] .= 4
    return [ownership => σ, kind => [:A, :B, :A, :A]]
end

cr_kop() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :B]])

function cr_run(m, fs, k = 10; op = _cr_default_op(), seed = 5)
    return solve(PottsProblem(m, op, (0, k); field_solver = fs, seed), SequentialCPM(); saveat = 0:2:k)
end

function cr_hand(σ, kind)
    return [
        :endo => [s != 0 && kind[s] == 1 for s in σ], :isB => [s != 0 && kind[s] == 2 for s in σ],
        :vol => [s == 0 ? 0.0 : Float64(count(==(s), σ)) for s in σ],
    ]
end

cr_divided(σ0, σ) = maximum(σ) != maximum(σ0)

function cr_partial(σ, k)
    return count(
        ((I, J),) -> (b = σ[I:(I + k - 1), J:(J + k - 1)]; any(!=(0), b) && any(==(0), b)),
        Iterators.product(1:k:size(σ, 1), 1:k:size(σ, 2))
    )
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
