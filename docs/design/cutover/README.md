# Field-compiler cutover

This folder holds the in-repo record of the field-compiler cutover (D-256, D-257): today's field
path is replaced by the `LatticeFields` and `LatticePDE` packages in one breaking branch,
`feat/lattice-pde`.

- `DESIGN.md`: a summary of the design of record (architecture, cutover plan, gates).
- `expected-frozen-diffs.toml`: the frozen-suite failures and `refreeze(list-A)` edits the branch
  expects. The frozen runs must match it exactly.

The full design and its evidence live outside the repository, in the ecosystem's research tree:

- `research/field-compiler/v3-design.md`: the design of record (after pass 4).
- `research/field-compiler/SUMMARY.md`: the executive summary.
- `research/field-compiler/pass1/` … `pass4/`: studies, reviews, probes and prototypes.
- `research/field-compiler/build/`: the build brief, the C0 Manifest and the upstream drafts.

Paths are relative to the ecosystem root (the parent of the monorepo checkout).
