## How it works

The VSLC (Very Small Logic Controller) is a stack machine with 8 inputs
and 8 outputs. On reset, the controller will send a READ command (0x03),
a 16-bit 0 address, and expects to receive a 2 byte scan
cycle vector, a 2 byte scan cycle end address, followed by instructions.
Once the end address is reached a new scan cycle is initiated. A scan
cycle begins by latching input while cycling the EEPROM chip select for 1
cycle, followed by a READ command (0x03) and the 16-bit cycle start vector.

A cycle may be triggered externally.
