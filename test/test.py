# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

INSTR_PUSH = 0;
INSTR_POP = 1;
INSTR_NOT = 8;
INSTR_AND = 9;
INSTR_OR = 10;
INSTR_XOR = 11;
INSTR_IMPL = 12;
INSTR_BIMP = 13;
INSTR_NAND = 14;
INSTR_NOP = 15;


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
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)

    program = [
            INSTR_PUSH , 0  , #  0
            INSTR_POP  , 0  , #  2
            INSTR_PUSH , 1  , #  4
            INSTR_POP  , 1  , #  6
            INSTR_PUSH , 1  , #  8
            INSTR_NOT  ,      #  9
            INSTR_POP  , 2  , #  B
            INSTR_PUSH , 0  , #  D
            INSTR_PUSH , 1  , #  F
            INSTR_AND  ,      # 11
            INSTR_POP  , 3  , # 12
            INSTR_PUSH , 0  , # 14
            INSTR_PUSH , 1  , # 16
            INSTR_OR   ,      # 18
            INSTR_POP  , 4]   # 19
    for i in program:
        dut.ui_in.value = i
        await ClockCycles(dut.clk, 1)


    dut._log.info("Test project behavior")

    dut.rst_n.value = 1
    dut.ui_in.value = 1

    # Set the input values you want to test

    # Wait for one clock cycle to see the output values
    await ClockCycles(dut.clk, len(program) + 2)

    dut._log.info(f"{dut.uo_out.value=}")
    assert dut.uo_out.value == 0x15

