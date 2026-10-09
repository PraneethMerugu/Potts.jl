# Coverage of the full no-`double` scan (D-157): every device kernel (`@kernel`, as its
# `gpu_*` function) and every launch body (`*_body!`) defined in CorePotts must appear in
# the kernels the GPU group compiled on ROCm (the union of the CorePotts and Potts suites'
# scans, `test/shared/device_ir_scan.jl`), or be on the allowlist below with its reason. A
# new kernel or body that the GPU group never compiles fails here.
# Run by `GROUP=GPU` on ROCm after both suites, with `POTTS_DEVICE_IR_DIR` set.
using Test
using CorePotts: CorePotts

# name => why the ROCm GPU group cannot compile it
const ALLOWLIST = Dict{String, String}(
    "propose_body!" => "called inside gpu_propose_kernel! and gpu_propose_track_kernel! (both scanned), never launched itself",
    "commit_body!" => "called inside gpu_commit_kernel! and gpu_commit_track_kernel! (both scanned), never launched itself",
    "propose_conn_body!" => "called inside gpu_propose_conn_kernel! and gpu_serial_conn_kernel! (both scanned), never launched itself",
    "global_deferred_body!" => "called inside gpu_global_conn_kernel! and gpu_global_serial_kernel! (both scanned), never launched itself",
)

@testset "device IR: every CorePotts kernel and launch body is scanned" begin
    dir = get(ENV, "POTTS_DEVICE_IR_DIR", "")
    files = isempty(dir) ? String[] : filter(f -> endswith(f, ".txt"), readdir(dir; join = true))
    @test length(files) == 2                                 # both suites wrote their scan
    sigs = join(read.(files, String), '\n')
    defined = sort!([string(n) for n in names(CorePotts; all = true)
                     if (startswith(string(n), "gpu_") || endswith(string(n), "_body!")) &&
                        isdefined(CorePotts, n) && getfield(CorePotts, n) isa Function])
    seen(n) = occursin(Regex("CorePotts\\." * replace(n, "!" => "\\!") * "(?![\\w!])"), sigs)
    missing_ = filter(n -> !seen(n) && !haskey(ALLOWLIST, n), defined)
    stale = filter(n -> !(n in defined) || seen(n), collect(keys(ALLOWLIST)))
    @info "device IR coverage" defined = length(defined) scanned = count(seen, defined) allowlisted = length(ALLOWLIST)
    @test length(defined) > 20                               # control: the enumeration finds them
    @test isempty(missing_)
    isempty(missing_) || @error "device IR: kernels or bodies the GPU group never compiled" missing_
    @test isempty(stale)                                     # an allowlist entry that is now covered or gone
    isempty(stale) || @error "device IR: stale allowlist entries" stale
end
