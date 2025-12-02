`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench for Compact AES Core
// Tests encryption and decryption with NIST test vectors
//////////////////////////////////////////////////////////////////////////////////

module tb_aes_compact;

// Inputs
reg clk;
reg rst_n;
reg start;
reg enc_dec;
reg [127:0] data_in;
reg [127:0] key_in;

// Outputs
wire [127:0] data_out;
wire ready;

// Expected outputs for verification
reg [127:0] expected_out;
reg test_pass;

// Instantiate the Unit Under Test (UUT)
aes_core_compact_v3 uut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .enc_dec(enc_dec),
    .data_in(data_in),
    .key_in(key_in),
    .data_out(data_out),
    .ready(ready)
);

// Clock generation - 100MHz = 10ns period
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// Test counter
integer test_num;
integer cycle_count;

// Test procedure
initial begin
    // Initialize signals
    rst_n = 0;
    start = 0;
    enc_dec = 1;
    data_in = 128'h0;
    key_in = 128'h0;
    test_pass = 1;
    test_num = 0;
    cycle_count = 0;

    // Display header
    $display("========================================");
    $display("AES-128 Compact Core Testbench");
    $display("========================================");

    // Apply reset
    #20;
    rst_n = 1;
    #20;

    //////////////////////////////////////////////////////////////////////////
    // Test 1: NIST FIPS 197 Appendix C.1 - Encryption
    //////////////////////////////////////////////////////////////////////////
    test_num = 1;
    $display("\nTest %0d: NIST FIPS 197 C.1 Encryption", test_num);
    key_in = 128'h000102030405060708090a0b0c0d0e0f;
    data_in = 128'h00112233445566778899aabbccddeeff;
    expected_out = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    enc_dec = 1;  // Encrypt

    $display("  Key:       %032x", key_in);
    $display("  Plaintext: %032x", data_in);
    $display("  Expected:  %032x", expected_out);

    // Start encryption
    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait for completion
    cycle_count = 0;
    wait(ready == 0);  // Wait for start
    wait(ready == 1);  // Wait for done

    $display("  Result:    %032x", data_out);
    if (data_out == expected_out) begin
        $display("  Status:    PASS");
    end else begin
        $display("  Status:    FAIL");
        test_pass = 0;
    end

    #50;

    //////////////////////////////////////////////////////////////////////////
    // Test 2: NIST FIPS 197 Appendix C.1 - Decryption
    //////////////////////////////////////////////////////////////////////////
    test_num = 2;
    $display("\nTest %0d: NIST FIPS 197 C.1 Decryption", test_num);
    key_in = 128'h000102030405060708090a0b0c0d0e0f;
    data_in = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    expected_out = 128'h00112233445566778899aabbccddeeff;
    enc_dec = 0;  // Decrypt

    $display("  Key:        %032x", key_in);
    $display("  Ciphertext: %032x", data_in);
    $display("  Expected:   %032x", expected_out);

    // Start decryption
    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait for completion
    wait(ready == 0);
    wait(ready == 1);

    $display("  Result:     %032x", data_out);
    if (data_out == expected_out) begin
        $display("  Status:     PASS");
    end else begin
        $display("  Status:     FAIL");
        test_pass = 0;
    end

    #50;

    //////////////////////////////////////////////////////////////////////////
    // Test 3: NIST FIPS 197 Appendix B - Encryption
    //////////////////////////////////////////////////////////////////////////
    test_num = 3;
    $display("\nTest %0d: NIST FIPS 197 Appendix B Encryption", test_num);
    key_in = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    data_in = 128'h3243f6a8885a308d313198a2e0370734;
    expected_out = 128'h3925841d02dc09fbdc118597196a0b32;
    enc_dec = 1;

    $display("  Key:       %032x", key_in);
    $display("  Plaintext: %032x", data_in);
    $display("  Expected:  %032x", expected_out);

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    wait(ready == 0);
    wait(ready == 1);

    $display("  Result:    %032x", data_out);
    if (data_out == expected_out) begin
        $display("  Status:    PASS");
    end else begin
        $display("  Status:    FAIL");
        test_pass = 0;
    end

    #50;

    //////////////////////////////////////////////////////////////////////////
    // Test 4: All Zeros
    //////////////////////////////////////////////////////////////////////////
    test_num = 4;
    $display("\nTest %0d: All Zeros Encryption", test_num);
    key_in = 128'h00000000000000000000000000000000;
    data_in = 128'h00000000000000000000000000000000;
    expected_out = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
    enc_dec = 1;

    $display("  Key:       %032x", key_in);
    $display("  Plaintext: %032x", data_in);
    $display("  Expected:  %032x", expected_out);

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    wait(ready == 0);
    wait(ready == 1);

    $display("  Result:    %032x", data_out);
    if (data_out == expected_out) begin
        $display("  Status:    PASS");
    end else begin
        $display("  Status:    FAIL");
        test_pass = 0;
    end

    #50;

    //////////////////////////////////////////////////////////////////////////
    // Final Results
    //////////////////////////////////////////////////////////////////////////
    $display("\n========================================");
    if (test_pass) begin
        $display("ALL TESTS PASSED!");
    end else begin
        $display("SOME TESTS FAILED!");
    end
    $display("========================================\n");

    #100;
    $finish;
end

// Timeout watchdog
initial begin
    #100000;  // 100us timeout
    $display("\nERROR: Simulation timeout!");
    $finish;
end

// Optional: Monitor for debugging
// initial begin
//     $monitor("Time=%0t rst_n=%b start=%b ready=%b state=%d round=%d step=%d",
//              $time, rst_n, start, ready, uut.state, uut.round, uut.step);
// end

endmodule
