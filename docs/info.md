<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The VSLC (Very Small Logic Controller) is a stack machine with 8 inputs
and 8 outputs. On reset, the controller will send a READ command (0x03),
a 16-bit 0 address, and expects to receive a 2 byte scan
cycle vector, a 2 byte scan cycle end address, followed by instructions.
Once the end address is reached a new scan cycle is initiated. A scan
cycle begins by latching input while cycling the EEPROM chip select for 1
cycle, followed by a READ command (0x03) and the 16-bit cycle start vector.

A cycle may be triggered externally.

## How to test

Explain how to use your project

## External hardware

The controller expects something that presents as an EEPROM that accepts
16-bit addresses and will provide continous data while the clock and chip
select are active.

Alternativly, I plan to make a PMOD that will act as a user controllable
test bed.
