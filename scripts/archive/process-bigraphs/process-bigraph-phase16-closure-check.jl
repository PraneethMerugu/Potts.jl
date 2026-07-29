#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ledger_path = joinpath(ROOT, "spec", "process-bigraph-phase16-qualification-v1.toml")
const ledger = TOML.parsefile(ledger_path)
const requirements = ledger["requirements"]
const open_rows = [row["id"] for row in requirements if row["status"] != "qualified"]
const expect_open = "--expect-open" in ARGS

if isempty(open_rows) && ledger["closure_status"] == "qualified_internal_beta"
    println("ProcessBigraphs Phase 16 closure check passed: every required row is qualified.")
elseif expect_open
    isempty(open_rows) &&
        error("Phase 16 ledger claims open but contains no open requirement rows")
    ledger["closure_status"] == "open" ||
        error("Phase 16 open-state check requires closure_status = open")
    println("ProcessBigraphs Phase 16 closure is honestly open: $(length(open_rows)) required rows remain.")
else
    preview = join(first(open_rows, min(10, length(open_rows))), ", ")
    println(stderr, "Phase 16 closure is open; $(length(open_rows)) required rows remain: $(preview)")
    exit(1)
end

