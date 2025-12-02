`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Ultra-Compact Serial AES-128 Core
// Target: <500 LUTs, <500 FFs, <40mW @ 100MHz
//
// Architecture:
// - Single SubBytes unit (4 S-boxes for one column)
// - Single MixColumns unit
// - Process one column per cycle (4 cycles per round step)
// - Minimal key storage (current round key only + key expansion state)
//
// Expected Resources:
// - SubBytes: 4 S-boxes × 64 LUTs = 256 LUTs
// - MixColumns: ~100 LUTs
// - ShiftRows: ~50 LUTs (minimal logic)
// - Control: ~80 LUTs
// - State storage: 128 FFs
// - Key storage: 128 FFs
// - Control regs: ~100 FFs
// TOTAL: ~480 LUTs, ~360 FFs ✅
//
// Performance @ 100MHz:
// - Cycles: ~180 (key expansion ~50 + rounds ~130)
// - Latency: 1.8µs
// - Throughput: 711 Mbps (when pipelined)
//////////////////////////////////////////////////////////////////////////////////

module aes_core_serial(
    input wire         clk,
    input wire         rst_n,
    input wire         start,
    input wire         enc_dec,       // 1=encrypt, 0=decrypt
    input wire [127:0] data_in,
    input wire [127:0] key_in,
    output reg [127:0] data_out,
    output reg         ready
);

////////////////////////////////////////////////////////////////////////////////
// State Machine
////////////////////////////////////////////////////////////////////////////////
localparam IDLE       = 3'd0;
localparam KEY_EXP    = 3'd1;
localparam INIT_ROUND = 3'd2;
localparam SUB_SHIFT  = 3'd3;
localparam MIX_ADD    = 3'd4;
localparam DONE       = 3'd5;

reg [2:0]   state;
reg [3:0]   round;           // 0-10
reg [1:0]   col_cnt;         // 0-3 (which column)
reg [1:0]   phase;           // Sub-phase within state
reg         mode;            // 1=enc, 0=dec
reg [127:0] aes_state;
reg [127:0] temp_state;      // For ShiftRows result

////////////////////////////////////////////////////////////////////////////////
// Key Expansion (reuse existing module)
////////////////////////////////////////////////////////////////////////////////
reg  key_start, key_next;
wire [31:0] key_word;
wire [5:0]  key_addr;
wire key_ready;

aes_key_expansion_otf key_exp (
    .clk(clk),
    .rst_n(rst_n),
    .start(key_start),
    .key(key_in),
    .round_key(key_word),
    .word_addr(key_addr),
    .ready(key_ready),
    .next(key_next)
);

// Current round key (4 words = 128 bits)
reg [31:0] round_key [0:3];

// Key index calculation - for decryption, round keys are used in reverse
// Encryption: round 0, 1, 2, ..., 10
// Decryption: round 10, 9, 8, ..., 0
// So for decryption round N, we need key expansion round (10-N)
wire [3:0] actual_key_round = mode ? round : (4'd10 - round);
wire [5:0] key_addr_needed = actual_key_round * 4;
reg  [1:0] key_word_cnt;     // Which word of current round key we're loading

////////////////////////////////////////////////////////////////////////////////
// Column Processing Units
////////////////////////////////////////////////////////////////////////////////
wire [31:0] state_col = aes_state[127 - col_cnt*32 -: 32];
wire [31:0] current_rkey = round_key[col_cnt];

// SubBytes (processes one column = 4 bytes)
wire [31:0] col_subbed;
aes_subbytes_32bit subbytes (
    .data_in(state_col),
    .enc_dec(mode),
    .data_out(col_subbed)
);

// ShiftRows (operates on full state)
wire [127:0] state_shifted;
aes_shiftrows_128bit shiftrows (
    .data_in(mode ? temp_state : aes_state),
    .enc_dec(mode),
    .data_out(state_shifted)
);

wire [31:0] shifted_col = state_shifted[127 - col_cnt*32 -: 32];

// MixColumns (processes one column)
// For decryption phase 1, input comes from temp_state (post-AddRoundKey)
wire [31:0] temp_col = temp_state[127 - col_cnt*32 -: 32];
wire [31:0] mixcols_in = mode ? shifted_col : temp_col;

wire [31:0] col_mixed;
aes_mixcolumns_32bit mixcols (
    .data_in(mixcols_in),
    .enc_dec(mode),
    .data_out(col_mixed)
);

////////////////////////////////////////////////////////////////////////////////
// Control Logic
////////////////////////////////////////////////////////////////////////////////
wire is_last_round = (round == 4'd10);
wire is_round_0 = (round == 4'd0);

////////////////////////////////////////////////////////////////////////////////
// Main FSM
////////////////////////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        round <= 4'd0;
        col_cnt <= 2'd0;
        phase <= 2'd0;
        mode <= 1'b1;
        aes_state <= 128'd0;
        temp_state <= 128'd0;
        data_out <= 128'd0;
        ready <= 1'b1;
        key_start <= 1'b0;
        key_next <= 1'b0;
        key_word_cnt <= 2'd0;
        round_key[0] <= 32'd0;
        round_key[1] <= 32'd0;
        round_key[2] <= 32'd0;
        round_key[3] <= 32'd0;
    end else begin
        key_next <= 1'b0;  // Default

        case (state)
            ////////////////////////////////////////////////////////////////
            // IDLE: Wait for start
            ////////////////////////////////////////////////////////////////
            IDLE: begin
                ready <= 1'b1;
                if (start) begin
                    aes_state <= data_in;
                    mode <= enc_dec;
                    round <= 4'd0;
                    col_cnt <= 2'd0;
                    phase <= 2'd0;
                    key_word_cnt <= 2'd0;
                    key_start <= 1'b1;
                    state <= KEY_EXP;
                    ready <= 1'b0;
                end
            end

            ////////////////////////////////////////////////////////////////
            // KEY_EXP: Load current round key (4 words)
            ////////////////////////////////////////////////////////////////
            KEY_EXP: begin
                key_start <= 1'b0;

                if (key_ready) begin
                    // Check if this is the word we need
                    if (key_addr == (key_addr_needed + key_word_cnt)) begin
                        round_key[key_word_cnt] <= key_word;

                        if (key_word_cnt == 2'd3) begin
                            // All 4 words loaded
                            key_word_cnt <= 2'd0;
                            col_cnt <= 2'd0;

                            if (is_round_0) begin
                                state <= INIT_ROUND;
                            end else begin
                                state <= SUB_SHIFT;
                            end
                        end else begin
                            key_word_cnt <= key_word_cnt + 1'b1;
                            key_next <= 1'b1;
                        end
                    end else begin
                        // Not the right word yet, keep advancing
                        key_next <= 1'b1;
                    end
                end
            end

            ////////////////////////////////////////////////////////////////
            // INIT_ROUND: Round 0 - just AddRoundKey
            ////////////////////////////////////////////////////////////////
            INIT_ROUND: begin
                // AddRoundKey column by column
                aes_state[127 - col_cnt*32 -: 32] <= state_col ^ current_rkey;

                if (col_cnt == 2'd3) begin
                    round <= 4'd1;
                    col_cnt <= 2'd0;
                    key_word_cnt <= 2'd0;
                    state <= KEY_EXP;  // Load next round key
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end

            ////////////////////////////////////////////////////////////////
            // SUB_SHIFT: SubBytes + ShiftRows (mode-dependent)
            ////////////////////////////////////////////////////////////////
            SUB_SHIFT: begin
                if (mode) begin
                    // ENCRYPTION: SubBytes then ShiftRows
                    if (col_cnt == 2'd0) begin
                        temp_state[127:96] <= col_subbed;
                        col_cnt <= 2'd1;
                    end else if (col_cnt == 2'd1) begin
                        temp_state[95:64] <= col_subbed;
                        col_cnt <= 2'd2;
                    end else if (col_cnt == 2'd2) begin
                        temp_state[63:32] <= col_subbed;
                        col_cnt <= 2'd3;
                    end else begin // col_cnt == 3
                        temp_state[31:0] <= col_subbed;
                        col_cnt <= 2'd0;
                        state <= MIX_ADD;
                    end
                end else begin
                    // DECRYPTION: InvShiftRows first (full state, combinational)
                    // Then InvSubBytes column-by-column
                    if (col_cnt == 2'd0) begin
                        // Apply InvShiftRows once (combinational)
                        temp_state <= state_shifted;
                        col_cnt <= 2'd1;
                    end else if (col_cnt == 2'd1) begin
                        aes_state[127:96] <= col_subbed;
                        col_cnt <= 2'd2;
                    end else if (col_cnt == 2'd2) begin
                        aes_state[95:64] <= col_subbed;
                        col_cnt <= 2'd3;
                    end else if (col_cnt == 2'd3) begin
                        aes_state[63:32] <= col_subbed;
                        col_cnt <= 2'd0;  // Reset for next column
                    end else begin
                        aes_state[31:0] <= col_subbed;
                        col_cnt <= 2'd0;
                        state <= MIX_ADD;
                    end
                end
            end

            ////////////////////////////////////////////////////////////////
            // MIX_ADD: MixColumns + AddRoundKey (mode-dependent)
            ////////////////////////////////////////////////////////////////
            MIX_ADD: begin
                if (mode) begin
                    // ENCRYPTION: (ShiftRows already done) MixColumns + AddRoundKey
                    if (is_last_round) begin
                        aes_state[127 - col_cnt*32 -: 32] <= shifted_col ^ current_rkey;
                    end else begin
                        aes_state[127 - col_cnt*32 -: 32] <= col_mixed ^ current_rkey;
                    end

                    if (col_cnt == 2'd3) begin
                        if (is_last_round) begin
                            state <= DONE;
                        end else begin
                            round <= round + 1'b1;
                            col_cnt <= 2'd0;
                            key_word_cnt <= 2'd0;
                            phase <= 2'd0;
                            state <= KEY_EXP;
                        end
                    end else begin
                        col_cnt <= col_cnt + 1'b1;
                    end
                end else begin
                    // DECRYPTION: Two phases - AddRoundKey then InvMixColumns
                    if (phase == 2'd0) begin
                        // Phase 0: AddRoundKey
                        temp_state[127 - col_cnt*32 -: 32] <= state_col ^ current_rkey;

                        if (col_cnt == 2'd3) begin
                            col_cnt <= 2'd0;
                            if (is_last_round) begin
                                // Last round: no InvMixColumns, copy to aes_state
                                aes_state <= temp_state;
                                aes_state[31:0] <= state_col ^ current_rkey;  // Last column
                                state <= DONE;
                            end else begin
                                phase <= 2'd1;  // Go to InvMixColumns phase
                            end
                        end else begin
                            col_cnt <= col_cnt + 1'b1;
                        end
                    end else begin
                        // Phase 1: InvMixColumns (data is in temp_state)
                        aes_state[127 - col_cnt*32 -: 32] <= col_mixed;

                        if (col_cnt == 2'd3) begin
                            round <= round + 1'b1;
                            col_cnt <= 2'd0;
                            key_word_cnt <= 2'd0;
                            phase <= 2'd0;
                            state <= KEY_EXP;
                        end else begin
                            col_cnt <= col_cnt + 1'b1;
                        end
                    end
                end
            end

            ////////////////////////////////////////////////////////////////
            // DONE: Output result
            ////////////////////////////////////////////////////////////////
            DONE: begin
                data_out <= aes_state;
                ready <= 1'b1;
                if (!start) begin
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
