#!/usr/bin/env julia

using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const AUDITS = joinpath(REPO, "design", "audits")
const CONTRACT_PATH =
    joinpath(AUDITS, "phase-14-g3b-entry-contract-v1.toml")
const LEDGER_PATH =
    joinpath(AUDITS, "phase-14-g3b-closure-ledger-v1.toml")

isfile(CONTRACT_PATH) || error("missing G3-B contract")
isfile(LEDGER_PATH) || error("missing G3-B closure ledger")

contract = TOML.parsefile(CONTRACT_PATH)
ledger = TOML.parsefile(LEDGER_PATH)
failures = String[]

check(condition, message) = condition || push!(failures, message)

contract_rows = Dict(row["id"] => row for row in contract["closure_requirement"])
ledger_rows = Dict(row["id"] => row for row in ledger["requirement"])

check(Set(keys(contract_rows)) == Set(keys(ledger_rows)),
    "closure ledger and contract requirement identities differ")
check(ledger["contract_revision"] == contract["revision"],
    "closure ledger targets contract revision $(ledger["contract_revision"]), not $(contract["revision"])")

for id in sort!(collect(keys(contract_rows)))
    haskey(ledger_rows, id) || continue
    row = ledger_rows[id]
    check(row["status"] == "passed",
        "OPEN $id: status is $(row["status"]); remaining=$(join(get(row, "remaining", String[]), " | "))")
    for evidence in row["evidence"]
        path = joinpath(AUDITS, evidence)
        check(isfile(path), "OPEN $id: missing evidence file $evidence")
    end
end

check(ledger["overall_status"] == "passed",
    "OPEN overall_status: expected passed, found $(ledger["overall_status"])")
check(contract["closure_protocol"]["status"] == "passed",
    "OPEN contract closure_protocol.status: expected passed, found $(contract["closure_protocol"]["status"])")

if !isempty(failures)
    println("Phase 14.1 G3-B closure: OPEN")
    foreach(message -> println(" - ", message), failures)
    exit(1)
end

println("Phase 14.1 G3-B closure: PASS")
