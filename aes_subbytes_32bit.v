`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.10.2025 14:53:00
// Design Name: 
// Module Name: aes_subbytes_32bit
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// 32-bit SubBytes module with simultaneous encryption/decryption
// Operates on 4 bytes in parallel using 4 S-boxes
module aes_subbytes_32bit(
    input  [31:0] data_in,
    input         enc_dec,      // 1=encryption, 0=decryption
    output [31:0] data_out
);

wire [7:0] sbox_out[0:3];
wire [7:0] inv_sbox_out[0:3];

// Instantiate 4 S-boxes and 4 Inverse S-boxes
// All operate simultaneously for security against power analysis
genvar i;
generate
    for (i = 0; i < 4; i = i + 1) begin : sbox_array
        aes_sbox sbox_inst (
            .in(data_in[i*8 +: 8]),
            .out(sbox_out[i])
        );
        
        aes_inv_sbox inv_sbox_inst (
            .in(data_in[i*8 +: 8]),
            .out(inv_sbox_out[i])
        );
    end
endgenerate

// Select output based on enc_dec
// Both paths are always active for power analysis resistance
// Note: Output byte order matches input byte order
assign data_out[7:0]   = enc_dec ? sbox_out[0] : inv_sbox_out[0];
assign data_out[15:8]  = enc_dec ? sbox_out[1] : inv_sbox_out[1];
assign data_out[23:16] = enc_dec ? sbox_out[2] : inv_sbox_out[2];
assign data_out[31:24] = enc_dec ? sbox_out[3] : inv_sbox_out[3];

endmodule