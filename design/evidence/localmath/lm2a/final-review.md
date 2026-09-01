# LM-2A final independent review

Decision: **PASS**. LM-2A publication and planning consolidation is approved.

The first committee pass blocked closure on a test-only second planning
entrance, duplicated Unique workspace dimensions, incomplete compiler/Metal
gate assertions, missing fresh flagship evidence, and overbroad failure
atomicity wording. The implementation was corrected directly and the same
reviewers independently re-audited the live result.

## Compiler and Julia design — PASS

- Exactly one `_stage_planning_entry` call remains in the execution tree.
- Unique, Reduce, and Resolve share `_candidate_publication_dimensions`.
- The final 1/4/8/13/32 matrix passes the affine host-compilation bound, the
  separate one-stage planning-through-first bound, exact physical phase
  counts, and zero warm compilation or recompilation.
- The fresh CorePotts flagship packet passes its inherited latency, structural
  identity, phase-order, fact-count, and warm-compilation bounds.
- `_WorkspaceAuthority` remains the sole workspace schema without restoring
  whole-program specialization or another runtime.

## GPU and scientific semantics — PASS

- Live Metal packets pass StageProgram 38/38, Reduce 9/9, and Resolve 15/15.
- Invalid fixed relationship content fails validation before evaluation and
  leaves publication untouched.
- Candidate and Collect no-write failure behavior and OrderedFold validated
  prefix behavior are stated separately; provider rollback is not claimed.
- Packed relationship validation, deterministic canonical settlement, and all
  required grid-visible barriers remain on one KernelAbstractions path.

## Simplification and maintainability — PASS

- The test-only `_stage_draft` / `_prepare_stage` planning path is deleted.
- Inspection consumes retained lowering evidence without replanning.
- The gate enforces exact authority occurrence counts and exact KA kernel-name
  set equality rather than aggregate counts alone.
- The four-stage witness has 21 stage-local phases plus one program reset; no
  scheduler, backend-specific executor, compatibility path, or migration
  machinery was introduced.
- The live source census is 17,356 lines in 34 Julia files. The recorded
  post-LM-1 delta is supporting context only; deletions are gated by exact
  files, symbols, and surviving authorities.

## Final evidence

- Official LocalWorksets package tests pass.
- Final synthetic compiler manifest:
  `compiler-qualified-synthetic-current/manifest.toml`.
- Fresh flagship manifest: `compiler-qualified-flagship/manifest.toml`.
- Real-Metal evidence with exact commands and source hashes:
  `real-metal.toml`.
- Machine authority gate: `julia scripts/check_localmath_lm2a_gate.jl`.

No reviewer identified a remaining implementation, performance, GPU,
scientific, or simplification blocker. LM-2A is closed; LM-2B may begin from
this single-path authority boundary.

## Post-LM-2D requalification addendum

The decision above records the LM-2A boundary at the time of that review. The
later preparation and receipt cutovers initially regressed the frozen bounds.
The 2026-08-23 workspace-template and validation consolidation removed that
regression without changing the execution path: fresh-process host compilation
is now 2.411 seconds at one Stage and 11.304 seconds at four Stages, with exact
`2/22/53/90/231` base launch counts and zero warm Julia compilation across the
1/4/8/13/32 witnesses. Current compiler qualification is closed.
