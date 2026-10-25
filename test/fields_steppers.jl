# F3-10 (F3 design §3.3, §3.7): `CrankNicolson` in front end A, through the runtime of front
# end B (the models and helpers of fields_implicit.jl). With σ frozen A equals B bitwise;
# Crank–Nicolson damps the first substep of every MCS when the group reads the CPM or its mask
# moves. Base (69bef544, ~/lpwork/f3b4-nc10-a-base.log): `CrankNicolson` is not defined in
# Potts (every testset errors).

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
