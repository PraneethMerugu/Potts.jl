# Macro-time records only. They never enter LocalLaw or execution.
struct _LocalMathReadSyntax
    field::Symbol
    relation::Union{Nothing,Symbol}
    mode::Symbol
    role::Symbol
end

struct _LocalMathCollectionReadSyntax
    collection::Symbol
    mode::Symbol
    argument::Any
    role::Symbol
end

struct _LocalMathPublicationSyntax
    field::Union{Nothing,Symbol}
    relation::Union{Nothing,Symbol}
    port::Symbol
    law::Symbol
    value::Any
    options::NamedTuple
    line::Int
end

struct _LocalMathTieFieldSyntax
    field::Symbol
    properties::Tuple{Vararg{Symbol}}
end

_lm_error(message, source; actual = nothing) = throw(LocalMathValidationError(
    message; stage = :construct, contract = :localmath_syntax,
    origin = SourceOrigin(String(source.file), source.line), actual))

function _lm_binder(spec, source)
    options = Dict{Symbol,Any}(
        :parameters => nothing, :when => nothing, :prefix => nothing,
        :mask => nothing, :subset => nothing)
    binder = spec
    if spec isa Expr && spec.head === :block
        binder = nothing
        for part in spec.args
            part isa LineNumberNode && continue
            if part isa Expr && part.head === :(=) &&
                    haskey(options, part.args[1])
                options[part.args[1]] = part.args[2]
            elseif binder === nothing
                binder = part
            else
                _lm_error("unknown @localmath stage option", source;
                    actual = part)
            end
        end
    elseif spec isa Expr && spec.head === :tuple
        for part in spec.args
            if part isa Expr && part.head === :parameters
                for option in part.args
                    option isa Expr && option.head === :kw ||
                        _lm_error("@localmath options must be keywords", source;
                            actual = option)
                    haskey(options, option.args[1]) ||
                        _lm_error("unknown @localmath stage option", source;
                            actual = option.args[1])
                    options[option.args[1]] = option.args[2]
                end
            else
                binder = part
            end
        end
    end
    binder isa Expr && binder.head === :call && length(binder.args) == 3 &&
        binder.args[1] in (:∈, :in) &&
        (binder.args[2] isa Symbol ||
         binder.args[2] isa Expr && binder.args[2].head === :tuple &&
         all(value -> value isa Symbol, binder.args[2].args)) ||
        _lm_error("@localmath requires `item ∈ source` or Cartesian `(i, j) ∈ source`",
            source; actual = binder)
    return binder.args[2], binder.args[3], (; options...)
end

function _lm_parameters(expression, source)
    expression === nothing && return ()
    expression isa Expr && expression.head === :tuple ||
        _lm_error("parameters must be a tuple of `name::Type` declarations",
            source; actual = expression)
    declarations = Tuple(expression.args)
    all(value -> value isa Expr && value.head === :(::) &&
            length(value.args) == 2 && value.args[1] isa Symbol,
        declarations) || _lm_error(
            "each @localmath parameter must be written `name::Type`", source;
            actual = expression)
    names = Tuple(value.args[1] for value in declarations)
    length(unique(names)) == length(names) || _lm_error(
        "@localmath parameter names must be unique", source; actual = names)
    return declarations
end

function _lm_relation_index(index, binder::Symbol)
    index === binder && return nothing
    index isa Expr && index.head === :call && length(index.args) == 2 &&
        index.args[1] isa Symbol && index.args[2] === binder &&
        return index.args[1]
    return missing
end

_lm_call(expression, name::Symbol) = expression isa Expr &&
    expression.head === :call && !isempty(expression.args) &&
    expression.args[1] === name
_lm_literal_symbol(value) = value isa QuoteNode ? value.value : value

function _lm_explicit_tie_fields(
        expression, binder, source, aliases = Dict{Symbol,Any}())
    _lm_literal_symbol(expression) === :canonical && return nothing
    components = expression isa Expr && expression.head === :tuple ?
        expression.args : (expression,)
    fields = _LocalMathTieFieldSyntax[]
    for component in components
        while component isa Symbol && haskey(aliases, component)
            component = aliases[component]
        end
        properties = Symbol[]
        while component isa Expr && component.head === :. &&
                length(component.args) == 2 &&
                component.args[2] isa QuoteNode &&
                component.args[2].value isa Symbol
            pushfirst!(properties, component.args[2].value)
            component = component.args[1]
            while component isa Symbol && haskey(aliases, component)
                component = aliases[component]
            end
        end
        valid = component isa Expr && component.head === :ref &&
            component.args[1] isa Symbol
        if valid && binder isa Expr && binder.head === :tuple
            valid = length(component.args) == length(binder.args) + 1 &&
                all(component.args[axis + 1] === binder.args[axis]
                    for axis in eachindex(binder.args))
        elseif valid
            valid = length(component.args) == 2 &&
                _lm_relation_index(component.args[2], binder) !== missing
        end
        valid || _lm_error(
            "an explicit Resolve tie must contain bounded Field reads",
            source; actual = component)
        push!(fields, _LocalMathTieFieldSyntax(
            component.args[1], Tuple(properties)))
    end
    return Tuple(fields)
end

function _lm_bounded_iteration_source(expression, binder::Symbol)
    expression isa Expr || return expression isa Tuple
    expression.head === :tuple && return true
    if expression.head === :ref && length(expression.args) == 2
        return _lm_relation_index(expression.args[2], binder) !== missing
    end
    if (_lm_call(expression, :samples) || _lm_call(expression, :indices)) &&
            length(expression.args) == 2
        reference = expression.args[2]
        return reference isa Expr && reference.head === :ref &&
            length(reference.args) == 2 &&
            _lm_relation_index(reference.args[2], binder) !== missing
    end
    if _lm_call(expression, :(:)) && length(expression.args) in (3, 4)
        bounds = expression.args[2:end]
        return all(bound -> bound isa Integer, bounds) ||
            (length(bounds) == 2 && bounds[1] == 1 &&
             _lm_call(bounds[2], :degree_bound))
    end
    return false
end

function _lm_call_options(expression, source)
    positional = Any[]
    keywords = Dict{Symbol,Any}()
    for argument in expression.args[2:end]
        if argument isa Expr && argument.head === :parameters
            for keyword in argument.args
                keyword isa Expr && keyword.head === :kw ||
                    _lm_error("LocalMath law options must be keywords", source;
                        actual = keyword)
                keywords[keyword.args[1]] = keyword.args[2]
            end
        else
            push!(positional, argument)
        end
    end
    return positional, keywords
end

function _lm_require_keywords(keywords, allowed, form, source)
    unexpected = Tuple(key for key in keys(keywords) if key ∉ allowed)
    isempty(unexpected) || _lm_error(
        "$(form) received unsupported keyword(s)", source;
        actual = unexpected)
    return nothing
end

_lm_namedtuple(pairs) = Expr(:tuple, Expr(:parameters,
    (Expr(:kw, name, value) for (name, value) in pairs)...))

function _lm_stage(spec, body::Expr, source; label = nothing)
    binder, source_expression, stage_options =
        _lm_binder(spec, source)
    tuple_binder = binder isa Expr && binder.head === :tuple
    spatial_contract = _lm_call(source_expression, :interior) ||
        _lm_call(source_expression, :periodic)
    cartesian = tuple_binder || spatial_contract
    binder_symbols = tuple_binder ? Tuple(binder.args) : (binder,)
    source_mode = :plain
    halo = 0
    semantic_source_expression = source_expression
    if cartesian
        (_lm_call(source_expression, :interior) ||
            _lm_call(source_expression, :periodic)) &&
            (source_mode = source_expression.args[1])
        if source_mode === :interior
            length(source_expression.args) == 3 &&
                source_expression.args[3] isa Integer || _lm_error(
                    "interior(space, halo) requires a literal halo", source;
                    actual = source_expression)
            halo = Int(source_expression.args[3])
            halo >= 0 || _lm_error("interior halo must be nonnegative", source;
                actual = halo)
        elseif source_mode === :periodic
            length(source_expression.args) == 2 || _lm_error(
                "periodic(space) accepts one Space", source;
                actual = source_expression)
        end
        source_mode !== :plain &&
            (semantic_source_expression = source_expression.args[2])
    end
    parameter_expression = stage_options.parameters
    declarations = _lm_parameters(parameter_expression, source)
    parameter_names = Tuple(declaration.args[1] for declaration in declarations)
    reads = Union{_LocalMathReadSyntax,_LocalMathCollectionReadSyntax}[]
    read_roles = Dict{Tuple{Symbol,Union{Nothing,Symbol},Symbol},Symbol}()
    used_read_roles = Dict{Symbol,Int}()
    function unique_read_role(base::Symbol)
        ordinal = get(used_read_roles, base, 0) + 1
        used_read_roles[base] = ordinal
        return ordinal == 1 ? base : Symbol(base, :_, ordinal)
    end
    function lexical_relation_name(relation)
        relation === nothing && return :identity
        startswith(String(relation), "##") && return :stencil
        return relation
    end
    function read_role(field::Symbol, relation, mode::Symbol)
        key = (field, relation, mode)
        return get!(read_roles, key) do
            role = unique_read_role(Symbol(field, :_via_,
                lexical_relation_name(relation), :_, mode))
            push!(reads, _LocalMathReadSyntax(field, relation, mode, role))
            role
        end
    end
    collection_roles = Dict{Tuple{Symbol,Symbol,Any},Symbol}()
    function collection_role(collection::Symbol, mode::Symbol, argument)
        key = (collection, mode, argument)
        return get!(collection_roles, key) do
            role = unique_read_role(Symbol(collection, :_, mode))
            push!(reads, _LocalMathCollectionReadSyntax(
                collection, mode, argument, role))
            role
        end
    end

    reads_symbol, parameters_symbol, item_symbol =
        gensym(:reads), gensym(:parameters), gensym(:item)
    required_scalar = GlobalRef(LocalMath, :_authoring_required_scalar)
    required_lane = GlobalRef(LocalMath, :_authoring_required_lane)
    sample_lane = GlobalRef(LocalMath, :_authoring_sample_lane)
    index_lane = GlobalRef(LocalMath, :_authoring_index_lane)
    values_view = GlobalRef(LocalMath, :_authoring_values)
    samples_view = GlobalRef(LocalMath, :_authoring_samples)
    indices_view = GlobalRef(LocalMath, :_authoring_indices)
    synthetic_relations = Dict{Tuple{Symbol,Symbol},Symbol}()
    synthetic_relation_expressions = Dict{Symbol,Any}()
    function cartesian_offset(index)
        index isa Tuple && length(index) == length(binder_symbols) ||
            _lm_error("Cartesian Field indexing must match the binder dimension",
                source; actual = index)
        return ntuple(length(binder_symbols)) do axis
            value = index[axis]
            value === binder_symbols[axis] && return 0
            value isa Expr && value.head === :call && length(value.args) == 3 &&
                value.args[2] === binder_symbols[axis] &&
                value.args[3] isa Integer && value.args[1] in (:+, :-) ||
                _lm_error("Cartesian indices admit only static binder offsets",
                    source; actual = value)
            value.args[1] === :+ ? Int(value.args[3]) : -Int(value.args[3])
        end
    end
    function cartesian_relation(field::Symbol, index, usage::Symbol)
        offset = cartesian_offset(index)
        if source_mode === :plain
            all(iszero, offset) || _lm_error(
                "offset Cartesian indexing requires interior(...) or periodic(...) bounds",
                source; actual = index)
            return nothing, 1
        end
        source_mode === :interior && any(abs(value) > halo for value in offset) &&
            _lm_error(
                "an authored Cartesian offset exceeds the interior halo",
                source; actual = (offset = offset, halo = halo))
        key = usage === :read ? (field, :read) :
            (field, Symbol(:publication_, join(offset, :_)))
        name = get!(synthetic_relations, key) do
            name = gensym(:cartesian_relation)
            synthetic_relation_expressions[name] = (; field, offsets = (),
                periodic = source_mode === :periodic)
            name
        end
        fact = synthetic_relation_expressions[name]
        lane = findfirst(==(offset), fact.offsets)
        if lane === nothing
            synthetic_relation_expressions[name] = merge(fact,
                (; offsets = (fact.offsets..., offset)))
            lane = length(fact.offsets) + 1
        end
        return name, lane
    end
    function relation_index(index, field::Symbol)
        if cartesian && index isa Tuple
            return first(cartesian_relation(field, index, :publication))
        end
        scalar_index = index isa Tuple && length(index) == 1 ? only(index) : index
        return _lm_relation_index(scalar_index, only(binder_symbols))
    end
    function transform(expression; requested_mode = :required)
        !cartesian && expression === binder && return item_symbol
        expression isa Expr || return expression
        if _lm_call(expression, :bounded)
            positional, keywords = _lm_call_options(expression, source)
            length(positional) == 1 || _lm_error(
                "bounded requires one Collection index", source;
                actual = expression)
            _lm_require_keywords(keywords, (:maximum,), :bounded, source)
            haskey(keywords, :maximum) || _lm_error(
                "bounded Collection access requires maximum", source;
                actual = expression)
            reference = only(positional)
            reference isa Expr && reference.head === :ref &&
                length(reference.args) == 2 &&
                reference.args[1] isa Symbol && reference.args[2] === binder ||
                _lm_error("bounded Collection access must be `collection[item]`",
                    source; actual = reference)
            role = collection_role(reference.args[1], :group,
                keywords[:maximum])
            return :(getfield($reads_symbol,
                $(findfirst(read -> read.role === role, reads))))
        elseif _lm_call(expression, :source_position)
            positional, keywords = _lm_call_options(expression, source)
            length(positional) == 2 || _lm_error(
                "source_position requires a Collection and source item",
                source; actual = expression)
            _lm_require_keywords(keywords, (:lane,), :source_position, source)
            collection, item = positional
            collection isa Symbol && item === binder || _lm_error(
                "source_position must use the current source item", source;
                actual = expression)
            lane = get(keywords, :lane, 1)
            lane isa Integer || _lm_error(
                "source_position lane must be a literal integer", source;
                actual = lane)
            role = collection_role(collection, :source_position, lane)
            read = :(getfield($reads_symbol,
                $(findfirst(read -> read.role === role, reads))))
            return read
        elseif (_lm_call(expression, :samples) || _lm_call(expression, :indices)) &&
                length(expression.args) == 2
            reference = expression.args[2]
            reference isa Expr && reference.head === :ref ||
                _lm_error("samples/indices requires one bounded Field read",
                    source; actual = reference)
            field, indices = reference.args[1], Tuple(reference.args[2:end])
            field isa Symbol || _lm_error(
                "authored Field descriptors must be simple bindings", source;
                actual = field)
            if cartesian
                relation, lane = cartesian_relation(field, indices, :read)
            else
                relation, lane = relation_index(indices, field), 1
            end
            relation === missing && _lm_error(
                "a Field read index must be the item or `relation(item)`",
                source; actual = indices)
            role = read_role(field, relation, :samples)
            read_index = findfirst(read -> read.role === role, reads)
            read = :(getfield($reads_symbol, $read_index))
            return cartesian ?
                (expression.args[1] === :samples ?
                    :($sample_lane($read, Val($lane))) :
                    :($index_lane($read, Val($lane)))) :
                (expression.args[1] === :samples ? :($samples_view($read)) :
                    :($indices_view($read)))
        elseif expression.head === :for
            iterator = expression.args[1]
            iterator isa Expr && iterator.head in (:(=), :in) &&
                _lm_bounded_iteration_source(iterator.args[2], binder) ||
                _lm_error("for loops must be bounded by a relation or literal static range",
                    source; actual = iterator)
        elseif expression.head === :generator
            all(iterator -> iterator isa Expr && iterator.head in (:(=), :in) &&
                    _lm_bounded_iteration_source(iterator.args[2], binder),
                expression.args[2:end]) || _lm_error(
                "comprehensions must be bounded by relations or literal static ranges",
                source; actual = expression)
        elseif expression.head === :ref && length(expression.args) >= 2
            field, indices = expression.args[1], Tuple(expression.args[2:end])
            field isa Symbol || return Expr(:ref,
                transform(field; requested_mode),
                (transform(index; requested_mode) for index in indices)...)
            if cartesian
                relation, lane = cartesian_relation(field, indices, :read)
            else
                relation, lane = relation_index(indices, field), 1
            end
            relation === missing && return Expr(:ref, field,
                (transform(index; requested_mode) for index in indices)...)
            role = read_role(field, relation, requested_mode)
            read_index = findfirst(read -> read.role === role, reads)
            read = :(getfield($reads_symbol, $read_index))
            return cartesian ? :($required_lane($read, Val($lane))) :
                relation === nothing ? :($required_scalar($read)) :
                :($values_view($read))
        elseif expression.head === :macrocall || expression.head in (:while, :global)
            _lm_error("unbounded loops, foreign macros, and global mutation are not admitted",
                source; actual = expression)
        end
        return Expr(expression.head,
            (transform(argument; requested_mode) for argument in expression.args)...)
    end

    publications = _LocalMathPublicationSyntax[]
    used_publication_ports = Dict{Symbol,Int}()
    function publication_port(field, law::Symbol)
        base = field === nothing ? :ordered_state : Symbol(field, :_, law)
        ordinal = get(used_publication_ports, base, 0) + 1
        used_publication_ports[base] = ordinal
        return ordinal == 1 ? base : Symbol(base, :_, ordinal)
    end
    evaluator_statements = Any[]
    evaluator_aliases = Dict{Symbol,Any}()
    evaluator_type_aliases = Dict{Symbol,Any}()
    function ordered_syntax(statement, line)
        length(statement.args) == 4 || _lm_error(
            "@ordered requires `(by=..., state=...)` and a body", source;
            actual = statement)
        specification, ordered_body = statement.args[3], statement.args[4]
        specification isa Expr && specification.head === :tuple || _lm_error(
            "@ordered requires `(by=..., state=...)`", source;
            actual = specification)
        options = Dict{Symbol,Any}()
        for option in specification.args
            option isa Expr && option.head === :(=) &&
                option.args[1] in (:by, :state) || _lm_error(
                    "@ordered accepts only by and state", source; actual=option)
            options[option.args[1]] = option.args[2]
        end
        all(haskey(options, name) for name in (:by, :state)) || _lm_error(
            "@ordered requires by and state", source; actual=keys(options))
        by = options[:by]
        source_ordered = _lm_literal_symbol(by) === :source
        source_ordered || by isa Expr && by.head === :tuple && length(by.args) == 2 ||
            _lm_error("@ordered by must be `(key, identity)`", source;
                actual=by)
        state_expression = options[:state]
        state_expression isa Expr && state_expression.head === :tuple ||
            _lm_error("@ordered state must be target => initial pairs", source;
                actual=state_expression)
        state_pairs = Pair{Symbol,Symbol}[]
        for pair in state_expression.args
            _lm_call(pair, :(=>)) && length(pair.args) == 3 &&
                pair.args[2] isa Symbol && pair.args[3] isa Symbol ||
                _lm_error("ordered state entries must be `target => initial`",
                    source; actual=pair)
            push!(state_pairs, pair.args[2] => pair.args[3])
        end
        targets = first.(state_pairs)
        state_symbol = gensym(:state)
        transition_reads = reads_symbol
        transition_item = item_symbol
        function ordered_transform(value)
            value isa Symbol && haskey(evaluator_aliases, value) &&
                return ordered_transform(evaluator_aliases[value])
            value === binder && return transition_item
            value isa Expr || return value
            if value.head === :ref && value.args[1] isa Symbol &&
                    value.args[1] in targets
                length(value.args) == 2 || _lm_error(
                    "ordered state reads require one linear index", source;
                    actual=value)
                return :(getproperty($state_symbol,
                    $(QuoteNode(value.args[1])))[$(ordered_transform(value.args[2]))])
            elseif value.head === :ref
                # A descriptor-rooted reference is a new bounded read and
                # must pass through the ordinary access lowering. References
                # rooted in an authored alias (including record projections
                # such as `event.sites[1]`) must instead expand that alias
                # recursively inside the ordered transition. Sending the
                # latter back through `transform` would leave the alias as an
                # accidental global and destroy inference.
                root = value.args[1]
                if root isa Symbol && !haskey(evaluator_aliases, root)
                    return transform(value)
                end
                return Expr(:ref,
                    (ordered_transform(arg) for arg in value.args)...)
            end
            return Expr(value.head, (ordered_transform(arg) for arg in value.args)...)
        end
        local_statements = Any[]
        writes = Dict{Symbol,Any}()
        halt = false
        function parse_ordered_block(block, condition=true)
            block isa Expr && block.head === :block ||
                _lm_error("@ordered requires a begin/end body", source;
                    actual=block)
            for value in block.args
                value isa LineNumberNode && continue
                if _lm_call(value, :halt_when) && length(value.args) == 2
                    halt === false || _lm_error(
                        "@ordered admits one halt_when condition", source;
                        actual=value)
                    halt = ordered_transform(value.args[2])
                elseif value isa Expr && value.head === :if
                    length(value.args) in (2,3) || _lm_error(
                        "ordered condition has invalid shape", source; actual=value)
                    length(value.args) == 3 && !(value.args[3] === nothing) &&
                        _lm_error("ordered state conditions do not admit else",
                            source; actual=value)
                    combined = condition === true ? ordered_transform(value.args[1]) :
                        :($condition && $(ordered_transform(value.args[1])))
                    parse_ordered_block(value.args[2], combined)
                elseif value isa Expr && value.head === :(=) &&
                        value.args[1] isa Expr && value.args[1].head === :ref &&
                        value.args[1].args[1] in targets
                    lhs, rhs = value.args
                    name = lhs.args[1]
                    haskey(writes, name) && _lm_error(
                        "each ordered state component may be assigned once",
                        source; actual=name)
                    length(lhs.args) == 2 || _lm_error(
                        "ordered state writes require one bounded index or tuple",
                        source; actual=lhs)
                    destinations = lhs.args[2] isa Expr &&
                        lhs.args[2].head === :tuple ? Tuple(lhs.args[2].args) :
                        (lhs.args[2],)
                    replacements = rhs isa Expr && rhs.head === :tuple ?
                        Tuple(rhs.args) : (rhs,)
                    length(destinations) == length(replacements) || _lm_error(
                        "ordered state destination and value widths must match",
                        source; actual=value)
                    keys = Expr(:tuple, (:(Int32($(ordered_transform(key))))
                        for key in destinations)...)
                    vals = Expr(:tuple,
                        (ordered_transform(replacement) for replacement in replacements)...)
                    count = condition === true ? Int32(length(destinations)) :
                        :(ifelse($condition, Int32($(length(destinations))), Int32(0)))
                    writes[name] = :($(GlobalRef(LocalMath, :_authoring_bounded_writes))(
                        $keys, $vals, $count))
                elseif value isa Expr && value.head === :(=) &&
                        value.args[1] isa Symbol
                    push!(local_statements, Expr(:(=), value.args[1],
                        ordered_transform(value.args[2])))
                else
                    _lm_error("ordered bodies admit local values, conditions, and bounded state assignments",
                        source; actual=value)
                end
            end
        end
        parse_ordered_block(ordered_body)
        isempty(writes) && _lm_error("@ordered requires a state assignment", source)
        missing_targets = filter(target -> !haskey(writes, target), targets)
        isempty(missing_targets) || _lm_error(
            "@ordered must define every declared state component in one FoldStep",
            source; actual=Tuple(missing_targets))
        update_pairs = Pair{Symbol,Any}[]
        for pair in state_pairs
            target = first(pair)
            expression = writes[target]
            push!(update_pairs, target => expression)
        end
        transition = Expr(:->,
            Expr(:tuple, state_symbol, gensym(:event), transition_item,
                transition_reads),
            Expr(:block, local_statements...,
                :(return $(GlobalRef(LocalMath, :_authoring_fold_step))(
                    $(_lm_namedtuple(update_pairs)), $(ordered_transform(halt))))))
        key, identity = source_ordered ? (item_symbol, nothing) :
            (transform(by.args[1]), transform(by.args[2]))
        port = publication_port(nothing, :ordered_state)
        push!(publications, _LocalMathPublicationSyntax(nothing, nothing,
            port, :ordered_state,
            source_ordered ? key : Expr(:tuple, key, identity),
            (; state_pairs=Tuple(state_pairs), transition, by,
                source_ordered), line))
        return nothing
    end
    current_line = source.line
    for statement in body.args
        statement isa LineNumberNode && (current_line = statement.line; continue)
        statement isa Expr || (push!(evaluator_statements, statement); continue)
        if statement.head === :macrocall &&
                statement.args[1] === Symbol("@ordered")
            ordered_syntax(statement, current_line)
        elseif _lm_call(statement, :publish)
            positional, keywords = _lm_call_options(statement, source)
            length(positional) == 2 || _lm_error(
                "publish requires a destination Field and one value", source;
                actual = statement)
            field, value = positional
            field isa Symbol || _lm_error(
                "publish destination must be a simple Field binding", source;
                actual = field)
            all(haskey(keywords, key) for key in (:route, :key)) || _lm_error(
                "runtime publish requires explicit route and key keywords",
                source; actual = statement)
            relation = keywords[:route]
            relation isa Symbol || _lm_error(
                "publish route must be a simple RuntimeRelation binding",
                source; actual = relation)
            law_value = get(keywords, :law, QuoteNode(:unique))
            law = law_value isa QuoteNode ? law_value.value : law_value
            law in (:unique, :reduce, :resolve) || _lm_error(
                "runtime publish law must be :unique, :reduce, or :resolve",
                source; actual = law)
            allowed = law === :unique ?
                (:route, :key, :law, :when, :maximum) :
                law === :reduce ?
                (:route, :key, :law, :when, :maximum, :op, :seed,
                    :onempty, :order) :
                    (:route, :key, :law, :when, :maximum, :score, :lower,
                    :upper, :sense, :tie, :onempty)
            _lm_require_keywords(keywords, allowed, :publish, source)
            delete!(keywords, :route)
            delete!(keywords, :law)
            if law === :resolve
                all(haskey(keywords, key) for key in (:score, :lower, :upper)) ||
                    _lm_error("runtime Resolve requires score, lower, and upper",
                        source; actual = statement)
                keywords[:payload] = value
                haskey(keywords, :tie) &&
                    (keywords[:_tie_fields] = _lm_explicit_tie_fields(
                        keywords[:tie], binder, source,
                        evaluator_type_aliases))
            end
            port = publication_port(field, law)
            transformed_options = (; (key => transform(val)
                for (key, val) in keywords)...)
            push!(publications, _LocalMathPublicationSyntax(field, relation,
                port, law, transform(value), transformed_options, current_line))
        elseif statement.head in (:(=), :(+=)) && statement.args[1] isa Expr &&
                statement.args[1].head === :ref
            lhs, rhs = statement.args
            length(lhs.args) >= 2 || _lm_error(
                "publication targets require a bounded index", source; actual = lhs)
            field, indices = lhs.args[1], Tuple(lhs.args[2:end])
            field isa Symbol || _lm_error(
                "publication descriptors must be simple bindings", source;
                actual = field)
            relation = relation_index(indices, field)
            relation === missing && _lm_error(
                "a publication index must be the item or `relation(item)`",
                source; actual = indices)
            law, value, options = statement.head === :(+=) ?
                (:reduce, rhs, NamedTuple()) : (:unique, rhs, NamedTuple())
            if _lm_call(rhs, :reduce_to)
                positional, keywords = _lm_call_options(rhs, source)
                _lm_require_keywords(keywords,
                    (:op, :seed, :order, :onempty, :when, :maximum),
                    :reduce_to, source)
                length(positional) == 1 || _lm_error(
                    "reduce_to requires one contribution", source; actual = rhs)
                law, value = :reduce, only(positional)
                options = (; (key => val for (key, val) in keywords)...)
            elseif _lm_call(rhs, :resolve_to)
                positional, keywords = _lm_call_options(rhs, source)
                _lm_require_keywords(keywords,
                    (:score, :payload, :lower, :upper, :sense, :when,
                        :maximum, :tie, :onempty), :resolve_to, source)
                isempty(positional) || _lm_error(
                    "resolve_to uses score and payload keywords", source; actual = rhs)
                all(haskey(keywords, key) for key in (:score, :payload, :lower, :upper)) ||
                    _lm_error("resolve_to requires score, payload, lower, and upper",
                        source; actual = rhs)
                haskey(keywords, :tie) &&
                    (keywords[:_tie_fields] = _lm_explicit_tie_fields(
                        keywords[:tie], binder, source,
                        evaluator_type_aliases))
                law, value = :resolve, nothing
                options = (; (key => val for (key, val) in keywords)...)
            elseif _lm_call(rhs, :bounded_collect)
                positional, keywords = _lm_call_options(rhs, source)
                _lm_require_keywords(keywords,
                    (:maximum, :group, :groups, :overflow, :when,
                        :order, :projection),
                    :bounded_collect, source)
                length(positional) == 1 || _lm_error(
                    "bounded_collect requires one record", source; actual = rhs)
                haskey(keywords, :maximum) || _lm_error(
                    "bounded_collect requires a static maximum", source; actual = rhs)
                overflow = _lm_literal_symbol(get(keywords, :overflow,
                    QuoteNode(:reject)))
                overflow === :reject || _lm_error(
                    "bounded_collect currently supports only overflow=:reject",
                    source; actual = overflow)
                haskey(keywords, :group) == haskey(keywords, :groups) ||
                    _lm_error("routed Collect requires both group and groups",
                        source; actual = keys(keywords))
                law, value = :collect, only(positional)
                options = (; (key => val for (key, val) in keywords)...)
            end
            port = publication_port(field, law)
            transformed_value = value === nothing ? nothing : transform(value)
            transformed_options = (; (key => transform(val)
                for (key, val) in pairs(options))...)
            push!(publications, _LocalMathPublicationSyntax(field, relation,
                port, law, transformed_value, transformed_options, current_line))
        elseif statement.head === :while
            _lm_error("@localmath does not admit unbounded while loops", source;
                actual = statement)
        else
            transformed = transform(statement)
            push!(evaluator_statements, transformed)
            if statement.head === :(=) && statement.args[1] isa Symbol
                evaluator_aliases[statement.args[1]] = transformed.args[2]
                evaluator_type_aliases[statement.args[1]] = statement.args[2]
            end
        end
    end
    isempty(publications) && _lm_error(
        "an @localmath stage requires at least one publication equation", source)

    source_local, full_source_local, identity_local =
        gensym(:source), gensym(:full_source), gensym(:identity)
    field_reads = filter(read -> read isa _LocalMathReadSyntax, reads)
    collection_reads = filter(read -> read isa _LocalMathCollectionReadSyntax, reads)
    fields = unique(vcat([read.field for read in field_reads],
        [publication.field for publication in publications
            if publication.field !== nothing],
        [name for publication in publications if publication.law === :ordered_state
            for pair in publication.options.state_pairs for name in pair]))
    relations = unique(vcat(
        [read.relation for read in field_reads if read.relation !== nothing],
        [publication.relation for publication in publications
            if publication.relation !== nothing]))
    field_locals = Dict(field => gensym(field) for field in fields)
    collection_targets = unique(publication.field for publication in publications
        if publication.law === :collect)
    record_types_symbol = gensym(:record_types)
    collection_names = unique(read.collection for read in collection_reads)
    collection_locals = Dict(name => gensym(name) for name in collection_names)
    relation_locals = Dict(relation => gensym(relation) for relation in relations)
    declaration_locals = Dict(name => gensym(name) for name in parameter_names)
    let_bindings = Any[]
    if cartesian
        push!(let_bindings, :($full_source_local = $semantic_source_expression))
        if source_mode === :interior
            push!(let_bindings, :($source_local = $(GlobalRef(LocalMath, :Space))(
                ntuple(axis -> size($full_source_local)[axis] - 2 * $halo,
                    length(size($full_source_local))))))
        else
            push!(let_bindings, :($source_local = $full_source_local))
        end
    else
        push!(let_bindings, :($source_local = $source_expression))
    end
    append!(let_bindings, [Expr(:(=), field_locals[field], field)
        for field in fields])
    append!(let_bindings, [Expr(:(=), collection_locals[name], name)
        for name in collection_names])
    for relation in relations
        if haskey(synthetic_relation_expressions, relation)
            fact = synthetic_relation_expressions[relation]
            base = :($(GlobalRef(LocalMath, :AffineRelation))(
                $source_local => $(field_locals[fact.field]).space;
                offsets=$(fact.offsets),
                origin=$(source_mode === :interior ?
                    ntuple(_ -> halo, length(binder_symbols)) : nothing)))
            value = fact.periodic ?
                :($(GlobalRef(LocalMath, :BoundaryRelation))($base,
                    $(GlobalRef(LocalMath, :PeriodicBoundary))(
                        ntuple(_ -> true, length(first($(fact.offsets))))))) : base
            push!(let_bindings, Expr(:(=), relation_locals[relation], value))
        else
            push!(let_bindings, Expr(:(=), relation_locals[relation], relation))
        end
    end
    push!(let_bindings,
        :($identity_local = $(GlobalRef(LocalMath, :IdentityRelation))($source_local)))
    for declaration in declarations
        name, type = declaration.args
        push!(let_bindings, :($(declaration_locals[name]) =
            $(GlobalRef(LocalMath, :Parameter))(
                $(QuoteNode(name)), $type)))
    end
    control_locals = Dict{Symbol,Symbol}()
    function control_value(expression, kind::Symbol)
        expression === nothing && return nothing
        if expression isa Symbol && expression in parameter_names
            return declaration_locals[expression]
        elseif kind === :prefix && _lm_call(expression, :count) &&
                length(expression.args) == 2 && expression.args[2] isa Symbol
            name = expression.args[2]
            local_name = get!(control_locals, name) do
                generated = gensym(name)
                push!(let_bindings, :($generated = $name))
                generated
            end
            return :($(GlobalRef(LocalMath, :CollectionCount))($local_name))
        elseif expression isa Symbol
            return get!(control_locals, expression) do
                generated = gensym(expression)
                push!(let_bindings, :($generated = $expression))
                generated
            end
        end
        _lm_error("$kind must name a descriptor or declared parameter",
            source; actual = expression)
    end
    accesses = Pair{Symbol,Any}[]
    for read in reads
        if read isa _LocalMathReadSyntax
            relation = read.relation === nothing ? identity_local :
                relation_locals[read.relation]
            push!(accesses, read.role => :($(GlobalRef(LocalMath, :Access))(
                $(field_locals[read.field]), $relation;
                required=$(read.mode === :required))))
        elseif read.mode === :group
            push!(accesses, read.role =>
                :($(GlobalRef(LocalMath, :CollectionAccess))(
                    $(collection_locals[read.collection]),
                    $(GlobalRef(LocalMath, :BoundedGroup))($(read.argument)))))
        else
            push!(accesses, read.role =>
                :($(GlobalRef(LocalMath, :SourcePositionAccess))(
                    $(collection_locals[read.collection]), $(read.argument))))
        end
    end

    evaluator_prefix = Any[]
    if cartesian
        function contains_coordinate(value)
            value isa Symbol && return value in binder_symbols
            value isa Expr || return false
            return any(contains_coordinate, value.args)
        end
        authored_values = Any[evaluator_statements...]
        append!(authored_values, [publication.value for publication in publications
            if publication.value !== nothing])
        any(contains_coordinate, authored_values) && _lm_error(
            "Cartesian coordinates may currently appear only in Field indices",
            source; actual = binder_symbols)
    end
    for (index, declaration) in enumerate(declarations)
        push!(evaluator_prefix,
            :($(declaration.args[1]) = getfield($parameters_symbol, $index)))
    end
    results = Pair{Symbol,Any}[]
    publication_expressions = Any[]
    for publication in publications
        if publication.law === :ordered_state
            law_local = gensym(:ordered_law)
            state_pairs = publication.options.state_pairs
            state_components = Pair{Symbol,Any}[
                first(pair) => (first(pair) === last(pair) ?
                    :($(GlobalRef(LocalMath, :FoldComponent))(
                        $(field_locals[first(pair)]); in_place=true)) :
                    :($(GlobalRef(LocalMath, :FoldComponent))(
                        $(field_locals[first(pair)]);
                        from=$(field_locals[last(pair)])))) for pair in state_pairs]
            state = Expr(:call, GlobalRef(LocalMath, :InitializedState),
                Expr(:parameters, (Expr(:kw, name, value)
                    for (name, value) in state_components)...))
            function ordered_value_type(value)
                value === binder && return :Int32
                value isa Symbol && haskey(evaluator_type_aliases, value) &&
                    return ordered_value_type(evaluator_type_aliases[value])
                if value isa Expr && value.head === :ref &&
                        length(value.args) >= 2 && value.args[1] isa Symbol &&
                        haskey(field_locals, value.args[1])
                    return :(eltype($(field_locals[value.args[1]])))
                elseif value isa Expr && value.head === :ref &&
                        length(value.args) == 2
                    return :(eltype($(ordered_value_type(value.args[1]))))
                elseif value isa Expr && value.head === :. &&
                        length(value.args) == 2 &&
                        value.args[2] isa QuoteNode
                    return :(fieldtype($(ordered_value_type(value.args[1])),
                        $(value.args[2])))
                elseif value isa Expr && value.head === :tuple
                    types = map(ordered_value_type, value.args)
                    return :(Tuple{$(types...)})
                end
                _lm_error("@ordered key and identity types must come from the binder or Field reads",
                    source; actual=value)
            end
            by = publication.options.by
            value_type = publication.options.source_ordered ? :Int32 :
                :(Tuple{$(ordered_value_type(by.args[1])),
                    $(ordered_value_type(by.args[2]))})
            transition = publication.options.transition
            order = publication.options.source_ordered ?
                :($(GlobalRef(LocalMath, :source_order))()) :
                :($(GlobalRef(LocalMath, :canonical_by))(
                    $(GlobalRef(LocalMath, :_AuthoringOrderKey))(),
                    $(GlobalRef(LocalMath, :_AuthoringOrderIdentity))()))
            push!(let_bindings, Expr(:(=), law_local,
                :($(GlobalRef(LocalMath, :OrderedFold))($value_type, $state,
                    $transition; order=$order))))
            origin = :($(GlobalRef(LocalMath, :SourceOrigin))(
                $(String(source.file)), $(publication.line)))
            role = :($(GlobalRef(LocalMath, :PublicationValue))(
                $(QuoteNode(publication.port))))
            component = :($(GlobalRef(LocalMath, :FoldPublication))(
                $role))
            value = :($(GlobalRef(LocalMath, :_authoring_fold))(
                $(publication.value)))
            push!(results, publication.port => value)
            push!(publication_expressions,
                :($(GlobalRef(LocalMath, :Publication))(
                    ($component,), $law_local, $origin)))
            continue
        end
        relation = publication.relation === nothing ? identity_local :
            relation_locals[publication.relation]
        target = field_locals[publication.field]
        width = publication.relation === nothing ? 1 :
            :($(GlobalRef(LocalMath, :degree_bound))($relation))
        maximum = get(publication.options, :maximum, width)
        origin = :($(GlobalRef(LocalMath, :SourceOrigin))(
            $(String(source.file)), $(publication.line)))
        role = :($(GlobalRef(LocalMath, :PublicationValue))(
            $(QuoteNode(publication.port))))
        if publication.law === :collect
            record_type = :(getfield($record_types_symbol,
                $(findfirst(==(publication.field), collection_targets))))
            component = :($(GlobalRef(LocalMath, :CollectionPublication))(
                $target, $role))
            value = haskey(publication.options, :group) ?
                :($(GlobalRef(LocalMath, :_authoring_keyed_collect))(
                    $(publication.options.group), $(publication.value),
                    $(get(publication.options, :when, true)), $record_type)) :
                :($(GlobalRef(LocalMath, :_authoring_collect))(
                    $(publication.value),
                    $(get(publication.options, :when, true)), $record_type))
            groups = haskey(publication.options, :group) ?
                :($(GlobalRef(LocalMath, :_routed_groups))(
                    $(get(publication.options, :groups, 1)))) :
                :($(GlobalRef(LocalMath, :one_group))())
            order = :($(GlobalRef(LocalMath, :_authoring_collect_order))(
                $(get(publication.options, :order, QuoteNode(:source)))))
            projection = :($(GlobalRef(LocalMath, :_authoring_collect_projection))(
                $(get(publication.options, :projection, QuoteNode(:none)))))
            law = :($(GlobalRef(LocalMath, :Collect))(
                eltype($target); maximum=$(publication.options.maximum),
                groups=$groups, order=$order, projection=$projection))
        else
            component = :($(GlobalRef(LocalMath, :FieldPublication))(
                $target, $relation, $role))
            if publication.law === :unique
                value = haskey(publication.options, :key) ?
                    :($(GlobalRef(LocalMath, :_authoring_routed_unique))(
                        $(publication.options.key), $(publication.value),
                        $(get(publication.options, :when, true)))) :
                    publication.relation === nothing ?
                    :($(GlobalRef(LocalMath, :_authoring_unique_scalar))(
                        $(publication.value))) :
                    :($(GlobalRef(LocalMath, :_authoring_unique))(
                        $(publication.value)))
                law = haskey(publication.options, :key) ?
                    :($(GlobalRef(LocalMath, :Unique))(
                        eltype($target); maximum=$maximum,
                        coverage=$(GlobalRef(LocalMath, :PartialCoverage))(),
                        onempty=$(GlobalRef(LocalMath, :PreserveEmpty))())) :
                    (source_mode === :interior || any(option !== nothing for option in
                        (stage_options.prefix, stage_options.mask,
                         stage_options.subset, stage_options.when))) ?
                    :($(GlobalRef(LocalMath, :Unique))(
                        eltype($target); maximum=$maximum,
                        coverage=$(GlobalRef(LocalMath, :PartialCoverage))(),
                        onempty=$(GlobalRef(LocalMath, :PreserveEmpty))())) :
                    :($(GlobalRef(LocalMath, :Unique))(
                        eltype($target); maximum=$maximum))
            elseif publication.law === :reduce
                value = haskey(publication.options, :key) ?
                    :($(GlobalRef(LocalMath, :_authoring_routed_reduce))(
                        $(publication.options.key), $(publication.value),
                        $(get(publication.options, :when, true)))) :
                    publication.relation === nothing ?
                    :($(GlobalRef(LocalMath, :_authoring_reduce_scalar))(
                        $(publication.value),
                        $(get(publication.options, :when, true)))) :
                    :($(GlobalRef(LocalMath, :_authoring_reduce))(
                        $(publication.value),
                        $(get(publication.options, :when, true))))
                operation = get(publication.options, :op, :+)
                seed_option = get(publication.options, :seed,
                    get(publication.options, :onempty, :existing))
                seed_kind = _lm_literal_symbol(seed_option)
                seed = seed_kind in (:existing, :preserve) ?
                    :($(GlobalRef(LocalMath, :ExistingSeed))()) :
                    :($(GlobalRef(LocalMath, :IdentitySeed))($seed_option))
                order_option = get(publication.options,
                    :order, QuoteNode(:canonical))
                order = :($(GlobalRef(LocalMath, :_authoring_reduce_order))(
                    $order_option))
                law = :($(GlobalRef(LocalMath, :Reduce))(
                    eltype($target), $operation; maximum=$maximum,
                    seed=$seed, order=$order))
            else
                options = publication.options
                tie_option = get(options, :tie, QuoteNode(:canonical))
                explicit_tie = _lm_literal_symbol(tie_option) !== :canonical
                if explicit_tie
                    value = :($(GlobalRef(LocalMath, :_authoring_resolve_tied))(
                        $(options.score), $tie_option, $(options.payload),
                        $(get(options, :when, true))))
                    haskey(options, :key) && (value =
                        :($(GlobalRef(LocalMath, :_authoring_routed_resolve_tied))(
                            $(options.key), $(options.score), $tie_option,
                            $(options.payload), $(get(options, :when, true)))))
                else
                    value = :($(GlobalRef(LocalMath, :_authoring_resolve))(
                        $(options.score), $(options.payload),
                        $(get(options, :when, true))))
                    haskey(options, :key) && (value =
                        :($(GlobalRef(LocalMath, :_authoring_routed_resolve))(
                            $(options.key), $(options.score), $(options.payload),
                            $(get(options, :when, true)))))
                end
                sense_option = get(options, :sense, QuoteNode(:min))
                direction = :($(GlobalRef(LocalMath, :_authoring_resolve_sense))(
                    $sense_option))
                tie = explicit_tie ?
                    begin
                        tie_types = map(options._tie_fields) do field
                            type = :(eltype($(field_locals[field.field])))
                            for property in field.properties
                                type = :(fieldtype($type, $(QuoteNode(property))))
                            end
                            type
                        end
                        tie_type = length(tie_types) == 1 ? only(tie_types) :
                            :(Tuple{$(tie_types...)})
                        :($(GlobalRef(LocalMath, :TieMin)){$tie_type}())
                    end :
                    :($(GlobalRef(LocalMath, :CanonicalSourceLaneTie))())
                empty_option = get(options, :onempty, QuoteNode(:preserve))
                onempty = _lm_literal_symbol(empty_option) === :preserve ?
                    :($(GlobalRef(LocalMath, :PreserveEmpty))()) :
                    :($(GlobalRef(LocalMath, :FillEmpty))($empty_option))
                law = :($(GlobalRef(LocalMath, :Resolve))(
                    typeof($(options.lower)), eltype($target); maximum=$maximum,
                    direction=$direction, lower=$(options.lower),
                    upper=$(options.upper),
                    tie=$tie,
                    onempty=$onempty))
            end
        end
        push!(results, publication.port => value)
        push!(publication_expressions,
            :($(GlobalRef(LocalMath, :Publication))(($component,), $law, $origin)))
    end
    evaluator_body = Expr(:block, evaluator_prefix..., evaluator_statements...,
        :(return $(_lm_namedtuple(results))))
    evaluator_arguments = isempty(collection_targets) ?
        Expr(:tuple, item_symbol, reads_symbol, parameters_symbol) :
        Expr(:tuple, item_symbol, reads_symbol, parameters_symbol,
            record_types_symbol)
    evaluator = Expr(:->, evaluator_arguments, evaluator_body)
    if !isempty(collection_targets)
        collections = Expr(:tuple,
            (field_locals[name] for name in collection_targets)...)
        evaluator = :($(GlobalRef(LocalMath, :_authoring_typed_evaluator))(
            $collections, $evaluator))
    end
    evaluator_spec = :($(GlobalRef(LocalMath, :Evaluator))(
        $evaluator, ($(map(name -> declaration_locals[name], parameter_names)...),)))
    prefix = control_value(stage_options.prefix, :prefix)
    mask = control_value(stage_options.mask, :mask)
    subset = control_value(stage_options.subset, :subset)
    gate = control_value(stage_options.when, :when)
    control = :($(GlobalRef(LocalMath, :Control))(;
        prefix=$prefix, mask=$mask, subset=$subset, gate=$gate))
    stage_origin = :($(GlobalRef(LocalMath, :SourceOrigin))(
        $(String(source.file)), $(source.line);
        label=$(label === nothing ? nothing : QuoteNode(label))))
    stage = :($(GlobalRef(LocalMath, :Stage))($source_local,
        $(_lm_namedtuple(accesses)), ($(publication_expressions...),),
        $evaluator_spec, $control, $stage_origin))
    return Expr(:let, Expr(:block, let_bindings...),
        :($(GlobalRef(LocalMath, :LocalLaw))($stage)))
end

function _lm_expand(args, source)
    if length(args) == 2
        spec, body = args
        body isa Expr && body.head === :block ||
            _lm_error("@localmath requires a begin/end body", source; actual = body)
        return _lm_stage(spec, body, source)
    elseif length(args) == 1
        body = only(args)
        if body isa Expr && body.head === :function
            # A transparent scalar definition is deliberately just an
            # ordinary Julia method. Calling it with symbolic values traces
            # its scalar body; calling it with concrete values specializes
            # normally. LocalMath stores no operator node or registry entry.
            return body
        end
        body isa Expr && body.head === :block ||
            _lm_error("@localmath requires a binder or @stage block", source;
                actual = body)
        works = Any[]
        for statement in body.args
            statement isa LineNumberNode && continue
            statement isa Expr && statement.head === :macrocall &&
                statement.args[1] === Symbol("@stage") ||
                _lm_error("multi-stage @localmath accepts only @stage blocks",
                    source; actual = statement)
            invocation, stage_body = statement.args[3], statement.args[4]
            invocation isa Expr && invocation.head === :call &&
                invocation.args[1] isa Symbol || _lm_error(
                    "@stage requires `name(item ∈ source; ...)`", source;
                    actual = invocation)
            label = invocation.args[1]
            stage_spec = length(invocation.args) == 2 ? invocation.args[2] :
                Expr(:tuple, invocation.args[2:end]...)
            push!(works, _lm_stage(stage_spec, stage_body, source; label))
        end
        isempty(works) && _lm_error("@localmath requires at least one @stage",
            source)
        return :($(GlobalRef(LocalMath, :sequence))($(works...)))
    end
    _lm_error("@localmath accepts a function definition, one binder and body, or a stage block",
        source; actual = args)
end

"""
    @localmath (i ∈ space; parameters=..., mask=..., subset=..., when=...) begin
        ...
    end
    @localmath begin
        @stage name(i ∈ space; ...) begin ... end
        ...
    end
    @localmath function scalar_operation(args...)
        ...
    end

Lower mathematical notation directly to typed `LocalLaw`, `Stage`, `Access`,
and `Publication` values. One-, two-, and three-dimensional binders are
supported; Cartesian offsets require `interior(space, width)` or
`periodic(space)`.

`field[i]` and `field[relation(i)]` are required reads. Use `samples(...)` for
presence-aware lanes and `indices(...)` for canonical endpoint identities.
Assignments lower to `Unique`, `+=` to deterministic `Reduce`, and the closed
forms `reduce_to`, `resolve_to`, `bounded_collect`, and `publish` expose their
full laws. Several equations are ports of one evaluation. `@stage` blocks form
an ordered finite sequence, and collection consumers use `bounded(...)`,
`count(...)`, and `source_position(...)`.

`@ordered (by=..., state=(target => initial, ...)) begin ... end` expresses a
bounded recurrence; `halt_when(condition)` requests early termination. Stage
controls include typed parameters, prefixes, masks, subsets, and gates.
Transparent function definitions emit ordinary Julia methods usable with both
concrete and symbolic values.

The language rejects unbounded loops, dynamic allocation, arbitrary mutation,
captured arrays, host callbacks, foreign macros, and runtime symbolic
interpretation. The macro creates no alternate executor or runtime syntax
tree.
"""
macro localmath(args...)
    return esc(_lm_expand(args, __source__))
end
