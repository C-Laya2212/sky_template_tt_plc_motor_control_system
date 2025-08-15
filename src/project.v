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

    // Pin mapping for uio_in[7:0] (Bidirectional inputs when configured as inputs)
    wire horn_plc = uio_in[0];                 // Horn control from PLC
    wire horn_hmi = uio_in[1];                 // Horn control from HMI
    wire right_ind_plc = uio_in[2];            // Right indicator from PLC
    wire right_ind_hmi = uio_in[3];            // Right indicator from HMI
    
    // FIXED: Simplified data input - use remaining uio_in bits for accel/brake
    wire [3:0] accelerator_input = uio_in[7:4]; // Upper 4 bits as accelerator
    wire [3:0] brake_input = uio_in[3:0];       // Lower 4 bits as brake (when needed)

    // FIXED: Set uio_oe properly - upper 4 bits as outputs for motor speed
    assign uio_oe = 8'b11110000;  // uio[7:4] as outputs, uio[3:0] as inputs

    // Internal registers
    reg [3:0] accelerator_value;
    reg [3:0] brake_value;
    reg [7:0] motor_speed;
    reg [7:0] pwm_counter;
    reg [7:0] pwm_duty_cycle;
    reg system_enabled;
    reg temperature_fault;
    reg [6:0] internal_temperature;
    
    // Output control registers
    reg headlight_active;
    reg horn_active;
    reg indicator_active;
    reg motor_active;
    reg pwm_active;

    // PWM clock divider
    reg [15:0] pwm_clk_div;

    // =============================================================================
    // SIMPLIFIED DATA INPUT HANDLING
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accelerator_value <= 4'd0;
            brake_value <= 4'd0;
        end else if (ena) begin
            // FIXED: Direct assignment based on operation mode
            case (operation_select)
                3'b100: begin // Motor speed calculation mode
                    accelerator_value <= accelerator_input;
                    brake_value <= brake_input;
                end
                default: begin
                    // Keep current values for other operations
                end
            endcase
        end
    end

    // PWM clock generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_clk_div <= 16'd0;
        end else if (ena) begin
            pwm_clk_div <= pwm_clk_div + 16'd1;
        end
    end

    // =============================================================================
    // TEMPERATURE MONITORING
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            internal_temperature <= 7'd25; // Room temperature
            temperature_fault <= 1'b0;
        end else if (ena) begin
            // Temperature rises with motor activity
            if (system_enabled && motor_speed > 8'd50) begin
                if (internal_temperature < 7'd100 && pwm_clk_div[11:0] == 12'd0)
                    internal_temperature <= internal_temperature + 7'd1;
            end else if (internal_temperature > 7'd25 && pwm_clk_div[11:0] == 12'd0) begin
                internal_temperature <= internal_temperature - 7'd1;
            end

            // Temperature fault detection
            temperature_fault <= (internal_temperature >= 7'd85);
        end
    end

    // =============================================================================
    // MAIN CONTROL LOGIC - SIMPLIFIED AND ROBUST
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize ALL registers to known states
            system_enabled <= 1'b0;
            motor_speed <= 8'd0;
            headlight_active <= 1'b0;
            horn_active <= 1'b0;
            indicator_active <= 1'b0;
            motor_active <= 1'b0;
            pwm_active <= 1'b0;
            pwm_duty_cycle <= 8'd0;
        end else if (ena) begin
            
            // FIXED: Power control is always evaluated
            system_enabled <= (power_on_plc | power_on_hmi);
            
            // FIXED: Only process operations when system is enabled
            if (system_enabled) begin
                case (operation_select)
                    // Power control
                    3'b000: begin
                        // System enable handled above
                    end
                    
                    // Headlight control
                    3'b001: begin
                        headlight_active <= mode_select ? headlight_hmi : headlight_plc;
                    end
                    
                    // Horn control
                    3'b010: begin
                        horn_active <= mode_select ? horn_hmi : horn_plc;
                    end
                    
                    // Right indicator control
                    3'b011: begin
                        indicator_active <= mode_select ? right_ind_hmi : right_ind_plc;
                    end
                    
                    // FIXED: Motor speed calculation - MUCH SIMPLER
                    3'b100: begin
                        motor_active <= 1'b1;
                        if (!temperature_fault) begin
                            // Simple calculation: if accel > brake, calculate speed
                            if (accelerator_value > brake_value) begin
                                motor_speed <= {4'b0000, (accelerator_value - brake_value)} << 4; // Scale by 16
                            end else begin
                                motor_speed <= 8'd0;
                            end
                        end else begin
                            // Reduce speed during overheating
                            motor_speed <= motor_speed >> 1;
                        end
                    end
                    
                    // PWM generation
                    3'b101: begin
                        if (!temperature_fault) begin
                            pwm_duty_cycle <= motor_speed;
                            pwm_active <= (motor_speed > 8'd0);
                        end else begin
                            pwm_duty_cycle <= motor_speed >> 1;
                            pwm_active <= (motor_speed > 8'd0);
                        end
                    end
                    
                    // Temperature monitoring
                    3'b110: begin
                        // Temperature handled in separate always block
                    end
                    
                    // System reset
                    3'b111: begin
                        motor_speed <= 8'd0;
                        pwm_duty_cycle <= 8'd0;
                        headlight_active <= 1'b0;
                        horn_active <= 1'b0;
                        indicator_active <= 1'b0;
                        motor_active <= 1'b0;
                        pwm_active <= 1'b0;
                    end
                    
                    default: begin
                        // Maintain current state
                    end
                endcase
            end else begin
                // FIXED: Clear all outputs when system is disabled
                motor_speed <= 8'd0;
                pwm_duty_cycle <= 8'd0;
                headlight_active <= 1'b0;
                horn_active <= 1'b0;
                indicator_active <= 1'b0;
                motor_active <= 1'b0;
                pwm_active <= 1'b0;
            end
        end
    end

    // =============================================================================
    // PWM GENERATION - SIMPLIFIED
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'd0;
        end else if (ena && system_enabled) begin
            pwm_counter <= pwm_counter + 8'd1;
        end else begin
            pwm_counter <= 8'd0;
        end
    end

    // =============================================================================
    // OUTPUT ASSIGNMENTS - CLEAN AND SIMPLE
    // =============================================================================
    
    // Status signals
    wire power_status = system_enabled;
    wire headlight_out = headlight_active & system_enabled;
    wire horn_out = horn_active & system_enabled;
    wire right_indicator = indicator_active & system_enabled;
    wire overheat_warning = temperature_fault;
    wire [1:0] status_led = {temperature_fault, system_enabled};

    // FIXED: Clean PWM generation
    wire motor_pwm = (system_enabled && pwm_active && (pwm_counter < pwm_duty_cycle));

    // Final output assignments
    assign uo_out = {
        status_led[1],      // bit 7: system enabled status
        status_led[0],      // bit 6: temperature fault
        overheat_warning,   // bit 5: overheat warning
        motor_pwm,          // bit 4: motor PWM
        right_indicator,    // bit 3: right indicator
        horn_out,           // bit 2: horn output
        headlight_out,      // bit 1: headlight output
        power_status        // bit 0: power status
    };
    
    // FIXED: Output motor speed on upper 4 bits, lower 4 bits driven to 0
    assign uio_out = {motor_speed[7:4], 4'b0000};

    // Prevent warnings for unused signals
    wire _unused = &{mode_select, motor_active, 1'b0};

endmodule
