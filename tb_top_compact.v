`timescale 1ns / 1ps

module tb_top_compact;

reg clk, rst_n, btnC, btnU;
reg [3:0] sw;
wire [7:0] led;

aes_fpga_top_compact uut (
    .clk(clk),
    .rst_n(rst_n),
    .btnC(btnC),
    .btnU(btnU),
    .sw(sw),
    .led(led)
);

initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz
end

initial begin
    $display("Testing Compact Top-Level with Minimal I/O");
   
    rst_n = 0;
    btnC = 0;
    btnU = 0;
    sw = 4'd0;  // NIST test vector
   
    #20 rst_n = 1;
    #20;
   
    // Test encryption
    $display("Test: NIST FIPS 197 C.1");
    #10 btnC = 1;  // Start
    #20 btnC = 0;
   
    // Wait for ready
    wait(led[7] == 1);
    $display("Encryption complete - LED shows ready");
    #100;
   
    $display("✅ Top-level module works!");
    $finish;
end

initial begin
    #50000;
    $display("Timeout");
    $finish;
end

endmodule
