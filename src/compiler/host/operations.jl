# Versioned authority for symbolic operations admitted to the normalized DAG.

struct OperationTransfer
    identity::Symbol
    schema_version::VersionNumber
    serialization_identity::String
    arity::UnitRange{Int}
    result_rule::Symbol
    unit_rule::Symbol
    purity::Symbol
    totality::Symbol
    locality::Symbol
    cpu::Bool
    gpu::Bool
end

OperationTransfer(
    identity::Symbol,
    schema_version::VersionNumber,
    arity::UnitRange{Int},
    result_rule::Symbol,
    unit_rule::Symbol,
    purity::Symbol,
    totality::Symbol,
    locality::Symbol,
    cpu::Bool,
    gpu::Bool,
) = OperationTransfer(
    identity,
    schema_version,
    "potts-operation:" * String(identity) * ":" * string(schema_version),
    arity,
    result_rule,
    unit_rule,
    purity,
    totality,
    locality,
    cpu,
    gpu,
)

function operation_transfer end

_transfer(identity, arity, result_rule, unit_rule;
        version = v"1.0.0",
        serialization_identity = "potts-operation:" * String(identity) * ":v1",
        purity = :pure,
        totality = :total,
        locality = :scalar,
        cpu = true,
        gpu = true,
    ) = OperationTransfer(
        identity,
        version,
        String(serialization_identity),
        arity isa Integer ? (Int(arity):Int(arity)) : arity,
        result_rule,
        unit_rule,
        purity,
        totality,
        locality,
        cpu,
        gpu,
    )

for operation in (+, -, *, /, ^, max, min)
    identity = if operation === (+)
        :add
    elseif operation === (-)
        :subtract
    elseif operation === (*)
        :multiply
    elseif operation === (/)
        :divide
    elseif operation === (^)
        :power
    elseif operation === max
        :maximum
    else
        :minimum
    end
    @eval operation_transfer(::typeof($operation), arity::Int) =
        _transfer($(QuoteNode(identity)), arity == 1 ? 1 : (2:typemax(Int)),
            :promote_numeric, :arithmetic)
end

for operation in (<, <=, >, >=, ==, !=)
    identity = if operation === (<)
        :less
    elseif operation === (<=)
        :less_equal
    elseif operation === (>)
        :greater
    elseif operation === (>=)
        :greater_equal
    elseif operation === (==)
        :equal
    else
        :not_equal
    end
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer($(QuoteNode(identity)), 2, :boolean, :comparison)
end

operation_transfer(::typeof(&), ::Int) =
    _transfer(:and, 2, :boolean, :dimensionless)
operation_transfer(::typeof(|), ::Int) =
    _transfer(:or, 2, :boolean, :dimensionless)
operation_transfer(::typeof(!), ::Int) =
    _transfer(:not, 1, :boolean, :dimensionless)
operation_transfer(::typeof(ifelse), ::Int) =
    _transfer(:ifelse, 3, :branch_promote, :branch)

for operation in (abs, exp, log, sqrt)
    identity = if operation === abs
        :absolute
    elseif operation === exp
        :exponential
    elseif operation === log
        :logarithm
    else
        :square_root
    end
    unit_rule = operation in (exp, log) ? :dimensionless : :unary
    totality = operation in (log, sqrt) ? :domain_checked : :total
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)),
            1,
            :preserve_numeric,
            $(QuoteNode(unit_rule));
            totality = $(QuoteNode(totality)),
        )
end

for operation in (
        source_site, target_site, source_cell, target_cell, source_kind,
        target_kind,
    )
    identity = nameof(operation)
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, :integer, :dimensionless;
            locality = :proposal_context,
        )
end

for operation in (is_extension, is_retraction, new_contact, lost_contact, linked)
    identity = nameof(operation)
    arity = operation === linked ? 3 : operation in (new_contact, lost_contact) ? 2 : 1
    locality = operation === linked ? :bounded_relationship : :proposal_context
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), $arity, :boolean, :dimensionless;
            locality = $(QuoteNode(locality)),
        )
end

operation_transfer(::typeof(_potts_merks_local_connectivity), ::Int) =
    _transfer(
        :merks_local_connectivity,
        3,
        :boolean,
        :dimensionless;
        locality = :finite_spatial,
    )

operation_transfer(::typeof(_potts_act_energy), ::Int) =
    _transfer(
        :act_energy,
        5,
        :real,
        :declared;
        locality = :finite_spatial,
        gpu = false,
    )

for operation in (
        cell_volume, cell_surface, cell_elongation, cell_center, unwrapped_center, endpoint_a,
        endpoint_b,
    )
    identity = nameof(operation)
    result_rule = operation in (endpoint_a, endpoint_b) ? :integer : :real
    locality = operation in (endpoint_a, endpoint_b) ?
               :bounded_relationship : :owner_local
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, $(QuoteNode(result_rule)), :declared;
            locality = $(QuoteNode(locality)),
        )
end

operation_transfer(::typeof(degree), ::Int) =
    _transfer(
        :degree, 2, :integer, :declared;
        locality = :bounded_relationship,
    )

for operation in (
        contact_owner_a, contact_owner_b, contact_kind_a, contact_kind_b,
    )
    identity = nameof(operation)
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, :integer, :dimensionless;
            locality = :contact_local,
        )
end

operation_transfer(::typeof(occupancy), ::Int) =
    _transfer(
        :occupancy, 2, :real, :declared;
        locality = :site_local,
    )

for operation in (
        distance, contact_measure, boundary_measure, neighbor_count, neighbor_sum,
        neighbor_mean, neighbor_geomean, field_value, field_gradient, laplacian,
        history_value, edge_payload, lag,
    )
    identity = nameof(operation)
    result_rule = operation === neighbor_count ? :integer : :real
    locality = operation in (edge_payload, lag) ?
               :bounded_relationship : :finite_spatial
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 2, $(QuoteNode(result_rule)), :declared;
            locality = $(QuoteNode(locality)),
        )
end

operation_transfer(::typeof(_potts_draw), ::Int) =
    _transfer(
        :draw, 4, :real, :distribution;
        purity = :semantic_rng,
        totality = :requires_prelaunch_validation,
        locality = :proposal_context,
    )
