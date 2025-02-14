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

Place a program on EEPROM (or an emulator), and use the IO pins.

For instance, the program:

````
0x00
0x04
0x00
0x08
0x00
0x8C
0x18
0x93
0x19
````

"decompiles" as

````
Cycle Start Vector - 0x00 0x04
Program end address - 0x00 0x08
PUSH input0 - Read input 0 and push onto the stack
DUP - Duplicate the top of stack
POP output0 - Pop the top of stack (value from input0) to output0
NOT - Invert the top of stack
PUSH output1 - Pop the top of stack (inverted input0) to output1
````

The controller will then chip select cycle the eeprom and send a read
command for address 0x00 0x04, latch input, and begin executing the program
again.

## External hardware

The controller expects something that presents as an EEPROM that accepts
16-bit addresses and will provide continous data while the clock and chip
select are active.

Alternativly, I plan to make a PMOD that will act as a user controllable
test bed.

## General Description

* Stack machine
  * Code executes until a cycle start happens or the end of code memory is
    reached, in which case a new cycle is started
* 8 input bits/registers mapped to pins
* 8 output bits/registers mapped to pins
* 16 bit data stack
* 1 10-bit timer/counter with clock divisor

### Opcodes

#### General Decoding rules

* Bit 7
* 0: Register Operations
* Bit 6
  * 00: IO Registers
  * 01: Special Function Registers (SFR)
* Bit 5,4
  \* 00 Push
  \* 01 Pop
  \* 10 Set
  \* 11 Reset
* 1: Operations
* Bit 6
* 0: Logical Operations
  These all write to the top of stack. The shifts below are the final
  shifts, not the number of pops before the operation pushes. e.g. `NOT`
  conseptually does a pop and then a push, which is a shift of 0.
  \* Bit 5,4
  * 00: No Shift
  * 01: Shift 1 Right
  * 10: Reserved
  * 11: Shift 1 Left
    \* Bits 3,2,1,0: Truth table. The result is bit `3 - {nos, tos}`
* 1: Other
  \* Bit 5
  * 0: Temporal (Rising/Falling)
  * Bit 4 - Expected previous state
  * 1: Other
  * Bit 4:
  * 0: Set Parameters
  * 1: Other

### Register Operations

````
PUSH reg    0000 IRRR
POP  reg    0001 1RRR
SET  reg    0010 1RRR
RESET reg   0011 1RRR
PUSH sfr    0100 RRRR
POP sfr     0101 RRRR
SET sfr     0110 RRRR
RESET sfr   0111 RRRR
````

### Logical Operations

````
AND         1010 0001
NAND        1010 1110
OR          1010 0111
NOR         1010 1000
XOR         1010 0110
BICOND      1010 1001
IMPL        1010 1101
NIMPL       1010 0010
CONV        1010 1011
NCONV       1010 0100

DUP         1000 1100
OVER        1000 1010
DROP        1010 1010
ZERO        1011 0000
ONE         1011 1111
NOT         1001 0011
OVERNOT     1010 0101
````

### Temporal Operations

````
RISING  reg 1100 IRRR
FALLING reg 1101 IRRR
````

### Parameters

These are followed by a byte with the value to set

````
SPARAM0 parm 1110 0PPP XXXX XXXX
SPARAM1 parm 1110 1PPP XXXX XXXX
````

## Other

````
CLR         1111 0000
SETALL      1111 0001
SWAP        1111 0010
ROT         1111 0011
NOP         1111 1111
````

## Special Function Registers SFR

* 0x0 Timer Enable
* 0x1 Timer Output
* 0x2 Servo Enable
* 0x3 Servo Value
* 0x4 Servo Output

## Parameter

* 0x0 SPI Clock Divider (Not Implemented)
* 0x1 Timer0 Clock Divider (4 bits)
* 0x2 Timer0 Counter A (Not Implemented)
* 0x3 Timer0 Counter B (Not Implemented)
* 0x4 Servo0 Clock Divider (Not Implemented)
* 0x5 Servo0 Frequency Value (Not Implemented)
* 0x6 Servo0 Reset Value (Not Implemented)
* 0x7 Servo0 Set Value (4 bits)

