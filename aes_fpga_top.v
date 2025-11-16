`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// AES-128 FPGA Top Module with 7-Segment Display
//
// This module integrates the AES core with FPGA I/O for verification
//
// Hardware Requirements:
//   - 8x 7-segment displays (for showing 8 hex digits at a time)
//   - 4 push buttons (btnC: start, btnU: enc/dec, btnL: prev group, btnR: next group)
//   - 16 switches (for selecting test vectors)
//   - 16 LEDs (for status indication)
//   - 100MHz clock
//
// Display Modes:
//   - Shows AES output in groups of 8 hex digits (32 digits total = 128 bits)
//   - Use btnL/btnR to cycle through 4 groups
//   - LEDs show current state and status
//
// Test Vectors (selected by switches):
//   sw[3:0] = Test vector selection (0-15)
//////////////////////////////////////////////////////////////////////////////////
module aes_fpga_top(
    input wire clk,              // 100MHz system clock
    input wire rst_n,            // Active-low reset (CPU_RESET button)

    // Push buttons
    input wire btnC,             // Center: Start AES operation
    input wire btnU,             // Up: Toggle encrypt/decrypt
    input wire btnL,             // Left: Previous display group
    input wire btnR,             // Right: Next display group

    // Switches
    input wire [15:0] sw,        // Test vector selection

    // 7-segment display
    output wire [7:0] an,        // Anode control
    output wire [6:0] seg,       // Segment control

    // LEDs
    output wire [15:0] led       // Status LEDs
);

//////////////////////////////////////////////////////////////////////////////
// Button Debouncing and Edge Detection
//////////////////////////////////////////////////////////////////////////////
reg [19:0] btn_counter;
reg [3:0] btn_stable;
reg [3:0] btn_prev;
wire btn_start, btn_enc_dec, btn_prev_group, btn_next_group;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        btn_counter <= 0;
        btn_stable <= 4'b0000;
        btn_prev <= 4'b0000;
    end else begin
        btn_counter <= btn_counter + 1;
        if (btn_counter == 0) begin
            btn_stable <= {btnR, btnL, btnU, btnC};
        end
        btn_prev <= btn_stable;
    end
end

// Rising edge detection
assign btn_start = btn_stable[0] & ~btn_prev[0];
assign btn_enc_dec = btn_stable[1] & ~btn_prev[1];
assign btn_prev_group = btn_stable[2] & ~btn_prev[2];
assign btn_next_group = btn_stable[3] & ~btn_prev[3];

//////////////////////////////////////////////////////////////////////////////
// Test Vector Selection
//////////////////////////////////////////////////////////////////////////////
reg [127:0] plaintext;
reg [127:0] key;
reg enc_dec_mode;
reg [2:0] display_group;

// NIST test vectors and custom patterns with encryption/decryption support
always @(*) begin
    case (sw[3:0])
        // NIST FIPS 197 Appendix C.1
        4'd0: begin
            key = 128'h000102030405060708090a0b0c0d0e0f;
            if (enc_dec_mode) begin
                // Encryption: plaintext → ciphertext
                plaintext = 128'h00112233445566778899aabbccddeeff;
            end else begin
                // Decryption: ciphertext → plaintext
                plaintext = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
            end
        end

        // NIST FIPS 197 Appendix B
        4'd1: begin
            key = 128'h2b7e151628aed2a6abf7158809cf4f3c;
            if (enc_dec_mode) begin
                plaintext = 128'h3243f6a8885a308d313198a2e0370734;
            end else begin
                plaintext = 128'h3925841d02dc09fbdc118597196a0b32;
            end
        end

        // All zeros
        4'd2: begin
            key = 128'h00000000000000000000000000000000;
            if (enc_dec_mode) begin
                plaintext = 128'h00000000000000000000000000000000;
            end else begin
                plaintext = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
            end
        end

        // All ones
        4'd3: begin
            key = 128'hffffffffffffffffffffffffffffffff;
            if (enc_dec_mode) begin
                plaintext = 128'hffffffffffffffffffffffffffffffff;
            end else begin
                plaintext = 128'hbcbf217cb280cf30b2517052193ab979;
            end
        end

        // Alternating pattern
        4'd4: begin
            plaintext = 128'haaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
            key       = 128'h55555555555555555555555555555555;
        end

        // Custom pattern 1
        4'd5: begin
            plaintext = 128'h0123456789abcdef0123456789abcdef;
            key       = 128'hfedcba9876543210fedcba9876543210;
        end


        // Sequential
        4'd6: begin
            plaintext = 128'h000102030405060708090a0b0c0d0e0f;
            key       = 128'h101112131415161718191a1b1c1d1e1f;
        end

        // Custom patterns 8-15
        default: begin
            plaintext = {sw[15:0], sw[15:0], sw[15:0], sw[15:0], sw[15:0], sw[15:0], sw[15:0], sw[15:0]};
            key       = {~sw[15:0], ~sw[15:0], ~sw[15:0], ~sw[15:0], ~sw[15:0], ~sw[15:0], ~sw[15:0], ~sw[15:0]};
        end
    endcase
end

// Toggle encrypt/decrypt mode
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        enc_dec_mode <= 1'b1; // Default to encryption
    else if (btn_enc_dec)
        enc_dec_mode <= ~enc_dec_mode;
end

// Display group selection (0-3, cycling through 32 hex digits in groups of 8)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        display_group <= 3'd0;
    else if (btn_next_group)
        display_group <= (display_group == 3'd3) ? 3'd0 : display_group + 1;
    else if (btn_prev_group)
        display_group <= (display_group == 3'd0) ? 3'd3 : display_group - 1;
end

//////////////////////////////////////////////////////////////////////////////
// AES Core Instantiation
//////////////////////////////////////////////////////////////////////////////
reg aes_start;
wire aes_ready;
wire [127:0] aes_output;

aes_core_fixed aes_inst (
    .clk(clk),
    .rst_n(rst_n),
    .start(aes_start),
    .enc_dec(enc_dec_mode),
    .data_in(plaintext),
    .key_in(key),
    .data_out(aes_output),
    .ready(aes_ready)
);

// Start pulse generation
reg start_prev;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        aes_start <= 0;
        start_prev <= 0;
    end else begin
        start_prev <= btn_start;
        aes_start <= btn_start & ~start_prev;
    end
end

//////////////////////////////////////////////////////////////////////////////
// 7-Segment Display Controller
//////////////////////////////////////////////////////////////////////////////
seven_seg_controller seg_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .data(aes_output),
    .digit_sel(display_group),
    .an(an),
    .seg(seg)
);

//////////////////////////////////////////////////////////////////////////////
// LED Status Indicators
//////////////////////////////////////////////////////////////////////////////
assign led[15] = aes_ready;           // Ready indicator
assign led[14] = ~aes_ready;          // Busy indicator
assign led[13] = enc_dec_mode;        // Encrypt/Decrypt mode
assign led[12] = ~enc_dec_mode;
assign led[11:10] = display_group[1:0]; // Current display group
assign led[9:6] = sw[3:0];            // Selected test vector
assign led[5:0] = 6'b0;               // Unused

endmodule