# A standalone MTK reaction-diffusion example (decay with a fixed end), solved on 512² (12
# automatic substeps per step). The field is uniform in y (periodic pair), so every row is
# the 1D problem D c″ − k c with c = 1 at x = 0 and no flux at x = 1, which a Float64 host
# loop with the same steps checks; the raw `Differential` spelling lowers to the same
# program.

@testsetup module LP_example
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/preamble.jl")
include("shared/discretize.jl")
include("shared/export_all.jl")
end

@testitem "§7.4 standalone example" setup = [LP_example] tags = [
    :latticepde,
    :example,
] begin
    @testset "§7.4 standalone example" begin
        ex = quote
            using ModelingToolkitBase, LatticePDE
            @parameters t x y Dc = 1.0e-3 k = 0.1
            @variables c(..)
            @named rd = PDESystem(
                Differential(t)(c(t, x, y)) ~ Dc * laplacian(c(t, x, y)) - k * c(t, x, y),
                [
                    c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0,
                    Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1),
                ],
                [t ∈ Interval(0, 10), x ∈ Interval(0, 1), y ∈ Interval(0, 1)], [t, x, y],
                [c(t, x, y)], [
                    Dc, k,
                ]
            )
            prob = discretize(rd, LatticeDiscretization(Grid((512, 512)); T = Float32))
            sol = solve(prob, ExplicitEuler(); dt = 1.0f-2, saveat = 1)
            sol[c(t, x, y)]
        end
        m = Module(:Example74)
        # `using` before the macros expand
        foreach(e -> e isa LineNumberNode || Core.eval(m, e), ex.args)
        prob, sol = m.prob, m.sol
        # (the owned problem)
        fp = LFP.field_problem(prob)
        p = fp.program
        # from the domain and the bc pair
        @test p.spacing == (1 / 512, 1 / 512) && p.periodic == (false, true)
        @test prob.p.values == [1.0e-3, 0.1] &&
            fp.stability(fp.p) ≈ 1.0e-3 * 8 * 512^2 + 0.1
        @test substep_counts(sol)[1] == 12 && sol.t == 0:10
        v = Core.eval(m, :(sol[c(t, x, y)]))
        # (one grid per save)
        w = v[end]
        @test length(v) == 11 && size(w) == (512, 512) && all(isfinite, w)
        # periodic in y: no y dependence
        @test all(j -> w[:, j] == w[:, 1], 1:512)
        # the 1D oracle, Float64, same 12 000 substeps
        n, h = 512, 1 / 512
        dt = 1.0e-2 / 12
        u = zeros(n)
        for _ in 1:12_000
            u = [
                u[i] +
                    dt * (
                    1.0e-3 *
                        (
                        (i < n ? u[i + 1] : u[i]) + (i > 1 ? u[i - 1] : 2 - u[i]) -
                            2u[i]
                    ) /
                        h^2 - 0.1u[i]
                )
                    for i in 1:n
            ]
        end
        @test maximum(abs, w[:, 1] .- u) < 1.0e-4
        @test maximum(
            abs, w[:, 1] .-
                (cosh.(10 .* (1 .- ((1:n) .- 0.5) ./ n)) ./ cosh(10))
        ) > 1.0e-3  # not the steady state yet
        # the raw `Differential` spelling lowers to the same program (§7.4)
        raw = Core.eval(
            m, quote
                Dx, Dy = Differential(x), Differential(y)
                @named rd2 = PDESystem(
                    Differential(t)(c(t, x, y)) ~
                        Dc * (Dx(Dx(c(t, x, y))) + Dy(Dy(c(t, x, y)))) - k * c(t, x, y),
                    rd.bcs, rd.domain, [t, x, y], [c(t, x, y)], [Dc, k]
                )
                symbolic_discretize(
                    rd2,
                    LatticeDiscretization(Grid((512, 512)); T = Float32)
                )
            end
        )
        ref = Core.eval(
            m, :(
                symbolic_discretize(
                    rd, LatticeDiscretization(
                        Grid(
                            (
                                512, 512,
                            )
                        ); T = Float32
                    )
                )
            )
        )
        @test sprint(LatticeFields.IR.print_program, raw.program) ==
            sprint(LatticeFields.IR.print_program, ref.program)
    end
end
