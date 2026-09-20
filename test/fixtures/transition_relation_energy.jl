function _transition_relation_energy_fixture(::Type{T} = Float64) where {T <: AbstractFloat}
    @variables bounded_oracle_signal bounded_oracle_gate
    @parameters bounded_oracle_weight = -1.0
    cell = CellKind(:bounded_oracle_cell; extinction = RetireAtZero())
    medium = MediumKind(:bounded_oracle_medium)
    signal = FieldState(
        bounded_oracle_signal; name = :bounded_oracle_signal, initial = zero(T)
    )
    gate = FieldState(
        bounded_oracle_gate; name = :bounded_oracle_gate, initial = zero(T)
    )
    site = SiteBinding(:bounded_oracle_site)
    proposal = ProposalContext(:bounded_oracle_proposal)
    source = PottsSystem(
        name = :gathered_values_energy_oracle,
        statements = StatementSet((
            Lattice((4, 4); relations = (
                proposal = VonNeumann(), contact = VonNeumann())),
            cell,
            medium,
            signal,
            gate,
            HamiltonianTerm(
                :bounded_ordered_energy;
                domain = sites(:lattice),
                anchor = site,
                expression = bounded_oracle_weight * occupancy(cell, site) *
                    sum(gather(signal, :contact; at = site)),
            ),
            ProposalConstraint(
                :isolate_bounded_oracle_extension,
                proposal.is_extension &
                (field_value(gate, proposal.source_site) == 1) &
                (field_value(gate, proposal.target_site) == 2),
            ),
            Protocol(Sweep(; temperature = zero(T)); name = :main),
        )),
        unknowns = [bounded_oracle_signal, bounded_oracle_gate],
        parameters = [bounded_oracle_weight],
    )
    labels = zeros(Int32, 4, 4)
    labels[2:3, 2:3] .= 1
    source_site = CartesianIndex(2, 2)
    target_site = CartesianIndex(1, 2)
    signal_values = zeros(T, 4, 4)
    signal_values[2, 2] = T(1.0e16)
    signal_values[4, 2] = T(-1.0e16)
    signal_values[1, 3] = one(T)
    gate_values = zeros(T, 4, 4)
    gate_values[source_site] = one(T)
    gate_values[target_site] = T(2)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            bounded_oracle_signal => signal_values,
            bounded_oracle_gate => gate_values,
        ),
    )
    after_extension = copy(labels)
    after_extension[target_site] = 1
    return (;
        scheduled = mtkcompile(source), initial, labels, after_extension,
        signal_values, weight = bounded_oracle_weight,
    )
end

function _ordered_relation_neighbor_sum(values, center)
    total = zero(eltype(values))
    for offset in ((1, 0), (-1, 0), (0, 1), (0, -1))
        neighbor = CartesianIndex(
            mod1(center[1] + offset[1], size(values, 1)),
            mod1(center[2] + offset[2], size(values, 2)),
        )
        total = total + values[neighbor]
    end
    return total
end

function _independent_transition_relation_energy_delta(
        before, after, values, weight
    )
    T = promote_type(eltype(values), typeof(weight))
    total = zero(T)
    for center in CartesianIndices(before)
        local_energy = weight * _ordered_relation_neighbor_sum(values, center)
        total += (after[center] == 1 ? local_energy : zero(T)) -
                 (before[center] == 1 ? local_energy : zero(T))
    end
    return total
end

function _solve_transition_relation_energy(
        fixture, algorithm, backend, weight, seed
    )
    T = eltype(fixture.signal_values)
    return solve(
        PottsProblem(
            fixture.scheduled,
            fixture.initial,
            (0, 1);
            p = (fixture.weight => weight,),
            seed,
        ),
        algorithm;
        backend,
        scalar_type = T,
        save_everystep = true,
    )
end

function _transition_relation_energy_witness(
        fixture, algorithm, backend; seeds = UInt64(1):UInt64(256)
    )
    T = eltype(fixture.signal_values)
    for seed in seeds
        favorable = _solve_transition_relation_energy(
            fixture, algorithm, backend, -one(T), seed
        )
        last(favorable).ownership == fixture.after_extension || continue
        unfavorable = _solve_transition_relation_energy(
            fixture, algorithm, backend, one(T), seed
        )
        unfavorable.stats.energy_rejections > 0 || continue
        return (; seed, favorable, unfavorable)
    end
    return nothing
end
