# `lattice_domain(t, (x, y), dims; spacing, tspan)` gives a PDESystem
# the domain of its lattice (the discretization derives the spacing back from it), and `HEX`
# is exported. Negative control at 8c3f01cf: `lattice_domain` is not
# defined (11 of 11 checks fail or error) and `HEX` is not exported (2 of 2).

@testsetup module LP_latticedomain
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
# imports an earlier file made in the old single Main
using LatticeFields.IR: HEX
include("shared/lp_runner.jl")
include("shared/discretize.jl")
@parameters ldD = 0.3
@variables ldc(..)
ldce = ldc(t, x, y)
include("shared/export_all.jl")
end

@testitem "lattice_domain is the hand-written domain" setup = [LP_latticedomain] tags = [:latticepde, :latticedomain] begin
    @testset "lattice_domain is the hand-written domain" begin
        function same(a, b)
            return length(a) == length(b) &&
                all(i -> isequal(a[i].variables, b[i].variables) && a[i].domain == b[i].domain, eachindex(a))
        end
        @test same(
            lattice_domain(t, (x, y), (8, 4); spacing = 0.5),
            [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 4.0), y ∈ Interval(0.0, 2.0)]
        )
        @test same(
            lattice_domain(t, (x, y), (8, 4); spacing = (0.5, 0.25), tspan = (1, 3)),
            [t ∈ Interval(1.0, 3.0), x ∈ Interval(0.0, 4.0), y ∈ Interval(0.0, 1.0)]
        )
        @test same(lattice_domain((x, y), (8, 4)), [x ∈ Interval(0.0, 8.0), y ∈ Interval(0.0, 4.0)])  # no time
        @test !same(lattice_domain(t, (x, y), (8, 4)), lattice_domain(t, (x, y), (8, 4); spacing = 0.5))   # (control)
        for (args, kw, msg) in (
                ((t, (x, y), (8,)), (;), "`dims`"), ((t, (x, y), (8, 0)), (;), "`dims`"), ((t, (x, y), (true, 4)), (;), "`dims`"),
                ((t, (x, y), (8, 4)), (; spacing = 0), "`spacing`"), ((t, (x, y), (8, 4)), (; spacing = (1, 2, 3)), "`spacing`"),
                ((t, (x, y), (8, 4)), (; tspan = (1.0, 0.0)), "`tspan`"), ((t, x, (8,)), (;), "coordinates"),
            )
            e = try
                lattice_domain(args...; kw...); ""
            catch err
                err isa ArgumentError ? err.msg : sprint(showerror, err)
            end
            @test occursin(msg, e) || (println("lattice_domain refusal: ", e); false)
        end
        # on a spaced lattice the discretization derives the spacing back: the same run as the
        # hand-written domain, bit for bit, and the site centers at (i − 1/2) h
        function sys(dom)
            return PDESystem(
                [D(ldce) ~ ldD * laplacian(ldce) - 0.5 * ldce], [ldc(0, x, y) ~ x + 2y], dom, [t, x, y], [ldce], [ldD];
                name = :lds
            )
        end
        function run(dom)
            return solve(
                discretize(sys(dom), LatticeDiscretization(Grid((8, 4)); T = Float64)), ExplicitEuler(); dt = 0.01,
                saveat = 0.5
            )
        end
        a = run(lattice_domain(t, (x, y), (8, 4); spacing = 0.5))
        @test a.u == run([t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 4.0), y ∈ Interval(0.0, 2.0)]).u
        @test a.u != run(lattice_domain(t, (x, y), (8, 4))).u                      # (control: the spacing matters)
        @test a[x] ≈ ((1:8) .- 0.5) .* 0.5 && a[y] ≈ ((1:4) .- 0.5) .* 0.5
    end
end

@testitem "HEX is exported" setup = [LP_latticedomain] tags = [:latticepde, :latticedomain] begin
    @testset "HEX is exported" begin
        @test Base.isexported(LatticePDE, :HEX)
        m = Module(:TiHex)
        Core.eval(m, :(using LatticePDE))
        @test Core.eval(m, :(Grid((4, 4); geometry = HEX).geometry)) == LatticeFields.IR.HEX
    end
end
