# Shared setup for AUDIT regression tests (docs/design/AUDIT.md, D-041..D-045, F1/F2 field bounds).

@testsetup module AuditSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

# the field models' PDESystems: a kind table, a CPM read and a parameter expression
# that a PDESystem does not hold are bound inputs (`dk => δ[kind]`)
module AuPDE
    using ..FieldPDE
    @variables c(..) u(..) dk(..) [input = true]
    const C, U, DK = c(t, x, y), u(t, x, y), dk(t, x, y)
    const D8 = (16, 16)
    dup() = pdesys([Dt(C) ~ -C / 10, Dt(C) ~ -C / 10], [c(0, x, y) ~ 1.0], (8, 8), [C])
    diffusion() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * laplacian(C)], [c(0, x, y) ~ 0.0], D8, [C], [Dc]))
    nonlinear() = (@parameters Dc = 0.1 k = 0.5; pdesys([Dt(C) ~ Dc * laplacian(C) - k * C^2], [c(0, x, y) ~ 0.0], D8, [C], [Dc, k]))
    bounded() = (@parameters Dc = 1.0; pdesys([Dt(C) ~ Dc * laplacian(C) - DK * C], [c(0, x, y) ~ 0.0], D8, [C, DK], [Dc]))
    kind_diffusion() = pdesys([Dt(C) ~ DK * laplacian(C)], [c(0, x, y) ~ 0.0], D8, [C, DK])
    volume_diffusion() = pdesys([Dt(C) ~ 0.01 * DK * laplacian(C)], [c(0, x, y) ~ 0.0], D8, [C, DK])
    mcs_diffusion() = pdesys([Dt(C) ~ DK * (1 + step_index(t)) * laplacian(C)], [c(0, x, y) ~ 0.0], D8, [C, DK])
    inv_table() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * laplacian(C) - (1 / DK) * C], [c(0, x, y) ~ 0.0], D8, [C, DK], [Dc]))
    function int_div()
        @parameters Dc = 0.25
        Cx = c(t, x)
        return pdesys([Dt(Cx) ~ Dc * laplacian(Cx) - dk(t, x) * Cx], [c(0, x) ~ 0.0], (16,), [Cx, dk(t, x)], [Dc])
    end
    function two(e1, e2)
        @parameters Dc = 0.5 Dx = 0.5
        return pdesys(
            [Dt(C) ~ e1(Dc, Dx), Dt(U) ~ e2(Dc, Dx)],
            [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], (8, 8), [C, U], [Dc, Dx]
        )
    end
    cross_field() = two((Dc, Dx) -> Dc * laplacian(C) - Dx * laplacian(U), (Dc, Dx) -> Dc * laplacian(U))
    cross_linear() = two((Dc, Dx) -> Dc * laplacian(C) - Dx * U, (Dc, Dx) -> Dc * laplacian(U))
    cross_loop() = two((Dc, Dx) -> Dc * laplacian(C) - Dx * laplacian(U), (Dc, Dx) -> Dc * laplacian(U) + Dx * laplacian(C))
    field1() = (@parameters Dc = 0.5; pdesys([Dt(C) ~ Dc * laplacian(C)], [c(0, x, y) ~ 0.0], (8, 8), [C], [Dc]))
    const MCS = step_index(t)
    function gate_rotation()
        @parameters t0 = 1000.0 k = 4.0
        return pdesys(
            [Dt(C) ~ ifelse(MCS >= t0, -10 * C, -k * U), Dt(U) ~ ifelse(MCS >= t0, -10 * U, k * C)],
            [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], (8, 8), [C, U], [t0, k]
        )
    end
    function gate_dominant()
        @parameters t0 = 1000.0
        return pdesys(
            [Dt(C) ~ ifelse(MCS >= t0, -10 * C - U, -10 * C + U), Dt(U) ~ ifelse(MCS >= t0, -10 * U, -5 * U)],
            [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], (8, 8), [C, U], [t0]
        )
    end
end


function audit_blocks()
    σ = zeros(Int32, 20, 20)
    for (k, (i, j)) in enumerate(Iterators.product(1:5:16, 1:5:16))
        σ[i:(i + 2), j:(j + 2)] .= k
    end
    return σ
end

# the substep count of the field phase `j` of a running integrator
audit_n(integ, j = 1) = CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n

function audit_err(f)
    return try
        f(); nothing
    catch e
        e
    end
end

# the field phase of a problem
function audit_phase(prob)
    for e in prob.f.phases.mcs, t in (e isa CorePotts.Repeat ? e.entries : (e,))
        t isa Tuple || continue
        for ph in t
            ph isa CorePotts.FieldPhase && !ph.init && return ph
        end
    end
end

helper_last(v) = v[end]


@potts_model AuditPopCell begin
    @kinds medium A
    @variables q(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @after_mcs q ~ sum(q for c in cells)
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditJacobi begin
    @kinds medium A
    @variables begin
        m(model) = 0.0
        ca(cell) = 0.0
        s(site) = 0.0
        cb(cell) = 10.0
        z(model) = 0.0
        y(cell) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ Pre(m) + 1
        ca ~ Pre(m)
        s ~ Pre(m)
        z ~ sum(Pre(cb) for c in cells)
        cb ~ Pre(cb) + 1
        y ~ m + 1                          # bare: m's new value
    end
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditCycle begin
    @kinds medium A
    @variables begin
        m(model) = 0.0
        n(model) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ n + 1
        n ~ m + 1
    end
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditEnergyPop begin
    @kinds medium A
    @lattice Lattice((20, 20))
    @energy cells => (volume - mean(volume for c in cells))^2 + (volume - 9)^2
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditOdePop begin
    @kinds medium A
    @variables h(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9)^2
    @equations D(h) ~ sum(h for c in cells)
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditKinds begin
    @kinds medium A B
    @parameters λ = 1.0
    @lattice Lattice((20, 20))
    @energy cells => λ * (volume - 9)^2
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditPosition begin
    @kinds medium A
    @variables begin
        px(site) = 0.0
        py(site) = 0.0
        c(site) = 1.0
        g(site) = 0.0
    end
    @lattice Lattice((8, 6); geometry = Hexagonal())
    @energy cells => (volume - 4)^2
    @after_mcs begin
        px ~ position[1]
        py ~ position[2]
        g ~ sum(c[n] for n in Hex(1)(site))
    end
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditDrawBase begin
    @kinds medium A
    @variables x(model) = 0.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @after_mcs x ~ rand()
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditDrawExt begin
    @kinds medium A
    @variables y(model) = 0.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @after_mcs y ~ rand()
    @sweep Metropolis(; temperature = 5.0)
end


# 8x8 parameter-free coupled / gated / duplicate field PDE variants
@potts_model AuditField8 begin
    @structural_parameters mode = :field1
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    if mode === :dup
        @fields AuPDE.dup()
    elseif mode === :cross_field
        @fields AuPDE.cross_field()
    elseif mode === :cross_linear
        @fields AuPDE.cross_linear()
    elseif mode === :cross_loop
        @fields AuPDE.cross_loop()
    elseif mode === :gate_rotation
        @fields AuPDE.gate_rotation()
    elseif mode === :gate_dominant
        @fields AuPDE.gate_dominant()
    else
        @fields AuPDE.field1()
    end
    @sweep Metropolis(; temperature = mode === :dup ? 5.0 : 1.0)
end


# 16x16 linear vs nonlinear diffusion field variants
@potts_model AuditField16 begin
    @structural_parameters mode = :diffusion
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    if mode === :nonlinear
        @fields AuPDE.nonlinear()
    else
        @fields AuPDE.diffusion()
    end
    @sweep Metropolis(; temperature = 5.0)
end


# kind-table-bound 16x16 field variants (reaction rate, kind diffusion, mcs-gated diffusion)
@potts_model AuditTableField begin
    @structural_parameters begin
        mode = :bounded
        d0 = 5.0
        d1 = 0.0
    end
    @kinds medium A
    @parameters δ[kind] = [d0, d1]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    if mode === :kind_diff
        @fields AuPDE.kind_diffusion() (AuPDE.dk => δ[kind])
    elseif mode === :mcs_diff
        @fields AuPDE.mcs_diffusion() (AuPDE.dk => δ[kind])
    else
        @fields AuPDE.bounded() (AuPDE.dk => δ[kind])
    end
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditVolumeDiffusion begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.volume_diffusion() (AuPDE.dk => volume[owner])
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditInvTable begin
    @kinds medium A
    @parameters τ[kind] = [2.0, 0.5]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.inv_table() (AuPDE.dk => τ[kind])
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditIntDivField begin
    @kinds medium A
    @parameters k₀ = 7.0
    @lattice Lattice((16,))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.int_div() (AuPDE.dk => k₀ ÷ 2)
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model AuditClear begin
    @kinds medium A
    @variables begin
        act(site) = 0.0, [clear_on_ownership_change = true]
        tag(site) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @sweep Metropolis(; temperature = 20.0)
end


@potts_model AuditBadOption begin
    @kinds medium A
    @variables act(site) = 0.0, [clear_on_ownership_chnage = true]
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model AuditOnCopyEnergy begin
    @kinds medium A
    @variables begin
        x(cell) = 1.0
        act(site) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy begin
        cells => x * volume + (volume - 9)^2
        sites => 0.5 * act
    end
    @on_copy begin
        x[new] ~ x[new] + 1
        act[target] ~ 3.0
    end
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditOnCopyContact begin
    @kinds medium A
    @variables x(cell) = 1.0
    @lattice Lattice((20, 20))
    @energy begin
        cells => (volume - 9)^2
        contacts => x[owner] + x[neighbor_owner]
    end
    @on_copy x[new] ~ x[new] + 1
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditDerived begin
    @kinds medium A
    @parameters begin
        V₀ = 9.0
        V2 = 2V₀
        pa = 2.0
        pb = 3pa
        J[kind, kind] = [0 2; 2 1]
    end
    @variables x(cell) = V₀
    @lattice Lattice((12, 12))
    @energy begin
        cells => (volume - V2 / 2)^2 + pb * 0
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 5.0)
end


@potts_model AuditOnCopyEvery begin
    @kinds medium A
    @variables act(site) = 0.0
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @on_copy Every(3) act[target] ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model AuditVecBase begin
    @kinds medium A
    @parameters d[1:2] = [1.0, 2.0]
    @variables p(cell)[1:2] = (3.0, 4.0)
    @lattice Lattice((10, 10))
    @energy cells => (volume - 4)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model AuditVecExt begin
    @extend d, p = base = AuditVecBase()
    @kinds medium A
    @variables c(cell)[1:2] = 0.0
    @after_mcs c ~ centroid() .+ d
end


@potts_model AuditTrackers begin
    @kinds medium A
    @variables s(cell) = 0.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 9)^2
    @observed per(cell) ~ surface
    @divide cells(A) when = volume > 1000, s => surface
    @sweep Metropolis(; temperature = 1.0 + 0 * centroid(1))
end


# D-049: conditional sections, model-declared proposals, `major_length` in energies
@potts_model AuditBranches begin
    @structural_parameters begin
        mode = :none
    end
    @kinds medium A
    @parameters begin
        μ = 3.0
    end
    @lattice Lattice((12, 12); boundary = Closed())
    @energy cells(A) => (volume - 9)^2
    if mode == :drive
        @drive copy => μ
    elseif mode == :energy
        @energy cells(A) => μ * volume
    else
        @relations proposal = Moore(1)
    end
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model AuditLength begin
    @structural_parameters begin
        lattice = (16, 16)
        geometry = Square()
    end
    @kinds medium A
    @parameters begin
        λ_L = 2.0
        L = 7.0
    end
    @lattice Lattice(lattice; geometry)
    @energy begin
        cells(A) => (volume - 12)^2 + λ_L * (major_length - L)^2
        contacts => 1.0 * (kind != neighbor_kind)
    end
    @observed len(cell) ~ major_length
    @sweep Metropolis(; temperature = 4.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
