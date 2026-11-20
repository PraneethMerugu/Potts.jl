# The opt-in vocabulary `using Potts.Fields`. Checks: `using Potts, Potts.Fields` leaves no name
# ambiguous; every exported name is the binding of its source (MTKBase, LatticePDE, Potts); a
# name it shares with LatticePDE, ModelingToolkitBase, SciMLBase or the OrdinaryDiffEq solver
# packages of this environment is the same binding; `using Potts` alone brings in no `t`, `x`,
# `y`, `z`. Negative control at the base 4ca38af7: `Potts.Fields` does not exist.

@testsetup module FieldVocabularySetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using OrdinaryDiffEqTsit5: OrdinaryDiffEqTsit5

using OrdinaryDiffEqRosenbrock: OrdinaryDiffEqRosenbrock


fv_exports() = [n for n in names(Potts.Fields) if n !== :Fields]

function fv_ambiguous(mods...)
    m = Module()
    foreach(p -> Core.eval(m, Expr(:using, Expr(:., p...))), mods)
    return [n for n in fv_exports() if (try; Core.eval(m, n); false; catch e; e isa UndefVarError; end)]
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "using Potts.Fields" setup = [FieldVocabularySetup] tags = [:potts, :field_vocabulary] begin
    @testset "using Potts.Fields" begin
        ex = fv_exports()
        @test issetequal(
            ex, [
                :PDESystem, :Differential, Symbol("@variables"), Symbol("@parameters"), :Interval, :laplacian, :Δ, :DivKGrad,
                :Advect, :Upwind1, :value_at, :ismember, :masked, :step_index, :lattice_domain, :pdesystem, :t, :x, :y, :z,
            ]
        )
        # no ambiguity with Potts, and with LatticePDE as well
        @test isempty(fv_ambiguous([:Potts], [:Potts, :Fields])) || (println(fv_ambiguous([:Potts], [:Potts, :Fields])); false)
        @test isempty(fv_ambiguous([:Potts], [:Potts, :Fields], [:Potts, :LatticePDE]))
        # the bindings of their sources
        MB, LP = Potts.ModelingToolkitBase, Potts.LatticePDE
        @test Potts.Fields.t === Potts.t && isequal(Potts.Fields.t, MB.t_nounits)
        @test all(n -> getfield(Potts.Fields, n) === getfield(Potts.FIELD_NAMES, n), (:x, :y, :z))
        @test Potts.Fields.PDESystem === MB.PDESystem && Potts.Fields.Differential === MB.Differential
        @test all(n -> getfield(Potts.Fields, n) === getfield(LP, n),
            (:Interval, :laplacian, :Δ, :DivKGrad, :Advect, :Upwind1, :value_at, :ismember, :masked, :step_index, :lattice_domain, :pdesystem)
        )
        # the names clash check: a name another package exports is the same binding. ModelingToolkit
        # and OrdinaryDiffEq are not in this environment; a one-off check with both loaded found no
        # clash and no ambiguity (2026-11-10 and e4-mtk.log)
        for M in (LP, MB, Potts.SciMLBase, OrdinaryDiffEqTsit5, OrdinaryDiffEqRosenbrock, Potts)
            clash = [n for n in ex if Base.isexported(M, n) && isdefined(M, n) && getfield(M, n) !== getfield(Potts.Fields, n)]
            @test isempty(clash) || (println(M, ": ", clash); false)
        end
        # opt-in: `using Potts` alone has no `t`, `x`, `y`, `z`
        m = Module()
        Core.eval(m, :(using Potts))
        @test !any(n -> (try; Core.eval(m, n); true; catch; false; end), (:t, :x, :y, :z))
    end
end
