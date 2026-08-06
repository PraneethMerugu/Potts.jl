# G5H implementation control

Status: active; G5H-0 and R2H-A passed; G5H-1 pending

Authority: [Symbolic Potts V1 G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md)

This is the sole living status record for G5H. It records outcomes and exact evidence; it does not
repeat or amend gate requirements.

## Gate state

| Boundary | State | Evidence or blocker |
|:--|:--|:--|
| G5H-0 — authority, baseline, preservation | `passed` | Corrected candidate `9afcf6f1ec44cf84525d8b023c2d1b705560e365`, tree `a8b0ce43489e558e1770f4982dece97ef4c6eca7`, cleared R2H-A with no carried finding. |
| R2H-A — authority and preservation review | `passed` | Fresh independent read-only review of the exact corrected candidate returned `PASS`: P0=0, P1=0, P2=0, P3=0. |
| G5H-1 — semantic and CorePotts consolidation | `pending` | Unblocked by R2H-A; implementation has not begun. |
| G5H-2 — pure-Potts authoring and SciML lifecycle | `pending` | Depends on G5H-1. |
| G5H-3 — native global MTK integration | `pending` | Depends on G5H-2. |
| R2H-B — cohesion and real-MTK review | `pending` | Opens only after G5H-1 through G5H-3 pass. |
| G5H-4 — dynamic components, fields, ensembles, profiles | `pending` | Blocked by R2H-B. |
| G5H-5 — product qualification and docs | `pending` | Depends on G5H-4. |
| R2H-C — hardening exit review | `pending` | Opens only after G5H-5 passes. |
| G6 owner decision | `pending` | G6 remains closed; it requires cleared R2H-C and explicit owner send-off. |

## Review results

The first formal R2H-A review inspected candidate
`6e8ea1c5e68a5a69f51f9c69249b1b756b4fb28c`, tree
`ca052bf1d719cdd48caea4a126fd630a895df5b8`, read-only and returned `PASS` with P0=0, P1=0,
P2=4, and P3=1. It verified the deletion/recovery boundary and found bounded record defects:
incomplete qualification-tool inventory, an invalid control-state spelling and insufficiently
exact command record, the exported `compile` generic mislabeled unexported, stale backend/audit
wording in one active standard, and one dangling historical trace locator.

The contract permitted those P2s to be carried, but the project elected to repair every finding
before clearance. Therefore the first result did not advance G5H-0, and the corrected candidate
required a new exact-commit R2H-A review. Separate request, copied-log, or freshness-ledger files
are not created.

The fresh formal rereview then inspected corrected candidate
`9afcf6f1ec44cf84525d8b023c2d1b705560e365`, tree
`a8b0ce43489e558e1770f4982dece97ef4c6eca7`, read-only and returned `PASS` with P0=0, P1=0,
P2=0, and P3=0. It independently reproduced the authority order, complete preservation and
tooling partitions, all 356 deletion/recovery witnesses, the archive hash and entry count, public
declaration ranges and digests, active-link/TOML/local-path checks, fresh package boundaries, and
closure of every first-review finding. G5H-0 and R2H-A therefore pass with no carried P2; G5H-1 is
unblocked but has not begun.

## G5H-0 candidate evidence

All commands completed on the target Mac with Julia 1.12.1 on 2026-08-06.

| Obligation | Reproduction command or exact artifact | Exact result |
|:--|:--|:--|
| PottsToolkit full package suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=. --startup-file=no -e 'using Pkg; Pkg.test("PottsToolkit")'` | 1,989/1,989 passed in 35m54s. |
| CorePotts package suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/CorePotts --startup-file=no -e 'using Pkg; Pkg.test("CorePotts")'` | 233/233 passed: 223 functional and 10 Aqua assertions. |
| MakiePotts package suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/MakiePotts --startup-file=no -e 'using Pkg; Pkg.test("MakiePotts")'` | 501/501 passed. |
| Optional integration suite | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=integration --startup-file=no integration/runtests.jl` | 22/22 passed: 12 legacy MTK-assimilation, 4 ModelingToolkitStandardLibrary, 4 Unitful, and 2 load-order assertions. The first two groups preserve existing behavior only and do not qualify the G5H-3 native-island target. The ignored local environment resolved ModelingToolkit 11.37.1, ModelingToolkitBase 1.58.1, ModelingToolkitStandardLibrary 2.29.5, SciMLBase 3.39.1, SymbolicIndexingInterface 0.3.51, Symbolics 7.34.1, DynamicQuantities 1.13.0, and Unitful 1.28.0. |
| Documentation | `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=docs --startup-file=no docs/make.jl`; `warnonly=false` is fixed in `docs/make.jl` | Strict four-page temporary manual passed; the exact local-link command below covered 208 active manual/authority Markdown files with zero missing targets. |
| Fresh package boundaries | The two exact loaded-module commands below; the CI platform command `/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --startup-file=no -e 'using Pkg; Pkg.activate(; temp=true); Pkg.develop(path=pwd()); include("test/platform_smoke.jl")'` | PottsToolkit loaded without full ModelingToolkit or the retired package; CorePotts loaded without PottsToolkit, ModelingToolkitBase, ModelingToolkit, SciML, or Makie; the public platform smoke trajectory passed. |
| Inventory and static integrity | `git diff --check 3591eccd6820bf51c185cf631c75467114319332..HEAD`; `shasum -a 256 src/PottsToolkit.jl lib/CorePotts/src/CorePotts.jl lib/MakiePotts/src/MakiePotts.jl`; exact path-set comparisons against the baseline tables | All 115 production source files, 58 package/integration test-support files, three vendor runners, six live qualification/benchmark tools, and seven historical checkers are partitioned. Public declarations are 299 unique PottsToolkit names (300 declarations), 479 CorePotts names, and 74 MakiePotts names with the baseline digests. |
| Retirement and environments | `diff -u <(git diff --name-only --diff-filter=D 3591eccd6820bf51c185cf631c75467114319332..HEAD \| sort) <(awk -F '\t' '!/^#/ && NF==3 {print $3}' design/hardening/g5h0-deletion-inventory.tsv \| sort)` plus retired-name `rg` scans over active code, projects, manifests, workflows, and docs | All 356 tracked deletions match the inventory; active surfaces contain no retired dependency or hook; stale application manifests were regenerated from surviving projects. |
| Recovery | `git cat-file -e 3591eccd6820bf51c185cf631c75467114319332^{commit}`; `shasum -a 256 '/Users/praneethmerugu/Documents/Jiang/CPM 1.6/ProcessBigraphs-retired-20260805.tar.gz'`; `tar -tzf '/Users/praneethmerugu/Documents/Jiang/CPM 1.6/ProcessBigraphs-retired-20260805.tar.gz' \| awk 'index($0,"./lib/ProcessBigraphs/")==1 {n++} END {print n+0}'` | Git recovers every tracked deletion. The archive checksum is `338d74d39aa46c2610f49bfc55cfb48ce60e86d12113b337d7d669af8a2007bd` and it contains 16,294 entries under `lib/ProcessBigraphs/`. |

The fresh loaded-module checks were:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=. --startup-file=no -e 'using PottsToolkit; loaded = Set(pkgid.name for pkgid in keys(Base.loaded_modules)); @assert "ModelingToolkitBase" in loaded; @assert !("ModelingToolkit" in loaded); @assert !("ProcessBigraphs" in loaded); @assert :compile in names(PottsToolkit)'
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --project=lib/CorePotts --startup-file=no -e 'using CorePotts; loaded = Set(pkgid.name for pkgid in keys(Base.loaded_modules)); forbidden = Set(["PottsToolkit", "ModelingToolkitBase", "ModelingToolkit", "SciMLBase", "Makie", "MakiePotts", "ProcessBigraphs"]); @assert isempty(intersect(loaded, forbidden))'
```

The exact static checks, run from the repository root, were:

```sh
git diff --check 3591eccd6820bf51c185cf631c75467114319332..HEAD
diff -u <(git diff --name-only --diff-filter=D 3591eccd6820bf51c185cf631c75467114319332..HEAD | LC_ALL=C sort) <(awk -F '\t' '!/^#/ && NF==3 {print $3}' design/hardening/g5h0-deletion-inventory.tsv | LC_ALL=C sort)
awk -F '\t' '!/^#/ && NF==3 {print $3}' design/hardening/g5h0-deletion-inventory.tsv | while IFS= read -r file; do git cat-file -e "3591eccd6820bf51c185cf631c75467114319332:$file" && test ! -e "$file" || exit 1; done
shasum -a 256 src/PottsToolkit.jl lib/CorePotts/src/CorePotts.jl lib/MakiePotts/src/MakiePotts.jl
! rg -n -i 'processbigraphs|process[- ]bigraph|PottsToolkitProcessBigraphsExt|process_component|efcc6515-205e-41e3-b553-f38f05ad529c' .github src ext test integration lib/CorePotts lib/MakiePotts benchmark examples paper Project.toml docs/Project.toml docs/Manifest.toml docs/make.jl docs/README.md docs/src/index.md docs/src/concepts/architecture.md docs/src/concepts/runtime-boundary.md docs/src/concepts/capability-status.md README.md CONTRIBUTING.md --glob '*.jl' --glob '*.toml' --glob '*.yml' --glob '*.yaml' --glob '*.md'
test "$(find src ext lib/CorePotts/src lib/MakiePotts/src -type f -name '*.jl' | wc -l | tr -d ' ')" = 115
test "$(find test integration lib/CorePotts/test lib/MakiePotts/test -type f -name '*.jl' | wc -l | tr -d ' ')" = 58
test "$(find benchmark/backends -mindepth 2 -maxdepth 2 -type f -name 'runtests.jl' | wc -l | tr -d ' ')" = 3
test "$({ find scripts -maxdepth 1 -type f -name '*.jl'; find benchmark/src lib/MakiePotts/benchmark -type f -name '*.jl'; } | wc -l | tr -d ' ')" = 6
test "$(find scripts/archive/potts-history -type f -name '*.jl' | wc -l | tr -d ' ')" = 7
find src ext lib/CorePotts/src lib/MakiePotts/src -type f -name '*.jl' | LC_ALL=C sort
find test integration lib/CorePotts/test lib/MakiePotts/test -type f -name '*.jl' | LC_ALL=C sort
{ find benchmark/backends -mindepth 2 -maxdepth 2 -type f -name 'runtests.jl'; find scripts -maxdepth 1 -type f -name '*.jl'; find benchmark/src lib/MakiePotts/benchmark -type f -name '*.jl'; find scripts/archive/potts-history -type f -name '*.jl'; } | LC_ALL=C sort
find src ext lib/CorePotts/src lib/MakiePotts/src test integration lib/CorePotts/test lib/MakiePotts/test scripts benchmark/src benchmark/backends lib/MakiePotts/benchmark -type f -name '*.jl' -print | while IFS= read -r file; do count=$(awk 'NF && $1 !~ /^#/' "$file" | wc -l | tr -d ' '); test "$count" -le 1000 || printf '%s\t%s\n' "$count" "$file"; done | sort -nr
```

R2H-A compares the three sorted path-set outputs line-for-line against the source, test, and
tooling rows. The last command must emit exactly the nine-file responsibility table. Generated
captures under `benchmark/results/**` are intentionally outside that maintained-source universe.

Declaration count, uniqueness, row-count, and nonoverlapping range coverage use:

```sh
ruby <<'RUBY'
specs = {
  "src/PottsToolkit.jl" => [300, 299, [[74,84,43],[85,95,36],[96,104,46],[105,109,26],[110,124,49],[125,130,25],[131,135,14],[137,156,34],[157,166,27]]],
  "lib/CorePotts/src/CorePotts.jl" => [479, 479, [[33,39,15],[40,51,24],[52,52,2],[53,86,66],[87,94,14],[95,105,24],[106,134,57],[135,156,54],[157,177,43],[178,194,35],[195,208,26],[209,268,119]]],
  "lib/MakiePotts/src/MakiePotts.jl" => [74, 74, [[23,29,22],[31,35,18],[37,40,14],[42,46,13],[48,49,7]]],
}
specs.each do |path, spec|
  raw_expected, unique_expected, ranges = spec
  rows = []
  File.readlines(path).each_with_index do |line, index|
    match = line.match(/^\s*(?:export|public)\s+(.+?)\s*$/)
    rows << [index + 1, match[1].split(",").map(&:strip)] if match
  end
  names = rows.map(&:last).flatten
  abort("#{path}: raw") unless names.length == raw_expected
  abort("#{path}: unique") unless names.uniq.length == unique_expected
  covered = []
  ranges.each do |first, last, count|
    selected = rows.select { |line, _| (first..last).cover?(line) }
    abort("#{path}: range #{first}-#{last}") unless
      selected.inject(0) { |sum, pair| sum + pair.last.length } == count
    covered.concat(selected.map(&:first))
  end
  abort("#{path}: coverage") unless
    covered.sort == rows.map(&:first).sort && covered.uniq.length == covered.length
end
RUBY
```

The local-link traversal was:

```sh
ruby <<'RUBY'
require "uri"
all = IO.popen(["git", "ls-files", "-co", "--exclude-standard"], &:read)
    .lines.map(&:chomp).select { |path| path.end_with?(".md") && File.file?(path) }
active_docs = [
  "docs/src/index.md",
  "docs/src/concepts/architecture.md",
  "docs/src/concepts/runtime-boundary.md",
  "docs/src/concepts/capability-status.md",
]
files = all.select { |path| !path.start_with?("docs/src/") || active_docs.include?(path) }
missing = []
files.each do |path|
  text = File.read(path)
  targets = text.scan(/\]\(([^)\n]+)\)/).flatten
  targets.concat(text.scan(/^\s*\[[^\]]+\]:\s*(\S+)/).flatten)
  targets.each do |raw|
    target = raw.strip
    target = target[1...target.index(">")].to_s if target.start_with?("<") && target.include?(">")
    target = target.split(/\s+/, 2).first.to_s
    next if target.empty? || target.start_with?("#", "@", "http://", "https://", "mailto:", "data:", "git:", "/")
    target = target.split("#", 2).first.split("?", 2).first
    next if target.empty?
    target = URI::DEFAULT_PARSER.unescape(target)
    missing << [path, raw] unless File.exist?(File.expand_path(target, File.dirname(path)))
  end
end
abort(missing.inspect) unless files.length == 208 && missing.empty?
RUBY
```

All tracked TOMLs and local dependency paths were checked with:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia --startup-file=no <<'JULIA'
using TOML
tracked = filter(isfile, readlines(`git ls-files`));
tomls = filter(path -> endswith(path, ".toml"), tracked);
foreach(TOML.parsefile, tomls);
projects = filter(path -> basename(path) in ("Project.toml", "Manifest.toml"), tomls);
local_path_count = Ref(0);
function check_local_paths(value, base, count)
    if value isa AbstractDict
        for (key, child) in value
            if key == "path" && child isa AbstractString
                count[] += 1
                @assert ispath(normpath(joinpath(base, child)))
            end
            check_local_paths(child, base, count)
        end
    elseif value isa AbstractVector
        foreach(child -> check_local_paths(child, base, count), value)
    end
end;
foreach(path -> check_local_paths(
    TOML.parsefile(path), dirname(path), local_path_count
), projects);
@assert length(tomls) == 150
@assert length(projects) == 23
@assert local_path_count[] == 50
JULIA
```

## Control rules

- A gate becomes `passed` only when every normative exit condition has executable or static
  evidence and the exact checkpoint is recorded.
- A later regression marks the earliest owning gate `reopened` and invalidates downstream review
  clearance as specified by the contract.
- P2 findings may be carried through R2H-A or R2H-B only with an explicit owning gate. R2H-C closes
  every in-scope P2.
- Historical audit results qualify only their recorded repository state.
