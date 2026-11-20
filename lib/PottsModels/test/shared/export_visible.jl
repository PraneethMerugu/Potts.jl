# The last line of every PottsModels `@testsetup` module: export every name visible in the setup,
# so that an item that declares the setup sees what the file's top level had (the rule of the
# Potts suite, test/shared/export_visible.jl).
include(joinpath(@__DIR__, "..", "..", "..", "..", "test", "shared", "export_visible.jl"))
