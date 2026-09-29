# Units (M3.1): dimensional analysis of `@potts_model`s whose parameters or variables carry
# `[unit = …]` metadata, on ModelingToolkitBase's DynamicQuantities unit inference. Potts'
# symbolic operations get their unit rules here; `mtkcompile` calls `_check_units`.
module PottsDynamicQuantitiesExt

using DynamicQuantities: DynamicQuantities as DQ
using ModelingToolkitBase: ModelingToolkitBase as MTK, get_unit, VariableUnit, ValidationError
using Potts: Potts, PottsSystem, Split, info
using Symbolics: Symbolics
using SymbolicUtils: SymbolicUtils

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

function _unit(label, x)
    try
        return get_unit(Symbolics.unwrap(x))
    catch err
        msg = err isa ValidationError ? err.message : err isa DQ.DimensionError ?
              ": $(err.x) and $(err.y) are not dimensionally compatible." : nothing
        msg === nothing && rethrow()
        throw(ArgumentError("units: in $label$msg"))
    end
end

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
        _require(label, _unit(label, u.eq.rhs), _unit(label, u.eq.lhs), "the right side")
    end
    for eq in sys.equations
        _unit(Potts._describe(eq), eq.rhs)
    end
    for c in sys.constraints
        c.kind === :expr && _require(Potts._describe(c), _unit(Potts._describe(c), c.expr), UNITLESS, "the condition")
    end
    for d in sys.divisions
        label = Potts._describe(d)
        _require(label, _unit(label, d.when), UNITLESS, "the condition")
        for (x, r) in d.rules
            r isa Split || _require(label, _unit(label, r), _unit(label, x), "the rule for $(info(x).name)")
        end
    end
    for o in sys.observed
        _unit(Potts._describe(o), o.expr)
    end
    return nothing
end

end
