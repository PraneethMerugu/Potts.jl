# Scientific operation admissions owned outside the generic host compiler.

operation_transfer(::typeof(_potts_merks_local_connectivity), ::Int) =
    _transfer(
        :merks_local_connectivity,
        3,
        :boolean,
        :dimensionless;
        footprint_rule = NeighborhoodFootprintRule(
            ProposalTargetNeighborhoodAnchor()
        ),
        allowed_roles = (:constraint,),
        allowed_phases = (:Proposal,),
        required_context = :proposal,
        owner = :PottsToolkitScientificOperations,
    )

operation_transfer(::typeof(_potts_act_energy), ::Int) =
    _transfer(
        :act_energy,
        5,
        :real,
        :declared;
        footprint_rule = NeighborhoodFootprintRule(
            ProposalSourceTargetNeighborhoodAnchor()
        ),
        gpu = false,
        allowed_roles = (:drive,),
        allowed_phases = (:Proposal,),
        required_context = :proposal,
        owner = :PottsToolkitScientificOperations,
    )
