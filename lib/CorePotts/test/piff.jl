@testset "PIFF import/export" begin
    piff = """
    # a CompuCell3D-style file
    0 Medium 0 9 0 9 0 0
    7 Condensing 1 3 1 2 0 0
    7 Condensing 4 4 1 1 0 0
    12 NonCondensing 6 8 6 8 0 0
    """
    σ, kinds, ids = read_piff(IOBuffer(piff), (10, 10))        # a medium box listed first is overwritten by cells
    @test kinds == ["Condensing", "NonCondensing"] && ids == [7, 12]
    @test count(==(1), σ) == 7 && count(==(2), σ) == 9 && σ[2, 2] == 1 && σ[5, 2] == 1 && σ[7, 7] == 2
    io = IOBuffer(); write_piff(io, σ, kinds; ids)
    σ2, k2, i2 = read_piff(IOBuffer(String(take!(io))), (10, 10))
    @test σ2 == σ && k2 == kinds && i2 == ids
    io = IOBuffer(); write_piff(io, σ, kinds; medium = "Medium")
    σ3, _, _ = read_piff(IOBuffer(String(take!(io))), (10, 10))
    @test σ3 == σ
    # 3D round trip
    σ3d = zeros(Int32, 5, 4, 3); σ3d[2:3, 2:3, 1:2] .= 1; σ3d[5, 4, 3] = 2
    io = IOBuffer(); write_piff(io, σ3d, [:a, :b])
    @test first(read_piff(IOBuffer(String(take!(io))), (5, 4, 3))) == σ3d
    # errors
    @test_throws ArgumentError read_piff(IOBuffer("1 A 0 10 0 0 0 0"), (10, 10))           # outside
    @test_throws ArgumentError read_piff(IOBuffer("1 A 0 1 0 0 0 0\n2 B 1 2 0 0 0 0"), (10, 10))   # overlap
    @test_throws ArgumentError read_piff(IOBuffer("1 A 0 1 0 0 0 0\n1 B 3 4 0 0 0 0"), (10, 10))   # two types
    @test_throws ArgumentError read_piff(IOBuffer("1 A 0 1 0 0 0 1"), (10, 10))           # z in 2D
    @test_throws ArgumentError read_piff(IOBuffer("1 A 0 1"), (10, 10))
    @test_throws ArgumentError read_piff(IOBuffer("1 A 0 1 0 0 0 0\n0 Medium 0 3 0 0 0 0"), (10, 10))  # medium over a cell
    # a file on disk
    path = tempname()
    write_piff(path, σ, kinds; ids)
    @test first(read_piff(path, (10, 10))) == σ
end
