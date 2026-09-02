import KernelAbstractions
import LocalMath
import StructArrays

struct _StoichiometricEvent{Z}
    species::NTuple{Z, Int32}
    deltas::NTuple{Z, Int32}
    count::Int32
    compartment::Int32
    ordinal::Int32
    order_key::NTuple{2, Int32}
    identity::UInt32
end

function _stoichiometric_scalar_reference(
        events, initial, species_per_compartment
    )
    inventory = copy(initial)
    dispositions = fill(Int32(0), length(events))
    order = sortperm(eachindex(events); by = index -> (
        events[index].order_key, events[index].identity
    ))
    for index in order
        event = events[index]
        offset = (event.compartment - 1) * species_per_compartment
        feasible = true
        for lane in 1:event.count
            destination = offset + event.species[lane]
            feasible &= inventory[destination] + event.deltas[lane] >= 0
        end
        if feasible
            for lane in 1:event.count
                destination = offset + event.species[lane]
                inventory[destination] += event.deltas[lane]
            end
            dispositions[index] = Int32(1)
        end
    end
    return (; inventory, dispositions)
end

function _stoichiometric_snapshot_counterexample(
        events, initial, species_per_compartment
    )
    dispositions = map(events) do event
        offset = (event.compartment - 1) * species_per_compartment
        all(1:event.count) do lane
            destination = offset + event.species[lane]
            initial[destination] + event.deltas[lane] >= 0
        end
    end
    return count(identity, dispositions)
end

function run_localmath_ordered_stoichiometry_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    species_per_compartment = 3
    group_count = 2
    event(compartment, ordinal, first_species, second_species) =
        _StoichiometricEvent{3}(
            (Int32(first_species), Int32(second_species), Int32(1)),
            (Int32(-1), Int32(1), Int32(0)),
            Int32(2),
            Int32(compartment),
            Int32(ordinal),
            (Int32(compartment), Int32(ordinal)),
            UInt32(100 * compartment + ordinal),
        )
    events = _StoichiometricEvent{3}[
        event(2, 2, 1, 3),
        event(1, 2, 2, 3),
        event(2, 1, 2, 1),
        event(1, 1, 1, 2),
    ]
    initial = Int32[
        1, 0, 0,
        0, 1, 0,
    ]
    reference = _stoichiometric_scalar_reference(
        events, initial, species_per_compartment
    )
    snapshot_accepted = _stoichiometric_snapshot_counterexample(
        events, initial, species_per_compartment
    )
    accepted = count(==(Int32(1)), reference.dispositions)
    snapshot_accepted != accepted || error(
        "stoichiometric witness does not distinguish snapshot admission"
    )

    source = LocalMath.Space(length(events))
    inventory_space = LocalMath.Space(length(initial))
    event_data = LocalMath.Field(source, _StoichiometricEvent{3})
    dispositions_initial = LocalMath.Field(source, Int32)
    dispositions = LocalMath.Field(source, Int32)
    inventory_initial = LocalMath.Field(inventory_space, Int32)
    inventory = LocalMath.Field(inventory_space, Int32)
    work = LocalMath.@localmath event ∈ source begin
            value = event_data[event]
            offset = (value.compartment - Int32(1)) * Int32(3)
            first = offset + value.species[1]
            second = offset + value.species[2]
            first_delta = value.deltas[1]
            second_delta = value.deltas[2]
            @ordered (
                by = (value.order_key, value.identity),
                state = (
                    inventory => inventory_initial,
                    dispositions => dispositions_initial,
                ),
            ) begin
                first_replacement = inventory[first] + first_delta
                second_replacement = inventory[second] + second_delta
                feasible = first_replacement >= Int32(0) &&
                    second_replacement >= Int32(0)
                if feasible
                    inventory[(first, second)] =
                        (first_replacement, second_replacement)
                end
                dispositions[event] = feasible ? Int32(1) : Int32(0)
            end
    end
    event_storage = StructArrays.StructArray(events)
    disposition_storage = array_type(fill(Int32(-1), length(events)))
    inventory_storage = array_type(fill(Int32(-1), length(initial)))
    prepared = LocalMath.@prepare (work; backend) begin
        event_data = allocate(event_storage)
        dispositions_initial = allocate(fill(Int32(0), length(events)))
        dispositions = disposition_storage
        inventory_initial = allocate(initial)
        inventory = inventory_storage
    end
    wait(LocalMath.execute!(prepared))
    actual = (
        inventory = Array(inventory_storage),
        dispositions = Array(disposition_storage),
    )
    actual == reference || error("ordered stoichiometric witness mismatch")
    for compartment in 1:group_count
        range = (compartment - 1) * species_per_compartment .+
            (1:species_per_compartment)
        sum(actual.inventory[range]) == sum(initial[range]) || error(
            "stoichiometric compartment conservation mismatch"
        )
        all(>=(Int32(0)), actual.inventory[range]) || error(
            "stoichiometric nonnegativity mismatch"
        )
    end
    return (
        name = :ordered_stoichiometry,
        result = actual,
        reference,
        accepted_count = accepted,
        snapshot_accepted_count = snapshot_accepted,
        sequential_counterexample = snapshot_accepted != accepted,
        compartment_count = group_count,
        semantics = LocalMath.inspect(work),
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) &&
    run_localmath_ordered_stoichiometry_witness()
