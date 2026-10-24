# LatticePDE vocabulary (v3 §5.1, §5.5): registered operators, metadata keys and scans.
# Ported from the pass-3 probes (research/field-compiler/pass3/mtk/o1_operators.jl, n7_map.jl,
# s2_coupling.jl) on ModelingToolkitBase 1.77.
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
# the byte-identity gate of the update pass (F2-07) runs in every owned `discretize` of the suite
get!(ENV, "LATTICEPDE_CHECK_FUSION", "1")

opof(e) = (u = unwrap(e); iscall(u) ? operation(u) : nothing)
function ops(e)                                     # every operation in the term tree
    out = Any[]
    walk(u) = iscall(u) && (push!(out, operation(u)); foreach(walk, arguments(u)))
    walk(unwrap(e))
    return out
end
has_op(e, f) = any(g -> g === f || (f isa Type && g isa f), ops(e))
dkg(e) = only(filter(f -> f isa DivKGrad, ops(e)))
vars(e) = Set(Symbolics.get_variables(e))
contains_var(e, v) = any(x -> isequal(x, unwrap(v)), vars(e))
symzero(e) = (v = unwrap_const(unwrap(e)); v isa Number && iszero(v))   # SymbolicUtils 4 wraps literals in Const

@parameters x y Dc = 1e-3 α = 1.0 ε = 0.5 K0 = 2.0
@parameters Dk[1:3] = [1.0, 2.0, 3.0] J[1:3, 1:3]
@variables c(..) o(..) K(..) kindₛ(..)::Int32 [input = true] vel(..)[1:2] [input = true]
ce, oe, Ke, ke, ve = c(t, x, y), o(t, x, y), K(t, x, y), kindₛ(t, x, y), vel(t, x, y)
dom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]

eqs = [D(ce) ~ Dc * Δ(ce) + α * ismember(ke, (2,)) - ε * ce * ismember(ke, (1,)),
    D(oe) ~ DivKGrad(:harmonic)(Ke, oe) - at(Dk, ke) * oe - Advect(Upwind1())(ve[1], oe),
    Ke ~ K0 * (1 + ismember(ke, (2, 3))) + at2(J, ke, ke)]
bcs = [ce ~ masked(ke == 3, 0.0), oe ~ masked(ismember(ke, (2, 3)), 1.0)]

@testset "LatticePDE" begin
    @testset "operators are positional registered terms" begin
        @test opof(Δ(ce)) === Δ
        @test opof(DivKGrad(:harmonic)(Ke, ce)) == DivKGrad(:harmonic)
        @test opof(DivKGrad(:arithmetic)(Ke, ce)).mean === :arithmetic
        @test opof(Advect(Upwind1())(ve[1], ce)) isa Advect{Upwind1}
        @test opof(Advect(Upwind1())(ve, ce)) isa Advect{Upwind1}           # velocity array
        @test contains_var(Advect(Upwind1())(ve, ce), ce)
        @test opof(at(Dk, ke)) === at
        @test opof(at(ce, ke)) === at                                       # a site read
        @test opof(at2(J, ke, ke)) === at2
        @test opof(ismember(ke, (2, 3))) === ismember
        @test opof(masked(ke == 3, 0.0)) === masked
        # options are struct fields, never keywords (S-3)
        @test_throws MethodError DivKGrad(; mean = :harmonic)
        @test_throws MethodError Advect(; scheme = Upwind1())
        @test_throws ArgumentError DivKGrad(:geometric)                     # negative control: the mean is checked
        @test_throws MethodError Advect(:upwind)                            # a scheme is an AdvectionScheme
        # the field operators never evaluate; the CPM reads do
        @test_throws ErrorException Δ(1.0)
        @test_throws ErrorException DivKGrad(:harmonic)(1.0, 2.0)
        @test at([10.0, 20.0, 30.0], 2.0) == 20.0
        @test at2(reshape(collect(1.0:9.0), 3, 3), 2, 3) == 8.0
        @test ismember(Int32(3), (2, 3)) && !ismember(1.0, (2, 3))
    end

    @testset "reads take any index: literal codes, Real-typed inputs, unwrapped terms" begin
        @variables owner(t) cv(t) flag(t)::Bool
        isread(e, f, n) = opof(e) === f && length(arguments(unwrap(e))) == n
        # literal kind codes into symbolic tables (the medium is 0): a term, not a symbolic
        # array indexed by the literal (negative control: the numeric method still evaluates)
        @test isread(at(Dk, 0), at, 2) && unwrap_const(arguments(unwrap(at(Dk, 0)))[2]) == 0
        @test isread(at2(J, 0, 1), at2, 3) && isread(at2(J, ke, 0), at2, 3) && isread(at2(J, 0, ke), at2, 3)
        @test at([10.0, 20.0, 30.0], 1) == 10.0
        # a site or cell value at a literal, at a Real-typed input, and a Bool-typed value
        @test isread(at(cv, 3), at, 2) && isread(at(cv, owner), at, 2) && isread(at(flag, owner), at, 2)
        @test isread(at2(J, owner, cv), at2, 3)
        # unwrapped terms (as a compiler walking a term tree holds them) build the same read
        @test isequal(at(unwrap(cv), unwrap(owner)), unwrap(at(cv, owner)))
        @test isequal(at2(unwrap(J), unwrap(owner), unwrap(cv)), unwrap(at2(J, owner, cv)))
        @test contains_var(at(cv, owner), owner) && contains_var(at2(J, owner, 0), J)
    end

    @testset "operators inside a PDESystem" begin
        pd = PDESystem(eqs, bcs, dom, [t, x, y], [ce, oe, Ke, ke, ve], [Dc, α, ε, Dk, K0, J]; name = :ops)
        @test length(pd.eqs) == 3 && length(pd.bcs) == 2
        @test has_op(pd.eqs[1].rhs, Δ) && has_op(pd.eqs[1].rhs, ismember)
        @test has_op(pd.eqs[2].rhs, DivKGrad) && has_op(pd.eqs[2].rhs, Advect) && has_op(pd.eqs[2].rhs, at)
        @test has_op(pd.eqs[3].rhs, at2)
        @test has_op(pd.bcs[1].rhs, masked) && has_op(pd.bcs[2].rhs, ismember)
        # get_variables sees every symbolic argument of an operator
        @test all(v -> contains_var(eqs[2].rhs, v), (Ke, oe, ke, Dk))
        @test contains_var(at2(J, ke, ke), J)
    end

    @testset "operators survive substitute and simplify" begin
        e2 = eqs[2].rhs
        s1 = substitute(e2, Dict(Dk => [5.0, 6.0, 7.0]))
        @test has_op(s1, DivKGrad) && has_op(s1, at) && dkg(s1).mean === :harmonic
        s2 = substitute(e2, Dict(oe => ce))                                 # field rename
        @test has_op(s2, Advect) && contains_var(s2, ce) && !contains_var(s2, oe)
        s3 = simplify(e2)
        @test has_op(s3, DivKGrad) && has_op(s3, Advect) && has_op(s3, at) && dkg(s3).mean === :harmonic
        s4 = simplify(Δ(ce) + Δ(ce))
        @test has_op(s4, Δ)
        @test symzero(simplify(Δ(ce) - Δ(ce)))                          # one term, not two opaque ones
        s5 = simplify(DivKGrad(:arithmetic)(Ke, ce) * 1)
        @test dkg(s5).mean === :arithmetic
        s6 = simplify(substitute(masked(ke == 3, α), Dict(α => 0.0)))
        @test has_op(s6, masked)
        # registered predicates fold only with `fold = Val(true)` (P3-mtk O)
        r = eqs[1].rhs
        @test has_op(substitute(r, Dict(ke => 2)), ismember)
        folded = substitute(r, Dict(ke => 2); fold = Val(true))
        @test !has_op(folded, ismember) && symzero(simplify(folded - (α + Dc * Δ(ce))))
    end

    @testset "mtkcompile(; inputs) with at / at2 / ismember (F-5)" begin
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
        cases = [(D(q) ~ -q + at(Jk, kc), [kc], [kc => 2], 19.0, Jk),
            (D(q) ~ -q + at2(J2, kc, kcp), [kc, kcp], [kc => 2, kcp => 3], 7.0, J2),
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
        @test_throws Exception ODEProblem(cs, [q => 1.0, kc => 2], (0.0, 1.0))
    end

    @testset "operators refuse symbolic differentiation" begin
        Dx = Differential(x)
        # a kind-table read: Symbolics refuses differentiation through the array argument itself
        @test_throws Exception Symbolics.expand_derivatives(Dx(at(Dk, ke)))
        @test_throws Exception Symbolics.expand_derivatives(Dx(at2(J, ke, ke)))
        for term in (Δ(ce), DivKGrad(:harmonic)(Ke, ce), Advect(Upwind1())(ve[1], ce), at(ce, ke),
            ismember(ke, (2, 3)), masked(ke == 3, ce))
            err = try
                Symbolics.expand_derivatives(Dx(term))
            catch e
                e
            end
            @test err isa ArgumentError && occursin("opaque to symbolic differentiation", err.msg)
        end
        # negative control: an operator that does not depend on the variable differentiates to 0
        @test symzero(Symbolics.expand_derivatives(Differential(α)(Δ(ce))))
        @test symzero(Symbolics.expand_derivatives(Dx(α * Dc)))
    end

    @testset "masked refuses a ∈ predicate with the ismember form" begin
        err = try
            masked(ke ∈ (2, 3), 0.0)
        catch e
            e
        end
        @test err isa ErrorException && occursin("ismember", err.msg)
        err = try
            masked(ke ∈ Set([2, 3]), 0.0)                                   # `false`: evaluates, refused
        catch e
            e
        end
        @test err isa ErrorException && occursin("ismember", err.msg)
        @test opof(masked(ismember(ke, (2, 3)), 0.0)) === masked            # negative control
    end

    @testset "metadata keys" begin
        @parameters dx [lattice_spacing = 1] dy [lattice_spacing = 2] h
        @variables u(..) [lattice_placement = :node, lattice_storage = :dense, lattice_level = 2] w(..)
        @variables kd(..)::Int32 [input = true, potts_entity = :site_kind]
        @test get_lattice_spacing(dx) == 1 && get_lattice_spacing(dy) == 2
        @test get_lattice_spacing(h) === nothing                            # untagged: the name does not count
        ue, we, kde = u(t, x, y), w(t, x, y), kd(t, x, y)
        @test get_lattice_placement(ue) === :node
        @test get_lattice_storage(ue) === :dense
        @test get_lattice_level(ue) == 2
        @test get_potts_entity(kde) === :site_kind && MTKB.isinput(kde)
        @test all(f -> f(we) === nothing, (get_lattice_placement, get_lattice_storage, get_lattice_level,
            get_potts_entity))
        # the keys read back from the stored dependent variables
        pd = PDESystem([D(ue) ~ Δ(ue) + kde, D(we) ~ Δ(we)], Equation[], dom, [t, x, y], [ue, we, kde], Num[];
            name = :meta)
        @test get_lattice_placement(pd.dvs[1]) === :node && get_potts_entity(pd.dvs[3]) === :site_kind
        @test get_lattice_placement(pd.dvs[2]) === nothing
        # and survive an offset read and a substitution
        @test get_potts_entity(kd(t, x + dx, y)) === :site_kind
        @test get_lattice_spacing(only(filter(v -> isequal(v, unwrap(dx)),
            collect(vars(substitute(ue + dx * h, Dict(h => 2.0))))))) == 1
    end

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
        @test has(vocabulary_issues([D(ce) ~ Δ(ce) * (ke ∈ [2, 3])]), "ismember(")
        @test isempty(vocabulary_issues([D(ce) ~ α * ismember(ke, (2, 3)) - ε * ce]))

        # ShiftIndex arguments: `N(k + 1)` on the callable builds a garbage term silently
        g = N(k + 1)
        @test unwrap_const(only(arguments(unwrap(g)))) isa ShiftIndex
        @test has(vocabulary_issues([g ~ Ne]), "Shift(t, 1)(c(t, x, y))")
        @test has(vocabulary_issues([Shift(t, 1)(Ne) ~ Δ(N(k + 1))]), "ShiftIndex")   # nested in an operator
        @test_throws Exception Ne(k + 1)                                    # MTK refuses the applied form itself
        @test isempty(vocabulary_issues([Shift(t, 1)(Ne) ~ Δ(Ne)]))

        # Pre: the callback previous value
        @test has(vocabulary_issues([D(ce) ~ Pre(ce) - ce]), "`Pre`")
        @test has(vocabulary_issues(Equation[], [Equation([ce, Pre(ce)], [0.0, 0.0])]), "`Pre`")   # array side
        @test isempty(vocabulary_issues([D(ce) ~ Δ(ce) - ce]))

        # check_vocabulary lists every issue and names the fix
        err = try
            check_vocabulary([bad, D(ce) ~ Pre(ce)], [ce ~ (ke ∈ (2, 3))])
        catch e
            e
        end
        @test err isa ArgumentError && occursin("3 terms", err.msg)
        @test occursin("ismember(kindₛ, (2, 3))", err.msg) && occursin("Shift(t, 1)", err.msg)
        pd = PDESystem([bad], Equation[], dom, [t, x, y], [ce, ke], [α, ε]; name = :bad)
        @test_throws ArgumentError check_vocabulary(pd)
    end

    include("discretize.jl")
    include("problems.jl")
    include("silent.jl")
    include("groups.jl")
    include("integ_ps.jl")
    include("groups_coupling.jl")
    include("implicit.jl")
    include("clock.jl")
    include("numbers.jl")
    include("example.jl")
    isempty(get(ENV, "LATTICEPDE_GPU", "")) || include("device.jl")

    @testset "QA" begin
        using Aqua, ExplicitImports
        Aqua.test_all(LatticePDE; ambiguities = false)
        @test isempty(Test.detect_ambiguities(LatticePDE))
        @test check_no_implicit_imports(LatticePDE) === nothing
        @test check_no_stale_explicit_imports(LatticePDE) === nothing
        @test check_all_qualified_accesses_via_owners(LatticePDE) === nothing
        # `VarDomainPairing` (what `x ∈ (a, b)` builds) is not declared public by Symbolics
        @test check_all_explicit_imports_are_public(LatticePDE; ignore = (:VarDomainPairing,)) === nothing
        # `get_unit` (MTK unit inference, which registered operators extend) is
        # not declared public by ModelingToolkitBase
        @test check_all_qualified_accesses_are_public(LatticePDE; ignore = (:get_unit,)) === nothing
        # no model, paper or author names in the package or its tests (BRIEF rules)
        files = [joinpath(d, f) for dir in ("src", "test") for (d, _, fs) in walkdir(joinpath(@__DIR__, "..", dir))
                 for f in fs if endswith(f, ".jl")]
        banned = Regex("\\b(" * join(["Jiang", "Merks", "Bauer", "Graner", "Glazier", "Fortuna", "Hogeweg", "Szabo",
                                        "Marée", "FBCA", "OpenVT"], "|") * ")\\b")
        @test isempty(filter(f -> normpath(f) != normpath(@__FILE__) && occursin(banned, read(f, String)), files))
        @test !any(f -> occursin("@generated", read(f, String)), filter(f -> occursin("/src/", f), files))
    end
end
