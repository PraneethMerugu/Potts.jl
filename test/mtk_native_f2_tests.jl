# F2 metadata parity (`tunable`, `bounds`, `description`), component bindings/initial values,
# and computed parameter routes & diagnostic messages.

@testitem "F2-14: tunable, bounds, description" setup = [F2MetadataSetup] tags = [:potts, :mtk_native] begin
    @testset "F2-14: tunable, bounds, description" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1
        op = [ownership => σ, kind => [1]]
        sys = F2Meta(; name = :m)
        prob = PottsProblem(sys, op, (0, 2))
        # `tunable = false`: T is a constant (control: the model without metadata tunes T)
        @test SS.canonicalize(SS.Tunable(), prob.p)[1] == [2.0, 9.0]
        @test SS.canonicalize(SS.Constants(), prob.p)[1] == [1.0]
        p0 = PottsProblem(F2NoMeta(; name = :m), op, (0, 2)).p
        @test SS.canonicalize(SS.Tunable(), p0)[1] == [1.0, 2.0, 9.0] && typeof(p0) == typeof(Potts.PottsParameters(NamedTuple(p0)))
        # the metadata is MTK's
        λs = only(x for x in MTKB.parameters(sys) if Symbol(x) === :λ)
        Ts = only(x for x in MTKB.parameters(sys) if Symbol(x) === :T)
        @test MTKB.getbounds(λs) == (0, 5) && MTKB.getdescription(λs) == "volume strength" && !MTKB.istunable(Ts)
        @test occursin("λ (\"volume strength\")", sprint(show, MIME"text/plain"(), sys))
        # `bounds`: refused at build, by `remake`, `setp`, `integ.ps`, `replace`; nothing changes
        bound(e) = occursin("parameter `λ` = 7.0 is outside its declared bounds (0, 5)", e)
        @test bound(emsg(() -> PottsProblem(sys, [op; :λ => 7.0], (0, 2))))
        @test bound(emsg(() -> Potts.SciMLBase.remake(prob; p = [:λ => 7.0])))
        integ = init(prob, SequentialCPM())
        @test bound(emsg(() -> setp(integ, :λ)(integ, 7.0))) && getp(integ, :λ)(integ) == 2.0
        @test bound(emsg(() -> (integ.ps[:λ] = 7.0))) && integ.ps[:λ] == 2.0
        @test bound(emsg(() -> setp(integ, [:V₀, :λ])(integ, [4.0, 7.0]))) && integ.ps[:V₀] == 9.0   # a list: none set
        @test bound(emsg(() -> SS.replace(SS.Tunable(), prob.p, [7.0, 9.0])))
        @test occursin("is outside its declared bounds", emsg(() -> F2Meta(; name = :m, λ = -1.0) |> m -> PottsProblem(m, op, (0, 2))))
        integ.ps[:λ] = 5.0
        @test integ.ps[:λ] == 5.0
        # options that are not MTK's are named
        @test occursin(
            "option `tunabel`", emsg(
                () -> Potts._potts_model(
                    :Bad, quote
                        @kinds medium cell
                        @parameters k = 1.0, [tunabel = false]
                    end, @__MODULE__
                )
            )
        )
    end
end

@testitem "F2-14: component bindings and initial values of parameters" setup = [F2MetadataSetup] tags = [:potts, :mtk_native] begin
    @testset "F2-14: component bindings and initial values of parameters" begin
        t = Potts.t
        σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
        op = [ownership => σ, kind => [:A]]
        run(sys; with_obs = false) = solve(
            PottsProblem(BindParity(; name = :bp, comp_sys = sys, with_obs), op, (0, 2)),
            SequentialCPM(),
        )
        MTKB.@parameters k = 0.3
        MTKB.@parameters k2 = 2k
        MTKB.@parameters k3 = 3k2
        MTKB.@variables y(t) = 1.0 z(t) = 2k
        # a bound parameter equals the component written inline
        bound = run(MTKB.System([Potts.D(y) ~ -k2 * y], t, [y], [k, k2]; name = :comp))
        inline = run(MTKB.System([Potts.D(y) ~ -2k * y], t, [y], [k]; name = :comp))
        @test bound.u[end].cell.comp₊y == inline.u[end].cell.comp₊y ≈ [(1 - 0.6)^2]
        # a chain (`k3 = 3k2`), and the model reading `comp.k2`
        chain = run(MTKB.System([Potts.D(y) ~ -k3 * y / 6], t, [y], [k, k2, k3]; name = :comp); with_obs = true)
        @test chain.u[end].cell.comp₊y ≈ [(1 - 0.3)^2] && Potts.observe(chain, :ok2)[end][1] ≈ 0.6
        # an initial value of parameters (`z(t) = 2k`) and the same as `initial_conditions`
        s = run(MTKB.System([Potts.D(z) ~ -k * z], t, [z], [k]; name = :comp))
        @test s.u[1].cell.comp₊z ≈ [0.6] && s.u[end].cell.comp₊z ≈ [0.6 * 0.7^2]
        MTKB.@variables w(t)
        s = run(MTKB.System([Potts.D(w) ~ -k * w], t, [w], [k]; name = :comp, initial_conditions = [w => 2k]))
        @test s.u[1].cell.comp₊w ≈ [0.6]
        # negative control: an initial value that reads an unknown is still refused, naming it
        MTKB.@variables o(t)
        e = emsg(() -> run(MTKB.System([o ~ 2y, Potts.D(y) ~ -k * o], t; name = :comp, initial_conditions = [y => 2o])))
        @test occursin("component `comp`", e) && occursin("more than the component's parameters", e)
    end
end

@testitem "F2-15: Foam has no computed parameter" setup = [F2MetadataSetup] tags = [:potts, :mtk_native] begin
    @testset "F2-15: Foam has no computed parameter" begin
        c = Potts.ModelingToolkitBase.mtkcompile(ShearedFoam(; name = :f, lattice = (32, 32)))
        @test isempty(Potts._computed_params(Potts._p(getfield(c, :sys), :parameters)))
    end
end

@testitem "F2-15 review: routes and messages of computed parameters" setup = [F2MetadataSetup] tags = [:potts, :mtk_native] begin
    @testset "F2-15 review: routes and messages of computed parameters" begin
        σ = zeros(Int32, 12, 12); σ[2:5, 2:5] .= 1
        prob = PottsProblem(F2BoundChain(; name = :b), [ownership => σ, kind => [1]], (0, 2))
        e = emsg(() -> Potts.SciMLBase.remake(prob; p = [:α => 1.0]))
        @test occursin("parameter `γ` = 2.05 is outside its declared bounds (0, 1): `γ` is computed from `α`", e) &&
            occursin("set `α`", e)
        ig = init(prob, SequentialCPM())
        e = emsg(() -> (ig[:β] = 1.0))
        @test occursin("`β` is computed from `α`", e) && !occursin("Invalid symbol", e)
        @test ig[:β] == 0.6
        t = Potts.t
        MTKB.@parameters k = 0.3
        MTKB.@parameters k2 = 2k
        MTKB.@variables y(t) = 1.0
        pb = compmodel(MTKB.System([Potts.D(y) ~ -k2 * y], t, [y], [k, k2]; name = :comp))
        e = emsg(() -> Potts.SciMLBase.remake(pb; p = [:comp₊k2 => 1.0]))
        @test occursin("`comp₊k2` is computed from `comp₊k`", e) && occursin("give `k2` a number in `comp`'s parameters", e)
        MTKB.@parameters k2n = 1.0
        pr = compmodel(MTKB.System([Potts.D(y) ~ -k2n * y], t, [y], [k, k2n]; name = :comp))
        @test getp(Potts.SciMLBase.remake(pr; p = [:comp₊k2n => 0.5]), :comp₊k2n)(Potts.SciMLBase.remake(pr; p = [:comp₊k2n => 0.5])) == 0.5
        kk = MTKB.ShiftIndex(t, 0)
        MTKB.@parameters s::Bool = false
        MTKB.@parameters s2::Bool = !s
        MTKB.@variables X(t)::Bool = false
        pd = compmodel(MTKB.System([X(kk) ~ s2], t; name = :comp))
        e = emsg(() -> Potts.SciMLBase.remake(pd; p = [:comp₊s2 => true]))
        @test occursin("`comp₊s2 = !comp₊s`", e) && !occursin("_nonzero", e)
    end
end
