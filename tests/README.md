# Test scope

Run from the repository root:

```bash
python3 scripts/check_project.py
python3 scripts/run_tests.py
```

The first command checks preserved assets, packaged source hashes, documentation
links and Python syntax. The second requires licensed VCS and compiles the
unmodified course testbench and exact submitted core separately for each case.

TB0 checks invalid-barcode rejection. TB1–TB6 cover every supported kernel/weight
precision combination and compare all 4096 image outputs, while checking
configuration and interface protocol. The runner requires one PASS banner,
zero SPEC errors, 4096 result writes for each valid case and a positive cycle
count. A nonzero exit, timeout or simulator failure diagnostic fails the run.
Sources are hashed before and after testing. Retained release evidence is linked
from [performance](../docs/PERFORMANCE.md).

`--cases tb0 tb6` selects a subset, `--period` changes the RTL clock period,
`--timeout` sets per-process wall time, and `--sram-model` selects a locally
licensed external macro model. Each run uses a new `.build/` directory; timeout
cleanup terminates only the process group started by the runner.

The public [functional SRAM model](../sim/sram_512x8.v) models synchronous
single-port read, write-through, active-low enables, output hold when disabled,
and uninitialized storage. It has no macro timing or notifier behavior and is
not a replacement for the licensed macro in synthesis or GLS. No `SYNTHESIS`
define or SDF is used in this regression; VCS timing checks are disabled for
the RTL run, including the optional licensed-model run.

These public patterns do not exhaust barcode origins, arbitrary weights/images,
reset interruption or hidden grading cases. Historical expanded-suite results
from other RTL versions are not assigned to this source. Lint, synthesis,
setup/hold STA and timed gate-level simulation are separate checks.
