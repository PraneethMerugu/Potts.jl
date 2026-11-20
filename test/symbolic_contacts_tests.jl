# Split from test/symbolic_tests.jl

@testitem "connectivity(rule = ArcOrPair()) keeps TST's zero-arc pass" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "connectivity(rule = ArcOrPair()) keeps TST's zero-arc pass" begin
        @potts_model ConnectivityProbe begin
            @structural_parameters local_only = false
            @kinds medium A
            @lattice Lattice((12, 12); neighborhood = Moore(1))
            @energy cells => (volume - 1)^2
            if local_only
                @constraint connectivity(A)
            else
                @constraint connectivity(A; rule = ArcOrPair())
            end
            @sweep Metropolis(; temperature = 1.0)
        end

        allows(local_only, σ, x, y) = (
            p = PottsProblem(
                ConnectivityProbe(; name = :r, local_only),
                [ownership => σ, kind => fill(:A, maximum(σ))], (0, 1)
            );
            prop = CorePotts.Proposal(CorePotts.linear_index(p.lattice, x), CorePotts.linear_index(p.lattice, y), x, 1, σ[x...], σ[y...]);
            p.f.constraint(p.u0, p.p, prop, Potts._host_ctx(p))
        )
        σ = zeros(Int32, 12, 12); σ[6, 6] = 1
        @test allows(false, σ, (6, 6), (7, 6))            # the last site: 0 arcs pass
        @test !allows(true, σ, (6, 6), (7, 6))            # negative control: the local rule rejects it
        σ[2:3, 2:3] .= 1
        @test allows(false, σ, (6, 6), (7, 6))            # an isolated fragment: 0 arcs pass
        @test !allows(true, σ, (6, 6), (7, 6))
        σ = zeros(Int32, 12, 12); σ[3:9, 6] .= 1
        @test !allows(false, σ, (6, 6), (6, 7))           # a bridge, one cell on the ring: 2 arcs
        σ[6, 5] = 2
        @test !allows(false, σ, (6, 6), (6, 5))           # 2 arcs, two cells but medium on the ring: refused
        σ = fill(Int32(2), 12, 12); σ[3:9, 6] .= 1
        @test allows(false, σ, (6, 6), (6, 5))            # 2 arcs, exactly two cells and no medium: the pair
        σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1
        @test allows(false, σ, (6, 4), (7, 4))            # an ordinary boundary copy: 1 arc
    end
end

# D-075: `Chemotaxis`'s `when` defaults to `new != 0`; `when = true` is every copy;
# `kinds` requires `kind[new] ∈ kinds`, so retractions stay 0 with `kinds` given


@testitem "Chemotaxis `when`" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "Chemotaxis `when`" begin
        @potts_model _ChemoWhen begin
            @structural_parameters mode = :every
            @kinds medium A
            @variables c(site) = 0.0
            @lattice Lattice((12, 12))
            @energy cells => (volume - 16)^2
            if mode === :every
                @drive Chemotaxis(c; strength = 1.0, when = true)
            elseif mode === :default
                @drive Chemotaxis(c; strength = 1.0)
            elseif mode === :ext
                @drive Chemotaxis(c; strength = 1.0, when = old == 0)
            else
                @drive Chemotaxis(c; strength = 1.0, kinds = (A,), when = true)
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        function chemo(mode)
            σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
            p = PottsProblem(_ChemoWhen(; name = :c, mode), [ownership => σ, kind => [:A], :c => [Float64(i) for i in 1:12, j in 1:12]], (0, 1))
            d(x, y) = (
                prop = CorePotts.Proposal(CorePotts.linear_index(p.lattice, x), CorePotts.linear_index(p.lattice, y), x, 1, σ[x...], σ[y...]);
                p.f.delta_H(p.u0, p.p, prop, Potts._host_ctx(p)) - energy_change(p, p.u0, prop)
            )
            return d((7, 5), (8, 5)), d((8, 5), (7, 5))     # (retraction, extension)
        end
        @test all(isapprox.(chemo(:every), (1.0, -1.0)))      # every copy
        @test all(isapprox.(chemo(:default), (0.0, -1.0)))    # default new != 0
        @test all(isapprox.(chemo(:ext), (0.0, -1.0)))        # extensions only
        @test all(isapprox.(chemo(:kinds), (0.0, -1.0)))      # S2
    end
end

# A relation may not take a run-context name CorePotts reserves (`lattice`, `mobility`,
# `spacing`): mtkcompile refuses it with CorePotts' error, before codegen; the declarable
# roles `contact` and `proposal` still build


@testitem "reserved relation names are refused at mtkcompile" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "reserved relation names are refused at mtkcompile" begin
        @potts_model ReservedRelProbe begin
            @structural_parameters rel = :spacing read = true
            @kinds medium cell
            @variables q(site) = 0.0
            @lattice Lattice((12, 12); spacing = (1.0, 1.0))
            if rel === :spacing
                @relations spacing = Moore(2)
            elseif rel === :lattice
                @relations lattice = Moore(2)
            elseif rel === :mobility
                @relations mobility = Moore(2)
            elseif rel === :far
                @relations far = Moore(2)
            elseif rel === :contact
                @relations contact = Moore(2)
            else
                @relations proposal = Moore(1)
            end
            if read && rel === :spacing
                @energy cells => 0.1 * volume * sum(q[n] for n in spacing(40))
            elseif read && rel === :lattice
                @energy cells => 0.1 * volume * sum(q[n] for n in lattice(40))
            elseif read && rel === :mobility
                @energy cells => 0.1 * volume * sum(q[n] for n in mobility(40))
            elseif read && rel === :far
                @energy cells => 0.1 * volume * sum(q[n] for n in far(40))
            else
                @energy cells => (volume - 16)^2
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        function build(rel; read = true)
            sys = ReservedRelProbe(; name = :r, rel, read)
            σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1
            return PottsProblem(sys, [ownership => σ, kind => [:cell]], (0, 1))
        end
        for rel in (:spacing, :lattice, :mobility)
            @test_throws Potts.PottsCompileError build(rel)
        end
        @test build(:far) isa CorePotts.PottsProblem                               # control: any other name
        @test build(:contact; read = false) isa CorePotts.PottsProblem             # declarable roles build
        @test build(:proposal; read = false) isa CorePotts.PottsProblem
    end
end

# `a` and `b` are reserved for every declaration, and for a programmatic
# PottsSystem; the error suggests `a₀`/`b₀`


@testitem "`a` and `b` are reserved globally" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "`a` and `b` are reserved globally" begin
        expand(body) = Potts._potts_model(:X, body, @__MODULE__)
        for decl in (
                :(@kinds medium a), :(@kinds medium A b), :(@observed b ~ volume), :(@relations a = Moore(1)),
                :(@structural_parameters a = 1), :(@relationship b(cell, cell) capacity = 1)
            )
            body = decl.args[1] === Symbol("@kinds") ? quote
                    $decl
                end : quote
                    @kinds medium A; $decl
                end
            @test_throws ArgumentError expand(body)
        end
        @test expand(
            quote
                @kinds medium ka kb; @observed b₀ ~ volume
            end
        ) isa Expr     # control
        V = Potts.B.volume
        prog(; kinds = [:medium, :cell], variables = Any[]) = Potts.PottsSystem(;
            name = :prog, kinds,
            lattice = Potts.lattice_spec((12, 12)), variables, energies = [Potts.energy(Potts.cells(1) => (V - 16)^2)],
            sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
        )
        @test prog() isa Potts.PottsSystem                                               # control
        @test_throws ArgumentError prog(; variables = Any[Potts.variable(only(Potts.Symbolics.@variables b(Potts.t)), :cell; default = 0.0)])
        @test_throws ArgumentError prog(; kinds = [:medium, :a])
    end
end


@testitem "contact terms read site values: name" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    SITE_CONTACT_CASES = (
        ("square", () -> SiteContacts(; name = :sq), (24, 24), Moore(1)),
        ("hex", () -> SiteContacts(; name = :hx, geometry = Hexagonal(), near = Hex(1), far = Hex(2)), (24, 24), Hex(1)),
        ("3D", () -> SiteContacts(; name = :cube, dims = (11, 11, 11)), (11, 11, 11), Moore(1)),
    )

    function swapped_sites_delta(sys)
        swap(ex) = ex isa Expr ?
            (
                ex.head === :ref && ex.args[1] == :(st.site.cue) && ex.args[2] in (:target, :sn) ?
                Expr(:ref, ex.args[1], ex.args[2] === :target ? :sn : :target) : Expr(ex.head, map(swap, ex.args)...)
            ) : ex
        has_cue_ref(ex, idx) = _has_ast(ex, n -> n isa Expr && n.head === :ref && n.args[1] == :(st.site.cue) && n.args[2] === idx)
        code = Potts.generated_code(sys).delta_H
        @assert has_cue_ref(code, :sn) && has_cue_ref(code, :target)
        return Potts._rgf(swap(code))
    end

    @testset "contact terms read site values: $name" for (name, mk, dims, rel) in SITE_CONTACT_CASES
        sys = mk()
        prob = site_contact_problem(sys, dims)
        @test site_selfcheck(prob, rel) < 1.0e-9
        # negative control: exchanging x and x′ in the lowering breaks ΔH
        f = swapped_sites_delta(sys)
        @test site_selfcheck(prob, rel; dH = (u, prop) -> f(u, prob.p, prop, ctx_of(prob))) > 1.0e-3
        # site reads at s′ stay inside the contact radius: no extra reach, no extra claims
        c = mtkcompile(sys)
        @test getfield(c, :footprint).read == CorePotts.radius(prob.relations.wide) == 2
        @test getfield(c, :footprint).source_read == -1 && getfield(c, :footprint).source_write == -1
    end
end


@testitem "x′ outside contact terms is rejected" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "x′ outside contact terms is rejected" begin
        bad(E) = Potts.PottsSystem(;
            name = :bad, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
            variables = [c], energies = [Potts.energy(E)], sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
        )
        c = Potts.variable(only(Potts.Symbolics.@variables c(Potts.t)), :site)
        @test_throws Potts.PottsCompileError mtkcompile(bad(Potts.sites => Potts._primed(c)))
        @test mtkcompile(bad(Potts.contacts => c * Potts._primed(c))) isa Potts.CompiledPottsSystem
        @test_throws ArgumentError Potts._primed(Potts.variable(only(Potts.Symbolics.@variables m(Potts.t)), :cell))
        @test_throws ArgumentError Potts._potts_model(
            :X,
            quote
                @kinds medium A; @variables begin
                    x(site) = 0.0; x′(site) = 0.0
                end
            end, @__MODULE__
        )
    end
end


@testitem "contact terms see on-copy writes and clears" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "contact terms see on-copy writes and clears" begin
        @potts_model SourceWriteContacts begin
            @kinds medium A
            @variables mark(site) = 0.0
            @lattice Lattice((8, 8))
            @energy contacts => mark * mark′
            @on_copy mark[source] ~ 1.0
            @sweep Metropolis(; temperature = 1.0)
        end

        σ, kinds, cue = site_contact_state((20, 20); side = 4)
        mk(; kw...) = PottsProblem(
            SiteContactsOnCopy(; name = :oc, kw...),
            [ownership => σ, kind => fill(:A, length(kinds)), :mark => cue, :tag => 2 .* cue], (0, 4)
        )
        prob = mk()
        @test site_selfcheck(prob, Moore(1)) < 1.0e-9
        # negative controls: ΔH of the model without the write (or the clear) misses the change
        # the committed copy makes
        nowrite, noclear = mk(; write = false), mk(; clear = false)
        @test site_selfcheck(prob, Moore(1); dH = (u, prop) -> energy_change(nowrite, u, prop)) > 1.0e-3
        @test site_selfcheck(prob, Moore(1); dH = (u, prop) -> energy_change(noclear, u, prop)) > 1.0e-3
        @test site_selfcheck(nowrite, Moore(1)) < 1.0e-9 && site_selfcheck(noclear, Moore(1)) < 1.0e-9
        # a write at the source changes pairs away from the target: rejected
        @test_throws Potts.PottsCompileError mtkcompile(SourceWriteContacts(; name = :sw))
    end
end


@testitem "checkerboard equals sequential; Float32 never touches Float64" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "checkerboard equals sequential; Float32 never touches Float64" begin
        prob = site_contact_problem(SiteContacts(; name = :sq), (24, 24); tspan = (0, 60))
        H(alg, seeds) = [total_energy(prob, solve(remake(prob; seed), alg; save_start = false).u[end]) for seed in seeds]
        n_sc = max(12, required_n(sqrt(2) * 150.0, 300.0; alpha = 1.0e-3, power = 0.9))
        xs, ys = H(SequentialCPM(), 1:n_sc), H(CheckerboardCPM(), 101:(100 + n_sc))
        margin = 0.1 * abs(Statistics.mean(xs))
        @test stat_accept(xs, ys; margin, alpha = 1.0e-3).pass
        @test !stat_accept(xs, ys .+ 0.25 * abs(Statistics.mean(xs)); margin, alpha = 1.0e-3).pass
        @test Statistics.mean(xs) < total_energy(prob, prob.u0) - 100           # the runs relax: the statistic is not trivial
        p32 = site_contact_problem(SiteContacts(; name = :sq), (24, 24); T = Float32)
        @test eltype(p32.u0.site.cue) === Float32
        σ, kinds = p32.u0.ownership, p32.u0.cell.kind
        prop = CorePotts.Proposal(5 + 24 * 3, 6 + 24 * 3, (5, 4), 1, σ[5, 4], σ[6, 4])
        io = IOBuffer()
        code_llvm(io, p32.f.delta_H, typeof.((p32.u0, p32.p, prop, ctx_of(p32))); debuginfo = :none)
        @test !occursin("double", String(take!(io)))
        @test p32.f.delta_H(p32.u0, p32.p, prop, ctx_of(p32)) isa Float32
    end
end


@testitem "population folds in contact terms keep their own site" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "population folds in contact terms keep their own site" begin
        @potts_model SiteContactsFold begin
            @kinds medium A B
            @variables cue(site) = 0.0
            @lattice Lattice((24, 24); neighborhood = Moore(1))
            @energy begin
                cells(A, B) => (volume - 16)^2
                contacts => cue * cue′ * sum(cue * (kind == A) for s in sites) / 100
            end
            @sweep Metropolis(; temperature = 6.0)
        end

        prob = site_contact_problem(SiteContactsFold(; name = :f), (24, 24))
        u, lat = prob.u0, prob.lattice
        m = sum(u.site.cue[i] for i in eachindex(u.ownership) if u.ownership[i] > 0 && u.cell.kind[u.ownership[i]] == 1) / 100
        H = 0.0
        for i in eachindex(u.ownership), o in prob.contact.offsets
            ins, y = CorePotts.shift(lat, CorePotts.coordinates(lat, i), o)
            j = CorePotts.linear_index(lat, y)
            ins && u.ownership[i] != u.ownership[j] && (H += u.site.cue[i] * u.site.cue[j] * m / 2)
        end
        E0 = sum((u.cell.volume[c] - 16)^2 for c in eachindex(u.cell.volume))
        @test total_energy(prob, u) ≈ H + E0 rtol = 1.0e-12
        @test site_selfcheck(prob, Moore(1)) < 1.0e-9
    end
end


@testitem "x′ in extensions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "x′ in extensions" begin
        @potts_model SiteContactsExt1 begin
            @extend cue, v = base = SiteContactsBase()
            @energy contacts => 2 * cue * (1 + cue′)^2 + v[2] * v′[1]
        end

        @potts_model SiteContactsExt2 begin
            @extend cue, cue′, v′, A = base = SiteContactsBase()
            @energy contacts => 2 * cue * (1 + cue′)^2 * (kind == A) + v′[1]
        end

        for sys in (SiteContactsExt1(; name = :e1), SiteContactsExt2(; name = :e2))
            σ, kinds, cue = site_contact_state((24, 24))
            prob = PottsProblem(sys, [ownership => σ, kind => kinds, :cue => cue, :v_1 => 1 .- cue, :v_2 => cue .^ 2], (0, 4))
            @test length(Potts._p(sys, :energies)) == 3             # the base's two terms and the extension's
            @test site_selfcheck(prob, Moore(1)) < 1.0e-9
        end
        @test Potts.lookup(SiteContactsBase(; name = :b), :v′) isa Potts.QuantityVector
        @test_throws ArgumentError Potts.lookup(SiteContactsBase(; name = :b), :J′)       # not a site variable
    end
end


@testitem "two site terms reading an on-copy write" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "two site terms reading an on-copy write" begin
        @potts_model TwoSiteTermsOnCopy begin
            @kinds medium A
            @variables mark(site) = 0.0
            @lattice Lattice((20, 20); neighborhood = Moore(1))
            @energy begin
                cells(A) => (volume - 16)^2
                sites => 0.7 * mark * (kind == A)
                sites => 0.2 * mark^2
            end
            @on_copy mark[target] ~ 0.5 * mark[source] + 1.0
            @sweep Metropolis(; temperature = 6.0)
        end

        σ, kinds, cue = site_contact_state((20, 20))
        prob = PottsProblem(TwoSiteTermsOnCopy(; name = :t), [ownership => σ, kind => fill(:A, length(kinds)), :mark => cue], (0, 4))
        @test site_selfcheck(prob, Moore(1)) < 1.0e-9
        # names a user cannot write stay out of the error text
        @test_throws Potts.PottsCompileError mtkcompile(
            Potts.PottsSystem(;
                name = :bad,
                kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.contacts => Potts.B.target)],
                sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
            )
        )
    end
end

# an extension cannot declare `x′` beside an inherited site variable `x` (nor the reverse)


@testitem "`x′` stays reserved through @extend" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "`x′` stays reserved through @extend" begin
        @potts_model PrimeClashParam begin
            @extend cue, A = b = SiteContactsBase()
            @parameters cue′ = 2.0
        end
        @potts_model PrimeClashVar begin
            @extend cue, A = b = SiteContactsBase()
            @variables cue′(cell) = 0.0
        end
        @potts_model PrimeClashOk begin
            @extend cue, A = b = SiteContactsBase()
            @parameters cue2 = 2.0
        end
        msg = r"`cue′` is declared, but `cue′` already means the contact-pair value of the site variable `cue`"
        @test_throws msg PrimeClashParam(; name = :pc)
        @test_throws msg PrimeClashVar(; name = :pc)
        @test PrimeClashOk(; name = :pc) isa Potts.PottsSystem   # control
    end
end


@testitem "primes of non-site quantities" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "primes of non-site quantities" begin
        @potts_model PrimeBase begin
            @structural_parameters n = 2
            @kinds medium A
            @parameters begin
                J[kind, kind] = [0 4; 4 2]
                λ = 1.0
            end
            @variables begin
                m(cell) = 1.0
                c(site) = 0.0
            end
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model PrimeProbeLocal begin
            @structural_parameters case = 1 n = 2
            @kinds medium A
            @parameters begin
                J[kind, kind] = [0 4; 4 2]
                λ = 1.0
            end
            @variables begin
                m(cell) = 1.0
                c(site) = 0.0
            end
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            if case == 1
                @energy cells(A) => let λ′ = 2λ
                    λ′ * volume
                end
            elseif case == 2
                @energy cells(A) => sum(volume * k for n′ in 1:n for k in 1:1)
            elseif case == 3
                @energy cells(A) => sum(volume * m′ for m′ in 1:2)
            elseif case == 4
                @energy cells(A) => ((λ′) -> λ′ * volume)(λ)
            elseif case == 5
                @energy cells(A) => (; m′ = 2.0).m′ * volume
            elseif case == 6
                @energy contacts => J[kind, neighbor_kind] + m′
            elseif case == 7
                @energy contacts => J[kind, neighbor_kind] + λ′
            elseif case == 8
                @observed q ~ 1.0
                @energy cells(A) => q′
            elseif case == 9
                @energy cells(A) => zz′
            end
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model PrimeExtNamedBad begin
            @extend m, c = b = PrimeBase()
            @energy contacts => m′
        end
        @potts_model PrimeExtAnonBad begin
            @extend PrimeBase()
            @energy contacts => m′
        end
        @potts_model PrimeExtSiteOk begin
            @extend c, J = b = PrimeBase()
            @energy contacts => J[kind, neighbor_kind] + c′
        end
        @potts_model PrimeExtParamBad begin
            @parameters q = 1.0
            @extend b = PrimeBase(; λ = q′)
        end

        rejects(f, n, what) = try
            f()
            false
        catch e
            e isa ArgumentError
        end
        # locals named `x′` (x declared) are ordinary Julia and build
        for case in 1:5
            @test mtkcompile(PrimeProbeLocal(; name = :pp, case)) isa CompiledPottsSystem
        end
        # declared non-site quantities, with the right description
        @test rejects(() -> PrimeProbeLocal(; name = :pp, case = 6), "m′", "`m` is a cell variable; in a contact term, `m[neighbor_owner]`")
        @test rejects(() -> PrimeProbeLocal(; name = :pp, case = 7), "λ′", "`λ` is a parameter")
        @test rejects(() -> PrimeProbeLocal(; name = :pp, case = 8), "q′", "`q` is an observed quantity")
        # inherited through @extend, named or not
        @test rejects(() -> PrimeExtNamedBad(; name = :pp), "m′", "`m` is a cell variable; in a contact term")
        @test rejects(() -> PrimeExtAnonBad(; name = :pp), "m′", "`m` is a cell variable")
        # controls: a site variable's prime and an unrelated unbound name keep their behaviour
        @test PrimeExtSiteOk(; name = :pp) isa Potts.PottsSystem
        @test_throws UndefVarError PrimeProbeLocal(; name = :pp, case = 9)
        # an `@extend` base's arguments are the extension's own code: their primes are translated
        @test rejects(() -> PrimeExtParamBad(; name = :pp), "q′", "`q` is a parameter")
    end
end

# Component bindings (an MTK value given as an expression): an expression of the component's
# parameters is evaluated at build (test/mtk_native.jl); any other binding is rejected by
# name only where Potts reads it; a binding of a continuous observed variable (its equation
# gives its value) stays ignored


@testitem "a gather in an on-copy update's index: numbered, in the footprint, same as named" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "a gather in an on-copy update's index: numbered, in the footprint, same as named" begin
        @potts_model OnCopyIndexInline begin
            @kinds medium A
            @variables y(cell) = 0.0
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @on_copy y[ifelse(count(owner[n] == 1 for n in Moore(3)(target)) > 3, new, old)] ~ y[new] + 1.0
            @sweep Metropolis(; temperature = 2.0)
        end

        @potts_model OnCopyIndexNamed begin
            @kinds medium A
            @variables y(cell) = 0.0
            @lattice Lattice((12, 12))
            @relations far = Moore(3)
            @energy cells => (volume - 9.0)^2
            @on_copy y[ifelse(count(owner[n] == 1 for n in far(target)) > 3, new, old)] ~ y[new] + 1.0
            @sweep Metropolis(; temperature = 2.0)
        end

        @potts_model OnCopyIndexPlain begin
            @kinds medium A
            @variables y(cell) = 0.0
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @on_copy y[new] ~ y[new] + 1.0
            @sweep Metropolis(; temperature = 2.0)
        end

        σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1; σ[7:9, 7:9] .= 2
        op = Any[ownership => σ, kind => [:A, :A]]
        run(mk) = (
            prob = PottsProblem(mk(; name = :g), op, (0, 6); seed = 7, capacity = 16);
            (prob, solve(prob, SequentialCPM(); saveat = 1))
        )
        (pi, si), (pn, sn) = run(OnCopyIndexInline), run(OnCopyIndexNamed)
        @test [u.ownership for u in si.u] == [u.ownership for u in sn.u]
        @test [u.cell.y for u in si.u] == [u.cell.y for u in sn.u]
        @test sum(si.u[end].cell.y) > 0                       # the update ran
        # the index's relation sets the read reach (Moore(3) → 3); the plain index stays at 1
        @test getfield(mtkcompile(OnCopyIndexInline(; name = :g)), :footprint).read == 3
        @test getfield(mtkcompile(OnCopyIndexNamed(; name = :g)), :footprint).read == 3
        @test getfield(mtkcompile(OnCopyIndexPlain(; name = :g)), :footprint).read == 1
    end
end
