#!/usr/bin/env python3
"""
lint_n8n_workflows.py — CI-friendly wrapper around rebind-workflow.py --lint-only.

Walks apps/n8n-workflows/operscale/, lints every *.json. Exits non-zero on
any finding. Designed to be wired into CI in the polish phase; in Foundation
it's run manually to confirm Day 2's rebind output is clean.

Usage: python tools/lint_n8n_workflows.py
"""
import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    target = repo_root / 'apps' / 'n8n-workflows' / 'operscale'
    if not target.exists():
        print(f"ERROR: {target} does not exist")
        return 1

    json_files = sorted(target.glob('*.json'))
    if not json_files:
        print(f"ERROR: No *.json found in {target}")
        return 1

    print(f"Linting {len(json_files)} workflow file(s) under {target}...")
    rebind_script = repo_root / 'infra' / 'scripts' / 'rebind-workflow.py'

    failures = 0
    for jf in json_files:
        result = subprocess.run(
            ['python3', str(rebind_script), '--lint-only', str(jf)],
            capture_output=True, text=True
        )
        sys.stdout.write(result.stdout)
        if result.returncode != 0:
            failures += 1

    print(f"\n{'=' * 60}")
    if failures == 0:
        print(f"PASS: All {len(json_files)} workflows lint-clean.")
        return 0
    else:
        print(f"FAIL: {failures} of {len(json_files)} workflows have lint findings.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
