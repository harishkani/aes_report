`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 7-Segment Display Controller with Multiplexing
// Supports 8 digits to display 128-bit data (32 hex digits shown in groups)
// Refresh rate: ~1kHz per digit (no visible flicker)
//////////////////////////////////////////////////////////////////////////////////

module seven_seg_controller(
    input wire clk,              // System clock (e.g., 100MHz)
    input wire rst_n,            // Active-low reset
    input wire [127:0] data,     // 128-bit data to display (32 hex digits)
    input wire [2:0] digit_sel,  // Which group of 8 digits to show (0-3)
    output reg [7:0] an,         // Anode control (active-low, one-hot)
    output reg [6:0] seg         // Segment control (active-low) {g,f,e,d,c,b,a}
);

// Clock divider for display refresh (~1kHz per digit, 8kHz total refresh)
reg [16:0] refresh_counter;
wire [2:0] digit_index;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        refresh_counter <= 0;
    else
        refresh_counter <= refresh_counter + 1;
end

// Use top 3 bits of counter to select which digit to display
assign digit_index = refresh_counter[16:14];

// Select 8 digits from the 32 hex digits based on digit_sel
wire [31:0] display_data;
assign display_data = (digit_sel == 3'd0) ? data[127:96] :   // Bytes 0-3
                      (digit_sel == 3'd1) ? data[95:64]  :   // Bytes 4-7
                      (digit_sel == 3'd2) ? data[63:32]  :   // Bytes 8-11
                                           data[31:0];       // Bytes 12-15

// Extract current hex digit (4 bits)
wire [3:0] current_digit;
assign current_digit = (digit_index == 3'd0) ? display_data[31:28] :
                       (digit_index == 3'd1) ? display_data[27:24] :
                       (digit_index == 3'd2) ? display_data[23:20] :
                       (digit_index == 3'd3) ? display_data[19:16] :
                       (digit_index == 3'd4) ? display_data[15:12] :
                       (digit_index == 3'd5) ? display_data[11:8]  :
                       (digit_index == 3'd6) ? display_data[7:4]   :
                                              display_data[3:0];

// Anode control (active-low, one-hot encoding)
// digit_index 0 = leftmost display (MSB), digit_index 7 = rightmost (LSB)
always @(*) begin
    case (digit_index)
        3'd0: an = 8'b01111111;  // Leftmost display (MSB)
        3'd1: an = 8'b10111111;
        3'd2: an = 8'b11011111;
        3'd3: an = 8'b11101111;
        3'd4: an = 8'b11110111;
        3'd5: an = 8'b11111011;
        3'd6: an = 8'b11111101;
        3'd7: an = 8'b11111110;  // Rightmost display (LSB)
        default: an = 8'b11111111;
    endcase
end

// 7-segment decoder (hex to segments, active-low)
// Segment mapping: {g,f,e,d,c,b,a}
//      a
//     ---
//  f |   | b
//     -g-
//  e |   | c
//     ---
//      d
always @(*) begin
    case (current_digit)
        4'h0: seg = 7'b1000000; // 0
        4'h1: seg = 7'b1111001; // 1
        4'h2: seg = 7'b0100100; // 2
        4'h3: seg = 7'b0110000; // 3
        4'h4: seg = 7'b0011001; // 4
        4'h5: seg = 7'b0010010; // 5
        4'h6: seg = 7'b0000010; // 6
        4'h7: seg = 7'b1111000; // 7
        4'h8: seg = 7'b0000000; // 8
        4'h9: seg = 7'b0010000; // 9
        4'hA: seg = 7'b0001000; // A
        4'hB: seg = 7'b0000011; // b
        4'hC: seg = 7'b1000110; // C
        4'hD: seg = 7'b0100001; // d
        4'hE: seg = 7'b0000110; // E
        4'hF: seg = 7'b0001110; // F
        default: seg = 7'b1111111; // blank
    endcase
end

endmodule