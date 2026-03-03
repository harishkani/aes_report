`timescale 1ns / 1ps
//==============================================================================
// Module: aes_gcm_ghash
//
// Description:
//   High-throughput GHASH engine for AES-GCM authentication tag computation.
//   Implements the NIST SP 800-38D GHASH function:
//
//       GHASH_H(X_1, X_2, ..., X_m) = X_1·H^m XOR X_2·H^(m-1) XOR ... XOR X_m·H
//
//   using Horner's scheme:
//       Y_0 = 0
//       Y_i = (Y_{i-1} XOR X_i) * H   (i = 1 to m)
//
// Architecture:
//   The GF(2^128) multiplication (Y XOR X) * H is implemented using the
//   fully combinatorial Karatsuba multiplier from aes_gcm_gf128_mul.v,
//   wrapped in a 4-stage pipeline register to achieve:
//     - 4-cycle latency per GF multiplication
//     - 1-block-per-cycle throughput (with 4-cycle startup latency)
//     - 4× parallel GF multiplications interleaved over 4 pipeline stages
//
//   The 4-stage pipeline uses a "4-way interleaved" approach:
//   Since each GHASH step has a true data dependence on the previous result,
//   single-stream pipelining requires the "feedback through the pipeline"
//   technique. With 4 pipeline stages, 4 independent input blocks can be
//   in-flight simultaneously IF and ONLY IF we accept that consecutive blocks
//   of the same message cannot all feed into this pipeline directly.
//
//   Design choice: Single-stream sequential GHASH with a 4-stage registered
//   multiplier.  New block accepted every 4 cycles (when prev_result ready).
//   For higher utilization, the top-level module can instantiate multiple
//   independent GHASH cores for parallel streams.
//
//   Alternatively (and implemented here as a second mode via PARALLEL_MODE=1):
//   "Pre-computation" approach: expand input 4 blocks at a time by processing
//   the 4-cycle pipeline latency as parallel independent subproblems using
//   powers of H (H, H^2, H^3, H^4) — this achieves 1-block/cycle effective
//   throughput.
//
// Throughput modes:
//   PARALLEL_MODE = 0: 1 block per 4 cycles (simple pipelined sequential)
//   PARALLEL_MODE = 1: 1 block per cycle (4-parallel with H powers, 4x LUTs)
//
// GHASH Bit Convention:
//   Matches NIST SP 800-38D: MSB of each byte transmitted first.
//   GCM uses MSB-first polynomial representation.
//
// Interface:
//   clk, rst_n             Clock and active-low reset
//   H[127:0]               GHASH subkey = AES_K(0^128)
//   init                   Pulse: resets Y accumulator to 0, starts new GHASH
//   block_in[127:0]        Input 128-bit GHASH block
//   block_valid            Input valid strobe
//   block_ready            Output: core ready to accept new block
//   ghash_out[127:0]       Current GHASH accumulator value
//   ghash_valid            ghash_out is the final result (all blocks processed)
//
// References:
//   - NIST SP 800-38D Section 6.4
//   - Abdellatif et al., "Efficient Parallel-Pipelined GHASH", 2014
//   - Zhou & Michalik, ARC 2009
//==============================================================================

module aes_gcm_ghash #(
    parameter PARALLEL_MODE = 0   // 0=sequential 4-cycle/block, 1=4-parallel 1-cycle/block
)(
    input  wire        clk,
    input  wire        rst_n,

    // Hash subkey H = AES_K(0^128)
    input  wire [127:0] H,

    // Control
    input  wire         init,         // Reset accumulator to start new message
    input  wire         last_block,   // Mark last block (ghash_valid pulses next cycle)

    // Input stream
    input  wire [127:0] block_in,
    input  wire         block_valid,
    output wire         block_ready,

    // Output
    output reg  [127:0] ghash_out,
    output reg          ghash_valid
);

generate
if (PARALLEL_MODE == 0) begin : seq_mode
    //--------------------------------------------------------------------------
    // Sequential mode: 4-stage pipelined GF multiplier
    // Accept one block every 4 cycles.
    //--------------------------------------------------------------------------

    // Pipeline registers for the GF multiplier (4 stages)
    reg [127:0] mul_pipe [0:3];
    reg         mul_valid_pipe [0:3];
    reg [127:0] Y_acc;          // GHASH accumulator
    reg [2:0]   cycle_cnt;      // 0..3: pipeline fill counter
    reg         busy;           // 1 when multiplier is in flight

    wire [127:0] mul_input  = block_in ^ Y_acc;
    wire [127:0] mul_result_comb;

    // Instantiate combinatorial GF(2^128) multiplier
    aes_gcm_gf128_mul u_gfmul (
        .a     (mul_input),
        .b     (H),
        .result(mul_result_comb)
    );

    assign block_ready = ~busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Y_acc      <= 128'b0;
            cycle_cnt  <= 3'b0;
            busy       <= 1'b0;
            ghash_out  <= 128'b0;
            ghash_valid<= 1'b0;
            mul_pipe[0]<= 128'b0;
            mul_pipe[1]<= 128'b0;
            mul_pipe[2]<= 128'b0;
            mul_pipe[3]<= 128'b0;
            mul_valid_pipe[0] <= 1'b0;
            mul_valid_pipe[1] <= 1'b0;
            mul_valid_pipe[2] <= 1'b0;
            mul_valid_pipe[3] <= 1'b0;
        end else begin
            ghash_valid <= 1'b0;

            if (init) begin
                Y_acc      <= 128'b0;
                busy       <= 1'b0;
                cycle_cnt  <= 3'b0;
                mul_valid_pipe[0] <= 1'b0;
                mul_valid_pipe[1] <= 1'b0;
                mul_valid_pipe[2] <= 1'b0;
                mul_valid_pipe[3] <= 1'b0;
            end else begin
                // Advance pipeline
                mul_pipe[1]       <= mul_pipe[0];
                mul_pipe[2]       <= mul_pipe[1];
                mul_pipe[3]       <= mul_pipe[2];
                mul_valid_pipe[1] <= mul_valid_pipe[0];
                mul_valid_pipe[2] <= mul_valid_pipe[1];
                mul_valid_pipe[3] <= mul_valid_pipe[2];

                if (block_valid && !busy) begin
                    // Latch the combinatorial result at the head of the pipeline
                    mul_pipe[0]       <= mul_result_comb;
                    mul_valid_pipe[0] <= 1'b1;
                    busy              <= 1'b1;
                    cycle_cnt         <= 3'd0;
                end else if (busy) begin
                    mul_pipe[0]       <= mul_result_comb;  // keep updating (combinatorial)
                    mul_valid_pipe[0] <= 1'b0;             // only valid on first cycle
                    cycle_cnt         <= cycle_cnt + 1'b1;
                    if (cycle_cnt == 3'd3) begin
                        // Result is now in mul_pipe[3]
                        Y_acc <= mul_pipe[3];
                        busy  <= 1'b0;
                        if (last_block) begin
                            ghash_out   <= mul_pipe[3];
                            ghash_valid <= 1'b1;
                        end
                    end
                end
            end
        end
    end

end else begin : par_mode
    //--------------------------------------------------------------------------
    // 4-PARALLEL mode: computes GHASH over 4 blocks simultaneously.
    // Precomputes H^2, H^3, H^4 alongside H.
    // Effective throughput: 1 block/cycle (4 blocks processed in 4 cycles).
    //
    // Block grouping: blocks are buffered into groups of 4.
    // Computation: Y_new = X_4*H^4 XOR X_3*H^3 XOR X_2*H^2 XOR X_1*H XOR Y_old*H^4
    //
    // For simplicity this implementation buffers 4 blocks, then computes
    // all 4 multiplications in parallel (using 5 GF multipliers) and XORs
    // the partial products together.
    //
    // Note: partial blocks at the end must be zero-padded per NIST spec.
    //--------------------------------------------------------------------------

    // Precompute H^2, H^3, H^4
    wire [127:0] H2, H3, H4;
    aes_gcm_gf128_mul u_H2 (.a(H),  .b(H),  .result(H2));
    aes_gcm_gf128_mul u_H3 (.a(H2), .b(H),  .result(H3));
    aes_gcm_gf128_mul u_H4 (.a(H2), .b(H2), .result(H4));

    // Block buffer (4 blocks)
    reg [127:0] buf_block [0:3];
    reg [1:0]   buf_cnt;
    reg         buf_full;
    reg [127:0] Y_acc;
    reg         last_flag;

    // 5 parallel multiplier results (registered)
    wire [127:0] p0, p1, p2, p3, p4;
    reg  [127:0] p0_r, p1_r, p2_r, p3_r, p4_r;
    reg          par_valid;

    // Multiplier inputs
    wire [127:0] m0_in = buf_block[3] ^ Y_acc;  // oldest block XOR accumulator
    aes_gcm_gf128_mul u_p0 (.a(m0_in),       .b(H4), .result(p0));
    aes_gcm_gf128_mul u_p1 (.a(buf_block[2]), .b(H3), .result(p1));
    aes_gcm_gf128_mul u_p2 (.a(buf_block[1]), .b(H2), .result(p2));
    aes_gcm_gf128_mul u_p3 (.a(buf_block[0]), .b(H),  .result(p3));

    assign block_ready = ~buf_full;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_cnt   <= 2'b0;
            buf_full  <= 1'b0;
            Y_acc     <= 128'b0;
            par_valid <= 1'b0;
            ghash_out  <= 128'b0;
            ghash_valid<= 1'b0;
            last_flag <= 1'b0;
        end else begin
            ghash_valid <= 1'b0;

            if (init) begin
                Y_acc     <= 128'b0;
                buf_cnt   <= 2'b0;
                buf_full  <= 1'b0;
                par_valid <= 1'b0;
                last_flag <= 1'b0;
            end else begin
                // Register parallel products
                p0_r <= p0; p1_r <= p1; p2_r <= p2; p3_r <= p3;

                if (par_valid) begin
                    Y_acc     <= p0_r ^ p1_r ^ p2_r ^ p3_r;
                    buf_full  <= 1'b0;
                    buf_cnt   <= 2'b0;
                    par_valid <= 1'b0;
                    if (last_flag) begin
                        ghash_out   <= p0_r ^ p1_r ^ p2_r ^ p3_r;
                        ghash_valid <= 1'b1;
                        last_flag   <= 1'b0;
                    end
                end

                if (block_valid && !buf_full) begin
                    buf_block[buf_cnt] <= block_in;
                    if (last_block) last_flag <= 1'b1;
                    if (buf_cnt == 2'd3) begin
                        buf_full  <= 1'b1;
                        par_valid <= 1'b1;  // fire multipliers
                    end else begin
                        buf_cnt <= buf_cnt + 1'b1;
                    end
                end
            end
        end
    end

end
endgenerate

endmodule
