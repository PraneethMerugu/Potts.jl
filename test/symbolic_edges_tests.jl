# Split from test/symbolic_tests.jl

@testitem "relationships: springs and link rules" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "relationships: springs and link rules" begin
        @potts_model Tissue begin
            @kinds medium leader follower
            @parameters begin
                T = 10.0
                J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
            end
            @variables age(edge) = 0.0
            @relationship bond(cell, cell) capacity = 8
            @lattice Lattice((30, 30); neighborhood = Moore(1))
            @energy contacts => J[kind, neighbor_kind]
            @link bond when = new_contact(a, b) && (kind[a] == leader), every = 100
            @unlink bond when = distance > 100.0
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[40:45, 12:17] .= 2
        prob = PottsProblem(Spring(; name = :spring), [ownership => σ, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000))
        @test CorePotts.linked(CorePotts.link_store(prob.u0.cell, :bond), 1, 2) && prob.u0.cell.link_rest[1, 1] == 12.0
        # self-check with edge energies (partner centroids move with the copy)
        worst = 0.0
        for (u, prop) in proposal_states(remake(prob; tspan = (0, 5)); mcs = (0, 5), n = 300)
            a = deepcopy(u); a.ownership[prop.target] = prop.new
            prob.f.commit!(a, prob.p, prop, ctx_of(prob))
            worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
        end
        @test worst < 1.0e-9
        ds = map(1:4) do seed
            u = solve(remake(prob; seed), CheckerboardCPM()).u[end]
            CorePotts.centroid_distance(Float64, u.cell, prob.lattice, 1, 2)
        end
        @test abs(sum(ds) / 4 - 12.0) < 2.5                 # relaxes from 25 to the rest length

        σb = zeros(Int32, 30, 30)
        for (c, (i, j)) in enumerate(Iterators.product(1:5:26, 1:5:26))
            σb[i:(i + 4), j:(j + 4)] .= c
        end
        n = maximum(σb)
        kinds = [isodd(c) ? :leader : :follower for c in 1:n]
        tp = PottsProblem(Tissue(; name = :tissue), [ownership => σb, kind => kinds], (0, 1))
        u = solve(tp, SequentialCPM()).u[end]            # the rule ran once, after MCS 0's sweep
        g = CorePotts.contact_graph(u.ownership, tp.lattice, tp.contact, n)
        nlinks = 0
        bonds = CorePotts.link_store(u.cell, :bond)
        for a in 1:n, b in (a + 1):n
            touching = b in CorePotts.contact_neighbors(g, a)
            led = isodd(a) || isodd(b)
            @test CorePotts.linked(bonds, a, b) == (touching && led)
            nlinks += CorePotts.linked(bonds, a, b)
        end
        @test nlinks > 20
    end
end


@testitem "several relationships: stores, brute-force ΔH, oracle" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "several relationships: stores, brute-force ΔH, oracle" begin
        @potts_model HexChain begin
            @kinds medium blob
            @variables begin
                rest(bond) = 5.0
                len(tether) = 8.0
            end
            @relationship bond(cell, cell) capacity = 2
            @relationship tether(cell, cell) capacity = 2
            @lattice Lattice((36, 16); geometry = Hexagonal(), neighborhood = Hex(1))
            @energy begin
                cells => (volume - 30)^2
                contacts => 6.0
                edges(bond) => 0.7 * (distance - rest)^2
                edges(tether) => 1.3 * (distance - len)^2
            end
            @sweep Metropolis(; temperature = 8.0)
        end

        @potts_model ChainNoLinks begin
            @kinds medium blob
            @parameters J[kind, kind] = [0 16; 16 2]
            @lattice Lattice((36, 16); boundary = Closed(), neighborhood = Moore(1))
            @energy begin
                cells => (volume - 36)^2
                contacts => J[kind, neighbor_kind]
            end
            @sweep Metropolis(; temperature = 8.0)
        end

        function edge_selfcheck(prob, rel; n = 600)
            sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = rel); saveat = [0, 2, 4])
            lat = prob.lattice
            R = CorePotts.relation(rel, lat)
            rng = Xoshiro(7)
            worst = 0.0; linked_pairs = 0
            for u in sol.u, _ in 1:n
                t = rand(rng, 1:length(u.ownership)); x = CorePotts.coordinates(lat, t)
                ins, y = CorePotts.shift(lat, x, R.offsets[rand(rng, 1:length(R))])
                ins || continue
                s = CorePotts.linear_index(lat, y)
                u.ownership[t] == u.ownership[s] && continue
                prop = CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s])
                a = deepcopy(u); a.ownership[t] = prop.new
                prob.f.commit!(a, prob.p, prop, ctx_of(prob))
                worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
                linked_pairs += any(r -> CorePotts.linked(CorePotts.link_store(u.cell, r), prop.old, prop.new), (:bond, :tether))
            end
            return worst, linked_pairs
        end

        prob = PottsProblem(Chain(; name = :chain), [ownership => chain_state(), CHAIN_LINKS...], (0, 20))
        u0 = prob.u0
        @test keys(u0.cell) ⊇ (:links__bond, :links__tether, :link_rest, :link_len)
        B, Tt = CorePotts.link_store(u0.cell, :bond), CorePotts.link_store(u0.cell, :tether)
        @test CorePotts.linked(B, 1, 2) && CorePotts.linked(B, 3, 4) && !CorePotts.linked(B, 2, 3)
        @test CorePotts.linked(Tt, 2, 3) && CorePotts.linked(Tt, 1, 4) && !CorePotts.linked(Tt, 1, 2)
        @test u0.cell.link_rest[CorePotts.link_slot(B, 2, 1), 2] == 6.0      # each store its own payload
        @test u0.cell.link_len[CorePotts.link_slot(Tt, 2, 3), 2] == 9.0
        # brute force: copies across bonded and tethered pairs, and cells with partners in both
        for (p, rel) in (
                (prob, Moore(1)),
                (PottsProblem(HexChain(; name = :hex), [ownership => chain_state(), CHAIN_LINKS...], (0, 20)), Hex(1)),
            )
            worst, npairs = edge_selfcheck(p, rel)
            @test worst < 1.0e-9
            @test npairs > 20
        end
        # independent oracle: total energy minus the link-free model is Σ over both stores
        bare = PottsProblem(ChainNoLinks(; name = :bare), [ownership => chain_state()], (0, 20))
        u = solve(prob, SequentialCPM()).u[end]
        link_energy(store, k, ℓ) = sum(
            k * (CorePotts.centroid_distance(Float64, u.cell, prob.lattice, a, b) - ℓ)^2
                for (a, b) in store
        )
        oracle = link_energy(((1, 2), (3, 4)), 0.7, 6.0) + link_energy(((2, 3), (1, 4)), 1.3, 9.0)
        diff = total_energy(prob, u) - total_energy(bare, u)
        @test diff ≈ oracle rtol = 1.0e-10
        @test !isapprox(diff, link_energy(((1, 2), (3, 4)), 0.7, 6.0); rtol = 1.0e-3)    # negative control: one store
    end
end


@testitem "several relationships: a copy's ΔH reads partners from every relationship" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "several relationships: a copy's ΔH reads partners from every relationship" begin
        prob = PottsProblem(Chain(; name = :chain), [ownership => chain_state(), CHAIN_LINKS...], (0, 20))
        u = deepcopy(prob.u0); ctx = ctx_of(prob); lat = prob.lattice
        site(c) = CorePotts.linear_index(lat, (6c - 3, 5))                # a medium site below cell c
        target(c) = CorePotts.linear_index(lat, (6c - 3, 6))              # cell c's bottom-left site
        # X: medium invades cell 2 (moves 2's centroid); Y: medium invades cell 3
        X = CorePotts.Proposal(target(2), site(2), CorePotts.coordinates(lat, target(2)), 1, Int32(2), Int32(0))
        Y = CorePotts.Proposal(target(3), site(3), CorePotts.coordinates(lat, target(3)), 1, Int32(3), Int32(0))
        # X's ΔH depends on cell 3, its tether partner: committing Y first changes it
        dX = energy_change(prob, u, X)
        v = deepcopy(u); v.ownership[Y.target] = Y.new; prob.f.commit!(v, prob.p, Y, ctx)
        @test abs(energy_change(prob, v, X) - dX) > 1.0e-3
    end
end


@testitem "several relationships: link rules fire per relationship" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "several relationships: link rules fire per relationship" begin
        @potts_model TwoRules begin
            @kinds medium leader follower
            @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
            @variables begin
                age(bond) = 1.0
                strength(tether) = 2.0
            end
            @relationship bond(cell, cell) capacity = 8
            @relationship tether(cell, cell) capacity = 8
            @lattice Lattice((30, 30); neighborhood = Moore(1))
            @energy contacts => J[kind, neighbor_kind]
            @link bond when = new_contact(a, b) && kind[a] == leader && kind[b] == leader
            @link tether when = new_contact(a, b) && kind[a] == follower && kind[b] == follower, every = 2
            @unlink tether when = strength > 1.5, every = 3
            @sweep Metropolis(; temperature = 10.0)
        end

        σb = zeros(Int32, 30, 30)
        for (c, (i, j)) in enumerate(Iterators.product(1:5:26, 1:5:26))
            σb[i:(i + 4), j:(j + 4)] .= c
        end
        n = maximum(σb)
        kinds = [isodd(c) ? :leader : :follower for c in 1:n]
        tp = PottsProblem(TwoRules(; name = :two), [ownership => σb, kind => kinds], (0, 1))
        u = solve(tp, SequentialCPM()).u[end]            # after MCS 0: every rule ran once
        g = CorePotts.contact_graph(u.ownership, tp.lattice, tp.contact, n)
        B, Tt = CorePotts.link_store(u.cell, :bond), CorePotts.link_store(u.cell, :tether)
        nb = nt = 0
        for a in 1:n, b in (a + 1):n
            touching = b in CorePotts.contact_neighbors(g, a)
            @test CorePotts.linked(B, a, b) == (touching && isodd(a) && isodd(b))
            @test !CorePotts.linked(Tt, a, b)             # linked, then unlinked (strength 2 > 1.5) at MCS 0
            nb += CorePotts.linked(B, a, b)
        end
        @test nb > 5 && all(==(1.0), u.cell.link_age[B.links .!= 0])
        # the tether rule on its own: at MCS 2 the link rule runs, the unlink rule does not (every 3)
        u2 = solve(remake(tp; tspan = (0, 3)), SequentialCPM()).u[end]
        T2 = CorePotts.link_store(u2.cell, :tether)
        g2 = CorePotts.contact_graph(u2.ownership, tp.lattice, tp.contact, n)
        for a in 1:n, b in (a + 1):n
            touching = b in CorePotts.contact_neighbors(g2, a)
            CorePotts.linked(T2, a, b) && (nt += 1; @test iseven(a) && iseven(b))
        end
        @test nt > 5 && all(==(2.0), u2.cell.link_strength[T2.links .!= 0])
        @test u2.cell.links__bond != u2.cell.links__tether
    end
end


@testitem "several relationships: @extend keeps a base's `x(edge)` bound to its relationship" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "several relationships: @extend keeps a base's `x(edge)` bound to its relationship" begin
        @potts_model SpringTether begin
            @extend base = Spring()
            @variables len(tether) = 18.0
            @relationship tether(cell, cell) capacity = 1
            @energy edges(tether) => 1.5 * (distance - len)^2
        end

        c = mtkcompile(SpringTether(; name = :st))
        @test [r.name for r in getfield(c, :relationships)] == [:tether, :bond]
        @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:bond]] == [:rest]
        @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:tether]] == [:len]
        σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2; σ[40:45, 12:17] .= 3
        prob = PottsProblem(c, [ownership => σ, kind => [:blob, :blob, :blob], :bond => [(1, 2)], :tether => [(2, 3)]], (0, 20))
        @test prob.u0.cell.link_rest[1, 1] == 12.0 && prob.u0.cell.link_len[1, 2] == 18.0
        @test selfcheck(prob) < 1.0e-9
        # the rule is per body: one body declaring two relationships still may not use `x(edge)`
        @test_throws "ambiguous" mtkcompile(AmbiguousEdge(; name = :a))
    end
end


@testitem "programmatic extend: a re-declared edge variable keeps the base's relationship" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "programmatic extend: a re-declared edge variable keeps the base's relationship" begin
        base = Spring(; name = :s)                       # `rest(edge)`: `bond`
        rest_sym = only(Potts.Symbolics.@variables rest(Potts.t))
        ext(scope; rels = [Potts.relationship(:tether; capacity = 1)]) = Potts.PottsSystem(;
            name = :x,
            kinds = Potts._p(base, :kinds), lattice = Potts.lattice(base), sweep = Potts._p(base, :sweep), relationships = rels,
            variables = Any[Potts.variable(rest_sym, scope; default = 9.0)]
        )
        σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2
        op = [ownership => σ, kind => [:blob, :blob], :bond => [(1, 2)]]
        for (scope, rels) in (
                (:edge, [Potts.relationship(:tether; capacity = 1)]), (:edge, Potts.RelationshipSpec[]),
                (:edge, [Potts.relationship(:tether), Potts.relationship(:glue)]), (:bond, Potts.RelationshipSpec[]),
            )
            c = mtkcompile(extend(ext(scope; rels), base))
            @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:bond]] == [:rest]
            @test all(r -> isempty(getfield(c, :edge_vars)[r]), filter(!=(:bond), collect(keys(getfield(c, :edge_vars)))))
            prob = PottsProblem(c, op, (0, 5))
            @test prob.u0.cell.link_rest[1, 1] == prob.u0.cell.link_rest[1, 2] == 9.0   # the extension's default
            @test total_energy(prob) == total_energy(PottsProblem(base, [op; :rest => 9.0], (0, 5)))
        end
        # a nested extension (of an extension) keeps it too
        c = mtkcompile(extend(ext(:edge; rels = Potts.RelationshipSpec[]), extend(ext(:edge), base; name = :mid)))
        @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:bond]] == [:rest] && isempty(getfield(c, :edge_vars)[:tether])
        # another relationship: rejected when built, naming the variable and both relationships
        @test_throws ArgumentError extend(ext(:tether), base)
        @test_throws r"`rest`.*`bond`.*`tether`" extend(ext(:tether), base)
        # control: without the base's variable, `rest(tether)` is the extension's own
        c = mtkcompile(ext(:tether))
        @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:tether]] == [:rest]
    end
end


@testitem "extend: a body's implicitly bound edge variable takes the base's relationship" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "extend: a body's implicitly bound edge variable takes the base's relationship" begin
        @potts_model EdgeBody begin
            @kinds medium blob
            @variables begin
                rest(edge) = 9.0
                len(tether) = 18.0
            end
            @relationship tether(cell, cell) capacity = 1
            @lattice Lattice((60, 30); neighborhood = Moore(1))
            @energy edges(tether) => 1.5 * (distance - len)^2
            @sweep Metropolis(; temperature = 10.0)
        end

        @potts_model EdgeBodyExtend begin                     # the `@extend` form of the same
            @extend base = Spring()
            @variables begin
                rest(edge) = 9.0
                len(tether) = 18.0
            end
            @relationship tether(cell, cell) capacity = 1
            @energy edges(tether) => 1.5 * (distance - len)^2
        end

        σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2; σ[40:45, 12:17] .= 3
        op = [ownership => σ, kind => [:blob, :blob, :blob], :bond => [(1, 2)], :tether => [(2, 3)]]
        # alone, the body's `rest(edge)` is its only relationship's (control)
        body = EdgeBody(; name = :x)
        @test sort([Potts.info(x).name for x in getfield(mtkcompile(body), :edge_vars)[:tether]]) == [:len, :rest]
        # the mark of an implicit binding is not code: settling it keeps the fingerprint
        settled = Potts.PottsSystem(;
            name = nameof(body), (f => Potts._p(body, f) for f in fieldnames(Potts.PottsPart))...,
            variables = map(Potts._settle_edge_scope, Potts.declared_variables(body))
        )
        @test any(x -> haskey(Potts.info(x).options, :implicit_relationship), Potts.declared_variables(body))
        @test !any(x -> haskey(Potts.info(x).options, :implicit_relationship), Potts.declared_variables(settled))
        bop = [ownership => σ, kind => [:blob, :blob, :blob], :tether => [(2, 3)]]
        @test PottsProblem(body, bop, (0, 5)).f.fingerprint == PottsProblem(settled, bop, (0, 5)).f.fingerprint
        sys = extend(EdgeBody(; name = :x), Spring(; name = :s))
        c = mtkcompile(sys)
        @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:bond]] == [:rest]
        @test [Potts.info(x).name for x in getfield(c, :edge_vars)[:tether]] == [:len]
        oracle = mtkcompile(EdgeBodyExtend(; name = :x))
        @test [Potts.info(x).name for x in getfield(oracle, :edge_vars)[:bond]] == [:rest]
        p, q = PottsProblem(c, op, (0, 5)), PottsProblem(oracle, op, (0, 5))
        @test p.u0.cell.link_rest[1, 1] == 9.0 && p.u0.cell.link_len[1, 2] == 18.0
        @test total_energy(p) == total_energy(q) == 3264 + 72 + 6
        # an explicit `rest(tether)` is still a move, and rejected
        @test_throws r"`rest`.*`bond`.*`tether`" extend(
            RestOnTether(; name = :x) |> s -> Potts.PottsSystem(;
                name = :x,
                kinds = Potts._p(s, :kinds), lattice = Potts.lattice(s), sweep = Potts._p(s, :sweep), relationships = Potts._p(s, :relationships),
                variables = Any[Potts.variable(only(Potts.Symbolics.@variables rest(Potts.t)), :tether; default = 5.0)]
            ),
            Spring(; name = :s)
        )
        # once merged, a binding is settled: a second base declaring `rest` elsewhere is an error
        @test_throws ArgumentError extend(extend(EdgeBody(; name = :x), Spring(; name = :s)), RestOnTether(; name = :t))
    end
end


@testitem "extend: edge variables of bases and changes of scope are checked" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "extend: edge variables of bases and changes of scope are checked" begin
        @potts_model TwoBasesOneEdgeName begin
            @extend a = Spring()
            @extend b = RestOnTether()
        end

        @potts_model RestAsCell begin                          # an inherited edge variable as a cell variable
            @extend base = Spring()
            @variables rest(cell) = 9.0
        end

        @potts_model VolumeGoalBase begin
            @kinds medium blob
            @variables goal(cell) = 36.0
            @lattice Lattice((60, 30); neighborhood = Moore(1))
            @energy cells(blob) => (volume - goal)^2
            @sweep Metropolis(; temperature = 10.0)
        end

        @potts_model GoalAsEdge begin                        # an inherited cell variable as an edge variable
            @extend base = VolumeGoalBase()
            @variables goal(edge) = 1.0
            @relationship bond(cell, cell) capacity = 1
        end

        @test_throws "bases `a` and `b` both declare edge variable `rest`, on `bond` and `tether`" TwoBasesOneEdgeName(; name = :m)
        @test_throws ArgumentError RestAsCell(; name = :m)
        @test_throws r"`rest` is an edge variable of `bond`.*a cell variable.*change its scope" RestAsCell(; name = :m)
        @test_throws r"`goal` is a cell variable.*an edge variable.*change its scope" GoalAsEdge(; name = :m)
    end
end


@testitem "several relationships: names are checked" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "several relationships: names are checked" begin
        @potts_model UnknownRelationship begin
            @kinds medium blob
            @variables rest(bnod) = 1.0
            @relationship bond(cell, cell) capacity = 1
            @lattice Lattice((8, 8); neighborhood = Moore(1))
            @energy edges(bond) => distance - rest
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model CrossRead begin
            @kinds medium blob
            @variables len(tether) = 1.0
            @relationship bond(cell, cell) capacity = 1
            @relationship tether(cell, cell) capacity = 1
            @lattice Lattice((8, 8); neighborhood = Moore(1))
            @energy edges(bond) => distance - len
            @link tether when = len > 0.0
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model CellRelationship begin
            @kinds medium blob
            @relationship cell(cell, cell) capacity = 1
            @lattice Lattice((8, 8); neighborhood = Moore(1))
            @energy contacts => 1.0
            @sweep Metropolis(; temperature = 1.0)
        end

        @test_throws "ambiguous" mtkcompile(AmbiguousEdge(; name = :a))
        @test_throws "neither a scope" mtkcompile(UnknownRelationship(; name = :u))
        @test_throws "an edge variable of relationship `tether`" mtkcompile(CrossRead(; name = :c))
        c = Chain(; name = :c)
        @test_throws "declared twice" mtkcompile(
            Potts.PottsSystem(;
                name = :dup, kinds = [:medium, :blob],
                lattice = Potts.lattice(c), relationships = [Potts.relationship(:bond), Potts.relationship(:bond)], sweep = Potts._p(c, :sweep)
            )
        )
        @test isequal(getfield(mtkcompile(Spring(; name = :s)), :edge_vars)[:bond], Potts.declared_variables(Spring(; name = :s)))   # `rest(edge)`: the only one
        @test_throws "is a variable scope" mtkcompile(CellRelationship(; name = :cr))
    end
end


@testitem "review regressions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "review regressions" begin
        @potts_model CellVarContacts begin
            @kinds medium A B
            @parameters begin
                λ = 1.0
                T = 8.0
                J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
            end
            @variables x(cell) = 1.0
            @lattice Lattice((24, 24); neighborhood = Moore(1))
            @relations near = Moore(1)
            @energy begin
                cells(A, B) => λ * (volume - 25)^2 + 0.3 * (surface - 20)^2
                contacts => J[kind, neighbor_kind] + x                      # bare cell variable: x[owner]
                contacts(near) => 0.5 * x[owner] * x[neighbor_owner]
            end
            @sweep Metropolis(; temperature = T)
        end

        σ, kinds = two_kind_blocks()
        n = length(kinds)
        xs = collect(1.0:n)
        prob = PottsProblem(
            CellVarContacts(; name = :cv), [
                ownership => σ, kind => kinds,
                first(filter(v -> Potts.info(v).name === :x, Potts.declared_variables(CellVarContacts(; name = :cv)))) => xs,
            ], (0, 3)
        )
        @test selfcheck(prob) < 1.0e-9           # cell variables mirrored; surface δ fused once
        ex = Potts.generated_code(CellVarContacts(; name = :cv))
        @test _count_ast(ex.delta_H, node -> node isa Expr && node.head === :(+=) && node.args[1] === :δs_old) == 1

        # quantities that change with the copy are rejected outside cell terms
        @test_throws ArgumentError mtkcompile(
            Potts.PottsSystem(;
                name = :bad, kinds = [:medium, :A],
                lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.contacts => Potts._index(Potts.B.volume, Potts.B.owner))],
                sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
            )
        )
        @test_throws ArgumentError mtkcompile(
            Potts.PottsSystem(;
                name = :bad, kinds = [:medium, :A],
                lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.sites => 0.1 * Potts._index(Potts.B.volume, Potts.B.owner))],
                sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
            )
        )
        @test_throws ArgumentError mtkcompile(
            Potts.PottsSystem(;
                name = :bad, kinds = [:medium, :A],
                lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.cells(0) => Potts.B.volume)],
                sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
            )
        )
    end
end
