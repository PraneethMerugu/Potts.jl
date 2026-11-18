"""
    LatticePDE

The MTK-facing vocabulary of the lattice field compiler: the registered operators that
field equations and CPM terms are written with, the metadata keys that tag variables and
parameters, and the scans that refuse spellings MTK accepts but that do not mean what they
say on a lattice (v3 §5.1, §5.5).

Every operator is a positional registered term (S-3): options that are not symbolic live
in a callable struct (`DivKGrad(:harmonic)`, `Advect(Upwind1())`), and every symbolic
argument is positional, so `substitute`, `simplify` and `get_variables` see it.

The discretizer (`LatticeDiscretization`, `symbolic_discretize`) puts a `PDESystem` on a
lattice: it parses the boundary conditions, classifies rate terms in the linearity table,
reads maps and offset reads, and lowers every equation to a LatticeFields `Program`.
`discretize` returns one SciML problem (an `ODEProblem` of rates, a `DiscreteProblem` of
maps), which the field algorithms and OrdinaryDiffEq's solvers both take; the steppers and
`solve` are re-exported, so a standalone model needs only `using
ModelingToolkitBase, LatticePDE`.
"""
module LatticePDE

using DomainSets: Interval, leftendpoint, rightendpoint
using LatticeFields.IR: F16, Grid, Program, ProgramBuilder, Coef, FaceRule, NodeValueRule, MaskDecl,
                        Access, Sel, Scalar, Bpolicy, Ex, field!, rule!, kernel, add!, program,
                        node!, constant!, param!, runtime!, coord!, table!, call!, cast!, arith!,
                        compare!, select!, cond!, load!, access!, store!, isfloat, CALLS,
                        F32, F64, I32, U8, U32, REAL, BOOL, RESOLVE, CLAMP, INSIDE, ZERO, PERSIGMA,
                        ADD, MUL, NEG, DIV, MIN, MAX, ABS, SQRT, EXP, LOG, POWI, EQ, LT, LE,
                        NOT, AND, OR, INSIDE_OP, HEX, DomainEdgeRule, Level, STATIC, RESTRICT, Space, FULL
using CommonSolve: solve, init, step!, solve!
using KernelAbstractions: KernelAbstractions
using LatticeFields: Exec, Problems
using LatticeFields.Solvers: LatticePCG, LatticeGMRES, LatticeMultigrid, LatticeBlockSolve, VCycle
using LatticeFields.Compile: CompileOptions, fingerprint_text, fuse_update, promote_dual, primal
using LatticeFields.IR: fieldid, RESOLVE, degenerate, leveldims, sitecoefs
using LatticeFields.Problems: FieldProblem, FieldSlot, LatticeIndex,
                              ExplicitEuler, ExplicitMap, BackwardEuler, CrankNicolson, BDF2, QuasiSteady, FieldGroups, RT_DT,
    substep_counts, steady_fields, field_series, field_jacobian_sparsity,
                              field_report
using ModelingToolkitBase: ModelingToolkitBase, PDESystem, Pre, ShiftIndex, Shift, Hold, Sample
using SciMLBase: AbstractDiscretization, NullParameters, remake
using SymbolicIndexingInterface: getp, getu, setp, parameter_index
import SciMLBase: discretize, symbolic_discretize
using Symbolics: Symbolics, Differential, Equation, Num, VarDomainPairing, @register_symbolic,
                 unwrap, substitute
using SymbolicUtils: SymbolicUtils, arguments, iscall, operation, unwrap_const
using SymbolicUtils.Code: toexpr
using TermInterface: TermInterface

public Δ, pdesystem, pdesystem_refusal, is_crossgrid_key, operand_reads, LatticeCutField, euler_update, bound_parts, StabilityBound, lower_group, DeferredBound, DeferredOperator, OPERATOR_BUILDS, resolve_bound, lowers_call, check_one_kind, velocity_terms, as_written,
    derivation, VCycle, steady_rows, steady_form, steady_choice, steady_sign
export laplacian, DivKGrad, Advect, AbstractAdvectionScheme, Upwind1, value_at, ismember, masked, step_index
export LatticePlacement, LatticeStorage, LatticeLevel, Coarse, LatticeSpacing, LatticeInputName
export get_lattice_placement, get_lattice_storage, get_lattice_level, get_lattice_spacing,
    get_lattice_input_name
export vocabulary_issues, check_vocabulary
export LatticeDiscretization, FiniteVolume, CompiledField, discretize, symbolic_discretize,
       parse_bcs, linearity, Grid, HEX, Interval, lattice_domain
export ExplicitEuler, ExplicitMap, BackwardEuler, CrankNicolson, BDF2, QuasiSteady, FieldGroups, solve, init, step!, solve!, stability_bound,
       substep_counts, steady_fields, field_series, field_report
export LatticePCG, LatticeGMRES, LatticeMultigrid   # the linear solvers (LinearSolve algorithms; `linsolve = …`); `VCycle` is public
export LatticeBlockSolve                          # coupled block preconditioner (LinearSolve `precs` function)
export field_jacobian_sparsity              # the Jacobian's pattern
export remake, getp, getu, setp            # the routes its messages give (SciMLBase, SymbolicIndexingInterface)

# ---------------------------------------------------------------------------------------
# Field operators: opaque terms, lowered by the discretizer and never evaluated here

"""
    laplacian(c)

The lattice Laplacian of field `c` (zero flux at closed boundaries). In the finite-volume
lowering it is `DivKGrad` with `K ≡ 1`. `Δ` is the same function, for equations written in
mathematical notation (public, not exported).
"""
function laplacian end
laplacian(x) = error("`laplacian` is symbolic-only: apply it inside a `PDESystem` equation and discretize with `LatticePDE.discretize`")
@register_symbolic laplacian(x)
"""
    Δ

The same function as [`laplacian`](@ref): `Δ(c) === laplacian(c)`.
"""
const Δ = laplacian

const FACE_MEANS = (:harmonic, :arithmetic)

"""
    DivKGrad(mean)

`DivKGrad(mean)(K, c)` is the conservative diffusion term `∇⋅(K ∇c)`. `mean` sets the
face value of `K`: `:harmonic` or `:arithmetic`. `K` and `c` are positional symbolic
arguments; the face mean is an option of the operator, kept through `substitute` and
`simplify` because it is part of the term's operation.
"""
struct DivKGrad
    mean::Symbol
    function DivKGrad(mean::Symbol)
        mean in FACE_MEANS || throw(ArgumentError("DivKGrad: the face mean must be one of " *
                                                  "$(join(repr.(FACE_MEANS), ", ")); got $(repr(mean))"))
        return new(mean)
    end
end
(op::DivKGrad)(K, c) = error("`DivKGrad($(repr(op.mean)))` is symbolic-only: apply it inside a `PDESystem` equation and discretize with `LatticePDE.discretize`")
@register_symbolic (op::DivKGrad)(K, c)

"""Discretization scheme of an [`Advect`](@ref) term."""
abstract type AbstractAdvectionScheme end
"""`Upwind1()`: first-order upwind advection."""
struct Upwind1 <: AbstractAdvectionScheme end

"""
    Advect(scheme)

`Advect(scheme)(u, c)` is the advection term of field `c` by velocity `u` (a velocity
component, or the velocity array). `scheme` is an [`AbstractAdvectionScheme`](@ref).
"""
struct Advect{S <: AbstractAdvectionScheme}
    scheme::S
end
(op::Advect)(u, c) = error("`Advect` is symbolic-only: apply it inside a `PDESystem` equation and discretize with `LatticePDE.discretize`")
# One registration for a velocity component and the velocity array: SymbolicUtils 4 gives
# scalar and array symbolics one `BasicSymbolic` type, so two registrations (`u` and
# `u::AbstractVector`) define the same methods twice, an error under precompilation.
@register_symbolic (op::Advect)(u::Union{Real, AbstractVector}, c)

# ---------------------------------------------------------------------------------------
# CPM reads and kind sets: these run inside compiled cell ODEs, so the numeric methods
# evaluate (a kind arrives as a Real after `mtkcompile(; inputs)`)

"""
    value_at(T, k)
    value_at(J, a, b)

`value_at(T, k)`: entry `k` of the kind table `T` (`value_at(Dk, kindₛ)`), or the value of `c` at an
explicit site or cell `s` (`value_at(c, target)`). Never index an array parameter with a symbolic
input (`Dk[kindₛ]`): `mtkcompile(; inputs)` then keeps the input as an unknown.

A table read follows the lattice kernel: index 0 reads 0 (an input value 0 reads no entry),
and any other index is clamped into `1:length(T)` (an index above the table reads its last
entry). The stability bound evaluates a coefficient at every index a read can take: the
interval of the index expression over the declared bounds of its inputs
(`[input = true, bounds = (1, n)]`, which their values are checked against) and, for an
input the host writes (`discretize(…; inputs)`, `remake(prob; inputs)`, `integ[k] = K`),
over its current values. Index 0 is evaluated only when that interval holds 0.

`value_at(J, a, b)`: entry `(a, b)` of the pair table `J` (`value_at(J, kindₛ, kindₛ′)`). It reads
as the two-argument form does along each axis: index 0 in either argument reads 0, and each
index is clamped into its axis (`1:size(J, 1)`, `1:size(J, 2)`).

With two or more integer inputs (for example the two kinds of a pair table read),
`mtkcompile(sys; inputs = [a, b])` can fail with `AssertionError: last_idx <= idx` in
ModelingToolkitBase `complete` (FR-36, MTKBase 1.77): it requires the inputs in its own
parameter order, which is hash order and so depends on the names and the machine. Give the
inputs in the reverse order (`inputs = [b, a]`).
"""
value_at(T::AbstractArray{<:Union{Integer, AbstractFloat}}, k::Union{Integer, AbstractFloat}) =
    k == 0 ? zero(eltype(T)) : T[clamp(Int(k), 1, length(T))]
# One registration for the table and the site forms (see `Advect`). The index is any `Real`
# term: a kind or a cell id may be a `Real`-typed input (a CPM built-in), and an integer
# literal reads that entry (`value_at(Dk, 2)`; `value_at(Dk, 0)` reads 0, as in the kernel).
@register_symbolic value_at(T::Union{Real, AbstractVector}, k::Real)
# literal indices into symbolic tables and site values (the registration covers a symbolic
# index only)
value_at(T::Union{Num, Symbolics.Arr}, k::Union{Integer, AbstractFloat}) = value_at(T, Num(k))

# the pair table form
value_at(T::AbstractArray{<:Union{Integer, AbstractFloat}}, k::Union{Integer, AbstractFloat}, kp::Union{Integer, AbstractFloat}) =
    k == 0 || kp == 0 ? zero(eltype(T)) : T[clamp(Int(k), 1, size(T, 1)), clamp(Int(kp), 1, size(T, 2))]
# (`false`: the first registration's shape rule covers every arity; a second would overwrite
# it, so the result type of this arity is declared here)
@register_symbolic value_at(T::AbstractMatrix, k::Real, kp::Real) false
SymbolicUtils.promote_symtype(::typeof(value_at), ::Type, ::Type, ::Type) = Real
value_at(T::Symbolics.Arr, k::Union{Integer, AbstractFloat}, kp::Union{Integer, AbstractFloat}) = value_at(T, Num(k), Num(kp))

# unit inference (MTK `get_unit`): a read has the unit of what it reads, `laplacian(c)` that of `c`
ModelingToolkitBase.get_unit(::Union{typeof(value_at), typeof(laplacian)}, args) = ModelingToolkitBase.get_unit(args[1])

"""
`ismember(k, s)`: whether the integer `k` (a kind) is one of the tuple `s` of integer
codes. The `∈` forms do not work in a symbolic expression: `kind ∈ Set(…)` evaluates to
`false` before any term exists (a product with it vanishes), `kind ∈ (a, b)` builds an
interval domain pairing and `kind ∈ [a, b]` builds an `in` term that LatticePDE refuses.
"""
ismember(k::Union{Integer, AbstractFloat}, s::Tuple) = Int(k) in s
@register_symbolic ismember(k::Real, s::Tuple)::Bool

"""
`masked(pred, v)`: the masked interior condition `c ~ masked(pred, v)`, written in the
boundary conditions: `c` is held at `v` on the sites where `pred` holds. `pred` is a
symbolic `Bool` term; arrays are written per component, `u[i] ~ masked(pred, v)`.
"""
masked(p, v) = error("`masked(pred, v)` is a symbolic boundary-condition marker; its predicate must be a " *
                     "symbolic Bool term such as `kindₛ == 3` or `ismember(kindₛ, (2, 3))`. A kind set " *
                     "written with `∈` (`kindₛ ∈ (2, 3)`, `kindₛ ∈ Set(…)`) is not a term: use `ismember`.")
@register_symbolic masked(p::Bool, v::Real)

"""
    step_index(t)

The step index of the discretization's clock (`LatticeDiscretization(…; clock = τ)`), read in
an equation of a system discretized with it: `k = 0` over the first period `τ` from the start
of the time span, then `1`, `2`, … (`k` counts from `tspan[1]`, also after a `remake` of the
span; a Potts model's `mcs` is the absolute MCS number instead: a span `(2, 5)` reads 2
first). The owned steppers keep `k` as an integer and never step
across a clock boundary, so `k` does not depend on `dt` or on the save times. A gate such as
`ifelse(step_index(t) >= 3, a, b)` is bounded through both arms; a factor that reads it
(`(1 + ε * step_index(t)) * laplacian(c)`) is a term the stability bound cannot see (give
`ExplicitEuler(; substeps = n)`). Refused without a declared clock. An OrdinaryDiffEq solver
lands on every boundary of the clock (a `tstop` at each, where the step index changes).

```julia
@parameters x y
@variables c(..)
eqs = [D(c(t, x, y)) ~ -c(t, x, y) + 0.1 * step_index(t)]
prob = discretize(sys, LatticeDiscretization(Grid((16, 16)); clock = 1.0))   # `sys`: a PDESystem of `eqs`
sol = solve(prob, ExplicitEuler(); dt = 0.25)       # 4 windows per step index
```
"""
step_index(t::Real) = throw(ArgumentError("`step_index(t)` is the step index of a discretization's clock: it has a " *
                                          "value only in an equation discretized with `LatticeDiscretization(…; clock = τ)`"))
@register_symbolic step_index(t::Real)

# No operator here has a symbolic derivative: the field operators are lowered, never
# expanded, and the CPM reads are piecewise constant in their kind arguments. A derivative
# that reaches one of them is an error, not the unevaluated `D(op(…))` Symbolics returns by
# default. (`expand_derivatives` asks only for arguments whose own derivative is nonzero.)
_no_derivative(op) = throw(ArgumentError("LatticePDE operators are opaque to symbolic differentiation; " *
                                         "`$op` has no derivative rule (differentiate the field before applying " *
                                         "the operator, or keep the derivative outside it)"))
Symbolics.@register_derivative laplacian(x) I _no_derivative(laplacian)
Symbolics.@register_derivative (op::DivKGrad)(K, c) I _no_derivative(op)
Symbolics.@register_derivative (op::Advect)(u, c) I _no_derivative(op)
Symbolics.@register_derivative value_at(T, k) I _no_derivative(value_at)
Symbolics.@register_derivative value_at(T, k, kp) I _no_derivative(value_at)
Symbolics.@register_derivative ismember(k, s) I _no_derivative(ismember)
Symbolics.@register_derivative masked(p, v) I _no_derivative(masked)
Symbolics.@register_derivative step_index(t) I _no_derivative(step_index)

# the registered operators of this vocabulary (the scans check their arguments)
_isvocabulary(f) = f === laplacian || f isa DivKGrad || f isa Advect || f === value_at || f === ismember ||
                   f === masked

# ---------------------------------------------------------------------------------------
# Metadata keys (`@variables c(..) [lattice_placement = …]`). MTK's own `tunable` is reused;
# these are ours, so they carry the `lattice_` prefix.

"""Metadata key `lattice_placement`: where a field's values live on the lattice."""
struct LatticePlacement end
"""Metadata key `lattice_storage`: how a field is stored."""
struct LatticeStorage end
"""Metadata key `lattice_level`: the grid a field lives on, [`Coarse`](@ref)`(k)`."""
struct LatticeLevel end
"""
    Coarse(k)

The grid of a field coarsened by `k` on every axis, `[lattice_level = Coarse(k)]` (`k` a power
of two; `Coarse(1)` is the lattice itself). Each node of the coarse grid is a block of `k` sites
per axis, its value the field over that block, with the spacing `k h`. Every axis of the lattice
must have a size that `k` divides (an axis of size 1 is never coarsened). The field's equation,
its conditions and its solver run on the coarse grid; the fine reads in its terms (the CPM
inputs, a field of the lattice) are folded over each node's block:

  - One rule holds for every fine read: a real, `Bool` or integer (`kind`) input and a field of
    the lattice. The largest part of a term that reads a fine field and is not linear in it is
    replaced by its mean over the block, with the fine reads at each site of the block. A sum
    is folded per term, and the factors of a product that read no fine field stay outside. The
    coarse field then receives the fine integral of the term: `max(g - gT, 0)`, `g / (K + g)`,
    `value_at(S, kind) * g`, `kind == P` and `value_at(R, kind)` are restricted exactly. A condition used as
    a number (in a sum, a product, a coefficient, the right side itself) is a 0/1 value and
    folds by its mean: on a block a quarter of whose sites are of kind P, `kind == P` is 0.25,
    so `(kind == P) + 0.5 (kind == Q)` and `value_at(R, kind)` agree, and `kind == 0` and `kind != 0`
    sum to 1. A spatial operator of the coarse field is not folded; its coefficient is, at
    each face (at a face of the box, the node's own block). A fine coefficient is the
    arithmetic mean of its fine values over the block, not a homogenized coefficient (the
    block's effective conductivity, which the arithmetic mean bounds from above).
  - A mask whose predicate reads fine values (`c ~ masked(kind == medium, v)`) blends (F4-15b).
    A node is masked, and holds `v`, when the predicate holds at every site of its block.
    Elsewhere the node holds the value of its block's free part, the sites where the predicate
    is false: the fine reads in its equation and its operator coefficients fold over the free
    sites, so the free volume times a folded source is the fine sum of that source over the free
    sites. On an irregular domain the fold's support is the free sites inside the domain: an
    out-of-domain site is not where the equation holds, so it never enters a fold. A spatial operator acts on the node values as before: its flux is the operator's,
    not a sum over the free children. The block's mean is `f v + (1 - f) c`, with `f` its
    masked fraction.

A term of a fine
field that reads a coarse one reads the node whose block holds the site. A spatial operator
(`laplacian`, `DivKGrad`, `Advect`, a raw flux `Dx(K * Dx(c))`) acts on its operand's own grid. In a row of
another grid it is an aux field of the operand's grid that LatticePDE adds (named `laplacian(c)`), and the row
reads it as it reads any field of that grid. The Laplacian of a coarse field in a fine row
is the coarse Laplacian at the node of the site's block. The Laplacian of a fine field in a coarse
row is the block mean of the fine Laplacian: the net flux through the faces of the block over its
volume, so the sum over the blocks is the net flux through the faces of the box. A map's offset read of a coarse
field moves by a multiple of `k` sites (`k * dx`). With an irregular `domain`, a node is in it
when most of its block is (the Majority fold), and its edge is the coarse field's zero-flux edge.
"""
struct Coarse
    k::Int
    function Coarse(k::Integer)
        (k >= 1 && ispow2(k)) || throw(ArgumentError(string("Coarse(", k, "): the factor is a power of two (1, 2, 4, 8, …), ",
            "the number of lattice sites per axis in each node of the coarse grid")))
        return new(Int(k))
    end
end
Base.show(io::IO, c::Coarse) = print(io, "Coarse(", c.k, ")")
# the level of a factor: k = 2^level
level_of(c::Coarse) = trailing_zeros(c.k)
"""
Metadata key `lattice_spacing`: marks a parameter as the grid spacing along axis `a`
(`@parameters dx [lattice_spacing = 1]`). The discretization supplies its value from the
grid; the tag, not the name, marks it.
"""
struct LatticeSpacing end
"""
Metadata key `lattice_input_name`: the name a user gives an input field by
(`kind__in(t, x, y)::Int32 [input = true, lattice_input_name = "kind"]`). `discretize(…;
inputs = [:kind => K])` takes it as well as the variable, and messages print it; a front end
that generates its input variables (Potts' `kind__in`) sets it to the user's word.
"""
struct LatticeInputName end
"""
Metadata key `LatticeCutField` (`true`): an input that is the field of another group (front end
A's group system, the cut of `lower_group(…; fields)`) and that a spatial operator of the group
reads. It carries that field's face conditions, so its ghost values are those of its own group
(F3-22 review r1); its masks and initial values stay with its own group.
"""
struct LatticeCutField end

Symbolics.option_to_metadata_type(::Val{:lattice_placement}) = LatticePlacement
Symbolics.option_to_metadata_type(::Val{:lattice_storage}) = LatticeStorage
Symbolics.option_to_metadata_type(::Val{:lattice_level}) = LatticeLevel
Symbolics.option_to_metadata_type(::Val{:lattice_spacing}) = LatticeSpacing
Symbolics.option_to_metadata_type(::Val{:lattice_input_name}) = LatticeInputName

_meta(x, key) = Symbolics.getmetadata(Symbolics.unwrap(x), key, nothing)
"""`get_lattice_placement(x)`: the `lattice_placement` of `x`, or `nothing`."""
get_lattice_placement(x) = _meta(x, LatticePlacement)
"""`get_lattice_storage(x)`: the `lattice_storage` of `x`, or `nothing`."""
get_lattice_storage(x) = _meta(x, LatticeStorage)
"""`get_lattice_level(x)`: the `lattice_level` of `x`, or `nothing`."""
get_lattice_level(x) = _meta(x, LatticeLevel)
"""`get_lattice_spacing(x)`: the axis of the spacing parameter `x`, or `nothing`."""
get_lattice_spacing(x) = _meta(x, LatticeSpacing)
"""`get_lattice_input_name(x)`: the `lattice_input_name` of the input `x` (or of its operation), or `nothing`."""
function get_lattice_input_name(x)
    n = _meta(x, LatticeInputName)
    n === nothing || return String(n)
    u = Symbolics.unwrap(x)
    SymbolicUtils.iscall(u) || return nothing
    n = _meta(SymbolicUtils.operation(u), LatticeInputName)
    return n === nothing ? nothing : String(n)
end

# ---------------------------------------------------------------------------------------
# Scans: spellings MTK builds without complaint that are wrong or meaningless here

const ISMEMBER_HINT = "write a kind set as `ismember(kindₛ, (2, 3))`"
const SHIFT_HINT = "write a discrete map as `Shift(t, 1)(c(t, x, y)) ~ rhs`"

"""
    vocabulary_issues(pdesys::PDESystem)
    vocabulary_issues(eqs, bcs = Equation[])

The refusals of the LatticePDE surface, one message per offending term, empty when the
system is clean. Checked in every equation and boundary condition, on both sides and inside
every operator's arguments:

  - a side or entry that is a `VarDomainPairing` (`kindₛ ∈ (2, 3)` builds an interval);
  - a side that is a literal `Bool` (`kindₛ ∈ Set(…)` evaluates to `false` before a term
    exists);
  - an `in` term (`kindₛ ∈ [2, 3]`), a valid term that is not a kind set here;
  - a `ShiftIndex` argument (`N(k + 1)` on the callable `N(..)` builds a term whose
    argument is the shift index; MTK refuses the same notation on `N(t, x, y)`);
  - a `Pre` term (the callback "previous value", not a map's previous step).

`kindₛ ∈ Set(…)` inside a larger expression cannot be seen: the product `α * false` is
already `0`, so the term is gone from the equation before any scan runs.
"""
vocabulary_issues(sys::PDESystem) = vocabulary_issues(sys.eqs, sys.bcs)
function vocabulary_issues(eqs, bcs = Equation[])
    issues = String[]
    for (where, list) in (("equation", eqs), ("boundary condition", bcs)), (i, e) in enumerate(list)
        _scan_entry!(issues, "$where $i", e)
    end
    return issues
end

"""
    check_vocabulary(pdesys::PDESystem)
    check_vocabulary(eqs, bcs = Equation[])

Throw an `ArgumentError` listing every [`vocabulary_issues`](@ref) entry; return `nothing`
when there are none.
"""
function check_vocabulary(args...)
    issues = vocabulary_issues(args...)
    isempty(issues) || throw(ArgumentError("LatticePDE refuses $(length(issues)) term" *
                                           "$(length(issues) == 1 ? "" : "s"):\n  - " * join(issues, "\n  - ")))
    return nothing
end

function _scan_entry!(issues, where, e)
    if e isa Equation
        _scan_side!(issues, "$where (lhs)", e.lhs)
        _scan_side!(issues, "$where (rhs)", e.rhs)
    else
        _scan_side!(issues, where, e)
    end
    return issues
end

function _scan_side!(issues, where, x)
    x isa AbstractArray && (foreach(y -> _scan_side!(issues, where, y), x); return issues)
    v = unwrap_const(Symbolics.unwrap(x))
    if v isa VarDomainPairing
        push!(issues, "$where: `$(v.variables) ∈ $(v.domain)` is a domain pairing (an interval), " *
                      "not a kind set; $ISMEMBER_HINT")
    elseif v isa Bool
        push!(issues, "$where: the side is the literal `$v`; `kindₛ ∈ Set(…)` evaluates before a term " *
                      "exists; $ISMEMBER_HINT")
    elseif v isa AbstractArray
        foreach(y -> _scan_side!(issues, where, y), v)
    else
        _scan_term!(issues, where, v)
    end
    return issues
end

function _scan_term!(issues, where, u)
    iscall(u) || return issues
    f = operation(u)
    args = arguments(u)
    if f === in
        push!(issues, "$where: `$u` is an `in` term, not a kind set; $ISMEMBER_HINT")
    elseif f isa Pre
        push!(issues, "$where: `$u` uses `Pre`, the callback previous value, which has no meaning " *
                      "in a field system; $SHIFT_HINT")
    end
    if _isvocabulary(f) && any(a -> unwrap_const(a) isa Bool, args)
        push!(issues, "$where: `$u` has a literal `Bool` argument; `kindₛ ∈ Set(…)` evaluates before a " *
                      "term exists; $ISMEMBER_HINT")
    end
    if any(a -> unwrap_const(a) isa ShiftIndex, args)
        push!(issues, "$where: `$u` has a `ShiftIndex` argument (the `c(k + 1)` notation does not " *
                      "apply to space-time variables); $SHIFT_HINT")
    end
    foreach(a -> _scan_term!(issues, where, a), args)
    return issues
end

include("bcs.jl")
include("linearity.jl")
include("lower.jl")
include("discretize.jl")
include("pdesystem.jl")
include("steady.jl")
include("crossgrid.jl")
include("problems.jl")
include("group.jl")
include("operator.jl")
include("derivation.jl")
include("precompile.jl")

# the operator builds of this session: the precompile workload's is in the package image (R2-N1)
__init__() = (OPERATOR_BUILDS[] = 0; nothing)

end # module LatticePDE
