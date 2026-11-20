# Runs a PottsModels test file (lib/PottsModels/test, ReTestItems `@testsetup`/`@testitem`)
# inside an item of another suite, the way `ReTestItems.runtests` runs it:
#
#     PottsModelsTestFile.run_file(into, path)                 # setups, then every item
#     PottsModelsTestFile.run_file(into, path; items = false)  # setups only
#
# Each `@testsetup module S … end` of the file is evaluated in the module `into` (so its
# definitions are `into.S.name`), and each `@testitem` runs in a fresh module of `into` that
# uses `Test` and its setups, inside a testset named after the item. The file's macros are
# not expanded: an item of the calling suite would otherwise register the file's items.
module PottsModelsTestFile

using Test: Test, @testset
using ReTestItems: ReTestItems

_macro(ex) = ex isa Expr && ex.head === :macrocall ? ex.args[1] : nothing

"""The setup names of a `@testitem` expression (its `setup = [...]` keyword)."""
function _setups(ex)
    for a in ex.args
        a isa Expr && a.head === :(=) && a.args[1] === :setup &&
            return Symbol[a.args[2].args...]
    end
    return Symbol[]
end

function _run_item(into::Module, ex)
    title = ex.args[3]::String
    body = Expr(:block, :(using Test))
    for s in _setups(ex)
        # `using ..S`: the item module is in `into`
        push!(body.args, Expr(:using, Expr(:., :., :., s)))
    end
    append!(body.args, ex.args[end].args)
    # `ReTestItems.softscope_all!` is an internal ReTestItems API (check it on dependency
    # updates): top-level loops assign globals, as in the runner.
    ReTestItems.softscope_all!(body)
    mod = Expr(:module, true, gensym(title), body)
    @testset "$title" begin
        Core.eval(into, mod)
    end
    return nothing
end

function run_file(into::Module, path::AbstractString; items::Bool = true)
    file = Meta.parseall(read(path, String); filename = String(path))
    for ex in file.args
        m = _macro(ex)
        if m === Symbol("@testsetup")
            Core.eval(into, ex.args[end])
        elseif m === Symbol("@testitem") && items
            _run_item(into, ex)
        end
    end
    return into
end

end
