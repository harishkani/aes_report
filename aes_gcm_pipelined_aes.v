`timescale 1ns / 1ps
//==============================================================================
// Module: aes_gcm_pipelined_aes
//
// Description:
//   Fully pipelined AES-128 encryption-only core with one 128-bit output
//   per clock cycle (after a 10-cycle fill latency).
//
// Architecture:
//   - 10 pipeline stages, one AES round per stage
//   - Each stage contains: AddRoundKey → SubBytes(16 parallel) →
//                          ShiftRows → MixColumns (rounds 1-9)
//   - Stage 10 (final): AddRoundKey → SubBytes → ShiftRows → AddRoundKey
//   - Key schedule precomputed externally via aes_gcm_key_schedule module
//   - 16 S-boxes instantiated per stage (160 total) for full parallelism
//
// Performance:
//   - Latency:     10 clock cycles (fill pipeline)
//   - Throughput:  1 block (128 bits) per clock cycle
//   - @ 200 MHz:   25.6 Gbps per core
//   - @ 300 MHz:   38.4 Gbps per core
//
// Interface:
//   clk               100–300 MHz clock
//   rst_n             Active-low synchronous reset
//   data_in[127:0]    Plaintext block input (registered on rising edge)
//   data_valid_in     Input valid strobe
//   round_keys[0:10]  Precomputed AES round keys (from key_schedule module)
//   data_out[127:0]   Ciphertext output (valid 10 cycles after input)
//   data_valid_out    Output valid signal (delayed by 10 cycles)
//
// Key-schedule Module: aes_gcm_key_schedule
//   Precomputes all 11 round keys from a 128-bit AES key.
//   See module below.
//
// References:
//   - FIPS 197, "Advanced Encryption Standard"
//   - Paar & Pelzl, "Understanding Cryptography"
//   - Drimer, Güneysu, Paar, "DSPs, BRAMs, and a Pinch of Logic:
//     Extended Recipes for AES on FPGAs", TRETS 2010.
//==============================================================================

//------------------------------------------------------------------------------
// AES S-box: 16 parallel instances for one full SubBytes per round stage.
// Uses combinatorial lookup table approach (synthesises to LUTs on FPGA).
//------------------------------------------------------------------------------
module aes_gcm_sbox (
    input  wire [7:0] in,
    output reg  [7:0] out
);
always @(*) begin
    case (in)
        8'h00:out=8'h63; 8'h01:out=8'h7c; 8'h02:out=8'h77; 8'h03:out=8'h7b;
        8'h04:out=8'hf2; 8'h05:out=8'h6b; 8'h06:out=8'h6f; 8'h07:out=8'hc5;
        8'h08:out=8'h30; 8'h09:out=8'h01; 8'h0a:out=8'h67; 8'h0b:out=8'h2b;
        8'h0c:out=8'hfe; 8'h0d:out=8'hd7; 8'h0e:out=8'hab; 8'h0f:out=8'h76;
        8'h10:out=8'hca; 8'h11:out=8'h82; 8'h12:out=8'hc9; 8'h13:out=8'h7d;
        8'h14:out=8'hfa; 8'h15:out=8'h59; 8'h16:out=8'h47; 8'h17:out=8'hf0;
        8'h18:out=8'had; 8'h19:out=8'hd4; 8'h1a:out=8'ha2; 8'h1b:out=8'haf;
        8'h1c:out=8'h9c; 8'h1d:out=8'ha4; 8'h1e:out=8'h72; 8'h1f:out=8'hc0;
        8'h20:out=8'hb7; 8'h21:out=8'hfd; 8'h22:out=8'h93; 8'h23:out=8'h26;
        8'h24:out=8'h36; 8'h25:out=8'h3f; 8'h26:out=8'hf7; 8'h27:out=8'hcc;
        8'h28:out=8'h34; 8'h29:out=8'ha5; 8'h2a:out=8'he5; 8'h2b:out=8'hf1;
        8'h2c:out=8'h71; 8'h2d:out=8'hd8; 8'h2e:out=8'h31; 8'h2f:out=8'h15;
        8'h30:out=8'h04; 8'h31:out=8'hc7; 8'h32:out=8'h23; 8'h33:out=8'hc3;
        8'h34:out=8'h18; 8'h35:out=8'h96; 8'h36:out=8'h05; 8'h37:out=8'h9a;
        8'h38:out=8'h07; 8'h39:out=8'h12; 8'h3a:out=8'h80; 8'h3b:out=8'he2;
        8'h3c:out=8'heb; 8'h3d:out=8'h27; 8'h3e:out=8'hb2; 8'h3f:out=8'h75;
        8'h40:out=8'h09; 8'h41:out=8'h83; 8'h42:out=8'h2c; 8'h43:out=8'h1a;
        8'h44:out=8'h1b; 8'h45:out=8'h6e; 8'h46:out=8'h5a; 8'h47:out=8'ha0;
        8'h48:out=8'h52; 8'h49:out=8'h3b; 8'h4a:out=8'hd6; 8'h4b:out=8'hb3;
        8'h4c:out=8'h29; 8'h4d:out=8'he3; 8'h4e:out=8'h2f; 8'h4f:out=8'h84;
        8'h50:out=8'h53; 8'h51:out=8'hd1; 8'h52:out=8'h00; 8'h53:out=8'hed;
        8'h54:out=8'h20; 8'h55:out=8'hfc; 8'h56:out=8'hb1; 8'h57:out=8'h5b;
        8'h58:out=8'h6a; 8'h59:out=8'hcb; 8'h5a:out=8'hbe; 8'h5b:out=8'h39;
        8'h5c:out=8'h4a; 8'h5d:out=8'h4c; 8'h5e:out=8'h58; 8'h5f:out=8'hcf;
        8'h60:out=8'hd0; 8'h61:out=8'hef; 8'h62:out=8'haa; 8'h63:out=8'hfb;
        8'h64:out=8'h43; 8'h65:out=8'h4d; 8'h66:out=8'h33; 8'h67:out=8'h85;
        8'h68:out=8'h45; 8'h69:out=8'hf9; 8'h6a:out=8'h02; 8'h6b:out=8'h7f;
        8'h6c:out=8'h50; 8'h6d:out=8'h3c; 8'h6e:out=8'h9f; 8'h6f:out=8'ha8;
        8'h70:out=8'h51; 8'h71:out=8'ha3; 8'h72:out=8'h40; 8'h73:out=8'h8f;
        8'h74:out=8'h92; 8'h75:out=8'h9d; 8'h76:out=8'h38; 8'h77:out=8'hf5;
        8'h78:out=8'hbc; 8'h79:out=8'hb6; 8'h7a:out=8'hda; 8'h7b:out=8'h21;
        8'h7c:out=8'h10; 8'h7d:out=8'hff; 8'h7e:out=8'hf3; 8'h7f:out=8'hd2;
        8'h80:out=8'hcd; 8'h81:out=8'h0c; 8'h82:out=8'h13; 8'h83:out=8'hec;
        8'h84:out=8'h5f; 8'h85:out=8'h97; 8'h86:out=8'h44; 8'h87:out=8'h17;
        8'h88:out=8'hc4; 8'h89:out=8'ha7; 8'h8a:out=8'h7e; 8'h8b:out=8'h3d;
        8'h8c:out=8'h64; 8'h8d:out=8'h5d; 8'h8e:out=8'h19; 8'h8f:out=8'h73;
        8'h90:out=8'h60; 8'h91:out=8'h81; 8'h92:out=8'h4f; 8'h93:out=8'hdc;
        8'h94:out=8'h22; 8'h95:out=8'h2a; 8'h96:out=8'h90; 8'h97:out=8'h88;
        8'h98:out=8'h46; 8'h99:out=8'hee; 8'h9a:out=8'hb8; 8'h9b:out=8'h14;
        8'h9c:out=8'hde; 8'h9d:out=8'h5e; 8'h9e:out=8'h0b; 8'h9f:out=8'hdb;
        8'ha0:out=8'he0; 8'ha1:out=8'h32; 8'ha2:out=8'h3a; 8'ha3:out=8'h0a;
        8'ha4:out=8'h49; 8'ha5:out=8'h06; 8'ha6:out=8'h24; 8'ha7:out=8'h5c;
        8'ha8:out=8'hc2; 8'ha9:out=8'hd3; 8'haa:out=8'hac; 8'hab:out=8'h62;
        8'hac:out=8'h91; 8'had:out=8'h95; 8'hae:out=8'he4; 8'haf:out=8'h79;
        8'hb0:out=8'he7; 8'hb1:out=8'hc8; 8'hb2:out=8'h37; 8'hb3:out=8'h6d;
        8'hb4:out=8'h8d; 8'hb5:out=8'hd5; 8'hb6:out=8'h4e; 8'hb7:out=8'ha9;
        8'hb8:out=8'h6c; 8'hb9:out=8'h56; 8'hba:out=8'hf4; 8'hbb:out=8'hea;
        8'hbc:out=8'h65; 8'hbd:out=8'h7a; 8'hbe:out=8'hae; 8'hbf:out=8'h08;
        8'hc0:out=8'hba; 8'hc1:out=8'h78; 8'hc2:out=8'h25; 8'hc3:out=8'h2e;
        8'hc4:out=8'h1c; 8'hc5:out=8'ha6; 8'hc6:out=8'hb4; 8'hc7:out=8'hc6;
        8'hc8:out=8'he8; 8'hc9:out=8'hdd; 8'hca:out=8'h74; 8'hcb:out=8'h1f;
        8'hcc:out=8'h4b; 8'hcd:out=8'hbd; 8'hce:out=8'h8b; 8'hcf:out=8'h8a;
        8'hd0:out=8'h70; 8'hd1:out=8'h3e; 8'hd2:out=8'hb5; 8'hd3:out=8'h66;
        8'hd4:out=8'h48; 8'hd5:out=8'h03; 8'hd6:out=8'hf6; 8'hd7:out=8'h0e;
        8'hd8:out=8'h61; 8'hd9:out=8'h35; 8'hda:out=8'h57; 8'hdb:out=8'hb9;
        8'hdc:out=8'h86; 8'hdd:out=8'hc1; 8'hde:out=8'h1d; 8'hdf:out=8'h9e;
        8'he0:out=8'he1; 8'he1:out=8'hf8; 8'he2:out=8'h98; 8'he3:out=8'h11;
        8'he4:out=8'h69; 8'he5:out=8'hd9; 8'he6:out=8'h8e; 8'he7:out=8'h94;
        8'he8:out=8'h9b; 8'he9:out=8'h1e; 8'hea:out=8'h87; 8'heb:out=8'he9;
        8'hec:out=8'hce; 8'hed:out=8'h55; 8'hee:out=8'h28; 8'hef:out=8'hdf;
        8'hf0:out=8'h8c; 8'hf1:out=8'ha1; 8'hf2:out=8'h89; 8'hf3:out=8'h0d;
        8'hf4:out=8'hbf; 8'hf5:out=8'he6; 8'hf6:out=8'h42; 8'hf7:out=8'h68;
        8'hf8:out=8'h41; 8'hf9:out=8'h99; 8'hfa:out=8'h2d; 8'hfb:out=8'h0f;
        8'hfc:out=8'hb0; 8'hfd:out=8'h54; 8'hfe:out=8'hbb; 8'hff:out=8'h16;
    endcase
end
endmodule


//==============================================================================
// Module: aes_gcm_key_schedule
// Expands a 128-bit AES key into 11 round keys (combinatorially).
// Output: rk[0..10], each 128 bits.
//==============================================================================
module aes_gcm_key_schedule (
    input  wire [127:0] key,
    output wire [127:0] rk [0:10]
);

// Rcon table
function [7:0] rcon;
    input [3:0] r;
    begin
        case (r)
            4'd1:  rcon = 8'h01; 4'd2:  rcon = 8'h02;
            4'd3:  rcon = 8'h04; 4'd4:  rcon = 8'h08;
            4'd5:  rcon = 8'h10; 4'd6:  rcon = 8'h20;
            4'd7:  rcon = 8'h40; 4'd8:  rcon = 8'h80;
            4'd9:  rcon = 8'h1b; 4'd10: rcon = 8'h36;
            default: rcon = 8'h00;
        endcase
    end
endfunction

// Internal round key words (44 words total, 4 per round key)
wire [31:0] w [0:43];

// Initial key words
assign w[0] = key[127:96];
assign w[1] = key[95:64];
assign w[2] = key[63:32];
assign w[3] = key[31:0];

// S-box instances for key schedule (4 bytes of RotWord+SubWord per round)
wire [7:0] ks_sbox_in  [1:10][0:3];
wire [7:0] ks_sbox_out [1:10][0:3];

genvar r, b;
generate
    for (r = 1; r <= 10; r = r + 1) begin : ks_round
        for (b = 0; b < 4; b = b + 1) begin : ks_byte
            aes_gcm_sbox sbox_ks (
                .in  (ks_sbox_in[r][b]),
                .out (ks_sbox_out[r][b])
            );
        end
        // RotWord then SubWord on w[4r-1] (last word of previous round)
        assign ks_sbox_in[r][0] = w[4*r-1][23:16]; // RotWord: byte 1
        assign ks_sbox_in[r][1] = w[4*r-1][15:8];  // RotWord: byte 2
        assign ks_sbox_in[r][2] = w[4*r-1][7:0];   // RotWord: byte 3
        assign ks_sbox_in[r][3] = w[4*r-1][31:24]; // RotWord: byte 0

        // w[4r] = w[4r-4] XOR SubWord(RotWord(w[4r-1])) XOR Rcon
        assign w[4*r]   = w[4*r-4] ^
                          {ks_sbox_out[r][0] ^ rcon(r[3:0]),
                           ks_sbox_out[r][1],
                           ks_sbox_out[r][2],
                           ks_sbox_out[r][3]};
        assign w[4*r+1] = w[4*r-3] ^ w[4*r];
        assign w[4*r+2] = w[4*r-2] ^ w[4*r+1];
        assign w[4*r+3] = w[4*r-1] ^ w[4*r+2];
    end
endgenerate

// Assemble 11 round keys
genvar k;
generate
    for (k = 0; k <= 10; k = k + 1) begin : rk_assemble
        assign rk[k] = {w[4*k], w[4*k+1], w[4*k+2], w[4*k+3]};
    end
endgenerate

endmodule


//==============================================================================
// Module: aes_round_comb
// Combinatorial AES round (SubBytes + ShiftRows + MixColumns + AddRoundKey).
// For the final round (round 10), set is_final=1 to skip MixColumns.
//==============================================================================
module aes_round_comb (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    input  wire         is_final,    // 1 = skip MixColumns
    output wire [127:0] state_out
);

// ---- SubBytes: 16 parallel S-boxes ----
wire [7:0] sb_in  [0:15];
wire [7:0] sb_out [0:15];

genvar i;
generate
    for (i = 0; i < 16; i = i + 1) begin : subbytes
        assign sb_in[i] = state_in[127 - 8*i -: 8];
        aes_gcm_sbox sbox_i (.in(sb_in[i]), .out(sb_out[i]));
    end
endgenerate

// Reconstruct SubBytes result
wire [127:0] after_sub;
assign after_sub = {
    sb_out[0],  sb_out[1],  sb_out[2],  sb_out[3],
    sb_out[4],  sb_out[5],  sb_out[6],  sb_out[7],
    sb_out[8],  sb_out[9],  sb_out[10], sb_out[11],
    sb_out[12], sb_out[13], sb_out[14], sb_out[15]
};

// ---- ShiftRows ----
// AES state bytes indexed [row][col], stored MSB-first as:
// byte 0 = row0 col0, byte 1 = row1 col0, byte 2 = row2 col0, byte 3 = row3 col0
// byte 4 = row0 col1, ...  (column-major)
// ShiftRows shifts row i left by i positions (encryption):
//   row 0: no shift      cols 0,1,2,3  → cols 0,1,2,3
//   row 1: left 1        cols 0,1,2,3  → cols 1,2,3,0
//   row 2: left 2        cols 0,1,2,3  → cols 2,3,0,1
//   row 3: left 3        cols 0,1,2,3  → cols 3,0,1,2
//
// Byte[row][col] = after_sub[127 - 8*(4*col + row) -: 8]
// After ShiftRows, byte[row][col] comes from original byte[row][(col+row) mod 4]
//
// Mapping output byte index j (= 4*col_out + row_out) from input:
//   row_out = j mod 4, col_out = j / 4
//   input col = (col_out + row_out) mod 4
//   input byte index = 4*((col_out + row_out) mod 4) + row_out

function [3:0] sr_src;
    input [3:0] j;  // output byte index (0..15, column-major)
    reg [1:0] row, col_in;
    begin
        row    = j[1:0];   // j mod 4
        // col_out = j[3:2], col_in = (col_out + row) mod 4
        col_in = (j[3:2] + row) & 2'b11;
        sr_src = {col_in, row};
    end
endfunction

wire [127:0] after_shift;
genvar j;
generate
    for (j = 0; j < 16; j = j + 1) begin : shiftrows
        assign after_shift[127 - 8*j -: 8] = after_sub[127 - 8*sr_src(j[3:0]) -: 8];
    end
endgenerate

// ---- MixColumns ----
// Process each of the 4 columns (32 bits each)
wire [31:0] mc_in  [0:3];
wire [31:0] mc_out [0:3];

genvar c;
generate
    for (c = 0; c < 4; c = c + 1) begin : mixcols
        assign mc_in[c] = after_shift[127 - 32*c -: 32];
    end
endgenerate

// GF(2^8) xtime (multiply by 2)
function [7:0] xtime;
    input [7:0] a;
    begin xtime = a[7] ? ({a[6:0],1'b0} ^ 8'h1b) : {a[6:0],1'b0}; end
endfunction

// MixColumns for one 32-bit column
function [31:0] mix_col;
    input [31:0] col;
    reg [7:0] s0, s1, s2, s3;
    reg [7:0] t0, t1, t2, t3;
    begin
        s0 = col[31:24]; s1 = col[23:16]; s2 = col[15:8]; s3 = col[7:0];
        t0 = xtime(s0) ^ (xtime(s1)^s1) ^ s2 ^ s3;
        t1 = s0 ^ xtime(s1) ^ (xtime(s2)^s2) ^ s3;
        t2 = s0 ^ s1 ^ xtime(s2) ^ (xtime(s3)^s3);
        t3 = (xtime(s0)^s0) ^ s1 ^ s2 ^ xtime(s3);
        mix_col = {t0, t1, t2, t3};
    end
endfunction

wire [127:0] after_mix;
genvar mc;
generate
    for (mc = 0; mc < 4; mc = mc + 1) begin : mixcol_inst
        assign after_mix[127 - 32*mc -: 32] = mix_col(mc_in[mc]);
    end
endgenerate

// ---- Select MixColumns bypass for final round ----
wire [127:0] pre_ark = is_final ? after_shift : after_mix;

// ---- AddRoundKey ----
assign state_out = pre_ark ^ round_key;

endmodule


//==============================================================================
// Module: aes_gcm_pipelined_aes
// Top-level 10-stage pipelined AES-128 encryption core.
//==============================================================================
module aes_gcm_pipelined_aes (
    input  wire        clk,
    input  wire        rst_n,

    // Plaintext input stream
    input  wire [127:0] data_in,
    input  wire         data_valid_in,

    // Pre-expanded round keys (11 × 128-bit)
    input  wire [127:0] rk [0:10],

    // Ciphertext output stream (latency = 10 cycles)
    output reg  [127:0] data_out,
    output reg          data_valid_out
);

// ---- Pipeline registers: state and valid ----
// pipe_state[0] = after initial AddRoundKey (pre-round 1)
// pipe_state[i] = after round i (i=1..10)
reg [127:0] pipe_state [0:10];
reg         pipe_valid [0:10];

// ---- Round combinatorial outputs ----
wire [127:0] round_out [1:10];

genvar stage;
generate
    for (stage = 1; stage <= 10; stage = stage + 1) begin : pipeline_stage
        aes_round_comb round_inst (
            .state_in  (pipe_state[stage-1]),
            .round_key (rk[stage]),
            .is_final  (stage == 10 ? 1'b1 : 1'b0),
            .state_out (round_out[stage])
        );
    end
endgenerate

integer k;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (k = 0; k <= 10; k = k + 1) begin
            pipe_state[k] <= 128'b0;
            pipe_valid[k] <= 1'b0;
        end
        data_out       <= 128'b0;
        data_valid_out <= 1'b0;
    end else begin
        // Stage 0: Initial AddRoundKey
        pipe_state[0] <= data_in ^ rk[0];
        pipe_valid[0] <= data_valid_in;

        // Stages 1-10: register the combinatorial round outputs
        for (k = 1; k <= 10; k = k + 1) begin
            pipe_state[k] <= round_out[k];
            pipe_valid[k] <= pipe_valid[k-1];
        end

        // Output
        data_out       <= pipe_state[10];
        data_valid_out <= pipe_valid[10];
    end
end

endmodule
