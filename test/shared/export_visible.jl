# The last line of every `@testsetup` module of the Potts suite:
#
#     include(joinpath(@__DIR__, "shared", "export_visible.jl"))
#
# exports every name visible in the setup (its own definitions, and the names its `using`s
# bring in), so a `@testitem` that declares the setup sees the namespace the file's top
# level had. Names from Base and Core are visible everywhere already. Two setups that an
# item declares together must not define the same name (Julia then resolves neither).
#
# A name that two modules export has no `binding_module` (Julia refuses to choose between
# them, "Constant binding was imported from multiple modules"). Exporting it would only move
# the ambiguity into the items, so such a name is left out and reported at debug level.
skipped = Symbol[]
for n in names(@__MODULE__; all = true, imported = true, usings = true)
    (n === nameof(@__MODULE__) || n in (:eval, :include) || startswith(String(n), '#')) &&
        continue
    isdefined(@__MODULE__, n) || continue
    bm = try
        Base.binding_module(@__MODULE__, n)
    catch
        push!(skipped, n)                       # provided by two modules: not exported
        continue
    end
    bm in (Base, Core) && continue
    @eval export $n
end
if !isempty(skipped)
    @debug "export_visible: bindings that several modules provide are not exported" setup =
        nameof(@__MODULE__) skipped
end
