# Lower analyzed facts into the mechanism-free CorePotts program.

_statement_option(statement, name::Symbol, default = nothing) =
    haskey(_statement_options(statement), name) ?
    getproperty(_statement_options(statement), name) : default

function _all_system_statements(
        system::PottsSystem, namespace::Tuple = ()
    )
    result = AbstractPottsStatement[]
    append!(
        result,
        (
            _namespace_statement_for_lowering(statement, namespace)
            for statement in statements(system)
        ),
    )
    for child in getfield(system, :systems)
        append!(
            result,
            _all_system_statements(
                child, (namespace..., nameof(child))
            ),
        )
    end
    return result
end

function _kind_name(kind::Union{CellKind, MediumKind})
    return Symbol(statement_id(kind))
end

function _neighborhood_offsets(neighborhood::VonNeumann, dimensions::Int)
    radius = neighborhood.radius
    offsets = NTuple{dimensions, Int}[]
    for dimension in 1:dimensions, distance in 1:radius
        push!(offsets, ntuple(i -> i == dimension ? distance : 0, dimensions))
        push!(offsets, ntuple(i -> i == dimension ? -distance : 0, dimensions))
    end
    return _offset_matrix(offsets, dimensions)
end

function _neighborhood_offsets(neighborhood::Moore, dimensions::Int)
    radius = neighborhood.radius
    ranges = ntuple(_ -> (-radius):radius, dimensions)
    offsets = NTuple{dimensions, Int}[]
    for candidate in Iterators.product(ranges...)
        all(iszero, candidate) && continue
        push!(offsets, Tuple(candidate))
    end
    sort!(offsets)
    return _offset_matrix(offsets, dimensions)
end

function _offset_matrix(offsets, dimensions)
    isempty(offsets) &&
        throw(ArgumentError("a spatial relation requires at least one offset"))
    result = Matrix{Int8}(undef, dimensions, length(offsets))
    for (column, offset) in enumerate(offsets), dimension in 1:dimensions
        typemin(Int8) <= offset[dimension] <= typemax(Int8) ||
            throw(ArgumentError("V1 relation radius exceeds Int8 storage"))
        result[dimension, column] = Int8(offset[dimension])
    end
    return result
end

function _relation_offsets(statements, name::Symbol, dimensions::Int, fallback)
    relation = findfirst(statement ->
        statement isa SpatialRelation &&
        Symbol(statement_id(statement)) === name, statements)
    relation === nothing && return _neighborhood_offsets(fallback, dimensions)
    neighborhood = _statement_option(statements[relation], :neighborhood)
    neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
        "relation `$name` must use VonNeumann or Moore in V1"
    ))
    return _neighborhood_offsets(neighborhood, dimensions)
end

function _lower_activity(statements, kinds, manifest, ::Type{T}, dimensions) where {
        T <: AbstractFloat,
    }
    term = findfirst(statement ->
        statement isa ProposalDrive &&
        _statement_option(statement, :mechanism) === :activity, statements)
    term === nothing && return nothing
    statement = statements[term]
    kind = kinds[_kind_name(_statement_option(statement, :kind))]
    reduction = _statement_option(statement, :reduction, Moore())
    offsets = _neighborhood_offsets(reduction, dimensions)
    maximum = _compiled_scalar(_statement_option(statement, :maximum), manifest, T)
    strength = _compiled_scalar(_statement_option(statement, :strength), manifest, T)
    activity_state = _statement_option(statement, :activity)
    activate_extensions = any(statements) do candidate
        candidate isa AcceptedCopyProcess || return false
        arguments = _statement_arguments(candidate)
        any(arguments.effects) do effect
            effect isa Assign && isequal(effect.target, activity_state)
        end
    end
    decay = one(T)
    for candidate in statements
        candidate isa SynchronousProcess || continue
        arguments = _statement_arguments(candidate)
        any(effect -> effect isa Assign && isequal(effect.target, activity_state),
            arguments.effects) || continue
        decay = T(_numeric_value(_statement_option(candidate, :decay, one(T))))
    end
    return CorePotts.CompiledActivityPlan(
        Int16(kind), maximum, strength, offsets, activate_extensions, decay
    )
end

function _lower_field(
        statements, kinds, manifest, ::Type{T}, dimensions
    ) where {
        T <: AbstractFloat,
    }
    field_states = filter(statement -> statement isa FieldState, statements)
    isempty(field_states) && return nothing
    length(field_states) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one FieldState per executable"
    ))
    field_state = only(field_states)
    chemotaxis_index = findfirst(statement ->
        statement isa ProposalDrive &&
        _statement_option(statement, :mechanism) === :chemotaxis, statements)
    chemotaxis = chemotaxis_index === nothing ?
                  nothing : statements[chemotaxis_index]
    if chemotaxis !== nothing
        field_ref = _statement_option(chemotaxis, :field)
        isequal(field_state, field_ref) ||
            Symbol(statement_id(field_state)) ===
            (field_ref isa Symbol ? field_ref :
             field_ref isa AbstractPottsStatement ?
             Symbol(statement_id(field_ref)) : Symbol("")) ||
            throw(ArgumentError(
                "chemotaxis references an undeclared FieldState"
            ))
    end
    source_kind_ref = _statement_option(
        field_state,
        :source_kind,
        chemotaxis === nothing ? nothing :
        _statement_option(chemotaxis, :kind),
    )
    source_kind = source_kind_ref === nothing ? 0 :
                  kinds[_kind_name(source_kind_ref)]
    chemotaxis_kind = chemotaxis === nothing ? 0 :
                       kinds[_kind_name(_statement_option(chemotaxis, :kind))]
    diffusion = _compiled_scalar(
        _statement_option(field_state, :diffusion, 0.0), manifest, T
    )
    decay = _compiled_scalar(
        _statement_option(field_state, :decay, 0.0), manifest, T
    )
    secretion = _compiled_scalar(
        _statement_option(field_state, :secretion, 0.0), manifest, T
    )
    strength = chemotaxis === nothing ?
               CorePotts.CompiledScalar(zero(T)) :
               _compiled_scalar(
                   _statement_option(chemotaxis, :strength), manifest, T
               )
    substeps = Int(_statement_option(field_state, :substeps, 1))
    substeps > 0 || throw(ArgumentError("field substeps must be positive"))
    duration_value = _statement_option(
        field_state, :duration_per_mcs, 1.0
    )
    duration = T(_numeric_value(
        duration_value,
        _reference_for(manifest.reference_units, duration_value),
    ))
    stencil_offsets = _relation_offsets(
        statements, :field_stencil, dimensions, VonNeumann()
    )
    return CorePotts.CompiledFieldPlan(
        true,
        diffusion,
        decay,
        secretion,
        Int16(source_kind),
        Int16(chemotaxis_kind),
        strength,
        stencil_offsets,
        Int32(substeps),
        duration,
    )
end

function _lower_history(statements)
    histories = filter(statement -> statement isa HistoryState, statements)
    isempty(histories) && return nothing
    length(histories) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one HistoryState per executable"
    ))
    statement = only(histories)
    source = _statement_option(statement, :of, nothing)
    source === nothing && throw(ArgumentError(
        "HistoryState requires an explicit `of` source in V1"
    ))
    activity_states = filter(candidate ->
        candidate isa SiteState &&
        isequal(_statement_arguments(candidate).variable, source), statements)
    length(activity_states) == 1 || throw(ArgumentError(
        "V1 history source must identify one declared SiteState"
    ))
    depth = _numeric_value(_statement_option(statement, :depth, 1))
    depth isa Real && isinteger(depth) ||
        throw(ArgumentError("history depth must be structurally resolved"))
    return CorePotts.CompiledHistoryPlan(Int(depth), :activity)
end

function _lower_relationships(statements, kinds, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    resources = filter(statement -> statement isa RelationshipState, statements)
    isempty(resources) && return nothing
    length(resources) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one RelationshipState per executable"
    ))
    relationship = only(resources)
    endpoints = _statement_option(relationship, :endpoints)
    endpoints isa Undirected || throw(ArgumentError(
        "V1 relationship lowering currently requires Undirected endpoints"
    ))
    kind_a = kinds[_kind_name(endpoints.kind_a)]
    kind_b = kinds[_kind_name(endpoints.kind_b)]
    capacity = _numeric_value(_statement_option(relationship, :capacity))
    maximum_degree =
        _numeric_value(_statement_option(relationship, :maximum_degree))
    capacity isa Real && isinteger(capacity) ||
        throw(ArgumentError("relationship capacity must be structurally resolved"))
    maximum_degree isa Real && isinteger(maximum_degree) || throw(ArgumentError(
        "relationship maximum_degree must be structurally resolved"
    ))
    payload = _statement_option(relationship, :payload, NamedTuple())
    all(name -> haskey(payload, name), (:strength, :target, :maximum)) ||
        throw(ArgumentError(
            "relationship payload requires strength, target, and maximum"
        ))
    strength = _compiled_scalar(payload.strength, manifest, T)
    target = _compiled_scalar(payload.target, manifest, T)
    maximum = _compiled_scalar(payload.maximum, manifest, T)
    create_on_copy = any(statements) do candidate
        candidate isa AcceptedCopyProcess || return false
        any(_statement_arguments(candidate).effects) do effect
            effect isa Create && isequal(effect.relationship, relationship)
        end
    end
    break_after_mcs = any(statements) do candidate
        candidate isa Union{RelationshipProcess, LifecycleProcess} || return false
        any(_statement_arguments(candidate).effects) do effect
            effect isa Remove && isequal(effect.relationship, relationship)
        end
    end
    lifecycle = _statement_option(
        relationship, :lifecycle, RejectEndpointRetirement()
    )
    lifecycle isa Union{RemoveWithEndpoint, RejectEndpointRetirement} ||
        throw(ArgumentError("unsupported relationship lifecycle policy"))
    remove_with_endpoint = lifecycle isa RemoveWithEndpoint
    return CorePotts.CompiledRelationshipPlan(
        Int(capacity),
        Int(maximum_degree),
        kind_a,
        kind_b,
        strength,
        target,
        maximum;
        create_on_accepted_copy = create_on_copy,
        break_after_mcs,
        remove_with_endpoint,
    )
end

function _lower_elongation(statements, kinds, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    terms = filter(statement ->
        statement isa HamiltonianTerm &&
        _statement_option(statement, :mechanism) === :elongation, statements)
    isempty(terms) && return nothing
    length(terms) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one elongation term"
    ))
    term = only(terms)
    kind = kinds[_kind_name(_statement_option(term, :kind))]
    return CorePotts.CompiledElongationPlan(
        Int16(kind),
        _compiled_scalar(_statement_option(term, :target), manifest, T),
        _compiled_scalar(_statement_option(term, :strength), manifest, T),
    )
end

function _token_suffix(value, prefix::AbstractString)
    name = String(Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value))))
    startswith(name, prefix) || return nothing
    return Symbol(name[(lastindex(prefix) + 1):end])
end

function _lower_observations(statements, kinds)
    plans = CorePotts.AbstractProgramObservation[]
    manifest = NamedTuple[]
    field_variables = Dict{Any, Symbol}()
    for statement in statements
        statement isa FieldState || continue
        arguments = _statement_arguments(statement)
        haskey(arguments, :variable) || continue
        field_variables[arguments.variable] = Symbol(statement_id(statement))
    end
    for statement in statements
        statement isa Observation || continue
        expression = _statement_arguments(statement).expression
        name = Symbol(statement_id(statement))
        if any(variable -> isequal(expression, variable), keys(field_variables))
            push!(plans, CorePotts.FieldStateObservation())
            push!(manifest, (name, kind = :field_state))
            continue
        end
        unwrapped = Symbolics.unwrap(expression)
        operation = try
            Symbolics.operation(unwrapped)
        catch
            nothing
        end
        arguments = try
            Symbolics.arguments(unwrapped)
        catch
            Any[]
        end
        if operation === occupancy && length(arguments) == 2
            kind_name = _token_suffix(first(arguments), "__potts_kind__")
            kind_name === nothing && throw(ArgumentError(
                "observation `$name` has an invalid occupancy kind"
            ))
            push!(plans, CorePotts.OccupiedSitesObservation(
                Int16(kinds[kind_name])
            ))
            push!(manifest, (name, kind = :occupied_sites))
        elseif operation === neighbor_count && length(arguments) == 2
            relationship_name = _token_suffix(
                first(arguments), "__potts_relationship_set__"
            )
            relationship_name === nothing && throw(ArgumentError(
                "observation `$name` has an unsupported neighbor-count source"
            ))
            endpoint = _numeric_value(last(arguments))
            endpoint isa Integer || isinteger(endpoint) ||
                throw(ArgumentError("relationship degree endpoint must be integral"))
            push!(plans, CorePotts.RelationshipDegreeObservation(
                Int32(endpoint)
            ))
            push!(manifest, (
                name, kind = :relationship_degree, relationship_name
            ))
        else
            throw(ArgumentError(
                "no concrete V1 observation lowering exists for `$name`: " *
                "$(repr(expression))"
            ))
        end
    end
    return Tuple(plans), Tuple(manifest)
end

function _protocol_settings(statements, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    attempts = 1
    temperature_value = one(T)
    for statement in statements
        statement isa Protocol || continue
        for stage in _statement_arguments(statement).stages
            stage isa SweepStage || continue
            attempts = stage.attempts.count
            if haskey(stage.options, :temperature)
                temperature_value = stage.options.temperature
            end
        end
    end
    return attempts, _compiled_scalar(temperature_value, manifest, T)
end

const _PROGRAM_BINARY_OPERATIONS = (
    (+) => :add,
    (-) => :subtract,
    (*) => :multiply,
    (/) => :divide,
    (^) => :power,
    max => :maximum,
    min => :minimum,
    (<) => :less,
    (<=) => :less_equal,
    (>) => :greater,
    (>=) => :greater_equal,
    (==) => :equal,
    (!=) => :not_equal,
    (&) => :and,
    (|) => :or,
)

const _PROGRAM_UNARY_OPERATIONS = (
    (!) => :not,
    abs => :absolute,
    exp => :exponential,
    log => :logarithm,
    sqrt => :square_root,
)

function _program_operation_name(operation, arity::Int)
    if operation === (-) && arity == 1
        return :negate
    end
    for (candidate, name) in _PROGRAM_BINARY_OPERATIONS
        operation === candidate && return name
    end
    for (candidate, name) in _PROGRAM_UNARY_OPERATIONS
        operation === candidate && return name
    end
    operation === ifelse && return :ifelse
    return nothing
end

function _fold_program_call(name::Symbol, arguments::Tuple)
    isempty(arguments) &&
        throw(ArgumentError("symbolic operation `$name` has no arguments"))
    length(arguments) == 1 &&
        return CorePotts.ProgramCall(Val(name), only(arguments))
    result = CorePotts.ProgramCall(Val(name), arguments[1], arguments[2])
    for index in 3:length(arguments)
        result = CorePotts.ProgramCall(Val(name), result, arguments[index])
    end
    return result
end

function _explicit_draw_operations(completed::PottsSystem)
    identities = Symbol[]
    for (_, operations) in inspect(completed, RandomOperations())
        for operation in operations
            operation.reserved && continue
            operation.identity in identities || push!(identities, operation.identity)
        end
    end
    sort!(identities; by = String)
    length(identities) <= 4095 - 15 ||
        throw(ArgumentError("too many explicit stochastic operations"))
    return Dict(identity => UInt16(index + 15)
                for (index, identity) in enumerate(identities))
end

function _lower_program_expression(
        value,
        manifest::ParameterManifest,
        ::Type{T},
        draw_operations,
    ) where {T <: AbstractFloat}
    if value isa Bool
        return CorePotts.ProgramLiteral(value)
    elseif value isa Number &&
            SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic
        return CorePotts.ProgramLiteral(T(_numeric_value(
            value, _reference_for(manifest.reference_units, value)
        )))
    end

    unwrapped = Symbolics.unwrap(value)
    if !Symbolics.iscall(unwrapped)
        literal = try
            Symbolics.value(unwrapped)
        catch
            nothing
        end
        if literal isa Bool
            return CorePotts.ProgramLiteral(literal)
        elseif literal isa Number
            return CorePotts.ProgramLiteral(T(_numeric_value(
                literal, _reference_for(manifest.reference_units, literal)
            )))
        end
        index = _parameter_index(manifest, value)
        index === nothing && throw(ArgumentError(
            "proposal expression contains an unresolved symbolic leaf " *
            "$(repr(value)); only runtime parameters and registered Potts " *
            "operations may reach execution"
        ))
        return CorePotts.ProgramScalar(_compiled_scalar(value, manifest, T))
    end

    operation = Symbolics.operation(unwrapped)
    arguments = Tuple(Symbolics.arguments(unwrapped))
    if operation === _potts_draw
        family = _draw_family(arguments)
        family === :unit_vector && throw(ArgumentError(
            "UnitVector draws require a vector-valued state/effect target and " *
            "cannot be used as a scalar proposal contribution"
        ))
        key = _draw_key(arguments)
        haskey(draw_operations, key) ||
            throw(ArgumentError("draw `$key` has no compiled RNG operation"))
        first_parameter = _lower_program_expression(
            arguments[2], manifest, T, draw_operations
        )
        second_parameter = _lower_program_expression(
            arguments[3], manifest, T, draw_operations
        )
        return CorePotts.ProgramDraw(
            Val(family),
            first_parameter,
            second_parameter,
            draw_operations[key],
        )
    end

    context_operation = if operation === source_site
        :source_site
    elseif operation === target_site
        :target_site
    elseif operation === source_cell
        :source_cell
    elseif operation === target_cell
        :target_cell
    elseif operation === source_kind
        :source_kind
    elseif operation === target_kind
        :target_kind
    elseif operation === is_extension
        :is_extension
    elseif operation === is_retraction
        :is_retraction
    else
        nothing
    end
    context_operation === nothing || return CorePotts.ProgramCall(
        Val(context_operation)
    )

    if operation === cell_volume
        length(arguments) == 1 ||
            throw(ArgumentError("cell_volume requires one proposal expression"))
        return CorePotts.ProgramCall(
            Val(:cell_volume),
            _lower_program_expression(
                only(arguments), manifest, T, draw_operations
            ),
        )
    elseif operation === field_value
        length(arguments) == 2 ||
            throw(ArgumentError("field_value requires a field and site"))
        return CorePotts.ProgramCall(
            Val(:field_value),
            CorePotts.ProgramLiteral(:compiled_field),
            _lower_program_expression(
                last(arguments), manifest, T, draw_operations
            ),
        )
    end

    name = _program_operation_name(operation, length(arguments))
    name === nothing && throw(ArgumentError(
        "no concrete V1 proposal-expression lowering exists for operation " *
        "$(repr(operation)) in $(repr(value))"
    ))
    lowered = Tuple(
        _lower_program_expression(argument, manifest, T, draw_operations)
        for argument in arguments
    )
    if name === :ifelse
        length(lowered) == 3 ||
            throw(ArgumentError("ifelse requires three arguments"))
        return CorePotts.ProgramCall(Val(:ifelse), lowered...)
    elseif name in (:negate, :not, :absolute, :exponential, :logarithm,
                    :square_root)
        length(lowered) == 1 ||
            throw(ArgumentError("unary operation `$name` requires one argument"))
        return CorePotts.ProgramCall(Val(name), only(lowered))
    end
    length(lowered) >= 2 ||
        throw(ArgumentError("binary operation `$name` requires two arguments"))
    return _fold_program_call(name, lowered)
end

function _lower_proposal_expressions(
        completed::PottsSystem,
        statements,
        manifest::ParameterManifest,
        ::Type{T},
    ) where {T <: AbstractFloat}
    draw_operations = _explicit_draw_operations(completed)
    lower(statement) = CorePotts.CompiledProposalTerm(
        _lower_program_expression(
            _statement_arguments(statement).expression,
            manifest,
            T,
            draw_operations,
        )
    )
    # Registered extensions are owned by the generic descriptor plan. Keeping
    # them out of the prototype program tuple prevents occurrence count from
    # leaking back into the executable type while G3 replaces proposal
    # execution with descriptor groups.
    legacy(statement) =
        !haskey(_statement_options(statement), :__registered_origin)
    energies = Tuple(
        lower(statement)
        for statement in statements
        if statement isa HamiltonianTerm &&
           _statement_option(statement, :mechanism) in (nothing, :symbolic) &&
           legacy(statement)
    )
    drives = Tuple(
        lower(statement) for statement in statements
        if statement isa ProposalDrive && legacy(statement)
    )
    constraints = Tuple(
        lower(statement)
        for statement in statements
        if statement isa ProposalConstraint &&
           _statement_option(statement, :mechanism) !== :local_connectivity &&
           legacy(statement)
    )
    modifiers = Tuple(
        lower(statement) for statement in statements
        if statement isa ProposalModifier && legacy(statement)
    )
    return (; energies, drives, constraints, modifiers)
end

function _lower_core_program(
        completed::PottsSystem,
        engine::AbstractPottsEngine,
        backend::AbstractPottsBackend,
        ::Type{T},
        manifest::ParameterManifest,
        descriptor_plan::CorePotts.DescriptorExecutionPlan,
        fingerprint_seed::String,
    ) where {T <: AbstractFloat}
    all_statements = _all_system_statements(completed)
    domains = filter(statement -> statement isa LatticeDomain, all_statements)
    length(domains) == 1 ||
        throw(ArgumentError("V1 compilation requires exactly one LatticeDomain"))
    domain = only(domains)
    shape = _statement_option(domain, :shape)
    shape isa Tuple{Vararg{Int}} ||
        throw(ArgumentError("lattice shape must be resolved to integer dimensions"))
    dimensions = length(shape)
    dimensions > 0 || throw(ArgumentError("lattice must have positive dimension"))
    boundary = _statement_option(domain, :boundary, Periodic())
    periodic = if boundary isa Periodic
        ntuple(_ -> true, dimensions)
    elseif boundary isa Union{Closed, FrozenBorder}
        ntuple(_ -> false, dimensions)
    else
        throw(ArgumentError("unsupported V1 lattice boundary $(typeof(boundary))"))
    end

    declarations = filter(
        statement -> statement isa Union{CellKind, MediumKind}, all_statements
    )
    isempty(declarations) &&
        throw(ArgumentError("V1 compilation requires declared cell/medium kinds"))
    sorted_declarations = sort(declarations; by = statement ->
        (statement isa MediumKind ? 0 : 1, String(Symbol(statement_id(statement)))))
    kinds = Dict{Symbol, Int}()
    for (index, declaration) in enumerate(sorted_declarations)
        name = _kind_name(declaration)
        haskey(kinds, name) &&
            throw(ArgumentError("duplicate kind `$name`"))
        kinds[name] = index
    end
    media = filter(statement -> statement isa MediumKind, sorted_declarations)
    isempty(media) &&
        throw(ArgumentError("V1 compilation requires at least one MediumKind"))
    medium_kind = kinds[_kind_name(first(media))]
    medium_kinds = falses(length(kinds))
    for declaration in media
        medium_kinds[kinds[_kind_name(declaration)]] = true
    end
    count = length(kinds)
    defaults = _default_parameter_buffer(manifest, T)
    zero_scalar = CorePotts.CompiledScalar(zero(T))
    volume_targets = fill(zero_scalar, count)
    volume_strengths = fill(zero_scalar, count)
    contact_energies = fill(zero_scalar, count, count)
    connectivity_kinds = falses(count)

    for statement in all_statements
        mechanism = _statement_option(statement, :mechanism)
        if statement isa HamiltonianTerm && mechanism === :volume
            kind = kinds[_kind_name(_statement_option(statement, :kind))]
            volume_targets[kind] = _compiled_scalar(
                _statement_option(statement, :target), manifest, T
            )
            volume_strengths[kind] = _compiled_scalar(
                _statement_option(statement, :strength), manifest, T
            )
        elseif statement isa HamiltonianTerm && mechanism === :contact
            for law in _statement_option(statement, :laws, ())
                pair = first(law)
                energy = _compiled_scalar(last(law), manifest, T)
                first_kind = kinds[_kind_name(pair.first)]
                second_kind = kinds[_kind_name(pair.second)]
                contact_energies[first_kind, second_kind] = energy
                contact_energies[second_kind, first_kind] = energy
            end
        elseif statement isa ProposalConstraint &&
                mechanism === :local_connectivity
            kind = kinds[_kind_name(_statement_option(statement, :kind))]
            connectivity_kinds[kind] = true
        elseif statement isa HamiltonianTerm &&
                !(mechanism in (
                    nothing, :symbolic,
                    :volume, :contact, :relationship, :elongation,
                ))
            throw(ArgumentError(
                "no V1 lowering is registered for HamiltonianTerm mechanism " *
                "$(repr(mechanism))"
            ))
        end
    end

    proposal_offsets = _relation_offsets(
        all_statements, :proposal, dimensions, VonNeumann()
    )
    contact_offsets = _relation_offsets(
        all_statements, :contact, dimensions, Moore()
    )
    attempts, temperature = _protocol_settings(all_statements, manifest, T)
    activity = _lower_activity(all_statements, kinds, manifest, T, dimensions)
    field = _lower_field(all_statements, kinds, manifest, T, dimensions)
    history = _lower_history(all_statements)
    elongation = _lower_elongation(all_statements, kinds, manifest, T)
    relationships = _lower_relationships(all_statements, kinds, manifest, T)
    observations, observation_manifest =
        _lower_observations(all_statements, kinds)
    cell_state_fields = Tuple(
        Symbol(statement_id(statement))
        for statement in all_statements
        if statement isa CellState &&
           haskey(_statement_arguments(statement), :variable)
    )
    core_engine = engine isa SequentialEngine ?
                  CorePotts.SequentialProgramEngine() :
                  CorePotts.CheckerboardProgramEngine()
    core_backend = CorePotts.CPUProgramBackend()
    program_fingerprint = _sha256_hex(
        "core-program-v1",
        fingerprint_seed,
        nameof(typeof(engine)),
        nameof(typeof(backend)),
        T,
        shape,
        periodic,
        proposal_offsets,
        contact_offsets,
        sort(collect(kinds); by = first),
    )
    return CorePotts.CompiledPottsProgram(
        shape,
        periodic,
        proposal_offsets,
        contact_offsets,
        count,
        medium_kind,
        volume_targets,
        volume_strengths,
        contact_energies,
        connectivity_kinds,
        temperature,
        attempts,
        defaults,
        activity,
        field,
        history,
        elongation,
        relationships,
        observations,
        descriptor_plan,
        core_engine,
        core_backend,
        program_fingerprint;
        medium_kinds,
        cell_state_fields,
    ), Tuple(_kind_name(declaration) for declaration in sorted_declarations),
       observation_manifest
end
