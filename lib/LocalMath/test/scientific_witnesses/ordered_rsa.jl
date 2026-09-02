import KernelAbstractions
import LocalMath
import StructArrays

struct _RSA2DAttempt
    sites::NTuple{2, Int32}
    label::Int32
    ordinal::Int32
    identity::UInt32
end

function _rsa2d_scalar_reference(attempts, initial)
    occupancy = copy(initial)
    accepted = fill(Int32(0), length(attempts))
    order = sortperm(eachindex(attempts); by = index -> (
        attempts[index].ordinal, attempts[index].identity
    ))
    for index in order
        attempt = attempts[index]
        first_site, second_site = attempt.sites
        if occupancy[first_site] == 0 && occupancy[second_site] == 0
            occupancy[first_site] = attempt.label
            occupancy[second_site] = attempt.label
            accepted[index] = Int32(1)
        end
    end
    return (; occupancy, accepted)
end

function _rsa2d_snapshot_counterexample(attempts, initial)
    accepted = map(attempts) do attempt
        first_site, second_site = attempt.sites
        initial[first_site] == 0 && initial[second_site] == 0
    end
    return count(identity, accepted)
end

function run_localmath_ordered_rsa_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    attempts = _RSA2DAttempt[
        _RSA2DAttempt((Int32(4), Int32(5)), Int32(3), Int32(3), UInt32(30)),
        _RSA2DAttempt((Int32(1), Int32(2)), Int32(1), Int32(1), UInt32(10)),
        _RSA2DAttempt((Int32(5), Int32(6)), Int32(4), Int32(4), UInt32(40)),
        _RSA2DAttempt((Int32(2), Int32(3)), Int32(2), Int32(2), UInt32(20)),
        _RSA2DAttempt((Int32(3), Int32(6)), Int32(5), Int32(5), UInt32(50)),
    ]
    initial = fill(Int32(0), 9)
    reference = _rsa2d_scalar_reference(attempts, initial)
    snapshot_accepted = _rsa2d_snapshot_counterexample(attempts, initial)
    snapshot_accepted != count(==(Int32(1)), reference.accepted) || error(
        "RSA witness does not distinguish snapshot from sequential admission"
    )

    source = LocalMath.Space(length(attempts))
    occupancy_space = LocalMath.Space(length(initial))
    attempt_data = LocalMath.Field(source, _RSA2DAttempt)
    accepted_initial = LocalMath.Field(source, Int32)
    accepted = LocalMath.Field(source, Int32)
    occupancy_initial = LocalMath.Field(occupancy_space, Int32)
    occupancy = LocalMath.Field(occupancy_space, Int32)
    work = LocalMath.@localmath attempt ∈ source begin
        value = attempt_data[attempt]
        first = value.sites[1]
        second = value.sites[2]
        deposited_label = value.label
        @ordered (
            by = (value.ordinal, value.identity),
            state = (
                occupancy => occupancy_initial,
                accepted => accepted_initial,
            ),
        ) begin
            admitted = occupancy[first] == Int32(0) &&
                occupancy[second] == Int32(0)
            if admitted
                occupancy[(first, second)] =
                    (deposited_label, deposited_label)
            end
            accepted[attempt] = admitted ? Int32(1) : Int32(0)
        end
    end
    attempt_storage = StructArrays.StructArray(attempts)
    accepted_storage = array_type(fill(Int32(-1), length(attempts)))
    occupancy_storage = array_type(fill(Int32(-1), length(initial)))
    prepared = LocalMath.@prepare (work; backend) begin
        attempt_data = allocate(attempt_storage)
        accepted_initial = allocate(fill(Int32(0), length(attempts)))
        accepted = accepted_storage
        occupancy_initial = allocate(initial)
        occupancy = occupancy_storage
    end
    wait(LocalMath.execute!(prepared))
    actual = (
        occupancy = Array(occupancy_storage),
        accepted = Array(accepted_storage),
    )
    actual == reference || error("2D ordered RSA witness mismatch")
    return (
        name = :ordered_rsa_2d,
        result = actual,
        reference,
        accepted_count = count(==(Int32(1)), actual.accepted),
        snapshot_accepted_count = snapshot_accepted,
        sequential_counterexample =
            snapshot_accepted != count(==(Int32(1)), actual.accepted),
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_localmath_ordered_rsa_witness()
