import KernelAbstractions
import LocalMath

function run_localmath_lattice_spring_witness(
        array_type = Array; backend = KernelAbstractions.CPU(),
        force_mode::Symbol = :deterministic)
    force_mode in (:deterministic, :fast) || throw(ArgumentError(
        "force_mode must be :deterministic or :fast"))
    displacements = Int32[0, 2, 9, 14, 13]
    edge_nodes = Int32[1 2 3 4; 2 3 4 5]
    edge_route = reshape(Int32[4, 1, 3, 2], 1, 4)
    force_route = Int32[1 2 3 1; 2 3 4 4]
    fracture_route = reshape(Int32[1, 1, 2, 2], 1, 4)
    prior_damage_values = Float32[3, 1, 7, 0]
    identity_values = UInt32[40, 10, 30, 20]

    edges = LocalMath.Space(4)
    nodes = LocalMath.Space(5)
    buckets = LocalMath.Space(3)
    incidence = LocalMath.FixedRelation(edges => nodes; degree = 2)
    damage_route = LocalMath.FixedRelation(edges => edges; degree = 1)
    state_route = LocalMath.FixedRelation(edges => edges; degree = 1)
    forces_route = LocalMath.FixedRelation(edges => nodes; degree = 2)
    failures_route = LocalMath.FixedRelation(edges => buckets; degree = 1)
    displacement = LocalMath.Field(nodes, Int32)
    prior_damage = LocalMath.Field(edges, Float32)
    identities = LocalMath.Field(edges, UInt32)
    damage = LocalMath.Field(edges, Float32)
    edge_state = LocalMath.Field(edges, Float32)
    force = LocalMath.Field(nodes, Float32)
    fracture = LocalMath.Field(buckets, UInt32)

    reduction_order = force_mode === :deterministic ? :canonical : :relaxed
    law = LocalMath.@localmath begin
        @stage damage_update(edge ∈ edges) begin
            endpoint_values = displacement[incidence(edge)]
            extension = endpoint_values[2] - endpoint_values[1]
            damage[damage_route(edge)] =
                prior_damage[edge] + abs(Float32(extension))
        end

        @stage force_and_fracture(edge ∈ edges) begin
            endpoint_values = displacement[incidence(edge)]
            extension = endpoint_values[2] - endpoint_values[1]
            damage_value = damage[edge]
            edge_state[state_route(edge)] = damage_value
            force[forces_route(edge)] = reduce_to((
                Float32(extension), -Float32(extension));
                op = +, seed = 0f0, order = reduction_order)
            fracture[failures_route(edge)] = resolve_to(;
                score = extension,
                tie = identities[edge],
                payload = UInt32(edge), sense = :max,
                lower = Int32(0), upper = Int32(20),
                onempty = UInt32(0), when = damage_value >= 5f0)
        end
    end
    expected_damage = similar(prior_damage_values)
    expected_edge = fill(0f0, 4)
    expected_force = fill(0f0, 5)
    expected_fracture = fill(UInt32(0), 3)
    winner_rank = fill(typemin(Int32), 3)
    winner_identity = fill(typemax(UInt32), 3)
    for item in 1:4
        extension = displacements[edge_nodes[2, item]] -
            displacements[edge_nodes[1, item]]
        value = prior_damage_values[item] + abs(Float32(extension))
        expected_damage[item] = value
        expected_edge[edge_route[item]] = value
        expected_force[force_route[1, item]] += Float32(extension)
        expected_force[force_route[2, item]] -= Float32(extension)
        value >= 5f0 || continue
        destination = fracture_route[item]
        if extension > winner_rank[destination] ||
                extension == winner_rank[destination] &&
                identity_values[item] < winner_identity[destination]
            winner_rank[destination] = extension
            winner_identity[destination] = identity_values[item]
            expected_fracture[destination] = UInt32(item)
        end
    end

    displacement_storage = array_type(displacements)
    prior_damage_storage = array_type(prior_damage_values)
    identity_storage = array_type(identity_values)
    damage_storage = array_type(fill(0f0, 4))
    edge_state_storage = array_type(fill(0f0, 4))
    force_storage = array_type(fill(0f0, 5))
    fracture_storage = array_type(fill(UInt32(0), 3))
    prepared = LocalMath.@prepare (law; backend, lease_capacity = 3) begin
        displacement = displacement_storage
        prior_damage = prior_damage_storage
        identities = identity_storage
        damage = damage_storage
        edge_state = edge_state_storage
        force = force_storage
        fracture = fracture_storage
        incidence = array_type(edge_nodes)
        damage_route = array_type(reshape(Int32.(1:4), 1, 4))
        state_route = array_type(edge_route)
        forces_route = array_type(force_route)
        failures_route = array_type(fracture_route)
    end
    wait(LocalMath.execute!(prepared))
    actual_damage = Array(damage_storage)
    actual_edge = Array(edge_state_storage)
    actual_force = Array(force_storage)
    actual_fracture = Array(fracture_storage)
    actual_damage == expected_damage || error("spring damage mismatch")
    actual_edge == expected_edge || error("spring edge mismatch")
    force_mode === :deterministic ?
        actual_force == expected_force || error("spring force mismatch") :
        all(isapprox.(actual_force, expected_force; rtol = 8eps(Float32))) ||
            error("spring fast-force mismatch")
    actual_fracture == expected_fracture || error("spring fracture mismatch")
    return (name = :lattice_spring, force_mode,
        result = (damage = actual_damage, edge_state = actual_edge,
            force = actual_force, fracture = actual_fracture),
        reference = (damage = expected_damage, edge_state = expected_edge,
            force = expected_force, fracture = expected_fracture),
        semantics = LocalMath.inspect(law))
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_localmath_lattice_spring_witness()
