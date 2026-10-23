# The §7.4 problem on a device (LATTICEPDE_GPU = metal | rocm), Float32: the owned solve on
# device arrays equals the host executor's bit for bit on normal-range values (128²; the
# device flushes subnormals), and the verbatim 512² run completes with automatic substeps.
using KernelAbstractions: KernelAbstractions
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
        problem = :owned, backend)), ExplicitEuler(dt = 1.0f-2); saveat = T / 2)
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
    @test s.substeps == 12 && all(isfinite, s[ce][end])
    @info "§7.4 verbatim size on $pgpu: 512², 1000 steps × 12 substeps in $(round(t512; digits = 2)) s (incl. compile)"
end

# F3-00 review r1 S7: the aux fields are evaluated at each save on the device (one aux launch on
# device arrays, before the copy) and at `integ[K]`: `K ~ 2c + t` holds at every save and
# equals the host executor's run
@testset "F3-00: B evaluates the aux fields at the saves on $pgpu" begin
    @parameters Da7 = 0.1 ka7 = 1.0
    sys = psys([D(ce) ~ Da7 * Δ(ce) - ka7 * ce, Ke ~ 2ce + t], [c(0, x, y) ~ 1.0 + x], [Da7, ka7]; dvs = [ce, Ke])
    mk(be) = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float32, problem = :owned, backend = be))
    sd = solve(mk(PDEV), ExplicitEuler(; dt = 0.25f0); saveat = 0.5)
    sh = solve(mk(KernelAbstractions.CPU()), ExplicitEuler(; dt = 0.25f0); saveat = 0.5)
    @test sd.retcode == ReturnCode.Success && sd.t == sh.t == [0.0, 0.5, 1.0]
    for i in eachindex(sd.t)
        @test Array(sd[Ke][i]) ≈ 2 .* Array(sd[ce][i]) .+ Float32(sd.t[i]) rtol = 1.0f-6
        @test Array(sd[Ke][i]) ≈ Array(sh[Ke][i]) rtol = 1.0f-5
    end
    ig = init(mk(PDEV), ExplicitEuler(; dt = 0.25f0))
    step!(ig)
    @test Array(ig[Ke]) ≈ 2 .* Array(ig[ce]) .+ 0.25f0 rtol = 1.0f-6
end

@testset "number types on $pgpu (P5)" begin
    # Dual{Float32} through the owned path on the device equals the host derivative
    sys = nsys()
    mk(backend) = discretize(sys, LatticeDiscretization(Grid((16, 8)); T = Float32, problem = :owned, backend))
    alg = ExplicitEuler(; dt = 0.01)
    i = pidx(mk(KernelAbstractions.CPU()), Dn)
    Jdev(prob) = v -> sum(Array(solve(remake(prob; p = withp(prob.p, i, v)), alg).u[end]))
    pd, ph = mk(PDEV), mk(KernelAbstractions.CPU())
    dd, dh = ForwardDiff.derivative(Jdev(pd), pd.p[i]), ForwardDiff.derivative(Jdev(ph), ph.p[i])
    @test dd isa Float32 && isapprox(dd, dh; rtol = 1e-5) && dd != 0
    # default state type: Float32 on a device
    @test eltype(discretize(sys, LatticeDiscretization(Grid((8, 4)); problem = :owned, backend = PDEV))) == Float32
    @test_throws ArgumentError discretize(sys, LatticeDiscretization(Grid((8, 4)); T = BigFloat, problem = :owned, backend = PDEV))
    # Rodas5P on device arrays (Jacobian and time gradient through the right side)
    ode = discretize(psys([D(ce) ~ Dn * Δ(ce) - kn * ce + 0.1 * sin(ωn * t)],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [Dn, kn, gn, ωn]), LatticeDiscretization(Grid((8, 4)); T = Float32, problem = :ode, backend = PDEV))
    host = discretize(psys([D(ce) ~ Dn * Δ(ce) - kn * ce + 0.1 * sin(ωn * t)],
            [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
            [Dn, kn, gn, ωn]), LatticeDiscretization(Grid((8, 4)); T = Float32, problem = :ode))
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
    ig = init(discretize(fs, LatticeDiscretization(Grid((8, 8)); T = Float32, problem = :owned, backend = PDEV)),
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
    mk(k) = discretize(msys, LatticeDiscretization(Grid((n, n)); T = Float32, problem = :owned, backend = PDEV);
        inputs = [qe => k])
    s = solve(mk(dk(K)), ExplicitEuler(; dt = 0.1f0))
    @test Array(s[:c][end]) ≈ Float32.(K)
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
    mk(m) = discretize(dsys, LatticeDiscretization(Grid((n, n)); T = Float32, problem = :owned, backend = PDEV,
        domain = dm); inputs = [dm => m])
    r = Threads.@spawn Array(solve(mk(db), ExplicitEuler(; dt = 0.1f0))[:c][end])
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
