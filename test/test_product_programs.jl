@testset "published serial product programs" begin
    project_root = dirname(@__DIR__)
    include(joinpath(project_root, "examples", "wortel_2021_serial.jl"))
    include(joinpath(project_root, "examples", "merks_2006_serial.jl"))
    include(joinpath(project_root, "examples", "openvt_monolayer_serial.jl"))

    wortel = Wortel2021Serial.run_wortel_2021()
    merks = Merks2006Serial.run_merks_2006()
    openvt = OpenVTMonolayerSerial.run_openvt_monolayer()

    @test wortel.solution.retcode == SciMLBase.ReturnCode.Success
    @test last(wortel.solution).mcs == 2
    @test last(wortel.solution)[:occupied_sites] ==
          count(!iszero, last(wortel.solution).ownership)
    @test merks.solution.retcode == SciMLBase.ReturnCode.Success
    @test last(merks.solution).mcs == 2
    @test sum(last(merks.solution)[:concentration]) > 0
    @test openvt.solution.retcode == SciMLBase.ReturnCode.Success
    @test last(openvt.solution).mcs == 2
    @test openvt.relaxation_steps > 0
    @test !isempty(openvt.inhibition)

    wortel_replay = Wortel2021Serial.run_wortel_2021()
    merks_replay = Merks2006Serial.run_merks_2006()
    openvt_replay = OpenVTMonolayerSerial.run_openvt_monolayer()
    @test getfield.(wortel.solution.u, :ownership) ==
          getfield.(wortel_replay.solution.u, :ownership)
    @test getfield.(merks.solution.u, :ownership) ==
          getfield.(merks_replay.solution.u, :ownership)
    @test last(merks.solution)[:concentration] ==
          last(merks_replay.solution)[:concentration]
    @test getfield.(openvt.solution.u, :ownership) ==
          getfield.(openvt_replay.solution.u, :ownership)
    @test openvt.inhibition == openvt_replay.inhibition
end
