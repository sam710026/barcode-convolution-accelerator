#!/usr/bin/env python3
"""Run the unmodified official HW3 RTL tests and retain version-matched evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def source_hashes(model):
    paths = [ROOT / name for name in (
        "01_RTL/core.v", "01_RTL/rtl_01.f", "00_TESTBED/testbench.v",
        "sim/sram_512x8.v", "scripts/run_tests.py")]
    paths += sorted((ROOT / "00_TESTBED/PATTERNS").glob("*.dat"))
    result = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    result["selected_sram_model"] = hashlib.sha256(model.read_bytes()).hexdigest()
    return result


def run_command(command, cwd, log, timeout):
    started = time.monotonic()
    with log.open("w") as stream:
        process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Terminate only this runner-owned process group, including VCS children.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            code = "timeout"
    return {"command": command, "cwd": str(cwd), "returncode": code,
            "seconds": round(time.monotonic() - started, 3), "log": str(log)}


def check_log(text, case):
    errors = []
    if text.count("CONGRATULATION! ALL DATA PASS!") != 1:
        errors.append("Expected exactly one official PASS banner")
    if re.findall(r"Total SPEC Error:\s*(\d+)", text) != ["0"]:
        errors.append("Expected exactly one zero SPEC-error report")
    if re.search(r"\[FAIL\]|Wrong!|Error-\[|Fatal|FATAL|Segmentation fault", text):
        errors.append("Failure diagnostic in simulation log")
    cycles = None
    if case != "tb0":
        if re.findall(r"Result writes:\s*(\d+)", text) != ["4096"]:
            errors.append("Expected exactly 4096 result writes")
        values = re.findall(r"Execution cycles:\s*(\d+)", text)
        if len(values) != 1 or int(values[0]) <= 0:
            errors.append("Missing or invalid execution-cycle count")
        else:
            cycles = int(values[0])
    elif "Invalid configuration correctly rejected." not in text:
        errors.append("Missing invalid-configuration confirmation")
    return errors, cycles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", nargs="+", choices=[f"tb{i}" for i in range(7)],
                        default=[f"tb{i}" for i in range(7)])
    parser.add_argument("--period", type=float, default=2.28)
    parser.add_argument("--sram-model", type=Path, default=ROOT / "sim/sram_512x8.v",
                        help="Functional default, or path to your licensed macro model")
    parser.add_argument("--timeout", type=float, default=180)
    args = parser.parse_args()
    if not 0 < args.period < float("inf") or not 0 < args.timeout < float("inf"):
        parser.error("Period and timeout must be finite and positive")
    if not shutil.which("vcs"):
        parser.error("VCS not on PATH; load vcs/2025.06 first")
    model = args.sram_model.resolve()
    if not model.is_file():
        parser.error("SRAM model does not exist")
    parent = ROOT / ".build"
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-"), dir=parent))
    before = source_hashes(model)
    report = {"scope": "RTL simulation only; not lint, synthesis, STA, GLS or measured PPA",
              "period_ns": args.period, "sram_model": str(model),
              "started_utc": datetime.now(timezone.utc).isoformat(), "source_sha256": before, "cases": [], "pass": False}
    summary = output / "summary.json"

    def save():
        summary.write_text(json.dumps(report, indent=2) + "\n")

    save()
    print(f"Evidence: {output}", flush=True)
    for case in args.cases:
        directory = output / case
        directory.mkdir()
        executable = directory / "simv"
        compile_command = ["vcs", str(ROOT / "00_TESTBED/testbench.v"), str(model),
                           str(ROOT / "01_RTL/core.v"), "-full64",
                           "+v2k", "+notimingcheck", "-sverilog", f"+define+{case}",
                           f"+define+CYCLE={args.period}", "-top", "testbed",
                           f"-Mdir={directory / 'csrc'}", "-o", str(executable)]
        record = {"case": case, "pass": False}
        report["cases"].append(record)
        record["compile"] = run_command(compile_command, ROOT / "01_RTL", directory / "compile.log", args.timeout)
        if record["compile"]["returncode"] != 0 or not executable.is_file():
            record["errors"] = ["Compilation failed; inspect compile.log"]
        else:
            record["simulation"] = run_command([str(executable)], ROOT / "01_RTL", directory / "simulation.log", args.timeout)
            errors, cycles = check_log((directory / "simulation.log").read_text(errors="replace"), case)
            if record["simulation"]["returncode"] != 0:
                errors.append("Simulation process failed or exceeded wall-clock timeout")
            record.update({"errors": errors, "execution_cycles": cycles, "pass": not errors})
        save()
        print(f"{case}: {'PASS' if record['pass'] else 'FAIL'}; cycles={record.get('execution_cycles')}", flush=True)
        if not record["pass"]:
            break
    report["sources_unchanged_during_run"] = source_hashes(model) == before
    report["pass"] = (len(report["cases"]) == len(args.cases)
                      and all(c["pass"] for c in report["cases"])
                      and report["sources_unchanged_during_run"])
    save()
    print(f"Summary: {summary}", flush=True)
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
