# AES FPGA Implementation - Technical Report

## Report Overview

This repository contains a comprehensive technical report on the **Resource-Optimized AES-128 Encryption/Decryption Implementation on FPGA**.

## Files

- **AES_FPGA_Report.tex** - Main LaTeX report (1374 lines)
- **AES_FPGA_Presentation.md** - Presentation slides (35+ slides)

## Report Sections

1. **Problem Statement** - Detailed analysis of challenges in AES FPGA implementation
2. **Literature Survey** - Review of 7 recent IEEE papers (2020-2025)
3. **Proposed Methodology** - Complete architecture with TikZ diagrams
4. **Comparison Analysis** - Comprehensive tables comparing with state-of-the-art
5. **Simulation & Synthesis Results** - Full verification and performance metrics
6. **Conclusion & Future Work** - Summary and research directions
7. **References** - 14 IEEE-style citations

## How to Compile the LaTeX Report

### Method 1: Using pdflatex (Recommended)

```bash
# Compile once
pdflatex AES_FPGA_Report.tex

# Compile for references (run 2-3 times)
pdflatex AES_FPGA_Report.tex
pdflatex AES_FPGA_Report.tex
```

### Method 2: Using latexmk (Automated)

```bash
latexmk -pdf AES_FPGA_Report.tex
```

### Method 3: Using Overleaf

1. Go to [Overleaf](https://www.overleaf.com/)
2. Create new project → Upload Project
3. Upload `AES_FPGA_Report.tex`
4. Compile automatically

### Required LaTeX Packages

The report uses the following packages (usually included in standard LaTeX distributions):

- `graphicx` - For graphics support
- `amsmath, amssymb` - Mathematical symbols
- `booktabs` - Professional tables
- `tikz` - Diagrams and figures
- `algorithm, algorithmic` - Algorithms
- `hyperref` - Hyperlinks
- `listings` - Code listings
- `xcolor` - Colors

### Installing LaTeX

**Ubuntu/Debian:**
```bash
sudo apt-get install texlive-full
```

**macOS:**
```bash
brew install --cask mactex
```

**Windows:**
- Download and install [MiKTeX](https://miktex.org/) or [TeX Live](https://www.tug.org/texlive/)

## Report Highlights

### Key Statistics

- **Total Pages:** ~35-40 pages (when compiled)
- **Figures:** Multiple TikZ diagrams (architecture, FSM, etc.)
- **Tables:** 15+ comprehensive comparison and results tables
- **References:** 14 IEEE-style citations
- **Sections:** 6 major sections with subsections

### Literature Survey Coverage

The report reviews papers from:
- IEEE Transactions on Consumer Electronics
- IEEE Transactions on VLSI Systems
- IEEE Access
- IEEE Conference Publications
- Focus: 2020-2025 publications

### Technical Content

- **Resource Utilization:** 3.36% LUTs, 0 BRAM/DSP
- **Power Consumption:** 0.172W total
- **Timing:** 100 MHz with +1.641ns slack
- **Verification:** 100% pass rate on NIST test vectors

## Converting to Other Formats

### PDF to Word (if needed)

```bash
# Using pdf2docx (Python)
pip install pdf2docx
pdf2docx AES_FPGA_Report.pdf AES_FPGA_Report.docx
```

### LaTeX to Word (direct)

```bash
# Using pandoc
pandoc AES_FPGA_Report.tex -o AES_FPGA_Report.docx
```

## Troubleshooting

### Missing Packages Error

If you get "Package not found" errors:

```bash
# Ubuntu/Debian
sudo apt-get install texlive-latex-extra texlive-science

# Or use tlmgr
tlmgr install <package-name>
```

### TikZ Diagrams Not Rendering

Ensure you have:
```bash
sudo apt-get install texlive-pictures
```

### Bibliography Issues

Run the complete compile sequence:
```bash
pdflatex AES_FPGA_Report.tex
bibtex AES_FPGA_Report
pdflatex AES_FPGA_Report.tex
pdflatex AES_FPGA_Report.tex
```

## Repository Structure

```
aes_report/
├── AES_FPGA_Report.tex          # Main technical report
├── AES_FPGA_Presentation.md     # Presentation slides
├── aes_core_fixed.v             # Main AES core
├── aes_fpga_top.v               # Top-level module
├── aes_key_expansion_otf.v      # Key expansion
├── aes_mixcolumns_32bit.v       # MixColumns
├── aes_subbytes_32bit.v         # SubBytes
├── aes_shiftrows_128bit.v       # ShiftRows
├── aes_sbox.v                   # Forward S-box
├── aes_inv_sbox.v               # Inverse S-box
├── seven_seg_controller.v       # Display controller
├── tb_aes_integration.v         # Testbench
├── aes_con.xdc                  # FPGA constraints
├── utilization.txt              # Synthesis report
├── power.txt                    # Power analysis
└── Screenshots/                 # Vivado results
```

## Citation

If you use this work, please cite:

```
Resource-Optimized AES-128 Encryption/Decryption Implementation on FPGA
Department of Electronics and Communication Engineering
2025
```

## Contact

For questions or issues with the report, please open an issue in the repository.

## License

This documentation and code are provided for educational and research purposes.
