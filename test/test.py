import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Starting CHIMERA-1 Elastic CPU/GPU Silicon Verification")

    # 50 MHz clock (20 ns period)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Reset core
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # 1. CPU Mode (FUSE): MOVI R0 = 5 (opcode=000, reg_sel=00, exec_strobe=1)
    dut.uio_in.value = 5
    dut.ui_in.value = 0b1_00_0_0_000
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value == 5

    # 2. CPU Mode (FUSE): MOVI R1 = 3 (opcode=000, reg_sel=01, exec_strobe=1)
    dut.uio_in.value = 3
    dut.ui_in.value = 0b1_01_0_0_000
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value == 3

    # 3. 1-Cycle Morph to GPU Mode (WAVE) + 2D Morton Swizzle (opcode=101, morph=1)
    dut.ui_in.value = 0b1_00_0_1_101
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value == 0x1F  # Morton interleaved address of X=5, Y=3

    # 4. Verify Hardware Z-Buffer Depth Test (ROP.ZWRITE, opcode=110)
    dut.ui_in.value = 0b1_00_0_1_110
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value == 3  # Shaded color in R1 committed!

    dut._log.info("CHIMERA-1 All Silicon Tests PASSED!")
