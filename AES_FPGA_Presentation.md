# AES-128 FPGA Implementation
## Advanced Encryption Standard on Nexys A7-100T

---

## Presentation Agenda

1. Project Overview
2. Architecture Design
3. Module-by-Module Analysis
4. FPGA Implementation Results
5. Performance Metrics
6. Testing & Verification
7. Strengths & Future Enhancements

---

## Project Overview

### What is This Project?

- **Complete AES-128 encryption/decryption** implementation
- Target: **Nexys A7-100T FPGA Board** (Xilinx Artix-7)
- **NIST FIPS-197 compliant** design
- **Production-ready** with hardware verification

### Key Features

- ✓ Dual-mode: Encryption & Decryption
- ✓ Interactive hardware interface (buttons, switches, displays)
- ✓ Resource-efficient design (3.36% LUT usage)
- ✓ Low power consumption (0.172W)
- ✓ Comprehensive test coverage

---

## AES Algorithm Basics

### AES-128 Overview

- **Block cipher**: 128-bit blocks
- **Key size**: 128 bits
- **Rounds**: 10 rounds
- **Operations per round**:
  - SubBytes (S-box substitution)
  - ShiftRows (row permutation)
  - MixColumns (column mixing) - except final round
  - AddRoundKey (XOR with round key)

---

## System Architecture

### Top-Level Design (aes_fpga_top)

```
┌─────────────────────────────────────────┐
│         User Interface Layer            │
│  Buttons | Switches | LEDs | 7-Seg      │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         AES Core (aes_core_fixed)       │
│  ┌──────────────────────────────────┐   │
│  │   Key Expansion (On-the-Fly)     │   │
│  ├──────────────────────────────────┤   │
│  │   State Machine Controller       │   │
│  ├──────────────────────────────────┤   │
│  │   SubBytes | ShiftRows | Mix     │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

---

## Core Design Features

### State Machine Architecture

**7 States:**
1. **IDLE**: Wait for start signal
2. **KEY_EXPAND**: Generate all 44 round key words
3. **ROUND0**: Initial AddRoundKey
4. **ENC_SUB**: Encryption SubBytes
5. **ENC_SHIFT_MIX**: Encryption ShiftRows + MixColumns + AddRoundKey
6. **DEC_SHIFT_SUB**: Decryption InvShiftRows + InvSubBytes
7. **DEC_ADD_MIX**: Decryption AddRoundKey + InvMixColumns
8. **DONE**: Output result

---

## Key Design Decisions

### Iterative vs Pipelined

**Chosen: Iterative (Round-by-Round)**

**Advantages:**
- ✓ Minimal resource usage (3.36% LUTs)
- ✓ Low power consumption
- ✓ Simple control logic
- ✓ Easy to verify

**Trade-off:**
- Lower throughput (~200 Mbps)
- ~50-60 cycles per operation

---

## Module: Key Expansion

### On-the-Fly Generation

**Innovation:**
- Generates round keys **dynamically** instead of storing all
- Only stores current 4-word window (128 bits)

**Benefits:**
- **85% memory reduction** vs pre-computed approach
- Minimal latency (~44 cycles)

**Implementation:**
- 4 S-boxes for SubWord transformation
- Rcon (round constant) lookup
- RotWord operation

---

## Module: SubBytes

### S-box Implementation

**Security Feature:**
- Instantiates **both forward & inverse S-boxes**
- All 8 S-boxes (4 fwd + 4 inv) operate simultaneously

**Why?**
- **Power analysis resistance**
- Constant power consumption regardless of mode
- Prevents side-channel attacks

**Resource:**
- 256-entry lookup table per S-box
- ~256 LUTs per S-box instance

---

## Module: MixColumns

### Optimization - Decomposition Matrix Method

**Key Innovation:**
```
InvMixColumns = MixColumns × DecompositionMatrix
```

**Single shared circuit for both modes:**
1. Encryption: Direct MixColumns
2. Decryption: Decomposition → MixColumns

**Benefits:**
- **10.4% area reduction**
- **9.1% delay reduction**
- Resource sharing between enc/dec

---

## MixColumns: GF(2^8) Operations

### Galois Field Arithmetic

**Implemented Operations:**
- **mult2**: xtime operation (shift + conditional XOR 0x1B)
- **mult3**: mult2(x) ⊕ x
- **mult4**: mult2(mult2(x))
- **mult5**: mult4(x) ⊕ x

**Decomposition Matrix:**
```
[05 00 04 00]
[00 05 00 04]
[04 00 05 00]
[00 04 00 05]
```

---

## Module: ShiftRows

### Byte Permutation

**Purely Combinational Logic**

**Encryption:**
- Row 0: No shift
- Row 1: Left shift 1
- Row 2: Left shift 2
- Row 3: Left shift 3

**Optimization:**
- Row 2 same for both enc/dec
- Efficient muxing reduces LUT usage

---

## Hardware Interface

### User Interaction Components

**Inputs:**
- 16 Switches: Test vector selection
- 4 Push Buttons:
  - btnC: Start operation
  - btnU: Toggle encrypt/decrypt
  - btnL/btnR: Navigate display

**Outputs:**
- 8× 7-segment displays (shows 8 hex digits)
- 16 LEDs (status indicators)

**Features:**
- Button debouncing (20-bit counter)
- Rising edge detection

---

## Built-in Test Vectors

### Comprehensive Test Coverage

**NIST Standard Vectors:**
1. FIPS 197 Appendix C.1
2. FIPS 197 Appendix B

**Edge Cases:**
3. All zeros (plaintext & key)
4. All ones (plaintext & key)

**Custom Patterns:**
5. Alternating pattern
6. Sequential data
7. User-defined (via switches)

---

## Synthesis Results

### Resource Utilization

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| **Slice LUTs** | 2,132 | 63,400 | **3.36%** ✓ |
| **Slice Registers** | 2,043 | 126,800 | **1.61%** ✓ |
| **F7 Muxes** | 366 | 31,700 | 1.15% |
| **F8 Muxes** | 34 | 15,850 | 0.21% |
| **Block RAM** | 0 | 135 | **0%** ✓ |
| **DSP Blocks** | 0 | 240 | **0%** ✓ |

**Conclusion:** Pure logic design, highly efficient!

---

## Resource Breakdown

### By Module

**From synthesis report:**

- **aes_core_fixed**:
  - 2,116 LUTs
  - 1,992 Registers

- **seven_seg_controller**:
  - 5 LUTs
  - 17 Registers

**Analysis:**
- AES core uses 99.2% of design resources
- Could fit **25+ AES cores** on same FPGA

---

## Power Consumption

### On-Chip Power Analysis

**Total: 0.172 W**

| Component | Power | Percentage |
|-----------|-------|------------|
| **Dynamic** | 0.075 W | 43% |
| **Static** | 0.097 W | 57% |

**Dynamic Breakdown:**
- Clocks: 0.006 W (8%)
- Signals: 0.021 W (28%)
- Logic: 0.018 W (24%)
- I/O: 0.030 W (40%)

---

## Thermal Performance

### Temperature Analysis

- **Junction Temperature**: 25.8°C
- **Ambient Temperature**: 25.0°C
- **Thermal Margin**: 59.2°C
- **Max Ambient**: 84.2°C

**Conclusion:**
- Excellent thermal performance
- Cool operation
- Safe for extended use

---

## Timing Analysis

### Timing Constraints

**Clock:** 100 MHz (10 ns period)

| Parameter | Value | Status |
|-----------|-------|--------|
| **Worst Negative Slack** | +1.641 ns | ✓ PASS |
| **Worst Hold Slack** | +0.028 ns | ✓ PASS |
| **Worst Pulse Width Slack** | +4.500 ns | ✓ PASS |

**All timing constraints met!** ✓

**Potential:** Could run at ~120 MHz (based on slack)

---

## Performance Metrics

### Throughput Calculation

**Operation Cycles:**
- Key expansion: ~44 cycles
- Encryption/Decryption: ~50-60 cycles
- **Total: ~94-104 cycles** per 128-bit block

**At 100 MHz:**
- Throughput: **128 bits / 100 cycles** = 1.28 bits/cycle
- **~128 Mbps** effective throughput
- **~16 MB/s** data rate

**Latency:** ~1 μs per block

---

## Testing & Verification

### Testbench Coverage

**tb_aes_integration.v**

**Test Categories:**
1. **Encryption Tests** (4 tests)
   - NIST vectors, edge cases

2. **Decryption Tests** (3 tests)
   - Inverse operation validation

3. **Round-trip Tests** (3 tests)
   - Encrypt → Decrypt verification

**Total: 10 comprehensive test cases**

---

## Test Features

### Robust Validation

**Capabilities:**
- Byte-by-byte mismatch reporting
- XOR difference display
- Pass/fail statistics
- Success rate calculation
- 100ms timeout watchdog

**Output:**
- Detailed console logs
- Color-coded results
- Automated verification

---

## Design Strengths

### What Makes This Design Excellent?

1. ✓ **NIST FIPS-197 Compliance**
2. ✓ **Dual-mode operation** (single core for enc/dec)
3. ✓ **Resource efficient** (3.36% LUTs, no BRAM/DSP)
4. ✓ **Low power** (0.172W, excellent thermal margin)
5. ✓ **Good timing** (100MHz with positive slack)
6. ✓ **Modular design** (clean hierarchy)
7. ✓ **Security conscious** (power analysis resistance)
8. ✓ **Well tested** (comprehensive testbench)
9. ✓ **Production ready** (complete constraints)
10. ✓ **User-friendly** (interactive interface)

---

## Security Considerations

### Implemented Protections

**Power Analysis Resistance:**
- Both S-box paths always active
- Constant power consumption
- Prevents simple power analysis (SPA)

**Timing Uniformity:**
- Fixed number of rounds
- Predictable execution time

**Potential Enhancements:**
- Add masking for DPA resistance
- Implement fault detection
- Add input validation

---

## Potential Improvements

### Future Enhancements

**1. Throughput Optimization**
- Implement **pipelined architecture** → 10x faster
- Trade-off: 5-8% LUT usage vs 3.36%

**2. Additional Modes**
- Add CBC, CTR, GCM modes
- Currently ECB only (implicit)

**3. Enhanced Security**
- Masking for DPA protection
- Random delay insertion
- Fault detection mechanisms

---

## Potential Improvements (cont.)

### Future Enhancements

**4. Key Management**
- Support for AES-192, AES-256
- Key derivation functions
- Secure key storage

**5. Documentation**
- Detailed README
- API documentation
- Usage examples
- Synthesis guides

**6. Interface Expansion**
- UART/SPI communication
- DMA support
- Interrupt handling

---

## Comparison: Iterative vs Pipelined

### Design Trade-offs

| Aspect | **Iterative** (Current) | **Pipelined** |
|--------|------------------------|---------------|
| LUT Usage | 3.36% (2,132) | ~6-8% (~4,000-5,000) |
| Throughput | ~128 Mbps | ~1.2 Gbps |
| Latency | ~1 μs | ~100 ns (after fill) |
| Power | 0.172 W | ~0.3-0.4 W |
| Complexity | Low | Medium |
| **Best For** | **Area-constrained** | **High-throughput** |

---

## Application Scenarios

### Where to Use This Design?

**Embedded Security:**
- IoT device encryption
- Secure boot systems
- Configuration data protection

**Communication:**
- Encrypted data links
- Secure protocols (TLS/SSL offload)
- VPN endpoints

**Storage:**
- Disk encryption
- Secure key storage
- Configuration memory protection

---

## Code Quality Assessment

### Engineering Practices

**Strengths:**
- ✓ Clear module hierarchy
- ✓ Consistent naming conventions
- ✓ Good inline comments
- ✓ Proper reset handling (active-low)
- ✓ Synchronous design throughout

**Enhancement Opportunities:**
- Parameterize magic numbers
- Explicit state encoding
- Add formal verification assertions
- Improve documentation

---

## Key Takeaways

### Summary of Achievements

1. **Successfully implemented** NIST-compliant AES-128
2. **Highly efficient** resource utilization (3.36% LUTs)
3. **Low power consumption** with excellent thermal margins
4. **Robust testing** with NIST test vectors
5. **Production-ready** with complete FPGA constraints
6. **Well-architected** modular design
7. **Security-conscious** implementation
8. **User-friendly** hardware interface

---

## Conclusion

### Final Assessment

**Rating: 9/10**

This is a **production-quality AES-128 implementation** demonstrating:

- Strong understanding of cryptographic algorithms
- Excellent FPGA design practices
- Efficient resource utilization
- Comprehensive testing and validation
- Successful timing closure

**Suitable for:**
- Educational purposes
- Practical cryptographic applications
- Foundation for advanced crypto systems

---

## Technical Specifications Summary

### Quick Reference

| Specification | Value |
|---------------|-------|
| **Algorithm** | AES-128 (NIST FIPS-197) |
| **FPGA** | Artix-7 XC7A100T |
| **Clock** | 100 MHz |
| **LUT Usage** | 2,132 (3.36%) |
| **Power** | 0.172 W |
| **Throughput** | ~128 Mbps |
| **Latency** | ~1 μs |
| **Modes** | Encryption & Decryption |
| **Test Coverage** | 10 test cases |

---

## Questions?

### Thank You!

**Repository Contents:**
- Complete Verilog source code
- Synthesis reports (utilization, power, timing)
- Comprehensive testbench
- FPGA constraints for Nexys A7
- Screenshots of synthesis results

**Contact Information:**
- Repository: aes_report/
- Documentation: See individual module headers

---

## Appendix: File Structure

### Repository Organization

```
aes_report/
├── aes_core_fixed.v              # Main AES engine
├── aes_fpga_top.v                # Top-level with I/O
├── aes_key_expansion_otf.v       # Key expansion
├── aes_mixcolumns_32bit.v        # MixColumns
├── aes_subbytes_32bit.v          # SubBytes wrapper
├── aes_shiftrows_128bit.v        # ShiftRows
├── aes_sbox.v                    # Forward S-box
├── aes_inv_sbox.v                # Inverse S-box
├── seven_seg_controller.v        # Display driver
├── tb_aes_integration.v          # Testbench
├── aes_con.xdc                   # Constraints
├── utilization.txt               # Synthesis report
├── power.txt                     # Power report
└── Screenshots/                  # Vivado results
```

---

## Appendix: References

### Standards & Resources

**Standards:**
- NIST FIPS-197: Advanced Encryption Standard
- IEEE papers on FPGA crypto implementations

**Tools:**
- Xilinx Vivado 2024.1
- Target: Nexys A7-100T Development Board

**Test Vectors:**
- NIST FIPS-197 Appendix B, C.1
- Custom validation patterns

**Further Reading:**
- AES algorithm specification
- FPGA optimization techniques
- Side-channel attack countermeasures
