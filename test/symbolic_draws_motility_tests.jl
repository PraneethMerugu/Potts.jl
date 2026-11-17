# Split from test/symbolic_tests.jl

@testitem "rand(): counter-based draws in updates and divisions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "rand(): counter-based draws in updates and divisions" begin
        @potts_model Noisy begin
            @kinds medium A
            @parameters T = 1.0
            @variables begin
                u(cell) = 0.0
                w(site) = 0.0
                tally(model) = 0.0
            end
            @lattice Lattice((16, 16))
            @after_mcs begin
                u ~ rand()
                w ~ rand()
                tally ~ Pre(tally) + rand()
            end
            @divide cells(A) when = (mcs == 2) && (rand() < 0.5), along = RandomPlane()
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 16, 16)
        for (c, (i, j)) in enumerate(Iterators.product(1:4:13, 1:4:13))
            σ[i:(i + 2), j:(j + 2)] .= c
        end
        p = PottsProblem(Noisy(; name = :n), [ownership => σ, kind => fill(1, 16)], (0, 4); seed = 3)
        s1 = solve(p, SequentialCPM(); saveat = 0:4)
        s2 = solve(p, CheckerboardCPM(); saveat = 0:4)
        # the same cell in both runs: live in both with the same generation (a reused id is a
        # different cell, and its draws differ by design, D-237)
        a, b = s1.u[end].cell, s2.u[end].cell
        live = findall(c -> a.volume[c] > 0 && b.volume[c] > 0 && a.generation[c] == b.generation[c], 1:16)
        @test !isempty(live)
        @test s1.u[end].cell.u[live] == s2.u[end].cell.u[live] && s1.u[end].site.w == s2.u[end].site.w &&
            s1.u[end].model.tally == s2.u[end].model.tally                                # schedule-independent
        @test s1.u[2].cell.u != s1.u[3].cell.u                                                # fresh every MCS
        w = s1.u[end].site.w
        @test length(unique(w)) == length(w) && abs(sum(w) / length(w) - 0.5) < 0.05          # per site, uniform
        @test 0 < s1.stats.lifecycle.divisions < 16                                           # about half divide
        @test s1.u[end].cell.u != solve(remake(p; seed = 4), SequentialCPM()).u[end].cell.u
        @potts_model RandomEnergy begin
            @kinds medium A
            @parameters T = 1.0
            @lattice Lattice((8, 8))
            @energy cells => (volume - 10 * rand())^2
            @sweep Metropolis(; temperature = T)
        end
        @test_throws ArgumentError mtkcompile(RandomEnergy(; name = :r))
    end
end


@testitem "rand(): cell draws are addressed by id and current generation (D-237)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "rand(): cell draws are addressed by id and current generation (D-237)" begin
        @potts_model DaughterDraws begin
            @kinds medium A B
            @parameters T = 1.0
            @variables begin
                X(cell) = 0.0
                u(cell) = 0.0
            end
            @lattice Lattice((16, 16))
            @energy cells(A) => (volume - 9.0)^2
            @energy cells(B) => 50.0 * volume
            @after_mcs u ~ rand()
            @divide cells(A) when = mcs == 8, along = RandomPlane(), X => rand()
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 16, 16)
        σ[1, 1] = 1
        σ[16, 16] = 2
        for (k, (i, j)) in enumerate(((3, 3), (3, 10), (10, 3), (10, 10)))
            σ[i:(i + 2), j:(j + 2)] .= k + 2
        end
        prob = PottsProblem(
            DaughterDraws(; name = :dd), [ownership => σ, kind => [:B, :B, :A, :A, :A, :A]], (0, 10);
            seed = 5, capacity = 12
        )
        key = Potts.CorePotts.RNGKey(prob.seed, prob.replica, prob.repeat)
        U(e, n, m) = Potts.CorePotts.uniform(Float64, Potts.CorePotts.draw(key, m, e, Potts.CorePotts.stream_id("Potts.draw.$n"))[1])
        E(c, g) = Potts.CorePotts.cell_entity(c, g)
        # host lifecycle planner (SequentialCPM), then the device planner on the CPU backend
        for (label, alg, device) in (("host", SequentialCPM(), false), ("device planner", CheckerboardCPM(), true))
            Potts.CorePotts._FORCE_DEVICE_LIFECYCLE[] = device
            try
                st = solve(prob, alg; save_start = false).u[end].cell
                gen, X, u = Array(st.generation), Array(st.X), Array(st.u)
                live = findall(>(0), Array(st.volume))
                parents = filter(c -> 3 <= c <= 6, live)
                daughters = filter(c -> !(3 <= c <= 6) && X[c] != 0, live)
                @test length(parents) == 4 && !isempty(daughters)
                @test any(d -> gen[d] >= 2, daughters)                  # some daughter took a reused slot
                # the rule's stream, recovered from the parents alone (generation 1 throughout)
                ns = filter(n -> all(c -> X[c] == U(E(c, gen[c]), n, 8), parents), 0:63)
                @test length(ns) == 1
                n = only(ns)
                for d in daughters
                    @test X[d] == U(E(d, gen[d]), n, 8)                  # her generation after the increment
                    @test X[d] != U(E(d, gen[d] - 1), n, 8)              # not the one before
                    @test X[d] != U(d, n, 8)                             # nor the raw id
                end
                # `@after_mcs u ~ rand()`: every live cell at its own (id, generation), one stream and MCS
                hits = [(k, m) for k in 0:63, m in 0:10 if all(c -> u[c] == U(E(c, gen[c]), k, m), live)]
                @test length(hits) == 1
                k, m = only(hits)
                @test all(c -> u[c] != U(c, k, m), live)
                @info "D-237 oracle ($label): $(length(daughters)) daughters, generations $(gen[daughters])"
            finally
                Potts.CorePotts._FORCE_DEVICE_LIFECYCLE[] = false
            end
        end
    end
end


@testitem "centroid/displacement: persistent motility" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "centroid/displacement: persistent motility" begin
        σ = zeros(Int32, 48, 48)
        σ[22:26, 22:26] .= 1
        p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 1); seed = 1)
        st, lat = p.u0, p.lattice
        mean_x(σ, d) = sum(i -> CorePotts.coordinates(lat, i)[d], findall(==(1), vec(σ))) / count(==(1), σ)
        @test CorePotts.centroid(Float64, st.cell, lat, 1) == (mean_x(σ, 1), mean_x(σ, 2))
        for (x, new, old) in (((27, 24), 1, 0), ((22, 23), 0, 1))           # add / remove a site
            prop = CorePotts.Proposal{2}(0, 0, x, 0, Int32(old), Int32(new))
            σ2 = copy(σ); σ2[x...] = new
            for k in 1:2
                @test Potts._displacement_axis(Float64, st.cell, lat, prop, 1, k) ≈ mean_x(σ2, k) - mean_x(σ, k)
                @test Potts._displacement_axis(Float64, st.cell, lat, prop, 2, k) == 0
            end
        end
        s = solve(p, SequentialCPM())
        @test s[:x][end][1] ≈ s.u[end].cell.cx[1]
        function travel(μ)
            d = map(1:6) do seed
                u = solve(remake(p; p = [:μ => μ], tspan = (0, 60), seed), SequentialCPM()).u[end]
                hypot(u.cell.cx[1] - 24, u.cell.cy[1] - 24)
            end
            return sum(d) / length(d)
        end
        @test travel(1000.0) > 2 * travel(0.0)
        @potts_model BadCentroid begin
            @kinds medium A
            @lattice Lattice((8, 8))
            @drive copy => centroid(1)
            @sweep Metropolis(; temperature = 1.0)
        end
        err = try
            mtkcompile(BadCentroid(; name = :b))
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("centroid(k)", sprint(showerror, err)) && occursin("needs a cell", sprint(showerror, err))
    end
end


@testitem "centroid/displacement/rand review regressions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "centroid/displacement/rand review regressions" begin
        @potts_model _BadCentroidRand begin
            @structural_parameters case = 1
            @kinds medium A
            @variables cz(cell) = 0.0
            @lattice Lattice((8, 8))
            if case == 1
                @drive copy => -displacement(new, 3)   # 2D: no axis 3
            elseif case == 2
                @after_mcs cz ~ centroid(3)
            elseif case == 3
                @energy cells => 100 * (centroid(1) - 5)^2
            else
                @observed r ~ rand()
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        for case in 1:4
            @test_throws ArgumentError mtkcompile(_BadCentroidRand(; name = :b, case))
        end
        # empty cell slots observe a zero centroid, not NaN
        σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
        p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 2); capacity = 4)
        x = solve(p, SequentialCPM())[:x][end]
        @test length(x) == 4 && x[2:4] == zeros(3) && !any(isnan, x)
    end
end


@testitem "vector quantities" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "vector quantities" begin
        @potts_model PersistentVec begin
            @kinds medium A
            @parameters μ = 0.0 T = 2.0
            @lattice Lattice((48, 48); neighborhood = Moore(1))
            @variables begin
                pol(cell)[1:2] = 0.0
                c(cell)[1:2] = 0.0
            end
            @energy begin
                Volume(A; target = 25.0, strength = 2.0)
                contacts => 4 * (kind != neighbor_kind)
            end
            @drive copy => -μ * (dot(pol[new], displacement(new)) + dot(pol[old], displacement(old)))
            @after_mcs begin
                pol ~ ifelse(mcs == 0, 0.0, 1.0) .* (0.8 * Pre(pol) + 0.2 * (centroid() - Pre(c)))
                c ~ centroid()
            end
            @observed speed(cell) ~ norm(pol)
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
        for μ in (0.0, 1000.0)
            a = solve(PottsProblem(Persistent(; name = :a, μ), [ownership => σ, kind => [1]], (0, 30); seed = 5), SequentialCPM())
            b = solve(PottsProblem(PersistentVec(; name = :b, μ), [ownership => σ, kind => [1]], (0, 30); seed = 5), SequentialCPM())
            @test a.u[end].ownership == b.u[end].ownership                                          # same model, same run
            @test a.u[end].cell.px ≈ b.u[end].cell.pol_1 && a.u[end].cell.cy ≈ b.u[end].cell.c_2
            @test b[:speed][end] ≈ hypot.(b.u[end].cell.pol_1, b.u[end].cell.pol_2)
        end
        σ2 = zeros(Int32, 12, 12); σ2[4:6, 4:6] .= 1
        p = PottsProblem(VectorBits(; name = :v), [ownership => σ2, kind => [1]], (0, 3); capacity = 4)
        @test p.p.d_1 == 1.0 && p.p.d_2 == 0.0 && p.u0.cell.q_3[1] == 3.0 && all(==(0.5), p.u0.site.g_1)
        u = solve(p, SequentialCPM()).u[end]
        @test u.model.m_1[1] == 3 && u.model.m_2[1] == 0
        @test all(x -> x ≈ sqrt(0.5), u.site.g_1) && all(x -> x ≈ -sqrt(0.5), u.site.g_2)
        live = findall(>(0), u.cell.volume)
        @test length(live) == 2 && sum(u.cell.q_2[live]) ≈ 2.0                    # Split() per component
        q = remake(p; p = [:d => [0.0, 2.0]])
        @test q.p.d_1 == 0.0 && q.p.d_2 == 2.0
        r = PottsProblem(
            VectorBits(; name = :v, d = [5.0, 6.0]), [
                ownership => σ2, kind => [1], :q => [(7.0, 8.0, 9.0)],
                :g => fill(1.0, 12, 12, 2),
            ], (0, 1)
        )
        @test r.p.d_2 == 6.0 && r.u0.cell.q_2[1] == 8.0 && all(==(1.0), r.u0.site.g_2)
        @test_throws ArgumentError PottsProblem(VectorBits(; name = :v), [ownership => σ2, kind => [1], :q => [1.0, 2.0]], (0, 1))
    end
end


@testitem "compound assignments, single writers, replacement" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "compound assignments, single writers, replacement" begin
        @potts_model Compound begin
            @kinds medium A
            @variables begin
                n(model) = 0.0
                g(model) = 1.0
                hits(site) = 0.0
                v(cell)[1:2] = 0.0
            end
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9)^2
            @on_copy hits[target] += 1
            @after_mcs begin
                n += 1
                n += 2
                n -= 0.5
                g *= 2
                v += [1.0, -1.0]
            end
            @sweep Metropolis(; temperature = 4.0)
        end

        @potts_model CompoundBase begin
            @kinds medium A
            @variables n(model) = 0.0
            @lattice Lattice((10, 10))
            @after_mcs n += 1
            @observed twice ~ 2n
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model CompoundExt begin
            @extend n = base = CompoundBase()
            @kinds medium A
            @after_mcs n += 10                 # replaces the base's update of `n`
            @observed twice ~ 3n               # and its observed `twice`
        end

        σ = zeros(Int32, 10, 10); σ[4:6, 4:6] .= 1
        sol = solve(PottsProblem(Compound(; name = :c), [ownership => σ, kind => [1]], (0, 4)), SequentialCPM())
        u = sol.u[end]
        @test u.model.n[1] == 4 * 2.5 && u.model.g[1] == 16
        @test u.cell.v_1[1] == 4 && u.cell.v_2[1] == -4
        @test sum(u.site.hits) == sol.stats.accepted                            # one per accepted copy
        s2 = solve(PottsProblem(CompoundExt(; name = :e), [ownership => σ, kind => [1]], (0, 3)), SequentialCPM())
        @test s2.u[end].model.n[1] == 30 && s2[:twice][end] == 90
        @potts_model _CompoundWriter begin
            @structural_parameters bad = true
            @kinds medium A
            @variables n(model) = 0.0
            @lattice Lattice((8, 8))
            if bad
                @after_mcs begin
                    n ~ 1.0
                    n ~ 2.0
                end
            else
                @after_mcs n += 1
                @after_mcs Every(5) n ~ 0.0
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        err_two = try
            mtkcompile(_CompoundWriter(; name = :b, bad = true))
            nothing
        catch e
            e
        end
        @test err_two isa ArgumentError && occursin("already written", sprint(showerror, err_two))
        @test_throws ["has both", "writes in one block"] Potts._potts_model(
            :_BadW1, quote
                @kinds medium A
                @variables n(model) = 0.0
                @lattice Lattice((8, 8))
                @after_mcs begin
                    n ~ 1.0
                    n += 2.0
                end
                @sweep Metropolis(; temperature = 1.0)
            end, @__MODULE__
        )
        @test_throws ["additive and multiplicative", "do not combine"] Potts._potts_model(
            :_BadW2, quote
                @kinds medium A
                @variables n(model) = 0.0
                @lattice Lattice((8, 8))
                @after_mcs begin
                    n += 1.0
                    n *= 2.0
                end
                @sweep Metropolis(; temperature = 1.0)
            end, @__MODULE__
        )
        @test mtkcompile(_CompoundWriter(; name = :ok, bad = false)) isa CompiledPottsSystem   # another cadence
    end
end


@testitem "P6.4a1: copy-scope `mcs` is the number of completed MCS (on-copy readback)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.4a1: copy-scope `mcs` is the number of completed MCS (on-copy readback)" begin
        @potts_model CopyClock begin
            @kinds medium A
            @parameters w = 0.0
            @variables m(site) = -1.0
            @lattice Lattice((16, 16); boundary = (Periodic(), Closed()))
            @energy begin
                cells(A) => (volume - 20.0)^2
                contacts => 2.0 * (kind != neighbor_kind)
            end
            @drive copy => w * mcs * direction[1] * position[source][2]
            @on_copy m[target] ~ mcs
            @sweep Metropolis(; temperature = 6.0)
        end

        function _copyclock_problem(n)
            σ = zeros(Int32, 16, 16)
            σ[3:7, 3:7] .= 1
            σ[10:14, 9:13] .= 2
            return PottsProblem(CopyClock(; name = :clock), [ownership => σ, kind => [:A, :A]], (0, n); seed = 3)
        end

        for alg in (
                SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)),
                SequentialCPM(; skip_interior = true, proposal = Moore(1)),
            )
            sol = solve(_copyclock_problem(3), alg; saveat = 1)
            ms = [Set(filter(>=(0), u.site.m)) for u in sol.u]
            @test isempty(ms[1])                                     # before the run: never written
            # after MCS n, the values written are 0, …, n − 1 (each MCS accepts copies here)
            @test ms[2] == Set([0.0]) && ms[3] ⊆ Set([0.0, 1.0]) && 1.0 in ms[3]
            @test maximum(ms[4]) == 2.0                              # MCS 3 writes 2, never 3
        end
        # outside a run (the host hook) `mcs` is 0
        prob = _copyclock_problem(3)
        lat = prob.lattice
        t, s = (8, 5), (7, 5)
        prop = Potts.CorePotts.Proposal(
            Potts.CorePotts.linear_index(lat, t), Potts.CorePotts.linear_index(lat, s), t, 1,
            prob.u0.ownership[t...], prob.u0.ownership[s...]
        )
        @test prob.f.delta_H(prob.u0, prob.p, prop, Potts._host_ctx(prob)) == energy_change(prob, prob.u0, prop)
    end
end


@testitem "P6.4a1: copy-scope `direction` and `position[s][k]` diagnostics" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.4a1: copy-scope `direction` and `position[s][k]` diagnostics" begin
        @potts_model DirDiagProbe begin
            @structural_parameters case = :drive_vec use_hex = false
            @kinds medium A
            @variables u(site) = 0.0
            if use_hex
                @lattice Lattice((8, 8); geometry = Potts.CorePotts.Hexagonal())
            else
                @lattice Lattice((8, 8))
            end
            @energy cells(A) => (volume - 10.0)^2
            if case === :drive_vec
                @drive copy => direction
            elseif case === :drive_axis3
                @drive copy => direction[3]
            elseif case === :drive_axis0
                @drive copy => direction[0]
            elseif case === :pos_axis3
                @drive copy => position[target][3]
            elseif case === :pos_vec
                @drive copy => position[target]
            elseif case === :pos_missing_site
                @drive copy => position[1]
            elseif case === :energy_dir
                @energy cells(A) => direction[1]
            elseif case === :drive_pre
                @drive copy => Pre(u[target], 2)
            elseif case === :ok_drive
                @drive copy => direction[1] * position[target][2] + mcs
            elseif case === :ok_constraint
                @constraint direction[1]^2 + direction[2]^2 <= 1.5
            else
                @drive copy => direction[2]
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        function build(case; use_hex = false)
            try
                mtkcompile(DirDiagProbe(; name = :bad, case, use_hex))
                return ""
            catch e
                return sprint(showerror, e)
            end
        end
        @test occursin("write its component `direction[k]`", build(:drive_vec))
        @test occursin("axis of the 2D lattice", build(:drive_axis3))
        @test occursin("axis of the 2D lattice", build(:drive_axis0))
        @test occursin("axis of the 2D lattice", build(:pos_axis3))
        @test occursin("is a vector", build(:pos_vec))
        @test occursin("needs a site", build(:pos_missing_site))
        @test occursin("`direction` is not available", build(:energy_dir))
        @test occursin("`Pre(x, k)` needs the MCS clock", build(:drive_pre))
        @test_throws ["has the name of a built-in"] Potts._potts_model(
            :DirBadParam, quote
                @kinds medium A
                @parameters direction = 1.0
            end, @__MODULE__
        )
        # negative control: the forms of the acceptance file build
        @test build(:ok_drive) == ""
        @test build(:ok_constraint) == ""
        @test build(:ok_hex; use_hex = true) == ""
    end
end
