# The callables the solvers items hand to `@sweep combine` (D-123). `src/vocabulary.jl`'s
# `_stable_callable` judges `combine` by its printed form and rejects a compiler-generated name
# (`var"#"`), because a wrapper holding an anonymous function is named differently in every
# session. A `@testsetup` module is gensym'd (`Main.var"##SolversSetup#1693"`), so a struct defined
# in one prints with that gensym; on the old include-into-Main runner they were `Main.SweepFnSub()`
# and passed. They are defined once per process in a module with a deterministic name and imported
# here, so the printed form is the same in a 4-worker run and in a single item run.
if !isdefined(Main, :PottsSolverTestTypes)
    Core.eval(Main, :(module PottsSolverTestTypes
        struct SweepHolder{F}
            f::F
        end
        (h::SweepHolder)(a, b) = h.f(a, b)
        struct SweepFnSub <: Function end
        (::SweepFnSub)(a, b) = min(a, b)
        struct SweepMix
            w::Float64
        end
        (m::SweepMix)(a, b) = m.w * a + (1 - m.w) * b
    end))
end
import Main.PottsSolverTestTypes
using Main.PottsSolverTestTypes: SweepHolder, SweepFnSub, SweepMix
