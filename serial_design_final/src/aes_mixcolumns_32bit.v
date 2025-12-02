`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: aes_mixcolumns_optimized
// Description: Optimized MixColumns using decomposition matrix method
//              This is a DROP-IN REPLACEMENT for aes_mixcolumns_32bit.v
//
// Key Innovation: InvMixColumns = MixColumns Ã- Decomposition Matrix
//                 Allows resource sharing between encryption and decryption
//
// Expected Benefits:
//   - Area reduction: ~10.4%
//   - Delay reduction: ~9.1%
//   - Same functionality as original module
//
// Interface: IDENTICAL to aes_mixcolumns_32bit.v
//   - Input:  32-bit column (4 bytes)
//   - Output: 32-bit transformed column
//   - Control: enc_dec (1=encrypt, 0=decrypt)
//////////////////////////////////////////////////////////////////////////////////

module aes_mixcolumns_32bit(
    input  [31:0] data_in,      // One column: [byte0, byte1, byte2, byte3]
    input         enc_dec,       // 1 = encryption, 0 = decryption
    output [31:0] data_out       // Transformed column
);

// ============================================================================
// Extract input bytes (MSB first: byte 0 at [31:24])
// ============================================================================
wire [7:0] a0 = data_in[31:24];  // Byte 0 (row 0)
wire [7:0] a1 = data_in[23:16];  // Byte 1 (row 1)
wire [7:0] a2 = data_in[15:8];   // Byte 2 (row 2)
wire [7:0] a3 = data_in[7:0];    // Byte 3 (row 3)

// ============================================================================
// GF(2^8) Multiplication Functions
// Irreducible polynomial: m(x) = x^8 + x^4 + x^3 + x + 1 (0x11B)
// ============================================================================

// Multiply by 2 in GF(2^8): "xtime" operation
// If MSB=1, shift left and XOR with 0x1B, else just shift left
function automatic [7:0] gf_mult2;
    input [7:0] x;
    reg [7:0] temp;
    begin
        temp = {x[6:0], 1'b0};  // Left shift
        gf_mult2 = x[7] ? (temp ^ 8'h1b) : temp;
    end
endfunction

// Multiply by 3: (x Ã- 2) âŠ• x
function automatic [7:0] gf_mult3;
    input [7:0] x;
    begin
        gf_mult3 = gf_mult2(x) ^ x;
    end
endfunction

// Multiply by 4: (x Ã- 2) Ã- 2
function automatic [7:0] gf_mult4;
    input [7:0] x;
    begin
        gf_mult4 = gf_mult2(gf_mult2(x));
    end
endfunction

// Multiply by 5: (x Ã- 4) âŠ• x
function automatic [7:0] gf_mult5;
    input [7:0] x;
    begin
        gf_mult5 = gf_mult4(x) ^ x;
    end
endfunction

// ============================================================================
// DECOMPOSITION MATRIX (For decryption pre-processing)
// ============================================================================
// Key insight from IEEE paper (CORRECTED):
//   InvMixColumns Matrix = MixColumns Matrix Ã- Decomposition Matrix
//   Decomposition = InvMixÂ² (InvMixColumns squared)
//
// Instead of computing InvMixColumns directly (which needs mult9, mult11, 
// mult13, mult14), we:
//   1. Apply decomposition matrix (needs only mult4, mult5)
//   2. Apply the SAME MixColumns matrix used for encryption
//
// CORRECT Decomposition Matrix (verified mathematically):
//   [05 00 04 00]
//   [00 05 00 04]
//   [04 00 05 00]
//   [00 04 00 05]
//
// Note: Paper's equation (5) had an error. This is the mathematically correct version.
// ============================================================================

// Pre-compute GF multiplications to avoid redundancy
wire [7:0] a0_x4 = gf_mult4(a0);
wire [7:0] a1_x4 = gf_mult4(a1);
wire [7:0] a2_x4 = gf_mult4(a2);
wire [7:0] a3_x4 = gf_mult4(a3);
wire [7:0] a0_x5 = gf_mult5(a0);
wire [7:0] a1_x5 = gf_mult5(a1);
wire [7:0] a2_x5 = gf_mult5(a2);
wire [7:0] a3_x5 = gf_mult5(a3);

wire [7:0] d0 = a0_x5 ^ a2_x4;  // 05Â·a0 âŠ• 04Â·a2
wire [7:0] d1 = a1_x5 ^ a3_x4;  // 05Â·a1 âŠ• 04Â·a3
wire [7:0] d2 = a0_x4 ^ a2_x5;  // 04Â·a0 âŠ• 05Â·a2
wire [7:0] d3 = a1_x4 ^ a3_x5;  // 04Â·a1 âŠ• 05Â·a3

// ============================================================================
// MUX: Select input to the shared MixColumns circuit
// ============================================================================
// For encryption: Use original input (a0, a1, a2, a3)
// For decryption: Use decomposition result (d0, d1, d2, d3)

wire [7:0] m0 = enc_dec ? a0 : d0;
wire [7:0] m1 = enc_dec ? a1 : d1;
wire [7:0] m2 = enc_dec ? a2 : d2;
wire [7:0] m3 = enc_dec ? a3 : d3;

// ============================================================================
// SHARED MIXCOLUMNS MATRIX (Used for BOTH encryption and decryption)
// ============================================================================
// Standard MixColumns matrix:
//   [02 03 01 01]
//   [01 02 03 01]
//   [01 01 02 03]
//   [03 01 01 02]
//
// Output column c = Matrix Ã- input column m

// Pre-compute all GF multiplications for clarity and potential synthesis optimization
wire [7:0] m0_x2 = gf_mult2(m0);
wire [7:0] m1_x2 = gf_mult2(m1);
wire [7:0] m2_x2 = gf_mult2(m2);
wire [7:0] m3_x2 = gf_mult2(m3);
wire [7:0] m0_x3 = gf_mult3(m0);
wire [7:0] m1_x3 = gf_mult3(m1);
wire [7:0] m2_x3 = gf_mult3(m2);
wire [7:0] m3_x3 = gf_mult3(m3);

wire [7:0] c0 = m0_x2 ^ m1_x3 ^ m2 ^ m3;           // Row 0
wire [7:0] c1 = m0 ^ m1_x2 ^ m2_x3 ^ m3;           // Row 1
wire [7:0] c2 = m0 ^ m1 ^ m2_x2 ^ m3_x3;           // Row 2
wire [7:0] c3 = m0_x3 ^ m1 ^ m2 ^ m3_x2;           // Row 3

// ============================================================================
// Output (MSB first: byte 0 at [31:24])
// ============================================================================
assign data_out = {c0, c1, c2, c3};

endmodule