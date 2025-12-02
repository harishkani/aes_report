`timescale 1ns / 1ps

module tb_aes_serial;

reg clk, rst_n, start, enc_dec;
reg [127:0] data_in, key_in;
wire [127:0] data_out;
wire ready;

aes_core_serial_enc uut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .enc_dec(enc_dec),
    .data_in(data_in),
    .key_in(key_in),
    .data_out(data_out),
    .ready(ready)
);

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz
end

// Test procedure
integer test_num;
reg [127:0] expected;
reg all_pass;

initial begin
    $display("========================================");
    $display("Serial AES-128 Core Testbench");
    $display("Target: <500 LUTs, <500 FFs, <40mW @ 100MHz");
    $display("========================================\n");

    all_pass = 1;
    test_num = 0;

    // Reset
    rst_n = 0;
    start = 0;
    enc_dec = 1;
    data_in = 128'd0;
    key_in = 128'd0;
    #20 rst_n = 1;
    #20;

    ////////////////////////////////////////////////////////////////
    // Test 1: NIST FIPS 197 C.1 Encryption
    ////////////////////////////////////////////////////////////////
    test_num = 1;
    $display("Test %0d: NIST FIPS 197 C.1 - Encryption", test_num);
    key_in = 128'h000102030405060708090a0b0c0d0e0f;
    data_in = 128'h00112233445566778899aabbccddeeff;
    expected = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    enc_dec = 1;

    $display("  Key:       %032x", key_in);
    $display("  Plaintext: %032x", data_in);
    $display("  Expected:  %032x", expected);

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait for ready
    wait(ready == 0);  // Wait for busy
    wait(ready == 1);  // Wait for done

    $display("  Result:    %032x", data_out);
    if (data_out == expected) begin
        $display("  Status:    ✅ PASS\n");
    end else begin
        $display("  Status:    ❌ FAIL\n");
        all_pass = 0;
    end
    #50;

    ////////////////////////////////////////////////////////////////
    // Test 2: NIST FIPS 197 Appendix B Encryption
    ////////////////////////////////////////////////////////////////
    test_num = 2;
    $display("Test %0d: NIST FIPS 197 Appendix B - Encryption", test_num);
    key_in = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    data_in = 128'h3243f6a8885a308d313198a2e0370734;
    expected = 128'h3925841d02dc09fbdc118597196a0b32;
    enc_dec = 1;

    $display("  Key:       %032x", key_in);
    $display("  Plaintext: %032x", data_in);
    $display("  Expected:  %032x", expected);

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    wait(ready == 0);
    wait(ready == 1);

    $display("  Result:    %032x", data_out);
    if (data_out == expected) begin
        $display("  Status:    ✅ PASS\n");
    end else begin
        $display("  Status:    ❌ FAIL\n");
        all_pass = 0;
    end
    #50;

    ////////////////////////////////////////////////////////////////
    // Test 3: All Zeros
    ////////////////////////////////////////////////////////////////
    test_num = 3;
    $display("Test %0d: All Zeros - Encryption", test_num);
    key_in = 128'h00000000000000000000000000000000;
    data_in = 128'h00000000000000000000000000000000;
    expected = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
    enc_dec = 1;

    $display("  Key:       %032x", key_in);
    $display("  Plaintext: %032x", data_in);
    $display("  Expected:  %032x", expected);

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    wait(ready == 0);
    wait(ready == 1);

    $display("  Result:    %032x", data_out);
    if (data_out == expected) begin
        $display("  Status:    ✅ PASS\n");
    end else begin
        $display("  Status:    ❌ FAIL\n");
        all_pass = 0;
    end
    #50;

    ////////////////////////////////////////////////////////////////
    // Final Summary
    ////////////////////////////////////////////////////////////////
    $display("========================================");
    if (all_pass) begin
        $display("✅ ALL TESTS PASSED!");
        $display("Serial design is working correctly.");
    end else begin
        $display("❌ SOME TESTS FAILED");
    end
    $display("========================================\n");

    #100;
    $finish;
end

// Timeout
initial begin
    #500000;  // 500us
    $display("\n❌ ERROR: Simulation timeout!");
    $finish;
end

// Optional: cycle counter
integer cycle_count;
initial begin
    cycle_count = 0;
    forever begin
        @(posedge clk);
        if (!ready && start == 0) cycle_count = cycle_count + 1;
        if (ready && cycle_count > 0) begin
            $display("  Cycles: %0d (%.2f µs @ 100MHz)", cycle_count, cycle_count * 0.01);
            cycle_count = 0;
        end
    end
end

endmodule
// Additional decryption tests (append to existing testbench before final summary)
