# Precompile the models (D-047): every constructor and its `mtkcompile`, and for the published
# models the first `PottsProblem` and sequential MCS in their usual configuration (Akeeb also
# in Float32, sequential and checkerboard), so a session's first construction, problem and
# MCS reuse cached code. The generated code does not depend on the lattice size and RGF ids
# are content hashes, so the small lattices here compile the same functions as any other.
# Developers switch it off with the PrecompileTools preference `precompile_workload = false`.
function _first_mcs(c, op, alg = Potts.SequentialCPM(); kw...)
    prob = Potts.PottsProblem(c, op, (0, 10); kw...)
    Potts.step!(Potts.init(prob, alg; save_start = false))
    return nothing
end

PrecompileTools.@setup_workload begin
    σ = zeros(Int32, 24, 24)
    σ[8:14, 8:14] .= 1
    PrecompileTools.@compile_workload begin
        Potts.mtkcompile(SingleDivisionFixture(; name = :s))
        gg = graner_glazier_state()
        _first_mcs(Potts.mtkcompile(GranerGlazier(; name = :gg)), [ownership => gg[1], kind => gg[2]])
        _first_mcs(Potts.mtkcompile(WortelAct(; name = :w, lattice = (24, 24))), [ownership => σ, kind => [:cell]])
        _first_mcs(Potts.mtkcompile(MerksVasculogenesis(; name = :m, lattice = (24, 24))),
            merks_state(; lattice = (24, 24), n = 2); field_solver = Potts.ExplicitEuler(substeps = 15, lower = 0.0))
        _first_mcs(Potts.mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))),
            openvt_monolayer_state(; lattice = (24, 24)); capacity = 64)
        a = Potts.mtkcompile(AkeebInvasion(; name = :a, lattice = (24, 30)))
        op = akeeb_state(; lattice = (24, 30))
        _first_mcs(a, op; capacity = 1000)
        _first_mcs(a, op; T = Float32, capacity = 1000)
        _first_mcs(a, op, Potts.CheckerboardCPM(); T = Float32, capacity = 1000)
    end
end
