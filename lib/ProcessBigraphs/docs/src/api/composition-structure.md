# Composition and dynamic structure API

> **Support level:** supported internal beta.

Structural effects are requests against a compiled canonical structure. The
runtime validates a complete candidate, applies it atomically, and records the
new structural epoch. Failed requests leave both data state and structure
unchanged.

```@docs
ProcessBigraphs.spawn
ProcessBigraphs.divide
ProcessBigraphs.remove
ProcessBigraphs.move
```

Use `spawn` for a new admitted instance, `divide` when lineage and
division-law semantics apply, `move` to change a mount relationship, and
`remove` to retire an instance. Each operation is explicit; none silently
rewires unresolved ports.

Before running a dynamic model, call `validate` and inspect `diagram` or
`describe`. At runtime, preserve the diagnostic attached to a rejected
transaction—the code and context identify the violated capacity, schema,
wiring, or continuation rule.
