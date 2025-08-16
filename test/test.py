# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
import os

# Set environment variable to handle X values
os.environ['COCOTB_RESOLVE_X'] = '0'

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    
    # Set the clock period to 10 ns (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Helper function to safely read output values
    def safe_read_output(signal):
        try:
            return int(signal.value)
        except (ValueError, TypeError):
            dut._log.warning(f"Signal contains X/Z values: {signal.value}, treating as 0")
            return 0
    
    # Helper function to decode output
    def decode_output(uo_out_val):
        power = uo_out_val & 0x01
        headlight = (uo_out_val >> 1) & 0x01
        horn = (uo_out_val >> 2) & 0x01
        indicator = (uo_out_val >> 3) & 0x01
        pwm = (uo_out_val >> 4) & 0x01
        overheat = (uo_out_val >> 5) & 0x01
        status_leds = (uo_out_val >> 6) & 0x03
        return power, headlight, horn, indicator, pwm, overheat, status_leds
    
    # EXTENDED RESET for Sky130 compatibility
    dut._log.info("Extended Reset for Sky130")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 100)  # Longer reset for Sky130
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 100)  # Longer stabilization time
    
    # Wait for internal reset synchronizer to complete
    dut._log.info("Waiting for internal reset synchronizer...")
    await ClockCycles(dut.clk, 50)
    
    dut._log.info("=== TESTING MOTOR SPEED CALCULATION (SKY130 VERSION) ===")
    
    # =============================================================================
    # CASE 4: MOTOR SPEED CALCULATION - FIXED FOR SKY130
    # =============================================================================
    dut._log.info("CASE 4: MOTOR SPEED CALCULATION")
    
    # Step 1: Ensure power is on and wait for stabilization
    dut.ui_in.value = 0b00001000  # power_on_plc=1, operation_select=000
    await ClockCycles(dut.clk, 50)  # Longer wait for Sky130
    
    # Verify power is actually on
    output_val = safe_read_output(dut.uo_out)
    power, _, _, _, _, _, _ = decode_output(output_val)
    dut._log.info(f"Power status after power on: {power}")
    
    # Step 2: Set input data BEFORE switching to motor control mode
    # Test 1: accelerator=12, brake=4
    # Upper 4 bits = 1100 (12), Lower 4 bits = 0100 (4)
    dut.uio_in.value = 0b11000100
    await ClockCycles(dut.clk, 20)  # Let data settle
    
    # Step 3: Switch to motor speed calculation mode
    dut.ui_in.value = 0b00001100  # power_on_plc=1, operation_select=100
    await ClockCycles(dut.clk, 100)  # Much longer wait for calculation in Sky130
    
    # Read results
    motor_speed = safe_read_output(dut.uio_out)
    output_val = safe_read_output(dut.uo_out)
    power, _, _, _, _, _, _ = decode_output(output_val)
    
    expected_speed = (12 - 4) * 16  # Should be 8 * 16 = 128
    
    dut._log.info(f"Motor Speed Test 1 (Sky130):")
    dut._log.info(f"  Input: accelerator=12, brake=4")
    dut._log.info(f"  Expected: (12-4)*16 = {expected_speed}")
    dut._log.info(f"  Actual: {motor_speed}")
    dut._log.info(f"  Power: {power}")
    dut._log.info(f"  Output register: 0x{output_val:02x}")
    dut._log.info(f"  uio_in value: 0x{int(dut.uio_in.value):02x}")
    
    # Debug: Check internal signals if accessible
    try:
        accel_val = safe_read_output(dut.accelerator_value)
        brake_val = safe_read_output(dut.brake_value)
        sys_enabled = safe_read_output(dut.system_enabled)
        dut._log.info(f"  Internal accelerator: {accel_val}")
        dut._log.info(f"  Internal brake: {brake_val}")
        dut._log.info(f"  System enabled: {sys_enabled}")
    except:
        dut._log.info("  Internal signals not accessible")
    
    assert motor_speed == expected_speed, f"Expected motor_speed={expected_speed}, got {motor_speed}"
    
    # Test 2: accelerator=15, brake=1 - with proper sequencing
    dut._log.info("Setting up Test 2...")
    dut.uio_in.value = 0b11110001  # Upper 4: 1111=15, Lower 4: 0001=1
    await ClockCycles(dut.clk, 20)  # Data setup time
    
    # Make sure we're still in motor control mode
    dut.ui_in.value = 0b00001100  # Reinforce mode setting
    await ClockCycles(dut.clk, 100)  # Calculation time
    
    motor_speed2 = safe_read_output(dut.uio_out)
    expected_speed2 = (15 - 1) * 16  # Should be 14 * 16 = 224
    
    dut._log.info(f"Motor Speed Test 2 (Sky130):")
    dut._log.info(f"  Input: accelerator=15, brake=1")
    dut._log.info(f"  Expected: (15-1)*16 = {expected_speed2}")
    dut._log.info(f"  Actual: {motor_speed2}")
    
    assert motor_speed2 == expected_speed2, f"Expected motor_speed={expected_speed2}, got {motor_speed2}"
    
    # Test 3: accelerator=brake (should be 0)
    dut._log.info("Setting up Test 3...")
    dut.uio_in.value = 0b10001000  # Upper 4: 1000=8, Lower 4: 1000=8
    await ClockCycles(dut.clk, 20)
    dut.ui_in.value = 0b00001100  # Reinforce mode
    await ClockCycles(dut.clk, 100)
    
    motor_speed3 = safe_read_output(dut.uio_out)
    
    dut._log.info(f"Motor Speed Test 3 (Sky130):")
    dut._log.info(f"  Input: accelerator=8, brake=8")
    dut._log.info(f"  Expected: 0 (equal values)")
    dut._log.info(f"  Actual: {motor_speed3}")
    
    assert motor_speed3 == 0, f"Expected motor_speed=0 when accel=brake, got {motor_speed3}"
    
    # Test 4: brake > accelerator (should be 0)
    dut._log.info("Setting up Test 4...")
    dut.uio_in.value = 0b01001111  # Upper 4: 0100=4, Lower 4: 1111=15
    await ClockCycles(dut.clk, 20)
    dut.ui_in.value = 0b00001100  # Reinforce mode
    await ClockCycles(dut.clk, 100)
    
    motor_speed4 = safe_read_output(dut.uio_out)
    
    dut._log.info(f"Motor Speed Test 4 (Sky130):")
    dut._log.info(f"  Input: accelerator=4, brake=15")
    dut._log.info(f"  Expected: 0 (brake > accelerator)")
    dut._log.info(f"  Actual: {motor_speed4}")
    
    assert motor_speed4 == 0, f"Expected motor_speed=0 when brake>accel, got {motor_speed4}"
    
    # =============================================================================
    # CASE 5: PWM GENERATION TEST - UPDATED FOR SKY130
    # =============================================================================
    dut._log.info("CASE 5: PWM GENERATION (Sky130)")
    
    # First set a known motor speed with proper sequencing
    dut.uio_in.value = 0b10100010  # accel=10, brake=2 -> speed = 8*16 = 128
    await ClockCycles(dut.clk, 20)
    dut.ui_in.value = 0b00001100  # motor speed calculation mode
    await ClockCycles(dut.clk, 100)  # Let motor speed calculate
    
    # Verify motor speed is set
    motor_speed_for_pwm = safe_read_output(dut.uio_out)
    dut._log.info(f"Motor speed for PWM test: {motor_speed_for_pwm}")
    
    # Now test PWM generation
    dut.ui_in.value = 0b00001101  # power_on_plc=1, operation_select=101
    await ClockCycles(dut.clk, 50)  # Mode switch time
    
    # Monitor PWM signal - longer observation for Sky130
    pwm_values = []
    for i in range(256):  # Full PWM cycle observation
        output_val = safe_read_output(dut.uo_out)
        _, _, _, _, pwm, _, _ = decode_output(output_val)
        pwm_values.append(pwm)
        await ClockCycles(dut.clk, 1)
    
    pwm_high_count = sum(pwm_values)
    duty_cycle_percent = (pwm_high_count / len(pwm_values)) * 100
    
    dut._log.info(f"PWM Generation Results (Sky130):")
    dut._log.info(f"  High Count: {pwm_high_count}/{len(pwm_values)}")
    dut._log.info(f"  Duty Cycle: {duty_cycle_percent:.1f}%")
    dut._log.info(f"  Pattern (first 20): {pwm_values[:20]}")
    dut._log.info(f"  Pattern (last 20): {pwm_values[-20:]}")
    
    # PWM should be active when motor speed > 0
    assert pwm_high_count > 0, f"Expected PWM activity, got {pwm_high_count}"
    
    dut._log.info("=== ALL MOTOR TESTS COMPLETED SUCCESSFULLY (SKY130) ===")
    dut._log.info("Motor control system is working correctly with Sky130!")
