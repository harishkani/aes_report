`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench for Ultra-Serial AES Core
// Tests both encryption and decryption with NIST test vectors
//////////////////////////////////////////////////////////////////////////////////

module tb_aes_ultraserial;

reg         clk;
reg         rst_n;
reg         start;
reg         enc_dec;
reg [127:0] data_in;
reg [127:0] key_in;
wire [127:0] data_out;
wire        ready;

// Instantiate ultra-serial AES core
aes_core_ultraserial uut (
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
    forever #5 clk = ~clk; // 100MHz
end

// Test variables
integer test_num;
integer pass_count;
integer fail_count;
reg [127:0] expected;
integer timeout_cycles;
integer cycle_count;

// Cycle counter
always @(posedge clk) begin
    if (!ready && start) begin
        cycle_count = cycle_count + 1;
    end else if (ready && cycle_count > 0) begin
        $display("  Cycles: %0d (%.2f µs @ 100MHz)", cycle_count, cycle_count * 0.01);
        cycle_count = 0;
    end
end

// Task to run a test
task run_test;
    input [127:0] test_key;
    input [127:0] test_data;
    input [127:0] test_expected;
    input test_enc_dec;
    input [256*8-1:0] test_name;
begin
    test_num = test_num + 1;
    $display("\nTest %0d: %s", test_num, test_name);
    $display("  Key:      %h", test_key);
    $display("  Input:    %h", test_data);
    $display("  Expected: %h", test_expected);

    // Apply inputs
    key_in = test_key;
    data_in = test_data;
    enc_dec = test_enc_dec;
    expected = test_expected;

    // Start operation
    @(posedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    // Wait for completion with timeout
    timeout_cycles = 0;
    cycle_count = 0;
    while (!ready && timeout_cycles < 10000) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
    end

    if (timeout_cycles >= 10000) begin
        $display("  Result:   TIMEOUT!");
        $display("  Status:   FAIL ❌");
        fail_count = fail_count + 1;
    end else begin
        $display("  Result:   %h", data_out);
        if (data_out === expected) begin
            $display("  Status:   PASS ✅");
            pass_count = pass_count + 1;
        end else begin
            $display("  Status:   FAIL ❌");
            fail_count = fail_count + 1;
        end
    end

    // Wait a few cycles before next test
    repeat(5) @(posedge clk);
end
endtask

// Main test sequence
initial begin
    $display("=================================================================");
    $display("Ultra-Serial AES-128 Core Testbench");
    $display("Architecture: 1 byte/cycle (single S-box)");
    $display("=================================================================");

    // Initialize
    rst_n = 0;
    start = 0;
    enc_dec = 1;
    data_in = 128'h0;
    key_in = 128'h0;
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    cycle_count = 0;

    // Reset
    #100;
    rst_n = 1;
    #50;

    // ===================================================================
    // NIST FIPS 197 Test Vectors
    // ===================================================================

    // Test 1: NIST FIPS 197 Appendix C.1 - Encryption
    run_test(
        128'h000102030405060708090a0b0c0d0e0f,  // key
        128'h00112233445566778899aabbccddeeff,  // plaintext
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,  // expected ciphertext
        1'b1,                                    // encrypt
        "NIST FIPS 197 C.1 Encryption"
    );

    // Test 2: NIST FIPS 197 Appendix C.1 - Decryption
    run_test(
        128'h000102030405060708090a0b0c0d0e0f,  // key
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,  // ciphertext
        128'h00112233445566778899aabbccddeeff,  // expected plaintext
        1'b0,                                    // decrypt
        "NIST FIPS 197 C.1 Decryption"
    );

    // Test 3: NIST FIPS 197 Appendix B - Encryption
    run_test(
        128'h2b7e151628aed2a6abf7158809cf4f3c,  // key
        128'h3243f6a8885a308d313198a2e0370734,  // plaintext
        128'h3925841d02dc09fbdc118597196a0b32,  // expected ciphertext
        1'b1,                                    // encrypt
        "NIST FIPS 197 Appendix B Encryption"
    );

    // Test 4: NIST FIPS 197 Appendix B - Decryption
    run_test(
        128'h2b7e151628aed2a6abf7158809cf4f3c,  // key
        128'h3925841d02dc09fbdc118597196a0b32,  // ciphertext
        128'h3243f6a8885a308d313198a2e0370734,  // expected plaintext
        1'b0,                                    // decrypt
        "NIST FIPS 197 Appendix B Decryption"
    );

    // Test 5: All Zeros - Encryption
    run_test(
        128'h00000000000000000000000000000000,  // key
        128'h00000000000000000000000000000000,  // plaintext
        128'h66e94bd4ef8a2c3b884cfa59ca342b2e,  // expected ciphertext
        1'b1,                                    // encrypt
        "All Zeros Encryption"
    );

    // Test 6: All Zeros - Decryption
    run_test(
        128'h00000000000000000000000000000000,  // key
        128'h66e94bd4ef8a2c3b884cfa59ca342b2e,  // ciphertext
        128'h00000000000000000000000000000000,  // expected plaintext
        1'b0,                                    // decrypt
        "All Zeros Decryption"
    );

    // ===================================================================
    // Test Summary
    // ===================================================================
    #100;
    $display("\n=================================================================");
    $display("Test Summary");
    $display("=================================================================");
    $display("Total Tests: %0d", test_num);
    $display("Passed:      %0d ✅", pass_count);
    $display("Failed:      %0d ❌", fail_count);
    $display("=================================================================");

    if (fail_count == 0) begin
        $display("🎉 ALL %0d TESTS PASSED! 🎉", test_num);
        $display("Ultra-serial AES core (1 byte/cycle) fully verified!");
    end else begin
        $display("⚠️  %0d TEST(S) FAILED", fail_count);
    end
    $display("=================================================================\n");

    $finish;
end

// Timeout watchdog
initial begin
    #500000; // 500µs timeout
    $display("\n⚠️  GLOBAL TIMEOUT - Simulation ran too long");
    $finish;
end

endmodule
