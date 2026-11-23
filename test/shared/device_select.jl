# Which device backend the environment requests (D-157), without loading any GPU package:
# `POTTS_GPU` = "" | "metal" | "rocm". The one resolution rule, used by `devices.jl` (which
# then loads the package) and by the test runner (test/runner/PottsTestRunner.jl, which
# must not load one).
module PottsDeviceSelect

function requested(env = ENV)
    gpu = lowercase(strip(get(env, "POTTS_GPU", "")))
    gpu in ("", "metal", "rocm") ||
        error("POTTS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")
    return gpu
end

end # module PottsDeviceSelect
