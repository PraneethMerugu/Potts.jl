# a σ-dependent gather in a cell or edge energy is refused
# at `mtkcompile`. Decision: D-209 (follows D-150, D-041).
#
# The defect (D-208). A gather in a `cells(…)` or
# `edges(…)` energy whose body reads something a copy changes is in `total_energy` but not
# in the generated ΔH: `_cell_delta` substitutes only the cell's own volume, surface, … and
# the gather cancels; edge terms are checked only by `_check_static`. Metropolis then samples
# the wrong distribution. Measured on 487fda85 with the ΔH oracle below (12×12 periodic, two
# 3×3 cells of kind A side by side, Xoshiro(7), T = 2, 3000 draws ≈ 290 compared copies): `count(owner[n] == id
# for n in far(40))` 81 wrong ΔH (worst 0.1); `kind[n]` 59 (0.2); a static body filtered by
# `if owner[n] == id` 35 (0.2); `edges(bond) => 0.1·count(owner[n] == a for n in far(40))`
# 64 (0.1). `volume[owner[n]]` fails at `PottsProblem` with "cannot index `-1 + volume`"; a
# contact-scope gather fails at `PottsProblem` with "cannot index `neighbor_owner`" (ErrorException);
# an `@on_copy`-written site variable read by a cell gather is already an ArgumentError at
# `mtkcompile`, but with the D-045 wording.
#
# Rule pinned here (D-209). A gather (`for n in R(site)`, named or inline) in a `cells(…)`,
# `edges(…)` or `contacts` energy whose body or filter reads
#  - `owner[n]` or `kind[n]` (σ at the gathered site),
#  - `x[owner[n]]` for any cell quantity x (a cell variable or a builtin such as `volume`),
#  - a site variable written by an `@on_copy` update, or one declared
#    `clear_on_ownership_change`,
# is a `PottsCompileError` at `mtkcompile` (so also at `PottsProblem`), naming the statement.
# THE STABLE MESSAGE FRAGMENT: the message contains `a copy changes` (e.g. "… reads `owner[n]`,
# which a copy changes; …") and the statement as `_located` already prints it (`in @energy
# <domain> => …`). Every refusal below checks both; the wording around them is free.
#
# Accepted, unchanged: gathers whose body reads only static values — a site variable no copy
# writes (set from the operating point, or written only at an MCS boundary by `@after_mcs`),
# a parameter, a constant, the cell's own `id` (`count(q[n] == id for n in R(40))`), the edge
# ends `a`, `b` compared with a static site value, and products with copy-varying cell
# quantities outside the gather (`volume * sum(q[n] …)`, `distance * count(q[n] == a …)`).
# For those the ΔH oracle matches exactly (≤ 1e-9; worst 3.6e-15) over 3000 compared copy
# attempts on 487fda85 (about 1765 accepted); the oracle's sensitivity is checked by a
# negative control (a ΔH off by 1 % is caught). Each gather is checked to be read by the
# generated ΔH where it should be (`ctx.far`, `ctx.gather1`).
#
# Also checked: a published model with no gathers (GranerGlazier) passes the ΔH oracle, and two
# published models run: the refusal adds a compile-time check only.
#
# On 487fda85: 83 pass, 77 fail of 160. Every failure is in section 1 and is the missing
# refusal (the forms compile; contacts and `volume[owner[n]]` then fail at `PottsProblem` with
# an ErrorException; the `@on_copy` site variable is a `PottsCompileError` at `mtkcompile` with
# the D-045 wording, located at the `@on_copy` statement, so only its type check passes).
# Sections 0, 2, 3 and 4 pass.
#
# Widened after review (D-209, "Widened after review"; sections 5 and 6, added after the
# implementation 24f38d98/7f20f89b). The same wrong ΔH arises outside gather bodies, so these
# are refused too, with the same message requirements (`a copy changes`, `in @energy <domain>`):
#  1. a σ-dependent gather anchor, cells and edges: `far(owner[40] + 39)`,
#     `Moore(1)(owner[40] + 39)`, and the bare `far(owner[40])`;
#  2. σ at an explicit site outside any gather: cells `owner[40] == id`, `y[owner[40]]`
#     (y = [1, 5]), `kind[40] == A`; edges `owner[40] == a`, `y[owner[40]]`;
#  3. contacts with an explicit index: `owner[40] == 1`, `kind[40] == A`;
#  4. indexed copy-varying builtins and on-copy cell variables in cell terms: `volume[id]`,
#     `volume[1]`, `surface[id]` (inside and outside a gather), `y[id]` with `@on_copy y[new]`
#     (outside and inside a gather). These messages must also name the bare form, in
#     backticks (`volume`, `surface`, `y`).
# Controls (section 6, accepted, ΔH oracle exact over 3000 attempts): contact terms reading
# the bare pair names `owner`, `neighbor_owner`, `kind`, `neighbor_kind`; `y[id]` with y static (outside and
# inside a gather) and with y written `@after_mcs`.
# On 6b06747c (implementation in): sections 0–4 and 6 pass (160 + 24); section 5 fails 69 of
# 92, every failure the missing widened refusal. Most forms compile; `kind[40]` in cells and
# contacts is already an ArgumentError ("`kind[…]` needs a site …") without the D-209 wording.
#
# Second review round (D-209 "Second review round"; sections 7 and 8, after bbb8b096).
# Refused, same message requirements: an explicit-site read of a copy-written site variable
# outside any fold — `act[40]` in contacts with `@on_copy act[target] ~ act[target] + 1.0`,
# and `tag[40]` for `tag(site) = 0.0, [clear_on_ownership_change = true]` in contacts, cells
# and `edges(bond)`, with tag = 1 in the operating point so an accepted form shows the wrong
# ΔH. `kind[id]` is refused with a message containing "bare" (fragment not required: kind
# does not change with a copy). Accepted with an exact ΔH oracle: population folds over a
# bound variable (D-041) — `sum(volume[c] for c in cells)`, `sum((owner[s] == 1) * 1.0 for s
# in sites)`, `sum(y[c] for c in cells)` with `@on_copy` writing y — and the bare pair read
# `act + act′` of an on-copy site variable in a contact term.
# On a6239bad: sections 0–6 pass (276); section 7 fails 13 of 18 (the four site fixtures
# compile; `kind[id]` is already refused without the "bare" wording); section 8 fails 3 of 8 (the three
# population folds are refused by the whole-term walk; the contact pair control passes). The files amended with this change (`relation_fingerprint_tests.jl`, `inline_gather_numbering_tests.jl`, `boundary_only_reach_tests.jl`) replace their
# refused fixtures with the static forms of section 2.

@testsetup module GatherEnergySetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using Random: Xoshiro
using SHA: sha256
# ---------------------------------------------------------------------------------------
# Fixtures: 12×12 periodic, two 3×3 cells of kind A, cell 1 = [2:4, 2:4], cell 2 = [5:7, 2:4]
# (they touch), `(volume - 9)^2`, Metropolis T = 2. `q(site)` is a static site value, set
# from the operating point to the initial owner map; `bond` links cells 1 and 2.
const FRAGMENT = "a copy changes"
const FAR = :(far = EuclideanBall(2.0))
const BOND = :(@relationship bond(cell, cell) capacity = 1)
gather_energy_cells(body) = :(@energy cells => 0.1 * $body)
# the σ-dependent bodies, around site 40 = (4, 4)
const BODIES = [
    "owner[n] == id" => r -> :(count(owner[n] == id for n in $r(40))),
    "owner[n] == 1" => r -> :(count(owner[n] == 1 for n in $r(40))),
    "kind[n]" => r -> :(count(kind[n] == A for n in $r(40))),
    "y[owner[n]]" => r -> :(sum(y[owner[n]] for n in $r(40))),
]
const RELS = ["far(40)" => (FAR, :far), "EuclideanBall(2.0)(40)" => (nothing, :(EuclideanBall(2.0))), "Moore(1)(40)" => (nothing, :(Moore(1)))]
# label => (@relations body or nothing, statements, the refused statement's domain as printed)
const REFUSED = Any[]
for (bl, b) in BODIES, (rl, (rel, r)) in RELS
    push!(REFUSED, "cells $bl, $rl" => (rel, [gather_energy_cells(b(r))], "cells"))
end
append!(
    REFUSED, [
        "cells kind[n] numeric" => (nothing, [gather_energy_cells(:(sum(kind[n] for n in Moore(1)(40))))], "cells"),
        "cells volume[owner[n]]" => (nothing, [:(@energy cells => 0.001 * sum(volume[owner[n]] for n in Moore(1)(40)))], "cells"),
        "cells static body, owner filter" => (nothing, [gather_energy_cells(:(sum(q[n] for n in Moore(1)(40) if owner[n] == id)))], "cells"),
        "cells indicator sum" => (nothing, [gather_energy_cells(:(sum((owner[n] == id) * 1.0 for n in Moore(1)(40))))], "cells"),
        "cells(A), inside the volume term" => (
            FAR,
            [:(@energy cells(A) => (volume - 8.0)^2 + 0.1 * count(owner[n] == id for n in far(40)))], "cells(A)",
        ),
        "cells, an @on_copy-written site variable" => (
            nothing, [
                :(@variables act(site) = 0.0), :(@on_copy act[target] ~ 1.0),
                gather_energy_cells(:(sum(act[n] for n in Moore(1)(40)))),
            ], "cells",
        ),
        "cells, a clear_on_ownership_change site variable" => (
            nothing,
            [:(@variables tag(site) = 0.5, [clear_on_ownership_change = true]), gather_energy_cells(:(sum(tag[n] for n in Moore(1)(40))))], "cells",
        ),
        # the `boundary_only_reach_tests.jl` copy-step edge fixture, named and inline
        "edges(bond) owner[n] == a/b, far(40)" => (
            FAR, [
                BOND,
                :(@energy edges(bond) => 0.1 * (count(owner[n] == a for n in far(40)) + count(owner[n] == b for n in far(40))))
            ], "edges(bond)",
        ),
        "edges(bond) owner[n] == a/b, EuclideanBall(2.0)(40)" => (
            nothing, [
                BOND,
                :(@energy edges(bond) => 0.1 * (count(owner[n] == a for n in EuclideanBall(2.0)(40)) + count(owner[n] == b for n in EuclideanBall(2.0)(40))))
            ],
            "edges(bond)",
        ),
        "edges(bond) kind[n]" => (nothing, [BOND, :(@energy edges(bond) => 0.1 * count(kind[n] == A for n in Moore(1)(40)))], "edges(bond)"),
        "edges(bond) y[owner[n]]" => (nothing, [BOND, :(@energy edges(bond) => 0.1 * sum(y[owner[n]] for n in Moore(1)(40)))], "edges(bond)"),
        # contacts (today an accidental "cannot index `neighbor_owner`" at PottsProblem)
        "contacts owner[n] == owner, far(40)" => (FAR, [:(@energy contacts => 0.1 * count(owner[n] == owner for n in far(40)))], "contacts"),
        "contacts owner[n] == 1, far(40)" => (FAR, [:(@energy contacts => 0.1 * count(owner[n] == 1 for n in far(40)))], "contacts"),
        "contacts owner[n] == 1, EuclideanBall(2.0)(40)" => (nothing, [:(@energy contacts => 0.1 * count(owner[n] == 1 for n in EuclideanBall(2.0)(40)))], "contacts"),
    ]
)
# accepted static gathers: label => (@relations body or nothing, statements, relation name read by ΔH or nothing)
const ACCEPTED = [
    "cells volume·Σq, far(40)" => (FAR, [:(@energy cells => 0.01 * volume * sum(q[n] for n in far(40)))], :far),
    "cells volume·Σq, EuclideanBall(2.0)(40)" => (nothing, [:(@energy cells => 0.01 * volume * sum(q[n] for n in EuclideanBall(2.0)(40)))], :gather1),
    "cells count(q[n] == id), Moore(2)(40)" => (nothing, [gather_energy_cells(:(count(q[n] == id for n in Moore(2)(40))))], nothing),
    "cells parameter and static filter, far(40)" => (
        FAR, [
            :(@parameters w = 0.5),
            :(@energy cells => 0.01 * volume * sum(w * q[n] for n in far(40) if q[n] > 0))
        ], :far,
    ),
    "cells @after_mcs-written site variable, far(40)" => (
        FAR, [
            :(@variables r(site) = 0.0), :(@after_mcs r ~ q + 0.01 * mcs),
            :(@energy cells => 0.01 * volume * sum(r[n] for n in far(40)))
        ], :far,
    ),
    "edges(bond) distance·count(q[n] == a/b), far(40)" => (
        FAR, [
            BOND,
            :(@energy edges(bond) => 0.1 * distance * (count(q[n] == a for n in far(40)) + count(q[n] == b for n in far(40))))
        ], :far,
    ),
]
# Widened after review (D-209 "Widened after review"): σ read outside gather bodies.
# label => (@relations body or nothing, statements, domain as printed, bare form the message
# suggests or nothing). These fixtures start with y = [1, 5] (cell variable, from the
# operating point).
const ONCOPY_Y = :(@on_copy y[new] ~ y[new] + 1.0)
const WIDE = [
    # 1. a σ-dependent gather anchor (the body is static)
    "anchor cells far(owner[40] + 39)" => (FAR, [gather_energy_cells(:(sum(q[n] for n in far(owner[40] + 39))))], "cells", nothing),
    "anchor cells Moore(1)(owner[40] + 39)" => (nothing, [gather_energy_cells(:(sum(q[n] for n in Moore(1)(owner[40] + 39))))], "cells", nothing),
    "anchor cells far(owner[40])" => (FAR, [gather_energy_cells(:(sum(q[n] for n in far(owner[40]))))], "cells", nothing),
    "anchor edges far(owner[40] + 39)" => (
        FAR, [
            BOND,
            :(@energy edges(bond) => 0.1 * sum(q[n] for n in far(owner[40] + 39)))
        ], "edges(bond)", nothing,
    ),
    "anchor edges Moore(1)(owner[40] + 39)" => (
        nothing, [
            BOND,
            :(@energy edges(bond) => 0.1 * sum(q[n] for n in Moore(1)(owner[40] + 39)))
        ], "edges(bond)", nothing,
    ),
    "anchor edges far(owner[40])" => (
        FAR, [
            BOND,
            :(@energy edges(bond) => 0.1 * sum(q[n] for n in far(owner[40])))
        ], "edges(bond)", nothing,
    ),
    # 2. σ at an explicit site, outside any gather
    "explicit cells owner[40] == id" => (nothing, [gather_energy_cells(:(owner[40] == id))], "cells", nothing),
    "explicit cells y[owner[40]]" => (nothing, [gather_energy_cells(:(y[owner[40]]))], "cells", nothing),
    "explicit cells kind[40] == A" => (nothing, [gather_energy_cells(:(kind[40] == A))], "cells", nothing),
    "explicit edges owner[40] == a" => (nothing, [BOND, :(@energy edges(bond) => 0.1 * (owner[40] == a))], "edges(bond)", nothing),
    "explicit edges y[owner[40]]" => (nothing, [BOND, :(@energy edges(bond) => 0.1 * y[owner[40]])], "edges(bond)", nothing),
    # 3. contacts with an explicit index
    "explicit contacts owner[40] == 1" => (nothing, [:(@energy contacts => 0.1 * (owner[40] == 1))], "contacts", nothing),
    "explicit contacts kind[40] == A" => (nothing, [:(@energy contacts => 0.1 * (kind[40] == A))], "contacts", nothing),
    # 4. indexed copy-varying builtins and on-copy cell variables in cell terms
    "indexed volume[id], outside a gather" => (FAR, [gather_energy_cells(:(0.1 * volume[id] * sum(q[n] for n in far(40))))], "cells", "volume"),
    "indexed volume[id], inside a gather" => (FAR, [gather_energy_cells(:(sum(0.1 * volume[id] * q[n] for n in far(40))))], "cells", "volume"),
    "indexed volume[1], outside a gather" => (nothing, [gather_energy_cells(:(0.01 * volume[1]))], "cells", "volume"),
    "indexed volume[1], inside a gather" => (nothing, [gather_energy_cells(:(0.01 * sum(volume[1] * q[n] for n in Moore(1)(40))))], "cells", "volume"),
    "indexed surface[id], outside a gather" => (nothing, [gather_energy_cells(:(0.1 * surface[id]))], "cells", "surface"),
    "indexed surface[id], inside a gather" => (FAR, [gather_energy_cells(:(sum(0.1 * surface[id] * q[n] for n in far(40))))], "cells", "surface"),
    "indexed y[id], y written @on_copy y[new]" => (nothing, [ONCOPY_Y, gather_energy_cells(:(volume * y[id]))], "cells", "y"),
    "indexed y[id] in a gather, y written @on_copy y[new]" => (
        FAR, [
            ONCOPY_Y,
            gather_energy_cells(:(sum(y[id] * q[n] for n in far(40)))),
        ], "cells", "y",
    ),
]
# controls of the widening: accepted, ΔH exact. label => (@relations body or nothing, statements, nothing)
const WIDE_OK = [
    "control contacts bare owner, neighbor_owner, kind, neighbor_kind" => (
        nothing,
        [:(@energy contacts => 0.1 * ((owner == 1) + (neighbor_owner == 1)) + 0.2 * (kind == neighbor_kind) + 0.3 * (neighbor_kind == A))], nothing,
    ),
    "control y[id], y static" => (nothing, [gather_energy_cells(:(volume * y[id]))], nothing),
    "control y[id] in a gather, y static" => (FAR, [gather_energy_cells(:(volume * sum(y[id] * q[n] for n in far(40))))], nothing),
    "control y[id], y written @after_mcs" => (nothing, [:(@after_mcs y ~ y + 1.0), gather_energy_cells(:(volume * y[id]))], nothing),
]
const Y15 = Set(first.([WIDE; WIDE_OK]))
# Second review round (D-209 "Second review round"): an explicit-site read of a copy-written
# site variable, outside any fold, in every domain. `tag` defaults to 0 and starts at 1 (from
# the operating point), so a clear on ownership change moves the energy.
const ACT = [:(@variables act(site) = 0.0), :(@on_copy act[target] ~ act[target] + 1.0)]
const TAG = :(@variables tag(site) = 0.0, [clear_on_ownership_change = true])
const SITE = [
    "site contacts act[40], act written @on_copy" => (nothing, [ACT..., :(@energy contacts => 0.1 * act[40])], "contacts", nothing),
    "site contacts tag[40], clear_on_ownership_change" => (nothing, [TAG, :(@energy contacts => 0.1 * tag[40])], "contacts", nothing),
    "site cells tag[40], clear_on_ownership_change" => (nothing, [TAG, gather_energy_cells(:(tag[40]))], "cells", nothing),
    "site edges(bond) tag[40], clear_on_ownership_change" => (
        nothing, [
            BOND, TAG,
            :(@energy edges(bond) => 0.1 * tag[40])
        ], "edges(bond)", nothing,
    ),
]
# `kind[id]`: refused with a hint to read it bare (not a copy-changed read; no fragment required)
const KIND_ID = ["indexed kind[id] == A" => (nothing, [gather_energy_cells(:(kind[id] == A))], "cells", nothing)]
# controls: accepted, ΔH exact. Population folds over a bound variable (D-041), and the bare
# pair read of an on-copy site variable in a contact term.
const POP_OK = [
    "control population sum(volume[c] for c in cells)" => (nothing, [gather_energy_cells(:(0.01 * sum(volume[c] for c in cells)))], nothing),
    "control population sum((owner[s] == 1) * 1.0 for s in sites)" => (
        nothing,
        [gather_energy_cells(:(0.1 * sum((owner[s] == 1) * 1.0 for s in sites)))], nothing,
    ),
    "control population sum(y[c] for c in cells), y written @on_copy" => (
        nothing, [
            ONCOPY_Y,
            gather_energy_cells(:(sum(y[c] for c in cells))),
        ], nothing,
    ),
    "control contacts bare act, act′, act written @on_copy" => (
        nothing, [
            ACT...,
            :(@energy contacts => 0.1 * (act + act′))
        ], nothing,
    ),
]
const TAG1 = Set(first.(SITE))
const MODELS = Dict{String, Any}()
const DOMAIN = Dict{String, String}()
const READS = Dict{String, Any}()
const BARE = Dict{String, Any}()
for (i, (label, fx)) in enumerate([REFUSED; ACCEPTED; WIDE; WIDE_OK; SITE; KIND_ID; POP_OK])
    rel, body, extra = fx
    length(fx) == 4 && (BARE[label] = fx[4])
    name = Symbol(:Gather, i)
    ln = LineNumberNode(@__LINE__, Symbol(@__FILE__))
    relx = rel === nothing ? nothing : Expr(:macrocall, Symbol("@relations"), ln, rel)
    @eval @potts_model $name begin
        @kinds medium A
        @variables y(cell) = 0.0 q(site) = 0.0
        @lattice Lattice((12, 12))
        $relx
        @energy cells => (volume - 9.0)^2
        $(body...)
        @sweep Metropolis(; temperature = 2.0)
    end
    MODELS[label] = @eval $name
    extra isa String ? (DOMAIN[label] = extra) : (READS[label] = extra)
end
function sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[5:7, 2:4] .= 2
    return σ
end
gather_energy_op(label) = Any[
    ownership => sigma(), kind => [:A, :A], :q => Float64.(sigma()),
    (occursin("edges", label) ? [:bond => [(1, 2)]] : [])..., (label in Y15 ? [:y => [1.0, 5.0]] : [])...,
    (label in TAG1 ? [:tag => fill(1.0, 12, 12)] : [])...,
]
system(label) = Base.invokelatest(MODELS[label]; name = :g)
problem(label; tspan = (0, 3), seed = 1) = PottsProblem(system(label), gather_energy_op(label), tspan; seed, capacity = 16)
"""The exception `mtkcompile` throws for fixture `label`, or `nothing` if it compiles."""
function compile_error(label)
    sys = system(label)
    try
        mtkcompile(sys)
        return nothing
    catch e
        return e
    end
end
"""Is `e` the refusal of a cell-dependent gather in a statement in domain `dom`?"""
is_refusal(e, dom) = e isa Potts.PottsCompileError && occursin("$dom", e.msg)
"""ΔH oracle: a Metropolis chain driven by `dH(u, p, prop, ctx)` (default the generated
`delta_H`), `nsteps` copy attempts (unlike pairs, Moore(1) source) each compared with
total_energy(after) − total_energy(before) + the killing credit. Returns (attempts compared,
mismatches > 1e-9, worst error, accepted)."""
function gather_energy_oracle(prob; nsteps = 3000, rng = Xoshiro(7), Tm = 2.0, dH = prob.f.delta_H)
    u = deepcopy(prob.u0)
    p = prob.p
    ctx = Potts._host_ctx(prob)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    n = bad = acc = tries = 0
    worst = 0.0
    while n < nsteps && tries < 1000 * nsteps
        tries += 1
        t = rand(rng, 1:length(u.ownership))
        x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, moore.offsets[rand(rng, 1:length(moore))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s])
        d = dH(u, p, prop, ctx)
        a = deepcopy(u)
        a.ownership[t] = prop.new
        prob.f.commit!(a, p, prop, ctx)
        dtrue = total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a)
        err = abs(d - dtrue)
        n += 1
        bad += err > 1.0e-9
        worst = max(worst, err)
        if d <= 0 || rand(rng) < exp(-d / Tm)
            u = a
            acc += 1
        end
    end
    return (; n, bad, worst, acc)
end
"""Relations of `names` that the generated ΔH of `label` reads (`ctx.<name>`)."""
dh_reads(label, names) = Potts._ctx_reads!(Set{Symbol}(), generated_code(system(label)).delta_H, names)
# ---------------------------------------------------------------------------------------
# 4. Published models are unchanged (fingerprints and trajectories recorded on 487fda85)
"""SHA-256 of a SequentialCPM run (every MCS saved): σ and volumes of each state, and the attempt count."""
function gather_energy_digest(prob)
    sol = solve(prob, SequentialCPM(); saveat = 1)
    io = IOBuffer()
    for u in sol.u
        write(io, htol.(vec(u.ownership)))
        write(io, htol.(Int64.(u.cell.volume)))
    end
    write(io, htol(Int64(sol.stats.attempts)), htol(Int64(length(sol.u))))
    return bytes2hex(sha256(take!(io)))
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "gather energy: controls — the fixtures build their models" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 0. Controls (pass on the base)
    @testset "gather energy: controls — the fixtures build their models" begin
        for (label, _) in [REFUSED; ACCEPTED]
            @test system(label) isa Potts.PottsSystem          # the macro and the constructor accept every form
        end
        @test LinearIndices((12, 12))[4, 4] == 40
    end
end

@testitem "gather energy: a σ-dependent gather in an energy is refused at mtkcompile" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Refusals at mtkcompile (base: they build, or fail later with another error)
    @testset "gather energy: a σ-dependent gather in an energy is refused at mtkcompile" begin
        for (label, _) in REFUSED
            @testset "$label" begin
                dom = DOMAIN[label]
                e = compile_error(label)
                @test e isa Potts.PottsCompileError
                ok = is_refusal(e, dom)
                @test ok
                ok || @info "gather energy: `$label` at mtkcompile: $(e === nothing ? "compiles" : sprint(showerror, e))"
                # the model build refuses it too, with the same refusal
                e2 = try
                    problem(label)
                    nothing
                catch err
                    err
                end
                @test is_refusal(e2, dom)
            end
        end
    end
end

@testitem "gather energy: a static gather in an energy builds and its ΔH is exact" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Static gathers stay allowed, and their ΔH is exact
    @testset "gather energy: a static gather in an energy builds and its ΔH is exact" begin
        for (label, _) in ACCEPTED
            @testset "$label" begin
                @test compile_error(label) === nothing
                prob = problem(label)
                r = gather_energy_oracle(prob)
                @test r.n == 3000
                @test r.acc >= 100                                   # the chain moves
                @test r.bad == 0
                @test r.worst <= 1.0e-9
                @info "gather energy: `$label` oracle $r"
                rel = READS[label]
                rel === nothing || @test rel in dh_reads(label, (rel,))   # the gather is in the copy step
            end
        end
        # the static gather is what it claims: hand values on the initial state
        # (q = the initial owner map; far = EuclideanBall(2.0) around (4, 4) holds 5 sites of cell 1 and 3 of cell 2)
        p = problem("cells volume·Σq, far(40)")
        @test total_energy(p, p.u0) ≈ 2 * 0.01 * 9 * (5 * 1 + 3 * 2)
        p = problem("edges(bond) distance·count(q[n] == a/b), far(40)")
        @test total_energy(p, p.u0) ≈ 0.1 * 3.0 * 8                  # centroids 3 apart, 5 + 3 sites
        p = problem("cells count(q[n] == id), Moore(2)(40)")
        @test total_energy(p, p.u0) ≈ 0.1 * (8 + 6)                  # Moore(2) around (4, 4): 8 of cell 1, 6 of cell 2
        # negative control: the oracle catches a ΔH off by 1 %
        prob = problem("cells volume·Σq, far(40)")
        wrong = gather_energy_oracle(prob; dH = (u, p, prop, ctx) -> 1.01 * prob.f.delta_H(u, p, prop, ctx))
        @test wrong.bad > 0
    end
end

@testitem "gather energy: ΔH oracle on GranerGlazier (no gathers)" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. The ΔH oracle on a published model without gathers
    @testset "gather energy: ΔH oracle on GranerGlazier (no gathers)" begin
        σ, kinds = graner_glazier_state()
        prob = PottsProblem(GranerGlazier(; name = :gg), [ownership => σ, kind => kinds], (0, 3); seed = 1)
        r = gather_energy_oracle(prob; nsteps = 2000, Tm = 10.0)
        @info "gather energy: GranerGlazier oracle $r"
        @test r.n == 2000
        @test r.acc >= 100
        @test r.bad == 0
        @test r.worst <= 1.0e-9
    end
end

@testitem "gather energy: published models build and their digest is deterministic" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "gather energy: published models build and their digest is deterministic" begin
        gg = let (σ, kinds) = graner_glazier_state()
            PottsProblem(GranerGlazier(; name = :gg), [ownership => σ, kind => kinds], (0, 5); seed = 3)
        end
        ov = PottsProblem(
            OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)), openvt_monolayer_state(; lattice = (24, 24)),
            (0, 10); capacity = 64, seed = 3
        )
        for (name, prob) in (("GranerGlazier", gg), ("OpenVTGrowingMonolayer", ov))
            @testset "$name" begin
                @test gather_energy_digest(prob) == gather_energy_digest(prob)      # deterministic
            end
        end
    end
end

@testitem "gather energy: σ read outside a gather body is refused at mtkcompile" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 5. Widened after review: σ outside gather bodies (anchors, explicit sites, contacts with an
    #    explicit index, indexed copy-varying cell quantities). Same message requirements; the
    #    indexed forms also name the bare form (`volume`, `surface`, `y`, in backticks).
    @testset "gather energy: σ read outside a gather body is refused at mtkcompile" begin
        for (label, _) in WIDE
            @testset "$label" begin
                dom = DOMAIN[label]
                bare = BARE[label]
                @test system(label) isa Potts.PottsSystem          # the model is built; the refusal is the compiler's
                e = compile_error(label)
                @test e isa Potts.PottsCompileError
                ok = is_refusal(e, dom)
                @test ok
                ok || @info "gather energy: `$label` at mtkcompile: $(e === nothing ? "compiles" : sprint(showerror, e))"
                bare === nothing || @test e isa Potts.PottsCompileError && occursin("`$bare`", e.msg)
                e2 = try
                    problem(label)
                    nothing
                catch err
                    err
                end
                @test is_refusal(e2, dom)
            end
        end
    end
end

@testitem "gather energy: controls of the widening are accepted and their ΔH is exact" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "gather energy: controls of the widening are accepted and their ΔH is exact" begin
        for (label, _) in WIDE_OK
            @testset "$label" begin
                @test compile_error(label) === nothing
                prob = problem(label)
                @test prob.u0.cell.y[1:2] == [1.0, 5.0]
                r = gather_energy_oracle(prob)
                @test r.n == 3000
                @test r.acc >= 100
                @test r.bad == 0
                @test r.worst <= 1.0e-9
                @info "gather energy: `$label` oracle $r"
            end
        end
    end
end

@testitem "gather energy: an explicit-site read of a copy-written site variable is refused" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 7. Second review round: explicit-site reads of a copy-written site variable are refused;
    #    population folds over a bound variable and bare contact pair reads stay accepted.
    @testset "gather energy: an explicit-site read of a copy-written site variable is refused" begin
        for (label, _) in SITE
            @testset "$label" begin
                dom = DOMAIN[label]
                @test system(label) isa Potts.PottsSystem
                e = compile_error(label)
                @test e isa Potts.PottsCompileError
                ok = is_refusal(e, dom)
                @test ok
                ok || @info "gather energy: `$label` at mtkcompile: $(e === nothing ? "compiles" : sprint(showerror, e))"
                e2 = try
                    problem(label)
                    nothing
                catch err
                    err
                end
                @test is_refusal(e2, dom)
            end
        end
        @testset "indexed kind[id]: refused, with a hint to read it bare" begin
            e = compile_error("indexed kind[id] == A")
            @test e isa Potts.PottsCompileError
            @test e isa Potts.PottsCompileError && occursin("bare", e.msg)
            e isa Potts.PottsCompileError || @info "indexed `kind[id]` at mtkcompile: $(e === nothing ? "compiles" : sprint(showerror, e))"
        end
    end
end

@testitem "gather energy: population folds and bare contact pair reads are accepted, ΔH exact" setup = [GatherEnergySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "gather energy: population folds and bare contact pair reads are accepted, ΔH exact" begin
        for (label, _) in POP_OK
            @testset "$label" begin
                e = compile_error(label)
                @test e === nothing
                e === nothing || @info "gather energy: `$label` at mtkcompile: $(sprint(showerror, e))"
                if e === nothing
                    r = gather_energy_oracle(problem(label))
                    @test r.n == 3000
                    @test r.acc >= 100
                    @test r.bad == 0
                    @test r.worst <= 1.0e-9
                    @info "gather energy: `$label` oracle $r"
                end
            end
        end
    end
end
