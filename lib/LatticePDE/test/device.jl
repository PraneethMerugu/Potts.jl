# The §7.4 problem on a device (LATTICEPDE_GPU = metal | rocm), Float32: the owned solve on
# device arrays equals the host executor's bit for bit on normal-range values (128²; the
# device flushes subnormals), and the verbatim 512² run completes with automatic substeps.
using KernelAbstractions: KernelAbstractions
using LatticeFields: LatticeFields
const pgpu = lowercase(get(ENV, "LATTICEPDE_GPU", ""))
if pgpu == "metal"
    using Metal: Metal
    const PDEV = Metal.MetalBackend()
else
    using AMDGPU: AMDGPU
    const PDEV = AMDGPU.ROCBackend()
end

@testset "§7.4 on $pgpu" begin
    @parameters Dc7 = 1e-3 k7 = 0.1
    rd = PDESystem(D(ce) ~ Dc7 * Δ(ce) - k7 * ce,
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
        [t ∈ Interval(0, 10), x ∈ Interval(0, 1), y ∈ Interval(0, 1)], [t, x, y], [ce], [Dc7, k7]; name = :rd)
    run(n, backend; T = 1.0) = solve(discretize(remake_t(rd, T), LatticeDiscretization(Grid((n, n)); T = Float32,
        backend)), ExplicitEuler(dt = 1.0f-2); saveat = T / 2)
    remake_t(s, T) = PDESystem(s.eqs, s.bcs, [t ∈ Interval(0, T), x ∈ Interval(0, 1), y ∈ Interval(0, 1)],
        [t, x, y], [ce], [Dc7, k7]; name = :rd)
    sd, sh = run(128, PDEV), run(128, KernelAbstractions.CPU())
    ulps(a, b) = maximum(abs.(Int64.(reinterpret(Int32, a)) .- Int64.(reinterpret(Int32, b))))
    d = [count(sd[ce, i] .!= sh[ce, i]) for i in eachindex(sd.t)]
    u = maximum(i -> ulps(sd[ce, i], sh[ce, i]), eachindex(sd.t))
    @info "§7.4 128² device vs host ($pgpu): differing words per save $d of $(128^2), max $u ulp"
    big = [count((sd[ce, i] .!= sh[ce, i]) .& (abs.(sh[ce, i]) .>= 1.0f-30)) for i in eachindex(sd.t)]
    sub = [extrema(abs.(sh[ce, i][sd[ce, i] .!= sh[ce, i]]); init = (0.0f0, 0.0f0)) for i in eachindex(sd.t)]
    @info "  differing words with |c| ≥ 1e-30: $big; |c| range of the differing words: $sub"
    # bit for bit on every normal-range word; the device flushes subnormals (Metal FTZ), so
    # the far tail of the front (|c| < 1e-30) may differ, by less than 1e-30
    @test sd.t == sh.t && all(==(0), big)
    @test all(i -> maximum(abs, sd[ce, i] .- sh[ce, i]) < 1.0f-30, eachindex(sd.t))
    t512 = @elapsed (s = run(512, PDEV; T = 10.0))
    @test substep_counts(s)[1] == 12 && all(isfinite, s[ce, end])
    @info "§7.4 verbatim size on $pgpu: 512², 1000 steps × 12 substeps in $(round(t512; digits = 2)) s (incl. compile)"
end

# F3-00 review r1 S7: the aux fields are evaluated at each save on the device (one aux launch on
# device arrays, before the copy) and at `integ[K]`: `K ~ 2c + t` holds at every save and
# equals the host executor's run
@testset "F3-00: B evaluates the aux fields at the saves on $pgpu" begin
    @parameters Da7 = 0.1 ka7 = 1.0
    sys = psys([D(ce) ~ Da7 * Δ(ce) - ka7 * ce, Ke ~ 2ce + t], [c(0, x, y) ~ 1.0 + x], [Da7, ka7]; dvs = [ce, Ke])
    mk(be) = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float32, backend = be))
    sd = solve(mk(PDEV), ExplicitEuler(; dt = 0.25f0); saveat = 0.5)
    sh = solve(mk(KernelAbstractions.CPU()), ExplicitEuler(; dt = 0.25f0); saveat = 0.5)
    @test sd.retcode == ReturnCode.Success && sd.t == sh.t == [0.0, 0.5, 1.0]
    for i in eachindex(sd.t)
        @test Array(sd[Ke, i]) ≈ 2 .* Array(sd[ce, i]) .+ Float32(sd.t[i]) rtol = 1.0f-6
        @test Array(sd[Ke, i]) ≈ Array(sh[Ke, i]) rtol = 1.0f-5
    end
    ig = init(mk(PDEV), ExplicitEuler(; dt = 0.25f0))
    step!(ig)
    @test Array(ig[Ke]) ≈ 2 .* Array(ig[ce]) .+ 0.25f0 rtol = 1.0f-6
end

@testset "number types on $pgpu (P5)" begin
    # Dual{Float32} through the owned path on the device equals the host derivative
    sys = nsys()
    mk(backend) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((16, 8)); T = Float32, backend)))
    alg = ExplicitEuler(; dt = 0.01)
    i = pidx(mk(KernelAbstractions.CPU()), Dn)
    Jdev(prob) = v -> sum(Array(solve(remake(prob; p = withp(prob.p, i, v)), alg).u[end]))
    pd, ph = mk(PDEV), mk(KernelAbstractions.CPU())
    dd, dh = ForwardDiff.derivative(Jdev(pd), pd.p[i]), ForwardDiff.derivative(Jdev(ph), ph.p[i])
    @test dd isa Float32 && isapprox(dd, dh; rtol = 1e-5) && dd != 0
    # default state type: Float32 on a device
    @test eltype(discretize(sys, LatticeDiscretization(Grid((8, 4)); backend = PDEV)).u0) == Float32
    @test_throws ArgumentError discretize(sys, LatticeDiscretization(Grid((8, 4)); T = BigFloat, backend = PDEV))
    # Rodas5P on device arrays (Jacobian and time gradient through the right side)
    ode = discretize(psys([D(ce) ~ Dn * Δ(ce) - kn * ce + 0.1 * sin(ωn * t)],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [Dn, kn, gn, ωn]), LatticeDiscretization(Grid((8, 4)); T = Float32, backend = PDEV))
    host = discretize(psys([D(ce) ~ Dn * Δ(ce) - kn * ce + 0.1 * sin(ωn * t)],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [Dn, kn, gn, ωn]), LatticeDiscretization(Grid((8, 4)); T = Float32))
    r = solve(ode, Rodas5P(); abstol = 1e-4, reltol = 1e-4)
    rh = solve(host, Rodas5P(); abstol = 1e-4, reltol = 1e-4)
    @test SciMLBase.successful_retcode(r) && isapprox(Array(r.u[end]), rh.u[end]; rtol = 1e-3)
end

@testset "integ[c] is a device array on $pgpu (F1 round 5)" begin
    # rounds 2–4: a read-only wrapper (`FieldValues`) failed or hung on device operations
    # (scalar indexing; `v[1:2, 1]`, then `v[v .> 0]`, `vcat`, `hcat` hung); round 5 returns
    # the copy itself, a device array, as SciML does
    fs = PDESystem([D(ce) ~ -ce], [c(0, x, y) ~ 1.0], [t ∈ Interval(0, 1), x ∈ Interval(0, 1), y ∈ Interval(0, 1)],
        [t, x, y], [ce], Num[]; name = :fv)
    ig = init(discretize(fs, LatticeDiscretization(Grid((8, 8)); T = Float32, backend = PDEV)),
        ExplicitEuler(; dt = 0.1f0))
    v = ig[ce]
    @test KernelAbstractions.get_backend(v) == PDEV && size(v) == (8, 8)
    h = Array(v)
    # each device operation runs on another task under a timeout, so a hang fails fast
    function within(f, s = 120.0)
        r = Threads.@spawn f()
        timedwait(() -> istaskdone(r), s) === :ok || return false
        return fetch(r)
    end
    @test within(() -> Array(v[v .> 0]) == vec(h))
    @test within(() -> Array(vcat(v, v)) == vcat(h, h) && Array(hcat(v, v)) == hcat(h, h))
    @test within(() -> v == v && Array(v) == h && h ≈ Array(v) && isapprox(v, v))
    @test within(() -> Array(v[1:2, 1]) == h[1:2, 1] && Array(v[:, 2]) == h[:, 2] && Array(v[2:3, 4:5]) == h[2:3, 4:5])
    @test within(() -> sum(view(v, :, 1)) == 8 && sum(vec(v)) == 64 && Array(vec(v) .+ 1) == fill(2.0f0, 64))
    @test within(() -> sum(v) == 64 && maximum(v) == 1 && minimum(v) == 1 && Array(v .+ 1) == fill(2.0f0, 8, 8))
    @test within(() -> convert(Matrix{Float32}, Array(v)) == h && Matrix(Array(v)) isa Matrix{Float32} &&
                       Array{Float64}(Array(v)) == ones(8, 8))
    @test within(() -> (hh = zeros(Float32, 8, 8); copyto!(hh, v); hh == h))
    @test within(() -> !isempty(sprint(show, MIME"text/plain"(), v)))
    # a write into the copy changes nothing; `.=` is named
    @test within(() -> (v .= 3.0f0; Array(ig[ce]) == h))
    @test occursin("integ[c] = values", emsg(() -> (ig[ce] .= 2.0f0)))
end

@testset "an integer input given as a device array (F1 round 4)" begin
    # round 3: the integer check indexed the device array in a kernel ("KernelError")
    n = 8
    msys = ssys([D(ce) ~ ifelse(qe == 1, 1.0, 0.0)], [c(0, x, y) ~ 0.0], [ce, qe], Num[])
    dk(vals) = (a = KernelAbstractions.allocate(PDEV, Int32, n, n); copyto!(a, vals); a)
    K = Int32[i <= 4 ? 1 : 0 for i in 1:n, j in 1:n]
    mk(k) = discretize(msys, LatticeDiscretization(Grid((n, n)); T = Float32, backend = PDEV);
        inputs = [qe => k])
    s = solve(mk(dk(K)), ExplicitEuler(; dt = 0.1f0))
    @test Array(s[:c, end]) ≈ Float32.(K)
    ig = init(mk(dk(K)), ExplicitEuler(; dt = 0.1f0))
    ig[qe] = dk(zeros(Int32, n, n))
    @test Array(ig[qe]) == zeros(Int32, n, n)
    # a value outside Int32 is named, from a device array of a wider type
    w = KernelAbstractions.allocate(PDEV, Int64, n, n)
    copyto!(w, fill(Int64(3)^30, n, n))
    err = emsg(() -> mk(w))
    @test occursin("`kq` holds integer values", err) && !occursin("KernelError", err)
end

@testset "a Bool input given as a device array (F1 round 5)" begin
    # round 4: scalar indexing
    n = 8
    dsys = ssys([D(ce) ~ 1.0], [c(0, x, y) ~ 0.0], [ce, de], Num[])
    half = [i <= 4 for i in 1:n, j in 1:n]
    db = KernelAbstractions.allocate(PDEV, Bool, n, n)
    copyto!(db, half)
    mk(m) = discretize(dsys, LatticeDiscretization(Grid((n, n)); T = Float32, backend = PDEV,
        domain = dm); inputs = [dm => m])
    r = Threads.@spawn Array(solve(mk(db), ExplicitEuler(; dt = 0.1f0))[:c, end])
    @test timedwait(() -> istaskdone(r), 300.0) === :ok && fetch(r) ≈ Float32.(half)
    d2 = KernelAbstractions.allocate(PDEV, Int32, n, n)
    copyto!(d2, fill(Int32(2), n, n))
    @test occursin("`dm` holds a Bool mask", emsg(() -> mk(d2)))
    # F2-09: the input reads back as a Bool array on the device (base: UInt8; `count` and `any`
    # threw a non-boolean TypeError, `.!` a MethodError)
    m = init(mk(db), ExplicitEuler(; dt = 0.1f0))[dm]
    @test eltype(m) == Bool && typeof(KernelAbstractions.get_backend(m)) == typeof(PDEV)
    @test Array(m) == half && count(m) == 4n && any(m) && !all(m) && Array(.!m) == .!half
end

@testset "F3-04: B reads the status word at the saves on $pgpu" begin
    p = discretize(gsys(), LatticeDiscretization(Grid((8, 8)); T = Float32, backend = PDEV))
    ig = init(p, WStub(0.01; code = 2, at = 3); saveat = 0.05)
    s = @test_logs (:warn, r"the solve failed in window 3") solve!(ig)
    @test s.retcode == ReturnCode.ConvergenceFailure && ig.iter == 5           # the first save after window 3
    s = solve(p, WStub(0.01; code = 1, at = 3); saveat = 0.05)
    @test s.retcode == ReturnCode.StalledSuccess && s.stats.solves == 10
end

# F3-15: the implicit algorithms of F3-07…F3-12 on the device in Float32 against the host form
# of the same problem (the host executor, the same Float32 program; a fixed `newton`, so the
# host's early stop does not enter): field and numeric rows, advection (a defect correction), a
# switch, a Robin face, Crank–Nicolson's and BDF2's stages, a QuasiSteady window and a steady
# start. The device and the host run the same reduction trees (the host's emulated form), so
# they agree to the D-158 tolerance (`rtol = 1e-12` of the field's scale; measured below).
@testset "F3-15: implicit algorithms on $pgpu equal the host form (Float32)" begin
    @parameters Di = 0.05 ki = 1.0 vi = 0.5
    per = [c(t, x, 0) ~ c(t, x, 1), c(t, 0, y) ~ c(t, 1, y)]
    field = psys([D(ce) ~ DivKGrad(:harmonic)(Di * (1 + x), ce) - ki * ce + 1], [c(0, x, y) ~ x * y], [Di, ki])
    adv = psys([D(ce) ~ Di * Δ(ce) - Advect(Upwind1())([vi, 0.0], ce) - ki * ce + 1], [c(0, x, y) ~ x * y; per], [Di, ki, vi])
    sw = psys([D(ce) ~ Di * Δ(ce) - ki * max(ce - 0.3, 0) + 0.5], [c(0, x, y) ~ x * y], [Di, ki])
    rob = psys([D(ce) ~ Di * Δ(ce) - ki * ce + 1], [c(0, x, y) ~ x * y, 1.5 * c(t, 1, y) + Differential(x)(c(t, 1, y)) ~ 0.2], [Di, ki])
    cases = [("BackwardEuler, field row", field, BackwardEuler(; dt = 0.1, newton = 1)),
             ("BackwardEuler, advection", adv, BackwardEuler(; dt = 0.1, newton = 6)),
             ("BackwardEuler, switch", sw, BackwardEuler(; dt = 0.1, newton = 2)),
             ("BackwardEuler, Robin face", rob, BackwardEuler(; dt = 0.1, newton = 1)),
             ("CrankNicolson", field, CrankNicolson(; dt = 0.1, newton = 1)),
             ("BDF2", field, BDF2(; dt = 0.1, newton = 1)),
             ("QuasiSteady", field, QuasiSteady(; dt = 0.1, newton = 1)),
             ("BackwardEuler, steady start", field, BackwardEuler(; dt = 0.1, newton = 1, init = :steady))]
    mk(sys, be) = discretize(sys, LatticeDiscretization(Grid((32, 32)); T = Float32, backend = be))
    for (name, sys, alg) in cases
        sd = solve(mk(sys, PDEV), alg; saveat = 0.5)
        sh = solve(mk(sys, KernelAbstractions.CPU()), alg; saveat = 0.5)
        @info "F3-15 $name: retcodes $(sd.retcode) (device), $(sh.retcode) (host); saves $(sd.t), $(sh.t)"
        @test sd.retcode == sh.retcode && sd.t ≈ sh.t
        rel = maximum(i -> maximum(abs, Array(sd[ce, i]) .- sh[ce, i]) / maximum(abs, sh[ce, i]), eachindex(sd.t))
        @info "F3-15 $name: device vs host (Float32) max relative difference $rel"
        @test rel <= 1e-12
    end
    # control: the comparison sees a change of one Newton iteration (the advection case)
    sd = solve(mk(adv, PDEV), BackwardEuler(; dt = 0.1, newton = 5); saveat = 0.5)
    sh = solve(mk(adv, KernelAbstractions.CPU()), BackwardEuler(; dt = 0.1, newton = 6); saveat = 0.5)
    @test maximum(abs, Array(sd[ce, end]) .- sh[ce, end]) / maximum(abs, sh[ce, end]) > 1e-12
end

# F3-15, batch 3 review R1: under the automatic Newton count the device closes a gate once every
# row met the tolerance (the later iterations' residuals are zeroed, so their solves are done at
# setup and the update adds 0): the device's field is the host's early-stop form, and the gated
# iterations cost launches only. The advection case of R1 (a site-varying velocity, `newton`
# from rule 2). Base f5641ce1: no gate, the device ran every iteration (measured below).
@testset "F3-15 (R1): the device stops correcting once every row converged ($pgpu)" begin
    @parameters Dg = 0.01
    sys = psys([D(ce) ~ Dg * Δ(ce) - Advect(Upwind1())([2 * (1 + x), 0.0], ce)], [c(0, x, y) ~ x * y], [Dg]; T = 0.1)
    mk(be, n) = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float32, backend = be))
    alg = BackwardEuler(; dt = 0.05)
    sd, sh = solve(mk(PDEV, 32), alg), solve(mk(KernelAbstractions.CPU(), 32), alg)
    ig = init(mk(PDEV, 32), alg)
    cc = only(ig.runtimes).cache
    @test cc.gate !== nothing && cc.newton > 2               # the gate is on (automatic count, several iterations)
    rel = maximum(abs, Array(sd[ce, end]) .- sh[ce, end]) / maximum(abs, sh[ce, end])
    @info "F3-15 R1: device vs host (early stop) max relative difference $rel; newton $(cc.newton)"
    @test sd.retcode == sh.retcode == ReturnCode.Success && rel <= 1e-5
    # the device counts the solves that ran, as the host (batch 5 review N3; 97045a1b counted the
    # gated ones too: 630 against 237 in the review's case)
    @test sd.stats.solves == sh.stats.solves
    # `field_stats` in the middle of a run reads the device's status words first (a device reads
    # them only at the saves and the end; 97045a1b gave 0 solves after 24 `step!` calls, the
    # timing's 75³ window): after two windows it gives the host's counts
    igd, igh = init(mk(PDEV, 32), alg), init(mk(KernelAbstractions.CPU(), 32), alg)
    foreach(_ -> (step!(igd); step!(igh)), 1:2)
    @test LatticeFields.Problems.field_stats(igd).solves == LatticeFields.Problems.field_stats(igh).solves > 0
    # the time of two windows at 128² with the gate and with every iteration run (`newton = k`)
    p = mk(PDEV, 128)
    run(a) = (solve(p, a); KernelAbstractions.synchronize(PDEV); @elapsed (solve(p, a); KernelAbstractions.synchronize(PDEV)))
    k = only(init(p, alg).runtimes).cache.newton
    tg, tk = minimum(_ -> run(alg), 1:3), minimum(_ -> run(BackwardEuler(; dt = 0.05, newton = k)), 1:3)
    @info "F3-15 R1 at 128² ($pgpu), $(init(p, alg).substeps) substeps per window: the gated run $(round(tg; digits = 3)) s, every iteration ($k) $(round(tk; digits = 3)) s"
end

# F3-16: a `Coarse(4)` field on the device (the features of coarse.jl's `csys`: the free-child
# mean fold and the whole-block mask (F4-15b), the moving masked Dirichlet, Robin and field
# faces). A fine field coupled to a `Coarse(2)` field (prolongation and restriction), Float32,
# against the host executor. Base 85794414: `Coarse` is not defined (the testset errors).
@testset "F3-16: coarse fields on $pgpu equal the host form (Float32)" begin
    cd4 = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cdev(..))), LatticePDE.LatticeLevel, Coarse(4)))
    q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
    mk(be) = cown(csys(cd4, q, g), CDIMS; T = Float32, backend = be, ins = [q(t, x, y) => CQ1, g(t, x, y) => CG])
    for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05, newton = 2))
        id, ih = init(mk(PDEV), alg), init(mk(KernelAbstractions.CPU()), alg)
        for n in 1:6
            n == 4 && (id[q(t, x, y)] = CQ2; ih[q(t, x, y)] = CQ2)          # the mask moves
            step!(id); step!(ih)
        end
        vd, vh = Array(id[cd4(t, x, y)]), ih[cd4(t, x, y)]
        @info "F3-16 $(nameof(typeof(alg))) on $pgpu: coarse field $(size(vd)), max |device − host| $(maximum(abs, vd .- vh))"
        @test size(vd) == (4, 4) && maximum(abs, vd .- vh) / maximum(abs, vh) <= 1e-6
    end
    cm = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(@variables cmdev(..))), LatticePDE.LatticeLevel, Coarse(2)))
    um = first(@variables umdev(..))
    sys = PDESystem([D(cm(t, x, y)) ~ 0.05 * Δ(cm(t, x, y)) - cm(t, x, y) + 0.7 * um(t, x, y),
            D(um(t, x, y)) ~ 0.02 * Δ(um(t, x, y)) - um(t, x, y) + 0.4 * cm(t, x, y)],
        [cm(0, x, y) ~ x, um(0, x, y) ~ y], cdom(), [t, x, y], [cm(t, x, y), um(t, x, y)], Num[]; name = :mixdev)
    for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.1))
        sd = solve(cown(sys, (32, 32); T = Float32, backend = PDEV), alg)
        sh = solve(cown(sys, (32, 32); T = Float32, backend = KernelAbstractions.CPU()), alg)
        for (v, n) in ((cm, 16), (um, 32))
            a, b = Array(sd[v(t, x, y), end]), sh[v(t, x, y), end]
            @test size(a) == (n, n) && maximum(abs, a .- b) / maximum(abs, b) <= 1e-6
        end
    end
end

# Review r1: CrankNicolson, BDF2, BackwardEuler(init = :steady) and QuasiSteady on a coarse field
# on the device equal the host form and the hand-coarsened twin (the reviewer's r3, Float32); and
# the block mean of a kind expression on the device (F4-15; it replaced the plurality owner)
@testset "review r1: coarse fields under CN, BDF2, QS and the kind fold on $pgpu" begin
    for steady in (false, true)
        algs = steady ? (QuasiSteady(; dt = 0.05),) :
               (CrankNicolson(; dt = 0.05), BDF2(; dt = 0.05), BackwardEuler(; dt = 0.05, init = :steady))
        for alg in algs
            out = map((PDEV, KernelAbstractions.CPU())) do be
                pc, ph, (c, ch, q, g) = ctwins(; steady, T = Float32, backend = be)
                ic, ih = init(pc, alg), init(ph, alg)
                for n in 1:6
                    if n == 4
                        # (F4-15b: the twin's mask input holds the predicate on whole blocks only,
                        # and its folded inputs are the free means)
                        ic[q(t, x, y)] = CQ2; ih[q(t, x, y)] = cwhole(CQ2)
                        ih[g(t, x, y)] = cfree(CG, CQ2 .== 3)
                        foreach(((v, a),) -> ih[v] = a, chand(CQ2))
                    end
                    step!(ic); step!(ih)
                end
                (Array(ic[c(t, x, y)]), Array(ih[ch(t, x, y)]), ic.retcode)
            end
            (d, dh, rd), (h, hh, rh) = out
            @info "review r1 $(nameof(typeof(alg))) on $pgpu: max |device − host| $(maximum(abs, d .- h)), |device − twin| $(maximum(abs, d .- dh))"
            @test rd == rh == SciMLBase.ReturnCode.Success
            @test maximum(abs, d .- dh) / maximum(abs, dh) <= 1e-5 && maximum(abs, d .- h) / maximum(abs, h) <= 1e-6
        end
    end
    lv(n) = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(Symbolics.variable(n; T = SymbolicUtils.FnType{Tuple, Real, Nothing})),
        LatticePDE.LatticeLevel, Coarse(CK)))
    cs, K2, M0 = lv(:csdev), lv(:K2dev), lv(:M0dev)
    q = first(@variables q(..)::Int32 [input = true])
    @parameters cRd[1:4] = [0.0, 1.0, 0.5, 0.25]
    qe = q(t, x, y)
    sys = PDESystem([D(cs(t, x, y)) ~ 0.05 * Δ(cs(t, x, y)) - cs(t, x, y) + at(cRd, qe + 1), K2(t, x, y) ~ at(cRd, qe + 1),
            M0(t, x, y) ~ (qe == 0)], [cs(0, x, y) ~ 0.0], cdom(), [t, x, y], [cs(t, x, y), K2(t, x, y), M0(t, x, y), qe], [cRd];
        name = :pldev)
    for alg in (ExplicitEuler(; dt = 0.05), BackwardEuler(; dt = 0.05))
        sd = solve(cown(sys, CDIMS; T = Float32, backend = PDEV, ins = [qe => CQT]), alg)
        sh = solve(cown(sys, CDIMS; T = Float32, backend = KernelAbstractions.CPU(), ins = [qe => CQT]), alg)
        @test Array(sd[K2(t, x, y), end]) == Float32.(cmean(Float64[0.0, 1.0, 0.5, 0.25][CQT .+ 1]))
        @test Array(sd[M0(t, x, y), end]) == Float32.(cmean(Float64.(CQT .== 0)))
        @test Array(sd[cs(t, x, y), end]) == sh[cs(t, x, y), end] || maximum(abs, Array(sd[cs(t, x, y), end]) .- sh[cs(t, x, y), end]) <= 1e-6
    end
end

@testset "F3-12d: the coupled steady solve on $pgpu equals the host bitwise" begin
    # Krylov.jl's FGMRES on `CoupledVector`s: fixed-order dot products on both backends, the
    # host's least-squares arithmetic shared, so device = host and a device rerun are bitwise.
    # Control: plain device arrays would reduce through rocBLAS, which differs from the host
    # (F3 design §5 F3-12d: 1e-15 in Float64)
    nl = PDESystem([D(cae) ~ 0.1Δ(cae) - 2.0 * cae / (0.5 + cae) + cbe + x, D(cbe) ~ 0.1Δ(cbe) - cbe + 0.5 * cae^2],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.3), [t, x, y], [cae, cbe], Any[]; name = :nldev)
    for (lab, s, alg) in (("q1 QS", q1(0.1, 5.0; steady = true), QuasiSteady(; dt = 0.1)), ("nonlinear QS", nl, QuasiSteady(; dt = 0.1)))
        for T in (Float32, Float64)
            mk(bk) = discretize(s, LatticeDiscretization(Grid((24, 20)); T, backend = bk))
            sd, sd2 = solve(mk(PDEV), alg; saveat = 0.1), solve(mk(PDEV), alg; saveat = 0.1)
            sh = solve(mk(KernelAbstractions.CPU()), alg; saveat = 0.1)
            @test sd.retcode == sh.retcode == SciMLBase.ReturnCode.Success
            same(a, b) = all(i -> Array(a[cae, i]) == Array(b[cae, i]) && Array(a[cbe, i]) == Array(b[cbe, i]), eachindex(sh.t))
            @test same(sd, sh) || (println("12d dev ", lab, " ", T, " ", maximum(abs, Array(sd[cae, end]) .- sh[cae, end])); false)
            @test same(sd, sd2)
        end
    end
end

@testset "F3-20: implicit algorithms on a hexagonal lattice on $pgpu equal the host form" begin
    # the six faces in the generated kernels, the bottom and the hex coarse build on the device:
    # BackwardEuler (numeric with a mask, a field row), CrankNicolson, BDF2, QuasiSteady and the
    # coupled steady solve, Float32 and Float64, against the host executor
    loop = PDESystem([0 ~ 0.1Δ(cae) - 1.0 * cae + 2.0 * cbe + x, 0 ~ 0.2Δ(cbe) - 2.0 * cbe - 1.5 * cae + y],
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 0.0], bdom(0.3), [t, x, y], [cae, cbe], Any[]; name = :hexdev)
    num = bsys([D(bce) ~ bD * Δ(bce) - bk * bce + x], [bc(0, x, y) ~ x * y, bce ~ masked(bqe == 2, 1.5)], [bD, bk]; T = 0.3)
    fld = bsys([D(bce) ~ (1 + x) * Δ(bce) - bk * bce + 1], [bc(0, x, y) ~ x * y], [bk]; T = 0.3)
    kind = Int32[(i + 2j) % 3 for i in 1:40, j in 1:40]
    cases = [("BackwardEuler", num, BackwardEuler(; dt = 0.1)), ("BackwardEuler, field row", fld, BackwardEuler(; dt = 0.1)),
             ("CrankNicolson", num, CrankNicolson(; dt = 0.1)), ("BDF2", fld, BDF2(; dt = 0.1)),
             ("QuasiSteady", num, QuasiSteady(; dt = 0.1)), ("coupled QuasiSteady", loop, QuasiSteady(; dt = 0.1))]
    for (name, sys, alg) in cases, T in (Float32, Float64)
        k = name == "coupled QuasiSteady" ? (cae, cbe) : (bce,)
        mk(be) = discretize(sys, LatticeDiscretization(Grid((40, 40); geometry = LatticeFields.IR.HEX); T, backend = be);
            inputs = name == "coupled QuasiSteady" ? [] : [bqe => kind])
        sd, sh = solve(mk(PDEV), alg; saveat = 0.1), solve(mk(KernelAbstractions.CPU()), alg; saveat = 0.1)
        @test sd.retcode == sh.retcode == SciMLBase.ReturnCode.Success
        same = all(v -> all(i -> Array(sd[v, i]) == Array(sh[v, i]), eachindex(sh.t)), k)
        @test same || (println("F3-20 hex dev ", name, " ", T, " ", maximum(abs, Array(sd[k[1]][end]) .- sh[k[1]][end])); false)
    end
end

# F3-21a: derivatives through the implicit solve on the device (Float64: ROCm only) equal the
# host's bit for bit (the primal solve and the tangent solves run the same kernels)
pgpu == "rocm" && @testset "F3-21a: Dual results on $pgpu equal the host's" begin
    @parameters kd = 0.7 Dd = 0.3 gd = 0.4
    @variables da(..) db(..)
    dae, dbe = da(t, x, y), db(t, x, y)
    ddom = [t ∈ Interval(0.0, 0.3), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    mr = PDESystem([D(ce) ~ Dd * Δ(ce) - kd * ce + gd * x], [c(0, x, y) ~ x * y, c(t, 0, y) ~ gd,
        ce ~ masked((x > 0.4) & (x < 0.6) & (y > 0.4) & (y < 0.6), 2 * kd), 1.5 * c(t, x, 0) - kd * Differential(y)(c(t, x, 0)) ~ 0.2],
        ddom, [t, x, y], [ce], [kd, Dd, gd]; name = :dm)
    cp = PDESystem([0 ~ Dd * Δ(dae) - dae + kd * dbe + x, 0 ~ 0.1 * Δ(dbe) - dbe - gd * dae + y], [da(0, x, y) ~ 0.0, db(0, x, y) ~ 0.0],
        ddom, [t, x, y], [dae, dbe], [kd, Dd, gd]; name = :dc)
    for (sys, alg, v) in ((mr, BackwardEuler(; dt = 0.1), ce), (mr, CrankNicolson(; dt = 0.1), ce),
                          (cp, QuasiSteady(; dt = 0.1, inner = DeviceGMRES(; rtol = 1e-12)), dae))
        u = map((KernelAbstractions.CPU(), PDEV)) do be
            pr = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64, backend = be))
            i = LatticePDE.Problems.SII.parameter_index(pr, kd)
            q = collect(ForwardDiff.Dual{Nothing, Float64, 1}, pr.p.values)
            q[i] = ForwardDiff.Dual(pr.p.values[i], 1.0)
            Array(solve(remake(pr; p = q), alg)[v, end])
        end
        vp(w) = [(ForwardDiff.value(d), ForwardDiff.partials(d, 1)) for d in w]
        @test vp(u[1]) == vp(u[2]) && any(d -> ForwardDiff.partials(d, 1) != 0, u[1])
    end
end

# F3-22: a spatial operator across grids on a device (the aux field of the operand's grid, the
# block fold of the fine one): the device run equals the host's, Float32, both directions, for
# the explicit and the implicit solvers (uses `xpair` of crossgrid.jl, which runs before).
@testset "F3-22: cross-grid operators on $pgpu equal the host" begin
    tight = DevicePCG(; rtol = 1.0f-6, budget = 64)
    for (name, op) in (("Δ", XOPS[1][2]), ("DivKGrad harmonic", XOPS[2][2]), ("Advect", XOPS[4][2]))
        p = xpair(op)
        for (pr, row) in ((p.cf, xu), (p.fc, xcc)), alg in (ExplicitEuler(; dt = 2.0f-3, substeps = 1), BackwardEuler(; dt = 1.0f-2, substeps = 1, inner = tight))
            run(backend) = solve(discretize(pr.dir, LatticeDiscretization(Grid((16, 16)); T = Float32, backend)), alg; saveat = [0.02])
            sd, sh = run(PDEV), run(KernelAbstractions.CPU())
            a, b = sd[xe(row), 2], sh[xe(row), 2]
            @info "F3-22 $pgpu $name $(row === xu ? "c to f" : "f to c") $(nameof(typeof(alg))): max |device − host| = $(maximum(abs, a .- b)) of $(maximum(abs, b))"
            @test maximum(abs, b) > 0 && maximum(abs, a .- b) <= 1.0f-5 * maximum(abs, b)
        end
    end
end

# F4-05/F4-06: an owned run on the device reads nothing back between saves with no callback; a
# callback's condition reads a host copy each window; an ensemble runs on the device
@testset "F4-05/F4-06: owned runs on $pgpu: host copies only for callbacks; an ensemble" begin
    p = discretize(cbsys(0.3), LatticeDiscretization(Grid((8, 8)); T = Float32, backend = PDEV))
    alg = ExplicitEuler(; dt = 0.01f0)
    @test solve(p, alg).stats.syncs == 0
    cb = SciMLBase.DiscreteCallback((u, t, i) -> true, i -> nothing; save_positions = (false, false))
    @test solve(p, alg; callback = cb).stats.syncs == 30
    ep = SciMLBase.EnsembleProblem(p; prob_func = (q, ctx) -> remake(q; p = [bk => 1.0 + ctx.sim_id]))
    es = solve(ep, alg, SciMLBase.EnsembleSerial(); trajectories = 2)
    @test all(i -> es.u[i].u[end] == solve(remake(p; p = [bk => 1.0 + i]), alg).u[end], 1:2)
end

# F4-12b: Robin coefficients that vary by site and in time on a device (Float32): the value
# fields, the field row's per-site diagonal (one sign, and both signs with a Newton count), the
# time-varying α rebuilt at each stage, and ExplicitEuler's count re-bounded each window equal
# the host's
@testset "F4-12b: per-site and time-varying Robin faces on $pgpu equal the host" begin
    @parameters Dr = 0.05 kr = 1.0
    site = psys([D(ce) ~ Dr * Δ(ce) - kr * ce],
        [c(0, x, y) ~ x * y, (1 + y) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 0.5,
            2.0 * c(t, x, 1) + (0.5 + x) * Differential(y)(c(t, x, 1)) ~ 1.0], [Dr, kr])
    mixed = psys([D(ce) ~ Dr * Δ(ce) - kr * ce], [c(0, x, y) ~ x * y, (y - 0.4) * c(t, 0, y) + Differential(x)(c(t, 0, y)) ~ 0.5],
        [Dr, kr])
    timed = psys([D(ce) ~ Dr * Δ(ce) - kr * ce], [c(0, x, y) ~ x * y, (-1 - 4t) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ 0.0],
        [Dr, kr])
    cases = [("per site, BackwardEuler", site, BackwardEuler(; dt = 0.1, newton = 1)),
             ("per site, ExplicitEuler", site, ExplicitEuler(; dt = 0.05)),
             ("mixed sign, BackwardEuler", mixed, BackwardEuler(; dt = 0.1, newton = 4)),
             ("time, BackwardEuler", timed, BackwardEuler(; dt = 0.1, newton = 3)),
             ("time, ExplicitEuler (re-bounded)", timed, ExplicitEuler(; dt = 0.05))]
    mk(sys, be) = discretize(sys, LatticeDiscretization(Grid((32, 32)); T = Float32, backend = be))
    for (name, sys, alg) in cases
        sd = solve(mk(sys, PDEV), alg; saveat = 0.5)
        sh = solve(mk(sys, KernelAbstractions.CPU()), alg; saveat = 0.5)
        # (a Float32 implicit solve may stop at its rounding floor: `StalledSuccess`, on both)
        @test sd.retcode == sh.retcode && sd.retcode in (ReturnCode.Success, ReturnCode.StalledSuccess) && sd.t ≈ sh.t
        rel = maximum(i -> maximum(abs, Array(sd[ce][i]) .- sh[ce][i]) / maximum(abs, sh[ce][i]), eachindex(sd.t))
        @info "F4-12b $name: device vs host (Float32) max relative difference $rel"
        @test rel <= 1e-5
    end
end

# F4-B1: an input given as a function of the time on the device (the result goes through a host
# buffer of the input's type into the device array each window) equals the host executor's run
@testset "F4-B1: an input as a function of t on $pgpu" begin
    @variables dq(..) [input = true]
    dqe = dq(t, x, y)
    sys = PDESystem([D(ce) ~ 0.1 * Δ(ce) - ce + dqe], [c(0, x, y) ~ 0.0],
        [t ∈ Interval(0.0, 0.5), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce, dqe], Any[]; name = :dq)
    Q(s) = [s > 0.05i ? 1.0 : 0.0 for i in 1:8, j in 1:8]
    mk(be) = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float32, backend = be); inputs = [dqe => Q])
    sd = solve(mk(PDEV), ExplicitEuler(; dt = 0.01f0); saveat = 0.1)
    sh = solve(mk(KernelAbstractions.CPU()), ExplicitEuler(; dt = 0.01f0); saveat = 0.1)
    @test sd.t == sh.t && all(i -> isapprox(Array(sd[ce, i]), sh[ce, i]; rtol = 1.0f-5), eachindex(sd.t))
    @test maximum(sh[ce, length(sh.t)]) > 0.05
    # a function that returns a device array (review B1 #7: the checks read a host copy)
    QD(s) = copyto!(KernelAbstractions.allocate(PDEV, Float64, 8, 8), Q(s))
    pg = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float32, backend = PDEV); inputs = [dqe => QD])
    sg = solve(pg, ExplicitEuler(; dt = 0.01f0); saveat = 0.1)
    @test all(i -> isapprox(Array(sg[ce, i]), sh[ce, i]; rtol = 1.0f-5), eachindex(sg.t))
end
