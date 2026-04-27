#!/usr/bin/env python3
"""
rebind-workflow.py — Apply Operscale rebind transforms to a VG workflow JSON.

Per docs/adr/0008-fork-vision-gridai.md and the vg-workflow-rebind skill:
  1. Webhook node paths:     parameters.path "X" → "operscale/X"
                              (n8n stores webhook paths bare, not as /webhook/X;
                               structurally rebind every webhook-typed node)
  2. Workflow name prefix:   WF_X → OPS_X
  3. SQL FK rebind:          topic_id→video_id, topics→videos,
                              project_id→order_id, projects→orders
  4. Scratch path remap:     /tmp/production/ → /tmp/operscale-production/,
                              /data/n8n-production/ → /data/operscale-production/
  5. Authorization headers:  every value MUST start with "=" (gotcha #2)
  6. Inline credentials:     none allowed; must reference n8n credential by ID

Usage: python infra/scripts/rebind-workflow.py <input.json> <output.json>
       python infra/scripts/rebind-workflow.py --batch <input_dir> <output_dir>

Exits non-zero if any AUTH-01 or CRED-01 violation is detected.

Idempotent: every transform is a no-op when applied to already-rebound input.
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# ── Rebind transforms ─────────────────────────────────

WEBHOOK_NODE_TYPE = 'n8n-nodes-base.webhook'
WEBHOOK_PATH_NS = 'operscale/'

# Legacy text-replacement pattern kept for any stray `/webhook/...` URL strings
# embedded in text fields (notes, code-node bodies, etc). The structural pass
# below is what rebinds the actual webhook node `parameters.path` field.
WEBHOOK_PATH_REPLACEMENTS = [
    (re.compile(r'/webhook/(?!operscale/)'), '/webhook/operscale/'),
]

NAME_PREFIX_REPLACEMENTS = [
    (re.compile(r'^WF_'), 'OPS_'),
]

SQL_FK_REPLACEMENTS = [
    (re.compile(r'\btopic_id\b'),   'video_id'),
    (re.compile(r'\btopics\b'),     'videos'),
    (re.compile(r'\bproject_id\b'), 'order_id'),
    (re.compile(r'\bprojects\b'),   'orders'),
]

PATH_REPLACEMENTS = [
    ('/tmp/production/',           '/tmp/operscale-production/'),
    ('/data/n8n-production/',      '/data/operscale-production/'),
]

# ── Lint rules ────────────────────────────────────────

AUTH_HEADER_KEYS = {'authorization', 'Authorization'}

class LintFinding:
    def __init__(self, rule: str, node_name: str, detail: str):
        self.rule = rule
        self.node_name = node_name
        self.detail = detail

    def __str__(self):
        return f"  [{self.rule}] node='{self.node_name}': {self.detail}"


def transform_string(s: str) -> str:
    """Apply all string-level transforms to a value."""
    for pattern, replacement in WEBHOOK_PATH_REPLACEMENTS:
        s = pattern.sub(replacement, s)
    for pattern, replacement in SQL_FK_REPLACEMENTS:
        s = pattern.sub(replacement, s)
    for old, new in PATH_REPLACEMENTS:
        s = s.replace(old, new)
    return s


def transform_value(v: Any) -> Any:
    if isinstance(v, str):
        return transform_string(v)
    if isinstance(v, dict):
        return {k: transform_value(val) for k, val in v.items()}
    if isinstance(v, list):
        return [transform_value(item) for item in v]
    return v


def rebind_webhook_node_paths(workflow: dict) -> None:
    """Prefix every webhook node's `parameters.path` with `operscale/` if missing.

    n8n stores webhook paths bare (e.g. `production/tts`), not URL-prefixed.
    The structural pass here is what actually prevents webhook conflicts with
    VG's existing workflows on the shared n8n instance.

    Idempotent: paths already starting with `operscale/` are left alone.
    """
    nodes = workflow.get('nodes', []) if isinstance(workflow, dict) else []
    for node in nodes:
        if not isinstance(node, dict):
            continue
        if node.get('type') != WEBHOOK_NODE_TYPE:
            continue
        params = node.get('parameters')
        if not isinstance(params, dict):
            continue
        current = params.get('path')
        if isinstance(current, str) and current and not current.startswith(WEBHOOK_PATH_NS):
            params['path'] = WEBHOOK_PATH_NS + current.lstrip('/')


def rebind(workflow: dict) -> dict:
    """Apply rebind transforms; return new dict (original untouched)."""
    out = transform_value(workflow)
    # Rename top-level workflow name
    if isinstance(out, dict) and 'name' in out and isinstance(out['name'], str):
        for pattern, replacement in NAME_PREFIX_REPLACEMENTS:
            out['name'] = pattern.sub(replacement, out['name'])
    # Structural webhook-path rebind (n8n stores paths bare; regex on text doesn't catch)
    rebind_webhook_node_paths(out)
    return out


def lint(workflow: dict, source_name: str) -> list[LintFinding]:
    """Detect AUTH-01 and CRED-01 violations."""
    findings: list[LintFinding] = []

    nodes = workflow.get('nodes', [])
    for node in nodes:
        node_name = node.get('name', '<unnamed>')
        params = node.get('parameters') or {}

        # AUTH-01: every Authorization header value must start with '=' if it
        # contains an n8n expression-syntax substring like {{ $env.X }}.
        headers = (
            (params.get('headerParameters') or {}).get('parameters')
            or (params.get('headers') or {}).get('parameters')
            or []
        )
        for h in headers if isinstance(headers, list) else []:
            if not isinstance(h, dict):
                continue
            key = (h.get('name') or '').strip()
            value = h.get('value') or ''
            if key.lower() == 'authorization' and isinstance(value, str):
                has_expr = '{{' in value and '}}' in value
                if has_expr and not value.startswith('='):
                    findings.append(LintFinding(
                        'AUTH-01', node_name,
                        f"Authorization value contains expression but doesn't start with '=': {value[:80]}"
                    ))

        # CRED-01: no inline API keys / secrets in node params.
        # Heuristic: look for raw key-shaped strings outside the credentials object.
        as_str = json.dumps(params)
        # Common API-key patterns
        if re.search(r'sk-[A-Za-z0-9_-]{20,}', as_str):
            findings.append(LintFinding(
                'CRED-01', node_name,
                "Inline OpenAI/Anthropic-shaped key detected (sk-…). Move to n8n credentials."
            ))
        if re.search(r'pk_(test|live)_[A-Za-z0-9]{20,}', as_str):
            findings.append(LintFinding(
                'CRED-01', node_name,
                "Inline Paystack-shaped key detected (pk_…). Move to n8n credentials."
            ))

    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--batch', action='store_true', help='Process all *.json in a directory')
    ap.add_argument('--lint-only', action='store_true', help='Lint without writing output')
    ap.add_argument('input', help='Input file or directory')
    ap.add_argument('output', nargs='?', help='Output file or directory')
    args = ap.parse_args()

    files: list[tuple[Path, Path]] = []
    in_path = Path(args.input)
    if args.batch:
        if not args.lint_only and not args.output:
            ap.error('--batch requires an output directory unless --lint-only is set')
        out_path = Path(args.output) if args.output else None
        for src in sorted(in_path.glob('*.json')):
            if out_path:
                # WF_X.json → OPS_X.json
                dst_name = re.sub(r'^WF_', 'OPS_', src.name)
                files.append((src, out_path / dst_name))
            else:
                files.append((src, src))
    else:
        if not args.lint_only and not args.output:
            ap.error('output required unless --lint-only')
        files.append((in_path, Path(args.output) if args.output else in_path))

    total_findings = 0
    for src, dst in files:
        with src.open() as f:
            wf = json.load(f)

        if not args.lint_only:
            wf = rebind(wf)

        findings = lint(wf, src.name)
        if findings:
            print(f"FAIL {src.name} -- {len(findings)} finding(s):")
            for fnd in findings:
                print(fnd)
            total_findings += len(findings)
        else:
            print(f"PASS {src.name}")

        if not args.lint_only:
            dst.parent.mkdir(parents=True, exist_ok=True)
            with dst.open('w') as f:
                json.dump(wf, f, indent=2)

    print(f"\nTotal findings: {total_findings}")
    return 1 if total_findings > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
