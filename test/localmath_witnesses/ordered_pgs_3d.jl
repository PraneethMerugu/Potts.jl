import KernelAbstractions
import LocalMath
import StructArrays

struct _PGS3DContactVisit
    bodies::NTuple{2, Int32}
    normal::NTuple{3, Float32}
    inverse_masses::NTuple{2, Float32}
    rhs::Float32
    effective_mass::Float32
    multiplier::Int32
    ordinal::Int32
    identity::UInt32
end

@inline _pgs3_dot(left, right) =
    left[1] * right[1] + left[2] * right[2] + left[3] * right[3]
@inline _pgs3_sub(left, right) = (
    left[1] - right[1], left[2] - right[2], left[3] - right[3]
)
@inline _pgs3_axpy(value, scale, direction) = (
    value[1] + scale * direction[1],
    value[2] + scale * direction[2],
    value[3] + scale * direction[3],
)

function _pgs3d_scalar_reference(visits, initial_velocities, initial_multipliers)
    velocities = copy(initial_velocities)
    multipliers = copy(initial_multipliers)
    order = sortperm(eachindex(visits); by = index -> (
        visits[index].ordinal, visits[index].identity
    ))
    for index in order
        visit = visits[index]
        first_body, second_body = visit.bodies
        first_velocity = velocities[first_body]
        second_velocity = velocities[second_body]
        old_multiplier = multipliers[visit.multiplier]
        relative = (
            second_velocity[1] - first_velocity[1],
            second_velocity[2] - first_velocity[2],
            second_velocity[3] - first_velocity[3],
        )
        normal_velocity = relative[1] * visit.normal[1] +
            relative[2] * visit.normal[2] +
            relative[3] * visit.normal[3]
        new_multiplier = max(
            0.0f0,
            old_multiplier + visit.effective_mass *
                (visit.rhs - normal_velocity),
        )
        impulse = new_multiplier - old_multiplier
        velocities[first_body] = ntuple(3) do axis
            first_velocity[axis] - visit.inverse_masses[1] *
                impulse * visit.normal[axis]
        end
        velocities[second_body] = ntuple(3) do axis
            second_velocity[axis] + visit.inverse_masses[2] *
                impulse * visit.normal[axis]
        end
        multipliers[visit.multiplier] = new_multiplier
    end
    return (; velocities, multipliers)
end

function _pgs3d_snapshot_counterexample(
        visits, initial_velocities, initial_multipliers
    )
    velocities = copy(initial_velocities)
    multipliers = copy(initial_multipliers)
    velocity_delta = fill((0.0f0, 0.0f0, 0.0f0), length(velocities))
    multiplier_replacement = copy(multipliers)
    for visit in visits
        first_body, second_body = visit.bodies
        first_velocity = initial_velocities[first_body]
        second_velocity = initial_velocities[second_body]
        relative = ntuple(3) do axis
            second_velocity[axis] - first_velocity[axis]
        end
        normal_velocity = sum(
            relative[axis] * visit.normal[axis] for axis in 1:3
        )
        old_multiplier = initial_multipliers[visit.multiplier]
        new_multiplier = max(
            0.0f0,
            old_multiplier + visit.effective_mass *
                (visit.rhs - normal_velocity),
        )
        impulse = new_multiplier - old_multiplier
        first_delta = ntuple(3) do axis
            -visit.inverse_masses[1] * impulse * visit.normal[axis]
        end
        second_delta = ntuple(3) do axis
            visit.inverse_masses[2] * impulse * visit.normal[axis]
        end
        velocity_delta[first_body] = ntuple(3) do axis
            velocity_delta[first_body][axis] + first_delta[axis]
        end
        velocity_delta[second_body] = ntuple(3) do axis
            velocity_delta[second_body][axis] + second_delta[axis]
        end
        multiplier_replacement[visit.multiplier] = new_multiplier
    end
    for body in eachindex(velocities)
        velocities[body] = ntuple(3) do axis
            velocities[body][axis] + velocity_delta[body][axis]
        end
    end
    return (; velocities, multipliers = multiplier_replacement)
end

function _pgs3d_projected_residual(contacts, velocities, multipliers)
    return maximum(contacts; init = 0.0f0) do contact
        first_velocity = velocities[contact.bodies[1]]
        second_velocity = velocities[contact.bodies[2]]
        normal_velocity = sum(
            (second_velocity[axis] - first_velocity[axis]) *
                contact.normal[axis] for axis in 1:3
        )
        old_multiplier = multipliers[contact.multiplier]
        projected = max(
            0.0f0,
            old_multiplier + contact.effective_mass *
                (contact.rhs - normal_velocity),
        )
        abs(projected - old_multiplier)
    end
end

function run_localmath_ordered_pgs_3d_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    contacts = _PGS3DContactVisit[
        _PGS3DContactVisit(
            (Int32(1), Int32(2)), (1.0f0, 0.0f0, 0.0f0),
            (1.0f0, 1.0f0), 1.0f0, 0.5f0,
            Int32(1), Int32(0), UInt32(0),
        ),
        _PGS3DContactVisit(
            (Int32(2), Int32(3)), (1.0f0, 0.0f0, 0.0f0),
            (1.0f0, 1.0f0), 1.0f0, 0.5f0,
            Int32(2), Int32(0), UInt32(0),
        ),
    ]
    visits = _PGS3DContactVisit[]
    ordinal = Int32(0)
    for _ in 1:6, contact in contacts
        ordinal += Int32(1)
        push!(visits, _PGS3DContactVisit(
            contact.bodies,
            contact.normal,
            contact.inverse_masses,
            contact.rhs,
            contact.effective_mass,
            contact.multiplier,
            ordinal,
            reinterpret(UInt32, ordinal),
        ))
    end
    initial_velocities = fill((0.0f0, 0.0f0, 0.0f0), 3)
    initial_multipliers = fill(0.0f0, 2)
    reference = _pgs3d_scalar_reference(
        visits, initial_velocities, initial_multipliers
    )
    snapshot = _pgs3d_snapshot_counterexample(
        visits, initial_velocities, initial_multipliers
    )
    snapshot != reference || error(
        "PGS witness does not distinguish snapshot/Jacobi evaluation"
    )

    source = LocalMath.Space(length(visits))
    body_space = LocalMath.Space(length(initial_velocities))
    multiplier_space = LocalMath.Space(length(initial_multipliers))
    contact_visit = LocalMath.Field(source, _PGS3DContactVisit)
    velocity_initial = LocalMath.Field(body_space, NTuple{3, Float32})
    velocity = LocalMath.Field(body_space, NTuple{3, Float32})
    multiplier_initial = LocalMath.Field(multiplier_space, Float32)
    multipliers = LocalMath.Field(multiplier_space, Float32)
    work = LocalMath.@localmath visit ∈ source begin
        contact = contact_visit[visit]
        first = contact.bodies[1]
        second = contact.bodies[2]
        normal = contact.normal
        inverse_first = contact.inverse_masses[1]
        inverse_second = contact.inverse_masses[2]
        visit_rhs = contact.rhs
        mass = contact.effective_mass
        multiplier = contact.multiplier
        @ordered (
            by = (contact.ordinal, contact.identity),
            state = (
                multipliers => multiplier_initial,
                velocity => velocity_initial,
            ),
        ) begin
            first_velocity = velocity[first]
            second_velocity = velocity[second]
            old_multiplier = multipliers[multiplier]
            relative_normal_velocity = _pgs3_dot(
                _pgs3_sub(second_velocity, first_velocity), normal)
            new_multiplier = max(0.0f0,
                old_multiplier + mass * (visit_rhs - relative_normal_velocity))
            impulse = new_multiplier - old_multiplier
            first_updated = _pgs3_axpy(
                first_velocity, -inverse_first * impulse, normal)
            second_updated = _pgs3_axpy(
                second_velocity, inverse_second * impulse, normal)
            multipliers[multiplier] = new_multiplier
            velocity[(first, second)] = (first_updated, second_updated)
        end
    end
    contact_storage = StructArrays.StructArray(visits)
    multiplier_storage = array_type(fill(-1.0f0, length(initial_multipliers)))
    velocity_storage = array_type(fill(
        (-99.0f0, -99.0f0, -99.0f0), length(initial_velocities)))
    prepared = LocalMath.@prepare (work; backend) begin
        contact_visit = allocate(contact_storage)
        multiplier_initial = allocate(initial_multipliers)
        multipliers = multiplier_storage
        velocity_initial = allocate(initial_velocities)
        velocity = velocity_storage
    end
    wait(LocalMath.execute!(prepared))
    actual = (
        velocities = Array(velocity_storage),
        multipliers = Array(multiplier_storage),
    )
    all(eachindex(actual.velocities)) do body
        all(1:3) do axis
            isapprox(
                actual.velocities[body][axis],
                reference.velocities[body][axis];
                rtol = 2.0f-6,
                atol = 2.0f-6,
            )
        end
    end || error(
        "3D PGS velocity witness mismatch"
    )
    all(isapprox.(actual.multipliers, reference.multipliers;
        rtol = 2.0f-6, atol = 2.0f-6)) || error(
        "3D PGS multiplier witness mismatch"
    )
    residual = _pgs3d_projected_residual(
        contacts, actual.velocities, actual.multipliers
    )
    residual <= 0.02f0 || error("3D PGS residual did not contract")
    return (
        name = :ordered_pgs_3d,
        result = actual,
        reference,
        snapshot,
        sequential_counterexample = snapshot != reference,
        projected_residual_linf = residual,
        floating_rule = (rtol = 2.0f-6, atol = 2.0f-6),
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_localmath_ordered_pgs_3d_witness()
