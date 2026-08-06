# GitHub and JuliaGPU Governance

Status: historical Phase 1 record; non-authoritative

Current disposition: operational truth is the checked-in `.github/workflows/` configuration and
`CONTRIBUTING.md`. Exact-check review and backend qualification follow the
[G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md). The required-check names, exact
Julia patch, runner inventory, and phase schedule below describe an earlier repository state.

## Purpose

GitHub is the durable coordination and evidence layer for the refactor. It does not replace the
scientific specifications: pull requests show reviewable changes, Actions qualify a revision, and
immutable releases preserve evidence for an exact source state.

## Required Checks and Merge Discipline

- `main` is changed through pull requests after the baseline bootstrap.
- `CI / Required` is the stable branch-protection check. It aggregates project-integrity and CPU
  contract jobs so internal job refactors do not silently weaken the protected rule.
- Project integrity and sharded CPU contracts run on GitHub-hosted infrastructure as the clean
  external reference. When their repository variables are enabled, the same complete CPU contract
  suite also runs on the macOS ARM64 and Linux x86_64 self-hosted systems and is included in the
  aggregate required result.
- Required checks use only read access to repository contents.
- A pull request is merged only when its exact head revision has passed the required check.
- GPU qualification is visible on the pull request but remains a separate signal until each runner
  is continuously available and its lane is stable enough to become required.

## Toolchain and Dependency Reproducibility

- Phase 1 and the refactor use exactly Julia 1.12.6. Compatibility ranges are introduced only with
  dedicated compatibility CI near release qualification.
- Every Action is pinned to a full commit SHA. Dependabot proposes reviewed SHA updates monthly.
- The Julia workspace and explicit `test/Project.toml` declare test dependencies; CI does not use
  `Pkg.add` or `Pkg.develop` to manufacture an environment.
- Unregistered or unreleased sources are pinned to full Git commits. Moving branch names may be
  cited for review, but are not dependency or evidence identities.
- GPU runtimes use separate projects so resolving CUDA, ROCm, or Metal cannot perturb another
  backend's scientific environment.
- Documentation instantiation disables automatic whole-environment precompilation. Pull requests
  build once without deployment; protected pushes and tags build once in the deployment job. This
  preserves the permission boundary without compiling the same documentation environment twice.

## Self-hosted Runner Trust Boundary

- Self-hosted runners never execute code from fork or Dependabot pull requests. GPU jobs are
  eligible only for pushes, manual dispatches, and human-authored pull requests whose head
  repository is this repository. The same restriction applies to self-hosted CPU jobs. Dependabot
  action updates receive hosted validation until a maintainer reviews and merges them; the ensuing
  protected `main` push performs the self-hosted qualification.
- Every self-hosted job checks the revision out under `_ci/source` and runs there. It never checks
  out into the job workspace root, so a runner whose workspace overlaps a developer checkout cannot
  switch, clean, or overwrite that developer worktree.
- Runners carry capability labels (`metal`, `rocm`, or `cuda`); workflows do not infer hardware
  from an operating-system label.
- Repository variables enable only runners that actually exist. A missing backend is skipped
  visibly rather than queued forever or emulated and reported as hardware evidence.
- GPU jobs have bounded timeouts, backend-specific concurrency, and least-privilege tokens.
- Secrets are not required for correctness or benchmark jobs. Documentation publication is
  isolated in a push-only job with its own narrow write permission.

## Test and Benchmark Roles

- Hosted Linux CPU CI is the always-available clean correctness gate. Complete macOS ARM64 and Linux
  x86_64 CPU runs independently validate architecture and operating-system portability on the same
  trusted revision; neither substitutes for the hosted result.
- GPU validation runs real-device smoke workloads with synchronization-aware timing and explicit
  state invariants. The historical statistical suite is not falsely described as backend-generic;
  Phase 3 will make its conformance cases genuinely backend-parametric.
- An algorithm with a known backend defect is named as unqualified and excluded from the green
  qualification set. Its reproducer remains available; it is never converted into an apparent
  pass.
- Benchmarks are manual, backend-selected workflows. They upload the versioned raw result tree as
  an artifact and never treat Actions timing alone as a paper measurement.
- Benchmark records include commit, source checksum, Julia version, architecture, backend, device,
  dependency commit, synchronization-aware timing, invariants, and known limitations.

## Releases and Evidence

- The pre-refactor baseline is a prerelease, not a semantic package release.
- Its tag points at the reviewed baseline commit. Raw CPU/Metal records, checksums, environment
  metadata, and the known-defect report are attached before publication.
- Release immutability is enabled before publishing. Assets and tags are verified after publication;
  corrections require a new release rather than mutation of the scientific record.
- Ordinary workflow artifacts support debugging and iteration. Release assets are the durable
  evidence boundary and must be independently checksummed.

## Deferred Hardening

CUDA becomes enabled only when a labeled trusted runner exists. GPU jobs may become protected
checks after availability is measured and false infrastructure failures are separated from
scientific failures. Julia-version compatibility, code-coverage policy, release automation, and
paper reproduction workflows are introduced in their roadmap phases rather than weakening the
1.12.6 baseline contract now.
