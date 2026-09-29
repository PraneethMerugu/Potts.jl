using MakiePotts

include("allocation_fixture.jl")

measurements = allocation_measurements()
for name in propertynames(measurements)
    println(name, " = ", getproperty(measurements, name), " bytes")
end
