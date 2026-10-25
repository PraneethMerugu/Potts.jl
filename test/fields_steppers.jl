# F3-10, F3-11 (F3 design §3.3, §3.7): `CrankNicolson` and `BDF2` in front end A, through the
# runtime of front end B (the models and helpers of fields_implicit.jl). With σ frozen A equals
# B bitwise; Crank–Nicolson damps the first substep of every MCS when the group reads the CPM
# or its mask moves; BDF2 keeps its history in the runtime (not in `st.site`, saved states or a
# checkpoint), across σ moves, and restarts after a write, `reinit!` or a restored checkpoint.
# Base (69bef544, ~/lpwork/f3b4-nc10-a-base.log, f3b4-nc11-a-base.log): `CrankNicolson` and
# `BDF2` are not defined in Potts (every testset errors).

# a Dirichlet mask on moving cells (P1 (c)): `c = 1` inside the cells, fast diffusion and decay
@potts_model FiMove begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((24, 24); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @equations D(c) ~ 4.0 * Δ(c) - 2.0 * c
    @bcs c ~ masked(kind == A, 1.0)
    @sweep Metropolis(; temperature = 12.0)
    @schedule sweep, fields
end
fi_rt(integ) = CorePotts._runtime(getfield(integ.ctx, :__fields1))
fi_c(integ) = copy(Array(current_state(integ).site.c))

@testset "F3-10: CrankNicolson in A equals B bitwise (σ frozen)" begin
    dims, k = (12, 10), 6
    # no CPM read and no moving mask: damped at the start only (as B)
    a, integ = fi_runA(FiStill, fi_op(dims), k; field_solver = CrankNicolson())
    b = fi_runB(FiStill, dims, k; u0 = [:c => zeros(dims)], inputs = [], alg = CrankNicolson(; dt = 1.0))
    @test a == b && !fi_rt(integ).cache.jumps
    # a mask that moves (it follows `e`) and a kind source: damped every MCS, in A and in B
    a, integ = fi_runA(FiMix, fi_op(dims), k; field_solver = CrankNicolson())
    b = fi_runB(FiMix, dims, k; u0 = [:c => zeros(dims), :e => zeros(dims)], alg = CrankNicolson(; dt = 1.0))
    @test a == b && fi_rt(integ).cache.jumps
    @test fi_warm(integ) == 0
    # components: the scalar spelling's run, bitwise
    run(M) = (i = init(PottsProblem(M(; name = :f), fi_op(dims), (0, 3); field_solver = CrankNicolson()), SequentialCPM());
              foreach(_ -> step!(i), 1:3); st = current_state(i).site; [Array(getproperty(st, n)) for n in sort!(collect(propertynames(st)))])
    @test run(FiComp) == run(FiScal)
    # one binding in both front ends
    m = Module()
    Core.eval(m, :(using Potts; using Potts.LatticePDE))
    @test Core.eval(m, :CrankNicolson) === Potts.LatticePDE.CrankNicolson === Potts.LatticeFields.Problems.CrankNicolson
end

@testset "F3-10: a moving mask: the damped start beats Backward Euler" begin
    # P1 (c): cells move every MCS; against 20 Backward Euler substeps per MCS, Crank–Nicolson
    # (one substep: two Backward Euler halves) is closer than one Backward Euler substep
    σ = zeros(Int32, 24, 24); σ[5:8, 5:8] .= 1; σ[14:17, 12:15] .= 2
    op = [ownership => σ, kind => [:A, :A]]
    run(fs) = (s = solve(PottsProblem(FiMove(; name = :f), op, (0, 12); field_solver = fs, seed = 7), SequentialCPM());
               (Array(s.u[end].site.c), s.u[end].σ))
    (ref, σr), (be, σb), (cn, σc) = run(BackwardEuler(; substeps = 20)), run(BackwardEuler()), run(CrankNicolson())
    @test σr == σb == σc                                       # (the field does not steer the CPM)
    eb, ec = maximum(abs, be .- ref), maximum(abs, cn .- ref)
    @test ec <= eb || (println("CN ", ec, " BE ", eb); false)
    # a state write re-damps (`reset!`)
    integ = init(PottsProblem(FiStill(; name = :f), fi_op((12, 10)), (0, 4); field_solver = CrankNicolson()), SequentialCPM())
    step!(integ); step!(integ)
    @test !fi_rt(integ).cache.start
    integ[:c] = fill(0.25, 12, 10)
    @test fi_rt(integ).cache.start
end

# a Merks-like secretion field: the cells secrete `c`, which diffuses and decays; it reads the
# CPM (`kind`), so its data jump every MCS, and it does not steer the CPM (σ is the same in
# every run)
@potts_model FiSecrete begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((24, 24); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @equations D(c) ~ 1.0 * Δ(c) - 0.2 * c + 1.0 * (kind == A)
    @sweep Metropolis(; temperature = 10.0)
end

@testset "F3-10 r1 S1: CrankNicolson on CPM-coupled data takes 2 substeps by default (order 2 in the count)" begin
    # base 00326b72 (~/lpwork/f3b5-nc-s1.log, the count of 1): `CrankNicolson()` takes 1 substep,
    # one damped substep per MCS (Backward Euler in two halves); its error then equals
    # `substeps = 1`'s, and the count assertion fails
    σ = zeros(Int32, 24, 24); σ[4:7, 4:7] .= 1; σ[4:7, 15:18] .= 2; σ[15:18, 9:12] .= 3
    op = [ownership => σ, kind => fill(:A, 3)]
    function run(fs)
        i = init(PottsProblem(FiSecrete(; name = :f), op, (0, 6); field_solver = fs, seed = 3), SequentialCPM())
        foreach(_ -> step!(i), 1:6)
        return fi_c(i), copy(Array(current_state(i).σ)), i
    end
    ref, σr, _ = run(CrankNicolson(; substeps = 128))
    err(fs) = ((c, σ, i) = run(fs); @test σ == σr; (maximum(abs, c .- ref), i))
    e2, i2 = err(CrankNicolson())
    @test fi_rt(i2).cache.jumps && substep_counts(i2) == [2]
    e1, _ = err(CrankNicolson(; substeps = 1))
    eb, _ = err(BackwardEuler())
    e4, _ = err(CrankNicolson(; substeps = 4))
    e8, _ = err(CrankNicolson(; substeps = 8))
    e16, _ = err(CrankNicolson(; substeps = 16))
    # the error of an MCS falls as 1/n² (here 2.32 from n = 2 to 4, then 2.02; measured 40²:
    # 1.20e-2, 2.96e-3, 7.29e-4 at n = 2, 4, 8)
    os = log2.([e4, e8] ./ [e8, e16])
    @test all(o -> abs(o - 2) < 0.25, os) || (println("CN orders in the count ", os); false)
    # the default beats one damped substep and Backward Euler (measured 40²: 1.2e-2 against
    # 5.9e-2 and 1.1e-1)
    @test e2 < e1 / 2 && e2 < eb / 4 || (println("CN() ", e2, " CN(1) ", e1, " BE ", eb); false)
    # data that do not jump keep the count of 1
    _, i = fi_runA(FiStill, fi_op((12, 10)), 2; field_solver = CrankNicolson())
    @test !fi_rt(i).cache.jumps && substep_counts(i) == [1]
end

@testset "F3-11: BDF2 in A equals B bitwise; its history is no state" begin
    dims, k = (12, 10), 6
    for M in (FiStill, FiMix)
        u0 = M === FiMix ? [:c => zeros(dims), :e => zeros(dims)] : [:c => zeros(dims)]
        a, integ = fi_runA(M, fi_op(dims), k; field_solver = BDF2())
        @test a == fi_runB(M, dims, k; u0, inputs = M === FiMix ? [:kind => fi_kin(dims)] : [], alg = BDF2(; dt = 1.0))
        @test fi_warm(integ) == 0
    end
    run(M) = (i = init(PottsProblem(M(; name = :f), fi_op(dims), (0, 3); field_solver = BDF2()), SequentialCPM());
              foreach(_ -> step!(i), 1:3); st = current_state(i).site; [Array(getproperty(st, n)) for n in sort!(collect(propertynames(st)))])
    @test run(FiComp) == run(FiScal)
    # the history lives in the runtime: `st.site`, the saved states and a checkpoint hold what a
    # Backward Euler run holds
    mk(fs) = PottsProblem(FiStill(; name = :f), fi_op(dims), (0, 3); field_solver = fs)
    sb, se = solve(mk(BDF2()), SequentialCPM()), solve(mk(BackwardEuler()), SequentialCPM())
    @test propertynames(sb.u[end].site) == propertynames(se.u[end].site)
    ib = init(mk(BDF2()), SequentialCPM())
    step!(ib); step!(ib)
    @test propertynames(checkpoint(ib).state.site) == propertynames(se.u[end].site)
    @test fi_rt(ib).cache.rows[1].prev !== nothing
    m = Module()
    Core.eval(m, :(using Potts; using Potts.LatticePDE))
    @test Core.eval(m, :BDF2) === Potts.LatticePDE.BDF2 === Potts.LatticeFields.Problems.BDF2
end

@testset "F3-11: BDF2's history survives σ moves; writes, reinit! and checkpoints restart it" begin
    dims = (16, 16)
    σ = zeros(Int32, dims...); σ[4:8, 4:8] .= 1
    integ = init(PottsProblem(FiMoving(; name = :f), [ownership => σ, kind => [:A]], (0, 8); field_solver = BDF2()),
        SequentialCPM(); save_start = false)
    step!(integ)
    rt = fi_rt(integ)
    σs = [copy(Array(current_state(integ).σ))]
    for _ in 2:6
        step!(integ)
        push!(σs, copy(Array(current_state(integ).σ)))
        @test !rt.cache.start && rt.cache.γ == 2 / 3          # no restart: BDF2 steps every MCS
    end
    @test length(unique(σs)) > 1                              # (σ moved)
    integ[:c] = fill(0.1, dims...)
    @test rt.cache.start                                      # a write restarts it
    step!(integ)
    @test !rt.cache.start
    reinit!(integ)
    @test rt.cache.start                                      # … and `reinit!`
    # a restored checkpoint restarts the history (one Backward Euler substep): it does not
    # continue a BDF2 run bitwise, while a Backward Euler run does (F3 design §3.3 Checkpoints)
    function restored(fs)
        p = PottsProblem(FiStill(; name = :f), fi_op((12, 10)), (0, 6); field_solver = fs)
        i = init(p, SequentialCPM())
        foreach(_ -> step!(i), 1:3)
        cp = checkpoint(i)
        foreach(_ -> step!(i), 1:3)
        j = init(p, SequentialCPM(); checkpoint = cp)
        @test fi_rt(j).cache.start
        foreach(_ -> step!(j), 1:3)
        return fi_c(i), fi_c(j)
    end
    a, b = restored(BackwardEuler())
    @test a == b
    a, b = restored(BDF2())
    @test a != b                                             # (a Backward Euler substep, then BDF2 again)
end

# F3-12a (F3 design §3.5): `QuasiSteady` in front end A, through the runtime of B. With σ
# frozen A equals B bitwise; the refusals name the route; an island the cells' kinds leave
# with no decay ends the run with `ConvergenceFailure`. Base (b32d9112,
# ~/lpwork/f3b5-nc-12a-a-base.log): `QuasiSteady` is not defined in Potts (every testset errors).
@potts_model FiSteady begin
    @kinds medium A[frozen]
    @parameters begin
        Dc = 0.4
        kd = 0.3
        s = 0.5
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) - kd * c + s * (kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
# two discs (the field's domain), a decay only inside the cells: the disc with no cell is an
# island with no decay and no fixed value
@potts_model FiIsland begin
    @structural_parameters begin
        domain = x -> (x[1] - 6.5)^2 + (x[2] - 6.5)^2 <= 25 || (x[1] - 18.5)^2 + (x[2] - 6.5)^2 <= 25
    end
    @kinds medium A
    @parameters kd = 1.0
    @variables c(field) = 0.0
    @lattice Lattice((24, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 16.0)^2
    @equations D(c) ~ 0.5 * Δ(c) - kd * (kind == A) * c + 1.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiNoIsland begin
    @structural_parameters begin
        domain = x -> (x[1] - 6.5)^2 + (x[2] - 6.5)^2 <= 25 || (x[1] - 18.5)^2 + (x[2] - 6.5)^2 <= 25
    end
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((24, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 16.0)^2
    @equations D(c) ~ 0.5 * Δ(c) - 0.1 * c + 1.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiGrow begin
    @kinds medium A[frozen]
    @parameters g = -0.5
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - g * c + 0.1 * (kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@testset "F3-12a: QuasiSteady in A equals B bitwise (σ frozen); one solve per MCS" begin
    dims, k = (12, 10), 4
    for M in (FiStill, FiSteady)
        a, integ = fi_runA(M, fi_op(dims), k; field_solver = QuasiSteady())
        @test a == fi_runB(M, dims, k; u0 = [:c => zeros(dims)], inputs = M === FiSteady ? [:kind => fi_kin(dims)] : [],
            alg = QuasiSteady(; dt = 1.0))
        @test substep_counts(integ) == [1] && integ.stats.fields.solves == k && fi_warm(integ) == 0
    end
    # the steady state: an MCS later the field is unchanged to the solver's tolerance
    a, _ = fi_runA(FiSteady, fi_op(dims), 3; field_solver = QuasiSteady(; inner = DevicePCG(; rtol = 1e-12, budget = 64)))
    @test maximum(abs, a[3] .- a[2]) < 1e-10 && maximum(a[3]) > 0
    @test_throws "`QuasiSteady(; dt = 0.1)`: a `PottsProblem` field steps over the MCS window (`mcs_duration`); leave `dt` out" PottsProblem(FiSteady(; name = :f),
        fi_op(dims), (0, 2); field_solver = QuasiSteady(; dt = 0.1))
    m = Module()
    Core.eval(m, :(using Potts; using Potts.LatticePDE))
    @test Core.eval(m, :QuasiSteady) === Potts.LatticePDE.QuasiSteady === Potts.LatticeFields.Problems.QuasiSteady
end

# Review r2 M1 in A: a steady field in a loop of solver groups is refused until F3-12c bounds
# its gain; the routes (one `BackwardEuler` solver; `BackwardEuler` for the steady field) run.
# Base (773f0957, ~/lpwork/f3b5-nc-r2-m1-a.log): the loop is accepted (the refusal test fails).
@potts_model FiLoop begin
    @kinds medium A[frozen]
    @variables begin
        u(field) = 0.0
        w(field) = 1.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u) ~ 0.1 * Δ(u) - 0.1 * u + 0.5 * w
        D(w) ~ 0.1 * Δ(w) - w - 0.5 * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
@testset "F3-12a (r2 M1): QuasiSteady in a loop of solver groups in A is refused, with its routes" begin
    dims = (12, 10)
    @test_throws "the fields `u`, `w` are in solver groups that read one another in a loop, and `u` is solved with `QuasiSteady`" PottsProblem(
        FiLoop(; name = :f), fi_op(dims), (0, 3); field_solver = FieldGroups(:u => QuasiSteady(), :w => BackwardEuler()))
    for fs in (BackwardEuler(), FieldGroups(:u => BackwardEuler(), :w => BackwardEuler()))
        s = solve(PottsProblem(FiLoop(; name = :f), fi_op(dims), (0, 3); field_solver = fs), SequentialCPM())
        @test s.retcode == Potts.SciMLBase.ReturnCode.Success
    end
end

@testset "F3-12a: QuasiSteady in A: the refusals; an island ends the run" begin
    dims = (12, 10)
    # a growth the operator sees (`g < 0` makes `- g c` a growth): at build and at a write
    @test_throws "QuasiSteady: field `c`: its local derivative `∂f/∂c` = 0.5 is positive" PottsProblem(FiGrow(; name = :f),
        fi_op(dims), (0, 3); field_solver = QuasiSteady())
    integ = init(PottsProblem(FiSteady(; name = :f), fi_op(dims), (0, 3); field_solver = QuasiSteady()), SequentialCPM())
    step!(integ)
    @test_throws "is positive (a growth the operator sees)" (integ.ps[:kd] = -1.0)
    # an island: the cell sits in one disc; the other has no decay and no fixed value
    σ = zeros(Int32, 24, 12); σ[5:8, 5:8] .= 1
    p = PottsProblem(FiIsland(; name = :f), [ownership => σ, kind => [:A]], (0, 3); field_solver = QuasiSteady())
    integ = init(p, SequentialCPM())
    s = @test_logs (:warn, r"field `c`: the solve failed in the field step of MCS 1 .*\(the steady solve made no real reduction.*`ReturnCode.ConvergenceFailure`: the run stops; give that region a decay or a fixed value, or step the field with `BackwardEuler`") match_mode = :any solve!(integ)
    @test s.retcode == Potts.SciMLBase.ReturnCode.ConvergenceFailure && integ.t == 1
    # with a decay everywhere, solved
    s = solve(PottsProblem(FiNoIsland(; name = :f), [ownership => σ, kind => [:A]], (0, 3); field_solver = QuasiSteady()),
        SequentialCPM())
    @test s.retcode == Potts.SciMLBase.ReturnCode.Success
end
