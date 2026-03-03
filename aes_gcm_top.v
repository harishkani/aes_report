`timescale 1ns / 1ps
//==============================================================================
// Module: aes_gcm_top
//
// Complete AES-128-GCM AEAD.  Simplified, fully-serialised state machine
// for correctness and ease of verification.  High-throughput pipelining
// optimisations can be layered on top once functional correctness is
// confirmed.
//
// Operation sequence:
//   1. Assert key_valid with the 128-bit key.
//      Module immediately computes H = AES_K(0^128).  Takes AES_LAT cycles.
//
//   2. Assert start with iv, aad_len, pt_len, encrypt.
//      Module computes E_J0 = AES_K(J0) where J0 = IV||0x00000001.
//      Takes AES_LAT cycles.
//
//   3. If aad_len > 0: drive aad_in / aad_valid.  Each 128-bit block accepted
//      one per cycle when aad_ready=1.
//
//   4. Drive pt_in / pt_valid.  For each 128-bit block the module:
//        a. Sends J0+ctr to AES.
//        b. Waits AES_LAT cycles.
//        c. Outputs ct_out = keystream XOR pt_in.
//        d. Sends ct_out to GHASH.
//        e. ctr++.
//      pt_ready is asserted only when the module is ready for the next block.
//
//   5. After all PT blocks, GHASH receives the lengths block then the result
//      is tag = ghash_out XOR E_J0.
//
// IV convention:
//   96-bit IV → J0 = {IV, 32'h00000001}  (NIST SP 800-38D §7.1)
//
// Latency parameters:
//   AES_LAT = 11 (pipeline depth of aes_gcm_pipelined_aes: 10 round stages +
//                 1 output register).  Adjust if AES pipeline is changed.
//==============================================================================

module aes_gcm_top (
    input  wire        clk,
    input  wire        rst_n,

    // Key setup
    input  wire [127:0] key,
    input  wire         key_valid,

    // IV (96-bit), lengths, mode
    input  wire [95:0]  iv,
    input  wire [31:0]  aad_len,
    input  wire [31:0]  pt_len,
    input  wire         encrypt,
    input  wire         start,

    // AAD stream (128-bit blocks, zero-pad partial)
    input  wire [127:0] aad_in,
    input  wire         aad_valid,
    output reg          aad_ready,

    // PT/CT stream
    input  wire [127:0] pt_in,
    input  wire         pt_valid,
    output reg          pt_ready,
    output reg  [127:0] ct_out,
    output reg          ct_valid,

    // Authentication tag
    output reg  [127:0] tag_out,
    output reg          tag_valid,

    // Decryption: tag verification
    input  wire [127:0] tag_in,
    output reg          tag_match
);

// ── Constants ────────────────────────────────────────────────────────────────
// AES_LAT = 12 accounts for the full round-trip:
//   GCM sets aes_vin via NBA at posedge T → AES samples it at T+1 →
//   pipeline fills over T+1 .. T+11 → data_out NBA update at T+12 →
//   GCM reads data_out at T+13 active (when lat_cnt reaches 0 after 12 decrements).
localparam AES_LAT = 12;

localparam [3:0]
    ST_IDLE        = 4'd0,
    ST_WAIT_H      = 4'd1,   // AES(0) in-flight → H
    ST_READY       = 4'd2,   // Key ready, waiting for start
    ST_WAIT_EJ0    = 4'd3,   // AES(J0) in-flight → E_J0
    ST_GHASH_INIT  = 4'd4,   // Assert ghash init for 1 cycle
    ST_AAD         = 4'd5,   // Process AAD blocks
    ST_CT_SEND     = 4'd6,   // Send CTR block to AES
    ST_CT_WAIT     = 4'd7,   // Wait AES_LAT cycles for keystream
    ST_LENGTHS     = 4'd8,   // Send lengths block to GHASH
    ST_WAIT_GHASH  = 4'd9,   // Wait for GHASH result
    ST_TAG         = 4'd10;  // Output tag

// ── Registers ────────────────────────────────────────────────────────────────
reg [3:0]   state;
reg [127:0] key_r;
reg [127:0] H;
reg [127:0] E_J0;
reg [127:0] J0;
reg [31:0]  ctr;
reg [31:0]  aad_blk_rem;
reg [31:0]  pt_blk_rem;
reg [31:0]  aad_len_r, pt_len_r;
reg         enc_r;
reg [127:0] pt_buf;        // Buffered PT waiting for keystream
reg [4:0]   lat_cnt;       // Counts down from AES_LAT

// ── Key schedule (combinatorial) ─────────────────────────────────────────────
wire [127:0] rk [0:10];
aes_gcm_key_schedule u_ks (.key(key_r), .rk(rk));

// ── Pipelined AES core ────────────────────────────────────────────────────────
reg  [127:0] aes_in;
reg          aes_vin;
wire [127:0] aes_out;
wire         aes_vout;

aes_gcm_pipelined_aes u_aes (
    .clk           (clk),
    .rst_n         (rst_n),
    .data_in       (aes_in),
    .data_valid_in (aes_vin),
    .rk            (rk),
    .data_out      (aes_out),
    .data_valid_out(aes_vout)
);

// ── GHASH engine ──────────────────────────────────────────────────────────────
reg  [127:0] ghash_blk;
reg          ghash_blk_v;
reg          ghash_last;
reg          ghash_init;
wire         ghash_rdy;
wire [127:0] ghash_res;
wire         ghash_done;

aes_gcm_ghash #(.PARALLEL_MODE(0)) u_ghash (
    .clk         (clk),
    .rst_n       (rst_n),
    .H           (H),
    .init        (ghash_init),
    .last_block  (ghash_last),
    .block_in    (ghash_blk),
    .block_valid (ghash_blk_v),
    .block_ready (ghash_rdy),
    .ghash_out   (ghash_res),
    .ghash_valid (ghash_done)
);

// Helper: number of 128-bit blocks (ceiling)
function [31:0] blk_cnt_of;
    input [31:0] bytes;
    begin blk_cnt_of = (bytes == 0) ? 0 : ((bytes + 15) >> 4); end
endfunction

// ── Main FSM ──────────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= ST_IDLE;
        key_r       <= 128'b0;
        H           <= 128'b0;
        E_J0        <= 128'b0;
        J0          <= 128'b0;
        ctr         <= 32'b0;
        aad_blk_rem <= 32'b0;
        pt_blk_rem  <= 32'b0;
        aad_len_r   <= 32'b0;
        pt_len_r    <= 32'b0;
        enc_r       <= 1'b1;
        pt_buf      <= 128'b0;
        lat_cnt     <= 5'b0;
        aes_in      <= 128'b0;
        aes_vin     <= 1'b0;
        ghash_blk   <= 128'b0;
        ghash_blk_v <= 1'b0;
        ghash_last  <= 1'b0;
        ghash_init  <= 1'b0;
        aad_ready   <= 1'b0;
        pt_ready    <= 1'b0;
        ct_out      <= 128'b0;
        ct_valid    <= 1'b0;
        tag_out     <= 128'b0;
        tag_valid   <= 1'b0;
        tag_match   <= 1'b0;
    end else begin
        // Default: deassert one-cycle strobes
        aes_vin     <= 1'b0;
        ghash_blk_v <= 1'b0;
        ghash_init  <= 1'b0;
        ghash_last  <= 1'b0;
        ct_valid    <= 1'b0;
        tag_valid   <= 1'b0;
        aad_ready   <= 1'b0;
        pt_ready    <= 1'b0;

        case (state)
        //----------------------------------------------------------------------
        ST_IDLE: begin
            if (key_valid) begin
                key_r   <= key;
                // Launch AES(0) for H
                aes_in  <= 128'b0;
                aes_vin <= 1'b1;
                lat_cnt <= AES_LAT[4:0];
                state   <= ST_WAIT_H;
            end
        end

        //----------------------------------------------------------------------
        ST_WAIT_H: begin
            if (lat_cnt > 0) begin
                lat_cnt <= lat_cnt - 1'b1;
            end else begin
                H     <= aes_out;   // AES_K(0) is now in aes_out
                state <= ST_READY;
            end
        end

        //----------------------------------------------------------------------
        ST_READY: begin
            if (start) begin
                // Build J0 = IV || 0x00000001
                J0        <= {iv, 32'h00000001};
                aad_len_r <= aad_len;
                pt_len_r  <= pt_len;
                enc_r     <= encrypt;
                aad_blk_rem <= blk_cnt_of(aad_len);
                pt_blk_rem  <= blk_cnt_of(pt_len);
                ctr         <= 32'd1;
                // Launch AES(J0) for E_J0
                aes_in  <= {iv, 32'h00000001};
                aes_vin <= 1'b1;
                lat_cnt <= AES_LAT[4:0];
                state   <= ST_WAIT_EJ0;
            end
        end

        //----------------------------------------------------------------------
        ST_WAIT_EJ0: begin
            if (lat_cnt > 0) begin
                lat_cnt <= lat_cnt - 1'b1;
            end else begin
                E_J0  <= aes_out;   // AES_K(J0) is now in aes_out
                // Initialise GHASH
                ghash_init <= 1'b1;
                state <= ST_GHASH_INIT;
            end
        end

        //----------------------------------------------------------------------
        ST_GHASH_INIT: begin
            // ghash_init was asserted last cycle; GHASH is now ready
            if (aad_blk_rem > 0)
                state <= ST_AAD;
            else if (pt_blk_rem > 0)
                state <= ST_CT_SEND;
            else
                state <= ST_LENGTHS;
        end

        //----------------------------------------------------------------------
        ST_AAD: begin
            aad_ready <= 1'b1;
            if (aad_valid && ghash_rdy) begin
                ghash_blk   <= aad_in;
                ghash_blk_v <= 1'b1;
                aad_blk_rem <= aad_blk_rem - 1'b1;
                if (aad_blk_rem == 32'd1) begin
                    aad_ready <= 1'b0;
                    if (pt_blk_rem > 0)
                        state <= ST_CT_SEND;
                    else
                        state <= ST_LENGTHS;
                end
            end
        end

        //----------------------------------------------------------------------
        ST_CT_SEND: begin
            // Accept PT, send counter block to AES
            pt_ready <= 1'b1;
            if (pt_valid) begin
                pt_buf  <= pt_in;
                // Counter block J0 + ctr (increment low 32 bits)
                aes_in  <= {J0[127:32], J0[31:0] + ctr};
                aes_vin <= 1'b1;
                ctr     <= ctr + 1'b1;
                lat_cnt <= AES_LAT[4:0];
                pt_ready <= 1'b0;
                state   <= ST_CT_WAIT;
            end
        end

        //----------------------------------------------------------------------
        ST_CT_WAIT: begin
            if (lat_cnt > 0) begin
                lat_cnt <= lat_cnt - 1'b1;
            end else begin
                // Keystream ready – XOR with buffered PT
                ct_out   <= aes_out ^ pt_buf;
                ct_valid <= 1'b1;
                // Feed ciphertext (or plaintext for decryption) to GHASH
                ghash_blk   <= enc_r ? (aes_out ^ pt_buf) : pt_buf;
                ghash_blk_v <= 1'b1;
                pt_blk_rem  <= pt_blk_rem - 1'b1;
                if (pt_blk_rem == 32'd1)
                    state <= ST_LENGTHS;
                else
                    state <= ST_CT_SEND;
            end
        end

        //----------------------------------------------------------------------
        ST_LENGTHS: begin
            // Wait 1 cycle for any in-flight GHASH to complete (always ready
            // in sequential mode, but be safe)
            if (ghash_rdy) begin
                // Length block: { len(AAD) in bits [63:0], len(PT) in bits [63:0] }
                ghash_blk   <= { {32'b0, aad_len_r} << 3, {32'b0, pt_len_r} << 3 };
                ghash_blk_v <= 1'b1;
                ghash_last  <= 1'b1;
                state       <= ST_WAIT_GHASH;
            end
        end

        //----------------------------------------------------------------------
        ST_WAIT_GHASH: begin
            if (ghash_done) begin
                tag_out <= ghash_res ^ E_J0;
                state   <= ST_TAG;
            end
        end

        //----------------------------------------------------------------------
        ST_TAG: begin
            tag_valid <= 1'b1;
            if (!encrypt)
                tag_match <= ((ghash_res ^ E_J0) == tag_in);
            state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
        endcase
    end
end

endmodule
