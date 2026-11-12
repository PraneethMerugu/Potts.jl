# Regression tests for docs/design/AUDIT.md findings (IDs A-xx) and decisions D-041..D-045.
# Uses `selfcheck` from symbolic.jl.

# the field models' PDESystems (F4-B4t): a kind table, a CPM read and a parameter expression
# that a PDESystem does not hold are bound inputs (`dk => δ[kind]`)

@testsetup module AuditSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module AuPDE
using ..FieldPDE
@variables c(..) u(..) dk(..) [input = true]
const C, U, DK = c(t, x, y), u(t, x, y), dk(t, x, y)
const D8 = (16, 16)
dup() = pdesys([Dt(C) ~ -C / 10, Dt(C) ~ -C / 10], [c(0, x, y) ~ 1.0], (8, 8), [C])
diffusion() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * Δ(C)], [c(0, x, y) ~ 0.0], D8, [C], [Dc]))
nonlinear() = (@parameters Dc = 0.1 k = 0.5; pdesys([Dt(C) ~ Dc * Δ(C) - k * C^2], [c(0, x, y) ~ 0.0], D8, [C], [Dc, k]))
bounded() = (@parameters Dc = 1.0; pdesys([Dt(C) ~ Dc * Δ(C) - DK * C], [c(0, x, y) ~ 0.0], D8, [C, DK], [Dc]))
kind_diffusion() = pdesys([Dt(C) ~ DK * Δ(C)], [c(0, x, y) ~ 0.0], D8, [C, DK])
volume_diffusion() = pdesys([Dt(C) ~ 0.01 * DK * Δ(C)], [c(0, x, y) ~ 0.0], D8, [C, DK])
mcs_diffusion() = pdesys([Dt(C) ~ DK * (1 + step_index(t)) * Δ(C)], [c(0, x, y) ~ 0.0], D8, [C, DK])
inv_table() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * Δ(C) - (1 / DK) * C], [c(0, x, y) ~ 0.0], D8, [C, DK], [Dc]))
int_div() = (@parameters Dc = 0.25; Cx = c(t, x);
             pdesys([Dt(Cx) ~ Dc * Δ(Cx) - dk(t, x) * Cx], [c(0, x) ~ 0.0], (16,), [Cx, dk(t, x)], [Dc]))
two(e1, e2) = (@parameters Dc = 0.5 Dx = 0.5; pdesys([Dt(C) ~ e1(Dc, Dx), Dt(U) ~ e2(Dc, Dx)],
    [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], (8, 8), [C, U], [Dc, Dx]))
cross_field() = two((Dc, Dx) -> Dc * Δ(C) - Dx * Δ(U), (Dc, Dx) -> Dc * Δ(U))
cross_linear() = two((Dc, Dx) -> Dc * Δ(C) - Dx * U, (Dc, Dx) -> Dc * Δ(U))
cross_loop() = two((Dc, Dx) -> Dc * Δ(C) - Dx * Δ(U), (Dc, Dx) -> Dc * Δ(U) + Dx * Δ(C))
field1() = (@parameters Dc = 0.5; pdesys([Dt(C) ~ Dc * Δ(C)], [c(0, x, y) ~ 0.0], (8, 8), [C], [Dc]))
const MCS = step_index(t)
gate_rotation() = (@parameters t0 = 1000.0 k = 4.0;
                   pdesys([Dt(C) ~ ifelse(MCS >= t0, -10 * C, -k * U), Dt(U) ~ ifelse(MCS >= t0, -10 * U, k * C)],
                       [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], (8, 8), [C, U], [t0, k]))
gate_dominant() = (@parameters t0 = 1000.0;
                   pdesys([Dt(C) ~ ifelse(MCS >= t0, -10 * C - U, -10 * C + U), Dt(U) ~ ifelse(MCS >= t0, -10 * U, -5 * U)],
                       [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0], (8, 8), [C, U], [t0]))
end


audit_blocks() = (σ = zeros(Int32, 20, 20);
    for (k, (i, j)) in enumerate(Iterators.product(1:5:16, 1:5:16)); σ[i:(i + 2), j:(j + 2)] .= k; end; σ)


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


@potts_model AuditDupODE begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4)^2
    @fields AuPDE.dup()
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


@potts_model AuditDiffusion begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.diffusion()
    @sweep Metropolis(; temperature = 5.0)
end


# the substep count of the field phase `j` of a running integrator
audit_n(integ, j = 1) = CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n

audit_err(f) = try
    f(); nothing
catch e
    e
end


@potts_model AuditNonlinearField begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.nonlinear()
    @sweep Metropolis(; temperature = 5.0)
end


# a kind table in a rate: the bound reads the table (F1 round 6; D-C8 item 6 refused it): the
# automatic count covers `δ[kind] c` (here ρ = Dc·8 + max δ = 13, ⌈13/1.8⌉ = 8; the old bound,
# diffusion only, gave 5), and an explicit count stays a minimum
@potts_model AuditBoundedField begin
    @kinds medium A
    @parameters δ[kind] = [5.0, 0.0]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.bounded() (AuPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 5.0)
end


# a diffusion multiplier read from a kind table varies by site, and the bound reads it (F2
# record (g): F1 refused it, "varies by site"): ρ = max δ · 8 = 16 (h = 1, 2D), ⌈16/1.8⌉ = 9.
# A multiplier that reads a CPM value directly (`volume`) is not bounded: refused without a
# count, with that reason, in the model's words (F1 round 7: `LatticePDE.at(…)`)
@potts_model AuditKindDiffusion begin
    @kinds medium A
    @parameters δ[kind] = [0.1, 2.0]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.kind_diffusion() (AuPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model AuditVolumeDiffusion begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.volume_diffusion() (AuPDE.dk => volume[owner])
    @sweep Metropolis(; temperature = 5.0)
end


# a multiplier that reads `mcs` is not bounded; the refusal prints the model's own words
# (305be9ad: `at(δ, 1 + kind)*(1 + t)`)
@potts_model AuditMcsDiffusion begin
    @kinds medium A
    @parameters δ[kind] = [0.1, 0.2]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.mcs_diffusion() (AuPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 5.0)
end


# a kind table under `1 / …` (F1 round 8): the bound reads every kind's entry, the medium's
# too, and never index 0 (a kind is never negative, so `τ[kind]` reads entry kind + 1): with
# every entry nonzero the automatic count holds (ρ = 0.1·8 + 1/0.5 = 2.8, ⌈2.8/1.8⌉ = 2); a
# zero entry is refused with or without a count, naming the entry and the route (round 7:
# "the substep bound of the field `c` is not finite at the current parameters (Inf)", for
# both); over the evaluation cap an explicit count runs as given (round 7: refused)
@potts_model AuditInvTable begin
    @kinds medium A
    @parameters τ[kind] = [2.0, 0.5]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields AuPDE.inv_table() (AuPDE.dk => τ[kind])
    @sweep Metropolis(; temperature = 5.0)
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


# an integer division of parameters in a rate: the bound cannot see `÷` (D-C8 item 6)
@potts_model AuditIntDivField begin
    @kinds medium A
    @parameters k₀ = 7.0
    @lattice Lattice((16,))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.int_div() (AuPDE.dk => k₀ ÷ 2)
    @sweep Metropolis(; temperature = 1.0)
end


# coupled fields: another field's Laplacian (or value) in a rate is an off-diagonal term of
# the Jacobian. A row on a loop of cross reads that is not diagonally dominant has no bound: refused without a count,
# never silently one substep; a negative diffusion coefficient is refused at any count
@potts_model AuditCrossField begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.cross_field()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model AuditCrossLinear begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.cross_linear()
    @sweep Metropolis(; temperature = 1.0)
end

# a loop: `u` reads `c` back (complex spectrum: Dc λ ± i Dx λ)
@potts_model AuditCrossLoop begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.cross_loop()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model AuditOneField begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.field1()
    @sweep Metropolis(; temperature = 1.0)
end


# an `ifelse` gate on `mcs` is bounded arm by arm: a decaying arm (active after t0) never
# certifies the rotation of the other arm (active before), so the rotation is refused
@potts_model AuditGateRotation begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.gate_rotation()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model AuditGateDominant begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields AuPDE.gate_dominant()
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
        contacts => x[owner] + x[owner′]
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
        contacts => J[kind, kind′]
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

helper_last(v) = v[end]


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
        contacts => 1.0 * (kind != kind′)
    end
    @observed len(cell) ~ major_length
    @sweep Metropolis(; temperature = 4.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "D-041/D-042 update semantics and population folds" setup = [AuditSetup, SymbolicSetup] tags = [:potts, :audit] begin
    @testset "D-041/D-042 update semantics and population folds" begin
        σ = audit_blocks()
        op = [ownership => σ, kind => fill(1, 16)]
        # A-62: a fold in a cell update reads previous values, once per stage
        u = solve(PottsProblem(AuditPopCell(; name = :a), op, (0, 1)), SequentialCPM()).u[end]
        @test all(==(16.0), u.cell.q[1:16])
        # A-63: Pre is the value before the block in every scope; bare reads are new values
        u = solve(PottsProblem(AuditJacobi(; name = :j), op, (0, 1)), SequentialCPM()).u[end]
        @test u.model.m[1] == 1 && u.cell.ca[1] == 0 && all(==(0), u.site.s) && u.model.z[1] == 160
        @test u.cell.cb[1] == 11 && u.cell.y[1] == 2
        # cycles of new-value reads are errors
        @test_throws ArgumentError mtkcompile(AuditCycle(; name = :c))
        # A-60 / D-041: energy folds are per-MCS snapshots; ΔH is exact under that meaning
        p = PottsProblem(AuditEnergyPop(; name = :e), op, (0, 5))
        @test p.u0.model.__snap1[1] == 9
        @test selfcheck(p) < 1e-9
        # A-61: cell ODE locals do not leak into folds (dh/dt = Σ h over 16 cells)
        u = solve(PottsProblem(AuditOdePop(; name = :o), op, (0, 1)), SequentialCPM()).u[end]
        @test all(==(17.0), u.cell.h[1:16])
    end
end

@testitem "A-50/A-51/A-54 operating-point validation" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-50/A-51/A-54 operating-point validation" begin
        σ = audit_blocks()
        sys = AuditKinds(; name = :k)
        @test PottsProblem(sys, [ownership => σ, :kind => fill(:B, 16)], (0, 1)).u0.cell.kind[1] == 2
        @test_throws ArgumentError PottsProblem(sys, [ownership => σ, kind => [1; fill(9, 15)]], (0, 1))
        @test_throws ArgumentError PottsProblem(sys, [ownership => -σ, kind => fill(1, 16)], (0, 1))
        @test_throws ArgumentError PottsProblem(sys, [ownership => σ, kind => fill(1, 16), :lamda => 2.0], (0, 1))
    end
end

@testitem "D-043 position is Cartesian, site is the current site" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "D-043 position is Cartesian, site is the current site" begin
        σ = zeros(Int32, 8, 6); σ[2:3, 2:3] .= 1
        p = PottsProblem(AuditPosition(; name = :p), [ownership => σ, kind => [1]], (0, 1))
        u = solve(p, SequentialCPM()).u[end]
        L = p.lattice
        for I in CartesianIndices(σ)
            e = embed(L, Float64.(Tuple(I)))
            @test (u.site.px[I], u.site.py[I]) == e
        end
        @test all(==(6), u.site.g)                       # periodic hex: six neighbours everywhere
    end
end

@testitem "A-31 one equation per variable" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-31 one equation per variable" begin
        @test_throws ArgumentError mtkcompile(AuditDupODE(; name = :d))
    end
end

@testitem "A-32 draws stay independent under extend" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-32 draws stay independent under extend" begin
        m = Potts.extend(AuditDrawExt(; name = :e), AuditDrawBase(; name = :b))
        σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1
        u = solve(PottsProblem(m, [ownership => σ, kind => [1]], (0, 3)), SequentialCPM()).u[end]
        @test u.model.x[1] != u.model.y[1]
    end
end

@testitem "A-64 field substeps follow the current parameters" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-64 field substeps follow the current parameters" begin
        σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1
        c0 = zeros(16, 16); c0[8, 8] = 100.0
        p = PottsProblem(AuditDiffusion(; name = :d), [ownership => σ, kind => [1], :c => c0], (0, 10); field_solver = ExplicitEuler())
        q = remake(p; p = [:Dc => 5.0])
        fresh = PottsProblem(AuditDiffusion(; name = :d), [ownership => σ, kind => [1], :c => c0, :Dc => 5.0], (0, 10);
            field_solver = ExplicitEuler())
        uq = solve(q, SequentialCPM()).u[end].site.c
        @test uq ≈ solve(fresh, SequentialCPM()).u[end].site.c
        @test maximum(abs, uq) < 100
    end
end

@testitem "a reaction nonlinear in the field has no substep bound: the count is the user's" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a reaction nonlinear in the field has no substep bound: the count is the user's" begin
        σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1
        op = [ownership => σ, kind => [1]]
        err = try
            PottsProblem(AuditNonlinearField(; name = :n), op, (0, 1); field_solver = ExplicitEuler())
        catch e
            e
        end
        @test err isa ArgumentError && occursin("no bound from the parameters", err.msg) && occursin("substeps = n", err.msg)
        @test occursin("^2", err.msg)                                       # the term is named
        # an explicit count is kept (at least the bound of the diffusion, 0.1·8/1.8 → 1), with one
        # warning naming the term the bound does not cover
        # (in the model's words: the term, not the key-prefixed `c: …` of round 0)
        prob = @test_logs (:warn, r"field `c`: 4 substeps.*does not cover `(?!c: )[^`]*c\^2[^`]*`") PottsProblem(AuditNonlinearField(; name = :n),
            op, (0, 1); field_solver = ExplicitEuler(substeps = 4))
        @test audit_n(init(prob, SequentialCPM())) == 4
    end
end

@testitem "a kind table in a rate: the bound reads it; an explicit count is a minimum" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a kind table in a rate: the bound reads it; an explicit count is a minimum" begin
        cb = [iseven(i + j) ? 1.0 : -1.0 for i in 1:16, j in 1:16]
        op = [ownership => zeros(Int32, 16, 16), kind => Symbol[], :c => cb]
        prob = PottsProblem(AuditBoundedField(; name = :b), op, (0, 30); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 8                  # (round 5: refused, "no bound")
        prob1 = @test_logs PottsProblem(AuditBoundedField(; name = :b), op, (0, 30); field_solver = ExplicitEuler(substeps = 1))
        @test audit_n(init(prob1, SequentialCPM())) == 8                 # raised (round 5: 5, the diffusion only)
        c = Array(solve(prob1, SequentialCPM()).u[end].site.c)
        @test all(isfinite, c) && maximum(abs, c) < 1e-3               # stable at 8 (13 · 1/8 ≤ 2)
        # control: a request above the bound is kept
        @test audit_n(init(PottsProblem(AuditBoundedField(; name = :b), op, (0, 1); field_solver = ExplicitEuler(substeps = 9)),
            SequentialCPM())) == 9
    end
end

@testitem "a kind-table diffusion multiplier is bounded; a CPM value read directly is refused" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a kind-table diffusion multiplier is bounded; a CPM value read directly is refused" begin
        σ = zeros(Int32, 16, 16); σ[4:6, 4:6] .= 1
        op = [ownership => σ, kind => [:A]]
        cb = [iseven(i + j) ? 1.0 : 0.0 for i in 1:16, j in 1:16]
        prob = PottsProblem(AuditKindDiffusion(; name = :k), [op; :c => cb], (0, 5); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 9
        c = Array(solve(prob, SequentialCPM()).u[end].site.c)
        @test all(isfinite, c) && maximum(c) <= 1 + 1e-12 && minimum(c) >= -1e-12     # a monotone step at n = 9
        err = audit_err(() -> PottsProblem(AuditVolumeDiffusion(; name = :k), op, (0, 1); field_solver = ExplicitEuler()))
        @test err isa ArgumentError && occursin("varies by site", err.msg) && occursin("volume[owner]", err.msg) &&
              !occursin("LatticePDE.", err.msg) && !occursin("at(volume", err.msg)
        err = audit_err(() -> PottsProblem(AuditMcsDiffusion(; name = :k), op, (0, 1); field_solver = ExplicitEuler()))
        @test err isa ArgumentError && occursin("δ[kind]", err.msg) && occursin("mcs", err.msg) &&
              !occursin("at(δ", err.msg) && !occursin("(1 + t)", err.msg)
    end
end

@testitem "a kind table under `1 / …`: every kind's entry, never index 0; a zero entry is named" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "a kind table under `1 / …`: every kind's entry, never index 0; a zero entry is named" begin
        op = [ownership => zeros(Int32, 16, 16), kind => Symbol[]]
        prob = PottsProblem(AuditInvTable(; name = :v), op, (0, 1); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 2
        for fs in (ExplicitEuler(), ExplicitEuler(substeps = 3)), τ in ([0.0, 0.5], [2.0, 0.0])
            err = audit_err(() -> PottsProblem(AuditInvTable(; name = :v), [op; :τ => τ], (0, 1); field_solver = fs))
            @test err isa ArgumentError && occursin("make it nonzero", err.msg) && occursin("`τ`", err.msg)
            @test occursin(τ[1] == 0 ? "the medium's entry of `τ` (kind 0)" : "the entry of kind 1 of `τ`", err.msg)
            @test !occursin("index 0", err.msg) && !occursin("LatticePDE.", err.msg) && !occursin("__in", err.msg)
        end
        # over the evaluation cap (a 5000-entry table): an explicit count runs as given, and no
        # count is refused with the route
        p3 = PottsProblem(AuditInvTable(; name = :v), op, (0, 1); field_solver = ExplicitEuler(substeps = 3))
        big(prob) = (ph = audit_phase(prob);
                     (ph.substeps, CorePotts.Problems.with_tables(Float64[getproperty(prob.p, n) for n in ph.params],
                          Pair{String, Vector{Float64}}[ph.program.tables[i].key => fill(1.0, 5000) for (i, _) in ph.tables])))
        s3, b3 = big(p3)
        # warned once per group, term and cause; the warning has no error route (F2 record (c):
        # bda31989 printed "with no count, give `PottsProblem` `field_solver = …`" inside it)
        logs, n3 = Test.collect_test_logs(() -> s3(b3))
        @test n3 == 3 && length(logs) == 1 && occursin(r"3 substeps.*does not cover.*4096", string(logs[1].message))
        @test !occursin("with no count", string(logs[1].message))
        # … raised by the bound over the terms it sees (round 9: Dc = 4.5 with 3 stayed at 3 past
        # the cap, against 22 with the 2-entry table; now 4.5·8/1.8 = 20; the group has warned)
        p45 = PottsProblem(AuditInvTable(; name = :v), [op; :Dc => 4.5], (0, 1); field_solver = ExplicitEuler(substeps = 3))
        @test audit_n(init(p45, SequentialCPM())) == 22                                    # control: 2 entries
        s45, b45 = big(p45)
        @test (@test_logs s45(b45)) == 20
        s0, b0 = big(prob)
        err = audit_err(() -> s0(b0))
        @test err isa ArgumentError && occursin("4096", err.msg) && occursin("substeps = n", err.msg)
    end
end

@testitem "÷ of parameters in a field rate has no bound: refused without a count" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "÷ of parameters in a field rate has no bound: refused without a count" begin
        op = [ownership => zeros(Int32, 16), kind => Symbol[], :c => [isodd(i) ? 1.0 : -1.0 for i in 1:16]]
        err = audit_err(() -> PottsProblem(AuditIntDivField(; name = :b), op, (0, 30); field_solver = ExplicitEuler()))
        # the term is printed in the model's words (F1, PO06: on f9a77dd3 the message printed the
        # key prefix and the internal `Potts._intdiv(k₀, 2)`)
        @test err isa ArgumentError && occursin("no bound from the parameters", err.msg) && occursin("k₀ ÷ 2", err.msg) &&
              !occursin("_intdiv", err.msg) && !occursin("`c: ", err.msg)
        # with a count: kept as a minimum over the diffusion bound (0.25·4 / 1.8 → 1)
        prob = @test_logs (:warn, r"does not cover") PottsProblem(AuditIntDivField(; name = :b), op, (0, 30);
            field_solver = ExplicitEuler(substeps = 3))
        @test audit_n(init(prob, SequentialCPM())) == 3
    end
end

@testitem "an ifelse gate is bounded arm by arm: a gated rotation is refused" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "an ifelse gate is bounded arm by arm: a gated rotation is refused" begin
        cb = [iseven(i + j) ? 1.0 : -1.0 for i in 1:8, j in 1:8]
        op = [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb, :u => copy(cb)]
        err = audit_err(() -> PottsProblem(AuditGateRotation(; name = :r), op, (0, 30); field_solver = ExplicitEuler()))
        @test err isa ArgumentError && occursin("coupled rate", err.msg)
        # control: both arms diagonally dominant: accepted with the worst arm's bound, ceil(11 / 1.8)
        prob = PottsProblem(AuditGateDominant(; name = :d), op, (0, 30); field_solver = ExplicitEuler())
        @test audit_n(init(prob, SequentialCPM())) == 7
        @test maximum(abs, Array(solve(prob, SequentialCPM()).u[end].site.c)) < 1e-3
    end
end

@testitem "coupled fields: no automatic count (never silently one substep); negative diffusion refused" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "coupled fields: no automatic count (never silently one substep); negative diffusion refused" begin
        cb = [iseven(i + j) ? 1.0 : -1.0 for i in 1:8, j in 1:8]
        op = [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb, :u => copy(cb)]
        # control: the field alone gets its bound, ceil(0.5·8 / 1.8) = 3, and decays
        one = PottsProblem(AuditOneField(; name = :o), [ownership => zeros(Int32, 8, 8), kind => Symbol[], :c => cb], (0, 30);
            field_solver = ExplicitEuler())
        @test audit_n(init(one, SequentialCPM())) == 3
        @test maximum(abs, Array(solve(one, SequentialCPM()).u[end].site.c)) < 1e-3
        # one way (`u` does not read `c`): block triangular, so the Gershgorin bound with no dominance
        # test (F3-22 review r1, D-C7a item 2 amended; base 9afaac05: refused), ceil((0.5·8 + 0.5·8) / 1.8)
        # and ceil((0.5·8 + 0.5) / 1.8)
        for (M, n) in ((AuditCrossField, 5), (AuditCrossLinear, 3))
            prob = @test_logs min_level = Base.CoreLogging.Warn PottsProblem(M(; name = :x), op, (0, 30); field_solver = ExplicitEuler())
            @test audit_n(init(prob, SequentialCPM())) == n
            @test maximum(abs, Array(solve(prob, SequentialCPM()).u[end].site.c)) < 1e-3
        end
        # a loop: refused without a count
        err = audit_err(() -> PottsProblem(AuditCrossLoop(; name = :x), op, (0, 30); field_solver = ExplicitEuler()))
        @test err isa ArgumentError && occursin("coupled rates of `c`, `u`", err.msg) && occursin("substeps = n", err.msg) &&
              occursin("`field_solver = BackwardEuler()`", err.msg)
        # an explicit count: at least the Gershgorin bound of the coupled row, ceil((0.5·8 + 0.5·8) / 1.8) = 5
        prob = @test_logs (:warn, r"coupled rates of `c`") PottsProblem(AuditCrossLoop(; name = :x), op, (0, 30);
            field_solver = ExplicitEuler(substeps = 1))
        @test audit_n(init(prob, SequentialCPM())) == 5
        c = Array(solve(prob, SequentialCPM()).u[end].site.c)
        @test all(isfinite, c) && maximum(abs, c) < 1e-3
        # negative diffusion: refused with and without a count, also after a parameter change
        for fs in (ExplicitEuler(), ExplicitEuler(substeps = 20))
            err = audit_err(() -> PottsProblem(AuditOneField(; name = :o), [ownership => zeros(Int32, 8, 8), kind => Symbol[],
                :c => cb, :Dc => -0.1], (0, 1); field_solver = fs))
            @test err isa ArgumentError && occursin("negative", err.msg) && occursin("`c`", err.msg)
            @test occursin("coefficient ≥ 0", err.msg)                  # the route (round 0: none)
        end
        # after a parameter change: refused by the write itself, which changes nothing (F2-08a)
        @test audit_err(() -> remake(one; p = [:Dc => -0.1])) isa ArgumentError
        integ = init(one, SequentialCPM())
        p0 = integ.p
        @test audit_err(() -> setp(integ, :Dc)(integ, -0.1)) isa ArgumentError
        @test integ.p === p0
        step!(integ)
        @test integ.t == 1
    end
end

@testitem "A-34 clear_on_ownership_change; unknown variable options" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-34 clear_on_ownership_change; unknown variable options" begin
        σ = zeros(Int32, 16, 16); σ[4:7, 4:7] .= 1; σ[10:13, 10:13] .= 2
        p = PottsProblem(AuditClear(; name = :c), [ownership => σ, kind => [1, 1], :act => 5.0, :tag => 5.0], (0, 5))
        u = solve(p, SequentialCPM()).u[end]
        changed = u.σ .!= σ
        @test any(changed)
        @test all(iszero, u.site.act[changed]) && count(==(5), u.site.act) > 0   # changed back: also cleared
        @test all(==(5), u.site.tag)
        @test_throws ArgumentError AuditBadOption(; name = :b)
    end
end

@testitem "A-30 declared names cannot shadow built-ins or each other" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-30 declared names cannot shadow built-ins or each other" begin
        expand(body) = Potts._potts_model(:X, body, @__MODULE__)
        base = quote
            @lattice Lattice((8, 8))
            @sweep Metropolis(; temperature = 1.0)
        end
        @test_throws ArgumentError expand(quote @kinds medium A; @parameters distance = 3.0 end)
        @test_throws ArgumentError expand(quote @kinds medium A; @parameters D = 3.0 end)
        @test_throws ArgumentError expand(quote @kinds medium source end)
        @test_throws ArgumentError expand(quote @kinds medium A; @variables target(cell) = 1.0 end)
        @test_throws ArgumentError expand(quote @kinds medium a; @parameters a = 1.0 end)
        @test_throws ArgumentError expand(quote @kinds medium A A end)
        @test_throws ArgumentError expand(quote @kinds medium A; @variables x(cell) = 1.0; @observed x ~ 2 end)
        @test expand(quote @kinds medium A; @parameters λ = 1.0; @variables x(cell) = 1.0 end) isa Expr
    end
end

@testitem "A-67 energies see on-copy writes (D-045)" setup = [AuditSetup, SymbolicSetup] tags = [:potts, :audit] begin
    @testset "A-67 energies see on-copy writes (D-045)" begin
        σ = audit_blocks()
        p = PottsProblem(AuditOnCopyEnergy(; name = :o), [ownership => σ, kind => fill(1, 16)], (0, 3))
        @test selfcheck(p) < 1e-9
        @test_throws ArgumentError mtkcompile(AuditOnCopyContact(; name = :c))
    end
end

@testitem "group 2: derived parameters, reinit!, cadence and length checks" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "group 2: derived parameters, reinit!, cadence and length checks" begin
        σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1
        op = [ownership => σ, kind => [1]]
        p = PottsProblem(AuditDerived(; name = :d), op, (0, 2))
        @test p.p.V2 == 18 && p.u0.cell.x[1] == 9                             # A-39
        @test PottsProblem(AuditDerived(; name = :d, V₀ = 4.0), op, (0, 2)).p.V2 == 8
        q = remake(p; p = [:pa => 10.0])
        @test (q.p.pa, q.p.pb) == (10, 30)                                     # pb follows pa (MTK)
        # pb is computed, so read-only (D-F2-1; before: a given value was kept)
        @test_throws ArgumentError remake(p; p = [:pa => 10.0, :pb => 1.0])
        integ = init(p, SequentialCPM())
        setp(integ, :pa)(integ, 7.0)
        @test integ.p.pb == 21
        @test_throws ArgumentError setp(integ, :J)(integ, [0 2; 5 1])       # A-53: contact tables stay symmetric
        @test_throws ArgumentError PottsProblem(AuditDerived(; name = :d), [op; :J => 2.0], (0, 2))   # A-57
        # A-15: reinit! validates shapes, takes symbolic maps, reruns callback initialization
        σ2 = zeros(Int32, 12, 12); σ2[6:8, 6:8] .= 1
        reinit!(integ, [ownership => σ2, kind => [1]])
        @test integ.u.σ == σ2
        @test_throws Exception reinit!(integ, PottsProblem(AuditDerived(; name = :d),
            [ownership => (s = zeros(Int32, 12, 12); s[1:2, 1:2] .= 1; s[5:6, 5:6] .= 2; s), kind => [1, 1]], (0, 2); capacity = 5).u0)
        # A-36: Every on on-copy updates; Every(0)
        @test_throws ArgumentError mtkcompile(AuditOnCopyEvery(; name = :e))
        @test_throws ArgumentError Potts.Every(0)
    end
end

@testitem "A-43/A-44 vector lengths; a frozen medium" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-43/A-44 vector lengths; a frozen medium" begin
        @test_throws ArgumentError Potts.vector_parameter(:d, 1:2, [5.0, 6.0, 7.0])
        @test_throws ArgumentError Potts._potts_model(:X, quote @kinds medium[frozen] A end, @__MODULE__)
    end
end

@testitem "group 3: extend vectors and centroid, Julia indexing, tuple defaults" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "group 3: extend vectors and centroid, Julia indexing, tuple defaults" begin
        s = AuditVecExt(; name = :v)                                         # A-37, A-38
        σ = zeros(Int32, 10, 10); σ[2:3, 2:3] .= 1
        u = solve(PottsProblem(s, [ownership => σ, kind => [1]], (0, 1)), SequentialCPM()).u[end]
        @test u.cell.p_1[1] == 3 && u.cell.p_2[1] == 4                       # A-42
        @test u.cell.c_2[1] ≈ Potts._centroid_axis(Float64, u.cell, PottsProblem(s, [ownership => σ, kind => [1]], (0, 1)).lattice, 1, 2) + 2
        ex = Potts.rewrite(:(v[end] + sum(i * j for i in 1:2, j in 1:3)))    # A-40
        @test eval(:(let v = [1, 5]; $ex; end)) == 5 + 18
    end
end

@testitem "A-35 trackers read only by observed/division/temperature" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "A-35 trackers read only by observed/division/temperature" begin
        σ = zeros(Int32, 16, 16); σ[2:4, 2:4] .= 1
        p = PottsProblem(AuditTrackers(; name = :t), [ownership => σ, kind => [1]], (0, 2))
        sol = solve(p, SequentialCPM())
        @test sol[:per][end][1] == sol.u[end].cell.surface[1]
    end
end

@testitem "D-014/D-016: binary sums, fingerprints over all code" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "D-014/D-016: binary sums, fingerprints over all code" begin
        # a wide energy: 40 terms lower to binary `+`, allocation-free
        ex = Potts.lower(sum(Potts.B.volume^k for k in 1:40) |> Potts._unwrap,
            Potts._cell_env(Float32, :c, Dict{Any, Symbol}()))
        @test ex.args[1] === (+) && length(ex.args) == 3
        # models differing only in an update block have different fingerprints
        σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1
        a = PottsProblem(AuditPopCell(; name = :a), [ownership => σ, kind => [1]], (0, 1))
        b = PottsProblem(AuditJacobi(; name = :j), [ownership => σ, kind => [1]], (0, 1))
        @test a.f.fingerprint != b.f.fingerprint
        @test PottsProblem(AuditPopCell(; name = :a), [ownership => σ, kind => [1]], (0, 1)).f.fingerprint == a.f.fingerprint
        @test haskey(Potts.generated_code(AuditPopCell(; name = :a)), :phases)
    end
end

@testitem "D-049: conditional sections and model proposals" setup = [AuditSetup] tags = [:potts, :audit] begin
    @testset "D-049: conditional sections and model proposals" begin
        σ = zeros(Int32, 12, 12); σ[4:6, 4:6] .= 1
        prob(mode) = PottsProblem(AuditBranches(; name = :b, mode), [ownership => σ, kind => [1]], (0, 1))
        grow = CorePotts.Proposal(CorePotts.linear_index(Lattice((12, 12)), (7, 5)), CorePotts.linear_index(Lattice((12, 12)), (6, 5)),
            (7, 5), 1, Int32(0), Int32(1))
        dH(p) = p.f.delta_H(p.u0, p.p, grow, (; lattice = p.lattice, contact = p.contact, p.relations...))
        @test dH(prob(:drive)) - dH(prob(:none)) ≈ 3.0
        @test dH(prob(:energy)) - dH(prob(:none)) ≈ 3.0
        # the else branch declared the proposal; the others keep the default, and algorithms
        # override the model's
        @test prob(:none).proposal isa Moore && prob(:drive).proposal isa VonNeumann
        @test CorePotts._proposal(SequentialCPM(), prob(:none)) isa Moore
        @test CorePotts._proposal(SequentialCPM(; proposal = VonNeumann(1)), prob(:none)) isa VonNeumann
        @test_throws Exception @eval @potts_model AuditBadBranch begin
            @structural_parameters begin
                flag = true
            end
            if flag
                @parameters begin
                    q = 1.0
                end
            end
        end
    end
end

@testitem "D-049: major_length in energies (square, hex, 3D)" setup = [AuditSetup, SymbolicSetup] tags = [:potts, :audit] begin
    @testset "D-049: major_length in energies (square, hex, 3D)" begin
        for (lattice, geometry, σ) in (((16, 16), Square(), (s = zeros(Int32, 16, 16); s[3:8, 4:5] .= 1; s[10:12, 9:12] .= 2; s)),
                                       ((16, 16), Hexagonal(), (s = zeros(Int32, 16, 16); s[3:8, 4:5] .= 1; s[10:12, 9:12] .= 2; s)),
                                       ((8, 8, 8), Square(), (s = zeros(Int32, 8, 8, 8); s[2:5, 2:3, 2:3] .= 1; s)))
            n = maximum(σ)
            p = PottsProblem(AuditLength(; name = :l, lattice, geometry), [ownership => σ, kind => fill(1, n)], (0, 20))
            # ΔH equals the difference of the brute-force energy along a trajectory
            worst = 0.0
            for (u, prop) in proposal_states(p; mcs = (0, 10, 20), n = 150)
                a = deepcopy(u); a.σ[prop.target] = prop.new
                p.f.commit!(a, p.p, prop, (; lattice = p.lattice, contact = p.contact, p.relations...))
                worst = max(worst, abs(energy_change(p, u, prop) - (total_energy(p, a) - total_energy(p, u) + Potts._killing_credit(p, u, prop, a))))
            end
            @test worst < 1e-8
            # the built-in is the CorePotts shape descriptor
            sol = solve(p, SequentialCPM())
            u = sol.u[end]
            @test sol[:len][end] ≈ [CorePotts.shape(u.cell, p.lattice, c).major_length for c in 1:n]
        end
    end
end
