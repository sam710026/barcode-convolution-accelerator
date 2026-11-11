# Release evidence

Both fresh runs used VCS X-2025.06 at a simulated 2.28 ns period on
2026-11-12 Asia/Taipei. Each directory contains `summary.json` with commands,
source/model SHA256 values, exit statuses, elapsed wall times, per-case cycles,
checker outcomes and a before/after source-identity check.

- [functional/](functional/): public independent `sim/sram_512x8.v`.
- [licensed-model/](licensed-model/): course-provided licensed macro source,
  referenced by hash only. The macro source is not distributed.

`tb0`–`tb6` contain complete compile and simulation **log text**; executables
and generated compiler trees are excluded. Log copies and summaries replace
the original build-directory prefix with `<run>`, the repository prefix with
`<project>`, and the external macro path with `<licensed>/sram_512x8.v`.
Other local home paths are normalized to `<home>` if present. These are display
normalizations; result values, diagnostics and source hashes are unchanged.

The compile commands deliberately select the model explicitly and use
`+notimingcheck`. These results establish RTL public-pattern correctness only.
See [performance](../PERFORMANCE.md) for scope and remaining gaps.
