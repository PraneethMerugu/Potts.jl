# `hamiltonian`, `drives` and the `PottsSweepSpec` payload of a compiled model with
# `@components` (D-160, P6.0bm review H1): the compiled system reports the energy as written,
# not the lowered one (coupled parameters substituted, observed quantities expanded).
using Test, Potts
using Potts.ModelingToolkitBase: System, getmetadata, hasmetadata, setmetadata

const _sst = Potts.t
Potts.ModelingToolkitBase.@variables ss_m(_sst) = 0.0 ss_y(_sst)
Potts.ModelingToolkitBase.@parameters ss_τ = 20.0 ss_r = 1.0
@named ss_clock = System([Potts.D(ss_m) ~ ss_r / ss_τ, ss_y ~ 3ss_m], _sst)
struct SsOtherKey end

@potts_model SsCoupled begin
    @kinds medium A
    @parameters begin
        T = 1.0
        μ = 0.5
    end
    @components cells(A) clock = ss_clock
    @equations clock.ss_r ~ volume / 25
    @lattice Lattice((12, 12))
    @energy begin
        cells(A) => 0.5 * clock.ss_r + clock.ss_m + clock.ss_τ + clock.ss_y
        contacts => 1.0
    end
    @drive copy => ifelse(new != 0, μ, 0.0)
    @sweep Metropolis(; temperature = T)
end

@testset "PottsSweepSpec: a compiled model with components reports the energy as written" begin
    sys = SsCoupled(; name = :ss)
    cs = mtkcompile(sys)
    H, Hc = Potts.hamiltonian(sys), Potts.hamiltonian(cs)
    @test isequal(H, Hc)
    @test !isequal(Potts.hamiltonian(cs.sys), H)       # negative control: `.sys` is the lowered model
    @test map(typeof ∘ last, H) == map(typeof ∘ last, Hc)
    @test isequal(Potts.drives(sys), Potts.drives(cs))
    # the payload of the compiled system is the authored one's
    spec, specc = getmetadata(sys, Potts.PottsSweepSpec, nothing), getmetadata(cs, Potts.PottsSweepSpec, nothing)
    @test isequal(spec.hamiltonian, specc.hamiltonian) && isequal(specc.hamiltonian, H)
    @test isequal(spec.drives, specc.drives) && isequal(spec.temperature, specc.temperature)
    @test spec.proposal == specc.proposal
    # the term reads the component's coupled parameter and observed quantity as written
    names = Set(Symbol(v) for v in Potts.Symbolics.get_variables(Potts.Symbolics.unwrap(last(H[1]))))
    @test any(n -> occursin("ss_r", string(n)), names) && any(n -> occursin("ss_y", string(n)), names)
    # a compiled system is read-only; other keys are read from `.sys`
    @test_throws ArgumentError setmetadata(cs, SsOtherKey, 1)
    @test_throws ArgumentError setmetadata(cs, Potts.PottsSweepSpec, spec)
    @test_throws ArgumentError setmetadata(sys, Potts.PottsSweepSpec, spec)
    cs2 = mtkcompile(setmetadata(sys, SsOtherKey, 7))
    @test getmetadata(cs2, SsOtherKey, nothing) == 7 && hasmetadata(cs2, SsOtherKey)
    @test !hasmetadata(cs, SsOtherKey) && hasmetadata(cs, Potts.PottsSweepSpec)
    # derived on read: the key is never stored in the raw metadata
    @test !any(kv -> kv[1] === Potts.PottsSweepSpec, getfield(sys, :metadata))
end

# `updates` (D-164, P6.0bp review H1): a contact fold prints as the fold it stands for,
# `count_contacts(contact_partner, pred, relation)`, never as its tracker's internal name
# (`contacts_<relation>_<hash>`), on the plain and the compiled form alike.
using PottsModels: OpenVTReferenceMonolayer

function ss_names(e)
    SU = Potts.SymbolicUtils
    out = Set{Symbol}()
    walk(y) = (y = Potts.Symbolics.unwrap(y);
               y isa SU.BasicSymbolic || return;
               if SU.issym(y)
                   push!(out, Potts.SymbolicIndexingInterface.getname(y))
               elseif SU.iscall(y)
                   op = SU.operation(y)
                   op isa SU.BasicSymbolic && SU.issym(op) ? push!(out, Potts.SymbolicIndexingInterface.getname(op)) :
                   foreach(walk, SU.arguments(y))
               end)
    walk(e)
    return out
end
ss_eq_names(eq) = union(ss_names(eq.lhs), ss_names(eq.rhs))

@testset "updates: contact folds print as count_contacts, not as tracker names" begin
    M = Potts.ModelingToolkitBase
    sys = OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24))
    U = Potts.updates(sys)
    declared = Set{Symbol}(Potts.SymbolicIndexingInterface.getname(x) for x in [M.parameters(sys); M.unknowns(sys)])
    allowed = union(declared, Set(Potts.BUILTIN_NAMES), Set([:kind′, :contact_partner]))
    for u in U
        @test isempty(setdiff(ss_eq_names(u.eq), allowed))
        @test !any(n -> startswith(string(n), "contacts_"), ss_eq_names(u.eq))
    end
    # the fold update reads `count_contacts` (the cell's contacts, all and with the medium)
    f = only(filter(u -> :f in ss_names(u.eq.lhs), U))
    @test occursin("count_contacts(contact_partner, true, contact)", string(f.eq.rhs))
    @test occursin("count_contacts(contact_partner, kind′ == 0, contact)", string(f.eq.rhs))
    # isequal-stable across the plain, completed and compiled forms
    for V in (Potts.updates(complete(sys)), Potts.updates(mtkcompile(sys)), Potts.updates(sys))
        @test length(V) == length(U) && all(i -> isequal(V[i].eq, U[i].eq), eachindex(U, V))
    end
    # negative control: the stored statements still name the trackers, which this check catches
    raw = [u.eq for u in getfield(sys, :updates)]
    @test any(eq -> any(n -> startswith(string(n), "contacts_"), ss_eq_names(eq)), raw)
    @test any(eq -> !isempty(setdiff(ss_eq_names(eq), allowed)), raw)
end
