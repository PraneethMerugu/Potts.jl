# [Hierarchy and open composition](@id hierarchy-open-composition)

> **Support level:** qualified static open composition.

An open composite exposes selected typed stores as import, export, or
bidirectional endpoints. A parent mounts a reusable definition under an
explicit namespace and joins endpoints through exact-compatible stores.

```text
parent.shared
   ├── left.state   (mounted definition instance :left)
   └── right.state  (mounted definition instance :right)
```

Compatibility is exact across value type, shape, units, ontology, update law,
persistence, residency, and endpoint transfer. Composition does not infer
scientific conversion.

Hierarchy is retained in the canonical structure and flattened
deterministically into one execution plan. Mount order does not determine
semantic identity. The Catlab structured-cospan and annotated wiring views are
inspection/interchange products; generic diagrams are not silently accepted
as compilation authority.

**Next:** [Dynamic structural transactions](@ref structural-transactions).
