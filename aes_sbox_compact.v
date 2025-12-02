`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Compact AES S-Box using Composite Field Arithmetic
//
// This implementation uses ~30-50 LUTs instead of 256 LUTs for LUT-based S-box
// Based on Canright's "A Very Compact S-Box for AES" (CHES 2005)
//
// Computation in GF((2^4)^2) with polynomial basis
// Reduces area significantly while maintaining functionality
//////////////////////////////////////////////////////////////////////////////////

module aes_sbox_compact(
    input  [7:0] in,
    output [7:0] out
);

// Forward transformation (encryption S-box)

// Step 1: Change basis from GF(2^8) to GF((2^4)^2)
wire [7:0] y;
assign y[7] = in[7] ^ in[5];
assign y[6] = in[7] ^ in[6] ^ in[4] ^ in[3] ^ in[2];
assign y[5] = in[7] ^ in[5] ^ in[3] ^ in[2];
assign y[4] = in[5] ^ in[3] ^ in[2];
assign y[3] = in[6] ^ in[5] ^ in[1];
assign y[2] = in[7] ^ in[3] ^ in[1];
assign y[1] = in[7] ^ in[4] ^ in[3] ^ in[2] ^ in[1];
assign y[0] = in[6] ^ in[5] ^ in[4] ^ in[1] ^ in[0];

// Step 2: Compute multiplicative inverse in GF((2^4)^2)
wire [3:0] yh = y[7:4];  // High nibble
wire [3:0] yl = y[3:0];  // Low nibble

// GF(2^4) operations
wire [3:0] t1 = gf4_mult(yh, yl);
wire [3:0] t2 = gf4_sq(yh ^ yl);
wire [3:0] t3 = t1 ^ t2;
wire [3:0] t4 = gf4_inv(t3);
wire [3:0] t5 = gf4_mult(t4, yh);
wire [3:0] t6 = gf4_mult(t4, yl);

wire [7:0] z = {t5, t6};

// Step 3: Affine transformation
wire [7:0] s;
assign s[7] = z[7] ^ z[6] ^ z[5] ^ z[4] ^ z[3]        ^ 1'b1;
assign s[6] = z[6] ^ z[5] ^ z[4] ^ z[3] ^ z[2]        ^ 1'b1;
assign s[5] = z[5] ^ z[4] ^ z[3] ^ z[2] ^ z[1];
assign s[4] = z[4] ^ z[3] ^ z[2] ^ z[1] ^ z[0]        ^ 1'b1;
assign s[3] = z[3] ^ z[2] ^ z[1] ^ z[0] ^ z[7]        ^ 1'b1;
assign s[2] = z[2] ^ z[1] ^ z[0] ^ z[7] ^ z[6];
assign s[1] = z[1] ^ z[0] ^ z[7] ^ z[6] ^ z[5];
assign s[0] = z[0] ^ z[7] ^ z[6] ^ z[5] ^ z[4];

assign out = s;

// GF(2^4) multiplication in polynomial basis {1, α, α^2, α^3}
function [3:0] gf4_mult;
    input [3:0] a, b;
    reg [3:0] p;
    begin
        p[3] = (a[3] & b[3]) ^ (a[2] & b[3] ^ a[3] & b[2]) ^ (a[3] & b[1] ^ a[2] & b[2] ^ a[1] & b[3]);
        p[2] = (a[2] & b[3] ^ a[3] & b[2]) ^ (a[1] & b[3] ^ a[2] & b[2] ^ a[3] & b[1]) ^
               (a[3] & b[0] ^ a[2] & b[1] ^ a[1] & b[2] ^ a[0] & b[3]);
        p[1] = (a[3] & b[1] ^ a[2] & b[2] ^ a[1] & b[3]) ^
               (a[2] & b[1] ^ a[1] & b[2] ^ a[0] & b[3] ^ a[3] & b[0]) ^
               (a[2] & b[0] ^ a[1] & b[1] ^ a[0] & b[2]);
        p[0] = (a[3] & b[0] ^ a[2] & b[1] ^ a[1] & b[2] ^ a[0] & b[3]) ^
               (a[2] & b[0] ^ a[1] & b[1] ^ a[0] & b[2]) ^
               (a[1] & b[0] ^ a[0] & b[1]);
        gf4_mult = p;
    end
endfunction

// GF(2^4) squaring
function [3:0] gf4_sq;
    input [3:0] a;
    reg [3:0] p;
    begin
        p[3] = a[3] ^ a[2];
        p[2] = a[2];
        p[1] = a[3] ^ a[1];
        p[0] = a[1] ^ a[0];
        gf4_sq = p;
    end
endfunction

// GF(2^4) inversion
function [3:0] gf4_inv;
    input [3:0] a;
    reg [3:0] p;
    begin
        // Inversion using extended GCD simplified for small field
        case(a)
            4'h0: p = 4'h0;  // 0 has no inverse
            4'h1: p = 4'h1;
            4'h2: p = 4'h9;
            4'h3: p = 4'hE;
            4'h4: p = 4'hD;
            4'h5: p = 4'hB;
            4'h6: p = 4'h7;
            4'h7: p = 4'h6;
            4'h8: p = 4'hF;
            4'h9: p = 4'h2;
            4'hA: p = 4'hC;
            4'hB: p = 4'h5;
            4'hC: p = 4'hA;
            4'hD: p = 4'h4;
            4'hE: p = 4'h3;
            4'hF: p = 4'h8;
        endcase
        gf4_inv = p;
    end
endfunction

endmodule


//////////////////////////////////////////////////////////////////////////////////
// Compact AES Inverse S-Box using Composite Field Arithmetic
//////////////////////////////////////////////////////////////////////////////////

module aes_inv_sbox_compact(
    input  [7:0] in,
    output [7:0] out
);

// Step 1: Inverse affine transformation
wire [7:0] t;
assign t[7] = in[7]                         ^ in[5] ^ in[3];
assign t[6] = in[6]               ^ in[4]           ^ in[2];
assign t[5] = in[5]     ^ in[3]           ^ in[1];
assign t[4] = in[4]           ^ in[2]     ^ in[0]   ^ 1'b1;
assign t[3] = in[3]           ^ in[1]     ^ in[7]   ^ 1'b1;
assign t[2] = in[2]                 ^ in[0] ^ in[6];
assign t[1] = in[1]                       ^ in[5];
assign t[0] = in[0]                       ^ in[4]   ^ 1'b1;

// Step 2: Change basis
wire [7:0] y;
assign y[7] = t[7]       ^ t[5] ^ t[4] ^ t[2] ^ t[1];
assign y[6] = t[6] ^ t[5]       ^ t[3] ^ t[2] ^ t[1];
assign y[5] =        t[5] ^ t[4]              ^ t[1];
assign y[4] =        t[5] ^ t[4] ^ t[3] ^ t[2] ^ t[1] ^ t[0];
assign y[3] = t[7]              ^ t[3]        ^ t[1];
assign y[2] = t[7] ^ t[6]              ^ t[2];
assign y[1] =               t[4] ^ t[3]              ^ t[0];
assign y[0] = t[7]       ^ t[5]                      ^ t[0];

// Step 3: Inverse in GF((2^4)^2)
wire [3:0] yh = y[7:4];
wire [3:0] yl = y[3:0];

wire [3:0] t1 = gf4_mult(yh, yl);
wire [3:0] t2 = gf4_sq(yh ^ yl);
wire [3:0] t3 = t1 ^ t2;
wire [3:0] t4 = gf4_inv(t3);
wire [3:0] t5 = gf4_mult(t4, yh);
wire [3:0] t6 = gf4_mult(t4, yl);

wire [7:0] z = {t5, t6};

// Step 4: Inverse basis change
wire [7:0] s;
assign s[7] = z[7]       ^ z[5] ^ z[4] ^ z[2];
assign s[6] = z[7] ^ z[6]              ^ z[2] ^ z[1];
assign s[5] =        z[5]                     ^ z[1];
assign s[4] =        z[5]              ^ z[2];
assign s[3] = z[7] ^ z[6] ^ z[5] ^ z[4];
assign s[2] = z[7]              ^ z[4] ^ z[3] ^ z[2] ^ z[1];
assign s[1] =        z[5]              ^ z[2]        ^ z[0];
assign s[0] = z[7]                            ^ z[1];

assign out = s;

// GF(2^4) functions (same as forward S-box)
function [3:0] gf4_mult;
    input [3:0] a, b;
    reg [3:0] p;
    begin
        p[3] = (a[3] & b[3]) ^ (a[2] & b[3] ^ a[3] & b[2]) ^ (a[3] & b[1] ^ a[2] & b[2] ^ a[1] & b[3]);
        p[2] = (a[2] & b[3] ^ a[3] & b[2]) ^ (a[1] & b[3] ^ a[2] & b[2] ^ a[3] & b[1]) ^
               (a[3] & b[0] ^ a[2] & b[1] ^ a[1] & b[2] ^ a[0] & b[3]);
        p[1] = (a[3] & b[1] ^ a[2] & b[2] ^ a[1] & b[3]) ^
               (a[2] & b[1] ^ a[1] & b[2] ^ a[0] & b[3] ^ a[3] & b[0]) ^
               (a[2] & b[0] ^ a[1] & b[1] ^ a[0] & b[2]);
        p[0] = (a[3] & b[0] ^ a[2] & b[1] ^ a[1] & b[2] ^ a[0] & b[3]) ^
               (a[2] & b[0] ^ a[1] & b[1] ^ a[0] & b[2]) ^
               (a[1] & b[0] ^ a[0] & b[1]);
        gf4_mult = p;
    end
endfunction

function [3:0] gf4_sq;
    input [3:0] a;
    reg [3:0] p;
    begin
        p[3] = a[3] ^ a[2];
        p[2] = a[2];
        p[1] = a[3] ^ a[1];
        p[0] = a[1] ^ a[0];
        gf4_sq = p;
    end
endfunction

function [3:0] gf4_inv;
    input [3:0] a;
    reg [3:0] p;
    begin
        case(a)
            4'h0: p = 4'h0;
            4'h1: p = 4'h1;
            4'h2: p = 4'h9;
            4'h3: p = 4'hE;
            4'h4: p = 4'hD;
            4'h5: p = 4'hB;
            4'h6: p = 4'h7;
            4'h7: p = 4'h6;
            4'h8: p = 4'hF;
            4'h9: p = 4'h2;
            4'hA: p = 4'hC;
            4'hB: p = 4'h5;
            4'hC: p = 4'hA;
            4'hD: p = 4'h4;
            4'hE: p = 4'h3;
            4'hF: p = 4'h8;
        endcase
        gf4_inv = p;
    end
endfunction

endmodule
