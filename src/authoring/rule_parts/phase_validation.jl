function _phase_diagnostics(components::Tuple)
    rules = Tuple(component for component in components if component isa Rule)
    isempty(rules) && return ()
    diagnostics = ()

    draw_addresses = Dict{UInt16, Vector{Tuple{SemanticName, Symbol}}}()
    for rule in rules, draw in _random_draws(rule.expression)
        label = something(draw.label, :draw)
        operation = UInt16(_semantic_rng_code(rule.name, label, UInt16(0x03ff)))
        identities = get!(draw_addresses, operation, Tuple{SemanticName, Symbol}[])
        identity = (rule.name, label)
        identity in identities || push!(identities, identity)
    end
    for (operation, identities) in draw_addresses
        length(identities) <= 1 && continue
        diagnostics = (diagnostics..., Diagnostic(:error,
            :random_draw_rng_identity_collision,
            "Level 1 random draws collide in the compiled RNG operation domain";
            related = (operation, identities...),
            correction = "rename one rule or draw label to obtain a distinct semantic address"))
    end

    phases = Dict{SemanticName, Tuple}()
    sources = Dict{SemanticName, Union{Nothing, SourceLocation}}()
    for rule in rules
        identity = rule.phase.name
        if haskey(phases, identity) && phases[identity] != rule.phase.after
            diagnostics = (diagnostics..., Diagnostic(:error,
                :inconsistent_phase_definition,
                "one phase identity has conflicting predecessor definitions";
                identity, related = (phases[identity], rule.phase.after),
                source = rule.source,
                correction = "reuse one Phase value for every rule in that phase"))
        else
            phases[identity] = rule.phase.after
            sources[identity] = rule.source
        end
    end

    rules_by_phase = Dict(identity => Tuple(rule for rule in rules
        if rule.phase.name == identity) for identity in keys(phases))
    for (identity, phase_rules) in rules_by_phase
        targets = Tuple(rule.target for rule in phase_rules)
        duplicates = Tuple(unique(target for target in targets
            if count(==(target), targets) > 1))
        isempty(duplicates) || (diagnostics = (diagnostics..., Diagnostic(
            :error, :duplicate_phase_writer,
            "one rule phase cannot write the same property more than once";
            identity, related = duplicates, source = sources[identity],
            correction = "combine the writers explicitly or place them in ordered phases"),))
    end

    function precedes(first_identity, second_identity, visited = Set{SemanticName}())
        first_identity == second_identity && return true
        second_identity in visited && return false
        push!(visited, second_identity)
        return any(dependency -> dependency == first_identity ||
            precedes(first_identity, dependency, visited),
            get(phases, second_identity, ()))
    end

    identities = sort!(collect(keys(phases)))
    for first_index in eachindex(identities)
        for second_index in (first_index + 1):length(identities)
            first_identity = identities[first_index]
            second_identity = identities[second_index]
            precedes(first_identity, second_identity) ||
                precedes(second_identity, first_identity) || begin
                first_rules = rules_by_phase[first_identity]
                second_rules = rules_by_phase[second_identity]
                first_writes = Set(rule.target for rule in first_rules)
                second_writes = Set(rule.target for rule in second_rules)
                first_reads = Set(identity for rule in first_rules
                    for identity in _expression_reads(rule.expression))
                second_reads = Set(identity for rule in second_rules
                    for identity in _expression_reads(rule.expression))
                hazard = !isempty(intersect(first_writes,
                    union(second_writes, second_reads))) ||
                    !isempty(intersect(second_writes,
                        union(first_writes, first_reads)))
                hazard && (diagnostics = (diagnostics..., Diagnostic(
                    :error, :unordered_phase_dependency,
                    "unordered rule phases have a read/write or write/write dependency";
                    identity = first_identity,
                    related = (second_identity,), source = sources[first_identity],
                    correction = "declare one phase `after` the other"),))
            end
        end
    end

    function visit(identity, active::Set{SemanticName}, complete::Set{SemanticName})
        identity in complete && return false
        identity in active && return true
        push!(active, identity)
        for dependency in get(phases, identity, ())
            visit(dependency, active, complete) && return true
        end
        delete!(active, identity)
        push!(complete, identity)
        return false
    end
    complete = Set{SemanticName}()
    for identity in keys(phases)
        visit(identity, Set{SemanticName}(), complete) || continue
        diagnostics = (diagnostics..., Diagnostic(:error, :phase_dependency_cycle,
            "rule phase dependencies must form a directed acyclic graph";
            identity, source = sources[identity],
            correction = "remove one dependency from the reported phase cycle"))
    end
    return diagnostics
end
