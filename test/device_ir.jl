# No `double` in any device kernel's LLVM IR (D-157; extends D-047). Metal has no doubles,
# so device code never touches Float64 (CLAUDE.md); ROCm has them and would run such code
# silently. While Metal verification is deferred (P6.0bi), this check stands in for Metal's
# own refusal: every kernel the device runs compiles, in Float32, to IR with no `double`.
#
# Representative set: every published model (PottsModels) in Float32 under CheckerboardCPM,
# with its sweep (propose/commit), field steps, phases, folds and lifecycle (divisions forced
# where the model has them), each run until its kernels have compiled. Every kernel compiled
# while the set runs is captured through GPUCompiler's compile hook (it fires on every
# compilation, cached or not) and its optimized module (the IR the backend lowers) is
# scanned for the LLVM type `double`.
#
# Negative controls: a kernel that widens to Float64 through a Float64 literal, and one that
# converts explicitly, are both flagged by the same scan; the Float32 twin of the first is not.
#
# ROCm only (included from test/gpu.jl when POTTS_GPU=rocm); the backend's own reflection
# hook is needed, and Metal refuses such kernels itself (p6_0v3 (6)).
module DeviceIR
using Test, Potts, PottsModels
using Potts: CorePotts
import AMDGPU
const GPUCompiler = AMDGPU.GPUCompiler
const KA = CorePotts.KernelAbstractions

# the LLVM type token `double`, not part of a name (`%double`, `@julia_double_1`, `.double`)
const DOUBLE = r"(?<![%@.\w\"])double(?![\w.\"])"

"""`[(kernel, optimized LLVM module)]` of every distinct kernel compiled while `f()` runs.
While a hook is set GPUCompiler recompiles at every launch, so `f` should be short."""
function kernels_ir(f)
    out = Tuple{String, String}[]
    seen = Set{Any}()
    function hook(job)
        key = (job.source, job.config)
        key in seen && return nothing
        push!(seen, key)
        GPUCompiler.compile_hook[] = nothing          # code_llvm compiles again: no re-entry
        try
            push!(out, (string(job.source.specTypes), sprint(io -> GPUCompiler.code_llvm(io, job; dump_module = true))))
        finally
            GPUCompiler.compile_hook[] = hook
        end
        return nothing
    end
    old = GPUCompiler.compile_hook[]
    GPUCompiler.compile_hook[] = hook
    try
        f()
        AMDGPU.synchronize()
    finally
        GPUCompiler.compile_hook[] = old
    end
    return out
end

"""The lines of `ir` that mention `double`."""
doubles(ir) = filter(l -> occursin(DOUBLE, l), split(ir, '\n'))

# --- negative controls ----------------------------------------------------------------
KA.@kernel function devir_f64_literal!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = a[i] * 1.000000001          # Float32 * Float64 literal → Float64
end
KA.@kernel function devir_f64_convert!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = Float32(sqrt(Float64(a[i])))
end
KA.@kernel function devir_f32!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = a[i] * 1.000000001f0
end

@testset "device IR: the scan flags a Float64-touching kernel (negative control)" begin
    backend = AMDGPU.ROCBackend()
    for (k, flagged) in ((devir_f64_literal!, true), (devir_f64_convert!, true), (devir_f32!, false))
        a = AMDGPU.ROCArray(ones(Float32, 8))
        irs = kernels_ir(() -> k(backend)(a; ndrange = 8))
        @test length(irs) == 1                                          # the hook saw the kernel
        @test any(!isempty ∘ doubles ∘ last, irs) == flagged
        @test Array(a)[1] ≈ (k === devir_f64_convert! ? 1.0f0 : 1.000000001f0)  # and it ran
    end
end

# --- the staged lifecycle's compile-only launch (lifecycle_device.jl, `_CompileOnly`) -----
# It relies on the backend compiling a launch over an empty range and then not dispatching
# it (verified for Metal.jl 1.10); on ROCm: the hook sees the kernel, the array is untouched.
@inline devir_write!(i, a) = (@inbounds a[i] = 2.0f0; nothing)      # i ≤ length(a)

@testset "device IR: a compile-only launch compiles and does not dispatch (ROCm)" begin
    backend = AMDGPU.ROCBackend()
    a = AMDGPU.ROCArray(ones(Float32, 4))
    irs = kernels_ir(() -> CorePotts._stage!(CorePotts._CompileOnly(), devir_write!, backend, 4, (a,)))
    @test length(irs) == 1 && occursin("devir_write!", first(only(irs)))
    @test Array(a) == ones(Float32, 4)
    CorePotts._stage!(CorePotts._Enqueue(), devir_write!, backend, 4, (a,))   # control: a launch writes
    AMDGPU.synchronize()
    @test Array(a) == fill(2.0f0, 4)
end

# --- the representative set ------------------------------------------------------------
"""`name => () -> problem` for every published model, small, Float32, with events forced."""
function devir_cases()
    T = Float32
    gg = graner_glazier_state()
    two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
    ref = (σ = zeros(Int32, 60, 60);
        foreach(((k, (a, b)),) -> σ[9 + 7a .+ (1:7), 9 + 7b .+ (1:7)] .= k, enumerate(Iterators.product(0:5, 0:5)));
        σ)
    return [
        "GranerGlazier" => () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 4); T),
        "WortelAct" => () -> PottsProblem(WortelAct(; name = :w, lattice = (40, 40)),
            [ownership => two((40, 40), (5:12, 5:12), (25:32, 25:32)), kind => [:cell, :cell]], (0, 4); T),
        "WortelAct (connected)" => () -> PottsProblem(WortelAct(; name = :wc, lattice = (40, 40), connected = true),
            [ownership => two((40, 40), (5:12, 5:12), (25:32, 25:32)), kind => [:cell, :cell]], (0, 4); T),
        "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :m, lattice = (60, 60)),
            merks_state(; lattice = (60, 60), n = 9), (0, 4); T, field_solver = ExplicitEuler(substeps = 3, lower = 0.0)),
        # one cell of 144 sites, far above 2A₀ = 50: it divides in the first MCS
        "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (40, 40)),
            [ownership => (s = zeros(Int32, 40, 40); s[15:26, 15:26] .= 1; s), kind => [:cell]], (0, 4); T, capacity = 64),
        "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :f),
            [ownership => (s = zeros(Int32, 12, 8); s[5:8, 3:6] .= 1; s), kind => [:epithelial]], (0, 4); T, capacity = 8),
        "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (0, 4); T, capacity = 1000),
        "OpenVTReferenceMonolayer" => () -> PottsProblem(OpenVTReferenceMonolayer(; name = :r, lattice = (60, 60)),
            [ownership => ref, kind => fill(:cell, 36), :σ_X => 0.0], (0, 4); T, capacity = 128),
        "OpenVTChain" => () -> PottsProblem(OpenVTChain(; name = :c, lattice = (150, 5)), openvt_chain(11), (0, 4); T),
        "Merks2006" => () -> PottsProblem(Merks2006(; name = :m6, lattice = (32, 32)),
            layout(merks2006_layout(; lattice = (32, 32), n = 6, side = 7), (32, 32)), (0, 4); T,
            field_solver = ExplicitEuler(substeps = 3)),
        "Merks2008" => () -> PottsProblem(Merks2008(; name = :m8, lattice = (32, 32)),
            layout(merks2008_denovo(; lattice = (32, 32), n = 12, rounds = 2), (32, 32)), (0, 4); T,
            field_solver = ExplicitEuler(substeps = 3)),
    ]
end

@testset "device IR: no `double` in any kernel of the published models (Float32)" begin
    backend = AMDGPU.ROCBackend()
    seen = String[]
    # While the hook is set every launch recompiles, so each run is one MCS; the von Neumann
    # sweep (the other proposal kernels) runs for Graner–Glazier only.
    for (name, make) in devir_cases(), alg in (CheckerboardCPM(; proposal = Moore(1)), CheckerboardCPM())
        name == "GranerGlazier" || alg.proposal isa Moore || continue
        prob = make()
        divisions = Ref(0)
        irs = kernels_ir() do
            integ = init(prob, alg; backend, save_start = false, save_end = false)
            step!(integ)
            divisions[] = checkpoint(integ).stats.lifecycle.divisions
        end
        @test !isempty(irs)
        for (k, ir) in irs
            push!(seen, k)
            d = doubles(ir)
            @test isempty(d)
            isempty(d) || @info "device IR: `double` in a kernel of $name" kernel = first(k, 300) lines = first(d, 5)
        end
        # control: the lifecycle ran on the device where an event was forced
        if name in ("OpenVTGrowingMonolayer", "SingleDivisionFixture")
            @test divisions[] > 0
            divisions[] > 0 || @info "device IR: no division in $name (fused)"
        end
    end
    # the staged lifecycle (one kernel per stage; the fused form above is for small problems)
    fs = CorePotts.FUSE_SITES[]
    try
        CorePotts.FUSE_SITES[] = 0
        for (name, make) in devir_cases()
            name in ("OpenVTGrowingMonolayer", "SingleDivisionFixture", "AkeebInvasion") || continue
            divisions = Ref(0)
            irs = kernels_ir() do
                integ = init(make(), CheckerboardCPM(; proposal = Moore(1)); backend, save_start = false, save_end = false)
                step!(integ)
                divisions[] = checkpoint(integ).stats.lifecycle.divisions
            end
            for (k, ir) in irs
                push!(seen, k)
                d = doubles(ir)
                @test isempty(d)
                isempty(d) || @info "device IR: `double` in a staged-lifecycle kernel of $name" kernel = first(k, 300) lines = first(d, 5)
            end
            name == "AkeebInvasion" || @test divisions[] > 0
            name == "AkeebInvasion" || divisions[] > 0 || @info "device IR: no division in $name (staged)"
        end
    finally
        CorePotts.FUSE_SITES[] = fs
    end
    names = join(sort!(unique!([m.captures[1] for k in seen for m in eachmatch(r"CorePotts\.(\w+!?)", k)])), " ")
    @info "device IR: kernels scanned" n = length(seen) distinct = length(unique(seen)) names
    # the set covers the sweep, the generic kernel around phase, field-step and staged
    # lifecycle bodies, and both device lifecycle forms (fused, and planner + stages)
    has(p) = any(k -> occursin(p, k), seen)
    @test has("propose_kernel!") && has("commit_kernel!")
    @test has("_each_kernel!") && has("_cell_phase_body!") && has("_field_step_body!")
    @test has("_fused_kernel!") && has("_plan_kernel!") && has("_dpartition_body!")
end
end # module DeviceIR
