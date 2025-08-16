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

    // CRITICAL FIX 1: uio_oe must be driven by a register to avoid synthesis issues
    reg [7:0] uio_oe_reg;
    assign uio_oe = uio_oe_reg;

    // CRITICAL FIX 2: All outputs must be driven by registers
    reg [7:0] uo_out_reg;
    reg [7:0] uio_out_reg;
    
    assign uo_out = uo_out_reg;
    assign uio_out = uio_out_reg;

    // CRITICAL FIX 3: Proper reset handling for Sky130
    // Sky130 requires very explicit reset behavior
    wire reset_active = !rst_n || !ena;  // Combine both reset conditions
    
    // Extract input signals (these are combinational)
    wire [2:0] operation_select = ui_in[2:0];
    wire power_on_plc = ui_in[3];
    wire power_on_hmi = ui_in[4];
    wire system_enabled = power_on_plc | power_on_hmi;
    wire [3:0] accelerator_in = uio_in[7:4];
    wire [3:0] brake_in = uio_in[3:0];
    
    // CRITICAL FIX 4: Use synchronous reset for Sky130 compatibility
    always @(posedge clk) begin
        if (reset_active) begin
            // EXPLICIT reset values for Sky130 - must be very clear
            uo_out_reg <= 8'b00000000;
            uio_out_reg <= 8'b00000000;
            uio_oe_reg <= 8'b11110000;  // Set I/O directions
        end else begin
            // CRITICAL FIX 5: Always provide default values to prevent X states
            uo_out_reg <= 8'b00000000;  // Default state
            uio_out_reg <= 8'b00000000;  // Default state
            uio_oe_reg <= 8'b11110000;   // Keep I/O directions stable
            
            // Logic only executes when system is enabled
            if (system_enabled) begin
                case (operation_select)
                    3'b000: begin
                        // Power mode - show power status
                        uo_out_reg <= 8'b00000001; // Set power bit
                    end
                    
                    3'b100: begin
                        // Motor calculation mode
                        if (accelerator_in > brake_in) begin
                            // Calculate motor speed: (accel - brake) * 16
                            uio_out_reg <= {accelerator_in - brake_in, 4'b0000};
                            uo_out_reg <= 8'b00000001; // Show power on
                        end else begin
                            uio_out_reg <= 8'b00000000; // No motor speed
                            uo_out_reg <= 8'b00000001; // Show power on
                        end
                    end
                    
                    3'b001: begin
                        // Additional mode for testing
                        uo_out_reg <= 8'b00000011; // Different pattern
                    end
                    
                    3'b010: begin
                        // Another test mode
                        uo_out_reg <= 8'b00000101; // Different pattern
                    end
                    
                    default: begin
                        // Default case - just show power
                        uo_out_reg <= 8'b00000001;
                    end
                endcase
            end
            // Note: if !system_enabled, we keep the default values set above
        end
    end

    // CRITICAL FIX 6: Add some unused signal handling to prevent optimization
    // Sometimes synthesis tools remove logic they think is unused
    wire unused_signals = |{ui_in[7:5], uio_in[3:0]};  // Acknowledge all inputs
    
    // Optional: Add a simple counter for debugging connectivity
    reg [7:0] debug_counter;
    always @(posedge clk) begin
        if (reset_active) begin
            debug_counter <= 8'b00000000;
        end else begin
            debug_counter <= debug_counter + 1;
        end
    end

endmodule
