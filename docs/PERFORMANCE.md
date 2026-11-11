# Performance and verification evidence

## Exact version

| Artifact | SHA256 |
| --- | --- |
| Requested `cvsd_hw3_v3.tar` | `a9a1707955f4a8fbb81e9ea58618cec3cd0c4e9598218d4f7a98a95c1eb9d9cd` |
| Submitted `01_RTL/core.v` | `09254f473499f56324db772e33025df77deeca484d2af1323059325f79878547` |

All numbers here refer to this source. Nearby working trees, earlier V3 bundles
and later experiments can contain different RTL despite similar names.

## Fresh public RTL regression

Run date: **2026-11-12 Asia/Taipei** (2026-11-11 UTC), VCS **X-2025.06**,
64-bit SystemVerilog, 2.28 ns simulated period, no SDF, timing checks disabled.
Source hashes before/after each run match. Both sets independently compiled
the exact core and unmodified official testbench with each TB define.

| Pattern | K / W | Public functional model | Locally licensed macro model | Execution cycles |
| --- | --- | --- | --- | ---: |
| TB0 | Invalid | PASS | PASS | Not reported by TB |
| TB1 | 3 / 4 | PASS | PASS | 1041 |
| TB2 | 3 / 8 | PASS | PASS | 1041 |
| TB3 | 4 / 4 | PASS | PASS | 1042 |
| TB4 | 4 / 8 | PASS | PASS | 2066 |
| TB5 | 5 / 4 | PASS | PASS | 1045 |
| TB6 | 5 / 8 | PASS | PASS | 2069 |

Each run passes 7/7 cases with zero SPEC errors and 24,576 output-pixel
comparisons across the six valid images. Running the same patterns against
two SRAM models checks functional-model compatibility on these workloads;
it does not expand stimulus coverage or establish gate timing.

Retained evidence:

- [Functional-model summary](evidence/functional/summary.json), plus
  `tb0`–`tb6/compile.log` and `simulation.log` in that directory.
- [Licensed-model summary](evidence/licensed-model/summary.json), with the
  same per-case log layout. The proprietary model is identified by hash and
  is **not included** in the repository.
- [Evidence inventory](evidence/README.md), including path normalization.

Reproduce the first run:

```bash
module load vcs/2025.06
python3 scripts/run_tests.py --period 2.28
```

For the second, add `--sram-model /path/to/your/licensed/sram_512x8.v`.
The helper compiles explicit paths so the original submission filelist can be
preserved without distributing the macro source. Build directories are isolated
and ignored by Git. Compile and simulation commands are recorded in each summary.

The official testbench starts its execution interval after image reception;
configuration/weight handling and pipeline overhead are reflected in its
cycle count. Image loading is excluded. The steady-state architecture delivers
four pixels per cycle in W4 and K3/W8, and four per two cycles in K4/W8 or
K5/W8; full-case counts include the remaining overhead.

## Archived performance report

The preserved [report.txt](../report.txt) records:

| Quantity | Value | Evidence status |
| --- | ---: | --- |
| Clock period | 2.28 ns | Submission-reported; also used for fresh **RTL** runs |
| Area | 571937.564082 µm² | Submission-reported; raw synthesis area report unavailable |
| TB1–TB6 cycles | 1041 / 1041 / 1042 / 2066 / 1045 / 2069 | Independently reproduced in both fresh RTL runs |
| Synthesis SDC period | 2.36 ns | Directly inspected in preserved `core_dc.sdc` |

The assignment defines `PA = Area × total execution time(TB1, TB2, TB3, TB5)`
with image loading excluded (assignment p. 10; TA notes p. 34). For the reported
values:

```text
Scored cycle sum = 1041 + 1041 + 1042 + 1045 = 4169
Scored time      = 4169 × 2.28 = 9505.32 ns
Reported PA      = 571937.564082 × 9505.32
                 = 5436449566.61991624 µm²·ns
```

This is arithmetic derived from the archived report, not a newly measured or
fully qualified course score. The course requires all patterns, nonnegative
setup slack and post-reset timed-GLS correctness for performance eligibility.
The 2.36 ns synthesis constraint and 2.28 ns reported operating period are kept
separate; no matching raw timing/GLS evidence is inferred from that difference.

## Verification limits

| Check | Status for this portfolio |
| --- | --- |
| Archive extraction, source identity and preservation | PASS |
| Official public RTL patterns, functional model | PASS, 7/7 |
| Official public RTL patterns, supplied licensed macro model | PASS, 7/7 |
| New hidden-style/random/reset-interruption regression | Not run |
| SpyGlass lint | Not run; no matching raw result supplied |
| Fresh synthesis / mapped area | Not run; report-only area retained |
| Setup/hold STA, recovery/removal, unconstrained-path audit | Not established by supplied evidence |
| SDF-annotated gate-level simulation | Not run; no matching netlist/SDF/logs supplied |
| Silicon measurement or power | Not supplied |

No production RTL was changed. Functional public correctness is supported by
the logs; physical signoff and hidden-test coverage remain separate work.
