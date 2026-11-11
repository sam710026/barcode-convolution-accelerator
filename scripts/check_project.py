#!/usr/bin/env python3
"""Check original asset identity, local links and project source checksums."""
import ast
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    original = json.loads((ROOT / 'docs/ORIGINAL_SOURCES.json').read_text())['files']
    for name, item in original.items():
        path = ROOT / item['path']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise RuntimeError(f'Original file changed or missing: {name}')
    count = 0
    for line in (ROOT / 'docs/SOURCES.sha256').read_text().splitlines():
        digest, relative = line.split('  ', 1)
        path = ROOT / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Packaged source changed or missing: {relative}')
        count += 1
    links = 0
    for p in ROOT.rglob('*.md'):
        if '.git' in p.parts or '.build' in p.parts:
            continue
        for target in re.findall(r'\]\(([^)]+)\)', p.read_text()):
            target = target.strip('<>').split('#', 1)[0]
            if not target or '://' in target or target.startswith('mailto:'):
                continue
            if not (p.parent / target).exists():
                raise RuntimeError(f'Broken link: {p.relative_to(ROOT)} -> {target}')
            links += 1
    for p in (ROOT / 'scripts').glob('*.py'):
        ast.parse(p.read_text())
    for name in ['README.md', 'AGENTS.md', 'docs/ARCHITECTURE.md', 'docs/PERFORMANCE.md', 'docs/PROVENANCE.md']:
        if not (ROOT / name).is_file():
            raise RuntimeError(f'Missing project document: {name}')
    print(f'PASS: {len(original)} original assets, {count} source hashes, {links} documentation links, Python syntax.')


if __name__ == '__main__':
    main()
