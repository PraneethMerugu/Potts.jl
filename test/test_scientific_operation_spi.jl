import LocalMath

struct ScientificProposalProbe <: CorePotts.CompilerSPI.AbstractProposalEvaluationContext
    ownership::Matrix{Int32}
    cell_kinds::Vector{Int16}
    state::Matrix{Float64}
    source::CartesianIndex{2}
    target::CartesianIndex{2}
    relations::Tuple{Tuple{Vararg{NTuple{2, Int}}}, Vararg}
    state_reads::Base.RefValue{Int}
end

CorePotts.CompilerSPI.proposal_source_site(context::ScientificProposalProbe) =
    context.source
CorePotts.CompilerSPI.proposal_target_site(context::ScientificProposalProbe) =
    context.target
CorePotts.CompilerSPI.proposal_source_owner(context::ScientificProposalProbe) =
    context.ownership[context.source]
CorePotts.CompilerSPI.proposal_target_owner(context::ScientificProposalProbe) =
    context.ownership[context.target]
function CorePotts.CompilerSPI.proposal_source_kind(
        context::ScientificProposalProbe
    )
    owner = CorePotts.CompilerSPI.proposal_source_owner(context)
    return owner > 0 ? context.cell_kinds[Int(owner)] : Int16(1)
end
function CorePotts.CompilerSPI.proposal_target_kind(
        context::ScientificProposalProbe
    )
    owner = CorePotts.CompilerSPI.proposal_target_owner(context)
    return owner > 0 ? context.cell_kinds[Int(owner)] : Int16(1)
end
CorePotts.CompilerSPI.proposal_site_owner(
    context::ScientificProposalProbe, site
) = context.ownership[site]
CorePotts.CompilerSPI.proposal_relation_count(
    context::ScientificProposalProbe, relation::Int32
) = length(context.relations[Int(relation)])
function CorePotts.CompilerSPI.proposal_relation_neighbor_site(
        context::ScientificProposalProbe,
        relation::Int32,
        center::CartesianIndex{2},
        direction::Integer,
    )
    offset = context.relations[Int(relation)][Int(direction)]
    neighbor = center + CartesianIndex(offset)
    return checkbounds(Bool, context.ownership, neighbor) ? neighbor : nothing
end
function CorePotts.CompilerSPI.proposal_relation_neighbor_owner(
        context::ScientificProposalProbe,
        relation::Int32,
        offset::NTuple{2, Int},
    )
    offset in context.relations[Int(relation)] || return typemin(Int32)
    neighbor = context.target + CartesianIndex(offset)
    return checkbounds(Bool, context.ownership, neighbor) ?
        context.ownership[neighbor] : typemin(Int32)
end
function CorePotts.CompilerSPI.state_value(
        context::ScientificProposalProbe, handle, site
    )
    handle === :activity || throw(ArgumentError("unexpected state handle"))
    context.state_reads[] += 1
    return context.state[site]
end

const SCIENTIFIC_MOORE_OFFSETS = Tuple(
    (row, column)
    for row in -1:1 for column in -1:1
    if (row, column) != (0, 0)
)
const SCIENTIFIC_VON_NEUMANN_OFFSETS =
    ((-1, 0), (0, -1), (0, 1), (1, 0))

function independent_local_geomean(context, center, owner)
    owner <= 0 && return 0.0
    values = Float64[]
    context.ownership[center] == owner && push!(values, context.state[center])
    for offset in SCIENTIFIC_MOORE_OFFSETS
        neighbor = center + CartesianIndex(offset)
        checkbounds(Bool, context.ownership, neighbor) || continue
        context.ownership[neighbor] == owner || continue
        push!(values, context.state[neighbor])
    end
    isempty(values) && return 0.0
    return exp(sum(log1p(max(0.0, value)) for value in values) /
               length(values)) - 1.0
end

@testset "Act operation matches an independent bounded-neighborhood oracle" begin
    operation = CorePotts.CompilerSPI.operation_callable(
        Val(:act_energy), v"1.0.0"
    )
    for shape in ((7, 7), (71, 71))
        ownership = zeros(Int32, shape)
        center = CartesianIndex(cld(shape[1], 2), cld(shape[2], 2))
        source = center + CartesianIndex(0, -1)
        target = center
        ownership[source] = 1
        ownership[source + CartesianIndex(-1, 0)] = 1
        ownership[source + CartesianIndex(1, 0)] = 1
        state = zeros(Float64, shape)
        state[source] = 3.0
        state[source + CartesianIndex(-1, 0)] = 8.0
        state[source + CartesianIndex(1, 0)] = 15.0
        reads = Ref(0)
        context = ScientificProposalProbe(
            ownership,
            Int16[2],
            state,
            source,
            target,
            (SCIENTIFIC_MOORE_OFFSETS, SCIENTIFIC_VON_NEUMANN_OFFSETS),
            reads,
        )
        maximum = 20.0
        strength = 5.0
        expected = -(strength / maximum) * (
            independent_local_geomean(context, source, Int32(1)) - 0.0
        )
        observed = operation(
            (Int16(2), :activity, Int32(1), maximum, strength), context
        )
        @test observed ≈ expected
        @test reads[] == 3
        @test CorePotts.CompilerSPI.operation_context_supported(
            operation, typeof(context)
        )
    end

    ownership = zeros(Int32, 7, 7)
    ownership[4, 3] = 1
    ownership[4, 4] = 2
    state = zeros(Float64, 7, 7)
    state[4, 3] = 8.0
    state[4, 4] = 3.0
    context = ScientificProposalProbe(
        ownership,
        Int16[2, 2],
        state,
        CartesianIndex(4, 3),
        CartesianIndex(4, 4),
        (SCIENTIFIC_MOORE_OFFSETS, SCIENTIFIC_VON_NEUMANN_OFFSETS),
        Ref(0),
    )
    expected = -(5.0 / 20.0) * (
        independent_local_geomean(context, context.source, Int32(1)) -
        independent_local_geomean(context, context.target, Int32(2))
    )
    @test operation(
        (Int16(2), :activity, Int32(1), 20.0, 5.0), context
    ) ≈ expected
    @test operation(
        (Int16(9), :activity, Int32(1), 20.0, 5.0), context
    ) == 0.0
end

@testset "Merks connectivity matches the independent clockwise truth table" begin
    operation = CorePotts.CompilerSPI.operation_callable(
        Val(:merks_local_connectivity), v"1.0.0"
    )
    clockwise = (
        (-1, -1), (0, -1), (1, -1), (1, 0),
        (1, 1), (0, 1), (-1, 1), (-1, 0),
    )
    cases = (
        ((1, 1, 1, 0, 0, 0, 0, 0), true),
        ((1, 0, 1, 0, 0, 0, 0, 0), false),
        ((1, 0, 1, 0, 2, 0, 0, 0), true),
        ((1, 0, 1, 0, 2, 0, 3, 0), false),
        ((0, 0, 0, 0, 0, 0, 0, 0), true),
    )
    for (owners, expected) in cases
        ownership = zeros(Int32, 7, 7)
        target = CartesianIndex(4, 4)
        ownership[target] = 1
        for (offset, owner) in zip(clockwise, owners)
            ownership[target + CartesianIndex(offset)] = owner
        end
        context = ScientificProposalProbe(
            ownership,
            Int16[2, 2, 2],
            zeros(Float64, 7, 7),
            CartesianIndex(4, 3),
            target,
            (clockwise, SCIENTIFIC_VON_NEUMANN_OFFSETS),
            Ref(0),
        )
        @test operation((Int16(2), Int32(1), Int32(2)), context) == expected
    end
end

@testset "relation gather matches an independent ordered energy oracle" begin
    @variables bounded_oracle_signal bounded_oracle_gate
    @parameters bounded_oracle_weight = -1.0
    cell = CellKind(:bounded_oracle_cell; extinction = RetireAtZero())
    medium = MediumKind(:bounded_oracle_medium)
    signal = FieldState(
        bounded_oracle_signal; name = :bounded_oracle_signal, initial = 0.0
    )
    gate = FieldState(
        bounded_oracle_gate; name = :bounded_oracle_gate, initial = 0.0
    )
    site = SiteBinding(:bounded_oracle_site)
    proposal = ProposalContext(:bounded_oracle_proposal)
    canonical_sum = LocalMath.bounded_fold(
        identity,
        +,
        0.0,
        (total, count) -> total;
        domain = LocalMath.Where(isfinite),
        oninvalid = LocalMath.RejectInvalid(),
        onempty = LocalMath.RejectEmpty(),
        order = LocalMath.CanonicalLeftFold(),
    )
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
                    canonical_sum(gather(
                        signal, :contact; at = anchor_value(site))),
            ),
            ProposalConstraint(
                :isolate_bounded_oracle_extension,
                proposal.is_extension &
                (field_value(gate, proposal.source_site) == 1) &
                (field_value(gate, proposal.target_site) == 2),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [bounded_oracle_signal, bounded_oracle_gate],
        parameters = [bounded_oracle_weight],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 4, 4)
    labels[2:3, 2:3] .= 1
    source_site = CartesianIndex(2, 2)
    target_site = CartesianIndex(1, 2)
    signal_values = zeros(Float64, 4, 4)
    signal_values[2, 2] = 1.0e16
    signal_values[4, 2] = -1.0e16
    signal_values[1, 3] = 1.0
    gate_values = zeros(Float64, 4, 4)
    gate_values[source_site] = 1
    gate_values[target_site] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            bounded_oracle_signal => signal_values,
            bounded_oracle_gate => gate_values,
        ),
    )

    # Independent full-energy definition. Von Neumann lanes use the declared
    # dimension/distance/sign order and are folded left without reassociation.
    offsets = ((1, 0), (-1, 0), (0, 1), (0, -1))
    function ordered_neighbor_sum(values, center)
        total = 0.0
        for offset in offsets
            neighbor = CartesianIndex(
                mod1(center[1] + offset[1], size(values, 1)),
                mod1(center[2] + offset[2], size(values, 2)),
            )
            total = total + values[neighbor]
        end
        return total
    end
    function global_bounded_delta(before, after, values, weight)
        total = 0.0
        for center in CartesianIndices(before)
            local_energy = weight * ordered_neighbor_sum(values, center)
            total += (after[center] == 1 ? local_energy : 0.0) -
                     (before[center] == 1 ? local_energy : 0.0)
        end
        return total
    end
    after_extension = copy(labels)
    after_extension[target_site] = 1
    favorable_delta = global_bounded_delta(
        labels, after_extension, signal_values, -1.0)
    unfavorable_delta = global_bounded_delta(
        labels, after_extension, signal_values, 1.0)
    @test ordered_neighbor_sum(signal_values, target_site) == 1.0
    @test favorable_delta == -1.0
    @test unfavorable_delta == 1.0

    run(weight, seed) = solve(
        PottsProblem(
            scheduled,
            initial,
            (0, 1);
            p = (bounded_oracle_weight => weight,),
            seed,
        ),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    witness = nothing
    for seed in UInt64(1):UInt64(256)
        favorable = run(-1.0, seed)
        last(favorable).ownership == after_extension || continue
        unfavorable = run(1.0, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no relation-gather proposal witness found")
    @test witness.favorable.stats.accepted == 1
    @test last(witness.unfavorable).ownership == labels
    @test witness.unfavorable.stats.accepted == 0
end

_tracker_lane_digits(accumulator, value) =
    Int32(10) * accumulator + value
_tracker_lane_digits_finish(accumulator, count) = accumulator

@testset "tracker gathers preserve bounded relation-lane semantics" begin
    @variables tracker_gather_gate
    cell = CellKind(:tracker_gather_cell; extinction = RetireAtZero())
    medium = MediumKind(:tracker_gather_medium)
    gate = FieldState(
        tracker_gather_gate; name = :tracker_gather_gate, initial = 0.0)
    proposal = ProposalContext(:tracker_gather_proposal)
    lane_digits = LocalMath.bounded_fold(
        identity,
        _tracker_lane_digits,
        Int32(0),
        _tracker_lane_digits_finish;
        domain = LocalMath.Where(>=(Int32(0))),
        oninvalid = LocalMath.RejectInvalid(),
        onempty = LocalMath.RejectEmpty(),
        order = LocalMath.CanonicalLeftFold(),
    )
    source = PottsSystem(
        name = :tracker_gather_oracle,
        statements = StatementSet((
            Lattice(
                (3, 3);
                boundary = Closed(),
                relations = (
                    proposal = VonNeumann(), contact = VonNeumann()),
            ),
            cell,
            medium,
            gate,
            ProposalConstraint(
                :one_tracker_gather_extension,
                proposal.is_extension &
                (field_value(gate, proposal.source_site) == 1) &
                (field_value(gate, proposal.target_site) == 2) &
                (lane_digits(gather(
                    cell_volume, :contact; at = proposal.target_site)) == 22),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [tracker_gather_gate],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 3, 3)
    source_site = CartesianIndex(2, 2)
    repeated_owner_site = CartesianIndex(1, 3)
    target_site = CartesianIndex(1, 2)
    labels[source_site] = 1
    labels[repeated_owner_site] = 1
    gate_values = zeros(Float64, 3, 3)
    gate_values[source_site] = 1
    gate_values[target_site] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (tracker_gather_gate => gate_values,),
    )
    expected = copy(labels)
    expected[target_site] = 1

    # Independent relation oracle. Von Neumann lanes are (+x, -x, +y, -y):
    # volume two, absent boundary, the same volume two again, then medium.
    # Only the two finite-owner lanes participate, in canonical lane order.
    expected_digits = foldl(_tracker_lane_digits, Int32[2, 2]; init = Int32(0))
    @test expected_digits == 22

    function witness(algorithm)
        for seed in UInt64(1):UInt64(512)
            solution = solve(
                PottsProblem(scheduled, initial, (0, 1); seed),
                algorithm;
                backend = CPUBackend(), scalar_type = Float64,
                save_everystep = true,
            )
            last(solution).ownership == expected && return solution
        end
        return nothing
    end
    sequential = witness(SequentialCPM())
    checkerboard = witness(CheckerboardSweepCPM())
    @test sequential !== nothing
    @test checkerboard !== nothing
    sequential === nothing || (@test sequential.stats.accepted == 1)
    checkerboard === nothing || (@test checkerboard.stats.accepted == 1)
end

@testset "composed local Hamiltonian matches an independent global-energy sign oracle" begin
    @variables local_oracle_gate
    @parameters local_oracle_site_weight = 0.0
    cell = CellKind(:local_oracle_cell; extinction = RetireAtZero())
    medium = MediumKind(:local_oracle_medium)
    gate = FieldState(
        local_oracle_gate; name = :local_oracle_gate, initial = 0.0
    )
    site = SiteBinding(:local_oracle_site)
    copy_context = ProposalContext(:local_oracle_copy)
    source = PottsSystem(
        name = :composed_local_hamiltonian_oracle,
        statements = StatementSet((
            Lattice(
                (4, 4);
                relations = (proposal = VonNeumann(), contact = Moore()),
            ),
            cell,
            medium,
            gate,
            Volume(cell; target = 4.0, strength = 2.0),
            ContactEnergy([(cell ↔ medium) => 3.0]),
            HamiltonianTerm(
                :site_energy_with_offset;
                domain = sites(:lattice),
                anchor = site,
                expression =
                    local_oracle_site_weight * occupancy(cell, site) + 99.0,
            ),
            ProposalConstraint(
                :isolate_local_oracle_extension,
                copy_context.is_extension &
                (field_value(
                    local_oracle_gate, copy_context.source_site
                ) == 1) &
                (field_value(
                    local_oracle_gate, copy_context.target_site
                ) == 2),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [local_oracle_gate],
        parameters = [local_oracle_site_weight],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 4, 4)
    labels[2:3, 2:3] .= 1
    source_site = CartesianIndex(2, 2)
    target_site = CartesianIndex(1, 2)
    gate_values = zeros(Float64, 4, 4)
    gate_values[source_site] = 1
    gate_values[target_site] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (local_oracle_gate => gate_values,),
    )

    # Deliberately independent full-energy oracle: no production evaluator,
    # affected-anchor proof, or delta routine is reused here.
    moore_offsets = Tuple(
        (row, column)
        for row in -1:1 for column in -1:1
        if (row, column) != (0, 0)
    )
    function global_energy(ownership, site_weight)
        volume = count(==(Int32(1)), ownership)
        energy = 2.0 * (volume - 4.0)^2
        energy += site_weight * volume + 99.0 * length(ownership)
        contacts_seen = Set{Tuple{Int, Int}}()
        linear = LinearIndices(ownership)
        for center in CartesianIndices(ownership)
            for offset in moore_offsets
                neighbor = CartesianIndex(
                    mod1(center[1] + offset[1], size(ownership, 1)),
                    mod1(center[2] + offset[2], size(ownership, 2)),
                )
                edge = minmax(linear[center], linear[neighbor])
                edge in contacts_seen && continue
                push!(contacts_seen, edge)
                ownership[center] == ownership[neighbor] || (energy += 3.0)
            end
        end
        return energy
    end
    after_extension = copy(labels)
    after_extension[target_site] = labels[source_site]
    favorable_delta = global_energy(after_extension, -15.0) -
                       global_energy(labels, -15.0)
    unfavorable_delta = global_energy(after_extension, -13.0) -
                         global_energy(labels, -13.0)
    @test favorable_delta == -1.0
    @test unfavorable_delta == 1.0

    run(site_weight, seed) = solve(
        PottsProblem(
            scheduled,
            initial,
            (0, 1);
            p = (local_oracle_site_weight => site_weight,),
            seed,
        ),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    witness = nothing
    for seed in UInt64(1):UInt64(256)
        favorable = run(-15.0, seed)
        favorable.stats.accepted == 1 || continue
        unfavorable = run(-13.0, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no composed local-Hamiltonian witness found")
    @test last(witness.favorable).ownership == after_extension
    @test last(witness.unfavorable).ownership == labels
    @test witness.unfavorable.stats.accepted == 0
end
