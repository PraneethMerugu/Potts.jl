# Centrally admitted generic local-operation mechanisms. This file contains
# only backend-neutral KernelAbstractions kernels and validation/lowering code;
# domain physics and provider-specific execution remain outside LocalWorksets.

struct _DirectIndependentLowering{O, P, R, T, D}
    outputs::O
    operation::P
    reads::R
    topology::T
    destination_counts::D
    item_count::Int
    lowering_identity::Symbol
end

mutable struct _PreparedDirectIndependent{K, R}
    apply_kernel::K
    device_routes::R
end

_static_topology_payload(lowering::_DirectIndependentLowering) = (
    routes = lowering.topology.routes,
)

_workspace_spec(::_DirectIndependentLowering, work) = ()

@inline _emission_value(emission::_Emission) = emission.value
@inline _emission_value(emission::_ConditionalEmission) = emission.value
@inline _emission_enabled(::_Emission) = true
@inline _emission_enabled(emission::_ConditionalEmission) = emission.when
@inline _candidate_rank(candidate::_Candidate) = candidate.rank
@inline _candidate_rank(candidate::_ConditionalCandidate) = candidate.rank
@inline _candidate_value(candidate::_Candidate) = candidate.value
@inline _candidate_value(candidate::_ConditionalCandidate) = candidate.value
@inline _candidate_enabled(::_Candidate) = true
@inline _candidate_enabled(candidate::_ConditionalCandidate) = candidate.when

@inline _emission_lane(
    emission::Union{_Emission, _ConditionalEmission}, ::Val{1}, ::Val{1}
) = emission
@inline _emission_lane(
    candidate::Union{_Candidate, _ConditionalCandidate}, ::Val{1}, ::Val{1}
) = candidate
@inline _emission_lane(emissions::Tuple, ::Val{K}, ::Val{I}) where {K, I} =
    @inbounds emissions[I]

@generated function _publish_independent!(
        declarations::D,
        outputs::O,
        routes::R,
        result::V,
        item::Int32,
    ) where {
        D <: NamedTuple, O <: NamedTuple, R <: NamedTuple, V <: NamedTuple,
    }
    declaration_names = D.parameters[1]
    output_names = O.parameters[1]
    route_names = R.parameters[1]
    result_names = V.parameters[1]
    declaration_names == output_names == route_names == result_names || return :(
        error("validated independent output names changed during execution")
    )
    declarations = D.parameters[2].parameters
    result_types = V.parameters[2].parameters
    expressions = Expr[]
    for (port_index, name) in pairs(output_names)
        declaration = declarations[port_index]
        declaration <: _IndependentOutput || return :(
            error("non-independent port reached the direct lowering")
        )
        maximum = declaration.parameters[2]
        port_result = result_types[port_index]
        homogeneous_tuple = maximum > 1 && port_result <: Tuple &&
            length(port_result.parameters) == maximum &&
            all(==(first(port_result.parameters)), port_result.parameters)
        if homogeneous_tuple
            full_unconditional = declaration.parameters[4] === :all &&
                first(port_result.parameters) <: _Emission
            publication = full_unconditional ? quote
                # Planning proves this branch contains no zero destinations,
                # and preparation freezes/copies the validated route.
                @inbounds port_output[destination] = emission.value
            end : quote
                if destination != 0 && _emission_enabled(emission)
                    @inbounds port_output[destination] =
                        _emission_value(emission)
                end
            end
            push!(expressions, quote
                local emissions = getproperty(result, $(QuoteNode(name)))
                local port_routes = getproperty(
                    routes, $(QuoteNode(name))
                )
                local port_output = getproperty(
                    outputs, $(QuoteNode(name))
                )
                for lane in 1:$maximum
                    local emission = @inbounds emissions[lane]
                    local destination = Int(
                        @inbounds port_routes[lane, item]
                    )
                    $publication
                end
            end)
            continue
        end
        for lane in 1:maximum
            push!(expressions, quote
                local emission = _emission_lane(
                    getproperty(result, $(QuoteNode(name))),
                    Val($maximum),
                    Val($lane),
                )
                local destination = Int(@inbounds getproperty(
                    routes, $(QuoteNode(name))
                )[$lane, item])
                if destination != 0 && _emission_enabled(emission)
                    @inbounds getproperty(
                        outputs, $(QuoteNode(name))
                    )[destination] = _emission_value(emission)
                end
            end)
        end
    end
    return Expr(:block, expressions..., :(nothing))
end

@kernel function _direct_independent_kernel!(
        operation,
        reads,
        values,
        declarations,
        outputs,
        routes,
        active_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= active_count
        result = operation(Int32(item), reads, values)
        _publish_independent!(
            declarations, outputs, routes, result, Int32(item)
        )
    end
end

function _generic_topology_header(work, topology)
    required = (:epoch, :item_count, :routes, :destination_counts)
    invoke(
        _require_properties,
        Tuple{Any, Tuple, Any},
        topology,
        required,
        :generic_topology,
    )
    topology.routes isa NamedTuple || throw(LocalWorkValidationError(
        "generic topology routes must be a named tuple"
    ))
    topology.destination_counts isa NamedTuple || throw(
        LocalWorkValidationError(
            "generic topology destination_counts must be a named tuple"
        )
    )
    invoke(
        _validate_topology_epoch,
        Tuple{Any, Any},
        topology,
        :generic,
    )
    item_count = invoke(
        _bounded_count,
        Tuple{Any, Any},
        topology.item_count,
        :generic_item_count,
    )
    invoke(
        _validate_item_domain,
        Tuple{LocalWork, Int, Any},
        work,
        item_count,
        :generic_topology,
    )
    return item_count
end

function _validate_independent_route(
        work, topology, name, output::_IndependentOutput{T, K, R, C},
        item_count,
    ) where {T, K, R, C}
    route, destination_count = invoke(
        _validate_dense_route,
        Tuple{Any, Symbol, Any, Int},
        topology,
        name,
        output,
        item_count;
        context = :independent,
        terminal_capacity = false,
    )
    destinations = Int[]
    sizehint!(destinations, length(route))
    for value in route
        destination = Int(value)
        destination == 0 || push!(destinations, destination)
    end
    length(unique(destinations)) == length(destinations) || throw(
        LocalWorkValidationError(
            "independent port $name has competing potential writers"
        )
    )
    if C === :all
        work.active === nothing || throw(LocalWorkValidationError(
            "full-coverage independent work cannot use active truncation"
        ))
        all(!=(Int32(0)), route) || throw(LocalWorkValidationError(
            "full-coverage independent port $name cannot contain a no-emission destination zero";
            stage = :plan,
            contract = :independent_output_coverage,
            port = name,
            expected = :strictly_positive_exact_permutation,
            actual = :contains_zero,
            hint = "use coverage=:partial when a fixed lane may emit nothing",
        ))
        length(destinations) == destination_count &&
            sort(destinations) == collect(1:destination_count) || throw(
                LocalWorkValidationError(
                    "full-coverage independent port $name must be an exact destination permutation";
                    stage = :plan,
                    contract = :independent_output_coverage,
                    port = name,
                    expected = collect(1:destination_count),
                    actual = sort(destinations),
                )
            )
    end
    return route, destination_count
end

function _lower_direct_independent(work::LocalWork, topology, backend)
    isempty(work.outputs) && throw(LocalWorkValidationError(
        "generic local work requires at least one output port"
    ))
    all(output -> output isa _IndependentOutput, values(work.outputs)) ||
        throw(LocalWorkValidationError(
            "the current generic lowering admits independent ports only"
        ))
    isbitstype(typeof(work.operation)) || throw(LocalWorkValidationError(
        "generic local-work operations must be concrete isbits callables"
    ))
    item_count = invoke(
        _generic_topology_header, Tuple{Any, Any}, work, topology
    )
    validated = map(keys(work.outputs)) do name
        output = getproperty(work.outputs, name)
        invoke(
            _validate_independent_route,
            Tuple{Any, Any, Any, _IndependentOutput, Any},
            work, topology, name, output, item_count,
        )
    end
    route_tuple = NamedTuple{keys(work.outputs)}(first.(validated))
    destination_counts = NamedTuple{keys(work.outputs)}(last.(validated))
    for (name, output) in pairs(work.outputs)
        invoke(
            _centrally_qualified_value_capability,
            Tuple{Any, Type, Symbol, Symbol},
            backend, output.value_type, :store, :global,
        ) || throw(LocalWorkValidationError(
            "backend x output type x store operation x address space is not qualified";
            stage = :plan, contract = :backend_capability,
            port = name,
            expected = :centrally_qualified_store,
            actual = (
                backend = typeof(backend),
                value_type = output.value_type,
                operation = :store,
                address_space = :global,
            ),
        ))
    end
    return _DirectIndependentLowering(
        work.outputs,
        work.operation,
        work.reads,
        merge(topology, (; routes = route_tuple)),
        destination_counts,
        item_count,
        :direct_independent_v1,
    )
end

function _lower_generic(work::LocalWork, topology, backend)
    all(output -> output isa _IndependentOutput, values(work.outputs)) &&
        return invoke(
            _lower_direct_independent,
            Tuple{LocalWork, Any, Any},
            work,
            topology,
            backend,
        )
    all(
        output -> output isa Union{
            _IndependentOutput, _CombinedOutput, _GenericResolvedOutput,
        },
        values(work.outputs),
    ) || throw(LocalWorkValidationError(
        "the generic lowering does not admit this output-family combination"
    ))
    return invoke(
        _lower_combined,
        Tuple{LocalWork, Any, Any},
        work,
        topology,
        backend,
    )
end

function _topology_fingerprint(topology, lowering::_DirectIndependentLowering)
    io = IOBuffer()
    write(io, Int64(lowering.item_count))
    write(io, UInt64(invoke(_topology_epoch, Tuple{Any}, topology)))
    for name in keys(lowering.outputs)
        write(io, String(name))
        write(io, Int64(getproperty(lowering.destination_counts, name)))
        route = getproperty(lowering.topology.routes, name)
        write(io, Int64(size(route, 1)))
        write(io, Int64(size(route, 2)))
        for value in route
            write(io, value)
        end
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

function _required_bindings(lowering::_DirectIndependentLowering, work)
    return invoke(
        _unique_symbols,
        Tuple{Any},
        (collect(values(work.reads))..., collect(keys(work.outputs))...),
    )
end

function _binding_access(lowering::_DirectIndependentLowering, work)
    names = invoke(
        _required_bindings,
        Tuple{_DirectIndependentLowering, Any},
        lowering,
        work,
    )
    output_names = keys(work.outputs)
    return NamedTuple{names}(map(
        name -> name in output_names ? :write : :read, names
    ))
end

function _scalar_value_type(schema::NamedTuple)
    names = Tuple(
        name for (name, slot) in pairs(schema) if slot isa _ValueSlot
    )
    types = Tuple(
        typeof(slot).parameters[1] for slot in values(schema)
        if slot isa _ValueSlot
    )
    return NamedTuple{names, Core.apply_type(Tuple, types...)}
end

function _operation_read_type(storage, schema, name)
    hasproperty(storage, name) && return typeof(getproperty(storage, name))
    hasproperty(schema, name) || throw(LocalWorkValidationError(
        "generic operation read $name has no static or submission binding"
    ))
    slot = getproperty(schema, name)
    slot isa _StorageSlot || throw(LocalWorkValidationError(
        "generic operation read $name requires a storage_slot"
    ))
    return slot.array_type
end

function _operation_call_signature(work, storage, schema)
    read_type = NamedTuple{
        keys(work.reads),
        Core.apply_type(
            Tuple,
            map(
                name -> invoke(
                    _operation_read_type,
                    Tuple{Any, Any, Any},
                    storage,
                    schema,
                    name,
                ),
                values(work.reads),
            )...,
        ),
    }
    value_type = invoke(
        _scalar_value_type, Tuple{NamedTuple}, schema
    )
    return Tuple{Int32, read_type, value_type}
end

function _operation_result_type(work, storage, schema)
    signature = invoke(
        _operation_call_signature,
        Tuple{Any, Any, Any},
        work,
        storage,
        schema,
    )
    return Core.Compiler.return_type(work.operation, signature)
end

function _operation_callback_facts(operation, signature)
    wrapper = (
        callback = operation,
        signature,
        method = which(operation, signature),
        purpose = :local_operation,
    )
    operation isa _SingleOutputOperation || return (wrapper,)
    inner = operation.operation
    return (
        wrapper,
        (
            callback = inner,
            signature,
            method = which(inner, signature),
            purpose = :single_output_operation,
        ),
    )
end

function _operation_call_facts(
        lowering::_DirectIndependentLowering,
        work,
        storage,
        schema,
    )
    signature = invoke(
        _operation_call_signature,
        Tuple{Any, Any, Any},
        work,
        storage,
        schema,
    )
    return invoke(
        _operation_callback_facts,
        Tuple{Any, Any},
        work.operation,
        signature,
    )
end

function _emission_result_type(type, ::Val{1})
    return type
end

function _emission_result_type(type, ::Val{K}) where {K}
    type <: Tuple && length(type.parameters) == K || return nothing
    return type
end

function _validate_independent_result_type(work, result_type)
    result_type <: NamedTuple || throw(LocalWorkValidationError(
        "generic operation result must infer as a concrete NamedTuple";
        stage = :prepare, contract = :operation_result_form,
        expected = NamedTuple, actual = result_type,
    ))
    result_type === Union{} && throw(LocalWorkValidationError(
        "generic operation call has no inferred return"
    ))
    result_names = result_type.parameters[1]
    result_names == Base.keys(work.outputs) || throw(LocalWorkValidationError(
        "generic operation result names must exactly match output port names";
        stage = :prepare, contract = :operation_result_ports,
        expected = Base.keys(work.outputs), actual = result_names,
    ))
    result_types = result_type.parameters[2].parameters
    for (index, (name, output)) in enumerate(pairs(work.outputs))
        port_type = invoke(
            _emission_result_type,
            Tuple{Any, Val{typeof(output).parameters[2]}},
            result_types[index],
            Val(typeof(output).parameters[2]),
        )
        port_type === nothing && throw(LocalWorkValidationError(
            "output port :$(name) has the wrong fixed emission arity";
            stage = :prepare,
            contract = :operation_result_arity,
            port = name,
            expected = typeof(output).parameters[2],
            actual = result_types[index],
        ))
        lane_types = typeof(output).parameters[2] == 1 ?
            (port_type,) : port_type.parameters
        for lane_type in lane_types
            lane_type <: Union{_Emission, _ConditionalEmission} || throw(
                LocalWorkValidationError(
                    "independent output port :$(name) must use emit(value[, when])";
                    stage = :prepare,
                    contract = :operation_result_form,
                    port = name,
                    expected = Union{_Emission, _ConditionalEmission},
                    actual = lane_type,
                )
            )
            lane_type.parameters[1] === output.value_type || throw(
                LocalWorkValidationError(
                    "emitted value type for independent output port :$(name) must be $(output.value_type), got $(lane_type.parameters[1])";
                    stage = :prepare,
                    contract = :operation_result_value_type,
                    port = name,
                    expected = output.value_type,
                    actual = lane_type.parameters[1],
                )
            )
            coverage = typeof(output).parameters[4]
            coverage === :all && lane_type <: _ConditionalEmission && throw(
                LocalWorkValidationError(
                    "full-coverage independent output port :$(name) requires unconditional emissions";
                    stage = :prepare,
                    contract = :independent_output_coverage,
                    port = name, expected = :unconditional_emission,
                    actual = lane_type,
                )
            )
        end
    end
    return nothing
end

function _validate_binding_schema(
        lowering::_DirectIndependentLowering,
        work,
        storage,
        schema,
        backend,
    )
    requirements = Tuple(
        _binding_requirement(
            name,
            output.value_type,
            (getproperty(lowering.destination_counts, name),),
            :write;
            allow_readwrite = true,
            role = :independent_output,
        ) for (name, output) in pairs(work.outputs)
    )
    invoke(
        _validate_binding_requirements,
        Tuple{Any, Any, Tuple},
        storage,
        schema,
        requirements,
    )
    result_type = invoke(
        _operation_result_type,
        Tuple{Any, Any, Any},
        work, storage, schema,
    )
    invoke(
        _validate_independent_result_type,
        Tuple{Any, Any},
        work, result_type,
    )
    return nothing
end

function _validate_workspace(
        lowering::_DirectIndependentLowering, work, workspace, backend
    )
    return invoke(
        _validate_workspace_spec,
        Tuple{Any, Tuple, Any},
        workspace,
        invoke(
            _centrally_owned_workspace_spec,
            Tuple{Any, Any},
            lowering,
            work,
        ),
        backend,
    )
end

function _prepare_lowering(
        lowering::_DirectIndependentLowering,
        work,
        storage,
        workspace,
        backend,
    )
    payload = invoke(
        _centrally_owned_static_topology_payload,
        Tuple{Any},
        lowering,
    )
    device_payload = invoke(
        _centrally_copy_topology_payload,
        Tuple{Any, Any},
        backend,
        payload,
    )
    return _PreparedDirectIndependent(
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            _direct_independent_kernel!,
            backend,
        ),
        device_payload.routes,
    )
end

function _scalar_values(submission::NamedTuple, schema::NamedTuple)
    names = Tuple(
        name for (name, slot) in pairs(schema) if slot isa _ValueSlot
    )
    return NamedTuple{names}(map(
        name -> getproperty(submission, name), names
    ))
end

@generated function _scalar_values(submission::S) where {S <: NamedTuple}
    schema_names = S.parameters[1]
    schema_types = S.parameters[2].parameters
    names = Tuple(
        name for (name, type) in zip(schema_names, schema_types)
        if !(type <: AbstractArray)
    )
    values = map(
        name -> :(getproperty(submission, $(QuoteNode(name)))), names
    )
    return :(NamedTuple{$names}(($(values...),)))
end

function _execute_lowering!(
        runtime::_PreparedDirectIndependent,
        lowering::_DirectIndependentLowering,
        work,
        bindings,
        workspace,
        submission,
    )
    reads = NamedTuple{keys(work.reads)}(map(
        name -> getproperty(bindings, name), values(work.reads)
    ))
    outputs = NamedTuple{keys(work.outputs)}(map(
        name -> getproperty(bindings, name), keys(work.outputs)
    ))
    values_tuple = invoke(
        _scalar_values,
        Tuple{NamedTuple},
        submission,
    )
    active_count = work.active === nothing ? lowering.item_count :
                   Int(getproperty(submission, work.active))
    0 <= active_count <= lowering.item_count || throw(
        LocalWorkValidationError(
            "active selection exceeds the planned item capacity"
        )
    )
    runtime.apply_kernel(
        work.operation,
        reads,
        values_tuple,
        work.outputs,
        outputs,
        runtime.device_routes,
        Int32(active_count);
        ndrange = max(active_count, 1),
    )
    return 1
end

function _direct_determinism(backend, lowering)
    qualifier = (
        backend = nameof(typeof(backend)),
        lowering_identity = lowering.lowering_identity,
        publication = :topology_proved_disjoint,
    )
    guarantees = (
        :qualified_disjoint_publication,
        :qualified_disjoint_publication,
        :not_applicable,
        :qualified_disjoint_publication,
        :qualified_same_backend_operation,
        :not_claimed,
        :caller_operation_responsibility,
        :domain_owned,
    )
    return invoke(
        _determinism_report,
        Tuple{NamedTuple, NTuple{8, Symbol}},
        qualifier,
        guarantees,
    )
end

function _lowering_evidence(
        lowering::_DirectIndependentLowering, work, topology, backend
    )
    determinism = invoke(
        _direct_determinism,
        Tuple{Any, Any},
        backend,
        lowering,
    )
    ports = NamedTuple{keys(lowering.outputs)}(map(
        keys(lowering.outputs)
    ) do name
        output = getproperty(lowering.outputs, name)
        route = getproperty(lowering.topology.routes, name)
        invoke(
            _port_evidence,
            Tuple{
                Symbol, Any, Int, Int, Symbol, NamedTuple, Symbol,
                Symbol, Any, NamedTuple, NamedTuple,
            },
            :independent,
            output.route,
            getproperty(lowering.destination_counts, name),
            typeof(output).parameters[2],
            typeof(output).parameters[4],
            (
                kind = :independent,
                coverage = typeof(output).parameters[4],
            ),
            :apply_publish,
            :may_be_partially_visible,
            typeof(output).parameters[4] === :all ?
                :not_possible_by_total_coverage : :preserve_existing,
            determinism,
            (; route_bytes = invoke(
                _checked_int_product,
                Tuple{Integer, Integer, Any},
                sizeof(eltype(route)),
                length(route),
                Symbol(name, :_route_bytes),
            )),
        )
    end)
    transfer = invoke(
        _centrally_count_topology_payload_bytes,
        Tuple{Any},
        invoke(
            _centrally_owned_static_topology_payload,
            Tuple{Any},
            lowering,
        ),
    )
    return (
        family = :direct,
        lowering_identity = lowering.lowering_identity,
        launch_count = 1,
        phases = (:apply_publish,),
        workspace = (algorithmic_bytes = 0, ports = (;)),
        topology_transfer_bytes = transfer,
        capability = (
            backend = typeof(backend),
            compiler = invoke(
                _centrally_qualified_provider_compiler_identity,
                Tuple{Any}, backend,
            ),
            ports,
        ),
        determinism,
        ports,
    )
end

function _lowering_inspection(
        runtime::_PreparedDirectIndependent,
        lowering::_DirectIndependentLowering,
        work,
        workspace,
    )
    return (
        family = :direct,
        phases = (:apply_publish,),
        launches = 1,
        device_routes = keys(runtime.device_routes),
        operation_invocations = :once_per_active_item,
        algorithmic_workspace_arrays = (),
    )
end
