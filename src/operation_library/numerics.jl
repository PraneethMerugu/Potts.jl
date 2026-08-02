# Numerical stage operation admissions owned outside biological mechanisms.

operation_transfer(::typeof(_potts_explicit_field_euler), ::Int) =
    _transfer(
        :explicit_field_euler,
        7,
        :real,
        :declared;
        footprint_rule = NeighborhoodFootprintRule(
            IterationNeighborhoodAnchor()
        ),
        gpu = false,
        allowed_roles = (:process,),
        allowed_phases = (:AfterMCS,),
        required_context = :iteration,
        owner = :PottsToolkitNumerics,
    )
