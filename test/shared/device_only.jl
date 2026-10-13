# Device-only runs of the CorePotts and Potts suites (GROUP=GPU, P6.ci). The CPU steps run
# both suites in full; the GPU step needs only what touches the device. This driver includes
# a suite's runner through a filter on each file's top-level expressions:
#
# - a top-level `@testset` that names no device (`PottsDevices`, AMDGPU, Metal, a backend) is
#   dropped: it is a CPU test the CPU step already ran;
# - everything else is kept: definitions (functions, constants, structs, models) that the
#   device files reuse, and any testset that names a device (backend dispatch, device
#   branches inside otherwise CPU files);
# - `include(path)` calls are rewritten so the included file is filtered the same way,
#   except the device files themselves (DEVICE_FILES) and everything they include, which
#   run unchanged, every testset kept.
#
# No test file changes: the filter sees the files as they are. POTTS_DEVICE_ONLY_LOG, when
# set, names a file that receives one line per kept and dropped testset, for review.
#
#     julia --project=<suite test project> test/shared/device_only.jl <suite runner>
using Test

const DEVICE_FILES = Set(["gpu.jl", "device_ir.jl", "transfer_counts.jl", "device_coverage.jl", "device_ir_scan.jl"])
const DEVICE_NAMES = Set([:PottsDevices, :AMDGPU, :Metal, :ROCBackend, :MetalBackend, :on_device, :device_backend,
    :device_name, :device_package, :device_sync])
const DEVICE_ONLY_LOG = get(ENV, "POTTS_DEVICE_ONLY_LOG", "")

_names_device(ex) = ex isa Symbol ? ex in DEVICE_NAMES :
                    ex isa QuoteNode ? _names_device(ex.value) :
                    ex isa Expr && any(_names_device, ex.args)
_is_testset(ex) = ex isa Expr && ex.head === :macrocall && ex.args[1] in (Symbol("@testset"), GlobalRef(Test, Symbol("@testset")))
function _testset_name(ex)
    for a in ex.args[2:end]
        a isa String && return a
        a isa Expr && a.head === :string && return string(a)
    end
    return "(unnamed)"
end
_log(kind, ex, file) = isempty(DEVICE_ONLY_LOG) ||
    open(io -> println(io, kind, '\t', basename(file), '\t', _testset_name(ex)), DEVICE_ONLY_LOG, "a")

# rewrite `include(x)` (any depth) so that the included file goes through `_device_only_map`
# (not inside a `module`: its includes run in that module, as before, unfiltered)
_rewrite(ex) = ex isa Expr ?
    (ex.head === :call && ex.args[1] === :include && length(ex.args) == 2 ?
        Expr(:call, :include, Expr(:call, GlobalRef(Main, :_device_only_map), ex.args[2]), ex.args[2]) :
        ex.head in (:quote, :module) || _is_testset(ex) ? ex : Expr(ex.head, map(_rewrite, ex.args)...)) : ex

function _device_only_filter(file)
    return function (ex)
        if _is_testset(ex)
            keep = _names_device(ex)
            _log(keep ? "KEEP" : "DROP", ex, file)
            keep || return nothing
            return ex
        end
        return _rewrite(ex)
    end
end

# the mapexpr for one include: device files run unchanged
_device_only_map(path) = basename(path) in DEVICE_FILES ? identity : _device_only_filter(path)

include(_device_only_map(ARGS[1]), abspath(ARGS[1]))
