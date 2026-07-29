using Documenter
using ProcessBigraphs

const DOCS_ROOT = @__DIR__
const REPOSITORY = "https://github.com/PraneethMerugu/Potts.jl"

makedocs(
    sitename = "ProcessBigraphs.jl",
    authors = "Praneeth Merugu and contributors",
    modules = [ProcessBigraphs],
    format = Documenter.HTML(
        prettyurls = true,
        canonical = "https://praneethmerugu.github.io/Potts.jl/ProcessBigraphs/",
        repolink = REPOSITORY,
        edit_link = "main",
        size_threshold = nothing,
        size_threshold_warn = nothing,
        assets = ["assets/docs.css", "assets/beta.js"],
    ),
    doctest = true,
    warnonly = false,
    pagesonly = true,
    checkdocs = :none,
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Learn" => [
            "Install and verify the internal beta" => "learn/install-and-verify.md",
            "The process-bigraph mental model" => "learn/mental-model.md",
            "Your first multirate composite" => "learn/first-multirate-composite.md",
            "Stores, ports, schemas, and updates" => "learn/stores-ports-updates.md",
            "Compose and inspect a system" => "learn/compose-and-inspect.md",
            "Logical time, scheduling, and publication" => "learn/time-scheduling-publication.md",
            "Write processes, steps, and observers" => "learn/write-components.md",
            "Integrate adapters and solvers" => "learn/adapters-and-solvers.md",
            "Change structure transactionally" => "learn/dynamic-structure.md",
            "Checkpoint, fail, restore, and replay" => "learn/checkpoint-failure-replay.md",
        ],
        "Examples" => [
            "Example gallery" => "examples/index.md",
            "Pulse and decay" => "examples/pulse-and-decay.md",
            "Reusable nested composites" => "examples/nested-composites.md",
            "N-way junctions" => "examples/n-way-junctions.md",
            "SciML field adapter" => "examples/sciml-field-adapter.md",
            "Independent custom engine adapter" => "examples/custom-engine-adapter.md",
            "Divide, fail, and recover" => "examples/divide-fail-recover.md",
        ],
        "Scientific Case Studies" => [
            "Scientific case-study boundary" => "case-studies/index.md",
            "Wortel 2021" => "case-studies/wortel-2021.md",
            "Merks 2006" => "case-studies/merks-2006.md",
        ],
        "Concepts and Guarantees" => [
            "Architecture and compute ownership" => "concepts/architecture.md",
            "Canonical structure and semantic identity" => "concepts/canonical-identity.md",
            "Logical state, effects, and reconciliation" => "concepts/state-effects-reconciliation.md",
            "Time, schedules, and visibility" => "concepts/time-schedules-visibility.md",
            "Hierarchy and open composition" => "concepts/hierarchy-open-composition.md",
            "Dynamic structural transactions" => "concepts/structural-transactions.md",
            "Engines, adapters, and heavy computation" => "concepts/engines-and-compute.md",
            "RNG, observation, checkpoints, and replay" => "concepts/rng-observation-persistence.md",
            "Capability status, migration, and troubleshooting" => "concepts/capability-migration-troubleshooting.md",
        ],
        "API" => [
            "User authoring API" => "api/user-authoring.md",
            "Semantic values, schemas, schedules, and effects" => "api/semantic-values.md",
            "Process, step, observer, runtime, and checkpoint API" => "api/runtime-checkpoint.md",
            "Composition and structure API" => "api/composition-structure.md",
            "Extension protocols, experimental surface, and compatibility" => "api/extension-experimental.md",
        ],
    ],
)

if get(ENV, "PROCESS_BIGRAPHS_DEPLOY_DOCS", "false") == "true"
    get(ENV, "GITHUB_ACTIONS", "false") == "true" ||
        error("ProcessBigraphs documentation deployment is GitHub Actions-only")
    get(ENV, "GITHUB_EVENT_NAME", "") == "pull_request" &&
        error("pull requests cannot deploy production documentation")
    deploydocs(
        repo = "github.com/PraneethMerugu/Potts.jl.git",
        devbranch = "main",
        dirname = "ProcessBigraphs",
        tag_prefix = "ProcessBigraphs-",
        push_preview = false,
    )
end
