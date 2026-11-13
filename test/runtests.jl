# Run with:  julia --project=. -e 'using Pkg; Pkg.test()'
# (or `julia --project=. test/runtests.jl`, which needs Test from the standard library)
"@stdlib" in LOAD_PATH || push!(LOAD_PATH, "@stdlib")

using MOS_amplifier_configurations, Microelectronics, SchematicSVG, Test

@testset "MOS_amplifier_configurations" begin
    names = circuit_list()
    @test length(names) == 18
    @test issorted(names)
    for n in names
        @test complete_schematic(n) isa Schematic
        @test amplifier_configuration(n) isa Schematic
        @test bias_schematic(n) isa Schematic
    end

    # one full pass, and the sequence starts over afterwards
    set_parameters(seed=7)
    cs = [next_circuit() for _ in 1:18]
    @test sort([c.name for c in cs]) == names
    @test [c.number for c in cs] == 1:18
    @test next_circuit().name == cs[1].name

    # the same seed gives the same assignment
    set_parameters(seed=7)
    again = next_circuit()
    @test again.name == cs[1].name
    @test (again.RD, again.RS, again.ID, again.Vofs) == (cs[1].RD, cs[1].RS, cs[1].ID, cs[1].Vofs)

    for c in cs
        @test c.netlist isa Netlist
        @test occursin(c.name, sprint(show, MIME"text/plain"(), c))
        @test occursin("<svg", sprint(show, MIME"text/html"(), c))
        (; RD, RS, VDD) = c
        @test VDD == 3u"V"
        @test (c.load == "ideal") == (c.ID !== nothing)
        @test (c.config == "sf") == (c.Vofs !== nothing)
    end

    # degenerated source followers: RD small enough for saturation
    # (NMOS: RD/RS ≤ (VDD - VG)/(VG - VSS); PMOS: the mirror image)
    set_parameters(seed=1)
    for _ in 1:5*18
        c = next_circuit()
        c.config == "sf" && c.load == "degen" || continue
        VG = c.Vofs
        bound = c.device == "nmos" ? (c.VDD - VG) / (VG - c.VSS) : (VG - c.VSS) / (c.VDD - VG)
        @test uconvert(NoUnits, c.RD / c.RS) <= bound
    end
end
