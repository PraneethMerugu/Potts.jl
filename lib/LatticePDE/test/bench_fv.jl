# C7a performance gates (v3 §10), not a test. One process, one window per row:
#
#   julia --project=lib/LatticePDE/test lib/LatticePDE/test/bench_fv.jl rocm|metal|cpu [gate…]
#
# gates (all by default):
#   pg1   generated single-field FV step (2D 4096², 3D 256³) vs a hand KA stencil and a KA copy
#   pg2   two species with shared reads: one fused kernel vs two separate launches (4096²)
#   pg6   K coupled species: generated (IR, fused) vs the pass-3 E2 generator body at equal
#         streams (2D 4096² K = 8, 16; 3D 256³ K = 8), and the planner's fused/split choice
#         vs measured fused/split at 42³, 128³, 256³ (K = 4)
#   pg10  compile time per body (first, further mean over same-arity bodies; the cost of a new
#         arity reported apart) and no recompile on a parameter change
#   pg14  build(4096²) / build(64²): discretize + init of the §7.4 problem
# SMOKE=1 shrinks every size (a quick run that checks the script).
using LatticePDE, LatticeFields, KernelAbstractions, Printf, Random
using ModelingToolkitBase: @parameters, @variables, Differential, PDESystem
using LatticeFields: Exec, IR, Problems
using LatticeFields.IR: Grid, ProgramBuilder, field!, kernel, load, store, param, runtime, add!, program, constant
using LatticeFields.Compile: CompileOptions, semantic
using LatticePDE: symbolic_discretize
using LatticeFields.Schedule: plan
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, @RuntimeGeneratedFunction
RuntimeGeneratedFunctions.init(@__MODULE__)
const KA = KernelAbstractions

const WHICH = isempty(ARGS) ? "cpu" : ARGS[1]
const GATES = length(ARGS) > 1 ? ARGS[2:end] : ["pg1", "pg2", "pg6", "pg10", "pg14"]
const SMOKE = get(ENV, "SMOKE", "0") == "1"
if WHICH == "rocm"
    using AMDGPU: AMDGPU
    const DEV = AMDGPU.ROCBackend()
    ninstances() = length(AMDGPU.Compiler._kernel_instances)
elseif WHICH == "metal"
    using Metal: Metal
    const DEV = Metal.MetalBackend()
    ninstances() = length(Metal.kernel_instances)
else
    const DEV = KA.CPU()
    ninstances() = 0
end
devsync() = KA.synchronize(DEV)
dev(x) = copyto!(KA.allocate(DEV, eltype(x), length(x)), x)
opts() = CompileOptions(; T = Float32, float64_ok = Exec.default_float(DEV) === Float64)
S2, S3 = SMOKE ? (256, 32) : (4096, 256)
println("C7a gates on $WHICH; KA $(pkgversion(KA)); threads $(Threads.nthreads()); smoke $SMOKE")

function timeit(f; steps = 20, reps = 5)
    f()
    devsync()
    best = Inf
    for _ in 1:reps
        devsync()
        t0 = time_ns()
        for _ in 1:steps
            f()
        end
        devsync()
        best = min(best, (time_ns() - t0) / steps)
    end
    return best * 1e-9
end

# ---- reference kernels -------------------------------------------------------------------
@kernel function copy_k!(b, @Const(a))
    i = @index(Global, Linear)
    @inbounds b[i] = a[i]
end
# hand 5-point / 7-point explicit diffusion step, periodic, linear index with one divrem chain
# in Int32 (as the generated bodies; Int64 division is slow on some devices)
@kernel function hand2_k!(out, @Const(u), k, nx::Int32, ny::Int32)
    i64 = @index(Global, Linear)
    i = i64 % Int32
    j0, i0 = divrem(i - 1i32, nx)
    x, y = i0 + 1i32, j0 + 1i32
    w = ifelse(x == 1i32, i + nx - 1i32, i - 1i32)
    e = ifelse(x == nx, i - nx + 1i32, i + 1i32)
    s = ifelse(y == 1i32, i + nx * (ny - 1i32), i - nx)
    n = ifelse(y == ny, i - nx * (ny - 1i32), i + nx)
    @inbounds c = u[i]
    @inbounds out[i] = c + k * (u[w] + u[e] + u[s] + u[n] - 4c)
end
@kernel function hand3_k!(out, @Const(u), k, nx::Int32, ny::Int32, nz::Int32)
    i64 = @index(Global, Linear)
    i = i64 % Int32
    r0, i0 = divrem(i - 1i32, nx)
    k0, j0 = divrem(r0, ny)
    x, y, z = i0 + 1i32, j0 + 1i32, k0 + 1i32
    pl = nx * ny
    @inbounds c = u[i]
    @inbounds out[i] = c + k * (u[ifelse(x == 1i32, i + nx - 1i32, i - 1i32)] + u[ifelse(x == nx, i - nx + 1i32, i + 1i32)] +
                        u[ifelse(y == 1i32, i + nx * (ny - 1i32), i - nx)] + u[ifelse(y == ny, i - nx * (ny - 1i32), i + nx)] +
                        u[ifelse(z == 1i32, i + pl * (nz - 1i32), i - pl)] + u[ifelse(z == nz, i - pl * (nz - 1i32), i + pl)] - 6c)
end
const i32 = Int32(1)

function copy_gbs(n)
    a, b = dev(rand(Float32, n)), dev(zeros(Float32, n))
    t = timeit(() -> copy_k!(DEV, 256)(b, a; ndrange = n))
    return 8n / t / 1e9
end

# ---- generated programs ------------------------------------------------------------------
const OFF = Dict(2 => ((1, 0), (-1, 0), (0, 1), (0, -1)),
    3 => ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)))

"""K coupled species (the pass-3 E2 shape: Δ, decay, T random bilinear terms)."""
function species(dims::NTuple{N}, K, T; kernels = :one, seed = 1, shift = 0.0) where {N}
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), nparams = 1 + K * (2 + T))
    fs = [field!(pb, "u$(lpad(k, 2, '0'))"; buffers = 2) for k in 1:K]
    rng = Xoshiro(seed)
    cpl = [[(rand(rng, 1:K), rand(rng, 1:K)) for _ in 1:T] for _ in 1:K]
    function upd(kb, k)
        b = 1 + (k - 1) * (2 + T)
        c = load(kb, fs[k])
        r = param(kb, b + 1) * (sum(load(kb, fs[k]; offset = o) for o in OFF[N]) - 2N * c) - param(kb, b + 2) * c
        for (t, (i, j)) in enumerate(cpl[k])
            r = r + param(kb, b + 2 + t) * load(kb, fs[i]) * load(kb, fs[j])
        end
        iszero(shift) || (r = r + constant(kb, shift))           # a distinct body, same arity
        return c + runtime(kb, 2) * r
    end
    if kernels == :one
        kb = kernel(pb)
        foreach(k -> store(kb, fs[k], upd(kb, k)), 1:K)
        add!(pb, kb, "species")
    else
        for k in 1:K
            kb = kernel(pb)
            store(kb, fs[k], upd(kb, k))
            add!(pb, kb, "s$(lpad(k, 2, '0'))")
        end
    end
    return program(pb)
end

"""Bound step of program `p` (plan options `kw`) on random state; returns the step thunk."""
function bound(p, K; fuse = true)
    s = semantic(p)
    sp = plan(s; options = opts(), fuse)
    st = Problems.FieldStore(DEV, s)
    for f in eachindex(s.fields), b in st.bufs[f]
        copyto!(b, rand(Xoshiro(f), Float32, length(b)) .* 0.1f0)
    end
    P = ntuple(_ -> 0.01, s.nparams)
    bs = Problems.BoundStep(DEV, s, sp, st, P)
    Problems.compile!(DEV, bs)
    return (() -> bs((0.0f0, 0.1f0))), sp
end

row(tag, t, bytes, ref) = @printf("%-52s %10.2f µs %7.1f GB/s  %s\n", tag, t * 1e6, bytes / t / 1e9, ref)

# ---- PG-1 ---------------------------------------------------------------------------------
function pg1()
    for dims in ((S2, S2), (S3, S3, S3))
        N, n = length(dims), prod(dims)
        bytes = 8n
        tg = timeit(first(bound(species(dims, 1, 0), 1)))
        u, o = dev(rand(Float32, n)), dev(zeros(Float32, n))
        th = N == 2 ? timeit(() -> hand2_k!(DEV, 256)(o, u, 0.01f0, Int32.(dims)...; ndrange = n)) :
             timeit(() -> hand3_k!(DEV, 256)(o, u, 0.01f0, Int32.(dims)...; ndrange = n))
        cg = copy_gbs(n)
        gg, gh = bytes / tg / 1e9, bytes / th / 1e9
        @printf("PG-1 %dD %s: generated %.1f GB/s, hand %.1f GB/s, copy %.1f GB/s; generated/hand = %.3f (gate ≥ 0.90), generated/copy = %.3f (floor %s)\n",
            N, join(dims, "×"), gg, gh, cg, gg / gh, gg / cg, N == 2 ? "0.75" : "0.70")
    end
end

# ---- PG-2 ---------------------------------------------------------------------------------
function pg2()
    dims = (S2, S2)
    p = species(dims, 2, 2; kernels = :each, seed = 3)        # u1 and u2 read each other (shared reads)
    tf, spf = bound(p, 2; fuse = true)
    ts, sps = bound(p, 2; fuse = false)
    a, b = timeit(tf), timeit(ts)
    @printf("PG-2 two species %s: fused %d launch(es) %.1f µs, separate %d launches %.1f µs; separate/fused = %.3f (gate ≥ 1.4)\n",
        join(dims, "×"), length(spf.launches), a * 1e6, length(sps.launches), b * 1e6, b / a)
end

# ---- PG-6 ---------------------------------------------------------------------------------
# the pass-3 E2 generator body (common.jl `fbody`, :sep :inter) for the same-window reference
function fbody(D, K, T; seed = 1)
    rng = Xoshiro(seed)
    st = Any[]
    if D == 2
        push!(st, :((j0, i0) = divrem(i - 1, nx)), :(x = i0 + 1), :(y = j0 + 1),
            :(n1 = ifelse(x == 1, i + nx - 1, i - 1)), :(n2 = ifelse(x == nx, i - nx + 1, i + 1)),
            :(n3 = ifelse(y == 1, i + nx * (ny - 1), i - nx)), :(n4 = ifelse(y == ny, i - nx * (ny - 1), i + nx)))
        nn = 4
    else
        push!(st, :((r0, i0) = divrem(i - 1, nx)), :((k0, j0) = divrem(r0, ny)),
            :(x = i0 + 1), :(y = j0 + 1), :(z = k0 + 1), :(pl = nx * ny),
            :(n1 = ifelse(x == 1, i + nx - 1, i - 1)), :(n2 = ifelse(x == nx, i - nx + 1, i + 1)),
            :(n3 = ifelse(y == 1, i + nx * (ny - 1), i - nx)), :(n4 = ifelse(y == ny, i - nx * (ny - 1), i + nx)),
            :(n5 = ifelse(z == 1, i + pl * (nz - 1), i - pl)), :(n6 = ifelse(z == nz, i - pl * (nz - 1), i + pl)))
        nn = 6
    end
    cs = [Symbol(:c, k) for k in 1:K]
    foreach(k -> push!(st, :($(cs[k]) = IN[$k][i])), 1:K)
    pk = 0
    for k in 1:K
        lap = :($(Expr(:call, :+, [:(IN[$k][$(Symbol(:n, j))]) for j in 1:nn]...)) - $(2D) * $(cs[k]))
        rate = :(p[$(pk += 1)] * $lap - p[$(pk += 1)] * $(cs[k]))
        for _ in 1:T
            a, b = rand(rng, 1:K), rand(rng, 1:K)
            rate = :($rate + p[$(pk += 1)] * $(cs[a]) * $(cs[b]))
        end
        push!(st, :(OUT[$k][i] = $(cs[k]) + h * ($rate)))
    end
    ex = :((i, OUT, IN, p, h, nx, ny, nz, N) -> begin
        @inbounds begin
            $(st...)
        end
        nothing
    end)
    return RuntimeGeneratedFunctions.drop_expr(@RuntimeGeneratedFunction(ex)), pk
end

function pg6()
    for (dims, K) in (((S2, S2), 8), ((S2, S2), 16), ((S3, S3, S3), 8))
        D, n = length(dims), prod(dims)
        tg = timeit(first(bound(species(dims, K, 3), K)))
        f, np = fbody(D, K, 3)
        IN = Tuple(dev(rand(Float32, n) .* 0.1f0) for _ in 1:K)
        OUT = Tuple(dev(zeros(Float32, n)) for _ in 1:K)
        p = ntuple(_ -> 0.01f0, np)
        d3 = D == 2 ? (dims..., 1) : dims
        tr = timeit(() -> Exec.launch!(DEV, f, n, (OUT, IN, p, 0.1f0, d3..., n)))
        @printf("PG-6 %dD %s K=%d (%d streams): generated %.1f µs, generator %.1f µs; generated/generator = %.3f (gate ≥ 0.95)\n",
            D, join(dims, "×"), K, 2K, tg * 1e6, tr * 1e6, tr / tg)
    end
    for m in (SMOKE ? (16, 32) : (42, 128, 256))
        dims = (m, m, m)
        p = species(dims, 4, 3; kernels = :each)
        (tf, spf), (ts, _) = bound(p, 4; fuse = true), bound(p, 4; fuse = false)
        a, b = timeit(tf), timeit(ts)
        planner = length(spf.launches) < 4 ? "fused" : "split"
        measured = a < b ? "fused" : "split"
        @printf("PG-6 choice %d³ K=4: planner %s (%d launches); measured fused %.1f µs, split %.1f µs → %s; %s\n",
            m, planner, length(spf.launches), a * 1e6, b * 1e6, measured, planner == measured ? "MATCH" : "MISMATCH")
    end
end

# ---- PG-10 --------------------------------------------------------------------------------
function pg10()
    Exec.ishost(DEV) && return println("PG-10: no device compile on the host executor")
    function compile_one(K, shift)
        p = semantic(species((64, 64), K, 1; seed = 100, shift))
        sp = plan(p; options = opts())
        st = Problems.FieldStore(DEV, p)
        bs = Problems.BoundStep(DEV, p, sp, st, ntuple(_ -> 0.01, p.nparams))
        return @elapsed Problems.compile!(DEV, bs)
    end
    # distinct bodies of one arity (K = 2: same arrays, parameters and geometry types): the
    # PG-10 rows; the first pays the first-kernel cost
    same = [compile_one(2, 0.1k) for k in 1:9]
    further = sort(same[2:end])
    @printf("PG-10 compile (same arity): first body %.2f s (gate ≤ 1.8), further mean %.3f s, median %.3f s over %d (gate ≤ 0.4): %s\n",
        same[1], sum(further) / length(further), further[cld(length(further), 2)], length(further),
        join(map(t -> @sprintf("%.3f", t), same), " "))
    # a new arity (K = 1, 3, 4, 5: new argument types) also specializes the host-side launch
    # and wrapper code; reported apart, not a PG-10 row
    arity = [compile_one(K, 0.7) for K in (1, 3, 4, 5)]
    @printf("PG-10 info, new arity per body (K = 1, 3, 4, 5): mean %.3f s: %s\n",
        sum(arity) / length(arity), join(map(t -> @sprintf("%.3f", t), arity), " "))
    # a parameter change does not recompile: remake + init + steps add no kernel instance
    @parameters t x y Dc = 1e-3 k = 0.1
    @variables c(..)
    rd = PDESystem(Differential(t)(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) - k * c(t, x, y),
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, c(t, x, 0) ~ c(t, x, 1)],
        [t ∈ Interval(0, 1), x ∈ Interval(0, 1), y ∈ Interval(0, 1)], [t, x, y], [c(t, x, y)], [Dc, k]; name = :rd)
    prob = discretize(rd, LatticeDiscretization(Grid((64, 64)); T = Float32, backend = DEV))
    solve(prob, ExplicitEuler(); dt = 0.1f0)   # the bound is known (Dc, k)
    devsync()
    n0 = ninstances()
    solve(LatticePDE.Problems.SciMLBase.remake(prob; p = [2e-3, 0.3]), ExplicitEuler(); dt = 0.1f0)
    devsync()
    @printf("PG-10 parameter change: %d new kernel instances (gate 0)\n", ninstances() - n0)
end

# ---- PG-14 --------------------------------------------------------------------------------
function pg14()
    @parameters t x y Dc = 1e-3 k = 0.1
    @variables c(..)
    rd = PDESystem(Differential(t)(c(t, x, y)) ~ Dc * Δ(c(t, x, y)) - k * c(t, x, y),
        [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
        [t ∈ Interval(0, 10), x ∈ Interval(0, 1), y ∈ Interval(0, 1)], [t, x, y], [c(t, x, y)], [Dc, k]; name = :rd)
    # the build: lowering, semantic passes, plan, binding and compile (site counts are runtime
    # values, so none of it should scale with the grid); the state (allocation, initial
    # values, upload) is O(sites) by nature and reported apart
    stores = Dict{Int, Any}()
    function build(n)
        cf = symbolic_discretize(rd, LatticeDiscretization(Grid((n, n)); T = Float32);
            update = LatticePDE.euler_update)
        s = semantic(cf.program)
        sp = plan(s; options = opts())
        st = get!(() -> Problems.FieldStore(DEV, s; flat = ["c"]), stores, n)   # arrays: allocated once
        bs = Problems.BoundStep(DEV, s, sp, st, cf.defaults)
        Problems.compile!(DEV, bs)
        devsync()
    end
    state(n) = (prob = discretize(rd, LatticeDiscretization(Grid((n, n)); T = Float32, backend = DEV));
        init(prob, ExplicitEuler(); dt = 1.0f-2); devsync())
    big = SMOKE ? 512 : 4096
    build(64); build(big); state(64); state(big)            # warm: compile and first-call costs
    t64, tbig = (minimum(@elapsed(build(n)) for _ in 1:3) for n in (64, big))
    s64, sbig = (minimum(@elapsed(state(n)) for _ in 1:3) for n in (64, big))
    @printf("PG-14 build (lower, passes, plan, bind, compile; arrays preallocated): 64² %.4f s, %d² %.4f s; ratio %.2f (gate < 1.5)\n",
        t64, big, tbig, tbig / t64)
    @printf("PG-14 info: discretize + init incl. the state (O(sites)): 64² %.4f s, %d² %.4f s\n", s64, big, sbig)
end

for g in GATES
    getfield(@__MODULE__, Symbol(g))()
end
println("done")
