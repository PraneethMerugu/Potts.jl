struct CapabilitySet
    domains::Tuple{Vararg{Symbol}}
    purity::Symbol
    idempotent::Bool
    continuation_codec::Symbol
    replay_class::Symbol
    function CapabilitySet(
        domains=(:cpu,);
        purity::Symbol=:pure,
        idempotent::Bool=true,
        continuation_codec::Symbol=:canonical_v1,
        replay_class::Symbol=:exact,
    )
        normalized = tuple(sort!(unique!(Symbol[domains...]))...)
        isempty(normalized) &&
            _fail(:empty_capability_domains, "at least one execution domain is required")
        all(domain -> domain in (:cpu, :metal, :rocm, :cuda), normalized) ||
            _fail(:unknown_execution_domain, "capability declares an unknown domain";
                domains=normalized)
        purity in (:pure, :runtime_owned_effects, :external_effects) ||
            _fail(:unknown_purity_class, "unknown purity declaration"; purity)
        replay_class in (:exact, :numerical, :statistical, :unsupported) ||
            _fail(:unknown_replay_class, "unknown replay class"; replay_class)
        new(normalized, purity, idempotent, continuation_codec, replay_class)
    end
end

struct TransferDeclaration
    source::Symbol
    destination::Symbol
    max_bytes::Int
    cadence::Symbol
    precision::Symbol
    synchronization::Symbol
    function TransferDeclaration(
        source::Symbol,
        destination::Symbol;
        max_bytes::Integer,
        cadence::Symbol=:event,
        precision::Symbol=:exact,
        synchronization::Symbol=:batch_boundary,
    )
        source == destination &&
            _fail(:redundant_transfer, "transfer endpoints must differ"; source)
        max_bytes > 0 ||
            _fail(:unbounded_transfer, "transfer declarations need a positive byte bound";
                max_bytes)
        new(source, destination, Int(max_bytes), cadence, precision, synchronization)
    end
end

struct PreflightReport
    domains::Tuple{Vararg{Pair{String,Symbol}}}
    transfers::Tuple{Vararg{Pair{Tuple{String,Symbol},TransferDeclaration}}}
    fingerprint::String
end

function _canonical(io::IO, capability::CapabilitySet)
    write(io, "CA")
    _canonical(io, capability.domains)
    _canonical(io, capability.purity)
    _canonical(io, capability.idempotent)
    _canonical(io, capability.continuation_codec)
    _canonical(io, capability.replay_class)
end

function _canonical(io::IO, transfer::TransferDeclaration)
    write(io, "TR")
    _canonical(io, transfer.source)
    _canonical(io, transfer.destination)
    _canonical(io, transfer.max_bytes)
    _canonical(io, transfer.cadence)
    _canonical(io, transfer.precision)
    _canonical(io, transfer.synchronization)
end
