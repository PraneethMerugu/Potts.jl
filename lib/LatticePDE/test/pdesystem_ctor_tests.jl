# `LatticePDE.pdesystem(eqs, bcs; name, domain)` works out the independent variables, the
# dependent variables (in order of first appearance) and the parameters, and returns a plain
# `PDESystem`. Oracle: the hand-built `PDESystem` (equal lists; the same problem, bitwise
# runs). Negative control at the base 4ca38af7: `pdesystem` does not exist (an
# `UndefVarError`).

@testsetup module LP_pdesystem_ctor
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/params.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/grids.jl")
include("shared/maskswitch.jl")
include("shared/coupled.jl")
include("shared/numbers.jl")
include("shared/coarse.jl")
include("shared/report.jl")
include("shared/unseen_loop.jl")
@parameters psD = 0.3 psk = 0.2 psJ[1:2] = [0.5, 1.5]
@variables psc(..) = 0.0 psu(..) psin(..)::Bool [input = true] psm(..)::Int32 [input = true]
psdom = [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
const PS_K = Bool[(i + 2j) % 3 == 0 for i in 1:8, j in 1:8]
const PS_M = Int32[1 + (i > 4) for i in 1:8, j in 1:8]
psdisc() = LatticeDiscretization(Grid((8, 8)); T = Float64)
function pseq()
    return [
            D(psc(t, x, y)) ~ psD * laplacian(psc(t, x, y)) + 0.5 * psin(t, x, y) - psk * psc(t, x, y),
            D(psu(t, x, y)) ~ 0.2 * laplacian(psu(t, x, y)) + value_at(psJ, psm(t, x, y)) * psc(t, x, y) - psu(t, x, y),
        ]
end
psbc() = [psc(0, x, y) ~ x, psu(0, x, y) ~ 0.0, psc(t, 0, y) ~ 1.0]
pslen(s) = (length(s.ivs), length(s.dvs), length(s.ps))
function psmsg(f)
    return try
            f()
            "built"
        catch e
            sprint(showerror, e)
        end
end

# The inputs come after the fields in name order, not in SymbolicUtils'
# term order or the order the conditions read them. Negative control at 11523b0b: the input
# first read in a condition (`psa`) came after `psz`.
@variables psz(..)::Bool [input = true] psa(..) [input = true]
include("shared/export_all.jl")
end

@testitem "pdesystem works out the lists of the hand-built PDESystem" setup = [LP_pdesystem_ctor] tags = [:latticepde, :pdesystem_ctor] begin
using .LP_pdesystem_ctor: fd
    @testset "pdesystem works out the lists of the hand-built PDESystem" begin
    a = LatticePDE.pdesystem(pseq(), psbc(); name = :ps, domain = psdom)
    @test a isa PDESystem && nameof(a) === :ps
    @test isequal(collect(a.ivs), [t, x, y])
    # the fields with equations first (each equation's left side), then the inputs
    @test isequal(a.dvs[1], psc(t, x, y)) && isequal(a.dvs[2], psu(t, x, y)) && length(a.dvs) == 4
    @test all(v -> any(w -> isequal(w, v), a.dvs), [psin(t, x, y), psm(t, x, y)])
    @test length(a.ps) == 3 && all(p -> any(q -> isequal(unwrap(q), unwrap(p)), a.ps), [psD, psk, psJ])
    @test isequal(a.eqs, pseq()) && isequal(a.bcs, psbc()) && isequal(a.domain, psdom)
    # the hand-built system in the order pdesystem gives: the same problem, bitwise runs
    b = PDESystem(pseq(), psbc(), psdom, [t, x, y], collect(a.dvs), collect(a.ps); name = :ps)
    ins = [psin => PS_K, psm => PS_M]
    pa, pb = discretize(a, psdisc(); inputs = ins), discretize(b, psdisc(); inputs = ins)
    @test pa.u0 == pb.u0 && isequal(pa.p.values, pb.p.values)
        ra, rb = solve(pa, ExplicitEuler(); dt = 1.0e-3), solve(pb, ExplicitEuler(); dt = 1.0e-3)
    @test ra.u[end] == rb.u[end] && maximum(abs, ra.u[end] .- ra.u[1]) > 1e-3
    # and the hand-built one in the written order (the lists are the same as sets)
    c = PDESystem(pseq(), psbc(), psdom, [t, x, y], [psc(t, x, y), psu(t, x, y), psin(t, x, y), psm(t, x, y)],
        [psD, psk, psJ]; name = :ps)
        @test solve(discretize(c, psdisc(); inputs = ins), ExplicitEuler(); dt = 1.0e-3).u[end] == ra.u[end]
    # keywords go to PDESystem; no parameters gives an empty list
    i = LatticePDE.pdesystem([D(psc(t, x, y)) ~ -psc(t, x, y)]; name = :pi, domain = psdom,
        initial_conditions = Dict(psc(t, x, y) => 0.25))
    @test pslen(i) == (3, 1, 0) && all(==(0.25), discretize(i, psdisc()).u0)
    # a steady system (no time): the coordinates only
        s = LatticePDE.pdesystem([0 ~ laplacian(psu(x, y)) - psu(x, y) + 1.0]; name = :pss)
    @test isequal(collect(s.ivs), [x, y]) && pslen(s) == (2, 1, 0)
end
end

@testitem "pdesystem refusals" setup = [LP_pdesystem_ctor] tags = [:latticepde, :pdesystem_ctor] begin
using .LP_pdesystem_ctor: fd
    @testset "pdesystem refusals" begin
    m = psmsg(() -> LatticePDE.pdesystem([D(psc(t, x, y)) ~ psu(t, x) - psc(t, x, y)]; name = :bad))
    @test occursin("different independent variables", m) || (println(m); false)
    m = psmsg(() -> LatticePDE.pdesystem(Equation[]; name = :bad))
    @test occursin("at least one equation", m) || (println(m); false)
    m = psmsg(() -> LatticePDE.pdesystem([psc(t, x, y)]; name = :bad))
    @test occursin("is not an equation", m) || (println(m); false)
end
end

@testitem "pdesystem orders the inputs by name" setup = [LP_pdesystem_ctor] tags = [:latticepde, :pdesystem_ctor] begin
using .LP_pdesystem_ctor: fd
    @testset "pdesystem orders the inputs by name" begin
    dvnames(s) = [string(nameof(operation(unwrap(u)))) for u in s.dvs]
    for rhs in (psz(t, x, y) - psc(t, x, y), psc(t, x, y) * psz(t, x, y), 2.0 * psz(t, x, y) - psc(t, x, y))
        s = LatticePDE.pdesystem([D(psc(t, x, y)) ~ rhs], [psc(t, 0, y) ~ psa(t, 0, y)]; name = :pso)
        @test dvnames(s) == ["psc", "psa", "psz"] || (println(dvnames(s)); false)
    end
    # two fields keep the order of their equations, before the inputs
    s = LatticePDE.pdesystem([D(psu(t, x, y)) ~ psz(t, x, y) + psa(t, x, y), D(psc(t, x, y)) ~ psu(t, x, y)]; name = :pso)
    @test dvnames(s) == ["psu", "psc", "psa", "psz"] || (println(dvnames(s)); false)
        # a front end's refusal hook: nothing by default (any metadata value is accepted)
    @test LatticePDE.pdesystem_refusal(:any, psc(t, x, y)) === nothing
end
end
