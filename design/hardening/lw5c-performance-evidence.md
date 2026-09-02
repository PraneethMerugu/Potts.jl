# LW-5C paired performance evidence

Status: exact consolidated-candidate CPU and real-Metal protocols passed

Date: 2026-08-14

Machine: Apple M1 Pro (`arm64`, Darwin 24.6.0)

Julia: 1.12.6

Protocol:

- direct checkerboard oracle versus the private LW-5C K02→K03 sequence;
- 128×128 periodic fixture;
- ten MCSs per measured batch;
- ten warm batches and fifty paired measured batches;
- deterministic randomized arm order;
- 10,000 paired-bootstrap resamples;
- unchanged noninferiority requirement: upper 95% bound ≤ 1.05;
- complete runtime-batch allocation scope; and
- CPU fixture includes the registered external Hamiltonian lowered through
  `complete` and `mtkcompile`; Metal uses the fully qualified built-in
  Hamiltonian surface because external Metal mechanisms remain fail-closed.

## Results

| Measure | CPU | real Metal |
|---|---:|---:|
| direct median seconds | 0.0251879795 | 0.1126387920 |
| adopted median seconds | 0.0259179585 | 0.1125552710 |
| median ratio | 1.0289812448 | 0.9992585059 |
| paired bootstrap upper 95% | 1.0423004818 | 1.0043324310 |
| threshold | 1.05 | 1.05 |
| direct median allocated bytes | 1,319,296 | 17,704,720 |
| adopted median allocated bytes | 1,508,896 | 17,986,160 |
| byte delta | +189,600 | +281,440 |
| direct median allocations | 10,227 | 261,538 |
| adopted median allocations | 11,500 | 263,919 |
| allocation-count delta | +1,273 | +2,381 |

Both backends pass the unchanged performance gate. The allocation deltas are
carried optimization debt; the phase does not relabel or hide them.

## Execution ledger

- two proposal-stage launches per color in both arms;
- one `LocalWorksets.sequence` submission per color in the adopted arm;
- zero intermediate waits;
- one final same-scope synchronization per settlement;
- zero algorithmic workspace bytes;
- zero topology-transfer bytes for the fixed prepared topology;
- submitted and drained prefixes are equal after settlement;
- no LocalWorksets poison in successful or expected-scientific-failure runs;
- direct claims, commit, counters, lifecycle indexing, publication and
  settlement remain CorePotts-owned; and
- direct execution remains the public/default engine pending LW-R3.

## Persistent Metal compile/lifetime probe

The final complete Metal runner reported:

```text
queued_mcs = 12
colors = 2
launches_per_color = 2
submissions = 24
waits = 1
scope_synchronizations = 1
algorithmic_workspace_bytes = 0
topology_transfer_bytes = 0
warm_host_allocations = 299584
compiler_cache = 322 -> 380 -> 380
```

Compiler-cache counts are context-dependent diagnostics, not a fixed
capability identity: the earlier isolated probe observed `4 -> 62 -> 62`,
while the complete runner had already compiled the cross-domain and native
blocks. The executable guarantee is attributable first growth followed by no
second warm growth. Lease exhaustion was rejected before submission without
poison; the complete submitted tail then drained through the single portable
synchronization boundary.
