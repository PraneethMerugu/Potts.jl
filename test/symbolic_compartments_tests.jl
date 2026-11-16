# Split from test/symbolic_tests.jl

@testitem "division rules are per kind; on-copy writes skip the medium" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "division rules are per kind; on-copy writes skip the medium" begin
        @potts_model TwoDivisions begin
            @kinds medium A B
            @parameters begin
                T = 5.0
                J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
            end
            @variables begin
                m(cell) = 8.0
                q(cell) = 5.0
                y(cell) = 0.0
            end
            @lattice Lattice((24, 24); neighborhood = Moore(1))
            @energy contacts => J[kind, kind′]
            @on_copy y[new] ~ 1.0                     # new may be the medium: nothing to write
            @divide cells(A) when = mcs == 0, m => Split()
            @divide cells(B) when = mcs == 1000, q => 0.0
            @constraint no_extinction
            @sweep Metropolis(; temperature = T)
        end

        σ, kinds = two_kind_blocks()
        prob = PottsProblem(TwoDivisions(; name = :td), [ownership => σ, kind => kinds], (0, 2))
        u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]      # retractions happen: no BoundsError
        nA = count(==(1), kinds)
        @test count(>(0), u.cell.volume) == length(kinds) + nA
        @test all(==(5.0), u.cell.q[u.cell.volume .> 0])                  # B's rule never ran on A cells
        @test all(c -> u.cell.m[c] == (kinds[c] == 1 ? 4.0 : 8.0), 1:length(kinds))
    end
end


@testitem "compartments in the authoring surface" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "compartments in the authoring surface" begin
        σ, kinds, groups = compartment_state()
        prob = PottsProblem(Compartments(; name = :comp), [ownership => σ, kind => kinds, cluster => groups], (0, 1))
        u0 = prob.u0
        @test Array(u0.cell.cluster)[1:18] == vcat(1:9, 1:9)
        @test Array(u0.cell.cluster_volume)[1:9] == fill(64, 9)
        @test Array(u0.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(σ, u0.cell.cluster, prob.lattice, Moore(1)) &&
            allequal(Array(u0.cell.cluster_surface)[1:9])      # nuclei are internal
        # the hand-written CorePotts model (lib/CorePotts/test/compartments.jl)
        Jt = [0 16 16; 16 14 30; 16 30 14]
        ki(st, a) = a == 0 ? 1 : Int(st.cell.kind[a]) + 1
        function hand(st, p, prop, ctx)
            J(a, b) = CorePotts.same_cluster(st.cell, a, b) ? 2.0 : Float64(Jt[ki(st, a), ki(st, b)])
            E(v, c) = (v - (48.0, 16.0)[st.cell.kind[c]])^2
            EC(v, k) = st.cell.kind[k] == 1 ? (v - 64.0)^2 : 0.0
            ES(s, k) = st.cell.kind[k] == 1 ? 0.1 * (s - 32.0)^2 : 0.0
            return CorePotts.contact_delta(st.σ, ctx, prop, J) + CorePotts.volume_delta(st.cell.volume, prop, E) +
                CorePotts.cluster_volume_delta(st.cell, prop, EC) +
                CorePotts.cluster_surface_delta(st.cell, prop, CorePotts.cluster_surface_change(st.σ, st.cell, ctx, prop), ES)
        end
        ctx = ctx_of(prob)
        states = proposal_states(remake(prob; tspan = (0, 1)); mcs = (0, 1), n = 400)
        @test maximum(((u, prop),) -> abs(prob.f.delta_H(u, prob.p, prop, ctx) - hand(u, prob.p, prop, ctx)), states) < 1.0e-9
        @test selfcheck(remake(prob; tspan = (0, 1))) < 1.0e-9
        # trackers stay exact through a run
        u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
        cl = Array(u.cell.cluster)
        @test Array(u.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(u.σ), cl)
        @test Array(u.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(u.σ), cl, prob.lattice, Moore(1))
        # a cluster divides as a unit: both daughters keep a nucleus and a cytoplasm
        sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = Moore(1)))
        v = sol.u[end]
        live = findall(>(0), Array(v.cell.volume))
        @test length(live) == 36
        roots = unique(Array(v.cell.cluster)[live])
        @test length(roots) == 18
        @test all(r -> sort(Array(v.cell.kind)[filter(c -> v.cell.cluster[c] == r, live)]) == [1, 2], roots)
        @test sum(Array(v.cell.mass)[live]) ≈ 36.0          # every member split its mass
        @test sort(Array(v.cell.mass)[live]) == fill(1.0, 36)
    end
end


@testitem "compartment validation" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "compartment validation" begin
        @test_throws ArgumentError mtkcompile(
            Potts.PottsSystem(;
                name = :x, kinds = [:medium, :ka],
                lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
                energies = [Potts.EnergyTerm(Potts.CellDomain(Int[]), Potts.B.cluster_volume^2)]
            )
        )
        @test_throws ArgumentError mtkcompile(
            Potts.PottsSystem(;
                name = :x, kinds = [:medium, :ka],
                lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
                energies = [Potts.EnergyTerm(Potts.ContactDomain(:contact), Potts.B.cluster_volume)]
            )
        )
        # P6.0a: cell and cluster divisions mix per kind, but one kind divides by one domain
        divsys(cellk, clusterk) = Potts.PottsSystem(;
            name = :x, kinds = [:medium, :ka, :kb],
            lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
            divisions = [Potts.divide(cellk; when = Potts.B.volume > 1), Potts.divide(clusterk; when = Potts.B.volume > 1)]
        )
        err = try
            mtkcompile(divsys(Potts.cells(1), Potts.clusters(1, 2)))
        catch e
            e
        end
        @test err isa ArgumentError && occursin("`ka`", err.msg) && !occursin("`kb`", err.msg)
        @test_throws ArgumentError mtkcompile(divsys(Potts.cells, Potts.clusters(2)))      # bare `cells` is every kind
        @test mtkcompile(divsys(Potts.cells(2), Potts.clusters(1))) isa Potts.CompiledPottsSystem
    end
end


@testitem "cell and cluster divisions in one model" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "cell and cluster divisions in one model" begin
        σ, kinds, groups = compartment_state()
        prob = PottsProblem(NucleusDivision(; name = :nd), [ownership => σ, kind => kinds, cluster => groups], (0, 5))
        @test selfcheck(remake(prob; tspan = (0, 1))) < 1.0e-9
        for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
            check_nucleus_division(solve(prob, alg).u[end])
        end
    end
end


@testitem "cell and cluster divisions in one model on the device" setup = [SymbolicSetup] tags = [:potts, :symbolic, :device] begin
    PottsDevices.on_device() && @testset "cell and cluster divisions in one model on the device" begin
        σ, kinds, groups = compartment_state()
        prob = PottsProblem(
            NucleusDivision(; name = :nd), [ownership => σ, kind => kinds, cluster => groups], (0, 5);
            T = Float32
        )
        check_nucleus_division(solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend = PottsDevices.device_backend()).u[end])
    end
end


@testitem "compartment review regressions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "compartment review regressions" begin
        @potts_model ClusterCensus begin
            @kinds medium cytoplasm nucleus
            @parameters T = 10.0
            @variables total(model) = 0.0
            @lattice Lattice((30, 30); neighborhood = Moore(1))
            @energy cells => (volume - 40.0)^2
            @after_mcs total ~ sum(cluster_volume for c in cells)
            @divide cells(nucleus) when = (cluster == id) && (mcs == 100), along = (1.0, 0.0)
            @sweep Metropolis(; temperature = T)
        end

        σ, kinds, groups = compartment_state()
        # populations read the bound cell's cluster trackers
        p = PottsProblem(ClusterCensus(; name = :cc), [ownership => σ, kind => kinds, cluster => groups], (0, 1))
        u = solve(p, SequentialCPM(; proposal = Moore(1))).u[end]
        @test u.model.total[1] == sum(u.cell.cluster_volume[u.cell.cluster[c]] for c in 1:18 if u.cell.volume[c] > 0)
        # roots are chosen among the kinds that name clusters, whatever the numbering
        n = 9
        σn = map(s -> s == 0 ? s : Int32(s <= n ? s + n : s - n), σ)     # nuclei first
        pn = PottsProblem(
            Compartments(; name = :comp), [
                ownership => σn, kind => vcat(kinds[(n + 1):end], kinds[1:n]),
                cluster => groups,
            ], (0, 1)
        )
        @test Array(pn.u0.cell.cluster)[1:18] == vcat((n + 1):2n, (n + 1):2n)
        @test total_energy(pn) ≈ total_energy(
            PottsProblem(
                Compartments(; name = :comp),
                [ownership => σ, kind => kinds, cluster => groups], (0, 1)
            )
        )
        # remake with a new state recomputes the frozen mask
        σk = zeros(Int32, 24, 24); σk[:, 1:2] .= 1; σk[10:14, 10:14] .= 2
        kt = PottsProblem(KindTemperature(; name = :kt), [ownership => σk, kind => [:wall, :dark]], (0, 5))
        σk2 = zeros(Int32, 24, 24); σk2[:, 23:24] .= 1; σk2[10:14, 10:14] .= 2
        kt2 = remake(kt; u0 = [ownership => σk2, kind => [:wall, :dark]])
        @test kt2.frozen == (σk2 .== 1)
        # clusters used only in a division condition or an observed quantity still get storage
        base = (;
            name = :x, kinds = [:medium, :ka], lattice = Potts.lattice_spec((8, 8)),
            sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        )
        @test getfield(
            mtkcompile(
                Potts.PottsSystem(;
                base..., divisions = [
                    Potts.divide(
                        Potts.cells(1);
                        when = Potts.B.cluster == Potts.B.id
                    ),
                ]
            )
            ), :uses_clusters
        )
        @test getfield(
            mtkcompile(
                Potts.PottsSystem(;
                base..., observed = [
                    Potts._observed_eq(
                        Potts.observed_var(:cv),
                        Potts.B.cluster_volume
                    ),
                ]
            )
            ), :uses_clusters
        )
    end
end


@testitem "irregular lattice domains in the surface" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "irregular lattice domains in the surface" begin
        sys = DiskSorting(; name = :disk)
        mask = Potts.lattice(sys).domain
        σ, kinds = two_kind_blocks()
        σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= σ
        @test all(mask[σd .> 0])
        prob = PottsProblem(sys, [ownership => σd, kind => kinds], (0, 30); field_solver = ExplicitEuler())
        @test count(prob.frozen) == count(!, mask)
        @test selfcheck(prob) < 1.0e-9
        u = solve(prob, CheckerboardCPM(; proposal = Moore(1))).u[end]
        @test all(u.σ[.!mask] .== 0) && all(u.site.c[.!mask] .== 0)
        @test sum(u.site.c) > 0
        σbad = copy(σd); σbad[1, 1] = 1
        @test_throws ArgumentError PottsProblem(sys, [ownership => σbad, kind => kinds], (0, 1); field_solver = ExplicitEuler())
    end
end


@testitem "3D models" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "3D models" begin
        @potts_model Sorting3D begin
            @kinds medium dark light
            @parameters begin
                λ = 1.0
                V₀ = 64.0
                λₛ = 0.01
                S₀ = 430.0                         # a 4³ cube has 432 NeighborOrder(2) bonds
                T = 12.0
                J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
            end
            @variables mass(cell) = 1.0
            @lattice Lattice(
                (24, 24, 24); boundary = Closed(), neighborhood = NeighborOrder(2),
                domain = x -> sum(abs2, x .- 12.5) <= 11.5^2
            )
            @energy begin
                cells(dark, light) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
                contacts => J[kind, kind′]
            end
            @fields c = SyPDE.sorting3d() (SyPDE.src => kind == dark)
            @drive copy => -2.0 * (c[target] - c[source]) * (kind[new] == dark)
            @divide cells(dark) when = (mcs == 3) && (volume >= 40), along = principal_axis(), mass => Split()
            @sweep Metropolis(; temperature = T)
        end

        σ = zeros(Int32, 24, 24, 24)
        n = 0
        for i in 8:5:13, j in 8:5:13, k in 8:5:13
            n += 1
            σ[i:(i + 3), j:(j + 3), k:(k + 3)] .= n
        end
        kinds = [isodd(c) ? :dark : :light for c in 1:n]
        prob = PottsProblem(Sorting3D(; name = :s3), [ownership => σ, kind => kinds], (0, 6); field_solver = ExplicitEuler())
        @test ndims(prob.lattice) == 3 && length(prob.contact) == 18                      # NeighborOrder(2) in 3D
        @test selfcheck(prob) < 1.0e-9
        for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
            u = solve(prob, alg).u[end]
            live = findall(>(0), u.cell.volume)
            @test length(live) > n                                                      # dark cells divided in 3D
            @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
            @test u.cell.surface ≈ CorePotts.recompute_surface(
                u.σ, prob.lattice, prob.relations.surface, length(u.cell.volume);
                T = eltype(u.cell.surface)
            )
            @test sum(u.cell.mass[live]) ≈ n
            @test all(u.σ[.!prob.lattice.mask] .== 0)
        end
    end
end


@testitem "hexagonal lattices in the surface" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "hexagonal lattices in the surface" begin
        σ = zeros(Int32, 30, 30); c0 = zeros(30, 30); c0[15, 15] = 100.0
        n = 0
        for q in 4:6:26, r in 4:6:26
            n += 1
            for x in CartesianIndices(σ)
                CorePotts._hexdist(Tuple(x) .- (q, r)) <= 2 && (σ[x] = n)
            end
        end
        p = PottsProblem(
            HexSorting(; name = :h), [ownership => σ, kind => [isodd(k) ? :dark : :light for k in 1:n], :c => c0], (0, 20);
            field_solver = ExplicitEuler()
        )
        @test p.lattice.geometry isa Hexagonal && length(p.contact) == 18
        for alg in (SequentialCPM(proposal = Hex(1)), CheckerboardCPM(proposal = Hex(1)))
            u = solve(p, alg).u[end]
            @test u.cell.volume == [count(==(k), u.σ) for k in 1:n]
            @test u.cell.surface ≈ CorePotts.recompute_surface(u.σ, p.lattice, p.relations.surface, n)
            @test sum(u.site.c) ≈ 100                                          # zero-sum 6-point Laplacian
            pos = [embed(p.lattice, Float64.(Tuple(x))) for x in CartesianIndices(u.σ)]
            k = findfirst(>(0), u.cell.volume)
            mine = pos[u.σ .== k]
            @test u.cell.cx[k] ≈ sum(first, mine) / length(mine) atol = 1.0e-9   # centroid() is Cartesian (no wrap here)
        end
    end
end


@testitem "P6.0r: free slots add nothing to total_energy" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0r: free slots add nothing to total_energy" begin
        @potts_model P60rFreeSlots begin
            @kinds medium cytoplasm nucleus
            @parameters begin
                V₀[kind] = [0.0, 6.0, 3.0]
            end
            @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
            @energy begin
                cells => (volume - V₀[kind])^2 + 0.3 * surface + 5.0
                contacts => 4.0
                clusters(cytoplasm) => 1.3 * (cluster_volume - 10.0)^2 + 2.0
            end
            @sweep Metropolis(; temperature = 8.0)
        end

        σc = zeros(Int32, 20, 20); σc[5, 5] = 1; σc[5, 6] = 2; σc[12:14, 12:14] .= 3; σc[13, 13] = 4
        op = [ownership => σc, kind => [:cytoplasm, :nucleus, :cytoplasm, :nucleus], cluster => [1, 1, 3, 3]]
        a = PottsProblem(P60rFreeSlots(; name = :c), op, (0, 5))
        b = PottsProblem(P60rFreeSlots(; name = :c), op, (0, 5); capacity = 50)
        @test length(b.u0.cell.volume) == 50
        @test total_energy(b) ≈ total_energy(a)
    end
end
