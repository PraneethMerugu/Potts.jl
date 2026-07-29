using Test
using CorePotts
using .TransitionKernelOracle

_oracle_owner(owner::OwnerRef) = is_cell_owner(owner) ?
    oracle_cell(value(cell_id(owner))) : oracle_medium(value(medium_id(owner)))

function _transition_adapter_fixture(boundary::OracleBoundaryKind, moore::Bool)
    dims = (3, 3)
    production_boundary = boundary === OraclePeriodic ? PeriodicBoundary() : ClosedBoundary()
    production_domain = CorePotts.CartesianDomain(dims; boundaries = (
        AxisBoundary(production_boundary), AxisBoundary(production_boundary)))
    raw_offsets = moore ? Tuple(offset for offset in Iterators.product(-1:1, -1:1)
        if any(!iszero, offset)) : ((-1, 0), (1, 0), (0, -1), (0, 1))
    proposal_relation = static_relation(ProposalRole(), raw_offsets; symmetric = true)
    contact_relation = static_relation(ContactRole(), raw_offsets; symmetric = true)

    volume = QuadraticVolumeHamiltonian(number_type = Float64)
    contact = UnorderedContactHamiltonian(Float64[0 2; 2 1],
        MediumTypeTable(MediumID(1) => CellTypeID(1)), contact_relation)
    owners = reshape(OwnerRef[
        CellOwner(1), CellOwner(1), MediumOwner(1),
        MediumOwner(1), CellOwner(1), MediumOwner(1),
        CellOwner(2), CellOwner(2), MediumOwner(1),
    ], dims)
    state = LogicalPottsState(owners, CellCapacity(2);
        cell_types = Dict(CellID(1) => CellTypeID(2), CellID(2) => CellTypeID(2)),
        medium_domains = [MediumID(1)], property_schema = required_properties(volume))
    property_values(state, :target_volume) .= 3.0
    property_values(state, :volume_strength) .= 1.25

    oracle_boundary = ntuple(_ -> boundary, Val(2))
    oracle_domain = OracleDomain(dims; boundaries = oracle_boundary)
    oracle_offsets = Tuple(Tuple(offset) for offset in proposal_relation.offsets)
    oracle_relation = OracleRelation(oracle_offsets)
    medium = oracle_medium(1)
    first_cell = oracle_cell(1)
    second_cell = oracle_cell(2)
    oracle_volume = OracleVolumeEnergy(
        Dict(1 => 3.0, 2 => 3.0), Dict(1 => 1.25, 2 => 1.25))
    oracle_contact = OracleContactEnergy(Float64[0 2; 2 1],
        Dict(medium => 1, first_cell => 2, second_cell => 2), oracle_relation)
    oracle_model = OracleModel(oracle_relation, (oracle_volume, oracle_contact);
        temperature = 0)
    oracle_state = OracleMicrostate(Tuple(_oracle_owner(owner) for owner in vec(owners)))
    return (; production_domain, proposal_relation, volume, contact, state,
        oracle_domain, oracle_relation, oracle_model, oracle_state)
end

@testset "production adapter independent oracle to production adapter" begin
    for boundary in (OraclePeriodic, OracleNoFlux), moore in (false, true)
        fixture = _transition_adapter_fixture(boundary, moore)
        production_before = CorePotts.global_energy(fixture.volume, fixture.state) +
                            CorePotts.global_energy(fixture.contact, fixture.state,
                                fixture.production_domain)
        oracle_before = TransitionKernelOracle.global_energy(
            fixture.oracle_model, fixture.oracle_state, fixture.oracle_domain, BigFloat)
        @test Float64(oracle_before) ≈ production_before

        checked = 0
        for recipient in eachindex(lattice_storage(fixture.state))
            for direction in 1:direction_count(fixture.proposal_relation)
                production_attempt = construct_copy_attempt(fixture.state,
                    fixture.production_domain, fixture.proposal_relation,
                    recipient, direction)
                oracle_proposal = direct_proposal(fixture.oracle_state,
                    fixture.oracle_domain, fixture.oracle_relation,
                    recipient, direction)
                if !is_actionable(production_attempt)
                    @test oracle_proposal === nothing
                    continue
                end
                @test oracle_proposal isa OracleProposal
                production_proposal = actionable_proposal(production_attempt)
                @test oracle_proposal.recipient == production_proposal.recipient
                @test oracle_proposal.donor == production_proposal.donor
                @test oracle_proposal.losing == _oracle_owner(production_proposal.losing)
                @test oracle_proposal.gaining == _oracle_owner(production_proposal.gaining)
                @test oracle_proposal.forward_multiplicity ==
                      production_proposal.forward_multiplicity
                @test oracle_proposal.reverse_multiplicity ==
                      production_proposal.reverse_multiplicity

                oracle_after_state = destination_state(
                    fixture.oracle_state, oracle_proposal)
                production_after_state = logical_state(
                    commit_copy_proposal(fixture.state, production_proposal))
                @test oracle_after_state.owners == Tuple(
                    _oracle_owner(owner) for owner in vec(lattice_storage(production_after_state)))

                oracle_delta = TransitionKernelOracle.global_energy(
                    fixture.oracle_model, oracle_after_state,
                    fixture.oracle_domain, BigFloat) - oracle_before
                production_delta = energy_change(
                    fixture.volume, production_proposal, fixture.state) +
                    energy_change(fixture.contact, production_proposal,
                        fixture.state, fixture.production_domain)
                @test Float64(oracle_delta) ≈ production_delta
                checked += 1
            end
        end
        @test checked > 0
    end
end
