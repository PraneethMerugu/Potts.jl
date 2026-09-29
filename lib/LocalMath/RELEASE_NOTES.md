# LocalMath 0.2.0-rc2

- Replaces callable-first bounded-fold authoring with `LocalMath.fold(values;
  ...)`, while retaining the checked `BoundedFold` compiler law.
- Adds familiar `sum`, `minimum`, `maximum`, `Statistics.mean`, and qualified
  `LocalMath.geometric_mean` methods for bounded relation and Collection views.
- Gives all bounded reductions explicit result-type, empty-input, absence, and
  canonical-order semantics on the existing transaction-aware executor.
- Adds a device-safe computed-validity flag and bounded diagnostic witness to
  `FoldStep`, preserving atomic ordered-state publication on semantic failure.

# LocalMath 0.2.0-rc1

- First independently versioned release candidate of the typed local scientific-computation language.
- Preserves the historical LocalWorksets and LocalMath development ancestry in the split repository.
- Qualifies one packed KernelAbstractions path on CPU and Metal.
- Owns cross-domain witnesses, compiler benchmarks, authoring documentation, and backend qualification.
