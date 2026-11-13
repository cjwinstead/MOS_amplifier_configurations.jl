# MOS_amplifier_configurations

Single-transistor MOS amplifier circuits (NMOS/PMOS; common source, common gate, source
follower; ideal, resistor or degenerated load) for assignments and practice problems.

```julia
using MOS_amplifier_configurations
set_parameters(seed=2026)          # optional
c = next_circuit()                 # shows the values and the schematic
(; RD, RS, VDD, netlist) = c
```

Tests, from this folder:

    julia --project=. -e 'using Pkg; Pkg.test()'
