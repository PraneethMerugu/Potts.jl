function test_parallel_algorithm_report_contract(first_run, second_run)
    first_report = current_mcs_report(first_run)
    second_report = current_mcs_report(second_run)
    @test first_report == second_report
    @test first_report.realized_proposals ==
          first_report.dynamic_conflicts + first_report.constraint_rejections +
          first_report.acceptance_rejections + first_report.accepted_copies
    @test first_report.activated_attempts ==
          first_report.same_owner_no_ops + first_report.boundary_no_ops +
          first_report.immutable_recipient_no_ops + first_report.dynamic_conflicts +
          first_report.constraint_rejections + first_report.acceptance_rejections +
          first_report.accepted_copies
    return (; first_report, second_report)
end

function test_parallel_algorithm_replay_contract(
        first_run,
        second_run,
        first_state,
        second_state,
        tracker)
    first_snapshot = logical_state(first_run)
    second_snapshot = logical_state(second_run)
    @test lattice_storage(first_snapshot) == lattice_storage(second_snapshot)
    @test isempty(tracker_conformance_errors(
        first_state, tracker, first_snapshot))
    @test isempty(tracker_conformance_errors(
        second_state, tracker, second_snapshot))
    return nothing
end
