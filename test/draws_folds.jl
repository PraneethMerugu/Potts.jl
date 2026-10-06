# D-150: the contact fold `count(pred for _ in contacts)` and `randn()` in the DSL. The frozen
# acceptance file (lib/PottsModels/test/acceptance/p6_15c_openvt_table_s1.jl) checks their
# values; this file checks what the DSL rejects, by name (ruling 5: a Base RNG call never
# silently becomes a build-time constant), and that models without them are unchanged.
using Test, Potts
using Potts: CorePotts

# a model whose body is `ex` (an update, energy, …) on a small two-kind lattice
function _df_model(sections::Expr...; extra = false)
    m = Module()
    Core.eval(m, :(using Potts))
    Core.eval(m, quote
        @potts_model DF begin
            @kinds medium A B
            @parameters begin
                T = 4.0
                q = 0.5
            end
            @variables begin
                x(cell) = 0.0
                y(site) = 0.0
                z(model) = 0.0
            end
            @lattice Lattice((12, 12); boundary = Closed(), neighborhood = Moore(1))
            @relations begin
                proposal = Moore(1)
                vn = VonNeumann(1)
                big = $(extra ? :(Moore(2)) : :(VonNeumann(1)))
                half = $(extra ? :(Stencil([(1, 0), (0, 1)])) : :(VonNeumann(1)))
            end
            @energy cells(A, B) => (volume - 9)^2
            $(sections...)
            @sweep Metropolis(; temperature = T)
        end
    end)
    return Core.eval(m, :(DF(; name = :df)))
end
_df_build(sections::Expr...; extra = false) = mtkcompile(_df_model(sections...; extra))
_df_state() = (σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1; σ[5:7, 2:4] .= 2; σ[9:11, 9:11] .= 3; [ownership => σ, kind => [:A, :B, :A]])

"""The message of the error `f()` throws, unwrapping `LoadError`s and located errors."""
function _df_msg(f)
    try
        f()
    catch e
        while e isa LoadError
            e = e.error
        end
        return sprint(showerror, e)
    end
    return ""
end

@testset "D-150: Base RNG calls in a model are rejected by name" begin
    for (call, shown) in (
            (:(rand(1:3)), "rand(1:3)"), (:(rand(2)), "rand(2)"), (:(randn(3)), "randn(3)"),
            (:(randn(Float32)), "randn(Float32)"), (:(randexp()), "randexp()"), (:(Base.rand()), nothing),
            (:(Random.randn(2, 3, 4)), "randn(2, 3, 4)"), (:(Random.randexp(2)), "randexp(2)"),
            (:(shuffle([1, 2])), "shuffle([1, 2])"), (:(randn(; lower = 0.0)), "randn(lower = 0.0)"))
        ex = :(@after_mcs x ~ $call)
        if shown === nothing          # `Base.rand()` is the model's `rand()` (a draw, not a constant)
            c = _df_build(ex)
            @test any(u -> Potts._has_draw(u.eq.rhs), getfield(c.sys, :updates))
        else
            msg = _df_msg(() -> _df_build(ex))
            @test occursin("`$shown`", msg) && occursin("not available in a model", msg)
        end
    end
    # the model's own forms build and draw
    for call in (:(rand()), :(randn()), :(randn(1.0, 2.0)), :(randn(q, 2.0; lower = 0.0)))
        c = _df_build(:(@after_mcs x ~ $call))
        @test any(u -> Potts._has_draw(u.eq.rhs), getfield(c.sys, :updates))
    end
    # a plain helper computing a constant from Base's RNG is rejected too (it would be fixed at build)
    @test occursin("`rand(1:6)`", _df_msg(() -> _df_build(:(@after_mcs x ~ q * rand(1:6)))))
    # not a model quantity where draws are not allowed
    @test occursin("randn()", _df_msg(() -> PottsProblem(_df_model(:(@energy cells(A) => randn() * volume)), _df_state(), (0, 1))))
end

@testset "D-150: the contact fold's scope and predicate" begin
    # fine: cell updates, division conditions, cell observed, a population over cells
    c = _df_build(:(@after_mcs x ~ count(kind′ == medium for _ in contacts) + count(kind′ == B for _ in contacts(vn))),
        :(@divide cells(A) when = count(true for _ in contacts) > 100, along = RandomPlane()),
        :(@after_mcs z ~ sum(count(true for _ in contacts) for c in cells(A))),
        :(@observed m ~ count(kind′ == medium for _ in contacts(big))); extra = true)
    @test length(Potts._contact_folds(c.sys)) == 4
    @test Set(r for (_, r, _) in Potts._contact_folds(c.sys)) == Set([:contact, :vn, :big])
    @test c.footprint.read == 2                                   # the Moore(2) fold's commit reads that far
    prob = PottsProblem(c, _df_state(), (0, 3); capacity = 8)
    @test haskey(prob.relations, :contact_counts) && length(prob.relations.contact_counts.counts) == 4
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
    @test length(sol[:m][end]) == 8
    # `cond` folds into the kind set, and equal kind sets written alike share one tracker
    a = _df_build(:(@after_mcs x ~ count(kind′ == B for _ in contacts) + count(true for _ in contacts if kind′ == B) +
                                   count((kind′ == A) | (kind′ == medium) for _ in contacts(vn))))
    @test length(Potts._contact_folds(a.sys)) == 2
    @test sort(last.(Potts._contact_trackers(a))) == [UInt64(0b011), UInt64(0b100)]
    # rejected, each with a message naming the rule
    for (sections, needle) in (
            ((:(@energy cells(A) => count(true for _ in contacts)),), "not available in a cell term"),
            ((:(@drive copy => count(true for _ in contacts)),), "not available in a drive"),
            ((:(@after_mcs z ~ count(true for _ in contacts)),), "not available in a model update"),
            ((:(@after_mcs y ~ count(true for _ in contacts)),), "not available in a site update"),
            ((:(@after_mcs x ~ count(kind′ == q for _ in contacts)),), "may read only `kind′`"),
            ((:(@after_mcs x ~ count(kind == A for _ in contacts)),), "may read only `kind′`"),
            ((:(@after_mcs x ~ sum(1.0 for _ in contacts)),), "only `count(pred for _ in contacts)`"),
            ((:(@after_mcs x ~ count(true for _ in contacts(nowhere))),), "nowhere"),
            ((:(@after_mcs x ~ count(true for _ in contacts(half))),), "not symmetric"))
        msg = _df_msg(() -> _df_build(sections...; extra = true))
        @test occursin(needle, msg)
    end
    # `count` stays Base's elsewhere: a population fold and a plain helper
    p = _df_build(:(@after_mcs z ~ count(volume > 5 for c in cells)))
    @test !any(u -> occursin("contacts_", string(u.eq.rhs)), getfield(p.sys, :updates))
    @test Potts.DSL.count(isodd, [1, 2, 3]) == 2 && nameof(Potts.DSL.count) === :count
end

@testset "D-150: models without folds or draws generate what they did" begin
    c = _df_build(:(@after_mcs x ~ volume + 1))
    prob = PottsProblem(c, _df_state(), (0, 1))
    @test !haskey(prob.relations, :contact_counts) && !haskey(prob.u0.model, CorePotts.MODEL_STATUS)
    @test !occursin("contact_count", string(generated_code(c)))
    b = PottsProblem(_df_build(:(@after_mcs x ~ randn(0.0, 1.0; lower = 5.0))), _df_state(), (0, 1))
    @test haskey(b.u0.model, CorePotts.MODEL_STATUS)
    # exhaustion (P ≈ 3·10⁻⁷ per attempt, 64 attempts) fails the run instead of throwing
    b10 = PottsProblem(_df_build(:(@after_mcs x ~ randn(0.0, 1.0; lower = 10.0))), _df_state(), (0, 4))
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(b10, alg; saveat = 1)
        @test sol.retcode == Potts.SciMLBase.ReturnCode.Failure && isnan(sol.u[end].cell.x[1]) && sol.t[end] == 1
    end
end
