`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Compact AES-128 Core V2 - Simpler and More Reliable
//
// Strategy: Reuse working modules but minimize storage
// - Process one column at a time (serialize the columns)
// - Store only current and next round key (not all 44 words)
// - Single SubBytes/MixColumns instance (time-multiplexed)
//
// Expected Resources:
// - LUTs: ~450-500
// - FFs: ~350-450
//////////////////////////////////////////////////////////////////////////////////

module aes_core_compact_v2(
    input wire         clk,
    input wire         rst_n,
    input wire         start,
    input wire         enc_dec,
    input wire [127:0] data_in,
    input wire [127:0] key_in,
    output reg [127:0] data_out,
    output reg         ready
);

////////////////////////////////////////////////////////////////////////////////
// State Machine
////////////////////////////////////////////////////////////////////////////////
localparam IDLE      = 3'd0;
localparam LOAD_KEY  = 3'd1;
localparam ROUND0    = 3'd2;
localparam PROCESS   = 3'd3;
localparam DONE      = 3'd4;

reg [2:0]   state;
reg [3:0]   round;
reg [1:0]   col_cnt;
reg [127:0] aes_state;
reg         mode;

////////////////////////////////////////////////////////////////////////////////
// Key Expansion - uses existing module
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

////////////////////////////////////////////////////////////////////////////////
// Round Key Storage - Only current round (4 words)
////////////////////////////////////////////////////////////////////////////////
reg [31:0] rkey [0:3];
reg [1:0] key_load_cnt;
wire [5:0] target_key_addr = round * 4 + col_cnt;

////////////////////////////////////////////////////////////////////////////////
// Column Processing - Single Instance
////////////////////////////////////////////////////////////////////////////////
wire [31:0] state_col = aes_state[127 - col_cnt*32 -: 32];
wire [31:0] state_col_keyed = state_col ^ rkey[col_cnt];

// SubBytes
wire [31:0] col_subbed;
aes_subbytes_32bit subbytes (
    .data_in(state_col),
    .enc_dec(mode),
    .data_out(col_subbed)
);

// ShiftRows
wire [127:0] state_shifted;
aes_shiftrows_128bit shiftrows (
    .data_in(aes_state),
    .enc_dec(mode),
    .data_out(state_shifted)
);

wire [31:0] shifted_col = state_shifted[127 - col_cnt*32 -: 32];

// MixColumns
wire [31:0] col_mixed;
aes_mixcolumns_32bit mixcols (
    .data_in(shifted_col),
    .enc_dec(mode),
    .data_out(col_mixed)
);

////////////////////////////////////////////////////////////////////////////////
// Processing Control
////////////////////////////////////////////////////////////////////////////////
reg [1:0] phase;  // 0=SubBytes, 1=ShiftRows, 2=MixColumns, 3=AddRoundKey
wire is_last_round = (round == 4'd10);

////////////////////////////////////////////////////////////////////////////////
// Main FSM
////////////////////////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        round <= 4'd0;
        col_cnt <= 2'd0;
        phase <= 2'd0;
        aes_state <= 128'd0;
        data_out <= 128'd0;
        ready <= 1'b1;
        mode <= 1'b1;
        key_start <= 1'b0;
        key_next <= 1'b0;
        key_load_cnt <= 2'd0;
        rkey[0] <= 32'd0;
        rkey[1] <= 32'd0;
        rkey[2] <= 32'd0;
        rkey[3] <= 32'd0;
    end else begin
        key_next <= 1'b0;  // Default

        case (state)
            ////////////////////////////////////////////////////////////////
            // IDLE
            ////////////////////////////////////////////////////////////////
            IDLE: begin
                ready <= 1'b1;
                if (start) begin
                    aes_state <= data_in;
                    mode <= enc_dec;
                    round <= 4'd0;
                    col_cnt <= 2'd0;
                    phase <= 2'd0;
                    key_start <= 1'b1;
                    key_load_cnt <= 2'd0;
                    state <= LOAD_KEY;
                    ready <= 1'b0;
                end
            end

            ////////////////////////////////////////////////////////////////
            // LOAD_KEY: Load round 0 key
            ////////////////////////////////////////////////////////////////
            LOAD_KEY: begin
                key_start <= 1'b0;

                if (key_ready) begin
                    if (key_addr == target_key_addr) begin
                        rkey[key_load_cnt] <= key_word;

                        if (key_load_cnt == 2'd3) begin
                            // All 4 words loaded
                            state <= ROUND0;
                            col_cnt <= 2'd0;
                        end else begin
                            key_load_cnt <= key_load_cnt + 1'b1;
                            key_next <= 1'b1;
                        end
                    end else begin
                        key_next <= 1'b1;
                    end
                end
            end

            ////////////////////////////////////////////////////////////////
            // ROUND0: Initial AddRoundKey
            ////////////////////////////////////////////////////////////////
            ROUND0: begin
                aes_state[127 - col_cnt*32 -: 32] <= state_col_keyed;

                if (col_cnt == 2'd3) begin
                    round <= 4'd1;
                    col_cnt <= 2'd0;
                    phase <= 2'd0;
                    key_load_cnt <= 2'd0;
                    state <= LOAD_KEY;  // Load next round key
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end

            ////////////////////////////////////////////////////////////////
            // PROCESS: Main rounds
            ////////////////////////////////////////////////////////////////
            PROCESS: begin
                case (phase)
                    // Phase 0: SubBytes
                    2'd0: begin
                        aes_state[127 - col_cnt*32 -: 32] <= col_subbed;

                        if (col_cnt == 2'd3) begin
                            col_cnt <= 2'd0;
                            phase <= 2'd1;
                        end else begin
                            col_cnt <= col_cnt + 1'b1;
                        end
                    end

                    // Phase 1: ShiftRows + MixColumns (or just ShiftRows if last round)
                    2'd1: begin
                        if (is_last_round) begin
                            aes_state[127 - col_cnt*32 -: 32] <= shifted_col ^ rkey[col_cnt];
                        end else begin
                            aes_state[127 - col_cnt*32 -: 32] <= col_mixed ^ rkey[col_cnt];
                        end

                        if (col_cnt == 2'd3) begin
                            if (is_last_round) begin
                                state <= DONE;
                            end else begin
                                round <= round + 1'b1;
                                col_cnt <= 2'd0;
                                phase <= 2'd0;
                                key_load_cnt <= 2'd0;
                                state <= LOAD_KEY;
                            end
                        end else begin
                            col_cnt <= col_cnt + 1'b1;
                        end
                    end
                endcase
            end

            ////////////////////////////////////////////////////////////////
            // DONE
            ////////////////////////////////////////////////////////////////
            DONE: begin
                data_out <= aes_state;
                ready <= 1'b1;
                if (!start) begin
                    state <= IDLE;
                end
            end
        endcase
    end
end

endmodule
