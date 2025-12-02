`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// AES-128 Key Expansion Module - TRUE ON-THE-FLY
// 
// Calculates round keys on demand instead of pre-computing all 44 words
// Significant resource savings: Only stores current round key (128 bits)
// instead of all 11 round keys (1408 bits)
//
// Interface:
//   - start: Load new master key and reset to round 0
//   - next: Advance to next word (generates new word if needed)
//   - word_addr: Current word index (0-43)
//   - round_key: Current 32-bit key word output
//   - ready: Always ready (no pre-computation phase)
//////////////////////////////////////////////////////////////////////////////////

module aes_key_expansion_otf(
    input wire        clk,
    input wire        rst_n,
    input wire        start,
    input wire [127:0] key,
    input wire        next,
    output reg [31:0] round_key,
    output reg [5:0]  word_addr,
    output reg        ready
);

//////////////////////////////////////////////////////////////////////////////
// Internal Storage - Only current round (4 words)
//////////////////////////////////////////////////////////////////////////////
reg [31:0] w0, w1, w2, w3;  // Current 4-word window
reg [3:0]  current_round;    // Current round number (0-10)
reg [127:0] master_key;      // Store master key for regeneration if needed

//////////////////////////////////////////////////////////////////////////////
// S-box instantiation for SubWord+RotWord operation
// Original function: RotWord then SubWord
//   output = {sbox(w3[23:16]), sbox(w3[15:8]), sbox(w3[7:0]), sbox(w3[31:24])}
//////////////////////////////////////////////////////////////////////////////
wire [7:0] sb_out0, sb_out1, sb_out2, sb_out3;

aes_sbox sbox0 (.in(w3[7:0]),   .out(sb_out0));
aes_sbox sbox1 (.in(w3[15:8]),  .out(sb_out1));
aes_sbox sbox2 (.in(w3[23:16]), .out(sb_out2));
aes_sbox sbox3 (.in(w3[31:24]), .out(sb_out3));

//////////////////////////////////////////////////////////////////////////////
// Rcon values
//////////////////////////////////////////////////////////////////////////////
function [31:0] rcon;
    input [3:0] round;
    begin
        case(round)
            4'd1:  rcon = 32'h01000000;
            4'd2:  rcon = 32'h02000000;
            4'd3:  rcon = 32'h04000000;
            4'd4:  rcon = 32'h08000000;
            4'd5:  rcon = 32'h10000000;
            4'd6:  rcon = 32'h20000000;
            4'd7:  rcon = 32'h40000000;
            4'd8:  rcon = 32'h80000000;
            4'd9:  rcon = 32'h1b000000;
            4'd10: rcon = 32'h36000000;
            default: rcon = 32'h00000000;
        endcase
    end
endfunction

//////////////////////////////////////////////////////////////////////////////
// SubWord with RotWord result
// RotWord rotates: [w3[31:24], w3[23:16], w3[15:8], w3[7:0]] -> [w3[23:16], w3[15:8], w3[7:0], w3[31:24]]
// Then apply SubWord (S-box) to each byte
//////////////////////////////////////////////////////////////////////////////
wire [31:0] subword_rotword_result = {sb_out2, sb_out1, sb_out0, sb_out3};

//////////////////////////////////////////////////////////////////////////////
// Combinational logic for next round generation
//////////////////////////////////////////////////////////////////////////////
wire [31:0] temp_w0, temp_w1, temp_w2, temp_w3;

// Generate next round keys combinationally
assign temp_w0 = w0 ^ subword_rotword_result ^ rcon(current_round + 1);
assign temp_w1 = w1 ^ temp_w0;
assign temp_w2 = w2 ^ temp_w1;
assign temp_w3 = w3 ^ temp_w2;

//////////////////////////////////////////////////////////////////////////////
// Main State Machine
//////////////////////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        w0 <= 32'h0;
        w1 <= 32'h0;
        w2 <= 32'h0;
        w3 <= 32'h0;
        word_addr <= 6'd0;
        round_key <= 32'h0;
        current_round <= 4'd0;
        master_key <= 128'h0;
        ready <= 1'b0;
    end else begin
        if (start) begin
            // Load master key and initialize to round 0
            master_key <= key;
            w0 <= key[127:96];
            w1 <= key[95:64];
            w2 <= key[63:32];
            w3 <= key[31:0];
            word_addr <= 6'd0;
            round_key <= key[127:96];
            current_round <= 4'd0;
            ready <= 1'b1;
        end else if (next && ready) begin
            // Move to next word
            if (word_addr < 43) begin
                word_addr <= word_addr + 1;
                
                // Check if we need to generate next round
                if (word_addr[1:0] == 2'b11) begin
                    // Moving to next round - use pre-computed next round keys
                    w0 <= temp_w0;
                    w1 <= temp_w1;
                    w2 <= temp_w2;
                    w3 <= temp_w3;
                    round_key <= temp_w0;
                    current_round <= current_round + 1;
                end else begin
                    // Stay in same round, just output next word
                    case (word_addr[1:0])
                        2'b00: round_key <= w1;
                        2'b01: round_key <= w2;
                        2'b10: round_key <= w3;
                        2'b11: round_key <= w0; // Won't reach here due to above if
                    endcase
                end
            end
        end
    end
end

endmodule