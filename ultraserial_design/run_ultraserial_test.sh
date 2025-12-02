#!/bin/bash
###################################################################################
# Ultra-Serial AES Test Script
# Compiles and runs testbench for byte-at-a-time AES core
###################################################################################

set -e

echo "========================================================================="
echo "Ultra-Serial AES-128 Core - Test Script"
echo "Architecture: 1 byte/cycle (single S-box)"
echo "Expected: ~300 LUTs, ~20-25mW @ 100MHz"
echo "========================================================================="

# Check if iverilog is installed
if ! command -v iverilog &> /dev/null; then
    echo "ERROR: iverilog not found!"
    echo ""
    echo "Please install iverilog:"
    echo "  Ubuntu/Debian: sudo apt-get install iverilog"
    echo "  macOS: brew install icarus-verilog"
    echo "  From source: https://github.com/steveicarus/iverilog"
    exit 1
fi

echo ""
echo "Found iverilog: $(which iverilog)"
echo "Version: $(iverilog -V 2>&1 | head -1)"
echo ""

# Compile
echo "========================================================================="
echo "Compiling ultra-serial AES design..."
echo "========================================================================="

iverilog -o sim_ultraserial -g2012 \
    tb_ultraserial.v \
    aes_core_ultraserial.v \
    aes_key_expansion_otf.v \
    aes_shiftrows_128bit.v \
    aes_mixcolumns_32bit.v \
    aes_sbox.v \
    aes_inv_sbox.v

if [ $? -eq 0 ]; then
    echo "✅ Compilation successful!"
else
    echo "❌ Compilation failed!"
    exit 1
fi

echo ""
echo "========================================================================="
echo "Running simulation..."
echo "========================================================================="

# Run simulation
vvp sim_ultraserial

echo ""
echo "========================================================================="
echo "Simulation complete!"
echo "========================================================================="

# Cleanup
rm -f sim_ultraserial

echo ""
echo "Expected Performance @ 100MHz:"
echo "  - LUT Usage: ~300 (vs ~600 for column-serial)"
echo "  - Power: ~20-25mW (vs ~41mW for column-serial)"
echo "  - Latency: ~2.5µs (vs ~2.0µs for column-serial)"
echo "  - Throughput: ~512 Mbps (vs ~640 Mbps for column-serial)"
echo ""
echo "Trade-off: 50% LUT savings and 40% power savings for 25% slower latency"
echo "========================================================================="
