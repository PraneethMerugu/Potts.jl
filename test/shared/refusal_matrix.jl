# The refusal matrix of the system container: every SciMLBase problem
# constructor MTKBase extends, plus `JumpProblem`, in 3 plain argument shapes, `{true}` and
# `{true, FullSpecialize}` (16 × 5 = 80 routes), and 19 MTK paths, on one `PottsSystem`.
# Each route is REFUSED (an `ArgumentError` naming `PottsProblem`), LOUD (any other exception)
# or BUILT (returns). Included by system_container_tests.jl and by its negative-control subprocess
# (test/system_refusal_negctl.jl), which runs it with the refusal methods deleted.
module RefusalMatrix

using Potts
const MTKB = Potts.ModelingToolkitBase
const SB = Potts.SciMLBase

const CONSTRUCTORS = Any[
    SB.ODEProblem, SB.NonlinearProblem, SB.SteadyStateProblem, SB.SDEProblem, SB.DAEProblem,
    Potts.JumpProcesses.JumpProblem, SB.OptimizationProblem, SB.DDEProblem, SB.SDDEProblem, SB.BVProblem,
    SB.DiscreteProblem, SB.ImplicitDiscreteProblem, SB.NonlinearLeastSquaresProblem, SB.LinearProblem,
    SB.IntervalNonlinearProblem, SB.HomotopyProblem,
]

function classify(f)
    try
        f()
        return :BUILT
    catch e
        msg = sprint(showerror, e)
        return e isa ArgumentError && occursin("PottsProblem", msg) ? :REFUSED : :LOUD
    end
end

"""`label => class` for every route on `W`; `other` is an MTK `System` to compose and extend with."""
function matrix(W, other)
    out = Pair{String, Symbol}[]
    for P in CONSTRUCTORS
        n = nameof(P)
        for (a, args) in (
                ("(W, [])", (W, [])), ("(W, [], (0,1))", (W, [], (0.0, 1.0))),
                ("(W, Dict(), (0,1))", (W, Dict(), (0.0, 1.0))),
            )
            push!(out, "$n$a" => classify(() -> P(args...)))
        end
        push!(out, "$n{true}" => classify(() -> P{true}(W, [], (0.0, 1.0))))
        push!(out, "$n{true,FullSpecialize}" => classify(() -> P{true, SB.FullSpecialize}(W, [], (0.0, 1.0))))
    end
    t = Potts.t
    x = first(MTKB.unknowns(other))
    empty() = MTKB.System(Potts.Equation[], t; name = :p)
    paths = [
        "mtkcompile(W)" => () -> MTKB.mtkcompile(W),
        "mtkcompile(W; inputs)" => () -> MTKB.mtkcompile(W; inputs = [x]),
        "complete(W)" => () -> MTKB.complete(W),
        "complete(W; flatten = false)" => () -> MTKB.complete(W; flatten = false),
        "structural_simplify(W)" => () -> MTKB.structural_simplify(W),
        "InitializationProblem(W, 0.0, [])" => () -> MTKB.InitializationProblem(W, 0.0, []),
        "InitializationProblem{true}(W, 0.0, [])" => () -> MTKB.InitializationProblem{true}(W, 0.0, []),
        "compose(System, [W])" => () -> MTKB.compose(empty(), [W]),
        "mtkcompile(compose(System, [W]))" => () -> MTKB.mtkcompile(MTKB.compose(empty(), [W])),
        "compose(W, [System])" => () -> MTKB.compose(W, [other]),
        "compose(W, W)" => () -> MTKB.compose(W, W),
        "extend(System, W)" => () -> MTKB.extend(empty(), W),
        "extend(W, System)" => () -> MTKB.extend(W, empty()),
        "extend(W, W)" => () -> MTKB.extend(W, W),
        "flatten(W)" => () -> MTKB.flatten(W),
        "expand_connections(W)" => () -> MTKB.expand_connections(W),
        "toggle_namespacing(W, false)" => () -> MTKB.toggle_namespacing(W, false),
        "rename(W, :q)" => () -> MTKB.rename(W, :q),
        "convert(System, W)" => () -> convert(MTKB.System, W),
    ]
    for (l, f) in paths
        push!(out, l => classify(f))
    end
    return out
end

"""`label => class` for further argument shapes on `W` (a symbol, a string, a symbolic
variable after the system; a steady-state call without `tspan`): every one must be REFUSED."""
function shapes(W)
    x = first(MTKB.unknowns(Potts.inner(W)) ∪ MTKB.parameters(Potts.inner(W)))
    out = Pair{String, Symbol}[]
    for P in CONSTRUCTORS
        n = nameof(P)
        for (a, arg) in ((":x", :x), ("\"s\"", "s"), ("'c'", 'c'), ("identity", identity), ("x", x))
            push!(out, "$n($a, (0,1))" => classify(() -> P(W, arg, (0.0, 1.0))))
            push!(out, "$n{true}($a, (0,1))" => classify(() -> P{true}(W, arg, (0.0, 1.0))))
            push!(out, "$n{true,FullSpecialize}($a, (0,1))" => classify(() -> P{true, SB.FullSpecialize}(W, arg, (0.0, 1.0))))
        end
    end
    push!(out, "SteadyStateProblem{true}(:x)" => classify(() -> SB.SteadyStateProblem{true}(W, :x)))
    push!(out, "SteadyStateProblem(:x)" => classify(() -> SB.SteadyStateProblem(W, :x)))
    return out
end

"""The refusal methods on `PottsSystem` (plain, `{iip}` and `{iip, spec}` forms of every constructor)."""
function refusal_methods()
    return unique(
        [
            m for P in CONSTRUCTORS
                for Q in (P, P{true}, P{true, SB.FullSpecialize}, P{true, SB.FunctionWrapperSpecialize}) for m in methods(Q)
                if m.module === Potts && any(==(PottsSystem), Base.unwrap_unionall(m.sig).parameters)
        ]
    )
end

tally(m) = Dict(c => count(p -> last(p) === c, m) for c in (:REFUSED, :LOUD, :BUILT))
built(m) = [first(p) for p in m if last(p) === :BUILT]

end
