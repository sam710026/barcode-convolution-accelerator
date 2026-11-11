# Provenance and source preservation

This repository presents the submitted implementation by
[sam710026](https://github.com/sam710026) for NTU Graduate Institute of Electronics
Engineering, Computer-Aided VLSI System Design, Fall 2026, Homework 3:
*Single-Channel Convolution with Barcode Decoding Engine*.

## Exact submission

The requested `1151_hw3/cvsd_hw3_v3.tar` was inspected and extracted into a
separate workspace after rejecting absolute/parent-traversal paths and links.
The archive's seven files are copied byte-for-byte into this repository,
preserving the `01_RTL`, `02_SYN`, `03_GATE` and `report.txt` layout.
The original folder and archive remain untouched.

[ORIGINAL_SOURCES.json](ORIGINAL_SOURCES.json) maps all **43 preserved assets**
to original names and SHA256 values, including the archive's hash. In addition
to the seven submission files, these comprise the adjacent official testbench,
33 pattern/image files, the assignment PDF and the TA-note PDF. The testbench
hash was checked against its copy inside the official starter archive
`1151_hw3_v1.tar`; they match.

| Original document | Repository location |
| --- | --- |
| `1151_hw3_v1.pdf` | [docs/spec/assignment.pdf](spec/assignment.pdf) |
| `1151_hw3_note_v1.pdf` | [docs/spec/ta_notes.pdf](spec/ta_notes.pdf) |

Specifications, TA notes, testbench, patterns and starter synthesis/filelist
material are course-provided assets. They are attributed to the course and
retain existing authorship information. This repository does not claim their
authorship or assign a blanket open-source license to them.

## Portfolio additions and external dependencies

README, project rules, architecture/performance/provenance documents,
test-scope notes, Python helpers and the functional SRAM model were added for
this portfolio. The functional model was independently written from the
synchronous read/write interface contract; it contains no licensed macro
implementation, characterization data, physical layout or timing checks.

The original filelists and synthesis scripts still refer to the course
environment. Proprietary Artisan SRAM Verilog, Liberty/database views,
standard-cell models, EDA tools, license configuration, mapped netlists/SDFs,
archives and generated executables are not distributed. Synthesis requires
access to the licensed libraries, including `ADDFX1` and `DFFHQX8`.

The submitted core is a complete assembled Verilog file. Its comments mention
`rtl_parts`, `tools/assemble_core.py` and `tools/generate_fused_heap.py`; those
development inputs were not part of the requested seven-file archive and
are not reconstructed here. Historical working-tree experiments are not
substituted for this submission.

[SOURCES.sha256](SOURCES.sha256) covers the preserved inputs and execution
helpers. `python3 scripts/check_project.py` validates these and local Markdown
links. Fresh source-hashed logs are retained under [evidence](evidence/).
Published log copies replace local project/home/build prefixes with symbolic
paths; outcomes, cycle counts and hashes are unchanged. The original raw logs
remain in the ignored local build directories.

## Performance attribution

The archived report is the source of the 571937.564082 µm² area and 2.28 ns
operating-period claim. Exact-hash historical public RTL logs were located in
the nearby `hw3_c3facap8_candidate_20261110` development folder; they agree with
the fresh regression's six cycle counts. No matching raw area/STA/GLS evidence
was found in the inspected nearby project/candidate records.

Fresh portfolio runs establish the public functional results and cycle counts
using both the independent model and a locally licensed macro model. They are
RTL simulations with timing checks disabled. [PERFORMANCE.md](PERFORMANCE.md)
separates those results from report-only physical metrics and checks not run.
