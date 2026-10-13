# Checks the status page's counting rules (render.jl). Light: reads the committed records only.
#
#     julia --startup-file=no docs/status/test_render.jl
using Test: @test, @testset
include(joinpath(@__DIR__, "render.jl"))

row(; kw...) = Dict{String, String}(string(k) => v for (k, v) in kw)

@testset "status page: control convention (P6.0cb)" begin
    rows = [
        row(id = "V1", result = "PASS", required = ""),                       # ordinary check
        row(id = "V2", result = "FAIL", required = ""),
        row(id = "k", kind = "info", result = "PASS", required = ""),         # 04 info row
        row(id = "C1", result = "PASS", required = "PASS"),                   # control, own rule
        row(id = "C2", result = "FAIL", required = "PASS"),                   # control, not as required
        row(row = "NC1", check = "x", result = "FAIL", required = "FAIL"),    # control, model's band
        # legacy encodings (records without the column, data/15)
        row(target = "NC2 V1 rule", band = "≤ 1 (control: must FAIL)", result = "FAIL"),
        row(target = "V4.1 f", case = "control", band = "[0, 1]", result = "PASS"),
        row(target = "V4 negative control fails", case = "control", result = "PASS"),
        row(target = "Controls fail as pre-registered", case = "control, b", result = "PASS"),
        row(target = "V4 (all rows)", case = "b", result = "FAIL"),           # summary
    ]
    c = _count(rows, rows)
    @test (c["PASS"], c["FAIL"], c["info"]) == (1, 1, 2)
    @test (c["controls"], c["controls_as_required"]) == (6, 5)
    @test _controls(c) == "5 of 6" && _controls(nothing) == "—"

    # the committed records
    rec(nn, name) = only(r for r in _records(nn) if r.name == name)
    c04 = (r = rec("04", "full-2026-10-09"); _count(r.rows, r.rows))
    @test (c04["PASS"], c04["FAIL"], c04["controls"], c04["controls_as_required"]) == (18, 24, 4, 4)
    c01b = (r = rec("01", "full-01b-2026-10-09"); _count(r.rows, r.rows))
    @test (c01b["PASS"], c01b["FAIL"], c01b["controls"], c01b["controls_as_required"]) == (27, 2, 7, 7)
    c01 = (r = rec("01", "full-2026-10-08"); _count(r.rows, r.rows))
    @test (c01["PASS"], c01["FAIL"], c01["controls"]) == (37, 0, 0)
    # every record's required column holds only PASS, FAIL or nothing
    for nn in readdir(STATUS_DATA), r in _records(nn), x in r.rows
        @test get(x, "required", "") in ("", "PASS", "FAIL")
    end
end
