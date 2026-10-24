# F3-08 (F3 design §3.7): `BackwardEuler` in front end A. A field group with
# `field_solver = BackwardEuler()` steps through the same runtime as front end B
# (`Problems.GroupRuntime`, the implicit cache), bound to the state's site arrays: with σ frozen
# A equals B (`Potts.fields` → `discretize`) bitwise; a moving σ enters the next window's solve
# through the CPM's own input array; a parameter write rebinds in place (`reset!`: the hierarchy
# is rebuilt); a solve that fails ends the run. Base (437a84ef, ~/lpwork/f3b3-nc-a-base.log):
# `BackwardEuler` is not defined in Potts (every testset errors). Negative control (mutation,
# ~/lpwork/f3b3-nc-a-reset2.log): `install_launches!` without `reset!` keeps the stale hierarchy
# and `jac:` arrays after a parameter write, and FiStill's run differs from a fresh problem's
# (FiMix passes: its mask reads `e`, so it rebuilds every window anyway, f3b3-nc-a-reset.log).
using Potts: CorePotts
using StableRNGs: StableRNG
const FIP = Potts.LatticeFields.Problems
const FiRC = Potts.SciMLBase.ReturnCode
using Potts.LatticeFields.IR: fieldid

@potts_model FiMix begin
    @kinds medium A[frozen]
    @parameters begin
        Dc = 0.4
        kd = 0.3
        s = 0.5
        v = 1.5
    end
    @variables begin
        c(field) = 0.0
        e(field) = 0.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(c) ~ Dc * Δ(c) - kd * c + s * (kind == A)
        D(e) ~ 0.02 + 0.01 * x
    end
    @bcs c ~ masked(e >= 0.5, v)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiRobinP begin
    @kinds medium A[frozen]
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - 0.3 * c + 0.1 * x
    @bcs 1.0 * c(t, x, 0) - Differential(y)(c(t, x, 0)) ~ 0.5
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiRobinN begin
    @kinds medium A[frozen]
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - 0.3 * c + 0.1 * x
    @bcs 1.0 * c(t, x, 0) + Differential(y)(c(t, x, 0)) ~ 0.5
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiFieldFace begin
    @kinds medium A[frozen]
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ DivKGrad(:harmonic)(1 + 0.05 * x * y, c) - 0.3 * c
    @bcs c(t, 0, y) ~ 1.0 + 0.1 * y
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiMaskField begin
    @kinds medium A[frozen]
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - 0.3 * c
    @bcs c ~ masked(kind == A, 1 + 0.1 * x)
    @sweep Metropolis(; temperature = 1.0)
end
# a moving σ: the decay reads the kind (a field row, rebuilt every window)
@potts_model FiMoving begin
    @kinds medium A
    @parameters begin
        Dc = 0.5
        kd = 0.4
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 12.0)^2
    @equations D(c) ~ Dc * Δ(c) + 0.5 * (kind == A) - kd * c * (kind == medium)
    @sweep Metropolis(; temperature = 8.0)
    @schedule sweep, fields
end
# a growth term the operator does not see, `+ g c³`: with large data the defect correction
# diverges and the run ends
@potts_model FiBlowup begin
    @kinds medium A[frozen]
    @parameters g = 1.0
    @variables c(field) = 1000.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.1 * Δ(c) + g * c^3
    @sweep Metropolis(; temperature = 1.0)
end

# a field row whose operator kernels read only the coordinates and parameters: nothing moves,
# so only a parameter write rebuilds its hierarchy and `jac:` arrays
@potts_model FiStill begin
    @kinds medium A[frozen]
    @parameters begin
        Dc = 0.4
        kd = 0.3
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ DivKGrad(:harmonic)(Dc * (1 + 0.05 * x), c) - kd * c + 0.1 * x
    @sweep Metropolis(; temperature = 1.0)
end

# a periodic field with no cells (the messages)
@potts_model FiPeriodic begin
    @kinds medium A
    @parameters Dc = 1.0
    @variables c(field) = 0.0
    @lattice Lattice((16, 8); boundary = Periodic(), spacing = (2.0, 2.0))
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 1.0)
end

fi_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
fi_kin(dims) = (K = zeros(Int32, dims...); K[4:6, 3:5] .= 1; K)
# A's field `c` after each of `k` MCS
function fi_runA(M, op, k; field_solver = BackwardEuler(), kw...)
    integ = init(PottsProblem(M(; name = :f), op, (0, k); field_solver, kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:k], integ
end
# B's (`Potts.fields` → `discretize`) at the same MCS, from the same start
function fi_runB(M, dims, k; u0, inputs = [:kind => fi_kin(dims)], alg = BackwardEuler(; dt = 1.0))
    bp = Potts.LatticePDE.discretize(Potts.fields(M(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(dims); T = Float64, problem = :owned);
        u0, tspan = (0, k), inputs)
    return Potts.LatticePDE.solve(bp, alg; saveat = 1.0)[:c][2:end]
end
fi_warm(integ) = (step!(integ); @allocated step!(integ))   # (a function barrier)

@testset "F3-08: BackwardEuler in A equals B bitwise (σ frozen)" begin
    dims, k = (12, 10), 8
    # diffusion, decay, a kind source and a mask that moves (it follows `e`)
    a, integ = fi_runA(FiMix, fi_op(dims), k)
    b = fi_runB(FiMix, dims, k; u0 = [:c => zeros(dims), :e => zeros(dims)])
    @test a == b
    @test integ.retcode == FiRC.Default || integ.retcode == FiRC.Success
    rt = CorePotts._runtime(getfield(integ.ctx, :__fields1))
    @test rt.cache isa FIP.ImplicitCache && rt.cache.moving && rt.cache.newton == 1
    @test integ.stats.fields.solves == k && integ.stats.fields.budget == 0
    # the mask moved: it covers part of the box at the last window's start (`e` one MCS before
    # the end), where `c` holds `v`, and covered nothing at MCS 2
    xs = [i - 0.5 for i in 1:12, j in 1:10]
    eprev = Array(current_state(integ).site.e) .- (0.02 .+ 0.01 .* xs)
    m = eprev .>= 0.5 + 1e-9
    @test any(m) && !all(m) && all(a[end][m] .== 1.5) && !any(a[2] .== 1.5)
    # the implicit result is not the explicit one
    ae, _ = fi_runA(FiMix, fi_op(dims), k; field_solver = ExplicitEuler())
    @test maximum(abs, ae[end] .- a[end]) > 1e-3
    @test fi_warm(integ) == 0
end

@testset "F3-08: the solver capabilities in A (F3-05), equal to B bitwise" begin
    dims, k = (12, 10), 3
    for M in (FiRobinP, FiFieldFace, FiMaskField)
        a, integ = fi_runA(M, fi_op(dims), k)
        @test a == fi_runB(M, dims, k; u0 = [:c => zeros(dims)], inputs = M === FiMaskField ? [:kind => fi_kin(dims)] : [])
        @test integ.stats.fields.solves == k
    end
    # opposite signs: the negative part in the residual, with its bound `w |d⁻|` (S1): two
    # substeps and `newton = 8` by default
    a, integ = fi_runA(FiRobinN, fi_op(dims), k)
    @test a == fi_runB(FiRobinN, dims, k; u0 = [:c => zeros(dims)], inputs = [])
    c = CorePotts._runtime(getfield(integ.ctx, :__fields1)).cache
    @test c.newton == 8 && c.seen && substep_counts(integ) == [2] && integ.stats.fields.newton_budget == 0
    # the mask value field: each masked site holds its own value
    a, _ = fi_runA(FiMaskField, fi_op(dims), 1)
    m = fi_kin(dims) .== 1
    @test a[1][m] == [1 + 0.1 * (i - 0.5) for i in 1:12, j in 1:10][m]
end

@testset "F3-08: a moving σ enters the next window's solve through the CPM's array" begin
    dims = (16, 16)
    σ = zeros(Int32, dims...); σ[4:7, 4:7] .= 1; σ[10:13, 9:12] .= 2
    integ = init(PottsProblem(FiMoving(; name = :f), [ownership => σ, kind => [:A, :A]], (0, 20);
        field_solver = BackwardEuler(), seed = 3), SequentialCPM(); save_start = false)
    foreach(_ -> step!(integ), 1:3)
    st = current_state(integ)
    rt = CorePotts._runtime(getfield(integ.ctx, :__fields1))
    # the operator's input is the CPM's own array (no copy)
    prog = rt.program
    kin = only(f.key for f in prog.fields if f.role === :input)
    @test pointer(rt.store.bufs[fieldid(prog, kin)][1]) == pointer(getfield(integ.state.site, Symbol(kin)))
    c3, σ3 = copy(Array(st.site.c)), copy(Array(st.σ))
    step!(integ)
    st = current_state(integ)
    @test Array(st.σ) != σ3                                   # σ moved in MCS 4's sweep
    K4 = Int32.(Array(st.σ) .!= 0)
    want = fi_runB(FiMoving, dims, 1; u0 = [:c => c3], inputs = [:kind => K4])[1]
    @test Array(st.site.c) == want                            # the window read the moved σ
    @test Array(st.site.c) != fi_runB(FiMoving, dims, 1; u0 = [:c => c3], inputs = [:kind => Int32.(σ3 .!= 0)])[1]
    @test fi_warm(integ) == 0
end

@testset "F3-08: a parameter write rebinds in place; a failure ends the run" begin
    dims = (12, 10)
    prob = PottsProblem(FiMix(; name = :f), fi_op(dims), (0, 6); field_solver = BackwardEuler())
    integ = init(prob, SequentialCPM(); save_start = false)
    foreach(_ -> step!(integ), 1:2)
    rt = CorePotts._runtime(getfield(integ.ctx, :__fields1))
    sv = rt.cache.rows[findfirst(r -> r.key == "c", collect(rt.cache.rows))].solver
    st = current_state(integ)
    c2, e2 = copy(Array(st.site.c)), copy(Array(st.site.e))
    integ.ps[:Dc] = 0.8
    @test rt.cache.rows[findfirst(r -> r.key == "c", collect(rt.cache.rows))].solver === sv   # no new solver
    foreach(_ -> step!(integ), 1:2)
    fresh, _ = fi_runA(FiMix, [fi_op(dims); :c => c2; :e => e2; :Dc => 0.8], 2)
    @test Array(current_state(integ).site.c) == fresh[end]
    # the same where nothing moves (the hierarchy is rebuilt only because of the write)
    integ = init(PottsProblem(FiStill(; name = :f), fi_op(dims), (0, 6); field_solver = BackwardEuler()), SequentialCPM();
        save_start = false)
    foreach(_ -> step!(integ), 1:2)
    rt = CorePotts._runtime(getfield(integ.ctx, :__fields1))
    @test !rt.cache.moving
    c2 = copy(Array(current_state(integ).site.c))
    integ.ps[:Dc] = 0.8
    integ.ps[:kd] = 0.6
    foreach(_ -> step!(integ), 1:2)
    fresh, _ = fi_runA(FiStill, [fi_op(dims); :c => c2; :Dc => 0.8; :kd => 0.6], 2)
    @test Array(current_state(integ).site.c) == fresh[end]
    # a growth term the operator does not see diverges: `ConvergenceFailure`, the warning names
    # the field, the MCS and the route
    s = @test_logs (:warn, r"field `c`: the solve failed in the field step of MCS \d.*`ReturnCode.ConvergenceFailure`.*substeps = n") match_mode = :any solve(
        PottsProblem(FiBlowup(; name = :f), fi_op((8, 6)), (0, 5); field_solver = BackwardEuler()), SequentialCPM())
    @test s.retcode == FiRC.ConvergenceFailure
end

@testset "F3-08: a Merks-like model with BackwardEuler runs 20 MCS (CPU)" begin
    p = PottsProblem(MERKS, [ownership => merks_state(), kind => [1, 1]], (0, 20); field_solver = BackwardEuler(lower = 0.0))
    s = solve(p, SequentialCPM())
    @test s.retcode == FiRC.Success && all(isfinite, s.u[end].site.c) && minimum(s.u[end].site.c) >= 0
    @test maximum(s.u[end].site.c) > 0
end

@testset "F3-08: messages name BackwardEuler as the route, and it works" begin
    op = [ownership => zeros(Int32, 16, 8), kind => Symbol[], :c => zeros(16, 8)]
    mk(; kw...) = PottsProblem(FiPeriodic(; name = :f), op, (0, 1); kw...)
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    m = e(() -> mk(; field_solver = DevicePCG()))
    @test occursin("give it to one, `field_solver = BackwardEuler(; inner = DevicePCG())`", m)
    @test solve(mk(; field_solver = BackwardEuler(; inner = DevicePCG())), SequentialCPM()).retcode == FiRC.Success
    m = e(() -> mk(; solvers = [:c => Multigrid()]))
    @test occursin("give it to one, `solvers = [c => BackwardEuler(; inner = Multigrid())]`", m)
    @test solve(mk(; solvers = [:c => BackwardEuler(; inner = Multigrid())]), SequentialCPM()).retcode == FiRC.Success
    @test occursin("`BackwardEuler(; dt = 0.5)`: a `PottsProblem` field steps over the MCS window",
        e(() -> mk(; field_solver = BackwardEuler(; dt = 0.5))))
end

# F3 batch 3 review r1 (research/field-compiler/f3/reviews/F3-batch3-r1.md), the A halves of M1,
# M2, M4 and M6. Base 2d213237 (~/lpwork/f3r1-nc-a-base.log): each testset fails there.
@potts_model FiTimed begin
    @kinds medium A
    @variables c(field) = 1.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.1 * Δ(c) - (1 + 20 * time) * c
    @sweep Metropolis(; temperature = 1.0, mcs_duration = 0.2)
end
@potts_model FiRobinW begin
    @kinds medium A[frozen]
    @parameters rb = -1.0
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - 0.3 * c + 0.1 * x
    @bcs 1.5 * c(t, x, 0) - rb * Differential(y)(c(t, x, 0)) ~ 0.5
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiHex begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); geometry = Hexagonal(), boundary = Periodic())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 2.0 * Δ(c) - c + 0.1 * (kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiComp begin
    @kinds medium A[frozen]
    @variables u(field)[1:2] = 0.5
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u[1]) ~ 0.5 * Δ(u[1]) - 40 * u[1] / (0.025 + u[1]) + 20
        D(u[2]) ~ 0.5 * Δ(u[2]) - u[2] + u[1]
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiScal begin
    @kinds medium A[frozen]
    @variables begin
        c(field) = 0.5
        o(field) = 0.5
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(c) ~ 0.5 * Δ(c) - 40 * c / (0.025 + c) + 20
        D(o) ~ 0.5 * Δ(o) - o + c
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "r1 M1 (A): an operator that reads the time is built at each substep's end time" begin
    # one MCS of length 0.2 in 4 substeps: c = Π_j 1/(1 + h(1 + 20 t_j)) (base: 0.49638, the
    # first substep's operator at every substep)
    s = solve(PottsProblem(FiTimed(; name = :f), [ownership => zeros(Int32, 8, 8), kind => Symbol[]], (0, 1);
        field_solver = BackwardEuler(; substeps = 4, inner = DevicePCG(; rtol = 1e-13, budget = 200))), SequentialCPM())
    h = 0.05
    @test maximum(abs, s.u[end].site.c .- prod(1 / (1 + h * (1 + 20 * j * h)) for j in 1:4)) < 1e-12
end

@testset "r1 M2 (A): a write that turns a Robin face negative reclassifies the group" begin
    dims = (12, 10)
    for (b0, b1) in ((-1.0, 1.0), (1.0, -1.0))
        integ = init(PottsProblem(FiRobinW(; name = :f), [fi_op(dims); :rb => b0], (0, 4); field_solver = BackwardEuler()),
            SequentialCPM(); save_start = false)
        step!(integ)
        c1 = copy(Array(current_state(integ).site.c))
        integ.ps[:rb] = b1
        foreach(_ -> step!(integ), 1:2)
        fresh, fi = fi_runA(FiRobinW, [fi_op(dims); :c => c1; :rb => b1], 2)
        rt, rf = CorePotts._runtime(getfield(integ.ctx, :__fields1)), CorePotts._runtime(getfield(fi.ctx, :__fields1))
        @test (rt.cache.exact, rt.cache.newton) == (rf.cache.exact, rf.cache.newton)
        @test maximum(abs, Array(current_state(integ).site.c) .- fresh[end]) < 1e-12   # (base, −1 → +1: exact, newton = 1)
    end
end

@testset "r1 M4 (A): a hexagonal lattice refuses BackwardEuler in words" begin
    σ = zeros(Int32, 16, 16); σ[4:6, 4:6] .= 1
    mk(fs) = PottsProblem(FiHex(; name = :f), [ownership => σ, kind => [:A]], (0, 3); field_solver = fs)
    # base: `ConvergenceFailure` at MCS 1 with the route "more substeps … or a larger linear budget"
    @test_throws "a hexagonal lattice has no implicit solve yet (the solver's operator has no hexagonal faces); step it with `field_solver = ExplicitEuler()`" solve(
        mk(BackwardEuler()), SequentialCPM())
    @test solve(mk(ExplicitEuler()), SequentialCPM()).retcode == FiRC.Success
end

@testset "r1 M6 (A): a component field equals its scalar spelling" begin
    dims, k = (12, 10), 3
    function run(M)
        integ = init(PottsProblem(M(; name = :f), fi_op(dims), (0, k); field_solver = BackwardEuler()), SequentialCPM(); save_start = false)
        foreach(_ -> step!(integ), 1:k)
        st = current_state(integ).site
        return integ, [Array(getproperty(st, n)) for n in sort!(collect(propertynames(st)))], sort!(collect(propertynames(st)))
    end
    (ia, a, na), (ib, b, nb) = run(FiComp), run(FiScal)
    ra, rb = CorePotts._runtime(getfield(ia.ctx, :__fields1)), CorePotts._runtime(getfield(ib.ctx, :__fields1))
    fs(i) = (i.stats.fields.solves, i.stats.fields.budget, i.stats.fields.newton_budget)
    @test ra.cache.newton == rb.cache.newton == 1 && fs(ia) == fs(ib) == (2k, 0, 0)
    @test [(r.op.exact, r.op.iterate) for r in ra.cache.rows] == [(r.op.exact, r.op.iterate) for r in rb.cache.rows]
    @test a == b
end
