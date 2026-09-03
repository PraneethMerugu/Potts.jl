# Unit algebra and inference over the normalized expression graph.
function _declared_record_unit(record::QualifiedStatement)
    isempty(record.units) && return :dimensionless
    length(record.units) == 1 || return :unknown
    declared = only(record.units).dimension
    quantities = Any[]
    _collect_quantities!(quantities, _record_arguments(record))
    _collect_quantities!(quantities, _record_options(record))
    for quantity in quantities
        dimension = DynamicQuantities.dimension(quantity)
        string(dimension) == declared || continue
        return _canonical_dimension(dimension)
    end
    # A string-backed atom is conservative: algebra may transform it, but it
    # cannot compare equal to an unrelated dimension merely because its label
    # looks similar.
    return (:declared_dimension, declared)
end

function _normalized_leaf_unit(
        node::NormalizedTermNode,
        source::FrozenSourceGraph,
    )
    payload = node.payload
    value = payload isa Union{LiteralPayload, ParameterBindingPayload} ?
            payload.value : nothing
    if value isa DynamicQuantities.UnionAbstractQuantity
        return _canonical_dimension(DynamicQuantities.dimension(value))
    elseif payload isa ParameterBindingPayload
        default = try
            ModelingToolkitBase.hasdefault(value) ?
                ModelingToolkitBase.getdefault(value) : nothing
        catch
            nothing
        end
        default isa DynamicQuantities.UnionAbstractQuantity && return(
            _canonical_dimension(DynamicQuantities.dimension(default))
        )
        default isa Number && return :dimensionless
        # Required parameters have no default from which to infer a dimension.
        # Runtime parameter normalization deliberately admits only ordinary
        # numbers for those entries, so their compiler-visible unit is
        # dimensionless as well.
        return ModelingToolkitBase.hasdefault(value) ? :unknown : :dimensionless
    elseif payload isa Union{StateBindingPayload, VariableBindingPayload}
        index = findfirst(
            record -> record.identity == payload.identity,
            source.records,
        )
        # A captured binding can be referenced by a semantic statement before
        # it is materialized as an owned state record (for example, during
        # host-only category analysis). Preserve its qualified identity as a
        # unit variable: equal bindings can be proven equal, while the value
        # cannot unify with a concrete or unrelated dimension.
        return index === nothing ? (:binding_dimension, payload.identity) :
               _declared_record_unit(source.records[index])
    elseif payload isa LiteralPayload
        return value isa Number && iszero(value) ?
               :polymorphic_zero : :dimensionless
    elseif node.payload_kind in (
            :proposal_context, :site_anchor, :cell_anchor, :contact_anchor,
            :relationship_context, :relationship_set, :spatial_relation,
            :kind, :relationship_payload, :draw,
        )
        return :dimensionless
    end
    return :unknown
end

function _unit_product(left, right)
    left === :dimensionless && return right
    right === :dimensionless && return left
    _is_polymorphic_zero_unit(left) && return right
    _is_polymorphic_zero_unit(right) && return left
    (_is_unknown_unit(left) || _is_unknown_unit(right)) && return :unknown
    if _is_native_dimension(left) && _is_native_dimension(right)
        return _canonical_dimension(left * right)
    end
    factors = Any[]
    append!(factors, left isa Tuple && first(left) === :product ? left[2:end] : (left,))
    append!(factors, right isa Tuple && first(right) === :product ? right[2:end] : (right,))
    sort!(factors; by = repr)
    return (:product, factors...)
end

function _unit_quotient(numerator, denominator)
    _is_polymorphic_zero_unit(numerator) && return :polymorphic_zero
    denominator === :dimensionless && return numerator
    (_is_unknown_unit(numerator) || _is_unknown_unit(denominator)) && return :unknown
    numerator == denominator && return :dimensionless
    if _is_native_dimension(numerator) && _is_native_dimension(denominator)
        return _canonical_dimension(numerator / denominator)
    end
    return (:quotient, numerator, denominator)
end

function _unit_power(unit, exponent::Rational)
    unit === :dimensionless && return (:dimensionless, nothing)
    _is_polymorphic_zero_unit(unit) && return (:polymorphic_zero, nothing)
    _is_unknown_unit(unit) && return (:unknown, nothing)
    exponent == 0 && return (:dimensionless, nothing)
    exponent == 1 && return (unit, nothing)
    if _is_native_dimension(unit)
        result = try
            unit ^ exponent
        catch error
            return (nothing, "cannot represent dimension exponent $exponent: $(sprint(showerror, error))")
        end
        return (_canonical_dimension(result), nothing)
    end
    return ((:power, unit, exponent), nothing)
end

function _literal_integer_exponent(
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
    )
    length(node.operands) == 2 || return nothing
    payload = graph.nodes[Int(node.operands[2])].payload
    payload isa LiteralPayload || return nothing
    value = payload.value
    value isa Integer && return value
    value isa Rational && denominator(value) == 1 && return Int(numerator(value))
    value isa AbstractFloat && isinteger(value) &&
        abs(value) <= typemax(Int) && return Int(value)
    return nothing
end

function _common_unit(units::Tuple)
    any(_is_unknown_unit, units) && return nothing
    known = filter(
        unit -> !_is_polymorphic_zero_unit(unit),
        units,
    )
    isempty(known) && return :dimensionless
    first_unit = first(known)
    all(unit -> unit == first_unit, known) || return nothing
    return first_unit
end


function _lattice_volume_unit(source::FrozenSourceGraph)
    domains = filter(
        record -> record.kind === :LatticeDomain, source.records
    )
    length(domains) == 1 || return(
        nothing, "lattice-volume units require exactly one lattice domain"
    )
    spacing = get(_record_options(only(domains)), :spacing, nothing)
    spacing isa Tuple && !isempty(spacing) || return(
        nothing, "lattice-volume units require a nonempty spacing tuple"
    )
    unit = :dimensionless
    for value in spacing
        factor = value isa DynamicQuantities.UnionAbstractQuantity ?
                 _canonical_dimension(DynamicQuantities.dimension(value)) :
                 value isa Number ? :dimensionless : :unknown
        _is_unknown_unit(factor) && return(
            nothing, "lattice spacing has an unproven unit"
        )
        unit = _unit_product(unit, factor)
    end
    return (unit, nothing)
end

function _operation_unit_result(
        transfer::OperationTransfer,
        operand_units::Tuple,
        record::QualifiedStatement,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    rule = transfer.unit_rule
    any(_is_unknown_unit, operand_units) && return (
        nothing,
        "cannot prove units for operands $(repr(operand_units))",
    )
    if rule === :dimensionless
        all(unit -> _unit_compatible(unit, :dimensionless), operand_units) ||
            return (
                nothing,
                "requires dimensionless operands, got $(repr(operand_units))",
            )
        return (:dimensionless, nothing)
    elseif rule === :comparison
        common = _common_unit(operand_units)
        common === nothing && return(
            nothing,
            "comparison operands have incompatible units $(repr(operand_units))",
        )
        return (:dimensionless, nothing)
    elseif rule === :branch
        length(operand_units) == 3 || return(
            nothing, "branch unit rule requires three operands"
        )
        _unit_compatible(operand_units[1], :dimensionless) || return(
            nothing, "branch condition must be dimensionless"
        )
        common = _common_unit((operand_units[2], operand_units[3]))
        common === nothing && return(
            nothing,
            "branch values have incompatible units $(repr(operand_units[2:3]))",
        )
        return (common, nothing)
    elseif rule === :unary
        return (isempty(operand_units) ? :unknown : first(operand_units), nothing)
    elseif rule === :square_root
        length(operand_units) == 1 || return(
            nothing, "square-root unit rule requires one operand"
        )
        return _unit_power(first(operand_units), 1 // 2)
    elseif rule === :arithmetic
        identity = transfer.identity
        if identity in (:add, :subtract, :maximum, :minimum)
            common = _common_unit(operand_units)
            common === nothing && return(
                nothing,
                "arithmetic operands have incompatible units $(repr(operand_units))",
            )
            return (common, nothing)
        elseif any(_is_unknown_unit, operand_units)
            return (:unknown, nothing)
        elseif identity === :multiply
            return (foldl(_unit_product, operand_units; init = :dimensionless), nothing)
        elseif identity === :divide
            length(operand_units) == 2 || return (:unknown, nothing)
            return (_unit_quotient(operand_units...), nothing)
        elseif identity === :power
            length(operand_units) == 2 || return (:unknown, nothing)
            _unit_compatible(operand_units[2], :dimensionless) || return(
                nothing, "power exponent must be dimensionless"
            )
            exponent = _literal_integer_exponent(node, graph)
            exponent === nothing && return(
                nothing,
                "power requires a literal integer exponent; use sqrt for square roots",
            )
            operand_units[1] === :dimensionless && return(:dimensionless, nothing)
            return _unit_power(operand_units[1], exponent // 1)
        end
        return (:unknown, nothing)
    elseif rule === :declared
        return (_declared_record_unit(record), nothing)
    elseif rule === :distribution
        parameters = length(operand_units) >= 3 ? operand_units[2:3] : operand_units
        common = _common_unit(parameters)
        common === nothing && return(
            nothing,
            "distribution parameters have incompatible or unproven units " *
            repr(parameters),
        )
        return (common, nothing)
    elseif rule === :lattice_volume
        return _lattice_volume_unit(source)
    end
    return (:unknown, "unsupported unit rule $(repr(rule))")
end

function _validated_operation_unit(
        node::NormalizedTermNode,
        operand_units::Tuple,
        record::QualifiedStatement,
        graph::NormalizedTermGraph,
        source::FrozenSourceGraph,
    )
    transfer = node.transfer
    transfer === nothing && return :unknown
    unit, problem = _operation_unit_result(
        transfer, operand_units, record, node, graph, source
    )
    problem === nothing && return unit
    throw(PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :illegal_operation_units,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "the frozen operation unit-transfer contract",
            problem,
            (),
            record.source,
        ),),
    ))
end

function _hamiltonian_analysis_error(record, error)
    return PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :invalid_hamiltonian_domain,
            record.identity,
            repr(first(record.normalized_payload).expression),
            record.identity.path,
            "a conservative energy expression with a compiler-proven finite affected-anchor plan",
            sprint(showerror, error),
            (),
            record.source,
        ),),
    )
end

function _footprint_analysis_error(record, node, error)
    return PottsValidationError(
        :analysis,
        (PottsDiagnostic(
            :invalid_footprint_transfer,
            record.identity,
            string(node.operation),
            record.identity.path,
            "a closed, compositional, fully resolved footprint fact",
            sprint(showerror, error),
            (),
            record.source,
        ),),
    )
end

