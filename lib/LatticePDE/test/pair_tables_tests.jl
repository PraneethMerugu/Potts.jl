# Pair tables in field terms: `value_at(J, a, b)` reads a matrix parameter, stored flat
# (column-major), with each index clamped into its axis and index 0 in either argument
# reading 0, as the host method `value_at(J, a, b)` does. The stability bound takes a pair
# read as two index groups; `remake`, `setp` and `integ.ps` write a matrix table. Base
# (1db3d3bf): any pair table read was refused at the lowering.

@testsetup module LP_pair_tables
using Test, LatticePDE
using ModelingToolkitBase: @parameters, @variables, PDESystem, t_nounits as t,
    D_nounits as D
using DomainSets: Interval
using SciMLBase: SciMLBase, remake
using SymbolicIndexingInterface: setp
using ForwardDiff: ForwardDiff

@parameters x y kd = 1.0
@parameters Jp[1:2, 1:3] = [1.0 2.0 3.0; 4.0 5.0 6.0] Dv[1:3] = [1.0, 2.0, 3.0]
@variables c(..) k1(..)::Int32 [input = true] k2(..)::Int32 [input = true]
const ce, ae, be = c(t, x, y), k1(t, x, y), k2(t, x, y)
const JM = [1.0 2.0 3.0; 4.0 5.0 6.0]
# the indices: 0 on either axis, every entry, and values past both axes
const A = Int32[0 1 2 3; 1 2 3 4; 2 2 1 0; 5 1 1 1]
const B = Int32[1 1 1 1; 2 2 2 2; 3 3 3 3; 0 4 9 1]
function tsys(rhs, ps = [Jp, kd]; c0 = 0.0)
    return PDESystem(
        [D(ce) ~ rhs], [c(0, x, y) ~ c0],
        [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
        [t, x, y], [ce, ae, be], ps; name = :pair
    )
end
function tprob(rhs; T = Float64, c0 = 0.0, a = A, b = B, kw...)
    return discretize(
        tsys(rhs; c0), LatticeDiscretization(Grid((4, 4)); T, kw...);
        inputs = [ae => a, be => b]
    )
end
# the pair table written out by `ifelse`, with the kernel's clamping and index 0
function written(a, b)
    ia, ib = min(max(a, 1), 2), min(max(b, 1), 3)
    row(i) = ifelse(ib == 1, Jp[i, 1], ifelse(ib == 2, Jp[i, 2], Jp[i, 3]))
    return ifelse((a == 0) | (b == 0), 0.0, ifelse(ia == 1, row(1), row(2)))
end
include("shared/export_all.jl")
end

@testitem "a pair table read per site against the host method" setup = [
    LP_pair_tables,
] tags = [:latticepde, :pair_tables] begin
    o = tprob(value_at(Jp, ae, be))
    du = similar(o.u0)
    o.f(du, o.u0, o.p, 0.0)
    @test reshape(du, 4, 4) == value_at.(Ref(JM), A, B)
    # index 0 on either axis reads 0; indices past an axis read its last entry
    @test all(iszero, reshape(du, 4, 4)[(A .== 0) .| (B .== 0)])
    @test reshape(du, 4, 4)[4, 3] == JM[1, 3] && reshape(du, 4, 4)[1, 4] == JM[2, 1]
    # a negative index reads the first entry of its axis, as the host clamps it
    An = Int32[-1 1 2 -3; 1 2 -1 1; 2 2 1 1; -2 1 1 1]
    on = tprob(value_at(Jp, ae, be); a = An, b = abs.(An) .+ Int32(1))
    on.f(du, on.u0, on.p, 0.0)
    @test reshape(du, 4, 4) == value_at.(Ref(JM), An, abs.(An) .+ 1)
    @test reshape(du, 4, 4)[1, 1] == JM[1, 2]
end

@testitem "a pair table read equals the table written out by ifelse" setup = [
    LP_pair_tables,
] tags = [:latticepde, :pair_tables] begin
    rate(o) = (du = similar(o.u0); o.f(du, o.u0, o.p, 0.0); du)
    @test rate(tprob(value_at(Jp, ae, be))) == rate(tprob(written(ae, be)))
end

@testitem "a pair table in a coefficient: the bound reads its entries" setup = [
    LP_pair_tables,
] tags = [:latticepde, :pair_tables] begin
    p = tprob(value_at(Jp, ae, be) * laplacian(ce); c0 = 1.0)
    n = init(p, ExplicitEuler(); dt = 0.01).substeps
    big = init(remake(p; p = [Jp => 100 .* JM]), ExplicitEuler(); dt = 0.01).substeps
    @test n >= 1 && big > n
    # a negative entry at an index a site reads is refused
    @test_throws ArgumentError init(
        remake(p; p = [Jp => [1.0 2.0 3.0; 4.0 5.0 -6.0]]), ExplicitEuler(); dt = 0.01
    )
    # two index groups: `value_at(Jp, a, a)` reads only the entries (i, i) and, past the
    # first axis, (2, 3); a negative entry (1, 2) that no site reads is not refused
    Mn = [1.0 -2.0 3.0; 4.0 5.0 6.0]
    pd = tprob(value_at(Jp, ae, ae) * laplacian(ce); c0 = 1.0)
    @test init(remake(pd; p = [Jp => Mn]), ExplicitEuler(); dt = 0.01).substeps >= 1
    # control: `value_at(Jp, a, b)` reads (1, 2) at a site, so the same table is refused
    @test_throws ArgumentError init(remake(p; p = [Jp => Mn]), ExplicitEuler(); dt = 0.01)
end

@testitem "remake, setp and integ.ps write a pair table" setup = [LP_pair_tables] tags = [
    :latticepde, :pair_tables,
] begin
    p = tprob(value_at(Jp, ae, be))
    M = [1.0 2.0 3.0; 4.0 5.0 9.0]
    du = similar(p.u0)
    r = remake(p; p = [Jp => M])
    r.f(du, r.u0, r.p, 0.0)
    @test reshape(du, 4, 4) == value_at.(Ref(M), A, B)
    @test p.ps[Jp] == JM && r.ps[Jp] == M
    ig = init(p, ExplicitEuler(); dt = 0.01)
    @test ig.ps[Jp] == JM
    setp(ig, Jp)(ig, M)
    @test ig.ps[Jp] == M
    ig.ps[Jp[1, 3]] = 7.0
    @test ig.ps[Jp[1, 3]] == 7.0 && ig.ps[Jp] == [1.0 2.0 7.0; 4.0 5.0 9.0]
    # a flat vector of the entries, column-major, writes the same table
    setp(ig, Jp)(ig, vec(JM))
    @test ig.ps[Jp] == JM
    @test_throws ArgumentError remake(p; p = [Jp => [1.0, 2.0]])
    # a matrix of another shape (the transpose: same length) is refused, not read as
    # another table
    @test_throws ArgumentError remake(p; p = [Jp => permutedims(JM)])
    @test_throws ArgumentError setp(ig, Jp)(ig, permutedims(M))
    @test_throws ArgumentError (ig.ps[Jp] = permutedims(M))
    @test ig.ps[Jp] == JM
end

@testitem "a literal entry and a computed parameter read a pair table" setup = [
    LP_pair_tables,
] tags = [:latticepde, :pair_tables] begin
    # `Jp[1, 2]` is entry (1, 2), not the first entry of the flat storage
    rate(o) = (du = similar(o.u0); o.f(du, o.u0, o.p, 0.0); du)
    @test all(==(JM[1, 2]), rate(tprob(Jp[1, 2] + 0 * ae)))
    @parameters kc = Jp[2, 3] + Jp[1, 2]
    o = discretize(
        tsys(kc + 0 * ae, [Jp, kc]), LatticeDiscretization(Grid((4, 4)));
        inputs = [ae => A, be => B]
    )
    @test all(==(JM[2, 3] + JM[1, 2]), rate(o))
    M = [1.0 7.0 3.0; 4.0 5.0 9.0]
    @test all(==(M[2, 3] + M[1, 2]), rate(remake(o; p = [Jp => M])))
end

@testitem "pair tables in Float32 and with a Dual parameter" setup = [
    LP_pair_tables,
] tags = [:latticepde, :pair_tables] begin
    p64 = tprob(kd * value_at(Jp, ae, be))
    p32 = tprob(kd * value_at(Jp, ae, be); T = Float32)
    s64 = solve(p64, ExplicitEuler(); dt = 0.1).u[end]
    s32 = solve(p32, ExplicitEuler(); dt = 0.1f0).u[end]
    @test eltype(s32) == Float32 && isapprox(s32, s64; rtol = 1.0e-6)
    # c(1) = kd J(a, b): the derivative in kd is the table entry at each site
    f(v) = sum(solve(remake(p64; p = [kd => v]), ExplicitEuler(); dt = 0.1).u[end])
    @test ForwardDiff.derivative(f, 1.0) ≈ sum(value_at.(Ref(JM), A, B)) rtol = 1.0e-12
end

@testitem "pair table reads that stay refused" setup = [LP_pair_tables] tags = [
    :latticepde, :pair_tables,
] begin
    # a vector parameter read with two indices
    @test_throws ArgumentError discretize(
        tsys(value_at(Dv, ae, be), [Jp, Dv, kd]), LatticeDiscretization(Grid((4, 4)));
        inputs = [ae => A, be => B]
    )    # an entry with a computed index (a site value): `value_at` reads that
    m = try
        tprob(Jp[ae, 1] + 0 * be)
        ""
    catch err
        err isa ArgumentError ? err.msg : rethrow()
    end
    @test occursin("one integer literal per axis", m)
    # control: the literal entry and the `value_at` read lower
    @test tprob(Jp[2, 1] + value_at(Jp, ae, be)) isa SciMLBase.AbstractODEProblem
end
