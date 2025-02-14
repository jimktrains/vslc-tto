## How to test

Place a program on EEPROM (or an emulator), and use the IO pins.

For instance, the program:

    0x00
    0x04
    0x00
    0x08
    0x00
    0x8C
    0x18
    0x93
    0x19

"decompiles" as

    Cycle Start Vector - 0x00 0x04
    Program end address - 0x00 0x08
    PUSH input0 - Read input 0 and push onto the stack
    DUP - Duplicate the top of stack
    POP output0 - Pop the top of stack (value from input0) to output0
    NOT - Invert the top of stack
    PUSH output1 - Pop the top of stack (inverted input0) to output1

The controller will then chip select cycle the eeprom and send a read
command for address 0x00 0x04, latch input, and begin executing the program
again.
