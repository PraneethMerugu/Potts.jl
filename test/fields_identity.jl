# F2 guard (F2 design §4 F2-01, §5): the behavior and the fingerprints of the field pipeline,
# recorded on lp/f1 bda31989 (F1 accepted) and checked at every commit of the F2 series.
#
# - Hard set (`GD_HARD`): per model, at Float64 and Float32, the canonical solver string, each
#   `:field_program` entry of the generated code (fingerprint text, arrays, parameters, tables,
#   least count, bounded flag), the problem fingerprint, the substep count `n` of every field
#   group at the default parameters, and a CPU digest of every site array and σ after 5 MCS
#   (SequentialCPM, seed 7). The behavior records (`n`, digests) are hard for every model; the
#   fingerprint records are hard for the pinned models (`pinned = true`: the frozen pins of
#   p6_0o and p6_0g, asserted below as well). A fingerprint move of an unpinned hard model
#   (Merks2006, Merks2008, FdTwo) is allowed only when the commit's plan lists it; the commit
#   then updates the record here, with its cause.
# - Soft set (`GD_SOFT`): the `test/fields.jl` models, the `test/audit.jl` field models (copies,
#   prefixed `Gd`) and the p6_5c Fortuna-like model (a copy), at Float64: the route (automatic
#   count or explicit), the problem fingerprint, the `:field_program` entries and `n`. A move
#   must be listed by the commit that makes it, which updates the record with its cause.
#
# `POTTS_GUARD_RECORD=<path>` writes the computed records to `<path>` (one `"key" => "value",`
# per line) for a new recording; the checks run as well.
using Potts, Test
using Potts: CorePotts
using PottsModels: MerksVasculogenesis, Merks2006, Merks2008

isdefined(Main, :FdTwo) || include(joinpath(@__DIR__, "fields.jl"))

# ---------------------------------------------------------------------------------------
# Copies of the pinned fixtures (p6_0o `P60oField`, p6_0g `P60gX`), verbatim

@potts_model P60oField begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
        χ = 3.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 9.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = χ, kinds = (dark,))
    @equations D(c) ~ 0.1 * Δ(c) + 0.02 * (kind == dark) - 0.01 * c
    @sweep Metropolis(; temperature = Tk[kind], combine = min)
end
const GD_OP_FIELD = [ownership => (s = zeros(Int32, 16, 16); s[:, 1] .= 1; s[4:6, 4:6] .= 2; s[10:12, 10:12] .= 3; s),
    kind => [:wall, :dark, :light]]

@potts_model P60gX begin
    @kinds medium fluid matrix tip stalk
    @parameters begin
        J[kind, kind] = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
        χ = 4.0
    end
    @variables begin
        V(site) = 0.0
        gain(site) = 0.0
        near(site) = 0.0
        tgt(cell) = 0.0
        age(cell) = 0.0
        g(cell) = 0.0
        q(field) = 0.0
        n_ec(model) = 0.0
    end
    @lattice Lattice((32, 24); neighborhood = Moore(1))
    @energy begin
        cells(tip, stalk) => 2.0 * (volume - 16)^2
        cells(fluid, matrix) => 0.02 * (volume - tgt)^2
        contacts => J[kind, kind′] + 3.0 * ((kind == tip) || (kind == stalk)) * ((kind′ == fluid) || (kind′ == matrix))
        sites => -0.5 * V * ((kind == tip) || (kind == stalk))
    end
    @drive begin
        copy => ifelse((kind[new] == tip) || (kind[new] == stalk), -χ * (V[target] - V[source]), 0.0)
        Chemotaxis(V; strength = 1.5, kinds = (tip, stalk))
    end
    @constraint begin
        connectivity(tip, stalk)
        !(((kind[old] == fluid) || (kind[old] == matrix)) && ((kind[new] == fluid) || (kind[new] == matrix)))
    end
    @on_copy gain[target] += ((kind[new] == tip) || (kind[new] == stalk))
    @before_mcs n_ec ~ count(true for c in cells(tip, stalk))
    @after_mcs begin
        age ~ Pre(age) + ((kind == tip) || (kind == stalk))
        near ~ count(true for n in Moore(1)(site) if (kind[n] == fluid) || (kind[n] == matrix))
    end
    @equations begin
        D(g) ~ 0.5 * ((kind == tip) || (kind == stalk))
        D(q) ~ 0.25 * ((kind == tip) || (kind == stalk))
    end
    @observed begin
        nec ~ count(true for c in cells(tip, stalk))
        vecm ~ sum(volume for c in cells(fluid, matrix))
        nmix ~ count(true for c in cells if ((kind[c] == fluid) || (kind[c] == matrix)) || (kind[c] == tip))
        nmix2 ~ count(true for c in cells(fluid, matrix, tip))
        nnot ~ count(true for c in cells if !((kind[c] == tip) || (kind[c] == stalk)))
    end
    @sweep Metropolis(; temperature = 3.0)
end
function gd_p60g_op()
    σ = fill(Int32(1), 32, 24)
    σ[:, 9:10] .= 2; σ[:, 17:18] .= 3
    σ[4:7, 3:6] .= 4
    σ[4:7, 12:15] .= 5
    σ[12:15, 12:15] .= 6
    kinds = [:fluid, :matrix, :matrix, :tip, :stalk, :stalk]
    return [ownership => σ, kind => kinds, :V => [x / 32 for x in 1:32, y in 1:24],
        :tgt => Float64[count(==(c), σ) for c in 1:length(kinds)]]
end

# the frozen pins these copies reproduce (p6_0o:614–617, :630; p6_0g:635)
const GD_PINS = Dict("MerksVasculogenesis|Float64" => 0xd89dd8d35e4384c8,
    "MerksVasculogenesis|Float32" => 0xb6af11159cf2d5bf,
    "MerksVasculogenesis contact-inhibited|Float32" => 0xbb90e55fb8ea25e1,
    "MerksVasculogenesis contact-inhibited|Float64" => 0x8c92c320ca533e38,
    "fixture field|Float64" => 0x1f65bf177c5435c4,
    "P60gX|Float64" => 0xcaa274201d432e7d)

# ---------------------------------------------------------------------------------------
# Copies of the `test/audit.jl` field models and of the p6_5c Fortuna-like model (soft set)

@potts_model GdAuditDiffusion begin
    @kinds medium A
    @parameters Dc = 0.1
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @equations D(c) ~ Dc * Δ(c)
    @sweep Metropolis(; temperature = 5.0)
end
@potts_model GdAuditNonlinearField begin
    @kinds medium A
    @parameters begin
        Dc = 0.1
        k = 0.5
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @equations D(c) ~ Dc * Δ(c) - k * c^2
    @sweep Metropolis(; temperature = 5.0)
end
@potts_model GdAuditBoundedField begin
    @kinds medium A
    @parameters begin
        Dc = 1.0
        δ[kind] = [5.0, 0.0]
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @equations D(c) ~ Dc * Δ(c) - δ[kind] * c
    @sweep Metropolis(; temperature = 5.0)
end
@potts_model GdAuditKindDiffusion begin             # test/audit.jl:272–280, `δ[kind] Δ(c)`
    @kinds medium A
    @parameters δ[kind] = [0.1, 0.2]
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @equations D(c) ~ δ[kind] * Δ(c)
    @sweep Metropolis(; temperature = 5.0)
end
@potts_model GdAuditInvTable begin
    @kinds medium A
    @parameters begin
        Dc = 0.1
        τ[kind] = [2.0, 0.5]
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @equations D(c) ~ Dc * Δ(c) - (1 / τ[kind]) * c
    @sweep Metropolis(; temperature = 5.0)
end
@potts_model GdAuditIntDivField begin
    @kinds medium A
    @parameters begin
        Dc = 0.25
        k₀ = 7.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16,))
    @energy cells => (volume - 4.0)^2
    @equations D(c) ~ Dc * Δ(c) - (k₀ ÷ 2) * c
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model GdAuditCrossField begin
    @kinds medium A
    @parameters begin
        Dc = 0.5
        Dx = 0.5
    end
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @equations begin
        D(c) ~ Dc * Δ(c) - Dx * Δ(u)
        D(u) ~ Dc * Δ(u)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model GdAuditCrossLinear begin
    @kinds medium A
    @parameters begin
        Dc = 0.5
        Dx = 0.5
    end
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @equations begin
        D(c) ~ Dc * Δ(c) - Dx * u
        D(u) ~ Dc * Δ(u)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model GdAuditGateRotation begin             # test/audit.jl:424–440, reads `mcs`
    @kinds medium A
    @parameters begin
        t0 = 1000.0
        k = 4.0
    end
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @equations begin
        D(c) ~ ifelse(mcs >= t0, -10 * c, -k * u)
        D(u) ~ ifelse(mcs >= t0, -10 * u, k * c)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model GdAuditGateDominant begin             # test/audit.jl:442–456, reads `mcs`
    @kinds medium A
    @parameters t0 = 1000.0
    @variables begin
        c(field) = 0.0
        u(field) = 0.0
    end
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @equations begin
        D(c) ~ ifelse(mcs >= t0, -10 * c - u, -10 * c + u)
        D(u) ~ ifelse(mcs >= t0, -10 * u, -5 * u)
    end
    @sweep Metropolis(; temperature = 1.0)
end
# p6_5c `P65cbAny` (Fixture P's shape, the any-neighbor predicate source)
@potts_model GdP65cbAny begin
    @kinds medium substrate[frozen] lam
    @parameters begin
        D_F = 0.0
        k_d = 0.5
        k_s = 0.5
        mobile = 0.0
    end
    @lattice Lattice((6, 6, 4); boundary = (Periodic(), Periodic(), Closed()), neighborhood = VonNeumann(1))
    touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0
    @energy cells(lam) => (volume - 8.0)^2
    @constraint mobile > 0.5
    @variables F(field) = 0.0
    @equations D(F) ~ D_F * Δ(F) - k_d * F + k_s * (kind == lam) * any(kind[n] == substrate for n in VonNeumann(1)(site))
    @sweep Metropolis(; temperature = 1.0)
end
gd_p65cb_op() = (σ = zeros(Int32, 6, 6, 4); σ[:, :, 1] .= 1; σ[2:3, 2:3, 2:3] .= 2;
                 [ownership => σ, kind => [:substrate, :lam]])

# ---------------------------------------------------------------------------------------
# Records

# FNV-1a over bytes: a digest independent of Julia's `hash` (which samples large arrays)
function gd_fnv(bytes)
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ b) * 0x00000100000001b3
    end
    return string(h; base = 16, pad = 16)
end
gd_digest(a) = gd_fnv(reinterpret(UInt8, vec(htol.(Array(a)))))
gd_text(s::AbstractString) = gd_fnv(codeunits(s))

gd_programs(sys, T, kw) = [e for e in generated_code(sys; T, kw...).phases if e isa Expr && e.head === :field_program]
# `n` of every field group of an integrator (the run-context entries `__fields1`, `__fields2`, …)
function gd_ns(integ)
    ns, j = Int[], 1
    while Symbol(:__fields, j) in propertynames(integ.ctx)
        push!(ns, CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n)
        j += 1
    end
    return ns
end
# solver keywords only (`generated_code` takes no `seed`)
gd_solverkw(kw) = (; (k => v for (k, v) in pairs(kw) if k in (:field_solver, :ode_solver, :solvers))...)

# the fingerprint records of one problem build: `pre` is "label|T"
function gd_fingerprints!(out, pre, sys, prob, T, kw)
    out["$pre|canonical"] = prob.f.sys.solvers.canonical
    out["$pre|fingerprint"] = repr(prob.f.fingerprint)
    progs = gd_programs(sys, T, gd_solverkw(kw))
    out["$pre|groups"] = string(length(progs))
    for (j, e) in enumerate(progs)
        fp, arrays, params, tables, least, flag = e.args
        out["$pre|g$j|fingerprint_text"] = gd_text(fp)
        out["$pre|g$j|arrays"] = arrays
        out["$pre|g$j|params"] = params
        out["$pre|g$j|tables"] = tables
        out["$pre|g$j|least"] = string(least)
        out["$pre|g$j|bounded"] = flag
    end
    return out
end

const GD_MERKS_OP = [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]]
# a one-site frozen border (cell 1) and two endothelial cells
function gd_op2006()
    σ = zeros(Int32, 16, 16)
    σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
    σ[4:7, 4:7] .= 2; σ[10:13, 9:12] .= 3
    return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
end
# a two-site frozen border and two endothelial cells
function gd_op2008()
    σ = zeros(Int32, 20, 20)
    σ[1:2, :] .= 1; σ[(end - 1):end, :] .= 1; σ[:, 1:2] .= 1; σ[:, (end - 1):end] .= 1
    σ[5:9, 5:9] .= 2; σ[12:16, 11:16] .= 3
    return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
end

# (label, system, operating point, keywords, pinned)
const GD_HARD = [
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)), GD_MERKS_OP,
        (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), true),
    ("MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true), GD_MERKS_OP,
        (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), true),
    ("Merks2006", () -> Merks2006(; name = :m, lattice = (16, 16)), gd_op2006(),
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    ("Merks2008", () -> Merks2008(; name = :m, lattice = (20, 20)), gd_op2008(),
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    # the `mcs >= t_relax` gate is crossed within the 5 MCS
    ("Merks2008 t_relax = 3", () -> Merks2008(; name = :m, lattice = (20, 20)), [gd_op2008(); :t_relax => 3.0],
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    ("fixture field", () -> P60oField(; name = :fld), GD_OP_FIELD,
        (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), true),
    ("P60gX", () -> P60gX(; name = :bauer), gd_p60g_op(), (; field_solver = ExplicitEuler()), true),
    # two solver groups; `u` reads `c` from its array (test/fields.jl FdTwo)
    ("FdTwo", () -> FdTwo(; name = :t), fd_source_op((12, 10)),
        (; field_solver = ExplicitEuler(substeps = 2), solvers = [:u => ExplicitEuler(substeps = 3)]), false),
]

function gd_hard!(out)
    for (label, build, op, kw, _) in GD_HARD, T in (Float64, Float32)
        pre = "$label|$T"
        sys = build()
        prob = PottsProblem(sys, op, (0, 5); T, seed = 7, kw...)
        gd_fingerprints!(out, pre, sys, prob, T, kw)
        integ = init(prob, SequentialCPM())
        out["$pre|n"] = string(gd_ns(integ))
        foreach(_ -> step!(integ), 1:5)
        st = current_state(integ)
        out["$pre|digest|σ"] = gd_digest(st.σ)
        for k in keys(st.site)
            out["$pre|digest|site.$k"] = gd_digest(getproperty(st.site, k))
        end
    end
    return out
end

const GD_SOFT = [:FdPeriodic, :FdClosed, :FdDefaults, :FdComputedRate, :FdVolumeRead, :FdSource, :FdDecay, :FdMask,
    :FdHex, :FdHalf, :FdDomain, :FdStripe, :FdRand, :FdDomainWord, :FdTab, :FdGate, :FdChemo, :FdChemoInter,
    :FdSourceInter, :FdComputedFace, :FdKindNonlinear, :FdDivK, :GdAuditDiffusion, :GdAuditNonlinearField,
    :GdAuditBoundedField, :GdAuditKindDiffusion, :GdAuditInvTable, :GdAuditIntDivField, :GdAuditCrossField,
    :GdAuditCrossLinear, :GdAuditGateRotation, :GdAuditGateDominant, :GdP65cbAny]

gd_try(f) = try
    (f(), nothing)
catch e
    e isa ArgumentError || rethrow()
    (nothing, e)
end

# the automatic count first; refused, the same model with `substeps = 3` (the route records it)
function gd_soft!(out)
    for name in GD_SOFT
        M = getfield(Main, name)
        sys = M(; name = :g)
        op = name === :GdP65cbAny ? gd_p65cb_op() :
             [ownership => zeros(Int32, Potts._p(sys, :lattice).dims...), kind => Symbol[]]
        pre = "$name|Float64"
        kw = (; field_solver = ExplicitEuler())
        prob, e = gd_try(() -> PottsProblem(sys, op, (0, 2); kw...))
        route = "auto"
        if prob === nothing
            kw = (; field_solver = ExplicitEuler(substeps = 3))
            prob, e2 = gd_try(() -> PottsProblem(sys, op, (0, 2); kw...))
            route = prob === nothing ? "refused" : "explicit"
        end
        out["$pre|route"] = route
        prob === nothing && continue
        gd_fingerprints!(out, pre, sys, prob, Float64, kw)
        out["$pre|n"] = string(gd_ns(init(prob, SequentialCPM())))
    end
    return out
end

# ---------------------------------------------------------------------------------------
# The recorded values (lp/f1 bda31989, Julia 1.12.6, the PC). A listed move updates its entry
# here with the commit and the cause.

include(joinpath(@__DIR__, "fields_identity_records.jl"))

function gd_compare(got, want, keys)
    bad = String[]
    for k in keys
        g = get(got, k, "<missing>")
        # a record with more than one accepted value lists them, with the cause, in the records
        g == get(want, k, "<missing>") || g in get(GD_ALTERNATES, k, String[]) ||
            push!(bad, "$k: recorded $(repr(get(want, k, "<missing>"))), now $(repr(g))")
    end
    return bad
end
gd_hard_model(k) = (l = first(split(k, '|')); only(g for g in GD_HARD if g[1] == l))

@testset "F2 guard: the field pipeline's behavior and fingerprints" begin
    got = gd_soft!(gd_hard!(Dict{String, String}()))
    path = get(ENV, "POTTS_GUARD_RECORD", "")
    isempty(path) || open(path, "w") do io
        for k in sort!(collect(keys(got)))
            println(io, "    ", repr(k), " => ", repr(got[k]), ",")
        end
    end
    # the copies reproduce the frozen pins
    for (k, v) in GD_PINS
        @test got["$k|fingerprint"] == repr(v)
    end
    hk = [k for k in keys(GD_RECORDS) if any(g -> startswith(k, g[1] * "|"), GD_HARD)]
    sk = setdiff(collect(keys(GD_RECORDS)), hk)
    behavior = [k for k in hk if occursin("|n", k) || occursin("|digest|", k)]
    pinned = [k for k in setdiff(hk, behavior) if gd_hard_model(k)[5]]
    unpinned = setdiff(hk, behavior, pinned)
    for (what, ks) in (("behavior (hard)", behavior), ("pinned fingerprints (hard)", pinned),
            ("unpinned fingerprints (listed moves only)", unpinned), ("soft set (listed moves only)", sk))
        bad = gd_compare(got, GD_RECORDS, sort!(ks))
        isempty(bad) || @error "F2 guard: $what moved: $(length(bad)) records"
        foreach(b -> println(stderr, "  GUARD MOVED ($what) ", b), bad)
        @test isempty(bad)
    end
    # no record appears or disappears unlisted
    @test sort!(collect(keys(got))) == sort!(collect(keys(GD_RECORDS)))
end
