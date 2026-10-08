# Which device backend the environment requests (D-157), without loading any GPU package:
# `POTTS_GPU`, else `COREPOTTS_GPU`; each "" | "metal" | "rocm"; both set must agree.
# The one resolution rule, used by `devices.jl` (which then loads the package) and by the
# `GROUP=GPU` runner (test/runtests.jl, which must not load one).
module PottsDeviceSelect

function requested(env = ENV)
    a = lowercase(strip(get(env, "POTTS_GPU", "")))
    b = lowercase(strip(get(env, "COREPOTTS_GPU", "")))
    for v in (a, b)
        v in ("", "metal", "rocm") ||
            error("POTTS_GPU/COREPOTTS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$v\"")
    end
    isempty(a) || isempty(b) || a == b ||
        error("POTTS_GPU = \"$a\" and COREPOTTS_GPU = \"$b\" disagree; set one, or both alike")
    return isempty(a) ? b : a
end

end # module PottsDeviceSelect
