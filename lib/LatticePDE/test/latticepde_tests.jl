# LatticePDE vocabulary: registered operators, metadata keys and scans
# (the inline testsets of the old runtests.jl).
@testsetup module LP_latticepde
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
include("shared/export_all.jl")
end

@testitem "operators are positional registered terms" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "operators are positional registered terms" begin
        @test opof(laplacian(ce)) === laplacian
        @test opof(DivKGrad(:harmonic)(Ke, ce)) == DivKGrad(:harmonic)
        @test opof(DivKGrad(:arithmetic)(Ke, ce)).mean === :arithmetic
        @test opof(Advect(Upwind1())(ve[1], ce)) isa Advect{Upwind1}
        @test opof(Advect(Upwind1())(ve, ce)) isa Advect{Upwind1}           # velocity array
        @test contains_var(Advect(Upwind1())(ve, ce), ce)
        @test opof(value_at(Dk, ke)) === value_at
        @test opof(value_at(ce, ke)) === value_at                                     # a site read
        @test opof(value_at(J, ke, ke)) === value_at
        @test opof(ismember(ke, (2, 3))) === ismember
        @test opof(masked(ke == 3, 0.0)) === masked
        # options are struct fields, never keywords
        @test_throws MethodError DivKGrad(; mean = :harmonic)
        @test_throws MethodError Advect(; scheme = Upwind1())
        @test_throws ArgumentError DivKGrad(:geometric)                     # negative control: the mean is checked
        @test_throws MethodError Advect(:upwind)                            # a scheme is an AbstractAdvectionScheme
        # the field operators never evaluate; the CPM reads do
        @test_throws ArgumentError laplacian(1.0)
        @test_throws ArgumentError DivKGrad(:harmonic)(1.0, 2.0)
        @test_throws ArgumentError Advect(Upwind1())(1.0, 2.0)
        @test_throws ArgumentError masked(true, 1.0)
        @test value_at([10.0, 20.0, 30.0], 2.0) == 20.0
        @test value_at(reshape(collect(1.0:9.0), 3, 3), 2, 3) == 8.0
        @test ismember(Int32(3), (2, 3)) && !ismember(1.0, (2, 3))
    end
end

@testitem "reads take any index: literal codes, Real-typed inputs, unwrapped terms" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "reads take any index: literal codes, Real-typed inputs, unwrapped terms" begin
        @variables owner(t) cv(t) flag(t)::Bool
        isread(e, f, n) = opof(e) === f && length(arguments(unwrap(e))) == n
        # literal kind codes into symbolic tables (the medium is 0): a term, not a symbolic
        # array indexed by the literal (negative control: the numeric method still evaluates)
        @test isread(value_at(Dk, 0), value_at, 2) && unwrap_const(arguments(unwrap(value_at(Dk, 0)))[2]) == 0
        @test isread(value_at(J, 0, 1), value_at, 3) && isread(value_at(J, ke, 0), value_at, 3) && isread(value_at(J, 0, ke), value_at, 3)
        @test value_at([10.0, 20.0, 30.0], 1) == 10.0
        # a site or cell value at a literal, at a Real-typed input, and a Bool-typed value
        @test isread(value_at(cv, 3), value_at, 2) && isread(value_at(cv, owner), value_at, 2) && isread(value_at(flag, owner), value_at, 2)
        @test isread(value_at(J, owner, cv), value_at, 3)
        # unwrapped terms (as a compiler walking a term tree holds them) build the same read
        @test isequal(value_at(unwrap(cv), unwrap(owner)), unwrap(value_at(cv, owner)))
        @test isequal(value_at(unwrap(J), unwrap(owner), unwrap(cv)), unwrap(value_at(J, owner, cv)))
        @test contains_var(value_at(cv, owner), owner) && contains_var(value_at(J, owner, 0), J)
    end
end

@testitem "operators inside a PDESystem" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "operators inside a PDESystem" begin
        pd = PDESystem(eqs, bcs, dom, [t, x, y], [ce, oe, Ke, ke, ve], [Dc, α, ε, Dk, K0, J]; name = :ops)
        @test length(pd.eqs) == 3 && length(pd.bcs) == 2
        @test has_op(pd.eqs[1].rhs, laplacian) && has_op(pd.eqs[1].rhs, ismember)
        @test has_op(pd.eqs[2].rhs, DivKGrad) && has_op(pd.eqs[2].rhs, Advect) && has_op(pd.eqs[2].rhs, value_at)
        @test has_op(pd.eqs[3].rhs, value_at)
        @test has_op(pd.bcs[1].rhs, masked) && has_op(pd.bcs[2].rhs, ismember)
        # get_variables sees every symbolic argument of an operator
        @test all(v -> contains_var(eqs[2].rhs, v), (Ke, oe, ke, Dk))
        @test contains_var(value_at(J, ke, ke), J)
    end
end

@testitem "operators survive substitute and simplify" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "operators survive substitute and simplify" begin
        e2 = eqs[2].rhs
        s1 = substitute(e2, Dict(Dk => [5.0, 6.0, 7.0]))
        @test has_op(s1, DivKGrad) && has_op(s1, value_at) && dkg(s1).mean === :harmonic
        s2 = substitute(e2, Dict(oe => ce))                                 # field rename
        @test has_op(s2, Advect) && contains_var(s2, ce) && !contains_var(s2, oe)
        s3 = simplify(e2)
        @test has_op(s3, DivKGrad) && has_op(s3, Advect) && has_op(s3, value_at) && dkg(s3).mean === :harmonic
        s4 = simplify(laplacian(ce) + laplacian(ce))
        @test has_op(s4, laplacian)
        @test symzero(simplify(laplacian(ce) - laplacian(ce)))                          # one term, not two opaque ones
        s5 = simplify(DivKGrad(:arithmetic)(Ke, ce) * 1)
        @test dkg(s5).mean === :arithmetic
        s6 = simplify(substitute(masked(ke == 3, α), Dict(α => 0.0)))
        @test has_op(s6, masked)
        # registered predicates fold only with `fold = Val(true)` (P3-mtk O)
        r = eqs[1].rhs
        @test has_op(substitute(r, Dict(ke => 2)), ismember)
        folded = substitute(r, Dict(ke => 2); fold = Val(true))
        @test !has_op(folded, ismember) && symzero(simplify(folded - (α + Dc * laplacian(ce))))
    end
end

@testitem "mtkcompile(; inputs) with value_at / ismember" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "mtkcompile(; inputs) with value_at / ismember" begin
        @variables q(t) = 1.0 kc(t)::Int [input = true] kcp(t)::Int [input = true]
        @parameters Jk[1:3] = [10.0, 20.0, 30.0] J2[1:3, 1:3] = reshape(collect(1.0:9.0), 3, 3)
        du(prob) = (u = copy(prob.u0); d = similar(u); prob.f(d, u, prob.p, 0.0); d)
        # FR-36 (MTKBase 1.77.0-1.77.4): with two or more Int inputs, `complete` asserts that the
        # `inputs` order matches its own parameter order, which comes from a `Set` (hash order,
        # so it differs between machines). Try the given order, then the reverse.
        function compile_inputs(sys, ins)
            try
                return mtkcompile(sys; inputs = ins)
            catch e
                (e isa AssertionError && length(ins) > 1) || rethrow()
                return mtkcompile(sys; inputs = reverse(ins))
            end
        end
        cases = [
            (D(q) ~ -q + value_at(Jk, kc), [kc], [kc => 2], 19.0, Jk),
            (D(q) ~ -q + value_at(J2, kc, kcp), [kc, kcp], [kc => 2, kcp => 3], 7.0, J2),
            (D(q) ~ -q + 5 * ismember(kc, (2, 3)), [kc], [kc => 3], 4.0, nothing)]
        for (eq, ins, iv, expect, table) in cases
            sys = System([eq], t; name = :cell)
            table === nothing || @test any(p -> isequal(p, unwrap(table)), parameters(sys))   # discovered
            cs = compile_inputs(sys, ins)
            @test isequal(unknowns(cs), [unwrap(q)])                       # inputs are not unknowns
            prob = ODEProblem(cs, [q => 1.0; iv], (0.0, 1.0))
            @test du(prob) ≈ [expect]
        end
        # ismember with a kind outside the set: the source is off
        cs = mtkcompile(System([D(q) ~ -q + 5 * ismember(kc, (2, 3))], t; name = :cell); inputs = [kc])
        @test du(ODEProblem(cs, [q => 1.0, kc => 1], (0.0, 1.0))) ≈ [-1.0]
        # negative control: MTK `getindex` on an array parameter keeps the input as an unknown
        cs = mtkcompile(System([D(q) ~ -q + Jk[kc]], t; name = :cell); inputs = [kc])
        @test any(u -> isequal(u, unwrap(kc)), unknowns(cs))
        @test_throws MTKB.IncompleteInitializationError ODEProblem(cs, [q => 1.0, kc => 2], (0.0, 1.0))
    end
end

@testitem "operators refuse symbolic differentiation" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "operators refuse symbolic differentiation" begin
        Dx = Differential(x)
        # a kind-table read: Symbolics refuses differentiation through the array argument itself
        @test_throws ["Differentiation with array expressions"] Symbolics.expand_derivatives(Dx(value_at(Dk, ke)))
        @test_throws ["Differentiation with array expressions"] Symbolics.expand_derivatives(Dx(value_at(J, ke, ke)))
        for term in (
                laplacian(ce), DivKGrad(:harmonic)(Ke, ce), Advect(Upwind1())(ve[1], ce), value_at(ce, ke),
            ismember(ke, (2, 3)), masked(ke == 3, ce))
            err = try
                Symbolics.expand_derivatives(Dx(term))
            catch e
                e
            end
            @test err isa ArgumentError && occursin("opaque to symbolic differentiation", err.msg)
        end
        # negative control: an operator that does not depend on the variable differentiates to 0
        @test symzero(Symbolics.expand_derivatives(Differential(α)(laplacian(ce))))
        @test symzero(Symbolics.expand_derivatives(Dx(α * Dc)))
    end
end

@testitem "masked refuses a ∈ predicate with the ismember form" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "masked refuses a ∈ predicate with the ismember form" begin
        @test_throws ArgumentError masked(ke ∈ (2, 3), 0.0)
        @test_throws ArgumentError masked(ke ∈ Set([2, 3]), 0.0)                  # `false`: evaluates, refused
        @test opof(masked(ismember(ke, (2, 3)), 0.0)) === masked            # negative control
    end
end

@testitem "metadata keys" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "metadata keys" begin
        @parameters dx [lattice_spacing = 1] dy [lattice_spacing = 2] h
        @variables u(..) [lattice_placement = :node, lattice_storage = :dense, lattice_level = 2] w(..)
        @variables kd(..)::Int32 [input = true, lattice_input_name = "kind"]
        @test get_lattice_spacing(dx) == 1 && get_lattice_spacing(dy) == 2
        @test get_lattice_spacing(h) === nothing                            # untagged: the name does not count
        ue, we, kde = u(t, x, y), w(t, x, y), kd(t, x, y)
        @test get_lattice_placement(ue) === :node
        @test get_lattice_storage(ue) === :dense
        @test get_lattice_level(ue) == 2
        @test get_lattice_input_name(kde) == "kind" && MTKB.isinput(kde)
        @test all(f -> f(we) === nothing, (get_lattice_placement, get_lattice_storage, get_lattice_level,
                get_lattice_input_name,
            )
        )
        # the keys read back from the stored dependent variables
        pd = PDESystem(
            [D(ue) ~ laplacian(ue) + kde, D(we) ~ laplacian(we)], Equation[], dom, [t, x, y], [ue, we, kde], Num[];
            name = :meta)
        @test get_lattice_placement(pd.dvs[1]) === :node && get_lattice_input_name(pd.dvs[3]) == "kind"
        @test get_lattice_placement(pd.dvs[2]) === nothing
        # and survive an offset read and a substitution
        @test get_lattice_input_name(kd(t, x + dx, y)) == "kind"
        @test get_lattice_spacing(only(filter(v -> isequal(v, unwrap(dx)),
            collect(vars(substitute(ue + dx * h, Dict(h => 2.0))))))) == 1
    end
end

@testitem "Shift(t, 1) map form survives substitute and simplify" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "Shift(t, 1) map form survives substitute and simplify" begin
        @parameters dx [lattice_spacing = 1] Dm = 1
        @variables N(..)
        Ne = N(t, x, y)
        rhs = Dm * (N(t, x + dx, y) + N(t, x - dx, y)) / 2
        mapeq = Shift(t, 1)(Ne) ~ rhs
        for e in (substitute(mapeq, Dict(Dm => 1)), Equation(simplify(mapeq.lhs), simplify(mapeq.rhs)))
            op = opof(e.lhs)
            @test op isa Shift && op.steps == 1 && isequal(arguments(unwrap(e.lhs))[1], unwrap(Ne))
        end
        @test isempty(vocabulary_issues([mapeq]))
    end
end

@testitem "scans" setup = [LP_latticepde] tags = [:latticepde, :vocabulary] begin
    @testset "scans" begin
        @variables N(..)
        Ne = N(t, x, y)
        k = ShiftIndex(t, 1)
        clean = PDESystem(eqs, bcs, dom, [t, x, y], [ce, oe, Ke, ke, ve], [Dc, α, ε, Dk, K0, J]; name = :ok)
        @test isempty(vocabulary_issues(clean))                            # negative control for every scan
        @test check_vocabulary(clean) === nothing
        has(issues, s) = length(issues) == 1 && occursin(s, only(issues))

        # VarDomainPairing: `∈` with a tuple builds an interval, as a whole entry or a side
        @test unwrap(ke ∈ (2, 3)) isa Symbolics.VarDomainPairing           # the MTK behavior the scan relies on
        @test has(vocabulary_issues(Equation[], Any[ke ∈ (2, 3)]), "domain pairing")
        @test has(vocabulary_issues(Equation[], [ce ~ (ke ∈ (2, 3))]), "ismember(")
        @test isempty(vocabulary_issues(Equation[], [ce ~ ismember(ke, (2, 3))]))

        # `∈ Set` as a whole side is the literal false
        @test has(vocabulary_issues(Equation[], [ce ~ (ke ∈ Set([2, 3]))]), "literal `false`")
        # pinned hazard (documented, not scannable): inside a product the term is gone
        hazard = D(ce) ~ α * (ke ∈ Set([2, 3])) - ε * ce
        @test !contains_var(hazard.rhs, α) && isempty(vocabulary_issues([hazard]))

        # `∈ Set` as an operator argument: `masked(false, α)` builds when the value is symbolic
        m = ce ~ masked(ke ∈ Set([2, 3]), α)
        @test unwrap_const(arguments(unwrap(m.rhs))[1]) === false
        @test has(vocabulary_issues(Equation[], [m]), "literal `Bool` argument")
        @test has(vocabulary_issues([D(ce) ~ DivKGrad(:harmonic)(ke ∈ Set([2]), ce)]), "ismember(")
        @test isempty(vocabulary_issues(Equation[], [ce ~ masked(ismember(ke, (2, 3)), α)]))

        # `in(·, ::Vector)`: a valid term that is not a kind set
        bad = D(ce) ~ α * (ke ∈ [2, 3]) - ε * ce
        @test opof(ke ∈ [2, 3]) === in
        @test has(vocabulary_issues([bad]), "`in` term")
        @test has(vocabulary_issues([D(ce) ~ laplacian(ce) * (ke ∈ [2, 3])]), "ismember(")
        @test isempty(vocabulary_issues([D(ce) ~ α * ismember(ke, (2, 3)) - ε * ce]))

        # ShiftIndex arguments: `N(k + 1)` on the callable builds a garbage term silently
        g = N(k + 1)
        @test unwrap_const(only(arguments(unwrap(g)))) isa ShiftIndex
        @test has(vocabulary_issues([g ~ Ne]), "Shift(t, 1)(c(t, x, y))")
        @test has(vocabulary_issues([Shift(t, 1)(Ne) ~ laplacian(N(k + 1))]), "ShiftIndex")   # nested in an operator
        @test_throws ["Cannot shift an expression with multiple independent variables"] Ne(k + 1)                                    # MTK refuses the applied form itself
        @test isempty(vocabulary_issues([Shift(t, 1)(Ne) ~ laplacian(Ne)]))

        # Pre: the callback previous value
        @test has(vocabulary_issues([D(ce) ~ Pre(ce) - ce]), "`Pre`")
        @test has(vocabulary_issues(Equation[], [Equation([ce, Pre(ce)], [0.0, 0.0])]), "`Pre`")   # array side
        @test isempty(vocabulary_issues([D(ce) ~ laplacian(ce) - ce]))

        # check_vocabulary refuses every issue
        @test_throws ArgumentError check_vocabulary([bad, D(ce) ~ Pre(ce)], [ce ~ (ke ∈ (2, 3))])
        pd = PDESystem([bad], Equation[], dom, [t, x, y], [ce, ke], [α, ε]; name = :bad)
        @test_throws ArgumentError check_vocabulary(pd)
    end
end
