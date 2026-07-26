struct CommittedSnapshot
    schema::AbstractSchema
    entries::Tuple{Vararg{Pair{Path,Any}}}
    version::UInt64
    time::LogicalTime
    parent_fingerprint::Union{Nothing,String}
    topology_fingerprint::String
end

struct Projection
    snapshot_version::UInt64
    snapshot_fingerprint::String
    entries::Tuple{Vararg{Pair{Path,Any}}}
end

function _normalize_values(values)
    normalized = Dict{Path,Any}()
    for (key, value) in pairs(values)
        target = key isa Path ? key :
            key isa Tuple ? path(key...) :
            key isa Union{AbstractString,Symbol} ? path(key) :
            _fail(:invalid_store_path, "state keys must be Path, Tuple, String, or Symbol";
                key_type=string(typeof(key)))
        haskey(normalized, target) &&
            _fail(:duplicate_store_path, "state path appears more than once"; target)
        normalized[target] = value
    end
    normalized
end

function _realize_entries(schema::AbstractSchema, values)
    supplied = _normalize_values(values)
    leaves = schema_leaves(schema)
    allowed = Set(first.(leaves))
    unknown = setdiff(Set(keys(supplied)), allowed)
    isempty(unknown) ||
        _fail(:unknown_store_path, "initial state includes undeclared paths";
            paths=sort!(collect(unknown)))

    entries = Pair{Path,Any}[]
    for (target, leaf) in leaves
        value = if haskey(supplied, target)
            supplied[target]
        elseif !(leaf.default isa NoDefault)
            deepcopy(leaf.default)
        elseif leaf.required
            _fail(:missing_required_state, "required state leaf has no value"; target)
        else
            nothing
        end
        isnothing(value) && !leaf.required || validate_value(leaf, value)
        push!(entries, target => deepcopy(value))
    end
    sort!(entries; by=first)
    tuple(entries...)
end

function initial_snapshot(schema::AbstractSchema, values;
    time::LogicalTime,
    topology_fingerprint::AbstractString=canonical_fingerprint((:static_topology_v1, schema)),
)
    CommittedSnapshot(schema, _realize_entries(schema, values), 0x0000000000000000,
        time, nothing, String(topology_fingerprint))
end

function _entry(snapshot::Union{CommittedSnapshot,Projection}, target::Path)
    position = findfirst(pair -> first(pair) == target, snapshot.entries)
    isnothing(position) && _fail(:unknown_store_path, "path is not present in snapshot"; target)
    last(snapshot.entries[position])
end

Base.getindex(snapshot::Union{CommittedSnapshot,Projection}, target::Path) =
    deepcopy(_entry(snapshot, target))
Base.haskey(snapshot::Union{CommittedSnapshot,Projection}, target::Path) =
    any(pair -> first(pair) == target, snapshot.entries)
paths(snapshot::Union{CommittedSnapshot,Projection}) = first.(snapshot.entries)
commit_id(snapshot::CommittedSnapshot) = snapshot.version
logical_time(snapshot::CommittedSnapshot) = snapshot.time

function materialize(snapshot::Union{CommittedSnapshot,Projection})
    Dict(target => deepcopy(value) for (target, value) in snapshot.entries)
end

function snapshot_fingerprint(snapshot::CommittedSnapshot)
    canonical_fingerprint((
        :committed_snapshot_v1,
        snapshot.version,
        snapshot.time,
        canonical_fingerprint(snapshot.schema),
        snapshot.entries,
        snapshot.parent_fingerprint,
        snapshot.topology_fingerprint,
    ))
end

function project(snapshot::CommittedSnapshot, requested::Path...)
    selected = if isempty(requested)
        snapshot.entries
    else
        chosen = Set(requested)
        missing = setdiff(chosen, Set(paths(snapshot)))
        isempty(missing) ||
            _fail(:unknown_projection_path, "projection requested undeclared state"; paths=missing)
        tuple((target => deepcopy(value) for (target, value) in snapshot.entries
            if target in chosen)...)
    end
    Projection(snapshot.version, snapshot_fingerprint(snapshot), selected)
end

function project(snapshot::CommittedSnapshot, prefix::Path; recursive::Bool)
    recursive || return project(snapshot, prefix)
    selected = tuple((target => deepcopy(value) for (target, value) in snapshot.entries
        if isprefixpath(prefix, target))...)
    isempty(selected) &&
        _fail(:empty_projection, "path prefix selected no state"; prefix)
    Projection(snapshot.version, snapshot_fingerprint(snapshot), selected)
end

function _committed_snapshot(
    previous::CommittedSnapshot,
    entries::Tuple,
    time::LogicalTime,
)
    time.scale == previous.time.scale ||
        _fail(:time_scale_mismatch, "commits must retain the compiled time scale")
    time.tick >= previous.time.tick ||
        _fail(:time_regression, "commit time cannot move backwards")
    CommittedSnapshot(previous.schema, entries,
        Base.Checked.checked_add(previous.version, UInt64(1)), time,
        snapshot_fingerprint(previous), previous.topology_fingerprint)
end

function _canonical(io::IO, snapshot::CommittedSnapshot)
    write(io, "CS")
    _canonical(io, snapshot.version)
    _canonical(io, snapshot.time)
    _canonical(io, snapshot.schema)
    _canonical(io, snapshot.entries)
    _canonical(io, snapshot.parent_fingerprint)
    _canonical(io, snapshot.topology_fingerprint)
end
