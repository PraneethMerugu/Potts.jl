# F3-17 (F3 design §3.9): `[lattice_level = Coarse(k)]` on a field of `@potts_model`. The
# field's array is its grid's (one value per node of k×k sites), its equation runs there
# through the same lowering as front end B (`Potts.fields` → `discretize`), and a CPM read of
# the field at a site reads the node whose block holds the site, so `integral(c) / volume` is
# the cell's average over its sites. With σ frozen A equals B bitwise. Base 392dd404
# (~/lpwork/f3b6-nc-a.log): `lattice_level` is not an option of `variable` (every model errors).
using Potts: CorePotts

@potts_model FcMix begin
    @kinds medium A[frozen] B[frozen]
    @parameters begin
        Dc = 0.4
        kd = 0.3
        s = 0.5
    end
    @variables begin
        c(field) = 0.0, [lattice_level = Coarse(4)]
        e(field) = 0.0
        avg(cell) = 0.0
    end
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @equations begin
        D(c) ~ Dc * Δ(c) - kd * c + s * (kind == A) + 0.2 * e + 0.01 * x
        D(e) ~ 0.1 * Δ(e) - e + 0.5 * c
    end
    @bcs c ~ masked(kind == B, 2.0)
    @after_mcs avg ~ integral(c) / volume
    @sweep Metropolis(; temperature = 1.0)
end

# two frozen cells, A (rows 2:8, columns 2:6; 9 and 12 of 16 sites of blocks (1, 1) and (2, 1),
# 6 and 8 of (1, 2) and (2, 2): block (2, 2) is a tie, which A owns: the medium loses a tie) and
# B (rows 9:15, columns 6:12; the owner of blocks (3, 2), (3, 3), (4, 2), (4, 3))
function fc_sigma(dims = (16, 12))
    σ = zeros(Int32, dims)
    σ[2:8, 2:6] .= 1
    σ[9:15, 6:12] .= 2
    return σ
end
fc_op() = [ownership => fc_sigma(), kind => [:A, :B]]
fc_kin(σ = fc_sigma()) = Int32[s == 0 ? 0 : s for s in σ]          # kind number per site (A = 1, B = 2)
# A's fields and `avg` after each of `k` MCS
function fc_runA(k; field_solver = BackwardEuler())
    integ = init(PottsProblem(FcMix(; name = :f), fc_op(), (0, k); field_solver), SequentialCPM(); save_start = false)
    out = [(step!(integ); st = current_state(integ); (copy(Array(st.site.c)), copy(Array(st.site.e)), copy(st.cell.avg)))
           for _ in 1:k]
    return out, integ
end
function fc_runB(k; alg = BackwardEuler(; dt = 1.0))
    bp = Potts.LatticePDE.discretize(Potts.fields(FcMix(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((16, 12)); T = Float64, problem = :owned);
        u0 = [:c => zeros(4, 3), :e => zeros(16, 12)], tspan = (0, k), inputs = [:kind => fc_kin()])
    s = Potts.LatticePDE.solve(bp, alg; saveat = 1.0)
    return s[:c][2:end], s[:e][2:end]
end

@testset "F3-17: a Coarse(4) field in A equals B bitwise (σ frozen)" begin
    k = 4
    for (fs, alg) in ((BackwardEuler(), BackwardEuler(; dt = 1.0)), (ExplicitEuler(), ExplicitEuler(; dt = 1.0)))
        a, integ = fc_runA(k; field_solver = fs)
        bc, be = fc_runB(k; alg)
        @test size(a[1][1]) == (4, 3) && size(a[1][2]) == (16, 12)
        @test [x[1] for x in a] == bc
        @test [x[2] for x in a] == be
    end
    # the mask holds on B's blocks only
    a, _ = fc_runA(1)
    @test findall(==(2.0), a[1][1]) == CartesianIndex.([(3, 2), (4, 2), (3, 3), (4, 3)])
end

# an irregular domain (the lattice's) with a coarse field: a node is in it when most of its block is
@potts_model FcDom begin
    @structural_parameters begin
        domain = x -> x[2] <= 7.0 || x[1] <= 5.0
    end
    @kinds medium A[frozen]
    @variables c(field) = 0.0, [lattice_level = Coarse(4)]
    @lattice Lattice((16, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ 0.4 * Δ(c) - 0.3 * c * (kind == A) + 1.0
    @sweep Metropolis(; temperature = 1.0)
end

@testset "F3-17: a coarse field in an irregular domain: A equals B bitwise" begin
    σ = zeros(Int32, 16, 12); σ[2:4, 2:4] .= 1
    integ = init(PottsProblem(FcDom(; name = :d), [ownership => σ, kind => [:A]], (0, 3); field_solver = BackwardEuler()),
        SequentialCPM(); save_start = false)
    a = [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:3]
    dm = Array(current_state(integ).site.domain__in) .!= 0
    bp = Potts.LatticePDE.discretize(Potts.fields(FcDom(; name = :d)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((16, 12)); T = Float64, problem = :owned,
            domain = "domain__in"); u0 = [:c => zeros(4, 3)], tspan = (0, 3),
        inputs = [:kind => Int32.(σ), :domain__in => dm])
    @test a == Potts.LatticePDE.solve(bp, BackwardEuler(; dt = 1.0); saveat = 1.0)[:c][2:end]
    # the nodes whose block is mostly outside keep their value (0); the others moved
    out = [count(dm[(I[1] - 1) * 4 .+ (1:4), (I[2] - 1) * 4 .+ (1:4)]) <= 8 for I in CartesianIndices((4, 3))]
    @test any(out) && all(a[end][out] .== 0.0) && all(a[end][.!out] .> 0.0)
end

@testset "F3-17: a site read of a coarse field reads its block's node; integral(c)/volume is the cell average" begin
    a, integ = fc_runA(3)
    σ = fc_sigma()
    # (the default order runs `after_mcs` before `fields`: `avg` reads `c` of the MCS before)
    c, avg = a[end - 1][1], a[end][3]
    # the hand average: each site of the cell reads the node of its block
    hand = [sum(c[(i - 1) ÷ 4 + 1, (j - 1) ÷ 4 + 1] for i in 1:16, j in 1:12 if σ[i, j] == n) / count(==(n), σ) for n in 1:2]
    @test avg ≈ hand rtol = 1e-14
    # (not the average of the nodes the cell touches: cell A covers 35 sites over 4 blocks unevenly)
    touched = [sum(c[I] for I in unique(CartesianIndex((i - 1) ÷ 4 + 1, (j - 1) ÷ 4 + 1)
                                       for i in 1:16, j in 1:12 if σ[i, j] == n)) /
               length(unique(CartesianIndex((i - 1) ÷ 4 + 1, (j - 1) ÷ 4 + 1) for i in 1:16, j in 1:12 if σ[i, j] == n))
               for n in 1:2]
    @test abs(avg[1] - touched[1]) > 1e-6
    @test Potts._coarse_site(LinearIndices((16, 12))[9, 5], (16, 12), 2) == LinearIndices((4, 3))[3, 2]
    @test Potts._coarse_site(LinearIndices((8, 1, 4))[6, 1, 3], (8, 1, 4), 1) == LinearIndices((4, 1, 2))[3, 1, 2]
end

@testset "F3-17: lattice_level in A: arrays, refusals and routes" begin
    # the operating point gives a coarse field its grid's array
    a0 = [Float64(i + 10j) for i in 1:4, j in 1:3]
    integ = init(PottsProblem(FcMix(; name = :f), [fc_op(); :c => a0], (0, 1)), SequentialCPM())
    # (the at-init clamp holds the masked value on B's blocks)
    m = falses(4, 3); m[3:4, 2:3] .= true
    @test Array(current_state(integ).site.c) == ifelse.(m, 2.0, a0)
    msg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    m = msg(() -> PottsProblem(FcMix(; name = :f), [fc_op(); :c => zeros(16, 12)], (0, 1)))
    @test occursin("`c` has `lattice_level = Coarse(4)`", m) && occursin("of size (4, 3)", m)
    # a field of the lattice given a coarsened array is refused as before F3-17 (review r1 M1: cb20be97
    # built it, and its kernels wrote past the 8×6 array; ~/lpwork/f3b6r-nc-m1.log)
    m = msg(() -> PottsProblem(FcMix(; name = :f), [fc_op(); :e => zeros(8, 6)], (0, 1)))
    @test m == "ArgumentError: site quantity `e` has size (8, 6), lattice (16, 12)"
    m = msg(() -> PottsProblem(FcMix(; name = :f), [fc_op(); :e => zeros(16, 11)], (0, 1)))
    @test m == "ArgumentError: site quantity `e` has size (16, 11), lattice (16, 12)"
    # a state given as such skips those checks: the binding asserts each array's length
    p = PottsProblem(FcMix(; name = :f), fc_op(), (0, 1))
    st = p.u0
    bad = CorePotts.CPMState(st.σ, st.cell, merge(st.site, (; e = zeros(8, 6))), st.model, st.history)
    m = msg(() -> init(remake(p; u0 = bad), SequentialCPM()))
    @test occursin("field array `e` has 48 values; its grid has 192 sites", m) || (println("M1 bind: ", m); false)
    # a number is not a grid; a site variable has no level; a copy cannot write a node
    m = msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :field; lattice_level = 4))
    @test occursin("`lattice_level = Coarse(4)`", m)
    m = msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :site; lattice_level = Coarse(2)))
    @test occursin("`lattice_level` applies to fields", m)
    m = msg(() -> Potts.variable(only(Potts.Symbolics.@variables q), :field; lattice_level = Coarse(2),
        clear_on_ownership_change = true))
    @test occursin("drop one of the two options", m)
    # a copy writes one site, which has no node of its own
    oc = eval(:(@potts_model _FcOnCopy begin
        @kinds medium A
        @variables c(field) = 0.0, [lattice_level = Coarse(2)]
        @lattice Lattice((8, 8))
        @energy cells => (volume - 9.0)^2
        @equations D(c) ~ 0.1 * Δ(c) - c
        @on_copy c[target] ~ 1.0
        @sweep Metropolis(; temperature = 1.0)
    end))
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
    m = msg(() -> PottsProblem(Base.invokelatest(oc; name = :o), [ownership => σ, kind => [:A]], (0, 1)))
    @test occursin("@on_copy cannot assign `c`", m) && occursin("write the change as a source in its equation", m)
    # review r1 N2: a refusal of the lowering names the equation it was lowering (not the first),
    # with a condition's parentheses and the kind's name (base cb20be97, ~/lpwork/f3b6r-nc-n2.log:
    # `in @equations Differential(t, 1)(c(t)) ~ kind == 1 - c(t) + …`)
    fw = eval(:(@potts_model _FcWhere begin
        @kinds medium A
        @variables begin
            c(field) = 0.0
            u(field) = 0.0
        end
        @lattice Lattice((8, 8))
        @energy cells => (volume - 9.0)^2
        @equations begin
            D(c) ~ 0.1 * Δ(c) - c
            D(u) ~ (kind == A) - u + 0.1 * Δ(kind)
        end
        @sweep Metropolis(; temperature = 1.0)
    end))
    σw = zeros(Int32, 8, 8); σw[3:5, 3:5] .= 1
    m = msg(() -> PottsProblem(Base.invokelatest(fw; name = :w), [ownership => σw, kind => [:A]], (0, 1)))
    @test occursin("\n  in @equations Differential(t, 1)(u(t)) ~ ", m) && occursin("(kind == A) - u(t)", m) || (println("N2: ", m); false)
    # Coarse(1) is the lattice itself (no option kept)
    v = Potts.variable(only(Potts.Symbolics.@variables q), :field; lattice_level = Coarse(1))
    @test !haskey(Potts.info(v).options, :lattice_level)
end

# Review r1 M2: a coarse field's source that reads a fine field nonlinearly receives the fine
# integral of the source (the mean of the whole subterm, each fine read at its site), in A as in
# B. Base cb20be97 (~/lpwork/f3b6r-nc-m2a.log): `f(mean g)`, off by up to 75%.
@potts_model FcMass begin
    @kinds medium A[frozen] B[frozen]
    @parameters S[kind] = [1.0, 2.0, 5.0]
    @variables begin
        g(field) = 0.0
        m1(field) = 0.0, [lattice_level = Coarse(4)]
        m2(field) = 0.0, [lattice_level = Coarse(4)]
        m3(field) = 0.0, [lattice_level = Coarse(4)]
        m4(field) = 0.0, [lattice_level = Coarse(4)]
        m5(field) = 0.0, [lattice_level = Coarse(4)]
        m6(field) = 0.0, [lattice_level = Coarse(4)]
    end
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @equations begin
        g ~ 0.5 + 0.45 * sin(0.7 * x + 0.3 * y)
        D(m1) ~ g
        D(m2) ~ max(g - 0.5, 0)
        D(m3) ~ g^2
        D(m4) ~ exp(g)
        D(m5) ~ S[kind] * g
        D(m6) ~ g / (0.2 + g)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@testset "review r1 M2: a coarse source of a fine field receives its fine integral (A)" begin
    integ = init(PottsProblem(FcMass(; name = :m), fc_op(), (0, 1); field_solver = ExplicitEuler()), SequentialCPM();
        save_start = false)
    step!(integ)
    st = current_state(integ)
    G = Array(st.site.g)
    @test size(G) == (16, 12) && size(Array(st.site.m1)) == (4, 3) && length(unique(G)) > 10
    Sk = [1.0, 2.0, 5.0][fc_kin() .+ 1]
    want = (sum(G), sum(max.(G .- 0.5, 0)), sum(G .^ 2), sum(exp.(G)), sum(Sk .* G), sum(G ./ (0.2 .+ G)))
    for (i, w) in enumerate(want)
        got = sum(Array(getproperty(st.site, Symbol(:m, i)))) * 16
        @test isapprox(got, w; rtol = 1e-13) || (println("M2 (A) m", i, ": ", got, " ", w); false)
    end
end

# F3-22 (F3 design §5 F3-22): a spatial operator across grids in A. `v` is fine, `c` is coarse:
# the coarse row reads the block mean of the fine Laplacian, and the fine row `u` the coarse
# `Δ(c)` at its block's node. The direct form is the aux field of the manual route (bitwise),
# A equals B (`Potts.fields`) bitwise, the added aux field is the binding's scratch (not in the
# state), and a ForwardDiff Dual runs through it (F3-21b's shadow store). Base 5316bf1c
# (~/lpwork/f322/nc-*.log): the direct form is refused ("a spatial operator reads its field on
# that field's own grid").
using ForwardDiff: ForwardDiff
@potts_model FcXd begin
    @kinds medium A[frozen] B[frozen]
    @parameters Dc = 0.4
    @variables begin
        c(field) = 0.0, [lattice_level = Coarse(4)]
        v(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @equations begin
        D(v) ~ 0.1 * Δ(v) - v + 0.5 * (kind == A)
        D(c) ~ Dc * Δ(c) - 0.3 * c + 0.5 * Δ(v)
        D(u) ~ 0.2 * Δ(u) - u + 0.5 * Δ(c) + 0.1 * DivKGrad(:harmonic)(1 + x, c)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model FcXr begin
    @kinds medium A[frozen] B[frozen]
    @parameters Dc = 0.4
    @variables begin
        c(field) = 0.0, [lattice_level = Coarse(4)]
        X(field) = 0.0
        L(field) = 0.0, [lattice_level = Coarse(4)]
        M(field) = 0.0, [lattice_level = Coarse(4)]
        v(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((16, 12); boundary = Closed())
    @energy cells => (volume - 20.0)^2
    @equations begin
        D(v) ~ 0.1 * Δ(v) - v + 0.5 * (kind == A)
        X ~ Δ(v)
        L ~ Δ(c)
        M ~ DivKGrad(:harmonic)(1 + x, c)
        D(c) ~ Dc * Δ(c) - 0.3 * c + 0.5 * X
        D(u) ~ 0.2 * Δ(u) - u + 0.5 * L + 0.1 * M
    end
    @sweep Metropolis(; temperature = 1.0)
end
fx_run(M, k, fs; ps = Pair[]) = begin
    integ = init(PottsProblem(M(; name = :x), [fc_op(); ps], (0, k); field_solver = fs, seed = 3), SequentialCPM(); save_start = false)
    [(step!(integ); st = current_state(integ).site; map(a -> copy(Array(a)), (st.c, st.v, st.u))) for _ in 1:k]
end

@testset "F3-22: a spatial operator across grids in A is the manual route, A equals B, the aux is scratch" begin
    tight = DevicePCG(; rtol = 1e-12, budget = 64)
    # (an explicit count, a minimum: the default count works too since review r1, the rows read one way)
    for fs in (ExplicitEuler(; substeps = 40), BackwardEuler(; inner = tight), CrankNicolson(; inner = tight))
        a, r = fx_run(FcXd, 3, fs), fx_run(FcXr, 3, fs)
        @test a == r && all(maximum(abs, a[end][i]) > 0 for i in 1:3)            # bitwise, and the rows moved
        @test size(a[1][1]) == (4, 3) && size(a[1][2]) == (16, 12)
    end
    st = current_state(init(PottsProblem(FcXd(; name = :x), fc_op(), (0, 1); field_solver = BackwardEuler()), SequentialCPM())).site
    @test !any(k -> occursin('(', string(k)), keys(st))                         # no hidden aux in the state
    # A equals B: `Potts.fields` through `discretize`, the CPM frozen
    for (fs, alg) in ((BackwardEuler(), BackwardEuler(; dt = 1.0)), (ExplicitEuler(; substeps = 40), ExplicitEuler(; dt = 1.0, substeps = 40)))
        a = fx_run(FcXd, 3, fs)
        bp = Potts.LatticePDE.discretize(Potts.fields(FcXd(; name = :x)),
            Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((16, 12)); T = Float64, problem = :owned),
            ; u0 = [:c => zeros(4, 3), :v => zeros(16, 12), :u => zeros(16, 12)], tspan = (0, 3), inputs = [:kind => fc_kin()])
        s = Potts.LatticePDE.solve(bp, alg; saveat = 1.0)
        @test [x[1] for x in a] == s[:c][2:end] && [x[2] for x in a] == s[:v][2:end] && [x[3] for x in a] == s[:u][2:end]
    end
end

@testset "F3-22: a Dual runs through a cross-grid term in A (against central differences)" begin
    tight = DevicePCG(; rtol = 1e-11, budget = 60)
    W = [0.01 * (i + 2j) for i in 1:16, j in 1:12]
    q(sol) = sum(W .* sol.u[end].site.u)
    drun(fs, p) = solve(PottsProblem(FcXd(; name = :x), [fc_op(); :Dc => p], (0, 6); field_solver = fs, seed = 3), SequentialCPM(); saveat = 0:2:6)
    for fs in (ExplicitEuler(; substeps = 40), BackwardEuler(; inner = tight))
        d = drun(fs, ForwardDiff.Dual(0.4, 1.0))
        h = 1e-4 * 0.4
        fd = (q(drun(fs, 0.4 + h)) - q(drun(fs, 0.4 - h))) / 2h
        @test ForwardDiff.partials(q(d), 1) ≈ fd rtol = 1e-6
        @test abs(fd) > 0
        # the Dual run is the primal run: its field values, bit for bit
        @test ForwardDiff.value.(d.u[end].site.u) == drun(fs, 0.4).u[end].site.u
    end
end
