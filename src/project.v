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

    // CRITICAL FIX: Set uio_oe immediately - no logic
    assign uio_oe = 8'b11110000;  // uio[7:4] as outputs, uio[3:0] as inputs

    // MINIMAL APPROACH: Single register for all state
    reg [7:0] main_output_reg;
    reg [7:0] motor_speed_reg;
    
    // Extract input signals as wires (OUTSIDE always block)
    wire [2:0] operation_select = ui_in[2:0];
    wire power_on_plc = ui_in[3];
    wire power_on_hmi = ui_in[4];
    wire system_enabled = power_on_plc | power_on_hmi;
    wire [3:0] accelerator_in = uio_in[7:4];
    wire [3:0] brake_in = uio_in[3:0];
    
    // CRITICAL FIX: Use ONLY ena and rst_n - no complex reset logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Simple reset
            main_output_reg <= 8'b00000000;
            motor_speed_reg <= 8'b00000000;
        end else if (ena) begin  // CRITICAL: Use ena directly
            
            // MINIMAL LOGIC: Direct response to inputs
            if (system_enabled) begin
                case (operation_select)
                    3'b000: begin
                        // Power mode - just show power status
                        main_output_reg <= 8'b00000001; // Power bit on
                    end
                    
                    3'b100: begin
                        // Motor calculation mode
                        // Simple motor speed calculation
                        if (accelerator_in > brake_in) begin
                            motor_speed_reg <= {accelerator_in - brake_in, 4'b0000}; // *16
                            main_output_reg <= 8'b00000001; // Show power on
                        end else begin
                            motor_speed_reg <= 8'b00000000;
                            main_output_reg <= 8'b00000001; // Show power on
                        end
                    end
                    
                    default: begin
                        // All other modes - just show power
                        main_output_reg <= 8'b00000001;
                    end
                endcase
            end else begin
                // Power off
                main_output_reg <= 8'b00000000;
                motor_speed_reg <= 8'b00000000;
            end
        end
    end

    // DIRECT OUTPUT ASSIGNMENT - NO COMPLEX LOGIC
    assign uo_out = main_output_reg;
    assign uio_out = motor_speed_reg;

endmodule
