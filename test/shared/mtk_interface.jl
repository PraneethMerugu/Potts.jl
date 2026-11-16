# ModelingToolkit's public system interface, walked on one system. Included by a test module
# that has `using Test` and the name `ModelingToolkitBase`; written so that it can join the
# shared QA helpers (qa_common.jl).
#
# The calls are ModelingToolkitBase's public `AbstractSystem` interface (version 1.77,
# `~/.julia/packages/ModelingToolkitBase/<slug>/src`):
#   - `nameof` and `get_systems`, the two methods every system type must answer
#     (`ModelingToolkitBase.jl:197-204`, the `AbstractSystem` docstring);
#   - the exported accessors `independent_variables`, `unknowns`, `parameters`, `observed`
#     (`ModelingToolkitBase.jl:134`), `equations`, `full_equations`, `initial_conditions`,
#     `bindings` and `guesses` (`systems/abstractsystem.jl`), and the scalar extension point
#     `independent_variable` (`ModelingToolkitBase.jl:233-261`);
#   - the public `inputs`, `outputs` and `iscomplete` (`ModelingToolkitBase.jl:507-516`) and
#     `does_namespacing` (`systems/abstractsystem.jl:464`, named by `getproperty`'s docstring);
#   - the metadata functions `getmetadata`, `hasmetadata`, `setmetadata`
#     (`systems/system.jl:1310-1330`);
#   - the exported operations `@named` (with an index range), `extend`, `compose`, `complete`
#     and `toggle_namespacing` (`ModelingToolkitBase.jl:473`), and `rename`
#     (`systems/abstractsystem.jl:1052`);
#   - `mtkcompile` and its keywords (`systems/systems.jl:100-135`).
#
# Each call must give a value of MTK's kind, or refuse with an `ArgumentError`: never a
# `FieldError`, a `MethodError` or a stack overflow, which are not answers a user can act on.

if !isdefined(@__MODULE__, :qa_mtk_system_interface)
    """A metadata key that no system sets."""
    struct MTKInterfaceKey end

    """The value of `f()`, or the exception it throws."""
    function mtk_outcome(f)
        try
            return f()
        catch err
            return err
        end
    end

    """Whether `x` is a value, or the `ArgumentError` of a refusal (not another exception)."""
    mtk_answered(x) = !(x isa Exception) || x isa ArgumentError

    """
        qa_mtk_system_interface(sys; rebuild, component)

    Walk MTK's public system interface on `sys` (see the list above). `rebuild(; name)` builds
    the same model under `name` (for `@named models[1:2]` and `extend`), and `component` is an MTK
    `System` that `compose(sys, [component])` adds. Every call must answer (`mtk_answered`), and
    the values must have MTK's types and agree with each other.
    """
    function qa_mtk_system_interface(sys; rebuild, component)
        M = ModelingToolkitBase
        Test.@testset "accessors" begin
            Test.@test nameof(sys) isa Symbol
            Test.@test mtk_outcome(() -> M.get_systems(sys)) isa AbstractVector
            for f in (M.equations, M.full_equations, M.observed)
                Test.@test mtk_outcome(() -> f(sys)) isa AbstractVector{<:M.Equation}
            end
            for f in (M.unknowns, M.parameters, M.inputs, M.outputs, M.independent_variables)
                Test.@test mtk_outcome(() -> f(sys)) isa AbstractVector
            end
            for f in (M.initial_conditions, M.bindings, M.guesses)
                Test.@test mtk_outcome(() -> f(sys)) isa AbstractDict
            end
            iv = mtk_outcome(() -> M.independent_variable(sys))
            Test.@test !(iv isa Exception) && iv !== nothing
            Test.@test isequal(M.independent_variables(sys), [iv])
        end
        Test.@testset "completeness and namespacing" begin
            complete = mtk_outcome(() -> M.iscomplete(sys))
            namespacing = mtk_outcome(() -> M.does_namespacing(sys))
            Test.@test complete isa Bool && namespacing isa Bool
            # `does_namespacing` says what `sys.p` is: the parameter itself, or a namespaced copy
            p = first(M.parameters(sys))
            name = Symbol(M.getname(p))
            Test.@test isequal(M.unwrap(getproperty(sys, name)), M.unwrap(p)) == !namespacing
            done = mtk_outcome(() -> M.complete(sys))
            Test.@test done isa M.AbstractSystem && M.iscomplete(done) && nameof(done) === nameof(sys)
            Test.@test mtk_answered(mtk_outcome(() -> M.toggle_namespacing(sys, false)))
        end
        Test.@testset "metadata" begin
            Test.@test mtk_outcome(() -> M.getmetadata(sys, MTKInterfaceKey, :none)) === :none
            Test.@test mtk_outcome(() -> M.hasmetadata(sys, MTKInterfaceKey)) === false
            set = mtk_outcome(() -> M.setmetadata(sys, MTKInterfaceKey, 42))
            Test.@test set isa typeof(sys) && M.getmetadata(set, MTKInterfaceKey, :none) == 42 &&
                M.hasmetadata(set, MTKInterfaceKey) && nameof(set) === nameof(sys)
        end
        Test.@testset "rename, @named with an index range, compose, extend" begin
            renamed = mtk_outcome(() -> M.rename(sys, :renamed))
            Test.@test renamed isa typeof(sys) && nameof(renamed) === :renamed
            several = mtk_outcome(() -> (ModelingToolkitBase.@named models[1:2] = rebuild(); models))
            Test.@test several isa AbstractVector && nameof.(several) == [:models_1, :models_2]
            composed = mtk_outcome(() -> M.compose(sys, [component]))
            Test.@test composed isa M.AbstractSystem && nameof(composed) === nameof(sys) &&
                length(M.unknowns(composed)) == length(M.unknowns(sys)) + length(M.unknowns(component))
            # a system with `sys` as its component: a composed system, or a refusal naming the route
            Test.@test mtk_answered(mtk_outcome(() -> M.compose(component, [sys])))
            extended = mtk_outcome(() -> M.extend(rebuild(; name = :extension), rebuild(; name = :base)))
            Test.@test extended isa typeof(sys) && nameof(extended) === :extension &&
                Set(M.getname.(M.parameters(extended))) == Set(M.getname.(M.parameters(sys)))
        end
        Test.@testset "mtkcompile" begin
            compiled = mtk_outcome(() -> M.mtkcompile(sys))
            Test.@test compiled isa M.AbstractSystem && M.iscomplete(compiled) && nameof(compiled) === nameof(sys)
            for f in (M.equations, M.observed)
                Test.@test mtk_outcome(() -> f(compiled)) isa AbstractVector{<:M.Equation}
            end
            for f in (M.unknowns, M.parameters, M.inputs, M.outputs, M.get_systems)
                Test.@test mtk_outcome(() -> f(compiled)) isa AbstractVector
            end
            Test.@test isequal(mtk_outcome(() -> M.independent_variable(compiled)), M.independent_variable(sys))
            Test.@test mtk_outcome(() -> M.getmetadata(compiled, MTKInterfaceKey, :none)) === :none
            # MTK's keywords: compiled, or refused by name
            for kw in ((; simplify = false), (; inputs = [], outputs = []))
                Test.@test mtk_answered(mtk_outcome(() -> M.mtkcompile(sys; kw...)))
            end
        end
        return nothing
    end
end
