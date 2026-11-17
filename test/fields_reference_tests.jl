# R4: naive site-by-site Symbolics.substitute reference evaluator for compiled field
# programs (PDE steps, BCs, coupled cell-field feedback) on tiny lattices against
# symbolic math, including negative controls. Self-contained (uses Potts.Symbolics).

@testsetup module FieldsReferenceSetup
using Potts, Test
using Potts: Symbolics
using Potts.Symbolics: substitute, unwrap, value
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module RefPDE
using ..FieldPDE
@variables c(..)
const C = c(t, x, y)
const ShiftT = Shift(t, 1)

function diff_decay_periodic(dims; Dc = 0.12, kc = 0.25)
    @parameters D = Dc k = kc
    return pdesys([Dt(C) ~ D * laplacian(C) - k * C], [c(0, x, y) ~ 0.0], dims, [C], [D, k])
end

function diff_decay_dirichlet(dims, spacing; Dc = 0.08, kc = 0.15)
    @parameters D = Dc k = kc
    nx = dims[1] * spacing
    return pdesys(
        [Dt(C) ~ D * laplacian(C) - k * C],
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, c(t, nx, y) ~ 0.0],
        dims, [C], [D, k]; spacing)
end

function map_step(dims)
    return pdesys([ShiftT(C) ~ 0.8 * C + 0.05 * laplacian(C) + 0.1], [c(0, x, y) ~ 0.0], dims, [C])
end

function coupled_source(dims)
    @parameters D = 0.1 alpha = 0.4 k = 0.2
    @variables mem(t, x, y) [input = true]
    return pdesys(
        [Dt(C) ~ D * laplacian(C) - k * C + alpha * mem],
        [c(0, x, y) ~ 0.0],
        dims, [C, mem], [D, alpha, k])
end
end

@potts_model RefPerModel begin
    @kinds medium A
    @lattice Lattice((6, 6); boundary = Periodic())
    @energy cells => (volume - 4.0)^2
    @fields RefPDE.diff_decay_periodic((6, 6))
    @sweep Metropolis(; temperature = 1.0e-12)
end

@potts_model RefDirModel begin
    @kinds medium A
    @lattice Lattice((6, 5); boundary = Closed(), spacing = (0.5, 0.5))
    @energy cells => (volume - 4.0)^2
    @fields RefPDE.diff_decay_dirichlet((6, 5), 0.5)
    @sweep Metropolis(; temperature = 1.0e-12)
end

@potts_model RefMapModel begin
    @kinds medium A
    @lattice Lattice((6, 6); boundary = Periodic())
    @energy cells => (volume - 4.0)^2
    @fields RefPDE.map_step((6, 6))
    @sweep Metropolis(; temperature = 1.0e-12)
end

@potts_model RefCoupledModel begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells => (volume - 4.0)^2
    @fields c = RefPDE.coupled_source((6, 6)) (mem => owner > 0)
    @after_mcs y ~ integral(c)
    @schedule sweep, fields, after_mcs
    @sweep Metropolis(; temperature = 1.0e-12)
end

# Hand discrete 5-point Laplacian at (i, j) with cell-centered BCs:
# - :periodic wraps modulo axis length
# - :neumann0 mirrors the cell value (zero-flux face)
# - (g_low, g_high)::Tuple{Real, Real} uses half-cell Dirichlet ghost 2*g - u[i, j]
function ref_axis_neighbors(u, i, j, axis, n, bc)
    idx(k) = axis == 1 ? u[k, j] : u[i, k]
    c0 = u[i, j]
    k = axis == 1 ? i : j
    cm = if k > 1
        idx(k - 1)
    elseif bc === :periodic
        idx(n)
    elseif bc === :neumann0
        c0
    else
        2.0 * Float64(bc[1]) - c0
    end
    cp = if k < n
        idx(k + 1)
    elseif bc === :periodic
        idx(1)
    elseif bc === :neumann0
        c0
    else
        2.0 * Float64(bc[2]) - c0
    end
    return cm, cp
end

function ref_laplacian(u, i, j, hx, hy, bc_x, bc_y)
    nx, ny = size(u)
    xm, xp = ref_axis_neighbors(u, i, j, 1, nx, bc_x)
    ym, yp = ref_axis_neighbors(u, i, j, 2, ny, bc_y)
    return (xm - 2.0 * u[i, j] + xp) / hx^2 + (ym - 2.0 * u[i, j] + yp) / hy^2
end

# Naive site-by-site Symbolics.substitute evaluator for one Euler substep or map step.
function ref_eval_site(rhs, C_sym, lap_sym, u, i, j, hx, hy, bc_x, bc_y, extra_subs)
    lap_val = ref_laplacian(u, i, j, hx, hy, bc_x, bc_y)
    subs = Dict{Any, Any}(unwrap(C_sym) => u[i, j], unwrap(lap_sym) => lap_val)
    for (k, v) in extra_subs(i, j)
        subs[unwrap(k)] = v
    end
    return Float64(value(substitute(unwrap(rhs), subs)))
end

function ref_step_euler(rhs, C_sym, lap_sym, u0; nsteps, dt, hx = 1.0, hy = 1.0,
        bc_x = :periodic, bc_y = :periodic, extra_subs = (i, j) -> ())
    u = copy(u0)
    unext = similar(u)
    hdt = dt / nsteps
    nx, ny = size(u)
    for _ in 1:nsteps
        for j in 1:ny, i in 1:nx
            rate = ref_eval_site(rhs, C_sym, lap_sym, u, i, j, hx, hy, bc_x, bc_y, extra_subs)
            unext[i, j] = u[i, j] + hdt * rate
        end
        u .= unext
    end
    return u
end

function ref_step_map(rhs, C_sym, lap_sym, u0; nsteps, hx = 1.0, hy = 1.0,
        bc_x = :periodic, bc_y = :periodic, extra_subs = (i, j) -> ())
    u = copy(u0)
    unext = similar(u)
    nx, ny = size(u)
    for _ in 1:nsteps
        for j in 1:ny, i in 1:nx
            unext[i, j] = ref_eval_site(rhs, C_sym, lap_sym, u, i, j, hx, hy, bc_x, bc_y, extra_subs)
        end
        u .= unext
    end
    return u
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "R4: Symbolics.substitute reference evaluator matches compiled field steps and BCs" setup = [FieldsReferenceSetup] tags = [:potts, :fields] begin
    @testset "R4: Symbolics.substitute reference evaluator matches compiled field steps and BCs" begin
        Symbolics.@variables C_sym lap_sym D_sym k_sym
        rhs_pde = D_sym * lap_sym - k_sym * C_sym

        # 1. Periodic 2D diffusion-decay with random initial field
        σ_per = zeros(Int32, 6, 6)
        σ_per[2:3, 2:3] .= 1
        c0_per = [0.2 + 0.1 * sin(0.7 * i + 1.1 * j) for i in 1:6, j in 1:6]
        prob_per = PottsProblem(RefPerModel(; name = :rp), [ownership => σ_per, kind => [:A], :c => c0_per], (0, 2);
            field_solver = ExplicitEuler(; substeps = 4), seed = 1)
        got_per = solve(prob_per, SequentialCPM()).u[end].site.c
        ref_per = ref_step_euler(rhs_pde, C_sym, lap_sym, c0_per; nsteps = 8, dt = 2.0,
            bc_x = :periodic, bc_y = :periodic,
            extra_subs = (i, j) -> (D_sym => 0.12, k_sym => 0.25))
        @test maximum(abs, got_per .- ref_per) < 1e-13

        # Negative controls on periodic case: wrong BC and wrong parameter
        bad_bc = ref_step_euler(rhs_pde, C_sym, lap_sym, c0_per; nsteps = 8, dt = 2.0,
            bc_x = :neumann0, bc_y = :neumann0,
            extra_subs = (i, j) -> (D_sym => 0.12, k_sym => 0.25))
        @test maximum(abs, got_per .- bad_bc) > 1e-3
        bad_param = ref_step_euler(rhs_pde, C_sym, lap_sym, c0_per; nsteps = 8, dt = 2.0,
            bc_x = :periodic, bc_y = :periodic,
            extra_subs = (i, j) -> (D_sym => 0.20, k_sym => 0.25))
        @test maximum(abs, got_per .- bad_param) > 1e-2

        # 2. Dirichlet on x (low = 1.0, high = 0.0) + Neumann 0 on y, non-unit spacing = 0.5
        σ_dir = zeros(Int32, 6, 5)
        σ_dir[2:3, 2:3] .= 1
        c0_dir = [0.1 * cos(0.5 * i - 0.8 * j) for i in 1:6, j in 1:5]
        prob_dir = PottsProblem(RefDirModel(; name = :rd), [ownership => σ_dir, kind => [:A], :c => c0_dir], (0, 2);
            field_solver = ExplicitEuler(; substeps = 4), seed = 1)
        got_dir = solve(prob_dir, SequentialCPM()).u[end].site.c
        ref_dir = ref_step_euler(rhs_pde, C_sym, lap_sym, c0_dir; nsteps = 8, dt = 2.0,
            hx = 0.5, hy = 0.5, bc_x = (1.0, 0.0), bc_y = :neumann0,
            extra_subs = (i, j) -> (D_sym => 0.08, k_sym => 0.15))
        @test maximum(abs, got_dir .- ref_dir) < 1e-13

        # Negative control: homogeneous Neumann on x instead of Dirichlet
        bad_dir = ref_step_euler(rhs_pde, C_sym, lap_sym, c0_dir; nsteps = 8, dt = 2.0,
            hx = 0.5, hy = 0.5, bc_x = :neumann0, bc_y = :neumann0,
            extra_subs = (i, j) -> (D_sym => 0.08, k_sym => 0.15))
        @test maximum(abs, got_dir .- bad_dir) > 1e-2

        # 3. Discrete map step
        rhs_map = 0.8 * C_sym + 0.05 * lap_sym + 0.1
        prob_map = PottsProblem(RefMapModel(; name = :rm), [ownership => σ_per, kind => [:A], :c => c0_per], (0, 3);
            field_solver = ExplicitMap(), seed = 1)
        got_map = solve(prob_map, SequentialCPM()).u[end].site.c
        ref_map = ref_step_map(rhs_map, C_sym, lap_sym, c0_per; nsteps = 3,
            bc_x = :periodic, bc_y = :periodic)
        @test maximum(abs, got_map .- ref_map) < 1e-13
    end
end

@testitem "R4: Symbolics.substitute reference evaluator verifies coupled cell-field feedback" setup = [FieldsReferenceSetup] tags = [:potts, :fields] begin
    @testset "R4: Symbolics.substitute reference evaluator verifies coupled cell-field feedback" begin
        Symbolics.@variables C_sym lap_sym D_sym alpha_sym k_sym mem_sym
        rhs_coupled = D_sym * lap_sym - k_sym * C_sym + alpha_sym * mem_sym

        σ = zeros(Int32, 6, 6)
        σ[2:3, 2:3] .= 1
        c0 = zeros(6, 6)
        prob = PottsProblem(RefCoupledModel(; name = :rc), [ownership => σ, kind => [:A], :c => c0], (0, 3);
            field_solver = ExplicitEuler(; substeps = 4), seed = 1)
        sol = solve(prob, SequentialCPM())
        got_c = sol.u[end].site.c
        got_y = sol.u[end].cell.y[1]

        # With T = 1e-12 and σ already at target volume 4, σ stays fixed; cell reads integral(c)
        # from the previous MCS step (2 MCS = 8 substeps, dt = 2.0).
        @test sol.u[end].σ == σ
        ref_c = ref_step_euler(rhs_coupled, C_sym, lap_sym, c0; nsteps = 12, dt = 3.0,
            bc_x = :neumann0, bc_y = :neumann0,
            extra_subs = (i, j) -> (D_sym => 0.1, k_sym => 0.2, alpha_sym => 0.4,
                mem_sym => (σ[i, j] > 0 ? 1.0 : 0.0)))
        ref_c_prev = ref_step_euler(rhs_coupled, C_sym, lap_sym, c0; nsteps = 8, dt = 2.0,
            bc_x = :neumann0, bc_y = :neumann0,
            extra_subs = (i, j) -> (D_sym => 0.1, k_sym => 0.2, alpha_sym => 0.4,
                mem_sym => (σ[i, j] > 0 ? 1.0 : 0.0)))
        ref_y = sum(ref_c_prev[i, j] for j in 1:6, i in 1:6 if σ[i, j] == 1)
        @test maximum(abs, got_c .- ref_c) < 1e-13
        @test got_y ≈ ref_y rtol = 1e-13

        # Negative control: drop the cell-membership source term
        no_src = ref_step_euler(rhs_coupled, C_sym, lap_sym, c0; nsteps = 12, dt = 3.0,
            bc_x = :neumann0, bc_y = :neumann0,
            extra_subs = (i, j) -> (D_sym => 0.1, k_sym => 0.2, alpha_sym => 0.4, mem_sym => 0.0))
        @test maximum(abs, got_c .- no_src) > 1e-1
    end
end
