# Potts monorepo — working rules

Design lives in `docs/design/` (read `AUTONOMY.md` first; `PROGRESS.md` is the running log,
`ROADMAP.md` the milestones, `DECISIONS.md` the settled questions — do not relitigate them).

## Layout and environments

One Julia ≥ 1.12 workspace: the root `Project.toml` lists every package and test project
under `[workspace]`, and there is a single, gitignored `Manifest.toml`. Never add a
Manifest or a nested `[workspace]` anywhere else (the only exception is
`reference/Manifest.toml`, which pins the legacy stack).

- `src/` — `Potts` (symbolic layer: MTK-style `@potts_model`, compiler, codegen)
- `lib/CorePotts` — numerical solvers, no Symbolics dependency
- `lib/LocalMath` — bulk-synchronous stage runtime
- `lib/MakiePotts` — plotting (outside the workspace until M2.10)

Tests: `julia --project=test test/runtests.jl` with `GROUP=All|LocalMath|CorePotts|Potts`,
or run one group directly, e.g. `julia --project=lib/CorePotts/test lib/CorePotts/test/runtests.jl`.

## Code rules (INTERNALS §5)

- No `@generated`, no recursion over heterogeneous tuples; models vary only through
  generated functions (RuntimeGeneratedFunctions, always `drop_expr`'d).
- No type parameters encoding model content (names, counts, expressions).
- `@inline` only on leaf primitives; no `@inbounds` without an adjacent bounds argument.
- No `throw` inside kernels; set the status word.
- Every pass-through of a function argument is `::F where {F}` (else Julia will not specialize).
- Closures passed to `ntuple` etc. must not reassign captured variables (they get boxed and
  allocate on every call — this cost 150 KB per MCS once).
- Device code must not touch `Float64` values (Metal has no doubles), including struct fields.
- SciML formatter style (`.JuliaFormatter.toml`); ExplicitImports clean.

## Git

Local only: no pushes, PRs, tag pushes, worktree pruning or branch deletion without the
maintainer (see `AUTONOMY.md` §4). Work on branch `monorepo`.
