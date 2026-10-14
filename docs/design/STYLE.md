# Docs writing style

These rules borrow the writing rules of ASD-STE100 (Simplified Technical English). They do
not adopt its controlled dictionary. Technical terms, Julia names and a paper's notation
are always allowed. How strictly the rules apply depends on the page tier (§1).

## 1. Page tiers

| Tier | Pages | Rules that apply |
|---|---|---|
| **Procedural** | `getting_started.md` (from *Step 1*), `tutorials/*`, `workshop.md`, `faq.md`, the *Usage* and *Examples* parts of docstrings, run and install instructions | All of §2, §3 and §4 |
| **Reference** | `manual/*`, `api.md`, `modelingtoolkit.md`, `coming_from.md`, `index.md`, the concept part of `getting_started.md` | §3 and §4; §2 as guidance |
| **Paper** | `models/*`, `published/*`, reproduction write-ups | §4 only, and only where the paper does not say otherwise. The paper's terms and symbols win (see *Docs paper fidelity*). Explain a paper term once with the glossary term: "the paper's *differential adhesion* (our contact energy `J`)" |

## 2. Procedural rules

1. **One instruction per sentence.** Write it as a command: "Set `T = 10`." Do not write
   "You may want to set `T` to 10."
2. **At most 20 words** in an instruction sentence. Code spans count as one word.
3. **Number the steps** when their order matters. One step is one action and its result.
4. **Put a warning before the step it applies to.** Use `!!! warning`, and start with the
   consequence: "This overwrites `sol`." Use `!!! note` for things that are not hazards.
5. **Name the condition first:** "If the lattice is 3D, set `spacing`." Do not write
   "Set `spacing`, if the lattice is 3D."
6. **Show the expected result** after a step whose outcome is not obvious, for example a
   printed value, a figure or the run time on the reference machine.

## 3. Sentence rules

1. **Use the active voice.** "Potts.jl derives ``\Delta H``", not "``\Delta H`` is
   derived". The passive voice is fine when the actor does not matter ("cells are
   removed when their volume reaches 0").
2. **At most 25 words** in a descriptive sentence. Split a long sentence at its "and",
   "which" or semicolon.
3. **One topic per sentence, and one topic per paragraph.**
4. **No filler words:** *simply*, *just*, *easily*, *obviously*, *of course*, *note that*,
   *it should be noted*.
5. **Say what a thing does, then how.** The first sentence of a page or section says what
   it gives the reader.
6. **Use numbers and units**, not *fast*, *large* or *a few*: "about 3 s per 1000 MCS
   on a 200 × 200 lattice".
7. **Use a list for three or more parallel items**, and a table for items that share
   attributes.

## 4. Terminology

Use one term for one concept, everywhere. The first column is the term to use. An alias is
allowed only where the table says. Never use the words in the *Avoid* column.

### Spelling

Use American spelling everywhere: prose, docstrings, code comments and new identifiers.
Write *neighbor*, *neighborhood*, *color*, *center*, *gray*, *modeling*, *behavior*,
*tumor*, *-ize*. Keep British spelling only inside a quoted title or a direct quote.

### Glossary

| Use | Meaning | Alias allowed | Avoid |
|---|---|---|---|
| **site** | one lattice point | *pixel* (2D) or *voxel* (3D), once, when introducing *site* | lattice cell, grid point, node |
| **lattice** | the grid of sites | *grid*, in the concept introduction only | mesh, board |
| **cell** | the set of sites with one cell number | — | domain (in the biological sense), blob, object |
| **cell number** | the integer that a site holds (σ in the papers) | σ, in maths | spin, label, ID (outside code) |
| **medium** | cell number 0, the space around the cells | *ECM*, only where a paper says ECM | background, empty, void |
| **kind** | the class of a cell (`@kinds`) | *type*, once, as "(also called a type)" | cell type, species, tau (outside a paper's notation) |
| **frozen kind** | a kind whose cells never move (`[frozen]`) | *obstacle*, for the cells of a frozen kind | fixed, wall (unless the paper says so) |
| **energy** ``H`` | the sum of the `@energy` terms | *Hamiltonian*, in paper and reference tiers | energy function, cost, objective |
| **energy change** ``\Delta H`` | the change in ``H`` caused by one copy | — | delta energy, dH |
| **contact energy** `J` | the energy per pair of neighboring sites of different cells | *adhesion energy*, where a paper says so | surface tension (unless the paper means it), bond energy |
| **volume** | the number of sites of a cell, also in 2D | *area*, only in a 2D paper's notation (`V₀` is still `V₀`) | size, mass |
| **target volume** `V₀` | the volume that the volume term prefers | *target area* in a 2D paper's notation | preferred size, rest volume |
| **copy** | writing the source site's cell number into the target site | — | spin flip, index copy, flip |
| **copy attempt** | one proposed copy and its accept or reject decision | *proposal*, for the choice of source and target only | trial, update, move |
| **target site**, **source site** | the site that changes, and the site whose cell number is copied | — | destination, origin |
| **relation** | a set of neighbor offsets (`@relations`) | *neighborhood*, when introducing *relation* | stencil, kernel |
| **proposal relation**, **contact relation** | the relation for copy sources, and the relation for contact energy | *copy neighborhood*, in `coming_from.md` only | — |
| **temperature** `T` | the Metropolis temperature | *motility*, only in a paper that uses it | noise, fluctuation amplitude |
| **Metropolis rule** | accept with probability ``\min(1, e^{-\Delta H / T})`` | — | Boltzmann acceptance, Glauber (unless that rule is used) |
| **MCS** | one Monte Carlo step: as many copy attempts as there are sites | *Monte Carlo step*, at first use on a page | sweep (see below), time step, step, iteration, tick |
| **sweep** | the `@sweep` protocol, or the copy-attempt phase in `@schedule` | — | do not use *sweep* to mean one MCS |
| **time step** | the step of an ODE or PDE solver | — | MCS, step (alone) |
| **replicate** | one of several runs that differ only in the seed | *trajectory*, in `EnsembleProblem` code (`trajectories = 4`) | realization, sample, repeat |
| **ensemble** | a set of runs solved together (`EnsembleProblem`) | — | batch (unless it means a batch of jobs) |
| **seed** | the integer that fixes the random streams | — | random state, RNG key |
| **backend** | the KernelAbstractions device (`CPU()`, `MetalBackend()`, `ROCBackend()`) | *GPU*, when only GPUs are meant | device (outside code), accelerator |
| **ModelingToolkit** | the SciML package | *MTK*, after the first use on a page | ModelingToolKit |

### Adding a term

Add a row when a page introduces a concept that users must name. Before adding a synonym,
search the docs for the term already in use (`grep -rn` under `docs/src`) and keep it.
