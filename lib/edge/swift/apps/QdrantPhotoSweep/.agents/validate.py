#!/usr/bin/env python3
"""Validate instruction artifacts, not application behavior or editor ingestion."""
from pathlib import Path
import math
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent.parent
LINKS = {
    'AGENTS.md': '.agents/AGENTS.md',
    '.claude/CLAUDE.md': '../.agents/AGENTS.md',
    '.cursor/rules': '../.agents/adapters/cursor',
}


def check(root):
    root = root.resolve()
    for alias, target in LINKS.items():
        path = root / alias
        assert path.is_symlink(), f'Not a symlink: {alias}'
        assert str(path.readlink()) == target, f'Unexpected target: {alias}'
        resolved = path.resolve(strict=True)
        assert resolved.is_relative_to(root), f'Link escapes project: {alias}'
    entry = (root / '.agents/AGENTS.md').read_text()
    assert (root / 'AGENTS.md').read_text() == entry
    assert (root / '.claude/CLAUDE.md').read_text() == entry
    assert math.ceil(len(entry) / 4) <= 1000, 'Shared entry exceeds approximate token budget'
    assert not (root / '.claude/rules').exists(), 'Unexpected eager Claude rule corpus'
    seen = set()
    table = (root / '.agents/requirements.md').read_text()
    mapped = re.findall(r'^\| ([A-Z]+-\d+) \|', table, re.M)
    assert len(mapped) == len(set(mapped)), 'Duplicate requirement-map ID'
    for rule in sorted((root / '.agents/rules').glob('*.md')):
        ids = re.findall(r'^## ([A-Z]+-\d+) \(([CTV])\)', rule.read_text(), re.M)
        assert ids, f'Rule lacks requirements: {rule.name}'
        for rid, kind in ids:
            assert rid not in seen, f'Duplicate canonical owner: {rid}'
            seen.add(rid)
            row = next((line for line in table.splitlines() if line.startswith(f'| {rid} |')), '')
            assert f'| {kind} |' in row and f'(rules/{rule.name})' in row, f'Wrong mapping: {rid}'
        assert f'.agents/rules/{rule.name}' in entry, f'Rule missing routing: {rule.name}'
        wrapper = root / '.cursor/rules' / (rule.stem + '.mdc')
        text = wrapper.read_text()
        assert text.startswith('---\nalwaysApply: false\n---\n'), f'Invalid manual wrapper: {wrapper}'
        assert f'.agents/rules/{rule.name}' in text
        assert 'globs:' not in text and 'description:' not in text, 'Wrapper should be manual'
    assert seen == set(mapped), 'Missing/orphaned requirements'
    for q in range(1, 17):
        assert f'| Q{q} |' in table, f'Decision Q{q} not audited'
    for doc in (root / '.agents').rglob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)', doc.read_text()):
            if '://' in target:
                continue
            assert (doc.parent / target.split('#')[0]).exists(), f'Broken link: {doc}: {target}'
    return len(seen)


def main():
    count = check(ROOT)
    with tempfile.TemporaryDirectory(prefix='photosweep-agent-check-') as temp:
        relocated = Path(temp)
        for name in ('.agents', '.claude', '.cursor'):
            shutil.copytree(ROOT / name, relocated / name, symlinks=True,
                            ignore=shutil.ignore_patterns('__pycache__'))
        (relocated / 'AGENTS.md').symlink_to(LINKS['AGENTS.md'])
        assert check(relocated) == count
    print(f'PASS: {count} unique requirements; 16 product decisions; links/wrappers/relocation valid.')
    print('Runtime instruction ingestion is not tested by this script.')
    print('| File | UTF-8 bytes | Words | Approx tokens (chars/4) |')
    print('| --- | --- | --- | --- |')
    for path in [ROOT / '.agents/AGENTS.md', *sorted((ROOT / '.agents/rules').glob('*.md'))]:
        text = path.read_text()
        print(f'| {path.relative_to(ROOT)} | {len(text.encode())} | {len(text.split())} | {math.ceil(len(text)/4)} |')


if __name__ == '__main__':
    main()
