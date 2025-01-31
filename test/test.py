# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

IO_I = 0
IO_O = 1

INSTR_PUSH = lambda io, reg : 0x00 + (io << 3) + reg
INSTR_POP = lambda reg : 0x10 + reg
INSTR_SET = lambda reg : 0x20 + reg
INSTR_RESET = lambda reg : 0x30 + reg
INSTR_POP_TIMER = 0x10
INSTR_SET_TIMER = 0x20
INSTR_RESET_TIMER = 0x30
INSTR_NOP = 0xff
INSTR_AND = 0xa1

MEMORY = [
    0x05, #0x00 RESET VECTOR
    0xa0, #0x01 LAST PROG ADDRESS
    INSTR_PUSH(IO_I, 0), #0x02
    INSTR_PUSH(IO_I, 0), #0x03
    INSTR_AND,
    INSTR_SET_TIMER,
        ] + ([INSTR_NOP] * 10) + [ INSTR_POP_TIMER ] + ([INSTR_NOP] * 10)

EEPROM_READ_COMMAND = 0x03;
EEPROM_SCK = 0;
EEPROM_CS = 1;
EEPROM_COPI = 2;
EEPROM_CIPO = 3;

async def read8(dut):
    r = 0x0
    for i in range(8):
        await ClockCycles(dut.clk, 1)
        dut._log.info(f"{dut.uio_out.value=}")
        r += ((dut.uio_out.value >> EEPROM_COPI) & 0x01) << (7-i)
    return r

async def write8(dut, v):
    for i in range(8):
        dut.uio_in.value = (dut.uio_in.value & (0xff - (1 << EEPROM_CIPO))) | (((v >> (7-i)) & 0x01) << EEPROM_CIPO)
        await ClockCycles(dut.clk, 1, rising=False)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await ClockCycles(dut.clk, 1)

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 1
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"{dut.uio_out.value=}")
    assert dut.uio_out.value == 0x02
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"Reset Done")
    await ClockCycles(dut.clk, 1)
    assert (await read8(dut)) == EEPROM_READ_COMMAND
    assert (await read8(dut)) == 0
    for m in MEMORY:
        dut._log.info(f"{m=:x}")
        await write8(dut, m);
    await ClockCycles(dut.clk, 1)



    dut._log.info("Test project behavior")

    dut.rst_n.value = 1
    dut.ui_in.value = 1

    # Set the input values you want to test

    dut._log.info(f"{dut.uo_out.value=}")

