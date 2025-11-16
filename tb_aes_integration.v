`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// INTEGRATION TEST: Full AES Core (FIXED DESIGN)
// Tests the complete aes_core_fixed.v with all submodules
// Uses NIST FIPS 197 test vectors for validation
////////////////////////////////////////////////////////////////////////////////

module tb_aes_integration;

reg         clk;
reg         rst_n;
reg         start;
reg         enc_dec;
reg  [127:0] data_in;
reg  [127:0] key_in;
wire [127:0] data_out;
wire        ready;

integer pass_count, fail_count, test_num;

// DUT
aes_core_fixed dut (
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
always #5 clk = ~clk;

////////////////////////////////////////////////////////////////////////////////
// Test Task: Encryption
////////////////////////////////////////////////////////////////////////////////
task test_encryption;
    input [127:0] plaintext;
    input [127:0] key;
    input [127:0] expected_ciphertext;
    input [255:0] test_name;
    begin
        test_num = test_num + 1;
        
        $display("\n========================================");
        $display("TEST %0d: ENCRYPTION", test_num);
        $display("%s", test_name);
        $display("========================================");
        $display("Plaintext:  %032h", plaintext);
        $display("Key:        %032h", key);
        $display("Expected:   %032h", expected_ciphertext);
        
        // Reset
        rst_n = 0;
        start = 0;
        #40;
        rst_n = 1;
        #40;
        
        // Set inputs
        data_in = plaintext;
        key_in = key;
        enc_dec = 1'b1; // Encryption
        
        // Start operation
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        // Wait for completion
        wait(ready);
        @(posedge clk);
        
        $display("Result:     %032h", data_out);
        
        // Verify
        if (data_out == expected_ciphertext) begin
            $display(" PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("âœ- FAIL");
            $display("XOR diff:   %032h", data_out ^ expected_ciphertext);
            
            // Show bit-by-bit difference
            $display("Differences at bytes:");
            if (data_out[127:120] != expected_ciphertext[127:120]) $display("  Byte 0:  got %02h, expected %02h", data_out[127:120], expected_ciphertext[127:120]);
            if (data_out[119:112] != expected_ciphertext[119:112]) $display("  Byte 1:  got %02h, expected %02h", data_out[119:112], expected_ciphertext[119:112]);
            if (data_out[111:104] != expected_ciphertext[111:104]) $display("  Byte 2:  got %02h, expected %02h", data_out[111:104], expected_ciphertext[111:104]);
            if (data_out[103:96]  != expected_ciphertext[103:96])  $display("  Byte 3:  got %02h, expected %02h", data_out[103:96],  expected_ciphertext[103:96]);
            if (data_out[95:88]   != expected_ciphertext[95:88])   $display("  Byte 4:  got %02h, expected %02h", data_out[95:88],   expected_ciphertext[95:88]);
            if (data_out[87:80]   != expected_ciphertext[87:80])   $display("  Byte 5:  got %02h, expected %02h", data_out[87:80],   expected_ciphertext[87:80]);
            if (data_out[79:72]   != expected_ciphertext[79:72])   $display("  Byte 6:  got %02h, expected %02h", data_out[79:72],   expected_ciphertext[79:72]);
            if (data_out[71:64]   != expected_ciphertext[71:64])   $display("  Byte 7:  got %02h, expected %02h", data_out[71:64],   expected_ciphertext[71:64]);
            if (data_out[63:56]   != expected_ciphertext[63:56])   $display("  Byte 8:  got %02h, expected %02h", data_out[63:56],   expected_ciphertext[63:56]);
            if (data_out[55:48]   != expected_ciphertext[55:48])   $display("  Byte 9:  got %02h, expected %02h", data_out[55:48],   expected_ciphertext[55:48]);
            if (data_out[47:40]   != expected_ciphertext[47:40])   $display("  Byte 10: got %02h, expected %02h", data_out[47:40],   expected_ciphertext[47:40]);
            if (data_out[39:32]   != expected_ciphertext[39:32])   $display("  Byte 11: got %02h, expected %02h", data_out[39:32],   expected_ciphertext[39:32]);
            if (data_out[31:24]   != expected_ciphertext[31:24])   $display("  Byte 12: got %02h, expected %02h", data_out[31:24],   expected_ciphertext[31:24]);
            if (data_out[23:16]   != expected_ciphertext[23:16])   $display("  Byte 13: got %02h, expected %02h", data_out[23:16],   expected_ciphertext[23:16]);
            if (data_out[15:8]    != expected_ciphertext[15:8])    $display("  Byte 14: got %02h, expected %02h", data_out[15:8],    expected_ciphertext[15:8]);
            if (data_out[7:0]     != expected_ciphertext[7:0])     $display("  Byte 15: got %02h, expected %02h", data_out[7:0],     expected_ciphertext[7:0]);
            
            fail_count = fail_count + 1;
        end
        
        wait(!ready);
        #100;
    end
endtask

////////////////////////////////////////////////////////////////////////////////
// Test Task: Decryption
////////////////////////////////////////////////////////////////////////////////
task test_decryption;
    input [127:0] ciphertext;
    input [127:0] key;
    input [127:0] expected_plaintext;
    input [255:0] test_name;
    begin
        test_num = test_num + 1;
        
        $display("\n========================================");
        $display("TEST %0d: DECRYPTION", test_num);
        $display("%s", test_name);
        $display("========================================");
        $display("Ciphertext: %032h", ciphertext);
        $display("Key:        %032h", key);
        $display("Expected:   %032h", expected_plaintext);
        
        // Reset
        rst_n = 0;
        start = 0;
        #40;
        rst_n = 1;
        #40;
        
        // Set inputs
        data_in = ciphertext;
        key_in = key;
        enc_dec = 1'b0; // Decryption
        
        // Start operation
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        // Wait for completion
        wait(ready);
        @(posedge clk);
        
        $display("Result:     %032h", data_out);
        
        // Verify
        if (data_out == expected_plaintext) begin
            $display(" PASS");
            pass_count = pass_count + 1;
        end else begin
            $display(" FAIL");
            $display("XOR diff:   %032h", data_out ^ expected_plaintext);
            fail_count = fail_count + 1;
        end
        
        wait(!ready);
        #100;
    end
endtask

////////////////////////////////////////////////////////////////////////////////
// Test Task: Round-trip
////////////////////////////////////////////////////////////////////////////////
task test_roundtrip;
    input [127:0] plaintext;
    input [127:0] key;
    input [255:0] test_name;
    reg [127:0] ciphertext;
    reg [127:0] recovered;
    begin
        test_num = test_num + 1;
        
        $display("\n========================================");
        $display("TEST %0d: ROUND-TRIP", test_num);
        $display("%s", test_name);
        $display("========================================");
        $display("Original:   %032h", plaintext);
        $display("Key:        %032h", key);
        
        // ENCRYPT
        rst_n = 0;
        start = 0;
        #40;
        rst_n = 1;
        #40;
        
        data_in = plaintext;
        key_in = key;
        enc_dec = 1'b1;
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        wait(ready);
        @(posedge clk);
        ciphertext = data_out;
        $display("Encrypted:  %032h", ciphertext);
        
        wait(!ready);
        #100;
        
        // DECRYPT
        rst_n = 0;
        #40;
        rst_n = 1;
        #40;
        
        data_in = ciphertext;
        key_in = key;
        enc_dec = 1'b0;
        
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        wait(ready);
        @(posedge clk);
        recovered = data_out;
        $display("Decrypted:  %032h", recovered);
        
        // Verify
        if (recovered == plaintext) begin
            $display(" PASS - Round-trip successful!");
            pass_count = pass_count + 1;
        end else begin
            $display(" FAIL - Round-trip failed!");
            $display("XOR diff:   %032h", recovered ^ plaintext);
            fail_count = fail_count + 1;
        end
        
        wait(!ready);
        #100;
    end
endtask

////////////////////////////////////////////////////////////////////////////////
// Main Test Sequence
////////////////////////////////////////////////////////////////////////////////
initial begin
    $display("\n");
    $display("================================================================================");
    $display("                    AES-128 INTEGRATION TEST SUITE");
    $display("                  Testing Fixed Design (aes_core_fixed.v)");
    $display("================================================================================\n");
    
    // Initialize
    clk = 0;
    rst_n = 0;
    start = 0;
    enc_dec = 1;
    pass_count = 0;
    fail_count = 0;
    test_num = 0;
    
    #100;
    
    //==========================================================================
    // ENCRYPTION TESTS - NIST FIPS 197 Test Vectors
    //==========================================================================
    $display("\n");
    $display("================================================================================");
    $display("                         ENCRYPTION TEST SECTION");
    $display("================================================================================");
    
    // Test 1: NIST FIPS 197 Appendix C.1
    test_encryption(
        128'h00112233445566778899aabbccddeeff,
        128'h000102030405060708090a0b0c0d0e0f,
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        "NIST FIPS 197 Appendix C.1"
    );
    
    // Test 2: NIST FIPS 197 Appendix B
    test_encryption(
        128'h3243f6a8885a308d313198a2e0370734,
        128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'h3925841d02dc09fbdc118597196a0b32,
        "NIST FIPS 197 Appendix B"
    );
    
    // Test 3: All zeros
    test_encryption(
        128'h00000000000000000000000000000000,
        128'h00000000000000000000000000000000,
        128'h66e94bd4ef8a2c3b884cfa59ca342b2e,
        "All zeros plaintext and key"
    );
    
    // Test 4: All ones
    test_encryption(
        128'hffffffffffffffffffffffffffffffff,
        128'hffffffffffffffffffffffffffffffff,
        128'hbcbf217cb280cf30b2517052193ab979,
        "All ones plaintext and key"
    );
    
    //==========================================================================
    // DECRYPTION TESTS
    //==========================================================================
    $display("\n");
    $display("================================================================================");
    $display("                         DECRYPTION TEST SECTION");
    $display("================================================================================");
    
    // Test 5: Decrypt NIST FIPS 197 Appendix C.1
    test_decryption(
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h000102030405060708090a0b0c0d0e0f,
        128'h00112233445566778899aabbccddeeff,
        "NIST FIPS 197 Appendix C.1"
    );
    
    // Test 6: Decrypt NIST FIPS 197 Appendix B
    test_decryption(
        128'h3925841d02dc09fbdc118597196a0b32,
        128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'h3243f6a8885a308d313198a2e0370734,
        "NIST FIPS 197 Appendix B"
    );
    
    // Test 7: Decrypt all zeros
    test_decryption(
        128'h66e94bd4ef8a2c3b884cfa59ca342b2e,
        128'h00000000000000000000000000000000,
        128'h00000000000000000000000000000000,
        "All zeros recovery"
    );
    
    //==========================================================================
    // ROUND-TRIP TESTS
    //==========================================================================
    $display("\n");
    $display("================================================================================");
    $display("                         ROUND-TRIP TEST SECTION");
    $display("================================================================================");
    
    // Test 8: Round-trip 1
    test_roundtrip(
        128'hdeadbeefcafebabe0123456789abcdef,
        128'h0f1e2d3c4b5a69788796a5b4c3d2e1f0,
        "Random data pattern 1"
    );
    
    // Test 9: Round-trip 2
    test_roundtrip(
        128'h0123456789abcdef0123456789abcdef,
        128'hfedcba9876543210fedcba9876543210,
        "Repeating pattern"
    );
    
    // Test 10: Round-trip 3
    test_roundtrip(
        128'h0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f,
        128'hf0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0,
        "Alternating nibbles"
    );
    
    //==========================================================================
    // FINAL SUMMARY
    //==========================================================================
    $display("\n");
    $display("================================================================================");
    $display("                            FINAL TEST SUMMARY");
    $display("================================================================================");
    $display("Total Tests:    %0d", pass_count + fail_count);
    $display("Tests Passed:   %0d", pass_count);
    $display("Tests Failed:   %0d", fail_count);
    $display("Success Rate:   %0d%%", (pass_count * 100) / (pass_count + fail_count));
    $display("================================================================================");
    
    if (fail_count == 0) begin
        $display("     ALL TESTS PASSED! ");
        $display("    AES-128 Fixed Design is VERIFIED!");
        $display("\n");
    end else begin
        $display("\n");
        $display("     %0d TEST(S) FAILED ", fail_count);
        $display("    Design needs debugging!");
        $display("\n");
    end
    $display("================================================================================\n");
    
    $finish;
end

// Timeout watchdog
initial begin
    #100000000; // 100ms timeout
    $display("\n\n ERROR: Simulation timeout! \n");
    $finish;
end


endmodule
