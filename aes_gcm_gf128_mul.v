`timescale 1ns / 1ps
//==============================================================================
// Module: aes_gcm_gf128_mul
//
// GCM-correct GF(2^128) multiplier using 3-level Karatsuba decomposition.
//
// GCM bit convention (NIST SP 800-38D §6.3):
//   The leftmost (MSB) bit of a 128-bit block = coefficient of x^0.
//   So in Verilog [127:0], bit[127] = x^0 coeff, bit[0] = x^127 coeff.
//
// Fix vs naive implementation:
//   Standard polynomial arithmetic expects bit[0] = x^0 (LSB-first).
//   GCM uses MSB-first.  We bit-reverse inputs to convert to LSB-first,
//   run standard Karatsuba + reduction, then bit-reverse the output.
//   Bit-reversal is purely wiring (zero logic, zero delay).
//
// Reduction polynomial (standard LSB-first form):
//   P(x) = x^128 + x^7 + x^2 + x + 1
//   x^(128+k) ≡ x^(k+7) + x^(k+2) + x^(k+1) + x^k  mod P(x)
//==============================================================================

module aes_gcm_gf128_mul (
    input  wire [127:0] a,        // GCM MSB-first element
    input  wire [127:0] b,        // GCM MSB-first element
    output wire [127:0] result    // GCM MSB-first result = a*b mod P(x)
);

// ── Step 0: bit-reverse inputs (GCM → standard LSB-first) ──────────────────
wire [127:0] a_s, b_s;   // _s = standard LSB-first
genvar gi;
generate
    for (gi = 0; gi < 128; gi = gi + 1) begin : brv_in
        assign a_s[gi] = a[127-gi];
        assign b_s[gi] = b[127-gi];
    end
endgenerate

// ── Step 1: Karatsuba level-1 (128 → 64-bit halves) ──────────────────────
// In LSB-first: A = Ah·x^64 + Al  where Ah = high-degree half = a_s[127:64]
wire [63:0] Ah = a_s[127:64];
wire [63:0] Al = a_s[63:0];
wire [63:0] Bh = b_s[127:64];
wire [63:0] Bl = b_s[63:0];

wire [63:0] AmX = Ah ^ Al;
wire [63:0] BmX = Bh ^ Bl;

wire [127:0] Z2, Z0, Zm;
gf64_mul u_Z2 (.a(Ah),  .b(Bh),  .result(Z2));
gf64_mul u_Z0 (.a(Al),  .b(Bl),  .result(Z0));
gf64_mul u_Zm (.a(AmX), .b(BmX), .result(Zm));

wire [127:0] Z1 = Zm ^ Z2 ^ Z0;

// ── Step 2: assemble 256-bit raw polynomial product ───────────────────────
// raw[63:0]   = Z0 low
// raw[127:64] = Z0 high ^ Z1 low
// raw[191:128]= Z1 high ^ Z2 low
// raw[255:192]= Z2 high
wire [255:0] raw;
assign raw[255:192] = Z2[127:64];
assign raw[191:128] = Z2[63:0]  ^ Z1[127:64];
assign raw[127:64]  = Z1[63:0]  ^ Z0[127:64];
assign raw[63:0]    = Z0[63:0];

// ── Step 3: modular reduction mod P(x) = x^128 + x^7 + x^2 + x + 1 ───────
wire [127:0] hi = raw[255:128];
wire [127:0] lo = raw[127:0];

// First fold: lo ^= hi * (x^7+x^2+x+1)
// hi<<k in 128-bit Verilog automatically truncates the overflow.
wire [127:0] fold = hi ^ (hi << 1) ^ (hi << 2) ^ (hi << 7);

// Overflow bits that were shifted out of the 128-bit window by each shift:
//   <<1  : hi[127] → position 128        (k=0 only)
//   <<2  : hi[127:126] → positions 128,129
//   <<7  : hi[127:121] → positions 128..134
// Combined overflow at position 128+k (k=0..6):
wire [6:0] ov;
assign ov[0] = hi[127] ^ hi[126] ^ hi[121];
assign ov[1] = hi[127] ^ hi[122];
assign ov[2] = hi[123];
assign ov[3] = hi[124];
assign ov[4] = hi[125];
assign ov[5] = hi[126];
assign ov[6] = hi[127];

// Second fold: reduce 7-bit overflow (degrees 128..134).
// Max degree after second fold = 6+7=13 < 128, so no third pass needed.
wire [13:0] ov2 = {7'b0, ov} ^ {6'b0, ov, 1'b0} ^ {5'b0, ov, 2'b0} ^ {ov, 7'b0};

wire [127:0] result_s = lo ^ fold ^ {114'b0, ov2};

// ── Step 4: bit-reverse output (standard → GCM MSB-first) ─────────────────
genvar go;
generate
    for (go = 0; go < 128; go = go + 1) begin : brv_out
        assign result[go] = result_s[127-go];
    end
endgenerate

endmodule


//==============================================================================
// gf64_mul  –  64×64 carry-less polynomial multiply (standard LSB-first)
// Produces a 128-bit result.  Uses 2-level Karatsuba → three 32×32 muls.
//==============================================================================
module gf64_mul (
    input  wire [63:0]  a,
    input  wire [63:0]  b,
    output wire [127:0] result
);

wire [31:0] Ah = a[63:32], Al = a[31:0];
wire [31:0] Bh = b[63:32], Bl = b[31:0];
wire [31:0] Am = Ah ^ Al,  Bm = Bh ^ Bl;

wire [63:0] Z2, Z0, Zm;
gf32_mul u_z2 (.a(Ah), .b(Bh), .result(Z2));
gf32_mul u_z0 (.a(Al), .b(Bl), .result(Z0));
gf32_mul u_zm (.a(Am), .b(Bm), .result(Zm));

wire [63:0] Z1 = Zm ^ Z2 ^ Z0;

assign result[127:96] = Z2[63:32];
assign result[95:64]  = Z2[31:0]  ^ Z1[63:32];
assign result[63:32]  = Z1[31:0]  ^ Z0[63:32];
assign result[31:0]   = Z0[31:0];

endmodule


//==============================================================================
// gf32_mul  –  32×32 schoolbook carry-less polynomial multiply (LSB-first)
// Produces a 64-bit result.
//==============================================================================
module gf32_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [63:0] result
);

wire [63:0] partial [0:31];
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : gen_partial
        assign partial[i] = b[i] ? ({32'b0, a} << i) : 64'b0;
    end
endgenerate

// XOR tree (5 levels)
wire [63:0] s0[0:15], s1[0:7], s2[0:3], s3[0:1];
genvar j;
generate
    for (j = 0; j < 16; j = j + 1) begin : l0
        assign s0[j] = partial[2*j] ^ partial[2*j+1];
    end
    for (j = 0; j < 8; j = j + 1) begin : l1
        assign s1[j] = s0[2*j] ^ s0[2*j+1];
    end
    for (j = 0; j < 4; j = j + 1) begin : l2
        assign s2[j] = s1[2*j] ^ s1[2*j+1];
    end
    for (j = 0; j < 2; j = j + 1) begin : l3
        assign s3[j] = s2[2*j] ^ s2[2*j+1];
    end
endgenerate

assign result = s3[0] ^ s3[1];

endmodule
