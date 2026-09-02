# Historical audits

Files in this directory preserve research, owner interviews, measurements, and implementation
reviews from earlier repository states. They are not current architecture or specification
authority, and many describe packages, APIs, paths, or phase gates that have since been changed or
removed.

Current authority lives in the [`spec/` index](../../spec/README.md), accepted
[decision records](../../spec/decisions/README.md), and, for current pre-G6 work, the
[LocalWorksets Implementation Gate](../../spec/localworksets-v1-implementation-gate.md) following the
cleared [G5H Hardening Contract](../../spec/symbolic-potts-v1-hardening.md). The repository architecture
standard and roadmap are subordinate contributor guidance, not semantic or phase authority.

Do not use a historical audit to restore a dependency, API, or product boundary superseded by a
later decision. Claiming current qualification from a historical conclusion requires a new
exact-head review when the governing invariant has changed, unless an accepted authority
explicitly carries that evidence forward.
