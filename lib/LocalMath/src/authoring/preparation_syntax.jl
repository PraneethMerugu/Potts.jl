const _PREPARE_OPTION_NAMES =
    (:backend, :workspace, :lease_capacity, :dependency_arity)

function _prepare_syntax_error(message, source; actual = nothing)
    throw(LocalMathValidationError(
        message;
        stage = :construct,
        contract = :prepare_syntax,
        origin = SourceOrigin(String(source.file), source.line),
        actual,
    ))
end

function _prepare_header_parts(header, source)
    parts = if header isa Expr && header.head === :tuple
        parameter_blocks = filter(
            value -> value isa Expr && value.head === :parameters,
            header.args,
        )
        length(parameter_blocks) == 1 || _prepare_syntax_error(
            "@prepare requires `(law; backend, ...)`", source;
            actual = header,
        )
        parameters = only(parameter_blocks)
        laws = filter(value -> value !== parameters, header.args)
        length(laws) == 1 || _prepare_syntax_error(
            "@prepare requires exactly one law expression", source;
            actual = laws,
        )
        (only(laws), Tuple(parameters.args))
    elseif header isa Expr && header.head === :block
        values = Tuple(value for value in header.args
            if !(value isa LineNumberNode))
        length(values) >= 2 || _prepare_syntax_error(
            "@prepare requires a law and an explicit backend", source;
            actual = header,
        )
        (first(values), Base.tail(values))
    else
        _prepare_syntax_error(
            "@prepare requires `(law; backend, ...)`", source;
            actual = header,
        )
    end

    law, declarations = parts
    options = Pair{Symbol,Any}[]
    for declaration in declarations
        name, value = if declaration isa Symbol
            (declaration, declaration)
        elseif declaration isa Expr &&
                declaration.head in (:kw, :(=)) &&
                length(declaration.args) == 2 &&
                declaration.args[1] isa Symbol
            (declaration.args[1], declaration.args[2])
        else
            _prepare_syntax_error(
                "@prepare options must be keyword assignments or shorthand names",
                source; actual = declaration,
            )
        end
        name in _PREPARE_OPTION_NAMES || _prepare_syntax_error(
            "unknown @prepare option", source; actual = name,
        )
        any(pair -> first(pair) === name, options) &&
            _prepare_syntax_error(
                "@prepare options must be unique", source; actual = name,
            )
        push!(options, name => value)
    end
    any(pair -> first(pair) === :backend, options) ||
        _prepare_syntax_error(
            "@prepare requires an explicit backend", source;
            actual = first.(options),
        )
    return law, Tuple(options)
end

function _prepare_allocation_expression(value, source)
    value isa Expr && value.head === :call &&
        !isempty(value.args) && value.args[1] === :allocate || return value
    length(value.args) in (1, 2) || _prepare_syntax_error(
        "allocate accepts zero or one argument", source; actual = value,
    )
    return Expr(:call, GlobalRef(LocalMath, :Allocate), value.args[2:end]...)
end

function _prepare_expand(header, body, source)
    body isa Expr && body.head === :block || _prepare_syntax_error(
        "@prepare requires a begin/end binding block", source; actual = body,
    )
    law, options = _prepare_header_parts(header, source)
    bindings = Any[]
    names = Symbol[]
    statement_source = source
    for statement in body.args
        if statement isa LineNumberNode
            statement_source = statement
            continue
        end
        statement isa Expr && statement.head === :(=) &&
            length(statement.args) == 2 || _prepare_syntax_error(
                "@prepare accepts only descriptor assignments",
                statement_source; actual = statement,
            )
        descriptor, storage = statement.args
        descriptor isa Symbol || _prepare_syntax_error(
            "the left side of an @prepare binding must be a bare descriptor name",
            statement_source; actual = descriptor,
        )
        descriptor in names && _prepare_syntax_error(
            "@prepare descriptor bindings must be unique",
            statement_source; actual = descriptor,
        )
        push!(names, descriptor)
        push!(bindings, :($descriptor =>
            $(_prepare_allocation_expression(storage, statement_source))))
    end
    isempty(bindings) && _prepare_syntax_error(
        "@prepare requires at least one descriptor binding", source,
    )
    keywords = Expr(:parameters,
        (Expr(:kw, first(option), last(option)) for option in options)...)
    return Expr(:call, GlobalRef(LocalMath, :prepare), keywords,
        law, bindings...)
end

"""
    @prepare (law; backend, workspace=nothing, lease_capacity=1,
              dependency_arity=0) begin
        input = input_array
        output = allocate(undef)
        initialized = allocate(value)
        copied = allocate(source_array)
        records = allocate()
    end

Associate explicit descriptor storage with a law and prepare it on one
KernelAbstractions backend. Direct arrays are borrowed without copying or
adaptation. `allocate(undef)` requests cold uninitialized Field storage and is
accepted only when definite initialization is proven; `allocate(value)` fills
an exact element value or copies an exact-shape source array; `allocate()`
creates the exact compacted Collection storage required by the law.

The backend is mandatory. The block accepts only bare descriptor assignments,
preserves their order, and evaluates the law, options, descriptors, and right
sides exactly once. Qualified `LocalMath.Allocate` and
`LocalMath.MutableRelationStorage` values pass through unchanged.

Domain compilers and dynamically assembled binding sets use the equivalent
Pair API: `prepare(law, descriptor => storage...; backend, ...)`. Neither form
infers outputs, initialization, topology, or a backend, and no setup syntax
survives into planning or execution.
"""
macro prepare(header, body)
    return esc(_prepare_expand(header, body, __source__))
end
