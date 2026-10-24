# The operator of an implicit group (F3 design §3.4): the symmetric Helmholtz part `J̃` of each
# row's rate Jacobian, from the linearity table, as a LatticeFields `OperatorSpec`. A row whose
# coefficients are numbers and parameters is numeric (`Coef` sums); a row whose face
# coefficient, multiplier or local coefficient varies by site (coordinates, inputs, tables at
# inputs), or that lives in an irregular domain, gets a `jac:<key>` kernel that writes them per
# site. Built once per group, at its first implicit use (`DeferredOperator`), never for
# explicit groups (S12).

"""
    DeferredOperator

The operator of a group, not built yet: the lowered system that `build_operator` extracts the
`OperatorSpec` from at the group's first implicit use (once: the result is kept). `builds`
counts the builds of this session (a test reads it: an explicit group builds none).
"""
mutable struct DeferredOperator
    cf::Any
    sys::Any
    disc::Any
    built::Any
end
DeferredOperator(cf, sys, disc) = DeferredOperator(cf, sys, disc, nothing)
const OPERATOR_BUILDS = Threads.Atomic{Int}(0)
const _OPERATOR_LOCK = ReentrantLock()

function Problems.build_operator(d::DeferredOperator, spec::Problems.GroupSpec)
    return lock(_OPERATOR_LOCK) do
        d.built === nothing || return d.built
        Threads.atomic_add!(OPERATOR_BUILDS, 1)
        d.built = _build_operator(d.cf, d.sys, d.disc)
    end
end

# a diffusion term `m Op(c)` in parts: the multiplier `m` (the operator replaced by 1), the face
# coefficient `K` (1 for `Δ`), the axes it acts on (every axis for `Δ` and `DivKGrad`, its own
# for a raw `Dx(K Dx(c))`) and the face mean; `nothing` for more than one operator
function _diffusion_parts(term, xs)
    reps, parts = Dict{Any, Any}(), Any[]
    walk(y) = iscall(y) && (f = operation(y);
                            f === Δ ? (reps[y] = 1; push!(parts, (1, :all, :harmonic))) :
                            f isa DivKGrad ? (reps[y] = 1; push!(parts, (arguments(y)[1], :all, f.mean))) :
                            f isa Differential ? (r = _raw_flux(y); reps[y] = 1;
                                                  push!(parts, (r === nothing || r[1] === nothing ? 1 : r[1],
                                                      findfirst(v -> isequal(v, unwrap(f.x)), xs), :harmonic))) :
                            foreach(walk, arguments(y)))
    walk(unwrap(term))
    length(parts) == 1 || return nothing
    K, ax, mean = only(parts)
    return (m = substitute(term, reps; fold = Val(false)), K, axes = ax, mean)
end

_freeof(x, ops) = !_reads(x, ops)
# a coefficient as a `Coef` (a number, a parameter, a number times a parameter), or nothing
_coefof(x, params) = (x isa Number ? Coef(Float64(x)) : _coef(x, params; strict = false))

function _build_operator(cf::CompiledField{N}, sys::PDESystem, disc::LatticeDiscretization) where {N}
    s = cf.program
    ivs = unwrap.(sys.ivs)
    xs = ivs[2:end]
    states = Set(_states(s))
    params = Dict{Any, Int}(unwrap(q) => i for (i, q) in enumerate(cf.params))
    dvs = Dict{String, Any}()
    for v in sys.dvs, (op, kk) in cf.keys
        isequal(_opof(v), op) || continue
        u = unwrap(v)
        for (i, k) in enumerate(kk)
            k in states && (dvs[k] = length(kk) == 1 ? u : unwrap(Symbolics.wrap(u)[i]))
        end
    end
    hex = s.hierarchy[1].grid.geometry == HEX
    domain = s.hierarchy[1].grid.domain != 0
    # the coordinates and the inputs: a coefficient that reads them varies by site
    inputops = unique([_opof(v) for v in unwrap.(sys.dvs) if ModelingToolkitBase.isinput(v)])
    siteops = Any[inputops; xs]
    tabs = Set(unwrap(q) for q in _params(sys) if SymbolicUtils.symtype(unwrap(q)) <: AbstractArray)
    bysite(x) = _reads(x, siteops) || _reads(x, collect(tabs)) || any(v -> any(y -> isequal(y, v), xs), Symbolics.get_variables(x))
    rows = Problems.RowOperator[]
    plans = Dict{String, Any}()                 # field rows: what their `jac:` kernel writes
    for k in _states(s)
        haskey(cf.linearity, k) || continue
        c = dvs[k]
        faces = [Coef[] for _ in 1:N]
        jloc = Coef[]
        diff = Any[]                            # (multiplier, K, axes, mean) of the row's diffusion terms
        jterms = Any[]                          # the local coefficients
        inexact = String[]
        scaled = false
        field = domain
        for (term, class) in cf.linearity[k]
            if class in (:Diffusion, :SiteDiffusion)
                p = _diffusion_parts(term, xs)
                if p === nothing || hex
                    push!(inexact, _term_text(string(term)))
                    continue
                end
                class == :SiteDiffusion && (scaled = true)
                push!(diff, p)
            elseif class == :LinearLocal
                push!(jterms, substitute(term, Dict(c => 1); fold = Val(false)))
            elseif class in (:Source, :CrossLinear)
                continue                        # residual only, exact (CrossLinear: solve order)
            else
                push!(inexact, _term_text(string(term)))
            end
        end
        # a scaled row (`m Δ(c)`): one face operator; terms with the same face coefficient
        # combine (`m Δ(c) + D Δ(c)` is `(m + D) Δ(c)`), another face coefficient stays out
        if scaled
            K0, ax0, mean0 = diff[1].K, diff[1].axes, diff[1].mean
            keep = Any[]
            for p in diff
                if isequal(unwrap(p.K), unwrap(K0)) && p.axes == ax0 && p.mean == mean0
                    push!(keep, p)
                else
                    push!(inexact, _term_text(string(p.m * p.K)))
                end
            end
            m = sum(p.m for p in keep)
            diff = Any[(m = m, K = K0, axes = ax0, mean = mean0)]
        end
        for p in diff
            mK = scaled ? nothing : _coefof(unwrap(substitute(p.m * p.K, Dict(); fold = Val(true))), params)
            if !scaled && !bysite(p.m) && !bysite(p.K) && mK !== nothing
                for a in (p.axes === :all ? (1:N) : (p.axes,))
                    push!(faces[a], Coef(mK.value / s.spacing[a]^2, mK.param))
                end
            else
                field = true
            end
        end
        for j in jterms
            cj = bysite(j) ? nothing : _coefof(unwrap(j), params)
            cj === nothing ? (field = true) : push!(jloc, cj)
        end
        field |= scaled
        # a numeric row needs a face on every axis that has neighbors (a raw `Dx(Dx(c))` in 2D
        # has none on `y`): such a row writes its faces per site (zero faces are allowed there)
        hasdiff = !isempty(diff)
        if hasdiff && !field && any(a -> s.hierarchy[1].grid.dims[a] > 1 && isempty(faces[a]), 1:N)
            field = true
        end
        local_only = !hasdiff
        if field
            plans[k] = (; diff, jterms, scaled, local_only)
        end
        push!(rows, Problems.RowOperator(k, faces, jloc, field, scaled, domain, local_only, isempty(inexact), inexact))
    end
    jac = isempty(plans) ? nothing : _jac_program(cf, sys, disc, plans, params, xs)
    return Problems.OperatorSpec{N}(rows, jac)
end

# The operator program: the rate program's fields (no scratch `∂c`, no kernels, no rules) and
# per field row a kernel `jac:<key>` that writes its site values (F3 design §3.4): the faces
# `jac:<key>.w<a>` (to `+e_a`, `K_f/h_a²`, 0 across the edge of an irregular domain; a
# boundary face of the box is not a face of the solver), the local Jacobian `.j`, the boundary
# diagonal `.d` of the face conditions (`w_b d⁺`, `w_b` the boundary face `K(i)/h²` and `d⁺`
# the positive part of the ghost rule, `Solvers.robin_parts`: Dirichlet 2), with `scaled` the
# multiplier `.m`, and with a domain its indicator `.dom`
function _jac_program(cf::CompiledField{N}, sys::PDESystem, disc::LatticeDiscretization, plans, params, xs) where {N}
    s = cf.program
    pb = ProgramBuilder(s.hierarchy[1].grid; periodic = s.periodic, spacing = s.spacing, nparams = s.nparams)
    pb.hierarchy = copy(s.hierarchy)
    for f in s.fields
        startswith(f.key, "∂") && continue
        push!(pb.fields, f)
    end
    append!(pb.tables, s.tables)
    append!(pb.masks, [MaskDecl(m.key, fieldid_in(pb, s.fields[m.field].key), m.epoch) for m in s.masks
                       if !startswith(s.fields[m.field].key, "∂")])
    # the lowering's environment over these fields
    fids = Dict{Any, Tuple{Vector{Int32}, Scalar}}()
    for (op, ks) in cf.keys
        all(k -> any(f -> f.key == k, pb.fields), ks) || continue
        ids = Int32[fieldid_in(pb, k) for k in ks]
        fids[op] = (ids, pb.fields[ids[1]].storage)
    end
    tables = Dict{Any, Tuple{Int32, Scalar}}()
    for q in _params(sys)
        u = unwrap(q)
        SymbolicUtils.symtype(u) <: AbstractArray || continue
        i = findfirst(t -> t.key == string(u), pb.tables)
        i === nothing || (tables[u] = (Int32(i), pb.tables[i].storage))
    end
    spacing = Dict{Any, Int}(p => get_lattice_spacing(p) for p in keys(params) if !(SymbolicUtils.symtype(p) <: AbstractArray) &&
                                                                    get_lattice_spacing(p) !== nothing)
    ends = map(xs) do v
        kk = findfirst(d -> isequal(unwrap(d.variables), v), sys.domain)
        Float64(leftendpoint(sys.domain[kk].domain))
    end
    lo = ntuple(d -> ends[d], N)
    h = s.spacing
    domid = s.hierarchy[1].grid.domain == 0 ? Int32(0) : fieldid_in(pb, s.fields[s.masks[s.hierarchy[1].grid.domain].field].key)
    env(kb) = Env(kb, fids, params, tables, spacing, unwrap(sys.ivs[1]), xs, lo, h, false, ntuple(_ -> 0, N), RESOLVE, nothing,
        false, domid)
    for (k, pl) in sort!(collect(plans); by = first)
        id = fieldid_in(pb, k)
        lane = pb.fields[id].storage
        out(name; storage = lane) = field!(pb, "jac:$k.$name"; storage, role = :aux)
        wids = pl.local_only ? Int32[] : Int32[out("w$a") for a in 1:N]
        jid = isempty(pl.jterms) ? Int32(0) : out("j")
        did = pl.local_only ? Int32(0) : out("d")
        mid = pl.scaled ? out("m") : Int32(0)
        dmid = domid == 0 ? Int32(0) : out("dom"; storage = U8)
        kb = kernel(pb)
        e = env(kb)
        zero_ = constant!(kb, 0.0)
        indom(o) = domid == 0 ? nothing : _indomain(kb, domid, N, o)
        inside(o) = node!(kb, INSIDE_OP, BOOL, Int32[], access!(kb, Access{N}(id, Int8(0), Sel(Int16(1)),
            Sel(NTuple{N, Int16}(o)), Int8(0), INSIDE)))
        if !pl.local_only
            p = pl.scaled ? only(pl.diff) : nothing     # (a scaled row: the combined term)
            dsum = zero_
            for a in 1:N
                o = _unit(e, a, 1)
                w = zero_
                wb = (zero_, zero_)             # the boundary faces' K(i)/h², low and high
                for q in pl.diff
                    (q.axes === :all || q.axes == a) || continue
                    mult = pl.scaled ? constant!(kb, 1.0) : _real(e, lower(q.m, e))
                    one_ = q.K isa Number && q.K == 1
                    Kc = one_ ? constant!(kb, 1.0) : _real(e, lower(q.K, e))
                    # the face to offset `oo` as the rate's lowering forms it (`_secdiff`: the
                    # coefficient at the neighbor, a ghost site at a face of the box)
                    function facecoef(oo)
                        Kn = one_ ? constant!(kb, 1.0) : _real(e, lower(q.K, _shift(e, oo)))
                        sum_ = _op(e, ADD, Kc, Kn)
                        face = q.mean === :arithmetic ? _op(e, MUL, constant!(kb, 0.5), sum_) :
                               select!(kb, _cmp(e, EQ, sum_, constant!(kb, 0.0)), constant!(kb, 0.0),
                                   _op(e, DIV, _op(e, MUL, constant!(kb, 2.0), Kc, Kn), sum_))
                        return _op(e, MUL, constant!(kb, 1 / h[a]^2), mult, face)
                    end
                    w = _op(e, ADD, w, facecoef(o))
                    wb = (_op(e, ADD, wb[1], facecoef(_unit(e, a, -1))), _op(e, ADD, wb[2], facecoef(o)))
                end
                # no face across the box (the solver's zero flux) or across the domain's edge
                s.periodic[a] || (w = select!(kb, inside(o), w, zero_))
                domid == 0 || (w = select!(kb, node!(kb, AND, BOOL, Int32[indom(ntuple(_ -> 0, N)), indom(o)]), w, zero_))
                store!(kb, wids[a], lane, w)
                s.periodic[a] && continue
                # the face conditions of the box: the ghost rule's diagonal `w_b d⁺`
                for (j, side) in enumerate((-1, 1))
                    r = findfirst(x -> x isa FaceRule && x.field == fieldid(s, k) && x.axis == a && x.side == side, s.rules)
                    r === nothing && continue
                    fr = s.rules[r]
                    (fr.alpha.param == 0 && fr.alpha.value == 0) && continue
                    α = _coefnode(kb, fr.alpha)
                    β = _coefnode(kb, fr.beta)
                    dd = _op(e, DIV, α, _op(e, ADD, _op(e, MUL, constant!(kb, 0.5), α), β))
                    dd = _op(e, MAX, dd, zero_)
                    term = select!(kb, inside(_unit(e, a, side)), zero_, _op(e, MUL, wb[j], dd))
                    dsum = _op(e, ADD, dsum, term)
                end
            end
            store!(kb, did, lane, dsum)
            pl.scaled && store!(kb, mid, lane, _real(e, lower(p.m, e)))
        end
        if jid != 0
            jv = zero_
            for j in pl.jterms
                jv = _op(e, ADD, jv, _real(e, lower(j, e)))
            end
            store!(kb, jid, lane, jv)
        end
        dmid == 0 || store!(kb, dmid, U8, cast!(kb, indom(ntuple(_ -> 0, N)), U8))
        add!(pb, kb, "jac:$k")
    end
    return program(pb)
end
fieldid_in(pb::ProgramBuilder, key) = Int32(findfirst(f -> f.key == key, pb.fields))
_coefnode(kb, c::Coef) = c.param == 0 ? constant!(kb, c.value) :
                         arith!(kb, MUL, constant!(kb, c.value), cast!(kb, param!(kb, c.param), REAL))
