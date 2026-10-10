# P6.15m m3 regression: a CallbackSet of two differently typed DiscreteCallbacks (a recorder
# and `openvt_release`) with `saveat` on the host CheckerboardCPM path corrupted the GC heap
# (segfault or "GC error (probable corruption)" in a later `_save!`; CorePotts looped `for cb
# in integ.callbacks` over the heterogeneous tuple). Run alone on Julia 1.12.6 (macOS arm64),
# the unfixed loop crashed within ~40 of these solves every time; the crash depends on the
# heap layout, so inside the full suite this is a smoke test and the deterministic guard is
# CorePotts' "CallbackSet of differently typed callbacks with saveat" testset.
using Potts, PottsModels, Test

@testset "CallbackSet + saveat on host CheckerboardCPM (OpenVT chain)" begin
    prob = PottsProblem(OpenVTChain(; name = :cbgc, lattice = (150, 5), λ = 2.0), openvt_chain(11), (0, 1185); seed = 1)
    alg = CheckerboardCPM(; proposal = Moore(1))
    ok = 0
    for i in 1:100
        snap = Ref((0, 0))
        mark = Potts.DiscreteCallback((u, t, integ) -> t == 100, integ -> (snap[] = (1, 2); nothing);
            save_positions = (false, false))
        sol = solve(remake(prob; seed = 214_200_000 + i), alg; saveat = 0:1185,
            callback = Potts.CorePotts.CallbackSet(mark, openvt_release(100)))
        ok += (length(sol.u) == 1186 && snap[] == (1, 2) && sol.retcode == Potts.CorePotts.SciMLBase.ReturnCode.Success)
    end
    GC.gc(true)
    @test ok == 100
end
