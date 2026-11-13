"""
    MOS_amplifier_configurations

A collection of single-transistor MOS amplifier schematics for assignments, examples and
practice problems: NMOS and PMOS; common-source, common-gate and source-follower; with
an ideal current-source load, a passive (resistor) load, or source degeneration. Each one
comes as the bare amplifier, its bias network, and the complete circuit with signal
source and coupling.

    using MOS_amplifier_configurations

    set_parameters(seed=2026)                       # optional: supplies, models, signal, seed
    c = next_circuit()                              # shows its values and schematic
    (; RD, RS, ID, VDD, netlist) = c

`next_circuit` steps through the circuits in a shuffled order (set by `seed`), draws
random component values, and returns an [`AmplifierCircuit`](@ref) holding them with the
annotated schematic and a Microelectronics netlist ready to simulate.
"""
module MOS_amplifier_configurations

using Microelectronics, SchematicSVG, Random

export next_circuit, set_parameters, circuit_list, AmplifierCircuit
export complete_schematic, amplifier_configuration, bias_schematic
export nmos_amplifier_topology, pmos_amplifier_topology

# ───────────────────────── building blocks (ASCII) ─────────────────────────

const PMOS_TOPOLOGY = """
     vdd
      |
      RS
      |
     @source
      |
gate-|P1
      |
     @drain
      |
      RD
      |
     vss
"""

# The NMOS amplifier is the PMOS one upside down: drain resistor on top, source below.
const NMOS_TOPOLOGY = replace(PMOS_TOPOLOGY,
    "RS" => "RD", "RD" => "RS", "P1" => "N1", "source" => "drain", "drain" => "source")

const PMOS_BIAS_TOPOLOGY = """
     vdd
      |
      RS
      |
      |
      |
     P2|-*-bias
      |  |
      *--+
      |
      RD
      |
     vss
"""

const NMOS_BIAS_TOPOLOGY = """
     vdd
      |
      RD
      |
      *--+
      |  |
     N2|-*-bias
      |
      |
      |
      RS
      |
     vss
"""

const TOPOLOGY = Dict("nmos" => NMOS_TOPOLOGY, "pmos" => PMOS_TOPOLOGY)
const BIAS_TOPOLOGY = Dict("nmos" => NMOS_BIAS_TOPOLOGY, "pmos" => PMOS_BIAS_TOPOLOGY)

const BIAS_COUPLING = schem"""
bias-RC-*-in
        |
        CC
        |
        |@sig
       SVsig
        |
       gnd
"""

const AC_COUPLING = schem"""
in-CC-*-out
      |
      RC
      |
     gnd
"""

const SIGNAL_SOURCE = schem"""
 sig
  |
  SVsig
  |
  gnd
"""

const SIGNAL_SOURCE_VSS = schem"""
  in
  |
  SVsig
  |
  vss
"""

const SIGNAL_SOURCE_VDD = schem"""
 vdd
  |
  SVsig
  |
  in
"""

const OFFSET_SIGNAL_SOURCE = schem"""
  in
  |
SVsig
  |
  Vofs
  |
  gnd
"""

# ─────────────────── edits that turn a topology into a variant ───────────────────
# Text replacements on the ASCII drawings, by (load, configuration); NMOS and PMOS use the
# same ones. Replacements keep the columns lined up ("gate" → "  in").

const IDEAL = ("RD" => "ID", "RS" => "|")           # ideal current-source load, no RS
const PASSIVE = ("RS" => "|", "RD" => "RD")          # resistor load, no RS
const CS = ("gate" => "  in", "@drain" => " *-drain")
const CG = ("@drain" => " *-drain",)
const SF = ("@source" => " *-source", "gate" => "  in", "RD" => "|")

const EDITS = Dict(
    ("ideal", "cs") => (IDEAL..., CS...),
    ("ideal", "cg") => (IDEAL..., CG..., "@source" => " |"),
    ("ideal", "sf") => (SF..., "RS" => "ID"),
    ("passive", "cs") => (PASSIVE..., CS..., "@source" => " |"),
    ("passive", "cg") => (PASSIVE..., CG..., "@source" => " |"),
    ("passive", "sf") => SF,
    ("degen", "cs") => CS,
    ("degen", "cg") => CG,
    ("degen", "sf") => ("gate" => "  in", "@source" => " *-source"),
)

const DEVICES = ("nmos", "pmos")
const LOADS = ("ideal", "passive", "degen")
const CONFIGS = ("cs", "cg", "sf")
const XSCALE = 0.6

# ───────────────────────────── the circuits ─────────────────────────────

# The bare amplifier, its bias network, and the complete circuit for one variant.
function build(device, load, config)
    edits = EDITS[(load, config)]
    amp_ascii = replace(TOPOLOGY[device], edits...)
    if config == "cg"                     # the signal enters at the source
        amp_ascii = replace(amp_ascii, (device == "nmos" ? "vss" : "vdd") => " in")
    end
    amp = ascii_schematic(amp_ascii)
    bias = ascii_schematic(replace(BIAS_TOPOLOGY[device], edits...))

    full = if config == "sf"
        layout(OFFSET_SIGNAL_SOURCE, amp, AC_COUPLING;
               connect=[(1, "in") => (2, "in"), (2, "source") => (3, "in")],
               xscale=XSCALE, nodelabels=true)
    elseif config == "cg"
        stage = layout(bias, amp, AC_COUPLING;
                       connect=[(1, "bias") => (2, "gate"), (2, "drain") => (3, "in")],
                       xscale=XSCALE, nodelabels=true)
        # the signal source sits below an NMOS stage (returned to V_SS) and above a PMOS
        # one (returned to V_DD)
        parts = device == "nmos" ? (stage, SIGNAL_SOURCE_VSS) : (SIGNAL_SOURCE_VDD, stage)
        layout(parts...; direction=:column, connect=[(1, "in") => (2, "in")],
               xscale=XSCALE, nodelabels=true)
    else                                  # cs
        layout(bias, BIAS_COUPLING, amp, AC_COUPLING;
               connect=[(1, "bias") => (2, "bias"), (2, "in") => (3, "in"), (3, "drain") => (4, "in")],
               xscale=XSCALE, nodelabels=true)
    end
    amp, bias, full
end

# Built once, when the module is (pre)compiled: name ("nmos_ideal_cs", …) => schematic.
const AMPLIFIERS = Dict{String,Schematic}()
const BIASES = Dict{String,Schematic}()
const SCHEMATICS = Dict{String,Schematic}()
for device in DEVICES, load in LOADS, config in CONFIGS
    name = "$(device)_$(load)_$(config)"
    AMPLIFIERS[name], BIASES[name], SCHEMATICS[name] = build(device, load, config)
end

# ─────────────────────────── settings and state ───────────────────────────

mutable struct Settings
    supplies::Dict{String,Any}
    RC::Any
    CC::Any
    Pmodel::String
    Nmodel::String
    amplitude::Any
    frequency::Any
    rng::Xoshiro
    order::Vector{String}             # circuit names, shuffled
    index::Int                        # position of the last circuit handed out
end

const SETTINGS = Ref{Settings}()

"""
    set_parameters(; VDD=3u"V", VSS=-3u"V", RC=100u"kΩ", CC=1u"μF",
                   Pmodel="ald1105p", Nmodel="ald1105n",
                   seed=1234, amplitude=5u"mV", frequency=1u"kHz")

Sets the supplies, coupling network, transistor models and input signal used by
`next_circuit`, and restarts its sequence: the circuits come in an order shuffled by
`seed`, and the random component values follow from `seed` too, so the same seed gives
the same assignment. Runs with the defaults when the module loads.
"""
function set_parameters(; VDD=3u"V", VSS=-3u"V", RC=100u"kΩ", CC=1u"μF",
                        Pmodel="ald1105p", Nmodel="ald1105n",
                        seed=1234, amplitude=5u"mV", frequency=1u"kHz")
    rng = Xoshiro(seed)
    order = shuffle!(rng, sort!(collect(keys(SCHEMATICS))))
    SETTINGS[] = Settings(Dict("vdd" => VDD, "vss" => VSS), RC, CC, Pmodel, Nmodel,
                          amplitude, frequency, rng, order, 0)
    nothing
end

__init__() = set_parameters()

# ───────────────────────────── assignments ─────────────────────────────

# The table entries for the elements drawn in `schem`, matched by instance name. `layout`
# numbers names used in more than one part (RD_1, RD_3), so the number is ignored.
function matching_elements(schem::Schematic, table)
    elements = Dict{String,Any}()
    for x in schem.items
        x isa Union{Bipole,Transistor} && !isempty(x.name) || continue
        base = replace(x.name, r"_\d+$" => "")
        for key in keys(table)
            string(key) == base && (elements[x.name] = table[key])
        end
    end
    elements
end

const DEVICE_NAMES = Dict("nmos" => "NMOS", "pmos" => "PMOS")
const LOAD_NAMES = Dict("ideal" => "ideal current-source load", "passive" => "resistor load",
                        "degen" => "source degeneration")
const CONFIG_NAMES = Dict("cs" => "common source", "cg" => "common gate",
                          "sf" => "source follower")

"""
    AmplifierCircuit

One circuit from [`next_circuit`](@ref): its name and place in the sequence, every
parameter value, the annotated schematic and a Microelectronics `Netlist`.

Fields:

- `name` (`"nmos_degen_cs"`, …), `device`, `load`, `config`; `number` of `total` in the
  sequence
- `RD`, `RS`, `ID`, `Vofs`: the random values, or `nothing` for an element this circuit
  doesn't have
- `VDD`, `VSS`, `RC`, `CC`, `model` (the transistor model), `amplitude`, `frequency`
- `schematic`, `netlist`

Unpack the ones you need by name:

    c = next_circuit()
    (; RD, RS, VDD, netlist) = c          # Julia ≥ 1.7
    @unpack RD, RS, VDD, netlist = c      # with Parameters.jl (or UnPack.jl)

In a notebook, `c` shows its values and its schematic; `print(c)` gives a text summary.
"""
struct AmplifierCircuit
    name::String
    device::String
    load::String
    config::String
    number::Int
    total::Int
    RD::Any
    RS::Any
    ID::Any
    Vofs::Any
    VDD::Any
    VSS::Any
    RC::Any
    CC::Any
    model::String
    amplitude::Any
    frequency::Any
    schematic::Schematic
    netlist::Any                      # Microelectronics Netlist
end

# (label, value) lines of the summary; elements the circuit doesn't have are left out
function summary_lines(c::AmplifierCircuit)
    present(xs...) = join(("$k = $v" for (k, v) in xs if v !== nothing), ", ")
    lines = [
        "supplies" => present("VDD" => c.VDD, "VSS" => c.VSS),
        "transistor" => c.model,
        "bias" => present("RD" => c.RD, "RS" => c.RS, "ID" => c.ID),
        "offset" => present("Vofs" => c.Vofs),
        "coupling" => present("RC" => c.RC, "CC" => c.CC),
        "signal" => "$(c.amplitude), $(c.frequency) sine",
    ]
    filter(l -> !isempty(l.second), lines)
end

summary_title(c::AmplifierCircuit) =
    "$(c.name) ($(c.number) of $(c.total)): $(DEVICE_NAMES[c.device]) " *
    "$(CONFIG_NAMES[c.config]), $(LOAD_NAMES[c.load])"

Base.show(io::IO, c::AmplifierCircuit) = print(io, "AmplifierCircuit(\"", c.name, "\")")

function Base.show(io::IO, ::MIME"text/plain", c::AmplifierCircuit)
    println(io, summary_title(c))
    for (label, text) in summary_lines(c)
        println(io, "  ", rpad(label * ":", 12), text)
    end
    print(io, "  fields:     ", join(fieldnames(AmplifierCircuit), ", "))
end

htmlescape(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

# Jupyter shows this: the summary as a small table, then the schematic
function Base.show(io::IO, ::MIME"text/html", c::AmplifierCircuit)
    print(io, "<div><p><b>", htmlescape(summary_title(c)), "</b></p>",
          "<table style=\"text-align:left\">")
    for (label, text) in summary_lines(c)
        print(io, "<tr><th style=\"text-align:left;padding-right:1em\">", htmlescape(label),
              "</th><td style=\"text-align:left\">", htmlescape(text), "</td></tr>")
    end
    print(io, "</table>", to_svg(c.schematic), "</div>")
end

#= Random RD, RS, ID and Vofs, chosen so the amplifying transistor is saturated.

Common source and common gate: the bias network is a copy of the amplifier with its
transistor diode-connected (same RD, RS or ID, same model), and it sets the amplifier's
gate voltage. So both transistors carry the same current, and the amplifier's drain sits
at its gate voltage: V_DS = V_GS > V_GS - V_t, saturated for any values. These keep the
original ranges, RD 10–50 kΩ and RS 50–1000 Ω.

Source follower: the gate sits at Vofs, between V_SS + 1.5 V and V_DD - 1.5 V in 0.5 V
steps (±1.5 V with the default ±3 V supplies), so the transistor is well on. RS is the
source load, 5–50 kΩ: with the ALD1105 models I_D is about 10–500 μA. With no RD the drain
is at a supply and the transistor is saturated whenever it's on. With RD
(degeneration) the drain moves, so RD is limited: for NMOS, on means V_S ≤ V_G - V_t, so
I_D ≤ (V_G - V_SS)/RS for any V_t ≥ 0, and V_D = V_DD - I_D RD ≥ V_G (≥ V_G - V_t,
saturated) whenever RD/RS ≤ (V_DD - V_G)/(V_G - V_SS). PMOS is the mirror image,
RD/RS ≤ (V_G - V_SS)/(V_DD - V_G). RD is drawn below 80% of that bound, in 100 Ω steps,
and no more than 50 kΩ. The bound holds for any enhancement-mode model, so changing the
models or supplies with `set_parameters` doesn't break it. =#
function random_values(s::Settings, device, load, config)
    rng = s.rng
    VDD, VSS = s.supplies["vdd"], s.supplies["vss"]
    RD = rand(rng, 10:50) * u"kΩ"
    RS = rand(rng, 50:1000) * u"Ω"
    ID = rand(rng, 100:500) * u"μA"
    steps = floor(Int, ustrip(u"V", VDD - VSS - 3u"V") / 0.5)
    steps >= 0 || error("V_DD - V_SS must be at least 3 V")
    Vofs = uconvert(u"V", VSS + 1.5u"V" + 0.5u"V" * rand(rng, 0:steps))
    if config == "sf"
        RS = rand(rng, 5:50) * u"kΩ"
        if load == "degen"
            ratio = device == "nmos" ? (VDD - Vofs) / (Vofs - VSS) :
                                       (Vofs - VSS) / (VDD - Vofs)
            limit = 0.8 * uconvert(NoUnits, ratio) * ustrip(u"Ω", RS)    # in Ω
            n = min(floor(Int, limit / 100), 500)
            RD = n >= 1 ? uconvert(u"kΩ", rand(rng, 1:n) * 100u"Ω") :
                          floor(Int, limit) * u"Ω"                  # only with tight supplies
        end
    end
    (; RD, RS, ID, Vofs)
end

"""
    next_circuit() -> AmplifierCircuit

The next circuit in the shuffled sequence (it starts over after the last one), with
random values for RD, RS, ID and the offset voltage Vofs, the annotated schematic and a
Microelectronics `Netlist` ready to simulate. See [`AmplifierCircuit`](@ref) for the
fields. `set_parameters` restarts the sequence.
"""
function next_circuit()
    s = SETTINGS[]
    s.index = mod1(s.index + 1, length(s.order))
    name = s.order[s.index]

    device, load, config = split(name, '_')
    (; RD, RS, ID, Vofs) = random_values(s, device, load, config)
    CC, RC = s.CC, s.RC
    P1 = P2 = s.Pmodel
    N1 = N2 = s.Nmodel
    amplitude, frequency = s.amplitude, s.frequency
    Vsig = (; amplitude, frequency)
    table = @table CC RC ID P1 P2 N1 N2 RD RS Vofs Vsig

    elements = matching_elements(SCHEMATICS[name], table)
    schem = annotate(SCHEMATICS[name], elements)
    model = to_microelectronics(schem; supplies=s.supplies)
    # Vsig: its last waveform becomes a plain sine at the set amplitude and frequency
    i = findfirst(x -> x.name == "Vsig", model.sources)
    if i !== nothing
        vsig = model.sources[i]
        isempty(vsig.waveforms) || pop!(vsig.waveforms)
        push!(vsig.waveforms, Waveform(:sin; amplitude, frequency))
    end
    netlist = Netlist(; title=name, model.components, model.sources)

    # values of elements this circuit has; `nothing` for the others
    drawn = Set(replace(k, r"_\d+$" => "") for k in keys(elements))
    ifdrawn(key, value) = key in drawn ? value : nothing
    AmplifierCircuit(name, device, load, config, s.index, length(s.order),
                     ifdrawn("RD", RD), ifdrawn("RS", RS), ifdrawn("ID", ID),
                     ifdrawn("Vofs", Vofs), s.supplies["vdd"], s.supplies["vss"], RC, CC,
                     device == "nmos" ? s.Nmodel : s.Pmodel, amplitude, frequency,
                     schem, netlist)
end

"""Names of all circuits, e.g. `"nmos_ideal_cs"`, sorted."""
circuit_list() = sort!(collect(keys(SCHEMATICS)))

"""The complete circuit (signal source, bias, amplifier, coupling) named `name`."""
complete_schematic(name) = SCHEMATICS[name]

"""The bare amplifier of circuit `name`."""
amplifier_configuration(name) = AMPLIFIERS[name]

"""The bias network of circuit `name`."""
bias_schematic(name) = BIASES[name]

"""The general NMOS amplifier, with drain and source resistors."""
nmos_amplifier_topology() = ascii_schematic(NMOS_TOPOLOGY)

"""The general PMOS amplifier, with source and drain resistors."""
pmos_amplifier_topology() = ascii_schematic(PMOS_TOPOLOGY)

end # module
