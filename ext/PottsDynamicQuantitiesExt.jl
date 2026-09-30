# Units (M3.1): dimensional analysis of `@potts_model`s whose parameters or variables carry
# `[unit = …]` metadata, on ModelingToolkitBase's DynamicQuantities unit inference. Potts'
# symbolic operations get their unit rules here; `mtkcompile` calls `_check_units`.
module PottsDynamicQuantitiesExt

using DynamicQuantities: DynamicQuantities as DQ
using ModelingToolkitBase: ModelingToolkitBase as MTK, get_unit, VariableUnit, ValidationError
using Potts: Potts, PottsSystem, Split, info
using Symbolics: Symbolics
using SymbolicUtils: SymbolicUtils
using TermInterface: TermInterface

const UNITLESS = DQ.Quantity(1.0)
_isunitless(u) = iszero(DQ.dimension(u))
_same(a, b) = DQ.dimension(a) == DQ.dimension(b)

# unit rules for Potts' symbolic operations
MTK.get_unit(::Union{typeof(Potts.at), typeof(Potts.at2), typeof(Potts.history_lag),
        typeof(Potts.cell_integral), typeof(Potts.Δ)}, args) = get_unit(args[1])
MTK.get_unit(::Union{typeof(Potts.cell_centroid), typeof(Potts.copy_displacement),
        typeof(Potts.random_uniform)}, args) = UNITLESS                    # lattice units
MTK.get_unit(::MTK.Pre, args) = get_unit(args[1])
MTK.get_unit(::typeof(Potts.gather), args) = _fold_unit(args[1], args[3])
MTK.get_unit(::typeof(Potts.population), args) = _fold_unit(args[1], args[2])
function MTK.get_unit(op::Union{typeof(&), typeof(|), typeof(!), typeof(xor)}, args)
    for a in args
        u = get_unit(a)
        _isunitless(u) || throw(ValidationError(", in $op, [$u] is not dimensionless."))
    end
    return UNITLESS
end

function _fold_unit(n, body)
    op = info(n).options.op
    op in (:count, :any, :all) && return UNITLESS
    u = get_unit(body)
    op in (:prod, :geomean_shifted) && !_isunitless(u) &&
        throw(ValidationError(", `$op` of a quantity with units [$u]."))
    return u
end

_hasunit(x) = SymbolicUtils.getmetadata(Symbolics.unwrap(x), VariableUnit, nothing) !== nothing

# A literal zero takes any unit: `ifelse(c, x, 0)`, `max(x, 0)`, `min(0, x)` have x's unit.
_iszeroconst(x) = SymbolicUtils.isconst(x) && iszero(SymbolicUtils.unwrap_const(x))
function _zero_free(x)
    x = Symbolics.unwrap(x)
    x isa SymbolicUtils.BasicSymbolic && SymbolicUtils.iscall(x) || return x
    op = SymbolicUtils.operation(x)
    args = map(_zero_free, SymbolicUtils.arguments(x))
    if op === ifelse && length(args) == 3          # keep the condition (it must be unitless)
        _iszeroconst(args[3]) && (args = [args[1], args[2], args[2]])
        _iszeroconst(args[2]) && (args = [args[1], args[3], args[3]])
    elseif (op === max || op === min) && length(args) == 2
        _iszeroconst(args[2]) && return args[1]
        _iszeroconst(args[1]) && return args[2]
    elseif op in (<, <=, >, >=, ==, !=) && length(args) == 2     # `clock >= 0`
        _iszeroconst(args[2]) && (args = [args[1], args[1]])
        _iszeroconst(args[1]) && (args = [args[2], args[2]])
    end
    return TermInterface.maketerm(typeof(x), op, args, TermInterface.metadata(x))
end

function _unit(label, x)
    try
        return get_unit(_zero_free(x))
    catch err
        msg = err isa ValidationError ? err.message : err isa DQ.DimensionError ?
              ": $(err.q1) and $(err.q2) are not dimensionally compatible." : nothing
        msg === nothing && rethrow()
        throw(ArgumentError("units: in $label$msg"))
    end
end

# a literal zero on the right side takes the unit of the left (`clock => 0.0`)
_literal_zero(x) = (x isa Number && iszero(x)) || _iszeroconst(Symbolics.unwrap(x))

function _require(label, u, want, what)
    _same(u, want) || throw(ArgumentError("units: in $label, $what has units [$u], expected [$want]"))
    return nothing
end

function Potts._check_units(sys::PottsSystem)
    any(_hasunit, sys.parameters) || any(_hasunit, sys.variables) || return nothing
    # H: every energy term, drive and the temperature share one unit
    terms = Any[(Potts._describe(e), e.expr) for e in sys.energies]
    append!(terms, [(Potts._describe(d), d.expr) for d in sys.drives])
    push!(terms, ("@sweep temperature", sys.sweep.temperature))
    first_term = nothing
    for (label, x) in terms
        u = _unit(label, x)
        SymbolicUtils._iszero(Symbolics.unwrap(x)) && continue
        if first_term === nothing
            first_term = (label, u)
        else
            _same(u, first_term[2]) || throw(ArgumentError(
                "units: the terms of H disagree: [$(first_term[2])] in $(first_term[1]), [$u] in $label"))
        end
    end
    for u in sys.updates
        label = Potts._describe(u)
        _literal_zero(u.eq.rhs) || _require(label, _unit(label, u.eq.rhs), _unit(label, u.eq.lhs), "the right side")
    end
    # `D(x) ~ rhs`: the clock is the MCS (`mcs_duration` is a plain number), so a rate has x's
    # units per unit of time in whatever time unit its parameters use: [rhs]/[x] must be
    # dimensionless or a pure inverse time
    for eq in sys.equations
        label = Potts._describe(eq)
        r = _unit(label, eq.rhs)
        _literal_zero(eq.rhs) && continue
        x = SymbolicUtils.arguments(Symbolics.unwrap(eq.lhs))[1]
        q = DQ.dimension(r / _unit(label, x))
        pertime = q.time == -1 && all(f -> f === :time || iszero(getfield(q, f)), fieldnames(typeof(q)))
        (iszero(q) || pertime) ||
            throw(ArgumentError("units: in $label, the rate has units [$r]; expected [$(_unit(label, x))] per unit of time"))
    end
    for c in sys.constraints
        c.kind === :expr && _require(Potts._describe(c), _unit(Potts._describe(c), c.expr), UNITLESS, "the condition")
    end
    for d in sys.divisions
        label = Potts._describe(d)
        _require(label, _unit(label, d.when), UNITLESS, "the condition")
        for (x, r) in d.rules
            r isa Split || _literal_zero(r) || _require(label, _unit(label, r), _unit(label, x), "the rule for $(info(x).name)")
        end
    end
    for o in sys.observed
        _unit(Potts._describe(o), o.expr)
    end
    return nothing
end

end
