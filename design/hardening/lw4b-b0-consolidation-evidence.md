# LW-4B B0 Common-Mechanism Consolidation Evidence

Date: 2026-08-11

Status: PASS; B1 declaration/route hold may begin

Authority: [LW-4B implementation matrix](lw4b-general-mechanism-implementation-matrix.md)

## Exact change

B0 moved six already shared helpers out of the specialized resolved file into
`execution/mechanism_support.jl`:

- package-owned atomic and value capability queries;
- storage-slot and binding facts;
- backend device copy/adaptation; and
- package-owned kernel-factory validation.

It changed no public name, operation declaration, kernel body, launch sequence, workspace formula,
provider lane, wait, lease, poison rule, qualification row or CorePotts adapter.

| Artifact | Before SHA-256 | B0 SHA-256 |
|---|---|---|
| `src/LocalWorksets.jl` | `a727a7971298b2f2ca0147da05235515f88ee764db5a31c0cabb67c375a82ab4` | `80c7e04ac8292af4621ef71af0b8973a03da123f821f18bad7cdeae9ff50d445` |
| `src/execution/localworksets_resolved.jl` | `1636a201235af4e250eb6e55f86631638efea2497a4f5f0e4231767e0ef3777b` | `b470b9de3418fbbe12dfa984eafb39a4621b8519f0dfe9c2f6931c44d5d2d684` |
| `src/execution/mechanism_support.jl` | absent | `fb2ab7f176615339b0aabd20a0e8b6a6e0f17309e885a010f4e5207a7c58d5b8` |
| `src/execution/localworksets_conjunctive.jl` | `fb982dbed7040f1e8980f28700970c43377f530f69756c7863dc0c18873861df` | unchanged |

## Qualification

| Lane | Result |
|---|---|
| standalone LocalWorksets | 355/355 PASS |
| complete CorePotts CPU | 17,462/17,462 PASS |
| CPU direct/candidate parity | median ratio 1.0088669362; upper95 1.0153797625 <= 1.05 |
| CPU allocation | candidate 1,303,296 < direct 1,318,176 bytes |
| real Metal extension/G5H4 | 2/2 and 37/37 PASS |
| Metal direct/candidate parity | median ratio 1.0020192709; upper95 1.0061720591 <= 1.05 |
| Metal allocation | candidate 17,149,648 < direct 17,678,968 bytes |
| Metal compiler cache | 324 -> 324 |
| ordering/failure | four claim launches, eight sequence launches, one final wait, isolated/shared poison witnesses unchanged |
| static hygiene | `git diff --check` exit 0 |

## Hold disposition

B0 passes. The extracted common file is a package-owned support layer, not an executor hierarchy or
extension registry. Existing specialized lowerings remain exact parity oracles. B1 may add
non-executable declaration, emission and route-validation values; no generic kernel is authorized
until all B1 negative rows pass.
