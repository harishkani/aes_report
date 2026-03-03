`timescale 1ns / 1ps
//==============================================================================
// Module: aes_gcm_top
//
// Description:
//   Complete AES-128-GCM Authenticated Encryption with Associated Data (AEAD)
//   top-level module, optimised for maximum throughput.
//
//   Implements NIST SP 800-38D GCM specification:
//     Encryption: C_i = P_i XOR AES_K(J_0 + i)
//     Authentication: T = GHASH_H(A || C || len(A) || len(C)) XOR AES_K(J_0)
//
// Architecture Overview:
//
//   ┌─────────────────────────────────────────────────────────┐
//   │                    aes_gcm_top                          │
//   │                                                         │
//   │  ┌──────────────────┐    ┌────────────────────────┐    │
//   │  │  Key Schedule    │    │  CTR Block Generator   │    │
//   │  │  (combinatorial) │    │  (J0 + counter[31:0])  │    │
//   │  └────────┬─────────┘    └──────────┬─────────────┘    │
//   │           │ rk[0..10]               │ CTR block        │
//   │           ▼                         ▼                   │
//   │  ┌──────────────────────────────────────────┐          │
//   │  │   Pipelined AES-128 Core (10 stages)     │          │
//   │  │   Throughput: 1 block/cycle @ 200 MHz    │          │
//   │  └────────────────────┬─────────────────────┘          │
//   │                       │ keystream block                 │
//   │                       ▼                                 │
//   │               XOR with plaintext                        │
//   │               → ciphertext                              │
//   │                       │                                 │
//   │                       ▼                                 │
//   │  ┌──────────────────────────────────────────┐          │
//   │  │     GHASH Engine (PARALLEL_MODE=0)        │          │
//   │  │     Phase 1: process AAD blocks           │          │
//   │  │     Phase 2: process ciphertext blocks    │          │
//   │  │     Phase 3: process lengths block        │          │
//   │  └────────────────────┬─────────────────────┘          │
//   │                       │                                 │
//   │              XOR with AES_K(J0)                         │
//   │                       │                                 │
//   │                       ▼                                 │
//   │               Authentication Tag T[127:0]               │
//   └─────────────────────────────────────────────────────────┘
//
// Throughput:
//   Encryption:    1 × 128-bit block per clock cycle (after pipeline fill)
//   Authentication: 1 block per 4 cycles (sequential GHASH mode)
//                  Combined rate limited by GHASH = 1/4 throughput
//
//   For full 1-block/cycle rate, use PARALLEL_MODE=1 in aes_gcm_ghash
//   (requires 5× the GF multiplier resources).
//
// Parameters:
//   IV_BITS       Width of the initialisation vector (default 96 per NIST)
//
// Interface:
//   -- Control --
//   clk, rst_n           System clock and active-low synchronous reset
//   key[127:0]           128-bit AES key (must be stable when key_valid=1)
//   key_valid            Strobe: latch the key and precompute H & J0
//   iv[95:0]             96-bit initialisation vector (nonce)
//   aad_len[31:0]        Length of AAD in bytes (0 if no AAD)
//   pt_len[31:0]         Length of plaintext in bytes
//   encrypt              1=encrypt, 0=decrypt (tag verify)
//   start                Begin processing
//
//   -- AAD input stream --
//   aad_in[127:0]        AAD block (zero-padded if < 128 bits)
//   aad_valid            AAD block valid
//   aad_ready            Module ready for AAD
//
//   -- Plaintext/Ciphertext stream --
//   pt_in[127:0]         Plaintext (encrypt=1) or ciphertext (encrypt=0)
//   pt_valid             Input valid
//   pt_ready             Ready to receive input
//   ct_out[127:0]        Ciphertext (encrypt=1) or plaintext (encrypt=0)
//   ct_valid             ct_out valid
//
//   -- Tag --
//   tag_out[127:0]       128-bit authentication tag
//   tag_valid            tag_out is valid
//   tag_match            (decrypt mode) 1 = received tag matches computed tag
//   tag_in[127:0]        (decrypt mode) expected tag to verify
//
// State Machine:
//   IDLE → KEY_SETUP → AAD_PROCESS → CT_PROCESS → FINALIZE → TAG_OUT
//
// Notes:
//   - For 96-bit IV: J0 = IV || 0x00000001 (per NIST SP 800-38D Sec 7.1)
//   - Counter increments the rightmost 32 bits (big-endian)
//   - AAD and plaintext must be presented in complete 128-bit blocks
//     (last partial block zero-padded)
//   - tag_out is always 128 bits; truncate externally if needed
//
// References:
//   - NIST SP 800-38D (November 2007)
//   - IEEE 802.1AE (MACsec)
//   - Ferguson, "Authentication weaknesses in GCM", 2005 (nonce-reuse warning)
//==============================================================================

module aes_gcm_top (
    input  wire        clk,
    input  wire        rst_n,

    // Key setup
    input  wire [127:0] key,
    input  wire         key_valid,

    // Nonce / IV (96-bit recommended per NIST)
    input  wire [95:0]  iv,

    // Lengths (in bytes; must be set before start)
    input  wire [31:0]  aad_len,
    input  wire [31:0]  pt_len,

    // Mode and control
    input  wire         encrypt,    // 1=encrypt, 0=decrypt
    input  wire         start,      // Begin operation

    // AAD stream (128-bit wide, zero-pad final partial block)
    input  wire [127:0] aad_in,
    input  wire         aad_valid,
    output wire         aad_ready,

    // Plaintext/Ciphertext stream
    input  wire [127:0] pt_in,
    input  wire         pt_valid,
    output wire         pt_ready,
    output reg  [127:0] ct_out,
    output reg          ct_valid,

    // Tag
    output reg  [127:0] tag_out,
    output reg          tag_valid,
    input  wire [127:0] tag_in,     // For decryption verification
    output reg          tag_match   // 1 = tags match (decrypt mode)
);

//==============================================================================
// State machine encoding
//==============================================================================
localparam [3:0]
    ST_IDLE        = 4'd0,
    ST_KEY_SETUP   = 4'd1,   // Generate H = AES_K(0) via pipelined AES
    ST_AAD_PROCESS = 4'd2,   // Feed AAD blocks into GHASH
    ST_CT_PROCESS  = 4'd3,   // Encrypt/Decrypt + feed CT into GHASH
    ST_FINAL_BLOCK = 4'd4,   // GHASH the lengths block
    ST_TAG_WAIT    = 4'd5,   // Wait for tag computation to complete
    ST_TAG_OUT     = 4'd6;   // Output the tag

reg [3:0] state, next_state;

//==============================================================================
// Key schedule
//==============================================================================
wire [127:0] rk [0:10];

aes_gcm_key_schedule u_keysched (
    .key (key_latched),
    .rk  (rk)
);

reg [127:0] key_latched;
reg         key_ready;     // Key schedule is ready

//==============================================================================
// Pipelined AES core (shared: used for H computation, J0 encryption, CTR)
//==============================================================================
reg  [127:0] aes_data_in;
reg          aes_data_valid_in;
wire [127:0] aes_data_out;
wire         aes_data_valid_out;

aes_gcm_pipelined_aes u_aes (
    .clk           (clk),
    .rst_n         (rst_n),
    .data_in       (aes_data_in),
    .data_valid_in (aes_data_valid_in),
    .rk            (rk),
    .data_out      (aes_data_out),
    .data_valid_out(aes_data_valid_out)
);

//==============================================================================
// Counter block generation
// J0 = IV[95:0] || 32'h00000001  (96-bit IV, NIST sec 7.1)
// CTR blocks for encryption: J0 + 1, J0 + 2, ... (increment low 32 bits)
//==============================================================================
reg [127:0] J0;            // Initial counter block
reg [31:0]  ctr;           // Counter value (starts at 1 for keystream)
wire [127:0] ctr_block = {J0[127:32], J0[31:0] + ctr};

//==============================================================================
// GHASH engine
//==============================================================================
reg  [127:0] H;             // Hash subkey = AES_K(0^128)
reg          H_valid;

reg  [127:0] ghash_block_in;
reg          ghash_block_valid;
reg          ghash_last_block;
wire         ghash_block_ready;
wire [127:0] ghash_out;
wire         ghash_valid;
reg          ghash_init;

aes_gcm_ghash #(.PARALLEL_MODE(0)) u_ghash (
    .clk         (clk),
    .rst_n       (rst_n),
    .H           (H),
    .init        (ghash_init),
    .last_block  (ghash_last_block),
    .block_in    (ghash_block_in),
    .block_valid (ghash_block_valid),
    .block_ready (ghash_block_ready),
    .ghash_out   (ghash_out),
    .ghash_valid (ghash_valid)
);

//==============================================================================
// AES_K(J0) computation for tag generation
//==============================================================================
reg [127:0] E_J0;           // AES_K(J0) result
reg         E_J0_valid;     // AES_K(J0) has been computed

//==============================================================================
// Counters for block processing
//==============================================================================
reg [31:0] aad_blocks_rem;   // Remaining AAD 128-bit blocks
reg [31:0] pt_blocks_rem;    // Remaining plaintext 128-bit blocks
reg [31:0] aad_len_r;
reg [31:0] pt_len_r;

// Number of 128-bit blocks (ceiling division)
function [31:0] blocks_of;
    input [31:0] bytes;
    begin
        blocks_of = (bytes + 31'd15) >> 4;
    end
endfunction

//==============================================================================
// Pipeline delay tracking for CTR encryption
//==============================================================================
// We need to track that ctr_block is sent to AES and the output comes back
// 10 cycles later (plus 1 for the input register).
localparam AES_LATENCY = 11;
reg [10:0] ctr_valid_pipe;   // Shift register tracking valid CTR in flight
reg [127:0] pt_pipe [0:10];  // Pipeline delay for plaintext
reg [127:0] ghash_pipe [0:10]; // Track which ct to send to GHASH

//==============================================================================
// Main FSM — synchronous
//==============================================================================
integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= ST_IDLE;
        key_latched     <= 128'b0;
        key_ready       <= 1'b0;
        H               <= 128'b0;
        H_valid         <= 1'b0;
        J0              <= 128'b0;
        ctr             <= 32'b0;
        E_J0            <= 128'b0;
        E_J0_valid      <= 1'b0;
        aes_data_in     <= 128'b0;
        aes_data_valid_in <= 1'b0;
        ghash_init      <= 1'b0;
        ghash_block_in  <= 128'b0;
        ghash_block_valid <= 1'b0;
        ghash_last_block  <= 1'b0;
        ct_out          <= 128'b0;
        ct_valid        <= 1'b0;
        tag_out         <= 128'b0;
        tag_valid       <= 1'b0;
        tag_match       <= 1'b0;
        aad_blocks_rem  <= 32'b0;
        pt_blocks_rem   <= 32'b0;
        aad_len_r       <= 32'b0;
        pt_len_r        <= 32'b0;
        ctr_valid_pipe  <= 11'b0;
        for (i = 0; i <= 10; i = i + 1) begin
            pt_pipe[i]    <= 128'b0;
            ghash_pipe[i] <= 128'b0;
        end
    end else begin
        // Default: deassert strobes
        aes_data_valid_in <= 1'b0;
        ghash_block_valid <= 1'b0;
        ghash_init        <= 1'b0;
        ghash_last_block  <= 1'b0;
        ct_valid          <= 1'b0;
        tag_valid         <= 1'b0;

        // Propagate plaintext pipeline
        for (i = 10; i >= 1; i = i - 1) begin
            pt_pipe[i]    <= pt_pipe[i-1];
            ghash_pipe[i] <= ghash_pipe[i-1];
        end
        ctr_valid_pipe <= {ctr_valid_pipe[9:0], 1'b0};

        case (state)
            //------------------------------------------------------------------
            ST_IDLE: begin
                tag_valid  <= 1'b0;
                tag_match  <= 1'b0;
                E_J0_valid <= 1'b0;
                H_valid    <= 1'b0;

                if (key_valid) begin
                    key_latched <= key;
                    key_ready   <= 1'b0;
                    state       <= ST_KEY_SETUP;
                    // Step 1: compute H = AES_K(0^128)
                    aes_data_in       <= 128'b0;
                    aes_data_valid_in <= 1'b1;
                end
            end

            //------------------------------------------------------------------
            ST_KEY_SETUP: begin
                // Wait for AES(0) = H to come out of the pipeline
                if (aes_data_valid_out && !H_valid) begin
                    H       <= aes_data_out;
                    H_valid <= 1'b1;
                    key_ready <= 1'b1;
                end

                if (H_valid && start) begin
                    // Form J0 = IV[95:0] || 32'h00000001
                    J0 <= {iv, 32'h00000001};
                    // Compute E_J0 = AES_K(J0)
                    aes_data_in       <= {iv, 32'h00000001};
                    aes_data_valid_in <= 1'b1;
                    // Store lengths, set up block counts
                    aad_len_r      <= aad_len;
                    pt_len_r       <= pt_len;
                    aad_blocks_rem <= blocks_of(aad_len);
                    pt_blocks_rem  <= blocks_of(pt_len);
                    // Initialise GHASH
                    ghash_init <= 1'b1;
                    ctr        <= 32'd1;  // First keystream counter
                    E_J0_valid <= 1'b0;

                    if (aad_len == 0)
                        state <= ST_CT_PROCESS;
                    else
                        state <= ST_AAD_PROCESS;
                end
            end

            //------------------------------------------------------------------
            ST_AAD_PROCESS: begin
                // Capture E_J0 when it arrives from the pipeline (we sent it above)
                if (aes_data_valid_out && !E_J0_valid) begin
                    E_J0       <= aes_data_out;
                    E_J0_valid <= 1'b1;
                end

                // Feed AAD blocks into GHASH
                if (aad_valid && ghash_block_ready && aad_blocks_rem > 0) begin
                    ghash_block_in    <= aad_in;
                    ghash_block_valid <= 1'b1;
                    ghash_last_block  <= (aad_blocks_rem == 32'd1) ? 1'b1 : 1'b0;
                    aad_blocks_rem    <= aad_blocks_rem - 1'b1;
                    if (aad_blocks_rem == 32'd1)
                        state <= ST_CT_PROCESS;
                end
            end

            //------------------------------------------------------------------
            ST_CT_PROCESS: begin
                // Capture E_J0 when it arrives from the pipeline
                if (aes_data_valid_out && !E_J0_valid) begin
                    E_J0       <= aes_data_out;
                    E_J0_valid <= 1'b1;
                end

                // Issue CTR blocks into AES pipeline
                if (pt_valid && pt_blocks_rem > 0) begin
                    // Send counter block to AES
                    aes_data_in       <= {J0[127:32], J0[31:0] + ctr};
                    aes_data_valid_in <= 1'b1;
                    ctr               <= ctr + 1'b1;
                    pt_blocks_rem     <= pt_blocks_rem - 1'b1;
                    // Delay plaintext in pipeline to XOR with keystream
                    pt_pipe[0]        <= pt_in;
                    ctr_valid_pipe[0] <= 1'b1;
                end

                // XOR keystream (AES output) with delayed plaintext
                if (aes_data_valid_out && ctr_valid_pipe[10]) begin
                    ct_out   <= encrypt ? (aes_data_out ^ pt_pipe[10])
                                        : (aes_data_out ^ pt_pipe[10]);
                    ct_valid <= 1'b1;

                    // Send ciphertext to GHASH
                    ghash_pipe[0] <= encrypt ? (aes_data_out ^ pt_pipe[10]) : pt_pipe[10];
                    if (ghash_block_ready) begin
                        ghash_block_in    <= ghash_pipe[0];
                        ghash_block_valid <= 1'b1;
                        ghash_last_block  <= (pt_blocks_rem == 32'd0) ? 1'b1 : 1'b0;
                    end
                end

                if (pt_blocks_rem == 32'd0 && !pt_valid)
                    state <= ST_FINAL_BLOCK;
            end

            //------------------------------------------------------------------
            ST_FINAL_BLOCK: begin
                // GHASH the length block: len(A) || len(C) in bits, 64 bits each
                // = {aad_len*8 [63:0], pt_len*8 [63:0]}
                if (ghash_block_ready) begin
                    ghash_block_in    <= {aad_len_r * 8, pt_len_r * 8};
                    ghash_block_valid <= 1'b1;
                    ghash_last_block  <= 1'b1;
                    state             <= ST_TAG_WAIT;
                end
            end

            //------------------------------------------------------------------
            ST_TAG_WAIT: begin
                // Wait for GHASH to complete
                if (ghash_valid && E_J0_valid) begin
                    tag_out   <= ghash_out ^ E_J0;
                    state     <= ST_TAG_OUT;
                end
            end

            //------------------------------------------------------------------
            ST_TAG_OUT: begin
                tag_valid <= 1'b1;
                if (!encrypt) begin
                    tag_match <= (tag_out == tag_in) ? 1'b1 : 1'b0;
                end
                state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

//==============================================================================
// Ready signals (backpressure)
//==============================================================================
assign aad_ready = (state == ST_AAD_PROCESS) && ghash_block_ready;
assign pt_ready  = (state == ST_CT_PROCESS)  && (pt_blocks_rem > 0);

endmodule
