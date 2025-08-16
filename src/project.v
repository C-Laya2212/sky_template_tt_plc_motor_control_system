/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ev_motor_control (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Pin mapping for ui_in[7:0] (Dedicated inputs)
    wire [2:0] operation_select = ui_in[2:0];  // 3-bit operation selector
    wire power_on_plc = ui_in[3];              // Power control from PLC
    wire power_on_hmi = ui_in[4];              // Power control from HMI
    wire mode_select = ui_in[5];               // 0: PLC mode, 1: HMI mode
    wire headlight_plc = ui_in[6];             // Headlight control from PLC
    wire headlight_hmi = ui_in[7];             // Headlight control from HMI

    // Pin mapping for uio_in[7:0] (Bidirectional inputs)
    wire horn_plc = uio_in[0];                 // Horn control from PLC
    wire horn_hmi = uio_in[1];                 // Horn control from HMI
    wire right_ind_plc = uio_in[2];            // Right indicator from PLC
    wire right_ind_hmi = uio_in[3];            // Right indicator from HMI
    wire [3:0] accelerator_brake_data = uio_in[7:4]; // 4-bit data for accel/brake

    // Set uio_oe to control bidirectional pins (1=output, 0=input)
    assign uio_oe = 8'b11110000;  // uio[7:4] as outputs, uio[3:0] as inputs

    // GDS FIX 1: More robust reset synchronizer for post-layout timing
    reg [3:0] reset_sync_reg;
    wire system_reset;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_sync_reg <= 4'b0000;
        end else begin
            reset_sync_reg <= {reset_sync_reg[2:0], 1'b1};
        end
    end
    
    // System is ready when reset chain is complete AND ena is high
    assign system_reset = reset_sync_reg[3] & ena;

    // Internal registers and wires - ALL explicitly sized for GDS
    reg [3:0] accelerator_value;
    reg [3:0] brake_value;
    reg [7:0] motor_speed;
    reg [7:0] pwm_counter;
    reg [7:0] pwm_duty_cycle;
    reg system_enabled;
    reg temperature_fault;
    reg [6:0] internal_temperature;
    
    // Output control registers for ALL cases
    reg headlight_active;
    reg horn_active;
    reg indicator_active;
    reg motor_active;
    reg pwm_active;

    // GDS FIX 2: Simplified timing - avoid complex clock dividers in GDS
    reg [7:0] simple_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            simple_counter <= 8'b0;
        end else if (system_reset) begin
            simple_counter <= simple_counter + 1'b1;
        end
    end

    // =============================================================================
    // GDS FIX 3: SIMPLIFIED DATA INPUT HANDLING
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accelerator_value <= 4'b0000;
            brake_value <= 4'b0000;
        end else if (system_reset) begin
            // Direct assignment - no complex logic
            accelerator_value <= uio_in[7:4];
            brake_value <= uio_in[3:0];
        end
    end

    // =============================================================================
    // GDS FIX 4: SIMPLIFIED TEMPERATURE MONITORING
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            internal_temperature <= 7'd25; // Room temperature
            temperature_fault <= 1'b0;
        end else if (system_reset) begin
            // Simplified temperature model for GDS reliability
            if (system_enabled && (motor_speed > 8'd50)) begin
                if (internal_temperature < 7'd85 && simple_counter[6:0] == 7'b0) begin
                    internal_temperature <= internal_temperature + 1'b1;
                end
            end else if (internal_temperature > 7'd25 && simple_counter[6:0] == 7'b0) begin
                internal_temperature <= internal_temperature - 1'b1;
            end

            // Simple temperature fault detection
            temperature_fault <= (internal_temperature >= 7'd80);
        end
    end

    // =============================================================================
    // GDS FIX 5: MAIN CONTROL LOGIC - GREATLY SIMPLIFIED
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Explicit reset for ALL registers for GDS compatibility
            system_enabled <= 1'b0;
            motor_speed <= 8'b00000000;
            headlight_active <= 1'b0;
            horn_active <= 1'b0;
            indicator_active <= 1'b0;
            motor_active <= 1'b0;
            pwm_active <= 1'b0;
            pwm_duty_cycle <= 8'b00000000;
        end else if (system_reset) begin
            
            // GDS FIX: Power control is the PRIMARY logic - always evaluated first
            system_enabled <= (power_on_plc | power_on_hmi);
            
            // Only proceed if system has power
            if (power_on_plc | power_on_hmi) begin
                case (operation_select)
                    3'b000: begin
                        // Power control - maintain current state
                    end
                    
                    3'b001: begin
                        // Headlight control
                        headlight_active <= (headlight_plc ^ headlight_hmi);
                    end
                    
                    3'b010: begin
                        // Horn control
                        horn_active <= (horn_plc ^ horn_hmi);
                    end
                    
                    3'b011: begin
                        // Right indicator control
                        indicator_active <= (right_ind_plc ^ right_ind_hmi);
                    end
                    
                    // GDS FIX 6: SIMPLIFIED MOTOR SPEED CALCULATION
                    3'b100: begin
                        motor_active <= 1'b1;
                        if (!temperature_fault) begin
                            // Simplified calculation - avoid potential overflow in GDS
                            if (accelerator_value > brake_value) begin
                                motor_speed <= {accelerator_value - brake_value, 4'b0000}; // Multiply by 16 using concat
                            end else begin
                                motor_speed <= 8'b00000000;
                            end
                        end else begin
                            // Fault mode - half speed
                            motor_speed <= motor_speed >> 1;
                        end
                    end
                    
                    // GDS FIX 7: SIMPLIFIED PWM GENERATION
                    3'b101: begin
                        pwm_duty_cycle <= motor_speed;
                        pwm_active <= (motor_speed != 8'b00000000);
                    end
                    
                    3'b110: begin
                        // Temperature monitoring is handled separately
                    end
                    
                    3'b111: begin
                        // System reset
                        motor_speed <= 8'b00000000;
                        pwm_duty_cycle <= 8'b00000000;
                        headlight_active <= 1'b0;
                        horn_active <= 1'b0;
                        indicator_active <= 1'b0;
                        motor_active <= 1'b0;
                        pwm_active <= 1'b0;
                    end
                    
                    default: begin
                        // Maintain state
                    end
                endcase
            end else begin
                // Power off - reset all outputs immediately
                headlight_active <= 1'b0;
                horn_active <= 1'b0;
                indicator_active <= 1'b0;
                motor_active <= 1'b0;
                pwm_active <= 1'b0;
                motor_speed <= 8'b00000000;
                pwm_duty_cycle <= 8'b00000000;
            end
        end
    end

    // =============================================================================
    // GDS FIX 8: SIMPLIFIED PWM GENERATION HARDWARE
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'b00000000;
        end else if (system_reset && system_enabled) begin
            pwm_counter <= pwm_counter + 1'b1;
        end else if (!system_enabled) begin
            pwm_counter <= 8'b00000000;
        end
    end

    // =============================================================================
    // GDS FIX 9: ROBUST OUTPUT ASSIGNMENTS
    // =============================================================================
    
    // Individual output wires for clarity
    wire power_status_wire;
    wire headlight_out_wire;
    wire horn_out_wire;
    wire right_indicator_wire;
    wire motor_pwm_wire;
    wire overheat_warning_wire;
    wire [1:0] status_led_wire;
    
    // GDS-safe assignments
    assign power_status_wire = system_reset ? system_enabled : 1'b0;
    assign headlight_out_wire = system_reset ? (headlight_active & system_enabled) : 1'b0;
    assign horn_out_wire = system_reset ? (horn_active & system_enabled) : 1'b0;
    assign right_indicator_wire = system_reset ? (indicator_active & system_enabled) : 1'b0;
    assign overheat_warning_wire = system_reset ? temperature_fault : 1'b0;
    assign status_led_wire = system_reset ? {temperature_fault, system_enabled} : 2'b00;
    
    // GDS-safe PWM generation
    assign motor_pwm_wire = (system_reset && system_enabled && pwm_active && (pwm_duty_cycle != 8'b00000000)) ? 
                           (pwm_counter < pwm_duty_cycle) : 1'b0;

    // Final output assignments - explicit bit concatenation for GDS
    assign uo_out[0] = power_status_wire;
    assign uo_out[1] = headlight_out_wire;
    assign uo_out[2] = horn_out_wire;
    assign uo_out[3] = right_indicator_wire;
    assign uo_out[4] = motor_pwm_wire;
    assign uo_out[5] = overheat_warning_wire;
    assign uo_out[6] = status_led_wire[0];
    assign uo_out[7] = status_led_wire[1];
    
    // Motor speed output - individual bit assignments for GDS reliability
    assign uio_out[0] = system_reset ? motor_speed[0] : 1'b0;
    assign uio_out[1] = system_reset ? motor_speed[1] : 1'b0;
    assign uio_out[2] = system_reset ? motor_speed[2] : 1'b0;
    assign uio_out[3] = system_reset ? motor_speed[3] : 1'b0;
    assign uio_out[4] = system_reset ? motor_speed[4] : 1'b0;
    assign uio_out[5] = system_reset ? motor_speed[5] : 1'b0;
    assign uio_out[6] = system_reset ? motor_speed[6] : 1'b0;
    assign uio_out[7] = system_reset ? motor_speed[7] : 1'b0;

    // Tie off unused signals to prevent warnings and floating nodes
    wire _unused_ok = &{mode_select, 1'b0};

endmodule
