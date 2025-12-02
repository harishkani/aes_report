`timescale 1ns / 1ps

module tb_aes_serial_debug;

reg clk, rst_n, start, enc_dec;
reg [127:0] data_in, key_in;
wire [127:0] data_out;
wire ready;

aes_core_serial uut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .enc_dec(enc_dec),
    .data_in(data_in),
    .key_in(key_in),
    .data_out(data_out),
    .ready(ready)
);

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

initial begin
    $display("Debug: Testing Decryption");
    
    rst_n = 0;
    start = 0;
    #20 rst_n = 1;
    #20;

    // Test decryption
    key_in = 128'h000102030405060708090a0b0c0d0e0f;
    data_in = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    enc_dec = 0;  // Decrypt

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    // Monitor state
    repeat(500) begin
        @(posedge clk);
        $display("t=%0t state=%0d round=%0d col=%0d phase=%0d ready=%b", 
                 $time, uut.state, uut.round, uut.col_cnt, uut.phase, ready);
        
        if (ready == 1 && $time > 1000) begin
            $display("\nDecryption done!");
            $display("Result: %032x", data_out);
            $display("Expected: 00112233445566778899aabbccddeeff");
            $finish;
        end
    end

    $display("\nStuck - last state=%0d round=%0d col=%0d", 
             uut.state, uut.round, uut.col_cnt);
    $finish;
end

endmodule
