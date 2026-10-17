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
