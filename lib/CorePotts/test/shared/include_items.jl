# Run a converted test file the way `include` ran the old one inside a testset: the
# statements of its @testsetup, then the body of each @testitem in file order, all in one new
# module. The testsets nest in the caller's current testset.
function include_items(parent::Module, path::AbstractString)
    path = abspath(path)
    m = Core.eval(parent, Expr(:module, true, gensym(:included_items), Expr(:block)))
    task_local_storage(:SOURCE_PATH, path) do
        for ex in Meta.parseall(read(path, String); filename = path).args
            ex isa Expr && ex.head === :macrocall || continue
            body = if ex.args[1] === Symbol("@testsetup")
                ex.args[end].args[3]
            elseif ex.args[1] === Symbol("@testitem")
                ex.args[end]
            else
                continue
            end
            Core.eval(m, :(using Test))
            for st in body.args
                Core.eval(m, st)
            end
        end
    end
    return m
end
