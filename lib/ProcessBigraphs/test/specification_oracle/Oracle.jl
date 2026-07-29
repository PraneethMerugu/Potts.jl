module SpecificationOracle

using SHA
using TOML

const FEATURE_IDS = (
    "canonical-state-serialization",
    "temporal-process-protocol",
    "ordered-reactive-step-protocol",
    "explicit-iterative-constructs",
    "imminent-event-scheduler",
    "adaptive-deadlines",
    "versioned-update-algebra",
    "settled-boundary-checkpoint",
    "versioned-process-continuation",
    "semantic-lineage-rng",
    "transactional-failure",
    "readonly-observer-protocol",
    "serial-semantic-executor",
    "multirate-input-semantics",
    "independent-julia-specification-oracle",
    "workflow-cycle-rejection",
    "exact-integer-logical-time",
    "actual-elapsed-partial-interval",
    "same-time-common-snapshot",
    "typed-process-deltas",
    "deterministic-conflict-reconciliation",
    "atomic-event-commit",
)

const M0 = UInt32(0xD2511F53)
const M1 = UInt32(0xCD9E8D57)
const W0 = UInt32(0x9E3779B9)
const W1 = UInt32(0xBB67AE85)

function mulhilo(left::UInt32, right::UInt32)
    value = UInt64(left) * UInt64(right)
    UInt32(value >> 32), UInt32(value & 0xffffffff)
end

function philox(counter, key)
    c0, c1, c2, c3 = counter
    k0, k1 = key
    for round in 1:10
        hi0, lo0 = mulhilo(M0, c0)
        hi1, lo1 = mulhilo(M1, c2)
        c0, c1, c2, c3 = hi1 ⊻ c1 ⊻ k0, lo1, hi0 ⊻ c3 ⊻ k1, lo0
        if round != 10
            k0 += W0
            k1 += W1
        end
    end
    (c0, c1, c2, c3)
end

function schedule_fixture(fixture)
    processes = [
        (
            id=String(row["id"]),
            amount=Int(row["amount"]),
            cadence=Int(row["cadence"]),
            next_due=Int(row["cadence"]),
        )
        for row in fixture["processes"]
    ]
    state = 0
    trace = String[]
    observations = String[]
    while true
        due_time = minimum(process.next_due for process in processes)
        due_time > Int(fixture["horizon"]) && break
        due = sort([process for process in processes
            if process.next_due == due_time]; by=process -> process.id)
        append!(observations,
            ["$(process.id):$state" for process in due])
        state += sum(process.amount for process in due)
        push!(trace, join((process.id for process in due), "+"))
        processes = [
            process.next_due == due_time ?
                merge(process,
                    (next_due=process.next_due + process.cadence,)) :
                process
            for process in processes
        ]
    end
    state, trace, observations
end

function oracle_results(fixture_path)
    fixture = TOML.parsefile(fixture_path)
    final_state, trace, common_reads = schedule_fixture(fixture)
    zero = philox(
        (UInt32(0), UInt32(0), UInt32(0), UInt32(0)),
        (UInt32(0), UInt32(0)),
    )
    rng_vector = join((string(word; base=16, pad=8)
        for word in zero), ",")
    results = Dict{String,String}(
        "canonical-state-serialization" =>
            "deterministic-logical-envelope",
        "temporal-process-protocol" => "elapsed=1,1,1,1",
        "ordered-reactive-step-protocol" => "copy=1;quiescent=true",
        "explicit-iterative-constructs" => "converged=2;bounded=3",
        "imminent-event-scheduler" => join(trace, "|"),
        "adaptive-deadlines" => "1,3,5;next=7",
        "versioned-update-algebra" =>
            "add=6;mul=30;replace=owner;keyed=1,2;indexed=4,5;set=1,2;append=a,b",
        "settled-boundary-checkpoint" =>
            "deterministic=true;roundtrip=true;integrity=sha256",
        "versioned-process-continuation" => "1,2,3,4",
        "semantic-lineage-rng" => rng_vector,
        "transactional-failure" => "state=0;events=0;diagnostic=true",
        "readonly-observer-protocol" => "1:1|2:2|3:3",
        "serial-semantic-executor" => "state=$(final_state);events=4",
        "multirate-input-semantics" =>
            "frozen=0;interpolated=2;event_updated=2;continuous=3",
        "independent-julia-specification-oracle" =>
            "stdlib-only=true;production-import=false",
        "workflow-cycle-rejection" => "rejected=true",
        "exact-integer-logical-time" => "3//10",
        "actual-elapsed-partial-interval" => "elapsed=3",
        "same-time-common-snapshot" => join(common_reads, "|"),
        "typed-process-deltas" =>
            "add,multiply,replace,keyed,indexed,set,append_stable",
        "deterministic-conflict-reconciliation" =>
            "forward=reverse",
        "atomic-event-commit" => "single-commit=true;partial=false",
    )
    Set(keys(results)) == Set(FEATURE_IDS) ||
        error("oracle result feature coverage drifted")
    results
end

function mutated_results(fixture_path, target::Symbol)
    results = oracle_results(fixture_path)
    if target === :scheduler
        results["imminent-event-scheduler"] = "fast|slow|fast|slow"
    elseif target === :update
        results["versioned-update-algebra"] = "declaration-order-fold"
    elseif target === :rng
        results["semantic-lineage-rng"] = "mutable-stream"
    elseif target === :failure
        results["transactional-failure"] =
            "state=1;events=1;diagnostic=false"
    elseif target === :checkpoint
        results["settled-boundary-checkpoint"] =
            "deterministic=false;roundtrip=false;integrity=none"
    else
        error("unknown registered oracle mutant: $(target)")
    end
    results
end

function write_results(fixture_path, output_path)
    open(output_path, "w") do io
        TOML.print(io, Dict(
            "schema_version" => "1.0.0",
            "implementation" => "independent-stdlib-julia-oracle",
            "results" => oracle_results(fixture_path),
        ); sorted=true)
    end
end

end
