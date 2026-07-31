# Symbolic Potts V1 Implementation Control

Date started: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: active; explicit owner implementation send-off received

## Authority

The owner gave explicit implementation send-off on 2026-07-30 with: “u may start”.

Implementation is governed by:

1. [`spec/symbolic-potts-v1-compiler-construction.md`](../../spec/symbolic-potts-v1-compiler-construction.md);
2. [`spec/symbolic-potts-v1-architecture-redirection.md`](../../spec/symbolic-potts-v1-architecture-redirection.md);
3. [`spec/symbolic-potts-v1-consolidation.md`](../../spec/symbolic-potts-v1-consolidation.md);
4. [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md); and
5. compatible scientific specifications and accepted decisions.

G0 through G9 in CCV1-022 are the sole execution order. This record tracks implementation state
only. It does not redefine semantics or create CI/evidence authority.

## Baseline ownership

The pre-G0 Git parent is `ac23160` (`Build Symbolic Potts V1 runtime slice`).

At send-off, the worktree contained 360 entries:

- 278 tracked deletions;
- 61 tracked modifications; and
- 21 untracked files.

These paths are the accumulated Symbolic Potts V1 prototype, consolidation, architecture
redirection, compiler specification, test fixtures, package integrations, and removal of obsolete
benchmark/oracle/engine/authoring surfaces from this branch. No unrelated path cluster was found.
All are preserved in the G0 checkpoint rather than discarded, reset, or reconstructed from memory.

The deleted parent sources remain recoverable from Git history. A temporary clone of `main` may be
used read-only for algorithm and test-intent inspection only.

## Surviving implementation and test authority

The baseline prototype currently concentrates execution in:

- `src/completion`;
- `src/compiler`;
- `src/runtime`;
- `src/statements`;
- `src/symbolics`;
- `src/systems.jl`;
- `lib/CorePotts/src/program/v1.jl`; and
- `lib/CorePotts/src/rng/semantic.jl`.

The prototype is test and semantic evidence, not the accepted final architecture. In particular,
its named activity, field, history, elongation, relationship, and observation plans are replacement
targets under CCV1-006, CCV1-012, CCV1-017, and CCV1-018.

Current reusable test authority is concentrated in:

- `test/test_system_contract.jl`;
- `test/test_statements_and_traversal.jl`;
- `test/test_completion_and_diagnostics.jl`;
- `test/test_compilation_and_inspection.jl`;
- `test/test_units_and_parameters.jl`;
- `test/test_initial_problem_remake.jl`;
- `test/test_runtime_solution_sii.jl`;
- `test/test_checkpoint.jl`;
- `test/test_wortel_fixture.jl`;
- `test/test_merks_fixture.jl`;
- `test/test_focal_fixture.jl`;
- `test/test_package_quality.jl`;
- `lib/CorePotts/test/test_program_v1.jl`; and
- the five current integration fixtures.

Deleted parent tests may be mined for independently useful semantic intent. They must not be
restored as a legacy oracle, expected-output archive, or competing runtime authority.

## Pre-checkpoint baseline execution

The root package baseline was executed before the G0 checkpoint with:

```text
/Users/praneethmerugu/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/bin/julia \
    --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
```

It completed in 5 minutes 16.4 seconds with 272 passes, no assertion failures, and one error.
`initial_problem` reaches `CorePotts.initialization_bounded`, which calls the keyword-only
`RNGAddress` constructor with an obsolete positional `Int64` at
`lib/CorePotts/src/program/v1.jl:1056`. This is an inherited prototype defect, not a moved
baseline. Its correction belongs to implementation after the G0 checkpoint.

## Gate state

| Gate | State | Establishing evidence | Checkpoint | Review |
|---|---|---|---|---|
| G0 authority and recovery baseline | `in_progress` | branch/worktree inventory; specification validation; baseline checkpoint | pending | none |
| G1 host compiler facts | `pending` | pending | pending | none |
| G2 descriptor/group/evaluator/state/workspace | `pending` | pending | pending | R1 |
| G3 sequential reference/finite transitions | `pending` | pending | pending | none |
| G4 checkerboard/first GPU witness | `pending` | pending | pending | none |
| G5 trackers/relationships/lifecycle/checkpoint | `pending` | pending | pending | R2 |
| G6 public integration spine | `pending` | pending | pending | none |
| G7 proof-model reconstruction | `pending` | pending | pending | R3 |
| G8 clean break/full integration | `pending` | pending | pending | none |
| G9 terminal qualification | `pending` | pending | pending | R4 |

## Reviewer state

| Review | State | Blocking findings | Nonblocking findings |
|---|---|---|---|
| R1 compiler | `pending` | none | none |
| R2 execution/concurrency/GPU | `pending` | none | none |
| R3 science | `pending` | none | none |
| R4 terminal | `pending` | none | none |

## G0 checks

Required:

- [x] explicit owner implementation send-off;
- [x] authoritative branch confirmed;
- [x] dirty-worktree ownership inventoried;
- [x] unrelated changes preserved;
- [x] specification links, Markdown fences, clause count, gates, reviews, and send-off boundary
      validated;
- [x] surviving prototype/test authority inventoried;
- [ ] complete baseline checkpoint commit;
- [ ] verify the checkpoint worktree is clean; and
- [ ] mark G0 `passed` and G1 `in_progress`.

Commands used:

```text
git branch --show-current
git status --short
git status --porcelain=v1
git diff --stat
git diff --check
git log -5 --oneline --decorate
```

## Reopen history

None.

## Unresolved P2 findings

None at G0.

## Prohibited record contents

This record intentionally contains no freshness deadline, renewed attestation, copied CI log,
expected-output archive, hardware ledger, manually renewed hash, duplicated vendor suite, or
second semantic definition.
