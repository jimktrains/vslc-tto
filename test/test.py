# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

IO_I = 0
IO_O = 1

INSTR_PUSH = lambda io, reg : 0x00 + (io << 3) + reg
INSTR_POP = lambda reg : 0x18 + reg
INSTR_SET = lambda reg : 0x28 + reg
INSTR_RESET = lambda reg : 0x38 + reg
INSTR_POP_TIMER = 0x10
INSTR_SET_TIMER = 0x20
INSTR_RESET_TIMER = 0x30
INSTR_NOP = 0xff
INSTR_CLR = 0xf0
INSTR_SETALL = 0xf1
INSTR_RISING     = lambda reg : 0b11100000 + reg
INSTR_FALLING    = lambda reg : 0b11101000 + reg
INSTR_SWAP = 0b11110010
INSTR_ROT  = 0b11110011

INSTR_AND     = 0b10100001
INSTR_NAND    = 0b10101110
INSTR_OR      = 0b10100111
INSTR_NOR     = 0b10101000
INSTR_XOR     = 0b10100110
INSTR_BICOND  = 0b10101001
INSTR_IMPL    = 0b10101101
INSTR_NIMPL   = 0b10100010
INSTR_CONV    = 0b10101011
INSTR_NCONV   = 0b10100100

INSTR_DUP     = 0b10001100
INSTR_OVER    = 0b10001010
INSTR_DROP    = 0b10101010
INSTR_ZERO    = 0b10000000
INSTR_ONE     = 0b10001111
INSTR_NOT     = 0b10010011
INSTR_OVERNOT = 0b10100101

instr_names = {
0b10100001: "INSTR_AND",
0b10101110: "INSTR_NAND",
0b10100111: "INSTR_OR",
0b10101000: "INSTR_NOR",
0b10100110: "INSTR_XOR",
0b10101001: "INSTR_BICOND",
0b10101101: "INSTR_IMPL",
0b10100010: "INSTR_NIMPL",
0b10101011: "INSTR_CONV",
0b10100100: "INSTR_NCONV",

0b10011010: "INSTR_NOT",
0b10000101: "INSTR_DUP",
0b10000011: "INSTR_OVER",
0b10100101: "INSTR_DROP",
0b10101010: "INSTR_OVERNOT",
0b10000000: "INSTR_ZERO",
0b10001111: "INSTR_ONE",
}

# These silly little functions just make debugging easier when it's
# just printing the function name.
def assert_timer_high(dut, stack):
    return ((dut.uo_out.value[7-TIMER_OUTPUT]) & 0x1) == 1

def assert_timer_low(dut, stack):
    return ((dut.uo_out.value[7-TIMER_OUTPUT]) & 0x1) == 0

def assert_tos(x):
    def y(dut, stack):
        return ((dut.uio_out.value[7-TOS_OUPUT]) & 0x1) == x
    return y

def assert_tos_t(dut, stack):
    return ((dut.uio_out.value[7-TOS_OUPUT]) & 0x1) == 1

def assert_tos_f(dut, stack):
    return ((dut.uio_out.value[7-TOS_OUPUT]) & 0x1) == 0

def assert_output_1_t(dut, stack):
    return ((dut.uo_out.value[7-1]) & 0x1) == 1

def assert_output_1_f(dut, stack):
    return ((dut.uo_out.value[7-1]) & 0x1) == 0


def generate_test_result(instr, i):
    return (instr >> (3-i)) & 0x1 == True

def generate_test(instr):
    name = instr_names[instr]
    tests = []
    tests.append((f"Clearing stack for " + instr_names[instr], None))
    tests.append((INSTR_CLR, test_stack(0)))
    r = 0
    for i in range(4):
        a = (i & 0b10) >> 1
        b = (i & 0b01)
        atest = assert_tos_t
        if a == 0:
            atest = assert_tos_f
        btest = assert_tos_t
        if b == 0:
            btest = assert_tos_f
        expected_result = generate_test_result(instr, i)
        expected_result_test = assert_tos_t
        if not expected_result:
            expected_result_test = assert_tos_f

        tests.append((instr_names[instr] + f" {i}: tos={b} {a} => {expected_result}", None))
        tests.append((INSTR_PUSH(IO_I, a),atest))
        tests.append((INSTR_PUSH(IO_I, b),btest))
        tests.append((instr, expected_result_test))

        r <<= 1
        r |= a
        r <<= 1
        r |= b

        if (instr & 0b00100000):
            r >>= 2
        elif (instr & 0b00010000):
            r >>= 1
        r <<= 1
        r |= expected_result
        r &= 0xff
        tests.append((f"Testing stack={r:08b}", None))
        tests.append((INSTR_NOP, test_stack(r)))
    return tests


def generate_timer_test():
    return [
        ("Timer Test", None),
        push_true,
        ("Enable Timer", None),
        (INSTR_SET_TIMER,    None ),
        ("Check High", None),
        (INSTR_NOP, assert_timer_high),
        ("Check Low", None),
        (INSTR_NOP, assert_timer_low),
        (INSTR_NOP,          None ),
        (INSTR_NOP,          None ),
        ("Disable Timer", None),
        push_false,
        (INSTR_POP_TIMER,    None ),
        (INSTR_NOP,          None ),
        ("Check Low 1", None),
        (INSTR_NOP, assert_timer_low),
        ("Check Low 2", None),
        (INSTR_NOP, assert_timer_low),
        ("Check Low 3", None),
        (INSTR_NOP, assert_timer_low),
        (INSTR_NOP,          None ),
    ]


EEPROM_READ_COMMAND = 0x03;

#CYCLE_START = 0;
EEPROM_COPI = 0;
EEPROM_CIPO = 1;
EEPROM_CS = 2;
#STACK_OUTPUT2 = 4;
STACK_OUTPUT = 5;
TOS_OUPUT = 6;
TIMER_OUTPUT = 7;


msg = lambda m : (m, None)

def test_stack(expected):
    def y(dut, stack):
        return True
        return stack == expected
    return y

def pop_test(expected):
    test_fn = assert_output_1_t;
    if not expected:
        test_fn = assert_output_1_f
    return (INSTR_POP(1), test_fn)

def set_test(expected):
    test_fn = assert_output_1_t;
    if not expected:
        test_fn = assert_output_1_f
    return (INSTR_SET(1), test_fn)

def reset_test(expected):
    test_fn = assert_output_1_t;
    if not expected:
        test_fn = assert_output_1_f
    return (INSTR_RESET(1), test_fn)

push_true = (INSTR_PUSH(IO_I, 1), assert_tos_t)
push_false = (INSTR_PUSH(IO_I, 0), assert_tos_f)

nop = (INSTR_NOP, None )

MEMORY = [
    (0x04, None ),
    (0x00, None ),
    (0xff, None ),
    (0xff, None ),

    msg("Test Push"),
    push_true,
    push_false,
    push_true,
    push_true,
    (INSTR_NOP, test_stack(0b00001011)),

    msg("Test Pop"),
    pop_test(True),
    pop_test(True),
    pop_test(False),
    pop_test(True),

    msg("Clear Test"),
    (INSTR_CLR, assert_tos_f),
    (INSTR_NOP, test_stack(0b00000000)),
    msg("SetAll Test"),
    (INSTR_SETALL, assert_tos_t),
    (INSTR_NOP, test_stack(0b11111111)),

    msg("Test Set (0)"),
    # Set the output to the opposite of
    # what it should be at the end
    # of the test if set isn't working/
    # behaving like a push.
    push_true,
    pop_test(True),
    push_false,
    set_test(True),

    msg("Test Set (1)"),
    push_false,
    pop_test(False),
    push_true,
    set_test(True),

    msg("Test Reset (0)"),
    push_true,
    pop_test(True),
    push_false,
    reset_test(True),

    msg("Test Reset (1)"),
    push_true,
    pop_test(True),
    push_true,
    reset_test(False),

    ] + \
    generate_timer_test()

for (instr, mnemonic) in instr_names.items():
    MEMORY += generate_test(instr)

for i in [True, False]:
    for j in [True, False]:
        for k in [True, False]:
            MEMORY.append((INSTR_CLR, None))
            if i:
                MEMORY.append(push_true)
            else:
                MEMORY.append(push_false)

            if j:
                MEMORY.append(push_true)
            else:
                MEMORY.append(push_false)

            if k:
                MEMORY.append(push_true)
            else:
                MEMORY.append(push_false)

            MEMORY.append((f"Testing rot tos={k} {j} {i}", None))
            MEMORY.append((INSTR_ROT, assert_tos(j)))
            r = k
            r <<= 1
            r |= i
            r <<= 1
            r |= j

            MEMORY.append((f"Testing stack={r:08b}", None))
            MEMORY.append((INSTR_NOP, test_stack(r)))

for j in [True, False]:
    for k in [True, False]:
        MEMORY.append((f"Testing SWAP tos={k} {j}", None))
        MEMORY.append((INSTR_CLR, None))
        if j:
            MEMORY.append(push_true)
        else:
            MEMORY.append(push_false)

        if k:
            MEMORY.append(push_true)
        else:
            MEMORY.append(push_false)

        MEMORY.append((INSTR_SWAP, assert_tos(j)))
        r = k
        r <<= 1
        r |= j

        MEMORY.append((f"Testing stack={r:08b}", None))
        MEMORY.append((INSTR_NOP, test_stack(r)))

async def read8(dut):
    r = 0x0
    for i in range(8):
        await ClockCycles(dut.clk, 1, rising=True)
        r += ((dut.uio_out.value[7-EEPROM_COPI]) & 0x01) << (7-i)
    return r

async def write8(dut, v):
    rs = 0
    orig_uio_in = dut.uio_in.value


    y = 1 << EEPROM_CIPO
    for i in range(8):
        x = orig_uio_in & (0xff - y)
        v1 = v & (1<<(7-i))
        v2 = v1 != 0
        v3 = v2 << EEPROM_CIPO
        x |= v3
        # Do a cycle every instruction
        x |= (i > 5) and (i < 7)
        dut.uio_in.value = x
        await ClockCycles(dut.clk, 1, rising=False)
        #if i < 7 and i > 2:
        #    s1 = (((dut.uio_out.value[7-STACK_OUTPUT]) & 0x01) << (((7-i)-1)*2 + 1)) & 0xff
        #    s2 = (((dut.uio_out.value[7-STACK_OUTPUT2]) & 0x01) << (((7-i)-1)*2)) & 0xff

            #rs += s1 + s2
    # rs += (((dut.uio_out.value[7-TOS_OUPUT]) & 0x01) << 0) & 0xff
    # rs += (((dut.uio_out.value[7-STACK_OUTPUT2]) & 0x01) << 1) & 0xff
    return rs

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await ClockCycles(dut.clk, 1)

    # Reset
    dut._log.info(f"{len(MEMORY)=}")
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"{dut.uio_out.value=}")
    assert dut.uio_out.value[7-EEPROM_CS]
    dut.rst_n.value = 1
    dut._log.info(f"Reset Done")
    dut._log.info(f"Reading READ Command")
    assert (await read8(dut)) == EEPROM_READ_COMMAND
    assert not dut.uio_out.value[7-EEPROM_CS]
    dut._log.info(f"Reading Address")
    assert (await read8(dut)) == 0
    assert (await read8(dut)) == 0
    last_a = None
    adj_addr = 0

    for (i,(m,a)) in enumerate(MEMORY):
        if (isinstance(m, str)):
            dut._log.info(f"#### {i=} {m=}")
            continue
        dut._log.info(f"{i=} {adj_addr=} {m=:02x}")
        adj_addr += 1
        read_stack = await write8(dut, m)
        tos = ((dut.uio_out.value[7-TOS_OUPUT]) & 0x1)
        dut._log.info(f"  {read_stack=:08b} {tos=}")
        if last_a is not None:
            res = last_a(dut, read_stack)
            if not res:
                dut._log.info(f"  {dut.uio_out.value=}")
                dut._log.info(f"  {dut.uo_out.value=}")
                dut._log.info(f"  {last_a=}")
                dut._log.info(f"  last_a(dut)={res}")
                assert res
        last_a = a

    for i in range(8):
        for j in [1, 0]:
            for k in [1, 0]:
                expected = ((not j) and k)
                dut._log.info(f"#### Testing RISING({i}) {j} to {k} => {expected}")
                adj_addr += 1
                dut.ui_in.value = (j << i)
                read_stack = await write8(dut, INSTR_NOP)

                dut.ui_in.value = (k << i)
                m = INSTR_RISING(i)
                adj_addr += 1
                dut._log.info(f"      {adj_addr=} {m=:02x} {j<<i=} {k<<i=}")
                read_stack = await write8(dut, m)
                read_stack = await write8(dut, INSTR_NOP)
                tos = ((dut.uio_out.value[7-TOS_OUPUT]) & 0x1)
                assert tos == expected
    for i in range(8):
        for j in [1, 0]:
            for k in [1, 0]:
                expected = ((not k) and j)
                dut._log.info(f"#### Testing FALLING ({i}) {j} to {k} => {expected}")
                adj_addr += 1
                dut.ui_in.value = (j << i)
                read_stack = await write8(dut, INSTR_NOP)

                dut.ui_in.value = (k << i)
                m = INSTR_FALLING(i)
                adj_addr += 1
                dut._log.info(f"      {adj_addr=} {m=:02x} {j<<i=} {k<<i=}")
                read_stack = await write8(dut, m)
                read_stack = await write8(dut, INSTR_NOP)
                tos = ((dut.uio_out.value[7-TOS_OUPUT]) & 0x1)
                assert tos == expected

        await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_addressing(dut):
    return
    dut._log.info("Start, the Second")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await ClockCycles(dut.clk, 1)

    MEMORY = [
        0x00,
        0x05,
        0x00,
        0x06,
        INSTR_ZERO,
        INSTR_POP(0),
        INSTR_ONE,
    ]

    # Reset
    dut._log.info(f"{len(MEMORY)=}")
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    assert dut.uio_out.value[7-EEPROM_CS]
    dut._log.info(f"Reset Done")
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"Reading READ Command")
    assert (await read8(dut)) == EEPROM_READ_COMMAND
    dut._log.info(f"Reading Address")
    assert (await read8(dut)) == 0
    assert (await read8(dut)) == 0

    await write8(dut, MEMORY[0])
    await write8(dut, MEMORY[1])
    await write8(dut, MEMORY[2])
    await write8(dut, MEMORY[3])
    await write8(dut, MEMORY[4])
    await write8(dut, MEMORY[5])
    await write8(dut, MEMORY[6])
    dut._log.info(f"Got to the end of the program")
    assert not dut.uo_out.value[7-0]
    # write8 stops on a falling edge
    # and we need a full clock cycle
    # to get to the start of the next
    # cycle.
    await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, 1)

    assert dut.uio_out.value[7-EEPROM_CS]

    await ClockCycles(dut.clk, 1, rising=False)
    dut._log.info(f"Reading READ Command")
    assert (await read8(dut)) == EEPROM_READ_COMMAND
    dut._log.info(f"Reading Address")
    assert (await read8(dut)) == 0
    assert (await read8(dut)) == 5
    await write8(dut, MEMORY[5])
    await write8(dut, MEMORY[6])
    dut._log.info(f"verified that it's running where it left of!")
    assert dut.uo_out.value[7-0]
