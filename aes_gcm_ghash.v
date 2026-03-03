`timescale 1ns / 1ps
//==============================================================================
// Module: aes_gcm_ghash
//
// Description:
//   High-throughput GHASH engine implementing the NIST SP 800-38D GHASH
//   function using Horner's scheme:
//       Y_0 = 0
//       Y_i = (Y_{i-1} XOR X_i) * H    (i = 1..m)
//
// Architecture (sequential mode, PARALLEL_MODE=0):
//   The GF(2^128) multiplier from aes_gcm_gf128_mul is fully combinatorial,
//   so the accumulator update is just one register stage:
//       Y_acc <= (block_in XOR Y_acc) * H    -- 1 block per cycle
//
//   block_ready is always 1 (no pipeline stall needed).
//   ghash_valid is sticky: stays high once the last block is processed,
//   until init is asserted for the next message.
//
// Architecture (4-parallel mode, PARALLEL_MODE=1):
//   Precomputes H^2, H^3, H^4.  Buffers 4 blocks then computes:
//       Y_new = (X_4 XOR Y_old)*H^4 XOR X_3*H^3 XOR X_2*H^2 XOR X_1*H
//   Achieves 1-block-per-cycle throughput for large messages.
//==============================================================================

module aes_gcm_ghash #(
    parameter PARALLEL_MODE = 0
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [127:0] H,           // GHASH subkey = AES_K(0^128)

    input  wire         init,        // Reset accumulator (start new message)
    input  wire         last_block,  // Mark this block as the last

    input  wire [127:0] block_in,
    input  wire         block_valid,
    output wire         block_ready,

    output reg  [127:0] ghash_out,
    output reg          ghash_valid  // Sticky until init
);

generate
if (PARALLEL_MODE == 0) begin : seq_ghash

    //------------------------------------------------------------------
    // Sequential GHASH: 1 block per cycle, combinatorial GF multiply
    //------------------------------------------------------------------
    reg [127:0] Y_acc;

    wire [127:0] mul_in  = block_in ^ Y_acc;
    wire [127:0] mul_out;

    aes_gcm_gf128_mul u_mul (
        .a     (mul_in),
        .b     (H),
        .result(mul_out)
    );

    assign block_ready = 1'b1;   // Always ready

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Y_acc      <= 128'b0;
            ghash_out  <= 128'b0;
            ghash_valid<= 1'b0;
        end else begin
            if (init) begin
                Y_acc      <= 128'b0;
                ghash_valid<= 1'b0;   // Clear result for new message
            end else if (block_valid) begin
                Y_acc <= mul_out;
                if (last_block) begin
                    ghash_out   <= mul_out;
                    ghash_valid <= 1'b1;   // Sticky: stays high until init
                end
            end
        end
    end

end else begin : par_ghash

    //------------------------------------------------------------------
    // 4-parallel GHASH: effective 1 block/cycle for bulk data.
    // Uses precomputed H^2, H^3, H^4 and buffers 4 input blocks.
    //------------------------------------------------------------------
    wire [127:0] H2, H3, H4;
    aes_gcm_gf128_mul u_H2 (.a(H),  .b(H),  .result(H2));
    aes_gcm_gf128_mul u_H3 (.a(H2), .b(H),  .result(H3));
    aes_gcm_gf128_mul u_H4 (.a(H2), .b(H2), .result(H4));

    reg [127:0] blk [0:3];     // 4-block ring buffer
    reg [1:0]   blk_cnt;       // 0..3
    reg         computing;     // Waiting for parallel mult result
    reg         last_flag;     // Last-block seen in this group
    reg [127:0] Y_acc;

    // 4 parallel multipliers: blocks 0..3 multiplied by H^4..H^1
    // block[3] (oldest) is XOR'd with Y_acc before multiply
    wire [127:0] m0_in = blk[3] ^ Y_acc;
    wire [127:0] p0, p1, p2, p3;
    aes_gcm_gf128_mul u_p0 (.a(m0_in),  .b(H4), .result(p0));
    aes_gcm_gf128_mul u_p1 (.a(blk[2]), .b(H3), .result(p1));
    aes_gcm_gf128_mul u_p2 (.a(blk[1]), .b(H2), .result(p2));
    aes_gcm_gf128_mul u_p3 (.a(blk[0]), .b(H),  .result(p3));

    // Registered partial products (1-cycle pipeline for timing)
    reg [127:0] p0r, p1r, p2r, p3r;
    reg         result_valid;

    assign block_ready = ~computing;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blk_cnt      <= 2'b0;
            computing    <= 1'b0;
            last_flag    <= 1'b0;
            Y_acc        <= 128'b0;
            result_valid <= 1'b0;
            ghash_out    <= 128'b0;
            ghash_valid  <= 1'b0;
        end else begin
            result_valid <= 1'b0;

            if (init) begin
                Y_acc       <= 128'b0;
                blk_cnt     <= 2'b0;
                computing   <= 1'b0;
                last_flag   <= 1'b0;
                ghash_valid <= 1'b0;
            end else begin
                // Latch partial product results (1-cycle delay)
                p0r <= p0; p1r <= p1; p2r <= p2; p3r <= p3;

                if (result_valid) begin
                    Y_acc     <= p0r ^ p1r ^ p2r ^ p3r;
                    computing <= 1'b0;
                    blk_cnt   <= 2'b0;
                    if (last_flag) begin
                        ghash_out   <= p0r ^ p1r ^ p2r ^ p3r;
                        ghash_valid <= 1'b1;
                        last_flag   <= 1'b0;
                    end
                end

                if (block_valid && !computing) begin
                    blk[blk_cnt] <= block_in;
                    if (last_block) last_flag <= 1'b1;
                    if (blk_cnt == 2'd3) begin
                        computing    <= 1'b1;
                        result_valid <= 1'b1;  // fires 1 cycle after muls are set
                    end else begin
                        blk_cnt <= blk_cnt + 1'b1;
                    end
                end
            end
        end
    end

end
endgenerate

endmodule
