`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// AES-128 Core - FIXED Version - SYNTHESIZABLE
// Handles both encryption and decryption
// NO RAM inference - stores keys as shift register
////////////////////////////////////////////////////////////////////////////////

module aes_core_fixed(
    input wire         clk,
    input wire         rst_n,
    input wire         start,
    input wire         enc_dec,      // 1=encrypt, 0=decrypt
    input wire [127:0] data_in,
    input wire [127:0] key_in,
    output reg [127:0] data_out,
    output reg         ready
);

////////////////////////////////////////////////////////////////////////////////
// State Machine Parameters
////////////////////////////////////////////////////////////////////////////////
localparam IDLE           = 4'd0;
localparam KEY_EXPAND     = 4'd1;
localparam ROUND0         = 4'd2;
localparam ENC_SUB        = 4'd3;
localparam ENC_SHIFT_MIX  = 4'd4;
localparam DEC_SHIFT_SUB  = 4'd5;
localparam DEC_ADD_MIX    = 4'd6;
localparam DONE           = 4'd7;

////////////////////////////////////////////////////////////////////////////////
// Registers and Wires
////////////////////////////////////////////////////////////////////////////////
reg [3:0]   state;
reg [3:0]   round_cnt;
reg [1:0]   col_cnt;
reg [1:0]   phase;
reg [127:0] aes_state;
reg [127:0] temp_state;
reg         enc_dec_reg;

// Key expansion interface
reg         key_start;
reg         key_next;
wire [31:0] key_word;
wire [5:0]  key_addr;
wire        key_ready;

// Round key storage - using individual registers to avoid RAM inference
reg [31:0] rk00, rk01, rk02, rk03, rk04, rk05, rk06, rk07, rk08, rk09;
reg [31:0] rk10, rk11, rk12, rk13, rk14, rk15, rk16, rk17, rk18, rk19;
reg [31:0] rk20, rk21, rk22, rk23, rk24, rk25, rk26, rk27, rk28, rk29;
reg [31:0] rk30, rk31, rk32, rk33, rk34, rk35, rk36, rk37, rk38, rk39;
reg [31:0] rk40, rk41, rk42, rk43;

////////////////////////////////////////////////////////////////////////////////
// Key Expansion Module Instance
////////////////////////////////////////////////////////////////////////////////
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
// Round Key Selection Logic
////////////////////////////////////////////////////////////////////////////////
wire [5:0] key_index = enc_dec_reg ? 
                       (round_cnt * 4 + col_cnt) : 
                       ((10 - round_cnt) * 4 + col_cnt);

reg [31:0] current_rkey;

always @(*) begin
    case (key_index)
        6'd0:  current_rkey = rk00;  6'd1:  current_rkey = rk01;
        6'd2:  current_rkey = rk02;  6'd3:  current_rkey = rk03;
        6'd4:  current_rkey = rk04;  6'd5:  current_rkey = rk05;
        6'd6:  current_rkey = rk06;  6'd7:  current_rkey = rk07;
        6'd8:  current_rkey = rk08;  6'd9:  current_rkey = rk09;
        6'd10: current_rkey = rk10;  6'd11: current_rkey = rk11;
        6'd12: current_rkey = rk12;  6'd13: current_rkey = rk13;
        6'd14: current_rkey = rk14;  6'd15: current_rkey = rk15;
        6'd16: current_rkey = rk16;  6'd17: current_rkey = rk17;
        6'd18: current_rkey = rk18;  6'd19: current_rkey = rk19;
        6'd20: current_rkey = rk20;  6'd21: current_rkey = rk21;
        6'd22: current_rkey = rk22;  6'd23: current_rkey = rk23;
        6'd24: current_rkey = rk24;  6'd25: current_rkey = rk25;
        6'd26: current_rkey = rk26;  6'd27: current_rkey = rk27;
        6'd28: current_rkey = rk28;  6'd29: current_rkey = rk29;
        6'd30: current_rkey = rk30;  6'd31: current_rkey = rk31;
        6'd32: current_rkey = rk32;  6'd33: current_rkey = rk33;
        6'd34: current_rkey = rk34;  6'd35: current_rkey = rk35;
        6'd36: current_rkey = rk36;  6'd37: current_rkey = rk37;
        6'd38: current_rkey = rk38;  6'd39: current_rkey = rk39;
        6'd40: current_rkey = rk40;  6'd41: current_rkey = rk41;
        6'd42: current_rkey = rk42;  6'd43: current_rkey = rk43;
        default: current_rkey = 32'h0;
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// Column Extraction - Optimized
////////////////////////////////////////////////////////////////////////////////
wire [31:0] state_col = aes_state[127 - col_cnt*32 -: 32];
wire [31:0] temp_col  = temp_state[127 - col_cnt*32 -: 32];

////////////////////////////////////////////////////////////////////////////////
// SubBytes Module Instance
////////////////////////////////////////////////////////////////////////////////
wire [31:0] subbytes_input = (state == DEC_SHIFT_SUB && phase == 2'd1) ? 
                              temp_col : state_col;
wire [31:0] col_subbed;

aes_subbytes_32bit subbytes_inst (
    .data_in(subbytes_input),
    .enc_dec(enc_dec_reg),
    .data_out(col_subbed)
);

////////////////////////////////////////////////////////////////////////////////
// ShiftRows Module Instance
////////////////////////////////////////////////////////////////////////////////
wire [127:0] state_shifted;

aes_shiftrows_128bit shiftrows_inst (
    .data_in(enc_dec_reg ? temp_state : aes_state),
    .enc_dec(enc_dec_reg),
    .data_out(state_shifted)
);

wire [31:0] shifted_col = state_shifted[127 - col_cnt*32 -: 32];

////////////////////////////////////////////////////////////////////////////////
// MixColumns Module Instance
////////////////////////////////////////////////////////////////////////////////
wire [31:0] col_mixed;

aes_mixcolumns_32bit mixcols_inst (
    .data_in(enc_dec_reg ? shifted_col : state_col),
    .enc_dec(enc_dec_reg),
    .data_out(col_mixed)
);

////////////////////////////////////////////////////////////////////////////////
// Control Logic
////////////////////////////////////////////////////////////////////////////////
wire is_last_round = (round_cnt == 4'd10);

////////////////////////////////////////////////////////////////////////////////
// Main State Machine
////////////////////////////////////////////////////////////////////////////////
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        round_cnt   <= 4'd0;
        col_cnt     <= 2'd0;
        phase       <= 2'd0;
        aes_state   <= 128'h0;
        temp_state  <= 128'h0;
        data_out    <= 128'h0;
        ready       <= 1'b0;
        key_start   <= 1'b0;
        key_next    <= 1'b0;
        enc_dec_reg <= 1'b1;

        // Reset all round keys - compact format
        {rk00, rk01, rk02, rk03} <= 128'h0;
        {rk04, rk05, rk06, rk07} <= 128'h0;
        {rk08, rk09, rk10, rk11} <= 128'h0;
        {rk12, rk13, rk14, rk15} <= 128'h0;
        {rk16, rk17, rk18, rk19} <= 128'h0;
        {rk20, rk21, rk22, rk23} <= 128'h0;
        {rk24, rk25, rk26, rk27} <= 128'h0;
        {rk28, rk29, rk30, rk31} <= 128'h0;
        {rk32, rk33, rk34, rk35} <= 128'h0;
        {rk36, rk37, rk38, rk39} <= 128'h0;
        {rk40, rk41, rk42, rk43} <= 128'h0;
    end else begin
        // Default: clear control signals
        key_next <= 1'b0;
        
        case (state)
            ////////////////////////////////////////////////////////////////////////
            // IDLE: Wait for start signal
            ////////////////////////////////////////////////////////////////////////
            IDLE: begin
                ready <= 1'b0;
                if (start) begin
                    aes_state   <= data_in;
                    temp_state  <= 128'h0;
                    round_cnt   <= 4'd0;
                    col_cnt     <= 2'd0;
                    phase       <= 2'd0;
                    enc_dec_reg <= enc_dec;
                    key_start   <= 1'b1;
                    state       <= KEY_EXPAND;
                end
            end
            
            ////////////////////////////////////////////////////////////////////////
            // KEY_EXPAND: Load all 44 round key words
            ////////////////////////////////////////////////////////////////////////
            KEY_EXPAND: begin
                key_start <= 1'b0;
                
                if (key_ready) begin
                    // Load round keys as they're generated
                    case (key_addr)
                        6'd0:  rk00 <= key_word;  6'd1:  rk01 <= key_word;
                        6'd2:  rk02 <= key_word;  6'd3:  rk03 <= key_word;
                        6'd4:  rk04 <= key_word;  6'd5:  rk05 <= key_word;
                        6'd6:  rk06 <= key_word;  6'd7:  rk07 <= key_word;
                        6'd8:  rk08 <= key_word;  6'd9:  rk09 <= key_word;
                        6'd10: rk10 <= key_word;  6'd11: rk11 <= key_word;
                        6'd12: rk12 <= key_word;  6'd13: rk13 <= key_word;
                        6'd14: rk14 <= key_word;  6'd15: rk15 <= key_word;
                        6'd16: rk16 <= key_word;  6'd17: rk17 <= key_word;
                        6'd18: rk18 <= key_word;  6'd19: rk19 <= key_word;
                        6'd20: rk20 <= key_word;  6'd21: rk21 <= key_word;
                        6'd22: rk22 <= key_word;  6'd23: rk23 <= key_word;
                        6'd24: rk24 <= key_word;  6'd25: rk25 <= key_word;
                        6'd26: rk26 <= key_word;  6'd27: rk27 <= key_word;
                        6'd28: rk28 <= key_word;  6'd29: rk29 <= key_word;
                        6'd30: rk30 <= key_word;  6'd31: rk31 <= key_word;
                        6'd32: rk32 <= key_word;  6'd33: rk33 <= key_word;
                        6'd34: rk34 <= key_word;  6'd35: rk35 <= key_word;
                        6'd36: rk36 <= key_word;  6'd37: rk37 <= key_word;
                        6'd38: rk38 <= key_word;  6'd39: rk39 <= key_word;
                        6'd40: rk40 <= key_word;  6'd41: rk41 <= key_word;
                        6'd42: rk42 <= key_word;  6'd43: rk43 <= key_word;
                    endcase
                    
                    if (key_addr < 6'd43) begin
                        key_next <= 1'b1;
                    end else begin
                        state <= ROUND0;
                    end
                end
            end
            
            ////////////////////////////////////////////////////////////////////////
            // ROUND0: Initial AddRoundKey
            ////////////////////////////////////////////////////////////////////////
            ROUND0: begin
                case (col_cnt)
                    2'd0: aes_state[127:96] <= aes_state[127:96] ^ current_rkey;
                    2'd1: aes_state[95:64]  <= aes_state[95:64]  ^ current_rkey;
                    2'd2: aes_state[63:32]  <= aes_state[63:32]  ^ current_rkey;
                    2'd3: aes_state[31:0]   <= aes_state[31:0]   ^ current_rkey;
                endcase
                
                if (col_cnt < 2'd3) begin
                    col_cnt <= col_cnt + 1'b1;
                end else begin
                    round_cnt <= 4'd1;
                    col_cnt   <= 2'd0;
                    state     <= enc_dec_reg ? ENC_SUB : DEC_SHIFT_SUB;
                end
            end
            
            ////////////////////////////////////////////////////////////////////////
            // ENCRYPTION: SubBytes â†' ShiftRows â†' MixColumns â†' AddRoundKey
            ////////////////////////////////////////////////////////////////////////
            ENC_SUB: begin
                // SubBytes on each column
                case (col_cnt)
                    2'd0: temp_state[127:96] <= col_subbed;
                    2'd1: temp_state[95:64]  <= col_subbed;
                    2'd2: temp_state[63:32]  <= col_subbed;
                    2'd3: temp_state[31:0]   <= col_subbed;
                endcase
                
                if (col_cnt < 2'd3) begin
                    col_cnt <= col_cnt + 1'b1;
                end else begin
                    col_cnt <= 2'd0;
                    state   <= ENC_SHIFT_MIX;
                end
            end
            
            ENC_SHIFT_MIX: begin
                // ShiftRows â†' MixColumns (skip in last round) â†' AddRoundKey
                case (col_cnt)
                    2'd0: aes_state[127:96] <= (is_last_round ? shifted_col : col_mixed) ^ current_rkey;
                    2'd1: aes_state[95:64]  <= (is_last_round ? shifted_col : col_mixed) ^ current_rkey;
                    2'd2: aes_state[63:32]  <= (is_last_round ? shifted_col : col_mixed) ^ current_rkey;
                    2'd3: aes_state[31:0]   <= (is_last_round ? shifted_col : col_mixed) ^ current_rkey;
                endcase
                
                if (col_cnt < 2'd3) begin
                    col_cnt <= col_cnt + 1'b1;
                end else begin
                    if (is_last_round) begin
                        state <= DONE;
                    end else begin
                        round_cnt <= round_cnt + 1'b1;
                        col_cnt   <= 2'd0;
                        state     <= ENC_SUB;
                    end
                end
            end
            
            ////////////////////////////////////////////////////////////////////////
            // DECRYPTION: InvShiftRows â†' InvSubBytes â†' AddRoundKey â†' InvMixColumns
            ////////////////////////////////////////////////////////////////////////
            DEC_SHIFT_SUB: begin
                if (phase == 2'd0) begin
                    // Phase 0: Apply InvShiftRows to entire state
                    temp_state <= state_shifted;
                    phase      <= 2'd1;
                end else begin
                    // Phase 1: Apply InvSubBytes column by column
                    case (col_cnt)
                        2'd0: aes_state[127:96] <= col_subbed;
                        2'd1: aes_state[95:64]  <= col_subbed;
                        2'd2: aes_state[63:32]  <= col_subbed;
                        2'd3: aes_state[31:0]   <= col_subbed;
                    endcase
                    
                    if (col_cnt < 2'd3) begin
                        col_cnt <= col_cnt + 1'b1;
                    end else begin
                        col_cnt <= 2'd0;
                        phase   <= 2'd0;
                        state   <= DEC_ADD_MIX;
                    end
                end
            end
            
            DEC_ADD_MIX: begin
                if (phase == 2'd0) begin
                    // Phase 0: AddRoundKey
                    case (col_cnt)
                        2'd0: aes_state[127:96] <= aes_state[127:96] ^ current_rkey;
                        2'd1: aes_state[95:64]  <= aes_state[95:64]  ^ current_rkey;
                        2'd2: aes_state[63:32]  <= aes_state[63:32]  ^ current_rkey;
                        2'd3: aes_state[31:0]   <= aes_state[31:0]   ^ current_rkey;
                    endcase
                    
                    if (col_cnt < 2'd3) begin
                        col_cnt <= col_cnt + 1'b1;
                    end else begin
                        if (is_last_round) begin
                            state <= DONE;
                        end else begin
                            col_cnt <= 2'd0;
                            phase   <= 2'd1;
                        end
                    end
                end else begin
                    // Phase 1: InvMixColumns (skip in last round)
                    case (col_cnt)
                        2'd0: aes_state[127:96] <= col_mixed;
                        2'd1: aes_state[95:64]  <= col_mixed;
                        2'd2: aes_state[63:32]  <= col_mixed;
                        2'd3: aes_state[31:0]   <= col_mixed;
                    endcase
                    
                    if (col_cnt < 2'd3) begin
                        col_cnt <= col_cnt + 1'b1;
                    end else begin
                        round_cnt <= round_cnt + 1'b1;
                        col_cnt   <= 2'd0;
                        phase     <= 2'd0;
                        state     <= DEC_SHIFT_SUB;
                    end
                end
            end
            
            ////////////////////////////////////////////////////////////////////////
            // DONE: Output result
            ////////////////////////////////////////////////////////////////////////
            DONE: begin
                data_out <= aes_state;
                ready    <= 1'b1;
                if (!start) begin
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule