module PairedPerformanceRunner

export paired_worker_command

"""Build a subject-pinned Julia command that always executes the shared harness worker."""
function paired_worker_command(worker::AbstractString, subject_root::AbstractString;
        backend::AbstractString, profile::AbstractString, precision::AbstractString)
    worker_path = abspath(worker)
    project = abspath(joinpath(subject_root, "benchmark"))
    return `$(Base.julia_cmd()) --project=$project --startup-file=no $worker_path --backend=$backend --profile=$profile --precision=$precision`
end

end
