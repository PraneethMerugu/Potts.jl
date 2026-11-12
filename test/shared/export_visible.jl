# The last line of every `@testsetup` module of the Potts suite (TS1a):
#
#     include(joinpath(@__DIR__, "shared", "export_visible.jl"))
#
# exports every name visible in the setup (its own definitions, and the names its `using`s bring
# in), so a `@testitem` that declares the setup sees the namespace the file's top level had.
# Names from Base and Core are visible everywhere already. Two setups that an item declares
# together must not define the same name (Julia then resolves neither).
for n in names(@__MODULE__; all = true, imported = true, usings = true)
    (n === nameof(@__MODULE__) || n in (:eval, :include) || startswith(String(n), '#')) && continue
    isdefined(@__MODULE__, n) || continue
    Base.binding_module(@__MODULE__, n) in (Base, Core) && continue
    @eval export $n
end
