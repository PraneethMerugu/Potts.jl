# A development session for the Potts suite (test/*_tests.jl): Revise plus ReTestItems, so
# items rerun in one session and reuse its compiled code.
#
#     julia --project=test -i test/dev.jl
#
#     ti("coarse field")           # items whose name contains "coarse field"
#     ti(r"^a Coarse\(4\)")        # items whose name matches a regex
#     ti(; tags = :fields_coarse)  # the items of fields_coarse_tests.jl (the file's tag)
#     ti("is_kind"; nworkers = 1)  # in a fresh worker process instead of this session
#     tf("fields_short_tests.jl")  # every item of one file
#
# Edits to src (Revise) and to the test files are picked up by the next call; `@testsetup`
# modules are evaluated again on every call (cheap: a model of an already compiled structure
# costs about 0.1 s). A long session can carry state that tests mutate; CI's fresh processes
# (test/runtests.jl) stay the reference.
try
    @eval using Revise
catch
    @warn "Revise is not on the load path (add it to your default environment); src edits need a new session"
end
include(joinpath(@__DIR__, "shared", "rti.jl"))

"""
    ti(name = nothing; tags = nothing, nworkers = 0, kw...)

Run the Potts items whose name contains `name` (a `String`) or matches it (a `Regex`), and
that carry every tag in `tags`, in this session (`nworkers = 0`) or in worker processes.
Other keywords go to `ReTestItems.runtests`.
"""
function ti(name = nothing; tags = nothing, nworkers = 0, kw...)
    pat = name isa AbstractString ? Regex(replace(name, r"[\\^$.|?*+()\[\]{}]" => s"\\\0")) : name
    return PottsRTI.rti(PottsRTI.TESTDIR; name = pat, tags, nworkers, PottsRTI.OPTIONS..., kw...)
end

"""
    tf(file; nworkers = 0, kw...)

Run every item of one file of test/ (for example `"fields_short_tests.jl"`).
"""
tf(file; nworkers = 0, kw...) = PottsRTI.rti(joinpath(PottsRTI.TESTDIR, file); nworkers, PottsRTI.OPTIONS..., kw...)

@info "Potts test session: ti(\"name\"), ti(r\"regex\"), ti(; tags = :file_tag), tf(\"file_tests.jl\")"
