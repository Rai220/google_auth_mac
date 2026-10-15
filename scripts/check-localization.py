#!/usr/bin/env python3
"""Validate translation coverage and interpolation without reading user data."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = root / 'Sources/AuthenticatorCore/Localization.swift'
quoted = r'"(?:[^"\\]|\\.)*"'
pairs = re.findall(r'^\s*(' + quoted + r'):\s*(' + quoted + r'),$', catalog.read_text(), re.M)
translations = {json.loads(key): json.loads(value) for key, value in pairs}
assert len(translations) == len(pairs), 'Duplicate localization key'
assert translations, 'Missing translation catalog'
for key, value in translations.items():
    assert value.strip(), f'Empty translation: {key}'
    assert sorted(re.findall(r'\{\d+\}', key)) == sorted(re.findall(r'\{\d+\}', value)), f'Placeholder mismatch: {key}'
used = set()
for path in (root / 'Sources').rglob('*.swift'):
    if path == catalog:
        continue
    used.update(json.loads(value) for value in re.findall(r'\btext\((' + quoted + r')', path.read_text()))
assert not used - translations.keys(), f'Missing translations: {sorted(used - translations.keys())}'
for language in ['en', 'ru']:
    assert 'NSCameraUsageDescription' in (root / f'Resources/{language}.lproj/InfoPlist.strings').read_text()
print(f'Localization: {len(used)} source strings covered; {len(translations)} translations and placeholders valid')
