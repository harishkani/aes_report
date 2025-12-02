`timescale 1ns / 1ps

module tb_aes_serial_full;

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

integer test_num, cycle_count;
reg [127:0] expected;
reg all_pass;

initial begin
    $display("========================================");
    $display("Serial AES-128 Full Test Suite");
    $display("========================================\n");

    all_pass = 1;
    test_num = 0;
    cycle_count = 0;

    rst_n = 0;
    start = 0;
    #20 rst_n = 1;
    #20;

    // Test 1: Encryption
    test_num = 1;
    $display("Test %0d: NIST C.1 Encryption", test_num);
    key_in = 128'h000102030405060708090a0b0c0d0e0f;
    data_in = 128'h00112233445566778899aabbccddeeff;
    expected = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    enc_dec = 1;

    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    wait(ready == 0); wait(ready == 1);

    if (data_out == expected) begin
        $display("  ✅ PASS");
    end else begin
        $display("  ❌ FAIL: got %032x", data_out);
        all_pass = 0;
    end
    #50;

    // Test 2: Decryption  
    test_num = 2;
    $display("Test %0d: NIST C.1 Decryption", test_num);
    key_in = 128'h000102030405060708090a0b0c0d0e0f;
    data_in = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    expected = 128'h00112233445566778899aabbccddeeff;
    enc_dec = 0;

    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    wait(ready == 0); wait(ready == 1);

    if (data_out == expected) begin
        $display("  ✅ PASS");
    end else begin
        $display("  ❌ FAIL: got %032x", data_out);
        all_pass = 0;
    end
    #50;

    // Test 3: Appendix B Encryption
    test_num = 3;
    $display("Test %0d: NIST Appendix B Encryption", test_num);
    key_in = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    data_in = 128'h3243f6a8885a308d313198a2e0370734;
    expected = 128'h3925841d02dc09fbdc118597196a0b32;
    enc_dec = 1;

    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    wait(ready == 0); wait(ready == 1);

    if (data_out == expected) begin
        $display("  ✅ PASS");
    end else begin
        $display("  ❌ FAIL: got %032x", data_out);
        all_pass = 0;
    end
    #50;

    // Test 4: Appendix B Decryption
    test_num = 4;
    $display("Test %0d: NIST Appendix B Decryption", test_num);
    key_in = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    data_in = 128'h3925841d02dc09fbdc118597196a0b32;
    expected = 128'h3243f6a8885a308d313198a2e0370734;
    enc_dec = 0;

    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    wait(ready == 0); wait(ready == 1);

    if (data_out == expected) begin
        $display("  ✅ PASS");
    end else begin
        $display("  ❌ FAIL: got %032x", data_out);
        all_pass = 0;
    end
    #50;

    // Test 5: All Zeros Encryption
    test_num = 5;
    $display("Test %0d: All Zeros Encryption", test_num);
    key_in = 128'h00000000000000000000000000000000;
    data_in = 128'h00000000000000000000000000000000;
    expected = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
    enc_dec = 1;

    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    wait(ready == 0); wait(ready == 1);

    if (data_out == expected) begin
        $display("  ✅ PASS");
    end else begin
        $display("  ❌ FAIL: got %032x", data_out);
        all_pass = 0;
    end
    #50;

    // Test 6: All Zeros Decryption
    test_num = 6;
    $display("Test %0d: All Zeros Decryption", test_num);
    key_in = 128'h00000000000000000000000000000000;
    data_in = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
    expected = 128'h00000000000000000000000000000000;
    enc_dec = 0;

    @(posedge clk); start = 1;
    @(posedge clk); start = 0;
    wait(ready == 0); wait(ready == 1);

    if (data_out == expected) begin
        $display("  ✅ PASS");
    end else begin
        $display("  ❌ FAIL: got %032x", data_out);
        all_pass = 0;
    end
    #50;

    $display("\n========================================");
    if (all_pass) begin
        $display("✅ ALL %0d TESTS PASSED!", test_num);
        $display("Serial AES core fully verified!");
    end else begin
        $display("❌ SOME TESTS FAILED");
    end
    $display("========================================\n");

    #100;
    $finish;
end

initial begin
    #1000000;
    $display("\n❌ TIMEOUT");
    $finish;
end

endmodule
