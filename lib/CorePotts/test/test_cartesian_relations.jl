@kernel function _relation_probe!(sites, kinds, domain, relation)
    direction = @index(Global, Linear)
    neighbor = realize_neighbor(domain, relation, 1, direction)
    sites[direction] = neighbor.site
    kinds[direction] = UInt8(neighbor.kind)
end

@testset "compiled Cartesian relation semantics" begin
    roles = (ProposalRole(), ContactRole(), SurfaceRole(), ConnectivityRole(),
        SpatialQueryRole(), FieldDiscretizationRole(), ConflictRole())
    role_relations = map(
        role -> first_shell_relation(role, Val(2); symmetric = true), roles)
    @test length(unique(typeof.(roles))) == 7
    @test map(relation -> relation_semantics_report(relation).role, role_relations) ==
          nameof.(typeof.(roles))
    @test all(isbitstype ∘ typeof, role_relations)
    normalized2 = normalized_kernel_relation(Val(2); spacing = (1.0f0, 1.0f0))
    normalized3 = normalized_kernel_relation(Val(3);
        spacing = (1.0f0, 1.0f0, 1.0f0))
    @test direction_count(normalized2) == 20
    @test direction_count(normalized3) == 80
    @test all(direction -> relation_weight(normalized2, direction) == 1.0f0,
        1:direction_count(normalized2))

    periodic2 = CartesianDomain((5, 4); spacing = (2.0, 1.0))
    @test mutable_site_count(periodic2) == 20
    @test periodic2.spacing == [2.0, 1.0]
    proposal = first_shell_relation(ProposalRole(), Val(2); spacing = periodic2.spacing)
    @test isbitstype(typeof(proposal))
    @test canonicalization_version(proposal) == v"1.0.0"
    @test direction_count(proposal) == 4
    @test Tuple.(proposal.offsets) == ((0, -1), (0, 1), (-1, 0), (1, 0))
    @test all(
        direction -> opposite_direction(proposal,
            opposite_direction(proposal, direction)) == direction,
        1:4)
    @test validate_relation_domain(periodic2, proposal) === proposal

    # Physical spacing makes -y the first canonical direction; it wraps to coordinate (0, 3).
    wrapped = realize_neighbor(periodic2, proposal, 1, 1)
    @test wrapped.kind === MutableNeighbor
    @test wrapped.site == 16
    multiwrap = static_relation(
        SpatialQueryRole(), ((0, -9), (0, 9)); symmetric = true)
    @test realize_neighbor(periodic2, multiwrap, 1, 1).site == 16
    @test realize_neighbor(periodic2, multiwrap, 1, 2).site == 6

    closed2 = CartesianDomain((5, 4);
        boundaries = (
            AxisBoundary(ClosedBoundary()), AxisBoundary(ClosedBoundary())))
    @test realize_neighbor(closed2, proposal, 1, 1).kind === AbsentNeighbor
    @test realize_neighbor(closed2, proposal, 1, 3).kind === AbsentNeighbor
    @test realize_neighbor(closed2, proposal, 1, 2).site == 6

    wall = MediumOwner(7)
    fixed2 = CartesianDomain((5, 4);
        boundaries = (
            AxisBoundary(FixedExterior(wall), ClosedBoundary()),
            AxisBoundary(ClosedBoundary())))
    contact = first_shell_relation(ContactRole(), Val(2))
    exterior = realize_neighbor(fixed2, contact, 1, 1)
    @test exterior.kind === ExteriorNeighbor
    @test fixed_owner(exterior) == wall
    @test realize_neighbor(fixed2, proposal, 1, 3).kind === AbsentNeighbor

    obstacle = MediumOwner(9)
    obstacle_domain = CartesianDomain((5, 4);
        obstacles = (CartesianIndex(3, 2) => obstacle,))
    obstacle_site = LinearIndices((5, 4))[CartesianIndex(3, 2)]
    @test mutable_site_count(obstacle_domain) == 19
    @test immutable_owner(obstacle_domain, obstacle_site) == obstacle
    obstacle_report = domain_semantics_report(obstacle_domain)
    @test obstacle_report.mutable_site_count == 19
    @test obstacle_report.obstacles ==
          ((site = obstacle_site, owner_kind = :medium, owner_id = UInt32(9)),)
    # Site immediately left of the obstacle reaches it through +x, direction 4.
    contact_obstacle = realize_neighbor(obstacle_domain, contact, obstacle_site - 1, 4)
    @test contact_obstacle.kind === FixedNeighbor
    @test fixed_owner(contact_obstacle) == obstacle
    @test realize_neighbor(obstacle_domain, proposal, obstacle_site - 1, 4).kind ===
          AbsentNeighbor

    compiled = compile_domain(obstacle_domain)
    @test domain_storage_valid(compiled.storage)
    @test compiled.storage.mutable_sites ==
          UInt32.(findall(vec(obstacle_domain.mutable_mask)))
    @test realize_neighbor(compiled, contact, obstacle_site - 1, 4) == contact_obstacle

    backend = KernelAbstractions.CPU()
    sites = zeros(UInt32, direction_count(proposal))
    kinds = zeros(UInt8, direction_count(proposal))
    kernel = _relation_probe!(backend, 4)
    kernel(sites, kinds, compile_domain(periodic2), proposal; ndrange = 4)
    KernelAbstractions.synchronize(backend)
    @test sites == UInt32[16, 6, 5, 2]
    @test kinds == fill(UInt8(MutableNeighbor), 4)

    periodic3 = CartesianDomain((4, 5, 6); spacing = (1.0f0, 2.0f0, 3.0f0))
    relation3 = first_shell_relation(SurfaceRole(), Val(3); spacing = periodic3.spacing)
    @test direction_count(relation3) == 6
    @test validate_relation_domain(periodic3, relation3) === relation3
    @test all(
        direction -> opposite_direction(relation3,
            opposite_direction(relation3, direction)) == direction,
        1:6)

    @test_throws ArgumentError CartesianDomain((3, 3);
        boundaries = (
            AxisBoundary(PeriodicBoundary(), ClosedBoundary()),
            AxisBoundary(ClosedBoundary())))
    @test_throws ArgumentError CartesianDomain((Int(typemax(Int32)) + 1, 1))
    @test_throws ArgumentError CartesianDomain((65_536, 65_536))
    @test_throws ArgumentError static_relation(ContactRole(), ((1, 0), (1, 0)))
    @test_throws ArgumentError static_relation(ContactRole(), ((1, 0), (0, 1)))
    @test_throws ArgumentError static_relation(
        ContactRole(), ((-1, 0), (1, 0)); weights = (1.0, 2.0))
    @test_throws ArgumentError validate_relation_domain(CartesianDomain((2, 3)), proposal)

    diagonal = static_relation(SpatialQueryRole(), ((-1, -1), (1, 1)); symmetric = true)
    ambiguous = CartesianDomain((3, 3);
        boundaries = (
            AxisBoundary(FixedExterior(MediumOwner(2)), ClosedBoundary()),
            AxisBoundary(ClosedBoundary())))
    @test_throws ArgumentError validate_relation_domain(ambiguous, diagonal)
end

@testset "topology-based public relation construction" begin
    topology = MooreTopology{2}()
    direct = static_relation(
        SpatialQueryRole(),
        topology;
        spacing=(0.5f0, 1.5f0),
    )
    legacy = static_relation(
        SpatialQueryRole(),
        CorePotts.offsets(topology);
        spacing=(0.5f0, 1.5f0),
    )
    @test direct == legacy
    @test component_semantic_data(direct) ==
          component_semantic_data(legacy)
    @test_throws ArgumentError static_relation(
        SpatialQueryRole(), topology; spacing=(1.0f0,))
    @test_throws ArgumentError static_relation(
        SpatialQueryRole(), topology; weights=(1.0f0,))
    @test_throws ArgumentError static_relation(
        SpatialQueryRole(), topology; spacing=(1.0f0, 0.0f0))
    @test_throws ArgumentError static_relation(
        SpatialQueryRole(), topology;
        weights=ntuple(index -> index == 1 ? -1.0f0 : 1.0f0, 8),
    )
end
