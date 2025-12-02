`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.10.2025 21:27:31
// Design Name: 
// Module Name: aes_shiftrows_128bit
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

// AES ShiftRows module
// NIST FIPS-197 compliant implementation
// AES state is column-major: s0-s3 in col0, s4-s7 in col1, s8-s11 in col2, s12-s15 in col3
module aes_shiftrows_128bit(
    input  [127:0] data_in,
    input          enc_dec,     // 1=encryption, 0=decryption
    output [127:0] data_out
);

// Extract bytes from column-major layout (MSB first: s0 at [127:120])
wire [7:0] s0  = data_in[127:120];  wire [7:0] s1  = data_in[119:112];
wire [7:0] s2  = data_in[111:104];  wire [7:0] s3  = data_in[103:96];
wire [7:0] s4  = data_in[95:88];    wire [7:0] s5  = data_in[87:80];
wire [7:0] s6  = data_in[79:72];    wire [7:0] s7  = data_in[71:64];
wire [7:0] s8  = data_in[63:56];    wire [7:0] s9  = data_in[55:48];
wire [7:0] s10 = data_in[47:40];    wire [7:0] s11 = data_in[39:32];
wire [7:0] s12 = data_in[31:24];    wire [7:0] s13 = data_in[23:16];
wire [7:0] s14 = data_in[15:8];     wire [7:0] s15 = data_in[7:0];

// ShiftRows - Optimized with reduced mux logic
// Encryption ShiftRows: Row 0: no shift, Row 1: <<1, Row 2: <<2, Row 3: <<3
// Decryption InvShiftRows: Row 0: no shift, Row 1: >>1, Row 2: >>2, Row 3: >>3

// Select output bytes based on enc_dec
// Row 0: same for encryption and decryption (no shift)
wire [7:0] b0  = s0;
wire [7:0] b4  = s4;
wire [7:0] b8  = s8;
wire [7:0] b12 = s12;

// Row 1: encryption shift left 1, decryption shift right 1
wire [7:0] b1  = enc_dec ? s5  : s13;
wire [7:0] b5  = enc_dec ? s9  : s1;
wire [7:0] b9  = enc_dec ? s13 : s5;
wire [7:0] b13 = enc_dec ? s1  : s9;

// Row 2: same for both (shift 2 positions = shift left 2 = shift right 2)
wire [7:0] b2  = s10;
wire [7:0] b6  = s14;
wire [7:0] b10 = s2;
wire [7:0] b14 = s6;

// Row 3: encryption shift left 3, decryption shift right 3
wire [7:0] b3  = enc_dec ? s15 : s7;
wire [7:0] b7  = enc_dec ? s3  : s11;
wire [7:0] b11 = enc_dec ? s7  : s15;
wire [7:0] b15 = enc_dec ? s11 : s3;

// Pack output in column-major order
assign data_out = {b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15};

endmodule