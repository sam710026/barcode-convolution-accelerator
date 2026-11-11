# Project rules

- The main agent supervises changes, evidence review and verification. Delegate independent tasks when useful.
- Preserve the submitted archive's RTL and synthesis configuration unless a design change is requested.
- Attribute course specifications, testbench and patterns separately from implementation and portfolio additions.
- Match all performance claims to the tested source, workload and evidence status.
- Run `python3 scripts/check_project.py` after packaging or documentation changes.
- Run `python3 scripts/run_tests.py` after RTL or simulation-flow changes with licensed VCS available.
- Never commit proprietary SRAM/standard-cell libraries, EDA binaries, credentials or build trees.
- The functional SRAM model supports RTL testing only. It cannot establish macro timing or gate-level correctness.
