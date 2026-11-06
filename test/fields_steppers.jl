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

# F3-12b (F3 design §3.5): steady rows `0 ~ rhs` in A. A steady row is solved by `QuasiSteady`
# for the field its operator acts on, by default too; another solver for it is refused; the
# QuasiSteady groups step first. Base (6b6bf089, ~/lpwork/f3b5-nc-12b-a-base.log): `0 ~ rhs` is
# refused ("equations are `D(x) ~ rhs` …"; every testset errors).
@potts_model FiSteady0 begin
    @kinds medium A[frozen]
    @parameters begin
        Dc = 0.4
        kd = 0.3
        s = 0.5
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations 0 ~ Dc * Δ(c) - kd * c + s * (kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
# a transient field `e` (declared and written first) that reads the steady `c`
@potts_model FiSteadyMix begin
    @kinds medium A[frozen]
    @variables begin
        e(field) = 0.0
        c(field) = 0.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(e) ~ 0.1 * Δ(e) - e + c
        0 ~ 0.4 * Δ(c) - 0.3 * c + 0.5 * (kind == A)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@testset "F3-12b: steady rows `0 ~ rhs` in A: QuasiSteady by default, equal to the rate row and to B" begin
    dims, k = (12, 10), 3
    a0, integ = fi_runA(FiSteady0, fi_op(dims), k; field_solver = nothing)
    a1, _ = fi_runA(FiSteady, fi_op(dims), k; field_solver = QuasiSteady())
    @test a0 == a1 && substep_counts(integ) == [1]
    # B reads the model's steady row as `0 ~ rhs` (`Potts.fields`) and steps it the same
    @test a0 == fi_runB(FiSteady0, dims, k; u0 = [:c => zeros(dims)], alg = QuasiSteady(; dt = 1.0))
    @test any(eq -> startswith(string(eq), "0 ~"), Potts.fields(FiSteady0(; name = :f)).eqs)
    # another solver for a steady row is refused; `QuasiSteady` given is the default
    @test_throws "`field_solver = BackwardEuler()`: every field of model `f` has a steady equation `0 ~ rhs` (`c`), which `QuasiSteady` solves" PottsProblem(
        FiSteady0(; name = :f), fi_op(dims), (0, 2); field_solver = BackwardEuler())
    @test_throws "`solvers`: the field `c` has a steady equation `0 ~ rhs`, which `QuasiSteady` solves" PottsProblem(
        FiSteady0(; name = :f), fi_op(dims), (0, 2); solvers = [:c => BackwardEuler()])
    b0, _ = fi_runA(FiSteady0, fi_op(dims), k; field_solver = QuasiSteady())
    @test b0 == a0
    # mixed: `c` steady (QuasiSteady), `e` with the field solver; the steady group first
    for fs in (nothing, BackwardEuler())
        p = PottsProblem(FiSteadyMix(; name = :f), fi_op(dims), (0, k); field_solver = fs)
        integ = init(p, SequentialCPM())
        @test solve!(integ).retcode == Potts.SciMLBase.ReturnCode.Success
        @test first(substep_counts(integ)) == 1 && length(substep_counts(integ)) == 2
    end
    @test_throws "`FieldGroups`: the field `c` has a steady equation `0 ~ rhs`" PottsProblem(FiSteadyMix(; name = :f),
        fi_op(dims), (0, 2); field_solver = FieldGroups(:c => ExplicitEuler()))
end

# Review r3 S3, S4: a steady row's sign does not matter (the elliptic form `0 ~ k c − D Δ(c) −
# s`), and its field follows the one rule of both front ends (`LatticePDE.steady_choice`): a
# field with no other equation, so a local row that reads a transient field (`0 ~ −2c + 0.5e`)
# is `c`'s, equal to B. Base (e7068add, ~/lpwork/f3b6-nc-r3-a.log): "the diffusion coefficient …
# is negative", and "this row's operators apply to `c` and `e`".
@potts_model FiSteadyNeg begin
    @kinds medium A[frozen]
    @parameters begin
        Dc = 0.4
        kd = 0.3
        s = 0.5
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations 0 ~ kd * c - Dc * Δ(c) - s * (kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FiLocal begin
    @kinds medium A[frozen]
    @variables begin
        c(field) = 0.0
        e(field) = 0.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        0 ~ -2.0 * c + 0.5 * e
        D(e) ~ 0.1 * Δ(e) - e + 0.5 * (kind == A)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@testset "F3-12b (r3 S3, S4): a steady row's sign; its field by the rule of both front ends" begin
    dims, k = (12, 10), 3
    an, _ = fi_runA(FiSteadyNeg, fi_op(dims), k; field_solver = QuasiSteady(; inner = DevicePCG(; rtol = 1e-12, budget = 64)))
    a0, _ = fi_runA(FiSteady0, fi_op(dims), k; field_solver = QuasiSteady(; inner = DevicePCG(; rtol = 1e-12, budget = 64)))
    @test maximum(abs, an[end] .- a0[end]) < 1e-10
    al, integ = fi_runA(FiLocal, fi_op(dims), k)
    @test substep_counts(integ)[1] == 1 && maximum(al[end]) > 0
    @test al == fi_runB(FiLocal, dims, k; u0 = [:c => zeros(dims), :e => zeros(dims)])
    @test only(steady_fields(FiLocal(; name = :f))) == ("0 ~ -2.0c(t) + 0.5e(t)" => :c)      # (r3 N2)
end

# F3-12c in A: the QuasiSteady gain in the coupling rule, and `init = :steady`. `FiLoopK` is
# FiLoop with the decay `kd` and the coupling `kc` as parameters: at kd = 1, kc = 0.5 the gain
# is 1 and κ = 1 · 0.5 · 1 · 0.5 = 0.25, accepted; uniform data stay uniform (no flux faces), so
# each MCS is u = (kc/kd) w, then w⁺ = (w − kc u)/2. A write to kd = 0.1 (κ = 2.5) is refused:
# the transient group's rule reads the steady row's decay (every group holds the system's
# parameters). Base (932c12ce, ~/lpwork/f3b7-nc-12c-a-base.log): the loop is refused ("does not
# bound that gain yet") and `init` is no keyword (both testsets error).
@potts_model FiLoopK begin
    @kinds medium A[frozen]
    @parameters begin
        kd = 1.0
        kc = 0.5
    end
    @variables begin
        u(field) = 0.0
        w(field) = 1.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u) ~ 0.1 * Δ(u) - kd * u + kc * w
        D(w) ~ 0.1 * Δ(w) - w - kc * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
# the decay a kind table: the transient group's rule reads that table too (its phase holds the
# system's tables after its own). Control (a327e38f, ~/lpwork/f3b7-a2.log before the fix): the
# table was missing from the rule, its decay read 0, and the loop was refused ("`u` has no decay").
@potts_model FiLoopT begin
    @kinds medium A[frozen]
    @parameters begin
        δ[kind] = [2.0, 1.0]
        kc = 0.5
    end
    @variables begin
        u(field) = 0.0
        w(field) = 1.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u) ~ 0.1 * Δ(u) - δ[kind] * u + kc * w
        D(w) ~ 0.1 * Δ(w) - w - kc * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
# the cross coefficients kind tables (review r4 N3; reviewer probe ~/lpwork/f3rev9/a4.jl): the
# steady row's `ko[kind]` (k_out) and the reader's `ki[kind]` (k_in), each read by the rule
# from the whole system's tables; at 0.5 κ = 0.25, at 3 in one kind κ = 1.5
@potts_model FiLoopX begin
    @kinds medium A[frozen]
    @parameters begin
        ko[kind] = [0.5, 0.5]
        ki[kind] = [0.5, 0.5]
    end
    @variables begin
        u(field) = 0.0
        w(field) = 1.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u) ~ 0.1 * Δ(u) - 1.0 * u + ko[kind] * w
        D(w) ~ 0.1 * Δ(w) - w - ki[kind] * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
@testset "F3-12c: the QuasiSteady gain in A: an accepted loop is the split recursion; a write past it is refused" begin
    dims = (12, 10)
    tight = DevicePCG(; rtol = 1e-12, budget = 64)
    fs = FieldGroups(:u => QuasiSteady(; inner = tight), :w => BackwardEuler(; inner = tight))
    integ = init(PottsProblem(FiLoopK(; name = :f), fi_op(dims), (0, 3); field_solver = fs), SequentialCPM())
    for n in 1:3
        step!(integ)
        st = current_state(integ).site
        @test maximum(abs, Array(st.w) .- 0.375^n) < 1e-9 && maximum(abs, Array(st.u) .- 0.5 * 0.375^(n - 1)) < 1e-9
    end
    @test_throws "window · Σ k_in · gain · k_out = 2.5 > 1" (integ.ps[:kd] = 0.1)
    @test integ.ps[:kd] == 1.0
    # a kind-table decay (smallest 1: κ = 0.25): accepted; a table write to 0.1 is refused
    integ = init(PottsProblem(FiLoopT(; name = :f), fi_op(dims), (0, 3); field_solver = fs), SequentialCPM())
    @test solve!(integ).retcode == FiRC.Success
    @test_throws "window · Σ k_in · gain · k_out = 2.5 > 1" (integ.ps[:δ] = [0.1, 0.1])
    # the cross coefficients in kind tables: either one past the limit is refused at build and
    # at a write (the values unchanged); within it the loop runs
    for (k, v) in ((:ko, [0.5, 3.0]), (:ki, [3.0, 0.5]))
        @test_throws "window · Σ k_in · gain · k_out = 1.5 > 1" PottsProblem(FiLoopX(; name = :f, k => v), fi_op(dims), (0, 3);
            field_solver = fs)
    end
    integ = init(PottsProblem(FiLoopX(; name = :f), fi_op(dims), (0, 3); field_solver = fs), SequentialCPM())
    for k in (:ko, :ki)
        @test_throws "> 1" (integ.ps[k] = [3.0, 3.0])
        @test integ.ps[k] == [0.5, 0.5]
    end
    @test solve!(integ).retcode == FiRC.Success
    # FiLoop (gain 10, κ = 2.5) stays refused, now with the gain
    @test_throws "(`u` answers at once with a gain up to 10.0, from its smallest decay and its faces, times 0.5" PottsProblem(
        FiLoop(; name = :f), fi_op(dims), (0, 3); field_solver = FieldGroups(:u => QuasiSteady(), :w => BackwardEuler()))
end

@testset "F3-12c: `init = :steady` in A: the field starts at its steady state; refusals name `init`" begin
    dims = (12, 10)
    tight = DevicePCG(; rtol = 1e-12, budget = 64)
    # the steady state: one QuasiSteady MCS (σ frozen: the same inputs)
    ref, _ = fi_runA(FiSteady, fi_op(dims), 1; field_solver = QuasiSteady(; inner = tight))
    for fs in (BackwardEuler(; init = :steady, inner = tight), ExplicitEuler(; init = :steady), CrankNicolson(; init = :steady),
               BDF2(; init = :steady), QuasiSteady(; init = :steady))
        integ = init(PottsProblem(FiSteady(; name = :f), fi_op(dims), (0, 3); field_solver = fs), SequentialCPM())
        c0 = copy(Array(current_state(integ).site.c))
        @test maximum(abs, c0 .- ref[1]) < (fs isa BackwardEuler ? 1e-9 : 1e-5) || (println("12c A init ", fs); false)
        @test integ.stats.fields.solves >= 1 && integ.retcode == FiRC.Default
        s = solve!(integ)
        @test s.retcode == FiRC.Success && maximum(abs, Array(current_state(integ).site.c) .- ref[1]) < 1e-5
        reinit!(integ)
        @test maximum(abs, Array(current_state(integ).site.c) .- c0) < 1e-12
    end
    # without it the start is the initial value
    integ = init(PottsProblem(FiSteady(; name = :f), fi_op(dims), (0, 3); field_solver = BackwardEuler()), SequentialCPM())
    @test all(iszero, Array(current_state(integ).site.c))
    # a growth has no stable steady state: refused at build, naming `init`; the step alone runs
    @test_throws "`init = :steady` of `c`: QuasiSteady: field `c`: its local derivative `∂f/∂c` = 0.5 is positive" PottsProblem(
        FiGrow(; name = :f), fi_op(dims), (0, 3); field_solver = BackwardEuler(; init = :steady))
    @test PottsProblem(FiGrow(; name = :f), fi_op(dims), (0, 3); field_solver = BackwardEuler()) isa PottsProblem
    # an ODE starts from its initial values
    @test_throws "`ode_solver`: `ExplicitEuler(; init = :steady)`: `init = :steady` starts a field group at its steady state" Potts._check_ode_dt(
        ExplicitEuler(; init = :steady), "`ode_solver`")
    # the canonical text keeps the default's (the guard's fingerprints), and names `init` when set
    @test Potts._canonical(BackwardEuler()) == "BackwardEuler(inner=:auto,lower=nothing,newton=nothing,solver_T=:auto,substeps=nothing)"
    # the PCG count of `ExplicitEuler(init = :steady)` from zero (design §5; review r4 N4): one
    # solve, 5 iterations of the default inner (rtol 1e-6) on the CPU (the design's "6, as C7b":
    # at most 6)
    integ = init(PottsProblem(FiSteady(; name = :f), fi_op(dims), (0, 3); field_solver = ExplicitEuler(; init = :steady)), SequentialCPM())
    rt = CorePotts._runtime(getfield(integ.ctx, :__fields1_start))
    ne = Potts.LatticeFields.Solvers.iterations(rt.cache.rows[1].solver)
    @test rt.totals.solves == 1 && 1 <= ne <= 6 || (println("r4 N4 A EE start PCG ", ne); false)
end

# a Robin face of opposite signs with a definite steady operator (decay 1 > the face's 0.8)
@potts_model FiRobinQ begin
    @kinds medium A[frozen]
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - 1.0 * c + 0.1 * x
    @bcs 1.0 * c(t, x, 0) + Differential(y)(c(t, x, 0)) ~ 0.5
    @sweep Metropolis(; temperature = 1.0)
end
# F3-12a (design §5; review r4 N4): the F3-05 capabilities in a QuasiSteady group in A, each
# equal to B bitwise (σ frozen): a Robin face of each sign, a field face, a mask value field;
# and an input bound by aliasing, the CPM's moving σ, read by the next window's steady solve
@testset "F3-12a: the solver capabilities in a QuasiSteady group in A (F3-05), equal to B bitwise" begin
    dims, k = (12, 10), 2
    # FiRobinN's face (α 1, β 1 at unit spacing: +0.8 on the diagonal against the decay 0.3) makes
    # the steady operator indefinite: refused, as in B; FiRobinQ's decay 1 keeps it definite
    @test_throws "its steady operator is indefinite (smallest eigenvalue -0.233)" PottsProblem(FiRobinN(; name = :f), fi_op(dims),
        (0, 3); field_solver = QuasiSteady())
    for M in (FiRobinP, FiRobinQ, FiFieldFace, FiMaskField)
        a, integ = fi_runA(M, fi_op(dims), k; field_solver = QuasiSteady())
        b = fi_runB(M, dims, k; u0 = [:c => zeros(dims)], inputs = M === FiMaskField ? [:kind => fi_kin(dims)] : [],
            alg = QuasiSteady(; dt = 1.0))
        @test a == b || (println("r4 N4 A ", M, " ", maximum(abs, a[end] .- b[end])); false)
        @test integ.stats.fields.solves >= k && integ.retcode == FiRC.Default
    end
    σ = zeros(Int32, 16, 16); σ[4:7, 4:7] .= 1; σ[10:13, 9:12] .= 2
    integ = init(PottsProblem(FiMoving(; name = :f), [ownership => σ, kind => [:A, :A]], (0, 20);
        field_solver = QuasiSteady(), seed = 3), SequentialCPM(); save_start = false)
    foreach(_ -> step!(integ), 1:3)
    c3, σ3 = copy(Array(current_state(integ).site.c)), copy(Array(current_state(integ).σ))
    step!(integ)
    st = current_state(integ)
    @test Array(st.σ) != σ3
    K4 = Int32.(Array(st.σ) .!= 0)
    @test Array(st.site.c) == fi_runB(FiMoving, (16, 16), 1; u0 = [:c => c3], inputs = [:kind => K4], alg = QuasiSteady(; dt = 1.0))[1]
    @test Array(st.site.c) != fi_runB(FiMoving, (16, 16), 1; u0 = [:c => c3], inputs = [:kind => Int32.(σ3 .!= 0)],
        alg = QuasiSteady(; dt = 1.0))[1]
end

# F3-12d: the coupled steady solve in A. Steady rows that read one another are one QuasiSteady
# group solved together (Krylov.jl FGMRES on the group's whole Jacobian), as in B: with σ frozen
# A equals B bitwise; components equal scalars; a loop through a transient field composes the
# steady gains; Float16 storage is refused. Base (c40a68f8, ~/lpwork/f312d/nc-base-potts.log):
# the strong pair ends `ConvergenceFailure`, the feedback loop is refused.
@potts_model FcPair begin
    @kinds medium A[frozen]
    @variables begin
        u(field) = 0.0
        v(field) = 0.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        0 ~ 0.1 * Δ(u) - 0.1 * u + 5.0 * v + 0.5 * (kind == A)
        0 ~ 0.1 * Δ(v) - v - 5.0 * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FcComp begin
    @kinds medium A[frozen]
    @variables w(field)[1:2] = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        0 ~ 0.1 * Δ(w[1]) - 0.1 * w[1] + 5.0 * w[2] + 0.5 * (kind == A)
        0 ~ 0.1 * Δ(w[2]) - w[2] - 5.0 * w[1]
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FcFeed begin
    @kinds medium A[frozen]
    @parameters k = 0.5
    @variables begin
        e(field) = 0.0
        u(field) = 0.0
        v(field) = 0.0
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(e) ~ 0.1 * Δ(e) - e + 0.5 * v + 0.5 * (kind == A)
        0 ~ 0.1 * Δ(u) - u + k * v + 0.2 * e
        0 ~ 0.1 * Δ(v) - v - k * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FcHalf begin
    @kinds medium A[frozen]
    @variables begin
        u(field) = 0.0
        v(field) = 0.0, [lattice_storage = Float16]
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        0 ~ 0.1 * Δ(u) - u + 0.5 * v + 0.5 * (kind == A)
        0 ~ 0.1 * Δ(v) - v - 0.5 * u
    end
    @sweep Metropolis(; temperature = 1.0)
end
fc_site(integ, names) = [copy(Array(getproperty(current_state(integ).site, n))) for n in names]
function fc_runA(M, k, names; kw...)
    integ = init(PottsProblem(M(; name = :f), fi_op((12, 10)), (0, k); kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); fc_site(integ, names)) for _ in 1:k], integ
end
function fc_runB(M, k, names; alg, kw...)
    bp = Potts.LatticePDE.discretize(Potts.fields(M(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((12, 10)); T = Float64);
        u0 = [n => zeros(12, 10) for n in names], tspan = (0, k), inputs = [:kind => fi_kin((12, 10))], kw...)
    s = Potts.LatticePDE.solve(bp, alg; saveat = 1.0)
    return [[s[n][i] for n in names] for i in 2:(k + 1)], s
end

@testset "F3-12d: coupled steady rows in A: solved together, equal to B bitwise; components equal scalars" begin
    a, integ = fc_runA(FcPair, 3, (:u, :v))
    rt = fi_rt(integ)
    @test integ.retcode == FiRC.Default && Potts.LatticeFields.Problems.coupled_solve(rt.cache) && rt.cache.newton == 1
    b, sb = fc_runB(FcPair, 3, (:u, :v); alg = QuasiSteady(; dt = 1.0))
    @test sb.retcode == FiRC.Success && a == b || (println("12d A=B ", maximum(abs, a[end][1] .- b[end][1])); false)
    @test fi_warm(integ) == 0
    # the steady state: the rate is 0 to the solver's tolerance (u is not 0: the cells' source)
    u, v = a[end]
    @test maximum(abs, u) > 0.01 && maximum(abs, v) > 0.01
    # components: the scalar spelling's run, bitwise
    _, ic = fc_runA(FcComp, 3, ())
    st = current_state(ic).site
    @test [Array(st.w_1), Array(st.w_2)] == a[end]
end

@testset "F3-12d: a coupled steady pair feeding back through a transient field in A, equal to B" begin
    a, integ = fc_runA(FcFeed, 4, (:e, :u, :v); field_solver = BackwardEuler())
    @test integ.retcode == FiRC.Default
    b, sb = fc_runB(FcFeed, 4, (:e, :u, :v); alg = BackwardEuler(; dt = 1.0))
    @test a == b || (println("12d feed ", maximum(abs, a[end][1] .- b[end][1])); false)
    # strong (k = 5): the rule's bound on the pair's joint gain does not hold; the routes say that
    # the steady rows must be rates for `BackwardEuler`
    m = try
        PottsProblem(FcFeed(; name = :f, k = 5.0), fi_op((12, 10)), (0, 3)); ""
    catch err
        sprint(showerror, err)
    end
    @test occursin("the steady fields `u`, `v` of one group read one another", m) &&
          occursin("for a `BackwardEuler` route, write the steady rows of `u`, `v` as rates `D(c) ~ rhs`", m) ||
          (println("12d strong A ", m); false)
end

@testset "F3-12d: a coupled steady group with a Float16 field is refused" begin
    @test_throws "the field `v` is stored in Float16, whose rounding is too coarse for the coupled solve's difference of the residual; give it `lattice_storage = Float32`" init(
        PottsProblem(FcHalf(; name = :f), fi_op((12, 10)), (0, 3)), SequentialCPM())
end
