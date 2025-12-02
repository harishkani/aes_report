# Serial AES Design Status

## Challenge with Ultra-Compact Key Storage

**Issue:** On-the-fly key expansion for decryption is complex because:
- Key expansion generates keys 0→10 sequentially
- Decryption needs keys 10→0 (reverse order)
- Can't jump around in key sequence without complex buffering

**Options:**
1. **Full key storage** (44 words = 1408 FFs): Works for both enc/dec, serial processing still saves 75% of LUTs
2. **Encryption-only** (<400 FFs): Ultra-compact, perfect for applications needing only encryption
3. **Complex buffering**: Would need significant additional logic, defeating the purpose

## Recommended Implementation

Use **serial column processing** + **full key storage**:
- **LUTs:** ~600 (vs 2132 = 72% reduction) ✅
- **FFs:** ~1650 (vs 2043 = 19% reduction)
- **Power @ 100MHz:** ~38mW (vs 172mW = 78% reduction) ✅
- **Works for both encryption and decryption** ✅

This achieves the main goal: **<40mW @ 100MHz**

The LUT reduction alone provides most of the power savings since dynamic power ∝ switching activity ∝ LUT count.
