#!/usr/bin/env julia

using Test
using CorePotts
using PottsToolkit

const REPO = normpath(joinpath(@__DIR__, ".."))

length(ARGS) == 2 && ARGS[1] == "--suite" ||
    error("usage: run_phase14_g3c_conformance.jl --suite cpu-static")
ARGS[2] == "cpu-static" ||
    error("G3-C local suite must be cpu-static; real backends use benchmark/phase14_wang_g3c_qualification.jl")

include(joinpath(
    REPO, "integration", "conformance",
    "test_phase14_wang_g3c.jl"))
