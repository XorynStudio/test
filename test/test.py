import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Starting CHIMERA-1 Elastic CPU/GPU Silicon Verification")

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

    # 1. CPU Mode (FUSE): MOVI R0 = 5
    dut.uio_in.value = 5
    dut.ui_in.value = 0b1_00_0_0_000
    await ClockCycles(dut.clk, 2)
    assert int(dut.uo_out.value) == 5

    # 2. CPU Mode (FUSE): MOVI R1 = 3
    dut.uio_in.value = 3
    dut.ui_in.value = 0b1_01_0_0_000
    await ClockCycles(dut.clk, 2)
    assert int(dut.uo_out.value) == 3

    # 3. 1-Cycle Morph to GPU Mode (WAVE) + 2D Morton Swizzle (X=5, Y=3 -> 0x1B)
    dut.ui_in.value = 0b1_00_0_1_101
    await ClockCycles(dut.clk, 2)
    assert int(dut.uo_out.value) == 0x1B

    # 4. Verify Hardware Z-Buffer Depth Test (ROP.ZWRITE)
    dut.ui_in.value = 0b1_00_0_1_110
    await ClockCycles(dut.clk, 2)
    assert int(dut.uo_out.value) == 3

    dut._log.info("CHIMERA-1 All Silicon Tests PASSED!")
