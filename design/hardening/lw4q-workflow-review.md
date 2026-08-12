# LW-4Q focused workflow review

Date: 2026-08-12

Scope: qualification mechanics only. This is not LW-R2 and does not reopen
LocalWorksets architecture, naming, lifecycle, output semantics,
KernelAbstractions ordering, or domain ownership.

## Final disposition

**PASS — P0=0, P1=0, P2=0.**

The corrected LW-4Q workflow is ready to qualify the clean committed product
candidate. Both remaining identity-validation blockers are closed, and the
previously closed command, artifact, subsampling, review, sealing and workflow
findings have not regressed.

Reviewed qualification-tool SHA-256:
`41cfb88dbaef0bd981a3e3f103e1d4b68050b7c82311630101926555917d5a67`.

## Exact verification

- The repository tool record validated against the exact final tool hash.
- A fresh hostile tool self-test passed against that hash. It exercised the
  minimal validate/seal path; bundle tampering; exact ledger, schema and
  inventory rejection; forbidden profiles; blocking review; post-seal review
  drift; tool-record tampering; and revalidation-record tampering.
- Direct hostile identity checks independently proved that a nonexistent
  workload object, a false Project/Manifest digest and a mismatched raw Julia
  identity are rejected, while the truthful synthetic identity is accepted.
- Direct hostile tool-record checks independently proved rejection of an empty
  timestamp, wrong Julia identity and incomplete covered-test list.
- Revalidation records have an exact schema and require a valid time, current
  validator hash, current Julia identity, pass disposition, exact detail, a
  live artifact, and an artifact digest that reconstructs from that artifact.
- Conflicting primary workflow modes are rejected.
- `git diff --check` passed.
- The bounded `--check` workflow passed end to end on the exact candidate:
  standalone LocalWorksets, CorePotts, CPU witnesses and real-Metal semantic,
  lifetime and failure witnesses.

## Finding closure

| Original finding | Final status | Evidence |
|---|---|---|
| P1-1 validate/seal always fail | **closed** | Validate, seal and verify-seal execute in the hostile tool test. |
| P1-2 ledger/schema/artifact and identity validation | **closed** | Exact commands/environments, contained logs, exact inventory, profiles, summaries and results are checked. Workload objects reconstruct from `product_commit`; every runtime Project/Manifest has a digested snapshot; committed snapshots reconstruct from Git; KA derives from the snapshot; raw Metal Julia/kernel/architecture/machine/KA/device identity is cross-checked. |
| P1-3 unbound 500-pair analysis | **closed** | Five content-addressed source series independently reconstruct exactly. The evidence correctly changes normal/confirmation from 500/1,000 to 1,000/2,000 pairs. |
| P1-4 tool CI and revalidation binding | **closed** | Tool and revalidation records enforce exact schemas, current identities, coverage/disposition and reconstructed evidence binding, with hostile tamper tests. |
| P1-5 post-seal drift | **closed** | The seal binds the current review digest; verify-seal revalidates decisions and review bytes; verify-final requires a committed clean artifact. |
| P2-1 environment placement | **closed** | Host/project facts are in the identity and snapshots; detailed selected-device facts remain in digested raw Metal evidence and are cross-checked. |
| P2-2 conflicting workflow modes | **closed** | Exactly one primary mode is required. |

## Performance-profile determination

The content-addressed subsampling input SHA-256 is
`2e5c52bc2b745776d77072bd0dfd859ca45ef75151e0179dbecc78b0b8a4e841`.
An independent threaded reconstruction exactly matched every source identity,
method and value in `lw4q-subsampling.toml`:

- 500 pairs is insufficient: Metal z-buffer failed 13/500 predetermined
  decisions, with worst upper bound 1.0680504737.
- 1,000 pairs passed 500/500 decisions for all four workloads; the worst upper
  bound was 1.0270353662.
- 1,000 is therefore the normal Freeze profile and 2,000 the confirmation
  profile.

CorePotts parity remains 50 measured hardware batches plus 10,000 inexpensive
offline bootstrap draws. Bootstrap draws are not presented as executions.

## P2 closure

The sole P2 count typo is closed. The authoritative workflow now says ten
Project/Manifest snapshots, exactly matching all ten entries in
`PROJECT_FILES` and the validated artifact inventory. This documentation-only
correction did not change the product or the reviewed qualification-tool hash.

## Candidate and bundle determination

- The workflow/tooling candidate is valid and reviewable at the exact hash
  above.
- Historical 1,000-pair bundles remain bound only to their historical product,
  environment and workload identities and to the sample-sizing study; they do
  not qualify subsequent product changes.
- The current product worktree is not yet the Freeze candidate because it is
  uncommitted. The tool correctly requires a clean committed candidate.
- No current CPU/Metal Freeze bundle exists for that future commit. The next
  step is therefore product execution, not another workflow redesign.

## Exact next step

Commit the exact product/tool/workload candidate and run one normal 1,000-pair
Freeze on CPU plus real Metal. Validate the bundle, conduct the fresh five-role
LW-R2 product review with one chair, seal and commit the exact review artifact,
then run verify-final. LW-5 remains blocked until LW-R2 freezes.

## Ballot

| Question | Decision |
|---|---|
| Are both remaining P1 identity/record blockers closed? | Yes |
| Did the previously closed findings regress? | No |
| Is Check bounded and passing? | Yes |
| Is the 1,000/2,000 profile empirically justified? | Yes |
| Are CPU and real Metal still mandatory at Freeze? | Yes |
| Is source portability kept distinct from backend qualification? | Yes |
| Ready to commit a clean candidate and run final Freeze? | **Yes** |
| Final disposition | **PASS (P0=0, P1=0, P2=0)** |
