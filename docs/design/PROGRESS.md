# Progress log


## 2026-09-29 — Phase 1 start (commit 7b0a81b)

- **M1.1 done.** Root workspace (`Potts` + `lib/LocalMath` + `lib/CorePotts` and their test
  projects), one gitignored Manifest, `CLAUDE.md`. A clean clone instantiates and
  precompiles in 9 s (CorePotts 1.9 s).
- **M1.2 done.** LocalMath subtree, nested `[workspace]` removed; 1947/1947 tests pass in the
  workspace (`GROUP=LocalMath`, 2 min 19 s).
- **M1.3 imported, not built.** MakiePotts subtree is in `lib/MakiePotts`, outside the
  workspace until M2.10 (it depends on the legacy Potts API).
- **M1.4 mostly done.** CorePotts is rewritten from FusedCPM against INTERNALS §1: 7763/7763
  tests pass in 5 s. `DEIntegrator{Alg,false,S,Int}` subtyping works. Still open: JET/AllocCheck
  gates.
- **Bugs found and fixed while testing:**
  - `shift`, `coordinates` and `color_site` boxed a captured variable reassigned inside an
    `ntuple` closure, costing 157 KB per MCS. The rule is now in CLAUDE.md.
  - The checkerboard colour vector was abstractly typed (`Vector{Color}`), so every launch
    dispatched dynamically.
  - Claim-buffer parity reset to buffer 1 every MCS. With an odd colour count the first
    colour used an uncleared buffer, which silently caused spurious claim losses. A
    regression test now covers it.
  - `Metropolis()` stored a Float64 offset, which is invalid IR on Metal. The default is
    now exact `0`, and float offsets are stored as Float32 on non-CPU backends
    (`_device_law`).
- **Warm throughput**, Graner–Glazier 256², 8 threads, M1 Pro:

  | Algorithm | Backend | MCS/s | ns/attempt | alloc/MCS |
  |---|---|---|---|---|
  | Sequential | CPU | 450 | 33.8 | 0 |
  | Checkerboard | CPU | 620 | 24.6 | 57–60 KB (KA launches) |
  | Checkerboard | Metal (Float32) | 1670 | 9.1 | 58 KB, launch-bound at this size |

- **Next:** M1.4 JET/AllocCheck gates, M1.4b transition-matrix oracle, M1.5 benchmark suite
  and `reference/` environment (CI parts deferred: local only).

## 2026-09-29 — M1.4 gates and M1.4b oracle

- **QA gates** (`lib/CorePotts/test/qa.jl`, skip with `COREPOTTS_QA=false`): JET `@test_opt` is
  clean on `sequential_mcs!`, `checkerboard_mcs!` and both `step!`s; AllocCheck finds no
  allocations in `sequential_mcs!` or a hand-written ΔH. `init` is deliberately not gated:
  resolving a relation fixes K at run time, a one-time function barrier.
- **Exact oracle** (`lib/CorePotts/test/oracle.jl`):
  - A self-contained re-derivation of both algorithms' stated semantics (random-site
    attempts; colour classes, uniform colour order, pre-colour proposals, claim
    resolution by uniform priorities). It propagates the exact state distribution on a
    closed 3×2 lattice for 2 MCS.
  - Scored against 40k seeds with pooled χ² as a Wilson–Hilferty z: sequential z = 0.00,
    checkerboard z = −0.76, and a T = 5 mutant against exact T = 4 gives z = 11.9.
- **Preflight found a latent race.** `CPMFunction` defaults to `Footprint(read = 1)`, so a
  wider contact relation (e.g. `NeighborOrder(3)`, radius 2) would have run the checkerboard
  at stride 2. `init` now rejects a declared read radius smaller than the proposal/contact
  radius. The symbolic compiler (M3) must derive the footprint itself.

## 2026-09-29 — M1.5 (local parts)

- **Benchmarks.** `benchmark/` is a workspace member: `graner.jl` (fresh-process TTFX and warm
  throughput), `benchmarks.jl` (BenchmarkTools `SUITE`), and the Graner baseline data with
  provenance. The results table is in `benchmark/README.md`.
  - Sequential 72²: 0.19 s to the first MCS, 0.018 s remake plus first MCS, 25–31 ns/attempt.
  - Legacy: 1.9 µs/attempt at 16 attempts/site and 62–67 s cold compile.
  - Metal 576²: 3.25 ns/attempt.
- **CPU launch fix.** A multithreaded KA CPU launch of a ~1300-site colour cost ~120 µs of
  task spawn and sync. 8 threads ran 6× slower than 1 thread at 72². CPU workgroups are now
  sized from an 8192-site grain: small colours run inline as one workgroup, large colours
  get one workgroup per thread.
- **Manifest.** Adding Metal re-resolved the workspace Manifest (GPUArraysCore
  0.2.1 → 0.2.0). All groups still pass.
- **Reference stack (D-021).** `reference/Project.toml` pins the five legacy repos by full
  SHA via `[sources]` URLs, with a committed Manifest. It is not a workspace member. Run
  it with `GROUP=Reference`, which is not part of `All`. Legacy `SequentialCPM` at
  427dc2e2 allows only `AttemptsPerSite(1)`, so its MCS equals ours.
- **First legacy parity look.** Graner 72², 320 MCS, heterotypic fraction of cell–cell
  Moore bonds over 8 seeds:
  - legacy: 0.342 (0.327–0.358)
  - new: 0.346 (0.308–0.387)
  - The difference, 0.004, is within one standard error (~0.01).
  - The new code's contact convention (unordered pairs, ΔH as in legacy) is confirmed:
    doubling J moves the result away from legacy, to 0.389.
  - Formal KS parity is M2.1. Legacy used `ForbidExtinction`; the new core has no
    extinction policy yet (no cell vanished in these runs at λ = 1, V0 = 40).
- **Performance note for M2/M3.** Sequential runs at ~25–31 ns/attempt against FusedCPM's
  ~20. The hand-written ΔH resolves kinds through a closure per neighbour. Generated code
  (M3) should hoist the old/new kind lookups.
